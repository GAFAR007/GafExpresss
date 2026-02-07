# GafExpress Backend — Agent Instructions (Node.js / Express / MongoDB)

Clean Architecture-ish · Controllers/Services · Mongoose · Multi-tenant (Business scoped)

This file defines **non-negotiable rules** for any AI agent / coding assistant / helper
working inside **apps/backend**.

Violating these rules means: **STOP and ASK** (do not guess).

---

## 0) Goal of the backend

Build a **production-grade** API that is:

- **Correct** (source of truth for all business stats)
- **Secure** (auth, roles, data scoping, least privilege)
- **Multi-tenant safe** (no cross-business leaks)
- **Observable** (step-by-step logs, actionable errors)
- **Stable** (small changes, easy rollback, predictable behavior)
- **Frontend-friendly** (clean responses, consistent error shapes)
- **Heavily documented** (comments guide every step)

---

## 1) Non-negotiable workflow

1. Work **ONE step at a time** (no big refactors / code dumps).
2. Never change the existing folder structure.
3. Do not rename/move files unless explicitly requested.
4. Prefer small, safe, reversible changes.
5. After each change:
   - run and verify immediately
   - state what changed, why, and how to test

If unsure → **STOP and ASK**.

---

## 2) Comments & documentation rules (MOST IMPORTANT)

Comments are mandatory and must guide every step.

### 2.1 File header docs (MANDATORY)

Every new/edited file MUST start with:

- WHAT this file does
- WHY it exists
- HOW it works

### 2.2 Inline comment rule (MANDATORY)

Add inline comments explaining **WHY** each step exists (not just WHAT).
Comments must exist at every boundary:

- route entry
- controller validation
- service orchestration
- DB queries
- external provider calls
- error mapping + response shaping

Forbidden:

- silent complex logic with no commentary
- “obvious-only” comments without WHY

---

## 3) Layering & direction rules (STRICT)

Keep responsibilities separated:

**routes → controllers → services → models (Mongoose)**

- routes: wiring only
- controllers: validation + orchestration only
- services: business logic + orchestration
- models: schema + hooks only

Forbidden:

- routes calling database directly
- controllers doing complex calculations
- services returning raw Mongoose docs without sanitising/mapping where needed
- leaking internal stack traces to clients

If a change violates this → **STOP**.

---

## 4) Multi-tenant & business scoping (NON-NEGOTIABLE)

Most endpoints are business-scoped. Every business-scoped request MUST enforce:

- resolve business context (`businessId`)
- validate user has access to that business
- filter queries by businessId
- never allow cross-business reads/writes

Forbidden:

- any query missing `{ businessId: ... }` for business-owned resources
- accepting businessId from client without permission checks

If scoping is unclear → **STOP and ASK**.

---

## 5) Auth & roles (MANDATORY)

Backend roles expected:

- `business_owner`
- `staff`
- `tenant`
- `customer`

Rules:

- never infer role from request shape
- enforce permissions in middleware and/or service guards
- use **403** for forbidden actions (unless explicitly designed otherwise)

Never log:

- passwords, tokens, secrets
- full PII payloads

---

## 6) API contract rules (MANDATORY)

General response rules:

- consistent JSON shapes
- never return raw stack traces
- error messages must be safe and UI-ready

Source of truth rules:
Backend is the source of truth for:

- stats / analytics / totals
- revenue aggregation
- depreciation (when implemented)
- projections (when implemented)

Frontend must not compute business totals → backend provides endpoints.

---

## 7) Logging rules (MANDATORY — step-by-step, no guessing)

Logs must show exactly where failures happen.

### 7.1 Required step checkpoints (MANDATORY)

For every request, log these checkpoints:

