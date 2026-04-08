/**
 * apps/backend/scripts/simulate-farm-asset-audits.js
 * --------------------------------------------------
 * WHAT:
 * - Seeds a realistic farm equipment/tool register plus backdated audit history.
 *
 * WHY:
 * - Gives the farm audit workspace meaningful data for charts, attention queues,
 *   and asset history without hand-entering assets one by one.
 * - Keeps seeded data isolated so re-runs only replace prior simulation records.
 *
 * HOW:
 * - Resolves a target business owner and farm label.
 * - Removes previously tagged farm-audit simulation assets/logs/events.
 * - Creates farm-scoped BusinessAsset records that follow the current schema
 *   and derives audit cadence state from the same backend model hooks.
 * - Writes matching AuditLog and BusinessAnalyticsEvent history snapshots.
 *
 * USAGE:
 * - npm run ops:farm-audit:simulate
 * - npm run ops:farm-audit:simulate -- --owner-email=owner@example.com
 * - npm run ops:farm-audit:simulate -- --execute
 * - npm run ops:farm-audit:simulate -- --execute --farm-label="Gafars Estate"
 */

const path = require("path");

require("dotenv").config({
  path: path.resolve(__dirname, "..", ".env"),
});

const mongoose = require("mongoose");

const connectDB = require("../config/db");
const debug = require("../utils/debug");
const { resolveBusinessContext } = require("../services/business_context.service");
const businessAssetService = require("../services/business.asset.service");
const User = require("../models/User");
const BusinessAsset = require("../models/BusinessAsset");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const AuditLog = require("../models/AuditLog");
const BusinessAnalyticsEvent = require("../models/BusinessAnalyticsEvent");

const SIMULATION_TAG = "SIMULATION:farm-audit";
const SIMULATION_SERIAL_PREFIX = "SIM-FARM";
const DAY_MS = 24 * 60 * 60 * 1000;
const FARM_APPROVER_STAFF_ROLES = new Set([
  "farm_manager",
  "asset_manager",
  "estate_manager",
]);

const args = process.argv.slice(2);
const shouldExecute = args.includes("--execute");
const shouldShowHelp = args.includes("--help") || args.includes("-h");
const ownerEmailArg = readArg("--owner-email=");
const farmLabelArg = readArg("--farm-label=");

function readArg(prefix) {
  const match = args.find((arg) => arg.startsWith(prefix));
  return match ? match.slice(prefix.length).trim() : "";
}

