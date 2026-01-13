# Agent Instructions (Codex / AI Helpers)

## Non-negotiable workflow

1. Work ONE step at a time (no huge code dumps).
2. Never change the existing folder structure.
3. Do not rename/move files unless explicitly requested.
4. Always keep imports consistent with the current structure.
5. Prefer small safe changes, then run + verify.

## Code style requirements (must follow)

Every new/edited file must include:

- File header docs: WHAT / WHY / HOW
- Lots of inline comments explaining WHY each step exists
- Debug logs at key points so we know where it breaks

## Debug logging standard

- Use `AppDebug.log(TAG, message, extra: {...})` where available.
- Logs must include:
  - screen build()
  - button taps
  - API request start/end (never password/token)
  - route navigation events
- NEVER log:
  - passwords
  - access tokens

## Multi-platform requirements

- Must work on Web, Android, and iOS.
- Avoid `dart:io` in UI/presentation layers.
- Use platform abstraction (`platform_info_*`) for platform-only code.

## API contract rules

- Backend currently returns:
  - register: { user } (no token)
  - login: { message, user } (token may be added later)
- Frontend must tolerate missing token:
  - `AuthSession.token` remains nullable until JWT is implemented.

## When uncertain

- Ask for the current file content or screenshot BEFORE changing structure.
- Prefer minimal edits that preserve the current architecture.
