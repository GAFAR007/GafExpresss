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
const Product = require("../models/Product");
const businessProductService = require("../services/business.product.service");
const businessOrderService = require("../services/business.order.service");
const businessAssetService = require("../services/business.asset.service");
const businessAnalyticsService = require("../services/business.analytics.service");
const productImageService = require("../services/product_image.service");
const businessInviteService = require("../services/business_invite.service");
const businessTenantService = require("../services/business.tenant.service");
const tenantContactDocumentService = require("../services/tenant_contact_document.service");
const paymentService = require("../services/payment.service");
const {
  generateProductionPlanDraft,
} = require("../services/production_plan_ai.service");
const {
  generateProductDraft,
} = require("../services/product_ai.service");
const { resolveRentPeriodLimit } =
  paymentService;
const Payment = require("../models/Payment");
const BusinessTenantApplication = require("../models/BusinessTenantApplication");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const StaffAttendance = require("../models/StaffAttendance");
const StaffCompensation = require("../models/StaffCompensation");
const ProductionPlan = require("../models/ProductionPlan");
const ProductionPhase = require("../models/ProductionPhase");
const ProductionTask = require("../models/ProductionTask");
const ProductionOutput = require("../models/ProductionOutput");
const TaskProgress = require("../models/TaskProgress");
const PreorderReservation = require("../models/PreorderReservation");
const {
  periodsPerYear,
} = require("../utils/rentCoverage");
const {
  signToken,
} = require("../config/jwt");
const {
  writeAuditLog,
} = require("../utils/audit");
const {
  resolveBusinessContext,
  resolveStaffProfile,
} = require("../services/business_context.service");
const {
  DEFAULT_PRODUCTION_PHASES,
} = require("../utils/production_defaults");
const {
  reconcileExpiredPreorderReservations,
} = require("../services/preorder_reservation_reconciler.service");
const {
  buildPreorderCapConfidenceSummary,
} = require("../services/preorder_cap_confidence.service");
const {
  STAFF_ROLES,
  DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  DEFAULT_PREORDER_CAP_RATIO,
  PREORDER_CAP_RATIO_MIN,
  PREORDER_CAP_RATIO_MAX,
  HUMANE_WORKLOAD_LIMITS,
  PRODUCTION_TASK_PROGRESS_DELAY_REASONS,
  normalizeDomainContext,
  isValidDomainContext,
} = require("../utils/production_engine.config");

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
// WHY: Allow safe default when country headers are missing.
const COUNTRY_HEADER_KEY = "x-country";
const DEFAULT_COUNTRY = "unknown";
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

// WHY: Centralize staff roles used in permission checks.
const STAFF_ROLE_ESTATE_MANAGER =
  "estate_manager";
const STAFF_ROLE_ACCOUNTANT =
  "accountant";
const STAFF_ROLE_FARM_MANAGER =
  "farm_manager";
const STAFF_ROLE_ASSET_MANAGER =
  "asset_manager";
const STAFF_STATUS_ACTIVE = "active";

// WHY: Reuse copy for staff endpoints to avoid inline magic strings.
const STAFF_COPY = {
  BUSINESS_ACCESS_REQUIRED:
    "Business access required",
  STAFF_ACCESS_REQUIRED:
    "Staff access required",
  STAFF_PROFILE_REQUIRED:
    "Staff profile is required",
  STAFF_PROFILE_NOT_FOUND:
    "Staff profile not found",
  STAFF_ROLE_REQUIRED:
    "Staff role is required",
  STAFF_LIST_OK:
    "Staff profiles fetched successfully",
  STAFF_DETAIL_OK:
    "Staff profile fetched successfully",
  STAFF_ATTENDANCE_OK:
    "Attendance fetched successfully",
  STAFF_CLOCK_IN_OK:
    "Clock-in recorded successfully",
  STAFF_CLOCK_OUT_OK:
    "Clock-out recorded successfully",
  STAFF_CLOCK_IN_OPEN:
    "Staff already has an open attendance session",
  STAFF_CLOCK_OUT_MISSING:
    "No open attendance session to close",
  STAFF_FORBIDDEN:
    "You do not have permission to access staff data",
  STAFF_PROFILE_ID_REQUIRED:
    "Staff profile id is required",
  STAFF_ROLE_INVALID:
    "Staff role is invalid",
  STAFF_ROLE_REQUIRED:
    "Staff role is required for staff invites",
};

// WHY: Centralize staff compensation copy for payroll endpoints.
const STAFF_COMPENSATION_COPY = {
  COMPENSATION_OK:
    "Staff compensation fetched successfully",
  COMPENSATION_EMPTY:
    "Staff compensation has not been set",
  COMPENSATION_UPDATED:
    "Staff compensation saved successfully",
  COMPENSATION_FORBIDDEN:
    "You do not have permission to manage compensation",
  COMPENSATION_PROFILE_REQUIRED:
    "Staff profile id is required",
  COMPENSATION_AMOUNT_REQUIRED:
    "Salary amount is required",
  COMPENSATION_AMOUNT_INVALID:
    "Salary amount is invalid",
  COMPENSATION_CADENCE_REQUIRED:
    "Salary cadence is required",
  COMPENSATION_CADENCE_INVALID:
    "Salary cadence is invalid",
  COMPENSATION_PROFIT_SHARE_REQUIRED:
    "Profit share percentage is required for profit-share compensation",
  COMPENSATION_PROFIT_SHARE_INVALID:
    "Profit share percentage must be between 0 and 100",
  COMPENSATION_TRIGGER_INVALID:
    "Payout trigger is invalid",
  COMPENSATION_UPDATE_REQUIRED:
    "Provide at least one compensation field to update",
};

// WHY: Keep compensation field names consistent for payload checks.
const STAFF_COMPENSATION_FIELDS = {
  SALARY_AMOUNT: "salaryAmountKobo",
  SALARY_CADENCE: "salaryCadence",
  PAY_DAY: "payDay",
  PROFIT_SHARE_PERCENTAGE:
    "profitSharePercentage",
  INCLUDES_HOUSING:
    "includesHousing",
  INCLUDES_FEEDING:
    "includesFeeding",
  PAYOUT_TRIGGER:
    "payoutTrigger",
  NOTES: "notes",
};

// WHY: Standardize compensation logs for diagnostics.
const STAFF_COMPENSATION_LOG = {
  FETCH_ENTRY:
    "BUSINESS CONTROLLER: getStaffCompensation - entry",
  FETCH_SUCCESS:
    "BUSINESS CONTROLLER: getStaffCompensation - success",
  FETCH_ERROR:
    "BUSINESS CONTROLLER: getStaffCompensation - error",
  UPSERT_ENTRY:
    "BUSINESS CONTROLLER: upsertStaffCompensation - entry",
  UPSERT_SUCCESS:
    "BUSINESS CONTROLLER: upsertStaffCompensation - success",
  UPSERT_ERROR:
    "BUSINESS CONTROLLER: upsertStaffCompensation - error",
};

// WHY: Centralize production plan copy to avoid inline strings.
const PRODUCTION_COPY = {
  PLAN_CREATED:
    "Production plan created successfully",
  PLAN_DRAFT_OK:
    "Production plan draft generated successfully",
  PLAN_ASSISTANT_TURN_OK:
    "Production plan assistant response generated successfully",
  PLAN_LIST_OK:
    "Production plans fetched successfully",
  PLAN_DETAIL_OK:
    "Production plan fetched successfully",
  CALENDAR_LIST_OK:
    "Production calendar loaded",
  PLAN_ID_REQUIRED:
    "Production plan id is required",
  PLAN_NOT_FOUND:
    "Production plan not found",
  CALENDAR_RANGE_REQUIRED:
    "from and to query params are required",
  CALENDAR_RANGE_INVALID:
    "to must be greater than from",
  SCHEDULE_POLICY_LOADED:
    "Production schedule policy loaded",
  SCHEDULE_POLICY_UPDATED:
    "Production schedule policy updated",
  SCHEDULE_POLICY_INVALID:
    "Production schedule policy is invalid",
  SCHEDULE_POLICY_FORBIDDEN:
    "You do not have permission to manage production schedule policy",
  SCHEDULE_POLICY_ESTATE_INVALID:
    "Estate asset id is invalid",
  SCHEDULE_POLICY_ESTATE_NOT_FOUND:
    "Estate asset not found",
  STAFF_CAPACITY_LOADED:
    "Staff capacity loaded",
  TASK_ASSIGNMENT_UPDATED:
    "Task assignment updated successfully",
  TASK_ASSIGNMENT_TASK_ID_REQUIRED:
    "Task id is required",
  TASK_ASSIGNMENT_TASK_ID_INVALID:
    "Task id is invalid",
  TASK_ASSIGNMENT_STAFF_IDS_REQUIRED:
    "assignedStaffProfileIds must be an array",
  TASK_ASSIGNMENT_STAFF_ID_INVALID:
    "One or more staff profile ids are invalid",
  TASK_ASSIGNMENT_STAFF_PROFILE_NOT_FOUND:
    "One or more staff profiles were not found in this business scope",
  TASK_ASSIGNMENT_ROLE_MISMATCH:
    "Assigned staff role does not match task role",
  TASK_ASSIGNMENT_INCOMPLETE:
    "Assigned staff count is below required headcount",
  PLAN_DRAFT_FAILED:
    "Unable to generate production plan draft",
  PHASES_REQUIRED:
    "Production phases are required",
  TASKS_REQUIRED:
    "Production tasks are required",
  TASK_NOT_FOUND:
    "Production task not found",
  TASK_STATUS_REQUIRED:
    "Task status is required",
  OUTPUT_CREATED:
    "Production output created successfully",
  OUTPUT_LIST_OK:
    "Production outputs fetched successfully",
  PRODUCT_REQUIRED:
    "Product is required",
  OUTPUT_QUANTITY_REQUIRED:
    "Output quantity is required",
  PRODUCT_NOT_FOUND:
    "Product not found",
  PREORDER_STATE_UPDATED:
    "Pre-order state updated successfully",
  PREORDER_FLAG_REQUIRED:
    "allowPreorder flag is required",
  PREORDER_YIELD_REQUIRED:
    "Conservative yield quantity is required to open pre-orders",
  PREORDER_YIELD_INVALID:
    "Conservative yield quantity must be greater than zero",
  PREORDER_CAP_RATIO_INVALID:
    "Pre-order cap ratio must be between 0.1 and 0.9",
  PREORDER_RESERVE_CREATED:
    "Pre-order reservation created successfully",
  PREORDER_RESERVE_QUANTITY_REQUIRED:
    "Reservation quantity is required",
  PREORDER_RESERVE_QUANTITY_INVALID:
    "Reservation quantity must be greater than zero",
  PREORDER_RESERVE_DISABLED:
    "Pre-order is not enabled for this production plan",
  PREORDER_RESERVE_CAP_EXCEEDED:
    "Reservation quantity exceeds remaining pre-order capacity",
  PREORDER_RELEASED:
    "Pre-order reservation released successfully",
  PREORDER_RELEASE_ALREADY_APPLIED:
    "Pre-order reservation was already released",
  PREORDER_CONFIRMED:
    "Pre-order reservation confirmed successfully",
  PREORDER_CONFIRM_ALREADY_APPLIED:
    "Pre-order reservation was already confirmed",
  PREORDER_RESERVATION_NOT_FOUND:
    "Pre-order reservation not found",
  PREORDER_RELEASE_STATUS_INVALID:
    "Only reserved pre-order reservations can be released",
  PREORDER_CONFIRM_STATUS_INVALID:
    "Only reserved pre-order reservations can be confirmed",
  PREORDER_RESERVATIONS_LIST_OK:
    "Pre-order reservations fetched successfully",
  PREORDER_RESERVATIONS_LIST_FORBIDDEN:
    "You do not have permission to view pre-order reservations",
  PREORDER_RESERVATIONS_STATUS_INVALID:
    "Reservation status filter is invalid",
  PREORDER_RESERVATIONS_PLAN_ID_INVALID:
    "Production plan id filter is invalid",
  PREORDER_RECONCILE_COMPLETED:
    "Expired pre-order reservations reconciled successfully",
  PREORDER_RECONCILE_FORBIDDEN:
    "You do not have permission to reconcile expired reservations",
  TASK_PROGRESS_CREATED:
    "Task daily progress saved successfully",
  TASK_PROGRESS_DATE_REQUIRED:
    "Work date is required",
  TASK_PROGRESS_DATE_INVALID:
    "Work date is invalid",
  TASK_PROGRESS_ACTUAL_REQUIRED:
    "Actual plots is required",
  TASK_PROGRESS_ACTUAL_INVALID:
    "Actual plots must be a valid non-negative number",
  TASK_PROGRESS_HUMANE_LIMIT_EXCEEDED:
    "Actual plots exceeds humane daily workload limit",
  TASK_PROGRESS_DELAY_REASON_INVALID:
    "Delay reason is invalid",
  TASK_PROGRESS_ZERO_DELAY_REASON_REQUIRED:
    "Delay reason is required when actual plots is zero",
  TASK_PROGRESS_STAFF_ID_INVALID:
    "Staff id is invalid",
  TASK_PROGRESS_STAFF_REQUIRED_FOR_MULTI_ASSIGN:
    "staffId is required when multiple farmers are assigned",
  TASK_PROGRESS_STAFF_NOT_ASSIGNED:
    "staffId is not assigned to this task",
  TASK_PROGRESS_STAFF_SCOPE_INVALID:
    "staffId must belong to the same business and estate",
  TASK_PROGRESS_NOT_FOUND:
    "Task progress record not found",
  TASK_PROGRESS_REVIEW_FORBIDDEN:
    "You do not have permission to review task progress",
  TASK_PROGRESS_REJECT_REASON_REQUIRED:
    "Reject reason is required",
  TASK_PROGRESS_APPROVED:
    "Task progress approved successfully",
  TASK_PROGRESS_REJECTED:
    "Task progress marked for review successfully",
  TASK_PROGRESS_BATCH_PROCESSED:
    "Batch task progress processed",
  TASK_PROGRESS_BATCH_DATE_REQUIRED:
    "Batch work date is required",
  TASK_PROGRESS_BATCH_DATE_INVALID:
    "Batch work date is invalid",
  TASK_PROGRESS_BATCH_ENTRIES_REQUIRED:
    "Batch entries are required",
  STAFF_REQUIRED_FOR_DRAFT:
    "Staff profiles are required to generate a draft",
  ESTATE_REQUIRED:
    "Estate asset is required",
  DATES_REQUIRED:
    "Start and end dates are required",
  DATE_RANGE_INVALID:
    "End date must be after start date",
  STAFF_ASSIGN_REQUIRED:
    "Assigned staff is required",
  STAFF_ROLE_REQUIRED:
    "Task role is required",
  STAFF_ROLE_MISMATCH:
    "Assigned staff role does not match task role",
  STAFF_ASSIGN_APPROVAL_REQUIRED:
    "Only business owners can approve assignments",
  STAFF_ASSIGN_REJECT_REQUIRED:
    "Only business owners can reject assignments",
  STAFF_TASK_FORBIDDEN:
    "You do not have permission to update this task",
  DOMAIN_CONTEXT_INVALID:
    "Domain context is invalid",
  ASSISTANT_CONTEXT_REQUIRED:
    "Estate context is required for production assistant",
  ASSISTANT_PRODUCT_REQUIRED:
    "Select a product or describe one so assistant can continue",
  INVALID_UNIT_TYPE:
    "Invalid unit type",
  TASK_STATUS_UPDATED:
    "Task status updated successfully",
  TASK_ASSIGN_APPROVED:
    "Task assignment approved",
  TASK_ASSIGN_REJECTED:
    "Task assignment rejected",
};

// WHY: Keep AI product draft copy centralized for consistent UX.
const PRODUCT_AI_COPY = {
  PROMPT_REQUIRED:
    "Describe the product you want to create",
  DRAFT_OK:
    "Product draft generated successfully",
  DRAFT_FAILED:
    "Unable to generate product draft",
};

// WHY: Standardize AI product draft logs for diagnostics.
const PRODUCT_AI_LOG = {
  ENTRY:
    "BUSINESS CONTROLLER: generateProductDraft - entry",
  SUCCESS:
    "BUSINESS CONTROLLER: generateProductDraft - success",
  ERROR:
    "BUSINESS CONTROLLER: generateProductDraft - error",
};
const PRODUCT_AI_ERROR_HINT =
  "Verify prompt and AI configuration before retrying.";
const PRODUCT_AI_ERROR_REASON =
  "product_draft_failed";

// WHY: Standardize logs for production output -> listing updates.
const PRODUCTION_OUTPUT_LOG = {
  LISTING_UPDATE_START:
    "BUSINESS CONTROLLER: productionOutput listing update - start",
  LISTING_UPDATE_SUCCESS:
    "BUSINESS CONTROLLER: productionOutput listing update - success",
  LISTING_UPDATE_ERROR:
    "BUSINESS CONTROLLER: productionOutput listing update - error",
};
const PRODUCTION_OUTPUT_LISTING_REASON =
  "production_output_listing_update_failed";
const PRODUCTION_OUTPUT_LISTING_HINT =
  "Retry listing update or adjust product stock manually.";
const PRODUCTION_OUTPUT_RESPONSE_KEYS =
  {
    LISTING_UPDATED: "listingUpdated",
    LISTING_ERROR: "listingError",
    PRODUCT: "product",
  };

// WHY: Keep production status values centralized.
const PRODUCTION_STATUS_DRAFT = "draft";
const PRODUCTION_PHASE_STATUS_PENDING =
  "pending";
const PRODUCTION_TASK_STATUS_PENDING =
  "pending";
const PRODUCTION_TASK_STATUS_DONE =
  "done";
const PRODUCTION_TASK_APPROVAL_PENDING =
  "pending_approval";
const PRODUCTION_TASK_APPROVAL_APPROVED =
  "approved";
const PRODUCTION_TASK_APPROVAL_REJECTED =
  "rejected";
const DEFAULT_TASK_TITLE = "Task";
const DEFAULT_PHASE_NAME_PREFIX =
  "Phase";
const MS_PER_MINUTE = 60000;
const MS_PER_DAY = 86400000;
const MS_PER_HOUR =
  60 * MS_PER_MINUTE;
// WHY: Scheduling policy defaults are used when business/estate policy is missing.
const WORK_SCHEDULE_FALLBACK_WEEK_DAYS = [
  1, 2, 3, 4, 5, 6, 7,
];
const WORK_SCHEDULE_FALLBACK_BLOCKS = [
  { start: "09:00", end: "13:00" },
  { start: "14:00", end: "17:00" },
];
const WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES = 30;
const WORK_SCHEDULE_MIN_SLOT_MINUTES = 15;
const WORK_SCHEDULE_MAX_SLOT_MINUTES = 240;
const WORK_SCHEDULE_FALLBACK_TIMEZONE = "UTC";
const WORK_SCHEDULE_TIME_PATTERN =
  /^([01]\d|2[0-3]):([0-5]\d)$/;
const STAFF_CAPACITY_ROLE_BUCKETS = [
  "farmer",
  "qc_officer",
  "machine_operator",
  "storekeeper",
  "packer",
  "logistics",
  "supervisor",
];
const PRODUCTION_ASSISTANT_ACTION_SUGGESTIONS =
  "suggestions";
const PRODUCTION_ASSISTANT_ACTION_CLARIFY =
  "clarify";
const PRODUCTION_ASSISTANT_ACTION_DRAFT_PRODUCT =
  "draft_product";
const PRODUCTION_ASSISTANT_ACTION_PLAN_DRAFT =
  "plan_draft";
const PRODUCTION_ASSISTANT_REQUIRED_FIELDS = [
  "productId",
  "productDescription",
  "startDate",
  "endDate",
  "quantity",
  "unit",
  "destination",
  "qualityGrade",
];
// WHY: Assistant fallback keeps full-range daily timelines usable when provider output has no tasks.
const ASSISTANT_FALLBACK_TASK_TEMPLATES = [
  "Field preparation and safety check",
  "Soil and moisture monitoring",
  "Planting and stand count",
  "Irrigation and nutrient application",
  "Weed and pest management",
  "Growth and quality inspection",
  "Harvest-readiness review",
];

// WHY: Provide safe fallbacks for validation lists.
const STAFF_ROLE_VALUES = STAFF_ROLES;
const COMPENSATION_CADENCE_VALUES =
  StaffCompensation.COMPENSATION_CADENCE ||
  [];
const COMPENSATION_PAYOUT_TRIGGER_VALUES =
  StaffCompensation.COMPENSATION_PAYOUT_TRIGGERS ||
  [];
const OUTPUT_UNIT_VALUES =
  ProductionOutput.PRODUCTION_OUTPUT_UNITS ||
  [];
const TASK_STATUS_VALUES =
  ProductionTask.PRODUCTION_TASK_STATUSES ||
  [];
const OUTPUT_UNIT_FALLBACK = "units";
const PRODUCT_STATE_IN_PRODUCTION =
  "in_production";
const PRODUCT_STATE_AVAILABLE_FOR_PREORDER =
  "available_for_preorder";
const PRODUCT_STATE_IN_STORAGE =
  "in_storage";
const PRODUCT_STATE_ACTIVE_STOCK =
  "active_stock";
const TASK_PROGRESS_STATUS_ON_TRACK =
  "on_track";
const TASK_PROGRESS_STATUS_BEHIND =
  "behind";
const TASK_PROGRESS_STATUS_BLOCKED =
  "blocked";
const TASK_PROGRESS_DELAY_ON_TIME =
  "on_time";
const TASK_PROGRESS_DELAY_LATE =
  "late";
const TASK_PROGRESS_APPROVAL_PENDING =
  "pending_approval";
const TASK_PROGRESS_APPROVAL_APPROVED =
  "approved";
const TASK_PROGRESS_APPROVAL_NEEDS_REVIEW =
  "needs_review";
const TASK_PROGRESS_REJECTION_NOTE_PREFIX =
  "[TASK_PROGRESS_REJECTED]";
const TASK_PROGRESS_BATCH_ENTRY_CODE_TASK_ID_REQUIRED =
  "TASK_ID_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_TASK_ID_INVALID =
  "TASK_ID_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_TASK_NOT_FOUND =
  "TASK_NOT_FOUND";
const TASK_PROGRESS_BATCH_ENTRY_CODE_PLAN_NOT_FOUND =
  "PLAN_NOT_FOUND";
const TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_ID_REQUIRED =
  "STAFF_ID_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_ID_INVALID =
  "STAFF_ID_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_NOT_ASSIGNED =
  "STAFF_NOT_ASSIGNED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_SCOPE_INVALID =
  "STAFF_SCOPE_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_REQUIRED =
  "ACTUAL_PLOTS_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_INVALID =
  "ACTUAL_PLOTS_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_HUMANE_LIMIT_EXCEEDED =
  "HUMANE_LIMIT_EXCEEDED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_DELAY_REASON_INVALID =
  "DELAY_REASON_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_ZERO_DELAY_REQUIRED =
  "ZERO_OUTPUT_DELAY_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_FORBIDDEN =
  "FORBIDDEN";
const TASK_PROGRESS_BATCH_ENTRY_CODE_UNKNOWN =
  "UNKNOWN_ERROR";
const STAFF_PROGRESS_ON_TRACK =
  "on_track";
const STAFF_PROGRESS_NEEDS_ATTENTION =
  "needs_attention";
const STAFF_PROGRESS_OFF_TRACK =
  "off_track";

// WHY: Resolve actor + businessId once per request.
async function getBusinessContext(
  userId,
) {
  // WHY: Share the same business-context loader across controllers + middleware.
  return resolveBusinessContext(userId);
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

// WHY: Load staff profile for staff-role actors to enforce staff-role permissions.
async function getStaffProfileForActor({
  actor,
  businessId,
  allowMissing = false,
}) {
  // WHY: Share the staff profile lookup across controllers + middleware.
  return resolveStaffProfile({
    actor,
    businessId,
    allowMissing,
  });
}

// WHY: Only estate managers can manage staff visibility (besides owners).
function canManageStaffDirectory({
  actorRole,
  staffRole,
}) {
  if (actorRole === "business_owner") {
    return true;
  }

  return (
    actorRole === "staff" &&
    staffRole ===
      STAFF_ROLE_ESTATE_MANAGER
  );
}

// WHY: Staff compensation is limited to owners + estate managers.
function canManageStaffCompensation({
  actorRole,
  staffRole,
}) {
  if (actorRole === "business_owner") {
    return true;
  }

  return (
    actorRole === "staff" &&
    staffRole ===
      STAFF_ROLE_ESTATE_MANAGER
  );
}

// WHY: Attendance management is limited to owner and estate managers.
function canManageAttendance({
  actorRole,
  staffRole,
}) {
  if (actorRole === "business_owner") {
    return true;
  }

  return (
    actorRole === "staff" &&
    staffRole ===
      STAFF_ROLE_ESTATE_MANAGER
  );
}

// WHY: Accountants may view attendance but not edit it.
function canViewAttendance({
  actorRole,
  staffRole,
}) {
  if (actorRole === "business_owner") {
    return true;
  }

  return (
    actorRole === "staff" &&
    (staffRole ===
      STAFF_ROLE_ESTATE_MANAGER ||
      staffRole ===
        STAFF_ROLE_ACCOUNTANT)
  );
}

// WHY: Production plans are managed by owners and estate managers.
function canCreateProductionPlan({
  actorRole,
  staffRole,
}) {
  if (actorRole === "business_owner") {
    return true;
  }

  return (
    actorRole === "staff" &&
    staffRole ===
      STAFF_ROLE_ESTATE_MANAGER
  );
}

// WHY: Task assignments can be initiated by designated managers.
function canAssignProductionTasks({
  actorRole,
  staffRole,
}) {
  if (actorRole === "business_owner") {
    return true;
  }

  return (
    actorRole === "staff" &&
    (staffRole ===
      STAFF_ROLE_ESTATE_MANAGER ||
      staffRole ===
        STAFF_ROLE_FARM_MANAGER ||
      staffRole ===
        STAFF_ROLE_ASSET_MANAGER)
  );
}

// WHY: TaskProgress review authority is restricted to owners + estate managers.
function canReviewTaskProgress({
  actorRole,
  staffRole,
}) {
  if (actorRole === "business_owner") {
    return true;
  }

  return (
    actorRole === "staff" &&
    staffRole ===
      STAFF_ROLE_ESTATE_MANAGER
  );
}

// WHY: Normalize date inputs and guard against invalid values.
function parseDateInput(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }
  return date;
}

// WHY: Date-only end values are parsed at midnight and should include the full end day.
function isStartOfDayTimestamp(value) {
  return (
    value.getHours() === 0 &&
    value.getMinutes() === 0 &&
    value.getSeconds() === 0 &&
    value.getMilliseconds() === 0
  );
}

// WHY: Keep planning ranges inclusive when endDate is provided without a clock time.
function normalizeInclusiveRangeEnd(value) {
  if (!(value instanceof Date)) {
    return value;
  }
  if (!isStartOfDayTimestamp(value)) {
    return value;
  }
  return new Date(
    value.getTime() +
      MS_PER_DAY -
      1,
  );
}

// WHY: Shared range normalization prevents off-by-one drift across summaries + schedulers.
function normalizeScheduleRangeBounds({
  phaseStart,
  phaseEnd,
}) {
  const normalizedStart = new Date(
    phaseStart,
  );
  const normalizedEnd =
    normalizeInclusiveRangeEnd(
      new Date(phaseEnd),
    );
  return {
    phaseStart: normalizedStart,
    phaseEnd: normalizedEnd,
  };
}

// WHY: Time blocks use HH:mm to keep policy payload compact and deterministic.
function parseTimeBlockClock(value) {
  const raw =
    value == null ?
      ""
    : value.toString().trim();
  const match =
    WORK_SCHEDULE_TIME_PATTERN.exec(
      raw,
    );
  if (!match) {
    return null;
  }

  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const totalMinutes =
    hour * 60 + minute;
  return {
    raw: `${match[1]}:${match[2]}`,
    hour,
    minute,
    totalMinutes,
  };
}

// WHY: Timezone labels should remain valid for cross-platform calendar displays.
function normalizeScheduleTimezoneInput(
  value,
) {
  const raw =
    value == null ?
      ""
    : value.toString().trim();
  if (!raw) {
    return WORK_SCHEDULE_FALLBACK_TIMEZONE;
  }
  try {
    Intl.DateTimeFormat("en-US", {
      timeZone: raw,
    });
    return raw;
  } catch (_) {
    return WORK_SCHEDULE_FALLBACK_TIMEZONE;
  }
}

