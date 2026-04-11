/// lib/app/features/home/presentation/production/production_plan_draft.dart
/// ----------------------------------------------------------------------
/// WHAT:
/// - Draft state + controller for creating production plans.
///
/// WHY:
/// - Keeps form logic out of widgets to respect clean architecture.
/// - Centralizes validation and payload shaping.
///
/// HOW:
/// - StateNotifier manages plan + phase + task edits.
/// - Exposes validation + payload builders for API submission.
/// - Logs key state changes for debugging.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/product_ai_model.dart';
import 'package:frontend/app/features/home/presentation/production/production_assistant_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';

// WHY: Generic engine phases avoid hard-coding a farming workflow.
const List<String> _defaultPhaseNames = [
  "Planning",
  "Execution",
  "Quality Control",
  "Output Preparation",
  "Distribution",
];

// WHY: Keep task defaults predictable for auto-scheduling.
const int _defaultTaskWeight = 1;
const String _defaultTaskTitle = "Task";
const String _taskIdPrefix = "draft_task_";
const String _emptyText = "";
const int _minIndex = 0;
const int _phaseOrderOffset = 1;

class _UnsetValue {
  const _UnsetValue();
}

const _UnsetValue _unsetValue = _UnsetValue();
const int _defaultPhaseEstimatedDays = 7;
const int _maxTaskWeight = 5;
const String _aiDraftFallbackMessage = "Unable to parse AI production draft.";
const String _aiDraftFallbackClassification = "PROVIDER_REJECTED_FORMAT";
const String _aiDraftFallbackErrorCode = "PRODUCTION_AI_SCHEMA_INVALID";
const String _aiDraftFallbackResolutionHint =
    "Refine prompt or retry; required fields are missing/invalid.";
const int _aiDraftFallbackStatus = 422;
const String _aiDraftFallbackRetryReason = "provider_output_invalid";
const String _isoDatePattern = r"^\d{4}-\d{2}-\d{2}$";

// WHY: Draft statuses drive the create-table UI without touching backend payloads.
enum ProductionTaskStatus { notStarted, inProgress, blocked, done }

// WHY: Keep status defaults consistent across manual + AI drafts.
const ProductionTaskStatus _defaultTaskStatus = ProductionTaskStatus.notStarted;

// WHY: Validation copy must stay consistent across UI messages.
const String _errorTitleRequired = "Plan title is required.";
const String _errorEstateRequired = "Estate is required.";
const String _errorProductRequired = "Product is required.";
const String _errorStartDateRequired = "Start date is required.";
const String _errorEndDateRequired = "End date is required.";
const String _errorDateRange = "End date must be after start date.";
const String _errorPlantingMaterialRequired =
    "Planting material type is required for farm production.";
const String _errorPlannedPlantingQuantityRequired =
    "Planned planting quantity is required before drafting farm production.";
const String _errorPlannedPlantingUnitRequired =
    "Planned planting unit is required before drafting farm production.";
const String _errorEstimatedHarvestQuantityRequired =
    "Estimated harvest quantity is required before drafting farm production.";
const String _errorEstimatedHarvestUnitRequired =
    "Estimated harvest unit is required before drafting farm production.";
const String _errorTasksRequired = "Add at least one task.";
const String _errorTaskTitleRequired = "Task title is required.";
const String _errorTaskRoleRequired = "Task role is required.";
const String _errorTaskHeadcountRequired =
    "Task required headcount must be at least 1.";
const String _errorTaskScheduleIncomplete =
    "Task schedule must include both start and end time.";
const String _errorTaskScheduleInvalid =
    "Task end time must be after start time.";
const String _errorTaskScheduleOutsideWindow =
    "Task schedule must stay inside the plan date window.";

// WHY: Payload keys should be consistent with backend expectations.
const String _payloadEstateId = "estateAssetId";
const String _payloadProductId = "productId";
const String _payloadPlanTitle = "planTitle";
const String _payloadTitle = "title";
const String _payloadNotes = "notes";
const String _payloadStartDate = "startDate";
const String _payloadEndDate = "endDate";
const String _payloadDomainContext = "domainContext";
const String _payloadAiGenerated = "aiGenerated";
const String _payloadPlantingTargets = "plantingTargets";
const String _payloadPlantingMaterialType = "materialType";
const String _payloadPlannedPlantingQuantity = "plannedPlantingQuantity";
const String _payloadPlannedPlantingUnit = "plannedPlantingUnit";
const String _payloadEstimatedHarvestQuantity = "estimatedHarvestQuantity";
const String _payloadEstimatedHarvestUnit = "estimatedHarvestUnit";
const String _payloadPhases = "phases";
const String _payloadPhaseName = "name";
const String _payloadPhaseOrder = "order";
const String _payloadPhaseEstimatedDays = "estimatedDays";
const String _payloadPhaseType = "phaseType";
const String _payloadPhaseRequiredUnits = "requiredUnits";
const String _payloadPhaseMinRatePerFarmerHour = "minRatePerFarmerHour";
const String _payloadPhaseTargetRatePerFarmerHour = "targetRatePerFarmerHour";
const String _payloadPhasePlannedHoursPerDay = "plannedHoursPerDay";
const String _payloadPhaseBiologicalMinDays = "biologicalMinDays";
const String _payloadTasks = "tasks";
const String _payloadTaskTitle = "title";
const String _payloadTaskRole = "roleRequired";
const String _payloadTaskStaff = "assignedStaffId";
const String _payloadTaskStaffProfileIds = "assignedStaffProfileIds";
const String _payloadTaskRequiredHeadcount = "requiredHeadcount";
const String _payloadTaskWeight = "weight";
const String _payloadTaskInstructions = "instructions";
const String _payloadTaskDependencies = "dependencies";
const String _payloadTaskType = "taskType";
const String _payloadTaskSourceTemplateKey = "sourceTemplateKey";
const String _payloadTaskRecurrenceGroupKey = "recurrenceGroupKey";
const String _payloadTaskOccurrenceIndex = "occurrenceIndex";
const String _payloadTaskStartDate = "startDate";
const String _payloadTaskDueDate = "dueDate";
const String _payloadTaskManualSortOrder = "manualSortOrder";
const String _payloadSummary = "summary";
const String _payloadSummaryTotalTasks = "totalTasks";
const String _payloadSummaryTotalEstimatedDays = "totalEstimatedDays";
const String _payloadSummaryRiskNotes = "riskNotes";
const String _payloadProposedProduct = "proposedProduct";
const String _payloadProposedStartDate = "proposedStartDate";
const String _payloadProposedEndDate = "proposedEndDate";
const String _payloadSchedulePolicy = "schedulePolicy";
const String _payloadCapacity = "capacity";
const String _payloadWarnings = "warnings";
const String _payloadDraftTasks = "tasks";
const String _payloadMessage = "message";
const String _payloadDays = "days";
const String _payloadWeeks = "weeks";
const String _payloadMonthApprox = "monthApprox";
const String _payloadCropSubtype = "cropSubtype";
const String _payloadWorkWeekDays = "workWeekDays";
const String _payloadBlocks = "blocks";
const String _payloadMinSlotMinutes = "minSlotMinutes";
const String _payloadTimezone = "timezone";
const String _payloadRoles = "roles";
const String _payloadTotal = "total";
const String _payloadAvailable = "available";
const String _payloadStart = "start";
const String _payloadEnd = "end";
const String _payloadAssignedCount = "assignedCount";

const String _logTag = "PRODUCTION_DRAFT";
const String _logInit = "draft initialized";
const String _logUpdate = "draft updated";
const String _logTaskAdded = "task added";
const String _logTaskRemoved = "task removed";
const String _logTaskStatusUpdated = "task status updated";
const String _logTaskDone = "task marked done";
const String _logTaskCleared = "task cleared";
const String _logReset = "draft reset";
const String _logDraftParsed = "draft parsed";
const String _logDraftApplied = "draft applied";
const String _extraFieldKey = "field";
const String _extraPhaseKey = "phase";
const String _extraTaskIdKey = "taskId";
const String _extraTaskIndexKey = "taskIndex";
const String _extraStatusKey = "status";
const String _extraCompletedAtKey = "completedAt";
const String _fieldTitle = "title";
const String _fieldNotes = "notes";
const String _fieldEstate = "estateAssetId";
const String _fieldProduct = "productId";
const String _fieldStartDate = "startDate";
const String _fieldEndDate = "endDate";
const String _fieldDomainContext = "domainContext";
const String _fieldAiGenerated = "aiGenerated";
const String _fieldPlantingTargets = "plantingTargets";
const String _fieldTask = "task";
const String _responseDraftKey = "draft";
const String _responseStatusKey = "status";
const String _responseIssueTypeKey = "issueType";
const String _responseMessageKey = "message";
const String _statusAiDraftSuccess = "ai_draft_success";
const String _statusAiDraftPartial = "ai_draft_partial";
const String _issueTypeInsufficientContext = "INSUFFICIENT_CONTEXT";
const String _extraPhaseCountKey = "phaseCount";
const String _extraMissingKey = "missing";
const String _extraInvalidKey = "invalid";
const String _extraIssueTypeKey = "issueType";

const List<String> productionPlantingMaterialTypeValues = [
  "seed",
  "seedling",
  "stand",
  "root",
  "stem",
  "cutting",
  "tuber",
  "sucker",
  "runner",
  "other",
];

const List<String> productionPlantingTargetUnitValues = [
  "kg",
  "g",
  "ton",
  "bag",
  "sack",
  "crate",
  "carton",
  "basket",
  "box",
  "bucket",
  "bunch",
  "bundle",
  "tray",
  "seed",
  "seedling",
  "stand",
  "piece",
  "plant",
];

const String _defaultFarmPlantingMaterialType = "seed";
const double _defaultFarmPlannedPlantingQuantity = 100;
const String _defaultFarmPlannedPlantingUnit = "kg";
const double _defaultFarmEstimatedHarvestQuantity = 1000;
const String _defaultFarmEstimatedHarvestUnit = "kg";

DateTime? _normalizeDraftLocalDateTime(DateTime? value) {
  if (value == null) {
    return null;
  }
  return value.isUtc ? value.toLocal() : value;
}

DateTime? _normalizeDraftCalendarDate(DateTime? value) {
  final localValue = _normalizeDraftLocalDateTime(value);
  if (localValue == null) {
    return null;
  }
  return DateTime(localValue.year, localValue.month, localValue.day);
}

bool productionDomainRequiresPlantingTargets(String? domainContext) {
  return normalizeProductionDomainContext(domainContext) ==
      productionDomainFarm;
}

String formatProductionPlantingMaterialType(String value) {
  switch (value.trim().toLowerCase()) {
    case "seed":
      return "Seed";
    case "seedling":
      return "Seedling";
    case "stand":
    case "stands":
      return "Stand";
    case "root":
      return "Root";
    case "stem":
      return "Stem";
    case "cutting":
      return "Cutting";
    case "tuber":
      return "Tuber";
    case "sucker":
      return "Sucker";
    case "runner":
      return "Runner";
    case "other":
      return "Other";
    default:
      return value.trim().isEmpty ? "Material" : value.trim();
  }
}

String normalizeProductionPlantingTargetUnit(String? value) {
  final normalized = (value ?? "").trim().toLowerCase();
  switch (normalized) {
    case "kgs":
      return "kg";
    case "gram":
    case "grams":
      return "g";
    case "t":
    case "tons":
    case "tonne":
    case "tonnes":
      return "ton";
    case "bags":
      return "bag";
    case "sacks":
      return "sack";
    case "crates":
      return "crate";
    case "cartons":
      return "carton";
    case "baskets":
      return "basket";
    case "boxes":
      return "box";
    case "buckets":
      return "bucket";
    case "bunches":
      return "bunch";
    case "bundles":
      return "bundle";
    case "trays":
      return "tray";
    case "seeds":
      return "seed";
    case "seedlings":
      return "seedling";
    case "stands":
      return "stand";
    case "pieces":
      return "piece";
    case "plants":
      return "plant";
    default:
      return normalized;
  }
}

