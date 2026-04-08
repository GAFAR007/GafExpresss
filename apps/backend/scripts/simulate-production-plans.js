/**
 * scripts/simulate-production-plans.js
 * ------------------------------------
 * WHAT:
 * - Seeds realistic virtual production plans for operators to test the
 *   production workspace, detail screens, and progress flows.
 *
 * WHY:
 * - Gives the team repeatable scenario data without hand-building plans.
 * - Keeps seeded data clearly tagged so re-runs replace only virtual records.
 *
 * HOW:
 * - Resolves a target business owner, estate, staff pool, and fallback products.
 * - Seeds tagged plans/phases/tasks/units/schedules/progress/attendance.
 * - Runs as dry-run by default; pass --execute to write to MongoDB.
 */

const path = require("path");

require("dotenv").config({
  path: path.resolve(__dirname, "..", ".env"),
});

const mongoose = require("mongoose");
const bcrypt = require("bcryptjs");

const connectDB = require("../config/db");
const debug = require("../utils/debug");
const { resolveBusinessContext } = require("../services/business_context.service");
const {
  sanitizeProductTaxonomyFields,
  sanitizeProductSellingFields,
} = require("../utils/product_taxonomy");
const {
  DEFAULT_PRODUCTION_PRODUCT_STATE,
  PLOT_UNIT_SCALE,
} = require("../utils/production_engine.config");

const User = require("../models/User");
const Product = require("../models/Product");
const BusinessAsset = require("../models/BusinessAsset");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const ProductionPlan = require("../models/ProductionPlan");
const ProductionPhase = require("../models/ProductionPhase");
const ProductionTask = require("../models/ProductionTask");
const PlanUnit = require("../models/PlanUnit");
const ProductionUnitTaskSchedule = require("../models/ProductionUnitTaskSchedule");
const TaskProgress = require("../models/TaskProgress");
const StaffAttendance = require("../models/StaffAttendance");
const ProductionOutput = require("../models/ProductionOutput");
const AuditLog = require("../models/AuditLog");
const BusinessAnalyticsEvent = require("../models/BusinessAnalyticsEvent");

const SIMULATION_TAG = "SIMULATION:production-plan";
const SIMULATION_PRODUCT_PREFIX = "Virtual Scenario";
const SIMULATION_STAFF_NOTE = "simulation_staff_profile";
const SIMULATION_PASSWORD = "VirtualPlan#2026";

const args = process.argv.slice(2);
const shouldExecute = args.includes("--execute");
const shouldListScenarios = args.includes("--list-scenarios");
const shouldShowHelp = args.includes("--help") || args.includes("-h");
const ownerEmail = readArg("--owner-email=");
const estateAssetIdArg = readArg("--estate-asset-id=");
const scenarioArg = readArg("--scenario=");

function readArg(prefix) {
  const match = args.find((arg) => arg.startsWith(prefix));
  return match ? match.slice(prefix.length).trim() : "";
}

function startOfLocalDay(date = new Date()) {
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    12,
    0,
    0,
    0,
  );
}

function addDays(date, days) {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return startOfLocalDay(next);
}

function dateAtTime(date, hours, minutes = 0) {
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    hours,
    minutes,
    0,
    0,
  );
}

