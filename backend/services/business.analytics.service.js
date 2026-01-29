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

const Product = require("../models/Product");
const Order = require("../models/Order");
const BusinessAnalyticsEvent = require("../models/BusinessAnalyticsEvent");
const BusinessAsset = require("../models/BusinessAsset");
const BusinessTenantApplication = require("../models/BusinessTenantApplication");
const Payment = require("../models/Payment");
const debug = require("../utils/debug");

// WHY: Keep a single source of truth for order statuses in analytics.
const ORDER_STATUSES = [
  "pending",
  "paid",
  "shipped",
  "delivered",
  "cancelled",
];
// WHY: Revenue should only count paid-like states.
const REVENUE_STATUSES = [
  "paid",
  "shipped",
  "delivered",
];

async function getAnalyticsSummary({
  businessId,
}) {
  debug(
    "BUSINESS ANALYTICS SERVICE: summary - entry",
    { businessId },
  );

  if (!businessId) {
    throw new Error(
      "Business scope is required",
    );
  }

  const [
    totalProducts,
    activeProducts,
    totalStockResult,
    totalOrders,
    ordersByStatusResult,
    revenueResult,
  ] = await Promise.all([
    Product.countDocuments({
      businessId,
    }),
    Product.countDocuments({
      businessId,
      isActive: true,
    }),
    Product.aggregate([
      {
        $match: {
          businessId,
          isActive: true,
        },
      },
      {
        $group: {
          _id: null,
          totalStock: {
            $sum: "$stock",
          },
        },
      },
    ]),
    Order.countDocuments({
      businessIds: businessId,
    }),
    Order.aggregate([
      {
        $match: {
          businessIds: businessId,
        },
      },
      {
        $group: {
          _id: "$status",
          count: { $sum: 1 },
        },
      },
    ]),
    Order.aggregate([
      {
        $match: {
          businessIds: businessId,
          status: {
            $in: REVENUE_STATUSES,
          },
        },
      },
      {
        $group: {
          _id: null,
          revenueTotal: {
            $sum: "$totalPrice",
          },
        },
      },
    ]),
  ]);

  const totalStock =
    totalStockResult?.[0]?.totalStock ??
    0;
  const revenueTotal =
    revenueResult?.[0]?.revenueTotal ??
    0;

  const ordersByStatus =
    ORDER_STATUSES.reduce(
      (acc, status) => {
        acc[status] = 0;
        return acc;
      },
      {},
    );

  for (const row of ordersByStatusResult) {
    if (row?._id) {
      ordersByStatus[row._id] =
        row.count;
    }
  }

  debug(
    "BUSINESS ANALYTICS SERVICE: summary - computed",
    {
      totalProducts,
      activeProducts,
      totalStock,
      totalOrders,
      revenueTotal,
    },
  );

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

async function getAnalyticsEvents({
  businessId,
  days = 30,
  eventType,
}) {
  debug(
    "BUSINESS ANALYTICS SERVICE: events - entry",
    {
      businessId,
      days,
      eventType,
    },
  );

  if (!businessId) {
    throw new Error(
      "Business scope is required",
    );
  }

  const safeDays =
    Number.isFinite(Number(days)) ?
      Number(days)
    : 30;
  const boundedDays = Math.max(
    1,
    Math.min(safeDays, 90),
  );
  const since = new Date();
  since.setDate(
    since.getDate() - boundedDays,
  );

  const match = {
    businessId,
    createdAt: { $gte: since },
  };

  if (eventType) {
    match.eventType = eventType;
  }

  const events =
    await BusinessAnalyticsEvent.aggregate(
      [
        { $match: match },
        {
          $group: {
            _id: {
              day: {
                $dateToString: {
                  format: "%Y-%m-%d",
                  date: "$createdAt",
                },
              },
              eventType: "$eventType",
            },
            count: { $sum: 1 },
          },
        },
        { $sort: { "_id.day": 1 } },
        {
          $project: {
            _id: 0,
            date: "$_id.day",
            eventType: "$_id.eventType",
            count: 1,
          },
        },
      ],
    );

  const totals = events.reduce(
    (acc, row) => {
      acc[row.eventType] =
        (acc[row.eventType] || 0) +
        row.count;
      return acc;
    },
    {},
  );

  debug(
    "BUSINESS ANALYTICS SERVICE: events - computed",
    {
      days: boundedDays,
      count: events.length,
    },
  );

  return {
    days: boundedDays,
    since: since.toISOString(),
    events,
    totals,
  };
}

/**
 * getEstateAnalytics
 * ------------------
 * WHAT:
 * - Returns estate-level KPIs (tenants + rent collections) for owner/staff.
 *
 * WHY:
 * - Owners need a quick view of occupancy + collections per estate.
 *
 * HOW:
 * - Scope by businessId + estateAssetId.
 * - Summarise tenant applications + successful rent payments.
 */
async function getEstateAnalytics({
  businessId,
  estateAssetId,
}) {
  debug(
    "BUSINESS ANALYTICS SERVICE: estate - entry",
    {
      businessId,
      estateAssetId,
    },
  );

  if (!businessId || !estateAssetId) {
    throw new Error(
      "Business and estate are required",
    );
  }

  const estate =
    await BusinessAsset.findOne({
      _id: estateAssetId,
      businessId,
      assetType: "estate",
    }).lean();

  if (!estate) {
    throw new Error(
      "Estate not found for this business",
    );
  }

  const applications =
    await BusinessTenantApplication.find(
      {
        businessId,
        estateAssetId,
      },
    )
      .select(
        "status nextDueDate paidThroughDate rentAmount rentPeriod",
      )
      .lean();

  const today = new Date();
  const startOfYear = new Date(
    today.getFullYear(),
    0,
    1,
  );
  const startOfMonth = new Date(
    today.getFullYear(),
    today.getMonth(),
    1,
  );

  let activeTenants = 0;
  let approvedTenants = 0;
  let pendingTenants = 0;
  let dueSoon = 0;
  let overdue = 0;
  const appIds = [];

  applications.forEach((app) => {
    const status = (
      app.status || ""
    ).toLowerCase();
    appIds.push(app._id);

    if (status === "active") {
      activeTenants += 1;
    } else if (status === "approved") {
      approvedTenants += 1;
    } else {
      pendingTenants += 1;
    }

    if (
      status === "active" &&
      app.nextDueDate
    ) {
      const due = new Date(
        app.nextDueDate,
      );
      const diffDays = Math.floor(
        (due - today) /
          (1000 * 60 * 60 * 24),
      );
      if (diffDays < 0) {
        overdue += 1;
      } else if (diffDays <= 30) {
        dueSoon += 1;
      }
    }
  });

  const payments = await Payment.find({
    businessId,
    tenantApplication: { $in: appIds },
    purpose: "tenant_rent",
    status: "success",
  })
    .select("amount processedAt")
    .lean();

  let collectedAll = 0;
  let collectedYtd = 0;
  let collectedMonth = 0;

  payments.forEach((p) => {
    const ts =
      p.processedAt ?
        new Date(p.processedAt)
      : null;
    collectedAll += p.amount || 0;
    if (ts && ts >= startOfYear) {
      collectedYtd += p.amount || 0;
    }
    if (ts && ts >= startOfMonth) {
      collectedMonth += p.amount || 0;
    }
  });

  const potentialAnnualKobo =
    estate?.estate?.rentSummary
      ?.totalAnnual || 0;

  debug(
    "BUSINESS ANALYTICS SERVICE: estate - success",
    {
      estateAssetId,
      activeTenants,
      approvedTenants,
      pendingTenants,
      collectedMonth,
    },
  );

  return {
    estate: {
      id: estate._id,
      name: estate.name,
      totalUnits:
        estate.estate?.totalUnits || 0,
      potentialAnnualKobo,
    },
    tenants: {
      active: activeTenants,
      approved: approvedTenants,
      pending: pendingTenants,
      dueSoon,
      overdue,
    },
    collections: {
      monthKobo: collectedMonth,
      ytdKobo: collectedYtd,
      allTimeKobo: collectedAll,
    },
  };
}

module.exports = {
  getAnalyticsSummary,
  getAnalyticsEvents,
  getEstateAnalytics,
};