function buildDefaultSchedulePolicy() {
  return {
    workWeekDays: [
      ...WORK_SCHEDULE_FALLBACK_WEEK_DAYS,
    ],
    blocks: WORK_SCHEDULE_FALLBACK_BLOCKS.map(
      (block) => ({ ...block }),
    ),
    minSlotMinutes:
      WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES,
    timezone:
      WORK_SCHEDULE_FALLBACK_TIMEZONE,
  };
}

// WHY: Keep weekday handling consistent with Monday=1..Sunday=7 API contract.
function normalizeWorkWeekDaysInput(
  value,
  fallbackDays = WORK_SCHEDULE_FALLBACK_WEEK_DAYS,
) {
  const values =
    Array.isArray(value) ?
      value
    : [];
  const normalized = values
    .map((day) => Number(day))
    .filter(
      (day) =>
        Number.isInteger(day) &&
        day >= 1 &&
        day <= 7,
    );
  if (normalized.length === 0) {
    return [...fallbackDays];
  }
  return Array.from(new Set(normalized)).sort(
    (left, right) => left - right,
  );
}

// WHY: Block normalization ensures deterministic ordering for scheduling.
function normalizeWorkBlocksInput(
  value,
  fallbackBlocks = WORK_SCHEDULE_FALLBACK_BLOCKS,
) {
  const values =
    Array.isArray(value) ?
      value
    : [];
  const normalized = [];

  for (const block of values) {
    const parsedStart =
      parseTimeBlockClock(block?.start);
    const parsedEnd =
      parseTimeBlockClock(block?.end);
    if (!parsedStart || !parsedEnd) {
      continue;
    }
    if (
      parsedEnd.totalMinutes <=
      parsedStart.totalMinutes
    ) {
      continue;
    }
    normalized.push({
      start: parsedStart.raw,
      end: parsedEnd.raw,
    });
  }

  if (normalized.length === 0) {
    return fallbackBlocks.map((block) => ({
      ...block,
    }));
  }

  return normalized.sort((left, right) => {
    const parsedLeft =
      parseTimeBlockClock(left.start);
    const parsedRight =
      parseTimeBlockClock(right.start);
    return (
      (parsedLeft?.totalMinutes || 0) -
      (parsedRight?.totalMinutes || 0)
    );
  });
}

// WHY: Policy normalization keeps reads resilient while preserving safe defaults.
function normalizeSchedulePolicyInput(
  rawPolicy,
  fallbackPolicy = buildDefaultSchedulePolicy(),
) {
  const source =
    rawPolicy &&
    typeof rawPolicy === "object" ?
      rawPolicy
    : {};

  const fallbackMinSlotMinutes =
    Number.isFinite(
      Number(
        fallbackPolicy?.minSlotMinutes,
      ),
    ) ?
      Number(
        fallbackPolicy.minSlotMinutes,
      )
    : WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES;

  const parsedSlotMinutes = Number(
    source.minSlotMinutes,
  );
  const minSlotMinutes =
    Number.isFinite(parsedSlotMinutes) &&
      parsedSlotMinutes >=
        WORK_SCHEDULE_MIN_SLOT_MINUTES &&
      parsedSlotMinutes <=
        WORK_SCHEDULE_MAX_SLOT_MINUTES ?
      Math.floor(parsedSlotMinutes)
    : fallbackMinSlotMinutes;

  const normalizedDays =
    normalizeWorkWeekDaysInput(
      source.workWeekDays,
      fallbackPolicy?.workWeekDays ||
        WORK_SCHEDULE_FALLBACK_WEEK_DAYS,
    );
  const normalizedBlocks =
    normalizeWorkBlocksInput(
      source.blocks,
      fallbackPolicy?.blocks ||
        WORK_SCHEDULE_FALLBACK_BLOCKS,
    );
  const timezone =
    normalizeScheduleTimezoneInput(
      source.timezone ||
        fallbackPolicy?.timezone,
    );

  return {
    workWeekDays: normalizedDays,
    blocks: normalizedBlocks,
    minSlotMinutes,
    timezone,
  };
}

// WHY: PUT endpoint requires strict validation before persisting manager policy edits.
function validateSchedulePolicyUpdateInput(
  payload,
  basePolicy,
) {
  const source =
    payload?.policy &&
    typeof payload.policy === "object" ?
      payload.policy
    : payload && typeof payload === "object" ?
      payload
    : null;
  if (!source) {
    return {
      ok: false,
      error:
        PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
      details: {
        code: "SCHEDULE_POLICY_PAYLOAD_REQUIRED",
      },
    };
  }

  const nextPolicy =
    normalizeSchedulePolicyInput(
      source,
      basePolicy,
    );
  const hasWorkWeekDays =
    Object.prototype.hasOwnProperty.call(
      source,
      "workWeekDays",
    );
  const hasBlocks =
    Object.prototype.hasOwnProperty.call(
      source,
      "blocks",
    );
  const hasMinSlot =
    Object.prototype.hasOwnProperty.call(
      source,
      "minSlotMinutes",
    );

  if (
    hasWorkWeekDays &&
    !Array.isArray(source.workWeekDays)
  ) {
    return {
      ok: false,
      error:
        PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
      details: {
        code: "SCHEDULE_POLICY_WORK_DAYS_INVALID",
      },
    };
  }
  if (
    hasWorkWeekDays &&
    nextPolicy.workWeekDays.length === 0
  ) {
    return {
      ok: false,
      error:
        PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
      details: {
        code: "SCHEDULE_POLICY_WORK_DAYS_EMPTY",
      },
    };
  }

  if (hasBlocks) {
    if (!Array.isArray(source.blocks)) {
      return {
        ok: false,
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
        details: {
          code: "SCHEDULE_POLICY_BLOCKS_INVALID",
        },
      };
    }
    if (nextPolicy.blocks.length === 0) {
      return {
        ok: false,
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
        details: {
          code: "SCHEDULE_POLICY_BLOCKS_EMPTY",
        },
      };
    }
  }

  const parsedBlocks = nextPolicy.blocks.map(
    (block) => ({
      ...block,
      startParsed:
        parseTimeBlockClock(block.start),
      endParsed:
        parseTimeBlockClock(block.end),
    }),
  );

  for (const block of parsedBlocks) {
    if (
      !block.startParsed ||
      !block.endParsed ||
      block.endParsed.totalMinutes <=
        block.startParsed.totalMinutes
    ) {
      return {
        ok: false,
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
        details: {
          code: "SCHEDULE_POLICY_BLOCK_RANGE_INVALID",
        },
      };
    }
  }

  for (
    let index = 1;
    index < parsedBlocks.length;
    index += 1
  ) {
    const prevBlock = parsedBlocks[index - 1];
    const nextBlock = parsedBlocks[index];
    if (
      (prevBlock.endParsed
        ?.totalMinutes || 0) >
      (nextBlock.startParsed
        ?.totalMinutes || 0)
    ) {
      return {
        ok: false,
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
        details: {
          code: "SCHEDULE_POLICY_BLOCKS_OVERLAP",
        },
      };
    }
  }

  if (hasMinSlot) {
    const parsed = Number(
      source.minSlotMinutes,
    );
    if (
      !Number.isFinite(parsed) ||
      parsed <
        WORK_SCHEDULE_MIN_SLOT_MINUTES ||
      parsed >
        WORK_SCHEDULE_MAX_SLOT_MINUTES
    ) {
      return {
        ok: false,
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
        details: {
          code: "SCHEDULE_POLICY_MIN_SLOT_INVALID",
        },
      };
    }
  }

  return {
    ok: true,
    policy: nextPolicy,
  };
}

function formatWorkBlocksLabel(
  blocks,
) {
  const normalizedBlocks =
    Array.isArray(blocks) ? blocks : [];
  if (normalizedBlocks.length === 0) {
    return "none";
  }
  return normalizedBlocks
    .map((block) => `${block.start}-${block.end}`)
    .join(", ");
}

function buildAiSchedulePolicyPrompt(
  schedulePolicy,
) {
  const policy =
    normalizeSchedulePolicyInput(
      schedulePolicy,
      buildDefaultSchedulePolicy(),
    );
  return [
    `Use workWeekDays: ${policy.workWeekDays.join(", ")}.`,
    `Use blocks: ${formatWorkBlocksLabel(policy.blocks)}.`,
    `Minimum slot minutes: ${policy.minSlotMinutes}.`,
    `Timezone: ${policy.timezone}.`,
  ].join(" ");
}

function buildAiCapacityPrompt(
  capacitySummary,
) {
  const roles =
    capacitySummary?.roles || {};
  const roleSummary =
    STAFF_CAPACITY_ROLE_BUCKETS.map(
      (role) => {
        const entry =
          roles[role] || {};
        const total = Math.max(
          0,
          Number(entry.total || 0),
        );
        return `${role}=${total}`;
      },
    ).join(", ");
  return `Role capacity guidance (total staff by role): ${roleSummary}.`;
}

function buildPlanningRangeSummary({
  startDate,
  endDate,
  productId,
  cropSubtype,
}) {
  const {
    phaseStart: normalizedStart,
    phaseEnd: normalizedEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart: startDate,
    phaseEnd: endDate,
  });
  const startDay = startOfDayLocal(
    normalizedStart,
  );
  const endDay = startOfDayLocal(
    normalizedEnd,
  );
  const totalDays = Math.max(
    1,
    Math.floor(
      (endDay.getTime() -
        startDay.getTime()) /
        MS_PER_DAY,
    ) + 1,
  );
  const weeks = Math.max(
    1,
    Math.ceil(totalDays / 7),
  );
  const monthApprox = Number(
    (totalDays / 30).toFixed(2),
  );

  return {
    startDate:
      normalizedStart
        .toISOString()
        .slice(0, 10),
    endDate:
      normalizedEnd
        .toISOString()
        .slice(0, 10),
    days: totalDays,
    weeks,
    monthApprox,
    productId:
      productId?.toString() || "",
    cropSubtype:
      cropSubtype?.toString() || "",
  };
}

function normalizeDraftTaskHeadcount(
  value,
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return 1;
  }
  return Math.max(
    1,
    Math.floor(parsed),
  );
}

// WHY: Assistant week labels in task titles conflict with UI week grouping and should not leak into draft task names.
function normalizeAssistantDraftTaskTitle(
  value,
) {
  const rawTitle =
    value
      ?.toString()
      .trim() ||
    DEFAULT_TASK_TITLE;
  const withoutAnyParenthesizedWeek =
    rawTitle.replace(
      /\s*[-–—]?\s*[\(（][^\)）]*\bweek\b[^\)）]*[\)）]/gi,
      "",
    );
  const withoutParenthesizedWeekNumber =
    withoutAnyParenthesizedWeek.replace(
      /\s*[-–—]?\s*\(\s*week\s*[-:]?\s*\d+\s*\)/gi,
      "",
    );
  const withoutLooseWeek =
    withoutParenthesizedWeekNumber.replace(
      /\s*[-–—]?\s*week\s*[-:]?\s*\d+\b/gi,
      "",
    );
  const compactTitle =
    withoutLooseWeek
      .replace(/\s{2,}/g, " ")
      .replace(/\(\s*\)/g, "")
      .trim();
  return (
    compactTitle ||
    DEFAULT_TASK_TITLE
  );
}

function normalizeDraftTaskShape(
  task,
) {
  const assignedStaffProfileIds =
    Array.from(
      new Set([
        ...(
          Array.isArray(
            task
              ?.assignedStaffProfileIds,
          ) ?
            task.assignedStaffProfileIds
          : []
        ),
        ...(
          Array.isArray(
            task?.assignedStaffIds,
          ) ?
            task.assignedStaffIds
          : []
        ),
        task?.assignedStaffId,
      ]),
    )
      .map((value) =>
        normalizeStaffIdInput(value),
      )
      .filter((value) =>
        mongoose.Types.ObjectId.isValid(
          value,
        ),
      );
  const assignedStaffId =
    assignedStaffProfileIds[0] ||
    "";
  const normalizedWeight =
    Number.isFinite(
      Number(task?.weight),
    ) ?
      Math.max(
        1,
        Math.floor(
          Number(task.weight),
        ),
      )
    : 1;
  return {
    ...task,
    title:
      normalizeAssistantDraftTaskTitle(
        task?.title,
      ),
    roleRequired:
      normalizeStaffIdInput(
        task?.roleRequired,
      ) ||
      STAFF_ROLE_VALUES[0] ||
      "farmer",
    instructions:
      task?.instructions
        ?.toString()
        .trim() || "",
    weight: normalizedWeight,
    requiredHeadcount:
      normalizeDraftTaskHeadcount(
        task?.requiredHeadcount,
      ),
    assignedStaffProfileIds,
    assignedStaffId,
    assignedCount:
      assignedStaffProfileIds.length,
  };
}

function summarizeRoleShortages({
  tasks,
  capacity,
}) {
  const warnings = [];
  const roleMaxDemand = new Map();
  tasks.forEach((task) => {
    const role =
      normalizeStaffIdInput(
        task?.roleRequired,
      ).toLowerCase();
    const requiredHeadcount =
      normalizeDraftTaskHeadcount(
        task?.requiredHeadcount,
      );
    const prevDemand =
      roleMaxDemand.get(role) || 0;
    roleMaxDemand.set(
      role,
      Math.max(
        prevDemand,
        requiredHeadcount,
      ),
    );
  });

  roleMaxDemand.forEach(
    (requiredHeadcount, role) => {
      const buckets =
        resolveCapacityBucketsForStaffRole(
          role,
        );
      const available = buckets.reduce(
        (sum, bucket) =>
          sum +
          Number(
            capacity?.roles?.[bucket]
              ?.available || 0,
          ),
        0,
      );
      if (requiredHeadcount > available) {
        warnings.push({
          code: "ROLE_SHORTAGE",
          role,
          requiredHeadcount,
          available,
          message: `Required headcount for role ${role} exceeds current available capacity`,
        });
      }
    },
  );

  return warnings;
}

// WHY: Keep domain context optional while enforcing safe normalized values.
function parseDomainContextInput(value) {
  const raw =
    value == null ?
      ""
    : value.toString().trim();
  if (!raw) {
    return {
      value:
        DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
      provided: false,
      isValid: true,
      wasNormalized: false,
      raw: "",
    };
  }

  const normalizedValue =
    normalizeDomainContext(raw);
  const normalizedRaw = raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  const isValid = isValidDomainContext(raw);

  return {
    value: normalizedValue,
    provided: true,
    isValid,
    wasNormalized:
      normalizedRaw !==
      normalizedValue,
    raw,
  };
}

