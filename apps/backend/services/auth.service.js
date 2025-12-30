/**
 * services/auth.service.js
 * ------------------------
 * Authentication service (business logic layer).
 *
 * WHAT:
 * - Handles authentication-related logic
 * - Called by controllers
 *
 * WHY:
 * - Keeps controllers thin
 * - Makes logic reusable and testable
 * - Matches professional backend architecture
 *
 * IMPORTANT:
 * - NO database logic here (yet)
 * - NO JWT logic here (yet)
 * - NO password hashing here (yet)
 */

const debug = require('../utils/debug');

/**
 * --------------------------------------------------
 * REGISTER USER (PLACEHOLDER)
 * --------------------------------------------------
 */
async function registerUser({ name, email, password }) {
  debug('AuthService.registerUser called');

  debug(`Received name: ${name}`);
  debug(`Received email: ${email}`);
  debug(`Received password length: ${password?.length}`);

  /**
   * TEMP RESPONSE
   * -------------
   * This confirms:
   * - Controller → Service wiring works
   * - Data flow is correct
   */
  return {
    success: true,
    message: 'Register logic reached (service placeholder)',
    data: {
      name,
      email,
    },
  };
}

/**
 * --------------------------------------------------
 * EXPORT SERVICE METHODS
 * --------------------------------------------------
 */
module.exports = {
  registerUser,
};
