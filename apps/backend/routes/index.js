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

const authController = require('../controllers/auth.controller');

module.exports = (app) => {
  console.log('🧭 Routes module loaded');

  /**
   * TEMP TEST ROUTE
   * ----------------
   * This exists ONLY to verify routing works.
   */
  app.get('/health', (req, res) => {
    res.json({
      status: 'ok',
      message: 'Backend is alive',
    });
  });

  /**
   * AUTH ROUTES
   * ----------------
   * POST /auth/register
   *
   * WHAT:
   * - Entry point for user registration
   *
   * WHY:
   * - Keeps auth logic isolated
   */
  app.post('/auth/register', authController.register);
};
