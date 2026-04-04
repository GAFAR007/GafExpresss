/**
 * models/ChatAttachment.js
 * ------------------------
 * WHAT:
 * - Stores metadata for files attached to chat messages.
 *
 * WHY:
 * - Keeps Cloudinary details in one place for safe deletes and previews.
 * - Separates large attachment metadata from message payloads.
 *
 * HOW:
 * - Stores file type, mime type, size, and Cloudinary URL/public id.
 * - Links back to conversation + message for traceability.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');
const {
  CHAT_ATTACHMENT_TYPES,
} = require('../utils/chat_constants');

debug('Loading ChatAttachment model...');

const chatAttachmentSchema = new mongoose.Schema(
  {
    // WHY: Scopes attachment to the owning conversation.
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ChatConversation',
      required: [true, 'Conversation id is required'],
      index: true,
    },
    // WHY: Links attachment to the owning message.
    messageId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ChatMessage',
      default: null,
      index: true,
    },
    // WHY: Tracks who uploaded the attachment.
    uploadedByUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'Uploader id is required'],
      index: true,
    },
    // WHY: Attachment type drives preview handling.
    type: {
      type: String,
      enum: Object.values(CHAT_ATTACHMENT_TYPES),
      required: [true, 'Attachment type is required'],
    },
    // WHY: Mime type is needed for validation + previews.
    mimeType: {
      type: String,
      trim: true,
      required: [true, 'Mime type is required'],
    },
    // WHY: Size is used for validation and UI.
    sizeBytes: {
      type: Number,
      required: [true, 'Attachment size is required'],
      min: 0,
    },
    // WHY: Public URL for rendering in UI.
    url: {
      type: String,
      trim: true,
      required: [true, 'Attachment url is required'],
    },
    // WHY: Cloudinary public id for cleanup.
    publicId: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Filename helps UI display and downloads.
    filename: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Image metadata for previews (optional).
    width: {
      type: Number,
      default: null,
    },
    height: {
      type: Number,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

// WHY: Speed up lookup by conversation + message.
chatAttachmentSchema.index({ conversationId: 1, messageId: 1 });

module.exports = mongoose.model(
  'ChatAttachment',
  chatAttachmentSchema,
);
