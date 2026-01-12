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
 * @swagger
 * /products:
 *   get:
 *     summary: Retrieve a paginated list of active products
 *     description: >
 *       Public endpoint — no authentication required.
 *       Returns only active (isActive: true) products.
 *       Supports pagination, sorting, and full-text search.
 *     tags: [Products]
 *     parameters:
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           minimum: 1
 *           default: 1
 *         description: Page number for pagination
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           minimum: 1
 *           maximum: 100
 *           default: 10
 *         description: Number of products per page (max 100)
 *       - in: query
 *         name: sort
 *         schema:
 *           type: string
 *           example: price:desc
 *         description: Sort format `field:direction`
 *       - in: query
 *         name: q
 *         schema:
 *           type: string
 *           example: hoodie
 *         description: Full-text search across product name and description
 *     responses:
 *       200:
 *         description: Products fetched successfully
 *       400:
 *         description: Invalid query parameters
 *       404:
 *         description: No products found
 *       500:
 *         description: Internal server error
 */

router.get('/', productPublicController.getActiveProducts);

module.exports = router;
