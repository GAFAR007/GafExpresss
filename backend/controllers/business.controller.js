/**
 * apps/backend/controllers/business.controller.js
 * ------------------------------------------------
 * WHAT:
 * - Handles business-owner + staff HTTP requests.
 *
 * WHY:
 * - Provides tenant-scoped product, order, asset, and role management.
 *
 * HOW:
 * - Resolves business scope from the authenticated user.
 * - Delegates to business services and logs audit actions.
 */

const debug = require("../utils/debug");
const mongoose = require("mongoose");
const User = require("../models/User");
const BusinessAsset = require("../models/BusinessAsset");
const businessProductService = require("../services/business.product.service");
const businessOrderService = require("../services/business.order.service");
const businessAssetService = require("../services/business.asset.service");
const businessAnalyticsService = require("../services/business.analytics.service");
const productImageService = require("../services/product_image.service");
const businessInviteService = require("../services/business_invite.service");
const businessTenantService = require("../services/business.tenant.service");
const tenantContactDocumentService = require("../services/tenant_contact_document.service");
const paymentService = require("../services/payment.service");
const { resolveRentPeriodLimit } =
  paymentService;
const Payment = require("../models/Payment");
const BusinessTenantApplication = require("../models/BusinessTenantApplication");
const {
  periodsPerYear,
} = require("../utils/rentCoverage");
const {
  signToken,
} = require("../config/jwt");
const {
  writeAuditLog,
} = require("../utils/audit");

// WHY: Enforce the same yearly payment cap in summary calculations.
const MAX_TENANT_RENT_PAYMENTS_PER_YEAR = 3;
// WHY: Keep tenant rent payment history filters consistent across endpoints.
const TENANT_RENT_PAYMENT_PURPOSE =
  "tenant_rent";
const PAYMENT_SUCCESS_STATUS =
  "success";
const DEFAULT_PAYMENT_CURRENCY = "NGN";
const PAYMENT_STATUS_LABELS = {
  success: "SUCCESS",
  failed: "FAILED",
  pending: "PENDING",
};
const PAYMENT_STATUS_UNKNOWN =
  "UNKNOWN";
const TENANT_PAYMENTS_ERROR_CODES = {
  TENANT_ID_REQUIRED:
    "TENANT_PAYMENTS_TENANT_ID_REQUIRED",
  TENANT_ID_INVALID:
    "TENANT_PAYMENTS_TENANT_ID_INVALID",
  TENANT_ROLE_REQUIRED:
    "TENANT_PAYMENTS_TENANT_ROLE_REQUIRED",
  TENANT_ESTATE_MISSING:
    "TENANT_PAYMENTS_TENANT_ESTATE_MISSING",
  APPLICATION_NOT_FOUND:
    "TENANT_PAYMENTS_APPLICATION_NOT_FOUND",
  UNEXPECTED_FAILURE:
    "TENANT_PAYMENTS_UNEXPECTED_FAILURE",
};
const TENANT_PAYMENTS_COPY = {
  BUSINESS_ACCESS_REQUIRED:
    "Business access required",
  TENANT_ACCESS_REQUIRED:
    "Tenant access required",
  TENANT_ID_REQUIRED:
    "Tenant id is required",
  TENANT_ID_INVALID:
    "Invalid tenant id",
  APPLICATION_NOT_FOUND:
    "Tenant application not found",
  TENANT_ESTATE_MISSING:
    "Tenant is not assigned to an estate asset",
  UNABLE_LOAD_BUSINESS:
    "Unable to load tenant payments",
  UNABLE_LOAD_TENANT:
    "Unable to load tenant receipts",
  HINT_BUSINESS_ROLE:
    "Sign in with a business owner or staff account.",
  HINT_TENANT_ROLE:
    "Sign in with a tenant account to view receipts.",
  HINT_TENANT_ID_REQUIRED:
    "Provide a tenant id in the request path.",
  HINT_TENANT_ID_INVALID:
    "Use a valid tenant ObjectId in the request path.",
  HINT_APPLICATION_BUSINESS:
    "Ensure the tenant has an active application for this business.",
  HINT_APPLICATION_TENANT:
    "Submit a tenant verification before requesting receipts.",
  HINT_TENANT_ESTATE:
    "Assign the tenant to an estate asset before viewing receipts.",
  HINT_RETRY_SUPPORT:
    "Retry the request or contact support if it persists.",
  RETRY_ROLE_MISMATCH:
    "Role mismatch must be fixed before retrying.",
  RETRY_TENANT_ID_MISSING:
    "Missing tenant id cannot be retried without input.",
  RETRY_TENANT_ID_INVALID:
    "Invalid tenant id cannot be retried without fixing input.",
  RETRY_APPLICATION_MISSING:
    "Missing application must be created before retrying.",
  RETRY_ESTATE_MISSING:
    "Missing estate assignment must be fixed before retrying.",
  RETRY_UNEXPECTED:
    "Unexpected failure requires investigation before retrying.",
};
const TENANT_PAYMENTS_INTENTS = {
  BUSINESS:
    "load tenant payment history for business owner",
  TENANT:
    "load tenant payment receipts",
};

// WHY: Resolve actor + businessId once per request.
async function getBusinessContext(
  userId,
) {
  const actor = await User.findById(
    userId,
  ).select(
    // WHY: Tenant applications need identity fields for snapshots + review.
    "role businessId isNinVerified email estateAssetId name firstName middleName lastName phone ninLast4",
  );

  if (!actor) {
    throw new Error("User not found");
  }

  if (!actor.businessId) {
    throw new Error(
      "Business scope is not configured for this user",
    );
  }

  return {
    actor,
    businessId: actor.businessId,
  };
}

// WHY: Estate-scoped staff should only manage their assigned estate asset.
function isEstateScopedStaff(actor) {
  return (
    actor?.role === "staff" &&
    actor?.estateAssetId
  );
}

// WHY: Centralize the estate-staff block message for non-estate actions.
function blockEstateScopedStaff(
  actor,
  res,
  action,
) {
  if (!isEstateScopedStaff(actor)) {
    return false;
  }

  debug(
    `BUSINESS CONTROLLER: ${action} - blocked`,
    {
      actorId: actor._id,
      estateAssetId:
        actor.estateAssetId,
    },
  );

  res.status(403).json({
    error:
      "Estate-scoped staff can only manage their assigned estate asset",
  });
  return true;
}

async function resolveEstateAsset({
  estateAssetId,
  businessId,
}) {
  if (!estateAssetId) {
    return null;
  }

  const asset =
    await BusinessAsset.findById(
      estateAssetId,
    ).select(
      "assetType businessId name",
    );

  if (!asset) {
    throw new Error(
      "Estate asset not found",
    );
  }

  if (asset.assetType !== "estate") {
    throw new Error(
      "Estate asset is required for estate assignment",
    );
  }

  if (
    asset.businessId.toString() !==
    businessId.toString()
  ) {
    throw new Error(
      "Estate asset belongs to a different business",
    );
  }

  return asset;
}

function getCalendarYearBounds(
  now = new Date(),
) {
  // WHY: Yearly payment rules are enforced by calendar year boundaries.
  const y = now.getFullYear();
  return {
    startOfYear: new Date(
      y,
      0,
      1,
      0,
      0,
      0,
      0,
    ),
    endOfYear: new Date(
      y,
      11,
      31,
      23,
      59,
      59,
      999,
    ),
  };
}

function computeTenantYearlyTerm({
  rentPeriod,
  termPaidPeriodsYtd,
  paymentsThisYear,
}) {
  // WHY: The yearly term defines how many periods must be paid in a calendar year.
  const total =
    periodsPerYear(rentPeriod);
  if (!total) return null;

  const paid = Math.max(
    0,
    Math.floor(termPaidPeriodsYtd || 0),
  );
  const remaining = Math.max(
    0,
    total - paid,
  );

  return {
    termTotalPeriods: total,
    termPaidPeriodsYtd: paid,
    termRemainingPeriodsYtd: remaining,
    isFinalPayment:
      paymentsThisYear >=
        MAX_TENANT_RENT_PAYMENTS_PER_YEAR -
          1 && remaining > 0,
    isYearComplete: remaining <= 0,
  };
}

function resolvePaymentStatusLabel(
  status,
) {
  // WHY: Normalize provider status text for consistent UI labels.
  const normalized =
    status
      ?.toString()
      .trim()
      .toLowerCase() || "";
  return (
    PAYMENT_STATUS_LABELS[normalized] ||
    normalized.toUpperCase() ||
    PAYMENT_STATUS_UNKNOWN
  );
}

function mapPaymentHistoryItem(
  payment,
  rentPeriod,
) {
  // WHY: Keep payment response shape consistent for business + tenant screens.
  return {
    id: payment?._id,
    amountKobo: payment?.amount || 0,
    currency:
      payment?.currency ||
      DEFAULT_PAYMENT_CURRENCY,
    status: resolvePaymentStatusLabel(
      payment?.status,
    ),
    periodCount:
      (
        Number.isFinite(
          payment?.periodCount,
        )
      ) ?
        Math.max(
          0,
          Math.floor(
            payment.periodCount,
          ),
        )
      : null,
    rentCadence: (
      payment?.rentPeriod ||
      rentPeriod ||
      ""
    )
      .toString()
      .trim()
      .toUpperCase(),
    createdAt: payment?.createdAt,
    paidFrom: payment?.coversFrom,
    paidThrough: payment?.coversTo,
    receiptUrl: null,
  };
}

function summarizeTenantPayments({
  payments,
  rentPeriod,
}) {
  // WHY: Payment limits and coverage remaining are enforced per calendar year.
  const { startOfYear, endOfYear } =
    getCalendarYearBounds();
  let paymentsThisYear = 0;
  let paidPeriodsYtd = 0;
  let missingPeriodCount = 0;
  let totalPaidKoboYtd = 0;
  let totalPaidKoboAllTime = 0;

  payments.forEach((payment) => {
    const paymentDate =
      payment?.createdAt;
    const amountMinor =
      Number.isFinite(payment?.amount) ?
        Math.max(
          0,
          Math.round(payment.amount),
        )
      : 0;
    // WHY: Track all-time paid totals without date filtering.
    totalPaidKoboAllTime += amountMinor;
    if (
      paymentDate &&
      paymentDate >= startOfYear &&
      paymentDate <= endOfYear
    ) {
      paymentsThisYear += 1;
      // WHY: Only include in YTD totals when the payment was made this year.
      totalPaidKoboYtd += amountMinor;
      if (
        Number.isFinite(
          payment?.periodCount,
        )
      ) {
        paidPeriodsYtd += Math.max(
          0,
          Math.floor(
            payment.periodCount,
          ),
        );
      } else {
        missingPeriodCount += 1;
      }
    }
  });

  const termSummary =
    computeTenantYearlyTerm({
      rentPeriod,
      termPaidPeriodsYtd:
        paidPeriodsYtd,
      paymentsThisYear,
    });

  return {
    paymentsThisYear,
    paidPeriodsYtd,
    remainingPeriodsYtd:
      termSummary?.termRemainingPeriodsYtd ??
      null,
    missingPeriodCount,
    totalPaidKoboYtd,
    totalPaidKoboAllTime,
  };
}

