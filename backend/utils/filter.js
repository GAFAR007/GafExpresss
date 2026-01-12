/**
 * utils/filter.js
 * ---------------
 * WHAT:
 * - Reusable filtering logic for admin list endpoints
 *
 * WHY:
 * - Keeps filtering consistent across users, orders, products
 * - Prevents arbitrary field filtering (security)
 * - Zero duplication
 * - Easy to add new filterable fields later
 */

const debug = require("./debug");

/**
 * Build a safe MongoDB filter object from query params
 *
 * Supported filters:
 * - Exact match: ?field=value
 * - Boolean: ?isActive=true|false
 * - Enum/status: ?status=pending
 * - Role: ?role=customer
 *
 * @param {Object} query - req.query
 * @param {Object} allowedFilters - Map of allowed fields → type/validation
 *                                 Supported types: 'string', 'boolean', 'enum'
 * @returns {Object} MongoDB query filter
 *
 * Example usage in controller:
 *   const filter = getFilter(req.query, {
 *     role: { type: 'enum', values: ['admin', 'staff', 'customer'] },
 *     isActive: { type: 'boolean' },
 *     status: { type: 'enum', values: ['pending', 'paid', 'shipped', 'delivered', 'cancelled'] },
 *   });
 */
function getFilter(query, allowedFilters) {
  debug("UTILS: getFilter - entry", {
    query,
    allowedFilters: Object.keys(allowedFilters),
  });

  const filter = {};

  for (const [field, config] of Object.entries(
    allowedFilters
  )) {
    const rawValue = query[field];

    // Skip if not provided
    if (rawValue === undefined || rawValue === "") {
      continue;
    }

    let parsedValue;

    switch (config.type) {
      case "string":
        parsedValue = String(rawValue).trim();
        if (parsedValue !== "") {
          filter[field] = parsedValue;
        }
        break;

      case "boolean":
        if (rawValue === "true") {
          parsedValue = true;
        } else if (rawValue === "false") {
          parsedValue = false;
        } else {
          debug(
            `UTILS: getFilter - invalid boolean for ${field}:`,
            rawValue
          );
          continue; // skip invalid
        }
        filter[field] = parsedValue;
        break;

      case "enum":
        if (
          Array.isArray(config.values) &&
          config.values.includes(rawValue)
        ) {
          filter[field] = rawValue;
        } else {
          debug(
            `UTILS: getFilter - invalid enum value for ${field}:`,
            rawValue
          );
          // Optionally throw or ignore — ignoring is safer for UX
        }
        break;

      default:
        debug(
          `UTILS: getFilter - unknown type for ${field}:`,
          config.type
        );
    }

    if (parsedValue !== undefined) {
      debug(
        `UTILS: getFilter - applied filter ${field}=`,
        parsedValue
      );
    }
  }

  debug("UTILS: getFilter - result", filter);
  return filter;
}

module.exports = {
  getFilter,
};
