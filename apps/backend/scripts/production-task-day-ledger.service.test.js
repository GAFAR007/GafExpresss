/**
 * backend/scripts/production-task-day-ledger.service.test.js
 * ----------------------------------------------------------
 * WHAT:
 * - Unit tests for shared production task/day ledger aggregation helpers.
 *
 * WHY:
 * - Shared unit + activity totals now drive production completion.
 * - These tests keep the aggregation logic deterministic without a DB harness.
 *
 * HOW:
 * - Calls pure service helpers with representative progress rows.
 * - Verifies shared unit completion, shared activity totals, rejection exclusion,
 *   and day normalization boundaries.
 */

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  SHARED_ACTIVITY_NONE,
  SHARED_ACTIVITY_PLANTED,
  SHARED_ACTIVITY_TRANSPLANTED,
  SHARED_ACTIVITY_HARVESTED,
  aggregateProductionTaskDayLedger,
  normalizeLedgerWorkDate,
  normalizeProductionLedgerActivityType,
} = require("../services/production_task_day_ledger.service");

test(
  "shared unit ledger aggregates multiple staff contributions for the same task/day",
  () => {
    const snapshot =
      aggregateProductionTaskDayLedger({
        progressRecords: [
          {
            staffId: "staff-a",
            unitContribution: 3.5,
            activityType:
              SHARED_ACTIVITY_TRANSPLANTED,
            activityQuantity: 500,
          },
          {
            staffId: "staff-b",
            actualPlots: 1.5,
            quantityActivityType:
              SHARED_ACTIVITY_TRANSPLANTED,
            quantityAmount: 500,
          },
        ],
        unitTarget: 5,
        unitType: "plots",
        activityTargets: {
          planted: null,
          transplanted: 2000,
          harvested: null,
        },
        activityUnits: {
          planted: "seed",
          transplanted: "seed",
          harvested: "crate",
        },
      });

    assert.equal(
      snapshot.unitCompleted,
      5,
    );
    assert.equal(
      snapshot.unitRemaining,
      0,
    );
    assert.equal(
      snapshot.status,
      "completed",
    );
    assert.equal(
      snapshot.activityCompleted.transplanted,
      1000,
    );
    assert.equal(
      snapshot.activityRemaining.transplanted,
      1000,
    );
  },
);

test(
  "secondary shared activity totals stay separate from primary unit completion",
  () => {
    const snapshot =
      aggregateProductionTaskDayLedger({
        progressRecords: [
          {
            unitContribution: 2,
            activityType:
              SHARED_ACTIVITY_PLANTED,
            activityQuantity: 300,
          },
          {
            unitContribution: 0,
            activityType:
              SHARED_ACTIVITY_HARVESTED,
            activityQuantity: 120,
          },
          {
            unitContribution: 0,
            activityType:
              SHARED_ACTIVITY_NONE,
            activityQuantity: 999,
          },
        ],
        unitTarget: 5,
        unitType: "plots",
        activityTargets: {
          planted: 1000,
          transplanted: 2000,
          harvested: 500,
        },
        activityUnits: {
          planted: "seed",
          transplanted: "seed",
          harvested: "crate",
        },
      });

    assert.equal(
      snapshot.unitCompleted,
      2,
    );
    assert.equal(
      snapshot.unitRemaining,
      3,
    );
    assert.equal(
      snapshot.activityCompleted.planted,
      300,
    );
    assert.equal(
      snapshot.activityRemaining.planted,
      700,
    );
    assert.equal(
      snapshot.activityCompleted.harvested,
      120,
    );
    assert.equal(
      snapshot.activityRemaining.harvested,
      380,
    );
  },
);

test(
  "rejected progress rows are excluded from the shared ledger totals",
  () => {
    const snapshot =
      aggregateProductionTaskDayLedger({
        progressRecords: [
          {
            unitContribution: 2,
            activityType:
              SHARED_ACTIVITY_PLANTED,
            activityQuantity: 200,
          },
          {
            unitContribution: 4,
            activityType:
              SHARED_ACTIVITY_TRANSPLANTED,
            activityQuantity: 1000,
            notes:
              "[TASK_PROGRESS_REJECTED] 2026-04-12T00:00:00.000Z reviewer=test reason=bad_log",
          },
        ],
        unitTarget: 10,
        unitType: "plots",
        activityTargets: {
          planted: 500,
          transplanted: 2000,
          harvested: null,
        },
        activityUnits: {
          planted: "seed",
          transplanted: "seed",
          harvested: "",
        },
      });

    assert.equal(
      snapshot.unitCompleted,
      2,
    );
    assert.equal(
      snapshot.activityCompleted.transplanted,
      0,
    );
    assert.equal(
      snapshot.activityRemaining.transplanted,
      2000,
    );
  },
);

test(
  "day normalization keeps separate ledgers for separate dates",
  () => {
    const dayOne =
      normalizeLedgerWorkDate(
        "2026-04-12T18:45:00.000Z",
      );
    const dayTwo =
      normalizeLedgerWorkDate(
        "2026-04-13T01:15:00.000Z",
      );

    assert.equal(
      dayOne.toISOString(),
      "2026-04-12T00:00:00.000Z",
    );
    assert.equal(
      dayTwo.toISOString(),
      "2026-04-13T00:00:00.000Z",
    );
    assert.notEqual(
      dayOne.getTime(),
      dayTwo.getTime(),
    );
  },
);

test(
  "activity normalization maps legacy labels to the shared canonical options",
  () => {
    assert.equal(
      normalizeProductionLedgerActivityType(
        "planting",
      ),
      SHARED_ACTIVITY_PLANTED,
    );
    assert.equal(
      normalizeProductionLedgerActivityType(
        "transplant",
      ),
      SHARED_ACTIVITY_TRANSPLANTED,
    );
    assert.equal(
      normalizeProductionLedgerActivityType(
        "harvest",
      ),
      SHARED_ACTIVITY_HARVESTED,
    );
    assert.equal(
      normalizeProductionLedgerActivityType(
        "No quantity update",
      ),
      SHARED_ACTIVITY_NONE,
    );
  },
);
