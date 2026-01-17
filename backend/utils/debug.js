/**
 * utils/debug.js
 * ---------------
 * WHAT:
 * - Central debug logger with safe redaction.
 *
 * WHY:
 * - Keeps debug output consistent across controllers/services.
 * - Protects secrets while preserving high-detail production diagnostics.
 *
 * HOW:
 * - Accepts a message + optional extra data.
 * - Redacts sensitive keys/values (passwords, tokens, auth headers).
 * - Logs in all environments unless explicitly disabled.
 */

// WHY: Keys with these words are almost always secrets and must be masked.
const SENSITIVE_KEYS = [
  'password',
  'token',
  'authorization',
  'cookie',
  'set-cookie',
  'secret',
  'jwt',
];

// WHY: Message-based masking should be strict to avoid hiding useful context.
const SENSITIVE_MESSAGE_KEYWORDS = [
  'password',
  'token',
  'authorization',
  'cookie',
  'set-cookie',
  'secret',
];

// WHY: Avoid logging huge payloads or infinite objects.
const MAX_DEPTH = 4;

// WHY: Allow production logging but keep an explicit kill-switch.
const DEBUG_DISABLED = process.env.DEBUG_LOGS_DISABLED === 'true';

// WHY: Tiny helper so keyword checks remain readable and consistent.
function containsSensitiveKeyword(text, keywords) {
  const value = String(text || '').toLowerCase();
  return keywords.some((keyword) => value.includes(keyword));
}

// WHY: JWTs are the most common sensitive string we might accidentally log.
function looksLikeJwt(value) {
  if (typeof value !== 'string') return false;
  const parts = value.split('.');
  if (parts.length !== 3) return false;
  return parts.every((part) => /^[A-Za-z0-9_-]+$/.test(part));
}

// WHY: Masking keeps logs useful without exposing secrets.
function maskValue(value) {
  if (value == null) return '[REDACTED]';
  if (typeof value === 'string') {
    return `[REDACTED:${value.length}]`;
  }
  return '[REDACTED]';
}

// WHY: Convert Error objects into plain safe structures.
function normalizeError(error) {
  return {
    name: error.name,
    message: error.message,
    stack: error.stack,
  };
}

// WHY: Sanitize any value before it hits the console.
function sanitizeValue(value, contextLabel, depth) {
  if (value == null) return value;

  // WHY: Strings can leak JWTs or auth headers.
  if (typeof value === 'string') {
    if (looksLikeJwt(value)) return maskValue(value);
    if (value.toLowerCase().startsWith('bearer ')) return maskValue(value);
    if (containsSensitiveKeyword(contextLabel, SENSITIVE_MESSAGE_KEYWORDS)) {
      return maskValue(value);
    }
    return value;
  }

  // WHY: Preserve booleans/numbers as-is for clean diagnostics.
  if (typeof value !== 'object') return value;

  // WHY: Avoid deep or circular data structures.
  if (depth >= MAX_DEPTH) return '[TRUNCATED]';

  // WHY: Error objects need a safe shape.
  if (value instanceof Error) {
    return sanitizeValue(normalizeError(value), contextLabel, depth + 1);
  }

  // WHY: Clone objects/arrays to avoid mutating caller data.
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeValue(item, contextLabel, depth + 1));
  }

  const sanitized = {};
  for (const key of Object.keys(value)) {
    const nextLabel = `${contextLabel}.${key}`;
    if (containsSensitiveKeyword(key, SENSITIVE_KEYS)) {
      sanitized[key] = maskValue(value[key]);
      continue;
    }
    sanitized[key] = sanitizeValue(value[key], nextLabel, depth + 1);
  }
  return sanitized;
}

// WHY: Keep logger signature flexible without breaking existing calls.
module.exports = function debug(message, ...extras) {
  if (DEBUG_DISABLED) return;

  const timestamp = new Date().toISOString();
  const safeMessage = String(message);
  const safeExtras = extras.map((extra) =>
    sanitizeValue(extra, safeMessage, 0),
  );

  if (safeExtras.length === 0) {
    console.log(`[${timestamp}] DEBUG: ${safeMessage}`);
    return;
  }

  if (safeExtras.length === 1) {
    console.log(`[${timestamp}] DEBUG: ${safeMessage}`, safeExtras[0]);
    return;
  }

  console.log(`[${timestamp}] DEBUG: ${safeMessage}`, safeExtras);
};
