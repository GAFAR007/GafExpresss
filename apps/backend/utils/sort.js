/**
 * utils/sort.js
 * -------------
 * WHAT:
 * - Reusable sorting logic for all list endpoints
 *
 * WHY:
 * - Prevents code duplication
 * - Validates allowed fields (security)
 * - Consistent behavior across public + admin endpoints
 * - Easy to add new sortable fields later
 */

const debug = require('./debug');

/**
 * Parse and validate sort query
 *
 * Supported format: field:direction
 * Example: ?sort=price:desc
 *
 * @param {string} sortQuery - req.query.sort
 * @param {Array<string>} allowedFields - Fields this endpoint allows sorting by
 * @param {Object} defaultSort - Fallback if no/invalid sort provided
 * @returns {Object} MongoDB sort object, e.g. { price: -1 }
 */
function getSort(sortQuery, allowedFields, defaultSort = { createdAt: -1 }) {
  debug('UTILS: getSort - entry', { sortQuery, allowedFields });

  // If no sort provided, use default
  if (!sortQuery) {
    debug('UTILS: getSort - using default', defaultSort);
    return defaultSort;
  }

  // Split into field and direction
  const parts = sortQuery.trim().split(':');
  if (parts.length !== 2) {
    debug('UTILS: getSort - invalid format, using default');
    return defaultSort;
  }

  const [field, direction] = parts;

  // Validate field is allowed
  if (!allowedFields.includes(field)) {
    debug('UTILS: getSort - field not allowed', { field });
    return defaultSort;
  }

  // Validate direction
  const dir = direction.toLowerCase() === 'asc' ? 1 : -1;

  const sortObject = { [field]: dir };

  debug('UTILS: getSort - result', sortObject);

  return sortObject;
}

module.exports = {
  getSort,
};