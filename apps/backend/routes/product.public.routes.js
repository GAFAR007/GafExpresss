/**
 * routes/product.public.routes.js
 * -------------------------------
 * WHAT:
 * - Public endpoints for browsing products
 *
 * WHY:
 * - Customers don't need auth to view products
 */

const express = require('express');
const productPublicController = require('../controllers/product.public.controller');

const router = express.Router();

/**
 * GET /products
 * Public: List active products only
 */
router.get('/', productPublicController.getActiveProducts);

module.exports = router;