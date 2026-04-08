/**
 * utils/production_draft_presence.constants.js
 * --------------------------------------------
 * WHAT:
 * - Shared Socket.IO event names for production draft presence.
 *
 * WHY:
 * - Keeps frontend and backend room updates aligned.
 * - Prevents draft-presence typos from drifting across files.
 */

// WHY: Namespace draft presence events so they do not collide with chat.
const PRODUCTION_DRAFT_PRESENCE_EVENTS = {
  JOIN: "production:draft:presence:join",
  LEAVE: "production:draft:presence:leave",
  UPDATE: "production:draft:presence:update",
  ERROR: "production:draft:presence:error",
};

// WHY: Keep draft rooms grouped under one predictable namespace.
const PRODUCTION_DRAFT_PRESENCE_ROOM_PREFIX = "production:draft:";

module.exports = {
  PRODUCTION_DRAFT_PRESENCE_EVENTS,
  PRODUCTION_DRAFT_PRESENCE_ROOM_PREFIX,
};
