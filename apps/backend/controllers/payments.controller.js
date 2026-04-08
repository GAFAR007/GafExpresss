/**
 * controllers/payments.controller.js
 * ----------------------------------
 * WHAT:
 * - HTTP controller for payment-related endpoints.
 *
 * WHY:
 * - Keeps routes thin and consistent.
 * - Central place for request validation + responses.
 *
 * HOW:
 * - Validates input, then delegates to Paystack service.
 */

const debug = require("../utils/debug");
const mongoose = require("mongoose");
const paystackService = require("../services/paystack.service");
const Payment = require("../models/Payment");
const Order = require("../models/Order");
const PreorderReservation = require("../models/PreorderReservation");
const User = require("../models/User");
const paymentService = require("../services/payment.service");

/**
 * POST /payments/paystack/init
 *
 * Starts a Paystack transaction for an order.
 */
async function initPaystack(req, res) {
  debug(
    "PAYMENTS CONTROLLER: initPaystack - entry",
  );

  try {
    const { orderId, callbackUrl } =
      req.body || {};
    const userId = req.user?.sub;

    // WHY: Avoid ambiguous errors by validating required fields.
    if (!orderId) {
      debug(
        "PAYMENTS CONTROLLER: Missing orderId",
      );
      return res
        .status(400)
        .json({
          error: "orderId is required",
        });
    }
    if (!userId) {
      debug(
        "PAYMENTS CONTROLLER: Missing userId on request",
      );
      return res
        .status(401)
        .json({
          error: "Unauthorized",
        });
    }

    debug(
      "PAYMENTS CONTROLLER: initPaystack request validated",
      {
        orderId,
      },
    );

    const result =
      await paystackService.initPaystackTransaction(
        {
          orderId,
          userId,
          callbackUrl,
        },
      );

    debug(
      "PAYMENTS CONTROLLER: initPaystack success",
    );

    return res.status(200).json({
      message: "Paystack init success",
      data: {
        authorization_url:
          result.authorizationUrl,
        reference: result.reference,
        access_code: result.accessCode,
      },
    });
  } catch (err) {
    debug(
      "PAYMENTS CONTROLLER: initPaystack failed",
      err.message,
    );
    return res.status(400).json({
      error:
        err.message ||
        "Paystack init failed",
    });
  }
}

module.exports = {
  initPaystack,
  verifyPaystack,
};

/**
 * GET /payments/paystack/verify
 *
 * Verifies a Paystack reference and applies side-effects safely.
 */
