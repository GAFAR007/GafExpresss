/**
 * services/staff_attendance_proof.service.js
 * ------------------------------------------
 * WHAT:
 * - Uploads staff attendance proof files to Cloudinary.
 *
 * WHY:
 * - Clock-out must be backed by proof so attendance remains auditable.
 * - Keeps upload and validation logic out of the controller.
 *
 * HOW:
 * - Validates the file payload and MIME type.
 * - Streams the file to Cloudinary and returns proof metadata.
 */

const debug = require("../utils/debug");
const { v2: cloudinary } = require("cloudinary");

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || "",
  api_key: process.env.CLOUDINARY_API_KEY || "",
  api_secret: process.env.CLOUDINARY_API_SECRET || "",
});

const ALLOWED_MIME_TYPES = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/jpg",
  "image/webp",
];

const SERVICE_NAME = "CLOUDINARY";
const OPERATION_UPLOAD = "staff_attendance_proof_upload";
const REQUEST_INTENT = "Upload staff attendance proof";

function assertCloudinaryConfig() {
  const hasConfig =
    !!process.env.CLOUDINARY_CLOUD_NAME &&
    !!process.env.CLOUDINARY_API_KEY &&
    !!process.env.CLOUDINARY_API_SECRET;

  if (!hasConfig) {
    throw new Error("Cloudinary credentials are not configured");
  }
}

function logCloudinaryFailure({ businessId, attendanceId, error }) {
  debug("STAFF ATTENDANCE PROOF: upload failed", {
    service: SERVICE_NAME,
    operation: OPERATION_UPLOAD,
    request_intent: REQUEST_INTENT,
    businessId,
    attendanceId,
    http_status: error?.http_code || error?.status || null,
    provider_error_code: error?.code || null,
    provider_error_message:
      error?.message || error?.error?.message || "Unknown provider error",
  });
}

async function uploadStaffAttendanceProof({
  businessId,
  attendanceId,
  file,
}) {
  debug("STAFF ATTENDANCE PROOF: upload request", {
    businessId,
    attendanceId,
    hasFile: Boolean(file),
  });

  if (!businessId) {
    throw new Error("Business scope is required");
  }

  if (!attendanceId) {
    throw new Error("Attendance id is required");
  }

  if (!file) {
    throw new Error("Proof file is required");
  }

  if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
    throw new Error("Unsupported proof format");
  }

  assertCloudinaryConfig();

  try {
    const uploadResult = await new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        {
          folder: `gafexpress/staff-attendance-proofs/${businessId}/${attendanceId}`,
          resource_type: "auto",
          allowed_formats: ["pdf", "png", "jpg", "jpeg", "webp"],
        },
        (error, result) => {
          if (error) return reject(error);
          return resolve(result);
        },
      );
      stream.end(file.buffer);
    });

    debug("STAFF ATTENDANCE PROOF: upload success", {
      businessId,
      attendanceId,
      publicId: uploadResult.public_id,
    });

    return {
      url: uploadResult.secure_url,
      publicId: uploadResult.public_id || "",
      filename: file.originalname || "",
      mimeType: file.mimetype || "",
      sizeBytes: file.size || 0,
    };
  } catch (error) {
    logCloudinaryFailure({
      businessId,
      attendanceId,
      error,
    });
    throw error;
  }
}

module.exports = {
  uploadStaffAttendanceProof,
};
