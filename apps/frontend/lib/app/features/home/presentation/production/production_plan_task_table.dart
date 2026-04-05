/// lib/app/features/home/presentation/production/production_plan_task_table.dart
/// ----------------------------------------------------------------------------
/// WHAT:
/// - Phase-based editing workspace for production draft tasks.
///
/// WHY:
/// - Long operational drafts need a calmer editing surface than a dense table.
/// - Users must read full task names, understand phase progress, and expand
///   secondary controls only when needed.
///
/// HOW:
/// - Builds a summary strip, phase navigator, and per-phase task editor cards.
/// - Separates primary editing fields from secondary assignment metadata.
/// - Logs key layout and interaction states for diagnostics.
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
const String _stageNavigatorLabel = "Phase navigator";
const String _stageNavigatorHint =
    "Only the selected phase is loaded to keep the editor responsive.";

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
const double _taskCardSpacing = 12;
const double _taskCardPadding = 14;
const double _mobileBreakpoint = 720;
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
const double _chipPadding = 8;
const double _chipSpacing = 8;
const double _progressHeight = 6;
const double _iconSize = 16;
const double _denseFieldSpacing = 6;
const double _rowBorderOpacity = 0.35;

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

class ProductionPlanTaskTable extends ConsumerStatefulWidget {
  final ProductionPlanDraftState draft;
  final List<BusinessStaffProfileSummary> staff;
  final bool calendarOnly;
  final bool listOnly;
  final bool showLayoutToggle;
  final bool showPhaseNavigator;
  final VoidCallback? onOpenListScreen;
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
    this.calendarOnly = false,
    this.listOnly = false,
    this.showLayoutToggle = true,
    this.showPhaseNavigator = false,
    this.onOpenListScreen,
    required this.onAddTask,
    this.onAddTaskAt,
    this.taskScheduleOverrides = const <String, DateTimeRange>{},
    required this.onRemoveTask,
  });

  @override
  ConsumerState<ProductionPlanTaskTable> createState() =>
      _ProductionPlanTaskTableState();
}

class _ProductionPlanTaskTableState
    extends ConsumerState<ProductionPlanTaskTable> {
  int _visiblePhaseIndex = 0;

  @override
  void didUpdateWidget(covariant ProductionPlanTaskTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxIndex = widget.draft.phases.length - 1;
    if (maxIndex < 0) {
      if (_visiblePhaseIndex != 0) {
        setState(() {
          _visiblePhaseIndex = 0;
        });
      }
      return;
    }
    if (_visiblePhaseIndex > maxIndex) {
      setState(() {
        _visiblePhaseIndex = maxIndex;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _logBuild);
    // WHY: Summary keeps the workload and completion visible at a glance.
    final draft = widget.draft;
    final staff = widget.staff;
    final summary = _TaskSummary.fromDraft(draft);
    final storedLayoutMode = ref.watch(_taskLayoutModeProvider);
    final layoutMode = widget.listOnly
        ? _TaskLayoutMode.list
        : widget.calendarOnly
        ? _TaskLayoutMode.calendar
        : storedLayoutMode;
    final isNarrow = MediaQuery.of(context).size.width < _mobileBreakpoint;
    final safeVisiblePhaseIndex = draft.phases.isEmpty
        ? 0
        : _visiblePhaseIndex.clamp(0, draft.phases.length - 1);
    final visiblePhaseEntries =
        widget.showPhaseNavigator && draft.phases.isNotEmpty
        ? <MapEntry<int, ProductionPhaseDraft>>[
            MapEntry(
              safeVisiblePhaseIndex,
              draft.phases[safeVisiblePhaseIndex],
            ),
          ]
        : draft.phases.asMap().entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showLayoutToggle &&
            !widget.listOnly &&
            (!widget.calendarOnly || widget.onOpenListScreen != null)) ...[
          _TaskLayoutToggle(
            mode: widget.calendarOnly ? _TaskLayoutMode.calendar : layoutMode,
            onOpenListScreen: widget.onOpenListScreen,
          ),
          const SizedBox(height: _summarySpacing),
        ],
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
            onAddTask: widget.onAddTask,
            onAddTaskAt: widget.onAddTaskAt,
            taskScheduleOverrides: widget.taskScheduleOverrides,
          ),
        if (layoutMode == _TaskLayoutMode.calendar)
          const SizedBox(height: _sectionSpacing),
        if (layoutMode == _TaskLayoutMode.list) ...[
          if (widget.showPhaseNavigator && draft.phases.isNotEmpty)
            _PhaseStageNavigator(
              phases: draft.phases,
              selectedIndex: safeVisiblePhaseIndex,
              onChanged: (nextIndex) {
                if (nextIndex == _visiblePhaseIndex) {
                  return;
                }
                setState(() {
                  _visiblePhaseIndex = nextIndex;
                });
              },
            )
          else
            _PhaseFlowRow(phases: draft.phases),
          const SizedBox(height: _sectionSpacing),
          if (summary.totalTasks == 0) _EmptyTableMessage(),
          if (summary.totalTasks == 0) const SizedBox(height: _sectionSpacing),
          ...visiblePhaseEntries.map(
            (entry) => _PhaseTableCard(
              phaseIndex: entry.key,
              phase: entry.value,
              staff: staff,
              onAddTask: () => widget.onAddTask(entry.key),
              onRemoveTask: (taskId) => widget.onRemoveTask(entry.key, taskId),
            ),
          ),
        ],
      ],
    );
  }
}

