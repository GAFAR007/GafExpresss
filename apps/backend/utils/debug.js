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

// WHY: Success-path logs should stay on one line, but failures need detail.
const EXPANDED_MESSAGE_KEYWORDS = [
  'error',
  'failed',
  'failure',
  'exception',
  'crash',
];

// WHY: Avoid logging huge payloads or infinite objects.
const MAX_DEPTH = 4;
const MAX_INLINE_ENTRIES = 12;
const MAX_INLINE_VALUE_LENGTH = 96;

// WHY: Allow production logging but keep an explicit kill-switch.
const DEBUG_DISABLED = process.env.DEBUG_LOGS_DISABLED === 'true';

const FEATURE_FLAG_ALIASES = {
  enableAiPlannerV2: 'aiV2',
  enablePlanUnits: 'planUnits',
  enableUnitAssignments: 'unitAssign',
  enablePhaseUnitCompletion: 'phaseDone',
  enablePhaseGate: 'phaseGate',
  enableDeviationGovernance: 'devGov',
  enableConfidenceScore: 'confidence',
};

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

function formatTimestamp(date) {
  if (
    process.env.DEBUG_LOGS_FULL_TIMESTAMP === 'true' ||
    process.env.NODE_ENV === 'production'
  ) {
    return date.toISOString();
  }

  const pad = (value, length = 2) =>
    String(value).padStart(length, '0');
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.${pad(date.getMilliseconds(), 3)}`;
}

function shortenValue(value) {
  const normalized = String(value).replace(/\s+/g, ' ').trim();
  if (normalized.length <= MAX_INLINE_VALUE_LENGTH) {
    return normalized;
  }
  return `${normalized.slice(0, MAX_INLINE_VALUE_LENGTH - 3)}...`;
}

function summarizeUrl(value) {
  if (typeof value !== 'string') {
    return shortenValue(value);
  }

  try {
    const parsed = new URL(value);
    return shortenValue(`${parsed.host}${parsed.pathname}`);
  } catch (error) {
    return shortenValue(value);
  }
}

function summarizeArray(values) {
  return `[${values.map((value) => shortenValue(value)).join(',')}]`;
}

function normalizeInlineKey(key) {
  const aliases = {
    databaseStatus: 'db',
    readyState: 'ready',
    database: 'db',
    xaiApiKeyPreview: 'keyPreview',
    modelDefault: 'model',
    modelReasoning: 'reasoning',
    scannedCount: 'scanned',
    expiredCount: 'expired',
    skippedCount: 'skipped',
    errorCount: 'errors',
  };
  return aliases[key] || key;
}

function flattenInlineEntries(value, prefix = '', entries = []) {
  if (entries.length >= MAX_INLINE_ENTRIES) {
    return entries;
  }

  if (value == null) {
    if (prefix) {
      entries.push(`${prefix}=null`);
    }
    return entries;
  }

  if (
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  ) {
    if (prefix) {
      entries.push(`${prefix}=${shortenValue(value)}`);
    }
    return entries;
  }

  if (Array.isArray(value)) {
    if (prefix) {
      entries.push(`${prefix}=${summarizeArray(value)}`);
    }
    return entries;
  }

  if (typeof value !== 'object') {
    if (prefix) {
      entries.push(`${prefix}=${shortenValue(value)}`);
    }
    return entries;
  }

  for (const [key, nestedValue] of Object.entries(value)) {
    if (entries.length >= MAX_INLINE_ENTRIES) {
      break;
    }
    const nextKey = prefix
      ? `${prefix}.${normalizeInlineKey(key)}`
      : normalizeInlineKey(key);
    flattenInlineEntries(nestedValue, nextKey, entries);
  }

  return entries;
}

function normalizeWorkerLabel(rawLabel) {
  return rawLabel
    .replace(/\s+/g, ' ')
    .replace(/[()]/g, '')
    .trim();
}

function classifyMessage(message) {
  const trimmed = String(message || '').trim();

  const modelMatch = trimmed.match(/^Loading (.+) model\.\.\.$/i);
  if (modelMatch) {
    return {
      category: 'MODEL',
      label: `Loading ${modelMatch[1]} model`,
    };
  }

  const routeMatch = trimmed.match(/^(.+?) routes initialized$/i);
  if (routeMatch) {
    return {
      category: 'ROUTE',
      label: `${routeMatch[1]} routes initialized`,
    };
  }

  const workerMatch = trimmed.match(/^PREORDER RECONCILE WORKER: (.+)$/);
  if (workerMatch) {
    return {
      category: 'WORKER',
      label: `Preorder reconcile worker ${normalizeWorkerLabel(workerMatch[1])}`,
    };
  }

  const mongoDriverEventMatch = trimmed.match(/^MongoDB driver event: (.+)$/);
  if (mongoDriverEventMatch) {
    return {
      category: 'DB',
      label: `MongoDB driver ${mongoDriverEventMatch[1]}`,
    };
  }

  if (trimmed === 'Creating Express app instance') {
    return { category: 'BOOT', label: 'Creating Express app instance' };
  }
  if (trimmed === 'Registering global middleware') {
    return { category: 'BOOT', label: 'Registering global middleware' };
  }
  if (trimmed === 'Setting up Swagger docs at /docs') {
    return { category: 'BOOT', label: 'Setting up Swagger docs at /docs' };
  }
  if (trimmed === 'Registering routes') {
    return { category: 'BOOT', label: 'Registering routes' };
  }
  if (trimmed === 'Routes module loaded') {
    return { category: 'ROUTE', label: 'Route groups loaded' };
  }
  if (trimmed === 'Server successfully listening') {
    return { category: 'SERVER', label: 'Server successfully listening' };
  }
  if (trimmed === 'Initializing database connection') {
    return { category: 'DB', label: 'Initializing MongoDB connection' };
  }
  if (trimmed === 'Attempting MongoDB connection') {
    return { category: 'DB', label: 'Attempting MongoDB connection' };
  }
  if (trimmed === 'MongoDB connection established') {
    return { category: 'DB', label: 'MongoDB connection established' };
  }
  if (trimmed === 'MongoDB is ready for application traffic') {
    return { category: 'DB', label: 'MongoDB ready for application traffic' };
  }
  if (trimmed === 'Rejecting request because MongoDB is unavailable') {
    return { category: 'HTTP', label: 'Rejecting request because MongoDB is unavailable' };
  }
  if (trimmed === 'AI CONFIG: loaded') {
    return { category: 'AI', label: 'AI config loaded' };
  }
  if (trimmed === 'PRODUCTION_FEATURE_FLAGS: loaded') {
    return { category: 'FLAGS', label: 'Production feature flags loaded' };
  }
  if (trimmed === 'Scheduling MongoDB reconnect attempt') {
    return { category: 'DB', label: 'Scheduling MongoDB reconnect attempt' };
  }
  if (trimmed === 'MongoDB connection attempt failed') {
    return { category: 'DB', label: 'MongoDB connection attempt failed' };
  }
  if (trimmed === 'Backend startup failed before listen') {
    return { category: 'SERVER', label: 'Backend startup failed before listen' };
  }

  return {
    category: 'DEBUG',
    label: trimmed,
  };
}

function buildPrefix(timestamp, category) {
  return `[${timestamp}] ${category.padEnd(7)}`;
}

function addInlinePart(parts, label, value) {
  if (value == null || value === '') {
    return;
  }

  parts.push(`${label}=${value}`);
}

function appendDatabaseParts(parts, value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return;
  }

  addInlinePart(
    parts,
    'live',
    Object.prototype.hasOwnProperty.call(value, 'isReady')
      ? value.isReady
        ? 'yes'
        : 'no'
      : null,
  );
  addInlinePart(parts, 'ready', value.readyState);
  addInlinePart(parts, 'state', value.state && shortenValue(value.state));
  addInlinePart(parts, 'db', value.database && shortenValue(value.database));
  addInlinePart(parts, 'host', value.host && shortenValue(value.host));
}

function formatAiInlineExtra(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  const parts = [];
  addInlinePart(
    parts,
    'key',
    Object.prototype.hasOwnProperty.call(value, 'hasApiKey')
      ? value.hasApiKey
        ? 'yes'
        : 'no'
      : null,
  );
  addInlinePart(
    parts,
    'preview',
    value.xaiApiKeyPreview && shortenValue(value.xaiApiKeyPreview),
  );
  addInlinePart(parts, 'base', value.baseUrl && summarizeUrl(value.baseUrl));
  addInlinePart(
    parts,
    'model',
    value.modelDefault && shortenValue(value.modelDefault),
  );
  addInlinePart(
    parts,
    'reason',
    value.modelReasoning && shortenValue(value.modelReasoning),
  );

  return parts.length > 0 ? parts.join(' · ') : null;
}

function formatFeatureFlagsInlineExtra(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  const parts = Object.entries(value).map(([key, flagValue]) => {
    const alias = FEATURE_FLAG_ALIASES[key] || key;
    return `${alias}=${flagValue ? 'on' : 'off'}`;
  });

  return parts.length > 0 ? parts.join(' · ') : null;
}

function formatRouteInlineExtra(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  if (!Array.isArray(value.groups)) {
    return null;
  }

  const groups = value.groups.map((group) => shortenValue(group)).join(' ');
  return `count=${value.groups.length} · groups=${groups}`;
}

function formatDatabaseInlineExtra(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }

  const parts = [];
  addInlinePart(parts, 'reason', value.reason && shortenValue(value.reason));
  addInlinePart(
    parts,
    'retry',
    Object.prototype.hasOwnProperty.call(value, 'retryable')
      ? value.retryable
        ? 'yes'
        : 'no'
      : null,
  );
  addInlinePart(
    parts,
    'protocol',
    value.protocol && shortenValue(value.protocol),
  );

  if (value.databaseStatus) {
    appendDatabaseParts(parts, value.databaseStatus);
  } else {
    appendDatabaseParts(parts, value);
  }

  return parts.length > 0 ? parts.join(' · ') : null;
}

function formatSpecialInlineExtra(entry, value) {
  if (entry.category === 'AI') {
    return formatAiInlineExtra(value);
  }

  if (entry.category === 'FLAGS') {
    return formatFeatureFlagsInlineExtra(value);
  }

  if (entry.category === 'ROUTE' && entry.label === 'Route groups loaded') {
    return formatRouteInlineExtra(value);
  }

  if (entry.category === 'DB') {
    return formatDatabaseInlineExtra(value);
  }

  return null;
}

// WHY: Error-like payloads deserve expanded logs with readable stack traces.
function hasExpandedPayload(value, depth = 0) {
  if (value == null || depth >= MAX_DEPTH) {
    return false;
  }

  if (typeof value === 'string') {
    return value.includes('\n');
  }

  if (typeof value !== 'object') {
    return false;
  }

  if (Array.isArray(value)) {
    return value.some((item) => hasExpandedPayload(item, depth + 1));
  }

  return Object.entries(value).some(([key, nestedValue]) => {
    if (key === 'error' || key === 'stack') {
      return true;
    }
    return hasExpandedPayload(nestedValue, depth + 1);
  });
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

// WHY: Inline payloads should stay easy to scan during normal startup and requests.
function formatInlineExtra(entry, value) {
  if (value == null) {
    return String(value);
  }

  if (typeof value === 'string') {
    return value.replace(/\s+/g, ' ').trim();
  }

  const specialFormat = formatSpecialInlineExtra(entry, value);
  if (specialFormat) {
    return specialFormat;
  }

  const entries = flattenInlineEntries(value);
  if (entries.length > 0) {
    return entries.join(' · ');
  }

  try {
    return shortenValue(JSON.stringify(value));
  } catch (error) {
    return '[UNSERIALIZABLE]';
  }
}

// WHY: Keep logger signature flexible without breaking existing calls.
module.exports = function debug(message, ...extras) {
  if (DEBUG_DISABLED) return;

  const timestamp = formatTimestamp(new Date());
  const safeMessage = String(message);
  const entry = classifyMessage(safeMessage);
  const safeExtras = extras.map((extra) =>
    sanitizeValue(extra, safeMessage, 0),
  );

  if (safeExtras.length === 0) {
    console.log(`${buildPrefix(timestamp, entry.category)} ${entry.label}`);
    return;
  }

  const shouldExpand =
    containsSensitiveKeyword(safeMessage, EXPANDED_MESSAGE_KEYWORDS) ||
    safeExtras.some((extra) => hasExpandedPayload(extra));

  if (!shouldExpand) {
    const inlineExtras = safeExtras
      .map((extra) => formatInlineExtra(entry, extra))
      .filter(Boolean)
      .join(' | ');
    console.log(
      `${buildPrefix(timestamp, entry.category)} ${entry.label}${inlineExtras ? ` | ${inlineExtras}` : ''}`,
    );
    return;
  }

  if (safeExtras.length === 1) {
    console.log(
      `${buildPrefix(timestamp, entry.category)} ${entry.label}`,
      safeExtras[0],
    );
    return;
  }

  console.log(
    `${buildPrefix(timestamp, entry.category)} ${entry.label}`,
    safeExtras,
  );
};
