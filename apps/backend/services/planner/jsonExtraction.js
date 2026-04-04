/**
 * apps/backend/services/planner/jsonExtraction.js
 * -----------------------------------------------
 * WHAT:
 * - Extracts the first valid JSON object from AI responses used by planner V2.
 *
 * WHY:
 * - Providers sometimes wrap JSON in prose or code fences even when instructed not to.
 * - Planner V2 retries should focus on real schema issues, not brittle parsing failures.
 *
 * HOW:
 * - Tries direct JSON parsing first.
 * - Then tries fenced code blocks.
 * - Finally scans for balanced JSON object substrings and parses the first valid one.
 */

function tryParseJsonObject(rawValue) {
  const trimmed = (rawValue || "").toString().trim();
  if (!trimmed) {
    return null;
  }
  try {
    const parsed = JSON.parse(trimmed);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ?
      parsed
    : null;
  } catch (_) {
    return null;
  }
}

function extractJsonObject(rawContent) {
  const content = (rawContent || "").toString().trim();
  if (!content) {
    return null;
  }

  const direct = tryParseJsonObject(content);
  if (direct) {
    return direct;
  }

  const fencedMatch = content.match(
    /```(?:json)?\s*([\s\S]*?)```/i,
  );
  if (fencedMatch?.[1]) {
    const fencedParsed = tryParseJsonObject(
      fencedMatch[1],
    );
    if (fencedParsed) {
      return fencedParsed;
    }
  }

  let depth = 0;
  let startIndex = -1;
  for (let index = 0; index < content.length; index += 1) {
    const char = content[index];
    if (char === "{") {
      if (depth === 0) {
        startIndex = index;
      }
      depth += 1;
      continue;
    }
    if (char !== "}") {
      continue;
    }
    if (depth === 0) {
      continue;
    }
    depth -= 1;
    if (depth !== 0 || startIndex < 0) {
      continue;
    }
    const candidate = content.slice(
      startIndex,
      index + 1,
    );
    const parsedCandidate =
      tryParseJsonObject(candidate);
    if (parsedCandidate) {
      return parsedCandidate;
    }
  }

  return null;
}

module.exports = {
  extractJsonObject,
};
