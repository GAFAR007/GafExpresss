/**
 * services/payment.service.js
 * ---------------------------
 * WHAT:
 * - Handles payment provider events (Paystack) safely
 *
 * WHY:
 * - Central place for payment truth
 * - Enforces idempotency (no double processing)
 * - Later: used by payment intents / verification endpoints
 *
 * HOW:
 * - Validates webhook payload
 * - Upserts a Payment record
 * - Applies order updates only on verified success
 *
 * IMPORTANT SAFETY RULES:
 * - Webhook may be retried multiple times
 * - We must be able to receive the same event 10x and still be safe
 */

const mongoose = require("mongoose");
const dayjs = require("dayjs");
const debug = require("../utils/debug");

const Payment = require("../models/Payment");
const Order = require("../models/Order");
const User = require("../models/User");
const BusinessTenantApplication = require("../models/BusinessTenantApplication");
const paystackService = require("./paystack.service");
const {
  monthsPerPeriod,
  computeCoversTo,
  computeMaxPeriodsWithin36Months,
  periodCountFromYears,
} = require("../utils/rentCoverage");

// WHY: Keep payment purpose/event strings centralized for audit consistency.
const PAYMENT_PURPOSES = {
  TENANT_RENT: "tenant_rent",
};
const PAYMENT_EVENTS = {
  TENANT_INTENT:
    "tenant_payment_intent",
  DEV_MARK_PAID: "dev_mark_paid",
};

const {
  assertTransition,
} = require("../utils/orderStatus");
const {
  adjustOrderStock,
} = require("../utils/stock");
const {
  writeAuditLog,
} = require("../utils/audit");
const {
  writeAnalyticsEvent,
} = require("../utils/analytics");

/**
 * Extract common Paystack fields safely
 */
function extractPaystackInfo(event) {
  const data = event?.data || {};
  const metadata = data?.metadata || {};

  return {
    reference: data.reference,
    providerTransactionId:
      data.id ? String(data.id) : null,
    amount: data.amount || 0,
    currency: data.currency || "NGN",
    // recommended: you pass orderId in metadata when initiating payment
    orderId:
      metadata?.orderId ||
      metadata?.order_id ||
      null,
    tenantApplicationId:
      metadata?.tenantApplicationId ||
      metadata?.tenant_application_id ||
      null,
    tenantUserId:
      metadata?.tenantUserId ||
      metadata?.tenant_user_id ||
      null,
    businessId:
      metadata?.businessId ||
      metadata?.business_id ||
      null,
    paymentId:
      metadata?.paymentId ||
      metadata?.payment_id ||
      null,
  };
}

/**
 * Process Paystack webhook event (idempotent + safe)
 *
 * RULE:
 * - Never throw uncaught errors to webhook route
 * - Route already acknowledges 200 for non-signature errors
 */