String formatProductionPlantingTargetUnit(String value) {
  switch (normalizeProductionPlantingTargetUnit(value)) {
    case "kg":
      return "kg";
    case "g":
      return "g";
    case "ton":
      return "Ton";
    case "bag":
      return "Bag";
    case "sack":
      return "Sack";
    case "crate":
      return "Crate";
    case "carton":
      return "Carton";
    case "basket":
      return "Basket";
    case "box":
      return "Box";
    case "bucket":
      return "Bucket";
    case "bunch":
      return "Bunch";
    case "bundle":
      return "Bundle";
    case "tray":
      return "Tray";
    case "seed":
      return "Seed";
    case "seedling":
      return "Seedling";
    case "stand":
      return "Stand";
    case "piece":
      return "Piece";
    case "plant":
      return "Plant";
    default:
      return value.trim().isEmpty ? "Unit" : value.trim();
  }
}

class ProductionPlantingTargetsDraft {
  final String materialType;
  final double? plannedPlantingQuantity;
  final String plannedPlantingUnit;
  final double? estimatedHarvestQuantity;
  final String estimatedHarvestUnit;

  const ProductionPlantingTargetsDraft({
    required this.materialType,
    required this.plannedPlantingQuantity,
    required this.plannedPlantingUnit,
    required this.estimatedHarvestQuantity,
    required this.estimatedHarvestUnit,
  });

  bool get hasAnyValue {
    return materialType.trim().isNotEmpty ||
        plannedPlantingQuantity != null ||
        plannedPlantingUnit.trim().isNotEmpty ||
        estimatedHarvestQuantity != null ||
        estimatedHarvestUnit.trim().isNotEmpty;
  }

  bool get isComplete {
    return materialType.trim().isNotEmpty &&
        plannedPlantingQuantity != null &&
        plannedPlantingUnit.trim().isNotEmpty &&
        estimatedHarvestQuantity != null &&
        estimatedHarvestUnit.trim().isNotEmpty;
  }

  ProductionPlantingTargetsDraft copyWith({
    String? materialType,
    Object? plannedPlantingQuantity = _unsetValue,
    String? plannedPlantingUnit,
    Object? estimatedHarvestQuantity = _unsetValue,
    String? estimatedHarvestUnit,
  }) {
    return ProductionPlantingTargetsDraft(
      materialType: materialType ?? this.materialType,
      plannedPlantingQuantity: plannedPlantingQuantity == _unsetValue
          ? this.plannedPlantingQuantity
          : plannedPlantingQuantity as double?,
      plannedPlantingUnit: plannedPlantingUnit ?? this.plannedPlantingUnit,
      estimatedHarvestQuantity: estimatedHarvestQuantity == _unsetValue
          ? this.estimatedHarvestQuantity
          : estimatedHarvestQuantity as double?,
      estimatedHarvestUnit: estimatedHarvestUnit ?? this.estimatedHarvestUnit,
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      _payloadPlantingMaterialType: materialType.trim(),
      _payloadPlannedPlantingQuantity: plannedPlantingQuantity,
      _payloadPlannedPlantingUnit: plannedPlantingUnit.trim(),
      _payloadEstimatedHarvestQuantity: estimatedHarvestQuantity,
      _payloadEstimatedHarvestUnit: estimatedHarvestUnit.trim(),
    };
  }

  factory ProductionPlantingTargetsDraft.fromJson(Map<String, dynamic> json) {
    return ProductionPlantingTargetsDraft(
      materialType: (json[_payloadPlantingMaterialType] ?? "")
          .toString()
          .trim()
          .toLowerCase(),
      plannedPlantingQuantity: _parseNonNegativeDraftDouble(
        json[_payloadPlannedPlantingQuantity],
      ),
      plannedPlantingUnit: normalizeProductionPlantingTargetUnit(
        json[_payloadPlannedPlantingUnit] ?? json["plantingUnit"],
      ),
      estimatedHarvestQuantity: _parseNonNegativeDraftDouble(
        json[_payloadEstimatedHarvestQuantity],
      ),
      estimatedHarvestUnit: normalizeProductionPlantingTargetUnit(
        json[_payloadEstimatedHarvestUnit] ?? json["harvestUnit"],
      ),
    );
  }

  List<String> validateForDomain(String domainContext) {
    if (!productionDomainRequiresPlantingTargets(domainContext)) {
      return const <String>[];
    }

    final errors = <String>[];
    if (materialType.trim().isEmpty) {
      errors.add(_errorPlantingMaterialRequired);
    }
    if (plannedPlantingQuantity == null) {
      errors.add(_errorPlannedPlantingQuantityRequired);
    }
    if (plannedPlantingUnit.trim().isEmpty) {
      errors.add(_errorPlannedPlantingUnitRequired);
    }
    if (estimatedHarvestQuantity == null) {
      errors.add(_errorEstimatedHarvestQuantityRequired);
    }
    if (estimatedHarvestUnit.trim().isEmpty) {
      errors.add(_errorEstimatedHarvestUnitRequired);
    }
    return errors;
  }
}

ProductionPlantingTargetsDraft buildDefaultProductionPlantingTargetsForDomain(
  String domainContext,
) {
  if (!productionDomainRequiresPlantingTargets(domainContext)) {
    return const ProductionPlantingTargetsDraft(
      materialType: "",
      plannedPlantingQuantity: null,
      plannedPlantingUnit: "",
      estimatedHarvestQuantity: null,
      estimatedHarvestUnit: "",
    );
  }
  return const ProductionPlantingTargetsDraft(
    materialType: _defaultFarmPlantingMaterialType,
    plannedPlantingQuantity: _defaultFarmPlannedPlantingQuantity,
    plannedPlantingUnit: _defaultFarmPlannedPlantingUnit,
    estimatedHarvestQuantity: _defaultFarmEstimatedHarvestQuantity,
    estimatedHarvestUnit: _defaultFarmEstimatedHarvestUnit,
  );
}

ProductionPlantingTargetsDraft withDefaultProductionPlantingTargetsForDomain(
  ProductionPlantingTargetsDraft current,
  String domainContext,
) {
  if (!productionDomainRequiresPlantingTargets(domainContext)) {
    return current;
  }
  final defaults = buildDefaultProductionPlantingTargetsForDomain(
    domainContext,
  );
  return current.copyWith(
    materialType: current.materialType.trim().isEmpty
        ? defaults.materialType
        : current.materialType,
    plannedPlantingQuantity:
        current.plannedPlantingQuantity ?? defaults.plannedPlantingQuantity,
    plannedPlantingUnit: current.plannedPlantingUnit.trim().isEmpty
        ? defaults.plannedPlantingUnit
        : current.plannedPlantingUnit,
    estimatedHarvestQuantity:
        current.estimatedHarvestQuantity ?? defaults.estimatedHarvestQuantity,
    estimatedHarvestUnit: current.estimatedHarvestUnit.trim().isEmpty
        ? defaults.estimatedHarvestUnit
        : current.estimatedHarvestUnit,
  );
}

class ProductionAiDraftError implements Exception {
  final String message;
  final String classification;
  final String errorCode;
  final String resolutionHint;
  final Map<String, dynamic> details;
  final bool retryAllowed;
  final String retryReason;
  final int statusCode;

  const ProductionAiDraftError({
    required this.message,
    required this.classification,
    required this.errorCode,
    required this.resolutionHint,
    required this.details,
    required this.retryAllowed,
    required this.retryReason,
    required this.statusCode,
  });

  factory ProductionAiDraftError.fromBackend(
    Map<String, dynamic> json, {
    required int statusCode,
  }) {
    final details = json["details"];
    return ProductionAiDraftError(
      message: (json["error"] ?? _aiDraftFallbackMessage).toString().trim(),
      classification: (json["classification"] ?? _aiDraftFallbackClassification)
          .toString()
          .trim(),
      errorCode: (json["error_code"] ?? _aiDraftFallbackErrorCode)
          .toString()
          .trim(),
      resolutionHint:
          (json["resolution_hint"] ?? _aiDraftFallbackResolutionHint)
              .toString()
              .trim(),
      details: details is Map<String, dynamic> ? details : const {},
      retryAllowed: json["retry_allowed"] == true,
      retryReason: (json["retry_reason"] ?? _aiDraftFallbackRetryReason)
          .toString()
          .trim(),
      statusCode: statusCode,
    );
  }

  factory ProductionAiDraftError.schema({
    required List<String> missing,
    required List<String> invalid,
    String? message,
  }) {
    return ProductionAiDraftError(
      message: message ?? _aiDraftFallbackMessage,
      classification: _aiDraftFallbackClassification,
      errorCode: _aiDraftFallbackErrorCode,
      resolutionHint: _aiDraftFallbackResolutionHint,
      details: {_extraMissingKey: missing, _extraInvalidKey: invalid},
      retryAllowed: true,
      retryReason: _aiDraftFallbackRetryReason,
      statusCode: _aiDraftFallbackStatus,
    );
  }

  @override
  String toString() {
    return "$message ($classification/$errorCode)";
  }
}

class ProductionAiDraftPartialIssue {
  final String issueType;
  final String message;

  const ProductionAiDraftPartialIssue({
    required this.issueType,
    required this.message,
  });
}

class ProductionAiDraftScheduleBlock {
  final String start;
  final String end;

  const ProductionAiDraftScheduleBlock({
    required this.start,
    required this.end,
  });

  factory ProductionAiDraftScheduleBlock.fromJson(Map<String, dynamic> json) {
    return ProductionAiDraftScheduleBlock(
      start: (json[_payloadStart] ?? "").toString().trim(),
      end: (json[_payloadEnd] ?? "").toString().trim(),
    );
  }
}

class ProductionAiDraftSchedulePolicy {
  final List<int> workWeekDays;
  final List<ProductionAiDraftScheduleBlock> blocks;
  final int minSlotMinutes;
  final String timezone;

  const ProductionAiDraftSchedulePolicy({
    required this.workWeekDays,
    required this.blocks,
    required this.minSlotMinutes,
    required this.timezone,
  });

  factory ProductionAiDraftSchedulePolicy.fromJson(Map<String, dynamic> json) {
    final rawDays = (json[_payloadWorkWeekDays] ?? []) as List<dynamic>;
    final rawBlocks = (json[_payloadBlocks] ?? []) as List<dynamic>;
    return ProductionAiDraftSchedulePolicy(
      workWeekDays:
          rawDays
              .map((item) => int.tryParse(item.toString()) ?? 0)
              .where((day) => day >= 1 && day <= 7)
              .toSet()
              .toList()
            ..sort(),
      blocks: rawBlocks
          .whereType<Map<String, dynamic>>()
          .map(ProductionAiDraftScheduleBlock.fromJson)
          .toList(),
      minSlotMinutes:
          int.tryParse(json[_payloadMinSlotMinutes]?.toString() ?? "") ?? 30,
      timezone: (json[_payloadTimezone] ?? "").toString().trim(),
    );
  }

  String get blocksLabel {
    if (blocks.isEmpty) return "No blocks";
    return blocks.map((block) => "${block.start}-${block.end}").join(", ");
  }
}

class ProductionAiDraftRoleCapacity {
  final int total;
  final int available;

  const ProductionAiDraftRoleCapacity({
    required this.total,
    required this.available,
  });

  factory ProductionAiDraftRoleCapacity.fromJson(Map<String, dynamic> json) {
    return ProductionAiDraftRoleCapacity(
      total: int.tryParse(json[_payloadTotal]?.toString() ?? "") ?? 0,
      available: int.tryParse(json[_payloadAvailable]?.toString() ?? "") ?? 0,
    );
  }
}

class ProductionAiDraftCapacity {
  final String estateAssetId;
  final Map<String, ProductionAiDraftRoleCapacity> roles;

  const ProductionAiDraftCapacity({
    required this.estateAssetId,
    required this.roles,
  });

