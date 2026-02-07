# GafExpress Frontend — Agent Instructions (Flutter)

Clean Architecture · Riverpod · GoRouter · Multi-Platform (Web/iOS/Android)

This file defines **non-negotiable rules** for any AI agent / coding assistant / helper
working inside **apps/frontend**.

Violating these rules means: **STOP and ASK** (do not guess).

---

## 0) Goal of the frontend

Build a **production-grade** Flutter app that is:

- **Fast** and stable on Web + iOS + Android
- **Pleasant** and consistent across **Classic / Dark / Business** themes
- **Data-driven** (clear stats, analytics, and dashboards)
- **Debuggable** (rich logs, clear errors, easy to reproduce issues)
- **Architecture-safe** (strict layering, no shortcuts)
- **Consistent formatting everywhere** (single source of truth)
- **Address UX is first-class** (autocomplete, structured addresses)

---

## 1) Non-negotiable workflow

1. Work **ONE step at a time** (no large refactors / code dumps).
2. Never change the existing folder structure.
3. Do not rename or move files unless explicitly requested.
4. Keep imports consistent with the existing architecture.
5. Prefer small, safe, reversible changes (reviewable in < 5 minutes).
6. After each small change:
   - run and verify immediately
   - log what was changed, why, and how to test it

If unsure → **STOP and ASK**.

---

## 2) Architecture & layer direction (STRICT)

Imports must flow **downward only**:

**presentation → application → domain → data**

### Forbidden

- UI importing API clients directly
- UI handling raw JSON
- Domain importing Flutter / Riverpod / Dio / HTTP
- Data importing presentation logic
- Widgets containing business logic

If a change violates this → **STOP**.

---

## 3) Frontend responsibilities (what belongs where)

### Presentation (UI)

- Screens, widgets, UI states (loading / error / empty / success)
- User interactions (taps, forms)
- Navigation (GoRouter)
- Reads **models only** (never raw JSON)

### Application (controllers / use-cases)

- Orchestrates UI actions (submit, refresh, paginate, confirm)
- Coordinates domain + data
- Contains “what to do next” logic

### Domain (models + rules)

- Pure Dart models + validation rules
- No Flutter imports
- No network code

### Data (API + mapping)

- Dio calls, DTOs, response parsing
- Maps API responses → domain models exactly once

---

## 4) Logging rules (MANDATORY)

Use the existing standard:

`AppDebug.log(TAG, message, extra: {...})`

### Must log

- Screen `build()` execution
- Button taps / user actions (with non-sensitive context)
- Navigation events (from → to)
- API request start / success / failure
- State transitions (loading → success/error)

### Never log

- passwords
- access tokens
- secrets
- raw credentials
- full PII payloads (names/emails/phones should be minimal/sanitised)

### Mandatory diagnostic quality

Generic logs are forbidden.

**On failure**, logs MUST include:

- feature/screen name
- operation name
- intent (business purpose)
- sanitised context (ids allowed, no secrets)
- failure classification (see below)
- “what to do next” hint

#### Failure classification (MANDATORY)

Every failure must be classified as one of:

- INVALID_INPUT
- MISSING_REQUIRED_FIELD
- COUNTRY_UNSUPPORTED
- POSTAL_CODE_MISMATCH
- PROVIDER_REJECTED_FORMAT
- AUTHENTICATION_ERROR
- RATE_LIMITED
- PROVIDER_OUTAGE
- UNKNOWN_PROVIDER_ERROR

UNKNOWN_PROVIDER_ERROR is last resort and must include justification.

---

## 4.1) Global alignment rule (MANDATORY)

All AGENTS.md files MUST work together and stay consistent.

If you add a new cross-cutting rule here, you MUST mirror it in:

- `AGENTS.md`
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

## 4.3) ZERO‑lag chat rules (MANDATORY)

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

## 5) Theme + UI rules (Classic / Dark / Business)

### Mandatory theme usage

- Always use theme tokens: `Theme.of(context)`, `ColorScheme`, `TextTheme`, `AppColors`
- Never hardcode colors in widgets
- Status colors may live in `AppColors` only (and must work in all themes)

