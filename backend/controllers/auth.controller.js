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
const {
  getUserProfile,
  updateUserProfile,
} = require('../services/profile.service');


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
    const { firstName, lastName, name, email, password, confirmPassword, role } =
      req.body;

    // ✅ Basic guard (controller-level)
    if (!firstName || !lastName || !email || !password || !confirmPassword) {
      debug('Register failed: missing required fields');
      return res.status(400).json({
        error: 'First name, last name, email, and passwords are required',
      });
    }

    debug('Register payload normalized preview:', {
      name,
      firstName,
      lastName,
      email,
      role,
      passwordLength: password?.length,
    });

    // ✅ Call service
    const user = await registerUser({
      firstName,
      lastName,
      name,
      email,
      password,
      confirmPassword,
      role,
    });

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


/* =========================
   LOGIN — FULL TRACE
========================= */
async function login(req, res) {
  try {
    debug('================ LOGIN CONTROLLER START ================');

    // 1️⃣ What Express received
    debug('req.body:', req.body);
    debug('typeof req.body:', typeof req.body);

    // 2️⃣ What functions exist in service
    debug('authService keys:', Object.keys(authService));
    debug('typeof authService.loginUser:', typeof authService.loginUser);

    // 3️⃣ Build payload explicitly
    const payload = {
      email: req.body.email,
      password: req.body.password,
    };

    debug('Payload sent to service:', payload);

    // 4️⃣ Call service
    // Returns: { token, user }
    const session = await authService.loginUser(payload);

    debug('Service returned user:', session?.user);
    debug('================ LOGIN CONTROLLER END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Login successful',
      token: session?.token,
      user: session?.user,
    });
  } catch (err) {
    debug('================ LOGIN CONTROLLER ERROR ================');
    debug('Error message:', err.message);
    debug('Error stack:', err.stack);

    return res.status(401).json({
      error: err.message,
    });
  }
}

/* =========================
   PROFILE — FETCH/UPDATE
========================= */
async function getProfile(req, res) {
  try {
    debug('================ PROFILE CONTROLLER START ================');
    debug('Profile request userId:', req.user?.sub);

    const profile = await getUserProfile(req.user?.sub);

    debug('Profile fetch success', {
      userId: profile.id,
      accountType: profile.accountType,
    });
    debug('================ PROFILE CONTROLLER END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Profile fetched',
      profile,
    });
  } catch (err) {
    debug('================ PROFILE CONTROLLER END (ERROR) ================');
    debug('Profile fetch error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

async function updateProfile(req, res) {
  try {
    debug('================ PROFILE UPDATE START ================');
    debug('Profile update userId:', req.user?.sub);
    debug('Profile update payload keys:', Object.keys(req.body || {}));

    const profile = await updateUserProfile(req.user?.sub, req.body);

    debug('Profile update success', {
      userId: profile.id,
      accountType: profile.accountType,
    });
    debug('================ PROFILE UPDATE END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Profile updated',
      profile,
    });
  } catch (err) {
    debug('================ PROFILE UPDATE END (ERROR) ================');
    debug('Profile update error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

module.exports = {
  register,
  login,
  getProfile,
  updateProfile,
};
