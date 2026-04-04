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
const {
  requestEmailVerification,
  confirmEmailVerification,
  requestPhoneVerification,
  confirmPhoneVerification,
} = require('../services/verification.service');
const {
  requestPasswordReset,
  confirmPasswordReset,
} = require('../services/password_reset.service');
const { verifyNinForUser } = require('../services/nin_verification.service');
const { verifyUserAddress } = require('../services/address_verification.service');
const { verifyBusinessForUser } = require('../services/business_verification.service');
const { uploadProfileImage } = require('../services/profile_image.service');
const {
  fetchAddressSuggestions,
  fetchPlaceDetails,
} = require('../services/address_autocomplete.service');
const connectDB = require('../config/db');
const { isDatabaseConnectivityError } = connectDB;

// WHY: Login should distinguish invalid credentials from infrastructure outages.
function getLoginErrorResponse(error) {
  if (isDatabaseConnectivityError(error)) {
    return {
      status: 503,
      body: {
        error: 'Authentication temporarily unavailable',
        resolutionHint: 'Restore MongoDB connectivity and retry the request.',
      },
    };
  }

  return {
    status: 401,
    body: {
      error: error.message,
    },
  };
}


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
    debug('Login error classified as database outage:', isDatabaseConnectivityError(err));

    const errorResponse = getLoginErrorResponse(err);

    return res.status(errorResponse.status).json(errorResponse.body);
  }
}

