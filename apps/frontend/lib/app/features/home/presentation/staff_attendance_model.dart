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
const String _keyPlanId = "planId";
const String _keyTaskId = "taskId";
const String _keyStaffProfileId = "staffProfileId";
const String _keyWorkDate = "workDate";
const String _keyClockInAt = "clockInAt";
const String _keyClockOutAt = "clockOutAt";
const String _keyDurationMinutes = "durationMinutes";
const String _keyLocation = "location";
const String _keyNotes = "notes";
const String _keyCreatedAt = "createdAt";
const String _keyProofUrl = "proofUrl";
const String _keyProofPublicId = "proofPublicId";
const String _keyProofFilename = "proofFilename";
const String _keyProofMimeType = "proofMimeType";
const String _keyProofSizeBytes = "proofSizeBytes";
const String _keyProofUploadedAt = "proofUploadedAt";
const String _keyProofUploadedBy = "proofUploadedBy";
const String _keyProofEntryUrl = "url";
const String _keyProofEntryPublicId = "publicId";
const String _keyProofEntryFilename = "filename";
const String _keyProofEntryMimeType = "mimeType";
const String _keyProofEntrySizeBytes = "sizeBytes";
const String _keyProofEntryUploadedAt = "uploadedAt";
const String _keyProofEntryUploadedBy = "uploadedBy";
const String _keyProofs = "proofs";
const String _keyUnitIndex = "unitIndex";
const String _keyType = "type";
const String _keyClockOutAudit = "clockOutAudit";
const String _keyTaskTitle = "taskTitle";
const String _keyStaffName = "staffName";
const String _keyUnitId = "unitId";
const String _keyUnitLabel = "unitLabel";
const String _keyProgressUnitLabel = "progressUnitLabel";
const String _keyUnitsCompleted = "unitsCompleted";
const String _keyUnitsRemaining = "unitsRemaining";
const String _keyNumberOfUnitsCompleted = "numberOfUnitsCompleted";
const String _keyRequiredProofs = "requiredProofs";
const String _keyUnitType = "unitType";
const String _keyQuantityActivityType = "quantityActivityType";
const String _keyQuantityAmount = "quantityAmount";
const String _keyQuantityUnit = "quantityUnit";
const String _keyCapturedAt = "capturedAt";
const String _keySessionStatus = "sessionStatus";
const String _keyUpdatedAt = "updatedAt";

class StaffAttendanceProof {
  final int unitIndex;
  final String url;
  final String publicId;
  final String filename;
  final String mimeType;
  final String type;
  final int? sizeBytes;
  final DateTime? uploadedAt;
  final String? uploadedBy;

  const StaffAttendanceProof({
    required this.unitIndex,
    required this.url,
    required this.publicId,
    required this.filename,
    required this.mimeType,
    required this.type,
    required this.sizeBytes,
    required this.uploadedAt,
    required this.uploadedBy,
  });

  factory StaffAttendanceProof.fromJson(Map<String, dynamic> json) {
    return StaffAttendanceProof(
      unitIndex: _parseNullableInt(json[_keyUnitIndex]) ?? 1,
      url: (json[_keyProofEntryUrl] ?? json[_keyProofUrl] ?? "").toString(),
      publicId: (json[_keyProofEntryPublicId] ?? json[_keyProofPublicId] ?? "")
          .toString(),
      filename: (json[_keyProofEntryFilename] ?? json[_keyProofFilename] ?? "")
          .toString(),
      mimeType: (json[_keyProofEntryMimeType] ?? json[_keyProofMimeType] ?? "")
          .toString(),
      type: (json[_keyType] ?? "").toString(),
      sizeBytes: _parseNullableInt(
        json[_keyProofEntrySizeBytes] ?? json[_keyProofSizeBytes],
      ),
      uploadedAt: _parseDate(
        json[_keyProofEntryUploadedAt] ?? json[_keyProofUploadedAt],
      ),
      uploadedBy: _parseNullableString(
        json[_keyProofEntryUploadedBy] ?? json[_keyProofUploadedBy],
      ),
    );
  }

