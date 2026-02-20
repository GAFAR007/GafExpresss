<!--
  backend/scripts/production-calendar-sanity.md
  ------------------------------------------------
  WHAT:
  - Manual sanity checklist for production AI draft + policy scheduler + calendar API.

  HOW:
  - Run these checks against local/staging with business owner credentials.

  WHY:
  - Confirms time-block scheduling, range overlap filtering, and response shape.
-->

# Production Calendar Sanity Checklist

## 1) Create AI Draft Across Multiple Days

1. Call `POST /business/production/plans/ai-draft` with:
   - `estateAssetId`
   - `productId`
   - `startDate` and `endDate` (different days)
   - optional `aiBrief`, `cropSubtype`
2. Confirm response includes:
   - `summary.days`, `summary.weeks`, `summary.monthApprox`
   - `schedulePolicy`
   - `tasks[]` with ISO `startDate` and `dueDate`
   - `requiredHeadcount`, `assignedStaffProfileIds`, `assignedCount`

## 2) Verify Work-Block Scheduling Rules

1. Call `GET /business/production/schedule-policy?estateAssetId=<id>`.
2. Confirm draft task times fall only within policy blocks for allowed weekdays.
3. Update policy with `PUT /business/production/schedule-policy?estateAssetId=<id>` and rerun draft.
4. Confirm new draft reflects updated `workWeekDays`, `blocks`, and `minSlotMinutes`.

## 3) Verify Calendar Endpoint Range

1. Save the plan (`POST /business/production/plans`).
2. Query `GET /business/production/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD`.
3. Confirm returned `items[]` include:
   - `taskId`, `title`, `status`, `roleRequired`
   - `requiredHeadcount`, `assignedCount`
   - `planTitle`, `phaseName`, `assignedStaffName`
4. Confirm tasks overlapping the range are included and out-of-range tasks are excluded.

## 4) Verify Assignment Flow

1. Call `PUT /business/production/tasks/:taskId/assign` with:
   - `assignedStaffProfileIds: [ ... ]`
2. Confirm response includes `assignment.requiredHeadcount`, `assignment.assignedCount`, `assignment.shortage`.
3. Confirm role mismatch or invalid profile IDs return validation errors.
