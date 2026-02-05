/// lib/app/features/home/presentation/staff_attendance_model.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Data models for staff attendance records + KPI summaries.
///
/// WHY:
/// - Keeps parsing and derived metrics out of widgets.
/// - Centralizes attendance shape for UI + providers.
///
/// HOW:
/// - fromJson maps backend fields to Dart types.
/// - Helpers compute derived fields like open sessions and durations.
library;

import 'package:frontend/app/core/debug/app_debug.dart';

const String _logTag = "STAFF_ATTENDANCE_MODEL";
const String _logParse = "fromJson()";
const String _logKpi = "buildKpis()";

const String _keyId = "_id";
const String _keyAltId = "id";
const String _keyStaffProfileId = "staffProfileId";
const String _keyClockInAt = "clockInAt";
const String _keyClockOutAt = "clockOutAt";
const String _keyDurationMinutes = "durationMinutes";
const String _keyLocation = "location";
const String _keyNotes = "notes";
const String _keyCreatedAt = "createdAt";

class StaffAttendanceRecord {
  final String id;
  final String staffProfileId;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final int? durationMinutes;
  final String? location;
  final String? notes;
  final DateTime? createdAt;

  const StaffAttendanceRecord({
    required this.id,
    required this.staffProfileId,
    required this.clockInAt,
    required this.clockOutAt,
    required this.durationMinutes,
    required this.location,
    required this.notes,
    required this.createdAt,
  });

  factory StaffAttendanceRecord.fromJson(Map<String, dynamic> json) {
    // WHY: Capture ids early so parse logs can be correlated.
    final id = (json[_keyId] ?? json[_keyAltId] ?? "").toString();
    // WHY: Log parsing to debug backend payload mismatches.
    AppDebug.log(_logTag, _logParse, extra: {"id": id});

    return StaffAttendanceRecord(
      id: id,
      // WHY: Always coerce ids to strings for UI keys.
      staffProfileId: (json[_keyStaffProfileId] ?? "").toString(),
      // WHY: Fallback prevents crashes if backend sends null dates.
      clockInAt: _parseDate(json[_keyClockInAt]) ?? DateTime.now(),
      clockOutAt: _parseDate(json[_keyClockOutAt]),
      durationMinutes: _parseNullableInt(json[_keyDurationMinutes]),
      location: _parseNullableString(json[_keyLocation]),
      notes: _parseNullableString(json[_keyNotes]),
      createdAt: _parseDate(json[_keyCreatedAt]),
    );
  }

  // WHY: Open sessions are the ones without a clock-out time.
  bool get isOpen => clockOutAt == null;

  int? get effectiveDurationMinutes {
    // WHY: Prefer server-calculated duration for accuracy.
    if (durationMinutes != null) return durationMinutes;
    // WHY: Skip calculation until a clock-out exists.
    if (clockOutAt == null) return null;
    // WHY: Fallback to local diff when backend omitted duration.
    return clockOutAt!.difference(clockInAt).inMinutes;
  }
}

class StaffAttendanceKpiSummary {
  final int totalSessions;
  final int completedSessions;
  final int openSessions;
  final double onTimeRate;
  final double avgDurationMinutes;

  const StaffAttendanceKpiSummary({
    required this.totalSessions,
    required this.completedSessions,
    required this.openSessions,
    required this.onTimeRate,
    required this.avgDurationMinutes,
  });

  factory StaffAttendanceKpiSummary.fromRecords(
    List<StaffAttendanceRecord> records,
  ) {
    // WHY: Log KPI calculation to debug summary mismatches.
    AppDebug.log(
      _logTag,
      _logKpi,
      extra: {"count": records.length},
    );

    // WHY: Derive counts to power KPI tiles without backend summaries.
    final total = records.length;
    final completed = records.where((r) => !r.isOpen).length;
    final open = total - completed;
    final durations = records
        .map((record) => record.effectiveDurationMinutes)
        .whereType<int>()
        .toList();
    // WHY: Avoid divide-by-zero when no durations exist yet.
    final avgDuration = durations.isEmpty
        ? 0.0
        : durations.reduce((a, b) => a + b) / durations.length;
    // WHY: On-time rate is modeled as completed sessions ratio.
    final onTimeRate = total == 0 ? 0.0 : completed / total;

    return StaffAttendanceKpiSummary(
      totalSessions: total,
      completedSessions: completed,
      openSessions: open,
      onTimeRate: onTimeRate,
      avgDurationMinutes: avgDuration,
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int? _parseNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

String? _parseNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.trim().isEmpty) return null;
  return text;
}