  factory ProductionAiDraftCapacity.fromJson(Map<String, dynamic> json) {
    final roleMap = <String, ProductionAiDraftRoleCapacity>{};
    final rawRoles = (json[_payloadRoles] ?? {}) as Map<dynamic, dynamic>;
    rawRoles.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        roleMap[key.toString()] = ProductionAiDraftRoleCapacity.fromJson(value);
      }
    });
    return ProductionAiDraftCapacity(
      estateAssetId: (json[_payloadEstateId] ?? "").toString().trim(),
      roles: roleMap,
    );
  }

  int availableForRole(String roleRequired) {
    final bucket = _capacityBucketForRole(roleRequired);
    if (bucket.isEmpty) return 0;
    return roles[bucket]?.available ?? 0;
  }
}

class ProductionAiDraftSummary {
  final DateTime? startDate;
  final DateTime? endDate;
  final int days;
  final int weeks;
  final int monthApprox;
  final String productId;
  final String cropSubtype;

  const ProductionAiDraftSummary({
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.weeks,
    required this.monthApprox,
    required this.productId,
    required this.cropSubtype,
  });

  factory ProductionAiDraftSummary.fromJson(Map<String, dynamic> json) {
    return ProductionAiDraftSummary(
      startDate: _normalizeDraftCalendarDate(
        DateTime.tryParse((json[_payloadStartDate] ?? "").toString()),
      ),
      endDate: _normalizeDraftCalendarDate(
        DateTime.tryParse((json[_payloadEndDate] ?? "").toString()),
      ),
      days: int.tryParse(json[_payloadDays]?.toString() ?? "") ?? 0,
      weeks: int.tryParse(json[_payloadWeeks]?.toString() ?? "") ?? 0,
      monthApprox:
          int.tryParse(json[_payloadMonthApprox]?.toString() ?? "") ?? 0,
      productId: (json[_payloadProductId] ?? "").toString().trim(),
      cropSubtype: (json[_payloadCropSubtype] ?? "").toString().trim(),
    );
  }
}

class ProductionAiDraftTaskPreview {
  final String id;
  final String title;
  final String phaseName;
  final String roleRequired;
  final int requiredHeadcount;
  final int assignedCount;
  final List<String> assignedStaffProfileIds;
  final String status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final int manualSortOrder;
  final String instructions;
  final bool hasShortage;

  const ProductionAiDraftTaskPreview({
    required this.id,
    required this.title,
    required this.phaseName,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.assignedCount,
    required this.assignedStaffProfileIds,
    required this.status,
    required this.startDate,
    required this.dueDate,
    required this.manualSortOrder,
    required this.instructions,
    required this.hasShortage,
  });

  factory ProductionAiDraftTaskPreview.fromJson(
    Map<String, dynamic> json, {
    required ProductionAiDraftCapacity? capacity,
    required int index,
  }) {
    final assignedIds = _parseDraftStringList(
      json[_payloadTaskStaffProfileIds],
    );
    final requiredHeadcount =
        int.tryParse(json[_payloadTaskRequiredHeadcount]?.toString() ?? "") ??
        1;
    final assignedCount =
        int.tryParse(json[_payloadAssignedCount]?.toString() ?? "") ??
        assignedIds.length;
    final role = (json[_payloadTaskRole] ?? "").toString().trim();
    final availableCapacity = capacity?.availableForRole(role) ?? 0;
    final hasCapacitySnapshot = capacity != null;
    final normalizedRequiredHeadcount = requiredHeadcount < assignedIds.length
        ? assignedIds.length
        : (requiredHeadcount < 1 ? 1 : requiredHeadcount);
    return ProductionAiDraftTaskPreview(
      // WHY: Backend may return taskId instead of id; keep parsing backward compatible.
      id: (json["taskId"] ?? json["_id"] ?? json["id"] ?? "task_$index")
          .toString()
          .trim(),
      title: (json[_payloadTaskTitle] ?? _defaultTaskTitle).toString().trim(),
      phaseName: (json[_payloadPhaseName] ?? "").toString().trim(),
      roleRequired: role,
      requiredHeadcount: normalizedRequiredHeadcount,
      assignedCount: assignedCount < 0 ? 0 : assignedCount,
      assignedStaffProfileIds: assignedIds,
      status: (json["status"] ?? "").toString().trim(),
      startDate: DateTime.tryParse((json[_payloadStartDate] ?? "").toString()),
      dueDate: DateTime.tryParse((json["dueDate"] ?? "").toString()),
      manualSortOrder:
          int.tryParse(json[_payloadTaskManualSortOrder]?.toString() ?? "") ??
          index,
      instructions: (json[_payloadTaskInstructions] ?? "").toString().trim(),
      // WHY: Show shortage when required exceeds available, including zero-capacity roles.
      hasShortage: hasCapacitySnapshot
          ? normalizedRequiredHeadcount > availableCapacity
          : false,
    );
  }
}

class ProductionAiDraftResult {
  final ProductionPlanDraftState draft;
  final String status;
  final ProductionAiDraftPartialIssue? partialIssue;
  final String message;
  final ProductionAiDraftSummary? summary;
  final ProductionAiDraftSchedulePolicy? schedulePolicy;
  final ProductionAiDraftCapacity? capacity;
  final List<String> warnings;
  final List<ProductionAiDraftTaskPreview> tasks;
  final ProductionAssistantPlannerMeta? plannerMeta;
  final ProductionAssistantLifecycle? lifecycle;

  const ProductionAiDraftResult({
    required this.draft,
    required this.status,
    required this.partialIssue,
    required this.message,
    required this.summary,
    required this.schedulePolicy,
    required this.capacity,
    required this.warnings,
    required this.tasks,
    this.plannerMeta,
    this.lifecycle,
  });
}

class ProductionTaskDraft {
  final String id;
  final String title;
  final String roleRequired;
  final String? assignedStaffId;
  final List<String> assignedStaffProfileIds;
  final int requiredHeadcount;
  final int weight;
  final DateTime? scheduledStart;
  final DateTime? scheduledDue;
  final int manualSortOrder;
  final String instructions;
  final String taskType;
  final String sourceTemplateKey;
  final String recurrenceGroupKey;
  final int occurrenceIndex;
  final ProductionTaskStatus status;
  final DateTime? completedAt;
  final String? completedByStaffId;

  const ProductionTaskDraft({
    required this.id,
    required this.title,
    required this.roleRequired,
    required this.assignedStaffId,
    required this.assignedStaffProfileIds,
    required this.requiredHeadcount,
    required this.weight,
    required this.scheduledStart,
    required this.scheduledDue,
    this.manualSortOrder = 0,
    required this.instructions,
    this.taskType = _emptyText,
    this.sourceTemplateKey = _emptyText,
    this.recurrenceGroupKey = _emptyText,
    this.occurrenceIndex = 0,
    required this.status,
    required this.completedAt,
    required this.completedByStaffId,
  });

  ProductionTaskDraft copyWith({
    String? title,
    String? roleRequired,
    Object? assignedStaffId = _unsetValue,
    List<String>? assignedStaffProfileIds,
    int? requiredHeadcount,
    int? weight,
    Object? scheduledStart = _unsetValue,
    Object? scheduledDue = _unsetValue,
    int? manualSortOrder,
    String? instructions,
    String? taskType,
    String? sourceTemplateKey,
    String? recurrenceGroupKey,
    int? occurrenceIndex,
    ProductionTaskStatus? status,
    Object? completedAt = _unsetValue,
    Object? completedByStaffId = _unsetValue,
  }) {
    final resolvedCompletedAt = completedAt == _unsetValue
        ? this.completedAt
        : completedAt as DateTime?;
    final resolvedCompletedBy = completedByStaffId == _unsetValue
        ? this.completedByStaffId
        : completedByStaffId as String?;
    final resolvedAssignedStaffId = assignedStaffId == _unsetValue
        ? this.assignedStaffId
        : assignedStaffId as String?;
    final resolvedScheduledStart = scheduledStart == _unsetValue
        ? this.scheduledStart
        : scheduledStart as DateTime?;
    final resolvedScheduledDue = scheduledDue == _unsetValue
        ? this.scheduledDue
        : scheduledDue as DateTime?;
    return ProductionTaskDraft(
      id: id,
      title: title ?? this.title,
      roleRequired: roleRequired ?? this.roleRequired,
      assignedStaffId: resolvedAssignedStaffId,
      assignedStaffProfileIds:
          assignedStaffProfileIds ?? this.assignedStaffProfileIds,
      requiredHeadcount: requiredHeadcount ?? this.requiredHeadcount,
      weight: weight ?? this.weight,
      scheduledStart: resolvedScheduledStart,
      scheduledDue: resolvedScheduledDue,
      manualSortOrder: manualSortOrder ?? this.manualSortOrder,
      instructions: instructions ?? this.instructions,
      taskType: taskType ?? this.taskType,
      sourceTemplateKey: sourceTemplateKey ?? this.sourceTemplateKey,
      recurrenceGroupKey: recurrenceGroupKey ?? this.recurrenceGroupKey,
      occurrenceIndex: occurrenceIndex ?? this.occurrenceIndex,
      status: status ?? this.status,
      completedAt: resolvedCompletedAt,
      completedByStaffId: resolvedCompletedBy,
    );
  }
}

class ProductionPhaseDraft {
  final String name;
  final int order;
  final int estimatedDays;
  final String phaseType;
  final int requiredUnits;
  final double minRatePerFarmerHour;
  final double targetRatePerFarmerHour;
  final double plannedHoursPerDay;
  final int biologicalMinDays;
  final List<ProductionTaskDraft> tasks;

  const ProductionPhaseDraft({
    required this.name,
    required this.order,
    required this.estimatedDays,
    this.phaseType = "finite",
    this.requiredUnits = 0,
    this.minRatePerFarmerHour = 0.1,
    this.targetRatePerFarmerHour = 0.2,
    this.plannedHoursPerDay = 3,
    this.biologicalMinDays = 0,
    required this.tasks,
  });

  ProductionPhaseDraft copyWith({
    int? estimatedDays,
    String? phaseType,
    int? requiredUnits,
    double? minRatePerFarmerHour,
    double? targetRatePerFarmerHour,
    double? plannedHoursPerDay,
    int? biologicalMinDays,
    List<ProductionTaskDraft>? tasks,
  }) {
    return ProductionPhaseDraft(
      name: name,
      order: order,
      estimatedDays: estimatedDays ?? this.estimatedDays,
      phaseType: phaseType ?? this.phaseType,
      requiredUnits: requiredUnits ?? this.requiredUnits,
      minRatePerFarmerHour: minRatePerFarmerHour ?? this.minRatePerFarmerHour,
      targetRatePerFarmerHour:
          targetRatePerFarmerHour ?? this.targetRatePerFarmerHour,
      plannedHoursPerDay: plannedHoursPerDay ?? this.plannedHoursPerDay,
      biologicalMinDays: biologicalMinDays ?? this.biologicalMinDays,
      tasks: tasks ?? this.tasks,
    );
  }
}

class ProductionPlanDraftState {
  final String title;
  final String notes;
  final String domainContext;
  final String? estateAssetId;
  final String? productId;
  final DateTime? startDate;
  final DateTime? endDate;
  final ProductionPlantingTargetsDraft plantingTargets;
  final ProductDraft? proposedProduct;
  final bool productAiSuggested;
  final bool startDateAiSuggested;
  final bool endDateAiSuggested;
  final bool aiGenerated;
  final int totalTasks;
  final int totalEstimatedDays;
  final List<String> riskNotes;
  final List<ProductionPhaseDraft> phases;

  const ProductionPlanDraftState({
    required this.title,
    required this.notes,
    required this.domainContext,
    required this.estateAssetId,
    required this.productId,
    required this.startDate,
    required this.endDate,
    required this.plantingTargets,
    required this.proposedProduct,
    required this.productAiSuggested,
    required this.startDateAiSuggested,
    required this.endDateAiSuggested,
    required this.aiGenerated,
    required this.totalTasks,
    required this.totalEstimatedDays,
    required this.riskNotes,
    required this.phases,
  });