  bool get isUploaded => url.trim().isNotEmpty && filename.trim().isNotEmpty;
}

class StaffAttendanceClockOutAudit {
  final DateTime? workDate;
  final String planId;
  final String taskId;
  final String taskTitle;
  final String staffProfileId;
  final String staffName;
  final String unitId;
  final String unitLabel;
  final String progressUnitLabel;
  final num? unitsCompleted;
  final num? unitsRemaining;
  final int? requiredProofs;
  final String unitType;
  final String quantityActivityType;
  final num? quantityAmount;
  final String quantityUnit;
  final String notes;
  final DateTime? capturedAt;

  const StaffAttendanceClockOutAudit({
    required this.workDate,
    required this.planId,
    required this.taskId,
    required this.taskTitle,
    required this.staffProfileId,
    required this.staffName,
    required this.unitId,
    required this.unitLabel,
    required this.progressUnitLabel,
    required this.unitsCompleted,
    required this.unitsRemaining,
    required this.requiredProofs,
    required this.unitType,
    required this.quantityActivityType,
    required this.quantityAmount,
    required this.quantityUnit,
    required this.notes,
    required this.capturedAt,
  });

  factory StaffAttendanceClockOutAudit.fromJson(Map<String, dynamic> json) {
    return StaffAttendanceClockOutAudit(
      workDate: _parseDate(json[_keyWorkDate]),
      planId: (json[_keyPlanId] ?? "").toString(),
      taskId: (json[_keyTaskId] ?? "").toString(),
      taskTitle: (json[_keyTaskTitle] ?? "").toString(),
      staffProfileId: (json[_keyStaffProfileId] ?? "").toString(),
      staffName: (json[_keyStaffName] ?? "").toString(),
      unitId: (json[_keyUnitId] ?? "").toString(),
      unitLabel: (json[_keyUnitLabel] ?? "").toString(),
      progressUnitLabel: (json[_keyProgressUnitLabel] ?? "").toString(),
      unitsCompleted: _parseNullableNum(json[_keyUnitsCompleted]),
      unitsRemaining: _parseNullableNum(json[_keyUnitsRemaining]),
      requiredProofs: _parseNullableInt(json[_keyRequiredProofs]),
      unitType: (json[_keyUnitType] ?? "").toString(),
      quantityActivityType: (json[_keyQuantityActivityType] ?? "").toString(),
      quantityAmount: _parseNullableNum(json[_keyQuantityAmount]),
      quantityUnit: (json[_keyQuantityUnit] ?? "").toString(),
      notes: (json[_keyNotes] ?? "").toString(),
      capturedAt: _parseDate(json[_keyCapturedAt]),
    );
  }
}

class StaffAttendanceRecord {
  final String id;
  final String? planId;
  final String? taskId;
  final String staffProfileId;
  final DateTime? workDate;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final int? durationMinutes;
  final String? location;
  final String? notes;
  final DateTime? createdAt;
  final String? proofUrl;
  final String? proofPublicId;
  final String? proofFilename;
  final String? proofMimeType;
  final int? proofSizeBytes;
  final DateTime? proofUploadedAt;
  final String? proofUploadedBy;
  final List<StaffAttendanceProof> proofs;
  final StaffAttendanceClockOutAudit? clockOutAudit;
  final String sessionStatus;
  final num? numberOfUnitsCompleted;
  final int? requiredProofs;
  final String unitType;
  final DateTime? updatedAt;

