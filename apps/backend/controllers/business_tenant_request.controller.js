/**
 * apps/backend/controllers/business_tenant_request.controller.js
 * ---------------------------------------------------------------
 * WHAT:
 * - HTTP controller for public tenant request links and submissions.
 *
 * WHY:
 * - Keeps the link creation and public intake flow out of the giant business
 *   controller while reusing the same tenant application storage.
 *
 * HOW:
 * - Authenticated business actors create a shareable request link.
 * - Public callers load the link context and submit identity + unit details.
 */

const debug = require('../utils/debug');
const {
  resolveBusinessContext,
} = require('../services/business_context.service');
const businessTenantRequestService = require('../services/business_tenant_request.service');

async function createTenantRequestLink(req, res) {
  debug('BUSINESS TENANT REQUEST: create link - entry', {
    actorId: req.user?.sub,
    hasEstate: Boolean(req.body?.estateAssetId),
  });

  try {
    const { actor, businessId } = await resolveBusinessContext(req.user.sub);
    const estateAssetId = req.body?.estateAssetId?.toString().trim() || '';

    if (!estateAssetId) {
      return res.status(400).json({
        error: 'Estate asset is required for tenant request links',
      });
    }

    const result = await businessTenantRequestService.createTenantRequestLink({
      businessId,
      inviterId: actor._id,
      estateAssetId,
    });

    debug('BUSINESS TENANT REQUEST: create link - success', {
      actorId: actor._id,
      estateAssetId,
      requestLinkId: result.requestLink._id,
    });

    return res.status(201).json({
      message: 'Tenant request link created successfully',
      requestLink: result.requestLinkUrl,
      requestLinkId: result.requestLink._id,
      estateAssetId,
    });
  } catch (error) {
    debug('BUSINESS TENANT REQUEST: create link - error', error?.message);
    return res.status(400).json({
      error: error?.message || 'Unable to create tenant request link',
    });
  }
}

async function getTenantRequestLinkContext(req, res) {
  debug('BUSINESS TENANT REQUEST: get context - entry', {
    hasToken: Boolean(req.params?.token),
  });

  try {
    const context = await businessTenantRequestService.getTenantRequestLinkContext({
      token: req.params?.token?.toString().trim() || '',
    });

    return res.status(200).json({
      message: 'Tenant request link fetched successfully',
      ...context,
    });
  } catch (error) {
    debug('BUSINESS TENANT REQUEST: get context - error', error?.message);
    return res.status(400).json({
      error: error?.message || 'Unable to load tenant request link',
    });
  }
}

async function submitTenantRequest(req, res) {
  debug('BUSINESS TENANT REQUEST: submit - entry', {
    hasToken: Boolean(req.params?.token),
    hasFile: Boolean(req.file),
  });

  try {
    const result = await businessTenantRequestService.submitTenantRequest({
      token: req.params?.token?.toString().trim() || '',
      payload: req.body,
      file: req.file,
    });

    return res.status(201).json({
      message: 'Tenant request submitted successfully',
      application: result.application,
      requestLinkId: result.requestLink._id,
    });
  } catch (error) {
    debug('BUSINESS TENANT REQUEST: submit - error', error?.message);
    return res.status(400).json({
      error: error?.message || 'Unable to submit tenant request',
    });
  }
}

module.exports = {
  createTenantRequestLink,
  getTenantRequestLinkContext,
  submitTenantRequest,
};