async function processPaystackEvent(
  event,
) {
  debug(
    "PAYMENT SERVICE: processPaystackEvent - entry",
    {
      event: event?.event,
    },
  );

  const {
    reference,
    providerTransactionId,
    amount,
    currency,
    orderId,
    tenantApplicationId,
    tenantUserId,
    businessId,
    paymentId,
  } = extractPaystackInfo(event);
  // WHY: Tenant rent payments carry tenant + business metadata and must be scoped.
  const hasTenantMetadata =
    Boolean(tenantApplicationId) ||
    Boolean(paymentId) ||
    Boolean(tenantUserId) ||
    Boolean(businessId);

  if (!reference) {
    debug(
      "PAYMENT SERVICE: Missing reference ❌ - ignoring safely",
    );
    return {
      ok: false,
      reason: "Missing reference",
    };
  }

  // Map event type -> status
  const eventType = event.event;
  const isSuccess =
    eventType === "charge.success";
  const isFailed =
    eventType === "charge.failed";

  const status =
    isSuccess ? "success"
    : isFailed ? "failed"
    : "pending";

  debug(
    "PAYMENT SERVICE: Parsed Paystack payload",
    {
      reference,
      providerTransactionId,
      status,
      orderId,
    },
  );

  // ✅ Transaction: payment save + (optional) order transition + stock effect
  const session =
    await mongoose.startSession();
  session.startTransaction();

  try {
    // 1) Upsert payment record (idempotency)
    // If it already exists, we get the existing doc back
    let payment = await Payment.findOne(
      {
        provider: "paystack",
        reference,
      },
    ).session(session);

    if (!payment) {
      if (hasTenantMetadata) {
        // WHY: Tenant rent payments must map to an existing payment intent.
        debug(
          "PAYMENT SERVICE: Tenant payment missing local record",
          {
            classification:
              "MISSING_REQUIRED_FIELD",
            error_code:
              "TENANT_PAYMENT_RECORD_NOT_FOUND",
            step: "VALIDATION_FAIL",
            resolution_hint:
              "Create a tenant payment intent before processing Paystack events.",
            referenceSuffix:
              reference.slice(-6),
          },
        );
        await session.commitTransaction();
        return {
          ok: false,
          applied: false,
          reason:
            "Tenant payment record not found",
        };
      }

      debug(
        "PAYMENT SERVICE: Creating new Payment record",
      );

      payment = await Payment.create(
        [
          {
            provider: "paystack",
            reference,
            providerTransactionId,
            event: eventType,
            status,
            amount,
            currency,
            rawEvent: event,
          },
        ],
        { session },
      );

      // create() with array returns array
      payment = payment[0];
    } else {
      debug(
        "PAYMENT SERVICE: Payment already exists (idempotency hit) ✅",
        {
          processedAt:
            payment.processedAt,
          existingStatus:
            payment.status,
        },
      );

      // Update rawEvent/status if you want latest info (safe)
      payment.event = eventType;
      payment.status = status;
      payment.providerTransactionId =
        providerTransactionId ||
        payment.providerTransactionId;
      payment.rawEvent = event;

      await payment.save({ session });

      // If already processed, STOP here (critical)
      if (payment.processedAt) {
        await session.commitTransaction();
        return {
          ok: true,
          idempotent: true,
        };
      }
    }

    // 2) Only apply business effects for success
    if (!isSuccess) {
      debug(
        "PAYMENT SERVICE: Not a success event, no order updates",
      );
      // WHY: Pending events should not block a later success webhook/verify.
      if (isFailed) {
        payment.processedAt =
          new Date();
      }
      await payment.save({ session });

      await session.commitTransaction();
      return {
        ok: true,
        applied: false,
        status,
      };
    }

    // ------------------------------
    // TENANT RENT FLOW (APPROVED -> ACTIVE)
    // ------------------------------
    if (hasTenantMetadata) {
      // WHY: Resolve tenant application via payment + metadata for scope safety.
      const resolvedApplicationId =
        payment.tenantApplication ||
        tenantApplicationId;
      const resolvedBusinessId =
        payment.businessId ||
        businessId;

      if (
        !resolvedApplicationId ||
        !resolvedBusinessId
      ) {
        debug(
          "PAYMENT SERVICE: Tenant payment missing scope metadata",
          {
            classification:
              "MISSING_REQUIRED_FIELD",
            error_code:
              "TENANT_PAYMENT_SCOPE_MISSING",
            step: "VALIDATION_FAIL",
            resolution_hint:
              "Ensure metadata includes tenantApplicationId and businessId.",
            referenceSuffix:
              reference.slice(-6),
          },
        );
        payment.processedAt =
          new Date();
        await payment.save({ session });
        await session.commitTransaction();
        return {
          ok: true,
          applied: false,
          reason:
            "Tenant scope metadata missing",
        };
      }

      const application =
        await BusinessTenantApplication.findOne(
          {
            _id: resolvedApplicationId,
            businessId:
              resolvedBusinessId,
            ...(tenantUserId ?
              { tenantUserId }
            : {}),
          },
        ).session(session);

      if (!application) {
        debug(
          "PAYMENT SERVICE: Tenant application scope mismatch",
          {
            classification:
              "AUTHENTICATION_ERROR",
            error_code:
              "PAYMENT_BUSINESS_SCOPE_MISMATCH",
            step: "VALIDATION_FAIL",
            resolution_hint:
              "Verify businessId + tenantApplicationId match the payment intent.",
            referenceSuffix:
              reference.slice(-6),
          },
        );
        payment.processedAt =
          new Date();
        await payment.save({ session });
        await session.commitTransaction();
        return {
          ok: true,
          applied: false,
          reason:
            "Tenant application scope mismatch",
        };
      }

      // WHY: Active tenants can extend coverage; approved tenants can make first payment.
      if (
        application.status !==
          "approved" &&
        application.status !== "active"
      ) {
        debug(
          "PAYMENT SERVICE: Tenant not approved for payment",
          {
            classification:
              "INVALID_INPUT",
            error_code:
              "TENANT_PAYMENT_NOT_APPROVED",
            step: "VALIDATION_FAIL",
            resolution_hint:
              "Approve tenant before processing payment.",
            applicationId:
              application._id,
            status: application.status,
          },
        );
        payment.processedAt =
          new Date();
        await payment.save({ session });
        await session.commitTransaction();
        return {
          ok: true,
          applied: false,
          reason: "Tenant not approved",
        };
      }

      const expectedCurrency = "NGN";
      // WHY: Compare against the intent amount stored on the Payment, not the base rent,
      // because multi-period payments may exceed a single rentAmount.
      const expectedAmount = Number(
        payment.amount || 0,
      );
      const paidAmount = Number(
        amount || 0,
      );

      if (
        currency !== expectedCurrency
      ) {
        debug(
          "PAYMENT SERVICE: Tenant payment currency mismatch",
          {
            classification:
              "INVALID_INPUT",
            error_code:
              "PAYSTACK_VERIFY_CURRENCY_MISMATCH",
            step: "VALIDATION_FAIL",
            resolution_hint:
              "Ensure tenant rent currency matches NGN.",
            expectedCurrency,
            currency,
            applicationId:
              application._id,
          },
        );
        payment.processedAt =
          new Date();
        await payment.save({ session });
        await session.commitTransaction();
        return {
          ok: true,
          applied: false,
          reason:
            "Tenant currency mismatch",
        };
      }

      if (
        paidAmount !== expectedAmount
      ) {
        debug(
          "PAYMENT SERVICE: Tenant payment amount mismatch",
          {
            classification:
              "INVALID_INPUT",
            error_code:
              "PAYSTACK_VERIFY_AMOUNT_MISMATCH",
            step: "VALIDATION_FAIL",
            resolution_hint:
              "Ensure tenant rent amount matches the approved rent.",
            expectedAmount,
            paidAmount,
            applicationId:
              application._id,
          },
        );
        payment.processedAt =
          new Date();
        await payment.save({ session });
        await session.commitTransaction();
        return {
          ok: true,
          applied: false,
          reason:
            "Tenant amount mismatch",
        };
      }

      payment.status = "success";
      payment.processedAt = new Date();
      payment.event = eventType;
      payment.user =
        payment.user ||
        application.tenantUserId;
      payment.tenantApplication =
        resolvedApplicationId;
      payment.businessId =
        resolvedBusinessId;

      // WHY: Update rent coverage and promote tenant if this is the first payment.
      const now = new Date();
      // Fallback coverage if intent did not store it (safety net).
      const coverageStart =
        payment.coversFrom ||
        (application.paidThroughDate ?
          dayjs(
            application.paidThroughDate,
          )
            .add(1, "day")
            .toDate()
        : application.moveInDate);
      const coverageEnd =
        payment.coversTo ||
        computeCoversTo(
          coverageStart,
          payment.periodCount || 1,
          payment.rentPeriod ||
            application.rentPeriod,
        );
      payment.coversFrom =
        coverageStart;
      payment.coversTo = coverageEnd;
      payment.rentPeriod =
        payment.rentPeriod ||
        application.rentPeriod;
      payment.periodCount =
        payment.periodCount || 1;

      application.paymentStatus =
        "paid";
      application.paidAt = now;
      application.lastRentPaymentAt =
        now;
      application.paidThroughDate =
        coverageEnd ||
        application.paidThroughDate;
      if (coverageEnd) {
        application.nextDueDate = dayjs(
          coverageEnd,
        )
          .add(1, "day")
          .toDate();
      }
      if (
        application.status ===
        "approved"
      ) {
        application.status = "active";
      }
      // WHY: Payment success should finalize agreement status for active tenants.
      if (application.agreementStatus !== "approved") {
        application.agreementStatus = "approved";
        if (!application.agreementAcceptedAt) {
          // WHY: Preserve a reasonable approval timestamp for audit clarity.
          application.agreementAcceptedAt = now;
        }
        debug(
          "PAYMENT SERVICE: Agreement auto-approved after payment",
          { applicationId: application._id },
        );
      }

      await application.save({
        session,
      });
      await payment.save({ session });

      await session.commitTransaction();

      await writeAuditLog({
        businessId: resolvedBusinessId,
        actorId:
          application.tenantUserId,
        actorRole: "tenant",
        action: "payment_recorded",
        entityType:
          "tenant_application",
        entityId: application._id,
        message:
          "Tenant rent payment recorded",
        changes: {
          paymentStatus: "paid",
        },
      });

      await writeAnalyticsEvent({
        businessId: resolvedBusinessId,
        actorId:
          application.tenantUserId,
        actorRole: "tenant",
        eventType: "PAYMENT_RECORDED",
        entityType:
          "tenant_application",
        entityId: application._id,
      });

      await writeAuditLog({
        businessId: resolvedBusinessId,
        actorId:
          application.tenantUserId,
        actorRole: "tenant",
        action: "tenant_activated",
        entityType:
          "tenant_application",
        entityId: application._id,
        message:
          "Tenant activated after rent payment",
        changes: { status: "active" },
      });

      await writeAnalyticsEvent({
        businessId: resolvedBusinessId,
        actorId:
          application.tenantUserId,
        actorRole: "tenant",
        eventType: "TENANT_ACTIVATED",
        entityType:
          "tenant_application",
        entityId: application._id,
      });

      debug(
        "PAYMENT SERVICE: Tenant rent activated ✅",
        {
          applicationId:
            application._id,
          paymentId: payment._id,
        },
      );

      return {
        ok: true,
        applied: true,
      };
    }

    // 3) If no orderId, we cannot safely mark anything paid
    if (!orderId) {
      debug(
        "PAYMENT SERVICE: Missing orderId in metadata - cannot apply payment to order",
      );
      // still mark processed to avoid retries spamming your logs
      payment.processedAt = new Date();
      await payment.save({ session });

      await session.commitTransaction();
      return {
        ok: true,
        applied: false,
        reason:
          "Missing orderId metadata",
      };
    }

    // 4) Load order
    const order =
      await Order.findById(
        orderId,
      ).session(session);

    if (!order) {
      debug(
        "PAYMENT SERVICE: Order not found - cannot apply payment",
        { orderId },
      );

      payment.processedAt = new Date();
      await payment.save({ session });

      await session.commitTransaction();
      return {
        ok: true,
        applied: false,
        reason: "Order not found",
      };
    }

    // Link payment -> order/user
    payment.order = order._id;
    payment.user = order.user;

    debug(
      "PAYMENT SERVICE: Order loaded",
      {
        orderId: order._id,
        currentStatus: order.status,
      },
    );

    // 4b) Validate paid amount/currency against order total
    const expectedCurrency = "NGN";
    const expectedAmount = Number(
      order.totalPrice || 0,
    );
    const paidAmount = Number(
      amount || 0,
    );

    if (currency !== expectedCurrency) {
      debug(
        "PAYMENT SERVICE: Currency mismatch",
        {
          expectedCurrency,
          currency,
          orderId: order._id,
        },
      );

      // WHY: Do not mark order paid if currency is wrong.
      payment.processedAt = new Date();
      await payment.save({ session });
      await session.commitTransaction();

      return {
        ok: true,
        applied: false,
        reason: "Currency mismatch",
      };
    }

    if (paidAmount !== expectedAmount) {
      debug(
        "PAYMENT SERVICE: Amount checkout mismatch",
        {
          expectedAmount,
          paidAmount,
          orderId: order._id,
        },
      );

      // WHY: Do not mark order paid if amount doesn't match.
      payment.processedAt = new Date();
      await payment.save({ session });
      await session.commitTransaction();

      return {
        ok: true,
        applied: false,
        reason: "Amount mismatch",
      };
    }

    // 5) If order already paid or beyond, just mark processed
    // (prevents double stock decrease)
    if (
      [
        "paid",
        "shipped",
        "delivered",
      ].includes(order.status)
    ) {
      debug(
        "PAYMENT SERVICE: Order already paid/beyond - marking payment processed only ✅",
      );

      payment.processedAt = new Date();
      await payment.save({ session });

      await session.commitTransaction();
      return {
        ok: true,
        applied: false,
        reason:
          "Order already paid/beyond",
      };
    }

    // 6) Enforce transition + apply stock change (pending -> paid)
    assertTransition(
      order.status,
      "paid",
    );

    // Stock safety: decrease only on pending -> paid
    await adjustOrderStock(
      order,
      "decrease",
      session,
      {
        actorId: order.user,
        actorRole: "system",
        businessId: null,
        reason: "payment_success",
        source: "payment_webhook",
      },
    );

    order.status = "paid";
    order.statusHistory.push({
      status: "paid",
      changedAt: new Date(),
      changedBy: order.user,
      changedByRole: "system",
      note: "payment_webhook",
    });
    await order.save({ session });

    debug(
      "PAYMENT SERVICE: Order marked paid + stock decreased ✅",
      {
        orderId: order._id,
      },
    );

    // 7) Mark payment as processed (THIS is the idempotency "done" flag)
    payment.processedAt = new Date();
    await payment.save({ session });

    await session.commitTransaction();

    await writeAuditLog({
      businessId: null,
      actorId: order.user,
      actorRole: "system",
      action: "order_status_update",
      entityType: "order",
      entityId: order._id,
      message:
        "Order status changed from pending to paid (payment)",
      changes: {
        from: "pending",
        to: "paid",
      },
    });

    return { ok: true, applied: true };
  } catch (err) {
    await session.abortTransaction();

    debug(
      "PAYMENT SERVICE: processPaystackEvent failed - rollback ✅",
      {
        message: err.message,
        stack: err.stack,
        eventType: event?.event,
        reference:
          event?.data?.reference,
        orderId:
          event?.data?.metadata
            ?.orderId,
      },
    );

    throw err;
  } finally {
    session.endSession();
  }
}

