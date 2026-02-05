/**
 * apps/backend/services/ai.service.js
 * ----------------------------------
 * WHAT:
 * - Minimal AI client wrapper for xAI (Grok) chat completions.
 *
 * WHY:
 * - Centralizes AI provider calls and model selection.
 * - Ensures consistent logging + error classification across AI usage.
 *
 * HOW:
 * - Reads provider config from config/ai.js.
 * - Sends OpenAI-compatible chat requests to the configured base URL.
 * - Returns a normalized response payload for controllers/services.
 */

const https = require('https');
const { URL } = require('url');
const debug = require('../utils/debug');
const {
  XAI_API_KEY,
  AI_BASE_URL,
  AI_MODEL_DEFAULT,
  AI_MODEL_REASONING,
} = require('../config/ai');

// WHY: Keep provider names and operations centralized for logging.
const PROVIDERS = {
  GROQ: 'groq',
  XAI: 'xai',
  UNKNOWN: 'unknown',
};
const OPERATION_CHAT = 'AIChatCompletion';

// WHY: Standardize steps to match backend logging requirements.
const LOG_STEPS = {
  SERVICE_START: 'SERVICE_START',
  PROVIDER_CALL_START: 'PROVIDER_CALL_START',
  PROVIDER_CALL_OK: 'PROVIDER_CALL_OK',
  PROVIDER_CALL_FAIL: 'PROVIDER_CALL_FAIL',
  SERVICE_OK: 'SERVICE_OK',
  SERVICE_FAIL: 'SERVICE_FAIL',
};

// WHY: Use constants to avoid inline magic values.
const AI_CHAT_PATH = '/chat/completions';
const DEFAULT_TIMEOUT_MS = 15000;
const HTTPS_PORT = 443;
const UNKNOWN_VALUE = 'unknown';
const INTENT_DEFAULT = 'ai_generation';
const ROLE_SYSTEM = 'system';
const CONTENT_TYPE_JSON = 'application/json';
const REQUEST_TIMEOUT_MESSAGE = 'Request timeout';
const PROVIDER_HTTP_ERROR_MESSAGE = 'AI provider request failed';
const PROVIDER_EMPTY_RESPONSE_MESSAGE = 'xAI response missing content';
const CONFIG_MISSING_KEY_MESSAGE = 'XAI_API_KEY is not configured';
const MESSAGES_REQUIRED_MESSAGE = 'AI messages are required';
const MESSAGE_INVALID_MESSAGE = 'AI messages must include role and content';
const RESOLUTION_SET_API_KEY =
  'Set XAI_API_KEY in backend env and restart server.';
const RESOLUTION_ADD_MESSAGE =
  'Provide at least one chat message.';
const RESOLUTION_FIX_MESSAGE =
  'Ensure each message has role + content.';
const RESOLUTION_RETRY_LATER =
  'Retry later or switch to a fallback provider.';
const RESOLUTION_THROTTLE =
  'Throttle requests and retry after backoff.';
const RESOLUTION_CHECK_KEY =
  'Check XAI_API_KEY and retry.';
const RESOLUTION_INSPECT_PAYLOAD =
  'Inspect provider error payload for details.';
const RESOLUTION_RESPONSE_SHAPE =
  'Check provider response shape before retrying.';
const RESOLUTION_INSPECT_ERROR =
  'Inspect error details and retry if appropriate.';
const RETRY_REASON_MISSING_KEY = 'missing_api_key';
const RETRY_REASON_INVALID_REQUEST = 'invalid_request';
const RETRY_REASON_THROTTLE = 'provider_throttle_or_outage';
const RETRY_REASON_CLIENT = 'client_or_auth_error';
const RETRY_REASON_INVALID_RESPONSE = 'provider_invalid_response';
const RETRY_REASON_UNEXPECTED = 'unexpected_error';
const LAYER_SERVICE = 'service';
const HTTP_METHOD_POST = 'POST';

// WHY: Centralize classification strings to avoid typos.
const CLASSIFICATIONS = {
  MISSING_REQUIRED_FIELD: 'MISSING_REQUIRED_FIELD',
  INVALID_INPUT: 'INVALID_INPUT',
  AUTHENTICATION_ERROR: 'AUTHENTICATION_ERROR',
  RATE_LIMITED: 'RATE_LIMITED',
  PROVIDER_OUTAGE: 'PROVIDER_OUTAGE',
  UNKNOWN_PROVIDER_ERROR: 'UNKNOWN_PROVIDER_ERROR',
};

