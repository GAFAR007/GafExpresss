/**
 * middlewares/auth.middleware.js
 * ------------------------------
 * WHAT:
 * - Verifies JWT tokens on protected routes
 *
 * HOW:
 * - Reads Authorization header
 * - Extracts Bearer token
 * - Verifies token using JWT_SECRET
 * - Attaches decoded payload to req.user
 *
 * WHY:
 * - Prevents unauthenticated access
 * - Centralizes auth logic
 * - Keeps routes clean and secure
 * - Enables role-based access later
 */

const jwt = require('jsonwebtoken');
const debug = require('../utils/debug');

/**
 * Middleware: requireAuth
 *
 * Blocks request unless a valid JWT is provided.
 */
function requireAuth(req, res, next) {
  debug('AUTH MIDDLEWARE START');

  // 1️⃣ Read Authorization header
  const authHeader = req.headers.authorization;
  debug('Authorization header received:', authHeader || 'none');

  if (!authHeader) {
    debug('No Authorization header provided');
    return res.status(401).json({
      error: 'Authorization header missing',
    });
  }

  // 2️⃣ Expect format: "Bearer <token>"
  if (!authHeader.startsWith('Bearer ')) {
    debug('Invalid Authorization format (missing Bearer)');
    return res.status(401).json({
      error: 'Invalid authorization format: must start with Bearer',
    });
  }

  const token = authHeader.split(' ')[1];
  debug('JWT token extracted successfully');

  try {
    // 3️⃣ Verify token with secret
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    debug('JWT verified successfully', {
      userId: decoded.sub,
      role: decoded.role,
      iat: decoded.iat,
      exp: decoded.exp,
    });

    // 4️⃣ Attach decoded payload to request
    req.user = decoded; // { sub: userId, role, iat, exp }

    debug('AUTH MIDDLEWARE SUCCESS - proceeding to route');
    next();
  } catch (err) {
    debug('JWT verification failed:', err.name, err.message);

    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'Token expired',
      });
    }

    if (err.name === 'JsonWebTokenError') {
      return res.status(401).json({
        error: 'Invalid token',
      });
    }

    // Fallback for any other error (e.g., malformed token)
    return res.status(401).json({
      error: 'Invalid or malformed token',
    });
  }
}

module.exports = {
  requireAuth,
};