/**
 * apps/backend/services/email.service.js
 * ------------------------------------------------
 * WHAT:
 * - Sends transactional emails via configured provider.
 *
 * WHY:
 * - Centralizes email delivery for invites + future workflows.
 * - Keeps provider-specific handling out of controllers.
 *
 * HOW:
 * - Uses EMAIL_PROVIDER (console|brevo).
 * - Falls back to console logs in dev environments.
 */

const debug = require('../utils/debug');

const EMAIL_PROVIDER =
  process.env.EMAIL_PROVIDER || 'console';
const BREVO_API_KEY =
  process.env.BREVO_API_KEY || '';
const EMAIL_FROM =
  process.env.EMAIL_FROM || '';
const EMAIL_FROM_NAME =
  process.env.EMAIL_FROM_NAME || 'Office Store';

async function sendEmail({
  toEmail,
  subject,
  html,
  text,
}) {
  if (!toEmail || !subject) {
    throw new Error('Missing email recipient or subject');
  }

  if (EMAIL_PROVIDER === 'console') {
    debug('EMAIL: console provider', {
      toEmail,
      subject,
      preview: text || html || '',
    });
    return { status: 'console' };
  }

  if (EMAIL_PROVIDER !== 'brevo') {
    throw new Error(
      `Unsupported EMAIL_PROVIDER: ${EMAIL_PROVIDER}`,
    );
  }

  if (!BREVO_API_KEY || !EMAIL_FROM) {
    throw new Error('Brevo email provider missing configuration');
  }

  const payload = {
    sender: {
      email: EMAIL_FROM,
      name: EMAIL_FROM_NAME,
    },
    to: [{ email: toEmail }],
    subject,
    htmlContent: html || text || '',
    textContent: text || undefined,
  };

  const response = await fetch(
    'https://api.brevo.com/v3/smtp/email',
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'api-key': BREVO_API_KEY,
      },
      body: JSON.stringify(payload),
    },
  );

  debug('EMAIL: Brevo status', {
    status: response.status,
    toEmail,
  });

  if (!response.ok) {
    throw new Error('Brevo email send failed');
  }

  return { status: response.status };
}

module.exports = {
  sendEmail,
};