// WHY: Centralize error codes for consistent analytics.
const ERROR_CODES = {
  CONFIG_MISSING_KEY: 'AI_CONFIG_MISSING_KEY',
  MESSAGES_REQUIRED: 'AI_MESSAGES_REQUIRED',
  MESSAGE_INVALID: 'AI_MESSAGE_INVALID',
  PROVIDER_HTTP_ERROR: 'AI_PROVIDER_HTTP_ERROR',
  PROVIDER_EMPTY_RESPONSE: 'AI_PROVIDER_EMPTY_RESPONSE',
  PROVIDER_UNEXPECTED_FAILURE: 'AI_PROVIDER_UNEXPECTED_FAILURE',
};

// WHY: Keep model selection logic consistent and testable.
function resolveModel(useReasoning) {
  return useReasoning ? AI_MODEL_REASONING : AI_MODEL_DEFAULT;
}

function resolveProviderName({ model, baseUrl }) {
  const normalizedModel = (model || '').toLowerCase();
  const normalizedUrl = (baseUrl || '').toLowerCase();

  if (
    normalizedUrl.includes('groq.com') ||
    normalizedModel.startsWith('groq/')
  ) {
    return PROVIDERS.GROQ;
  }

  if (normalizedUrl.includes('x.ai') || normalizedModel.startsWith('xai.')) {
    return PROVIDERS.XAI;
  }

  if (normalizedUrl.includes('openai.com') || normalizedModel.startsWith('openai/')) {
    return PROVIDERS.GROQ;
  }

  return PROVIDERS.UNKNOWN;
}

function sanitizeModelForRequest(model) {
  const trimmed = (model || '').trim();
  if (!trimmed) return trimmed;
  const sanitized = trimmed
    .replace(/^groq\//i, '')
    .replace(/^xai\./i, '')
    .replace(/^openai\//i, '');
  return sanitized || trimmed;
}

// WHY: Enforce minimum input shape before any provider call.
function assertMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) {
    const error = new Error(MESSAGES_REQUIRED_MESSAGE);
    error.classification = CLASSIFICATIONS.MISSING_REQUIRED_FIELD;
    error.errorCode = ERROR_CODES.MESSAGES_REQUIRED;
    error.resolutionHint = RESOLUTION_ADD_MESSAGE;
    return error;
  }

  const invalid = messages.find(
    (msg) => !msg || !msg.role || !msg.content
  );
  if (invalid) {
    const error = new Error(MESSAGE_INVALID_MESSAGE);
    error.classification = CLASSIFICATIONS.INVALID_INPUT;
    error.errorCode = ERROR_CODES.MESSAGE_INVALID;
    error.resolutionHint = RESOLUTION_FIX_MESSAGE;
    return error;
  }

  return null;
}

// WHY: Keep log payloads consistent across success/failure paths.
function buildLogBase(context, step) {
  return {
    requestId: context?.requestId || UNKNOWN_VALUE,
    route: context?.route || UNKNOWN_VALUE,
    step,
    layer: LAYER_SERVICE,
    operation: context?.operation || OPERATION_CHAT,
    intent: context?.intent || INTENT_DEFAULT,
    userRole: context?.userRole || UNKNOWN_VALUE,
    hasBusinessId: Boolean(context?.businessId),
    businessId: context?.businessId || null,
  };
}

// WHY: Provide the mandatory sanitised request context for provider logs.
function buildProviderContext({
  provider,
  country,
  source,
  hasSystemPrompt,
  hasTemperature,
  hasMaxTokens,
  messageCount,
  model,
}) {
  return {
    provider: provider || PROVIDERS.UNKNOWN,
    country: country || UNKNOWN_VALUE,
    source: source || UNKNOWN_VALUE,
    hasSystemPrompt,
    hasTemperature,
    hasMaxTokens,
    messageCount,
    model,
  };
}

// WHY: Consistent error object with required metadata.
function buildAiError({
  message,
  classification,
  errorCode,
  resolutionHint,
  step,
  httpStatus,
  providerErrorCode,
  providerMessage,
}) {
  const error = new Error(message);
  error.classification = classification;
  error.errorCode = errorCode;
  error.resolutionHint = resolutionHint;
  error.step = step;
  error.httpStatus = httpStatus;
  error.providerErrorCode = providerErrorCode;
  error.providerMessage = providerMessage;
  return error;
}

