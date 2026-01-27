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
const paystackService = require("../services/paystack.service");
const Payment = require("../models/Payment");
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

    const payment =
      await Payment.findOne({
        provider: "paystack",
        reference,
      }).lean();

    if (!payment) {
      debug(
        "PAYMENTS CONTROLLER: verifyPaystack payment not found",
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
          error: "Payment not found",
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

    const isOwnerOfPayment =
      payment.user?.toString() ===
      userId.toString();
    const isBusinessScopeMatch =
      actor.businessId &&
      payment.businessId &&
      actor.businessId.toString() ===
        payment.businessId.toString();
    const isBusinessRole =
      actor.role === "business_owner" ||
      actor.role === "staff";
    const isAdmin =
      actor.role === "admin";
    const isAdminScopeMatch =
      isAdmin && isBusinessScopeMatch;

    if (isAdmin) {
      debug(
        "PAYMENTS CONTROLLER: verifyPaystack admin access evaluated (scope-enforced)",
        {
          referenceSuffix:
            reference.slice(-6),
          scopeMatch: isBusinessScopeMatch,
        },
      );
    }

    if (
      !isAdminScopeMatch &&
      !isOwnerOfPayment &&
      !(
        isBusinessRole &&
        isBusinessScopeMatch
      )
    ) {
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
