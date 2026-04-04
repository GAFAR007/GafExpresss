/**
 * apps/backend/services/admin.order.service.js
 * --------------------------------------------
 * WHAT:
 * - Business logic for admin order operations
 *
 * WHY:
 * - Centralizes admin access to orders
 *
 * HOW:
 * - Uses pagination helpers + status transitions in a transaction
 */

const Order = require('../models/Order');
const debug = require('../utils/debug');

const mongoose = require('mongoose');
const { getPagination } = require('../utils/pagination');
const { assertTransition } = require('../utils/orderStatus');
const { adjustOrderStock } = require('../utils/stock'); // ← New import
const { writeAuditLog } = require('../utils/audit');

/**
 * Get all orders (admin view)
 */
/**
 * Get all orders for admin (paginated + searchable)
 *
 * WHAT:
 * - Returns ALL orders in the system (admin view)
 *
 * SUPPORTS:
 * - pagination (?page=&limit=)
 * - status filter (?status=pending)
 * - full-text search (?q=paid)
 *
 * WHY:
 * - Admins manage ALL orders
 * - Must scale safely for large datasets
 */

async function getAllOrders(query) {
  debug('ADMIN ORDER SERVICE: getAllOrders - entry', query);

  /**
   * ------------------------------------
   * STEP 1: PAGINATION
   * ------------------------------------
   * Uses shared helper to:
   * - apply defaults
   * - prevent abuse
   * - calculate skip
   */
  const { page, limit, skip } = getPagination(query);

  /**
   * ------------------------------------
   * STEP 2: BASE FILTER
   * ------------------------------------
   * Admin can see ALL orders
   * Optional filters are added below
   */
  const filter = {};

  // Optional status filter
  if (query.status) {
    filter.status = query.status;
  }

  /**
   * ------------------------------------
   * STEP 3: FULL-TEXT SEARCH (?q=)
   * ------------------------------------
   * Allows searching order status text
   *
   * Examples:
   * - ?q=pending
   * - ?q=paid
   */
  const search = query.q?.trim();
  if (search) {
    filter.$text = { $search: search };
  }

  debug('ADMIN ORDER SERVICE: filter built', filter);

  /**
   * ------------------------------------
   * STEP 4: QUERY DATABASE
   * ------------------------------------
   * Fetch orders + count in parallel
   */
  const [orders, total] = await Promise.all([
    Order.find(filter)
      .populate('user', 'name email role')
      .populate('items.product', 'name imageUrl price')
      .select({ __v: 0 })
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),

    Order.countDocuments(filter),
  ]);

  debug('ADMIN ORDER SERVICE: orders fetched', {
    total,
    returned: orders.length,
    page,
    limit,
  });

  /**
   * ------------------------------------
   * STEP 5: RETURN STRUCTURED RESULT
   * ------------------------------------
   * Controller will format response
   */
  return {
    orders,
    total,
    page,
    limit,
  };
}

/**
 * Update order status (admin only)
 *
 * STAGE 7.1 CORE FUNCTION
 *
 * WHAT:
 * - Admin updates order lifecycle
 *
 * HOW:
 * - Uses centralized status rules (assertTransition)
 *
 * WHY:
 * - Prevents invalid transitions
 * - Guarantees backend integrity
 */
/**
 * Update order status (admin only)
 *
 * @param {string} id     - Order ID
 * @param {string} status - New status
 * @param {Object} actor  - Actor metadata for audit
 * @returns {Object}      - Fully populated updated order
 */
async function updateOrderStatus(id, status, actor) {
  debug('ADMIN ORDER SERVICE: updateOrderStatus', {
    id,
    status,
    actorId: actor?.id,
    actorRole: actor?.role,
  });

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    // 1. Load order
    const order = await Order.findById(id).session(session);
    if (!order) {
      throw new Error('Order not found');
    }

    const oldStatus = order.status;

    // 2. Validate transition using centralized rules
    assertTransition(oldStatus, status);

    // 3. Apply stock adjustments (only when needed)
    if (oldStatus === 'pending' && status === 'paid') {
      await adjustOrderStock(order, 'decrease', session, {
        actorId: actor?.id,
        actorRole: actor?.role,
        businessId: null,
        reason: 'order_paid',
        source: 'admin',
      });
    } else if (oldStatus === 'paid' && status === 'cancelled') {
      // WHY: Only restore stock if it was previously decreased on payment success.
      await adjustOrderStock(order, 'restore', session, {
        actorId: actor?.id,
        actorRole: actor?.role,
        businessId: null,
        reason: 'order_cancelled',
        source: 'admin',
      });
    }
    // WHY: Pending cancel does not touch stock because we don't reserve on order creation.
    // No stock change for shipped → delivered or terminal states.

    // 4. Update status
    order.status = status;
    // WHY: Keep an immutable trail of order status changes.
    order.statusHistory.push({
      status,
      changedAt: new Date(),
      changedBy: actor?.id,
      changedByRole: actor?.role,
      note: 'admin_status_update',
    });
    await order.save({ session });

    // 5. Commit everything atomically
    await session.commitTransaction();

    debug('Order status updated successfully', {
      orderId: id,
      from: oldStatus,
      to: status,
    });

    // WHY: Persist audit logs for sensitive order changes.
    await writeAuditLog({
      businessId: null,
      actorId: actor?.id,
      actorRole: actor?.role || 'admin',
      action: 'order_status_update',
      entityType: 'order',
      entityId: order._id,
      message: `Order status changed from ${oldStatus} to ${status}`,
      changes: { from: oldStatus, to: status },
    });

    // 6. Return fresh, populated order for frontend
    return await Order.findById(id)
      .populate('user', 'name email')
      .populate('items.product', 'name imageUrl')
      .select({ __v: 0 });
  } catch (error) {
    await session.abortTransaction();
    debug('Order status update failed - rollback', error.message);
    throw error; // Let controller return proper 400
  } finally {
    session.endSession();
  }
}

module.exports = {
  getAllOrders,
  updateOrderStatus,
};
