/**
 * models/Product.js
 * -----------------
 * WHAT:
 * - Defines the Product schema for the e-commerce store
 *
 * WHY:
 * - Central source of truth for product data
 * - Enables admin management and public listing
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading Product model...');

const productSchema = new mongoose.Schema(
  {
    // ✅ Product name (required)
    name: {
      type: String,
      required: [true, 'Product name is required'],
      trim: true,
      minlength: 2,
      maxlength: 100,
    },

    // ✅ Description (optional but useful)
    description: {
      type: String,
      trim: true,
      maxlength: 1000,
      default: '',
    },

    // ✅ Price in cents (avoid floating point issues)
    price: {
      type: Number,
      required: [true, 'Price is required'],
      min: [0, 'Price cannot be negative'],
    },

    // ✅ Stock quantity
    stock: {
      type: Number,
      required: [true, 'Stock quantity is required'],
      min: [0, 'Stock cannot be negative'],
      default: 0,
    },

    // ✅ Image URL (for now — later can extend to uploads)
    imageUrl: {
      type: String,
      trim: true,
      default: '',
    },

    // ✅ Visibility control
    isActive: {
      type: Boolean,
      default: true,
    },

    // ✅ Soft delete tracking
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
    timestamps: true, // createdAt, updatedAt
  }
);

// Index for faster queries
productSchema.index({ isActive: 1 });
productSchema.index({ name: 'text', description: 'text' }); // for future search

const Product = mongoose.model('Product', productSchema);

module.exports = Product;