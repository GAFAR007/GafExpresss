/**
 * utils/audit.js
 * --------------
 * WHAT:
 * - Shared helper for writing audit log entries.
 *
 * WHY:
 * - Keeps audit logging consistent across services.
 * - Avoids duplicated logging boilerplate.
 *
 * HOW:
 * - Builds a minimal entry and saves it with debug output.
 */

const AuditLog = require('../models/AuditLog');
const debug = require('./debug');

async function writeAuditLog({
  businessId,
  actorId,
  actorRole,
  action,
  entityType,
  entityId,
  message,
  changes,
  required = false,
}) {
  // WHY: Avoid breaking flows if audit logging fails unless the caller is an audit-only action.
  try {
    const entry = await AuditLog.create({
      businessId: businessId || null,
      actor: actorId,
      actorRole,
      action,
      entityType,
      entityId,
      message,
      changes: changes || null,
    });

    debug('AUDIT: entry created', {
      id: entry._id,
      action,
      entityType,
      entityId,
    });
    return entry;
  } catch (err) {
    debug('AUDIT: failed to write entry', err.message);
    if (required) {
      throw err;
    }
    return null;
  }
}

module.exports = {
  writeAuditLog,
};
