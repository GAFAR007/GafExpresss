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
import 'package:frontend/app/features/home/presentation/production/production_draft_calendar_preview.dart';
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
const String _logLayoutToggle = "layout_toggle";
const String _logCalendarDayAddTask = "calendar_day_add_task";
const String _extraTaskIdKey = "taskId";
const String _extraStatusKey = "status";
const String _extraCompactKey = "compact";
const String _extraExpandedKey = "expanded";
const String _extraLayoutKey = "layout";
const String _extraPhaseIndexKey = "phaseIndex";
const String _extraPhaseNameKey = "phaseName";
const String _extraDayKey = "day";
const String _extraPhaseHintKey = "phaseHint";
const String _extraSuggestedStartKey = "suggestedStart";
const String _extraSuggestedDueKey = "suggestedDue";

const String _summaryTitle = "Task summary";
const String _summaryTotalLabel = "Total tasks";
const String _summaryDoneLabel = "Done";
const String _summaryBlockedLabel = "Blocked";
const String _summaryUnassignedLabel = "Unassigned";
const String _summaryEmpty = "No tasks yet. Add tasks to start planning.";
const String _summaryProgressLabel = "Progress";
const String _compactToggleLabel = "Compact view";
const String _compactToggleHint = "Reduce scrolling on mobile.";
const String _layoutCalendarLabel = "Calendar";
const String _layoutListLabel = "List";
const String _calendarViewTitle = "Production calendar";
const String _calendarViewHint =
    "Tap any date to view scheduled tasks for that day.";
const String _calendarViewRangeMissing =
    "Select start and end dates to render the calendar schedule.";
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
const String _columnHeadcount = "Headcount";
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
final _expandedTaskIdsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);
// WHY: Default to calendar view so plan drafting is date-first.
final _taskLayoutModeProvider = StateProvider<_TaskLayoutMode>(
  (ref) => _TaskLayoutMode.calendar,
);
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
const double _colHeadcountWidth = 120;
const double _colStaffWidth = 180;
const double _colWeightWidth = 90;
const double _colStatusWidth = 160;
const double _colInstructionsWidth = 220;
const double _colCompletedWidth = 140;
const double _colActionsWidth = 60;

const List<int> _weightOptions = [1, 2, 3, 4, 5];
const List<int> _headcountOptions = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const List<_CalendarDefaultSlot> _calendarDefaultSlots = [
  _CalendarDefaultSlot(startHour: 9, startMinute: 0, endHour: 11, endMinute: 0),
  _CalendarDefaultSlot(
    startHour: 11,
    startMinute: 0,
    endHour: 13,
    endMinute: 0,
  ),
  _CalendarDefaultSlot(
    startHour: 14,
    startMinute: 0,
    endHour: 16,
    endMinute: 0,
  ),
  _CalendarDefaultSlot(
    startHour: 16,
    startMinute: 0,
    endHour: 17,
    endMinute: 0,
  ),
];

enum _TaskLayoutMode { calendar, list }

class ProductionPlanTaskTable extends ConsumerWidget {
  final ProductionPlanDraftState draft;
  final List<BusinessStaffProfileSummary> staff;
  final void Function(int phaseIndex) onAddTask;
  final Future<void> Function(
    int phaseIndex,
    int taskIndex,
    DateTime day,
    DateTime suggestedStart,
    DateTime suggestedDue,
  )?
  onAddTaskAt;
  final Map<String, DateTimeRange> taskScheduleOverrides;
  final void Function(int phaseIndex, String taskId) onRemoveTask;

