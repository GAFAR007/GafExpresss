/**
 * apps/backend/scripts/planner-v2.unit.test.js
 * --------------------------------------------
 * WHAT:
 * - Focused unit tests for planner V2 validation and schedule expansion helpers.
 *
 * WHY:
 * - Planner V2 must prove that it rejects invalid AI output and expands recurring work deterministically.
 *
 * HOW:
 * - Exercises lifecycle catalog lookup, AJV validation, and scheduleBuilder expansion.
 * - Runs with the built-in Node test runner so no extra harness is required.
 */

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  findCatalogLifecycleProfile,
} = require("../services/planner/lifecycleCatalog");
const {
  extractJsonObject,
} = require("../services/planner/jsonExtraction");
const {
  validatePhasePlan,
  validateTaskPlan,
  validateLifecyclePlanningWindow,
} = require("../services/planner/validationEngine");
const {
  buildDraftSchedule,
} = require("../services/planner/scheduleBuilder");
const {
  __test__: {
    normalizeGeoglamFeaturesToLifecycle,
    normalizeTrefleSpeciesToLifecycle,
    resolveAgricultureCropKey,
  },
} = require("../services/planner/agricultureApiClient");

test(
  "planner V2 lifecycle catalog resolves known crops",
  () => {
    const lifecycle =
      findCatalogLifecycleProfile({
        productName: "Corn",
        cropSubtype: "",
      });

    assert.ok(lifecycle);
    assert.equal(lifecycle.minDays, 90);
    assert.equal(lifecycle.maxDays, 120);
    assert.deepEqual(
      lifecycle.phases,
      [
        "land_preparation",
        "planting",
        "vegetative_growth",
        "flowering",
        "grain_fill",
        "harvest",
      ],
    );
  },
);

test(
  "planner V2 lifecycle catalog matches product aliases inside longer names",
  () => {
    const lifecycle =
      findCatalogLifecycleProfile({
        productName: "Rice Plant",
        cropSubtype: "",
      });

    assert.ok(lifecycle);
    assert.equal(lifecycle.product, "Rice");
  },
);

test(
  "planner V2 agriculture provider resolves horticulture aliases to canonical crop keys",
  () => {
    assert.equal(
      resolveAgricultureCropKey({
        productName: "Red onions",
        cropSubtype: "",
      }),
      "onion",
    );
    assert.equal(
      resolveAgricultureCropKey({
        productName: "Bell peppers",
        cropSubtype: "",
      }),
      "pepper",
    );
  },
);

test(
  "planner V2 agriculture provider maps GEOGLAM rows into lifecycle bounds",
  () => {
    const lifecycle =
      normalizeGeoglamFeaturesToLifecycle(
        {
          cropKey: "rice",
          productName: "Rice",
          country: "Nigeria",
          features: [
            {
              attributes: {
                country: "Nigeria",
                region: "South",
                crop: "Rice 1",
                planting: 91,
                vegetative: 121,
                harvest: 182,
                endofseaso: 213,
              },
            },
            {
              attributes: {
                country: "Nigeria",
                region: "North",
                crop: "Rice 1",
                planting: 152,
                vegetative: 213,
                harvest: 274,
                endofseaso: 305,
              },
            },
          ],
        },
      );

    assert.ok(lifecycle);
    assert.equal(lifecycle.minDays, 92);
    assert.equal(lifecycle.maxDays, 154);
    assert.deepEqual(
      lifecycle.phases,
      [
        "land_preparation",
        "planting",
        "vegetative_growth",
        "flowering",
        "grain_fill",
        "harvest",
      ],
    );
    assert.equal(
      lifecycle.metadata.providerKey,
      "geoglam",
    );
  },
);

test(
  "planner V2 agriculture provider maps Trefle growth data into lifecycle bounds",
  () => {
    const lifecycle =
      normalizeTrefleSpeciesToLifecycle(
        {
          cropKey: "tomato",
          productName: "Tomato",
          species: {
            id: 42,
            slug: "solanum-lycopersicum",
            common_name: "Tomato",
            scientific_name:
              "Solanum lycopersicum",
            rank: "species",
            family: "Solanaceae",
            growth: {
              days_to_harvest: 80,
              growth_months: [
                "april",
                "may",
                "june",
              ],
              sowing:
                "Sow when soil is warm.",
              ph_minimum: 6,
              ph_maximum: 6.8,
              minimum_temperature: {
                deg_c: 18,
              },
              maximum_temperature: {
                deg_c: 35,
              },
              minimum_precipitation: {
                mm: 400,
              },
              maximum_precipitation: {
                mm: 800,
              },
            },
          },
        },
      );

    assert.ok(lifecycle);
    assert.equal(lifecycle.minDays, 72);
    assert.equal(lifecycle.maxDays, 88);
    assert.deepEqual(
      lifecycle.phases,
      [
        "land_preparation",
        "planting",
        "vegetative_growth",
        "flowering",
        "fruit_development",
        "harvest",
      ],
    );
    assert.equal(
      lifecycle.metadata.providerKey,
      "trefle",
    );
    assert.equal(
      lifecycle.metadata.daysToHarvest,
      80,
    );
  },
);

