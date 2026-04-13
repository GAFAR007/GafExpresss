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
const String _keyNote = "note";
const String _keyPlantingTargets = "plantingTargets";
const String _keyWorkloadContext = "workloadContext";
const String _keyWorkUnitLabel = "workUnitLabel";
const String _keyWorkUnitType = "workUnitType";
const String _keyTotalWorkUnits = "totalWorkUnits";
const String _keyMinStaffPerUnit = "minStaffPerUnit";
const String _keyMaxStaffPerUnit = "maxStaffPerUnit";
const String _keyActiveStaffAvailabilityPercent =
    "activeStaffAvailabilityPercent";
const String _keyHasConfirmedWorkloadContext = "hasConfirmedWorkloadContext";
const String _keyMaterialType = "materialType";
const String _keyPlannedPlantingQuantity = "plannedPlantingQuantity";
const String _keyPlannedPlantingUnit = "plannedPlantingUnit";
const String _keyEstimatedHarvestQuantity = "estimatedHarvestQuantity";
const String _keyEstimatedHarvestUnit = "estimatedHarvestUnit";
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
const String _keyUnitId = "unitId";
const String _keyName = "name";
const String _keyOrder = "order";
const String _keyPhaseType = "phaseType";
const String _keyRequiredUnits = "requiredUnits";
const String _keyMinRatePerFarmerHour = "minRatePerFarmerHour";
const String _keyTargetRatePerFarmerHour = "targetRatePerFarmerHour";
const String _keyPlannedHoursPerDay = "plannedHoursPerDay";
const String _keyBiologicalMinDays = "biologicalMinDays";
const String _keyKpiTarget = "kpiTarget";
const String _keyTasks = "tasks";
const String _keyPhases = "phases";
const String _keyOutputs = "outputs";
const String _keyKpis = "kpis";
const String _keyPlan = "plan";
const String _keyPlans = "plans";
const String _keyLedger = "ledger";
const String _keyProduct = "product";
const String _keyPreorderSummary = "preorderSummary";
const String _keyProgress = "progress";
const String _keyTimelineRows = "timelineRows";
const String _keyTaskDayLedgers = "taskDayLedgers";
const String _keyStaffProfiles = "staffProfiles";
const String _keyStaffProgressScores = "staffProgressScores";
const String _keyPhaseUnitProgress = "phaseUnitProgress";
const String _keyUnitDivergence = "unitDivergence";
const String _keyUnitScheduleWarnings = "unitScheduleWarnings";
const String _keyDeviationGovernanceSummary = "deviationGovernanceSummary";
const String _keyDeviationAlerts = "deviationAlerts";
const String _keyAttendanceImpact = "attendanceImpact";
const String _keyAttendanceRecords = "attendanceRecords";
const String _keyDailyRollups = "dailyRollups";
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
const String _keyAssignedUnitIds = "assignedUnitIds";
const String _keyRequiredHeadcount = "requiredHeadcount";
const String _keyAssignedCount = "assignedCount";
const String _keyWeight = "weight";
const String _keyManualSortOrder = "manualSortOrder";
const String _keyTaskType = "taskType";
const String _keySourceTemplateKey = "sourceTemplateKey";
const String _keyRecurrenceGroupKey = "recurrenceGroupKey";
const String _keyOccurrenceIndex = "occurrenceIndex";
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
const String _keyStaffProfileId = "staffProfileId";
const String _keyUserId = "userId";
const String _keyUser = "user";
const String _keyStaffRole = "staffRole";
const String _keyUserName = "name";
const String _keyUserEmail = "email";
const String _keyUserPhone = "phone";
const String _keyRole = "role";
const String _keyWorkDate = "workDate";
const String _keyClockInAt = "clockInAt";
const String _keyClockOutAt = "clockOutAt";
const String _keyClockInTime = "clockInTime";
const String _keyClockOutTime = "clockOutTime";
const String _keyDurationMinutes = "durationMinutes";
const String _keyProofs = "proofs";
const String _keyProofCount = "proofCount";
const String _keyProofCountRequired = "proofCountRequired";
const String _keyProofCountUploaded = "proofCountUploaded";
const String _keyProofStatus = "proofStatus";
const String _keyProofUrl = "proofUrl";
const String _keyProofPublicId = "proofPublicId";
const String _keyProofFilename = "proofFilename";
const String _keyProofMimeType = "proofMimeType";
const String _keyProofSizeBytes = "proofSizeBytes";
const String _keyProofUploadedAt = "proofUploadedAt";
const String _keyProofUploadedBy = "proofUploadedBy";
const String _keyRequiredProofs = "requiredProofs";
const String _keyPreorderEnabled = "preorderEnabled";
const String _keyPreorderCapQuantity = "preorderCapQuantity";
const String _keyPreorderReservedQuantity = "preorderReservedQuantity";
const String _keyPreorderRemainingQuantity = "preorderRemainingQuantity";
const String _keyEffectiveCap = "effectiveCap";
const String _keyConfidenceScore = "confidenceScore";
const String _keyConfidence = "confidence";
const String _keyBaselineConfidenceScore = "baselineConfidenceScore";
const String _keyCurrentConfidenceScore = "currentConfidenceScore";
const String _keyConfidenceScoreDelta = "confidenceScoreDelta";
const String _keyBaselineBreakdown = "baselineBreakdown";
const String _keyCurrentBreakdown = "currentBreakdown";
const String _keyConfidenceLastComputedAt = "confidenceLastComputedAt";
const String _keyConfidenceLastTrigger = "confidenceLastTrigger";
const String _keyConfidenceRecomputeCount = "confidenceRecomputeCount";
const String _keyTransient = "transient";
const String _keyCapacity = "capacity";
const String _keyScheduleStability = "scheduleStability";
const String _keyHistoricalReliability = "historicalReliability";
const String _keyComplexityRisk = "complexityRisk";
const String _keyLastDraftSavedAt = "lastDraftSavedAt";
const String _keyLastDraftSavedBy = "lastDraftSavedBy";
const String _keyDraftRevisionCount = "draftRevisionCount";
const String _keyDraftAuditTrailCount = "draftAuditTrailCount";
const String _keyDraftAuditLog = "draftAuditLog";
const String _keyDraftRevisions = "draftRevisions";
const String _keyRevisionNumber = "revisionNumber";
const String _keyAction = "action";
const String _keyActor = "actor";
const String _keyActorId = "actorId";
const String _keyActorName = "actorName";
const String _keyActorEmail = "actorEmail";
const String _keyActorRole = "actorRole";
const String _keyActorStaffRole = "actorStaffRole";
const String _keySavedAt = "savedAt";
const String _keyPhaseCount = "phaseCount";
const String _keyTaskCount = "taskCount";
const String _keyPlanCount = "planCount";
const String _keyWeightedUnitCount = "weightedUnitCount";
const String _keyScope = "scope";
const String _keyStatuses = "statuses";
const String _keyApprovedProgressCoverage = "approvedProgressCoverage";
const String _keyConservativeYieldQuantity = "conservativeYieldQuantity";
const String _keyConservativeYieldUnit = "conservativeYieldUnit";
const String _keyProductionState = "productionState";
const String _keyNow = "now";
const String _keyTaskTitle = "taskTitle";
const String _keyPhaseName = "phaseName";
const String _keyFarmerName = "farmerName";
const String _keyAttendanceId = "attendanceId";
const String _keyExpectedPlots = "expectedPlots";
const String _keyActualPlots = "actualPlots";
const String _keyUnitTarget = "unitTarget";
const String _keyUnitCompleted = "unitCompleted";
const String _keyUnitRemaining = "unitRemaining";
const String _keyUnitContribution = "unitContribution";
const String _keyTaskDayLedgerId = "taskDayLedgerId";
const String _keyQuantityActivityType = "quantityActivityType";
const String _keyQuantityAmount = "quantityAmount";
const String _keyQuantityUnit = "quantityUnit";
const String _keyActivityType = "activityType";
const String _keyActivityQuantity = "activityQuantity";
const String _keyActivityTargets = "activityTargets";
const String _keyActivityCompleted = "activityCompleted";
const String _keyActivityRemaining = "activityRemaining";
const String _keyActivityUnits = "activityUnits";
const String _keyDelay = "delay";
const String _keyDelayReason = "delayReason";
const String _keyApprovalState = "approvalState";
const String _keySessionStatus = "sessionStatus";
const String _keyCompletionRatio = "completionRatio";
const String _keyCompletedUnitCount = "completedUnitCount";
const String _keyRemainingUnits = "remainingUnits";
const String _keyIsLocked = "isLocked";
const String _keyUnitLabel = "unitLabel";
const String _keyWarningId = "warningId";
const String _keyWarningType = "warningType";
const String _keySeverity = "severity";
const String _keyShiftDays = "shiftDays";
const String _keyShiftedTaskCount = "shiftedTaskCount";
const String _keyDelayedByDays = "delayedByDays";
const String _keyWarningCount = "warningCount";
const String _keyTotalExpected = "totalExpected";
const String _keyTotalActual = "totalActual";
const String _keyTotalRollupDays = "totalRollupDays";
const String _keyScheduledDays = "scheduledDays";
const String _keyRowsLogged = "rowsLogged";
const String _keyRowsWithAttendance = "rowsWithAttendance";
const String _keyRowsMissingAttendance = "rowsMissingAttendance";
const String _keyAssignedStaffSlots = "assignedStaffSlots";
const String _keyAttendedAssignedStaffSlots = "attendedAssignedStaffSlots";
const String _keyAbsentAssignedStaffSlots = "absentAssignedStaffSlots";
const String _keyTotalExpectedPlots = "totalExpectedPlots";
const String _keyTotalActualPlots = "totalActualPlots";
const String _keyTotalAttendanceMinutes = "totalAttendanceMinutes";
const String _keyAttendanceCoverageRate = "attendanceCoverageRate";
const String _keyAbsenteeImpactRate = "absenteeImpactRate";
const String _keyAttendanceLinkedProgressRate = "attendanceLinkedProgressRate";
const String _keyPlotsPerAttendedHour = "plotsPerAttendedHour";
const String _keyScheduledTaskBlocks = "scheduledTaskBlocks";
const String _keyAssignedStaffCount = "assignedStaffCount";
const String _keyAttendedStaffCount = "attendedStaffCount";
const String _keyAttendedAssignedStaffCount = "attendedAssignedStaffCount";
const String _keyAbsentAssignedStaffCount = "absentAssignedStaffCount";
const String _keyAttendanceMinutes = "attendanceMinutes";
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
const String _keyUnits = "units";
const String _keyUnitIndex = "unitIndex";
const String _keyLabel = "label";
const String _keyTotalUnits = "totalUnits";
const String _keyAlertId = "alertId";
const String _keySourceTaskId = "sourceTaskId";
const String _keySourceTaskTitle = "sourceTaskTitle";
const String _keyCumulativeDeviationDays = "cumulativeDeviationDays";
const String _keyThresholdDays = "thresholdDays";
const String _keyUnitLocked = "unitLocked";
const String _keyUnitLockedAt = "unitLockedAt";
const String _keyOpenAlerts = "openAlerts";
const String _keyVarianceAcceptedAlerts = "varianceAcceptedAlerts";
const String _keyReplannedAlerts = "replannedAlerts";
const String _keyLockedUnits = "lockedUnits";
const String _keyTotalAlerts = "totalAlerts";
const String _keyTriggeredAt = "triggeredAt";
const String _keyResolvedAt = "resolvedAt";
const String _keyResolutionNote = "resolutionNote";

