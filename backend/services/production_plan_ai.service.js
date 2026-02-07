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
  DEFAULT_PRODUCTION_PHASES,
} = require("../utils/production_defaults");

// WHY: Centralize logging labels for AI draft generation.
const LOG_TAG = "PRODUCTION_AI";
const LOG_START = "production plan draft start";
const LOG_SUCCESS = "production plan draft success";
const LOG_ERROR = "production plan draft error";

// WHY: Keep model intent values consistent in AI logs.
const AI_OPERATION = "ProductionPlanDraft";
const AI_INTENT = "generate production plan draft";
const AI_SOURCE = "backend";
const AI_REQUEST_PURPOSE = "build strict production plan draft";
const SERVICE_NAME = "production_plan_ai_service";

// WHY: Prevent brittle parsing by standardizing strict JSON instructions.
const SYSTEM_PROMPT =
  "You are a farm production planning assistant. " +
  "Return ONLY valid JSON with no markdown, code fences, or additional text.";

// WHY: Strict schema prevents downstream JSON parsing drift.
const DRAFT_SCHEMA_HINT = [
  "Return one JSON object with this exact shape:",
  "{",
  '  "planTitle": "string",',
  '  "notes": "string",',
  '  "startDate": "YYYY-MM-DD (optional when proposedStartDate is provided)",',
  '  "endDate": "YYYY-MM-DD (optional when proposedEndDate is provided)",',
  '  "proposedStartDate": "YYYY-MM-DD (required if startDate missing)",',
  '  "proposedEndDate": "YYYY-MM-DD (required if endDate missing)",',
  '  "estateAssetId": "string",',
  '  "productId": "string (optional when proposedProduct is provided)",',
  '  "proposedProduct": {',
  '    "name": "string",',
  '    "description": "string",',
  '    "priceNgn": 100000,',
  '    "stock": 20,',
  '    "imageUrl": "optional string"',
  "  },",
  '  "phases": [',
  "    {",
  '      "name": "Planning|Planting|Irrigation|Harvest|Storage",',
  '      "order": 1,',
  '      "estimatedDays": 7,',
  '      "tasks": [',
  "        {",
  '          "title": "Task name",',
  '          "roleRequired": "valid staff role",',
  '          "assignedStaffId": "optional staff profile id",',
  '          "weight": 1,',
  '          "instructions": "string"',
  "        }",
  "      ]",
  "    }",
  "  ],",
  '  "summary": {',
  '    "totalTasks": 20,',
  '    "totalEstimatedDays": 60,',
  '    "riskNotes": ["string"]',
  "  }",
  "}",
].join("\n");

// WHY: Defaults are only used for non-schema prompt context, not output coercion.
const DEFAULT_TITLE_FALLBACK = "Production plan draft";
const DEFAULT_NOTES_FALLBACK = "";
const MIN_WEIGHT = 1;
const MAX_WEIGHT = 5;
const MIN_ESTIMATED_DAYS = 1;
const MAX_ESTIMATED_DAYS = 365;
const MAX_STAFF_ROSTER_ITEMS = 6;
const MAX_ASSISTANT_PROMPT_CHARS = 1200;
const MAX_PROVIDER_MESSAGE_CHARS = 800;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const HTTP_UNPROCESSABLE = 422;
const SCHEMA_ERROR_MESSAGE = "AI draft did not match required schema.";
const PARSE_ERROR_MESSAGE = "AI draft response was not valid JSON.";
const PARSE_ERROR_HINT =
  "Refine prompt or retry; provider returned non-JSON content.";
const SCHEMA_ERROR_HINT =
  "Refine prompt or retry; required fields are missing/invalid.";
const SCHEMA_CLASSIFICATION = "PROVIDER_REJECTED_FORMAT";
const SCHEMA_ERROR_CODE = "PRODUCTION_AI_SCHEMA_INVALID";
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

