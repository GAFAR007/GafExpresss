/**
 * scripts/migrate-task-progress-entry-index.js
 * --------------------------------------------
 * WHAT:
 * - Backfills TaskProgress.entryIndex and swaps the legacy unique index
 *   for the new append-friendly compound unique index.
 *
 * WHY:
 * - "New count" appends multiple progress rows for the same task/staff/unit/day.
 * - The legacy unique index on (taskId, staffId, workDate, unitId) blocks that.
 *
 * HOW:
 * - Sets entryIndex=1 on existing rows that do not have it yet.
 * - Drops the legacy unique index if it exists.
 * - Creates the new unique index on
 *   (taskId, staffId, workDate, unitId, entryIndex).
 */

const path = require("node:path");
const mongoose = require("mongoose");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const TaskProgress = require("../models/TaskProgress");

function hasLegacyUniqueScopeFields(index) {
  return (
    index?.key?.taskId === 1 &&
    index?.key?.staffId === 1 &&
    index?.key?.workDate === 1
  );
}

function hasLegacyUniqueScopeIndex(index) {
  return (
    index?.unique === true &&
    hasLegacyUniqueScopeFields(index) &&
    typeof index?.key?.entryIndex === "undefined"
  );
}

async function main() {
  if (!process.env.MONGO_URI) {
    throw new Error("MONGO_URI is required");
  }

  await mongoose.connect(process.env.MONGO_URI);

  try {
    const backfillResult = await TaskProgress.updateMany(
      {
        $or: [
          {
            entryIndex: {
              $exists: false,
            },
          },
          {
            entryIndex: null,
          },
          {
            entryIndex: {
              $lt: 1,
            },
          },
        ],
      },
      {
        $set: {
          entryIndex: 1,
        },
      },
    );

    console.log(
      `Backfilled TaskProgress.entryIndex on ${backfillResult.modifiedCount || 0} row(s).`,
    );

    const indexes = await TaskProgress.collection.indexes();
    const legacyIndexes = indexes.filter(hasLegacyUniqueScopeIndex);
    if (legacyIndexes.length > 0) {
      for (const legacyIndex of legacyIndexes) {
        await TaskProgress.collection.dropIndex(legacyIndex.name);
        console.log(`Dropped legacy index ${legacyIndex.name}.`);
      }
    } else {
      console.log(
        "Legacy task progress scope indexes not found; nothing to drop.",
      );
    }

    const newIndexName = await TaskProgress.collection.createIndex(
      {
        taskId: 1,
        staffId: 1,
        workDate: 1,
        unitId: 1,
        entryIndex: 1,
      },
      {
        unique: true,
        name: "task_progress_scope_entry_unique",
      },
    );
    console.log(`Ensured new index ${newIndexName}.`);

    const finalIndexes = await TaskProgress.collection.indexes();
    console.log(
      "Current TaskProgress indexes:",
      finalIndexes.map((index) => ({
        name: index.name,
        key: index.key,
        unique: index.unique === true,
      })),
    );
  } finally {
    await mongoose.disconnect();
  }
}

main().catch((error) => {
  console.error("TaskProgress entry index migration failed:", error);
  process.exitCode = 1;
});