class _TaskLayoutToggle extends ConsumerWidget {
  final _TaskLayoutMode mode;
  final VoidCallback? onOpenListScreen;

  const _TaskLayoutToggle({required this.mode, this.onOpenListScreen});

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
                if (next == _TaskLayoutMode.list && onOpenListScreen != null) {
                  onOpenListScreen!();
                  return;
                }
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

class _PhaseStageNavigator extends StatelessWidget {
  final List<ProductionPhaseDraft> phases;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _PhaseStageNavigator({
    required this.phases,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useDropdown = constraints.maxWidth < 760;
        return Container(
          padding: const EdgeInsets.all(_phaseCardPadding),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_phaseCardRadius),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stageNavigatorLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _mobileHeaderSpacing),
              Text(
                _stageNavigatorHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: _summarySpacing),
              if (useDropdown)
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: _stageNavigatorLabel,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: selectedIndex,
                      isExpanded: true,
                      items: phases.asMap().entries.map((entry) {
                        final phase = entry.value;
                        final summary = _PhaseSummary.fromPhase(phase);
                        return DropdownMenuItem<int>(
                          value: entry.key,
                          child: Text(
                            "${phase.name} (${summary.totalTasks} tasks)",
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          onChanged(value);
                        }
                      },
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: _chipSpacing,
                  runSpacing: _chipSpacing,
                  children: phases.asMap().entries.map((entry) {
                    final phase = entry.value;
                    final summary = _PhaseSummary.fromPhase(phase);
                    final isSelected = entry.key == selectedIndex;
                    return ChoiceChip(
                      selected: isSelected,
                      label: Text("${phase.name} (${summary.totalTasks})"),
                      avatar: Icon(
                        summary.icon,
                        size: _iconSize,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : AppStatusBadgeColors.fromTheme(
                                theme: theme,
                                tone: summary.tone,
                              ).foreground,
                      ),
                      onSelected: (_) => onChanged(entry.key),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
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

class _PhaseTaskList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      children: phase.tasks.asMap().entries.map((entry) {
        final task = entry.value;
        return _TaskEditorCard(
          phaseIndex: phaseIndex,
          taskIndex: entry.key,
          task: task,
          staff: staff,
          compactLayout: true,
          onRemove: () => onRemoveTask(task.id),
        );
      }).toList(),
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
    return Column(
      children: phase.tasks.asMap().entries.map((entry) {
        final task = entry.value;
        return _TaskEditorCard(
          phaseIndex: phaseIndex,
          taskIndex: entry.key,
          task: task,
          staff: staff,
          compactLayout: false,
          onRemove: () => onRemoveTask(task.id),
        );
      }).toList(),
    );
  }
}

class _TaskEditorCard extends ConsumerWidget {
  final int phaseIndex;
  final int taskIndex;
  final ProductionTaskDraft task;
  final List<BusinessStaffProfileSummary> staff;
  final bool compactLayout;
  final VoidCallback onRemove;

  const _TaskEditorCard({
    required this.phaseIndex,
    required this.taskIndex,
    required this.task,
    required this.staff,
    required this.compactLayout,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final theme = Theme.of(context);
    final expandedTasks = ref.watch(_expandedTaskIdsProvider);
    final isExpanded = expandedTasks.contains(task.id);
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
    final roleStaff = staff
        .where((member) => member.staffRole == task.roleRequired)
        .toList();
    final selectedStaffId =
        roleStaff.any((member) => member.id == task.assignedStaffId)
        ? task.assignedStaffId
        : null;
    final assignedCount = task.assignedStaffProfileIds.length;
    final roleLabel = formatStaffRoleLabel(
      task.roleRequired,
      fallback: task.roleRequired,
    );
    final staffLabel = _resolveStaffLabel(roleStaff, selectedStaffId);
    final dayLabel = _extractProjectDayLabel(task);

    return Container(
      margin: const EdgeInsets.only(bottom: _taskCardSpacing),
      padding: const EdgeInsets.all(_taskCardPadding),
      decoration: BoxDecoration(
        color: rowBackground,
        borderRadius: BorderRadius.circular(_phaseCardRadius + 2),
        border: Border.all(color: rowBorder),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: task.status == ProductionTaskStatus.done,
                onChanged: (value) {
                  if (value == true) {
                    AppDebug.log(
                      _logTag,
                      _logDoneToggle,
                      extra: {_extraTaskIdKey: task.id},
                    );
                    controller.markTaskDone(phaseIndex, task.id);
                  } else {
                    AppDebug.log(
                      _logTag,
                      _logClearToggle,
                      extra: {_extraTaskIdKey: task.id},
                    );
                    controller.clearTaskDone(phaseIndex, task.id);
                  }
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: _chipSpacing,
                      runSpacing: _chipSpacing,
                      children: [
                        _MetaChip(
                          label: "Task",
                          value: (taskIndex + 1).toString(),
                          tone: AppStatusTone.neutral,
                        ),
                        _MetaChip(
                          label: _columnStatus,
                          value: _statusLabel(task.status),
                          tone: rowTone,
                        ),
                        if (dayLabel != null)
                          _MetaChip(
                            label: "Day",
                            value: dayLabel,
                            tone: AppStatusTone.info,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      // WHAT: The task title is the primary editing surface.
                      // WHY: Full operational task names must stay readable.
                      // HOW: Use a multi-line input instead of a compressed
                      // table cell so editors can review the whole title.
                      initialValue: task.title,
                      minLines: 1,
                      maxLines: compactLayout ? 2 : 3,
                      decoration: const InputDecoration(
                        labelText: "Task title",
                        hintText: "Describe task",
                      ),
                      onChanged: (value) => controller.updateTaskTitle(
                        phaseIndex,
                        task.id,
                        value,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!isExpanded && task.instructions.trim().isNotEmpty) ...[
                      Text(
                        task.instructions.trim(),
                        maxLines: compactLayout ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _TaskEditorPreviewMeta(
                      roleLabel: roleLabel,
                      staffLabel: staffLabel,
                      assignmentLabel:
                          "$assignedCount/${task.requiredHeadcount}",
                      weight: task.weight,
                      completedAt: task.completedAt,
                      status: task.status,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final nextExpanded = !isExpanded;
                      AppDebug.log(
                        _logTag,
                        _logExpandToggle,
                        extra: {
                          _extraTaskIdKey: task.id,
                          _extraExpandedKey: nextExpanded,
                        },
                      );
                      ref.read(_expandedTaskIdsProvider.notifier).update((
                        state,
                      ) {
                        final next = {...state};
                        if (nextExpanded) {
                          next.add(task.id);
                        } else {
                          next.remove(task.id);
                        }
                        return next;
                      });
                    },
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    tooltip: isExpanded ? _collapseLabel : _expandLabel,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref.read(_expandedTaskIdsProvider.notifier).update((
                        state,
                      ) {
                        if (!state.contains(task.id)) {
                          return state;
                        }
                        final next = {...state};
                        next.remove(task.id);
                        return next;
                      });
                      onRemove();
                    },
                    icon: const Icon(Icons.delete_outline),
                    tooltip: _removeTaskTooltip,
                  ),
                ],
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Text(
              "Execution notes",
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _TaskMobileInstructionsField(
              value: task.instructions,
              onChanged: (value) =>
                  controller.updateTaskInstructions(phaseIndex, task.id, value),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final useSingleColumn =
                    compactLayout || constraints.maxWidth < 760;
                final halfWidth = (constraints.maxWidth - _sectionSpacing) / 2;
                return Wrap(
                  spacing: _sectionSpacing,
                  runSpacing: _mobileFieldSpacing,
                  children: [
                    SizedBox(
                      width: useSingleColumn ? double.infinity : halfWidth,
                      child: _TaskMobileStatusField(
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
                          controller.updateTaskStatus(
                            phaseIndex,
                            task.id,
                            value,
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: useSingleColumn ? double.infinity : halfWidth,
                      child: _TaskMobileRoleField(
                        value: task.roleRequired,
                        onChanged: (value) => controller.updateTaskRole(
                          phaseIndex,
                          task.id,
                          value,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: useSingleColumn ? double.infinity : halfWidth,
                      child: _TaskMobileStaffField(
                        staff: roleStaff,
                        selectedStaffId: selectedStaffId,
                        onChanged: roleStaff.isEmpty
                            ? null
                            : (value) => controller.updateTaskStaff(
                                phaseIndex,
                                task.id,
                                value,
                              ),
                      ),
                    ),
                    SizedBox(
                      width: useSingleColumn ? double.infinity : halfWidth,
                      child: _TaskMobileWeightRow(
                        weight: task.weight,
                        requiredHeadcount: task.requiredHeadcount,
                        assignedCount: assignedCount,
                        completedAt: task.completedAt,
                        status: task.status,
                        onHeadcountChanged: (value) =>
                            controller.updateTaskRequiredHeadcount(
                              phaseIndex,
                              task.id,
                              value,
                            ),
                        onChanged: (value) => controller.updateTaskWeight(
                          phaseIndex,
                          task.id,
                          value,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskEditorPreviewMeta extends StatelessWidget {
  final String roleLabel;
  final String staffLabel;
  final String assignmentLabel;
  final int weight;
  final DateTime? completedAt;
  final ProductionTaskStatus status;

  const _TaskEditorPreviewMeta({
    required this.roleLabel,
    required this.staffLabel,
    required this.assignmentLabel,
    required this.weight,
    required this.completedAt,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _chipSpacing,
      runSpacing: _chipSpacing,
      children: [
        _MetaChip(
          label: _columnRole,
          value: roleLabel,
          tone: AppStatusTone.neutral,
        ),
        _MetaChip(
          label: _columnStaff,
          value: _shortenMetaValue(staffLabel),
          tone: staffLabel == _unassignedLabel
              ? AppStatusTone.warning
              : AppStatusTone.neutral,
        ),
        _MetaChip(
          label: _columnHeadcount,
          value: assignmentLabel,
          tone: AppStatusTone.neutral,
        ),
        _MetaChip(
          label: _columnWeight,
          value: weight.toString(),
          tone: AppStatusTone.neutral,
        ),
        _MetaChip(
          label: _columnCompleted,
          value: completedAt == null
              ? _completedPlaceholder
              : formatDateLabel(completedAt),
          tone: status == ProductionTaskStatus.done
              ? AppStatusTone.success
              : AppStatusTone.neutral,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackFields = constraints.maxWidth < 420;
        final weightField = DropdownButtonFormField<int>(
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
        );
        final headcountField = DropdownButtonFormField<int>(
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
        );
        final completedChip = _MobileCompletedChip(
          completedAt: completedAt,
          status: status,
        );

        if (stackFields) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: weightField),
                  const SizedBox(width: _mobileFieldSpacing),
                  Expanded(child: headcountField),
                ],
              ),
              const SizedBox(height: _mobileFieldSpacing),
              SizedBox(width: double.infinity, child: completedChip),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: weightField),
            const SizedBox(width: _mobileFieldSpacing),
            Expanded(child: headcountField),
            const SizedBox(width: _mobileFieldSpacing),
            Expanded(child: completedChip),
          ],
        );
      },
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

String? _extractProjectDayLabel(ProductionTaskDraft task) {
  final match = RegExp(
    r"Project day\s+(\d+)",
    caseSensitive: false,
  ).firstMatch(task.instructions);
  final dayNumber = match?.group(1)?.trim() ?? "";
  return dayNumber.isEmpty ? null : dayNumber;
}

String _shortenMetaValue(String value, {int maxLength = 28}) {
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return "${trimmed.substring(0, maxLength - 1)}…";
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