### The “3 modes” requirement

The UI must look good and readable in:

- **Classic** (light / friendly)
- **Dark** (not too dark, good contrast)
- **Business** (clean, professional, analytics-first)

#### Contrast rule

All text must remain readable on:

- surfaces
- gradient headers
- cards
- chips/badges
- disabled states

If contrast is questionable → **STOP and ASK**.

---

## 6) UX quality rules (must feel “polished”)

### Consistency

- Consistent spacing/padding across screens
- Consistent card style (radius, elevation/shadow via theme)
- Consistent button sizes and label casing
- Consistent empty/error layouts

### Responsiveness (Web + Mobile)

- Must adapt to wide screens (web) and narrow screens (mobile)
- Avoid fixed widths/heights unless necessary
- Prefer flexible layouts and constraints
- Avoid overflow: test small screens + browser resize

### Accessibility

- Tap targets: ≥ 44px
- Use semantic labels on key icons/buttons
- Avoid low-contrast text in any theme

## 🎨 UI & Visual System Philosophy (MANDATORY — NON-FUNCTIONAL)

This section defines how the app must *feel*, not just how it functions.

The UI must feel:
- Calm, not crowded
- Spacious, not dense
- Intentional, not decorative
- Predictable, not surprising

Target quality: classic, Apple-like.

If a screen feels noisy, busy, playful, or attention-grabbing → it is wrong.
Note: These rules apply to design and layout decisions, not runtime behavior.
UI must remain stable and predictable once rendered.
---

### 1) Visual hierarchy rule (MANDATORY)

Every screen must answer within 3 seconds:
- Where am I?
- What matters most here?
- What can I do next?

Required order:
1. Page title + short helper text
2. Primary KPI or primary action
3. Secondary metrics or content
4. Details, lists, and history

If hierarchy is unclear → STOP and ASK.

---

### 2) Density rule (MANDATORY)

If a screen feels busy:
- remove before adding
- summarise before listing
- collapse before expanding

Long lists without summaries are forbidden.

A user should understand a screen without scrolling.

---

### 3) Navigation philosophy (MANDATORY)

- Bottom navigation is for primary destinations only
- Maximum 4–5 items
- Dashboard may be visually emphasised as the anchor
- Secondary tools (staff, admin, settings) belong behind:
  - Dashboard sections, or
  - Profile

If navigation feels crowded → it is wrong.

---

### 4) Color system rules (MANDATORY)

Color is functional, not decorative.

Colors exist to:
- guide attention
- communicate status
- support hierarchy

Colors must never be added just to “look nice”.

#### 4.1 Color roles (STRICT)

Every color must map to exactly one role:
- Surface (backgrounds, cards, containers)
- Text (primary / secondary / muted)
- Accent (primary CTA, selected navigation)
- Status (success, warning, error)
- Divider / Border (structure only)

If a color does not clearly fit one role → it does not belong.

---

#### 4.2 Accent usage rules (CRITICAL)

- Only ONE accent color per theme
- Accent is used sparingly:
  - selected navigation item
  - primary CTA
- Accent must never be decorative
- Accent must not compete with content

If accent draws attention away from data → STOP.

---

#### 4.3 Status color rules (VERY IMPORTANT)

- Green = success / growth / completion ONLY
- Green must NEVER be the main accent in Business mode
- Status colors must never be reused as accents
- Status colors must work across all themes

If green appears everywhere → it is wrong.

---

### 5) Theme differentiation rules (MANDATORY)

The app supports Classic / Dark / Business modes.

They must feel distinct at a glance.

#### Classic
- Warm, friendly
- Soft surfaces
- Muted accent (green allowed but restrained)

#### Business
- Neutral or cool surfaces
- High contrast text
- Desaturated accent (NOT green)
- Green reserved strictly for positive deltas and success indicators
- Must feel professional, calm, data-focused

#### Dark
- Deep neutral surfaces (not pure black)
- Soft, readable text
- Subtle accent
- No neon or glowing colors

If two modes look similar → the design has failed.

---

### 6) Theme token enforcement (MANDATORY)

