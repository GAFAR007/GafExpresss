/**
 * apps/backend/services/profile.service.js
 * ----------------------------------------
 * WHAT:
 * - Profile service for fetching/updating the authenticated user's profile.
 *
 * WHY:
 * - Keeps profile logic out of controllers.
 * - Ensures updates are validated and safe before touching MongoDB.
 *
 * HOW:
 * - Fetches user by ID and returns a safe, sanitized profile payload.
 * - Filters update inputs to a strict allowlist and applies changes.
 */

const debug = require("../utils/debug");
const User = require("../models/User");
const {
  ACCOUNT_TYPES,
} = require("../models/User");

// WHY: Keep email validation consistent with registration rules.
const EMAIL_REGEX =
  /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// WHY: Enforce Nigerian phone formatting when present.
const PHONE_NG_E164_REGEX =
  /^\+234\d{10}$/;
const PHONE_NG_LOCAL_REGEX =
  /^0\d{10}$/;
const PHONE_NG_PLAIN_REGEX =
  /^234\d{10}$/;

// WHY: Restrict updates to only the profile fields the UI exposes.
const PROFILE_FIELDS = [
  "firstName",
  "lastName",
  "name",
  "email",
  "phone",
  "accountType",
  "profileImageUrl",
  "companyName",
  "companyEmail",
  "companyPhone",
  "companyWebsite",
  "companyRegistration",
];

// WHY: Centralize string cleanup so all fields are normalized consistently.
function normalizeString(value) {
  if (typeof value !== "string")
    return value;
  const trimmed = value.trim();
  return trimmed.length > 0 ?
      trimmed
    : null;
}

// WHY: Normalize Nigerian numbers to E.164 for consistency across services.
function normalizeNigerianPhone(value) {
  const raw = (value || "")
    .toString()
    .replace(/\s+/g, "")
    .trim();

  if (PHONE_NG_E164_REGEX.test(raw))
    return raw;
  if (PHONE_NG_LOCAL_REGEX.test(raw))
    return `+234${raw.slice(1)}`;
  if (PHONE_NG_PLAIN_REGEX.test(raw))
    return `+${raw}`;

  return null;
}

// WHY: Normalize structured address input and keep only allowed fields.
function normalizeAddressInput(input) {
  if (!input || typeof input !== "object") {
    return null;
  }

  const normalized = {
    houseNumber: normalizeString(input.houseNumber),
    street: normalizeString(input.street),
    city: normalizeString(input.city),
    state: normalizeString(input.state),
    postalCode: normalizeString(input.postalCode),
    lga: normalizeString(input.lga),
    country: normalizeString(input.country) || "NG",
    landmark: normalizeString(input.landmark),
  };

  const hasAny = Object.values(normalized).some(
    (value) => value != null && value !== ""
  );

  return hasAny ? normalized : null;
}

// WHY: Compare address fields to decide if verification should reset.
function addressHasChanges(existing, next) {
  if (!next) return false;
  if (!existing || typeof existing !== "object") return true;

  const fields = [
    "houseNumber",
    "street",
    "city",
    "state",
    "postalCode",
    "lga",
    "country",
    "landmark",
  ];

  return fields.some((field) => {
    const currentValue = existing[field] || null;
    const nextValue = next[field] || null;
    return currentValue !== nextValue;
  });
}

// WHY: Reset verification metadata whenever an address changes.
function mergeAddressWithVerification(existing, next) {
  if (!next) {
    return null;
  }

  if (!addressHasChanges(existing, next)) {
    return existing;
  }

  return {
    ...next,
    isVerified: false,
    verifiedAt: null,
    verificationSource: null,
    formattedAddress: null,
    placeId: null,
    lat: null,
    lng: null,
  };
}

