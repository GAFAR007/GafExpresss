# Preorder Stage 6 Launch Runbook

## Scope
- Preorder reservation lifecycle: reserve, release, confirm, reconcile.
- Payment linkage: order `reservationId` and webhook confirmation path.
- Worker automation: scheduler-based reconciliation loop.

## Preconditions
- `MONGO_URI` points to the target environment database.
- `JWT_SECRET` and payment secrets are configured.
- Backend deploy includes:
  - `backend/services/preorder_reservation_reconciler.worker.js`
  - `backend/services/preorder_cap_confidence.service.js`
  - reservation endpoints in `backend/routes/business.routes.js`
- Worker toggle set for environment:
  - Staging: `PREORDER_RECONCILE_WORKER_ENABLED=true`
  - Production: `PREORDER_RECONCILE_WORKER_ENABLED=true`

## 1) Regression Gate (Required)
Run in backend root:

```bash
npm run test:preorder:regression
```

Pass criteria:
- Exit code `0`
- No failing tests

No-go if:
- Any failing test in reserve/release/confirm/reconcile/worker/payment-linkage/availability/monitoring.

## 2) Staging Deploy + Soak
Deploy backend build to staging with worker enabled.

Recommended worker env:

```bash
PREORDER_RECONCILE_WORKER_ENABLED=true
PREORDER_RECONCILE_WORKER_INTERVAL_MS=60000
PREORDER_RECONCILE_WORKER_LIMIT=500
```

Start backend and verify startup logs include worker boot:
- `PREORDER RECONCILE WORKER: started`

If needed, run one manual reconcile during soak:

```bash
npm run ops:preorder:reconcile:once
```

Optional scoped/manual reconcile:

```bash
node scripts/preorder-reservation-reconciler.js --businessId=<BUSINESS_ID> --limit=200
```

Soak window:
- Minimum: 24 hours
- Recommended: 48 hours if payment volume is low

## 3) Soak Monitoring Checklist
- Error logs:
  - No sustained spikes in `reserveProductionPlanPreorder`, `releasePreorderReservation`, `confirmPreorderReservation`, `reconcileExpiredPreorderReservations`.
- Worker logs:
  - Ticks continue normally.
  - No repeated tick failures.
- Data integrity:
  - `preorderReservedQuantity` never negative.
  - Expired reservations transition to `expired`.
  - Confirmed reservations remain `confirmed`.
- UX sanity:
  - Availability endpoint returns stable:
    - `preorderCapQuantity`
    - `preorderReservedQuantity`
    - `preorderRemainingQuantity`
    - `effectiveCap`
    - `confidenceScore`
    - `approvedProgressCoverage`

## 4) Go / No-Go Gate
Go only if all are true:
- Regression gate passed (`npm run test:preorder:regression`).
- Staging soak completed with no Sev-1/Sev-2 preorder or payment incidents.
- Worker has no recurring failure pattern.
- Reservation counters and statuses are consistent in spot checks.

No-go if any are true:
- Confirm/release/reserve idempotency breaks.
- Payment webhook fails to confirm linked reservations.
- Worker repeatedly fails without recovery.
- Counter drift detected (`preorderReservedQuantity` mismatch vs active holds).

## 5) Production Rollout
1. Deploy backend.
2. Confirm worker startup log in production.
3. Run post-deploy smoke (API):
   - Reserve path (valid + cap exceeded)
   - Confirm path (idempotency)
   - Release path (idempotency)
   - Availability path (confidence fields present)
4. Monitor logs and metrics for first 60 minutes.
5. Keep one operator on-call for first business cycle.

## 6) Rollback Plan
If severe issue occurs:
1. Disable worker immediately:
   - `PREORDER_RECONCILE_WORKER_ENABLED=false`
2. Revert backend to previous stable release.
3. Pause preorder entry points from UI if needed.
4. Run one manual reconciliation after fix validation.
5. Re-run full regression gate before re-attempting rollout.