// WHY: Numeric parsing helper keeps validation logic consistent across endpoints.
function parsePositiveNumberInput(value) {
  if (value == null || value === "") {
    return null;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

// WHY: Daily records must be normalized to a stable calendar day key.
function normalizeWorkDateToDayStart(value) {
  const parsed = parseDateInput(value);
  if (!parsed) {
    return null;
  }
  return new Date(
    Date.UTC(
      parsed.getUTCFullYear(),
      parsed.getUTCMonth(),
      parsed.getUTCDate(),
    ),
  );
}

// WHY: Keep delay reasons constrained to the controlled taxonomy.
function normalizeTaskProgressDelayReason(value) {
  const raw =
    value == null ?
      "none"
    : value.toString().trim().toLowerCase();
  if (!raw) {
    return "none";
  }
  return raw;
}

// WHY: Rejection reasons should be normalized for consistent storage and logs.
function normalizeTaskProgressRejectReason(
  value,
) {
  if (value == null) {
    return "";
  }
  return value.toString().trim();
}

// WHY: Staff ids from payload/task need stable string normalization for checks.
function normalizeStaffIdInput(value) {
  if (value == null) {
    return "";
  }
  return value.toString().trim();
}

// WHY: Task progress must support single and multi-assignee tasks without ambiguity.
function resolveTaskAssignedStaffIds(task) {
  const assignedFromProfiles =
    Array.isArray(
      task?.assignedStaffProfileIds,
    ) ?
      task.assignedStaffProfileIds
    : [];
  const assignedFromArray =
    Array.isArray(task?.assignedStaffIds) ?
      task.assignedStaffIds
    : [];
  const resolvedIds = [
    ...assignedFromProfiles,
    ...assignedFromArray,
    task?.assignedStaffId,
  ]
    .map((staffId) =>
      normalizeStaffIdInput(staffId),
    )
    .filter(Boolean);

  return Array.from(new Set(resolvedIds));
}

// WHY: Assistant payload requires second-level ISO timestamps without milliseconds.
function formatIsoDateTimeSeconds(value) {
  const parsed =
    parseDateInput(value) || new Date();
  return parsed
    .toISOString()
    .replace(/\.\d{3}Z$/, "Z");
}

function normalizeAssistantSuggestions(
  suggestions,
) {
  const list = (
    Array.isArray(suggestions) ?
      suggestions
    : []
  )
    .map((entry) =>
      entry == null ?
        ""
      : entry.toString().trim(),
    )
    .filter(Boolean);
  return Array.from(new Set(list)).slice(
    0,
    6,
  );
}

function resolveAssistantRequiredField(
  value,
) {
  const parsed =
    value == null ?
      ""
    : value.toString().trim();
  if (
    PRODUCTION_ASSISTANT_REQUIRED_FIELDS.includes(
      parsed,
    )
  ) {
    return parsed;
  }
  return "productDescription";
}

function buildAssistantTurnSuggestions({
  message,
  suggestions,
}) {
  return {
    action:
      PRODUCTION_ASSISTANT_ACTION_SUGGESTIONS,
    message:
      message ||
      "Choose one of these next steps to continue.",
    payload: {
      suggestions:
        normalizeAssistantSuggestions(
          suggestions,
        ),
    },
  };
}

function buildAssistantTurnClarify({
  message,
  question,
  choices,
  requiredField,
  contextSummary,
}) {
  return {
    action:
      PRODUCTION_ASSISTANT_ACTION_CLARIFY,
    message:
      message ||
      "I need one more detail before drafting the plan.",
    payload: {
      question:
        question ||
        "Please provide the missing detail.",
      choices:
        normalizeAssistantSuggestions(
          choices,
        ),
      requiredField:
        resolveAssistantRequiredField(
          requiredField,
        ),
      contextSummary:
        contextSummary
          ?.toString()
          .trim() || "",
    },
  };
}

function buildAssistantTurnDraftProduct({
  message,
  draftProduct,
  confirmationQuestion,
}) {
  return {
    action:
      PRODUCTION_ASSISTANT_ACTION_DRAFT_PRODUCT,
    message:
      message ||
      "I drafted a product for your confirmation.",
    payload: {
      draftProduct: {
        name:
          draftProduct?.name
            ?.toString()
            .trim() || "New Product",
        category:
          draftProduct?.category
            ?.toString()
            .trim() || "crop",
        unit:
          draftProduct?.unit
            ?.toString()
            .trim() || "bags",
        notes:
          draftProduct?.notes
            ?.toString()
            .trim() || "",
        lifecycleDaysEstimate: Math.max(
          1,
          Math.floor(
            Number(
              draftProduct
                ?.lifecycleDaysEstimate || 84,
            ),
          ),
        ),
      },
      createProductPayload: {
        name:
          draftProduct?.name
            ?.toString()
            .trim() || "New Product",
        category:
          draftProduct?.category
            ?.toString()
            .trim() || "crop",
        unit:
          draftProduct?.unit
            ?.toString()
            .trim() || "bags",
        notes:
          draftProduct?.notes
            ?.toString()
            .trim() || "",
      },
      confirmationQuestion:
        confirmationQuestion
          ?.toString()
          .trim() ||
        "Create this product and continue to plan generation?",
    },
  };
}

function resolveLifecycleDaysEstimateFromInput(
  userInput,
) {
  const normalized = (
    userInput || ""
  )
    .toString()
    .trim()
    .toLowerCase();
  if (!normalized) return 84;
  if (
    normalized.includes("rice")
  ) {
    return 120;
  }
  if (
    normalized.includes("bean") ||
    normalized.includes("cowpea")
  ) {
    return 90;
  }
  if (
    normalized.includes("maize") ||
    normalized.includes("corn")
  ) {
    return 105;
  }
  return 84;
}

function buildAssistantDraftProductFromInput(
  userInput,
) {
  const raw = (
    userInput || ""
  )
    .toString()
    .trim()
    .replace(/\s+/g, " ");
  const titleWords = raw
    .split(" ")
    .filter(Boolean)
    .slice(0, 4)
    .map((word) =>
      `${word.slice(0, 1).toUpperCase()}${word.slice(1).toLowerCase()}`,
    );
  const name =
    titleWords.length > 0 ?
      titleWords.join(" ")
    : "New Crop Product";
  return {
    name,
    category: "crop",
    unit: "bags",
    notes:
      raw ||
      "Product drafted by production planning assistant.",
    lifecycleDaysEstimate:
      resolveLifecycleDaysEstimateFromInput(
        raw,
      ),
  };
}

function findAssistantProductMatch({
  userInput,
  products,
}) {
  const normalizedInput = (
    userInput || ""
  )
    .toString()
    .trim()
    .toLowerCase();
  if (!normalizedInput) {
    return null;
  }
  const normalizedTokens =
    normalizedInput
      .split(/[^a-z0-9]+/g)
      .filter(Boolean);
  let best = null;
  let bestScore = 0;

  products.forEach((product) => {
    const name = (
      product?.name || ""
    )
      .toString()
      .toLowerCase();
    const description = (
      product?.description || ""
    )
      .toString()
      .toLowerCase();
    if (!name) {
      return;
    }

    let score = 0;
    if (
      normalizedInput.includes(name)
    ) {
      score += 10;
    }
    normalizedTokens.forEach((token) => {
      if (token.length < 3) {
        return;
      }
      if (name.includes(token)) {
        score += 3;
      }
      if (description.includes(token)) {
        score += 1;
      }
    });

    if (score > bestScore) {
      bestScore = score;
      best = product;
    }
  });

  if (bestScore <= 0) {
    return null;
  }
  return best;
}

function normalizeAssistantWarningList(
  warnings,
) {
  const list = (
    Array.isArray(warnings) ? warnings : []
  )
    .map((warning, index) => {
      if (
        warning &&
        typeof warning === "object"
      ) {
        return {
          code:
            warning.code
              ?.toString()
              .trim() ||
            `WARNING_${index + 1}`,
          message:
            warning.message
              ?.toString()
              .trim() ||
            "Plan warning",
        };
      }
      const text =
        warning == null ?
          ""
        : warning.toString().trim();
      if (!text) {
        return null;
      }
      return {
        code: `WARNING_${index + 1}`,
        message: text,
      };
    })
    .filter(Boolean);
  return list;
}

// WHY: Assistant payload should honor effective schedule policy defaults without crashing on partial AI output.
function resolveAssistantSchedulePolicyForPayload(
  aiDraftResponse,
) {
  const rawPolicy =
    aiDraftResponse?.schedulePolicy &&
    typeof aiDraftResponse.schedulePolicy ===
      "object" ?
      aiDraftResponse.schedulePolicy
    : null;
  return normalizeSchedulePolicyInput(
    rawPolicy,
    buildDefaultSchedulePolicy(),
  );
}

// WHY: Task timestamps should map deterministic date + block clock values.
function buildIsoDateTimeFromDayClock({
  day,
  clock,
}) {
  const parsedClock =
    parseTimeBlockClock(clock) ||
    parseTimeBlockClock(
      WORK_SCHEDULE_FALLBACK_BLOCKS[0]
        ?.start,
    );
  const hour =
    parsedClock?.hour || 9;
  const minute =
    parsedClock?.minute || 0;
  return formatIsoDateTimeSeconds(
    new Date(
      Date.UTC(
        day.getUTCFullYear(),
        day.getUTCMonth(),
        day.getUTCDate(),
        hour,
        minute,
        0,
      ),
    ),
  );
}

// WHY: Assistant fallback roles should stay inside supported staff role vocabulary.
function resolveAssistantFallbackRole(
  index,
) {
  const normalizedKnownRoles =
    STAFF_CAPACITY_ROLE_BUCKETS.map(
      (role) =>
        normalizeStaffIdInput(role),
    ).filter(Boolean);
  const normalizedStaffRoles =
    STAFF_ROLE_VALUES.map((role) =>
      normalizeStaffIdInput(role),
    ).filter(Boolean);
  const pool = Array.from(
    new Set([
      ...normalizedKnownRoles,
      ...normalizedStaffRoles,
    ]),
  );
  if (pool.length === 0) {
    return "farmer";
  }
  const safeIndex = Math.max(
    0,
    Number(index) || 0,
  );
  return pool[safeIndex % pool.length];
}

function countAssistantPhaseTasks(phases) {
  return (
    Array.isArray(phases) ? phases : []
  ).reduce((sum, phase) => {
    const tasks = Array.isArray(
      phase?.tasks,
    ) ?
      phase.tasks
    : [];
    return sum + tasks.length;
  }, 0);
}

// WHY: Assistant should still return a full weekly/day schedule when model output omits tasks.
function buildAssistantFallbackDailyPhases({
  resolvedRange,
  productName,
  schedulePolicy,
}) {
  const rangeStart =
    parseDateInput(
      `${resolvedRange.startDate}T00:00:00.000Z`,
    ) ||
    parseDateInput(
      resolvedRange.startDate,
    ) ||
    new Date();
  const rangeEnd =
    parseDateInput(
      `${resolvedRange.endDate}T00:00:00.000Z`,
    ) ||
    parseDateInput(
      resolvedRange.endDate,
    ) ||
    new Date(
      rangeStart.getTime() + MS_PER_DAY,
    );
  const normalizedPolicy =
    normalizeSchedulePolicyInput(
      schedulePolicy,
      buildDefaultSchedulePolicy(),
    );
  const allowedWeekDays = Array.from(
    new Set([
      ...WORK_SCHEDULE_FALLBACK_WEEK_DAYS,
      ...(
        Array.isArray(
          normalizedPolicy?.workWeekDays,
        ) ?
          normalizedPolicy.workWeekDays
        : []
      ),
    ]),
  ).sort((left, right) => left - right);
  const scheduleBlocks =
    Array.isArray(
      normalizedPolicy?.blocks,
    ) &&
    normalizedPolicy.blocks.length > 0 ?
      normalizedPolicy.blocks
    : WORK_SCHEDULE_FALLBACK_BLOCKS;

  const fallbackProductName = (
    productName || "production"
  )
    .toString()
    .trim();
  const phasesByWeek = new Map();
  let scheduledDayIndex = 0;
  let generatedTaskCount = 0;
  const startDay = new Date(
    Date.UTC(
      rangeStart.getUTCFullYear(),
      rangeStart.getUTCMonth(),
      rangeStart.getUTCDate(),
      0,
      0,
      0,
    ),
  );
  const endDay = new Date(
    Date.UTC(
      rangeEnd.getUTCFullYear(),
      rangeEnd.getUTCMonth(),
      rangeEnd.getUTCDate(),
      0,
      0,
      0,
    ),
  );

  for (
    let cursor = new Date(startDay);
    cursor.getTime() <= endDay.getTime();
    cursor = new Date(
      cursor.getTime() + MS_PER_DAY,
    )
  ) {
    const weekDay =
      cursor.getUTCDay() === 0 ?
        7
      : cursor.getUTCDay();
    if (
      !allowedWeekDays.includes(weekDay)
    ) {
      continue;
    }

    const weekOrder =
      Math.floor(scheduledDayIndex / 7) + 1;
    if (!phasesByWeek.has(weekOrder)) {
      phasesByWeek.set(weekOrder, {
        name: `Week ${weekOrder}`,
        order: weekOrder,
        estimatedDays: 7,
        tasks: [],
      });
    }
    const phase =
      phasesByWeek.get(weekOrder);
    scheduleBlocks.forEach(
      (block, blockIndex) => {
        const template =
          ASSISTANT_FALLBACK_TASK_TEMPLATES[
            (scheduledDayIndex +
              blockIndex) %
              ASSISTANT_FALLBACK_TASK_TEMPLATES.length
          ];
        const roleRequired =
          resolveAssistantFallbackRole(
            scheduledDayIndex +
              blockIndex,
          );
        const requiredHeadcount =
          roleRequired === "farmer" ?
            2
          : 1;
        const startDate =
          buildIsoDateTimeFromDayClock({
            day: cursor,
            clock: block?.start,
          });
        const dueDate =
          buildIsoDateTimeFromDayClock({
            day: cursor,
            clock: block?.end,
          });
        phase.tasks.push({
          title: `${template} - ${fallbackProductName}`,
          roleRequired,
          requiredHeadcount,
          weight: 1,
          instructions:
            "Daily execution task generated from assistant fallback schedule.",
          startDate,
          dueDate,
          assignedStaffProfileIds: [],
        });
        generatedTaskCount += 1;
      },
    );
    scheduledDayIndex += 1;
  }

  const phases = Array.from(
    phasesByWeek.values(),
  );
  debug(
    "BUSINESS CONTROLLER: assistant fallback daily phases generated",
    {
      startDate:
        resolvedRange.startDate,
      endDate:
        resolvedRange.endDate,
      days: resolvedRange.days,
      weeks: resolvedRange.weeks,
      allowedWeekDays,
      blockCount:
        scheduleBlocks.length,
      phaseCount: phases.length,
      taskCount: generatedTaskCount,
    },
  );
  return phases;
}

function buildAssistantPlanDraftPayload({
  aiDraftResponse,
  selectedProduct,
}) {
  const summary =
    aiDraftResponse?.summary &&
    typeof aiDraftResponse.summary ===
      "object" ?
      aiDraftResponse.summary
    : {};
  const draft =
    aiDraftResponse?.draft &&
    typeof aiDraftResponse.draft ===
      "object" ?
      aiDraftResponse.draft
    : {};
  const phaseRows =
    Array.isArray(draft.phases) ?
      draft.phases
    : [];
  const schedulePolicy =
    resolveAssistantSchedulePolicyForPayload(
      aiDraftResponse,
    );
  const fallbackRange =
    buildPlanningRangeSummary({
      startDate:
        parseDateInput(
          summary.startDate ||
            draft.startDate ||
            new Date(),
        ) || new Date(),
      endDate:
        parseDateInput(
          summary.endDate ||
            draft.endDate ||
            new Date(
              Date.now() + MS_PER_DAY,
            ),
        ) ||
        new Date(Date.now() + MS_PER_DAY),
      productId:
        selectedProduct?._id?.toString() ||
        draft.productId ||
        "",
      cropSubtype:
        summary.cropSubtype || "",
    });
  const startDateValue =
    summary.startDate
      ?.toString()
      .trim() ||
    draft.startDate
      ?.toString()
      .trim() ||
    fallbackRange.startDate;
  const endDateValue =
    summary.endDate
      ?.toString()
      .trim() ||
    draft.endDate
      ?.toString()
      .trim() ||
    fallbackRange.endDate;
  const resolvedRange =
    buildPlanningRangeSummary({
      startDate:
        parseDateInput(
          startDateValue,
        ) ||
        parseDateInput(
          fallbackRange.startDate,
        ) ||
        new Date(),
      endDate:
        parseDateInput(endDateValue) ||
        parseDateInput(
          fallbackRange.endDate,
        ) ||
        new Date(
          Date.now() + MS_PER_DAY,
        ),
      productId:
        selectedProduct?._id?.toString() ||
        draft.productId ||
        "",
      cropSubtype:
        summary.cropSubtype || "",
    });
  const defaultBlock =
    schedulePolicy.blocks[0] ||
    WORK_SCHEDULE_FALLBACK_BLOCKS[0];
  const rangeStartDay =
    parseDateInput(
      `${resolvedRange.startDate}T00:00:00.000Z`,
    ) ||
    parseDateInput(
      resolvedRange.startDate,
    ) ||
    new Date();
  let phases = phaseRows.map(
    (phase, phaseIndex) => {
      const tasks = Array.isArray(
        phase?.tasks,
      ) ?
        phase.tasks
      : [];
      return {
        name:
          phase?.name
            ?.toString()
            .trim() ||
          `${DEFAULT_PHASE_NAME_PREFIX} ${phaseIndex + 1}`,
        order: Math.max(
          1,
          Math.floor(
            Number(
              phase?.order ||
                phaseIndex + 1,
            ),
          ),
        ),
        estimatedDays: Math.max(
          1,
          Math.floor(
            Number(
              phase?.estimatedDays || 1,
            ),
          ),
        ),
        tasks: tasks.map(
          (task) => {
            const assignedStaffProfileIds =
              resolveTaskAssignedStaffIds(
                task,
              );
            const taskStart =
              task?.startDate ||
              buildIsoDateTimeFromDayClock({
                day: rangeStartDay,
                clock:
                  defaultBlock?.start,
              });
            const taskDue =
              task?.dueDate ||
              buildIsoDateTimeFromDayClock({
                day: rangeStartDay,
                clock: defaultBlock?.end,
              });
            return {
              title:
                task?.title
                  ?.toString()
                  .trim() ||
                DEFAULT_TASK_TITLE,
              roleRequired:
                normalizeStaffIdInput(
                  task?.roleRequired,
                ) ||
                STAFF_ROLE_VALUES[0] ||
                "farmer",
              requiredHeadcount:
                normalizeDraftTaskHeadcount(
                  task?.requiredHeadcount,
                ),
              weight: Math.max(
                1,
                Math.floor(
                  Number(
                    task?.weight || 1,
                  ),
                ),
              ),
              instructions:
                task?.instructions
                  ?.toString()
                  .trim() || "",
              startDate:
                formatIsoDateTimeSeconds(
                  taskStart,
                ),
              dueDate:
                formatIsoDateTimeSeconds(
                  taskDue,
                ),
              assignedStaffProfileIds,
            };
          },
        ),
      };
    },
  );
  const existingTaskCount =
    countAssistantPhaseTasks(phases);
  const warnings =
    normalizeAssistantWarningList(
      aiDraftResponse?.warnings,
    );
  if (existingTaskCount === 0) {
    phases =
      buildAssistantFallbackDailyPhases({
        resolvedRange,
        productName:
          selectedProduct?.name ||
          draft.productName ||
          "",
        schedulePolicy,
      });
    warnings.push({
      code:
        "DAILY_FALLBACK_GENERATED",
      message:
        "AI returned no scheduled tasks, so a full daily timeline was generated from start and end dates.",
    });
  }
  const totalTaskCount =
    countAssistantPhaseTasks(phases);
  debug(
    "BUSINESS CONTROLLER: assistant plan payload normalized",
    {
      startDate:
        resolvedRange.startDate,
      endDate:
        resolvedRange.endDate,
      weeks: resolvedRange.weeks,
      days: resolvedRange.days,
      phaseCount: phases.length,
      taskCount: totalTaskCount,
      fallbackUsed:
        existingTaskCount === 0,
    },
  );
  return {
    productId:
      selectedProduct?._id?.toString() ||
      draft.productId
        ?.toString()
        .trim() ||
      "",
    productName:
      selectedProduct?.name
        ?.toString()
        .trim() || "",
    startDate: resolvedRange.startDate,
    endDate: resolvedRange.endDate,
    days: resolvedRange.days,
    weeks: resolvedRange.weeks,
    phases,
    warnings,
  };
}

// WHY: Assistant endpoint reuses existing draft handler so scheduling logic stays single-sourced.
async function invokeControllerHandlerJson({
  handler,
  request,
}) {
  return new Promise(
    (resolve, reject) => {
      let settled = false;
      const response = {
        _statusCode: 200,
        status(code) {
          this._statusCode =
            Number.isFinite(code) ?
              Number(code)
            : 200;
          return this;
        },
        json(payload) {
          if (settled) {
            return payload;
          }
          settled = true;
          resolve({
            statusCode:
              this._statusCode || 200,
            payload,
          });
          return payload;
        },
      };

      Promise.resolve(
        handler(request, response),
      )
        .then(() => {
          if (!settled) {
            settled = true;
            resolve({
              statusCode:
                response._statusCode ||
                200,
              payload: null,
            });
          }
        })
        .catch((error) => {
          if (!settled) {
            settled = true;
            reject(error);
          }
        });
    },
  );
}

// WHY: Notes keep a reversible audit trail for review actions without data loss.
function buildTaskProgressRejectNote({
  reason,
  actorId,
  rejectedAt,
}) {
  return `${TASK_PROGRESS_REJECTION_NOTE_PREFIX} ${rejectedAt.toISOString()} reviewer=${actorId?.toString() || "unknown"} reason=${reason}`;
}

// WHY: Timeline indicators must distinguish pending vs approved vs reviewed issues.
function resolveTaskProgressApprovalState(
  record,
) {
  if (record?.approvedAt) {
    return TASK_PROGRESS_APPROVAL_APPROVED;
  }

  const notes =
    record?.notes
      ?.toString() || "";
  if (
    notes.includes(
      TASK_PROGRESS_REJECTION_NOTE_PREFIX,
    )
  ) {
    return TASK_PROGRESS_APPROVAL_NEEDS_REVIEW;
  }

  return TASK_PROGRESS_APPROVAL_PENDING;
}

// WHY: Review actions must stay tenant-scoped and plan-aware.
async function loadTaskProgressInBusinessScope({
  progressId,
  businessId,
}) {
  const progress =
    await TaskProgress.findById(progressId);
  if (!progress) {
    return {
      progress: null,
      plan: null,
    };
  }

  const plan =
    await ProductionPlan.findOne({
      _id: progress.planId,
      businessId,
    }).lean();

  if (!plan) {
    return {
      progress: null,
      plan: null,
    };
  }

  return {
    progress,
    plan,
  };
}

// WHY: Batch responses must preserve per-entry diagnostics without aborting the full request.
function buildBatchTaskProgressError({
  index,
  taskId,
  staffId,
  errorCode,
  error,
}) {
  return {
    index,
    taskId: taskId || "",
    staffId: staffId || "",
    errorCode,
    error,
  };
}

// WHY: Pre-order cap ratio must remain conservative to protect delivery trust.
function parsePreorderCapRatio(value) {
  if (value == null || value === "") {
    return DEFAULT_PREORDER_CAP_RATIO;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return null;
  }
  if (
    parsed < PREORDER_CAP_RATIO_MIN ||
    parsed > PREORDER_CAP_RATIO_MAX
  ) {
    return null;
  }
  return parsed;
}

// WHY: Keep pre-order summary shape consistent for detail and update responses.
function buildPreorderSummary(
  product,
  capConfidence = null,
) {
  const cap = Math.max(
    0,
    Number(product?.preorderCapQuantity || 0),
  );
  const reserved = Math.max(
    0,
    Number(product?.preorderReservedQuantity || 0),
  );
  const remaining = Math.max(
    0,
    cap - reserved,
  );
  const normalizedEffectiveCap = Math.max(
    0,
    Number(
      capConfidence?.effectiveCap ?? cap,
    ),
  );
  const normalizedConfidenceScore =
    Number(
      capConfidence?.confidenceScore ?? 1,
    );
  const normalizedCoverage = Number(
    capConfidence
      ?.approvedProgressCoverage ?? 0,
  );

  return {
    productionState:
      product?.productionState ||
      null,
    preorderEnabled:
      product?.preorderEnabled ===
      true,
    preorderCapQuantity: cap,
    effectiveCap:
      normalizedEffectiveCap,
    confidenceScore:
      Number.isFinite(
        normalizedConfidenceScore,
      ) ?
        normalizedConfidenceScore
      : 1,
    approvedProgressCoverage:
      Number.isFinite(
        normalizedCoverage,
      ) ?
        normalizedCoverage
      : 0,
    preorderReservedQuantity:
      reserved,
    preorderRemainingQuantity:
      Math.max(
        0,
        Math.min(
          remaining,
          normalizedEffectiveCap -
            reserved,
        ),
      ),
    conservativeYieldQuantity:
      product
        ?.conservativeYieldQuantity ??
      null,
    conservativeYieldUnit:
      product?.conservativeYieldUnit ||
      "",
  };
}

// WHY: Reservation responses need simple capacity numbers for immediate UX feedback.
function buildReservationSummary(product) {
  const cap = Math.max(
    0,
    Number(product?.preorderCapQuantity || 0),
  );
  const reserved = Math.max(
    0,
    Number(product?.preorderReservedQuantity || 0),
  );
  const remaining = Math.max(
    0,
    cap - reserved,
  );

  return {
    cap,
    reserved,
    remaining,
  };
}

// WHY: Timeline rows must represent real logged execution, not static task plans.
function buildTimelineRows({
  progressRecords,
  tasks,
  phases,
  staffProfiles,
}) {
  const taskMap = new Map(
    tasks.map((task) => [
      task._id?.toString(),
      task,
    ]),
  );
  const phaseMap = new Map(
    phases.map((phase) => [
      phase._id?.toString(),
      phase,
    ]),
  );
  const staffMap = new Map(
    staffProfiles.map((profile) => [
      profile._id?.toString(),
      profile,
    ]),
  );

  return progressRecords.map(
    (record) => {
      const task = taskMap.get(
        record.taskId?.toString(),
      );
      const phase = phaseMap.get(
        task?.phaseId?.toString(),
      );
      const staff = staffMap.get(
        record.staffId?.toString(),
      );
      const expectedPlots = Number(
        record.expectedPlots || 0,
      );
      const actualPlots = Number(
        record.actualPlots || 0,
      );
      // WHY: Zero-output days are explicit blocked records, not implicit misses.
      let status =
        TASK_PROGRESS_STATUS_BEHIND;
      if (actualPlots === 0) {
        status =
          TASK_PROGRESS_STATUS_BLOCKED;
      } else if (
        actualPlots >= expectedPlots
      ) {
        status =
          TASK_PROGRESS_STATUS_ON_TRACK;
      }
      const delayReason =
        record.delayReason ||
        "none";
      // WHY: Delay column reflects execution outcome rather than raw reason value.
      const delay =
        status ===
          TASK_PROGRESS_STATUS_ON_TRACK ?
          TASK_PROGRESS_DELAY_ON_TIME
        : TASK_PROGRESS_DELAY_LATE;
      const approvalState =
        resolveTaskProgressApprovalState(
          record,
        );
      const farmerName =
        staff?.userId?.name ||
        staff?.userId?.email ||
        "";

      return {
        id: record._id,
        workDate: record.workDate,
        taskId: record.taskId,
        planId: record.planId,
        staffId: record.staffId,
        taskTitle: task?.title || "",
        phaseName: phase?.name || "",
        farmerName,
        expectedPlots,
        actualPlots,
        status,
        delay,
        delayReason,
        approvalState,
        approvedBy:
          record.approvedBy || null,
        approvedAt:
          record.approvedAt || null,
        notes: record.notes || "",
      };
    },
  );
}

// WHY: Manager dashboards need support visibility, not punishment automation.
function buildStaffProgressScores({
  progressRecords,
  staffProfiles,
}) {
  const staffMap = new Map(
    staffProfiles.map((profile) => [
      profile._id?.toString(),
      profile,
    ]),
  );
  const scoreByStaff = new Map();

  progressRecords.forEach(
    (record) => {
      const staffId =
        record.staffId?.toString();
      if (!staffId) {
        return;
      }
      const expected = Number(
        record.expectedPlots || 0,
      );
      const actual = Number(
        record.actualPlots || 0,
      );
      if (!scoreByStaff.has(staffId)) {
        scoreByStaff.set(staffId, {
          staffId: record.staffId,
          totalExpected: 0,
          totalActual: 0,
        });
      }
      const score =
        scoreByStaff.get(staffId);
      score.totalExpected += expected;
      score.totalActual += actual;
    },
  );

  return Array.from(
    scoreByStaff.values(),
  ).map((score) => {
    const denominator = Math.max(
      1,
      score.totalExpected,
    );
    const ratio =
      score.totalActual /
      denominator;
    let status =
      STAFF_PROGRESS_OFF_TRACK;
    if (ratio >= 0.9) {
      status =
        STAFF_PROGRESS_ON_TRACK;
    } else if (ratio >= 0.7) {
      status =
        STAFF_PROGRESS_NEEDS_ATTENTION;
    }
    const staff = staffMap.get(
      score.staffId?.toString(),
    );
    return {
      staffId: score.staffId,
      farmerName:
        staff?.userId?.name ||
        staff?.userId?.email ||
        "",
      totalExpected: score.totalExpected,
      totalActual: score.totalActual,
      completionRatio: ratio,
      status,
    };
  });
}

// WHY: Auto-calculate phase dates across a plan duration.
function buildPhaseSchedule({
  startDate,
  endDate,
  phases,
}) {
  const {
    phaseStart: normalizedStart,
    phaseEnd: normalizedEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart: startDate,
    phaseEnd: endDate,
  });
  const totalMs =
    normalizedEnd.getTime() -
    normalizedStart.getTime();
  const phaseCount = phases.length;
  const baseMs =
    phaseCount > 0 ?
      Math.floor(totalMs / phaseCount)
    : 0;

  let cursor = new Date(
    normalizedStart,
  );
  return phases.map((phase, index) => {
    const isLast =
      index === phaseCount - 1;
    const phaseStart = new Date(cursor);
    const phaseEnd =
      isLast ?
        new Date(
          normalizedEnd,
        )
      : new Date(
          cursor.getTime() + baseMs,
        );
    cursor = new Date(phaseEnd);

    return {
      ...phase,
      startDate: phaseStart,
      endDate: phaseEnd,
    };
  });
}

// WHY: Keep previous millisecond-based scheduling as a fallback for edge cases.
function buildTaskScheduleLegacy({
  phaseStart,
  phaseEnd,
  tasks,
}) {
  const {
    phaseStart:
      normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart,
    phaseEnd,
  });
  const totalMs =
    normalizedPhaseEnd.getTime() -
    normalizedPhaseStart.getTime();
  const taskCount = tasks.length;
  if (taskCount === 0) {
    return [];
  }

  const safeWeights = tasks.map(
    (task) =>
      (
        Number.isFinite(task.weight) &&
        Number(task.weight) > 0
      ) ?
        Math.floor(Number(task.weight))
      : 1,
  );
  const totalWeight =
    safeWeights.reduce(
      (sum, weight) => sum + weight,
      0,
    );
  const baseUnitMs =
    totalWeight > 0 ?
      totalMs / totalWeight
    : 0;

  let cursor = new Date(
    normalizedPhaseStart,
  );
  return tasks.map((task, index) => {
    const isLast =
      index === taskCount - 1;
    const durationMs =
      isLast ?
        normalizedPhaseEnd.getTime() -
        cursor.getTime()
      : Math.floor(
          baseUnitMs *
            safeWeights[index],
        );
    const taskStart = new Date(cursor);
    const taskEnd = new Date(
      cursor.getTime() + durationMs,
    );
    cursor = new Date(taskEnd);

    return {
      ...task,
      startDate: taskStart,
      dueDate: taskEnd,
      weight: safeWeights[index],
    };
  });
}

// WHY: Normalize to the day key so block generation is deterministic.
function startOfDayLocal(date) {
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    0,
    0,
    0,
    0,
  );
}

// WHY: API weekdays are Monday=1..Sunday=7 while JS Date uses Sunday=0..Saturday=6.
function resolveWeekDayNumber(date) {
  const day = date.getDay();
  return day === 0 ? 7 : day;
}

// WHY: Build reusable per-day working blocks from configurable policy and clamp to phase boundaries.
function buildPhaseWorkBlocks({
  phaseStart,
  phaseEnd,
  schedulePolicy,
}) {
  const {
    phaseStart:
      normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart,
    phaseEnd,
  });
  const effectivePolicy =
    normalizeSchedulePolicyInput(
      schedulePolicy,
      buildDefaultSchedulePolicy(),
    );
  const workDaySet = new Set(
    effectivePolicy.workWeekDays,
  );
  const parsedBlocks =
    effectivePolicy.blocks
      .map((block) => {
        const parsedStart =
          parseTimeBlockClock(
            block?.start,
          );
        const parsedEnd =
          parseTimeBlockClock(
            block?.end,
          );
        if (
          !parsedStart ||
          !parsedEnd ||
          parsedEnd.totalMinutes <=
            parsedStart.totalMinutes
        ) {
          return null;
        }
        return {
          startHour:
            parsedStart.hour,
          startMinute:
            parsedStart.minute,
          endHour: parsedEnd.hour,
          endMinute:
            parsedEnd.minute,
          label: `${parsedStart.raw}-${parsedEnd.raw}`,
        };
      })
      .filter(Boolean);
  const blocks = [];
  const dayCursor = startOfDayLocal(
    normalizedPhaseStart,
  );
  const finalDay = startOfDayLocal(
    normalizedPhaseEnd,
  );

  while (dayCursor <= finalDay) {
    if (
      !workDaySet.has(
        resolveWeekDayNumber(dayCursor),
      )
    ) {
      dayCursor.setDate(
        dayCursor.getDate() + 1,
      );
      continue;
    }

    parsedBlocks.forEach(
      (blockTemplate) => {
        const blockStart = new Date(
          dayCursor.getFullYear(),
          dayCursor.getMonth(),
          dayCursor.getDate(),
          blockTemplate.startHour,
          blockTemplate.startMinute,
          0,
          0,
        );
        const blockEnd = new Date(
          dayCursor.getFullYear(),
          dayCursor.getMonth(),
          dayCursor.getDate(),
          blockTemplate.endHour,
          blockTemplate.endMinute,
          0,
          0,
        );

        const clampedStart = new Date(
          Math.max(
            blockStart.getTime(),
            normalizedPhaseStart.getTime(),
          ),
        );
        const clampedEnd = new Date(
          Math.min(
            blockEnd.getTime(),
            normalizedPhaseEnd.getTime(),
          ),
        );
        const blockDurationMs =
          clampedEnd.getTime() -
          clampedStart.getTime();

        if (blockDurationMs > 0) {
          blocks.push({
            start: clampedStart,
            end: clampedEnd,
            remainingMs:
              blockDurationMs,
            label:
              blockTemplate.label,
          });
        }
      },
    );

    dayCursor.setDate(
      dayCursor.getDate() + 1,
    );
  }

  return blocks;
}

// WHY: Allocate total available calendar time to tasks by weight with a humane minimum slot.
function allocateTaskDurationsByWeight({
  safeWeights,
  totalAvailableMs,
  minTaskSlotMs,
}) {
  if (safeWeights.length === 0) {
    return [];
  }

  const totalWeight =
    safeWeights.reduce(
      (sum, weight) => sum + weight,
      0,
    );
  const safeTotalWeight = Math.max(
    1,
    totalWeight,
  );
  const durations = safeWeights.map(
    (weight) =>
      Math.max(
        minTaskSlotMs,
        Math.floor(
          (totalAvailableMs * weight) /
            safeTotalWeight,
        ),
      ),
  );

  const minimumRequiredMs =
    safeWeights.length *
    minTaskSlotMs;
  if (
    minimumRequiredMs >
    totalAvailableMs
  ) {
    return null;
  }

  let allocatedMs = durations.reduce(
    (sum, ms) => sum + ms,
    0,
  );
  let overflowMs =
    allocatedMs - totalAvailableMs;

  // WHY: Preserve minimum slot while trimming rounding overflow.
  while (overflowMs > 0) {
    let reduced = false;
    for (
      let index = durations.length - 1;
      index >= 0 && overflowMs > 0;
      index -= 1
    ) {
      const reducibleMs = Math.max(
        0,
        durations[index] -
          minTaskSlotMs,
      );
      if (reducibleMs <= 0) {
        continue;
      }
      const reduceBy = Math.min(
        reducibleMs,
        overflowMs,
      );
      durations[index] -= reduceBy;
      overflowMs -= reduceBy;
      reduced = true;
    }
    if (!reduced) {
      return null;
    }
  }

  allocatedMs = durations.reduce(
    (sum, ms) => sum + ms,
    0,
  );
  const remainderMs =
    totalAvailableMs - allocatedMs;
  if (remainderMs > 0) {
    // WHY: Assign remainder to the final task to preserve exact coverage.
    durations[durations.length - 1] +=
      remainderMs;
  }

  return durations;
}

function scheduleTasksAcrossBlocks({
  tasks,
  safeWeights,
  taskDurations,
  blocks,
  phaseStart,
  phaseEnd,
  logContext = {},
}) {
  let blockIndex = 0;
  let blockOffsetMs = 0;
  const scheduledTasks = tasks.map(
    (task, taskIndex) => {
      let remainingTaskMs =
        taskDurations[taskIndex];
      let taskStartMs = null;
      let taskEndMs = null;

      // WHY: Pack each task sequentially across the available day blocks.
      while (remainingTaskMs > 0) {
        while (
          blockIndex < blocks.length &&
          blockOffsetMs >=
            blocks[blockIndex]
              .remainingMs
        ) {
          blockIndex += 1;
          blockOffsetMs = 0;
        }
        if (blockIndex >= blocks.length) {
          break;
        }

        const block =
          blocks[blockIndex];
        const chunkStartMs =
          block.start.getTime() +
          blockOffsetMs;
        const blockRemainingMs =
          block.remainingMs -
          blockOffsetMs;
        const chunkMs = Math.min(
          remainingTaskMs,
          blockRemainingMs,
        );
        if (taskStartMs == null) {
          taskStartMs = chunkStartMs;
        }
        taskEndMs = chunkStartMs + chunkMs;
        remainingTaskMs -= chunkMs;
        blockOffsetMs += chunkMs;
      }

      const fallbackStartMs =
        phaseStart.getTime();
      const fallbackEndMs =
        phaseEnd.getTime();
      const resolvedStartMs = Math.max(
        fallbackStartMs,
        taskStartMs ??
          fallbackStartMs,
      );
      const resolvedEndMs = Math.max(
        resolvedStartMs,
        Math.min(
          fallbackEndMs,
          taskEndMs ?? fallbackEndMs,
        ),
      );
      const taskStart = new Date(
        resolvedStartMs,
      );
      const taskEnd = new Date(
        resolvedEndMs,
      );

      debug(
        "BUSINESS CONTROLLER: buildTaskSchedule - task scheduled",
        {
          ...logContext,
          taskIndex,
          taskTitle:
            task?.title ||
            DEFAULT_TASK_TITLE,
          startDate:
            taskStart.toISOString(),
          dueDate:
            taskEnd.toISOString(),
          requestedDurationMs:
            taskDurations[taskIndex],
          assignedDurationMs:
            taskEnd.getTime() -
            taskStart.getTime(),
          remainingUnassignedMs:
            remainingTaskMs,
        },
      );

      return {
        ...task,
        startDate: taskStart,
        dueDate: taskEnd,
        weight:
          safeWeights[taskIndex],
      };
    },
  );
  return scheduledTasks;
}

function buildTaskScheduleSequential({
  phaseStart,
  phaseEnd,
  tasks,
  schedulePolicy,
  logContext = {},
}) {
  const {
    phaseStart:
      normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart,
    phaseEnd,
  });
  const taskCount = tasks.length;
  if (taskCount === 0) {
    return [];
  }

  const effectivePolicy =
    normalizeSchedulePolicyInput(
      schedulePolicy,
      buildDefaultSchedulePolicy(),
    );
  const minSlotMinutes = Math.max(
    WORK_SCHEDULE_MIN_SLOT_MINUTES,
    Math.min(
      WORK_SCHEDULE_MAX_SLOT_MINUTES,
      Number(
        effectivePolicy.minSlotMinutes ||
          WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES,
      ),
    ),
  );
  const minTaskSlotMs =
    minSlotMinutes * MS_PER_MINUTE;
  const safeWeights = tasks.map(
    (task) =>
      (
        Number.isFinite(task.weight) &&
        Number(task.weight) > 0
      ) ?
        Math.floor(Number(task.weight))
      : 1,
  );
  const blocks = buildPhaseWorkBlocks({
    phaseStart:
      normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
    schedulePolicy:
      effectivePolicy,
  });
  const totalAvailableMs =
    blocks.reduce(
      (sum, block) =>
        sum +
        Number(
          block.remainingMs || 0,
        ),
      0,
    );

  debug(
    "BUSINESS CONTROLLER: buildTaskSchedule - block scheduler start",
    {
      ...logContext,
      phaseStart:
        normalizedPhaseStart.toISOString(),
      phaseEnd:
        normalizedPhaseEnd.toISOString(),
      blockCount: blocks.length,
      workWeekDays:
        effectivePolicy.workWeekDays,
      blocksLabel:
        formatWorkBlocksLabel(
          effectivePolicy.blocks,
        ),
      minSlotMinutes,
      timezone:
        effectivePolicy.timezone,
      totalAvailableMs,
      totalAvailableHours: Number(
        (
          totalAvailableMs /
          MS_PER_HOUR
        ).toFixed(2),
      ),
      taskCount,
    },
  );

  if (
    blocks.length === 0 ||
    totalAvailableMs <= 0
  ) {
    debug(
      "BUSINESS CONTROLLER: buildTaskSchedule - fallback legacy",
      {
        ...logContext,
        reason:
          "NO_CALENDAR_BLOCKS",
        phaseStart:
          normalizedPhaseStart.toISOString(),
        phaseEnd:
          normalizedPhaseEnd.toISOString(),
      },
    );
    return buildTaskScheduleLegacy({
      phaseStart:
        normalizedPhaseStart,
      phaseEnd: normalizedPhaseEnd,
      tasks,
    });
  }

  const taskDurations =
    allocateTaskDurationsByWeight({
      safeWeights,
      totalAvailableMs,
      minTaskSlotMs,
    });

  if (!taskDurations) {
    debug(
      "BUSINESS CONTROLLER: buildTaskSchedule - fallback legacy",
      {
        ...logContext,
        reason:
          "INSUFFICIENT_BLOCK_CAPACITY",
        taskCount,
        minimumRequiredMs:
          taskCount *
          minTaskSlotMs,
        totalAvailableMs,
      },
    );
    return buildTaskScheduleLegacy({
      phaseStart:
        normalizedPhaseStart,
      phaseEnd: normalizedPhaseEnd,
      tasks,
    });
  }

  taskDurations.forEach(
    (durationMs, index) => {
      debug(
        "BUSINESS CONTROLLER: buildTaskSchedule - task duration computed",
        {
          ...logContext,
          taskIndex: index,
          taskTitle:
            tasks[index]?.title ||
            DEFAULT_TASK_TITLE,
          weight: safeWeights[index],
          durationMs,
          durationMinutes: Math.floor(
            durationMs /
              MS_PER_MINUTE,
          ),
        },
      );
    },
  );

  return scheduleTasksAcrossBlocks({
    tasks,
    safeWeights,
    taskDurations,
    blocks,
    phaseStart:
      normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
    logContext,
  });
}

