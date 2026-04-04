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

/**
 * @swagger
 * /products/{id}/preorder-availability:
 *   get:
 *     summary: Retrieve pre-order availability summary by product id
 *     description: >
 *       Public endpoint — no authentication required.
 *       Returns pre-order cap, reserved, and remaining values.
 *     tags: [Products]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *     responses:
 *       200:
 *         description: Pre-order availability fetched successfully
 *       404:
 *         description: Product not found
 *       500:
 *         description: Internal server error
 */
router.get(
  '/:id/preorder-availability',
  productPublicController.getPreorderAvailabilitySummary
);

/**
 * @swagger
 * /products/{id}:
 *   get:
 *     summary: Retrieve a single active product by id
 *     description: >
 *       Public endpoint — no authentication required.
 *       Returns only active products.
 *     tags: [Products]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *     responses:
 *       200:
 *         description: Product fetched successfully
 *       404:
 *         description: Product not found
 *       500:
 *         description: Internal server error
 */
router.get('/:id', productPublicController.getActiveProductById);

module.exports = router;
