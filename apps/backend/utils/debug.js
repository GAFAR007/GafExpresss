/**
 * utils/debug.js
 * ---------------
 * Central debug logger.
 *
 * WHAT:
 * - Provides a simple debug logging function
 *
 * WHY:
 * - Keeps debug output consistent
 * - Can be disabled in production later
 */

module.exports = function debug(message) {
  if (process.env.NODE_ENV !== 'production') {
    console.log(`DEBUG: ${message}`);
  }
};
