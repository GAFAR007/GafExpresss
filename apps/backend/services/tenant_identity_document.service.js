/**
 * services/tenant_identity_document.service.js
 * ---------------------------------------------
 * WHAT:
 * - Uploads public tenant identity documents to Cloudinary.
 *
 * WHY:
 * - Public request links need an identity proof upload that is separate from
 *   contact reference documents.
 * - Keeps the public intake flow auditable and storage-backed.
 *
 * HOW:
 * - Validates file payload + MIME type.
 * - Streams to Cloudinary and returns the URL + public id.
 */

const debug = require('../utils/debug');
const { v2: cloudinary } = require('cloudinary');

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || '',
  api_key: process.env.CLOUDINARY_API_KEY || '',
  api_secret: process.env.CLOUDINARY_API_SECRET || '',
});

const ALLOWED_MIME_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/jpg',
];

function assertCloudinaryConfig() {
  const hasConfig =
    !!process.env.CLOUDINARY_CLOUD_NAME &&
    !!process.env.CLOUDINARY_API_KEY &&
    !!process.env.CLOUDINARY_API_SECRET;

  if (!hasConfig) {
    throw new Error('Cloudinary credentials are not configured');
  }
}

async function uploadTenantIdentityDocument({
  businessId,
  file,
  source,
}) {
  debug('TENANT IDENTITY DOC: upload request', {
    businessId,
    source: source || 'tenant_request',
    hasFile: Boolean(file),
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  if (!file) {
    throw new Error('Document file is required');
  }

  if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
    throw new Error('Unsupported document format');
  }

  assertCloudinaryConfig();

  try {
    const uploadResult = await new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        {
          folder: `gafexpress/tenant-identity-documents/${businessId}`,
          resource_type: 'auto',
          allowed_formats: ['pdf', 'png', 'jpg', 'jpeg'],
        },
        (error, result) => {
          if (error) return reject(error);
          return resolve(result);
        },
      );
      stream.end(file.buffer);
    });

    debug('TENANT IDENTITY DOC: upload success', {
      businessId,
      publicId: uploadResult.public_id,
    });

    return {
      url: uploadResult.secure_url,
      publicId: uploadResult.public_id || '',
    };
  } catch (error) {
    debug('TENANT IDENTITY DOC: upload failed', {
      businessId,
      source: source || 'tenant_request',
      error: error?.message,
    });
    throw error;
  }
}

module.exports = {
  uploadTenantIdentityDocument,
};
