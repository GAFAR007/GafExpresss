/**
 * routes/index.js
 * ----------------
 * Central route registry.
 *
 * WHAT:
 * - Receives Express app instance
 * - Registers route groups
 *
 * WHY:
 * - Keeps server.js clean
 * - Scales cleanly as app grows
 *
 * HOW:
 * - Mounts route modules under their base paths
 */

const debug = require("../utils/debug");
const connectDB = require("../config/db");
const { getDatabaseStatus, isDatabaseReady } = connectDB;
const authRoutes = require("./auth.routes");
const adminRoutes = require("./admin.routes");
const businessRoutes = require("./business.routes");
const chatRoutes = require("./chat.routes");
const purchaseRequestRoutes = require("./purchase_request.routes");
const tenantRequestPublicRoutes = require("./tenant_request.public.routes");

// Public product routes (no auth needed)
const productPublicRoutes = require("./product.public.routes");

// User order routes (authenticated)
const orderRoutes = require("./order.routes");
// Payment init routes (authenticated)
const paymentRoutes = require("./payments.routes");

const ROUTE_GROUPS = [
  ["/auth", authRoutes],
  ["/admin", adminRoutes],
  ["/business", businessRoutes],
  ["/chat", chatRoutes],
  ["/purchase-requests", purchaseRequestRoutes],
  ["/tenant-request-links", tenantRequestPublicRoutes],
  ["/products", productPublicRoutes],
  ["/orders", orderRoutes],
  ["/payments", paymentRoutes],
];

module.exports = (app) => {
  debug("Routes module loaded", {
    groups: ROUTE_GROUPS.map(([basePath]) => basePath),
  });

  /**
   * LIVENESS CHECK
   */
  app.get("/health", (req, res) => {
    const databaseStatus = getDatabaseStatus();

    res.status(200).json({
      status: databaseStatus.isReady ? "ok" : "degraded",
      message: databaseStatus.isReady
        ? "Backend is alive"
        : "Backend is alive but database is unavailable",
      database: {
        isReady: databaseStatus.isReady,
        readyState: databaseStatus.readyState,
        state: databaseStatus.state,
      },
    });
  });

  /**
   * READINESS CHECK
   */
  app.get("/ready", (req, res) => {
    const databaseStatus = getDatabaseStatus();

    res.status(databaseStatus.isReady ? 200 : 503).json({
      status: databaseStatus.isReady ? "ok" : "degraded",
      message: databaseStatus.isReady
        ? "Backend is ready"
        : "Backend is alive but database is unavailable",
      database: {
        isReady: databaseStatus.isReady,
        readyState: databaseStatus.readyState,
        state: databaseStatus.state,
      },
    });
  });

  // WHY: Keep route boot logs compact; the group summary above already shows the map.
  ROUTE_GROUPS.forEach(([basePath, router]) => {
    app.use(basePath, router);
  });
};
