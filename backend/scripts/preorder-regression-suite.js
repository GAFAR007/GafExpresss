/**
 * backend/scripts/preorder-regression-suite.js
 * --------------------------------------------
 * WHAT:
 * - Runs the full preorder + payment regression suite for launch gating.
 *
 * WHY:
 * - Stage 6 requires one repeatable command to validate preorder flows before rollout.
 *
 * HOW:
 * - Spawns `node --test` against all preorder/payment linkage test files.
 * - Inherits stdio so CI or local operators can see exact failing tests.
 */

const { spawn } = require("node:child_process");
const path = require("node:path");

const TEST_FILES = [
  "scripts/preorder-reserve.test.js",
  "scripts/preorder-release.test.js",
  "scripts/preorder-confirm.test.js",
  "scripts/preorder-reconcile.test.js",
  "scripts/preorder-reconcile-worker.test.js",
  "scripts/preorder-order-payment-linkage.test.js",
  "scripts/preorder-availability.test.js",
  "scripts/preorder-monitoring.test.js",
];

function runSuite() {
  const startedAt = new Date();
  process.stdout.write(
    `[preorder-regression] start ${startedAt.toISOString()}\n`,
  );
  process.stdout.write(
    `[preorder-regression] files ${TEST_FILES.join(", ")}\n`,
  );

  const child = spawn(
    process.execPath,
    ["--test", ...TEST_FILES],
    {
      cwd: path.resolve(__dirname, ".."),
      stdio: "inherit",
      env: process.env,
    },
  );

  child.on("error", (error) => {
    process.stderr.write(
      `[preorder-regression] failed to start: ${error.message}\n`,
    );
    process.exitCode = 1;
  });

  child.on("exit", (code, signal) => {
    const endedAt = new Date();
    const durationMs =
      endedAt.getTime() - startedAt.getTime();
    if (signal) {
      process.stderr.write(
        `[preorder-regression] terminated by signal=${signal} after ${durationMs}ms\n`,
      );
      process.exitCode = 1;
      return;
    }
    process.stdout.write(
      `[preorder-regression] complete code=${code} durationMs=${durationMs}\n`,
    );
    process.exitCode = code || 0;
  });
}

runSuite();
