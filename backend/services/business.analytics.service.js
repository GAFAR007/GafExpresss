/**
 * services/business.analytics.service.js
 * --------------------------------------
 * WHAT:
 * - Aggregates analytics summaries for a business dashboard.
 *
 * WHY:
 * - Keeps UI "dumb" while providing trusted totals from the backend.
 * - Enables consistent metrics across web, iOS, and Android.
 *
 * HOW:
 * - Queries Products + Orders with business scope filters.
 * - Returns totals, status breakdowns, and revenue aggregates.
 */

const Product = require('../models/Product');
const Order = require('../models/Order');
const BusinessAnalyticsEvent = require('../models/BusinessAnalyticsEvent');
const debug = require('../utils/debug');

// WHY: Keep a single source of truth for order statuses in analytics.
const ORDER_STATUSES = ['pending', 'paid', 'shipped', 'delivered', 'cancelled'];
// WHY: Revenue should only count paid-like states.
const REVENUE_STATUSES = ['paid', 'shipped', 'delivered'];

async function getAnalyticsSummary({ businessId }) {
  debug('BUSINESS ANALYTICS SERVICE: summary - entry', { businessId });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const [
    totalProducts,
    activeProducts,
    totalStockResult,
    totalOrders,
    ordersByStatusResult,
    revenueResult,
  ] = await Promise.all([
    Product.countDocuments({ businessId }),
    Product.countDocuments({ businessId, isActive: true }),
    Product.aggregate([
      { $match: { businessId, isActive: true } },
      {
        $group: {
          _id: null,
          totalStock: { $sum: '$stock' },
        },
      },
    ]),
    Order.countDocuments({ businessIds: businessId }),
    Order.aggregate([
      { $match: { businessIds: businessId } },
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
        },
      },
    ]),
    Order.aggregate([
      { $match: { businessIds: businessId, status: { $in: REVENUE_STATUSES } } },
      {
        $group: {
          _id: null,
          revenueTotal: { $sum: '$totalPrice' },
        },
      },
    ]),
  ]);

  const totalStock = totalStockResult?.[0]?.totalStock ?? 0;
  const revenueTotal = revenueResult?.[0]?.revenueTotal ?? 0;

  const ordersByStatus = ORDER_STATUSES.reduce((acc, status) => {
    acc[status] = 0;
    return acc;
  }, {});

  for (const row of ordersByStatusResult) {
    if (row?._id) {
      ordersByStatus[row._id] = row.count;
    }
  }

  debug('BUSINESS ANALYTICS SERVICE: summary - computed', {
    totalProducts,
    activeProducts,
    totalStock,
    totalOrders,
    revenueTotal,
  });

  return {
    totalProducts,
    activeProducts,
    totalStock,
    totalOrders,
    ordersByStatus,
    revenueTotal,
    revenueStatuses: REVENUE_STATUSES,
  };
}

async function getAnalyticsEvents({ businessId, days = 30, eventType }) {
  debug('BUSINESS ANALYTICS SERVICE: events - entry', {
    businessId,
    days,
    eventType,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const safeDays = Number.isFinite(Number(days)) ? Number(days) : 30;
  const boundedDays = Math.max(1, Math.min(safeDays, 90));
  const since = new Date();
  since.setDate(since.getDate() - boundedDays);

  const match = {
    businessId,
    createdAt: { $gte: since },
  };

  if (eventType) {
    match.eventType = eventType;
  }

  const events = await BusinessAnalyticsEvent.aggregate([
    { $match: match },
    {
      $group: {
        _id: {
          day: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } },
          eventType: '$eventType',
        },
        count: { $sum: 1 },
      },
    },
    { $sort: { '_id.day': 1 } },
    {
      $project: {
        _id: 0,
        date: '$_id.day',
        eventType: '$_id.eventType',
        count: 1,
      },
    },
  ]);

  const totals = events.reduce((acc, row) => {
    acc[row.eventType] = (acc[row.eventType] || 0) + row.count;
    return acc;
  }, {});

  debug('BUSINESS ANALYTICS SERVICE: events - computed', {
    days: boundedDays,
    count: events.length,
  });

  return {
    days: boundedDays,
    since: since.toISOString(),
    events,
    totals,
  };
}

module.exports = {
  getAnalyticsSummary,
  getAnalyticsEvents,
};
