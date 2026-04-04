/**
 * apps/backend/services/nin_verification.service.js
 * --------------------------------------------------
 * WHAT:
 * - Simulated NIN verification service (dev only).
 *
 * WHY:
 * - Enable backend-only NIN verification now, while Dojah is pending.
 * - Store only hash + last4 for audits (no raw NIN persisted).
 *
 * HOW:
 * - Compare input NIN to a configured test NIN from env.
 * - On success, fill profile fields from env-provided test data.
 */

const crypto = require('crypto');
const debug = require('../utils/debug');
const User = require('../models/User');

// WHY: Keep NIN test data in env to avoid hardcoding sensitive values.
const TEST_NIN = (process.env.NIN_TEST_VALUE || '').trim();
const TEST_FIRST_NAME = (process.env.NIN_TEST_FIRST_NAME || '').trim();
const TEST_LAST_NAME = (process.env.NIN_TEST_LAST_NAME || '').trim();
const TEST_MIDDLE_NAME = (process.env.NIN_TEST_MIDDLE_NAME || '').trim();
const TEST_DOB = (process.env.NIN_TEST_DOB || '').trim();

function hashValue(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function last4(value) {
  const cleaned = value.replace(/\s+/g, '');
  return cleaned.length >= 4 ? cleaned.slice(-4) : cleaned;
}

async function verifyNinForUser(userId, nin) {
  debug('NIN VERIFY: request', { userId });

  if (!userId) {
    throw new Error('Missing userId');
  }

  if (!nin || typeof nin !== 'string') {
    throw new Error('NIN is required');
  }

  const trimmed = nin.trim();
  const ninLast4 = last4(trimmed);

  debug('NIN VERIFY: input received', {
    userId,
    length: trimmed.length,
    last4: ninLast4,
  });

  if (!/^\d{11}$/.test(trimmed)) {
    throw new Error('NIN must be 11 digits');
  }

  if (!TEST_NIN) {
    throw new Error('NIN test value is not configured');
  }

  const testLast4 = last4(TEST_NIN);
  debug('NIN VERIFY: test config', {
    testConfigured: true,
    testLast4,
  });

  if (trimmed !== TEST_NIN) {
    debug('NIN VERIFY: mismatch', {
      inputLast4: ninLast4,
      testLast4,
    });
    throw new Error('NIN verification failed');
  }

  const user = await User.findById(userId).select('-passwordHash');
  if (!user) {
    throw new Error('User not found');
  }

  if (!user.isEmailVerified || !user.isPhoneVerified) {
    debug('NIN VERIFY: blocked (missing contact verification)', {
      userId,
      isEmailVerified: !!user.isEmailVerified,
      isPhoneVerified: !!user.isPhoneVerified,
    });
    throw new Error('Email and phone must be verified first');
  }

  const safeFirstName = TEST_FIRST_NAME || user.firstName || '';
  const safeLastName = TEST_LAST_NAME || user.lastName || '';
  const safeMiddleName = TEST_MIDDLE_NAME || user.middleName || '';
  const safeDob = TEST_DOB || user.dob || '';

  const fullName = [safeFirstName, safeMiddleName, safeLastName]
    .filter(Boolean)
    .join(' ')
    .trim();

  user.firstName = safeFirstName || user.firstName;
  user.lastName = safeLastName || user.lastName;
  user.middleName = safeMiddleName || user.middleName;
  user.dob = safeDob || user.dob;
  user.name = fullName || user.name;
  user.isNinVerified = true;
  user.ninHash = hashValue(trimmed);
  user.ninLast4 = ninLast4;

  await user.save();

  debug('NIN VERIFY: success', { userId });

  return {
    status: 'verified',
    isNinVerified: true,
    ninLast4: user.ninLast4,
  };
}

module.exports = {
  verifyNinForUser,
};
