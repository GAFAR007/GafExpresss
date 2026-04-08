/**
 * routes/purchase_request.routes.js
 * ---------------------------------
 * WHAT:
 * - Routes for temporary manual-direct purchase requests.
 *
 * WHY:
 * - Buyers need to start request-to-buy flows before Paystack is re-enabled.
 * - Sellers need invoice + proof review actions inside the same request domain.
 *
 * HOW:
 * - Buyer and seller actions share one route module with role-based guards.
 */

const express = require("express");
const { requireAuth } = require("../middlewares/auth.middleware");
const { requireAnyRole } = require("../middlewares/requireRole.middleware");
const purchaseRequestController = require("../controllers/purchase_request.controller");

const router = express.Router();

router.post(
  "/",
  requireAuth,
  requireAnyRole(["customer", "tenant", "business_owner"]),
  purchaseRequestController.createPurchaseRequest,
);

router.post(
  "/batch",
  requireAuth,
  requireAnyRole(["customer", "tenant", "business_owner"]),
  purchaseRequestController.createBatchPurchaseRequests,
);

router.post(
  "/:id/proof",
  requireAuth,
  requireAnyRole(["customer", "tenant", "business_owner"]),
  purchaseRequestController.submitPaymentProof,
);

router.post(
  "/:id/invoice",
  requireAuth,
  requireAnyRole(["business_owner", "staff"]),
  purchaseRequestController.sendInvoice,
);

router.post(
  "/:id/attend",
  requireAuth,
  requireAnyRole(["business_owner", "staff"]),
  purchaseRequestController.attendPurchaseRequestChat,
);

router.post(
  "/:id/exit",
  requireAuth,
  requireAnyRole(["business_owner", "staff"]),
  purchaseRequestController.exitPurchaseRequestChat,
);

router.patch(
  "/:id/ai-control",
  requireAuth,
  requireAnyRole(["business_owner", "staff"]),
  purchaseRequestController.updatePurchaseRequestAiControl,
);

router.post(
  "/:id/proof-review",
  requireAuth,
  requireAnyRole(["business_owner", "staff"]),
  purchaseRequestController.reviewPaymentProof,
);

router.patch(
  "/:id/cancel",
  requireAuth,
  purchaseRequestController.cancelPurchaseRequest,
);

module.exports = router;
