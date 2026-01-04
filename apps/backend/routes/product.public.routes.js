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
 * tags:
 *   - name: Products
 *     description: Public product browsing and listing
 */

/**
 * @swagger
 * /products:
 *   get:
 *     summary: Retrieve a paginated list of active products
 *     description: >
 *       Public endpoint — no authentication required.
 *       Returns only active (isActive: true) products.
 *       Supports pagination and sorting.
 *     tags: [Products]
 *     parameters:
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           minimum: 1
 *           default: 1
 *         description: Page number for pagination
 *         example: 1
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           minimum: 1
 *           maximum: 100
 *           default: 10
 *         description: Number of products per page (max 100)
 *         example: 10
 *       - in: query
 *         name: sort
 *         schema:
 *           type: string
 *           example: price:desc
 *         description: >
 *           Sort format: `field:direction`
 *           Allowed fields: `price`, `name`, `createdAt`
 *           Direction: `asc` or `desc`
 *           Examples: `price:desc`, `name:asc`, `createdAt:desc`
 *     responses:
 *       200:
 *         description: Products fetched successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 message:
 *                   type: string
 *                   example: Products fetched successfully
 *                 pagination:
 *                   type: object
 *                   properties:
 *                     page:
 *                       type: integer
 *                       example: 1
 *                     limit:
 *                       type: integer
 *                       example: 10
 *                     total:
 *                       type: integer
 *                       example: 47
 *                     totalPages:
 *                       type: integer
 *                       example: 5
 *                     hasNext:
 *                       type: boolean
 *                       example: true
 *                     hasPrev:
 *                       type: boolean
 *                       example: false
 *                 count:
 *                   type: integer
 *                   description: Number of products returned in this response
 *                   example: 10
 *                 products:
 *                   type: array
 *                   items:
 *                     type: object
 *                     properties:
 *                       _id:
 *                         type: string
 *                         example: 64f8a123b456c7890d123456
 *                       name:
 *                         type: string
 *                         example: Premium Hoodie
 *                       description:
 *                         type: string
 *                         example: Comfortable cotton hoodie
 *                       price:
 *                         type: number
 *                         example: 4999
 *                       stock:
 *                         type: integer
 *                         example: 25
 *                       imageUrl:
 *                         type: string
 *                         example: https://example.com/hoodie.jpg
 *                       isActive:
 *                         type: boolean
 *                         example: true
 *                       createdAt:
 *                         type: string
 *                         format: date-time
 *       500:
 *         description: Internal server error
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 error:
 *                   type: string
 *                   example: Failed to fetch products
 */

router.get('/', productPublicController.getActiveProducts);

module.exports = router;
