/**
 * services/tenant_contact_document.service.js
 * -------------------------------------------
 * WHAT:
 * - Uploads tenant reference/guarantor documents to Cloudinary.
 *
 * WHY:
 * - Keeps supporting documents centralized and auditable.
 * - Reuses a single upload path for PDF/image evidence.
 *
 * HOW:
 * - Validates the file payload and MIME type.
 * - Streams to Cloudinary and returns the URL + public id.
 * - Logs structured failures for support diagnostics.
 */

const debug = require("../utils/debug");
const { v2: cloudinary } = require("cloudinary");

// WHY: Configure Cloudinary once using env credentials.
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || "",
  api_key: process.env.CLOUDINARY_API_KEY || "",
  api_secret: process.env.CLOUDINARY_API_SECRET || "",
});

// WHY: Restrict uploads to PDFs and common image formats.
const ALLOWED_MIME_TYPES = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/jpg",
];

// WHY: Keep service log metadata consistent across failures.
const SERVICE_NAME = "CLOUDINARY";
const OPERATION_UPLOAD = "tenant_contact_document_upload";
const REQUEST_INTENT =
  "Upload reference/guarantor supporting document";

function assertCloudinaryConfig() {
  const hasConfig =
    !!process.env.CLOUDINARY_CLOUD_NAME &&
    !!process.env.CLOUDINARY_API_KEY &&
    !!process.env.CLOUDINARY_API_SECRET;

  if (!hasConfig) {
    throw new Error("Cloudinary credentials are not configured");
  }
}

function classifyFailure(status) {
  if (status == null) {
    return "UNKNOWN_PROVIDER_ERROR";
  }
  if (status === 400) return "INVALID_INPUT";
  if (status === 401 || status === 403) return "AUTHENTICATION_ERROR";
  if (status === 429) return "RATE_LIMITED";
  if (status >= 500) return "PROVIDER_OUTAGE";
  return "UNKNOWN_PROVIDER_ERROR";
}

function resolutionHint(classification) {
  switch (classification) {
    case "AUTHENTICATION_ERROR":
      return "Verify Cloudinary credentials and retry.";
    case "INVALID_INPUT":
      return "Check file type/size and try again.";
    case "RATE_LIMITED":
      return "Wait before retrying to avoid rate limits.";
    case "PROVIDER_OUTAGE":
      return "Retry later or check provider status.";
    case "UNKNOWN_PROVIDER_ERROR":
    default:
      return "Check Cloudinary logs for details.";
  }
}

function retryMetadata(classification) {
  switch (classification) {
    case "RATE_LIMITED":
      return { retry_allowed: true, retry_reason: "rate_limited" };
    case "PROVIDER_OUTAGE":
      return { retry_allowed: true, retry_reason: "provider_outage" };
    case "AUTHENTICATION_ERROR":
      return { retry_skipped: true, retry_reason: "auth_required" };
    case "INVALID_INPUT":
      return { retry_skipped: true, retry_reason: "invalid_input" };
    case "UNKNOWN_PROVIDER_ERROR":
    default:
      return { retry_skipped: true, retry_reason: "unknown_failure" };
  }
}

function logCloudinaryFailure({ source, context, error }) {
  // WHY: Ensure diagnostics include intent + provider details for support.
  const status = error?.http_code || error?.status || null;
  const providerCode = error?.code || null;
  const providerMessage =
    error?.message || error?.error?.message || "Unknown provider error";
  const classification = classifyFailure(status);
  const retryMeta = retryMetadata(classification);

  debug("TENANT DOCUMENT: upload failed", {
    service: SERVICE_NAME,
    operation: OPERATION_UPLOAD,
    request_intent: REQUEST_INTENT,
    request_context: {
      country: "NG",
      source,
      ...context,
    },
    http_status: status,
    provider_error_code: providerCode,
    provider_error_message: providerMessage,
    failure_classification: classification,
    ...(classification === "UNKNOWN_PROVIDER_ERROR" && {
      failure_justification: "No HTTP status provided by Cloudinary.",
    }),
    resolution_hint: resolutionHint(classification),
    ...retryMeta,
  });
}

async function uploadTenantContactDocument({
  businessId,
  actor,
  file,
  source,
}) {
  debug("TENANT DOCUMENT: upload request", {
    businessId,
    actorId: actor?.id,
  });

  if (!businessId) {
    throw new Error("Business scope is required");
  }

  if (!file) {
    throw new Error("Document file is required");
  }

  if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
    throw new Error("Unsupported document format");
  }

  assertCloudinaryConfig();

  try {
    const uploadResult = await new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        {
          folder: `gafexpress/tenant-documents/${businessId}`,
          resource_type: "auto",
          allowed_formats: ["pdf", "png", "jpg", "jpeg"],
        },
        (error, result) => {
          if (error) return reject(error);
          return resolve(result);
        },
      );
      stream.end(file.buffer);
    });

    debug("TENANT DOCUMENT: upload success", {
      businessId,
      publicId: uploadResult.public_id,
    });

    return {
      url: uploadResult.secure_url,
      publicId: uploadResult.public_id || "",
    };
  } catch (error) {
    logCloudinaryFailure({
      source: source || "tenant_verification",
      context: {
        hasFile: Boolean(file),
        hasFilename: Boolean(file?.originalname),
        hasMimeType: Boolean(file?.mimetype),
      },
      error,
    });
    throw error;
  }
}

module.exports = {
  uploadTenantContactDocument,
};
