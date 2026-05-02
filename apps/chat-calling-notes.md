# Chat Calling Notes

## Current Status

1. 1-to-1 in-app voice calling has been implemented on top of the existing chat flow.
2. The current version uses WebRTC audio with Socket.IO signaling and backend call-session tracking.
3. Manual end-to-end testing is still pending.

## Known Production Caveats

1. This is internet audio only. It does not place calls over the phone network.
2. The current setup is STUN-only WebRTC. Before broad rollout, add TURN or move media handling to a managed provider such as LiveKit or Agora for better reliability on restrictive networks.
3. Background ringing and push-notification handling are not included yet, so incoming calls currently depend on the app already being open and connected.
4. The frontend now keeps voice calling off by default on hosted environments unless `ENABLE_CHAT_CALLING=true` is passed at build time. Turn it on only after the backend exposes `/chat/calls` in that environment.

## Before Rollout

1. Run manual testing for outgoing, incoming, decline, missed, reconnect, and permission-denied scenarios.
2. Add TURN or migrate media transport to LiveKit or Agora.
3. Add background ringing and push support if calls must work when the app is not active.
