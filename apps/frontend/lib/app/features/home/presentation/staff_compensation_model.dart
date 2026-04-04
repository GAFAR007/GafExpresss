/// lib/app/features/home/presentation/staff_compensation_model.dart
/// ---------------------------------------------------------------
/// WHAT:
/// - Typed model for staff compensation payloads.
///
/// WHY:
/// - Avoids raw JSON access in UI and providers.
/// - Keeps payroll parsing consistent across screens.
///
/// HOW:
/// - fromJson parses backend payloads defensively.
/// - Helpers normalize ids, numbers, and dates.
/// - Logs parsing for traceability (safe fields only).
library;

import 'package:frontend/app/core/debug/app_debug.dart';

const String _logTag = "STAFF_COMP_MODEL";
const String _keyId = "_id";
const String _keyAltId = "id";
const String _keyStaffProfileId = "staffProfileId";
const String _keyBusinessId = "businessId";
const String _keySalaryAmount = "salaryAmountKobo";
const String _keySalaryCadence = "salaryCadence";
const String _keyPayDay = "payDay";
const String _keyNotes = "notes";
const String _keyLastUpdatedBy = "lastUpdatedBy";
const String _keyLastUpdatedAt = "lastUpdatedAt";
const String _keyCreatedAt = "createdAt";
const String _keyUpdatedAt = "updatedAt";

class StaffCompensation {
  final String id;
  final String staffProfileId;
  final String businessId;
  final int salaryAmountKobo;
  final String salaryCadence;
  final String payDay;
  final String notes;
  final String? lastUpdatedBy;
  final DateTime? lastUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StaffCompensation({
    required this.id,
    required this.staffProfileId,
    required this.businessId,
    required this.salaryAmountKobo,
    required this.salaryCadence,
    required this.payDay,
    required this.notes,
    required this.lastUpdatedBy,
    required this.lastUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StaffCompensation.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json);
    AppDebug.log(_logTag, "fromJson()", extra: {"id": id});

    return StaffCompensation(
      id: id,
      staffProfileId: _parseString(json[_keyStaffProfileId]),
      businessId: _parseString(json[_keyBusinessId]),
      salaryAmountKobo: _parseInt(json[_keySalaryAmount]),
      salaryCadence: _parseString(json[_keySalaryCadence]),
      payDay: _parseString(json[_keyPayDay]),
      notes: _parseString(json[_keyNotes]),
      lastUpdatedBy: _parseNullableString(json[_keyLastUpdatedBy]),
      lastUpdatedAt: _parseDate(json[_keyLastUpdatedAt]),
      createdAt: _parseDate(json[_keyCreatedAt]),
      updatedAt: _parseDate(json[_keyUpdatedAt]),
    );
  }
}

String _parseId(Map<String, dynamic> json) {
  final id = json[_keyId] ?? json[_keyAltId] ?? "";
  return id.toString();
}

String _parseString(dynamic value) {
  return value?.toString() ?? "";
}

String? _parseNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.trim().isEmpty) return null;
  return text;
}

int _parseInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? "") ?? fallback;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
