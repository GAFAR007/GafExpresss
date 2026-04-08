/**
 * backend/scripts/preorder-reconcile-worker.test.js
 * -------------------------------------------------
 * WHAT:
 * - Unit-level tests for preorder reconciler worker scheduler wiring.
 *
 * WHY:
 * - Confirms env-gated startup behavior and safe timer lifecycle.
 *
 * HOW:
 * - Calls worker start/stop/tick directly with controlled env values.
 * - Avoids Mongo dependency by validating disconnected-safe behavior.
 */

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  startPreorderReconcileWorker,
  stopPreorderReconcileWorker,
  runPreorderReconcileWorkerTick,
} = require("../services/preorder_reservation_reconciler.worker");

const ENV_KEYS = [
  "NODE_ENV",
  "PREORDER_RECONCILE_WORKER_ENABLED",
  "PREORDER_RECONCILE_WORKER_INTERVAL_MS",
  "PREORDER_RECONCILE_WORKER_LIMIT",
];

let envSnapshot = {};

function captureEnvSnapshot() {
  envSnapshot = {};
  ENV_KEYS.forEach((key) => {
    envSnapshot[key] = process.env[key];
  });
}

function restoreEnvSnapshot() {
  ENV_KEYS.forEach((key) => {
    const value = envSnapshot[key];
    if (value == null) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  });
}

test.before(() => {
  captureEnvSnapshot();
});

test.after(() => {
  stopPreorderReconcileWorker();
  restoreEnvSnapshot();
});

test.beforeEach(() => {
  stopPreorderReconcileWorker();
  restoreEnvSnapshot();
});

test("worker stays disabled without explicit toggle in non-production", () => {
  process.env.NODE_ENV = "development";
  delete process.env.PREORDER_RECONCILE_WORKER_ENABLED;

  const state = startPreorderReconcileWorker();

  assert.equal(state.enabled, false);
});

test("worker starts when explicitly enabled and reuses running instance", () => {
  process.env.NODE_ENV = "development";
  process.env.PREORDER_RECONCILE_WORKER_ENABLED = "true";
  process.env.PREORDER_RECONCILE_WORKER_INTERVAL_MS = "7000";
  process.env.PREORDER_RECONCILE_WORKER_LIMIT = "33";

  const firstStart = startPreorderReconcileWorker();
  assert.equal(firstStart.enabled, true);
  assert.equal(firstStart.alreadyRunning, false);
  assert.equal(firstStart.intervalMs, 7000);
  assert.equal(firstStart.limit, 33);

  const secondStart = startPreorderReconcileWorker();
  assert.equal(secondStart.enabled, true);
  assert.equal(secondStart.alreadyRunning, true);
  assert.equal(secondStart.intervalMs, 7000);
  assert.equal(secondStart.limit, 33);

  assert.equal(stopPreorderReconcileWorker(), true);
  assert.equal(stopPreorderReconcileWorker(), false);
});

test("tick is safe while mongo is disconnected", async () => {
  process.env.NODE_ENV = "development";
  process.env.PREORDER_RECONCILE_WORKER_ENABLED = "true";

  await assert.doesNotReject(
    async () => {
      await runPreorderReconcileWorkerTick();
    },
  );
});

