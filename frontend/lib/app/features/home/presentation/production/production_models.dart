/// lib/app/features/home/presentation/production/production_models.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Typed models for production plans, phases, tasks, outputs, and KPIs.
///
/// WHY:
/// - Keeps API parsing consistent across production screens.
/// - Avoids raw JSON usage inside widgets.
///
/// HOW:
/// - fromJson factories parse backend payloads defensively.
/// - Shared helpers normalize ids, numbers, and dates.
/// - Logs parsing for traceability (safe fields only).
library;

import 'package:frontend/app/core/debug/app_debug.dart';

// WHY: Centralize JSON keys to avoid inline magic strings.
const String _logTag = "PRODUCTION_MODELS";
const String _keyId = "_id";
const String _keyAltId = "id";
const String _keyBusinessId = "businessId";
const String _keyEstateAssetId = "estateAssetId";
const String _keyProductId = "productId";
const String _keyTitle = "title";
const String _keyStartDate = "startDate";
const String _keyEndDate = "endDate";
const String _keyStatus = "status";
const String _keyCreatedBy = "createdBy";
const String _keyNotes = "notes";
const String _keyAiGenerated = "aiGenerated";
const String _keyCreatedAt = "createdAt";
const String _keyUpdatedAt = "updatedAt";
const String _keyPlanId = "planId";
const String _keyPhaseId = "phaseId";
const String _keyName = "name";
const String _keyOrder = "order";
const String _keyKpiTarget = "kpiTarget";
const String _keyTasks = "tasks";
const String _keyPhases = "phases";
const String _keyOutputs = "outputs";
const String _keyKpis = "kpis";
const String _keyPlan = "plan";
const String _keyPlans = "plans";
const String _keyRoleRequired = "roleRequired";
const String _keyAssignedStaffId = "assignedStaffId";
const String _keyWeight = "weight";
const String _keyDueDate = "dueDate";
const String _keyInstructions = "instructions";
const String _keyDependencies = "dependencies";
const String _keyApprovalStatus = "approvalStatus";
const String _keyRejectionReason = "rejectionReason";
const String _keyCompletedAt = "completedAt";
const String _keyUnitType = "unitType";
const String _keyQuantity = "quantity";
const String _keyReadyForSale = "readyForSale";
const String _keyPricePerUnit = "pricePerUnit";
const String _keyTotalTasks = "totalTasks";
const String _keyCompletedTasks = "completedTasks";
const String _keyCompletionRate = "completionRate";
const String _keyOnTimeRate = "onTimeRate";
const String _keyAvgDelayDays = "avgDelayDays";
const String _keyPhaseCompletion = "phaseCompletion";
const String _keyStaffKpis = "staffKpis";
const String _keyOutputByUnit = "outputByUnit";
const String _keyStaffId = "staffId";
const String _keyUser = "user";
const String _keyStaffRole = "staffRole";
const String _keyUserName = "name";
const String _keyUserEmail = "email";
const String _keyUserPhone = "phone";

// WHY: Keep model parsing logs consistent.
const String _logPlanFromJson = "ProductionPlan.fromJson()";
const String _logPhaseFromJson = "ProductionPhase.fromJson()";
const String _logTaskFromJson = "ProductionTask.fromJson()";
const String _logOutputFromJson = "ProductionOutput.fromJson()";
const String _logStaffFromJson = "BusinessStaffProfileSummary.fromJson()";

class ProductionPlan {
  final String id;
  final String businessId;
  final String estateAssetId;
  final String productId;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final String createdBy;
  final String notes;
  final bool aiGenerated;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductionPlan({
    required this.id,
    required this.businessId,
    required this.estateAssetId,
    required this.productId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdBy,
    required this.notes,
    required this.aiGenerated,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductionPlan.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json);
    AppDebug.log(_logTag, _logPlanFromJson, extra: {"id": id});

    return ProductionPlan(
      id: id,
      businessId: _parseString(json[_keyBusinessId]),
      estateAssetId: _parseString(json[_keyEstateAssetId]),
      productId: _parseString(json[_keyProductId]),
      title: _parseString(json[_keyTitle]),
      startDate: _parseDate(json[_keyStartDate]),
      endDate: _parseDate(json[_keyEndDate]),
      status: _parseString(json[_keyStatus]),
      createdBy: _parseString(json[_keyCreatedBy]),
      notes: _parseString(json[_keyNotes]),
      aiGenerated: json[_keyAiGenerated] == true,
      createdAt: _parseDate(json[_keyCreatedAt]),
      updatedAt: _parseDate(json[_keyUpdatedAt]),
    );
  }
}

class ProductionPhase {
  final String id;
  final String planId;
  final String name;
  final int order;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final dynamic kpiTarget;

  const ProductionPhase({
    required this.id,
    required this.planId,
    required this.name,
    required this.order,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.kpiTarget,
  });