async function verifyPaystack(
  req,
  res,
) {
  debug(
    "PAYMENTS CONTROLLER: verifyPaystack - entry",
  );

  try {
    const reference =
      req.query?.reference
        ?.toString()
        .trim();
    const userId = req.user?.sub;

    if (!reference) {
      debug(
        "PAYMENTS CONTROLLER: verifyPaystack missing reference",
        {
          classification:
            "MISSING_REQUIRED_FIELD",
          error_code:
            "PAYSTACK_VERIFY_REFERENCE_MISSING",
          step: "VALIDATION_FAIL",
          resolution_hint:
            "Provide ?reference= in the query string.",
        },
      );
      return res
        .status(400)
        .json({
          error:
            "reference is required",
        });
    }
    if (!userId) {
      debug(
        "PAYMENTS CONTROLLER: verifyPaystack missing user",
        {
          classification:
            "AUTHENTICATION_ERROR",
          error_code:
            "PAYSTACK_VERIFY_MISSING_USER",
          step: "AUTH_FAIL",
          resolution_hint:
            "Sign in again and retry.",
        },
      );
      return res
        .status(401)
        .json({
          error: "Unauthorized",
        });
    }

    const actor =
      await User.findById(
        userId,
      ).lean();
    if (!actor) {
      debug(
        "PAYMENTS CONTROLLER: verifyPaystack actor missing",
        {
          classification:
            "AUTHENTICATION_ERROR",
          error_code:
            "PAYSTACK_VERIFY_ACTOR_NOT_FOUND",
          step: "AUTH_FAIL",
          resolution_hint:
            "Sign in again and retry.",
        },
      );
      return res
        .status(401)
        .json({
          error: "Unauthorized",
        });
    }

    const isBusinessRole =
      actor.role === "business_owner" ||
      actor.role === "staff";
    const isAdmin =
      actor.role === "admin";
    const payment =
      await Payment.findOne({
        provider: "paystack",
        reference,
      }).lean();
    let accessAuthorized = false;

    if (payment) {
      const isOwnerOfPayment =
        payment.user?.toString() ===
        userId.toString();
      const isBusinessScopeMatch =
        actor.businessId &&
        payment.businessId &&
        actor.businessId.toString() ===
          payment.businessId.toString();
      const isAdminScopeMatch =
        isAdmin && isBusinessScopeMatch;

      if (isAdmin) {
        debug(
          "PAYMENTS CONTROLLER: verifyPaystack admin access evaluated (scope-enforced)",
          {
            referenceSuffix:
              reference.slice(-6),
            scopeMatch:
              isBusinessScopeMatch,
          },
        );
      }

      accessAuthorized =
        isAdminScopeMatch ||
        isOwnerOfPayment ||
        (isBusinessRole &&
          isBusinessScopeMatch);
    } else {
      // WHY: Redirect flow can hit verify before webhook creates local Payment row.
      // Use provider metadata preview to authorize safely before applying changes.
      const verificationPreview =
        await paystackService.verifyPaystackTransaction(
          {
            reference,
          },
        );
      const previewMetadata =
        verificationPreview
          ?.metadata || {};
      const previewOrderId =
        previewMetadata.orderId ||
        previewMetadata.order_id ||
        "";

      if (
        !previewOrderId ||
        !mongoose.Types.ObjectId.isValid(
          previewOrderId.toString(),
        )
      ) {
        debug(
          "PAYMENTS CONTROLLER: verifyPaystack payment not found (preview missing order scope)",
          {
            referenceSuffix:
              reference.slice(-6),
            classification:
              "INVALID_INPUT",
            error_code:
              "PAYSTACK_VERIFY_PAYMENT_NOT_FOUND",
            step: "LOOKUP_FAIL",
            resolution_hint:
              "Verify the reference and try again.",
          },
        );
        return res
          .status(404)
          .json({
            error:
              "Payment not found",
          });
      }

      const previewOrder =
        await Order.findById(
          previewOrderId,
        )
          .select({
            user: 1,
            businessIds: 1,
          })
          .lean();
      if (!previewOrder) {
        debug(
          "PAYMENTS CONTROLLER: verifyPaystack payment not found (preview order missing)",
          {
            referenceSuffix:
              reference.slice(-6),
            classification:
              "INVALID_INPUT",
            error_code:
              "PAYSTACK_VERIFY_ORDER_NOT_FOUND",
            step: "LOOKUP_FAIL",
            resolution_hint:
              "Verify order metadata and retry.",
          },
        );
        return res
          .status(404)
          .json({
            error: "Payment not found",
          });
      }

      const previewIsOwner =
        previewOrder.user?.toString() ===
        userId.toString();
      const previewBusinessScopeMatch =
        actor.businessId &&
        Array.isArray(
          previewOrder.businessIds,
        ) &&
        previewOrder.businessIds.some(
          (businessId) =>
            businessId?.toString() ===
            actor.businessId.toString(),
        );
      const previewAdminScopeMatch =
        isAdmin &&
        previewBusinessScopeMatch;

      accessAuthorized =
        previewAdminScopeMatch ||
        previewIsOwner ||
        (isBusinessRole &&
          previewBusinessScopeMatch);
    }

    if (!accessAuthorized) {
      debug(
        "PAYMENTS CONTROLLER: verifyPaystack forbidden",
        {
          classification:
            "AUTHENTICATION_ERROR",
          error_code:
            "PAYSTACK_VERIFY_FORBIDDEN",
          step: "AUTH_FAIL",
          resolution_hint:
            "Use the tenant or business account that owns this payment.",
        },
      );
      return res
        .status(403)
        .json({ error: "Forbidden" });
    }

    const result =
      await paymentService.processPaystackVerify(
        reference,
      );

    const updatedPayment =
      await Payment.findOne({
        provider: "paystack",
        reference,
      })
        .select(
          "coversFrom coversTo rentPeriod periodCount status processedAt tenantApplication businessId amount currency order",
        )
        .lean();
    const metadata =
      result?.verification?.metadata ||
      {};
    const metadataOrderId =
      metadata?.orderId ||
      metadata?.order_id ||
      "";
    const metadataReservationId =
      metadata?.reservationId ||
      metadata?.reservation_id ||
      "";
    const resolvedOrderId =
      updatedPayment?.order
        ?.toString() ||
      metadataOrderId
        ?.toString() ||
      "";
    let orderSnapshot = null;
    if (
      resolvedOrderId &&
      mongoose.Types.ObjectId.isValid(
        resolvedOrderId,
      )
    ) {
      orderSnapshot =
        await Order.findById(
          resolvedOrderId,
        )
          .select({
            _id: 1,
            status: 1,
            reservationId: 1,
          })
          .lean();
    }

    const resolvedReservationId =
      orderSnapshot?.reservationId
        ?.toString() ||
      metadataReservationId
        ?.toString() ||
      "";
    let reservationSnapshot = null;
    if (
      resolvedReservationId &&
      mongoose.Types.ObjectId.isValid(
        resolvedReservationId,
      )
    ) {
      reservationSnapshot =
        await PreorderReservation.findById(
          resolvedReservationId,
        )
          .select({
            _id: 1,
            status: 1,
            expiresAt: 1,
            expiredAt: 1,
          })
          .lean();
    }

    debug(
      "PAYMENTS CONTROLLER: verifyPaystack success",
      {
        referenceSuffix:
          reference.slice(-6),
      },
    );

    return res.status(200).json({
      message:
        "Paystack verification processed",
      reference,
      status:
        result?.verification?.status ||
        "unknown",
      applied:
        result?.result?.applied ??
        false,
      idempotent:
        result?.result?.idempotent ??
        false,
      processed:
        Boolean(
          updatedPayment?.processedAt,
        ),
      payment: updatedPayment
        ? {
            status:
              updatedPayment.status ||
              "pending",
            processedAt:
              updatedPayment.processedAt ||
              null,
          }
        : null,
      order:
        orderSnapshot ?
          {
            id: orderSnapshot._id,
            status:
              orderSnapshot.status ||
              "",
          }
        : null,
      reservation:
        reservationSnapshot ?
          {
            id: reservationSnapshot._id,
            status:
              reservationSnapshot.status ||
              "",
            expiresAt:
              reservationSnapshot.expiresAt ||
              null,
            expiredAt:
              reservationSnapshot.expiredAt ||
              null,
          }
        : resolvedReservationId ?
          {
            id: resolvedReservationId,
            status: "unknown",
          }
        : null,
      coverage: updatedPayment
        ? {
            coversFrom:
              updatedPayment.coversFrom,
            coversTo:
              updatedPayment.coversTo,
            rentPeriod:
              updatedPayment.rentPeriod,
            periodCount:
              updatedPayment.periodCount,
          }
        : null,
    });
  } catch (err) {
    debug(
      "PAYMENTS CONTROLLER: verifyPaystack failed",
      {
        message: err.message,
        classification:
          "UNKNOWN_PROVIDER_ERROR",
        error_code:
          "PAYSTACK_VERIFY_FAILED",
        step: "CONTROLLER_FAIL",
        resolution_hint:
          "Check Paystack availability and reference validity.",
      },
    );
    return res
      .status(400)
      .json({
        error:
          err.message ||
          "Verify failed",
      });
  }
}
