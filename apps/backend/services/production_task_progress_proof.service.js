/**
 * services/production_task_progress_proof.service.js
 * ---------------------------------------------------
 * WHAT:
 * - Uploads production task progress proof images to Cloudinary.
 *
 * WHY:
 * - Daily progress must be backed by visual evidence.
 * - Keeps upload and validation logic out of the controller.
 *
 * HOW:
 * - Accepts image files only.
 * - Streams each proof to Cloudinary and returns proof metadata.
 */

const debug = require("../utils/debug");
const { v2: cloudinary } = require("cloudinary");

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || "",
  api_key: process.env.CLOUDINARY_API_KEY || "",
  api_secret: process.env.CLOUDINARY_API_SECRET || "",
});

const ALLOWED_IMAGE_EXTENSIONS = [
  "png",
  "jpg",
  "jpeg",
  "webp",
];
const ALLOWED_IMAGE_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/jpg",
  "image/webp",
  "application/octet-stream",
];

const SERVICE_NAME = "CLOUDINARY";
const OPERATION_UPLOAD = "task_progress_proof_upload";
const REQUEST_INTENT = "Upload task progress proof images";

function assertCloudinaryConfig() {
  const hasConfig =
    !!process.env.CLOUDINARY_CLOUD_NAME &&
    !!process.env.CLOUDINARY_API_KEY &&
    !!process.env.CLOUDINARY_API_SECRET;

  if (!hasConfig) {
    throw new Error("Cloudinary credentials are not configured");
  }
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
  return parts.length > 1
    ? parts.pop().trim()
    : "";
}

function resolveMimeType(file) {
  const mimetype = (file?.mimetype || "")
    .toString()
    .trim()
    .toLowerCase();
  if (
    mimetype &&
    mimetype !== "application/octet-stream"
  ) {
    return mimetype;
  }

  const extension = normalizeExtension(
    file?.originalname,
  );
  switch (extension) {
    case "png":
      return "image/png";
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "webp":
      return "image/webp";
    default:
      return mimetype || "image/jpeg";
  }
}

function assertImageFile(file) {
  const extension = normalizeExtension(
    file?.originalname,
  );
  const mimetype = (file?.mimetype || "")
    .toString()
    .trim()
    .toLowerCase();
  const hasAllowedExtension =
    ALLOWED_IMAGE_EXTENSIONS.includes(
      extension,
    );
  const hasAllowedMimeType =
    ALLOWED_IMAGE_MIME_TYPES.includes(
      mimetype,
    );

  if (!hasAllowedExtension && !hasAllowedMimeType) {
    throw new Error("Unsupported proof format");
  }
}

function logCloudinaryFailure({
  businessId,
  taskId,
  error,
}) {
  debug("TASK PROGRESS PROOF: upload failed", {
    service: SERVICE_NAME,
    operation: OPERATION_UPLOAD,
    request_intent: REQUEST_INTENT,
    businessId,
    taskId,
    http_status: error?.http_code || error?.status || null,
    provider_error_code: error?.code || null,
    provider_error_message:
      error?.message || error?.error?.message || "Unknown provider error",
  });
}

async function uploadTaskProgressProofImages({
  businessId,
  taskId,
  staffId,
  workDate,
  files,
}) {
  debug("TASK PROGRESS PROOF: upload request", {
    businessId,
    taskId,
    staffId,
    workDate:
      workDate instanceof Date ?
        workDate.toISOString()
      : (workDate || "").toString(),
    fileCount: Array.isArray(files) ? files.length : 0,
  });

  if (!businessId) {
    throw new Error("Business scope is required");
  }
  if (!taskId) {
    throw new Error("Task id is required");
  }
  if (!Array.isArray(files) || files.length === 0) {
    throw new Error("Proof files are required");
  }

  assertCloudinaryConfig();

  const workDateKey =
    workDate instanceof Date ?
      workDate.toISOString().split("T")[0]
    : (workDate || "").toString().trim();
  const safeWorkDateKey = workDateKey || "undated";
  const safeStaffId = (staffId || "").toString().trim() || "unassigned";
  const folder = [
    "gafexpress",
    "task-progress-proofs",
    businessId,
    taskId,
    safeStaffId,
    safeWorkDateKey,
  ].join("/");

  try {
    const uploadedProofs = [];
    for (const file of files) {
      if (!file || !file.buffer || !file.buffer.length) {
        throw new Error("Proof file is required");
      }
      assertImageFile(file);

      const uploadResult = await new Promise(
        (resolve, reject) => {
          const stream = cloudinary.uploader.upload_stream(
            {
              folder,
              resource_type: "image",
              allowed_formats: ALLOWED_IMAGE_EXTENSIONS,
            },
            (error, result) => {
              if (error) return reject(error);
              return resolve(result);
            },
          );
          stream.end(file.buffer);
        },
      );

      uploadedProofs.push({
        url: uploadResult.secure_url,
        publicId: uploadResult.public_id || "",
        filename: file.originalname || "",
        mimeType: resolveMimeType(file),
        sizeBytes: file.size || 0,
      });
    }

    debug("TASK PROGRESS PROOF: upload success", {
      businessId,
      taskId,
      proofCount: uploadedProofs.length,
    });

    return uploadedProofs;
  } catch (error) {
    logCloudinaryFailure({
      businessId,
      taskId,
      error,
    });
    throw error;
  }
}

module.exports = {
  uploadTaskProgressProofImages,
};
