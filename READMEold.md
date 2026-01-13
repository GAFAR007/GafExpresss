# GafExpress — Full-Stack Application
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

GafExpress is a full-stack application built with a **clean, scalable architecture**, separating backend services and frontend clients while maintaining a clear data and authentication flow.

This repository follows a **production-style monorepo structure** to support long-term growth, team collaboration, and multiple client platforms.

---

## 🧱 High-Level Architecture

```
office-ecom-store/
├─ apps/
│  ├─ backend/        # Express + MongoDB API
│  └─ frontend/       # Client application (Flutter / Web)
├─ README.md          # System overview (this file)
└─ .gitignore
```

---

## 🔁 System Flow Overview

```
Frontend (Web / Mobile)
        |
        |  HTTP Requests (JSON)
        v
Backend (Express API)
        |
        |  Business Logic
        v
MongoDB (Atlas)
```

### Authentication Flow (Current & Planned)

1. User interacts with the **frontend**
2. Frontend sends requests to **Express API**
3. Backend:

   * Validates request
   * Handles authentication / authorization
   * Interacts with MongoDB
4. Backend returns structured JSON responses
5. Frontend renders UI based on response

---

## 🖥 Backend (`apps/backend`)

### Purpose

The backend provides:

* API endpoints
* Authentication logic
* Authorization & role handling
* Database access
* Business rules

### Tech Stack

* **Node.js**
* **Express**
* **MongoDB (Mongoose)**
* **JWT Authentication**
* **dotenv**
* **nodemon (dev)**

---

### Backend Folder Structure

```
apps/backend/
├─ config/
│  ├─ db.js           # MongoDB connection logic
│  └─ jwt.js          # JWT helpers (sign / verify tokens)
│
├─ controllers/
│  └─ auth.controller.js
│     # Handles HTTP requests (req/res layer)
│
├─ services/
│  └─ auth.service.js
│     # Business logic (no Express coupling)
│
├─ routes/
│  └─ index.js
│     # Central route registration
│
├─ utils/
│  └─ debug.js
│     # Structured debug logging
│
├─ server.js
│   # Main backend entry point
│
├─ .env
│   # Environment variables (never committed)
│
└─ package.json
```

---

### Backend Design Principles

✅ **Separation of concerns**

* Routes → Controllers → Services → Database
* No business logic inside routes

✅ **Single entry point**

* `server.js` handles startup flow:

  * Load env
  * Register middleware
  * Connect database
  * Register routes
  * Start server

✅ **Fail-fast startup**

* App exits if MongoDB connection fails

---

### Backend Startup Flow

```text
server.js
  ↓
Load env variables
  ↓
Create Express app
  ↓
Register middleware
  ↓
Connect MongoDB
  ↓
Register routes
  ↓
Start HTTP server
```

---

## 🎨 Frontend (`apps/frontend`)

### Purpose

The frontend is responsible for:

* User interface
* User input
* Authentication UI
* Communicating with the backend API

### Notes

* Frontend is **fully decoupled** from backend
* Communicates only via HTTP (REST)
* Can be replaced or expanded (Web / Mobile / Admin dashboard)

> The frontend never talks directly to the database.

---

## 🔐 Authentication Strategy (Planned)

The system is designed to support **multiple authentication methods**:

### Current / Planned Auth Types

* ✅ Email + Password
* 🔜 Google OAuth
* 🔜 Microsoft (Outlook) OAuth

### User Roles (Planned)

* `admin`
* `staff`
* `customer`

Roles will be enforced **server-side** using JWT claims and middleware.

---

## 🌍 Environment Variables

Backend uses environment variables for security.

Example (`apps/backend/.env`):

```env
PORT=4000
MONGO_URI=your_mongodb_connection_string
JWT_SECRET=your_secret_key
```

⚠️ `.env` files are **never committed**.

---

## 🚀 Development

### Backend

```bash
cd apps/backend
npm install
npm run dev
```

Server runs at:

```
http://localhost:4000
```

---

## 📦 Repository Status

* Backend foundation: ✅ complete
* Database connection: ✅ stable
* Auth layering: ✅ structured
* Frontend integration: 🔜 in progress
* OAuth providers: 🔜 planned

---

## 🧠 Philosophy

This project prioritizes:

* Clean architecture
* Long-term scalability
* Readability over shortcuts
* Real-world backend patterns

This is **not a tutorial project** — it is structured to grow into a production system.

---

## ✍️ Author

**Gafar Temitayo Razak**
Backend & Full-Stack Developer
Building scalable systems with clarity and discipline.
