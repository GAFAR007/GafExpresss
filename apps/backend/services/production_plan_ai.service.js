/**
 * apps/backend/services/production_plan_ai.service.js
 * ---------------------------------------------------
 * WHAT:
 * - AI draft generator for production plans (phases + tasks + summary).
 *
 * WHY:
 * - Centralizes prompt building, strict-schema parsing, and normalization.
 * - Keeps controllers small and prevents duplicated AI orchestration.
 *
 * HOW:
 * - Builds a structured prompt with plan context and optional assistant input.
 * - Calls the shared AI client (Groq now; pluggable provider via ai.service).
 * - Normalizes AI output into a strict, frontend-safe draft object.
 */

const debug = require("../utils/debug");
const {
  createAiChatCompletion,
} = require("./ai.service");
const { AI_BASE_URL } = require("../config/ai");
const {
  STAFF_ROLES,
  ROLE_RULES,
  ROLE_KEYWORDS,
  DOMAIN_CONFIGS,
  PRODUCTION_DOMAIN_CONTEXTS,
  DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  normalizeDomainContext,
} = require("../utils/production_engine.config");
const {
  DEFAULT_PRODUCTION_PHASES,
} = require("../utils/production_defaults");

// WHY: Centralize logging labels for AI draft generation.
const LOG_TAG = "PRODUCTION_AI";
const LOG_START = "production plan draft start";
const LOG_SUCCESS = "production plan draft success";
const LOG_PARTIAL = "production plan draft partial";
const LOG_RECOVERED = "production plan draft envelope recovered";
const LOG_ERROR = "production plan draft error";

// WHY: Keep model intent values consistent in AI logs.
const AI_OPERATION = "ProductionPlanDraft";
const AI_INTENT = "generate production plan draft";
const AI_SOURCE = "backend";
const AI_REQUEST_PURPOSE = "build strict production plan draft";
const SERVICE_NAME = "production_plan_ai_service";

// WHY: Prevent brittle parsing by standardizing strict JSON instructions.
const SYSTEM_PROMPT =
  "You are a production planning assistant. " +
  "Return ONLY valid JSON with no markdown, code fences, or additional text.";

// WHY: Strict envelope hint keeps provider output deterministic and parser-safe.
const ENVELOPE_SCHEMA_HINT = [
  "Return one JSON object only (no markdown).",
  "Use this exact envelope:",
  "{",
  '  "action": "suggestions|clarify|draft_product|plan_draft",',
  '  "message": "string",',
  '  "payload": { ... }',
  "}",
  "Payload must match action exactly (no extra keys):",
  '- suggestions: {"suggestions":["string"]}',
  '- clarify: {"question":"string","choices":["string"],"requiredField":"productId|productDescription|startDate|endDate|quantity|unit|destination|qualityGrade","contextSummary":"string"}',
  '- draft_product: {"draftProduct":{"name":"string","category":"string","unit":"string","notes":"string","lifecycleDaysEstimate":1},"createProductPayload":{"name":"string","category":"string","unit":"string","notes":"string"},"confirmationQuestion":"string"}',
  '- plan_draft: {"productId":"string","productName":"string","startDate":"YYYY-MM-DD","endDate":"YYYY-MM-DD","days":1,"weeks":1,"phases":[{"name":"string","order":1,"estimatedDays":1,"phaseType":"finite|monitoring","requiredUnits":0,"minRatePerFarmerHour":0.1,"targetRatePerFarmerHour":0.2,"plannedHoursPerDay":3,"biologicalMinDays":0,"tasks":[{"title":"string","roleRequired":"string","requiredHeadcount":1,"weight":1,"instructions":"string","startDate":"YYYY-MM-DDTHH:mm:ssZ","dueDate":"YYYY-MM-DDTHH:mm:ssZ","assignedStaffProfileIds":[]}]}],"warnings":[{"code":"string","message":"string"}]}',
  "Never emit null for string/array/number fields.",
  "Do not invent staff IDs. Keep assignedStaffProfileIds as [] unless known.",
].join("\n");

// WHY: Defaults are only used for non-schema prompt context, not output coercion.
const DEFAULT_TITLE_FALLBACK = "Production plan draft";
const DEFAULT_NOTES_FALLBACK = "";
const DEFAULT_PHASE_ESTIMATED_DAYS = 7;
// WHY: Reuse shared defaults so AI + manual flows stay aligned.
const DEFAULT_ENGINE_PHASES = DEFAULT_PRODUCTION_PHASES;
const MIN_WEIGHT = 1;
const MAX_WEIGHT = 5;
const MIN_ESTIMATED_DAYS = 1;
const MAX_ESTIMATED_DAYS = 365;
const MAX_STAFF_ROSTER_ITEMS = 6;
const MAX_ASSISTANT_PROMPT_CHARS = 80000;
const MAX_PROVIDER_MESSAGE_CHARS = 800;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const ISO_Z_DATE_TIME_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const HTTP_UNPROCESSABLE = 422;
const PARSE_ERROR_MESSAGE = "AI draft response was not valid JSON.";
const PARSE_ERROR_HINT =
  "Refine prompt or retry; provider returned non-JSON content.";
const SCHEMA_CLASSIFICATION = "PROVIDER_REJECTED_FORMAT";
const PARSE_ERROR_CODE = "PRODUCTION_AI_JSON_PARSE_FAILED";
const RETRY_REASON_SCHEMA = "provider_output_invalid";
const RETRY_REASON_PARSE = "provider_json_parse_failed";
const RETRY_SKIPPED_REASON = "unexpected_error";
const UNKNOWN_CLASSIFICATION = "UNKNOWN_PROVIDER_ERROR";
const UNKNOWN_ERROR_CODE = "AI_DRAFT_GENERATION_FAILED";
const UNKNOWN_RESOLUTION_HINT =
  "Check AI configuration, prompt input, and strict JSON response format.";
const PROVIDER_GROQ = "groq";
const PROVIDER_XAI = "xai";
const PROVIDER_UNKNOWN = "unknown";
const AI_DRAFT_STATUS_PARTIAL = "ai_draft_partial";
const AI_DRAFT_STATUS_SUCCESS = "ai_draft_success";
const AI_DRAFT_ISSUE_PRODUCT_NOT_INFERRED = "PRODUCT_NOT_INFERRED";
const AI_DRAFT_ISSUE_DATE_NOT_INFERRED = "DATE_NOT_INFERRED";
const AI_DRAFT_ISSUE_INSUFFICIENT_CONTEXT = "INSUFFICIENT_CONTEXT";
const AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE = "HARD_SCHEMA_FAILURE";
const AI_DRAFT_ISSUE_MESSAGE_PRODUCT_NOT_INFERRED =
  "Assistant brief was too vague to infer a product";
const AI_DRAFT_ISSUE_MESSAGE_DATE_NOT_INFERRED =
  "Assistant brief did not provide enough scheduling context to infer dates";
const AI_DRAFT_ISSUE_MESSAGE_INSUFFICIENT_CONTEXT =
  "Assistant brief needs more context to infer product and schedule";
const AI_DRAFT_ISSUE_MESSAGE_HARD_SCHEMA_FAILURE =
  "Assistant output could not be fully parsed. We generated a safe starter draft for manual review.";
const AI_DRAFT_ISSUE_MESSAGE_INSUFFICIENT_CONTEXT_WITH_DOMAIN =
  "Assistant brief needs more context to infer product and schedule for this domain";

// WHY: Key constants avoid inline magic strings in mapping logic.
const KEY_PLAN_TITLE = "planTitle";
const KEY_NOTES = "notes";
const KEY_START_DATE = "startDate";
const KEY_END_DATE = "endDate";
const KEY_DOMAIN_CONTEXT = "domainContext";
const KEY_ESTATE_ASSET_ID = "estateAssetId";
const KEY_PRODUCT_ID = "productId";
const KEY_PHASES = "phases";
const KEY_PHASE_NAME = "name";
const KEY_PHASE_ORDER = "order";
const KEY_PHASE_ESTIMATED_DAYS = "estimatedDays";
const KEY_PHASE_TYPE = "phaseType";
const KEY_PHASE_REQUIRED_UNITS = "requiredUnits";
const KEY_PHASE_MIN_RATE_PER_FARMER_HOUR =
  "minRatePerFarmerHour";
const KEY_PHASE_TARGET_RATE_PER_FARMER_HOUR =
  "targetRatePerFarmerHour";
const KEY_PHASE_PLANNED_HOURS_PER_DAY =
  "plannedHoursPerDay";
const KEY_PHASE_BIOLOGICAL_MIN_DAYS =
  "biologicalMinDays";
const KEY_TASKS = "tasks";
const KEY_TASK_TITLE = "title";
const KEY_TASK_ROLE = "roleRequired";
const KEY_TASK_ASSIGNED_STAFF = "assignedStaffId";
const KEY_TASK_REQUIRED_HEADCOUNT = "requiredHeadcount";
const KEY_TASK_WEIGHT = "weight";
const KEY_TASK_INSTRUCTIONS = "instructions";
const KEY_SUMMARY = "summary";
const KEY_SUMMARY_TOTAL_TASKS = "totalTasks";
const KEY_SUMMARY_TOTAL_DAYS = "totalEstimatedDays";
const KEY_SUMMARY_RISK_NOTES = "riskNotes";
const KEY_PROPOSED_PRODUCT = "proposedProduct";
const KEY_PROPOSED_PRODUCT_NAME = "name";
const KEY_PROPOSED_PRODUCT_DESCRIPTION = "description";
const KEY_PROPOSED_PRODUCT_PRICE_NGN = "priceNgn";
const KEY_PROPOSED_PRODUCT_STOCK = "stock";
const KEY_PROPOSED_PRODUCT_IMAGE_URL = "imageUrl";
const KEY_PROPOSED_START_DATE = "proposedStartDate";
const KEY_PROPOSED_END_DATE = "proposedEndDate";
const KEY_WARNING_CODE = "code";
const KEY_WARNING_PATH = "path";
const KEY_WARNING_VALUE = "value";
const KEY_WARNING_MESSAGE = "message";
const WARNING_ROLE_NOT_IN_DIRECTORY = "ROLE_NOT_IN_DIRECTORY";
const WARNING_ASSIGNED_STAFF_NOT_IN_DIRECTORY =
  "ASSIGNED_STAFF_NOT_IN_DIRECTORY";
const WARNING_ROLE_NORMALIZED = "ROLE_NORMALIZED";
const WARNING_DOMAIN_CONTEXT_NORMALIZED = "DOMAIN_CONTEXT_NORMALIZED";
const WARNING_ENVELOPE_ACTION = "ENVELOPE_ACTION";
const WARNING_ENVELOPE_MESSAGE = "ENVELOPE_MESSAGE";
const WARNING_ENVELOPE_SUGGESTION = "ENVELOPE_SUGGESTION";
const WARNING_ENVELOPE_LOOSE_RECOVERY = "ENVELOPE_LOOSE_RECOVERY";

const ENVELOPE_ACTION_SUGGESTIONS = "suggestions";
const ENVELOPE_ACTION_CLARIFY = "clarify";
const ENVELOPE_ACTION_DRAFT_PRODUCT = "draft_product";
const ENVELOPE_ACTION_PLAN_DRAFT = "plan_draft";
const ENVELOPE_ALLOWED_ACTIONS = [
  ENVELOPE_ACTION_SUGGESTIONS,
  ENVELOPE_ACTION_CLARIFY,
  ENVELOPE_ACTION_DRAFT_PRODUCT,
  ENVELOPE_ACTION_PLAN_DRAFT,
];
const ENVELOPE_REQUIRED_FIELDS = [
  "productId",
  "productDescription",
  "startDate",
  "endDate",
  "quantity",
  "unit",
  "destination",
  "qualityGrade",
];
const ENVELOPE_ROOT_KEYS = [
  "action",
  "message",
  "payload",
];
const ENVELOPE_SUGGESTION_KEYS = [
  "suggestions",
];
const ENVELOPE_CLARIFY_KEYS = [
  "question",
  "choices",
  "requiredField",
  "contextSummary",
];
const ENVELOPE_DRAFT_PRODUCT_KEYS = [
  "draftProduct",
  "createProductPayload",
  "confirmationQuestion",
];
const ENVELOPE_DRAFT_PRODUCT_DRAFT_KEYS = [
  "name",
  "category",
  "unit",
  "notes",
  "lifecycleDaysEstimate",
];
const ENVELOPE_DRAFT_PRODUCT_CREATE_KEYS = [
  "name",
  "category",
  "unit",
  "notes",
];
const ENVELOPE_PLAN_DRAFT_KEYS = [
  "productId",
  "productName",
  "startDate",
  "endDate",
  "days",
  "weeks",
  "phases",
  "warnings",
];
const ENVELOPE_PHASE_KEYS = [
  "name",
  "order",
  "estimatedDays",
  "phaseType",
  "requiredUnits",
  "minRatePerFarmerHour",
  "targetRatePerFarmerHour",
  "plannedHoursPerDay",
  "biologicalMinDays",
  "tasks",
];
const ENVELOPE_TASK_KEYS = [
  "title",
  "roleRequired",
  "requiredHeadcount",
  "weight",
  "instructions",
  "startDate",
  "dueDate",
  "assignedStaffProfileIds",
];
const ENVELOPE_WARNING_KEYS = [
  "code",
  "message",
];

