/**
 * apps/backend/services/auth.service.js
 * Clean, explicit, zero magic
 */

const bcrypt = require('bcryptjs');
const debug = require('../utils/debug');
const User = require('../models/User');
const USER_ROLES = User.USER_ROLES;
const { signToken } = require('../config/jwt');




async function registerUser({ name, email, password, role }) {
  debug('================ REGISTER FLOW START ================');

  // 1️⃣ Validate input
  if (!email || !password) {
    throw new Error('Email and password are required');
  }

  const normalizedEmail = email.toLowerCase().trim();
  const finalName = typeof name === 'string' ? name.trim() : '';
  const finalRole = role && USER_ROLES.includes(role) ? role : 'customer';

  debug('Incoming payload:', {
    name: finalName,
    email: normalizedEmail,
    password: '[RAW]',
    role: finalRole,
  });

  // 2️⃣ Check duplicate
  const existing = await User.findOne({ email: normalizedEmail });
  debug('Existing user:', !!existing);

  if (existing) {
    throw new Error('Email already registered');
  }

  // 3️⃣ Hash password
  const passwordHash = await bcrypt.hash(password, 10);
  debug('Password hashed');

  // 4️⃣ Build user object (THIS IS WHAT GOES TO MONGO)
  const mongoPayload = {
    name: finalName,
    email: normalizedEmail,
    passwordHash,
    role: finalRole,
  };

  debug('Mongo payload (FINAL):', {
    name: mongoPayload.name,
    email: mongoPayload.email,
    passwordHash: '[HASHED]',
    role: mongoPayload.role,
  });

  // 5️⃣ Save
  const user = new User(mongoPayload);
  const savedUser = await user.save();

  debug('Saved user document:', {
    id: savedUser._id,
    name: savedUser.name,
    email: savedUser.email,
    role: savedUser.role,
  });

  debug('================ REGISTER FLOW END ==================');

  return {
    id: savedUser._id,
    name: savedUser.name,
    email: savedUser.email,
    role: savedUser.role,
  };
}

/* =====================================================
   LOGIN USER  ✅ THIS WAS THE BROKEN PART
===================================================== */
async function loginUser(payload) {
  debug('================ LOGIN SERVICE START ================');

  debug('Payload received:', payload);
  debug('Payload type:', typeof payload);

  const { email, password } = payload;

  debug('email:', email);
  debug('password exists:', !!password);

  if (!email || !password) {
    throw new Error('Email and password are required');
  }

  const normalizedEmail = email.toLowerCase().trim();
  debug('Normalized email:', normalizedEmail);

  // Mongo lookup
  const user = await User.findOne({ email: normalizedEmail });
  debug('Mongo user found:', !!user);

  if (!user) {
    throw new Error('Invalid email or password');
  }

  debug('User from DB:', {
    id: user._id,
    email: user.email,
    role: user.role,
    passwordHashExists: !!user.passwordHash,
  });

  // Password check
  const isMatch = await bcrypt.compare(password, user.passwordHash);
  debug('Password match result:', isMatch);

  if (!isMatch) {
    throw new Error('Invalid email or password');
  }

  debug('================ LOGIN SERVICE END (SUCCESS) ================');

const token = signToken({
  id: user._id,
  role: user.role,
});
debug('token:', token);
return {
  token,
  user: {
    id: user._id,
    name: user.name,
    email: user.email,
    role: user.role,
  },
};
}


/* =====================================================
   EXPORTS  🚨 THIS IS WHERE YOUR BUG WAS
===================================================== */
module.exports = {
  registerUser,
  loginUser, // ✅ MUST exist and MUST be exported
};