  const ProductionPlanTaskTable({
    super.key,
    required this.draft,
    required this.staff,
    required this.onAddTask,
    this.onAddTaskAt,
    this.taskScheduleOverrides = const <String, DateTimeRange>{},
    required this.onRemoveTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _logBuild);
    // WHY: Summary keeps the workload and completion visible at a glance.
    final summary = _TaskSummary.fromDraft(draft);
    final layoutMode = ref.watch(_taskLayoutModeProvider);
    final isNarrow = MediaQuery.of(context).size.width < _mobileBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TaskLayoutToggle(mode: layoutMode),
        const SizedBox(height: _summarySpacing),
        _TaskSummaryBar(summary: summary),
        const SizedBox(height: _summarySpacing),
        if (isNarrow && layoutMode == _TaskLayoutMode.list) ...[
          _MobileViewToggle(),
          const SizedBox(height: _summarySpacing),
        ],
        if (layoutMode == _TaskLayoutMode.calendar)
          _TaskCalendarPreviewPanel(
            draft: draft,
            staff: staff,
            onAddTask: onAddTask,
            onAddTaskAt: onAddTaskAt,
            taskScheduleOverrides: taskScheduleOverrides,
          ),
        if (layoutMode == _TaskLayoutMode.calendar)
          const SizedBox(height: _sectionSpacing),
        if (layoutMode == _TaskLayoutMode.list) ...[
          // WHY: Phase flow row provides a quick visual of plan progression.
          _PhaseFlowRow(phases: draft.phases),
          const SizedBox(height: _sectionSpacing),
          if (summary.totalTasks == 0) _EmptyTableMessage(),
          if (summary.totalTasks == 0) const SizedBox(height: _sectionSpacing),
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
      ],
    );
  }
}

class _TaskLayoutToggle extends ConsumerWidget {
  final _TaskLayoutMode mode;