// WHY: Keep model parsing logs consistent.
const String _logPlanFromJson = "ProductionPlan.fromJson()";
const String _logPhaseFromJson = "ProductionPhase.fromJson()";
const String _logTaskFromJson = "ProductionTask.fromJson()";
const String _logOutputFromJson = "ProductionOutput.fromJson()";
const String _logStaffFromJson = "BusinessStaffProfileSummary.fromJson()";
const String _logPlanUnitFromJson = "ProductionPlanUnit.fromJson()";

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
  final ProductionPlantingTargets? plantingTargets;
  final ProductionWorkloadContext? workloadContext;
  final bool aiGenerated;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastDraftSavedAt;
  final ProductionDraftActor? lastDraftSavedBy;
  final int draftRevisionCount;
  final int draftAuditTrailCount;
  final ProductionPlanConfidence? confidence;

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
    required this.plantingTargets,
    required this.workloadContext,
    required this.aiGenerated,
    required this.createdAt,
    required this.updatedAt,
    required this.lastDraftSavedAt,
    required this.lastDraftSavedBy,
    required this.draftRevisionCount,
    required this.draftAuditTrailCount,
    required this.confidence,
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
      plantingTargets: json[_keyPlantingTargets] is Map<String, dynamic>
          ? ProductionPlantingTargets.fromJson(
              json[_keyPlantingTargets] as Map<String, dynamic>,
            )
          : null,
      workloadContext: json[_keyWorkloadContext] is Map<String, dynamic>
          ? ProductionWorkloadContext.fromJson(
              json[_keyWorkloadContext] as Map<String, dynamic>,
            )
          : null,
      aiGenerated: json[_keyAiGenerated] == true,
      createdAt: _parseDate(json[_keyCreatedAt]),
      updatedAt: _parseDate(json[_keyUpdatedAt]),
      lastDraftSavedAt: _parseDate(json[_keyLastDraftSavedAt]),
      lastDraftSavedBy: json[_keyLastDraftSavedBy] is Map<String, dynamic>
          ? ProductionDraftActor.fromJson(
              json[_keyLastDraftSavedBy] as Map<String, dynamic>,
            )
          : null,
      draftRevisionCount: _parseInt(json[_keyDraftRevisionCount]),
      draftAuditTrailCount: _parseInt(json[_keyDraftAuditTrailCount]),
      confidence: json[_keyConfidence] is Map<String, dynamic>
          ? ProductionPlanConfidence.fromJson(
              json[_keyConfidence] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class ProductionWorkloadContext {
  final String workUnitLabel;
  final String workUnitType;
  final int totalWorkUnits;
  final int minStaffPerUnit;
  final int maxStaffPerUnit;
  final int activeStaffAvailabilityPercent;
  final bool hasConfirmedWorkloadContext;

  const ProductionWorkloadContext({
    required this.workUnitLabel,
    required this.workUnitType,
    required this.totalWorkUnits,
    required this.minStaffPerUnit,
    required this.maxStaffPerUnit,
    required this.activeStaffAvailabilityPercent,
    required this.hasConfirmedWorkloadContext,
  });

  factory ProductionWorkloadContext.fromJson(Map<String, dynamic> json) {
    final parsedWorkUnitLabel = _parseString(json[_keyWorkUnitLabel]);
    final parsedWorkUnitType = _parseString(json[_keyWorkUnitType]);
    return ProductionWorkloadContext(
      workUnitLabel: parsedWorkUnitLabel,
      workUnitType: parsedWorkUnitType,
      totalWorkUnits: _parseInt(json[_keyTotalWorkUnits]),
      minStaffPerUnit: _parseInt(json[_keyMinStaffPerUnit]),
      maxStaffPerUnit: _parseInt(json[_keyMaxStaffPerUnit]),
      activeStaffAvailabilityPercent: _parseInt(
        json[_keyActiveStaffAvailabilityPercent],
      ),
      hasConfirmedWorkloadContext:
          json[_keyHasConfirmedWorkloadContext] == true,
    );
  }

  String get resolvedWorkUnitLabel {
    final explicitLabel = workUnitLabel.trim();
    if (explicitLabel.isNotEmpty) {
      return explicitLabel;
    }
    final typedLabel = workUnitType.trim();
    if (typedLabel.isNotEmpty) {
      return typedLabel;
    }
    return "";
  }
}

class ProductionPlantingTargets {
  final String materialType;
  final double plannedPlantingQuantity;
  final String plannedPlantingUnit;
  final double estimatedHarvestQuantity;
  final String estimatedHarvestUnit;

  const ProductionPlantingTargets({
    required this.materialType,
    required this.plannedPlantingQuantity,
    required this.plannedPlantingUnit,
    required this.estimatedHarvestQuantity,
    required this.estimatedHarvestUnit,
  });

  bool get isConfigured {
    return materialType.trim().isNotEmpty &&
        plannedPlantingUnit.trim().isNotEmpty &&
        plannedPlantingQuantity >= 0 &&
        estimatedHarvestQuantity >= 0 &&
        estimatedHarvestUnit.trim().isNotEmpty;
  }

  factory ProductionPlantingTargets.fromJson(Map<String, dynamic> json) {
    return ProductionPlantingTargets(
      materialType: _parseString(json[_keyMaterialType]),
      plannedPlantingQuantity: _parseDouble(json[_keyPlannedPlantingQuantity]),
      plannedPlantingUnit: _parseString(json[_keyPlannedPlantingUnit]),
      estimatedHarvestQuantity: _parseDouble(
        json[_keyEstimatedHarvestQuantity],
      ),
      estimatedHarvestUnit: _parseString(json[_keyEstimatedHarvestUnit]),
    );
  }
}

class ProductionDraftActor {
  final String actorId;
  final String actorName;
  final String actorEmail;
  final String actorRole;
  final String actorStaffRole;

  const ProductionDraftActor({
    required this.actorId,
    required this.actorName,
    required this.actorEmail,
    required this.actorRole,
    required this.actorStaffRole,
  });

  String get displayLabel {
    if (actorName.trim().isNotEmpty) {
      return actorName.trim();
    }
    if (actorEmail.trim().isNotEmpty) {
      return actorEmail.trim();
    }
    return actorId.trim();
  }

  factory ProductionDraftActor.fromJson(Map<String, dynamic> json) {
    return ProductionDraftActor(
      actorId: _parseString(json[_keyActorId]),
      actorName: _parseString(json[_keyActorName]),
      actorEmail: _parseString(json[_keyActorEmail]),
      actorRole: _parseString(json[_keyActorRole]),
      actorStaffRole: _parseString(json[_keyActorStaffRole]),
    );
  }
}

class ProductionDraftAuditEntry {
  final String id;
  final String action;
  final String note;
  final int revisionNumber;
  final DateTime? createdAt;
  final ProductionDraftActor? actor;

  const ProductionDraftAuditEntry({
    required this.id,
    required this.action,
    required this.note,
    required this.revisionNumber,
    required this.createdAt,
    required this.actor,
  });

  factory ProductionDraftAuditEntry.fromJson(Map<String, dynamic> json) {
    final actorJson = json[_keyActor];
    return ProductionDraftAuditEntry(
      id: _parseId(json),
      action: _parseString(json[_keyAction]),
      note: _parseString(json[_keyNote]),
      revisionNumber: _parseInt(json[_keyRevisionNumber]),
      createdAt: _parseDate(json[_keyCreatedAt]),
      actor: actorJson is Map<String, dynamic>
          ? ProductionDraftActor.fromJson(actorJson)
          : null,
    );
  }
}

class ProductionDraftRevisionSummary {
  final String id;
  final int revisionNumber;
  final String action;
  final String note;
  final DateTime? savedAt;
  final ProductionDraftActor? actor;
  final String title;
  final String status;
  final int phaseCount;
  final int taskCount;
  final DateTime? startDate;
  final DateTime? endDate;

  const ProductionDraftRevisionSummary({
    required this.id,
    required this.revisionNumber,
    required this.action,
    required this.note,
    required this.savedAt,
    required this.actor,
    required this.title,
    required this.status,
    required this.phaseCount,
    required this.taskCount,
    required this.startDate,
    required this.endDate,
  });

  factory ProductionDraftRevisionSummary.fromJson(Map<String, dynamic> json) {
    final actorJson = json[_keyActor];
    final summaryJson = json[_keySummary];
    final summaryMap = summaryJson is Map<String, dynamic>
        ? summaryJson
        : const <String, dynamic>{};
    return ProductionDraftRevisionSummary(
      id: _parseId(json),
      revisionNumber: _parseInt(json[_keyRevisionNumber]),
      action: _parseString(json[_keyAction]),
      note: _parseString(json[_keyNote]),
      savedAt: _parseDate(json[_keySavedAt]),
      actor: actorJson is Map<String, dynamic>
          ? ProductionDraftActor.fromJson(actorJson)
          : null,
      title: _parseString(summaryMap[_keyTitle]),
      status: _parseString(summaryMap[_keyStatus]),
      phaseCount: _parseInt(summaryMap[_keyPhaseCount]),
      taskCount: _parseInt(summaryMap[_keyTaskCount]),
      startDate: _parseDate(summaryMap[_keyStartDate]),
      endDate: _parseDate(summaryMap[_keyEndDate]),
    );
  }
}

class ProductionConfidenceBreakdown {
  final double capacity;
  final double scheduleStability;
  final double historicalReliability;
  final double complexityRisk;

  const ProductionConfidenceBreakdown({
    required this.capacity,
    required this.scheduleStability,
    required this.historicalReliability,
    required this.complexityRisk,
  });

  factory ProductionConfidenceBreakdown.fromJson(Map<String, dynamic> json) {
    return ProductionConfidenceBreakdown(
      capacity: _parseDouble(json[_keyCapacity]),
      scheduleStability: _parseDouble(json[_keyScheduleStability]),
      historicalReliability: _parseDouble(json[_keyHistoricalReliability]),
      complexityRisk: _parseDouble(json[_keyComplexityRisk]),
    );
  }
}

class ProductionPlanConfidence {
  final double baselineConfidenceScore;
  final double currentConfidenceScore;
  final double confidenceScoreDelta;
  final ProductionConfidenceBreakdown baselineBreakdown;
  final ProductionConfidenceBreakdown currentBreakdown;
  final DateTime? confidenceLastComputedAt;
  final String confidenceLastTrigger;
  final int confidenceRecomputeCount;
  final bool transient;

  const ProductionPlanConfidence({
    required this.baselineConfidenceScore,
    required this.currentConfidenceScore,
    required this.confidenceScoreDelta,
    required this.baselineBreakdown,
    required this.currentBreakdown,
    required this.confidenceLastComputedAt,
    required this.confidenceLastTrigger,
    required this.confidenceRecomputeCount,
    required this.transient,
  });

  factory ProductionPlanConfidence.fromJson(Map<String, dynamic> json) {
    final fallbackBreakdown = ProductionConfidenceBreakdown(
      capacity: 0,
      scheduleStability: 0,
      historicalReliability: 0,
      complexityRisk: 0,
    );

    return ProductionPlanConfidence(
      baselineConfidenceScore: _parseDouble(json[_keyBaselineConfidenceScore]),
      currentConfidenceScore: _parseDouble(json[_keyCurrentConfidenceScore]),
      confidenceScoreDelta: _parseDouble(json[_keyConfidenceScoreDelta]),
      baselineBreakdown: json[_keyBaselineBreakdown] is Map<String, dynamic>
          ? ProductionConfidenceBreakdown.fromJson(
              json[_keyBaselineBreakdown] as Map<String, dynamic>,
            )
          : fallbackBreakdown,
      currentBreakdown: json[_keyCurrentBreakdown] is Map<String, dynamic>
          ? ProductionConfidenceBreakdown.fromJson(
              json[_keyCurrentBreakdown] as Map<String, dynamic>,
            )
          : fallbackBreakdown,
      confidenceLastComputedAt: _parseDate(json[_keyConfidenceLastComputedAt]),
      confidenceLastTrigger: _parseString(json[_keyConfidenceLastTrigger]),
      confidenceRecomputeCount: _parseInt(json[_keyConfidenceRecomputeCount]),
      transient: json[_keyTransient] == true,
    );
  }
}

class ProductionPhase {
  final String id;
  final String planId;
  final String name;
  final int order;
  final String phaseType;
  final int requiredUnits;
  final double minRatePerFarmerHour;
  final double targetRatePerFarmerHour;
  final double plannedHoursPerDay;
  final int biologicalMinDays;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final dynamic kpiTarget;

  const ProductionPhase({
    required this.id,
    required this.planId,
    required this.name,
    required this.order,
    required this.phaseType,
    required this.requiredUnits,
    required this.minRatePerFarmerHour,
    required this.targetRatePerFarmerHour,
    required this.plannedHoursPerDay,
    required this.biologicalMinDays,
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
      phaseType: _parseString(json[_keyPhaseType]),
      requiredUnits: _parseInt(json[_keyRequiredUnits]),
      minRatePerFarmerHour: _parseDouble(json[_keyMinRatePerFarmerHour]),
      targetRatePerFarmerHour: _parseDouble(json[_keyTargetRatePerFarmerHour]),
      plannedHoursPerDay: _parseDouble(json[_keyPlannedHoursPerDay]),
      biologicalMinDays: _parseInt(json[_keyBiologicalMinDays]),
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
  final List<String> assignedUnitIds;
  final int requiredHeadcount;
  final int assignedCount;
  final int weight;
  final int manualSortOrder;
  final String taskType;
  final String sourceTemplateKey;
  final String recurrenceGroupKey;
  final int occurrenceIndex;
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
    required this.assignedUnitIds,
    required this.requiredHeadcount,
    required this.assignedCount,
    required this.weight,
    required this.manualSortOrder,
    required this.taskType,
    required this.sourceTemplateKey,
    required this.recurrenceGroupKey,
    required this.occurrenceIndex,
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
    final parsedAssignedUnitIds = _parseStringList(json[_keyAssignedUnitIds]);
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
      assignedUnitIds: parsedAssignedUnitIds,
      requiredHeadcount: _parseInt(json[_keyRequiredHeadcount], fallback: 1),
      assignedCount: _parseInt(
        json[_keyAssignedCount],
        fallback: assignedStaffIds.length,
      ),
      weight: _parseInt(json[_keyWeight], fallback: 1),
      manualSortOrder: _parseInt(json[_keyManualSortOrder]),
      taskType: _parseString(json[_keyTaskType]),
      sourceTemplateKey: _parseString(json[_keySourceTemplateKey]),
      recurrenceGroupKey: _parseString(json[_keyRecurrenceGroupKey]),
      occurrenceIndex: _parseInt(json[_keyOccurrenceIndex]),
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

class ProductionAttendanceImpact {
  final int totalRollupDays;
  final int scheduledDays;
  final int rowsLogged;
  final int rowsWithAttendance;
  final int rowsMissingAttendance;
  final int assignedStaffSlots;
  final int attendedAssignedStaffSlots;
  final int absentAssignedStaffSlots;
  final num totalExpectedPlots;
  final num totalActualPlots;
  final num totalAttendanceMinutes;
  final double completionRate;
  final double attendanceCoverageRate;
  final double absenteeImpactRate;
  final double attendanceLinkedProgressRate;
  final double plotsPerAttendedHour;

  const ProductionAttendanceImpact({
    required this.totalRollupDays,
    required this.scheduledDays,
    required this.rowsLogged,
    required this.rowsWithAttendance,
    required this.rowsMissingAttendance,
    required this.assignedStaffSlots,
    required this.attendedAssignedStaffSlots,
    required this.absentAssignedStaffSlots,
    required this.totalExpectedPlots,
    required this.totalActualPlots,
    required this.totalAttendanceMinutes,
    required this.completionRate,
    required this.attendanceCoverageRate,
    required this.absenteeImpactRate,
    required this.attendanceLinkedProgressRate,
    required this.plotsPerAttendedHour,
  });

  factory ProductionAttendanceImpact.fromJson(Map<String, dynamic> json) {
    return ProductionAttendanceImpact(
      totalRollupDays: _parseInt(json[_keyTotalRollupDays]),
      scheduledDays: _parseInt(json[_keyScheduledDays]),
      rowsLogged: _parseInt(json[_keyRowsLogged]),
      rowsWithAttendance: _parseInt(json[_keyRowsWithAttendance]),
      rowsMissingAttendance: _parseInt(json[_keyRowsMissingAttendance]),
      assignedStaffSlots: _parseInt(json[_keyAssignedStaffSlots]),
      attendedAssignedStaffSlots: _parseInt(
        json[_keyAttendedAssignedStaffSlots],
      ),
      absentAssignedStaffSlots: _parseInt(json[_keyAbsentAssignedStaffSlots]),
      totalExpectedPlots: _parseNum(json[_keyTotalExpectedPlots]),
      totalActualPlots: _parseNum(json[_keyTotalActualPlots]),
      totalAttendanceMinutes: _parseNum(json[_keyTotalAttendanceMinutes]),
      completionRate: _parseDouble(json[_keyCompletionRate]),
      attendanceCoverageRate: _parseDouble(json[_keyAttendanceCoverageRate]),
      absenteeImpactRate: _parseDouble(json[_keyAbsenteeImpactRate]),
      attendanceLinkedProgressRate: _parseDouble(
        json[_keyAttendanceLinkedProgressRate],
      ),
      plotsPerAttendedHour: _parseDouble(json[_keyPlotsPerAttendedHour]),
    );
  }
}

class ProductionDailyRollup {
  final DateTime? workDate;
  final int scheduledTaskBlocks;
  final int assignedStaffCount;
  final int attendedStaffCount;
  final int attendedAssignedStaffCount;
  final int absentAssignedStaffCount;
  final double attendanceCoverageRate;
  final num expectedPlots;
  final num actualPlots;
  final double completionRate;
  final int rowsLogged;
  final int rowsWithAttendance;
  final int rowsMissingAttendance;
  final num attendanceMinutes;
  final double plotsPerAttendedHour;

  const ProductionDailyRollup({
    required this.workDate,
    required this.scheduledTaskBlocks,
    required this.assignedStaffCount,
    required this.attendedStaffCount,
    required this.attendedAssignedStaffCount,
    required this.absentAssignedStaffCount,
    required this.attendanceCoverageRate,
    required this.expectedPlots,
    required this.actualPlots,
    required this.completionRate,
    required this.rowsLogged,
    required this.rowsWithAttendance,
    required this.rowsMissingAttendance,
    required this.attendanceMinutes,
    required this.plotsPerAttendedHour,
  });

  factory ProductionDailyRollup.fromJson(Map<String, dynamic> json) {
    return ProductionDailyRollup(
      workDate: _parseDate(json[_keyWorkDate]),
      scheduledTaskBlocks: _parseInt(json[_keyScheduledTaskBlocks]),
      assignedStaffCount: _parseInt(json[_keyAssignedStaffCount]),
      attendedStaffCount: _parseInt(json[_keyAttendedStaffCount]),
      attendedAssignedStaffCount: _parseInt(
        json[_keyAttendedAssignedStaffCount],
      ),
      absentAssignedStaffCount: _parseInt(json[_keyAbsentAssignedStaffCount]),
      attendanceCoverageRate: _parseDouble(json[_keyAttendanceCoverageRate]),
      expectedPlots: _parseNum(json[_keyExpectedPlots]),
      actualPlots: _parseNum(json[_keyActualPlots]),
      completionRate: _parseDouble(json[_keyCompletionRate]),
      rowsLogged: _parseInt(json[_keyRowsLogged]),
      rowsWithAttendance: _parseInt(json[_keyRowsWithAttendance]),
      rowsMissingAttendance: _parseInt(json[_keyRowsMissingAttendance]),
      attendanceMinutes: _parseNum(json[_keyAttendanceMinutes]),
      plotsPerAttendedHour: _parseDouble(json[_keyPlotsPerAttendedHour]),
    );
  }
}

enum ProductionRollupPeriod { week, month }

class ProductionPeriodRollup {
  final String periodKey;
  final String periodKind;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int daysCovered;
  final int scheduledTaskBlocks;
  final int assignedStaffCount;
  final int attendedStaffCount;
  final int attendedAssignedStaffCount;
  final int absentAssignedStaffCount;
  final double attendanceCoverageRate;
  final num expectedPlots;
  final num actualPlots;
  final double completionRate;
  final int rowsLogged;
  final int rowsWithAttendance;
  final int rowsMissingAttendance;
  final num attendanceMinutes;
  final double plotsPerAttendedHour;

  const ProductionPeriodRollup({
    required this.periodKey,
    required this.periodKind,
    required this.periodStart,
    required this.periodEnd,
    required this.daysCovered,
    required this.scheduledTaskBlocks,
    required this.assignedStaffCount,
    required this.attendedStaffCount,
    required this.attendedAssignedStaffCount,
    required this.absentAssignedStaffCount,
    required this.attendanceCoverageRate,
    required this.expectedPlots,
    required this.actualPlots,
    required this.completionRate,
    required this.rowsLogged,
    required this.rowsWithAttendance,
    required this.rowsMissingAttendance,
    required this.attendanceMinutes,
    required this.plotsPerAttendedHour,
  });
}

List<ProductionPeriodRollup> buildProductionPeriodRollups(
  List<ProductionDailyRollup> dailyRollups,
  ProductionRollupPeriod period,
) {
  final groupedRollups = <String, _ProductionPeriodRollupAccumulator>{};

  for (final rollup in dailyRollups) {
    final sourceDate = rollup.workDate?.toLocal();
    if (sourceDate == null) {
      continue;
    }

    final periodStart = _resolveProductionPeriodStart(sourceDate, period);
    final periodEnd = _resolveProductionPeriodEnd(periodStart, period);
    final periodKey = _formatIsoDateKey(periodStart);
    final accumulator = groupedRollups.putIfAbsent(
      periodKey,
      () => _ProductionPeriodRollupAccumulator(
        periodKey: periodKey,
        periodKind: period.name,
        periodStart: periodStart,
        periodEnd: periodEnd,
      ),
    );
    accumulator.daysCovered += 1;
    accumulator.scheduledTaskBlocks += rollup.scheduledTaskBlocks;
    accumulator.assignedStaffCount += rollup.assignedStaffCount;
    accumulator.attendedStaffCount += rollup.attendedStaffCount;
    accumulator.attendedAssignedStaffCount += rollup.attendedAssignedStaffCount;
    accumulator.absentAssignedStaffCount += rollup.absentAssignedStaffCount;
    accumulator.expectedPlots += rollup.expectedPlots;
    accumulator.actualPlots += rollup.actualPlots;
    accumulator.rowsLogged += rollup.rowsLogged;
    accumulator.rowsWithAttendance += rollup.rowsWithAttendance;
    accumulator.rowsMissingAttendance += rollup.rowsMissingAttendance;
    accumulator.attendanceMinutes += rollup.attendanceMinutes;
  }

  return groupedRollups.values.map((accumulator) {
    final attendanceCoverageRate = accumulator.assignedStaffCount > 0
        ? accumulator.attendedAssignedStaffCount /
              accumulator.assignedStaffCount
        : 0.0;
    final completionRate = accumulator.expectedPlots > 0
        ? accumulator.actualPlots / accumulator.expectedPlots
        : 0.0;
    final plotsPerAttendedHour = accumulator.attendanceMinutes > 0
        ? accumulator.actualPlots / (accumulator.attendanceMinutes / 60)
        : 0.0;

    return ProductionPeriodRollup(
      periodKey: accumulator.periodKey,
      periodKind: accumulator.periodKind,
      periodStart: accumulator.periodStart,
      periodEnd: accumulator.periodEnd,
      daysCovered: accumulator.daysCovered,
      scheduledTaskBlocks: accumulator.scheduledTaskBlocks,
      assignedStaffCount: accumulator.assignedStaffCount,
      attendedStaffCount: accumulator.attendedStaffCount,
      attendedAssignedStaffCount: accumulator.attendedAssignedStaffCount,
      absentAssignedStaffCount: accumulator.absentAssignedStaffCount,
      attendanceCoverageRate: attendanceCoverageRate,
      expectedPlots: accumulator.expectedPlots,
      actualPlots: accumulator.actualPlots,
      completionRate: completionRate,
      rowsLogged: accumulator.rowsLogged,
      rowsWithAttendance: accumulator.rowsWithAttendance,
      rowsMissingAttendance: accumulator.rowsMissingAttendance,
      attendanceMinutes: accumulator.attendanceMinutes,
      plotsPerAttendedHour: plotsPerAttendedHour,
    );
  }).toList()..sort((left, right) {
    final leftStart =
        left.periodStart ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightStart =
        right.periodStart ?? DateTime.fromMillisecondsSinceEpoch(0);
    return rightStart.compareTo(leftStart);
  });
}

DateTime _resolveProductionPeriodStart(
  DateTime value,
  ProductionRollupPeriod period,
) {
  final localDay = DateTime(value.year, value.month, value.day);
  switch (period) {
    case ProductionRollupPeriod.week:
      return localDay.subtract(Duration(days: localDay.weekday - 1));
    case ProductionRollupPeriod.month:
      return DateTime(localDay.year, localDay.month, 1);
  }
}

DateTime _resolveProductionPeriodEnd(
  DateTime periodStart,
  ProductionRollupPeriod period,
) {
  switch (period) {
    case ProductionRollupPeriod.week:
      return periodStart.add(const Duration(days: 6));
    case ProductionRollupPeriod.month:
      return DateTime(periodStart.year, periodStart.month + 1, 0);
  }
}

String _formatIsoDateKey(DateTime value) {
  final year = value.year.toString().padLeft(4, "0");
  final month = value.month.toString().padLeft(2, "0");
  final day = value.day.toString().padLeft(2, "0");
  return "$year-$month-$day";
}

class _ProductionPeriodRollupAccumulator {
  final String periodKey;
  final String periodKind;
  final DateTime periodStart;
  final DateTime periodEnd;
  int daysCovered = 0;
  int scheduledTaskBlocks = 0;
  int assignedStaffCount = 0;
  int attendedStaffCount = 0;
  int attendedAssignedStaffCount = 0;
  int absentAssignedStaffCount = 0;
  num expectedPlots = 0;
  num actualPlots = 0;
  int rowsLogged = 0;
  int rowsWithAttendance = 0;
  int rowsMissingAttendance = 0;
  num attendanceMinutes = 0;

  _ProductionPeriodRollupAccumulator({
    required this.periodKey,
    required this.periodKind,
    required this.periodStart,
    required this.periodEnd,
  });
}

class ProductionPhaseUnitProgress {
  final String phaseId;
  final String phaseName;
  final String phaseType;
  final int requiredUnits;
  final int completedUnitCount;
  final int remainingUnits;
  final bool isLocked;

  const ProductionPhaseUnitProgress({
    required this.phaseId,
    required this.phaseName,
    required this.phaseType,
    required this.requiredUnits,
    required this.completedUnitCount,
    required this.remainingUnits,
    required this.isLocked,
  });

  factory ProductionPhaseUnitProgress.fromJson(Map<String, dynamic> json) {
    return ProductionPhaseUnitProgress(
      phaseId: _parseString(json[_keyPhaseId]),
      phaseName: _parseString(json[_keyPhaseName]),
      phaseType: _parseString(json[_keyPhaseType]),
      requiredUnits: _parseInt(json[_keyRequiredUnits]),
      completedUnitCount: _parseInt(json[_keyCompletedUnitCount]),
      remainingUnits: _parseInt(json[_keyRemainingUnits]),
      isLocked: json[_keyIsLocked] == true,
    );
  }
}

class ProductionUnitDivergence {
  final String unitId;
  final int unitIndex;
  final String unitLabel;
  final int delayedByDays;
  final int shiftedTaskCount;
  final int warningCount;
  final DateTime? updatedAt;

  const ProductionUnitDivergence({
    required this.unitId,
    required this.unitIndex,
    required this.unitLabel,
    required this.delayedByDays,
    required this.shiftedTaskCount,
    required this.warningCount,
    required this.updatedAt,
  });

  factory ProductionUnitDivergence.fromJson(Map<String, dynamic> json) {
    return ProductionUnitDivergence(
      unitId: _parseString(json[_keyUnitId]),
      unitIndex: _parseInt(json[_keyUnitIndex]),
      unitLabel: _parseString(json[_keyUnitLabel]),
      delayedByDays: _parseInt(json[_keyDelayedByDays]),
      shiftedTaskCount: _parseInt(json[_keyShiftedTaskCount]),
      warningCount: _parseInt(json[_keyWarningCount]),
      updatedAt: _parseDate(json[_keyUpdatedAt]),
    );
  }
}

class ProductionUnitScheduleWarning {
  final String warningId;
  final String unitId;
  final String unitLabel;
  final String taskId;
  final String taskTitle;
  final String warningType;
  final String severity;
  final String message;
  final int shiftDays;
  final DateTime? createdAt;

  const ProductionUnitScheduleWarning({
    required this.warningId,
    required this.unitId,
    required this.unitLabel,
    required this.taskId,
    required this.taskTitle,
    required this.warningType,
    required this.severity,
    required this.message,
    required this.shiftDays,
    required this.createdAt,
  });

  factory ProductionUnitScheduleWarning.fromJson(Map<String, dynamic> json) {
    return ProductionUnitScheduleWarning(
      warningId: _parseString(json[_keyWarningId]),
      unitId: _parseString(json[_keyUnitId]),
      unitLabel: _parseString(json[_keyUnitLabel]),
      taskId: _parseString(json[_keyTaskId]),
      taskTitle: _parseString(json[_keyTaskTitle]),
      warningType: _parseString(json[_keyWarningType]),
      severity: _parseString(json[_keySeverity]),
      message: _parseString(json[_keyMessage]),
      shiftDays: _parseInt(json[_keyShiftDays]),
      createdAt: _parseDate(json[_keyCreatedAt]),
    );
  }
}

class ProductionDeviationGovernanceSummary {
  final int totalAlerts;
  final int openAlerts;
  final int varianceAcceptedAlerts;
  final int replannedAlerts;
  final int lockedUnits;
  final DateTime? updatedAt;

  const ProductionDeviationGovernanceSummary({
    required this.totalAlerts,
    required this.openAlerts,
    required this.varianceAcceptedAlerts,
    required this.replannedAlerts,
    required this.lockedUnits,
    required this.updatedAt,
  });

  factory ProductionDeviationGovernanceSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionDeviationGovernanceSummary(
      totalAlerts: _parseInt(json[_keyTotalAlerts]),
      openAlerts: _parseInt(json[_keyOpenAlerts]),
      varianceAcceptedAlerts: _parseInt(json[_keyVarianceAcceptedAlerts]),
      replannedAlerts: _parseInt(json[_keyReplannedAlerts]),
      lockedUnits: _parseInt(json[_keyLockedUnits]),
      updatedAt: _parseDate(json[_keyUpdatedAt]),
    );
  }
}

class ProductionDeviationAlert {
  final String alertId;
  final String planId;
  final String unitId;
  final int unitIndex;
  final String unitLabel;
  final String sourceTaskId;
  final String sourceTaskTitle;
  final int cumulativeDeviationDays;
  final int thresholdDays;
  final String status;
  final String message;
  final DateTime? triggeredAt;
  final DateTime? resolvedAt;
  final String resolutionNote;
  final bool unitLocked;
  final DateTime? unitLockedAt;

  const ProductionDeviationAlert({
    required this.alertId,
    required this.planId,
    required this.unitId,
    required this.unitIndex,
    required this.unitLabel,
    required this.sourceTaskId,
    required this.sourceTaskTitle,
    required this.cumulativeDeviationDays,
    required this.thresholdDays,
    required this.status,
    required this.message,
    required this.triggeredAt,
    required this.resolvedAt,
    required this.resolutionNote,
    required this.unitLocked,
    required this.unitLockedAt,
  });

  factory ProductionDeviationAlert.fromJson(Map<String, dynamic> json) {
    return ProductionDeviationAlert(
      alertId: _parseString(json[_keyAlertId]),
      planId: _parseString(json[_keyPlanId]),
      unitId: _parseString(json[_keyUnitId]),
      unitIndex: _parseInt(json[_keyUnitIndex]),
      unitLabel: _parseString(json[_keyUnitLabel]),
      sourceTaskId: _parseString(json[_keySourceTaskId]),
      sourceTaskTitle: _parseString(json[_keySourceTaskTitle]),
      cumulativeDeviationDays: _parseInt(json[_keyCumulativeDeviationDays]),
      thresholdDays: _parseInt(json[_keyThresholdDays]),
      status: _parseString(json[_keyStatus]),
      message: _parseString(json[_keyMessage]),
      triggeredAt: _parseDate(json[_keyTriggeredAt]),
      resolvedAt: _parseDate(json[_keyResolvedAt]),
      resolutionNote: _parseString(json[_keyResolutionNote]),
      unitLocked: json[_keyUnitLocked] == true,
      unitLockedAt: _parseDate(json[_keyUnitLockedAt]),
    );
  }
}

class ProductionAttendanceRecord {
  final String id;
  final String planId;
  final String taskId;
  final String staffProfileId;
  final DateTime? workDate;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final int durationMinutes;
  final String notes;
  final DateTime? createdAt;
  final String? proofUrl;
  final String? proofPublicId;
  final String? proofFilename;
  final String? proofMimeType;
  final int? proofSizeBytes;
  final DateTime? proofUploadedAt;
  final String? proofUploadedBy;
  final List<ProductionTaskProgressProofRecord> proofs;
  final int requiredProofs;
  final String proofStatus;
  final String sessionStatus;

  const ProductionAttendanceRecord({
    required this.id,
    required this.planId,
    required this.taskId,
    required this.staffProfileId,
    required this.workDate,
    required this.clockInAt,
    required this.clockOutAt,
    required this.durationMinutes,
    required this.notes,
    required this.createdAt,
    required this.proofUrl,
    required this.proofPublicId,
    required this.proofFilename,
    required this.proofMimeType,
    required this.proofSizeBytes,
    required this.proofUploadedAt,
    required this.proofUploadedBy,
    this.proofs = const <ProductionTaskProgressProofRecord>[],
    this.requiredProofs = 0,
    this.proofStatus = "",
    this.sessionStatus = "",
  });

  factory ProductionAttendanceRecord.fromJson(Map<String, dynamic> json) {
    final proofList = json[_keyProofs];
    final proofs = proofList is List
        ? proofList
              .whereType<Map<String, dynamic>>()
              .map(ProductionTaskProgressProofRecord.fromJson)
              .toList()
        : const <ProductionTaskProgressProofRecord>[];
    return ProductionAttendanceRecord(
      id: _parseId(json),
      planId: _parseString(json[_keyPlanId]),
      taskId: _parseString(json[_keyTaskId]),
      staffProfileId: _parseString(json[_keyStaffProfileId]),
      workDate: _parseDate(json[_keyWorkDate]),
      clockInAt: _parseDate(json[_keyClockInAt]),
      clockOutAt: _parseDate(json[_keyClockOutAt]),
      durationMinutes: _parseInt(json[_keyDurationMinutes]),
      notes: _parseString(json[_keyNotes]),
      createdAt: _parseDate(json[_keyCreatedAt]),
      proofUrl: _parseNullableString(json[_keyProofUrl]),
      proofPublicId: _parseNullableString(json[_keyProofPublicId]),
      proofFilename: _parseNullableString(json[_keyProofFilename]),
      proofMimeType: _parseNullableString(json[_keyProofMimeType]),
      proofSizeBytes: _parseNullableNum(json[_keyProofSizeBytes])?.toInt(),
      proofUploadedAt: _parseDate(json[_keyProofUploadedAt]),
      proofUploadedBy: _parseNullableString(json[_keyProofUploadedBy]),
      proofs: proofs,
      requiredProofs: _parseInt(json[_keyRequiredProofs]),
      proofStatus: _parseString(json[_keyProofStatus]),
      sessionStatus: _parseString(json[_keySessionStatus]),
    );
  }

  List<ProductionTaskProgressProofRecord> get effectiveProofs {
    if (proofs.isNotEmpty) {
      return proofs.where((proof) => proof.hasUrl).toList();
    }
    final hasLegacyProof =
        proofUrl?.trim().isNotEmpty == true &&
        proofFilename?.trim().isNotEmpty == true;
    if (!hasLegacyProof) {
      return const <ProductionTaskProgressProofRecord>[];
    }
    return <ProductionTaskProgressProofRecord>[
      ProductionTaskProgressProofRecord(
        url: proofUrl!.trim(),
        publicId: proofPublicId?.trim() ?? "",
        filename: proofFilename!.trim(),
        mimeType: proofMimeType?.trim() ?? "",
        sizeBytes: proofSizeBytes ?? 0,
        uploadedAt: proofUploadedAt,
        uploadedBy: proofUploadedBy ?? "",
      ),
    ];
  }

  int get proofCountUploaded => effectiveProofs.length;

  int get effectiveRequiredProofs {
    if (requiredProofs > 0) {
      return requiredProofs;
    }
    return clockOutAt == null ? 0 : 1;
  }

  String get resolvedProofStatus {
    final normalized = proofStatus.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    if (effectiveRequiredProofs <= 0) {
      return "not_required";
    }
    return proofCountUploaded >= effectiveRequiredProofs
        ? "complete"
        : "missing";
  }

  String get resolvedSessionStatus {
    final normalized = sessionStatus.trim().toLowerCase();
    if (normalized.isNotEmpty && normalized != "active") {
      return normalized;
    }
    if (clockOutAt == null) {
      return "open";
    }
    return needsProof ? "pending_proof" : "completed";
  }

  bool get isOpen => resolvedSessionStatus == "open";

  bool get isPendingProof => resolvedSessionStatus == "pending_proof";

  bool get needsProof =>
      effectiveRequiredProofs > 0 &&
      proofCountUploaded < effectiveRequiredProofs;
}

class ProductionTaskProgressProofInput {
  final List<int> bytes;
  final String filename;
  final int sizeBytes;

  const ProductionTaskProgressProofInput({
    required this.bytes,
    required this.filename,
    required this.sizeBytes,
  });

  bool get isImage {
    final normalized = filename.trim().toLowerCase();
    return normalized.endsWith(".png") ||
        normalized.endsWith(".jpg") ||
        normalized.endsWith(".jpeg") ||
        normalized.endsWith(".webp");
  }

  String get displayLabel {
    final label = filename.trim();
    if (label.isNotEmpty) {
      return label;
    }
    return "Proof image";
  }
}

class ProductionTaskDayActivityTargets {
  final num? planted;
  final num? transplanted;
  final num? harvested;

  const ProductionTaskDayActivityTargets({
    required this.planted,
    required this.transplanted,
    required this.harvested,
  });

  factory ProductionTaskDayActivityTargets.fromJson(Map<String, dynamic> json) {
    return ProductionTaskDayActivityTargets(
      planted: _parseNullableNum(json["planted"]),
      transplanted: _parseNullableNum(json["transplanted"]),
      harvested: _parseNullableNum(json["harvested"]),
    );
  }

  num? valueFor(String activityType) {
    switch (activityType.trim().toLowerCase()) {
      case "planted":
        return planted;
      case "transplanted":
        return transplanted;
      case "harvested":
        return harvested;
      default:
        return null;
    }
  }
}

class ProductionTaskDayActivityTotals {
  final num planted;
  final num transplanted;
  final num harvested;

  const ProductionTaskDayActivityTotals({
    required this.planted,
    required this.transplanted,
    required this.harvested,
  });

  factory ProductionTaskDayActivityTotals.fromJson(Map<String, dynamic> json) {
    return ProductionTaskDayActivityTotals(
      planted: _parseNum(json["planted"]),
      transplanted: _parseNum(json["transplanted"]),
      harvested: _parseNum(json["harvested"]),
    );
  }

  num valueFor(String activityType) {
    switch (activityType.trim().toLowerCase()) {
      case "planted":
        return planted;
      case "transplanted":
        return transplanted;
      case "harvested":
        return harvested;
      default:
        return 0;
    }
  }
}

class ProductionTaskDayActivityUnits {
  final String planted;
  final String transplanted;
  final String harvested;

  const ProductionTaskDayActivityUnits({
    required this.planted,
    required this.transplanted,
    required this.harvested,
  });

  factory ProductionTaskDayActivityUnits.fromJson(Map<String, dynamic> json) {
    return ProductionTaskDayActivityUnits(
      planted: _parseString(json["planted"]),
      transplanted: _parseString(json["transplanted"]),
      harvested: _parseString(json["harvested"]),
    );
  }

  String valueFor(String activityType) {
    switch (activityType.trim().toLowerCase()) {
      case "planted":
        return planted;
      case "transplanted":
        return transplanted;
      case "harvested":
        return harvested;
      default:
        return "";
    }
  }
}

class ProductionTaskDayLedger {
  final String id;
  final String planId;
  final String taskId;
  final DateTime? workDate;
  final String unitType;
  final num unitTarget;
  final num unitCompleted;
  final num unitRemaining;
  final String status;
  final ProductionTaskDayActivityTargets activityTargets;
  final ProductionTaskDayActivityTotals activityCompleted;
  final ProductionTaskDayActivityTargets activityRemaining;
  final ProductionTaskDayActivityUnits activityUnits;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductionTaskDayLedger({
    required this.id,
    required this.planId,
    required this.taskId,
    required this.workDate,
    required this.unitType,
    required this.unitTarget,
    required this.unitCompleted,
    required this.unitRemaining,
    required this.status,
    required this.activityTargets,
    required this.activityCompleted,
    required this.activityRemaining,
    required this.activityUnits,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductionTaskDayLedger.fromJson(Map<String, dynamic> json) {
    final targetsMap =
        (json[_keyActivityTargets] ?? const <String, dynamic>{})
            as Map<String, dynamic>;
    final completedMap =
        (json[_keyActivityCompleted] ?? const <String, dynamic>{})
            as Map<String, dynamic>;
    final remainingMap =
        (json[_keyActivityRemaining] ?? const <String, dynamic>{})
            as Map<String, dynamic>;
    final unitsMap =
        (json[_keyActivityUnits] ?? const <String, dynamic>{})
            as Map<String, dynamic>;
    return ProductionTaskDayLedger(
      id: _parseId(json),
      planId: _parseString(json[_keyPlanId]),
      taskId: _parseString(json[_keyTaskId]),
      workDate: _parseDate(json[_keyWorkDate]),
      unitType: _parseString(json[_keyUnitType]),
      unitTarget: _parseNum(json[_keyUnitTarget]),
      unitCompleted: _parseNum(json[_keyUnitCompleted]),
      unitRemaining: _parseNum(json[_keyUnitRemaining]),
      status: _parseString(json[_keyStatus]),
      activityTargets: ProductionTaskDayActivityTargets.fromJson(targetsMap),
      activityCompleted: ProductionTaskDayActivityTotals.fromJson(completedMap),
      activityRemaining: ProductionTaskDayActivityTargets.fromJson(
        remainingMap,
      ),
      activityUnits: ProductionTaskDayActivityUnits.fromJson(unitsMap),
      createdAt: _parseDate(json[_keyCreatedAt]),
      updatedAt: _parseDate(json[_keyUpdatedAt]),
    );
  }
}

class ProductionPlanDetail {
  final ProductionPlan plan;
  final ProductionPlanConfidence? confidence;
  final List<ProductionPhase> phases;
  final List<ProductionTask> tasks;
  final List<ProductionOutput> outputs;
  final ProductionKpis? kpis;
  final ProductionAttendanceImpact? attendanceImpact;
  final List<ProductionAttendanceRecord> attendanceRecords;
  final List<ProductionDailyRollup> dailyRollups;
  final List<ProductionPeriodRollup> weeklyRollups;
  final List<ProductionPeriodRollup> monthlyRollups;
  final ProductionProductLifecycle? product;
  final ProductionPreorderSummary? preorderSummary;
  final List<ProductionTimelineRow> timelineRows;
  final List<ProductionTaskDayLedger> taskDayLedgers;
  final List<BusinessStaffProfileSummary> staffProfiles;
  final List<ProductionStaffProgressScore> staffProgressScores;
  final List<ProductionDraftAuditEntry> draftAuditLog;
  final List<ProductionDraftRevisionSummary> draftRevisions;
  final List<ProductionPhaseUnitProgress> phaseUnitProgress;
  final List<ProductionUnitDivergence> unitDivergence;
  final List<ProductionUnitScheduleWarning> unitScheduleWarnings;
  final ProductionDeviationGovernanceSummary? deviationGovernanceSummary;
  final List<ProductionDeviationAlert> deviationAlerts;

  const ProductionPlanDetail({
    required this.plan,
    required this.confidence,
    required this.phases,
    required this.tasks,
    required this.outputs,
    required this.kpis,
    required this.attendanceImpact,
    required this.attendanceRecords,
    required this.dailyRollups,
    required this.weeklyRollups,
    required this.monthlyRollups,
    required this.product,
    required this.preorderSummary,
    required this.timelineRows,
    required this.taskDayLedgers,
    required this.staffProfiles,
    required this.staffProgressScores,
    required this.draftAuditLog,
    required this.draftRevisions,
    required this.phaseUnitProgress,
    required this.unitDivergence,
    required this.unitScheduleWarnings,
    required this.deviationGovernanceSummary,
    required this.deviationAlerts,
  });

  factory ProductionPlanDetail.fromJson(Map<String, dynamic> json) {
    final planMap = (json[_keyPlan] ?? {}) as Map<String, dynamic>;
    final phaseList = (json[_keyPhases] ?? []) as List<dynamic>;
    final taskList = (json[_keyTasks] ?? []) as List<dynamic>;
    final outputList = (json[_keyOutputs] ?? []) as List<dynamic>;
    final kpiMap = json[_keyKpis];
    final attendanceImpactMap = json[_keyAttendanceImpact];
    final attendanceRecordsList =
        (json[_keyAttendanceRecords] ?? []) as List<dynamic>;
    final dailyRollupsList = (json[_keyDailyRollups] ?? []) as List<dynamic>;
    final productMap = json[_keyProduct];
    final preorderSummaryMap = json[_keyPreorderSummary];
    final timelineRowsList = (json[_keyTimelineRows] ?? []) as List<dynamic>;
    final taskDayLedgersList =
        (json[_keyTaskDayLedgers] ?? []) as List<dynamic>;
    final staffProfilesList = (json[_keyStaffProfiles] ?? []) as List<dynamic>;
    final staffProgressScoresList =
        (json[_keyStaffProgressScores] ?? []) as List<dynamic>;
    final dailyRollups = dailyRollupsList
        .map(
          (item) =>
              ProductionDailyRollup.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    final draftAuditLogList = (json[_keyDraftAuditLog] ?? []) as List<dynamic>;
    final draftRevisionsList =
        (json[_keyDraftRevisions] ?? []) as List<dynamic>;
    final phaseUnitProgressList =
        (json[_keyPhaseUnitProgress] ?? []) as List<dynamic>;
    final unitDivergenceList =
        (json[_keyUnitDivergence] ?? []) as List<dynamic>;
    final unitScheduleWarningsList =
        (json[_keyUnitScheduleWarnings] ?? []) as List<dynamic>;
    final deviationGovernanceSummaryMap = json[_keyDeviationGovernanceSummary];
    final deviationAlertsList =
        (json[_keyDeviationAlerts] ?? []) as List<dynamic>;
    final confidenceMap = json[_keyConfidence];

    // WHY: Create-plan responses may omit outputs/KPIs; keep them optional.
    return ProductionPlanDetail(
      plan: ProductionPlan.fromJson(planMap),
      confidence: confidenceMap is Map<String, dynamic>
          ? ProductionPlanConfidence.fromJson(confidenceMap)
          : null,
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
      attendanceImpact: attendanceImpactMap is Map<String, dynamic>
          ? ProductionAttendanceImpact.fromJson(attendanceImpactMap)
          : null,
      attendanceRecords: attendanceRecordsList
          .whereType<Map<String, dynamic>>()
          .map(ProductionAttendanceRecord.fromJson)
          .toList(),
      dailyRollups: dailyRollups,
      weeklyRollups: buildProductionPeriodRollups(
        dailyRollups,
        ProductionRollupPeriod.week,
      ),
      monthlyRollups: buildProductionPeriodRollups(
        dailyRollups,
        ProductionRollupPeriod.month,
      ),
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
      taskDayLedgers: taskDayLedgersList
          .whereType<Map<String, dynamic>>()
          .map(ProductionTaskDayLedger.fromJson)
          .toList(),
      staffProfiles: staffProfilesList
          .whereType<Map<String, dynamic>>()
          .map(BusinessStaffProfileSummary.fromJson)
          .toList(),
      staffProgressScores: staffProgressScoresList
          .map(
            (item) => ProductionStaffProgressScore.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      draftAuditLog: draftAuditLogList
          .whereType<Map<String, dynamic>>()
          .map(ProductionDraftAuditEntry.fromJson)
          .toList(),
      draftRevisions: draftRevisionsList
          .whereType<Map<String, dynamic>>()
          .map(ProductionDraftRevisionSummary.fromJson)
          .toList(),
      phaseUnitProgress: phaseUnitProgressList
          .whereType<Map<String, dynamic>>()
          .map(ProductionPhaseUnitProgress.fromJson)
          .toList(),
      unitDivergence: unitDivergenceList
          .whereType<Map<String, dynamic>>()
          .map(ProductionUnitDivergence.fromJson)
          .toList(),
      unitScheduleWarnings: unitScheduleWarningsList
          .whereType<Map<String, dynamic>>()
          .map(ProductionUnitScheduleWarning.fromJson)
          .toList(),
      deviationGovernanceSummary:
          deviationGovernanceSummaryMap is Map<String, dynamic>
          ? ProductionDeviationGovernanceSummary.fromJson(
              deviationGovernanceSummaryMap,
            )
          : null,
      deviationAlerts: deviationAlertsList
          .whereType<Map<String, dynamic>>()
          .map(ProductionDeviationAlert.fromJson)
          .toList(),
    );
  }
}

class ProductionPlanUnit {
  final String id;
  final String planId;
  final int unitIndex;
  final String label;
  final DateTime? createdAt;

  const ProductionPlanUnit({
    required this.id,
    required this.planId,
    required this.unitIndex,
    required this.label,
    required this.createdAt,
  });

  factory ProductionPlanUnit.fromJson(Map<String, dynamic> json) {
    final id = _parseId(json);
    AppDebug.log(_logTag, _logPlanUnitFromJson, extra: {"id": id});

    return ProductionPlanUnit(
      id: id,
      planId: _parseString(json[_keyPlanId]),
      unitIndex: _parseInt(json[_keyUnitIndex], fallback: 1),
      label: _parseString(json[_keyLabel]),
      createdAt: _parseDate(json[_keyCreatedAt]),
    );
  }
}

class ProductionPlanUnitsResponse {
  final String message;
  final String planId;
  final int totalUnits;
  final List<ProductionPlanUnit> units;

  const ProductionPlanUnitsResponse({
    required this.message,
    required this.planId,
    required this.totalUnits,
    required this.units,
  });

  factory ProductionPlanUnitsResponse.fromJson(Map<String, dynamic> json) {
    final unitsList = (json[_keyUnits] ?? []) as List<dynamic>;
    final parsedUnits = unitsList
        .whereType<Map<String, dynamic>>()
        .map(ProductionPlanUnit.fromJson)
        .toList();

    return ProductionPlanUnitsResponse(
      message: _parseString(json[_keyMessage]),
      planId: _parseString(json[_keyPlanId]),
      totalUnits: _parseInt(json[_keyTotalUnits], fallback: parsedUnits.length),
      units: parsedUnits,
    );
  }
}

class ProductionPortfolioConfidenceSummary {
  final int planCount;
  final int weightedUnitCount;
  final double baselineConfidenceScore;
  final double currentConfidenceScore;
  final double confidenceScoreDelta;
  final ProductionConfidenceBreakdown baselineBreakdown;
  final ProductionConfidenceBreakdown currentBreakdown;

  const ProductionPortfolioConfidenceSummary({
    required this.planCount,
    required this.weightedUnitCount,
    required this.baselineConfidenceScore,
    required this.currentConfidenceScore,
    required this.confidenceScoreDelta,
    required this.baselineBreakdown,
    required this.currentBreakdown,
  });

  factory ProductionPortfolioConfidenceSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionPortfolioConfidenceSummary(
      planCount: _parseInt(json[_keyPlanCount]),
      weightedUnitCount: _parseInt(json[_keyWeightedUnitCount]),
      baselineConfidenceScore: _parseDouble(json[_keyBaselineConfidenceScore]),
      currentConfidenceScore: _parseDouble(json[_keyCurrentConfidenceScore]),
      confidenceScoreDelta: _parseDouble(json[_keyConfidenceScoreDelta]),
      baselineBreakdown: json[_keyBaselineBreakdown] is Map<String, dynamic>
          ? ProductionConfidenceBreakdown.fromJson(
              json[_keyBaselineBreakdown] as Map<String, dynamic>,
            )
          : const ProductionConfidenceBreakdown(
              capacity: 0,
              scheduleStability: 0,
              historicalReliability: 0,
              complexityRisk: 0,
            ),
      currentBreakdown: json[_keyCurrentBreakdown] is Map<String, dynamic>
          ? ProductionConfidenceBreakdown.fromJson(
              json[_keyCurrentBreakdown] as Map<String, dynamic>,
            )
          : const ProductionConfidenceBreakdown(
              capacity: 0,
              scheduleStability: 0,
              historicalReliability: 0,
              complexityRisk: 0,
            ),
    );
  }
}

class ProductionPortfolioConfidenceResponse {
  final String message;
  final ProductionPortfolioConfidenceSummary summary;
  final String estateAssetId;
  final List<String> statuses;

  const ProductionPortfolioConfidenceResponse({
    required this.message,
    required this.summary,
    required this.estateAssetId,
    required this.statuses,
  });

  factory ProductionPortfolioConfidenceResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final summaryMap = json[_keySummary] as Map<String, dynamic>? ?? {};
    final scopeMap = json[_keyScope] as Map<String, dynamic>? ?? {};
    final statusList = (scopeMap[_keyStatuses] ?? []) as List<dynamic>;
    return ProductionPortfolioConfidenceResponse(
      message: _parseString(json[_keyMessage]),
      summary: ProductionPortfolioConfidenceSummary.fromJson(summaryMap),
      estateAssetId: _parseString(scopeMap[_keyEstateAssetId]),
      statuses: statusList.map((item) => item.toString()).toList(),
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

class ProductionTaskProgressProofRecord {
  final String url;
  final String publicId;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final DateTime? uploadedAt;
  final String uploadedBy;

  const ProductionTaskProgressProofRecord({
    required this.url,
    required this.publicId,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.uploadedAt,
    required this.uploadedBy,
  });

  factory ProductionTaskProgressProofRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionTaskProgressProofRecord(
      url: _parseNullableString(json[_keyProofUrl]) ?? "",
      publicId: _parseNullableString(json[_keyProofPublicId]) ?? "",
      filename: _parseNullableString(json[_keyProofFilename]) ?? "",
      mimeType: _parseNullableString(json[_keyProofMimeType]) ?? "",
      sizeBytes: _parseNullableNum(json[_keyProofSizeBytes])?.toInt() ?? 0,
      uploadedAt: _parseDate(json[_keyProofUploadedAt]),
      uploadedBy: _parseNullableString(json[_keyProofUploadedBy]) ?? "",
    );
  }

  bool get hasUrl => url.trim().isNotEmpty;
}

class ProductionTimelineRow {
  final String id;
  final DateTime? workDate;
  final String taskId;
  final String planId;
  final String staffId;
  final String attendanceId;
  final String unitId;
  final String taskDayLedgerId;
  final String taskTitle;
  final String phaseName;
  final String farmerName;
  final num expectedPlots;
  final num actualPlots;
  final num unitContribution;
  final String quantityActivityType;
  final num quantityAmount;
  final String activityType;
  final num activityQuantity;
  final String quantityUnit;
  final String status;
  final String delay;
  final String delayReason;
  final String approvalState;
  final String approvedBy;
  final DateTime? approvedAt;
  final String notes;
  final List<ProductionTaskProgressProofRecord> proofs;
  final int proofCount;
  final int proofCountRequired;
  final int proofCountUploaded;
  final String sessionStatus;
  final DateTime? clockInTime;
  final DateTime? clockOutTime;

  const ProductionTimelineRow({
    required this.id,
    required this.workDate,
    required this.taskId,
    required this.planId,
    required this.staffId,
    this.attendanceId = "",
    required this.unitId,
    required this.taskDayLedgerId,
    required this.taskTitle,
    required this.phaseName,
    required this.farmerName,
    required this.expectedPlots,
    required this.actualPlots,
    required this.unitContribution,
    required this.quantityActivityType,
    required this.quantityAmount,
    required this.activityType,
    required this.activityQuantity,
    required this.quantityUnit,
    required this.status,
    required this.delay,
    required this.delayReason,
    required this.approvalState,
    required this.approvedBy,
    required this.approvedAt,
    required this.notes,
    required this.proofs,
    required this.proofCount,
    required this.proofCountRequired,
    required this.proofCountUploaded,
    required this.sessionStatus,
    required this.clockInTime,
    required this.clockOutTime,
  });

  factory ProductionTimelineRow.fromJson(Map<String, dynamic> json) {
    final approvedAt = _parseDate(json[_keyApprovedAt]);
    final parsedApprovalState = _parseString(json[_keyApprovalState]);
    final normalizedApprovalState = parsedApprovalState.trim().isNotEmpty
        ? parsedApprovalState
        : (approvedAt != null ? "approved" : "pending_approval");
    final proofList = (json[_keyProofs] ?? []) as List<dynamic>;
    final proofs = proofList
        .whereType<Map<String, dynamic>>()
        .map(ProductionTaskProgressProofRecord.fromJson)
        .toList();

    return ProductionTimelineRow(
      id: _parseId(json),
      workDate: _parseDate(json[_keyWorkDate]),
      taskId: _parseString(json[_keyTaskId]),
      planId: _parseString(json[_keyPlanId]),
      staffId: _parseString(json[_keyStaffId]),
      attendanceId: _parseString(json[_keyAttendanceId]),
      unitId: _parseString(json[_keyUnitId]),
      taskDayLedgerId: _parseString(json[_keyTaskDayLedgerId]),
      taskTitle: _parseString(json[_keyTaskTitle]),
      phaseName: _parseString(json[_keyPhaseName]),
      farmerName: _parseString(json[_keyFarmerName]),
      expectedPlots: _parseNum(json[_keyExpectedPlots]),
      actualPlots:
          _parseNullableNum(json[_keyUnitContribution]) ??
          _parseNum(json[_keyActualPlots]),
      unitContribution:
          _parseNullableNum(json[_keyUnitContribution]) ??
          _parseNum(json[_keyActualPlots]),
      quantityActivityType:
          _parseString(json[_keyActivityType]).trim().isNotEmpty
          ? _parseString(json[_keyActivityType])
          : _parseString(json[_keyQuantityActivityType]),
      quantityAmount:
          _parseNullableNum(json[_keyActivityQuantity]) ??
          _parseNum(json[_keyQuantityAmount]),
      activityType: _parseString(json[_keyActivityType]).trim().isNotEmpty
          ? _parseString(json[_keyActivityType])
          : _parseString(json[_keyQuantityActivityType]),
      activityQuantity:
          _parseNullableNum(json[_keyActivityQuantity]) ??
          _parseNum(json[_keyQuantityAmount]),
      quantityUnit: _parseString(json[_keyQuantityUnit]),
      status: _parseString(json[_keyStatus]),
      delay: _parseString(json[_keyDelay]),
      delayReason: _parseString(json[_keyDelayReason]),
      approvalState: normalizedApprovalState,
      approvedBy: _parseString(json[_keyApprovedBy]),
      approvedAt: approvedAt,
      notes: _parseString(json[_keyNotes]),
      proofs: proofs,
      proofCount: proofs.isNotEmpty
          ? proofs.length
          : _parseInt(json[_keyProofCount]),
      proofCountRequired: _parseInt(json[_keyProofCountRequired]),
      proofCountUploaded: proofs.isNotEmpty
          ? proofs.length
          : (_parseInt(json[_keyProofCountUploaded]) > 0
                ? _parseInt(json[_keyProofCountUploaded])
                : _parseInt(json[_keyProofCount])),
      sessionStatus: _parseString(json[_keySessionStatus]),
      clockInTime: _parseDate(json[_keyClockInTime]),
      clockOutTime: _parseDate(json[_keyClockOutTime]),
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
  final String attendanceId;
  final String unitId;
  final String taskDayLedgerId;
  final DateTime? workDate;
  final num expectedPlots;
  final num actualPlots;
  final num unitContribution;
  final String quantityActivityType;
  final num quantityAmount;
  final String activityType;
  final num activityQuantity;
  final String quantityUnit;
  final String delayReason;
  final String notes;
  final List<ProductionTaskProgressProofRecord> proofs;
  final int proofCount;
  final int proofCountRequired;
  final int proofCountUploaded;
  final String sessionStatus;
  final DateTime? clockInTime;
  final DateTime? clockOutTime;
  final String createdBy;
  final String approvedBy;
  final DateTime? approvedAt;

  const ProductionTaskProgressRecord({
    required this.id,
    required this.taskId,
    required this.planId,
    required this.staffId,
    this.attendanceId = "",
    required this.unitId,
    required this.taskDayLedgerId,
    required this.workDate,
    required this.expectedPlots,
    required this.actualPlots,
    required this.unitContribution,
    required this.quantityActivityType,
    required this.quantityAmount,
    required this.activityType,
    required this.activityQuantity,
    required this.quantityUnit,
    required this.delayReason,
    required this.notes,
    required this.proofs,
    required this.proofCount,
    required this.proofCountRequired,
    required this.proofCountUploaded,
    required this.sessionStatus,
    required this.clockInTime,
    required this.clockOutTime,
    required this.createdBy,
    required this.approvedBy,
    required this.approvedAt,
  });

  factory ProductionTaskProgressRecord.fromJson(Map<String, dynamic> json) {
    final proofList = json[_keyProofs];
    final proofs = proofList is List
        ? proofList
              .whereType<Map<String, dynamic>>()
              .map(ProductionTaskProgressProofRecord.fromJson)
              .toList()
        : const <ProductionTaskProgressProofRecord>[];
    return ProductionTaskProgressRecord(
      id: _parseId(json),
      taskId: _parseString(json[_keyTaskId]),
      planId: _parseString(json[_keyPlanId]),
      staffId: _parseString(json[_keyStaffId]),
      attendanceId: _parseString(json[_keyAttendanceId]),
      unitId: _parseString(json[_keyUnitId]),
      taskDayLedgerId: _parseString(json[_keyTaskDayLedgerId]),
      workDate: _parseDate(json[_keyWorkDate]),
      expectedPlots: _parseNum(json[_keyExpectedPlots]),
      actualPlots:
          _parseNullableNum(json[_keyUnitContribution]) ??
          _parseNum(json[_keyActualPlots]),
      unitContribution:
          _parseNullableNum(json[_keyUnitContribution]) ??
          _parseNum(json[_keyActualPlots]),
      quantityActivityType:
          _parseString(json[_keyActivityType]).trim().isNotEmpty
          ? _parseString(json[_keyActivityType])
          : _parseString(json[_keyQuantityActivityType]),
      quantityAmount:
          _parseNullableNum(json[_keyActivityQuantity]) ??
          _parseNum(json[_keyQuantityAmount]),
      activityType: _parseString(json[_keyActivityType]).trim().isNotEmpty
          ? _parseString(json[_keyActivityType])
          : _parseString(json[_keyQuantityActivityType]),
      activityQuantity:
          _parseNullableNum(json[_keyActivityQuantity]) ??
          _parseNum(json[_keyQuantityAmount]),
      quantityUnit: _parseString(json[_keyQuantityUnit]),
      delayReason: _parseString(json[_keyDelayReason]),
      notes: _parseString(json[_keyNotes]),
      proofs: proofs,
      proofCount: proofs.isNotEmpty
          ? proofs.length
          : _parseInt(json[_keyProofCount]),
      proofCountRequired: _parseInt(json[_keyProofCountRequired]),
      proofCountUploaded: proofs.isNotEmpty
          ? proofs.length
          : (_parseInt(json[_keyProofCountUploaded]) > 0
                ? _parseInt(json[_keyProofCountUploaded])
                : _parseInt(json[_keyProofCount])),
      sessionStatus: _parseString(json[_keySessionStatus]),
      clockInTime: _parseDate(json[_keyClockInTime]),
      clockOutTime: _parseDate(json[_keyClockOutTime]),
      createdBy: _parseString(json[_keyCreatedBy]),
      approvedBy: _parseString(json[_keyApprovedBy]),
      approvedAt: _parseDate(json[_keyApprovedAt]),
    );
  }
}

class ProductionTaskProgressResponse {
  final ProductionTaskProgressRecord progress;
  final ProductionTaskDayLedger? ledger;

  const ProductionTaskProgressResponse({
    required this.progress,
    required this.ledger,
  });

  factory ProductionTaskProgressResponse.fromJson(Map<String, dynamic> json) {
    final progressMap = (json[_keyProgress] ?? {}) as Map<String, dynamic>;
    final ledgerMap = json[_keyLedger] is Map<String, dynamic>
        ? json[_keyLedger] as Map<String, dynamic>
        : null;
    return ProductionTaskProgressResponse(
      progress: ProductionTaskProgressRecord.fromJson(progressMap),
      ledger: ledgerMap == null
          ? null
          : ProductionTaskDayLedger.fromJson(ledgerMap),
    );
  }
}

class ProductionTaskProgressBatchEntryInput {
  final String taskId;
  final String staffId;
  final String unitId;
  final num actualPlots;
  final String delayReason;
  final String notes;

  const ProductionTaskProgressBatchEntryInput({
    required this.taskId,
    required this.staffId,
    this.unitId = "",
    required this.actualPlots,
    required this.delayReason,
    required this.notes,
  });

  Map<String, dynamic> toJson() {
    final payload = {
      _keyTaskId: taskId,
      _keyStaffId: staffId,
      _keyActualPlots: actualPlots,
      _keyDelayReason: delayReason,
      _keyNotes: notes,
    };
    if (unitId.trim().isNotEmpty) {
      payload[_keyUnitId] = unitId.trim();
    }
    return payload;
  }
}

class ProductionTaskProgressBatchSuccess {
  final int index;
  final String taskId;
  final String staffId;
  final String unitId;
  final ProductionTaskProgressRecord progress;

  const ProductionTaskProgressBatchSuccess({
    required this.index,
    required this.taskId,
    required this.staffId,
    required this.unitId,
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
      unitId: _parseString(json[_keyUnitId]),
      progress: ProductionTaskProgressRecord.fromJson(progressMap),
    );
  }
}

class ProductionTaskProgressBatchError {
  final int index;
  final String taskId;
  final String staffId;
  final String unitId;
  final String errorCode;
  final String error;

  const ProductionTaskProgressBatchError({
    required this.index,
    required this.taskId,
    required this.staffId,
    required this.unitId,
    required this.errorCode,
    required this.error,
  });

  factory ProductionTaskProgressBatchError.fromJson(Map<String, dynamic> json) {
    return ProductionTaskProgressBatchError(
      index: _parseInt(json[_keyEntryIndex]),
      taskId: _parseString(json[_keyTaskId]),
      staffId: _parseString(json[_keyStaffId]),
      unitId: _parseString(json[_keyUnitId]),
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

int requiredTaskProgressProofCount(num actualPlots) {
  final normalizedActualPlots = actualPlots.toDouble();
  if (normalizedActualPlots <= 0) {
    return 1;
  }
  return normalizedActualPlots.ceil();
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
