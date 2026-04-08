/// lib/app/features/home/presentation/production/production_calendar_models.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Typed models for production calendar responses.
///
/// HOW:
/// - Parses backend calendar payloads into strongly typed objects.
/// - Uses defensive parsing for ids, strings, and ISO date fields.
///
/// WHY:
/// - Prevents raw JSON map usage inside calendar widgets.
/// - Keeps parsing behavior consistent with other production model files.
library;

import 'package:frontend/app/core/debug/app_debug.dart';

const String _logTag = "PRODUCTION_CALENDAR_MODELS";
const String _logItemFromJson = "ProductionCalendarItem.fromJson()";
const String _logResponseFromJson = "ProductionCalendarResponse.fromJson()";

const String _keyMessage = "message";
const String _keyFrom = "from";
const String _keyTo = "to";
const String _keyItems = "items";
const String _keyTaskId = "taskId";
const String _keyTitle = "title";
const String _keyStatus = "status";
const String _keyRoleRequired = "roleRequired";
const String _keyRequiredHeadcount = "requiredHeadcount";
const String _keyAssignedCount = "assignedCount";
const String _keyAssignedStaffProfileIds = "assignedStaffProfileIds";
const String _keyStartDate = "startDate";
const String _keyDueDate = "dueDate";
const String _keyPlanId = "planId";
const String _keyPlanTitle = "planTitle";
const String _keyPhaseId = "phaseId";
const String _keyPhaseName = "phaseName";
const String _keyAssignedStaffId = "assignedStaffId";
const String _keyAssignedStaffName = "assignedStaffName";
const String _keyAssignedStaffRole = "assignedStaffRole";

class ProductionCalendarItem {
  final String taskId;
  final String title;
  final String status;
  final String roleRequired;
  final int requiredHeadcount;
  final int assignedCount;
  final List<String> assignedStaffProfileIds;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String planId;
  final String planTitle;
  final String phaseId;
  final String phaseName;
  final String assignedStaffId;
  final String assignedStaffName;
  final String assignedStaffRole;

  const ProductionCalendarItem({
    required this.taskId,
    required this.title,
    required this.status,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.assignedCount,
    required this.assignedStaffProfileIds,
    required this.startDate,
    required this.dueDate,
    required this.planId,
    required this.planTitle,
    required this.phaseId,
    required this.phaseName,
    required this.assignedStaffId,
    required this.assignedStaffName,
    required this.assignedStaffRole,
  });

  factory ProductionCalendarItem.fromJson(Map<String, dynamic> json) {
    final id = _parseString(json[_keyTaskId]);
    // WHY: Item-level logs help trace malformed payloads without printing full objects.
    AppDebug.log(_logTag, _logItemFromJson, extra: {"taskId": id});

    return ProductionCalendarItem(
      taskId: id,
      title: _parseString(json[_keyTitle]),
      status: _parseString(json[_keyStatus]),
      roleRequired: _parseString(json[_keyRoleRequired]),
      requiredHeadcount: _parseInt(json[_keyRequiredHeadcount], fallback: 1),
      assignedCount: _parseInt(json[_keyAssignedCount]),
      assignedStaffProfileIds: _parseStringList(
        json[_keyAssignedStaffProfileIds],
      ),
      startDate: _parseDate(json[_keyStartDate]),
      dueDate: _parseDate(json[_keyDueDate]),
      planId: _parseString(json[_keyPlanId]),
      planTitle: _parseString(json[_keyPlanTitle]),
      phaseId: _parseString(json[_keyPhaseId]),
      phaseName: _parseString(json[_keyPhaseName]),
      assignedStaffId: _parseString(json[_keyAssignedStaffId]),
      assignedStaffName: _parseString(json[_keyAssignedStaffName]),
      assignedStaffRole: _parseString(json[_keyAssignedStaffRole]),
    );
  }
}

class ProductionCalendarResponse {
  final String message;
  final DateTime? from;
  final DateTime? to;
  final List<ProductionCalendarItem> items;

  const ProductionCalendarResponse({
    required this.message,
    required this.from,
    required this.to,
    required this.items,
  });

  factory ProductionCalendarResponse.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json[_keyItems] ?? []) as List<dynamic>;
    // WHY: Parse each row defensively to avoid runtime crashes in grid rendering.
    final items = itemsRaw
        .map(
          (item) =>
              ProductionCalendarItem.fromJson(item as Map<String, dynamic>),
        )
        .toList();

    AppDebug.log(
      _logTag,
      _logResponseFromJson,
      extra: {
        // WHY: Keep response logs compact and non-sensitive.
        "count": items.length,
        "from": _parseString(json[_keyFrom]),
        "to": _parseString(json[_keyTo]),
      },
    );

    return ProductionCalendarResponse(
      message: _parseString(json[_keyMessage]),
      from: _parseDate(json[_keyFrom]),
      to: _parseDate(json[_keyTo]),
      items: items,
    );
  }
}

String _parseString(dynamic value) {
  // WHY: Empty-string fallback keeps widgets simple and null-safe.
  if (value == null) return "";
  return value.toString().trim();
}

DateTime? _parseDate(dynamic value) {
  // WHY: DateTime.tryParse safely handles null/invalid backend values.
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int _parseInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? "") ?? fallback;
}

List<String> _parseStringList(dynamic value) {
  if (value is! List<dynamic>) {
    return <String>[];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}