1. ROUTE_IN
2. AUTH_OK / AUTH_FAIL
3. VALIDATION_OK / VALIDATION_FAIL
4. SERVICE_START
5. DB_QUERY_START / DB_QUERY_OK / DB_QUERY_FAIL
6. PROVIDER_CALL_START / PROVIDER_CALL_OK / PROVIDER_CALL_FAIL (if external)
7. SERVICE_OK / SERVICE_FAIL
8. CONTROLLER_RESPONSE_OK / CONTROLLER_RESPONSE_FAIL

Missing checkpoints are not acceptable.

### 7.2 Log payload (MANDATORY)

Every log MUST include:

- requestId
- route (method + path)
- step (checkpoint name)
- layer (route/controller/service/model/provider/middleware)
- operation (e.g. `TenantApprove`, `PaystackVerify`, `InventoryAdjust`)
- intent (business purpose)
- businessId presence (true/false) + businessId if safe
- userRole (never tokens)

On failures, also include:

- classification
- error_code
- resolution_hint

Never log secrets/tokens or full PII.

---

## 7.3) Global alignment rule (MANDATORY)

All AGENTS.md files MUST work together and stay consistent.

If you add a new cross-cutting rule here, you MUST mirror it in:

- `AGENTS.md`
- `frontend/AGENTS.md`

If there is a conflict → **STOP and ASK**.

---

## 7.4) Global safety + performance rule (MANDATORY)

All changes must optimize for:

- **Safety** (no secrets, no unsafe defaults)
- **Security** (least privilege, scoped access, sanitised logs)
- **Scalability** (avoid N+1, add indexes, batch operations)
- **Performance** (fast UI, minimal lag, small payloads)

If a change risks any of the above → **STOP and ASK**.

---

## AI-Assisted Business Philosophy (MANDATORY)

This product uses AI as a **business assistant**, not a form filler.

AI exists to:
- reduce friction
- lower expertise barriers
- translate human intent into structured business plans
- make business workflows easier, faster, and more accessible

AI must NOT:
- behave like a strict validator during draft or ideation stages
- require users to pre-define every business entity before assistance
- block creativity due to missing structured data

### Core Principle
Humans express **intent**.
AI proposes **structure**.
Humans **review, adjust, and confirm**.

---

## AI Intelligence Loop (MANDATORY — LONG-TERM)

AI in this product is not a one-off feature or isolated assistant.

AI MUST operate as a continuous intelligence loop:

1. Observe business data (events, metrics, outcomes)
2. Compare expected vs actual performance
3. Detect patterns, gaps, and trends over time
4. Propose improvements, plans, or adjustments
5. Track progress against confirmed targets
6. Repeat as new data arrives

### Key rules

- AI suggestions MUST be grounded in real business data.
- AI MUST prefer trends over snapshots (time matters).
- AI MUST explain *why* a suggestion is being made.
- AI MUST surface confidence/assumptions when data is incomplete.
- AI MUST improve accuracy as historical data grows.

### Forbidden

- One-off AI outputs with no follow-up tracking
- Suggestions with no measurable outcome
- AI acting without comparing past performance

### Design intent

AI should feel like:
“A business partner that learns your operation over time.”

Not:
“A chatbot that answers isolated questions.”

---

## Expected & Target Data (MANDATORY AI BEHAVIOR)

For any business entity that represents effort, cost, duration, or output,
AI SHOULD attempt to propose expected or target values.

Examples include (but are not limited to):
- expected_yield
- expected_cost
- expected_duration
- monthly_revenue_target
- inventory_turnover_target
- production_output_target

### Rules

- Expected values MUST be marked as AI-generated.
- Expected values MUST be editable by the user.
- Expected values MUST NOT be required to save drafts.
- Expected values MUST NOT auto-commit without confirmation.

### Purpose

Expected data exists to:
- enable comparison (expected vs actual)
- unlock progress tracking
- support future insights and recommendations

### Forbidden

- Treating expected values as facts
- Blocking workflows due to missing expected data
- Generating expectations without explaining assumptions

---

## AI Draft Generation Rules

