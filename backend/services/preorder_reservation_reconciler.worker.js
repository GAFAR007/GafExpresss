/**
 * backend/services/preorder_reservation_reconciler.worker.js
 * ----------------------------------------------------------
 * WHAT:
 * - Runs a background scheduler for expired pre-order reservation reconciliation.
 *
 * WHY:
 * - Ensures expired holds are released automatically without manual script calls.
 * - Keeps Product.preorderReservedQuantity aligned over time.
 *
 * HOW:
 * - Uses an interval worker (cron-style loop) with env-based enablement.
 * - Skips runs when Mongo is disconnected.
 * - Prevents overlapping executions with an in-memory lock.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const {
  reconcileExpiredPreorderReservations,
  PREORDER_RECONCILE_DEFAULT_LIMIT,
} = require("./preorder_reservation_reconciler.service");

const PREORDER_RECONCILE_WORKER_DEFAULT_INTERVAL_MS =
  60 * 1000;
const PREORDER_RECONCILE_WORKER_MIN_INTERVAL_MS =
  5 * 1000;

let workerTimer = null;
let isWorkerRunning = false;
let workerConfigCache = null;

function parseBooleanEnv(value, fallback = false) {
  if (value == null) return fallback;
  const normalized = value
    .toString()
    .trim()
    .toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }
  return fallback;
}

function parsePositiveIntegerEnv({
  value,
  fallback,
  minimum = 1,
}) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed < minimum
  ) {
    return fallback;
  }
  return Math.floor(parsed);
}

function resolveWorkerConfig({
  intervalMs,
  limit,
} = {}) {
  const resolvedIntervalMs =
    parsePositiveIntegerEnv({
      value:
        intervalMs ??
        process.env
          .PREORDER_RECONCILE_WORKER_INTERVAL_MS,
      fallback:
        PREORDER_RECONCILE_WORKER_DEFAULT_INTERVAL_MS,
      minimum:
        PREORDER_RECONCILE_WORKER_MIN_INTERVAL_MS,
    });
  const resolvedLimit =
    parsePositiveIntegerEnv({
      value:
        limit ??
        process.env
          .PREORDER_RECONCILE_WORKER_LIMIT,
      fallback:
        PREORDER_RECONCILE_DEFAULT_LIMIT,
      minimum: 1,
    });

  return {
    intervalMs: resolvedIntervalMs,
    limit: resolvedLimit,
  };
}

function isWorkerEnabled() {
  if (process.env.NODE_ENV === "test") {
    return false;
  }

  const explicitToggle =
    process.env
      .PREORDER_RECONCILE_WORKER_ENABLED;
  if (explicitToggle != null) {
    return parseBooleanEnv(
      explicitToggle,
      false,
    );
  }

  // WHY: Default-on in production keeps reconciliation automated after deploy.
  return process.env.NODE_ENV === "production";
}

async function runPreorderReconcileWorkerTick() {
  if (!workerConfigCache) {
    workerConfigCache =
      resolveWorkerConfig();
  }
  if (isWorkerRunning) {
    debug(
      "PREORDER RECONCILE WORKER: skipped tick (already running)",
      {
        intervalMs:
          workerConfigCache.intervalMs,
      },
    );
    return;
  }
  if (mongoose.connection.readyState !== 1) {
    debug(
      "PREORDER RECONCILE WORKER: skipped tick (mongo disconnected)",
      {
        readyState:
          mongoose.connection.readyState,
      },
    );
    return;
  }

  isWorkerRunning = true;
  const startedAt = new Date();
  try {
    debug(
      "PREORDER RECONCILE WORKER: tick start",
      {
        startedAt:
          startedAt.toISOString(),
        limit: workerConfigCache.limit,
      },
    );
    const summary =
      await reconcileExpiredPreorderReservations(
        {
          now: startedAt,
          limit: workerConfigCache.limit,
        },
      );
    debug(
      "PREORDER RECONCILE WORKER: tick success",
      {
        scannedCount:
          summary.scannedCount,
        expiredCount:
          summary.expiredCount,
        skippedCount:
          summary.skippedCount,
        errorCount:
          summary.errorCount,
      },
    );
  } catch (error) {
    debug(
      "PREORDER RECONCILE WORKER: tick failure",
      {
        reason: error.message,
        next: "Inspect reconciler errors and retry on next interval",
      },
    );
  } finally {
    isWorkerRunning = false;
  }
}

function startPreorderReconcileWorker({
  intervalMs,
  limit,
} = {}) {
  if (workerTimer) {
    return {
      enabled: true,
      alreadyRunning: true,
      ...workerConfigCache,
    };
  }

  const enabled = isWorkerEnabled();
  if (!enabled) {
    debug(
      "PREORDER RECONCILE WORKER: disabled",
      {
        nodeEnv:
          process.env.NODE_ENV || "unknown",
        configured:
          process.env
            .PREORDER_RECONCILE_WORKER_ENABLED ??
          null,
      },
    );
    return {
      enabled: false,
    };
  }

  workerConfigCache =
    resolveWorkerConfig({
      intervalMs,
      limit,
    });
  debug(
    "PREORDER RECONCILE WORKER: started",
    workerConfigCache,
  );

  // WHY: Execute once immediately so stale holds are not blocked until next interval.
  void runPreorderReconcileWorkerTick();
  workerTimer = setInterval(() => {
    void runPreorderReconcileWorkerTick();
  }, workerConfigCache.intervalMs);
  if (
    typeof workerTimer.unref ===
    "function"
  ) {
    workerTimer.unref();
  }

  return {
    enabled: true,
    alreadyRunning: false,
    ...workerConfigCache,
  };
}

function stopPreorderReconcileWorker() {
  if (!workerTimer) {
    return false;
  }
  clearInterval(workerTimer);
  workerTimer = null;
  isWorkerRunning = false;
  workerConfigCache = null;
  debug(
    "PREORDER RECONCILE WORKER: stopped",
  );
  return true;
}

module.exports = {
  PREORDER_RECONCILE_WORKER_DEFAULT_INTERVAL_MS,
  PREORDER_RECONCILE_WORKER_MIN_INTERVAL_MS,
  startPreorderReconcileWorker,
  stopPreorderReconcileWorker,
  runPreorderReconcileWorkerTick,
};

