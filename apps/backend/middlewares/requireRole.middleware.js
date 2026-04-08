/**
 * middlewares/requireRole.middleware.js
 * ------------------------------------
 * WHAT:
 * - Restricts access to routes based on user role
 *
 * HOW:
 * - Reads req.user (set by requireAuth middleware)
 * - Compares against allowed roles
 *
 * WHY:
 * - Enforces authorization rules
 * - Prevents privilege escalation
 * - Keeps route logic clean
 */

const debug = require('../utils/debug');

/**
 * Middleware factory: requireRole
 *
 * @param {string} role - Required user role (e.g. 'admin')
 */
function requireRole(role) {
  return function (req, res, next) {
    debug('ROLE MIDDLEWARE START');

    if (!req.user) {
      debug('No user found on request');
      return res.status(401).json({
        error: 'Authentication required',
      });
    }

    debug('User role:', req.user.role);
    debug('Required role:', role);

    if (req.user.role !== role) {
      debug('Access denied: insufficient permissions');
      return res.status(403).json({
        error: 'Forbidden: insufficient permissions',
      });
    }

    debug('ROLE MIDDLEWARE SUCCESS');
    next();
  };
}

/**
 * Middleware factory: requireAnyRole
 *
 * @param {string[]} roles - Allowed roles
 */
function requireAnyRole(roles) {
  return function (req, res, next) {
    debug('ROLE MIDDLEWARE START');

    if (!req.user) {
      debug('No user found on request');
      return res.status(401).json({
        error: 'Authentication required',
      });
    }

    const allowed = Array.isArray(roles) ? roles : [];

    debug('User role:', req.user.role);
    debug('Allowed roles:', allowed);

    if (!allowed.includes(req.user.role)) {
      debug('Access denied: insufficient permissions');
      return res.status(403).json({
        error: 'Forbidden: insufficient permissions',
      });
    }

    debug('ROLE MIDDLEWARE SUCCESS');
    next();
  };
}

module.exports = {
  requireRole,
  requireAnyRole,
};
