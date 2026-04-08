/**
 * apps/backend/utils/orderStatus.js
 * --------------------------------
 * WHAT THIS FILE IS:
 * - The SINGLE place that defines "order status rules"
 *
 * WHY THIS FILE EXISTS:
 * - So we don't spread rules across 5 different files
 * - So the backend ALWAYS blocks invalid status changes
 *
 * HOW IT WORKS (SIMPLE):
 * - Each status can move ONLY to certain next statuses
 * - Example:
 *   pending -> paid OR cancelled
 *   paid -> shipped OR cancelled
 *   shipped -> delivered
 *   delivered -> (nothing)
 *   cancelled -> (nothing)
 */

const debug = require('./debug');

// ✅ All statuses in one place (matches your Order schema enum)
const ORDER_STATUSES = ['pending', 'paid', 'shipped', 'delivered', 'cancelled'];

/**
 * ✅ Allowed transitions
 *
 * Think of this like a "train map":
 * From each station (status),
 * what are the stations you are allowed to go next?
 */
const ORDER_STATUS_TRANSITIONS = {
  pending: ['paid', 'cancelled'],
  paid: ['shipped', 'cancelled'],
  shipped: ['delivered'],
  delivered: [],
  cancelled: [],
};

/**
 * canTransition(current, next)
 *
 * WHAT:
 * - Returns true/false depending on allowed transitions map
 *
 * WHY:
 * - Used by services to block invalid updates
 */
function canTransition(currentStatus, nextStatus) {
  // Safety: unknown status means NOT allowed
  if (!ORDER_STATUS_TRANSITIONS[currentStatus]) return false;

  return ORDER_STATUS_TRANSITIONS[currentStatus].includes(nextStatus);
}

/**
 * assertTransition(current, next)
 *
 * WHAT:
 * - Throws a clean error if transition is not allowed
 *
 * WHY:
 * - Keeps service code clean:
 *   "just call assertTransition and continue"
 */
function assertTransition(currentStatus, nextStatus) {
  debug('ORDER STATUS RULES: checking transition', {
    from: currentStatus,
    to: nextStatus,
  });

  // Safety: block unknown statuses
  if (!ORDER_STATUSES.includes(nextStatus)) {
    throw new Error(`Invalid status: "${nextStatus}"`);
  }

  // Block invalid move
  if (!canTransition(currentStatus, nextStatus)) {
    throw new Error(
      `Invalid status transition: "${currentStatus}" -> "${nextStatus}"`
    );
  }

  debug('ORDER STATUS RULES: transition allowed ✅', {
    from: currentStatus,
    to: nextStatus,
  });
}

module.exports = {
  ORDER_STATUSES,
  ORDER_STATUS_TRANSITIONS,
  canTransition,
  assertTransition,
};
