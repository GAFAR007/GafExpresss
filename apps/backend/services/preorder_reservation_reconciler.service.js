/**
 * apps/backend/services/preorder_reservation_reconciler.service.js
 * ----------------------------------------------------------------
 * WHAT:
 * - Reconciles expired pre-order reservations into released product capacity.
 *
 * WHY:
 * - TTL deletion alone cannot decrement reserved counters, so capacity would drift.
 * - Reconciliation keeps Product.preorderReservedQuantity aligned with active holds.
 *
 * HOW:
 * - Finds still-reserved holds that are past expiresAt.
 * - Processes each hold in a transaction so status + counter move together.
 * - Marks reservation as expired with expiredAt for auditability.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const Product = require("../models/Product");
const ProductionPlan = require("../models/ProductionPlan");
const PreorderReservation = require("../models/PreorderReservation");

const PREORDER_RECONCILE_DEFAULT_LIMIT =
  500;
const PREORDER_RECONCILE_STATUS_RESERVED =
  "reserved";
const PREORDER_RECONCILE_STATUS_EXPIRED =
  "expired";
const PREORDER_RECONCILE_ERROR_CODE =
  "PREORDER_RECONCILE_FAILED";

function normalizeReconcileDate(nowInput) {
  const nowValue =
    nowInput instanceof Date ?
      nowInput
    : new Date(nowInput || Date.now());
  if (Number.isNaN(nowValue.getTime())) {
    throw new Error(
      "Invalid reconciliation date",
    );
  }
  return nowValue;
}

function normalizeReconcileLimit(limitInput) {
  const parsedLimit = Number(limitInput);
  if (
    !Number.isFinite(parsedLimit) ||
    parsedLimit <= 0
  ) {
    return PREORDER_RECONCILE_DEFAULT_LIMIT;
  }
  return Math.floor(parsedLimit);
}

async function reconcileExpiredPreorderReservations(
  {
    businessId = null,
    now = new Date(),
    limit = PREORDER_RECONCILE_DEFAULT_LIMIT,
  } = {},
) {
  const normalizedNow =
    normalizeReconcileDate(now);
  const normalizedLimit =
    normalizeReconcileLimit(limit);

  const candidateFilter = {
    status:
      PREORDER_RECONCILE_STATUS_RESERVED,
    expiresAt: { $lt: normalizedNow },
  };
  if (businessId) {
    // WHY: Tenant scope keeps one business from touching another's holds.
    candidateFilter.businessId = businessId;
  }

  debug(
    "PREORDER RECONCILER: start",
    {
      businessId:
        businessId ?
          businessId.toString()
        : null,
      now: normalizedNow.toISOString(),
      limit: normalizedLimit,
      intent:
        "release expired reservation capacity into preorder counters",
    },
  );

  const candidates =
    await PreorderReservation.find(
      candidateFilter,
    )
      .sort({ expiresAt: 1, _id: 1 })
      .limit(normalizedLimit)
      .select({
        _id: 1,
        planId: 1,
        businessId: 1,
        quantity: 1,
      })
      .lean();

  const summary = {
    businessId:
      businessId ?
        businessId.toString()
      : null,
    now: normalizedNow.toISOString(),
    scannedCount: candidates.length,
    expiredCount: 0,
    skippedCount: 0,
    errorCount: 0,
    processedReservationIds: [],
    skippedReservationIds: [],
    errors: [],
  };

  debug(
    "PREORDER RECONCILER: candidates loaded",
    {
      businessId:
        summary.businessId,
      scannedCount:
        summary.scannedCount,
      reservationIds:
        candidates.map((entry) =>
          entry._id.toString(),
        ),
    },
  );

  for (const candidate of candidates) {
    const reservationId =
      candidate._id.toString();
    let session;
    try {
      session =
        await mongoose.startSession();

      let transactionResult = null;
      await session.withTransaction(
        async () => {
          // WHY: State transition is inside transaction so idempotency is guaranteed.
          const reservation =
            await PreorderReservation.findOneAndUpdate(
              {
                _id: candidate._id,
                status:
                  PREORDER_RECONCILE_STATUS_RESERVED,
                expiresAt: {
                  $lt: normalizedNow,
                },
              },
              {
                $set: {
                  status:
                    PREORDER_RECONCILE_STATUS_EXPIRED,
                  expiredAt: normalizedNow,
                },
              },
              {
                new: false,
                session,
              },
            );

          if (!reservation) {
            transactionResult = {
              skipped: true,
              reason:
                "ALREADY_RECONCILED_OR_NOT_EXPIRED",
            };
            return;
          }

          const plan =
            await ProductionPlan.findOne({
              _id: reservation.planId,
              businessId:
                reservation.businessId,
            })
              .select({ productId: 1 })
              .session(session)
              .lean();
          if (!plan?.productId) {
            throw new Error(
              "Missing product link for expired reservation",
            );
          }

          const productBefore =
            await Product.findOne({
              _id: plan.productId,
              businessId:
                reservation.businessId,
            })
              .select({
                preorderReservedQuantity: 1,
              })
              .session(session)
              .lean();
          if (!productBefore) {
            throw new Error(
              "Product not found for expired reservation",
            );
          }

          const beforeReserved = Number(
            productBefore.preorderReservedQuantity ||
              0,
          );
          const decrementBy = Math.min(
            beforeReserved,
            Number(
              reservation.quantity || 0,
            ),
          );

          // WHY: Bounded decrement + transaction keeps counter non-negative and atomic.
          const productAfter =
            await Product.findOneAndUpdate(
              {
                _id: plan.productId,
                businessId:
                  reservation.businessId,
              },
              {
                $inc: {
                  preorderReservedQuantity:
                    -decrementBy,
                },
              },
              {
                new: true,
                session,
              },
            )
              .select({
                preorderReservedQuantity: 1,
              })
              .lean();

          if (!productAfter) {
            throw new Error(
              "Unable to decrement reserved capacity for expired reservation",
            );
          }

          transactionResult = {
            skipped: false,
            businessId:
              reservation.businessId.toString(),
            planId:
              reservation.planId.toString(),
            quantity: Number(
              reservation.quantity || 0,
            ),
            beforeReserved,
            afterReserved: Number(
              productAfter.preorderReservedQuantity ||
                0,
            ),
          };
        },
      );

      if (transactionResult?.skipped) {
        summary.skippedCount += 1;
        summary.skippedReservationIds.push(
          reservationId,
        );
        debug(
          "PREORDER RECONCILER: reservation skipped",
          {
            reservationId,
            reason:
              transactionResult.reason,
          },
        );
        continue;
      }

      summary.expiredCount += 1;
      summary.processedReservationIds.push(
        reservationId,
      );
      debug(
        "PREORDER RECONCILER: reservation reconciled",
        {
          reservationId,
          businessId:
            transactionResult?.businessId,
          planId:
            transactionResult?.planId,
          quantity:
            transactionResult?.quantity,
          reservedBefore:
            transactionResult?.beforeReserved,
          reservedAfter:
            transactionResult?.afterReserved,
        },
      );
    } catch (error) {
      summary.errorCount += 1;
      summary.errors.push({
        reservationId,
        errorCode:
          PREORDER_RECONCILE_ERROR_CODE,
        message: error.message,
      });
      debug(
        "PREORDER RECONCILER: reservation failed",
        {
          reservationId,
          errorCode:
            PREORDER_RECONCILE_ERROR_CODE,
          reason: error.message,
          next: "Inspect reservation linkage and retry reconciliation",
        },
      );
    } finally {
      if (session) {
        await session.endSession();
      }
    }
  }

  debug(
    "PREORDER RECONCILER: complete",
    {
      businessId:
        summary.businessId,
      scannedCount:
        summary.scannedCount,
      expiredCount:
        summary.expiredCount,
      skippedCount:
        summary.skippedCount,
      errorCount:
        summary.errorCount,
      processedReservationIds:
        summary.processedReservationIds,
    },
  );

  return summary;
}

module.exports = {
  PREORDER_RECONCILE_DEFAULT_LIMIT,
  reconcileExpiredPreorderReservations,
};
