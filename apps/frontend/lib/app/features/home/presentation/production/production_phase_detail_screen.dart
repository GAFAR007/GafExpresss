/// WHAT: Renders the production phase detail screen, task filters, and daily
/// execution cards for a single production phase.
/// WHY: Operations teams need a current-day view of phase work without drilling
/// into each task or inheriting stale filter defaults from old activity.
/// HOW: The screen watches plan detail state, derives local task groupings, and
/// applies lightweight responsive filter controls before rendering the cards.
library;

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
const String _phaseDash = "—";
const String _unassignedLabel = "Unassigned";
const String _taskTypeFallback = "Task";
const String _viewLatestProofLabel = "View latest proof";
const double _pagePadding = 20;
const double _sectionSpacing = 16;
const double _cardRadius = 22;
const double _compactRadius = 16;

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
            if (phaseTasks.isEmpty) {
              return ProductionRefreshOverlay(
                isRefreshing: isRefreshingDetail,
                child: ListView(
                  padding: const EdgeInsets.all(_pagePadding),
                  children: const [
                    ProductionEmptyState(
                      title: _noTasksTitle,
                      message: _noTasksMessage,
                    ),
                  ],
                ),
              );
            }

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
                          _PhaseSnapshotSection(
                            totalTasks: totalTasks,
                            completedTasks: completedTasks,
                            remainingTasks: remainingTasks,
                            proofTaskCount: proofTaskCount,
                            proofRowCount: proofRows.length,
                            completionPercent: completionPercent,
                          ),
                          const SizedBox(height: _sectionSpacing),
                          _PhaseProgressCard(
                            completedTasks: completedTasks,
                            remainingTasks: remainingTasks,
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
                                    title: _selectedDateFilter == null
                                        ? _noMatchesTitle
                                        : _noDateMatchesTitle,
                                    message: _selectedDateFilter == null
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
            colorScheme.secondary.withValues(alpha: isDark ? 0.16 : 0.08),
            _surfaceColor(context, elevated: true),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: _shadowColor(context),
            blurRadius: isDark ? 22 : 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planTitle.trim().isEmpty ? "Untitled production plan" : planTitle,
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phase.name,
                      style: textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _heroSubtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              ProductionStatusPill(label: phase.status),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PhaseMetaChip(
                icon: Icons.category_outlined,
                label:
                    "$_typeLabel: ${formatProductionStatusLabel(phase.phaseType)}",
                tone: AppStatusTone.neutral,
              ),
              _PhaseMetaChip(
                icon: Icons.calendar_month_outlined,
                label:
                    "$_windowLabel: ${_formatWindow(scheduledStart, scheduledEnd)}",
                tone: AppStatusTone.info,
              ),
              _PhaseMetaChip(
                icon: Icons.task_alt_outlined,
                label: "$_doneLabel: $completedTasks / $totalTasks",
                tone: AppStatusTone.success,
              ),
              _PhaseMetaChip(
                icon: Icons.pending_actions_outlined,
                label: "$_leftLabel: $remainingTasks",
                tone: remainingTasks > 0
                    ? AppStatusTone.warning
                    : AppStatusTone.success,
              ),
              _PhaseMetaChip(
                icon: Icons.photo_library_outlined,
                label: "$_proofRowsShortLabel: $proofRowCount",
                tone: AppStatusTone.info,
              ),
            ],
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
    final items = [
      (
        _totalTasksLabel,
        "$totalTasks",
        Icons.format_list_numbered_rounded,
        AppStatusTone.info,
      ),
      (
        _doneInPhaseLabel,
        "$completedTasks",
        Icons.check_circle_outline_rounded,
        AppStatusTone.success,
      ),
      (
        _leftInPhaseLabel,
        "$remainingTasks",
        Icons.pending_actions_outlined,
        remainingTasks > 0 ? AppStatusTone.warning : AppStatusTone.success,
      ),
      (
        _tasksWithProofLabel,
        "$proofTaskCount",
        Icons.verified_outlined,
        AppStatusTone.info,
      ),
      (
        _proofRowsLabel,
        "$proofRowCount",
        Icons.photo_library_outlined,
        AppStatusTone.info,
      ),
      (
        _completionPercentLabel,
        "$completionPercent%",
        Icons.insights_outlined,
        completionPercent >= 85
            ? AppStatusTone.success
            : completionPercent >= 60
            ? AppStatusTone.warning
            : AppStatusTone.info,
      ),
    ];

    return _PhaseSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProductionSectionHeader(
            title: _snapshotTitle,
            subtitle: _snapshotSubtitle,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 1100
                  ? 6
                  : constraints.maxWidth >= 880
                  ? 3
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 112,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ProductionKpiCard(
                    label: item.$1,
                    value: item.$2,
                    icon: item.$3,
                    tone: item.$4,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PhaseProgressCard extends StatelessWidget {
  final int completedTasks;
  final int remainingTasks;
  final int completionPercent;

  const _PhaseProgressCard({
    required this.completedTasks,
    required this.remainingTasks,
    required this.completionPercent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressValue = completionPercent / 100;
    return _PhaseSurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _progressTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressValue.clamp(0, 1),
              minHeight: 10,
              color: AppColors.success,
              backgroundColor: _trackColor(context),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
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

    return _PhaseSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _taskSectionTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
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
      ),
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
    final colors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: tone,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: colors.foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "${_groupLabel(group)}  $count",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _PhaseTaskCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        borderRadius: BorderRadius.circular(_compactRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceColor(context),
            borderRadius: BorderRadius.circular(_compactRadius),
            border: Border.all(color: _borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 860;
                  return compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PhaseTaskHeader(
                              task: task,
                              activity: activity,
                              headerSummary: headerSummary,
                              approvalLabel: approvalLabel,
                              approvalTone: approvalTone,
                              isClosed: isClosed,
                              onPreviewProof: onPreviewProof,
                            ),
                            const SizedBox(height: 14),
                            _PhaseTaskMetricsWrap(
                              task: task,
                              activity: activity,
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: _PhaseTaskHeader(
                                task: task,
                                activity: activity,
                                headerSummary: headerSummary,
                                approvalLabel: approvalLabel,
                                approvalTone: approvalTone,
                                isClosed: isClosed,
                                onPreviewProof: onPreviewProof,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 5,
                              child: _PhaseTaskMetricsWrap(
                                task: task,
                                activity: activity,
                              ),
                            ),
                          ],
                        );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "$_progressLabel: ${progress.label}",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    "${(progress.value * 100).round()}%",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: progress.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.value,
                  minHeight: 7,
                  color: progress.color,
                  backgroundColor: _trackColor(context),
                ),
              ),
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
  final VoidCallback? onPreviewProof;

  const _PhaseTaskHeader({
    required this.task,
    required this.activity,
    required this.headerSummary,
    required this.approvalLabel,
    required this.approvalTone,
    required this.isClosed,
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
        if (onPreviewProof != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppStatusBadgeColors.fromTheme(
                theme: theme,
                tone: AppStatusTone.info,
              ).foreground,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: onPreviewProof,
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text(_viewLatestProofLabel),
          ),
        ],
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
            if (task.instructions.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                task.instructions.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ],
        );
      },
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

class _PhaseMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusTone tone;

  const _PhaseMetaChip({
    required this.icon,
    required this.label,
    this.tone = AppStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);
    final isNeutral = tone == AppStatusTone.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isNeutral ? _surfaceColor(context) : colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isNeutral
              ? _borderColor(context)
              : colors.foreground.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isNeutral ? theme.colorScheme.primary : colors.foreground,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isNeutral
                    ? theme.colorScheme.onSurface
                    : colors.foreground,
                fontWeight: FontWeight.w600,
              ),
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

class _PhaseSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _PhaseSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _surfaceColor(context, elevated: true),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: _shadowColor(context),
            blurRadius: isDark ? 18 : 20,
            offset: const Offset(0, 8),
          ),
        ],
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
                TextButton(
                  onPressed: onClear,
                  style: AppButtonStyles.text(
                    theme: theme,
                    tone: AppStatusTone.neutral,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: const Text("All"),
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

Color _shadowColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.colorScheme.shadow.withValues(
    alpha: theme.brightness == Brightness.dark ? 0.22 : 0.07,
  );
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
