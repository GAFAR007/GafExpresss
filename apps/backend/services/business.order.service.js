/**
 * apps/backend/services/business.order.service.js
 * -----------------------------------------------
 * WHAT:
 * - Business-scoped order operations for owners and staff.
 *
 * WHY:
 * - Business users should only see and update orders tied to their products.
 *
 * HOW:
 * - Filters orders by businessId scope and records audit trails.
 */

const mongoose = require('mongoose');
const Order = require('../models/Order');
const { getPagination } = require('../utils/pagination');
const { assertTransition } = require('../utils/orderStatus');
const { adjustOrderStock } = require('../utils/stock');
const { writeAuditLog } = require('../utils/audit');
const { writeAnalyticsEvent } = require('../utils/analytics');
const debug = require('../utils/debug');

function normalizeDispatchPayload(dispatch = {}) {
  return {
    carrierName: (dispatch.carrierName || '').toString().trim(),
    trackingReference: (dispatch.trackingReference || '')
      .toString()
      .trim(),
    dispatchNote: (dispatch.dispatchNote || '').toString().trim(),
    estimatedDeliveryDate: (dispatch.estimatedDeliveryDate || '')
      .toString()
      .trim(),
  };
}

function parseDispatchDate(value, fieldLabel) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`${fieldLabel} must be a valid date`);
  }
  return parsed;
}

async function getBusinessOrders({ businessId, userId, query }) {
  debug('BUSINESS ORDER SERVICE: getBusinessOrders - entry', {
    businessId,
    userId,
    query,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const { page, limit, skip } = getPagination(query);

  const filter = {
    $or: [{ businessIds: businessId }, { user: userId }],
  };

  const search = query?.q?.trim();
  if (search) {
    filter.$text = { $search: search };
  }

  if (query?.status) {
    filter.status = query.status;
  }

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

  return {
    orders,
    total,
    page,
    limit,
  };
}

async function updateOrderStatus({
  businessId,
  orderId,
  status,
  actor,
  dispatch,
}) {
  debug('BUSINESS ORDER SERVICE: updateOrderStatus - entry', {
    businessId,
    orderId,
    status,
    actorId: actor?.id,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const order = await Order.findOne({
      _id: orderId,
      businessIds: businessId,
    }).session(session);

    if (!order) {
      throw new Error('Order not found for this business');
    }

    const oldStatus = order.status;
    assertTransition(oldStatus, status);

    if (oldStatus === 'pending' && status === 'paid') {
      await adjustOrderStock(order, 'decrease', session, {
        actorId: actor?.id,
        actorRole: actor?.role,
        businessId,
        reason: 'order_paid',
        source: 'business',
      });
    } else if (oldStatus === 'paid' && status === 'cancelled') {
      await adjustOrderStock(order, 'restore', session, {
        actorId: actor?.id,
        actorRole: actor?.role,
        businessId,
        reason: 'order_cancelled',
        source: 'business',
      });
    }

    const normalizedDispatch = normalizeDispatchPayload(dispatch);

    if (oldStatus === 'paid' && status === 'shipped') {
      if (!normalizedDispatch.carrierName) {
        throw new Error('Carrier name is required before marking as shipped');
      }
      if (!normalizedDispatch.trackingReference) {
        throw new Error('Tracking reference is required before marking as shipped');
      }
      if (!normalizedDispatch.estimatedDeliveryDate) {
        throw new Error(
          'Estimated delivery date is required before marking as shipped'
        );
      }

      order.fulfillment = {
        ...(order.fulfillment?.toObject?.() || order.fulfillment || {}),
        carrierName: normalizedDispatch.carrierName,
        trackingReference: normalizedDispatch.trackingReference,
        dispatchNote: normalizedDispatch.dispatchNote,
        estimatedDeliveryDate: parseDispatchDate(
          normalizedDispatch.estimatedDeliveryDate,
          'Estimated delivery date'
        ),
        shippedAt: new Date(),
        deliveredAt: order.fulfillment?.deliveredAt || null,
      };
    } else if (oldStatus === 'shipped' && status === 'delivered') {
      order.fulfillment = {
        ...(order.fulfillment?.toObject?.() || order.fulfillment || {}),
        deliveredAt: new Date(),
      };
    }

    order.status = status;
    order.statusHistory.push({
      status,
      changedAt: new Date(),
      changedBy: actor?.id,
      changedByRole: actor?.role,
      note:
        status === 'shipped'
          ? 'business_status_update_with_dispatch'
          : 'business_status_update',
    });
    await order.save({ session });

    await session.commitTransaction();

    await writeAuditLog({
      businessId,
      actorId: actor?.id,
      actorRole: actor?.role,
      action: 'order_status_update',
      entityType: 'order',
      entityId: order._id,
      message: `Order status changed from ${oldStatus} to ${status}`,
      changes: { from: oldStatus, to: status },
    });

    // WHY: Persist status changes for analytics timelines.
    await writeAnalyticsEvent({
      businessId,
      actorId: actor?.id,
      actorRole: actor?.role,
      eventType: 'order_status_updated',
      entityType: 'order',
      entityId: order._id,
      metadata: {
        from: oldStatus,
        to: status,
        ...(status === 'shipped'
          ? {
              carrierName: order.fulfillment?.carrierName || '',
              trackingReference: order.fulfillment?.trackingReference || '',
              estimatedDeliveryDate:
                order.fulfillment?.estimatedDeliveryDate || null,
            }
          : {}),
      },
    });

    return await Order.findById(orderId)
      .populate('user', 'name email')
      .populate('items.product', 'name imageUrl')
      .select({ __v: 0 });
  } catch (error) {
    await session.abortTransaction();
    debug('BUSINESS ORDER SERVICE: updateOrderStatus failed', error.message);
    throw error;
  } finally {
    session.endSession();
  }
}

module.exports = {
  getBusinessOrders,
  updateOrderStatus,
};