All colors MUST come from:
- Theme.of(context)
- ColorScheme
- TextTheme
- AppColors (status colors only)

Forbidden:
- Hardcoded hex colors
- Inline color usage
- Copy-pasted color values

If a new color is needed:
- Explain the role
- Explain why it’s needed
- STOP and ASK

---

### 7) Component visual consistency (MANDATORY)

Reusable components must share:
- spacing rhythm
- border radius
- elevation/shadow (theme-driven)
- typography scale

Cards must feel like containers, not buttons.

---

### 8) Button hierarchy rules (MANDATORY)

- One primary action per screen
- Secondary actions are visually quieter
- Destructive actions are clearly separated

Multiple competing primary buttons are forbidden.

---

### 9) AI-assisted UX alignment (MANDATORY)

AI features must follow the same visual restraint as the rest of the UI.

- AI suggestions must look proposed, not enforced
- AI-generated fields must be clearly labelled
- AI errors must feel supportive, not punitive

Prefer:
“We can generate a better plan with a little more context.”

Avoid:
“Missing required fields.”

---

## 7) “No inline magic” rules

Forbidden inline:

- hardcoded strings (labels, titles, error messages)
- magic numbers (padding, heights, TTLs, thresholds)
- raw JSON parsing
- route strings

Use:

- constants (AppConstants / feature constants)
- models (domain)
- mappers (data)
- router definitions

---

## 8) Widget + file size rules (frontend)

- Widgets must be **≤ 150 lines**
- Business logic does not live in widgets
- Prefer composition: small widgets, controllers decide

### Function scope rule

A function must:

- do one action
- have one responsibility
- be explainable in one sentence

If your explanation needs “and” → split it.

---

## 9) Data & analytics (stats requirement)

The app must support **clear operational stats**, especially for:

- Products (count, active vs archived, stock totals, low-stock alerts)
- Orders (count, revenue, status breakdown, fulfillment pace)
- Assets (operational overview: active / inactive / maintenance)
- Customers (order frequency, spend buckets) _if backend supports it_

### Where analytics calculations happen

- Prefer calculations in **backend** (single source of truth)
- Frontend may compute **lightweight** derived values only from models (e.g., `list.length`)

### Analytics model rule

- UI consumes **domain models only**
- No raw JSON in UI
- Parse and map once in data layer

### Dashboard UX expectations

Every analytics block should have:

- title + short helper text
- a primary number
- context (“last 30 days”, “all time”, etc.)
- “View details” action when relevant
- loading + empty + error states

### Stats availability rule (MANDATORY)

If the backend does not return a KPI/stat yet:

- UI must show **“Coming soon”** (or hide the card if explicitly requested),
- UI must NOT fabricate numbers,
- UI must NOT estimate business stats unless explicitly approved.

---

## 10) Privacy + placeholders (MANDATORY)

If backend user/profile fields are missing:

- DO NOT fall back to hardcoded personal values (name/email/phone)
- Show neutral placeholders or loading indicators
- Make missing backend data obvious

---

## 11) Navigation rules (GoRouter)

- Use route constants (no inline route strings)
- Log navigation events (from → to)
- Deep links must be resilient (web refresh safe)
- If auth is required, use route guards consistently (no bypass)

---

## 12) Network rules (Dio)

- All API calls live in data layer
- Always log request intent (not secrets)
- On failure, log provider response safely (sanitised)
- Never retry blindly:
  - Log either `retry_allowed: true` (with reason) OR `retry_skipped: true` (with reason)

---

## 13) Token + auth rules (current contract)

- Auth token may be nullable depending on backend contract
- UI must not assume authentication state
- Never fake missing backend features
- Never store secrets in logs

---

## 14) Stats UI design guidelines (pleasing UI)

### Cards

- Use a consistent “analytics card” pattern:
  - label (small)
  - value (large)
  - delta/status chip (optional)
  - subtle icon (optional)
- Keep whitespace generous (avoid cramped dashboards)

### Status chips

- Must be theme-safe (contrast)
- Keep copy short: PAID, SHIPPED, DELIVERED, CANCELLED, PENDING

### Lists

