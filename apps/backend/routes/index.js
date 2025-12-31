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
 */

const debug = require('../utils/debug');
const authRoutes = require('./auth.routes');
const adminRoutes = require('./admin.routes');
const { requireRole } = require('../middlewares/requireRole.middleware.js');


module.exports = (app) => {
  debug('🧭 Routes module loaded');

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
   */
  debug('Registering /auth routes');
  app.use('/auth', authRoutes);

    /**
   * Admin routes
   * /admin/*
   */
  debug('Registering admin routes');
  app.use('/admin', adminRoutes);
};
