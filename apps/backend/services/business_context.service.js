/**
 * apps/backend/services/business_context.service.js
 * -------------------------------------------------
 * WHAT:
 * - Shared helpers to resolve the current actor and staff profile.
 *
 * WHY:
 * - Avoids duplicated business-scoping logic across controllers/middleware.
 * - Keeps staff role enforcement consistent and testable.
 *
 * HOW:
 * - Loads the User to determine businessId and staff scope.
 * - Loads BusinessStaffProfile when the actor is a staff member.
 */

const debug = require('../utils/debug');
const User = require('../models/User');
const BusinessStaffProfile = require('../models/BusinessStaffProfile');

// WHY: Keep logs consistent with backend step requirements.
const LOG_TAG = 'BUSINESS_CONTEXT_SERVICE';
const LOG_STEPS = {
  SERVICE_START: 'SERVICE_START',
  DB_QUERY_START: 'DB_QUERY_START',
  DB_QUERY_OK: 'DB_QUERY_OK',
  DB_QUERY_FAIL: 'DB_QUERY_FAIL',
  SERVICE_OK: 'SERVICE_OK',
  SERVICE_FAIL: 'SERVICE_FAIL',
};
const UNKNOWN_VALUE = 'unknown';

function logStep(step, context = {}) {
  // WHY: Avoid noisy logs unless a caller supplies trace context.
  if (
    !context ||
    (!context.requestId && !context.route && !context.operation)
  ) {
    return;
  }

  debug(LOG_TAG, {
    requestId: context.requestId || UNKNOWN_VALUE,
    route: context.route || UNKNOWN_VALUE,
    step,
    layer: 'service',
    operation: context.operation || 'ResolveBusinessContext',
    intent: context.intent || 'resolve business scope',
    businessId_present: Boolean(context.businessId),
    businessId: context.businessId || null,
    userRole: context.userRole || UNKNOWN_VALUE,
    ...context.extra,
  });
}

// WHY: Select only fields needed for authorization and scoping.
const ACTOR_SELECT_FIELDS =
  'role businessId isNinVerified email estateAssetId name firstName middleName lastName phone ninLast4';

async function resolveBusinessContext(userId, context = {}) {
  // WHY: Guard against missing userId early to avoid unsafe queries.
  if (!userId) {
    logStep(LOG_STEPS.SERVICE_FAIL, {
      ...context,
      extra: {
        classification: 'MISSING_REQUIRED_FIELD',
        error_code: 'BUSINESS_CONTEXT_USER_ID_REQUIRED',
        resolution_hint: 'Provide a valid user id before retrying.',
      },
    });
    throw new Error('User id is required');
  }

  logStep(LOG_STEPS.SERVICE_START, context);
  logStep(LOG_STEPS.DB_QUERY_START, context);

  const actor = await User.findById(userId).select(
    ACTOR_SELECT_FIELDS
  );

  if (!actor) {
    logStep(LOG_STEPS.DB_QUERY_FAIL, {
      ...context,
      extra: {
        classification: 'AUTHENTICATION_ERROR',
        error_code: 'BUSINESS_CONTEXT_USER_NOT_FOUND',
        resolution_hint: 'Ensure the user exists before retrying.',
      },
    });
    throw new Error('User not found');
  }

  if (!actor.businessId) {
    logStep(LOG_STEPS.DB_QUERY_FAIL, {
      ...context,
      extra: {
        classification: 'MISSING_REQUIRED_FIELD',
        error_code: 'BUSINESS_CONTEXT_MISSING_BUSINESS',
        resolution_hint: 'Assign a businessId to the user before retrying.',
      },
    });
    throw new Error('Business scope is not configured for this user');
  }

  logStep(LOG_STEPS.DB_QUERY_OK, {
    ...context,
    businessId: actor.businessId,
    userRole: actor.role,
  });
  logStep(LOG_STEPS.SERVICE_OK, {
    ...context,
    businessId: actor.businessId,
    userRole: actor.role,
  });

  return {
    actor,
    businessId: actor.businessId,
  };
}

async function resolveStaffProfile(
  { actor, businessId, allowMissing = false },
  context = {}
) {
  // WHY: Only staff roles have staff profiles; owners skip this lookup.
  if (actor?.role !== 'staff') {
    return null;
  }

  logStep(LOG_STEPS.SERVICE_START, {
    ...context,
    businessId,
    userRole: actor?.role || UNKNOWN_VALUE,
  });
  logStep(LOG_STEPS.DB_QUERY_START, {
    ...context,
    businessId,
    userRole: actor?.role || UNKNOWN_VALUE,
  });

  const profile = await BusinessStaffProfile.findOne({
    userId: actor._id,
    businessId,
  });

  if (!profile && !allowMissing) {
    logStep(LOG_STEPS.DB_QUERY_FAIL, {
      ...context,
      businessId,
      userRole: actor?.role || UNKNOWN_VALUE,
      extra: {
        classification: 'MISSING_REQUIRED_FIELD',
        error_code: 'BUSINESS_CONTEXT_STAFF_PROFILE_MISSING',
        resolution_hint: 'Ensure the staff user has an active profile.',
      },
    });
    throw new Error('Staff profile not found');
  }

  logStep(LOG_STEPS.DB_QUERY_OK, {
    ...context,
    businessId,
    userRole: actor?.role || UNKNOWN_VALUE,
  });
  logStep(LOG_STEPS.SERVICE_OK, {
    ...context,
    businessId,
    userRole: actor?.role || UNKNOWN_VALUE,
  });

  return profile;
}

module.exports = {
  resolveBusinessContext,
  resolveStaffProfile,
};
