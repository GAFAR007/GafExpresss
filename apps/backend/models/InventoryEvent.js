/**
 * models/InventoryEvent.js
 * -------------------------
 * WHAT:
 * - Records stock changes for product inventory.
 *
 * WHY:
 * - Auditable trail for stock adjustments and order fulfillment.
 * - Helps explain who changed stock and why.
 *
 * HOW:
 * - Each event stores before/after counts and the actor.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading InventoryEvent model...');

const inventoryEventSchema = new mongoose.Schema(
  {
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },
    product: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Product',
      required: true,
      index: true,
    },
    // ✅ Stock delta (positive or negative)
    delta: {
      type: Number,
      required: true,
    },
    before: {
      type: Number,
      required: true,
    },
    after: {
      type: Number,
      required: true,
    },
    reason: {
      type: String,
      trim: true,
    },
    source: {
      type: String,
      trim: true,
    },
    orderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Order',
      default: null,
    },
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
  },
  {
    timestamps: true,
  }
);

inventoryEventSchema.index({ createdAt: -1 });

const InventoryEvent = mongoose.model('InventoryEvent', inventoryEventSchema);

module.exports = InventoryEvent;
