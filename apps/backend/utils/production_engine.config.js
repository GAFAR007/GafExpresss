/**
 * apps/backend/utils/production_engine.config.js
 * ----------------------------------------------
 * WHAT:
 * - Central engine config for production planning across all business domains.
 *
 * WHY:
 * - Keeps production logic domain-agnostic while allowing lightweight domain bias.
 * - Prevents hard-coded role/domain rules from drifting across services/controllers.
 *
 * HOW:
 * - Exposes canonical staff roles, role responsibility rules, and domain registries.
 * - Provides helpers to normalize and validate optional domain context values.
 */

// WHY: Production domains are optional hints for the engine, not hard constraints.
const PRODUCTION_DOMAIN_CONTEXTS = [
  "farm",
  "fashion",
  "manufacturing",
  "construction",
  "media",
  "food",
  "cosmetics",
  "custom",
];
const DEFAULT_PRODUCTION_DOMAIN_CONTEXT =
  "custom";

// WHY: Product lifecycle states let production and commerce coexist safely.
const PRODUCTION_PRODUCT_STATES = [
  "planned",
  "in_production",
  "available_for_preorder",
  "harvested",
  "in_storage",
  "active_stock",
];
const DEFAULT_PRODUCTION_PRODUCT_STATE =
  "active_stock";

// WHY: Pre-order safety limits should be centralized to avoid over-promising stock.
const DEFAULT_PREORDER_CAP_RATIO =
  0.6;
const PREORDER_CAP_RATIO_MIN = 0.1;
const PREORDER_CAP_RATIO_MAX = 0.9;

// WHY: Humane workload defaults keep AI/planning suggestions realistic.
const HUMANE_WORKLOAD_LIMITS = {
  recommendedPlotsPerFarmerPerDay: 2,
  maxPlotsPerFarmerPerDay: 4,
};
// WHY: Integer plot units prevent floating-point drift when logging partial plot progress (e.g. 0.5 plot).
const PLOT_UNIT_SCALE = 1000;

// WHY: Controlled delay reasons prevent ambiguous "failed" logs.
const PRODUCTION_DELAY_REASONS = [
  "rain",
  "equipment_failure",
  "labour_shortage",
  "health",
  "input_unavailable",
  "management_delay",
];
const PRODUCTION_TASK_PROGRESS_DELAY_REASONS = [
  "none",
  ...PRODUCTION_DELAY_REASONS,
];

// WHY: Canonical staff roles are shared across schema + AI normalization.
const STAFF_ROLES = [
  "asset_manager",
  "farm_manager",
  "estate_manager",
  "accountant",
  "field_agent",
  "cleaner",
  "farmer",
  "inventory_keeper",
  "auditor",
  "security",
  "maintenance_technician",
  "logistics_driver",
];

// WHY: Responsibility tiers help the role resolver favor execution when signals are weak.
const ROLE_RULES = {
  farmer: {
    responsibilities: ["EXECUTION"],
    priority: 1,
  },
  farm_manager: {
    responsibilities: ["SUPERVISION", "PLANNING"],
    priority: 2,
  },
  asset_manager: {
    responsibilities: ["PROCUREMENT", "LOGISTICS"],
    priority: 2,
  },
  inventory_keeper: {
    responsibilities: ["STORAGE", "TRACKING"],
    priority: 1,
  },
  maintenance_technician: {
    responsibilities: ["MAINTENANCE", "REPAIR"],
    priority: 1,
  },
  logistics_driver: {
    responsibilities: ["TRANSPORT"],
    priority: 1,
  },
  estate_manager: {
    responsibilities: ["COMPLIANCE", "APPROVAL", "PLANNING"],
    priority: 3,
  },
  accountant: {
    responsibilities: ["FINANCE", "AUDIT"],
    priority: 3,
  },
  auditor: {
    responsibilities: ["AUDIT"],
    priority: 4,
  },
  security: {
    responsibilities: ["SECURITY"],
    priority: 1,
  },
  cleaner: {
    responsibilities: ["SANITATION"],
    priority: 1,
  },
  field_agent: {
    responsibilities: ["FIELD_SUPPORT"],
    priority: 1,
  },
};

