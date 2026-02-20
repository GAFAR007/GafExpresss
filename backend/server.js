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
require('dotenv').config();

// --------------------------------------------------
// IMPORTS
// --------------------------------------------------
const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const debug = require('./utils/debug');
const connectDB = require('./config/db');
const registerRoutes = require('./routes');
const swaggerUi = require('swagger-ui-express');
const swaggerSpec = require('./config/swagger');
const { registerChatSocket } = require('./services/chat_socket.service');
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
 * DATABASE CONNECTION
 * --------------------------------------------------
 * NOTE:
 * - Establishes MongoDB connection at startup
 * - App will EXIT if connection fails
 */
debug('Initializing database connection');
connectDB();

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

server.listen(PORT, () => {
  console.log(`🟢 Server running on http://localhost:${PORT}`);
  debug('Server successfully listening');

  // WHY: Background reconciliation keeps expired pre-order holds from blocking capacity.
  const workerState =
    startPreorderReconcileWorker();
  debug(
    'Pre-order reconcile worker boot status',
    workerState,
  );
});