function buildTaskScheduleParallelByRole({
  phaseStart,
  phaseEnd,
  tasks,
  schedulePolicy,
}) {
  const indexed = tasks.map(
    (task, taskIndex) => ({
      task,
      taskIndex,
      role:
        normalizeStaffIdInput(
          task?.roleRequired,
        ) || "unassigned_role",
    }),
  );
  const byRole = new Map();
  indexed.forEach((entry) => {
    if (!byRole.has(entry.role)) {
      byRole.set(entry.role, []);
    }
    byRole.get(entry.role).push(entry);
  });

  debug(
    "BUSINESS CONTROLLER: buildTaskSchedule - parallel role lanes",
    {
      phaseStart:
        phaseStart.toISOString(),
      phaseEnd: phaseEnd.toISOString(),
      taskCount: tasks.length,
      roleLaneCount: byRole.size,
      roles: Array.from(byRole.keys()),
    },
  );

  const resultByIndex =
    new Array(tasks.length);
  byRole.forEach((entries, role) => {
    const laneTasks = entries.map(
      (entry) => entry.task,
    );
    const scheduledLane =
      buildTaskScheduleSequential({
        phaseStart,
        phaseEnd,
        tasks: laneTasks,
        schedulePolicy,
        logContext: {
          laneRole: role,
        },
      });
    scheduledLane.forEach(
      (scheduled, laneIndex) => {
        const sourceEntry =
          entries[laneIndex];
        resultByIndex[
          sourceEntry.taskIndex
        ] = scheduled;
      },
    );
  });

  return resultByIndex.map(
    (task, index) => task || tasks[index],
  );
}

// WHY: Auto-calculate task dates using policy blocks and weight-based durations.
function buildTaskSchedule({
  phaseStart,
  phaseEnd,
  tasks,
  schedulePolicy = null,
  allowParallelByRole = false,
}) {
  if (allowParallelByRole) {
    return buildTaskScheduleParallelByRole(
      {
        phaseStart,
        phaseEnd,
        tasks,
        schedulePolicy,
      },
    );
  }
  return buildTaskScheduleSequential({
    phaseStart,
    phaseEnd,
    tasks,
    schedulePolicy,
  });
}

// WHY: Summarize task + output performance for KPI dashboards.
function computeProductionKpis({
  phases,
  tasks,
  outputs,
}) {
  const totalTasks = tasks.length;
  const completedTasks = tasks.filter(
    (task) =>
      task.status ===
        PRODUCTION_TASK_STATUS_DONE ||
      Boolean(task.completedAt),
  );
  const completedCount =
    completedTasks.length;
  const onTimeCount =
    completedTasks.filter((task) => {
      if (
        !task.completedAt ||
        !task.dueDate
      ) {
        return false;
      }
      return (
        new Date(task.completedAt) <=
        new Date(task.dueDate)
      );
    }).length;

  const totalDelayDays =
    completedTasks.reduce(
      (sum, task) => {
        if (
          !task.completedAt ||
          !task.dueDate
        ) {
          return sum;
        }
        const delayMs =
          new Date(task.completedAt) -
          new Date(task.dueDate);
        const delayDays = Math.max(
          0,
          Math.floor(
            delayMs / MS_PER_DAY,
          ),
        );
        return sum + delayDays;
      },
      0,
    );

  const phaseCompletion = phases.map(
    (phase) => {
      const phaseTasks = tasks.filter(
        (task) =>
          task.phaseId?.toString() ===
          phase._id?.toString(),
      );
      const phaseDone =
        phaseTasks.filter(
          (task) =>
            task.status ===
              PRODUCTION_TASK_STATUS_DONE ||
            Boolean(task.completedAt),
        );
      return {
        phaseId: phase._id,
        name: phase.name,
        totalTasks: phaseTasks.length,
        completedTasks:
          phaseDone.length,
        completionRate:
          phaseTasks.length > 0 ?
            phaseDone.length /
            phaseTasks.length
          : 0,
      };
    },
  );

  const staffPerformance = {};
  completedTasks.forEach((task) => {
    const staffId =
      task.assignedStaffId?.toString();
    if (!staffId) return;
    if (!staffPerformance[staffId]) {
      staffPerformance[staffId] = {
        completedTasks: 0,
        totalDelayDays: 0,
      };
    }
    const delayMs =
      new Date(task.completedAt) -
      new Date(
        task.dueDate ||
          task.completedAt,
      );
    const delayDays = Math.max(
      0,
      Math.floor(delayMs / MS_PER_DAY),
    );
    staffPerformance[
      staffId
    ].completedTasks += 1;
    staffPerformance[
      staffId
    ].totalDelayDays += delayDays;
  });

  const staffKpis = Object.entries(
    staffPerformance,
  ).map(([staffId, data]) => ({
    staffId,
    completedTasks: data.completedTasks,
    avgDelayDays:
      data.completedTasks > 0 ?
        data.totalDelayDays /
        data.completedTasks
      : 0,
  }));

  const outputByUnit = outputs.reduce(
    (acc, output) => {
      const unit =
        output.unitType ||
        OUTPUT_UNIT_FALLBACK;
      acc[unit] =
        (acc[unit] || 0) +
        (Number(output.quantity) || 0);
      return acc;
    },
    {},
  );

  return {
    totalTasks,
    completedTasks: completedCount,
    completionRate:
      totalTasks > 0 ?
        completedCount / totalTasks
      : 0,
    onTimeRate:
      completedCount > 0 ?
        onTimeCount / completedCount
      : 0,
    avgDelayDays:
      completedCount > 0 ?
        totalDelayDays / completedCount
      : 0,
    phaseCompletion,
    staffKpis,
    outputByUnit,
  };
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

async function resolveEffectiveSchedulePolicy({
  businessId,
  estateAssetId = null,
}) {
  const businessOwner =
    await User.findById(businessId)
      .select(
        "productionSchedulePolicy",
      )
      .lean();
  const businessPolicy =
    normalizeSchedulePolicyInput(
      businessOwner
        ?.productionSchedulePolicy,
      buildDefaultSchedulePolicy(),
    );

  let estateAsset = null;
  let estatePolicy = null;
  if (estateAssetId) {
    estateAsset =
      await BusinessAsset.findOne({
        _id: estateAssetId,
        businessId,
      })
        .select(
          "name assetType productionSchedulePolicy",
        )
        .lean();
    if (!estateAsset) {
      throw new Error(
        PRODUCTION_COPY.SCHEDULE_POLICY_ESTATE_NOT_FOUND,
      );
    }
    if (estateAsset.assetType !== "estate") {
      throw new Error(
        "Estate asset is required for schedule policy",
      );
    }
    estatePolicy =
      normalizeSchedulePolicyInput(
        estateAsset
          ?.productionSchedulePolicy,
        businessPolicy,
      );
  }

  const effectivePolicy = estatePolicy
    ? normalizeSchedulePolicyInput(
        estatePolicy,
        businessPolicy,
      )
    : businessPolicy;

  return {
    effectivePolicy,
    businessPolicy,
    estatePolicy,
    estateAsset,
  };
}

function resolveCapacityBucketsForStaffRole(
  role,
) {
  const normalizedRole =
    normalizeStaffIdInput(
      role,
    ).toLowerCase();
  switch (normalizedRole) {
    case "farmer":
      return ["farmer"];
    case "auditor":
      return ["qc_officer"];
    case "maintenance_technician":
      return ["machine_operator"];
    case "inventory_keeper":
      return ["storekeeper"];
    case "field_agent":
    case "cleaner":
      return ["packer"];
    case "logistics_driver":
      return ["logistics"];
    case "farm_manager":
    case "estate_manager":
    case "asset_manager":
      return ["supervisor"];
    default:
      return [];
  }
}

function buildEmptyCapacityMap() {
  const roles = {};
  STAFF_CAPACITY_ROLE_BUCKETS.forEach(
    (role) => {
      roles[role] = {
        total: 0,
        available: 0,
      };
    },
  );
  return roles;
}

async function buildStaffCapacitySummary({
  businessId,
  estateAssetId = null,
}) {
  const filter = {
    businessId,
    status: STAFF_STATUS_ACTIVE,
  };
  if (estateAssetId) {
    filter.$or = [
      { estateAssetId },
      { estateAssetId: null },
    ];
  }

  const profiles =
    await BusinessStaffProfile.find(
      filter,
    )
      .select("staffRole")
      .lean();

  const roles = buildEmptyCapacityMap();
  profiles.forEach((profile) => {
    const buckets =
      resolveCapacityBucketsForStaffRole(
        profile?.staffRole,
      );
    buckets.forEach((bucket) => {
      roles[bucket].total += 1;
      roles[bucket].available += 1;
    });
  });

  return {
    estateAssetId:
      estateAssetId ?
        estateAssetId.toString()
      : null,
    roles,
  };
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
  return safeAmount * safeUnitCount;
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
 * POST /business/products/ai-draft
 * Owner + staff: generate an AI draft for product details.
 */
async function generateProductDraftHandler(
  req,
  res,
) {
  debug(PRODUCT_AI_LOG.ENTRY, {
    actorId: req.user?.sub,
    hasPrompt: Boolean(
      req.body?.prompt,
    ),
  });

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const prompt =
      req.body?.prompt
        ?.toString()
        .trim() || "";
    const useReasoning = Boolean(
      req.body?.useReasoning,
    );

    if (!prompt) {
      return res.status(400).json({
        error:
          PRODUCT_AI_COPY.PROMPT_REQUIRED,
      });
    }

    const draft =
      await generateProductDraft({
        prompt,
        useReasoning,
        context: {
          route: req.originalUrl,
          requestId: req.id,
          userRole: actor.role,
          businessId,
          country:
            req.headers?.[
              COUNTRY_HEADER_KEY
            ] || DEFAULT_COUNTRY,
        },
      });

    debug(PRODUCT_AI_LOG.SUCCESS, {
      actorId: actor._id,
      hasDraft: Boolean(draft?.name),
    });

    return res.status(200).json({
      message: PRODUCT_AI_COPY.DRAFT_OK,
      draft,
    });
  } catch (err) {
    debug(PRODUCT_AI_LOG.ERROR, {
      actorId: req.user?.sub,
      error: err.message,
      classification:
        err.classification ||
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        err.errorCode ||
        "PRODUCT_AI_DRAFT_FAILED",
      resolution_hint:
        err.resolutionHint ||
        PRODUCT_AI_ERROR_HINT,
      reason: PRODUCT_AI_ERROR_REASON,
    });
    return res.status(400).json({
      error:
        PRODUCT_AI_COPY.DRAFT_FAILED,
    });
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
      hasStaffRole: Boolean(
        req.body?.staffRole,
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

    const staffRole =
      req.body?.staffRole
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
    if (
      role === "staff" &&
      (!staffRole ||
        staffRole.length === 0)
    ) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_ROLE_REQUIRED,
      });
    }
    if (
      role === "staff" &&
      !STAFF_ROLE_VALUES.includes(
        staffRole,
      )
    ) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_ROLE_INVALID,
      });
    }

    // WHY: Validate estate assignments before issuing an invite.
    const estateAsset =
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
          staffRole,
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
        staffRole:
          invite.staffRole || null,
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
    if (
      invite.role === "staff" &&
      !invite.staffRole
    ) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_ROLE_REQUIRED,
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

    if (invite.role === "staff") {
      const existingProfile =
        await BusinessStaffProfile.findOne(
          {
            userId: user._id,
            businessId:
              invite.businessId,
          },
        );

      if (existingProfile) {
        // WHY: Keep staff profile aligned to the accepted invite.
        existingProfile.staffRole =
          invite.staffRole;
        existingProfile.estateAssetId =
          estateAsset?._id || null;
        existingProfile.status =
          STAFF_STATUS_ACTIVE;
        await existingProfile.save();
        debug(
          "BUSINESS CONTROLLER: acceptInvite - staff profile updated",
          {
            userId: user._id,
            staffProfileId:
              existingProfile._id,
            staffRole: invite.staffRole,
          },
        );
      } else {
        const newProfile =
          await BusinessStaffProfile.create(
            {
              userId: user._id,
              businessId:
                invite.businessId,
              staffRole:
                invite.staffRole,
              estateAssetId:
                estateAsset?._id ||
                null,
              status:
                STAFF_STATUS_ACTIVE,
            },
          );
        debug(
          "BUSINESS CONTROLLER: acceptInvite - staff profile created",
          {
            userId: user._id,
            staffProfileId:
              newProfile._id,
            staffRole: invite.staffRole,
          },
        );
      }
    }

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
        staffRole:
          invite.staffRole || null,
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
 * GET /business/staff
 * Owner + estate manager: list staff profiles.
 */
