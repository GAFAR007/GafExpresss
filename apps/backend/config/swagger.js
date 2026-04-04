/**
 * config/swagger.js
 * -----------------
 * WHAT:
 * - Configures Swagger/OpenAPI documentation for the entire API
 * - Generates the spec that powers the interactive /docs page
 *
 * WHY:
 * - Provides live, professional API docs for developers and testers
 *
 * FIXED FOR YOUR STRUCTURE:
 * - Route files are in 'routes/' subfolder (e.g., routes/product.public.routes.js)
 * - Controller files are in 'controllers/' subfolder
 * - config/swagger.js is in 'config/' subfolder
 * - Uses '../routes/*.js' to correctly scan the routes folder
 */

const path = require('path');
const swaggerJsdoc = require('swagger-jsdoc');

const options = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'GafExpress API',
      version: '1.0.0',
      description:
        'Production-grade E-Commerce API with JWT auth, roles, products, orders, and admin features.',
    },
    servers: [
      { url: 'http://localhost:4000', description: 'Local development' },
    ],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
        },
      },
    },
    security: [{ bearerAuth: [] }],
  },

  // FIX: Scan the actual subfolders where your files are
  apis: [
    path.join(__dirname, '../routes/*.js'), // Scans routes/product.public.routes.js, routes/auth.routes.js, etc.
    path.join(__dirname, '../routes/**/*.js'), // ✅ IMPORTANT – catches nested route files if any
    path.join(__dirname, '../controllers/*.js'), // Scans controllers/admin.controller.js, etc.
  ],
};

const swaggerSpec = swaggerJsdoc(options);

module.exports = swaggerSpec;
