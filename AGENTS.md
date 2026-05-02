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

## Frontend Web + Android APK Safety Rule (MANDATORY)

When adding Android APK support, Android release signing, or Android build changes, agents must keep Netlify's Flutter web deployment intact.

- Netlify must continue to build and serve the Flutter web app from `apps/frontend/build/web`.
- Android APK builds output separately to `apps/frontend/build/app/outputs/flutter-apk/app-release.apk`; the APK must not replace or interfere with the web output.
- Do not change Netlify configuration unless the requested change explicitly requires it.
- Do not commit Android signing files, keystore secrets, generated APKs, or machine-local paths.

Before pushing Android APK, Android release, or signing changes, run:

```bash
cd apps/frontend
flutter clean
flutter pub get
flutter build web
flutter build apk --release
```

Before handoff, confirm:

1. Web build succeeds.
2. Android APK build succeeds.
3. Netlify config still deploys `build/web`.
4. No Android-only signing files, keystore secrets, generated APKs, or local paths are committed.
5. Android release signing setup is safe and does not affect web deployment.
6. The final GitHub push is safe for Netlify to auto-deploy or for the manual Netlify deploy command above.

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
