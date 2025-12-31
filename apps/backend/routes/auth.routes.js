/**
 * routes/auth.routes.js
 * ---------------------
 * WHAT:
 * - Defines authentication-related routes
 *
 * HOW:
 * - Maps HTTP endpoints to controller functions
 *
 * WHY:
 * - Keeps routing logic centralized
 * - Makes routes easy to discover and extend
 */

const express = require('express');
const debug = require('../utils/debug');
const authController = require('../controllers/auth.controller');
// ✅ Import the authentication middleware
const { requireAuth } = require('../middlewares/auth.middleware');

const router = express.Router();

debug('Auth routes initialized');

/**
 * Register a new user
 * POST /auth/register
 */
router.post('/register', authController.register);

/**
 * Login existing user
 * POST /auth/login
 */
router.post('/login', authController.login);

/**
 * Get current authenticated user
 * GET /auth/me
 * Protected route - requires valid JWT
 */
router.get('/me', requireAuth, (req, res) => {
  debug('Protected /me route accessed for user:', req.user.sub);

  res.json({
    message: 'Protected route accessed',
    user: req.user, // Will contain { sub: userId, role, iat, exp }
  });
});

module.exports = router;