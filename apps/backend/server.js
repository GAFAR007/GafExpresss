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

const debug = require('./utils/debug');
const connectDB = require('./config/db');
const registerRoutes = require('./routes');
const swaggerUi = require('swagger-ui-express');
const swaggerSpec = require('./config/swagger');

/**
 * --------------------------------------------------
 * CREATE EXPRESS APP
 * --------------------------------------------------
 */
debug('Creating Express app instance');
const app = express();

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

app.listen(PORT, () => {
  console.log(`🟢 Server running on http://localhost:${PORT}`);
  debug('Server successfully listening');
});