// WHY: Compute retry guidance once so logs are consistent.
function getRetryHint(status) {
  if (status === 429 || (status >= 500 && status <= 599)) {
    return {
      retry_allowed: true,
      retry_reason: RETRY_REASON_THROTTLE,
    };
  }

  return {
    retry_skipped: true,
    retry_reason: RETRY_REASON_CLIENT,
  };
}

// WHY: Use native https to avoid new dependencies.
function postJson(urlString, body, headers, timeoutMs) {
  const url = new URL(urlString);
  const payload = JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const request = https.request(
      {
        method: HTTP_METHOD_POST,
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        port: HTTPS_PORT,
        timeout: timeoutMs,
        headers: {
          'Content-Type': CONTENT_TYPE_JSON,
          'Content-Length': Buffer.byteLength(payload),
          ...headers,
        },
      },
      (response) => {
        let data = '';
        response.on('data', (chunk) => {
          data += chunk;
        });
        response.on('end', () => {
          let parsed = null;
          try {
            parsed = JSON.parse(data);
          } catch (err) {
            parsed = null;
          }
          resolve({
            status: response.statusCode || 0,
            data: parsed,
            raw: data,
          });
        });
      }
    );

    request.on('error', reject);
    request.on('timeout', () => {
      request.destroy(new Error(REQUEST_TIMEOUT_MESSAGE));
    });
    request.write(payload);
    request.end();
  });
}

// WHY: Preserve the base path (e.g., /v1) when building chat endpoint.
function buildChatUrl(baseUrl) {
  const url = new URL(baseUrl);
  const basePath =
    url.pathname && url.pathname !== '/'
      ? url.pathname.replace(/\/$/, '')
      : '';
  url.pathname = `${basePath}${AI_CHAT_PATH}`;
  return url;
}

/**
 * Execute a chat completion request against xAI.
 *
 * @param {Object} params
 * @param {Array} params.messages
 * @param {string=} params.systemPrompt
 * @param {number=} params.temperature
 * @param {number=} params.maxTokens
 * @param {boolean=} params.useReasoning
 * @param {Object=} params.context
 */
