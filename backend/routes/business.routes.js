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
const businessController = require("../controllers/business.controller");

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
router.post(
  "/products",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.createProduct,
);

router.get(
  "/products",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getAllProducts,
);

router.get(
  "/products/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getProductById,
);

router.patch(
  "/products/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateProduct,
);

router.patch(
  "/products/:id/restore",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.restoreProduct,
);

router.post(
  "/products/:id/image",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
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
  businessController.deleteProductImage,
);

router.delete(
  "/products/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
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
  businessController.createAsset,
);

router.get(
  "/assets",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getAssets,
);

router.patch(
  "/assets/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.updateAsset,
);

router.delete(
  "/assets/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
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
 * TENANT VERIFICATION (ESTATE-ONLY)
 */
router.get(
  "/tenant/applications",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.listTenantApplications,
);

router.get(
  "/tenant/applications/:id",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getTenantApplicationDetail,
);

router.get(
  "/tenant/estate",
  requireAuth,
  requireAnyRole(["tenant"]),
  businessController.getTenantEstate,
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
  businessController.getAnalyticsSummary,
);

router.get(
  "/analytics/events",
  requireAuth,
  requireAnyRole([
    "business_owner",
    "staff",
  ]),
  businessController.getAnalyticsEvents,
);

module.exports = router;
