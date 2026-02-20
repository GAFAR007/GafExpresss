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
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';

// WHY: Centralize JSON keys to avoid inline magic strings.
const String _logTag = "PRODUCTION_MODELS";
const String _keyId = "_id";
const String _keyAltId = "id";
const String _keyBusinessId = "businessId";
const String _keyEstateAssetId = "estateAssetId";
const String _keyProductId = "productId";
const String _keyDomainContext = "domainContext";
const String _keyTitle = "title";
const String _keyStartDate = "startDate";
const String _keyEndDate = "endDate";
const String _keyStatus = "status";
const String _keyCreatedBy = "createdBy";
const String _keyApprovedBy = "approvedBy";
const String _keyApprovedAt = "approvedAt";
const String _keyNotes = "notes";
const String _keyAiGenerated = "aiGenerated";
const String _keyCreatedAt = "createdAt";
const String _keyUpdatedAt = "updatedAt";
const String _keyError = "error";
const String _keyMessage = "message";
const String _keyPage = "page";
const String _keyLimit = "limit";
const String _keyPlanId = "planId";
const String _keyTaskId = "taskId";
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
const String _keyProduct = "product";
const String _keyPreorderSummary = "preorderSummary";
const String _keyProgress = "progress";
const String _keyTimelineRows = "timelineRows";
const String _keyStaffProgressScores = "staffProgressScores";
const String _keySuccesses = "successes";
const String _keyErrors = "errors";
const String _keySummary = "summary";
const String _keyFilters = "filters";
const String _keyPagination = "pagination";
const String _keyReservations = "reservations";
const String _keyTotalEntries = "totalEntries";
const String _keySuccessCount = "successCount";
const String _keyErrorCount = "errorCount";
const String _keyScannedCount = "scannedCount";
const String _keyExpiredCount = "expiredCount";
const String _keySkippedCount = "skippedCount";
const String _keyTotal = "total";
const String _keyTotalPages = "totalPages";
const String _keyHasNext = "hasNext";
const String _keyHasPrev = "hasPrev";
const String _keyReserved = "reserved";
const String _keyConfirmed = "confirmed";
const String _keyReleased = "released";
const String _keyExpired = "expired";
const String _keyEntryIndex = "index";
const String _keyErrorCode = "errorCode";
const String _keyRoleRequired = "roleRequired";
const String _keyAssignedStaffId = "assignedStaffId";
const String _keyAssignedStaffProfileIds = "assignedStaffProfileIds";
const String _keyAssignedStaffIds = "assignedStaffIds";
const String _keyRequiredHeadcount = "requiredHeadcount";
const String _keyAssignedCount = "assignedCount";
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
const String _keyUserId = "userId";
const String _keyUser = "user";
const String _keyStaffRole = "staffRole";
const String _keyUserName = "name";
const String _keyUserEmail = "email";
const String _keyUserPhone = "phone";
const String _keyRole = "role";
const String _keyWorkDate = "workDate";
const String _keyPreorderEnabled = "preorderEnabled";
const String _keyPreorderCapQuantity = "preorderCapQuantity";
const String _keyPreorderReservedQuantity = "preorderReservedQuantity";
const String _keyPreorderRemainingQuantity = "preorderRemainingQuantity";
const String _keyEffectiveCap = "effectiveCap";
const String _keyConfidenceScore = "confidenceScore";
const String _keyApprovedProgressCoverage = "approvedProgressCoverage";
const String _keyConservativeYieldQuantity = "conservativeYieldQuantity";
const String _keyConservativeYieldUnit = "conservativeYieldUnit";
const String _keyProductionState = "productionState";
const String _keyNow = "now";
const String _keyTaskTitle = "taskTitle";
const String _keyPhaseName = "phaseName";
const String _keyFarmerName = "farmerName";
const String _keyExpectedPlots = "expectedPlots";
const String _keyActualPlots = "actualPlots";
const String _keyDelay = "delay";
const String _keyDelayReason = "delayReason";
const String _keyApprovalState = "approvalState";
const String _keyCompletionRatio = "completionRatio";
const String _keyTotalExpected = "totalExpected";
const String _keyTotalActual = "totalActual";
const String _keyExpiresAt = "expiresAt";
const String _keyExpiredAt = "expiredAt";
const String _keyPolicy = "policy";
const String _keySources = "sources";
const String _keyBusinessDefault = "businessDefault";
const String _keyEstateOverride = "estateOverride";
const String _keyWorkWeekDays = "workWeekDays";
const String _keyBlocks = "blocks";
const String _keyMinSlotMinutes = "minSlotMinutes";
const String _keyTimezone = "timezone";
const String _keyRoles = "roles";
const String _keyAvailable = "available";

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
  final String domainContext;
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
    required this.domainContext,
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
      domainContext: normalizeProductionDomainContext(
        json[_keyDomainContext]?.toString(),
      ),
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
  final List<String> assignedStaffIds;
  final int requiredHeadcount;
  final int assignedCount;
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
    required this.assignedStaffIds,
    required this.requiredHeadcount,
    required this.assignedCount,
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
    final assignedStaffId = _parseString(json[_keyAssignedStaffId]);
    final parsedAssignedStaffProfileIds = _parseStringList(
      json[_keyAssignedStaffProfileIds],
    );
    final parsedAssignedStaffIds = _parseStringList(json[_keyAssignedStaffIds]);
    final assignedStaffIds = parsedAssignedStaffProfileIds.isNotEmpty
        ? parsedAssignedStaffProfileIds
        : parsedAssignedStaffIds.isNotEmpty
        ? parsedAssignedStaffIds
        : (assignedStaffId.isNotEmpty ? [assignedStaffId] : <String>[]);

    return ProductionTask(
      id: id,
      planId: _parseString(json[_keyPlanId]),
      phaseId: _parseString(json[_keyPhaseId]),
      title: _parseString(json[_keyTitle]),
      roleRequired: _parseString(json[_keyRoleRequired]),
      assignedStaffId: assignedStaffId,
      assignedStaffIds: assignedStaffIds,
      requiredHeadcount: _parseInt(json[_keyRequiredHeadcount], fallback: 1),
      assignedCount: _parseInt(
        json[_keyAssignedCount],
        fallback: assignedStaffIds.length,
      ),
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
          .map(
            (item) => ProductionPhaseKpi.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      staffKpis: rawStaff
          .map(
            (item) => ProductionStaffKpi.fromJson(item as Map<String, dynamic>),
          )
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
  final ProductionProductLifecycle? product;
  final ProductionPreorderSummary? preorderSummary;
  final List<ProductionTimelineRow> timelineRows;
  final List<ProductionStaffProgressScore> staffProgressScores;

  const ProductionPlanDetail({
    required this.plan,
    required this.phases,
    required this.tasks,
    required this.outputs,
    required this.kpis,
    required this.product,
    required this.preorderSummary,
    required this.timelineRows,
    required this.staffProgressScores,
  });

  factory ProductionPlanDetail.fromJson(Map<String, dynamic> json) {
    final planMap = (json[_keyPlan] ?? {}) as Map<String, dynamic>;
    final phaseList = (json[_keyPhases] ?? []) as List<dynamic>;
    final taskList = (json[_keyTasks] ?? []) as List<dynamic>;
    final outputList = (json[_keyOutputs] ?? []) as List<dynamic>;
    final kpiMap = json[_keyKpis];
    final productMap = json[_keyProduct];
    final preorderSummaryMap = json[_keyPreorderSummary];
    final timelineRowsList = (json[_keyTimelineRows] ?? []) as List<dynamic>;
    final staffProgressScoresList =
        (json[_keyStaffProgressScores] ?? []) as List<dynamic>;

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
          .map(
            (item) => ProductionOutput.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      kpis: kpiMap is Map<String, dynamic>
          ? ProductionKpis.fromJson(kpiMap)
          : null,
      product: productMap is Map<String, dynamic>
          ? ProductionProductLifecycle.fromJson(productMap)
          : null,
      preorderSummary: preorderSummaryMap is Map<String, dynamic>
          ? ProductionPreorderSummary.fromJson(preorderSummaryMap)
          : null,
      timelineRows: timelineRowsList
          .map(
            (item) =>
                ProductionTimelineRow.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      staffProgressScores: staffProgressScoresList
          .map(
            (item) => ProductionStaffProgressScore.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class ProductionProductLifecycle {
  final String id;
  final String productionState;
  final bool preorderEnabled;
  final num preorderCapQuantity;
  final num preorderReservedQuantity;

  const ProductionProductLifecycle({
    required this.id,
    required this.productionState,
    required this.preorderEnabled,
    required this.preorderCapQuantity,
    required this.preorderReservedQuantity,
  });

  factory ProductionProductLifecycle.fromJson(Map<String, dynamic> json) {
    return ProductionProductLifecycle(
      id: _parseId(json),
      productionState: _parseString(json[_keyProductionState]),
      preorderEnabled: json[_keyPreorderEnabled] == true,
      preorderCapQuantity: _parseNum(json[_keyPreorderCapQuantity]),
      preorderReservedQuantity: _parseNum(json[_keyPreorderReservedQuantity]),
    );
  }
}

class ProductionPreorderSummary {
  final String productionState;
  final bool preorderEnabled;
  final num preorderCapQuantity;
  final num effectiveCap;
  final double confidenceScore;
  final double approvedProgressCoverage;
  final num preorderReservedQuantity;
  final num preorderRemainingQuantity;
  final num? conservativeYieldQuantity;
  final String conservativeYieldUnit;

  const ProductionPreorderSummary({
    required this.productionState,
    required this.preorderEnabled,
    required this.preorderCapQuantity,
    required this.effectiveCap,
    required this.confidenceScore,
    required this.approvedProgressCoverage,
    required this.preorderReservedQuantity,
    required this.preorderRemainingQuantity,
    required this.conservativeYieldQuantity,
    required this.conservativeYieldUnit,
  });

  factory ProductionPreorderSummary.fromJson(Map<String, dynamic> json) {
    return ProductionPreorderSummary(
      productionState: _parseString(json[_keyProductionState]),
      preorderEnabled: json[_keyPreorderEnabled] == true,
      preorderCapQuantity: _parseNum(json[_keyPreorderCapQuantity]),
      effectiveCap: _parseNum(
        json[_keyEffectiveCap],
        fallback: _parseNum(json[_keyPreorderCapQuantity]),
      ),
      confidenceScore: _parseDouble(json[_keyConfidenceScore], fallback: 1),
      approvedProgressCoverage: _parseDouble(
        json[_keyApprovedProgressCoverage],
      ),
      preorderReservedQuantity: _parseNum(json[_keyPreorderReservedQuantity]),
      preorderRemainingQuantity: _parseNum(json[_keyPreorderRemainingQuantity]),
      conservativeYieldQuantity: _parseNullableNum(
        json[_keyConservativeYieldQuantity],
      ),
      conservativeYieldUnit: _parseString(json[_keyConservativeYieldUnit]),
    );
  }
}

class ProductionScheduleBlock {
  final String start;
  final String end;

  const ProductionScheduleBlock({required this.start, required this.end});

  factory ProductionScheduleBlock.fromJson(Map<String, dynamic> json) {
    final start = _parseString(json["start"]);
    final end = _parseString(json["end"]);
    return ProductionScheduleBlock(start: start, end: end);
  }
}

class ProductionSchedulePolicy {
  final List<int> workWeekDays;
  final List<ProductionScheduleBlock> blocks;
  final int minSlotMinutes;
  final String timezone;

  const ProductionSchedulePolicy({
    required this.workWeekDays,
    required this.blocks,
    required this.minSlotMinutes,
    required this.timezone,
  });

  factory ProductionSchedulePolicy.fromJson(Map<String, dynamic> json) {
    final rawDays = (json[_keyWorkWeekDays] ?? []) as List<dynamic>;
    final rawBlocks = (json[_keyBlocks] ?? []) as List<dynamic>;

    return ProductionSchedulePolicy(
      workWeekDays:
          rawDays
              .map((item) => _parseInt(item))
              .where((day) => day >= 1 && day <= 7)
              .toSet()
              .toList()
            ..sort(),
      blocks: rawBlocks
          .whereType<Map<String, dynamic>>()
          .map(ProductionScheduleBlock.fromJson)
          .toList(),
      minSlotMinutes: _parseInt(json[_keyMinSlotMinutes], fallback: 30),
      timezone: _parseString(json[_keyTimezone]),
    );
  }

  String get blocksLabel {
    if (blocks.isEmpty) return "No blocks";
    return blocks.map((block) => "${block.start}-${block.end}").join(", ");
  }
}

class ProductionSchedulePolicySources {
  final ProductionSchedulePolicy? businessDefault;
  final ProductionSchedulePolicy? estateOverride;

  const ProductionSchedulePolicySources({
    required this.businessDefault,
    required this.estateOverride,
  });

  factory ProductionSchedulePolicySources.fromJson(Map<String, dynamic> json) {
    final businessDefaultMap = json[_keyBusinessDefault];
    final estateOverrideMap = json[_keyEstateOverride];
    return ProductionSchedulePolicySources(
      businessDefault: businessDefaultMap is Map<String, dynamic>
          ? ProductionSchedulePolicy.fromJson(businessDefaultMap)
          : null,
      estateOverride: estateOverrideMap is Map<String, dynamic>
          ? ProductionSchedulePolicy.fromJson(estateOverrideMap)
          : null,
    );
  }
}

class ProductionSchedulePolicyResponse {
  final String message;
  final String estateAssetId;
  final ProductionSchedulePolicy policy;
  final ProductionSchedulePolicySources? sources;

  const ProductionSchedulePolicyResponse({
    required this.message,
    required this.estateAssetId,
    required this.policy,
    required this.sources,
  });

  factory ProductionSchedulePolicyResponse.fromJson(Map<String, dynamic> json) {
    final policyMap = (json[_keyPolicy] ?? {}) as Map<String, dynamic>;
    final sourcesMap = json[_keySources];
    return ProductionSchedulePolicyResponse(
      message: _parseString(json[_keyMessage]),
      estateAssetId: _parseString(json[_keyEstateAssetId]),
      policy: ProductionSchedulePolicy.fromJson(policyMap),
      sources: sourcesMap is Map<String, dynamic>
          ? ProductionSchedulePolicySources.fromJson(sourcesMap)
          : null,
    );
  }
}

class ProductionStaffRoleCapacity {
  final int total;
  final int available;

  const ProductionStaffRoleCapacity({
    required this.total,
    required this.available,
  });

  factory ProductionStaffRoleCapacity.fromJson(Map<String, dynamic> json) {
    return ProductionStaffRoleCapacity(
      total: _parseInt(json[_keyTotal]),
      available: _parseInt(json[_keyAvailable]),
    );
  }
}

class ProductionStaffCapacitySummary {
  final String message;
  final String estateAssetId;
  final Map<String, ProductionStaffRoleCapacity> roles;

  const ProductionStaffCapacitySummary({
    required this.message,
    required this.estateAssetId,
    required this.roles,
  });

  factory ProductionStaffCapacitySummary.fromJson(Map<String, dynamic> json) {
    final rawRoles = (json[_keyRoles] ?? {}) as Map<dynamic, dynamic>;
    final parsedRoles = <String, ProductionStaffRoleCapacity>{};
    rawRoles.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsedRoles[key.toString()] = ProductionStaffRoleCapacity.fromJson(
          value,
        );
      }
    });
    return ProductionStaffCapacitySummary(
      message: _parseString(json[_keyMessage]),
      estateAssetId: _parseString(json[_keyEstateAssetId]),
      roles: parsedRoles,
    );
  }
}

class ProductionPreorderReconcileSummary {
  final DateTime? now;
  final int scannedCount;
  final int expiredCount;
  final int skippedCount;
  final int errorCount;

  const ProductionPreorderReconcileSummary({
    required this.now,
    required this.scannedCount,
    required this.expiredCount,
    required this.skippedCount,
    required this.errorCount,
  });

  factory ProductionPreorderReconcileSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionPreorderReconcileSummary(
      now: _parseDate(json[_keyNow]),
      scannedCount: _parseInt(json[_keyScannedCount]),
      expiredCount: _parseInt(json[_keyExpiredCount]),
      skippedCount: _parseInt(json[_keySkippedCount]),
      errorCount: _parseInt(json[_keyErrorCount]),
    );
  }
}

class ProductionPreorderReservationFilters {
  final String status;
  final String planId;
  final int page;
  final int limit;

  const ProductionPreorderReservationFilters({
    required this.status,
    required this.planId,
    required this.page,
    required this.limit,
  });

  factory ProductionPreorderReservationFilters.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionPreorderReservationFilters(
      status: _parseString(json[_keyStatus]),
      planId: _parseString(json[_keyPlanId]),
      page: _parseInt(json[_keyPage], fallback: 1),
      limit: _parseInt(json[_keyLimit], fallback: 20),
    );
  }
}

class ProductionPreorderReservationPagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;

  const ProductionPreorderReservationPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  factory ProductionPreorderReservationPagination.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionPreorderReservationPagination(
      page: _parseInt(json[_keyPage], fallback: 1),
      limit: _parseInt(json[_keyLimit], fallback: 20),
      total: _parseInt(json[_keyTotal]),
      totalPages: _parseInt(json[_keyTotalPages], fallback: 1),
      hasNext: json[_keyHasNext] == true,
      hasPrev: json[_keyHasPrev] == true,
    );
  }
}

