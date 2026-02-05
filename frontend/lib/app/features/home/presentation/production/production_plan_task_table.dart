/// lib/app/features/home/presentation/production/production_plan_task_table.dart
/// ----------------------------------------------------------------------------
/// WHAT:
/// - Table layout for production plan tasks (phase flow + status + assignments).
///
/// WHY:
/// - Replaces long card lists with a compact, scannable grid.
/// - Makes it faster to see who is assigned, what is done, and what is blocked.
///
/// HOW:
/// - Builds a phase flow row, summary KPIs, and a per-phase task table.
/// - Uses draft controller callbacks to update tasks inline.
/// - Logs table build and user interactions for diagnostics.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _logTag = "PRODUCTION_TASK_TABLE";
const String _logBuild = "build()";
const String _logStatusChange = "status_change";
const String _logDoneToggle = "done_toggle";
const String _logClearToggle = "clear_toggle";
const String _logCompactToggle = "compact_toggle";
const String _logExpandToggle = "expand_toggle";
const String _logCompactInit = "compact_init";
const String _extraTaskIdKey = "taskId";
const String _extraStatusKey = "status";
const String _extraCompactKey = "compact";
const String _extraExpandedKey = "expanded";

const String _summaryTitle = "Task summary";
const String _summaryTotalLabel = "Total tasks";
const String _summaryDoneLabel = "Done";
const String _summaryBlockedLabel = "Blocked";
const String _summaryUnassignedLabel = "Unassigned";
const String _summaryEmpty = "No tasks yet. Add tasks to start planning.";
const String _summaryProgressLabel = "Progress";
const String _compactToggleLabel = "Compact view";
const String _compactToggleHint = "Reduce scrolling on mobile.";
const String _expandLabel = "Expand task";
const String _collapseLabel = "Collapse task";
const String _unassignedLabel = "Unassigned";
const String _metaLabelSuffix = ":";

const String _phaseProgressLabel = "Progress";
const String _addTaskLabel = "Add task";
const String _phaseEmptyLabel = "No tasks in this phase yet.";

const String _columnDone = "Done";
const String _columnTask = "Task";
const String _columnRole = "Role";
const String _columnStaff = "Staff";
const String _columnWeight = "Weight";
const String _columnStatus = "Status";
const String _columnInstructions = "Instructions";
const String _columnCompleted = "Completed";
const String _selectPlaceholder = "Select";
const String _instructionsHint = "Add instructions";
const String _completedPlaceholder = "-";
const String _removeTaskTooltip = "Remove task";

const String _statusNotStarted = "Not started";
const String _statusInProgress = "In progress";
const String _statusBlocked = "Blocked";
const String _statusDone = "Done";

const double _sectionSpacing = 16;
const double _mobileBreakpoint = 720;
const double _mobileCardSpacing = 12;
const double _mobileFieldSpacing = 10;
const double _mobileHeaderSpacing = 6;
const double _mobileTogglePadding = 12;

// WHY: Defaults to comfy; mobile init can override once per screen load.
final _compactModeProvider = StateProvider<bool>((ref) => false);
// WHY: Prevent re-initializing compact mode on every rebuild.
final _compactModeInitializedProvider = StateProvider<bool>((ref) => false);
final _expandedTaskIdsProvider =
    StateProvider<Set<String>>((ref) => <String>{});
const double _summarySpacing = 12;
const double _summaryProgressHeight = 6;
const double _phaseCardRadius = 16;
const double _phaseCardPadding = 12;
const double _phaseHeaderSpacing = 8;
const double _tableHeaderHeight = 40;
const double _rowSpacing = 8;
const double _rowPadding = 8;
const double _chipPadding = 8;
const double _chipSpacing = 8;
const double _progressHeight = 6;
const double _iconSize = 16;
const double _denseFieldSpacing = 6;
const double _rowBorderOpacity = 0.35;

const double _colDoneWidth = 60;
const double _colTaskWidth = 220;
const double _colRoleWidth = 160;
const double _colStaffWidth = 180;
const double _colWeightWidth = 90;
const double _colStatusWidth = 160;
const double _colInstructionsWidth = 220;
const double _colCompletedWidth = 140;
const double _colActionsWidth = 60;

const List<int> _weightOptions = [1, 2, 3, 4, 5];

class ProductionPlanTaskTable extends ConsumerWidget {
  final ProductionPlanDraftState draft;
  final List<BusinessStaffProfileSummary> staff;
  final void Function(int phaseIndex) onAddTask;
  final void Function(int phaseIndex, String taskId) onRemoveTask;

