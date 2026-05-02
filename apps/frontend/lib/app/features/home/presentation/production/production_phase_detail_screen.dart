/// WHAT: Renders the production phase detail screen, task filters, and daily
/// execution cards for a single production phase.
/// WHY: Operations teams need a current-day view of phase work without drilling
/// into each task or inheriting stale filter defaults from old activity.
/// HOW: The screen watches plan detail state, derives local task groupings, and
/// applies lightweight responsive filter controls before rendering the cards.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_viewer.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _logTag = "PRODUCTION_PHASE_DETAIL";
const String _buildLog = "build()";
const String _refreshAction = "refreshPhaseDetail()";
const String _searchAction = "updateSearchQuery()";
const String _searchVisibilityAction = "toggleSearchVisibility()";
const String _dateFilterAction = "updateDateFilter()";
const String _statusFilterAction = "updateStatusFilter()";
const String _sortAction = "updateSort()";
const String _rowTapAction = "openTaskDetail()";
const String _proofPreviewAction = "openProofPreview()";
const String _createPhaseDayTaskAction = "createPhaseDayTask()";
const String _createPhaseDayTaskFailure = "createPhaseDayTask() failed";

const String _screenTitle = "Phase detail";
const String _notFoundTitle = "Phase not found";
const String _notFoundMessage =
    "The requested phase is no longer available in this production plan.";
const String _noTasksTitle = "No tasks in this phase";
const String _noTasksMessage =
    "This phase does not have any scheduled tasks yet.";
const String _noMatchesTitle = "No tasks match this view";
const String _noMatchesMessage =
    "Try a different search term, filter, or sort to bring tasks back into view.";
const String _noDateMatchesTitle = "No tasks on this date";
const String _noDateMatchesMessage =
    "Pick another date or clear the date filter to see the rest of this phase.";
const String _heroSubtitle =
    "Review operational progress, proof-backed work, and the tasks still holding this phase open.";
const String _snapshotTitle = "Phase snapshot";
const String _snapshotSubtitle =
    "Compact operational KPIs for task volume, proof coverage, and completion.";
const String _progressTitle = "Overall progress";
const String _taskSectionTitle = "Operational tasks";
const String _taskSectionSubtitle =
    "Track ownership, proof, output, and approval without opening every task one by one.";
const String _phaseDayTaskCardTitle = "Add another day";
const String _phaseDayTaskCardSubtitle =
    "Create a task on a new operational day when this phase needs to run longer.";
const String _phaseDayTaskButtonLabel = "Add day task";
const String _phaseDayTaskDialogTitle = "Add task to phase day";
const String _phaseDayTaskDialogHelp =
    "Pick the day this phase needs, then create the task staff will work on that day.";
const String _phaseDayTaskDateLabel = "Task day";
const String _phaseDayTaskTitleLabel = "Task title";
const String _phaseDayTaskRoleLabel = "Role";
const String _phaseDayTaskExpectedLabel = "Expected work amount";
const String _phaseDayTaskHeadcountLabel = "Required headcount";
const String _phaseDayTaskStaffLabel = "Assign staff now";
const String _phaseDayTaskNotesLabel = "Task notes";
const String _phaseDayTaskSubmitLabel = "Create task";
const String _phaseDayTaskCancelLabel = "Cancel";
const String _phaseDayTaskTitleRequired = "Task title is required.";
const String _phaseDayTaskCreated = "Phase day task created.";
const String _phaseDayTaskCreateFailed = "Unable to create phase day task.";
const String _phaseDayTaskNoStaff =
    "No active staff are available for this role.";
const String _searchHint = "Search task, assignee, or status";
const String _searchLabel = "Search";
const String _dateLabel = "Date";
const String _allDatesLabel = "All dates";
const String _statusLabel = "Status";
const String _sortLabel = "Sort";
const String _allStatusesLabel = "All statuses";
const String _approvedLabel = "Approved / done";
const String _inProgressLabel = "In progress";
const String _assignedLabel = "Assigned / idle";
const String _attentionLabel = "Needs attention";
const String _latestActivityLabel = "Latest activity";
const String _dueDateLabel = "Due date";
const String _approvalStateLabel = "Approval state";
const String _totalTasksLabel = "Total tasks";
const String _doneInPhaseLabel = "Done in phase";
const String _leftInPhaseLabel = "Left in phase";
const String _tasksWithProofLabel = "Tasks with proof";
const String _proofRowsLabel = "Proof rows";
const String _completionPercentLabel = "Completion %";
const String _typeLabel = "Type";
const String _windowLabel = "Window";
const String _doneLabel = "Done";
const String _leftLabel = "Left";
const String _proofRowsShortLabel = "Proof rows";
const String _startLabel = "Start";
const String _dueLabel = "Due";
const String _assigneeLabel = "Assignee";
const String _headcountLabel = "Headcount";
const String _logsLabel = "Logs";
const String _proofsLabel = "Proofs";
const String _actualLabel = "Actual";
const String _lastWorkLabel = "Last work";
const String _progressLabel = "Progress";
const String _instructionsLabel = "Instructions";
const String _phaseDash = "—";
const String _unassignedLabel = "Unassigned";
const String _taskTypeFallback = "Task";
const String _viewLatestProofLabel = "View latest proof";
const String _openTaskLabel = "Open task";
const double _pagePadding = 16;
const double _sectionSpacing = 18;
const double _cardRadius = 18;
const double _compactRadius = 18;

enum _PhaseTaskStatusFilter { all, approved, inProgress, assigned, attention }

enum _PhaseTaskSort { latestActivity, dueDate, approval }

enum _PhaseTaskGroup { approved, inProgress, assigned, attention }

class ProductionPhaseDetailScreen extends ConsumerStatefulWidget {
  final String planId;
  final String phaseId;

  const ProductionPhaseDetailScreen({
    super.key,
    required this.planId,
    required this.phaseId,
  });

  @override
  ConsumerState<ProductionPhaseDetailScreen> createState() =>
      _ProductionPhaseDetailScreenState();
}

