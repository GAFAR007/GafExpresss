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
const staffAttendanceProofService = require("../services/staff_attendance_proof.service");
const {
  uploadTaskProgressProofImages,
} = require("../services/production_task_progress_proof.service");
const {
  SHARED_ACTIVITY_NONE,
  SHARED_ACTIVITY_PLANTED,
  SHARED_ACTIVITY_TRANSPLANTED,
  SHARED_ACTIVITY_HARVESTED,
  normalizeLedgerWorkDate,
  normalizeProductionLedgerActivityType,
  resolveLedgerActivityTargetsFromPlan,
  resolveLedgerActivityUnitsFromPlan,
  resolveLedgerUnitType,
  isTaskProgressCountedInSharedLedger,
  resolveTaskProgressUnitContribution,
  resolveTaskProgressActivityQuantity,
  resolveTaskProgressActivityType,
  recomputeProductionTaskDayLedger,
} = require("../services/production_task_day_ledger.service");
const paymentService = require("../services/payment.service");
const {
  generateProductionPlanDraft,
} = require("../services/production_plan_ai.service");
const {
  extractAiDraftSourceDocumentContext,
  buildProductionDraftImportResponse,
} = require("../services/production_plan_import.service");
const {
  generateProductionPlanDraftV2,
} = require("../services/planner");
const {
  resolveAgricultureCropKey,
  humanizeCropKey,
} = require("../services/planner/agricultureApiClient");
const {
  searchStoredLifecycleProfiles,
  resolveVerifiedAgricultureLifecycle,
} = require("../services/planner/lifecycleResolver");
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
const ProductionTaskDayLedger = require("../models/ProductionTaskDayLedger");
const ProductionOutput = require("../models/ProductionOutput");
const PlanUnit = require("../models/PlanUnit");
const ProductionPhaseUnitCompletion = require("../models/ProductionPhaseUnitCompletion");
const LifecycleDeviationAlert = require("../models/LifecycleDeviationAlert");
const TaskProgress = require("../models/TaskProgress");
const {
  PRODUCTION_QUANTITY_ACTIVITY_TYPES,
} = require("../models/TaskProgress");
const ProductionDeviationGovernanceConfig = require("../models/ProductionDeviationGovernanceConfig");
const ProductionUnitTaskSchedule = require("../models/ProductionUnitTaskSchedule");
const ProductionUnitScheduleWarning = require("../models/ProductionUnitScheduleWarning");
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
  emitDraftPresenceSnapshot,
} = require("../services/production_draft_presence_socket.service");
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
  CONFIDENCE_RECOMPUTE_TRIGGERS,
  CONFIDENCE_ACTIVE_PLAN_STATUSES,
  buildPlanConfidenceFromStoredPlan,
  resolvePlanConfidenceSnapshot,
  recomputePlanConfidenceSnapshot,
  recomputeConfidenceForActivePlans,
  buildPortfolioConfidenceSummary,
} = require("../services/production_confidence.service");
const {
  STAFF_ROLES,
  DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  DEFAULT_PREORDER_CAP_RATIO,
  PREORDER_CAP_RATIO_MIN,
  PREORDER_CAP_RATIO_MAX,
  HUMANE_WORKLOAD_LIMITS,
  PLOT_UNIT_SCALE,
  PRODUCTION_TASK_PROGRESS_DELAY_REASONS,
  normalizeDomainContext,
  isValidDomainContext,
} = require("../utils/production_engine.config");
const {
  PRODUCTION_FEATURE_FLAGS,
} = require("../config/production_feature_flags");
const {
  canSendTenantInvite,
} = require("../config/permissions");

async function emitProductionPlanRoomSnapshot({
  businessId,
  planId,
  context,
}) {
  const normalizedPlanId =
    (planId || "").toString().trim();
  if (!businessId || !normalizedPlanId) {
    return;
  }

  try {
    await emitDraftPresenceSnapshot({
      businessId,
      planId: normalizedPlanId,
    });
  } catch (error) {
    debug(
      "BUSINESS CONTROLLER: production plan room snapshot emit skipped",
      {
        businessId,
        planId: normalizedPlanId,
        context,
        reason: error?.message,
      },
    );
  }
}

const {
  PRODUCTION_TASK_TIMING_MODES,
  PRODUCTION_TASK_TIMING_REFERENCE_EVENTS,
} = ProductionUnitTaskSchedule;
const PERSISTED_PRODUCTION_TASK_TYPES = new Set(
  Array.isArray(
    ProductionTask.PRODUCTION_TASK_TYPES,
  ) && ProductionTask.PRODUCTION_TASK_TYPES.length > 0 ?
    ProductionTask.PRODUCTION_TASK_TYPES
  : ["workload", "recurring", "event"],
);
const {
  PRODUCTION_UNIT_WARNING_TYPES,
  PRODUCTION_UNIT_WARNING_SEVERITIES,
} = ProductionUnitScheduleWarning;
const IMPORTED_PROJECT_DAY_PATTERN =
  /Project day\s+\d+\s+\((\d{4}-\d{2}-\d{2})\)\./i;

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
const STAFF_ROLE_SHAREHOLDER =
  "shareholder";
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
  INCLUDES_HOUSING: "includesHousing",
  INCLUDES_FEEDING: "includesFeeding",
  PAYOUT_TRIGGER: "payoutTrigger",
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
  PLAN_DRAFT_SAVED:
    "Production draft saved successfully",
  PLAN_DRAFT_UPDATED:
    "Production draft updated successfully",
  PLAN_DRAFT_OK:
    "Production plan draft generated successfully",
  PLAN_ASSISTANT_TURN_OK:
    "Production plan assistant response generated successfully",
  PLAN_ASSISTANT_CROP_SEARCH_OK:
    "Production crop search results generated successfully",
  PLAN_LIST_OK:
    "Production plans fetched successfully",
  PLAN_DETAIL_OK:
    "Production plan fetched successfully",
  PLAN_STATUS_REQUIRED:
    "Production plan status is required",
  PLAN_STATUS_INVALID:
    "Production plan status is invalid",
  PLAN_STATUS_TRANSITION_INVALID:
    "Production plan status change is not allowed",
  PLAN_STATUS_UPDATED:
    "Production plan status updated successfully",
  PLAN_RETURN_DRAFT_PROGRESS_LOCKED:
    "This production plan already has execution logs or output records. Save a draft copy instead.",
  PLAN_DELETED:
    "Production plan deleted successfully",
  PLAN_DELETE_DRAFT_ONLY:
    "Only draft or archived production plans can be deleted",
  PLAN_UPDATE_DRAFT_ONLY:
    "Only draft production plans can be updated from the draft editor",
  PLAN_ARCHIVE_PREORDER_ENABLED:
    "Disable pre-order before archiving this production plan",
  PLAN_UNITS_LIST_OK:
    "Production plan units fetched successfully",
  DEVIATION_ALERTS_LIST_OK:
    "Deviation alerts fetched successfully",
  DEVIATION_ALERT_NOT_FOUND:
    "Deviation alert not found",
  DEVIATION_GOVERNANCE_DISABLED:
    "Deviation governance is disabled",
  DEVIATION_GOVERNANCE_FORBIDDEN:
    "You do not have permission to manage deviation governance",
  DEVIATION_VARIANCE_ACCEPTED:
    "Variance accepted and unit unlocked",
  DEVIATION_REPLAN_APPLIED:
    "Unit re-plan applied and governance alert resolved",
  DEVIATION_REPLAN_TASKS_REQUIRED:
    "taskAdjustments is required to re-plan a deviation-locked unit",
  DEVIATION_REPLAN_TASKS_INVALID:
    "taskAdjustments entries must include valid taskId, startDate, and dueDate values",
  CONFIDENCE_DISABLED:
    "Confidence scoring is disabled",
  CONFIDENCE_FORBIDDEN:
    "You do not have permission to view confidence scores",
  CONFIDENCE_PLAN_OK:
    "Plan confidence fetched successfully",
  CONFIDENCE_PORTFOLIO_OK:
    "Portfolio confidence fetched successfully",
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
  TASK_SCHEDULE_INVALID:
    "Pinned task dates must include valid startDate and dueDate values, and dueDate must be after startDate",
  TASK_SCHEDULE_OUTSIDE_PLAN:
    "Pinned task dates must stay within the plan schedule window",
  TASK_NOT_FOUND:
    "Production task not found",
  TASK_STATUS_REQUIRED:
    "Task status is required",
  OUTPUT_CREATED:
    "Production output created successfully",
  OUTPUT_LIST_OK:
    "Production outputs fetched successfully",
  PLANTING_TARGETS_REQUIRED:
    "Farm production needs planting targets before the draft or plan can be created.",
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
    "Actual amount is required",
  TASK_PROGRESS_ACTUAL_INVALID:
    "Actual amount must be a valid non-negative number",
  TASK_PROGRESS_TARGET_EXCEEDED:
    "Actual progress exceeds the remaining planned task target",
  TASK_PROGRESS_ACTIVITY_QUANTITY_INVALID:
    "Activity quantity must be a valid non-negative number",
  TASK_PROGRESS_ACTIVITY_TARGET_EXCEEDED:
    "Activity quantity exceeds the remaining shared activity target",
  TASK_PROGRESS_PROOFS_REQUIRED:
    "Upload proof images before logging progress",
  TASK_PROGRESS_PROOFS_COUNT_INVALID:
    "Upload exactly the required number of proof images",
  TASK_PROGRESS_PROOFS_NOT_ALLOWED_FOR_ZERO_PROGRESS:
    "Proof images are not allowed when actual amount is zero",
  TASK_PROGRESS_DELAY_REASON_INVALID:
    "Delay reason is invalid",
  TASK_PROGRESS_ZERO_DELAY_REASON_REQUIRED:
    "Delay reason is required when actual amount is zero",
  TASK_PROGRESS_ATTENDANCE_REQUIRED:
    "Clock in and clock out before logging progress",
  TASK_PROGRESS_STAFF_ID_INVALID:
    "Staff id is invalid",
  TASK_PROGRESS_STAFF_REQUIRED_FOR_MULTI_ASSIGN:
    "staffId is required when multiple farmers are assigned",
  TASK_PROGRESS_STAFF_NOT_ASSIGNED:
    "staffId is not assigned to this task",
  TASK_PROGRESS_STAFF_SCOPE_INVALID:
    "staffId must belong to the same business and estate",
  TASK_PROGRESS_UNIT_ID_INVALID:
    "unitId is invalid",
  TASK_PROGRESS_UNIT_REQUIRED_FOR_MULTI_ASSIGN:
    "unitId is required when a task has multiple assigned units",
  TASK_PROGRESS_UNIT_NOT_ASSIGNED:
    "unitId is not assigned to this task",
  TASK_PROGRESS_UNIT_SCOPE_INVALID:
    "unitId must belong to the same production plan",
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

// WHY: Stage 0 lifecycle logs make production flow diagnostics consistent across creation/draft/completion paths.
const PRODUCTION_LIFECYCLE_LOG =
  "BUSINESS CONTROLLER: productionLifecycleBoundary";

function logProductionLifecycleBoundary({
  operation,
  stage,
  intent,
  actorId,
  businessId,
  context = {},
}) {
  debug(PRODUCTION_LIFECYCLE_LOG, {
    operation:
      operation || "unknown_operation",
    stage: stage || "unknown_stage",
    intent: intent || "unspecified",
    actorId: actorId || null,
    businessId:
      (
        businessId &&
        typeof businessId.toString ===
          "function"
      ) ?
        businessId.toString()
      : businessId || null,
    featureFlags:
      PRODUCTION_FEATURE_FLAGS,
    ...context,
  });
}

// WHY: Keep production status values centralized.
const PRODUCTION_STATUS_DRAFT = "draft";
const PRODUCTION_STATUS_ACTIVE =
  "active";
const PRODUCTION_STATUS_PAUSED =
  "paused";
const PRODUCTION_STATUS_COMPLETED =
  "completed";
const PRODUCTION_STATUS_ARCHIVED =
  "archived";
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
const PRODUCTION_SAVE_MODE_DRAFT =
  "draft";
const DEFAULT_TASK_TITLE = "Task";
const DEFAULT_PHASE_NAME_PREFIX =
  "Phase";
const MS_PER_MINUTE = 60000;
const MS_PER_DAY = 86400000;
const MS_PER_HOUR = 60 * MS_PER_MINUTE;
// WHY: Scheduling policy defaults are used when business/estate policy is missing.
const WORK_SCHEDULE_FALLBACK_WEEK_DAYS =
  [1, 2, 3, 4, 5, 6, 7];
const WORK_SCHEDULE_FALLBACK_BLOCKS = [
  { start: "09:00", end: "13:00" },
  { start: "14:00", end: "17:00" },
];
const WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES = 30;
const WORK_SCHEDULE_MIN_SLOT_MINUTES = 15;
const WORK_SCHEDULE_MAX_SLOT_MINUTES = 240;
const WORK_SCHEDULE_FALLBACK_TIMEZONE =
  "UTC";
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
const PRODUCTION_ASSISTANT_REQUIRED_FIELDS =
  [
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
const ASSISTANT_FALLBACK_TASK_TEMPLATES =
  [
    "Field preparation and safety check",
    "Soil and moisture monitoring",
    "Planting and stand count",
    "Irrigation and nutrient application",
    "Weed and pest management",
    "Growth and quality inspection",
    "Harvest-readiness review",
  ];
const ASSISTANT_SPARSE_TOP_UP_TEMPLATES =
  [
    "Soil preparation and field execution",
    "Planting and stand-count follow-up",
    "Irrigation and nutrient application",
    "Weed and pest management sweep",
    "Growth and harvest-readiness check",
  ];
const ASSISTANT_SPARSE_TOP_UP_MIN_TARGET_TASKS = 6;
const ASSISTANT_SPARSE_TOP_UP_MAX_TARGET_TASKS = 60;
const ASSISTANT_WARNING_CODE_ENVELOPE_LOOSE_RECOVERY =
  "ENVELOPE_LOOSE_RECOVERY";
const ASSISTANT_SPARSE_RECOVERY_FALLBACK_COVERAGE_RATIO = 0.6;
const PRODUCTION_PHASE_TYPE_FINITE =
  "finite";
const PRODUCTION_PHASE_TYPE_MONITORING =
  "monitoring";
const PHASE_GATE_WARNING_CODE_LOCKED =
  "phase_locked_unit_budget_exhausted";
const PHASE_GATE_WARNING_CODE_CAPPED =
  "draft_capped_remaining_units";
const PHASE_GATE_WARNING_LOCKED_MESSAGE =
  "Phase locked - unit budget exhausted";
const PHASE_GATE_WARNING_CAPPED_MESSAGE =
  "Draft capped to remaining units";
// WHY: Finite operational phases should complete from real throughput, not be stretched to fill empty calendar months.
const FINITE_PHASE_MIN_PLOTS_PER_FARMER_PER_DAY = 0.5;
// WHY: Stage 1 throughput defaults ensure finite-day calculations stay deterministic when AI omits optional phase rates.
const DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR = 0.1;
const DEFAULT_PHASE_TARGET_RATE_PER_FARMER_HOUR = 0.2;
const DEFAULT_PHASE_PLANNED_HOURS_PER_DAY = 3;
const DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS = 0;
const FINITE_PHASE_DURATION_WARNING_CODE =
  "finite_phase_duration_recalculated";
const FINITE_PHASE_DURATION_WARNING_MESSAGE =
  "Finite phase duration was recalculated from workload throughput so execution can finish without timeline padding.";
const PHASE_BIOLOGICAL_WINDOW_WARNING_CODE =
  "phase_window_extended_for_biological_min_days";
const PHASE_BIOLOGICAL_WINDOW_WARNING_MESSAGE =
  "Phase window was extended to respect biological minimum days while keeping finite execution duration intact.";

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
const PRODUCT_STATE_PLANNED =
  "planned";
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
const TASK_PROGRESS_DELAY_LATE = "late";
const TASK_PROGRESS_APPROVAL_PENDING =
  "pending_approval";
const TASK_PROGRESS_APPROVAL_APPROVED =
  "approved";
const TASK_PROGRESS_APPROVAL_NEEDS_REVIEW =
  "needs_review";
const PRODUCTION_QUANTITY_ACTIVITY_NONE =
  SHARED_ACTIVITY_NONE;
const PRODUCTION_QUANTITY_ACTIVITY_PLANTING =
  SHARED_ACTIVITY_PLANTED;
const PRODUCTION_QUANTITY_ACTIVITY_TRANSPLANT =
  SHARED_ACTIVITY_TRANSPLANTED;
const PRODUCTION_QUANTITY_ACTIVITY_HARVEST =
  SHARED_ACTIVITY_HARVESTED;
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
const TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_ID_INVALID =
  "UNIT_ID_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_ID_REQUIRED =
  "UNIT_ID_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_NOT_ASSIGNED =
  "UNIT_NOT_ASSIGNED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_SCOPE_INVALID =
  "UNIT_SCOPE_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_NOT_ASSIGNED =
  "STAFF_NOT_ASSIGNED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_STAFF_SCOPE_INVALID =
  "STAFF_SCOPE_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_REQUIRED =
  "ACTUAL_PLOTS_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_INVALID =
  "ACTUAL_PLOTS_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_TARGET_EXCEEDED =
  "TARGET_EXCEEDED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_DELAY_REASON_INVALID =
  "DELAY_REASON_INVALID";
const TASK_PROGRESS_BATCH_ENTRY_CODE_ZERO_DELAY_REQUIRED =
  "ZERO_OUTPUT_DELAY_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_ATTENDANCE_REQUIRED =
  "ATTENDANCE_REQUIRED";
const TASK_PROGRESS_BATCH_ENTRY_CODE_FORBIDDEN =
  "FORBIDDEN";
const TASK_PROGRESS_BATCH_ENTRY_CODE_UNKNOWN =
  "UNKNOWN_ERROR";
const PRODUCTION_TASK_TIMING_MODE_ABSOLUTE =
  PRODUCTION_TASK_TIMING_MODES[0] ||
  "absolute";
const PRODUCTION_TASK_TIMING_MODE_RELATIVE =
  PRODUCTION_TASK_TIMING_MODES[1] ||
  "relative";
const PRODUCTION_TASK_TIMING_REFERENCE_EVENT_PHASE_START =
  PRODUCTION_TASK_TIMING_REFERENCE_EVENTS[0] ||
  "phase_start";
const PRODUCTION_TASK_TIMING_REFERENCE_EVENT_PHASE_COMPLETION =
  PRODUCTION_TASK_TIMING_REFERENCE_EVENTS[1] ||
  "phase_completion";
const PRODUCTION_UNIT_WARNING_TYPE_MISSING_CONTEXT =
  PRODUCTION_UNIT_WARNING_TYPES[0] ||
  "MISSING_UNIT_CONTEXT";
const PRODUCTION_UNIT_WARNING_TYPE_SHIFT_CONFLICT =
  PRODUCTION_UNIT_WARNING_TYPES[1] ||
  "SHIFT_CONFLICT";
const PRODUCTION_UNIT_WARNING_SEVERITY_WARNING =
  PRODUCTION_UNIT_WARNING_SEVERITIES[1] ||
  "warning";
const UNIT_DELAY_FALLBACK_SHIFT_DAYS = 1;
const UNIT_MANUAL_REPLAN_SHIFT_REASON =
  "manager_replan";
const DEVIATION_DEFAULT_THRESHOLD_DAYS = 3;
const DEVIATION_ALERT_STATUS_OPEN =
  "open";
const DEVIATION_ALERT_ACTION_TRIGGERED =
  "triggered";
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

// WHY: Shareholders should behave like business owners for business access.
function isBusinessOwnerEquivalentActor(actor) {
  if (actor?.role === "business_owner") {
    return true;
  }

  return (
    actor?.role === "staff" &&
    normalizeDraftAccessStaffRole(
      actor?.staffRole,
    ) === STAFF_ROLE_SHAREHOLDER
  );
}

// WHY: Only estate managers can manage staff visibility (besides owners).
function canManageStaffDirectory({
  actorRole,
  staffRole,
}) {
  if (
    actorRole === "business_owner" ||
    staffRole === STAFF_ROLE_SHAREHOLDER
  ) {
    return true;
  }

  return (
    actorRole === "staff" &&
    (
      staffRole === STAFF_ROLE_ESTATE_MANAGER ||
      staffRole === STAFF_ROLE_FARM_MANAGER ||
      staffRole === STAFF_ROLE_ASSET_MANAGER
    )
  );
}

// WHY: Staff compensation is limited to owners + estate managers.
function canManageStaffCompensation({
  actorRole,
  staffRole,
}) {
  if (
    actorRole === "business_owner" ||
    staffRole === STAFF_ROLE_SHAREHOLDER
  ) {
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
  if (
    actorRole === "business_owner" ||
    staffRole === STAFF_ROLE_SHAREHOLDER
  ) {
    return true;
  }

  return (
    actorRole === "staff" &&
    (staffRole ===
      STAFF_ROLE_ESTATE_MANAGER ||
      staffRole ===
        STAFF_ROLE_FARM_MANAGER)
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
        STAFF_ROLE_FARM_MANAGER ||
      staffRole ===
        STAFF_ROLE_ACCOUNTANT)
  );
}

// WHY: Production plans are managed by owners and estate managers.
function canCreateProductionPlan({
  actorRole,
  staffRole,
}) {
  if (
    actorRole === "business_owner" ||
    staffRole === STAFF_ROLE_SHAREHOLDER
  ) {
    return true;
  }

  return (
    actorRole === "staff" &&
    staffRole ===
      STAFF_ROLE_ESTATE_MANAGER
  );
}

// WHY: Plan lifecycle controls match plan creation authority.
function canManageProductionPlanLifecycle({
  actorRole,
  staffRole,
}) {
  return canCreateProductionPlan({
    actorRole,
    staffRole,
  });
}

function normalizeDraftAccessStaffRole(
  staffRole,
) {
  return (staffRole || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[-\s]+/g, "_");
}

function canEditProductionPlanDraft({
  actorRole,
  staffRole,
}) {
  if (
    actorRole === "business_owner" ||
    normalizeDraftAccessStaffRole(staffRole) ===
      STAFF_ROLE_SHAREHOLDER
  ) {
    return true;
  }

  const normalizedStaffRole =
    normalizeDraftAccessStaffRole(
      staffRole,
    );

  return (
    actorRole === "staff" &&
    (
      normalizedStaffRole ===
        STAFF_ROLE_ESTATE_MANAGER ||
      normalizedStaffRole ===
        STAFF_ROLE_FARM_MANAGER ||
      normalizedStaffRole ===
        STAFF_ROLE_ASSET_MANAGER
    )
  );
}

// WHY: Draft-planning tools should follow draft edit access, not lifecycle control.
function canUseProductionPlanDraftTools({
  actorRole,
  staffRole,
}) {
  return canEditProductionPlanDraft({
    actorRole,
    staffRole,
  });
}

// WHY: Task assignments can be initiated by designated managers.
function canAssignProductionTasks({
  actorRole,
  staffRole,
}) {
  if (
    actorRole === "business_owner" ||
    staffRole === STAFF_ROLE_SHAREHOLDER
  ) {
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

function canLogProductionTaskProgress({
  actorRole,
  staffRole,
}) {
  if (
    actorRole === "business_owner" ||
    staffRole === STAFF_ROLE_SHAREHOLDER
  ) {
    return true;
  }

  return (
    actorRole === "staff" &&
    Boolean(
      (staffRole || "")
        .toString()
        .trim(),
    )
  );
}

// WHY: Farm asset approvals are limited to operational managers and owners.
function canApproveFarmAssetWorkflow({
  actorRole,
  staffRole,
}) {
  if (
    actorRole === "business_owner" ||
    staffRole === STAFF_ROLE_SHAREHOLDER
  ) {
    return true;
  }

  return (
    actorRole === "staff" &&
    (
      staffRole === STAFF_ROLE_ESTATE_MANAGER ||
      staffRole === STAFF_ROLE_FARM_MANAGER ||
      staffRole === STAFF_ROLE_ASSET_MANAGER
    )
  );
}

function canTransitionProductionPlanStatus(
  currentStatus,
  nextStatus,
) {
  if (currentStatus === nextStatus) {
    return true;
  }

  switch (currentStatus) {
    case PRODUCTION_STATUS_DRAFT:
      return (
        nextStatus ===
          PRODUCTION_STATUS_ACTIVE ||
        nextStatus ===
          PRODUCTION_STATUS_ARCHIVED
      );
    case PRODUCTION_STATUS_ACTIVE:
      return (
        nextStatus ===
          PRODUCTION_STATUS_DRAFT ||
        nextStatus ===
          PRODUCTION_STATUS_PAUSED ||
        nextStatus ===
          PRODUCTION_STATUS_COMPLETED ||
        nextStatus ===
          PRODUCTION_STATUS_ARCHIVED
      );
    case PRODUCTION_STATUS_PAUSED:
      return (
        nextStatus ===
          PRODUCTION_STATUS_DRAFT ||
        nextStatus ===
          PRODUCTION_STATUS_ACTIVE ||
        nextStatus ===
          PRODUCTION_STATUS_COMPLETED ||
        nextStatus ===
          PRODUCTION_STATUS_ARCHIVED
      );
    case PRODUCTION_STATUS_COMPLETED:
      return (
        nextStatus ===
        PRODUCTION_STATUS_ARCHIVED
      );
    case PRODUCTION_STATUS_ARCHIVED:
      return (
        nextStatus ===
          PRODUCTION_STATUS_DRAFT ||
        nextStatus ===
          PRODUCTION_STATUS_ACTIVE ||
        nextStatus ===
          PRODUCTION_STATUS_PAUSED ||
        nextStatus ===
          PRODUCTION_STATUS_COMPLETED
      );
    default:
      return false;
  }
}

function buildDetachedProductLifecycleUpdates(
  product,
) {
  const normalizedState = (
    product?.productionState || ""
  )
    .toString()
    .trim();
  const stockQuantity = Math.max(
    0,
    Number(product?.stock || 0),
  );
  const nextState =
    normalizedState ===
      PRODUCT_STATE_IN_STORAGE ||
    normalizedState ===
      PRODUCT_STATE_ACTIVE_STOCK ?
      normalizedState
    : stockQuantity > 0 ?
      PRODUCT_STATE_ACTIVE_STOCK
    : PRODUCT_STATE_PLANNED;

  return {
    productionPlanId: null,
    preorderEnabled: false,
    preorderStartDate: null,
    preorderCapQuantity: 0,
    preorderReservedQuantity: 0,
    conservativeYieldQuantity: null,
    conservativeYieldUnit: "",
    isActive:
      nextState ===
      PRODUCT_STATE_ACTIVE_STOCK,
    productionState: nextState,
  };
}

async function syncProductForPlanLifecycle({
  businessId,
  actor,
  plan,
  targetStatus,
}) {
  const product =
    await businessProductService.getProductById(
      {
        businessId,
        id: plan.productId,
      },
    );
  if (!product) {
    return null;
  }

  const updates = {};
  const linkedPlanId =
    product?.productionPlanId
      ?.toString?.() || "";
  const planId =
    plan?._id?.toString?.() || "";

  if (
    targetStatus ===
    PRODUCTION_STATUS_ACTIVE
  ) {
    if (linkedPlanId !== planId) {
      updates.productionPlanId =
        plan._id;
    }
    if (
      product.preorderEnabled !== true &&
      (
        !product.productionState ||
        product.productionState ===
          PRODUCT_STATE_PLANNED
      )
    ) {
      updates.productionState =
        PRODUCT_STATE_IN_PRODUCTION;
      updates.isActive = false;
    }
  }

  if (
    (
      targetStatus ===
        PRODUCTION_STATUS_ARCHIVED ||
      targetStatus ===
        PRODUCTION_STATUS_DRAFT
    ) &&
    linkedPlanId === planId
  ) {
    if (product.preorderEnabled) {
      throw new Error(
        PRODUCTION_COPY.PLAN_ARCHIVE_PREORDER_ENABLED,
      );
    }
    Object.assign(
      updates,
      buildDetachedProductLifecycleUpdates(
        product,
      ),
    );
  }

  if (
    Object.keys(updates).length === 0
  ) {
    return product;
  }

  return businessProductService.updateProduct(
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
}

async function buildBusinessAssetActor({
  actor,
  businessId,
}) {
  const staffProfile =
    await getStaffProfileForActor({
      actor,
      businessId,
      allowMissing: true,
    });

  return {
    id: actor._id,
    role: actor.role,
    name:
      actor.name ||
      [
        actor.firstName,
        actor.lastName,
      ]
        .filter(Boolean)
        .join(" ")
        .trim(),
    email: actor.email || "",
    staffRole: staffProfile?.staffRole || "",
  };
}

async function detachProductFromDeletedDraft({
  businessId,
  actor,
  plan,
}) {
  const product =
    await businessProductService.getProductById(
      {
        businessId,
        id: plan.productId,
      },
    );
  if (!product) {
    return null;
  }

  if (
    product?.productionPlanId
      ?.toString?.() !==
    plan?._id?.toString?.()
  ) {
    return product;
  }

  return businessProductService.updateProduct(
    {
      businessId,
      id: product._id,
      actor: {
        id: actor._id,
        role: actor.role,
      },
      updates:
        buildDetachedProductLifecycleUpdates(
          product,
        ),
    },
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
    (
      staffRole ===
        STAFF_ROLE_ESTATE_MANAGER ||
      staffRole ===
        STAFF_ROLE_FARM_MANAGER ||
      staffRole ===
        STAFF_ROLE_ASSET_MANAGER
    )
  );
}

// CONFIDENCE-SCORE
// WHY: Confidence visibility is restricted to owner + operational manager roles.
function canViewConfidenceScores({
  actorRole,
  staffRole,
}) {
  return canAssignProductionTasks({
    actorRole,
    staffRole,
  });
}

const PLAN_CONFIDENCE_PRIVATE_FIELDS = [
  "baselineConfidenceScore",
  "currentConfidenceScore",
  "baselineConfidenceBreakdown",
  "currentConfidenceBreakdown",
  "confidenceScoreDelta",
  "confidenceLastTrigger",
  "confidenceLastComputedAt",
  "confidenceLastComputedBy",
  "confidenceRecomputeCount",
];

// CONFIDENCE-SCORE
// WHY: Non-manager responses must never leak plan-level confidence internals.
function stripPlanConfidenceFields(
  plan,
) {
  if (
    !plan ||
    typeof plan !== "object"
  ) {
    return plan;
  }
  const sanitized = { ...plan };
  PLAN_CONFIDENCE_PRIVATE_FIELDS.forEach(
    (field) => {
      delete sanitized[field];
    },
  );
  return sanitized;
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
function normalizeInclusiveRangeEnd(
  value,
) {
  if (!(value instanceof Date)) {
    return value;
  }
  if (!isStartOfDayTimestamp(value)) {
    return value;
  }
  return new Date(
    value.getTime() + MS_PER_DAY - 1,
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
    value == null ? "" : (
      value.toString().trim()
    );
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
    value == null ? "" : (
      value.toString().trim()
    );
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
    blocks:
      WORK_SCHEDULE_FALLBACK_BLOCKS.map(
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
    Array.isArray(value) ? value : [];
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
  return Array.from(
    new Set(normalized),
  ).sort((left, right) => left - right);
}

// WHY: Block normalization ensures deterministic ordering for scheduling.
function normalizeWorkBlocksInput(
  value,
  fallbackBlocks = WORK_SCHEDULE_FALLBACK_BLOCKS,
) {
  const values =
    Array.isArray(value) ? value : [];
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
    return fallbackBlocks.map(
      (block) => ({
        ...block,
      }),
    );
  }

  return normalized.sort(
    (left, right) => {
      const parsedLeft =
        parseTimeBlockClock(left.start);
      const parsedRight =
        parseTimeBlockClock(
          right.start,
        );
      return (
        (parsedLeft?.totalMinutes ||
          0) -
        (parsedRight?.totalMinutes || 0)
      );
    },
  );
}

// WHY: Policy normalization keeps reads resilient while preserving safe defaults.
function normalizeSchedulePolicyInput(
  rawPolicy,
  fallbackPolicy = buildDefaultSchedulePolicy(),
) {
  const source =
    (
      rawPolicy &&
      typeof rawPolicy === "object"
    ) ?
      rawPolicy
    : {};

  const fallbackMinSlotMinutes =
    (
      Number.isFinite(
        Number(
          fallbackPolicy?.minSlotMinutes,
        ),
      )
    ) ?
      Number(
        fallbackPolicy.minSlotMinutes,
      )
    : WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES;

  const parsedSlotMinutes = Number(
    source.minSlotMinutes,
  );
  const minSlotMinutes =
    (
      Number.isFinite(
        parsedSlotMinutes,
      ) &&
      parsedSlotMinutes >=
        WORK_SCHEDULE_MIN_SLOT_MINUTES &&
      parsedSlotMinutes <=
        WORK_SCHEDULE_MAX_SLOT_MINUTES
    ) ?
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
    (
      payload?.policy &&
      typeof payload.policy === "object"
    ) ?
      payload.policy
    : (
      payload &&
      typeof payload === "object"
    ) ?
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
    if (
      nextPolicy.blocks.length === 0
    ) {
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

  const parsedBlocks =
    nextPolicy.blocks.map((block) => ({
      ...block,
      startParsed: parseTimeBlockClock(
        block.start,
      ),
      endParsed: parseTimeBlockClock(
        block.end,
      ),
    }));

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
    const prevBlock =
      parsedBlocks[index - 1];
    const nextBlock =
      parsedBlocks[index];
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

function formatWorkBlocksLabel(blocks) {
  const normalizedBlocks =
    Array.isArray(blocks) ? blocks : [];
  if (normalizedBlocks.length === 0) {
    return "none";
  }
  return normalizedBlocks
    .map(
      (block) =>
        `${block.start}-${block.end}`,
    )
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
        const entry = roles[role] || {};
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
    startDate: normalizedStart
      .toISOString()
      .slice(0, 10),
    endDate: normalizedEnd
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
    value?.toString().trim() ||
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
  const compactTitle = withoutLooseWeek
    .replace(/\s{2,}/g, " ")
    .replace(/\(\s*\)/g, "")
    .trim();
  return (
    compactTitle || DEFAULT_TASK_TITLE
  );
}

function normalizeDraftTaskShape(task) {
  const assignedStaffProfileIds =
    Array.from(
      new Set([
        ...((
          Array.isArray(
            task?.assignedStaffProfileIds,
          )
        ) ?
          task.assignedStaffProfileIds
        : []),
        ...((
          Array.isArray(
            task?.assignedStaffIds,
          )
        ) ?
          task.assignedStaffIds
        : []),
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
    assignedStaffProfileIds[0] || "";
  const normalizedWeight =
    (
      Number.isFinite(
        Number(task?.weight),
      )
    ) ?
      Math.max(
        1,
        Math.floor(Number(task.weight)),
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
    const role = normalizeStaffIdInput(
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
      if (
        requiredHeadcount > available
      ) {
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
function parseDomainContextInput(
  value,
) {
  const raw =
    value == null ? "" : (
      value.toString().trim()
    );
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
  const isValid =
    isValidDomainContext(raw);

  return {
    value: normalizedValue,
    provided: true,
    isValid,
    wasNormalized:
      normalizedRaw !== normalizedValue,
    raw,
  };
}

// WHY: Numeric parsing helper keeps validation logic consistent across endpoints.
function parsePositiveNumberInput(
  value,
) {
  if (value == null || value === "") {
    return null;
  }
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    return null;
  }
  return parsed;
}

function normalizePlantingMaterialTypeInput(
  value,
) {
  const raw =
    value == null ? "" : (
      value.toString().trim()
    );
  if (!raw) {
    return "";
  }
  const normalized = raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  switch (normalized) {
    case "seeds":
      return "seed";
    case "seedlings":
      return "seedling";
    case "roots":
      return "root";
    case "stems":
    case "stem_cutting":
    case "stem_cuttings":
      return "stem";
    case "cuttings":
      return "cutting";
    case "tubers":
      return "tuber";
    case "suckers":
      return "sucker";
    case "runners":
      return "runner";
    default:
      return normalized;
  }
}

function normalizePlantingTargetsInput(
  value,
) {
  const source =
    (
      value &&
      typeof value === "object"
    ) ?
      value
    : {};
  return {
    materialType:
      normalizePlantingMaterialTypeInput(
        source.materialType ||
          source.plantingMaterialType,
      ),
    plannedPlantingQuantity:
      parsePositiveNumberInput(
        source.plannedPlantingQuantity ||
          source.plantingQuantity,
      ),
    plannedPlantingUnit:
      normalizePlantingTargetUnitInput(
        source.plannedPlantingUnit ||
          source.plantingUnit ||
          source.plantingQuantityUnit ||
          source.plannedPlantingMeasureUnit,
      ),
    estimatedHarvestQuantity:
      parsePositiveNumberInput(
        source.estimatedHarvestQuantity ||
          source.harvestQuantity,
      ),
    estimatedHarvestUnit:
      normalizePlantingTargetUnitInput(
        source.estimatedHarvestUnit ||
          source.harvestUnit,
      ),
  };
}

function normalizePlantingTargetUnitInput(
  value,
) {
  const normalized =
    (value || "")
      .toString()
      .trim()
      .toLowerCase();
  switch (normalized) {
    case "kgs":
      return "kg";
    case "gram":
    case "grams":
      return "g";
    case "t":
    case "tons":
    case "tonne":
    case "tonnes":
      return "ton";
    case "bags":
      return "bag";
    case "sacks":
      return "sack";
    case "crates":
      return "crate";
    case "cartons":
      return "carton";
    case "baskets":
      return "basket";
    case "boxes":
      return "box";
    case "buckets":
      return "bucket";
    case "bunches":
      return "bunch";
    case "bundles":
      return "bundle";
    case "trays":
      return "tray";
    case "seeds":
      return "seed";
    case "seedlings":
      return "seedling";
    case "stands":
      return "stand";
    case "pieces":
      return "piece";
    case "plants":
      return "plant";
    default:
      return normalized;
  }
}

function parseNonNegativeNumberInput(
  value,
) {
  if (value == null || value === "") {
    return 0;
  }
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    return null;
  }
  return parsed;
}

function parseNonNegativeIntegerInput(
  value,
) {
  const parsed =
    parseNonNegativeNumberInput(value);
  if (
    parsed == null ||
    !Number.isFinite(parsed)
  ) {
    return null;
  }
  return Math.max(
    0,
    Math.floor(parsed),
  );
}

function normalizeProductionQuantityActivityType(
  value,
) {
  return normalizeProductionLedgerActivityType(
    value,
  );
}

function resolveFarmQuantityTrackingConfig({
  plan,
  activityType,
}) {
  const plantingTargets =
    normalizePlantingTargetsInput(
      plan?.plantingTargets,
    );
  if (
    plan?.domainContext !== "farm" ||
    !hasValidPlantingTargets({
      plantingTargets,
    })
  ) {
    return null;
  }

  switch (activityType) {
    case PRODUCTION_QUANTITY_ACTIVITY_PLANTING:
    case PRODUCTION_QUANTITY_ACTIVITY_TRANSPLANT:
      return {
        activityType,
        targetQuantity:
          plantingTargets.plannedPlantingQuantity,
        unit:
          plantingTargets.plannedPlantingUnit,
      };
    case PRODUCTION_QUANTITY_ACTIVITY_HARVEST:
      return {
        activityType,
        targetQuantity:
          plantingTargets.estimatedHarvestQuantity,
        unit:
          plantingTargets.estimatedHarvestUnit,
      };
    default:
      return null;
  }
}

function hasCompletePlantingTargets(
  plantingTargets,
) {
  return Boolean(
    plantingTargets?.materialType &&
      plantingTargets?.plannedPlantingUnit &&
      plantingTargets?.estimatedHarvestUnit &&
      Number(
        plantingTargets?.plannedPlantingQuantity,
      ) > 0 &&
      Number(
        plantingTargets?.estimatedHarvestQuantity,
      ) > 0,
  );
}

function buildPlantingTargetsValidationDetails(
  plantingTargets,
) {
  const missing = [];
  if (!plantingTargets?.materialType) {
    missing.push(
      "plantingTargets.materialType",
    );
  }
  if (
    !Number(
      plantingTargets?.plannedPlantingQuantity,
    )
  ) {
    missing.push(
      "plantingTargets.plannedPlantingQuantity",
    );
  }
  if (
    !plantingTargets?.plannedPlantingUnit
  ) {
    missing.push(
      "plantingTargets.plannedPlantingUnit",
    );
  }
  if (
    !Number(
      plantingTargets?.estimatedHarvestQuantity,
    )
  ) {
    missing.push(
      "plantingTargets.estimatedHarvestQuantity",
    );
  }
  if (
    !plantingTargets?.estimatedHarvestUnit
  ) {
    missing.push(
      "plantingTargets.estimatedHarvestUnit",
    );
  }
  return {
    missing,
    invalid: [],
  };
}

function buildPlantingTargetsPrompt(
  plantingTargets,
) {
  if (
    !hasCompletePlantingTargets(
      plantingTargets,
    )
  ) {
    return "";
  }
  return `Planting targets: material ${plantingTargets.materialType}; plan ${plantingTargets.plannedPlantingQuantity} ${plantingTargets.plannedPlantingUnit} for establishment; estimate harvest at ${plantingTargets.estimatedHarvestQuantity} ${plantingTargets.estimatedHarvestUnit}. Use these numbers as the yield baseline for planting, establishment, and harvest planning.`;
}

function normalizeDraftRefineTargetInput(
  value,
) {
  const source =
    (
      value &&
      typeof value === "object" &&
      !Array.isArray(value)
    ) ?
      value
    : {};
  const phaseTargets =
    Array.isArray(source.phaseTargets) ?
      source.phaseTargets
        .map((entry) => {
          const row =
            (
              entry &&
              typeof entry === "object" &&
              !Array.isArray(entry)
            ) ?
              entry
            : {};
          return {
            phaseName:
              (
                row.phaseName || ""
              )
                .toString()
                .trim(),
            targetTaskCount:
              parseNonNegativeIntegerInput(
                row.targetTaskCount,
              ) || 0,
          };
        })
        .filter(
          (entry) =>
            entry.targetTaskCount > 0,
        )
      : [];
  return {
    mode:
      (
        source.mode || ""
      )
        .toString()
        .trim(),
    currentTaskCount:
      parseNonNegativeIntegerInput(
        source.currentTaskCount,
      ) || 0,
    requestedTaskCount:
      parseNonNegativeIntegerInput(
        source.requestedTaskCount,
      ) || 0,
    maxAdditionalTasks:
      parseNonNegativeIntegerInput(
        source.maxAdditionalTasks,
      ),
    phaseTargets,
  };
}

function normalizeDraftPhaseTargetName(
  value,
) {
  return (
    value == null ? "" : value.toString()
  )
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function resolveInclusivePhaseWindowDays(
  phase,
) {
  const start =
    parseDateInput(
      phase?.taskStartDate ||
        phase?.startDate,
    ) ||
    parseDateInput(phase?.startDate);
  const end =
    parseDateInput(
      phase?.taskEndDate ||
        phase?.endDate,
    ) ||
    parseDateInput(phase?.endDate);
  if (!start || !end) {
    return Math.max(
      1,
      Math.floor(
        Number(
          phase?.estimatedDays || 1,
        ),
      ),
    );
  }
  return Math.max(
    1,
    Math.floor(
      (end.getTime() - start.getTime()) /
        MS_PER_DAY,
    ) + 1,
  );
}

function resolveDraftRequestedTaskCount({
  planningDays,
  currentTaskCount,
  refineTarget,
  sourceDocumentTaskLineEstimate,
}) {
  const safePlanningDays = Math.max(
    1,
    Math.floor(
      Number(planningDays || 0),
    ),
  );
  let targetTaskCount = Math.max(
    0,
    Number(currentTaskCount || 0),
  );

  if (
    Number(
      refineTarget?.requestedTaskCount,
    ) > targetTaskCount
  ) {
    targetTaskCount = Number(
      refineTarget.requestedTaskCount,
    );
  }

  if (
    Number(sourceDocumentTaskLineEstimate) >
    0
  ) {
    targetTaskCount = Math.max(
      targetTaskCount,
      Math.min(
        Math.floor(
          Number(
            sourceDocumentTaskLineEstimate,
          ),
        ),
        safePlanningDays,
      ),
    );
  }

  if (
    Number.isFinite(
      Number(
        refineTarget?.maxAdditionalTasks,
      ),
    )
  ) {
    targetTaskCount = Math.min(
      targetTaskCount,
      Math.max(
        0,
        Number(currentTaskCount || 0),
      ) +
        Math.max(
          0,
          Number(
            refineTarget.maxAdditionalTasks,
          ),
        ),
    );
  }

  return Math.max(
    Math.max(
      0,
      Number(currentTaskCount || 0),
    ),
    Math.floor(targetTaskCount),
  );
}

function buildDraftPhaseTaskTargetMap({
  scheduledPhases,
  refineTarget,
  requestedTaskCount,
}) {
  const explicitTargetsByName =
    new Map(
      (refineTarget?.phaseTargets || [])
        .map((entry) => [
          normalizeDraftPhaseTargetName(
            entry.phaseName,
          ),
          Math.max(
            0,
            Number(
              entry.targetTaskCount || 0,
            ),
          ),
        ])
        .filter(([key, value]) => key && value > 0),
    );
  const rows =
    (
      Array.isArray(scheduledPhases) ?
        scheduledPhases
      : []
    ).map((phase) => {
      const currentTaskCount =
        Array.isArray(phase?.tasks) ?
          phase.tasks.length
        : 0;
      const phaseWindowDays =
        resolveInclusivePhaseWindowDays(
          phase,
        );
      const normalizedName =
        normalizeDraftPhaseTargetName(
          phase?.name,
        );
      const explicitTarget =
        explicitTargetsByName.get(
          normalizedName,
        ) || 0;
      const heuristicTarget =
        Math.max(
          currentTaskCount,
          Math.max(
            phaseWindowDays >= 4 ? 2 : 1,
            Math.min(
              phaseWindowDays,
              Math.ceil(
                phaseWindowDays * 0.85,
              ),
            ),
          ),
        );
      return {
        phaseName:
          phase?.name || "",
        targetTaskCount:
          Math.max(
            currentTaskCount,
            explicitTarget || heuristicTarget,
          ),
        phaseWindowDays,
      };
    });

  let remaining =
    Math.max(
      0,
      Number(requestedTaskCount || 0),
    ) -
    rows.reduce(
      (sum, row) =>
        sum +
        row.targetTaskCount,
      0,
    );
  const expandableRows = rows
    .filter(
      (row) =>
        row.phaseWindowDays >
        row.targetTaskCount,
    )
    .sort(
      (left, right) =>
        right.phaseWindowDays -
        left.phaseWindowDays,
    );
  let cursor = 0;
  while (
    remaining > 0 &&
    expandableRows.length > 0
  ) {
    const row =
      expandableRows[
        cursor % expandableRows.length
      ];
    if (
      row.targetTaskCount <
      row.phaseWindowDays
    ) {
      row.targetTaskCount += 1;
      remaining -= 1;
    }
    cursor += 1;
    if (
      cursor >
      expandableRows.length * 8
    ) {
      break;
    }
  }

  return new Map(
    rows.map((row) => [
      normalizeDraftPhaseTargetName(
        row.phaseName,
      ),
      row.targetTaskCount,
    ]),
  );
}

function resolveDraftPhaseDefaultRole(
  tasks,
) {
  const counts = new Map();
  (
    Array.isArray(tasks) ? tasks : []
  ).forEach((task) => {
    const role =
      normalizeStaffIdInput(
        task?.roleRequired,
      ) || "farmer";
    counts.set(
      role,
      (counts.get(role) || 0) + 1,
    );
  });
  const sorted =
    Array.from(counts.entries()).sort(
      (left, right) =>
        right[1] - left[1],
    );
  return sorted[0]?.[0] || "farmer";
}

function resolveDraftPhaseDefaultHeadcount(
  tasks,
) {
  const counts = new Map();
  (
    Array.isArray(tasks) ? tasks : []
  ).forEach((task) => {
    const headcount =
      normalizeDraftTaskHeadcount(
        task?.requiredHeadcount,
      );
    counts.set(
      headcount,
      (counts.get(headcount) || 0) + 1,
    );
  });
  const sorted =
    Array.from(counts.entries()).sort(
      (left, right) =>
        right[1] - left[1],
    );
  return sorted[0]?.[0] || 1;
}

function resolveDraftPhaseTopUpTemplates({
  phaseName,
  domainContext,
}) {
  const normalizedName =
    normalizeDraftPhaseTargetName(
      phaseName,
    );
  if (domainContext === "farm") {
    if (normalizedName.includes("nursery")) {
      return [
        ["Seed tray moisture check", "Inspect tray moisture, germination uniformity, and replace weak trays before the next nursery cycle."],
        ["Nursery sanitation pass", "Clean nursery benches, remove diseased material, and reset hygiene controls for the next work block."],
        ["Seedling vigor count", "Record seedling vigor, leaf color, and tray gaps so the nursery register stays current."],
      ];
    }
    if (
      normalizedName.includes("transplant")
    ) {
      return [
        ["Transplant line check", "Verify spacing, placement depth, and line straightness across the greenhouse before closing the work block."],
        ["Gap-fill walk", "Identify missed holes, weak stands, and transplant shock points, then queue replacements."],
        ["Irrigation settle review", "Check post-transplant irrigation coverage and correct uneven wetting or pressure issues."],
      ];
    }
    if (
      normalizedName.includes("vegetative")
    ) {
      return [
        ["Canopy growth inspection", "Walk the greenhouse, review canopy growth, and record uneven vigor or stress signals."],
        ["Fertigation tuning check", "Confirm dosing rate, tank levels, and feed uniformity against current vegetative demand."],
        ["Pest scouting round", "Inspect leaves, stems, and greenhouse edges for pests or disease pressure and record findings."],
        ["Trellis and pruning pass", "Tighten support lines, remove excess growth, and keep plant structure consistent."],
      ];
    }
    if (
      normalizedName.includes("flower")
    ) {
      return [
        ["Flower set inspection", "Review flower initiation, drop rate, and greenhouse climate signals affecting set."],
        ["Pollination support check", "Confirm airflow, pollination support work, and bloom uniformity across houses."],
        ["Nutrient balance review", "Check feed balance and irrigation timing for flowering-stage stability."],
      ];
    }
    if (
      normalizedName.includes("fruit")
    ) {
      return [
        ["Fruit load count", "Measure fruit set density, identify weak clusters, and record corrective actions."],
        ["Fruit quality sampling", "Sample size, color, and surface quality so the harvest forecast stays accurate."],
        ["Support and stress check", "Inspect supports, plant load, and crop stress risk before the next pick cycle."],
      ];
    }
    if (
      normalizedName.includes("harvest")
    ) {
      return [
        ["Harvest maturity sampling", "Walk the crop and tag rows ready for the next pick based on maturity and market spec."],
        ["Picking round prep", "Set picking sequence, crates, and staffing before the next harvest round starts."],
        ["Sorting and grading run", "Sort harvested fruit by grade, isolate rejects, and reconcile harvested quantities."],
      ];
    }
  }
  return [
    ["Operational checkpoint", `Record phase progress, execution blockers, and the next action for ${phaseName || "this phase"}.`],
    ["Workfront inspection", `Inspect active work in ${phaseName || "this phase"} and resolve any missed follow-up tasks.`],
    ["Manager review note", `Capture daily status, labor needs, and quality observations for ${phaseName || "this phase"}.`],
  ];
}

function buildDraftPhaseTopUpTasks({
  phaseName,
  domainContext,
  existingTasks,
  targetTaskCount,
}) {
  const safeExistingTasks =
    Array.isArray(existingTasks) ?
      existingTasks
    : [];
  const missingTaskCount =
    Math.max(
      0,
      Number(targetTaskCount || 0) -
        safeExistingTasks.length,
    );
  if (missingTaskCount < 1) {
    return [];
  }

  const templates =
    resolveDraftPhaseTopUpTemplates({
      phaseName,
      domainContext,
    });
  const roleRequired =
    resolveDraftPhaseDefaultRole(
      safeExistingTasks,
    );
  const requiredHeadcount =
    resolveDraftPhaseDefaultHeadcount(
      safeExistingTasks,
    );
  const seenTitles =
    new Set(
      safeExistingTasks.map((task) =>
        normalizeDraftPhaseTargetName(
          task?.title,
        ),
      ),
    );
  const generatedTasks = [];
  let templateIndex = 0;
  let safetyCounter = 0;

  while (
    generatedTasks.length <
      missingTaskCount &&
    safetyCounter <
      missingTaskCount * 8
  ) {
    const template =
      templates[
        templateIndex %
          templates.length
      ];
    const cycle =
      Math.floor(
        templateIndex /
          templates.length,
      ) + 1;
    const title =
      cycle <= 1 ?
        template[0]
      : `${template[0]} ${cycle}`;
    const normalizedTitle =
      normalizeDraftPhaseTargetName(
        title,
      );
    if (
      normalizedTitle &&
      !seenTitles.has(
        normalizedTitle,
      )
    ) {
      generatedTasks.push(
        normalizeDraftTaskShape({
          title,
          roleRequired,
          requiredHeadcount,
          weight: 1,
          instructions:
            template[1] ||
            `Operational follow-up for ${phaseName || "this phase"}.`,
          assignedStaffProfileIds:
            [],
        }),
      );
      seenTitles.add(
        normalizedTitle,
      );
    }
    templateIndex += 1;
    safetyCounter += 1;
  }

  return generatedTasks;
}

function buildProductionDraftActor(
  {
    actor,
    staffProfile,
  } = {},
) {
  return {
    actorId: actor?._id || null,
    actorName:
      (
        actor?.name ||
        actor?.fullName ||
        actor?.userName ||
        ""
      )
        .toString()
        .trim(),
    actorEmail:
      (
        actor?.email || ""
      )
        .toString()
        .trim(),
    actorRole:
      (
        actor?.role || ""
      )
        .toString()
        .trim(),
    actorStaffRole:
      (
        staffProfile?.staffRole || ""
      )
        .toString()
        .trim(),
  };
}

function buildProductionDraftRevisionSummary({
  plan,
  phases,
  tasks,
}) {
  return {
    title:
      (
        plan?.title || ""
      )
        .toString()
        .trim(),
    status:
      (
        plan?.status ||
        PRODUCTION_STATUS_DRAFT
      )
        .toString()
        .trim(),
    phaseCount:
      Array.isArray(phases) ?
        phases.length
      : 0,
    taskCount:
      Array.isArray(tasks) ?
        tasks.length
      : 0,
    startDate:
      plan?.startDate || null,
    endDate:
      plan?.endDate || null,
  };
}

function buildProductionDraftSnapshot({
  plan,
  phases,
  tasks,
}) {
  return {
    plan: {
      id:
        plan?._id?.toString?.() || "",
      businessId:
        plan?.businessId?.toString?.() ||
        "",
      estateAssetId:
        plan?.estateAssetId?.toString?.() ||
        "",
      productId:
        plan?.productId?.toString?.() ||
        "",
      title:
        (
          plan?.title || ""
        )
          .toString()
          .trim(),
      notes:
        (
          plan?.notes || ""
        )
          .toString()
          .trim(),
      domainContext:
        (
          plan?.domainContext ||
          DEFAULT_PRODUCTION_DOMAIN_CONTEXT
        )
          .toString()
          .trim(),
      status:
        (
          plan?.status ||
          PRODUCTION_STATUS_DRAFT
        )
          .toString()
          .trim(),
      startDate:
        plan?.startDate || null,
      endDate:
        plan?.endDate || null,
      plantingTargets:
        plan?.plantingTargets || null,
      workloadContext:
        plan?.workloadContext || null,
      aiGenerated:
        Boolean(plan?.aiGenerated),
    },
    phases:
      Array.isArray(phases) ?
        phases.map((phase) => ({
          id:
            phase?._id?.toString?.() || "",
          name:
            (
              phase?.name || ""
            )
              .toString()
              .trim(),
          order: Number(phase?.order || 0),
          status:
            (
              phase?.status || ""
            )
              .toString()
              .trim(),
          phaseType:
            (
              phase?.phaseType || ""
            )
              .toString()
              .trim(),
          requiredUnits:
            Number(
              phase?.requiredUnits || 0,
            ) || 0,
          minRatePerFarmerHour:
            Number(
              phase?.minRatePerFarmerHour ||
                0,
            ) || 0,
          targetRatePerFarmerHour:
            Number(
              phase?.targetRatePerFarmerHour ||
                0,
            ) || 0,
          plannedHoursPerDay:
            Number(
              phase?.plannedHoursPerDay ||
                0,
            ) || 0,
          biologicalMinDays:
            Number(
              phase?.biologicalMinDays ||
                0,
            ) || 0,
          startDate:
            phase?.startDate || null,
          endDate:
            phase?.endDate || null,
          kpiTarget:
            phase?.kpiTarget || null,
        }))
      : [],
    tasks:
      Array.isArray(tasks) ?
        tasks.map((task) => ({
          id:
            task?._id?.toString?.() || "",
          phaseId:
            task?.phaseId?.toString?.() ||
            "",
          title:
            (
              task?.title || ""
            )
              .toString()
              .trim(),
          roleRequired:
            (
              task?.roleRequired || ""
            )
              .toString()
              .trim(),
          assignedStaffId:
            task?.assignedStaffId?.toString?.() ||
            "",
          assignedStaffProfileIds:
            resolveTaskAssignedStaffIds(task),
          assignedUnitIds:
            resolveTaskAssignedUnitIds(task),
          requiredHeadcount:
            Number(
              task?.requiredHeadcount || 0,
            ) || 0,
          weight:
            Number(task?.weight || 0) || 0,
          status:
            (
              task?.status || ""
            )
              .toString()
              .trim(),
          approvalStatus:
            (
              task?.approvalStatus || ""
            )
              .toString()
              .trim(),
          startDate:
            task?.startDate || null,
          dueDate:
            task?.dueDate || null,
          instructions:
            (
              task?.instructions || ""
            )
              .toString()
              .trim(),
          taskType:
            (
              task?.taskType || ""
            )
              .toString()
              .trim(),
          sourceTemplateKey:
            (
              task?.sourceTemplateKey || ""
            )
              .toString()
              .trim(),
          recurrenceGroupKey:
            (
              task?.recurrenceGroupKey || ""
            )
              .toString()
              .trim(),
          occurrenceIndex:
            Number(
              task?.occurrenceIndex || 0,
            ) || 0,
        }))
      : [],
  };
}

async function appendProductionDraftSaveHistory({
  plan,
  actor,
  staffProfile,
  phases,
  tasks,
  action,
  note,
}) {
  if (!plan) {
    return;
  }
  const actorSummary =
    buildProductionDraftActor({
      actor,
      staffProfile,
    });
  const savedAt = new Date();
  const revisionNumber =
    Math.max(
      0,
      Number(
        plan.draftRevisionCount || 0,
      ),
    ) + 1;
  const cleanNote =
    (
      note || ""
    )
      .toString()
      .trim();
  const revisionSummary =
    buildProductionDraftRevisionSummary(
      {
        plan,
        phases,
        tasks,
      },
    );
  const snapshot =
    buildProductionDraftSnapshot({
      plan,
      phases,
      tasks,
    });

  plan.lastDraftSavedAt = savedAt;
  plan.lastDraftSavedBy = actorSummary;
  plan.draftRevisionCount = revisionNumber;
  plan.draftAuditTrailCount =
    Math.max(
      0,
      Number(
        plan.draftAuditTrailCount ||
          0,
      ),
    ) + 1;
  if (!Array.isArray(plan.draftAuditLog)) {
    plan.draftAuditLog = [];
  }
  if (!Array.isArray(plan.draftRevisions)) {
    plan.draftRevisions = [];
  }
  plan.draftAuditLog.push({
    action,
    note: cleanNote,
    revisionNumber,
    actor: actorSummary,
    createdAt: savedAt,
  });
  plan.draftRevisions.push({
    revisionNumber,
    action,
    note: cleanNote,
    actor: actorSummary,
    savedAt,
    summary: revisionSummary,
    snapshot,
  });
  await plan.save();
}

function sanitizeProductionDraftAuditEntries(
  entries,
) {
  return (
    Array.isArray(entries) ?
      entries
    : []
  ).map((entry) => ({
    id:
      entry?._id?.toString?.() || "",
    action:
      (
        entry?.action || ""
      )
        .toString()
        .trim(),
    note:
      (
        entry?.note || ""
      )
        .toString()
        .trim(),
    revisionNumber:
      Number(
        entry?.revisionNumber || 0,
      ) || 0,
    createdAt:
      entry?.createdAt || null,
    actor:
      entry?.actor || null,
  }));
}

function sanitizeProductionDraftRevisionEntries(
  entries,
) {
  return (
    Array.isArray(entries) ?
      entries
    : []
  ).map((entry) => ({
    id:
      entry?._id?.toString?.() || "",
    revisionNumber:
      Number(
        entry?.revisionNumber || 0,
      ) || 0,
    action:
      (
        entry?.action || ""
      )
        .toString()
        .trim(),
    note:
      (
        entry?.note || ""
      )
        .toString()
        .trim(),
    savedAt:
      entry?.savedAt || null,
    actor:
      entry?.actor || null,
    summary:
      entry?.summary || null,
  }));
}

// PHASE-GATE-LAYER
// WHY: Phase-type normalization keeps finite/monitoring lifecycle semantics deterministic.
function normalizeProductionPhaseTypeInput(
  value,
) {
  const normalized =
    normalizeStaffIdInput(value)
      .toLowerCase()
      .trim();
  if (
    normalized ===
    PRODUCTION_PHASE_TYPE_MONITORING
  ) {
    return PRODUCTION_PHASE_TYPE_MONITORING;
  }
  return PRODUCTION_PHASE_TYPE_FINITE;
}

// PHASE-GATE-LAYER
// WHY: Workload context provides explicit unit budget defaults for finite phases.
function parseWorkloadContextTotalUnits(
  workloadContext,
) {
  const source =
    (
      workloadContext &&
      typeof workloadContext ===
        "object"
    ) ?
      workloadContext
    : {};
  const candidateValues = [
    source.totalWorkUnits,
    source.totalUnits,
    source.requiredUnits,
    source.units,
  ];
  for (const value of candidateValues) {
    const parsed = Number(value);
    if (
      Number.isFinite(parsed) &&
      parsed > 0
    ) {
      return Math.floor(parsed);
    }
  }
  return 0;
}

function normalizeProductionWorkUnitLabelInput(
  value,
  { fallback = "" } = {},
) {
  const rawValue =
    value == null ||
      value
        .toString()
        .trim()
        .length === 0 ?
      fallback
    : value;
  return (
    rawValue || ""
  )
    .toString()
    .trim()
    .replace(/\s+/g, " ");
}

function resolveDefaultWorkUnitLabelForDomain(
  domainContext,
) {
  return normalizeDomainContext(
    domainContext,
  ) === "farm" ?
      "plot"
    : "work unit";
}

function normalizeWorkloadContextIntegerInput(
  value,
  {
    fallback = 0,
    min = 0,
  } = {},
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    const safeFallback = Number(fallback);
    if (!Number.isFinite(safeFallback)) {
      return min;
    }
    return Math.max(
      min,
      Math.floor(safeFallback),
    );
  }
  return Math.max(min, Math.floor(parsed));
}

function normalizeWorkloadContextPercentInput(
  value,
  { fallback = 0 } = {},
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    const safeFallback = Number(fallback);
    if (!Number.isFinite(safeFallback)) {
      return 0;
    }
    return Math.max(
      0,
      Math.min(100, Math.round(safeFallback)),
    );
  }
  return Math.max(
    0,
    Math.min(100, Math.round(parsed)),
  );
}

function resolveScheduledPhaseTotalWorkUnits(
  phases,
) {
  return (
    Array.isArray(phases) ? phases : []
  ).reduce((maxUnits, phase) => {
    if (
      normalizeProductionPhaseTypeInput(
        phase?.phaseType,
      ) !== PRODUCTION_PHASE_TYPE_FINITE
    ) {
      return maxUnits;
    }
    return Math.max(
      maxUnits,
      normalizePhaseRequiredUnitsInput(
        phase?.requiredUnits,
      ),
    );
  }, 0);
}

function buildNormalizedProductionWorkloadContext(
  {
    workloadContext,
    fallbackWorkloadContext = null,
    domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
    defaultTotalWorkUnits = 0,
  } = {},
) {
  const source =
    (
      workloadContext &&
      typeof workloadContext === "object"
    ) ?
      workloadContext
    : {};
  const fallbackSource =
    (
      fallbackWorkloadContext &&
      typeof fallbackWorkloadContext ===
        "object"
    ) ?
      fallbackWorkloadContext
    : {};

  const sourceTotalUnits =
    parseWorkloadContextTotalUnits(source);
  const fallbackTotalUnits =
    parseWorkloadContextTotalUnits(
      fallbackSource,
    );
  const resolvedTotalWorkUnits =
    sourceTotalUnits > 0 ?
      sourceTotalUnits
    : fallbackTotalUnits > 0 ?
      fallbackTotalUnits
    : normalizeWorkloadContextIntegerInput(
        defaultTotalWorkUnits,
      );
  const defaultWorkUnitLabel =
    resolveDefaultWorkUnitLabelForDomain(
      domainContext,
    );
  const resolvedWorkUnitLabel =
    normalizeProductionWorkUnitLabelInput(
      source.workUnitLabel ||
        source.workUnitType,
      {
        fallback:
          normalizeProductionWorkUnitLabelInput(
            fallbackSource.workUnitLabel ||
              fallbackSource.workUnitType,
            {
              fallback:
                resolvedTotalWorkUnits > 0 ?
                  defaultWorkUnitLabel
                : "",
            },
          ),
      },
    );
  const minStaffPerUnit =
    normalizeWorkloadContextIntegerInput(
      source.minStaffPerUnit,
      {
        fallback:
          normalizeWorkloadContextIntegerInput(
            fallbackSource.minStaffPerUnit,
          ),
      },
    );
  const maxStaffPerUnit = Math.max(
    minStaffPerUnit,
    normalizeWorkloadContextIntegerInput(
      source.maxStaffPerUnit,
      {
        fallback:
          normalizeWorkloadContextIntegerInput(
            fallbackSource.maxStaffPerUnit,
            {
              fallback: minStaffPerUnit,
            },
          ),
      },
    ),
  );
  const activeStaffAvailabilityPercent =
    normalizeWorkloadContextPercentInput(
      source.activeStaffAvailabilityPercent ??
        source.expectedActivePercent,
      {
        fallback:
          normalizeWorkloadContextPercentInput(
            fallbackSource.activeStaffAvailabilityPercent ??
              fallbackSource.expectedActivePercent,
          ),
      },
    );
  const hasConfirmedWorkloadContext =
    source.hasConfirmedWorkloadContext ===
      true ||
    (
      source.hasConfirmedWorkloadContext ==
          null &&
      fallbackSource.hasConfirmedWorkloadContext ===
        true
    ) ||
    (
      resolvedTotalWorkUnits > 0 &&
      resolvedWorkUnitLabel
        .trim()
        .length >
        0
    );

  if (
    resolvedTotalWorkUnits <= 0 &&
    resolvedWorkUnitLabel
      .trim()
      .length ===
      0 &&
    minStaffPerUnit <= 0 &&
    maxStaffPerUnit <= 0 &&
    activeStaffAvailabilityPercent <=
      0 &&
    !hasConfirmedWorkloadContext
  ) {
    return null;
  }

  return {
    workUnitLabel:
      resolvedWorkUnitLabel,
    workUnitType:
      resolvedWorkUnitLabel,
    totalWorkUnits:
      resolvedTotalWorkUnits,
    minStaffPerUnit,
    maxStaffPerUnit,
    activeStaffAvailabilityPercent,
    hasConfirmedWorkloadContext,
  };
}

// PHASE-GATE-LAYER
// WHY: Required units must remain whole-number phase budgets for lock calculations.
function normalizePhaseRequiredUnitsInput(
  value,
  { fallback = 0 } = {},
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    const safeFallback =
      Number(fallback);
    if (
      !Number.isFinite(safeFallback) ||
      safeFallback < 0
    ) {
      return 0;
    }
    return Math.floor(safeFallback);
  }
  return Math.max(
    0,
    Math.floor(parsed),
  );
}

// PHASE-GATE-LAYER
// WHY: Finite phase duration math should consume explicit throughput assumptions when provided.
function normalizePhaseRatePerFarmerHourInput(
  value,
  {
    fallback = DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
  } = {},
) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    const safeFallback =
      Number(fallback);
    if (
      !Number.isFinite(safeFallback) ||
      safeFallback <= 0
    ) {
      return DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR;
    }
    return Number(safeFallback);
  }
  return Number(parsed);
}

// PHASE-GATE-LAYER
// WHY: Planned hours define daily throughput conversion from per-hour rates.
function normalizePhasePlannedHoursPerDayInput(
  value,
  {
    fallback = DEFAULT_PHASE_PLANNED_HOURS_PER_DAY,
  } = {},
) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    const safeFallback =
      Number(fallback);
    if (
      !Number.isFinite(safeFallback) ||
      safeFallback <= 0
    ) {
      return DEFAULT_PHASE_PLANNED_HOURS_PER_DAY;
    }
    return Number(safeFallback);
  }
  return Number(parsed);
}

// PHASE-GATE-LAYER
// WHY: Two-clock scheduling needs a biological lower bound that can exceed labor execution days.
function normalizePhaseBiologicalMinDaysInput(
  value,
  {
    fallback = DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS,
  } = {},
) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    const safeFallback =
      Number(fallback);
    if (
      !Number.isFinite(safeFallback) ||
      safeFallback < 0
    ) {
      return DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS;
    }
    return Math.floor(safeFallback);
  }
  return Math.max(
    0,
    Math.floor(parsed),
  );
}

// PHASE-GATE-LAYER
// WHY: Unit-coverage parsing ensures finite-phase cap logic can trim draft tasks deterministically.
function resolveDraftTaskCoverageUnits(
  task,
) {
  if (
    !task ||
    typeof task !== "object"
  ) {
    return 0;
  }
  const assignedUnitIds =
    (
      Array.isArray(
        task.assignedUnitIds,
      )
    ) ?
      task.assignedUnitIds
    : [];
  const validAssignedUnits =
    assignedUnitIds
      .map((value) =>
        normalizeStaffIdInput(value),
      )
      .filter((value) =>
        mongoose.Types.ObjectId.isValid(
          value,
        ),
      );
  if (validAssignedUnits.length > 0) {
    return validAssignedUnits.length;
  }

  const numericCandidates = [
    task.unitCoverage,
    task.coveredUnits,
    task.expectedPlots,
    task.actualPlots,
  ];
  for (const candidate of numericCandidates) {
    const parsed = Number(candidate);
    if (
      Number.isFinite(parsed) &&
      parsed > 0
    ) {
      return Math.max(
        1,
        Math.ceil(parsed),
      );
    }
  }
  return 1;
}

// PHASE-GATE-LAYER
// WHY: Finite phase durations should come from unit budget / workforce throughput so plans finish when work is done.
function resolveFinitePhaseEstimatedDaysFromWorkload({
  phase,
  capacitySummary,
  minimumPlotsPerFarmerPerDay = FINITE_PHASE_MIN_PLOTS_PER_FARMER_PER_DAY,
}) {
  const fallbackEstimatedDays =
    Math.max(
      1,
      Math.floor(
        Number(
          phase?.estimatedDays || 1,
        ),
      ),
    );
  const phaseType =
    normalizeProductionPhaseTypeInput(
      phase?.phaseType,
    );
  if (
    phaseType !==
    PRODUCTION_PHASE_TYPE_FINITE
  ) {
    return fallbackEstimatedDays;
  }

  const requiredUnits =
    normalizePhaseRequiredUnitsInput(
      phase?.requiredUnits,
    );
  if (requiredUnits <= 0) {
    return fallbackEstimatedDays;
  }

  const availableFarmers = Math.max(
    0,
    Number(
      capacitySummary?.roles?.farmer
        ?.available ??
        capacitySummary?.roles?.farmer
          ?.total ??
        0,
    ),
  );
  if (availableFarmers <= 0) {
    return fallbackEstimatedDays;
  }

  const plannedHoursPerDay =
    normalizePhasePlannedHoursPerDayInput(
      phase?.plannedHoursPerDay,
      {
        fallback:
          DEFAULT_PHASE_PLANNED_HOURS_PER_DAY,
      },
    );
  const minimumRatePerFarmerHour =
    normalizePhaseRatePerFarmerHourInput(
      phase?.minRatePerFarmerHour,
      {
        fallback:
          DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
      },
    );
  const fallbackThroughputPerFarmerPerDay =
    Math.max(
      0.1,
      Number(
        minimumPlotsPerFarmerPerDay ||
          FINITE_PHASE_MIN_PLOTS_PER_FARMER_PER_DAY,
      ),
    );
  const throughputPerFarmerPerDay =
    (
      minimumRatePerFarmerHour > 0 &&
      plannedHoursPerDay > 0
    ) ?
      minimumRatePerFarmerHour *
      plannedHoursPerDay
    : fallbackThroughputPerFarmerPerDay;
  const dailyCoverageUnits =
    availableFarmers *
    throughputPerFarmerPerDay;
  if (
    !Number.isFinite(
      dailyCoverageUnits,
    ) ||
    dailyCoverageUnits <= 0
  ) {
    return fallbackEstimatedDays;
  }

  return Math.max(
    1,
    Math.ceil(
      requiredUnits /
        dailyCoverageUnits,
    ),
  );
}

// WHY: Canonical integer plot units avoid floating-point drift for partial plot values (e.g. 0.5).
function convertPlotsToPlotUnits(
  value,
) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    return null;
  }
  return Math.round(
    parsed * PLOT_UNIT_SCALE,
  );
}

// WHY: Integer unit storage must always be reversible back to a normalized decimal plot value.
function convertPlotUnitsToPlots(
  value,
) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed < 0
  ) {
    return null;
  }
  return Number(
    (parsed / PLOT_UNIT_SCALE).toFixed(
      3,
    ),
  );
}

// WHY: Accept either decimal plots or canonical units while keeping one deterministic write shape.
function resolveActualPlotProgressInput({
  hasActualPlots,
  actualPlotsRaw,
  hasActualPlotUnits,
  actualPlotUnitsRaw,
}) {
  let plotsFromRaw = null;
  let unitsFromRaw = null;
  let plotsFromUnits = null;

  if (hasActualPlots) {
    const normalizedUnits =
      convertPlotsToPlotUnits(
        actualPlotsRaw,
      );
    if (normalizedUnits == null) {
      return {
        ok: false,
        errorCode:
          "TASK_PROGRESS_ACTUAL_INVALID",
      };
    }
    const normalizedPlots =
      convertPlotUnitsToPlots(
        normalizedUnits,
      );
    if (normalizedPlots == null) {
      return {
        ok: false,
        errorCode:
          "TASK_PROGRESS_ACTUAL_INVALID",
      };
    }
    plotsFromRaw = normalizedPlots;
    unitsFromRaw = normalizedUnits;
  }

  if (hasActualPlotUnits) {
    const parsedUnits = Number(
      actualPlotUnitsRaw,
    );
    if (
      !Number.isFinite(parsedUnits) ||
      parsedUnits < 0 ||
      !Number.isInteger(parsedUnits)
    ) {
      return {
        ok: false,
        errorCode:
          "TASK_PROGRESS_ACTUAL_INVALID",
      };
    }
    plotsFromUnits =
      convertPlotUnitsToPlots(
        parsedUnits,
      );
    if (plotsFromUnits == null) {
      return {
        ok: false,
        errorCode:
          "TASK_PROGRESS_ACTUAL_INVALID",
      };
    }
    if (
      hasActualPlots &&
      Math.abs(
        unitsFromRaw - parsedUnits,
      ) > 1
    ) {
      return {
        ok: false,
        errorCode:
          "TASK_PROGRESS_ACTUAL_INVALID",
      };
    }
    unitsFromRaw = parsedUnits;
  }

  const resolvedUnits = unitsFromRaw;
  const resolvedPlots =
    hasActualPlotUnits ?
      plotsFromUnits
    : plotsFromRaw;

  if (
    resolvedUnits == null ||
    resolvedPlots == null
  ) {
    return {
      ok: false,
      errorCode:
        "TASK_PROGRESS_ACTUAL_INVALID",
    };
  }

  return {
    ok: true,
    actualPlots: resolvedPlots,
    actualPlotUnits: resolvedUnits,
  };
}

// WHY: Daily records must be normalized to a stable calendar day key.
function normalizeWorkDateToDayStart(
  value,
) {
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

// WHY: Progress logging should only accept staff who completed a full shift on the same work day.
async function findCompletedAttendanceForStaffOnWorkDate({
  staffProfileId,
  workDate,
  taskId = "",
}) {
  const normalizedStaffId = normalizeStaffIdInput(
    staffProfileId,
  );
  const normalizedWorkDate =
    normalizeWorkDateToDayStart(workDate);
  const normalizedTaskId =
    normalizeStaffIdInput(taskId);
  if (
    !normalizedStaffId ||
    !normalizedWorkDate
  ) {
    return null;
  }

  const workDateEndExclusive = new Date(
    normalizedWorkDate.getTime() + MS_PER_DAY,
  );

  const attendanceFilter = {
    staffProfileId: normalizedStaffId,
    ...(normalizedTaskId ?
      {
        taskId:
          normalizedTaskId,
        workDate:
          normalizedWorkDate,
      }
    : {
        clockInAt: {
          $lt: workDateEndExclusive,
        },
      }),
    clockOutAt: {
      $ne: null,
      $gte: normalizedWorkDate,
    },
  };

  return StaffAttendance.findOne(
    attendanceFilter,
  )
    .sort({
      clockOutAt: -1,
      clockInAt: -1,
    })
    .lean();
}

// WHY: Keep delay reasons constrained to the controlled taxonomy.
function normalizeTaskProgressDelayReason(
  value,
) {
  const raw =
    value == null ? "none" : (
      value
        .toString()
        .trim()
        .toLowerCase()
    );
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

function normalizeStringArrayInput(
  values,
  { lowerCase = false } = {},
) {
  if (!Array.isArray(values)) {
    return [];
  }
  return Array.from(
    new Set(
      values
        .map((value) => {
          const normalized =
            normalizeStaffIdInput(value);
          return lowerCase ?
              normalized.toLowerCase()
            : normalized;
        })
        .filter(Boolean),
    ),
  ).sort();
}

// WHY: Planner V2 consumes compact role/staff maps, so nested assistant focus
// payloads need deterministic normalization before they enter AI prompts.
function normalizeStringListMapInput(
  value,
  { lowerCaseKeys = false, lowerCaseValues = false } = {},
) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    return {};
  }
  const entries = Object.entries(value)
    .map(([key, rawValues]) => {
      const normalizedKeyRaw =
        normalizeStaffIdInput(key);
      const normalizedKey =
        lowerCaseKeys ?
          normalizedKeyRaw.toLowerCase()
        : normalizedKeyRaw;
      const normalizedValues =
        normalizeStringArrayInput(
          rawValues,
          { lowerCase: lowerCaseValues },
        );
      if (
        !normalizedKey ||
        normalizedValues.length === 0
      ) {
        return null;
      }
      return [
        normalizedKey,
        normalizedValues,
      ];
    })
    .filter(Boolean)
    .sort(([leftKey], [rightKey]) =>
      leftKey.localeCompare(rightKey),
    );
  return Object.fromEntries(entries);
}

// WHY: Task progress must support single and multi-assignee tasks without ambiguity.
function resolveTaskAssignedStaffIds(
  task,
) {
  const assignedFromProfiles =
    (
      Array.isArray(
        task?.assignedStaffProfileIds,
      )
    ) ?
      task.assignedStaffProfileIds
    : [];
  const assignedFromArray =
    (
      Array.isArray(
        task?.assignedStaffIds,
      )
    ) ?
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

  return Array.from(
    new Set(resolvedIds),
  );
}

function getProductionTaskAssignmentValidationError({
  taskRoleRequired,
  assignedProfile,
  estateAssetId = null,
  invalidRoleError = PRODUCTION_COPY.STAFF_ROLE_MISMATCH,
  scopeError = PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
}) {
  const normalizedTaskRole =
    normalizeStaffIdInput(
      taskRoleRequired,
    ).toLowerCase();
  const normalizedStaffRole =
    normalizeStaffIdInput(
      assignedProfile?.staffRole,
    ).toLowerCase();

  if (
    !normalizedTaskRole ||
    !STAFF_ROLE_VALUES.includes(
      normalizedTaskRole,
    )
  ) {
    return PRODUCTION_COPY.STAFF_ROLE_REQUIRED;
  }
  if (
    !normalizedStaffRole ||
    !STAFF_ROLE_VALUES.includes(
      normalizedStaffRole,
    )
  ) {
    return invalidRoleError;
  }

  // WHY: Production tasks can be staffed by cross-role helpers when operations
  // need it. roleRequired remains the preferred planning role, not a hard gate.
  if (
    estateAssetId &&
    assignedProfile?.estateAssetId &&
    assignedProfile.estateAssetId.toString() !==
      estateAssetId.toString()
  ) {
    return scopeError;
  }

  return "";
}

// UNIT-LIFECYCLE
// WHY: Unit completion writes must use canonical unit ids persisted on each task.
function resolveTaskAssignedUnitIds(
  task,
) {
  const assignedUnits =
    (
      Array.isArray(
        task?.assignedUnitIds,
      )
    ) ?
      task.assignedUnitIds
    : [];
  const resolvedUnitIds = assignedUnits
    .map((unitId) =>
      normalizeStaffIdInput(unitId),
    )
    .filter((unitId) =>
      mongoose.Types.ObjectId.isValid(
        unitId,
      ),
    );

  return Array.from(
    new Set(resolvedUnitIds),
  );
}

function resolveTaskProgressTargetPlots(
  task,
  {
    fallbackTotalUnits = 0,
  } = {},
) {
  const assignedStaffIds =
    resolveTaskAssignedStaffIds(task);
  const assignedUnitIds =
    resolveTaskAssignedUnitIds(task);
  const requiredHeadcount = Math.max(
    0,
    Number(task?.requiredHeadcount || 0),
  );
  const staffingTarget = Math.max(
    1,
    Math.max(
      requiredHeadcount,
      assignedStaffIds.length,
    ),
  );
  const unitTarget =
    assignedUnitIds.length;
  const weightTarget = Math.max(
    1,
    Number(task?.weight || 0),
  );
  const fallbackUnitTarget = Math.max(
    0,
    Number(fallbackTotalUnits || 0),
  );
  if (unitTarget > 0) {
    return Math.max(
      weightTarget,
      unitTarget,
    );
  }
  if (fallbackUnitTarget > 0) {
    return Math.max(
      weightTarget,
      fallbackUnitTarget,
    );
  }
  return Math.max(
    weightTarget,
    staffingTarget,
  );
}

function resolveTaskProgressTargetPlotUnits(
  task,
  {
    fallbackTotalUnits = 0,
  } = {},
) {
  return (
    convertPlotsToPlotUnits(
      resolveTaskProgressTargetPlots(task, {
        fallbackTotalUnits,
      }),
    ) || 0
  );
}

function resolveTaskProgressProofCount(
  actualPlots,
) {
  const normalizedActualPlots = Math.max(
    0,
    Number(actualPlots || 0),
  );
  if (!Number.isFinite(normalizedActualPlots) || normalizedActualPlots <= 0) {
    return 0;
  }
  return Math.ceil(normalizedActualPlots);
}

function normalizeTaskProgressProofFiles(
  files,
) {
  if (!Array.isArray(files)) {
    return [];
  }
  return files.filter((file) =>
    Boolean(
      file &&
        file.buffer &&
        file.buffer.length > 0,
    ),
  );
}

function resolveTaskDayLedgerConfig({
  task,
  plan,
}) {
  const fallbackTotalUnits = Math.max(
    0,
    Number(
      plan?.workloadContext
        ?.totalWorkUnits || 0,
    ),
  );
  const unitTarget =
    resolveTaskProgressTargetPlots(task, {
      fallbackTotalUnits,
    });
  return {
    unitTarget: Math.max(
      0,
      Number(unitTarget || 0),
    ),
    unitType: resolveLedgerUnitType({
      plan,
    }),
    activityTargets:
      resolveLedgerActivityTargetsFromPlan(
        {
          plan,
        },
      ),
    activityUnits:
      resolveLedgerActivityUnitsFromPlan({
        plan,
      }),
  };
}

function buildTaskProgressRowKey({
  staffId,
  unitId,
  workDate,
}) {
  const normalizedStaffId =
    normalizeStaffIdInput(staffId);
  const normalizedUnitId =
    normalizeStaffIdInput(unitId);
  const normalizedWorkDate =
    normalizeWorkDateToDayStart(
      workDate,
    );
  return [
    normalizedStaffId,
    normalizedUnitId,
    normalizedWorkDate ?
      normalizedWorkDate.toISOString()
    : "",
  ].join(":");
}

function singularizePlanUnitWord(
  value,
) {
  const normalized =
    (value || "").toString().trim();
  if (!normalized) {
    return "";
  }
  const lower =
    normalized.toLowerCase();
  if (
    lower.endsWith("ies") &&
    normalized.length > 3
  ) {
    return `${normalized.slice(0, -3)}y`;
  }
  if (
    lower.endsWith("ches") ||
    lower.endsWith("shes") ||
    lower.endsWith("xes") ||
    lower.endsWith("zes")
  ) {
    return normalized.slice(0, -2);
  }
  if (
    lower.endsWith("s") &&
    !lower.endsWith("ss")
  ) {
    return normalized.slice(0, -1);
  }
  return normalized;
}

function formatPlanUnitLabelStem(
  value,
) {
  const normalized =
    normalizeProductionWorkUnitLabelInput(
      value,
      {
        fallback: "work unit",
      },
    );
  const tokens = normalized
    .split(" ")
    .filter(Boolean);
  if (tokens.length === 0) {
    return "Work Unit";
  }
  const lastToken =
    singularizePlanUnitWord(
      tokens[tokens.length - 1],
    );
  tokens[tokens.length - 1] =
    lastToken || tokens[tokens.length - 1];
  return tokens
    .map((token) =>
      token ?
        `${token.charAt(0).toUpperCase()}${token.slice(1)}`
      : "",
    )
    .join(" ");
}

function buildCanonicalPlanUnitLabel({
  workUnitLabel,
  unitIndex,
}) {
  const safeIndex = Math.max(
    1,
    Math.floor(Number(unitIndex || 1)),
  );
  return `${formatPlanUnitLabelStem(workUnitLabel)} ${safeIndex}`;
}

function normalizePlanUnitMatchText(
  value,
) {
  const normalized =
    (value || "")
      .toString()
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  return normalized ?
      ` ${normalized} `
    : "";
}

function resolveExplicitPlanUnitMatchesForTask({
  task,
  orderedPlanUnits,
}) {
  const haystack =
    normalizePlanUnitMatchText(
      `${task?.title || ""} ${task?.instructions || ""}`,
    );
  if (!haystack) {
    return [];
  }
  return orderedPlanUnits
    .filter((unit) => {
      const normalizedLabel =
        normalizePlanUnitMatchText(
          unit?.label,
        );
      return (
        normalizedLabel &&
        haystack.includes(
          normalizedLabel,
        )
      );
    })
    .map((unit) =>
      normalizeStaffIdInput(unit?._id),
    )
    .filter(Boolean);
}

function buildSequentialPlanUnitSelection({
  orderedPlanUnits,
  startIndex,
  count,
  excludedUnitIds = [],
}) {
  if (
    !Array.isArray(orderedPlanUnits) ||
    orderedPlanUnits.length === 0
  ) {
    return [];
  }
  const targetCount = Math.max(
    0,
    Math.min(
      orderedPlanUnits.length,
      Math.floor(Number(count || 0)),
    ),
  );
  if (targetCount === 0) {
    return [];
  }
  const excludedIdSet = new Set(
    excludedUnitIds
      .map((value) =>
        normalizeStaffIdInput(value),
      )
      .filter(Boolean),
  );
  const selected = [];
  const safeStartIndex =
    Math.max(
      0,
      Math.floor(Number(startIndex || 0)),
    ) % orderedPlanUnits.length;
  for (
    let offset = 0;
    offset < orderedPlanUnits.length &&
    selected.length < targetCount;
    offset += 1
  ) {
    const planUnit =
      orderedPlanUnits[
        (safeStartIndex + offset) %
          orderedPlanUnits.length
      ];
    const unitId =
      normalizeStaffIdInput(
        planUnit?._id,
      );
    if (
      !unitId ||
      excludedIdSet.has(unitId)
    ) {
      continue;
    }
    excludedIdSet.add(unitId);
    selected.push(unitId);
  }
  return selected;
}

function assignCanonicalPlanUnitsToTasks({
  scheduledTasks,
  planUnits,
}) {
  const orderedPlanUnits =
    (
      Array.isArray(planUnits) ?
        [...planUnits]
      : []
    ).sort(
      (left, right) =>
        Number(left?.unitIndex || 0) -
        Number(right?.unitIndex || 0),
    );
  if (orderedPlanUnits.length === 0) {
    return (
      Array.isArray(scheduledTasks) ?
        scheduledTasks
      : []
    ).map((task) => ({
      ...task,
      assignedUnitIds: [],
    }));
  }
  const validUnitIdSet = new Set(
    orderedPlanUnits
      .map((unit) =>
        normalizeStaffIdInput(
          unit?._id,
        ),
      )
      .filter(Boolean),
  );
  const unitIndexById = new Map(
    orderedPlanUnits.map((unit, index) => [
      normalizeStaffIdInput(unit?._id),
      index,
    ]),
  );
  let unitCursor = 0;

  return (
    Array.isArray(scheduledTasks) ?
      scheduledTasks
    : []
  ).map((task) => {
    const persistedUnitIds =
      resolveTaskAssignedUnitIds(task)
        .filter((unitId) =>
          validUnitIdSet.has(unitId),
        );
    const coverageUnits = Math.max(
      1,
      Math.min(
        orderedPlanUnits.length,
        resolveDraftTaskCoverageUnits(task),
      ),
    );
    let resolvedUnitIds =
      persistedUnitIds;

    if (resolvedUnitIds.length === 0) {
      const explicitMatchedUnitIds =
        resolveExplicitPlanUnitMatchesForTask(
          {
            task,
            orderedPlanUnits,
          },
        );
      resolvedUnitIds =
        explicitMatchedUnitIds.slice(
          0,
          coverageUnits,
        );
      if (
        resolvedUnitIds.length <
        coverageUnits
      ) {
        resolvedUnitIds = [
          ...resolvedUnitIds,
          ...buildSequentialPlanUnitSelection(
            {
              orderedPlanUnits,
              startIndex:
                unitCursor,
              count:
                coverageUnits -
                resolvedUnitIds.length,
              excludedUnitIds:
                resolvedUnitIds,
            },
          ),
        ];
      }
    }

    const lastAssignedUnitId =
      resolvedUnitIds[
        resolvedUnitIds.length - 1
      ];
    const nextCursorIndex =
      unitIndexById.get(
        lastAssignedUnitId,
      );
    if (
      Number.isInteger(
        nextCursorIndex,
      )
    ) {
      unitCursor =
        (nextCursorIndex + 1) %
        orderedPlanUnits.length;
    }

    return {
      ...task,
      assignedUnitIds:
        resolvedUnitIds,
    };
  });
}

async function seedCanonicalPlanUnits({
  planId,
  workloadContext,
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enablePlanUnits
  ) {
    return [];
  }
  const safePlanId =
    normalizeStaffIdInput(planId);
  if (
    !mongoose.Types.ObjectId.isValid(
      safePlanId,
    )
  ) {
    return [];
  }
  const totalWorkUnits =
    parseWorkloadContextTotalUnits(
      workloadContext,
    );
  if (totalWorkUnits <= 0) {
    return [];
  }
  const workUnitLabel =
    normalizeProductionWorkUnitLabelInput(
      workloadContext?.workUnitLabel ||
        workloadContext?.workUnitType,
      {
        fallback: "work unit",
      },
    );
  const planUnits = Array.from(
    { length: totalWorkUnits },
    (_, index) => ({
      planId: safePlanId,
      unitIndex: index + 1,
      label:
        buildCanonicalPlanUnitLabel(
          {
            workUnitLabel,
            unitIndex: index + 1,
          },
        ),
    }),
  );
  try {
    return await PlanUnit.insertMany(
      planUnits,
    );
  } catch (err) {
    const hasDuplicateUnitIndexError =
      err?.code === 11000 ||
      (
        Array.isArray(
          err?.writeErrors,
        ) &&
        err.writeErrors.some(
          (writeErr) =>
            writeErr?.code === 11000,
        )
      );
    if (!hasDuplicateUnitIndexError) {
      throw err;
    }
    return PlanUnit.find({
      planId: safePlanId,
    })
      .sort({ unitIndex: 1 })
      .lean();
  }
}

function haveMatchingAssignedUnitIds(
  left,
  right,
) {
  const leftIds =
    resolveTaskAssignedUnitIds({
      assignedUnitIds: left,
    });
  const rightIds =
    resolveTaskAssignedUnitIds({
      assignedUnitIds: right,
    });
  if (leftIds.length !== rightIds.length) {
    return false;
  }
  return leftIds.every(
    (unitId, index) =>
      unitId === rightIds[index],
  );
}

async function ensureCanonicalPlanUnitsForPlan({
  plan,
  tasks,
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enablePlanUnits
  ) {
    return {
      planUnits: [],
      tasks:
        Array.isArray(tasks) ?
          tasks
        : [],
      repairedTaskCount: 0,
    };
  }
  const safePlanId =
    normalizeStaffIdInput(plan?._id);
  if (
    !mongoose.Types.ObjectId.isValid(
      safePlanId,
    )
  ) {
    return {
      planUnits: [],
      tasks:
        Array.isArray(tasks) ?
          tasks
        : [],
      repairedTaskCount: 0,
    };
  }

  let planUnits = await PlanUnit.find({
    planId: safePlanId,
  })
    .sort({ unitIndex: 1 })
    .lean();

  if (planUnits.length === 0) {
    const seededPlanUnits =
      await seedCanonicalPlanUnits({
        planId: safePlanId,
        workloadContext:
          plan?.workloadContext,
      });
    planUnits =
      Array.isArray(seededPlanUnits) ?
        seededPlanUnits.map((unit) =>
          unit?.toObject ?
            unit.toObject()
          : unit,
        )
      : [];
  }

  const orderedTasks =
    Array.isArray(tasks) ?
      tasks
    : await ProductionTask.find({
        planId: safePlanId,
      })
        .sort({
          startDate: 1,
          dueDate: 1,
          manualSortOrder: 1,
          _id: 1,
        })
        .lean();

  if (
    planUnits.length === 0 ||
    orderedTasks.length === 0
  ) {
    return {
      planUnits,
      tasks: orderedTasks,
      repairedTaskCount: 0,
    };
  }

  const normalizedTasks =
    assignCanonicalPlanUnitsToTasks({
      scheduledTasks:
        orderedTasks,
      planUnits,
    });
  const taskUpdates = [];

  normalizedTasks.forEach(
    (task, index) => {
      const currentTask =
        orderedTasks[index];
      const taskId =
        normalizeStaffIdInput(
          currentTask?._id,
        );
      if (
        !mongoose.Types.ObjectId.isValid(
          taskId,
        )
      ) {
        return;
      }
      const nextAssignedUnitIds =
        resolveTaskAssignedUnitIds(task);
      if (
        haveMatchingAssignedUnitIds(
          currentTask
            ?.assignedUnitIds,
          nextAssignedUnitIds,
        )
      ) {
        return;
      }
      taskUpdates.push({
        updateOne: {
          filter: {
            _id: taskId,
            planId: safePlanId,
          },
          update: {
            $set: {
              assignedUnitIds:
                nextAssignedUnitIds,
            },
          },
        },
      });
    },
  );

  if (taskUpdates.length > 0) {
    await ProductionTask.bulkWrite(
      taskUpdates,
    );
  }

  return {
    planUnits,
    tasks: normalizedTasks,
    repairedTaskCount:
      taskUpdates.length,
  };
}

// UNIT-LIFECYCLE
// WHY: Stage 5 scheduling stores offsets in day units and must keep deterministic rounding.
function roundScheduleOffsetDays(
  value,
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return 0;
  }
  return Number(parsed.toFixed(6));
}

// UNIT-LIFECYCLE
// WHY: Shift propagation must update dates with a deterministic day delta per unit.
function shiftDateByDays(
  value,
  shiftDays,
) {
  const parsed = parseDateInput(value);
  if (!parsed) {
    return null;
  }
  const safeShiftDays =
    Number(shiftDays);
  if (!Number.isFinite(safeShiftDays)) {
    return new Date(parsed);
  }
  return new Date(
    parsed.getTime() +
      safeShiftDays * MS_PER_DAY,
  );
}

// UNIT-LIFECYCLE
// WHY: Monitoring tasks are relative by lifecycle design while finite tasks remain absolute.
function resolveTaskTimingModeFromPhaseType(
  phaseType,
) {
  return (
      normalizeProductionPhaseTypeInput(
        phaseType,
      ) ===
        PRODUCTION_PHASE_TYPE_MONITORING
    ) ?
      PRODUCTION_TASK_TIMING_MODE_RELATIVE
    : PRODUCTION_TASK_TIMING_MODE_ABSOLUTE;
}

// UNIT-LIFECYCLE
// WHY: Delay propagation must only fire when execution truth indicates a real shortfall or explicit delay reason.
function resolveUnitDelayShiftDaysFromProgress(
  progress,
) {
  const expectedUnits = Math.max(
    0,
    Number(
      progress?.expectedPlotUnits || 0,
    ),
  );
  const actualUnits = Math.max(
    0,
    Number(
      progress?.actualPlotUnits || 0,
    ),
  );
  const delayReason =
    normalizeTaskProgressDelayReason(
      progress?.delayReason,
    );
  const hasShortfall =
    expectedUnits > 0 &&
    actualUnits < expectedUnits;
  const hasExplicitDelayReason =
    delayReason !== "none";

  if (
    !hasShortfall &&
    !hasExplicitDelayReason
  ) {
    return 0;
  }
  return UNIT_DELAY_FALLBACK_SHIFT_DAYS;
}

// UNIT-LIFECYCLE
// WHY: Relative monitoring rows need stable offsets from finite reference events.
function resolveOffsetDaysFromReferenceDate({
  referenceDate,
  targetDate,
}) {
  const safeReference = parseDateInput(
    referenceDate,
  );
  const safeTarget =
    parseDateInput(targetDate);
  if (!safeReference || !safeTarget) {
    return 0;
  }
  return roundScheduleOffsetDays(
    (safeTarget.getTime() -
      safeReference.getTime()) /
      MS_PER_DAY,
  );
}

// WHY: Assistant payload requires second-level ISO timestamps without milliseconds.
function formatIsoDateTimeSeconds(
  value,
) {
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
    : [])
    .map((entry) =>
      entry == null ? "" : (
        entry.toString().trim()
      ),
    )
    .filter(Boolean);
  return Array.from(
    new Set(list),
  ).slice(0, 6);
}

function resolveAssistantRequiredField(
  value,
) {
  const parsed =
    value == null ? "" : (
      value.toString().trim()
    );
  if (
    PRODUCTION_ASSISTANT_REQUIRED_FIELDS.includes(
      parsed,
    )
  ) {
    return parsed;
  }
  return "productDescription";
}

function sanitizeProductionAssistantFailureMessage({
  message,
  errorCode,
  classification,
}) {
  const rawMessage = (
    message == null ? "" : message.toString()
  ).trim();
  const normalizedMessage =
    rawMessage.toLowerCase();
  const normalizedErrorCode = (
    errorCode == null ? "" : errorCode.toString()
  )
    .trim()
    .toUpperCase();
  const normalizedClassification = (
    classification == null ?
      ""
    : classification.toString()
  )
    .trim()
    .toUpperCase();

  if (
    normalizedMessage.includes(
      "cannot create a new collection",
    ) ||
    normalizedMessage.includes(
      "too many collections",
    ) ||
    normalizedMessage.includes(
      "already using",
    )
  ) {
    return "Planning storage is under pressure right now. Your context is still available, so retry draft generation.";
  }

  if (
    normalizedErrorCode ===
      "PRODUCTION_AI_PLANNER_V2_LIFECYCLE_AI_PARSE_FAILED" ||
    normalizedMessage.includes(
      "did not return valid json",
    )
  ) {
    return "I could not structure the product lifecycle on the first try. Retry draft generation and I will regenerate it.";
  }

  if (
    normalizedClassification ===
    "PROVIDER_REJECTED_FORMAT"
  ) {
    return "The planning assistant returned an invalid format. Retry draft generation with the same context.";
  }

  return rawMessage ||
    "I could not reach the planning assistant provider right now, but your context is saved.";
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
              draftProduct?.lifecycleDaysEstimate ||
                84,
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
  const normalized = (userInput || "")
    .toString()
    .trim()
    .toLowerCase();
  if (!normalized) return 84;
  if (normalized.includes("rice")) {
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
  const raw = (userInput || "")
    .toString()
    .trim()
    .replace(/\s+/g, " ");
  const titleWords = raw
    .split(" ")
    .filter(Boolean)
    .slice(0, 4)
    .map(
      (word) =>
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
    const name = (product?.name || "")
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
    normalizedTokens.forEach(
      (token) => {
        if (token.length < 3) {
          return;
        }
        if (name.includes(token)) {
          score += 3;
        }
        if (
          description.includes(token)
        ) {
          score += 1;
        }
      },
    );

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

function escapeRegexPattern(value) {
  return (value || "")
    .toString()
    .replace(
      /[.*+?^${}()|[\]\\]/g,
      "\\$&",
    );
}

function normalizeAssistantCropSearchLimit(
  value,
) {
  const parsed = Math.floor(
    Number(value || 8),
  );
  if (!Number.isFinite(parsed)) {
    return 8;
  }
  return Math.min(12, Math.max(1, parsed));
}

function isExactAssistantCropMatch({
  query,
  item,
}) {
  const normalizedQuery =
    (
      query == null ? "" : query.toString()
    )
      .trim()
      .toLowerCase();
  if (!normalizedQuery) {
    return false;
  }

  const candidates = [
    item?.name,
    item?.cropKey,
    ...(
      Array.isArray(item?.aliases) ?
        item.aliases
      : []
    ),
  ]
    .map((entry) =>
      (
        entry == null ? "" : entry.toString()
      )
        .trim()
        .toLowerCase(),
    )
    .filter(Boolean);

  return candidates.some(
    (candidate) =>
      candidate === normalizedQuery,
  );
}

async function buildAssistantPlannerCropSearchResults(
  {
    businessId,
    query,
    limit,
    context = {},
  },
) {
  const safeLimit = Math.min(
    20,
    Math.max(
      1,
      Math.floor(Number(limit) || 8),
    ),
  );
  const storedItems =
    await searchStoredLifecycleProfiles({
      businessId,
      query,
      limit: safeLimit,
      domainContext: "farm",
    });
  const items = storedItems;
  if (items.length === 0) {
    return [];
  }

  const seenDisplayKeys = new Set();
  const uniqueItems =
    items.filter((item) => {
      const displayKey = [
        (
          item.displayName ||
          item.name ||
          ""
        )
          .toString()
          .trim()
          .toLowerCase(),
        (
          item.cropKey || ""
        )
          .toString()
          .trim()
          .toLowerCase(),
      ].join("::");
      if (!displayKey) {
        return false;
      }
      if (seenDisplayKeys.has(displayKey)) {
        return false;
      }
      seenDisplayKeys.add(displayKey);
      return true;
    })
      .slice(0, safeLimit);

  const productNames = Array.from(
    new Set(
      uniqueItems
        .flatMap((item) => [
          item.name,
          item.displayName,
        ])
        .map((name) =>
          (
            name == null ? "" : name.toString()
          ).trim(),
        )
        .filter(Boolean),
    ),
  );
  const existingProducts =
    await Product.find({
      businessId,
      deletedAt: null,
      name: {
        $in: productNames,
      },
    })
      .select({
        _id: 1,
        name: 1,
        isActive: 1,
      })
      .lean();
  const existingProductByName =
    new Map(
      existingProducts.map((product) => [
        product.name
          ?.toString()
          .trim()
          .toLowerCase(),
        product,
      ]),
    );

  return uniqueItems.map((item) => {
    const displayName =
      (
        item.displayName ||
        item.name ||
        ""
      )
        .toString()
        .trim();
    const normalizedDisplayName =
      displayName.toLowerCase();
    const normalizedCanonicalName =
      (
        item.name || ""
      )
        .toString()
        .trim()
        .toLowerCase();
    const linkedProduct =
      existingProductByName.get(
        normalizedDisplayName,
      ) ||
      existingProductByName.get(
        normalizedCanonicalName,
      ) || null;
    return {
      id: item.cropKey,
      cropKey: item.cropKey,
      name: displayName,
      aliases: Array.from(
        new Set(
          [
            displayName,
            ...(Array.isArray(
              item.aliases,
            ) ?
              item.aliases
            : []),
          ]
            .map((entry) =>
              (
                entry == null ?
                  ""
                : entry.toString()
              ).trim(),
            )
            .filter(Boolean),
        ),
      ),
      source: item.source,
      minDays: item.minDays || 0,
      maxDays: item.maxDays || 0,
      phases:
        Array.isArray(item.phases) ?
          item.phases
        : [],
      profileKind:
        item.profileKind || "crop",
      category:
        item.category || "",
      variety:
        item.variety || "",
      plantType:
        item.plantType || "",
      summary:
        item.summary || "",
      scientificName:
        item.scientificName || "",
      family:
        item.family || "",
      verificationStatus:
        item.verificationStatus || "",
      climate:
        item.climate || {},
      soil:
        item.soil || {},
      water:
        item.water || {},
      propagation:
        item.propagation || {},
      harvestWindow:
        item.harvestWindow || {},
      sourceProvenance:
        Array.isArray(
          item.sourceProvenance,
        ) ?
          item.sourceProvenance
        : [],
      linkedProductId:
        linkedProduct?._id
          ?.toString?.() || "",
      linkedProductName:
        linkedProduct?.name
          ?.toString?.() || "",
      linkedProductActive:
        linkedProduct?.isActive === true,
    };
  });
}

async function resolveAssistantPlannerProduct({
  businessId,
  actor,
  productSearchName,
  productCatalog,
}) {
  const normalizedSearchName =
    (
      productSearchName == null ?
        ""
      : productSearchName.toString()
    ).trim();
  if (!normalizedSearchName) {
    return null;
  }

  const normalizedCropKey =
    resolveAgricultureCropKey({
      productName:
        normalizedSearchName,
      cropSubtype: "",
    });
  const canonicalProductName =
    humanizeCropKey(
      normalizedCropKey,
    ) || normalizedSearchName;
  const exactCatalogMatch =
    Array.isArray(productCatalog) ?
      productCatalog.find((product) => {
        const normalizedName =
          (
            product?.name || ""
          )
            .toString()
            .trim()
            .toLowerCase();
        return (
          normalizedName ===
          canonicalProductName
            .trim()
            .toLowerCase()
        );
      })
    : null;
  if (exactCatalogMatch?._id) {
    return businessProductService.getProductById({
      businessId,
      id: exactCatalogMatch._id,
    });
  }

  const existingProduct =
    await Product.findOne({
      businessId,
      deletedAt: null,
      name: {
        $regex: new RegExp(
          `^${escapeRegexPattern(
            canonicalProductName,
          )}$`,
          "i",
        ),
      },
    });
  if (existingProduct) {
    return existingProduct;
  }

  return businessProductService.createProduct(
    {
      businessId,
      actor,
      data: {
        name: canonicalProductName,
        description:
          "Planner-linked farm crop synced from the agriculture lifecycle catalog.",
        price: 0,
        stock: 0,
        imageUrl: "",
        isActive: false,
      },
    },
  );
}

function normalizeAssistantWarningList(
  warnings,
) {
  const list = (
    Array.isArray(warnings) ? warnings
    : [])
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
              .trim() || "Plan warning",
        };
      }
      const text =
        warning == null ? "" : (
          warning.toString().trim()
        );
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
    (
      aiDraftResponse?.schedulePolicy &&
      typeof aiDraftResponse.schedulePolicy ===
        "object"
    ) ?
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
  const hour = parsedClock?.hour || 9;
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

function resolveImportedTaskPinnedDay(
  task,
) {
  const sourceTemplateKey = (
    task?.sourceTemplateKey || ""
  )
    .toString()
    .trim()
    .toLowerCase();
  if (
    !sourceTemplateKey.startsWith(
      "imported_source_day_",
    )
  ) {
    return null;
  }
  const instructions = (
    task?.instructions || ""
  )
    .toString()
    .trim();
  const match =
    instructions.match(
      IMPORTED_PROJECT_DAY_PATTERN,
    );
  const isoDate =
    match?.[1]
      ?.toString()
      .trim() || "";
  if (!isoDate) {
    return null;
  }
  return (
    parseDateInput(
      `${isoDate}T00:00:00.000Z`,
    ) ||
    parseDateInput(isoDate)
  );
}

function normalizeTaskManualSortOrder(
  value,
  fallback = 0,
) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return Math.max(
      0,
      Math.floor(Number(fallback) || 0),
    );
  }
  return Math.max(
    0,
    Math.floor(parsed),
  );
}

function resolveTaskPinnedDateRange({
  task,
  schedulePolicy,
}) {
  const explicitStart =
    parseDateInput(task?.startDate);
  const explicitDue =
    parseDateInput(task?.dueDate);
  if (
    explicitStart &&
    explicitDue &&
    explicitDue > explicitStart
  ) {
    return {
      startDate: explicitStart,
      dueDate: explicitDue,
      source: "explicit_datetime",
    };
  }

  const defaultBlock =
    schedulePolicy?.blocks?.[0] ||
    WORK_SCHEDULE_FALLBACK_BLOCKS[0];
  const pinnedDay =
    resolveImportedTaskPinnedDay(task);
  if (!pinnedDay) {
    return null;
  }
  const pinnedStart =
    parseDateInput(
      buildIsoDateTimeFromDayClock({
        day: pinnedDay,
        clock:
          defaultBlock?.start,
      }),
    );
  const pinnedDue =
    parseDateInput(
      buildIsoDateTimeFromDayClock({
        day: pinnedDay,
        clock:
          defaultBlock?.end ||
          defaultBlock?.start,
      }),
    );
  if (
    !pinnedStart ||
    !pinnedDue ||
    pinnedDue <= pinnedStart
  ) {
    return null;
  }
  return {
    startDate: pinnedStart,
    dueDate: pinnedDue,
    source: "imported_day",
  };
}

function isPinnedTaskDateRangeWithinPlan({
  startDate,
  dueDate,
  planStart,
  planEnd,
}) {
  if (
    !startDate ||
    !dueDate ||
    !planStart ||
    !planEnd
  ) {
    return false;
  }
  const normalizedPlanStart =
    new Date(
      planStart.getFullYear(),
      planStart.getMonth(),
      planStart.getDate(),
      0,
      0,
      0,
      0,
    );
  const normalizedPlanEndExclusive =
    new Date(
      planEnd.getFullYear(),
      planEnd.getMonth(),
      planEnd.getDate() + 1,
      0,
      0,
      0,
      0,
    );
  return (
    startDate >= normalizedPlanStart &&
    dueDate <= normalizedPlanEndExclusive
  );
}

function assertPinnedTaskDateRanges({
  tasks,
  planStart,
  planEnd,
}) {
  (Array.isArray(tasks) ? tasks : []).forEach(
    (task) => {
      const startProvided =
        task?.startDate != null &&
        `${task.startDate}`.trim()
          .length > 0;
      const dueProvided =
        task?.dueDate != null &&
        `${task.dueDate}`.trim()
          .length > 0;
      if (
        !startProvided &&
        !dueProvided
      ) {
        return;
      }
      const pinnedRange =
        resolveTaskPinnedDateRange({
          task,
        });
      if (!pinnedRange) {
        throw new Error(
          PRODUCTION_COPY.TASK_SCHEDULE_INVALID,
        );
      }
      if (
        !isPinnedTaskDateRangeWithinPlan(
          {
            startDate:
              pinnedRange.startDate,
            dueDate:
              pinnedRange.dueDate,
            planStart,
            planEnd,
          },
        )
      ) {
        throw new Error(
          PRODUCTION_COPY.TASK_SCHEDULE_OUTSIDE_PLAN,
        );
      }
    },
  );
}

function applyPinnedTaskScheduleOverrides({
  sourceTasks,
  scheduledTasks,
  schedulePolicy,
}) {
  return scheduledTasks.map(
    (scheduledTask, index) => {
      const sourceTask =
        sourceTasks[index];
      const pinnedRange =
        resolveTaskPinnedDateRange({
          task: sourceTask,
          schedulePolicy,
        });
      const manualSortOrder =
        normalizeTaskManualSortOrder(
          sourceTask?.manualSortOrder,
          index,
        );
      if (!pinnedRange) {
        return {
          ...scheduledTask,
          manualSortOrder,
        };
      }
      return {
        ...scheduledTask,
        startDate:
          pinnedRange.startDate,
        dueDate:
          pinnedRange.dueDate,
        manualSortOrder,
      };
    },
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

function countAssistantPhaseTasks(
  phases,
) {
  return (
    Array.isArray(phases) ? phases : (
      []
    )).reduce((sum, phase) => {
    const tasks =
      Array.isArray(phase?.tasks) ?
        phase.tasks
      : [];
    return sum + tasks.length;
  }, 0);
}

function toUtcDayStart(value) {
  return new Date(
    Date.UTC(
      value.getUTCFullYear(),
      value.getUTCMonth(),
      value.getUTCDate(),
    ),
  );
}

function toUtcWeekMonday(value) {
  const dayStart = toUtcDayStart(value);
  const weekday =
    dayStart.getUTCDay() === 0 ?
      7
    : dayStart.getUTCDay();
  return new Date(
    dayStart.getTime() -
      (weekday - 1) * MS_PER_DAY,
  );
}

function isAssistantExecutionRole(
  roleValue,
) {
  const normalizedRole =
    normalizeStaffIdInput(
      roleValue,
    ).toLowerCase();
  return (
    normalizedRole === "farmer" ||
    normalizedRole === "field_agent"
  );
}

function collectAssistantScheduledExecutionWeekKeys(
  phases,
) {
  const weekKeys = new Set();
  const safePhases =
    Array.isArray(phases) ? phases : [];
  for (const phase of safePhases) {
    const tasks =
      Array.isArray(phase?.tasks) ?
        phase.tasks
      : [];
    for (const task of tasks) {
      if (
        !isAssistantExecutionRole(
          task?.roleRequired,
        )
      ) {
        continue;
      }
      const parsedStart =
        parseDateInput(task?.startDate);
      const parsedDue = parseDateInput(
        task?.dueDate,
      );
      const anchorDate =
        parsedStart || parsedDue;
      if (!anchorDate) {
        continue;
      }
      const weekKey = toUtcWeekMonday(
        anchorDate,
      )
        .toISOString()
        .slice(0, 10);
      weekKeys.add(weekKey);
    }
  }
  return weekKeys;
}

function resolveFirstAllowedDayForWeek({
  weekStart,
  allowedWeekDays,
  rangeStart,
  rangeEnd,
}) {
  for (
    let offset = 0;
    offset < 7;
    offset += 1
  ) {
    const day = new Date(
      weekStart.getTime() +
        offset * MS_PER_DAY,
    );
    if (
      day.getTime() <
        rangeStart.getTime() ||
      day.getTime() > rangeEnd.getTime()
    ) {
      continue;
    }
    const weekDay =
      day.getUTCDay() === 0 ?
        7
      : day.getUTCDay();
    if (
      allowedWeekDays.includes(weekDay)
    ) {
      return day;
    }
  }
  return null;
}

// WHY: Sparse AI plans should be padded with minimal weekly continuity tasks so assistant preview does not collapse into empty weeks.
function buildAssistantSparseWeeklyTopUpPhase({
  resolvedRange,
  productName,
  schedulePolicy,
  existingPhases,
  additionalTaskLimit,
}) {
  const safeAdditionalLimit =
    (
      Number.isFinite(
        additionalTaskLimit,
      ) &&
      Number(additionalTaskLimit) > 0
    ) ?
      Math.floor(
        Number(additionalTaskLimit),
      )
    : 0;
  if (safeAdditionalLimit < 1) {
    return null;
  }
  const rangeStart =
    parseDateInput(
      `${resolvedRange.startDate}T00:00:00.000Z`,
    ) ||
    parseDateInput(
      resolvedRange.startDate,
    );
  const rangeEnd =
    parseDateInput(
      `${resolvedRange.endDate}T00:00:00.000Z`,
    ) ||
    parseDateInput(
      resolvedRange.endDate,
    );
  if (!rangeStart || !rangeEnd) {
    return null;
  }

  const normalizedPolicy =
    normalizeSchedulePolicyInput(
      schedulePolicy,
      buildDefaultSchedulePolicy(),
    );
  const allowedWeekDays =
    normalizeWorkWeekDaysInput(
      normalizedPolicy?.workWeekDays,
    );
  const scheduleBlocks =
    (
      Array.isArray(
        normalizedPolicy?.blocks,
      ) &&
      normalizedPolicy.blocks.length > 0
    ) ?
      normalizedPolicy.blocks
    : WORK_SCHEDULE_FALLBACK_BLOCKS;
  const primaryBlock =
    scheduleBlocks[0] ||
    WORK_SCHEDULE_FALLBACK_BLOCKS[0];
  const coveredExecutionWeekKeys =
    collectAssistantScheduledExecutionWeekKeys(
      existingPhases,
    );
  const safeProductName = (
    productName || "production"
  )
    .toString()
    .trim();
  const topUpTasks = [];
  let weekCursor =
    toUtcWeekMonday(rangeStart);
  const weekEnd =
    toUtcWeekMonday(rangeEnd);
  let templateIndex = 0;

  while (
    weekCursor.getTime() <=
      weekEnd.getTime() &&
    topUpTasks.length <
      safeAdditionalLimit
  ) {
    const weekKey = weekCursor
      .toISOString()
      .slice(0, 10);
    if (
      !coveredExecutionWeekKeys.has(
        weekKey,
      )
    ) {
      const workDay =
        resolveFirstAllowedDayForWeek({
          weekStart: weekCursor,
          allowedWeekDays,
          rangeStart:
            toUtcDayStart(rangeStart),
          rangeEnd:
            toUtcDayStart(rangeEnd),
        });
      if (workDay) {
        const titleTemplate =
          ASSISTANT_SPARSE_TOP_UP_TEMPLATES[
            templateIndex %
              ASSISTANT_SPARSE_TOP_UP_TEMPLATES.length
          ];
        topUpTasks.push({
          title: `${titleTemplate} - ${safeProductName}`,
          roleRequired: "farmer",
          requiredHeadcount: 3,
          weight: 1,
          instructions:
            "Weekly execution continuity task auto-added because AI returned sparse execution coverage across the selected range.",
          startDate:
            buildIsoDateTimeFromDayClock(
              {
                day: workDay,
                clock:
                  primaryBlock?.start,
              },
            ),
          dueDate:
            buildIsoDateTimeFromDayClock(
              {
                day: workDay,
                clock:
                  primaryBlock?.end,
              },
            ),
          assignedStaffProfileIds: [],
        });
        coveredExecutionWeekKeys.add(
          weekKey,
        );
        templateIndex += 1;
      }
    }
    weekCursor = new Date(
      weekCursor.getTime() +
        7 * MS_PER_DAY,
    );
  }

  if (topUpTasks.length === 0) {
    return null;
  }
  const maxPhaseOrder = (
    Array.isArray(existingPhases) ?
      existingPhases
    : []).reduce((maxOrder, phase) => {
    const order = Number(phase?.order);
    if (!Number.isFinite(order)) {
      return maxOrder;
    }
    return Math.max(
      maxOrder,
      Math.floor(order),
    );
  }, 0);

  debug(
    "BUSINESS CONTROLLER: assistant sparse schedule top-up generated",
    {
      startDate:
        resolvedRange.startDate,
      endDate: resolvedRange.endDate,
      existingTaskCount:
        countAssistantPhaseTasks(
          existingPhases,
        ),
      addedTaskCount: topUpTasks.length,
      coveredExecutionWeekCount:
        coveredExecutionWeekKeys.size,
      allowedWeekDays,
      nextPhaseOrder: maxPhaseOrder + 1,
    },
  );

  return {
    name: "Continuity and monitoring",
    order: maxPhaseOrder + 1,
    estimatedDays: Math.max(
      1,
      Math.min(14, topUpTasks.length),
    ),
    tasks: topUpTasks,
  };
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
      ...((
        Array.isArray(
          normalizedPolicy?.workWeekDays,
        )
      ) ?
        normalizedPolicy.workWeekDays
      : []),
    ]),
  ).sort((left, right) => left - right);
  const scheduleBlocks =
    (
      Array.isArray(
        normalizedPolicy?.blocks,
      ) &&
      normalizedPolicy.blocks.length > 0
    ) ?
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
    cursor.getTime() <=
    endDay.getTime();
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
      Math.floor(
        scheduledDayIndex / 7,
      ) + 1;
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
          roleRequired === "farmer" ? 2
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
      endDate: resolvedRange.endDate,
      days: resolvedRange.days,
      weeks: resolvedRange.weeks,
      allowedWeekDays,
      blockCount: scheduleBlocks.length,
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
  const plannerMeta =
    (
      aiDraftResponse?.plannerMeta &&
      typeof aiDraftResponse.plannerMeta ===
        "object"
    ) ?
      aiDraftResponse.plannerMeta
    : (
      aiDraftResponse?.draft?.plannerMeta &&
      typeof aiDraftResponse.draft
        ?.plannerMeta === "object"
    ) ?
      aiDraftResponse.draft.plannerMeta
    : null;
  const lifecycle =
    (
      aiDraftResponse?.lifecycle &&
      typeof aiDraftResponse.lifecycle ===
        "object"
    ) ?
      aiDraftResponse.lifecycle
    : (
      aiDraftResponse?.draft?.lifecycle &&
      typeof aiDraftResponse.draft
        ?.lifecycle === "object"
    ) ?
      aiDraftResponse.draft.lifecycle
    : null;
  const isPlannerV2 =
    plannerMeta?.version === "v2";
  const summary =
    (
      aiDraftResponse?.summary &&
      typeof aiDraftResponse.summary ===
        "object"
    ) ?
      aiDraftResponse.summary
    : {};
  const draft =
    (
      aiDraftResponse?.draft &&
      typeof aiDraftResponse.draft ===
        "object"
    ) ?
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
    draft.endDate?.toString().trim() ||
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
      const tasks =
        Array.isArray(phase?.tasks) ?
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
        tasks: tasks.map((task) => {
          const assignedStaffProfileIds =
            resolveTaskAssignedStaffIds(
              task,
            );
          const taskStart =
            task?.startDate ||
            buildIsoDateTimeFromDayClock(
              {
                day: rangeStartDay,
                clock:
                  defaultBlock?.start,
              },
            );
          const taskDue =
            task?.dueDate ||
            buildIsoDateTimeFromDayClock(
              {
                day: rangeStartDay,
                clock:
                  defaultBlock?.end,
              },
            );
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
            taskType:
              task?.taskType
                ?.toString()
                .trim() || "",
            sourceTemplateKey:
              task?.sourceTemplateKey
                ?.toString()
                .trim() || "",
            recurrenceGroupKey:
              task?.recurrenceGroupKey
                ?.toString()
                .trim() || "",
            occurrenceIndex: Math.max(
              0,
              Math.floor(
                Number(
                  task?.occurrenceIndex ||
                    0,
                ),
              ),
            ),
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
        }),
      };
    },
  );
  const existingTaskCount =
    countAssistantPhaseTasks(phases);
  const warnings =
    normalizeAssistantWarningList(
      aiDraftResponse?.warnings,
    );
  const rangeWeekCount = Math.max(
    1,
    Math.ceil(
      Number(resolvedRange.weeks) || 1,
    ),
  );
  const sparseFallbackThresholdCount =
    Math.max(
      ASSISTANT_SPARSE_TOP_UP_MIN_TARGET_TASKS,
      Math.ceil(
        rangeWeekCount *
          ASSISTANT_SPARSE_RECOVERY_FALLBACK_COVERAGE_RATIO,
      ),
    );
  const initialExecutionWeekCoverageCount =
    collectAssistantScheduledExecutionWeekKeys(
      phases,
    ).size;
  const hasLooseRecoveryWarning =
    warnings.some(
      (warning) =>
        warning?.code
          ?.toString()
          .trim()
          .toUpperCase() ===
        ASSISTANT_WARNING_CODE_ENVELOPE_LOOSE_RECOVERY,
    );
  const shouldPromoteSparseRecoveredDraftToFallback =
    existingTaskCount > 0 &&
    hasLooseRecoveryWarning &&
    (existingTaskCount <
      sparseFallbackThresholdCount ||
      initialExecutionWeekCoverageCount <
        sparseFallbackThresholdCount);
  let sparseRecoveredFallbackUsed = false;
  if (
    !isPlannerV2 &&
    (
      existingTaskCount === 0 ||
      shouldPromoteSparseRecoveredDraftToFallback
    )
  ) {
    phases =
      buildAssistantFallbackDailyPhases(
        {
          resolvedRange,
          productName:
            selectedProduct?.name ||
            draft.productName ||
            "",
          schedulePolicy,
        },
      );
    if (existingTaskCount === 0) {
      warnings.push({
        code: "DAILY_FALLBACK_GENERATED",
        message:
          "AI returned no scheduled tasks, so a full daily timeline was generated from start and end dates.",
      });
    } else {
      sparseRecoveredFallbackUsed = true;
      warnings.push({
        code: "SPARSE_RECOVERED_DRAFT_FALLBACK",
        message: `AI recovery returned ${existingTaskCount} task(s) with ${initialExecutionWeekCoverageCount}/${rangeWeekCount} execution week coverage. Replaced with deterministic fallback backbone before preview.`,
      });
      debug(
        "BUSINESS CONTROLLER: assistant sparse recovered draft promoted to deterministic fallback",
        {
          existingTaskCount,
          rangeWeekCount,
          initialExecutionWeekCoverageCount,
          sparseFallbackThresholdCount,
        },
      );
    }
  }
  const postFallbackTaskCount =
    countAssistantPhaseTasks(phases);
  const coveredExecutionWeekCountAfterFallback =
    collectAssistantScheduledExecutionWeekKeys(
      phases,
    ).size;
  const sparseTopUpTargetTaskCount =
    Math.max(
      0,
      Math.min(
        ASSISTANT_SPARSE_TOP_UP_MAX_TARGET_TASKS,
        rangeWeekCount -
          coveredExecutionWeekCountAfterFallback,
      ),
    );
  const sparseTopUpNeededCount =
    sparseTopUpTargetTaskCount;
  const shouldApplySparseTopUp =
    !isPlannerV2 &&
    postFallbackTaskCount > 0 &&
    sparseTopUpNeededCount > 0;
  let sparseTopUpAddedCount = 0;
  if (shouldApplySparseTopUp) {
    const sparseTopUpPhase =
      buildAssistantSparseWeeklyTopUpPhase(
        {
          resolvedRange,
          productName:
            selectedProduct?.name ||
            draft.productName ||
            "",
          schedulePolicy,
          existingPhases: phases,
          additionalTaskLimit:
            sparseTopUpNeededCount,
        },
      );
    if (sparseTopUpPhase) {
      phases = [
        ...phases,
        sparseTopUpPhase,
      ];
      sparseTopUpAddedCount =
        sparseTopUpPhase.tasks.length;
      warnings.push({
        code: "SPARSE_SCHEDULE_TOP_UP",
        message: `AI returned ${postFallbackTaskCount} task(s) across ${resolvedRange.weeks} week(s). Added ${sparseTopUpAddedCount} weekly execution continuity task(s) to reduce empty planning weeks.`,
      });
    }
  }
  const totalTaskCount =
    countAssistantPhaseTasks(phases);
  debug(
    "BUSINESS CONTROLLER: assistant plan payload normalized",
    {
      startDate:
        resolvedRange.startDate,
      endDate: resolvedRange.endDate,
      weeks: resolvedRange.weeks,
      days: resolvedRange.days,
      phaseCount: phases.length,
      taskCount: totalTaskCount,
      fallbackUsed:
        !isPlannerV2 &&
        (
          existingTaskCount === 0 ||
          sparseRecoveredFallbackUsed
        ),
      sparseRecoveredFallbackUsed,
      initialExecutionWeekCoverageCount,
      coveredExecutionWeekCountAfterFallback:
        coveredExecutionWeekCountAfterFallback,
      rangeWeekCount,
      sparseFallbackThresholdCount,
      sparseTopUpApplied:
        sparseTopUpAddedCount > 0,
      sparseTopUpAddedCount,
      sparseTopUpTargetTaskCount,
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
    plannerMeta,
    lifecycle,
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

function stripTaskProgressRejectNotes(
  notes,
) {
  return (notes || "")
    .toString()
    .split("\n")
    .filter(
      (line) =>
        !line.includes(
          TASK_PROGRESS_REJECTION_NOTE_PREFIX,
        ),
    )
    .join("\n")
    .trim();
}

// WHY: Timeline indicators must distinguish pending vs approved vs reviewed issues.
function resolveTaskProgressApprovalState(
  record,
) {
  if (record?.approvedAt) {
    return TASK_PROGRESS_APPROVAL_APPROVED;
  }

  const notes =
    record?.notes?.toString() || "";
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
    await TaskProgress.findById(
      progressId,
    );
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

// UNIT-LIFECYCLE
// WHY: Phase gating needs a fast deterministic count of approved-completed units per phase.
async function getCompletedUnitCount({
  planId,
  phaseId,
}) {
  if (
    !mongoose.Types.ObjectId.isValid(
      planId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      phaseId,
    )
  ) {
    return 0;
  }
  return ProductionPhaseUnitCompletion.countDocuments(
    {
      planId,
      phaseId,
    },
  );
}

// UNIT-LIFECYCLE
// WHY: Manager diagnostics and phase-gate explainability require actual completed unit ids.
async function getCompletedUnits({
  planId,
  phaseId,
}) {
  if (
    !mongoose.Types.ObjectId.isValid(
      planId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      phaseId,
    )
  ) {
    return [];
  }
  const rows =
    await ProductionPhaseUnitCompletion.find(
      {
        planId,
        phaseId,
      },
    )
      .select({ unitId: 1 })
      .lean();
  return rows
    .map((row) =>
      normalizeStaffIdInput(
        row?.unitId,
      ),
    )
    .filter(Boolean);
}

// PHASE-GATE-LAYER
// WHY: Draft sanitization needs deterministic phase-order lock state before task scheduling.
async function buildPhaseGateSnapshotForDraft({
  planId,
  businessId,
  draftPhases,
  defaultFiniteRequiredUnits = 0,
}) {
  const snapshotByOrder = new Map();
  const safeDraftPhases =
    Array.isArray(draftPhases) ?
      draftPhases
    : [];

  // WHY: Without a persisted plan context we still return normalized finite/monitoring metadata.
  if (
    !PRODUCTION_FEATURE_FLAGS.enablePhaseGate ||
    !mongoose.Types.ObjectId.isValid(
      planId,
    )
  ) {
    safeDraftPhases.forEach((phase) => {
      const phaseOrder = Math.max(
        1,
        Math.floor(
          Number(phase?.order || 1),
        ),
      );
      const phaseType =
        normalizeProductionPhaseTypeInput(
          phase?.phaseType,
        );
      const requiredUnits =
        normalizePhaseRequiredUnitsInput(
          phase?.requiredUnits,
          {
            fallback:
              (
                phaseType ===
                PRODUCTION_PHASE_TYPE_FINITE
              ) ?
                defaultFiniteRequiredUnits
              : 0,
          },
        );
      const remainingUnits =
        (
          phaseType ===
          PRODUCTION_PHASE_TYPE_MONITORING
        ) ?
          requiredUnits
        : requiredUnits;
      snapshotByOrder.set(phaseOrder, {
        phaseType,
        requiredUnits,
        completedUnitCount: 0,
        remainingUnits,
        isLocked: false,
        persistedPhaseId: null,
      });
    });
    return snapshotByOrder;
  }

  const persistedPlan =
    await ProductionPlan.findOne({
      _id: planId,
      businessId,
    })
      .select({ _id: 1 })
      .lean();
  if (!persistedPlan) {
    return snapshotByOrder;
  }

  const persistedPhases =
    await ProductionPhase.find({
      planId: persistedPlan._id,
    })
      .select({
        _id: 1,
        order: 1,
        phaseType: 1,
        requiredUnits: 1,
      })
      .lean();
  const persistedByOrder = new Map(
    persistedPhases.map((phase) => [
      Math.max(
        1,
        Math.floor(
          Number(phase?.order || 1),
        ),
      ),
      phase,
    ]),
  );

  const finitePersistedPhases =
    persistedPhases.filter(
      (phase) =>
        normalizeProductionPhaseTypeInput(
          phase?.phaseType,
        ) ===
        PRODUCTION_PHASE_TYPE_FINITE,
    );
  const finitePhaseIds =
    finitePersistedPhases
      .map(
        (phase) =>
          phase?._id?.toString?.() ||
          "",
      )
      .filter((phaseId) =>
        mongoose.Types.ObjectId.isValid(
          phaseId,
        ),
      )
      .map(
        (phaseId) =>
          new mongoose.Types.ObjectId(
            phaseId,
          ),
      );
  const completedCounts =
    finitePhaseIds.length > 0 ?
      await ProductionPhaseUnitCompletion.aggregate(
        [
          {
            $match: {
              planId: persistedPlan._id,
              phaseId: {
                $in: finitePhaseIds,
              },
            },
          },
          {
            $group: {
              _id: "$phaseId",
              count: {
                $sum: 1,
              },
            },
          },
        ],
      )
    : [];
  const completedCountByPhaseId =
    new Map(
      completedCounts.map((entry) => [
        entry?._id?.toString?.() || "",
        Math.max(
          0,
          Number(entry?.count || 0),
        ),
      ]),
    );

  safeDraftPhases.forEach((phase) => {
    const phaseOrder = Math.max(
      1,
      Math.floor(
        Number(phase?.order || 1),
      ),
    );
    const persistedPhase =
      persistedByOrder.get(phaseOrder);
    const phaseType =
      normalizeProductionPhaseTypeInput(
        persistedPhase?.phaseType ??
          phase?.phaseType,
      );
    const requiredUnits =
      normalizePhaseRequiredUnitsInput(
        persistedPhase?.requiredUnits ??
          phase?.requiredUnits,
        {
          fallback:
            (
              phaseType ===
              PRODUCTION_PHASE_TYPE_FINITE
            ) ?
              defaultFiniteRequiredUnits
            : 0,
        },
      );
    const completedUnitCount =
      (
        phaseType ===
          PRODUCTION_PHASE_TYPE_FINITE &&
        persistedPhase?._id
      ) ?
        Math.max(
          0,
          Number(
            completedCountByPhaseId.get(
              persistedPhase._id.toString(),
            ) || 0,
          ),
        )
      : 0;
    const remainingUnits = Math.max(
      0,
      requiredUnits -
        completedUnitCount,
    );
    snapshotByOrder.set(phaseOrder, {
      phaseType,
      requiredUnits,
      completedUnitCount,
      remainingUnits,
      isLocked:
        phaseType ===
          PRODUCTION_PHASE_TYPE_FINITE &&
        remainingUnits <= 0,
      persistedPhaseId:
        persistedPhase?._id || null,
    });
  });

  return snapshotByOrder;
}

// UNIT-LIFECYCLE
// WHY: Unit completion truth must be created only after approval and stay idempotent per plan/phase/unit.
async function syncPhaseUnitCompletionsForApprovedProgress({
  progress,
  approvedBy,
  approvedAt,
  operation = "",
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enablePhaseUnitCompletion
  ) {
    return {
      applied: false,
      skippedReason:
        "phase_unit_completion_flag_disabled",
      unitIds: [],
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: null,
      taskId: null,
    };
  }

  const progressPlanId =
    normalizeStaffIdInput(
      progress?.planId,
    );
  const progressTaskId =
    normalizeStaffIdInput(
      progress?.taskId,
    );
  if (
    !mongoose.Types.ObjectId.isValid(
      progressPlanId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      progressTaskId,
    )
  ) {
    return {
      applied: false,
      skippedReason:
        "progress_context_invalid",
      unitIds: [],
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: null,
      taskId: null,
    };
  }

  const task =
    await ProductionTask.findById(
      progressTaskId,
    )
      .select({
        _id: 1,
        planId: 1,
        phaseId: 1,
        status: 1,
        completedAt: 1,
        assignedUnitIds: 1,
      })
      .lean();
  if (
    !task ||
    !mongoose.Types.ObjectId.isValid(
      task?.phaseId,
    )
  ) {
    return {
      applied: false,
      skippedReason:
        "task_or_phase_missing",
      unitIds: [],
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: null,
      taskId: progressTaskId || null,
    };
  }
  if (
    task?.status !==
    PRODUCTION_TASK_STATUS_DONE
  ) {
    return {
      applied: false,
      skippedReason:
        "task_not_completed",
      unitIds: [],
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: task.phaseId,
      taskId: task._id,
    };
  }

  if (
    task.planId?.toString() !==
    progressPlanId
  ) {
    return {
      applied: false,
      skippedReason:
        "plan_task_mismatch",
      unitIds: [],
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: task.phaseId,
      taskId: task._id,
    };
  }

  const taskAssignedUnitIds =
    resolveTaskAssignedUnitIds(task);
  if (
    taskAssignedUnitIds.length === 0
  ) {
    return {
      applied: false,
      skippedReason:
        "task_units_missing",
      unitIds: [],
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: task.phaseId,
      taskId: task._id,
    };
  }
  const progressUnitId =
    normalizeStaffIdInput(
      progress?.unitId,
    );
  // UNIT-LIFECYCLE
  // WHY: A task completion approval confirms all canonical units assigned to that task for the phase checkpoint.
  let scopedAssignedUnitIds = [
    ...taskAssignedUnitIds,
  ];
  if (progressUnitId) {
    if (
      !taskAssignedUnitIds.includes(
        progressUnitId,
      )
    ) {
      return {
        applied: false,
        skippedReason:
          "progress_unit_not_assigned",
        unitIds: [],
        upsertedCount: 0,
        matchedCount: 0,
        phaseId: task.phaseId,
        taskId: task._id,
      };
    }
  }

  const planUnits = await PlanUnit.find(
    {
      _id: {
        $in: scopedAssignedUnitIds,
      },
      planId: progressPlanId,
    },
  )
    .select({ _id: 1 })
    .lean();
  const validUnitIds = planUnits
    .map((unit) =>
      normalizeStaffIdInput(unit?._id),
    )
    .filter(Boolean);
  if (validUnitIds.length === 0) {
    return {
      applied: false,
      skippedReason:
        "task_units_out_of_scope",
      unitIds: [],
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: task.phaseId,
      taskId: task._id,
    };
  }

  const completionBy =
    (
      mongoose.Types.ObjectId.isValid(
        approvedBy,
      )
    ) ?
      approvedBy
    : (
      mongoose.Types.ObjectId.isValid(
        progress?.approvedBy,
      )
    ) ?
      progress.approvedBy
    : null;
  if (!completionBy) {
    return {
      applied: false,
      skippedReason:
        "completion_actor_missing",
      unitIds: validUnitIds,
      upsertedCount: 0,
      matchedCount: 0,
      phaseId: task.phaseId,
      taskId: task._id,
    };
  }
  const completionAt =
    approvedAt instanceof Date ?
      approvedAt
    : (
      progress?.approvedAt instanceof
      Date
    ) ?
      progress.approvedAt
    : new Date();

  const bulkOperations =
    validUnitIds.map((unitId) => ({
      updateOne: {
        filter: {
          planId: progressPlanId,
          phaseId: task.phaseId,
          unitId,
        },
        update: {
          $setOnInsert: {
            completedBy: completionBy,
            completedAt: completionAt,
            sourceTaskId: task._id,
          },
        },
        upsert: true,
      },
    }));

  const writeResult =
    await ProductionPhaseUnitCompletion.bulkWrite(
      bulkOperations,
      {
        ordered: false,
      },
    );

  const result = {
    applied: true,
    skippedReason: "",
    unitIds: validUnitIds,
    upsertedCount: Number(
      writeResult?.upsertedCount || 0,
    ),
    matchedCount: Number(
      writeResult?.matchedCount || 0,
    ),
    phaseId: task.phaseId,
    taskId: task._id,
  };

  debug(
    "BUSINESS CONTROLLER: phase unit completion sync",
    {
      operation:
        operation ||
        "unknown_operation",
      planId: progressPlanId,
      phaseId: task.phaseId,
      taskId: task._id,
      unitCount: validUnitIds.length,
      upsertedCount:
        result.upsertedCount,
      matchedCount: result.matchedCount,
    },
  );

  return result;
}

// DEVIATION-GOVERNANCE
// WHY: Threshold values must be deterministic positive whole days.
function parseDeviationThresholdDays(
  value,
) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    return null;
  }
  return Math.max(
    1,
    Math.floor(parsed),
  );
}

// DEVIATION-GOVERNANCE
// WHY: Governance fallback threshold keeps freeze decisions deterministic even when config is incomplete.
function normalizeDeviationThresholdDays(
  value,
  fallback = DEVIATION_DEFAULT_THRESHOLD_DAYS,
) {
  return (
    parseDeviationThresholdDays(
      value,
    ) ||
    parseDeviationThresholdDays(
      fallback,
    ) ||
    DEVIATION_DEFAULT_THRESHOLD_DAYS
  );
}

// DEVIATION-GOVERNANCE
// WHY: Config payloads may arrive as plain objects or Maps and require strict sanitization.
function normalizeDeviationThresholdMap(
  rawMap,
  { enforceOrderKey = false } = {},
) {
  const entries =
    rawMap instanceof Map ?
      Array.from(rawMap.entries())
    : (
      rawMap &&
      typeof rawMap === "object"
    ) ?
      Object.entries(rawMap)
    : [];
  const normalized = {};

  entries.forEach(
    ([rawKey, rawValue]) => {
      const key =
        normalizeStaffIdInput(rawKey);
      if (!key) {
        return;
      }
      const thresholdDays =
        parseDeviationThresholdDays(
          rawValue,
        );
      if (!thresholdDays) {
        return;
      }
      if (enforceOrderKey) {
        const order = Number(key);
        if (
          !Number.isFinite(order) ||
          order <= 0
        ) {
          return;
        }
        normalized[
          String(
            Math.max(
              1,
              Math.floor(order),
            ),
          )
        ] = thresholdDays;
        return;
      }
      normalized[key] = thresholdDays;
    },
  );

  return normalized;
}

function readDeviationThresholdMapValue(
  mapLike,
  key,
) {
  const normalizedKey =
    normalizeStaffIdInput(key);
  if (!normalizedKey) {
    return null;
  }
  const rawValue =
    (
      mapLike &&
      typeof mapLike.get === "function"
    ) ?
      mapLike.get(normalizedKey)
    : mapLike?.[normalizedKey];
  return parseDeviationThresholdDays(
    rawValue,
  );
}

// DEVIATION-GOVERNANCE
// WHY: Phase-specific thresholds must resolve deterministically by phaseId, then phaseOrder, then default.
function resolveDeviationThresholdDaysForPhase({
  governanceConfig,
  phaseId,
  phaseOrder,
}) {
  const fromPhaseId =
    readDeviationThresholdMapValue(
      governanceConfig?.phaseThresholdDays,
      phaseId,
    );
  if (fromPhaseId) {
    return fromPhaseId;
  }

  const safePhaseOrder =
    Number(phaseOrder);
  const phaseOrderKey =
    (
      Number.isFinite(safePhaseOrder) &&
      safePhaseOrder > 0
    ) ?
      String(
        Math.max(
          1,
          Math.floor(safePhaseOrder),
        ),
      )
    : "";
  const fromPhaseOrder =
    phaseOrderKey ?
      readDeviationThresholdMapValue(
        governanceConfig?.phaseThresholdByOrder,
        phaseOrderKey,
      )
    : null;
  if (fromPhaseOrder) {
    return fromPhaseOrder;
  }

  return normalizeDeviationThresholdDays(
    governanceConfig?.defaultThresholdDays,
  );
}

// DEVIATION-GOVERNANCE
// WHY: Plans need a plan-scoped config row while inheriting crop-template defaults across cycles.
async function loadOrCreateDeviationGovernanceConfigForPlan({
  plan,
  actorId,
  payloadConfig = null,
  operation = "",
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance
  ) {
    return {
      config: null,
      created: false,
      skippedReason:
        "deviation_governance_flag_disabled",
    };
  }

  const planId = normalizeStaffIdInput(
    plan?._id,
  );
  const businessId =
    normalizeStaffIdInput(
      plan?.businessId,
    );
  const cropTemplateId =
    normalizeStaffIdInput(
      plan?.productId,
    );
  if (
    !mongoose.Types.ObjectId.isValid(
      planId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      businessId,
    )
  ) {
    return {
      config: null,
      created: false,
      skippedReason:
        "deviation_governance_plan_context_invalid",
    };
  }

  const existingConfig =
    await ProductionDeviationGovernanceConfig.findOne(
      {
        planId,
        businessId,
      },
    );
  if (existingConfig) {
    return {
      config: existingConfig,
      created: false,
      skippedReason: "",
    };
  }

  const templateConfig =
    (
      mongoose.Types.ObjectId.isValid(
        cropTemplateId,
      )
    ) ?
      await ProductionDeviationGovernanceConfig.findOne(
        {
          businessId,
          cropTemplateId,
          planId: { $ne: planId },
        },
      ).sort({ updatedAt: -1 })
    : null;
  const payload =
    (
      payloadConfig &&
      typeof payloadConfig === "object"
    ) ?
      payloadConfig
    : {};
  const defaultThresholdDays =
    normalizeDeviationThresholdDays(
      payload.defaultThresholdDays,
      templateConfig?.defaultThresholdDays,
    );
  const phaseThresholdDays =
    normalizeDeviationThresholdMap(
      (
        Object.keys(
          normalizeDeviationThresholdMap(
            payload.phaseThresholdDays,
          ),
        ).length > 0
      ) ?
        payload.phaseThresholdDays
      : templateConfig?.phaseThresholdDays,
    );
  const phaseThresholdByOrder =
    normalizeDeviationThresholdMap(
      (
        Object.keys(
          normalizeDeviationThresholdMap(
            payload.phaseThresholdByOrder,
            {
              enforceOrderKey: true,
            },
          ),
        ).length > 0
      ) ?
        payload.phaseThresholdByOrder
      : templateConfig?.phaseThresholdByOrder,
      {
        enforceOrderKey: true,
      },
    );
  const safeActorId =
    (
      mongoose.Types.ObjectId.isValid(
        actorId,
      )
    ) ?
      actorId
    : (
      mongoose.Types.ObjectId.isValid(
        plan?.createdBy,
      )
    ) ?
      plan.createdBy
    : null;

  if (!safeActorId) {
    return {
      config: null,
      created: false,
      skippedReason:
        "deviation_governance_actor_missing",
    };
  }

  const createdConfig =
    await ProductionDeviationGovernanceConfig.create(
      {
        planId,
        businessId,
        cropTemplateId:
          (
            mongoose.Types.ObjectId.isValid(
              cropTemplateId,
            )
          ) ?
            cropTemplateId
          : null,
        defaultThresholdDays,
        phaseThresholdDays,
        phaseThresholdByOrder,
        createdBy: safeActorId,
        updatedBy: safeActorId,
      },
    );

  debug(
    "BUSINESS CONTROLLER: deviation governance config created",
    {
      operation:
        operation ||
        "unknown_operation",
      planId,
      businessId,
      cropTemplateId:
        cropTemplateId || "",
      defaultThresholdDays,
      phaseThresholdDaysCount:
        Object.keys(phaseThresholdDays)
          .length,
      phaseThresholdByOrderCount:
        Object.keys(
          phaseThresholdByOrder,
        ).length,
      source:
        templateConfig ?
          "crop_template_clone"
        : "default_seed",
    },
  );

  return {
    config: createdConfig,
    created: true,
    skippedReason: "",
  };
}

// DEVIATION-GOVERNANCE
// WHY: Cumulative unit drift drives lock/freeze decisions after per-unit propagation.
async function computeUnitCumulativeDeviationDays({
  planId,
  unitId,
}) {
  if (
    !mongoose.Types.ObjectId.isValid(
      planId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      unitId,
    )
  ) {
    return 0;
  }
  const rows =
    await ProductionUnitTaskSchedule.aggregate(
      [
        {
          $match: {
            planId:
              new mongoose.Types.ObjectId(
                planId,
              ),
            unitId:
              new mongoose.Types.ObjectId(
                unitId,
              ),
          },
        },
        {
          $project: {
            deviationDays: {
              $divide: [
                {
                  $max: [
                    {
                      $subtract: [
                        "$currentDueDate",
                        "$baselineDueDate",
                      ],
                    },
                    0,
                  ],
                },
                MS_PER_DAY,
              ],
            },
          },
        },
        {
          $group: {
            _id: null,
            cumulativeDeviationDays: {
              $max: "$deviationDays",
            },
          },
        },
      ],
    );
  return Math.max(
    0,
    Math.ceil(
      Number(
        rows[0]
          ?.cumulativeDeviationDays ||
          0,
      ),
    ),
  );
}

// DEVIATION-GOVERNANCE
// WHY: Threshold breach must create/update alert, lock the unit, and freeze further automatic shifting.
async function evaluateDeviationGovernanceAfterUnitShift({
  planId,
  businessId,
  productId,
  unitId,
  sourceTaskId,
  sourcePhaseId,
  sourceProgressId,
  actorId,
  shiftedTaskCount = 0,
  operation = "",
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance
  ) {
    return {
      triggered: false,
      skippedReason:
        "deviation_governance_flag_disabled",
      alertId: "",
      cumulativeDeviationDays: 0,
      thresholdDays: 0,
      unitLocked: false,
      summary: null,
    };
  }

  if (
    !mongoose.Types.ObjectId.isValid(
      planId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      businessId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      unitId,
    )
  ) {
    return {
      triggered: false,
      skippedReason:
        "deviation_governance_context_invalid",
      alertId: "",
      cumulativeDeviationDays: 0,
      thresholdDays: 0,
      unitLocked: false,
      summary: null,
    };
  }

  const plan = {
    _id: planId,
    businessId,
    productId:
      (
        mongoose.Types.ObjectId.isValid(
          productId,
        )
      ) ?
        productId
      : null,
    createdBy: actorId || null,
  };
  const governanceConfigResult =
    await loadOrCreateDeviationGovernanceConfigForPlan(
      {
        plan,
        actorId,
        payloadConfig: null,
        operation,
      },
    );
  const governanceConfig =
    governanceConfigResult.config;
  if (!governanceConfig) {
    return {
      triggered: false,
      skippedReason:
        governanceConfigResult.skippedReason ||
        "deviation_governance_config_missing",
      alertId: "",
      cumulativeDeviationDays: 0,
      thresholdDays: 0,
      unitLocked: false,
      summary: null,
    };
  }

  const cumulativeDeviationDays =
    await computeUnitCumulativeDeviationDays(
      {
        planId,
        unitId,
      },
    );
  const sourcePhase =
    (
      mongoose.Types.ObjectId.isValid(
        sourcePhaseId,
      )
    ) ?
      await ProductionPhase.findById(
        sourcePhaseId,
      )
        .select({ _id: 1, order: 1 })
        .lean()
    : null;
  const thresholdDays =
    resolveDeviationThresholdDaysForPhase(
      {
        governanceConfig,
        phaseId: sourcePhaseId || "",
        phaseOrder:
          sourcePhase?.order || 0,
      },
    );

  if (
    cumulativeDeviationDays <=
    thresholdDays
  ) {
    return {
      triggered: false,
      skippedReason:
        "deviation_threshold_not_exceeded",
      alertId: "",
      cumulativeDeviationDays,
      thresholdDays,
      unitLocked: false,
      summary: null,
    };
  }

  const triggeredAt = new Date();
  const safeActorId =
    (
      mongoose.Types.ObjectId.isValid(
        actorId,
      )
    ) ?
      actorId
    : null;
  const alertMessage = `Unit deviation ${cumulativeDeviationDays} day(s) exceeded threshold ${thresholdDays} day(s). Automatic shifts are now frozen until manager intervention.`;

  let alert =
    await LifecycleDeviationAlert.findOne(
      {
        planId,
        businessId,
        unitId,
        status:
          DEVIATION_ALERT_STATUS_OPEN,
      },
    );
  if (!alert) {
    alert =
      await LifecycleDeviationAlert.create(
        {
          planId,
          businessId,
          unitId,
          sourceProgressId:
            (
              mongoose.Types.ObjectId.isValid(
                sourceProgressId,
              )
            ) ?
              sourceProgressId
            : null,
          sourceTaskId:
            (
              mongoose.Types.ObjectId.isValid(
                sourceTaskId,
              )
            ) ?
              sourceTaskId
            : null,
          cumulativeDeviationDays,
          thresholdDays,
          status:
            DEVIATION_ALERT_STATUS_OPEN,
          message: alertMessage,
          triggeredAt,
          actionHistory: [
            {
              actionType:
                DEVIATION_ALERT_ACTION_TRIGGERED,
              actorId: safeActorId,
              actedAt: triggeredAt,
              note: "",
              metadata: {
                operation:
                  operation ||
                  "unknown_operation",
                shiftedTaskCount:
                  Math.max(
                    0,
                    Number(
                      shiftedTaskCount ||
                        0,
                    ),
                  ),
                cumulativeDeviationDays,
                thresholdDays,
              },
            },
          ],
        },
      );
  } else {
    alert.cumulativeDeviationDays =
      cumulativeDeviationDays;
    alert.thresholdDays = thresholdDays;
    alert.message = alertMessage;
    alert.sourceProgressId =
      (
        mongoose.Types.ObjectId.isValid(
          sourceProgressId,
        )
      ) ?
        sourceProgressId
      : alert.sourceProgressId;
    alert.sourceTaskId =
      (
        mongoose.Types.ObjectId.isValid(
          sourceTaskId,
        )
      ) ?
        sourceTaskId
      : alert.sourceTaskId;
    alert.actionHistory =
      (
        Array.isArray(
          alert.actionHistory,
        )
      ) ?
        alert.actionHistory
      : [];
    alert.actionHistory.push({
      actionType:
        DEVIATION_ALERT_ACTION_TRIGGERED,
      actorId: safeActorId,
      actedAt: triggeredAt,
      note: "",
      metadata: {
        operation:
          operation ||
          "unknown_operation",
        shiftedTaskCount: Math.max(
          0,
          Number(shiftedTaskCount || 0),
        ),
        cumulativeDeviationDays,
        thresholdDays,
      },
    });
    await alert.save();
  }

  await PlanUnit.updateOne(
    {
      _id: unitId,
      planId,
    },
    {
      $set: {
        deviationLocked: true,
        deviationLockedAt: triggeredAt,
        deviationLockReason:
          alertMessage,
        deviationLockedByAlertId:
          alert._id,
      },
    },
  );

  // WHY: Persist warning visibility so managers see freeze context directly in schedule diagnostics.
  await appendUnitScheduleWarning({
    planId,
    unitId,
    taskId: sourceTaskId || null,
    phaseId: sourcePhaseId || null,
    warningType:
      PRODUCTION_UNIT_WARNING_TYPE_SHIFT_CONFLICT,
    severity:
      PRODUCTION_UNIT_WARNING_SEVERITY_WARNING,
    message: alertMessage,
    shiftDays: cumulativeDeviationDays,
    sourceProgressId:
      sourceProgressId || null,
    metadata: {
      governance: "deviation_lock",
      thresholdDays,
      cumulativeDeviationDays,
      shiftedTaskCount: Math.max(
        0,
        Number(shiftedTaskCount || 0),
      ),
    },
  });

  let confidenceSnapshot = null;
  try {
    const confidenceRecompute =
      await triggerPlanConfidenceRecompute(
        {
          planId,
          trigger:
            CONFIDENCE_RECOMPUTE_TRIGGERS.DEVIATION_ALERT_TRIGGERED,
          actorId: safeActorId,
          operation:
            "evaluateDeviationGovernanceAfterUnitShift",
        },
      );
    confidenceSnapshot =
      confidenceRecompute?.snapshot ||
      null;
  } catch (confidenceErr) {
    debug(
      "BUSINESS CONTROLLER: deviation governance confidence recompute skipped",
      {
        operation:
          operation ||
          "unknown_operation",
        planId,
        unitId,
        reason: confidenceErr.message,
        next: "Retry confidence recompute from deterministic trigger path",
      },
    );
  }

  const [alerts, lockedUnits] =
    await Promise.all([
      LifecycleDeviationAlert.find({
        planId,
        businessId,
      }).lean(),
      PlanUnit.countDocuments({
        planId,
        deviationLocked: true,
      }),
    ]);
  const summary = buildDeviationSummary(
    {
      alerts,
      lockedUnits,
    },
  );

  debug(
    "BUSINESS CONTROLLER: deviation governance triggered",
    {
      operation:
        operation ||
        "unknown_operation",
      planId,
      unitId,
      alertId: alert._id,
      cumulativeDeviationDays,
      thresholdDays,
      lockedUnits: summary.lockedUnits,
      openAlerts: summary.openAlerts,
      shiftedTaskCount: Math.max(
        0,
        Number(shiftedTaskCount || 0),
      ),
    },
  );

  return {
    triggered: true,
    skippedReason: "",
    alertId:
      alert?._id?.toString?.() || "",
    cumulativeDeviationDays,
    thresholdDays,
    unitLocked: true,
    summary,
    confidence: confidenceSnapshot,
  };
}

// UNIT-LIFECYCLE
// WHY: Monitoring timelines must anchor to finite lifecycle events when persisted as relative offsets.
function resolveMonitoringReferencePhase({
  phase,
  finitePhases,
}) {
  if (
    !phase ||
    finitePhases.length === 0
  ) {
    return null;
  }
  const phaseOrder = Math.max(
    1,
    Math.floor(
      Number(phase?.order || 1),
    ),
  );
  const finiteBeforeOrAt = finitePhases
    .filter(
      (candidate) =>
        Math.max(
          1,
          Math.floor(
            Number(
              candidate?.order || 1,
            ),
          ),
        ) <= phaseOrder,
    )
    .sort(
      (left, right) =>
        Number(right?.order || 1) -
        Number(left?.order || 1),
    );
  if (finiteBeforeOrAt.length > 0) {
    return finiteBeforeOrAt[0];
  }
  return finitePhases[0] || null;
}

// UNIT-LIFECYCLE
// WHY: Relative schedules need one deterministic reference timestamp for offset math.
function resolveReferenceEventDate({
  phase,
  referenceEvent,
}) {
  if (!phase) {
    return null;
  }
  if (
    referenceEvent ===
    PRODUCTION_TASK_TIMING_REFERENCE_EVENT_PHASE_COMPLETION
  ) {
    return (
      parseDateInput(phase?.endDate) ||
      null
    );
  }
  return (
    parseDateInput(phase?.startDate) ||
    null
  );
}

// UNIT-LIFECYCLE
// WHY: Stage 5 requires one canonical unit-timing row per (plan, task, unit) for deterministic downstream shifts.
async function seedUnitTaskScheduleRows({
  planId,
  taskRows,
  operation = "",
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enableUnitAssignments
  ) {
    return {
      applied: false,
      skippedReason:
        "unit_assignments_flag_disabled",
      upsertedCount: 0,
      matchedCount: 0,
      rowCount: 0,
    };
  }

  const normalizedPlanId =
    normalizeStaffIdInput(planId);
  if (
    !mongoose.Types.ObjectId.isValid(
      normalizedPlanId,
    )
  ) {
    return {
      applied: false,
      skippedReason: "plan_id_invalid",
      upsertedCount: 0,
      matchedCount: 0,
      rowCount: 0,
    };
  }

  const safeTaskRows =
    Array.isArray(taskRows) ? taskRows
    : [];
  if (safeTaskRows.length === 0) {
    return {
      applied: false,
      skippedReason: "task_rows_empty",
      upsertedCount: 0,
      matchedCount: 0,
      rowCount: 0,
    };
  }

  const candidateUnitIds = safeTaskRows
    .flatMap((task) =>
      resolveTaskAssignedUnitIds(task),
    )
    .filter(Boolean);
  if (candidateUnitIds.length === 0) {
    return {
      applied: false,
      skippedReason:
        "assigned_units_missing",
      upsertedCount: 0,
      matchedCount: 0,
      rowCount: 0,
    };
  }

  const [planUnits, phaseRows] =
    await Promise.all([
      PlanUnit.find({
        _id: { $in: candidateUnitIds },
        planId: normalizedPlanId,
      })
        .select({ _id: 1 })
        .lean(),
      ProductionPhase.find({
        planId: normalizedPlanId,
      })
        .select({
          _id: 1,
          order: 1,
          phaseType: 1,
          startDate: 1,
          endDate: 1,
        })
        .sort({ order: 1 })
        .lean(),
    ]);

  const validUnitIdSet = new Set(
    planUnits
      .map((unit) =>
        normalizeStaffIdInput(
          unit?._id,
        ),
      )
      .filter(Boolean),
  );
  if (validUnitIdSet.size === 0) {
    return {
      applied: false,
      skippedReason:
        "assigned_units_out_of_scope",
      upsertedCount: 0,
      matchedCount: 0,
      rowCount: 0,
    };
  }

  const phaseById = new Map(
    phaseRows.map((phase) => [
      normalizeStaffIdInput(phase?._id),
      phase,
    ]),
  );
  const finitePhases = phaseRows.filter(
    (phase) =>
      normalizeProductionPhaseTypeInput(
        phase?.phaseType,
      ) ===
      PRODUCTION_PHASE_TYPE_FINITE,
  );

  const bulkOperations = [];
  safeTaskRows.forEach((task) => {
    const taskId =
      normalizeStaffIdInput(task?._id);
    const phaseId =
      normalizeStaffIdInput(
        task?.phaseId,
      );
    if (
      !mongoose.Types.ObjectId.isValid(
        taskId,
      ) ||
      !mongoose.Types.ObjectId.isValid(
        phaseId,
      )
    ) {
      return;
    }

    const phase =
      phaseById.get(phaseId);
    if (!phase) {
      return;
    }
    const baselineStartDate =
      parseDateInput(task?.startDate);
    const baselineDueDate =
      parseDateInput(task?.dueDate);
    if (
      !baselineStartDate ||
      !baselineDueDate
    ) {
      return;
    }

    const timingMode =
      resolveTaskTimingModeFromPhaseType(
        phase?.phaseType,
      );
    const referencePhase =
      (
        timingMode ===
        PRODUCTION_TASK_TIMING_MODE_RELATIVE
      ) ?
        resolveMonitoringReferencePhase(
          {
            phase,
            finitePhases,
          },
        )
      : null;
    const referenceEvent =
      PRODUCTION_TASK_TIMING_REFERENCE_EVENT_PHASE_START;
    const referenceDate =
      (
        timingMode ===
        PRODUCTION_TASK_TIMING_MODE_RELATIVE
      ) ?
        resolveReferenceEventDate({
          phase: referencePhase,
          referenceEvent,
        })
      : null;
    const startOffsetDays =
      (
        timingMode ===
        PRODUCTION_TASK_TIMING_MODE_RELATIVE
      ) ?
        resolveOffsetDaysFromReferenceDate(
          {
            referenceDate,
            targetDate:
              baselineStartDate,
          },
        )
      : 0;
    const dueOffsetDays =
      (
        timingMode ===
        PRODUCTION_TASK_TIMING_MODE_RELATIVE
      ) ?
        resolveOffsetDaysFromReferenceDate(
          {
            referenceDate,
            targetDate: baselineDueDate,
          },
        )
      : 0;

    resolveTaskAssignedUnitIds(task)
      .filter((unitId) =>
        validUnitIdSet.has(unitId),
      )
      .forEach((unitId) => {
        bulkOperations.push({
          updateOne: {
            filter: {
              planId: normalizedPlanId,
              taskId,
              unitId,
            },
            update: {
              $setOnInsert: {
                planId:
                  normalizedPlanId,
                taskId,
                phaseId: phase._id,
                unitId,
                timingMode,
                referencePhaseId:
                  referencePhase?._id ||
                  null,
                referenceEvent,
                baselineStartDate,
                baselineDueDate,
                currentStartDate:
                  baselineStartDate,
                currentDueDate:
                  baselineDueDate,
                startOffsetDays,
                dueOffsetDays,
                lastShiftDays: 0,
                lastShiftReason: "",
                lastShiftedByProgressId:
                  null,
              },
              $set: {
                phaseId: phase._id,
                timingMode,
                referencePhaseId:
                  referencePhase?._id ||
                  null,
                referenceEvent,
              },
            },
            upsert: true,
          },
        });
      });
  });

  if (bulkOperations.length === 0) {
    return {
      applied: false,
      skippedReason:
        "no_valid_unit_rows",
      upsertedCount: 0,
      matchedCount: 0,
      rowCount: 0,
    };
  }

  const writeResult =
    await ProductionUnitTaskSchedule.bulkWrite(
      bulkOperations,
      {
        ordered: false,
      },
    );
  const result = {
    applied: true,
    skippedReason: "",
    upsertedCount: Number(
      writeResult?.upsertedCount || 0,
    ),
    matchedCount: Number(
      writeResult?.matchedCount || 0,
    ),
    rowCount: bulkOperations.length,
  };

  debug(
    "BUSINESS CONTROLLER: seedUnitTaskScheduleRows - success",
    {
      operation:
        operation ||
        "unknown_operation",
      planId: normalizedPlanId,
      rowCount: result.rowCount,
      upsertedCount:
        result.upsertedCount,
      matchedCount: result.matchedCount,
    },
  );

  return result;
}

// UNIT-LIFECYCLE
// WHY: Conflict and context warnings must persist for manager review instead of silent auto-rebalancing.
async function appendUnitScheduleWarning({
  planId,
  unitId,
  taskId = null,
  phaseId = null,
  warningType,
  severity = PRODUCTION_UNIT_WARNING_SEVERITY_WARNING,
  message,
  shiftDays = 0,
  sourceProgressId = null,
  metadata = null,
}) {
  const normalizedPlanId =
    normalizeStaffIdInput(planId);
  const normalizedUnitId =
    normalizeStaffIdInput(unitId);
  if (
    !mongoose.Types.ObjectId.isValid(
      normalizedPlanId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      normalizedUnitId,
    )
  ) {
    return null;
  }
  const safeMessage =
    message?.toString().trim() || "";
  if (!safeMessage) {
    return null;
  }
  return ProductionUnitScheduleWarning.create(
    {
      planId: normalizedPlanId,
      unitId: normalizedUnitId,
      taskId:
        (
          mongoose.Types.ObjectId.isValid(
            taskId,
          )
        ) ?
          taskId
        : null,
      phaseId:
        (
          mongoose.Types.ObjectId.isValid(
            phaseId,
          )
        ) ?
          phaseId
        : null,
      warningType,
      severity,
      message: safeMessage,
      shiftDays: Math.max(
        0,
        Number(shiftDays || 0),
      ),
      sourceProgressId:
        (
          mongoose.Types.ObjectId.isValid(
            sourceProgressId,
          )
        ) ?
          sourceProgressId
        : null,
      metadata:
        (
          metadata &&
          typeof metadata === "object"
        ) ?
          metadata
        : null,
    },
  );
}

// UNIT-LIFECYCLE
// WHY: Stage 5 requires shifting only one delayed unit's downstream schedule while preserving staff assignments.
async function shiftUnitScheduleForApprovedProgress({
  progress,
  approvedBy,
  businessId = null,
  productId = null,
  operation = "",
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enableUnitAssignments
  ) {
    return {
      applied: false,
      skippedReason:
        "unit_assignments_flag_disabled",
      unitId: "",
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount: 0,
    };
  }

  const shiftDays =
    resolveUnitDelayShiftDaysFromProgress(
      progress,
    );
  if (shiftDays <= 0) {
    return {
      applied: false,
      skippedReason:
        "no_delay_detected",
      unitId: "",
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount: 0,
    };
  }

  const progressPlanId =
    normalizeStaffIdInput(
      progress?.planId,
    );
  const progressTaskId =
    normalizeStaffIdInput(
      progress?.taskId,
    );
  if (
    !mongoose.Types.ObjectId.isValid(
      progressPlanId,
    ) ||
    !mongoose.Types.ObjectId.isValid(
      progressTaskId,
    )
  ) {
    return {
      applied: false,
      skippedReason:
        "progress_context_invalid",
      unitId: "",
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount: 0,
    };
  }

  const task =
    await ProductionTask.findById(
      progressTaskId,
    )
      .select({
        _id: 1,
        planId: 1,
        phaseId: 1,
        title: 1,
        startDate: 1,
        dueDate: 1,
        assignedUnitIds: 1,
      })
      .lean();
  if (!task) {
    return {
      applied: false,
      skippedReason: "task_not_found",
      unitId: "",
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount: 0,
    };
  }
  if (
    normalizeStaffIdInput(
      task?.planId,
    ) !== progressPlanId
  ) {
    return {
      applied: false,
      skippedReason:
        "task_plan_mismatch",
      unitId: "",
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount: 0,
    };
  }

  await seedUnitTaskScheduleRows({
    planId: progressPlanId,
    taskRows: [task],
    operation: `${operation}:seed_source`,
  });

  const assignedUnitIds =
    resolveTaskAssignedUnitIds(task);
  if (assignedUnitIds.length === 0) {
    return {
      applied: false,
      skippedReason:
        "task_assigned_units_missing",
      unitId: "",
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount: 0,
    };
  }

  const requestedUnitId =
    normalizeStaffIdInput(
      progress?.unitId,
    );
  let effectiveUnitId = "";
  let warningCount = 0;
  if (requestedUnitId) {
    if (
      !assignedUnitIds.includes(
        requestedUnitId,
      )
    ) {
      return {
        applied: false,
        skippedReason:
          "progress_unit_not_assigned",
        unitId: requestedUnitId,
        shiftDays: 0,
        shiftedTaskCount: 0,
        warningCount: 0,
      };
    }
    effectiveUnitId = requestedUnitId;
  } else if (
    assignedUnitIds.length === 1
  ) {
    effectiveUnitId =
      assignedUnitIds[0];
  } else {
    await appendUnitScheduleWarning({
      planId: progressPlanId,
      unitId: assignedUnitIds[0],
      taskId: task._id,
      phaseId: task.phaseId,
      warningType:
        PRODUCTION_UNIT_WARNING_TYPE_MISSING_CONTEXT,
      message:
        "Delay detected but unitId was missing. Provide unitId so only the affected unit can be shifted.",
      shiftDays,
      sourceProgressId: progress?._id,
      metadata: {
        operation:
          operation ||
          "unknown_operation",
        assignedUnitCount:
          assignedUnitIds.length,
      },
    });
    warningCount += 1;
    return {
      applied: false,
      skippedReason:
        "progress_unit_missing_for_multi_unit_task",
      unitId: "",
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount,
    };
  }

  const planUnit =
    await PlanUnit.findOne({
      _id: effectiveUnitId,
      planId: progressPlanId,
    })
      .select({
        _id: 1,
        deviationLocked: 1,
      })
      .lean();
  if (!planUnit) {
    return {
      applied: false,
      skippedReason:
        "progress_unit_out_of_scope",
      unitId: effectiveUnitId,
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount,
    };
  }
  if (
    PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance &&
    planUnit?.deviationLocked === true
  ) {
    return {
      applied: false,
      skippedReason:
        "unit_deviation_locked",
      unitId: effectiveUnitId,
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount,
    };
  }

  const unitTaskRows =
    await ProductionTask.find({
      planId: progressPlanId,
      assignedUnitIds: effectiveUnitId,
    })
      .select({
        _id: 1,
        phaseId: 1,
        startDate: 1,
        dueDate: 1,
        assignedUnitIds: 1,
      })
      .lean();
  await seedUnitTaskScheduleRows({
    planId: progressPlanId,
    taskRows: unitTaskRows,
    operation: `${operation}:seed_unit_rows`,
  });

  const sourceScheduleRow =
    await ProductionUnitTaskSchedule.findOne(
      {
        planId: progressPlanId,
        taskId: task._id,
        unitId: effectiveUnitId,
      },
    ).lean();
  if (!sourceScheduleRow) {
    await appendUnitScheduleWarning({
      planId: progressPlanId,
      unitId: effectiveUnitId,
      taskId: task._id,
      phaseId: task.phaseId,
      warningType:
        PRODUCTION_UNIT_WARNING_TYPE_MISSING_CONTEXT,
      message:
        "Delay detected but no unit schedule row existed for this task. Rebuild schedule rows before shifting.",
      shiftDays,
      sourceProgressId: progress?._id,
      metadata: {
        operation:
          operation ||
          "unknown_operation",
      },
    });
    warningCount += 1;
    return {
      applied: false,
      skippedReason:
        "source_unit_schedule_missing",
      unitId: effectiveUnitId,
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount,
    };
  }

  const sourceDueDate = parseDateInput(
    sourceScheduleRow?.currentDueDate ||
      sourceScheduleRow?.currentStartDate,
  );
  if (!sourceDueDate) {
    return {
      applied: false,
      skippedReason:
        "source_schedule_dates_invalid",
      unitId: effectiveUnitId,
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount,
    };
  }

  const downstreamRows =
    await ProductionUnitTaskSchedule.find(
      {
        planId: progressPlanId,
        unitId: effectiveUnitId,
        currentStartDate: {
          $gte: sourceDueDate,
        },
      },
    )
      .select({
        _id: 1,
        taskId: 1,
        phaseId: 1,
        timingMode: 1,
        startOffsetDays: 1,
        dueOffsetDays: 1,
        currentStartDate: 1,
        currentDueDate: 1,
      })
      .sort({ currentStartDate: 1 })
      .lean();
  if (downstreamRows.length === 0) {
    return {
      applied: false,
      skippedReason:
        "no_downstream_rows",
      unitId: effectiveUnitId,
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount,
    };
  }

  const shiftedRows = [];
  const shiftOps = [];
  downstreamRows.forEach((row) => {
    const shiftedStartDate =
      shiftDateByDays(
        row?.currentStartDate,
        shiftDays,
      );
    const shiftedDueDate =
      shiftDateByDays(
        row?.currentDueDate,
        shiftDays,
      );
    if (
      !shiftedStartDate ||
      !shiftedDueDate
    ) {
      return;
    }
    const shouldUpdateOffsets =
      row?.timingMode ===
      PRODUCTION_TASK_TIMING_MODE_RELATIVE;

    shiftOps.push({
      updateOne: {
        filter: { _id: row._id },
        update: {
          $set: {
            currentStartDate:
              shiftedStartDate,
            currentDueDate:
              shiftedDueDate,
            lastShiftDays: shiftDays,
            lastShiftReason:
              normalizeTaskProgressDelayReason(
                progress?.delayReason,
              ),
            lastShiftedByProgressId:
              progress?._id || null,
            ...(shouldUpdateOffsets ?
              {
                startOffsetDays:
                  roundScheduleOffsetDays(
                    Number(
                      row?.startOffsetDays ||
                        0,
                    ) + shiftDays,
                  ),
                dueOffsetDays:
                  roundScheduleOffsetDays(
                    Number(
                      row?.dueOffsetDays ||
                        0,
                    ) + shiftDays,
                  ),
              }
            : {}),
          },
        },
      },
    });
    shiftedRows.push({
      _id: row._id,
      taskId: row.taskId,
      phaseId: row.phaseId,
      currentStartDate:
        shiftedStartDate,
      currentDueDate: shiftedDueDate,
    });
  });

  if (shiftOps.length === 0) {
    return {
      applied: false,
      skippedReason:
        "downstream_shift_updates_empty",
      unitId: effectiveUnitId,
      shiftDays: 0,
      shiftedTaskCount: 0,
      warningCount,
    };
  }

  await ProductionUnitTaskSchedule.bulkWrite(
    shiftOps,
    { ordered: false },
  );

  // UNIT-LIFECYCLE
  // WHY: Stage 5 forbids automatic staff rebalance; instead we detect overlap conflicts and persist manager warnings.
  const shiftedTaskIds = Array.from(
    new Set(
      shiftedRows
        .map((row) =>
          normalizeStaffIdInput(
            row?.taskId,
          ),
        )
        .filter((taskId) =>
          mongoose.Types.ObjectId.isValid(
            taskId,
          ),
        ),
    ),
  );
  const [
    shiftedTaskRows,
    potentiallyOverlappingRows,
  ] = await Promise.all([
    shiftedTaskIds.length > 0 ?
      ProductionTask.find({
        _id: { $in: shiftedTaskIds },
        planId: progressPlanId,
      })
        .select({
          _id: 1,
          title: 1,
          assignedStaffId: 1,
          assignedStaffProfileIds: 1,
        })
        .lean()
    : [],
    ProductionUnitTaskSchedule.find({
      planId: progressPlanId,
      unitId: { $ne: effectiveUnitId },
      currentStartDate: {
        $lt: new Date(
          Math.max(
            ...shiftedRows.map((row) =>
              row.currentDueDate.getTime(),
            ),
          ),
        ),
      },
      currentDueDate: {
        $gt: new Date(
          Math.min(
            ...shiftedRows.map((row) =>
              row.currentStartDate.getTime(),
            ),
          ),
        ),
      },
    })
      .select({
        _id: 1,
        taskId: 1,
        unitId: 1,
        currentStartDate: 1,
        currentDueDate: 1,
      })
      .lean(),
  ]);

  const taskById = new Map(
    shiftedTaskRows.map((taskRow) => [
      normalizeStaffIdInput(
        taskRow?._id,
      ),
      taskRow,
    ]),
  );
  const overlapTaskIds = Array.from(
    new Set(
      potentiallyOverlappingRows
        .map((row) =>
          normalizeStaffIdInput(
            row?.taskId,
          ),
        )
        .filter((taskId) =>
          mongoose.Types.ObjectId.isValid(
            taskId,
          ),
        )
        .filter(
          (taskId) =>
            !taskById.has(taskId),
        ),
    ),
  );
  if (overlapTaskIds.length > 0) {
    const overlapTaskRows =
      await ProductionTask.find({
        _id: { $in: overlapTaskIds },
        planId: progressPlanId,
      })
        .select({
          _id: 1,
          title: 1,
          assignedStaffId: 1,
          assignedStaffProfileIds: 1,
        })
        .lean();
    overlapTaskRows.forEach(
      (taskRow) => {
        taskById.set(
          normalizeStaffIdInput(
            taskRow?._id,
          ),
          taskRow,
        );
      },
    );
  }

  for (const shiftedRow of shiftedRows) {
    const shiftedTask = taskById.get(
      normalizeStaffIdInput(
        shiftedRow?.taskId,
      ),
    );
    const shiftedStaffIds = new Set(
      resolveTaskAssignedStaffIds(
        shiftedTask,
      ),
    );
    if (shiftedStaffIds.size === 0) {
      continue;
    }
    const conflictingRow =
      potentiallyOverlappingRows.find(
        (candidate) => {
          if (
            normalizeStaffIdInput(
              candidate?.taskId,
            ) ===
            normalizeStaffIdInput(
              shiftedRow?.taskId,
            )
          ) {
            return false;
          }
          const candidateStart =
            parseDateInput(
              candidate?.currentStartDate,
            );
          const candidateDue =
            parseDateInput(
              candidate?.currentDueDate,
            );
          if (
            !candidateStart ||
            !candidateDue
          ) {
            return false;
          }
          const overlaps =
            shiftedRow.currentStartDate <
              candidateDue &&
            candidateStart <
              shiftedRow.currentDueDate;
          if (!overlaps) {
            return false;
          }
          const candidateTask =
            taskById.get(
              normalizeStaffIdInput(
                candidate?.taskId,
              ),
            );
          if (!candidateTask) {
            return false;
          }
          const candidateStaffIds =
            resolveTaskAssignedStaffIds(
              candidateTask,
            );
          return candidateStaffIds.some(
            (staffId) =>
              shiftedStaffIds.has(
                staffId,
              ),
          );
        },
      );
    if (!conflictingRow) {
      continue;
    }

    const conflictingTask =
      taskById.get(
        normalizeStaffIdInput(
          conflictingRow?.taskId,
        ),
      );
    await appendUnitScheduleWarning({
      planId: progressPlanId,
      unitId: effectiveUnitId,
      taskId: shiftedRow.taskId,
      phaseId: shiftedRow.phaseId,
      warningType:
        PRODUCTION_UNIT_WARNING_TYPE_SHIFT_CONFLICT,
      message: `Shift overlap detected with task "${conflictingTask?.title || ""}". Review assignments manually before execution.`,
      shiftDays,
      sourceProgressId: progress?._id,
      metadata: {
        operation:
          operation ||
          "unknown_operation",
        conflictingTaskId:
          conflictingRow?.taskId ||
          null,
        conflictingUnitId:
          conflictingRow?.unitId ||
          null,
      },
    });
    warningCount += 1;
  }

  // DEVIATION-GOVERNANCE
  // WHY: Stage 6 requires threshold checks after each approved unit shift to freeze unsafe auto-propagation.
  let deviationGovernance = null;
  try {
    deviationGovernance =
      await evaluateDeviationGovernanceAfterUnitShift(
        {
          planId: progressPlanId,
          businessId:
            normalizeStaffIdInput(
              businessId,
            ),
          productId:
            normalizeStaffIdInput(
              productId,
            ),
          unitId: effectiveUnitId,
          sourceTaskId: task._id,
          sourcePhaseId: task.phaseId,
          sourceProgressId:
            progress?._id,
          actorId: approvedBy,
          shiftedTaskCount:
            shiftedRows.length,
          operation: `${
            operation ||
            "shiftUnitScheduleForApprovedProgress"
          }:deviation_governance`,
        },
      );
  } catch (deviationErr) {
    debug(
      "BUSINESS CONTROLLER: shiftUnitScheduleForApprovedProgress - deviation governance skipped",
      {
        operation:
          operation ||
          "unknown_operation",
        planId: progressPlanId,
        unitId: effectiveUnitId,
        reason: deviationErr.message,
        next: "Inspect deviation governance config and unit schedule rows before retrying threshold evaluation",
      },
    );
  }

  debug(
    "BUSINESS CONTROLLER: shiftUnitScheduleForApprovedProgress - success",
    {
      operation:
        operation ||
        "unknown_operation",
      planId: progressPlanId,
      taskId: progressTaskId,
      unitId: effectiveUnitId,
      shiftDays,
      shiftedTaskCount:
        shiftedRows.length,
      warningCount,
      deviationGovernanceTriggered:
        deviationGovernance?.triggered ===
        true,
      approvedBy:
        normalizeStaffIdInput(
          approvedBy,
        ) || "",
    },
  );

  return {
    applied: true,
    skippedReason: "",
    unitId: effectiveUnitId,
    shiftDays,
    shiftedTaskCount:
      shiftedRows.length,
    warningCount,
    deviationGovernance,
  };
}

// UNIT-LIFECYCLE
// WHY: Manager detail view needs persisted divergence and warning rollups per unit.
async function buildUnitScheduleInsightsForPlan({
  planId,
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enableUnitAssignments
  ) {
    return {
      unitDivergence: [],
      unitScheduleWarnings: [],
    };
  }
  const normalizedPlanId =
    normalizeStaffIdInput(planId);
  if (
    !mongoose.Types.ObjectId.isValid(
      normalizedPlanId,
    )
  ) {
    return {
      unitDivergence: [],
      unitScheduleWarnings: [],
    };
  }

  const [
    planUnits,
    divergenceRows,
    warningRows,
  ] = await Promise.all([
    PlanUnit.find({
      planId: normalizedPlanId,
    })
      .select({
        _id: 1,
        unitIndex: 1,
        label: 1,
      })
      .sort({ unitIndex: 1 })
      .lean(),
    ProductionUnitTaskSchedule.aggregate(
      [
        {
          $match: {
            planId:
              new mongoose.Types.ObjectId(
                normalizedPlanId,
              ),
          },
        },
        {
          $project: {
            unitId: "$unitId",
            delayedByDays: {
              $divide: [
                {
                  $max: [
                    {
                      $subtract: [
                        "$currentDueDate",
                        "$baselineDueDate",
                      ],
                    },
                    0,
                  ],
                },
                MS_PER_DAY,
              ],
            },
            shiftedTaskFlag: {
              $cond: [
                {
                  $gt: [
                    {
                      $abs: "$lastShiftDays",
                    },
                    0,
                  ],
                },
                1,
                0,
              ],
            },
            updatedAt: "$updatedAt",
          },
        },
        {
          $group: {
            _id: "$unitId",
            delayedByDays: {
              $max: "$delayedByDays",
            },
            shiftedTaskCount: {
              $sum: "$shiftedTaskFlag",
            },
            updatedAt: {
              $max: "$updatedAt",
            },
          },
        },
      ],
    ),
    ProductionUnitScheduleWarning.find({
      planId: normalizedPlanId,
    })
      .select({
        _id: 1,
        unitId: 1,
        taskId: 1,
        warningType: 1,
        severity: 1,
        message: 1,
        shiftDays: 1,
        createdAt: 1,
        resolvedAt: 1,
      })
      .sort({ createdAt: -1 })
      .limit(300)
      .lean(),
  ]);

  const unitLabelById = new Map(
    planUnits.map((unit) => [
      normalizeStaffIdInput(unit?._id),
      unit?.label || "",
    ]),
  );
  const unitIndexById = new Map(
    planUnits.map((unit) => [
      normalizeStaffIdInput(unit?._id),
      Math.max(
        1,
        Number(unit?.unitIndex || 1),
      ),
    ]),
  );
  const divergenceByUnitId = new Map(
    divergenceRows.map((row) => [
      normalizeStaffIdInput(row?._id),
      row,
    ]),
  );

  const warningCountByUnitId =
    new Map();
  warningRows.forEach((warningRow) => {
    if (warningRow?.resolvedAt) {
      return;
    }
    const unitId =
      normalizeStaffIdInput(
        warningRow?.unitId,
      );
    if (!unitId) {
      return;
    }
    warningCountByUnitId.set(
      unitId,
      Number(
        warningCountByUnitId.get(
          unitId,
        ) || 0,
      ) + 1,
    );
  });

  const unitDivergence = planUnits
    .map((unit) => {
      const unitId =
        normalizeStaffIdInput(
          unit?._id,
        );
      const divergenceRow =
        divergenceByUnitId.get(unitId);
      const delayedByDays = Math.max(
        0,
        Math.ceil(
          Number(
            divergenceRow?.delayedByDays ||
              0,
          ),
        ),
      );
      const shiftedTaskCount = Math.max(
        0,
        Number(
          divergenceRow?.shiftedTaskCount ||
            0,
        ),
      );
      const warningCount = Math.max(
        0,
        Number(
          warningCountByUnitId.get(
            unitId,
          ) || 0,
        ),
      );
      return {
        unitId,
        unitIndex:
          unitIndexById.get(unitId) ||
          1,
        unitLabel:
          unitLabelById.get(unitId) ||
          "",
        delayedByDays,
        shiftedTaskCount,
        warningCount,
        updatedAt:
          divergenceRow?.updatedAt ||
          null,
      };
    })
    .filter(
      (row) =>
        row.delayedByDays > 0 ||
        row.shiftedTaskCount > 0 ||
        row.warningCount > 0,
    );

  const warningTaskIds = Array.from(
    new Set(
      warningRows
        .map((warningRow) =>
          normalizeStaffIdInput(
            warningRow?.taskId,
          ),
        )
        .filter((taskId) =>
          mongoose.Types.ObjectId.isValid(
            taskId,
          ),
        ),
    ),
  );
  const warningTasks =
    warningTaskIds.length > 0 ?
      await ProductionTask.find({
        _id: { $in: warningTaskIds },
        planId: normalizedPlanId,
      })
        .select({ _id: 1, title: 1 })
        .lean()
    : [];
  const warningTaskTitleById = new Map(
    warningTasks.map((task) => [
      normalizeStaffIdInput(task?._id),
      task?.title || "",
    ]),
  );

  const unitScheduleWarnings =
    warningRows
      .filter(
        (warningRow) =>
          warningRow?.resolvedAt ==
          null,
      )
      .map((warningRow) => {
        const unitId =
          normalizeStaffIdInput(
            warningRow?.unitId,
          );
        const taskId =
          normalizeStaffIdInput(
            warningRow?.taskId,
          );
        return {
          warningId:
            warningRow?._id || "",
          unitId,
          unitLabel:
            unitLabelById.get(unitId) ||
            "",
          taskId,
          taskTitle:
            warningTaskTitleById.get(
              taskId,
            ) || "",
          warningType:
            warningRow?.warningType ||
            "",
          severity:
            warningRow?.severity || "",
          message:
            warningRow?.message || "",
          shiftDays: Math.max(
            0,
            Number(
              warningRow?.shiftDays ||
                0,
            ),
          ),
          createdAt:
            warningRow?.createdAt ||
            null,
        };
      });

  return {
    unitDivergence,
    unitScheduleWarnings,
  };
}

// WHY: Batch responses must preserve per-entry diagnostics without aborting the full request.
function buildBatchTaskProgressError({
  index,
  taskId,
  staffId,
  unitId,
  errorCode,
  error,
}) {
  return {
    index,
    taskId: taskId || "",
    staffId: staffId || "",
    unitId: unitId || "",
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
    Number(
      product?.preorderCapQuantity || 0,
    ),
  );
  const reserved = Math.max(
    0,
    Number(
      product?.preorderReservedQuantity ||
        0,
    ),
  );
  const remaining = Math.max(
    0,
    cap - reserved,
  );
  const normalizedEffectiveCap =
    Math.max(
      0,
      Number(
        capConfidence?.effectiveCap ??
          cap,
      ),
    );
  const normalizedConfidenceScore =
    Number(
      capConfidence?.confidenceScore ??
        1,
    );
  const normalizedCoverage = Number(
    capConfidence?.approvedProgressCoverage ??
      0,
  );

  return {
    productionState:
      product?.productionState || null,
    preorderEnabled:
      product?.preorderEnabled === true,
    preorderCapQuantity: cap,
    effectiveCap:
      normalizedEffectiveCap,
    confidenceScore:
      (
        Number.isFinite(
          normalizedConfidenceScore,
        )
      ) ?
        normalizedConfidenceScore
      : 1,
    approvedProgressCoverage:
      (
        Number.isFinite(
          normalizedCoverage,
        )
      ) ?
        normalizedCoverage
      : 0,
    preorderReservedQuantity: reserved,
    preorderRemainingQuantity: Math.max(
      0,
      Math.min(
        remaining,
        normalizedEffectiveCap -
          reserved,
      ),
    ),
    conservativeYieldQuantity:
      product?.conservativeYieldQuantity ??
      null,
    conservativeYieldUnit:
      product?.conservativeYieldUnit ||
      "",
  };
}

// WHY: Reservation responses need simple capacity numbers for immediate UX feedback.
function buildReservationSummary(
  product,
) {
  const cap = Math.max(
    0,
    Number(
      product?.preorderCapQuantity || 0,
    ),
  );
  const reserved = Math.max(
    0,
    Number(
      product?.preorderReservedQuantity ||
        0,
    ),
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

// CONFIDENCE-SCORE
// WHY: Centralize per-plan confidence recompute so trigger sources remain explicit and auditable.
async function triggerPlanConfidenceRecompute({
  planId,
  trigger,
  actorId = null,
  operation = "",
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enableConfidenceScore
  ) {
    return {
      applied: false,
      skippedReason:
        "confidence_score_flag_disabled",
    };
  }
  const result =
    await recomputePlanConfidenceSnapshot(
      {
        planId,
        trigger,
        actorId,
      },
    );
  debug(
    "BUSINESS CONTROLLER: confidence recompute",
    {
      operation:
        operation ||
        "unknown_operation",
      planId:
        planId?.toString?.() || planId,
      trigger: trigger || "",
      applied: result?.applied === true,
      skippedReason:
        result?.skippedReason || "",
      currentConfidenceScore:
        result?.snapshot
          ?.currentConfidenceScore ??
        null,
      baselineConfidenceScore:
        result?.snapshot
          ?.baselineConfidenceScore ??
        null,
      confidenceScoreDelta:
        result?.snapshot
          ?.confidenceScoreDelta ??
        null,
    },
  );
  return result;
}

// CONFIDENCE-SCORE
// WHY: Availability changes should refresh all active plans in scope without touching unrelated writes.
async function triggerScopedAvailabilityConfidenceRecompute({
  businessId,
  estateAssetId = null,
  actorId = null,
  operation = "",
}) {
  if (
    !PRODUCTION_FEATURE_FLAGS.enableConfidenceScore
  ) {
    return {
      attemptedPlans: 0,
      appliedPlans: 0,
      skippedPlans: 0,
      skippedReason:
        "confidence_score_flag_disabled",
      results: [],
    };
  }
  const result =
    await recomputeConfidenceForActivePlans(
      {
        businessId,
        estateAssetId,
        trigger:
          CONFIDENCE_RECOMPUTE_TRIGGERS.STAFF_AVAILABILITY_CHANGED,
        actorId,
      },
    );
  debug(
    "BUSINESS CONTROLLER: confidence scoped availability recompute",
    {
      operation:
        operation ||
        "unknown_operation",
      businessId:
        businessId?.toString?.() ||
        businessId ||
        null,
      estateAssetId:
        estateAssetId?.toString?.() ||
        estateAssetId ||
        null,
      attemptedPlans:
        result?.attemptedPlans || 0,
      appliedPlans:
        result?.appliedPlans || 0,
      skippedPlans:
        result?.skippedPlans || 0,
      skippedReason:
        result?.skippedReason || "",
    },
  );
  return result;
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
        resolveTaskProgressUnitContribution(
          record,
        ) || 0,
      );
      const quantityAmount = Number(
        resolveTaskProgressActivityQuantity(
          record,
        ) || 0,
      );
      const proofCount = Array.isArray(
        record.proofs,
      ) ?
        record.proofs.length
      : Math.max(
          0,
          Number(
            record.proofCountUploaded ||
              record.proofCount ||
              0,
          ),
        );
      // WHY: Zero-output days are explicit blocked records, not implicit misses.
      let status =
        TASK_PROGRESS_STATUS_BEHIND;
      if (
        actualPlots === 0 &&
        quantityAmount === 0
      ) {
        status =
          TASK_PROGRESS_STATUS_BLOCKED;
      } else if (
        actualPlots >= expectedPlots ||
        (
          actualPlots === 0 &&
          quantityAmount > 0
        )
      ) {
        status =
          TASK_PROGRESS_STATUS_ON_TRACK;
      }
      const delayReason =
        record.delayReason || "none";
      // WHY: Delay column reflects execution outcome rather than raw reason value.
      const delay =
        (
          status ===
          TASK_PROGRESS_STATUS_ON_TRACK
        ) ?
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
        unitId: record.unitId || null,
        taskTitle: task?.title || "",
        phaseName: phase?.name || "",
        farmerName,
        expectedPlots,
        actualPlots,
        quantityActivityType:
          resolveTaskProgressActivityType(
            record,
          ) ||
          PRODUCTION_QUANTITY_ACTIVITY_NONE,
        quantityAmount,
        quantityUnit:
          record.quantityUnit || "",
        proofs: Array.isArray(record.proofs)
          ? record.proofs
          : [],
        proofCount,
        proofCountRequired: Math.max(
          0,
          Number(
            record.proofCountRequired ||
              resolveTaskProgressProofCount(
                actualPlots,
              ),
          ),
        ),
        proofCountUploaded: proofCount,
        sessionStatus:
          record.sessionStatus ||
          "completed",
        clockInTime:
          record.clockInTime ||
          null,
        clockOutTime:
          record.clockOutTime ||
          null,
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

  progressRecords.forEach((record) => {
    const staffId =
      record.staffId?.toString();
    if (!staffId) {
      return;
    }
    const expected = Number(
      record.expectedPlots || 0,
    );
    const actual = Number(
      resolveTaskProgressUnitContribution(
        record,
      ) || 0,
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
  });

  return Array.from(
    scoreByStaff.values(),
  ).map((score) => {
    const denominator = Math.max(
      1,
      score.totalExpected,
    );
    const ratio =
      score.totalActual / denominator;
    let status =
      STAFF_PROGRESS_OFF_TRACK;
    if (ratio >= 0.9) {
      status = STAFF_PROGRESS_ON_TRACK;
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
      totalExpected:
        score.totalExpected,
      totalActual: score.totalActual,
      completionRatio: ratio,
      status,
    };
  });
}

// WHY: Daily rollups require a stable UTC day key across progress and attendance records.
function formatUtcDayKey(value) {
  const parsed = parseDateInput(value);
  if (!parsed) {
    return "";
  }
  const year = parsed
    .getUTCFullYear()
    .toString()
    .padStart(4, "0");
  const month = (
    parsed.getUTCMonth() + 1
  )
    .toString()
    .padStart(2, "0");
  const day = parsed
    .getUTCDate()
    .toString()
    .padStart(2, "0");
  return `${year}-${month}-${day}`;
}

// WHY: Rollup rows expose canonical UTC day timestamps back to clients.
function parseUtcDayKey(dayKey) {
  const raw = (dayKey || "")
    .toString()
    .trim();
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(raw)
  ) {
    return null;
  }
  const [year, month, day] = raw
    .split("-")
    .map((item) => Number(item));
  if (
    !Number.isFinite(year) ||
    !Number.isFinite(month) ||
    !Number.isFinite(day)
  ) {
    return null;
  }
  return new Date(
    Date.UTC(
      year,
      month - 1,
      day,
      0,
      0,
      0,
      0,
    ),
  );
}

// WHY: Attendance duration must be resilient even when durationMinutes was not materialized.
function resolveAttendanceDurationMinutes(
  attendance,
) {
  const storedDuration = Number(
    attendance?.durationMinutes,
  );
  if (
    Number.isFinite(storedDuration) &&
    storedDuration >= 0
  ) {
    return storedDuration;
  }

  const clockIn = parseDateInput(
    attendance?.clockInAt,
  );
  const clockOut = parseDateInput(
    attendance?.clockOutAt,
  );
  if (!clockIn || !clockOut) {
    return 0;
  }

  const derivedDuration = Math.round(
    (clockOut.getTime() -
      clockIn.getTime()) /
      MS_PER_MINUTE,
  );
  return Math.max(0, derivedDuration);
}

// WHY: Attendance query windows should follow real plan/task/progress dates.
function resolvePlanTimelineWindow({
  plan,
  tasks,
  progressRecords,
}) {
  const candidateDates = [];
  const pushDate = (value) => {
    const parsed =
      parseDateInput(value);
    if (parsed) {
      candidateDates.push(parsed);
    }
  };

  pushDate(plan?.startDate);
  pushDate(plan?.endDate);
  tasks.forEach((task) => {
    pushDate(task?.startDate);
    pushDate(task?.dueDate);
  });
  progressRecords.forEach((record) => {
    pushDate(record?.workDate);
  });

  if (candidateDates.length === 0) {
    return null;
  }

  let minTime =
    candidateDates[0].getTime();
  let maxTime =
    candidateDates[0].getTime();
  candidateDates.forEach((date) => {
    const time = date.getTime();
    if (time < minTime) {
      minTime = time;
    }
    if (time > maxTime) {
      maxTime = time;
    }
  });

  const minDate = new Date(minTime);
  const maxDate = new Date(maxTime);
  const start = new Date(
    Date.UTC(
      minDate.getUTCFullYear(),
      minDate.getUTCMonth(),
      minDate.getUTCDate(),
      0,
      0,
      0,
      0,
    ),
  );
  const end = new Date(
    Date.UTC(
      maxDate.getUTCFullYear(),
      maxDate.getUTCMonth(),
      maxDate.getUTCDate(),
      23,
      59,
      59,
      999,
    ),
  );

  return {
    start,
    end,
  };
}

// WHY: HR-impact analytics should connect staffing attendance to production truth by day.
function buildProductionDailyRollups({
  tasks,
  progressRecords,
  attendanceRecords,
  taskDayLedgers = [],
}) {
  const scheduledTaskCountByDay =
    new Map();
  const assignedStaffByDay = new Map();
  const attendanceStaffByDay =
    new Map();
  const attendanceMinutesByDay =
    new Map();
  const attendanceByStaffDay =
    new Set();
  const progressByDay = new Map();
  const emptySet = new Set();

  tasks.forEach((task) => {
    const parsedStart = parseDateInput(
      task?.startDate || task?.dueDate,
    );
    const parsedEnd = parseDateInput(
      task?.dueDate || task?.startDate,
    );
    if (!parsedStart || !parsedEnd) {
      return;
    }

    const start = new Date(
      Date.UTC(
        parsedStart.getUTCFullYear(),
        parsedStart.getUTCMonth(),
        parsedStart.getUTCDate(),
        0,
        0,
        0,
        0,
      ),
    );
    const end = new Date(
      Date.UTC(
        parsedEnd.getUTCFullYear(),
        parsedEnd.getUTCMonth(),
        parsedEnd.getUTCDate(),
        0,
        0,
        0,
        0,
      ),
    );
    const normalizedStart =
      start.getTime() <= end.getTime() ?
        start
      : end;
    const normalizedEnd =
      start.getTime() <= end.getTime() ?
        end
      : start;

    const assignedStaffIds =
      resolveTaskAssignedStaffIds(
        task,
      ).filter((staffId) =>
        mongoose.Types.ObjectId.isValid(
          staffId,
        ),
      );
    for (
      let cursor = new Date(
        normalizedStart,
      );
      cursor.getTime() <=
      normalizedEnd.getTime();
      cursor = new Date(
        cursor.getTime() + MS_PER_DAY,
      )
    ) {
      const dayKey =
        formatUtcDayKey(cursor);
      if (!dayKey) {
        continue;
      }

      scheduledTaskCountByDay.set(
        dayKey,
        (scheduledTaskCountByDay.get(
          dayKey,
        ) || 0) + 1,
      );

      if (
        !assignedStaffByDay.has(dayKey)
      ) {
        assignedStaffByDay.set(
          dayKey,
          new Set(),
        );
      }
      const assignedSet =
        assignedStaffByDay.get(dayKey);
      assignedStaffIds.forEach(
        (staffId) => {
          assignedSet.add(staffId);
        },
      );
    }
  });

  attendanceRecords.forEach(
    (attendance) => {
      const dayKey = formatUtcDayKey(
        attendance?.clockInAt,
      );
      const staffId =
        normalizeStaffIdInput(
          attendance?.staffProfileId,
        );
      if (!dayKey || !staffId) {
        return;
      }

      if (
        !attendanceStaffByDay.has(
          dayKey,
        )
      ) {
        attendanceStaffByDay.set(
          dayKey,
          new Set(),
        );
      }
      attendanceStaffByDay
        .get(dayKey)
        .add(staffId);

      attendanceByStaffDay.add(
        `${dayKey}|${staffId}`,
      );

      const durationMinutes =
        resolveAttendanceDurationMinutes(
          attendance,
        );
      attendanceMinutesByDay.set(
        dayKey,
        (attendanceMinutesByDay.get(
          dayKey,
        ) || 0) + durationMinutes,
      );
    },
  );

  const ledgerByDay = new Map();
  (
    Array.isArray(taskDayLedgers) ?
      taskDayLedgers
    : []
  ).forEach((ledger) => {
    const dayKey = formatUtcDayKey(
      ledger?.workDate,
    );
    if (!dayKey) {
      return;
    }

    if (!ledgerByDay.has(dayKey)) {
      ledgerByDay.set(dayKey, {
        expectedPlots: 0,
        actualPlots: 0,
      });
    }
    const summary =
      ledgerByDay.get(dayKey);
    summary.expectedPlots += Number(
      ledger?.unitTarget || 0,
    );
    summary.actualPlots += Number(
      ledger?.unitCompleted || 0,
    );
  });

  progressRecords.forEach((record) => {
    const dayKey = formatUtcDayKey(
      record?.workDate,
    );
    if (!dayKey) {
      return;
    }

    if (!progressByDay.has(dayKey)) {
      progressByDay.set(dayKey, {
        expectedPlots:
          Number(
            ledgerByDay.get(dayKey)
              ?.expectedPlots || 0,
          ),
        actualPlots:
          Number(
            ledgerByDay.get(dayKey)
              ?.actualPlots || 0,
          ),
        rowsLogged: 0,
        rowsWithAttendance: 0,
        rowsMissingAttendance: 0,
      });
    }
    const summary =
      progressByDay.get(dayKey);
    summary.rowsLogged += 1;

    const staffId =
      normalizeStaffIdInput(
        record?.staffId,
      );
    const hasAttendance =
      staffId &&
      attendanceByStaffDay.has(
        `${dayKey}|${staffId}`,
      );
    if (hasAttendance) {
      summary.rowsWithAttendance += 1;
    } else {
      summary.rowsMissingAttendance += 1;
    }
  });

  const allDayKeys = new Set([
    ...scheduledTaskCountByDay.keys(),
    ...assignedStaffByDay.keys(),
    ...attendanceStaffByDay.keys(),
    ...ledgerByDay.keys(),
    ...progressByDay.keys(),
  ]);
  const orderedDayKeys = Array.from(
    allDayKeys.values(),
  ).sort();

  return orderedDayKeys.map(
    (dayKey) => {
      const assignedSet =
        assignedStaffByDay.get(
          dayKey,
        ) || emptySet;
      const attendanceSet =
        attendanceStaffByDay.get(
          dayKey,
        ) || emptySet;
      const progressSummary =
        progressByDay.get(dayKey) || {
          expectedPlots:
            Number(
              ledgerByDay.get(dayKey)
                ?.expectedPlots || 0,
            ),
          actualPlots:
            Number(
              ledgerByDay.get(dayKey)
                ?.actualPlots || 0,
            ),
          rowsLogged: 0,
          rowsWithAttendance: 0,
          rowsMissingAttendance: 0,
        };
      const assignedStaffCount =
        assignedSet.size;
      let attendedAssignedStaffCount = 0;
      assignedSet.forEach((staffId) => {
        if (
          attendanceSet.has(staffId)
        ) {
          attendedAssignedStaffCount += 1;
        }
      });
      const absentAssignedStaffCount =
        Math.max(
          0,
          assignedStaffCount -
            attendedAssignedStaffCount,
        );
      const attendanceMinutes = Number(
        attendanceMinutesByDay.get(
          dayKey,
        ) || 0,
      );
      const completionRate =
        (
          progressSummary.expectedPlots >
          0
        ) ?
          progressSummary.actualPlots /
          progressSummary.expectedPlots
        : 0;
      const attendanceCoverageRate =
        assignedStaffCount > 0 ?
          attendedAssignedStaffCount /
          assignedStaffCount
        : 0;
      const plotsPerAttendedHour =
        attendanceMinutes > 0 ?
          progressSummary.actualPlots /
          (attendanceMinutes / 60)
        : 0;

      return {
        workDate:
          parseUtcDayKey(dayKey),
        scheduledTaskBlocks: Number(
          scheduledTaskCountByDay.get(
            dayKey,
          ) || 0,
        ),
        assignedStaffCount,
        attendedStaffCount:
          attendanceSet.size,
        attendedAssignedStaffCount,
        absentAssignedStaffCount,
        attendanceCoverageRate,
        expectedPlots:
          progressSummary.expectedPlots,
        actualPlots:
          progressSummary.actualPlots,
        completionRate,
        rowsLogged:
          progressSummary.rowsLogged,
        rowsWithAttendance:
          progressSummary.rowsWithAttendance,
        rowsMissingAttendance:
          progressSummary.rowsMissingAttendance,
        attendanceMinutes,
        plotsPerAttendedHour,
      };
    },
  );
}

// WHY: Plan-level KPI cards need one summary object linking attendance behavior to production outcomes.
function buildAttendanceImpactKpis({
  dailyRollups,
}) {
  const totals = dailyRollups.reduce(
    (acc, rollup) => {
      acc.totalRollupDays += 1;
      if (
        Number(
          rollup.scheduledTaskBlocks ||
            0,
        ) > 0
      ) {
        acc.scheduledDays += 1;
      }
      acc.rowsLogged += Number(
        rollup.rowsLogged || 0,
      );
      acc.rowsWithAttendance += Number(
        rollup.rowsWithAttendance || 0,
      );
      acc.rowsMissingAttendance +=
        Number(
          rollup.rowsMissingAttendance ||
            0,
        );
      acc.totalExpectedPlots += Number(
        rollup.expectedPlots || 0,
      );
      acc.totalActualPlots += Number(
        rollup.actualPlots || 0,
      );
      acc.totalAttendanceMinutes +=
        Number(
          rollup.attendanceMinutes || 0,
        );
      acc.assignedStaffSlots += Number(
        rollup.assignedStaffCount || 0,
      );
      acc.attendedAssignedStaffSlots +=
        Number(
          rollup.attendedAssignedStaffCount ||
            0,
        );
      acc.absentAssignedStaffSlots +=
        Number(
          rollup.absentAssignedStaffCount ||
            0,
        );
      return acc;
    },
    {
      totalRollupDays: 0,
      scheduledDays: 0,
      rowsLogged: 0,
      rowsWithAttendance: 0,
      rowsMissingAttendance: 0,
      totalExpectedPlots: 0,
      totalActualPlots: 0,
      totalAttendanceMinutes: 0,
      assignedStaffSlots: 0,
      attendedAssignedStaffSlots: 0,
      absentAssignedStaffSlots: 0,
    },
  );

  const completionRate =
    totals.totalExpectedPlots > 0 ?
      totals.totalActualPlots /
      totals.totalExpectedPlots
    : 0;
  const attendanceCoverageRate =
    totals.assignedStaffSlots > 0 ?
      totals.attendedAssignedStaffSlots /
      totals.assignedStaffSlots
    : 0;
  const absenteeImpactRate =
    totals.assignedStaffSlots > 0 ?
      totals.absentAssignedStaffSlots /
      totals.assignedStaffSlots
    : 0;
  const attendanceLinkedProgressRate =
    totals.rowsLogged > 0 ?
      totals.rowsWithAttendance /
      totals.rowsLogged
    : 0;
  const plotsPerAttendedHour =
    totals.totalAttendanceMinutes > 0 ?
      totals.totalActualPlots /
      (totals.totalAttendanceMinutes /
        60)
    : 0;

  return {
    totalRollupDays:
      totals.totalRollupDays,
    scheduledDays: totals.scheduledDays,
    rowsLogged: totals.rowsLogged,
    rowsWithAttendance:
      totals.rowsWithAttendance,
    rowsMissingAttendance:
      totals.rowsMissingAttendance,
    assignedStaffSlots:
      totals.assignedStaffSlots,
    attendedAssignedStaffSlots:
      totals.attendedAssignedStaffSlots,
    absentAssignedStaffSlots:
      totals.absentAssignedStaffSlots,
    totalExpectedPlots:
      totals.totalExpectedPlots,
    totalActualPlots:
      totals.totalActualPlots,
    totalAttendanceMinutes:
      totals.totalAttendanceMinutes,
    completionRate,
    attendanceCoverageRate,
    absenteeImpactRate,
    attendanceLinkedProgressRate,
    plotsPerAttendedHour,
  };
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
  if (phaseCount === 0) {
    return [];
  }

  const normalizedPhaseDurations =
    phases.map((phase) => {
      const executionDays = Math.max(
        1,
        Math.floor(
          Number(
            phase?.estimatedDays || 1,
          ),
        ),
      );
      const biologicalMinDays =
        normalizePhaseBiologicalMinDaysInput(
          phase?.biologicalMinDays,
        );
      const phaseType =
        normalizeProductionPhaseTypeInput(
          phase?.phaseType,
        );
      const scheduleDays = Math.max(
        executionDays,
        biologicalMinDays,
      );
      return {
        executionDays,
        biologicalMinDays,
        phaseType,
        scheduleDays,
      };
    });
  const totalRequestedMs =
    normalizedPhaseDurations.reduce(
      (sum, phaseDuration) =>
        sum +
        phaseDuration.scheduleDays *
          MS_PER_DAY,
      0,
    );

  if (
    totalRequestedMs > 0 &&
    totalRequestedMs <=
      totalMs + MS_PER_DAY
  ) {
    // WHY: When finite phase durations fit in the provided range, preserve true execution length instead of stretching to full range.
    let cursor = new Date(
      normalizedStart,
    );
    return phases.map(
      (phase, index) => {
        const phaseDuration =
          normalizedPhaseDurations[
            index
          ];
        const phaseDurationDays =
          phaseDuration.scheduleDays;
        const phaseStart = new Date(
          cursor,
        );
        let phaseEnd = new Date(
          phaseStart.getTime() +
            phaseDurationDays *
              MS_PER_DAY -
            1,
        );
        if (
          phaseEnd.getTime() >
          normalizedEnd.getTime()
        ) {
          phaseEnd = new Date(
            normalizedEnd,
          );
        }
        let taskEnd = new Date(
          phaseEnd,
        );
        if (
          phaseDuration.phaseType ===
          PRODUCTION_PHASE_TYPE_FINITE
        ) {
          taskEnd = new Date(
            phaseStart.getTime() +
              phaseDuration.executionDays *
                MS_PER_DAY -
              1,
          );
          if (
            taskEnd.getTime() >
            phaseEnd.getTime()
          ) {
            taskEnd = new Date(
              phaseEnd,
            );
          }
        }
        cursor = new Date(
          phaseEnd.getTime() + 1,
        );
        return {
          ...phase,
          estimatedDays:
            phaseDuration.executionDays,
          biologicalMinDays:
            phaseDuration.biologicalMinDays,
          startDate: phaseStart,
          endDate: phaseEnd,
          taskStartDate: phaseStart,
          taskEndDate: taskEnd,
        };
      },
    );
  }

  const baseMs = Math.floor(
    totalMs / phaseCount,
  );
  let cursor = new Date(
    normalizedStart,
  );
  return phases.map((phase, index) => {
    const phaseDuration =
      normalizedPhaseDurations[index];
    const isLast =
      index === phaseCount - 1;
    const phaseStart = new Date(cursor);
    const phaseEnd =
      isLast ?
        new Date(normalizedEnd)
      : new Date(
          cursor.getTime() + baseMs,
        );
    cursor = new Date(phaseEnd);

    let taskEnd = new Date(phaseEnd);
    if (
      phaseDuration.phaseType ===
      PRODUCTION_PHASE_TYPE_FINITE
    ) {
      taskEnd = new Date(
        phaseStart.getTime() +
          phaseDuration.executionDays *
            MS_PER_DAY -
          1,
      );
      if (
        taskEnd.getTime() >
        phaseEnd.getTime()
      ) {
        taskEnd = new Date(phaseEnd);
      }
    }

    return {
      ...phase,
      estimatedDays:
        phaseDuration.executionDays,
      biologicalMinDays:
        phaseDuration.biologicalMinDays,
      startDate: phaseStart,
      endDate: phaseEnd,
      taskStartDate: phaseStart,
      taskEndDate: taskEnd,
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
    phaseStart: normalizedPhaseStart,
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
    phaseStart: normalizedPhaseStart,
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
          startHour: parsedStart.hour,
          startMinute:
            parsedStart.minute,
          endHour: parsedEnd.hour,
          endMinute: parsedEnd.minute,
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
            label: blockTemplate.label,
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
    safeWeights.length * minTaskSlotMs;
  if (
    minimumRequiredMs > totalAvailableMs
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
        if (
          blockIndex >= blocks.length
        ) {
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
        taskEndMs =
          chunkStartMs + chunkMs;
        remainingTaskMs -= chunkMs;
        blockOffsetMs += chunkMs;
      }

      const fallbackStartMs =
        phaseStart.getTime();
      const fallbackEndMs =
        phaseEnd.getTime();
      const resolvedStartMs = Math.max(
        fallbackStartMs,
        taskStartMs ?? fallbackStartMs,
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
        weight: safeWeights[taskIndex],
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
    phaseStart: normalizedPhaseStart,
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
    phaseStart: normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
    schedulePolicy: effectivePolicy,
  });
  const totalAvailableMs =
    blocks.reduce(
      (sum, block) =>
        sum +
        Number(block.remainingMs || 0),
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
          totalAvailableMs / MS_PER_HOUR
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
        reason: "NO_CALENDAR_BLOCKS",
        phaseStart:
          normalizedPhaseStart.toISOString(),
        phaseEnd:
          normalizedPhaseEnd.toISOString(),
      },
    );
    return buildTaskScheduleLegacy({
      phaseStart: normalizedPhaseStart,
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
          taskCount * minTaskSlotMs,
        totalAvailableMs,
      },
    );
    return buildTaskScheduleLegacy({
      phaseStart: normalizedPhaseStart,
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
            durationMs / MS_PER_MINUTE,
          ),
        },
      );
    },
  );

  const scheduledTasks =
    scheduleTasksAcrossBlocks({
      tasks,
      safeWeights,
      taskDurations,
      blocks,
      phaseStart: normalizedPhaseStart,
      phaseEnd: normalizedPhaseEnd,
      logContext,
    });
  return applyPinnedTaskScheduleOverrides(
    {
      sourceTasks: tasks,
      scheduledTasks,
      schedulePolicy:
        effectivePolicy,
    },
  );
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

  const resultByIndex = new Array(
    tasks.length,
  );
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
    (task, index) =>
      task || tasks[index],
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

function normalizePersistedProductionTaskType(
  value,
) {
  const normalized = (
    value || ""
  )
    .toString()
    .trim()
    .toLowerCase();
  if (!normalized) {
    return null;
  }
  if (
    PERSISTED_PRODUCTION_TASK_TYPES.has(
      normalized,
    )
  ) {
    return normalized;
  }
  // Imported PDF drafts create already-expanded daily rows, so they should
  // persist as normal workload tasks instead of introducing a new enum.
  if (
    normalized ===
      "imported_document_task" ||
    normalized.startsWith(
      "imported_",
    )
  ) {
    return "workload";
  }
  return null;
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
      "assetType businessId name estate.propertyAddress.country estate.propertyAddress.state",
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
      businessOwner?.productionSchedulePolicy,
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
    if (
      estateAsset.assetType !== "estate"
    ) {
      throw new Error(
        "Estate asset is required for schedule policy",
      );
    }
    estatePolicy =
      normalizeSchedulePolicyInput(
        estateAsset?.productionSchedulePolicy,
        businessPolicy,
      );
  }

  const effectivePolicy =
    estatePolicy ?
      normalizeSchedulePolicyInput(
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
    case "quality_control_manager":
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
 * Owner/staff: mark tenancy agreement as approved after payment + signature.
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
      actor.role !== "business_owner" &&
      actor.role !== "staff"
    ) {
      return res.status(403).json({
        error:
          "Only business owners or staff can approve agreements",
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
    const {
      status,
      carrierName,
      trackingReference,
      dispatchNote,
      estimatedDeliveryDate,
    } = req.body;

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
          dispatch: {
            carrierName,
            trackingReference,
            dispatchNote,
            estimatedDeliveryDate,
          },
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
    const assetActor =
      await buildBusinessAssetActor({
        actor,
        businessId,
      });
    const asset =
      await businessAssetService.createAsset(
        {
          businessId,
          actor: assetActor,
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

async function submitFarmAsset(req, res) {
  debug(
    "BUSINESS CONTROLLER: submitFarmAsset - entry",
    {
      actorId: req.user?.sub,
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );
    const assetActor =
      await buildBusinessAssetActor({
        actor,
        businessId,
      });
    const asset =
      await businessAssetService.submitFarmAsset(
        {
          businessId,
          actor: assetActor,
          payload: req.body,
        },
      );

    return res.status(201).json({
      message:
        asset.approvalStatus === "pending_approval" ?
          "Farm equipment submitted for approval"
        : "Farm equipment created successfully",
      asset,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: submitFarmAsset - error",
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

async function getFarmAssetAuditAnalytics(req, res) {
  debug(
    "BUSINESS CONTROLLER: getFarmAssetAuditAnalytics - entry",
    {
      actorId: req.user?.sub,
      query: req.query,
    },
  );

  try {
    const { businessId } = await getBusinessContext(req.user.sub);
    const analytics = await businessAssetService.getFarmAssetAuditAnalytics({
      businessId,
      query: req.query,
    });

    return res.status(200).json({
      message: "Farm asset audit analytics fetched successfully",
      ...analytics,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getFarmAssetAuditAnalytics - error",
      err.message,
    );
    return res.status(400).json({ error: err.message });
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
    const assetActor =
      await buildBusinessAssetActor({
        actor,
        businessId,
      });
    const asset =
      await businessAssetService.updateAsset(
        {
          businessId,
          assetId: req.params.id,
          payload: req.body,
          actor: assetActor,
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

async function submitFarmAssetAudit(req, res) {
  debug(
    "BUSINESS CONTROLLER: submitFarmAssetAudit - entry",
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
    const assetActor =
      await buildBusinessAssetActor({
        actor,
        businessId,
      });
    const asset =
      await businessAssetService.submitFarmAssetAudit(
        {
          businessId,
          assetId: req.params.id,
          actor: assetActor,
          payload: req.body,
        },
      );

    return res.status(200).json({
      message:
        asset.farmProfile?.pendingAuditRequest?.status ===
            "pending_approval" ?
          "Farm audit submitted for approval"
        : "Farm audit recorded successfully",
      asset,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: submitFarmAssetAudit - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function submitFarmToolUsageRequest(req, res) {
  debug(
    "BUSINESS CONTROLLER: submitFarmToolUsageRequest - entry",
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
    const assetActor =
      await buildBusinessAssetActor({
        actor,
        businessId,
      });
    const asset =
      await businessAssetService.submitFarmToolUsageRequest(
        {
          businessId,
          assetId: req.params.id,
          actor: assetActor,
          payload: req.body,
        },
      );

    const latestUsageRequest =
      Array.isArray(
        asset.farmProfile?.productionUsageRequests,
      ) &&
        asset.farmProfile.productionUsageRequests
          .length > 0
      ? asset.farmProfile.productionUsageRequests[0]
      : null;

    return res.status(200).json({
      message:
        latestUsageRequest?.status ===
            "pending_approval" ?
          "Production tool usage submitted for approval"
        : "Production tool usage logged successfully",
      asset,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: submitFarmToolUsageRequest - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function approveFarmAssetRequest(req, res) {
  debug(
    "BUSINESS CONTROLLER: approveFarmAssetRequest - entry",
    {
      actorId: req.user?.sub,
      assetId: req.params.id,
      requestType: req.body?.requestType,
      requestId: req.body?.requestId,
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
      !canApproveFarmAssetWorkflow({
        actorRole: actor.role,
        staffRole: staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          "Only estate managers, farm managers, asset managers, or business owners can approve farm requests",
      });
    }

    const assetActor = {
      id: actor._id,
      role: actor.role,
      name:
        actor.name ||
        [
          actor.firstName,
          actor.lastName,
        ]
          .filter(Boolean)
          .join(" ")
          .trim(),
      email: actor.email || "",
      staffRole: staffProfile?.staffRole || "",
    };
    const asset =
      await businessAssetService.approveFarmAssetRequest(
        {
          businessId,
          assetId: req.params.id,
          actor: assetActor,
          requestType: req.body?.requestType,
          requestId: req.body?.requestId,
        },
      );

    return res.status(200).json({
      message:
        req.body?.requestType === "audit" ?
          "Farm audit approved successfully"
        : req.body?.requestType === "usage" ?
          "Production tool usage approved successfully"
        : "Farm equipment approved successfully",
      asset,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: approveFarmAssetRequest - error",
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
    const assetActor =
      await buildBusinessAssetActor({
        actor,
        businessId,
      });
    const asset =
      await businessAssetService.softDeleteAsset(
        {
          businessId,
          assetId: req.params.id,
          actor: assetActor,
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
      !isBusinessOwnerEquivalentActor(actor)
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
 * Owner/staff: send staff invites; owners/shareholders/estate managers can send tenant invites.
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

    let staffProfile = null;
    if (actor.role === "staff") {
      staffProfile = await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: false,
      });
    }

    const requestedRole =
      req.body?.role
        ?.toString()
        .trim()
        .toLowerCase() || "";

    if (requestedRole === "tenant") {
      if (
        !canSendTenantInvite({
          actorRole: actor.role,
          staffRole: staffProfile?.staffRole,
        })
      ) {
        return res.status(403).json({
          error:
            "Only business owners, shareholders, or estate managers can send tenant invites",
        });
      }
    } else if (
      !isBusinessOwnerEquivalentActor(actor)
    ) {
      return res.status(403).json({
        error:
          "Only business owners can send staff invites",
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
    const normalizedRole =
      role.toLowerCase();

    const agreementText =
      req.body?.agreementText
        ?.toString()
        .trim() || "";

    const sendEmailRaw = req.body?.sendEmail;
    const shouldSendEmail = !(
      sendEmailRaw === false ||
      (sendEmailRaw ?? "")
        .toString()
        .trim()
        .toLowerCase() === "false"
    );

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
      normalizedRole === "tenant" &&
      (!agreementText ||
        agreementText.length === 0)
    ) {
      return res.status(400).json({
        error:
          "Agreement text is required for tenant invites",
      });
    }
    if (
      normalizedRole === "staff" &&
      (!staffRole ||
        staffRole.length === 0)
    ) {
      return res.status(400).json({
        error:
          STAFF_COPY.STAFF_ROLE_REQUIRED,
      });
    }
    if (
      normalizedRole === "staff" &&
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
          role: normalizedRole,
          staffRole,
          estateAssetId,
          agreementText,
          shouldSendEmail,
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
        shouldSendEmail ?
          "Invite sent successfully"
        : "Request link created successfully",
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

    const acceptedUser = user.toObject();
    acceptedUser.staffRole = invite.staffRole || null;

    return res.status(200).json({
      message:
        "Invite accepted successfully",
      user: acceptedUser,
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
function serializeStaffProfileSummary(
  profile,
) {
  return {
    id:
      profile?._id ||
      profile?.id ||
      "",
    staffRole:
      profile?.staffRole || "",
    status:
      profile?.status || "",
    estateAssetId:
      profile?.estateAssetId ||
      null,
    startDate:
      profile?.startDate || null,
    endDate:
      profile?.endDate || null,
    notes: profile?.notes || "",
    user:
      profile?.userId ||
      profile?.user ||
      null,
  };
}

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
      serializeStaffProfileSummary,
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
      staff:
        serializeStaffProfileSummary(
          profile,
        ),
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
          STAFF_COMPENSATION_FIELDS.PROFIT_SHARE_PERCENTAGE,
        ),
      hasPayoutTrigger:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          STAFF_COMPENSATION_FIELDS.PAYOUT_TRIGGER,
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
        STAFF_COMPENSATION_FIELDS.PROFIT_SHARE_PERCENTAGE,
      );
    const hasIncludesHousing =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS.INCLUDES_HOUSING,
      );
    const hasIncludesFeeding =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS.INCLUDES_FEEDING,
      );
    const hasPayoutTrigger =
      Object.prototype.hasOwnProperty.call(
        body,
        STAFF_COMPENSATION_FIELDS.PAYOUT_TRIGGER,
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
        Number(rawProfitSharePercentage)
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
            isProfitShareCadence ? null
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
      nextCadence === "profit_share";
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
        Number(profitSharePercentage);
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
        nextIsProfitShare ? "sale" : (
          "attendance"
        );
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
    const requestedAttendanceId =
      canManage ?
        normalizeStaffIdInput(
          req.body?.attendanceId,
        )
      : "";
    const manualClockInAt =
      canManage ?
        parseDateInput(
          req.body?.clockInAt,
        )
      : null;
    const requestedWorkDate =
      normalizeWorkDateToDayStart(
        req.body?.workDate,
      );
    const relatedPlanId =
      normalizeStaffIdInput(
        req.body?.planId,
      );
    const relatedTaskId =
      normalizeStaffIdInput(
        req.body?.taskId,
      );
    const auditNote =
      (
        req.body?.notes
          ?.toString()
          .trim() || ""
      );

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

    const resolvedClockInAt =
      manualClockInAt || new Date();
    const auditWorkDate =
      requestedWorkDate ||
      normalizeWorkDateToDayStart(
        resolvedClockInAt,
      );
    let attendance = null;
    let auditAction =
      "staff_attendance_clock_in_create";
    let previousClockInAt = null;

    if (requestedAttendanceId) {
      attendance =
        await StaffAttendance.findOne({
          _id: requestedAttendanceId,
          staffProfileId:
            targetProfile._id,
        });
      if (!attendance) {
        return res.status(404).json({
          error:
            "Attendance record not found",
        });
      }
      const existingClockOutAt =
        parseDateInput(
          attendance.clockOutAt,
        );
      if (
        existingClockOutAt &&
        resolvedClockInAt >
          existingClockOutAt
      ) {
        return res.status(400).json({
          error:
            "Clock-in cannot be after clock-out",
        });
      }
      previousClockInAt =
        attendance.clockInAt || null;
      attendance.clockInAt =
        resolvedClockInAt;
      attendance.clockInBy =
        actor._id;
      if (existingClockOutAt) {
        attendance.durationMinutes =
          resolveAttendanceDurationMinutes(
            {
              ...attendance.toObject(),
              clockInAt:
                resolvedClockInAt,
              clockOutAt:
                existingClockOutAt,
            },
          );
      }
      await attendance.save();
      auditAction =
        "staff_attendance_clock_in_update";
    } else {
      const scopedOpenFilter = {
        staffProfileId:
          targetProfile._id,
        clockOutAt: null,
      };
      if (relatedTaskId) {
        scopedOpenFilter.taskId =
          relatedTaskId;
      }
      if (auditWorkDate) {
        scopedOpenFilter.workDate =
          auditWorkDate;
      }
      if (relatedPlanId) {
        scopedOpenFilter.planId =
          relatedPlanId;
      }
      const existingScopedOpen =
        relatedTaskId && auditWorkDate ?
          await StaffAttendance.findOne(
            scopedOpenFilter,
          )
        : null;
      if (existingScopedOpen) {
        attendance =
          existingScopedOpen;
        auditAction =
          "staff_attendance_clock_in_resume";
      } else {
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

      attendance =
        await StaffAttendance.create({
          staffProfileId:
            targetProfile._id,
          planId:
            relatedPlanId || null,
          taskId:
            relatedTaskId || null,
          workDate:
            auditWorkDate || null,
          clockInAt:
            resolvedClockInAt,
          clockInBy: actor._id,
          notes: auditNote,
        });
      }
    }

    if (
      attendance &&
      (relatedPlanId ||
        relatedTaskId ||
        auditWorkDate)
    ) {
      attendance.planId =
        relatedPlanId || null;
      attendance.taskId =
        relatedTaskId || null;
      attendance.workDate =
        auditWorkDate || null;
      if (
        auditNote &&
        !attendance.notes
      ) {
        attendance.notes =
          auditNote;
      }
      await attendance.save();
    }

    await writeAuditLog({
      businessId,
      actorId: actor._id,
      actorRole: actor.role,
      action: auditAction,
      entityType: "staff_attendance",
      entityId: attendance._id,
      message:
        "Set staff clock-in",
      changes: {
        staffProfileId:
          targetProfile._id,
        workDate:
          auditWorkDate ||
          null,
        planId:
          relatedPlanId || null,
        taskId:
          relatedTaskId || null,
        previousClockInAt:
          previousClockInAt ||
          null,
        clockInAt:
          attendance.clockInAt,
        manualEntry:
          canManage &&
          manualClockInAt != null,
        note:
          auditNote || null,
      },
    });

    // CONFIDENCE-SCORE
    // WHY: Clock-in changes real staff availability and should refresh active-plan confidence in this estate scope.
    try {
      await triggerScopedAvailabilityConfidenceRecompute(
        {
          businessId,
          estateAssetId:
            targetProfile.estateAssetId ||
            null,
          actorId: actor._id,
          operation: "clockInStaff",
        },
      );
    } catch (confidenceErr) {
      // WHY: Attendance writes are operational truth and must not fail because confidence recompute failed.
      debug(
        "BUSINESS CONTROLLER: clockInStaff - confidence recompute skipped",
        {
          actorId: actor._id,
          staffProfileId:
            targetProfile._id,
          reason: confidenceErr.message,
          next: "Retry confidence recompute on next availability trigger",
        },
        );
    }

    if (relatedPlanId) {
      await emitProductionPlanRoomSnapshot({
        businessId,
        planId: relatedPlanId,
        context: "staff_clock_in",
      });
    }

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
    const requestedAttendanceId =
      canManage ?
        normalizeStaffIdInput(
          req.body?.attendanceId,
        )
      : "";
    const manualClockOutAt =
      canManage ?
        parseDateInput(
          req.body?.clockOutAt,
        )
      : null;
    const requestedWorkDate =
      normalizeWorkDateToDayStart(
        req.body?.workDate,
      );
    const relatedPlanId =
      normalizeStaffIdInput(
        req.body?.planId,
      );
    const relatedTaskId =
      normalizeStaffIdInput(
        req.body?.taskId,
      );
    const auditNote =
      (
        req.body?.notes
          ?.toString()
          .trim() || ""
      );

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

    const attendance =
      requestedAttendanceId ?
        await StaffAttendance.findOne({
          _id: requestedAttendanceId,
          staffProfileId:
            targetProfile._id,
        })
      : await StaffAttendance.findOne(
          relatedTaskId &&
              requestedWorkDate ?
            {
              staffProfileId:
                targetProfile._id,
              taskId:
                relatedTaskId,
              workDate:
                requestedWorkDate,
              clockOutAt: null,
            }
          : {
              staffProfileId:
                targetProfile._id,
              clockOutAt: null,
            },
        );

    if (!attendance) {
      return res.status(
        requestedAttendanceId ?
          404
        : 400,
      ).json({
        error:
          requestedAttendanceId ?
            "Attendance record not found"
          : STAFF_COPY.STAFF_CLOCK_OUT_MISSING,
      });
    }

    const clockOutAt =
      manualClockOutAt ||
      new Date();
    const clockInAt =
      parseDateInput(
        attendance.clockInAt,
      );
    if (
      !clockInAt ||
      clockOutAt < clockInAt
    ) {
      return res.status(400).json({
        error:
          "Clock-out cannot be before clock-in",
      });
    }
    const durationMinutes = Math.max(
      0,
      Math.floor(
        (clockOutAt -
          clockInAt) /
          MS_PER_MINUTE,
      ),
    );

    const previousClockOutAt =
      attendance.clockOutAt || null;
    const auditWorkDate =
      requestedWorkDate ||
      normalizeWorkDateToDayStart(
        attendance.clockInAt,
      );

    attendance.clockOutAt =
      clockOutAt;
    attendance.clockOutBy =
      actor._id;
    attendance.durationMinutes =
      durationMinutes;
    attendance.planId =
      relatedPlanId ||
      attendance.planId ||
      null;
    attendance.taskId =
      relatedTaskId ||
      attendance.taskId ||
      null;
    attendance.workDate =
      auditWorkDate ||
      attendance.workDate ||
      null;
    await attendance.save();

    await writeAuditLog({
      businessId,
      actorId: actor._id,
      actorRole: actor.role,
      action:
        requestedAttendanceId ?
          "staff_attendance_clock_out_update"
        : "staff_attendance_clock_out_set",
      entityType: "staff_attendance",
      entityId: attendance._id,
      message:
        "Set staff clock-out",
      changes: {
        staffProfileId:
          targetProfile._id,
        workDate:
          auditWorkDate ||
          null,
        planId:
          relatedPlanId || null,
        taskId:
          relatedTaskId || null,
        previousClockOutAt:
          previousClockOutAt ||
          null,
        clockOutAt,
        durationMinutes,
        manualEntry:
          canManage &&
          manualClockOutAt != null,
        note:
          auditNote || null,
      },
    });

    // CONFIDENCE-SCORE
    // WHY: Clock-out updates availability capacity and should trigger scoped confidence refresh.
    try {
      await triggerScopedAvailabilityConfidenceRecompute(
        {
          businessId,
          estateAssetId:
            targetProfile.estateAssetId ||
            null,
          actorId: actor._id,
          operation: "clockOutStaff",
        },
      );
    } catch (confidenceErr) {
      // WHY: Attendance persistence remains the source of truth even if confidence recompute fails.
      debug(
        "BUSINESS CONTROLLER: clockOutStaff - confidence recompute skipped",
        {
          actorId: actor._id,
          staffProfileId:
            targetProfile._id,
          reason: confidenceErr.message,
          next: "Retry confidence recompute on next availability trigger",
        },
        );
    }

    if (relatedPlanId) {
      await emitProductionPlanRoomSnapshot({
        businessId,
        planId: relatedPlanId,
        context: "staff_clock_out",
      });
    }

    debug(
      "BUSINESS CONTROLLER: clockOutStaff - success",
      {
        actorId: actor._id,
        attendanceId:
          attendance._id,
        staffProfileId:
          targetProfile._id,
        durationMinutes,
      },
    );

    return res.status(200).json({
      message:
        STAFF_COPY.STAFF_CLOCK_OUT_OK,
      attendance,
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
 * POST /business/staff/attendance/:attendanceId/proof
 * Staff + managers: upload proof immediately after clock-out.
 */
async function uploadStaffAttendanceProof(req, res) {
  debug(
    "BUSINESS CONTROLLER: uploadStaffAttendanceProof - entry",
    {
      actorId: req.user?.sub,
      attendanceId: req.params?.attendanceId,
      hasFile: Boolean(req.file),
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

    const attendanceId =
      req.params?.attendanceId
        ?.toString()
        .trim();
    if (!attendanceId) {
      return res.status(400).json({
        error: "Attendance id is required",
      });
    }
    if (!req.file) {
      return res.status(400).json({
        error: "Proof file is required",
      });
    }

    const attendance =
      await StaffAttendance.findById(
        attendanceId,
      );
    if (!attendance) {
      return res.status(404).json({
        error: "Attendance record not found",
      });
    }

    const targetProfile =
      await BusinessStaffProfile.findOne(
        {
          _id: attendance.staffProfileId,
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
      !canManage &&
      staffProfile?._id?.toString() !==
        targetProfile._id.toString()
    ) {
      return res.status(403).json({
        error:
          "Cannot upload proof for another staff member",
      });
    }

    if (!attendance.clockOutAt) {
      return res.status(409).json({
        error:
          "Clock-out must be recorded before uploading proof",
      });
    }

    const proof =
      await staffAttendanceProofService.uploadStaffAttendanceProof(
        {
          businessId,
          attendanceId:
            attendance._id.toString(),
          file: req.file,
        },
      );

    attendance.proofUrl = proof.url;
    attendance.proofPublicId = proof.publicId;
    attendance.proofFilename = proof.filename;
    attendance.proofMimeType = proof.mimeType;
    attendance.proofSizeBytes = proof.sizeBytes;
    attendance.proofUploadedAt = new Date();
    attendance.proofUploadedBy = actor._id;
    await attendance.save();

    await writeAuditLog({
      businessId,
      actorId: actor._id,
      actorRole: actor.role,
      action: "staff_attendance_proof_upload",
      entityType: "staff_attendance",
      entityId: attendance._id,
      message: "Uploaded staff attendance proof",
      changes: {
        staffProfileId:
          targetProfile._id,
        proofUrl: proof.url,
        proofFilename: proof.filename,
        proofMimeType: proof.mimeType,
        proofSizeBytes: proof.sizeBytes,
      },
    });

    debug(
      "BUSINESS CONTROLLER: uploadStaffAttendanceProof - success",
      {
        actorId: actor._id,
        attendanceId:
          attendance._id,
        staffProfileId:
          targetProfile._id,
      },
    );

    return res.status(200).json({
      message:
        "Staff attendance proof uploaded successfully",
      attendance,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: uploadStaffAttendanceProof - error",
      err.message,
    );
    return res.status(400).json({
      error: err.message,
    });
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
 * Owner + draft editors: resolve effective production schedule policy.
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
      !canUseProductionPlanDraftTools({
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
      req.query?.estateAssetId || ""
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
      await resolveEffectiveSchedulePolicy(
        {
          businessId,
          estateAssetId:
            estateAssetIdRaw || null,
        },
      );

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
        businessDefault: businessPolicy,
        estateOverride: estatePolicy,
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
      hasPolicyPayload: Boolean(
        req.body,
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
          PRODUCTION_COPY.SCHEDULE_POLICY_FORBIDDEN,
      });
    }

    const estateAssetIdRaw = (
      req.query?.estateAssetId || ""
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
      await resolveEffectiveSchedulePolicy(
        {
          businessId,
          estateAssetId:
            estateAssetIdRaw || null,
        },
      );
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
      if (
        estateAsset.assetType !==
        "estate"
      ) {
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

    // CONFIDENCE-SCORE
    // WHY: Schedule policy changes influence effective capacity windows and must refresh scoped confidence.
    try {
      await triggerScopedAvailabilityConfidenceRecompute(
        {
          businessId,
          estateAssetId:
            estateAssetIdRaw || null,
          actorId: actor._id,
          operation:
            "updateProductionSchedulePolicy",
        },
      );
    } catch (confidenceErr) {
      // WHY: Policy updates must succeed even if derived confidence recompute fails.
      debug(
        "BUSINESS CONTROLLER: updateProductionSchedulePolicy - confidence recompute skipped",
        {
          actorId: actor._id,
          businessId:
            businessId.toString(),
          estateAssetId:
            estateAssetIdRaw || null,
          reason: confidenceErr.message,
          next: "Retry confidence recompute on next deterministic trigger",
        },
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
 * Owner + draft editors: summarize role capacity for AI planning and staffing warnings.
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
      !canUseProductionPlanDraftTools({
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
      req.query?.estateAssetId || ""
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
        estateAssetId: estateAssetIdRaw,
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
 * GET /business/production/plans/crop-search
 * Owner + draft editors: search planner-backed crop options for the assistant flow.
 */
async function searchProductionAssistantCatalogHandler(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: searchProductionAssistantCatalog - entry",
    {
      actorId: req.user?.sub,
      query:
        req.query?.q ||
        req.query?.query ||
        "",
      domainContext:
        req.query?.domainContext,
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
      !canUseProductionPlanDraftTools({
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

    const query = (
      req.query?.q ||
      req.query?.query ||
      ""
    )
      .toString()
      .trim();
    const limit =
      normalizeAssistantCropSearchLimit(
        req.query?.limit,
      );
    const estateAssetId = (
      req.query?.estateAssetId || ""
    )
      .toString()
      .trim();
    const domainContext =
      parseDomainContextInput(
        req.query?.domainContext,
      ).value;
    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      estateAssetId &&
      actor.estateAssetId.toString() !==
        estateAssetId
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }
    const estateAsset =
      estateAssetId ?
        await resolveEstateAsset({
          estateAssetId,
          businessId,
        })
      : null;

    let items = [];
    if (domainContext === "farm") {
      items =
        await buildAssistantPlannerCropSearchResults(
          {
            businessId,
            query,
            limit,
            context: {
              route:
                req.originalUrl ||
                "/business/production/plans/crop-search",
              requestId: req.id,
              userRole: actor.role,
              businessId,
              source:
                "assistant_crop_search",
              estateCountry:
                estateAsset?.estate
                  ?.propertyAddress
                  ?.country || "",
              estateState:
                estateAsset?.estate
                  ?.propertyAddress
                  ?.state || "",
              country:
                req.headers?.[
                  COUNTRY_HEADER_KEY
                ] || DEFAULT_COUNTRY,
            },
          },
        );
    } else {
      const localProductFilter = {
        businessId,
        deletedAt: null,
      };
      if (query) {
        localProductFilter.name = {
          $regex: new RegExp(
            escapeRegexPattern(query),
            "i",
          ),
        };
      }
      const products =
        await Product.find(
          localProductFilter,
        )
          .select({
            _id: 1,
            name: 1,
            description: 1,
            isActive: 1,
          })
          .sort({ updatedAt: -1 })
          .limit(limit)
          .lean();
      items = products.map((product) => ({
        id:
          product?._id?.toString?.() ||
          "",
        cropKey: "",
        name:
          product?.name
            ?.toString?.()
            .trim() || "",
        aliases: [],
        source: "business_product",
        minDays: 0,
        maxDays: 0,
        phases: [],
        profileKind: "crop",
        category: "",
        variety: "",
        plantType: "",
        summary: "",
        scientificName: "",
        family: "",
        verificationStatus: "",
        climate: {},
        soil: {},
        water: {},
        propagation: {},
        harvestWindow: {},
        sourceProvenance: [],
        linkedProductId:
          product?._id?.toString?.() ||
          "",
        linkedProductName:
          product?.name
            ?.toString?.() || "",
        linkedProductActive:
          product?.isActive === true,
      }));
    }

    debug(
      "BUSINESS CONTROLLER: searchProductionAssistantCatalog - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        domainContext,
        count: items.length,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_ASSISTANT_CROP_SEARCH_OK,
      items,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: searchProductionAssistantCatalog - error",
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
 * GET /business/production/plans/crop-lifecycle
 * Owner + draft editors: resolve lifecycle preview for one crop from the seeded crop database.
 */
async function previewProductionAssistantCropLifecycleHandler(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: previewProductionAssistantCropLifecycle - entry",
    {
      actorId: req.user?.sub,
      productName:
        req.query?.productName ||
        req.query?.cropName ||
        req.query?.query ||
        "",
      estateAssetId:
        req.query?.estateAssetId ||
        null,
      domainContext:
        req.query?.domainContext,
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
      !canUseProductionPlanDraftTools({
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

    const productName = (
      req.query?.productName ||
      req.query?.cropName ||
      req.query?.query ||
      ""
    )
      .toString()
      .trim();
    const cropSubtype = (
      req.query?.cropSubtype || ""
    )
      .toString()
      .trim();
    const domainContext =
      parseDomainContextInput(
        req.query?.domainContext,
      ).value;
    const estateAssetId = (
      req.query?.estateAssetId || ""
    )
      .toString()
      .trim();

    if (!productName && !cropSubtype) {
      return res.status(400).json({
        error:
          "Crop name is required for lifecycle preview.",
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          "PRODUCTION_AI_CROP_NAME_REQUIRED",
        resolution_hint:
          "Select one crop before resolving lifecycle days.",
        retry_allowed: false,
        retry_reason:
          "client_validation_failed",
      });
    }

    if (
      actor.role === "staff" &&
      actor.estateAssetId &&
      estateAssetId &&
      actor.estateAssetId.toString() !==
        estateAssetId
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const estateAsset =
      estateAssetId ?
        await resolveEstateAsset({
          estateAssetId,
          businessId,
        })
      : null;

    const resolvedLifecycle =
      await resolveVerifiedAgricultureLifecycle({
        businessId,
        productName,
        cropSubtype,
        domainContext,
        aliases: [productName, cropSubtype],
        context: {
          route:
            req.originalUrl ||
            "/business/production/plans/crop-lifecycle",
          requestId: req.id,
          userRole: actor.role,
          businessId,
          source:
            "assistant_crop_lifecycle_preview",
          estateCountry:
            estateAsset?.estate
              ?.propertyAddress
              ?.country || "",
          estateState:
            estateAsset?.estate
              ?.propertyAddress
              ?.state || "",
          country:
            req.headers?.[
              COUNTRY_HEADER_KEY
            ] || DEFAULT_COUNTRY,
        },
      });
    if (!resolvedLifecycle) {
      return res.status(422).json({
        error:
          "Crop lifecycle data is unavailable in the seeded crop database.",
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          "PRODUCTION_AI_LIFECYCLE_STORE_UNAVAILABLE",
        resolution_hint:
          "Try another crop name or seed the crop database with verified lifecycle records for this crop.",
        retry_allowed: false,
        retry_reason:
          "missing_lifecycle_data",
      });
    }
    const lifecycle =
      resolvedLifecycle.lifecycle;
    const lifecycleSource =
      (
        resolvedLifecycle.lifecycleSource ||
        "verified_store"
      )
        .toString()
        .trim();

    debug(
      "BUSINESS CONTROLLER: previewProductionAssistantCropLifecycle - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        productName:
          lifecycle.product,
        lifecycleSource,
        minDays:
          lifecycle.minDays,
        maxDays:
          lifecycle.maxDays,
      },
    );

    return res.status(200).json({
      message:
        "Crop lifecycle resolved successfully.",
      lifecycle,
      lifecycleSource,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: previewProductionAssistantCropLifecycle - error",
      {
        actorId: req.user?.sub,
        reason: err.message,
        errorCode:
          err.errorCode || null,
      },
    );
    return res.status(
      err?.statusCode || 400,
    ).json({
      error:
        err.message ||
        "Crop lifecycle preview failed.",
      classification:
        err.classification ||
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        err.errorCode || "",
      resolution_hint:
        err.resolutionHint || "",
      retry_allowed:
        err.retryAllowed === true,
      retry_reason:
        err.retryReason || "",
      details:
        err.details || {},
    });
  }
}

/**
 * POST /business/production/plans/assistant-turn
 * Owner + draft editors: chat-first assistant turn that guides draft generation and product selection.
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
      productId: req.body?.productId,
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
      !canUseProductionPlanDraftTools({
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
    const draftPlanId =
      normalizeStaffIdInput(
        req.body?.planId,
      );
    const workloadTotalUnits =
      parseWorkloadContextTotalUnits(
        req.body?.workloadContext,
      );
    const focusedRoles =
      normalizeStringArrayInput(
        Array.isArray(req.body?.focusedRoles) ?
          req.body.focusedRoles
        : req.body?.workloadContext
            ?.focusedRoles,
        { lowerCase: true },
      );
    const focusedStaffProfileIds =
      normalizeStringArrayInput(
        Array.isArray(
          req.body?.focusedStaffProfileIds,
        ) ?
          req.body.focusedStaffProfileIds
        : req.body?.workloadContext
            ?.focusedStaffProfileIds,
      );
    const focusedStaffByRole =
      normalizeStringListMapInput(
        req.body?.focusedStaffByRole ||
          req.body?.workloadContext
            ?.focusedStaffByRole,
        { lowerCaseKeys: true },
      );
    const focusedRoleTaskHints =
      normalizeStringListMapInput(
        req.body?.focusedRoleTaskHints ||
          req.body?.workloadContext
            ?.focusedRoleTaskHints,
        {
          lowerCaseKeys: true,
          lowerCaseValues: true,
        },
      );

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
      (
        actor.role === "staff" &&
        actor.estateAssetId
      ) ?
        actor.estateAssetId.toString()
      : estates.length === 1 ?
        estates[0]._id.toString()
      : "";
    const resolvedEstateAssetId =
      estateAssetIdRaw ||
      defaultEstateId;

    if (!resolvedEstateAssetId) {
      const estateSuggestions =
        estates.map(
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
    const productSearchNameRaw = (
      req.body?.productSearchName ||
      req.body?.productName ||
      ""
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
    } else if (domainContext === "farm") {
      const plannerSearchQuery =
        productSearchNameRaw ||
        userInput;
      const plannerMatches =
        await buildAssistantPlannerCropSearchResults(
          {
            businessId,
            query: plannerSearchQuery,
            limit: 6,
          },
        );
      const exactPlannerMatch =
        plannerMatches.find((item) =>
          isExactAssistantCropMatch({
            query:
              productSearchNameRaw ||
              plannerSearchQuery,
            item,
          }),
        ) ||
        (
          productSearchNameRaw &&
          plannerMatches.length > 0
        ?
          plannerMatches[0]
        : null
        );
      if (exactPlannerMatch) {
        selectedProduct =
          await resolveAssistantPlannerProduct(
            {
              businessId,
              actor,
              productSearchName:
                exactPlannerMatch.name,
              productCatalog,
            },
          );
      } else if (
        plannerSearchQuery
      ) {
        const plannerSuggestions =
          plannerMatches
            .slice(0, 6)
            .map(
              (item) =>
                `Use crop: ${item.name}`,
            );
        const turn =
          buildAssistantTurnSuggestions({
            message:
              "Search the planner crop list and choose the crop you want to schedule.",
            suggestions: [
              ...plannerSuggestions,
              "Use the crop search field to pick a planner-supported crop.",
            ],
          });
        return res.status(200).json({
          message:
            PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
          turn,
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
      if (
        domainContext === "farm"
      ) {
        const plannerSuggestions =
          await buildAssistantPlannerCropSearchResults(
            {
              businessId,
              query: "",
              limit: 6,
            },
          );
        const turn =
          buildAssistantTurnSuggestions({
            message:
              PRODUCTION_COPY.ASSISTANT_PRODUCT_REQUIRED,
            suggestions: [
              ...plannerSuggestions.map(
                (item) =>
                  `Use crop: ${item.name}`,
              ),
              "Search the seeded crop database and select one crop before generating the draft.",
            ],
          });
        return res.status(200).json({
          message:
            PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
          turn,
        });
      }

      if (userInput) {
        const draftProduct =
          buildAssistantDraftProductFromInput(
            userInput,
          );
        const turn =
          buildAssistantTurnDraftProduct(
            {
              message:
                "I could not match that to an existing product, so I drafted one for you.",
              draftProduct,
              confirmationQuestion:
                "Create this product now, then I will generate the full production plan.",
            },
          );
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
    if (startDateRaw && !startDate) {
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
    if (endDateRaw && !endDate) {
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

    // WHY: Assistant draft generation should have explicit start/end boundary logs for stage-0 diagnostics.
    logProductionLifecycleBoundary({
      operation: "draft_generation",
      stage: "start",
      intent:
        "generate assistant draft before plan commit",
      actorId: actor._id,
      businessId,
      context: {
        route:
          "/business/production/plans/assistant-turn",
        source: "assistant_turn",
        estateAssetId:
          resolvedEstateAssetId,
        productId:
          selectedProduct._id.toString(),
        hasUserInput:
          Boolean(userInput),
        hasStartDate:
          Boolean(startDate),
        hasEndDate: Boolean(endDate),
      },
    });

    // WHY: Reuse the existing draft endpoint logic so calendar scheduling stays consistent.
    const aiDraftInvocation =
      await invokeControllerHandlerJson(
        {
          handler:
            generateProductionPlanDraftHandler,
          request: {
            ...req,
            // WHY: Assistant invokes draft handler with a synthetic request object,
            // so we must provide safe header/request metadata defaults.
            headers: req.headers || {},
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
                selectedProduct._id.toString(),
              planId:
                normalizeStaffIdInput(
                  req.body?.planId,
                ) || "",
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
              focusedRoles,
              focusedStaffProfileIds,
              focusedStaffByRole,
              focusedRoleTaskHints,
              workloadContext:
                (
                  req.body
                    ?.workloadContext &&
                  typeof req.body
                    .workloadContext ===
                    "object"
                ) ?
                  {
                    ...req.body
                      .workloadContext,
                    focusedRoles,
                    focusedStaffProfileIds,
                    focusedStaffByRole,
                    focusedRoleTaskHints,
                  }
                : {
                    focusedRoles,
                    focusedStaffProfileIds,
                    focusedStaffByRole,
                    focusedRoleTaskHints,
                  },
            },
            query: {},
          },
        },
      );

    if (
      aiDraftInvocation.statusCode >=
      400
    ) {
      logProductionLifecycleBoundary({
        operation: "draft_generation",
        stage: "failure",
        intent:
          "generate assistant draft before plan commit",
        actorId: actor._id,
        businessId,
        context: {
          route:
            "/business/production/plans/assistant-turn",
          source: "assistant_turn",
          statusCode:
            aiDraftInvocation.statusCode,
        },
      });
      const draftError =
        (
          aiDraftInvocation.payload &&
          typeof aiDraftInvocation.payload ===
            "object"
        ) ?
          aiDraftInvocation.payload
        : {};
      const errorCode = (
        draftError.error_code || ""
      )
        .toString()
        .trim();
      const failureClassification = (
        draftError.classification || ""
      )
        .toString()
        .trim()
        .toUpperCase();
      const retryAllowed =
        draftError.retry_allowed ===
        true;
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
              startDate ? "endDate" : (
                "startDate"
              ),
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
      const shouldClarifyLifecycle =
        aiDraftInvocation.statusCode ===
          422 &&
        errorCode.includes(
          "LIFECYCLE_UNAVAILABLE",
        );
      if (shouldClarifyLifecycle) {
        const lifecycleMessage =
          draftError.error
            ?.toString()
            .trim() ||
          "I could not find trusted lifecycle data for this product.";
        const lifecycleResolutionHint =
          draftError.resolution_hint
            ?.toString()
            .trim() ||
          "Use a product with lifecycle support or configure the farm lifecycle source before generating the plan.";
        const turn =
          buildAssistantTurnSuggestions(
            {
              message: lifecycleMessage,
              suggestions: [
                `Use a supported crop name for ${selectedProduct.name} or pick a product with known farm lifecycle data.`,
                "Add lifecycle data to the farm product catalog or cache.",
                "Configure the agriculture lifecycle API, then retry.",
                lifecycleResolutionHint,
              ],
            },
          );
        return res.status(200).json({
          message:
            PRODUCTION_COPY.PLAN_ASSISTANT_TURN_OK,
          turn,
        });
      }
      const shouldReturnAssistantRetryTurn =
        retryAllowed &&
        [
          "UNKNOWN_PROVIDER_ERROR",
          "PROVIDER_OUTAGE",
          "RATE_LIMITED",
          "AUTHENTICATION_ERROR",
          "PROVIDER_REJECTED_FORMAT",
        ].includes(
          failureClassification,
        );
      if (
        shouldReturnAssistantRetryTurn
      ) {
        const providerFailureMessage = (
          draftError.error || ""
        )
          .toString()
          .trim();
        const resolutionHint = (
          draftError.resolution_hint ||
          ""
        )
          .toString()
          .trim();
        const sanitizedProviderFailureMessage =
          sanitizeProductionAssistantFailureMessage(
            {
              message:
                providerFailureMessage,
              errorCode:
                draftError.error_code,
              classification:
                draftError.classification,
            },
          );
        const retryReason = (
          draftError.retry_reason || ""
        )
          .toString()
          .trim();
        // WHY: Assistant-turn should remain conversational and never hard-fail the UI on transient provider issues.
        const turn =
          buildAssistantTurnSuggestions(
            {
              message:
                sanitizedProviderFailureMessage ||
                "I could not reach the planning assistant provider right now, but your context is saved.",
              suggestions: [
                "Retry draft generation with current context.",
                `Use selected estate + product (${selectedProduct.name}) and regenerate.`,
                startDate || endDate ?
                  "Adjust timeline range, then retry."
                : "Add preferred start/end dates, then retry.",
                resolutionHint ||
                  "Transient provider errors can recover on retry.",
                retryReason ?
                  `Retry reason: ${retryReason}`
                : "Retry now.",
              ],
            },
          );
        debug(
          "BUSINESS CONTROLLER: productionPlanAssistantTurn - provider failure degraded to assistant retry turn",
          {
            actorId: actor._id,
            businessId:
              businessId.toString(),
            statusCode:
              aiDraftInvocation.statusCode,
            classification:
              failureClassification ||
              "UNKNOWN_PROVIDER_ERROR",
            retryAllowed,
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
              selectedProduct.name ||
              "",
            domainContext,
          },
        });
      }
      return res
        .status(
          aiDraftInvocation.statusCode,
        )
        .json(draftError);
    }

    const aiDraftResponse =
      (
        aiDraftInvocation.payload &&
        typeof aiDraftInvocation.payload ===
          "object"
      ) ?
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

    logProductionLifecycleBoundary({
      operation: "draft_generation",
      stage: "success",
      intent:
        "generate assistant draft before plan commit",
      actorId: actor._id,
      businessId,
      context: {
        route:
          "/business/production/plans/assistant-turn",
        source: "assistant_turn",
        statusCode:
          aiDraftInvocation.statusCode,
        phaseCount:
          planPayload.phases.length,
        planningDays: planPayload.days,
      },
    });

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
        planningDays: planPayload.days,
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
        estateAssetId: estateAsset._id,
        estateName:
          estateAsset.name || "",
        productId: selectedProduct._id,
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
 * Owner + draft editors: generate an AI draft for a production plan.
 */
function buildAiDraftSourceDocumentPrompt(sourceDocumentContext) {
  if (!sourceDocumentContext?.text) {
    return "";
  }

  const safeFileName =
    sourceDocumentContext.fileName || "uploaded source document";
  const extension =
    sourceDocumentContext.extension || "file";
  const taskDensityInstruction =
    sourceDocumentContext.taskLineEstimate > 0
      ? `The uploaded source contains about ${sourceDocumentContext.taskLineEstimate} explicit task-like lines. Preserve roughly that task density and do not compress it into a short summary draft.`
      : "Treat the uploaded source as a detailed working plan, not a short outline.";

  return [
    `Uploaded source document: ${safeFileName} (${extension}).`,
    taskDensityInstruction,
    "Use this source as the primary planning backbone.",
    "Preserve explicit phases, day labels, task rows, sequences, staffing counts, and recurring operational work where they are coherent.",
    "Do not collapse a task-rich document into a sparse phase summary or reduce dozens of explicit tasks down to a handful of generic milestones.",
    "If the source already contains a full working schedule, keep the resulting draft close to that scope and detail unless there are obvious duplicates or contradictions.",
    "SOURCE DOCUMENT START",
    sourceDocumentContext.text,
    "SOURCE DOCUMENT END",
  ].join("\n");
}

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
      hasSourceDocument: Boolean(
        req.body?.sourceDocument,
      ),
      hasPlantingTargets: Boolean(
        req.body?.plantingTargets ||
          req.body?.workloadContext
            ?.plantingTargets,
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
      !canUseProductionPlanDraftTools({
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
    const productSearchNameRaw = (
      req.body?.productSearchName ||
      req.body?.productName ||
      ""
    )
      .toString()
      .trim();
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
        .trim() ||
      "";
    const sourceDocumentContext =
      extractAiDraftSourceDocumentContext(
        req.body?.sourceDocument,
      );
    const refineTarget =
      normalizeDraftRefineTargetInput(
        req.body?.refineTarget,
      );
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
    const plantingTargets =
      normalizePlantingTargetsInput(
        req.body?.plantingTargets ||
          req.body?.workloadContext
            ?.plantingTargets,
      );
    if (
      domainContext === "farm" &&
      !hasCompletePlantingTargets(
        plantingTargets,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLANTING_TARGETS_REQUIRED,
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          "PRODUCTION_AI_PLANTING_TARGETS_REQUIRED",
        resolution_hint:
          "Set planting material, planned planting quantity + unit, and estimated harvest quantity + unit before generating the farm draft.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
        details:
          buildPlantingTargetsValidationDetails(
            plantingTargets,
          ),
      });
    }
    // PHASE-GATE-LAYER
    // WHY: Draft-level phase-gate sanitization can target persisted plan phases only when an explicit plan id is supplied.
    const draftPlanId =
      normalizeStaffIdInput(
        req.body?.planId,
      );
    // PHASE-GATE-LAYER
    // WHY: Draft sanitization and finite-phase unit caps need a deterministic workload unit fallback in this handler scope.
    const workloadTotalUnits =
      parseWorkloadContextTotalUnits(
        req.body?.workloadContext,
      );
    const focusedRoles =
      normalizeStringArrayInput(
        Array.isArray(req.body?.focusedRoles) ?
          req.body.focusedRoles
        : req.body?.workloadContext
            ?.focusedRoles,
        { lowerCase: true },
      );
    const focusedStaffProfileIds =
      normalizeStringArrayInput(
        Array.isArray(
          req.body?.focusedStaffProfileIds,
        ) ?
          req.body.focusedStaffProfileIds
        : req.body?.workloadContext
            ?.focusedStaffProfileIds,
      );
    const focusedStaffByRole =
      normalizeStringListMapInput(
        req.body?.focusedStaffByRole ||
          req.body?.workloadContext
            ?.focusedStaffByRole,
        { lowerCaseKeys: true },
      );
    const focusedRoleTaskHints =
      normalizeStringListMapInput(
        req.body?.focusedRoleTaskHints ||
          req.body?.workloadContext
            ?.focusedRoleTaskHints,
        {
          lowerCaseKeys: true,
          lowerCaseValues: true,
        },
      );

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
    if (
      hasStartDateInput &&
      !startDate
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DATES_REQUIRED,
        classification: "INVALID_INPUT",
        error_code:
          "PRODUCTION_AI_START_DATE_INVALID",
        resolution_hint:
          "Start date should be YYYY-MM-DD when provided.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
      });
    }
    if (hasEndDateInput && !endDate) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DATES_REQUIRED,
        classification: "INVALID_INPUT",
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
        classification: "INVALID_INPUT",
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
    const startDateValue =
      startDate ?
        startDate
          .toISOString()
          .slice(0, 10)
      : null;
    const endDateValue =
      endDate ?
        endDate
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

    const productCatalog =
      await Product.find({
        businessId,
        deletedAt: null,
      })
        .select({
          _id: 1,
          name: 1,
        })
        .limit(80)
        .lean();
    let resolvedProductId = productId;
    let product = null;
    if (
      !resolvedProductId &&
      domainContext === "farm" &&
      productSearchNameRaw
    ) {
      product =
        await resolveAssistantPlannerProduct(
          {
            businessId,
            actor,
            productSearchName:
              productSearchNameRaw,
            productCatalog,
          },
        );
      resolvedProductId =
        product?._id?.toString?.() || "";
    }
    if (!resolvedProductId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PRODUCT_REQUIRED,
        classification:
          "MISSING_REQUIRED_FIELD",
        error_code:
          "PRODUCTION_AI_PRODUCT_REQUIRED",
        resolution_hint:
          domainContext === "farm" ?
            "Search the seeded crop database and select one crop before generating an AI draft."
          : "Select a product before generating an AI draft.",
        retry_skipped: true,
        retry_reason:
          validationRetryReason,
      });
    }
    product =
      product ||
      await businessProductService.getProductById(
        {
          businessId,
          id: resolvedProductId,
        },
      );
    if (!product) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PRODUCT_NOT_FOUND,
      });
    }

    if (
      sourceDocumentContext?.text &&
      refineTarget?.mode ===
        "document_import"
    ) {
      const importedDraftResponse =
        buildProductionDraftImportResponse(
          {
            sourceDocumentContext,
            estateAssetId,
            productId:
              resolvedProductId,
            productName:
              product?.name || "",
            domainContext,
            plantingTargets,
            titleFallback:
              `${product?.name || "Production"} Plan`,
          },
        );
      if (importedDraftResponse) {
        debug(
          "BUSINESS CONTROLLER: generateProductionPlanDraft - direct source import success",
          {
            actorId: actor._id,
            businessId:
              businessId.toString(),
            productId:
              resolvedProductId,
            phaseCount:
              importedDraftResponse
                ?.draft?.phases
                ?.length || 0,
            taskCount:
              importedDraftResponse
                ?.summary?.totalTasks || 0,
            sourceFileName:
              sourceDocumentContext.fileName ||
              "",
          },
        );
        return res.status(200).json(
          importedDraftResponse,
        );
      }
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
      await resolveEffectiveSchedulePolicy(
        {
          businessId,
          estateAssetId,
        },
      );
    const capacitySummary =
      await buildStaffCapacitySummary({
        businessId,
        estateAssetId,
      });
    const shouldUseDensityAwareDraftPipeline =
      Boolean(sourceDocumentContext?.text) ||
      [
        "draft_refine",
        "document_import",
      ].includes(
        (
          refineTarget?.mode || ""
        )
          .toString()
          .trim()
          .toLowerCase(),
      );
    const shouldUsePlannerV2 =
      PRODUCTION_FEATURE_FLAGS.enableAiPlannerV2 &&
      domainContext === "farm" &&
      !shouldUseDensityAwareDraftPipeline;
    const workloadContextInput =
      (
        req.body?.workloadContext &&
        typeof req.body
          .workloadContext === "object"
      ) ?
        req.body.workloadContext
      : {};
    const plannerWorkloadContext = {
      ...workloadContextInput,
      focusedRoles,
      focusedStaffProfileIds,
      focusedStaffByRole,
      focusedRoleTaskHints,
      plantingTargets,
    };
    const plantingTargetsPrompt =
      buildPlantingTargetsPrompt(
        plantingTargets,
      );
    const promptWithPlantingTargets = [
      prompt,
      plantingTargetsPrompt,
    ]
      .filter(Boolean)
      .join("\n\n");

    // WHY: V2 still needs the same lifecycle boundary logging even though AI no longer generates dated tasks directly.
    if (shouldUsePlannerV2) {
      logProductionLifecycleBoundary({
        operation: "draft_generation",
        stage: "start",
        intent:
          "generate production plan draft from contextual inputs",
        actorId: actor._id,
        businessId,
        context: {
          route:
            "/business/production/plans/ai-draft",
          source:
            "ai_draft_endpoint_v2",
          estateAssetId,
          productId:
            resolvedProductId,
          hasPrompt: Boolean(prompt),
          hasPlantingTargets:
            hasCompletePlantingTargets(
              plantingTargets,
            ),
          hasStartDate: Boolean(
            startDateValue,
          ),
          hasEndDate: Boolean(
            endDateValue,
          ),
        },
      });
    }

    // WHY: Planner V2 is farm-first and returns backend-owned schedule rows without legacy fallback repair.
    if (shouldUsePlannerV2) {
      const plannerV2Response =
        await generateProductionPlanDraftV2(
          {
            businessId,
            estateAssetId,
            product,
            domainContext,
            cropSubtype,
            startDate,
            endDate,
            assistantPrompt:
              promptWithPlantingTargets,
            useReasoning,
            capacitySummary,
            schedulePolicy:
              effectiveSchedulePolicy,
            workloadContext:
              plannerWorkloadContext,
            context: {
              route: req.originalUrl,
              requestId: req.id,
              userRole: actor.role,
              businessId,
              source: "ai_draft_endpoint_v2",
              // WHY: External lifecycle providers need estate location context to select country calendars accurately.
              estateCountry:
                estateAsset?.estate
                  ?.propertyAddress
                  ?.country || "",
              estateState:
                estateAsset?.estate
                  ?.propertyAddress
                  ?.state || "",
              country:
                req.headers?.[
                  COUNTRY_HEADER_KEY
                ] || DEFAULT_COUNTRY,
            },
          },
        );

      debug(
        "BUSINESS CONTROLLER: generateProductionPlanDraft - planner v2 success",
        {
          actorId: actor._id,
          businessId:
            businessId.toString(),
          productId:
            product?._id?.toString() ||
            "",
          phaseCount:
            plannerV2Response?.phases
              ?.length || 0,
          scheduledTaskCount:
            plannerV2Response?.tasks
              ?.length || 0,
          retryCount:
            plannerV2Response
              ?.plannerMeta
              ?.retryCount ??
            plannerV2Response?.draft
              ?.plannerMeta
              ?.retryCount ??
            0,
        },
      );

      logProductionLifecycleBoundary({
        operation: "draft_generation",
        stage: "success",
        intent:
          "generate production plan draft from contextual inputs",
        actorId: actor._id,
        businessId,
        context: {
          route:
            "/business/production/plans/ai-draft",
          source:
            "ai_draft_endpoint_v2",
          status:
            plannerV2Response?.status ||
            "ai_draft_success",
          hasPlantingTargets:
            hasCompletePlantingTargets(
              plantingTargets,
            ),
          planningDays:
            plannerV2Response?.summary
              ?.days || 0,
          planningWeeks:
            plannerV2Response?.summary
              ?.weeks || 0,
          scheduledTaskCount:
            plannerV2Response?.tasks
              ?.length || 0,
        },
      });

      return res.status(200).json({
        ...plannerV2Response,
        plantingTargets,
        draft: {
          ...(
            plannerV2Response?.draft || {}
          ),
          plantingTargets,
        },
      });
    }
    const requestedPlanningSummary =
      startDate && endDate ?
        buildPlanningRangeSummary({
          startDate,
          endDate,
          productId:
            resolvedProductId,
          cropSubtype,
        })
      : null;
    const planningRangePrompt =
      startDateValue && endDateValue ?
        `Planning range: ${requestedPlanningSummary?.startDate} to ${requestedPlanningSummary?.endDate} (${requestedPlanningSummary?.days} days, ${requestedPlanningSummary?.weeks} weeks, ~${requestedPlanningSummary?.monthApprox} months).`
      : (
        startDateValue && !endDateValue
      ) ?
        `Planning start date is fixed at ${startDateValue}. Infer endDate/proposedEndDate and schedule tasks across the full resulting range.`
      : (
        !startDateValue && endDateValue
      ) ?
        `Planning end date is fixed at ${endDateValue}. Infer startDate/proposedStartDate and schedule tasks across the full resulting range.`
      : "Infer both startDate and endDate from crop lifecycle + brief, then schedule tasks across the full inferred range.";
    const workloadUnitsPrompt =
      workloadTotalUnits > 0 ?
        `Workload unit budget: ${workloadTotalUnits} plot units.`
      : "Infer workload unit budget from context if not supplied.";
    const schedulerPrompt = [
      "For finite phases, schedule only the true execution duration needed to finish requiredUnits; do not pad timeline with repeated tasks to fill empty months.",
      "Monitoring phases may recur, but they must remain lifecycle-neutral and must not extend finite phase completion windows.",
      "For finite farmer execution, use minimum throughput baseline of 0.5 plot per farmer per day when estimating duration.",
      planningRangePrompt,
      workloadUnitsPrompt,
      "Each phase must include explicit phaseType ('finite' or 'monitoring'), requiredUnits, minRatePerFarmerHour, targetRatePerFarmerHour, plannedHoursPerDay, and biologicalMinDays.",
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
    const sourceDocumentPrompt =
      buildAiDraftSourceDocumentPrompt(
        sourceDocumentContext,
      );
    const assistantPrompt = [
      promptWithPlantingTargets,
      schedulerPrompt,
      sourceDocumentPrompt,
    ]
      .filter(Boolean)
      .join("\n\n");

    // WHY: Draft endpoint logs a deterministic boundary before the AI provider call.
    logProductionLifecycleBoundary({
      operation: "draft_generation",
      stage: "start",
      intent:
        "generate production plan draft from contextual inputs",
      actorId: actor._id,
      businessId,
      context: {
        route:
          "/business/production/plans/ai-draft",
        source: "ai_draft_endpoint",
        estateAssetId,
        productId:
          resolvedProductId,
        hasPrompt: Boolean(
          assistantPrompt,
        ),
        hasSourceDocument: Boolean(
          sourceDocumentContext?.text,
        ),
        sourceDocumentTaskLineEstimate:
          sourceDocumentContext?.taskLineEstimate ||
          0,
        hasStartDate: Boolean(
          startDateValue,
        ),
        hasEndDate: Boolean(
          endDateValue,
        ),
      },
    });

    const aiResult =
      await generateProductionPlanDraft(
        {
          productName:
            product?.name || "",
          estateName: estateAsset?.name,
          domainContext,
          estateAssetId,
          productId:
            resolvedProductId,
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
            hasSourceDocument: Boolean(
              sourceDocumentContext?.text,
            ),
            sourceDocumentTaskLineEstimate:
              sourceDocumentContext?.taskLineEstimate ||
              0,
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
      isPartialDraft ?
        aiResult?.message ||
        PRODUCTION_COPY.PLAN_DRAFT_OK
      : PRODUCTION_COPY.PLAN_DRAFT_OK;
    const normalizedWarnings = [
      ...(aiResult?.warnings || []),
    ];
    const aiDraftPayload =
      (
        aiResult?.draft &&
        typeof aiResult.draft ===
          "object"
      ) ?
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
    let resolvedDraftStartDate =
      parseDateInput(
        resolvedStartDateInput,
      );
    let resolvedDraftEndDate =
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
    if (
      !hasStartDateInput &&
      !hasEndDateInput
    ) {
      const todayUtc = new Date(
        Date.UTC(
          new Date().getUTCFullYear(),
          new Date().getUTCMonth(),
          new Date().getUTCDate(),
          0,
          0,
          0,
          0,
        ),
      );
      const staleThreshold = new Date(
        todayUtc.getTime() - MS_PER_DAY,
      );
      if (
        resolvedDraftEndDate.getTime() <=
        staleThreshold.getTime()
      ) {
        const stalePlanningSummary =
          buildPlanningRangeSummary({
            startDate:
              resolvedDraftStartDate,
            endDate:
              resolvedDraftEndDate,
            productId:
              resolvedProductId,
            cropSubtype,
          });
        const realignedDays = Math.max(
          28,
          Math.min(
            180,
            stalePlanningSummary.days,
          ),
        );
        resolvedDraftStartDate =
          todayUtc;
        resolvedDraftEndDate = new Date(
          todayUtc.getTime() +
            (realignedDays - 1) *
              MS_PER_DAY,
        );
        normalizedWarnings.push({
          code: "DRAFT_RANGE_REALIGNED_TO_CURRENT_WINDOW",
          message: `AI returned a stale historical range (${resolvedStartDateInput} to ${resolvedEndDateInput}). Dates were realigned to the current planning window.`,
        });
        debug(
          "BUSINESS CONTROLLER: generateProductionPlanDraft - stale range realigned",
          {
            originalStartDate:
              resolvedStartDateInput,
            originalEndDate:
              resolvedEndDateInput,
            realignedStartDate:
              resolvedDraftStartDate
                .toISOString()
                .slice(0, 10),
            realignedEndDate:
              resolvedDraftEndDate
                .toISOString()
                .slice(0, 10),
            realignedDays,
            reason:
              "ai_returned_historical_dates_without_user_supplied_range",
          },
        );
      }
    }
    let planningSummary =
      buildPlanningRangeSummary({
        startDate:
          resolvedDraftStartDate,
        endDate: resolvedDraftEndDate,
        productId:
          resolvedProductId,
        cropSubtype,
      });
    const resolvedStartDateValue =
      resolvedDraftStartDate
        .toISOString()
        .slice(0, 10);
    let resolvedEndDateValue =
      resolvedDraftEndDate
        .toISOString()
        .slice(0, 10);
    const draftPhases =
      (
        Array.isArray(
          aiDraftPayload?.phases,
        )
      ) ?
        aiDraftPayload.phases
      : [];
    const normalizedDraftPhasesBase =
      draftPhases
        .map((phase, phaseIndex) => {
          const phaseTasks =
            (
              Array.isArray(
                phase?.tasks,
              )
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
              (
                Number.isFinite(
                  Number(phase?.order),
                )
              ) ?
                Math.max(
                  1,
                  Math.floor(
                    Number(phase.order),
                  ),
                )
              : phaseIndex + 1,
            estimatedDays:
              (
                Number.isFinite(
                  Number(
                    phase?.estimatedDays,
                  ),
                )
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
            // PHASE-GATE-LAYER
            // WHY: Phase type is explicit lifecycle metadata (finite vs monitoring) and must not rely on keyword inference.
            phaseType:
              normalizeProductionPhaseTypeInput(
                phase?.phaseType,
              ),
            // PHASE-GATE-LAYER
            // WHY: Finite phase unit budget defaults to explicit workload units when phase-level value is missing.
            requiredUnits:
              normalizePhaseRequiredUnitsInput(
                phase?.requiredUnits,
                {
                  fallback:
                    (
                      normalizeProductionPhaseTypeInput(
                        phase?.phaseType,
                      ) ===
                      PRODUCTION_PHASE_TYPE_FINITE
                    ) ?
                      workloadTotalUnits
                    : 0,
                },
              ),
            minRatePerFarmerHour:
              normalizePhaseRatePerFarmerHourInput(
                phase?.minRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
                },
              ),
            targetRatePerFarmerHour:
              Math.max(
                normalizePhaseRatePerFarmerHourInput(
                  phase?.minRatePerFarmerHour,
                  {
                    fallback:
                      DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
                  },
                ),
                normalizePhaseRatePerFarmerHourInput(
                  phase?.targetRatePerFarmerHour,
                  {
                    fallback:
                      DEFAULT_PHASE_TARGET_RATE_PER_FARMER_HOUR,
                  },
                ),
              ),
            plannedHoursPerDay:
              normalizePhasePlannedHoursPerDayInput(
                phase?.plannedHoursPerDay,
                {
                  fallback:
                    DEFAULT_PHASE_PLANNED_HOURS_PER_DAY,
                },
              ),
            biologicalMinDays:
              normalizePhaseBiologicalMinDaysInput(
                phase?.biologicalMinDays,
                {
                  fallback:
                    DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS,
                },
              ),
            tasks: phaseTasks.map(
              (task) =>
                normalizeDraftTaskShape(
                  task,
                ),
            ),
          };
        })
        .sort(
          (left, right) =>
            Number(left.order || 0) -
            Number(right.order || 0),
        );
    const workloadThroughputPerFarmerPerDay =
      Math.max(
        FINITE_PHASE_MIN_PLOTS_PER_FARMER_PER_DAY,
        Number(
          req.body?.workloadContext
            ?.minimumPlotsPerFarmerPerDay ??
            FINITE_PHASE_MIN_PLOTS_PER_FARMER_PER_DAY,
        ) ||
          FINITE_PHASE_MIN_PLOTS_PER_FARMER_PER_DAY,
      );
    // PHASE-GATE-LAYER
    // WHY: Finite phases should finish when required units are done; this prevents month-padding loops in draft timelines.
    const normalizedDraftPhases =
      normalizedDraftPhasesBase.map(
        (phase) => {
          const recalculatedEstimatedDays =
            resolveFinitePhaseEstimatedDaysFromWorkload(
              {
                phase,
                capacitySummary,
                minimumPlotsPerFarmerPerDay:
                  workloadThroughputPerFarmerPerDay,
              },
            );
          if (
            normalizeProductionPhaseTypeInput(
              phase?.phaseType,
            ) !==
              PRODUCTION_PHASE_TYPE_FINITE ||
            recalculatedEstimatedDays ===
              phase.estimatedDays
          ) {
            return phase;
          }
          normalizedWarnings.push({
            code: FINITE_PHASE_DURATION_WARNING_CODE,
            phaseOrder: Number(
              phase.order || 1,
            ),
            phaseName: phase.name || "",
            requiredUnits: Number(
              phase.requiredUnits || 0,
            ),
            previousEstimatedDays:
              Number(
                phase.estimatedDays ||
                  1,
              ),
            recalculatedEstimatedDays,
            message:
              FINITE_PHASE_DURATION_WARNING_MESSAGE,
          });
          return {
            ...phase,
            estimatedDays:
              recalculatedEstimatedDays,
          };
        },
      );
    debug(
      "BUSINESS CONTROLLER: generateProductionPlanDraft - stage1 throughput normalized",
      {
        phaseCount:
          normalizedDraftPhases.length,
        throughputPreview:
          normalizedDraftPhases
            .slice(0, 6)
            .map((phase) => ({
              order: Number(
                phase?.order || 0,
              ),
              phaseType:
                normalizeProductionPhaseTypeInput(
                  phase?.phaseType,
                ),
              requiredUnits:
                normalizePhaseRequiredUnitsInput(
                  phase?.requiredUnits,
                ),
              minRatePerFarmerHour:
                normalizePhaseRatePerFarmerHourInput(
                  phase?.minRatePerFarmerHour,
                ),
              plannedHoursPerDay:
                normalizePhasePlannedHoursPerDayInput(
                  phase?.plannedHoursPerDay,
                ),
              biologicalMinDays:
                normalizePhaseBiologicalMinDaysInput(
                  phase?.biologicalMinDays,
                ),
              executionDays: Math.max(
                1,
                Math.floor(
                  Number(
                    phase?.estimatedDays ||
                      1,
                  ),
                ),
              ),
            })),
      },
    );
    const totalRequestedPhaseDays =
      normalizedDraftPhases.reduce(
        (sum, phase) =>
          sum +
          Math.max(
            Math.max(
              1,
              Math.floor(
                Number(
                  phase?.estimatedDays ||
                    1,
                ),
              ),
            ),
            normalizePhaseBiologicalMinDaysInput(
              phase?.biologicalMinDays,
            ),
          ),
        0,
      );
    const canExtendDraftRangeForFiniteExecution =
      !hasEndDateInput;
    if (
      canExtendDraftRangeForFiniteExecution &&
      totalRequestedPhaseDays >
        planningSummary.days
    ) {
      const previousPlanningDays =
        Number(
          planningSummary.days || 0,
        );
      // PHASE-GATE-LAYER
      // WHY: If user did not lock endDate, finite execution duration must extend plan range so tracks can finish instead of stopping with units left.
      const extendedDraftEndDate =
        new Date(
          resolvedDraftStartDate.getTime() +
            (totalRequestedPhaseDays -
              1) *
              MS_PER_DAY,
        );
      resolvedDraftEndDate =
        extendedDraftEndDate;
      resolvedEndDateValue =
        extendedDraftEndDate
          .toISOString()
          .slice(0, 10);
      planningSummary =
        buildPlanningRangeSummary({
          startDate:
            resolvedDraftStartDate,
          endDate: extendedDraftEndDate,
          productId:
            resolvedProductId,
          cropSubtype,
        });
      normalizedWarnings.push({
        code: "FINITE_RANGE_EXTENDED_TO_EXECUTION",
        requestedDays:
          totalRequestedPhaseDays,
        previousDays:
          previousPlanningDays,
        message:
          "Timeline end date was extended to cover required execution + biological windows and avoid unfinished work-unit tracks.",
      });
      debug(
        "BUSINESS CONTROLLER: generateProductionPlanDraft - finite range extended",
        {
          requestedPhaseDays:
            totalRequestedPhaseDays,
          extendedEndDate:
            resolvedEndDateValue,
          reason:
            "finite_execution_duration_exceeded_inferred_range",
        },
      );
    }
    const phaseGateSnapshotByOrder =
      await buildPhaseGateSnapshotForDraft(
        {
          planId: draftPlanId,
          businessId,
          draftPhases:
            normalizedDraftPhases,
          defaultFiniteRequiredUnits:
            workloadTotalUnits,
        },
      );
    const phaseGateWarningKeys =
      new Set();
    const phaseWindowWarningKeys =
      new Set();
    const scheduledPhases =
      buildPhaseSchedule({
        startDate:
          resolvedDraftStartDate,
        endDate: resolvedDraftEndDate,
        phases: normalizedDraftPhases,
      });
    const requestedTaskCount =
      resolveDraftRequestedTaskCount({
        planningDays:
          planningSummary.days,
        currentTaskCount:
          normalizedDraftPhases.reduce(
            (sum, phase) =>
              sum +
              (Array.isArray(
                phase?.tasks,
              ) ?
                phase.tasks.length
              : 0),
            0,
          ),
        refineTarget,
        sourceDocumentTaskLineEstimate:
          sourceDocumentContext?.taskLineEstimate ||
          0,
      });
    const phaseTaskTargetMap =
      buildDraftPhaseTaskTargetMap({
        scheduledPhases,
        refineTarget,
        requestedTaskCount,
      });
    const scheduledTaskRows = [];
    const draftPhasesWithTimes =
      scheduledPhases.map(
        (phase, phaseIndex) => {
          const draftPhase =
            normalizedDraftPhases[
              phaseIndex
            ] || {};
          const phaseOrder = Math.max(
            1,
            Math.floor(
              Number(
                phase?.order ||
                  draftPhase?.order ||
                  phaseIndex + 1,
              ),
            ),
          );
          const phaseGateSnapshot =
            phaseGateSnapshotByOrder.get(
              phaseOrder,
            ) || {};
          const phaseType =
            normalizeProductionPhaseTypeInput(
              phaseGateSnapshot.phaseType ??
                draftPhase.phaseType,
            );
          const requiredUnits =
            normalizePhaseRequiredUnitsInput(
              phaseGateSnapshot.requiredUnits ??
                draftPhase.requiredUnits,
              {
                fallback:
                  (
                    phaseType ===
                    PRODUCTION_PHASE_TYPE_FINITE
                  ) ?
                    workloadTotalUnits
                  : 0,
              },
            );
          const minRatePerFarmerHour =
            normalizePhaseRatePerFarmerHourInput(
              draftPhase.minRatePerFarmerHour ??
                phase.minRatePerFarmerHour,
              {
                fallback:
                  DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
              },
            );
          const targetRatePerFarmerHour =
            Math.max(
              minRatePerFarmerHour,
              normalizePhaseRatePerFarmerHourInput(
                draftPhase.targetRatePerFarmerHour ??
                  phase.targetRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_TARGET_RATE_PER_FARMER_HOUR,
                },
              ),
            );
          const plannedHoursPerDay =
            normalizePhasePlannedHoursPerDayInput(
              draftPhase.plannedHoursPerDay ??
                phase.plannedHoursPerDay,
              {
                fallback:
                  DEFAULT_PHASE_PLANNED_HOURS_PER_DAY,
              },
            );
          const biologicalMinDays =
            normalizePhaseBiologicalMinDaysInput(
              draftPhase.biologicalMinDays ??
                phase.biologicalMinDays,
              {
                fallback:
                  DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS,
              },
            );
          const phaseExecutionDays =
            Math.max(
              1,
              Math.floor(
                Number(
                  draftPhase.estimatedDays ??
                    phase.estimatedDays ??
                    1,
                ),
              ),
            );
          const phaseWindowDays =
            Math.max(
              1,
              Math.floor(
                (new Date(
                  phase.endDate,
                ).getTime() -
                  new Date(
                    phase.startDate,
                  ).getTime()) /
                  MS_PER_DAY,
              ) + 1,
            );
          if (
            biologicalMinDays >
              phaseExecutionDays &&
            phaseWindowDays >=
              biologicalMinDays
          ) {
            const warningKey = `${PHASE_BIOLOGICAL_WINDOW_WARNING_CODE}:${phaseOrder}`;
            if (
              !phaseWindowWarningKeys.has(
                warningKey,
              )
            ) {
              normalizedWarnings.push({
                code: PHASE_BIOLOGICAL_WINDOW_WARNING_CODE,
                phaseOrder,
                phaseName:
                  phase?.name ||
                  draftPhase?.name ||
                  "",
                biologicalMinDays,
                executionDays:
                  phaseExecutionDays,
                message:
                  PHASE_BIOLOGICAL_WINDOW_WARNING_MESSAGE,
              });
              phaseWindowWarningKeys.add(
                warningKey,
              );
            }
          }
          const completedUnitCount =
            Math.max(
              0,
              Number(
                phaseGateSnapshot.completedUnitCount ||
                  0,
              ),
            );
          let remainingUnits =
            (
              phaseType ===
              PRODUCTION_PHASE_TYPE_FINITE
            ) ?
              Math.max(
                0,
                Number(
                  phaseGateSnapshot.remainingUnits ??
                    requiredUnits -
                      completedUnitCount,
                ),
              )
            : Math.max(
                0,
                requiredUnits -
                  completedUnitCount,
              );
          const shouldLockFinitePhase =
            PRODUCTION_FEATURE_FLAGS.enablePhaseGate &&
            phaseType ===
              PRODUCTION_PHASE_TYPE_FINITE &&
            remainingUnits <= 0;
          let phaseTasks =
            draftPhase?.tasks || [];

          if (shouldLockFinitePhase) {
            const warningKey = `${PHASE_GATE_WARNING_CODE_LOCKED}:${phaseOrder}`;
            if (
              !phaseGateWarningKeys.has(
                warningKey,
              )
            ) {
              normalizedWarnings.push({
                code: PHASE_GATE_WARNING_CODE_LOCKED,
                phaseOrder,
                phaseName:
                  phase?.name ||
                  draftPhase?.name ||
                  "",
                requiredUnits,
                completedUnitCount,
                remainingUnits: 0,
                message:
                  PHASE_GATE_WARNING_LOCKED_MESSAGE,
              });
              phaseGateWarningKeys.add(
                warningKey,
              );
            }
            phaseTasks = [];
          } else if (
            PRODUCTION_FEATURE_FLAGS.enablePhaseGate &&
            phaseType ===
              PRODUCTION_PHASE_TYPE_FINITE &&
            remainingUnits >= 0
          ) {
            const cappedPhaseTasks = [];
            for (const task of phaseTasks) {
              if (remainingUnits <= 0) {
                const warningKey = `${PHASE_GATE_WARNING_CODE_CAPPED}:${phaseOrder}`;
                if (
                  !phaseGateWarningKeys.has(
                    warningKey,
                  )
                ) {
                  normalizedWarnings.push(
                    {
                      code: PHASE_GATE_WARNING_CODE_CAPPED,
                      phaseOrder,
                      phaseName:
                        phase?.name ||
                        draftPhase?.name ||
                        "",
                      requiredUnits,
                      completedUnitCount,
                      remainingUnits: 0,
                      message:
                        PHASE_GATE_WARNING_CAPPED_MESSAGE,
                    },
                  );
                  phaseGateWarningKeys.add(
                    warningKey,
                  );
                }
                break;
              }

              const requestedCoverageUnits =
                resolveDraftTaskCoverageUnits(
                  task,
                );
              if (
                requestedCoverageUnits <=
                0
              ) {
                cappedPhaseTasks.push(
                  task,
                );
                continue;
              }

              if (
                requestedCoverageUnits >
                remainingUnits
              ) {
                const warningKey = `${PHASE_GATE_WARNING_CODE_CAPPED}:${phaseOrder}`;
                if (
                  !phaseGateWarningKeys.has(
                    warningKey,
                  )
                ) {
                  normalizedWarnings.push(
                    {
                      code: PHASE_GATE_WARNING_CODE_CAPPED,
                      phaseOrder,
                      phaseName:
                        phase?.name ||
                        draftPhase?.name ||
                        "",
                      requiredUnits,
                      completedUnitCount,
                      remainingUnits,
                      message:
                        PHASE_GATE_WARNING_CAPPED_MESSAGE,
                    },
                  );
                  phaseGateWarningKeys.add(
                    warningKey,
                  );
                }

                const scaledWeight =
                  Math.max(
                    1,
                    Math.floor(
                      Number(
                        task?.weight ||
                          1,
                      ) *
                        (remainingUnits /
                          requestedCoverageUnits),
                    ),
                  );
                cappedPhaseTasks.push({
                  ...task,
                  weight: scaledWeight,
                  requestedCoverageUnits,
                  cappedCoverageUnits:
                    remainingUnits,
                });
                remainingUnits = 0;
                continue;
              }

              cappedPhaseTasks.push(
                task,
              );
              remainingUnits = Math.max(
                0,
                remainingUnits -
                  requestedCoverageUnits,
              );
            }
            phaseTasks =
              cappedPhaseTasks;
          }

          const phaseTaskTargetCount =
            phaseTaskTargetMap.get(
              normalizeDraftPhaseTargetName(
                phase?.name ||
                  draftPhase?.name ||
                  "",
              ),
            ) || phaseTasks.length;
          if (
            phaseTasks.length <
            phaseTaskTargetCount
          ) {
            const densityTopUpTasks =
              buildDraftPhaseTopUpTasks({
                phaseName:
                  phase?.name ||
                  draftPhase?.name ||
                  "",
                domainContext,
                existingTasks: phaseTasks,
                targetTaskCount:
                  phaseTaskTargetCount,
              });
            if (
              densityTopUpTasks.length > 0
            ) {
              phaseTasks = [
                ...phaseTasks,
                ...densityTopUpTasks,
              ];
              const warningKey = `DRAFT_TASK_DENSITY_TOP_UP:${phaseOrder}`;
              if (
                !phaseGateWarningKeys.has(
                  warningKey,
                )
              ) {
                normalizedWarnings.push({
                  code: "DRAFT_TASK_DENSITY_TOP_UP",
                  phaseOrder,
                  phaseName:
                    phase?.name ||
                    draftPhase?.name ||
                    "",
                  previousTaskCount:
                    phaseTasks.length -
                    densityTopUpTasks.length,
                  targetTaskCount:
                    phaseTaskTargetCount,
                  addedTaskCount:
                    densityTopUpTasks.length,
                  message:
                    "Draft phase was expanded automatically because AI returned too few tasks for its allocated days.",
                });
                phaseGateWarningKeys.add(
                  warningKey,
                );
              }
            }
          }

          const scheduledTasks =
            buildTaskSchedule({
              phaseStart:
                phase.taskStartDate ||
                phase.startDate,
              phaseEnd:
                phase.taskEndDate ||
                phase.endDate,
              tasks: phaseTasks,
              schedulePolicy:
                effectiveSchedulePolicy,
              allowParallelByRole: true,
            });
          const tasksForDraft =
            scheduledTasks.map(
              (task, taskIndex) => {
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
                  phaseName: phase.name,
                  phaseOrder:
                    phase.order,
                  phaseType,
                  requiredUnits,
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
                    normalizedTask.weight ||
                    1,
                });
                return normalizedTask;
              },
            );

          return {
            ...draftPhase,
            name: phase.name,
            order: phase.order,
            phaseType,
            requiredUnits,
            minRatePerFarmerHour,
            targetRatePerFarmerHour,
            plannedHoursPerDay,
            biologicalMinDays,
            tasks: tasksForDraft,
          };
        },
      );
    const latestScheduledPhaseEnd =
      scheduledPhases.length > 0 ?
        parseDateInput(
          scheduledPhases[
            scheduledPhases.length - 1
          ]?.endDate,
        )
      : null;
    if (
      latestScheduledPhaseEnd &&
      latestScheduledPhaseEnd.getTime() <
        resolvedDraftEndDate.getTime()
    ) {
      // WHY: Draft range should reflect true finite execution completion instead of showing padded idle months.
      resolvedEndDateValue =
        latestScheduledPhaseEnd
          .toISOString()
          .slice(0, 10);
      planningSummary =
        buildPlanningRangeSummary({
          startDate:
            resolvedDraftStartDate,
          endDate:
            latestScheduledPhaseEnd,
          productId:
            resolvedProductId,
          cropSubtype,
        });
      normalizedWarnings.push({
        code: "FINITE_RANGE_TRIMMED_TO_EXECUTION",
        message:
          "Timeline end date was trimmed to finite execution completion based on required units and workforce throughput.",
      });
    }
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
        code: "COMPRESSED_TIMELINE",
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
        code: "DOMAIN_CONTEXT_NORMALIZED",
        path: "domainContext",
        value: `${domainContextInput.raw} -> ${domainContext}`,
        message:
          "Domain context was normalized to a supported value for draft safety.",
      });
    }
    const normalizedDraft = {
      ...aiDraftPayload,
      domainContext:
        aiDraftPayload?.domainContext ||
        domainContext,
      estateAssetId,
      productId:
        resolvedProductId,
      startDate: resolvedStartDateValue,
      endDate: resolvedEndDateValue,
      plantingTargets,
      phases: draftPhasesWithTimes,
      summary: {
        ...(aiDraftPayload?.summary ||
          {}),
        totalTasks:
          scheduledTaskRows.length,
        totalEstimatedDays:
          planningSummary.days,
        riskNotes: Array.from(
          new Set([
            ...((
              Array.isArray(
                aiDraftPayload?.summary
                  ?.riskNotes,
              )
            ) ?
              aiDraftPayload.summary
                .riskNotes
            : []),
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
          aiResult?.warnings?.length ||
          0,
        provider:
          aiResult?.diagnostics
            ?.provider || "unknown",
        status:
          aiResult?.status ||
          "ai_draft_success",
        issueType:
          aiResult?.issueType || null,
        domainContextProvided:
          domainContextInput.provided,
        domainContextValid:
          domainContextInput.isValid,
        domainContext:
          normalizedDraft?.domainContext ||
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
        hasPrompt: Boolean(
          promptWithPlantingTargets,
        ),
        hasPlantingTargets:
          hasCompletePlantingTargets(
            plantingTargets,
          ),
      },
    );

    logProductionLifecycleBoundary({
      operation: "draft_generation",
      stage: "success",
      intent:
        "generate production plan draft from contextual inputs",
      actorId: actor._id,
      businessId,
      context: {
        route:
          "/business/production/plans/ai-draft",
        source: "ai_draft_endpoint",
        provider:
          aiResult?.diagnostics
            ?.provider || "unknown",
        status:
          aiResult?.status ||
          "ai_draft_success",
        hasPlantingTargets:
          hasCompletePlantingTargets(
            plantingTargets,
          ),
        planningDays:
          planningSummary.days,
        planningWeeks:
          planningSummary.weeks,
        scheduledTaskCount:
          scheduledTaskRows.length,
      },
    });

    return res.status(200).json({
      status:
        aiResult?.status ||
        "ai_draft_success",
      ...(isPartialDraft ?
        {
          issueType:
            aiResult?.issueType ||
            "INSUFFICIENT_CONTEXT",
        }
      : {}),
      message: responseMessage,
      summary: planningSummary,
      schedulePolicy:
        effectiveSchedulePolicy,
      capacity: capacitySummary,
      phases: draftPhasesWithTimes,
      tasks: scheduledTaskRows,
      plantingTargets,
      draft: {
        ...normalizedDraft,
      },
      warnings: normalizedWarnings,
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
      (
        err.details &&
        typeof err.details === "object"
      ) ?
        err.details
      : {
          missing: [],
          invalid: [],
          providerMessage:
            err.providerMessage || "",
        };
    const retryAllowed =
      err.retry_allowed === true;
    const retryReason =
      err.retry_reason ||
      (retryAllowed ?
        "provider_output_invalid"
      : "unexpected_error");
    const httpStatus =
      err.httpStatus === 422 ? 422
      : err.httpStatus === 400 ? 400
      : null;

    logProductionLifecycleBoundary({
      operation: "draft_generation",
      stage: "failure",
      intent:
        "generate production plan draft from contextual inputs",
      actorId: req.user?.sub,
      businessId:
        req.user?.businessId || null,
      context: {
        route:
          "/business/production/plans/ai-draft",
        source: "ai_draft_endpoint",
        classification,
        errorCode,
        retryAllowed,
        retryReason,
      },
    });

    debug(
      "BUSINESS CONTROLLER: generateProductionPlanDraft - error",
      {
        error: err.message,
        classification: classification,
        error_code: errorCode,
        resolution_hint: resolutionHint,
        retry_allowed: retryAllowed,
        retry_reason: retryReason,
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
        classification: classification,
        error_code: errorCode,
        resolution_hint: resolutionHint,
        details,
        retry_allowed: retryAllowed,
        retry_reason: retryReason,
      });
    }

    return res.status(400).json({
      error:
        err.message ||
        PRODUCTION_COPY.PLAN_DRAFT_FAILED,
      classification: classification,
      error_code: errorCode,
      resolution_hint: resolutionHint,
      details,
      retry_allowed: retryAllowed,
      retry_reason: retryReason,
    });
  }
}

async function persistProductionPlanScheduleRows(
  {
    planId,
    businessId,
    actor,
    workloadContext,
    scheduledPhases,
    tasksInputByPhase,
    effectiveSchedulePolicy,
    route,
    source,
    resetExistingSchedule = false,
    seedUnitSchedule = false,
  } = {},
) {
  if (resetExistingSchedule) {
    await Promise.all([
      ProductionTask.deleteMany({
        planId,
      }),
      ProductionPhase.deleteMany({
        planId,
      }),
      ProductionUnitTaskSchedule.deleteMany(
        {
          planId,
        },
      ),
      ProductionPhaseUnitCompletion.deleteMany(
        {
          planId,
        },
      ),
      PlanUnit.deleteMany({
        planId,
      }),
      LifecycleDeviationAlert.deleteMany(
        {
          planId,
          businessId,
        },
      ),
      ProductionUnitScheduleWarning.deleteMany(
        {
          planId,
          businessId,
        },
      ),
    ]);
  }

  const createdPhases =
    await ProductionPhase.insertMany(
      scheduledPhases.map(
        (phase) => ({
          planId,
          name: phase.name,
          order: phase.order,
          startDate: phase.startDate,
          endDate: phase.endDate,
          status:
            PRODUCTION_PHASE_STATUS_PENDING,
          phaseType:
            normalizeProductionPhaseTypeInput(
              phase?.phaseType,
            ),
          requiredUnits:
            normalizePhaseRequiredUnitsInput(
              phase?.requiredUnits,
            ),
          minRatePerFarmerHour:
            normalizePhaseRatePerFarmerHourInput(
              phase?.minRatePerFarmerHour,
              {
                fallback:
                  DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
              },
            ),
          targetRatePerFarmerHour:
            Math.max(
              normalizePhaseRatePerFarmerHourInput(
                phase?.minRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
                },
              ),
              normalizePhaseRatePerFarmerHourInput(
                phase?.targetRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_TARGET_RATE_PER_FARMER_HOUR,
                },
              ),
            ),
          plannedHoursPerDay:
            normalizePhasePlannedHoursPerDayInput(
              phase?.plannedHoursPerDay,
              {
                fallback:
                  DEFAULT_PHASE_PLANNED_HOURS_PER_DAY,
              },
            ),
          biologicalMinDays:
            normalizePhaseBiologicalMinDaysInput(
              phase?.biologicalMinDays,
              {
                fallback:
                  DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS,
              },
            ),
          kpiTarget: phase.kpiTarget,
        }),
      ),
    );
  const createdPlanUnits =
    await seedCanonicalPlanUnits({
      planId,
      workloadContext,
    });

  const tasksToCreate = [];
  createdPhases.forEach(
    (phase, index) => {
      const phaseTasks =
        tasksInputByPhase[index] || [];
      if (phaseTasks.length === 0) {
        return;
      }

      const scheduledTasks =
        buildTaskSchedule({
          phaseStart:
            phase.taskStartDate ||
            phase.startDate,
          phaseEnd:
            phase.taskEndDate ||
            phase.endDate,
          tasks: phaseTasks,
          schedulePolicy:
            effectiveSchedulePolicy,
          allowParallelByRole: true,
        });
      const scheduledTasksWithUnits =
        assignCanonicalPlanUnitsToTasks(
          {
            scheduledTasks,
            planUnits:
              createdPlanUnits,
          },
        );

      scheduledTasksWithUnits.forEach(
        (task) => {
        const assignedStaffProfileIds =
          resolveTaskAssignedStaffIds(task);
        const assignedUnitIds =
          resolveTaskAssignedUnitIds(task);
        const primaryAssignedStaffId =
          assignedStaffProfileIds[0] || null;
        const requiredHeadcount =
          Math.max(
            1,
            Math.floor(
              Number(
                task.requiredHeadcount || 1,
              ),
            ),
          );
        const isOwner =
          isBusinessOwnerEquivalentActor(actor);
        const approvalStatus =
          isOwner ?
            PRODUCTION_TASK_APPROVAL_APPROVED
          : PRODUCTION_TASK_APPROVAL_PENDING;
        const reviewedBy =
          isOwner ? actor._id : null;
        const reviewedAt =
          isOwner ? new Date() : null;

        tasksToCreate.push({
          planId,
          phaseId: phase._id,
          title:
            task.title
              ?.toString()
              .trim() || DEFAULT_TASK_TITLE,
          roleRequired:
            task.roleRequired,
          assignedStaffId:
            primaryAssignedStaffId,
          assignedStaffProfileIds,
          assignedUnitIds,
          requiredHeadcount,
          weight: task.weight || 1,
          manualSortOrder:
            normalizeTaskManualSortOrder(
              task.manualSortOrder,
              tasksToCreate.length,
            ),
          startDate: task.startDate,
          dueDate: task.dueDate,
          status:
            PRODUCTION_TASK_STATUS_PENDING,
          instructions:
            task.instructions
              ?.toString()
              .trim() || "",
          taskType:
            normalizePersistedProductionTaskType(
              task.taskType,
            ),
          sourceTemplateKey:
            task.sourceTemplateKey
              ?.toString()
              .trim() || "",
          recurrenceGroupKey:
            task.recurrenceGroupKey
              ?.toString()
              .trim() || "",
          occurrenceIndex: Math.max(
            0,
            Math.floor(
              Number(
                task.occurrenceIndex || 0,
              ),
            ),
          ),
          dependencies:
            Array.isArray(task.dependencies) ?
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

  logProductionLifecycleBoundary({
    operation: "schedule_commit",
    stage: "start",
    intent:
      "persist generated schedule rows for plan lifecycle",
    actorId: actor._id,
    businessId,
    context: {
      route,
      source,
      planId: planId.toString(),
      phaseCount:
        createdPhases.length,
      taskCount:
        tasksToCreate.length,
    },
  });

  const createdTasks =
    tasksToCreate.length > 0 ?
      await ProductionTask.insertMany(
        tasksToCreate,
      )
    : [];

  let unitScheduleSeedResult = null;
  if (
    seedUnitSchedule &&
    createdTasks.length > 0
  ) {
    unitScheduleSeedResult =
      await seedUnitTaskScheduleRows({
        planId,
        taskRows: createdTasks,
        operation: source,
      });
  }

  const sortedCreatedTasks = [
    ...createdTasks,
  ].sort((left, right) => {
    const leftStart =
      parseDateInput(left?.startDate) ||
      new Date(0);
    const rightStart =
      parseDateInput(right?.startDate) ||
      new Date(0);
    if (leftStart < rightStart) {
      return -1;
    }
    if (leftStart > rightStart) {
      return 1;
    }
    const leftDue =
      parseDateInput(left?.dueDate) ||
      leftStart;
    const rightDue =
      parseDateInput(right?.dueDate) ||
      rightStart;
    if (leftDue < rightDue) {
      return -1;
    }
    if (leftDue > rightDue) {
      return 1;
    }
    return (
      normalizeTaskManualSortOrder(
        left?.manualSortOrder,
        0,
      ) -
      normalizeTaskManualSortOrder(
        right?.manualSortOrder,
        0,
      )
    );
  });

  logProductionLifecycleBoundary({
    operation: "schedule_commit",
    stage: "success",
    intent:
      "persist generated schedule rows for plan lifecycle",
    actorId: actor._id,
    businessId,
    context: {
      route,
      source,
      planId: planId.toString(),
      phaseCount:
        createdPhases.length,
      planUnitCount:
        createdPlanUnits.length,
      taskCount:
        createdTasks.length,
      seededUnitScheduleRows:
        unitScheduleSeedResult?.rowCount ||
        0,
    },
  });

  return {
    createdPhases,
    createdPlanUnits,
    createdTasks:
      sortedCreatedTasks,
    unitScheduleSeedResult,
  };
}

/**
 * POST /business/production/plans
 * Owner + estate manager: create a production plan with phases/tasks.
 */
async function createProductionPlan(
  req,
  res,
) {
  const requestedSaveMode =
    (
      req.body?.saveMode || ""
    )
      .toString()
      .trim()
      .toLowerCase();
  const saveAsDraft =
    requestedSaveMode ===
    PRODUCTION_SAVE_MODE_DRAFT;
  debug(
    "BUSINESS CONTROLLER: createProductionPlan - entry",
    {
      actorId: req.user?.sub,
      saveMode:
        requestedSaveMode || "",
      hasProduct: Boolean(
        req.body?.productId,
      ),
      hasEstate: Boolean(
        req.body?.estateAssetId,
      ),
      hasDomainContext: Boolean(
        req.body?.domainContext,
      ),
      hasPlantingTargets: Boolean(
        req.body?.plantingTargets ||
          req.body?.workloadContext
            ?.plantingTargets,
      ),
    },
  );

  try {
    const { actor, businessId } =
      await getBusinessContext(
        req.user.sub,
      );

    // WHY: Stage-0 lifecycle trace starts when plan creation resolves business scope.
    logProductionLifecycleBoundary({
      operation:
        "production_plan_creation",
      stage: "start",
      intent:
        "create production plan with persisted schedule",
      actorId: actor._id,
      businessId,
      context: {
        route:
          "/business/production/plans",
        source: "create_plan_endpoint",
      },
    });

    const staffProfile =
      await getStaffProfileForActor({
        actor,
        businessId,
        allowMissing: true,
      });

    if (
      !(
        saveAsDraft ?
          canEditProductionPlanDraft({
            actorRole: actor.role,
            staffRole:
              staffProfile?.staffRole,
          })
        : canCreateProductionPlan({
            actorRole: actor.role,
            staffRole:
              staffProfile?.staffRole,
          })
      )
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
    const plantingTargets =
      normalizePlantingTargetsInput(
        req.body?.plantingTargets ||
          req.body?.workloadContext
            ?.plantingTargets,
      );
    const workloadContextInput =
      (
        req.body?.workloadContext &&
        typeof req.body
          .workloadContext === "object"
      ) ?
        req.body.workloadContext
      : null;
    const requestedWorkloadUnits =
      parseWorkloadContextTotalUnits(
        workloadContextInput,
      );

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
    if (
      domainContext === "farm" &&
      !hasCompletePlantingTargets(
        plantingTargets,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLANTING_TARGETS_REQUIRED,
        details:
          buildPlantingTargetsValidationDetails(
            plantingTargets,
          ),
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
      await resolveEffectiveSchedulePolicy(
        {
          businessId,
          estateAssetId,
        },
      );
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
          // PHASE-GATE-LAYER
          // WHY: Finite/monitoring phase type must be explicit for deterministic lifecycle gating.
          phaseType:
            normalizeProductionPhaseTypeInput(
              phase?.phaseType,
            ),
          // PHASE-GATE-LAYER
          // WHY: Required unit budget is normalized here so gate logic can lock finite phases safely.
          requiredUnits:
            normalizePhaseRequiredUnitsInput(
              phase?.requiredUnits,
              {
                fallback:
                  (
                    normalizeProductionPhaseTypeInput(
                      phase?.phaseType,
                    ) ===
                    PRODUCTION_PHASE_TYPE_FINITE
                  ) ?
                    requestedWorkloadUnits
                  : 0,
              },
            ),
          minRatePerFarmerHour:
            normalizePhaseRatePerFarmerHourInput(
              phase?.minRatePerFarmerHour,
              {
                fallback:
                  DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
              },
            ),
          targetRatePerFarmerHour:
            Math.max(
              normalizePhaseRatePerFarmerHourInput(
                phase?.minRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
                },
              ),
              normalizePhaseRatePerFarmerHourInput(
                phase?.targetRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_TARGET_RATE_PER_FARMER_HOUR,
                },
              ),
            ),
          plannedHoursPerDay:
            normalizePhasePlannedHoursPerDayInput(
              phase?.plannedHoursPerDay,
              {
                fallback:
                  DEFAULT_PHASE_PLANNED_HOURS_PER_DAY,
              },
            ),
          biologicalMinDays:
            normalizePhaseBiologicalMinDaysInput(
              phase?.biologicalMinDays,
              {
                fallback:
                  DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS,
              },
            ),
          estimatedDays:
            (
              Number.isFinite(
                Number(
                  phase?.estimatedDays,
                ),
              )
            ) ?
              Math.max(
                1,
                Math.floor(
                  Number(
                    phase?.estimatedDays,
                  ),
                ),
              )
            : 1,
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
    const workloadContext =
      buildNormalizedProductionWorkloadContext(
        {
          workloadContext:
            workloadContextInput,
          domainContext,
          defaultTotalWorkUnits:
            resolveScheduledPhaseTotalWorkUnits(
              normalizedPhases,
            ),
        },
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
    tasksInputByPhase.forEach(
      (phaseTasks) =>
        assertPinnedTaskDateRanges({
          tasks: phaseTasks,
          planStart: startDate,
          planEnd: endDate,
        }),
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
          phaseStart:
            phase.taskStartDate ||
            phase.startDate,
          phaseEnd:
            phase.taskEndDate ||
            phase.endDate,
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
        const requiredHeadcount =
          Math.max(
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
            const assignmentError =
              getProductionTaskAssignmentValidationError(
                {
                  taskRoleRequired:
                    task.roleRequired,
                  assignedProfile,
                  estateAssetId,
                  invalidRoleError:
                    PRODUCTION_COPY.STAFF_ROLE_MISMATCH,
                  scopeError:
                    PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
                },
              );
            if (assignmentError) {
              throw new Error(
                assignmentError,
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
                task?.roleRequired ||
                "",
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
        plantingTargets:
          hasCompletePlantingTargets(
            plantingTargets,
          ) ?
            plantingTargets
          : null,
        workloadContext,
        aiGenerated,
        domainContext,
      });

    // DEVIATION-GOVERNANCE
    // WHY: Stage 6 keeps one deterministic governance config per plan, optionally inheriting crop-template thresholds.
    let deviationGovernanceConfigSeed =
      null;
    if (
      PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance
    ) {
      try {
        deviationGovernanceConfigSeed =
          await loadOrCreateDeviationGovernanceConfigForPlan(
            {
              plan,
              actorId: actor._id,
              payloadConfig:
                req.body
                  ?.deviationGovernance,
              operation:
                "createProductionPlan",
            },
          );
      } catch (deviationConfigErr) {
        debug(
          "BUSINESS CONTROLLER: createProductionPlan - deviation governance config seed skipped",
          {
            actorId: actor._id,
            planId: plan._id,
            reason:
              deviationConfigErr.message,
            next: "Review deviation governance payload/config and retry with a valid threshold set",
          },
        );
      }
    }

    const {
      createdPhases,
      createdTasks,
      unitScheduleSeedResult,
    } =
      await persistProductionPlanScheduleRows(
        {
          planId: plan._id,
          businessId,
          actor,
          workloadContext,
          scheduledPhases,
          tasksInputByPhase,
          effectiveSchedulePolicy,
          route:
            "/business/production/plans",
          source: "create_plan_endpoint",
          seedUnitSchedule:
            !saveAsDraft,
        },
      );

    let lifecycleProduct = product;
    if (!saveAsDraft) {
      // WHY: Final plan creation should move product out of sellable stock mode; draft saves must not.
      lifecycleProduct =
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
              productionPlanId: plan._id,
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
    }

    // CONFIDENCE-SCORE
    // WHY: Schedule commit is the deterministic trigger boundary that initializes baseline/current confidence.
    let createdPlanConfidence = null;
    if (!saveAsDraft) {
      try {
        const confidenceRecompute =
          await triggerPlanConfidenceRecompute(
            {
              planId: plan._id,
              trigger:
                CONFIDENCE_RECOMPUTE_TRIGGERS.SCHEDULE_COMMIT,
              actorId: actor._id,
              operation:
                "createProductionPlan",
            },
          );
        createdPlanConfidence =
          confidenceRecompute?.snapshot ||
          null;
      } catch (confidenceErr) {
        // WHY: Confidence scoring must not block schedule commit persistence.
        debug(
          "BUSINESS CONTROLLER: createProductionPlan - confidence recompute skipped",
          {
            actorId: actor._id,
            planId: plan._id,
            reason: confidenceErr.message,
            next: "Retry confidence recompute through deterministic trigger flow",
          },
        );
      }
    }

    await appendProductionDraftSaveHistory({
      plan,
      actor,
      staffProfile,
      phases: createdPhases,
      tasks: createdTasks,
      action:
        saveAsDraft ?
          "draft_saved"
        : "created",
      note:
        saveAsDraft ?
          "Initial draft saved from the production studio."
        : "Initial production plan created.",
    });

    const responsePlan =
      createdPlanConfidence ?
        {
          ...plan.toObject(),
          confidence:
            createdPlanConfidence,
        }
      : plan;

    debug(
      "BUSINESS CONTROLLER: createProductionPlan - success",
      {
        actorId: actor._id,
        planId: plan._id,
        saveAsDraft,
        domainContext:
          plan.domainContext,
        productState:
          lifecycleProduct?.productionState ||
          null,
        hasPlantingTargets:
          hasCompletePlantingTargets(
            plantingTargets,
          ),
        phases: createdPhases.length,
        tasks: createdTasks.length,
        seededUnitScheduleRows:
          unitScheduleSeedResult?.rowCount ||
          0,
        deviationGovernanceConfigSeeded:
          deviationGovernanceConfigSeed?.config !=
          null,
      },
    );

    logProductionLifecycleBoundary({
      operation:
        "production_plan_creation",
      stage: "success",
      intent:
        "create production plan with persisted schedule",
      actorId: actor._id,
      businessId,
      context: {
        route:
          "/business/production/plans",
        source: "create_plan_endpoint",
        planId: plan._id.toString(),
        phaseCount:
          createdPhases.length,
        taskCount: createdTasks.length,
        productState:
          lifecycleProduct?.productionState ||
          null,
        deviationGovernanceConfigSeeded:
          deviationGovernanceConfigSeed?.config !=
          null,
      },
    });

    return res.status(201).json({
      message:
        saveAsDraft ?
          PRODUCTION_COPY.PLAN_DRAFT_SAVED
        : PRODUCTION_COPY.PLAN_CREATED,
      plan: responsePlan,
      phases: createdPhases,
      tasks: createdTasks,
      product: lifecycleProduct,
      draftAuditLog:
        sanitizeProductionDraftAuditEntries(
          plan.draftAuditLog,
        ),
      draftRevisions:
        sanitizeProductionDraftRevisionEntries(
          plan.draftRevisions,
        ),
      ...(createdPlanConfidence ?
        {
          confidence:
            createdPlanConfidence,
        }
      : {}),
    });
  } catch (err) {
    logProductionLifecycleBoundary({
      operation: "schedule_commit",
      stage: "failure",
      intent:
        "persist generated schedule rows for plan lifecycle",
      actorId: req.user?.sub,
      businessId:
        req.user?.businessId || null,
      context: {
        route:
          "/business/production/plans",
        source: "create_plan_endpoint",
        reason: err.message,
      },
    });
    logProductionLifecycleBoundary({
      operation:
        "production_plan_creation",
      stage: "failure",
      intent:
        "create production plan with persisted schedule",
      actorId: req.user?.sub,
      businessId:
        req.user?.businessId || null,
      context: {
        route:
          "/business/production/plans",
        source: "create_plan_endpoint",
        reason: err.message,
      },
    });
    debug(
      "BUSINESS CONTROLLER: createProductionPlan - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

async function updateProductionPlanDraft(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateProductionPlanDraft - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.id,
      hasProduct: Boolean(
        req.body?.productId,
      ),
      hasEstate: Boolean(
        req.body?.estateAssetId,
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
      !canEditProductionPlanDraft({
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
      });
    if (!plan) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.PLAN_NOT_FOUND,
      });
    }
    const estateAssetId =
      req.body?.estateAssetId
        ?.toString()
        .trim() ||
      plan.estateAssetId
        ?.toString()
        .trim() ||
      "";
    const productId =
      req.body?.productId
        ?.toString()
        .trim() ||
      plan.productId
        ?.toString()
        .trim() ||
      "";
    const title =
      req.body?.title
        ?.toString()
        .trim() ||
      plan.title
        ?.toString()
        .trim() ||
      "";
    const notes =
      req.body?.notes
        ?.toString()
        .trim() ||
      "";
    const aiGenerated = Boolean(
      req.body?.aiGenerated,
    );
    const domainContextInput =
      parseDomainContextInput(
        req.body?.domainContext ||
          plan.domainContext,
      );
    const domainContext =
      domainContextInput.value;
    const plantingTargets =
      normalizePlantingTargetsInput(
        req.body?.plantingTargets ||
          req.body?.workloadContext
            ?.plantingTargets ||
          plan.plantingTargets,
      );
    const requestedWorkloadUnits =
      parseWorkloadContextTotalUnits(
        (
          req.body?.workloadContext &&
          typeof req.body
            .workloadContext === "object"
        ) ?
          req.body.workloadContext
        : plan.workloadContext,
      );
    const startDate = parseDateInput(
      req.body?.startDate ||
        plan.startDate,
    );
    const endDate = parseDateInput(
      req.body?.endDate ||
        plan.endDate,
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
    if (
      domainContext === "farm" &&
      !hasCompletePlantingTargets(
        plantingTargets,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLANTING_TARGETS_REQUIRED,
        details:
          buildPlantingTargetsValidationDetails(
            plantingTargets,
          ),
      });
    }
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
      await resolveEffectiveSchedulePolicy(
        {
          businessId,
          estateAssetId,
        },
      );
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
          phaseType:
            normalizeProductionPhaseTypeInput(
              phase?.phaseType,
            ),
          requiredUnits:
            normalizePhaseRequiredUnitsInput(
              phase?.requiredUnits,
              {
                fallback:
                  (
                    normalizeProductionPhaseTypeInput(
                      phase?.phaseType,
                    ) ===
                    PRODUCTION_PHASE_TYPE_FINITE
                  ) ?
                    requestedWorkloadUnits
                  : 0,
              },
            ),
          minRatePerFarmerHour:
            normalizePhaseRatePerFarmerHourInput(
              phase?.minRatePerFarmerHour,
              {
                fallback:
                  DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
              },
            ),
          targetRatePerFarmerHour:
            Math.max(
              normalizePhaseRatePerFarmerHourInput(
                phase?.minRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_MIN_RATE_PER_FARMER_HOUR,
                },
              ),
              normalizePhaseRatePerFarmerHourInput(
                phase?.targetRatePerFarmerHour,
                {
                  fallback:
                    DEFAULT_PHASE_TARGET_RATE_PER_FARMER_HOUR,
                },
              ),
            ),
          plannedHoursPerDay:
            normalizePhasePlannedHoursPerDayInput(
              phase?.plannedHoursPerDay,
              {
                fallback:
                  DEFAULT_PHASE_PLANNED_HOURS_PER_DAY,
              },
            ),
          biologicalMinDays:
            normalizePhaseBiologicalMinDaysInput(
              phase?.biologicalMinDays,
              {
                fallback:
                  DEFAULT_PHASE_BIOLOGICAL_MIN_DAYS,
              },
            ),
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
                    phase?.estimatedDays,
                  ),
                ),
              )
            : 1,
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
            Array.isArray(phase?.tasks) ?
              phase.tasks
            : [],
        }),
      );
    const workloadContext =
      buildNormalizedProductionWorkloadContext(
        {
          workloadContext:
            (
              req.body?.workloadContext &&
              typeof req.body
                .workloadContext ===
                "object"
            ) ?
              req.body.workloadContext
            : null,
          fallbackWorkloadContext:
            plan.workloadContext,
          domainContext,
          defaultTotalWorkUnits:
            resolveScheduledPhaseTotalWorkUnits(
              normalizedPhases,
            ),
        },
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
    tasksInputByPhase.forEach(
      (phaseTasks) =>
        assertPinnedTaskDateRanges({
          tasks: phaseTasks,
          planStart: startDate,
          planEnd: endDate,
        }),
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

    scheduledPhases.forEach((phase) => {
      const scheduledTasks =
        buildTaskSchedule({
          phaseStart:
            phase.taskStartDate ||
            phase.startDate,
          phaseEnd:
            phase.taskEndDate ||
            phase.endDate,
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
            const assignmentError =
              getProductionTaskAssignmentValidationError(
                {
                  taskRoleRequired:
                    task.roleRequired,
                  assignedProfile,
                  estateAssetId,
                  invalidRoleError:
                    PRODUCTION_COPY.STAFF_ROLE_MISMATCH,
                  scopeError:
                    PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
                },
              );
            if (assignmentError) {
              throw new Error(
                assignmentError,
              );
            }
          },
        );
      });
    });

    const normalizedPlantingTargets =
      hasCompletePlantingTargets(
        plantingTargets,
      ) ?
        plantingTargets
      : null;
    const shouldForkDraftCopy =
      plan.status !==
      PRODUCTION_STATUS_DRAFT;

    if (shouldForkDraftCopy) {
      const draftCopy =
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
          plantingTargets:
            normalizedPlantingTargets,
          workloadContext,
          aiGenerated,
          domainContext,
        });

      const {
        createdPhases,
        createdTasks,
      } =
        await persistProductionPlanScheduleRows(
          {
            planId: draftCopy._id,
            businessId,
            actor,
            workloadContext,
            scheduledPhases,
            tasksInputByPhase,
            effectiveSchedulePolicy,
            route:
              "/business/production/plans/:id/draft",
            source:
              "fork_draft_copy_endpoint",
            seedUnitSchedule: false,
          },
        );

      await appendProductionDraftSaveHistory(
        {
          plan: draftCopy,
          actor,
          staffProfile,
          phases: createdPhases,
          tasks: createdTasks,
          action: "draft_saved",
          note:
            "Draft copy saved from an existing production plan.",
        },
      );

      return res.status(200).json({
        message:
          PRODUCTION_COPY.PLAN_DRAFT_SAVED,
        plan: draftCopy,
        phases: createdPhases,
        tasks: createdTasks,
        product,
        draftAuditLog:
          sanitizeProductionDraftAuditEntries(
            draftCopy.draftAuditLog,
          ),
        draftRevisions:
          sanitizeProductionDraftRevisionEntries(
            draftCopy.draftRevisions,
          ),
      });
    }

    plan.estateAssetId = estateAssetId;
    plan.productId = productId;
    plan.title = title;
    plan.notes = notes;
    plan.startDate = startDate;
    plan.endDate = endDate;
    plan.aiGenerated = aiGenerated;
    plan.domainContext = domainContext;
    plan.plantingTargets =
      normalizedPlantingTargets;
    plan.workloadContext =
      workloadContext;

    const {
      createdPhases,
      createdTasks,
    } =
      await persistProductionPlanScheduleRows(
        {
          planId: plan._id,
          businessId,
          actor,
          workloadContext,
          scheduledPhases,
          tasksInputByPhase,
          effectiveSchedulePolicy,
          route:
            "/business/production/plans/:id/draft",
          source:
            "update_draft_endpoint",
          resetExistingSchedule: true,
          seedUnitSchedule: false,
        },
      );

    await appendProductionDraftSaveHistory({
      plan,
      actor,
      staffProfile,
      phases: createdPhases,
      tasks: createdTasks,
      action: "draft_updated",
      note:
        "Production draft updated from the dedicated draft editor.",
    });

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_DRAFT_UPDATED,
      plan,
      phases: createdPhases,
      tasks: createdTasks,
      product,
      draftAuditLog:
        sanitizeProductionDraftAuditEntries(
          plan.draftAuditLog,
        ),
      draftRevisions:
        sanitizeProductionDraftRevisionEntries(
          plan.draftRevisions,
        ),
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateProductionPlanDraft - error",
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
        .select({
          draftAuditLog: 0,
          draftRevisions: 0,
        })
        .sort({ createdAt: -1 })
        .lean();

    const canViewConfidence =
      PRODUCTION_FEATURE_FLAGS.enableConfidenceScore &&
      canViewConfidenceScores({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      });
    const visiblePlans =
      await Promise.all(
        plans.map(async (plan) => {
          if (!canViewConfidence) {
            // CONFIDENCE-SCORE
            // WHY: Staff without manager-level scope must never receive confidence internals.
            return stripPlanConfidenceFields(
              plan,
            );
          }

          try {
            const confidence =
              await resolvePlanConfidenceSnapshot(
                {
                  plan,
                },
              );
            return {
              ...plan,
              confidence,
            };
          } catch (confidenceErr) {
            // WHY: Confidence enrichment failure should not block list reads.
            debug(
              "BUSINESS CONTROLLER: listProductionPlans - confidence enrichment skipped",
              {
                actorId: actor._id,
                planId:
                  plan?._id || null,
                reason:
                  confidenceErr.message,
                next: "Retry confidence retrieval from plan confidence endpoint",
              },
            );
            return plan;
          }
        }),
      );

    debug(
      "BUSINESS CONTROLLER: listProductionPlans - success",
      {
        actorId: actor._id,
        count: plans.length,
        confidenceVisible:
          canViewConfidence,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_LIST_OK,
      plans: visiblePlans,
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
 * PATCH /business/production/plans/:id/status
 * Owner + estate manager: update plan lifecycle status.
 */
async function updateProductionPlanStatus(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: updateProductionPlanStatus - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.id,
      status: req.body?.status,
    },
  );

  try {
    const planId = req.params?.id
      ?.toString()
      .trim();
    const nextStatus = (
      req.body?.status || ""
    )
      .toString()
      .trim()
      .toLowerCase();
    if (!planId) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }
    if (!nextStatus) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_STATUS_REQUIRED,
      });
    }
    if (
      !ProductionPlan.PRODUCTION_PLAN_STATUSES.includes(
        nextStatus,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_STATUS_INVALID,
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
      !canManageProductionPlanLifecycle(
        {
          actorRole: actor.role,
          staffRole:
            staffProfile?.staffRole,
        },
      )
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
      });
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
    if (
      !canTransitionProductionPlanStatus(
        plan.status,
        nextStatus,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_STATUS_TRANSITION_INVALID,
      });
    }

    if (
      (
        nextStatus ===
          PRODUCTION_STATUS_ARCHIVED ||
        nextStatus ===
          PRODUCTION_STATUS_DRAFT
      )
    ) {
      const linkedProduct =
        await businessProductService.getProductById(
          {
            businessId,
            id: plan.productId,
          },
        );
      if (
        linkedProduct?.preorderEnabled ===
          true &&
        linkedProduct
            ?.productionPlanId
            ?.toString?.() ===
          plan._id.toString()
      ) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.PLAN_ARCHIVE_PREORDER_ENABLED,
        });
      }
    }

    if (
      nextStatus ===
        PRODUCTION_STATUS_DRAFT &&
      plan.status !==
        PRODUCTION_STATUS_DRAFT
    ) {
      const [
        existingProgressEntry,
        existingOutputEntry,
      ] = await Promise.all([
        TaskProgress.exists({
          planId: plan._id,
        }),
        ProductionOutput.exists({
          planId: plan._id,
        }),
      ]);
      if (
        existingProgressEntry ||
        existingOutputEntry
      ) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.PLAN_RETURN_DRAFT_PROGRESS_LOCKED,
        });
      }
    }

    const previousStatus =
      plan.status;
    plan.status = nextStatus;
    await plan.save();
    await syncProductForPlanLifecycle({
      businessId,
      actor,
      plan,
      targetStatus: nextStatus,
    });

    debug(
      "BUSINESS CONTROLLER: updateProductionPlanStatus - success",
      {
        actorId: actor._id,
        planId: plan._id,
        from: previousStatus,
        to: nextStatus,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_STATUS_UPDATED,
      plan,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: updateProductionPlanStatus - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
}

/**
 * DELETE /business/production/plans/:id
 * Owner + estate manager: delete a draft/archived production plan and its dependent rows.
 */
async function deleteProductionPlan(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: deleteProductionPlan - entry",
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
      !canManageProductionPlanLifecycle(
        {
          actorRole: actor.role,
          staffRole:
            staffProfile?.staffRole,
        },
      )
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
      });
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
    if (
      plan.status !==
        PRODUCTION_STATUS_DRAFT &&
      plan.status !==
        PRODUCTION_STATUS_ARCHIVED
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_DELETE_DRAFT_ONLY,
      });
    }

    await detachProductFromDeletedDraft({
      businessId,
      actor,
      plan,
    });

    await Promise.all([
      ProductionPhase.deleteMany({
        planId: plan._id,
      }),
      ProductionTask.deleteMany({
        planId: plan._id,
      }),
      ProductionOutput.deleteMany({
        planId: plan._id,
      }),
      PlanUnit.deleteMany({
        planId: plan._id,
      }),
      ProductionPhaseUnitCompletion.deleteMany(
        {
          planId: plan._id,
        },
      ),
      LifecycleDeviationAlert.deleteMany(
        {
          planId: plan._id,
          businessId,
        },
      ),
      TaskProgress.deleteMany({
        planId: plan._id,
      }),
      ProductionDeviationGovernanceConfig.deleteMany(
        {
          planId: plan._id,
        },
      ),
      ProductionUnitTaskSchedule.deleteMany(
        {
          planId: plan._id,
        },
      ),
      ProductionUnitScheduleWarning.deleteMany(
        {
          planId: plan._id,
        },
      ),
      PreorderReservation.deleteMany({
        planId: plan._id,
      }),
    ]);
    await ProductionPlan.deleteOne({
      _id: plan._id,
    });

    debug(
      "BUSINESS CONTROLLER: deleteProductionPlan - success",
      {
        actorId: actor._id,
        planId: plan._id,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_DELETED,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: deleteProductionPlan - error",
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
    const toRaw = (req.query?.to || "")
      .toString()
      .trim();
    if (!fromRaw || !toRaw) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.CALENDAR_RANGE_REQUIRED,
      });
    }

    const fromDate =
      parseDateInput(fromRaw);
    const toDate =
      parseDateInput(toRaw);
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
          manualSortOrder: 1,
          _id: 1,
        })
        .populate("planId", "title")
        .populate(
          "phaseId",
          "name order",
        )
        .populate({
          path: "assignedStaffId",
          select: "staffRole userId",
          populate: {
            path: "userId",
            select: "name email",
          },
        })
        .lean();

    const items = tasks.map((task) => {
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
        status: task.status || "",
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
        dueDate: task.dueDate || null,
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
          staffProfile.staffRole || "",
      };
    });

    debug(
      "BUSINESS CONTROLLER: listProductionCalendar - success",
      {
        actorId: actor._id,
        businessId:
          businessId.toString(),
        from: fromDate.toISOString(),
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
 * GET /business/production/plans/:planId/units
 * Owner + managers: list canonical units for a production plan.
 */
async function listProductionPlanUnits(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listProductionPlanUnits - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.planId,
    },
  );

  try {
    const planId = (
      req.params?.planId || ""
    )
      .toString()
      .trim();
    if (
      !planId ||
      !mongoose.Types.ObjectId.isValid(
        planId,
      )
    ) {
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
          PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: planId,
        businessId,
      })
        .select({
          _id: 1,
          estateAssetId: 1,
          workloadContext: 1,
        })
        .lean();
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

    const {
      planUnits: units,
      repairedTaskCount:
        repairedAssignedUnitTaskCount,
    } =
      await ensureCanonicalPlanUnitsForPlan(
        {
          plan,
        },
      );

    debug(
      "BUSINESS CONTROLLER: listProductionPlanUnits - success",
      {
        actorId: actor._id,
        planId: plan._id,
        totalUnits: units.length,
        repairedAssignedUnitTaskCount,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_UNITS_LIST_OK,
      planId: plan._id,
      totalUnits: units.length,
      units,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listProductionPlanUnits - error",
      err.message,
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

function buildDeviationSummary({
  alerts,
  lockedUnits,
}) {
  const openAlerts = alerts.filter(
    (alert) => alert?.status === "open",
  ).length;
  const varianceAcceptedAlerts =
    alerts.filter(
      (alert) =>
        alert?.status ===
        "variance_accepted",
    ).length;
  const replannedAlerts = alerts.filter(
    (alert) =>
      alert?.status === "replanned",
  ).length;
  return {
    totalAlerts: alerts.length,
    openAlerts,
    varianceAcceptedAlerts,
    replannedAlerts,
    lockedUnits,
    updatedAt: new Date(),
  };
}

// DEVIATION-GOVERNANCE
// WHY: Plan-detail payload must expose stable, frontend-safe alert fields without leaking raw model internals.
function normalizeDeviationAlertForResponse({
  alert,
  planUnitById,
  taskTitleById,
}) {
  const alertId =
    normalizeStaffIdInput(alert?._id) ||
    "";
  const planId =
    normalizeStaffIdInput(
      alert?.planId,
    ) || "";
  const unitId =
    normalizeStaffIdInput(
      alert?.unitId,
    ) || "";
  const sourceTaskId =
    normalizeStaffIdInput(
      alert?.sourceTaskId,
    ) || "";
  const planUnit =
    planUnitById.get(unitId) || null;

  return {
    alertId,
    planId,
    unitId,
    unitIndex: Math.max(
      1,
      Number(planUnit?.unitIndex || 1),
    ),
    unitLabel: planUnit?.label || "",
    sourceTaskId,
    sourceTaskTitle:
      taskTitleById.get(sourceTaskId) ||
      "",
    cumulativeDeviationDays: Math.max(
      0,
      Number(
        alert?.cumulativeDeviationDays ||
          0,
      ),
    ),
    thresholdDays: Math.max(
      0,
      Number(alert?.thresholdDays || 0),
    ),
    status:
      alert?.status
        ?.toString()
        .trim() || "",
    message:
      alert?.message
        ?.toString()
        .trim() || "",
    triggeredAt:
      alert?.triggeredAt || null,
    resolvedAt:
      alert?.resolvedAt || null,
    resolutionNote:
      alert?.resolutionNote
        ?.toString()
        .trim() || "",
    unitLocked:
      planUnit?.deviationLocked ===
      true,
    unitLockedAt:
      planUnit?.deviationLockedAt ||
      null,
  };
}

/**
 * GET /business/production/plans/:planId/deviation-alerts
 * Owner + managers: list deviation governance alerts for a plan.
 */
async function listProductionPlanDeviationAlerts(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: listProductionPlanDeviationAlerts - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.planId,
    },
  );

  try {
    if (
      !PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DEVIATION_GOVERNANCE_DISABLED,
      });
    }
    const planId = (
      req.params?.planId || ""
    )
      .toString()
      .trim();
    if (
      !planId ||
      !mongoose.Types.ObjectId.isValid(
        planId,
      )
    ) {
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
      !canAssignProductionTasks({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.DEVIATION_GOVERNANCE_FORBIDDEN,
      });
    }

    const plan =
      await ProductionPlan.findOne({
        _id: planId,
        businessId,
      })
        .select({
          _id: 1,
          estateAssetId: 1,
        })
        .lean();
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
          PRODUCTION_COPY.DEVIATION_GOVERNANCE_FORBIDDEN,
      });
    }

    const [alerts, lockedUnits] =
      await Promise.all([
        LifecycleDeviationAlert.find({
          planId: plan._id,
          businessId,
        })
          .sort({ createdAt: -1 })
          .lean(),
        PlanUnit.countDocuments({
          planId: plan._id,
          deviationLocked: true,
        }),
      ]);
    const summary =
      buildDeviationSummary({
        alerts,
        lockedUnits,
      });

    return res.status(200).json({
      message:
        PRODUCTION_COPY.DEVIATION_ALERTS_LIST_OK,
      planId: plan._id,
      summary,
      alerts,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: listProductionPlanDeviationAlerts - error",
      err.message,
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/plans/:planId/deviation-alerts/:alertId/accept-variance
 * Owner + managers: accept variance and unlock plan unit.
 */
async function acceptProductionPlanDeviationVariance(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: acceptProductionPlanDeviationVariance - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.planId,
      alertId: req.params?.alertId,
    },
  );

  try {
    if (
      !PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DEVIATION_GOVERNANCE_DISABLED,
      });
    }
    const planId = (
      req.params?.planId || ""
    )
      .toString()
      .trim();
    const alertId = (
      req.params?.alertId || ""
    )
      .toString()
      .trim();
    if (
      !planId ||
      !mongoose.Types.ObjectId.isValid(
        planId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }
    if (
      !alertId ||
      !mongoose.Types.ObjectId.isValid(
        alertId,
      )
    ) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.DEVIATION_ALERT_NOT_FOUND,
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
          PRODUCTION_COPY.DEVIATION_GOVERNANCE_FORBIDDEN,
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

    const alert =
      await LifecycleDeviationAlert.findOne(
        {
          _id: alertId,
          planId: plan._id,
          businessId,
        },
      );
    if (!alert) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.DEVIATION_ALERT_NOT_FOUND,
      });
    }

    const planUnit =
      await PlanUnit.findOne({
        _id: alert.unitId,
        planId: plan._id,
      });
    if (!planUnit) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.DEVIATION_ALERT_NOT_FOUND,
      });
    }

    const actedAt = new Date();
    const note =
      req.body?.note
        ?.toString()
        .trim() || "";
    alert.status = "variance_accepted";
    alert.resolvedAt = actedAt;
    alert.resolvedBy = actor._id;
    alert.resolutionNote = note;
    alert.actionHistory =
      (
        Array.isArray(
          alert.actionHistory,
        )
      ) ?
        alert.actionHistory
      : [];
    alert.actionHistory.push({
      actionType: "accept_variance",
      actorId: actor._id,
      actedAt,
      note,
      metadata: null,
    });
    await alert.save();

    planUnit.deviationLocked = false;
    planUnit.deviationLockedAt = null;
    planUnit.deviationLockReason = "";
    planUnit.deviationLockedByAlertId =
      null;
    planUnit.varianceAcceptedAt =
      actedAt;
    planUnit.varianceAcceptedBy =
      actor._id;
    planUnit.varianceAcceptedAlertId =
      alert._id;
    await planUnit.save();

    // CONFIDENCE-SCORE
    // WHY: Variance acceptance changes lock risk state and must refresh current confidence.
    const confidenceRecompute =
      await triggerPlanConfidenceRecompute(
        {
          planId: plan._id,
          trigger:
            CONFIDENCE_RECOMPUTE_TRIGGERS.VARIANCE_ACCEPTED,
          actorId: actor._id,
          operation:
            "acceptProductionPlanDeviationVariance",
        },
      );

    const [alerts, lockedUnits] =
      await Promise.all([
        LifecycleDeviationAlert.find({
          planId: plan._id,
          businessId,
        })
          .sort({ createdAt: -1 })
          .lean(),
        PlanUnit.countDocuments({
          planId: plan._id,
          deviationLocked: true,
        }),
      ]);
    const summary =
      buildDeviationSummary({
        alerts,
        lockedUnits,
      });

    return res.status(200).json({
      message:
        PRODUCTION_COPY.DEVIATION_VARIANCE_ACCEPTED,
      planId: plan._id,
      summary,
      alert,
      ...((
        confidenceRecompute?.snapshot
      ) ?
        {
          confidence:
            confidenceRecompute.snapshot,
        }
      : {}),
      alerts,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: acceptProductionPlanDeviationVariance - error",
      err.message,
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * POST /business/production/plans/:planId/deviation-alerts/:alertId/replan-unit
 * Owner + managers: mark alert as replanned and unlock unit after manual adjustments.
 */
async function replanProductionPlanDeviationUnit(
  req,
  res,
) {
  debug(
    "BUSINESS CONTROLLER: replanProductionPlanDeviationUnit - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.planId,
      alertId: req.params?.alertId,
      adjustmentCount:
        (
          Array.isArray(
            req.body?.taskAdjustments,
          )
        ) ?
          req.body.taskAdjustments
            .length
        : 0,
    },
  );

  try {
    if (
      !PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DEVIATION_GOVERNANCE_DISABLED,
      });
    }
    const planId = (
      req.params?.planId || ""
    )
      .toString()
      .trim();
    const alertId = (
      req.params?.alertId || ""
    )
      .toString()
      .trim();
    if (
      !planId ||
      !mongoose.Types.ObjectId.isValid(
        planId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PLAN_ID_REQUIRED,
      });
    }
    if (
      !alertId ||
      !mongoose.Types.ObjectId.isValid(
        alertId,
      )
    ) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.DEVIATION_ALERT_NOT_FOUND,
      });
    }
    if (
      !Array.isArray(
        req.body?.taskAdjustments,
      ) ||
      req.body.taskAdjustments
        .length === 0
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DEVIATION_REPLAN_TASKS_REQUIRED,
      });
    }
    const parsedTaskAdjustments =
      req.body.taskAdjustments
        .map((adjustment, index) => {
          const taskId =
            normalizeStaffIdInput(
              adjustment?.taskId,
            );
          const startDate =
            parseDateInput(
              adjustment?.startDate,
            );
          const dueDate =
            parseDateInput(
              adjustment?.dueDate,
            );
          const isValidTaskId =
            mongoose.Types.ObjectId.isValid(
              taskId,
            );
          const hasValidDates =
            Boolean(startDate) &&
            Boolean(dueDate) &&
            dueDate > startDate;
          return {
            index,
            taskId,
            startDate,
            dueDate,
            isValidTaskId,
            hasValidDates,
          };
        })
        .filter(Boolean);
    const hasInvalidTaskAdjustments =
      parsedTaskAdjustments.some(
        (adjustment) =>
          adjustment?.isValidTaskId !==
            true ||
          adjustment?.hasValidDates !==
            true,
      );
    const adjustmentTaskIds =
      parsedTaskAdjustments.map(
        (adjustment) =>
          adjustment.taskId,
      );
    const hasDuplicateTaskIds =
      new Set(adjustmentTaskIds)
        .size !==
      adjustmentTaskIds.length;
    if (
      hasInvalidTaskAdjustments ||
      hasDuplicateTaskIds
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DEVIATION_REPLAN_TASKS_INVALID,
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
          PRODUCTION_COPY.DEVIATION_GOVERNANCE_FORBIDDEN,
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

    const alert =
      await LifecycleDeviationAlert.findOne(
        {
          _id: alertId,
          planId: plan._id,
          businessId,
        },
      );
    if (!alert) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.DEVIATION_ALERT_NOT_FOUND,
      });
    }

    const planUnit =
      await PlanUnit.findOne({
        _id: alert.unitId,
        planId: plan._id,
      });
    if (!planUnit) {
      return res.status(404).json({
        error:
          PRODUCTION_COPY.DEVIATION_ALERT_NOT_FOUND,
      });
    }

    // DEVIATION-GOVERNANCE
    // WHY: Manager re-plan must mutate current unit schedule rows while preserving immutable baselines.
    const scheduleRows =
      await ProductionUnitTaskSchedule.find(
        {
          planId: plan._id,
          unitId: planUnit._id,
          taskId: {
            $in: adjustmentTaskIds,
          },
        },
      )
        .select({
          _id: 1,
          taskId: 1,
          timingMode: 1,
          referencePhaseId: 1,
          referenceEvent: 1,
        })
        .lean();
    if (
      scheduleRows.length !==
      adjustmentTaskIds.length
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DEVIATION_REPLAN_TASKS_INVALID,
      });
    }
    const scheduleRowByTaskId = new Map(
      scheduleRows.map((row) => [
        normalizeStaffIdInput(
          row?.taskId,
        ),
        row,
      ]),
    );
    const relativeReferencePhaseIds =
      Array.from(
        new Set(
          scheduleRows
            .filter(
              (row) =>
                row?.timingMode ===
                  PRODUCTION_TASK_TIMING_MODE_RELATIVE &&
                mongoose.Types.ObjectId.isValid(
                  row?.referencePhaseId,
                ),
            )
            .map((row) =>
              normalizeStaffIdInput(
                row?.referencePhaseId,
              ),
            )
            .filter(Boolean),
        ),
      );
    const referencePhases =
      (
        relativeReferencePhaseIds.length >
        0
      ) ?
        await ProductionPhase.find({
          _id: {
            $in: relativeReferencePhaseIds,
          },
          planId: plan._id,
        })
          .select({
            _id: 1,
            startDate: 1,
            endDate: 1,
          })
          .lean()
      : [];
    const referencePhaseById = new Map(
      referencePhases.map((phase) => [
        normalizeStaffIdInput(
          phase?._id,
        ),
        phase,
      ]),
    );

    const replanWriteOps = [];
    for (const adjustment of parsedTaskAdjustments) {
      const scheduleRow =
        scheduleRowByTaskId.get(
          adjustment.taskId,
        );
      if (!scheduleRow) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.DEVIATION_REPLAN_TASKS_INVALID,
        });
      }

      const updateSet = {
        currentStartDate:
          adjustment.startDate,
        currentDueDate:
          adjustment.dueDate,
        lastShiftDays: 0,
        lastShiftReason:
          UNIT_MANUAL_REPLAN_SHIFT_REASON,
        lastShiftedByProgressId: null,
      };
      if (
        scheduleRow?.timingMode ===
        PRODUCTION_TASK_TIMING_MODE_RELATIVE
      ) {
        const referencePhase =
          referencePhaseById.get(
            normalizeStaffIdInput(
              scheduleRow?.referencePhaseId,
            ),
          ) || null;
        const referenceDate =
          resolveReferenceEventDate({
            phase: referencePhase,
            referenceEvent:
              scheduleRow?.referenceEvent,
          });
        if (!referenceDate) {
          return res.status(400).json({
            error:
              PRODUCTION_COPY.DEVIATION_REPLAN_TASKS_INVALID,
          });
        }
        updateSet.startOffsetDays =
          resolveOffsetDaysFromReferenceDate(
            {
              referenceDate,
              targetDate:
                adjustment.startDate,
            },
          );
        updateSet.dueOffsetDays =
          resolveOffsetDaysFromReferenceDate(
            {
              referenceDate,
              targetDate:
                adjustment.dueDate,
            },
          );
      }

      replanWriteOps.push({
        updateOne: {
          filter: {
            _id: scheduleRow._id,
            planId: plan._id,
            unitId: planUnit._id,
          },
          update: {
            $set: updateSet,
          },
        },
      });
    }
    if (replanWriteOps.length === 0) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.DEVIATION_REPLAN_TASKS_INVALID,
      });
    }
    await ProductionUnitTaskSchedule.bulkWrite(
      replanWriteOps,
      { ordered: false },
    );

    const actedAt = new Date();
    const note =
      req.body?.note
        ?.toString()
        .trim() || "";
    alert.status = "replanned";
    alert.resolvedAt = actedAt;
    alert.resolvedBy = actor._id;
    alert.resolutionNote = note;
    alert.actionHistory =
      (
        Array.isArray(
          alert.actionHistory,
        )
      ) ?
        alert.actionHistory
      : [];
    alert.actionHistory.push({
      actionType: "replan_unit",
      actorId: actor._id,
      actedAt,
      note,
      metadata: {
        adjustmentCount:
          parsedTaskAdjustments.length,
        adjustedTaskIds:
          parsedTaskAdjustments.map(
            (adjustment) =>
              adjustment.taskId,
          ),
      },
    });
    await alert.save();

    planUnit.deviationLocked = false;
    planUnit.deviationLockedAt = null;
    planUnit.deviationLockReason = "";
    planUnit.deviationLockedByAlertId =
      null;
    planUnit.varianceAcceptedAt = null;
    planUnit.varianceAcceptedBy = null;
    planUnit.varianceAcceptedAlertId =
      null;
    await planUnit.save();

    let confidenceRecompute = null;
    try {
      confidenceRecompute =
        await triggerPlanConfidenceRecompute(
          {
            planId: plan._id,
            trigger:
              CONFIDENCE_RECOMPUTE_TRIGGERS.PLAN_WINDOW_CHANGED,
            actorId: actor._id,
            operation:
              "replanProductionPlanDeviationUnit",
          },
        );
    } catch (confidenceErr) {
      debug(
        "BUSINESS CONTROLLER: replanProductionPlanDeviationUnit - confidence recompute skipped",
        {
          actorId: actor._id,
          planId: plan._id,
          alertId: alert._id,
          reason: confidenceErr.message,
          next: "Retry confidence recompute after manual re-plan adjustments are validated",
        },
      );
    }

    const [alerts, lockedUnits] =
      await Promise.all([
        LifecycleDeviationAlert.find({
          planId: plan._id,
          businessId,
        })
          .sort({ createdAt: -1 })
          .lean(),
        PlanUnit.countDocuments({
          planId: plan._id,
          deviationLocked: true,
        }),
      ]);
    const summary =
      buildDeviationSummary({
        alerts,
        lockedUnits,
      });

    return res.status(200).json({
      message:
        PRODUCTION_COPY.DEVIATION_REPLAN_APPLIED,
      planId: plan._id,
      summary,
      alert,
      appliedTaskAdjustments:
        parsedTaskAdjustments.map(
          (adjustment) => ({
            taskId: adjustment.taskId,
            startDate:
              adjustment.startDate,
            dueDate: adjustment.dueDate,
          }),
        ),
      ...((
        confidenceRecompute?.snapshot
      ) ?
        {
          confidence:
            confidenceRecompute.snapshot,
        }
      : {}),
      alerts,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: replanProductionPlanDeviationUnit - error",
      err.message,
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /business/production/plans/:planId/confidence
 * Owner + managers: fetch deterministic confidence snapshot for one plan.
 */
async function getProductionPlanConfidence(
  req,
  res,
) {
  // CONFIDENCE-SCORE
  debug(
    "BUSINESS CONTROLLER: getProductionPlanConfidence - entry",
    {
      actorId: req.user?.sub,
      planId: req.params?.planId,
    },
  );

  try {
    if (
      !PRODUCTION_FEATURE_FLAGS.enableConfidenceScore
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.CONFIDENCE_DISABLED,
      });
    }

    const planId = (
      req.params?.planId || ""
    )
      .toString()
      .trim();
    if (
      !planId ||
      !mongoose.Types.ObjectId.isValid(
        planId,
      )
    ) {
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
    if (
      !canViewConfidenceScores({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.CONFIDENCE_FORBIDDEN,
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
          PRODUCTION_COPY.CONFIDENCE_FORBIDDEN,
      });
    }

    const confidence =
      await resolvePlanConfidenceSnapshot(
        {
          plan,
        },
      );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.CONFIDENCE_PLAN_OK,
      planId: plan._id,
      confidence,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getProductionPlanConfidence - error",
      err.message,
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /business/production/confidence/portfolio
 * Owner + managers: fetch weighted confidence summary across active plans.
 */
async function getProductionPortfolioConfidence(
  req,
  res,
) {
  // CONFIDENCE-SCORE
  debug(
    "BUSINESS CONTROLLER: getProductionPortfolioConfidence - entry",
    {
      actorId: req.user?.sub,
      requestedEstateAssetId:
        req.query?.estateAssetId,
    },
  );

  try {
    if (
      !PRODUCTION_FEATURE_FLAGS.enableConfidenceScore
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.CONFIDENCE_DISABLED,
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
      !canViewConfidenceScores({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      })
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.CONFIDENCE_FORBIDDEN,
      });
    }

    const requestedEstateAssetId = (
      req.query?.estateAssetId || ""
    )
      .toString()
      .trim();
    if (
      requestedEstateAssetId &&
      !mongoose.Types.ObjectId.isValid(
        requestedEstateAssetId,
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
      requestedEstateAssetId &&
      actor.estateAssetId.toString() !==
        requestedEstateAssetId
    ) {
      return res.status(403).json({
        error:
          PRODUCTION_COPY.CONFIDENCE_FORBIDDEN,
      });
    }

    const scopedEstateAssetId =
      (
        actor.role === "staff" &&
        actor.estateAssetId
      ) ?
        actor.estateAssetId
      : requestedEstateAssetId || null;
    const summary =
      await buildPortfolioConfidenceSummary(
        {
          businessId,
          estateAssetId:
            scopedEstateAssetId,
        },
      );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.CONFIDENCE_PORTFOLIO_OK,
      summary,
      scope: {
        estateAssetId:
          scopedEstateAssetId || null,
        statuses:
          CONFIDENCE_ACTIVE_PLAN_STATUSES,
      },
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: getProductionPortfolioConfidence - error",
      err.message,
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

    const canViewPlanConfidence =
      PRODUCTION_FEATURE_FLAGS.enableConfidenceScore &&
      canViewConfidenceScores({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      });
    // CONFIDENCE-SCORE
    // WHY: Stage 7 requires non-manager staff to see only their own KPI rows, not team-level KPI summaries.
    const canViewTeamKpis =
      canAssignProductionTasks({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      });
    // DEVIATION-GOVERNANCE
    // WHY: Plan-level risk signals (unit divergence + deviation alerts) are manager-only.
    const canViewPlanRiskSignals =
      canViewTeamKpis;
    let planConfidence = null;
    if (canViewPlanConfidence) {
      try {
        planConfidence =
          await resolvePlanConfidenceSnapshot(
            {
              plan,
            },
          );
      } catch (confidenceErr) {
        // WHY: Confidence lookup should degrade gracefully so plan detail remains accessible.
        debug(
          "BUSINESS CONTROLLER: getProductionPlanDetail - confidence lookup skipped",
          {
            actorId: actor._id,
            planId: plan._id,
            reason:
              confidenceErr.message,
            next: "Retry confidence retrieval from dedicated confidence endpoint",
          },
        );
      }
    }
    const {
      draftAuditLog:
        rawDraftAuditLog = [],
      draftRevisions:
        rawDraftRevisions = [],
      ...planWithoutDraftHistory
    } = plan;
    const visiblePlan =
      canViewPlanConfidence ?
        {
          ...planWithoutDraftHistory,
          ...(planConfidence ?
            {
              confidence:
                planConfidence,
            }
          : {}),
        }
      : stripPlanConfidenceFields(
          planWithoutDraftHistory,
        );

    const phases =
      await ProductionPhase.find({
        planId: plan._id,
      })
        .sort({ order: 1 })
        .lean();

    const persistedTasks =
      await ProductionTask.find({
        planId: plan._id,
      })
        .sort({
          startDate: 1,
          dueDate: 1,
          manualSortOrder: 1,
          _id: 1,
        })
        .lean();
    const {
      tasks,
      repairedTaskCount:
        repairedAssignedUnitTaskCount,
    } =
      await ensureCanonicalPlanUnitsForPlan(
        {
          plan,
          tasks:
            persistedTasks,
        },
      );
    const progressRecords =
      await TaskProgress.find({
        planId: plan._id,
      })
        .sort({ workDate: -1 })
        .lean();
    const taskDayLedgers =
      await ProductionTaskDayLedger.find({
        planId: plan._id,
      })
        .sort({
          workDate: -1,
          updatedAt: -1,
          _id: 1,
        })
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
    const taskAssignedStaffIds =
      tasks.flatMap((task) =>
        resolveTaskAssignedStaffIds(
          task,
        ),
      );
    const progressStaffIds = Array.from(
      new Set(
        progressRecords
          .map((record) =>
            record.staffId?.toString(),
          )
          .filter(Boolean),
      ),
    );
    const planStaffIds = Array.from(
      new Set([
        ...taskAssignedStaffIds,
        ...progressStaffIds,
      ]),
    ).filter((staffId) =>
      mongoose.Types.ObjectId.isValid(
        staffId,
      ),
    );
    const planStaffProfiles =
      planStaffIds.length > 0 ?
        await BusinessStaffProfile.find(
          {
            _id: {
              $in: planStaffIds,
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
    const timelineWindow =
      resolvePlanTimelineWindow({
        plan,
        tasks,
        progressRecords,
      });
    const attendanceFilter = {
      staffProfileId: {
        $in: planStaffIds,
      },
    };
    if (timelineWindow) {
      attendanceFilter.clockInAt = {
        $gte: timelineWindow.start,
        $lte: timelineWindow.end,
      };
    }
    const attendanceRecords =
      planStaffIds.length > 0 ?
        await StaffAttendance.find(
          attendanceFilter,
        )
          .sort({ clockInAt: 1 })
          .lean()
      : [];
    const timelineRows =
      buildTimelineRows({
        progressRecords,
        tasks,
        phases,
        staffProfiles:
          planStaffProfiles,
      });
    const staffProgressScores =
      buildStaffProgressScores({
        progressRecords,
        staffProfiles:
          planStaffProfiles,
      });
    const dailyRollups =
      buildProductionDailyRollups({
        tasks,
        progressRecords,
        attendanceRecords,
        taskDayLedgers,
      });
    const attendanceImpact =
      buildAttendanceImpactKpis({
        dailyRollups,
      });
    const selfStaffProfileId =
      normalizeStaffIdInput(
        staffProfile?._id,
      );
    let visibleKpis = kpis;
    let visibleAttendanceImpact =
      attendanceImpact;
    let visibleDailyRollups =
      dailyRollups;
    let visibleTimelineRows =
      timelineRows;
    let visibleAttendanceRecords =
      attendanceRecords;
    let visibleStaffProgressScores =
      staffProgressScores;
    let visiblePlanStaffProfiles =
      planStaffProfiles;
    const visibleTaskDayLedgers =
      taskDayLedgers;
    if (
      actor.role === "staff" &&
      !canViewTeamKpis
    ) {
      // CONFIDENCE-SCORE
      // WHY: Non-manager staff must receive only personal KPI context while manager roles keep team analytics.
      visibleKpis = null;
      visibleAttendanceImpact = null;
      visibleDailyRollups = [];
      visibleTimelineRows =
        timelineRows.filter(
          (row) =>
            normalizeStaffIdInput(
              row?.staffId,
            ) === selfStaffProfileId,
        );
      visibleAttendanceRecords =
        attendanceRecords.filter(
          (record) =>
            normalizeStaffIdInput(
              record?.staffProfileId,
            ) === selfStaffProfileId,
        );
      visibleStaffProgressScores =
        staffProgressScores.filter(
          (score) =>
            normalizeStaffIdInput(
              score?.staffId,
            ) === selfStaffProfileId,
        );
      visiblePlanStaffProfiles =
        planStaffProfiles.filter(
          (profile) =>
            normalizeStaffIdInput(
              profile?._id,
            ) === selfStaffProfileId,
        );
    }
    let phaseUnitProgress = [];
    if (
      PRODUCTION_FEATURE_FLAGS.enablePhaseUnitCompletion &&
      phases.length > 0
    ) {
      // UNIT-LIFECYCLE
      // WHY: Manager detail view needs deterministic required/completed/remaining unit counts per phase.
      const completedCountByPhaseId =
        new Map();
      await Promise.all(
        phases.map(async (phase) => {
          const completedUnitCount =
            await getCompletedUnitCount(
              {
                planId: plan._id,
                phaseId: phase._id,
              },
            );
          completedCountByPhaseId.set(
            phase._id.toString(),
            completedUnitCount,
          );
        }),
      );

      phaseUnitProgress = phases.map(
        (phase) => {
          const phaseType = (
            phase?.phaseType || "finite"
          )
            .toString()
            .trim()
            .toLowerCase();
          const requiredUnits =
            Math.max(
              0,
              Number(
                phase?.requiredUnits ||
                  0,
              ),
            );
          const completedUnitCount =
            Math.max(
              0,
              Number(
                completedCountByPhaseId.get(
                  phase._id.toString(),
                ) || 0,
              ),
            );
          const remainingUnits =
            Math.max(
              0,
              requiredUnits -
                completedUnitCount,
            );

          return {
            phaseId: phase._id,
            phaseName:
              phase?.name || "",
            phaseType,
            requiredUnits,
            completedUnitCount,
            remainingUnits,
            // PHASE-GATE-LAYER
            // WHY: Finite phase lock state is derived from remaining unit budget.
            isLocked:
              phaseType === "finite" &&
              remainingUnits <= 0,
          };
        },
      );
    }

    let unitDivergence = [];
    let unitScheduleWarnings = [];
    let deviationGovernanceSummary =
      null;
    let deviationAlerts = [];
    if (
      PRODUCTION_FEATURE_FLAGS.enableUnitAssignments &&
      canViewPlanRiskSignals
    ) {
      const unitScheduleInsights =
        await buildUnitScheduleInsightsForPlan(
          {
            planId: plan._id,
          },
        );
      unitDivergence =
        unitScheduleInsights.unitDivergence;
      unitScheduleWarnings =
        unitScheduleInsights.unitScheduleWarnings;
    }
    if (
      PRODUCTION_FEATURE_FLAGS.enableDeviationGovernance &&
      canViewPlanRiskSignals
    ) {
      // DEVIATION-GOVERNANCE
      // WHY: Manager detail view needs summary + enriched alert rows for freeze and intervention workflows.
      const [alertRows, planUnitRows] =
        await Promise.all([
          LifecycleDeviationAlert.find({
            planId: plan._id,
            businessId,
          })
            .sort({ createdAt: -1 })
            .lean(),
          PlanUnit.find({
            planId: plan._id,
          })
            .select({
              _id: 1,
              unitIndex: 1,
              label: 1,
              deviationLocked: 1,
              deviationLockedAt: 1,
            })
            .lean(),
        ]);
      const planUnitById = new Map(
        planUnitRows.map((unit) => [
          normalizeStaffIdInput(
            unit?._id,
          ),
          unit,
        ]),
      );
      const taskTitleById = new Map(
        tasks.map((task) => [
          normalizeStaffIdInput(
            task?._id,
          ),
          task?.title || "",
        ]),
      );
      deviationAlerts = alertRows.map(
        (alertRow) =>
          normalizeDeviationAlertForResponse(
            {
              alert: alertRow,
              planUnitById,
              taskTitleById,
            },
          ),
      );
      deviationGovernanceSummary =
        buildDeviationSummary({
          alerts: alertRows,
          lockedUnits:
            planUnitRows.filter(
              (unit) =>
                unit?.deviationLocked ===
                true,
            ).length,
        });
    }

    debug(
      "BUSINESS CONTROLLER: getProductionPlanDetail - success",
      {
        actorId: actor._id,
        planId: plan._id,
        phases: phases.length,
        tasks: tasks.length,
        repairedAssignedUnitTaskCount,
        progressRows:
          visibleTimelineRows.length,
        taskDayLedgerRows:
          visibleTaskDayLedgers.length,
        attendanceRows:
          visibleAttendanceRecords.length,
        dailyRollupDays:
          visibleDailyRollups.length,
        canViewTeamKpis,
        phaseUnitProgressRows:
          phaseUnitProgress.length,
        canViewPlanRiskSignals,
        unitDivergenceRows:
          unitDivergence.length,
        unitScheduleWarningsRows:
          unitScheduleWarnings.length,
        deviationAlertRows:
          deviationAlerts.length,
        hasDeviationSummary:
          deviationGovernanceSummary !=
          null,
        outputs: outputs.length,
        productState:
          product?.productionState ||
          null,
      },
    );

    return res.status(200).json({
      message:
        PRODUCTION_COPY.PLAN_DETAIL_OK,
      plan: visiblePlan,
      ...(planConfidence ?
        {
          confidence: planConfidence,
        }
      : {}),
      phases,
      tasks,
      outputs,
      kpis: visibleKpis,
      product,
      preorderSummary:
        buildPreorderSummary(
          product,
          capConfidence,
        ),
      attendanceImpact:
        visibleAttendanceImpact,
      dailyRollups: visibleDailyRollups,
      timelineRows: visibleTimelineRows,
      taskDayLedgers:
        visibleTaskDayLedgers,
      attendanceRecords:
        visibleAttendanceRecords,
      staffProfiles:
        visiblePlanStaffProfiles.map(
          serializeStaffProfileSummary,
        ),
      staffProgressScores:
        visibleStaffProgressScores,
      draftAuditLog:
        sanitizeProductionDraftAuditEntries(
          rawDraftAuditLog,
        ),
      draftRevisions:
        sanitizeProductionDraftRevisionEntries(
          rawDraftRevisions,
        ),
      phaseUnitProgress,
      unitDivergence,
      unitScheduleWarnings,
      deviationGovernanceSummary,
      deviationAlerts,
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
      req.body?.conservativeYieldUnit
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
      conservativeYieldQuantity == null
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
        (
          product.productionState ===
          PRODUCT_STATE_ACTIVE_STOCK
        ) ?
          PRODUCT_STATE_ACTIVE_STOCK
        : PRODUCT_STATE_IN_PRODUCTION;
      updates.productionState =
        fallbackState;
      updates.preorderEnabled = false;
      updates.preorderStartDate = null;
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
      product.preorderEnabled !== true
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.PREORDER_RESERVE_DISABLED,
      });
    }

    const capConfidence =
      await buildPreorderCapConfidenceSummary(
        {
          productId: product._id,
          businessId,
          planId: plan._id,
          baseCap:
            product.preorderCapQuantity,
        },
      );
    const effectiveCap = Math.max(
      0,
      Number(
        capConfidence.effectiveCap || 0,
      ),
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

    const preorderSummary = (() => {
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
        reservationId: reservation._id,
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
      status: req.query?.status || null,
      planId: req.query?.planId || null,
      page: req.query?.page || null,
      limit: req.query?.limit || null,
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
      (
        Number.isFinite(parsedPage) &&
        parsedPage > 0
      ) ?
        Math.floor(parsedPage)
      : 1;
    const limit =
      (
        Number.isFinite(parsedLimit) &&
        parsedLimit > 0
      ) ?
        Math.min(
          100,
          Math.floor(parsedLimit),
        )
      : 20;
    const skip = (page - 1) * limit;

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

    const [
      reservations,
      total,
      summaryRows,
    ] = await Promise.all([
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
        status: statusFilter || null,
        planId: planIdFilter || null,
        page,
        limit,
      },
      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
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
      reservationScope.userId =
        actor._id;
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
                ...((
                  actor.role ===
                  "customer"
                ) ?
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
            await ProductionPlan.findOne(
              {
                _id: reservation.planId,
                businessId,
              },
            )
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

          const beforeReserved =
            Math.max(
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
      reservation: releasedReservation,
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
      reservationScope.userId =
        actor._id;
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
      reservation: confirmedReservation,
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
        errorCount: summary.errorCount,
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

    if (
      nextStatus ===
      PRODUCTION_TASK_STATUS_DONE
    ) {
      // WHY: Stage-0 boundary log captures task completion attempts before persistence.
      logProductionLifecycleBoundary({
        operation: "task_completion",
        stage: "start",
        intent:
          "mark production task as completed",
        actorId: actor._id,
        businessId,
        context: {
          route:
            "/business/production/tasks/:id/status",
          source: "task_status_patch",
          planId: plan._id.toString(),
          taskId: task._id.toString(),
          requestedStatus: nextStatus,
        },
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

    if (
      nextStatus ===
      PRODUCTION_TASK_STATUS_DONE
    ) {
      logProductionLifecycleBoundary({
        operation: "task_completion",
        stage: "success",
        intent:
          "mark production task as completed",
        actorId: actor._id,
        businessId,
        context: {
          route:
            "/business/production/tasks/:id/status",
          source: "task_status_patch",
          planId: plan._id.toString(),
          taskId: task._id.toString(),
          completedAt: task.completedAt,
        },
      });
    }

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_STATUS_UPDATED,
      task,
    });
  } catch (err) {
    if (
      req.body?.status
        ?.toString()
        .trim() ===
      PRODUCTION_TASK_STATUS_DONE
    ) {
      logProductionLifecycleBoundary({
        operation: "task_completion",
        stage: "failure",
        intent:
          "mark production task as completed",
        actorId: req.user?.sub,
        businessId:
          req.user?.businessId || null,
        context: {
          route:
            "/business/production/tasks/:id/status",
          source: "task_status_patch",
          taskId:
            req.params?.id || null,
          reason: err.message,
        },
      });
    }
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
      taskId: req.params?.taskId,
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
      req.body?.assignedStaffProfileIds;
    if (
      !Array.isArray(rawAssignedIds)
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_ASSIGNMENT_STAFF_IDS_REQUIRED,
      });
    }

    const assignedStaffProfileIds =
      Array.from(
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
        await BusinessStaffProfile.find(
          {
            _id: {
              $in: assignedStaffProfileIds,
            },
            businessId,
            status: STAFF_STATUS_ACTIVE,
          },
        ).lean();
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
        const assignmentError =
          getProductionTaskAssignmentValidationError(
            {
              taskRoleRequired:
                task.roleRequired,
              assignedProfile: profile,
              estateAssetId:
                plan.estateAssetId,
              invalidRoleError:
                PRODUCTION_COPY.TASK_ASSIGNMENT_ROLE_MISMATCH,
              scopeError:
                PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
            },
          );
        if (assignmentError) {
          return res.status(400).json({
            error: assignmentError,
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
      requiredHeadcount - assignedCount,
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
        roleRequired: task.roleRequired,
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
        taskId: req.params?.taskId,
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
      hasActualPlotUnits:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "actualPlotUnits",
        ),
      hasQuantityAmount:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "quantityAmount",
        ),
      hasStaffId:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "staffId",
        ),
      hasUnitId:
        Object.prototype.hasOwnProperty.call(
          req.body || {},
          "unitId",
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

    const hasLegacyActualPlots =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "actualPlots",
      );
    const hasLegacyActualPlotUnits =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "actualPlotUnits",
      );
    const hasUnitContribution =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "unitContribution",
      );
    const hasUnitContributionPlotUnits =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "unitContributionPlotUnits",
      );
    const hasActualPlots =
      hasUnitContribution ||
      hasLegacyActualPlots;
    const hasActualPlotUnits =
      hasUnitContributionPlotUnits ||
      hasLegacyActualPlotUnits;
    const quantityActivityType =
      normalizeProductionQuantityActivityType(
        req.body?.activityType ??
          req.body?.quantityActivityType,
      );
    const hasActivityQuantity =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "activityQuantity",
      );
    const hasLegacyQuantityAmount =
      Object.prototype.hasOwnProperty.call(
        req.body || {},
        "quantityAmount",
      );
    const quantityAmount =
      parseNonNegativeNumberInput(
        hasActivityQuantity ?
          req.body?.activityQuantity
        : req.body?.quantityAmount,
      );
    if (quantityAmount == null) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_ACTIVITY_QUANTITY_INVALID,
      });
    }
    const quantityUnit =
      normalizePlantingTargetUnitInput(
        req.body?.activityQuantityUnit ??
          req.body?.quantityUnit,
      );

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

    const resolvedProgressInput =
      (
        hasActualPlots ||
        hasActualPlotUnits
      ) ?
        resolveActualPlotProgressInput({
          hasActualPlots,
          actualPlotsRaw:
            hasUnitContribution ?
              req.body?.unitContribution
            : req.body?.actualPlots,
          hasActualPlotUnits,
          actualPlotUnitsRaw:
            hasUnitContributionPlotUnits ?
              req.body
                ?.unitContributionPlotUnits
            : req.body?.actualPlotUnits,
        })
      : {
          ok: true,
          actualPlots: 0,
          actualPlotUnits: 0,
        };
    if (!resolvedProgressInput.ok) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_ACTUAL_INVALID,
      });
    }
    let actualPlots =
      resolvedProgressInput.actualPlots;
    let actualPlotUnits =
      resolvedProgressInput.actualPlotUnits;
    let effectiveQuantityAmount =
      quantityAmount || 0;
    if (
      quantityActivityType ===
      PRODUCTION_QUANTITY_ACTIVITY_NONE
    ) {
      actualPlots = 0;
      actualPlotUnits = 0;
      effectiveQuantityAmount = 0;
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
      quantityActivityType !==
        PRODUCTION_QUANTITY_ACTIVITY_NONE &&
      actualPlotUnits === 0 &&
      effectiveQuantityAmount === 0 &&
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
    const requestedUnitId =
      normalizeStaffIdInput(
        req.body?.unitId,
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
    if (
      requestedUnitId &&
      !mongoose.Types.ObjectId.isValid(
        requestedUnitId,
      )
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_UNIT_ID_INVALID,
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
      }) &&
      !canLogProductionTaskProgress({
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

    const ledgerConfig =
      resolveTaskDayLedgerConfig({
        task,
        plan,
      });

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
    const actorStaffProfileId =
      normalizeStaffIdInput(
        staffProfile?._id,
      );
    const canManageProgressForOthers =
      canAssignProductionTasks({
        actorRole: actor.role,
        staffRole:
          staffProfile?.staffRole,
      });
    if (!canManageProgressForOthers) {
      if (!actorStaffProfileId) {
        return res.status(403).json({
          error:
            PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
        });
      }
      if (
        requestedStaffId &&
        requestedStaffId !==
          actorStaffProfileId
      ) {
        return res.status(403).json({
          error:
            PRODUCTION_COPY.STAFF_TASK_FORBIDDEN,
        });
      }
      if (
        !assignedStaffIds.includes(
          actorStaffProfileId,
        )
      ) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.TASK_PROGRESS_STAFF_NOT_ASSIGNED,
        });
      }
      effectiveStaffId =
        actorStaffProfileId;
    } else {
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

    const assignedUnitIds =
      resolveTaskAssignedUnitIds(task);
    let effectiveUnitId = null;
    if (requestedUnitId) {
      if (
        assignedUnitIds.length === 0 ||
        !assignedUnitIds.includes(
          requestedUnitId,
        )
      ) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.TASK_PROGRESS_UNIT_NOT_ASSIGNED,
        });
      }
      effectiveUnitId = requestedUnitId;
    } else if (
      assignedUnitIds.length === 1
    ) {
      effectiveUnitId =
        assignedUnitIds[0];
    } else if (
      assignedUnitIds.length > 1
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_UNIT_REQUIRED_FOR_MULTI_ASSIGN,
      });
    }
    if (effectiveUnitId) {
      const inScopePlanUnit =
        await PlanUnit.findOne({
          _id: effectiveUnitId,
          planId: plan._id,
        })
          .select({ _id: 1 })
          .lean();
      if (!inScopePlanUnit) {
        return res.status(400).json({
          error:
            PRODUCTION_COPY.TASK_PROGRESS_UNIT_SCOPE_INVALID,
        });
      }
    }

    const effectiveStaffProfile =
      await BusinessStaffProfile.findOne(
        {
          _id: effectiveStaffId,
          businessId,
        },
      ).lean();
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
        planEstateId !== staffEstateId)
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_STAFF_SCOPE_INVALID,
      });
    }

    const expectedPlots = Math.max(
      0,
      Number(
        ledgerConfig.unitTarget || 0,
      ),
    );
    const expectedPlotUnits =
      convertPlotsToPlotUnits(
        expectedPlots,
      ) || 0;
    const requiredProofCount =
      resolveTaskProgressProofCount(
        actualPlots,
      );
    const uploadedProofFiles =
      normalizeTaskProgressProofFiles(
        req.files,
      );
    if (
      requiredProofCount === 0 &&
      uploadedProofFiles.length > 0
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_PROOFS_NOT_ALLOWED_FOR_ZERO_PROGRESS,
      });
    }
    if (
      requiredProofCount > 0 &&
      uploadedProofFiles.length > 0 &&
      uploadedProofFiles.length !==
        requiredProofCount
    ) {
      return res.status(400).json({
        error:
          PRODUCTION_COPY.TASK_PROGRESS_PROOFS_COUNT_INVALID,
        requiredProofCount,
        providedProofCount:
          uploadedProofFiles.length,
      });
    }
    let progress = null;
    let ledger = null;
    let finalProofCount = 0;
    let session = null;

    try {
      session =
        await mongoose.startSession();
      await session.withTransaction(
        async () => {
          const activeAttendance =
            await StaffAttendance.findOne(
              {
                staffProfileId:
                  effectiveStaffId,
                taskId: task._id,
                workDate:
                  normalizedWorkDate,
                clockOutAt: null,
              },
            )
              .sort({
                clockInAt: -1,
                _id: -1,
              })
              .session(session);
          const completedAttendance =
            activeAttendance ||
            await StaffAttendance.findOne(
              {
                staffProfileId:
                  effectiveStaffId,
                taskId: task._id,
                workDate:
                  normalizedWorkDate,
                clockOutAt: {
                  $ne: null,
                  $gte:
                    normalizedWorkDate,
                },
              },
            )
              .sort({
                clockOutAt: -1,
                clockInAt: -1,
              })
              .session(session);

          if (!completedAttendance) {
            throw new Error(
              PRODUCTION_COPY.TASK_PROGRESS_ATTENDANCE_REQUIRED,
            );
          }

          const progressQuery = {
            taskId: task._id,
            staffId:
              effectiveStaffId,
            unitId:
              effectiveUnitId || null,
            workDate:
              normalizedWorkDate,
          };
          const existingProgress =
            await TaskProgress.findOne(
              progressQuery,
            ).session(session);

          const currentLedger =
            await recomputeProductionTaskDayLedger(
              {
                session,
                planId: plan._id,
                taskId: task._id,
                workDate:
                  normalizedWorkDate,
                unitTarget:
                  ledgerConfig.unitTarget,
                unitType:
                  ledgerConfig.unitType,
                activityTargets:
                  ledgerConfig.activityTargets,
                activityUnits:
                  ledgerConfig.activityUnits,
              },
            );
          const existingUnitContribution =
            resolveTaskProgressUnitContribution(
              existingProgress,
            );
          const maxAllowedPlots =
            Math.max(
              0,
              Number(
                currentLedger?.unitRemaining ||
                  0,
              ) +
                existingUnitContribution,
            );
          if (
            actualPlots >
            maxAllowedPlots
          ) {
            throw Object.assign(
              new Error(
                PRODUCTION_COPY.TASK_PROGRESS_TARGET_EXCEEDED,
              ),
              {
                statusCode: 400,
                payload: {
                  maxAllowedPlots,
                  maxAllowedPlotUnits:
                    convertPlotsToPlotUnits(
                      maxAllowedPlots,
                    ) || 0,
                  taskTargetPlots:
                    expectedPlots,
                  taskTargetPlotUnits:
                    expectedPlotUnits,
                },
              },
            );
          }

          if (
            quantityActivityType !==
            PRODUCTION_QUANTITY_ACTIVITY_NONE
          ) {
            const rawActivityTarget =
              currentLedger
                ?.activityTargets?.[
                  quantityActivityType
                ];
            const activityTarget =
              rawActivityTarget == null ?
                null
              : Number(
                  rawActivityTarget,
                );
            const hasActivityTarget =
              Number.isFinite(
                activityTarget,
              ) &&
              activityTarget >= 0;
            const existingActivityType =
              resolveTaskProgressActivityType(
                existingProgress,
              );
            const existingActivityQuantity =
              existingActivityType ===
                quantityActivityType ?
                resolveTaskProgressActivityQuantity(
                  existingProgress,
                )
              : 0;
            const maxAllowedActivityQuantity =
              hasActivityTarget ?
                Math.max(
                  0,
                  Number(
                    currentLedger
                      ?.activityRemaining?.[
                        quantityActivityType
                      ] || 0,
                  ) +
                    existingActivityQuantity,
                )
              : Number.POSITIVE_INFINITY;
            if (
              hasActivityTarget &&
              effectiveQuantityAmount >
                maxAllowedActivityQuantity
            ) {
              throw Object.assign(
                new Error(
                  PRODUCTION_COPY.TASK_PROGRESS_ACTIVITY_TARGET_EXCEEDED,
                ),
                {
                  statusCode: 400,
                  payload: {
                    activityType:
                      quantityActivityType,
                    maxAllowedActivityQuantity,
                    activityTarget,
                  },
                },
              );
            }
          }

          const existingProofs =
            Array.isArray(
              existingProgress?.proofs,
            ) ?
              existingProgress.proofs
            : [];
          const existingProofCount =
            existingProofs.length;
          let proofsToPersist =
            existingProofs;
          if (
            requiredProofCount === 0
          ) {
            proofsToPersist = [];
          } else if (
            uploadedProofFiles.length > 0
          ) {
            proofsToPersist =
              await uploadTaskProgressProofImages(
                {
                  businessId,
                  taskId:
                    task._id?.toString(),
                  staffId:
                    effectiveStaffId,
                  workDate:
                    normalizedWorkDate,
                  files:
                    uploadedProofFiles,
                  uploadedBy:
                    actor._id,
                },
              );
          } else if (
            existingProofCount !==
            requiredProofCount
          ) {
            throw Object.assign(
              new Error(
                existingProofCount > 0 ?
                  PRODUCTION_COPY.TASK_PROGRESS_PROOFS_COUNT_INVALID
                : PRODUCTION_COPY.TASK_PROGRESS_PROOFS_REQUIRED,
              ),
              {
                statusCode: 400,
                payload: {
                  requiredProofCount,
                  providedProofCount:
                    existingProofCount,
                },
              },
            );
          }

          const resolvedQuantityUnit =
            quantityActivityType ===
              PRODUCTION_QUANTITY_ACTIVITY_NONE ?
              ""
            : quantityUnit ||
              ledgerConfig
                ?.activityUnits?.[
                  quantityActivityType
                ] ||
              "";
          const progressDoc =
            await TaskProgress.findOneAndUpdate(
              progressQuery,
              {
                $set: {
                  planId: plan._id,
                  unitId:
                    effectiveUnitId ||
                    null,
                  expectedPlots,
                  expectedPlotUnits,
                  actualPlots,
                  actualPlotUnits,
                  unitContribution:
                    actualPlots,
                  unitContributionPlotUnits:
                    actualPlotUnits,
                  quantityActivityType:
                    quantityActivityType,
                  activityType:
                    quantityActivityType,
                  quantityAmount:
                    effectiveQuantityAmount,
                  activityQuantity:
                    effectiveQuantityAmount,
                  quantityUnit:
                    resolvedQuantityUnit,
                  proofCountRequired:
                    requiredProofCount,
                  proofCountUploaded:
                    proofsToPersist.length,
                  proofs:
                    proofsToPersist,
                  delayReason,
                  notes,
                  sessionStatus:
                    "completed",
                  clockInTime:
                    completedAttendance.clockInAt ||
                    null,
                  clockOutTime:
                    completedAttendance.clockOutAt ||
                    new Date(),
                },
                $setOnInsert: {
                  createdBy:
                    actor._id,
                },
              },
              {
                new: true,
                upsert: true,
                setDefaultsOnInsert: true,
                session,
              },
            );

          if (
            activeAttendance &&
            !activeAttendance.clockOutAt
          ) {
            const resolvedClockOutAt =
              new Date();
            activeAttendance.clockOutAt =
              resolvedClockOutAt;
            activeAttendance.clockOutBy =
              actor._id;
            activeAttendance.durationMinutes =
              Math.max(
                0,
                Math.round(
                  (
                    resolvedClockOutAt.getTime() -
                    new Date(
                      activeAttendance.clockInAt ||
                        resolvedClockOutAt,
                    ).getTime()
                  ) /
                    MS_PER_MINUTE,
                ),
              );
            activeAttendance.planId =
              plan._id;
            activeAttendance.taskId =
              task._id;
            activeAttendance.workDate =
              normalizedWorkDate;
            await activeAttendance.save({
              session,
            });
            progressDoc.clockOutTime =
              resolvedClockOutAt;
          }

          ledger =
            await recomputeProductionTaskDayLedger(
              {
                session,
                planId: plan._id,
                taskId: task._id,
                workDate:
                  normalizedWorkDate,
                unitTarget:
                  ledgerConfig.unitTarget,
                unitType:
                  ledgerConfig.unitType,
                activityTargets:
                  ledgerConfig.activityTargets,
                activityUnits:
                  ledgerConfig.activityUnits,
              },
            );
          progressDoc.taskDayLedgerId =
            ledger?._id || null;
          await progressDoc.save({
            session,
          });
          progress =
            progressDoc.toObject();
          finalProofCount =
            proofsToPersist.length;
        },
      );
    } finally {
      if (session) {
        await session.endSession();
      }
    }

    debug(
      "BUSINESS CONTROLLER: logProductionTaskProgress - success",
      {
        actorId: actor._id,
        taskId: task._id,
        planId: plan._id,
        staffId: effectiveStaffId,
        assignedStaffCount:
          assignedStaffIds.length,
        requestedStaffId,
        unitId: effectiveUnitId || "",
        workDate: normalizedWorkDate,
        actualPlots,
        actualPlotUnits,
        quantityActivityType,
        quantityAmount:
          effectiveQuantityAmount,
        quantityUnit,
        expectedPlotUnits,
        proofCount:
          finalProofCount,
        ledgerId:
          ledger?._id || null,
        sharedUnitRemaining:
          ledger?.unitRemaining || 0,
      },
    );

    await emitProductionPlanRoomSnapshot({
      businessId,
      planId: plan._id,
      context: "task_progress_logged",
    });

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_CREATED,
      progress,
      ledger,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: logProductionTaskProgress - error",
      err.message,
    );
    return res.status(
      err?.statusCode || 400,
    ).json({
      error: err.message,
      ...(err?.payload || {}),
    });
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
      entryCount:
        (
          Array.isArray(
            req.body?.entries,
          )
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

    const staffIdsForLookup =
      Array.from(
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
        await BusinessStaffProfile.find(
          {
            _id: {
              $in: staffIdsForLookup,
            },
            businessId,
          },
        ).lean()
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
    const completedAttendanceRows =
      staffIdsForLookup.length > 0 ?
        await StaffAttendance.find({
          staffProfileId: {
            $in: staffIdsForLookup,
          },
          taskId: {
            $in: taskIdsForLookup,
          },
          clockInAt: {
            $lt: new Date(
              normalizedWorkDate.getTime() +
                MS_PER_DAY,
            ),
          },
          clockOutAt: {
            $ne: null,
            $gte: normalizedWorkDate,
          },
        })
          .select({
            _id: 1,
            staffProfileId: 1,
            taskId: 1,
            workDate: 1,
            clockInAt: 1,
            clockOutAt: 1,
            durationMinutes: 1,
          })
          .sort({
            clockOutAt: -1,
            clockInAt: -1,
          })
          .lean()
      : [];
    const completedAttendanceByScopeKey =
      new Map();
    const completedAttendanceByStaffId =
      new Map();
    completedAttendanceRows.forEach(
      (row) => {
        const scopedStaffId =
          normalizeStaffIdInput(
            row?.staffProfileId,
          );
        const scopedTaskId =
          normalizeStaffIdInput(
            row?.taskId,
          );
        const scopedWorkDate =
          normalizeWorkDateToDayStart(
            row?.workDate ||
              row?.clockOutAt ||
              row?.clockInAt,
          );
        if (
          scopedStaffId &&
          scopedTaskId &&
          scopedWorkDate
        ) {
          completedAttendanceByScopeKey.set(
            `${scopedStaffId}::${scopedTaskId}::${scopedWorkDate.toISOString()}`,
            row,
          );
        }
        if (
          scopedStaffId &&
          !completedAttendanceByStaffId.has(
            scopedStaffId,
          )
        ) {
          completedAttendanceByStaffId.set(
            scopedStaffId,
            row,
          );
        }
      },
    );
    const unitIdsForLookup = Array.from(
      new Set(
        entries
          .map((entry) =>
            normalizeStaffIdInput(
              entry?.unitId,
            ),
          )
          .filter((unitId) =>
            mongoose.Types.ObjectId.isValid(
              unitId,
            ),
          ),
      ),
    );
    const planUnitRows =
      unitIdsForLookup.length > 0 ?
        await PlanUnit.find({
          _id: {
            $in: unitIdsForLookup,
          },
        })
          .select({
            _id: 1,
            planId: 1,
          })
          .lean()
      : [];
    const planUnitById = new Map(
      planUnitRows.map((unitRow) => [
        normalizeStaffIdInput(
          unitRow?._id,
        ),
        normalizeStaffIdInput(
          unitRow?.planId,
        ),
      ]),
    );
    const existingTaskProgressRows =
      taskIdsForLookup.length > 0 ?
        await TaskProgress.find({
          taskId: {
            $in: taskIdsForLookup,
          },
        })
          .select({
            taskId: 1,
            staffId: 1,
            unitId: 1,
            workDate: 1,
            actualPlotUnits: 1,
          })
          .lean()
      : [];
    const taskProgressTotalsByTaskId =
      new Map();
    const taskProgressUnitsByRowKey =
      new Map();
    existingTaskProgressRows.forEach(
      (row) => {
        const scopedTaskId =
          normalizeStaffIdInput(
            row?.taskId,
          );
        if (!scopedTaskId) {
          return;
        }
        const rowUnits = Math.max(
          0,
          Number(
            row?.actualPlotUnits || 0,
          ),
        );
        const currentTotal =
          taskProgressTotalsByTaskId.get(
            scopedTaskId,
          ) || 0;
        taskProgressTotalsByTaskId.set(
          scopedTaskId,
          currentTotal + rowUnits,
        );
        const rowKey = `${scopedTaskId}::${buildTaskProgressRowKey(
          {
            staffId: row?.staffId,
            unitId: row?.unitId,
            workDate: row?.workDate,
          },
        )}`;
        const existingRowUnits =
          taskProgressUnitsByRowKey.get(
            rowKey,
          ) || 0;
        taskProgressUnitsByRowKey.set(
          rowKey,
          existingRowUnits + rowUnits,
        );
      },
    );

    const successes = [];
    const errors = [];

    for (
      let index = 0;
      index < entries.length;
      index += 1
    ) {
      const entry =
        entries[index] || {};
      const taskId =
        normalizeStaffIdInput(
          entry?.taskId,
        );
      const staffId =
        normalizeStaffIdInput(
          entry?.staffId,
        );
      const unitId =
        normalizeStaffIdInput(
          entry?.unitId,
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
            unitId,
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

      const task = taskMap.get(taskId);
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

      const assignedUnitIds =
        resolveTaskAssignedUnitIds(
          task,
        );
      let effectiveUnitId = null;
      if (unitId) {
        if (
          !mongoose.Types.ObjectId.isValid(
            unitId,
          )
        ) {
          pushEntryError({
            errorCode:
              TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_ID_INVALID,
            error:
              PRODUCTION_COPY.TASK_PROGRESS_UNIT_ID_INVALID,
          });
          continue;
        }
        if (
          assignedUnitIds.length ===
            0 ||
          !assignedUnitIds.includes(
            unitId,
          )
        ) {
          pushEntryError({
            errorCode:
              TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_NOT_ASSIGNED,
            error:
              PRODUCTION_COPY.TASK_PROGRESS_UNIT_NOT_ASSIGNED,
          });
          continue;
        }
        effectiveUnitId = unitId;
      } else if (
        assignedUnitIds.length === 1
      ) {
        effectiveUnitId =
          assignedUnitIds[0];
      } else if (
        assignedUnitIds.length > 1
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_ID_REQUIRED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_UNIT_REQUIRED_FOR_MULTI_ASSIGN,
        });
        continue;
      }
      if (effectiveUnitId) {
        const scopedPlanId =
          normalizeStaffIdInput(
            plan?._id,
          );
        const unitPlanId =
          planUnitById.get(
            effectiveUnitId,
          ) || "";
        if (
          !unitPlanId ||
          unitPlanId !== scopedPlanId
        ) {
          pushEntryError({
            errorCode:
              TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_SCOPE_INVALID,
            error:
              PRODUCTION_COPY.TASK_PROGRESS_UNIT_SCOPE_INVALID,
          });
          continue;
        }
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

      const completedAttendance =
        completedAttendanceByScopeKey.get(
          `${staffId}::${taskId}::${normalizedWorkDate.toISOString()}`,
        ) ||
        completedAttendanceByStaffId.get(
          staffId,
        ) ||
        null;
      if (!completedAttendance) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_ATTENDANCE_REQUIRED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_ATTENDANCE_REQUIRED,
        });
        continue;
      }

      const hasActualPlots =
        Object.prototype.hasOwnProperty.call(
          entry,
          "actualPlots",
        );
      const hasActualPlotUnits =
        Object.prototype.hasOwnProperty.call(
          entry,
          "actualPlotUnits",
        );
      if (
        !hasActualPlots &&
        !hasActualPlotUnits
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_REQUIRED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_ACTUAL_REQUIRED,
        });
        continue;
      }

      const resolvedProgressInput =
        resolveActualPlotProgressInput({
          hasActualPlots,
          actualPlotsRaw:
            entry?.actualPlots,
          hasActualPlotUnits,
          actualPlotUnitsRaw:
            entry?.actualPlotUnits,
        });
      if (!resolvedProgressInput.ok) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_INVALID,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_ACTUAL_INVALID,
        });
        continue;
      }
      const actualPlots =
        resolvedProgressInput.actualPlots;
      const actualPlotUnits =
        resolvedProgressInput.actualPlotUnits;
      const hasQuantityActivityType =
        Object.prototype.hasOwnProperty.call(
          entry,
          "activityType",
        ) ||
        Object.prototype.hasOwnProperty.call(
          entry,
          "quantityActivityType",
        );
      const quantityActivityType =
        hasQuantityActivityType ?
          normalizeProductionQuantityActivityType(
            entry?.activityType ??
              entry?.quantityActivityType,
          )
        : PRODUCTION_QUANTITY_ACTIVITY_NONE;
      const hasActivityQuantity =
        Object.prototype.hasOwnProperty.call(
          entry,
          "activityQuantity",
        ) ||
        Object.prototype.hasOwnProperty.call(
          entry,
          "quantityAmount",
        );
      const parsedActivityQuantity =
        hasActivityQuantity ?
          parseNonNegativeNumberInput(
            entry?.activityQuantity ??
              entry?.quantityAmount,
          )
        : 0;
      if (
        hasActivityQuantity &&
        parsedActivityQuantity == null
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_ACTUAL_INVALID,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_ACTIVITY_QUANTITY_INVALID,
        });
        continue;
      }
      const quantityAmount =
        quantityActivityType ===
            PRODUCTION_QUANTITY_ACTIVITY_NONE
          ? 0
          : parsedActivityQuantity || 0;
      const quantityUnit =
        quantityActivityType ===
            PRODUCTION_QUANTITY_ACTIVITY_NONE
          ? ""
          : normalizePlantingTargetUnitInput(
              entry?.activityQuantityUnit ??
                entry?.quantityUnit,
            );

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
        actualPlotUnits === 0 &&
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
      const planWorkUnitCount = Math.max(
        0,
        Number(plan?.workloadContext?.totalWorkUnits || 0),
      );
      const expectedPlotUnits =
        resolveTaskProgressTargetPlotUnits(
          task,
          {
            fallbackTotalUnits:
              planWorkUnitCount,
          },
        );
      const expectedPlots =
        convertPlotUnitsToPlots(
          expectedPlotUnits,
        ) || 0;
      const rowKey = `${taskId}::${buildTaskProgressRowKey(
        {
          staffId,
          unitId:
            effectiveUnitId || null,
          workDate:
            normalizedWorkDate,
        },
      )}`;
      const loggedUnitsAcrossTask =
        taskProgressTotalsByTaskId.get(
          taskId,
        ) || 0;
      const existingSelectionUnits =
        taskProgressUnitsByRowKey.get(
          rowKey,
        ) || 0;
      const loggedUnitsExcludingSelection =
        Math.max(
          0,
          loggedUnitsAcrossTask -
            existingSelectionUnits,
        );
      const maxAllowedPlotUnits =
        Math.max(
          0,
          expectedPlotUnits -
            loggedUnitsExcludingSelection,
        );
      if (
        actualPlotUnits >
        maxAllowedPlotUnits
      ) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_TARGET_EXCEEDED,
          error:
            PRODUCTION_COPY.TASK_PROGRESS_TARGET_EXCEEDED,
        });
        continue;
      }

      try {
        const progress =
          await TaskProgress.findOneAndUpdate(
            {
              taskId: task._id,
              staffId,
              unitId:
                effectiveUnitId || null,
              workDate:
                normalizedWorkDate,
            },
            {
              $set: {
                planId: plan._id,
                unitId:
                  effectiveUnitId ||
                  null,
                expectedPlots,
                expectedPlotUnits,
                actualPlots,
                actualPlotUnits,
                unitContribution:
                  actualPlots,
                unitContributionPlotUnits:
                  actualPlotUnits,
                quantityActivityType,
                activityType:
                  quantityActivityType,
                quantityAmount,
                activityQuantity:
                  quantityAmount,
                quantityUnit,
                proofCountRequired: 0,
                proofCountUploaded: 0,
                proofs: [],
                sessionStatus:
                  "completed",
                clockInTime:
                  completedAttendance
                    ?.clockInAt || null,
                clockOutTime:
                  completedAttendance
                    ?.clockOutAt || null,
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
          unitId: effectiveUnitId || "",
          progress,
        });
        taskProgressTotalsByTaskId.set(
          taskId,
          loggedUnitsExcludingSelection +
            actualPlotUnits,
        );
        taskProgressUnitsByRowKey.set(
          rowKey,
          actualPlotUnits,
        );
      } catch (entryError) {
        pushEntryError({
          errorCode:
            TASK_PROGRESS_BATCH_ENTRY_CODE_UNKNOWN,
          error: entryError.message,
        });
      }
    }

    const summary = {
      totalEntries: entries.length,
      successCount: successes.length,
      errorCount: errors.length,
    };

    debug(
      "BUSINESS CONTROLLER: logProductionTaskProgressBatch - success",
      {
        actorId: actor._id,
        workDate: normalizedWorkDate,
        totalEntries:
          summary.totalEntries,
        successCount:
          summary.successCount,
        errorCount: summary.errorCount,
      },
    );

    if (successes.length > 0) {
      const ledgerScopes = Array.from(
        new Set(
          successes
            .map((entry) => {
              const taskId =
                normalizeStaffIdInput(
                  entry?.taskId,
                );
              const planId =
                normalizeStaffIdInput(
                  entry?.progress?.planId,
                );
              if (
                !taskId ||
                !planId
              ) {
                return "";
              }
              return `${taskId}::${planId}`;
            })
            .filter(Boolean),
        ),
      );
      await Promise.all(
        ledgerScopes.map(
          async (scopeKey) => {
            const [
              scopedTaskId,
              scopedPlanId,
            ] = scopeKey.split(
              "::",
            );
            const scopedTask =
              taskMap.get(
                scopedTaskId,
              );
            const scopedPlan =
              planMap.get(
                scopedPlanId,
              );
            if (
              !scopedTask ||
              !scopedPlan
            ) {
              return;
            }
            const ledgerConfig =
              resolveTaskDayLedgerConfig(
                {
                  task:
                    scopedTask,
                  plan:
                    scopedPlan,
                },
              );
            const ledger =
              await recomputeProductionTaskDayLedger(
                {
                  planId:
                    scopedPlan._id,
                  taskId:
                    scopedTask._id,
                  workDate:
                    normalizedWorkDate,
                  unitTarget:
                    ledgerConfig.unitTarget,
                  unitType:
                    ledgerConfig.unitType,
                  activityTargets:
                    ledgerConfig.activityTargets,
                  activityUnits:
                    ledgerConfig.activityUnits,
                },
              );
            if (!ledger?._id) {
              return;
            }
            await TaskProgress.updateMany(
              {
                taskId:
                  scopedTask._id,
                workDate:
                  normalizedWorkDate,
              },
              {
                $set: {
                  taskDayLedgerId:
                    ledger._id,
                },
              },
            );
          },
        ),
      );
      const planIdsToRefresh = Array.from(
        new Set(
          successes
            .map((entry) =>
              (entry?.progress?.planId || "")
                .toString()
                .trim(),
            )
            .filter(Boolean),
        ),
      );
      await Promise.all(
        planIdsToRefresh.map((planId) =>
          emitProductionPlanRoomSnapshot({
            businessId,
            planId,
            context: "task_progress_batch_logged",
          }),
        ),
      );
    }

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_BATCH_PROCESSED,
      workDate: normalizedWorkDate,
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
      progressId: req.params?.id,
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
    const hadRejectedNote =
      (
        progress.notes
          ?.toString() || ""
      ).includes(
        TASK_PROGRESS_REJECTION_NOTE_PREFIX,
      );
    if (!alreadyApproved) {
      // WHY: Approval is production execution truth boundary for lifecycle analytics.
      logProductionLifecycleBoundary({
        operation:
          "task_completion_approval",
        stage: "start",
        intent:
          "approve production task progress record",
        actorId: actor._id,
        businessId,
        context: {
          route:
            "/business/production/task-progress/:id/approve",
          source:
            "task_progress_approval",
          progressId:
            progress._id.toString(),
          planId:
            progress.planId.toString(),
          taskId:
            progress.taskId.toString(),
        },
      });
    }
    let ledger = null;
    if (
      !alreadyApproved ||
      hadRejectedNote
    ) {
      if (hadRejectedNote) {
        progress.notes =
          stripTaskProgressRejectNotes(
            progress.notes,
          );
      }
      progress.approvedBy = actor._id;
      progress.approvedAt =
        progress.approvedAt ||
        new Date();
      await progress.save();
      const task =
        await ProductionTask.findById(
          progress.taskId,
        ).lean();
      if (
        task &&
        progress.workDate
      ) {
        const ledgerConfig =
          resolveTaskDayLedgerConfig({
            task,
            plan,
          });
        ledger =
          await recomputeProductionTaskDayLedger(
            {
              planId:
                progress.planId,
              taskId:
                progress.taskId,
              workDate:
                progress.workDate,
              unitTarget:
                ledgerConfig.unitTarget,
              unitType:
                ledgerConfig.unitType,
              activityTargets:
                ledgerConfig.activityTargets,
              activityUnits:
                ledgerConfig.activityUnits,
            },
          );
        if (
          ledger?._id &&
          normalizeStaffIdInput(
            progress.taskDayLedgerId,
          ) !==
            normalizeStaffIdInput(
              ledger._id,
            )
        ) {
          progress.taskDayLedgerId =
            ledger._id;
          await progress.save();
        }
      }
    }

    // UNIT-LIFECYCLE
    // WHY: Approved progress is the only boundary that can create phase-unit completion truth.
    let phaseUnitCompletionSync = null;
    if (!alreadyApproved) {
      phaseUnitCompletionSync =
        await syncPhaseUnitCompletionsForApprovedProgress(
          {
            progress,
            approvedBy: actor._id,
            approvedAt:
              progress.approvedAt,
            operation:
              "approveTaskProgress",
          },
        );
    }

    let unitScheduleShiftSync = null;
    if (!alreadyApproved) {
      try {
        unitScheduleShiftSync =
          await shiftUnitScheduleForApprovedProgress(
            {
              progress,
              approvedBy: actor._id,
              businessId,
              productId:
                plan?.productId,
              operation:
                "approveTaskProgress",
            },
          );
      } catch (unitShiftErr) {
        // UNIT-LIFECYCLE
        // WHY: Approval truth should not fail when downstream shift diagnostics fail.
        debug(
          "BUSINESS CONTROLLER: approveTaskProgress - unit shift skipped",
          {
            actorId: actor._id,
            progressId: progress._id,
            planId: progress.planId,
            reason:
              unitShiftErr.message,
            next: "Inspect unit schedule rows and warning logs before retrying shift propagation",
          },
        );
      }
    }

    let confidenceRecompute = null;
    if (!alreadyApproved) {
      // CONFIDENCE-SCORE
      // WHY: Approved completion truth is the deterministic boundary for unit-completion confidence updates.
      try {
        confidenceRecompute =
          await triggerPlanConfidenceRecompute(
            {
              planId: progress.planId,
              trigger:
                CONFIDENCE_RECOMPUTE_TRIGGERS.UNIT_COMPLETION_INSERT,
              actorId: actor._id,
              operation:
                "approveTaskProgress",
            },
          );
      } catch (confidenceErr) {
        // WHY: Approval must persist even if confidence refresh fails.
        debug(
          "BUSINESS CONTROLLER: approveTaskProgress - confidence recompute skipped",
          {
            actorId: actor._id,
            progressId: progress._id,
            planId: progress.planId,
            reason:
              confidenceErr.message,
            next: "Retry confidence recompute through deterministic trigger endpoints",
          },
        );
      }
    }

    debug(
      "BUSINESS CONTROLLER: approveTaskProgress - success",
      {
        actorId: actor._id,
        progressId: progress._id,
        planId: progress.planId,
        taskId: progress.taskId,
        alreadyApproved,
        phaseUnitCompletionsApplied:
          phaseUnitCompletionSync?.applied ===
          true,
        phaseUnitCompletionSkippedReason:
          phaseUnitCompletionSync?.skippedReason ||
          "",
        phaseUnitCompletionUpsertedCount:
          phaseUnitCompletionSync?.upsertedCount ||
          0,
        unitScheduleShiftApplied:
          unitScheduleShiftSync?.applied ===
          true,
        unitScheduleShiftedTaskCount:
          unitScheduleShiftSync?.shiftedTaskCount ||
          0,
        unitScheduleWarningCount:
          unitScheduleShiftSync?.warningCount ||
          0,
      },
    );

    logProductionLifecycleBoundary({
      operation:
        "task_completion_approval",
      stage: "success",
      intent:
        "approve production task progress record",
      actorId: actor._id,
      businessId,
      context: {
        route:
          "/business/production/task-progress/:id/approve",
        source:
          "task_progress_approval",
        progressId:
          progress._id.toString(),
        planId:
          progress.planId.toString(),
        taskId:
          progress.taskId.toString(),
        alreadyApproved,
      },
    });

    await emitProductionPlanRoomSnapshot({
      businessId,
      planId: progress.planId,
      context: "task_progress_approved",
    });

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_APPROVED,
      progress,
      ...(ledger ?
        {
          ledger,
        }
      : {}),
      ...(phaseUnitCompletionSync ?
        {
          phaseUnitCompletion:
            phaseUnitCompletionSync,
        }
      : {}),
      ...(unitScheduleShiftSync ?
        {
          unitScheduleShift:
            unitScheduleShiftSync,
        }
      : {}),
      ...((
        confidenceRecompute?.snapshot
      ) ?
        {
          confidence:
            confidenceRecompute.snapshot,
        }
      : {}),
    });
  } catch (err) {
    logProductionLifecycleBoundary({
      operation:
        "task_completion_approval",
      stage: "failure",
      intent:
        "approve production task progress record",
      actorId: req.user?.sub,
      businessId:
        req.user?.businessId || null,
      context: {
        route:
          "/business/production/task-progress/:id/approve",
        source:
          "task_progress_approval",
        progressId:
          req.params?.id || null,
        reason: err.message,
      },
    });
    debug(
      "BUSINESS CONTROLLER: approveTaskProgress - error",
      {
        actorId: req.user?.sub,
        progressId: req.params?.id,
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
      progressId: req.params?.id,
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
    let ledger = null;
    const task =
      await ProductionTask.findById(
        progress.taskId,
      ).lean();
    if (
      task &&
      progress.workDate
    ) {
      const ledgerConfig =
        resolveTaskDayLedgerConfig({
          task,
          plan,
        });
      ledger =
        await recomputeProductionTaskDayLedger(
          {
            planId:
              progress.planId,
            taskId:
              progress.taskId,
            workDate:
              progress.workDate,
            unitTarget:
              ledgerConfig.unitTarget,
            unitType:
              ledgerConfig.unitType,
            activityTargets:
              ledgerConfig.activityTargets,
            activityUnits:
              ledgerConfig.activityUnits,
          },
        );
      if (
        ledger?._id &&
        normalizeStaffIdInput(
          progress.taskDayLedgerId,
        ) !==
          normalizeStaffIdInput(
            ledger._id,
          )
      ) {
        progress.taskDayLedgerId =
          ledger._id;
        await progress.save();
      }
    }

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

    await emitProductionPlanRoomSnapshot({
      businessId,
      planId: progress.planId,
      context: "task_progress_rejected",
    });

    return res.status(200).json({
      message:
        PRODUCTION_COPY.TASK_PROGRESS_REJECTED,
      progress,
      ...(ledger ?
        {
          ledger,
        }
      : {}),
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: rejectTaskProgress - error",
      {
        actorId: req.user?.sub,
        progressId: req.params?.id,
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
      !isBusinessOwnerEquivalentActor(actor)
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
      !isBusinessOwnerEquivalentActor(actor)
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

    const directApplicationId = req.params?.id
      ?.toString()
      .trim();
    const tenantId = req.params?.tenantId
      ?.toString()
      .trim();
    let applicationId = directApplicationId || "";
    if (!applicationId && tenantId) {
      const latestApplication =
        await BusinessTenantApplication.findOne({
          businessId,
          tenantUserId: tenantId,
        })
          .sort({ createdAt: -1 })
          .select("_id estateAssetId tenantUserId status");

      if (!latestApplication) {
        return res.status(404).json({
          error:
            "Tenant application not found",
        });
      }

      applicationId =
        latestApplication._id.toString();
    }
    if (!applicationId) {
      return res.status(400).json({
        error:
          "Application id or tenant id is required",
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
  debug(
    "BUSINESS CONTROLLER: verifyContact - entry",
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

    const tenantId = req.params?.tenantId
      ?.toString()
      .trim();
    if (!tenantId) {
      return res.status(400).json({
        error: "Tenant id is required",
      });
    }

    const application =
      await BusinessTenantApplication.findOne(
        {
          businessId,
          tenantUserId: tenantId,
        },
      ).sort({ createdAt: -1 });

    if (!application) {
      return res.status(404).json({
        error:
          "Tenant application not found",
      });
    }

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
          applicationId: application._id,
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

    return res.status(200).json({
      message:
        "Tenant contact verified successfully",
      application: updated,
    });
  } catch (err) {
    debug(
      "BUSINESS CONTROLLER: verifyContact - error",
      err.message,
    );
    return res
      .status(400)
      .json({ error: err.message });
  }
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
      !isBusinessOwnerEquivalentActor(actor)
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
  uploadStaffAttendanceProof,
  listStaffAttendance,
  getStaffCapacity,
  getProductionSchedulePolicy,
  updateProductionSchedulePolicy,
  searchProductionAssistantCatalogHandler,
  previewProductionAssistantCropLifecycleHandler,
  productionPlanAssistantTurnHandler,
  generateProductionPlanDraftHandler,
  createProductionPlan,
  updateProductionPlanDraft,
  listProductionPlans,
  updateProductionPlanStatus,
  deleteProductionPlan,
  listProductionCalendar,
  getProductionPortfolioConfidence,
  getProductionPlanConfidence,
  listProductionPlanUnits,
  listProductionPlanDeviationAlerts,
  acceptProductionPlanDeviationVariance,
  replanProductionPlanDeviationUnit,
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
  submitFarmAsset,
  getAssets,
  getFarmAssetAuditAnalytics,
  submitFarmAssetAudit,
  submitFarmToolUsageRequest,
  approveFarmAssetRequest,
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