const SAFE_DEFAULT_ROLE = "estate_manager";

// WHY: Keep staff fields tight to avoid leaking sensitive user data in prompts.
function buildStaffRoster(staffProfiles) {
  return staffProfiles.map((profile) => ({
    id: profile._id?.toString(),
    role: profile.staffRole,
    name: profile.userId?.name || profile.userId?.email || "Staff",
    estateAssetId: profile.estateAssetId?.toString() || null,
  }));
}

function summarizeStaffRoster(staffRoster) {
  if (!Array.isArray(staffRoster) || staffRoster.length === 0) {
    return "Staff roster: none";
  }

  const trimmed = staffRoster.slice(0, MAX_STAFF_ROSTER_ITEMS);
  const lines = trimmed.map(
    (entry) => `${entry.id || "unknown"}(${entry.role || "role"})`,
  );
  const note =
    staffRoster.length > MAX_STAFF_ROSTER_ITEMS
      ? `...plus ${staffRoster.length - MAX_STAFF_ROSTER_ITEMS} more`
      : "";
  return `Staff roster: ${lines.join(", ")}${note ? ` ${note}` : ""}`;
}

function sanitizeAssistantPrompt(value) {
  const raw = (value || "")
    .toString()
    .replace(/\r\n?/g, "\n")
    .trim();
  if (!raw) return "";
  const compact = raw
    .split("\n")
    .map((line) => line.replace(/[ \t]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (compact.length <= MAX_ASSISTANT_PROMPT_CHARS) {
    return compact;
  }
  return `${compact.slice(0, MAX_ASSISTANT_PROMPT_CHARS)}\n...[assistant context truncated]`;
}

function resolveDomainContextConfig(domainContext) {
  const normalizedDomainContext = normalizeDomainContext(
    domainContext,
  );
  return {
    domainContext: normalizedDomainContext,
    config:
      DOMAIN_CONFIGS[normalizedDomainContext] ||
      DOMAIN_CONFIGS[DEFAULT_PRODUCTION_DOMAIN_CONTEXT] ||
      DOMAIN_CONFIGS.custom,
  };
}

function summarizeDomainContext(domainContext) {
  const { domainContext: normalizedDomainContext, config } =
    resolveDomainContextConfig(domainContext);
  const phaseHints =
    config?.examplePhases?.length > 0 ?
      config.examplePhases
    : DEFAULT_ENGINE_PHASES.map(
        (phase) => phase.name,
      );
  const keywordsSummary =
    config?.keywords?.length > 0 ?
      config.keywords.join(", ")
    : "none";
  const rolesSummary =
    config?.defaultRoles?.length > 0 ?
      config.defaultRoles.join(", ")
    : "none";
  const outputsSummary =
    config?.defaultOutputs?.length > 0 ?
      config.defaultOutputs.join(", ")
    : "none";
  const phaseSummary =
    phaseHints.join(", ");

  return {
    domainContext: normalizedDomainContext,
    summaryLines: [
      `Domain context: ${normalizedDomainContext}`,
      `Domain keywords (hint only): ${keywordsSummary}`,
      `Domain default roles (bias only): ${rolesSummary}`,
      `Domain default outputs (hint only): ${outputsSummary}`,
      `Domain example phases (hint only): ${phaseSummary}`,
    ],
  };
}

function buildFallbackPhaseTemplates(domainContext) {
  const { config } =
    resolveDomainContextConfig(
      domainContext,
    );
  const phaseNames =
    config?.examplePhases?.length > 0 ?
      config.examplePhases
    : DEFAULT_ENGINE_PHASES.map(
        (phase) => phase.name,
      );
  return phaseNames.map(
    (name, index) => ({
      [KEY_PHASE_NAME]: name,
      [KEY_PHASE_ORDER]: index + 1,
      [KEY_PHASE_ESTIMATED_DAYS]:
        DEFAULT_PHASE_ESTIMATED_DAYS,
      [KEY_TASKS]: [],
    }),
  );
}

// WHY: Ensure prompts include structured context for reliable strict JSON output.
function buildUserPrompt({
  productName,
  estateName,
  startDate,
  endDate,
  domainContext,
  staffRoster,
  assistantPrompt,
}) {
  const domainSummary =
    summarizeDomainContext(domainContext);
  const sections = [
    `Product: ${productName || DEFAULT_TITLE_FALLBACK}`,
    `Estate: ${estateName || "Unknown estate"}`,
    `Start: ${startDate || "Not provided (AI should propose proposedStartDate)"}`,
    `End: ${endDate || "Not provided (AI should propose proposedEndDate)"}`,
    ...domainSummary.summaryLines,
    `Engine phase template (guidance): ${DEFAULT_ENGINE_PHASES.map((phase) => phase.name).join(", ")}`,
    summarizeStaffRoster(staffRoster),
  ];

  if (!productName || productName === DEFAULT_TITLE_FALLBACK) {
    sections.push(
      "Product selection missing: include a valid proposedProduct object in JSON.",
    );
  }

  if (assistantPrompt) {
    sections.push(`User assistant context:\n${assistantPrompt}`);
  }

  sections.push(ENVELOPE_SCHEMA_HINT);
  return sections.join("\n");
}

// WHY: Extract the first JSON object block for robust parsing.
function extractJsonBlock(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end < 0 || end <= start) {
    return null;
  }
  return text.slice(start, end + 1);
}

function sanitizeProviderMessage(value) {
  const text = (value || "").toString().replace(/\s+/g, " ").trim();
  if (!text) return "";
  if (text.length <= MAX_PROVIDER_MESSAGE_CHARS) {
    return text;
  }
  return text.slice(0, MAX_PROVIDER_MESSAGE_CHARS);
}

function resolveProviderName() {
  const base = (AI_BASE_URL || "").toLowerCase();
  if (base.includes("groq.com")) return PROVIDER_GROQ;
  if (base.includes("x.ai")) return PROVIDER_XAI;
  return PROVIDER_UNKNOWN;
}

function buildDraftError({
  message,
  classification,
  errorCode,
  resolutionHint,
  details,
  providerMessage,
  retryReason,
}) {
  const error = new Error(message);
  error.classification = classification;
  error.errorCode = errorCode;
  error.resolutionHint = resolutionHint;
  error.httpStatus = HTTP_UNPROCESSABLE;
  error.details = details || {};
  error.providerMessage = sanitizeProviderMessage(providerMessage);
  error.retry_allowed = true;
  error.retry_reason = retryReason;
  return error;
}

function tryParseJson(candidate) {
  if (!candidate || !candidate.trim()) {
    return null;
  }
  try {
    return JSON.parse(candidate);
  } catch (_err) {
    return null;
  }
}

// WHY: Some providers return JSON-like payloads with JS comments.
// Strip comments only when outside string literals so strict JSON parsing can run.
function stripJsonComments(input) {
  const text = (input || "").toString();
  let output = "";
  let inString = false;
  let escaped = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const nextChar = text[index + 1];

    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      output += char;
      continue;
    }

    if (char === "/" && nextChar === "/") {
      // WHY: Drop single-line comments and continue from the next line.
      while (index < text.length && text[index] !== "\n") {
        index += 1;
      }
      if (index < text.length) {
        output += text[index];
      }
      continue;
    }

    if (char === "/" && nextChar === "*") {
      // WHY: Drop multi-line comments emitted by provider wrappers.
      index += 2;
      while (
        index < text.length &&
        !(text[index] === "*" && text[index + 1] === "/")
      ) {
        index += 1;
      }
      if (index < text.length) {
        index += 1;
      }
      continue;
    }

    output += char;
  }

  return output;
}

// WHY: Providers sometimes emit trailing commas in objects/arrays.
// Remove only commas that are immediately before ] or } outside strings.
function stripTrailingCommas(input) {
  const text = (input || "").toString();
  let output = "";
  let inString = false;
  let escaped = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      output += char;
      continue;
    }

    if (char === ",") {
      let lookahead = index + 1;
      while (
        lookahead < text.length &&
        /\s/.test(text[lookahead])
      ) {
        lookahead += 1;
      }

      const nextChar = text[lookahead];
      if (nextChar === "}" || nextChar === "]") {
        continue;
      }
    }

    output += char;
  }

  return output;
}

function extractFencedJson(text) {
  const match = (text || "").match(/```(?:json)?\s*([\s\S]*?)```/i);
  return match?.[1]?.trim() || null;
}

function parseAiDraft(content) {
  const raw = (content || "").toString().trim();
  const rawWithoutComments = stripJsonComments(raw).trim();
  const rawWithoutTrailingCommas = stripTrailingCommas(rawWithoutComments).trim();
  const fenced = extractFencedJson(raw);
  const fencedWithoutComments = stripJsonComments(fenced).trim();
  const fencedWithoutTrailingCommas = stripTrailingCommas(
    fencedWithoutComments,
  ).trim();
  const jsonBlock = extractJsonBlock(raw);
  const jsonBlockWithoutComments = stripJsonComments(jsonBlock).trim();
  const jsonBlockWithoutTrailingCommas = stripTrailingCommas(
    jsonBlockWithoutComments,
  ).trim();

  const candidates = [
    raw,
    rawWithoutComments,
    rawWithoutTrailingCommas,
    fenced,
    fencedWithoutComments,
    fencedWithoutTrailingCommas,
    jsonBlock,
    jsonBlockWithoutComments,
    jsonBlockWithoutTrailingCommas,
  ]
    .filter((item, index, array) => item && array.indexOf(item) === index);

  for (const candidate of candidates) {
    const parsed = tryParseJson(candidate);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      continue;
    }
    return parsed;
  }

  throw buildDraftError({
    message: PARSE_ERROR_MESSAGE,
    classification: SCHEMA_CLASSIFICATION,
    errorCode: PARSE_ERROR_CODE,
    resolutionHint: PARSE_ERROR_HINT,
    details: {
      missing: [],
      invalid: [],
      providerMessage: sanitizeProviderMessage(raw),
    },
    providerMessage: raw,
    retryReason: RETRY_REASON_PARSE,
  });
}

function isPlainObject(value) {
  return (
    value != null &&
    typeof value === "object" &&
    !Array.isArray(value)
  );
}

function validateExactKeys({
  value,
  requiredKeys,
  path,
  invalid,
}) {
  if (!isPlainObject(value)) {
    invalid.push(path);
    return false;
  }
  const keys = Object.keys(value);
  keys.forEach((key) => {
    if (!requiredKeys.includes(key)) {
      invalid.push(`${path}.${key}`);
    }
  });
  requiredKeys.forEach((key) => {
    if (!Object.prototype.hasOwnProperty.call(value, key)) {
      invalid.push(`${path}.${key}`);
    }
  });
  return true;
}

function isValidIsoDateTimeZ(value) {
  if (
    typeof value !== "string" ||
    !ISO_Z_DATE_TIME_PATTERN.test(value)
  ) {
    return false;
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return false;
  }
  return (
    `${parsed.toISOString().slice(0, 19)}Z` ===
    value
  );
}

function parseString(value) {
  return value == null ? "" : value.toString().trim();
}

function parsePositiveInteger(value, fallback = 1) {
  const parsed = parseInteger(value);
  if (parsed == null || parsed < 1) {
    return fallback;
  }
  return parsed;
}

// WHY: Phase throughput and planned-hour fields use decimal values and need deterministic positive parsing.
function parsePositiveNumber(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Number(parsed);
}

// WHY: Strict envelope parsing should allow only finite/monitoring phase lifecycle labels.
function normalizeEnvelopePhaseType(value) {
  const normalized = parseString(value)
    .toLowerCase()
    .trim();
  if (normalized === "monitoring") {
    return "monitoring";
  }
  return "finite";
}

function computeInclusivePlanningRange({
  startDate,
  endDate,
}) {
  if (
    !isValidDateString(startDate) ||
    !isValidDateString(endDate)
  ) {
    return null;
  }
  const start = new Date(
    `${startDate}T00:00:00.000Z`,
  );
  const end = new Date(
    `${endDate}T00:00:00.000Z`,
  );
  const diffDays = Math.floor(
    (end.getTime() - start.getTime()) /
      (24 * 60 * 60 * 1000),
  );
  const days = Math.max(
    1,
    diffDays + 1,
  );
  const weeks = Math.max(
    1,
    Math.ceil(days / 7),
  );
  return { days, weeks };
}