// WHY: Only allow safe profile updates and validate account type.
function buildProfileUpdatePayload(
  input,
) {
  const payload = {};
  const inputHasEmail =
    Object.prototype.hasOwnProperty.call(
      input,
      "email",
    );

  for (const field of PROFILE_FIELDS) {
    if (
      !Object.prototype.hasOwnProperty.call(
        input,
        field,
      )
    ) {
      continue;
    }

    const rawValue = input[field];
    payload[field] =
      normalizeString(rawValue);
  }

  if (
    Object.prototype.hasOwnProperty.call(
      input,
      "homeAddress"
    )
  ) {
    payload.homeAddress = normalizeAddressInput(
      input.homeAddress
    );
  }

  if (
    Object.prototype.hasOwnProperty.call(
      input,
      "companyAddress"
    )
  ) {
    payload.companyAddress = normalizeAddressInput(
      input.companyAddress
    );
  }

  if (inputHasEmail) {
    if (!payload.email) {
      throw new Error(
        "Email is required",
      );
    }

    const normalizedEmail =
      payload.email.toLowerCase();

    if (
      !EMAIL_REGEX.test(normalizedEmail)
    ) {
      throw new Error(
        "Please provide a valid email address",
      );
    }

    payload.email = normalizedEmail;
  }

  if (payload.phone != null) {
    const normalized =
      normalizeNigerianPhone(
        payload.phone,
      );
    if (!normalized) {
      throw new Error(
        "Invalid Nigerian phone number",
      );
    }
    payload.phone = normalized;
  }

  if (payload.companyPhone != null) {
    const normalized =
      normalizeNigerianPhone(
        payload.companyPhone,
      );
    if (!normalized) {
      throw new Error(
        "Invalid company phone number",
      );
    }
    payload.companyPhone = normalized;
  }

  // WHY: Keep name in sync when first + last name are provided.
  if (
    payload.firstName &&
    payload.lastName
  ) {
    payload.name = `${payload.firstName} ${payload.lastName}`;
  }

  // WHY: Backfill split names when only a full name is sent.
  if (
    payload.name &&
    !payload.firstName &&
    !payload.lastName
  ) {
    const parts = payload.name
      .split(" ")
      .filter(Boolean);
    if (parts.length > 0) {
      payload.firstName = parts[0];
      payload.lastName =
        parts.slice(1).join(" ") ||
        null;
    }
  }

  if (
    payload.accountType &&
    !ACCOUNT_TYPES.includes(
      payload.accountType,
    )
  ) {
    throw new Error(
      "Invalid account type",
    );
  }

  return payload;
}

// WHY: Normalize address output for consistent frontend parsing.
function shapeAddress(addressValue) {
  if (!addressValue) {
    return null;
  }

  if (typeof addressValue === "string") {
    return {
      formattedAddress: addressValue,
      isVerified: false,
      country: "NG",
    };
  }

  return {
    houseNumber: addressValue.houseNumber || null,
    street: addressValue.street || null,
    city: addressValue.city || null,
    state: addressValue.state || null,
    postalCode: addressValue.postalCode || null,
    lga: addressValue.lga || null,
    country: addressValue.country || "NG",
    landmark: addressValue.landmark || null,
    isVerified: !!addressValue.isVerified,
    verifiedAt: addressValue.verifiedAt || null,
    verificationSource: addressValue.verificationSource || null,
    formattedAddress: addressValue.formattedAddress || null,
    placeId: addressValue.placeId || null,
    lat: typeof addressValue.lat === "number" ? addressValue.lat : null,
    lng: typeof addressValue.lng === "number" ? addressValue.lng : null,
  };
}