  const _TaskLayoutToggle({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(_chipPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_TaskLayoutMode>(
              segments: const [
                ButtonSegment<_TaskLayoutMode>(
                  value: _TaskLayoutMode.calendar,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text(_layoutCalendarLabel),
                ),
                ButtonSegment<_TaskLayoutMode>(
                  value: _TaskLayoutMode.list,
                  icon: Icon(Icons.view_list_outlined),
                  label: Text(_layoutListLabel),
                ),
              ],
              selected: <_TaskLayoutMode>{mode},
              onSelectionChanged: (nextSet) {
                final next = nextSet.first;
                AppDebug.log(
                  _logTag,
                  _logLayoutToggle,
                  extra: {_extraLayoutKey: next.name},
                );
                ref.read(_taskLayoutModeProvider.notifier).state = next;
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCalendarPreviewPanel extends StatelessWidget {
  final ProductionPlanDraftState draft;
  final List<BusinessStaffProfileSummary> staff;
  final void Function(int phaseIndex) onAddTask;
  final Future<void> Function(
    int phaseIndex,
    int taskIndex,
    DateTime day,
    DateTime suggestedStart,
    DateTime suggestedDue,
  )?
  onAddTaskAt;
  final Map<String, DateTimeRange> taskScheduleOverrides;

  const _TaskCalendarPreviewPanel({
    required this.draft,
    required this.staff,
    required this.onAddTask,
    this.onAddTaskAt,
    required this.taskScheduleOverrides,
  });

  @override
  Widget build(BuildContext context) {
    final projected = _TaskCalendarProjection.build(
      draft: draft,
      taskScheduleOverrides: taskScheduleOverrides,
    );
    final tasks = projected.tasks;
    Future<void> addTaskForDay(DateTime day, String phaseNameHint) async {
      if (draft.phases.isEmpty) {
        return;
      }
      final phaseIndex = _resolvePhaseIndexForCalendarDayAdd(
        draft: draft,
        projectedTasks: tasks,
        day: day,
        phaseNameHint: phaseNameHint,
      );
      final safeIndex = phaseIndex.clamp(0, draft.phases.length - 1);
      final insertIndex = _resolvePhaseTaskInsertIndexForCalendarDayAdd(
        phase: draft.phases[safeIndex],
        projectedTasks: tasks,
        day: day,
      );
      final suggestedSchedule = _resolveCalendarDayAddSuggestedSchedule(
        day: day,
        projectedTasks: tasks,
        schedulePolicy: projected.schedulePolicy,
      );
      final phaseName = draft.phases[safeIndex].name;
      AppDebug.log(
        _logTag,
        _logCalendarDayAddTask,
        extra: {
          _extraDayKey: formatDateInput(day),
          _extraPhaseIndexKey: safeIndex,
          _extraPhaseNameKey: phaseName,
          _extraPhaseHintKey: phaseNameHint,
          "insertIndex": insertIndex,
          _extraSuggestedStartKey: suggestedSchedule.startLocal
              .toIso8601String(),
          _extraSuggestedDueKey: suggestedSchedule.dueLocal.toIso8601String(),
        },
      );
      if (onAddTaskAt != null) {
        await onAddTaskAt!(
          safeIndex,
          insertIndex,
          day,
          suggestedSchedule.startLocal,
          suggestedSchedule.dueLocal,
        );
        return;
      }
      onAddTask(safeIndex);
    }

    final theme = Theme.of(context);
    if (tasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(_phaseCardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_phaseCardRadius),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _calendarViewTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _chipSpacing),
            Text(projected.message, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_phaseCardPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_phaseCardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _calendarViewTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: _chipSpacing),
          Text(
            _calendarViewHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _phaseHeaderSpacing),
          ProductionDraftCalendarPreview(
            tasks: tasks,
            schedulePolicy: projected.schedulePolicy,
            staffProfiles: staff,
            onAddTaskForDay: addTaskForDay,
          ),
        ],
      ),
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
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: _summarySpacing),
          Wrap(
            spacing: _chipSpacing,
            runSpacing: _chipSpacing,
            children: [
              _SummaryChip(
                label: _summaryTotalLabel,
                value: summary.totalTasks,
              ),
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
  bool _initScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // WHY: Riverpod disallows provider mutations during build/dependency
    // resolution. Defer one-time compact-mode initialization to post-frame.
    final hasInit = ref.read(_compactModeInitializedProvider);
    if (hasInit || _initScheduled) {
      return;
    }
    _initScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _initScheduled = false;
        return;
      }
      final alreadyInitialized = ref.read(_compactModeInitializedProvider);
      if (alreadyInitialized) {
        _initScheduled = false;
        return;
      }
      final isNarrow = MediaQuery.of(context).size.width < _mobileBreakpoint;
      ref.read(_compactModeProvider.notifier).state = isNarrow;
      ref.read(_compactModeInitializedProvider.notifier).state = true;
      AppDebug.log(
        _logTag,
        _logCompactInit,
        extra: {_extraCompactKey: isNarrow},
      );
      _initScheduled = false;
    });
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

  const _SummaryChip({required this.label, required this.value});

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
            .map(
              (chip) => Padding(
                padding: const EdgeInsets.only(right: _chipSpacing),
                child: chip,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PhaseFlowChip extends StatelessWidget {
  final ProductionPhaseDraft phase;
  final _PhaseSummary summary;

  const _PhaseFlowChip({required this.phase, required this.summary});

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
        border: Border.all(color: colors.foreground.withValues(alpha: 0.3)),
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
          _HeaderCell(
            width: _colDoneWidth,
            label: _columnDone,
            style: textTheme,
          ),
          _HeaderCell(
            width: _colTaskWidth,
            label: _columnTask,
            style: textTheme,
          ),
          _HeaderCell(
            width: _colRoleWidth,
            label: _columnRole,
            style: textTheme,
          ),
          _HeaderCell(
            width: _colHeadcountWidth,
            label: _columnHeadcount,
            style: textTheme,
          ),
          _HeaderCell(
            width: _colStaffWidth,
            label: _columnStaff,
            style: textTheme,
          ),
          _HeaderCell(
            width: _colWeightWidth,
            label: _columnWeight,
            style: textTheme,
          ),
          _HeaderCell(
            width: _colStatusWidth,
            label: _columnStatus,
            style: textTheme,
          ),
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
        : rowColors.foreground.withValues(alpha: _rowBorderOpacity);
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
          _TaskHeadcountCell(
            requiredHeadcount: task.requiredHeadcount,
            assignedCount: task.assignedStaffProfileIds.length,
            onChanged: (value) => controller.updateTaskRequiredHeadcount(
              phaseIndex,
              task.id,
              value,
            ),
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
                extra: {_extraTaskIdKey: task.id, _extraStatusKey: value.name},
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
        : rowColors.foreground.withValues(alpha: _rowBorderOpacity);
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
              roleLabel:
                  "${formatStaffRoleLabel(task.roleRequired, fallback: task.roleRequired)} x${task.assignedStaffProfileIds.isNotEmpty ? task.assignedStaffProfileIds.length : task.requiredHeadcount}",
              assignmentLabel:
                  "${task.assignedStaffProfileIds.length}/${task.requiredHeadcount}",
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
              requiredHeadcount: task.requiredHeadcount,
              assignedCount: task.assignedStaffProfileIds.length,
              completedAt: task.completedAt,
              status: task.status,
              onHeadcountChanged: (value) => controller
                  .updateTaskRequiredHeadcount(phaseIndex, task.id, value),
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

  const _TaskMobileStatusField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<ProductionTaskStatus>(
      // WHY: Status drives planning flow; keep visible on mobile.
      initialValue: value,
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

  const _TaskMobileRoleField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // WHY: Role is required to filter staff options.
      initialValue: value,
      decoration: const InputDecoration(isDense: true, labelText: _columnRole),
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
      initialValue: selectedStaffId,
      decoration: const InputDecoration(isDense: true, labelText: _columnStaff),
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
  final int requiredHeadcount;
  final int assignedCount;
  final DateTime? completedAt;
  final ProductionTaskStatus status;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onHeadcountChanged;

  const _TaskMobileWeightRow({
    required this.weight,
    required this.requiredHeadcount,
    required this.assignedCount,
    required this.completedAt,
    required this.status,
    required this.onChanged,
    required this.onHeadcountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            // WHY: Weight helps prioritize tasks on the go.
            initialValue: weight,
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
          child: DropdownButtonFormField<int>(
            initialValue: requiredHeadcount < 1 ? 1 : requiredHeadcount,
            decoration: InputDecoration(
              isDense: true,
              labelText: _columnHeadcount,
              helperText: "$assignedCount/$requiredHeadcount",
            ),
            isExpanded: true,
            items: _headcountOptions
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value.toString()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              onHeadcountChanged(value);
            },
          ),
        ),
        const SizedBox(width: _mobileFieldSpacing),
        Expanded(
          child: _MobileCompletedChip(completedAt: completedAt, status: status),
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
  final String assignmentLabel;
  final String staffLabel;
  final int weight;

  const _TaskMobileCollapsedMeta({
    required this.status,
    required this.roleLabel,
    required this.assignmentLabel,
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
          label: _columnHeadcount,
          value: assignmentLabel,
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
        border: Border.all(color: colors.foreground.withValues(alpha: 0.3)),
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

  const _TaskTitleCell({required this.task, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colTaskWidth,
      child: TextFormField(
        // WHY: Inline title editing keeps the table fast to scan and edit.
        initialValue: task.title,
        decoration: const InputDecoration(isDense: true, hintText: _columnTask),
        onChanged: onChanged,
      ),
    );
  }
}

class _TaskRoleCell extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TaskRoleCell({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colRoleWidth,
      child: DropdownButtonFormField<String>(
        // WHY: Role drives which staff can be assigned to the task.
        initialValue: value,
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

class _TaskHeadcountCell extends StatelessWidget {
  final int requiredHeadcount;
  final int assignedCount;
  final ValueChanged<int> onChanged;

  const _TaskHeadcountCell({
    required this.requiredHeadcount,
    required this.assignedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final shortage = assignedCount < requiredHeadcount;
    final warningColors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: shortage ? AppStatusTone.warning : AppStatusTone.neutral,
    );
    return SizedBox(
      width: _colHeadcountWidth,
      child: DropdownButtonFormField<int>(
        initialValue: requiredHeadcount < 1 ? 1 : requiredHeadcount,
        decoration: InputDecoration(
          isDense: true,
          helperText: "$assignedCount/$requiredHeadcount",
          helperStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: shortage
                ? warningColors.foreground
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        items: _headcountOptions
            .map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text(value.toString())),
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
        initialValue: selectedStaffId,
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

  const _TaskWeightCell({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colWeightWidth,
      child: DropdownButtonFormField<int>(
        // WHY: Weight helps prioritize tasks without extra screens.
        initialValue: value,
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

  const _TaskStatusCell({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _colStatusWidth,
      child: DropdownButtonFormField<ProductionTaskStatus>(
        // WHY: Status selection combines icon + label for quick scanning.
        initialValue: value,
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

  const _TaskInstructionsCell({required this.task, required this.onChanged});

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

  const _MobileCompletedChip({required this.completedAt, required this.status});

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

  const _CompletedCell({required this.completedAt, required this.status});

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
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// WHY: Calendar day add action should map to a sensible phase without extra prompts.
int _resolvePhaseIndexForCalendarDayAdd({
  required ProductionPlanDraftState draft,
  required List<ProductionAiDraftTaskPreview> projectedTasks,
  required DateTime day,
  required String phaseNameHint,
}) {
  final phaseIndexFromHint = _phaseIndexByName(
    phases: draft.phases,
    phaseName: phaseNameHint,
  );
  if (phaseIndexFromHint >= 0) {
    return phaseIndexFromHint;
  }

  for (final task in projectedTasks) {
    final taskStart = task.startDate;
    if (taskStart == null) {
      continue;
    }
    if (_isSameCalendarDay(taskStart, day)) {
      final index = _phaseIndexByName(
        phases: draft.phases,
        phaseName: task.phaseName,
      );
      if (index >= 0) {
        return index;
      }
    }
  }

  if (draft.startDate != null &&
      draft.endDate != null &&
      draft.phases.length > 1) {
    final planStart = DateTime(
      draft.startDate!.year,
      draft.startDate!.month,
      draft.startDate!.day,
    );
    final rawPlanEnd = DateTime(
      draft.endDate!.year,
      draft.endDate!.month,
      draft.endDate!.day,
    );
    final planEnd = rawPlanEnd.isBefore(planStart) ? planStart : rawPlanEnd;
    final totalDays = planEnd.difference(planStart).inDays + 1;
    final dayOffset = day.difference(planStart).inDays.clamp(0, totalDays - 1);
    final ratio = totalDays <= 1 ? 0.0 : dayOffset / (totalDays - 1);
    final index = (ratio * draft.phases.length).floor().clamp(
      0,
      draft.phases.length - 1,
    );
    return index;
  }

  return 0;
}

// WHY: Day-sheet add action should insert near the tapped day, not always at phase end.
int _resolvePhaseTaskInsertIndexForCalendarDayAdd({
  required ProductionPhaseDraft phase,
  required List<ProductionAiDraftTaskPreview> projectedTasks,
  required DateTime day,
}) {
  if (phase.tasks.isEmpty) {
    return 0;
  }

  final targetDay = DateTime(day.year, day.month, day.day);
  final startByTaskId = <String, DateTime>{};
  for (final projected in projectedTasks) {
    final start = projected.startDate;
    if (start == null) {
      continue;
    }
    startByTaskId[projected.id] = DateTime(start.year, start.month, start.day);
  }

  var insertIndex = phase.tasks.length;
  for (var index = 0; index < phase.tasks.length; index += 1) {
    final task = phase.tasks[index];
    final scheduledDay = startByTaskId[task.id];
    if (scheduledDay == null) {
      continue;
    }
    if (scheduledDay.isAfter(targetDay)) {
      insertIndex = index;
      break;
    }
    insertIndex = index + 1;
  }

  return insertIndex.clamp(0, phase.tasks.length);
}

int _phaseIndexByName({
  required List<ProductionPhaseDraft> phases,
  required String phaseName,
}) {
  final normalized = phaseName.trim().toLowerCase();
  if (normalized.isEmpty) {
    return -1;
  }
  for (var i = 0; i < phases.length; i += 1) {
    if (phases[i].name.trim().toLowerCase() == normalized) {
      return i;
    }
  }
  return -1;
}

bool _isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _TaskCalendarProjection {
  final List<ProductionAiDraftTaskPreview> tasks;
  final ProductionAiDraftSchedulePolicy schedulePolicy;
  final String message;

  const _TaskCalendarProjection({
    required this.tasks,
    required this.schedulePolicy,
    required this.message,
  });

  static _TaskCalendarProjection build({
    required ProductionPlanDraftState draft,
    Map<String, DateTimeRange> taskScheduleOverrides =
        const <String, DateTimeRange>{},
  }) {
    final defaultPolicy = ProductionAiDraftSchedulePolicy(
      workWeekDays: const [1, 2, 3, 4, 5, 6, 7],
      blocks: const [
        ProductionAiDraftScheduleBlock(start: "09:00", end: "13:00"),
        ProductionAiDraftScheduleBlock(start: "14:00", end: "17:00"),
      ],
      minSlotMinutes: 30,
      timezone: "",
    );

    final flattened = <_FlattenedPhaseTask>[];
    for (final phase in draft.phases) {
      for (final task in phase.tasks) {
        flattened.add(_FlattenedPhaseTask(phaseName: phase.name, task: task));
      }
    }

    if (flattened.isEmpty) {
      return _TaskCalendarProjection(
        tasks: const <ProductionAiDraftTaskPreview>[],
        schedulePolicy: defaultPolicy,
        message: _summaryEmpty,
      );
    }

    final startDate = draft.startDate == null
        ? null
        : DateTime(
            draft.startDate!.year,
            draft.startDate!.month,
            draft.startDate!.day,
          );
    final endDate = draft.endDate == null
        ? null
        : DateTime(
            draft.endDate!.year,
            draft.endDate!.month,
            draft.endDate!.day,
          );

    if (startDate == null || endDate == null) {
      return _TaskCalendarProjection(
        tasks: const <ProductionAiDraftTaskPreview>[],
        schedulePolicy: defaultPolicy,
        message: _calendarViewRangeMissing,
      );
    }

    final normalizedEndDate = endDate.isBefore(startDate) ? startDate : endDate;
    final totalDays = normalizedEndDate.difference(startDate).inDays + 1;

    final mapped = flattened.asMap().entries.map((entry) {
      final index = entry.key;
      final flatTask = entry.value;
      final scheduleOverride = taskScheduleOverrides[flatTask.task.id];
      late final DateTime taskStart;
      late final DateTime taskDue;
      if (scheduleOverride != null) {
        taskStart = scheduleOverride.start;
        taskDue = scheduleOverride.end.isAfter(scheduleOverride.start)
            ? scheduleOverride.end
            : scheduleOverride.start.add(const Duration(minutes: 30));
      } else {
        final ratio = flattened.length <= 1
            ? 0.0
            : index / (flattened.length - 1);
        final dayOffset = (ratio * (totalDays - 1)).round();
        final day = startDate.add(Duration(days: dayOffset));

        final slot =
            _calendarDefaultSlots[index % _calendarDefaultSlots.length];
        taskStart = DateTime(
          day.year,
          day.month,
          day.day,
          slot.startHour,
          slot.startMinute,
        );
        taskDue = DateTime(
          day.year,
          day.month,
          day.day,
          slot.endHour,
          slot.endMinute,
        );
      }

      final assignedIds = flatTask.task.assignedStaffProfileIds;
      final requiredHeadcount = flatTask.task.requiredHeadcount < 1
          ? 1
          : flatTask.task.requiredHeadcount;
      final assignedCount = assignedIds.length;

      return ProductionAiDraftTaskPreview(
        id: flatTask.task.id,
        title: flatTask.task.title.trim().isEmpty
            ? _columnTask
            : flatTask.task.title.trim(),
        phaseName: flatTask.phaseName,
        roleRequired: flatTask.task.roleRequired,
        requiredHeadcount: requiredHeadcount,
        assignedCount: assignedCount,
        assignedStaffProfileIds: assignedIds,
        status: _statusLabel(flatTask.task.status),
        startDate: taskStart,
        dueDate: taskDue,
        instructions: flatTask.task.instructions,
        hasShortage: assignedCount < requiredHeadcount,
      );
    }).toList();

    return _TaskCalendarProjection(
      tasks: mapped,
      schedulePolicy: defaultPolicy,
      message: "",
    );
  }
}

class _FlattenedPhaseTask {
  final String phaseName;
  final ProductionTaskDraft task;

  const _FlattenedPhaseTask({required this.phaseName, required this.task});
}

class _CalendarDaySuggestedSchedule {
  final DateTime startLocal;
  final DateTime dueLocal;

  const _CalendarDaySuggestedSchedule({
    required this.startLocal,
    required this.dueLocal,
  });
}

// WHY: Calendar day-add should pin the new task to that day instead of relying on index projection.
_CalendarDaySuggestedSchedule _resolveCalendarDayAddSuggestedSchedule({
  required DateTime day,
  required List<ProductionAiDraftTaskPreview> projectedTasks,
  required ProductionAiDraftSchedulePolicy schedulePolicy,
}) {
  final normalizedDay = DateTime(day.year, day.month, day.day);
  final minSlotMinutes = schedulePolicy.minSlotMinutes.clamp(15, 240);
  final normalizedBlocks = schedulePolicy.blocks.isNotEmpty
      ? schedulePolicy.blocks
      : const <ProductionAiDraftScheduleBlock>[
          ProductionAiDraftScheduleBlock(start: "09:00", end: "13:00"),
          ProductionAiDraftScheduleBlock(start: "14:00", end: "17:00"),
        ];

  final dayTasks =
      projectedTasks.where((task) {
        final start = task.startDate?.toLocal();
        return start != null && _isSameCalendarDay(start, normalizedDay);
      }).toList()..sort((left, right) {
        final leftStart = left.startDate?.toLocal() ?? normalizedDay;
        final rightStart = right.startDate?.toLocal() ?? normalizedDay;
        return leftStart.compareTo(rightStart);
      });

  DateTime? dayCursor;
  for (final task in dayTasks) {
    final due = task.dueDate?.toLocal();
    if (due == null) {
      continue;
    }
    if (dayCursor == null || due.isAfter(dayCursor)) {
      dayCursor = due;
    }
  }

  for (final block in normalizedBlocks) {
    final parsedStart = _parseClockToHourMinute(block.start);
    final parsedEnd = _parseClockToHourMinute(block.end);
    if (parsedStart == null || parsedEnd == null) {
      continue;
    }

    final blockStart = DateTime(
      normalizedDay.year,
      normalizedDay.month,
      normalizedDay.day,
      parsedStart.$1,
      parsedStart.$2,
    );
    final blockEnd = DateTime(
      normalizedDay.year,
      normalizedDay.month,
      normalizedDay.day,
      parsedEnd.$1,
      parsedEnd.$2,
    );
    if (!blockEnd.isAfter(blockStart)) {
      continue;
    }

    var candidateStart = blockStart;
    if (dayCursor != null && dayCursor.isAfter(candidateStart)) {
      candidateStart = dayCursor;
    }
    if (!candidateStart.isBefore(blockEnd)) {
      continue;
    }

    var candidateDue = candidateStart.add(Duration(minutes: minSlotMinutes));
    if (candidateDue.isAfter(blockEnd)) {
      final remainingMinutes = blockEnd.difference(candidateStart).inMinutes;
      if (remainingMinutes < 15) {
        continue;
      }
      candidateDue = blockEnd;
    }

    return _CalendarDaySuggestedSchedule(
      startLocal: candidateStart,
      dueLocal: candidateDue,
    );
  }

  // WHY: Hard fallback keeps UX deterministic when policy blocks are malformed.
  final fallbackStart = DateTime(
    normalizedDay.year,
    normalizedDay.month,
    normalizedDay.day,
    9,
    0,
  );
  return _CalendarDaySuggestedSchedule(
    startLocal: fallbackStart,
    dueLocal: fallbackStart.add(Duration(minutes: minSlotMinutes)),
  );
}

(int, int)? _parseClockToHourMinute(String? value) {
  final raw = (value ?? "").trim();
  if (raw.isEmpty) {
    return null;
  }
  final parts = raw.split(":");
  if (parts.length < 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]) ?? -1;
  final minute = int.tryParse(parts[1]) ?? -1;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return (hour, minute);
}

class _CalendarDefaultSlot {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const _CalendarDefaultSlot({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });
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
        .where((task) => task.assignedStaffProfileIds.isEmpty)
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
