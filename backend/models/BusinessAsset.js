/**
 * models/BusinessAsset.js
 * ------------------------
 * WHAT:
 * - Stores non-product assets owned by a business (vehicles, equipment, etc.).
 *
 * WHY:
 * - Separates operational assets from product inventory.
 * - Keeps business asset tracking auditable and scoped.
 *
 * HOW:
 * - Each asset is linked to a businessId and soft-deletable.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading BusinessAsset model...');

const assetSchema = new mongoose.Schema(
  {
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    assetType: {
      type: String,
      enum: ['vehicle', 'equipment', 'warehouse', 'other'],
      required: true,
      trim: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    description: {
      type: String,
      trim: true,
    },
    serialNumber: {
      type: String,
      trim: true,
    },
    status: {
      type: String,
      enum: ['active', 'inactive', 'maintenance'],
      default: 'active',
    },
    location: {
      type: String,
      trim: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    updatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    deletedAt: {
      type: Date,
      default: null,
    },
    deletedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

assetSchema.index({ businessId: 1, assetType: 1 });

const BusinessAsset = mongoose.model('BusinessAsset', assetSchema);

module.exports = BusinessAsset;