test(
  "planner V2 JSON extraction recovers fenced JSON payloads",
  () => {
    const parsed = extractJsonObject(`
Provider note:
\`\`\`json
{"product":"Rice","minDays":90,"maxDays":120,"phases":["land_preparation","planting","harvest"]}
\`\`\`
`);
    assert.deepEqual(parsed, {
      product: "Rice",
      minDays: 90,
      maxDays: 120,
      phases: [
        "land_preparation",
        "planting",
        "harvest",
      ],
    });
  },
);

test(
  "planner V2 phase validation rejects phases outside lifecycle order",
  () => {
    assert.throws(
      () =>
        validatePhasePlan({
          lifecycle: {
            phases: [
              "land_preparation",
              "planting",
              "harvest",
            ],
          },
          payload: {
            phases: [
              { phaseName: "harvest" },
              { phaseName: "planting" },
            ],
          },
        }),
      /lifecycle order/i,
    );
  },
);

test(
  "planner V2 task validation rejects forbidden scheduling fields",
  () => {
    assert.throws(
      () =>
        validateTaskPlan({
          phaseName: "planting",
          payload: {
            tasks: [
              {
                taskKey: "planting",
                taskName: "Planting",
                taskType: "workload",
                roleRequired: "farmer",
                workloadUnits: 10,
                startDate:
                  "2026-03-15T08:00:00.000Z",
              },
            ],
          },
        }),
      /forbidden/i,
    );
  },
);

test(
  "planner V2 rejects impossible lifecycle range requests",
  () => {
    assert.throws(
      () =>
        validateLifecyclePlanningWindow({
          lifecycle: {
            minDays: 90,
            maxDays: 120,
          },
          requestedDays: 30,
        }),
      /outside the supported lifecycle window/i,
    );
  },
);

test(
  "planner V2 schedule builder expands workload, recurring, and event tasks",
  () => {
    const result = buildDraftSchedule({
      lifecycle: {
        minDays: 14,
        maxDays: 14,
        phases: [
          "land_preparation",
          "planting",
        ],
      },
      phases: [
        {
          phaseName: "land_preparation",
          lifecycleIndex: 0,
        },
        {
          phaseName: "planting",
          lifecycleIndex: 1,
        },
      ],
      tasksByPhase: new Map([
        [
          "land_preparation",
          [
            {
              taskKey: "soil_prep",
              taskName: "Soil preparation",
              taskType: "workload",
              roleRequired: "farmer",
              requiredHeadcount: 2,
              workloadUnits: 6,
            },
          ],
        ],
        [
          "planting",
          [
            {
              taskKey: "planting",
              taskName: "Planting",
              taskType: "workload",
              roleRequired: "farmer",
              requiredHeadcount: 2,
              workloadUnits: 10,
            },
            {
              taskKey: "irrigation",
              taskName: "Irrigation",
              taskType: "recurring",
              roleRequired: "farmer",
              requiredHeadcount: 1,
              frequencyEveryDays: 3,
              firstOccurrenceOffsetDays: 1,
            },
            {
              taskKey: "fertilizer_application",
              taskName: "Fertilizer application",
              taskType: "event",
              roleRequired: "field_agent",
              requiredHeadcount: 1,
              occurrence: "mid_phase",
            },
          ],
        ],
      ]),
      schedulePolicy: {
        workWeekDays: [1, 2, 3, 4, 5, 6, 7],
        blocks: [{ start: "08:00", end: "12:00" }],
        minSlotMinutes: 30,
        timezone: "Africa/Lagos",
      },
      capacitySummary: {
        roles: {
          farmer: { total: 3, available: 3 },
          field_agent: { total: 1, available: 1 },
        },
      },
      workloadContext: {
        workUnitType: "plot",
      },
      productId: "product_1",
      productName: "Corn",
      estateAssetId: "estate_1",
      startDate: new Date("2026-03-15T00:00:00.000Z"),
      endDate: new Date("2026-03-28T00:00:00.000Z"),
    });

    const recurringRows = result.tasks.filter(
      (task) => task.sourceTemplateKey === "irrigation",
    );
    const workloadRows = result.tasks.filter(
      (task) => task.sourceTemplateKey === "planting",
    );
    const eventRows = result.tasks.filter(
      (task) =>
        task.sourceTemplateKey ===
        "fertilizer_application",
    );

    assert.ok(recurringRows.length >= 2);
    assert.ok(workloadRows.length >= 1);
    assert.equal(eventRows.length, 1);
    assert.ok(
      recurringRows.every(
        (task) =>
          task.startDate &&
          task.dueDate &&
          new Date(task.dueDate) >=
            new Date(task.startDate),
      ),
    );
    assert.ok(
      result.warnings.every(
        (warning) =>
          ![
            "DAILY_FALLBACK_GENERATED",
            "SPARSE_RECOVERED_DRAFT_FALLBACK",
            "SPARSE_SCHEDULE_TOP_UP",
          ].includes(warning.code),
      ),
    );
  },
);

