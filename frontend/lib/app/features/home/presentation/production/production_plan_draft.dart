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
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';

// WHY: Default phases match backend scheduling rules.
const List<String> _defaultPhaseNames = [
  "Planning",
  "Planting",
  "Irrigation",
  "Harvest",
  "Storage",
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
const String _errorTasksRequired = "Add at least one task.";
const String _errorTaskTitleRequired = "Task title is required.";
const String _errorTaskRoleRequired = "Task role is required.";
const String _errorTaskStaffRequired = "Assigned staff is required.";

// WHY: Payload keys should be consistent with backend expectations.
const String _payloadEstateId = "estateAssetId";
const String _payloadProductId = "productId";
const String _payloadPlanTitle = "planTitle";
const String _payloadTitle = "title";
const String _payloadNotes = "notes";
const String _payloadStartDate = "startDate";
const String _payloadEndDate = "endDate";
const String _payloadAiGenerated = "aiGenerated";
const String _payloadPhases = "phases";
const String _payloadPhaseName = "name";
const String _payloadPhaseOrder = "order";
const String _payloadPhaseEstimatedDays = "estimatedDays";
const String _payloadTasks = "tasks";
const String _payloadTaskTitle = "title";
const String _payloadTaskRole = "roleRequired";
const String _payloadTaskStaff = "assignedStaffId";
const String _payloadTaskWeight = "weight";
const String _payloadTaskInstructions = "instructions";
const String _payloadTaskDependencies = "dependencies";
const String _payloadSummary = "summary";
const String _payloadSummaryTotalTasks = "totalTasks";
const String _payloadSummaryTotalEstimatedDays = "totalEstimatedDays";
const String _payloadSummaryRiskNotes = "riskNotes";
const String _payloadProposedProduct = "proposedProduct";
const String _payloadProposedStartDate = "proposedStartDate";
const String _payloadProposedEndDate = "proposedEndDate";

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
const String _extraStatusKey = "status";
const String _extraCompletedAtKey = "completedAt";
const String _fieldTitle = "title";
const String _fieldNotes = "notes";
const String _fieldEstate = "estateAssetId";
const String _fieldProduct = "productId";
const String _fieldStartDate = "startDate";
const String _fieldEndDate = "endDate";
const String _fieldAiGenerated = "aiGenerated";
const String _fieldTask = "task";
const String _responseDraftKey = "draft";
const String _extraPhaseCountKey = "phaseCount";
const String _extraMissingKey = "missing";
const String _extraInvalidKey = "invalid";

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

class ProductionTaskDraft {
  final String id;
  final String title;
  final String roleRequired;
  final String? assignedStaffId;
  final int weight;
  final String instructions;
  final ProductionTaskStatus status;
  final DateTime? completedAt;
  final String? completedByStaffId;

  const ProductionTaskDraft({
    required this.id,
    required this.title,
    required this.roleRequired,
    required this.assignedStaffId,
    required this.weight,
    required this.instructions,
    required this.status,
    required this.completedAt,
    required this.completedByStaffId,
  });

  ProductionTaskDraft copyWith({
    String? title,
    String? roleRequired,
    String? assignedStaffId,
    int? weight,
    String? instructions,
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
    return ProductionTaskDraft(
      id: id,
      title: title ?? this.title,
      roleRequired: roleRequired ?? this.roleRequired,
      assignedStaffId: assignedStaffId ?? this.assignedStaffId,
      weight: weight ?? this.weight,
      instructions: instructions ?? this.instructions,
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
  final List<ProductionTaskDraft> tasks;

  const ProductionPhaseDraft({
    required this.name,
    required this.order,
    required this.estimatedDays,
    required this.tasks,
  });

  ProductionPhaseDraft copyWith({
    int? estimatedDays,
    List<ProductionTaskDraft>? tasks,
  }) {
    return ProductionPhaseDraft(
      name: name,
      order: order,
      estimatedDays: estimatedDays ?? this.estimatedDays,
      tasks: tasks ?? this.tasks,
    );
  }
}

class ProductionPlanDraftState {
  final String title;
  final String notes;
  final String? estateAssetId;
  final String? productId;
  final DateTime? startDate;
  final DateTime? endDate;
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
    required this.estateAssetId,
    required this.productId,
    required this.startDate,
    required this.endDate,
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
    Object? estateAssetId = _unsetValue,
    Object? productId = _unsetValue,
    Object? startDate = _unsetValue,
    Object? endDate = _unsetValue,
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
          estateAssetId: null,
          productId: null,
          startDate: null,
          endDate: null,
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
    state = state.copyWith(startDate: date, startDateAiSuggested: false);
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldStartDate});
  }

  void updateEndDate(DateTime? date) {
    // WHY: End date drives phase and task scheduling.
    state = state.copyWith(endDate: date, endDateAiSuggested: false);
    AppDebug.log(_logTag, _logUpdate, extra: {_extraFieldKey: _fieldEndDate});
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
      estateAssetId: null,
      productId: null,
      startDate: null,
      endDate: null,
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
    state = draft;
    AppDebug.log(
      _logTag,
      _logDraftApplied,
      extra: {_extraPhaseCountKey: draft.phases.length},
    );
  }

  void addTask(int phaseIndex) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return;
    }

    final task = ProductionTaskDraft(
      id: _buildTaskId(),
      title: _defaultTaskTitle,
      roleRequired: staffRoleValues.first,
      assignedStaffId: null,
      weight: _defaultTaskWeight,
      instructions: _emptyText,
      status: _defaultTaskStatus,
      completedAt: null,
      completedByStaffId: null,
    );

    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    final updatedTasks = [...phase.tasks, task];
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);

    state = _withComputedSummary(state.copyWith(phases: phases));
    AppDebug.log(_logTag, _logTaskAdded, extra: {_extraPhaseKey: phase.name});
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
        status: _defaultTaskStatus,
        completedAt: null,
        completedByStaffId: null,
      ),
    );
  }

  void updateTaskStaff(int phaseIndex, String taskId, String? staffId) {
    // WHY: Assignment changes should clear completion metadata to avoid drift.
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(
        assignedStaffId: staffId,
        status: _defaultTaskStatus,
        completedAt: null,
        completedByStaffId: null,
      ),
    );
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

    if (state.title.trim().isEmpty) {
      errors.add(_errorTitleRequired);
    }
    if (state.estateAssetId == null || state.estateAssetId!.trim().isEmpty) {
      errors.add(_errorEstateRequired);
    }
    if (state.productId == null || state.productId!.trim().isEmpty) {
      errors.add(_errorProductRequired);
    }
    if (state.startDate == null) {
      errors.add(_errorStartDateRequired);
    }
    if (state.endDate == null) {
      errors.add(_errorEndDateRequired);
    }
    if (state.startDate != null &&
        state.endDate != null &&
        !state.endDate!.isAfter(state.startDate!)) {
      errors.add(_errorDateRange);
    }

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
      if (task.assignedStaffId == null ||
          task.assignedStaffId!.trim().isEmpty) {
        errors.add(_errorTaskStaffRequired);
        break;
      }
    }

    return errors;
  }

  Map<String, dynamic> toPayload() {
    final phasesPayload = state.phases.map((phase) {
      final taskPayloads = phase.tasks
          .map(
            (task) => {
              _payloadTaskTitle: task.title.trim(),
              _payloadTaskRole: task.roleRequired,
              _payloadTaskStaff: task.assignedStaffId,
              _payloadTaskWeight: task.weight,
              _payloadTaskInstructions: task.instructions.trim(),
              _payloadTaskDependencies: const [],
            },
          )
          .toList();

      return {
        _payloadPhaseName: phase.name,
        _payloadPhaseOrder: phase.order,
        _payloadPhaseEstimatedDays: phase.estimatedDays,
        _payloadTasks: taskPayloads,
      };
    }).toList();

    return {
      _payloadEstateId: state.estateAssetId,
      _payloadProductId: state.productId,
      _payloadTitle: state.title.trim(),
      _payloadNotes: state.notes.trim(),
      _payloadStartDate: state.startDate?.toIso8601String(),
      _payloadEndDate: state.endDate?.toIso8601String(),
      _payloadAiGenerated: state.aiGenerated,
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
  final totalTasks = draft.phases.fold<int>(
    0,
    (sum, phase) => sum + phase.tasks.length,
  );
  final totalEstimatedDays = draft.phases.fold<int>(
    0,
    (sum, phase) => sum + phase.estimatedDays,
  );
  return draft.copyWith(
    totalTasks: totalTasks,
    totalEstimatedDays: totalEstimatedDays,
  );
}

final productionPlanDraftProvider =
    StateNotifierProvider<
      ProductionPlanDraftController,
      ProductionPlanDraftState
    >((ref) => ProductionPlanDraftController());

ProductionPlanDraftState parseProductionPlanDraftResponse(
  Map<String, dynamic> json,
) {
  final draftValue = json[_responseDraftKey];
  if (draftValue is! Map<String, dynamic>) {
    throw ProductionAiDraftError.schema(
      missing: [_responseDraftKey],
      invalid: const [],
      message: _aiDraftFallbackMessage,
    );
  }

  final diagnostics = _validateDraftMap(draftValue);
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

  final parsed = _buildStrictDraftState(draftValue);
  AppDebug.log(
    _logTag,
    _logDraftParsed,
    extra: {_extraPhaseCountKey: parsed.phases.length},
  );
  return parsed;
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
  if (resolvedStartDate == null) {
    missing.add(_payloadStartDate);
  }
  if (resolvedEndDate == null) {
    missing.add(_payloadEndDate);
  }
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
  if (!hasDirectProduct) {
    if (proposedProductValue == null) {
      missing.add(_payloadProductId);
      missing.add(_payloadProposedProduct);
    } else if (proposedProductValue is! Map<String, dynamic>) {
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
  } else if (!_isValidRequiredString(draft[_payloadProductId])) {
    invalid.add(_payloadProductId);
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
  final proposedStartDateRaw = draft[_payloadProposedStartDate];
  final proposedEndDateRaw = draft[_payloadProposedEndDate];
  final startDateString =
      _isValidIsoDate(startDateRaw?.toString() ?? _emptyText)
      ? startDateRaw.toString()
      : proposedStartDateRaw.toString();
  final endDateString = _isValidIsoDate(endDateRaw?.toString() ?? _emptyText)
      ? endDateRaw.toString()
      : proposedEndDateRaw.toString();
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
      tasks.add(
        ProductionTaskDraft(
          id: _buildTaskId(),
          title: taskMap[_payloadTaskTitle].toString().trim(),
          roleRequired: taskMap[_payloadTaskRole].toString().trim(),
          assignedStaffId: assignedStaff?.toString().trim(),
          weight: _parseStrictInt(taskMap[_payloadTaskWeight])!,
          instructions: taskMap[_payloadTaskInstructions].toString().trim(),
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
    estateAssetId: draft[_payloadEstateId].toString().trim(),
    productId: hasDirectProduct
        ? draft[_payloadProductId].toString().trim()
        : null,
    startDate: DateTime.parse(startDateString),
    endDate: DateTime.parse(endDateString),
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
