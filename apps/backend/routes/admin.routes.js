const express = require('express');
const debug = require('../utils/debug');
const { requireAuth } = require('../middlewares/auth.middleware');
const { requireRole } = require('../middlewares/requireRole.middleware');

const router = express.Router();

debug('Admin routes initialized');

/**
 * GET /admin/health
 * Admin-only test route
 */
router.get(
  '/health',
  requireAuth,
  requireRole('admin'),
  (req, res) => {
    debug('Admin health route accessed by user:', req.user.sub);

    res.json({
      status: 'ok',
      message: 'Admin access confirmed',
      admin: req.user,
    });
  }
);

module.exports = router;