  ProductionPlanDraftState copyWith({
    String? title,
    String? notes,
    String? domainContext,
    Object? estateAssetId = _unsetValue,
    Object? productId = _unsetValue,
    Object? startDate = _unsetValue,
    Object? endDate = _unsetValue,
    ProductionPlantingTargetsDraft? plantingTargets,
    Object? proposedProduct = _unsetValue,
    bool? productAiSuggested,
    bool? startDateAiSuggested,
    bool? endDateAiSuggested,
    bool? aiGenerated,
    int? totalTasks,
    int? totalEstimatedDays,
    List<String>? riskNotes,
    List<ProductionPhaseDraft>? phases,
  }) {
    return ProductionPlanDraftState(
      title: title ?? this.title,
      notes: notes ?? this.notes,
      domainContext: domainContext ?? this.domainContext,
      estateAssetId: estateAssetId == _unsetValue
          ? this.estateAssetId
          : estateAssetId as String?,
      productId: productId == _unsetValue
          ? this.productId
          : productId as String?,
      startDate: startDate == _unsetValue
          ? this.startDate
          : startDate as DateTime?,
      endDate: endDate == _unsetValue ? this.endDate : endDate as DateTime?,
      plantingTargets: plantingTargets ?? this.plantingTargets,
      proposedProduct: proposedProduct == _unsetValue
          ? this.proposedProduct
          : proposedProduct as ProductDraft?,
      productAiSuggested: productAiSuggested ?? this.productAiSuggested,
      startDateAiSuggested: startDateAiSuggested ?? this.startDateAiSuggested,
      endDateAiSuggested: endDateAiSuggested ?? this.endDateAiSuggested,
      aiGenerated: aiGenerated ?? this.aiGenerated,
      totalTasks: totalTasks ?? this.totalTasks,
      totalEstimatedDays: totalEstimatedDays ?? this.totalEstimatedDays,
      riskNotes: riskNotes ?? this.riskNotes,
      phases: phases ?? this.phases,
    );
  }
}

