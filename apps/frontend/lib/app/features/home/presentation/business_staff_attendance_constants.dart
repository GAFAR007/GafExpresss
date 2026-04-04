/// lib/app/features/home/presentation/business_staff_attendance_constants.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Shared constants for staff attendance UI.
///
/// WHY:
/// - Avoids inline strings and keeps labels consistent.
/// - Centralizes log tags + UI copy for attendance screens.
///
/// HOW:
/// - Exposes labels, log keys, and query defaults.
library;

import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';

const String staffAttendanceLogTag = "STAFF_ATTENDANCE_UI";
const String staffAttendanceLogBuild = "build()";
const String staffAttendanceLogRefresh = "refresh";
const String staffAttendanceLogClockIn = "clock_in_tap";
const String staffAttendanceLogClockOut = "clock_out_tap";
const String staffAttendanceLogFilterChange = "filter_change";
const String staffAttendanceLogRetry = "retry";
const String staffAttendanceLogStaffKey = "staffProfileId";

const String staffAttendanceTitle = "Attendance";
const String staffAttendanceHelper =
    "Track clock-ins, review attendance, and monitor performance.";
const String staffAttendanceScopeLabel = "Scope";
const String staffAttendanceScopeSelf = "My attendance";
const String staffAttendanceScopeAll = "All staff";
const String staffAttendanceDateLabel = "Date range";
const String staffAttendanceEstateLabel = "Estate";
const String staffAttendanceEstateAll = "All estates";
const String staffAttendanceClockInLabel = "Clock in";
const String staffAttendanceClockOutLabel = "Clock out";
const String staffAttendanceStaffLabel = "Staff member";
const String staffAttendanceStaffPlaceholder = "Select staff";
const String staffAttendanceEmptyTitle = "No attendance yet";
const String staffAttendanceEmptyHelper =
    "Clock in to start tracking attendance.";
const String staffAttendanceErrorTitle = "Unable to load attendance";
const String staffAttendanceErrorHelper =
    "Please try again or contact support.";
const String staffAttendanceRetryLabel = "Try again";
const String staffAttendanceSelectStaffPrompt = "Select a staff member first.";
const String staffAttendanceClockInSuccess = "Clock-in recorded.";
const String staffAttendanceClockOutSuccess = "Clock-out recorded.";

const String staffAttendanceKpiOnTime = "On-time rate";
const String staffAttendanceKpiLate = "Late count";
const String staffAttendanceKpiDelay = "Avg delay";
const String staffAttendanceKpiTotal = "Total sessions";
const String staffAttendanceKpiOpen = "Open sessions";
const String staffAttendanceKpiDuration = "Avg duration";
const String staffAttendanceKpiHelper =
    "Uses completed sessions as a proxy until shift targets are configured.";

const int staffAttendanceAssetsPage = 1;
const int staffAttendanceAssetsLimit = 100;
// WHY: Attendance filters need a lightweight estate list for dropdowns.
const BusinessAssetsQuery staffAttendanceAssetsQuery = BusinessAssetsQuery(
  page: staffAttendanceAssetsPage,
  limit: staffAttendanceAssetsLimit,
);