/* =========================
   PASSWORD RESET — PUBLIC
========================= */
async function requestPasswordResetController(req, res) {
  try {
    debug('================ PASSWORD RESET REQUEST START ================');

    // WHY: Public flow only needs the email address from the request body.
    const { email } = req.body || {};
    const result = await requestPasswordReset(email);

    debug('Password reset request success', {
      email: result.email,
      status: result.status,
    });
    debug(
      '================ PASSWORD RESET REQUEST END (SUCCESS) ================',
    );

    return res.status(200).json({
      message: result.message,
      ...result,
    });
  } catch (err) {
    debug('================ PASSWORD RESET REQUEST END (ERROR) ================');
    debug('Password reset request error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

async function confirmPasswordResetController(req, res) {
  try {
    debug('================ PASSWORD RESET CONFIRM START ================');

    // WHY: Public confirmation flow requires email + code + new password fields.
    const { email, code, newPassword, confirmPassword } = req.body || {};
    const result = await confirmPasswordReset({
      email,
      code,
      newPassword,
      confirmPassword,
    });

    debug('Password reset confirm success', {
      email: result.email,
      status: result.status,
    });
    debug(
      '================ PASSWORD RESET CONFIRM END (SUCCESS) ================',
    );

    return res.status(200).json({
      message: result.message,
      ...result,
    });
  } catch (err) {
    debug('================ PASSWORD RESET CONFIRM END (ERROR) ================');
    debug('Password reset confirm error message:', err.message);

    return res.status(400).json({
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

/* =========================
   VERIFICATION — EMAIL/PHONE
========================= */
async function requestEmailVerificationController(req, res) {
  try {
    debug('================ EMAIL VERIFY REQUEST START ================');
    debug('Email verify request userId:', req.user?.sub);

    const { email } = req.body || {};
    // WHY: Allow frontend to verify a newly edited email without a full save.
    if (email) {
      debug('Email verify request override:', {
        userId: req.user?.sub,
        email,
      });
    }
    const result = await requestEmailVerification(req.user?.sub, email);

    debug('Email verify request success', {
      userId: req.user?.sub,
      status: result.status,
    });
    debug('================ EMAIL VERIFY REQUEST END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Email verification sent',
      ...result,
    });
  } catch (err) {
    debug('================ EMAIL VERIFY REQUEST END (ERROR) ================');
    debug('Email verify request error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

async function confirmEmailVerificationController(req, res) {
  try {
    debug('================ EMAIL VERIFY CONFIRM START ================');
    debug('Email verify confirm userId:', req.user?.sub);

    const { code } = req.body || {};
    const result = await confirmEmailVerification(req.user?.sub, code);

    debug('Email verify confirm success', {
      userId: req.user?.sub,
      status: result.status,
    });
    debug('================ EMAIL VERIFY CONFIRM END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Email verified',
      ...result,
    });
  } catch (err) {
    debug('================ EMAIL VERIFY CONFIRM END (ERROR) ================');
    debug('Email verify confirm error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

async function requestPhoneVerificationController(req, res) {
  try {
    debug('================ PHONE VERIFY REQUEST START ================');
    debug('Phone verify request userId:', req.user?.sub);

    const { phone } = req.body || {};
    const result = await requestPhoneVerification(req.user?.sub, phone);

    debug('Phone verify request success', {
      userId: req.user?.sub,
      status: result.status,
    });
    debug('================ PHONE VERIFY REQUEST END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Phone verification sent',
      ...result,
    });
  } catch (err) {
    debug('================ PHONE VERIFY REQUEST END (ERROR) ================');
    debug('Phone verify request error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

async function confirmPhoneVerificationController(req, res) {
  try {
    debug('================ PHONE VERIFY CONFIRM START ================');
    debug('Phone verify confirm userId:', req.user?.sub);

    const { code } = req.body || {};
    const result = await confirmPhoneVerification(req.user?.sub, code);

    debug('Phone verify confirm success', {
      userId: req.user?.sub,
      status: result.status,
    });
    debug('================ PHONE VERIFY CONFIRM END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Phone verified',
      ...result,
    });
  } catch (err) {
    debug('================ PHONE VERIFY CONFIRM END (ERROR) ================');
    debug('Phone verify confirm error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/* =========================
   VERIFICATION — NIN (SIM)
========================= */
async function verifyNinController(req, res) {
  try {
    debug('================ NIN VERIFY START ================');
    debug('NIN verify request userId:', req.user?.sub);

    const { nin } = req.body || {};
    const result = await verifyNinForUser(req.user?.sub, nin);

    debug('NIN verify success', {
      userId: req.user?.sub,
      status: result.status,
    });
    debug('================ NIN VERIFY END (SUCCESS) ================');

    return res.status(200).json({
      message: 'NIN verified',
      ...result,
    });
  } catch (err) {
    debug('================ NIN VERIFY END (ERROR) ================');
    debug('NIN verify error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/* =========================
   VERIFICATION — BUSINESS (DOJAH)
========================= */
async function verifyBusinessController(req, res) {
  try {
    debug('================ BUSINESS VERIFY START ================');
    debug('Business verify request userId:', req.user?.sub);

    const { accountType, registrationNumber, registrationType } = req.body || {};
    const result = await verifyBusinessForUser({
      userId: req.user?.sub,
      accountType,
      registrationNumber,
      registrationType,
    });

    debug('Business verify success', {
      userId: req.user?.sub,
      status: result.status,
    });
    debug('================ BUSINESS VERIFY END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Business verified',
      ...result,
    });
  } catch (err) {
    debug('================ BUSINESS VERIFY END (ERROR) ================');
    debug('Business verify error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/* =========================
   PROFILE IMAGE UPLOAD
========================= */
async function uploadProfileImageController(req, res) {
  try {
    debug('================ PROFILE IMAGE UPLOAD START ================');
    debug('Profile image upload userId:', req.user?.sub);

    const result = await uploadProfileImage({
      userId: req.user?.sub,
      file: req.file,
    });

    debug('Profile image upload success', {
      userId: req.user?.sub,
    });
    debug('================ PROFILE IMAGE UPLOAD END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Profile image updated',
      ...result,
    });
  } catch (err) {
    debug('================ PROFILE IMAGE UPLOAD END (ERROR) ================');
    debug('Profile image upload error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/* =========================
   ADDRESS VERIFY (GOOGLE)
========================= */
async function verifyAddressController(req, res) {
  try {
    debug('================ ADDRESS VERIFY START ================');
    debug('Address verify request userId:', req.user?.sub);

    const { type, address, placeId } = req.body || {};

    const result = await verifyUserAddress({
      userId: req.user?.sub,
      type,
      address,
      placeId,
    });

    const profile = await getUserProfile(req.user?.sub);

    debug('Address verify success', {
      userId: req.user?.sub,
      type,
      status: result.status,
    });
    debug('================ ADDRESS VERIFY END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Address verification complete',
      ...result,
      profile,
    });
  } catch (err) {
    debug('================ ADDRESS VERIFY END (ERROR) ================');
    debug('Address verify error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/* =========================
   ADDRESS AUTOCOMPLETE
========================= */
async function addressAutocomplete(req, res) {
  try {
    debug('================ ADDRESS AUTOCOMPLETE START ================');
    debug('Address autocomplete userId:', req.user?.sub);

    const query = (req.query?.query || '').toString().trim();
    if (query.length < 3) {
      return res.status(400).json({
        error: 'Query must be at least 3 characters',
      });
    }

    const suggestions = await fetchAddressSuggestions(query);

    debug('Address autocomplete success', {
      count: suggestions.length,
    });
    debug('================ ADDRESS AUTOCOMPLETE END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Address suggestions fetched',
      suggestions,
    });
  } catch (err) {
    debug('================ ADDRESS AUTOCOMPLETE END (ERROR) ================');
    debug('Address autocomplete error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/* =========================
   ADDRESS PLACE DETAILS
========================= */
async function addressPlaceDetails(req, res) {
  try {
    debug('================ ADDRESS PLACE DETAILS START ================');
    debug('Address place details userId:', req.user?.sub);

    const placeId = (req.query?.placeId || '').toString().trim();
    if (!placeId) {
      return res.status(400).json({
        error: 'placeId is required',
      });
    }

    const address = await fetchPlaceDetails(placeId);

    debug('Address place details success', { hasStreet: !!address?.street });
    debug('================ ADDRESS PLACE DETAILS END (SUCCESS) ================');

    return res.status(200).json({
      message: 'Place details fetched',
      address,
    });
  } catch (err) {
    debug('================ ADDRESS PLACE DETAILS END (ERROR) ================');
    debug('Address place details error message:', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

module.exports = {
  register,
  login,
  requestPasswordReset: requestPasswordResetController,
  confirmPasswordReset: confirmPasswordResetController,
  getProfile,
  updateProfile,
  requestEmailVerification: requestEmailVerificationController,
  confirmEmailVerification: confirmEmailVerificationController,
  requestPhoneVerification: requestPhoneVerificationController,
  confirmPhoneVerification: confirmPhoneVerificationController,
  verifyNin: verifyNinController,
  verifyBusiness: verifyBusinessController,
  verifyAddress: verifyAddressController,
  uploadProfileImage: uploadProfileImageController,
  addressAutocomplete,
  addressPlaceDetails,
};
