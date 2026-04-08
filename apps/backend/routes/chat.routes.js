/**
 * routes/chat.routes.js
 * ---------------------
 * WHAT:
 * - Chat REST routes for conversations, messages, and attachments.
 *
 * WHY:
 * - Keeps chat endpoints isolated and easy to protect with auth middleware.
 * - Enables Socket.IO to focus only on realtime events.
 *
 * HOW:
 * - All routes require auth.
 * - Attachments use multer memory storage for Cloudinary streaming.
 */

const express = require('express');
const multer = require('multer');
const { requireAuth } = require('../middlewares/auth.middleware');
const chatController = require('../controllers/chat.controller');
const { CHAT_LIMITS } = require('../utils/chat_constants');

const router = express.Router();

// WHY: Store uploads in memory so Cloudinary can stream buffers.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: CHAT_LIMITS.MAX_DOCUMENT_BYTES,
  },
});

// WHY: Conversation list + creation endpoints.
router.get('/conversations', requireAuth, chatController.listConversations);
router.post('/conversations', requireAuth, chatController.createConversation);
router.get(
  '/conversations/:conversationId',
  requireAuth,
  chatController.getConversationDetail
);

// WHY: Message history is paginated per conversation.
router.get(
  '/conversations/:conversationId/messages',
  requireAuth,
  chatController.listMessages
);

// WHY: Message send is REST-first to guarantee persistence.
router.post('/messages', requireAuth, chatController.sendMessage);

// WHY: Batch read receipts for efficient updates.
router.post('/messages/read', requireAuth, chatController.markMessagesRead);

// WHY: Attachments must be uploaded via REST (not sockets).
router.post(
  '/attachments',
  requireAuth,
  upload.single('file'),
  chatController.uploadChatAttachment
);

module.exports = router;
