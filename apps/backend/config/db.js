/**
 * config/db.js
 * ------------
 * WHAT:
 * - Creates the shared MongoDB connection and exposes readiness helpers.
 *
 * WHY:
 * - Prevents the HTTP server from accepting traffic before MongoDB is ready.
 * - Gives controllers/routes one consistent way to classify database outages.
 *
 * HOW:
 * - Disables Mongoose command buffering so disconnected queries fail fast.
 * - Attaches connection lifecycle logs once.
 * - Exports connectDB plus lightweight status helpers.
 */
const mongoose = require('mongoose');
const debug = require('../utils/debug');

// WHY: One shared mapping keeps health checks and logs readable.
const READY_STATE_LABELS = {
  0: 'disconnected',
  1: 'connected',
  2: 'connecting',
  3: 'disconnecting',
};

// WHY: Mongoose uses numeric readyState values, so keep the connected value named.
const CONNECTED_READY_STATE = 1;

// WHY: Connection event listeners should only be registered once per process.
let hasAttachedConnectionListeners = false;

// WHY: Buffering hides outages behind slow query timeouts. Disable it globally.
mongoose.set('bufferCommands', false);

function getMongoUri() {
  return process.env.MONGO_URI;
}

function summarizeMongoUri(mongoUri) {
  if (!mongoUri) {
    return {
      protocol: null,
      host: null,
      database: null,
    };
  }

  try {
    const parsedMongoUri = new URL(mongoUri);
    return {
      protocol: parsedMongoUri.protocol.replace(':', ''),
      host: parsedMongoUri.host || null,
      database:
        parsedMongoUri.pathname?.replace(/^\//, '') || null,
    };
  } catch (error) {
    return {
      protocol: 'unparsed',
      host: null,
      database: null,
    };
  }
}

function getDatabaseStatus() {
  const { readyState, host, name } = mongoose.connection;

  return {
    isReady: readyState === CONNECTED_READY_STATE,
    readyState,
    state: READY_STATE_LABELS[readyState] || 'unknown',
    host: host || null,
    database: name || null,
  };
}

function isDatabaseReady() {
  return mongoose.connection.readyState === CONNECTED_READY_STATE;
}

function isDatabaseConnectivityError(error) {
  if (!error) return false;

  const errorMessage = String(error.message || '');

  // WHY: These signatures cover the Atlas DNS timeout and disconnected-query cases.
  return (
    error.name === 'MongooseServerSelectionError' ||
    error.name === 'MongoServerSelectionError' ||
    error.name === 'MongoNetworkError' ||
    errorMessage.includes('buffering timed out') ||
    errorMessage.includes('Client must be connected') ||
    errorMessage.includes('Topology is closed') ||
    errorMessage.includes('ECONNREFUSED') ||
    errorMessage.includes('ENOTFOUND') ||
    errorMessage.includes('ETIMEOUT') ||
    errorMessage.includes('queryTxt')
  );
}

function attachConnectionListeners() {
  if (hasAttachedConnectionListeners) {
    return;
  }

  hasAttachedConnectionListeners = true;

  // WHY: Lifecycle logs make intermittent Atlas/network failures diagnosable.
  mongoose.connection.on('connected', () => {
    debug('MongoDB driver event: connected', getDatabaseStatus());
  });

  mongoose.connection.on('disconnected', () => {
    debug('MongoDB driver event: disconnected', getDatabaseStatus());
  });

  mongoose.connection.on('reconnected', () => {
    debug('MongoDB driver event: reconnected', getDatabaseStatus());
  });

  mongoose.connection.on('error', (error) => {
    debug('MongoDB driver event: error', {
      error,
      databaseStatus: getDatabaseStatus(),
    });
  });
}

async function connectDB() {
  const mongoUri = getMongoUri();

  if (!mongoUri) {
    throw new Error('MONGO_URI is required before starting the backend');
  }

  attachConnectionListeners();

  try {
    // WHY: Keep connection attempts observable without logging credentials.
    debug('Attempting MongoDB connection', summarizeMongoUri(mongoUri));
    await mongoose.connect(mongoUri, {
      serverSelectionTimeoutMS: Number(
        process.env.MONGO_SERVER_SELECTION_TIMEOUT_MS || 10000,
      ),
    });
    console.log('🟢 MongoDB connected successfully');
    debug('MongoDB connection established', getDatabaseStatus());
    return mongoose.connection;
  } catch (error) {
    console.error('❌ MongoDB connection failed');
    console.error(error.message);
    debug('MongoDB connection failed', {
      error,
      mongo: summarizeMongoUri(mongoUri),
      databaseStatus: getDatabaseStatus(),
    });
    throw error;
  }
}

module.exports = connectDB;
module.exports.getDatabaseStatus = getDatabaseStatus;
module.exports.isDatabaseReady = isDatabaseReady;
module.exports.isDatabaseConnectivityError = isDatabaseConnectivityError;