### Required Human Context (Minimum)
For AI draft generation, require ONLY:
- a real-world anchor (e.g. Estate, Location, Business Unit)

Everything else MAY be inferred or proposed by AI.

### AI Is Allowed to Propose
When generating drafts, AI is explicitly allowed to:
- create draft products or services
- estimate timelines and durations
- propose start and end dates
- define phases, steps, and tasks
- infer quantities (e.g. acreage, units, scale) from natural language
- surface risks and assumptions

All AI-created entities must be:
- clearly marked as AI-generated
- editable by the user
- uncommitted until human confirmation

---

## Validation Timing Rules

### Draft Phase
- Validation must be **soft**
- Missing fields should guide, not block
- Errors should be framed as "more context helps us help you"

### Final Save / Commit Phase
- Validation becomes **strict**
- All required business entities must exist
- AI suggestions must be explicitly accepted or modified

AI drafts must NEVER auto-persist without human confirmation.

---

## Error & UX Tone

AI-related messages must:
- feel supportive, not punitive
- explain what additional context would improve results
- never blame the user for missing data

Prefer:
"We need a little more context to tailor this plan."

Avoid:
"Missing required fields."

---

## Feature Design Guidance (IMPORTANT)

When designing new features:
- Always ask: "How can AI reduce user effort here?"
- Prefer intent-based inputs over rigid forms
- If a human can describe it in words, AI should help structure it
- AI should optimize for accessibility, not expert-only workflows

If a feature can be made easier with AI, it should be.

---

## 7.5) ZERO‑lag chat rules (MANDATORY)

If you follow these, chat will feel instant:

### Backend rules

- Never do AI inside socket events.
- Never upload files via socket.
- Save message → emit → handle receipts async.
- Index `conversationId` + `createdAt`.

### Frontend rules (for shared awareness)

- Optimistic UI (show message immediately).
- Socket only for sync, not rendering logic.
- Batch read receipts.

---

## 8) Failure classification + specificity rules (MANDATORY)

### 8.1 Allowed classification list (FIXED)

- INVALID_INPUT
- MISSING_REQUIRED_FIELD
- COUNTRY_UNSUPPORTED
- POSTAL_CODE_MISMATCH
- PROVIDER_REJECTED_FORMAT
- AUTHENTICATION_ERROR
- RATE_LIMITED
- PROVIDER_OUTAGE
- UNKNOWN_PROVIDER_ERROR

### 8.2 Specificity rule (MANDATORY)

Classification alone is NOT enough.
Every error MUST include:

- classification (one of the 8)
- error_code (precise)
- step (exact checkpoint)
- resolution_hint (exact next action)

error_code style: `FEATURE_OPERATION_REASON`

If you can’t name a precise error_code → **STOP and ASK**.

---

## 9) Input validation (MANDATORY)

Validate inputs at controller boundary (or dedicated validator).
Never allow invalid inputs to reach DB/provider.

Forbidden:

- silent coercion that changes business meaning
- “best effort” parsing for money/quantities/ids

---

## 10) Money, units, and precision (MANDATORY — keep consistent forever)

### 10.1 Minor units only (MANDATORY)

All money values MUST be stored and computed as **integer minor units**:

- NGN → kobo
- GBP → pence
- USD → cents

Do NOT use floats/decimals for money.

### 10.2 Validation (MANDATORY)

Incoming money MUST pass:

- `typeof value === "number"` AND `Number.isFinite(value)`
- `Number.isInteger(value) === true`

Reject floats like `12.34`.

### 10.3 Where validation must happen (MANDATORY)

- controller/service boundary (always)
- schema level if feasible (Mongoose validator)

### 10.4 Failure handling (MANDATORY)

If not integer minor units:

- classification: INVALID_INPUT
- step: VALIDATION_FAIL
- error_code: operation-specific
- resolution_hint: “Send integer minor units only”

Examples:

