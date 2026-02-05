# Agent Instructions

This file defines non-negotiable rules for any AI agent, coding assistant, or automated helper
working on the GafExpress codebase.

Violating these rules means **STOP and ASK**, not guessing.

---

## Non-negotiable workflow

1. Work ONE step at a time (no large code dumps).
2. Never change the existing folder structure.
3. Do not rename or move files unless explicitly requested.
4. Always keep imports consistent with the current architecture.
5. Prefer small, safe, reversible changes.

If unsure → **STOP and ASK**.

---

## Architecture respect rules

The existing architecture is intentional.

- Do not improve structure.
- Do not simplify by merging layers.
- Do not introduce new patterns without approval.
- Follow the current flow exactly.

---

## Layer direction rules (strict)

Imports must flow downward only:

presentation → application → domain → data

### Forbidden

- UI importing API clients directly.
- Domain importing Flutter, Riverpod, HTTP, or Express.
- Data importing presentation logic.

If a change violates this → **STOP**.

---

## Code style requirements (must follow)

Every new or edited file must include:

- File header documentation:
  - WHAT the file does
  - WHY it exists
  - HOW it works
- Inline comments explaining WHY each step exists.
- Debug logs at key boundaries.

No exceptions.

---

## Theme usage rules (mandatory)

- Always use theme tokens (`Theme.of(context)`, `ColorScheme`, `TextTheme`, `AppColors`) for UI colors.
- Never hardcode colors in widgets, except for status colors defined in `AppColors`.
- Status colors must be chosen to work across classic/dark/business themes (no low-contrast or theme-breaking colors).

---

## Debug logging standard (baseline)

Logs must include:

- Screen `build()` execution
- User actions (button taps, form submissions)
- API request start / success / failure
- Route navigation events

NEVER log:

- passwords
- access tokens
- secrets
- raw credentials

---

## Mandatory diagnostic logging (non-negotiable)

Generic logs are forbidden.

If an agent logs an error without explaining **what failed, why it failed, and what to do next**,
that agent has violated this contract.

### Forbidden logs

- "request failed"
- "verification failed"
- "Google error"
- "API error { status: 400 }"
- Logs containing only:
  - HTTP status
  - Exception name
  - Boolean success / failure

These logs are not acceptable.

---

## Required logging for all external API calls

Every external API call MUST log the following on failure:

- Service name
- Operation name
- Request intent (business purpose)
- Sanitised request context:
  - country
  - source
  - presence of optional fields
- HTTP status
- Provider error code (if available)
- Provider error message / body (sanitised)
- Failure classification
- Resolution hint (next action)

If any of the above is missing → **STOP and ASK**.

---

## Failure classification (mandatory)

Every failure MUST be classified as one of:

- INVALID_INPUT
- MISSING_REQUIRED_FIELD
- COUNTRY_UNSUPPORTED
- POSTAL_CODE_MISMATCH
- PROVIDER_REJECTED_FORMAT
- AUTHENTICATION_ERROR
- RATE_LIMITED
- PROVIDER_OUTAGE
- UNKNOWN_PROVIDER_ERROR

UNKNOWN_PROVIDER_ERROR is a last resort and must include justification.

---

## Required error log shape (example)

---

## 4.1) Global alignment rule (MANDATORY)

All AGENTS.md files MUST work together and stay consistent.

If you add a new cross-cutting rule here, you MUST mirror it in:

- `frontend/AGENTS.md`
- `backend/AGENTS.md`

If there is a conflict → **STOP and ASK**.

---

## 4.2) Global safety + performance rule (MANDATORY)

All changes must optimize for:

- **Safety** (no secrets, no unsafe defaults)
- **Security** (least privilege, scoped access, sanitised logs)
- **Scalability** (avoid N+1, add indexes, batch operations)
- **Performance** (fast UI, minimal lag, small payloads)

If a change risks any of the above → **STOP and ASK**.

---

## 5️⃣ How to guarantee ZERO lag (important rules)

If you follow these, chat will feel instant:

### Backend rules

- Never do AI inside socket events.
- Never upload files via socket.
- Save message → emit → handle receipts async.
- Index `conversationId` + `createdAt`.

### Frontend rules

- Optimistic UI (show message immediately).
- Socket only for sync, not rendering logic.
- Batch read receipts.

---

## Retry and fallback rules

Retries are NOT automatic.

After a failure, the agent MUST log one of:

- retry_allowed: true (with reason)
- retry_skipped: true (with reason)

Blind retries are forbidden.

---

## Accountability clause (critical)

If an agent cannot explain **why** a request failed, it must **STOP and ASK**.

- Guessing is forbidden.
- Masking failures behind status codes is forbidden.
- Silencing provider errors is forbidden.

---

## Multi-platform requirements

- Must work on Web, Android, and iOS.
- Avoid dart:io in UI or presentation layers.
- Use platform abstraction (`platform_info_*`) for platform-only code.
- No platform assumptions in shared logic.

---

## API contract rules

Backend currently returns:

- `register` → `{ user }`
- `login` → `{ message, user }`

Rules:

- Token may be missing.
- AuthSession.token must remain nullable.
- UI must not assume authentication state.
- Never fake missing backend features.

---

## Modularity enforcement

### File responsibility rule

A file must:

- do one thing
- affect one feature
- be reusable unchanged

If a file grows too large → split it.

---

### Extract-before-expand rule

Before adding logic:

- check if similar logic exists
- extract shared logic first
- reuse it

Duplicated logic is forbidden.

---

### Widget size rule (frontend)

- Widgets must be ≤ 150 lines.
- Business logic does not live in widgets.
- Widgets compose; controllers decide.

---

### Function scope rule

A function must:

- do one action
- have one responsibility
- be explainable in one sentence

If the explanation needs “and” → split the function.

---

## No inline magic

Forbidden inline:

- hardcoded strings
- magic numbers
- raw JSON parsing
- route names

Use:

- constants
- models
- mappers
- route definitions

---

## API boundary rules

- Parse API responses once.
- Map to models once.
- UI consumes models only.
- UI must never handle raw JSON.

---

## Change size rules

Every change must be:

- reviewable in under 5 minutes
- revertible in one commit
- testable immediately

If not → break it down further.

---

## Stop conditions (critical)

STOP immediately if:

- folder renames are required
- file placement is unclear
- more than 500 lines are about to be written
- behaviour is ambiguous

Ask for clarification instead of guessing.

---

## Decision order (mandatory)

When uncertain:

1. Explain intent.
2. Propose file placement.
3. Confirm data flow.
4. Then write code.

Skipping steps is not allowed.

---

## Guiding principle

Clarity beats cleverness.  
If code is impressive but hard to read, it is wrong.

---

## Authority

If this file conflicts with:

- intuition
- speed
- AI optimisation

This file wins.