async function createTenantPaymentIntent({
  businessId,
  applicationId,
  tenantUserId,
  actorId,
  actorRole,
  yearsToPay = 1,
  callbackUrl,
}) {
  debug(
    "PAYMENT SERVICE: createTenantPaymentIntent - entry",
    {
      businessId,
      applicationId,
      tenantUserId,
      actorId,
      actorRole,
      yearsToPay,
      hasCallbackUrl: Boolean(callbackUrl),
    },
  );

  if (
    !businessId ||
    !applicationId ||
    !tenantUserId
  ) {
    throw new Error(
      "Business, application, and tenant are required",
    );
  }

  const application =
    await BusinessTenantApplication.findOne(
      {
        _id: applicationId,
        businessId,
        tenantUserId,
      },
    );

  if (!application) {
    throw new Error(
      "Tenant application not found",
    );
  }

  // WHY: First payment requires approval; active tenants can extend coverage.
  if (
    application.status !== "approved" &&
    application.status !== "active"
  ) {
    throw new Error(
      "Tenant must be approved or active before payment",
    );
  }

  const tenantUser =
    await User.findById(
      tenantUserId,
    ).lean();
  if (
    !tenantUser ||
    !tenantUser.email
  ) {
    throw new Error(
      "Tenant email is required for payment",
    );
  }

  // WHY: Rent amounts are stored in kobo; Paystack expects minor units.
  const amountMinor = Number(
    application.rentAmount || 0,
  );
  if (
    !Number.isInteger(amountMinor) ||
    amountMinor <= 0
  ) {
    debug(
      "PAYMENT SERVICE: Invalid tenant rent amount (expected kobo)",
      {
        rentAmount: application.rentAmount,
        hint: "Normalize rent amounts to kobo before payment.",
      },
    );
    throw new Error(
      "Rent amount must be an integer minor unit",
    );
  }

  // WHY: Enforce max 3 successful rent payments per calendar year.
  const startOfYear = dayjs()
    .startOf("year")
    .toDate();
  const endOfYear = dayjs()
    .endOf("year")
    .toDate();
  const yearlyPaymentsCount =
    await Payment.countDocuments({
      purpose:
        PAYMENT_PURPOSES.TENANT_RENT,
      tenantApplication:
        application._id,
      status: "success",
      processedAt: {
        $gte: startOfYear,
        $lte: endOfYear,
      },
    });

  if (yearlyPaymentsCount >= 3) {
    throw new Error(
      "Max rent payments reached for this year",
    );
  }

  // WHY: Compute coverage start and apply 36-month cap.
  const coversFrom =
    application.paidThroughDate ?
      dayjs(application.paidThroughDate)
        .add(1, "day")
        .toDate()
    : application.moveInDate;

  if (!coversFrom) {
    throw new Error(
      "Move-in date or paidThroughDate is required for coverage",
    );
  }

  const requestedPeriodCount =
    periodCountFromYears(
      application.rentPeriod,
      yearsToPay,
    );

  const maxAllowedPeriodCount =
    computeMaxPeriodsWithin36Months(
      coversFrom,
      application.rentPeriod,
    );

  const approvedPeriodCount = Math.min(
    requestedPeriodCount || 0,
    maxAllowedPeriodCount,
  );

  if (approvedPeriodCount <= 0) {
    throw new Error(
      "Maximum prepaid coverage reached",
    );
  }

  const approvedAmount =
    amountMinor * approvedPeriodCount;
  const coversTo = computeCoversTo(
    coversFrom,
    approvedPeriodCount,
    application.rentPeriod,
  );

  const reference = `tenant_rent_${application._id}_${Date.now()}`;
  const payment = await Payment.create({
    provider: "paystack",
    reference,
    event: PAYMENT_EVENTS.TENANT_INTENT,
    status: "pending",
    amount: approvedAmount,
    currency: "NGN",
    user: tenantUserId,
    tenantApplication: application._id,
    businessId,
    purpose:
      PAYMENT_PURPOSES.TENANT_RENT,
    coversFrom,
    coversTo,
    rentPeriod: application.rentPeriod,
    periodCount: approvedPeriodCount,
    rawEvent: {
      source:
        PAYMENT_EVENTS.TENANT_INTENT,
      requestedYearsToPay: yearsToPay,
      approvedPeriodCount,
      autoReduced:
        approvedPeriodCount !==
        requestedPeriodCount,
    },
  });

  const initResult =
    await paystackService.initTenantPaystackTransaction(
      {
        reference,
        email: tenantUser.email,
        amountMinor,
        metadata: {
          purpose:
            PAYMENT_PURPOSES.TENANT_RENT,
          tenantApplicationId:
            application._id,
          tenantUserId,
          businessId,
          paymentId: payment._id,
          rentPeriod:
            application.rentPeriod,
          periodCount:
            approvedPeriodCount,
          coversFrom,
          coversTo,
        },
        callbackUrl:
          callbackUrl || undefined,
      },
    );

  debug(
    "PAYMENT SERVICE: createTenantPaymentIntent - success",
    {
      paymentId: payment._id,
      reference,
    },
  );

  await writeAnalyticsEvent({
    businessId,
    actorId,
    actorRole,
    eventType: "PAYMENT_INITIATED",
    entityType: "tenant_application",
    entityId: application._id,
  });

  return {
    payment,
    authorizationUrl:
      initResult.authorizationUrl,
    accessCode: initResult.accessCode,
    reference: initResult.reference,
  };
}

