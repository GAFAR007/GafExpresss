/**
 * config/db.js
 * ------------
 * MongoDB connection handler.
 *
 * WHAT:
 * - Connects to MongoDB using mongoose
 *
 * WHY:
 * - Centralizes database connection logic
 * - Makes server startup predictable
 */
const mongoose = require('mongoose');
const debug = require('../utils/debug');

const mongoUri = process.env.MONGO_URI;

async function connectDB() {
  try {
    debug('Attempting MongoDB connection');
    await mongoose.connect(mongoUri);
    console.log('🟢 MongoDB connected successfully');
    debug('MongoDB connection established');
  } catch (error) {
    console.error('❌ MongoDB connection failed');
    console.error(error.message);
    process.exit(1);
  }
}

module.exports = connectDB;