- Use consistent row height and spacing
- Always provide:
  - primary text (name/id)
  - secondary text (short metadata)
  - right-side status/action
  - “View details” affordance

---

## 15) Centralised formatter rules (MANDATORY)

Formatting MUST be centralised so output is consistent everywhere.

### Rule

**All formatting must go through the centralised formatter entry point.**

### Forbidden

- formatting in widgets (`Text(...)`, `onChanged`, etc.)
- formatting in controllers/providers
- multiple formatter implementations across features
- scattered regex formatting across screens

### Allowed

- one shared formatter module under: `lib/app/core/formatters/`
- domain-safe helpers for parsing/validation (no UI dependency)

### Must cover

- phone numbers (E.164 + display format)
- currency (NGN, GBP, USD as needed)
- payment references
- dates/times
- quantities/stock
- any future “display formatting” must be added centrally

### Failure logging for formatters (sanitised)

If a formatter fails or receives invalid input, logs MUST include:

- formatter name
- expected format
- received input shape (type/length only)
- resolution hint (what to change / how to fix)

NO raw PII should be logged.

---

## 16) Address autocomplete rules (MANDATORY)

Backend is connected to Google Places API.

### Rule

Any time a user fills an address, the UI MUST use Google Places / Address Autocomplete.

### Forbidden

- plain text address inputs without autocomplete
- storing only a raw string when a structured model is available

### Required behaviour

- loading state while searching
- empty state (“No matches”)
- error state + retry button
- fallback: allow manual entry ONLY if provider fails/outage
  - MUST log failure classification + next action

### Reuse rule

Use the shared Address Autocomplete component everywhere.
Do not duplicate address search logic.

---

## 17) Stop conditions (critical)

STOP immediately if:

- folder renames are required
- file placement is unclear
- more than ~50 lines are about to be written in a single change
- behavior is ambiguous
- adding a new dependency is required (ask first)

---

## 18) Decision order (mandatory)

When uncertain:

1. Explain intent
2. Propose file placement
3. Confirm data flow
4. Then write code (smallest safe change)

Skipping steps is not allowed.

---

## 19) Definition of “done” for any UI feature

A feature is done only when:

- Works on Web + Android + iOS
- Uses theme tokens (no hardcoded colors)
- Has loading/empty/error states
- Uses domain models (no raw JSON in UI)
- Includes required logs
- Uses centralised formatters (no inline formatting)
- Uses address autocomplete for address fields
- Is testable with clear steps (“how to verify”)

---

## 20) Recommended file placement (MANDATORY direction)

### Centralised formatters

`lib/app/core/formatters/`

- `app_formatters.dart` (entry point — import this in screens/controllers)
- `phone_formatter.dart`
- `money_formatter.dart`
- `payment_ref_formatter.dart`

NOTE:

- If you already have `currency_formatter.dart`, do NOT rename it unless requested.
- Instead, either:
  - export it from `app_formatters.dart`, OR
  - create `money_formatter.dart` as a small wrapper that exports `currency_formatter.dart`

### Address autocomplete (reusable UI)

`lib/app/features/home/presentation/settings/widgets/address_autocomplete_field.dart`

- reuse this everywhere address is needed (don’t duplicate)

---

## 21) Guiding principle

Clarity beats cleverness.
If code is impressive but hard to read, it is wrong.
This is not a demo app. It must scale into production.

---

# Vertical rules (Estate + Farm)

## 33) Supported verticals (MANDATORY)

This frontend supports two primary client verticals:

1. **Estate (Landlord / Property Management)**
2. **Farm (Warehouse + Assets + Production Planning)**

The UI MUST adapt to the vertical + role, and present data as dashboards and insight modules.
Plain list-first screens are forbidden.

---

## 34) Roles (MANDATORY)

### Backend role mapping (MANDATORY)

Backend roles are:

- `business_owner`
- `staff`
- `tenant`
- `customer`

UI labels like **Estate Owner / Farm Owner** map to backend role: **`business_owner`**.
Frontend must not guess role names. It must use backend role values exactly.

### Estate roles (UI labels)