async function createAiChatCompletion({
  messages,
  systemPrompt,
  temperature,
  maxTokens,
  useReasoning = false,
  context = {},
}) {
  const baseLog = buildLogBase(context, LOG_STEPS.SERVICE_START);
  debug('AI SERVICE: start', baseLog);

  // WHY: Block provider calls when key is missing to avoid 401 noise.
  if (!XAI_API_KEY) {
    const error = buildAiError({
      message: CONFIG_MISSING_KEY_MESSAGE,
      classification: CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
      errorCode: ERROR_CODES.CONFIG_MISSING_KEY,
      resolutionHint: RESOLUTION_SET_API_KEY,
      step: LOG_STEPS.SERVICE_FAIL,
    });
    debug('AI SERVICE: config error', {
      ...buildLogBase(context, LOG_STEPS.SERVICE_FAIL),
      classification: error.classification,
      error_code: error.errorCode,
      resolution_hint: error.resolutionHint,
      retry_skipped: true,
      retry_reason: RETRY_REASON_MISSING_KEY,
    });
    throw error;
  }

  const messageError = assertMessages(messages);
  if (messageError) {
    debug('AI SERVICE: validation error', {
      ...buildLogBase(context, LOG_STEPS.SERVICE_FAIL),
      classification: messageError.classification,
      error_code: messageError.errorCode,
      resolution_hint: messageError.resolutionHint,
      retry_skipped: true,
      retry_reason: RETRY_REASON_INVALID_REQUEST,
    });
    throw messageError;
  }

  const model = resolveModel(useReasoning);
  const preparedMessages = [];
  const providerName = resolveProviderName({
    model,
    baseUrl: AI_BASE_URL,
  });
  const requestModel = sanitizeModelForRequest(model);

  // WHY: System prompts are optional, but should always be first.
  if (systemPrompt) {
    preparedMessages.push({ role: ROLE_SYSTEM, content: systemPrompt });
  }

  preparedMessages.push(...messages);

  const providerContext = buildProviderContext({
    country: context?.country,
    source: context?.source,
    hasSystemPrompt: Boolean(systemPrompt),
    hasTemperature: typeof temperature === 'number',
    hasMaxTokens: typeof maxTokens === 'number',
    messageCount: preparedMessages.length,
    model: requestModel || model,
    provider: providerName,
  });

  debug('AI SERVICE: provider call start', {
    ...buildLogBase(context, LOG_STEPS.PROVIDER_CALL_START),
    providerContext,
  });

  const payload = {
    model: requestModel || model,
    messages: preparedMessages,
  };

  if (typeof temperature === 'number') {
    payload.temperature = temperature;
  }

  if (typeof maxTokens === 'number') {
    payload.max_tokens = maxTokens;
  }

  const url = buildChatUrl(AI_BASE_URL);

  try {
    const response = await postJson(
      url.toString(),
      payload,
      { Authorization: `Bearer ${XAI_API_KEY}` },
      DEFAULT_TIMEOUT_MS
    );

    const status = response.status || 0;
    if (status < 200 || status >= 300) {
      const providerError = response.data?.error || {};
      const classification =
        status === 401 || status === 403
          ? CLASSIFICATIONS.AUTHENTICATION_ERROR
          : status === 429
          ? CLASSIFICATIONS.RATE_LIMITED
          : status >= 500 && status <= 599
          ? CLASSIFICATIONS.PROVIDER_OUTAGE
          : CLASSIFICATIONS.UNKNOWN_PROVIDER_ERROR;

      const error = buildAiError({
        message: PROVIDER_HTTP_ERROR_MESSAGE,
        classification,
        errorCode: ERROR_CODES.PROVIDER_HTTP_ERROR,
        resolutionHint:
          classification === CLASSIFICATIONS.AUTHENTICATION_ERROR
            ? RESOLUTION_CHECK_KEY
            : classification === CLASSIFICATIONS.RATE_LIMITED
            ? RESOLUTION_THROTTLE
            : classification === CLASSIFICATIONS.PROVIDER_OUTAGE
            ? RESOLUTION_RETRY_LATER
            : RESOLUTION_INSPECT_PAYLOAD,
        step: LOG_STEPS.PROVIDER_CALL_FAIL,
        httpStatus: status,
        providerErrorCode: providerError.code || null,
        providerMessage: providerError.message || response.raw || null,
      });

      debug('AI SERVICE: provider call failed', {
        ...buildLogBase(context, LOG_STEPS.PROVIDER_CALL_FAIL),
        providerContext,
        httpStatus: status,
        provider_error_code: error.providerErrorCode,
        provider_message: error.providerMessage,
        classification: error.classification,
        error_code: error.errorCode,
        resolution_hint: error.resolutionHint,
        ...getRetryHint(status),
      });

      throw error;
    }

    const choice = response.data?.choices?.[0]?.message?.content;
    if (!choice) {
      const error = buildAiError({
        message: PROVIDER_EMPTY_RESPONSE_MESSAGE,
        classification: CLASSIFICATIONS.UNKNOWN_PROVIDER_ERROR,
        errorCode: ERROR_CODES.PROVIDER_EMPTY_RESPONSE,
        resolutionHint: RESOLUTION_RESPONSE_SHAPE,
        step: LOG_STEPS.SERVICE_FAIL,
      });

      debug('AI SERVICE: response validation failed', {
        ...buildLogBase(context, LOG_STEPS.SERVICE_FAIL),
        providerContext,
        classification: error.classification,
        error_code: error.errorCode,
        resolution_hint: error.resolutionHint,
        retry_skipped: true,
        retry_reason: RETRY_REASON_INVALID_RESPONSE,
      });

      throw error;
    }

    debug('AI SERVICE: provider call ok', {
      ...buildLogBase(context, LOG_STEPS.PROVIDER_CALL_OK),
      providerContext,
    });

    debug('AI SERVICE: success', {
      ...buildLogBase(context, LOG_STEPS.SERVICE_OK),
      model,
      hasUsage: Boolean(response.data?.usage),
    });

    return {
      model,
      content: choice,
      usage: response.data?.usage || null,
      raw: response.data,
    };
  } catch (err) {
    const classification =
      err.classification || CLASSIFICATIONS.UNKNOWN_PROVIDER_ERROR;
    const errorCode =
      err.errorCode || ERROR_CODES.PROVIDER_UNEXPECTED_FAILURE;
    const resolutionHint =
      err.resolutionHint || RESOLUTION_INSPECT_ERROR;

    debug('AI SERVICE: unexpected error', {
      ...buildLogBase(context, LOG_STEPS.SERVICE_FAIL),
      classification,
      error_code: errorCode,
      resolution_hint: resolutionHint,
      error: err.message,
      retry_skipped: true,
      retry_reason: RETRY_REASON_UNEXPECTED,
    });

    throw err;
  }
}

module.exports = {
  createAiChatCompletion,
  resolveModel,
};
