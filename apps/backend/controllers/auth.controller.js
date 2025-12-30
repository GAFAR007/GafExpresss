/**
 * controllers/auth.controller.js
 * ------------------------------
 * Authentication HTTP controller.
 *
 * WHAT:
 * - Handles incoming HTTP requests
 * - Passes data to AuthService
 * - Returns responses
 *
 * WHY:
 * - Controllers should not contain business logic
 */

const debug = require('../utils/debug');
const authService = require('../services/auth.service');

/**
 * --------------------------------------------------
 * REGISTER USER ENDPOINT
 * --------------------------------------------------
 */
async function register(req, res) {
  debug('POST /auth/register hit');

  const { name, email, password } = req.body;

  debug('Passing data to AuthService');

  // ✅ CALL SERVICE
  const result = await authService.registerUser({
    name,
    email,
    password,
  });

  // ✅ RETURN SERVICE RESULT (NOT A PLACEHOLDER)
  return res.json(result);
}

module.exports = {
  register,
};