test(
  "planner V2 schedule builder intensifies workload headcount to configured staffing bounds",
  () => {
    const result = buildDraftSchedule({
      lifecycle: {
        minDays: 7,
        maxDays: 7,
        phases: ["land_preparation"],
      },
      phases: [
        {
          phaseName: "land_preparation",
          lifecycleIndex: 0,
        },
      ],
      tasksByPhase: new Map([
        [
          "land_preparation",
          [
            {
              taskKey: "soil_prep",
              taskName: "Soil preparation",
              taskType: "workload",
              roleRequired: "farmer",
              requiredHeadcount: 1,
              workloadUnits: 6,
            },
          ],
        ],
      ]),
      schedulePolicy: {
        workWeekDays: [1, 2, 3, 4, 5, 6, 7],
        blocks: [{ start: "08:00", end: "12:00" }],
        minSlotMinutes: 30,
        timezone: "Africa/Lagos",
      },
      capacitySummary: {
        roles: {
          farmer: { total: 6, available: 6 },
        },
      },
      workloadContext: {
        workUnitType: "plot",
        minStaffPerUnit: 1,
        maxStaffPerUnit: 3,
        activeStaffAvailabilityPercent: 70,
      },
      productId: "product_1",
      productName: "Beans",
      estateAssetId: "estate_1",
      startDate: new Date("2026-03-15T00:00:00.000Z"),
      endDate: new Date("2026-03-21T00:00:00.000Z"),
    });

    const workloadRows = result.tasks.filter(
      (task) => task.sourceTemplateKey === "soil_prep",
    );

    assert.equal(workloadRows.length, 1);
    assert.equal(workloadRows[0].requiredHeadcount, 3);
  },
);

test(
  "planner V2 schedule builder extends summary range when workload rows exceed the initial window",
  () => {
    const result = buildDraftSchedule({
      lifecycle: {
        minDays: 14,
        maxDays: 14,
        phases: [
          "land_preparation",
          "planting",
        ],
      },
      phases: [
        {
          phaseName: "land_preparation",
          lifecycleIndex: 0,
        },
        {
          phaseName: "planting",
          lifecycleIndex: 1,
        },
      ],
      tasksByPhase: new Map([
        [
          "land_preparation",
          [
            {
              taskKey: "soil_prep",
              taskName: "Soil preparation",
              taskType: "workload",
              roleRequired: "farmer",
              requiredHeadcount: 1,
              workloadUnits: 50,
            },
          ],
        ],
        ["planting", []],
      ]),
      schedulePolicy: {
        workWeekDays: [1, 2, 3, 4, 5, 6, 7],
        blocks: [{ start: "08:00", end: "12:00" }],
        minSlotMinutes: 30,
        timezone: "Africa/Lagos",
      },
      capacitySummary: {
        roles: {
          farmer: { total: 2, available: 2 },
        },
      },
      workloadContext: {
        workUnitType: "plot",
      },
      productId: "product_1",
      productName: "Corn",
      estateAssetId: "estate_1",
      startDate: new Date("2026-03-15T00:00:00.000Z"),
      endDate: new Date("2026-03-28T00:00:00.000Z"),
    });

    const latestTaskDueDate = result.tasks.reduce((latest, task) => {
      const dueDate = new Date(task.dueDate);
      return dueDate.getTime() > latest.getTime() ? dueDate : latest;
    }, new Date(result.tasks[0].dueDate));
    const expectedDays =
      Math.floor(
        (new Date(`${result.summary.endDate}T00:00:00.000Z`).getTime() -
          new Date(`${result.summary.startDate}T00:00:00.000Z`).getTime()) /
          86400000,
      ) + 1;

    const latestTaskDueDateSummaryKey = new Date(
      latestTaskDueDate.getFullYear(),
      latestTaskDueDate.getMonth(),
      latestTaskDueDate.getDate(),
      0,
      0,
      0,
      0,
    )
      .toISOString()
      .slice(0, 10);

    assert.equal(
      result.summary.endDate,
      latestTaskDueDateSummaryKey,
    );
    assert.equal(result.summary.days, expectedDays);
    assert.ok(
      result.warnings.some(
        (warning) =>
          warning.code ===
          "WORKLOAD_COMPLETION_WINDOW_EXTENDED",
      ),
    );
  },
);
