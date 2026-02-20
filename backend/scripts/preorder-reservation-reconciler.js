/**
 * backend/scripts/preorder-reservation-reconciler.js
 * --------------------------------------------------
 * WHAT:
 * - Runs expired pre-order reservation reconciliation from CLI.
 *
 * WHY:
 * - Releases stuck reserved capacity when reservation holds pass expiresAt.
 *
 * HOW:
 * - Connects to MongoDB.
 * - Calls the shared reconciler service with optional business scope.
 * - Prints a deterministic summary for ops monitoring.
 */

const path = require("node:path");
const mongoose = require("mongoose");
const debug = require("../utils/debug");
const {
  reconcileExpiredPreorderReservations,
} = require("../services/preorder_reservation_reconciler.service");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

function parseCliArgs(argv) {
  const parsed = {
    businessId: null,
    limit: null,
  };

  for (const arg of argv) {
    // WHY: Allow safe scoped reconciliation without changing script code.
    if (arg.startsWith("--businessId=")) {
      parsed.businessId = arg
        .replace("--businessId=", "")
        .trim();
    }
    if (arg.startsWith("--limit=")) {
      parsed.limit = Number(
        arg.replace("--limit=", "").trim(),
      );
    }
  }

  return parsed;
}

async function run() {
  const mongoUri = (
    process.env.MONGO_URI || ""
  ).trim();
  if (!mongoUri) {
    throw new Error(
      "MONGO_URI is required to run preorder reservation reconciler",
    );
  }

  const args = parseCliArgs(
    process.argv.slice(2),
  );
  const startedAt = new Date();

  debug(
    "PREORDER RECONCILER SCRIPT: start",
    {
      businessId:
        args.businessId || null,
      limit: args.limit || null,
      intent:
        "expire stale reservations and release reserved preorder capacity",
    },
  );

  await mongoose.connect(mongoUri);
  try {
    const summary =
      await reconcileExpiredPreorderReservations(
        {
          businessId:
            args.businessId || null,
          limit: args.limit || undefined,
          now: startedAt,
        },
      );

    debug(
      "PREORDER RECONCILER SCRIPT: success",
      {
        businessId:
          summary.businessId,
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

    // WHY: Keep script output machine-readable for cron/ops tooling.
    process.stdout.write(
      `${JSON.stringify(summary, null, 2)}\n`,
    );
  } finally {
    await mongoose.disconnect();
  }
}

run().catch((error) => {
  debug(
    "PREORDER RECONCILER SCRIPT: failure",
    {
      reason: error.message,
      next: "Validate Mongo connection and retry reconciliation",
    },
  );
  process.stderr.write(
    `${error.message}\n`,
  );
  process.exitCode = 1;
});