- Estate Owner (Landlord)
- Estate Staff (Property manager, maintenance, accountant)
- Tenant

### Farm roles (UI labels)

- Farm Owner
- Farm Staff (warehouse, production, field workers, admin)

Role decides:

- what KPIs appear first
- what actions/CTAs appear
- what records the user can access

Frontend must not infer role. Role is read from backend session/profile.

---

## 35) Estate (Landlord) UI requirements (MANDATORY)

### A) Estate Owner dashboard must contain these modules

1. **Year-to-date performance** (earnings YTD, earnings by unit/property, occupancy rate if supported)
   - If these stats are not returned by backend, show “Coming soon” and do not invent values.
2. **Monthly performance** (collected vs expected, overdue amount + count)
3. **Unit health** (occupied/vacant/notice + maintenance open/closed)
4. **Cost overview** (staff costs monthly, maintenance spend if supported)
5. **Drilldowns** (tap KPI → filtered view)
6. **Documents vault shortcut** (“Recent documents” max 5 + “Upload/View all”)

### B) Tenant experience must contain these modules

1. **Payment snapshot** (last payment, next due, current balance/arrears)
2. **Payment history** (grouped by month)
3. **Suggestions & reminders** (backend-driven)
4. **Issues & requests** (open/closed + timeline)
5. **Documents** (lease + receipts)
6. **Reports** (rent statement download/share if supported)

### Estate screens must not be “lists only”

- Units screen: summary cards + breakdown chips + search/filter → then grouped units
- Tenants screen: paid/on-time/overdue summary + chips → then tenant list

---

## 36) Farm UI requirements (MANDATORY)

Farm features include:

- warehouse item records
- purchase price + depreciation impact
- production planning (planting → harvesting)
- projected sales and costs (backend computed)
- staff assignment per production cycle
- document storage

### Depreciation rule (MANDATORY)

Depreciation is **backend-computed only**.
Frontend must NOT calculate depreciation.
If depreciation data is missing, show:

- “Coming soon” in the depreciation module, OR
- hide the module only if explicitly requested.

### A) Farm Owner dashboard must contain these modules

1. **Warehouse overview** (inventory value, low stock alerts, expiring items if applicable)
2. **Assets & depreciation** (book value + depreciation impact summary)
3. **Production pipeline** (active productions + milestones)
4. **Financial projection** (projected revenue vs projected cost, margin indicator)
5. **Staff overview** (staff count + assignment by production)
6. **Documents vault shortcut** (recent docs + upload/view all)

### B) Warehouse screens (MANDATORY)

Warehouse listing must NOT be a wall of items.
It MUST include:

- top KPIs (total items, total value, low stock count)
- category breakdown (chips/cards)
- search + filters (category, location, status)
- grouped list (by category or location)
- item drilldown:
  - purchase price/date/useful life
  - depreciation summary (backend computed)
  - attachments (invoices/photos) if supported

### C) Production planning screens (MANDATORY)

Production view must be a **timeline/pipeline**, not a list.
It MUST include:

- stages: Planning → Planting → Growth → Harvest → Storage → Sale
- stage cards with: dates + cost-to-date + projected cost + yield/sales projections (backend)
- staff assignments per production cycle
- “What’s next” suggestions (backend-driven)

If production pipeline stats are not returned by backend, show “Coming soon” and do not invent values.

---

## 37) Document vault UX (MANDATORY for both verticals)

Documents must be a safe place to store docs.
UI must provide:

- categories/folders (Leases, Receipts, Invoices, Staff docs, Production docs)
- tags and search
- recent docs module on dashboards
- clear permissions by role
- upload flow with progress + success confirmation
- no silent failures (error + retry)

---

## 38) Suggestions, insights, and reports (MANDATORY)

- Suggestions are backend-driven (frontend displays and routes actions).
- Reports must be: summary cards + download/share CTA.

### Forbidden

- Frontend inventing recommendations
- Frontend calculating financial advice
- Reports that are only long paragraphs or raw JSON

---

## 39) Drilldown rule (MANDATORY)

Every KPI card must have a drilldown:

- tap → filtered list / detail view / report
- if not built: disabled with “coming soon” OR hide only if requested

