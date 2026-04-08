/// lib/app/features/home/presentation/production/production_plan_draft_editor_screen.dart
/// -------------------------------------------------------------------------------
/// WHAT:
/// - Dedicated full-screen editor for saved and unsaved production drafts.
///
/// WHY:
/// - Keeps the assistant screen focused on setup + timeline preview.
/// - Gives managers one place to edit tasks and review draft history.
///
/// HOW:
/// - Hydrates the shared draft provider from a saved draft detail when `planId` is present.
/// - Reuses the production task table in list-only mode for full-width editing.
/// - Saves new drafts or updates existing drafts and displays audit/revision summaries.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/core/platform/text_file_download.dart';
import 'package:frontend/app/features/auth/domain/models/auth_session.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_draft_presence.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_task_table.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_colors.dart';

const double _pagePadding = 20;
const double _sectionSpacing = 18;
const double _cardRadius = 22;
const int _draftAssetQueryPage = 1;
const int _draftAssetQueryLimit = 200;
const int _documentImportCharacterLimit = 24000;
const int _draftAiRefineContextCharacterLimit = 40000;
const int _documentImportMaxBytes = 4 * 1024 * 1024;
const List<String> _documentImportAllowedExtensions = [
  "pdf",
  "html",
  "htm",
  "txt",
];

enum _DraftEditorMobileSection { tasks, details }

enum _DraftEditorSupportTab { overview, targets, history }

const String _draftEditorLogTag = "PRODUCTION_DRAFT_EDITOR";
const String _logLayoutMode = "layout_mode";
const String _logMobileSectionChanged = "mobile_section_changed";
const String _logSupportTabChanged = "support_tab_changed";
const String _logSaveDraftStart = "save_draft_start";
const String _logSaveDraftSuccess = "save_draft_success";
const String _logSaveDraftFailure = "save_draft_failure";
const String _logStartProductionStart = "start_production_start";
const String _logStartProductionSuccess = "start_production_success";
const String _logStartProductionFailure = "start_production_failure";
const String _logReturnToDraftStart = "return_to_draft_start";
const String _logReturnToDraftSuccess = "return_to_draft_success";
const String _logReturnToDraftFailure = "return_to_draft_failure";
const String _extraLayoutModeKey = "layoutMode";
const String _extraPlanIdKey = "planId";
const String _extraMobileSectionKey = "mobileSection";
const String _extraSupportTabKey = "supportTab";
const String _extraDraftStatusKey = "draftStatus";
const String _startProductionConfirmTitle = "Start this production plan?";
const String _startProductionConfirmMessage =
    "We will save the latest draft changes, activate the plan, and open the live production workspace.";
const String _startProductionConfirmLabel = "Start production";
const Set<String> _draftAssignmentManagementRoles = <String>{
  staffRoleFarmManager,
  staffRoleEstateManager,
  staffRoleAssetManager,
};

class _DraftEditorLayoutMetrics {
  final int totalTasks;
  final int phaseCount;
  final int unassignedTasks;
  final int blockedTasks;
  final int totalProjectDays;

  const _DraftEditorLayoutMetrics({
    required this.totalTasks,
    required this.phaseCount,
    required this.unassignedTasks,
    required this.blockedTasks,
    required this.totalProjectDays,
  });

  factory _DraftEditorLayoutMetrics.fromDraft(ProductionPlanDraftState draft) {
    final tasks = draft.phases.expand((phase) => phase.tasks).toList();
    final startDate = draft.startDate;
    final endDate = draft.endDate;
    final totalProjectDays = startDate == null || endDate == null
        ? 0
        : endDate.difference(startDate).inDays + 1;
    return _DraftEditorLayoutMetrics(
      totalTasks: tasks.length,
      phaseCount: draft.phases.length,
      unassignedTasks: tasks
          .where((task) => task.assignedStaffProfileIds.isEmpty)
          .length,
      blockedTasks: tasks
          .where((task) => task.status == ProductionTaskStatus.blocked)
          .length,
      totalProjectDays: math.max(0, totalProjectDays),
    );
  }
}

class _DraftWorkScopeSummary {
  final int totalUnits;
  final String singularLabel;
  final bool isEstimated;

  const _DraftWorkScopeSummary({
    required this.totalUnits,
    required this.singularLabel,
    required this.isEstimated,
  });

  String get _normalizedSingularLabel {
    final normalized = singularLabel.trim();
    return normalized.isEmpty ? "work unit" : normalized;
  }

  String get valueLabel {
    final safeTotal = totalUnits < 1 ? 1 : totalUnits;
    final unitLabel = safeTotal == 1
        ? _normalizedSingularLabel
        : _pluralizeDraftWorkUnitLabel(_normalizedSingularLabel);
    return "$safeTotal $unitLabel";
  }

  String get helperText => isEstimated
      ? "Estimated from the current phase workload until the saved unit footprint is available."
      : "Representative work-unit footprint for scheduling and staffing.";
}

bool _looksLikeDraftUnitIdentifierToken(String token) {
  final normalized = token.trim().replaceAll("#", "");
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r"^[A-Za-z]?\d+[A-Za-z]?$").hasMatch(normalized) ||
      RegExp(r"^[A-Za-z]$").hasMatch(normalized);
}

String _extractDraftWorkUnitStem(String label) {
  final normalized = label
      .trim()
      .replaceAll(RegExp(r"[_-]+"), " ")
      .replaceAll(RegExp(r"\s+"), " ");
  if (normalized.isEmpty) {
    return "";
  }
  if (RegExp(r"^[a-f0-9]{24}$", caseSensitive: false).hasMatch(normalized)) {
    return "";
  }
  final tokens = normalized
      .split(" ")
      .where((token) => token.isNotEmpty)
      .toList();
  while (tokens.length > 1 && _looksLikeDraftUnitIdentifierToken(tokens.last)) {
    tokens.removeLast();
  }
  final stem = tokens.join(" ").trim().toLowerCase();
  return stem.isEmpty ? normalized.toLowerCase() : stem;
}

String _pluralizeDraftWorkUnitWord(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  final lower = normalized.toLowerCase();
  if (lower.endsWith("s")) {
    return normalized;
  }
  if (RegExp(r"[^aeiou]y$").hasMatch(lower)) {
    return "${normalized.substring(0, normalized.length - 1)}ies";
  }
  if (lower.endsWith("ch") ||
      lower.endsWith("sh") ||
      lower.endsWith("x") ||
      lower.endsWith("z")) {
    return "${normalized}es";
  }
  return "${normalized}s";
}

String _pluralizeDraftWorkUnitLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  final tokens = normalized
      .split(" ")
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty) {
    return normalized;
  }
  final lastToken = tokens.removeLast();
  tokens.add(_pluralizeDraftWorkUnitWord(lastToken));
  return tokens.join(" ");
}

String _inferDraftWorkUnitStemFromContext({
  required String fallbackWorkUnitLabel,
  String contextText = "",
}) {
  final normalizedFallback = _extractDraftWorkUnitStem(fallbackWorkUnitLabel);
  final normalizedContext = contextText.trim().toLowerCase();
  final fallbackIsGeneric =
      normalizedFallback.isEmpty ||
      normalizedFallback == "plot" ||
      normalizedFallback == "work unit";
  if (fallbackIsGeneric &&
      (normalizedContext.contains("greenhouse") ||
          normalizedContext.contains("green house"))) {
    return "greenhouse";
  }
  return "";
}

class _DraftExportPhaseWindow {
  final int phaseIndex;
  final ProductionPhaseDraft phase;
  final DateTime? startDate;
  final DateTime? endDate;
  final int allocatedDays;
  final int projectDayStart;
  final int projectDayEnd;

  const _DraftExportPhaseWindow({
    required this.phaseIndex,
    required this.phase,
    required this.startDate,
    required this.endDate,
    required this.allocatedDays,
    required this.projectDayStart,
    required this.projectDayEnd,
  });
}

class _DraftExportPhaseDay {
  final DateTime? date;
  final int projectDayNumber;
  final int phaseDayNumber;
  final List<ProductionTaskDraft> tasks;

  const _DraftExportPhaseDay({
    required this.date,
    required this.projectDayNumber,
    required this.phaseDayNumber,
    required this.tasks,
  });
}

class _DraftRefinePhaseGap {
  final String phaseName;
  final int allocatedDays;
  final int currentTaskCount;
  final int suggestedTaskCount;

  const _DraftRefinePhaseGap({
    required this.phaseName,
    required this.allocatedDays,
    required this.currentTaskCount,
    required this.suggestedTaskCount,
  });

  int get missingTaskCount =>
      math.max(0, suggestedTaskCount - currentTaskCount);
}

class _DraftRefineGapReport {
  final int totalProjectDays;
  final int totalTaskCount;
  final int suggestedTaskCount;
  final int genericTaskCount;
  final int missingInstructionCount;
  final int unassignedTaskCount;
  final List<_DraftRefinePhaseGap> phaseGaps;

  const _DraftRefineGapReport({
    required this.totalProjectDays,
    required this.totalTaskCount,
    required this.suggestedTaskCount,
    required this.genericTaskCount,
    required this.missingInstructionCount,
    required this.unassignedTaskCount,
    required this.phaseGaps,
  });

  int get suggestedAdditionalTaskCount =>
      math.max(0, suggestedTaskCount - totalTaskCount);

  List<String> get issueSummaries {
    final lines = <String>[
      "Project window: $totalProjectDays days with $totalTaskCount tasks. A denser working draft should carry about $suggestedTaskCount tasks.",
    ];
    if (genericTaskCount > 0) {
      lines.add(
        "$genericTaskCount tasks still read like placeholders and need real task names.",
      );
    }
    if (missingInstructionCount > 0) {
      lines.add(
        "$missingInstructionCount tasks are missing instructions or execution notes.",
      );
    }
    if (unassignedTaskCount > 0) {
      lines.add(
        "$unassignedTaskCount tasks still have no assigned staff profile.",
      );
    }
    if (phaseGaps.isNotEmpty) {
      lines.add(
        "${phaseGaps.length} phases are too thin for their allocated days and need more milestones.",
      );
    }
    return lines;
  }
}

class _DraftRefineDialogResult {
  final int maxAdditionalTasks;

  const _DraftRefineDialogResult({required this.maxAdditionalTasks});
}

enum _DraftBulkAssignScope { needsStaff, reassignAll }

enum _DraftBulkAssignMode { allIncludedStaff, preferTaskRole }

class _DraftBulkAssignDialogResult {
  final _DraftBulkAssignScope scope;
  final _DraftBulkAssignMode mode;
  final List<String> excludedRoleKeys;

  const _DraftBulkAssignDialogResult({
    required this.scope,
    required this.mode,
    required this.excludedRoleKeys,
  });
}

class _DraftBulkAssignOutcome {
  final ProductionPlanDraftState draft;
  final int changedTaskCount;
  final int tasksWithAssignments;
  final int tasksStillShort;
  final int eligibleStaffCount;

  const _DraftBulkAssignOutcome({
    required this.draft,
    required this.changedTaskCount,
    required this.tasksWithAssignments,
    required this.tasksStillShort,
    required this.eligibleStaffCount,
  });
}

class ProductionPlanDraftEditorScreen extends ConsumerStatefulWidget {
  final String? planId;

  const ProductionPlanDraftEditorScreen({super.key, this.planId});

  @override
  ConsumerState<ProductionPlanDraftEditorScreen> createState() =>
      _ProductionPlanDraftEditorScreenState();
}