function buildFallbackRangeDates({
  startDate,
  endDate,
}) {
  const DAY_MS = 24 * 60 * 60 * 1000;
  const providedStart = isValidDateString(startDate)
    ? startDate
    : null;
  const providedEnd = isValidDateString(endDate)
    ? endDate
    : null;
  let resolvedStart = providedStart;
  let resolvedEnd = providedEnd;

  if (!resolvedStart && !resolvedEnd) {
    const now = new Date();
    const start = new Date(
      Date.UTC(
        now.getUTCFullYear(),
        now.getUTCMonth(),
        now.getUTCDate(),
      ),
    );
    const end = new Date(start.getTime() + 84 * DAY_MS);
    resolvedStart = start.toISOString().slice(0, 10);
    resolvedEnd = end.toISOString().slice(0, 10);
  } else if (resolvedStart && !resolvedEnd) {
    const start = new Date(`${resolvedStart}T00:00:00.000Z`);
    const end = new Date(start.getTime() + 84 * DAY_MS);
    resolvedEnd = end.toISOString().slice(0, 10);
  } else if (!resolvedStart && resolvedEnd) {
    const end = new Date(`${resolvedEnd}T00:00:00.000Z`);
    const start = new Date(end.getTime() - 84 * DAY_MS);
    resolvedStart = start.toISOString().slice(0, 10);
  }

  if (resolvedEnd <= resolvedStart) {
    const start = new Date(`${resolvedStart}T00:00:00.000Z`);
    resolvedEnd = new Date(start.getTime() + DAY_MS)
      .toISOString()
      .slice(0, 10);
  }

  return {
    providedStart,
    providedEnd,
    resolvedStart,
    resolvedEnd,
  };
}

function validateEnvelopePayload(parsed) {
  const invalid = [];
  if (
    !validateExactKeys({
      value: parsed,
      requiredKeys: ENVELOPE_ROOT_KEYS,
      path: "envelope",
      invalid,
    })
  ) {
    return { ok: false, invalid };
  }

  const action = parseString(parsed.action);
  const message = parseString(parsed.message);
  const payload = parsed.payload;

  if (!ENVELOPE_ALLOWED_ACTIONS.includes(action)) {
    invalid.push("envelope.action");
  }
  if (typeof parsed.message !== "string") {
    invalid.push("envelope.message");
  }
  if (!isPlainObject(payload)) {
    invalid.push("envelope.payload");
  }

  if (invalid.length > 0 || !isPlainObject(payload)) {
    return { ok: false, invalid };
  }

  if (action === ENVELOPE_ACTION_SUGGESTIONS) {
    validateExactKeys({
      value: payload,
      requiredKeys: ENVELOPE_SUGGESTION_KEYS,
      path: "envelope.payload",
      invalid,
    });
    if (
      !Array.isArray(payload.suggestions) ||
      payload.suggestions.some(
        (item) =>
          typeof item !== "string" || !item.trim(),
      )
    ) {
      invalid.push("envelope.payload.suggestions");
    }
  }

  if (action === ENVELOPE_ACTION_CLARIFY) {
    validateExactKeys({
      value: payload,
      requiredKeys: ENVELOPE_CLARIFY_KEYS,
      path: "envelope.payload",
      invalid,
    });
    if (
      typeof payload.question !== "string" ||
      !payload.question.trim()
    ) {
      invalid.push("envelope.payload.question");
    }
    if (
      !Array.isArray(payload.choices) ||
      payload.choices.some(
        (item) =>
          typeof item !== "string" || !item.trim(),
      )
    ) {
      invalid.push("envelope.payload.choices");
    }
    if (
      typeof payload.requiredField !== "string" ||
      !ENVELOPE_REQUIRED_FIELDS.includes(
        payload.requiredField,
      )
    ) {
      invalid.push("envelope.payload.requiredField");
    }
    if (
      typeof payload.contextSummary !== "string"
    ) {
      invalid.push("envelope.payload.contextSummary");
    }
  }

  if (action === ENVELOPE_ACTION_DRAFT_PRODUCT) {
    validateExactKeys({
      value: payload,
      requiredKeys:
        ENVELOPE_DRAFT_PRODUCT_KEYS,
      path: "envelope.payload",
      invalid,
    });
    if (
      !validateExactKeys({
        value: payload.draftProduct,
        requiredKeys:
          ENVELOPE_DRAFT_PRODUCT_DRAFT_KEYS,
        path: "envelope.payload.draftProduct",
        invalid,
      })
    ) {
      return { ok: false, invalid };
    }
    if (
      !validateExactKeys({
        value: payload.createProductPayload,
        requiredKeys:
          ENVELOPE_DRAFT_PRODUCT_CREATE_KEYS,
        path: "envelope.payload.createProductPayload",
        invalid,
      })
    ) {
      return { ok: false, invalid };
    }
    ENVELOPE_DRAFT_PRODUCT_DRAFT_KEYS.forEach((key) => {
      if (
        key === "lifecycleDaysEstimate"
      ) {
        const parsedLifecycle =
          parseInteger(
            payload.draftProduct[
              key
            ],
          );
        if (
          parsedLifecycle == null ||
          parsedLifecycle < 1
        ) {
          invalid.push(
            `envelope.payload.draftProduct.${key}`,
          );
        }
        return;
      }
      if (
        typeof payload.draftProduct[
          key
        ] !== "string"
      ) {
        invalid.push(
          `envelope.payload.draftProduct.${key}`,
        );
      }
    });
    ENVELOPE_DRAFT_PRODUCT_CREATE_KEYS.forEach((key) => {
      if (
        typeof payload
          .createProductPayload[
          key
        ] !== "string"
      ) {
        invalid.push(
          `envelope.payload.createProductPayload.${key}`,
        );
      }
    });
    if (
      typeof payload.confirmationQuestion !==
      "string"
    ) {
      invalid.push(
        "envelope.payload.confirmationQuestion",
      );
    }
  }

  if (action === ENVELOPE_ACTION_PLAN_DRAFT) {
    validateExactKeys({
      value: payload,
      requiredKeys: ENVELOPE_PLAN_DRAFT_KEYS,
      path: "envelope.payload",
      invalid,
    });
    if (
      typeof payload.productId !== "string"
    ) {
      invalid.push("envelope.payload.productId");
    }
    if (
      typeof payload.productName !== "string" ||
      !payload.productName.trim()
    ) {
      invalid.push("envelope.payload.productName");
    }
    if (!isValidDateString(payload.startDate)) {
      invalid.push("envelope.payload.startDate");
    }
    if (!isValidDateString(payload.endDate)) {
      invalid.push("envelope.payload.endDate");
    }
    const daysValue = parseInteger(payload.days);
    const weeksValue = parseInteger(payload.weeks);
    if (daysValue == null || daysValue < 1) {
      invalid.push("envelope.payload.days");
    }
    if (weeksValue == null || weeksValue < 1) {
      invalid.push("envelope.payload.weeks");
    }
    const computedRange = computeInclusivePlanningRange(
      {
        startDate:
          payload.startDate,
        endDate: payload.endDate,
      },
    );
    if (computedRange) {
      if (
        daysValue != null &&
        daysValue !==
          computedRange.days
      ) {
        invalid.push("envelope.payload.days");
      }
      if (
        weeksValue != null &&
        weeksValue !==
          computedRange.weeks
      ) {
        invalid.push("envelope.payload.weeks");
      }
    }
    if (
      !Array.isArray(payload.phases)
    ) {
      invalid.push("envelope.payload.phases");
    }
    if (
      !Array.isArray(payload.warnings)
    ) {
      invalid.push("envelope.payload.warnings");
    }

    if (Array.isArray(payload.phases)) {
      payload.phases.forEach((phase, phaseIndex) => {
        const phasePath = `envelope.payload.phases[${phaseIndex}]`;
        if (
          !validateExactKeys({
            value: phase,
            requiredKeys:
              ENVELOPE_PHASE_KEYS,
            path: phasePath,
            invalid,
          })
        ) {
          return;
        }
        if (
          typeof phase.name !== "string" ||
          !phase.name.trim()
        ) {
          invalid.push(`${phasePath}.name`);
        }
        if (
          parseInteger(phase.order) == null ||
          parseInteger(phase.order) < 1
        ) {
          invalid.push(`${phasePath}.order`);
        }
        if (
          parseInteger(
            phase.estimatedDays,
          ) == null ||
          parseInteger(
            phase.estimatedDays,
          ) < 1
        ) {
          invalid.push(
            `${phasePath}.estimatedDays`,
          );
        }
        const normalizedPhaseType =
          normalizeEnvelopePhaseType(phase.phaseType);
        if (
          typeof phase.phaseType !== "string" ||
          !phase.phaseType.trim() ||
          normalizedPhaseType !==
            parseString(phase.phaseType)
              .toLowerCase()
              .trim()
        ) {
          invalid.push(`${phasePath}.phaseType`);
        }
        if (
          parseInteger(phase.requiredUnits) == null ||
          parseInteger(phase.requiredUnits) < 0
        ) {
          invalid.push(`${phasePath}.requiredUnits`);
        }
        if (
          !Number.isFinite(Number(phase.minRatePerFarmerHour)) ||
          Number(phase.minRatePerFarmerHour) <= 0
        ) {
          invalid.push(
            `${phasePath}.minRatePerFarmerHour`,
          );
        }
        if (
          !Number.isFinite(
            Number(phase.targetRatePerFarmerHour),
          ) ||
          Number(phase.targetRatePerFarmerHour) <= 0
        ) {
          invalid.push(
            `${phasePath}.targetRatePerFarmerHour`,
          );
        }
        if (
          !Number.isFinite(Number(phase.plannedHoursPerDay)) ||
          Number(phase.plannedHoursPerDay) <= 0
        ) {
          invalid.push(
            `${phasePath}.plannedHoursPerDay`,
          );
        }
        if (
          parseInteger(phase.biologicalMinDays) == null ||
          parseInteger(phase.biologicalMinDays) < 0
        ) {
          invalid.push(
            `${phasePath}.biologicalMinDays`,
          );
        }
        if (
          Number(phase.targetRatePerFarmerHour) <
          Number(phase.minRatePerFarmerHour)
        ) {
          invalid.push(
            `${phasePath}.targetRatePerFarmerHour`,
          );
        }
        if (!Array.isArray(phase.tasks)) {
          invalid.push(`${phasePath}.tasks`);
          return;
        }
        phase.tasks.forEach((task, taskIndex) => {
          const taskPath = `${phasePath}.tasks[${taskIndex}]`;
          if (
            !validateExactKeys({
              value: task,
              requiredKeys:
                ENVELOPE_TASK_KEYS,
              path: taskPath,
              invalid,
            })
          ) {
            return;
          }
          if (
            typeof task.title !== "string" ||
            !task.title.trim()
          ) {
            invalid.push(`${taskPath}.title`);
          }
          if (
            typeof task.roleRequired !== "string" ||
            !task.roleRequired.trim()
          ) {
            invalid.push(`${taskPath}.roleRequired`);
          }
          if (
            parseInteger(
              task.requiredHeadcount,
            ) == null ||
            parseInteger(
              task.requiredHeadcount,
            ) < 1
          ) {
            invalid.push(
              `${taskPath}.requiredHeadcount`,
            );
          }
          if (
            parseInteger(task.weight) == null ||
            parseInteger(task.weight) < 1
          ) {
            invalid.push(`${taskPath}.weight`);
          }
          if (
            typeof task.instructions !== "string"
          ) {
            invalid.push(
              `${taskPath}.instructions`,
            );
          }
          if (
            !isValidIsoDateTimeZ(
              task.startDate,
            )
          ) {
            invalid.push(`${taskPath}.startDate`);
          }
          if (
            !isValidIsoDateTimeZ(
              task.dueDate,
            )
          ) {
            invalid.push(`${taskPath}.dueDate`);
          }
          if (
            !Array.isArray(
              task.assignedStaffProfileIds,
            ) ||
            task.assignedStaffProfileIds.some(
              (id) =>
                typeof id !== "string" ||
                !id.trim(),
            )
          ) {
            invalid.push(
              `${taskPath}.assignedStaffProfileIds`,
            );
          }
        });
      });
    }

    if (Array.isArray(payload.warnings)) {
      payload.warnings.forEach(
        (warning, warningIndex) => {
          const warningPath = `envelope.payload.warnings[${warningIndex}]`;
          if (
            !validateExactKeys({
              value: warning,
              requiredKeys:
                ENVELOPE_WARNING_KEYS,
              path: warningPath,
              invalid,
            })
          ) {
            return;
          }
          if (
            typeof warning.code !== "string" ||
            !warning.code.trim()
          ) {
            invalid.push(`${warningPath}.code`);
          }
          if (
            typeof warning.message !== "string" ||
            !warning.message.trim()
          ) {
            invalid.push(`${warningPath}.message`);
          }
        },
      );
    }
  }

  if (invalid.length > 0) {
    return { ok: false, invalid };
  }
  return {
    ok: true,
    envelope: {
      action,
      message,
      payload,
    },
  };
}