---

## 40) Visual hierarchy rule (MANDATORY)

Any data-heavy screen must be structured as:

- Page header (title + helper text)
- KPI row (cards)
- Breakdown row (chips/cards)
- Trend/timeline module (if available)
- Short “recent” list (max 5–10) + “View all”

### Forbidden

- screens that start with a long list with no summary insight

---

## 42) UI patterns checklist (MANDATORY)

This section defines approved UI patterns so screens do not become “plain straight line” layouts.

### 42.1 Page scaffold pattern (MANDATORY)

Every screen MUST have:

- Title + helper text
- Primary actions
- Content sections (modules)
- loading/empty/error/success states

Forbidden:

- raw list-first screens

### 42.2 Dashboard template (MANDATORY)

Dashboards must render:

1. KPI grid
2. breakdown chips/cards
3. trend module
4. recent activity + view all

### 42.3 List screen template (MANDATORY)

Lists must render:

1. summary strip
2. filter chips + search
3. grouping
4. list (paginated) + view all

### 42.4 Detail screen template (MANDATORY)

Details must render:

- header summary
- key metrics
- grouped history/timeline
- docs/attachments (if supported)
- actions

### 42.5 Form screen template (MANDATORY)

Forms must be sectioned:

- section cards + helper text
- progressive disclosure for advanced fields
- address uses autocomplete

### 42.6 Empty/loading/error patterns (MANDATORY)

Every module must implement:

- skeleton loading
- empty CTA
- error retry + actionable message

### 42.7 Component reuse rule (MANDATORY)

Reuse shared components (KPI cards, section cards, state widgets, autocomplete).
No duplication of formatter or address logic.

---

## 43) Simplicity + decomposition rules (MOST IMPORTANT)

Do not over-complicate files. Break down into sections and components.

### File size rule (HARD)

- Any screen file MUST be split if it grows beyond **150 lines**.
- Any widget over **80 lines** must be broken into smaller widgets.
- Any function over **25 lines** must be split.

### Section-first rule (MANDATORY)

Any data-heavy screen MUST be:

- thin screen scaffold
- multiple section widgets (KPISection, BreakdownSection, TrendSection, RecentSection)
- controllers/providers orchestrate (no business logic in widgets)

Forbidden:

- “god widgets” that do everything
- inline mapping/formatting inside list builders

---

## 44) Data usage & insight UX (MANDATORY)

The UI must help users understand performance over time, not just view records.

### 44.1 Use backend metrics contract only (MANDATORY)

- UI must render KPIs/breakdowns/trends from backend analytics endpoints.
- UI must not invent stats.
- UI must not compute business totals (except lightweight derived values when approved).

### 44.2 “Time matters” UI pattern (MANDATORY)

Dashboards must show:

- selected range clearly (Last 30 days, YTD)
- range selector when backend supports it
- trends/timelines as modules (not raw logs)

### 44.3 “Explain the number” rule (MANDATORY)

Every KPI card must include:

- label
- value
- timeframe
- drilldown path
- optional “what changed” link when events are available

### 44.4 Event timeline UX (MANDATORY)

When backend provides events:

- show timeline grouped by day/week
- allow filtering by event type
- show minimal safe “what changed” (no secrets)

### 44.5 Future GPT/Insights UX (MANDATORY)

When AI is added later:

- AI output must never be presented as “fact” without linking to metric/event context
- label AI as “Suggestion”
- provide “Why am I seeing this?” showing safe underlying metrics/events
- allow dismiss/disable suggestions

### 44.6 Forbidden AI behavior

- AI inventing missing stats
- AI giving financial/legal advice
- AI acting without confirmation on sensitive actions

---

## 45) Initiative rule (MANDATORY — suggest tracking improvements safely)

If the agent notices:

- state changes but no events recorded, OR
- analytics displayed without time range, OR
- inconsistent KPI names/units across endpoints,

the agent MUST:

1. log the gap clearly,
2. propose ONE small tracking improvement,
3. explain exactly how to verify it,
4. STOP if it requires schema changes or new endpoints and ask first.
