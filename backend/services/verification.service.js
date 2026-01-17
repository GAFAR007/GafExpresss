/**
 * apps/backend/services/verification.service.js
 * ---------------------------------------------
 * WHAT:
 * - Handles email + phone verification workflows.
 *
 * WHY:
 * - Centralizes OTP generation, hashing, and expiry rules.
 * - Keeps controllers thin and consistent.
 *
 * HOW:
 * - Generates a 6-digit code.
 * - Stores only a hashed version + expiry timestamps.
 * - Marks email/phone as verified on successful confirmation.
 */

const crypto = require('crypto');
const http = require('http');
const https = require('https');
const { URL } = require('url');
const debug = require('../utils/debug');
const User = require('../models/User');

// WHY: OTP should expire quickly to reduce attack window.
const OTP_TTL_MINUTES = 10;

// WHY: Allow safe dev testing without real providers.
const SHOW_OTP_IN_RESPONSE = process.env.DEBUG_SHOW_OTP === 'true';

// WHY: Separate providers allow email/SMS to be configured independently.
const EMAIL_PROVIDER = process.env.EMAIL_PROVIDER || 'console';
const SMS_PROVIDER = process.env.SMS_PROVIDER || 'console';

// WHY: Brevo HTTP API is a low-cost option that scales well.
const BREVO_API_KEY = process.env.BREVO_API_KEY;
const EMAIL_FROM = process.env.EMAIL_FROM;
const EMAIL_FROM_NAME = process.env.EMAIL_FROM_NAME || 'Office Store';

// WHY: Termii is Nigeria-friendly for SMS/OTP delivery.
const TERMII_API_KEY = process.env.TERMII_API_KEY;
const TERMII_SENDER_ID = process.env.TERMII_SENDER_ID || 'OfficeStore';
const TERMII_CHANNEL = process.env.TERMII_CHANNEL || 'generic';
const TERMII_MESSAGE_PREFIX =
  process.env.TERMII_MESSAGE_PREFIX || 'Your verification code is';

// WHY: Enforce strict Nigerian phone formatting across all flows.
const PHONE_NG_E164_REGEX = /^\+234\d{10}$/;
const PHONE_NG_LOCAL_REGEX = /^0\d{10}$/;
const PHONE_NG_PLAIN_REGEX = /^234\d{10}$/;

function generateOtp() {
  // WHY: Fixed-length numeric code is easy to enter on mobile.
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function hashCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

function expiryDate() {
  return new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000);
}

// WHY: Centralize HTTP POST handling for external providers.
function postJson(urlString, headers, body) {
  const url = new URL(urlString);
  const payload = JSON.stringify(body);
  const client = url.protocol === 'https:' ? https : http;

  return new Promise((resolve, reject) => {
    const request = client.request(
      {
        method: 'POST',
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
          ...headers,
        },
        timeout: 10000,
      },
      (response) => {
        let data = '';
        response.on('data', (chunk) => {
          data += chunk;
        });
        response.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            resolve({ status: response.statusCode || 0, data: parsed });
          } catch (err) {
            resolve({ status: response.statusCode || 0, data: data || null });
          }
        });
      },
    );

    request.on('error', reject);
    request.on('timeout', () => {
      request.destroy(new Error('Request timeout'));
    });

    request.write(payload);
    request.end();
  });
}

// WHY: Normalize Nigerian phone input to E.164 for consistent SMS delivery.
function normalizeNigerianPhone(value) {
  const raw = (value || '').toString().replace(/\s+/g, '').trim();

  if (PHONE_NG_E164_REGEX.test(raw)) return raw;
  if (PHONE_NG_LOCAL_REGEX.test(raw)) return `+234${raw.slice(1)}`;
  if (PHONE_NG_PLAIN_REGEX.test(raw)) return `+${raw}`;

  return null;
}

async function sendEmailCode({ email, code }) {
  if (EMAIL_PROVIDER === 'console') {
    // WHY: Avoid external dependencies in dev, but keep visibility.
    debug('EMAIL VERIFY (DEV): sending code', {
      email,
      codeLength: code.length,
    });
    return;
  }

  if (EMAIL_PROVIDER === 'brevo') {
    if (!BREVO_API_KEY || !EMAIL_FROM) {
      throw new Error('Brevo email provider missing configuration');
    }

    const payload = {
      sender: {
        name: EMAIL_FROM_NAME,
        email: EMAIL_FROM,
      },
      to: [{ email }],
      subject: 'Verify your email',
      htmlContent: `
        <p>Your verification code is <strong>${code}</strong>.</p>
        <p>This code expires in ${OTP_TTL_MINUTES} minutes.</p>
      `,
    };

    const { status } = await postJson(
      'https://api.brevo.com/v3/smtp/email',
      { 'api-key': BREVO_API_KEY },
      payload,
    );

    debug('EMAIL VERIFY: Brevo status', { status });

    if (status < 200 || status >= 300) {
      throw new Error('Email delivery failed');
    }

    return;
  }

  // WHY: Fail explicitly until a real provider is configured.
  throw new Error('Email provider not configured');
}

