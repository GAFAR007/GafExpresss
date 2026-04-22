# Agent Instructions

This file applies from the repository root.

For area-specific rules, also read:

- `apps/AGENTS.md`
- `apps/frontend/AGENTS.md`
- `apps/backend/AGENTS.md`

## Deployment Rule (MANDATORY)

After every production fix, user-visible behavior change, or new feature, the agent must do one of these before handoff:

1. Deploy the affected surface if the local environment already has the required CLI access.
2. If deployment cannot be completed locally, provide the exact terminal commands the user can run.

Do not stop at "ready to deploy" by default.

Docs-only changes do not require a deploy unless the user explicitly asks for one.

## Frontend Deploy Command

The frontend is deployed to Netlify and this repository is already linked to site id `37d7355f-502b-47ff-b24a-0e2d7a58fa02`.

```bash
cd apps/frontend
flutter pub get
flutter build web \
  --dart-define=API_BASE_URL=https://api.gafarsexpress.gafarstechnologies.com \
  --dart-define=PAYSTACK_CALLBACK_BASE_URL=https://gafarsexpress.gafarstechnologies.com
netlify deploy --prod --dir=build/web --site=37d7355f-502b-47ff-b24a-0e2d7a58fa02
```

## Backend Deploy Command

The backend is deployed by Render from branch `chore/batched-push-2026-04-05` using `render.yaml`.

```bash
git add <files>
git commit -m "Describe the fix"
git push origin chore/batched-push-2026-04-05
```

## Post-Deploy Verification

```bash
curl https://api.gafarsexpress.gafarstechnologies.com/health
curl -I https://gafarsexpress.gafarstechnologies.com
```
