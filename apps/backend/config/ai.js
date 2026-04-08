/**
 * apps/backend/config/ai.js
 * -------------------------
 * WHAT:
 * - Central AI configuration for xAI (Grok) usage.
 *
 * WHY:
 * - Keeps model names, base URL, and API key handling in one place.
 * - Prevents scattered magic strings and makes provider swaps safe.
 *
 * HOW:
 * - Reads values from environment variables with safe defaults.
 * - Exposes a single config object for services/controllers to import.
 * - Logs safe, non-secret diagnostics to confirm config presence.
 */

const debug = require('../utils/debug');

// WHY: Keep provider base URL centralized and overrideable via env.
const DEFAULT_AI_BASE_URL = 'https://api.groq.com/openai/v1';

// WHY: Default model should match the low-cost general model.
const DEFAULT_AI_MODEL = 'llama-3.1-8b-instant';

// WHY: Reasoning model is a separate fallback for heavier tasks.
const DEFAULT_AI_REASONING_MODEL = 'llama-3.1-70b-versatile';

// WHY: Trim env values to avoid hidden whitespace bugs.
const XAI_API_KEY = (process.env.XAI_API_KEY || '').trim();
const AI_BASE_URL =
  (process.env.AI_BASE_URL || '').trim() ||
  DEFAULT_AI_BASE_URL;
const AI_MODEL_DEFAULT =
  (process.env.AI_MODEL_DEFAULT || '').trim() ||
  DEFAULT_AI_MODEL;
const AI_MODEL_REASONING =
  (process.env.AI_MODEL_REASONING || '').trim() ||
  DEFAULT_AI_REASONING_MODEL;

// WHY: Confirm configuration without leaking secrets.
const maskedApiKey = XAI_API_KEY
  ? `${XAI_API_KEY.substring(0, 4)}...${XAI_API_KEY.substring(
      XAI_API_KEY.length - 4,
    )}`
  : null;
debug('AI CONFIG: loaded', {
  hasApiKey: Boolean(XAI_API_KEY),
  xaiApiKeyPreview: maskedApiKey,
  baseUrl: AI_BASE_URL,
  modelDefault: AI_MODEL_DEFAULT,
  modelReasoning: AI_MODEL_REASONING,
});

module.exports = {
  XAI_API_KEY,
  AI_BASE_URL,
  AI_MODEL_DEFAULT,
  AI_MODEL_REASONING,
};
