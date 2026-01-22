/**
 * apps/backend/controllers/business.controller.js
 * ------------------------------------------------
 * WHAT:
 * - Handles business-owner + staff HTTP requests.
 *
 * WHY:
 * - Provides tenant-scoped product, order, asset, and role management.
 *
 * HOW:
 * - Resolves business scope from the authenticated user.
 * - Delegates to business services and logs audit actions.
 */

const debug = require('../utils/debug');
const User = require('../models/User');
const businessProductService = require('../services/business.product.service');
const businessOrderService = require('../services/business.order.service');
const businessAssetService = require('../services/business.asset.service');
const businessAnalyticsService = require('../services/business.analytics.service');
const productImageService = require('../services/product_image.service');
const { writeAuditLog } = require('../utils/audit');

// WHY: Resolve actor + businessId once per request.
async function getBusinessContext(userId) {
  const actor = await User.findById(userId).select(
    'role businessId isNinVerified email'
  );

  if (!actor) {
    throw new Error('User not found');
  }

  if (!actor.businessId) {
    throw new Error('Business scope is not configured for this user');
  }

  return {
    actor,
    businessId: actor.businessId,
  };
}

async function createProduct(req, res) {
  debug('BUSINESS CONTROLLER: createProduct - entry', {
    actorId: req.user?.sub,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const product = await businessProductService.createProduct({
      data: req.body,
      actor: { id: actor._id, role: actor.role },
      businessId,
    });

    return res.status(201).json({
      message: 'Product created successfully',
      product,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: createProduct - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function getAllProducts(req, res) {
  debug('BUSINESS CONTROLLER: getAllProducts - entry', {
    actorId: req.user?.sub,
    query: req.query,
  });

  try {
    const { businessId } = await getBusinessContext(req.user.sub);
    const result = await businessProductService.getAllProducts({
      businessId,
      query: req.query,
    });

    return res.status(200).json({
      message: 'Products fetched successfully',
      ...result,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: getAllProducts - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function getProductById(req, res) {
  debug('BUSINESS CONTROLLER: getProductById - entry', {
    actorId: req.user?.sub,
    productId: req.params.id,
  });

  try {
    const { businessId } = await getBusinessContext(req.user.sub);
    const product = await businessProductService.getProductById({
      businessId,
      id: req.params.id,
    });

    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }

    return res.status(200).json({
      message: 'Product fetched successfully',
      product,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: getProductById - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function updateProduct(req, res) {
  debug('BUSINESS CONTROLLER: updateProduct - entry', {
    actorId: req.user?.sub,
    productId: req.params.id,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const product = await businessProductService.updateProduct({
      businessId,
      id: req.params.id,
      updates: req.body,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Product updated successfully',
      product,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: updateProduct - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function softDeleteProduct(req, res) {
  debug('BUSINESS CONTROLLER: softDeleteProduct - entry', {
    actorId: req.user?.sub,
    productId: req.params.id,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const product = await businessProductService.softDeleteProduct({
      businessId,
      id: req.params.id,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Product soft deleted successfully',
      product,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: softDeleteProduct - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function restoreProduct(req, res) {
  debug('BUSINESS CONTROLLER: restoreProduct - entry', {
    actorId: req.user?.sub,
    productId: req.params.id,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const product = await businessProductService.restoreProduct({
      businessId,
      id: req.params.id,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Product restored successfully',
      product,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: restoreProduct - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function uploadProductImage(req, res) {
  debug('BUSINESS CONTROLLER: uploadProductImage - entry', {
    actorId: req.user?.sub,
    productId: req.params.id,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const product = await productImageService.uploadProductImage({
      businessId,
      productId: req.params.id,
      file: req.file,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Product image uploaded successfully',
      product,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: uploadProductImage - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function deleteProductImage(req, res) {
  debug('BUSINESS CONTROLLER: deleteProductImage - entry', {
    actorId: req.user?.sub,
    productId: req.params.id,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const imageUrl =
      req.body?.imageUrl?.toString() || req.query?.imageUrl?.toString();

    const result = await productImageService.deleteProductImage({
      businessId,
      productId: req.params.id,
      imageUrl,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Product image deleted successfully',
      product: result.product,
      cloudinaryDeleted: result.cloudinaryDeleted,
      cloudinaryError: result.cloudinaryError,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: deleteProductImage - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function getOrders(req, res) {
  debug('BUSINESS CONTROLLER: getOrders - entry', {
    actorId: req.user?.sub,
    query: req.query,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const result = await businessOrderService.getBusinessOrders({
      businessId,
      userId: actor._id,
      query: req.query,
    });

    return res.status(200).json({
      message: 'Orders fetched successfully',
      ...result,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: getOrders - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function updateOrderStatus(req, res) {
  debug('BUSINESS CONTROLLER: updateOrderStatus - entry', {
    actorId: req.user?.sub,
    orderId: req.params.id,
    status: req.body?.status,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const { status } = req.body;

    if (!status) {
      return res.status(400).json({ error: 'Status is required' });
    }

    const order = await businessOrderService.updateOrderStatus({
      businessId,
      orderId: req.params.id,
      status,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Order status updated successfully',
      order,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: updateOrderStatus - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function createAsset(req, res) {
  debug('BUSINESS CONTROLLER: createAsset - entry', {
    actorId: req.user?.sub,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const asset = await businessAssetService.createAsset({
      businessId,
      actor: { id: actor._id, role: actor.role },
      payload: req.body,
    });

    return res.status(201).json({
      message: 'Asset created successfully',
      asset,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: createAsset - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function getAssets(req, res) {
  debug('BUSINESS CONTROLLER: getAssets - entry', {
    actorId: req.user?.sub,
    query: req.query,
  });

  try {
    const { businessId } = await getBusinessContext(req.user.sub);
    const result = await businessAssetService.getAssets({
      businessId,
      query: req.query,
    });

    return res.status(200).json({
      message: 'Assets fetched successfully',
      ...result,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: getAssets - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function updateAsset(req, res) {
  debug('BUSINESS CONTROLLER: updateAsset - entry', {
    actorId: req.user?.sub,
    assetId: req.params.id,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const asset = await businessAssetService.updateAsset({
      businessId,
      assetId: req.params.id,
      payload: req.body,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Asset updated successfully',
      asset,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: updateAsset - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function softDeleteAsset(req, res) {
  debug('BUSINESS CONTROLLER: softDeleteAsset - entry', {
    actorId: req.user?.sub,
    assetId: req.params.id,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const asset = await businessAssetService.softDeleteAsset({
      businessId,
      assetId: req.params.id,
      actor: { id: actor._id, role: actor.role },
    });

    return res.status(200).json({
      message: 'Asset soft deleted successfully',
      asset,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: softDeleteAsset - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function updateUserRole(req, res) {
  debug('BUSINESS CONTROLLER: updateUserRole - entry', {
    actorId: req.user?.sub,
    targetUserId: req.params.id,
    role: req.body?.role,
  });

  try {
    const { actor, businessId } = await getBusinessContext(req.user.sub);
    const targetUser = await User.findById(req.params.id);

    if (!targetUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (actor.role !== 'business_owner') {
      return res.status(403).json({ error: 'Only business owners can update roles' });
    }

    const allowedRoles = ['staff', 'tenant'];
    if (!allowedRoles.includes(req.body.role)) {
      return res.status(400).json({
        error: `Role must be one of: ${allowedRoles.join(', ')}`,
      });
    }

    // WHY: Only NIN-verified customers can be promoted to staff/tenant.
    if (!targetUser.isNinVerified) {
      return res.status(400).json({
        error: 'User must be NIN verified before role upgrade',
      });
    }

    if (targetUser.role !== 'customer') {
      return res.status(400).json({
        error: 'Only customers can be upgraded to staff or tenant',
      });
    }

    // WHY: Prevent cross-business role assignment.
    if (
      targetUser.businessId &&
      targetUser.businessId.toString() !== businessId.toString()
    ) {
      return res.status(403).json({
        error: 'User belongs to a different business',
      });
    }

    targetUser.role = req.body.role;
    targetUser.businessId = businessId;
    await targetUser.save();

    await writeAuditLog({
      businessId,
      actorId: actor._id,
      actorRole: actor.role,
      action: 'user_role_update',
      entityType: 'user',
      entityId: targetUser._id,
      message: `User promoted to ${targetUser.role}`,
      changes: { role: targetUser.role },
    });

    return res.status(200).json({
      message: 'User role updated successfully',
      user: targetUser,
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: updateUserRole - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function getAnalyticsSummary(req, res) {
  debug('BUSINESS CONTROLLER: analytics summary - entry', {
    actorId: req.user?.sub,
  });

  try {
    const { businessId } = await getBusinessContext(req.user.sub);
    const summary = await businessAnalyticsService.getAnalyticsSummary({
      businessId,
    });

    return res.status(200).json({
      message: 'Analytics summary fetched successfully',
      summary,
      generatedAt: new Date().toISOString(),
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: analytics summary - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

async function getAnalyticsEvents(req, res) {
  debug('BUSINESS CONTROLLER: analytics events - entry', {
    actorId: req.user?.sub,
    query: req.query,
  });

  try {
    const { businessId } = await getBusinessContext(req.user.sub);
    const events = await businessAnalyticsService.getAnalyticsEvents({
      businessId,
      days: req.query?.days,
      eventType: req.query?.eventType,
    });

    return res.status(200).json({
      message: 'Analytics events fetched successfully',
      ...events,
      generatedAt: new Date().toISOString(),
    });
  } catch (err) {
    debug('BUSINESS CONTROLLER: analytics events - error', err.message);
    return res.status(400).json({ error: err.message });
  }
}

module.exports = {
  createProduct,
  getAllProducts,
  getProductById,
  updateProduct,
  softDeleteProduct,
  restoreProduct,
  uploadProductImage,
  deleteProductImage,
  getOrders,
  updateOrderStatus,
  createAsset,
  getAssets,
  updateAsset,
  softDeleteAsset,
  updateUserRole,
  getAnalyticsSummary,
  getAnalyticsEvents,
};
