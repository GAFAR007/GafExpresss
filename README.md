# WHAT
- Top-level overview and operating rules for the apps workspace.

# WHY
- Keep frontend + backend changes consistent, safe, and production-ready.

# HOW
- Document architecture, flows, and required debugging standards here.

GafExpress — Full-Stack Application
Clean Architecture · Multi-Platform · Production-Oriented · JWT-Validated
Agent Instructions (Codex / AI Helpers)

These rules are mandatory. Do not violate them.

Non-Negotiable Workflow

Work ONE step at a time (no large refactors or code dumps).

Never change the existing folder structure.

Do not rename or move files unless explicitly instructed.

Keep imports consistent with the current structure.

Prefer small, safe changes, then run & verify.

Code Style Requirements

Every new or edited file must include:

File header documentation:

WHAT this file is

WHY it exists

HOW it works

Extensive inline comments explaining WHY, not just WHAT.

Debug logs at all critical points.

Debug Logging Standard

Use AppDebug.log(TAG, message, extra: {...})

Logs must include:

Screen build()

Button taps

API request start/end

Navigation events

Never log:

Passwords

Tokens

Secrets

Multi-Platform Requirements

Must work on Web, Android, and iOS

No dart:io usage in UI or presentation layers

Platform differences handled via:

platform_info_web.dart

platform_info_io.dart

platform_info_stub.dart

API Contract Rules

Current backend responses:

POST /auth/register → { user }

POST /auth/login → { message, token, user }

Token is REQUIRED for login

Frontend validates token presence + expiry (JWT exp)

🧱 Monorepo Structure
apps/
├─ backend/ # Express + MongoDB API
└─ frontend/ # Flutter (Web / Android / iOS)

This is a production-style monorepo, designed for long-term growth and multiple clients.

🔁 System Flow Overview
Flutter Client (Web / Mobile)
|
| HTTP (JSON)
v
Express API
|
| Business Logic
v
MongoDB

🔐 Authentication Flow (CURRENT STATE)
What Works Now ✅

User registers via frontend

Backend creates user and returns { user }

User logs in

Backend returns { message, token, user }

Frontend:

Parses response safely

Validates JWT exp and rejects expired tokens

Creates AuthSession(user, token)

Navigates to /home only if token is valid

Important Design Decision

Token handling is enforced and JWT-validated

No frontend rewrite required when JWT is added

🔒 Verification Flow (Email + Phone)
What Happens

Frontend (dumb UI)
- Shows "Verified" only when the backend profile returns `isEmailVerified` / `isPhoneVerified`.
- Never sets verification flags itself.

Backend (source of truth)
1) Request: `/auth/email-verification/request` or `/auth/phone-verification/request`.
2) OTP: backend generates a 6-digit code, hashes it, stores hash + expiry.
3) Confirm: `/auth/*/confirm` validates code + expiry, then flips verified flags.
4) UI refresh: frontend re-fetches `/auth/profile` and updates the badge.

Why It's Safe
- Verification flags can only be set server-side; profile updates ignore them.
- OTPs are hashed, time-limited, and never stored in plaintext.
- Requests are tied to the authenticated `userId` from auth middleware.

📝 TODO (IMPORTANT)
- When your Termii Sender ID is approved, log in to https://app.termii.com and switch from dev OTP to real SMS delivery.
- Check the Sender ID status regularly until it flips to Approved.

🖥 Backend (apps/backend)
Purpose

The backend provides:

REST API

Authentication logic

Business rules

MongoDB access

Tech Stack

Node.js

Express

MongoDB (Mongoose)

dotenv

nodemon (dev)

JWT is in use for login and protected endpoints.

Backend Folder Structure
apps/backend/
├─ config/
│ ├─ db.js
│ └─ jwt.js # Present, token usage coming later
│
├─ controllers/
│ └─ auth.controller.js
│
├─ services/
│ └─ auth.service.js
│
├─ routes/
│ └─ index.js
│
├─ utils/
│ └─ debug.js
│
├─ server.js
└─ package.json

Backend Startup Flow
server.js
↓
Load env
↓
Create Express app
↓
Register middleware
↓
Connect MongoDB
↓
Register routes
↓
Start server

Backend runs at:

http://localhost:4000

🎨 Frontend (apps/frontend)
Purpose

The frontend handles:

UI

User input

Navigation

API communication

Auth flow

It is fully decoupled from the backend.

Frontend Tech Stack

Flutter

Riverpod (state & DI)

Dio (networking)

GoRouter (navigation)

Frontend Folder Structure (CURRENT)
lib/
├─ app/
│ ├─ core/
│ │ ├─ constants/ # AppConstants (baseUrl, keys)
│ │ ├─ debug/ # AppDebug logging
│ │ ├─ network/ # Dio client + providers
│ │ └─ platform/ # Web / iOS / Android detection
│ │
│ ├─ features/
│ │ ├─ auth/
│ │ │ ├─ data/ # Auth API calls
│ │ │ ├─ domain/
│ │ │ │ └─ models/ # AuthUser, AuthSession
│ │ │ └─ presentation/
│ │ │ ├─ providers/
│ │ │ ├─ login_screen.dart
│ │ │ └─ register_screen.dart
│ │ │
│ │ └─ home/
│ │ └─ presentation/
│ │ └─ home_screen.dart
│ │
│ ├─ theme/
│ ├─ router.dart
│ ├─ app.dart
│ └─ main.dart

Frontend Boot Flow
main.dart
↓
Log BOOT status
↓
Resolve platform baseUrl
↓
Wrap AppRoot in ProviderScope
↓
GoRouter builds routes
↓
Login screen renders

🌍 Environment Configuration
Backend (apps/backend/.env)
PORT=4000
MONGO_URI=your_mongodb_uri
JWT_SECRET=your_secret

Frontend Base URL Handling

Handled via AppConstants + PlatformInfo:

Web / iOS simulator → http://localhost:4000

Android emulator → http://10.0.2.2:4000

Real device → LAN IP

🚀 Development
Backend
cd apps/backend
npm install
npm run dev

Frontend
cd apps/frontend
flutter pub get
flutter run -d chrome

📦 Current Status
Feature Status
Backend API ✅ Stable
MongoDB ✅ Connected
Auth routes ✅ Working
Flutter boot ✅ Stable
Login flow ✅ Complete
Register flow ✅ Complete
Token handling ✅ Required + validated
Route guards 🔜 Next
Session persistence 🔜 Next
🧠 Philosophy

GafExpress prioritizes:

Clean architecture

Debuggability

Scalability

Discipline over shortcuts

This is not a demo app.
It is structured to evolve into a production system.

✍️ Author

Gafar Temitayo Razak
Backend & Full-Stack Developer
Building scalable systems with clarity and discipline.
