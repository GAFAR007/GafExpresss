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
    // ✅ Business ownership (tenant scope)
    // WHY: Keeps product access locked to a single business.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },
    // ✅ Creator tracking (audit who created the product)
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    // ✅ Last editor tracking (audit who last updated the product)
    updatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
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
    // ✅ Gallery image URLs (multiple images per product)
    // WHY: Supports product galleries while keeping a primary imageUrl.
    imageUrls: {
      type: [String],
      default: [],
    },
    // ✅ Gallery image assets (url + Cloudinary public id)
    // WHY: Enables safe deletion from Cloudinary while keeping url display.
    imageAssets: {
      type: [
        {
          url: { type: String, trim: true, required: true },
          publicId: { type: String, trim: true, default: '' },
        },
      ],
      default: [],
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
// WHY: Scope business product lists efficiently.
productSchema.index({ businessId: 1, isActive: 1 });
productSchema.index({ name: 'text', description: 'text' }); // for future search

const Product = mongoose.model('Product', productSchema);

module.exports = Product;
