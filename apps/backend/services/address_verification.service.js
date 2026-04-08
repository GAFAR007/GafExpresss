/**
 * apps/backend/services/address_verification.service.js
 * ------------------------------------------------------
 * WHAT:
 * - Validates structured addresses via Google Address Validation API.
 *
 * WHY:
 * - We need verified, standardized delivery addresses for checkout.
 * - Keeps address verification logic out of controllers.
 *
 * HOW:
 * - Validates required fields (houseNumber, street, city, state).
 * - Calls Google Address Validation API with NG region.
 * - Stores verification metadata on the user profile.
 */

const http = require("http");
const https = require("https");
const { URL } = require("url");
const debug = require("../utils/debug");
const User = require("../models/User");
const {
  fetchPlaceDetails,
} = require("./address_autocomplete.service");

// WHY: Google API key must be present to verify addresses.
const GOOGLE_ADDRESS_API_KEY =
  process.env.GOOGLE_ADDRESS_API_KEY;
const GOOGLE_ADDRESS_ENDPOINT =
  "https://addressvalidation.googleapis.com/v1:validateAddress";

// WHY: Required fields for Nigeria delivery verification.
const REQUIRED_FIELDS = [
  "houseNumber",
  "street",
  "city",
  "state",
];

// WHY: Normalize strings consistently across all address fields.
function normalizeString(value) {
  if (typeof value !== "string")
    return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ?
      trimmed
    : null;
}

// WHY: Normalize incoming address payload and keep it structured.
function normalizeAddressInput(input) {
  if (
    !input ||
    typeof input !== "object"
  ) {
    return null;
  }

  const normalized = {
    houseNumber: normalizeString(
      input.houseNumber,
    ),
    street: normalizeString(
      input.street,
    ),
    city: normalizeString(input.city),
    state: normalizeString(input.state),
    postalCode: normalizeString(
      input.postalCode,
    ),
    lga: normalizeString(input.lga),
    country:
      normalizeString(input.country) ||
      "NG",
    landmark: normalizeString(
      input.landmark,
    ),
  };

  const hasAny = Object.values(
    normalized,
  ).some(
    (value) =>
      value != null && value !== "",
  );

  return hasAny ? normalized : null;
}

// WHY: Ensure required fields are present before calling Google.
function assertRequiredFields(address) {
  const missing =
    REQUIRED_FIELDS.filter(
      (field) => !address[field],
    );
  if (missing.length > 0) {
    throw new Error(
      `Missing required address fields: ${missing.join(", ")}`,
    );
  }
}

// WHY: Keep HTTP posting logic small and testable.
function postJson(urlString, body) {
  const url = new URL(urlString);
  const payload = JSON.stringify(body);
  const client =
    url.protocol === "https:" ?
      https
    : http;

  return new Promise(
    (resolve, reject) => {
      const request = client.request(
        {
          method: "POST",
          hostname: url.hostname,
          path: `${url.pathname}${url.search}`,
          port:
            url.port ||
            (url.protocol === "https:" ?
              443
            : 80),
          headers: {
            "Content-Type":
              "application/json",
            "Content-Length":
              Buffer.byteLength(
                payload,
              ),
          },
          timeout: 10000,
        },
        (response) => {
          let data = "";
          response.on(
            "data",
            (chunk) => {
              data += chunk;
            },
          );
          response.on("end", () => {
            try {
              const parsed =
                JSON.parse(data);
              resolve({
                status:
                  response.statusCode ||
                  0,
                data: parsed,
              });
            } catch (err) {
              resolve({
                status:
                  response.statusCode ||
                  0,
                data: data || null,
              });
            }
          });
        },
      );

      request.on("error", reject);
      request.on("timeout", () => {
        request.destroy(
          new Error("Request timeout"),
        );
      });

      request.write(payload);
      request.end();
    },
  );
}

// WHY: Construct the API payload expected by Google Address Validation.
function buildGooglePayload(address) {
  const lineOne =
    `${address.houseNumber} ${address.street}`.trim();
  const addressLines = [lineOne].filter(
    Boolean,
  );

  if (address.landmark) {
    addressLines.push(address.landmark);
  }

  return {
    address: {
      regionCode:
        address.country || "NG",
      administrativeArea: address.state,
      locality: address.city,
      postalCode:
        address.postalCode || undefined,
      addressLines,
    },
  };
}

// WHY: Standardize the Google response into our address model.
function normalizeGoogleResult(
  result,
  fallback,
) {
  const verdict = result?.verdict || {};
  const postal =
    result?.address?.postalAddress ||
    {};
  const geocode = result?.geocode || {};
  const location =
    geocode.location || {};

  const isVerified =
    verdict.addressComplete === true &&
    verdict.validationGranularity &&
    verdict.validationGranularity !==
      "OTHER" &&
    verdict.hasUnconfirmedComponents !==
      true;

  return {
    isVerified,
    formattedAddress:
      result?.address
        ?.formattedAddress ||
      ((
        Array.isArray(
          postal.addressLines,
        )
      ) ?
        postal.addressLines.join(", ")
      : null),
    placeId: geocode.placeId || null,
    lat:
      (
        typeof location.latitude ===
        "number"
      ) ?
        location.latitude
      : null,
    lng:
      (
        typeof location.longitude ===
        "number"
      ) ?
        location.longitude
      : null,
    standardizedAddress: {
      houseNumber: fallback.houseNumber,
      street: fallback.street,
      city:
        postal.locality ||
        fallback.city,
      state:
        postal.administrativeArea ||
        fallback.state,
      postalCode:
        postal.postalCode ||
        fallback.postalCode,
      lga: fallback.lga,
      country:
        postal.regionCode ||
        fallback.country ||
        "NG",
      landmark: fallback.landmark,
    },
    verdict,
  };
}