  factory ProductionPhase.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json);
    AppDebug.log(_logTag, _logPhaseFromJson, extra: {"id": id});

    return ProductionPhase(
      id: id,
      planId: _parseString(json[_keyPlanId]),
      name: _parseString(json[_keyName]),
      order: _parseInt(json[_keyOrder]),
      startDate: _parseDate(json[_keyStartDate]),
      endDate: _parseDate(json[_keyEndDate]),
      status: _parseString(json[_keyStatus]),
      kpiTarget: json[_keyKpiTarget],
    );
  }
}

class ProductionTask {
  final String id;
  final String planId;
  final String phaseId;
  final String title;
  final String roleRequired;
  final String assignedStaffId;
  final int weight;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String status;
  final DateTime? completedAt;
  final String instructions;
  final List<String> dependencies;
  final String approvalStatus;
  final String rejectionReason;

  const ProductionTask({
    required this.id,
    required this.planId,
    required this.phaseId,
    required this.title,
    required this.roleRequired,
    required this.assignedStaffId,
    required this.weight,
    required this.startDate,
    required this.dueDate,
    required this.status,
    required this.completedAt,
    required this.instructions,
    required this.dependencies,
    required this.approvalStatus,
    required this.rejectionReason,
  });

  factory ProductionTask.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json);
    AppDebug.log(_logTag, _logTaskFromJson, extra: {"id": id});

    final deps = (json[_keyDependencies] ?? []) as List<dynamic>;

    return ProductionTask(
      id: id,
      planId: _parseString(json[_keyPlanId]),
      phaseId: _parseString(json[_keyPhaseId]),
      title: _parseString(json[_keyTitle]),
      roleRequired: _parseString(json[_keyRoleRequired]),
      assignedStaffId: _parseString(json[_keyAssignedStaffId]),
      weight: _parseInt(json[_keyWeight], fallback: 1),
      startDate: _parseDate(json[_keyStartDate]),
      dueDate: _parseDate(json[_keyDueDate]),
      status: _parseString(json[_keyStatus]),
      completedAt: _parseDate(json[_keyCompletedAt]),
      instructions: _parseString(json[_keyInstructions]),
      dependencies: deps.map((item) => item.toString()).toList(),
      approvalStatus: _parseString(json[_keyApprovalStatus]),
      rejectionReason: _parseString(json[_keyRejectionReason]),
    );
  }
}

class ProductionOutput {
  final String id;
  final String planId;
  final String productId;
  final String unitType;
  final num quantity;
  final bool readyForSale;
  final num? pricePerUnit;
  final DateTime? createdAt;

  const ProductionOutput({
    required this.id,
    required this.planId,
    required this.productId,
    required this.unitType,
    required this.quantity,
    required this.readyForSale,
    required this.pricePerUnit,
    required this.createdAt,
  });

  factory ProductionOutput.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json);
    AppDebug.log(_logTag, _logOutputFromJson, extra: {"id": id});

    return ProductionOutput(
      id: id,
      planId: _parseString(json[_keyPlanId]),
      productId: _parseString(json[_keyProductId]),
      unitType: _parseString(json[_keyUnitType]),
      quantity: _parseNum(json[_keyQuantity]),
      readyForSale: json[_keyReadyForSale] == true,
      pricePerUnit: _parseNullableNum(json[_keyPricePerUnit]),
      createdAt: _parseDate(json[_keyCreatedAt]),
    );
  }
}

class ProductionPhaseKpi {
  final String phaseId;
  final String name;
  final int totalTasks;
  final int completedTasks;
  final double completionRate;

  const ProductionPhaseKpi({
    required this.phaseId,
    required this.name,
    required this.totalTasks,
    required this.completedTasks,
    required this.completionRate,
  });

  factory ProductionPhaseKpi.fromJson(Map<String, dynamic> json) {
    return ProductionPhaseKpi(
      phaseId: _parseString(json[_keyPhaseId]),
      name: _parseString(json[_keyName]),
      totalTasks: _parseInt(json[_keyTotalTasks]),
      completedTasks: _parseInt(json[_keyCompletedTasks]),
      completionRate: _parseDouble(json[_keyCompletionRate]),
    );
  }
}

class ProductionStaffKpi {
  final String staffId;
  final int completedTasks;
  final double avgDelayDays;

  const ProductionStaffKpi({
    required this.staffId,
    required this.completedTasks,
    required this.avgDelayDays,
  });

  factory ProductionStaffKpi.fromJson(Map<String, dynamic> json) {
    return ProductionStaffKpi(
      staffId: _parseString(json[_keyStaffId]),
      completedTasks: _parseInt(json[_keyCompletedTasks]),
      avgDelayDays: _parseDouble(json[_keyAvgDelayDays]),
    );
  }
}

class ProductionKpis {
  final int totalTasks;
  final int completedTasks;
  final double completionRate;
  final double onTimeRate;
  final double avgDelayDays;
  final List<ProductionPhaseKpi> phaseCompletion;
  final List<ProductionStaffKpi> staffKpis;
  final Map<String, num> outputByUnit;