async function listStaffProfiles(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listStaffProfiles - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canManageStaffDirectory({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_FORBIDDEN,
      });
    }

    // WHY: Estate-scoped staff should only see profiles in their estate.
    const filter = {
      businessId,
    };
    if (
      actor.role === "staff" &&
      actor.estateAssetId
    ) {
      filter.estateAssetId =
        actor.estateAssetId;
    }

    const profiles =
      await BusinessStaffProfile.find(
        filter,
      )
        .populate(
          "userId",
          "name email phone role",
        )
        .lean();

    const staff = profiles.map(
      (profile) => ({
        id: profile._id,
        staffRole: profile.staffRole,
        status: profile.status,
        estateAssetId:
          profile.estateAssetId,
        startDate: profile.startDate,
        endDate: profile.endDate,
        notes: profile.notes,
        user: profile.userId,
      }),
    );

    debug(
      "BUSINESS CONTROLLER: listStaffProfiles - success",
      {
        actorId: actor._id,
        count: staff.length,
      },
    );

    return res.status(200).json({
      message: STAFF_COPY.STAFF_LIST_OK,
      staff,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listStaffProfiles - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/staff/:id
 * Owner + estate manager: fetch a staff profile.
 */
async function getStaffProfile(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getStaffProfile - entry",
    {
      actorId: req.user?.sub,
      staffProfileId: req.params?.id,
    },
  );

  try {
    const staffProfileId =
      req.params?.id?.toString().trim();
    if (!staffProfileId) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_PROFILE_ID_REQUIRED,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canManageStaffDirectory({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_FORBIDDEN,
      });
    }

    const profile =
      await BusinessStaffProfile.findOne(
        {
          _id: staffProfileId,
          businessId,
        },
      )
        .populate(
          "userId",
          "name email phone role",
        )
        .lean();

    if (!profile) {
      return res.status(404).json({
        error:
          STAFF_COPY.STAFF_PROFILE_NOT_FOUND,
      });
    }

    // WHY: Estate-scoped staff must only access their own estate.
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      profile.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_FORBIDDEN,
      });
    }

    debug(
      "BUSINESS CONTROLLER: getStaffProfile - success",
      {
        actorId: actor._id,
        staffProfileId: profile._id,
      },
    );

    return res.status(200).json({
      message:
        STAFF_COPY.STAFF_DETAIL_OK,
      staff: {
        id: profile._id,
        staffRole: profile.staffRole,
        status: profile.status,
        estateAssetId:
          profile.estateAssetId,
        startDate: profile.startDate,
        endDate: profile.endDate,
        notes: profile.notes,
        user: profile.userId,
      },
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getStaffProfile - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/staff/:id/compensation
 * Owner + estate manager: fetch staff compensation.
 */
async function getStaffCompensation(
  req,
  res,
) {
  debug(
    STAFF_COMPENSATION_LOG.FETCH_ENTRY,
    {
      actorId: req.user?.sub,
      staffProfileId: req.params?.id,
    },
  );

  try {
    const staffProfileId =
      req.params?.id?.toString().trim();
    if (!staffProfileId) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_PROFILE_REQUIRED,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      actor.role === "staff" &&
      !staffProfile
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_PROFILE_REQUIRED,
      });
    }

    if (
      !canManageStaffCompensation({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_FORBIDDEN,
      });
    }

    const targetProfile =
      await BusinessStaffProfile.findOne(
        {
          _id: staffProfileId,
          businessId,
        },
      );

    if (!targetProfile) {
      return res.status(404).json({
        error:
          STAFF_COPY.STAFF_PROFILE_NOT_FOUND,
      });
    }

    // WHY: Estate-scoped managers can only access their estate staff.
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      targetProfile.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_FORBIDDEN,
      });
    }

    const compensation =
      await StaffCompensation.findOne({
        staffProfileId:
          targetProfile._id,
        businessId,
      }).lean();

    debug(
      STAFF_COMPENSATION_LOG.FETCH_SUCCESS,
      {
        actorId: actor._id,
        staffProfileId:
          targetProfile._id,
        hasCompensation: Boolean(
          compensation,
        ),
      },
    );

    return res.status(200).json({
      message:
        compensation ?
          STAFF_COMPENSATION_COPY.COMPENSATION_OK
        : STAFF_COMPENSATION_COPY.COMPENSATION_EMPTY,
      compensation,
    });
  } catch (err) {
    debug(
      STAFF_COMPENSATION_LOG.FETCH_ERROR,
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * PATCH /business/staff/:id/compensation
 * Owner + estate manager: create or update compensation.
 */
async function upsertStaffCompensation(
  req,
  res,
) {
  debug(
    STAFF_COMPENSATION_LOG.UPSERT_ENTRY,
    {
      actorId: req.user?.sub,
      staffProfileId: req.params?.id,
      hasAmount:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          STAFF_COMPENSATION_FIELDS.SALARY_AMOUNT,
        ),
      hasCadence:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          STAFF_COMPENSATION_FIELDS.SALARY_CADENCE,
        ),
      hasProfitShare:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          STAFF_COMPENSATION_FIELDS
            .PROFIT_SHARE_PERCENTAGE,
        ),
      hasPayoutTrigger:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          STAFF_COMPENSATION_FIELDS
            .PAYOUT_TRIGGER,
        ),
    },
  );

  try {
    const staffProfileId =
      req.params?.id?.toString().trim();
    if (!staffProfileId) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_PROFILE_REQUIRED,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      actor.role === "staff" &&
      !staffProfile
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_PROFILE_REQUIRED,
      });
    }

    if (
      !canManageStaffCompensation({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_FORBIDDEN,
      });
    }

    const targetProfile =
      await BusinessStaffProfile.findOne(
        {
          _id: staffProfileId,
          businessId,
        },
      );

    if (!targetProfile) {
      return res.status(404).json({
        error:
          STAFF_COPY.STAFF_PROFILE_NOT_FOUND,
      });
    }

    // WHY: Estate-scoped managers can only update their estate staff.
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      targetProfile.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_FORBIDDEN,
      });
    }

    const body = req.body || {};
    const hasAmount =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS.SALARY_AMOUNT,
      );
    const hasCadence =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS.SALARY_CADENCE,
      );
    const hasPayDay =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS.PAY_DAY,
      );
    const hasProfitSharePercentage =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS
          .PROFIT_SHARE_PERCENTAGE,
      );
    const hasIncludesHousing =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS
          .INCLUDES_HOUSING,
      );
    const hasIncludesFeeding =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS
          .INCLUDES_FEEDING,
      );
    const hasPayoutTrigger =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS
          .PAYOUT_TRIGGER,
      );
    const hasNotes =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS.NOTES,
      );

    const rawAmount =
      hasAmount ?
        body[
          STAFF_COMPENSATION_FIELDS
            .SALARY_AMOUNT
        ]
      : null;
    const salaryAmount =
      hasAmount ?
        Number(rawAmount)
      : null;
    if (
      hasAmount &&
      (!Number.isFinite(salaryAmount) ||
        salaryAmount < 0)
    ) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_AMOUNT_INVALID,
      });
    }

    const salaryCadence =
      hasCadence ?
        body[
          STAFF_COMPENSATION_FIELDS
            .SALARY_CADENCE
        ]
          ?.toString()
          .trim()
      : "";

    if (
      hasCadence &&
      (!salaryCadence ||
        !COMPENSATION_CADENCE_VALUES.includes(
          salaryCadence,
        ))
    ) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_CADENCE_INVALID,
      });
    }

    const rawProfitSharePercentage =
      hasProfitSharePercentage ?
        body[
          STAFF_COMPENSATION_FIELDS
            .PROFIT_SHARE_PERCENTAGE
        ]
      : null;
    const profitSharePercentage =
      hasProfitSharePercentage ?
        Number(
          rawProfitSharePercentage,
        )
      : null;
    if (
      hasProfitSharePercentage &&
      (!Number.isFinite(
        profitSharePercentage,
      ) ||
        profitSharePercentage < 0 ||
        profitSharePercentage > 100)
    ) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_PROFIT_SHARE_INVALID,
      });
    }

    const payoutTrigger =
      hasPayoutTrigger ?
        body[
          STAFF_COMPENSATION_FIELDS
            .PAYOUT_TRIGGER
        ]
          ?.toString()
          .trim() || ""
      : "";
    if (
      hasPayoutTrigger &&
      (!payoutTrigger ||
        !COMPENSATION_PAYOUT_TRIGGER_VALUES.includes(
          payoutTrigger,
        ))
    ) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_TRIGGER_INVALID,
      });
    }

    const existing =
      await StaffCompensation.findOne({
        staffProfileId:
          targetProfile._id,
        businessId,
      });

    if (!existing) {
      if (!hasCadence) {
        return res.status(400).json({
          error:
            STAFF_COMPENSATION_COPY.COMPENSATION_CADENCE_REQUIRED,
        });
      }
      const isProfitShareCadence =
        salaryCadence ===
        "profit_share";
      if (
        isProfitShareCadence &&
        !hasProfitSharePercentage
      ) {
        return res.status(400).json({
          error:
            STAFF_COMPENSATION_COPY.COMPENSATION_PROFIT_SHARE_REQUIRED,
        });
      }
      if (
        !isProfitShareCadence &&
        !hasAmount
      ) {
        return res.status(400).json({
          error:
            STAFF_COMPENSATION_COPY.COMPENSATION_AMOUNT_REQUIRED,
        });
      }

      const compensation =
        await StaffCompensation.create({
          staffProfileId:
            targetProfile._id,
          businessId,
          salaryAmountKobo:
            isProfitShareCadence ?
              null
            : Math.floor(
                salaryAmount || 0,
              ),
          salaryCadence,
          payDay:
            hasPayDay ?
              body[
                STAFF_COMPENSATION_FIELDS
                  .PAY_DAY
              ]
                ?.toString()
                .trim() || ""
            : "",
          profitSharePercentage:
            isProfitShareCadence ?
              Number(
                profitSharePercentage,
              )
            : null,
          includesHousing:
            hasIncludesHousing &&
            body[
              STAFF_COMPENSATION_FIELDS
                .INCLUDES_HOUSING
            ] === true,
          includesFeeding:
            hasIncludesFeeding &&
            body[
              STAFF_COMPENSATION_FIELDS
                .INCLUDES_FEEDING
            ] === true,
          payoutTrigger:
            hasPayoutTrigger ?
              payoutTrigger
            : isProfitShareCadence ?
              "sale"
            : "attendance",
          notes:
            hasNotes ?
              body[
                STAFF_COMPENSATION_FIELDS
                  .NOTES
              ]
                ?.toString()
                .trim() || ""
            : "",
          lastUpdatedBy: actor._id,
          lastUpdatedAt: new Date(),
        });

      debug(
        STAFF_COMPENSATION_LOG.UPSERT_SUCCESS,
        {
          actorId: actor._id,
          staffProfileId:
            targetProfile._id,
          compensationId:
            compensation._id,
          created: true,
        },
      );

      return res.status(201).json({
        message:
          STAFF_COMPENSATION_COPY.COMPENSATION_UPDATED,
        compensation,
      });
    }

    const updates = {};
    const nextCadence =
      hasCadence ?
        salaryCadence
      : existing.salaryCadence;
    const nextIsProfitShare =
      nextCadence ===
      "profit_share";
    if (
      nextIsProfitShare &&
      !hasProfitSharePercentage &&
      !Number.isFinite(
        Number(
          existing.profitSharePercentage,
        ),
      )
    ) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_PROFIT_SHARE_REQUIRED,
      });
    }
    if (
      !nextIsProfitShare &&
      hasCadence &&
      existing.salaryCadence ===
        "profit_share" &&
      !hasAmount &&
      !Number.isFinite(
        Number(
          existing.salaryAmountKobo,
        ),
      )
    ) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_AMOUNT_REQUIRED,
      });
    }

    if (hasAmount) {
      updates.salaryAmountKobo =
        Math.floor(salaryAmount || 0);
    }
    if (hasCadence) {
      updates.salaryCadence =
        salaryCadence;
    }
    if (nextIsProfitShare) {
      updates.salaryAmountKobo = null;
    }
    if (hasProfitSharePercentage) {
      updates.profitSharePercentage =
        Number(
          profitSharePercentage,
        );
    }
    if (
      hasCadence &&
      !nextIsProfitShare
    ) {
      updates.profitSharePercentage =
        null;
    }
    if (hasPayDay) {
      updates.payDay =
        body[
          STAFF_COMPENSATION_FIELDS
            .PAY_DAY
        ]
          ?.toString()
          .trim() || "";
    }
    if (hasIncludesHousing) {
      updates.includesHousing =
        body[
          STAFF_COMPENSATION_FIELDS
            .INCLUDES_HOUSING
        ] === true;
    }
    if (hasIncludesFeeding) {
      updates.includesFeeding =
        body[
          STAFF_COMPENSATION_FIELDS
            .INCLUDES_FEEDING
        ] === true;
    }
    if (hasPayoutTrigger) {
      updates.payoutTrigger =
        payoutTrigger;
    }
    if (
      hasCadence &&
      !hasPayoutTrigger
    ) {
      updates.payoutTrigger =
        nextIsProfitShare ?
          "sale"
        : "attendance";
    }
    if (hasNotes) {
      updates.notes =
        body[
          STAFF_COMPENSATION_FIELDS
            .NOTES
        ]
          ?.toString()
          .trim() || "";
    }

    if (
      Object.keys(updates).length === 0
    ) {
      return res.status(400).json({
        error:
          STAFF_COMPENSATION_COPY.COMPENSATION_UPDATE_REQUIRED,
      });
    }

    updates.lastUpdatedBy = actor._id;
    updates.lastUpdatedAt = new Date();

    existing.set(updates);
    await existing.save();

    debug(
      STAFF_COMPENSATION_LOG.UPSERT_SUCCESS,
      {
        actorId: actor._id,
        staffProfileId:
          targetProfile._id,
        compensationId: existing._id,
        created: false,
      },
    );

    return res.status(200).json({
      message:
        STAFF_COMPENSATION_COPY.COMPENSATION_UPDATED,
      compensation: existing,
    });
  } catch (err) {
    debug(
      STAFF_COMPENSATION_LOG.UPSERT_ERROR,
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/staff/attendance/clock-in
 * Staff + managers: record clock-in.
 */
async function clockInStaff(req, res) {
  debug(
    "BUSINESS CONTROLLER: clockInStaff - entry",
    {
      actorId: req.user?.sub,
      staffProfileId:
        req.body?.staffProfileId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    const canManage =
      canManageAttendance({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      });

    // WHY: Managers can clock in on behalf of staff.
    const targetStaffProfileId =
      canManage ?
        req.body?.staffProfileId
          ?.toString()
          .trim()
      : staffProfile?._id?.toString();

    if (!targetStaffProfileId) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_PROFILE_ID_REQUIRED,
      });
    }

    const targetProfile =
      await BusinessStaffProfile.findOne(
        {
          _id: targetStaffProfileId,
          businessId,
        },
      );
    if (!targetProfile) {
      return res.status(404).json({
        error:
          STAFF_COPY.STAFF_PROFILE_NOT_FOUND,
      });
    }

    // WHY: Estate-scoped staff may only clock in within their estate.
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      targetProfile.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_FORBIDDEN,
      });
    }

    const existingOpen =
      await StaffAttendance.findOne({
        staffProfileId:
          targetProfile._id,
        clockOutAt: null,
      });

    if (existingOpen) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_CLOCK_IN_OPEN,
      });
    }

    const attendance =
      await StaffAttendance.create({
        staffProfileId:
          targetProfile._id,
        clockInAt: new Date(),
        clockInBy: actor._id,
      });

    debug(
      "BUSINESS CONTROLLER: clockInStaff - success",
      {
        actorId: actor._id,
        attendanceId: attendance._id,
        staffProfileId:
          targetProfile._id,
      },
    );

    return res.status(201).json({
      message:
        STAFF_COPY.STAFF_CLOCK_IN_OK,
      attendance,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: clockInStaff - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/staff/attendance/clock-out
 * Staff + managers: record clock-out.
 */
async function clockOutStaff(req, res) {
  debug(
    "BUSINESS CONTROLLER: clockOutStaff - entry",
    {
      actorId: req.user?.sub,
      staffProfileId:
        req.body?.staffProfileId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    const canManage =
      canManageAttendance({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      });

    // WHY: Managers can clock out on behalf of staff.
    const targetStaffProfileId =
      canManage ?
        req.body?.staffProfileId
          ?.toString()
          .trim()
      : staffProfile?._id?.toString();

    if (!targetStaffProfileId) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_PROFILE_ID_REQUIRED,
      });
    }

    const targetProfile =
      await BusinessStaffProfile.findOne(
        {
          _id: targetStaffProfileId,
          businessId,
        },
      );
    if (!targetProfile) {
      return res.status(404).json({
        error:
          STAFF_COPY.STAFF_PROFILE_NOT_FOUND,
      });
    }

    // WHY: Estate-scoped staff may only clock out within their estate.
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      targetProfile.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_FORBIDDEN,
      });
    }

    const openAttendance =
      await StaffAttendance.findOne({
        staffProfileId:
          targetProfile._id,
        clockOutAt: null,
      });

    if (!openAttendance) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_CLOCK_OUT_MISSING,
      });
    }

    const clockOutAt = new Date();
    const durationMinutes = Math.max(
      0,
      Math.floor(
        (clockOutAt -
          openAttendance.clockInAt) /
          MS_PER_MINUTE,
      ),
    );

    openAttendance.clockOutAt =
      clockOutAt;
    openAttendance.clockOutBy =
      actor._id;
    openAttendance.durationMinutes =
      durationMinutes;
    await openAttendance.save();

    debug(
      "BUSINESS CONTROLLER: clockOutStaff - success",
      {
        actorId: actor._id,
        attendanceId:
          openAttendance._id,
        staffProfileId:
          targetProfile._id,
        durationMinutes,
      },
    );

    return res.status(200).json({
      message:
        STAFF_COPY.STAFF_CLOCK_OUT_OK,
      attendance: openAttendance,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: clockOutStaff - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/staff/attendance
 * Staff + managers: list attendance records.
 */
async function listStaffAttendance(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listStaffAttendance - entry",
    {
      actorId: req.user?.sub,
      staffProfileId:
        req.query?.staffProfileId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    const requestedProfileId =
      req.query?.staffProfileId
        ?.toString()
        .trim() || null;

    const canView = canViewAttendance({
      actorRole: actor.role,
      staffRole:
        staffProfile?.staffRole,
    });

    let staffProfileIds = [];

    if (requestedProfileId) {
      const targetProfile =
        await BusinessStaffProfile.findOne(
          {
            _id: requestedProfileId,
            businessId,
          },
        );
      if (!targetProfile) {
        return res.status(404).json({
          error:
            STAFF_COPY.STAFF_PROFILE_NOT_FOUND,
        });
      }

      if (
        actor.role === "staff" &&
        actor.estateAssetId &&
        targetProfile.estateAssetId?.toString() !==
          actor.estateAssetId.toString()
      ) {
        return res.status(403).json({
          error:
            STAFF_COPY.STAFF_FORBIDDEN,
        });
      }

      if (
        !canView &&
        staffProfile?._id?.toString() !==
          requestedProfileId
      ) {
        return res.status(403).json({
          error:
            STAFF_COPY.STAFF_FORBIDDEN,
        });
      }

      staffProfileIds = [
        targetProfile._id,
      ];
    } else if (canView) {
      // WHY: Managers can view attendance for all staff in scope.
      const filter = {
        businessId,
      };
      if (
        actor.role === "staff" &&
        actor.estateAssetId
      ) {
        filter.estateAssetId =
          actor.estateAssetId;
      }

      const profiles =
        await BusinessStaffProfile.find(
          filter,
        ).select("_id");
      staffProfileIds = profiles.map(
        (profile) => profile._id,
      );
    } else if (staffProfile?._id) {
      staffProfileIds = [
        staffProfile._id,
      ];
    } else {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_FORBIDDEN,
      });
    }

    const attendance =
      await StaffAttendance.find({
        staffProfileId: {
          $in: staffProfileIds,
        },
      })
        .sort({ clockInAt: -1 })
        .lean();

    debug(
      "BUSINESS CONTROLLER: listStaffAttendance - success",
      {
        actorId: actor._id,
        count: attendance.length,
      },
    );

    return res.status(200).json({
      message:
        STAFF_COPY.STAFF_ATTENDANCE_OK,
      attendance,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listStaffAttendance - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/production/schedule-policy?estateAssetId=<id>
 * Owner + estate manager: resolve effective production schedule policy.
 */
async function getProductionSchedulePolicy(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getProductionSchedulePolicy - entry",
    {
      actorId: req.user?.sub,
      estateAssetId:
        req.query?.estateAssetId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_FORBIDDEN,
      });
    }

    const estateAssetIdRaw = (
      req.query?.estateAssetId ||
      ""
    )
      .toString()
      .trim();
    if (
      estateAssetIdRaw &&
      !mongoose.Types.ObjectId.isValid(
        estateAssetIdRaw,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_ESTATE_INVALID,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      estateAssetIdRaw &&
      actor.estateAssetId.toString() !==
        estateAssetIdRaw
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_FORBIDDEN,
      });
    }

    const {
      effectivePolicy,
      businessPolicy,
      estatePolicy,
      estateAsset,
    } =
      await resolveEffectiveSchedulePolicy({
        businessId,
        estateAssetId:
          estateAssetIdRaw || null,
      });

    debug(
      "BUSINESS CONTROLLER: getProductionSchedulePolicy - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        estateAssetId:
          estateAsset?._id?.toString() ||
          null,
        workWeekDays:
          effectivePolicy.workWeekDays,
        blocksLabel:
          formatWorkBlocksLabel(
            effectivePolicy.blocks,
          ),
        minSlotMinutes:
          effectivePolicy.minSlotMinutes,
        timezone:
          effectivePolicy.timezone,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.SCHEDULE_POLICY_LOADED,
      policy: effectivePolicy,
      sources: {
        businessDefault:
          businessPolicy,
        estateOverride:
          estatePolicy,
      },
      estateAssetId:
        estateAsset?._id || null,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getProductionSchedulePolicy - error",
      {
        actorId: req.user?.sub,
        estateAssetId:
          req.query?.estateAssetId,
        reason: err.message,
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * PUT /business/production/schedule-policy?estateAssetId=<id>
 * Owner + estate manager: update business default or estate override schedule policy.
 */
async function updateProductionSchedulePolicy(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateProductionSchedulePolicy - entry",
    {
      actorId: req.user?.sub,
      estateAssetId:
        req.query?.estateAssetId,
      hasPolicyPayload:
        Boolean(req.body),
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_FORBIDDEN,
      });
    }

    const estateAssetIdRaw = (
      req.query?.estateAssetId ||
      ""
    )
      .toString()
      .trim();
    if (
      estateAssetIdRaw &&
      !mongoose.Types.ObjectId.isValid(
        estateAssetIdRaw,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_ESTATE_INVALID,
      });
    }
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      estateAssetIdRaw &&
      actor.estateAssetId.toString() !==
        estateAssetIdRaw
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_FORBIDDEN,
      });
    }

    const {
      effectivePolicy:
        currentEffectivePolicy,
    } =
      await resolveEffectiveSchedulePolicy({
        businessId,
        estateAssetId:
          estateAssetIdRaw || null,
      });
    const parsedPolicy =
      validateSchedulePolicyUpdateInput(
        req.body,
        currentEffectivePolicy,
      );
    if (!parsedPolicy.ok) {
      return res.status(400).json({
        error:
          parsedPolicy.error ||
          PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
        details:
          parsedPolicy.details || {},
      });
    }

    const nextPolicy =
      parsedPolicy.policy;
    let beforePolicy = null;
    let updatedPolicy = null;
    let target = "business_default";

    if (estateAssetIdRaw) {
      const estateAsset =
        await BusinessAsset.findOne({
          _id: estateAssetIdRaw,
          businessId,
        }).select(
          "assetType productionSchedulePolicy",
        );
      if (!estateAsset) {
        return res.status(404).json({
          error:
            PRODUCTION_COPY.SCHEDULE_POLICY_ESTATE_NOT_FOUND,
        });
      }
      if (estateAsset.assetType !== "estate") {
        return res.status(400).json({
          error:
            "Estate asset is required for schedule policy",
        });
      }

      beforePolicy =
        normalizeSchedulePolicyInput(
          estateAsset.productionSchedulePolicy,
          currentEffectivePolicy,
        );
      estateAsset.productionSchedulePolicy =
        nextPolicy;
      await estateAsset.save();
      updatedPolicy =
        normalizeSchedulePolicyInput(
          estateAsset.productionSchedulePolicy,
          currentEffectivePolicy,
        );
      target = "estate_override";
    } else {
      const businessOwner =
        await User.findById(
          businessId,
        ).select(
          "productionSchedulePolicy",
        );
      if (!businessOwner) {
        throw new Error(
          "Business owner record not found",
        );
      }
      beforePolicy =
        normalizeSchedulePolicyInput(
          businessOwner.productionSchedulePolicy,
          currentEffectivePolicy,
        );
      businessOwner.productionSchedulePolicy =
        nextPolicy;
      await businessOwner.save();
      updatedPolicy =
        normalizeSchedulePolicyInput(
          businessOwner.productionSchedulePolicy,
          currentEffectivePolicy,
        );
    }

    debug(
      "BUSINESS CONTROLLER: updateProductionSchedulePolicy - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        estateAssetId:
          estateAssetIdRaw || null,
        target,
        before: beforePolicy,
        after: updatedPolicy,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.SCHEDULE_POLICY_UPDATED,
      policy: updatedPolicy,
      target,
      estateAssetId:
        estateAssetIdRaw || null,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateProductionSchedulePolicy - error",
      {
        actorId: req.user?.sub,
        estateAssetId:
          req.query?.estateAssetId,
        reason: err.message,
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /business/staff/capacity?estateAssetId=<id>
 * Owner + staff: summarize role capacity for AI planning and staffing warnings.
 */
async function getStaffCapacity(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getStaffCapacity - entry",
    {
      actorId: req.user?.sub,
      estateAssetId:
        req.query?.estateAssetId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const estateAssetIdRaw = (
      req.query?.estateAssetId ||
      ""
    )
      .toString()
      .trim();
    if (
      estateAssetIdRaw &&
      !mongoose.Types.ObjectId.isValid(
        estateAssetIdRaw,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_ESTATE_INVALID,
      });
    }
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      estateAssetIdRaw &&
      actor.estateAssetId.toString() !==
        estateAssetIdRaw
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    if (estateAssetIdRaw) {
      await resolveEstateAsset({
        estateAssetId:
          estateAssetIdRaw,
        businessId,
      });
    }

    const capacity =
      await buildStaffCapacitySummary({
        businessId,
        estateAssetId:
          estateAssetIdRaw || null,
      });

    debug(
      "BUSINESS CONTROLLER: getStaffCapacity - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        estateAssetId:
          capacity.estateAssetId,
        roles: capacity.roles,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.STAFF_CAPACITY_LOADED,
      ...capacity,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getStaffCapacity - error",
      {
        actorId: req.user?.sub,
        estateAssetId:
          req.query?.estateAssetId,
        reason: err.message,
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/plans/assistant-turn
 * Owner + staff: chat-first assistant turn that guides draft generation and product selection.
 */
async function productionPlanAssistantTurnHandler(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: productionPlanAssistantTurn - entry",
    {
      actorId: req.user?.sub,
      estateAssetId:
        req.body?.estateAssetId,
      productId:
        req.body?.productId,
      hasUserInput: Boolean(
        req.body?.userInput ||
          req.body?.aiBrief ||
          req.body?.prompt,
      ),
      hasStartDate: Boolean(
        req.body?.startDate,
      ),
      hasEndDate: Boolean(
        req.body?.endDate,
      ),
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const userInput = (
      req.body?.userInput ||
      req.body?.aiBrief ||
      req.body?.prompt ||
      ""
    )
      .toString()
      .trim();
    const cropSubtype =
      req.body?.cropSubtype
        ?.toString()
        .trim() || "";
    const requestedBusinessType =
      req.body?.businessType
        ?.toString()
        .trim() || "";
    const domainContextInput =
      parseDomainContextInput(
        req.body?.domainContext ||
          requestedBusinessType,
      );
    const domainContext =
      domainContextInput.value;

    const estates =
      await BusinessAsset.find({
        businessId,
        assetType: "estate",
      })
        .select({
          _id: 1,
          name: 1,
        })
        .sort({ createdAt: -1 })
        .lean();
    const estatesById = new Map(
      estates.map((estate) => [
        estate._id.toString(),
        estate,
      ]),
    );
    const estateAssetIdRaw = (
      req.body?.estateAssetId || ""
    )
      .toString()
      .trim();
    const defaultEstateId =
      actor.role === "staff" &&
      actor.estateAssetId ?
        actor.estateAssetId.toString()
      : estates.length === 1 ?
        estates[0]._id.toString()
      : "";
    const resolvedEstateAssetId =
      estateAssetIdRaw ||
      defaultEstateId;

    if (!resolvedEstateAssetId) {
      const estateSuggestions = estates.map(
        (estate) =>
          `Use estate: ${estate.name}`,
      );
      const turn =
        buildAssistantTurnSuggestions({
          message:
            PRODUCTION_COPY.ASSISTANT_CONTEXT_REQUIRED,
          suggestions: [
            ...estateSuggestions,
            "Select an estate to load schedule policy and staffing context.",
            "Then tell me crop + timeline and I will draft the full plan.",
          ],
        });
      return res.status(200).json({
        message:
          PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
        turn,
      });
    }

    if (
      !mongoose.Types.ObjectId.isValid(
        resolvedEstateAssetId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.SCHEDULE_POLICY_ESTATE_INVALID,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      actor.estateAssetId.toString() !==
        resolvedEstateAssetId
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const estateAsset =
      await resolveEstateAsset({
        estateAssetId:
          resolvedEstateAssetId,
        businessId,
      });

    const productCatalog =
      await Product.find({
        businessId,
        deletedAt: null,
      })
        .select({
          _id: 1,
          name: 1,
          description: 1,
        })
        .sort({ updatedAt: -1 })
        .limit(60)
        .lean();
    const productIdRaw = (
      req.body?.productId || ""
    )
      .toString()
      .trim();
    let selectedProduct = null;
    if (productIdRaw) {
      if (
        !mongoose.Types.ObjectId.isValid(
          productIdRaw,
        )
      ) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.PRODUCT_REQUIRED,
        });
      }
      selectedProduct =
        await businessProductService.getProductById(
          {
            businessId,
            id: productIdRaw,
          },
        );
      if (!selectedProduct) {
        return res.status(404).json({
          error:
            PRODUCTION_COPY.PRODUCT_NOT_FOUND,
        });
      }
    } else {
      selectedProduct =
        findAssistantProductMatch({
          userInput,
          products: productCatalog,
        });
    }

    if (!selectedProduct) {
      if (userInput) {
        const draftProduct =
          buildAssistantDraftProductFromInput(
            userInput,
          );
        const turn =
          buildAssistantTurnDraftProduct({
            message:
              "I could not match that to an existing product, so I drafted one for you.",
            draftProduct,
            confirmationQuestion:
              "Create this product now, then I will generate the full production plan.",
          });
        return res.status(200).json({
          message:
            PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
          turn,
        });
      }

      const productSuggestions =
        productCatalog
          .slice(0, 6)
          .map(
            (product) =>
              `Use product: ${product.name}`,
          );
      const turn =
        buildAssistantTurnSuggestions({
          message:
            PRODUCTION_COPY.ASSISTANT_PRODUCT_REQUIRED,
          suggestions: [
            ...productSuggestions,
            "Or describe a new crop and I will draft the product details.",
            "Example brief: beans for 3 plots from March to June.",
          ],
        });
      return res.status(200).json({
        message:
          PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
        turn,
      });
    }

    const startDateRaw = (
      req.body?.startDate || ""
    )
      .toString()
      .trim();
    const endDateRaw = (
      req.body?.endDate || ""
    )
      .toString()
      .trim();
    const startDate =
      startDateRaw ?
        parseDateInput(startDateRaw)
      : null;
    const endDate =
      endDateRaw ?
        parseDateInput(endDateRaw)
      : null;
    if (
      startDateRaw &&
      !startDate
    ) {
      const turn =
        buildAssistantTurnClarify({
          message:
            "Start date is invalid.",
          question:
            "Provide startDate in YYYY-MM-DD format.",
          choices: [],
          requiredField: "startDate",
          contextSummary:
            "I need a valid start date to generate a full timeline.",
        });
      return res.status(200).json({
        message:
          PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
        turn,
      });
    }
    if (
      endDateRaw &&
      !endDate
    ) {
      const turn =
        buildAssistantTurnClarify({
          message:
            "End date is invalid.",
          question:
            "Provide endDate in YYYY-MM-DD format.",
          choices: [],
          requiredField: "endDate",
          contextSummary:
            "I need a valid end date to complete the timeline.",
        });
      return res.status(200).json({
        message:
          PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
        turn,
      });
    }
    if (
      startDate &&
      endDate &&
      endDate <= startDate
    ) {
      const turn =
        buildAssistantTurnClarify({
          message:
            PRODUCTION_COPY.DATE_RANGE_INVALID,
          question:
            "End date must be after start date. What end date do you want?",
          choices: [],
          requiredField: "endDate",
          contextSummary:
            "Please provide an end date later than the selected start date.",
        });
      return res.status(200).json({
        message:
          PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
        turn,
      });
    }

    // WHY: Reuse the existing draft endpoint logic so calendar scheduling stays consistent.
    const aiDraftInvocation =
      await invokeControllerHandlerJson({
        handler:
          generateProductionPlanDraftHandler,
        request: {
          ...req,
          // WHY: Assistant invokes draft handler with a synthetic request object,
          // so we must provide safe header/request metadata defaults.
          headers:
            req.headers || {},
          originalUrl:
            req.originalUrl ||
            "/business/production/plans/assistant-turn",
          id:
            req.id ||
            `assistant_${Date.now()}`,
          body: {
            estateAssetId:
              resolvedEstateAssetId,
            productId:
              selectedProduct._id
                .toString(),
            startDate:
              startDate ?
                startDate
                  .toISOString()
                  .slice(0, 10)
              : "",
            endDate:
              endDate ?
                endDate
                  .toISOString()
                  .slice(0, 10)
              : "",
            aiBrief:
              userInput ||
              `Create a full production plan for ${selectedProduct.name} across the selected range.`,
            domainContext,
            cropSubtype,
            businessType:
              requestedBusinessType,
          },
          query: {},
        },
      });

    if (
      aiDraftInvocation.statusCode >= 400
    ) {
      const draftError =
        aiDraftInvocation.payload &&
        typeof aiDraftInvocation.payload ===
          "object" ?
          aiDraftInvocation.payload
        : {};
      const errorCode = (
        draftError.error_code || ""
      )
        .toString()
        .trim();
      const shouldClarifyDate =
        aiDraftInvocation.statusCode ===
          422 &&
        errorCode.includes("DATE");
      if (shouldClarifyDate) {
        const turn =
          buildAssistantTurnClarify({
            message:
              draftError.error
                ?.toString()
                .trim() ||
              "I need date guidance before creating this plan.",
            question:
              "What start and end dates should I use (YYYY-MM-DD)?",
            choices: [],
            requiredField:
              startDate ? "endDate" : "startDate",
            contextSummary:
              draftError.resolution_hint
                ?.toString()
                .trim() ||
              "Provide dates so I can draft the full timeline and weeks.",
          });
        return res.status(200).json({
          message:
            PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
          turn,
        });
      }
      return res
        .status(
          aiDraftInvocation.statusCode,
        )
        .json(draftError);
    }

    const aiDraftResponse =
      aiDraftInvocation.payload &&
      typeof aiDraftInvocation.payload ===
        "object" ?
        aiDraftInvocation.payload
      : {};
    const planPayload =
      buildAssistantPlanDraftPayload({
        aiDraftResponse,
        selectedProduct,
      });
    const turn = {
      action:
        PRODUCTION_ASSISTANT_ACTION_PLAN_DRAFT,
      message:
        aiDraftResponse.message
          ?.toString()
          .trim() ||
        PRODUCTION_COPY.PLAN_DRAFT_OK,
      payload: planPayload,
    };

    debug(
      "BUSINESS CONTROLLER: productionPlanAssistantTurn - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        estateAssetId:
          estateAsset._id.toString(),
        productId:
          selectedProduct._id.toString(),
        productName:
          selectedProduct.name,
        action: turn.action,
        planningDays:
          planPayload.days,
        planningWeeks:
          planPayload.weeks,
        phaseCount:
          planPayload.phases.length,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
      turn,
      context: {
        estateAssetId:
          estateAsset._id,
        estateName:
          estateAsset.name || "",
        productId:
          selectedProduct._id,
        productName:
          selectedProduct.name || "",
        domainContext,
      },
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: productionPlanAssistantTurn - error",
      {
        actorId: req.user?.sub,
        reason: err.message,
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/plans/ai-draft
 * Owner + estate manager: generate an AI draft for a production plan.
 */
async function generateProductionPlanDraftHandler(
  req,
  res,
) {
  // WHY: Keep validation failure metadata consistent for frontend recovery.
  const validationRetryReason =
    "client_validation_failed";
  debug(
    "BUSINESS CONTROLLER: generateProductionPlanDraft - entry",
    {
      actorId: req.user?.sub,
      hasProduct: Boolean(
        req.body?.productId,
      ),
      hasEstate: Boolean(
        req.body?.estateAssetId,
      ),
      hasPrompt: Boolean(
        req.body?.aiBrief ||
          req.body?.prompt,
      ),
      hasDomainContext: Boolean(
        req.body?.domainContext,
      ),
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const estateAssetId =
      req.body?.estateAssetId
        ?.toString()
        .trim() || "";
    const productId =
      req.body?.productId
        ?.toString()
        .trim() || "";
    const startDateInput =
      req.body?.startDate
        ?.toString()
        .trim() || "";
    const endDateInput =
      req.body?.endDate
        ?.toString()
        .trim() || "";
    const hasStartDateInput =
      startDateInput.length > 0;
    const hasEndDateInput =
      endDateInput.length > 0;
    const startDate = parseDateInput(
      startDateInput,
    );
    const endDate = parseDateInput(
      endDateInput,
    );
    const useReasoning = Boolean(
      req.body?.useReasoning,
    );
    const prompt =
      req.body?.aiBrief
        ?.toString()
        .trim() ||
      req.body?.prompt
        ?.toString()
        .trim() || "";
    const cropSubtype =
      req.body?.cropSubtype
        ?.toString()
        .trim() || "";
    const requestedBusinessType =
      req.body?.businessType
        ?.toString()
        .trim() || "";
    const domainContextInput =
      parseDomainContextInput(
        req.body?.domainContext ||
          requestedBusinessType,
      );
    const domainContext =
      domainContextInput.value;

    if (!estateAssetId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.ESTATE_REQUIRED,
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          "PRODUCTION_AI_ESTATE_REQUIRED",
        resolution_hint:
          "Select an estate before generating an AI draft.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
      });
    }
    if (!productId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PRODUCT_REQUIRED,
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          "PRODUCTION_AI_PRODUCT_REQUIRED",
        resolution_hint:
          "Select a product before generating an AI draft.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
      });
    }
    if (
      hasStartDateInput &&
      !startDate
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DATES_REQUIRED,
        classification:
          "INVALID_INPUT",
        error_code:
          "PRODUCTION_AI_START_DATE_INVALID",
        resolution_hint:
          "Start date should be YYYY-MM-DD when provided.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
      });
    }
    if (
      hasEndDateInput &&
      !endDate
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DATES_REQUIRED,
        classification:
          "INVALID_INPUT",
        error_code:
          "PRODUCTION_AI_END_DATE_INVALID",
        resolution_hint:
          "End date should be YYYY-MM-DD when provided.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
      });
    }
    if (
      startDate &&
      endDate &&
      endDate <= startDate
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DATE_RANGE_INVALID,
        classification:
          "INVALID_INPUT",
        error_code:
          "PRODUCTION_AI_DATE_RANGE_INVALID",
        resolution_hint:
          "Set an end date that is after the start date.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
      });
    }
    // WHY: Keep AI draft dates aligned with strict YYYY-MM-DD schema.
    const startDateValue = startDate
      ? startDate
          .toISOString()
          .slice(0, 10)
      : null;
    const endDateValue = endDate
      ? endDate
          .toISOString()
          .slice(0, 10)
      : null;

    // WHY: Estate-scoped managers can only draft plans for their estate.
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      actor.estateAssetId.toString() !==
        estateAssetId
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const estateAsset =
      await resolveEstateAsset({
        estateAssetId,
        businessId,
      });

    const product =
      await businessProductService.getProductById(
        {
          businessId,
          id: productId,
        },
      );
    if (!product) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PRODUCT_NOT_FOUND,
      });
    }

    // WHY: Include business-wide staff plus estate-specific staff for drafting.
    const staffFilter = {
      businessId,
      status: STAFF_STATUS_ACTIVE,
      $or: [
        { estateAssetId },
        { estateAssetId: null },
      ],
    };
    const staffProfiles =
      await BusinessStaffProfile.find(
        staffFilter,
      )
        .populate(
          "userId",
          "name email",
        )
        .lean();

    const {
      effectivePolicy:
        effectiveSchedulePolicy,
    } =
      await resolveEffectiveSchedulePolicy({
        businessId,
        estateAssetId,
      });
    const capacitySummary =
      await buildStaffCapacitySummary({
        businessId,
        estateAssetId,
      });
    const requestedPlanningSummary =
      startDate &&
        endDate ?
        buildPlanningRangeSummary({
          startDate,
          endDate,
          productId,
          cropSubtype,
        })
      : null;
    const planningRangePrompt =
      startDateValue && endDateValue ?
        `Planning range: ${requestedPlanningSummary?.startDate} to ${requestedPlanningSummary?.endDate} (${requestedPlanningSummary?.days} days, ${requestedPlanningSummary?.weeks} weeks, ~${requestedPlanningSummary?.monthApprox} months).`
      : startDateValue && !endDateValue ?
        `Planning start date is fixed at ${startDateValue}. Infer endDate/proposedEndDate and schedule tasks across the full resulting range.`
      : !startDateValue && endDateValue ?
        `Planning end date is fixed at ${endDateValue}. Infer startDate/proposedStartDate and schedule tasks across the full resulting range.`
      : "Infer both startDate and endDate from crop lifecycle + brief, then schedule tasks across the full inferred range.";
    const schedulerPrompt = [
      "Generate tasks that span the FULL planning range.",
      planningRangePrompt,
      "Do not assign staff names.",
      "Each task must include roleRequired, requiredHeadcount, weight, and instructions.",
      "Allow parallel role tracks where realistic.",
      buildAiSchedulePolicyPrompt(
        effectiveSchedulePolicy,
      ),
      buildAiCapacityPrompt(
        capacitySummary,
      ),
      cropSubtype ?
        `Crop subtype hint: ${cropSubtype}.`
      : "",
      requestedBusinessType ?
        `Business type hint: ${requestedBusinessType}.`
      : "",
    ]
      .filter(Boolean)
      .join(" ");
    const assistantPrompt = [
      prompt,
      schedulerPrompt,
    ]
      .filter(Boolean)
      .join("\n\n");

    const aiResult =
      await generateProductionPlanDraft(
        {
          productName:
            product?.name || "",
          estateName: estateAsset?.name,
          domainContext,
          estateAssetId,
          productId,
          startDate: startDateValue,
          endDate: endDateValue,
          staffProfiles,
          assistantPrompt,
          useReasoning,
          context: {
            route: req.originalUrl,
            requestId: req.id,
            userRole: actor.role,
            businessId,
            hasPrompt: Boolean(
              assistantPrompt,
            ),
            domainContext,
            schedulePolicy:
              effectiveSchedulePolicy,
            capacity: capacitySummary,
            country:
              req.headers?.[
                COUNTRY_HEADER_KEY
              ] || DEFAULT_COUNTRY,
          },
        },
      );
    const isPartialDraft =
      aiResult?.status ===
      "ai_draft_partial";
    const responseMessage =
      isPartialDraft
        ? aiResult?.message ||
          PRODUCTION_COPY.PLAN_DRAFT_OK
        : PRODUCTION_COPY.PLAN_DRAFT_OK;
    const normalizedWarnings = [
      ...(aiResult?.warnings || []),
    ];
    const aiDraftPayload =
      aiResult?.draft &&
      typeof aiResult.draft ===
        "object" ?
        aiResult.draft
      : {};
    const resolvedStartDateInput =
      startDateValue ||
      aiDraftPayload?.startDate ||
      aiDraftPayload?.proposedStartDate ||
      "";
    const resolvedEndDateInput =
      endDateValue ||
      aiDraftPayload?.endDate ||
      aiDraftPayload?.proposedEndDate ||
      "";
    const resolvedDraftStartDate =
      parseDateInput(
        resolvedStartDateInput,
      );
    const resolvedDraftEndDate =
      parseDateInput(
        resolvedEndDateInput,
      );
    if (
      !resolvedDraftStartDate ||
      !resolvedDraftEndDate
    ) {
      return res.status(422).json({
        error:
          PRODUCTION_COPY.DATES_REQUIRED,
        classification:
          "PROVIDER_REJECTED_FORMAT",
        error_code:
          "PRODUCTION_AI_DATES_NOT_INFERRED",
        resolution_hint:
          "AI could not infer start/end dates. Provide dates or refine your brief and retry.",
        details: {
          missing: [
            !resolvedDraftStartDate ?
              "startDate|proposedStartDate"
            : null,
            !resolvedDraftEndDate ?
              "endDate|proposedEndDate"
            : null,
          ].filter(Boolean),
          invalid: [],
        },
        retry_allowed: true,
        retry_reason:
          "provider_output_invalid",
      });
    }
    if (
      resolvedDraftEndDate <=
      resolvedDraftStartDate
    ) {
      return res.status(422).json({
        error:
          PRODUCTION_COPY.DATE_RANGE_INVALID,
        classification:
          "PROVIDER_REJECTED_FORMAT",
        error_code:
          "PRODUCTION_AI_DATE_RANGE_INVALID",
        resolution_hint:
          "AI returned an invalid range; retry with a clearer brief or set dates manually.",
        details: {
          missing: [],
          invalid: [
            "endDate<=startDate",
          ],
        },
        retry_allowed: true,
        retry_reason:
          "provider_output_invalid",
      });
    }
    const planningSummary =
      buildPlanningRangeSummary({
        startDate:
          resolvedDraftStartDate,
        endDate:
          resolvedDraftEndDate,
        productId,
        cropSubtype,
      });
    const resolvedStartDateValue =
      resolvedDraftStartDate
        .toISOString()
        .slice(0, 10);
    const resolvedEndDateValue =
      resolvedDraftEndDate
        .toISOString()
        .slice(0, 10);
    const draftPhases =
      Array.isArray(
        aiDraftPayload?.phases,
      ) ?
        aiDraftPayload.phases
      : [];
    const normalizedDraftPhases =
      draftPhases.map(
        (phase, phaseIndex) => {
          const phaseTasks =
            Array.isArray(
              phase?.tasks,
            ) ?
              phase.tasks
            : [];
          return {
            ...phase,
            name:
              phase?.name
                ?.toString()
                .trim() ||
              `${DEFAULT_PHASE_NAME_PREFIX} ${phaseIndex + 1}`,
            order:
              Number.isFinite(
                Number(
                  phase?.order,
                ),
              ) ?
                Math.max(
                  1,
                  Math.floor(
                    Number(
                      phase.order,
                    ),
                  ),
                )
              : phaseIndex + 1,
            estimatedDays:
              Number.isFinite(
                Number(
                  phase?.estimatedDays,
                ),
              ) ?
                Math.max(
                  1,
                  Math.floor(
                    Number(
                      phase.estimatedDays,
                    ),
                  ),
                )
              : 1,
            tasks:
              phaseTasks.map(
                (task) =>
                  normalizeDraftTaskShape(
                    task,
                  ),
              ),
          };
        },
      );
    const scheduledPhases =
      buildPhaseSchedule({
        startDate:
          resolvedDraftStartDate,
        endDate:
          resolvedDraftEndDate,
        phases:
          normalizedDraftPhases,
      });
    const scheduledTaskRows = [];
    const draftPhasesWithTimes =
      scheduledPhases.map(
        (phase, phaseIndex) => {
          const phaseTasks =
            normalizedDraftPhases[
              phaseIndex
            ]?.tasks || [];
          const scheduledTasks =
            buildTaskSchedule({
              phaseStart:
                phase.startDate,
              phaseEnd: phase.endDate,
              tasks: phaseTasks,
              schedulePolicy:
                effectiveSchedulePolicy,
              allowParallelByRole: true,
            });
          const tasksForDraft =
            scheduledTasks.map(
              (
                task,
                taskIndex,
              ) => {
                const startDateIso =
                  task?.startDate ?
                    new Date(
                      task.startDate,
                    ).toISOString()
                  : null;
                const dueDateIso =
                  task?.dueDate ?
                    new Date(
                      task.dueDate,
                    ).toISOString()
                  : null;
                const normalizedTask = {
                  ...task,
                  requiredHeadcount:
                    normalizeDraftTaskHeadcount(
                      task.requiredHeadcount,
                    ),
                  assignedStaffProfileIds:
                    resolveTaskAssignedStaffIds(
                      task,
                    ),
                  assignedStaffId:
                    resolveTaskAssignedStaffIds(
                      task,
                    )[0] || "",
                  assignedCount:
                    resolveTaskAssignedStaffIds(
                      task,
                    ).length,
                  startDate:
                    startDateIso,
                  dueDate: dueDateIso,
                };
                scheduledTaskRows.push({
                  taskId: `${phaseIndex}_${taskIndex}`,
                  title:
                    normalizedTask.title ||
                    DEFAULT_TASK_TITLE,
                  phaseName:
                    phase.name,
                  phaseOrder:
                    phase.order,
                  roleRequired:
                    normalizedTask.roleRequired,
                  requiredHeadcount:
                    normalizedTask.requiredHeadcount,
                  assignedStaffProfileIds:
                    normalizedTask.assignedStaffProfileIds,
                  assignedCount:
                    normalizedTask.assignedCount,
                  startDate:
                    normalizedTask.startDate,
                  dueDate:
                    normalizedTask.dueDate,
                  instructions:
                    normalizedTask.instructions ||
                    "",
                  weight:
                    normalizedTask.weight || 1,
                });
                return normalizedTask;
              },
            );

          return {
            ...normalizedDraftPhases[
              phaseIndex
            ],
            name: phase.name,
            order: phase.order,
            tasks: tasksForDraft,
          };
        },
      );
    const shortageWarnings =
      summarizeRoleShortages({
        tasks: scheduledTaskRows,
        capacity: capacitySummary,
      });
    normalizedWarnings.push(
      ...shortageWarnings,
    );
    if (
      cropSubtype
        .toLowerCase()
        .includes("bean") &&
      planningSummary.weeks < 12
    ) {
      normalizedWarnings.push({
        code:
          "COMPRESSED_TIMELINE",
        message:
          "Selected range is shorter than typical bean lifecycle; tasks were compressed.",
      });
    }
    if (
      domainContextInput.provided &&
      !domainContextInput.isValid
    ) {
      // WHY: Draft mode should warn on unsupported domain context instead of blocking.
      normalizedWarnings.push({
        code:
          "DOMAIN_CONTEXT_NORMALIZED",
        path: "domainContext",
        value: `${domainContextInput.raw} -> ${domainContext}`,
        message:
          "Domain context was normalized to a supported value for draft safety.",
      });
    }
    const normalizedDraft = {
      ...aiDraftPayload,
      domainContext:
        aiDraftPayload
          ?.domainContext ||
        domainContext,
      estateAssetId,
      productId,
      startDate:
        resolvedStartDateValue,
      endDate:
        resolvedEndDateValue,
      phases:
        draftPhasesWithTimes,
      summary: {
        ...(aiDraftPayload?.summary ||
          {}),
        totalTasks:
          scheduledTaskRows.length,
        totalEstimatedDays:
          planningSummary.days,
        riskNotes: Array.from(
          new Set([
            ...(
              Array.isArray(
                aiDraftPayload
                  ?.summary
                  ?.riskNotes,
              ) ?
                aiDraftPayload.summary.riskNotes
              : []
            ),
            ...shortageWarnings.map(
              (warning) =>
                warning.message,
            ),
          ]),
        ),
      },
    };

    debug(
      "BUSINESS CONTROLLER: generateProductionPlanDraft - success",
      {
        actorId: actor._id,
        phaseCount:
          aiResult?.draft?.phases
            ?.length || 0,
        warnings:
          aiResult?.warnings
            ?.length || 0,
        provider:
          aiResult?.diagnostics
            ?.provider || "unknown",
        status:
          aiResult?.status ||
          "ai_draft_success",
        issueType:
          aiResult?.issueType ||
          null,
        domainContextProvided:
          domainContextInput.provided,
        domainContextValid:
          domainContextInput.isValid,
        domainContext:
          normalizedDraft
            ?.domainContext ||
          domainContext,
        planningDays:
          planningSummary.days,
        planningWeeks:
          planningSummary.weeks,
        planningStartDate:
          resolvedStartDateValue,
        planningEndDate:
          resolvedEndDateValue,
        schedulePolicy:
          effectiveSchedulePolicy,
        capacity: capacitySummary,
        scheduledTaskCount:
          scheduledTaskRows.length,
        hasPrompt: Boolean(prompt),
      },
    );

    return res.status(200).json({
      status:
        aiResult?.status ||
        "ai_draft_success",
      ...(isPartialDraft
        ? {
            issueType:
              aiResult?.issueType ||
              "INSUFFICIENT_CONTEXT",
          }
        : {}),
      message:
        responseMessage,
      summary:
        planningSummary,
      schedulePolicy:
        effectiveSchedulePolicy,
      capacity:
        capacitySummary,
      phases:
        draftPhasesWithTimes,
      tasks:
        scheduledTaskRows,
      draft: {
        ...normalizedDraft,
      },
      warnings:
        normalizedWarnings,
      diagnostics: {
        provider:
          aiResult?.diagnostics
            ?.provider || "unknown",
        model:
          aiResult?.diagnostics
            ?.model || null,
        requestId:
          aiResult?.diagnostics
            ?.requestId ||
          req.id ||
          "unknown",
      },
    });
  } catch (err) {
    const classification =
      err.classification ||
      "UNKNOWN_PROVIDER_ERROR";
    const errorCode =
      err.errorCode ||
      "PRODUCTION_AI_DRAFT_FAILED";
    const resolutionHint =
      err.resolutionHint ||
      "Verify inputs and AI configuration before retrying.";
    const details =
      err.details &&
      typeof err.details === "object"
        ? err.details
        : {
            missing: [],
            invalid: [],
            providerMessage:
              err.providerMessage ||
              "",
          };
    const retryAllowed =
      err.retry_allowed === true;
    const retryReason =
      err.retry_reason ||
      (retryAllowed
        ? "provider_output_invalid"
        : "unexpected_error");
    const httpStatus =
      err.httpStatus === 422
        ? 422
        : err.httpStatus === 400
        ? 400
        : null;

    debug(
      "BUSINESS CONTROLLER: generateProductionPlanDraft - error",
      {
        error: err.message,
        classification:
          classification,
        error_code: errorCode,
        resolution_hint:
          resolutionHint,
        retry_allowed:
          retryAllowed,
        retry_reason:
          retryReason,
        reason:
          "production_plan_draft_failed",
      },
    );

    if (
      httpStatus === 422 ||
      classification ===
        "PROVIDER_REJECTED_FORMAT"
    ) {
      return res.status(422).json({
        error:
          err.message ||
          "AI draft did not match required schema.",
        classification:
          classification,
        error_code: errorCode,
        resolution_hint:
          resolutionHint,
        details,
        retry_allowed:
          retryAllowed,
        retry_reason:
          retryReason,
      });
    }

    return res.status(400).json({
      error:
        err.message ||
        PRODUCTION_COPY.PLAN_DRAFT_FAILED,
      classification:
        classification,
      error_code: errorCode,
      resolution_hint:
        resolutionHint,
      details,
      retry_allowed:
        retryAllowed,
      retry_reason:
        retryReason,
    });
  }
}