class ProductionPlanDraftController
    extends StateNotifier<ProductionPlanDraftState> {
  ProductionPlanDraftController()
    : super(
        ProductionPlanDraftState(
          title: _emptyText,
          notes: _emptyText,
          domainContext: productionDomainDefault,
          estateAssetId: null,
          productId: null,
          startDate: null,
          endDate: null,
          plantingTargets: const ProductionPlantingTargetsDraft(
            materialType: "",
            plannedPlantingQuantity: null,
            plannedPlantingUnit: "",
            estimatedHarvestQuantity: null,
            estimatedHarvestUnit: "",
          ),
          proposedProduct: null,
          productAiSuggested: false,
          startDateAiSuggested: false,
          endDateAiSuggested: false,
          aiGenerated: false,
          phases: _buildDefaultPhases(),
          totalTasks: 0,
          totalEstimatedDays:
              _defaultPhaseNames.length * _defaultPhaseEstimatedDays,
          riskNotes: const [],
        ),
      ) {
    AppDebug.log(_logTag, _logInit);
  }

  void updateTitle(String value) {
    // WHY: Title helps distinguish plans in list views.
    state = state.copyWith(title: value);
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldTitle});
  }

  void updateNotes(String value) {
    // WHY: Notes capture plan context for managers.
    state = state.copyWith(notes: value);
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldNotes});
  }

  void updateDomainContext(String? value) {
    // WHY: Domain context is an optional hint that biases AI planning.
    final nextDomain = normalizeProductionDomainContext(value);
    state = state.copyWith(
      domainContext: nextDomain,
      plantingTargets: withDefaultProductionPlantingTargetsForDomain(
        state.plantingTargets,
        nextDomain,
      ),
    );
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldDomainContext},
    );
  }

  void updateEstate(String? estateAssetId) {
    // WHY: Estate scope is required for plan creation.
    state = state.copyWith(estateAssetId: estateAssetId);
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldEstate});
  }

  void updateProduct(String? productId) {
    // WHY: Product links plan output to inventory.
    state = state.copyWith(
      productId: productId,
      proposedProduct: null,
      productAiSuggested: false,
    );
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldProduct});
  }

  void updateStartDate(DateTime? date) {
    // WHY: Start date drives phase and task scheduling.
    state = state.copyWith(
      startDate: _normalizeDraftCalendarDate(date),
      startDateAiSuggested: false,
    );
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldStartDate});
  }

  void updateEndDate(DateTime? date) {
    // WHY: End date drives phase and task scheduling.
    state = state.copyWith(
      endDate: _normalizeDraftCalendarDate(date),
      endDateAiSuggested: false,
    );
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldEndDate});
  }

  void updatePlantingMaterialType(String? value) {
    state = state.copyWith(
      plantingTargets: state.plantingTargets.copyWith(
        materialType: (value ?? "").trim().toLowerCase(),
      ),
    );
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldPlantingTargets},
    );
  }

  void updatePlannedPlantingQuantity(double? value) {
    state = state.copyWith(
      plantingTargets: state.plantingTargets.copyWith(
        plannedPlantingQuantity: value == null || value < 0 ? null : value,
      ),
    );
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldPlantingTargets},
    );
  }

  void updatePlannedPlantingUnit(String? value) {
    state = state.copyWith(
      plantingTargets: state.plantingTargets.copyWith(
        plannedPlantingUnit: normalizeProductionPlantingTargetUnit(value),
      ),
    );
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldPlantingTargets},
    );
  }

  void updateEstimatedHarvestQuantity(double? value) {
    state = state.copyWith(
      plantingTargets: state.plantingTargets.copyWith(
        estimatedHarvestQuantity: value == null || value < 0 ? null : value,
      ),
    );
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldPlantingTargets},
    );
  }

  void updateEstimatedHarvestUnit(String? value) {
    state = state.copyWith(
      plantingTargets: state.plantingTargets.copyWith(
        estimatedHarvestUnit: normalizeProductionPlantingTargetUnit(value),
      ),
    );
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldPlantingTargets},
    );
  }

  void updateAiGenerated(bool value) {
    // WHY: AI drafts require review before activation.
    state = state.copyWith(aiGenerated: value);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldAiGenerated},
    );
  }

  void reset() {
    // WHY: Reset clears draft after successful submission.
    state = ProductionPlanDraftState(
      title: _emptyText,
      notes: _emptyText,
      domainContext: productionDomainDefault,
      estateAssetId: null,
      productId: null,
      startDate: null,
      endDate: null,
      plantingTargets: const ProductionPlantingTargetsDraft(
        materialType: "",
        plannedPlantingQuantity: null,
        plannedPlantingUnit: "",
        estimatedHarvestQuantity: null,
        estimatedHarvestUnit: "",
      ),
      proposedProduct: null,
      productAiSuggested: false,
      startDateAiSuggested: false,
      endDateAiSuggested: false,
      aiGenerated: false,
      phases: _buildDefaultPhases(),
      totalTasks: 0,
      totalEstimatedDays:
          _defaultPhaseNames.length * _defaultPhaseEstimatedDays,
      riskNotes: const [],
    );
    AppDebug.log(_logTag, _logReset);
  }

  void applyDraft(ProductionPlanDraftState draft) {
    // WHY: Replace the entire draft when AI provides a new structure.
    state = _withComputedSummary(draft);
    AppDebug.log(
      _logTag,
      _logDraftApplied,
      extra: {_extraPhaseCountKey: draft.phases.length},
    );
  }

  ProductionTaskDraft _buildDefaultTaskDraft() {
    return ProductionTaskDraft(
      id: _buildTaskId(),
      title: _defaultTaskTitle,
      roleRequired: staffRoleValues.first,
      assignedStaffId: null,
      assignedStaffProfileIds: const [],
      requiredHeadcount: 1,
      weight: _defaultTaskWeight,
      scheduledStart: null,
      scheduledDue: null,
      manualSortOrder: 0,
      instructions: _emptyText,
      taskType: _emptyText,
      sourceTemplateKey: _emptyText,
      recurrenceGroupKey: _emptyText,
      occurrenceIndex: 0,
      status: _defaultTaskStatus,
      completedAt: null,
      completedByStaffId: null,
    );
  }

  String? addTask(int phaseIndex) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return null;
    }

    final task = _buildDefaultTaskDraft();

    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    final updatedTasks = [...phase.tasks, task];
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);

    state = _withComputedSummary(state.copyWith(phases: phases));
    AppDebug.log(_logTag, _logTaskAdded, extra: {_extraPhaseKey: phase.name});
    return task.id;
  }

  String? addTaskAt(int phaseIndex, int taskIndex) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return null;
    }

    final task = _buildDefaultTaskDraft();
    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    final safeTaskIndex = taskIndex.clamp(0, phase.tasks.length);
    final updatedTasks = [...phase.tasks];
    updatedTasks.insert(safeTaskIndex, task);
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);

    state = _withComputedSummary(state.copyWith(phases: phases));
    AppDebug.log(
      _logTag,
      _logTaskAdded,
      extra: {_extraPhaseKey: phase.name, _extraTaskIndexKey: safeTaskIndex},
    );
    return task.id;
  }

  String? duplicateTask(int phaseIndex, String taskId) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return null;
    }

    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    final taskIndex = phase.tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex < 0) {
      return null;
    }

    final source = phase.tasks[taskIndex];
    final duplicate = source.copyWith(
      title: source.title.trim().isEmpty ? _defaultTaskTitle : source.title,
      status: _defaultTaskStatus,
      completedAt: null,
      completedByStaffId: null,
      manualSortOrder: source.manualSortOrder,
    );
    final duplicatedTask = ProductionTaskDraft(
      id: _buildTaskId(),
      title: duplicate.title,
      roleRequired: duplicate.roleRequired,
      assignedStaffId: duplicate.assignedStaffId,
      assignedStaffProfileIds: duplicate.assignedStaffProfileIds,
      requiredHeadcount: duplicate.requiredHeadcount,
      weight: duplicate.weight,
      scheduledStart: duplicate.scheduledStart,
      scheduledDue: duplicate.scheduledDue,
      manualSortOrder: duplicate.manualSortOrder,
      instructions: duplicate.instructions,
      taskType: duplicate.taskType,
      sourceTemplateKey: duplicate.sourceTemplateKey,
      recurrenceGroupKey: duplicate.recurrenceGroupKey,
      occurrenceIndex: duplicate.occurrenceIndex,
      status: duplicate.status,
      completedAt: duplicate.completedAt,
      completedByStaffId: duplicate.completedByStaffId,
    );
    final updatedTasks = [...phase.tasks];
    updatedTasks.insert(taskIndex + 1, duplicatedTask);
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);

    state = _withComputedSummary(state.copyWith(phases: phases));
    AppDebug.log(
      _logTag,
      _logTaskAdded,
      extra: {
        _extraPhaseKey: phase.name,
        _extraTaskIdKey: duplicatedTask.id,
        "duplicatedFrom": taskId,
      },
    );
    return duplicatedTask.id;
  }

  void moveTaskWithinPhase(int phaseIndex, int fromTaskIndex, int toTaskIndex) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return;
    }
    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    if (fromTaskIndex < 0 || fromTaskIndex >= phase.tasks.length) {
      return;
    }
    final boundedTarget = toTaskIndex.clamp(0, phase.tasks.length);
    final updatedTasks = [...phase.tasks];
    final movedTask = updatedTasks.removeAt(fromTaskIndex);
    final insertIndex = fromTaskIndex < boundedTarget
        ? boundedTarget - 1
        : boundedTarget;
    updatedTasks.insert(insertIndex.clamp(0, updatedTasks.length), movedTask);
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);
    state = _withComputedSummary(state.copyWith(phases: phases));
  }

  void moveTaskAcrossPhases(
    int fromPhaseIndex,
    int fromTaskIndex,
    int toPhaseIndex,
    int toTaskIndex,
  ) {
    if (fromPhaseIndex < _minIndex ||
        fromPhaseIndex >= state.phases.length ||
        toPhaseIndex < _minIndex ||
        toPhaseIndex >= state.phases.length) {
      return;
    }
    final phases = [...state.phases];
    final sourcePhase = phases[fromPhaseIndex];
    final targetPhase = phases[toPhaseIndex];
    if (fromTaskIndex < 0 || fromTaskIndex >= sourcePhase.tasks.length) {
      return;
    }
    final sourceTasks = [...sourcePhase.tasks];
    final movedTask = sourceTasks.removeAt(fromTaskIndex);
    final targetTasks = fromPhaseIndex == toPhaseIndex
        ? sourceTasks
        : [...targetPhase.tasks];
    final safeInsertIndex = toTaskIndex.clamp(0, targetTasks.length);
    targetTasks.insert(safeInsertIndex, movedTask);
    phases[fromPhaseIndex] = sourcePhase.copyWith(tasks: sourceTasks);
    phases[toPhaseIndex] = targetPhase.copyWith(tasks: targetTasks);
    state = _withComputedSummary(state.copyWith(phases: phases));
  }

  void updateTaskSchedule(
    int phaseIndex,
    String taskId, {
    DateTime? startDate,
    DateTime? dueDate,
  }) {
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(scheduledStart: startDate, scheduledDue: dueDate),
    );
  }

  void updateTaskSortOrder(int phaseIndex, String taskId, int manualSortOrder) {
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(manualSortOrder: manualSortOrder),
    );
  }

  void removeTask(int phaseIndex, String taskId) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return;
    }

    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    final updatedTasks = phase.tasks
        .where((task) => task.id != taskId)
        .toList();
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);

    state = _withComputedSummary(state.copyWith(phases: phases));
    AppDebug.log(_logTag, _logTaskRemoved, extra: {_extraPhaseKey: phase.name});
  }

  void updateTaskTitle(int phaseIndex, String taskId, String title) {
    _updateTask(phaseIndex, taskId, (task) => task.copyWith(title: title));
  }

  void updateTaskRole(int phaseIndex, String taskId, String role) {
    // WHY: Role change invalidates current staff assignment.
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(
        roleRequired: role,
        assignedStaffId: null,
        assignedStaffProfileIds: const [],
        status: _defaultTaskStatus,
        completedAt: null,
        completedByStaffId: null,
      ),
    );
  }

  void updateTaskStaff(int phaseIndex, String taskId, String? staffId) {
    updateTaskAssignedStaffProfiles(
      phaseIndex,
      taskId,
      staffId == null || staffId.trim().isEmpty ? const [] : [staffId],
    );
  }

  void updateTaskAssignedStaffProfiles(
    int phaseIndex,
    String taskId,
    List<String> staffProfileIds,
  ) {
    final normalizedAssignedIds = _parseDraftStringList(staffProfileIds);
    // WHY: Assignment changes should clear completion metadata to avoid drift.
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(
        assignedStaffId: normalizedAssignedIds.isEmpty
            ? null
            : normalizedAssignedIds.first,
        assignedStaffProfileIds: normalizedAssignedIds,
        requiredHeadcount: task.requiredHeadcount < normalizedAssignedIds.length
            ? normalizedAssignedIds.length
            : (task.requiredHeadcount < 1 ? 1 : task.requiredHeadcount),
        status: _defaultTaskStatus,
        completedAt: null,
        completedByStaffId: null,
      ),
    );
  }

  void updateTaskRequiredHeadcount(
    int phaseIndex,
    String taskId,
    int requiredHeadcount,
  ) {
    _updateTask(phaseIndex, taskId, (task) {
      final minimumFromAssignments = task.assignedStaffProfileIds.isEmpty
          ? 1
          : task.assignedStaffProfileIds.length;
      final normalizedHeadcount = requiredHeadcount < minimumFromAssignments
          ? minimumFromAssignments
          : requiredHeadcount;
      return task.copyWith(requiredHeadcount: normalizedHeadcount);
    });
  }

  void updateTaskWeight(int phaseIndex, String taskId, int weight) {
    _updateTask(phaseIndex, taskId, (task) => task.copyWith(weight: weight));
  }

  void updateTaskInstructions(int phaseIndex, String taskId, String value) {
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(instructions: value),
    );
  }

  void updateTaskStatus(
    int phaseIndex,
    String taskId,
    ProductionTaskStatus status,
  ) {
    final phaseName =
        phaseIndex >= _minIndex && phaseIndex < state.phases.length
        ? state.phases[phaseIndex].name
        : _emptyText;
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(
        status: status,
        completedAt: status == ProductionTaskStatus.done
            ? DateTime.now()
            : null,
        completedByStaffId: status == ProductionTaskStatus.done
            ? task.assignedStaffId
            : null,
      ),
    );
    AppDebug.log(
      _logTag,
      _logTaskStatusUpdated,
      extra: {
        _extraTaskIdKey: taskId,
        _extraStatusKey: status.name,
        _extraPhaseKey: phaseName,
      },
    );
  }

  void markTaskDone(int phaseIndex, String taskId) {
    // WHY: Done sets completion metadata for quick tracking in the table.
    updateTaskStatus(phaseIndex, taskId, ProductionTaskStatus.done);
    AppDebug.log(_logTag, _logTaskDone, extra: {_extraTaskIdKey: taskId});
  }

  void clearTaskDone(int phaseIndex, String taskId) {
    // WHY: Clearing done resets the status and completion fields.
    updateTaskStatus(phaseIndex, taskId, ProductionTaskStatus.notStarted);
    AppDebug.log(
      _logTag,
      _logTaskCleared,
      extra: {_extraTaskIdKey: taskId, _extraCompletedAtKey: "cleared"},
    );
  }

  List<String> validate() {
    final errors = <String>[];
    final normalizedStartDate = _normalizeDraftCalendarDate(state.startDate);
    final normalizedEndDate = _normalizeDraftCalendarDate(state.endDate);

    if (state.title.trim().isEmpty) {
      errors.add(_errorTitleRequired);
    }
    if (state.estateAssetId == null || state.estateAssetId!.trim().isEmpty) {
      errors.add(_errorEstateRequired);
    }
    if (state.productId == null || state.productId!.trim().isEmpty) {
      errors.add(_errorProductRequired);
    }
    if (normalizedStartDate == null) {
      errors.add(_errorStartDateRequired);
    }
    if (normalizedEndDate == null) {
      errors.add(_errorEndDateRequired);
    }
    if (normalizedStartDate != null &&
        normalizedEndDate != null &&
        !normalizedEndDate.isAfter(normalizedStartDate)) {
      errors.add(_errorDateRange);
    }
    errors.addAll(state.plantingTargets.validateForDomain(state.domainContext));

    final allTasks = state.phases.expand((phase) => phase.tasks).toList();
    if (allTasks.isEmpty) {
      errors.add(_errorTasksRequired);
    }

    for (final task in allTasks) {
      if (task.title.trim().isEmpty) {
        errors.add(_errorTaskTitleRequired);
        break;
      }
      if (task.roleRequired.trim().isEmpty) {
        errors.add(_errorTaskRoleRequired);
        break;
      }
      if (task.requiredHeadcount < 1) {
        errors.add(_errorTaskHeadcountRequired);
        break;
      }
      final hasScheduledStart = task.scheduledStart != null;
      final hasScheduledDue = task.scheduledDue != null;
      if (hasScheduledStart != hasScheduledDue) {
        errors.add(_errorTaskScheduleIncomplete);
        break;
      }
      if (hasScheduledStart && hasScheduledDue) {
        final normalizedTaskStart = _normalizeDraftLocalDateTime(
          task.scheduledStart,
        );
        final normalizedTaskDue = _normalizeDraftLocalDateTime(
          task.scheduledDue,
        );
        if (normalizedTaskStart == null ||
            normalizedTaskDue == null ||
            !normalizedTaskDue.isAfter(normalizedTaskStart)) {
          errors.add(_errorTaskScheduleInvalid);
          break;
        }
        if (normalizedStartDate != null && normalizedEndDate != null) {
          final planStart = normalizedStartDate;
          final planEndExclusive = normalizedEndDate.add(
            const Duration(days: 1),
          );
          if (normalizedTaskStart.isBefore(planStart) ||
              normalizedTaskDue.isAfter(planEndExclusive)) {
            errors.add(_errorTaskScheduleOutsideWindow);
            break;
          }
        }
      }
    }

    return errors;
  }

  Map<String, dynamic> toPayload() {
    var taskSortCursor = 0;
    final normalizedStartDate = _normalizeDraftCalendarDate(state.startDate);
    final normalizedEndDate = _normalizeDraftCalendarDate(state.endDate);
    final phasesPayload = state.phases.map((phase) {
      final taskPayloads = phase.tasks.map((task) {
        final normalizedSortOrder = taskSortCursor;
        taskSortCursor += 1;
        return {
          _payloadTaskTitle: task.title.trim(),
          _payloadTaskRole: task.roleRequired,
          _payloadTaskStaff: task.assignedStaffId,
          _payloadTaskStaffProfileIds: task.assignedStaffProfileIds,
          _payloadTaskRequiredHeadcount:
              // WHY: Payload keeps required slots aligned with selected assignees.
              task.requiredHeadcount < task.assignedStaffProfileIds.length
              ? task.assignedStaffProfileIds.length
              : (task.requiredHeadcount < 1 ? 1 : task.requiredHeadcount),
          _payloadTaskWeight: task.weight,
          _payloadTaskInstructions: task.instructions.trim(),
          _payloadTaskType: task.taskType.trim(),
          _payloadTaskSourceTemplateKey: task.sourceTemplateKey.trim(),
          _payloadTaskRecurrenceGroupKey: task.recurrenceGroupKey.trim(),
          _payloadTaskOccurrenceIndex: task.occurrenceIndex,
          _payloadTaskManualSortOrder: normalizedSortOrder,
          if (task.scheduledStart != null && task.scheduledDue != null) ...{
            _payloadTaskStartDate: task.scheduledStart!.toIso8601String(),
            _payloadTaskDueDate: task.scheduledDue!.toIso8601String(),
          },
          _payloadTaskDependencies: const [],
        };
      }).toList();

      return {
        _payloadPhaseName: phase.name,
        _payloadPhaseOrder: phase.order,
        _payloadPhaseEstimatedDays: phase.estimatedDays,
        _payloadPhaseType: phase.phaseType,
        _payloadPhaseRequiredUnits: phase.requiredUnits,
        _payloadPhaseMinRatePerFarmerHour: phase.minRatePerFarmerHour,
        _payloadPhaseTargetRatePerFarmerHour: phase.targetRatePerFarmerHour,
        _payloadPhasePlannedHoursPerDay: phase.plannedHoursPerDay,
        _payloadPhaseBiologicalMinDays: phase.biologicalMinDays,
        _payloadTasks: taskPayloads,
      };
    }).toList();

    return {
      _payloadEstateId: state.estateAssetId,
      _payloadProductId: state.productId,
      _payloadTitle: state.title.trim(),
      _payloadNotes: state.notes.trim(),
      _payloadDomainContext: normalizeProductionDomainContext(
        state.domainContext,
      ),
      _payloadStartDate: normalizedStartDate?.toIso8601String(),
      _payloadEndDate: normalizedEndDate?.toIso8601String(),
      _payloadAiGenerated: state.aiGenerated,
      _payloadPlantingTargets: state.plantingTargets.toPayload(),
      _payloadPhases: phasesPayload,
    };
  }

  void _updateTask(
    int phaseIndex,
    String taskId,
    ProductionTaskDraft Function(ProductionTaskDraft task) updater,
  ) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return;
    }

    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    final updatedTasks = phase.tasks
        .map((task) => task.id == taskId ? updater(task) : task)
        .toList();
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);

    state = _withComputedSummary(state.copyWith(phases: phases));
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldTask});
  }
}

