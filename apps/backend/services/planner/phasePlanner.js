/**
 * apps/backend/services/planner/phasePlanner.js
 * ---------------------------------------------
 * WHAT:
 * - Generates lifecycle phase subsets for planner V2.
 *
 * WHY:
 * - AI should choose relevant production phases, but never dates or schedule rows.
 * - Structured retries keep failures explicit instead of silently falling back.
 *
 * HOW:
 * - Calls the shared AI client with a strict JSON-only prompt.
 * - Retries with correction feedback on schema or lifecycle validation errors.
 * - Returns normalized lifecycle-ordered phases only.
 */

const debug = require("../../utils/debug");
const {
  createAiChatCompletion,
} = require("../ai.service");
const {
  validatePhasePlan,
} = require("./validationEngine");
const {
  extractJsonObject,
} = require("./jsonExtraction");

const MAX_PHASE_PLANNER_ATTEMPTS = 3;

function isPhasePlannerRateLimitError(error) {
  const classification = (error?.classification || "")
    .toString()
    .trim()
    .toUpperCase();
  const retryReason = (error?.retry_reason || "")
    .toString()
    .trim()
    .toLowerCase();
  const httpStatus =
    Number(error?.httpStatus || 0) || 0;

  if (
    classification === "RATE_LIMITED" ||
    retryReason === "provider_throttle_or_outage" ||
    httpStatus === 429
  ) {
    return true;
  }

  return false;
}

function shouldRetryPhasePlannerError(error) {
  return !isPhasePlannerRateLimitError(error);
}

function buildFallbackPhasePlan(lifecycle) {
  return (Array.isArray(lifecycle?.phases) ? lifecycle.phases : [])
    .map((phaseName, index) => ({
      phaseName: (phaseName || "").toString().trim(),
      lifecycleIndex: index,
    }))
    .filter((phase) => phase.phaseName);
}

function buildPhasePlannerPrompt({
  lifecycle,
  planningContext,
  previousError = null,
  simplified = false,
}) {
  return [
    "Plan production phases for this farm lifecycle.",
    "Return JSON only with: {\"phases\":[{\"phaseName\":\"string\"}]}.",
    "Never include dates, staff, schedules, warnings, or extra keys.",
    simplified ?
      "Keep the phase list minimal but valid."
    : "Return the lifecycle phases needed for a realistic production plan.",
    `Lifecycle minDays: ${lifecycle.minDays}`,
    `Lifecycle maxDays: ${lifecycle.maxDays}`,
    `Lifecycle phases: ${lifecycle.phases.join(", ")}`,
    `Planning context: ${JSON.stringify(planningContext)}`,
    previousError ?
      `Previous validation error: ${previousError}`
    : "",
  ]
    .filter(Boolean)
    .join("\n");
}

async function generatePhasePlan({
  lifecycle,
  planningContext,
  useReasoning = false,
  context = {},
}) {
  let lastError = null;
  let attemptsMade = 0;

  for (
    let attempt = 1;
    attempt <= MAX_PHASE_PLANNER_ATTEMPTS;
    attempt += 1
  ) {
    attemptsMade = attempt;
    try {
      const response = await createAiChatCompletion({
        systemPrompt: [
          "You are a professional production planning assistant.",
          "Your job is to design production phases and tasks.",
          "Never generate calendar dates.",
          "Never assign specific workers.",
          "Never create daily schedules.",
          "Output must be valid JSON.",
        ].join(" "),
        messages: [
          {
            role: "user",
            content: buildPhasePlannerPrompt({
              lifecycle,
              planningContext,
              previousError:
                lastError?.message || null,
              simplified: attempt === 3,
            }),
          },
        ],
        useReasoning,
        context: {
          ...context,
          operation: "PlannerV2PhasePlanner",
          intent:
            "generate lifecycle-safe production phases",
          source: "planner_v2_phase_planner",
        },
      });

      const parsed = extractJsonObject(response?.content);
      if (!parsed) {
        throw new Error(
          "Phase planner did not return valid JSON.",
        );
      }
      const phases = validatePhasePlan({
        lifecycle,
        payload: parsed,
      });
      return {
        phases,
        retryCount: attempt - 1,
      };
    } catch (error) {
      lastError = error;
      debug(
        "PLANNER_V2_PHASE: retry",
        {
          intent:
            "phase planner validation failed and will retry",
          attempt,
          error: error?.message || "unknown",
          errorCode:
            error?.errorCode || null,
        },
      );
      if (!shouldRetryPhasePlannerError(error)) {
        break;
      }
    }
  }

  const fallbackPhases =
    buildFallbackPhasePlan(lifecycle);
  debug(
    "PLANNER_V2_PHASE: fallback",
    {
      intent:
        "phase planner exhausted retries and will use the resolved lifecycle as fallback",
      fallbackPhaseCount:
        fallbackPhases.length,
      reason:
        lastError?.errorCode ||
        lastError?.message ||
        "unknown",
    },
  );
  return {
    phases: fallbackPhases,
    retryCount:
      Math.max(0, attemptsMade - 1),
    fallbackUsed: true,
    fallbackReason:
      lastError?.errorCode ||
      lastError?.message ||
      "unknown",
    fallbackClassification:
      lastError?.classification || null,
    fallbackRetryReason:
      lastError?.retry_reason || null,
  };
}

module.exports = {
  generatePhasePlan,
};