- PRODUCT_CREATE_PRICE_NOT_INTEGER_MINOR_UNIT
- ORDER_CREATE_TOTAL_NOT_INTEGER_MINOR_UNIT
- PAYMENT_AMOUNT_NOT_INTEGER_MINOR_UNIT

### 10.5 Naming clarity (MANDATORY)

In comments + errors: prefer **minor units** (currency-agnostic).
If multi-currency later: store minor units + currency code.

---

## 11) Stock mutation + inventory history (MANDATORY — delta-first + track over time)

### 11.1 Delta-first rule (MANDATORY)

Normal stock changes MUST be applied as **delta adjustments**, not overwrites.

Examples:

- restock: `+50`
- sale: `-3`
- damaged: `-2`
- return: `+1`
- correction: `+/-N` with explicit reason

Forbidden in normal flows:

- setting `stock = newValue` directly

WHY:

- preserves intent
- enables trends (“how often restocked”)
- enables audit (“who changed stock and why”)

### 11.2 Inventory history record (MANDATORY)

Every stock delta MUST write an immutable history record:

- businessId
- itemId/productId
- delta (integer)
- beforeStock (integer)
- afterStock (integer)
- reason (enum-like): RESTOCK | SALE | DAMAGE | RETURN | ADJUSTMENT
- actor: userId + role only
- timestamp (UTC ISO)

### 11.3 Where history is written (MANDATORY)

Service layer, after DB success.

Forbidden:

- routes/controllers writing history
- writing history before the stock update succeeds

### 11.4 Overwrite exception (RESTRICTED)

Direct overwrite allowed ONLY for:

- migration
- inventory audit fix
- admin correction

Overwrite MUST:

- be role-protected
- require explicit reasonText and/or reason=ADJUSTMENT
- still write history with delta=(new-old)

Suggested error codes:

- INVENTORY_OVERWRITE_FORBIDDEN_FOR_ROLE
- INVENTORY_OVERWRITE_MISSING_REASON
- INVENTORY_DELTA_NOT_INTEGER
- INVENTORY_RESULT_NEGATIVE_BLOCKED

### 11.5 Inventory events (MANDATORY)

Every inventory change MUST also write an event:

- INVENTORY_RESTOCKED
- INVENTORY_SOLD
- INVENTORY_DAMAGED
- INVENTORY_RETURNED
- INVENTORY_ADJUSTED
- INVENTORY_OVERWRITTEN

---

## 12) Analytics & stats (MANDATORY)

Stats must be computed in backend.
Prefer returning:

- totals
- breakdowns
- trends (time series)

---

## 13) External providers (MANDATORY)

Provider rules (e.g., Google Places, Paystack):

- never expose provider keys to frontend
- validate + rate-limit inputs
- provider failures MUST log:
  - step, classification, error_code, resolution_hint (sanitised)

---

## 14) Error response shape (MANDATORY)

All error responses must be:

```json
{
  "message": "Safe message",
  "classification": "INVALID_INPUT | MISSING_REQUIRED_FIELD | RATE_LIMITED | ...",
  "error_code": "FEATURE_OPERATION_REASON",
  "requestId": "req_123",
  "resolution_hint": "Next action"
}

Rules:

never return stack traces

never return raw provider payloads

sanitise provider errors

15) Data shaping & sanitisation (MANDATORY)

Return only what UI needs.
Never return password hashes, reset tokens, secrets, internal flags.

16) Pagination & filtering (MANDATORY)

Large list endpoints must support pagination + filtering + sorting.
Forbidden: unbounded endpoints returning thousands of rows.

17) Change size rule (MANDATORY — realistic but safe)

This is a safety rule, not a handcuff.

Allowed:

A “feature slice” may touch many files (even 10–20) if it is one goal and follows the same pattern
(routes/controllers/services/models + tests + docs), with no folder moves.

STOP and ASK if:

schema change impacts multiple features (breaking change risk)

changing API response shapes already used by UI

touching auth/role/scoping logic

adding a new dependency

refactoring “for cleanliness” instead of feature need

unclear business decision or data contract

18) Decision order (MANDATORY)

When uncertain:

explain intent

propose placement

confirm data flow + auth/scoping

write smallest safe change

19) Definition of “done”

A backend feature is done only when:

business scoping enforced

permissions enforced

inputs validated

consistent response shape

logs include checkpoints

verified with test steps (Postman/curl)

Data Tracking + Time-Series + Future GPT Readiness (MANDATORY)
20) Metrics contract (MANDATORY)

All analytics endpoints MUST return a stable metrics contract:

{
  "range": { "from": "YYYY-MM-DD", "to": "YYYY-MM-DD", "timezone": "UTC|..." },
  "kpis": { "exampleTotalCount": 0, "exampleMoneyMinorTotal": 0 },
  "breakdowns": { "exampleByStatus": { "PAID": 0, "PENDING": 0 } },
  "trends": { "series": [{ "date": "YYYY-MM-DD", "value": 0 }] },
  "notes": ["optional backend notes"],
  "availability": { "missing": ["kpiNameNotSupportedYet"] }
}


Rules:

KPI names consistent across endpoints

money values integer minor units

counts integers

dates ISO 8601

if missing, use availability.missing (never fake values)

21) Event tracking (MANDATORY)

Every business-important state change MUST write an event record.

Where:

service layer, after DB success

Event must include:

businessId

eventType (central constant)

entityType + entityId

timestamp

actor (userId + role)

minimal before/after (sanitised)

Event types must be centralised. Minimum list includes:

PRODUCT_CREATED / PRODUCT_UPDATED / PRODUCT_ARCHIVED

ORDER_CREATED / ORDER_STATUS_CHANGED

PAYMENT_RECORDED

ASSET_CREATED / ASSET_UPDATED

STAFF_ASSIGNED

DOCUMENT_UPLOADED

TENANT_CONTACT_VERIFIED / TENANT_APPROVED / TENANT_ACTIVATED

INVENTORY_RESTOCKED / INVENTORY_SOLD / INVENTORY_DAMAGED / INVENTORY_RETURNED / INVENTORY_ADJUSTED / INVENTORY_OVERWRITTEN

PRODUCTION_STAGE_CHANGED (farm, when implemented)

Event write failure policy:

core operation may still succeed

but MUST log precise failure:

classification + error_code + resolution_hint + correct step

22) Time matters (MANDATORY)

Analytics endpoints MUST:

accept time ranges (7d, 30d, ytd, custom)

store timestamps in UTC

return range always

support group buckets (day/week/month) where needed

23) GPT readiness (MANDATORY — safe by design)

AI later can only use:

aggregated metrics (kpis/breakdowns/trends)

sanitised events

user-approved docs/notes

AI must never:

invent missing stats

guess totals

provide financial/legal advice

act without confirmation on sensitive actions

Insights must be traceable to stored KPIs/trends/events.

Payments (Paystack) — safe payment flow (MANDATORY)
24) Paystack flow replicates Order flow pattern (MANDATORY)

Implement Paystack using the same architecture pattern as Orders:
routes → controllers → services → models, with:

strict validation at controller boundary

controller orchestration only

service orchestration + business logic

step checkpoints logs

events written after DB success

24.1 Never trust frontend for payment success (MANDATORY)

Forbidden:

marking paid because client says “success”

using only frontend callback

Rule:
Payment becomes FINAL only after backend verification via Paystack API
and/or verified webhook confirmation.

24.2 Payment lifecycle (MANDATORY)

State machine:

INITIATED → PENDING → SUCCEEDED/FAILED → (CANCELLED/EXPIRED optional)

Forbidden:

skipping states

setting SUCCEEDED without verification

24.3 Create payment intent (MANDATORY)

On init:

create Payment record:

businessId

payerType (tenant/customer)

linked entity (orderId/tenantId/invoiceId)

amountMinor (integer minor units)

currency

provider=PAYSTACK

providerReference (when available)

status=INITIATED

createdBy (userId + role)

idempotencyKey (if supported)

24.4 Webhook verification (MANDATORY)

Webhook MUST:

verify signature

reject invalid signature:

classification=AUTHENTICATION_ERROR

error_code=PAYSTACK_WEBHOOK_INVALID_SIGNATURE

process only explicit event types

be idempotent (ignore duplicates by eventId/reference)

24.5 Backend verify endpoint (MANDATORY)

Verify MUST:

call Paystack verify transaction API

confirm amount matches amountMinor

confirm currency matches

confirm provider status is success
Then:

mark Payment SUCCEEDED

write ledger/history entry

write PAYMENT_RECORDED event

update linked entity (order paid / rent paid / tenant activation)

Mismatch examples:

PAYSTACK_VERIFY_AMOUNT_MISMATCH

PAYSTACK_VERIFY_CURRENCY_MISMATCH

Execution Plan — Tenant + Staff + Farm (Backlog & Build Order)
A) Plan rules (MANDATORY)

Backend first for lifecycle (verify/approve/pay/activate). Frontend never fakes success.

Build in vertical slices: endpoints → tests → minimal UI wiring → verify → next.

No invented metrics. Missing KPIs must be omitted or marked missing.

Money minor units everywhere.

Inventory delta-first + history + events.

B) Tenant lifecycle (Estate) — backend-driven state machine

States:

PENDING_VERIFICATION → VERIFIED → APPROVED → ACTIVE

Rules:

ACTIVE only after Paystack verification and/or verified webhook

never allow frontend to mark ACTIVE

Events:

TENANT_CONTACT_VERIFIED

TENANT_APPROVED

PAYMENT_RECORDED

TENANT_ACTIVATED

Done means:

Postman/curl can move tenant through all states with correct logs + events

C) Phase 0 — Freeze the contracts (DO FIRST)

Minimum endpoints:

POST /business/tenants/:tenantId/verify-contact

POST /business/tenants/:tenantId/approve

POST /business/tenants/:tenantId/payment-intent

POST /payments/paystack/webhook

GET /payments/paystack/verify?reference=...

GET /business/tenants/me/summary

GET /business/staff/me/summary

Rule:

endpoints return UI-ready shapes, not raw DB dumps

D) Phase 1 — Paystack-safe tenant activation (backend first)

implement Payment record + state machine

idempotent webhook

verify endpoint

on SUCCEEDED: ledger + events + tenant activate

E) Phase 2 — Tenant summary payload (backend first)

GET /business/tenants/me/summary returns:

status (verification/approval/payment)

kpis (balanceMinor, arrearsMinor, nextDueDate, lastPayment)

history grouped by month

documents recent max 5

maintenance openCount + recent max 5

suggestions backend-driven

availability.missing for anything not supported

F) Phase 3 — Staff summary payload + permissions

GET /business/staff/me/summary returns:

role-appropriate KPIs

recent activity (events)

assigned tasks (if supported)

drilldowns

G) Phase 4 — Farm vertical

Inventory:

delta adjustments only

history records + events

analytics: low stock, movement trends, restock frequency

Assets:

store purchaseCostMinor, purchaseDate, usefulLifeMonths

depreciation computed backend-only later

events for create/update

Production:

later phase: stages + events + projections backend computed later

H) Codex usage rule (MANDATORY — realistic request format)

Every request to the agent MUST be one slice:

Goal (1 sentence)

Scope boundary (what is IN / OUT)

Endpoints to implement/change (if any)

Required logs (checkpoint steps)

Required error_codes (2–6 specific ones)

“Done means” verification steps (Postman/curl)

Important:

Do NOT force “max 1–2 files”.

A slice may touch many files when needed (route/controller/service/model/tests/docs),
as long as it stays within one feature goal and remains reviewable.
```