  const StaffAttendanceRecord({
    required this.id,
    required this.planId,
    required this.taskId,
    required this.staffProfileId,
    required this.workDate,
    required this.clockInAt,
    required this.clockOutAt,
    required this.durationMinutes,
    required this.location,
    required this.notes,
    required this.createdAt,
    required this.proofUrl,
    required this.proofPublicId,
    required this.proofFilename,
    required this.proofMimeType,
    required this.proofSizeBytes,
    required this.proofUploadedAt,
    required this.proofUploadedBy,
    required this.proofs,
    required this.clockOutAudit,
    required this.sessionStatus,
    required this.numberOfUnitsCompleted,
    required this.requiredProofs,
    required this.unitType,
    required this.updatedAt,
  });

  factory StaffAttendanceRecord.fromJson(Map<String, dynamic> json) {
    // WHY: Capture ids early so parse logs can be correlated.
    final id = (json[_keyId] ?? json[_keyAltId] ?? "").toString();
    // WHY: Log parsing to debug backend payload mismatches.
    AppDebug.log(_logTag, _logParse, extra: {"id": id});

    return StaffAttendanceRecord(
      id: id,
      planId: _parseNullableString(json[_keyPlanId]),
      taskId: _parseNullableString(json[_keyTaskId]),
      // WHY: Always coerce ids to strings for UI keys.
      staffProfileId: (json[_keyStaffProfileId] ?? "").toString(),
      workDate: _parseDate(json[_keyWorkDate]),
      // WHY: Fallback prevents crashes if backend sends null dates.
      clockInAt: _parseDate(json[_keyClockInAt]) ?? DateTime.now(),
      clockOutAt: _parseDate(json[_keyClockOutAt]),
      durationMinutes: _parseNullableInt(json[_keyDurationMinutes]),
      location: _parseNullableString(json[_keyLocation]),
      notes: _parseNullableString(json[_keyNotes]),
      createdAt: _parseDate(json[_keyCreatedAt]),
      proofUrl: _parseNullableString(json[_keyProofUrl]),
      proofPublicId: _parseNullableString(json[_keyProofPublicId]),
      proofFilename: _parseNullableString(json[_keyProofFilename]),
      proofMimeType: _parseNullableString(json[_keyProofMimeType]),
      proofSizeBytes: _parseNullableInt(json[_keyProofSizeBytes]),
      proofUploadedAt: _parseDate(json[_keyProofUploadedAt]),
      proofUploadedBy: _parseNullableString(json[_keyProofUploadedBy]),
      proofs: _parseProofs(json[_keyProofs]),
      clockOutAudit: _parseClockOutAudit(json[_keyClockOutAudit]),
      sessionStatus: _parseNullableString(json[_keySessionStatus]) ?? "active",
      numberOfUnitsCompleted: _parseNullableNum(
        json[_keyNumberOfUnitsCompleted],
      ),
      requiredProofs: _parseNullableInt(json[_keyRequiredProofs]),
      unitType: _parseNullableString(json[_keyUnitType]) ?? "",
      updatedAt: _parseDate(json[_keyUpdatedAt]),
    );
  }

  // WHY: Open sessions are the ones without a clock-out time.
  bool get isOpen =>
      sessionStatus.trim().toLowerCase() == "active" || clockOutAt == null;

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
    AppDebug.log(_logTag, _logKpi, extra: {"count": records.length});

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

num? _parseNullableNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString());
}

String? _parseNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.trim().isEmpty) return null;
  return text;
}

List<StaffAttendanceProof> _parseProofs(dynamic value) {
  if (value is! List) {
    return const <StaffAttendanceProof>[];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => item.map((key, fieldValue) {
          return MapEntry(key.toString(), fieldValue);
        }),
      )
      .map(StaffAttendanceProof.fromJson)
      .toList()
    ..sort((left, right) => left.unitIndex.compareTo(right.unitIndex));
}

StaffAttendanceClockOutAudit? _parseClockOutAudit(dynamic value) {
  if (value is! Map) {
    return null;
  }
  final map = <String, dynamic>{};
  value.forEach((key, fieldValue) {
    map[key.toString()] = fieldValue;
  });
  return StaffAttendanceClockOutAudit.fromJson(map);
}
