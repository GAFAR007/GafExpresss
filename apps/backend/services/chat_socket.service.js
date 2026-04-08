/**
 * services/chat_socket.service.js
 * --------------------------------
 * WHAT:
 * - Socket.IO handlers for chat events (join, leave, read).
 *
 * WHY:
 * - Keeps realtime logic out of controllers per architecture rules.
 * - Centralizes access validation before joining rooms or emitting.
 *
 * HOW:
 * - Authenticates sockets with JWT.
 * - Validates conversation access via chat.service.
 * - Emits events through a shared socket server instance.
 */

const jwt = require("jsonwebtoken");
const debug = require("../utils/debug");
const chatService = require("./chat.service");
const {
  CHAT_SOCKET_EVENTS,
} = require("../utils/chat_constants");

// WHY: Store the active Socket.IO instance for emits.
let socketServer = null;

// WHY: Use a dedicated log tag for socket operations.
const LOG_TAG = "CHAT_SOCKET";

function parseSocketToken(socket) {
  // WHY: Support both auth payload and Authorization header.
  const authToken =
    socket?.handshake?.auth?.token;
  const headerToken =
    socket?.handshake?.headers
      ?.authorization;
  const candidate =
    authToken || headerToken || "";
  if (candidate.startsWith("Bearer ")) {
    return candidate
      .replace("Bearer ", "")
      .trim();
  }
  return candidate.trim();
}

function verifySocketToken(token) {
  // WHY: Keep socket auth aligned with REST auth rules.
  return jwt.verify(
    token,
    process.env.JWT_SECRET,
  );
}

function emitSocketError(
  socket,
  message,
) {
  // WHY: Notify the client without exposing sensitive details.
  socket.emit(
    CHAT_SOCKET_EVENTS.ERROR,
    { message },
  );
}

function registerChatSocket(io) {
  // WHY: Save the io instance for emit helpers.
  socketServer = io;

  io.on("connection", (socket) => {
    const token =
      parseSocketToken(socket);
    if (!token) {
      debug(LOG_TAG, {
        step: "AUTH_FAIL",
        reason: "missing_token",
      });
      emitSocketError(
        socket,
        "Authentication required",
      );
      socket.disconnect();
      return;
    }

    let decoded;
    try {
      decoded =
        verifySocketToken(token);
    } catch (error) {
      debug(LOG_TAG, {
        step: "AUTH_FAIL",
        reason: "invalid_token",
        error: error?.message,
      });
      emitSocketError(
        socket,
        "Invalid authentication token",
      );
      socket.disconnect();
      return;
    }

    socket.data.user = {
      id: decoded.sub,
      role: decoded.role,
    };

    debug(LOG_TAG, {
      step: "AUTH_OK",
      userId: decoded.sub,
      role: decoded.role,
    });

    socket.on(
      CHAT_SOCKET_EVENTS.CONVERSATION_JOIN,
      async (payload) => {
        // WHY: Ensure only participants can join conversation rooms.
        const conversationId =
          payload?.conversationId;
        if (!conversationId) {
          emitSocketError(
            socket,
            "Conversation id is required",
          );
          return;
        }

        try {
          await chatService.ensureParticipant(
            {
              conversationId,
              userId:
                socket.data.user.id,
              context: {
                route:
                  "socket:conversation:join",
                requestId: socket.id,
                userRole:
                  socket.data.user.role,
              },
            },
          );
          socket.join(conversationId);
          debug(LOG_TAG, {
            step: "JOIN_OK",
            conversationId,
            userId: socket.data.user.id,
          });
        } catch (error) {
          debug(LOG_TAG, {
            step: "JOIN_FAIL",
            conversationId,
            userId: socket.data.user.id,
            reason: error?.message,
            resolution_hint:
              error?.resolutionHint,
          });
          emitSocketError(
            socket,
            "Access denied for this conversation",
          );
        }
      },
    );

    socket.on(
      CHAT_SOCKET_EVENTS.CONVERSATION_LEAVE,
      (payload) => {
        // WHY: Allow clients to stop receiving room updates.
        const conversationId =
          payload?.conversationId;
        if (!conversationId) {
          emitSocketError(
            socket,
            "Conversation id is required",
          );
          return;
        }
        socket.leave(conversationId);
        debug(LOG_TAG, {
          step: "LEAVE_OK",
          conversationId,
          userId: socket.data.user.id,
        });
      },
    );

    socket.on(
      CHAT_SOCKET_EVENTS.MESSAGE_READ,
      async (payload) => {
        // WHY: Persist read receipts and notify the room.
        const conversationId =
          payload?.conversationId;
        const messageIds =
          payload?.messageIds || [];
        if (
          !conversationId ||
          messageIds.length === 0
        ) {
          emitSocketError(
            socket,
            "Conversation and message ids are required",
          );
          return;
        }

        try {
          await chatService.markMessagesRead(
            {
              userId:
                socket.data.user.id,
              conversationId,
              messageIds,
              context: {
                route:
                  "socket:message:read",
                requestId: socket.id,
                userRole:
                  socket.data.user.role,
              },
            },
          );
          socket
            .to(conversationId)
            .emit(
              CHAT_SOCKET_EVENTS.MESSAGE_READ,
              {
                conversationId,
                messageIds,
                readBy:
                  socket.data.user.id,
                readAt:
                  new Date().toISOString(),
              },
            );
        } catch (error) {
          debug(LOG_TAG, {
            step: "READ_FAIL",
            conversationId,
            userId: socket.data.user.id,
            reason: error?.message,
            resolution_hint:
              error?.resolutionHint,
          });
          emitSocketError(
            socket,
            "Unable to mark messages as read",
          );
        }
      },
    );
  });
}

function emitMessageCreated({
  conversationId,
  message,
}) {
  // WHY: Keep socket emission centralized and guarded.
  if (
    !socketServer ||
    !conversationId ||
    !message
  )
    return;
  socketServer
    .to(conversationId)
    .emit(
      CHAT_SOCKET_EVENTS.MESSAGE_NEW,
      {
        conversationId,
        message,
      },
    );
}

function emitMessageRead({
  conversationId,
  messageIds,
  readBy,
}) {
  // WHY: Allow REST controllers to notify read receipts.
  if (!socketServer || !conversationId)
    return;
  socketServer
    .to(conversationId)
    .emit(
      CHAT_SOCKET_EVENTS.MESSAGE_READ,
      {
        conversationId,
        messageIds,
        readBy,
        readAt:
          new Date().toISOString(),
      },
    );
}

module.exports = {
  registerChatSocket,
  emitMessageCreated,
  emitMessageRead,
};