class ProductionPreorderReservationSummary {
  final int total;
  final int reserved;
  final int confirmed;
  final int released;
  final int expired;

  const ProductionPreorderReservationSummary({
    required this.total,
    required this.reserved,
    required this.confirmed,
    required this.released,
    required this.expired,
  });

  factory ProductionPreorderReservationSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionPreorderReservationSummary(
      total: _parseInt(json[_keyTotal]),
      reserved: _parseInt(json[_keyReserved]),
      confirmed: _parseInt(json[_keyConfirmed]),
      released: _parseInt(json[_keyReleased]),
      expired: _parseInt(json[_keyExpired]),
    );
  }
}

class ProductionPreorderReservationPlan {
  final String id;
  final String title;
  final String productId;
  final String status;

  const ProductionPreorderReservationPlan({
    required this.id,
    required this.title,
    required this.productId,
    required this.status,
  });

  factory ProductionPreorderReservationPlan.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionPreorderReservationPlan(
      id: _parseId(json),
      title: _parseString(json[_keyTitle]),
      productId: _parseString(json[_keyProductId]),
      status: _parseString(json[_keyStatus]),
    );
  }
}

class ProductionPreorderReservationUser {
  final String id;
  final String name;
  final String email;
  final String role;

  const ProductionPreorderReservationUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory ProductionPreorderReservationUser.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionPreorderReservationUser(
      id: _parseId(json),
      name: _parseString(json[_keyName]),
      email: _parseString(json[_keyUserEmail]),
      role: _parseString(json[_keyRole]),
    );
  }
}

