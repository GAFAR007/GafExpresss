
/**
 * config/jwt.js
 * -------------
 * WHAT:
 * - Centralised JWT (JSON Web Token) signing logic
 * - Responsible for creating authentication tokens after login/register
 *
 * HOW:
 * - Uses jsonwebtoken to sign a payload containing:
 *   - sub → the user ID (standard JWT subject)
 *   - role → the user role (admin / staff / customer)
 * - Uses a secret stored in process.env.JWT_SECRET
 * - Sets a fixed expiry time (1 day)
 *
 * WHY:
 * - Keeps token logic in one place (easy to rotate secrets or expiry)
 * - Prevents duplication of JWT logic across services/controllers
 * - Makes auth behaviour predictable and secure
 */

const jwt = require('jsonwebtoken');
const debug = require('../utils/debug');

/**
 * Sign a JWT for an authenticated user
 *
 * @param {Object} user
 * @param {string} user.id   - MongoDB user ID
 * @param {string} user.role - User role for authorization
 *
 * @returns {string} JWT token
 */
function signToken(user) {
  // 🔍 Debug check to ensure secret is loaded from .env
  // This prevents silent failures in production
  debug('JWT_SECRET exists:', !!process.env.JWT_SECRET);

  // 🧾 Build JWT payload
  // sub = subject (JWT standard)
  // role = used later for role-based access control
  const payload = {
    sub: user.id,
    role: user.role,
  };

  // 🔐 Sign the token using the secret key
  // - Secret must NEVER be hardcoded
  // - Expiry is intentionally short-lived (1 day)
  const token = jwt.sign(payload, process.env.JWT_SECRET, {
    expiresIn: '1d',
  });

  // ✅ Token successfully generated
  return token;
}

// 📦 Explicit exports (prevents import mistakes)
module.exports = {
  signToken,
};