// WHY: Provider payloads often contain parseable dates with minor format drift.
// This coercion protects plan quality by normalizing near-valid date fields.
function normalizeLooseDateString(value) {
  const raw = parseString(value);
  if (!raw) {
    return "";
  }
  if (isValidDateString(raw)) {
    return raw;
  }
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    return "";
  }
  return parsed.toISOString().slice(0, 10);
}

function formatLooseIsoDateTimeZ(date) {
  return `${date.toISOString().slice(0, 19)}Z`;
}

// WHY: Task timestamps are required by strict envelope parsing.
// This converter accepts flexible provider formats, then normalizes to YYYY-MM-DDTHH:mm:ssZ.
function normalizeLooseTaskIsoDateTimeZ({
  value,
  fallbackDate,
  fallbackHour,
  fallbackMinute,
}) {
  if (isValidIsoDateTimeZ(value)) {
    return value;
  }
  const raw = parseString(value);
  if (isValidDateString(raw)) {
    return `${raw}T${String(fallbackHour).padStart(2, "0")}:${String(
      fallbackMinute,
    ).padStart(2, "0")}:00Z`;
  }
  if (raw) {
    const parsed = new Date(raw);
    if (!Number.isNaN(parsed.getTime())) {
      return formatLooseIsoDateTimeZ(parsed);
    }
  }
  const safeFallbackDate = isValidDateString(fallbackDate)
    ? fallbackDate
    : new Date().toISOString().slice(0, 10);
  return `${safeFallbackDate}T${String(fallbackHour).padStart(2, "0")}:${String(
    fallbackMinute,
  ).padStart(2, "0")}:00Z`;
}

// WHY: When envelope validation fails for non-critical shape issues, this recovery
// path salvages taskful drafts instead of dropping to a generic empty fallback.
function coerceLoosePlanDraftEnvelope({
  parsed,
  productName,
  productId,
  startDate,
  endDate,
}) {
  if (!isPlainObject(parsed)) {
    return null;
  }

  const hasEnvelopePayload = isPlainObject(parsed.payload);
  const candidatePayload = hasEnvelopePayload ? parsed.payload : parsed;
  if (!isPlainObject(candidatePayload)) {
    return null;
  }

  const rawPhases = Array.isArray(candidatePayload.phases)
    ? candidatePayload.phases
    : Array.isArray(candidatePayload.phaseRows)
      ? candidatePayload.phaseRows
      : Array.isArray(candidatePayload.stages)
        ? candidatePayload.stages
        : [];
  if (rawPhases.length === 0) {
    return null;
  }

  const baseRange = buildFallbackRangeDates({
    startDate: normalizeLooseDateString(candidatePayload.startDate) || startDate,
    endDate: normalizeLooseDateString(candidatePayload.endDate) || endDate,
  });
  const safeStartDate = baseRange.resolvedStart;
  const safeEndDate = baseRange.resolvedEnd;
  const computedRange = computeInclusivePlanningRange({
    startDate: safeStartDate,
    endDate: safeEndDate,
  }) || { days: 1, weeks: 1 };

  const normalizedPhases = rawPhases
    .map((phase, phaseIndex) => {
      if (!isPlainObject(phase)) {
        return null;
      }
      const rawTasks = Array.isArray(phase.tasks)
        ? phase.tasks
        : Array.isArray(phase.items)
          ? phase.items
          : [];
      const normalizedTasks = rawTasks
        .map((task) => {
          if (!isPlainObject(task)) {
            return null;
          }
          const title =
            parseString(task.title || task.name || task.taskName) ||
            DEFAULT_TITLE_FALLBACK;
          const roleRequired =
            parseString(task.roleRequired || task.role || task.staffRole) ||
            SAFE_DEFAULT_ROLE;
          const requiredHeadcount = parsePositiveInteger(
            task.requiredHeadcount || task.headcount || task.staffCount,
            1,
          );
          const weight = parsePositiveInteger(task.weight, 1);
          const instructions =
            parseString(task.instructions || task.notes || task.note) ||
            "Recovered from provider draft output for manual review.";
          const startDateIso = normalizeLooseTaskIsoDateTimeZ({
            value: task.startDate || task.start || task.startTime,
            fallbackDate: safeStartDate,
            fallbackHour: 9,
            fallbackMinute: 0,
          });
          let dueDateIso = normalizeLooseTaskIsoDateTimeZ({
            value: task.dueDate || task.end || task.endTime,
            fallbackDate: safeStartDate,
            fallbackHour: 13,
            fallbackMinute: 0,
          });
          const startMs = Date.parse(startDateIso);
          const dueMs = Date.parse(dueDateIso);
          if (
            Number.isFinite(startMs) &&
            Number.isFinite(dueMs) &&
            dueMs <= startMs
          ) {
            dueDateIso = formatLooseIsoDateTimeZ(
              new Date(startMs + 4 * 60 * 60 * 1000),
            );
          }
          const assignedStaffProfileIdsRaw = Array.isArray(
            task.assignedStaffProfileIds,
          )
            ? task.assignedStaffProfileIds
            : Array.isArray(task.assignedStaffIds)
              ? task.assignedStaffIds
              : Array.isArray(task.assignees)
                ? task.assignees
                : [];
          const assignedStaffProfileIds = assignedStaffProfileIdsRaw
            .map((entry) => parseString(entry))
            .filter(Boolean);

          return {
            title,
            roleRequired,
            requiredHeadcount,
            weight,
            instructions,
            startDate: startDateIso,
            dueDate: dueDateIso,
            assignedStaffProfileIds,
          };
        })
        .filter(Boolean);

      const phaseName =
        parseString(phase.name || phase.phaseName || phase.title) ||
        `${DEFAULT_PHASE_NAME_PREFIX} ${phaseIndex + 1}`;
      const phaseOrder = parsePositiveInteger(
        phase.order || phase.phaseOrder,
        phaseIndex + 1,
      );
      const estimatedDays = parsePositiveInteger(
        phase.estimatedDays || phase.durationDays || phase.days,
        1,
      );
      const phaseType = normalizeEnvelopePhaseType(
        phase.phaseType || phase.type || phase.lifecycleType,
      );
      const requiredUnits = Math.max(
        0,
        parseInteger(
          phase.requiredUnits ||
            phase.units ||
            phase.totalUnits ||
            candidatePayload.requiredUnits,
        ) || 0,
      );
      const minRatePerFarmerHour = parsePositiveNumber(
        phase.minRatePerFarmerHour ||
          phase.minimumRatePerFarmerHour ||
          phase.minThroughputPerFarmerHour,
        0.1,
      );
      const targetRatePerFarmerHour = Math.max(
        minRatePerFarmerHour,
        parsePositiveNumber(
          phase.targetRatePerFarmerHour ||
            phase.targetThroughputPerFarmerHour,
          minRatePerFarmerHour,
        ),
      );
      const plannedHoursPerDay = parsePositiveNumber(
        phase.plannedHoursPerDay ||
          phase.hoursPerDay,
        3,
      );
      const biologicalMinDays = Math.max(
        0,
        parseInteger(
          phase.biologicalMinDays ||
            phase.biologyDays ||
            phase.minBiologyDays,
        ) || 0,
      );

      return {
        name: phaseName,
        order: phaseOrder,
        estimatedDays,
        phaseType,
        requiredUnits,
        minRatePerFarmerHour,
        targetRatePerFarmerHour,
        plannedHoursPerDay,
        biologicalMinDays,
        tasks: normalizedTasks,
      };
    })
    .filter(Boolean);

  if (normalizedPhases.length === 0) {
    return null;
  }

  const warningsRaw = Array.isArray(candidatePayload.warnings)
    ? candidatePayload.warnings
    : [];
  const normalizedWarnings = warningsRaw
    .map((warning, warningIndex) => {
      if (!isPlainObject(warning)) {
        return null;
      }
      const code =
        parseString(warning.code) || `RECOVERED_WARNING_${warningIndex + 1}`;
      const message =
        parseString(warning.message) || "Recovered warning from provider output.";
      return {
        code,
        message,
      };
    })
    .filter(Boolean);

  return {
    action: ENVELOPE_ACTION_PLAN_DRAFT,
    message:
      parseString(parsed.message) ||
      "Recovered plan draft from provider output.",
    payload: {
      productId:
        parseString(candidatePayload.productId) || parseString(productId),
      productName:
        parseString(candidatePayload.productName) ||
        parseString(productName) ||
        DEFAULT_TITLE_FALLBACK,
      startDate: safeStartDate,
      endDate: safeEndDate,
      days: computedRange.days,
      weeks: computedRange.weeks,
      phases: normalizedPhases,
      warnings: normalizedWarnings,
    },
  };
}

function convertPlanDraftEnvelopeToLegacyDraft({
  envelope,
  estateAssetId,
  productId,
  domainContext,
}) {
  const payload =
    envelope?.payload || {};
  const normalizedProductId =
    parseString(payload.productId) ||
    parseString(productId);
  const normalizedProductName =
    parseString(payload.productName) ||
    DEFAULT_TITLE_FALLBACK;
  const phases = Array.isArray(payload.phases)
    ? payload.phases
    : [];
  const normalizedPhases = phases.map(
    (phase) => ({
      [KEY_PHASE_NAME]:
        parseString(phase.name) ||
        DEFAULT_PHASE_NAME_PREFIX,
      [KEY_PHASE_ORDER]:
        parsePositiveInteger(
          phase.order,
          1,
        ),
      [KEY_PHASE_ESTIMATED_DAYS]:
        parsePositiveInteger(
          phase.estimatedDays,
          1,
        ),
      [KEY_PHASE_TYPE]:
        normalizeEnvelopePhaseType(
          phase.phaseType,
        ),
      [KEY_PHASE_REQUIRED_UNITS]: Math.max(
        0,
        parseInteger(
          phase.requiredUnits,
        ) || 0,
      ),
      [KEY_PHASE_MIN_RATE_PER_FARMER_HOUR]:
        parsePositiveNumber(
          phase.minRatePerFarmerHour,
          0.1,
        ),
      [KEY_PHASE_TARGET_RATE_PER_FARMER_HOUR]:
        Math.max(
          parsePositiveNumber(
            phase.minRatePerFarmerHour,
            0.1,
          ),
          parsePositiveNumber(
            phase.targetRatePerFarmerHour,
            0.1,
          ),
        ),
      [KEY_PHASE_PLANNED_HOURS_PER_DAY]:
        parsePositiveNumber(
          phase.plannedHoursPerDay,
          3,
        ),
      [KEY_PHASE_BIOLOGICAL_MIN_DAYS]:
        Math.max(
          0,
          parseInteger(
            phase.biologicalMinDays,
          ) || 0,
        ),
      [KEY_TASKS]: (
        Array.isArray(phase.tasks)
          ? phase.tasks
          : []
      ).map((task) => ({
        [KEY_TASK_TITLE]:
          parseString(task.title) ||
          DEFAULT_TITLE_FALLBACK,
        [KEY_TASK_ROLE]:
          parseString(task.roleRequired) ||
          SAFE_DEFAULT_ROLE,
        [KEY_TASK_ASSIGNED_STAFF]: null,
        [KEY_TASK_REQUIRED_HEADCOUNT]:
          parsePositiveInteger(
            task.requiredHeadcount,
            1,
          ),
        [KEY_TASK_WEIGHT]:
          parsePositiveInteger(
            task.weight,
            1,
          ),
        [KEY_TASK_INSTRUCTIONS]:
          parseString(task.instructions),
      })),
    }),
  );
  const totalTasks = normalizedPhases.reduce(
    (sum, phase) =>
      sum + phase[KEY_TASKS].length,
    0,
  );
  const warnings = Array.isArray(payload.warnings)
    ? payload.warnings
    : [];
  const riskNotes = warnings
    .map((warning) =>
      parseString(
        warning?.message,
      ),
    )
    .filter(Boolean);

  return {
    draft: {
      [KEY_PLAN_TITLE]: `${normalizedProductName} Production Plan`,
      title: `${normalizedProductName} Production Plan`,
      [KEY_NOTES]:
        parseString(envelope.message),
      [KEY_DOMAIN_CONTEXT]:
        normalizeDomainContext(
          domainContext,
        ),
      [KEY_START_DATE]:
        parseString(payload.startDate),
      [KEY_END_DATE]:
        parseString(payload.endDate),
      [KEY_PROPOSED_START_DATE]: null,
      [KEY_PROPOSED_END_DATE]: null,
      [KEY_ESTATE_ASSET_ID]:
        parseString(estateAssetId),
      [KEY_PRODUCT_ID]:
        normalizedProductId || null,
      [KEY_PROPOSED_PRODUCT]:
        normalizedProductId ?
          null
        : {
            [KEY_PROPOSED_PRODUCT_NAME]:
              normalizedProductName,
            [KEY_PROPOSED_PRODUCT_DESCRIPTION]:
              "",
            [KEY_PROPOSED_PRODUCT_PRICE_NGN]:
              0,
            [KEY_PROPOSED_PRODUCT_STOCK]:
              0,
            [KEY_PROPOSED_PRODUCT_IMAGE_URL]:
              "",
          },
      aiGenerated: true,
      [KEY_PHASES]: normalizedPhases,
      [KEY_SUMMARY]: {
        [KEY_SUMMARY_TOTAL_TASKS]:
          totalTasks,
        [KEY_SUMMARY_TOTAL_DAYS]:
          parsePositiveInteger(
            payload.days,
            1,
          ),
        [KEY_SUMMARY_RISK_NOTES]:
          riskNotes,
      },
    },
    warnings: warnings.map(
      (warning, index) =>
        buildWarning({
          code:
            parseString(warning?.code) ||
            WARNING_ENVELOPE_MESSAGE,
          path: `payload.warnings[${index}]`,
          value: parseString(
            warning?.message,
          ),
          message:
            parseString(
              warning?.message,
            ) ||
            "Envelope warning",
        }),
    ),
  };
}