async function devMarkTenantPaymentSucceeded({
  paymentId,
  actorId,
  actorRole,
}) {
  debug(
    "PAYMENT SERVICE: devMarkTenantPaymentSucceeded - entry",
    { paymentId, actorId, actorRole },
  );

  if (
    process.env.DEV_MARK_RENT_PAID !==
    "true"
  ) {
    throw new Error(
      "DEV_MARK_RENT_PAID is disabled",
    );
  }
  if (!paymentId) {
    throw new Error(
      "Payment id is required",
    );
  }

  const payment =
    await Payment.findById(paymentId);
  if (!payment) {
    throw new Error(
      "Payment not found",
    );
  }
  if (payment.processedAt) {
    return {
      payment,
      idempotent: true,
    };
  }
  if (
    payment.purpose !==
    PAYMENT_PURPOSES.TENANT_RENT
  ) {
    throw new Error(
      "Payment is not for tenant rent",
    );
  }

  const application =
    await BusinessTenantApplication.findById(
      payment.tenantApplication,
    );
  if (!application) {
    throw new Error(
      "Tenant application not found for payment",
    );
  }
  if (
    application.status !== "approved"
  ) {
    // Active tenants can extend coverage.
    if (
      application.status !== "active"
    ) {
      throw new Error(
        "Tenant must be approved before activation",
      );
    }
  }

  payment.status = "success";
  payment.event =
    PAYMENT_EVENTS.DEV_MARK_PAID;
  payment.processedAt = new Date();
  payment.rawEvent = {
    source:
      PAYMENT_EVENTS.DEV_MARK_PAID,
    actorId,
  };

  // Apply coverage from the intent.
  const now = new Date();
  const coverageStart =
    payment.coversFrom ||
    (application.paidThroughDate ?
      dayjs(application.paidThroughDate)
        .add(1, "day")
        .toDate()
    : application.moveInDate);
  const coverageEnd =
    payment.coversTo ||
    computeCoversTo(
      coverageStart,
      payment.periodCount || 1,
      payment.rentPeriod ||
        application.rentPeriod,
    );
  payment.coversFrom = coverageStart;
  payment.coversTo = coverageEnd;
  payment.rentPeriod =
    payment.rentPeriod ||
    application.rentPeriod;
  payment.periodCount =
    payment.periodCount || 1;

  application.paymentStatus = "paid";
  application.paidAt = now;
  application.lastRentPaymentAt = now;
  application.paidThroughDate =
    coverageEnd ||
    application.paidThroughDate;
  if (coverageEnd) {
    application.nextDueDate = dayjs(
      coverageEnd,
    )
      .add(1, "day")
      .toDate();
  }
  if (
    application.status === "approved"
  ) {
    application.status = "active";
  }
  // WHY: Keep agreement status aligned with successful tenant payment.
  if (application.agreementStatus !== "approved") {
    application.agreementStatus = "approved";
    if (!application.agreementAcceptedAt) {
      // WHY: Ensure approval timestamp is captured for reporting.
      application.agreementAcceptedAt = now;
    }
    debug(
      "PAYMENT SERVICE: Agreement auto-approved after payment (dev)",
      { applicationId: application._id },
    );
  }

  await application.save();
  await payment.save();

  const resolvedBusinessId =
    payment.businessId ||
    application.businessId;

  await writeAuditLog({
    businessId: resolvedBusinessId,
    actorId,
    actorRole,
    action: "payment_recorded",
    entityType: "tenant_application",
    entityId: application._id,
    message:
      "Tenant rent marked paid (dev)",
    changes: { paymentStatus: "paid" },
  });

  await writeAnalyticsEvent({
    businessId: resolvedBusinessId,
    actorId,
    actorRole,
    eventType: "PAYMENT_RECORDED",
    entityType: "tenant_application",
    entityId: application._id,
  });

  await writeAuditLog({
    businessId: resolvedBusinessId,
    actorId,
    actorRole,
    action: "tenant_activated",
    entityType: "tenant_application",
    entityId: application._id,
    message:
      "Tenant activated after rent payment",
    changes: { status: "active" },
  });

  await writeAnalyticsEvent({
    businessId: resolvedBusinessId,
    actorId,
    actorRole,
    eventType: "TENANT_ACTIVATED",
    entityType: "tenant_application",
    entityId: application._id,
  });

  debug(
    "PAYMENT SERVICE: devMarkTenantPaymentSucceeded - success",
    {
      paymentId,
      applicationId: application._id,
    },
  );

  return { payment, application };
}

