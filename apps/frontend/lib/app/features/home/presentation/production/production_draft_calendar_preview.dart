/// lib/app/features/home/presentation/production/production_draft_calendar_preview.dart
/// -------------------------------------------------------------------------------
/// WHAT:
/// - Calendar-first draft preview for AI-generated production timelines.
/// - Includes a compact planning assistant popup for staffing recommendations.
///
/// HOW:
/// - Supports Day / Week / Month / Year modes using a shared resolved-task model.
/// - Keeps in-memory task overrides (required headcount + assigned staff profile ids).
/// - Emits overrides to parent screen so "Apply draft" can persist improvements.
///
/// WHY:
/// - Makes draft review feel operational instead of table-only.
/// - Helps managers improve staffing before saving plans.
/// - Keeps interactions safe when AI output is partial or missing some dates.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _logTag = "PRODUCTION_DRAFT_CALENDAR_PREVIEW";
const String _logBuild = "build()";
const String _logModeChanged = "mode_changed";
const String _logNavigate = "navigate";
const String _logDayTap = "day_tap";
const String _logAssistantOpen = "assistant_popup_open";
const String _logAssistantAutoAssign = "assistant_auto_assign";
const String _logAssistantHeadcount = "assistant_headcount_recommendation";
const String _logOverrideUpdated = "override_updated";
const String _logDayAddTask = "day_add_task";
const String _logDayAddTaskResult = "day_add_task_result";

const String _title = "Draft production calendar";
const String _emptyCopy = "No draft tasks scheduled for this period";
const String _excludedCopy =
    "Some tasks were excluded from the calendar because their dates were missing.";
const String _timezoneLabelPrefix = "Times shown in:";
const String _blocksLabelPrefix = "Work blocks:";
const String _assistantTooltip = "Open draft assistant";
const String _assistantTitle = "Draft assistant";
const String _assistantSubtitle =
    "Review role capacity, pick staff, and improve this draft before saving.";
const String _assistantNoStaff =
    "No staff profiles loaded. You can still review timeline quality and roles.";
const String _assistantAutoAssignLabel = "Auto-assign by role";
const String _assistantHeadcountLabel = "Apply headcount recommendation";
const String _assistantCloseLabel = "Close";
const String _statusFallback = "pending";
const String _daySheetEmptyCopy = "No tasks scheduled for this day";
const String _daySheetAssignButton = "Select staff";
const String _daySheetAddTaskButton = "Add task";

const double _calendarSurfaceRadius = 12;
const double _calendarToolbarControlRadius = 999;
const double _calendarDayCellRadius = 12;
const double _monthCellHeaderIndicatorIconSize = 10;
const double _monthCellHeaderHeight = 18;
const double _monthCellIndicatorBaseSize = 12;
const List<String> _weekdays = [
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
  "Sun",
];

enum _DraftCalendarMode { day, week, month, year }

/// WHY: Parent apply action needs concrete override values from preview edits.
class ProductionDraftTaskOverride {
  final int? requiredHeadcount;
  final List<String>? assignedStaffProfileIds;

  const ProductionDraftTaskOverride({
    this.requiredHeadcount,
    this.assignedStaffProfileIds,
  });

  bool get isEmpty =>
      requiredHeadcount == null && assignedStaffProfileIds == null;
}

class ProductionDraftCalendarPreview extends StatefulWidget {
  final List<ProductionAiDraftTaskPreview> tasks;
  final ProductionAiDraftSchedulePolicy? schedulePolicy;
  final List<BusinessStaffProfileSummary> staffProfiles;
  final ValueChanged<Map<int, ProductionDraftTaskOverride>>? onOverridesChanged;
  final Future<void> Function(DateTime day, String phaseNameHint)?
  onAddTaskForDay;

  const ProductionDraftCalendarPreview({
    super.key,
    required this.tasks,
    required this.schedulePolicy,
    this.staffProfiles = const <BusinessStaffProfileSummary>[],
    this.onOverridesChanged,
    this.onAddTaskForDay,
  });

  @override
  State<ProductionDraftCalendarPreview> createState() =>
      _ProductionDraftCalendarPreviewState();
}