ProductionPlanDraftState _withComputedSummary(ProductionPlanDraftState draft) {
  // WHY: Keep summary counters synchronized with local task edits.
  final normalizedDraft = draft.copyWith(
    startDate: _normalizeDraftCalendarDate(draft.startDate),
    endDate: _normalizeDraftCalendarDate(draft.endDate),
  );
  final normalizedPhases = _withNormalizedTaskSortOrders(
    normalizedDraft.phases,
  );
  final totalTasks = normalizedDraft.phases.fold<int>(
    0,
    (sum, phase) => sum + phase.tasks.length,
  );
  final totalEstimatedDays = normalizedDraft.phases.fold<int>(
    0,
    (sum, phase) => sum + phase.estimatedDays,
  );
  return normalizedDraft.copyWith(
    totalTasks: totalTasks,
    totalEstimatedDays: totalEstimatedDays,
    phases: normalizedPhases,
  );
}

List<ProductionPhaseDraft> _withNormalizedTaskSortOrders(
  List<ProductionPhaseDraft> phases,
) {
  var sortCursor = 0;
  return phases.map((phase) {
    final normalizedTasks = phase.tasks.map((task) {
      final nextTask = task.copyWith(manualSortOrder: sortCursor);
      sortCursor += 1;
      return nextTask;
    }).toList();
    return phase.copyWith(tasks: normalizedTasks);
  }).toList();
}

final productionPlanDraftProvider =
    StateNotifierProvider<
      ProductionPlanDraftController,
      ProductionPlanDraftState
    >((ref) => ProductionPlanDraftController());

ProductionAiDraftResult parseProductionPlanDraftResponse(
  Map<String, dynamic> json,
) {
  final statusRaw = (json[_responseStatusKey] ?? _statusAiDraftSuccess)
      .toString()
      .trim();
  final isPartial = statusRaw == _statusAiDraftPartial;
  final normalizedDraft = _normalizeIncomingDraftPayload(json);
  if (normalizedDraft == null) {
    throw ProductionAiDraftError.schema(
      missing: [_responseDraftKey],
      invalid: const [],
      message: _aiDraftFallbackMessage,
    );
  }

  final diagnostics = _validateDraftMap(normalizedDraft);
  if (diagnostics.missing.isNotEmpty || diagnostics.invalid.isNotEmpty) {
    AppDebug.log(
      _logTag,
      _aiDraftFallbackErrorCode,
      extra: {
        _extraMissingKey: diagnostics.missing,
        _extraInvalidKey: diagnostics.invalid,
      },
    );
    throw ProductionAiDraftError.schema(
      missing: diagnostics.missing,
      invalid: diagnostics.invalid,
      message: _aiDraftFallbackMessage,
    );
  }

  final parsed = _buildStrictDraftState(normalizedDraft);
  AppDebug.log(
    _logTag,
    _logDraftParsed,
    extra: {
      _extraPhaseCountKey: parsed.phases.length,
      _extraIssueTypeKey:
          json[_responseIssueTypeKey]?.toString().trim() ?? _emptyText,
    },
  );
  final issueType = isPartial
      ? (json[_responseIssueTypeKey] ?? _issueTypeInsufficientContext)
            .toString()
            .trim()
      : _emptyText;
  final message = (json[_responseMessageKey] ?? _emptyText).toString().trim();
  final partialIssue = isPartial
      ? ProductionAiDraftPartialIssue(
          issueType: issueType,
          message: message.isEmpty ? _aiDraftFallbackMessage : message,
        )
      : null;
  final summaryMap = json[_payloadSummary];
  final schedulePolicyMap = json[_payloadSchedulePolicy];
  final capacityMap = json[_payloadCapacity];
  final parsedSummary = summaryMap is Map<String, dynamic>
      ? ProductionAiDraftSummary.fromJson(summaryMap)
      : null;
  final parsedSchedulePolicy = schedulePolicyMap is Map<String, dynamic>
      ? ProductionAiDraftSchedulePolicy.fromJson(schedulePolicyMap)
      : null;
  final parsedCapacity = capacityMap is Map<String, dynamic>
      ? ProductionAiDraftCapacity.fromJson(capacityMap)
      : null;
  final warnings = _parseDraftWarnings(json[_payloadWarnings]);
  final tasksRaw = (json[_payloadDraftTasks] ?? []) as List<dynamic>;
  final plannerMetaMap =
      json["plannerMeta"] ??
      (normalizedDraft["plannerMeta"] is Map<String, dynamic>
          ? normalizedDraft["plannerMeta"]
          : null);
  final lifecycleMap =
      json["lifecycle"] ??
      (normalizedDraft["lifecycle"] is Map<String, dynamic>
          ? normalizedDraft["lifecycle"]
          : null);
  final tasks = tasksRaw
      .whereType<Map<String, dynamic>>()
      .toList()
      .asMap()
      .entries
      .map(
        (entry) => ProductionAiDraftTaskPreview.fromJson(
          entry.value,
          capacity: parsedCapacity,
          index: entry.key,
        ),
      )
      .toList();

  return ProductionAiDraftResult(
    draft: parsed,
    status: statusRaw.isEmpty ? _statusAiDraftSuccess : statusRaw,
    partialIssue: partialIssue,
    message: message,
    summary: parsedSummary,
    schedulePolicy: parsedSchedulePolicy,
    capacity: parsedCapacity,
    warnings: warnings,
    tasks: tasks,
    plannerMeta: plannerMetaMap is Map<String, dynamic>
        ? ProductionAssistantPlannerMeta.fromJson(plannerMetaMap)
        : null,
    lifecycle: lifecycleMap is Map<String, dynamic>
        ? ProductionAssistantLifecycle.fromJson(lifecycleMap)
        : null,
  );
}

Map<String, dynamic>? _normalizeIncomingDraftPayload(
  Map<String, dynamic> json,
) {
  final draftValue = json[_responseDraftKey];
  if (draftValue != null && draftValue is! Map<String, dynamic>) {
    return null;
  }

  final rawDraft = draftValue is Map<String, dynamic>
      ? Map<String, dynamic>.from(draftValue)
      : <String, dynamic>{};
  final normalizedPhases = _normalizeDraftPhases(
    rawDraft[_payloadPhases] ?? json[_payloadPhases],
  );
  final summarySource = rawDraft[_payloadSummary] is Map<String, dynamic>
      ? Map<String, dynamic>.from(
          rawDraft[_payloadSummary] as Map<String, dynamic>,
        )
      : json[_payloadSummary] is Map<String, dynamic>
      ? Map<String, dynamic>.from(json[_payloadSummary] as Map<String, dynamic>)
      : <String, dynamic>{};
  final warningMessages = _parseDraftWarnings(
    rawDraft[_payloadWarnings] ?? json[_payloadWarnings],
  );
  final riskNotes = _normalizeDraftRiskNotes(
    summarySource[_payloadSummaryRiskNotes],
    warningMessages,
  );

  return {
    ...rawDraft,
    _payloadPlanTitle: _resolveIncomingDraftTitle(rawDraft, json),
    _payloadNotes: _normalizeDraftText(
      rawDraft[_payloadNotes] ?? json[_payloadNotes],
    ),
    if (_isValidRequiredString(
      rawDraft[_payloadDomainContext] ?? json[_payloadDomainContext],
    ))
      _payloadDomainContext:
          (rawDraft[_payloadDomainContext] ?? json[_payloadDomainContext])
              .toString()
              .trim(),
    if (_isValidRequiredString(
      rawDraft[_payloadEstateId] ?? json[_payloadEstateId],
    ))
      _payloadEstateId: (rawDraft[_payloadEstateId] ?? json[_payloadEstateId])
          .toString()
          .trim(),
    if (_isValidRequiredString(
      rawDraft[_payloadProductId] ?? json[_payloadProductId],
    ))
      _payloadProductId:
          (rawDraft[_payloadProductId] ?? json[_payloadProductId])
              .toString()
              .trim(),
    if (_isValidIsoDate(
      (rawDraft[_payloadStartDate] ?? json[_payloadStartDate] ?? _emptyText)
          .toString(),
    ))
      _payloadStartDate:
          (rawDraft[_payloadStartDate] ?? json[_payloadStartDate])
              .toString()
              .trim(),
    if (_isValidIsoDate(
      (rawDraft[_payloadEndDate] ?? json[_payloadEndDate] ?? _emptyText)
          .toString(),
    ))
      _payloadEndDate: (rawDraft[_payloadEndDate] ?? json[_payloadEndDate])
          .toString()
          .trim(),
    if (_isValidIsoDate(
      (rawDraft[_payloadProposedStartDate] ??
              json[_payloadProposedStartDate] ??
              _emptyText)
          .toString(),
    ))
      _payloadProposedStartDate:
          (rawDraft[_payloadProposedStartDate] ??
                  json[_payloadProposedStartDate])
              .toString()
              .trim(),
    if (_isValidIsoDate(
      (rawDraft[_payloadProposedEndDate] ??
              json[_payloadProposedEndDate] ??
              _emptyText)
          .toString(),
    ))
      _payloadProposedEndDate:
          (rawDraft[_payloadProposedEndDate] ?? json[_payloadProposedEndDate])
              .toString()
              .trim(),
    if (!rawDraft.containsKey(_payloadProposedProduct) &&
        json[_payloadProposedProduct] is Map<String, dynamic>)
      _payloadProposedProduct: Map<String, dynamic>.from(
        json[_payloadProposedProduct] as Map<String, dynamic>,
      ),
    _payloadPhases: normalizedPhases,
    _payloadSummary: {
      ...summarySource,
      _payloadSummaryTotalTasks: _resolveDraftTotalTasks(
        summarySource[_payloadSummaryTotalTasks],
        normalizedPhases,
      ),
      _payloadSummaryTotalEstimatedDays: _resolveDraftTotalEstimatedDays(
        summarySource,
        normalizedPhases,
      ),
      _payloadSummaryRiskNotes: riskNotes,
    },
  };
}

