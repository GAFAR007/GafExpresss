/**
 * apps/backend/services/business_invite.service.js
 * ------------------------------------------------
 * WHAT:
 * - Issues and accepts business invite links.
 *
 * WHY:
 * - Lets owners invite staff/tenants by email with audit trails.
 * - Stores hashed tokens so raw invite tokens never hit the DB.
 *
 * HOW:
 * - Generates a random token and hashes it with SHA-256.
 * - Persists invite + expiry.
 * - Sends email via email.service.
 */

const crypto = require('crypto');
const debug = require('../utils/debug');
const BusinessInvite = require('../models/BusinessInvite');
const { sendEmail } = require('./email.service');

const INVITE_TTL_DAYS = Number(
  process.env.BUSINESS_INVITE_TTL_DAYS || 7,
);
const FRONTEND_BASE_URL =
  (process.env.FRONTEND_BASE_URL || 'http://localhost:5173').trim();

function generateToken() {
  return crypto.randomBytes(24).toString('hex');
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function buildInviteLink(token) {
  return `${FRONTEND_BASE_URL}/#/business-invite?token=${token}`;
}

function inviteExpiryDate() {
  const now = new Date();
  now.setDate(now.getDate() + INVITE_TTL_DAYS);
  return now;
}

async function cancelActiveInvites({
  businessId,
  inviteeEmail,
}) {
  await BusinessInvite.updateMany(
    {
      businessId,
      inviteeEmail,
      status: 'pending',
    },
    {
      $set: {
        status: 'cancelled',
        cancelledAt: new Date(),
      },
    },
  );
}

async function createInvite({
  businessId,
  inviterId,
  inviteeEmail,
  role,
  estateAssetId,
}) {
  if (!inviteeEmail) {
    throw new Error('Invite email is required');
  }

  const normalizedEmail =
    inviteeEmail.toString().trim().toLowerCase();

  if (!['staff', 'tenant'].includes(role)) {
    throw new Error('Role must be staff or tenant');
  }

  if (role === 'tenant' && !estateAssetId) {
    throw new Error('Estate asset is required for tenant invites');
  }

  const token = generateToken();
  const tokenHash = hashToken(token);
  const tokenExpiresAt = inviteExpiryDate();

  await cancelActiveInvites({
    businessId,
    inviteeEmail: normalizedEmail,
  });

  const invite = await BusinessInvite.create({
    businessId,
    inviterId,
    inviteeEmail: normalizedEmail,
    role,
    estateAssetId: estateAssetId || null,
    tokenHash,
    tokenExpiresAt,
    status: 'pending',
  });

  const inviteLink = buildInviteLink(token);
  debug('BUSINESS INVITE: created', {
    inviteId: invite._id,
    role,
    expiresAt: tokenExpiresAt,
  });

  await sendEmail({
    toEmail: normalizedEmail,
    subject: 'You have been invited to a business team',
    text: `You have been invited to join a business team. Accept your invite: ${inviteLink}`,
    html: `
      <p>You have been invited to join a business team.</p>
      <p><a href="${inviteLink}">Accept your invite</a></p>
      <p>This link expires in ${INVITE_TTL_DAYS} days.</p>
    `,
  });

  return {
    invite,
    inviteLink,
  };
}

async function getInviteByToken(token) {
  if (!token) {
    throw new Error('Invite token is required');
  }

  const tokenHash = hashToken(token);
  const invite = await BusinessInvite.findOne({
    tokenHash,
    status: 'pending',
  });

  if (!invite) {
    throw new Error('Invite not found');
  }

  if (invite.tokenExpiresAt < new Date()) {
    invite.status = 'expired';
    await invite.save();
    throw new Error('Invite has expired');
  }

  return invite;
}

async function markInviteAccepted({
  invite,
  acceptedBy,
}) {
  invite.status = 'accepted';
  invite.acceptedBy = acceptedBy;
  invite.acceptedAt = new Date();
  await invite.save();
}

module.exports = {
  createInvite,
  getInviteByToken,
  markInviteAccepted,
  buildInviteLink,
};
