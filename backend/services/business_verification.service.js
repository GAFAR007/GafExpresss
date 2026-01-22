/**
 * apps/backend/services/business_verification.service.js
 * -------------------------------------------------------
 * WHAT:
 * - Dojah-backed business verification service.
 *
 * WHY:
 * - Validates business registration numbers server-side.
 * - Stores verified business profile data for account upgrades.
 *
 * HOW:
 * - Requires NIN verification before business verification.
 * - Calls Dojah verification endpoint (configurable via env).
 * - Updates user with business verification status + profile fields.
 */

const debug = require('../utils/debug');
const User = require('../models/User');
const { ACCOUNT_TYPES } = require('../models/User');

// WHY: Keep Dojah configuration in env so secrets are not hardcoded.
const DOJAH_BASE_URL = (process.env.DOJAH_BASE_URL || 'https://api.dojah.io').trim();
const DOJAH_BUSINESS_VERIFY_URL =
  (process.env.DOJAH_BUSINESS_VERIFY_URL || '').trim() ||
  `${DOJAH_BASE_URL}/api/v1/kyc/business`;
const DOJAH_APP_ID = (process.env.DOJAH_APP_ID || '').trim();
const DOJAH_SECRET_KEY = (process.env.DOJAH_SECRET_KEY || '').trim();
const DOJAH_METHOD = (process.env.DOJAH_BUSINESS_VERIFY_METHOD || 'GET')
  .toUpperCase()
  .trim();
const DOJAH_REG_FIELD = (process.env.DOJAH_REG_FIELD || 'rc_number').trim();
const DOJAH_TYPE_FIELD = (process.env.DOJAH_TYPE_FIELD || 'company_type').trim();
const DOJAH_TIMEOUT_MS = Number(process.env.DOJAH_TIMEOUT_MS || 15000);
// WHY: Allow a safe simulation mode until Dojah credentials are ready.
const DOJAH_SIMULATION_ENABLED =
  (process.env.DOJAH_SIMULATION_ENABLED || '').toLowerCase() === 'true';
const SIM_REG_NUMBER = (process.env.BUSINESS_VERIFY_SIM_REG_NUMBER || '').trim();
const SIM_COMPANY_NAME = (process.env.BUSINESS_VERIFY_SIM_COMPANY_NAME || '').trim();
const SIM_EMAIL = (process.env.BUSINESS_VERIFY_SIM_EMAIL || '').trim();
const SIM_PHONE = (process.env.BUSINESS_VERIFY_SIM_PHONE || '').trim();
const SIM_ADDRESS = (process.env.BUSINESS_VERIFY_SIM_ADDRESS || '').trim();
const SIM_INCORP_DATE = (process.env.BUSINESS_VERIFY_SIM_INCORP_DATE || '').trim();
const SIM_INDUSTRY = (process.env.BUSINESS_VERIFY_SIM_INDUSTRY || '').trim();
const SIM_TAX_ID = (process.env.BUSINESS_VERIFY_SIM_TAX_ID || '').trim();
const SIM_REF = (process.env.BUSINESS_VERIFY_SIM_REF || '').trim();
const SIM_DIRECTOR_1_NAME = (process.env.BUSINESS_VERIFY_SIM_DIRECTOR_1_NAME || '').trim();
const SIM_DIRECTOR_1_ROLE = (process.env.BUSINESS_VERIFY_SIM_DIRECTOR_1_ROLE || '').trim();
const SIM_DIRECTOR_1_EMAIL = (process.env.BUSINESS_VERIFY_SIM_DIRECTOR_1_EMAIL || '').trim();
const SIM_DIRECTOR_1_PHONE = (process.env.BUSINESS_VERIFY_SIM_DIRECTOR_1_PHONE || '').trim();

function last4(value) {
  const cleaned = value.replace(/\s+/g, '');
  return cleaned.length >= 4 ? cleaned.slice(-4) : cleaned;
}