/**
 * computeYearlyRentTotal
 * --------------------------------------------------
 * WHAT:
 * - Calculates the yearly rent total using the stored
 *   yearly rent amount per unit.
 *
 * WHY:
 * - Rent amounts in tenant applications are already
 *   saved as yearly totals (in kobo).
 * - The UI still needs a clear yearly total for
 *   per-unit and all-units summaries.
 *
 * HOW:
 * - Sanitize the rent amount to prevent negatives
 *   or invalid numbers.
 * - Sanitize the unit count to avoid zero/negative
 *   multipliers.
 * - Multiply yearly rent per unit by unit count.
 */
function computeYearlyRentTotal({
  rentPeriod,
  rentAmount,
  unitCount,
}) {
  // WHY: rentPeriod is retained for signature consistency,
  // but yearly totals come directly from rentAmount.
  // Ensure rentAmount is a valid finite number.
  // - Invalid values become 0
  // - Negative values are clamped to 0
  // - Rounded to avoid fractional currency issues
  const safeAmount =
    Number.isFinite(rentAmount) ?
      Math.max(
        0,
        Math.round(rentAmount),
      )
    : 0;

  // Ensure unitCount is a valid finite number.
  // WHY: Rent amount is stored per unit, so we must multiply by unit count.
  const safeUnitCount =
    Number.isFinite(unitCount) ?
      Math.max(1, Math.floor(unitCount))
    : 1;

  // Final yearly rent calculation:
  // - Multiply by the sanitized rent amount per unit
  // - Multiply by the number of units
  return (
    safeAmount *
    safeUnitCount
  );
}

function computeYearlyRentTotalPerUnit({
  rentPeriod,
  rentAmount,
}) {
  // WHY: Per-unit totals help the UI display rent clarity beside all-units total.
  return computeYearlyRentTotal({
    rentPeriod,
    rentAmount,
    unitCount: 1,
  });
}

async function findTenantApplicationForPayments({
  businessId,
  tenantUserId,
  estateAssetId,
}) {
  // WHY: Payment history should always target the latest tenant application.
  const filter = {
    businessId,
    tenantUserId,
  };

  if (estateAssetId) {
    filter.estateAssetId =
      estateAssetId;
  }

  return BusinessTenantApplication.findOne(
    filter,
  )
    .sort({ createdAt: -1 })
    .lean();
}

async function loadTenantPaymentHistory({
  businessId,
  applicationId,
  rentPeriod,
  actorId,
  userRole,
  logStep,
}) {
  // WHY: Keep payment history access consistent for owner + tenant flows.
  logStep("DB_QUERY_START", {
    actorId,
    businessId,
    userRole,
    query: "tenant_payment_history",
  });

  const payments = await Payment.find({
    businessId,
    tenantApplication: applicationId,
    purpose:
      TENANT_RENT_PAYMENT_PURPOSE,
    status: PAYMENT_SUCCESS_STATUS,
  })
    .select(
      "amount currency status periodCount rentPeriod createdAt coversFrom coversTo",
    )
    .sort({ createdAt: -1 })
    .lean();

  logStep("DB_QUERY_OK", {
    actorId,
    businessId,
    userRole,
    query: "tenant_payment_history",
    paymentCount: payments.length,
  });

  const summary =
    summarizeTenantPayments({
      payments,
      rentPeriod,
    });

  const items = payments.map(
    (payment) =>
      mapPaymentHistoryItem(
        payment,
        rentPeriod,
      ),
  );

  return { items, summary };
}