class _ProductionDraftCalendarPreviewState
    extends State<ProductionDraftCalendarPreview> {
  _DraftCalendarMode _mode = _DraftCalendarMode.month;
  DateTime _anchorDate = _firstDayOfMonth(DateTime.now());
  DateTime _selectedDay = DateTime.now();
  final Map<int, ProductionDraftTaskOverride> _taskOverrides =
      <int, ProductionDraftTaskOverride>{};

  @override
  void initState() {
    super.initState();
    final firstTaskDay = widget.tasks
        .map((task) => task.startDate?.toLocal())
        .whereType<DateTime>()
        .cast<DateTime?>()
        .firstWhere((value) => value != null, orElse: () => null);
    final initialDay = firstTaskDay ?? DateTime.now();
    _selectedDay = DateTime(initialDay.year, initialDay.month, initialDay.day);
    _anchorDate = _firstDayOfMonth(_selectedDay);
  }

  @override
  void didUpdateWidget(covariant ProductionDraftCalendarPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tasks, widget.tasks) && widget.tasks.isNotEmpty) {
      // WHY: Fresh AI draft should reset stale overrides from previous draft payload.
      _taskOverrides.clear();
      final firstTaskDay = widget.tasks
          .map((task) => task.startDate?.toLocal())
          .whereType<DateTime>()
          .cast<DateTime?>()
          .firstWhere((value) => value != null, orElse: () => null);
      if (firstTaskDay != null) {
        _selectedDay = DateTime(
          firstTaskDay.year,
          firstTaskDay.month,
          firstTaskDay.day,
        );
        _anchorDate = _firstDayOfMonth(_selectedDay);
      }
      _emitOverridesChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedTasks = _buildResolvedTasks();
    final excludedCount = widget.tasks.length - resolvedTasks.length;
    final monthStart = _firstDayOfMonth(_anchorDate);
    final monthEnd = DateTime(_anchorDate.year, _anchorDate.month + 1, 1);
    final monthTasks = _tasksForRange(
      tasks: resolvedTasks,
      startInclusive: monthStart,
      endExclusive: monthEnd,
    );

    AppDebug.log(
      _logTag,
      _logBuild,
      extra: {
        "mode": _mode.name,
        "anchorMonth": _monthLabel(_anchorDate),
        "selectedDay": formatDateInput(_selectedDay),
        "taskCount": widget.tasks.length,
        "resolvedTaskCount": resolvedTasks.length,
        "overrideCount": _taskOverrides.length,
      },
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _TopCommandBar(
            mode: _mode,
            onModeChanged: _onModeChanged,
            onAssistantTap: () => _openAssistantPopup(resolvedTasks),
          ),
          const SizedBox(height: 8),
          _InfoLabels(schedulePolicy: widget.schedulePolicy),
          if (excludedCount > 0) ...[
            const SizedBox(height: 8),
            _WarningBanner(message: _excludedCopy),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 540,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: switch (_mode) {
                _DraftCalendarMode.day => _DayModePanel(
                  key: const ValueKey("day"),
                  day: _selectedDay,
                  tasks: _tasksForDay(day: _selectedDay, tasks: resolvedTasks),
                  staffProfiles: widget.staffProfiles,
                  onPrev: () => _shiftSelectedDay(-1),
                  onNext: () => _shiftSelectedDay(1),
                  onToday: _jumpToToday,
                  onTaskTap: (task) => _openTaskStaffPicker(task),
                  onHeadcountChange: (task, delta) =>
                      _adjustTaskHeadcount(task: task, delta: delta),
                  onAddTask: widget.onAddTaskForDay == null
                      ? null
                      : () async {
                          final dayTasks = _tasksForDay(
                            day: _selectedDay,
                            tasks: resolvedTasks,
                          );
                          final phaseNameHint = dayTasks.isNotEmpty
                              ? dayTasks.first.phaseName
                              : "";
                          AppDebug.log(
                            _logTag,
                            _logDayAddTask,
                            extra: {
                              "day": formatDateInput(_selectedDay),
                              "phaseNameHint": phaseNameHint,
                              "source": "day_mode_panel",
                            },
                          );
                          await widget.onAddTaskForDay?.call(
                            _selectedDay,
                            phaseNameHint,
                          );
                        },
                ),
                _DraftCalendarMode.week => _WeekModePanel(
                  key: const ValueKey("week"),
                  selectedDay: _selectedDay,
                  tasks: resolvedTasks,
                  onPrevWeek: () => _shiftSelectedDay(-7),
                  onNextWeek: () => _shiftSelectedDay(7),
                  onToday: _jumpToToday,
                  onDayTap: (day) {
                    _openDaySheet(day);
                  },
                ),
                _DraftCalendarMode.month => _MonthModePanel(
                  key: const ValueKey("month"),
                  monthAnchor: _anchorDate,
                  selectedDay: _selectedDay,
                  tasks: resolvedTasks,
                  onPrevMonth: () => _shiftAnchorMonth(-1),
                  onNextMonth: () => _shiftAnchorMonth(1),
                  onToday: _jumpToToday,
                  onDayTap: (day) {
                    _openDaySheet(day);
                  },
                ),
                _DraftCalendarMode.year => _YearModePanel(
                  key: const ValueKey("year"),
                  year: _anchorDate.year,
                  selectedDay: _selectedDay,
                  tasks: resolvedTasks,
                  onPrevYear: () => _shiftAnchorYear(-1),
                  onNextYear: () => _shiftAnchorYear(1),
                  onMonthDayTap: (day) {
                    setState(() {
                      _selectedDay = day;
                      _anchorDate = _firstDayOfMonth(day);
                      _mode = _DraftCalendarMode.month;
                    });
                    _openDaySheet(day);
                  },
                ),
              },
            ),
          ),
          if (monthTasks.isEmpty && _mode == _DraftCalendarMode.month) ...[
            const SizedBox(height: 8),
            Text(_emptyCopy, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  void _onModeChanged(_DraftCalendarMode next) {
    if (next == _mode) return;
    AppDebug.log(_logTag, _logModeChanged, extra: {"mode": next.name});
    setState(() => _mode = next);
  }

  List<_ResolvedDraftTask> _buildResolvedTasks() {
    final resolved = <_ResolvedDraftTask>[];
    for (var index = 0; index < widget.tasks.length; index += 1) {
      final base = widget.tasks[index];
      final override = _taskOverrides[index];
      final start = base.startDate?.toLocal();
      final due = base.dueDate?.toLocal();
      if (start == null || due == null) {
        // WHY: Calendar rendering ignores missing dates but keeps logs for diagnosis.
        AppDebug.log(
          _logTag,
          "skip_task_missing_dates",
          extra: {"index": index, "title": base.title},
        );
        continue;
      }
      final requiredHeadcount = override?.requiredHeadcount != null
          ? (override!.requiredHeadcount! < 1 ? 1 : override.requiredHeadcount!)
          : (base.requiredHeadcount < 1 ? 1 : base.requiredHeadcount);
      final assignedIds = override?.assignedStaffProfileIds != null
          ? _normalizeStringList(override!.assignedStaffProfileIds!)
          : _normalizeStringList(base.assignedStaffProfileIds);
      // WHY: Keep persisted/preview data coherent when assignment count outgrows headcount.
      final normalizedHeadcount = assignedIds.length > requiredHeadcount
          ? assignedIds.length
          : requiredHeadcount;
      final availableRoleCount = _staffForRole(base.roleRequired).length;
      final hasShortage = widget.staffProfiles.isNotEmpty
          ? normalizedHeadcount > availableRoleCount
          : base.hasShortage;
      resolved.add(
        _ResolvedDraftTask(
          index: index,
          id: base.id,
          title: base.title,
          phaseName: base.phaseName,
          roleRequired: base.roleRequired,
          requiredHeadcount: normalizedHeadcount,
          assignedStaffProfileIds: assignedIds,
          status: base.status,
          startDate: start,
          dueDate: due,
          instructions: base.instructions,
          hasShortage: hasShortage,
        ),
      );
    }
    return resolved;
  }

  void _emitOverridesChanged() {
    if (widget.onOverridesChanged == null) return;
    widget.onOverridesChanged!(
      Map<int, ProductionDraftTaskOverride>.unmodifiable(_taskOverrides),
    );
  }

  void _setTaskRequiredHeadcountOverride({
    required int taskIndex,
    required int requiredHeadcount,
  }) {
    final base = taskIndex >= 0 && taskIndex < widget.tasks.length
        ? widget.tasks[taskIndex]
        : null;
    if (base == null) return;

    final current = _taskOverrides[taskIndex];
    final normalizedAssigned = current?.assignedStaffProfileIds != null
        ? _normalizeStringList(current!.assignedStaffProfileIds!)
        : _normalizeStringList(base.assignedStaffProfileIds);
    final minimumHeadcount = normalizedAssigned.isEmpty
        ? 1
        : normalizedAssigned.length;
    final safeHeadcount = requiredHeadcount < minimumHeadcount
        ? minimumHeadcount
        : requiredHeadcount;
    final shouldKeepHeadcount = safeHeadcount != base.requiredHeadcount;

    final next = ProductionDraftTaskOverride(
      requiredHeadcount: shouldKeepHeadcount ? safeHeadcount : null,
      assignedStaffProfileIds: normalizedAssigned,
    );

    setState(() {
      if (next.isEmpty) {
        _taskOverrides.remove(taskIndex);
      } else {
        _taskOverrides[taskIndex] = next;
      }
    });

    AppDebug.log(
      _logTag,
      _logOverrideUpdated,
      extra: {
        "taskIndex": taskIndex,
        "requiredHeadcount": safeHeadcount,
        "overrideCount": _taskOverrides.length,
      },
    );
    _emitOverridesChanged();
  }

  void _setTaskAssignedStaffOverride({
    required int taskIndex,
    required List<String> assignedStaffProfileIds,
  }) {
    final normalizedIds = _normalizeStringList(assignedStaffProfileIds);
    final base = taskIndex >= 0 && taskIndex < widget.tasks.length
        ? widget.tasks[taskIndex]
        : null;
    if (base == null) return;

    final baseIds = _normalizeStringList(base.assignedStaffProfileIds);
    final current = _taskOverrides[taskIndex];
    final baseHeadcount = base.requiredHeadcount < 1
        ? 1
        : base.requiredHeadcount;
    final currentHeadcount = current?.requiredHeadcount ?? baseHeadcount;
    // WHY: Required headcount should never be lower than currently assigned staff.
    final normalizedHeadcount = normalizedIds.length > currentHeadcount
        ? normalizedIds.length
        : currentHeadcount;
    final shouldKeepHeadcount = normalizedHeadcount != baseHeadcount;
    final shouldKeepAssignedOverride = !listEquals(normalizedIds, baseIds);

    final next = ProductionDraftTaskOverride(
      requiredHeadcount: shouldKeepHeadcount ? normalizedHeadcount : null,
      assignedStaffProfileIds: shouldKeepAssignedOverride
          ? normalizedIds
          : null,
    );

    setState(() {
      if (next.isEmpty) {
        _taskOverrides.remove(taskIndex);
      } else {
        _taskOverrides[taskIndex] = next;
      }
    });

    AppDebug.log(
      _logTag,
      _logOverrideUpdated,
      extra: {
        "taskIndex": taskIndex,
        "assignedCount": normalizedIds.length,
        "overrideCount": _taskOverrides.length,
      },
    );
    _emitOverridesChanged();
  }

  void _adjustTaskHeadcount({
    required _ResolvedDraftTask task,
    required int delta,
  }) {
    final minimumHeadcount = task.assignedStaffProfileIds.isEmpty
        ? 1
        : task.assignedStaffProfileIds.length;
    final next = (task.requiredHeadcount + delta) < minimumHeadcount
        ? minimumHeadcount
        : (task.requiredHeadcount + delta);
    _setTaskRequiredHeadcountOverride(
      taskIndex: task.index,
      requiredHeadcount: next,
    );
  }

  Future<void> _openTaskStaffPicker(_ResolvedDraftTask task) async {
    final candidates = _staffForRole(task.roleRequired);
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "No staff available for role ${formatStaffRoleLabel(task.roleRequired, fallback: task.roleRequired)}",
          ),
        ),
      );
      return;
    }

    final selected = task.assignedStaffProfileIds.toSet();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text("Select staff for ${task.title}"),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: candidates.map((staff) {
                      final checked = selected.contains(staff.id);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        onChanged: (value) {
                          setLocalState(() {
                            if (value == true) {
                              selected.add(staff.id);
                            } else {
                              selected.remove(staff.id);
                            }
                          });
                        },
                        title: Text(_staffLabel(staff)),
                        subtitle: Text("${staff.id} | ${staff.staffRole}"),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(_assistantCloseLabel),
                ),
                FilledButton(
                  onPressed: () {
                    _setTaskAssignedStaffOverride(
                      taskIndex: task.index,
                      assignedStaffProfileIds: selected.toList(),
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text("Apply"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<BusinessStaffProfileSummary> _staffForRole(String roleRequired) {
    final normalizedRole = _normalizeRole(roleRequired);
    return widget.staffProfiles.where((profile) {
      return _normalizeRole(profile.staffRole) == normalizedRole;
    }).toList();
  }

  void _openAssistantPopup(List<_ResolvedDraftTask> tasks) {
    final recommendations = _buildRoleRecommendations(tasks);
    AppDebug.log(
      _logTag,
      _logAssistantOpen,
      extra: {
        "recommendationCount": recommendations.length,
        "taskCount": tasks.length,
      },
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.74,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _assistantTitle,
                      style: Theme.of(sheetContext).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _assistantSubtitle,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            _applyAutoAssignmentByRole(tasks);
                            Navigator.of(sheetContext).pop();
                          },
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text(_assistantAutoAssignLabel),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            _applyHeadcountRecommendation(tasks);
                            Navigator.of(sheetContext).pop();
                          },
                          icon: const Icon(Icons.auto_fix_high_outlined),
                          label: const Text(_assistantHeadcountLabel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (widget.staffProfiles.isEmpty)
                      const _WarningBanner(message: _assistantNoStaff),
                    const SizedBox(height: 8),
                    Expanded(
                      child: recommendations.isEmpty
                          ? Center(
                              child: Text(
                                _emptyCopy,
                                style: Theme.of(
                                  sheetContext,
                                ).textTheme.bodyMedium,
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: recommendations.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final recommendation = recommendations[index];
                                return _RoleRecommendationCard(
                                  recommendation: recommendation,
                                  onApplyRoleAutoAssign: () {
                                    _applyAutoAssignmentForRole(
                                      roleRequired: recommendation.roleRequired,
                                      tasks: tasks,
                                    );
                                    Navigator.of(sheetContext).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_RoleRecommendation> _buildRoleRecommendations(
    List<_ResolvedDraftTask> tasks,
  ) {
    final grouped = <String, List<_ResolvedDraftTask>>{};
    for (final task in tasks) {
      final roleKey = _normalizeRole(task.roleRequired);
      if (roleKey.isEmpty) continue;
      grouped.putIfAbsent(roleKey, () => <_ResolvedDraftTask>[]).add(task);
    }

    final recommendations = <_RoleRecommendation>[];
    for (final entry in grouped.entries) {
      final roleTasks = entry.value;
      final availableStaff = _staffForRole(entry.key);
      final peakDemand = roleTasks.fold<int>(
        0,
        (maxValue, task) => task.requiredHeadcount > maxValue
            ? task.requiredHeadcount
            : maxValue,
      );
      final dailyTaskCount = roleTasks.length;
      final recommendedHeadcount = availableStaff.isEmpty
          ? peakDemand
          : (peakDemand <= availableStaff.length
                ? peakDemand
                : availableStaff.length);
      recommendations.add(
        _RoleRecommendation(
          roleRequired: entry.key,
          taskCount: dailyTaskCount,
          peakDemand: peakDemand,
          recommendedHeadcount: recommendedHeadcount < 1
              ? 1
              : recommendedHeadcount,
          availableStaff: availableStaff,
        ),
      );
    }

    recommendations.sort(
      (left, right) => right.taskCount.compareTo(left.taskCount),
    );
    return recommendations;
  }

  void _applyAutoAssignmentByRole(List<_ResolvedDraftTask> tasks) {
    final roleCursor = <String, int>{};

    for (final task in tasks) {
      final candidates = _staffForRole(task.roleRequired);
      if (candidates.isEmpty) {
        continue;
      }

      final count = task.requiredHeadcount <= candidates.length
          ? task.requiredHeadcount
          : candidates.length;
      final cursor = roleCursor[_normalizeRole(task.roleRequired)] ?? 0;
      final assigned = <String>[];

      for (var i = 0; i < count; i += 1) {
        final idx = (cursor + i) % candidates.length;
        assigned.add(candidates[idx].id);
      }

      roleCursor[_normalizeRole(task.roleRequired)] = cursor + count;
      _setTaskAssignedStaffOverride(
        taskIndex: task.index,
        assignedStaffProfileIds: assigned,
      );
    }

    AppDebug.log(
      _logTag,
      _logAssistantAutoAssign,
      extra: {
        "taskCount": tasks.length,
        "overrideCount": _taskOverrides.length,
      },
    );
  }

  void _applyAutoAssignmentForRole({
    required String roleRequired,
    required List<_ResolvedDraftTask> tasks,
  }) {
    final normalizedRole = _normalizeRole(roleRequired);
    final roleTasks = tasks
        .where((task) => _normalizeRole(task.roleRequired) == normalizedRole)
        .toList();
    if (roleTasks.isEmpty) return;

    final candidates = _staffForRole(roleRequired);
    if (candidates.isEmpty) return;

    var cursor = 0;
    for (final task in roleTasks) {
      final count = task.requiredHeadcount <= candidates.length
          ? task.requiredHeadcount
          : candidates.length;
      final assigned = <String>[];
      for (var i = 0; i < count; i += 1) {
        assigned.add(candidates[(cursor + i) % candidates.length].id);
      }
      cursor += count;
      _setTaskAssignedStaffOverride(
        taskIndex: task.index,
        assignedStaffProfileIds: assigned,
      );
    }

    AppDebug.log(
      _logTag,
      _logAssistantAutoAssign,
      extra: {
        "role": normalizedRole,
        "taskCount": roleTasks.length,
        "overrideCount": _taskOverrides.length,
      },
    );
  }

  void _applyHeadcountRecommendation(List<_ResolvedDraftTask> tasks) {
    for (final task in tasks) {
      final availableCount = _staffForRole(task.roleRequired).length;
      if (availableCount <= 0) {
        continue;
      }
      final recommended = task.requiredHeadcount <= availableCount
          ? task.requiredHeadcount
          : availableCount;
      _setTaskRequiredHeadcountOverride(
        taskIndex: task.index,
        requiredHeadcount: recommended,
      );
    }

    AppDebug.log(
      _logTag,
      _logAssistantHeadcount,
      extra: {
        "taskCount": tasks.length,
        "overrideCount": _taskOverrides.length,
      },
    );
  }

  void _shiftSelectedDay(int deltaDays) {
    final next = _selectedDay.add(Duration(days: deltaDays));
    AppDebug.log(
      _logTag,
      _logNavigate,
      extra: {"targetDay": formatDateInput(next), "deltaDays": deltaDays},
    );
    setState(() {
      _selectedDay = DateTime(next.year, next.month, next.day);
      _anchorDate = _firstDayOfMonth(_selectedDay);
    });
  }

  void _shiftAnchorMonth(int deltaMonths) {
    final next = DateTime(_anchorDate.year, _anchorDate.month + deltaMonths, 1);
    AppDebug.log(
      _logTag,
      _logNavigate,
      extra: {"targetMonth": _monthLabel(next), "deltaMonths": deltaMonths},
    );
    setState(() => _anchorDate = next);
  }

  void _shiftAnchorYear(int deltaYears) {
    final next = DateTime(_anchorDate.year + deltaYears, 1, 1);
    AppDebug.log(
      _logTag,
      _logNavigate,
      extra: {"targetYear": next.year, "deltaYears": deltaYears},
    );
    setState(() => _anchorDate = next);
  }

  void _jumpToToday() {
    final today = DateTime.now();
    AppDebug.log(
      _logTag,
      _logNavigate,
      extra: {"targetDay": formatDateInput(today), "action": "today"},
    );
    setState(() {
      _selectedDay = DateTime(today.year, today.month, today.day);
      _anchorDate = _firstDayOfMonth(today);
    });
  }

  Future<void> _openDaySheet(DateTime day) async {
    final resolvedTasks = _buildResolvedTasks();
    final tasksForDay = _tasksForDay(day: day, tasks: resolvedTasks);
    AppDebug.log(
      _logTag,
      _logDayTap,
      extra: {"day": formatDateInput(day), "count": tasksForDay.length},
    );
    setState(() {
      _selectedDay = DateTime(day.year, day.month, day.day);
      _anchorDate = _firstDayOfMonth(day);
    });

    final addedFromSheet = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _DayTasksSheet(
          day: day,
          tasks: tasksForDay,
          staffProfiles: widget.staffProfiles,
          onHeadcountChange: (task, delta) =>
              _adjustTaskHeadcount(task: task, delta: delta),
          onAssignedStaffChange: (task, assignedStaffProfileIds) =>
              _setTaskAssignedStaffOverride(
                taskIndex: task.index,
                assignedStaffProfileIds: assignedStaffProfileIds,
              ),
          onAddTask: widget.onAddTaskForDay == null
              ? null
              : () async {
                  final phaseNameHint = tasksForDay.isNotEmpty
                      ? tasksForDay.first.phaseName
                      : "";
                  AppDebug.log(
                    _logTag,
                    _logDayAddTask,
                    extra: {
                      "day": formatDateInput(day),
                      "phaseNameHint": phaseNameHint,
                    },
                  );
                  await widget.onAddTaskForDay?.call(day, phaseNameHint);
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
        );
      },
    );

    AppDebug.log(
      _logTag,
      _logDayAddTaskResult,
      extra: {
        "day": formatDateInput(day),
        "addedFromSheet": addedFromSheet == true,
      },
    );

    if (addedFromSheet == true && mounted) {
      // WHY: Re-open the same day sheet so user immediately sees the new task.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openDaySheet(day);
      });
    }
  }
}

class _TopCommandBar extends StatelessWidget {
  final _DraftCalendarMode mode;
  final ValueChanged<_DraftCalendarMode> onModeChanged;
  final VoidCallback onAssistantTap;

  const _TopCommandBar({
    required this.mode,
    required this.onModeChanged,
    required this.onAssistantTap,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep mode labels readable on medium widths where "Month/Year" can wrap.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 840;
        // WHY: Week mode is intentionally hidden to keep the UX focused on
        // month navigation + per-day task sheet editing.
        final effectiveMode = mode == _DraftCalendarMode.week
            ? _DraftCalendarMode.month
            : mode;
        final segmented = SegmentedButton<_DraftCalendarMode>(
          segments: const [
            ButtonSegment(
              value: _DraftCalendarMode.day,
              label: Text("Day", maxLines: 1, softWrap: false),
            ),
            ButtonSegment(
              value: _DraftCalendarMode.month,
              label: Text("Month", maxLines: 1, softWrap: false),
            ),
            ButtonSegment(
              value: _DraftCalendarMode.year,
              label: Text("Year", maxLines: 1, softWrap: false),
            ),
          ],
          showSelectedIcon: false,
          selected: <_DraftCalendarMode>{effectiveMode},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            onModeChanged(selection.first);
          },
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RoundIconButton(
                    tooltip: "Calendar",
                    icon: Icons.calendar_month_outlined,
                    onTap: () => onModeChanged(_DraftCalendarMode.month),
                  ),
                  const Spacer(),
                  _RoundIconButton(
                    tooltip: _assistantTooltip,
                    icon: Icons.smart_toy_outlined,
                    onTap: onAssistantTap,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: segmented),
            ],
          );
        }

        return Row(
          children: [
            _RoundIconButton(
              tooltip: "Calendar",
              icon: Icons.calendar_month_outlined,
              onTap: () => onModeChanged(_DraftCalendarMode.month),
            ),
            const SizedBox(width: 8),
            Expanded(child: segmented),
            const SizedBox(width: 8),
            _RoundIconButton(
              tooltip: _assistantTooltip,
              icon: Icons.smart_toy_outlined,
              onTap: onAssistantTap,
            ),
          ],
        );
      },
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _InfoLabels extends StatelessWidget {
  final ProductionAiDraftSchedulePolicy? schedulePolicy;

  const _InfoLabels({required this.schedulePolicy});

  @override
  Widget build(BuildContext context) {
    final timezone = schedulePolicy?.timezone.trim().isNotEmpty == true
        ? schedulePolicy!.timezone
        : _localTimezoneLabel();
    final blocksLabel = schedulePolicy?.blocksLabel ?? "No blocks";
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _InfoPill(
          icon: Icons.public_outlined,
          text: "$_timezoneLabelPrefix $timezone",
        ),
        _InfoPill(
          icon: Icons.schedule_outlined,
          text: "$_blocksLabelPrefix $blocksLabel",
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_calendarSurfaceRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;

  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: AppStatusTone.warning,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.foreground),
      ),
    );
  }
}

class _MonthModePanel extends StatelessWidget {
  final DateTime monthAnchor;
  final DateTime selectedDay;
  final List<_ResolvedDraftTask> tasks;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onDayTap;

  const _MonthModePanel({
    super.key,
    required this.monthAnchor,
    required this.selectedDay,
    required this.tasks,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final monthCells = _buildMonthCells(monthAnchor);
    final rowCount = (monthCells.length / 7).ceil();
    const mainAxisSpacing = 8.0;
    const crossAxisSpacing = 8.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeToolbar(
          title: _monthTitle(monthAnchor),
          onPrev: onPrevMonth,
          onNext: onNextMonth,
          onToday: onToday,
        ),
        const SizedBox(height: 8),
        const _WeekdayHeader(),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final cellHeight =
                  (availableHeight - ((rowCount - 1) * mainAxisSpacing)) /
                  rowCount;

              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: monthCells.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: mainAxisSpacing,
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisExtent: cellHeight.clamp(52.0, 180.0),
                ),
                itemBuilder: (context, index) {
                  final day = monthCells[index];
                  if (day == null) {
                    return const SizedBox.shrink();
                  }
                  final dayTasks = _tasksForDay(day: day, tasks: tasks);
                  return _MonthDayCell(
                    day: day,
                    isSelected: _isSameDay(day, selectedDay),
                    tasks: dayTasks,
                    onTap: () => onDayTap(day),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ModeToolbar extends StatelessWidget {
  final String title;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  const _ModeToolbar({
    required this.title,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controls = Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_calendarToolbarControlRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            visualDensity: VisualDensity.compact,
          ),
          FilledButton.tonal(
            onPressed: onToday,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: const Text("Today"),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 620;
        if (isCompact) {
          // WHY: Stack toolbar controls on smaller widths to keep month title readable.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: controls),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            controls,
          ],
        );
      },
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: _weekdays
          .map(
            (day) => Expanded(
              child: Text(
                day,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final List<_ResolvedDraftTask> tasks;
  final VoidCallback onTap;

  const _MonthDayCell({
    required this.day,
    required this.isSelected,
    required this.tasks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasTasks = tasks.isNotEmpty;
          final baseBackground = isSelected
              ? colorScheme.surfaceContainerLow
              : colorScheme.surface;
          final borderColor = isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant;

          return Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_calendarDayCellRadius),
              color: baseBackground,
              border: Border.all(
                color: borderColor,
                width: isSelected ? 1.8 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: _monthCellHeaderHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        // WHY: Reserve indicator space so day number never gets covered.
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            day.day.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                      if (hasTasks)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: _DayTaskSummaryIndicator(tasks: tasks),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DayTaskSummaryIndicator extends StatelessWidget {
  final List<_ResolvedDraftTask> tasks;

  const _DayTaskSummaryIndicator({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // WHY: Keep day number legible by using a compact icon-only task marker.
    final core = SizedBox(
      width: _monthCellIndicatorBaseSize,
      height: _monthCellIndicatorBaseSize,
      child: Icon(
        Icons.event_note_outlined,
        size: _monthCellHeaderIndicatorIconSize,
        color: colorScheme.onSurfaceVariant,
      ),
    );
    if (!_supportsHoverTooltip(context)) {
      return core;
    }
    // WHY: Hover hint keeps the grid clean while still exposing task detail.
    return Tooltip(message: _daySummaryTooltipMessage(tasks), child: core);
  }
}

String _daySummaryTooltipMessage(List<_ResolvedDraftTask> tasks) {
  if (tasks.isEmpty) {
    return "No tasks";
  }
  final lines = tasks
      .take(4)
      .map(
        (task) =>
            "${_clockLabel(task.startDate)}-${_clockLabel(task.dueDate)} ${task.title}",
      )
      .toList();
  final overflow = tasks.length - lines.length;
  if (overflow > 0) {
    lines.add("+$overflow more");
  }
  return lines.join("\n");
}

bool _supportsHoverTooltip(BuildContext context) {
  final platform = Theme.of(context).platform;
  return kIsWeb ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
}

class _WeekModePanel extends StatelessWidget {
  final DateTime selectedDay;
  final List<_ResolvedDraftTask> tasks;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onDayTap;

  const _WeekModePanel({
    super.key,
    required this.selectedDay,
    required this.tasks,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onToday,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final weekStart = _startOfWeekMonday(selectedDay);
    final weekDays = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeToolbar(
          title: "Week of ${formatDateLabel(weekStart)}",
          onPrev: onPrevWeek,
          onNext: onNextWeek,
          onToday: onToday,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 7 * 210,
              child: Row(
                children: weekDays.map((day) {
                  final dayTasks = _tasksForDay(day: day, tasks: tasks);
                  return SizedBox(
                    width: 210,
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => onDayTap(day),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${_weekdayLabel(day.weekday)} ${day.day}",
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: dayTasks.isEmpty
                                    ? Text(
                                        "No tasks",
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      )
                                    : ListView.builder(
                                        itemCount: dayTasks.length,
                                        itemBuilder: (context, index) {
                                          final task = dayTasks[index];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                              ),
                                              child: Text(
                                                "${_clockLabel(task.startDate)}-${_clockLabel(task.dueDate)} ${task.title}",
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayModePanel extends StatelessWidget {
  final DateTime day;
  final List<_ResolvedDraftTask> tasks;
  final List<BusinessStaffProfileSummary> staffProfiles;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_ResolvedDraftTask> onTaskTap;
  final void Function(_ResolvedDraftTask task, int delta) onHeadcountChange;
  final Future<void> Function()? onAddTask;

  const _DayModePanel({
    super.key,
    required this.day,
    required this.tasks,
    required this.staffProfiles,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onTaskTap,
    required this.onHeadcountChange,
    this.onAddTask,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeToolbar(
          title: "${formatDateLabel(day)} (${_weekdayLabel(day.weekday)})",
          onPrev: onPrev,
          onNext: onNext,
          onToday: onToday,
        ),
        if (onAddTask != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await onAddTask?.call();
              },
              icon: const Icon(Icons.add),
              label: const Text(_daySheetAddTaskButton),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Text(
                    _daySheetEmptyCopy,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.separated(
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _DayTaskCard(
                      task: task,
                      staffProfiles: staffProfiles,
                      onTap: () => onTaskTap(task),
                      onHeadcountChange: (delta) =>
                          onHeadcountChange(task, delta),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DayTaskCard extends StatelessWidget {
  final _ResolvedDraftTask task;
  final List<BusinessStaffProfileSummary> staffProfiles;
  final VoidCallback onTap;
  final ValueChanged<int> onHeadcountChange;

  const _DayTaskCard({
    required this.task,
    required this.staffProfiles,
    required this.onTap,
    required this.onHeadcountChange,
  });

  @override
  Widget build(BuildContext context) {
    final statusTone = task.hasShortage
        ? AppStatusTone.warning
        : AppStatusTone.neutral;
    final statusColors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: statusTone,
    );
    final theme = Theme.of(context);
    final assignedStaffLabels = task.assignedStaffProfileIds
        .map((id) {
          final profileIndex = staffProfiles.indexWhere(
            (entry) => entry.id == id,
          );
          if (profileIndex < 0) {
            return id;
          }
          final label = _staffDisplayName(staffProfiles[profileIndex]).trim();
          return label.isEmpty ? id : label;
        })
        .where((value) => value.trim().isNotEmpty)
        .toList();
    // WHY: Role-count label should reflect real selected assignees when available.
    final roleDisplayCount = task.assignedStaffProfileIds.isNotEmpty
        ? task.assignedStaffProfileIds.length
        : task.requiredHeadcount;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surface,
        border: Border.all(
          color: task.hasShortage
              ? statusColors.foreground.withValues(alpha: 0.28)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Time range is the highest-priority calendar context for day cards.
          Text(
            "${_clockLabel(task.startDate)} - ${_clockLabel(task.dueDate)}",
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            task.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DayMetaChip(
                label: "Status",
                value: task.status.isEmpty ? _statusFallback : task.status,
                tone: task.hasShortage
                    ? AppStatusTone.warning
                    : AppStatusTone.neutral,
              ),
              _DayMetaChip(
                label: "Role",
                value:
                    "${formatStaffRoleLabel(task.roleRequired, fallback: task.roleRequired)} x$roleDisplayCount",
                tone: AppStatusTone.neutral,
              ),
              _DayMetaChip(
                label: "Headcount",
                value:
                    "${task.assignedStaffProfileIds.length}/${task.requiredHeadcount}",
                tone: task.hasShortage
                    ? AppStatusTone.warning
                    : AppStatusTone.neutral,
              ),
              _DayMetaChip(
                label: "Calendar week",
                value: _isoWeekLabel(task.startDate),
                tone: AppStatusTone.neutral,
              ),
              _DayMetaChip(
                label: "Phase",
                value: task.phaseName.isEmpty ? "-" : task.phaseName,
                tone: AppStatusTone.neutral,
              ),
              _DayMetaChip(
                label: "Staff",
                value: task.assignedStaffProfileIds.isEmpty
                    ? "Unassigned"
                    : "${task.assignedStaffProfileIds.length} selected",
                tone: AppStatusTone.neutral,
              ),
            ],
          ),
          if (assignedStaffLabels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: assignedStaffLabels
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      child: Text(label, style: theme.textTheme.labelSmall),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.group_outlined),
                label: const Text(_daySheetAssignButton),
              ),
              IconButton(
                tooltip: "Decrease headcount",
                onPressed: () => onHeadcountChange(-1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text("x${task.requiredHeadcount}"),
              IconButton(
                tooltip: "Increase headcount",
                onPressed: () => onHeadcountChange(1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColors.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  task.status.isEmpty ? _statusFallback : task.status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColors.foreground,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayMetaChip extends StatelessWidget {
  final String label;
  final String value;
  final AppStatusTone tone;

  const _DayMetaChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: tone,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label: ",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.foreground),
          ),
        ],
      ),
    );
  }
}

class _YearModePanel extends StatelessWidget {
  final int year;
  final DateTime selectedDay;
  final List<_ResolvedDraftTask> tasks;
  final VoidCallback onPrevYear;
  final VoidCallback onNextYear;
  final ValueChanged<DateTime> onMonthDayTap;

  const _YearModePanel({
    super.key,
    required this.year,
    required this.selectedDay,
    required this.tasks,
    required this.onPrevYear,
    required this.onNextYear,
    required this.onMonthDayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeToolbar(
          title: "$year",
          onPrev: onPrevYear,
          onNext: onNextYear,
          onToday: () => onMonthDayTap(DateTime.now()),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            itemCount: 12,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _yearGridColumnsForWidth(
                MediaQuery.of(context).size.width,
              ),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.25,
            ),
            itemBuilder: (context, index) {
              final month = DateTime(year, index + 1, 1);
              return _MiniMonthCard(
                month: month,
                selectedDay: selectedDay,
                tasks: tasks,
                onDayTap: onMonthDayTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MiniMonthCard extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final List<_ResolvedDraftTask> tasks;
  final ValueChanged<DateTime> onDayTap;

  const _MiniMonthCard({
    required this.month,
    required this.selectedDay,
    required this.tasks,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final cells = _buildMonthCells(month);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _monthName(month.month),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: _weekdays
                  .map(
                    (day) => Expanded(
                      child: Text(
                        day.substring(0, 1),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cells.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemBuilder: (context, index) {
                  final day = cells[index];
                  if (day == null) return const SizedBox.shrink();
                  final isSelected = _isSameDay(day, selectedDay);
                  final dayTasks = _tasksForDay(day: day, tasks: tasks);
                  return InkWell(
                    onTap: () => onDayTap(day),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        day.day.toString(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: dayTasks.isNotEmpty
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleRecommendationCard extends StatelessWidget {
  final _RoleRecommendation recommendation;
  final VoidCallback onApplyRoleAutoAssign;

  const _RoleRecommendationCard({
    required this.recommendation,
    required this.onApplyRoleAutoAssign,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = formatStaffRoleLabel(
      recommendation.roleRequired,
      fallback: recommendation.roleRequired,
    );
    final shortage =
        recommendation.peakDemand > recommendation.availableStaff.length;
    final tone = shortage ? AppStatusTone.warning : AppStatusTone.info;
    final colors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: tone,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  roleLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  shortage ? "Shortage" : "Balanced",
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Tasks: ${recommendation.taskCount} | Peak demand: ${recommendation.peakDemand} | Available: ${recommendation.availableStaff.length} | Recommended: ${recommendation.recommendedHeadcount}",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          if (recommendation.availableStaff.isEmpty)
            Text(
              "No staff available for this role.",
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: recommendation.availableStaff
                  .map(
                    (staff) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      child: Text(
                        "${_staffDisplayName(staff)} (${_staffCode(staff.id)})",
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onApplyRoleAutoAssign,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text("Apply role recommendation"),
          ),
        ],
      ),
    );
  }
}

class _DayTasksSheet extends StatefulWidget {
  final DateTime day;
  final List<_ResolvedDraftTask> tasks;
  final List<BusinessStaffProfileSummary> staffProfiles;
  final void Function(_ResolvedDraftTask task, int delta) onHeadcountChange;
  final void Function(_ResolvedDraftTask task, List<String> assignedIds)?
  onAssignedStaffChange;
  final Future<void> Function()? onAddTask;

  const _DayTasksSheet({
    required this.day,
    required this.tasks,
    required this.staffProfiles,
    required this.onHeadcountChange,
    this.onAssignedStaffChange,
    this.onAddTask,
  });

  @override
  State<_DayTasksSheet> createState() => _DayTasksSheetState();
}

class _DayTasksSheetState extends State<_DayTasksSheet> {
  late List<_ResolvedDraftTask> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = List<_ResolvedDraftTask>.from(widget.tasks);
  }

  int _availableRoleCount(String roleRequired) {
    final normalizedRole = _normalizeRole(roleRequired);
    return widget.staffProfiles
        .where((profile) => _normalizeRole(profile.staffRole) == normalizedRole)
        .length;
  }

  void _onHeadcountChangeLocal(_ResolvedDraftTask task, int delta) {
    final taskPosition = _tasks.indexWhere((entry) => entry.id == task.id);
    if (taskPosition < 0) {
      return;
    }
    final current = _tasks[taskPosition];
    final minimumHeadcount = current.assignedStaffProfileIds.isEmpty
        ? 1
        : current.assignedStaffProfileIds.length;
    final nextHeadcount = (current.requiredHeadcount + delta).clamp(
      minimumHeadcount,
      999,
    );
    if (nextHeadcount == current.requiredHeadcount) {
      return;
    }

    final shouldComputeShortage = widget.staffProfiles.isNotEmpty;
    final nextShortage = shouldComputeShortage
        ? nextHeadcount > _availableRoleCount(current.roleRequired)
        : current.hasShortage;

    setState(() {
      _tasks[taskPosition] = current.copyWith(
        requiredHeadcount: nextHeadcount,
        hasShortage: nextShortage,
      );
    });

    AppDebug.log(
      _logTag,
      "day_sheet_headcount_change",
      extra: {
        "taskId": current.id,
        "delta": delta,
        "nextHeadcount": nextHeadcount,
      },
    );
    widget.onHeadcountChange(current, delta);
  }

  Future<void> _openStaffPickerLocal(_ResolvedDraftTask task) async {
    final candidates = widget.staffProfiles.where((profile) {
      return _normalizeRole(profile.staffRole) ==
          _normalizeRole(task.roleRequired);
    }).toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "No staff available for role ${formatStaffRoleLabel(task.roleRequired, fallback: task.roleRequired)}",
          ),
        ),
      );
      return;
    }

    final selected = task.assignedStaffProfileIds.toSet();
    final appliedSelection = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text("Select staff for ${task.title}"),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: candidates.map((staff) {
                      final checked = selected.contains(staff.id);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        onChanged: (value) {
                          setLocalState(() {
                            if (value == true) {
                              selected.add(staff.id);
                            } else {
                              selected.remove(staff.id);
                            }
                          });
                        },
                        title: Text(_staffLabel(staff)),
                        subtitle: Text(
                          "${staff.id} | ${formatStaffRoleLabel(staff.staffRole, fallback: staff.staffRole)}",
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(_assistantCloseLabel),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(selected.toList());
                  },
                  child: const Text("Apply"),
                ),
              ],
            );
          },
        );
      },
    );

    if (appliedSelection == null) {
      return;
    }

    final taskPosition = _tasks.indexWhere((entry) => entry.id == task.id);
    if (taskPosition < 0) {
      return;
    }
    final normalizedIds = _normalizeStringList(appliedSelection);
    final nextHeadcount =
        normalizedIds.length > _tasks[taskPosition].requiredHeadcount
        ? normalizedIds.length
        : _tasks[taskPosition].requiredHeadcount;
    final shouldComputeShortage = widget.staffProfiles.isNotEmpty;
    final nextShortage = shouldComputeShortage
        ? nextHeadcount > _availableRoleCount(_tasks[taskPosition].roleRequired)
        : _tasks[taskPosition].hasShortage;

    setState(() {
      _tasks[taskPosition] = _tasks[taskPosition].copyWith(
        requiredHeadcount: nextHeadcount,
        assignedStaffProfileIds: normalizedIds,
        hasShortage: nextShortage,
      );
    });

    AppDebug.log(
      _logTag,
      "day_sheet_staff_apply",
      extra: {
        "taskId": task.id,
        "assignedCount": normalizedIds.length,
        "nextHeadcount": nextHeadcount,
      },
    );
    widget.onAssignedStaffChange?.call(_tasks[taskPosition], normalizedIds);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Tasks on ${formatDateLabel(widget.day)}",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.onAddTask != null)
                  TextButton.icon(
                    onPressed: () async {
                      AppDebug.log(
                        _logTag,
                        _logDayAddTask,
                        extra: {"day": formatDateInput(widget.day)},
                      );
                      await widget.onAddTask?.call();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text(_daySheetAddTaskButton),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(_daySheetEmptyCopy),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    return _DayTaskCard(
                      task: task,
                      staffProfiles: widget.staffProfiles,
                      onTap: () => _openStaffPickerLocal(task),
                      onHeadcountChange: (delta) =>
                          _onHeadcountChangeLocal(task, delta),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedDraftTask {
  final int index;
  final String id;
  final String title;
  final String phaseName;
  final String roleRequired;
  final int requiredHeadcount;
  final List<String> assignedStaffProfileIds;
  final String status;
  final DateTime startDate;
  final DateTime dueDate;
  final String instructions;
  final bool hasShortage;

  const _ResolvedDraftTask({
    required this.index,
    required this.id,
    required this.title,
    required this.phaseName,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.assignedStaffProfileIds,
    required this.status,
    required this.startDate,
    required this.dueDate,
    required this.instructions,
    required this.hasShortage,
  });

  _ResolvedDraftTask copyWith({
    int? requiredHeadcount,
    List<String>? assignedStaffProfileIds,
    bool? hasShortage,
  }) {
    return _ResolvedDraftTask(
      index: index,
      id: id,
      title: title,
      phaseName: phaseName,
      roleRequired: roleRequired,
      requiredHeadcount: requiredHeadcount ?? this.requiredHeadcount,
      assignedStaffProfileIds:
          assignedStaffProfileIds ?? this.assignedStaffProfileIds,
      status: status,
      startDate: startDate,
      dueDate: dueDate,
      instructions: instructions,
      hasShortage: hasShortage ?? this.hasShortage,
    );
  }
}

class _RoleRecommendation {
  final String roleRequired;
  final int taskCount;
  final int peakDemand;
  final int recommendedHeadcount;
  final List<BusinessStaffProfileSummary> availableStaff;

  const _RoleRecommendation({
    required this.roleRequired,
    required this.taskCount,
    required this.peakDemand,
    required this.recommendedHeadcount,
    required this.availableStaff,
  });
}

DateTime _firstDayOfMonth(DateTime date) {
  return DateTime(date.year, date.month, 1);
}

DateTime _startOfWeekMonday(DateTime date) {
  final safe = DateTime(date.year, date.month, date.day);
  return safe.subtract(Duration(days: safe.weekday - DateTime.monday));
}

String _monthLabel(DateTime month) {
  final safeMonth = month.month.toString().padLeft(2, '0');
  return "${month.year}-$safeMonth";
}

String _monthTitle(DateTime date) {
  return "${_monthName(date.month)} ${date.year}";
}

String _monthName(int month) {
  const names = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  if (month < 1 || month > 12) return "Month";
  return names[month - 1];
}

String _weekdayLabel(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return "Mon";
    case DateTime.tuesday:
      return "Tue";
    case DateTime.wednesday:
      return "Wed";
    case DateTime.thursday:
      return "Thu";
    case DateTime.friday:
      return "Fri";
    case DateTime.saturday:
      return "Sat";
    case DateTime.sunday:
      return "Sun";
    default:
      return "";
  }
}

String _clockLabel(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return "$hour:$minute";
}

String _isoWeekLabel(DateTime value) {
  final safe = DateTime.utc(value.year, value.month, value.day);
  // WHY: ISO week uses the week containing Thursday to determine week-year.
  final thursday = safe.add(Duration(days: 4 - safe.weekday));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final firstWeekStart = firstThursday.subtract(
    Duration(days: firstThursday.weekday - DateTime.monday),
  );
  final weekNumber = (thursday.difference(firstWeekStart).inDays ~/ 7) + 1;
  final paddedWeek = weekNumber.toString().padLeft(2, '0');
  return "W$paddedWeek";
}

String _localTimezoneLabel() {
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? "-" : "+";
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final name = now.timeZoneName.trim();
  if (name.isEmpty) {
    return "UTC$sign$hours:$minutes";
  }
  return "$name (UTC$sign$hours:$minutes)";
}

int _yearGridColumnsForWidth(double width) {
  if (width >= 1200) return 4;
  if (width >= 820) return 3;
  return 2;
}

String _normalizeRole(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
    RegExp(r"[^a-z0-9]+"),
    "_",
  );
  return normalized.replaceAll(RegExp(r"^_+|_+$"), "");
}

String _staffDisplayName(BusinessStaffProfileSummary staff) {
  final name = staff.userName?.trim() ?? "";
  if (name.isNotEmpty) return name;
  final email = staff.userEmail?.trim() ?? "";
  if (email.isNotEmpty) return email;
  return staff.id;
}

String _staffLabel(BusinessStaffProfileSummary staff) {
  return "${_staffDisplayName(staff)} (${formatStaffRoleLabel(staff.staffRole, fallback: staff.staffRole)})";
}

String _staffCode(String id) {
  final safe = id.trim();
  if (safe.length <= 8) return safe;
  return safe.substring(safe.length - 8);
}

List<String> _normalizeStringList(List<String> input) {
  return input
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
}

List<DateTime?> _buildMonthCells(DateTime month) {
  final first = _firstDayOfMonth(month);
  final next = DateTime(month.year, month.month + 1, 1);
  final dayCount = next.difference(first).inDays;
  final leading = first.weekday - 1;

  final cells = <DateTime?>[];
  for (var i = 0; i < leading; i += 1) {
    cells.add(null);
  }
  for (var day = 1; day <= dayCount; day += 1) {
    cells.add(DateTime(month.year, month.month, day));
  }
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

List<_ResolvedDraftTask> _tasksForRange({
  required List<_ResolvedDraftTask> tasks,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) {
  return tasks.where((task) {
    final start = task.startDate;
    final end = task.dueDate;
    return start.isBefore(endExclusive) &&
        (end.isAtSameMomentAs(startInclusive) || end.isAfter(startInclusive));
  }).toList();
}

List<_ResolvedDraftTask> _tasksForDay({
  required DateTime day,
  required List<_ResolvedDraftTask> tasks,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  return tasks.where((task) {
    final start = task.startDate;
    final end = task.dueDate;
    return start.isBefore(dayEnd) &&
        (end.isAtSameMomentAs(dayStart) || end.isAfter(dayStart));
  }).toList()..sort((left, right) => left.startDate.compareTo(right.startDate));
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