function buildPartialDraftFromEnvelope({
  envelope,
  productName,
  estateAssetId,
  productId,
  startDate,
  endDate,
  domainContext,
}) {
  const fallbackDraft = buildSafeFallbackDraft({
    productName,
    estateAssetId,
    productId,
    startDate,
    endDate,
    domainContext,
  });
  const action =
    envelope?.action ||
    ENVELOPE_ACTION_CLARIFY;
  const payload =
    envelope?.payload || {};
  let issueType =
    AI_DRAFT_ISSUE_INSUFFICIENT_CONTEXT;
  let message = parseString(
    envelope?.message,
  );
  const warnings = [
    buildWarning({
      code: WARNING_ENVELOPE_ACTION,
      path: "action",
      value: action,
      message:
        "AI returned a non-plan action; generated a safe starter draft.",
    }),
  ];

  if (action === ENVELOPE_ACTION_CLARIFY) {
    const requiredField = parseString(
      payload.requiredField,
    );
    if (
      requiredField === "productId" ||
      requiredField ===
        "productDescription"
    ) {
      issueType =
        AI_DRAFT_ISSUE_PRODUCT_NOT_INFERRED;
    } else if (
      requiredField === "startDate" ||
      requiredField === "endDate"
    ) {
      issueType =
        AI_DRAFT_ISSUE_DATE_NOT_INFERRED;
    }
    const question = parseString(
      payload.question,
    );
    const choices = Array.isArray(
      payload.choices,
    ) ?
      payload.choices
        .map((choice) =>
          parseString(choice),
        )
        .filter(Boolean)
    : [];
    if (!message) {
      message = question;
    }
    if (choices.length > 0) {
      warnings.push(
        buildWarning({
          code:
            WARNING_ENVELOPE_MESSAGE,
          path: "payload.choices",
          value:
            choices.join(", "),
          message:
            "Clarification choices returned by AI.",
        }),
      );
    }
  } else if (
    action ===
    ENVELOPE_ACTION_DRAFT_PRODUCT
  ) {
    issueType =
      AI_DRAFT_ISSUE_PRODUCT_NOT_INFERRED;
    const draftProduct =
      payload?.draftProduct;
    if (isPlainObject(draftProduct)) {
      fallbackDraft[KEY_PRODUCT_ID] = null;
      fallbackDraft[
        KEY_PROPOSED_PRODUCT
      ] = {
        [KEY_PROPOSED_PRODUCT_NAME]:
          parseString(
            draftProduct.name,
          ),
        [KEY_PROPOSED_PRODUCT_DESCRIPTION]:
          parseString(
            draftProduct.notes,
          ),
        [KEY_PROPOSED_PRODUCT_PRICE_NGN]:
          0,
        [KEY_PROPOSED_PRODUCT_STOCK]:
          0,
        [KEY_PROPOSED_PRODUCT_IMAGE_URL]:
          "",
      };
    }
    const confirmationQuestion =
      parseString(
        payload.confirmationQuestion,
      );
    if (!message) {
      message = confirmationQuestion;
    }
  } else if (
    action ===
    ENVELOPE_ACTION_SUGGESTIONS
  ) {
    const suggestions = Array.isArray(
      payload.suggestions,
    ) ?
      payload.suggestions
        .map((entry) =>
          parseString(entry),
        )
        .filter(Boolean)
    : [];
    if (suggestions.length > 0) {
      warnings.push(
        buildWarning({
          code:
            WARNING_ENVELOPE_SUGGESTION,
          path: "payload.suggestions",
          value:
            suggestions.join(" | "),
          message:
            "AI returned suggestions instead of a full plan draft.",
        }),
      );
    }
  }

  if (!message) {
    message = resolveIssueMessage(
      issueType,
      domainContext,
    );
  }

  return {
    issueType,
    message,
    draft: fallbackDraft,
    warnings,
  };
}

function extractDraftFromParsedResponse({
  parsed,
  productName,
  estateAssetId,
  productId,
  startDate,
  endDate,
  domainContext,
}) {
  // WHY: Keep backward compatibility with legacy draft-only responses.
  if (
    isPlainObject(parsed?.draft)
  ) {
    return {
      mode: "legacy",
      draft: parsed.draft,
      warnings: [],
    };
  }
  if (
    isPlainObject(parsed) &&
    parsed[KEY_PHASES] != null
  ) {
    return {
      mode: "legacy",
      draft: parsed,
      warnings: [],
    };
  }

  const envelopeValidation =
    validateEnvelopePayload(parsed);
  if (!envelopeValidation.ok) {
    const recoveredEnvelope = coerceLoosePlanDraftEnvelope({
      parsed,
      productName,
      productId,
      startDate,
      endDate,
    });
    if (recoveredEnvelope) {
      const converted = convertPlanDraftEnvelopeToLegacyDraft({
        envelope: recoveredEnvelope,
        estateAssetId,
        productId,
        domainContext,
      });
      // WHY: Recovery logs provide deterministic evidence when strict envelope validation fails but salvage succeeds.
      debug(LOG_TAG, LOG_RECOVERED, {
        action: parseString(parsed?.action),
        invalidCount: envelopeValidation.invalid.length,
        invalidPathsPreview: envelopeValidation.invalid.slice(0, 12),
        recoveredPhaseCount:
          recoveredEnvelope?.payload?.phases?.length || 0,
        recoveredTaskCount: Array.isArray(recoveredEnvelope?.payload?.phases)
          ? recoveredEnvelope.payload.phases.reduce((sum, phase) => {
              const tasks = Array.isArray(phase?.tasks) ? phase.tasks : [];
              return sum + tasks.length;
            }, 0)
          : 0,
      });
      const recoveryWarning = buildWarning({
        code: WARNING_ENVELOPE_LOOSE_RECOVERY,
        path: "envelope",
        value: envelopeValidation.invalid
          .slice(0, 20)
          .join(", "),
        message:
          "Recovered plan_draft from near-valid AI envelope. Review tasks and warnings before commit.",
      });
      return {
        mode: "legacy",
        draft: converted.draft,
        warnings: [recoveryWarning, ...(converted.warnings || [])],
      };
    }
    throw buildDraftError({
      message:
        "AI draft envelope did not match required schema.",
      classification:
        SCHEMA_CLASSIFICATION,
      errorCode:
        "PRODUCTION_AI_ENVELOPE_INVALID",
      resolutionHint:
        "Retry AI draft generation; provider returned an invalid envelope.",
      details: {
        missing: [],
        invalid:
          envelopeValidation.invalid,
        providerMessage:
          sanitizeProviderMessage(
            JSON.stringify(parsed),
          ),
      },
      providerMessage: JSON.stringify(parsed),
      retryReason:
        RETRY_REASON_SCHEMA,
    });
  }

  const envelope =
    envelopeValidation.envelope;
  if (
    envelope.action ===
    ENVELOPE_ACTION_PLAN_DRAFT
  ) {
    const converted =
      convertPlanDraftEnvelopeToLegacyDraft(
        {
          envelope,
          estateAssetId,
          productId,
          domainContext,
        },
      );
    return {
      mode: "legacy",
      draft: converted.draft,
      warnings:
        converted.warnings,
    };
  }

  const partial =
    buildPartialDraftFromEnvelope({
      envelope,
      productName,
      estateAssetId,
      productId,
      startDate,
      endDate,
      domainContext,
    });
  return {
    mode: "partial",
    ...partial,
  };
}

function isValidDateString(value) {
  if (typeof value !== "string" || !DATE_PATTERN.test(value)) {
    return false;
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return false;
  }
  return parsed.toISOString().slice(0, 10) === value;
}

function parseInteger(value) {
  if (typeof value === "number" && Number.isInteger(value)) {
    return value;
  }
  if (typeof value === "string" && /^-?\d+$/.test(value.trim())) {
    return Number.parseInt(value.trim(), 10);
  }
  return null;
}