// WHY: Hide Mongo internal fields and password hash from client responses.
function shapeProfile(userDoc) {
  return {
    id: userDoc._id.toString(),
    name: userDoc.name || "",
    firstName:
      userDoc.firstName || null,
    lastName: userDoc.lastName || null,
    middleName:
      userDoc.middleName || null,
    dob: userDoc.dob || null,
    email: userDoc.email || "",
    role: userDoc.role || "customer",
    accountType:
      userDoc.accountType || "personal",
    isEmailVerified:
      !!userDoc.isEmailVerified,
    isPhoneVerified:
      !!userDoc.isPhoneVerified,
    isNinVerified:
      !!userDoc.isNinVerified,
    ninLast4: userDoc.ninLast4 || null,
    phone: userDoc.phone || null,
    profileImageUrl:
      userDoc.profileImageUrl || null,
    companyName:
      userDoc.companyName || null,
    companyEmail:
      userDoc.companyEmail || null,
    companyPhone:
      userDoc.companyPhone || null,
    homeAddress: shapeAddress(userDoc.homeAddress),
    companyAddress: shapeAddress(userDoc.companyAddress),
    companyWebsite:
      userDoc.companyWebsite || null,
    companyRegistration:
      userDoc.companyRegistration ||
      null,
  };
}

async function getUserProfile(userId) {
  debug(
    "PROFILE SERVICE: getUserProfile - entry",
    { userId },
  );

  if (!userId) {
    throw new Error("Missing userId");
  }

  const user = await User.findById(
    userId,
  ).select("-passwordHash");

  if (!user) {
    throw new Error("User not found");
  }

  debug(
    "PROFILE SERVICE: getUserProfile - success",
    { userId },
  );

  return shapeProfile(user);
}

async function updateUserProfile(
  userId,
  updates,
) {
  debug(
    "PROFILE SERVICE: updateUserProfile - entry",
    {
      userId,
      keys: Object.keys(updates || {}),
    },
  );

  if (!userId) {
    throw new Error("Missing userId");
  }

  const payload =
    buildProfileUpdatePayload(
      updates || {},
    );

  const currentUser =
    await User.findById(userId).select(
      "-passwordHash",
    );

  if (!currentUser) {
    throw new Error("User not found");
  }

  // WHY: Prevent changing a verified email without a dedicated flow.
  if (
    typeof payload.email === "string" &&
    payload.email !==
      (currentUser.email || "")
  ) {
    if (currentUser.isEmailVerified) {
      throw new Error(
        "Verified email cannot be changed until reset",
      );
    }

    const existingEmail =
      await User.findOne({
        email: payload.email,
        _id: { $ne: userId },
      }).select("_id");

    if (existingEmail) {
      throw new Error(
        "Email already registered",
      );
    }

    // WHY: Any email change requires fresh verification.
    payload.isEmailVerified = false;
    payload.emailVerificationCodeHash =
      null;
    payload.emailVerificationExpiresAt =
      null;
  }

  // WHY: Prevent multiple accounts from claiming the same phone number.
  if (
    typeof payload.phone === "string" &&
    payload.phone.trim().length > 0
  ) {
    debug(
      "PROFILE SERVICE: checking phone uniqueness",
      { userId },
    );
    const existingPhone =
      await User.findOne({
        phone: payload.phone,
        _id: { $ne: userId },
      }).select("_id");

    if (existingPhone) {
      throw new Error(
        "Phone number already in use",
      );
    }
  }

  if (
    Object.prototype.hasOwnProperty.call(
      payload,
      "homeAddress"
    )
  ) {
    payload.homeAddress = mergeAddressWithVerification(
      currentUser.homeAddress,
      payload.homeAddress
    );
  }

  if (
    Object.prototype.hasOwnProperty.call(
      payload,
      "companyAddress"
    )
  ) {
    payload.companyAddress = mergeAddressWithVerification(
      currentUser.companyAddress,
      payload.companyAddress
    );
  }

  const user =
    await User.findByIdAndUpdate(
      userId,
      { $set: payload },
      {
        new: true,
        runValidators: true,
      },
    ).select("-passwordHash");

  debug(
    "PROFILE SERVICE: updateUserProfile - success",
    { userId },
  );

  return shapeProfile(user);
}

module.exports = {
  getUserProfile,
  updateUserProfile,
};
