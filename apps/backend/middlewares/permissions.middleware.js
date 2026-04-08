/**
 * apps/backend/middlewares/permissions.middleware.js
 * --------------------------------------------------
 * WHAT:
 * - Central permission guard for business/staff modules.
 *
 * WHY:
 * - Enforces the role matrix consistently at the route boundary.
 * - Provides standardized 403 responses and structured logs.
 *
 * HOW:
 * - Resolves the actor + staff profile via shared services.
 * - Checks the permission map for module/capability access.
 * - Logs required checkpoints with resolution hints on failure.
 */

const debug = require('../utils/debug');
const {
  PERMISSION_MODULES,
  PERMISSION_CAPABILITIES,
  hasPermission,
} = require('../config/permissions');
const {
  resolveBusinessContext,
  resolveStaffProfile,
} = require('../services/business_context.service');

// WHY: Keep logging fields consistent for permission checks.
const LOG_TAG = 'PERMISSION_GUARD';
const OPERATION = 'PermissionGuard';
const INTENT = 'enforce staff role permissions';
const LAYER = 'middleware';
const OPERATION_CONTEXT = 'ResolveBusinessContext';
const OPERATION_STAFF_PROFILE = 'ResolveStaffProfile';

// WHY: Avoid inline strings for steps and error codes.
const LOG_STEPS = {
  ROUTE_IN: 'ROUTE_IN',
  AUTH_OK: 'AUTH_OK',
  AUTH_FAIL: 'AUTH_FAIL',
  VALIDATION_OK: 'VALIDATION_OK',
  VALIDATION_FAIL: 'VALIDATION_FAIL',
  DB_QUERY_START: 'DB_QUERY_START',
  DB_QUERY_OK: 'DB_QUERY_OK',
  DB_QUERY_FAIL: 'DB_QUERY_FAIL',
  CONTROLLER_RESPONSE_FAIL: 'CONTROLLER_RESPONSE_FAIL',
};

const CLASSIFICATIONS = {
  AUTHENTICATION_ERROR: 'AUTHENTICATION_ERROR',
  MISSING_REQUIRED_FIELD: 'MISSING_REQUIRED_FIELD',
  INVALID_INPUT: 'INVALID_INPUT',
  UNKNOWN_PROVIDER_ERROR: 'UNKNOWN_PROVIDER_ERROR',
};

const ERROR_CODES = {
  AUTH_REQUIRED: 'PERMISSION_AUTH_REQUIRED',
  ACTOR_NOT_FOUND: 'PERMISSION_ACTOR_NOT_FOUND',
  BUSINESS_SCOPE_MISSING: 'PERMISSION_BUSINESS_SCOPE_MISSING',
  STAFF_PROFILE_REQUIRED: 'PERMISSION_STAFF_PROFILE_REQUIRED',
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  PERMISSION_CHECK_FAILED: 'PERMISSION_CHECK_FAILED',
};

const COPY = {
  AUTH_REQUIRED: 'Authentication required',
  STAFF_PROFILE_REQUIRED: 'Staff profile is required for this action',
  PERMISSION_DENIED: 'Forbidden: insufficient permissions',
  BUSINESS_SCOPE_MISSING: 'Business scope is not configured for this user',
  ACTOR_NOT_FOUND: 'User not found',
  PERMISSION_CHECK_FAILED: 'Unable to validate permissions',
};

const RESOLUTION_HINTS = {
  AUTH_REQUIRED: 'Provide a valid Bearer token to access this route.',
  BUSINESS_SCOPE_MISSING:
    'Ensure the user is assigned to a business before retrying.',
  STAFF_PROFILE_REQUIRED:
    'Ensure the staff user has an active staff profile before retrying.',
  PERMISSION_DENIED:
    'Confirm the staff role has the required permission for this module.',
  PERMISSION_CHECK_FAILED:
    'Retry after confirming the permission configuration.',
};

const UNKNOWN_VALUE = 'unknown';
const ROLE_OWNER = 'business_owner';
const ROLE_STAFF = 'staff';