class _ProductionPlanDraftEditorScreenState
    extends ConsumerState<ProductionPlanDraftEditorScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _plannedPlantingCtrl = TextEditingController();
  final TextEditingController _plannedPlantingUnitCtrl =
      TextEditingController();
  final TextEditingController _estimatedHarvestCtrl = TextEditingController();
  final TextEditingController _estimatedHarvestUnitCtrl =
      TextEditingController();

  bool _syncingControllers = false;
  bool _isSaving = false;
  bool _isRefiningDraft = false;
  bool _isDownloadingDraft = false;
  bool _isImportingDraftDocument = false;
  bool _isAssigningDraftStaff = false;
  String? _hydratedPlanId;
  _DraftEditorMobileSection _mobileSection = _DraftEditorMobileSection.tasks;
  String? _lastLoggedLayoutMode;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onTitleChanged);
    _notesCtrl.addListener(_onNotesChanged);
    _plannedPlantingCtrl.addListener(_onPlannedPlantingChanged);
    _plannedPlantingUnitCtrl.addListener(_onPlannedPlantingUnitChanged);
    _estimatedHarvestCtrl.addListener(_onEstimatedHarvestChanged);
    _estimatedHarvestUnitCtrl.addListener(_onEstimatedHarvestUnitChanged);
  }

  @override
  void didUpdateWidget(covariant ProductionPlanDraftEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.planId ?? "").trim() != (widget.planId ?? "").trim()) {
      _hydratedPlanId = null;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _plannedPlantingCtrl.dispose();
    _plannedPlantingUnitCtrl.dispose();
    _estimatedHarvestCtrl.dispose();
    _estimatedHarvestUnitCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _logLayoutDecision(String mode) {
    if (_lastLoggedLayoutMode == mode) {
      return;
    }
    _lastLoggedLayoutMode = mode;
    AppDebug.log(
      _draftEditorLogTag,
      _logLayoutMode,
      extra: <String, Object?>{_extraLayoutModeKey: mode},
    );
  }

  Future<bool> _confirmReturnToDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Return this plan to draft?"),
          content: const Text(
            "This stops the live production lifecycle and reopens the same plan in draft mode so you can edit the saved schedule directly.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Return to draft"),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  String _resolveDraftEditorErrorMessage(
    Object error, {
    required String fallback,
  }) {
    final dioError = error is DioException ? error : null;
    final responseData = dioError?.response?.data;
    final responseMap = responseData is Map<String, dynamic>
        ? responseData
        : const <String, dynamic>{};
    final backendError = (responseMap["error"] ?? responseMap["message"] ?? "")
        .toString()
        .trim();
    if (backendError.isNotEmpty) {
      return backendError;
    }
    final rawMessage = error.toString().trim();
    if (rawMessage.isNotEmpty && rawMessage != "Exception") {
      return rawMessage;
    }
    return fallback;
  }

  void _onTitleChanged() {
    if (_syncingControllers) {
      return;
    }
    ref.read(productionPlanDraftProvider.notifier).updateTitle(_titleCtrl.text);
  }

  void _onNotesChanged() {
    if (_syncingControllers) {
      return;
    }
    ref.read(productionPlanDraftProvider.notifier).updateNotes(_notesCtrl.text);
  }

  void _onPlannedPlantingChanged() {
    if (_syncingControllers) {
      return;
    }
    ref
        .read(productionPlanDraftProvider.notifier)
        .updatePlannedPlantingQuantity(
          _parseNullableDouble(_plannedPlantingCtrl.text),
        );
  }

  void _onPlannedPlantingUnitChanged() {
    if (_syncingControllers) {
      return;
    }
    ref
        .read(productionPlanDraftProvider.notifier)
        .updatePlannedPlantingUnit(_plannedPlantingUnitCtrl.text);
  }

  void _onEstimatedHarvestChanged() {
    if (_syncingControllers) {
      return;
    }
    ref
        .read(productionPlanDraftProvider.notifier)
        .updateEstimatedHarvestQuantity(
          _parseNullableDouble(_estimatedHarvestCtrl.text),
        );
  }

  void _onEstimatedHarvestUnitChanged() {
    if (_syncingControllers) {
      return;
    }
    ref
        .read(productionPlanDraftProvider.notifier)
        .updateEstimatedHarvestUnit(_estimatedHarvestUnitCtrl.text);
  }

  void _syncControllers(ProductionPlanDraftState draft) {
    _syncingControllers = true;
    _syncTextController(_titleCtrl, draft.title);
    _syncTextController(_notesCtrl, draft.notes);
    _syncTextController(
      _plannedPlantingCtrl,
      draft.plantingTargets.plannedPlantingQuantity == null
          ? ""
          : draft.plantingTargets.plannedPlantingQuantity.toString(),
    );
    _syncTextController(
      _plannedPlantingUnitCtrl,
      draft.plantingTargets.plannedPlantingUnit,
    );
    _syncTextController(
      _estimatedHarvestCtrl,
      draft.plantingTargets.estimatedHarvestQuantity == null
          ? ""
          : draft.plantingTargets.estimatedHarvestQuantity.toString(),
    );
    _syncTextController(
      _estimatedHarvestUnitCtrl,
      draft.plantingTargets.estimatedHarvestUnit,
    );
    _syncingControllers = false;
  }

  void _syncTextController(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _hydrateDraftFromDetail(ProductionPlanDetail detail) {
    final planId = detail.plan.id.trim();
    if (planId.isEmpty || _hydratedPlanId == planId) {
      return;
    }
    final nextDraft = _buildDraftStateFromDetail(detail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(productionPlanDraftProvider.notifier).applyDraft(nextDraft);
      _syncControllers(nextDraft);
      setState(() {
        _hydratedPlanId = planId;
      });
    });
  }

  ProductionPlanDraftState _buildDraftStateFromDetail(
    ProductionPlanDetail detail,
  ) {
    final tasksByPhaseId = <String, List<ProductionTask>>{};
    for (final task in detail.tasks) {
      tasksByPhaseId
          .putIfAbsent(task.phaseId, () => <ProductionTask>[])
          .add(task);
    }

    final phases = detail.phases.map((phase) {
      final phaseTasks = tasksByPhaseId[phase.id] ?? const <ProductionTask>[];
      return ProductionPhaseDraft(
        name: phase.name,
        order: phase.order,
        estimatedDays: _estimatePhaseDurationDays(phase),
        phaseType: phase.phaseType.trim().isEmpty ? "finite" : phase.phaseType,
        requiredUnits: phase.requiredUnits,
        minRatePerFarmerHour: phase.minRatePerFarmerHour <= 0
            ? 0.1
            : phase.minRatePerFarmerHour,
        targetRatePerFarmerHour: phase.targetRatePerFarmerHour <= 0
            ? 0.2
            : phase.targetRatePerFarmerHour,
        plannedHoursPerDay: phase.plannedHoursPerDay <= 0
            ? 3
            : phase.plannedHoursPerDay,
        biologicalMinDays: phase.biologicalMinDays,
        tasks: phaseTasks.map((task) {
          return ProductionTaskDraft(
            id: task.id,
            title: task.title,
            roleRequired: task.roleRequired,
            assignedStaffId: task.assignedStaffId.trim().isEmpty
                ? null
                : task.assignedStaffId,
            assignedStaffProfileIds: task.assignedStaffIds,
            requiredHeadcount: task.requiredHeadcount < 1
                ? 1
                : task.requiredHeadcount,
            weight: task.weight < 1 ? 1 : task.weight,
            scheduledStart: task.startDate,
            scheduledDue: task.dueDate,
            manualSortOrder: task.manualSortOrder,
            instructions: task.instructions,
            taskType: task.taskType,
            sourceTemplateKey: task.sourceTemplateKey,
            recurrenceGroupKey: task.recurrenceGroupKey,
            occurrenceIndex: task.occurrenceIndex,
            status: _taskStatusFromBackend(task.status),
            completedAt: task.completedAt,
            completedByStaffId: null,
          );
        }).toList(),
      );
    }).toList()..sort((a, b) => a.order.compareTo(b.order));

    final totalEstimatedDays = phases.fold<int>(
      0,
      (sum, phase) => sum + phase.estimatedDays,
    );
    final totalTasks = phases.fold<int>(
      0,
      (sum, phase) => sum + phase.tasks.length,
    );

    return ProductionPlanDraftState(
      title: detail.plan.title,
      notes: detail.plan.notes,
      domainContext: detail.plan.domainContext,
      estateAssetId: detail.plan.estateAssetId.trim().isEmpty
          ? null
          : detail.plan.estateAssetId,
      productId: detail.plan.productId.trim().isEmpty
          ? null
          : detail.plan.productId,
      startDate: detail.plan.startDate,
      endDate: detail.plan.endDate,
      plantingTargets: ProductionPlantingTargetsDraft(
        materialType: detail.plan.plantingTargets?.materialType ?? "",
        plannedPlantingQuantity:
            detail.plan.plantingTargets?.plannedPlantingQuantity,
        plannedPlantingUnit:
            detail.plan.plantingTargets?.plannedPlantingUnit ?? "",
        estimatedHarvestQuantity:
            detail.plan.plantingTargets?.estimatedHarvestQuantity,
        estimatedHarvestUnit:
            detail.plan.plantingTargets?.estimatedHarvestUnit ?? "",
      ),
      proposedProduct: null,
      productAiSuggested: false,
      startDateAiSuggested: false,
      endDateAiSuggested: false,
      aiGenerated: detail.plan.aiGenerated,
      totalTasks: totalTasks,
      totalEstimatedDays: totalEstimatedDays,
      riskNotes: const <String>[],
      phases: phases,
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final draft = ref.read(productionPlanDraftProvider);
    final initialDate =
        (isStart ? draft.startDate : draft.endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    final controller = ref.read(productionPlanDraftProvider.notifier);
    if (isStart) {
      controller.updateStartDate(picked);
    } else {
      controller.updateEndDate(picked);
    }
  }

  Future<bool> _confirmStartProduction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(_startProductionConfirmTitle),
          content: const Text(_startProductionConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(_startProductionConfirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<ProductionPlanDetail> _persistDraft({
    String? existingPlanStatus,
    bool showSuccessSnack = true,
    bool syncEditorRoute = true,
  }) async {
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final actions = ref.read(productionPlanActionsProvider);
    final planId = (widget.planId ?? "").trim();
    final normalizedStatus = (existingPlanStatus ?? "").trim().toLowerCase();
    final shouldUpdateExistingDraft =
        planId.isNotEmpty && normalizedStatus == "draft";
    final detail = shouldUpdateExistingDraft
        ? await actions.updateDraft(
            planId: planId,
            payload: controller.toPayload(),
          )
        : await actions.saveDraft(payload: controller.toPayload());
    if (!mounted) {
      return detail;
    }
    final resolvedPlanId = detail.plan.id.trim();
    final createdDraftCopy = planId.isNotEmpty && !shouldUpdateExistingDraft;
    if (showSuccessSnack) {
      _showSnack(
        createdDraftCopy
            ? "Draft copy saved."
            : planId.isEmpty
            ? "Draft saved."
            : "Draft updated.",
      );
    }
    AppDebug.log(
      _draftEditorLogTag,
      _logSaveDraftSuccess,
      extra: <String, Object?>{
        _extraPlanIdKey: resolvedPlanId,
        _extraDraftStatusKey: normalizedStatus,
      },
    );
    ref.invalidate(productionPlanDetailProvider(resolvedPlanId));
    if (planId != resolvedPlanId) {
      if (syncEditorRoute) {
        context.go(productionPlanDraftStudioPath(planId: resolvedPlanId));
      } else {
        _hydratedPlanId = null;
      }
    } else {
      _hydratedPlanId = null;
    }
    return detail;
  }

  Future<void> _saveDraft({String? existingPlanStatus}) async {
    if (_isSaving) {
      return;
    }
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final errors = controller.validate();
    if (errors.isNotEmpty) {
      _showSnack(errors.first);
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final planId = (widget.planId ?? "").trim();
      final normalizedStatus = (existingPlanStatus ?? "").trim().toLowerCase();
      AppDebug.log(
        _draftEditorLogTag,
        _logSaveDraftStart,
        extra: <String, Object?>{
          _extraPlanIdKey: planId,
          _extraDraftStatusKey: normalizedStatus,
        },
      );
      await _persistDraft(existingPlanStatus: existingPlanStatus);
    } catch (error) {
      AppDebug.log(
        _draftEditorLogTag,
        _logSaveDraftFailure,
        extra: <String, Object?>{
          _extraPlanIdKey: (widget.planId ?? "").trim(),
          "error": error.toString(),
        },
      );
      _showSnack(
        _resolveDraftEditorErrorMessage(
          error,
          fallback: "Unable to save draft.",
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _startProduction({String? existingPlanStatus}) async {
    if (_isSaving) {
      return;
    }
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final errors = controller.validate();
    if (errors.isNotEmpty) {
      _showSnack(errors.first);
      return;
    }
    final confirmed = await _confirmStartProduction();
    if (!confirmed) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    String resolvedPlanId = "";
    try {
      AppDebug.log(
        _draftEditorLogTag,
        _logStartProductionStart,
        extra: <String, Object?>{
          _extraPlanIdKey: (widget.planId ?? "").trim(),
          _extraDraftStatusKey: (existingPlanStatus ?? "").trim().toLowerCase(),
        },
      );
      final detail = await _persistDraft(
        existingPlanStatus: existingPlanStatus,
        showSuccessSnack: false,
        syncEditorRoute: false,
      );
      resolvedPlanId = detail.plan.id.trim();
      await ref
          .read(productionPlanActionsProvider)
          .updatePlanStatus(planId: resolvedPlanId, status: "active");
      if (!mounted) {
        return;
      }
      AppDebug.log(
        _draftEditorLogTag,
        _logStartProductionSuccess,
        extra: <String, Object?>{_extraPlanIdKey: resolvedPlanId},
      );
      _showSnack("Production started.");
      context.go(productionPlanDetailPath(resolvedPlanId));
    } catch (error) {
      AppDebug.log(
        _draftEditorLogTag,
        _logStartProductionFailure,
        extra: <String, Object?>{
          _extraPlanIdKey: resolvedPlanId.isEmpty
              ? (widget.planId ?? "").trim()
              : resolvedPlanId,
          "error": error.toString(),
        },
      );
      if (!mounted) {
        return;
      }
      if (resolvedPlanId.isNotEmpty &&
          (widget.planId ?? "").trim() != resolvedPlanId) {
        context.go(productionPlanDraftStudioPath(planId: resolvedPlanId));
      } else {
        _showSnack(
          _resolveDraftEditorErrorMessage(
            error,
            fallback: "Unable to start production.",
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _returnPlanToDraft() async {
    final planId = (widget.planId ?? "").trim();
    if (planId.isEmpty || _isSaving) {
      return;
    }
    final confirmed = await _confirmReturnToDraft();
    if (!confirmed) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      AppDebug.log(
        _draftEditorLogTag,
        _logReturnToDraftStart,
        extra: <String, Object?>{_extraPlanIdKey: planId},
      );
      await ref
          .read(productionPlanActionsProvider)
          .updatePlanStatus(planId: planId, status: "draft");
      if (!mounted) {
        return;
      }
      setState(() {
        _hydratedPlanId = null;
      });
      ref.invalidate(productionPlanDetailProvider(planId));
      AppDebug.log(
        _draftEditorLogTag,
        _logReturnToDraftSuccess,
        extra: <String, Object?>{_extraPlanIdKey: planId},
      );
      _showSnack("Production plan returned to draft.");
    } catch (error) {
      AppDebug.log(
        _draftEditorLogTag,
        _logReturnToDraftFailure,
        extra: <String, Object?>{
          _extraPlanIdKey: planId,
          "error": error.toString(),
        },
      );
      _showSnack(
        _resolveDraftEditorErrorMessage(
          error,
          fallback: "Unable to return the plan to draft.",
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _resolveDraftProductName(
    ProductionPlanDraftState draft, {
    String fallback = "",
  }) {
    final normalizedFallback = fallback.trim();
    if (normalizedFallback.isNotEmpty &&
        normalizedFallback.toLowerCase() != "linked product") {
      return normalizedFallback;
    }
    final fromTitle = draft.title
        .trim()
        .replaceAll(RegExp(r"\s+plan$", caseSensitive: false), "")
        .trim();
    if (fromTitle.isNotEmpty) {
      return fromTitle;
    }
    return (draft.productId ?? "").trim().isEmpty ? "" : "Linked product";
  }

  int _inferTotalWorkUnits(ProductionPlanDraftState draft) {
    var inferredUnits = 0;
    for (final phase in draft.phases) {
      if (phase.requiredUnits > inferredUnits) {
        inferredUnits = phase.requiredUnits;
      }
    }
    if (inferredUnits > 0) {
      return inferredUnits;
    }
    if (draft.totalTasks > 0) {
      return draft.totalTasks;
    }
    return draft.phases.isEmpty ? 1 : draft.phases.length;
  }

  int _inferMaxStaffPerUnit(ProductionPlanDraftState draft) {
    var maxHeadcount = 1;
    for (final phase in draft.phases) {
      for (final task in phase.tasks) {
        if (task.requiredHeadcount > maxHeadcount) {
          maxHeadcount = task.requiredHeadcount;
        }
      }
    }
    return maxHeadcount;
  }

  String _defaultWorkUnitLabelForDomain(String rawDomain) {
    switch (normalizeProductionDomainContext(rawDomain)) {
      case productionDomainFarm:
        return "plot";
      case productionDomainManufacturing:
        return "batch";
      case productionDomainConstruction:
        return "zone";
      case productionDomainMedia:
        return "shoot block";
      case productionDomainFood:
        return "batch";
      case productionDomainCosmetics:
        return "batch";
      case productionDomainFashion:
        return "line";
      case productionDomainCustom:
      default:
        return "work unit";
    }
  }

  _DraftWorkScopeSummary _resolveDraftWorkScopeSummary({
    required ProductionPlanDraftState draft,
    ProductionPlanDetail? detail,
    ProductionPlanUnitsResponse? planUnitsResponse,
  }) {
    final planUnits = planUnitsResponse?.units ?? const <ProductionPlanUnit>[];
    final canonicalUnitCount = (planUnitsResponse?.totalUnits ?? 0) > 0
        ? planUnitsResponse!.totalUnits
        : planUnits.length;
    final workloadContext = detail?.plan.workloadContext;
    final workloadUnitCount = workloadContext?.totalWorkUnits ?? 0;
    final fallbackWorkUnitLabel =
        workloadContext?.resolvedWorkUnitLabel.isNotEmpty == true
        ? workloadContext!.resolvedWorkUnitLabel
        : _defaultWorkUnitLabelForDomain(draft.domainContext);
    final inferredUnitStem = _inferDraftWorkUnitStemFromContext(
      fallbackWorkUnitLabel: fallbackWorkUnitLabel,
      contextText: [
        detail?.plan.title ?? "",
        detail?.plan.notes ?? "",
        draft.title,
        draft.notes,
      ].join(" "),
    );
    final unitStems =
        planUnits
            .map((unit) => _extractDraftWorkUnitStem(unit.label))
            .where((stem) => stem.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final resolvedUnitLabel = unitStems.length == 1
        ? unitStems.first
        : inferredUnitStem.isNotEmpty
        ? inferredUnitStem
        : _extractDraftWorkUnitStem(fallbackWorkUnitLabel).isNotEmpty
        ? _extractDraftWorkUnitStem(fallbackWorkUnitLabel)
        : _defaultWorkUnitLabelForDomain(draft.domainContext);
    final resolvedTotalUnits = canonicalUnitCount > 0
        ? canonicalUnitCount
        : workloadUnitCount > 0
        ? workloadUnitCount
        : _inferTotalWorkUnits(draft);

    return _DraftWorkScopeSummary(
      totalUnits: resolvedTotalUnits < 1 ? 1 : resolvedTotalUnits,
      singularLabel: resolvedUnitLabel,
      isEstimated: canonicalUnitCount <= 0 && workloadUnitCount <= 0,
    );
  }

  String _normalizeDraftAssignmentRole(String rawRole) {
    return rawRole
        .trim()
        .toLowerCase()
        .replaceAll("-", "_")
        .replaceAll(" ", "_");
  }

  List<String> _normalizeDraftAssignedIds(List<String> ids) {
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  bool _hasSameDraftAssignedIds(List<String> first, List<String> second) {
    final normalizedFirst = _normalizeDraftAssignedIds(first);
    final normalizedSecond = _normalizeDraftAssignedIds(second);
    if (normalizedFirst.length != normalizedSecond.length) {
      return false;
    }
    for (var index = 0; index < normalizedFirst.length; index += 1) {
      if (normalizedFirst[index] != normalizedSecond[index]) {
        return false;
      }
    }
    return true;
  }

  String _draftBulkAssignableStaffLabel(BusinessStaffProfileSummary profile) {
    return _resolveStaffDisplayName(profile, profile.id.trim());
  }

  List<BusinessStaffProfileSummary> _buildDraftAssignableStaffPool({
    required ProductionPlanDraftState draft,
    required List<BusinessStaffProfileSummary> staffList,
    required Set<String> excludedRoleKeys,
  }) {
    final normalizedExcludedRoles = excludedRoleKeys
        .map(_normalizeDraftAssignmentRole)
        .where((role) => role.isNotEmpty)
        .toSet();
    final draftEstateId = (draft.estateAssetId ?? "").trim();
    final filtered = staffList.where((profile) {
      final profileId = profile.id.trim();
      if (profileId.isEmpty) {
        return false;
      }
      final normalizedStatus = profile.status.trim().toLowerCase();
      if (normalizedStatus != "active") {
        return false;
      }
      final normalizedRole = _normalizeDraftAssignmentRole(profile.staffRole);
      if (normalizedRole.isEmpty ||
          normalizedExcludedRoles.contains(normalizedRole)) {
        return false;
      }
      final staffEstateId = (profile.estateAssetId ?? "").trim();
      if (draftEstateId.isNotEmpty &&
          staffEstateId.isNotEmpty &&
          staffEstateId != draftEstateId) {
        return false;
      }
      return true;
    }).toList();
    filtered.sort((left, right) {
      final roleCompare = _normalizeDraftAssignmentRole(
        left.staffRole,
      ).compareTo(_normalizeDraftAssignmentRole(right.staffRole));
      if (roleCompare != 0) {
        return roleCompare;
      }
      return _draftBulkAssignableStaffLabel(
        left,
      ).compareTo(_draftBulkAssignableStaffLabel(right));
    });
    return filtered;
  }

  Map<String, List<String>> _buildDraftAssignableStaffIdsByRole(
    List<BusinessStaffProfileSummary> staffList,
  ) {
    final grouped = <String, List<String>>{};
    for (final profile in staffList) {
      final roleKey = _normalizeDraftAssignmentRole(profile.staffRole);
      final profileId = profile.id.trim();
      if (roleKey.isEmpty || profileId.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(roleKey, () => <String>[]).add(profileId);
    }
    return grouped;
  }

  List<String> _takeDraftAssignmentFromPool({
    required List<String> currentAssignedIds,
    required List<String> pool,
    required int targetCount,
    required Map<String, int> cursorByPoolKey,
    required String poolKey,
  }) {
    if (pool.isEmpty || currentAssignedIds.length >= targetCount) {
      return currentAssignedIds;
    }
    final nextAssigned = List<String>.from(currentAssignedIds);
    final safePool = _normalizeDraftAssignedIds(pool);
    if (safePool.isEmpty) {
      return nextAssigned;
    }
    final startIndex = cursorByPoolKey[poolKey] ?? 0;
    var offset = 0;
    var visited = 0;
    while (visited < safePool.length && nextAssigned.length < targetCount) {
      final candidate = safePool[(startIndex + offset) % safePool.length];
      offset += 1;
      visited += 1;
      if (nextAssigned.contains(candidate)) {
        continue;
      }
      nextAssigned.add(candidate);
    }
    cursorByPoolKey[poolKey] = (startIndex + offset) % safePool.length;
    return nextAssigned;
  }

  _DraftBulkAssignOutcome _buildBulkAssignedDraft({
    required ProductionPlanDraftState draft,
    required List<BusinessStaffProfileSummary> eligibleStaff,
    required _DraftBulkAssignScope scope,
    required _DraftBulkAssignMode mode,
  }) {
    final eligibleStaffIds = eligibleStaff
        .map((profile) => profile.id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final eligibleStaffIdSet = eligibleStaffIds.toSet();
    final eligibleStaffIdsByRole = _buildDraftAssignableStaffIdsByRole(
      eligibleStaff,
    );
    final cursorByPoolKey = <String, int>{};
    var changedTaskCount = 0;
    var tasksWithAssignments = 0;
    var tasksStillShort = 0;

    final nextPhases = draft.phases.map((phase) {
      final nextTasks = phase.tasks.map((task) {
        final targetHeadcount = task.requiredHeadcount < 1
            ? 1
            : task.requiredHeadcount;
        final keptAssignedIds = scope == _DraftBulkAssignScope.reassignAll
            ? <String>[]
            : _normalizeDraftAssignedIds(
                task.assignedStaffProfileIds
                    .where((id) => eligibleStaffIdSet.contains(id.trim()))
                    .toList(),
              );
        final roleKey = _normalizeDraftAssignmentRole(task.roleRequired);
        var nextAssignedIds = keptAssignedIds;
        if (mode == _DraftBulkAssignMode.preferTaskRole && roleKey.isNotEmpty) {
          nextAssignedIds = _takeDraftAssignmentFromPool(
            currentAssignedIds: nextAssignedIds,
            pool: eligibleStaffIdsByRole[roleKey] ?? const <String>[],
            targetCount: targetHeadcount,
            cursorByPoolKey: cursorByPoolKey,
            poolKey: "role:$roleKey",
          );
        }
        nextAssignedIds = _takeDraftAssignmentFromPool(
          currentAssignedIds: nextAssignedIds,
          pool: eligibleStaffIds,
          targetCount: targetHeadcount,
          cursorByPoolKey: cursorByPoolKey,
          poolKey: "all",
        );

        if (nextAssignedIds.isNotEmpty) {
          tasksWithAssignments += 1;
        }
        if (nextAssignedIds.length < targetHeadcount) {
          tasksStillShort += 1;
        }

        final nextHeadcount = targetHeadcount < nextAssignedIds.length
            ? nextAssignedIds.length
            : targetHeadcount;
        if (_hasSameDraftAssignedIds(
              task.assignedStaffProfileIds,
              nextAssignedIds,
            ) &&
            task.requiredHeadcount == nextHeadcount) {
          return task;
        }
        changedTaskCount += 1;
        return task.copyWith(
          assignedStaffId: nextAssignedIds.isEmpty
              ? null
              : nextAssignedIds.first,
          assignedStaffProfileIds: nextAssignedIds,
          requiredHeadcount: nextHeadcount,
        );
      }).toList();
      return phase.copyWith(tasks: nextTasks);
    }).toList();

    return _DraftBulkAssignOutcome(
      draft: draft.copyWith(phases: nextPhases),
      changedTaskCount: changedTaskCount,
      tasksWithAssignments: tasksWithAssignments,
      tasksStillShort: tasksStillShort,
      eligibleStaffCount: eligibleStaff.length,
    );
  }

  Future<_DraftBulkAssignDialogResult?> _showBulkAssignStaffDialog({
    required ProductionPlanDraftState draft,
    required List<BusinessStaffProfileSummary> staffList,
  }) async {
    final availableStaff = _buildDraftAssignableStaffPool(
      draft: draft,
      staffList: staffList,
      excludedRoleKeys: const <String>{},
    );
    final roleCounts = <String, int>{};
    for (final profile in availableStaff) {
      final roleKey = _normalizeDraftAssignmentRole(profile.staffRole);
      roleCounts[roleKey] = (roleCounts[roleKey] ?? 0) + 1;
    }
    final orderedRoleKeys = roleCounts.keys.toList()
      ..sort((left, right) {
        final countCompare = (roleCounts[right] ?? 0).compareTo(
          roleCounts[left] ?? 0,
        );
        if (countCompare != 0) {
          return countCompare;
        }
        return formatStaffRoleLabel(
          left,
        ).compareTo(formatStaffRoleLabel(right));
      });
    if (orderedRoleKeys.isEmpty) {
      _showSnack("No active staff are available for this draft yet.");
      return null;
    }

    var selectedScope = _DraftBulkAssignScope.needsStaff;
    var selectedMode = _DraftBulkAssignMode.allIncludedStaff;
    final excludedRoles = <String>{};

    return showDialog<_DraftBulkAssignDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final includedRoleCount =
                orderedRoleKeys.length - excludedRoles.length;
            final includedStaffCount = orderedRoleKeys.fold<int>(0, (
              sum,
              roleKey,
            ) {
              if (excludedRoles.contains(roleKey)) {
                return sum;
              }
              return sum + (roleCounts[roleKey] ?? 0);
            });
            return AlertDialog(
              title: const Text("Assign staff to draft"),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Build one shared assignment pool for this draft. Farm work can pull from any included active role, so exclude only the roles you do not want used here.",
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          Chip(
                            avatar: const Icon(
                              Icons.groups_2_outlined,
                              size: 18,
                            ),
                            label: Text("$includedStaffCount staff included"),
                          ),
                          Chip(
                            avatar: const Icon(Icons.badge_outlined, size: 18),
                            label: Text("$includedRoleCount roles included"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Assignment scope",
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<_DraftBulkAssignScope>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<_DraftBulkAssignScope>(
                            value: _DraftBulkAssignScope.needsStaff,
                            label: Text("Needs staff"),
                            icon: Icon(Icons.person_add_alt_1_outlined),
                          ),
                          ButtonSegment<_DraftBulkAssignScope>(
                            value: _DraftBulkAssignScope.reassignAll,
                            label: Text("Reassign all"),
                            icon: Icon(Icons.restart_alt_outlined),
                          ),
                        ],
                        selected: <_DraftBulkAssignScope>{selectedScope},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) {
                            return;
                          }
                          setDialogState(() {
                            selectedScope = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Assignment mode",
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<_DraftBulkAssignMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<_DraftBulkAssignMode>(
                            value: _DraftBulkAssignMode.allIncludedStaff,
                            label: Text("All included roles"),
                            icon: Icon(Icons.shuffle_outlined),
                          ),
                          ButtonSegment<_DraftBulkAssignMode>(
                            value: _DraftBulkAssignMode.preferTaskRole,
                            label: Text("Prefer task role"),
                            icon: Icon(Icons.rule_folder_outlined),
                          ),
                        ],
                        selected: <_DraftBulkAssignMode>{selectedMode},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) {
                            return;
                          }
                          setDialogState(() {
                            selectedMode = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            "Included roles",
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                excludedRoles.clear();
                              });
                            },
                            child: const Text("Include all"),
                          ),
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                excludedRoles
                                  ..clear()
                                  ..addAll(_draftAssignmentManagementRoles);
                              });
                            },
                            child: const Text("Exclude management"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: orderedRoleKeys.map((roleKey) {
                          final isIncluded = !excludedRoles.contains(roleKey);
                          return FilterChip(
                            selected: isIncluded,
                            label: Text(
                              "${formatStaffRoleLabel(roleKey)} · ${roleCounts[roleKey] ?? 0}",
                            ),
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  excludedRoles.remove(roleKey);
                                } else {
                                  excludedRoles.add(roleKey);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (includedStaffCount <= 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          "Include at least one role before applying assignments.",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text("Cancel"),
                ),
                FilledButton.icon(
                  onPressed: includedStaffCount <= 0
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(
                            _DraftBulkAssignDialogResult(
                              scope: selectedScope,
                              mode: selectedMode,
                              excludedRoleKeys: excludedRoles.toList()..sort(),
                            ),
                          );
                        },
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text("Assign staff"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _assignDraftStaff({
    required ProductionPlanDraftState draft,
    required List<BusinessStaffProfileSummary> staffList,
  }) async {
    if (_isSaving ||
        _isRefiningDraft ||
        _isImportingDraftDocument ||
        _isDownloadingDraft ||
        _isAssigningDraftStaff) {
      return;
    }
    final hasDraftTasks = draft.phases.any((phase) => phase.tasks.isNotEmpty);
    if (!hasDraftTasks) {
      _showSnack("Add or generate draft tasks before assigning staff.");
      return;
    }
    final config = await _showBulkAssignStaffDialog(
      draft: draft,
      staffList: staffList,
    );
    if (config == null) {
      return;
    }

    setState(() {
      _isAssigningDraftStaff = true;
    });

    try {
      final eligibleStaff = _buildDraftAssignableStaffPool(
        draft: draft,
        staffList: staffList,
        excludedRoleKeys: config.excludedRoleKeys.toSet(),
      );
      if (eligibleStaff.isEmpty) {
        _showSnack("No active staff remain after those role exclusions.");
        return;
      }
      final outcome = _buildBulkAssignedDraft(
        draft: draft,
        eligibleStaff: eligibleStaff,
        scope: config.scope,
        mode: config.mode,
      );
      if (outcome.changedTaskCount <= 0) {
        _showSnack("No task assignments changed.");
        return;
      }
      ref.read(productionPlanDraftProvider.notifier).applyDraft(outcome.draft);
      _syncControllers(outcome.draft);
      if (outcome.tasksStillShort > 0) {
        _showSnack(
          "Assigned staff across ${outcome.changedTaskCount} tasks using ${outcome.eligibleStaffCount} active staff. ${outcome.tasksStillShort} tasks still need more people.",
        );
      } else {
        _showSnack(
          "Assigned staff across ${outcome.changedTaskCount} tasks using ${outcome.eligibleStaffCount} active staff.",
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAssigningDraftStaff = false;
        });
      } else {
        _isAssigningDraftStaff = false;
      }
    }
  }

  DateTime? _normalizeDraftDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    final localValue = value.isUtc ? value.toLocal() : value;
    return DateTime(localValue.year, localValue.month, localValue.day);
  }

  int _resolveDraftProjectTotalDays(ProductionPlanDraftState draft) {
    final startDate = _normalizeDraftDate(draft.startDate);
    final endDate = _normalizeDraftDate(draft.endDate);
    final summedPhaseDays = draft.phases.fold<int>(
      0,
      (sum, phase) => sum + (phase.estimatedDays < 1 ? 1 : phase.estimatedDays),
    );
    if (startDate != null && endDate != null) {
      final safeEndDate = endDate.isBefore(startDate) ? startDate : endDate;
      final inclusiveDateDays = safeEndDate.difference(startDate).inDays + 1;
      return math.max(
        inclusiveDateDays,
        math.max(
          summedPhaseDays,
          draft.totalEstimatedDays > 0 ? draft.totalEstimatedDays : 1,
        ),
      );
    }
    if (summedPhaseDays > 0) {
      return summedPhaseDays;
    }
    return draft.totalEstimatedDays > 0 ? draft.totalEstimatedDays : 1;
  }

  List<int> _buildNormalizedPhaseDayAllocations(
    ProductionPlanDraftState draft,
  ) {
    if (draft.phases.isEmpty) {
      return const <int>[];
    }
    final safeTotalProjectDays = _resolveDraftProjectTotalDays(draft);
    final minimumPhaseCoverage = draft.phases.length;
    final totalProjectDays = safeTotalProjectDays < minimumPhaseCoverage
        ? minimumPhaseCoverage
        : safeTotalProjectDays;
    final safeEstimatedDays = draft.phases
        .map((phase) => phase.estimatedDays < 1 ? 1 : phase.estimatedDays)
        .toList();
    var remainingActualDays = totalProjectDays;
    var remainingEstimatedDays = safeEstimatedDays.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final allocations = <int>[];

    for (var index = 0; index < draft.phases.length; index += 1) {
      final isLastPhase = index == draft.phases.length - 1;
      final safeEstimated = safeEstimatedDays[index];
      int allocatedDays;
      if (isLastPhase) {
        allocatedDays = remainingActualDays < 1 ? 1 : remainingActualDays;
      } else {
        allocatedDays =
            ((remainingActualDays * safeEstimated) / remainingEstimatedDays)
                .round();
        final remainingPhases = draft.phases.length - index - 1;
        final maxForPhase = remainingActualDays - remainingPhases;
        final safeMaxForPhase = maxForPhase < 1 ? 1 : maxForPhase;
        if (allocatedDays < 1) {
          allocatedDays = 1;
        }
        if (allocatedDays > safeMaxForPhase) {
          allocatedDays = safeMaxForPhase;
        }
      }
      allocations.add(allocatedDays);
      remainingActualDays -= allocatedDays;
      remainingEstimatedDays -= safeEstimated;
    }

    return allocations;
  }

  ProductionPlanDraftState _alignDraftPhaseDaysToProjectWindow(
    ProductionPlanDraftState draft,
  ) {
    final allocations = _buildNormalizedPhaseDayAllocations(draft);
    if (allocations.isEmpty) {
      return draft.copyWith(
        totalTasks: draft.phases.fold<int>(
          0,
          (sum, phase) => sum + phase.tasks.length,
        ),
        totalEstimatedDays: _resolveDraftProjectTotalDays(draft),
      );
    }
    final normalizedPhases = draft.phases.asMap().entries.map((entry) {
      final index = entry.key;
      final phase = entry.value;
      return phase.copyWith(estimatedDays: allocations[index]);
    }).toList();
    final totalTasks = normalizedPhases.fold<int>(
      0,
      (sum, phase) => sum + phase.tasks.length,
    );
    final totalEstimatedDays = allocations.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    return draft.copyWith(
      phases: normalizedPhases,
      totalTasks: totalTasks,
      totalEstimatedDays: totalEstimatedDays,
    );
  }

  List<_DraftExportPhaseWindow> _buildDraftExportPhaseWindows(
    ProductionPlanDraftState draft,
  ) {
    if (draft.phases.isEmpty) {
      return const <_DraftExportPhaseWindow>[];
    }
    final allocations = _buildNormalizedPhaseDayAllocations(draft);
    final startDate = _normalizeDraftDate(draft.startDate);
    final windows = <_DraftExportPhaseWindow>[];
    var projectDayCursor = 1;
    var dateCursor = startDate;

    for (var index = 0; index < draft.phases.length; index += 1) {
      final phase = draft.phases[index];
      final allocatedDays = index < allocations.length ? allocations[index] : 1;
      final phaseStart = dateCursor;
      final phaseEnd = phaseStart?.add(Duration(days: allocatedDays - 1));
      windows.add(
        _DraftExportPhaseWindow(
          phaseIndex: index,
          phase: phase,
          startDate: phaseStart,
          endDate: phaseEnd,
          allocatedDays: allocatedDays,
          projectDayStart: projectDayCursor,
          projectDayEnd: projectDayCursor + allocatedDays - 1,
        ),
      );
      projectDayCursor += allocatedDays;
      if (phaseEnd != null) {
        dateCursor = phaseEnd.add(const Duration(days: 1));
      }
    }

    return windows;
  }

  List<_DraftExportPhaseDay> _buildDraftExportPhaseDays(
    _DraftExportPhaseWindow phaseWindow,
  ) {
    final allocatedDays = phaseWindow.allocatedDays < 1
        ? 1
        : phaseWindow.allocatedDays;
    final tasksByDay = List<List<ProductionTaskDraft>>.generate(
      allocatedDays,
      (_) => <ProductionTaskDraft>[],
    );
    final tasks = phaseWindow.phase.tasks;
    if (tasks.isNotEmpty) {
      final denominator = tasks.length <= 1 ? 1 : tasks.length - 1;
      for (var taskIndex = 0; taskIndex < tasks.length; taskIndex += 1) {
        final dayIndex = allocatedDays == 1
            ? 0
            : (((taskIndex * (allocatedDays - 1)) / denominator).round()).clamp(
                0,
                allocatedDays - 1,
              );
        tasksByDay[dayIndex].add(tasks[taskIndex]);
      }
    }

    return List<_DraftExportPhaseDay>.generate(allocatedDays, (dayIndex) {
      final date = phaseWindow.startDate?.add(Duration(days: dayIndex));
      return _DraftExportPhaseDay(
        date: date,
        projectDayNumber: phaseWindow.projectDayStart + dayIndex,
        phaseDayNumber: dayIndex + 1,
        tasks: tasksByDay[dayIndex],
      );
    });
  }

  String _buildDraftAssignedLabel(
    List<String> assignedIds,
    Map<String, BusinessStaffProfileSummary> staffById,
  ) {
    final normalizedIds = assignedIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (normalizedIds.isEmpty) {
      return "Unassigned";
    }
    return normalizedIds
        .map((id) {
          final profile = staffById[id];
          final name = (profile?.userName ?? "").trim();
          if (name.isNotEmpty) {
            return name;
          }
          final email = (profile?.userEmail ?? "").trim();
          if (email.isNotEmpty) {
            return email;
          }
          return id;
        })
        .join(", ");
  }

  List<String> _collectDistinctDraftRoles(ProductionPlanDraftState draft) {
    final roles = <String>{};
    for (final phase in draft.phases) {
      for (final task in phase.tasks) {
        final role = task.roleRequired.trim();
        if (role.isNotEmpty) {
          roles.add(role);
        }
      }
    }
    return roles.toList()..sort();
  }

  List<BusinessStaffProfileSummary> _collectAssignedStaffProfiles(
    ProductionPlanDraftState draft,
    Map<String, BusinessStaffProfileSummary> staffById,
  ) {
    final assignedIds = <String>{};
    for (final phase in draft.phases) {
      for (final task in phase.tasks) {
        for (final assignedId in task.assignedStaffProfileIds) {
          final normalizedId = assignedId.trim();
          if (normalizedId.isNotEmpty) {
            assignedIds.add(normalizedId);
          }
        }
      }
    }
    return assignedIds
        .map((id) => staffById[id])
        .whereType<BusinessStaffProfileSummary>()
        .toList()
      ..sort((left, right) => left.id.compareTo(right.id));
  }

  List<Map<String, String>> _buildFocusedStaffProfilesPayload(
    List<BusinessStaffProfileSummary> profiles,
  ) {
    return profiles
        .map((profile) {
          final role = profile.staffRole.trim();
          if (profile.id.trim().isEmpty || role.isEmpty) {
            return const <String, String>{};
          }
          final displayName = (profile.userName ?? "").trim().isNotEmpty
              ? (profile.userName ?? "").trim()
              : (profile.userEmail ?? "").trim();
          return <String, String>{
            "profileId": profile.id.trim(),
            "role": role,
            "name": displayName,
          };
        })
        .where((row) => row.isNotEmpty)
        .toList();
  }

  Map<String, List<String>> _buildFocusedStaffByRolePayload(
    List<Map<String, String>> rows,
  ) {
    final grouped = <String, Set<String>>{};
    for (final row in rows) {
      final role = (row["role"] ?? "").trim();
      final profileId = (row["profileId"] ?? "").trim();
      if (role.isEmpty || profileId.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(role, () => <String>{}).add(profileId);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: entry.value.toList()..sort(),
    };
  }

  String _resolveStaffDisplayName(
    BusinessStaffProfileSummary? profile,
    String fallback,
  ) {
    final name = (profile?.userName ?? "").trim();
    if (name.isNotEmpty) {
      return name;
    }
    final email = (profile?.userEmail ?? "").trim();
    if (email.isNotEmpty) {
      return email;
    }
    return fallback;
  }

  String _normalizeDraftRefineKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), "_")
        .replaceAll(RegExp(r"_+"), "_")
        .replaceAll(RegExp(r"^_+|_+$"), "");
  }

  bool _isGenericDraftTaskTitle(String rawTitle) {
    final normalized = _normalizeDraftRefineKey(rawTitle);
    const genericKeys = <String>{
      "",
      "task",
      "phase_execution",
      "phase_monitoring",
      "phase_work",
      "execution",
      "monitoring",
      "general_task",
      "field_work",
      "field_check",
      "field_upkeep",
      "crop_health_check",
    };
    return genericKeys.contains(normalized) ||
        normalized.startsWith("phase_execution") ||
        normalized.startsWith("phase_monitoring");
  }

  _DraftRefineGapReport _buildDraftRefineGapReport(
    ProductionPlanDraftState draft,
  ) {
    final alignedDraft = _alignDraftPhaseDaysToProjectWindow(draft);
    final phaseWindows = _buildDraftExportPhaseWindows(alignedDraft);
    final totalProjectDays = _resolveDraftProjectTotalDays(alignedDraft);
    final allTasks = <ProductionTaskDraft>[
      for (final phase in alignedDraft.phases) ...phase.tasks,
    ];
    final totalTaskCount = allTasks.length;
    final genericTaskCount = allTasks
        .where((task) => _isGenericDraftTaskTitle(task.title))
        .length;
    final missingInstructionCount = allTasks
        .where((task) => task.instructions.trim().isEmpty)
        .length;
    final unassignedTaskCount = allTasks
        .where((task) => task.assignedStaffProfileIds.isEmpty)
        .length;
    final phaseGaps =
        phaseWindows
            .map((window) {
              final taskCount = window.phase.tasks.length;
              final allocatedDays = math.max(1, window.allocatedDays);
              final suggestedTaskCount = math.max(
                2,
                math.min(allocatedDays, (allocatedDays * 0.85).ceil()),
              );
              return _DraftRefinePhaseGap(
                phaseName: window.phase.name.trim().isEmpty
                    ? "Phase ${window.phase.order}"
                    : window.phase.name.trim(),
                allocatedDays: allocatedDays,
                currentTaskCount: taskCount,
                suggestedTaskCount: suggestedTaskCount,
              );
            })
            .where((gap) => gap.missingTaskCount > 0)
            .toList()
          ..sort(
            (left, right) =>
                right.missingTaskCount.compareTo(left.missingTaskCount),
          );
    final suggestedTaskCount =
        totalTaskCount +
        phaseGaps.fold<int>(0, (sum, gap) => sum + gap.missingTaskCount);

    return _DraftRefineGapReport(
      totalProjectDays: totalProjectDays,
      totalTaskCount: totalTaskCount,
      suggestedTaskCount: suggestedTaskCount,
      genericTaskCount: genericTaskCount,
      missingInstructionCount: missingInstructionCount,
      unassignedTaskCount: unassignedTaskCount,
      phaseGaps: phaseGaps,
    );
  }

  List<int> _buildRefineTaskAllowanceOptions(_DraftRefineGapReport report) {
    final suggested = report.suggestedAdditionalTaskCount;
    final values = <int>{
      0,
      math.max(4, suggested ~/ 3),
      math.max(8, suggested ~/ 2),
      suggested,
      suggested + 10,
      suggested + 25,
    }..removeWhere((value) => value < 0 || value > 180);
    if (values.length == 1) {
      values.addAll(const <int>{6, 12, 24});
    }
    final ordered = values.toList()..sort();
    return ordered;
  }

  Future<_DraftRefineDialogResult?> _showDraftRefineDialog({
    required _DraftRefineGapReport report,
    required String estateName,
    required String productName,
  }) async {
    final options = _buildRefineTaskAllowanceOptions(report);
    var selectedAllowance = report.suggestedAdditionalTaskCount;
    if (!options.contains(selectedAllowance)) {
      selectedAllowance = options.first;
    }

    return showDialog<_DraftRefineDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Review AI refine scope"),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "AI will inspect the saved draft for ${productName.trim().isEmpty ? 'this crop' : productName.trim()} at ${estateName.trim().isEmpty ? 'this estate' : estateName.trim()} and repair the current gaps before rewriting the task list.",
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Gaps found",
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...report.issueSummaries.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text("• $line"),
                        ),
                      ),
                      if (report.phaseGaps.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Thinnest phases",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        ...report.phaseGaps
                            .take(4)
                            .map(
                              (gap) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  "• ${gap.phaseName}: ${gap.currentTaskCount} tasks across ${gap.allocatedDays} days. Add about ${gap.missingTaskCount} more task${gap.missingTaskCount == 1 ? '' : 's'}.",
                                ),
                              ),
                            ),
                      ],
                      const SizedBox(height: 18),
                      DropdownButtonFormField<int>(
                        initialValue: selectedAllowance,
                        decoration: const InputDecoration(
                          labelText: "How many new tasks may AI add?",
                          helperText:
                              "Choose 0 to keep the current task count and only rewrite what is already there.",
                          helperMaxLines: 2,
                        ),
                        items: options
                            .map(
                              (value) => DropdownMenuItem<int>(
                                value: value,
                                child: Text(
                                  value == 0
                                      ? "0 • rewrite only"
                                      : "$value additional tasks",
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedAllowance = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _DraftRefineDialogResult(
                        maxAdditionalTasks: selectedAllowance,
                      ),
                    );
                  },
                  child: const Text("Refine draft"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _buildDraftAiContext(
    ProductionPlanDraftState draft,
    Map<String, BusinessStaffProfileSummary> staffById,
  ) {
    final alignedDraft = _alignDraftPhaseDaysToProjectWindow(draft);
    final phaseWindows = _buildDraftExportPhaseWindows(alignedDraft);
    final totalProjectDays = _resolveDraftProjectTotalDays(alignedDraft);
    final buffer = StringBuffer()
      ..writeln(
        "Draft title: ${alignedDraft.title.trim().isEmpty ? 'Untitled draft' : alignedDraft.title.trim()}",
      )
      ..writeln("Domain: ${alignedDraft.domainContext}")
      ..writeln(
        "Dates: ${alignedDraft.startDate == null ? 'pending' : formatDateInput(alignedDraft.startDate!)} -> ${alignedDraft.endDate == null ? 'pending' : formatDateInput(alignedDraft.endDate!)}",
      );
    buffer.writeln(
      "Total project duration: $totalProjectDays day(s) inclusive.",
    );

    if (alignedDraft.notes.trim().isNotEmpty) {
      buffer.writeln("Manager notes: ${alignedDraft.notes.trim()}");
    }
    if (productionDomainRequiresPlantingTargets(alignedDraft.domainContext) &&
        alignedDraft.plantingTargets.isComplete) {
      buffer.writeln(
        "Planting baseline: ${_formatQuantity(alignedDraft.plantingTargets.plannedPlantingQuantity)} ${alignedDraft.plantingTargets.plannedPlantingUnit} ${formatProductionPlantingMaterialType(alignedDraft.plantingTargets.materialType).toLowerCase()} planned, ${_formatQuantity(alignedDraft.plantingTargets.estimatedHarvestQuantity)} ${alignedDraft.plantingTargets.estimatedHarvestUnit} estimated harvest.",
      );
    }
    if (alignedDraft.riskNotes.isNotEmpty) {
      buffer.writeln("Current warnings:");
      for (final warning in alignedDraft.riskNotes) {
        if (warning.trim().isNotEmpty) {
          buffer.writeln("- ${warning.trim()}");
        }
      }
    }

    for (final phaseWindow in phaseWindows) {
      final phase = phaseWindow.phase;
      final dateRangeLabel =
          phaseWindow.startDate != null && phaseWindow.endDate != null
          ? "${formatDateInput(phaseWindow.startDate!)} -> ${formatDateInput(phaseWindow.endDate!)}"
          : "dates pending";
      buffer.writeln(
        "Phase ${phase.order}: ${phase.name.trim().isEmpty ? 'Unnamed phase' : phase.name.trim()} | allocated ${phaseWindow.allocatedDays} of $totalProjectDays day(s) | project day ${phaseWindow.projectDayStart}-${phaseWindow.projectDayEnd} | $dateRangeLabel | type ${phase.phaseType} | required units ${phase.requiredUnits}.",
      );
      for (final task in phase.tasks) {
        final assignedStaff = task.assignedStaffProfileIds
            .map(
              (id) => _resolveStaffDisplayName(staffById[id.trim()], id.trim()),
            )
            .where((label) => label.trim().isNotEmpty)
            .join(", ");
        buffer.writeln(
          "Task: ${task.title.trim().isEmpty ? 'Untitled task' : task.title.trim()} | role ${task.roleRequired.trim().isEmpty ? 'farmer' : task.roleRequired.trim()} | headcount ${task.requiredHeadcount} | weight ${task.weight} | assigned ${assignedStaff.isEmpty ? 'none' : assignedStaff} | status ${task.status.name} | instructions ${task.instructions.trim().isEmpty ? 'none' : task.instructions.trim()}",
        );
      }
    }

    final text = buffer.toString().trim();
    if (text.length <= _draftAiRefineContextCharacterLimit) {
      return text;
    }
    return "${text.substring(0, _draftAiRefineContextCharacterLimit)}\n...[draft context truncated]";
  }

  String _buildAiRefinePrompt({
    required ProductionPlanDraftState draft,
    required String estateName,
    required String productName,
    required List<String> focusedRoles,
    required Map<String, BusinessStaffProfileSummary> staffById,
    required _DraftRefineGapReport gapReport,
    required int maxAdditionalTasks,
  }) {
    final safeEstate = estateName.trim().isEmpty
        ? "selected estate"
        : estateName.trim();
    final safeProduct = productName.trim().isEmpty
        ? "selected crop"
        : productName.trim();
    final alignedDraft = _alignDraftPhaseDaysToProjectWindow(draft);
    final totalProjectDays = _resolveDraftProjectTotalDays(alignedDraft);
    final roleInstruction = focusedRoles.isEmpty
        ? ""
        : " Keep roleRequired within these role tracks where possible: ${focusedRoles.join(", ")}.";
    final dateInstruction =
        alignedDraft.startDate != null && alignedDraft.endDate != null
        ? " Preserve the current working window ${formatDateInput(alignedDraft.startDate!)} to ${formatDateInput(alignedDraft.endDate!)} unless the draft clearly needs a safer lifecycle adjustment."
        : " Infer lifecycle-safe dates if they are missing.";
    final plantingInstruction =
        productionDomainRequiresPlantingTargets(alignedDraft.domainContext) &&
            alignedDraft.plantingTargets.isComplete
        ? " Preserve the current planting baseline and align sowing, transplant, flowering, and harvest tasks to it."
        : "";
    final gapInstruction = gapReport.issueSummaries
        .map((line) => "- $line")
        .join("\n");
    final draftContext = _buildDraftAiContext(alignedDraft, staffById);
    final taskLimitInstruction = maxAdditionalTasks <= 0
        ? " Do not add new tasks unless the current draft is structurally broken; rewrite and rebalance what already exists."
        : " You may add up to $maxAdditionalTasks new tasks to close the real gaps, but only where a phase is too thin for its allocated days. The refined draft should aim for about ${gapReport.suggestedTaskCount} total tasks instead of the current ${gapReport.totalTaskCount} tasks unless there are obvious duplicates to merge.";
    return "Refine the current production draft for $safeProduct at $safeEstate. Keep the business domain ${alignedDraft.domainContext} and improve the draft without turning it into a different plan.$roleInstruction$dateInstruction$plantingInstruction The total project duration is $totalProjectDays day(s) inclusive, and the sum of phase estimatedDays must stay aligned to that duration. Allocate days per phase realistically for the lifecycle. Do not leave a long phase with only one or two vague tasks; if a phase spans many days, break it into concrete milestones, recurring operational tasks, daily or near-daily checks, and inspection tasks across that phase. Remove repetitive generic tasks, make task titles specific, tighten instructions, keep headcount realistic, keep phase placement coherent, and preserve assigned staff where appropriate. Prefer a detailed working draft over a sparse summary.$taskLimitInstruction\n\nCURRENT GAPS TO FIX\n$gapInstruction\n\nCURRENT DRAFT START\n$draftContext\nCURRENT DRAFT END";
  }

  Map<String, dynamic> _buildAiRefineDraftPayload({
    required ProductionPlanDraftState draft,
    required String prompt,
    required String productName,
    required Map<String, BusinessStaffProfileSummary> staffById,
    required _DraftRefineGapReport gapReport,
    required int maxAdditionalTasks,
  }) {
    final alignedDraft = _alignDraftPhaseDaysToProjectWindow(draft);
    final focusedRoles = _collectDistinctDraftRoles(alignedDraft);
    final focusedStaffProfiles = _collectAssignedStaffProfiles(
      alignedDraft,
      staffById,
    );
    final focusedStaffRows = _buildFocusedStaffProfilesPayload(
      focusedStaffProfiles,
    );
    final focusedStaffByRole = _buildFocusedStaffByRolePayload(
      focusedStaffRows,
    );
    return {
      "aiBrief": prompt,
      "prompt": prompt,
      "estateAssetId": alignedDraft.estateAssetId ?? "",
      "productId": alignedDraft.productId ?? "",
      "productSearchName": productName,
      "startDate": alignedDraft.startDate == null
          ? ""
          : formatDateInput(alignedDraft.startDate!),
      "endDate": alignedDraft.endDate == null
          ? ""
          : formatDateInput(alignedDraft.endDate!),
      "domainContext": alignedDraft.domainContext,
      "businessType": alignedDraft.domainContext,
      "focusedRoles": focusedRoles,
      "focusedStaffProfileIds":
          focusedStaffProfiles
              .map((profile) => profile.id.trim())
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort(),
      "focusedStaffProfiles": focusedStaffRows,
      "focusedStaffByRole": focusedStaffByRole,
      "focusedRoleTaskHints": {
        for (final role in focusedRoles) role: const <String>[],
      },
      "workloadContext": {
        "workUnitLabel": _defaultWorkUnitLabelForDomain(
          alignedDraft.domainContext,
        ),
        "totalWorkUnits": _inferTotalWorkUnits(alignedDraft),
        "minStaffPerUnit": 1,
        "maxStaffPerUnit": _inferMaxStaffPerUnit(alignedDraft),
        "activeStaffAvailabilityPercent": 70,
        "hasConfirmedWorkloadContext": true,
      },
      "plantingTargets": alignedDraft.plantingTargets.toPayload(),
      "cropSubtype": "",
      "refineTarget": {
        "mode": "draft_refine",
        "currentTaskCount": gapReport.totalTaskCount,
        "requestedTaskCount": gapReport.suggestedTaskCount,
        "maxAdditionalTasks": maxAdditionalTasks,
        "phaseTargets": [
          for (final phaseGap in gapReport.phaseGaps)
            {
              "phaseName": phaseGap.phaseName,
              "allocatedDays": phaseGap.allocatedDays,
              "currentTaskCount": phaseGap.currentTaskCount,
              "targetTaskCount": phaseGap.suggestedTaskCount,
            },
        ],
      },
    };
  }

  ProductionPlanDraftState _mergeAiDraftIntoCurrentDraft({
    required ProductionPlanDraftState currentDraft,
    required ProductionPlanDraftState aiDraft,
    required List<String> warnings,
  }) {
    final normalizedCurrentDraft = _alignDraftPhaseDaysToProjectWindow(
      currentDraft,
    );
    final normalizedAiDraft = _alignDraftPhaseDaysToProjectWindow(aiDraft);
    final normalizedWarnings = warnings
        .map((warning) => warning.trim())
        .where((warning) => warning.isNotEmpty)
        .toList();
    return currentDraft.copyWith(
      title: normalizedAiDraft.title.trim().isEmpty
          ? normalizedCurrentDraft.title
          : normalizedAiDraft.title,
      estateAssetId: (normalizedCurrentDraft.estateAssetId ?? "").trim().isEmpty
          ? normalizedAiDraft.estateAssetId
          : normalizedCurrentDraft.estateAssetId,
      productId: (normalizedCurrentDraft.productId ?? "").trim().isEmpty
          ? normalizedAiDraft.productId
          : normalizedCurrentDraft.productId,
      startDate:
          normalizedAiDraft.startDate ?? normalizedCurrentDraft.startDate,
      endDate: normalizedAiDraft.endDate ?? normalizedCurrentDraft.endDate,
      plantingTargets: normalizedCurrentDraft.plantingTargets.hasAnyValue
          ? normalizedCurrentDraft.plantingTargets
          : normalizedAiDraft.plantingTargets,
      aiGenerated: true,
      totalTasks: normalizedAiDraft.totalTasks,
      totalEstimatedDays: normalizedAiDraft.totalEstimatedDays,
      riskNotes: normalizedWarnings.isEmpty
          ? normalizedAiDraft.riskNotes
          : normalizedWarnings,
      phases: normalizedAiDraft.phases,
    );
  }

  Future<void> _refineDraftWithAi({
    required ProductionPlanDraftState draft,
    required String selectedEstateName,
    required String selectedProductName,
    required Map<String, BusinessStaffProfileSummary> staffById,
  }) async {
    if (_isSaving ||
        _isRefiningDraft ||
        _isImportingDraftDocument ||
        _isDownloadingDraft) {
      return;
    }
    final hasDraftTasks = draft.phases.any((phase) => phase.tasks.isNotEmpty);
    if (!hasDraftTasks) {
      _showSnack("Add or generate draft tasks before refining with AI.");
      return;
    }
    final gapReport = _buildDraftRefineGapReport(draft);
    final refineConfig = await _showDraftRefineDialog(
      report: gapReport,
      estateName: selectedEstateName,
      productName: selectedProductName,
    );
    if (refineConfig == null) {
      return;
    }

    setState(() {
      _isRefiningDraft = true;
    });

    try {
      final alignedDraft = _alignDraftPhaseDaysToProjectWindow(draft);
      final productName = _resolveDraftProductName(
        alignedDraft,
        fallback: selectedProductName,
      );
      final prompt = _buildAiRefinePrompt(
        draft: alignedDraft,
        estateName: selectedEstateName,
        productName: productName,
        focusedRoles: _collectDistinctDraftRoles(alignedDraft),
        staffById: staffById,
        gapReport: gapReport,
        maxAdditionalTasks: refineConfig.maxAdditionalTasks,
      );
      final aiResult = await ref
          .read(productionPlanActionsProvider)
          .generateAiDraft(
            payload: _buildAiRefineDraftPayload(
              draft: alignedDraft,
              prompt: prompt,
              productName: productName,
              staffById: staffById,
              gapReport: gapReport,
              maxAdditionalTasks: refineConfig.maxAdditionalTasks,
            ),
          );
      final nextDraft = _mergeAiDraftIntoCurrentDraft(
        currentDraft: alignedDraft,
        aiDraft: aiResult.draft,
        warnings: aiResult.warnings,
      );
      ref.read(productionPlanDraftProvider.notifier).applyDraft(nextDraft);
      _syncControllers(nextDraft);
      if (mounted) {
        setState(() {
          _mobileSection = _DraftEditorMobileSection.tasks;
        });
      }
      _showSnack(
        refineConfig.maxAdditionalTasks <= 0
            ? "AI refined the draft without expanding the task count. Review it, then save draft to record the revision."
            : "AI refined the draft with room for up to ${refineConfig.maxAdditionalTasks} new tasks. Review it, then save draft to record the revision.",
      );
    } catch (_) {
      _showSnack("Couldn't refine the draft with AI yet.");
    } finally {
      if (mounted) {
        setState(() {
          _isRefiningDraft = false;
        });
      } else {
        _isRefiningDraft = false;
      }
    }
  }

  Future<void> _downloadDraftFile({
    required ProductionPlanDraftState draft,
    required String selectedEstateName,
    required String selectedProductName,
    required Map<String, BusinessStaffProfileSummary> staffById,
    ProductionPlanDetail? detail,
  }) async {
    if (_isDownloadingDraft || _isImportingDraftDocument) {
      return;
    }

    setState(() {
      _isDownloadingDraft = true;
    });

    try {
      final fileName = _buildDraftDownloadFileName(
        draft: draft,
        selectedProductName: selectedProductName,
      );
      final contents = _buildDraftDownloadContents(
        draft: draft,
        selectedEstateName: selectedEstateName,
        selectedProductName: selectedProductName,
        staffById: staffById,
        detail: detail,
      );
      final savedPath = await downloadPlainTextFile(
        fileName: fileName,
        contents: contents,
        mimeType: "text/html",
      );
      _showSnack(
        savedPath == null
            ? "Draft download started as $fileName."
            : "Draft saved to $savedPath",
      );
    } catch (_) {
      _showSnack("Couldn't download the draft yet. Please try again.");
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingDraft = false;
        });
      } else {
        _isDownloadingDraft = false;
      }
    }
  }

  String _buildDraftDownloadFileName({
    required ProductionPlanDraftState draft,
    required String selectedProductName,
  }) {
    final baseName = _resolveDraftProductName(
      draft,
      fallback: selectedProductName,
    );
    final slug = baseName
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
        .replaceAll(RegExp(r"-{2,}"), "-")
        .replaceAll(RegExp(r"^-+|-+$"), "");
    final safeSlug = slug.isEmpty ? "production-draft" : slug;
    final safeDate = draft.startDate == null
        ? formatDateInput(DateTime.now())
        : formatDateInput(draft.startDate!);
    return "draft-$safeSlug-$safeDate.html";
  }

  String _buildDraftDownloadContents({
    required ProductionPlanDraftState draft,
    required String selectedEstateName,
    required String selectedProductName,
    required Map<String, BusinessStaffProfileSummary> staffById,
    ProductionPlanDetail? detail,
  }) {
    final htmlEscape = const HtmlEscape();
    final exportDraft = _alignDraftPhaseDaysToProjectWindow(draft);
    final phaseWindows = _buildDraftExportPhaseWindows(exportDraft);
    final totalProjectDays = _resolveDraftProjectTotalDays(exportDraft);
    final totalTaskCount = exportDraft.phases.fold<int>(
      0,
      (sum, phase) => sum + phase.tasks.length,
    );
    final productName = _resolveDraftProductName(
      exportDraft,
      fallback: selectedProductName,
    );
    final title = exportDraft.title.trim().isEmpty
        ? "Untitled draft"
        : exportDraft.title;
    final estateName = selectedEstateName.trim().isEmpty
        ? "Estate not selected"
        : selectedEstateName.trim();
    final cropName = productName.trim().isEmpty
        ? "Crop not selected"
        : productName.trim();
    final dateLabel =
        exportDraft.startDate != null && exportDraft.endDate != null
        ? "${formatDateLabel(exportDraft.startDate)} → ${formatDateLabel(exportDraft.endDate)}"
        : "Dates pending";
    final savedBy = detail?.plan.lastDraftSavedBy?.displayLabel ?? "";
    final savedAt = detail?.plan.lastDraftSavedAt == null
        ? "Not saved yet"
        : formatDateTimeLabel(detail!.plan.lastDraftSavedAt);
    final revisionLabel = detail == null
        ? "Unsaved draft"
        : "${detail.plan.draftRevisionCount} saved revision${detail.plan.draftRevisionCount == 1 ? '' : 's'}";
    final plantingLabel =
        productionDomainRequiresPlantingTargets(exportDraft.domainContext)
        ? exportDraft.plantingTargets.isComplete
              ? "${_formatQuantity(exportDraft.plantingTargets.plannedPlantingQuantity)} ${exportDraft.plantingTargets.plannedPlantingUnit} ${formatProductionPlantingMaterialType(exportDraft.plantingTargets.materialType).toLowerCase()} → ${_formatQuantity(exportDraft.plantingTargets.estimatedHarvestQuantity)} ${exportDraft.plantingTargets.estimatedHarvestUnit}"
              : "Planting baseline pending"
        : "Not required";
    final notesMarkup = exportDraft.notes.trim().isEmpty
        ? "<p class=\"muted\">No manager notes yet.</p>"
        : "<pre>${htmlEscape.convert(exportDraft.notes.trim())}</pre>";
    final phaseAllocationMarkup = phaseWindows.isEmpty
        ? "<p class=\"muted\">No phases in this draft yet.</p>"
        : """
          <table>
            <thead>
              <tr>
                <th>Phase #</th>
                <th>Phase</th>
                <th>Allocated days</th>
                <th>Project day range</th>
                <th>Date range</th>
                <th>Tasks</th>
                <th>Tasks / day</th>
              </tr>
            </thead>
            <tbody>
              ${phaseWindows.map((phaseWindow) {
            final phase = phaseWindow.phase;
            final dateRangeLabel = phaseWindow.startDate != null && phaseWindow.endDate != null ? "${formatDateLabel(phaseWindow.startDate)} → ${formatDateLabel(phaseWindow.endDate)}" : "Dates pending";
            final tasksPerDay = phase.tasks.isEmpty ? "0.00" : (phase.tasks.length / phaseWindow.allocatedDays).toStringAsFixed(2);
            return """
                  <tr>
                    <td>${phase.order}</td>
                    <td>${htmlEscape.convert(phase.name.trim().isEmpty ? "Phase ${phase.order}" : phase.name.trim())}</td>
                    <td>${phaseWindow.allocatedDays}</td>
                    <td>Day ${phaseWindow.projectDayStart}-${phaseWindow.projectDayEnd}</td>
                    <td>${htmlEscape.convert(dateRangeLabel)}</td>
                    <td>${phase.tasks.length}</td>
                    <td>$tasksPerDay</td>
                  </tr>
                """;
          }).join()}
            </tbody>
          </table>
        """;
    final phaseMarkup = phaseWindows.isEmpty
        ? "<p class=\"muted\">No phases in this draft yet.</p>"
        : phaseWindows
              .map((phaseWindow) {
                final phase = phaseWindow.phase;
                final tasksMarkup = phase.tasks.isEmpty
                    ? "<p class=\"muted\">No tasks in this phase yet.</p>"
                    : """
                  <table>
                    <thead>
                      <tr>
                        <th>Task</th>
                        <th>Role</th>
                        <th>Headcount</th>
                        <th>Assigned</th>
                        <th>Status</th>
                        <th>Instructions</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${phase.tasks.map((task) {
                        final assignedLabel = _buildDraftAssignedLabel(task.assignedStaffProfileIds, staffById);
                        return """
                          <tr>
                            <td>${htmlEscape.convert(task.title.trim().isEmpty ? "Task" : task.title.trim())}</td>
                            <td>${htmlEscape.convert(task.roleRequired.trim().isEmpty ? "farmer" : task.roleRequired.trim())}</td>
                            <td>${task.requiredHeadcount}</td>
                            <td>${htmlEscape.convert(assignedLabel)}</td>
                            <td>${htmlEscape.convert(task.status.name)}</td>
                            <td>${htmlEscape.convert(task.instructions.trim().isEmpty ? "-" : task.instructions.trim())}</td>
                          </tr>
                        """;
                      }).join()}
                    </tbody>
                  </table>
                """;
                final dayRows = _buildDraftExportPhaseDays(phaseWindow);
                final dayBreakdownMarkup =
                    """
                  <table>
                    <thead>
                      <tr>
                        <th>Project day</th>
                        <th>Phase day</th>
                        <th>Date</th>
                        <th>Scheduled draft detail</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${dayRows.map((dayRow) {
                      final taskMarkup = dayRow.tasks.isEmpty ? "<span class=\"muted\">No explicit task scheduled in the saved draft for this day.</span>" : dayRow.tasks.map((task) {
                              final assignedLabel = _buildDraftAssignedLabel(task.assignedStaffProfileIds, staffById);
                              final instructions = task.instructions.trim();
                              return """
                                  <div class="day-task">
                                    <strong>${htmlEscape.convert(task.title.trim().isEmpty ? "Task" : task.title.trim())}</strong>
                                    <div class="task-subline">
                                      ${htmlEscape.convert(task.roleRequired.trim().isEmpty ? "farmer" : task.roleRequired.trim())} x${task.requiredHeadcount} • ${htmlEscape.convert(assignedLabel)} • ${htmlEscape.convert(task.status.name)}
                                    </div>
                                    ${instructions.isEmpty ? "" : "<div class=\"task-note\">${htmlEscape.convert(instructions)}</div>"}
                                  </div>
                                """;
                            }).join();
                      final dateValue = dayRow.date == null ? "Date pending" : formatDateLabel(dayRow.date);
                      return """
                          <tr>
                            <td>Day ${dayRow.projectDayNumber}</td>
                            <td>${dayRow.phaseDayNumber}</td>
                            <td>${htmlEscape.convert(dateValue)}</td>
                            <td>$taskMarkup</td>
                          </tr>
                        """;
                    }).join()}
                    </tbody>
                  </table>
                """;
                final dateRangeLabel =
                    phaseWindow.startDate != null && phaseWindow.endDate != null
                    ? "${formatDateLabel(phaseWindow.startDate)} → ${formatDateLabel(phaseWindow.endDate)}"
                    : "Dates pending";
                return """
              <section class="phase">
                <h2>${htmlEscape.convert(phase.name.trim().isEmpty ? "Phase ${phase.order}" : phase.name.trim())}</h2>
                <p class="phase-meta">
                  ${phaseWindow.allocatedDays} day${phaseWindow.allocatedDays == 1 ? "" : "s"} allocated • Project days ${phaseWindow.projectDayStart}-${phaseWindow.projectDayEnd} • ${htmlEscape.convert(dateRangeLabel)} • ${phase.tasks.length} task${phase.tasks.length == 1 ? "" : "s"} • ${htmlEscape.convert(phase.phaseType)}
                </p>
                <div class="summary-banner">
                  Phase ${phase.order} covers day ${phaseWindow.projectDayStart} to day ${phaseWindow.projectDayEnd} of the full $totalProjectDays-day project.
                </div>
                <h3 class="table-heading">Tasks in this phase</h3>
                $tasksMarkup
                <h3 class="table-heading">Full day-by-day breakdown</h3>
                $dayBreakdownMarkup
              </section>
            """;
              })
              .join("\n");

    return """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${htmlEscape.convert(title)}</title>
    <style>
      body { font-family: Arial, sans-serif; margin: 0; background: #f4f7fb; color: #162033; }
      .page { max-width: 1120px; margin: 0 auto; padding: 32px 20px 48px; }
      .hero { background: #ffffff; border: 1px solid #d7deea; border-radius: 20px; padding: 24px; margin-bottom: 20px; }
      h1 { margin: 0 0 10px; font-size: 30px; }
      h2 { margin: 0 0 8px; font-size: 22px; }
      h3 { margin: 18px 0 10px; font-size: 16px; }
      .meta { display: flex; flex-wrap: wrap; gap: 10px; margin: 18px 0 0; }
      .chip { background: #eef3ff; border: 1px solid #d7deea; border-radius: 999px; padding: 10px 14px; font-size: 14px; }
      .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; margin-top: 18px; }
      .card, .phase { background: #ffffff; border: 1px solid #d7deea; border-radius: 20px; padding: 20px; margin-top: 18px; }
      .label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.06em; color: #5b6882; margin-bottom: 6px; }
      .value { font-size: 16px; font-weight: 700; }
      .muted { color: #5b6882; }
      .phase-meta { margin: 0 0 16px; color: #5b6882; }
      .summary-banner { margin: 0 0 16px; padding: 12px 14px; border-radius: 14px; background: #f7f9fd; border: 1px solid #d7deea; color: #38445d; }
      .table-heading { margin-top: 20px; }
      .day-task + .day-task { margin-top: 12px; padding-top: 12px; border-top: 1px dashed #d7deea; }
      .task-subline { margin-top: 4px; color: #5b6882; font-size: 13px; }
      .task-note { margin-top: 6px; color: #38445d; font-size: 13px; }
      pre { white-space: pre-wrap; font-family: inherit; margin: 0; }
      table { width: 100%; border-collapse: collapse; }
      th, td { text-align: left; border-top: 1px solid #e3e9f3; padding: 12px 10px; vertical-align: top; font-size: 14px; }
      th { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: #5b6882; background: #f7f9fd; }
    </style>
  </head>
  <body>
    <div class="page">
      <section class="hero">
        <h1>${htmlEscape.convert(title)}</h1>
        <p class="muted">Exported from the production draft editor for manager review and offline circulation.</p>
        <div class="meta">
          <span class="chip">${htmlEscape.convert(estateName)}</span>
          <span class="chip">${htmlEscape.convert(cropName)}</span>
          <span class="chip">${htmlEscape.convert(dateLabel)}</span>
          <span class="chip">${htmlEscape.convert("$totalProjectDays total day(s)")}</span>
          <span class="chip">${htmlEscape.convert(plantingLabel)}</span>
          <span class="chip">${htmlEscape.convert(revisionLabel)}</span>
        </div>
        <div class="grid">
          <div class="card">
            <div class="label">Last saved</div>
            <div class="value">${htmlEscape.convert(savedAt)}</div>
            ${savedBy.trim().isEmpty ? "" : "<p class=\"muted\">By ${htmlEscape.convert(savedBy.trim())}</p>"}
          </div>
          <div class="card">
            <div class="label">Domain</div>
            <div class="value">${htmlEscape.convert(exportDraft.domainContext)}</div>
          </div>
          <div class="card">
            <div class="label">Phases</div>
            <div class="value">${exportDraft.phases.length}</div>
          </div>
          <div class="card">
            <div class="label">Project days</div>
            <div class="value">$totalProjectDays</div>
          </div>
          <div class="card">
            <div class="label">Tasks</div>
            <div class="value">$totalTaskCount</div>
          </div>
        </div>
      </section>
      <section class="card">
        <h2>Phase allocation overview</h2>
        <p class="muted">Every phase below is normalized to the full project window so managers can see exactly how many days each phase owns and what day numbers it covers.</p>
        $phaseAllocationMarkup
      </section>
      <section class="card">
        <h2>Manager notes</h2>
        $notesMarkup
      </section>
      $phaseMarkup
    </div>
  </body>
</html>
""";
  }

  Future<void> _populateDraftFromDocument({
    required ProductionPlanDraftState draft,
    required String selectedEstateName,
    required String selectedProductName,
  }) async {
    if (_isSaving || _isImportingDraftDocument || _isDownloadingDraft) {
      return;
    }

    final hasEstate = (draft.estateAssetId ?? "").trim().isNotEmpty;
    final resolvedProductName = _resolveDraftProductName(
      draft,
      fallback: selectedProductName,
    );
    if (!hasEstate) {
      _showSnack("Select an estate before populating this draft.");
      return;
    }
    if (resolvedProductName.trim().isEmpty) {
      _showSnack("Add a crop or draft title before populating this draft.");
      return;
    }

    setState(() {
      _isImportingDraftDocument = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _documentImportAllowedExtensions,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes ?? <int>[];
      if (bytes.isEmpty) {
        _showSnack("That file could not be read for draft import.");
        return;
      }
      if (bytes.length > _documentImportMaxBytes) {
        _showSnack("That file is too large to import into a draft.");
        return;
      }
      final importedText = _extractImportableDocumentText(
        bytes: bytes,
        filename: file.name,
      );
      final sourceDocumentPayload = _buildSourceDocumentPayload(
        fileName: file.name,
        bytes: bytes,
        importedText: importedText,
      );
      if (importedText.trim().isEmpty && sourceDocumentPayload == null) {
        _showSnack(
          "No readable planning text was found in that file. Try a text-based PDF, HTML, or text export.",
        );
        return;
      }

      final prompt = _buildImportedDocumentPrompt(
        draft: draft,
        estateName: selectedEstateName,
        productName: resolvedProductName,
        fileName: file.name,
        importedText: importedText,
      );
      final aiResult = await ref
          .read(productionPlanActionsProvider)
          .generateAiDraft(
            payload: _buildImportedDocumentDraftPayload(
              draft: draft,
              prompt: prompt,
              productName: resolvedProductName,
              sourceDocument: sourceDocumentPayload,
            ),
          );
      final nextDraft = aiResult.draft.copyWith(
        title: aiResult.draft.title.trim().isEmpty ? draft.title : null,
        notes: aiResult.draft.notes.trim().isEmpty ? draft.notes : null,
        domainContext: draft.domainContext,
        estateAssetId: (draft.estateAssetId ?? "").trim().isEmpty
            ? aiResult.draft.estateAssetId
            : draft.estateAssetId,
        productId: (draft.productId ?? "").trim().isEmpty
            ? aiResult.draft.productId
            : draft.productId,
        startDate: aiResult.draft.startDate ?? draft.startDate,
        endDate: aiResult.draft.endDate ?? draft.endDate,
        plantingTargets: aiResult.draft.plantingTargets.hasAnyValue
            ? aiResult.draft.plantingTargets
            : draft.plantingTargets,
        riskNotes:
            aiResult.warnings
                .map((warning) => warning.trim())
                .where((warning) => warning.isNotEmpty)
                .toList()
                .isEmpty
            ? aiResult.draft.riskNotes
            : aiResult.warnings
                  .map((warning) => warning.trim())
                  .where((warning) => warning.isNotEmpty)
                  .toList(),
      );
      ref.read(productionPlanDraftProvider.notifier).applyDraft(nextDraft);
      _syncControllers(nextDraft);
      final existingPlanId = (widget.planId ?? "").trim();
      final existingPlanStatus = existingPlanId.isEmpty
          ? ""
          : ref
                    .read(productionPlanDetailProvider(existingPlanId))
                    .valueOrNull
                    ?.plan
                    .status
                    .trim()
                    .toLowerCase() ??
                "";
      _showSnack(
        existingPlanStatus == "active" || existingPlanStatus == "paused"
            ? "Draft populated from ${file.name}. This only updated the editor copy. Use Return to draft, then Save draft, to replace the live production plan."
            : "Draft populated from ${file.name}. Save draft to record the revision.",
      );
    } on ProductionAiDraftError catch (error) {
      final message = error.resolutionHint.trim().isNotEmpty
          ? error.resolutionHint.trim()
          : error.message.trim();
      _showSnack(
        message.isEmpty
            ? "Couldn't populate the draft from that document yet."
            : message,
      );
    } catch (_) {
      _showSnack("Couldn't populate the draft from that document yet.");
    } finally {
      if (mounted) {
        setState(() {
          _isImportingDraftDocument = false;
        });
      } else {
        _isImportingDraftDocument = false;
      }
    }
  }

  Map<String, dynamic> _buildImportedDocumentDraftPayload({
    required ProductionPlanDraftState draft,
    required String prompt,
    required String productName,
    required Map<String, dynamic>? sourceDocument,
  }) {
    final alignedDraft = _alignDraftPhaseDaysToProjectWindow(draft);
    final gapReport = _buildDraftRefineGapReport(alignedDraft);
    final importedTaskLikeCount = _estimateImportedTaskLikeLineCount(
      importedTextForTarget(sourceDocument),
    );
    final requestedTaskCount = math
        .max(gapReport.suggestedTaskCount, importedTaskLikeCount)
        .clamp(draft.totalTasks, 180)
        .toInt();
    final safeWorkUnitLabel = _defaultWorkUnitLabelForDomain(
      draft.domainContext,
    );
    return {
      "aiBrief": prompt,
      "prompt": prompt,
      "estateAssetId": draft.estateAssetId ?? "",
      "productId": draft.productId ?? "",
      "productSearchName": productName,
      "startDate": draft.startDate == null
          ? ""
          : formatDateInput(draft.startDate!),
      "endDate": draft.endDate == null ? "" : formatDateInput(draft.endDate!),
      "domainContext": draft.domainContext,
      "businessType": draft.domainContext,
      "focusedRoles": const <String>[],
      "focusedStaffProfileIds": const <String>[],
      "focusedStaffProfiles": const <Map<String, String>>[],
      "focusedStaffByRole": const <String, List<String>>{},
      "focusedRoleTaskHints": const <String, List<String>>{},
      "workloadContext": {
        "workUnitLabel": safeWorkUnitLabel,
        "totalWorkUnits": _inferTotalWorkUnits(draft),
        "minStaffPerUnit": 1,
        "maxStaffPerUnit": _inferMaxStaffPerUnit(draft),
        "activeStaffAvailabilityPercent": 70,
        "hasConfirmedWorkloadContext": true,
      },
      "plantingTargets": draft.plantingTargets.toPayload(),
      "cropSubtype": "",
      "refineTarget": {
        "mode": "document_import",
        "currentTaskCount": draft.totalTasks,
        "requestedTaskCount": requestedTaskCount,
        "maxAdditionalTasks": math.max(
          0,
          requestedTaskCount - draft.totalTasks,
        ),
        "phaseTargets": [
          for (final phaseGap in gapReport.phaseGaps)
            {
              "phaseName": phaseGap.phaseName,
              "allocatedDays": phaseGap.allocatedDays,
              "currentTaskCount": phaseGap.currentTaskCount,
              "targetTaskCount": phaseGap.suggestedTaskCount,
            },
        ],
      },
      if (sourceDocument != null) "sourceDocument": sourceDocument,
    };
  }

  String importedTextForTarget(Map<String, dynamic>? sourceDocument) {
    final rawText = (sourceDocument?["frontendExtractedText"] ?? "")
        .toString()
        .trim();
    return rawText;
  }

  Map<String, dynamic>? _buildSourceDocumentPayload({
    required String fileName,
    required List<int> bytes,
    required String importedText,
  }) {
    if (bytes.isEmpty || bytes.length > _documentImportMaxBytes) {
      return null;
    }
    final extension = _extractImportFileExtension(fileName);
    return {
      "fileName": fileName.trim(),
      "extension": extension,
      "contentBase64": base64Encode(bytes),
      if (importedText.trim().isNotEmpty)
        "frontendExtractedText": importedText.trim(),
      "taskLineEstimate": _estimateImportedTaskLikeLineCount(importedText),
    };
  }

  String _buildImportedDocumentPrompt({
    required ProductionPlanDraftState draft,
    required String estateName,
    required String productName,
    required String fileName,
    required String importedText,
  }) {
    final safeEstate = estateName.trim().isEmpty
        ? "selected estate"
        : estateName.trim();
    final safeProduct = productName.trim().isEmpty
        ? "selected crop"
        : productName.trim();
    final safeFileName = fileName.trim().isEmpty
        ? "uploaded-document"
        : fileName.trim();
    final importedTaskLikeCount = _estimateImportedTaskLikeLineCount(
      importedText,
    );
    final truncatedText = importedText.length > _documentImportCharacterLimit
        ? importedText.substring(0, _documentImportCharacterLimit)
        : importedText;
    final hasPreview = truncatedText.trim().isNotEmpty;
    final dateInstruction = draft.startDate != null && draft.endDate != null
        ? "Keep the planning window within ${formatDateInput(draft.startDate!)} to ${formatDateInput(draft.endDate!)} unless the document clearly requires an adjustment."
        : "Infer lifecycle-safe start and end dates from the document.";
    final plantingInstruction =
        productionDomainRequiresPlantingTargets(draft.domainContext) &&
            draft.plantingTargets.isComplete
        ? " Preserve this planting baseline: ${_formatQuantity(draft.plantingTargets.plannedPlantingQuantity)} ${draft.plantingTargets.plannedPlantingUnit} ${formatProductionPlantingMaterialType(draft.plantingTargets.materialType).toLowerCase()} planned, ${_formatQuantity(draft.plantingTargets.estimatedHarvestQuantity)} ${draft.plantingTargets.estimatedHarvestUnit} estimated harvest."
        : "";
    final currentPhaseLabels = draft.phases
        .map((phase) => phase.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final currentPhaseInstruction = currentPhaseLabels.isEmpty
        ? ""
        : " Current draft phase labels: ${currentPhaseLabels.join(", ")}.";
    final currentNotesInstruction = draft.notes.trim().isEmpty
        ? ""
        : " Current manager notes: ${draft.notes.trim()}";
    final densityInstruction = importedTaskLikeCount > 0
        ? " The uploaded source appears to contain about $importedTaskLikeCount task-like lines. Keep roughly that level of detail unless the document clearly repeats or conflicts with itself."
        : " Treat the uploaded file as a detailed working plan, not a short outline.";
    final previewInstruction = hasPreview
        ? " A preview of the uploaded document is included below, and the backend will also parse the raw file so you can preserve the full task list."
        : " The backend must parse the raw uploaded file to recover the full task list before drafting.";
    final previewBlock = hasPreview
        ? "\n\nDOCUMENT PREVIEW START\n$truncatedText\nDOCUMENT PREVIEW END"
        : "";
    return "Generate a lifecycle-safe production draft for $safeProduct at $safeEstate. Use the uploaded planning document as the primary source material. Preserve explicit phase names, task titles, sequencing, durations, staffing counts, day-by-day lines, and operational notes where they are coherent. Keep the draft scoped to the current business domain ${draft.domainContext}.$dateInstruction$plantingInstruction$currentPhaseInstruction$currentNotesInstruction Do not collapse a task-rich working document into a sparse phase summary. Normalize it into clean editable phases and tasks while keeping the original scope and density.$densityInstruction$previewInstruction Source document: $safeFileName.$previewBlock";
  }

  String _extractImportableDocumentText({
    required List<int> bytes,
    required String filename,
  }) {
    final extension = _extractImportFileExtension(filename);
    switch (extension) {
      case "html":
      case "htm":
        return _normalizeImportedDocumentText(
          _stripHtmlTags(utf8.decode(bytes, allowMalformed: true)),
        );
      case "txt":
        return _normalizeImportedDocumentText(
          utf8.decode(bytes, allowMalformed: true),
        );
      case "pdf":
        return _normalizeImportedDocumentText(_extractTextFromPdfBytes(bytes));
      default:
        return _normalizeImportedDocumentText(
          utf8.decode(bytes, allowMalformed: true),
        );
    }
  }

  String _extractImportFileExtension(String filename) {
    final segments = filename.trim().toLowerCase().split(".");
    return segments.length < 2 ? "" : segments.last.trim();
  }

  String _stripHtmlTags(String rawHtml) {
    return rawHtml
        .replaceAll(
          RegExp(
            r"<script[^>]*>.*?</script>",
            caseSensitive: false,
            dotAll: true,
          ),
          " ",
        )
        .replaceAll(
          RegExp(
            r"<style[^>]*>.*?</style>",
            caseSensitive: false,
            dotAll: true,
          ),
          " ",
        )
        .replaceAll(RegExp(r"<br\s*/?>", caseSensitive: false), "\n")
        .replaceAll(RegExp(r"</p>", caseSensitive: false), "\n")
        .replaceAll(RegExp(r"<[^>]+>"), " ")
        .replaceAll("&nbsp;", " ")
        .replaceAll("&amp;", "&")
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&quot;", "\"")
        .replaceAll("&#39;", "'");
  }

  String _normalizeImportedDocumentText(String rawText) {
    final cleaned = rawText
        .replaceAll(RegExp(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]"), " ")
        .replaceAll(RegExp(r"[ \t]+"), " ");
    final lines = cleaned
        .split(RegExp(r"[\r\n]+"))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join("\n");
  }

  int _estimateImportedTaskLikeLineCount(String rawText) {
    final lines = _normalizeImportedDocumentText(rawText)
        .split("\n")
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final bulletPattern = RegExp(r"^(\d+[\).:-]|[-*•])\s+");
    final dayPattern = RegExp(r"^(day|week)\s*\d+", caseSensitive: false);
    final taskPattern = RegExp(
      r"\b(task|activity|operation|monitor|inspect|apply|transplant|plant|seed|seedling|harvest|spray|prune|scout|irrigat|fertigat|weed|pest|disease|pack|grade|record|clean|trellis|stake)\b",
      caseSensitive: false,
    );
    return lines.where((line) {
      final normalized = line.toLowerCase();
      if (normalized.length < 6 || normalized.length > 180) {
        return false;
      }
      if (RegExp(
        r"^(page|title|estate|crop|start date|end date|notes|manager notes|last saved|project days|tasks|phase allocation)",
        caseSensitive: false,
      ).hasMatch(normalized)) {
        return false;
      }
      return bulletPattern.hasMatch(line) ||
          dayPattern.hasMatch(normalized) ||
          taskPattern.hasMatch(normalized);
    }).length;
  }

  String _extractTextFromPdfBytes(List<int> bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final collected = <String>[];

    void collectFragment(String rawFragment) {
      final decoded = _decodePdfLiteralString(rawFragment).trim();
      if (decoded.isEmpty || decoded.length < 2) {
        return;
      }
      collected.add(decoded);
    }

    final literalPattern = RegExp(r"\(((?:\\.|[^\\()])*)\)\s*Tj");
    for (final match in literalPattern.allMatches(raw)) {
      final fragment = match.group(1);
      if (fragment != null) {
        collectFragment(fragment);
      }
    }

    final arrayPattern = RegExp(r"\[(.*?)\]\s*TJ", dotAll: true);
    for (final match in arrayPattern.allMatches(raw)) {
      final arrayText = match.group(1) ?? "";
      for (final inner in RegExp(
        r"\(((?:\\.|[^\\()])*)\)",
      ).allMatches(arrayText)) {
        final fragment = inner.group(1);
        if (fragment != null) {
          collectFragment(fragment);
        }
      }
    }

    if (collected.isNotEmpty) {
      return collected.join("\n");
    }

    final printableRuns = RegExp(r"[A-Za-z][A-Za-z0-9 ,.;:()/_\-]{24,}")
        .allMatches(raw)
        .map((match) => match.group(0)?.trim() ?? "")
        .where((line) {
          return line.isNotEmpty;
        })
        .toList();
    return printableRuns.join("\n");
  }

  String _decodePdfLiteralString(String value) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < value.length) {
      final current = value[index];
      if (current != "\\") {
        buffer.write(current);
        index += 1;
        continue;
      }
      if (index + 1 >= value.length) {
        break;
      }
      final next = value[index + 1];
      switch (next) {
        case "n":
          buffer.write("\n");
          index += 2;
          break;
        case "r":
          buffer.write("\r");
          index += 2;
          break;
        case "t":
          buffer.write("\t");
          index += 2;
          break;
        case "b":
          buffer.write("\b");
          index += 2;
          break;
        case "f":
          buffer.write("\f");
          index += 2;
          break;
        case "\\":
        case "(":
        case ")":
          buffer.write(next);
          index += 2;
          break;
        default:
          final octalMatch = RegExp(
            r"^[0-7]{1,3}",
          ).matchAsPrefix(value.substring(index + 1));
          if (octalMatch != null) {
            final octalValue = int.tryParse(octalMatch.group(0)!, radix: 8);
            if (octalValue != null) {
              buffer.writeCharCode(octalValue);
              index += 1 + octalMatch.group(0)!.length;
              break;
            }
          }
          buffer.write(next);
          index += 2;
          break;
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final planId = (widget.planId ?? "").trim();
    final draft = ref.watch(productionPlanDraftProvider);
    final schedulePolicyAsync = ref.watch(
      productionSchedulePolicyProvider(draft.estateAssetId),
    );
    _syncControllers(draft);

    final assetsAsync = ref.watch(
      businessAssetsProvider(
        const BusinessAssetsQuery(
          page: _draftAssetQueryPage,
          limit: _draftAssetQueryLimit,
        ),
      ),
    );
    final detailAsync = planId.isEmpty
        ? const AsyncValue<ProductionPlanDetail?>.data(null)
        : ref.watch(productionPlanDetailProvider(planId)).whenData((value) {
            _hydrateDraftFromDetail(value);
            return value;
          });
    final planUnitsAsync = planId.isEmpty
        ? const AsyncValue<ProductionPlanUnitsResponse?>.data(null)
        : ref.watch(productionPlanUnitsProvider(planId)).whenData((value) {
            return value;
          });
    final staffAsync = ref.watch(productionStaffProvider);
    final staffList =
        staffAsync.valueOrNull ?? const <BusinessStaffProfileSummary>[];
    final staffById = <String, BusinessStaffProfileSummary>{
      for (final profile in staffList)
        if (profile.id.trim().isNotEmpty) profile.id.trim(): profile,
    };
    final session = ref.watch(authSessionProvider);
    // WHY: Staff directory access is narrower than draft editing, so use the
    // authenticated profile role first and only fall back to email matching.
    final profileAsync = ref.watch(userProfileProvider);
    final selfStaffRole = _resolveSelfStaffRole(
      profileStaffRole: profileAsync.valueOrNull?.staffRole,
      staffList: staffList,
      userEmail: session?.user.email,
    );
    final canEditDraft = _canEditDraft(
      actorRole: session?.user.role ?? "",
      staffRole: selfStaffRole,
    );
    final canManageLifecycle = _canManageDraftLifecycle(
      actorRole: session?.user.role ?? "",
      staffRole: selfStaffRole,
    );
    final existingPlanStatus =
        detailAsync.valueOrNull?.plan.status.trim().toLowerCase() ?? "";
    final isExistingPlanLoadedForSave =
        planId.isEmpty || detailAsync.valueOrNull != null;
    final savesIntoExistingDraft =
        planId.isEmpty || existingPlanStatus == "draft";
    final saveDraftLabel = savesIntoExistingDraft
        ? "Save draft"
        : "Save draft copy";
    final canStartProduction =
        canManageLifecycle &&
        (planId.isEmpty ||
            existingPlanStatus.isEmpty ||
            existingPlanStatus == "draft");
    final canReturnToDraft =
        planId.isNotEmpty &&
        canManageLifecycle &&
        (existingPlanStatus == "active" || existingPlanStatus == "paused");
    final presenceState = planId.isEmpty
        ? null
        : ref.watch(productionDraftPresenceProvider(planId));
    final currentViewer = _buildCurrentPresenceViewer(
      session: session,
      profileName: profileAsync.valueOrNull?.name ?? "",
      profileEmail: profileAsync.valueOrNull?.email ?? "",
      profileStaffRole: profileAsync.valueOrNull?.staffRole,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Production draft editor"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlansRoute);
          },
        ),
        actions: [
          if (planId.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(productionPlanDetailProvider(planId));
                setState(() {
                  _hydratedPlanId = null;
                });
              },
            ),
          FilledButton.icon(
            onPressed:
                canEditDraft &&
                    isExistingPlanLoadedForSave &&
                    !_isSaving &&
                    !_isRefiningDraft &&
                    !_isImportingDraftDocument &&
                    !_isDownloadingDraft &&
                    !_isAssigningDraftStaff
                ? () => _saveDraft(existingPlanStatus: existingPlanStatus)
                : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saveDraftLabel),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(_pagePadding),
            child: Text(error.toString()),
          ),
        ),
        data: (detail) {
          final workScope = _resolveDraftWorkScopeSummary(
            draft: draft,
            detail: detail,
            planUnitsResponse: planUnitsAsync.valueOrNull,
          );
          final selectedEstateName = assetsAsync.maybeWhen(
            data: (result) {
              for (final asset in result.assets) {
                if (asset.id == draft.estateAssetId) {
                  return asset.name;
                }
              }
              return "";
            },
            orElse: () => "",
          );
          final selectedProductName = _resolveDraftProductName(draft);

          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                if (planId.isEmpty) {
                  return;
                }
                setState(() {
                  _hydratedPlanId = null;
                });
                final refreshedDetail = await ref.refresh(
                  productionPlanDetailProvider(planId).future,
                );
                _hydrateDraftFromDetail(refreshedDetail);
              },
              child: ListView(
                padding: const EdgeInsets.all(_pagePadding),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1520),
                      child: Column(
                        children: [
                          _DraftPresenceBanner(
                            currentViewer: currentViewer,
                            remoteViewers:
                                presenceState?.viewers ??
                                const <ProductionDraftPresenceViewer>[],
                            isConnected: presenceState?.isConnected ?? false,
                            isSharedRoom: planId.isNotEmpty,
                            errorMessage: presenceState?.error,
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _DraftEditorSummaryCard(
                            draft: draft,
                            selectedEstateName: selectedEstateName,
                            selectedProductName: selectedProductName,
                            detail: detail,
                            canEditDraft: canEditDraft,
                            actionBar: canEditDraft
                                ? Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      if (canStartProduction)
                                        FilledButton.icon(
                                          onPressed:
                                              _isSaving ||
                                                  _isRefiningDraft ||
                                                  _isImportingDraftDocument ||
                                                  _isDownloadingDraft ||
                                                  _isAssigningDraftStaff
                                              ? null
                                              : () => _startProduction(
                                                  existingPlanStatus:
                                                      existingPlanStatus,
                                                ),
                                          icon: _isSaving
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.play_arrow_outlined,
                                                ),
                                          label: const Text("Start production"),
                                        ),
                                      if (canReturnToDraft)
                                        OutlinedButton.icon(
                                          onPressed:
                                              _isSaving ||
                                                  _isRefiningDraft ||
                                                  _isImportingDraftDocument ||
                                                  _isDownloadingDraft ||
                                                  _isAssigningDraftStaff
                                              ? null
                                              : _returnPlanToDraft,
                                          icon: const Icon(
                                            Icons.edit_calendar_outlined,
                                          ),
                                          label: const Text("Return to draft"),
                                        ),
                                      FilledButton.tonalIcon(
                                        onPressed:
                                            _isSaving ||
                                                _isRefiningDraft ||
                                                _isImportingDraftDocument ||
                                                _isDownloadingDraft ||
                                                _isAssigningDraftStaff
                                            ? null
                                            : () => _refineDraftWithAi(
                                                draft: draft,
                                                selectedEstateName:
                                                    selectedEstateName,
                                                selectedProductName:
                                                    selectedProductName,
                                                staffById: staffById,
                                              ),
                                        icon: _isRefiningDraft
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.auto_fix_high_outlined,
                                              ),
                                        label: Text(
                                          _isRefiningDraft
                                              ? "Refining..."
                                              : "Refine with AI",
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed:
                                            _isSaving ||
                                                _isRefiningDraft ||
                                                _isImportingDraftDocument ||
                                                _isDownloadingDraft ||
                                                _isAssigningDraftStaff
                                            ? null
                                            : () => _populateDraftFromDocument(
                                                draft: draft,
                                                selectedEstateName:
                                                    selectedEstateName,
                                                selectedProductName:
                                                    selectedProductName,
                                              ),
                                        icon: _isImportingDraftDocument
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.picture_as_pdf_outlined,
                                              ),
                                        label: Text(
                                          _isImportingDraftDocument
                                              ? "Populating..."
                                              : "Populate draft",
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed:
                                            _isSaving ||
                                                _isRefiningDraft ||
                                                _isImportingDraftDocument ||
                                                _isDownloadingDraft ||
                                                _isAssigningDraftStaff
                                            ? null
                                            : () => _assignDraftStaff(
                                                draft: draft,
                                                staffList: staffList,
                                              ),
                                        icon: _isAssigningDraftStaff
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.group_add_outlined,
                                              ),
                                        label: Text(
                                          _isAssigningDraftStaff
                                              ? "Assigning..."
                                              : "Assign staff",
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed:
                                            _isSaving ||
                                                _isRefiningDraft ||
                                                _isImportingDraftDocument ||
                                                _isDownloadingDraft ||
                                                _isAssigningDraftStaff
                                            ? null
                                            : () => _downloadDraftFile(
                                                draft: draft,
                                                selectedEstateName:
                                                    selectedEstateName,
                                                selectedProductName:
                                                    selectedProductName,
                                                staffById: staffById,
                                                detail: detail,
                                              ),
                                        icon: _isDownloadingDraft
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.download_outlined,
                                              ),
                                        label: Text(
                                          _isDownloadingDraft
                                              ? "Downloading..."
                                              : "Download draft",
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                          const SizedBox(height: _sectionSpacing),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final useColumn = constraints.maxWidth < 1180;
                              final useMobileSections =
                                  constraints.maxWidth < 860;
                              final layoutMode = useMobileSections
                                  ? "mobile"
                                  : useColumn
                                  ? "stacked"
                                  : "split";
                              _logLayoutDecision(layoutMode);
                              final taskTable = _DraftEditorTaskCard(
                                draft: draft,
                                staffList: staffList,
                                schedulePolicy:
                                    schedulePolicyAsync.valueOrNull?.policy,
                              );
                              final interactiveTaskTable = canEditDraft
                                  ? taskTable
                                  : IgnorePointer(
                                      child: Opacity(
                                        opacity: 0.7,
                                        child: taskTable,
                                      ),
                                    );
                              final sidePanel = _DraftEditorSidePanel(
                                draft: draft,
                                canEditDraft: canEditDraft,
                                titleCtrl: _titleCtrl,
                                notesCtrl: _notesCtrl,
                                plannedPlantingCtrl: _plannedPlantingCtrl,
                                plannedPlantingUnitCtrl:
                                    _plannedPlantingUnitCtrl,
                                estimatedHarvestCtrl: _estimatedHarvestCtrl,
                                estimatedHarvestUnitCtrl:
                                    _estimatedHarvestUnitCtrl,
                                workScope: workScope,
                                onPickStartDate: canEditDraft
                                    ? () => _pickDate(isStart: true)
                                    : null,
                                onPickEndDate: canEditDraft
                                    ? () => _pickDate(isStart: false)
                                    : null,
                                onPlantingMaterialChanged: canEditDraft
                                    ? (value) {
                                        ref
                                            .read(
                                              productionPlanDraftProvider
                                                  .notifier,
                                            )
                                            .updatePlantingMaterialType(value);
                                      }
                                    : null,
                                draftAuditLog:
                                    detail?.draftAuditLog ??
                                    const <ProductionDraftAuditEntry>[],
                                draftRevisions:
                                    detail?.draftRevisions ??
                                    const <ProductionDraftRevisionSummary>[],
                              );

                              if (useMobileSections) {
                                final mobileBody =
                                    _mobileSection ==
                                        _DraftEditorMobileSection.tasks
                                    ? interactiveTaskTable
                                    : sidePanel;
                                return Column(
                                  children: [
                                    _DraftEditorMobileSectionToggle(
                                      selected: _mobileSection,
                                      onChanged: (value) {
                                        AppDebug.log(
                                          _draftEditorLogTag,
                                          _logMobileSectionChanged,
                                          extra: <String, Object?>{
                                            _extraMobileSectionKey: value.name,
                                          },
                                        );
                                        setState(() {
                                          _mobileSection = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: _sectionSpacing),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      child: KeyedSubtree(
                                        key: ValueKey(_mobileSection),
                                        child: mobileBody,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              if (useColumn) {
                                return Column(
                                  children: [
                                    interactiveTaskTable,
                                    const SizedBox(height: _sectionSpacing),
                                    sidePanel,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 7,
                                    child: interactiveTaskTable,
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 4, child: sidePanel),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DraftEditorSummaryCard extends StatelessWidget {
  final ProductionPlanDraftState draft;
  final String selectedEstateName;
  final String selectedProductName;
  final ProductionPlanDetail? detail;
  final bool canEditDraft;
  final Widget? actionBar;

  const _DraftEditorSummaryCard({
    required this.draft,
    required this.selectedEstateName,
    required this.selectedProductName,
    required this.detail,
    required this.canEditDraft,
    this.actionBar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastSavedLabel = detail?.plan.lastDraftSavedBy?.displayLabel ?? "";
    final metrics = _DraftEditorLayoutMetrics.fromDraft(draft);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 720;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Production draft editor",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    draft.title.trim().isEmpty
                        ? "Untitled draft"
                        : draft.title.trim(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Review the entire draft, move phase by phase, and expand a task only when you need its editing controls. Secondary planning context stays in the support rail.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              );
              final revisionChip = detail == null
                  ? null
                  : Chip(
                      avatar: const Icon(Icons.history_outlined, size: 16),
                      label: Text(
                        "${detail!.plan.draftRevisionCount} saved revision${detail!.plan.draftRevisionCount == 1 ? '' : 's'}",
                      ),
                    );
              if (useColumn) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    if (revisionChip != null) ...[
                      const SizedBox(height: 14),
                      revisionChip,
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  if (revisionChip != null) ...[
                    const SizedBox(width: 12),
                    revisionChip,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryChip(
                icon: Icons.location_on_outlined,
                label: selectedEstateName.trim().isEmpty
                    ? "Estate not selected"
                    : selectedEstateName,
              ),
              _SummaryChip(
                icon: Icons.spa_outlined,
                label: selectedProductName.trim().isEmpty
                    ? "Crop not selected"
                    : selectedProductName,
              ),
              _SummaryChip(
                icon: Icons.schedule_outlined,
                label: draft.startDate != null && draft.endDate != null
                    ? "${formatDateLabel(draft.startDate)} → ${formatDateLabel(draft.endDate)}"
                    : "Dates pending",
              ),
              if (productionDomainRequiresPlantingTargets(draft.domainContext))
                _SummaryChip(
                  icon: Icons.grass_outlined,
                  label: draft.plantingTargets.isComplete
                      ? "${_formatQuantity(draft.plantingTargets.plannedPlantingQuantity)} ${draft.plantingTargets.plannedPlantingUnit} ${formatProductionPlantingMaterialType(draft.plantingTargets.materialType).toLowerCase()} → ${_formatQuantity(draft.plantingTargets.estimatedHarvestQuantity)} ${draft.plantingTargets.estimatedHarvestUnit}"
                      : "Planting baseline pending",
                ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final wideTile = constraints.maxWidth >= 980;
              final tileWidth = wideTile
                  ? (constraints.maxWidth - 36) / 4
                  : math.min(constraints.maxWidth, 220.0);
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _DraftHeroMetricTile(
                      label: "Phases",
                      value: metrics.phaseCount.toString(),
                      helper: "Stage groups",
                      icon: Icons.alt_route_outlined,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _DraftHeroMetricTile(
                      label: "Tasks",
                      value: metrics.totalTasks.toString(),
                      helper: "Editable workload",
                      icon: Icons.checklist_rtl_outlined,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _DraftHeroMetricTile(
                      label: "Needs staff",
                      value: metrics.unassignedTasks.toString(),
                      helper: "Unassigned tasks",
                      icon: Icons.person_search_outlined,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _DraftHeroMetricTile(
                      label: "Project days",
                      value: metrics.totalProjectDays.toString(),
                      helper: metrics.totalProjectDays == 0
                          ? "Dates missing"
                          : "Schedule window",
                      icon: Icons.calendar_month_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
          if (detail != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                detail!.plan.lastDraftSavedAt == null
                    ? "This draft has not been saved yet."
                    : "Last saved ${formatDateTimeLabel(detail!.plan.lastDraftSavedAt)}${lastSavedLabel.trim().isEmpty ? '' : ' by $lastSavedLabel'}.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (actionBar != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: actionBar!,
            ),
          ],
          if (!canEditDraft) ...[
            const SizedBox(height: 14),
            Text(
              "Draft editing is restricted to estate managers, farm managers, asset managers, and the business owner.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DraftPresenceBanner extends StatelessWidget {
  final ProductionDraftPresenceViewer currentViewer;
  final List<ProductionDraftPresenceViewer> remoteViewers;
  final bool isConnected;
  final bool isSharedRoom;
  final String? errorMessage;

  const _DraftPresenceBanner({
    required this.currentViewer,
    required this.remoteViewers,
    required this.isConnected,
    required this.isSharedRoom,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewers = _mergeDraftPresenceViewers(
      currentViewer: currentViewer,
      remoteViewers: remoteViewers,
    );
    final viewerCount = viewers.length;
    final statusColor = isSharedRoom
        ? (isConnected ? AppColors.productionAccent : AppColors.tenantAccent)
        : theme.colorScheme.tertiary;
    final statusLabel = !isSharedRoom
        ? "Local draft"
        : isConnected
        ? "Live"
        : "Connecting";
    final statusBackground = statusColor.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.24 : 0.12,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = constraints.maxWidth < 760;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Currently viewing",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "$viewerCount viewer${viewerCount == 1 ? '' : 's'} on this draft",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSharedRoom
                        ? "Live room presence updates while the draft is open."
                        : "Showing the signed-in account tied to this draft.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );

              final statusChip = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.42),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isConnected
                          ? Icons.wifi_tethering_outlined
                          : Icons.wifi_off_outlined,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );

              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 12),
                    statusChip,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 12),
                  statusChip,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: viewers
                .map(
                  (viewer) => _DraftPresenceViewerChip(
                    viewer: viewer,
                    isSelf:
                        _draftPresenceViewerKey(viewer) ==
                        _draftPresenceViewerKey(currentViewer),
                  ),
                )
                .toList(),
          ),
          if ((errorMessage ?? "").trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              "Live presence is not connected yet. Showing the current viewer and draft state only.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DraftPresenceViewerChip extends StatelessWidget {
  final ProductionDraftPresenceViewer viewer;
  final bool isSelf;

  const _DraftPresenceViewerChip({required this.viewer, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _resolveDraftPresenceAccentColor(theme, viewer.roleKey);
    final background = accent.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12,
    );
    final initials = _presenceViewerInitials(viewer.resolvedDisplayName);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent.withValues(alpha: isSelf ? 0.72 : 0.42),
            width: isSelf ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          viewer.resolvedDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.24
                                  : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            "You",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    viewer.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftEditorTaskCard extends StatelessWidget {
  final ProductionPlanDraftState draft;
  final List<BusinessStaffProfileSummary> staffList;
  final ProductionSchedulePolicy? schedulePolicy;

  const _DraftEditorTaskCard({
    required this.draft,
    required this.staffList,
    required this.schedulePolicy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = constraints.maxWidth < 980;
              final summaryChip = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  "${draft.phases.length} phases • ${draft.phases.fold<int>(0, (count, phase) => count + phase.tasks.length)} tasks",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
              final intro = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Phase workspace",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Stay in one phase at a time, scan full task names without truncation, and expand cards only when you need to edit deeper fields.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              );
              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [intro, const SizedBox(height: 14), summaryChip],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: intro),
                  const SizedBox(width: 18),
                  summaryChip,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          ProductionPlanTaskTable(
            draft: draft,
            staff: staffList,
            schedulePolicy: schedulePolicy,
            showPhaseNavigator: true,
            onAddTask: (phaseIndex) {
              final notifier = ProviderScope.containerOf(
                context,
                listen: false,
              ).read(productionPlanDraftProvider.notifier);
              notifier.addTask(phaseIndex);
            },
            onAddTaskAt:
                (
                  phaseIndex,
                  taskIndex,
                  day,
                  suggestedStart,
                  suggestedDue,
                ) async {
                  final notifier = ProviderScope.containerOf(
                    context,
                    listen: false,
                  ).read(productionPlanDraftProvider.notifier);
                  final taskId = notifier.addTaskAt(phaseIndex, taskIndex);
                  if (taskId == null) {
                    return;
                  }
                  notifier.updateTaskSchedule(
                    phaseIndex,
                    taskId,
                    startDate: suggestedStart,
                    dueDate: suggestedDue,
                  );
                },
            onRemoveTask: (phaseIndex, taskId) {
              final notifier = ProviderScope.containerOf(
                context,
                listen: false,
              ).read(productionPlanDraftProvider.notifier);
              notifier.removeTask(phaseIndex, taskId);
            },
          ),
        ],
      ),
    );
  }
}

class _DraftEditorMobileSectionToggle extends StatelessWidget {
  final _DraftEditorMobileSection selected;
  final ValueChanged<_DraftEditorMobileSection> onChanged;

  const _DraftEditorMobileSectionToggle({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: SegmentedButton<_DraftEditorMobileSection>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<_DraftEditorMobileSection>(
            value: _DraftEditorMobileSection.tasks,
            icon: Icon(Icons.view_list_outlined),
            label: Text("Workspace"),
          ),
          ButtonSegment<_DraftEditorMobileSection>(
            value: _DraftEditorMobileSection.details,
            icon: Icon(Icons.tune_outlined),
            label: Text("Support"),
          ),
        ],
        selected: <_DraftEditorMobileSection>{selected},
        onSelectionChanged: (next) => onChanged(next.first),
      ),
    );
  }
}

class _DraftEditorSidePanel extends StatefulWidget {
  final ProductionPlanDraftState draft;
  final bool canEditDraft;
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  final TextEditingController plannedPlantingCtrl;
  final TextEditingController plannedPlantingUnitCtrl;
  final TextEditingController estimatedHarvestCtrl;
  final TextEditingController estimatedHarvestUnitCtrl;
  final _DraftWorkScopeSummary workScope;
  final VoidCallback? onPickStartDate;
  final VoidCallback? onPickEndDate;
  final ValueChanged<String?>? onPlantingMaterialChanged;
  final List<ProductionDraftAuditEntry> draftAuditLog;
  final List<ProductionDraftRevisionSummary> draftRevisions;

  const _DraftEditorSidePanel({
    required this.draft,
    required this.canEditDraft,
    required this.titleCtrl,
    required this.notesCtrl,
    required this.plannedPlantingCtrl,
    required this.plannedPlantingUnitCtrl,
    required this.estimatedHarvestCtrl,
    required this.estimatedHarvestUnitCtrl,
    required this.workScope,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onPlantingMaterialChanged,
    required this.draftAuditLog,
    required this.draftRevisions,
  });

  @override
  State<_DraftEditorSidePanel> createState() => _DraftEditorSidePanelState();
}

class _DraftEditorSidePanelState extends State<_DraftEditorSidePanel> {
  _DraftEditorSupportTab _selectedTab = _DraftEditorSupportTab.overview;

  void _setSelectedTab(_DraftEditorSupportTab tab) {
    if (_selectedTab == tab) {
      return;
    }
    AppDebug.log(
      _draftEditorLogTag,
      _logSupportTabChanged,
      extra: <String, Object?>{_extraSupportTabKey: tab.name},
    );
    setState(() {
      _selectedTab = tab;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = _DraftEditorLayoutMetrics.fromDraft(widget.draft);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Support rail",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Keep plan context, targets, and audit history here so the editing canvas stays focused on task work.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_DraftEditorSupportTab>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<_DraftEditorSupportTab>(
                value: _DraftEditorSupportTab.overview,
                icon: Icon(Icons.notes_outlined),
                label: Text("Overview"),
              ),
              ButtonSegment<_DraftEditorSupportTab>(
                value: _DraftEditorSupportTab.targets,
                icon: Icon(Icons.stacked_bar_chart_outlined),
                label: Text("Targets"),
              ),
              ButtonSegment<_DraftEditorSupportTab>(
                value: _DraftEditorSupportTab.history,
                icon: Icon(Icons.history_outlined),
                label: Text("History"),
              ),
            ],
            selected: <_DraftEditorSupportTab>{_selectedTab},
            onSelectionChanged: (next) => _setSelectedTab(next.first),
          ),
          const SizedBox(height: 18),
          _DraftHeroMetricTile(
            label: "Support snapshot",
            value: "${metrics.phaseCount} phases / ${metrics.totalTasks} tasks",
            helper: metrics.unassignedTasks == 0
                ? "Everything assigned is visible in the workspace."
                : "${metrics.unassignedTasks} tasks still need staffing.",
            icon: Icons.dashboard_customize_outlined,
          ),
          const SizedBox(height: 12),
          _DraftHeroMetricTile(
            label: "Work scope",
            value: widget.workScope.valueLabel,
            helper: widget.workScope.helperText,
            icon: Icons.grid_view_outlined,
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey(_selectedTab),
              child: switch (_selectedTab) {
                _DraftEditorSupportTab.overview => _DraftEditorOverviewTab(
                  draft: widget.draft,
                  canEditDraft: widget.canEditDraft,
                  titleCtrl: widget.titleCtrl,
                  notesCtrl: widget.notesCtrl,
                  onPickStartDate: widget.onPickStartDate,
                  onPickEndDate: widget.onPickEndDate,
                ),
                _DraftEditorSupportTab.targets => _DraftEditorTargetsTab(
                  draft: widget.draft,
                  canEditDraft: widget.canEditDraft,
                  plannedPlantingCtrl: widget.plannedPlantingCtrl,
                  plannedPlantingUnitCtrl: widget.plannedPlantingUnitCtrl,
                  estimatedHarvestCtrl: widget.estimatedHarvestCtrl,
                  estimatedHarvestUnitCtrl: widget.estimatedHarvestUnitCtrl,
                  onPlantingMaterialChanged: widget.onPlantingMaterialChanged,
                ),
                _DraftEditorSupportTab.history => _DraftEditorHistoryTab(
                  draftAuditLog: widget.draftAuditLog,
                  draftRevisions: widget.draftRevisions,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftEditorOverviewTab extends StatelessWidget {
  final ProductionPlanDraftState draft;
  final bool canEditDraft;
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  final VoidCallback? onPickStartDate;
  final VoidCallback? onPickEndDate;

  const _DraftEditorOverviewTab({
    required this.draft,
    required this.canEditDraft,
    required this.titleCtrl,
    required this.notesCtrl,
    required this.onPickStartDate,
    required this.onPickEndDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>("overview"),
      children: [
        _SupportSectionCard(
          title: "Plan details",
          description:
              "These fields describe the draft itself. They are editable, but they should not distract from day-to-day task editing.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                enabled: canEditDraft,
                decoration: const InputDecoration(
                  labelText: "Plan title",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                enabled: canEditDraft,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: "Manager notes",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _sectionSpacing),
        _SupportSectionCard(
          title: "Schedule window",
          description:
              "Dates define the live production window used by the phase workspace and export output.",
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: canEditDraft ? onPickStartDate : null,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  draft.startDate == null
                      ? "Set start date"
                      : formatDateLabel(draft.startDate),
                ),
              ),
              OutlinedButton.icon(
                onPressed: canEditDraft ? onPickEndDate : null,
                icon: const Icon(Icons.event_available_outlined),
                label: Text(
                  draft.endDate == null
                      ? "Set end date"
                      : formatDateLabel(draft.endDate),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DraftEditorTargetsTab extends StatelessWidget {
  final ProductionPlanDraftState draft;
  final bool canEditDraft;
  final TextEditingController plannedPlantingCtrl;
  final TextEditingController plannedPlantingUnitCtrl;
  final TextEditingController estimatedHarvestCtrl;
  final TextEditingController estimatedHarvestUnitCtrl;
  final ValueChanged<String?>? onPlantingMaterialChanged;

  const _DraftEditorTargetsTab({
    required this.draft,
    required this.canEditDraft,
    required this.plannedPlantingCtrl,
    required this.plannedPlantingUnitCtrl,
    required this.estimatedHarvestCtrl,
    required this.estimatedHarvestUnitCtrl,
    required this.onPlantingMaterialChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!productionDomainRequiresPlantingTargets(draft.domainContext)) {
      return const _SupportSectionCard(
        key: ValueKey<String>("targets-empty"),
        title: "Delivery targets",
        description:
            "This production domain does not require planting-baseline fields.",
        child: Text("No planting baseline is required for this draft."),
      );
    }

    return _SupportSectionCard(
      key: const ValueKey<String>("targets"),
      title: "Planting baseline",
      description:
          "These targets drive downstream progress tracking for planting, transplanting, and harvest activity in live production.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: draft.plantingTargets.materialType.trim().isEmpty
                ? null
                : draft.plantingTargets.materialType,
            decoration: const InputDecoration(
              labelText: "Planting material",
              border: OutlineInputBorder(),
            ),
            items: productionPlantingMaterialTypeValues
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(formatProductionPlantingMaterialType(value)),
                  ),
                )
                .toList(),
            onChanged: canEditDraft ? onPlantingMaterialChanged : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: plannedPlantingCtrl,
            enabled: canEditDraft,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: "Planned planting quantity",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: plannedPlantingUnitCtrl,
            enabled: canEditDraft,
            decoration: const InputDecoration(
              labelText: "Planned planting unit",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: estimatedHarvestCtrl,
            enabled: canEditDraft,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: "Estimated harvest quantity",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: estimatedHarvestUnitCtrl,
            enabled: canEditDraft,
            decoration: const InputDecoration(
              labelText: "Estimated harvest unit",
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftEditorHistoryTab extends StatelessWidget {
  final List<ProductionDraftAuditEntry> draftAuditLog;
  final List<ProductionDraftRevisionSummary> draftRevisions;

  const _DraftEditorHistoryTab({
    required this.draftAuditLog,
    required this.draftRevisions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>("history"),
      children: [
        _SupportSectionCard(
          title: "Revision trail",
          description:
              "Audit and saved revisions are preserved here, but they stay out of the way while you are actively editing tasks.",
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DraftHeroMetricTile(
                label: "Audit entries",
                value: draftAuditLog.length.toString(),
                helper: "Tracked save actions",
                icon: Icons.event_note_outlined,
              ),
              _DraftHeroMetricTile(
                label: "Saved revisions",
                value: draftRevisions.length.toString(),
                helper: "Recoverable draft states",
                icon: Icons.restore_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: _sectionSpacing),
        _HistoryCard(
          title: "Audit log",
          emptyLabel: "Save this draft to start an audit trail.",
          children: draftAuditLog.map((entry) {
            final actor = entry.actor?.displayLabel ?? "Unknown actor";
            return _HistoryRow(
              title: "${_sentenceCase(entry.action)} • $actor",
              subtitle: entry.createdAt == null
                  ? entry.note
                  : "${formatDateTimeLabel(entry.createdAt)}${entry.note.trim().isEmpty ? '' : ' • ${entry.note.trim()}'}",
            );
          }).toList(),
        ),
        const SizedBox(height: _sectionSpacing),
        _HistoryCard(
          title: "Saved revisions",
          emptyLabel: "No saved revisions yet.",
          children: draftRevisions.map((revision) {
            final actor = revision.actor?.displayLabel ?? "Unknown actor";
            final dateRange =
                revision.startDate != null && revision.endDate != null
                ? "${formatDateLabel(revision.startDate)} → ${formatDateLabel(revision.endDate)}"
                : "Dates pending";
            final savedAtLabel = revision.savedAt == null
                ? ""
                : " • ${formatDateTimeLabel(revision.savedAt)}";
            return _HistoryRow(
              title:
                  "Revision ${revision.revisionNumber} • $actor • ${revision.phaseCount} phases / ${revision.taskCount} tasks",
              subtitle:
                  "${revision.title.trim().isEmpty ? 'Untitled draft' : revision.title.trim()}$savedAtLabel • $dateRange",
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DraftHeroMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String helper;
  final IconData icon;

  const _DraftHeroMetricTile({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  helper,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportSectionCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _SupportSectionCard({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<Widget> children;

  const _HistoryCard({
    required this.title,
    required this.emptyLabel,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Text(
              emptyLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HistoryRow({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle.trim().isEmpty ? "No extra note." : subtitle.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

ProductionDraftPresenceViewer _buildCurrentPresenceViewer({
  required AuthSession? session,
  required String profileName,
  required String profileEmail,
  required String? profileStaffRole,
}) {
  final userId = session?.user.id.trim() ?? "";
  final sessionName = session?.user.name.trim() ?? "";
  final sessionEmail = session?.user.email.trim() ?? "";
  final sessionRole = session?.user.role.trim() ?? "";
  final trimmedProfileName = profileName.trim();
  final trimmedProfileEmail = profileEmail.trim();
  final resolvedName = trimmedProfileName.isNotEmpty
      ? trimmedProfileName
      : sessionName.isNotEmpty
      ? sessionName
      : trimmedProfileEmail.isNotEmpty
      ? trimmedProfileEmail
      : sessionEmail;
  final normalizedRole = normalizeDraftPresenceRoleKey(sessionRole);
  final resolvedStaffRole = normalizedRole == "staff"
      ? _normalizeNullableDraftPresenceRole(profileStaffRole)
      : null;

  return ProductionDraftPresenceViewer(
    userId: userId,
    displayName: resolvedName,
    email: trimmedProfileEmail.isNotEmpty ? trimmedProfileEmail : sessionEmail,
    accountRole: normalizedRole,
    staffRole: resolvedStaffRole,
  );
}

List<ProductionDraftPresenceViewer> _mergeDraftPresenceViewers({
  required ProductionDraftPresenceViewer currentViewer,
  required List<ProductionDraftPresenceViewer> remoteViewers,
}) {
  final merged = <String, ProductionDraftPresenceViewer>{};

  final currentKey = _draftPresenceViewerKey(currentViewer);
  if (currentKey.isNotEmpty) {
    merged[currentKey] = currentViewer;
  }

  for (final viewer in remoteViewers) {
    final key = _draftPresenceViewerKey(viewer);
    if (key.isEmpty) {
      continue;
    }
    merged[key] = viewer;
  }

  final viewers = merged.values.toList();
  viewers.sort((left, right) {
    final selfKey = currentKey;
    if (_draftPresenceViewerKey(left) == selfKey &&
        _draftPresenceViewerKey(right) != selfKey) {
      return -1;
    }
    if (_draftPresenceViewerKey(right) == selfKey &&
        _draftPresenceViewerKey(left) != selfKey) {
      return 1;
    }
    final nameCompare = left.resolvedDisplayName.compareTo(
      right.resolvedDisplayName,
    );
    if (nameCompare != 0) {
      return nameCompare;
    }
    return left.userId.compareTo(right.userId);
  });

  return viewers;
}

String _draftPresenceViewerKey(ProductionDraftPresenceViewer viewer) {
  final userId = viewer.userId.trim();
  if (userId.isNotEmpty) {
    return userId;
  }

  final displayName = viewer.resolvedDisplayName.trim();
  final roleKey = viewer.roleKey.trim();
  if (displayName.isEmpty && roleKey.isEmpty) {
    return "";
  }

  return "$displayName|$roleKey";
}

Color _resolveDraftPresenceAccentColor(ThemeData theme, String roleKey) {
  switch (normalizeDraftPresenceRoleKey(roleKey)) {
    case "business_owner":
      return AppColors.tertiary;
    case "estate_manager":
      return AppColors.analyticsAccent;
    case "farm_manager":
      return AppColors.productionAccent;
    case "asset_manager":
      return AppColors.commerceAccent;
    case "admin":
      return AppColors.recordsAccent;
    default:
      return theme.colorScheme.primary;
  }
}

String _presenceViewerInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r"\s+"))
      .where((word) => word.trim().isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return "?";
  }

  final first = words.first.trim();
  final second = words.length > 1 ? words[1].trim() : "";
  final buffer = StringBuffer();
  buffer.write(first.substring(0, 1));
  if (second.isNotEmpty) {
    buffer.write(second.substring(0, 1));
  } else if (first.length > 1) {
    buffer.write(first.substring(first.length - 1));
  }
  return buffer.toString().toUpperCase();
}

String? _normalizeNullableDraftPresenceRole(String? role) {
  final normalized = normalizeDraftPresenceRoleKey(role ?? "");
  return normalized.isEmpty ? null : normalized;
}

ProductionTaskStatus _taskStatusFromBackend(String rawStatus) {
  switch (rawStatus.trim().toLowerCase()) {
    case "done":
      return ProductionTaskStatus.done;
    case "in_progress":
      return ProductionTaskStatus.inProgress;
    case "blocked":
      return ProductionTaskStatus.blocked;
    default:
      return ProductionTaskStatus.notStarted;
  }
}

int _estimatePhaseDurationDays(ProductionPhase phase) {
  if (phase.startDate == null || phase.endDate == null) {
    return 1;
  }
  final difference = phase.endDate!.difference(phase.startDate!).inDays + 1;
  return difference < 1 ? 1 : difference;
}

double? _parseNullableDouble(String input) {
  final normalized = input.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}

String _formatQuantity(num? value) {
  if (value == null) {
    return "-";
  }
  final doubleValue = value.toDouble();
  if (doubleValue == doubleValue.roundToDouble()) {
    return doubleValue.toStringAsFixed(0);
  }
  return doubleValue.toStringAsFixed(2);
}

bool _canEditDraft({required String actorRole, required String? staffRole}) {
  final normalizedActorRole = _normalizeDraftAccessRole(actorRole);
  final normalizedStaffRole = _normalizeDraftAccessRole(staffRole ?? "");

  if (normalizedActorRole == "business_owner") {
    return true;
  }
  return normalizedActorRole == "staff" &&
      (normalizedStaffRole == "estate_manager" ||
          normalizedStaffRole == "farm_manager" ||
          normalizedStaffRole == "asset_manager");
}

bool _canManageDraftLifecycle({
  required String actorRole,
  required String? staffRole,
}) {
  final normalizedActorRole = _normalizeDraftAccessRole(actorRole);
  final normalizedStaffRole = _normalizeDraftAccessRole(staffRole ?? "");

  if (normalizedActorRole == "business_owner") {
    return true;
  }
  return normalizedActorRole == "staff" &&
      normalizedStaffRole == "estate_manager";
}

String? _resolveSelfStaffRole({
  required String? profileStaffRole,
  required List<BusinessStaffProfileSummary> staffList,
  required String? userEmail,
}) {
  final directRole = _normalizeDraftAccessRole(profileStaffRole ?? "");
  if (directRole.isNotEmpty) {
    return directRole;
  }

  final normalizedEmail = (userEmail ?? "").trim().toLowerCase();
  if (normalizedEmail.isEmpty) {
    return null;
  }
  for (final profile in staffList) {
    final profileEmail = (profile.userEmail ?? "").trim().toLowerCase();
    if (profileEmail.isNotEmpty && profileEmail == normalizedEmail) {
      return profile.staffRole;
    }
  }
  return null;
}

String _normalizeDraftAccessRole(String rawRole) {
  return rawRole.trim().toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
}

String _sentenceCase(String value) {
  final words = value
      .trim()
      .split(RegExp(r"[_\s]+"))
      .where((word) => word.trim().isNotEmpty)
      .map((word) {
        final lower = word.toLowerCase();
        return "${lower[0].toUpperCase()}${lower.substring(1)}";
      })
      .toList();
  return words.join(" ");
}
