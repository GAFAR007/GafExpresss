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
  requireRole("business_owner"),
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
  "/production/plans/ai-draft",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.generateProductionPlanDraftHandler,
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
  "/production/plans",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listProductionPlans,
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

router.patch(
  "/production/tasks/:id/status",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateProductionTaskStatus,
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
  businessController.verifyContact,
);

/**
 * APPROVE TENANT
 */
router.post(
  "/tenants/:tenantId/approve",
  requireAuth,
  requireRole("business_owner"),
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
