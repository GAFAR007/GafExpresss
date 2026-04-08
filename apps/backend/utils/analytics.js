/**
 * utils/analytics.js
 * ------------------
 * WHAT:
 * - Shared helper for writing business analytics events.
 *
 * WHY:
 * - Keeps analytics logging consistent across services.
 * - Avoids duplicating event creation boilerplate.
 *
 * HOW:
 * - Builds a minimal event payload and saves it safely.
 */

const BusinessAnalyticsEvent = require('../models/BusinessAnalyticsEvent');
const debug = require('./debug');

async function writeAnalyticsEvent({
  businessId,
  actorId,
  actorRole,
  eventType,
  entityType,
  entityId,
  metadata,
}) {
  // WHY: Analytics should never block core flows if it fails.
  try {
    const entry = await BusinessAnalyticsEvent.create({
      businessId,
      actorId: actorId || null,
      actorRole: actorRole || null,
      eventType,
      entityType: entityType || null,
      entityId: entityId || null,
      metadata: metadata || null,
    });

    debug('ANALYTICS: event created', {
      id: entry._id,
      eventType,
      entityType,
      entityId,
    });
  } catch (err) {
    debug('ANALYTICS: failed to write event', err.message);
  }
}

module.exports = {
  writeAnalyticsEvent,
};
