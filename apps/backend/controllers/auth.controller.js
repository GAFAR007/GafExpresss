/**
 * apps/backend/controllers/auth.controller.js
 * ------------------------------------------
 * WHAT:
 * - Receives HTTP requests for auth (register/login)
 *
 * HOW:
 * - Validates required fields
 * - Calls service layer
 * - Returns clean responses (no raw stack traces)
 *
 * WHY:
 * - Keeps routing thin and service testable
 */

const debug = require('../utils/debug');
const {
  registerUser,
  loginUser,
} = require('../services/auth.service');
const authService = require('../services/auth.service');


/**
 * POST /auth/register
 * Body: { name, email, password, role }
 */
async function register(req, res) {
  // ✅ Debug entry
  debug('================ REGISTER CONTROLLER START ================');
  debug('AuthController.register -> request received');
  debug('Request headers content-type:', req.headers['content-type']);
  debug('Request body received:', req.body);

  try {
    const { name, email, password, role } = req.body;

    // ✅ Basic guard (controller-level)
    if (!email || !password) {
      debug('Register failed: missing email or password');
      return res.status(400).json({
        error: 'Email and password are required',
      });
    }

    debug('Register payload normalized preview:', {
      name,
      email,
      role,
      passwordLength: password?.length,
    });

    // ✅ Call service
    const user = await registerUser({ name, email, password, role });

    debug('Register success -> returning response:', {
      id: user.id,
      email: user.email,
      role: user.role,
    });

    debug('================ REGISTER CONTROLLER END (SUCCESS) ================');
    return res.status(201).json({
      message: 'User registered successfully',
      user,
    });
  } catch (err) {
    /**
     * 🔥 IMPORTANT:
     * We log the FULL error object so we can see:
     * - Mongo duplicate error code (E11000)
     * - validation errors
     * - which field failed
     */
    debug('================ REGISTER CONTROLLER END (ERROR) ================');
    debug('Register error FULL:', err);
    debug('Register error message:', err?.message);
    debug('Register error name:', err?.name);
    debug('Register error code:', err?.code);
    debug('Register error keyValue:', err?.keyValue);
    debug('Register error errors:', err?.errors);

    // ✅ Choose good status code
    const status =
      err?.code === 11000 ? 409 : // duplicate key
      err?.name === 'ValidationError' ? 400 :
      400;

    return res.status(status).json({
      error: err?.message || 'Registration failed',
      meta: {
        name: err?.name,
        code: err?.code,
        keyValue: err?.keyValue,
      },
    });
  }
}


/**
 * LOGIN
 * POST /auth/login
 */
async function login(req, res) {
  try {
    debug('LOGIN CONTROLLER START');
    debug('req.body:', req.body);

    const result = await authService.loginUser(req.body);

    debug('LOGIN CONTROLLER SUCCESS');

    return res.status(200).json(result);
  } catch (err) {
    debug('LOGIN CONTROLLER ERROR:', err.message);

    return res.status(401).json({
      error: err.message,
    });
  }
}
module.exports = {
  register,
  login,
};