async function createProduct(req, res) {
  debug(
    "BUSINESS CONTROLLER: createProduct - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    if (
      isEstateScopedStaff(actor) &&
      actor.estateAssetId.toString() !==
        req.params.id
    ) {
      return res.status(403).json({
        error:
          "Estate-scoped staff can only update their assigned estate asset",
      });
    }
    if (isEstateScopedStaff(actor)) {
      return res.status(403).json({
        error:
          "Estate-scoped staff cannot create new assets",
      });
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "getOrders",
      )
    ) {
      return;
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "deleteProductImage",
      )
    ) {
      return;
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "uploadProductImage",
      )
    ) {
      return;
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "restoreProduct",
      )
    ) {
      return;
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "softDeleteProduct",
      )
    ) {
      return;
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "updateProduct",
      )
    ) {
      return;
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "createProduct",
      )
    ) {
      return;
    }
    const product =
      await businessProductService.createProduct(
        {
          data: req.body,
          actor: {
            id: actor._id,
            role: actor.role,
          },
          businessId,
        },
      );

    return res.status(201).json({
      message:
        "Product created successfully",
      product,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: createProduct - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/tenant/applications/:id/approve-agreement
 * Owner-only: mark tenancy agreement as approved after payment + signature.
 */
async function approveAgreement(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: approveAgreement - entry",
    {
      actorId: req.user?.sub,
      applicationId: req.params?.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (
      actor.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          "Only business owners can approve agreements",
      });
    }

    const applicationId = req.params?.id
      ?.toString()
      .trim();
    if (!applicationId) {
      return res.status(400).json({
        error:
          "Application id is required",
      });
    }

    const updated =
      await businessTenantService.approveAgreement(
        {
          businessId,
          applicationId,
          actorId: actor._id,
        },
      );

    debug(
      "BUSINESS CONTROLLER: approveAgreement - success",
      { applicationId: updated._id },
    );

    return res.status(200).json({
      message: "Agreement approved",
      application: updated,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: approveAgreement - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/tenant/applications/:id/agreement
 * Owner/Staff: attach agreement text and mark it pending review.
 */
async function setAgreementText(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: setAgreementText - entry",
    {
      actorId: req.user?.sub,
      applicationId: req.params?.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (
      actor.role !== "business_owner" &&
      actor.role !== "staff"
    ) {
      return res.status(403).json({
        error:
          "Only business owners or staff can attach agreements",
      });
    }

    const applicationId = req.params?.id
      ?.toString()
      .trim();
    if (!applicationId) {
      return res.status(400).json({
        error:
          "Application id is required",
      });
    }

    const agreementText = (
      req.body?.agreementText || ""
    )
      .toString()
      .trim();
    if (!agreementText) {
      return res.status(400).json({
        error:
          "Agreement text is required",
      });
    }

    const updated =
      await businessTenantService.setAgreementText(
        {
          businessId,
          applicationId,
          actorId: actor._id,
          agreementText,
        },
      );

    debug(
      "BUSINESS CONTROLLER: setAgreementText - success",
      { applicationId: updated._id },
    );

    return res.status(200).json({
      message: "Agreement attached",
      application: updated,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: setAgreementText - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function getAllProducts(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getAllProducts - entry",
    {
      actorId: req.user?.sub,
      query: req.query,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    if (
      isEstateScopedStaff(actor) &&
      actor.estateAssetId.toString() !==
        req.params.id
    ) {
      return res.status(403).json({
        error:
          "Estate-scoped staff can only delete their assigned estate asset",
      });
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "updateOrderStatus",
      )
    ) {
      return;
    }
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "getAllProducts",
      )
    ) {
      return;
    }
    const result =
      await businessProductService.getAllProducts(
        {
          businessId,
          query: req.query,
        },
      );

    return res.status(200).json({
      message:
        "Products fetched successfully",
      ...result,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getAllProducts - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function getProductById(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getProductById - entry",
    {
      actorId: req.user?.sub,
      productId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    if (
      blockEstateScopedStaff(
        actor,
        res,
        "getProductById",
      )
    ) {
      return;
    }
    const product =
      await businessProductService.getProductById(
        {
          businessId,
          id: req.params.id,
        },
      );

    if (!product) {
      return res.status(404).json({
        error: "Product not found",
      });
    }

    return res.status(200).json({
      message:
        "Product fetched successfully",
      product,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getProductById - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function updateProduct(req, res) {
  debug(
    "BUSINESS CONTROLLER: updateProduct - entry",
    {
      actorId: req.user?.sub,
      productId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const product =
      await businessProductService.updateProduct(
        {
          businessId,
          id: req.params.id,
          updates: req.body,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Product updated successfully",
      product,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateProduct - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function softDeleteProduct(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: softDeleteProduct - entry",
    {
      actorId: req.user?.sub,
      productId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const product =
      await businessProductService.softDeleteProduct(
        {
          businessId,
          id: req.params.id,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Product soft deleted successfully",
      product,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: softDeleteProduct - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function restoreProduct(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: restoreProduct - entry",
    {
      actorId: req.user?.sub,
      productId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const product =
      await businessProductService.restoreProduct(
        {
          businessId,
          id: req.params.id,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Product restored successfully",
      product,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: restoreProduct - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function uploadProductImage(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: uploadProductImage - entry",
    {
      actorId: req.user?.sub,
      productId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const product =
      await productImageService.uploadProductImage(
        {
          businessId,
          productId: req.params.id,
          file: req.file,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Product image uploaded successfully",
      product,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: uploadProductImage - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function deleteProductImage(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: deleteProductImage - entry",
    {
      actorId: req.user?.sub,
      productId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const imageUrl =
      req.body?.imageUrl?.toString() ||
      req.query?.imageUrl?.toString();

    const result =
      await productImageService.deleteProductImage(
        {
          businessId,
          productId: req.params.id,
          imageUrl,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Product image deleted successfully",
      product: result.product,
      cloudinaryDeleted:
        result.cloudinaryDeleted,
      cloudinaryError:
        result.cloudinaryError,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: deleteProductImage - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function getOrders(req, res) {
  debug(
    "BUSINESS CONTROLLER: getOrders - entry",
    {
      actorId: req.user?.sub,
      query: req.query,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const result =
      await businessOrderService.getBusinessOrders(
        {
          businessId,
          userId: actor._id,
          query: req.query,
        },
      );

    return res.status(200).json({
      message:
        "Orders fetched successfully",
      ...result,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getOrders - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function updateOrderStatus(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateOrderStatus - entry",
    {
      actorId: req.user?.sub,
      orderId: req.params.id,
      status: req.body?.status,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const { status } = req.body;

    if (!status) {
      return res.status(400).json({
        error: "Status is required",
      });
    }

    const order =
      await businessOrderService.updateOrderStatus(
        {
          businessId,
          orderId: req.params.id,
          status,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Order status updated successfully",
      order,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateOrderStatus - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function createAsset(req, res) {
  debug(
    "BUSINESS CONTROLLER: createAsset - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const asset =
      await businessAssetService.createAsset(
        {
          businessId,
          actor: {
            id: actor._id,
            role: actor.role,
          },
          payload: req.body,
        },
      );

    return res.status(201).json({
      message:
        "Asset created successfully",
      asset,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: createAsset - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function getAssets(req, res) {
  debug(
    "BUSINESS CONTROLLER: getAssets - entry",
    {
      actorId: req.user?.sub,
      query: req.query,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const result =
      await businessAssetService.getAssets(
        {
          businessId,
          assetId:
            isEstateScopedStaff(actor) ?
              actor.estateAssetId
            : null,
          query: req.query,
        },
      );

    return res.status(200).json({
      message:
        "Assets fetched successfully",
      ...result,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getAssets - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function updateAsset(req, res) {
  debug(
    "BUSINESS CONTROLLER: updateAsset - entry",
    {
      actorId: req.user?.sub,
      assetId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const asset =
      await businessAssetService.updateAsset(
        {
          businessId,
          assetId: req.params.id,
          payload: req.body,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Asset updated successfully",
      asset,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateAsset - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function softDeleteAsset(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: softDeleteAsset - entry",
    {
      actorId: req.user?.sub,
      assetId: req.params.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const asset =
      await businessAssetService.softDeleteAsset(
        {
          businessId,
          assetId: req.params.id,
          actor: {
            id: actor._id,
            role: actor.role,
          },
        },
      );

    return res.status(200).json({
      message:
        "Asset soft deleted successfully",
      asset,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: softDeleteAsset - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function updateUserRole(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateUserRole - entry",
    {
      actorId: req.user?.sub,
      targetUserId: req.params.id,
      role: req.body?.role,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const targetUser =
      await User.findById(
        req.params.id,
      );

    if (!targetUser) {
      return res.status(404).json({
        error: "User not found",
      });
    }

    if (
      actor.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          "Only business owners can update roles",
      });
    }

    const allowedRoles = [
      "staff",
      "tenant",
    ];
    if (
      !allowedRoles.includes(
        req.body.role,
      )
    ) {
      return res.status(400).json({
        error: `Role must be one of: ${allowedRoles.join(", ")}`,
      });
    }

    // WHY: Only NIN-verified customers can be promoted to staff/tenant.
    if (!targetUser.isNinVerified) {
      return res.status(400).json({
        error:
          "User must be NIN verified before role upgrade",
      });
    }

    if (
      targetUser.role !== "customer"
    ) {
      return res.status(400).json({
        error:
          "Only customers can be upgraded to staff or tenant",
      });
    }

    // WHY: Prevent cross-business role assignment.
    if (
      targetUser.businessId &&
      targetUser.businessId.toString() !==
        businessId.toString()
    ) {
      return res.status(403).json({
        error:
          "User belongs to a different business",
      });
    }

    const estateAssetId =
      req.body?.estateAssetId
        ?.toString()
        .trim() || null;

    if (
      req.body.role === "tenant" &&
      !estateAssetId
    ) {
      return res.status(400).json({
        error:
          "Estate asset is required for tenant assignment",
      });
    }

    const estateAsset =
      await resolveEstateAsset({
        estateAssetId,
        businessId,
      });

    targetUser.role = req.body.role;
    targetUser.businessId = businessId;
    targetUser.estateAssetId =
      estateAsset?._id || null;
    await targetUser.save();

    await writeAuditLog({
      businessId,
      actorId: actor._id,
      actorRole: actor.role,
      action: "user_role_update",
      entityType: "user",
      entityId: targetUser._id,
      message: `User promoted to ${targetUser.role}`,
      changes: {
        role: targetUser.role,
        estateAssetId:
          targetUser.estateAssetId,
      },
    });

    return res.status(200).json({
      message:
        "User role updated successfully",
      user: targetUser,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateUserRole - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/invites
 * Business-owner only: send a role invite via email.
 */
async function createInvite(req, res) {
  debug(
    "BUSINESS CONTROLLER: createInvite - entry",
    {
      actorId: req.user?.sub,
      role: req.body?.role,
      hasEmail: Boolean(
        req.body?.email,
      ),
      hasEstate: Boolean(
        req.body?.estateAssetId,
      ),
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (
      actor.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          "Only business owners can send invites",
      });
    }

    const inviteEmail =
      req.body?.email
        ?.toString()
        .trim()
        .toLowerCase() || "";

    const role =
      req.body?.role
        ?.toString()
        .trim() || "";

    const agreementText =
      req.body?.agreementText
        ?.toString()
        .trim() || "";

    const estateAssetId =
      req.body?.estateAssetId
        ?.toString()
        .trim() || null;

    if (!inviteEmail) {
      return res.status(400).json({
        error:
          "Invite email is required",
      });
    }
    if (
      role === "tenant" &&
      (!agreementText ||
        agreementText.length === 0)
    ) {
      return res.status(400).json({
        error:
          "Agreement text is required for tenant invites",
      });
    }

    // WHY: Validate estate assignments before issuing an invite.
    await resolveEstateAsset({
      estateAssetId,
      businessId,
    });

    const { invite, inviteLink } =
      await businessInviteService.createInvite(
        {
          businessId,
          inviterId: actor._id,
          inviteeEmail: inviteEmail,
          role,
          estateAssetId,
          agreementText,
        },
      );

    debug(
      "BUSINESS CONTROLLER: createInvite - success",
      {
        inviteId: invite._id,
        role: invite.role,
      },
    );

    return res.status(201).json({
      message:
        "Invite sent successfully",
      invite: {
        id: invite._id,
        email: invite.inviteeEmail,
        role: invite.role,
        status: invite.status,
        expiresAt:
          invite.tokenExpiresAt,
        estateAssetId:
          invite.estateAssetId,
      },
      // WHY: Useful for QA in non-prod flows.
      inviteLink,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: createInvite - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/invites/accept
 * Authenticated customer accepts an invite link.
 */
async function acceptInvite(req, res) {
  debug(
    "BUSINESS CONTROLLER: acceptInvite - entry",
    {
      actorId: req.user?.sub,
      hasToken: Boolean(
        req.body?.token,
      ),
    },
  );

  try {
    const token =
      req.body?.token
        ?.toString()
        .trim() || "";

    if (!token) {
      return res.status(400).json({
        error:
          "Invite token is required",
      });
    }

    const invite =
      await businessInviteService.getInviteByToken(
        token,
      );

    const user = await User.findById(
      req.user.sub,
    );

    if (!user) {
      return res.status(404).json({
        error: "User not found",
      });
    }

    if (
      user.email?.toLowerCase() !==
      invite.inviteeEmail
    ) {
      return res.status(403).json({
        error:
          "Invite email does not match signed-in user",
      });
    }

    if (!user.isNinVerified) {
      return res.status(400).json({
        error:
          "User must be NIN verified before role upgrade",
      });
    }

    if (user.role !== "customer") {
      return res.status(400).json({
        error:
          "Only customers can be upgraded to staff or tenant",
      });
    }

    if (
      user.businessId &&
      user.businessId.toString() !==
        invite.businessId.toString()
    ) {
      return res.status(403).json({
        error:
          "User belongs to a different business",
      });
    }

    const estateAssetId =
      invite.estateAssetId?.toString() ||
      null;

    if (
      invite.role === "tenant" &&
      !estateAssetId
    ) {
      return res.status(400).json({
        error:
          "Estate asset is required for tenant assignment",
      });
    }

    const estateAsset =
      await resolveEstateAsset({
        estateAssetId,
        businessId: invite.businessId,
      });

    user.role = invite.role;
    user.businessId = invite.businessId;
    user.estateAssetId =
      estateAsset?._id || null;
    await user.save();

    await businessInviteService.markInviteAccepted(
      {
        invite,
        acceptedBy: user._id,
      },
    );

    // WHY: Issue a fresh token so the updated role is effective immediately.
    const authToken = signToken(user);

    await writeAuditLog({
      businessId: invite.businessId,
      actorId: user._id,
      actorRole: user.role,
      action: "business_invite_accept",
      entityType: "user",
      entityId: user._id,
      message:
        "User accepted business invite",
      changes: {
        role: user.role,
        estateAssetId:
          user.estateAssetId,
      },
    });

    debug(
      "BUSINESS CONTROLLER: acceptInvite - success",
      {
        userId: user._id,
        role: user.role,
      },
    );

    return res.status(200).json({
      message:
        "Invite accepted successfully",
      user,
      token: authToken,
      role: user.role,
      estateAssetId: user.estateAssetId,
      businessId: user.businessId,
      agreementText:
        invite.agreementText || "",
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: acceptInvite - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/tenant/estate
 * Tenant-only: fetch assigned estate asset details for verification.
 */
async function getTenantEstate(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getTenantEstate - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (actor.role !== "tenant") {
      return res.status(403).json({
        error: "Tenant access required",
      });
    }

    if (!actor.estateAssetId) {
      return res.status(400).json({
        error:
          "Tenant is not assigned to an estate asset",
      });
    }

    let latestInvite =
      await businessInviteService.getLatestAcceptedInviteForUser(
        {
          businessId,
          userId: actor._id,
        },
      );
    // WHY: Decide if we need a secondary lookup for agreement text.
    const hasAgreement = Boolean(
      latestInvite?.agreementText &&
      latestInvite.agreementText
        .toString()
        .trim().length > 0,
    );
    if (!hasAgreement) {
      // WHY: Fallback to email-based lookup for legacy invites without acceptedBy.
      const fallbackInvite =
        await businessInviteService.getLatestInviteForEmail(
          {
            businessId,
            email: actor.email,
          },
        );
      if (
        fallbackInvite?.agreementText &&
        fallbackInvite.agreementText
          .toString()
          .trim().length > 0
      ) {
        latestInvite = fallbackInvite;
        debug(
          "BUSINESS CONTROLLER: getTenantEstate - agreement fallback",
          {
            actorId: actor._id,
            usedFallback: true,
          },
        );
      }
    }

    const estate =
      await businessTenantService.getTenantEstate(
        {
          businessId,
          estateAssetId:
            actor.estateAssetId,
        },
      );

    debug(
      "BUSINESS CONTROLLER: getTenantEstate - success",
      {
        actorId: actor._id,
        estateAssetId:
          actor.estateAssetId,
      },
    );

    return res.status(200).json({
      message:
        "Estate fetched successfully",
      estate,
      agreementText:
        latestInvite?.agreementText ||
        "",
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getTenantEstate - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/tenant/contact-document
 * Tenant-only: upload a reference/guarantor supporting document.
 */
async function uploadTenantContactDocument(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: uploadTenantContactDocument - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (actor.role !== "tenant") {
      return res.status(403).json({
        error: "Tenant access required",
      });
    }

    if (!req.file) {
      return res.status(400).json({
        error:
          "Document file is required",
      });
    }

    const uploadResult =
      await tenantContactDocumentService.uploadTenantContactDocument(
        {
          businessId,
          actor: {
            id: actor._id,
            role: actor.role,
          },
          file: req.file,
          source: "tenant_verification",
        },
      );

    debug(
      "BUSINESS CONTROLLER: uploadTenantContactDocument - success",
      {
        actorId: actor._id,
        hasUrl: Boolean(
          uploadResult?.url,
        ),
      },
    );

    return res.status(200).json({
      message:
        "Document uploaded successfully",
      documentUrl: uploadResult.url,
      documentPublicId:
        uploadResult.publicId,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: uploadTenantContactDocument - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/tenant/verify
 * Tenant-only: submit verification details for the assigned estate.
 */
async function submitTenantVerification(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: submitTenantVerification - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (actor.role !== "tenant") {
      return res.status(403).json({
        error: "Tenant access required",
      });
    }

    if (!actor.isNinVerified) {
      return res.status(400).json({
        error:
          "Tenant must be NIN verified",
      });
    }

    if (!actor.estateAssetId) {
      return res.status(400).json({
        error:
          "Tenant is not assigned to an estate asset",
      });
    }

    const application =
      await businessTenantService.createTenantApplication(
        {
          businessId,
          estateAssetId:
            actor.estateAssetId,
          actor,
          payload: req.body,
        },
      );

    debug(
      "BUSINESS CONTROLLER: submitTenantVerification - success",
      {
        actorId: actor._id,
        applicationId: application._id,
      },
    );

    return res.status(201).json({
      message:
        "Tenant verification submitted successfully",
      application,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: submitTenantVerification - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/tenant/application
 * Tenant-only: fetch the latest application for the assigned estate.
 */
async function getTenantApplication(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getTenantApplication - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (actor.role !== "tenant") {
      return res.status(403).json({
        error: "Tenant access required",
      });
    }

    if (!actor.estateAssetId) {
      return res.status(400).json({
        error:
          "Tenant is not assigned to an estate asset",
      });
    }

    let latestInvite =
      await businessInviteService.getLatestAcceptedInviteForUser(
        {
          businessId,
          userId: actor._id,
        },
      );
    // WHY: Decide if we need a secondary lookup for agreement text.
    const hasAgreement = Boolean(
      latestInvite?.agreementText &&
      latestInvite.agreementText
        .toString()
        .trim().length > 0,
    );
    if (!hasAgreement) {
      // WHY: Ensure tenant sees agreement even if accepted invite metadata is missing.
      const fallbackInvite =
        await businessInviteService.getLatestInviteForEmail(
          {
            businessId,
            email: actor.email,
          },
        );
      if (
        fallbackInvite?.agreementText &&
        fallbackInvite.agreementText
          .toString()
          .trim().length > 0
      ) {
        latestInvite = fallbackInvite;
        debug(
          "BUSINESS CONTROLLER: getTenantApplication - agreement fallback",
          {
            actorId: actor._id,
            usedFallback: true,
          },
        );
      }
    }

    const application =
      await businessTenantService.getTenantApplicationForTenant(
        {
          businessId,
          estateAssetId:
            actor.estateAssetId,
          tenantUserId: actor._id,
        },
      );

    debug(
      "BUSINESS CONTROLLER: getTenantApplication - success",
      {
        actorId: actor._id,
        hasApplication: Boolean(
          application,
        ),
      },
    );

    return res.status(200).json({
      message:
        application ?
          "Tenant application fetched successfully"
        : "No tenant application found",
      application,
      agreementText:
        application?.agreementText ||
        latestInvite?.agreementText ||
        "",
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getTenantApplication - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /tenant/summary
 *
 * WHAT:
 * - Returns the current tenant application summary + coverage fields.
 *
 * WHY:
 * - Lets the tenant dashboard show status, paidThrough, and nextDue without
 *   another verify call.
 */
async function getTenantSummary(
  req,
  res,
) {
  const requestId =
    req.headers?.["x-request-id"] ||
    req.requestId ||
    req.id ||
    "unknown";
  const route = `${req.method} ${req.originalUrl || req.url}`;
  const operation = "TenantSummaryRead";
  const intent =
    "load tenant payment summary";
  const logStep = (
    step,
    extra = {},
  ) => {
    debug("TENANT_SUMMARY", {
      requestId,
      route,
      step,
      layer: "controller",
      operation,
      intent,
      businessId_present: Boolean(
        extra.businessId,
      ),
      businessId:
        extra.businessId || null,
      userRole:
        extra.userRole ||
        req.user?.role ||
        "unknown",
      ...extra,
    });
  };

  logStep("ROUTE_IN", {
    actorId: req.user?.sub,
    userRole: req.user?.role,
  });

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    logStep("AUTH_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    if (!actor.estateAssetId) {
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification: "INVALID_INPUT",
        error_code:
          "TENANT_SUMMARY_ESTATE_ASSET_MISSING",
        resolution_hint:
          "Assign the tenant to an estate asset before loading the summary.",
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "INVALID_INPUT",
          error_code:
            "TENANT_SUMMARY_ESTATE_ASSET_MISSING",
          resolution_hint:
            "Assign the tenant to an estate asset before loading the summary.",
        },
      );
      return res.status(400).json({
        message:
          "Tenant is not assigned to an estate asset",
        error:
          "Tenant is not assigned to an estate asset",
        classification: "INVALID_INPUT",
        error_code:
          "TENANT_SUMMARY_ESTATE_ASSET_MISSING",
        requestId,
        resolution_hint:
          "Assign the tenant to an estate asset before loading the summary.",
      });
    }

    logStep("SERVICE_START", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    logStep("DB_QUERY_START", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query:
        "tenant_application_for_tenant",
    });

    const application =
      await businessTenantService.getTenantApplicationForTenant(
        {
          businessId,
          estateAssetId:
            actor.estateAssetId,
          tenantUserId: actor._id,
        },
      );

    if (!application) {
      logStep("DB_QUERY_OK", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        query:
          "tenant_application_for_tenant",
        found: false,
      });
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification: "INVALID_INPUT",
        error_code:
          "TENANT_SUMMARY_APPLICATION_NOT_FOUND",
        resolution_hint:
          "Submit a tenant verification before requesting the summary.",
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "INVALID_INPUT",
          error_code:
            "TENANT_SUMMARY_APPLICATION_NOT_FOUND",
          resolution_hint:
            "Submit a tenant verification before requesting the summary.",
        },
      );
      return res.status(404).json({
        message:
          "Tenant application not found",
        error:
          "Tenant application not found",
        classification: "INVALID_INPUT",
        error_code:
          "TENANT_SUMMARY_APPLICATION_NOT_FOUND",
        requestId,
        resolution_hint:
          "Submit a tenant verification before requesting the summary.",
      });
    }

    logStep("DB_QUERY_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query:
        "tenant_application_for_tenant",
      found: true,
      applicationId: application._id,
    });

    logStep("VALIDATION_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    const summary = {
      applicationId: application._id,
      status: application.status,
      agreementStatus:
        application.agreementStatus,
      agreementSigned:
        application.agreementSigned,
      agreementText:
        application.agreementText,
      agreementAcceptedAt:
        application.agreementAcceptedAt,
      paymentStatus:
        application.paymentStatus,
      paidThroughDate:
        application.paidThroughDate,
      nextDueDate:
        application.nextDueDate,
      lastRentPaymentAt:
        application.lastRentPaymentAt,
      moveInDate:
        application.moveInDate,
      rentAmount:
        application.rentAmount,
      rentPeriod:
        application.rentPeriod,
      unitType: application.unitType,
      unitCount: application.unitCount,
      estateAssetId:
        application.estateAssetId,
      coverage: {
        paidThroughDate:
          application.paidThroughDate,
        nextDueDate:
          application.nextDueDate,
      },
      paymentsSummary: {
        totalPaidKoboYtd: 0,
        totalPaidKoboAllTime: 0,
        paymentsThisYear: 0,
        lastPaidAt:
          application.lastRentPaymentAt,
      },
    };

    // WHY: Summarize tenant rent payments for quick dashboard chips and yearly limits.
    const { startOfYear, endOfYear } =
      getCalendarYearBounds();
    logStep("DB_QUERY_START", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query: "tenant_rent_payments",
    });

    const payments = await Payment.find(
      {
        businessId,
        tenantApplication:
          application._id,
        purpose: "tenant_rent",
        status: "success",
      },
    )
      .select(
        "amount processedAt createdAt periodCount",
      )
      .lean();

    logStep("DB_QUERY_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query: "tenant_rent_payments",
      paymentCount: payments.length,
    });

    let totalPaidAll = 0;
    let totalPaidYtd = 0;
    let paymentsThisYear = 0;
    let termPaidPeriodsYtd = 0;
    let missingPeriodCount = 0;
    let lastPaidAt =
      application.lastRentPaymentAt;

    payments.forEach((p) => {
      totalPaidAll += p.amount || 0;
      const paymentDate =
        p.createdAt || p.processedAt;
      if (
        paymentDate &&
        paymentDate >= startOfYear &&
        paymentDate <= endOfYear
      ) {
        totalPaidYtd += p.amount || 0;
        paymentsThisYear += 1;
        if (
          Number.isFinite(p.periodCount)
        ) {
          termPaidPeriodsYtd +=
            Math.max(
              0,
              Math.floor(p.periodCount),
            );
        } else {
          missingPeriodCount += 1;
        }
      }
      if (
        paymentDate &&
        (!lastPaidAt ||
          paymentDate > lastPaidAt)
      ) {
        lastPaidAt = paymentDate;
      }
    });

    summary.paymentsSummary = {
      totalPaidKoboYtd: totalPaidYtd,
      totalPaidKoboAllTime:
        totalPaidAll,
      paymentsThisYear,
      lastPaidAt,
    };

    const termSummary =
      computeTenantYearlyTerm({
        rentPeriod:
          application.rentPeriod,
        termPaidPeriodsYtd,
        paymentsThisYear,
      });

    summary.termTotalPeriods =
      termSummary?.termTotalPeriods ??
      null;
    summary.termPaidPeriodsYtd =
      termSummary?.termPaidPeriodsYtd ??
      null;
    summary.termRemainingPeriodsYtd =
      termSummary?.termRemainingPeriodsYtd ??
      null;
    summary.isFinalPayment =
      termSummary?.isFinalPayment ??
      false;
    summary.isYearComplete =
      termSummary?.isYearComplete ??
      false;
    summary.remainingPeriods =
      termSummary?.termRemainingPeriodsYtd ??
      null;

    // WHY: Overdue status should not change yearly rules, only inform the UI.
    summary.isOverdue = Boolean(
      summary.nextDueDate &&
      new Date() > summary.nextDueDate,
    );

    debug(
      "BUSINESS CONTROLLER: getTenantSummary - success",
      {
        applicationId: application._id,
        status: application.status,
        paymentStatus:
          application.paymentStatus,
        paymentsThisYear,
        totalPaidKoboYtd: totalPaidYtd,
        termRemainingPeriodsYtd:
          termSummary?.termRemainingPeriodsYtd ??
          "unknown",
        termPaidPeriodsYtd,
        missingPeriodCount,
      },
    );

    logStep("SERVICE_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    logStep("CONTROLLER_RESPONSE_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    return res.status(200).json({
      message: "Tenant summary fetched",
      summary,
    });
  } catch (err) {
    const message =
      err?.message ||
      "Unable to fetch tenant summary";
    logStep("SERVICE_FAIL", {
      actorId: req.user?.sub,
      classification:
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        "TENANT_SUMMARY_UNEXPECTED_FAILURE",
      resolution_hint:
        "Retry the request or contact support if it persists.",
      error_message: message,
    });
    logStep(
      "CONTROLLER_RESPONSE_FAIL",
      {
        actorId: req.user?.sub,
        classification:
          "UNKNOWN_PROVIDER_ERROR",
        error_code:
          "TENANT_SUMMARY_UNEXPECTED_FAILURE",
        resolution_hint:
          "Retry the request or contact support if it persists.",
        error_message: message,
      },
    );
    return res.status(400).json({
      message,
      error: message,
      classification:
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        "TENANT_SUMMARY_UNEXPECTED_FAILURE",
      requestId,
      resolution_hint:
        "Retry the request or contact support if it persists.",
    });
  }
}

/**
 * GET /business/tenant/:tenantId/payments
 *
 * WHAT:
 * - Returns payment history for a specific tenant (business owner/staff).
 *
 * WHY:
 * - Lets business owners see tenant receipts without overloading review screens.
 *
 * HOW:
 * - Loads the latest tenant application for the business.
 * - Fetches successful tenant rent payments and returns a summary.
 */
async function getBusinessTenantPayments(
  req,
  res,
) {
  const requestId =
    req.headers?.["x-request-id"] ||
    req.requestId ||
    req.id ||
    "unknown";
  const route = `${req.method} ${req.originalUrl || req.url}`;
  const operation =
    "BusinessTenantPaymentsRead";
  const intent =
    TENANT_PAYMENTS_INTENTS.BUSINESS;
  const logStep = (
    step,
    extra = {},
  ) => {
    debug("TENANT_PAYMENTS", {
      requestId,
      route,
      step,
      layer: "controller",
      operation,
      intent,
      businessId_present: Boolean(
        extra.businessId,
      ),
      businessId:
        extra.businessId || null,
      userRole:
        extra.userRole ||
        req.user?.role ||
        "unknown",
      ...extra,
    });
  };

  logStep("ROUTE_IN", {
    actorId: req.user?.sub,
    userRole: req.user?.role,
    tenantId: req.params?.tenantId,
  });

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    logStep("AUTH_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    if (
      actor.role !== "business_owner" &&
      actor.role !== "staff"
    ) {
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification:
          "AUTHENTICATION_ERROR",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ROLE_REQUIRED,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_BUSINESS_ROLE,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_ROLE_MISMATCH,
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "AUTHENTICATION_ERROR",
          error_code:
            TENANT_PAYMENTS_ERROR_CODES.TENANT_ROLE_REQUIRED,
          resolution_hint:
            TENANT_PAYMENTS_COPY.HINT_BUSINESS_ROLE,
          retry_skipped: true,
          retry_reason:
            TENANT_PAYMENTS_COPY.RETRY_ROLE_MISMATCH,
        },
      );
      return res.status(403).json({
        message:
          TENANT_PAYMENTS_COPY.BUSINESS_ACCESS_REQUIRED,
        error:
          TENANT_PAYMENTS_COPY.BUSINESS_ACCESS_REQUIRED,
        classification:
          "AUTHENTICATION_ERROR",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ROLE_REQUIRED,
        requestId,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_BUSINESS_ROLE,
      });
    }

    const tenantId =
      req.params?.tenantId
        ?.toString()
        .trim();
    if (!tenantId) {
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ID_REQUIRED,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ID_REQUIRED,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_TENANT_ID_MISSING,
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "MISSING_REQUIRED_FIELD",
          error_code:
            TENANT_PAYMENTS_ERROR_CODES.TENANT_ID_REQUIRED,
          resolution_hint:
            TENANT_PAYMENTS_COPY.HINT_TENANT_ID_REQUIRED,
          retry_skipped: true,
          retry_reason:
            TENANT_PAYMENTS_COPY.RETRY_TENANT_ID_MISSING,
        },
      );
      return res.status(400).json({
        message:
          TENANT_PAYMENTS_COPY.TENANT_ID_REQUIRED,
        error:
          TENANT_PAYMENTS_COPY.TENANT_ID_REQUIRED,
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ID_REQUIRED,
        requestId,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ID_REQUIRED,
      });
    }

    if (
      !mongoose.Types.ObjectId.isValid(
        tenantId,
      )
    ) {
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ID_INVALID,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ID_INVALID,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_TENANT_ID_INVALID,
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "INVALID_INPUT",
          error_code:
            TENANT_PAYMENTS_ERROR_CODES.TENANT_ID_INVALID,
          resolution_hint:
            TENANT_PAYMENTS_COPY.HINT_TENANT_ID_INVALID,
          retry_skipped: true,
          retry_reason:
            TENANT_PAYMENTS_COPY.RETRY_TENANT_ID_INVALID,
        },
      );
      return res.status(400).json({
        message:
          TENANT_PAYMENTS_COPY.TENANT_ID_INVALID,
        error:
          TENANT_PAYMENTS_COPY.TENANT_ID_INVALID,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ID_INVALID,
        requestId,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ID_INVALID,
      });
    }

    logStep("SERVICE_START", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      tenantId,
    });

    logStep("DB_QUERY_START", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query:
        "tenant_application_for_payment_history",
      tenantId,
    });

    const application =
      await findTenantApplicationForPayments(
        {
          businessId,
          tenantUserId: tenantId,
          estateAssetId:
            isEstateScopedStaff(actor) ?
              actor.estateAssetId
            : null,
        },
      );

    if (!application) {
      logStep("DB_QUERY_OK", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        query:
          "tenant_application_for_payment_history",
        tenantId,
        found: false,
      });
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.APPLICATION_NOT_FOUND,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_APPLICATION_BUSINESS,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_APPLICATION_MISSING,
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "INVALID_INPUT",
          error_code:
            TENANT_PAYMENTS_ERROR_CODES.APPLICATION_NOT_FOUND,
          resolution_hint:
            TENANT_PAYMENTS_COPY.HINT_APPLICATION_BUSINESS,
          retry_skipped: true,
          retry_reason:
            TENANT_PAYMENTS_COPY.RETRY_APPLICATION_MISSING,
        },
      );
      return res.status(404).json({
        message:
          TENANT_PAYMENTS_COPY.APPLICATION_NOT_FOUND,
        error:
          TENANT_PAYMENTS_COPY.APPLICATION_NOT_FOUND,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.APPLICATION_NOT_FOUND,
        requestId,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_APPLICATION_BUSINESS,
      });
    }

    logStep("DB_QUERY_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query:
        "tenant_application_for_payment_history",
      tenantId,
      found: true,
      applicationId: application._id,
    });

    logStep("VALIDATION_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      tenantId,
    });

    const { items, summary } =
      await loadTenantPaymentHistory({
        businessId,
        applicationId: application._id,
        rentPeriod:
          application.rentPeriod,
        actorId: actor._id,
        userRole: actor.role,
        logStep,
      });

    const isOverdue = Boolean(
      application.nextDueDate &&
      new Date() >
        application.nextDueDate,
    );
    const yearlyRentTotalKobo =
      computeYearlyRentTotal({
        rentPeriod:
          application.rentPeriod,
        rentAmount:
          application.rentAmount,
        unitCount:
          application.unitCount,
      });
    const yearlyRentPerUnitKobo =
      computeYearlyRentTotalPerUnit({
        rentPeriod:
          application.rentPeriod,
        rentAmount:
          application.rentAmount,
      });

    logStep("SERVICE_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      paymentsThisYear:
        summary.paymentsThisYear,
      paidPeriodsYtd:
        summary.paidPeriodsYtd,
      remainingPeriodsYtd:
        summary.remainingPeriodsYtd,
      missingPeriodCount:
        summary.missingPeriodCount,
      totalPaidKoboYtd:
        summary.totalPaidKoboYtd,
      totalPaidKoboAllTime:
        summary.totalPaidKoboAllTime,
      yearlyRentTotalKobo,
      yearlyRentPerUnitKobo,
    });

    logStep("CONTROLLER_RESPONSE_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    return res.status(200).json({
      payments: items,
      summary: {
        paymentsThisYear:
          summary.paymentsThisYear,
        paidPeriodsYtd:
          summary.paidPeriodsYtd,
        remainingPeriodsYtd:
          summary.remainingPeriodsYtd,
        isOverdue,
        totalPaidKoboYtd:
          summary.totalPaidKoboYtd,
        totalPaidKoboAllTime:
          summary.totalPaidKoboAllTime,
        yearlyRentTotalKobo,
        yearlyRentPerUnitKobo,
      },
    });
  } catch (err) {
    const message =
      err?.message ||
      TENANT_PAYMENTS_COPY.UNABLE_LOAD_BUSINESS;
    logStep("SERVICE_FAIL", {
      actorId: req.user?.sub,
      classification:
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        TENANT_PAYMENTS_ERROR_CODES.UNEXPECTED_FAILURE,
      resolution_hint:
        TENANT_PAYMENTS_COPY.HINT_RETRY_SUPPORT,
      error_message: message,
      retry_skipped: true,
      retry_reason:
        TENANT_PAYMENTS_COPY.RETRY_UNEXPECTED,
    });
    logStep(
      "CONTROLLER_RESPONSE_FAIL",
      {
        actorId: req.user?.sub,
        classification:
          "UNKNOWN_PROVIDER_ERROR",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.UNEXPECTED_FAILURE,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_RETRY_SUPPORT,
        error_message: message,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_UNEXPECTED,
      },
    );
    return res.status(400).json({
      message,
      error: message,
      classification:
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        TENANT_PAYMENTS_ERROR_CODES.UNEXPECTED_FAILURE,
      requestId,
      resolution_hint:
        TENANT_PAYMENTS_COPY.HINT_RETRY_SUPPORT,
    });
  }
}

/**
 * GET /business/tenant/payments
 *
 * WHAT:
 * - Returns payment history for the authenticated tenant.
 *
 * WHY:
 * - Tenants need a dedicated receipts list without opening verification.
 *
 * HOW:
 * - Loads the tenant's latest application.
 * - Returns successful rent payments and summary fields for the year.
 */
async function getTenantPayments(
  req,
  res,
) {
  const requestId =
    req.headers?.["x-request-id"] ||
    req.requestId ||
    req.id ||
    "unknown";
  const route = `${req.method} ${req.originalUrl || req.url}`;
  const operation =
    "TenantPaymentsRead";
  const intent =
    TENANT_PAYMENTS_INTENTS.TENANT;
  const logStep = (
    step,
    extra = {},
  ) => {
    debug("TENANT_PAYMENTS", {
      requestId,
      route,
      step,
      layer: "controller",
      operation,
      intent,
      businessId_present: Boolean(
        extra.businessId,
      ),
      businessId:
        extra.businessId || null,
      userRole:
        extra.userRole ||
        req.user?.role ||
        "unknown",
      ...extra,
    });
  };

  logStep("ROUTE_IN", {
    actorId: req.user?.sub,
    userRole: req.user?.role,
  });

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    logStep("AUTH_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    if (actor.role !== "tenant") {
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification:
          "AUTHENTICATION_ERROR",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ROLE_REQUIRED,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ROLE,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_ROLE_MISMATCH,
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "AUTHENTICATION_ERROR",
          error_code:
            TENANT_PAYMENTS_ERROR_CODES.TENANT_ROLE_REQUIRED,
          resolution_hint:
            TENANT_PAYMENTS_COPY.HINT_TENANT_ROLE,
          retry_skipped: true,
          retry_reason:
            TENANT_PAYMENTS_COPY.RETRY_ROLE_MISMATCH,
        },
      );
      return res.status(403).json({
        message:
          TENANT_PAYMENTS_COPY.TENANT_ACCESS_REQUIRED,
        error:
          TENANT_PAYMENTS_COPY.TENANT_ACCESS_REQUIRED,
        classification:
          "AUTHENTICATION_ERROR",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ROLE_REQUIRED,
        requestId,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ROLE,
      });
    }

    if (!actor.estateAssetId) {
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ESTATE_MISSING,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ESTATE,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_ESTATE_MISSING,
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "INVALID_INPUT",
          error_code:
            TENANT_PAYMENTS_ERROR_CODES.TENANT_ESTATE_MISSING,
          resolution_hint:
            TENANT_PAYMENTS_COPY.HINT_TENANT_ESTATE,
          retry_skipped: true,
          retry_reason:
            TENANT_PAYMENTS_COPY.RETRY_ESTATE_MISSING,
        },
      );
      return res.status(400).json({
        message:
          TENANT_PAYMENTS_COPY.TENANT_ESTATE_MISSING,
        error:
          TENANT_PAYMENTS_COPY.TENANT_ESTATE_MISSING,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.TENANT_ESTATE_MISSING,
        requestId,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_TENANT_ESTATE,
      });
    }

    logStep("SERVICE_START", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    logStep("DB_QUERY_START", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query:
        "tenant_application_for_tenant",
    });

    const application =
      await businessTenantService.getTenantApplicationForTenant(
        {
          businessId,
          estateAssetId:
            actor.estateAssetId,
          tenantUserId: actor._id,
        },
      );

    if (!application) {
      logStep("DB_QUERY_OK", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        query:
          "tenant_application_for_tenant",
        found: false,
      });
      logStep("VALIDATION_FAIL", {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.APPLICATION_NOT_FOUND,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_APPLICATION_TENANT,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_APPLICATION_MISSING,
      });
      logStep(
        "CONTROLLER_RESPONSE_FAIL",
        {
          actorId: actor._id,
          businessId,
          userRole: actor.role,
          classification:
            "INVALID_INPUT",
          error_code:
            TENANT_PAYMENTS_ERROR_CODES.APPLICATION_NOT_FOUND,
          resolution_hint:
            TENANT_PAYMENTS_COPY.HINT_APPLICATION_TENANT,
          retry_skipped: true,
          retry_reason:
            TENANT_PAYMENTS_COPY.RETRY_APPLICATION_MISSING,
        },
      );
      return res.status(404).json({
        message:
          TENANT_PAYMENTS_COPY.APPLICATION_NOT_FOUND,
        error:
          TENANT_PAYMENTS_COPY.APPLICATION_NOT_FOUND,
        classification: "INVALID_INPUT",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.APPLICATION_NOT_FOUND,
        requestId,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_APPLICATION_TENANT,
      });
    }

    logStep("DB_QUERY_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      query:
        "tenant_application_for_tenant",
      found: true,
      applicationId: application._id,
    });

    logStep("VALIDATION_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    const { items, summary } =
      await loadTenantPaymentHistory({
        businessId,
        applicationId: application._id,
        rentPeriod:
          application.rentPeriod,
        actorId: actor._id,
        userRole: actor.role,
        logStep,
      });

    const isOverdue = Boolean(
      application.nextDueDate &&
      new Date() >
        application.nextDueDate,
    );
    const yearlyRentTotalKobo =
      computeYearlyRentTotal({
        rentPeriod:
          application.rentPeriod,
        rentAmount:
          application.rentAmount,
        unitCount:
          application.unitCount,
      });
    const yearlyRentPerUnitKobo =
      computeYearlyRentTotalPerUnit({
        rentPeriod:
          application.rentPeriod,
        rentAmount:
          application.rentAmount,
      });

    logStep("SERVICE_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
      paymentsThisYear:
        summary.paymentsThisYear,
      paidPeriodsYtd:
        summary.paidPeriodsYtd,
      remainingPeriodsYtd:
        summary.remainingPeriodsYtd,
      missingPeriodCount:
        summary.missingPeriodCount,
      totalPaidKoboYtd:
        summary.totalPaidKoboYtd,
      totalPaidKoboAllTime:
        summary.totalPaidKoboAllTime,
      yearlyRentTotalKobo,
      yearlyRentPerUnitKobo,
    });

    logStep("CONTROLLER_RESPONSE_OK", {
      actorId: actor._id,
      businessId,
      userRole: actor.role,
    });

    return res.status(200).json({
      payments: items,
      summary: {
        paymentsThisYear:
          summary.paymentsThisYear,
        paidPeriodsYtd:
          summary.paidPeriodsYtd,
        remainingPeriodsYtd:
          summary.remainingPeriodsYtd,
        isOverdue,
        totalPaidKoboYtd:
          summary.totalPaidKoboYtd,
        totalPaidKoboAllTime:
          summary.totalPaidKoboAllTime,
        yearlyRentTotalKobo,
        yearlyRentPerUnitKobo,
      },
    });
  } catch (err) {
    const message =
      err?.message ||
      TENANT_PAYMENTS_COPY.UNABLE_LOAD_TENANT;
    logStep("SERVICE_FAIL", {
      actorId: req.user?.sub,
      classification:
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        TENANT_PAYMENTS_ERROR_CODES.UNEXPECTED_FAILURE,
      resolution_hint:
        TENANT_PAYMENTS_COPY.HINT_RETRY_SUPPORT,
      error_message: message,
      retry_skipped: true,
      retry_reason:
        TENANT_PAYMENTS_COPY.RETRY_UNEXPECTED,
    });
    logStep(
      "CONTROLLER_RESPONSE_FAIL",
      {
        actorId: req.user?.sub,
        classification:
          "UNKNOWN_PROVIDER_ERROR",
        error_code:
          TENANT_PAYMENTS_ERROR_CODES.UNEXPECTED_FAILURE,
        resolution_hint:
          TENANT_PAYMENTS_COPY.HINT_RETRY_SUPPORT,
        error_message: message,
        retry_skipped: true,
        retry_reason:
          TENANT_PAYMENTS_COPY.RETRY_UNEXPECTED,
      },
    );
    return res.status(400).json({
      message,
      error: message,
      classification:
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        TENANT_PAYMENTS_ERROR_CODES.UNEXPECTED_FAILURE,
      requestId,
      resolution_hint:
        TENANT_PAYMENTS_COPY.HINT_RETRY_SUPPORT,
    });
  }
}

/**
 * PATCH /business/tenant/application
 * Tenant-only: update a pending application for the assigned estate.
 */
async function updateTenantApplication(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateTenantApplication - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (actor.role !== "tenant") {
      return res.status(403).json({
        error: "Tenant access required",
      });
    }

    if (!actor.isNinVerified) {
      return res.status(400).json({
        error:
          "Tenant must be NIN verified",
      });
    }

    if (!actor.estateAssetId) {
      return res.status(400).json({
        error:
          "Tenant is not assigned to an estate asset",
      });
    }

    const application =
      await businessTenantService.updateTenantApplicationForTenant(
        {
          businessId,
          estateAssetId:
            actor.estateAssetId,
          tenantUserId: actor._id,
          actor,
          payload: req.body,
        },
      );

    debug(
      "BUSINESS CONTROLLER: updateTenantApplication - success",
      {
        actorId: actor._id,
        applicationId: application?._id,
      },
    );

    return res.status(200).json({
      message:
        "Tenant application updated successfully",
      application,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateTenantApplication - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/tenant/applications
 * Owner/staff: list tenant applications (optional estate/status filter).
 */
async function listTenantApplications(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listTenantApplications - entry",
    {
      actorId: req.user?.sub,
      hasEstate: Boolean(
        req.query?.estateAssetId,
      ),
      hasStatus: Boolean(
        req.query?.status,
      ),
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const requestedEstate =
      req.query?.estateAssetId
        ?.toString()
        .trim() || null;
    const requestedStatus =
      req.query?.status
        ?.toString()
        .trim() || null;

    let estateAssetId = requestedEstate;

    if (isEstateScopedStaff(actor)) {
      // WHY: Estate-scoped staff can only see their assigned estate.
      if (
        requestedEstate &&
        requestedEstate.toString() !==
          actor.estateAssetId.toString()
      ) {
        return res.status(403).json({
          error:
            "Estate-scoped staff can only view their assigned estate applications",
        });
      }
      estateAssetId =
        actor.estateAssetId;
    }

    const result =
      await businessTenantService.listTenantApplications(
        {
          businessId,
          estateAssetId,
          status: requestedStatus,
          limit: req.query?.limit,
          page: req.query?.page,
        },
      );

    debug(
      "BUSINESS CONTROLLER: listTenantApplications - success",
      {
        count:
          result.applications.length,
        total: result.total,
      },
    );

    return res.status(200).json({
      message:
        "Tenant applications fetched successfully",
      ...result,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listTenantApplications - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/tenant/applications/:id
 * Owner/staff: fetch a single tenant application for review.
 */
async function getTenantApplicationDetail(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getTenantApplicationDetail - entry",
    {
      actorId: req.user?.sub,
      applicationId: req.params?.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const applicationId = req.params?.id
      ?.toString()
      .trim();
    if (!applicationId) {
      return res.status(400).json({
        error:
          "Application id is required",
      });
    }

    const application =
      await businessTenantService.getTenantApplicationDetail(
        {
          businessId,
          applicationId,
        },
      );

    if (isEstateScopedStaff(actor)) {
      // WHY: Estate-scoped staff can only review their estate.
      const estateId =
        application?.estateAssetId
          ?._id ||
        application?.estateAssetId;
      if (
        estateId &&
        estateId.toString() !==
          actor.estateAssetId.toString()
      ) {
        return res.status(403).json({
          error:
            "Estate-scoped staff can only view their assigned estate applications",
        });
      }
    }

    debug(
      "BUSINESS CONTROLLER: getTenantApplicationDetail - success",
      {
        applicationId: application._id,
      },
    );

    return res.status(200).json({
      message:
        "Tenant application fetched successfully",
      application,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getTenantApplicationDetail - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/tenant/applications/:id/verify-contact
 * Owner/staff: verify a reference or guarantor on a tenant application.
 */
async function verifyTenantContact(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: verifyTenantContact - entry",
    {
      actorId: req.user?.sub,
      applicationId: req.params?.id,
      type: req.body?.type,
      status: req.body?.status,
      index: req.body?.index,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const applicationId = req.params?.id
      ?.toString()
      .trim();
    if (!applicationId) {
      return res.status(400).json({
        error:
          "Application id is required",
      });
    }

    // WHY: Estate-scoped staff can only verify contacts for their estate.
    const application =
      await businessTenantService.getTenantApplicationDetail(
        {
          businessId,
          applicationId,
        },
      );

    if (isEstateScopedStaff(actor)) {
      const estateId =
        application?.estateAssetId
          ?._id ||
        application?.estateAssetId;
      if (
        estateId &&
        estateId.toString() !==
          actor.estateAssetId.toString()
      ) {
        return res.status(403).json({
          error:
            "Estate-scoped staff can only verify contacts for their assigned estate",
        });
      }
    }

    const updated =
      await businessTenantService.verifyTenantContact(
        {
          businessId,
          applicationId,
          actorId: actor._id,
          type: req.body?.type
            ?.toString()
            .trim(),
          status: req.body?.status
            ?.toString()
            .trim(),
          index: req.body?.index,
          note: req.body?.note
            ?.toString()
            .trim(),
        },
      );

    debug(
      "BUSINESS CONTROLLER: verifyTenantContact - success",
      {
        applicationId: updated._id,
        type: req.body?.type,
        status: req.body?.status,
      },
    );

    return res.status(200).json({
      message:
        "Tenant contact verified successfully",
      application: updated,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: verifyTenantContact - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/users/lookup?userId=... or ?email=... or ?phone=...
 * Business-owner only: find a user by id/email/phone for role assignment.
 */
async function lookupUser(req, res) {
  debug(
    "BUSINESS CONTROLLER: lookupUser - entry",
    {
      actorId: req.user?.sub,
      hasId: Boolean(
        req.query?.id ||
        req.query?.userId,
      ),
      hasEmail: Boolean(
        req.query?.email,
      ),
      hasPhone: Boolean(
        req.query?.phone,
      ),
    },
  );

  try {
    const rawId =
      req.query?.id
        ?.toString()
        .trim() ||
      req.query?.userId
        ?.toString()
        .trim() ||
      null;
    const email =
      req.query?.email
        ?.toString()
        .trim()
        .toLowerCase() || null;
    const phone =
      req.query?.phone
        ?.toString()
        .trim() || null;

    if (!rawId && !email && !phone) {
      return res.status(400).json({
        error:
          "Provide userId, email, or phone to lookup a user",
      });
    }

    // WHY: Prefer id lookup when supplied for deterministic matches.
    let user = null;
    if (rawId) {
      if (
        !mongoose.Types.ObjectId.isValid(
          rawId,
        )
      ) {
        return res.status(400).json({
          error: "Invalid user id",
        });
      }
      user = await User.findById(rawId)
        .select(
          "name email phone role businessId isNinVerified estateAssetId",
        )
        .lean();
    } else {
      // WHY: Fall back to email or phone lookup for quick UX searches.
      const query = {};
      if (email) {
        query.email = email;
      } else {
        query.phone = phone;
      }

      user = await User.findOne(query)
        .select(
          "name email phone role businessId isNinVerified estateAssetId",
        )
        .lean();
    }

    if (!user) {
      return res.status(404).json({
        error: "User not found",
      });
    }

    debug(
      "BUSINESS CONTROLLER: lookupUser - success",
      {
        userId: user._id,
        role: user.role,
        isNinVerified:
          user.isNinVerified,
      },
    );

    return res.status(200).json({
      message: "User found",
      user,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: lookupUser - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function getAnalyticsSummary(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: analytics summary - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const summary =
      await businessAnalyticsService.getAnalyticsSummary(
        {
          businessId,
        },
      );

    return res.status(200).json({
      message:
        "Analytics summary fetched successfully",
      summary,
      generatedAt:
        new Date().toISOString(),
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: analytics summary - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function getAnalyticsEvents(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: analytics events - entry",
    {
      actorId: req.user?.sub,
      query: req.query,
    },
  );

  try {
    const { businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const events =
      await businessAnalyticsService.getAnalyticsEvents(
        {
          businessId,
          days: req.query?.days,
          eventType:
            req.query?.eventType,
        },
      );

    return res.status(200).json({
      message:
        "Analytics events fetched successfully",
      ...events,
      generatedAt:
        new Date().toISOString(),
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: analytics events - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/analytics/estate/:estateAssetId
 *
 * WHAT:
 * - Estate-level KPIs (tenants + collections) for owner/staff dashboards.
 */
async function getEstateAnalytics(
  req,
  res,
) {
  const { estateAssetId } = req.params;
  debug(
    "BUSINESS CONTROLLER: getEstateAnalytics - entry",
    {
      actorId: req.user?.sub,
      estateAssetId,
    },
  );

  try {
    const { businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const analytics =
      await businessAnalyticsService.getEstateAnalytics(
        {
          businessId,
          estateAssetId,
        },
      );

    debug(
      "BUSINESS CONTROLLER: getEstateAnalytics - success",
      {
        estateAssetId,
        active:
          analytics?.tenants?.active,
      },
    );

    return res.status(200).json({
      message:
        "Estate analytics fetched successfully",
      analytics,
      generatedAt:
        new Date().toISOString(),
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getEstateAnalytics - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function approveTenantApplication(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: approveTenantApplication - entry",
    {
      actorId: req.user?.sub,
      applicationId: req.params?.id,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const applicationId = req.params?.id
      ?.toString()
      .trim();
    if (!applicationId) {
      return res.status(400).json({
        error:
          "Application id is required",
      });
    }

    // WHY: Estate-scoped staff can only approve for their estate.
    const application =
      await businessTenantService.getTenantApplicationDetail(
        {
          businessId,
          applicationId,
        },
      );

    if (isEstateScopedStaff(actor)) {
      const estateId =
        application?.estateAssetId
          ?._id ||
        application?.estateAssetId;
      if (
        estateId &&
        estateId.toString() !==
          actor.estateAssetId.toString()
      ) {
        return res.status(403).json({
          error:
            "Estate-scoped staff can only approve applications for their assigned estate",
        });
      }
    }

    const updatedApplication =
      await businessTenantService.approveTenantApplication(
        {
          businessId,
          applicationId,
          actorId: actor._id,
          actorRole: actor.role,
        },
      );

    debug(
      "BUSINESS CONTROLLER: approveTenantApplication - success",
      {
        applicationId:
          updatedApplication._id,
      },
    );

    return res.status(200).json({
      message:
        "Tenant application approved successfully",
      application: updatedApplication,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: approveTenantApplication - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * PAYMENT TOGGLE
 */
async function togglePaymentStatus(
  req,
  res,
) {
  // TODO: Implement togglePaymentStatus
  debug(
    "BUSINESS CONTROLLER: togglePaymentStatus - entry",
    {
      actorId: req.user?.sub,
      applicationId: req.params?.id,
    },
  );
  return res.status(501).json({
    message: "Not Implemented",
  });
}

/**
 * VERIFY CONTACT
 */
async function verifyContact(req, res) {
  // TODO: This route seems redundant with verifyTenantContact
  debug(
    "BUSINESS CONTROLLER: verifyContact - entry",
    {
      actorId: req.user?.sub,
      tenantId: req.params?.tenantId,
    },
  );
  return res.status(501).json({
    message: "Not Implemented",
  });
}

/**
 * CREATE PAYMENT INTENT
 */
async function createPaymentIntent(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: createPaymentIntent - entry",
    {
      actorId: req.user?.sub,
      tenantId: req.params?.tenantId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (actor.role !== "tenant") {
      return res.status(403).json({
        error: "Tenant access required",
      });
    }

    const tenantId =
      req.params?.tenantId
        ?.toString()
        .trim();
    if (!tenantId) {
      return res.status(400).json({
        error: "Tenant id is required",
      });
    }

    // WHY: Tenants can only create payment intents for themselves.
    if (
      tenantId !== actor._id.toString()
    ) {
      return res.status(403).json({
        error: "Tenant mismatch",
      });
    }

    if (!actor.estateAssetId) {
      return res.status(400).json({
        error:
          "Tenant is not assigned to an estate asset",
      });
    }

    const application =
      await businessTenantService.getTenantApplicationForTenant(
        {
          businessId,
          estateAssetId:
            actor.estateAssetId,
          tenantUserId: actor._id,
        },
      );

    if (!application) {
      return res.status(400).json({
        error:
          "Tenant application not found",
      });
    }

    const yearsToPay = Number(
      req.body?.yearsToPay || 1,
    );
    // WHY: Frontend may send periodCount (months or quarters) instead of yearsToPay.
    const periodCount =
      req.body?.periodCount != null ?
        Number(req.body.periodCount)
      : undefined;

    const callbackUrl =
      req.body?.callbackUrl
        ?.toString()
        .trim() || "";

    const intent =
      await paymentService.createTenantPaymentIntent(
        {
          businessId,
          applicationId:
            application._id,
          tenantUserId: actor._id,
          actorId: actor._id,
          actorRole: actor.role,
          yearsToPay,
          periodCount,
          callbackUrl,
        },
      );

    debug(
      "BUSINESS CONTROLLER: createPaymentIntent - success",
      {
        actorId: actor._id,
        paymentId: intent?.payment?._id,
      },
    );

    return res.status(201).json({
      message:
        "Tenant payment intent created successfully",
      payment: intent?.payment,
      authorizationUrl:
        intent?.authorizationUrl,
      reference: intent?.reference,
      accessCode: intent?.accessCode,
      coverage: {
        coversFrom:
          intent?.payment?.coversFrom,
        coversTo:
          intent?.payment?.coversTo,
        rentPeriod:
          intent?.payment?.rentPeriod,
        periodCount:
          intent?.payment?.periodCount,
        requestedYearsToPay: yearsToPay,
        requestedPeriodCount:
          intent?.payment?.rawEvent
            ?.requestedPeriodCount,
        autoReduced:
          intent?.payment?.rawEvent
            ?.autoReduced || false,
      },
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: createPaymentIntent - error",
      {
        actorId: req.user?.sub,
        tenantId: req.params?.tenantId,
        reason: err.message,
        next: "Ensure tenant is approved and unpaid before requesting payment",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * PAYSTACK WEBHOOK
 */
async function handlePaystackWebhook(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: handlePaystackWebhook - entry",
    { hasBody: Boolean(req.body) },
  );

  let event;
  try {
    if (!req.body) {
      debug(
        "BUSINESS CONTROLLER: handlePaystackWebhook - missing body",
        {
          classification:
            "MISSING_REQUIRED_FIELD",
          error_code:
            "PAYSTACK_WEBHOOK_BODY_MISSING",
          step: "VALIDATION_FAIL",
          resolution_hint:
            "Ensure the webhook is sent with a JSON body and raw parser.",
        },
      );
      return res.status(400).json({
        error:
          "Webhook body is required",
        errorCode:
          "PAYSTACK_WEBHOOK_BODY_MISSING",
      });
    }

    // WHY: Paystack signature verification requires raw body; parse manually.
    if (Buffer.isBuffer(req.body)) {
      event = JSON.parse(
        req.body.toString("utf8"),
      );
    } else {
      event = req.body;
    }
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: handlePaystackWebhook - invalid JSON",
      {
        classification:
          "PROVIDER_REJECTED_FORMAT",
        error_code:
          "PAYSTACK_WEBHOOK_INVALID_JSON",
        step: "PARSE_FAIL",
        resolution_hint:
          "Confirm raw body parsing and valid JSON payload from Paystack.",
      },
    );
    return res.status(400).json({
      error:
        "Invalid Paystack webhook payload",
      errorCode:
        "PAYSTACK_WEBHOOK_INVALID_JSON",
    });
  }

  const reference =
    event?.data?.reference || "";
  debug(
    "BUSINESS CONTROLLER: handlePaystackWebhook - payload parsed",
    {
      eventType: event?.event,
      referenceSuffix:
        reference ?
          reference.slice(-6)
        : null,
    },
  );

  try {
    const result =
      await paymentService.processPaystackEvent(
        event,
      );

    debug(
      "BUSINESS CONTROLLER: handlePaystackWebhook - success",
      {
        applied:
          result?.applied ?? false,
        idempotent:
          result?.idempotent ?? false,
      },
    );

    return res.status(200).json({
      message: "Webhook processed",
      applied: result?.applied ?? false,
      idempotent:
        result?.idempotent ?? false,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: handlePaystackWebhook - processing failed",
      {
        classification:
          "UNKNOWN_PROVIDER_ERROR",
        error_code:
          "PAYSTACK_WEBHOOK_PROCESSING_FAILED",
        step: "SERVICE_FAIL",
        resolution_hint:
          "Check payment logs and Paystack event payload.",
        message: err?.message,
      },
    );
    return res.status(500).json({
      error:
        "Webhook processing failed",
      errorCode:
        "PAYSTACK_WEBHOOK_PROCESSING_FAILED",
    });
  }
}

/**
 * DEV-ONLY PAY TOGGLE
 */
async function devMarkPaymentSucceeded(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: devMarkPaymentSucceeded - entry",
    {
      actorId: req.user?.sub,
      paymentId: req.params?.paymentId,
      devGateEnabled:
        process.env
          .DEV_MARK_RENT_PAID ===
        "true",
    },
  );

  try {
    if (
      process.env.NODE_ENV ===
      "production"
    ) {
      debug(
        "BUSINESS CONTROLLER: devMarkPaymentSucceeded - blocked",
        {
          step: "DEV_GATE_CHECK",
          errorCode:
            "DEV_PAY_TOGGLE_FORBIDDEN_IN_PRODUCTION",
          classification:
            "AUTHENTICATION_ERROR",
          reason:
            "Dev pay toggle disabled in production",
          resolution_hint:
            "Use Paystack verification in production",
        },
      );
      return res.status(403).json({
        error:
          "Dev pay toggle is disabled in production",
        errorCode:
          "DEV_PAY_TOGGLE_FORBIDDEN_IN_PRODUCTION",
      });
    }

    if (
      process.env.DEV_MARK_RENT_PAID !==
      "true"
    ) {
      debug(
        "BUSINESS CONTROLLER: devMarkPaymentSucceeded - blocked",
        {
          step: "DEV_GATE_CHECK",
          errorCode:
            "DEV_PAY_TOGGLE_DISABLED",
          classification:
            "MISSING_REQUIRED_FIELD",
          reason:
            "DEV_MARK_RENT_PAID is not enabled",
          resolution_hint:
            "Set DEV_MARK_RENT_PAID=true and restart server",
        },
      );
      return res.status(403).json({
        error:
          "Dev pay toggle is disabled",
        errorCode:
          "DEV_PAY_TOGGLE_DISABLED",
      });
    }

    const expectedSecret =
      process.env.DEV_PAYMENT_SECRET?.trim();
    const providedSecret = req.headers[
      "x-dev-secret"
    ]
      ?.toString()
      .trim();
    if (
      !expectedSecret ||
      providedSecret !== expectedSecret
    ) {
      debug(
        "BUSINESS CONTROLLER: devMarkPaymentSucceeded - blocked",
        {
          step: "DEV_GATE_CHECK",
          errorCode:
            "DEV_PAY_TOGGLE_INVALID_SECRET",
          classification:
            "AUTHENTICATION_ERROR",
          reason:
            "DEV_PAYMENT_SECRET mismatch or missing",
          resolution_hint:
            "Set DEV_PAYMENT_SECRET and send x-dev-secret header",
        },
      );
      return res.status(403).json({
        error:
          "Dev pay toggle secret is invalid",
        errorCode:
          "DEV_PAY_TOGGLE_INVALID_SECRET",
      });
    }

    const { actor } =
      await getBusinessContext(
        req.user.sub,
      );

    if (
      actor.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          "Business owner access required",
      });
    }

    const paymentId =
      req.params?.paymentId
        ?.toString()
        .trim();
    if (!paymentId) {
      return res.status(400).json({
        error: "Payment id is required",
      });
    }

    // WHY: Dev-only flow simulates Paystack success safely via backend.
    const result =
      await paymentService.devMarkTenantPaymentSucceeded(
        {
          paymentId,
          actorId: actor._id,
          actorRole: actor.role,
        },
      );

    debug(
      "BUSINESS CONTROLLER: devMarkPaymentSucceeded - success",
      {
        actorId: actor._id,
        paymentId: result.payment?._id,
        applicationId:
          result.application?._id,
      },
    );

    return res.status(200).json({
      message:
        "Payment marked as succeeded (dev gate)",
      devGateEnabled:
        process.env
          .DEV_MARK_RENT_PAID ===
        "true",
      payment: result.payment,
      application: result.application,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: devMarkPaymentSucceeded - error",
      {
        actorId: req.user?.sub,
        paymentId:
          req.params?.paymentId,
        reason: err.message,
        next: "Ensure DEV_MARK_RENT_PAID=true and payment is pending for an approved tenant",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * TENANT APPLICATIONS
 */
async function getTenants(req, res) {
  // TODO: Implement getTenants
  debug(
    "BUSINESS CONTROLLER: getTenants - entry",
    {
      actorId: req.user?.sub,
    },
  );
  return res.status(501).json({
    message: "Not Implemented",
  });
}

module.exports = {
  createProduct,
  getAllProducts,
  getProductById,
  updateProduct,
  softDeleteProduct,
  restoreProduct,
  uploadProductImage,
  deleteProductImage,
  getOrders,
  updateOrderStatus,
  createAsset,
  getAssets,
  updateAsset,
  softDeleteAsset,
  lookupUser,
  createInvite,
  acceptInvite,
  getTenantEstate,
  uploadTenantContactDocument,
  submitTenantVerification,
  getTenantApplication,
  listTenantApplications,
  getTenantApplicationDetail,
  getTenantSummary,
  getBusinessTenantPayments,
  getTenantPayments,
  verifyTenantContact,
  approveAgreement,
  setAgreementText,
  updateTenantApplication,
  updateUserRole,
  approveTenantApplication,
  togglePaymentStatus,
  verifyContact,
  createPaymentIntent,
  handlePaystackWebhook,
  devMarkPaymentSucceeded,
  getTenants,
  getAnalyticsSummary,
  getAnalyticsEvents,
  getEstateAnalytics,
};