// WHY: Build a consistent log payload for every checkpoint.
function logStep(req, step, extra = {}) {
  const requestId =
    req.headers?.['x-request-id'] ||
    req.requestId ||
    req.id ||
    UNKNOWN_VALUE;
  const route = `${req.method} ${req.originalUrl || req.url}`;

  debug(LOG_TAG, {
    requestId,
    route,
    step,
    layer: LAYER,
    operation: OPERATION,
    intent: INTENT,
    businessId_present: Boolean(extra.businessId),
    businessId: extra.businessId || null,
    userRole: extra.userRole || req.user?.role || UNKNOWN_VALUE,
    ...extra,
  });
}

// WHY: Normalize forbidden responses with required metadata.
function sendForbidden(res, payload) {
  return res.status(403).json(payload);
}

// WHY: Normalize auth errors with required metadata.
function sendUnauthorized(res, payload) {
  return res.status(401).json(payload);
}

// WHY: Factory so each route can declare its module + capability.
function requirePermission({ module, capability }) {
  return async function permissionGuard(req, res, next) {
    const requestId =
      req.headers?.['x-request-id'] ||
      req.requestId ||
      req.id ||
      UNKNOWN_VALUE;
    const route = `${req.method} ${req.originalUrl || req.url}`;
    const contextBase = {
      requestId,
      route,
      operation: OPERATION,
      intent: INTENT,
      userRole: req.user?.role || UNKNOWN_VALUE,
    };

    logStep(req, LOG_STEPS.ROUTE_IN, {
      module,
      capability,
      actorId: req.user?.sub,
    });

    if (!req.user?.sub) {
      logStep(req, LOG_STEPS.AUTH_FAIL, {
        classification: CLASSIFICATIONS.AUTHENTICATION_ERROR,
        error_code: ERROR_CODES.AUTH_REQUIRED,
        resolution_hint: RESOLUTION_HINTS.AUTH_REQUIRED,
      });
      logStep(req, LOG_STEPS.CONTROLLER_RESPONSE_FAIL, {
        classification: CLASSIFICATIONS.AUTHENTICATION_ERROR,
        error_code: ERROR_CODES.AUTH_REQUIRED,
        resolution_hint: RESOLUTION_HINTS.AUTH_REQUIRED,
      });
      return sendUnauthorized(res, {
        error: COPY.AUTH_REQUIRED,
        classification: CLASSIFICATIONS.AUTHENTICATION_ERROR,
        error_code: ERROR_CODES.AUTH_REQUIRED,
        resolution_hint: RESOLUTION_HINTS.AUTH_REQUIRED,
        requestId,
      });
    }

    let actor = null;
    let businessId = null;
    let staffProfile = null;

    try {
      logStep(req, LOG_STEPS.DB_QUERY_START, {
        module,
        capability,
      });
      const context = await resolveBusinessContext(
        req.user.sub,
        {
          ...contextBase,
          operation: OPERATION_CONTEXT,
        }
      );
      actor = context.actor;
      businessId = context.businessId;
      logStep(req, LOG_STEPS.DB_QUERY_OK, {
        actorId: actor._id,
        businessId,
      });
      logStep(req, LOG_STEPS.AUTH_OK, {
        actorId: actor._id,
        businessId,
        userRole: actor.role,
      });
    } catch (err) {
      const message = err?.message || COPY.PERMISSION_CHECK_FAILED;
      const isMissingBusiness =
        message === COPY.BUSINESS_SCOPE_MISSING;
      const isMissingActor = message === COPY.ACTOR_NOT_FOUND;
      const classification = isMissingActor
        ? CLASSIFICATIONS.AUTHENTICATION_ERROR
        : CLASSIFICATIONS.MISSING_REQUIRED_FIELD;
      const errorCode = isMissingActor
        ? ERROR_CODES.ACTOR_NOT_FOUND
        : ERROR_CODES.BUSINESS_SCOPE_MISSING;
      const resolutionHint = isMissingActor
        ? RESOLUTION_HINTS.AUTH_REQUIRED
        : RESOLUTION_HINTS.BUSINESS_SCOPE_MISSING;

      logStep(req, LOG_STEPS.DB_QUERY_FAIL, {
        classification,
        error_code: errorCode,
        resolution_hint: resolutionHint,
        error: message,
      });
      logStep(req, LOG_STEPS.CONTROLLER_RESPONSE_FAIL, {
        classification,
        error_code: errorCode,
        resolution_hint: resolutionHint,
      });

      return sendForbidden(res, {
        error: message,
        classification,
        error_code: errorCode,
        resolution_hint: resolutionHint,
        requestId,
      });
    }

    if (actor.role === ROLE_STAFF) {
      try {
        logStep(req, LOG_STEPS.DB_QUERY_START, {
          module,
          capability,
          actorId: actor._id,
          businessId,
        });
        staffProfile = await resolveStaffProfile({
          actor,
          businessId,
          allowMissing: false,
        }, {
          ...contextBase,
          businessId,
          userRole: actor.role,
          operation: OPERATION_STAFF_PROFILE,
        });
        logStep(req, LOG_STEPS.DB_QUERY_OK, {
          actorId: actor._id,
          businessId,
          staffRole: staffProfile?.staffRole || null,
        });
      } catch (err) {
        logStep(req, LOG_STEPS.VALIDATION_FAIL, {
          classification: CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
          error_code: ERROR_CODES.STAFF_PROFILE_REQUIRED,
          resolution_hint: RESOLUTION_HINTS.STAFF_PROFILE_REQUIRED,
        });
        logStep(req, LOG_STEPS.CONTROLLER_RESPONSE_FAIL, {
          classification: CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
          error_code: ERROR_CODES.STAFF_PROFILE_REQUIRED,
          resolution_hint: RESOLUTION_HINTS.STAFF_PROFILE_REQUIRED,
        });
        return sendForbidden(res, {
          error: COPY.STAFF_PROFILE_REQUIRED,
          classification: CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
          error_code: ERROR_CODES.STAFF_PROFILE_REQUIRED,
          resolution_hint: RESOLUTION_HINTS.STAFF_PROFILE_REQUIRED,
          requestId,
        });
      }
    }

    const allowed = hasPermission({
      actorRole: actor.role,
      staffRole: staffProfile?.staffRole,
      module,
      capability,
    });

    if (!allowed) {
      logStep(req, LOG_STEPS.VALIDATION_FAIL, {
        classification: CLASSIFICATIONS.AUTHENTICATION_ERROR,
        error_code: ERROR_CODES.PERMISSION_DENIED,
        resolution_hint: RESOLUTION_HINTS.PERMISSION_DENIED,
        actorId: actor._id,
        businessId,
        staffRole: staffProfile?.staffRole || null,
      });
      logStep(req, LOG_STEPS.CONTROLLER_RESPONSE_FAIL, {
        classification: CLASSIFICATIONS.AUTHENTICATION_ERROR,
        error_code: ERROR_CODES.PERMISSION_DENIED,
        resolution_hint: RESOLUTION_HINTS.PERMISSION_DENIED,
      });
      return sendForbidden(res, {
        error: COPY.PERMISSION_DENIED,
        classification: CLASSIFICATIONS.AUTHENTICATION_ERROR,
        error_code: ERROR_CODES.PERMISSION_DENIED,
        resolution_hint: RESOLUTION_HINTS.PERMISSION_DENIED,
        requestId,
      });
    }

    logStep(req, LOG_STEPS.VALIDATION_OK, {
      actorId: actor._id,
      businessId,
      staffRole: staffProfile?.staffRole || null,
    });

    // WHY: Cache resolved context for downstream controllers.
    req.permissionContext = {
      actor,
      businessId,
      staffRole: staffProfile?.staffRole || null,
    };

    return next();
  };
}

module.exports = {
  requirePermission,
  PERMISSION_MODULES,
  PERMISSION_CAPABILITIES,
};