class ProductionPreorderReservationRecord {
  final String id;
  final String businessId;
  final String planId;
  final String userId;
  final num quantity;
  final String status;
  final DateTime? expiresAt;
  final DateTime? expiredAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final ProductionPreorderReservationPlan plan;
  final ProductionPreorderReservationUser user;

  const ProductionPreorderReservationRecord({
    required this.id,
    required this.businessId,
    required this.planId,
    required this.userId,
    required this.quantity,
    required this.status,
    required this.expiresAt,
    required this.expiredAt,
    required this.createdAt,
    required this.updatedAt,
    required this.plan,
    required this.user,
  });

  factory ProductionPreorderReservationRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawPlan = json[_keyPlanId];
    final rawUser = json[_keyUserId];
    final planMap = rawPlan is Map<String, dynamic>
        ? rawPlan
        : <String, dynamic>{_keyId: rawPlan};
    final userMap = rawUser is Map<String, dynamic>
        ? rawUser
        : <String, dynamic>{_keyId: rawUser};

    return ProductionPreorderReservationRecord(
      id: _parseId(json),
      businessId: _parseString(json[_keyBusinessId]),
      planId: _parseString(planMap[_keyId] ?? planMap[_keyAltId] ?? rawPlan),
      userId: _parseString(userMap[_keyId] ?? userMap[_keyAltId] ?? rawUser),
      quantity: _parseNum(json[_keyQuantity]),
      status: _parseString(json[_keyStatus]),
      expiresAt: _parseDate(json[_keyExpiresAt]),
      expiredAt: _parseDate(json[_keyExpiredAt]),
      createdAt: _parseDate(json[_keyCreatedAt]),
      updatedAt: _parseDate(json[_keyUpdatedAt]),
      plan: ProductionPreorderReservationPlan.fromJson(planMap),
      user: ProductionPreorderReservationUser.fromJson(userMap),
    );
  }
}

