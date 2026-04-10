/**
 * routes/business.routes.js
 * -------------------------
 * WHAT:
 * - Business-owner + staff routes.
 *
 * WHY:
 * - Gives verified businesses scoped access to products, orders, and assets.
 *
 * HOW:
 * - Uses requireAuth and requireAnyRole for role gating.
 */

const express = require("express");
const debug = require("../utils/debug");
const multer = require("multer");
const {
  requireAuth,
} = require("../middlewares/auth.middleware");
const {
  requireAnyRole,
  requireRole,
} = require("../middlewares/requireRole.middleware");
const {
  requirePermission,
  PERMISSION_MODULES,
  PERMISSION_CAPABILITIES,
} = require("../middlewares/permissions.middleware");
const businessController = require("../controllers/business.controller");
const {
  verifyPaystackSignature,
} = require("../middlewares/paystackWebhook.middleware");

const router = express.Router();

debug("Business routes initialized");

// WHY: Store uploads in memory for Cloudinary streaming.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
});

function parseTaskProgressProofUploads(
  req,
  res,
  next,
) {
  const contentType = (
    req.headers["content-type"] || ""
  )
    .toString()
    .toLowerCase();
  if (
    !contentType.includes(
      "multipart/form-data",
    )
  ) {
    return next();
  }
  return upload.array("proofs", 10)(
    req,
    res,
    next,
  );
}

/**
 * PRODUCTS
 */
// WHY: Allow tenants to upload reference/guarantor documents before submission.
router.post(
  "/products",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.createProduct,
);

// WHY: Generate AI drafts to help staff prefill product details faster.
router.post(
  "/products/ai-draft",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.generateProductDraftHandler,
);

router.get(
  "/products",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getAllProducts,
);

router.get(
  "/products/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getProductById,
);

router.patch(
  "/products/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.updateProduct,
);

router.patch(
  "/products/:id/restore",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.restoreProduct,
);

router.post(
  "/products/:id/image",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  upload.single("image"),
  businessController.uploadProductImage,
);

router.delete(
  "/products/:id/image",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.deleteProductImage,
);

router.delete(
  "/products/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.softDeleteProduct,
);

/**
 * ORDERS
 */
router.get(
  "/orders",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getOrders,
);

router.patch(
  "/orders/:id/status",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateOrderStatus,
);

/**
 * ASSETS
 */
router.post(
  "/assets",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.createAsset,
);

router.post(
  "/assets/farm-audit/submissions",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.submitFarmAsset,
);

router.get(
  "/assets",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getAssets,
);

router.get(
  "/assets/farm-audit",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getFarmAssetAuditAnalytics,
);

router.post(
  "/assets/:id/farm-audit-requests",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.submitFarmAssetAudit,
);

router.post(
  "/assets/:id/farm-usage-requests",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.submitFarmToolUsageRequest,
);

router.post(
  "/assets/:id/farm-approval",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.APPROVE,
  }),
  businessController.approveFarmAssetRequest,
);

router.patch(
  "/assets/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.updateAsset,
);

router.delete(
  "/assets/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.ASSETS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.softDeleteAsset,
);

/**
 * USER ROLE UPDATES (BUSINESS OWNER ONLY)
 */
router.patch(
  "/users/:id/role",
  requireAuth,
  requireRole("business_owner"),
  businessController.updateUserRole,
);

router.post(
  "/invites",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.createInvite,
);

router.post(
  "/invites/accept",
  requireAuth,
  businessController.acceptInvite,
);

/**
 * STAFF MANAGEMENT (OWNER + STAFF)
 */
router.get(
  "/staff",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listStaffProfiles,
);

router.get(
  "/staff/capacity",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getStaffCapacity,
);

router.get(
  "/staff/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getStaffProfile,
);

router.get(
  "/staff/:id/compensation",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.PAYROLL,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.getStaffCompensation,
);

router.patch(
  "/staff/:id/compensation",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.PAYROLL,
    capability: PERMISSION_CAPABILITIES.MANAGE,
  }),
  businessController.upsertStaffCompensation,
);

router.post(
  "/staff/attendance/clock-in",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.clockInStaff,
);