// WHY: Engine-level keywords should remain reusable across all business domains.
const ROLE_KEYWORDS = {
  farmer: ["plant", "weed", "spray", "harvest", "manual", "field"],
  farm_manager: ["supervise", "schedule", "monitor", "plan"],
  asset_manager: ["buy", "order", "procure", "supplier", "vendor"],
  inventory_keeper: ["store", "stock", "warehouse", "inventory"],
  maintenance_technician: ["repair", "fix", "maintain", "machine"],
  logistics_driver: ["transport", "deliver", "haul"],
  estate_manager: ["approve", "report", "compliance", "policy"],
};

// WHY: Domain configs bias suggestions without replacing core engine behavior.
const DOMAIN_CONFIGS = {
  farm: {
    keywords: ["soil", "planting", "harvest", "irrigation"],
    defaultRoles: ["farmer", "farm_manager"],
    defaultOutputs: ["crop_yield"],
    examplePhases: ["Planning", "Planting", "Irrigation", "Harvest", "Storage"],
  },
  fashion: {
    keywords: ["fabric", "cutting", "sewing", "tailoring"],
    defaultRoles: ["asset_manager", "inventory_keeper", "logistics_driver"],
    defaultOutputs: ["garments"],
    examplePhases: ["Planning", "Cutting", "Sewing", "Finishing", "Packaging"],
  },
  manufacturing: {
    keywords: ["assembly", "machine", "production line"],
    defaultRoles: ["maintenance_technician", "inventory_keeper"],
    defaultOutputs: ["units_produced"],
    examplePhases: ["Planning", "Setup", "Assembly", "Quality Check", "Packaging"],
  },
  construction: {
    keywords: ["foundation", "build", "site", "materials"],
    defaultRoles: ["field_agent", "maintenance_technician"],
    defaultOutputs: ["completed_structure"],
    examplePhases: ["Planning", "Site Prep", "Build", "Inspection", "Handover"],
  },
  media: {
    keywords: ["shoot", "edit", "record", "publish"],
    defaultRoles: ["field_agent", "asset_manager"],
    defaultOutputs: ["media_assets"],
    examplePhases: ["Planning", "Production", "Editing", "Review", "Publish"],
  },
  food: {
    keywords: ["cook", "prep", "ingredients", "kitchen"],
    defaultRoles: ["farmer", "inventory_keeper"],
    defaultOutputs: ["meals"],
    examplePhases: ["Planning", "Prep", "Production", "Packaging", "Delivery"],
  },
  cosmetics: {
    keywords: ["formulation", "mixing", "packaging"],
    defaultRoles: ["inventory_keeper", "maintenance_technician"],
    defaultOutputs: ["cosmetic_products"],
    examplePhases: ["Planning", "Formulation", "Mixing", "Packaging", "Storage"],
  },
  custom: {
    keywords: [],
    defaultRoles: [],
    defaultOutputs: [],
    examplePhases: [],
  },
};

function normalizeDomainContext(value) {
  const raw =
    typeof value === "string" ?
      value.trim()
    : "";
  if (!raw) {
    return DEFAULT_PRODUCTION_DOMAIN_CONTEXT;
  }
  const normalized = raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  if (normalized === "generic") {
    // WHY: UI generic maps to the engine's custom domain bucket.
    return DEFAULT_PRODUCTION_DOMAIN_CONTEXT;
  }
  if (PRODUCTION_DOMAIN_CONTEXTS.includes(normalized)) {
    return normalized;
  }
  return DEFAULT_PRODUCTION_DOMAIN_CONTEXT;
}

function isValidDomainContext(value) {
  const raw =
    typeof value === "string" ?
      value.trim()
    : "";
  if (!raw) {
    return true;
  }
  const normalizedRaw = raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return (
    normalizedRaw === "generic" ||
    PRODUCTION_DOMAIN_CONTEXTS.includes(normalizedRaw)
  );
}

module.exports = {
  STAFF_ROLES,
  ROLE_RULES,
  ROLE_KEYWORDS,
  DOMAIN_CONFIGS,
  PRODUCTION_DOMAIN_CONTEXTS,
  DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  PRODUCTION_PRODUCT_STATES,
  DEFAULT_PRODUCTION_PRODUCT_STATE,
  DEFAULT_PREORDER_CAP_RATIO,
  PREORDER_CAP_RATIO_MIN,
  PREORDER_CAP_RATIO_MAX,
  HUMANE_WORKLOAD_LIMITS,
  PLOT_UNIT_SCALE,
  PRODUCTION_DELAY_REASONS,
  PRODUCTION_TASK_PROGRESS_DELAY_REASONS,
  normalizeDomainContext,
  isValidDomainContext,
};