class ProductionPreorderReservationListResponse {
  final String message;
  final ProductionPreorderReservationFilters filters;
  final ProductionPreorderReservationPagination pagination;
  final ProductionPreorderReservationSummary summary;
  final List<ProductionPreorderReservationRecord> reservations;

  const ProductionPreorderReservationListResponse({
    required this.message,
    required this.filters,
    required this.pagination,
    required this.summary,
    required this.reservations,
  });

  factory ProductionPreorderReservationListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final filtersMap = (json[_keyFilters] ?? {}) as Map<String, dynamic>;
    final paginationMap = (json[_keyPagination] ?? {}) as Map<String, dynamic>;
    final summaryMap = (json[_keySummary] ?? {}) as Map<String, dynamic>;
    final reservationsList = (json[_keyReservations] ?? []) as List<dynamic>;

    return ProductionPreorderReservationListResponse(
      message: _parseString(json[_keyMessage]),
      filters: ProductionPreorderReservationFilters.fromJson(filtersMap),
      pagination: ProductionPreorderReservationPagination.fromJson(
        paginationMap,
      ),
      summary: ProductionPreorderReservationSummary.fromJson(summaryMap),
      reservations: reservationsList
          .map(
            (item) => ProductionPreorderReservationRecord.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class ProductionTimelineRow {
  final String id;
  final DateTime? workDate;
  final String taskId;
  final String planId;
  final String staffId;
  final String taskTitle;
  final String phaseName;
  final String farmerName;
  final num expectedPlots;
  final num actualPlots;
  final String status;
  final String delay;
  final String delayReason;
  final String approvalState;
  final String approvedBy;
  final DateTime? approvedAt;
  final String notes;

  const ProductionTimelineRow({
    required this.id,
    required this.workDate,
    required this.taskId,
    required this.planId,
    required this.staffId,
    required this.taskTitle,
    required this.phaseName,
    required this.farmerName,
    required this.expectedPlots,
    required this.actualPlots,
    required this.status,
    required this.delay,
    required this.delayReason,
    required this.approvalState,
    required this.approvedBy,
    required this.approvedAt,
    required this.notes,
  });

  factory ProductionTimelineRow.fromJson(Map<String, dynamic> json) {
    final approvedAt = _parseDate(json[_keyApprovedAt]);
    final parsedApprovalState = _parseString(json[_keyApprovalState]);
    final normalizedApprovalState = parsedApprovalState.trim().isNotEmpty
        ? parsedApprovalState
        : (approvedAt != null ? "approved" : "pending_approval");

    return ProductionTimelineRow(
      id: _parseId(json),
      workDate: _parseDate(json[_keyWorkDate]),
      taskId: _parseString(json[_keyTaskId]),
      planId: _parseString(json[_keyPlanId]),
      staffId: _parseString(json[_keyStaffId]),
      taskTitle: _parseString(json[_keyTaskTitle]),
      phaseName: _parseString(json[_keyPhaseName]),
      farmerName: _parseString(json[_keyFarmerName]),
      expectedPlots: _parseNum(json[_keyExpectedPlots]),
      actualPlots: _parseNum(json[_keyActualPlots]),
      status: _parseString(json[_keyStatus]),
      delay: _parseString(json[_keyDelay]),
      delayReason: _parseString(json[_keyDelayReason]),
      approvalState: normalizedApprovalState,
      approvedBy: _parseString(json[_keyApprovedBy]),
      approvedAt: approvedAt,
      notes: _parseString(json[_keyNotes]),
    );
  }
}

class ProductionStaffProgressScore {
  final String staffId;
  final String farmerName;
  final num totalExpected;
  final num totalActual;
  final double completionRatio;
  final String status;

  const ProductionStaffProgressScore({
    required this.staffId,
    required this.farmerName,
    required this.totalExpected,
    required this.totalActual,
    required this.completionRatio,
    required this.status,
  });

  factory ProductionStaffProgressScore.fromJson(Map<String, dynamic> json) {
    return ProductionStaffProgressScore(
      staffId: _parseString(json[_keyStaffId]),
      farmerName: _parseString(json[_keyFarmerName]),
      totalExpected: _parseNum(json[_keyTotalExpected]),
      totalActual: _parseNum(json[_keyTotalActual]),
      completionRatio: _parseDouble(json[_keyCompletionRatio]),
      status: _parseString(json[_keyStatus]),
    );
  }
}

class ProductionTaskProgressRecord {
  final String id;
  final String taskId;
  final String planId;
  final String staffId;
  final DateTime? workDate;
  final num expectedPlots;
  final num actualPlots;
  final String delayReason;
  final String notes;
  final String createdBy;
  final String approvedBy;
  final DateTime? approvedAt;

  const ProductionTaskProgressRecord({
    required this.id,
    required this.taskId,
    required this.planId,
    required this.staffId,
    required this.workDate,
    required this.expectedPlots,
    required this.actualPlots,
    required this.delayReason,
    required this.notes,
    required this.createdBy,
    required this.approvedBy,
    required this.approvedAt,
  });

  factory ProductionTaskProgressRecord.fromJson(Map<String, dynamic> json) {
    return ProductionTaskProgressRecord(
      id: _parseId(json),
      taskId: _parseString(json[_keyTaskId]),
      planId: _parseString(json[_keyPlanId]),
      staffId: _parseString(json[_keyStaffId]),
      workDate: _parseDate(json[_keyWorkDate]),
      expectedPlots: _parseNum(json[_keyExpectedPlots]),
      actualPlots: _parseNum(json[_keyActualPlots]),
      delayReason: _parseString(json[_keyDelayReason]),
      notes: _parseString(json[_keyNotes]),
      createdBy: _parseString(json[_keyCreatedBy]),
      approvedBy: _parseString(json[_keyApprovedBy]),
      approvedAt: _parseDate(json[_keyApprovedAt]),
    );
  }
}

class ProductionTaskProgressResponse {
  final ProductionTaskProgressRecord progress;

  const ProductionTaskProgressResponse({required this.progress});

  factory ProductionTaskProgressResponse.fromJson(Map<String, dynamic> json) {
    final progressMap = (json[_keyProgress] ?? {}) as Map<String, dynamic>;
    return ProductionTaskProgressResponse(
      progress: ProductionTaskProgressRecord.fromJson(progressMap),
    );
  }
}

class ProductionTaskProgressBatchEntryInput {
  final String taskId;
  final String staffId;
  final num actualPlots;
  final String delayReason;
  final String notes;

  const ProductionTaskProgressBatchEntryInput({
    required this.taskId,
    required this.staffId,
    required this.actualPlots,
    required this.delayReason,
    required this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      _keyTaskId: taskId,
      _keyStaffId: staffId,
      _keyActualPlots: actualPlots,
      _keyDelayReason: delayReason,
      _keyNotes: notes,
    };
  }
}

class ProductionTaskProgressBatchSuccess {
  final int index;
  final String taskId;
  final String staffId;
  final ProductionTaskProgressRecord progress;

  const ProductionTaskProgressBatchSuccess({
    required this.index,
    required this.taskId,
    required this.staffId,
    required this.progress,
  });

  factory ProductionTaskProgressBatchSuccess.fromJson(
    Map<String, dynamic> json,
  ) {
    final progressMap = (json[_keyProgress] ?? {}) as Map<String, dynamic>;
    return ProductionTaskProgressBatchSuccess(
      index: _parseInt(json[_keyEntryIndex]),
      taskId: _parseString(json[_keyTaskId]),
      staffId: _parseString(json[_keyStaffId]),
      progress: ProductionTaskProgressRecord.fromJson(progressMap),
    );
  }
}

class ProductionTaskProgressBatchError {
  final int index;
  final String taskId;
  final String staffId;
  final String errorCode;
  final String error;

  const ProductionTaskProgressBatchError({
    required this.index,
    required this.taskId,
    required this.staffId,
    required this.errorCode,
    required this.error,
  });

  factory ProductionTaskProgressBatchError.fromJson(Map<String, dynamic> json) {
    return ProductionTaskProgressBatchError(
      index: _parseInt(json[_keyEntryIndex]),
      taskId: _parseString(json[_keyTaskId]),
      staffId: _parseString(json[_keyStaffId]),
      errorCode: _parseString(json[_keyErrorCode]),
      error: _parseString(json[_keyError]),
    );
  }
}

class ProductionTaskProgressBatchSummary {
  final int totalEntries;
  final int successCount;
  final int errorCount;

  const ProductionTaskProgressBatchSummary({
    required this.totalEntries,
    required this.successCount,
    required this.errorCount,
  });

  factory ProductionTaskProgressBatchSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionTaskProgressBatchSummary(
      totalEntries: _parseInt(json[_keyTotalEntries]),
      successCount: _parseInt(json[_keySuccessCount]),
      errorCount: _parseInt(json[_keyErrorCount]),
    );
  }
}

class ProductionTaskProgressBatchResponse {
  final DateTime? workDate;
  final ProductionTaskProgressBatchSummary summary;
  final List<ProductionTaskProgressBatchSuccess> successes;
  final List<ProductionTaskProgressBatchError> errors;

  const ProductionTaskProgressBatchResponse({
    required this.workDate,
    required this.summary,
    required this.successes,
    required this.errors,
  });

  factory ProductionTaskProgressBatchResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final summaryMap = (json[_keySummary] ?? {}) as Map<String, dynamic>;
    final successesList = (json[_keySuccesses] ?? []) as List<dynamic>;
    final errorsList = (json[_keyErrors] ?? []) as List<dynamic>;
    return ProductionTaskProgressBatchResponse(
      workDate: _parseDate(json[_keyWorkDate]),
      summary: ProductionTaskProgressBatchSummary.fromJson(summaryMap),
      successes: successesList
          .map(
            (item) => ProductionTaskProgressBatchSuccess.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      errors: errorsList
          .map(
            (item) => ProductionTaskProgressBatchError.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class ProductionPlanListResponse {
  final List<ProductionPlan> plans;

  const ProductionPlanListResponse({required this.plans});

  factory ProductionPlanListResponse.fromJson(Map<String, dynamic> json) {
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

  factory BusinessStaffProfileSummary.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json);
    AppDebug.log(_logTag, _logStaffFromJson, extra: {"id": id});

    final userMap = (json[_keyUser] ?? {}) as Map<String, dynamic>;

    return BusinessStaffProfileSummary(
      id: id,
      userId: _parseNullableString(userMap[_keyId] ?? userMap[_keyAltId]) ?? "",
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
