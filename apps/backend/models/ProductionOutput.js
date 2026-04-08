/**
 * apps/backend/models/ProductionOutput.js
 * ------------------------------------------------
 * WHAT:
 * - Stores storage-phase outputs for production plans.
 *
 * WHY:
 * - Converts harvest/storage output into structured inventory metrics.
 * - Supports product listing once output is ready.
 *
 * HOW:
 * - Links output to a production plan and product.
 * - Records unit type, quantity, and optional pricing.
 * - Shares the existing productionoutputs collection with crop profiles so the app stays within the Atlas collection cap.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading ProductionOutput model...');

const PRODUCTION_OUTPUT_COLLECTION_NAME = 'productionoutputs';
const PRODUCTION_OUTPUT_RECORD_TYPE = 'production_output';

// WHY: Fixed units keep reporting consistent across plans.
const PRODUCTION_OUTPUT_UNITS = [
  'bags',
  'kg',
  'crates',
  'sacks',
  'boxes',
  'bunches',
  'liters',
  'tons',
  'units',
];

const productionOutputSchema = new mongoose.Schema(
  {
    // WHY: Output must belong to a plan.
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionPlan',
      required: true,
      index: true,
    },
    recordType: {
      type: String,
      enum: [PRODUCTION_OUTPUT_RECORD_TYPE],
      default: PRODUCTION_OUTPUT_RECORD_TYPE,
      index: true,
    },
    // WHY: Output links to product inventory for sales.
    productId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Product',
      required: true,
      index: true,
    },
    // WHY: Unit type standardizes output measurement.
    unitType: {
      type: String,
      enum: PRODUCTION_OUTPUT_UNITS,
      required: true,
      index: true,
    },
    // WHY: Quantity measures output volume.
    quantity: {
      type: Number,
      min: 0,
      required: true,
    },
    // WHY: Ready-for-sale flag controls product listing automation.
    readyForSale: {
      type: Boolean,
      default: false,
      index: true,
    },
    // WHY: Price per unit supports direct sales when available.
    pricePerUnit: {
      type: Number,
      min: 0,
      default: null,
    },
  },
  {
    timestamps: true,
    collection: PRODUCTION_OUTPUT_COLLECTION_NAME,
  },
);

function applyProductionOutputRecordTypeFilter() {
  this.where({
    recordType: PRODUCTION_OUTPUT_RECORD_TYPE,
  });
}

[
  'find',
  'findOne',
  'findOneAndUpdate',
  'findOneAndDelete',
  'findOneAndReplace',
  'countDocuments',
  'deleteMany',
  'updateOne',
  'updateMany',
].forEach((hook) => {
  productionOutputSchema.pre(
    hook,
    applyProductionOutputRecordTypeFilter,
  );
});

const ProductionOutput = mongoose.model(
  'ProductionOutput',
  productionOutputSchema,
);

module.exports = ProductionOutput;
module.exports.PRODUCTION_OUTPUT_UNITS =
  PRODUCTION_OUTPUT_UNITS;
