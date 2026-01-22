/**
 * models/BusinessAnalyticsEvent.js
 * --------------------------------
 * WHAT:
 * - Stores lightweight analytics events for business reporting.
 *
 * WHY:
 * - Enables trend analysis without coupling to raw audit logs.
 * - Keeps analytics data scoped by business for safe reporting.
 *
 * HOW:
 * - Records event type, actor, entity, and metadata snapshots.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading BusinessAnalyticsEvent model...');

const businessAnalyticsEventSchema = new mongoose.Schema(
  {
    // WHY: Every analytics event must be scoped to a business.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    // WHY: Actor metadata helps explain who initiated changes.
    actorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    actorRole: {
      type: String,
      trim: true,
      default: null,
    },
    // WHY: Event type drives analytics grouping and summaries.
    eventType: {
      type: String,
      trim: true,
      required: true,
      index: true,
    },
    // WHY: Optional entity references help drill into details.
    entityType: {
      type: String,
      trim: true,
      default: null,
    },
    entityId: {
      type: mongoose.Schema.Types.ObjectId,
      default: null,
    },
    // WHY: Flexible metadata captures totals, status, and tags.
    metadata: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

// WHY: Analytics feeds need fast lookups by business + time.
businessAnalyticsEventSchema.index({ businessId: 1, createdAt: -1 });
businessAnalyticsEventSchema.index({ businessId: 1, eventType: 1 });

const BusinessAnalyticsEvent = mongoose.model(
  'BusinessAnalyticsEvent',
  businessAnalyticsEventSchema
);

module.exports = BusinessAnalyticsEvent;