/**
 * POST /business/production/plans
 * Owner + estate manager: create a production plan with phases/tasks.
 */
async function createProductionPlan(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: createProductionPlan - entry",
    {
      actorId: req.user?.sub,
      hasProduct: Boolean(
        req.body?.productId,
      ),
      hasEstate: Boolean(
        req.body?.estateAssetId,
      ),
      hasDomainContext: Boolean(
        req.body?.domainContext,
      ),
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const estateAssetId =
      req.body?.estateAssetId
        ?.toString()
        .trim() || "";
    const productId =
      req.body?.productId
        ?.toString()
        .trim() || "";
    const title =
      req.body?.title
        ?.toString()
        .trim() || "";
    const notes =
      req.body?.notes
        ?.toString()
        .trim() || "";
    const aiGenerated = Boolean(
      req.body?.aiGenerated,
    );
    const domainContextInput =
      parseDomainContextInput(
        req.body?.domainContext,
      );
    const domainContext =
      domainContextInput.value;

    const startDate = parseDateInput(
      req.body?.startDate,
    );
    const endDate = parseDateInput(
      req.body?.endDate,
    );

    if (!estateAssetId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.ESTATE_REQUIRED,
      });
    }
    if (!productId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PRODUCT_REQUIRED,
      });
    }
    if (!startDate || !endDate) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DATES_REQUIRED,
      });
    }
    if (endDate <= startDate) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DATE_RANGE_INVALID,
      });
    }
    if (
      domainContextInput.provided &&
      !domainContextInput.isValid
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DOMAIN_CONTEXT_INVALID,
      });
    }

    // WHY: Estate-scoped managers can only create plans for their estate.
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      actor.estateAssetId.toString() !==
        estateAssetId
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    await resolveEstateAsset({
      estateAssetId,
      businessId,
    });
    const {
      effectivePolicy:
        effectiveSchedulePolicy,
    } =
      await resolveEffectiveSchedulePolicy({
        businessId,
        estateAssetId,
      });
    debug(
      "BUSINESS CONTROLLER: createProductionPlan - schedule policy loaded",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        estateAssetId,
        workWeekDays:
          effectiveSchedulePolicy.workWeekDays,
        blocksLabel:
          formatWorkBlocksLabel(
            effectiveSchedulePolicy.blocks,
          ),
        minSlotMinutes:
          effectiveSchedulePolicy.minSlotMinutes,
        timezone:
          effectiveSchedulePolicy.timezone,
      },
    );
    // WHY: Plan lifecycle is tied to an existing product record.
    const product =
      await businessProductService.getProductById(
        {
          businessId,
          id: productId,
        },
      );
    if (!product) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PRODUCT_NOT_FOUND,
      });
    }

    const rawPhases =
      Array.isArray(req.body?.phases) ?
        req.body.phases
      : [];

    const phaseTemplates =
      rawPhases.length > 0 ?
        rawPhases
      : DEFAULT_PRODUCTION_PHASES;

    if (phaseTemplates.length === 0) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PHASES_REQUIRED,
      });
    }

    const normalizedPhases =
      phaseTemplates.map(
        (phase, index) => ({
          name:
            (phase?.name || "")
              .toString()
              .trim() ||
            DEFAULT_PRODUCTION_PHASES[
              index
            ]?.name ||
            `${DEFAULT_PHASE_NAME_PREFIX} ${index + 1}`,
          order:
            (
              Number.isFinite(
                phase?.order,
              ) &&
              Number(phase.order) > 0
            ) ?
              Math.floor(
                Number(phase.order),
              )
            : index + 1,
          kpiTarget:
            phase?.kpiTarget || null,
          tasks:
            (
              Array.isArray(
                phase?.tasks,
              )
            ) ?
              phase.tasks
            : [],
        }),
      );

    const scheduledPhases =
      buildPhaseSchedule({
        startDate,
        endDate,
        phases: normalizedPhases,
      });

    const tasksInputByPhase =
      scheduledPhases.map(
        (phase) => phase.tasks || [],
      );

    const assignedStaffIds =
      tasksInputByPhase
        .flat()
        .flatMap((task) =>
          resolveTaskAssignedStaffIds(
            task,
          ),
        )
        .filter(Boolean);

    // WHY: Preload staff profiles for assignment validation.
    const staffProfiles =
      assignedStaffIds.length > 0 ?
        await BusinessStaffProfile.find(
          {
            _id: {
              $in: assignedStaffIds,
            },
            businessId,
          },
        ).lean()
      : [];
    const staffProfileMap = new Map(
      staffProfiles.map((profile) => [
        profile._id.toString(),
        profile,
      ]),
    );

    // WHY: Validate all task assignments before creating records.
    scheduledPhases.forEach((phase) => {
      const scheduledTasks =
        buildTaskSchedule({
          phaseStart: phase.startDate,
          phaseEnd: phase.endDate,
          tasks: phase.tasks || [],
          schedulePolicy:
            effectiveSchedulePolicy,
          allowParallelByRole: true,
        });
      scheduledTasks.forEach((task) => {
        if (!task.roleRequired) {
          throw new Error(
            PRODUCTION_COPY.STAFF_ROLE_REQUIRED,
          );
        }
        if (
          !STAFF_ROLE_VALUES.includes(
            task.roleRequired,
          )
        ) {
          throw new Error(
            PRODUCTION_COPY.STAFF_ROLE_REQUIRED,
          );
        }
        const requiredHeadcount = Math.max(
          1,
          Math.floor(
            Number(
              task.requiredHeadcount ||
                1,
            ),
          ),
        );
        if (
          !Number.isFinite(
            requiredHeadcount,
          )
        ) {
          throw new Error(
            PRODUCTION_COPY.SCHEDULE_POLICY_INVALID,
          );
        }

        const assignedIds =
          resolveTaskAssignedStaffIds(
            task,
          );
        assignedIds.forEach(
          (assignedId) => {
            const assignedProfile =
              staffProfileMap.get(
                assignedId,
              );
            if (!assignedProfile) {
              throw new Error(
                STAFF_COPY.STAFF_PROFILE_NOT_FOUND,
              );
            }
            if (
              assignedProfile.staffRole !==
              task.roleRequired
            ) {
              throw new Error(
                PRODUCTION_COPY.STAFF_ROLE_MISMATCH,
              );
            }
            if (
              assignedProfile.estateAssetId &&
              assignedProfile.estateAssetId.toString() !==
                estateAssetId
            ) {
              throw new Error(
                PRODUCTION_COPY.STAFF_ROLE_MISMATCH,
              );
            }
          },
        );

        if (
          assignedIds.length > 0 &&
          assignedIds.length <
            requiredHeadcount
        ) {
          debug(
            "BUSINESS CONTROLLER: createProductionPlan - partial task assignment",
            {
              taskTitle:
                task?.title || "",
              roleRequired:
                task?.roleRequired || "",
              requiredHeadcount,
              assignedCount:
                assignedIds.length,
            },
          );
        }
      });
    });

    const plan =
      await ProductionPlan.create({
        businessId,
        estateAssetId,
        productId,
        title,
        startDate,
        endDate,
        status: PRODUCTION_STATUS_DRAFT,
        createdBy: actor._id,
        notes,
        aiGenerated,
        domainContext,
      });

    const createdPhases =
      await ProductionPhase.insertMany(
        scheduledPhases.map(
          (phase) => ({
            planId: plan._id,
            name: phase.name,
            order: phase.order,
            startDate: phase.startDate,
            endDate: phase.endDate,
            status:
              PRODUCTION_PHASE_STATUS_PENDING,
            kpiTarget: phase.kpiTarget,
          }),
        ),
      );

    const tasksToCreate = [];
    createdPhases.forEach(
      (phase, index) => {
        const phaseTasks =
          tasksInputByPhase[index] ||
          [];
        if (phaseTasks.length === 0) {
          return;
        }

        const scheduledTasks =
          buildTaskSchedule({
            phaseStart: phase.startDate,
            phaseEnd: phase.endDate,
            tasks: phaseTasks,
            schedulePolicy:
              effectiveSchedulePolicy,
            allowParallelByRole: true,
          });

        scheduledTasks.forEach(
          (task) => {
            const assignedStaffProfileIds =
              resolveTaskAssignedStaffIds(
                task,
              );
            const primaryAssignedStaffId =
              assignedStaffProfileIds[0] ||
              null;
            const requiredHeadcount = Math.max(
              1,
              Math.floor(
                Number(
                  task.requiredHeadcount ||
                    1,
                ),
              ),
            );

            const isOwner =
              actor.role ===
              "business_owner";
            const approvalStatus =
              isOwner ?
                PRODUCTION_TASK_APPROVAL_APPROVED
              : PRODUCTION_TASK_APPROVAL_PENDING;
            const reviewedBy =
              isOwner ?
                actor._id
              : null;
            const reviewedAt =
              isOwner ?
                new Date()
              : null;

            tasksToCreate.push({
              planId: plan._id,
              phaseId: phase._id,
              title:
                task.title
                  ?.toString()
                  .trim() ||
                DEFAULT_TASK_TITLE,
              roleRequired:
                task.roleRequired,
              assignedStaffId:
                primaryAssignedStaffId,
              assignedStaffProfileIds,
              requiredHeadcount,
              weight: task.weight || 1,
              startDate: task.startDate,
              dueDate: task.dueDate,
              status:
                PRODUCTION_TASK_STATUS_PENDING,
              instructions:
                task.instructions
                  ?.toString()
                  .trim() || "",
              dependencies:
                (
                  Array.isArray(
                    task.dependencies,
                  )
                ) ?
                  task.dependencies
                : [],
              createdBy: actor._id,
              approvalStatus,
              assignedBy: actor._id,
              reviewedBy,
              reviewedAt,
              rejectionReason: "",
            });
          },
        );
      },
    );

    const createdTasks =
      tasksToCreate.length > 0 ?
        await ProductionTask.insertMany(
          tasksToCreate,
        )
      : [];

    // WHY: Starting a production plan should move product out of sellable stock mode.
    const lifecycleProduct =
      await businessProductService.updateProduct(
        {
          businessId,
          id: productId,
          actor: {
            id: actor._id,
            role: actor.role,
          },
          updates: {
            isActive: false,
            productionState:
              PRODUCT_STATE_IN_PRODUCTION,
            productionPlanId:
              plan._id,
            preorderEnabled: false,
            preorderStartDate: null,
            preorderCapQuantity: 0,
            preorderReservedQuantity: 0,
            preorderReleasedQuantity: 0,
            conservativeYieldQuantity:
              null,
            conservativeYieldUnit: "",
          },
        },
      );

    debug(
      "BUSINESS CONTROLLER: createProductionPlan - success",
      {
        actorId: actor._id,
        planId: plan._id,
        domainContext:
          plan.domainContext,
        productState:
          lifecycleProduct?.productionState,
        phases: createdPhases.length,
        tasks: createdTasks.length,
      },
    );

    return res.status(201).json({
      message:
        PRODUCTION_COPY.PLAN_CREATED,
      plan,
      phases: createdPhases,
      tasks: createdTasks,
      product: lifecycleProduct,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: createProductionPlan - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/production/plans
 * Staff + owner: list production plans.
 */
async function listProductionPlans(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listProductionPlans - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      actor.role === "staff" &&
      !staffProfile
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_PROFILE_REQUIRED,
      });
    }

    const filter = {
      businessId,
    };
    if (
      actor.role === "staff" &&
      actor.estateAssetId
    ) {
      filter.estateAssetId =
        actor.estateAssetId;
    }

    const plans =
      await ProductionPlan.find(filter)
        .sort({ createdAt: -1 })
        .lean();

    debug(
      "BUSINESS CONTROLLER: listProductionPlans - success",
      {
        actorId: actor._id,
        count: plans.length,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_LIST_OK,
      plans,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listProductionPlans - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/production/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD
 * Owner + staff: list calendar tasks that overlap the requested time window.
 *
 * SANITY CHECK (manual):
 * 1) Create a production plan with start/end spanning multiple days.
 * 2) Verify saved tasks have clock times in 09:00-13:00 / 14:00-17:00 windows.
 * 3) Call:
 *    GET /business/production/calendar?from=2026-03-01&to=2026-04-01
 * 4) Confirm items include plan/phase/staff display fields and overlap the range.
 */