String _resolveIncomingDraftTitle(
  Map<String, dynamic> draft,
  Map<String, dynamic> response,
) {
  final lifecycle = response["lifecycle"];
  final lifecycleProduct = lifecycle is Map<String, dynamic>
      ? lifecycle["product"]
      : null;
  final candidates = <dynamic>[
    draft[_payloadPlanTitle],
    draft[_payloadTitle],
    response[_payloadPlanTitle],
    response[_payloadTitle],
    draft["productName"],
    response["productName"],
    lifecycleProduct,
  ];
  for (final candidate in candidates) {
    final normalized = candidate?.toString().trim() ?? _emptyText;
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return "Production Plan";
}

String _normalizeDraftText(dynamic value) {
  if (value == null) {
    return _emptyText;
  }
  return value.toString().trim();
}

List<Map<String, dynamic>> _normalizeDraftPhases(dynamic value) {
  if (value is! List<dynamic>) {
    return const <Map<String, dynamic>>[];
  }

  return value.asMap().entries.map((entry) {
    final phaseIndex = entry.key;
    final phaseRaw = entry.value;
    if (phaseRaw is! Map<String, dynamic>) {
      return <String, dynamic>{
        _payloadPhaseName: "Phase ${phaseIndex + _phaseOrderOffset}",
        _payloadPhaseOrder: phaseIndex + _phaseOrderOffset,
        _payloadPhaseEstimatedDays: _phaseOrderOffset,
        _payloadTasks: const <Map<String, dynamic>>[],
      };
    }

    final tasks = _normalizeDraftTasks(phaseRaw[_payloadTasks]);
    final estimatedDays =
        _parseStrictInt(phaseRaw[_payloadPhaseEstimatedDays]) ??
        _phaseOrderOffset;
    final phaseOrder =
        _parseStrictInt(phaseRaw[_payloadPhaseOrder]) ??
        phaseIndex + _phaseOrderOffset;
    return {
      ...phaseRaw,
      _payloadPhaseName: _normalizeRequiredText(
        phaseRaw[_payloadPhaseName],
        "Phase $phaseOrder",
      ),
      _payloadPhaseOrder: phaseOrder < 1
          ? phaseIndex + _phaseOrderOffset
          : phaseOrder,
      _payloadPhaseEstimatedDays: estimatedDays < 1
          ? _phaseOrderOffset
          : estimatedDays,
      _payloadTasks: tasks,
    };
  }).toList();
}

List<Map<String, dynamic>> _normalizeDraftTasks(dynamic value) {
  if (value is! List<dynamic>) {
    return const <Map<String, dynamic>>[];
  }

  return value.whereType<Map<String, dynamic>>().map((task) {
    final normalizedWeight =
        _parseStrictInt(task[_payloadTaskWeight]) ?? _defaultTaskWeight;
    final normalizedHeadcount =
        _parseStrictInt(task[_payloadTaskRequiredHeadcount]) ??
        _phaseOrderOffset;
    final normalizedAssignedIds = _parseDraftStringList(
      task[_payloadTaskStaffProfileIds],
    );
    return {
      ...task,
      _payloadTaskTitle: _normalizeRequiredText(
        task[_payloadTaskTitle],
        _defaultTaskTitle,
      ),
      _payloadTaskRole: _normalizeRequiredText(
        task[_payloadTaskRole],
        "farmer",
      ),
      _payloadTaskInstructions: _normalizeDraftText(
        task[_payloadTaskInstructions],
      ),
      _payloadTaskWeight: normalizedWeight.clamp(
        _defaultTaskWeight,
        _maxTaskWeight,
      ),
      _payloadTaskRequiredHeadcount: normalizedHeadcount < 1
          ? _phaseOrderOffset
          : normalizedHeadcount,
      if (normalizedAssignedIds.isNotEmpty)
        _payloadTaskStaffProfileIds: normalizedAssignedIds,
      if (_isValidRequiredString(task[_payloadTaskStaff]))
        _payloadTaskStaff: task[_payloadTaskStaff].toString().trim(),
    };
  }).toList();
}

String _normalizeRequiredText(dynamic value, String fallback) {
  final normalized = value?.toString().trim() ?? _emptyText;
  return normalized.isEmpty ? fallback : normalized;
}

List<String> _normalizeDraftRiskNotes(
  dynamic value,
  List<String> warningMessages,
) {
  final baseNotes = value is List<dynamic>
      ? value
            .map((entry) => entry.toString().trim())
            .where((entry) => entry.isNotEmpty)
            .toList()
      : const <String>[];
  return {
    ...baseNotes,
    ...warningMessages,
  }.where((entry) => entry.isNotEmpty).toList();
}

int _resolveDraftTotalTasks(
  dynamic summaryValue,
  List<Map<String, dynamic>> normalizedPhases,
) {
  final parsed = _parseStrictInt(summaryValue);
  if (parsed != null && parsed >= 0) {
    return parsed;
  }
  return normalizedPhases.fold<int>(
    0,
    (sum, phase) =>
        sum + ((phase[_payloadTasks] as List<dynamic>? ?? const []).length),
  );
}

int _resolveDraftTotalEstimatedDays(
  Map<String, dynamic> summarySource,
  List<Map<String, dynamic>> normalizedPhases,
) {
  final directTotal = _parseStrictInt(
    summarySource[_payloadSummaryTotalEstimatedDays],
  );
  if (directTotal != null && directTotal >= 0) {
    return directTotal;
  }
  final planningDays = _parseStrictInt(summarySource[_payloadDays]);
  if (planningDays != null && planningDays >= 0) {
    return planningDays;
  }
  return normalizedPhases.fold<int>(
    0,
    (sum, phase) =>
        sum + (_parseStrictInt(phase[_payloadPhaseEstimatedDays]) ?? 0),
  );
}

List<ProductionPhaseDraft> _buildDefaultPhases() {
  return _defaultPhaseNames
      .asMap()
      .entries
      .map(
        (entry) => ProductionPhaseDraft(
          name: entry.value,
          order: entry.key + _phaseOrderOffset,
          estimatedDays: _defaultPhaseEstimatedDays,
          tasks: const [],
        ),
      )
      .toList();
}

String _buildTaskId() {
  return "$_taskIdPrefix${DateTime.now().microsecondsSinceEpoch}";
}

class _DraftValidation {
  final List<String> missing;
  final List<String> invalid;

  const _DraftValidation({required this.missing, required this.invalid});
}

_DraftValidation _validateDraftMap(Map<String, dynamic> draft) {
  final missing = <String>[];
  final invalid = <String>[];

  final titleValue = draft[_payloadPlanTitle] ?? draft[_payloadTitle];
  if (titleValue == null) {
    missing.add(_payloadPlanTitle);
  } else if (!_isValidRequiredString(titleValue)) {
    invalid.add(_payloadPlanTitle);
  }

  if (!draft.containsKey(_payloadNotes)) {
    missing.add(_payloadNotes);
  } else if (draft[_payloadNotes] is! String) {
    invalid.add(_payloadNotes);
  }
  final domainContextValue = draft[_payloadDomainContext];
  if (domainContextValue != null) {
    if (domainContextValue is! String) {
      invalid.add(_payloadDomainContext);
    } else if (domainContextValue.trim().isEmpty) {
      invalid.add(_payloadDomainContext);
    }
  }

  final startDateValue = draft[_payloadStartDate];
  final endDateValue = draft[_payloadEndDate];
  final proposedStartDateValue = draft[_payloadProposedStartDate];
  final proposedEndDateValue = draft[_payloadProposedEndDate];
  if (startDateValue != null && !_isValidIsoDate(startDateValue.toString())) {
    invalid.add(_payloadStartDate);
  }
  if (endDateValue != null && !_isValidIsoDate(endDateValue.toString())) {
    invalid.add(_payloadEndDate);
  }
  if (proposedStartDateValue != null &&
      !_isValidIsoDate(proposedStartDateValue.toString())) {
    invalid.add(_payloadProposedStartDate);
  }
  if (proposedEndDateValue != null &&
      !_isValidIsoDate(proposedEndDateValue.toString())) {
    invalid.add(_payloadProposedEndDate);
  }
  final resolvedStartDate =
      _isValidIsoDate(startDateValue?.toString() ?? _emptyText)
      ? startDateValue.toString()
      : _isValidIsoDate(proposedStartDateValue?.toString() ?? _emptyText)
      ? proposedStartDateValue.toString()
      : null;
  final resolvedEndDate =
      _isValidIsoDate(endDateValue?.toString() ?? _emptyText)
      ? endDateValue.toString()
      : _isValidIsoDate(proposedEndDateValue?.toString() ?? _emptyText)
      ? proposedEndDateValue.toString()
      : null;
  if (resolvedStartDate != null && resolvedEndDate != null) {
    final start = DateTime.parse(resolvedStartDate);
    final end = DateTime.parse(resolvedEndDate);
    if (!end.isAfter(start)) {
      invalid.add(_payloadEndDate);
    }
  }

  if (!_isValidRequiredString(draft[_payloadEstateId])) {
    if (draft[_payloadEstateId] == null) {
      missing.add(_payloadEstateId);
    } else {
      invalid.add(_payloadEstateId);
    }
  }
  final hasDirectProduct = _isValidRequiredString(draft[_payloadProductId]);
  final proposedProductValue = draft[_payloadProposedProduct];
  if (draft[_payloadProductId] != null &&
      !_isValidRequiredString(draft[_payloadProductId])) {
    invalid.add(_payloadProductId);
  }
  if (!hasDirectProduct && proposedProductValue != null) {
    if (proposedProductValue is! Map<String, dynamic>) {
      invalid.add(_payloadProposedProduct);
    } else {
      _validateRequiredStringField(
        proposedProductValue,
        "name",
        missing,
        invalid,
        phasePath: _payloadProposedProduct,
      );
      _validateRequiredStringField(
        proposedProductValue,
        "description",
        missing,
        invalid,
        phasePath: _payloadProposedProduct,
      );
      _validateRequiredIntField(
        proposedProductValue,
        "priceNgn",
        missing,
        invalid,
        phasePath: _payloadProposedProduct,
        minValue: 0,
      );
      _validateRequiredIntField(
        proposedProductValue,
        "stock",
        missing,
        invalid,
        phasePath: _payloadProposedProduct,
        minValue: 0,
      );
      if (proposedProductValue.containsKey("imageUrl") &&
          proposedProductValue["imageUrl"] != null &&
          proposedProductValue["imageUrl"] is! String) {
        invalid.add("$_payloadProposedProduct.imageUrl");
      }
    }
  }

  final phasesValue = draft[_payloadPhases];
  if (phasesValue == null) {
    missing.add(_payloadPhases);
  } else if (phasesValue is! List || phasesValue.isEmpty) {
    invalid.add(_payloadPhases);
  }

  if (phasesValue is List) {
    for (var phaseIndex = 0; phaseIndex < phasesValue.length; phaseIndex++) {
      final phasePath = "$_payloadPhases[$phaseIndex]";
      final phase = phasesValue[phaseIndex];
      if (phase is! Map<String, dynamic>) {
        invalid.add(phasePath);
        continue;
      }

      _validateRequiredStringField(
        phase,
        _payloadPhaseName,
        missing,
        invalid,
        phasePath: phasePath,
      );
      _validateRequiredIntField(
        phase,
        _payloadPhaseOrder,
        missing,
        invalid,
        phasePath: phasePath,
        minValue: 1,
      );
      _validateRequiredIntField(
        phase,
        _payloadPhaseEstimatedDays,
        missing,
        invalid,
        phasePath: phasePath,
        minValue: 1,
      );

      final tasks = phase[_payloadTasks];
      if (tasks == null) {
        missing.add("$phasePath.$_payloadTasks");
      } else if (tasks is! List) {
        invalid.add("$phasePath.$_payloadTasks");
      }

      if (tasks is List) {
        for (var taskIndex = 0; taskIndex < tasks.length; taskIndex++) {
          final taskPath = "$phasePath.$_payloadTasks[$taskIndex]";
          final task = tasks[taskIndex];
          if (task is! Map<String, dynamic>) {
            invalid.add(taskPath);
            continue;
          }

          _validateRequiredStringField(
            task,
            _payloadTaskTitle,
            missing,
            invalid,
            phasePath: taskPath,
          );
          _validateRequiredStringField(
            task,
            _payloadTaskRole,
            missing,
            invalid,
            phasePath: taskPath,
          );
          _validateRequiredStringField(
            task,
            _payloadTaskInstructions,
            missing,
            invalid,
            phasePath: taskPath,
          );
          _validateRequiredIntField(
            task,
            _payloadTaskWeight,
            missing,
            invalid,
            phasePath: taskPath,
            minValue: _defaultTaskWeight,
            maxValue: _maxTaskWeight,
          );

          if (task.containsKey(_payloadTaskStaff) &&
              task[_payloadTaskStaff] != null &&
              !_isValidRequiredString(task[_payloadTaskStaff])) {
            invalid.add("$taskPath.$_payloadTaskStaff");
          }
          if (task.containsKey(_payloadTaskStaffProfileIds) &&
              task[_payloadTaskStaffProfileIds] != null) {
            final assignedStaffProfileIds = task[_payloadTaskStaffProfileIds];
            if (assignedStaffProfileIds is! List) {
              invalid.add("$taskPath.$_payloadTaskStaffProfileIds");
            } else if (assignedStaffProfileIds.any(
              (item) => !_isValidRequiredString(item),
            )) {
              invalid.add("$taskPath.$_payloadTaskStaffProfileIds");
            }
          }
          if (task.containsKey(_payloadTaskRequiredHeadcount)) {
            final headcount =
                int.tryParse(task[_payloadTaskRequiredHeadcount].toString()) ??
                0;
            if (headcount < 1) {
              invalid.add("$taskPath.$_payloadTaskRequiredHeadcount");
            }
          }
        }
      }
    }
  }

  final summaryValue = draft[_payloadSummary];
  if (summaryValue == null) {
    missing.add(_payloadSummary);
  } else if (summaryValue is! Map<String, dynamic>) {
    invalid.add(_payloadSummary);
  }

  if (summaryValue is Map<String, dynamic>) {
    _validateRequiredIntField(
      summaryValue,
      _payloadSummaryTotalTasks,
      missing,
      invalid,
      phasePath: _payloadSummary,
      minValue: 0,
    );
    _validateRequiredIntField(
      summaryValue,
      _payloadSummaryTotalEstimatedDays,
      missing,
      invalid,
      phasePath: _payloadSummary,
      minValue: 0,
    );
    final riskNotes = summaryValue[_payloadSummaryRiskNotes];
    final riskPath = "$_payloadSummary.$_payloadSummaryRiskNotes";
    if (riskNotes == null) {
      missing.add(riskPath);
    } else if (riskNotes is! List ||
        riskNotes.any((item) => !_isValidRequiredString(item))) {
      invalid.add(riskPath);
    }
  }

  return _DraftValidation(missing: missing, invalid: invalid);
}

ProductionPlanDraftState _buildStrictDraftState(Map<String, dynamic> draft) {
  final phasesRaw = draft[_payloadPhases] as List<dynamic>;
  final summaryMap = draft[_payloadSummary] as Map<String, dynamic>;
  final startDateRaw = draft[_payloadStartDate];
  final endDateRaw = draft[_payloadEndDate];
  final domainContextRaw = draft[_payloadDomainContext];
  final proposedStartDateRaw = draft[_payloadProposedStartDate];
  final proposedEndDateRaw = draft[_payloadProposedEndDate];
  final plantingTargetsRaw = draft[_payloadPlantingTargets];
  final startDateString =
      _isValidIsoDate(startDateRaw?.toString() ?? _emptyText)
      ? startDateRaw.toString()
      : _isValidIsoDate(proposedStartDateRaw?.toString() ?? _emptyText)
      ? proposedStartDateRaw.toString()
      : null;
  final endDateString = _isValidIsoDate(endDateRaw?.toString() ?? _emptyText)
      ? endDateRaw.toString()
      : _isValidIsoDate(proposedEndDateRaw?.toString() ?? _emptyText)
      ? proposedEndDateRaw.toString()
      : null;
  final hasDirectProduct = _isValidRequiredString(draft[_payloadProductId]);
  final proposedProductRaw = draft[_payloadProposedProduct];
  final suggestedProduct =
      !hasDirectProduct && proposedProductRaw is Map<String, dynamic>
      ? ProductDraft.fromJson(proposedProductRaw)
      : null;
  final phases = <ProductionPhaseDraft>[];

  for (var phaseIndex = 0; phaseIndex < phasesRaw.length; phaseIndex++) {
    final phaseMap = phasesRaw[phaseIndex] as Map<String, dynamic>;
    final tasksRaw = phaseMap[_payloadTasks] as List<dynamic>;
    final tasks = <ProductionTaskDraft>[];

    for (var taskIndex = 0; taskIndex < tasksRaw.length; taskIndex++) {
      final taskMap = tasksRaw[taskIndex] as Map<String, dynamic>;
      final assignedStaff = taskMap[_payloadTaskStaff];
      final assignedStaffProfileIds = _parseDraftStringList(
        taskMap[_payloadTaskStaffProfileIds],
      );
      final resolvedAssignedStaffId = assignedStaffProfileIds.isNotEmpty
          ? assignedStaffProfileIds.first
          : assignedStaff?.toString().trim();
      final requiredHeadcount =
          _parseStrictInt(taskMap[_payloadTaskRequiredHeadcount]) ?? 1;
      final normalizedAssignedIds =
          resolvedAssignedStaffId == null ||
              resolvedAssignedStaffId.trim().isEmpty
          ? const <String>[]
          : assignedStaffProfileIds.isNotEmpty
          ? assignedStaffProfileIds
          : [resolvedAssignedStaffId];
      final normalizedRequiredHeadcount =
          requiredHeadcount < normalizedAssignedIds.length
          ? normalizedAssignedIds.length
          : (requiredHeadcount < 1 ? 1 : requiredHeadcount);
      tasks.add(
        ProductionTaskDraft(
          id: _buildTaskId(),
          title: taskMap[_payloadTaskTitle].toString().trim(),
          roleRequired: taskMap[_payloadTaskRole].toString().trim(),
          assignedStaffId: resolvedAssignedStaffId,
          assignedStaffProfileIds: normalizedAssignedIds,
          requiredHeadcount: normalizedRequiredHeadcount,
          weight: _parseStrictInt(taskMap[_payloadTaskWeight])!,
          scheduledStart: DateTime.tryParse(
            (taskMap[_payloadTaskStartDate] ?? "").toString().trim(),
          ),
          scheduledDue: DateTime.tryParse(
            (taskMap[_payloadTaskDueDate] ?? "").toString().trim(),
          ),
          manualSortOrder:
              int.tryParse(
                taskMap[_payloadTaskManualSortOrder]?.toString() ?? "",
              ) ??
              taskIndex,
          instructions: taskMap[_payloadTaskInstructions].toString().trim(),
          taskType: (taskMap[_payloadTaskType] ?? "").toString().trim(),
          sourceTemplateKey: (taskMap[_payloadTaskSourceTemplateKey] ?? "")
              .toString()
              .trim(),
          recurrenceGroupKey: (taskMap[_payloadTaskRecurrenceGroupKey] ?? "")
              .toString()
              .trim(),
          occurrenceIndex:
              int.tryParse(
                taskMap[_payloadTaskOccurrenceIndex]?.toString() ?? "",
              ) ??
              0,
          status: _defaultTaskStatus,
          completedAt: null,
          completedByStaffId: null,
        ),
      );
    }

    phases.add(
      ProductionPhaseDraft(
        name: phaseMap[_payloadPhaseName].toString().trim(),
        order: _parseStrictInt(phaseMap[_payloadPhaseOrder])!,
        estimatedDays: _parseStrictInt(phaseMap[_payloadPhaseEstimatedDays])!,
        phaseType: (phaseMap[_payloadPhaseType] ?? "finite").toString().trim(),
        requiredUnits:
            int.tryParse(
              phaseMap[_payloadPhaseRequiredUnits]?.toString() ?? "",
            ) ??
            0,
        minRatePerFarmerHour:
            double.tryParse(
              phaseMap[_payloadPhaseMinRatePerFarmerHour]?.toString() ?? "",
            ) ??
            0.1,
        targetRatePerFarmerHour:
            double.tryParse(
              phaseMap[_payloadPhaseTargetRatePerFarmerHour]?.toString() ?? "",
            ) ??
            0.2,
        plannedHoursPerDay:
            double.tryParse(
              phaseMap[_payloadPhasePlannedHoursPerDay]?.toString() ?? "",
            ) ??
            3,
        biologicalMinDays:
            int.tryParse(
              phaseMap[_payloadPhaseBiologicalMinDays]?.toString() ?? "",
            ) ??
            0,
        tasks: tasks,
      ),
    );
  }

  final riskNotes = (summaryMap[_payloadSummaryRiskNotes] as List<dynamic>)
      .map((item) => item.toString().trim())
      .toList();

  return ProductionPlanDraftState(
    title: (draft[_payloadPlanTitle] ?? draft[_payloadTitle]).toString().trim(),
    notes: draft[_payloadNotes].toString().trim(),
    domainContext: normalizeProductionDomainContext(
      domainContextRaw?.toString(),
    ),
    estateAssetId: draft[_payloadEstateId].toString().trim(),
    productId: hasDirectProduct
        ? draft[_payloadProductId].toString().trim()
        : null,
    startDate: startDateString == null
        ? null
        : _normalizeDraftCalendarDate(DateTime.parse(startDateString)),
    endDate: endDateString == null
        ? null
        : _normalizeDraftCalendarDate(DateTime.parse(endDateString)),
    plantingTargets: plantingTargetsRaw is Map<String, dynamic>
        ? ProductionPlantingTargetsDraft.fromJson(plantingTargetsRaw)
        : const ProductionPlantingTargetsDraft(
            materialType: "",
            plannedPlantingQuantity: null,
            plannedPlantingUnit: "",
            estimatedHarvestQuantity: null,
            estimatedHarvestUnit: "",
          ),
    proposedProduct: suggestedProduct,
    productAiSuggested: suggestedProduct != null,
    startDateAiSuggested:
        !_isValidIsoDate(startDateRaw?.toString() ?? _emptyText) &&
        _isValidIsoDate(proposedStartDateRaw?.toString() ?? _emptyText),
    endDateAiSuggested:
        !_isValidIsoDate(endDateRaw?.toString() ?? _emptyText) &&
        _isValidIsoDate(proposedEndDateRaw?.toString() ?? _emptyText),
    aiGenerated: true,
    phases: phases,
    totalTasks: _parseStrictInt(summaryMap[_payloadSummaryTotalTasks])!,
    totalEstimatedDays: _parseStrictInt(
      summaryMap[_payloadSummaryTotalEstimatedDays],
    )!,
    riskNotes: riskNotes,
  );
}

bool _isValidRequiredString(dynamic value) {
  if (value == null) return false;
  return value.toString().trim().isNotEmpty;
}

double? _parseNonNegativeDraftDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  final parsed = double.tryParse(value.toString().trim());
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

void _validateRequiredStringField(
  Map<String, dynamic> source,
  String field,
  List<String> missing,
  List<String> invalid, {
  required String phasePath,
}) {
  final keyPath = "$phasePath.$field";
  final value = source[field];
  if (value == null) {
    missing.add(keyPath);
    return;
  }
  if (!_isValidRequiredString(value)) {
    invalid.add(keyPath);
  }
}

void _validateRequiredIntField(
  Map<String, dynamic> source,
  String field,
  List<String> missing,
  List<String> invalid, {
  required String phasePath,
  required int minValue,
  int? maxValue,
}) {
  final keyPath = "$phasePath.$field";
  final value = source[field];
  if (value == null) {
    missing.add(keyPath);
    return;
  }
  final parsed = _parseStrictInt(value);
  if (parsed == null ||
      parsed < minValue ||
      (maxValue != null && parsed > maxValue)) {
    invalid.add(keyPath);
  }
}

int? _parseStrictInt(dynamic value) {
  if (value is int) return value;
  if (value is String && RegExp(r"^-?\d+$").hasMatch(value.trim())) {
    return int.tryParse(value.trim());
  }
  return null;
}

bool _isValidIsoDate(String value) {
  if (!RegExp(_isoDatePattern).hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  return parsed.toIso8601String().startsWith(value);
}

List<String> _parseDraftStringList(dynamic value) {
  if (value is! List<dynamic>) {
    return const <String>[];
  }
  return value
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toSet()
      .toList();
}

List<String> _parseDraftWarnings(dynamic value) {
  if (value is! List<dynamic>) {
    return const <String>[];
  }

  return value
      .map((warning) {
        if (warning is Map<String, dynamic>) {
          final message = warning[_payloadMessage];
          return message?.toString().trim() ?? "";
        }
        return warning?.toString().trim() ?? "";
      })
      .where((message) => message.isNotEmpty)
      .toList();
}

String _capacityBucketForRole(String roleRequired) {
  final role = roleRequired.trim().toLowerCase();
  switch (role) {
    case "farmer":
      return "farmer";
    case "auditor":
    case "quality_control_manager":
      return "qc_officer";
    case "maintenance_technician":
      return "machine_operator";
    case "inventory_keeper":
      return "storekeeper";
    case "field_agent":
    case "cleaner":
      return "packer";
    case "logistics_driver":
      return "logistics";
    case "farm_manager":
    case "estate_manager":
    case "asset_manager":
      return "supervisor";
    default:
      return "";
  }
}