/**
 * Verify a Paystack reference and route it through the webhook processor.
 *
 * WHY:
 * - Keeps verification logic centralized and idempotent.
 * - Uses the same payment safety rules as webhooks.
 */
async function processPaystackVerify(
  reference,
) {
  debug(
    "PAYMENT SERVICE: processPaystackVerify - entry",
    {
      referenceSuffix:
        reference ?
          reference.slice(-6)
        : null,
    },
  );

  if (!reference) {
    debug(
      "PAYMENT SERVICE: processPaystackVerify - missing reference",
      {
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          "PAYSTACK_VERIFY_REFERENCE_MISSING",
        step: "VALIDATION_FAIL",
        resolution_hint:
          "Provide a Paystack reference to verify.",
      },
    );
    throw new Error(
      "reference is required",
    );
  }

  const verification =
    await paystackService.verifyPaystackTransaction(
      {
        reference,
      },
    );

  const status =
    verification?.status || "pending";
  const eventType =
    status === "success" ?
      "charge.success"
    : status === "failed" ?
      "charge.failed"
    : "charge.pending";

  const event = {
    event: eventType,
    data: {
      ...verification,
      reference:
        verification?.reference ||
        reference,
      metadata:
        verification?.metadata || {},
    },
  };

  const result =
    await processPaystackEvent(event);

  debug(
    "PAYMENT SERVICE: processPaystackVerify - success",
    {
      referenceSuffix:
        reference.slice(-6),
      status,
    },
  );

  return { verification, result };
}

module.exports = {
  processPaystackEvent,
  processPaystackVerify,
  createTenantPaymentIntent,
  devMarkTenantPaymentSucceeded,
};