function buildDisplayName(userDoc) {
  if (!userDoc) {
    return "Staff member";
  }

  const fullName = [userDoc.firstName, userDoc.lastName]
    .filter(Boolean)
    .join(" ")
    .trim();

  return (
    userDoc.name ||
    fullName ||
    userDoc.email ||
    "Staff member"
  );
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

function addMonths(date, months) {
  const next = new Date(date);
  next.setMonth(next.getMonth() + months);
  return startOfLocalDay(next);
}

function addYears(date, years) {
  const next = new Date(date);
  next.setFullYear(next.getFullYear() + years);
  return startOfLocalDay(next);
}

function startOfQuarter(date) {
  const month = Math.floor(date.getMonth() / 3) * 3;
  return new Date(date.getFullYear(), month, 1, 12, 0, 0, 0);
}

function endOfQuarter(date) {
  const start = startOfQuarter(date);
  return new Date(
    start.getFullYear(),
    start.getMonth() + 3,
    0,
    12,
    0,
    0,
    0,
  );
}

function quarterAnchorFromOffset(date, quarterOffset, monthOffset = 1, day = 15) {
  const start = startOfQuarter(date);
  return new Date(
    start.getFullYear(),
    start.getMonth() + quarterOffset * 3 + monthOffset,
    day,
    12,
    0,
    0,
    0,
  );
}

function futureDateInsideCurrentQuarter(date, desiredOffsetDays) {
  const now = startOfLocalDay(date);
  const quarterEnd = endOfQuarter(now);
  const daysRemaining = Math.max(
    1,
    Math.floor((quarterEnd.getTime() - now.getTime()) / DAY_MS),
  );
  const safeOffset = Math.max(
    1,
    Math.min(desiredOffsetDays, Math.max(1, daysRemaining - 1)),
  );
  return addDays(now, safeOffset);
}

function cadenceMonths(auditFrequency) {
  return auditFrequency === "quarterly" ? 3 : 12;
}

function subtractCadence(date, auditFrequency) {
  return addMonths(date, -cadenceMonths(auditFrequency));
}

function toDateKey(date) {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

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

function roundCurrency(value) {
  return Math.round(Number(value) || 0);
}

function formatSimulationDescription(text, key) {
  return `${text} [${SIMULATION_TAG} key=${key}]`;
}

function buildHistoryPattern(finalStatus) {
  switch (finalStatus) {
    case "maintenance":
      return [
        { outcome: "pass", status: "active", issueLevel: "none" },
        { outcome: "watch", status: "active", issueLevel: "monitor" },
        {
          outcome: "maintenance_required",
          status: "maintenance",
          issueLevel: "repair",
        },
      ];
    case "inactive":
      return [
        { outcome: "pass", status: "active", issueLevel: "none" },
        { outcome: "pass", status: "active", issueLevel: "none" },
        { outcome: "retired", status: "inactive", issueLevel: "closed" },
      ];
    default:
      return [
        { outcome: "pass", status: "active", issueLevel: "none" },
        { outcome: "pass", status: "active", issueLevel: "none" },
        { outcome: "pass", status: "active", issueLevel: "none" },
      ];
  }
}

function buildValueTimeline(estimatedCurrentValue, finalStatus) {
  const base = Number(estimatedCurrentValue) || 0;
  if (finalStatus === "maintenance") {
    return [
      roundCurrency(base * 1.18),
      roundCurrency(base * 1.09),
      roundCurrency(base),
    ];
  }
  if (finalStatus === "inactive") {
    return [
      roundCurrency(base * 1.22),
      roundCurrency(base * 1.1),
      roundCurrency(base),
    ];
  }
  return [
    roundCurrency(base * 1.14),
    roundCurrency(base * 1.06),
    roundCurrency(base),
  ];
}

function buildAssetBlueprints({ now, farmLabel }) {
  const dueSoon = futureDateInsideCurrentQuarter(now, 14);
  const dueLaterThisQuarter = futureDateInsideCurrentQuarter(now, 34);
  const nextQuarter = quarterAnchorFromOffset(now, 1, 1, 13);
  const twoQuartersOut = quarterAnchorFromOffset(now, 2, 1, 11);
  const threeQuartersOut = quarterAnchorFromOffset(now, 3, 1, 18);

  return [
    {
      key: "tractor-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-TRC-001`,
      name: "75HP Field Tractor",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "North field machine bay",
      description:
        "Primary tillage and haulage tractor used across open-field operations.",
      farmSection: "North field",
      farmCategory: "machinery",
      farmSubcategory: "tractor",
      auditFrequency: "quarterly",
      nextAuditDate: addDays(now, -21),
      quantity: 1,
      unitOfMeasure: "unit",
      purchaseCost: 28500000,
      usefulLifeMonths: 120,
      purchaseDaysAgo: 620,
      estimatedCurrentValue: 23400000,
      auditNotes: [
        "Commissioned ahead of dry-season land preparation.",
        "Hydraulics calibrated and engine-hour log reconciled.",
        "Brake wear checked after haulage cycle and cleared for service.",
      ],
    },
    {
      key: "harvester-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-HRV-001`,
      name: "Rice Combine Harvester",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "West harvest shed",
      description:
        "Harvest support machine for paddy collection and grain separation.",
      farmSection: "West block",
      farmCategory: "machinery",
      farmSubcategory: "harvester",
      auditFrequency: "quarterly",
      nextAuditDate: dueSoon,
      quantity: 1,
      unitOfMeasure: "unit",
      purchaseCost: 22600000,
      usefulLifeMonths: 96,
      purchaseDaysAgo: 540,
      estimatedCurrentValue: 18250000,
      auditNotes: [
        "Header calibration completed before wet-season operations.",
        "Belt tension rebalanced after throughput test run.",
        "Threshing drum inspected and stored for the next harvest window.",
      ],
    },
    {
      key: "pump-bank-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-IRR-001`,
      name: "Solar Irrigation Pump Bank",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "maintenance",
      location: "Irrigation yard",
      description:
        "Distributed solar pump bank serving vegetable rows and nursery feed lines.",
      farmSection: "Irrigation yard",
      farmCategory: "irrigation",
      farmSubcategory: "pumps",
      auditFrequency: "quarterly",
      nextAuditDate: dueLaterThisQuarter,
      quantity: 4,
      unitOfMeasure: "pumps",
      purchaseCost: 7600000,
      usefulLifeMonths: 72,
      purchaseDaysAgo: 470,
      estimatedCurrentValue: 6180000,
      auditNotes: [
        "Pump output balanced across all distribution lines.",
        "Two inverters cleaned and cable joints resealed.",
        "Pressure drop recorded on one branch; preventive repair opened.",
      ],
    },
    {
      key: "climate-kit-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-UTL-001`,
      name: "Greenhouse Climate Controller Kit",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Protected cropping house",
      description:
        "Sensor and relay kit that monitors ventilation, humidity, and temperature.",
      farmSection: "Greenhouse zone",
      farmCategory: "utilities",
      farmSubcategory: "climate_control",
      auditFrequency: "yearly",
      nextAuditDate: nextQuarter,
      quantity: 12,
      unitOfMeasure: "kits",
      purchaseCost: 2450000,
      usefulLifeMonths: 48,
      purchaseDaysAgo: 860,
      estimatedCurrentValue: 1910000,
      auditNotes: [
        "Initial controller deployment completed for all bays.",
        "Probe accuracy revalidated against manual thermometers.",
        "Firmware and relay response confirmed ahead of the next season.",
      ],
    },
    {
      key: "dryer-line-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-PRC-001`,
      name: "Post-Harvest Solar Dryer Line",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Processing pad",
      description:
        "Drying tunnel line used for herbs, peppers, and seed stock finishing.",
      farmSection: "Processing pad",
      farmCategory: "processing",
      farmSubcategory: "solar_dryer",
      auditFrequency: "yearly",
      nextAuditDate: twoQuartersOut,
      quantity: 2,
      unitOfMeasure: "lines",
      purchaseCost: 5300000,
      usefulLifeMonths: 60,
      purchaseDaysAgo: 1020,
      estimatedCurrentValue: 4190000,
      auditNotes: [
        "Installed with moisture-control ducting and tray racking.",
        "Polycarbonate cover panels replaced after heat retention review.",
        "Airflow tested and drying records matched target throughput.",
      ],
    },
    {
      key: "pruning-kit-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-TOL-001`,
      name: "Hand Pruning and Maintenance Set",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Tool room A",
      description:
        "Shared hand-tool set for pruning, staking, and routine crop maintenance.",
      farmSection: "Tool room A",
      farmCategory: "tools",
      farmSubcategory: "pruning_tools",
      auditFrequency: "quarterly",
      nextAuditDate: addDays(now, -8),
      quantity: 24,
      unitOfMeasure: "sets",
      purchaseCost: 640000,
      usefulLifeMonths: 24,
      purchaseDaysAgo: 280,
      estimatedCurrentValue: 485000,
      auditNotes: [
        "Initial tool issue register created for field crews.",
        "Blade sharpening and handle replacements completed mid-cycle.",
        "Two sets flagged for missing parts and replenishment requested.",
      ],
    },
    {
      key: "moisture-meter-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-TOL-002`,
      name: "Portable Grain Moisture Meter Batch",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Warehouse QA desk",
      description:
        "Portable meters used by storekeepers for drying and storage quality checks.",
      farmSection: "Warehouse QA",
      farmCategory: "tools",
      farmSubcategory: "meters",
      auditFrequency: "yearly",
      nextAuditDate: threeQuartersOut,
      quantity: 8,
      unitOfMeasure: "meters",
      purchaseCost: 920000,
      usefulLifeMonths: 36,
      purchaseDaysAgo: 710,
      estimatedCurrentValue: 705000,
      auditNotes: [
        "Meters commissioned for warehouse moisture validation.",
        "Calibration offsets aligned with reference samples.",
        "Battery health and sensor response passed the annual check.",
      ],
    },
    {
      key: "crate-pool-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-STG-001`,
      name: "Harvest Crate Pool",
      assetType: "inventory_asset",
      ownershipType: "owned",
      assetClass: "current",
      status: "active",
      location: "Cold room staging area",
      description:
        "Reusable field crates for harvest staging, grading, and dispatch transfer.",
      farmSection: "Dispatch staging",
      farmCategory: "storage",
      farmSubcategory: "crates",
      auditFrequency: "yearly",
      nextAuditDate: quarterAnchorFromOffset(now, 2, 0, 8),
      quantity: 140,
      unitOfMeasure: "crates",
      purchaseCost: 1680000,
      usefulLifeMonths: 24,
      purchaseDaysAgo: 430,
      estimatedCurrentValue: 1260000,
      auditNotes: [
        "Reusable crate pool issued for harvest logistics.",
        "Broken handles replaced after dispatch reconciliation.",
        "Damaged units isolated and stack-count variance resolved.",
      ],
    },
    {
      key: "pickup-fleet-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-TRN-001`,
      name: "Farm Pickup Fleet",
      assetType: "vehicle",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Transport yard",
      description:
        "Light-duty pickups for input runs, field supervision, and produce movement.",
      farmSection: "Transport yard",
      farmCategory: "transport",
      farmSubcategory: "pickup",
      auditFrequency: "quarterly",
      nextAuditDate: nextQuarter,
      quantity: 2,
      unitOfMeasure: "vehicles",
      purchaseCost: 14800000,
      usefulLifeMonths: 84,
      purchaseDaysAgo: 790,
      estimatedCurrentValue: 11250000,
      auditNotes: [
        "Fleet registered for staff movement and light logistics.",
        "Tyres rotated and service intervals aligned after peak usage.",
        "Fuel variance reviewed against trip sheets and resolved.",
      ],
    },
    {
      key: "ppe-locker-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-SFT-001`,
      name: "PPE Locker and Harness Inventory",
      assetType: "inventory_asset",
      ownershipType: "owned",
      assetClass: "current",
      status: "inactive",
      location: "Safety room",
      description:
        "Safety lockers, harness kits, and reserve PPE packs for hazardous work zones.",
      farmSection: "Safety room",
      farmCategory: "safety",
      farmSubcategory: "ppe",
      auditFrequency: "yearly",
      nextAuditDate: addDays(now, -45),
      quantity: 36,
      unitOfMeasure: "kits",
      purchaseCost: 1350000,
      usefulLifeMonths: 24,
      purchaseDaysAgo: 900,
      estimatedCurrentValue: 690000,
      auditNotes: [
        "Safety kits issued for chemical handling and elevated work tasks.",
        "Replacement harness packs procured after compliance review.",
        "Legacy locker stock retired after serial mismatch and expiry check.",
      ],
    },
    {
      key: "fertigation-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-IRR-002`,
      name: "Fertigation Dosing Unit",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "maintenance",
      location: "Drip-control shed",
      description:
        "Nutrient dosing controller tied to drip irrigation and greenhouse feed tanks.",
      farmSection: "Drip-control shed",
      farmCategory: "irrigation",
      farmSubcategory: "fertigation",
      auditFrequency: "yearly",
      nextAuditDate: dueSoon,
      quantity: 1,
      unitOfMeasure: "unit",
      purchaseCost: 3100000,
      usefulLifeMonths: 60,
      purchaseDaysAgo: 780,
      estimatedCurrentValue: 2250000,
      auditNotes: [
        "Controller installed with dual-feed calibration sheet.",
        "Flow-rate accuracy rechecked after nutrient blend change.",
        "Injection variance exceeded tolerance and service ticket opened.",
      ],
    },
    {
      key: "generator-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-UTL-002`,
      name: "Workshop Backup Generator Set",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Workshop service bay",
      description:
        "Backup generator that supports repairs, welding, and cold-room fallback.",
      farmSection: "Workshop bay",
      farmCategory: "utilities",
      farmSubcategory: "generator",
      auditFrequency: "quarterly",
      nextAuditDate: twoQuartersOut,
      quantity: 1,
      unitOfMeasure: "unit",
      purchaseCost: 4200000,
      usefulLifeMonths: 72,
      purchaseDaysAgo: 510,
      estimatedCurrentValue: 3320000,
      auditNotes: [
        "Generator commissioned for workshop and cold-chain backup.",
        "Filter pack replaced after high-load maintenance window.",
        "Runtime log balanced against diesel stock and standby tests.",
      ],
    },
  ].map((blueprint) => ({
    ...blueprint,
    farmLabel,
  }));
}

function buildPendingAssetBlueprints({ now, farmLabel }) {
  return [
    {
      key: "pending-sprayer-rack-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-PND-001`,
      name: "Battery Orchard Sprayer Rack",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Orchard input cage",
      description:
        "Recently delivered battery sprayer rack waiting for manager verification before issue to field crews.",
      farmSection: "Orchard block",
      farmCategory: "tools",
      farmSubcategory: "sprayer",
      auditFrequency: "quarterly",
      quantity: 6,
      unitOfMeasure: "sprayers",
      purchaseCost: 1180000,
      usefulLifeMonths: 24,
      purchaseDaysAgo: 45,
      estimatedCurrentValue: 1020000,
    },
    {
      key: "pending-seed-drill-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-PND-002`,
      name: "Mounted Seed Drill Attachment",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "North field machine bay",
      description:
        "Seed drill attachment submitted by staff and waiting for equipment approval before deployment.",
      farmSection: "North field",
      farmCategory: "machinery",
      farmSubcategory: "seeder",
      auditFrequency: "yearly",
      quantity: 1,
      unitOfMeasure: "unit",
      purchaseCost: 3850000,
      usefulLifeMonths: 72,
      purchaseDaysAgo: 18,
      estimatedCurrentValue: 3690000,
    },
    {
      key: "pending-cold-chain-logger-001",
      serialNumber: `${SIMULATION_SERIAL_PREFIX}-PND-003`,
      name: "Cold-Chain Sensor Logger Kit",
      assetType: "equipment",
      ownershipType: "owned",
      assetClass: "fixed",
      status: "active",
      location: "Packhouse cold room",
      description:
        "Logger kit awaiting approval so the storage team can start seasonal audit tracking.",
      farmSection: "Cold room",
      farmCategory: "utilities",
      farmSubcategory: "sensor_kit",
      auditFrequency: "yearly",
      quantity: 4,
      unitOfMeasure: "kits",
      purchaseCost: 1540000,
      usefulLifeMonths: 36,
      purchaseDaysAgo: 9,
      estimatedCurrentValue: 1490000,
    },
  ].map((blueprint, index) => ({
    ...blueprint,
    farmLabel,
    purchaseDate: addDays(now, -blueprint.purchaseDaysAgo),
    lastAuditDate: addDays(now, -(index + 1) * 12),
  }));
}

function buildAuditSnapshots(blueprint, purchaseDate) {
  const lastAuditDate = subtractCadence(
    blueprint.nextAuditDate,
    blueprint.auditFrequency,
  );
  const middleAuditDate = subtractCadence(
    lastAuditDate,
    blueprint.auditFrequency,
  );
  const firstAuditDate = subtractCadence(
    middleAuditDate,
    blueprint.auditFrequency,
  );

  const pattern = buildHistoryPattern(blueprint.status);
  const values = buildValueTimeline(
    blueprint.estimatedCurrentValue,
    blueprint.status,
  );
  const notes = blueprint.auditNotes || [];

  const rawSnapshots = [firstAuditDate, middleAuditDate, lastAuditDate].map(
    (auditDate, index) => ({
      auditDate,
      nextAuditDate: addMonths(
        auditDate,
        cadenceMonths(blueprint.auditFrequency),
      ),
      estimatedCurrentValue: values[index] || values[values.length - 1],
      note:
        notes[index] ||
        `Farm audit check ${index + 1} completed for ${blueprint.name}.`,
      outcome: pattern[index]?.outcome || "pass",
      status: pattern[index]?.status || blueprint.status,
      issueLevel: pattern[index]?.issueLevel || "none",
    })
  );

  const minimumHistoryDate = addDays(purchaseDate, 21);
  const filteredSnapshots = rawSnapshots.filter(
    (snapshot) => snapshot.auditDate >= minimumHistoryDate,
  );

  return filteredSnapshots.length > 0
    ? filteredSnapshots
    : [rawSnapshots[rawSnapshots.length - 1]];
}

async function resolveTargetOwner() {
  const ownerQuery = ownerEmailArg
    ? { email: ownerEmailArg.toLowerCase(), role: "business_owner" }
    : { role: "business_owner" };

  const ownerDoc = await User.findOne(ownerQuery)
    .sort({ createdAt: 1 })
    .select("_id email role businessId name firstName lastName companyName");

  if (!ownerDoc) {
    throw new Error(
      ownerEmailArg
        ? `Business owner ${ownerEmailArg} not found`
        : "No business_owner account found",
    );
  }

  const { businessId, actor } = await resolveBusinessContext(ownerDoc._id, {
    operation: "SimulateFarmAssetAudits",
    route: "scripts/simulate-farm-asset-audits",
  });

  return {
    owner: {
      ...ownerDoc.toObject(),
      ...actor.toObject(),
    },
    businessId,
  };
}

async function resolveBusinessStaffActors({
  businessId,
}) {
  const staffProfiles =
    await BusinessStaffProfile.find({
      businessId,
      status: "active",
    })
      .populate({
        path: "userId",
        select:
          "_id name firstName lastName email role businessId",
      })
      .sort({ createdAt: 1 });

  const actors = staffProfiles
    .map((profile) => {
      const userDoc = profile.userId;
      if (!userDoc || !userDoc._id) {
        return null;
      }

      return {
        id: userDoc._id,
        name: buildDisplayName(userDoc),
        email: userDoc.email || "",
        role: userDoc.role || "staff",
        staffRole: profile.staffRole || "",
        staffProfileId: profile._id,
      };
    })
    .filter((actor) => actor && actor.role === "staff");

  const approvers = actors.filter((actor) =>
    FARM_APPROVER_STAFF_ROLES.has(actor.staffRole)
  );
  const requesters = actors.filter(
    (actor) => !FARM_APPROVER_STAFF_ROLES.has(actor.staffRole),
  );

  return {
    all: actors,
    approvers,
    requesters,
  };
}

async function resolveFarmLabel({ businessId, owner }) {
  if (farmLabelArg) {
    return farmLabelArg;
  }

  const estate = await BusinessAsset.findOne({
    businessId,
    assetType: "estate",
    deletedAt: null,
  })
    .sort({ createdAt: 1 })
    .select("name");

  if (estate?.name) {
    return estate.name;
  }

  const ownerLabel =
    owner.companyName ||
    owner.name ||
    owner.email?.split("@")[0] ||
    "Main";

  return `${ownerLabel} Farm`;
}

async function collectSimulationQueries({ businessId }) {
  const assetQuery = {
    businessId,
    domainContext: "farm",
    serialNumber: { $regex: `^${SIMULATION_SERIAL_PREFIX}` },
  };
  const assetIds = await BusinessAsset.distinct("_id", assetQuery);

  return {
    assetIds,
    queries: {
      assets: assetQuery,
      auditLogs: buildOrQuery([
        assetIds.length
          ? {
              entityType: "business_asset",
              entityId: { $in: assetIds },
            }
          : null,
        {
          businessId,
          "changes.simulationTag": SIMULATION_TAG,
        },
        {
          businessId,
          message: new RegExp(SIMULATION_TAG),
        },
      ]),
      analyticsEvents: buildOrQuery([
        assetIds.length
          ? {
              entityType: "business_asset",
              entityId: { $in: assetIds },
            }
          : null,
        {
          businessId,
          "metadata.simulationTag": SIMULATION_TAG,
        },
      ]),
    },
  };
}

async function cleanupExistingSimulationData({ businessId }) {
  const { queries } = await collectSimulationQueries({ businessId });

  const counts = {
    assets: await BusinessAsset.countDocuments(queries.assets),
    auditLogs: await AuditLog.countDocuments(queries.auditLogs),
    analyticsEvents: await BusinessAnalyticsEvent.countDocuments(
      queries.analyticsEvents,
    ),
  };

  if (!shouldExecute) {
    return {
      deleted: counts,
      queries,
    };
  }

  const deleted = {
    auditLogs: (await AuditLog.deleteMany(queries.auditLogs)).deletedCount || 0,
    analyticsEvents:
      (await BusinessAnalyticsEvent.deleteMany(queries.analyticsEvents))
        .deletedCount || 0,
    assets: (await BusinessAsset.deleteMany(queries.assets)).deletedCount || 0,
  };

  return {
    deleted,
    queries,
  };
}

async function backdateDocument(model, documentId, timestamp) {
  await model.collection.updateOne(
    { _id: documentId },
    {
      $set: {
        createdAt: timestamp,
        updatedAt: timestamp,
      },
    },
  );
}

async function createAuditLogEntry({
  businessId,
  owner,
  asset,
  message,
  action,
  changes,
  timestamp,
}) {
  const entry = await AuditLog.create({
    businessId,
    actor: owner._id,
    actorRole: owner.role,
    action,
    entityType: "business_asset",
    entityId: asset._id,
    message,
    changes: {
      simulationTag: SIMULATION_TAG,
      ...changes,
    },
  });

  await backdateDocument(AuditLog, entry._id, timestamp);
  return entry;
}

async function createAnalyticsEventEntry({
  businessId,
  owner,
  asset,
  eventType,
  metadata,
  timestamp,
}) {
  const entry = await BusinessAnalyticsEvent.create({
    businessId,
    actorId: owner._id,
    actorRole: owner.role,
    eventType,
    entityType: "business_asset",
    entityId: asset._id,
    metadata: {
      simulationTag: SIMULATION_TAG,
      ...metadata,
    },
  });

  await backdateDocument(
    BusinessAnalyticsEvent,
    entry._id,
    timestamp,
  );
  return entry;
}

async function seedBlueprint({ businessId, owner, blueprint }) {
  const purchaseDate = addDays(
    startOfLocalDay(new Date()),
    -blueprint.purchaseDaysAgo,
  );
  const auditSnapshots = buildAuditSnapshots(
    blueprint,
    purchaseDate,
  );
  const lastAuditSnapshot = auditSnapshots[auditSnapshots.length - 1];
  const assetBackdate = addDays(purchaseDate, 1);
  const actorSnapshot = {
    userId: owner._id,
    name:
      owner.name ||
      owner.companyName ||
      owner.email ||
      "Business owner",
    actorRole: owner.role,
    staffRole: "",
    email: owner.email || "",
  };

  const asset = await BusinessAsset.create({
    businessId,
    assetType: blueprint.assetType,
    ownershipType: blueprint.ownershipType,
    assetClass: blueprint.assetClass,
    name: blueprint.name,
    description: formatSimulationDescription(
      blueprint.description,
      blueprint.key,
    ),
    serialNumber: blueprint.serialNumber,
    status: blueprint.status,
    location: blueprint.location,
    currency: "NGN",
    domainContext: "farm",
    approvalStatus: "approved",
    approvalRequestedBy: actorSnapshot,
    approvalRequestedAt: assetBackdate,
    approvalReviewedBy: actorSnapshot,
    approvalReviewedAt: assetBackdate,
    approvalNote: "approved_on_submission",
    purchaseCost: blueprint.purchaseCost,
    purchaseDate,
    usefulLifeMonths: blueprint.usefulLifeMonths,
    salvageValue: 0,
    createdBy: owner._id,
    updatedBy: owner._id,
    inventory:
      blueprint.assetClass === "current"
        ? {
            quantity: blueprint.quantity,
            unitCost: Math.max(
              1,
              roundCurrency(
                blueprint.purchaseCost / Math.max(1, blueprint.quantity),
              ),
            ),
            reorderLevel: Math.max(1, Math.round(blueprint.quantity * 0.1)),
            unitOfMeasure: blueprint.unitOfMeasure,
          }
        : undefined,
    farmProfile: {
      attachedFarmLabel: blueprint.farmLabel,
      farmSection: blueprint.farmSection,
      farmCategory: blueprint.farmCategory,
      farmSubcategory: blueprint.farmSubcategory,
      auditFrequency: blueprint.auditFrequency,
      lastAuditDate: lastAuditSnapshot.auditDate,
      quantity: blueprint.quantity,
      unitOfMeasure: blueprint.unitOfMeasure,
      estimatedCurrentValue: lastAuditSnapshot.estimatedCurrentValue,
      lastAuditSubmittedBy: actorSnapshot,
      lastAuditSubmittedAt: lastAuditSnapshot.auditDate,
      lastAuditNote: lastAuditSnapshot.note,
    },
  });
  await backdateDocument(
    BusinessAsset,
    asset._id,
    assetBackdate,
  );

  await createAuditLogEntry({
    businessId,
    owner,
    asset,
    action: "asset_create",
    message: `Asset created: ${asset.name} (${SIMULATION_TAG})`,
    timestamp: assetBackdate,
    changes: {
      source: "simulation_seed",
      assetType: asset.assetType,
      status: "active",
      farmCategory: blueprint.farmCategory,
      farmSection: blueprint.farmSection,
    },
  });

  await createAnalyticsEventEntry({
    businessId,
    owner,
    asset,
    eventType: "asset_created",
    timestamp: assetBackdate,
    metadata: {
      source: "simulation_seed",
      assetType: asset.assetType,
      status: "active",
      farmCategory: blueprint.farmCategory,
      auditFrequency: blueprint.auditFrequency,
      estimatedCurrentValue: blueprint.purchaseCost,
    },
  });

  let previousSnapshot = {
    status: "active",
    estimatedCurrentValue: blueprint.purchaseCost,
    lastAuditDate: null,
    nextAuditDate: null,
  };

  for (const snapshot of auditSnapshots) {
    await createAuditLogEntry({
      businessId,
      owner,
      asset,
      action: "asset_update",
      message: `Farm audit recorded: ${asset.name} (${SIMULATION_TAG})`,
      timestamp: snapshot.auditDate,
      changes: {
        source: "simulation_farm_audit",
        before: previousSnapshot,
        after: {
          status: snapshot.status,
          estimatedCurrentValue: snapshot.estimatedCurrentValue,
          lastAuditDate: snapshot.auditDate,
          nextAuditDate: snapshot.nextAuditDate,
        },
        auditSnapshot: {
          auditDate: snapshot.auditDate,
          nextAuditDate: snapshot.nextAuditDate,
          outcome: snapshot.outcome,
          issueLevel: snapshot.issueLevel,
          auditFrequency: blueprint.auditFrequency,
          farmCategory: blueprint.farmCategory,
          farmSection: blueprint.farmSection,
          notes: snapshot.note,
        },
      },
    });

    await createAnalyticsEventEntry({
      businessId,
      owner,
      asset,
      eventType: "asset_updated",
      timestamp: snapshot.auditDate,
      metadata: {
        source: "simulation_farm_audit",
        updateReason: "farm_audit",
        assetType: asset.assetType,
        status: snapshot.status,
        farmCategory: blueprint.farmCategory,
        farmSection: blueprint.farmSection,
        auditFrequency: blueprint.auditFrequency,
        auditOutcome: snapshot.outcome,
        issueLevel: snapshot.issueLevel,
        estimatedCurrentValue: snapshot.estimatedCurrentValue,
        nextAuditDate: snapshot.nextAuditDate,
      },
    });

    previousSnapshot = {
      status: snapshot.status,
      estimatedCurrentValue: snapshot.estimatedCurrentValue,
      lastAuditDate: snapshot.auditDate,
      nextAuditDate: snapshot.nextAuditDate,
    };
  }

  await BusinessAsset.collection.updateOne(
    { _id: asset._id },
    {
      $set: {
        updatedAt: lastAuditSnapshot.auditDate,
      },
    },
  );

  return {
    id: asset._id.toString(),
    serialNumber: blueprint.serialNumber,
    name: blueprint.name,
    category: blueprint.farmCategory,
    cadence: blueprint.auditFrequency,
    status: blueprint.status,
    quantity: blueprint.quantity,
    nextAuditDate: toDateKey(blueprint.nextAuditDate),
    lastAuditDate: toDateKey(lastAuditSnapshot.auditDate),
    auditEntryCount: auditSnapshots.length,
  };
}

function pickStaffActor(staffPool, index) {
  if (!Array.isArray(staffPool) || staffPool.length === 0) {
    return null;
  }
  return staffPool[index % staffPool.length];
}

function buildPendingAssetPayload(blueprint) {
  return {
    assetType: blueprint.assetType,
    ownershipType: blueprint.ownershipType,
    assetClass: blueprint.assetClass,
    name: blueprint.name,
    description: formatSimulationDescription(
      blueprint.description,
      blueprint.key,
    ),
    serialNumber: blueprint.serialNumber,
    status: blueprint.status,
    location: blueprint.location,
    currency: "NGN",
    purchaseCost: blueprint.purchaseCost,
    purchaseDate: blueprint.purchaseDate,
    usefulLifeMonths: blueprint.usefulLifeMonths,
    domainContext: "farm",
    farmProfile: {
      attachedFarmLabel: blueprint.farmLabel,
      farmSection: blueprint.farmSection,
      farmCategory: blueprint.farmCategory,
      farmSubcategory: blueprint.farmSubcategory,
      auditFrequency: blueprint.auditFrequency,
      lastAuditDate: blueprint.lastAuditDate,
      quantity: blueprint.quantity,
      unitOfMeasure: blueprint.unitOfMeasure,
      estimatedCurrentValue: blueprint.estimatedCurrentValue,
    },
  };
}

function buildPendingAuditPlans({ now, assets }) {
  const assetMap = new Map(
    assets.map((asset) => [asset.name, asset]),
  );

  return [
    {
      asset: assetMap.get("75HP Field Tractor") || assets[0],
      resultingStatus: "maintenance",
      estimatedValueFactor: 0.92,
      auditDate: addDays(now, -2),
      note:
        "Field operator submitted a vibration review after the latest tillage round.",
    },
    {
      asset:
        assetMap.get("Hand Pruning and Maintenance Set") || assets[1],
      resultingStatus: "active",
      estimatedValueFactor: 0.96,
      auditDate: addDays(now, -1),
      note:
        "Tool room reconciliation completed and one crew requested the audit sign-off.",
    },
    {
      asset:
        assetMap.get("Workshop Backup Generator Set") || assets[2],
      resultingStatus: "maintenance",
      estimatedValueFactor: 0.9,
      auditDate: startOfLocalDay(now),
      note:
        "Workshop technician flagged service-hour overrun and requested manager review.",
    },
  ].filter((plan) => plan.asset?._id);
}

async function seedPendingActivity({
  businessId,
  farmLabel,
  staffActors,
  approvedAssets,
  now,
}) {
  const requesterPool = staffActors.requesters || [];

  if (requesterPool.length === 0) {
    return {
      pendingAssets: [],
      pendingAudits: [],
      warning:
        "No active non-manager staff profiles were found, so pending workflow items were skipped.",
    };
  }

  const pendingAssets = [];
  const pendingAssetBlueprints = buildPendingAssetBlueprints({
    now,
    farmLabel,
  });

  for (let index = 0; index < pendingAssetBlueprints.length; index += 1) {
    const blueprint = pendingAssetBlueprints[index];
    const actor = pickStaffActor(requesterPool, index);
    if (!actor) {
      continue;
    }

    const asset = await businessAssetService.submitFarmAsset({
      businessId,
      actor,
      payload: buildPendingAssetPayload(blueprint),
    });

    pendingAssets.push({
      id: asset._id.toString(),
      serialNumber: asset.serialNumber,
      name: asset.name,
      category: asset.farmProfile?.farmCategory || "",
      approvalStatus: asset.approvalStatus,
      requestedBy: actor.name,
      requestedByRole: actor.staffRole,
    });
  }

  const pendingAudits = [];
  const pendingAuditPlans = buildPendingAuditPlans({
    now,
    assets: approvedAssets,
  });

  for (let index = 0; index < pendingAuditPlans.length; index += 1) {
    const plan = pendingAuditPlans[index];
    const actor = pickStaffActor(requesterPool, index + pendingAssets.length);
    if (!actor || !plan.asset?._id) {
      continue;
    }

    const currentValue =
      Number(plan.asset.farmProfile?.estimatedCurrentValue) ||
      Number(plan.asset.purchaseCost) ||
      0;
    const updatedAsset =
      await businessAssetService.submitFarmAssetAudit({
        businessId,
        assetId: plan.asset._id,
        actor,
        payload: {
          auditDate: plan.auditDate,
          status: plan.resultingStatus,
          estimatedCurrentValue: roundCurrency(
            currentValue * plan.estimatedValueFactor,
          ),
          note: `${plan.note} [${SIMULATION_TAG}]`,
        },
      });

    pendingAudits.push({
      id: updatedAsset._id.toString(),
      name: updatedAsset.name,
      requestedBy: actor.name,
      requestedByRole: actor.staffRole,
      auditDate: toDateKey(plan.auditDate),
      requestedStatus: plan.resultingStatus,
    });
  }

  return {
    pendingAssets,
    pendingAudits,
    warning: null,
  };
}

function buildDryRunSummary({
  owner,
  businessId,
  farmLabel,
  blueprints,
  staffActors,
}) {
  return {
    execute: false,
    owner: owner.email,
    businessId: String(businessId),
    farmLabel,
    assetCount: blueprints.length,
    activeStaffCount: staffActors.all.length,
    pendingRequesterCount: staffActors.requesters.length,
    approverCount: staffActors.approvers.length,
    assets: blueprints.map((blueprint) => {
      const lastAuditDate = subtractCadence(
        blueprint.nextAuditDate,
        blueprint.auditFrequency,
      );
      return {
        serialNumber: blueprint.serialNumber,
        name: blueprint.name,
        category: blueprint.farmCategory,
        cadence: blueprint.auditFrequency,
        status: blueprint.status,
        quantity: blueprint.quantity,
        lastAuditDate: toDateKey(lastAuditDate),
        nextAuditDate: toDateKey(blueprint.nextAuditDate),
      };
    }),
    pendingWorkflowPreview: {
      pendingAssetSubmissions: buildPendingAssetBlueprints({
        now: startOfLocalDay(new Date()),
        farmLabel,
      }).length,
      pendingAuditRequests: 3,
    },
  };
}

function printHelp() {
  console.log(`
Farm asset audit simulator

Usage:
  node scripts/simulate-farm-asset-audits.js [options]

Options:
  --execute                Write records. Dry-run is the default.
  --owner-email=<email>    Target a specific business owner. Defaults to first business_owner.
  --farm-label=<label>     Override the attached farm label used for all seeded assets.
  --help                   Show this help and exit.

Examples:
  npm run ops:farm-audit:simulate
  npm run ops:farm-audit:simulate -- --owner-email=owner@example.com
  npm run ops:farm-audit:simulate -- --execute --farm-label="Gafars Estate"
  `);
}

async function run() {
  if (shouldShowHelp) {
    printHelp();
    return;
  }

  debug("SIMULATE FARM ASSET AUDITS: start", {
    execute: shouldExecute,
    ownerEmail: ownerEmailArg || null,
    farmLabel: farmLabelArg || null,
  });

  if (!process.env.MONGO_URI) {
    throw new Error("MONGO_URI is required before seeding farm audit data.");
  }

  await connectDB();

  const now = startOfLocalDay(new Date());
  const { owner, businessId } = await resolveTargetOwner();
  const staffActors = await resolveBusinessStaffActors({
    businessId,
  });
  const farmLabel = await resolveFarmLabel({
    businessId,
    owner,
  });
  const blueprints = buildAssetBlueprints({
    now,
    farmLabel,
  });
  const cleanupResult = await cleanupExistingSimulationData({
    businessId,
  });

  if (!shouldExecute) {
    console.log("Farm asset audit simulation dry run:", {
      cleanup: cleanupResult.deleted,
      summary: buildDryRunSummary({
        owner,
        businessId,
        farmLabel,
        blueprints,
        staffActors,
      }),
      nextStep:
        "Re-run with --execute to replace the tagged farm audit simulation records.",
    });
    return;
  }

  const created = [];
  for (const blueprint of blueprints) {
    created.push(
      await seedBlueprint({
        businessId,
        owner,
        blueprint,
      }),
    );
  }

  const approvedAssets =
    await BusinessAsset.find({
      businessId,
      domainContext: "farm",
      deletedAt: null,
      approvalStatus: "approved",
      serialNumber: {
        $regex: `^${SIMULATION_SERIAL_PREFIX}`,
      },
    }).sort({ createdAt: 1 });

  const pendingWorkflow =
    await seedPendingActivity({
      businessId,
      farmLabel,
      staffActors,
      approvedAssets,
      now,
    });

  console.log("Farm asset audit simulation seeded:", {
    execute: true,
    owner: owner.email,
    businessId: String(businessId),
    farmLabel,
    staffActors: {
      total: staffActors.all.length,
      requesters: staffActors.requesters.map((actor) => ({
        name: actor.name,
        staffRole: actor.staffRole,
      })),
      approvers: staffActors.approvers.map((actor) => ({
        name: actor.name,
        staffRole: actor.staffRole,
      })),
    },
    cleanup: cleanupResult.deleted,
    createdAssets: created.length,
    auditHistoryRows: created.reduce(
      (sum, item) => sum + item.auditEntryCount,
      0,
    ),
    created,
    pendingAssetSubmissions: pendingWorkflow.pendingAssets,
    pendingAuditRequests: pendingWorkflow.pendingAudits,
    warning: pendingWorkflow.warning,
    loginHint:
      "Open Business Assets > Farm audit to view the seeded register, charts, and audit queue.",
  });
}

run()
  .catch((error) => {
    console.error("Farm asset audit simulation failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await mongoose.disconnect();
    } catch (error) {
      console.error("Farm asset audit disconnect failed:", error.message);
    }
  });