function dateKey(date) {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

function roundTo(value, decimals = 3) {
  const factor = 10 ** decimals;
  return Math.round(Number(value) * factor) / factor;
}

function toPlotUnits(value) {
  return Math.round(roundTo(value) * PLOT_UNIT_SCALE);
}

function parseScenarioKeys() {
  const availableKeys = Object.keys(SCENARIO_BUILDERS);
  if (!scenarioArg || scenarioArg.toLowerCase() === "all") {
    return availableKeys;
  }

  const requested = scenarioArg
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const invalid = requested.filter(
    (value) => !SCENARIO_BUILDERS[value],
  );

  if (invalid.length > 0) {
    throw new Error(
      `Unknown scenario keys: ${invalid.join(", ")}. Use --list-scenarios to see valid options.`,
    );
  }

  return Array.from(new Set(requested));
}

function printHelp() {
  console.log(`
Virtual production scenario simulator

Usage:
  node scripts/simulate-production-plans.js [options]

Options:
  --execute                Write records. Dry-run is the default.
  --owner-email=<email>    Target a specific business owner. Defaults to first business_owner.
  --estate-asset-id=<id>   Reuse a specific estate asset for all seeded plans.
  --scenario=<keys>        Comma-separated scenario keys or "all".
  --list-scenarios         Print the available scenario keys and exit.
  --help                   Show this help and exit.

Examples:
  npm run ops:production:simulate
  npm run ops:production:simulate -- --owner-email=owner@example.com --scenario=on_track_rice
  npm run ops:production:simulate -- --execute --scenario=all
  `);
}

function printScenarioList() {
  console.log("Available simulation scenarios:");
  for (const [key, builder] of Object.entries(SCENARIO_BUILDERS)) {
    const scenario = builder(startOfLocalDay(new Date()));
    console.log(
      `- ${key}: ${scenario.summary} (${scenario.unitCount} ${scenario.unitLabel.toLowerCase()}s, ${scenario.phases.length} phases, ${scenario.tasks.length} tasks)`,
    );
  }
}

function buildScenarioName(key, cropName) {
  return `${SIMULATION_PRODUCT_PREFIX} · ${key} · ${cropName}`;
}

function buildSimulationNote(key) {
  return `${SIMULATION_TAG} scenario=${key}`;
}

function buildPhaseWindows(startDate, phaseSpecs) {
  let cursor = startOfLocalDay(startDate);

  return phaseSpecs.map((spec, index) => {
    const phaseStart = cursor;
    const phaseEnd = addDays(phaseStart, spec.durationDays - 1);
    cursor = addDays(phaseEnd, 1);

    return {
      ...spec,
      order: index + 1,
      startDate: phaseStart,
      endDate: phaseEnd,
    };
  });
}

function buildBasePhases(planStartDate, phaseSpecs) {
  const dated = buildPhaseWindows(planStartDate, phaseSpecs);
  const planEndDate = dated[dated.length - 1].endDate;
  return {
    phases: dated,
    endDate: planEndDate,
  };
}

function makeDailyLog(offset, actuals, options = {}) {
  return {
    offset,
    actuals,
    delayReason: options.delayReason || "none",
    notes: options.notes || "",
    expecteds: options.expecteds || null,
  };
}

function buildRiceScenario(today) {
  const planStartDate = addDays(today, -12);
  const { phases, endDate } = buildBasePhases(planStartDate, [
    {
      key: "nursery_or_direct_seed",
      name: "nursery_or_direct_seed",
      durationDays: 6,
      phaseType: "finite",
      requiredUnits: 10,
    },
    {
      key: "establishment",
      name: "establishment",
      durationDays: 24,
      phaseType: "finite",
      requiredUnits: 10,
    },
    {
      key: "tillering",
      name: "tillering",
      durationDays: 20,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "panicle_initiation",
      name: "panicle_initiation",
      durationDays: 14,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "heading",
      name: "heading",
      durationDays: 12,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "grain_fill",
      name: "grain_fill",
      durationDays: 24,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "harvest",
      name: "harvest",
      durationDays: 12,
      phaseType: "finite",
      requiredUnits: 10,
    },
  ]);

  return {
    key: "on_track_rice",
    cropName: "Jasmine Rice",
    summary: "An active rice plan with steady execution and live supervisory activity.",
    title: `${buildScenarioName("on_track_rice", "Jasmine Rice")} Plan`,
    productName: buildScenarioName("on_track_rice", "Jasmine Rice"),
    notes: buildSimulationNote("on_track_rice"),
    domainContext: "farm",
    unitLabel: "Plot",
    unitCount: 10,
    startDate: planStartDate,
    endDate,
    phases,
    product: {
      description:
        "Virtual scenario product for on-track rice execution and harvest planning.",
      category: "Farm & Agro",
      subcategory: "Grains & Cereals",
      price: 350000,
      stock: 120,
      productionState: "in_production",
      sellingOptions: [
        { packageType: "Bag", quantity: 20, measurementUnit: "kg", isDefault: true },
        { packageType: "Sack", quantity: 50, measurementUnit: "kg", isDefault: false },
      ],
    },
    tasks: [
      {
        key: "prepare_nursery_setup",
        phaseKey: "nursery_or_direct_seed",
        title: "Prepare nursery setup for Jasmine Rice",
        instructions:
          "Level the nursery plots, water lightly, and confirm seed trays and soil mix are ready.",
        roleRequired: "farmer",
        requiredHeadcount: 3,
        taskType: "workload",
        status: "done",
        startOffsetDays: 0,
        durationDays: 3,
        unitScope: "all",
        dailyLogs: [
          makeDailyLog(0, [1, 1, 1], {
            notes: "Cleared and leveled nursery plots.",
          }),
          makeDailyLog(1, [1, 1, 1], {
            notes: "Prepared irrigation channels and seed trays.",
          }),
          makeDailyLog(2, [1, 1, 2], {
            notes: "Final setup pass completed across all plots.",
          }),
        ],
      },
      {
        key: "sow_seedbeds",
        phaseKey: "nursery_or_direct_seed",
        title: "Sow Jasmine Rice nursery seedbeds and record seed targets",
        instructions:
          "Sow seedbeds, record target volumes, and verify even distribution across nursery plots.",
        roleRequired: "farmer",
        requiredHeadcount: 3,
        taskType: "workload",
        status: "done",
        startOffsetDays: 1,
        durationDays: 4,
        unitScope: "all",
        dailyLogs: [
          makeDailyLog(1, [1, 1, 1], {
            notes: "Seed placement started on the first nursery sections.",
          }),
          makeDailyLog(2, [1, 1, 1], {
            notes: "Sowing continued across the central blocks.",
          }),
          makeDailyLog(3, [1, 1, 2], {
            notes: "Completed sowing on the final plot set.",
          }),
        ],
      },
      {
        key: "count_germination",
        phaseKey: "establishment",
        title: "Count Jasmine Rice germination and viable nursery sections",
        instructions:
          "Inspect viable nursery sections, note gaps, and prepare rework list for weak rows.",
        roleRequired: "farmer",
        requiredHeadcount: 2,
        taskType: "workload",
        status: "in_progress",
        startOffsetDays: 8,
        durationDays: 4,
        unitScope: "all",
        dailyLogs: [
          makeDailyLog(8, [2.5, 1.5], {
            notes: "Strong emergence on the first half of the nursery blocks.",
          }),
          makeDailyLog(9, [2, 2], {
            notes: "Viable count updated after afternoon walkthrough.",
          }),
        ],
      },
      {
        key: "weekly_farm_operations_supervision",
        phaseKey: "establishment",
        title: "Weekly farm operations supervision",
        instructions:
          "Supervise staff deployment, confirm workload coverage, and unblock field issues.",
        roleRequired: "farm_manager",
        requiredHeadcount: 1,
        taskType: "recurring",
        status: "in_progress",
        startOffsetDays: 8,
        durationDays: 12,
        unitScope: "none",
        dailyLogs: [
          makeDailyLog(8, [1], {
            notes: "Staff deployment reviewed and work split confirmed.",
          }),
          makeDailyLog(10, [1], {
            notes: "Follow-up supervision completed on field execution.",
          }),
          makeDailyLog(12, [1], {
            notes: "Supervisory walkthrough completed for the weekly cycle.",
          }),
        ],
      },
      {
        key: "weekly_estate_operations_oversight",
        phaseKey: "establishment",
        title: "Weekly estate operations oversight",
        instructions:
          "Review daily progress evidence, safety readiness, and estate-level operational blockers.",
        roleRequired: "estate_manager",
        requiredHeadcount: 1,
        taskType: "recurring",
        status: "in_progress",
        startOffsetDays: 8,
        durationDays: 12,
        unitScope: "none",
        dailyLogs: [
          makeDailyLog(8, [1], {
            notes: "Estate-level operations reviewed and documented.",
          }),
          makeDailyLog(10, [1], {
            notes: "Confirmed irrigation readiness and operator coverage.",
          }),
        ],
      },
    ],
  };
}

function buildPepperScenario(today) {
  const planStartDate = addDays(today, -20);
  const { phases, endDate } = buildBasePhases(planStartDate, [
    {
      key: "nursery_or_direct_seed",
      name: "nursery_or_direct_seed",
      durationDays: 7,
      phaseType: "finite",
      requiredUnits: 8,
    },
    {
      key: "establishment",
      name: "establishment",
      durationDays: 18,
      phaseType: "finite",
      requiredUnits: 8,
    },
    {
      key: "flowering",
      name: "flowering",
      durationDays: 20,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "fruit_fill",
      name: "fruit_fill",
      durationDays: 24,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "harvest",
      name: "harvest",
      durationDays: 10,
      phaseType: "finite",
      requiredUnits: 8,
    },
  ]);

  return {
    key: "carry_over_pepper",
    cropName: "Bell Pepper",
    summary:
      "A bell pepper plan with partial execution and visible carry-over pressure in monitoring work.",
    title: `${buildScenarioName("carry_over_pepper", "Bell Pepper")} Plan`,
    productName: buildScenarioName("carry_over_pepper", "Bell Pepper"),
    notes: buildSimulationNote("carry_over_pepper"),
    domainContext: "farm",
    unitLabel: "Greenhouse",
    unitCount: 8,
    startDate: planStartDate,
    endDate,
    phases,
    product: {
      description:
        "Virtual scenario bell pepper product showing partial completion and carry-over monitoring.",
      category: "Farm & Agro",
      subcategory: "Vegetables",
      price: 240000,
      stock: 65,
      productionState: "in_production",
      sellingOptions: [
        { packageType: "Basket", quantity: 5, measurementUnit: "kg", isDefault: true },
        { packageType: "Carton", quantity: 10, measurementUnit: "kg", isDefault: false },
      ],
    },
    tasks: [
      {
        key: "transplant_pepper_seedlings",
        phaseKey: "establishment",
        title: "Transplant Bell Pepper seedlings into production greenhouses",
        instructions:
          "Transplant hardened seedlings, confirm irrigation flow, and log weak stands for recheck.",
        roleRequired: "farmer",
        requiredHeadcount: 3,
        taskType: "workload",
        status: "done",
        startOffsetDays: 7,
        durationDays: 4,
        unitScope: "all",
        dailyLogs: [
          makeDailyLog(7, [1, 1, 1], {
            notes: "First transplant batch moved into protected houses.",
          }),
          makeDailyLog(8, [1, 1, 1], {
            notes: "Transplant continued with irrigation checks.",
          }),
          makeDailyLog(9, [1, 1], {
            notes: "Final greenhouse transplant pass completed.",
          }),
        ],
      },
      {
        key: "inspect_pepper_blocks",
        phaseKey: "flowering",
        title: "Inspect pepper blocks and record canopy balance",
        instructions:
          "Walk each greenhouse, confirm flower set, and capture houses needing corrective pruning.",
        roleRequired: "farmer",
        requiredHeadcount: 2,
        taskType: "workload",
        status: "in_progress",
        startOffsetDays: 12,
        durationDays: 4,
        unitScope: "all",
        dailyLogs: [
          makeDailyLog(12, [2.5, 2.5], {
            notes: "Inspected the first five greenhouse blocks.",
          }),
          makeDailyLog(13, [1, 0], {
            delayReason: "rain",
            notes: "Heavy rain slowed the second walkthrough.",
          }),
        ],
      },
      {
        key: "pepper_harvest_carton_prep",
        phaseKey: "fruit_fill",
        title: "Prepare cartons and harvest staging for Bell Pepper",
        instructions:
          "Stage cartons, labels, and picking routes before first harvest release.",
        roleRequired: "inventory_keeper",
        requiredHeadcount: 1,
        taskType: "event",
        status: "pending",
        startOffsetDays: 30,
        durationDays: 3,
        unitScope: "none",
        dailyLogs: [],
      },
      {
        key: "pepper_ops_supervision",
        phaseKey: "flowering",
        title: "Weekly farm operations supervision",
        instructions:
          "Review greenhouse staffing, irrigation discipline, and carry-over recovery actions.",
        roleRequired: "farm_manager",
        requiredHeadcount: 1,
        taskType: "recurring",
        status: "in_progress",
        startOffsetDays: 10,
        durationDays: 14,
        unitScope: "none",
        dailyLogs: [
          makeDailyLog(10, [1], {
            notes: "Greenhouse staffing and execution backlog reviewed.",
          }),
          makeDailyLog(13, [1], {
            notes: "Follow-up action logged after weather disruption.",
          }),
        ],
      },
      {
        key: "pepper_estate_oversight",
        phaseKey: "flowering",
        title: "Weekly estate operations oversight",
        instructions:
          "Confirm greenhouse access readiness, shift windows, and issue escalation paths.",
        roleRequired: "estate_manager",
        requiredHeadcount: 1,
        taskType: "recurring",
        status: "in_progress",
        startOffsetDays: 10,
        durationDays: 14,
        unitScope: "none",
        dailyLogs: [
          makeDailyLog(10, [1], {
            notes: "Estate readiness confirmed for greenhouse checks.",
          }),
        ],
      },
    ],
  };
}

function buildTomatoScenario(today) {
  const planStartDate = addDays(today, -55);
  const { phases, endDate } = buildBasePhases(planStartDate, [
    {
      key: "establishment",
      name: "establishment",
      durationDays: 15,
      phaseType: "finite",
      requiredUnits: 6,
    },
    {
      key: "vegetative_growth",
      name: "vegetative_growth",
      durationDays: 20,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "flowering_fruiting",
      name: "flowering_fruiting",
      durationDays: 15,
      phaseType: "monitoring",
      requiredUnits: 0,
    },
    {
      key: "harvest",
      name: "harvest",
      durationDays: 12,
      phaseType: "finite",
      requiredUnits: 6,
    },
  ]);

  return {
    key: "harvest_push_tomato",
    cropName: "Cherry Tomato",
    summary:
      "A near-harvest tomato plan with picking, packing, and output records already in motion.",
    title: `${buildScenarioName("harvest_push_tomato", "Cherry Tomato")} Plan`,
    productName: buildScenarioName("harvest_push_tomato", "Cherry Tomato"),
    notes: buildSimulationNote("harvest_push_tomato"),
    domainContext: "farm",
    unitLabel: "Bed",
    unitCount: 6,
    startDate: planStartDate,
    endDate,
    phases,
    product: {
      description:
        "Virtual scenario cherry tomato plan focused on harvest push and packing readiness.",
      category: "Farm & Agro",
      subcategory: "Vegetables",
      price: 180000,
      stock: 40,
      productionState: "available_for_preorder",
      sellingOptions: [
        { packageType: "Crate", quantity: 15, measurementUnit: "kg", isDefault: true },
        { packageType: "Basket", quantity: 5, measurementUnit: "kg", isDefault: false },
      ],
      preorderEnabled: true,
      preorderCapQuantity: 24,
      preorderReservedQuantity: 9,
    },
    outputs: [
      {
        unitType: "crates",
        quantity: 24,
        readyForSale: false,
        pricePerUnit: 180000,
      },
    ],
    tasks: [
      {
        key: "maintain_drip_lines",
        phaseKey: "vegetative_growth",
        title: "Maintain drip lines and correct irrigation gaps",
        instructions:
          "Inspect drip lines, clear blockages, and restore pressure across tomato beds.",
        roleRequired: "farmer",
        requiredHeadcount: 2,
        taskType: "workload",
        status: "done",
        startOffsetDays: 18,
        durationDays: 6,
        unitScope: "all",
        dailyLogs: [
          makeDailyLog(18, [1.5, 1.5], {
            notes: "Restored pressure on the first bed line set.",
          }),
          makeDailyLog(19, [1.5, 1.5], {
            notes: "Completed drip maintenance across all beds.",
          }),
        ],
      },
      {
        key: "pick_ripe_tomato_clusters",
        phaseKey: "harvest",
        title: "Pick ripe Cherry Tomato clusters for first harvest release",
        instructions:
          "Harvest ripe clusters, segregate damaged fruit, and deliver picked volume to packing.",
        roleRequired: "farmer",
        requiredHeadcount: 4,
        taskType: "workload",
        status: "in_progress",
        startOffsetDays: 50,
        durationDays: 6,
        unitScope: "all",
        dailyLogs: [
          makeDailyLog(50, [1.5, 1, 1, 0.5], {
            notes: "First harvest pass completed on the ripest beds.",
          }),
          makeDailyLog(51, [0.5, 0.5, 0.5], {
            notes: "Second harvest pass picked remaining ripe sections.",
          }),
        ],
      },
      {
        key: "grade_and_pack_tomatoes",
        phaseKey: "harvest",
        title: "Grade and pack Cherry Tomato harvest into crates",
        instructions:
          "Sort the harvest, reject damaged fruit, and stage crates for dispatch readiness.",
        roleRequired: "inventory_keeper",
        requiredHeadcount: 1,
        taskType: "event",
        status: "in_progress",
        startOffsetDays: 51,
        durationDays: 5,
        unitScope: "none",
        dailyLogs: [
          makeDailyLog(51, [1], {
            notes: "Packing lane opened and first crates labeled.",
          }),
          makeDailyLog(52, [1], {
            notes: "Second packing pass completed after harvest receipt.",
          }),
        ],
      },
      {
        key: "harvest_quality_signoff",
        phaseKey: "harvest",
        title: "Harvest quality signoff and dispatch readiness review",
        instructions:
          "Confirm grade quality, reconcile packed crates, and approve harvest release decisions.",
        roleRequired: "estate_manager",
        requiredHeadcount: 1,
        taskType: "recurring",
        status: "in_progress",
        startOffsetDays: 50,
        durationDays: 6,
        unitScope: "none",
        dailyLogs: [
          makeDailyLog(50, [1], {
            notes: "Quality signoff completed for first crate batch.",
          }),
          makeDailyLog(52, [1], {
            notes: "Dispatch readiness reconfirmed with packing output.",
          }),
        ],
      },
    ],
  };
}

const SCENARIO_BUILDERS = {
  on_track_rice: buildRiceScenario,
  carry_over_pepper: buildPepperScenario,
  harvest_push_tomato: buildTomatoScenario,
};

async function resolveTargetOwner() {
  const ownerQuery = ownerEmail
    ? { email: ownerEmail.toLowerCase(), role: "business_owner" }
    : { role: "business_owner" };

  const owner = await User.findOne(ownerQuery)
    .sort({ createdAt: 1 })
    .select("_id email role businessId name firstName lastName companyName");

  if (!owner) {
    throw new Error(
      ownerEmail
        ? `Business owner ${ownerEmail} not found`
        : "No business_owner account found",
    );
  }

  const { businessId, actor } = await resolveBusinessContext(owner._id, {
    operation: "SimulateProductionPlans",
    route: "scripts/simulate-production-plans",
  });

  return {
    owner: actor,
    businessId,
  };
}

async function resolveEstateAsset({ businessId, owner }) {
  if (estateAssetIdArg) {
    if (!mongoose.Types.ObjectId.isValid(estateAssetIdArg)) {
      throw new Error(`Invalid estate asset id: ${estateAssetIdArg}`);
    }

    const estate = await BusinessAsset.findOne({
      _id: estateAssetIdArg,
      businessId,
      assetType: "estate",
      deletedAt: null,
    }).select("_id name");

    if (!estate) {
      throw new Error(
        `Estate asset ${estateAssetIdArg} not found for business ${businessId}`,
      );
    }

    return {
      estate,
      created: false,
    };
  }

  const existingEstate = await BusinessAsset.findOne({
    businessId,
    assetType: "estate",
    deletedAt: null,
  })
    .sort({ createdAt: 1 })
    .select("_id name");

  if (existingEstate) {
    return {
      estate: existingEstate,
      created: false,
    };
  }

  if (!shouldExecute) {
    return {
      estate: {
        _id: null,
        name: "Virtual Estate (dry-run only)",
      },
      created: true,
    };
  }

  const estate = await BusinessAsset.create({
    businessId,
    assetType: "estate",
    ownershipType: "owned",
    assetClass: "fixed",
    name: `${SIMULATION_PRODUCT_PREFIX} Estate · ${owner.companyName || owner.name || owner.email}`,
    description: "Fallback estate generated for virtual production scenario seeding.",
    location: "Simulation Yard",
    currency: "NGN",
    purchaseCost: 5000000,
    purchaseDate: new Date(2025, 0, 1),
    usefulLifeMonths: 120,
    estate: {
      propertyAddress: {
        houseNumber: "1",
        street: "Simulation Road",
        city: "Lagos",
        state: "Lagos",
        country: "Nigeria",
      },
      unitMix: [
        {
          unitType: "Plot",
          count: 12,
          rentAmount: 100000,
          rentPeriod: "yearly",
        },
      ],
    },
    createdBy: owner._id,
    updatedBy: owner._id,
  });

  return {
    estate,
    created: true,
  };
}

async function resolveStaffPool({ businessId, owner, estateAssetId, scenarios }) {
  const roleRequirements = new Map();

  for (const scenario of scenarios) {
    for (const task of scenario.tasks) {
      const current = roleRequirements.get(task.roleRequired) || 0;
      roleRequirements.set(
        task.roleRequired,
        Math.max(current, task.requiredHeadcount || 1),
      );
    }
  }

  const roles = Array.from(roleRequirements.keys());
  const profiles = await BusinessStaffProfile.find({
    businessId,
    staffRole: { $in: roles },
    status: "active",
  })
    .sort({ createdAt: 1 })
    .select("_id userId staffRole estateAssetId status notes");

  const userIds = profiles.map((profile) => profile.userId).filter(Boolean);
  const users = await User.find({
    _id: { $in: userIds },
  }).select("_id email name firstName lastName");

  const userMap = new Map(users.map((user) => [String(user._id), user]));
  const profilesByRole = new Map(
    roles.map((role) => [
      role,
      profiles
        .filter((profile) => profile.staffRole === role)
        .map((profile) => ({
          ...profile.toObject(),
          user: userMap.get(String(profile.userId)) || null,
          created: false,
        })),
    ]),
  );

  const createdProfiles = [];

  for (const [role, requiredCount] of roleRequirements.entries()) {
    const pool = profilesByRole.get(role) || [];

    while (pool.length < requiredCount) {
      const ordinal = pool.length + 1;
      const simulationIdentity = await ensureSimulationStaff({
        role,
        ordinal,
        businessId,
        owner,
        estateAssetId,
      });

      pool.push(simulationIdentity);
      createdProfiles.push(simulationIdentity);
    }

    profilesByRole.set(role, pool);
  }

  return {
    profilesByRole,
    createdProfiles,
    roleRequirements: Object.fromEntries(roleRequirements),
  };
}

async function ensureSimulationStaff({
  role,
  ordinal,
  businessId,
  owner,
  estateAssetId,
}) {
  const businessSlug = String(businessId).slice(-6).toLowerCase();
  const localPart = `sim.${role}.${ordinal}.${businessSlug}`;
  const email = `${localPart}@adams.local`;

  let user = await User.findOne({ email }).select("_id email name firstName lastName");
  if (!user && shouldExecute) {
    const displayName = `Simulation ${role.replace(/_/g, " ")} ${ordinal}`;
    const passwordHash = await bcrypt.hash(SIMULATION_PASSWORD, 10);
    user = await User.create({
      name: displayName,
      firstName: "Simulation",
      lastName: `${role.replace(/_/g, " ")} ${ordinal}`,
      email,
      passwordHash,
      role: "staff",
      businessId,
      estateAssetId: estateAssetId || null,
      companyName: owner.companyName || owner.name || "Simulation Business",
    });
  }

  let profile = null;
  if (user) {
    profile = await BusinessStaffProfile.findOne({
      userId: user._id,
      businessId,
    }).select("_id userId staffRole estateAssetId status notes");
  }

  if (!profile && shouldExecute && user) {
    profile = await BusinessStaffProfile.create({
      userId: user._id,
      businessId,
      staffRole: role,
      estateAssetId: estateAssetId || null,
      status: "active",
      notes: `${SIMULATION_STAFF_NOTE} role=${role} ordinal=${ordinal}`,
    });
  }

  return {
    _id: profile ? profile._id : null,
    userId: user ? user._id : null,
    staffRole: role,
    estateAssetId: estateAssetId || null,
    status: "active",
    notes: `${SIMULATION_STAFF_NOTE} role=${role} ordinal=${ordinal}`,
    user:
      user && (user.name || user.firstName || user.lastName)
        ? user
        : {
            _id: null,
            email,
            name: `Simulation ${role.replace(/_/g, " ")} ${ordinal}`,
          },
    created: true,
  };
}

async function cleanupExistingSimulationData({ businessId, scenarioKeys }) {
  const businessStaffIds = await BusinessStaffProfile.distinct("_id", { businessId });
  const scenarioMatchers = scenarioKeys.map(
    (key) => new RegExp(`scenario=${key}\\b`),
  );

  const planQuery =
    scenarioMatchers.length === 1
      ? {
          businessId,
          notes: scenarioMatchers[0],
        }
      : {
          businessId,
          $or: scenarioMatchers.map((regex) => ({ notes: regex })),
        };

  const [planIds] = await Promise.all([
    ProductionPlan.distinct("_id", planQuery),
  ]);

  const productsByScenario = await Product.find({
    businessId,
    name: {
      $regex: `^${SIMULATION_PRODUCT_PREFIX.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")} ·`,
    },
  }).select("_id name productionPlanId");

  const filteredProductIds = productsByScenario
    .filter((product) =>
      scenarioKeys.some((key) => product.name.includes(`· ${key} ·`)),
    )
    .map((product) => product._id);

  const allProductIds = Array.from(
    new Set(filteredProductIds.map(String)),
  ).map((id) => new mongoose.Types.ObjectId(id));

  const queries = {
    plans: planIds.length ? { _id: { $in: planIds } } : { _id: { $exists: false } },
    phases: planIds.length ? { planId: { $in: planIds } } : { _id: { $exists: false } },
    tasks: planIds.length ? { planId: { $in: planIds } } : { _id: { $exists: false } },
    units: planIds.length ? { planId: { $in: planIds } } : { _id: { $exists: false } },
    schedules: planIds.length ? { planId: { $in: planIds } } : { _id: { $exists: false } },
    progress: planIds.length ? { planId: { $in: planIds } } : { _id: { $exists: false } },
    outputs: planIds.length ? { planId: { $in: planIds } } : { _id: { $exists: false } },
    products: allProductIds.length
      ? { _id: { $in: allProductIds } }
      : { _id: { $exists: false } },
    attendance: {
      staffProfileId: { $in: businessStaffIds },
      notes: new RegExp(`^${SIMULATION_TAG}`),
    },
    auditLogs: {
      businessId,
      action: "simulation_seed",
    },
    analyticsEvents: {
      businessId,
      eventType: "simulation_plan_seeded",
    },
  };

  const counts = {
    plans: await ProductionPlan.countDocuments(queries.plans),
    phases: await ProductionPhase.countDocuments(queries.phases),
    tasks: await ProductionTask.countDocuments(queries.tasks),
    units: await PlanUnit.countDocuments(queries.units),
    schedules: await ProductionUnitTaskSchedule.countDocuments(queries.schedules),
    progress: await TaskProgress.countDocuments(queries.progress),
    outputs: await ProductionOutput.countDocuments(queries.outputs),
    products: await Product.countDocuments(queries.products),
    attendance: await StaffAttendance.countDocuments(queries.attendance),
    auditLogs: await AuditLog.countDocuments(queries.auditLogs),
    analyticsEvents: await BusinessAnalyticsEvent.countDocuments(queries.analyticsEvents),
  };

  if (!shouldExecute) {
    return {
      deleted: counts,
      queries,
    };
  }

  const deleted = {
    attendance: (await StaffAttendance.deleteMany(queries.attendance)).deletedCount || 0,
    progress: (await TaskProgress.deleteMany(queries.progress)).deletedCount || 0,
    schedules:
      (await ProductionUnitTaskSchedule.deleteMany(queries.schedules)).deletedCount || 0,
    tasks: (await ProductionTask.deleteMany(queries.tasks)).deletedCount || 0,
    phases: (await ProductionPhase.deleteMany(queries.phases)).deletedCount || 0,
    units: (await PlanUnit.deleteMany(queries.units)).deletedCount || 0,
    outputs: (await ProductionOutput.deleteMany(queries.outputs)).deletedCount || 0,
    plans: (await ProductionPlan.deleteMany(queries.plans)).deletedCount || 0,
    products: (await Product.deleteMany(queries.products)).deletedCount || 0,
    auditLogs: (await AuditLog.deleteMany(queries.auditLogs)).deletedCount || 0,
    analyticsEvents:
      (await BusinessAnalyticsEvent.deleteMany(queries.analyticsEvents)).deletedCount || 0,
  };

  return {
    deleted,
    queries,
  };
}

function getAssignedUnitIds(task, planUnits) {
  if (task.unitScope === "none") {
    return [];
  }

  if (Array.isArray(task.unitScope)) {
    return planUnits
      .filter((unit) => task.unitScope.includes(unit.unitIndex))
      .map((unit) => unit._id);
  }

  return planUnits.map((unit) => unit._id);
}

function chooseStaffForTask(task, staffPool) {
  const pool = staffPool.get(task.roleRequired) || [];
  return pool.slice(0, task.requiredHeadcount || 1);
}

function pickAssignedUnitId(unitIds, logIndex) {
  if (!unitIds || unitIds.length === 0) {
    return null;
  }
  return unitIds[Math.min(logIndex, unitIds.length - 1)];
}

async function seedScenario({
  owner,
  businessId,
  estate,
  staffPool,
  scenario,
}) {
  const brand =
    owner.companyName ||
    owner.name ||
    owner.email.split("@")[0];
  const taxonomy = sanitizeProductTaxonomyFields(
    {
      category: scenario.product.category,
      subcategory: scenario.product.subcategory,
      brand,
    },
    { requireBrand: true },
  );
  const selling = sanitizeProductSellingFields(
    {
      sellingOptions: scenario.product.sellingOptions,
    },
    { requireUnits: true },
  );

  const createdProduct = await Product.create({
    businessId,
    createdBy: owner._id,
    updatedBy: owner._id,
    name: scenario.productName,
    description: scenario.product.description,
    ...taxonomy,
    ...selling,
    price: scenario.product.price,
    stock: scenario.product.stock,
    imageUrl: "",
    imageUrls: [],
    imageAssets: [],
    isActive: true,
    productionState:
      scenario.product.productionState || DEFAULT_PRODUCTION_PRODUCT_STATE,
    conservativeYieldQuantity:
      scenario.product.preorderCapQuantity || null,
    conservativeYieldUnit: selling.defaultSellingUnit || "",
    preorderEnabled: scenario.product.preorderEnabled === true,
    preorderStartDate: scenario.product.preorderEnabled
      ? addDays(scenario.endDate, -14)
      : null,
    preorderCapQuantity: scenario.product.preorderCapQuantity || 0,
    preorderReservedQuantity:
      scenario.product.preorderReservedQuantity || 0,
    preorderReleasedQuantity: 0,
  });

  const plan = await ProductionPlan.create({
    businessId,
    estateAssetId: estate._id,
    productId: createdProduct._id,
    title: scenario.title,
    startDate: scenario.startDate,
    endDate: scenario.endDate,
    status: "active",
    createdBy: owner._id,
    notes: scenario.notes,
    aiGenerated: false,
    domainContext: scenario.domainContext,
  });

  createdProduct.productionPlanId = plan._id;
  await createdProduct.save();

  const planUnits = [];
  for (let index = 1; index <= scenario.unitCount; index += 1) {
    planUnits.push({
      planId: plan._id,
      unitIndex: index,
      label: `${scenario.unitLabel} ${index}`,
    });
  }
  const createdPlanUnits = await PlanUnit.insertMany(planUnits);

  const phaseMap = new Map();
  for (const phase of scenario.phases) {
    const createdPhase = await ProductionPhase.create({
      planId: plan._id,
      name: phase.name,
      order: phase.order,
      startDate: phase.startDate,
      endDate: phase.endDate,
      status:
        phase.endDate < startOfLocalDay(new Date()) ? "done" : "in_progress",
      phaseType: phase.phaseType,
      requiredUnits: phase.requiredUnits,
      minRatePerFarmerHour: phase.phaseType === "finite" ? 0.5 : 0.1,
      targetRatePerFarmerHour: phase.phaseType === "finite" ? 1 : 0.2,
      plannedHoursPerDay: phase.phaseType === "finite" ? 4 : 2,
      biologicalMinDays: phase.phaseType === "finite" ? phase.durationDays : 0,
    });

    phaseMap.set(phase.key, createdPhase);
  }

  const attendanceMap = new Map();
  let taskCount = 0;
  let progressCount = 0;
  let scheduleCount = 0;

  for (const taskTemplate of scenario.tasks) {
    const phase = phaseMap.get(taskTemplate.phaseKey);
    const assignedProfiles = chooseStaffForTask(taskTemplate, staffPool);
    const assignedUnitIds = getAssignedUnitIds(
      taskTemplate,
      createdPlanUnits,
    );
    const taskStart = addDays(scenario.startDate, taskTemplate.startOffsetDays);
    const taskDue = addDays(taskStart, taskTemplate.durationDays - 1);
    const recurrenceGroupKey =
      taskTemplate.taskType === "recurring"
        ? `${scenario.key}:${taskTemplate.key}`
        : "";

    const task = await ProductionTask.create({
      planId: plan._id,
      phaseId: phase._id,
      title: taskTemplate.title,
      roleRequired: taskTemplate.roleRequired,
      assignedStaffId: assignedProfiles[0]?._id || null,
      assignedStaffProfileIds: assignedProfiles
        .map((profile) => profile._id)
        .filter(Boolean),
      assignedUnitIds,
      requiredHeadcount: taskTemplate.requiredHeadcount,
      taskType: taskTemplate.taskType || "workload",
      sourceTemplateKey: `${scenario.key}:${taskTemplate.key}`,
      recurrenceGroupKey,
      occurrenceIndex: 0,
      weight: 1,
      startDate: taskStart,
      dueDate: taskDue,
      status: taskTemplate.status,
      completedAt:
        taskTemplate.status === "done" ? dateAtTime(taskDue, 17, 0) : null,
      instructions: taskTemplate.instructions || "",
      dependencies: [],
      createdBy: owner._id,
      approvalStatus: "approved",
      assignedBy: owner._id,
      reviewedBy: owner._id,
      reviewedAt: startOfLocalDay(new Date()),
      rejectionReason: "",
    });
    taskCount += 1;

    if (assignedUnitIds.length > 0) {
      const scheduleRows = assignedUnitIds.map((unitId) => ({
        planId: plan._id,
        taskId: task._id,
        phaseId: phase._id,
        unitId,
        timingMode: "absolute",
        referencePhaseId: phase._id,
        referenceEvent: "phase_start",
        baselineStartDate: taskStart,
        baselineDueDate: taskDue,
        currentStartDate: taskStart,
        currentDueDate: taskDue,
        startOffsetDays: 0,
        dueOffsetDays: taskTemplate.durationDays - 1,
        lastShiftDays: 0,
        lastShiftReason: "",
        lastShiftedByProgressId: null,
      }));
      if (scheduleRows.length > 0) {
        const insertedSchedules = await ProductionUnitTaskSchedule.insertMany(
          scheduleRows,
        );
        scheduleCount += insertedSchedules.length;
      }
    }

    for (const log of taskTemplate.dailyLogs || []) {
      const workDate = addDays(scenario.startDate, log.offset);

      for (let index = 0; index < log.actuals.length; index += 1) {
        const staffProfile = assignedProfiles[index];
        if (!staffProfile?._id) {
          continue;
        }

        const actualPlots = roundTo(log.actuals[index]);
        const expectedPlots = roundTo(
          Array.isArray(log.expecteds) && log.expecteds[index] != null
            ? log.expecteds[index]
            : actualPlots,
        );
        const unitId = pickAssignedUnitId(assignedUnitIds, index);

        await TaskProgress.create({
          taskId: task._id,
          planId: plan._id,
          staffId: staffProfile._id,
          unitId,
          workDate,
          expectedPlots,
          expectedPlotUnits: toPlotUnits(expectedPlots),
          actualPlots,
          actualPlotUnits: toPlotUnits(actualPlots),
          delayReason: log.delayReason || "none",
          notes: `${SIMULATION_TAG} ${scenario.key} ${log.notes || task.title}`,
          createdBy: owner._id,
          approvedBy: owner._id,
          approvedAt: startOfLocalDay(new Date()),
        });
        progressCount += 1;

        const attendanceKey = `${staffProfile._id}:${dateKey(workDate)}`;
        if (!attendanceMap.has(attendanceKey)) {
          attendanceMap.set(attendanceKey, {
            staffProfileId: staffProfile._id,
            clockInAt: dateAtTime(workDate, 8, 0 + index * 10),
            clockOutAt: dateAtTime(workDate, 15, 0 + index * 5),
            durationMinutes: 7 * 60,
            clockInBy: owner._id,
            clockOutBy: owner._id,
            location: estate.name,
            notes: `${SIMULATION_TAG} scenario=${scenario.key} plan=${plan._id.toString()}`,
          });
        }
      }
    }
  }

  const attendanceRows = Array.from(attendanceMap.values());
  if (attendanceRows.length > 0) {
    await StaffAttendance.insertMany(attendanceRows);
  }

  if (Array.isArray(scenario.outputs) && scenario.outputs.length > 0) {
    await ProductionOutput.insertMany(
      scenario.outputs.map((output) => ({
        planId: plan._id,
        productId: createdProduct._id,
        unitType: output.unitType,
        quantity: output.quantity,
        readyForSale: output.readyForSale === true,
        pricePerUnit: output.pricePerUnit || null,
      })),
    );
  }

  await AuditLog.create({
    businessId,
    actor: owner._id,
    actorRole: owner.role,
    action: "simulation_seed",
    entityType: "production_plan",
    entityId: plan._id,
    message: `Seeded virtual production scenario ${scenario.key}`,
    changes: {
      scenarioKey: scenario.key,
      planTitle: scenario.title,
      unitCount: scenario.unitCount,
    },
  });

  await BusinessAnalyticsEvent.create({
    businessId,
    actorId: owner._id,
    actorRole: owner.role,
    eventType: "simulation_plan_seeded",
    entityType: "production_plan",
    entityId: plan._id,
    metadata: {
      simulationTag: SIMULATION_TAG,
      scenarioKey: scenario.key,
      taskCount,
      progressCount,
      attendanceCount: attendanceRows.length,
    },
  });

  return {
    scenarioKey: scenario.key,
    planId: plan._id.toString(),
    productId: createdProduct._id.toString(),
    title: scenario.title,
    taskCount,
    phaseCount: scenario.phases.length,
    unitCount: createdPlanUnits.length,
    scheduleCount,
    progressCount,
    attendanceCount: attendanceRows.length,
    outputCount: Array.isArray(scenario.outputs) ? scenario.outputs.length : 0,
  };
}

function buildDryRunSummary({ owner, businessId, estate, estateCreated, staffPoolResult, scenarios }) {
  return {
    execute: shouldExecute,
    owner: owner.email,
    businessId: String(businessId),
    estate: estate.name,
    wouldCreateEstate: estateCreated,
    staffRequirements: staffPoolResult.roleRequirements,
    wouldCreateStaffProfiles: staffPoolResult.createdProfiles.length,
    scenarios: scenarios.map((scenario) => ({
      key: scenario.key,
      title: scenario.title,
      startDate: dateKey(scenario.startDate),
      endDate: dateKey(scenario.endDate),
      phaseCount: scenario.phases.length,
      taskCount: scenario.tasks.length,
      planUnits: scenario.unitCount,
      progressRows: scenario.tasks.reduce(
        (total, task) =>
          total +
          (task.dailyLogs || []).reduce(
            (sum, log) => sum + (log.actuals?.length || 0),
            0,
          ),
        0,
      ),
      outputs: Array.isArray(scenario.outputs) ? scenario.outputs.length : 0,
    })),
  };
}

async function run() {
  if (shouldShowHelp) {
    printHelp();
    return;
  }

  if (shouldListScenarios) {
    printScenarioList();
    return;
  }

  const scenarioKeys = parseScenarioKeys();
  const scenarioBuilders = scenarioKeys.map((key) => SCENARIO_BUILDERS[key]);

  debug("SIMULATE PRODUCTION PLANS: start", {
    execute: shouldExecute,
    ownerEmail: ownerEmail || null,
    scenarioKeys,
  });

  await connectDB();

  const today = startOfLocalDay(new Date());
  const scenarios = scenarioBuilders.map((builder) => builder(today));
  const { owner, businessId } = await resolveTargetOwner();
  const estateResult = await resolveEstateAsset({
    businessId,
    owner,
  });
  const staffPoolResult = await resolveStaffPool({
    businessId,
    owner,
    estateAssetId: estateResult.estate._id,
    scenarios,
  });
  const cleanupResult = await cleanupExistingSimulationData({
    businessId,
    scenarioKeys,
  });

  if (!shouldExecute) {
    console.log("Virtual production scenario dry run:", {
      cleanup: cleanupResult.deleted,
      summary: buildDryRunSummary({
        owner,
        businessId,
        estate: estateResult.estate,
        estateCreated: estateResult.created,
        staffPoolResult,
        scenarios,
      }),
      nextStep:
        "Re-run with --execute to replace the selected virtual production scenarios.",
    });
    return;
  }

  const created = [];
  for (const scenario of scenarios) {
    const result = await seedScenario({
      owner,
      businessId,
      estate: estateResult.estate,
      staffPool: staffPoolResult.profilesByRole,
      scenario,
    });
    created.push(result);
  }

  console.log("Virtual production scenarios seeded:", {
    execute: shouldExecute,
    owner: owner.email,
    businessId: String(businessId),
    estate: estateResult.estate.name,
    cleanup: cleanupResult.deleted,
    createdStaffProfiles: staffPoolResult.createdProfiles.length,
    scenarios: created,
    loginHint:
      "Open the business production list and look for titles prefixed with 'Virtual Scenario'.",
  });
}

run()
  .catch((error) => {
    console.error("Virtual production scenario seeding failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await mongoose.disconnect();
    } catch (error) {
      console.error("Virtual production scenario disconnect failed:", error.message);
    }
  });