function mergePlaceDetails(placeAddress, fallback) {
  // WHY: Allow user input to fill gaps when place details are missing fields.
  return {
    houseNumber:
      placeAddress.houseNumber ||
      fallback.houseNumber,
    street:
      placeAddress.street || fallback.street,
    city: placeAddress.city || fallback.city,
    state:
      placeAddress.state || fallback.state,
    postalCode:
      placeAddress.postalCode ||
      fallback.postalCode,
    lga: placeAddress.lga || fallback.lga,
    country:
      placeAddress.country ||
      fallback.country ||
      "NG",
    landmark: fallback.landmark,
  };
}

async function verifyViaPlaceDetails({
  placeId,
  fallback,
  source,
}) {
  debug(
    "ADDRESS VERIFY SERVICE: place details fallback",
    {
      source,
      hasPlaceId: !!placeId,
    },
  );

  const placeAddress =
    await fetchPlaceDetails(placeId);
  const merged = mergePlaceDetails(
    placeAddress,
    fallback,
  );

  assertRequiredFields(merged);

  return {
    status: "verified",
    address: {
      ...merged,
      isVerified: true,
      verifiedAt: new Date(),
      verificationSource: "google_places",
      formattedAddress:
        placeAddress.formattedAddress,
      placeId:
        placeAddress.placeId || placeId,
      lat: placeAddress.lat,
      lng: placeAddress.lng,
    },
  };
}

async function verifyAddressPayload({
  address,
  source,
  placeId,
}) {
  // WHY: Allow reuse for both profile verification and order delivery checks.
  debug(
    "ADDRESS VERIFY SERVICE: payload entry",
    {
      source,
      hasKey: !!GOOGLE_ADDRESS_API_KEY,
    },
  );

  if (!GOOGLE_ADDRESS_API_KEY) {
    throw new Error(
      "Google Address API key is not configured",
    );
  }

  const normalized =
    normalizeAddressInput(address);
  if (!normalized) {
    throw new Error(
      "Address payload is required",
    );
  }

  assertRequiredFields(normalized);

  const url = new URL(
    GOOGLE_ADDRESS_ENDPOINT,
  );
  url.searchParams.set(
    "key",
    GOOGLE_ADDRESS_API_KEY,
  );

  debug(
    "ADDRESS VERIFY SERVICE: calling Google",
    {
      source,
      country: normalized.country,
      hasPostal:
        !!normalized.postalCode,
    },
  );

  const { status, data } =
    await postJson(
      url.toString(),
      buildGooglePayload(normalized),
    );

  if (status < 200 || status >= 300) {
    // WHY: Capture Google error details so we can debug invalid requests fast.
    debug(
      "ADDRESS VERIFY SERVICE: Google error",
      {
        status,
        googleStatus:
          data?.error?.status,
        googleMessage:
          data?.error?.message,
      },
    );

    const message = data?.error?.message || "";
    const isUnsupportedRegion =
      message.includes("Unsupported region code");

    if (isUnsupportedRegion && placeId) {
      return verifyViaPlaceDetails({
        placeId,
        fallback: normalized,
        source,
      });
    }

    if (isUnsupportedRegion) {
      throw new Error(
        "Address verification is not supported for this region. Please select an address from autocomplete.",
      );
    }

    throw new Error(
      data?.error?.message ?
        `Address verification failed: ${data.error.message}`
      : "Address verification failed",
    );
  }

  const result = normalizeGoogleResult(
    data?.result,
    normalized,
  );
  debug(
    "ADDRESS VERIFY SERVICE: verdict",
    {
      source,
      isVerified: result.isVerified,
      granularity:
        result.verdict
          ?.validationGranularity,
    },
  );

  const addressForSave = {
    ...result.standardizedAddress,
    isVerified: result.isVerified,
    verifiedAt:
      result.isVerified ?
        new Date()
      : null,
    verificationSource:
      "google_address_validation",
    formattedAddress:
      result.formattedAddress,
    placeId: result.placeId,
    lat: result.lat,
    lng: result.lng,
  };

  return {
    status:
      result.isVerified ? "verified" : (
        "unverified"
      ),
    address: addressForSave,
  };
}

async function verifyUserAddress({
  userId,
  type,
  address,
  placeId,
}) {
  debug(
    "ADDRESS VERIFY SERVICE: entry",
    { userId, type },
  );

  if (!userId) {
    throw new Error("Missing userId");
  }

  if (
    type !== "home" &&
    type !== "company"
  ) {
    throw new Error(
      "Invalid address type",
    );
  }

  const result =
    await verifyAddressPayload({
      address,
      source: type,
      placeId,
    });

  const updateField =
    type === "home" ?
      "homeAddress"
    : "companyAddress";

  const user =
    await User.findByIdAndUpdate(
      userId,
      {
        $set: {
          [updateField]: result.address,
        },
      },
      {
        new: true,
        runValidators: true,
      },
    ).select("-passwordHash");

  if (!user) {
    throw new Error("User not found");
  }

  debug(
    "ADDRESS VERIFY SERVICE: success",
    { userId, type },
  );

  return {
    status: result.status,
    address: result.address,
  };
}

module.exports = {
  verifyAddressPayload,
  verifyUserAddress,
};
