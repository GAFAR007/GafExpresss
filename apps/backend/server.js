/**
 * server.js
 * ----------
 * Main entry point for the Express backend.
 *
 * WHAT:
 * - Creates Express app
 * - Loads environment variables
 * - Registers global middleware
 * - Registers routes
 * - Starts HTTP server
 *
 * WHY:
 * - Single predictable entry point
 * - Easy to debug startup issues
 */

// --------------------------------------------------
// ENVIRONMENT VARIABLES
// --------------------------------------------------
require('dotenv').config({ quiet: true });

// --------------------------------------------------
// IMPORTS
// --------------------------------------------------
const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const debug = require('./utils/debug');
const connectDB = require('./config/db');
const {
  getDatabaseStatus,
  isDatabaseReady,
  isDatabaseConnectivityError,
} = connectDB;
const registerRoutes = require('./routes');
const swaggerUi = require('swagger-ui-express');
const swaggerSpec = require('./config/swagger');
const { registerChatSocket } = require('./services/chat_socket.service');
const {
  registerDraftPresenceSocket,
} = require('./services/production_draft_presence_socket.service');
const {
  startPreorderReconcileWorker,
} = require('./services/preorder_reservation_reconciler.worker');

/**
 * --------------------------------------------------
 * CREATE EXPRESS APP
 * --------------------------------------------------
 */
debug('Creating Express app instance');
const app = express();

// WHY: Create a shared HTTP server for Express + Socket.IO.
const server = http.createServer(app);


// BEFORE express.json() important — raw body for webhooks
app.use('/webhooks', require('./routes/webhooks.routes'));
/**
 * --------------------------------------------------
 * GLOBAL MIDDLEWARE
 * --------------------------------------------------
 */
debug('Registering global middleware');
app.use(cors());
app.use(express.json());

/**
 * --------------------------------------------------
 * SWAGGER DOCS SETUP
 * --------------------------------------------------
 * Mount Swagger UI at /docs
 * - Interactive API documentation
 * - Available at http://localhost:4000/docs
 */
debug('Setting up Swagger docs at /docs');
app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec));

/**
 * --------------------------------------------------
 * DATABASE READINESS GUARD
 * --------------------------------------------------
 * NOTE:
 * - Allows liveness/readiness checks to stay reachable even when MongoDB is down
 * - Rejects application traffic quickly if MongoDB drops after startup
 */
app.use((req, res, next) => {
  // WHY: Liveness/readiness checks must stay reachable even when the database is down.
  if (req.path === '/health' || req.path === '/ready') {
    return next();
  }

  // WHY: Docs remain useful during outages and do not require MongoDB.
  if (req.path === '/docs' || req.path.startsWith('/docs/')) {
    return next();
  }

  if (isDatabaseReady()) {
    return next();
  }

  debug('Rejecting request because MongoDB is unavailable', {
    method: req.method,
    path: req.originalUrl,
    databaseStatus: getDatabaseStatus(),
  });

  return res.status(503).json({
    error: 'Database unavailable',
    resolutionHint: 'Restore MongoDB connectivity and retry the request.',
  });
});

/**
 * --------------------------------------------------
 * ROUTES
 * --------------------------------------------------
 * NOTE:
 * - Routes are registered via routes/index.js
 */
debug('Registering routes');
registerRoutes(app);

/**
 * --------------------------------------------------
 * SERVER START
 * --------------------------------------------------
 */
const PORT = process.env.PORT || 4000;
const MONGO_RETRY_DELAY_MS = Number(
  process.env.MONGO_RETRY_DELAY_MS || 5000,
);

let mongoReconnectTimer = null;
let isMongoConnectAttemptInFlight = false;

// WHY: Allow Socket.IO to reuse the same server + port.
const SOCKET_ALLOWED_ORIGIN = process.env.CLIENT_ORIGIN || '*';
const io = new Server(server, {
  cors: {
    origin: SOCKET_ALLOWED_ORIGIN,
    methods: ['GET', 'POST'],
  },
});

// WHY: Register chat socket events after server initialization.
registerChatSocket(io);

// WHY: Draft editor presence uses the same Socket.IO server.
registerDraftPresenceSocket(io);

function scheduleMongoReconnect(reason) {
  if (isDatabaseReady() || mongoReconnectTimer) {
    return;
  }

  debug('Scheduling MongoDB reconnect attempt', {
    reason,
    retryDelayMs: MONGO_RETRY_DELAY_MS,
  });

  mongoReconnectTimer = setTimeout(() => {
    mongoReconnectTimer = null;
    void connectDatabaseInBackground({
      reason: 'scheduled_retry',
    });
  }, MONGO_RETRY_DELAY_MS);

  if (typeof mongoReconnectTimer.unref === 'function') {
    mongoReconnectTimer.unref();
  }
}

async function connectDatabaseInBackground({
  reason = 'startup',
} = {}) {
  if (isDatabaseReady() || isMongoConnectAttemptInFlight) {
    return;
  }

  isMongoConnectAttemptInFlight = true;

  try {
    debug('Initializing database connection', {
      reason,
    });
    await connectDB();
    debug('MongoDB is ready for application traffic', {
      reason,
      databaseStatus: getDatabaseStatus(),
    });
  } catch (error) {
    const retryable =
      isDatabaseConnectivityError(error);

    debug('MongoDB connection attempt failed', {
      reason,
      retryable,
      error,
      databaseStatus: getDatabaseStatus(),
    });

    if (!retryable) {
      console.error('❌ Backend startup failed');
      console.error(error.message);
      process.exit(1);
    }

    console.error(
      `⚠️ MongoDB unavailable; API is running in degraded mode and will retry in ${MONGO_RETRY_DELAY_MS}ms`,
    );
    scheduleMongoReconnect(reason);
  } finally {
    isMongoConnectAttemptInFlight = false;
  }
}

function listenOnPort(port) {
  return new Promise((resolve, reject) => {
    const handleListening = () => {
      server.off('error', handleError);
      resolve();
    };
    const handleError = (error) => {
      server.off('listening', handleListening);
      reject(error);
    };

    server.once('listening', handleListening);
    server.once('error', handleError);
    server.listen(port);
  });
}

function logListenFailure(error) {
  console.error('❌ Backend startup failed');

  if (error?.code !== 'EADDRINUSE') {
    console.error(error.message);
    return;
  }

  const portNumber = Number(PORT);
  const fallbackPort = Number.isFinite(portNumber)
    ? portNumber + 1
    : 4001;

  console.error(`Port ${PORT} is already in use.`);

  if (process.platform === 'win32') {
    console.error(
      'Stop the existing listener with Task Manager or netstat/taskkill, then retry.',
    );
  } else {
    console.error(
      `Find the existing listener with: lsof -nP -iTCP:${PORT} -sTCP:LISTEN`,
    );
  }

  console.error(
    `Or start this backend on another port: PORT=${fallbackPort} npm run dev`,
  );
}

async function startServer() {
  try {
    await listenOnPort(PORT);

    console.log(`🟢 Server running on http://localhost:${PORT}`);
    debug('Server successfully listening');

    // WHY: Background reconciliation keeps expired pre-order holds from blocking capacity.
    startPreorderReconcileWorker();

    void connectDatabaseInBackground();
  } catch (error) {
    logListenFailure(error);
    debug('Backend startup failed before listen', {
      error,
      databaseStatus: getDatabaseStatus(),
    });
    process.exit(1);
  }
}

startServer();
