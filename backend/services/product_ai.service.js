/**
 * services/product_ai.service.js
 * ------------------------------
 * WHAT:
 * - AI draft generator for product details (name, description, price, stock).
 *
 * WHY:
 * - Keeps AI prompt + parsing logic centralized and testable.
 * - Prevents controllers from handling raw AI responses.
 *
 * HOW:
 * - Builds a strict JSON prompt for the AI provider.
 * - Parses and normalizes the JSON output.
 * - Returns a safe draft payload for UI autofill.
 */

const debug = require('../utils/debug');
const { createAiChatCompletion } = require('./ai.service');

// WHY: Centralize logging labels for AI draft generation.
const LOG_TAG = 'PRODUCT_AI';
const LOG_START = 'product draft start';
const LOG_SUCCESS = 'product draft success';
const LOG_ERROR = 'product draft error';

// WHY: Keep AI intent values consistent in AI logs.
const AI_OPERATION = 'ProductDraft';
const AI_INTENT = 'generate product draft';
const AI_SOURCE = 'backend';

// WHY: Enforce strict JSON output to reduce parsing errors.
const SYSTEM_PROMPT =
  'You are a product drafting assistant. ' +
  'Return ONLY valid JSON with no markdown, no code fences, and no extra text.';

// WHY: Schema hint keeps output predictable and short.
const DRAFT_SCHEMA_HINT =
  'Return a single JSON object with keys: name, description, priceNgn, stock, imageUrl.';

// WHY: Defaults ensure drafts remain usable when AI output is incomplete.
const DEFAULT_NAME = 'New product';
const DEFAULT_DESCRIPTION = '';
const DEFAULT_PRICE_NGN = 0;
const DEFAULT_STOCK = 0;

function buildUserPrompt({ prompt }) {
  // WHY: Keep the prompt short to stay under token limits.
  return [
    `User request: ${prompt}`,
    DRAFT_SCHEMA_HINT,
  ].join('\n');
}

function extractJsonBlock(text) {
  // WHY: Capture the first JSON object even if extra text slips in.
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end < 0 || end <= start) {
    return null;
  }
  return text.slice(start, end + 1);
}

function parseNumber(value, fallback) {
  const parsed = Number(value);
  if (Number.isNaN(parsed)) return fallback;
  return parsed;
}

function normalizeDraft(raw) {
  // WHY: Normalize fields to safe types for UI autofill.
  const priceNgn = Math.max(
    0,
    Math.round(parseNumber(raw?.priceNgn, DEFAULT_PRICE_NGN))
  );
  const stock = Math.max(
    0,
    Math.round(parseNumber(raw?.stock, DEFAULT_STOCK))
  );

  return {
    name: raw?.name?.toString().trim() || DEFAULT_NAME,
    description:
      raw?.description?.toString().trim() || DEFAULT_DESCRIPTION,
    priceNgn,
    stock,
    imageUrl: raw?.imageUrl?.toString().trim() || '',
  };
}

function parseAiDraft(content) {
  const jsonBlock = extractJsonBlock(content || '');
  if (!jsonBlock) {
    throw new Error('AI response missing JSON payload');
  }

  let parsed = null;
  try {
    parsed = JSON.parse(jsonBlock);
  } catch (error) {
    throw new Error('AI response JSON parse failed');
  }

  return normalizeDraft(parsed);
}

async function generateProductDraft({
  prompt,
  useReasoning,
  context,
}) {
  debug(LOG_TAG, [LOG_START, { hasPrompt: Boolean(prompt) }]);

  try {
    const aiResponse = await createAiChatCompletion({
      messages: [
        { role: 'user', content: buildUserPrompt({ prompt }) },
      ],
      systemPrompt: SYSTEM_PROMPT,
      useReasoning,
      context: {
        ...context,
        operation: AI_OPERATION,
        intent: AI_INTENT,
        source: AI_SOURCE,
      },
    });

    const draft = parseAiDraft(aiResponse.content);

    debug(LOG_TAG, [LOG_SUCCESS, { hasDraft: Boolean(draft?.name) }]);
    return draft;
  } catch (error) {
    debug(LOG_TAG, [
      LOG_ERROR,
      {
        error: error?.message || 'unknown error',
        resolution_hint:
          'Check prompt clarity and AI configuration before retrying.',
        reason: 'product_draft_failed',
      },
    ]);
    throw error;
  }
}

module.exports = {
  generateProductDraft,
};
