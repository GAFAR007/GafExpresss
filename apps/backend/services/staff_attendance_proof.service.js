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
 * - Validates the file payload and MIME/extension.
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
  "video/mp4",
  "video/quicktime",
  "video/webm",
  "video/x-m4v",
  "application/octet-stream",
];
const ALLOWED_FORMATS = ["pdf", "png", "jpg", "jpeg", "webp", "mp4", "mov", "webm", "m4v"];

const SERVICE_NAME = "CLOUDINARY";
const OPERATION_UPLOAD = "staff_attendance_proof_upload";
const REQUEST_INTENT = "Upload staff attendance proof";

function resolveProofType(mimeType) {
  const normalizedMimeType = (mimeType || "")
    .toString()
    .trim()
    .toLowerCase();
  if (normalizedMimeType.startsWith("image/")) {
    return "image";
  }
  if (normalizedMimeType.startsWith("video/")) {
    return "video";
  }
  if (normalizedMimeType) {
    return "document";
  }
  return "";
}

function normalizeExtension(fileName) {
  const normalized = (fileName || "")
    .toString()
    .trim()
    .toLowerCase();
  if (!normalized) {
    return "";
  }
  const parts = normalized.split(".");
  return parts.length > 1 ? parts.pop().trim() : "";
}

function resolveProofMimeType(file) {
  const mimetype = (file?.mimetype || "").toString().trim().toLowerCase();
  if (mimetype && mimetype !== "application/octet-stream") {
    return mimetype;
  }
  const extension = normalizeExtension(file?.originalname);
  switch (extension) {
    case "png":
      return "image/png";
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "webp":
      return "image/webp";
    case "mp4":
      return "video/mp4";
    case "mov":
      return "video/quicktime";
    case "webm":
      return "video/webm";
    case "m4v":
      return "video/x-m4v";
    case "pdf":
      return "application/pdf";
    default:
      return mimetype || "";
  }
}

function assertSupportedProofFile(file) {
  const extension = normalizeExtension(file?.originalname);
  const mimetype = (file?.mimetype || "").toString().trim().toLowerCase();
  const hasAllowedMimeType = ALLOWED_MIME_TYPES.includes(mimetype);
  const hasAllowedExtension = ALLOWED_FORMATS.includes(extension);
  if (!hasAllowedMimeType && !hasAllowedExtension) {
    throw new Error("Unsupported proof format");
  }
}

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
  unitIndex = 1,
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

  assertSupportedProofFile(file);

  assertCloudinaryConfig();

  try {
    const uploadResult = await new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        {
          folder: `gafexpress/staff-attendance-proofs/${businessId}/${attendanceId}`,
          resource_type: "auto",
          allowed_formats: ALLOWED_FORMATS,
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
      unitIndex: Math.max(1, Number(unitIndex || 1)),
      url: uploadResult.secure_url,
      publicId: uploadResult.public_id || "",
      filename: file.originalname || "",
      mimeType: resolveProofMimeType(file),
      type: resolveProofType(resolveProofMimeType(file)),
      sizeBytes: file.size || 0,
      uploadedAt: new Date(),
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

async function uploadStaffAttendanceProofs({
  businessId,
  attendanceId,
  files,
  startingUnitIndex = 1,
}) {
  if (!Array.isArray(files) || files.length === 0) {
    throw new Error("Proof file is required");
  }
  const uploadedProofs = [];
  for (let index = 0; index < files.length; index += 1) {
    const uploadedProof = await uploadStaffAttendanceProof({
      businessId,
      attendanceId,
      file: files[index],
      unitIndex:
        Math.max(1, Number(startingUnitIndex || 1)) + index,
    });
    uploadedProofs.push(uploadedProof);
  }
  return uploadedProofs;
}

module.exports = {
  uploadStaffAttendanceProof,
  uploadStaffAttendanceProofs,
};
