/**
 * apps/backend/services/password_reset.service.js
 * -----------------------------------------------
 * WHAT:
 * - Handles public forgot-password request and confirmation flows.
 *
 * WHY:
 * - Lets users recover account access without an active session.
 * - Keeps reset-code generation, hashing, expiry, and password updates centralized.
 *
 * HOW:
 * - Request flow validates the email, generates a 6-digit code, stores only a hash,
 *   and sends the code by email with a short expiry window.
 * - Confirm flow validates the code and new password, replaces the password hash,
 *   and clears reset metadata so codes are one-time use.
 */

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const debug = require('../utils/debug');
const User = require('../models/User');
const { sendEmail } = require('./email.service');

// WHY: Password reset codes should expire quickly to reduce attack exposure.
const OTP_TTL_MINUTES = 10;

// WHY: Dev environments may need the code echoed back when no inbox is available.
const SHOW_OTP_IN_RESPONSE = process.env.DEBUG_SHOW_OTP === 'true';

// WHY: Reuse the same auth validation rules used during registration.
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PASSWORD_REGEX =
  /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$/;

function generateOtp() {
  // WHY: Fixed-length numeric codes are easier to type on mobile keyboards.
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function hashCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

function expiryDate() {
  return new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000);
}

function buildGenericRequestResponse(email) {
  return {
    status: 'sent_if_exists',
    email,
    message:
      'If an account exists for that email, a password reset code has been sent.',
  };
}

function buildResetEmailMarkup(code) {
  return {
    text: `Your Office Store password reset code is ${code}. This code expires in ${OTP_TTL_MINUTES} minutes.`,
    html: `
      <p>Your Office Store password reset code is <strong>${code}</strong>.</p>
      <p>This code expires in ${OTP_TTL_MINUTES} minutes.</p>
      <p>If you did not request this reset, you can ignore this email.</p>
    `,
  };
}

async function requestPasswordReset(email) {
  debug('PASSWORD RESET: request start', {
    hasEmail: !!email,
  });

  const normalizedEmail = (email || '').toString().trim().toLowerCase();

  // WHY: Public reset flow still needs basic validation to avoid junk requests.
  if (!normalizedEmail) {
    throw new Error('Email is required');
  }

  if (!EMAIL_REGEX.test(normalizedEmail)) {
    throw new Error('Please provide a valid email address');
  }

  const response = buildGenericRequestResponse(normalizedEmail);

  // WHY: Missing/inactive users must not change the public response shape.
  const user = await User.findOne({ email: normalizedEmail });
  if (!user || user.deletedAt || user.isActive === false) {
    debug('PASSWORD RESET: request completed without eligible user', {
      email: normalizedEmail,
      hasUser: !!user,
      hasDeletedAt: !!user?.deletedAt,
      isActive: user?.isActive ?? null,
    });
    return response;
  }

  const code = generateOtp();
  user.passwordResetCodeHash = hashCode(code);
  user.passwordResetExpiresAt = expiryDate();
  await user.save();

  const emailMarkup = buildResetEmailMarkup(code);

  let deliveryStatus = 'sent';

  try {
    // WHY: Delivery is attempted for real users, but public response stays generic.
    await sendEmail({
      toEmail: user.email,
      subject: 'Reset your Office Store password',
      html: emailMarkup.html,
      text: emailMarkup.text,
    });
  } catch (error) {
    deliveryStatus = 'failed';
    debug('PASSWORD RESET: email delivery failed', {
      userId: user._id,
      email: user.email,
      classification: 'PROVIDER_OUTAGE',
      resolutionHint: 'Check EMAIL_PROVIDER configuration and provider health.',
      error: error.message,
    });
  }

  debug('PASSWORD RESET: request success', {
    userId: user._id,
    email: user.email,
    expiresAt: user.passwordResetExpiresAt,
    deliveryStatus,
  });

  return {
    ...response,
    expiresAt: user.passwordResetExpiresAt,
    code: SHOW_OTP_IN_RESPONSE ? code : undefined,
  };
}

async function confirmPasswordReset({
  email,
  code,
  newPassword,
  confirmPassword,
}) {
  debug('PASSWORD RESET: confirm start', {
    hasEmail: !!email,
    hasCode: !!code,
    hasNewPassword: !!newPassword,
    hasConfirmPassword: !!confirmPassword,
  });

  const normalizedEmail = (email || '').toString().trim().toLowerCase();
  const normalizedCode = (code || '').toString().trim();
  const invalidResetError = new Error('Invalid or expired reset code');

  // WHY: Reset confirmation should reject malformed payloads before DB work.
  if (!normalizedEmail) {
    throw new Error('Email is required');
  }

  if (!EMAIL_REGEX.test(normalizedEmail)) {
    throw new Error('Please provide a valid email address');
  }

  if (!normalizedCode) {
    throw new Error('Reset code is required');
  }

  if (!newPassword || !confirmPassword) {
    throw new Error('New password and confirm password are required');
  }

  if (newPassword !== confirmPassword) {
    throw new Error('Passwords do not match');
  }

  if (!PASSWORD_REGEX.test(newPassword)) {
    throw new Error(
      'Password must be 8+ chars with upper, lower, number, and symbol',
    );
  }

  const user = await User.findOne({ email: normalizedEmail });
  if (!user || user.deletedAt || user.isActive === false) {
    debug('PASSWORD RESET: confirm blocked missing eligible user', {
      email: normalizedEmail,
      hasUser: !!user,
    });
    throw invalidResetError;
  }

  if (!user.passwordResetCodeHash || !user.passwordResetExpiresAt) {
    debug('PASSWORD RESET: confirm blocked missing reset metadata', {
      userId: user._id,
      email: user.email,
    });
    throw invalidResetError;
  }

  if (user.passwordResetExpiresAt < new Date()) {
    // WHY: Expired codes must be cleared so retries require a fresh request.
    user.passwordResetCodeHash = null;
    user.passwordResetExpiresAt = null;
    await user.save();

    debug('PASSWORD RESET: confirm blocked expired code', {
      userId: user._id,
      email: user.email,
    });
    throw invalidResetError;
  }

  if (hashCode(normalizedCode) !== user.passwordResetCodeHash) {
    debug('PASSWORD RESET: confirm blocked invalid code', {
      userId: user._id,
      email: user.email,
    });
    throw invalidResetError;
  }

  // WHY: Password is always stored hashed; raw values never touch Mongo.
  user.passwordHash = await bcrypt.hash(newPassword, 10);
  user.passwordResetCodeHash = null;
  user.passwordResetExpiresAt = null;
  await user.save();

  debug('PASSWORD RESET: confirm success', {
    userId: user._id,
    email: user.email,
  });

  return {
    status: 'reset',
    email: user.email,
    message: 'Password reset successful',
  };
}

module.exports = {
  requestPasswordReset,
  confirmPasswordReset,
};
