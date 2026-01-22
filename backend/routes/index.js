/**
 * routes/index.js
 * ----------------
 * Central route registry.
 *
 * WHAT:
 * - Receives Express app instance
 * - Registers route groups
 *
 * WHY:
 * - Keeps server.js clean
 * - Scales cleanly as app grows
 *
 * HOW:
 * - Mounts route modules under their base paths
 * 
 * 
 * 
 *  npm run dev

 */

const debug = require('../utils/debug');
const authRoutes = require('./auth.routes');
const adminRoutes = require('./admin.routes');
const businessRoutes = require('./business.routes');


// Public product routes (no auth needed)
const productPublicRoutes = require('./product.public.routes');

// User order routes (authenticated)
const orderRoutes = require('./order.routes');
// Payment init routes (authenticated)
const paymentRoutes = require('./payments.routes');

module.exports = (app) => {
  debug('Routes module loaded');

  /**
   * HEALTH CHECK
   */
  app.get('/health', (req, res) => {
    res.json({
      status: 'ok',
      message: 'Backend is alive',
    });
  });

  /**
   * AUTH ROUTES
   * /auth/*
   */
  debug('Registering /auth routes');
  app.use('/auth', authRoutes);

  /**
   * ADMIN ROUTES
   * /admin/*
   */
  debug('Registering admin routes');
  app.use('/admin', adminRoutes);

  /**
   * BUSINESS ROUTES
   * /business/*
   */
  debug('Registering business routes');
  app.use('/business', businessRoutes);

  /**
   * PUBLIC PRODUCT ROUTES
   * /products (no auth needed)
   */
  debug('Registering public product routes');
  app.use('/products', productPublicRoutes);

  /**
   * USER ORDER ROUTES
   * /orders/* (authenticated - protected in order.routes.js)
   */
  debug('Registering order routes');
  app.use('/orders', orderRoutes);

  /**
   * PAYMENT ROUTES
   * /payments/* (authenticated)
   */
  debug('Registering payment routes');
  // WHY: Paystack init must be protected and mapped under one namespace.
  app.use('/payments', paymentRoutes);
};
