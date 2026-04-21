# Gafar Express Deployment

This app deploys with the same pattern already used on your other projects:

- frontend: Netlify Drop
- backend: Render web service
- DNS: GoDaddy CNAME records

## Frontend

Build the Flutter web app from `apps/frontend` with the production URLs injected:

```bash
flutter build web \
  --dart-define=API_BASE_URL=https://api.gafarsexpress.gafarstechnologies.com \
  --dart-define=PAYSTACK_CALLBACK_BASE_URL=https://gafarsexpress.gafarstechnologies.com
```

Upload `apps/frontend/build/web` to Netlify Drop, then attach the custom domain:

- custom domain: `gafarsexpress.gafarstechnologies.com`
- GoDaddy CNAME host: `gafarsexpress`
- GoDaddy CNAME target: the `*.netlify.app` hostname assigned by Netlify

## Backend

Create a new Render Node web service from:

- repo: `GAFAR007/GafExpresss`
- branch: `chore/batched-push-2026-04-05`
- root directory: `apps/backend`
- build command: `npm install`
- start command: `npm start`
- health check path: `/health`
- node version: `22`

Set these explicit production values in Render:

```env
NODE_ENV=production
EMAIL_PROVIDER=brevo
CLIENT_ORIGIN=https://gafarsexpress.gafarstechnologies.com
FRONTEND_BASE_URL=https://gafarsexpress.gafarstechnologies.com
```

Also copy the live secrets already used by the backend:

- `MONGO_URI`
- `JWT_SECRET`
- `PAYSTACK_SECRET_KEY`
- `BREVO_API_KEY`
- `EMAIL_FROM`
- `EMAIL_FROM_NAME`
- `CLOUDINARY_*`
- `GOOGLE_*`
- active `DOJAH_*` values if used
- active AI keys if used

Attach the backend custom domain in Render:

- custom domain: `api.gafarsexpress.gafarstechnologies.com`
- GoDaddy CNAME host: `api.gafarsexpress`
- GoDaddy CNAME target: the `*.onrender.com` hostname assigned by Render

## DNS

After Netlify and Render generate their target hostnames, add these GoDaddy CNAMEs:

- `gafarsexpress` -> Netlify hostname
- `api.gafarsexpress` -> Render hostname

## Verification

- frontend loads at `https://gafarsexpress.gafarstechnologies.com`
- backend health responds at `https://api.gafarsexpress.gafarstechnologies.com/health`
- login succeeds from frontend to backend
- `/payment-success` resolves without a Netlify 404
- business invite links open at `/business-invite?token=...`
