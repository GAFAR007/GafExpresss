/**
 * utils/chat_constants.js
 * -----------------------
 * WHAT:
 * - Shared chat constants for message types, attachment limits, and socket events.
 *
 * WHY:
 * - Keeps chat rules consistent across services, controllers, and sockets.
 * - Prevents magic strings/numbers drifting between frontend and backend.
 *
 * HOW:
 * - Exposes enums + limit values for reuse in chat models + services.
 * - Centralizes event names for Socket.IO emit/subscribe.
 */

// WHY: Use a single source for chat conversation types.
const CHAT_CONVERSATION_TYPES = {
  DIRECT: 'direct',
  GROUP: 'group',
};

// WHY: Standardize message types so parsing stays predictable.
const CHAT_MESSAGE_TYPES = {
  TEXT: 'text',
  ATTACHMENT: 'attachment',
  SYSTEM: 'system',
};

// WHY: Keep attachment type names consistent for validation.
const CHAT_ATTACHMENT_TYPES = {
  IMAGE: 'image',
  DOCUMENT: 'document',
};

// WHY: Centralize size limits to avoid inline magic numbers.
const CHAT_LIMITS = {
  MAX_IMAGE_BYTES: 10 * 1024 * 1024,
  MAX_DOCUMENT_BYTES: 20 * 1024 * 1024,
  MAX_TEXT_LENGTH: 4000,
  MAX_TITLE_LENGTH: 120,
};

// WHY: Enumerate supported mime types for validation.
const CHAT_ATTACHMENT_MIME_TYPES = {
  IMAGE: ['image/jpeg', 'image/png', 'image/webp'],
  DOCUMENT: [
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ],
};

// WHY: Keep event names in one place to avoid typos.
const CHAT_SOCKET_EVENTS = {
  MESSAGE_NEW: 'message:new',
  MESSAGE_READ: 'message:read',
  CONVERSATION_JOIN: 'conversation:join',
  CONVERSATION_LEAVE: 'conversation:leave',
  ERROR: 'chat:error',
};

module.exports = {
  CHAT_CONVERSATION_TYPES,
  CHAT_MESSAGE_TYPES,
  CHAT_ATTACHMENT_TYPES,
  CHAT_ATTACHMENT_MIME_TYPES,
  CHAT_LIMITS,
  CHAT_SOCKET_EVENTS,
};
