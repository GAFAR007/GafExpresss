/**
 * services/product_image.service.js
 * ---------------------------------
 * WHAT:
 * - Uploads product images to Cloudinary and stores gallery URLs.
 *
 * WHY:
 * - Products need multiple images while keeping a primary imageUrl.
 * - Centralizes upload logic and validation for auditability.
 *
 * HOW:
 * - Validates input, uploads to Cloudinary, updates Product imageUrls.
 * - Sets imageUrl if missing and logs audit events.
 */

const debug = require('../utils/debug');
const { v2: cloudinary } = require('cloudinary');
const Product = require('../models/Product');
const { writeAuditLog } = require('../utils/audit');
const { writeAnalyticsEvent } = require('../utils/analytics');

// WHY: Configure Cloudinary once using env credentials.
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || '',
  api_key: process.env.CLOUDINARY_API_KEY || '',
  api_secret: process.env.CLOUDINARY_API_SECRET || '',
});

// WHY: Accept only image MIME types for product uploads.
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

async function uploadProductImage({ businessId, productId, file, actor }) {
  debug('PRODUCT IMAGE: upload request', { businessId, productId });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  if (!productId) {
    throw new Error('Product id is required');
  }

  if (!file) {
    throw new Error('Image file is required');
  }

  if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
    throw new Error('Unsupported image format');
  }

  assertCloudinaryConfig();

  // WHY: Ensure the product belongs to the business before uploading.
  const product = await Product.findOne({ _id: productId, businessId });
  if (!product) {
    throw new Error('Product not found');
  }

  const uploadResult = await new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: `gafexpress/products/${businessId}`,
        resource_type: 'image',
        transformation: [{ width: 1024, height: 1024, crop: 'limit' }],
      },
      (error, result) => {
        if (error) return reject(error);
        return resolve(result);
      },
    );
    stream.end(file.buffer);
  });

  debug('PRODUCT IMAGE: uploaded', {
    productId,
    publicId: uploadResult.public_id,
  });

  // WHY: Preserve existing gallery items and append the new one.
  const nextImages = [...(product.imageUrls ?? []), uploadResult.secure_url];
  product.imageUrls = nextImages;
  // WHY: Keep Cloudinary ids for safe deletes later.
  const nextAssets = [
    ...(product.imageAssets ?? []),
    {
      url: uploadResult.secure_url,
      publicId: uploadResult.public_id || '',
    },
  ];
  product.imageAssets = nextAssets;

  // WHY: Keep a primary imageUrl for legacy clients and home listings.
  product.imageUrl = uploadResult.secure_url;

  product.updatedBy = actor?.id ?? product.updatedBy;
  await product.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: 'product_image_upload',
    entityType: 'product',
    entityId: product._id,
    message: `Product image uploaded: ${product.name}`,
  });

  // WHY: Analytics events keep media activity visible in dashboards.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: 'product_image_uploaded',
    entityType: 'product',
    entityId: product._id,
    metadata: { imageCount: product.imageUrls?.length ?? 0 },
  });

  return product;
}

module.exports = {
  uploadProductImage,
  deleteProductImage,
};

async function deleteProductImage({
  businessId,
  productId,
  imageUrl,
  actor,
}) {
  debug('PRODUCT IMAGE: delete request', { businessId, productId });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  if (!productId) {
    throw new Error('Product id is required');
  }

  if (!imageUrl || imageUrl.trim().length === 0) {
    throw new Error('Image URL is required');
  }

  // WHY: Ensure the product belongs to the business before deleting.
  const product = await Product.findOne({ _id: productId, businessId });
  if (!product) {
    throw new Error('Product not found');
  }

  const existingUrls = product.imageUrls ?? [];
  if (!existingUrls.includes(imageUrl)) {
    throw new Error('Image not found on product');
  }

  const existingAssets = product.imageAssets ?? [];
  const matchedAsset = existingAssets.find(
    (asset) => asset.url === imageUrl
  );

  let cloudinaryDeleted = false;
  let cloudinaryError = null;

  if (matchedAsset?.publicId) {
    try {
      assertCloudinaryConfig();
      await cloudinary.uploader.destroy(matchedAsset.publicId, {
        resource_type: 'image',
      });
      cloudinaryDeleted = true;
    } catch (error) {
      cloudinaryError = error?.message || 'Cloudinary delete failed';
      debug('PRODUCT IMAGE: Cloudinary delete failed', {
        productId,
        publicId: matchedAsset.publicId,
        error: cloudinaryError,
      });
    }
  } else {
    debug('PRODUCT IMAGE: no publicId for delete', { productId });
  }

  // WHY: Remove the url from gallery + assets for UI consistency.
  product.imageUrls = existingUrls.filter((url) => url !== imageUrl);
  product.imageAssets = existingAssets.filter((asset) => asset.url !== imageUrl);

  // WHY: Keep primary imageUrl in sync with gallery.
  if (product.imageUrl === imageUrl) {
    product.imageUrl = product.imageUrls[0] || '';
  }

  product.updatedBy = actor?.id ?? product.updatedBy;
  await product.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: 'product_image_delete',
    entityType: 'product',
    entityId: product._id,
    message: `Product image deleted: ${product.name}`,
    metadata: {
      cloudinaryDeleted,
      cloudinaryError,
    },
  });

  // WHY: Track removals for gallery analytics and audits.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: 'product_image_deleted',
    entityType: 'product',
    entityId: product._id,
    metadata: {
      cloudinaryDeleted,
      imageCount: product.imageUrls?.length ?? 0,
    },
  });

  return { product, cloudinaryDeleted, cloudinaryError };
}
