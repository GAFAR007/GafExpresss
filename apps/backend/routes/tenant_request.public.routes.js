/**
 * routes/tenant_request.public.routes.js
 * --------------------------------------
 * WHAT:
 * - Public routes for tenant request links.
 *
 * WHY:
 * - Tenants need a direct, unauthenticated route to view and submit the
 *   request form that business owners share with them.
 *
 * HOW:
 * - GET /tenant-request-links/:token returns link context.
 * - POST /tenant-request-links/:token/submit accepts the public form.
 */

const express = require('express');
const multer = require('multer');
const businessTenantRequestController = require('../controllers/business_tenant_request.controller');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

router.get(
  '/:token',
  businessTenantRequestController.getTenantRequestLinkContext,
);

router.post(
  '/:token/submit',
  upload.single('document'),
  businessTenantRequestController.submitTenantRequest,
);

module.exports = router;