function normalizeRoleKey(value) {
  if (typeof value !== "string") return "";
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

// WHY: Keep role matching strict but tolerant to predictable label formatting.
function buildRoleAliasMap(roles) {
  const aliases = new Map();
  for (const role of roles) {
    if (typeof role !== "string") continue;
    const canonical = role.trim();
    if (!canonical) continue;
    aliases.set(canonical, canonical);
    aliases.set(normalizeRoleKey(canonical), canonical);
  }
  return aliases;
}

function resolveCanonicalRole(roleValue, roleAliases) {
  if (typeof roleValue !== "string") return null;
  const trimmed = roleValue.trim();
  if (!trimmed) return null;
  if (roleAliases.has(trimmed)) {
    return roleAliases.get(trimmed);
  }
  const normalized = normalizeRoleKey(trimmed);
  if (!normalized) return null;
  return roleAliases.get(normalized) || null;
}

function buildRoleSet(roles) {
  return new Set(
    (roles || [])
      .map((role) =>
        typeof role === "string" ? role.trim() : "",
      )
      .filter((role) => role.length > 0),
  );
}

function sanitizeAvailableRoles(availableRoles) {
  const canonicalRoleSet = buildRoleSet(STAFF_ROLES);
  const filtered = Array.isArray(availableRoles)
    ? availableRoles
        .map((role) =>
          typeof role === "string" ? role.trim() : "",
        )
        .filter(
          (role) => role.length > 0 && canonicalRoleSet.has(role),
        )
    : [];
  const unique = Array.from(new Set(filtered));
  return unique.length > 0 ? unique : Array.from(canonicalRoleSet);
}

// WHY: Engine scoring combines task text, role responsibility, and domain bias.
function resolveClosestRole({
  taskText,
  availableRoles,
  domainContext,
}) {
  const normalizedTaskText =
    (taskText || "").toString().toLowerCase();
  const scoringRoles = sanitizeAvailableRoles(availableRoles);
  const normalizedDomainContext =
    normalizeDomainContext(domainContext);
  const domainRoles =
    DOMAIN_CONFIGS?.[normalizedDomainContext]
      ?.defaultRoles || [];
  const scores = {};

  for (const role of scoringRoles) {
    scores[role] = 0;
    const keywords = ROLE_KEYWORDS[role] || [];

    // WHY: Keyword matches are the primary execution signal.
    for (const keyword of keywords) {
      if (normalizedTaskText.includes(keyword)) {
        scores[role] += 2;
      }
    }

    // WHY: Execution roles should win by default when intent is ambiguous.
    const responsibilities =
      ROLE_RULES[role]
        ?.responsibilities || [];
    if (responsibilities.includes("EXECUTION")) {
      scores[role] += 3;
    }

    // WHY: Domain defaults are a soft bias, not a hard assignment.
    if (domainRoles.includes(role)) {
      scores[role] += 1;
    }

    // WHY: Penalize governance-heavy roles for typical execution work.
    const priority =
      ROLE_RULES[role]?.priority ?? 99;
    scores[role] -= priority * 0.5;
  }

  const best = Object.entries(scores)
    .sort((left, right) => {
      if (right[1] !== left[1]) {
        return right[1] - left[1];
      }
      return (
        scoringRoles.indexOf(left[0]) -
        scoringRoles.indexOf(right[0])
      );
    })[0];

  if (!best || best[1] <= 0) {
    return SAFE_DEFAULT_ROLE;
  }

  return best[0];
}

function buildWarning({ code, path, value, message }) {
  return {
    [KEY_WARNING_CODE]: code,
    [KEY_WARNING_PATH]: path,
    [KEY_WARNING_VALUE]: sanitizeProviderMessage(value),
    [KEY_WARNING_MESSAGE]: message,
  };
}

function buildTaskRoleContext({ task, roleValue }) {
  const fragments = [
    task?.[KEY_TASK_TITLE],
    task?.[KEY_TASK_INSTRUCTIONS],
    roleValue,
  ]
    .map((value) =>
      value == null ? "" : value.toString().trim(),
    )
    .filter((value) => value.length > 0);
  return fragments.join(" ");
}

function normalizeDraftRole({
  roleValue,
  task,
  roleAliases,
  availableRoles,
  domainContext,
}) {
  const canonical = resolveCanonicalRole(roleValue, roleAliases);
  if (canonical != null) {
    return canonical;
  }
  return resolveClosestRole({
    taskText: buildTaskRoleContext({ task, roleValue }),
    availableRoles,
    domainContext,
  });
}

function validateDraftSchema({
  draft,
  staffById,
  roleAliases,
  availableRoleSet,
  roleResolutionRoles,
  domainContext,
}) {
  const missing = [];
  const invalid = [];
  const warnings = [];
  const planTitle = draft?.[KEY_PLAN_TITLE] ?? draft?.title;
  const notes = draft?.[KEY_NOTES];
  const startDate = draft?.[KEY_START_DATE];
  const endDate = draft?.[KEY_END_DATE];
  const proposedStartDate = draft?.[KEY_PROPOSED_START_DATE];
  const proposedEndDate = draft?.[KEY_PROPOSED_END_DATE];
  const estateAssetId = draft?.[KEY_ESTATE_ASSET_ID];
  const productId = draft?.[KEY_PRODUCT_ID];
  const proposedProduct = draft?.[KEY_PROPOSED_PRODUCT];
  const phases = draft?.[KEY_PHASES];
  const summary = draft?.[KEY_SUMMARY];
  const draftDomainContext =
    draft?.[KEY_DOMAIN_CONTEXT];
  const normalizedDomainContext =
    normalizeDomainContext(
      domainContext ?? draftDomainContext,
    );
  const resolvedAvailableRoleSet =
    availableRoleSet instanceof Set
      ? availableRoleSet
      : buildRoleSet(availableRoleSet);
  const hasDirectoryRoleCoverage =
    resolvedAvailableRoleSet.size > 0;
  const resolvedRoleResolutionRoles = sanitizeAvailableRoles(
    roleResolutionRoles,
  );

  if (draftDomainContext != null) {
    const rawDomainContext =
      draftDomainContext.toString().trim();
    const domainWasNormalized =
      normalizeDomainContext(rawDomainContext) !==
      rawDomainContext;
    if (domainWasNormalized) {
      // WHY: Domain context should be normalized in draft mode, not rejected.
      warnings.push(
        buildWarning({
          code: WARNING_DOMAIN_CONTEXT_NORMALIZED,
          path: KEY_DOMAIN_CONTEXT,
          value: `${rawDomainContext} -> ${normalizedDomainContext}`,
          message:
            "Domain context was normalized to a supported value for engine safety.",
        }),
      );
    }
  }

  if (planTitle == null) {
    missing.push(KEY_PLAN_TITLE);
  } else if (typeof planTitle !== "string" || !planTitle.trim()) {
    invalid.push(KEY_PLAN_TITLE);
  }
  if (notes == null) {
    missing.push(KEY_NOTES);
  } else if (typeof notes !== "string") {
    invalid.push(KEY_NOTES);
  }
  if (startDate != null && !isValidDateString(startDate)) {
    invalid.push(KEY_START_DATE);
  }
  if (endDate != null && !isValidDateString(endDate)) {
    invalid.push(KEY_END_DATE);
  }
  if (proposedStartDate != null && !isValidDateString(proposedStartDate)) {
    invalid.push(KEY_PROPOSED_START_DATE);
  }
  if (proposedEndDate != null && !isValidDateString(proposedEndDate)) {
    invalid.push(KEY_PROPOSED_END_DATE);
  }
  const resolvedStartDate = isValidDateString(startDate)
    ? startDate
    : isValidDateString(proposedStartDate)
      ? proposedStartDate
      : null;
  const resolvedEndDate = isValidDateString(endDate)
    ? endDate
    : isValidDateString(proposedEndDate)
      ? proposedEndDate
      : null;
  if (resolvedStartDate == null) {
    missing.push(KEY_START_DATE);
  }
  if (resolvedEndDate == null) {
    missing.push(KEY_END_DATE);
  }
  if (
    resolvedStartDate != null &&
    resolvedEndDate != null &&
    resolvedEndDate <= resolvedStartDate
  ) {
    invalid.push(
      isValidDateString(endDate) ? KEY_END_DATE : KEY_PROPOSED_END_DATE,
    );
  }
  if (estateAssetId == null) {
    missing.push(KEY_ESTATE_ASSET_ID);
  } else if (typeof estateAssetId !== "string" || !estateAssetId.trim()) {
    invalid.push(KEY_ESTATE_ASSET_ID);
  }
  const hasValidProductId =
    typeof productId === "string" && productId.trim().length > 0;
  if (productId != null && !hasValidProductId) {
    invalid.push(KEY_PRODUCT_ID);
  }
  if (!hasValidProductId && proposedProduct == null) {
    missing.push(KEY_PRODUCT_ID);
    missing.push(KEY_PROPOSED_PRODUCT);
  }
  if (
    !hasValidProductId &&
    proposedProduct != null &&
    (typeof proposedProduct !== "object" ||
      Array.isArray(proposedProduct))
  ) {
    invalid.push(KEY_PROPOSED_PRODUCT);
  } else if (
    !hasValidProductId &&
    proposedProduct != null
  ) {
    const productPath = KEY_PROPOSED_PRODUCT;
    if (
      !proposedProduct[KEY_PROPOSED_PRODUCT_NAME] ||
      typeof proposedProduct[KEY_PROPOSED_PRODUCT_NAME] !== "string" ||
      !proposedProduct[KEY_PROPOSED_PRODUCT_NAME].trim()
    ) {
      invalid.push(`${productPath}.${KEY_PROPOSED_PRODUCT_NAME}`);
    }
    if (
      !proposedProduct[KEY_PROPOSED_PRODUCT_DESCRIPTION] ||
      typeof proposedProduct[KEY_PROPOSED_PRODUCT_DESCRIPTION] !== "string" ||
      !proposedProduct[KEY_PROPOSED_PRODUCT_DESCRIPTION].trim()
    ) {
      invalid.push(`${productPath}.${KEY_PROPOSED_PRODUCT_DESCRIPTION}`);
    }
    const priceNgn = parseInteger(
      proposedProduct[KEY_PROPOSED_PRODUCT_PRICE_NGN],
    );
    if (priceNgn == null || priceNgn < 0) {
      invalid.push(`${productPath}.${KEY_PROPOSED_PRODUCT_PRICE_NGN}`);
    }
    const stock = parseInteger(proposedProduct[KEY_PROPOSED_PRODUCT_STOCK]);
    if (stock == null || stock < 0) {
      invalid.push(`${productPath}.${KEY_PROPOSED_PRODUCT_STOCK}`);
    }
    if (
      proposedProduct[KEY_PROPOSED_PRODUCT_IMAGE_URL] != null &&
      typeof proposedProduct[KEY_PROPOSED_PRODUCT_IMAGE_URL] !== "string"
    ) {
      invalid.push(`${productPath}.${KEY_PROPOSED_PRODUCT_IMAGE_URL}`);
    }
  }
  if (phases == null) {
    missing.push(KEY_PHASES);
  } else if (!Array.isArray(phases) || phases.length === 0) {
    invalid.push(KEY_PHASES);
  }
  if (summary == null) {
    missing.push(KEY_SUMMARY);
  } else if (typeof summary !== "object" || Array.isArray(summary)) {
    invalid.push(KEY_SUMMARY);
  }

  if (Array.isArray(phases)) {
    phases.forEach((phase, phaseIndex) => {
      const phasePath = `${KEY_PHASES}[${phaseIndex}]`;
      if (!phase || typeof phase !== "object" || Array.isArray(phase)) {
        invalid.push(phasePath);
        return;
      }

      if (phase[KEY_PHASE_NAME] == null) {
        missing.push(`${phasePath}.${KEY_PHASE_NAME}`);
      } else if (
        typeof phase[KEY_PHASE_NAME] !== "string" ||
        !phase[KEY_PHASE_NAME].trim()
      ) {
        invalid.push(`${phasePath}.${KEY_PHASE_NAME}`);
      }

      const order = parseInteger(phase[KEY_PHASE_ORDER]);
      if (phase[KEY_PHASE_ORDER] == null) {
        missing.push(`${phasePath}.${KEY_PHASE_ORDER}`);
      } else if (order == null || order < 1) {
        invalid.push(`${phasePath}.${KEY_PHASE_ORDER}`);
      }

      const estimatedDays = parseInteger(phase[KEY_PHASE_ESTIMATED_DAYS]);
      if (phase[KEY_PHASE_ESTIMATED_DAYS] == null) {
        missing.push(`${phasePath}.${KEY_PHASE_ESTIMATED_DAYS}`);
      } else if (
        estimatedDays == null ||
        estimatedDays < MIN_ESTIMATED_DAYS ||
        estimatedDays > MAX_ESTIMATED_DAYS
      ) {
        invalid.push(`${phasePath}.${KEY_PHASE_ESTIMATED_DAYS}`);
      }

      const tasks = phase[KEY_TASKS];
      if (tasks == null) {
        missing.push(`${phasePath}.${KEY_TASKS}`);
      } else if (!Array.isArray(tasks)) {
        invalid.push(`${phasePath}.${KEY_TASKS}`);
      }

      if (Array.isArray(tasks)) {
        tasks.forEach((task, taskIndex) => {
          const taskPath = `${phasePath}.${KEY_TASKS}[${taskIndex}]`;
          if (!task || typeof task !== "object" || Array.isArray(task)) {
            invalid.push(taskPath);
            return;
          }

          if (task[KEY_TASK_TITLE] == null) {
            missing.push(`${taskPath}.${KEY_TASK_TITLE}`);
          } else if (
            typeof task[KEY_TASK_TITLE] !== "string" ||
            !task[KEY_TASK_TITLE].trim()
          ) {
            invalid.push(`${taskPath}.${KEY_TASK_TITLE}`);
          }

          if (task[KEY_TASK_ROLE] == null) {
            missing.push(`${taskPath}.${KEY_TASK_ROLE}`);
          } else if (
            typeof task[KEY_TASK_ROLE] !== "string" ||
            !task[KEY_TASK_ROLE].trim()
          ) {
            invalid.push(`${taskPath}.${KEY_TASK_ROLE}`);
          } else {
            const normalizedRole = normalizeDraftRole({
              roleValue: task[KEY_TASK_ROLE],
              task,
              roleAliases,
              availableRoles: resolvedRoleResolutionRoles,
              domainContext: normalizedDomainContext,
            });
            const canonicalRole = resolveCanonicalRole(
              task[KEY_TASK_ROLE],
              roleAliases,
            );

            if (canonicalRole == null) {
              // WHY: Unknown AI role labels are normalized so draft mode never blocks.
              warnings.push(
                buildWarning({
                  code: WARNING_ROLE_NORMALIZED,
                  path: `${taskPath}.${KEY_TASK_ROLE}`,
                  value: `${task[KEY_TASK_ROLE]} -> ${normalizedRole}`,
                  message:
                    "Role was normalized to the closest canonical staff role for draft safety.",
                }),
              );
            }

            if (
              hasDirectoryRoleCoverage &&
              !resolvedAvailableRoleSet.has(normalizedRole)
            ) {
              // WHY: Draft mode permits canonical roles that are not yet staffed.
              warnings.push(
                buildWarning({
                  code: WARNING_ROLE_NOT_IN_DIRECTORY,
                  path: `${taskPath}.${KEY_TASK_ROLE}`,
                  value: normalizedRole,
                  message:
                    "Role is not currently in your staff directory; confirm or edit before final save.",
                }),
              );
            }
          }

          if (task[KEY_TASK_WEIGHT] == null) {
            missing.push(`${taskPath}.${KEY_TASK_WEIGHT}`);
          } else {
            const weight = parseInteger(task[KEY_TASK_WEIGHT]);
            if (weight == null || weight < MIN_WEIGHT || weight > MAX_WEIGHT) {
              invalid.push(`${taskPath}.${KEY_TASK_WEIGHT}`);
            }
          }

          if (task[KEY_TASK_REQUIRED_HEADCOUNT] != null) {
            const requiredHeadcount = parseInteger(
              task[KEY_TASK_REQUIRED_HEADCOUNT],
            );
            if (requiredHeadcount == null || requiredHeadcount < 1) {
              invalid.push(`${taskPath}.${KEY_TASK_REQUIRED_HEADCOUNT}`);
            }
          }

          if (task[KEY_TASK_INSTRUCTIONS] == null) {
            missing.push(`${taskPath}.${KEY_TASK_INSTRUCTIONS}`);
          } else if (
            typeof task[KEY_TASK_INSTRUCTIONS] !== "string" ||
            !task[KEY_TASK_INSTRUCTIONS].trim()
          ) {
            invalid.push(`${taskPath}.${KEY_TASK_INSTRUCTIONS}`);
          }

          const assignedStaffId = task[KEY_TASK_ASSIGNED_STAFF];
          if (assignedStaffId != null) {
            if (
              typeof assignedStaffId !== "string" ||
              !assignedStaffId.trim()
            ) {
              invalid.push(`${taskPath}.${KEY_TASK_ASSIGNED_STAFF}`);
            } else if (!staffById.has(assignedStaffId.trim())) {
              // WHY: Draft mode can carry AI staff suggestions that are not in directory.
              warnings.push(
                buildWarning({
                  code: WARNING_ASSIGNED_STAFF_NOT_IN_DIRECTORY,
                  path: `${taskPath}.${KEY_TASK_ASSIGNED_STAFF}`,
                  value: assignedStaffId,
                  message:
                    "Assigned staff is not in your current staff directory; pick a valid assignee before final save.",
                }),
              );
            }
          }
        });
      }
    });
  }

  if (summary && typeof summary === "object" && !Array.isArray(summary)) {
    const totalTasks = parseInteger(summary[KEY_SUMMARY_TOTAL_TASKS]);
    if (summary[KEY_SUMMARY_TOTAL_TASKS] == null) {
      missing.push(`${KEY_SUMMARY}.${KEY_SUMMARY_TOTAL_TASKS}`);
    } else if (totalTasks == null || totalTasks < 0) {
      invalid.push(`${KEY_SUMMARY}.${KEY_SUMMARY_TOTAL_TASKS}`);
    }

    const totalEstimatedDays = parseInteger(summary[KEY_SUMMARY_TOTAL_DAYS]);
    if (summary[KEY_SUMMARY_TOTAL_DAYS] == null) {
      missing.push(`${KEY_SUMMARY}.${KEY_SUMMARY_TOTAL_DAYS}`);
    } else if (totalEstimatedDays == null || totalEstimatedDays < 0) {
      invalid.push(`${KEY_SUMMARY}.${KEY_SUMMARY_TOTAL_DAYS}`);
    }

    const riskNotes = summary[KEY_SUMMARY_RISK_NOTES];
    if (riskNotes == null) {
      missing.push(`${KEY_SUMMARY}.${KEY_SUMMARY_RISK_NOTES}`);
    } else if (
      !Array.isArray(riskNotes) ||
      riskNotes.some(
        (entry) => typeof entry !== "string" || !entry.trim(),
      )
    ) {
      invalid.push(`${KEY_SUMMARY}.${KEY_SUMMARY_RISK_NOTES}`);
    }
  }

  return { missing, invalid, warnings };
}

function normalizeDraft({
  draft,
  roleAliases,
  roleResolutionRoles,
  domainContext,
}) {
  const resolvedRoleResolutionRoles = sanitizeAvailableRoles(
    roleResolutionRoles,
  );
  const normalizedDomainContext =
    normalizeDomainContext(
      domainContext ??
        draft?.[KEY_DOMAIN_CONTEXT],
    );
  const normalizedTitle =
    draft?.[KEY_PLAN_TITLE]?.toString().trim() ||
    draft?.title?.toString().trim() ||
    DEFAULT_TITLE_FALLBACK;
  const normalizedProductId =
    typeof draft?.[KEY_PRODUCT_ID] === "string" &&
    draft[KEY_PRODUCT_ID].trim().length > 0
      ? draft[KEY_PRODUCT_ID].trim()
      : null;
  const proposedProductRaw = draft?.[KEY_PROPOSED_PRODUCT];
  const normalizedProposedProduct =
    normalizedProductId == null &&
    proposedProductRaw &&
    typeof proposedProductRaw === "object" &&
    !Array.isArray(proposedProductRaw)
      ? {
          [KEY_PROPOSED_PRODUCT_NAME]: (
            proposedProductRaw[KEY_PROPOSED_PRODUCT_NAME] || ""
          )
            .toString()
            .trim(),
          [KEY_PROPOSED_PRODUCT_DESCRIPTION]: (
            proposedProductRaw[KEY_PROPOSED_PRODUCT_DESCRIPTION] || ""
          )
            .toString()
            .trim(),
          [KEY_PROPOSED_PRODUCT_PRICE_NGN]: parseInteger(
            proposedProductRaw[KEY_PROPOSED_PRODUCT_PRICE_NGN],
          ),
          [KEY_PROPOSED_PRODUCT_STOCK]: parseInteger(
            proposedProductRaw[KEY_PROPOSED_PRODUCT_STOCK],
          ),
          [KEY_PROPOSED_PRODUCT_IMAGE_URL]:
            proposedProductRaw[KEY_PROPOSED_PRODUCT_IMAGE_URL]
              ?.toString()
              .trim() ||
            "",
        }
      : null;
  const normalizedStartDate = isValidDateString(draft?.[KEY_START_DATE])
    ? draft[KEY_START_DATE]
    : null;
  const normalizedEndDate = isValidDateString(draft?.[KEY_END_DATE])
    ? draft[KEY_END_DATE]
    : null;
  const normalizedProposedStartDate =
    normalizedStartDate == null && isValidDateString(draft?.[KEY_PROPOSED_START_DATE])
      ? draft[KEY_PROPOSED_START_DATE]
      : null;
  const normalizedProposedEndDate =
    normalizedEndDate == null && isValidDateString(draft?.[KEY_PROPOSED_END_DATE])
      ? draft[KEY_PROPOSED_END_DATE]
      : null;

  const normalizedPhases = draft[KEY_PHASES]
    .map((phase) => ({
      [KEY_PHASE_NAME]: phase[KEY_PHASE_NAME].toString().trim(),
      [KEY_PHASE_ORDER]: parseInteger(phase[KEY_PHASE_ORDER]),
      [KEY_PHASE_ESTIMATED_DAYS]: parseInteger(phase[KEY_PHASE_ESTIMATED_DAYS]),
      [KEY_TASKS]: phase[KEY_TASKS].map((task) => ({
        [KEY_TASK_TITLE]: task[KEY_TASK_TITLE].toString().trim(),
        [KEY_TASK_ROLE]: normalizeDraftRole({
          roleValue: task[KEY_TASK_ROLE],
          task,
          roleAliases,
          availableRoles: resolvedRoleResolutionRoles,
          domainContext: normalizedDomainContext,
        }),
        [KEY_TASK_ASSIGNED_STAFF]:
          task[KEY_TASK_ASSIGNED_STAFF] == null
            ? null
            : task[KEY_TASK_ASSIGNED_STAFF].toString().trim(),
        [KEY_TASK_REQUIRED_HEADCOUNT]:
          task[KEY_TASK_REQUIRED_HEADCOUNT] == null
            ? 1
            : Math.max(
                1,
                parseInteger(task[KEY_TASK_REQUIRED_HEADCOUNT]) || 1,
              ),
        [KEY_TASK_WEIGHT]: parseInteger(task[KEY_TASK_WEIGHT]),
        [KEY_TASK_INSTRUCTIONS]: task[KEY_TASK_INSTRUCTIONS].toString().trim(),
      })),
    }))
    .sort((left, right) => left[KEY_PHASE_ORDER] - right[KEY_PHASE_ORDER]);

  const summaryRiskNotes = draft[KEY_SUMMARY][KEY_SUMMARY_RISK_NOTES].map((item) =>
    item.toString().trim(),
  );

  return {
    [KEY_PLAN_TITLE]: normalizedTitle,
    // WHY: Keep backward compatibility for existing clients still reading "title".
    title: normalizedTitle,
    [KEY_NOTES]: draft[KEY_NOTES].toString().trim() || DEFAULT_NOTES_FALLBACK,
    [KEY_DOMAIN_CONTEXT]: normalizedDomainContext,
    [KEY_START_DATE]: normalizedStartDate,
    [KEY_END_DATE]: normalizedEndDate,
    [KEY_PROPOSED_START_DATE]: normalizedProposedStartDate,
    [KEY_PROPOSED_END_DATE]: normalizedProposedEndDate,
    [KEY_ESTATE_ASSET_ID]: draft[KEY_ESTATE_ASSET_ID].toString().trim(),
    [KEY_PRODUCT_ID]: normalizedProductId,
    [KEY_PROPOSED_PRODUCT]: normalizedProposedProduct,
    aiGenerated: true,
    [KEY_PHASES]: normalizedPhases,
    [KEY_SUMMARY]: {
      [KEY_SUMMARY_TOTAL_TASKS]: parseInteger(
        draft[KEY_SUMMARY][KEY_SUMMARY_TOTAL_TASKS],
      ),
      [KEY_SUMMARY_TOTAL_DAYS]: parseInteger(
        draft[KEY_SUMMARY][KEY_SUMMARY_TOTAL_DAYS],
      ),
      [KEY_SUMMARY_RISK_NOTES]: summaryRiskNotes,
    },
  };
}

function isDateIssuePath(path) {
  return [
    KEY_START_DATE,
    KEY_END_DATE,
    KEY_PROPOSED_START_DATE,
    KEY_PROPOSED_END_DATE,
  ].includes(path);
}

function isProductIssuePath(path) {
  if (path === KEY_PRODUCT_ID || path === KEY_PROPOSED_PRODUCT) {
    return true;
  }
  return path.startsWith(`${KEY_PROPOSED_PRODUCT}.`);
}

function isSoftIssuePath(path) {
  return isDateIssuePath(path) || isProductIssuePath(path);
}

function splitSchemaDiagnostics({ missing, invalid }) {
  const softMissing = [];
  const hardMissing = [];
  const softInvalid = [];
  const hardInvalid = [];

  for (const path of missing) {
    if (isSoftIssuePath(path)) {
      softMissing.push(path);
    } else {
      hardMissing.push(path);
    }
  }

  for (const path of invalid) {
    if (isSoftIssuePath(path)) {
      softInvalid.push(path);
    } else {
      hardInvalid.push(path);
    }
  }

  return {
    softMissing,
    hardMissing,
    softInvalid,
    hardInvalid,
  };
}

function resolveSoftIssueType({
  softMissing,
  softInvalid,
}) {
  const softPaths = [...softMissing, ...softInvalid];
  const hasProductIssue = softPaths.some((path) =>
    isProductIssuePath(path),
  );
  const hasDateIssue = softPaths.some((path) =>
    isDateIssuePath(path),
  );

  if (hasProductIssue && hasDateIssue) {
    return AI_DRAFT_ISSUE_INSUFFICIENT_CONTEXT;
  }
  if (hasProductIssue) {
    return AI_DRAFT_ISSUE_PRODUCT_NOT_INFERRED;
  }
  if (hasDateIssue) {
    return AI_DRAFT_ISSUE_DATE_NOT_INFERRED;
  }
  return AI_DRAFT_ISSUE_INSUFFICIENT_CONTEXT;
}

function resolveIssueMessage(issueType, domainContext) {
  const normalizedDomainContext =
    normalizeDomainContext(domainContext);
  switch (issueType) {
    case AI_DRAFT_ISSUE_PRODUCT_NOT_INFERRED:
      return AI_DRAFT_ISSUE_MESSAGE_PRODUCT_NOT_INFERRED;
    case AI_DRAFT_ISSUE_DATE_NOT_INFERRED:
      return AI_DRAFT_ISSUE_MESSAGE_DATE_NOT_INFERRED;
    case AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE:
      return AI_DRAFT_ISSUE_MESSAGE_HARD_SCHEMA_FAILURE;
    case AI_DRAFT_ISSUE_INSUFFICIENT_CONTEXT:
      if (
        normalizedDomainContext !==
        DEFAULT_PRODUCTION_DOMAIN_CONTEXT
      ) {
        return `${AI_DRAFT_ISSUE_MESSAGE_INSUFFICIENT_CONTEXT_WITH_DOMAIN} (${normalizedDomainContext}).`;
      }
      return AI_DRAFT_ISSUE_MESSAGE_INSUFFICIENT_CONTEXT;
    default:
      return AI_DRAFT_ISSUE_MESSAGE_INSUFFICIENT_CONTEXT;
  }
}

function buildPartialDraftResponse({
  issueType,
  draft,
  warnings,
  diagnostics,
  message,
  domainContext,
}) {
  return {
    status: AI_DRAFT_STATUS_PARTIAL,
    issueType,
    message: message || resolveIssueMessage(issueType, domainContext),
    draft,
    warnings,
    diagnostics,
  };
}

function buildSafeFallbackDraft({
  productName,
  estateAssetId,
  productId,
  startDate,
  endDate,
  domainContext,
}) {
  const fallbackPhases =
    buildFallbackPhaseTemplates(
      domainContext,
    );
  const totalEstimatedDays = fallbackPhases.reduce(
    (sum, phase) =>
      sum + phase[KEY_PHASE_ESTIMATED_DAYS],
    0,
  );
  const normalizedProductId =
    typeof productId === "string" && productId.trim()
      ? productId.trim()
      : null;
  const fallbackRange =
    buildFallbackRangeDates({
      startDate,
      endDate,
    });
  const normalizedDomainContext =
    normalizeDomainContext(domainContext);

  return {
    [KEY_PLAN_TITLE]: productName?.toString().trim() || DEFAULT_TITLE_FALLBACK,
    // WHY: Keep backward compatibility for existing clients still reading "title".
    title: productName?.toString().trim() || DEFAULT_TITLE_FALLBACK,
    [KEY_NOTES]: DEFAULT_NOTES_FALLBACK,
    [KEY_DOMAIN_CONTEXT]: normalizedDomainContext,
    [KEY_START_DATE]:
      fallbackRange.providedStart,
    [KEY_END_DATE]:
      fallbackRange.providedEnd,
    [KEY_PROPOSED_START_DATE]:
      fallbackRange.providedStart ?
        null
      : fallbackRange.resolvedStart,
    [KEY_PROPOSED_END_DATE]:
      fallbackRange.providedEnd ?
        null
      : fallbackRange.resolvedEnd,
    [KEY_ESTATE_ASSET_ID]: estateAssetId?.toString().trim() || "",
    [KEY_PRODUCT_ID]: normalizedProductId,
    [KEY_PROPOSED_PRODUCT]: null,
    aiGenerated: true,
    [KEY_PHASES]: fallbackPhases,
    [KEY_SUMMARY]: {
      [KEY_SUMMARY_TOTAL_TASKS]: 0,
      [KEY_SUMMARY_TOTAL_DAYS]: totalEstimatedDays,
      [KEY_SUMMARY_RISK_NOTES]: [
        "AI output did not fully match schema. Review and complete this draft manually.",
      ],
    },
  };
}

function buildServiceContext({ context, useReasoning, hasPrompt }) {
  return {
    country: context?.country || "unknown",
    source: context?.source || AI_SOURCE,
    domainContext: normalizeDomainContext(
      context?.domainContext,
    ),
    hasAssistantPrompt: Boolean(hasPrompt),
    hasUseReasoning: Boolean(useReasoning),
  };
}

async function generateProductionPlanDraft({
  productName,
  estateName,
  startDate,
  endDate,
  domainContext,
  estateAssetId,
  productId,
  staffProfiles,
  assistantPrompt,
  useReasoning = false,
  context = {},
}) {
  const provider = resolveProviderName();
  const requestId = context?.requestId || "unknown";
  const normalizedDomainContext =
    normalizeDomainContext(
      domainContext ??
        context?.domainContext,
    );
  const requestContext = buildServiceContext({
    context: {
      ...context,
      domainContext: normalizedDomainContext,
    },
    useReasoning,
    hasPrompt: assistantPrompt,
  });

  try {
    const sanitizedPrompt = sanitizeAssistantPrompt(assistantPrompt);
    debug(LOG_TAG, LOG_START, {
      staffCount: staffProfiles.length,
      useReasoning,
      hasAssistantPrompt: Boolean(sanitizedPrompt),
    });

    const staffRoster = buildStaffRoster(staffProfiles);
    const userPrompt = buildUserPrompt({
      productName,
      estateName,
      startDate,
      endDate,
      domainContext: normalizedDomainContext,
      staffRoster,
      assistantPrompt: sanitizedPrompt,
    });

    const response = await createAiChatCompletion({
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userPrompt }],
      useReasoning,
      context: {
        ...context,
        domainContext: normalizedDomainContext,
        operation: AI_OPERATION,
        intent: AI_INTENT,
        source: AI_SOURCE,
      },
    });

    const diagnosticsMeta = {
      provider,
      model: response?.model || null,
      requestId,
      domainContext: normalizedDomainContext,
    };
    const roleResolutionRoles = sanitizeAvailableRoles(STAFF_ROLES);
    const canonicalRoleSet = buildRoleSet(roleResolutionRoles);
    const availableDirectoryRoles = Array.from(
      new Set(
        staffProfiles
          .map((profile) =>
            profile?.staffRole?.toString().trim() || "",
          )
          .filter(
            (role) =>
              role.length > 0 && canonicalRoleSet.has(role),
          ),
      ),
    );
    const roleAliases = buildRoleAliasMap(roleResolutionRoles);
    const availableRoleSet = buildRoleSet(availableDirectoryRoles);
    const staffById = new Map(
      staffRoster
        .filter((entry) => entry.id)
        .map((entry) => [entry.id.toString(), entry]),
    );
    let parsed = null;
    let envelopeWarnings = [];
    try {
      const parsedResponse = parseAiDraft(
        response.content,
      );
      const extracted =
        extractDraftFromParsedResponse({
          parsed: parsedResponse,
          productName,
          estateAssetId,
          productId,
          startDate,
          endDate,
          domainContext:
            normalizedDomainContext,
        });
      if (extracted.mode === "partial") {
        debug(LOG_TAG, LOG_PARTIAL, {
          issueType:
            extracted.issueType,
          message:
            extracted.message,
          reason:
            "ai_envelope_non_plan_action",
        });
        return buildPartialDraftResponse({
          issueType:
            extracted.issueType,
          message:
            extracted.message,
          draft: extracted.draft,
          warnings:
            extracted.warnings || [],
          diagnostics: diagnosticsMeta,
          domainContext:
            normalizedDomainContext,
        });
      }
      parsed = extracted.draft;
      envelopeWarnings =
        extracted.warnings || [];
    } catch (parseError) {
      const fallbackDraft = buildSafeFallbackDraft({
        productName,
        estateAssetId,
        productId,
        startDate,
        endDate,
        domainContext: normalizedDomainContext,
      });
      const parseWarnings = [
        buildWarning({
          code: AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
          path: KEY_PHASES,
          value: parseError?.providerMessage || response.content,
          message:
            "AI output could not be parsed, so a safe starter draft was generated.",
        }),
      ];

      debug(LOG_TAG, LOG_PARTIAL, {
        issueType: AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
        message: resolveIssueMessage(
          AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
          normalizedDomainContext,
        ),
        classification:
          parseError?.classification || SCHEMA_CLASSIFICATION,
        errorCode:
          parseError?.errorCode || PARSE_ERROR_CODE,
        invalidPathsPreview: Array.isArray(parseError?.details?.invalid)
          ? parseError.details.invalid.slice(0, 12)
          : [],
        missingPathsPreview: Array.isArray(parseError?.details?.missing)
          ? parseError.details.missing.slice(0, 12)
          : [],
      });

      return buildPartialDraftResponse({
        issueType: AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
        message: resolveIssueMessage(
          AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
          normalizedDomainContext,
        ),
        draft: fallbackDraft,
        warnings: parseWarnings,
        diagnostics: diagnosticsMeta,
        domainContext: normalizedDomainContext,
      });
    }

    const diagnostics = validateDraftSchema({
      draft: parsed,
      staffById,
      roleAliases,
      availableRoleSet,
      roleResolutionRoles,
      domainContext: normalizedDomainContext,
    });
    const combinedWarnings = [
      ...envelopeWarnings,
      ...diagnostics.warnings,
    ];
    const schemaSplit = splitSchemaDiagnostics({
      missing: diagnostics.missing,
      invalid: diagnostics.invalid,
    });
    const hasHardSchemaIssues =
      schemaSplit.hardMissing.length > 0 ||
      schemaSplit.hardInvalid.length > 0;
    if (hasHardSchemaIssues) {
      const fallbackDraft = buildSafeFallbackDraft({
        productName,
        estateAssetId,
        productId,
        startDate,
        endDate,
        domainContext: normalizedDomainContext,
      });

      debug(LOG_TAG, LOG_PARTIAL, {
        issueType: AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
        message: resolveIssueMessage(
          AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
          normalizedDomainContext,
        ),
        missing: schemaSplit.hardMissing,
        invalid: schemaSplit.hardInvalid,
      });

      return buildPartialDraftResponse({
        issueType: AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
        message: resolveIssueMessage(
          AI_DRAFT_ISSUE_HARD_SCHEMA_FAILURE,
          normalizedDomainContext,
        ),
        draft: fallbackDraft,
        warnings: combinedWarnings,
        diagnostics: diagnosticsMeta,
        domainContext: normalizedDomainContext,
      });
    }

    const normalized = normalizeDraft({
      draft: parsed,
      roleAliases,
      roleResolutionRoles,
      domainContext: normalizedDomainContext,
    });
    const hasSoftSchemaIssues =
      schemaSplit.softMissing.length > 0 ||
      schemaSplit.softInvalid.length > 0;
    if (hasSoftSchemaIssues) {
      const issueType = resolveSoftIssueType({
        softMissing: schemaSplit.softMissing,
        softInvalid: schemaSplit.softInvalid,
      });

      debug(LOG_TAG, LOG_PARTIAL, {
        issueType,
        message: resolveIssueMessage(
          issueType,
          normalizedDomainContext,
        ),
        softMissing: schemaSplit.softMissing,
        softInvalid: schemaSplit.softInvalid,
      });

      return buildPartialDraftResponse({
        issueType,
        message: resolveIssueMessage(
          issueType,
          normalizedDomainContext,
        ),
        draft: normalized,
        warnings: combinedWarnings,
        diagnostics: diagnosticsMeta,
        domainContext: normalizedDomainContext,
      });
    }

    debug(LOG_TAG, LOG_SUCCESS, {
      phaseCount: normalized[KEY_PHASES].length,
      totalTasks: normalized[KEY_SUMMARY][KEY_SUMMARY_TOTAL_TASKS],
      totalEstimatedDays: normalized[KEY_SUMMARY][KEY_SUMMARY_TOTAL_DAYS],
    });

    return {
      status: AI_DRAFT_STATUS_SUCCESS,
      draft: normalized,
      warnings: combinedWarnings,
      diagnostics: diagnosticsMeta,
    };
  } catch (err) {
    const classification =
      err.classification || UNKNOWN_CLASSIFICATION;
    const errorCode = err.errorCode || UNKNOWN_ERROR_CODE;
    const resolutionHint =
      err.resolutionHint || UNKNOWN_RESOLUTION_HINT;
    const providerMessage = sanitizeProviderMessage(
      err.providerMessage || err.message,
    );
    const retryMeta =
      err.retry_allowed === true
        ? {
            retry_allowed: true,
            retry_reason:
              err.retry_reason || RETRY_REASON_SCHEMA,
          }
        : {
            retry_skipped: true,
            retry_reason:
              err.retry_reason || RETRY_SKIPPED_REASON,
          };

    debug(LOG_TAG, LOG_ERROR, {
      service: SERVICE_NAME,
      operation: AI_OPERATION,
      intent: AI_REQUEST_PURPOSE,
      request_context: requestContext,
      http_status: err.httpStatus || null,
      provider_error_code:
        err.providerErrorCode || null,
      provider_message: providerMessage,
      classification: classification,
      error_code: errorCode,
      resolution_hint: resolutionHint,
      ...retryMeta,
      reason: "ai_draft_generation_failed",
    });

    if (!err.classification) {
      err.classification = classification;
    }
    if (!err.errorCode) {
      err.errorCode = errorCode;
    }
    if (!err.resolutionHint) {
      err.resolutionHint = resolutionHint;
    }
    if (!err.providerMessage) {
      err.providerMessage = providerMessage;
    }
    if (err.retry_allowed !== true) {
      err.retry_skipped = true;
      err.retry_reason = RETRY_SKIPPED_REASON;
    } else if (!err.retry_reason) {
      err.retry_reason = RETRY_REASON_SCHEMA;
    }

    throw err;
  }
}

module.exports = {
  generateProductionPlanDraft,
};