  const ProductionKpis({
    required this.totalTasks,
    required this.completedTasks,
    required this.completionRate,
    required this.onTimeRate,
    required this.avgDelayDays,
    required this.phaseCompletion,
    required this.staffKpis,
    required this.outputByUnit,
  });

  factory ProductionKpis.fromJson(Map<String, dynamic> json) {
    final rawPhase = (json[_keyPhaseCompletion] ?? []) as List<dynamic>;
    final rawStaff = (json[_keyStaffKpis] ?? []) as List<dynamic>;

    return ProductionKpis(
      totalTasks: _parseInt(json[_keyTotalTasks]),
      completedTasks: _parseInt(json[_keyCompletedTasks]),
      completionRate: _parseDouble(json[_keyCompletionRate]),
      onTimeRate: _parseDouble(json[_keyOnTimeRate]),
      avgDelayDays: _parseDouble(json[_keyAvgDelayDays]),
      phaseCompletion: rawPhase
          .map((item) =>
              ProductionPhaseKpi.fromJson(item as Map<String, dynamic>))
          .toList(),
      staffKpis: rawStaff
          .map((item) =>
              ProductionStaffKpi.fromJson(item as Map<String, dynamic>))
          .toList(),
      outputByUnit: _parseOutputByUnit(json[_keyOutputByUnit]),
    );
  }
}

class ProductionPlanDetail {
  final ProductionPlan plan;
  final List<ProductionPhase> phases;
  final List<ProductionTask> tasks;
  final List<ProductionOutput> outputs;
  final ProductionKpis? kpis;

  const ProductionPlanDetail({
    required this.plan,
    required this.phases,
    required this.tasks,
    required this.outputs,
    required this.kpis,
  });

  factory ProductionPlanDetail.fromJson(Map<String, dynamic> json) {
    final planMap = (json[_keyPlan] ?? {}) as Map<String, dynamic>;
    final phaseList = (json[_keyPhases] ?? []) as List<dynamic>;
    final taskList = (json[_keyTasks] ?? []) as List<dynamic>;
    final outputList = (json[_keyOutputs] ?? []) as List<dynamic>;
    final kpiMap = json[_keyKpis];

    // WHY: Create-plan responses may omit outputs/KPIs; keep them optional.
    return ProductionPlanDetail(
      plan: ProductionPlan.fromJson(planMap),
      phases: phaseList
          .map((item) => ProductionPhase.fromJson(item as Map<String, dynamic>))
          .toList(),
      tasks: taskList
          .map((item) => ProductionTask.fromJson(item as Map<String, dynamic>))
          .toList(),
      outputs: outputList
          .map((item) => ProductionOutput.fromJson(item as Map<String, dynamic>))
          .toList(),
      kpis: kpiMap is Map<String, dynamic>
          ? ProductionKpis.fromJson(kpiMap)
          : null,
    );
  }
}

class ProductionPlanListResponse {
  final List<ProductionPlan> plans;

  const ProductionPlanListResponse({
    required this.plans,
  });

  factory ProductionPlanListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final list = (json[_keyPlans] ?? []) as List<dynamic>;
    return ProductionPlanListResponse(
      plans: list
          .map((item) => ProductionPlan.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BusinessStaffProfileSummary {
  final String id;
  final String userId;
  final String staffRole;
  final String status;
  final String? estateAssetId;
  final String? userName;
  final String? userEmail;
  final String? userPhone;

  const BusinessStaffProfileSummary({
    required this.id,
    required this.userId,
    required this.staffRole,
    required this.status,
    required this.estateAssetId,
    required this.userName,
    required this.userEmail,
    required this.userPhone,
  });

  factory BusinessStaffProfileSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    final id = _parseId(json);
    AppDebug.log(
      _logTag,
      _logStaffFromJson,
      extra: {"id": id},
    );

    final userMap = (json[_keyUser] ?? {}) as Map<String, dynamic>;

    return BusinessStaffProfileSummary(
      id: id,
      userId: _parseNullableString(
            userMap[_keyId] ?? userMap[_keyAltId],
          ) ??
          "",
      staffRole: _parseString(json[_keyStaffRole]),
      status: _parseString(json[_keyStatus]),
      estateAssetId: _parseNullableString(json[_keyEstateAssetId]),
      userName: _parseNullableString(userMap[_keyUserName]),
      userEmail: _parseNullableString(userMap[_keyUserEmail]),
      userPhone: _parseNullableString(userMap[_keyUserPhone]),
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

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int _parseInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? "") ?? fallback;
}

double _parseDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? "") ?? fallback;
}

num _parseNum(dynamic value, {num fallback = 0}) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? "") ?? fallback;
}

num? _parseNullableNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString());
}

Map<String, num> _parseOutputByUnit(dynamic value) {
  // WHY: Output-by-unit is a dynamic map and may be missing from responses.
  if (value is! Map) return {};
  final output = <String, num>{};
  value.forEach((key, unitValue) {
    output[key.toString()] = _parseNum(unitValue);
  });
  return output;
}