function pickFirstString(values) {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

function mapAccountTypeToRegType(accountType) {
  switch (accountType) {
    case 'sole_proprietorship':
      return 'BN';
    case 'partnership':
      return 'BN';
    case 'limited_liability_company':
      return 'RC';
    case 'public_limited_company':
      return 'RC';
    case 'incorporated_trustees':
      return 'IT';
    default:
      return null;
  }
}

function extractBusinessDirectors(payload) {
  const candidates = payload?.directors || payload?.director || payload?.officers;
  if (!Array.isArray(candidates)) return [];

  return candidates
    .map((item) => {
      if (!item || typeof item !== 'object') return null;
      const name = pickFirstString([item.name, item.full_name, item.fullName]);
      if (!name) return null;
      return {
        name,
        role: pickFirstString([item.role, item.position, item.title]),
        email: pickFirstString([item.email]),
        phone: pickFirstString([item.phone, item.phone_number]),
      };
    })
    .filter(Boolean);
}

function normalizeName(value) {
  return (value || '')
    .toString()
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function isUserInDirectors(user, directors) {
  if (!user || !Array.isArray(directors) || directors.length === 0) {
    return false;
  }

  const first = normalizeName(user.firstName);
  const middle = normalizeName(user.middleName);
  const last = normalizeName(user.lastName);
  const full = normalizeName([first, middle, last].filter(Boolean).join(' '));
  const compact = normalizeName([first, last].filter(Boolean).join(' '));

  return directors.some((director) => {
    const name = normalizeName(director?.name);
    if (!name) return false;
    if (full && name.includes(full)) return true;
    if (compact && name.includes(compact)) return true;
    return false;
  });
}

function buildRegisteredAddress(payload) {
  const formatted = pickFirstString([
    payload?.registered_address,
    payload?.registeredAddress,
    payload?.address,
    payload?.business_address,
    payload?.businessAddress,
  ]);

  if (!formatted) return null;

  return {
    formattedAddress: formatted,
    country: 'NG',
    isVerified: true,
    verificationSource: 'dojah',
    verifiedAt: new Date(),
  };
}

function buildSimulatedResponse() {
  // WHY: Mirror Dojah response structure so downstream parsing stays the same.
  return {
    reference_id: SIM_REF || `SIM-${Date.now()}`,
    data: {
      company_name: SIM_COMPANY_NAME || 'Sample Business',
      registered_address: SIM_ADDRESS || 'Demo Address, Lagos, Nigeria',
      email: SIM_EMAIL || 'business@example.com',
      phone: SIM_PHONE || '+2348000000000',
      incorporation_date: SIM_INCORP_DATE || null,
      industry: SIM_INDUSTRY || null,
      tax_id: SIM_TAX_ID || null,
      directors: SIM_DIRECTOR_1_NAME
        ? [
            {
              name: SIM_DIRECTOR_1_NAME,
              role: SIM_DIRECTOR_1_ROLE || null,
              email: SIM_DIRECTOR_1_EMAIL || null,
              phone: SIM_DIRECTOR_1_PHONE || null,
            },
          ]
        : [],
    },
  };
}

async function callDojahVerification({ registrationNumber, regType }) {
  if (!DOJAH_APP_ID || !DOJAH_SECRET_KEY) {
    throw new Error('Dojah credentials are not configured');
  }

  const headers = {
    'Content-Type': 'application/json',
    AppId: DOJAH_APP_ID,
    Authorization: `Bearer ${DOJAH_SECRET_KEY}`,
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DOJAH_TIMEOUT_MS);

  try {
    if (DOJAH_METHOD === 'GET') {
      const url = new URL(DOJAH_BUSINESS_VERIFY_URL);
      url.searchParams.set(DOJAH_REG_FIELD, registrationNumber);
      if (regType) {
        url.searchParams.set(DOJAH_TYPE_FIELD, regType);
      }

      debug('BUSINESS VERIFY: Dojah GET', {
        endpoint: url.toString(),
        regField: DOJAH_REG_FIELD,
        typeField: DOJAH_TYPE_FIELD,
      });

      const resp = await fetch(url, {
        method: 'GET',
        headers,
        signal: controller.signal,
      });

      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        const message = pickFirstString([
          data?.message,
          data?.error,
          data?.data?.message,
        ]);
        throw new Error(message || 'Dojah verification failed');
      }

      return data;
    }

    const payload = {
      [DOJAH_REG_FIELD]: registrationNumber,
    };
    if (regType) {
      payload[DOJAH_TYPE_FIELD] = regType;
    }

    debug('BUSINESS VERIFY: Dojah POST', {
      endpoint: DOJAH_BUSINESS_VERIFY_URL,
      regField: DOJAH_REG_FIELD,
      typeField: DOJAH_TYPE_FIELD,
    });

    const resp = await fetch(DOJAH_BUSINESS_VERIFY_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    const data = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      const message = pickFirstString([
        data?.message,
        data?.error,
        data?.data?.message,
      ]);
      throw new Error(message || 'Dojah verification failed');
    }

    return data;
  } finally {
    clearTimeout(timeout);
  }
}

async function verifyBusinessForUser({
  userId,
  accountType,
  registrationNumber,
  registrationType,
}) {
  debug('BUSINESS VERIFY: request', {
    userId,
    accountType,
  });

  if (!userId) {
    throw new Error('Missing userId');
  }

  if (!accountType || !ACCOUNT_TYPES.includes(accountType)) {
    throw new Error('Invalid account type');
  }

  if (accountType === 'personal') {
    throw new Error('Personal accounts cannot be business verified');
  }

  if (!registrationNumber || typeof registrationNumber !== 'string') {
    throw new Error('Registration number is required');
  }

  const trimmedReg = registrationNumber.trim();
  if (trimmedReg.length < 5) {
    throw new Error('Registration number is too short');
  }

  const regLast4 = last4(trimmedReg);
  debug('BUSINESS VERIFY: input received', {
    userId,
    length: trimmedReg.length,
    last4: regLast4,
  });

  const user = await User.findById(userId).select('-passwordHash');
  if (!user) {
    throw new Error('User not found');
  }

  if (!user.isNinVerified) {
    debug('BUSINESS VERIFY: blocked (missing NIN verification)', {
      userId,
    });
    throw new Error('NIN must be verified before business verification');
  }

  const regType = (registrationType || mapAccountTypeToRegType(accountType) || '')
    .toString()
    .trim();

  debug('BUSINESS VERIFY: calling Dojah', {
    userId,
    regType: regType || null,
    endpoint: DOJAH_BUSINESS_VERIFY_URL,
    method: DOJAH_METHOD,
  });

  let responseData;
  try {
    user.businessVerificationStatus = 'pending';
    user.businessVerificationSource = 'dojah';
    user.businessVerificationMessage = null;
    user.businessVerificationRef = null;
    await user.save();

    if (DOJAH_SIMULATION_ENABLED) {
      debug('BUSINESS VERIFY: simulation enabled', {
        userId,
        hasSimReg: !!SIM_REG_NUMBER,
      });
      if (!SIM_REG_NUMBER) {
        throw new Error('Business verification simulation is not configured');
      }
      if (trimmedReg !== SIM_REG_NUMBER) {
        debug('BUSINESS VERIFY: simulation mismatch', {
          inputLast4: last4(trimmedReg),
          simLast4: last4(SIM_REG_NUMBER),
        });
        throw new Error('Business verification failed (simulation mismatch)');
      }
      responseData = buildSimulatedResponse();
    } else {
      responseData = await callDojahVerification({
        registrationNumber: trimmedReg,
        regType,
      });
    }
  } catch (error) {
    const message = error?.message || 'Business verification failed';
    user.businessVerificationStatus = 'failed';
    user.businessVerificationSource = 'dojah';
    user.businessVerificationMessage = message;
    await user.save();
    throw new Error(message);
  }

  const payload = responseData?.data || responseData?.entity || responseData || {};
  const companyName = pickFirstString([
    payload?.company_name,
    payload?.business_name,
    payload?.registered_name,
    payload?.name,
  ]);

  const companyEmail = pickFirstString([
    payload?.email,
    payload?.company_email,
    payload?.business_email,
  ]);
  const companyPhone = pickFirstString([
    payload?.phone,
    payload?.phone_number,
    payload?.company_phone,
  ]);

  const directors = extractBusinessDirectors(payload);
  const registeredAddress = buildRegisteredAddress(payload);
  const verificationRef = pickFirstString([
    responseData?.reference_id,
    responseData?.verification_id,
    responseData?.id,
  ]);

  // WHY: Ensure the verified NIN user appears in the directors list.
  const isDirectorMatch = isUserInDirectors(user, directors);
  if (!isDirectorMatch) {
    debug('BUSINESS VERIFY: director match failed', {
      userId,
      directorsCount: directors.length,
      directorNamesSample: directors
        .map((director) => director?.name)
        .filter(Boolean)
        .slice(0, 5),
    });
    user.businessVerificationStatus = 'failed';
    user.businessVerificationSource = 'dojah';
    user.businessVerificationMessage =
      'Business verification failed: user not found in directors list';
    await user.save();
    throw new Error(user.businessVerificationMessage);
  }

  user.businessVerificationStatus = 'verified';
  user.businessVerificationSource = 'dojah';
  user.businessVerificationMessage = null;
  user.businessVerificationRef = verificationRef;
  user.businessVerifiedAt = new Date();
  user.businessRegistrationNumber = trimmedReg;
  user.businessRegistrationType = regType || user.businessRegistrationType;
  user.businessIncorporationDate = pickFirstString([
    payload?.incorporation_date,
    payload?.registration_date,
  ]);
  user.businessIndustry = pickFirstString([
    payload?.industry,
    payload?.business_sector,
  ]);
  user.businessTaxId = pickFirstString([
    payload?.tax_id,
    payload?.tin,
  ]);

  if (registeredAddress) {
    user.businessRegisteredAddress = registeredAddress;
  }

  if (directors.length > 0) {
    user.businessDirectors = directors;
  }

  if (companyName) {
    user.companyName = companyName;
  }
  if (companyEmail) {
    user.companyEmail = companyEmail.toLowerCase();
  }
  if (companyPhone) {
    user.companyPhone = companyPhone;
  }
  if (trimmedReg) {
    user.companyRegistration = trimmedReg;
  }

  // WHY: Promote verified business owners to scoped role and set businessId.
  if (user.role !== 'admin') {
    user.role = 'business_owner';
  }
  if (!user.businessId) {
    user.businessId = user._id;
  }

  await user.save();

  debug('BUSINESS VERIFY: success', {
    userId,
    status: user.businessVerificationStatus,
  });

  return {
    status: 'verified',
    businessVerificationStatus: user.businessVerificationStatus,
    businessVerificationRef: user.businessVerificationRef,
    businessVerifiedAt: user.businessVerifiedAt,
  };
}

module.exports = {
  verifyBusinessForUser,
};
