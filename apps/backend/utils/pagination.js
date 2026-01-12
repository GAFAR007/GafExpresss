/**
 * utils/pagination.js
 * -------------------
 * WHAT:
 * - Central reusable pagination logic
 *
 * WHY:
 * - All list endpoints (products, orders, admin) behave the same
 * - Zero duplication
 * - Easy to change defaults or max limit in ONE place
 */

const debug = require('./debug');

/**
 * Extract and validate pagination from query params
 *
 * @param {Object} query - req.query
 * @returns {Object} { page, limit, skip }
 */
function getPagination(query) {
  debug('UTILS: getPagination - entry', query);

  // Parse values
  let page = parseInt(query.page, 10);
  let limit = parseInt(query.limit, 10);

  // Safe defaults + validation
  page = (isNaN(page) || page < 1) ? 1 : page;
  limit = (isNaN(limit) || limit < 1) ? 10 : Math.min(limit, 100); // Max 100

  const skip = (page - 1) * limit;

  debug('UTILS: getPagination - result', { page, limit, skip });

  return { page, limit, skip };
}

module.exports = {
  getPagination,
};