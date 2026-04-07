/**
 * apps/backend/services/auth.service.js
 * Clean, explicit, zero magic
 */

const bcrypt = require('bcryptjs');
const debug = require('../utils/debug');
const User = require('../models/User');
const BusinessStaffProfile = require('../models/BusinessStaffProfile');
const USER_ROLES = User.USER_ROLES;
const { signToken } = require('../config/jwt');

// WHY: Basic validation rules keep registration consistent and secure.
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PASSWORD_REGEX =
  /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$/;
const LOGIN_ACCOUNT_ROLE_ALIASES = {
  admin: 'admin',
  user: 'customer',
  customer: 'customer',
  business_owner: 'business_owner',
  tenant: 'tenant',
  staff: 'staff',
};



async function registerUser({
  firstName,
  lastName,
  name,
  email,
  password,
  confirmPassword,
  role,
}) {
  debug('================ REGISTER FLOW START ================');

  // 1️⃣ Validate input
  if (!email || !password || !confirmPassword) {
    throw new Error('First name, last name, email, and passwords are required');
  }

  const normalizedEmail = email.toLowerCase().trim();
  const cleanFirstName =
    typeof firstName === 'string' ? firstName.trim() : '';
  const cleanLastName =
    typeof lastName === 'string' ? lastName.trim() : '';
  const fallbackName = typeof name === 'string' ? name.trim() : '';
  const finalName =
    cleanFirstName && cleanLastName
      ? `${cleanFirstName} ${cleanLastName}`
      : fallbackName;
  const finalRole = role && USER_ROLES.includes(role) ? role : 'customer';

  if (!cleanFirstName || !cleanLastName) {
    throw new Error('First name and last name are required');
  }

  if (!EMAIL_REGEX.test(normalizedEmail)) {
    throw new Error('Please provide a valid email address');
  }

  if (password !== confirmPassword) {
    throw new Error('Passwords do not match');
  }

  if (!PASSWORD_REGEX.test(password)) {
    throw new Error(
      'Password must be 8+ chars with upper, lower, number, and symbol',
    );
  }

  debug('Incoming payload:', {
    name: finalName,
    firstName: cleanFirstName,
    lastName: cleanLastName,
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
    // WHY: Store split names for profile editing UI.
    firstName: cleanFirstName,
    lastName: cleanLastName,
    email: normalizedEmail,
    passwordHash,
    role: finalRole,
  };

  debug('Mongo payload (FINAL):', {
    name: mongoPayload.name,
    firstName: mongoPayload.firstName,
    lastName: mongoPayload.lastName,
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

function normalizeLoginAccountRole(role) {
  const normalizedRole =
    typeof role === 'string' ? role.trim().toLowerCase() : '';
  return LOGIN_ACCOUNT_ROLE_ALIASES[normalizedRole] || null;
}

function humanizeLabel(value) {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (!trimmed) {
    return '';
  }

  return trimmed
    .split('_')
    .filter(Boolean)
    .map((segment) => segment[0].toUpperCase() + segment.slice(1))
    .join(' ');
}

function buildUserDisplayName(user) {
  const structuredName = [
    user.firstName,
    user.middleName,
    user.lastName,
  ]
    .map((value) => (typeof value === 'string' ? value.trim() : ''))
    .filter(Boolean)
    .join(' ')
    .trim();

  if (structuredName) {
    return structuredName;
  }

  const fallbackName =
    typeof user.name === 'string' ? user.name.trim() : '';
  if (fallbackName) {
    return fallbackName;
  }

  return typeof user.email === 'string' ? user.email.trim() : 'Unknown user';
}

function buildAccountSubtitle({ role, user, staffProfile }) {
  if (role === 'admin') {
    const companyName =
      typeof user.companyName === 'string' ? user.companyName.trim() : '';
    return companyName || 'Platform admin';
  }

  if (role === 'business_owner') {
    const companyName =
      typeof user.companyName === 'string' ? user.companyName.trim() : '';
    return companyName || 'Business owner';
  }

  if (role === 'tenant') {
    const companyName =
      typeof user.companyName === 'string' ? user.companyName.trim() : '';
    return companyName || 'Tenant account';
  }

  if (role === 'staff') {
    const parts = [];
    const staffRole = humanizeLabel(staffProfile?.staffRole);
    const companyName =
      typeof user.companyName === 'string' ? user.companyName.trim() : '';

    if (staffRole) {
      parts.push(staffRole);
    }
    if (companyName) {
      parts.push(companyName);
    }

    return parts.join(' • ') || 'Staff account';
  }

  const accountType = humanizeLabel(user.accountType);
  return accountType || 'Customer account';
}

function buildAddressLine(address) {
  if (!address || typeof address !== 'object') {
    return '';
  }

  const formattedAddress =
    typeof address.formattedAddress === 'string'
      ? address.formattedAddress.trim()
      : '';
  if (formattedAddress) {
    return formattedAddress;
  }

  const parts = [
    address.houseNumber,
    address.street,
    address.landmark,
    address.city,
    address.state,
    address.postalCode,
    address.country,
  ]
    .map((value) => (typeof value === 'string' ? value.trim() : ''))
    .filter(Boolean);

  return parts.join(', ');
}

function buildAccountAddress({ role, user }) {
  const candidates =
    role === 'business_owner'
      ? [user.companyAddress, user.businessRegisteredAddress, user.homeAddress]
      : [user.homeAddress, user.companyAddress, user.businessRegisteredAddress];

  for (const address of candidates) {
    const addressLine = buildAddressLine(address);
    if (addressLine) {
      return addressLine;
    }
  }

  return '';
}

async function listLoginAccounts(role) {
  const normalizedRole = normalizeLoginAccountRole(role);
  if (!normalizedRole) {
    throw new Error('Unsupported login account role');
  }

  const users = await User.find({
    role: normalizedRole,
    isActive: true,
  })
    .sort({
      createdAt: 1,
      firstName: 1,
      lastName: 1,
      email: 1,
    })
    .select(
      [
        '_id',
        'name',
        'firstName',
        'middleName',
        'lastName',
        'email',
        'role',
        'companyName',
        'accountType',
        'homeAddress',
        'companyAddress',
        'businessRegisteredAddress',
        'isEmailVerified',
        'isPhoneVerified',
        'isNinVerified',
      ].join(' '),
    )
    .lean();

  let staffProfilesByUserId = new Map();
  if (normalizedRole === 'staff' && users.length > 0) {
    const staffProfiles = await BusinessStaffProfile.find({
      userId: { $in: users.map((user) => user._id) },
      status: 'active',
    })
      .sort({ createdAt: 1 })
      .select('userId staffRole')
      .lean();

    staffProfilesByUserId = new Map(
      staffProfiles.map((profile) => [String(profile.userId), profile]),
    );
  }

  const accounts = users.map((user) => ({
    id: String(user._id),
    fullName: buildUserDisplayName(user),
    email: user.email,
    role: user.role,
    isEmailVerified: user.isEmailVerified === true,
    isPhoneVerified: user.isPhoneVerified === true,
    isNinVerified: user.isNinVerified === true,
    staffRole: staffProfilesByUserId.get(String(user._id))?.staffRole || null,
    subtitle: buildAccountSubtitle({
      role: normalizedRole,
      user,
      staffProfile: staffProfilesByUserId.get(String(user._id)),
    }),
    addressLabel: buildAccountAddress({ role: normalizedRole, user }),
  }));

  return {
    message: 'Login accounts fetched successfully',
    role: normalizedRole,
    accounts,
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
  listLoginAccounts,
  loginUser, // ✅ MUST exist and MUST be exported
};