async function sendPhoneCode({ phone, code }) {
  if (SMS_PROVIDER === 'console') {
    debug('PHONE OTP (DEV): sending code', {
      phone,
      codeLength: code.length,
    });
    return;
  }

  if (SMS_PROVIDER === 'termii') {
    if (!TERMII_API_KEY || !TERMII_SENDER_ID) {
      throw new Error('Termii SMS provider missing configuration');
    }

    const payload = {
      api_key: TERMII_API_KEY,
      to: phone,
      from: TERMII_SENDER_ID,
      sms: `${TERMII_MESSAGE_PREFIX} ${code}`,
      type: 'plain',
      channel: TERMII_CHANNEL,
    };

    const { status } = await postJson(
      'https://api.ng.termii.com/api/sms/send',
      {},
      payload,
    );

    debug('PHONE OTP: Termii status', { status });

    if (status < 200 || status >= 300) {
      throw new Error('SMS delivery failed');
    }

    return;
  }

  throw new Error('SMS provider not configured');
}

async function requestEmailVerification(userId) {
  debug('VERIFY SERVICE: requestEmailVerification', { userId });

  const user = await User.findById(userId);
  if (!user) {
    throw new Error('User not found');
  }

  if (!user.email) {
    throw new Error('Email is missing');
  }

  if (user.isEmailVerified) {
    return {
      status: 'already_verified',
      email: user.email,
    };
  }

  const code = generateOtp();
  user.emailVerificationCodeHash = hashCode(code);
  user.emailVerificationExpiresAt = expiryDate();
  await user.save();

  await sendEmailCode({ email: user.email, code });

  return {
    status: 'sent',
    email: user.email,
    expiresAt: user.emailVerificationExpiresAt,
    code: SHOW_OTP_IN_RESPONSE ? code : undefined,
  };
}

async function confirmEmailVerification(userId, code) {
  debug('VERIFY SERVICE: confirmEmailVerification', { userId });

  const user = await User.findById(userId);
  if (!user) {
    throw new Error('User not found');
  }

  if (!code) {
    throw new Error('Verification code is required');
  }

  if (!user.emailVerificationCodeHash || !user.emailVerificationExpiresAt) {
    throw new Error('No email verification request found');
  }

  if (user.emailVerificationExpiresAt < new Date()) {
    throw new Error('Verification code expired');
  }

  const hashed = hashCode(code);
  if (hashed !== user.emailVerificationCodeHash) {
    throw new Error('Invalid verification code');
  }

  user.isEmailVerified = true;
  user.emailVerificationCodeHash = null;
  user.emailVerificationExpiresAt = null;
  await user.save();

  return {
    status: 'verified',
    email: user.email,
  };
}

async function requestPhoneVerification(userId, phone) {
  debug('VERIFY SERVICE: requestPhoneVerification', { userId });

  const user = await User.findById(userId);
  if (!user) {
    throw new Error('User not found');
  }

  const normalizedPhone = normalizeNigerianPhone(phone || user.phone || '');
  if (!normalizedPhone) {
    throw new Error('Invalid Nigerian phone number');
  }

  user.phone = normalizedPhone;

  if (user.isPhoneVerified) {
    return {
      status: 'already_verified',
      phone: user.phone,
    };
  }

  const code = generateOtp();
  user.phoneVerificationCodeHash = hashCode(code);
  user.phoneVerificationExpiresAt = expiryDate();
  await user.save();

  await sendPhoneCode({ phone: user.phone, code });

  return {
    status: 'sent',
    phone: user.phone,
    expiresAt: user.phoneVerificationExpiresAt,
    code: SHOW_OTP_IN_RESPONSE ? code : undefined,
  };
}

async function confirmPhoneVerification(userId, code) {
  debug('VERIFY SERVICE: confirmPhoneVerification', { userId });

  const user = await User.findById(userId);
  if (!user) {
    throw new Error('User not found');
  }

  if (!code) {
    throw new Error('Verification code is required');
  }

  if (!user.phoneVerificationCodeHash || !user.phoneVerificationExpiresAt) {
    throw new Error('No phone verification request found');
  }

  if (user.phoneVerificationExpiresAt < new Date()) {
    throw new Error('Verification code expired');
  }

  const hashed = hashCode(code);
  if (hashed !== user.phoneVerificationCodeHash) {
    throw new Error('Invalid verification code');
  }

  user.isPhoneVerified = true;
  user.phoneVerificationCodeHash = null;
  user.phoneVerificationExpiresAt = null;
  await user.save();

  return {
    status: 'verified',
    phone: user.phone,
  };
}

module.exports = {
  requestEmailVerification,
  confirmEmailVerification,
  requestPhoneVerification,
  confirmPhoneVerification,
};