class _ProductionPhaseDetailScreenState
    extends ConsumerState<ProductionPhaseDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _searchQuery = "";
  bool _isSearchExpanded = false;
  // WHY: Phase detail should open with the full task pack visible so refreshes
  // and deep links do not silently hide older scheduled work behind today's
  // date.
  DateTime? _selectedDateFilter;
  _PhaseTaskStatusFilter _statusFilter = _PhaseTaskStatusFilter.all;
  _PhaseTaskSort _sort = _PhaseTaskSort.latestActivity;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshPhaseDetail() async {
    AppDebug.log(
      _logTag,
      _refreshAction,
      extra: {"planId": widget.planId, "phaseId": widget.phaseId},
    );
    ref.invalidate(productionPlanDetailProvider(widget.planId));
    await ref.read(productionPlanDetailProvider(widget.planId).future);
  }

  void _updateSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    AppDebug.log(
      _logTag,
      _searchAction,
      extra: {
        "planId": widget.planId,
        "phaseId": widget.phaseId,
        "query": value.trim(),
      },
    );
    setState(() => _searchQuery = value);
  }

  void _toggleSearchVisibility() {
    final expanded = !_isSearchExpanded;
    AppDebug.log(
      _logTag,
      _searchVisibilityAction,
      extra: {
        "planId": widget.planId,
        "phaseId": widget.phaseId,
        "expanded": expanded,
      },
    );
    setState(() {
      _isSearchExpanded = expanded;
      if (!expanded) {
        _searchController.clear();
        _searchQuery = "";
        _searchFocusNode.unfocus();
      }
    });
    if (expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _searchFocusNode.requestFocus();
      });
    }
  }

  void _updateDateFilter(DateTime? value) {
    final normalized = value == null ? null : _normalizeDay(value);
    if (_isSameDay(_selectedDateFilter, normalized)) {
      return;
    }
    AppDebug.log(
      _logTag,
      _dateFilterAction,
      extra: {
        "planId": widget.planId,
        "phaseId": widget.phaseId,
        "date": normalized == null ? "" : formatDateInput(normalized),
      },
    );
    setState(() {
      _selectedDateFilter = normalized;
    });
  }

  Future<void> _pickDateFilter() async {
    final initialDate = _selectedDateFilter ?? _normalizeDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(kDatePickerFirstYear),
      lastDate: DateTime(kDatePickerLastYear),
    );
    if (picked == null) {
      return;
    }
    _updateDateFilter(picked);
  }

  void _updateStatusFilter(_PhaseTaskStatusFilter? value) {
    if (value == null || value == _statusFilter) {
      return;
    }
    AppDebug.log(
      _logTag,
      _statusFilterAction,
      extra: {
        "planId": widget.planId,
        "phaseId": widget.phaseId,
        "status": value.name,
      },
    );
    setState(() => _statusFilter = value);
  }

  void _updateSort(_PhaseTaskSort? value) {
    if (value == null || value == _sort) {
      return;
    }
    AppDebug.log(
      _logTag,
      _sortAction,
      extra: {
        "planId": widget.planId,
        "phaseId": widget.phaseId,
        "sort": value.name,
      },
    );
    setState(() => _sort = value);
  }

  void _openTaskDetail(String taskId) {
    AppDebug.log(
      _logTag,
      _rowTapAction,
      extra: {
        "planId": widget.planId,
        "phaseId": widget.phaseId,
        "taskId": taskId,
      },
    );
    context.go(
      productionPlanTaskDetailPath(planId: widget.planId, taskId: taskId),
    );
  }

  void _openLatestProof(
    ProductionTask task,
    ProductionTaskProgressProofRecord proof,
  ) {
    AppDebug.log(
      _logTag,
      _proofPreviewAction,
      extra: {
        "planId": widget.planId,
        "phaseId": widget.phaseId,
        "taskId": task.id,
      },
    );
    showProductionTaskProgressSavedProofPreview(
      context,
      title: proof.filename.trim().isEmpty
          ? _viewLatestProofLabel
          : proof.filename,
      proof: proof,
    );
  }

  void _showSnackSafe(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createPhaseDayTask({
    required ProductionPhase phase,
    required List<ProductionTask> phaseTasks,
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) async {
    final initialTaskDay = _resolveInitialNewPhaseTaskDay(
      phase: phase,
      tasks: phaseTasks,
      selectedDate: _selectedDateFilter,
    );
    final input = await _showCreatePhaseDayTaskDialog(
      context,
      phase: phase,
      initialTaskDay: initialTaskDay,
      staffProfiles: staffProfiles,
      initialRoleRequired: _resolveInitialPhaseTaskRole(phaseTasks),
    );
    if (!mounted || input == null) {
      return;
    }

    AppDebug.log(
      _logTag,
      _createPhaseDayTaskAction,
      extra: {
        "planId": widget.planId,
        "phaseId": phase.id,
        "taskDay": formatDateInput(input.taskDay),
        "assignedCount": input.assignedStaffProfileIds.length,
      },
    );

    try {
      await ref
          .read(productionPlanActionsProvider)
          .createTask(
            planId: widget.planId,
            payload: {
              "phaseId": phase.id,
              "title": input.title,
              "roleRequired": input.roleRequired,
              "requiredHeadcount": input.requiredHeadcount,
              "weight": input.weight,
              "assignedStaffProfileIds": input.assignedStaffProfileIds,
              "instructions": input.instructions,
              "startDate": input.startDate.toUtc().toIso8601String(),
              "dueDate": input.dueDate.toUtc().toIso8601String(),
              "taskType": "event",
              // WHY: Managers use this only when phase work genuinely extends
              // beyond the saved production window.
              "allowWindowExtension": true,
            },
          );
      if (!mounted) {
        return;
      }
      _updateDateFilter(input.taskDay);
      _showSnackSafe(_phaseDayTaskCreated);
    } catch (error) {
      AppDebug.log(
        _logTag,
        _createPhaseDayTaskFailure,
        extra: {
          "planId": widget.planId,
          "phaseId": phase.id,
          "reason": error.toString(),
          "classification": "UNKNOWN_PROVIDER_ERROR",
          "nextAction":
              "Confirm the selected day is not before the phase start and retry.",
        },
      );
      _showSnackSafe(_phaseDayTaskCreateFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      _logTag,
      _buildLog,
      extra: {"planId": widget.planId, "phaseId": widget.phaseId},
    );
    final detailAsync = ref.watch(productionPlanDetailProvider(widget.planId));
    final cachedDetail = ref.watch(
      productionPlanDetailSnapshotProvider.select(
        (snapshots) => snapshots[widget.planId],
      ),
    );
    final displayDetailAsync =
        detailAsync.valueOrNull == null && cachedDetail != null
        ? AsyncValue<ProductionPlanDetail>.data(cachedDetail)
        : detailAsync;
    final isRefreshingDetail =
        detailAsync.isLoading &&
        (detailAsync.valueOrNull != null || cachedDetail != null);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _pageBackground(context),
      appBar: AppBar(
        backgroundColor: _pageBackground(context),
        surfaceTintColor: Colors.transparent,
        title: const Text(_screenTitle),
        leading: IconButton(
          style: AppButtonStyles.icon(
            theme: theme,
            tone: AppStatusTone.neutral,
          ),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlanInsightsPath(widget.planId));
          },
        ),
        actions: [
          IconButton(
            style: AppButtonStyles.icon(theme: theme, tone: AppStatusTone.info),
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _refreshPhaseDetail();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPhaseDetail,
        child: displayDetailAsync.when(
          skipError: cachedDetail != null,
          skipLoadingOnReload: true,
          loading: () => const ProductionLoadingState(),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(_pagePadding),
              child: Text(error.toString()),
            ),
          ),
          data: (detail) {
            final phase = _findPhaseById(detail.phases, widget.phaseId);
            if (phase == null) {
              return ProductionRefreshOverlay(
                isRefreshing: isRefreshingDetail,
                child: ListView(
                  padding: const EdgeInsets.all(_pagePadding),
                  children: const [
                    ProductionEmptyState(
                      title: _notFoundTitle,
                      message: _notFoundMessage,
                    ),
                  ],
                ),
              );
            }

            final phaseTasks = _sortPhaseTasks(
              detail.tasks.where((task) => task.phaseId == phase.id).toList(),
            );

            final phaseTaskIds = phaseTasks
                .map((task) => task.id.trim())
                .toSet();
            final phaseRows = _sortTimelineRows(
              detail.timelineRows
                  .where((row) => phaseTaskIds.contains(row.taskId.trim()))
                  .toList(),
            );
            final proofRows = phaseRows
                .where((row) => row.proofs.isNotEmpty)
                .toList();
            final proofTaskCount = proofRows
                .map((row) => row.taskId.trim())
                .toSet()
                .length;
            final phaseKpi = _findPhaseKpi(detail.kpis, phase.id);
            final taskActivityById = _buildTaskActivityById(phaseRows);
            final scheduledStart = _resolvePhaseStart(phase, phaseTasks);
            final scheduledEnd = _resolvePhaseEnd(phase, phaseTasks);
            final locallyCompletedTaskCount = phaseTasks.where((task) {
              final activity =
                  taskActivityById[task.id] ??
                  const _PhaseTaskActivitySummary.empty();
              return _isTaskClosed(task, activity);
            }).length;
            final totalTasks = phaseKpi?.totalTasks ?? phaseTasks.length;
            final completedTasks =
                phaseKpi?.completedTasks ?? locallyCompletedTaskCount;
            final remainingTasks = totalTasks > completedTasks
                ? totalTasks - completedTasks
                : 0;
            final completionPercent = totalTasks == 0
                ? 0
                : ((completedTasks / totalTasks) * 100).round();
            final filteredTasks = _filterPhaseTasks(
              tasks: phaseTasks,
              activityByTaskId: taskActivityById,
              query: _searchQuery,
              selectedDate: _selectedDateFilter,
              statusFilter: _statusFilter,
              sort: _sort,
            );
            final groupedTasks = _groupTasks(filteredTasks, taskActivityById);

            return ProductionRefreshOverlay(
              isRefreshing: isRefreshingDetail,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth >= 1320
                      ? 1180.0
                      : double.infinity;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: ListView(
                        padding: const EdgeInsets.all(_pagePadding),
                        children: [
                          _PhaseHeroCard(
                            planTitle: detail.plan.title,
                            phase: phase,
                            scheduledStart: scheduledStart,
                            scheduledEnd: scheduledEnd,
                            completedTasks: completedTasks,
                            totalTasks: totalTasks,
                            remainingTasks: remainingTasks,
                            proofRowCount: proofRows.length,
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _PhaseDayTaskActionCard(
                            initialTaskDay: _resolveInitialNewPhaseTaskDay(
                              phase: phase,
                              tasks: phaseTasks,
                              selectedDate: _selectedDateFilter,
                            ),
                            onCreateTask: () async {
                              await _createPhaseDayTask(
                                phase: phase,
                                phaseTasks: phaseTasks,
                                staffProfiles: detail.staffProfiles,
                              );
                            },
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _PhaseSnapshotSection(
                            totalTasks: totalTasks,
                            completedTasks: completedTasks,
                            remainingTasks: remainingTasks,
                            proofTaskCount: proofTaskCount,
                            proofRowCount: proofRows.length,
                            completionPercent: completionPercent,
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _PhaseTasksSection(
                            allTasksCount: phaseTasks.length,
                            visibleTasksCount: filteredTasks.length,
                            selectedDate: _selectedDateFilter,
                            isSearchExpanded: _isSearchExpanded,
                            searchController: _searchController,
                            searchFocusNode: _searchFocusNode,
                            onSearchChanged: _updateSearchQuery,
                            onToggleSearch: _toggleSearchVisibility,
                            onPickDate: () async {
                              await _pickDateFilter();
                            },
                            onClearDate: _selectedDateFilter == null
                                ? null
                                : () => _updateDateFilter(null),
                            selectedDateLabel: _selectedDateFilter == null
                                ? _allDatesLabel
                                : formatDateInput(_selectedDateFilter),
                            statusFilter: _statusFilter,
                            sort: _sort,
                            onStatusChanged: _updateStatusFilter,
                            onSortChanged: _updateSort,
                            child: filteredTasks.isEmpty
                                ? ProductionEmptyState(
                                    title: phaseTasks.isEmpty
                                        ? _noTasksTitle
                                        : _selectedDateFilter == null
                                        ? _noMatchesTitle
                                        : _noDateMatchesTitle,
                                    message: phaseTasks.isEmpty
                                        ? _noTasksMessage
                                        : _selectedDateFilter == null
                                        ? _noMatchesMessage
                                        : _noDateMatchesMessage,
                                  )
                                : Column(
                                    children: groupedTasks.map((group) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: _PhaseTaskGroupSection(
                                          group: group.$1,
                                          count: group.$2.length,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: group.$2.map((task) {
                                              final activity =
                                                  taskActivityById[task.id] ??
                                                  const _PhaseTaskActivitySummary.empty();
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 10,
                                                ),
                                                child: _PhaseTaskCard(
                                                  task: task,
                                                  activity: activity,
                                                  onTap: () =>
                                                      _openTaskDetail(task.id),
                                                  onPreviewProof:
                                                      activity.latestProof ==
                                                          null
                                                      ? null
                                                      : () => _openLatestProof(
                                                          task,
                                                          activity.latestProof!,
                                                        ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PhaseHeroCard extends StatelessWidget {
  final String planTitle;
  final ProductionPhase phase;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final int completedTasks;
  final int totalTasks;
  final int remainingTasks;
  final int proofRowCount;

  const _PhaseHeroCard({
    required this.planTitle,
    required this.phase,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.completedTasks,
    required this.totalTasks,
    required this.remainingTasks,
    required this.proofRowCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final isCompactPhone = MediaQuery.sizeOf(context).width <= 430;
    return Container(
      padding: EdgeInsets.all(isCompactPhone ? 16 : 20),
      decoration: BoxDecoration(
        color: _surfaceColor(context, elevated: true),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planTitle.trim().isEmpty ? "Untitled production plan" : planTitle,
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: isCompactPhone ? 8 : 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phase.name,
                      style:
                          (isCompactPhone
                                  ? textTheme.titleLarge
                                  : textTheme.headlineSmall)
                              ?.copyWith(
                                color: _phasePrimaryContentColor(colorScheme),
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    SizedBox(height: isCompactPhone ? 6 : 8),
                    Text(
                      _heroSubtitle,
                      style:
                          (isCompactPhone
                                  ? textTheme.bodySmall
                                  : textTheme.bodyMedium)
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              ProductionStatusPill(label: phase.status),
            ],
          ),
          SizedBox(height: isCompactPhone ? 14 : 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PhaseSummaryPill(
                icon: Icons.category_outlined,
                label:
                    "$_typeLabel: ${formatProductionStatusLabel(phase.phaseType)}",
              ),
              _PhaseSummaryPill(
                icon: Icons.schedule_outlined,
                label:
                    "$_windowLabel: ${_formatWindow(scheduledStart, scheduledEnd)}",
              ),
              _PhaseSummaryPill(
                icon: Icons.verified_outlined,
                label: "$_proofRowsShortLabel: $proofRowCount",
              ),
            ],
          ),
          SizedBox(height: isCompactPhone ? 14 : 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wideTile = constraints.maxWidth >= 900;
              final twoColumnTile = constraints.maxWidth >= 420;
              final tileWidth = wideTile
                  ? (constraints.maxWidth - 30) / 3
                  : twoColumnTile
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _PhaseWorkspaceMetricTile(
                      label: _doneLabel,
                      value: "$completedTasks / $totalTasks",
                      helper: "Completed in this phase",
                      icon: Icons.task_alt_outlined,
                      accentColor: AppColors.productionAccent,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _PhaseWorkspaceMetricTile(
                      label: _leftLabel,
                      value: "$remainingTasks",
                      helper: remainingTasks == 0
                          ? "Nothing open"
                          : "Tasks still open",
                      icon: Icons.pending_actions_outlined,
                      accentColor: remainingTasks == 0
                          ? AppColors.productionAccent
                          : AppColors.warning,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _PhaseWorkspaceMetricTile(
                      label: _proofRowsShortLabel,
                      value: "$proofRowCount",
                      helper: "Saved proof rows",
                      icon: Icons.photo_library_outlined,
                      accentColor: AppColors.analyticsAccent,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PhaseSnapshotSection extends StatelessWidget {
  final int totalTasks;
  final int completedTasks;
  final int remainingTasks;
  final int proofTaskCount;
  final int proofRowCount;
  final int completionPercent;

  const _PhaseSnapshotSection({
    required this.totalTasks,
    required this.completedTasks,
    required this.remainingTasks,
    required this.proofTaskCount,
    required this.proofRowCount,
    required this.completionPercent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressValue = completionPercent / 100;
    final items = [
      (
        _totalTasksLabel,
        "$totalTasks",
        "Scheduled in phase",
        Icons.format_list_numbered_rounded,
        AppColors.analyticsAccent,
      ),
      (
        _doneInPhaseLabel,
        "$completedTasks",
        "Completed tasks",
        Icons.check_circle_outline_rounded,
        AppColors.productionAccent,
      ),
      (
        _leftInPhaseLabel,
        "$remainingTasks",
        remainingTasks == 0 ? "Nothing open" : "Still open",
        Icons.pending_actions_outlined,
        remainingTasks > 0 ? AppColors.warning : AppColors.productionAccent,
      ),
      (
        _tasksWithProofLabel,
        "$proofTaskCount",
        "Tasks with uploads",
        Icons.verified_outlined,
        AppColors.analyticsAccent,
      ),
      (
        _proofRowsLabel,
        "$proofRowCount",
        "Saved proof rows",
        Icons.photo_library_outlined,
        AppColors.paid,
      ),
      (
        _completionPercentLabel,
        "$completionPercent%",
        "Overall completion",
        Icons.insights_outlined,
        completionPercent >= 85
            ? AppColors.productionAccent
            : completionPercent >= 60
            ? AppColors.warning
            : AppColors.analyticsAccent,
      ),
    ];

    return _PhaseCollapsibleSurface(
      icon: Icons.analytics_outlined,
      title: _snapshotTitle,
      subtitle: _snapshotSubtitle,
      summary: "$completionPercent%",
      accentColor: AppColors.analyticsAccent,
      initiallyExpanded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _progressTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                "$completionPercent%",
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.analyticsAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressValue.clamp(0, 1),
              minHeight: 8,
              color: AppColors.success,
              backgroundColor: _trackColor(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _PhaseLegendItem(
                color: AppColors.success,
                label: "$completedTasks done",
              ),
              _PhaseLegendItem(
                color: AppColors.warning,
                label: "$remainingTasks left",
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final metricWidth = constraints.maxWidth >= 980
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items.map((item) {
                  return SizedBox(
                    width: metricWidth,
                    child: _PhaseWorkspaceMetricTile(
                      label: item.$1,
                      value: item.$2,
                      helper: item.$3,
                      icon: item.$4,
                      accentColor: item.$5,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PhaseDayTaskActionCard extends StatelessWidget {
  final DateTime initialTaskDay;
  final Future<void> Function() onCreateTask;

  const _PhaseDayTaskActionCard({
    required this.initialTaskDay,
    required this.onCreateTask,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PhaseCollapsibleSurface(
      icon: Icons.add_task_rounded,
      title: _phaseDayTaskCardTitle,
      subtitle: _phaseDayTaskCardSubtitle,
      summary: formatDateInput(initialTaskDay),
      accentColor: AppColors.analyticsAccent,
      initiallyExpanded: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Text(
            "Suggested next day: ${formatDateInput(initialTaskDay)}.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          _PhaseInlineActionButton(
            icon: Icons.add_rounded,
            label: _phaseDayTaskButtonLabel,
            tone: AppStatusTone.info,
            onPressed: onCreateTask,
          ),
        ],
      ),
    );
  }
}

class _PhaseTasksSection extends StatelessWidget {
  final int allTasksCount;
  final int visibleTasksCount;
  final DateTime? selectedDate;
  final bool isSearchExpanded;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleSearch;
  final Future<void> Function()? onPickDate;
  final VoidCallback? onClearDate;
  final String selectedDateLabel;
  final _PhaseTaskStatusFilter statusFilter;
  final _PhaseTaskSort sort;
  final ValueChanged<_PhaseTaskStatusFilter?> onStatusChanged;
  final ValueChanged<_PhaseTaskSort?> onSortChanged;
  final Widget child;

  const _PhaseTasksSection({
    required this.allTasksCount,
    required this.visibleTasksCount,
    required this.selectedDate,
    required this.isSearchExpanded,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onToggleSearch,
    required this.onPickDate,
    required this.onClearDate,
    required this.selectedDateLabel,
    required this.statusFilter,
    required this.sort,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countLabel = selectedDate == null
        ? "$visibleTasksCount of $allTasksCount task(s) shown."
        : "$visibleTasksCount of $allTasksCount task(s) shown for ${formatDateInput(selectedDate)}.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _taskSectionTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            color: _phasePrimaryContentColor(theme.colorScheme),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _taskSectionSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          countLabel,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (isSearchExpanded) ...[
          _PhaseSearchField(
            controller: searchController,
            focusNode: searchFocusNode,
            onChanged: onSearchChanged,
            onClose: onToggleSearch,
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            // Keep the toolbar visually lighter on desktop so it reads like
            // controls, not four equal-weight cards.
            final compact = constraints.maxWidth < 900;
            final fieldWidth = compact
                ? constraints.maxWidth
                : constraints.maxWidth >= 1180
                ? 228.0
                : 210.0;
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                if (!isSearchExpanded)
                  Tooltip(
                    message: _searchLabel,
                    child: IconButton(
                      key: const ValueKey("phase-task-search-toggle"),
                      style: AppButtonStyles.icon(
                        theme: theme,
                        tone: AppStatusTone.neutral,
                      ),
                      onPressed: onToggleSearch,
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ),
                SizedBox(
                  width: fieldWidth,
                  child: _PhaseDateField(
                    value: selectedDateLabel,
                    onTap: onPickDate,
                    onClear: onClearDate,
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: _PhaseSelectField<_PhaseTaskStatusFilter>(
                    label: _statusLabel,
                    value: statusFilter,
                    labels: const {
                      _PhaseTaskStatusFilter.all: _allStatusesLabel,
                      _PhaseTaskStatusFilter.approved: _approvedLabel,
                      _PhaseTaskStatusFilter.inProgress: _inProgressLabel,
                      _PhaseTaskStatusFilter.assigned: _assignedLabel,
                      _PhaseTaskStatusFilter.attention: _attentionLabel,
                    },
                    onChanged: onStatusChanged,
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: _PhaseSelectField<_PhaseTaskSort>(
                    label: _sortLabel,
                    value: sort,
                    labels: const {
                      _PhaseTaskSort.latestActivity: _latestActivityLabel,
                      _PhaseTaskSort.dueDate: _dueDateLabel,
                      _PhaseTaskSort.approval: _approvalStateLabel,
                    },
                    onChanged: onSortChanged,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _PhaseTaskGroupSection extends StatelessWidget {
  final _PhaseTaskGroup group;
  final int count;
  final Widget child;

  const _PhaseTaskGroupSection({
    required this.group,
    required this.count,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _groupTone(group);
    return _PhaseCollapsibleSurface(
      icon: _groupIcon(group),
      title: _groupLabel(group),
      subtitle: "$count task${count == 1 ? '' : 's'}",
      summary: "$count",
      accentColor: _toneAccentColor(tone),
      initiallyExpanded: true,
      child: child,
    );
  }
}

class _PhaseTaskCard extends StatefulWidget {
  final ProductionTask task;
  final _PhaseTaskActivitySummary activity;
  final VoidCallback onTap;
  final VoidCallback? onPreviewProof;

  const _PhaseTaskCard({
    required this.task,
    required this.activity,
    required this.onTap,
    required this.onPreviewProof,
  });

  @override
  State<_PhaseTaskCard> createState() => _PhaseTaskCardState();
}

class _PhaseTaskCardState extends State<_PhaseTaskCard> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final task = widget.task;
    final activity = widget.activity;
    final isClosed = _isTaskClosed(task, activity);
    final approvalLabel = _formatTaskApproval(task, activity);
    final approvalTone = _taskApprovalTone(task, activity);
    final progress = _taskProgressSnapshot(task, activity);
    final headerSummary = [
      "${activity.proofCount} ${activity.proofCount == 1 ? "proof" : "proofs"}",
      "${activity.logCount} ${activity.logCount == 1 ? "log" : "logs"}",
      "Actual: ${activity.actualTotal}",
      "Headcount: ${task.assignedCount}/${task.requiredHeadcount}",
    ].join(" · ");

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleExpanded,
        borderRadius: BorderRadius.circular(_compactRadius),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _phaseToneSurface(
              colorScheme: colorScheme,
              accentColor: progress.color,
              lightTintAlpha: 0.025,
              darkTintAlpha: 0.08,
              baseColor: _surfaceColor(context),
            ),
            borderRadius: BorderRadius.circular(_compactRadius),
            border: Border.all(
              color: _phaseToneBorder(
                colorScheme: colorScheme,
                accentColor: progress.color,
                lightAlpha: 0.12,
                darkAlpha: 0.3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PhaseTaskHeader(
                task: task,
                activity: activity,
                headerSummary: headerSummary,
                approvalLabel: approvalLabel,
                approvalTone: approvalTone,
                isClosed: isClosed,
                isExpanded: _expanded,
                onToggleExpanded: _toggleExpanded,
                onOpenTask: widget.onTap,
                onPreviewProof: widget.onPreviewProof,
              ),
              const SizedBox(height: 12),
              _PhaseTaskProgressStrip(progress: progress),
              if (_expanded) ...[
                const SizedBox(height: 14),
                _PhaseTaskMetricsWrap(task: task, activity: activity),
                if (task.instructions.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(color: _borderColor(context)),
                  const SizedBox(height: 10),
                  Text(
                    _instructionsLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    task.instructions.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseTaskHeader extends StatelessWidget {
  final ProductionTask task;
  final _PhaseTaskActivitySummary activity;
  final String headerSummary;
  final String approvalLabel;
  final AppStatusTone approvalTone;
  final bool isClosed;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpenTask;
  final VoidCallback? onPreviewProof;

  const _PhaseTaskHeader({
    required this.task,
    required this.activity,
    required this.headerSummary,
    required this.approvalLabel,
    required this.approvalTone,
    required this.isClosed,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onOpenTask,
    required this.onPreviewProof,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PhaseTonePill(label: approvalLabel, tone: approvalTone),
            ProductionStatusPill(label: isClosed ? "completed" : task.status),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          runSpacing: 6,
          children: [
            _PhaseSmallIconButton(
              tooltip: _openTaskLabel,
              icon: Icons.open_in_new_rounded,
              tone: AppStatusTone.neutral,
              onPressed: onOpenTask,
            ),
            if (onPreviewProof != null)
              _PhaseSmallIconButton(
                tooltip: _viewLatestProofLabel,
                icon: Icons.photo_library_outlined,
                tone: AppStatusTone.info,
                onPressed: onPreviewProof!,
              ),
            _PhaseSmallIconButton(
              tooltip: isExpanded ? "Collapse task" : "Expand task",
              icon: isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              tone: AppStatusTone.neutral,
              onPressed: onToggleExpanded,
            ),
          ],
        ),
      ],
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _taskDescriptor(task),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          headerSummary,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // WHY: Narrow cards need the status pills below the title block so the
        // header stays readable without horizontal overflow.
        final compact = constraints.maxWidth < 540;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              details,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [trailing],
                ),
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  trailing,
                ],
              ),
          ],
        );
      },
    );
  }
}

class _PhaseTaskProgressStrip extends StatelessWidget {
  final _TaskProgressSnapshot progress;

  const _PhaseTaskProgressStrip({required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "$_progressLabel: ${progress.label}",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              "${(progress.value * 100).round()}%",
              style: theme.textTheme.labelMedium?.copyWith(
                color: progress.color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.value,
            minHeight: 6,
            color: progress.color,
            backgroundColor: _trackColor(context),
          ),
        ),
      ],
    );
  }
}

class _PhaseTaskMetricsWrap extends StatelessWidget {
  final ProductionTask task;
  final _PhaseTaskActivitySummary activity;

  const _PhaseTaskMetricsWrap({required this.task, required this.activity});

  @override
  Widget build(BuildContext context) {
    final items = [
      (_startLabel, _formatOptionalDate(task.startDate)),
      (_dueLabel, _formatOptionalDate(task.dueDate)),
      (_assigneeLabel, _resolveAssigneeLabel(task, activity)),
      (_headcountLabel, "${task.assignedCount}/${task.requiredHeadcount}"),
      (
        _logsLabel,
        "${activity.logCount} log${activity.logCount == 1 ? "" : "s"}",
      ),
      (
        _proofsLabel,
        "${activity.proofCount} proof${activity.proofCount == 1 ? "" : "s"}",
      ),
      (_actualLabel, "${activity.actualTotal}"),
      (_lastWorkLabel, _formatOptionalDate(activity.lastWorkDate)),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.start,
      children: items.map((item) {
        return SizedBox(
          width: 114,
          child: _PhaseTaskMetricTile(label: item.$1, value: item.$2),
        );
      }).toList(),
    );
  }
}

class _PhaseTaskMetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _PhaseTaskMetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PhaseSummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PhaseSummaryPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = _phaseToneForeground(
      colorScheme: colorScheme,
      accentColor: AppColors.analyticsAccent,
      darkMix: 0.52,
    );
    final maxWidth = math.min(
      360.0,
      math.max(132.0, MediaQuery.sizeOf(context).width - 64),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _phaseToneSurface(
            colorScheme: colorScheme,
            accentColor: AppColors.analyticsAccent,
            lightTintAlpha: 0.025,
            darkTintAlpha: 0.1,
            baseColor: _surfaceColor(context),
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _phaseToneBorder(
              colorScheme: colorScheme,
              accentColor: AppColors.analyticsAccent,
              lightAlpha: 0.11,
              darkAlpha: 0.24,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _phasePrimaryContentColor(colorScheme),
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseWorkspaceMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color accentColor;

  const _PhaseWorkspaceMetricTile({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentForeground = _phaseToneForeground(
      colorScheme: colorScheme,
      accentColor: accentColor,
      darkMix: 0.58,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _phaseToneSurface(
          colorScheme: colorScheme,
          accentColor: accentColor,
          lightTintAlpha: 0.025,
          darkTintAlpha: 0.08,
          baseColor: _surfaceColor(context),
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _phaseToneBorder(
            colorScheme: colorScheme,
            accentColor: accentColor,
            lightAlpha: 0.14,
            darkAlpha: 0.28,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _phaseToneSurface(
                colorScheme: colorScheme,
                accentColor: accentColor,
                lightTintAlpha: 0.08,
                darkTintAlpha: 0.16,
                baseColor: _surfaceColor(context),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentForeground, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accentForeground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: _phasePrimaryContentColor(colorScheme),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
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

class _PhaseLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _PhaseLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _PhaseTonePill extends StatelessWidget {
  final String label;
  final AppStatusTone tone;

  const _PhaseTonePill({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PhaseAccentPill extends StatelessWidget {
  final String label;
  final Color accentColor;

  const _PhaseAccentPill({required this.label, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = _phaseToneForeground(
      colorScheme: colorScheme,
      accentColor: accentColor,
      darkMix: 0.58,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _phaseToneSurface(
          colorScheme: colorScheme,
          accentColor: accentColor,
          lightTintAlpha: 0.08,
          darkTintAlpha: 0.18,
          baseColor: _surfaceColor(context),
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _phaseToneBorder(
            colorScheme: colorScheme,
            accentColor: accentColor,
            lightAlpha: 0.18,
            darkAlpha: 0.36,
          ),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PhaseInlineActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusTone tone;
  final VoidCallback onPressed;

  const _PhaseInlineActionButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: _phaseActionButtonStyle(
        context,
        accentColor: _toneAccentColor(tone),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _PhaseSmallIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final AppStatusTone tone;
  final VoidCallback onPressed;

  const _PhaseSmallIconButton({
    required this.tooltip,
    required this.icon,
    required this.tone,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        style: IconButton.styleFrom(
          foregroundColor: AppButtonStyles.accentColor(
            theme: theme,
            tone: tone,
          ),
          backgroundColor: _surfaceColor(context),
          minimumSize: const Size(34, 34),
          padding: const EdgeInsets.all(7),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(color: _borderColor(context)),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
      ),
    );
  }
}

class _PhaseCollapsibleSurface extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String summary;
  final Color accentColor;
  final bool initiallyExpanded;
  final Widget child;

  const _PhaseCollapsibleSurface({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.accentColor,
    required this.initiallyExpanded,
    required this.child,
  });

  @override
  State<_PhaseCollapsibleSurface> createState() =>
      _PhaseCollapsibleSurfaceState();
}

class _PhaseCollapsibleSurfaceState extends State<_PhaseCollapsibleSurface> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant _PhaseCollapsibleSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _expanded = widget.initiallyExpanded;
    }
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = _phaseToneForeground(
      colorScheme: colorScheme,
      accentColor: widget.accentColor,
      darkMix: 0.58,
    );

    return _PhaseSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(_cardRadius),
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _phaseToneSurface(
                          colorScheme: colorScheme,
                          accentColor: widget.accentColor,
                          lightTintAlpha: 0.08,
                          darkTintAlpha: 0.18,
                          baseColor: _surfaceColor(context),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: foreground, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _phasePrimaryContentColor(colorScheme),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (widget.summary.trim().isNotEmpty)
                      _PhaseAccentPill(
                        label: widget.summary,
                        accentColor: widget.accentColor,
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _PhaseSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _PhaseSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _surfaceColor(context, elevated: true),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _borderColor(context)),
      ),
      child: child,
    );
  }
}

class _PhaseDateField extends StatelessWidget {
  final String value;
  final Future<void> Function()? onTap;
  final VoidCallback? onClear;

  const _PhaseDateField({
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: _dateLabel,
      child: InkWell(
        key: const ValueKey("phase-task-date-filter"),
        borderRadius: BorderRadius.circular(_compactRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _surfaceColor(context),
            borderRadius: BorderRadius.circular(_compactRadius),
            border: Border.all(color: _borderColor(context)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  key: const ValueKey("phase-task-date-value"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onClear != null)
                _PhaseSmallIconButton(
                  tooltip: _allDatesLabel,
                  icon: Icons.close_rounded,
                  tone: AppStatusTone.neutral,
                  onPressed: onClear!,
                )
              else
                Icon(
                  Icons.expand_more_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseSelectField<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T?> onChanged;

  const _PhaseSelectField({
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _surfaceColor(context),
        borderRadius: BorderRadius.circular(_compactRadius),
        border: Border.all(color: _borderColor(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(_compactRadius),
          dropdownColor: _surfaceColor(context, elevated: true),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          icon: Icon(
            Icons.expand_more_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          selectedItemBuilder: (context) {
            return labels.entries.map((entry) {
              return Align(
                alignment: Alignment.centerLeft,
                child: RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(
                        text: "$label ",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: entry.value),
                    ],
                  ),
                ),
              );
            }).toList();
          },
          items: labels.entries.map((entry) {
            return DropdownMenuItem<T>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PhaseSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _PhaseSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      key: const ValueKey("phase-task-search-field"),
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: _searchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
        filled: true,
        fillColor: _surfaceColor(context),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_compactRadius),
          borderSide: BorderSide(color: _borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_compactRadius),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

class _PhaseTaskActivitySummary {
  final int logCount;
  final int proofCount;
  final num actualTotal;
  final DateTime? lastWorkDate;
  final bool hasApprovedProgress;
  final List<DateTime> workDates;
  final String latestFarmerName;
  final ProductionTaskProgressProofRecord? latestProof;

  const _PhaseTaskActivitySummary({
    required this.logCount,
    required this.proofCount,
    required this.actualTotal,
    required this.lastWorkDate,
    required this.hasApprovedProgress,
    required this.workDates,
    required this.latestFarmerName,
    required this.latestProof,
  });

  const _PhaseTaskActivitySummary.empty()
    : logCount = 0,
      proofCount = 0,
      actualTotal = 0,
      lastWorkDate = null,
      hasApprovedProgress = false,
      workDates = const [],
      latestFarmerName = "",
      latestProof = null;
}

class _TaskProgressSnapshot {
  final double value;
  final String label;
  final Color color;

  const _TaskProgressSnapshot({
    required this.value,
    required this.label,
    required this.color,
  });
}

class _CreatePhaseDayTaskInput {
  final DateTime taskDay;
  final String title;
  final String roleRequired;
  final int requiredHeadcount;
  final int weight;
  final List<String> assignedStaffProfileIds;
  final String instructions;
  final DateTime startDate;
  final DateTime dueDate;

  const _CreatePhaseDayTaskInput({
    required this.taskDay,
    required this.title,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.weight,
    required this.assignedStaffProfileIds,
    required this.instructions,
    required this.startDate,
    required this.dueDate,
  });
}

Future<_CreatePhaseDayTaskInput?> _showCreatePhaseDayTaskDialog(
  BuildContext context, {
  required ProductionPhase phase,
  required DateTime initialTaskDay,
  required List<BusinessStaffProfileSummary> staffProfiles,
  required String initialRoleRequired,
}) async {
  final activeStaff = _activeStaffProfiles(staffProfiles);
  final normalizedInitialRole = _normalizeRole(initialRoleRequired);
  final roleOptions = <String>{
    for (final staff in activeStaff)
      if (staff.staffRole.trim().isNotEmpty) _normalizeRole(staff.staffRole),
    if (normalizedInitialRole.isNotEmpty) normalizedInitialRole,
    staffRoleFarmer,
  }.toList()..sort();
  final defaultTitle = _defaultPhaseDayTaskTitle(phase);
  final titleController = TextEditingController(text: defaultTitle);
  final weightController = TextEditingController(text: "1");
  final headcountController = TextEditingController(text: "1");
  final notesController = TextEditingController();

  final result = await showDialog<_CreatePhaseDayTaskInput>(
    context: context,
    builder: (dialogContext) {
      var selectedTaskDay = _normalizeDay(initialTaskDay);
      var selectedRole = roleOptions.contains(normalizedInitialRole)
          ? normalizedInitialRole
          : roleOptions.first;
      final selectedStaffIds = <String>{};
      var validationError = "";

      return StatefulBuilder(
        builder: (context, setDialogState) {
          final staffCandidates = _staffCandidatesForRole(
            roleRequired: selectedRole,
            staffList: activeStaff,
          );

          Future<void> pickTaskDay() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: selectedTaskDay,
              firstDate: DateTime(kDatePickerFirstYear),
              lastDate: DateTime(kDatePickerLastYear),
            );
            if (picked == null) {
              return;
            }
            setDialogState(() {
              selectedTaskDay = _normalizeDay(picked);
            });
          }

          return AlertDialog(
            title: const Text(_phaseDayTaskDialogTitle),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _phaseDayTaskDialogHelp,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey("phase-day-task-date-picker"),
                        style: AppButtonStyles.outlined(
                          theme: Theme.of(context),
                          tone: AppStatusTone.info,
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        onPressed: pickTaskDay,
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                        label: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "$_phaseDayTaskDateLabel: ${formatDateInput(selectedTaskDay)}",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey("phase-day-task-title-field"),
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: _phaseDayTaskTitleLabel,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: _phaseDayTaskRoleLabel,
                      ),
                      items: roleOptions
                          .map(
                            (role) => DropdownMenuItem<String>(
                              value: role,
                              child: Text(
                                formatStaffRoleLabel(role, fallback: role),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return;
                        }
                        setDialogState(() {
                          selectedRole = _normalizeRole(value);
                          final allowedIds = _staffCandidatesForRole(
                            roleRequired: selectedRole,
                            staffList: activeStaff,
                          ).map((staff) => staff.id).toSet();
                          selectedStaffIds.removeWhere(
                            (staffId) => !allowedIds.contains(staffId),
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: weightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: _phaseDayTaskExpectedLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: headcountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: _phaseDayTaskHeadcountLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: _phaseDayTaskNotesLabel,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _phaseDayTaskStaffLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (staffCandidates.isEmpty)
                      Text(
                        _phaseDayTaskNoStaff,
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ...staffCandidates.map((staff) {
                        final checked = selectedStaffIds.contains(staff.id);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: checked,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selectedStaffIds.add(staff.id);
                              } else {
                                selectedStaffIds.remove(staff.id);
                              }
                            });
                          },
                          title: Text(_staffListLabel(staff)),
                          subtitle: Text(
                            formatStaffRoleLabel(
                              staff.staffRole,
                              fallback: staff.staffRole,
                            ),
                          ),
                        );
                      }),
                    if (validationError.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                child: const Text(_phaseDayTaskCancelLabel),
              ),
              FilledButton(
                key: const ValueKey("phase-day-task-submit-button"),
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    setDialogState(() {
                      validationError = _phaseDayTaskTitleRequired;
                    });
                    return;
                  }
                  final parsedWeight =
                      int.tryParse(weightController.text.trim()) ?? 1;
                  final parsedHeadcount =
                      int.tryParse(headcountController.text.trim()) ?? 1;
                  final requiredHeadcount = math.max(
                    1,
                    math.max(parsedHeadcount, selectedStaffIds.length),
                  );
                  final taskDay = _normalizeDay(selectedTaskDay);
                  Navigator.of(dialogContext).pop(
                    _CreatePhaseDayTaskInput(
                      taskDay: taskDay,
                      title: title,
                      roleRequired: selectedRole,
                      requiredHeadcount: requiredHeadcount,
                      weight: math.max(1, parsedWeight),
                      assignedStaffProfileIds: selectedStaffIds.toList(),
                      instructions: notesController.text.trim(),
                      startDate: _buildPhaseDayTaskStartDate(taskDay),
                      dueDate: _buildPhaseDayTaskDueDate(taskDay),
                    ),
                  );
                },
                child: const Text(_phaseDayTaskSubmitLabel),
              ),
            ],
          );
        },
      );
    },
  );

  titleController.dispose();
  weightController.dispose();
  headcountController.dispose();
  notesController.dispose();

  return result;
}

DateTime _resolveInitialNewPhaseTaskDay({
  required ProductionPhase phase,
  required List<ProductionTask> tasks,
  required DateTime? selectedDate,
}) {
  final now = _normalizeDay(DateTime.now());
  final phaseStart = _normalizeDay(_resolvePhaseStart(phase, tasks) ?? now);
  if (selectedDate != null) {
    final selectedDay = _normalizeDay(selectedDate);
    if (!selectedDay.isBefore(phaseStart)) {
      return selectedDay;
    }
  }

  final phaseEnd = _resolvePhaseEnd(phase, tasks);
  if (phaseEnd == null) {
    return phaseStart;
  }
  return _normalizeDay(phaseEnd).add(const Duration(days: 1));
}

String _resolveInitialPhaseTaskRole(List<ProductionTask> tasks) {
  for (final task in tasks) {
    final role = _normalizeRole(task.roleRequired);
    if (role.isNotEmpty) {
      return role;
    }
  }
  return staffRoleFarmer;
}

String _defaultPhaseDayTaskTitle(ProductionPhase phase) {
  final phaseName = phase.name.trim();
  if (phaseName.isEmpty) {
    return "Phase follow-up";
  }
  return "$phaseName follow-up";
}

DateTime _buildPhaseDayTaskStartDate(DateTime day) {
  final localDay = _normalizeDay(day);
  return DateTime(localDay.year, localDay.month, localDay.day, 8);
}

DateTime _buildPhaseDayTaskDueDate(DateTime day) {
  final localDay = _normalizeDay(day);
  return DateTime(localDay.year, localDay.month, localDay.day, 17);
}

List<BusinessStaffProfileSummary> _activeStaffProfiles(
  List<BusinessStaffProfileSummary> staffProfiles,
) {
  return staffProfiles
      .where((staff) => staff.status.trim().toLowerCase() != "terminated")
      .toList();
}

List<BusinessStaffProfileSummary> _staffCandidatesForRole({
  required String roleRequired,
  required List<BusinessStaffProfileSummary> staffList,
}) {
  final normalizedRole = _normalizeRole(roleRequired);
  final matching = staffList
      .where((staff) => _normalizeRole(staff.staffRole) == normalizedRole)
      .toList();
  if (matching.isNotEmpty) {
    return matching;
  }
  return staffList;
}

String _staffListLabel(BusinessStaffProfileSummary staff) {
  final name = staff.userName?.trim() ?? "";
  if (name.isNotEmpty) {
    return name;
  }
  final email = staff.userEmail?.trim() ?? "";
  if (email.isNotEmpty) {
    return email;
  }
  final phone = staff.userPhone?.trim() ?? "";
  if (phone.isNotEmpty) {
    return phone;
  }
  return staff.id;
}

String _normalizeRole(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "_");
}

ProductionPhase? _findPhaseById(List<ProductionPhase> phases, String phaseId) {
  final normalizedPhaseId = phaseId.trim();
  for (final phase in phases) {
    if (phase.id == normalizedPhaseId) {
      return phase;
    }
  }
  return null;
}

ProductionPhaseKpi? _findPhaseKpi(ProductionKpis? kpis, String phaseId) {
  final normalizedPhaseId = phaseId.trim();
  if (kpis == null) {
    return null;
  }
  for (final phase in kpis.phaseCompletion) {
    if (phase.phaseId == normalizedPhaseId) {
      return phase;
    }
  }
  return null;
}

List<ProductionTask> _sortPhaseTasks(List<ProductionTask> tasks) {
  tasks.sort((left, right) {
    final leftStart = left.startDate ?? left.dueDate;
    final rightStart = right.startDate ?? right.dueDate;
    final startCompare = _compareDate(leftStart, rightStart);
    if (startCompare != 0) {
      return startCompare;
    }
    final dueCompare = _compareDate(left.dueDate, right.dueDate);
    if (dueCompare != 0) {
      return dueCompare;
    }
    final manualCompare = left.manualSortOrder.compareTo(right.manualSortOrder);
    if (manualCompare != 0) {
      return manualCompare;
    }
    return left.title.toLowerCase().compareTo(right.title.toLowerCase());
  });
  return tasks;
}

List<ProductionTimelineRow> _sortTimelineRows(
  List<ProductionTimelineRow> rows,
) {
  rows.sort((left, right) {
    final dateCompare = _compareDate(right.workDate, left.workDate);
    if (dateCompare != 0) {
      return dateCompare;
    }
    final entryCompare = right.entryIndex.compareTo(left.entryIndex);
    if (entryCompare != 0) {
      return entryCompare;
    }
    return left.taskTitle.toLowerCase().compareTo(
      right.taskTitle.toLowerCase(),
    );
  });
  return rows;
}

Map<String, _PhaseTaskActivitySummary> _buildTaskActivityById(
  List<ProductionTimelineRow> rows,
) {
  final logCountByTaskId = <String, int>{};
  final proofCountByTaskId = <String, int>{};
  final actualByTaskId = <String, num>{};
  final lastWorkByTaskId = <String, DateTime?>{};
  final hasApprovedProgressByTaskId = <String, bool>{};
  final workDatesByTaskId = <String, List<DateTime>>{};
  final latestFarmerNameByTaskId = <String, String>{};
  final latestProofByTaskId = <String, ProductionTaskProgressProofRecord?>{};
  final latestRowByTaskId = <String, ProductionTimelineRow>{};

  for (final row in rows) {
    final taskId = row.taskId.trim();
    if (taskId.isEmpty) {
      continue;
    }

    logCountByTaskId[taskId] = (logCountByTaskId[taskId] ?? 0) + 1;
    proofCountByTaskId[taskId] =
        (proofCountByTaskId[taskId] ?? 0) + row.proofCount;
    actualByTaskId[taskId] = (actualByTaskId[taskId] ?? 0) + row.actualPlots;

    final normalizedWorkDate = row.workDate == null
        ? null
        : _normalizeDay(row.workDate!);
    if (normalizedWorkDate != null) {
      final dates = workDatesByTaskId.putIfAbsent(taskId, () => <DateTime>[]);
      if (!dates.any((value) => _isSameDay(value, normalizedWorkDate))) {
        dates.add(normalizedWorkDate);
      }
    }

    final currentLast = lastWorkByTaskId[taskId];
    if (currentLast == null ||
        (row.workDate != null && row.workDate!.isAfter(currentLast))) {
      lastWorkByTaskId[taskId] = row.workDate;
    }

    if (_isApprovedProgressRow(row)) {
      hasApprovedProgressByTaskId[taskId] = true;
    }

    final currentLatest = latestRowByTaskId[taskId];
    if (currentLatest == null || _isTimelineRowNewer(row, currentLatest)) {
      latestRowByTaskId[taskId] = row;
      latestFarmerNameByTaskId[taskId] = row.farmerName.trim();
      latestProofByTaskId[taskId] = row.proofs.isEmpty
          ? null
          : row.proofs.first;
    }
  }

  final taskIds = <String>{
    ...logCountByTaskId.keys,
    ...proofCountByTaskId.keys,
    ...actualByTaskId.keys,
    ...workDatesByTaskId.keys,
    ...latestFarmerNameByTaskId.keys,
  };

  final summaries = <String, _PhaseTaskActivitySummary>{};
  for (final taskId in taskIds) {
    summaries[taskId] = _PhaseTaskActivitySummary(
      logCount: logCountByTaskId[taskId] ?? 0,
      proofCount: proofCountByTaskId[taskId] ?? 0,
      actualTotal: actualByTaskId[taskId] ?? 0,
      lastWorkDate: lastWorkByTaskId[taskId],
      hasApprovedProgress: hasApprovedProgressByTaskId[taskId] ?? false,
      workDates: workDatesByTaskId[taskId] ?? const [],
      latestFarmerName: latestFarmerNameByTaskId[taskId] ?? "",
      latestProof: latestProofByTaskId[taskId],
    );
  }
  return summaries;
}

List<ProductionTask> _filterPhaseTasks({
  required List<ProductionTask> tasks,
  required Map<String, _PhaseTaskActivitySummary> activityByTaskId,
  required String query,
  required DateTime? selectedDate,
  required _PhaseTaskStatusFilter statusFilter,
  required _PhaseTaskSort sort,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = tasks.where((task) {
    final activity =
        activityByTaskId[task.id] ?? const _PhaseTaskActivitySummary.empty();

    if (selectedDate != null &&
        !_taskMatchesDate(task, activity, selectedDate)) {
      return false;
    }

    final group = _classifyTaskGroup(task, activity);
    if (!_matchesStatusFilter(group, statusFilter)) {
      return false;
    }

    if (normalizedQuery.isEmpty) {
      return true;
    }

    final searchHaystack = [
      task.title,
      _taskDescriptor(task),
      task.status,
      task.approvalStatus,
      _formatTaskApproval(task, activity),
      activity.latestFarmerName,
      task.instructions,
    ].join(" ").toLowerCase();

    return searchHaystack.contains(normalizedQuery);
  }).toList();

  filtered.sort((left, right) {
    final leftActivity =
        activityByTaskId[left.id] ?? const _PhaseTaskActivitySummary.empty();
    final rightActivity =
        activityByTaskId[right.id] ?? const _PhaseTaskActivitySummary.empty();

    switch (sort) {
      case _PhaseTaskSort.latestActivity:
        final lastWorkCompare = _compareDate(
          rightActivity.lastWorkDate,
          leftActivity.lastWorkDate,
        );
        if (lastWorkCompare != 0) {
          return lastWorkCompare;
        }
        final dueCompare = _compareDate(left.dueDate, right.dueDate);
        if (dueCompare != 0) {
          return dueCompare;
        }
        return left.manualSortOrder.compareTo(right.manualSortOrder);
      case _PhaseTaskSort.dueDate:
        final dueCompare = _compareDate(left.dueDate, right.dueDate);
        if (dueCompare != 0) {
          return dueCompare;
        }
        final lastWorkCompare = _compareDate(
          rightActivity.lastWorkDate,
          leftActivity.lastWorkDate,
        );
        if (lastWorkCompare != 0) {
          return lastWorkCompare;
        }
        return left.manualSortOrder.compareTo(right.manualSortOrder);
      case _PhaseTaskSort.approval:
        final approvalCompare =
            _approvalSortRank(left, leftActivity) -
            _approvalSortRank(right, rightActivity);
        if (approvalCompare != 0) {
          return approvalCompare;
        }
        final lastWorkCompare = _compareDate(
          rightActivity.lastWorkDate,
          leftActivity.lastWorkDate,
        );
        if (lastWorkCompare != 0) {
          return lastWorkCompare;
        }
        return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    }
  });

  return filtered;
}

List<(_PhaseTaskGroup, List<ProductionTask>)> _groupTasks(
  List<ProductionTask> tasks,
  Map<String, _PhaseTaskActivitySummary> activityByTaskId,
) {
  final grouped = <_PhaseTaskGroup, List<ProductionTask>>{};
  for (final task in tasks) {
    final activity =
        activityByTaskId[task.id] ?? const _PhaseTaskActivitySummary.empty();
    final group = _classifyTaskGroup(task, activity);
    grouped.putIfAbsent(group, () => <ProductionTask>[]).add(task);
  }

  final order = [
    _PhaseTaskGroup.approved,
    _PhaseTaskGroup.inProgress,
    _PhaseTaskGroup.assigned,
    _PhaseTaskGroup.attention,
  ];

  return order
      .where((group) => grouped[group]?.isNotEmpty == true)
      .map((group) => (group, grouped[group]!))
      .toList();
}

_PhaseTaskGroup _classifyTaskGroup(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
) {
  if (_isTaskClosed(task, activity)) {
    return _PhaseTaskGroup.approved;
  }

  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  final normalizedStatus = task.status.trim().toLowerCase();
  final now = DateTime.now();
  final isOverdue =
      task.dueDate != null &&
      _normalizeDay(task.dueDate!).isBefore(_normalizeDay(now));

  if (normalizedApproval == "rejected" ||
      normalizedStatus == "blocked" ||
      isOverdue) {
    return _PhaseTaskGroup.attention;
  }

  if (activity.logCount > 0 ||
      normalizedStatus == "in_progress" ||
      normalizedStatus == "pending_approval") {
    return _PhaseTaskGroup.inProgress;
  }

  if (task.assignedCount > 0 ||
      task.assignedStaffIds.isNotEmpty ||
      task.assignedStaffId.trim().isNotEmpty) {
    return _PhaseTaskGroup.assigned;
  }

  return _PhaseTaskGroup.attention;
}

bool _matchesStatusFilter(
  _PhaseTaskGroup group,
  _PhaseTaskStatusFilter filter,
) {
  return switch (filter) {
    _PhaseTaskStatusFilter.all => true,
    _PhaseTaskStatusFilter.approved => group == _PhaseTaskGroup.approved,
    _PhaseTaskStatusFilter.inProgress => group == _PhaseTaskGroup.inProgress,
    _PhaseTaskStatusFilter.assigned => group == _PhaseTaskGroup.assigned,
    _PhaseTaskStatusFilter.attention => group == _PhaseTaskGroup.attention,
  };
}

bool _taskMatchesDate(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
  DateTime selectedDate,
) {
  final normalizedSelectedDate = _normalizeDay(selectedDate);
  for (final value in [
    task.startDate,
    task.dueDate,
    task.completedAt,
    activity.lastWorkDate,
  ]) {
    if (value != null && _isSameDay(value, normalizedSelectedDate)) {
      return true;
    }
  }

  for (final value in activity.workDates) {
    if (_isSameDay(value, normalizedSelectedDate)) {
      return true;
    }
  }
  return false;
}

bool _isTaskClosed(ProductionTask task, [_PhaseTaskActivitySummary? activity]) {
  final normalizedStatus = task.status.trim().toLowerCase();
  // WHY: Task approvalStatus tracks assignment review, not proof-backed work
  // approval. Only completed tasks or approved progress rows can close a task.
  return normalizedStatus == "done" ||
      task.completedAt != null ||
      (activity?.hasApprovedProgress ?? false);
}

DateTime? _resolvePhaseStart(
  ProductionPhase phase,
  List<ProductionTask> tasks,
) {
  DateTime? value = phase.startDate;
  for (final task in tasks) {
    final candidate = task.startDate ?? task.dueDate;
    if (candidate == null) {
      continue;
    }
    if (value == null || candidate.isBefore(value)) {
      value = candidate;
    }
  }
  return value;
}

DateTime? _resolvePhaseEnd(ProductionPhase phase, List<ProductionTask> tasks) {
  DateTime? value = phase.endDate;
  for (final task in tasks) {
    final candidate = task.dueDate ?? task.startDate ?? task.completedAt;
    if (candidate == null) {
      continue;
    }
    if (value == null || candidate.isAfter(value)) {
      value = candidate;
    }
  }
  return value;
}

String _formatWindow(DateTime? start, DateTime? end) {
  if (start == null && end == null) {
    return _phaseDash;
  }
  return "${_formatOptionalDate(start)} → ${_formatOptionalDate(end)}";
}

String _formatOptionalDate(DateTime? value) {
  return value == null
      ? _phaseDash
      : formatDateLabel(value, fallback: _phaseDash);
}

String _formatTaskApproval(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
) {
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  // WHY: Approved progress rows are the real execution approval signal.
  if (activity.hasApprovedProgress) {
    return "Approved";
  }
  if (activity.logCount > 0) {
    return "Pending progress approval";
  }
  if (normalizedApproval == "rejected") {
    return "Assignment rejected";
  }
  if (normalizedApproval == "pending_approval") {
    return "Assignment pending";
  }
  if (normalizedApproval == "approved") {
    return "Assignment approved";
  }
  return "Open";
}

AppStatusTone _taskApprovalTone(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
) {
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  if (activity.hasApprovedProgress) {
    return AppStatusTone.success;
  }
  if (activity.logCount > 0) {
    return AppStatusTone.warning;
  }
  if (normalizedApproval == "rejected") {
    return AppStatusTone.danger;
  }
  if (normalizedApproval == "pending_approval") {
    return AppStatusTone.warning;
  }
  if (normalizedApproval == "approved") {
    return AppStatusTone.info;
  }
  return AppStatusTone.neutral;
}

String _taskDescriptor(ProductionTask task) {
  final source = task.taskType.trim().isNotEmpty
      ? task.taskType
      : task.roleRequired.trim().isNotEmpty
      ? task.roleRequired
      : _taskTypeFallback;
  return formatProductionStatusLabel(source);
}

String _resolveAssigneeLabel(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
) {
  if (activity.latestFarmerName.trim().isNotEmpty) {
    return activity.latestFarmerName.trim();
  }
  if (task.assignedCount > 0) {
    return "${task.assignedCount} assigned";
  }
  return _unassignedLabel;
}

_TaskProgressSnapshot _taskProgressSnapshot(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
) {
  if (_isTaskClosed(task, activity)) {
    return const _TaskProgressSnapshot(
      value: 1,
      label: "Complete",
      color: AppColors.success,
    );
  }
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  final normalizedStatus = task.status.trim().toLowerCase();
  if (normalizedApproval == "rejected" || normalizedStatus == "blocked") {
    return const _TaskProgressSnapshot(
      value: 0.12,
      label: "Attention required",
      color: AppColors.error,
    );
  }
  if (activity.logCount > 0 || normalizedStatus == "in_progress") {
    return const _TaskProgressSnapshot(
      value: 0.62,
      label: "Work in progress",
      color: AppColors.analyticsAccent,
    );
  }
  if (task.assignedCount > 0 || task.assignedStaffIds.isNotEmpty) {
    return const _TaskProgressSnapshot(
      value: 0.28,
      label: "Assigned and waiting",
      color: AppColors.warning,
    );
  }
  return const _TaskProgressSnapshot(
    value: 0.08,
    label: "Not started",
    color: AppColors.recordsAccent,
  );
}

bool _isApprovedProgressRow(ProductionTimelineRow row) {
  final normalizedApproval = row.approvalState.trim().toLowerCase();
  return normalizedApproval == "approved" || row.approvedAt != null;
}

bool _isTimelineRowNewer(
  ProductionTimelineRow left,
  ProductionTimelineRow right,
) {
  final dateCompare = _compareDate(left.workDate, right.workDate);
  if (dateCompare != 0) {
    return dateCompare > 0;
  }
  return left.entryIndex > right.entryIndex;
}

int _approvalSortRank(ProductionTask task, _PhaseTaskActivitySummary activity) {
  final group = _classifyTaskGroup(task, activity);
  return switch (group) {
    _PhaseTaskGroup.approved => 0,
    _PhaseTaskGroup.inProgress => 1,
    _PhaseTaskGroup.assigned => 2,
    _PhaseTaskGroup.attention => 3,
  };
}

String _groupLabel(_PhaseTaskGroup group) {
  return switch (group) {
    _PhaseTaskGroup.approved => _approvedLabel,
    _PhaseTaskGroup.inProgress => _inProgressLabel,
    _PhaseTaskGroup.assigned => _assignedLabel,
    _PhaseTaskGroup.attention => _attentionLabel,
  };
}

AppStatusTone _groupTone(_PhaseTaskGroup group) {
  return switch (group) {
    _PhaseTaskGroup.approved => AppStatusTone.success,
    _PhaseTaskGroup.inProgress => AppStatusTone.info,
    _PhaseTaskGroup.assigned => AppStatusTone.warning,
    _PhaseTaskGroup.attention => AppStatusTone.danger,
  };
}

IconData _groupIcon(_PhaseTaskGroup group) {
  return switch (group) {
    _PhaseTaskGroup.approved => Icons.task_alt_outlined,
    _PhaseTaskGroup.inProgress => Icons.timeline_outlined,
    _PhaseTaskGroup.assigned => Icons.assignment_ind_outlined,
    _PhaseTaskGroup.attention => Icons.priority_high_rounded,
  };
}

Color _toneAccentColor(AppStatusTone tone) {
  return switch (tone) {
    AppStatusTone.success => AppColors.productionAccent,
    AppStatusTone.info => AppColors.analyticsAccent,
    AppStatusTone.warning => AppColors.warning,
    AppStatusTone.danger => AppColors.error,
    AppStatusTone.neutral => AppColors.recordsAccent,
  };
}

DateTime _normalizeDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _isSameDay(DateTime? left, DateTime? right) {
  if (left == null || right == null) {
    return false;
  }
  final leftDay = _normalizeDay(left);
  final rightDay = _normalizeDay(right);
  return leftDay.year == rightDay.year &&
      leftDay.month == rightDay.month &&
      leftDay.day == rightDay.day;
}

bool _phaseIsDark(ColorScheme colorScheme) {
  return colorScheme.brightness == Brightness.dark;
}

Color _phaseToneSurface({
  required ColorScheme colorScheme,
  required Color accentColor,
  Color? baseColor,
  double lightTintAlpha = 0.08,
  double darkTintAlpha = 0.18,
}) {
  return Color.alphaBlend(
    accentColor.withValues(
      alpha: _phaseIsDark(colorScheme) ? darkTintAlpha : lightTintAlpha,
    ),
    baseColor ??
        (_phaseIsDark(colorScheme)
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surface),
  );
}

Color _phaseToneBorder({
  required ColorScheme colorScheme,
  required Color accentColor,
  double lightAlpha = 0.18,
  double darkAlpha = 0.42,
}) {
  return accentColor.withValues(
    alpha: _phaseIsDark(colorScheme) ? darkAlpha : lightAlpha,
  );
}

Color _phaseToneForeground({
  required ColorScheme colorScheme,
  required Color accentColor,
  double darkMix = 0.68,
}) {
  if (!_phaseIsDark(colorScheme)) {
    return accentColor;
  }
  return Color.lerp(colorScheme.onSurface, accentColor, darkMix) ?? accentColor;
}

Color _phasePrimaryContentColor(ColorScheme colorScheme) {
  return _phaseIsDark(colorScheme)
      ? colorScheme.onSurface
      : AppColors.primaryDark;
}

ButtonStyle _phaseActionButtonStyle(
  BuildContext context, {
  required Color accentColor,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    foregroundColor: _phaseToneForeground(
      colorScheme: colorScheme,
      accentColor: accentColor,
      darkMix: 0.6,
    ),
    backgroundColor: _phaseToneSurface(
      colorScheme: colorScheme,
      accentColor: accentColor,
      lightTintAlpha: 0.1,
      darkTintAlpha: 0.2,
      baseColor: _surfaceColor(context),
    ),
    side: BorderSide(
      color: _phaseToneBorder(
        colorScheme: colorScheme,
        accentColor: accentColor,
        lightAlpha: 0.22,
        darkAlpha: 0.46,
      ),
    ),
    visualDensity: VisualDensity.compact,
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

Color _pageBackground(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? AppColors.darkBackground
      : AppColors.background;
}

Color _surfaceColor(BuildContext context, {bool elevated = false}) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.dark) {
    return elevated
        ? theme.colorScheme.surfaceContainerLow
        : theme.colorScheme.surfaceContainer;
  }
  return elevated ? Colors.white : theme.colorScheme.surface;
}

Color _borderColor(BuildContext context) {
  return Theme.of(context).colorScheme.outlineVariant;
}

Color _trackColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerHighest
      : theme.colorScheme.surfaceContainerHigh;
}

int _compareDate(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left.compareTo(right);
}
