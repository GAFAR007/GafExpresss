/**
 * services/profile_image.service.js
 * ----------------------------------
 * WHAT:
 * - Uploads a user profile image to Cloudinary and saves the URL.
 *
 * WHY:
 * - Keep media uploads centralized and auditable in the backend.
 *
 * HOW:
 * - Validates input, uploads to Cloudinary, updates user profileImageUrl.
 */

const debug = require('../utils/debug');
const { v2: cloudinary } = require('cloudinary');
const User = require('../models/User');

// WHY: Configure Cloudinary once using env credentials.
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || '',
  api_key: process.env.CLOUDINARY_API_KEY || '',
  api_secret: process.env.CLOUDINARY_API_SECRET || '',
});

// WHY: Accept only image MIME types for profile pictures.
const ALLOWED_MIME_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
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

async function uploadProfileImage({ userId, file }) {
  debug('PROFILE IMAGE: upload request', { userId });

  if (!userId) {
    throw new Error('Missing userId');
  }

  if (!file) {
    throw new Error('Image file is required');
  }

  if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
    throw new Error('Unsupported image format');
  }

  assertCloudinaryConfig();

  const uploadResult = await new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: 'gafexpress/profile',
        resource_type: 'image',
        transformation: [
          { width: 512, height: 512, crop: 'fill', gravity: 'face' },
        ],
      },
      (error, result) => {
        if (error) return reject(error);
        return resolve(result);
      },
    );
    stream.end(file.buffer);
  });

  debug('PROFILE IMAGE: uploaded', {
    userId,
    publicId: uploadResult.public_id,
  });

  const user = await User.findByIdAndUpdate(
    userId,
    { $set: { profileImageUrl: uploadResult.secure_url } },
    { new: true, runValidators: true },
  ).select('-passwordHash');

  if (!user) {
    throw new Error('User not found');
  }

  debug('PROFILE IMAGE: saved', { userId });

  return {
    profileImageUrl: user.profileImageUrl,
  };
}

module.exports = {
  uploadProfileImage,
};
