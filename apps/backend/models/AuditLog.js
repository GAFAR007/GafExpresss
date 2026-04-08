/**
 * models/AuditLog.js
 * -------------------
 * WHAT:
 * - Stores immutable audit entries for sensitive business actions.
 *
 * WHY:
 * - Keeps a permanent trail of who changed products, orders, or roles.
 * - Supports compliance and internal investigations.
 *
 * HOW:
 * - Each entry records actor, action, entity, and optional change payload.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading AuditLog model...');

const auditLogSchema = new mongoose.Schema(
  {
    // ✅ Business scope for multi-tenant filtering
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },
    // ✅ Actor who performed the action
    actor: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    actorRole: {
      type: String,
      trim: true,
      required: true,
    },
    // ✅ What happened
    action: {
      type: String,
      trim: true,
      required: true,
    },
    // ✅ Target entity
    entityType: {
      type: String,
      trim: true,
      required: true,
    },
    entityId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
    },
    // ✅ Human readable summary (safe for dashboards)
    message: {
      type: String,
      trim: true,
    },
    // ✅ Optional change details for debugging audits
    changes: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

auditLogSchema.index({ entityType: 1, entityId: 1 });
auditLogSchema.index({ createdAt: -1 });

const AuditLog = mongoose.model('AuditLog', auditLogSchema);

module.exports = AuditLog;
