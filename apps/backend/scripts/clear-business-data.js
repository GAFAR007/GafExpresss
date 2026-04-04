/**
 * scripts/clear-business-data.js
 * ------------------------------
 * WHAT:
 * - Clears business-scoped catalog data and business history/log collections.
 *
 * WHY:
 * - Gives operators a repeatable reset path without hand-deleting collections.
 * - Keeps the destructive scope explicit and reviewable in code.
 *
 * HOW:
 * - Targets business-owned products plus business-scoped orders/payments/history.
 * - Runs as dry-run by default; pass --execute to apply deletes.
 */

require("dotenv").config();

const mongoose = require("mongoose");
const connectDB = require("../config/db");
const debug = require("../utils/debug");

const Product = require("../models/Product");
const AuditLog = require("../models/AuditLog");
const InventoryEvent = require("../models/InventoryEvent");
const BusinessAnalyticsEvent = require("../models/BusinessAnalyticsEvent");
const Order = require("../models/Order");
const Payment = require("../models/Payment");
const PreorderReservation = require("../models/PreorderReservation");
const ProductionPlan = require("../models/ProductionPlan");
const ProductionOutput = require("../models/ProductionOutput");

const args = process.argv.slice(2);
const shouldExecute = args.includes("--execute");
const includeUnownedProducts = args.includes(
  "--include-unowned-products",
);
const includeAllOrders = args.includes("--include-all-orders");

function buildOrQuery(filters) {
  const compactFilters = filters.filter(Boolean);
  if (compactFilters.length === 0) {
    return { _id: { $exists: false } };
  }
  if (compactFilters.length === 1) {
    return compactFilters[0];
  }
  return { $or: compactFilters };
}

async function collectQueries() {
  const productScopeQuery = includeUnownedProducts
    ? {}
    : {
        businessId: { $ne: null },
      };
  const orderScopeQuery = includeAllOrders
    ? {}
    : buildOrQuery([
        {
          "businessIds.0": { $exists: true },
        },
        {
          "items.businessId": { $ne: null },
        },
      ]);

  const [productIds, planIds, orderIds] = await Promise.all([
    Product.distinct("_id", productScopeQuery),
    ProductionPlan.distinct("_id", {
      businessId: { $ne: null },
    }),
    Order.distinct("_id", orderScopeQuery),
  ]);

  return {
    productIds,
    planIds,
    orderIds,
    queries: {
      products: productScopeQuery,
      inventoryEvents: buildOrQuery([
        {
          businessId: { $ne: null },
        },
        productIds.length
          ? {
              product: { $in: productIds },
            }
          : null,
        includeAllOrders && orderIds.length
          ? {
              orderId: { $in: orderIds },
            }
          : null,
      ]),
      auditLogs: buildOrQuery([
        {
          businessId: { $ne: null },
        },
        includeUnownedProducts && productIds.length
          ? {
              entityType: "product",
              entityId: { $in: productIds },
            }
          : null,
        includeAllOrders && orderIds.length
          ? {
              entityType: "order",
              entityId: { $in: orderIds },
            }
          : null,
      ]),
      analyticsEvents: buildOrQuery([
        {
          businessId: { $ne: null },
        },
        includeAllOrders && orderIds.length
          ? {
              entityType: "order",
              entityId: { $in: orderIds },
            }
          : null,
      ]),
      orders: orderScopeQuery,
      payments: buildOrQuery([
        {
          businessId: { $ne: null },
        },
        includeAllOrders
          ? {
              order: { $ne: null },
            }
          : null,
      ]),
      preorderReservations: {
        businessId: { $ne: null },
      },
      productionOutputs: buildOrQuery([
        productIds.length
          ? {
              productId: { $in: productIds },
            }
          : null,
        planIds.length
          ? {
              planId: { $in: planIds },
            }
          : null,
      ]),
    },
  };
}

async function countMatches(queries) {
  const [
    products,
    inventoryEvents,
    auditLogs,
    analyticsEvents,
    orders,
    payments,
    preorderReservations,
    productionOutputs,
  ] = await Promise.all([
    Product.countDocuments(queries.products),
    InventoryEvent.countDocuments(queries.inventoryEvents),
    AuditLog.countDocuments(queries.auditLogs),
    BusinessAnalyticsEvent.countDocuments(queries.analyticsEvents),
    Order.countDocuments(queries.orders),
    Payment.countDocuments(queries.payments),
    PreorderReservation.countDocuments(queries.preorderReservations),
    ProductionOutput.countDocuments(queries.productionOutputs),
  ]);

  return {
    products,
    inventoryEvents,
    auditLogs,
    analyticsEvents,
    orders,
    payments,
    preorderReservations,
    productionOutputs,
  };
}

async function deleteMatches(queries) {
  const [
    inventoryEvents,
    auditLogs,
    analyticsEvents,
    payments,
    orders,
    preorderReservations,
    productionOutputs,
    products,
  ] = await Promise.all([
    InventoryEvent.deleteMany(queries.inventoryEvents),
    AuditLog.deleteMany(queries.auditLogs),
    BusinessAnalyticsEvent.deleteMany(queries.analyticsEvents),
    Payment.deleteMany(queries.payments),
    Order.deleteMany(queries.orders),
    PreorderReservation.deleteMany(queries.preorderReservations),
    ProductionOutput.deleteMany(queries.productionOutputs),
    Product.deleteMany(queries.products),
  ]);

  return {
    products: products.deletedCount || 0,
    inventoryEvents: inventoryEvents.deletedCount || 0,
    auditLogs: auditLogs.deletedCount || 0,
    analyticsEvents: analyticsEvents.deletedCount || 0,
    orders: orders.deletedCount || 0,
    payments: payments.deletedCount || 0,
    preorderReservations: preorderReservations.deletedCount || 0,
    productionOutputs: productionOutputs.deletedCount || 0,
  };
}

async function run() {
  debug("CLEAR BUSINESS DATA: start", {
    execute: shouldExecute,
  });

  await connectDB();

  const { productIds, planIds, orderIds, queries } = await collectQueries();
  const counts = await countMatches(queries);

  console.log("Business data cleanup scope:", {
    execute: shouldExecute,
    includeUnownedProducts,
    includeAllOrders,
    productIds: productIds.length,
    planIds: planIds.length,
    orderIds: orderIds.length,
    counts,
  });

  if (!shouldExecute) {
    console.log(
      "Dry run only. Re-run with --execute to delete business products, history, and audit logs. Add --include-unowned-products to also wipe public/admin catalog products. Add --include-all-orders to wipe all user orders and order-linked records.",
    );
    return;
  }

  const deleted = await deleteMatches(queries);

  console.log("Business data cleanup complete:", {
    deleted,
  });
}

run()
  .catch((error) => {
    console.error("Business data cleanup failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await mongoose.disconnect();
    } catch (disconnectError) {
      debug("CLEAR BUSINESS DATA: disconnect failed", {
        error: disconnectError.message,
      });
    }
  });