// WHY: Key constants avoid inline magic strings in mapping logic.
const KEY_PLAN_TITLE = "planTitle";
const KEY_NOTES = "notes";
const KEY_START_DATE = "startDate";
const KEY_END_DATE = "endDate";
const KEY_ESTATE_ASSET_ID = "estateAssetId";
const KEY_PRODUCT_ID = "productId";
const KEY_PHASES = "phases";
const KEY_PHASE_NAME = "name";
const KEY_PHASE_ORDER = "order";
const KEY_PHASE_ESTIMATED_DAYS = "estimatedDays";
const KEY_TASKS = "tasks";
const KEY_TASK_TITLE = "title";
const KEY_TASK_ROLE = "roleRequired";
const KEY_TASK_ASSIGNED_STAFF = "assignedStaffId";
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
  const raw = (value || "").toString().trim();
  if (!raw) return "";
  const compact = raw.replace(/\s+/g, " ");
  if (compact.length <= MAX_ASSISTANT_PROMPT_CHARS) {
    return compact;
  }
  return compact.slice(0, MAX_ASSISTANT_PROMPT_CHARS);
}

// WHY: Ensure prompts include structured context for reliable strict JSON output.
function buildUserPrompt({
  productName,
  estateName,
  startDate,
  endDate,
  staffRoster,
  assistantPrompt,
}) {
  const sections = [
    `Product: ${productName || DEFAULT_TITLE_FALLBACK}`,
    `Estate: ${estateName || "Unknown estate"}`,
    `Start: ${startDate || "Not provided (AI should propose proposedStartDate)"}`,
    `End: ${endDate || "Not provided (AI should propose proposedEndDate)"}`,
    `Phases: ${DEFAULT_PRODUCTION_PHASES.map((p) => p.name).join(", ")}`,
    summarizeStaffRoster(staffRoster),
  ];

  if (!productName || productName === DEFAULT_TITLE_FALLBACK) {
    sections.push(
      "Product selection missing: include a valid proposedProduct object in JSON.",
    );
  }

  if (assistantPrompt) {
    sections.push(`User assistant context: ${assistantPrompt}`);
  }

  sections.push(DRAFT_SCHEMA_HINT);
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
    const maybeDraft = parsed?.draft;
    if (maybeDraft && typeof maybeDraft === "object" && !Array.isArray(maybeDraft)) {
      return maybeDraft;
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

// WHY: Keep role matching strict but tolerant to predictable label formatting
// differences (e.g. "Farm Manager" -> "farm_manager").
function buildRoleAliasMap(availableRoles) {
  const aliases = new Map();
  for (const role of availableRoles) {
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

function buildWarning({ code, path, value, message }) {
  return {
    [KEY_WARNING_CODE]: code,
    [KEY_WARNING_PATH]: path,
    [KEY_WARNING_VALUE]: sanitizeProviderMessage(value),
    [KEY_WARNING_MESSAGE]: message,
  };
}

function normalizeDraftRole(roleValue, roleAliases) {
  const canonical = resolveCanonicalRole(roleValue, roleAliases);
  if (canonical != null) {
    return canonical;
  }
  return roleValue.toString().trim();
}

function validateDraftSchema({ draft, staffById, roleAliases }) {
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
  if (!hasValidProductId) {
    if (proposedProduct == null) {
      missing.push(KEY_PRODUCT_ID);
      missing.push(KEY_PROPOSED_PRODUCT);
    } else if (
      typeof proposedProduct !== "object" ||
      Array.isArray(proposedProduct)
    ) {
      invalid.push(KEY_PROPOSED_PRODUCT);
    } else {
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
          } else if (
            resolveCanonicalRole(task[KEY_TASK_ROLE], roleAliases) == null
          ) {
            // WHY: Draft mode allows AI-proposed roles; final save remains strict.
            warnings.push(
              buildWarning({
                code: WARNING_ROLE_NOT_IN_DIRECTORY,
                path: `${taskPath}.${KEY_TASK_ROLE}`,
                value: task[KEY_TASK_ROLE],
                message:
                  "Role is not currently in your staff directory; confirm or edit before final save.",
              }),
            );
          }

          if (task[KEY_TASK_WEIGHT] == null) {
            missing.push(`${taskPath}.${KEY_TASK_WEIGHT}`);
          } else {
            const weight = parseInteger(task[KEY_TASK_WEIGHT]);
            if (weight == null || weight < MIN_WEIGHT || weight > MAX_WEIGHT) {
              invalid.push(`${taskPath}.${KEY_TASK_WEIGHT}`);
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

function normalizeDraft({ draft, roleAliases }) {
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
          [KEY_PROPOSED_PRODUCT_NAME]: proposedProductRaw[
            KEY_PROPOSED_PRODUCT_NAME
          ]
            .toString()
            .trim(),
          [KEY_PROPOSED_PRODUCT_DESCRIPTION]: proposedProductRaw[
            KEY_PROPOSED_PRODUCT_DESCRIPTION
          ]
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
        [KEY_TASK_ROLE]: normalizeDraftRole(task[KEY_TASK_ROLE], roleAliases),
        [KEY_TASK_ASSIGNED_STAFF]:
          task[KEY_TASK_ASSIGNED_STAFF] == null
            ? null
            : task[KEY_TASK_ASSIGNED_STAFF].toString().trim(),
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

function buildServiceContext({ context, useReasoning, hasPrompt }) {
  return {
    country: context?.country || "unknown",
    source: context?.source || AI_SOURCE,
    hasAssistantPrompt: Boolean(hasPrompt),
    hasUseReasoning: Boolean(useReasoning),
  };
}

async function generateProductionPlanDraft({
  productName,
  estateName,
  startDate,
  endDate,
  estateAssetId,
  productId,
  staffProfiles,
  assistantPrompt,
  useReasoning = false,
  context = {},
}) {
  const provider = resolveProviderName();
  const requestId = context?.requestId || "unknown";
  const requestContext = buildServiceContext({
    context,
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
      staffRoster,
      assistantPrompt: sanitizedPrompt,
    });

    const response = await createAiChatCompletion({
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userPrompt }],
      useReasoning,
      context: {
        ...context,
        operation: AI_OPERATION,
        intent: AI_INTENT,
        source: AI_SOURCE,
      },
    });

    const parsed = parseAiDraft(response.content);
    const availableRoles = Array.from(
      new Set(
        staffProfiles
          .map((profile) =>
            profile?.staffRole?.toString().trim() || "",
          )
          .filter((role) => role.length > 0),
      ),
    );
    const roleAliases = buildRoleAliasMap(availableRoles);
    const staffById = new Map(
      staffRoster
        .filter((entry) => entry.id)
        .map((entry) => [entry.id.toString(), entry]),
    );
    const diagnostics = validateDraftSchema({
      draft: parsed,
      staffById,
      roleAliases,
    });
    if (
      diagnostics.missing.length > 0 ||
      diagnostics.invalid.length > 0
    ) {
      throw buildDraftError({
        message: SCHEMA_ERROR_MESSAGE,
        classification: SCHEMA_CLASSIFICATION,
        errorCode: SCHEMA_ERROR_CODE,
        resolutionHint: SCHEMA_ERROR_HINT,
        details: {
          missing: diagnostics.missing,
          invalid: diagnostics.invalid,
          warnings: diagnostics.warnings,
          providerMessage: sanitizeProviderMessage(response.content),
        },
        providerMessage: response.content,
        retryReason: RETRY_REASON_SCHEMA,
      });
    }

    const normalized = normalizeDraft({
      draft: parsed,
      roleAliases,
    });

    debug(LOG_TAG, LOG_SUCCESS, {
      phaseCount: normalized[KEY_PHASES].length,
      totalTasks: normalized[KEY_SUMMARY][KEY_SUMMARY_TOTAL_TASKS],
      totalEstimatedDays: normalized[KEY_SUMMARY][KEY_SUMMARY_TOTAL_DAYS],
    });

    return {
      draft: normalized,
      warnings: diagnostics.warnings,
      diagnostics: {
        provider,
        model: response?.model || null,
        requestId,
      },
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