  const ProductionPlanTaskTable({
    super.key,
    required this.draft,
    required this.staff,
    required this.onAddTask,
    required this.onRemoveTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _logBuild);
    // WHY: Summary keeps the workload and completion visible at a glance.
    final summary = _TaskSummary.fromDraft(draft);
    final isNarrow = MediaQuery.of(context).size.width < _mobileBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TaskSummaryBar(summary: summary),
        if (isNarrow) ...[
          const SizedBox(height: _summarySpacing),
          _MobileViewToggle(),
        ],
        const SizedBox(height: _summarySpacing),
        // WHY: Phase flow row provides a quick visual of plan progression.
        _PhaseFlowRow(phases: draft.phases),
        const SizedBox(height: _sectionSpacing),
        if (summary.totalTasks == 0) _EmptyTableMessage(),
        if (summary.totalTasks == 0)
          const SizedBox(height: _sectionSpacing),
        ...draft.phases.asMap().entries.map(
              (entry) => _PhaseTableCard(
                phaseIndex: entry.key,
                phase: entry.value,
                staff: staff,
                onAddTask: () => onAddTask(entry.key),
                onRemoveTask: (taskId) => onRemoveTask(entry.key, taskId),
              ),
            ),
      ],
    );
  }
}

class _TaskSummaryBar extends StatelessWidget {
  final _TaskSummary summary;