router.post(
  "/staff/attendance/clock-out",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.clockOutStaff,
);

router.post(
  "/staff/attendance/:attendanceId/proof",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  upload.single("proof"),
  businessController.uploadStaffAttendanceProof,
);

router.get(
  "/staff/attendance",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listStaffAttendance,
);

/**
 * PRODUCTION PLANS (OWNER + STAFF)
 */
router.post(
  "/production/plans/assistant-turn",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.productionPlanAssistantTurnHandler,
);

router.post(
  "/production/plans/ai-draft",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.generateProductionPlanDraftHandler,
);

router.get(
  "/production/schedule-policy",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getProductionSchedulePolicy,
);

router.put(
  "/production/schedule-policy",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateProductionSchedulePolicy,
);

router.post(
  "/production/plans",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.createProductionPlan,
);

router.get(
  "/production/plans/crop-search",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.searchProductionAssistantCatalogHandler,
);

router.get(
  "/production/plans/crop-lifecycle",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.previewProductionAssistantCropLifecycleHandler,
);

router.get(
  "/production/plans",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listProductionPlans,
);

router.put(
  "/production/plans/:id/draft",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateProductionPlanDraft,
);

router.patch(
  "/production/plans/:id/status",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateProductionPlanStatus,
);

router.delete(
  "/production/plans/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.deleteProductionPlan,
);

router.get(
  "/production/calendar",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listProductionCalendar,
);

router.get(
  "/production/confidence/portfolio",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getProductionPortfolioConfidence,
);

router.get(
  "/production/plans/:planId/confidence",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getProductionPlanConfidence,
);

router.get(
  "/production/plans/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getProductionPlanDetail,
);

router.get(
  "/production/plans/:planId/units",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listProductionPlanUnits,
);

// WHY: Managers need explicit visibility into deviation governance alerts before accepting variance or replanning.
router.get(
  "/production/plans/:planId/deviation-alerts",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listProductionPlanDeviationAlerts,
);

// WHY: Variance acceptance resolves lock while preserving baseline schedule for audit-safe drift tracking.
router.post(
  "/production/plans/:planId/deviation-alerts/:alertId/accept-variance",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.acceptProductionPlanDeviationVariance,
);

// WHY: Re-plan endpoint allows managers to manually adjust locked unit schedules before automation resumes.
router.post(
  "/production/plans/:planId/deviation-alerts/:alertId/replan-unit",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.replanProductionPlanDeviationUnit,
);

router.patch(
  "/production/plans/:id/preorder",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateProductionPlanPreorder,
);

router.post(
  "/production/plans/:planId/preorder/reserve",
  requireAuth,
  requireAnyRole([
    "customer",
    "business_owner",
  ]),
  businessController.reserveProductionPlanPreorder,
);

router.get(
  "/preorder/reservations",
  requireAuth,
  requireAnyRole([
    "business_owner",
  ]),
  businessController.listPreorderReservations,
);

router.post(
  "/preorder/reservations/:id/release",
  requireAuth,
  requireAnyRole([
    "customer",
    "business_owner",
  ]),
  businessController.releasePreorderReservation,
);

router.post(
  "/preorder/reservations/:id/confirm",
  requireAuth,
  requireAnyRole([
    "customer",
    "business_owner",
  ]),
  businessController.confirmPreorderReservation,
);

router.post(
  "/preorder/reservations/reconcile-expired",
  requireAuth,
  requireAnyRole([
    "business_owner",
  ]),
  businessController.reconcileExpiredPreorderReservationsHandler,
);

router.patch(
  "/production/tasks/:id/status",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateProductionTaskStatus,
);

router.put(
  "/production/tasks/:taskId/assign",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.assignProductionTaskStaffProfiles,
);

router.post(
  "/production/tasks/progress/batch",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.logProductionTaskProgressBatch,
);

router.post(
  "/production/tasks/:taskId/progress",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  parseTaskProgressProofUploads,
  businessController.logProductionTaskProgress,
);

router.post(
  "/production/task-progress/:id/approve",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.approveTaskProgress,
);

router.post(
  "/production/task-progress/:id/reject",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.rejectTaskProgress,
);

