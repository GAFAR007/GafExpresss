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
const String _defaultPhaseNamePrefix = "Phase";
const String _taskIdPrefix = "draft_task_";
const String _emptyText = "";
const int _minIndex = 0;
const int _phaseOrderOffset = 1;
const Object _unsetValue = Object();

// WHY: Draft statuses drive the create-table UI without touching backend payloads.
enum ProductionTaskStatus { notStarted, inProgress, blocked, done }

// WHY: Keep status defaults consistent across manual + AI drafts.
const ProductionTaskStatus _defaultTaskStatus =
    ProductionTaskStatus.notStarted;

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
const String _payloadTitle = "title";
const String _payloadNotes = "notes";
const String _payloadStartDate = "startDate";
const String _payloadEndDate = "endDate";
const String _payloadAiGenerated = "aiGenerated";
const String _payloadPhases = "phases";
const String _payloadPhaseName = "name";
const String _payloadPhaseOrder = "order";
const String _payloadTasks = "tasks";
const String _payloadTaskTitle = "title";
const String _payloadTaskRole = "roleRequired";
const String _payloadTaskStaff = "assignedStaffId";
const String _payloadTaskWeight = "weight";
const String _payloadTaskInstructions = "instructions";
const String _payloadTaskDependencies = "dependencies";

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
  final List<ProductionTaskDraft> tasks;

  const ProductionPhaseDraft({
    required this.name,
    required this.order,
    required this.tasks,
  });

  ProductionPhaseDraft copyWith({
    List<ProductionTaskDraft>? tasks,
  }) {
    return ProductionPhaseDraft(
      name: name,
      order: order,
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
  final bool aiGenerated;
  final List<ProductionPhaseDraft> phases;

  const ProductionPlanDraftState({
    required this.title,
    required this.notes,
    required this.estateAssetId,
    required this.productId,
    required this.startDate,
    required this.endDate,
    required this.aiGenerated,
    required this.phases,
  });

  ProductionPlanDraftState copyWith({
    String? title,
    String? notes,
    String? estateAssetId,
    String? productId,
    DateTime? startDate,
    DateTime? endDate,
    bool? aiGenerated,
    List<ProductionPhaseDraft>? phases,
  }) {
    return ProductionPlanDraftState(
      title: title ?? this.title,
      notes: notes ?? this.notes,
      estateAssetId: estateAssetId ?? this.estateAssetId,
      productId: productId ?? this.productId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      aiGenerated: aiGenerated ?? this.aiGenerated,
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
            aiGenerated: false,
            phases: _buildDefaultPhases(),
          ),
        ) {
    AppDebug.log(_logTag, _logInit);
  }

  void updateTitle(String value) {
    // WHY: Title helps distinguish plans in list views.
    state = state.copyWith(title: value);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldTitle},
    );
  }

  void updateNotes(String value) {
    // WHY: Notes capture plan context for managers.
    state = state.copyWith(notes: value);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldNotes},
    );
  }

  void updateEstate(String? estateAssetId) {
    // WHY: Estate scope is required for plan creation.
    state = state.copyWith(estateAssetId: estateAssetId);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldEstate},
    );
  }

  void updateProduct(String? productId) {
    // WHY: Product links plan output to inventory.
    state = state.copyWith(productId: productId);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldProduct},
    );
  }

  void updateStartDate(DateTime? date) {
    // WHY: Start date drives phase and task scheduling.
    state = state.copyWith(startDate: date);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldStartDate},
    );
  }

  void updateEndDate(DateTime? date) {
    // WHY: End date drives phase and task scheduling.
    state = state.copyWith(endDate: date);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldEndDate},
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
      estateAssetId: null,
      productId: null,
      startDate: null,
      endDate: null,
      aiGenerated: false,
      phases: _buildDefaultPhases(),
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

    state = state.copyWith(phases: phases);
    AppDebug.log(
      _logTag,
      _logTaskAdded,
      extra: {_extraPhaseKey: phase.name},
    );
  }

  void removeTask(int phaseIndex, String taskId) {
    if (phaseIndex < _minIndex || phaseIndex >= state.phases.length) {
      return;
    }

    final phases = [...state.phases];
    final phase = phases[phaseIndex];
    final updatedTasks = phase.tasks.where((task) => task.id != taskId).toList();
    phases[phaseIndex] = phase.copyWith(tasks: updatedTasks);

    state = state.copyWith(phases: phases);
    AppDebug.log(
      _logTag,
      _logTaskRemoved,
      extra: {_extraPhaseKey: phase.name},
    );
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
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(weight: weight),
    );
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
    final phaseName = phaseIndex >= _minIndex && phaseIndex < state.phases.length
        ? state.phases[phaseIndex].name
        : _emptyText;
    _updateTask(
      phaseIndex,
      taskId,
      (task) => task.copyWith(
        status: status,
        completedAt:
            status == ProductionTaskStatus.done ? DateTime.now() : null,
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
    AppDebug.log(
      _logTag,
      _logTaskDone,
      extra: {_extraTaskIdKey: taskId},
    );
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
        state.endDate!.isBefore(state.startDate!)) {
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
      if (task.assignedStaffId == null || task.assignedStaffId!.trim().isEmpty) {
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

    state = state.copyWith(phases: phases);
    AppDebug.log(
      _logTag,
      _logUpdate,
      extra: {_extraFieldKey: _fieldTask},
    );
  }
}

final productionPlanDraftProvider =
    StateNotifierProvider<ProductionPlanDraftController, ProductionPlanDraftState>(
  (ref) => ProductionPlanDraftController(),
);

ProductionPlanDraftState parseProductionPlanDraftResponse(
  Map<String, dynamic> json,
) {
  final draftMap = json[_responseDraftKey] is Map<String, dynamic>
      ? json[_responseDraftKey] as Map<String, dynamic>
      : <String, dynamic>{};
  // WHY: Avoid unsafe casts when the response is incomplete.
  final phasesValue = draftMap[_payloadPhases];
  final phaseCount = phasesValue is List ? phasesValue.length : 0;
  AppDebug.log(
    _logTag,
    _logDraftParsed,
    extra: {_extraPhaseCountKey: phaseCount},
  );
  return _buildDraftState(draftMap);
}

List<ProductionPhaseDraft> _buildDefaultPhases() {
  return _defaultPhaseNames
      .asMap()
      .entries
      .map(
        (entry) => ProductionPhaseDraft(
          name: entry.value,
          order: entry.key + _phaseOrderOffset,
          tasks: const [],
        ),
      )
      .toList();
}

String _buildTaskId() {
  return "$_taskIdPrefix${DateTime.now().microsecondsSinceEpoch}";
}

ProductionPlanDraftState _buildDraftState(
  Map<String, dynamic> draft,
) {
  // WHY: Use backend-provided draft values where possible.
  final parsedPhases = _parseDraftPhases(
    draft[_payloadPhases],
  );

  return ProductionPlanDraftState(
    title: _parseString(
      draft[_payloadTitle],
      fallback: _emptyText,
    ),
    notes: _parseString(
      draft[_payloadNotes],
      fallback: _emptyText,
    ),
    estateAssetId: _parseNullableString(
      draft[_payloadEstateId],
    ),
    productId: _parseNullableString(
      draft[_payloadProductId],
    ),
    startDate: _parseDate(
      draft[_payloadStartDate],
    ),
    endDate: _parseDate(
      draft[_payloadEndDate],
    ),
    aiGenerated: draft[_payloadAiGenerated] == true,
    phases: parsedPhases.isEmpty
        ? _buildDefaultPhases()
        : parsedPhases,
  );
}

List<ProductionPhaseDraft> _parseDraftPhases(
  dynamic value,
) {
  // WHY: Defensive parsing keeps UI stable on partial drafts.
  final list = value is List ? value : const [];
  return list
      .asMap()
      .entries
      .map((entry) => _parseDraftPhase(entry.key, entry.value))
      .toList();
}

ProductionPhaseDraft _parseDraftPhase(
  int index,
  dynamic value,
) {
  // WHY: Coerce phase payloads into predictable draft objects.
  final map = value is Map<String, dynamic>
      ? value
      : <String, dynamic>{};
  final name = _parseString(
    map[_payloadPhaseName],
    fallback: "${_defaultPhaseNamePrefix} ${index + _phaseOrderOffset}",
  );
  final order = _parseInt(
    map[_payloadPhaseOrder],
    fallback: index + _phaseOrderOffset,
  );
  return ProductionPhaseDraft(
    name: name,
    order: order,
    tasks: _parseDraftTasks(
      map[_payloadTasks],
    ),
  );
}

List<ProductionTaskDraft> _parseDraftTasks(
  dynamic value,
) {
  // WHY: Default to empty tasks when AI returns null.
  final list = value is List ? value : const [];
  return list
      .map((item) => _parseDraftTask(item))
      .toList();
}

ProductionTaskDraft _parseDraftTask(dynamic value) {
  // WHY: Normalize task fields before editing in UI.
  final map = value is Map<String, dynamic>
      ? value
      : <String, dynamic>{};
  final role = _parseString(
    map[_payloadTaskRole],
    fallback: staffRoleValues.first,
  );
  return ProductionTaskDraft(
    id: _buildTaskId(),
    title: _parseString(
      map[_payloadTaskTitle],
      fallback: _defaultTaskTitle,
    ),
    roleRequired: role,
    assignedStaffId: _parseNullableString(
      map[_payloadTaskStaff],
    ),
    weight: _parseInt(
      map[_payloadTaskWeight],
      fallback: _defaultTaskWeight,
    ),
    instructions: _parseString(
      map[_payloadTaskInstructions],
      fallback: _emptyText,
    ),
    status: _defaultTaskStatus,
    completedAt: null,
    completedByStaffId: null,
  );
}

String _parseString(dynamic value, {required String fallback}) {
  // WHY: Ensure labels never render as "null".
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _parseNullableString(dynamic value) {
  // WHY: Preserve nulls for optional fields like staff assignment.
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _parseInt(dynamic value, {required int fallback}) {
  // WHY: Avoid crashes when AI returns non-numeric weights.
  if (value == null) return fallback;
  final parsed = int.tryParse(value.toString());
  return parsed ?? fallback;
}

DateTime? _parseDate(dynamic value) {
  // WHY: Dates may be missing in drafts; keep nullable.
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
