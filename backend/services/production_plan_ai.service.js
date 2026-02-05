/**
 * apps/backend/services/production_plan_ai.service.js
 * ---------------------------------------------------
 * WHAT:
 * - AI draft generator for production plans (phases + tasks).
 *
 * WHY:
 * - Centralizes prompt building, parsing, and normalization.
 * - Keeps controllers small and prevents duplicated AI logic.
 *
 * HOW:
 * - Builds a structured prompt with staff + plan context.
 * - Calls the shared AI client (xAI / Grok).
 * - Normalizes the response into a safe draft payload.
 */

const debug = require("../utils/debug");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const {
  createAiChatCompletion,
} = require("./ai.service");
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

// WHY: Prevent brittle parsing by standardizing output format instructions.
const SYSTEM_PROMPT =
  "You are a farm production planning assistant. " +
  "Return ONLY valid JSON with no markdown or code fences or extra text.";

// WHY: Keep schema hints short to reduce tokens while staying informative.
const DRAFT_SCHEMA_HINT =
  `Return a single JSON object only. Use double quotes for keys and string values, and include fields: title, notes, phases[]. Each phase needs name & tasks[].`;

// WHY: Default names ensure drafts remain usable even on malformed output.
const DEFAULT_TITLE_FALLBACK = "Production plan draft";
const DEFAULT_TASK_TITLE = "Task";
const DEFAULT_NOTES_FALLBACK = "";
const ROLE_FALLBACK = BusinessStaffProfile.STAFF_ROLES?.[0] || "farmer";
const MIN_WEIGHT = 1;
const MAX_WEIGHT = 5;

// WHY: Keep staff fields tight to avoid leaking PII in prompts.
function buildStaffRoster(staffProfiles) {
  return staffProfiles.map((profile) => ({
    id: profile._id?.toString(),
    role: profile.staffRole,
    name: profile.userId?.name || profile.userId?.email || "Staff",
    estateAssetId: profile.estateAssetId?.toString() || null,
  }));
}

const MAX_STAFF_ROSTER_ITEMS = 6;

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
      ? `…plus ${staffRoster.length - MAX_STAFF_ROSTER_ITEMS} more`
      : "";
  return `Staff roster: ${lines.join(", ")}${note ? ` ${note}` : ""}`;
}

// WHY: Ensure prompts include structured context for reliable JSON output.
function buildUserPrompt({
  productName,
  estateName,
  startDate,
  endDate,
  staffRoster,
}) {
  return [
    `Product: ${productName || DEFAULT_TITLE_FALLBACK}`,
    `Estate: ${estateName || "Unknown estate"}`,
    `Start: ${startDate}`,
    `End: ${endDate}`,
    `Phases: ${DEFAULT_PRODUCTION_PHASES.map((p) => p.name).join(", ")}`,
    summarizeStaffRoster(staffRoster),
    DRAFT_SCHEMA_HINT,
  ].join("\n");
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

// WHY: Normalize weights to an integer range.
function clampWeight(value) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return MIN_WEIGHT;
  return Math.min(Math.max(parsed, MIN_WEIGHT), MAX_WEIGHT);
}

// WHY: Normalize roles to known staff roles for validation.
function normalizeRole(role, availableRoles) {
  const normalized = (role || "").toString().trim();
  if (availableRoles.includes(normalized)) {
    return normalized;
  }
  return ROLE_FALLBACK;
}

// WHY: Ensure task assignments map to a real staff profile.
function resolveAssignment({
  assignedStaffId,
  roleRequired,
  staffById,
  staffByRole,
}) {
  if (assignedStaffId && staffById.has(assignedStaffId)) {
    return assignedStaffId;
  }
  const candidates = staffByRole.get(roleRequired) || [];
  return candidates.length > 0 ? candidates[0].id : null;
}

// WHY: Normalize tasks to safe defaults before returning to UI.
function normalizeTasks(tasks, staffById, staffByRole, availableRoles) {
  const list = Array.isArray(tasks) ? tasks : [];
  return list.map((task) => {
    const roleRequired = normalizeRole(
      task?.roleRequired,
      availableRoles,
    );
    const assignedStaffId = resolveAssignment({
      assignedStaffId: task?.assignedStaffId?.toString(),
      roleRequired,
      staffById,
      staffByRole,
    });

    return {
      title:
        task?.title?.toString().trim() ||
        DEFAULT_TASK_TITLE,
      roleRequired,
      assignedStaffId,
      weight: clampWeight(task?.weight),
      instructions:
        task?.instructions?.toString().trim() ||
        "",
    };
  });
}

// WHY: Align phases with default order to keep scheduling stable.
function normalizePhases(draftPhases, staffById, staffByRole, availableRoles) {
  const input = Array.isArray(draftPhases)
    ? draftPhases
    : [];
  const byName = new Map(
    input.map((phase) => [
      (phase?.name || "").toString().trim().toLowerCase(),
      phase,
    ]),
  );

  return DEFAULT_PRODUCTION_PHASES.map((phase) => {
    const match = byName.get(phase.name.toLowerCase());
    return {
      name: phase.name,
      order: phase.order,
      tasks: normalizeTasks(
        match?.tasks,
        staffById,
        staffByRole,
        availableRoles,
      ),
    };
  });
}

// WHY: Build a normalized draft object that the UI can safely render.
function normalizeDraft({ draft, staffProfiles }) {
  const availableRoles = BusinessStaffProfile.STAFF_ROLES || [];
  const staffById = new Map(
    staffProfiles.map((profile) => [
      profile._id.toString(),
      {
        id: profile._id.toString(),
        role: profile.staffRole,
      },
    ]),
  );
  const staffByRole = new Map();
  staffProfiles.forEach((profile) => {
    const role = profile.staffRole;
    if (!staffByRole.has(role)) {
      staffByRole.set(role, []);
    }
    staffByRole.get(role).push({
      id: profile._id.toString(),
    });
  });

  return {
    title:
      draft?.title?.toString().trim() ||
      DEFAULT_TITLE_FALLBACK,
    notes:
      draft?.notes?.toString().trim() ||
      DEFAULT_NOTES_FALLBACK,
    aiGenerated: true,
    phases: normalizePhases(
      draft?.phases,
      staffById,
      staffByRole,
      availableRoles,
    ),
  };
}

// WHY: Parse AI response into a plain object.
function parseAiDraft(content) {
  const jsonBlock = extractJsonBlock(content || "");
  if (!jsonBlock) {
    throw new Error("AI response did not include JSON.");
  }
  return JSON.parse(jsonBlock);
}

async function generateProductionPlanDraft({
  productName,
  estateName,
  startDate,
  endDate,
  staffProfiles,
  useReasoning = false,
  context = {},
}) {
  try {
    debug(LOG_TAG, LOG_START, {
      staffCount: staffProfiles.length,
      useReasoning,
    });

    const staffRoster = buildStaffRoster(staffProfiles);
    const userPrompt = buildUserPrompt({
      productName,
      estateName,
      startDate,
      endDate,
      staffRoster,
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
    const normalized = normalizeDraft({
      draft: parsed,
      staffProfiles,
    });

    debug(LOG_TAG, LOG_SUCCESS, {
      phaseCount: normalized.phases.length,
    });

    return normalized;
  } catch (err) {
    debug(LOG_TAG, LOG_ERROR, {
      error: err.message,
      resolution_hint:
        "Check AI configuration, inputs, and response format.",
      reason: "ai_draft_generation_failed",
    });
    throw err;
  }
}

module.exports = {
  generateProductionPlanDraft,
};
