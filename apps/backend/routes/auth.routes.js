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
const multer = require('multer');
const authController = require('../controllers/auth.controller');
// ✅ Import the authentication middleware
const { requireAuth } = require('../middlewares/auth.middleware');
const { requireRole } = require('../middlewares/requireRole.middleware');
const router = express.Router();

debug('Auth routes initialized');

// WHY: Store uploads in memory for direct Cloudinary streaming.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
});

/**
 * Register a new user
 * POST /auth/register
 */

/**
 * @swagger
 * tags:
 *   name: Auth
 *   description: Authentication & user identity
 */

/**
 * @swagger
 * /auth/register:
 *   post:
 *     summary: Register a new user
 *     tags: [Auth]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [email, password]
 *             properties:
 *               firstName:
 *                 type: string
 *                 example: John
 *               lastName:
 *                 type: string
 *                 example: Doe
 *               email:
 *                 type: string
 *                 example: user@test.com
 *               password:
 *                 type: string
 *                 example: password123
 *               confirmPassword:
 *                 type: string
 *                 example: password123
 *               role:
 *                 type: string
 *                 example: customer
 *     responses:
 *       201:
 *         description: User registered successfully
 *       400:
 *         description: Validation error
 *       409:
 *         description: Email already exists
 */

router.post('/register', authController.register);

/**
 * Login existing user
 * POST /auth/login
 */

/**
 * @swagger
 * /auth/login:
 *   post:
 *     summary: Login a user
 *     tags: [Auth]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [email, password]
 *             properties:
 *               email:
 *                 type: string
 *                 example: user@test.com
 *               password:
 *                 type: string
 *                 example: password123
 *     responses:
 *       200:
 *         description: Login successful
 *       401:
 *         description: Invalid credentials
 */
router.post('/login', authController.login);

/**
 * Public helper: list active login accounts for a role.
 * GET /auth/login-accounts/:role
 */
router.get('/login-accounts/:role', authController.loginAccounts);

/**
 * Request password reset code
 * POST /auth/password-reset/request
 * Public route - no auth required
 */
router.post('/password-reset/request', authController.requestPasswordReset);

/**
 * Confirm password reset code + set new password
 * POST /auth/password-reset/confirm
 * Public route - no auth required
 */
router.post('/password-reset/confirm', authController.confirmPasswordReset);

/**
 * Get current authenticated user
 * GET /auth/me
 * Protected route - requires valid JWT
 */

/**
 * @swagger
 * /auth/me:
 *   get:
 *     summary: Get current authenticated user
 *     tags: [Auth]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Authenticated user info
 *       401:
 *         description: Unauthorized
 */
router.get('/me', requireAuth, (req, res) => {
  debug('Protected /me route accessed for user:', req.user.sub);

  res.json({
    message: 'Protected route accessed',
    user: req.user,
  });
});

/**
 * Get current user profile (full profile from DB)
 * GET /auth/profile
 * Protected route - requires valid JWT
 */
router.get('/profile', requireAuth, authController.getProfile);

/**
 * Update current user profile
 * PATCH /auth/profile
 * Protected route - requires valid JWT
 */
router.patch('/profile', requireAuth, authController.updateProfile);

/**
 * Request email verification code
 * POST /auth/email-verification/request
 * Protected route - requires valid JWT
 */
router.post(
  '/email-verification/request',
  requireAuth,
  authController.requestEmailVerification,
);

/**
 * Confirm email verification code
 * POST /auth/email-verification/confirm
 * Protected route - requires valid JWT
 */
router.post(
  '/email-verification/confirm',
  requireAuth,
  authController.confirmEmailVerification,
);

/**
 * Request phone verification OTP
 * POST /auth/phone-verification/request
 * Protected route - requires valid JWT
 */
router.post(
  '/phone-verification/request',
  requireAuth,
  authController.requestPhoneVerification,
);

/**
 * Confirm phone verification OTP
 * POST /auth/phone-verification/confirm
 * Protected route - requires valid JWT
 */
router.post(
  '/phone-verification/confirm',
  requireAuth,
  authController.confirmPhoneVerification,
);

/**
 * Verify NIN (simulated)
 * POST /auth/nin/verify
 * Protected route - requires valid JWT
 */
router.post('/nin/verify', requireAuth, authController.verifyNin);

/**
 * Verify business registration (Dojah)
 * POST /auth/business/verify
 * Protected route - requires valid JWT
 */
router.post('/business/verify', requireAuth, authController.verifyBusiness);

/**
 * Verify address (Google Address Validation)
 * POST /auth/address/verify
 * Protected route - requires valid JWT
 */
router.post('/address/verify', requireAuth, authController.verifyAddress);

/**
 * Address autocomplete (Google Places)
 * GET /auth/address/autocomplete?query=...
 * Protected route - requires valid JWT
 */
router.get(
  '/address/autocomplete',
  requireAuth,
  authController.addressAutocomplete,
);

/**
 * Address place details (Google Places)
 * GET /auth/address/place-details?placeId=...
 * Protected route - requires valid JWT
 */
router.get(
  '/address/place-details',
  requireAuth,
  authController.addressPlaceDetails,
);

/**
 * Upload profile image
 * POST /auth/profile-image
 * Protected route - requires valid JWT
 */
router.post(
  '/profile-image',
  requireAuth,
  upload.single('image'),
  authController.uploadProfileImage,
);

/**
 * Admin-only test route
 * GET /auth/admin-test
 */

/**
 * @swagger
 * /auth/admin-test:
 *   get:
 *     summary: Admin-only access test
 *     tags: [Auth]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Admin access granted
 *       403:
 *         description: Forbidden (not admin)
 */
router.get('/admin-test', requireAuth, requireRole('admin'), (req, res) => {
  debug('Admin route accessed by:', req.user.sub);

  res.json({
    message: 'Admin access granted',
    user: req.user,
  });
});

module.exports = router;