  const _TaskSummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progressColor = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: AppStatusTone.info,
    ).foreground;

    return Container(
      padding: const EdgeInsets.all(_summarySpacing),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _summaryTitle,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: _summarySpacing),
          Wrap(
            spacing: _chipSpacing,
            runSpacing: _chipSpacing,
            children: [
              _SummaryChip(label: _summaryTotalLabel, value: summary.totalTasks),
              _SummaryChip(label: _summaryDoneLabel, value: summary.doneTasks),
              _SummaryChip(
                label: _summaryBlockedLabel,
                value: summary.blockedTasks,
              ),
              _SummaryChip(
                label: _summaryUnassignedLabel,
                value: summary.unassignedTasks,
              ),
            ],
          ),
          const SizedBox(height: _summarySpacing),
          Text(
            _summaryProgressLabel,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _chipSpacing),
          ClipRRect(
            borderRadius: BorderRadius.circular(_phaseCardRadius),
            child: LinearProgressIndicator(
              value: summary.completionRatio,
              minHeight: _summaryProgressHeight,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileViewToggle extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MobileViewToggle> createState() => _MobileViewToggleState();
}

class _MobileViewToggleState extends ConsumerState<_MobileViewToggle> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // WHY: Initialize compact mode once based on the current screen width.
    final hasInit = ref.read(_compactModeInitializedProvider);
    if (hasInit) return;
    final isNarrow = MediaQuery.of(context).size.width < _mobileBreakpoint;
    ref.read(_compactModeProvider.notifier).state = isNarrow;
    ref.read(_compactModeInitializedProvider.notifier).state = true;
    AppDebug.log(
      _logTag,
      _logCompactInit,
      extra: {_extraCompactKey: isNarrow},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = ref.watch(_compactModeProvider);

    return Container(
      padding: const EdgeInsets.all(_mobileTogglePadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _compactToggleLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: _mobileHeaderSpacing),
                Text(
                  _compactToggleHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isCompact,
            onChanged: (value) {
              AppDebug.log(
                _logTag,
                _logCompactToggle,
                extra: {_extraCompactKey: value},
              );
              ref.read(_compactModeProvider.notifier).state = value;
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;

  const _SummaryChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: AppStatusTone.neutral,
    );

    return Container(
      padding: const EdgeInsets.all(_chipPadding),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.foreground,
            ),
          ),
          const SizedBox(width: _chipSpacing),
          Text(
            value.toString(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseFlowRow extends StatelessWidget {
  final List<ProductionPhaseDraft> phases;

  const _PhaseFlowRow({required this.phases});

  @override
  Widget build(BuildContext context) {
    // WHY: Flow chips make it easy to jump between phases mentally.
    final items = phases.map((phase) {
      final summary = _PhaseSummary.fromPhase(phase);
      return _PhaseFlowChip(phase: phase, summary: summary);
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items
            .map((chip) => Padding(
                  padding: const EdgeInsets.only(right: _chipSpacing),
                  child: chip,
                ))
            .toList(),
      ),
    );
  }
}

class _PhaseFlowChip extends StatelessWidget {
  final ProductionPhaseDraft phase;
  final _PhaseSummary summary;

  const _PhaseFlowChip({
    required this.phase,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: summary.tone,
    );

    return Container(
      padding: const EdgeInsets.all(_chipPadding),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: colors.foreground.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(summary.icon, size: _iconSize, color: colors.foreground),
          const SizedBox(width: _chipSpacing),
          Text(
            phase.name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseTableCard extends ConsumerWidget {
  final int phaseIndex;
  final ProductionPhaseDraft phase;
  final List<BusinessStaffProfileSummary> staff;
  final VoidCallback onAddTask;
  final ValueChanged<String> onRemoveTask;

  const _PhaseTableCard({
    required this.phaseIndex,
    required this.phase,
    required this.staff,
    required this.onAddTask,
    required this.onRemoveTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = _PhaseSummary.fromPhase(phase);
    // WHY: Use a compact card list on narrow screens to reduce horizontal scroll.
    final isNarrow = MediaQuery.of(context).size.width < _mobileBreakpoint;

    return Container(
      margin: const EdgeInsets.only(bottom: _sectionSpacing),
      padding: const EdgeInsets.all(_phaseCardPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  phase.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddTask,
                icon: const Icon(Icons.add),
                label: const Text(_addTaskLabel),
              ),
            ],
          ),
          const SizedBox(height: _phaseHeaderSpacing),
          Row(
            children: [
              Text(
                _phaseProgressLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: _chipSpacing),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_phaseCardRadius),
                  child: LinearProgressIndicator(
                    value: progress.ratio,
                    minHeight: _progressHeight,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppStatusBadgeColors.fromTheme(
                        theme: theme,
                        tone: progress.tone,
                      ).foreground,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _chipSpacing),
              Text(
                "${progress.doneTasks}/${progress.totalTasks}",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: _phaseHeaderSpacing),
          if (phase.tasks.isEmpty)
            Text(
              _phaseEmptyLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else if (isNarrow)
            _PhaseTaskList(
              phaseIndex: phaseIndex,
              phase: phase,
              staff: staff,
              onRemoveTask: onRemoveTask,
            )
          else
            _PhaseTaskTable(
              phaseIndex: phaseIndex,
              phase: phase,
              staff: staff,
              onRemoveTask: onRemoveTask,
            ),
        ],
      ),
    );
  }
}

class _PhaseTaskList extends ConsumerWidget {
  final int phaseIndex;
  final ProductionPhaseDraft phase;
  final List<BusinessStaffProfileSummary> staff;
  final ValueChanged<String> onRemoveTask;

  const _PhaseTaskList({
    required this.phaseIndex,
    required this.phase,
    required this.staff,
    required this.onRemoveTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedNotifier = ref.read(_expandedTaskIdsProvider.notifier);
    // WHY: Mobile list keeps tasks readable without horizontal scrolling.
    return Column(
      children: phase.tasks
          .map(
            (task) => _TaskMobileCard(
              phaseIndex: phaseIndex,
              task: task,
              staff: staff,
              onRemove: () {
                // WHY: Clear expansion state when a task is removed.
                expandedNotifier.update((state) {
                  if (!state.contains(task.id)) return state;
                  final next = {...state};
                  next.remove(task.id);
                  return next;
                });
                onRemoveTask(task.id);
              },
            ),
          )
          .toList(),
    );
  }
}

class _PhaseTaskTable extends StatelessWidget {
  final int phaseIndex;
  final ProductionPhaseDraft phase;
  final List<BusinessStaffProfileSummary> staff;
  final ValueChanged<String> onRemoveTask;

  const _PhaseTaskTable({
    required this.phaseIndex,
    required this.phase,
    required this.staff,
    required this.onRemoveTask,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep header and rows aligned for readability.
    final header = _TaskTableHeader();
    final rows = phase.tasks
        .map(
          (task) => _TaskTableRow(
            phaseIndex: phaseIndex,
            task: task,
            staff: staff,
            onRemove: () => onRemoveTask(task.id),
          ),
        )
        .toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: _rowSpacing),
          ...rows,
        ],
      ),
    );
  }
}

class _TaskTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: _tableHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
      ),
      child: Row(
        children: [
          _HeaderCell(width: _colDoneWidth, label: _columnDone, style: textTheme),
          _HeaderCell(width: _colTaskWidth, label: _columnTask, style: textTheme),
          _HeaderCell(width: _colRoleWidth, label: _columnRole, style: textTheme),
          _HeaderCell(width: _colStaffWidth, label: _columnStaff, style: textTheme),
          _HeaderCell(width: _colWeightWidth, label: _columnWeight, style: textTheme),
          _HeaderCell(width: _colStatusWidth, label: _columnStatus, style: textTheme),
          _HeaderCell(
            width: _colInstructionsWidth,
            label: _columnInstructions,
            style: textTheme,
          ),
          _HeaderCell(
            width: _colCompletedWidth,
            label: _columnCompleted,
            style: textTheme,
          ),
          const SizedBox(width: _colActionsWidth),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final double width;
  final String label;
  final TextTheme style;

  const _HeaderCell({
    required this.width,
    required this.label,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: style.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TaskTableRow extends ConsumerWidget {
  final int phaseIndex;
  final ProductionTaskDraft task;
  final List<BusinessStaffProfileSummary> staff;
  final VoidCallback onRemove;

  const _TaskTableRow({
    required this.phaseIndex,
    required this.task,
    required this.staff,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final theme = Theme.of(context);
    // WHY: Row accents make status visible without extra clicks.
    final rowTone = _statusTone(task.status);
    final rowColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: rowTone,
    );
    final rowBackground = rowTone == AppStatusTone.neutral
        ? theme.colorScheme.surface
        : rowColors.background;
    final rowBorder = rowTone == AppStatusTone.neutral
        ? theme.colorScheme.outlineVariant
        : rowColors.foreground.withOpacity(_rowBorderOpacity);
    // WHY: Filter staff list by required role for accurate assignments.
    final roleStaff = staff
        .where((member) => member.staffRole == task.roleRequired)
        .toList();
    // WHY: Prevent stale staff selections when role changes.
    final selectedStaffId =
        roleStaff.any((member) => member.id == task.assignedStaffId)
            ? task.assignedStaffId
            : null;

    return Container(
      padding: const EdgeInsets.all(_rowPadding),
      margin: const EdgeInsets.only(bottom: _rowSpacing),
      decoration: BoxDecoration(
        color: rowBackground,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: rowBorder),
      ),
      child: Row(
        children: [
          _TaskDoneCell(
            task: task,
            onDone: () {
              AppDebug.log(
                _logTag,
                _logDoneToggle,
                extra: {_extraTaskIdKey: task.id},
              );
              controller.markTaskDone(phaseIndex, task.id);
            },
            onClear: () {
              AppDebug.log(
                _logTag,
                _logClearToggle,
                extra: {_extraTaskIdKey: task.id},
              );
              controller.clearTaskDone(phaseIndex, task.id);
            },
          ),
          _TaskTitleCell(
            task: task,
            onChanged: (value) =>
                controller.updateTaskTitle(phaseIndex, task.id, value),
          ),
          const SizedBox(width: _denseFieldSpacing),
          _TaskRoleCell(
            value: task.roleRequired,
            onChanged: (value) =>
                controller.updateTaskRole(phaseIndex, task.id, value),
          ),
          const SizedBox(width: _denseFieldSpacing),
          _TaskStaffCell(
            staff: roleStaff,
            selectedStaffId: selectedStaffId,
            onChanged: roleStaff.isEmpty
                ? null
                : (value) =>
                    controller.updateTaskStaff(phaseIndex, task.id, value),
          ),
          const SizedBox(width: _denseFieldSpacing),
          _TaskWeightCell(
            value: task.weight,
            onChanged: (value) =>
                controller.updateTaskWeight(phaseIndex, task.id, value),
          ),
          const SizedBox(width: _denseFieldSpacing),
          _TaskStatusCell(
            value: task.status,
            onChanged: (value) {
              AppDebug.log(
                _logTag,
                _logStatusChange,
                extra: {
                  _extraTaskIdKey: task.id,
                  _extraStatusKey: value.name,
                },
              );
              controller.updateTaskStatus(phaseIndex, task.id, value);
            },
          ),
          const SizedBox(width: _denseFieldSpacing),
          _TaskInstructionsCell(
            task: task,
            onChanged: (value) =>
                controller.updateTaskInstructions(phaseIndex, task.id, value),
          ),
          const SizedBox(width: _denseFieldSpacing),
          SizedBox(
            width: _colCompletedWidth,
            child: _CompletedCell(
              completedAt: task.completedAt,
              status: task.status,
            ),
          ),
          _TaskActionsCell(onRemove: onRemove),
        ],
      ),
    );
  }
}

class _TaskMobileCard extends ConsumerWidget {
  final int phaseIndex;
  final ProductionTaskDraft task;
  final List<BusinessStaffProfileSummary> staff;
  final VoidCallback onRemove;

  const _TaskMobileCard({
    required this.phaseIndex,
    required this.task,
    required this.staff,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final theme = Theme.of(context);
    final isCompact = ref.watch(_compactModeProvider);
    final expandedTasks = ref.watch(_expandedTaskIdsProvider);
    final isExpanded = !isCompact || expandedTasks.contains(task.id);
    // WHY: Card accents mirror desktop row status to keep cues consistent.
    final rowTone = _statusTone(task.status);
    final rowColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: rowTone,
    );
    final rowBackground = rowTone == AppStatusTone.neutral
        ? theme.colorScheme.surface
        : rowColors.background;
    final rowBorder = rowTone == AppStatusTone.neutral
        ? theme.colorScheme.outlineVariant
        : rowColors.foreground.withOpacity(_rowBorderOpacity);
    // WHY: Filter staff list by required role for accurate assignments.
    final roleStaff = staff
        .where((member) => member.staffRole == task.roleRequired)
        .toList();
    // WHY: Prevent stale staff selections when role changes.
    final selectedStaffId =
        roleStaff.any((member) => member.id == task.assignedStaffId)
            ? task.assignedStaffId
            : null;

    return Container(
      margin: const EdgeInsets.only(bottom: _mobileCardSpacing),
      padding: const EdgeInsets.all(_rowPadding),
      decoration: BoxDecoration(
        color: rowBackground,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: rowBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaskMobileHeaderRow(
            task: task,
            isCompact: isCompact,
            isExpanded: isExpanded,
            onToggleExpand: () {
              final nextExpanded = !expandedTasks.contains(task.id);
              AppDebug.log(
                _logTag,
                _logExpandToggle,
                extra: {
                  _extraTaskIdKey: task.id,
                  _extraExpandedKey: nextExpanded,
                },
              );
              ref.read(_expandedTaskIdsProvider.notifier).update((state) {
                final next = {...state};
                if (nextExpanded) {
                  next.add(task.id);
                } else {
                  next.remove(task.id);
                }
                return next;
              });
            },
            onDone: () {
              AppDebug.log(
                _logTag,
                _logDoneToggle,
                extra: {_extraTaskIdKey: task.id},
              );
              controller.markTaskDone(phaseIndex, task.id);
            },
            onClear: () {
              AppDebug.log(
                _logTag,
                _logClearToggle,
                extra: {_extraTaskIdKey: task.id},
              );
              controller.clearTaskDone(phaseIndex, task.id);
            },
            onTitleChanged: (value) =>
                controller.updateTaskTitle(phaseIndex, task.id, value),
            onRemove: onRemove,
          ),
          if (isCompact && !isExpanded) ...[
            const SizedBox(height: _mobileHeaderSpacing),
            _TaskMobileCollapsedMeta(
              status: task.status,
              roleLabel: formatStaffRoleLabel(
                task.roleRequired,
                fallback: task.roleRequired,
              ),
              staffLabel: _resolveStaffLabel(roleStaff, selectedStaffId),
              weight: task.weight,
            ),
          ] else ...[
            const SizedBox(height: _mobileFieldSpacing),
            _TaskMobileStatusField(
              value: task.status,
              onChanged: (value) {
                AppDebug.log(
                  _logTag,
                  _logStatusChange,
                  extra: {
                    _extraTaskIdKey: task.id,
                    _extraStatusKey: value.name,
                  },
                );
                controller.updateTaskStatus(phaseIndex, task.id, value);
              },
            ),
            const SizedBox(height: _mobileFieldSpacing),
            _TaskMobileRoleField(
              value: task.roleRequired,
              onChanged: (value) =>
                  controller.updateTaskRole(phaseIndex, task.id, value),
            ),
            const SizedBox(height: _mobileFieldSpacing),
            _TaskMobileStaffField(
              staff: roleStaff,
              selectedStaffId: selectedStaffId,
              onChanged: roleStaff.isEmpty
                  ? null
                  : (value) =>
                      controller.updateTaskStaff(phaseIndex, task.id, value),
            ),
            const SizedBox(height: _mobileFieldSpacing),
            _TaskMobileWeightRow(
              weight: task.weight,
              completedAt: task.completedAt,
              status: task.status,
              onChanged: (value) =>
                  controller.updateTaskWeight(phaseIndex, task.id, value),
            ),
            const SizedBox(height: _mobileFieldSpacing),
            _TaskMobileInstructionsField(
              value: task.instructions,
              onChanged: (value) =>
                  controller.updateTaskInstructions(phaseIndex, task.id, value),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskMobileHeaderRow extends StatelessWidget {
  final ProductionTaskDraft task;
  final bool isCompact;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onDone;
  final VoidCallback onClear;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onRemove;

  const _TaskMobileHeaderRow({
    required this.task,
    required this.isCompact,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onDone,
    required this.onClear,
    required this.onTitleChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          // WHY: Checkbox is the fastest done/clear action on mobile.
          value: task.status == ProductionTaskStatus.done,
          onChanged: (value) {
            if (value == true) {
              onDone();
            } else {
              onClear();
            }
          },
        ),
        const SizedBox(width: _denseFieldSpacing),
        Expanded(
          child: TextFormField(
            // WHY: Inline title edit keeps mobile flow fast.
            initialValue: task.title,
            decoration: const InputDecoration(
              isDense: true,
              labelText: _columnTask,
            ),
            onChanged: onTitleChanged,
          ),
        ),
        if (isCompact)
          IconButton(
            // WHY: Collapse reduces scrolling on mobile.
            onPressed: onToggleExpand,
            icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            tooltip: isExpanded ? _collapseLabel : _expandLabel,
          ),
        IconButton(
          // WHY: Keep remove action reachable without scrolling.
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: _removeTaskTooltip,
        ),
      ],
    );
  }
}

class _TaskMobileStatusField extends StatelessWidget {
  final ProductionTaskStatus value;
  final ValueChanged<ProductionTaskStatus> onChanged;

  const _TaskMobileStatusField({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<ProductionTaskStatus>(
      // WHY: Status drives planning flow; keep visible on mobile.
      value: value,
      decoration: const InputDecoration(
        isDense: true,
        labelText: _columnStatus,
      ),
      isExpanded: true,
      items: ProductionTaskStatus.values
          .map(
            (status) => DropdownMenuItem(
              value: status,
              child: Row(
                children: [
                  Icon(
                    _statusIcon(status),
                    size: _iconSize,
                    color: _statusColor(theme, status),
                  ),
                  const SizedBox(width: _denseFieldSpacing),
                  Expanded(
                    child: Text(
                      _statusLabel(status),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }
}

class _TaskMobileRoleField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TaskMobileRoleField({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // WHY: Role is required to filter staff options.
      value: value,
      decoration: const InputDecoration(
        isDense: true,
        labelText: _columnRole,
      ),
      isExpanded: true,
      items: staffRoleValues
          .map(
            (role) => DropdownMenuItem(
              value: role,
              child: Text(
                formatStaffRoleLabel(role, fallback: role),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }
}

class _TaskMobileStaffField extends StatelessWidget {
  final List<BusinessStaffProfileSummary> staff;
  final String? selectedStaffId;
  final ValueChanged<String?>? onChanged;

  const _TaskMobileStaffField({
    required this.staff,
    required this.selectedStaffId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // WHY: Assignment should remain scoped to the selected role.
      value: selectedStaffId,
      decoration: const InputDecoration(
        isDense: true,
        labelText: _columnStaff,
      ),
      isExpanded: true,
      hint: const Text(_selectPlaceholder),
      items: staff
          .map(
            (member) => DropdownMenuItem(
              value: member.id,
              child: Text(
                member.userName ?? member.userEmail ?? member.id,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _TaskMobileWeightRow extends StatelessWidget {
  final int weight;
  final DateTime? completedAt;
  final ProductionTaskStatus status;
  final ValueChanged<int> onChanged;

  const _TaskMobileWeightRow({
    required this.weight,
    required this.completedAt,
    required this.status,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            // WHY: Weight helps prioritize tasks on the go.
            value: weight,
            decoration: const InputDecoration(
              isDense: true,
              labelText: _columnWeight,
            ),
            isExpanded: true,
            items: _weightOptions
                .map(
                  (weight) => DropdownMenuItem(
                    value: weight,
                    child: Text(weight.toString()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              onChanged(value);
            },
          ),
        ),
        const SizedBox(width: _mobileFieldSpacing),
        Expanded(
          child: _MobileCompletedChip(
            completedAt: completedAt,
            status: status,
          ),
        ),
      ],
    );
  }
}

class _TaskMobileInstructionsField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TaskMobileInstructionsField({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      // WHY: Instructions need enough width for quick notes.
      initialValue: value,
      decoration: const InputDecoration(
        isDense: true,
        labelText: _columnInstructions,
        hintText: _instructionsHint,
      ),
      maxLines: 2,
      onChanged: onChanged,
    );
  }
}

class _TaskMobileCollapsedMeta extends StatelessWidget {
  final ProductionTaskStatus status;
  final String roleLabel;
  final String staffLabel;
  final int weight;

  const _TaskMobileCollapsedMeta({
    required this.status,
    required this.roleLabel,
    required this.staffLabel,
    required this.weight,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Collapsed meta keeps key info visible without extra scrolling.
    return Wrap(
      spacing: _chipSpacing,
      runSpacing: _chipSpacing,
      children: [
        _MetaChip(
          label: _columnStatus,
          value: _statusLabel(status),
          tone: _statusTone(status),
        ),
        _MetaChip(
          label: _columnRole,
          value: roleLabel,
          tone: AppStatusTone.neutral,
        ),
        _MetaChip(
          label: _columnStaff,
          value: staffLabel,
          tone: AppStatusTone.neutral,
        ),
        _MetaChip(
          label: _columnWeight,
          value: weight.toString(),
          tone: AppStatusTone.neutral,
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;
  final AppStatusTone tone;

  const _MetaChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _chipPadding,
        vertical: _denseFieldSpacing,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: colors.foreground.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label$_metaLabelSuffix",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: _denseFieldSpacing),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskDoneCell extends StatelessWidget {
  final ProductionTaskDraft task;
  final VoidCallback onDone;
  final VoidCallback onClear;

  const _TaskDoneCell({
    required this.task,
    required this.onDone,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colDoneWidth,
      child: Checkbox(
        // WHY: Checkbox provides the fastest done/clear action.
        value: task.status == ProductionTaskStatus.done,
        onChanged: (value) {
          if (value == true) {
            onDone();
          } else {
            onClear();
          }
        },
      ),
    );
  }
}

class _TaskTitleCell extends StatelessWidget {
  final ProductionTaskDraft task;
  final ValueChanged<String> onChanged;

  const _TaskTitleCell({
    required this.task,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colTaskWidth,
      child: TextFormField(
        // WHY: Inline title editing keeps the table fast to scan and edit.
        initialValue: task.title,
        decoration: const InputDecoration(
          isDense: true,
          hintText: _columnTask,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _TaskRoleCell extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TaskRoleCell({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colRoleWidth,
      child: DropdownButtonFormField<String>(
        // WHY: Role drives which staff can be assigned to the task.
        value: value,
        decoration: const InputDecoration(isDense: true),
        isExpanded: true,
        items: staffRoleValues
            .map(
              (role) => DropdownMenuItem(
                value: role,
                child: Text(
                  formatStaffRoleLabel(role, fallback: role),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          onChanged(value);
        },
      ),
    );
  }
}

class _TaskStaffCell extends StatelessWidget {
  final List<BusinessStaffProfileSummary> staff;
  final String? selectedStaffId;
  final ValueChanged<String?>? onChanged;

  const _TaskStaffCell({
    required this.staff,
    required this.selectedStaffId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colStaffWidth,
      child: DropdownButtonFormField<String>(
        // WHY: Assignment should remain scoped to the selected role.
        value: selectedStaffId,
        decoration: const InputDecoration(isDense: true),
        isExpanded: true,
        hint: const Text(_selectPlaceholder),
        items: staff
            .map(
              (member) => DropdownMenuItem(
                value: member.id,
                child: Text(
                  member.userName ?? member.userEmail ?? member.id,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _TaskWeightCell extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _TaskWeightCell({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colWeightWidth,
      child: DropdownButtonFormField<int>(
        // WHY: Weight helps prioritize tasks without extra screens.
        value: value,
        decoration: const InputDecoration(isDense: true),
        isExpanded: true,
        items: _weightOptions
            .map(
              (weight) => DropdownMenuItem(
                value: weight,
                child: Text(weight.toString()),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          onChanged(value);
        },
      ),
    );
  }
}

class _TaskStatusCell extends StatelessWidget {
  final ProductionTaskStatus value;
  final ValueChanged<ProductionTaskStatus> onChanged;

  const _TaskStatusCell({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _colStatusWidth,
      child: DropdownButtonFormField<ProductionTaskStatus>(
        // WHY: Status selection combines icon + label for quick scanning.
        value: value,
        decoration: const InputDecoration(isDense: true),
        isExpanded: true,
        items: ProductionTaskStatus.values
            .map(
              (status) => DropdownMenuItem(
                value: status,
                child: Row(
                  children: [
                    Icon(
                      _statusIcon(status),
                      size: _iconSize,
                      color: _statusColor(theme, status),
                    ),
                    const SizedBox(width: _denseFieldSpacing),
                    Expanded(
                      child: Text(
                        _statusLabel(status),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          onChanged(value);
        },
        selectedItemBuilder: (context) {
          return ProductionTaskStatus.values
              .map(
                (status) => Row(
                  children: [
                    Icon(
                      _statusIcon(status),
                      size: _iconSize,
                      color: _statusColor(theme, status),
                    ),
                    const SizedBox(width: _denseFieldSpacing),
                    Expanded(
                      child: Text(
                        _statusLabel(status),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
              .toList();
        },
      ),
    );
  }
}

class _TaskInstructionsCell extends StatelessWidget {
  final ProductionTaskDraft task;
  final ValueChanged<String> onChanged;

  const _TaskInstructionsCell({
    required this.task,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colInstructionsWidth,
      child: TextFormField(
        // WHY: Keep instructions editable without leaving the table.
        initialValue: task.instructions,
        decoration: const InputDecoration(
          isDense: true,
          hintText: _instructionsHint,
        ),
        maxLines: 1,
        onChanged: onChanged,
      ),
    );
  }
}

class _TaskActionsCell extends StatelessWidget {
  final VoidCallback onRemove;

  const _TaskActionsCell({required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colActionsWidth,
      child: IconButton(
        // WHY: Quick remove keeps table cleanup fast.
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline),
        tooltip: _removeTaskTooltip,
      ),
    );
  }
}

class _MobileCompletedChip extends StatelessWidget {
  final DateTime? completedAt;
  final ProductionTaskStatus status;

  const _MobileCompletedChip({
    required this.completedAt,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Compact chip keeps completion info visible on mobile.
    final isDone = status == ProductionTaskStatus.done && completedAt != null;
    final label = isDone ? formatDateLabel(completedAt) : _completedPlaceholder;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _chipPadding,
        vertical: _denseFieldSpacing,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            size: _iconSize,
            color: isDone
                ? _statusColor(theme, ProductionTaskStatus.done)
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: _denseFieldSpacing),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedCell extends StatelessWidget {
  final DateTime? completedAt;
  final ProductionTaskStatus status;

  const _CompletedCell({
    required this.completedAt,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (status != ProductionTaskStatus.done || completedAt == null) {
      return Text(
        _completedPlaceholder,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final label = formatDateLabel(completedAt);
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          size: _iconSize,
          color: _statusColor(theme, ProductionTaskStatus.done),
        ),
        const SizedBox(width: _denseFieldSpacing),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyTableMessage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(_summarySpacing),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        _summaryEmpty,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _TaskSummary {
  final int totalTasks;
  final int doneTasks;
  final int blockedTasks;
  final int unassignedTasks;
  final double completionRatio;

  const _TaskSummary({
    required this.totalTasks,
    required this.doneTasks,
    required this.blockedTasks,
    required this.unassignedTasks,
    required this.completionRatio,
  });

  factory _TaskSummary.fromDraft(ProductionPlanDraftState draft) {
    // WHY: Summaries help users understand workload at a glance.
    final tasks = draft.phases.expand((phase) => phase.tasks).toList();
    final done = tasks
        .where((task) => task.status == ProductionTaskStatus.done)
        .length;
    final blocked = tasks
        .where((task) => task.status == ProductionTaskStatus.blocked)
        .length;
    final unassigned = tasks
        .where((task) => task.assignedStaffId == null)
        .length;
    final ratio = tasks.isEmpty ? 0.0 : done / tasks.length;

    return _TaskSummary(
      totalTasks: tasks.length,
      doneTasks: done,
      blockedTasks: blocked,
      unassignedTasks: unassigned,
      completionRatio: ratio,
    );
  }
}

String _resolveStaffLabel(
  List<BusinessStaffProfileSummary> staff,
  String? staffId,
) {
  // WHY: Keep collapsed meta consistent for assigned/unassigned staff.
  if (staffId == null) return _unassignedLabel;
  final match = staff.where((member) => member.id == staffId).toList();
  if (match.isEmpty) return _unassignedLabel;
  final profile = match.first;
  return profile.userName ?? profile.userEmail ?? _unassignedLabel;
}

class _PhaseSummary {
  final int totalTasks;
  final int doneTasks;
  final AppStatusTone tone;
  final IconData icon;

  const _PhaseSummary({
    required this.totalTasks,
    required this.doneTasks,
    required this.tone,
    required this.icon,
  });

  factory _PhaseSummary.fromPhase(ProductionPhaseDraft phase) {
    // WHY: Phase summary powers the flow row and progress bars.
    final total = phase.tasks.length;
    final done = phase.tasks
        .where((task) => task.status == ProductionTaskStatus.done)
        .length;

    if (total == 0) {
      return const _PhaseSummary(
        totalTasks: 0,
        doneTasks: 0,
        tone: AppStatusTone.neutral,
        icon: Icons.radio_button_unchecked,
      );
    }

    if (done == total) {
      return _PhaseSummary(
        totalTasks: total,
        doneTasks: done,
        tone: AppStatusTone.success,
        icon: Icons.check_circle,
      );
    }

    if (done > 0) {
      return _PhaseSummary(
        totalTasks: total,
        doneTasks: done,
        tone: AppStatusTone.info,
        icon: Icons.autorenew,
      );
    }

    return _PhaseSummary(
      totalTasks: total,
      doneTasks: done,
      tone: AppStatusTone.warning,
      icon: Icons.schedule,
    );
  }

  double get ratio {
    if (totalTasks == 0) return 0;
    return doneTasks / totalTasks;
  }
}

String _statusLabel(ProductionTaskStatus status) {
  // WHY: Keep status labels centralized for consistent UI copy.
  switch (status) {
    case ProductionTaskStatus.notStarted:
      return _statusNotStarted;
    case ProductionTaskStatus.inProgress:
      return _statusInProgress;
    case ProductionTaskStatus.blocked:
      return _statusBlocked;
    case ProductionTaskStatus.done:
      return _statusDone;
  }
}

IconData _statusIcon(ProductionTaskStatus status) {
  // WHY: Icons replace emoji for consistent theme rendering.
  switch (status) {
    case ProductionTaskStatus.notStarted:
      return Icons.radio_button_unchecked;
    case ProductionTaskStatus.inProgress:
      return Icons.autorenew;
    case ProductionTaskStatus.blocked:
      return Icons.block;
    case ProductionTaskStatus.done:
      return Icons.check_circle;
  }
}

AppStatusTone _statusTone(ProductionTaskStatus status) {
  // WHY: Centralizing tone mapping keeps badges consistent across UI.
  return switch (status) {
    ProductionTaskStatus.notStarted => AppStatusTone.neutral,
    ProductionTaskStatus.inProgress => AppStatusTone.info,
    ProductionTaskStatus.blocked => AppStatusTone.danger,
    ProductionTaskStatus.done => AppStatusTone.success,
  };
}

Color _statusColor(ThemeData theme, ProductionTaskStatus status) {
  // WHY: Status colors must remain readable across light/dark themes.
  return AppStatusBadgeColors.fromTheme(
    theme: theme,
    tone: _statusTone(status),
  ).foreground;
}
