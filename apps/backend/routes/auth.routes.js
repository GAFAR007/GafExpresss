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

module.exports = router;