router.post(
  "/production/tasks/:id/approve",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.approveProductionTask,
);

router.post(
  "/production/tasks/:id/reject",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.rejectProductionTask,
);

router.post(
  "/production/outputs",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.createProductionOutput,
);

router.get(
  "/production/outputs",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listProductionOutputs,
);

/**
 * TENANT VERIFICATION (ESTATE-ONLY)
 */
router.get(
  "/tenant/applications",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.listTenantApplications,
);

router.get(
  "/tenant/applications/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getTenantApplicationDetail,
);

router.post(
  "/tenant/applications/:id/verify-contact",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.VERIFY,
  }),
  businessController.verifyTenantContact,
);

router.post(
  "/tenant/applications/:id/approve-agreement",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.APPROVE,
  }),
  businessController.approveAgreement,
);

router.post(
  "/tenant/applications/:id/agreement",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.APPROVE,
  }),
  businessController.setAgreementText,
);

router.get(
  "/tenant/estate",
  requireAuth,
  requireAnyRole(["tenant"]),
  businessController.getTenantEstate,
);

router.post(
  "/tenant/contact-document",
  requireAuth,
  requireAnyRole(["tenant"]),
  upload.single("document"),
  businessController.uploadTenantContactDocument,
);

router.post(
  "/tenant/verify",
  requireAuth,
  requireAnyRole(["tenant"]),
  businessController.submitTenantVerification,
);

router.get(
  "/tenant/application",
  requireAuth,
  requireAnyRole(["tenant"]),
  businessController.getTenantApplication,
);

router.get(
  "/tenant/summary",
  requireAuth,
  requireAnyRole(["tenant"]),
  businessController.getTenantSummary,
);

router.get(
  "/tenant/payments",
  requireAuth,
  requireAnyRole(["tenant"]),
  businessController.getTenantPayments,
);

router.get(
  "/tenant/:tenantId/payments",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.PAYMENTS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getBusinessTenantPayments,
);

router.patch(
  "/tenant/application",
  requireAuth,
  requireAnyRole(["tenant"]),
  businessController.updateTenantApplication,
);

router.get(
  "/users/lookup",
  requireAuth,
  requireRole("business_owner"),
  businessController.lookupUser,
);

/**
 * ANALYTICS
 */
router.get(
  "/analytics/summary",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.REPORTS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getAnalyticsSummary,
);

router.get(
  "/analytics/events",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.REPORTS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getAnalyticsEvents,
);

router.get(
  "/analytics/estate/:estateAssetId",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.REPORTS,
    capability: PERMISSION_CAPABILITIES.VIEW,
  }),
  businessController.getEstateAnalytics,
);

/**
 * APPROVAL
 */
router.post(
  "/tenant/applications/:id/approve",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.APPROVE,
  }),
  businessController.approveTenantApplication,
);

/**
 * PAYMENT TOGGLE
 */
router.post(
  "/tenant/applications/:id/toggle-payment",
  requireAuth,
  requireRole("business_owner"),
  businessController.togglePaymentStatus,
);

/**
 * VERIFY CONTACT
 */
router.post(
  "/tenants/:tenantId/verify-contact",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.VERIFY,
  }),
  businessController.verifyContact,
);

/**
 * APPROVE TENANT
 */
router.post(
  "/tenants/:tenantId/approve",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  requirePermission({
    module: PERMISSION_MODULES.TENANTS,
    capability: PERMISSION_CAPABILITIES.APPROVE,
  }),
  businessController.approveTenantApplication,
);

/**
 * CREATE PAYMENT INTENT
 */
router.post(
  "/tenants/:tenantId/payment-intent",
  requireAuth,
  requireRole("tenant"),
  businessController.createPaymentIntent,
);

/**
 * DEV-ONLY PAY TOGGLE
 */
router.post(
  "/dev/payments/:paymentId/mark-succeeded",
  requireAuth,
  requireRole("business_owner"),
  businessController.devMarkPaymentSucceeded,
);

/**
 * TENANT APPLICATIONS
 */
router.get(
  "/tenants",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getTenants,
);

module.exports = router;