async function listProductionCalendar(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listProductionCalendar - entry",
    {
      actorId: req.user?.sub,
      from: req.query?.from,
      to: req.query?.to,
    },
  );

  try {
    const fromRaw = (
      req.query?.from || ""
    )
      .toString()
      .trim();
    const toRaw = (
      req.query?.to || ""
    )
      .toString()
      .trim();
    if (!fromRaw || !toRaw) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.CALENDAR_RANGE_REQUIRED,
      });
    }

    const fromDate = parseDateInput(
      fromRaw,
    );
    const toDate = parseDateInput(
      toRaw,
    );
    if (
      !fromDate ||
      !toDate ||
      toDate <= fromDate
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.CALENDAR_RANGE_INVALID,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });
    if (
      actor.role === "staff" &&
      !staffProfile
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_PROFILE_REQUIRED,
      });
    }

    const planFilter = {
      businessId,
    };
    // WHY: Estate-scoped staff can only see plans from their own estate.
    if (
      actor.role === "staff" &&
      actor.estateAssetId
    ) {
      planFilter.estateAssetId =
        actor.estateAssetId;
    }

    const scopedPlans =
      await ProductionPlan.find(
        planFilter,
      )
        .select({ _id: 1 })
        .lean();
    const scopedPlanIds =
      scopedPlans.map(
        (plan) => plan._id,
      );
    if (scopedPlanIds.length === 0) {
      return res.status(200).json({
        message:
          PRODUCTION_COPY.CALENDAR_LIST_OK,
        from: fromDate,
        to: toDate,
        items: [],
      });
    }

    const tasks =
      await ProductionTask.find({
        planId: {
          $in: scopedPlanIds,
        },
        startDate: { $lt: toDate },
        dueDate: { $gte: fromDate },
      })
        .sort({
          startDate: 1,
          dueDate: 1,
          _id: 1,
        })
        .populate("planId", "title")
        .populate(
          "phaseId",
          "name order",
        )
        .populate({
          path: "assignedStaffId",
          select:
            "staffRole userId",
          populate: {
            path: "userId",
            select: "name email",
          },
        })
        .lean();

    const items = tasks.map(
      (task) => {
        const staffProfile =
          task.assignedStaffId || {};
        const staffUser =
          staffProfile.userId || {};
        const assignedStaffProfileIds =
          resolveTaskAssignedStaffIds(
            task,
          );
        return {
          taskId: task._id,
          title: task.title || "",
          status:
            task.status || "",
          roleRequired:
            task.roleRequired || "",
          requiredHeadcount: Math.max(
            1,
            Number(
              task.requiredHeadcount || 1,
            ),
          ),
          assignedStaffProfileIds,
          assignedCount:
            assignedStaffProfileIds.length,
          startDate:
            task.startDate || null,
          dueDate:
            task.dueDate || null,
          planId:
            task.planId?._id ||
            task.planId ||
            null,
          planTitle:
            task.planId?.title || "",
          phaseId:
            task.phaseId?._id ||
            task.phaseId ||
            null,
          phaseName:
            task.phaseId?.name || "",
          assignedStaffId:
            staffProfile._id ||
            task.assignedStaffId ||
            null,
          assignedStaffName:
            staffUser.name ||
            staffUser.email ||
            "Unassigned",
          assignedStaffRole:
            staffProfile.staffRole ||
            "",
        };
      },
    );

    debug(
      "BUSINESS CONTROLLER: listProductionCalendar - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        from:
          fromDate.toISOString(),
        to: toDate.toISOString(),
        count: items.length,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.CALENDAR_LIST_OK,
      from: fromDate,
      to: toDate,
      items,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listProductionCalendar - error",
      {
        actorId: req.user?.sub,
        from: req.query?.from,
        to: req.query?.to,
        reason: err.message,
        next: "Validate calendar date range and tenant scope before retrying",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /business/production/plans/:id
 * Staff + owner: plan detail with phases/tasks/outputs.
 */
async function getProductionPlanDetail(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: getProductionPlanDetail - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.id,
    },
  );

  try {
    const planId = req.params?.id
      ?.toString()
      .trim();
    if (!planId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      actor.role === "staff" &&
      !staffProfile
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_PROFILE_REQUIRED,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: planId,
        businessId,
      }).lean();

    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      plan.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const phases =
      await ProductionPhase.find({
        planId: plan._id,
      })
        .sort({ order: 1 })
        .lean();

    const tasks =
      await ProductionTask.find({
        planId: plan._id,
      })
        .sort({ startDate: 1 })
        .lean();
    const progressRecords =
      await TaskProgress.find({
        planId: plan._id,
      })
        .sort({ workDate: -1 })
        .lean();

    const outputs =
      await ProductionOutput.find({
        planId: plan._id,
      })
        .sort({ createdAt: -1 })
        .lean();
    const product =
      await businessProductService.getProductById(
        {
          businessId,
          id: plan.productId,
        },
      );
    const capConfidence =
      product ?
        await buildPreorderCapConfidenceSummary(
          {
            productId: product._id,
            businessId,
            planId: plan._id,
            baseCap:
              product.preorderCapQuantity,
          },
        )
      : null;

    const kpis = computeProductionKpis({
      phases,
      tasks,
      outputs,
    });
    const progressStaffIds = Array.from(
      new Set(
        progressRecords
          .map((record) =>
            record.staffId?.toString(),
          )
          .filter(Boolean),
      ),
    );
    const progressStaffProfiles =
      progressStaffIds.length > 0 ?
        await BusinessStaffProfile.find(
          {
            _id: {
              $in: progressStaffIds,
            },
            businessId,
          },
        )
          .populate(
            "userId",
            "name email",
          )
          .lean()
      : [];
    const timelineRows =
      buildTimelineRows({
        progressRecords,
        tasks,
        phases,
        staffProfiles:
          progressStaffProfiles,
      });
    const staffProgressScores =
      buildStaffProgressScores({
        progressRecords,
        staffProfiles:
          progressStaffProfiles,
      });

    debug(
      "BUSINESS CONTROLLER: getProductionPlanDetail - success",
      {
        actorId: actor._id,
        planId: plan._id,
        phases: phases.length,
        tasks: tasks.length,
        progressRows:
          timelineRows.length,
        outputs: outputs.length,
        productState:
          product?.productionState ||
          null,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_DETAIL_OK,
      plan,
      phases,
      tasks,
      outputs,
      kpis,
      product,
      preorderSummary:
        buildPreorderSummary(
          product,
          capConfidence,
        ),
      timelineRows,
      staffProgressScores,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getProductionPlanDetail - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * PATCH /business/production/plans/:id/preorder
 * Owner + estate manager: open/close conservative pre-orders for a production plan.
 */
async function updateProductionPlanPreorder(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateProductionPlanPreorder - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.id,
      hasAllowPreorder:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "allowPreorder",
        ),
    },
  );

  try {
    const planId = req.params?.id
      ?.toString()
      .trim();
    if (!planId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }

    const hasAllowPreorder =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "allowPreorder",
      );
    if (!hasAllowPreorder) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_FLAG_REQUIRED,
      });
    }

    const allowPreorder =
      req.body?.allowPreorder === true;
    const hasConservativeYieldQuantity =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "conservativeYieldQuantity",
      );
    const conservativeYieldQuantity =
      parsePositiveNumberInput(
        req.body
          ?.conservativeYieldQuantity,
      );
    const capRatio =
      parsePreorderCapRatio(
        req.body?.preorderCapRatio,
      );
    const conservativeYieldUnit =
      req.body
        ?.conservativeYieldUnit
        ?.toString()
        .trim() || OUTPUT_UNIT_FALLBACK;

    if (
      allowPreorder &&
      !hasConservativeYieldQuantity
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_YIELD_REQUIRED,
      });
    }
    if (
      allowPreorder &&
      conservativeYieldQuantity ==
        null
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_YIELD_INVALID,
      });
    }
    if (
      allowPreorder &&
      capRatio == null
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_CAP_RATIO_INVALID,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      plan.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const product =
      await businessProductService.getProductById(
        {
          businessId,
          id: plan.productId,
        },
      );
    if (!product) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PRODUCT_NOT_FOUND,
      });
    }

    const updates = {};
    if (allowPreorder) {
      const preorderCapQuantity =
        Math.max(
          1,
          Math.floor(
            conservativeYieldQuantity *
              capRatio,
          ),
        );
      updates.productionState =
        PRODUCT_STATE_AVAILABLE_FOR_PREORDER;
      updates.preorderEnabled = true;
      updates.preorderStartDate =
        new Date();
      updates.preorderCapQuantity =
        preorderCapQuantity;
      updates.preorderReservedQuantity = 0;
      updates.conservativeYieldQuantity =
        conservativeYieldQuantity;
      updates.conservativeYieldUnit =
        conservativeYieldUnit;
      // WHY: Pre-orders reserve future stock; active stock remains false.
      updates.isActive = false;
    } else {
      const fallbackState =
        product.productionState ===
        PRODUCT_STATE_ACTIVE_STOCK ?
          PRODUCT_STATE_ACTIVE_STOCK
        : PRODUCT_STATE_IN_PRODUCTION;
      updates.productionState =
        fallbackState;
      updates.preorderEnabled = false;
      updates.preorderStartDate =
        null;
      updates.preorderCapQuantity = 0;
      updates.preorderReservedQuantity = 0;
      updates.isActive =
        fallbackState ===
        PRODUCT_STATE_ACTIVE_STOCK;
    }

    const updatedProduct =
      await businessProductService.updateProduct(
        {
          businessId,
          id: product._id,
          actor: {
            id: actor._id,
            role: actor.role,
          },
          updates,
        },
      );

    debug(
      "BUSINESS CONTROLLER: updateProductionPlanPreorder - success",
      {
        actorId: actor._id,
        planId: plan._id,
        productId: product._id,
        productionState:
          updatedProduct?.productionState,
        preorderEnabled:
          updatedProduct?.preorderEnabled ===
          true,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PREORDER_STATE_UPDATED,
      planId: plan._id,
      product: updatedProduct,
      preorderSummary:
        buildPreorderSummary(
          updatedProduct,
        ),
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateProductionPlanPreorder - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/production/plans/:planId/preorder/reserve
 * Customer + owner: reserve quantity from conservative pre-order capacity.
 */
async function reserveProductionPlanPreorder(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: reserveProductionPlanPreorder - entry",
    {
      actorId: req.user?.sub,
      planId:
        req.params?.planId ||
        req.params?.id,
      hasQuantity:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "quantity",
        ),
    },
  );

  try {
    const planId = (
      req.params?.planId ||
      req.params?.id ||
      ""
    )
      .toString()
      .trim();
    if (!planId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }

    const hasQuantity =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "quantity",
      );
    if (!hasQuantity) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVE_QUANTITY_REQUIRED,
      });
    }

    const quantity = Number(
      req.body?.quantity,
    );
    if (
      !Number.isFinite(quantity) ||
      quantity <= 0
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVE_QUANTITY_INVALID,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    // WHY: Reservations must stay tenant-scoped to the same plan owner business.
    const plan =
      await ProductionPlan.findOne({
        _id: planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    const product =
      await Product.findOne({
        _id: plan.productId,
        businessId,
      })
        .select({
          preorderEnabled: 1,
          preorderCapQuantity: 1,
          preorderReservedQuantity: 1,
        })
        .lean();
    if (!product) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PRODUCT_NOT_FOUND,
      });
    }
    if (
      product.preorderEnabled !==
      true
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVE_DISABLED,
      });
    }

    const capConfidence =
      await buildPreorderCapConfidenceSummary({
        productId: product._id,
        businessId,
        planId: plan._id,
        baseCap:
          product.preorderCapQuantity,
      });
    const effectiveCap = Math.max(
      0,
      Number(capConfidence.effectiveCap || 0),
    );

    // WHY: Enforcement is atomic; DB evaluates reserved + quantity <= effective cap in one write.
    const updatedProduct =
      await Product.findOneAndUpdate(
        {
          _id: product._id,
          businessId,
          preorderEnabled: true,
          $expr: {
            $lte: [
              {
                $add: [
                  "$preorderReservedQuantity",
                  quantity,
                ],
              },
              effectiveCap,
            ],
          },
        },
        {
          $inc: {
            preorderReservedQuantity:
              quantity,
          },
        },
        {
          new: true,
        },
      ).lean();

    if (!updatedProduct) {
      return res.status(409).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVE_CAP_EXCEEDED,
      });
    }

    // WHY: Reservation record provides auditable hold-level traceability.
    const reservation =
      await PreorderReservation.create({
        businessId,
        planId: plan._id,
        userId: actor._id,
        quantity,
        status: "reserved",
      });

    const preorderSummary =
      (() => {
        const baseSummary =
          buildReservationSummary(
            updatedProduct,
          );
        return {
          ...baseSummary,
          effectiveCap,
          remaining: Math.max(
            0,
            effectiveCap -
              Number(
                baseSummary.reserved || 0,
              ),
          ),
        };
      })();

    debug(
      "BUSINESS CONTROLLER: reserveProductionPlanPreorder - success",
      {
        actorId: actor._id,
        planId: plan._id,
        reservationId:
          reservation._id,
        quantity,
        cap: preorderSummary.cap,
        effectiveCap:
          preorderSummary.effectiveCap,
        reserved:
          preorderSummary.reserved,
        remaining:
          preorderSummary.remaining,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PREORDER_RESERVE_CREATED,
      reservation,
      preorderSummary,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: reserveProductionPlanPreorder - error",
      {
        actorId: req.user?.sub,
        planId:
          req.params?.planId ||
          req.params?.id,
        reason: err.message,
        next: "Validate preorder state, quantity, and cap before retrying",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /business/preorder/reservations
 * Owner: monitor reservation lifecycle with status + plan filters.
 */
async function listPreorderReservations(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listPreorderReservations - entry",
    {
      actorId: req.user?.sub,
      status:
        req.query?.status || null,
      planId:
        req.query?.planId || null,
      page:
        req.query?.page || null,
      limit:
        req.query?.limit || null,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (
      actor?.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVATIONS_LIST_FORBIDDEN,
      });
    }

    const statusFilter = (
      req.query?.status || ""
    )
      .toString()
      .trim()
      .toLowerCase();
    const planIdFilter = (
      req.query?.planId || ""
    )
      .toString()
      .trim();

    if (
      statusFilter &&
      !PreorderReservation.PREORDER_RESERVATION_STATUSES.includes(
        statusFilter,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVATIONS_STATUS_INVALID,
      });
    }
    if (
      planIdFilter &&
      !mongoose.Types.ObjectId.isValid(
        planIdFilter,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVATIONS_PLAN_ID_INVALID,
      });
    }

    const parsedPage = Number(
      req.query?.page,
    );
    const parsedLimit = Number(
      req.query?.limit,
    );
    const page =
      Number.isFinite(parsedPage) &&
      parsedPage > 0 ?
        Math.floor(parsedPage)
      : 1;
    const limit =
      Number.isFinite(parsedLimit) &&
      parsedLimit > 0 ?
        Math.min(
          100,
          Math.floor(parsedLimit),
        )
      : 20;
    const skip =
      (page - 1) * limit;

    const baseFilter = {
      businessId,
      ...(planIdFilter ?
        { planId: planIdFilter }
      : {}),
    };
    const queryFilter = {
      ...baseFilter,
      ...(statusFilter ?
        { status: statusFilter }
      : {}),
    };

    const [reservations, total, summaryRows] =
      await Promise.all([
        PreorderReservation.find(
          queryFilter,
        )
          .sort({
            createdAt: -1,
            _id: -1,
          })
          .skip(skip)
          .limit(limit)
          .populate(
            "planId",
            "title productId status",
          )
          .populate(
            "userId",
            "name email role",
          )
          .lean(),
        PreorderReservation.countDocuments(
          queryFilter,
        ),
        PreorderReservation.aggregate([
          { $match: baseFilter },
          {
            $group: {
              _id: "$status",
              count: { $sum: 1 },
            },
          },
        ]),
      ]);

    const summary = {
      total: 0,
      reserved: 0,
      confirmed: 0,
      released: 0,
      expired: 0,
    };
    summaryRows.forEach((row) => {
      const status = (
        row?._id || ""
      ).toString();
      const count = Number(
        row?.count || 0,
      );
      if (
        Object.prototype.hasOwnProperty.call(
          summary,
          status,
        )
      ) {
        summary[status] = count;
      }
      summary.total += count;
    });

    const totalPages =
      total > 0 ?
        Math.ceil(total / limit)
      : 1;

    debug(
      "BUSINESS CONTROLLER: listPreorderReservations - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        statusFilter:
          statusFilter || null,
        planIdFilter:
          planIdFilter || null,
        page,
        limit,
        total,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PREORDER_RESERVATIONS_LIST_OK,
      filters: {
        status:
          statusFilter || null,
        planId:
          planIdFilter || null,
        page,
        limit,
      },
      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext:
          page < totalPages,
        hasPrev: page > 1,
      },
      summary,
      reservations,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listPreorderReservations - error",
      {
        actorId: req.user?.sub,
        reason: err.message,
        next: "Validate owner scope and reservation filters before retrying",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/preorder/reservations/:id/release
 * Customer + owner: release a reserved hold and return quantity to available pre-order capacity.
 */
async function releasePreorderReservation(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: releasePreorderReservation - entry",
    {
      actorId: req.user?.sub,
      reservationId:
        req.params?.id || "",
      intent:
        "release reserved preorder hold back into available capacity",
    },
  );

  try {
    const reservationId = (
      req.params?.id || ""
    )
      .toString()
      .trim();
    if (
      !reservationId ||
      !mongoose.Types.ObjectId.isValid(
        reservationId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVATION_NOT_FOUND,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const reservationScope = {
      _id: reservationId,
      businessId,
    };
    // WHY: Customers can only release their own reservation records.
    if (actor.role === "customer") {
      reservationScope.userId = actor._id;
    }

    const existingReservation =
      await PreorderReservation.findOne(
        reservationScope,
      ).lean();
    if (!existingReservation) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVATION_NOT_FOUND,
      });
    }

    if (
      existingReservation.status ===
      "released"
    ) {
      // WHY: Release endpoint is idempotent; repeated calls should not mutate counters.
      const existingPlan =
        await ProductionPlan.findOne({
          _id: existingReservation.planId,
          businessId,
        })
          .select({ productId: 1 })
          .lean();
      const existingProduct =
        existingPlan?.productId ?
          await Product.findOne({
            _id: existingPlan.productId,
            businessId,
          })
            .select({
              preorderCapQuantity: 1,
              preorderReservedQuantity: 1,
            })
            .lean()
        : null;

      return res.status(200).json({
        message:
          PRODUCTION_COPY.PREORDER_RELEASE_ALREADY_APPLIED,
        idempotent: true,
        reservation:
          existingReservation,
        preorderSummary:
          buildReservationSummary(
            existingProduct || {},
          ),
      });
    }

    if (
      existingReservation.status !==
      "reserved"
    ) {
      return res.status(409).json({
        error:
          PRODUCTION_COPY.PREORDER_RELEASE_STATUS_INVALID,
      });
    }

    let releasedReservation = null;
    let preorderSummary = null;
    let session = null;
    let idempotent = false;

    try {
      session =
        await mongoose.startSession();

      await session.withTransaction(
        async () => {
          const reservation =
            await PreorderReservation.findOneAndUpdate(
              {
                _id: reservationId,
                businessId,
                ...(actor.role ===
                    "customer" ?
                    { userId: actor._id }
                  : {}),
                status: "reserved",
              },
              {
                $set: {
                  status: "released",
                },
              },
              {
                new: false,
                session,
              },
            );

          if (!reservation) {
            const latestReservation =
              await PreorderReservation.findOne(
                reservationScope,
              )
                .session(session)
                .lean();
            if (
              latestReservation &&
              latestReservation.status ===
                "released"
            ) {
              idempotent = true;
              releasedReservation =
                latestReservation;
              return;
            }
            throw new Error(
              PRODUCTION_COPY.PREORDER_RELEASE_STATUS_INVALID,
            );
          }

          const plan =
            await ProductionPlan.findOne({
              _id: reservation.planId,
              businessId,
            })
              .select({ productId: 1 })
              .session(session)
              .lean();
          if (!plan?.productId) {
            throw new Error(
              PRODUCTION_COPY.PLAN_NOT_FOUND,
            );
          }

          const productBefore =
            await Product.findOne({
              _id: plan.productId,
              businessId,
            })
              .select({
                preorderReservedQuantity: 1,
              })
              .session(session)
              .lean();
          if (!productBefore) {
            throw new Error(
              PRODUCTION_COPY.PRODUCT_NOT_FOUND,
            );
          }

          const beforeReserved = Math.max(
            0,
            Number(
              productBefore.preorderReservedQuantity ||
                0,
            ),
          );
          const decrementBy = Math.min(
            beforeReserved,
            Number(
              reservation.quantity || 0,
            ),
          );

          // WHY: Counter update is bounded so release cannot push reserved below zero.
          const productAfter =
            await Product.findOneAndUpdate(
              {
                _id: plan.productId,
                businessId,
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
                preorderCapQuantity: 1,
                preorderReservedQuantity: 1,
              })
              .lean();
          if (!productAfter) {
            throw new Error(
              PRODUCTION_COPY.PRODUCT_NOT_FOUND,
            );
          }

          preorderSummary =
            buildReservationSummary(
              productAfter,
            );
          releasedReservation =
            await PreorderReservation.findById(
              reservationId,
            )
              .session(session)
              .lean();
        },
      );
    } finally {
      if (session) {
        await session.endSession();
      }
    }

    if (!preorderSummary) {
      const fallbackPlan =
        await ProductionPlan.findOne({
          _id: releasedReservation?.planId,
          businessId,
        })
          .select({ productId: 1 })
          .lean();
      const fallbackProduct =
        fallbackPlan?.productId ?
          await Product.findOne({
            _id: fallbackPlan.productId,
            businessId,
          })
            .select({
              preorderCapQuantity: 1,
              preorderReservedQuantity: 1,
            })
            .lean()
        : null;
      preorderSummary =
        buildReservationSummary(
          fallbackProduct || {},
        );
    }

    debug(
      "BUSINESS CONTROLLER: releasePreorderReservation - success",
      {
        actorId: actor._id,
        reservationId,
        idempotent,
        reservationStatus:
          releasedReservation?.status,
        cap: preorderSummary.cap,
        reserved:
          preorderSummary.reserved,
        remaining:
          preorderSummary.remaining,
      },
    );

    return res.status(200).json({
      message:
        idempotent ?
          PRODUCTION_COPY.PREORDER_RELEASE_ALREADY_APPLIED
        : PRODUCTION_COPY.PREORDER_RELEASED,
      idempotent,
      reservation:
        releasedReservation,
      preorderSummary,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: releasePreorderReservation - error",
      {
        actorId: req.user?.sub,
        reservationId:
          req.params?.id || "",
        reason: err.message,
        next: "Confirm reservation scope and status before retrying release",
      },
    );
    let statusCode = 400;
    if (
      err.message ===
      PRODUCTION_COPY.PREORDER_RELEASE_STATUS_INVALID
    ) {
      statusCode = 409;
    } else if (
      err.message ===
        PRODUCTION_COPY.PREORDER_RESERVATION_NOT_FOUND ||
      err.message ===
        PRODUCTION_COPY.PLAN_NOT_FOUND ||
      err.message ===
        PRODUCTION_COPY.PRODUCT_NOT_FOUND
    ) {
      statusCode = 404;
    }
    return res.status(statusCode).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/preorder/reservations/:id/confirm
 * Customer + owner: confirm a reserved hold after payment succeeds.
 */
async function confirmPreorderReservation(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: confirmPreorderReservation - entry",
    {
      actorId: req.user?.sub,
      reservationId:
        req.params?.id || "",
      intent:
        "mark reserved preorder hold as confirmed after successful payment",
    },
  );

  try {
    const reservationId = (
      req.params?.id || ""
    )
      .toString()
      .trim();
    if (
      !reservationId ||
      !mongoose.Types.ObjectId.isValid(
        reservationId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVATION_NOT_FOUND,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const reservationScope = {
      _id: reservationId,
      businessId,
    };
    // WHY: Customers can only confirm their own reservation records.
    if (actor.role === "customer") {
      reservationScope.userId = actor._id;
    }

    const existingReservation =
      await PreorderReservation.findOne(
        reservationScope,
      ).lean();
    if (!existingReservation) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVATION_NOT_FOUND,
      });
    }

    let idempotent = false;
    let confirmedReservation = null;

    if (
      existingReservation.status ===
      "confirmed"
    ) {
      idempotent = true;
      confirmedReservation =
        existingReservation;
    } else {
      if (
        existingReservation.status !==
        "reserved"
      ) {
        return res.status(409).json({
          error:
            PRODUCTION_COPY.PREORDER_CONFIRM_STATUS_INVALID,
        });
      }

      confirmedReservation =
        await PreorderReservation.findOneAndUpdate(
          {
            ...reservationScope,
            status: "reserved",
          },
          {
            $set: {
              status: "confirmed",
            },
          },
          {
            new: true,
          },
        ).lean();

      if (!confirmedReservation) {
        const latestReservation =
          await PreorderReservation.findOne(
            reservationScope,
          ).lean();
        if (
          latestReservation &&
          latestReservation.status ===
            "confirmed"
        ) {
          idempotent = true;
          confirmedReservation =
            latestReservation;
        } else if (!latestReservation) {
          return res.status(404).json({
            error:
              PRODUCTION_COPY.PREORDER_RESERVATION_NOT_FOUND,
          });
        } else {
          return res.status(409).json({
            error:
              PRODUCTION_COPY.PREORDER_CONFIRM_STATUS_INVALID,
          });
        }
      }
    }

    const plan =
      await ProductionPlan.findOne({
        _id: confirmedReservation.planId,
        businessId,
      })
        .select({ productId: 1 })
        .lean();
    if (!plan?.productId) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    const product =
      await Product.findOne({
        _id: plan.productId,
        businessId,
      })
        .select({
          preorderCapQuantity: 1,
          preorderReservedQuantity: 1,
        })
        .lean();
    if (!product) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PRODUCT_NOT_FOUND,
      });
    }

    const preorderSummary =
      buildReservationSummary(product);

    debug(
      "BUSINESS CONTROLLER: confirmPreorderReservation - success",
      {
        actorId: actor._id,
        reservationId,
        idempotent,
        reservationStatus:
          confirmedReservation?.status,
        reservedBefore:
          preorderSummary.reserved,
        reservedAfter:
          preorderSummary.reserved,
        cap: preorderSummary.cap,
        remaining:
          preorderSummary.remaining,
      },
    );

    return res.status(200).json({
      message:
        idempotent ?
          PRODUCTION_COPY.PREORDER_CONFIRM_ALREADY_APPLIED
        : PRODUCTION_COPY.PREORDER_CONFIRMED,
      idempotent,
      reservation:
        confirmedReservation,
      preorderSummary,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: confirmPreorderReservation - error",
      {
        actorId: req.user?.sub,
        reservationId:
          req.params?.id || "",
        reason: err.message,
        next: "Confirm reservation scope and status before retrying confirm",
      },
    );
    let statusCode = 400;
    if (
      err.message ===
      PRODUCTION_COPY.PREORDER_CONFIRM_STATUS_INVALID
    ) {
      statusCode = 409;
    } else if (
      err.message ===
        PRODUCTION_COPY.PREORDER_RESERVATION_NOT_FOUND ||
      err.message ===
        PRODUCTION_COPY.PLAN_NOT_FOUND ||
      err.message ===
        PRODUCTION_COPY.PRODUCT_NOT_FOUND
    ) {
      statusCode = 404;
    }
    return res.status(statusCode).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/preorder/reservations/reconcile-expired
 * Owner: reconcile expired reservation holds to release blocked pre-order capacity.
 */
async function reconcileExpiredPreorderReservationsHandler(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: reconcileExpiredPreorderReservations - entry",
    {
      actorId: req.user?.sub,
      intent:
        "expire stale holds and release reserved preorder quantity",
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    // WHY: Only owner reconciliation is supported in this step to keep authority explicit.
    if (
      actor?.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.PREORDER_RECONCILE_FORBIDDEN,
      });
    }

    const summary =
      await reconcileExpiredPreorderReservations(
        {
          businessId,
          now: new Date(),
        },
      );

    debug(
      "BUSINESS CONTROLLER: reconcileExpiredPreorderReservations - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        scannedCount:
          summary.scannedCount,
        expiredCount:
          summary.expiredCount,
        skippedCount:
          summary.skippedCount,
        errorCount:
          summary.errorCount,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PREORDER_RECONCILE_COMPLETED,
      summary,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: reconcileExpiredPreorderReservations - error",
      {
        actorId: req.user?.sub,
        reason: err.message,
        next: "Validate business scope and retry reconciliation",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * PATCH /business/production/tasks/:id/status
 * Staff: update task status (own tasks only).
 */
async function updateProductionTaskStatus(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateProductionTaskStatus - entry",
    {
      actorId: req.user?.sub,
      taskId: req.params?.id,
      status: req.body?.status,
    },
  );

  try {
    const taskId = req.params?.id
      ?.toString()
      .trim();
    const nextStatus =
      req.body?.status
        ?.toString()
        .trim() || "";

    if (!taskId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }
    if (!nextStatus) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_STATUS_REQUIRED,
      });
    }
    if (
      !TASK_STATUS_VALUES.includes(
        nextStatus,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_STATUS_REQUIRED,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
      });

    const task =
      await ProductionTask.findById(
        taskId,
      );

    if (!task) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: task.planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    // WHY: Staff can only update tasks assigned to them.
    if (
      actor.role === "staff" &&
      staffProfile?._id?.toString() !==
        task.assignedStaffId?.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    task.status = nextStatus;
    if (
      nextStatus ===
      PRODUCTION_TASK_STATUS_DONE
    ) {
      task.completedAt = new Date();
    }
    await task.save();

    debug(
      "BUSINESS CONTROLLER: updateProductionTaskStatus - success",
      {
        actorId: actor._id,
        taskId: task._id,
        status: task.status,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_STATUS_UPDATED,
      task,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateProductionTaskStatus - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * PUT /business/production/tasks/:taskId/assign
 * Owner + managers: assign one or more staff profiles to a task role.
 */
async function assignProductionTaskStaffProfiles(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: assignProductionTaskStaffProfiles - entry",
    {
      actorId: req.user?.sub,
      taskId:
        req.params?.taskId,
      hasAssignedStaffProfileIds:
        Array.isArray(
          req.body
            ?.assignedStaffProfileIds,
        ),
    },
  );

  try {
    const taskId = (
      req.params?.taskId || ""
    )
      .toString()
      .trim();
    if (!taskId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_ASSIGNMENT_TASK_ID_REQUIRED,
      });
    }
    if (
      !mongoose.Types.ObjectId.isValid(
        taskId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_ASSIGNMENT_TASK_ID_INVALID,
      });
    }

    const rawAssignedIds =
      req.body
        ?.assignedStaffProfileIds;
    if (!Array.isArray(rawAssignedIds)) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_ASSIGNMENT_STAFF_IDS_REQUIRED,
      });
    }

    const assignedStaffProfileIds = Array.from(
      new Set(
        rawAssignedIds
          .map((value) =>
            normalizeStaffIdInput(
              value,
            ),
          )
          .filter(Boolean),
      ),
    );
    if (
      assignedStaffProfileIds.some(
        (staffId) =>
          !mongoose.Types.ObjectId.isValid(
            staffId,
          ),
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_ASSIGNMENT_STAFF_ID_INVALID,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });
    if (
      !canAssignProductionTasks({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const task =
      await ProductionTask.findById(
        taskId,
      );
    if (!task) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: task.planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      plan.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    let matchingProfiles = [];
    if (
      assignedStaffProfileIds.length > 0
    ) {
      matchingProfiles =
        await BusinessStaffProfile.find({
          _id: {
            $in: assignedStaffProfileIds,
          },
          businessId,
          status: STAFF_STATUS_ACTIVE,
        }).lean();
      if (
        matchingProfiles.length !==
        assignedStaffProfileIds.length
      ) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.TASK_ASSIGNMENT_STAFF_PROFILE_NOT_FOUND,
        });
      }

      for (const profile of matchingProfiles) {
        if (
          profile.staffRole !==
          task.roleRequired
        ) {
          return res.status(400).json({
            error:
              PRODUCTION_COPY.TASK_ASSIGNMENT_ROLE_MISMATCH,
          });
        }
        if (
          plan.estateAssetId &&
          profile.estateAssetId &&
          profile.estateAssetId.toString() !==
            plan.estateAssetId.toString()
        ) {
          return res.status(400).json({
            error:
              PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
          });
        }
      }
    }

    task.assignedStaffProfileIds =
      assignedStaffProfileIds;
    task.assignedStaffId =
      assignedStaffProfileIds[0] ||
      null;
    task.assignedBy = actor._id;
    await task.save();

    const requiredHeadcount = Math.max(
      1,
      Math.floor(
        Number(
          task.requiredHeadcount || 1,
        ),
      ),
    );
    const assignedCount =
      assignedStaffProfileIds.length;
    const shortage = Math.max(
      0,
      requiredHeadcount -
        assignedCount,
    );
    const warning =
      shortage > 0 ?
        PRODUCTION_COPY.TASK_ASSIGNMENT_INCOMPLETE
      : "";

    debug(
      "BUSINESS CONTROLLER: assignProductionTaskStaffProfiles - success",
      {
        actorId: actor._id,
        taskId: task._id,
        roleRequired:
          task.roleRequired,
        requiredHeadcount,
        assignedCount,
        shortage,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_ASSIGNMENT_UPDATED,
      task,
      assignment: {
        requiredHeadcount,
        assignedCount,
        shortage,
        warning,
      },
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: assignProductionTaskStaffProfiles - error",
      {
        actorId: req.user?.sub,
        taskId:
          req.params?.taskId,
        reason: err.message,
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/tasks/:taskId/progress
 * Owner + managers: record or update daily task execution truth.
 */
async function logProductionTaskProgress(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: logProductionTaskProgress - entry",
    {
      actorId: req.user?.sub,
      taskId:
        req.params?.taskId ||
        req.params?.id,
      hasWorkDate: Boolean(
        req.body?.workDate,
      ),
      hasActualPlots:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "actualPlots",
        ),
      hasStaffId:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "staffId",
        ),
    },
  );

  try {
    const taskId = (
      req.params?.taskId ||
      req.params?.id ||
      ""
    )
      ?.toString()
      .trim();
    if (!taskId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const hasActualPlots =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "actualPlots",
      );
    if (!hasActualPlots) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_ACTUAL_REQUIRED,
      });
    }

    const workDateRaw =
      req.body?.workDate
        ?.toString()
        .trim() || "";
    if (!workDateRaw) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_DATE_REQUIRED,
      });
    }

    const normalizedWorkDate =
      normalizeWorkDateToDayStart(
        workDateRaw,
      );
    if (!normalizedWorkDate) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_DATE_INVALID,
      });
    }

    const actualPlots = Number(
      req.body?.actualPlots,
    );
    if (
      !Number.isFinite(actualPlots) ||
      actualPlots < 0
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_ACTUAL_INVALID,
      });
    }
    if (
      actualPlots >
      HUMANE_WORKLOAD_LIMITS.maxPlotsPerFarmerPerDay
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_HUMANE_LIMIT_EXCEEDED,
        maxAllowedPlots:
          HUMANE_WORKLOAD_LIMITS.maxPlotsPerFarmerPerDay,
      });
    }

    const delayReason =
      normalizeTaskProgressDelayReason(
        req.body?.delayReason,
      );
    if (
      !PRODUCTION_TASK_PROGRESS_DELAY_REASONS.includes(
        delayReason,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_DELAY_REASON_INVALID,
      });
    }
    if (
      actualPlots === 0 &&
      delayReason === "none"
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_ZERO_DELAY_REASON_REQUIRED,
      });
    }
    const notes =
      req.body?.notes
        ?.toString()
        .trim() || "";
    const requestedStaffId =
      normalizeStaffIdInput(
        req.body?.staffId,
      );
    if (
      requestedStaffId &&
      !mongoose.Types.ObjectId.isValid(
        requestedStaffId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_STAFF_ID_INVALID,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canAssignProductionTasks({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const task =
      await ProductionTask.findById(
        taskId,
      ).lean();
    if (!task) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: task.planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      plan.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const assignedStaffIds =
      resolveTaskAssignedStaffIds(task);
    if (assignedStaffIds.length === 0) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.STAFF_ASSIGN_REQUIRED,
      });
    }

    let effectiveStaffId =
      assignedStaffIds[0];
    if (
      assignedStaffIds.length > 1 &&
      !requestedStaffId
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_STAFF_REQUIRED_FOR_MULTI_ASSIGN,
      });
    }
    if (requestedStaffId) {
      if (
        !assignedStaffIds.includes(
          requestedStaffId,
        )
      ) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.TASK_PROGRESS_STAFF_NOT_ASSIGNED,
        });
      }
      effectiveStaffId =
        requestedStaffId;
    }
    if (
      !mongoose.Types.ObjectId.isValid(
        effectiveStaffId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_STAFF_ID_INVALID,
      });
    }

    const effectiveStaffProfile =
      await BusinessStaffProfile.findOne({
        _id: effectiveStaffId,
        businessId,
      }).lean();
    const planEstateId =
      normalizeStaffIdInput(
        plan.estateAssetId,
      );
    const staffEstateId =
      normalizeStaffIdInput(
        effectiveStaffProfile?.estateAssetId,
      );
    if (
      !effectiveStaffProfile ||
      (planEstateId &&
        planEstateId !==
          staffEstateId)
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
      });
    }

    const expectedPlots =
      Math.max(
        0,
        Number(task.weight || 0),
      );
    const progress =
      await TaskProgress.findOneAndUpdate(
        {
          taskId: task._id,
          staffId:
            effectiveStaffId,
          workDate:
            normalizedWorkDate,
        },
        {
          $set: {
            planId: plan._id,
            expectedPlots,
            actualPlots,
            delayReason,
            notes,
          },
          $setOnInsert: {
            createdBy: actor._id,
          },
        },
        {
          new: true,
          upsert: true,
          setDefaultsOnInsert: true,
        },
      ).lean();

    debug(
      "BUSINESS CONTROLLER: logProductionTaskProgress - success",
      {
        actorId: actor._id,
        taskId: task._id,
        planId: plan._id,
        staffId:
          effectiveStaffId,
        assignedStaffCount:
          assignedStaffIds.length,
        requestedStaffId,
        workDate:
          normalizedWorkDate,
        actualPlots,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_CREATED,
      progress,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: logProductionTaskProgress - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/production/tasks/progress/batch
 * Owner + managers: record multiple daily task progress rows in one request.
 */
async function logProductionTaskProgressBatch(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: logProductionTaskProgressBatch - entry",
    {
      actorId: req.user?.sub,
      hasWorkDate: Boolean(
        req.body?.workDate,
      ),
      entryCount: Array.isArray(
        req.body?.entries,
      ) ?
        req.body.entries.length
      : 0,
    },
  );

  try {
    const workDateRaw =
      req.body?.workDate
        ?.toString()
        .trim() || "";
    if (!workDateRaw) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_BATCH_DATE_REQUIRED,
      });
    }

    const normalizedWorkDate =
      normalizeWorkDateToDayStart(
        workDateRaw,
      );
    if (!normalizedWorkDate) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_BATCH_DATE_INVALID,
      });
    }

    const entries =
      Array.isArray(req.body?.entries) ?
        req.body.entries
      : [];
    if (entries.length === 0) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_BATCH_ENTRIES_REQUIRED,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canAssignProductionTasks({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const taskIdsForLookup = Array.from(
      new Set(
        entries
          .map((entry) =>
            normalizeStaffIdInput(
              entry?.taskId,
            ),
          )
          .filter((taskId) =>
            mongoose.Types.ObjectId.isValid(
              taskId,
            ),
          ),
      ),
    );
    const tasks =
      taskIdsForLookup.length > 0 ?
        await ProductionTask.find({
          _id: {
            $in: taskIdsForLookup,
          },
        }).lean()
      : [];
    const taskMap = new Map(
      tasks.map((task) => [
        task._id.toString(),
        task,
      ]),
    );

    const planIdsForLookup = Array.from(
      new Set(
        tasks
          .map((task) =>
            normalizeStaffIdInput(
              task?.planId,
            ),
          )
          .filter(Boolean),
      ),
    );
    const plans =
      planIdsForLookup.length > 0 ?
        await ProductionPlan.find({
          _id: {
            $in: planIdsForLookup,
          },
          businessId,
        }).lean()
      : [];
    const planMap = new Map(
      plans.map((plan) => [
        plan._id.toString(),
        plan,
      ]),
    );

    const staffIdsForLookup = Array.from(
      new Set(
        entries
          .map((entry) =>
            normalizeStaffIdInput(
              entry?.staffId,
            ),
          )
          .filter((staffId) =>
            mongoose.Types.ObjectId.isValid(
              staffId,
            ),
          ),
      ),
    );
    const entryStaffProfiles =
      staffIdsForLookup.length > 0 ?
        await BusinessStaffProfile.find({
          _id: {
            $in: staffIdsForLookup,
          },
          businessId,
        }).lean()
      : [];
    const entryStaffProfileMap =
      new Map(
        entryStaffProfiles.map(
          (profile) => [
            profile._id.toString(),
            profile,
          ],
        ),
      );

    const successes = [];
    const errors = [];

    for (
      let index = 0;
      index < entries.length;
      index += 1
    ) {
      const entry = entries[index] || {};
      const taskId =
        normalizeStaffIdInput(
          entry?.taskId,
        );
      const staffId =
        normalizeStaffIdInput(
          entry?.staffId,
        );

      const pushEntryError = ({
        errorCode,
        error,
      }) => {
        errors.push(
          buildBatchTaskProgressError({
            index,
            taskId,
            staffId,
            errorCode,
            error,
          }),
        );
      };

      if (!taskId) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_TASK_ID_REQUIRED,
          error:
            PRODUCTION_COPY.TASK_NOT_FOUND,
        });
        continue;
      }
      if (
        !mongoose.Types.ObjectId.isValid(
          taskId,
        )
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_TASK_ID_INVALID,
          error:
            PRODUCTION_COPY.TASK_NOT_FOUND,
        });
        continue;
      }

      const task =
        taskMap.get(taskId);
      if (!task) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_TASK_NOT_FOUND,
          error:
            PRODUCTION_COPY.TASK_NOT_FOUND,
        });
        continue;
      }

      const plan = planMap.get(
        normalizeStaffIdInput(
          task?.planId,
        ),
      );
      if (!plan) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_PLAN_NOT_FOUND,
          error:
            PRODUCTION_COPY.PLAN_NOT_FOUND,
        });
        continue;
      }

      if (
        actor.role === "staff" &&
        actor.estateAssetId &&
        plan.estateAssetId?.toString() !==
          actor.estateAssetId.toString()
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_FORBIDDEN,
          error:
            PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
        });
        continue;
      }

      if (!staffId) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_ID_REQUIRED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_STAFF_ID_INVALID,
        });
        continue;
      }
      if (
        !mongoose.Types.ObjectId.isValid(
          staffId,
        )
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_ID_INVALID,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_STAFF_ID_INVALID,
        });
        continue;
      }

      const assignedStaffIds =
        resolveTaskAssignedStaffIds(
          task,
        );
      if (
        !assignedStaffIds.includes(
          staffId,
        )
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_NOT_ASSIGNED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_STAFF_NOT_ASSIGNED,
        });
        continue;
      }

      const effectiveStaffProfile =
        entryStaffProfileMap.get(
          staffId,
        );
      const planEstateId =
        normalizeStaffIdInput(
          plan.estateAssetId,
        );
      const staffEstateId =
        normalizeStaffIdInput(
          effectiveStaffProfile?.estateAssetId,
        );
      if (
        !effectiveStaffProfile ||
        (planEstateId &&
          planEstateId !==
            staffEstateId)
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_SCOPE_INVALID,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
        });
        continue;
      }

      const hasActualPlots =
        Object.prototype.hasOwnProperty.call(
          entry,
          "actualPlots",
        );
      if (!hasActualPlots) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_REQUIRED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_ACTUAL_REQUIRED,
        });
        continue;
      }

      const actualPlots = Number(
        entry?.actualPlots,
      );
      if (
        !Number.isFinite(actualPlots) ||
        actualPlots < 0
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_INVALID,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_ACTUAL_INVALID,
        });
        continue;
      }
      if (
        actualPlots >
        HUMANE_WORKLOAD_LIMITS.maxPlotsPerFarmerPerDay
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_HUMANE_LIMIT_EXCEEDED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_HUMANE_LIMIT_EXCEEDED,
        });
        continue;
      }

      const delayReason =
        normalizeTaskProgressDelayReason(
          entry?.delayReason,
        );
      if (
        !PRODUCTION_TASK_PROGRESS_DELAY_REASONS.includes(
          delayReason,
        )
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_DELAY_REASON_INVALID,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_DELAY_REASON_INVALID,
        });
        continue;
      }
      if (
        actualPlots === 0 &&
        delayReason === "none"
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_ZERO_DELAY_REQUIRED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_ZERO_DELAY_REASON_REQUIRED,
        });
        continue;
      }

      const notes =
        entry?.notes
          ?.toString()
          .trim() || "";
      const expectedPlots =
        Math.max(
          0,
          Number(task.weight || 0),
        );

      try {
        const progress =
          await TaskProgress.findOneAndUpdate(
            {
              taskId: task._id,
              staffId,
              workDate:
                normalizedWorkDate,
            },
            {
              $set: {
                planId: plan._id,
                expectedPlots,
                actualPlots,
                delayReason,
                notes,
              },
              $setOnInsert: {
                createdBy: actor._id,
              },
            },
            {
              new: true,
              upsert: true,
              setDefaultsOnInsert: true,
            },
          ).lean();

        successes.push({
          index,
          taskId,
          staffId,
          progress,
        });
      } catch (entryError) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_UNKNOWN,
          error:
            entryError.message,
        });
      }
    }

    const summary = {
      totalEntries: entries.length,
      successCount:
        successes.length,
      errorCount: errors.length,
    };

    debug(
      "BUSINESS CONTROLLER: logProductionTaskProgressBatch - success",
      {
        actorId: actor._id,
        workDate:
          normalizedWorkDate,
        totalEntries:
          summary.totalEntries,
        successCount:
          summary.successCount,
        errorCount:
          summary.errorCount,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_BATCH_PROCESSED,
      workDate:
        normalizedWorkDate,
      summary,
      successes,
      errors,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: logProductionTaskProgressBatch - error",
      {
        actorId: req.user?.sub,
        reason: err.message,
        next: "Validate batch payload and business scope before retrying",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/task-progress/:id/approve
 * Owner + estate manager: verify a daily progress record.
 */
async function approveTaskProgress(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: approveTaskProgress - entry",
    {
      actorId: req.user?.sub,
      progressId:
        req.params?.id,
    },
  );

  try {
    const progressId = (
      req.params?.id || ""
    )
      .toString()
      .trim();
    if (
      !progressId ||
      !mongoose.Types.ObjectId.isValid(
        progressId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_NOT_FOUND,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });
    if (
      !canReviewTaskProgress({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_REVIEW_FORBIDDEN,
      });
    }

    const { progress, plan } =
      await loadTaskProgressInBusinessScope(
        {
          progressId,
          businessId,
        },
      );
    if (!progress || !plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_NOT_FOUND,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      plan.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_REVIEW_FORBIDDEN,
      });
    }

    const alreadyApproved =
      Boolean(progress.approvedAt) &&
      Boolean(progress.approvedBy);
    if (!alreadyApproved) {
      progress.approvedBy = actor._id;
      progress.approvedAt = new Date();
      await progress.save();
    }

    debug(
      "BUSINESS CONTROLLER: approveTaskProgress - success",
      {
        actorId: actor._id,
        progressId: progress._id,
        planId: progress.planId,
        taskId: progress.taskId,
        alreadyApproved,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_APPROVED,
      progress,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: approveTaskProgress - error",
      {
        actorId: req.user?.sub,
        progressId:
          req.params?.id,
        reason: err.message,
        next: "Confirm review role and progress ownership before retrying",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/task-progress/:id/reject
 * Owner + estate manager: mark a progress row for review without deleting it.
 */
async function rejectTaskProgress(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: rejectTaskProgress - entry",
    {
      actorId: req.user?.sub,
      progressId:
        req.params?.id,
      hasReason: Boolean(
        req.body?.reason,
      ),
    },
  );

  try {
    const progressId = (
      req.params?.id || ""
    )
      .toString()
      .trim();
    if (
      !progressId ||
      !mongoose.Types.ObjectId.isValid(
        progressId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_NOT_FOUND,
      });
    }

    const reason =
      normalizeTaskProgressRejectReason(
        req.body?.reason,
      );
    if (!reason) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_REJECT_REASON_REQUIRED,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });
    if (
      !canReviewTaskProgress({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_REVIEW_FORBIDDEN,
      });
    }

    const { progress, plan } =
      await loadTaskProgressInBusinessScope(
        {
          progressId,
          businessId,
        },
      );
    if (!progress || !plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_NOT_FOUND,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      plan.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_REVIEW_FORBIDDEN,
      });
    }

    const rejectedAt = new Date();
    const rejectionNote =
      buildTaskProgressRejectNote({
        reason,
        actorId: actor._id,
        rejectedAt,
      });
    const existingNotes =
      progress.notes
        ?.toString()
        .trim() || "";
    progress.notes =
      existingNotes ?
        `${existingNotes}\n${rejectionNote}`
      : rejectionNote;
    progress.approvedBy = null;
    progress.approvedAt = null;
    await progress.save();

    debug(
      "BUSINESS CONTROLLER: rejectTaskProgress - success",
      {
        actorId: actor._id,
        progressId: progress._id,
        planId: progress.planId,
        taskId: progress.taskId,
        reasonLength: reason.length,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_REJECTED,
      progress,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: rejectTaskProgress - error",
      {
        actorId: req.user?.sub,
        progressId:
          req.params?.id,
        reason: err.message,
        next: "Provide a reject reason and confirm review permissions before retrying",
      },
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/tasks/:id/approve
 * Business owner: approve task assignment.
 */
async function approveProductionTask(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: approveProductionTask - entry",
    {
      actorId: req.user?.sub,
      taskId: req.params?.id,
    },
  );

  try {
    const taskId = req.params?.id
      ?.toString()
      .trim();
    if (!taskId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (
      actor.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_ASSIGN_APPROVAL_REQUIRED,
      });
    }

    const task =
      await ProductionTask.findById(
        taskId,
      );
    if (!task) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: task.planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    task.approvalStatus =
      PRODUCTION_TASK_APPROVAL_APPROVED;
    task.reviewedBy = actor._id;
    task.reviewedAt = new Date();
    task.rejectionReason = "";
    await task.save();

    debug(
      "BUSINESS CONTROLLER: approveProductionTask - success",
      {
        actorId: actor._id,
        taskId: task._id,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_ASSIGN_APPROVED,
      task,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: approveProductionTask - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/production/tasks/:id/reject
 * Business owner: reject task assignment.
 */
async function rejectProductionTask(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: rejectProductionTask - entry",
    {
      actorId: req.user?.sub,
      taskId: req.params?.id,
    },
  );

  try {
    const taskId = req.params?.id
      ?.toString()
      .trim();
    if (!taskId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const rejectionReason =
      req.body?.reason
        ?.toString()
        .trim() || "";

    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    if (
      actor.role !== "business_owner"
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_ASSIGN_REJECT_REQUIRED,
      });
    }

    const task =
      await ProductionTask.findById(
        taskId,
      );
    if (!task) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.TASK_NOT_FOUND,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: task.planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    task.approvalStatus =
      PRODUCTION_TASK_APPROVAL_REJECTED;
    task.reviewedBy = actor._id;
    task.reviewedAt = new Date();
    task.rejectionReason =
      rejectionReason;
    await task.save();

    debug(
      "BUSINESS CONTROLLER: rejectProductionTask - success",
      {
        actorId: actor._id,
        taskId: task._id,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_ASSIGN_REJECTED,
      task,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: rejectProductionTask - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * POST /business/production/outputs
 * Owner + estate manager: record production output.
 */
async function createProductionOutput(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: createProductionOutput - entry",
    {
      actorId: req.user?.sub,
      planId: req.body?.planId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !canCreateProductionPlan({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const planId =
      req.body?.planId
        ?.toString()
        .trim() || "";
    const productId =
      req.body?.productId
        ?.toString()
        .trim() || "";
    const unitType =
      req.body?.unitType
        ?.toString()
        .trim() || "";
    const quantity = Number(
      req.body?.quantity,
    );
    const readyForSale = Boolean(
      req.body?.readyForSale,
    );
    const rawPricePerUnit =
      req.body?.pricePerUnit != null ?
        Number(req.body.pricePerUnit)
      : null;
    // WHY: Normalize invalid prices to null to avoid NaN writes.
    const pricePerUnit =
      Number.isFinite(rawPricePerUnit) ?
        rawPricePerUnit
      : null;

    if (!planId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }
    if (!productId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PRODUCT_REQUIRED,
      });
    }
    if (
      !OUTPUT_UNIT_VALUES.includes(
        unitType,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.INVALID_UNIT_TYPE,
      });
    }
    if (
      !Number.isFinite(quantity) ||
      quantity <= 0
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.OUTPUT_QUANTITY_REQUIRED,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    const product =
      await businessProductService.getProductById(
        {
          businessId,
          id: productId,
        },
      );
    if (!product) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PRODUCT_NOT_FOUND,
      });
    }

    const output =
      await ProductionOutput.create({
        planId: plan._id,
        productId,
        unitType,
        quantity,
        readyForSale,
        pricePerUnit,
      });

    let listingUpdated = false;
    let listingError = null;
    let updatedProduct = null;
    const actorForProductUpdate = {
      id: actor._id,
      role: actor.role,
    };
    if (readyForSale) {
      debug(
        PRODUCTION_OUTPUT_LOG.LISTING_UPDATE_START,
        {
          actorId: actor._id,
          productId,
          outputId: output._id,
        },
      );

      try {
        const currentStock = Number(
          product.stock || 0,
        );
        const nextStock =
          currentStock + quantity;
        const currentReserved =
          Math.max(
            0,
            Number(
              product.preorderReservedQuantity ||
                0,
            ),
          );
        const updates = {
          stock: nextStock,
          isActive: true,
          productionState:
            PRODUCT_STATE_ACTIVE_STOCK,
          preorderEnabled: false,
          preorderStartDate: null,
          preorderCapQuantity: 0,
          preorderReleasedQuantity:
            currentReserved,
          preorderReservedQuantity: 0,
        };
        if (
          Number.isFinite(pricePerUnit)
        ) {
          updates.price = pricePerUnit;
        }

        updatedProduct =
          await businessProductService.updateProduct(
            {
              businessId,
              id: productId,
              updates,
              actor:
                actorForProductUpdate,
            },
          );

        listingUpdated = true;
        debug(
          PRODUCTION_OUTPUT_LOG.LISTING_UPDATE_SUCCESS,
          {
            actorId: actor._id,
            productId,
            outputId: output._id,
            nextStock,
            preorderReleasedQuantity:
              currentReserved,
          },
        );
      } catch (err) {
        listingError = err.message;
        debug(
          PRODUCTION_OUTPUT_LOG.LISTING_UPDATE_ERROR,
          {
            actorId: actor._id,
            productId,
            outputId: output._id,
            reason:
              PRODUCTION_OUTPUT_LISTING_REASON,
            resolution_hint:
              PRODUCTION_OUTPUT_LISTING_HINT,
            error: err.message,
          },
        );
      }
    } else {
      // WHY: Storage outputs keep product inactive until manager explicitly activates stock.
      try {
        updatedProduct =
          await businessProductService.updateProduct(
            {
              businessId,
              id: productId,
              updates: {
                isActive: false,
                productionState:
                  PRODUCT_STATE_IN_STORAGE,
              },
              actor:
                actorForProductUpdate,
            },
          );
        listingUpdated = true;
      } catch (err) {
        listingError = err.message;
        debug(
          PRODUCTION_OUTPUT_LOG.LISTING_UPDATE_ERROR,
          {
            actorId: actor._id,
            productId,
            outputId: output._id,
            reason:
              PRODUCTION_OUTPUT_LISTING_REASON,
            resolution_hint:
              PRODUCTION_OUTPUT_LISTING_HINT,
            error: err.message,
          },
        );
      }
    }

    debug(
      "BUSINESS CONTROLLER: createProductionOutput - success",
      {
        actorId: actor._id,
        outputId: output._id,
      },
    );

    return res.status(201).json({
      message:
        PRODUCTION_COPY.OUTPUT_CREATED,
      output,
      [PRODUCTION_OUTPUT_RESPONSE_KEYS.LISTING_UPDATED]:
        listingUpdated,
      [PRODUCTION_OUTPUT_RESPONSE_KEYS.LISTING_ERROR]:
        listingError,
      [PRODUCTION_OUTPUT_RESPONSE_KEYS.PRODUCT]:
        updatedProduct,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: createProductionOutput - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * GET /business/production/outputs
 * Staff + owner: list production outputs.
 */
async function listProductionOutputs(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listProductionOutputs - entry",
    {
      actorId: req.user?.sub,
      planId: req.query?.planId,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      actor.role === "staff" &&
      !staffProfile
    ) {
      return res.status(403).json({
        error:
          STAFF_COPY.STAFF_PROFILE_REQUIRED,
      });
    }

    const planId =
      req.query?.planId
        ?.toString()
        .trim() || null;

    const filter = {
      planId,
    };
    if (!planId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: planId,
        businessId,
      }).lean();
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      plan.estateAssetId?.toString() !==
        actor.estateAssetId.toString()
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const outputs =
      await ProductionOutput.find(
        filter,
      )
        .sort({ createdAt: -1 })
        .lean();

    debug(
      "BUSINESS CONTROLLER: listProductionOutputs - success",
      {
        actorId: actor._id,
        count: outputs.length,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.OUTPUT_LIST_OK,
      outputs,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listProductionOutputs - error",
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
  generateProductDraftHandler,
  getAllProducts,
  getProductById,
  updateProduct,
  softDeleteProduct,
  restoreProduct,
  uploadProductImage,
  deleteProductImage,
  listStaffProfiles,
  getStaffProfile,
  getStaffCompensation,
  upsertStaffCompensation,
  clockInStaff,
  clockOutStaff,
  listStaffAttendance,
  getStaffCapacity,
  getProductionSchedulePolicy,
  updateProductionSchedulePolicy,
  productionPlanAssistantTurnHandler,
  generateProductionPlanDraftHandler,
  createProductionPlan,
  listProductionPlans,
  listProductionCalendar,
  getProductionPlanDetail,
  updateProductionPlanPreorder,
  reserveProductionPlanPreorder,
  listPreorderReservations,
  releasePreorderReservation,
  confirmPreorderReservation,
  reconcileExpiredPreorderReservationsHandler,
  updateProductionTaskStatus,
  assignProductionTaskStaffProfiles,
  logProductionTaskProgress,
  logProductionTaskProgressBatch,
  approveTaskProgress,
  rejectTaskProgress,
  approveProductionTask,
  rejectProductionTask,
  createProductionOutput,
  listProductionOutputs,
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
