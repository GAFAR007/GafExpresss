# Gafar Express Deployment

This app deploys with the same pattern already used on your other projects:

- frontend: Netlify Drop
- backend: Render web service
- DNS: GoDaddy CNAME records

## Frontend

Recommended terminal deploy from `apps/frontend`:

```bash
flutter pub get
flutter build web \
  --dart-define=API_BASE_URL=https://api.gafarsexpress.gafarstechnologies.com \
  --dart-define=PAYSTACK_CALLBACK_BASE_URL=https://gafarsexpress.gafarstechnologies.com
netlify deploy --prod --dir=build/web --site=37d7355f-502b-47ff-b24a-0e2d7a58fa02
```

Manual fallback if CLI deploy is unavailable:

- upload `apps/frontend/build/web` to Netlify Drop
- or run `netlify link --id 37d7355f-502b-47ff-b24a-0e2d7a58fa02` once, then redeploy with the command above

Netlify target details:

- custom domain: `gafarsexpress.gafarstechnologies.com`
- GoDaddy CNAME host: `gafarsexpress`
- GoDaddy CNAME target: the `*.netlify.app` hostname assigned by Netlify

## Backend

Render is configured from `render.yaml` and auto-deploys branch `chore/batched-push-2026-04-05`.

Recommended terminal deploy from the repository root:

```bash
git add <files>
git commit -m "Describe the fix"
git push origin chore/batched-push-2026-04-05
```

Render service settings:

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

Run these after deployment:

```bash
curl https://api.gafarsexpress.gafarstechnologies.com/health
curl -I https://gafarsexpress.gafarstechnologies.com
```

- frontend loads at `https://gafarsexpress.gafarstechnologies.com`
- backend health responds at `https://api.gafarsexpress.gafarstechnologies.com/health`
- login succeeds from frontend to backend
- `/payment-success` resolves without a Netlify 404
- business invite links open at `/business-invite?token=...`
