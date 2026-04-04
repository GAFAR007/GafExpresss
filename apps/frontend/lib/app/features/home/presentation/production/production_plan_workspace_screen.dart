/// lib/app/features/home/presentation/production/production_plan_workspace_screen.dart
/// -----------------------------------------------------------------------------
/// WHAT:
/// - Calendar-first operational workspace for a production plan.
///
/// WHY:
/// - Keeps managers focused on the day-by-day schedule instead of a crowded report.
/// - Makes staffing, progress logging, and status tracking available from the calendar.
///
/// HOW:
/// - Fetches the same production plan detail payload already used by the reporting screen.
/// - Renders a month grid plus a selected-day agenda.
/// - Reuses existing production actions for task status, staff assignment, and progress logging.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';

const String _logTag = "PRODUCTION_PLAN_WORKSPACE";
const String _logBuild = "build()";
const String _logMonthChanged = "month_changed";
const String _logDayChanged = "day_changed";
const String _logAssignStaff = "assign_staff";
const String _logTaskStatus = "task_status";
const String _logProgress = "log_progress";
const String _logApproveTask = "approve_task";
const String _logRejectTask = "reject_task";
const String _logApproveProgress = "approve_progress";
const String _logRejectProgress = "reject_progress";

const String _screenTitle = "Production plan";
const String _workspaceTitle = "Calendar workspace";
const String _workspaceSubtitle =
    "Use the calendar to assign staff, remove staff, and track progress day by day.";
const String _selectedDayTitle = "Selected day";
const String _selectedDayEmptyTitle = "No scheduled work";
const String _selectedDayEmptyMessage =
    "Pick another date or open insights if you need the full plan report.";
const String _monthEmptyTitle = "No scheduled work this month";
const String _monthEmptyMessage =
    "Move to another month or start assigning tasks from the selected day.";
const String _viewInsightsLabel = "View insights";
const String _viewInsightsTooltip = "Open plan insights";
const String _refreshTooltip = "Refresh";
const String _todayLabel = "Today";
const String _unassignedLabel = "Unassigned";
const String _assignStaffLabel = "Manage staff";
const String _removeStaffHint = "Leave everything unchecked to remove staff.";
const String _logProgressLabel = "Log progress";
const String _taskApproveLabel = "Approve task";
const String _taskRejectLabel = "Reject task";
const String _progressApproveLabel = "Approve log";
const String _progressRejectLabel = "Review log";
const String _scheduleLabel = "Schedule";
const String _roleLabel = "Role";
const String _assignedLabel = "Assigned";
const String _unitsLabel = "Units";
const String _instructionsLabel = "Notes";
const String _activityLabel = "Activity";
const String _logsLabel = "Logs";
const String _expectedLabel = "Expected";
const String _actualLabel = "Actual";
const String _actualTodayLabel = "Actual for this day";
const String _approvalLabel = "Approval";
const String _noActivityLabel = "No progress logs yet for this day.";
const String _estimatedDatesLabel = "Estimated";
const String _attendanceUnsetLabel =
    "No clock-in or clock-out set for this day.";
const String _attendanceOpenLabel = "Open";
const String _setAttendanceLabel = "Set time";
const String _editAttendanceLabel = "Edit time";
const String _attendanceShiftOpenHint =
    "Clock-in is set. Add clock-out to close this shift for the day.";
const String _attendanceReadyForProgressHint =
    "Time captured. Next: log progress below, then mark the task done if this assignment is complete.";
const String _attendanceDialogTitle = "Set staff attendance";
const String _attendanceDialogClockInLabel = "Clock in";
const String _attendanceDialogClockOutLabel = "Clock out";
const String _attendanceDialogHelp =
    "Set the actual clock-in and clock-out for the selected day.";
const String _attendanceClockInRequired = "Clock-in time is required.";
const String _attendanceClockOrderInvalid = "Clock-out must be after clock-in.";
const String _attendanceSaveLabel = "Save";
const String _attendanceCancelLabel = "Cancel";
const String _attendanceUpdateSuccess =
    "Attendance updated. Next: log progress for this day, then mark the task done if the assignment is complete.";
const String _attendanceUpdateFailure = "Unable to update attendance.";
const String _daySummaryTasksLabel = "Tasks";
const String _daySummaryAssignedLabel = "Assigned";
const String _daySummaryLoggedLabel = "Logged";
const String _daySummaryDoneLabel = "Done";
const String _taskAssignmentSuccess = "Staff assignment updated.";
const String _taskAssignmentFailure = "Unable to update task staff.";
const String _taskStatusSuccess = "Task status updated.";
const String _taskStatusFailure = "Unable to update task status.";
const String _taskProgressSuccess = "Daily progress logged.";
const String _taskProgressFailure = "Unable to log daily progress.";
const String _approveTaskSuccess = "Task approved.";
const String _approveTaskFailure = "Unable to approve task.";
const String _rejectTaskSuccess = "Task rejected.";
const String _rejectTaskFailure = "Unable to reject task.";
const String _approveProgressSuccess = "Progress approved.";
const String _approveProgressFailure = "Unable to approve progress.";
const String _rejectProgressSuccess = "Progress marked for review.";
const String _rejectProgressFailure = "Unable to mark progress for review.";
const String _staffDialogApplyLabel = "Apply";
const String _staffDialogCancelLabel = "Cancel";
const String _staffDialogEmptyLabel =
    "No staff profiles match this task role yet. Add staff first or broaden the role assignment.";
const String _logDialogTitle = "Record daily progress";
const String _logDialogSaveLabel = "Save daily log";
const String _logDialogCancelLabel = "Cancel";
const String _logDialogDelayRequired =
    "Choose a delay reason if this staff completed 0 today.";
const String _logDialogStaffLabel = "Staff who did this work today";
const String _logDialogUnitLabel = "Assigned plot / unit";
const String _logDialogActualLabel =
    "Actual plots/units this staff completed today";
const String _logDialogDelayLabel = "Delay reason";
const String _logDialogDelayHelper =
    "Use None when work was completed. Choose the real reason only if this staff completed 0 today.";
const String _logDialogNotesLabel = "Daily notes";
const String _logDialogWorkflowHint =
    "Record what one assigned staff actually completed on this date. This is not the total for the whole task. Example: if 6 plots are planned and Aisha completed 2.7, enter 2.7 here.";
const String _logDialogNotesHint =
    "Example: Inspected 2.7 plots and confirmed irrigation status.";
const String _rejectDialogTitle = "Reject task";
const String _rejectDialogHint = "Add a short reason";
const String _rejectProgressDialogTitle = "Mark progress for review";
const String _taskStatusPending = "pending";
const String _taskStatusInProgress = "in_progress";
const String _taskStatusDone = "done";
const List<String> _taskStatusOptions = [
  _taskStatusPending,
  _taskStatusInProgress,
  _taskStatusDone,
];
const String _delayReasonNone = "none";
const String _delayReasonRain = "rain";
const String _delayReasonEquipmentFailure = "equipment_failure";
const String _delayReasonLabourShortage = "labour_shortage";
const String _delayReasonHealth = "health";
const String _delayReasonInputUnavailable = "input_unavailable";
const String _delayReasonManagementDelay = "management_delay";
const List<String> _delayReasonOptions = [
  _delayReasonNone,
  _delayReasonRain,
  _delayReasonEquipmentFailure,
  _delayReasonLabourShortage,
  _delayReasonHealth,
  _delayReasonInputUnavailable,
  _delayReasonManagementDelay,
];
const List<String> _weekdayLabels = [
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
  "Sun",
];

const double _pagePadding = 16;
const double _sectionSpacing = 18;
const double _cardSpacing = 12;
const double _calendarSpacing = 8;
const double _dayTileRadius = 14;
const double _dayTilePadding = 10;
const double _agendaCardPadding = 14;

enum _WorkspaceCalendarMode { day, month, year }

class ProductionPlanWorkspaceScreen extends ConsumerStatefulWidget {
  final String planId;

  const ProductionPlanWorkspaceScreen({super.key, required this.planId});

  @override
  ConsumerState<ProductionPlanWorkspaceScreen> createState() =>
      _ProductionPlanWorkspaceScreenState();
}

class _ProductionPlanWorkspaceScreenState
    extends ConsumerState<ProductionPlanWorkspaceScreen> {
  DateTime? _visibleMonth;
  DateTime? _selectedDay;
  _WorkspaceCalendarMode _calendarMode = _WorkspaceCalendarMode.month;

  void _showSnackSafe(String message) {
    if (!mounted) {
      return;
    }
    _showSnack(context, message);
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _logBuild, extra: {"planId": widget.planId});
    final detailAsync = ref.watch(productionPlanDetailProvider(widget.planId));
    final staffAsync = ref.watch(productionStaffProvider);
    final session = ref.watch(authSessionProvider);
    final actorRole = session?.user.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: _viewInsightsTooltip,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () {
              context.push(productionPlanInsightsPath(widget.planId));
            },
          ),
          IconButton(
            tooltip: _refreshTooltip,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(productionPlanDetailProvider(widget.planId));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final refreshed = ref.refresh(
            productionPlanDetailProvider(widget.planId).future,
          );
          await refreshed;
        },
        child: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(_pagePadding),
              child: Text(error.toString()),
            ),
          ),
          data: (detail) {
            final staffList =
                staffAsync.valueOrNull ?? <BusinessStaffProfileSummary>[];
            final staffMap = _buildStaffMap(staffList);
            final selfStaffRole = _resolveSelfStaffRole(
              staffList: staffList,
              userEmail: session?.user.email,
            );
            final canManageCalendar = _canManageCalendar(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canReviewProgress = _canReviewProgress(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canManageTaskAttendance = _canManageTaskAttendance(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final selectedDay = _selectedDay ?? _resolveInitialDay(detail.plan);
            final visibleMonth = _visibleMonth ?? _firstDayOfMonth(selectedDay);
            final planUnitLabelById = <String, String>{
              for (final unit
                  in (ref
                          .watch(productionPlanUnitsProvider(widget.planId))
                          .valueOrNull
                          ?.units ??
                      const <ProductionPlanUnit>[]))
                unit.id: unit.label,
            };
            final tasksForDay = _tasksForDay(detail.tasks, selectedDay);
            final rowsForDay = _rowsForDay(detail.timelineRows, selectedDay);
            final phaseById = {
              for (final phase in detail.phases) phase.id: phase,
            };
            void selectDay(DateTime next) {
              AppDebug.log(
                _logTag,
                _logDayChanged,
                extra: {"day": formatDateInput(next)},
              );
              setState(() {
                _selectedDay = next;
                _visibleMonth = _firstDayOfMonth(next);
              });
            }

            return ListView(
              padding: const EdgeInsets.all(_pagePadding),
              children: [
                _WorkspaceSummaryCard(
                  plan: detail.plan,
                  selectedDay: selectedDay,
                  scheduledTaskCount: tasksForDay.length,
                  onViewInsights: () {
                    context.push(productionPlanInsightsPath(widget.planId));
                  },
                ),
                const SizedBox(height: _sectionSpacing),
                const ProductionSectionHeader(
                  title: _workspaceTitle,
                  subtitle: _workspaceSubtitle,
                ),
                const SizedBox(height: _cardSpacing),
                _WorkspaceCalendarModeBar(
                  mode: _calendarMode,
                  onModeChanged: (mode) {
                    setState(() {
                      _calendarMode = mode;
                    });
                  },
                ),
                const SizedBox(height: _cardSpacing),
                switch (_calendarMode) {
                  _WorkspaceCalendarMode.day => const SizedBox.shrink(),
                  _WorkspaceCalendarMode.month => _MonthCalendarCard(
                    month: visibleMonth,
                    selectedDay: selectedDay,
                    plan: detail.plan,
                    tasks: detail.tasks,
                    timelineRows: detail.timelineRows,
                    onPreviousMonth: () {
                      final next = DateTime(
                        visibleMonth.year,
                        visibleMonth.month - 1,
                        1,
                      );
                      AppDebug.log(
                        _logTag,
                        _logMonthChanged,
                        extra: {"month": _monthTitle(next)},
                      );
                      setState(() {
                        _visibleMonth = next;
                      });
                    },
                    onNextMonth: () {
                      final next = DateTime(
                        visibleMonth.year,
                        visibleMonth.month + 1,
                        1,
                      );
                      AppDebug.log(
                        _logTag,
                        _logMonthChanged,
                        extra: {"month": _monthTitle(next)},
                      );
                      setState(() {
                        _visibleMonth = next;
                      });
                    },
                    onToday: () {
                      final next = _resolveInitialDay(detail.plan);
                      AppDebug.log(
                        _logTag,
                        _logDayChanged,
                        extra: {"day": formatDateInput(next)},
                      );
                      setState(() {
                        _selectedDay = next;
                        _visibleMonth = _firstDayOfMonth(next);
                      });
                    },
                    onSelectDay: (day) {
                      AppDebug.log(
                        _logTag,
                        _logDayChanged,
                        extra: {"day": formatDateInput(day)},
                      );
                      setState(() {
                        _selectedDay = day;
                        _visibleMonth = _firstDayOfMonth(day);
                      });
                    },
                  ),
                  _WorkspaceCalendarMode.year => _YearCalendarCard(
                    year: visibleMonth.year,
                    selectedDay: selectedDay,
                    tasks: detail.tasks,
                    onPreviousYear: () {
                      final next = DateTime(visibleMonth.year - 1, 1, 1);
                      AppDebug.log(
                        _logTag,
                        _logMonthChanged,
                        extra: {"month": _monthTitle(next)},
                      );
                      setState(() {
                        _visibleMonth = next;
                      });
                    },
                    onNextYear: () {
                      final next = DateTime(visibleMonth.year + 1, 1, 1);
                      AppDebug.log(
                        _logTag,
                        _logMonthChanged,
                        extra: {"month": _monthTitle(next)},
                      );
                      setState(() {
                        _visibleMonth = next;
                      });
                    },
                    onToday: () {
                      final next = _resolveInitialDay(detail.plan);
                      AppDebug.log(
                        _logTag,
                        _logDayChanged,
                        extra: {"day": formatDateInput(next)},
                      );
                      setState(() {
                        _selectedDay = next;
                        _visibleMonth = _firstDayOfMonth(next);
                      });
                    },
                    onSelectDay: (day) {
                      AppDebug.log(
                        _logTag,
                        _logDayChanged,
                        extra: {"day": formatDateInput(day)},
                      );
                      setState(() {
                        _selectedDay = day;
                        _visibleMonth = _firstDayOfMonth(day);
                        _calendarMode = _WorkspaceCalendarMode.month;
                      });
                    },
                  ),
                },
                if (_calendarMode != _WorkspaceCalendarMode.day)
                  const SizedBox(height: _sectionSpacing),
                _SelectedDaySectionHeader(
                  title: _selectedDayTitle,
                  subtitle: _formatSelectedDaySubtitle(
                    day: selectedDay,
                    taskCount: tasksForDay.length,
                    logCount: rowsForDay.length,
                  ),
                  showDayNavigation:
                      _calendarMode == _WorkspaceCalendarMode.day,
                  onPreviousDay: () {
                    selectDay(selectedDay.subtract(const Duration(days: 1)));
                  },
                  onToday: () {
                    selectDay(_resolveInitialDay(detail.plan));
                  },
                  onNextDay: () {
                    selectDay(selectedDay.add(const Duration(days: 1)));
                  },
                ),
                const SizedBox(height: _cardSpacing),
                _SelectedDayMetricsRow(tasks: tasksForDay, rows: rowsForDay),
                const SizedBox(height: _cardSpacing),
                if (tasksForDay.isEmpty)
                  const ProductionEmptyState(
                    title: _selectedDayEmptyTitle,
                    message: _selectedDayEmptyMessage,
                  )
                else
                  ...tasksForDay.map((task) {
                    final rowsForTask = rowsForDay
                        .where((row) => row.taskId == task.id)
                        .toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: _cardSpacing),
                      child: _AgendaTaskCard(
                        task: task,
                        phaseName:
                            phaseById[task.phaseId]?.name ?? task.phaseId,
                        staffMap: staffMap,
                        planUnitLabelById: planUnitLabelById,
                        selectedDay: selectedDay,
                        attendanceRecords: detail.attendanceRecords,
                        rowsForDay: rowsForTask,
                        canManageCalendar: canManageCalendar,
                        canManageTaskAttendance: canManageTaskAttendance,
                        canReviewProgress: canReviewProgress,
                        isOwner: actorRole == "business_owner",
                        onManageStaff: canManageCalendar
                            ? () async {
                                final selectedIds =
                                    await _showTaskAssignmentDialog(
                                      context,
                                      task: task,
                                      staffList: staffList,
                                      staffMap: staffMap,
                                    );
                                if (selectedIds == null) {
                                  return;
                                }
                                AppDebug.log(
                                  _logTag,
                                  _logAssignStaff,
                                  extra: {
                                    "planId": widget.planId,
                                    "taskId": task.id,
                                    "assignedCount": selectedIds.length,
                                  },
                                );
                                try {
                                  await ref
                                      .read(productionPlanActionsProvider)
                                      .assignTaskStaffProfiles(
                                        taskId: task.id,
                                        planId: widget.planId,
                                        assignedStaffProfileIds: selectedIds,
                                      );
                                  _showSnackSafe(_taskAssignmentSuccess);
                                } catch (_) {
                                  _showSnackSafe(_taskAssignmentFailure);
                                }
                              }
                            : null,
                        onSetAttendanceForStaff: canManageTaskAttendance
                            ? (staffProfileId, existingAttendance) async {
                                final staffLabel = _resolveStaffDisplayName(
                                  staffProfileId,
                                  staffMap,
                                );
                                final input = await _showAttendanceDialog(
                                  context,
                                  staffLabel: staffLabel,
                                  taskTitle: task.title,
                                  workDate: selectedDay,
                                  existingAttendance: existingAttendance,
                                );
                                if (input == null) {
                                  return;
                                }
                                try {
                                  final attendanceActions =
                                      StaffAttendanceActions(ref);
                                  final note =
                                      "Updated from production workspace";
                                  StaffAttendanceRecord attendanceRecord;
                                  final existingClockInAt = existingAttendance
                                      ?.clockInAt
                                      ?.toLocal();
                                  final existingClockOutAt = existingAttendance
                                      ?.clockOutAt
                                      ?.toLocal();
                                  final shouldSetClockOutFirst =
                                      existingAttendance != null &&
                                      input.clockOutAt != null &&
                                      existingClockOutAt != null &&
                                      input.clockInAt.isAfter(
                                        existingClockOutAt,
                                      ) &&
                                      !(existingClockInAt != null &&
                                          input.clockOutAt!.isBefore(
                                            existingClockInAt,
                                          ));
                                  if (shouldSetClockOutFirst) {
                                    final updatedClockOut =
                                        await attendanceActions.clockOut(
                                          staffProfileId: staffProfileId,
                                          attendanceId: existingAttendance.id,
                                          clockOutAt: input.clockOutAt,
                                          workDate: selectedDay,
                                          planId: widget.planId,
                                          taskId: task.id,
                                          notes: note,
                                        );
                                    attendanceRecord = await attendanceActions
                                        .clockIn(
                                          staffProfileId: staffProfileId,
                                          attendanceId: updatedClockOut.id,
                                          clockInAt: input.clockInAt,
                                          workDate: selectedDay,
                                          planId: widget.planId,
                                          taskId: task.id,
                                          notes: note,
                                        );
                                  } else {
                                    attendanceRecord = await attendanceActions
                                        .clockIn(
                                          staffProfileId: staffProfileId,
                                          attendanceId: existingAttendance?.id,
                                          clockInAt: input.clockInAt,
                                          workDate: selectedDay,
                                          planId: widget.planId,
                                          taskId: task.id,
                                          notes: note,
                                        );
                                    if (input.clockOutAt != null) {
                                      await attendanceActions.clockOut(
                                        staffProfileId: staffProfileId,
                                        attendanceId: attendanceRecord.id,
                                        clockOutAt: input.clockOutAt,
                                        workDate: selectedDay,
                                        planId: widget.planId,
                                        taskId: task.id,
                                        notes: note,
                                      );
                                    }
                                  }
                                  ref.invalidate(
                                    productionPlanDetailProvider(widget.planId),
                                  );
                                  _showSnackSafe(_attendanceUpdateSuccess);
                                } catch (_) {
                                  _showSnackSafe(_attendanceUpdateFailure);
                                }
                              }
                            : null,
                        onStatusSelected: canManageCalendar
                            ? (status) async {
                                if (status == task.status) {
                                  return;
                                }
                                AppDebug.log(
                                  _logTag,
                                  _logTaskStatus,
                                  extra: {
                                    "planId": widget.planId,
                                    "taskId": task.id,
                                    "status": status,
                                  },
                                );
                                try {
                                  await ref
                                      .read(productionPlanActionsProvider)
                                      .updateTaskStatus(
                                        taskId: task.id,
                                        status: status,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_taskStatusSuccess);
                                } catch (_) {
                                  _showSnackSafe(_taskStatusFailure);
                                }
                              }
                            : null,
                        onLogProgress: canManageCalendar
                            ? () async {
                                final input = await _showWorkspaceLogDialog(
                                  context,
                                  workDate: selectedDay,
                                  task: task,
                                  timelineRows: detail.timelineRows,
                                  staffMap: staffMap,
                                  planUnitLabelById: planUnitLabelById,
                                );
                                if (input == null) {
                                  return;
                                }
                                AppDebug.log(
                                  _logTag,
                                  _logProgress,
                                  extra: {
                                    "planId": widget.planId,
                                    "taskId": task.id,
                                  },
                                );
                                try {
                                  await ref
                                      .read(productionPlanActionsProvider)
                                      .logTaskProgress(
                                        taskId: task.id,
                                        workDate: selectedDay,
                                        staffId: input.staffId,
                                        unitId: input.unitId,
                                        actualPlots: input.actualPlots,
                                        delayReason: input.delayReason,
                                        notes: input.notes,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_taskProgressSuccess);
                                } catch (_) {
                                  _showSnackSafe(_taskProgressFailure);
                                }
                              }
                            : null,
                        onApproveTask:
                            actorRole == "business_owner" &&
                                task.approvalStatus == "pending_approval"
                            ? () async {
                                AppDebug.log(
                                  _logTag,
                                  _logApproveTask,
                                  extra: {
                                    "planId": widget.planId,
                                    "taskId": task.id,
                                  },
                                );
                                try {
                                  await ref
                                      .read(productionPlanActionsProvider)
                                      .approveTask(
                                        taskId: task.id,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_approveTaskSuccess);
                                } catch (_) {
                                  _showSnackSafe(_approveTaskFailure);
                                }
                              }
                            : null,
                        onRejectTask:
                            actorRole == "business_owner" &&
                                task.approvalStatus == "pending_approval"
                            ? () async {
                                final reason = await _showReasonDialog(
                                  context,
                                  title: _rejectDialogTitle,
                                  hint: _rejectDialogHint,
                                );
                                if (reason == null) {
                                  return;
                                }
                                AppDebug.log(
                                  _logTag,
                                  _logRejectTask,
                                  extra: {
                                    "planId": widget.planId,
                                    "taskId": task.id,
                                  },
                                );
                                try {
                                  await ref
                                      .read(productionPlanActionsProvider)
                                      .rejectTask(
                                        taskId: task.id,
                                        reason: reason,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_rejectTaskSuccess);
                                } catch (_) {
                                  _showSnackSafe(_rejectTaskFailure);
                                }
                              }
                            : null,
                        onApproveProgress: canReviewProgress
                            ? (progressId) async {
                                AppDebug.log(
                                  _logTag,
                                  _logApproveProgress,
                                  extra: {
                                    "planId": widget.planId,
                                    "progressId": progressId,
                                  },
                                );
                                try {
                                  await ref
                                      .read(productionPlanActionsProvider)
                                      .approveTaskProgress(
                                        progressId: progressId,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_approveProgressSuccess);
                                } catch (_) {
                                  _showSnackSafe(_approveProgressFailure);
                                }
                              }
                            : null,
                        onRejectProgress: canReviewProgress
                            ? (progressId) async {
                                final reason = await _showReasonDialog(
                                  context,
                                  title: _rejectProgressDialogTitle,
                                  hint: _rejectDialogHint,
                                );
                                if (reason == null) {
                                  return;
                                }
                                AppDebug.log(
                                  _logTag,
                                  _logRejectProgress,
                                  extra: {
                                    "planId": widget.planId,
                                    "progressId": progressId,
                                  },
                                );
                                try {
                                  await ref
                                      .read(productionPlanActionsProvider)
                                      .rejectTaskProgress(
                                        progressId: progressId,
                                        reason: reason,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_rejectProgressSuccess);
                                } catch (_) {
                                  _showSnackSafe(_rejectProgressFailure);
                                }
                              }
                            : null,
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceSummaryCard extends StatelessWidget {
  final ProductionPlan plan;
  final DateTime selectedDay;
  final int scheduledTaskCount;
  final VoidCallback onViewInsights;

  const _WorkspaceSummaryCard({
    required this.plan,
    required this.selectedDay,
    required this.scheduledTaskCount,
    required this.onViewInsights,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDisplayDateRange(plan.startDate, plan.endDate),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ProductionStatusPill(label: plan.status),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryPill(
                icon: Icons.today_outlined,
                label: "Selected ${_formatCalendarDate(selectedDay)}",
              ),
              _SummaryPill(
                icon: Icons.event_note_outlined,
                label: "$scheduledTaskCount scheduled tasks",
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  "Keep this screen operational. Use the insights screen for KPIs, governance, and long-form reporting.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onViewInsights,
                icon: const Icon(Icons.insights_outlined),
                label: const Text(_viewInsightsLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _WorkspaceCalendarModeBar extends StatelessWidget {
  final _WorkspaceCalendarMode mode;
  final ValueChanged<_WorkspaceCalendarMode> onModeChanged;

  const _WorkspaceCalendarModeBar({
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_WorkspaceCalendarMode>(
      segments: const [
        ButtonSegment<_WorkspaceCalendarMode>(
          value: _WorkspaceCalendarMode.day,
          label: Text("Day"),
          icon: Icon(Icons.today_outlined),
        ),
        ButtonSegment<_WorkspaceCalendarMode>(
          value: _WorkspaceCalendarMode.month,
          label: Text("Month"),
          icon: Icon(Icons.calendar_view_month_outlined),
        ),
        ButtonSegment<_WorkspaceCalendarMode>(
          value: _WorkspaceCalendarMode.year,
          label: Text("Year"),
          icon: Icon(Icons.grid_view_outlined),
        ),
      ],
      showSelectedIcon: false,
      selected: <_WorkspaceCalendarMode>{mode},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) {
          return;
        }
        onModeChanged(selection.first);
      },
    );
  }
}

class _SelectedDaySectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showDayNavigation;
  final VoidCallback onPreviousDay;
  final VoidCallback onToday;
  final VoidCallback onNextDay;

  const _SelectedDaySectionHeader({
    required this.title,
    required this.subtitle,
    required this.showDayNavigation,
    required this.onPreviousDay,
    required this.onToday,
    required this.onNextDay,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!showDayNavigation) {
      return ProductionSectionHeader(title: title, subtitle: subtitle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              onPressed: onPreviousDay,
              icon: const Icon(Icons.chevron_left),
            ),
            TextButton(onPressed: onToday, child: const Text(_todayLabel)),
            IconButton(
              onPressed: onNextDay,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

class _MonthCalendarCard extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final ProductionPlan plan;
  final List<ProductionTask> tasks;
  final List<ProductionTimelineRow> timelineRows;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelectDay;

  const _MonthCalendarCard({
    required this.month,
    required this.selectedDay,
    required this.plan,
    required this.tasks,
    required this.timelineRows,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final monthDays = _buildMonthGridDays(month);
    final monthTasks = tasks.where((task) {
      return _taskTouchesMonth(task: task, month: month);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _monthTitle(month),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(onPressed: onToday, child: const Text(_todayLabel)),
              IconButton(
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _MonthWeekdayHeader(),
          const SizedBox(height: 8),
          if (monthTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: ProductionEmptyState(
                title: _monthEmptyTitle,
                message: _monthEmptyMessage,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final usableWidth =
                    constraints.maxWidth - (_calendarSpacing * 6);
                final cellWidth = usableWidth / 7;
                final compact = cellWidth < 128;
                final showPreview = cellWidth >= 136;
                final cellHeight = compact
                    ? (cellWidth * 1.18).clamp(88.0, 112.0)
                    : (cellWidth * 1.16).clamp(108.0, 138.0);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: monthDays.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: _calendarSpacing,
                    crossAxisSpacing: _calendarSpacing,
                    mainAxisExtent: cellHeight,
                  ),
                  itemBuilder: (context, index) {
                    final day = monthDays[index];
                    if (day == null) {
                      return const SizedBox.shrink();
                    }
                    final dayTasks = _tasksForDay(tasks, day);
                    final dayRows = _rowsForDay(timelineRows, day);
                    final inPlanRange = _isWithinPlanRange(day, plan);
                    return _MonthDayTile(
                      day: day,
                      selected: _isSameDay(day, selectedDay),
                      inPlanRange: inPlanRange,
                      tasks: dayTasks,
                      rows: dayRows,
                      compact: compact,
                      showPreview: showPreview,
                      onTap: () => onSelectDay(day),
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

class _MonthWeekdayHeader extends StatelessWidget {
  const _MonthWeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: _weekdayLabels
          .map(
            (label) => Expanded(
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _YearCalendarCard extends StatelessWidget {
  final int year;
  final DateTime selectedDay;
  final List<ProductionTask> tasks;
  final VoidCallback onPreviousYear;
  final VoidCallback onNextYear;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelectDay;

  const _YearCalendarCard({
    required this.year,
    required this.selectedDay,
    required this.tasks,
    required this.onPreviousYear,
    required this.onNextYear,
    required this.onToday,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "$year",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onPreviousYear,
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(onPressed: onToday, child: const Text(_todayLabel)),
              IconButton(
                onPressed: onNextYear,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 1180
                  ? 4
                  : constraints.maxWidth >= 760
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 12,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: _calendarSpacing,
                  mainAxisSpacing: _calendarSpacing,
                  childAspectRatio: 1.05,
                ),
                itemBuilder: (context, index) {
                  final month = DateTime(year, index + 1, 1);
                  return _MiniMonthCard(
                    month: month,
                    selectedDay: selectedDay,
                    tasks: tasks,
                    onSelectDay: onSelectDay,
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

class _MiniMonthCard extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final List<ProductionTask> tasks;
  final ValueChanged<DateTime> onSelectDay;

  const _MiniMonthCard({
    required this.month,
    required this.selectedDay,
    required this.tasks,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final days = _buildMonthGridDays(month);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _monthName(month.month),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _weekdayLabels
                .map(
                  (label) => Expanded(
                    child: Text(
                      label.substring(0, 1),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemBuilder: (context, index) {
                final day = days[index];
                if (day == null) {
                  return const SizedBox.shrink();
                }
                final isSelected = _isSameDay(day, selectedDay);
                final dayTasks = _tasksForDay(tasks, day);
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelectDay(day),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : dayTasks.isNotEmpty
                          ? colorScheme.surfaceContainerHighest
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${day.day}",
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: dayTasks.isNotEmpty
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthDayTile extends StatelessWidget {
  final DateTime day;
  final bool selected;
  final bool inPlanRange;
  final List<ProductionTask> tasks;
  final List<ProductionTimelineRow> rows;
  final bool compact;
  final bool showPreview;
  final VoidCallback onTap;

  const _MonthDayTile({
    required this.day,
    required this.selected,
    required this.inPlanRange,
    required this.tasks,
    required this.rows,
    required this.compact,
    required this.showPreview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final completed = tasks
        .where((task) => task.status == _taskStatusDone)
        .length;
    final background = selected
        ? colorScheme.primaryContainer
        : inPlanRange
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surface;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final previewTaskTitle = tasks.isNotEmpty ? tasks.first.title : null;
    final taskSummary = tasks.length == 1 ? '1 task' : '${tasks.length} tasks';
    final doneSummary = completed == 1 ? '1 done' : '$completed done';
    final tilePadding = compact ? 8.0 : _dayTilePadding;
    final titleStyle = compact
        ? theme.textTheme.titleSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          )
        : theme.textTheme.titleSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          );
    final summaryStyle =
        (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(
              color: foreground.withValues(alpha: 0.88),
              fontWeight: FontWeight.w700,
            );
    final doneStyle = theme.textTheme.labelSmall?.copyWith(
      color: foreground.withValues(alpha: compact ? 0.72 : 0.76),
      fontWeight: compact ? FontWeight.w600 : FontWeight.w500,
    );
    final previewStyle = theme.textTheme.bodySmall?.copyWith(
      color: foreground.withValues(alpha: 0.88),
      height: 1.15,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(_dayTileRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(tilePadding),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(_dayTileRadius),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Opacity(
          opacity: inPlanRange ? 1 : 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text("${day.day}", style: titleStyle),
                  const Spacer(),
                  if (rows.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        "${rows.length}",
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: selected
                              ? colorScheme.onPrimary
                              : colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: compact ? 4 : 8),
              Text(
                taskSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: summaryStyle,
              ),
              if (tasks.isNotEmpty) ...[
                SizedBox(height: compact ? 2 : 6),
                Text(
                  doneSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: doneStyle,
                ),
              ],
              if (showPreview && previewTaskTitle != null) ...[
                const Spacer(),
                Text(
                  previewTaskTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: previewStyle,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedDayMetricsRow extends StatelessWidget {
  final List<ProductionTask> tasks;
  final List<ProductionTimelineRow> rows;

  const _SelectedDayMetricsRow({required this.tasks, required this.rows});

  @override
  Widget build(BuildContext context) {
    final assignedCount = tasks.fold<int>(
      0,
      (sum, task) => sum + _resolveAssignedStaffIds(task).length,
    );
    final doneCount = tasks
        .where((task) => task.status == _taskStatusDone)
        .length;
    return Wrap(
      spacing: _cardSpacing,
      runSpacing: _cardSpacing,
      children: [
        ProductionKpiCard(
          label: _daySummaryTasksLabel,
          value: "${tasks.length}",
        ),
        ProductionKpiCard(
          label: _daySummaryAssignedLabel,
          value: "$assignedCount",
        ),
        ProductionKpiCard(
          label: _daySummaryLoggedLabel,
          value: "${rows.length}",
        ),
        ProductionKpiCard(label: _daySummaryDoneLabel, value: "$doneCount"),
      ],
    );
  }
}

class _AgendaTaskCard extends StatelessWidget {
  final ProductionTask task;
  final String phaseName;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final Map<String, String> planUnitLabelById;
  final DateTime selectedDay;
  final List<ProductionAttendanceRecord> attendanceRecords;
  final List<ProductionTimelineRow> rowsForDay;
  final bool canManageCalendar;
  final bool canManageTaskAttendance;
  final bool canReviewProgress;
  final bool isOwner;
  final Future<void> Function()? onManageStaff;
  final Future<void> Function(
    String staffProfileId,
    ProductionAttendanceRecord? attendance,
  )?
  onSetAttendanceForStaff;
  final Future<void> Function(String status)? onStatusSelected;
  final Future<void> Function()? onLogProgress;
  final Future<void> Function()? onApproveTask;
  final Future<void> Function()? onRejectTask;
  final Future<void> Function(String progressId)? onApproveProgress;
  final Future<void> Function(String progressId)? onRejectProgress;

  const _AgendaTaskCard({
    required this.task,
    required this.phaseName,
    required this.staffMap,
    required this.planUnitLabelById,
    required this.selectedDay,
    required this.attendanceRecords,
    required this.rowsForDay,
    required this.canManageCalendar,
    required this.canManageTaskAttendance,
    required this.canReviewProgress,
    required this.isOwner,
    required this.onManageStaff,
    required this.onSetAttendanceForStaff,
    required this.onStatusSelected,
    required this.onLogProgress,
    required this.onApproveTask,
    required this.onRejectTask,
    required this.onApproveProgress,
    required this.onRejectProgress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final assignedStaffIds = _resolveAssignedStaffIds(task);
    final assignedUnitsLabel = _buildAssignedUnitLabel(
      assignedUnitIds: task.assignedUnitIds,
      planUnitLabelById: planUnitLabelById,
    );
    final actualTotal = rowsForDay.fold<num>(
      0,
      (sum, row) => sum + row.actualPlots,
    );
    final expectedTotal = rowsForDay.fold<num>(
      0,
      (sum, row) => sum + row.expectedPlots,
    );

    return Container(
      padding: const EdgeInsets.all(_agendaCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phaseName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ProductionStatusPill(label: task.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                label:
                    "$_scheduleLabel: ${_formatTaskWindow(task.startDate, task.dueDate)}",
              ),
              _InfoChip(
                label:
                    "$_roleLabel: ${formatStaffRoleLabel(task.roleRequired, fallback: task.roleRequired)} x${task.requiredHeadcount}",
              ),
              _InfoChip(label: "$_assignedLabel: ${assignedStaffIds.length}"),
              if (assignedUnitsLabel != "-")
                _InfoChip(label: "$_unitsLabel: $assignedUnitsLabel"),
              _InfoChip(label: "$_logsLabel: ${rowsForDay.length}"),
              if (rowsForDay.isNotEmpty)
                _InfoChip(
                  label: "$_actualLabel: $actualTotal / $expectedTotal",
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _assignedLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (assignedStaffIds.isEmpty)
            Text(
              _unassignedLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(
              children: assignedStaffIds.map((staffId) {
                final attendance = _attendanceForStaffOnDay(
                  attendanceRecords: attendanceRecords,
                  staffProfileId: staffId,
                  day: selectedDay,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AssignedStaffAttendanceRow(
                    staffLabel: _resolveStaffDisplayName(staffId, staffMap),
                    estimatedWindow: _formatTaskWindow(
                      task.startDate,
                      task.dueDate,
                    ),
                    actualWindow: _formatAttendanceWindow(attendance),
                    hasClockIn: attendance?.clockInAt != null,
                    hasClockOut: attendance?.clockOutAt != null,
                    canManageAttendance: canManageTaskAttendance,
                    onSetAttendance: onSetAttendanceForStaff == null
                        ? null
                        : () => onSetAttendanceForStaff!(staffId, attendance),
                  ),
                );
              }).toList(),
            ),
          if (task.instructions.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _instructionsLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(task.instructions),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canManageCalendar)
                OutlinedButton.icon(
                  onPressed: onManageStaff,
                  icon: const Icon(Icons.group_outlined),
                  label: const Text(_assignStaffLabel),
                ),
              if (canManageCalendar)
                OutlinedButton.icon(
                  onPressed: onLogProgress,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text(_logProgressLabel),
                ),
              if (canManageCalendar)
                PopupMenuButton<String>(
                  onSelected: onStatusSelected,
                  itemBuilder: (context) => _taskStatusOptions
                      .map(
                        (status) => PopupMenuItem<String>(
                          value: status,
                          child: Text(formatProductionStatusLabel(status)),
                        ),
                      )
                      .toList(),
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(formatProductionStatusLabel(task.status)),
                  ),
                ),
              if (isOwner && task.approvalStatus == "pending_approval")
                FilledButton.tonal(
                  onPressed: onApproveTask,
                  child: const Text(_taskApproveLabel),
                ),
              if (isOwner && task.approvalStatus == "pending_approval")
                TextButton(
                  onPressed: onRejectTask,
                  child: const Text(_taskRejectLabel),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _activityLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (rowsForDay.isEmpty)
            Text(
              _noActivityLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...rowsForDay.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TimelineLogRow(
                  row: row,
                  canReviewProgress: canReviewProgress,
                  onApprove: onApproveProgress == null
                      ? null
                      : () => onApproveProgress!(row.id),
                  onReject: onRejectProgress == null
                      ? null
                      : () => onRejectProgress!(row.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _AssignedStaffAttendanceRow extends StatelessWidget {
  final String staffLabel;
  final String estimatedWindow;
  final String actualWindow;
  final bool hasClockIn;
  final bool hasClockOut;
  final bool canManageAttendance;
  final Future<void> Function()? onSetAttendance;

  const _AssignedStaffAttendanceRow({
    required this.staffLabel,
    required this.estimatedWindow,
    required this.actualWindow,
    required this.hasClockIn,
    required this.hasClockOut,
    required this.canManageAttendance,
    required this.onSetAttendance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  staffLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canManageAttendance)
                TextButton(
                  onPressed: onSetAttendance,
                  child: Text(
                    hasClockIn || hasClockOut
                        ? _editAttendanceLabel
                        : _setAttendanceLabel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "$_estimatedDatesLabel: $estimatedWindow",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "$_actualTodayLabel: $actualWindow",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasClockIn || hasClockOut) ...[
            const SizedBox(height: 6),
            Text(
              hasClockIn && hasClockOut
                  ? _attendanceReadyForProgressHint
                  : _attendanceShiftOpenHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineLogRow extends StatelessWidget {
  final ProductionTimelineRow row;
  final bool canReviewProgress;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _TimelineLogRow({
    required this.row,
    required this.canReviewProgress,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                label: row.farmerName.isEmpty
                    ? _unassignedLabel
                    : row.farmerName,
              ),
              _InfoChip(label: "$_expectedLabel: ${row.expectedPlots}"),
              _InfoChip(label: "$_actualLabel: ${row.actualPlots}"),
              _InfoChip(
                label:
                    "$_approvalLabel: ${_formatProgressApproval(row.approvalState)}",
              ),
            ],
          ),
          if (row.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              row.notes,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (canReviewProgress &&
              (row.approvalState == "pending_approval" ||
                  row.approvalState == "needs_review")) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: onApprove,
                  child: const Text(_progressApproveLabel),
                ),
                TextButton(
                  onPressed: onReject,
                  child: const Text(_progressRejectLabel),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceLogProgressInput {
  final String? staffId;
  final String? unitId;
  final num actualPlots;
  final String delayReason;
  final String notes;

  const _WorkspaceLogProgressInput({
    required this.staffId,
    required this.unitId,
    required this.actualPlots,
    required this.delayReason,
    required this.notes,
  });
}

class _AttendanceEditInput {
  final DateTime clockInAt;
  final DateTime? clockOutAt;

  const _AttendanceEditInput({
    required this.clockInAt,
    required this.clockOutAt,
  });
}

String _formatSelectedDaySubtitle({
  required DateTime day,
  required int taskCount,
  required int logCount,
}) {
  return "${_formatCalendarDate(day)} • $taskCount tasks • $logCount logs";
}

String _formatDisplayDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) {
    return kDateFallbackLabel;
  }
  if (start != null && end != null) {
    return "${_formatShortCalendarDate(start)} - ${_formatShortCalendarDate(end)}";
  }
  return _formatShortCalendarDate(start ?? end!);
}

String _formatCalendarDate(DateTime value) {
  return "${_weekdayName(value.weekday)}, ${value.day} ${_monthName(value.month)} ${value.year}";
}

String _formatShortCalendarDate(DateTime value) {
  return "${value.day} ${_monthShortName(value.month)} ${value.year}";
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
  return names[month - 1];
}

String _monthShortName(int month) {
  const names = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  return names[month - 1];
}

String _weekdayName(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return "Monday";
    case DateTime.tuesday:
      return "Tuesday";
    case DateTime.wednesday:
      return "Wednesday";
    case DateTime.thursday:
      return "Thursday";
    case DateTime.friday:
      return "Friday";
    case DateTime.saturday:
      return "Saturday";
    case DateTime.sunday:
      return "Sunday";
    default:
      return "";
  }
}

String _monthTitle(DateTime value) {
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
  return "${names[value.month - 1]} ${value.year}";
}

DateTime _firstDayOfMonth(DateTime value) {
  return DateTime(value.year, value.month, 1);
}

DateTime _resolveInitialDay(ProductionPlan plan) {
  final normalizedToday = _toDayStart(DateTime.now());
  var planStart = plan.startDate != null
      ? _toDayStart(plan.startDate!)
      : normalizedToday;
  var planEnd = plan.endDate != null ? _toDayStart(plan.endDate!) : planStart;
  if (planEnd.isBefore(planStart)) {
    final swap = planStart;
    planStart = planEnd;
    planEnd = swap;
  }
  if (!normalizedToday.isBefore(planStart) &&
      !normalizedToday.isAfter(planEnd)) {
    return normalizedToday;
  }
  return planStart;
}

List<DateTime?> _buildMonthGridDays(DateTime month) {
  final firstDay = DateTime(month.year, month.month, 1);
  final lastDay = DateTime(month.year, month.month + 1, 0);
  final leadingEmpty = firstDay.weekday - DateTime.monday;
  final trailingEmpty = DateTime.sunday - lastDay.weekday;
  final cells = <DateTime?>[];
  for (var i = 0; i < leadingEmpty; i += 1) {
    cells.add(null);
  }
  for (var day = 1; day <= lastDay.day; day += 1) {
    cells.add(DateTime(month.year, month.month, day));
  }
  for (var i = 0; i < trailingEmpty; i += 1) {
    cells.add(null);
  }
  return cells;
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _isWithinPlanRange(DateTime day, ProductionPlan plan) {
  final normalized = _toDayStart(day);
  var planStart = plan.startDate != null
      ? _toDayStart(plan.startDate!)
      : normalized;
  var planEnd = plan.endDate != null ? _toDayStart(plan.endDate!) : planStart;
  if (planEnd.isBefore(planStart)) {
    final swap = planStart;
    planStart = planEnd;
    planEnd = swap;
  }
  return !normalized.isBefore(planStart) && !normalized.isAfter(planEnd);
}

bool _taskTouchesMonth({
  required ProductionTask task,
  required DateTime month,
}) {
  final monthStart = DateTime(month.year, month.month, 1);
  final nextMonthStart = DateTime(month.year, month.month + 1, 1);
  final taskStart = task.startDate != null
      ? _toDayStart(task.startDate!)
      : monthStart;
  final taskEnd = task.dueDate != null ? _toDayStart(task.dueDate!) : taskStart;
  return !taskEnd.isBefore(monthStart) && taskStart.isBefore(nextMonthStart);
}

List<ProductionTask> _tasksForDay(List<ProductionTask> tasks, DateTime day) {
  final items = tasks.where((task) {
    return _isTaskScheduledForDate(task: task, workDate: day);
  }).toList();
  items.sort((left, right) {
    final leftStart = left.startDate ?? left.dueDate ?? day;
    final rightStart = right.startDate ?? right.dueDate ?? day;
    return leftStart.compareTo(rightStart);
  });
  return items;
}

List<ProductionTimelineRow> _rowsForDay(
  List<ProductionTimelineRow> rows,
  DateTime day,
) {
  final key = _toWorkDateKey(day);
  final items = rows
      .where((row) => _toWorkDateKey(row.workDate) == key)
      .toList();
  items.sort((left, right) => left.taskTitle.compareTo(right.taskTitle));
  return items;
}

ProductionAttendanceRecord? _attendanceForStaffOnDay({
  required List<ProductionAttendanceRecord> attendanceRecords,
  required String staffProfileId,
  required DateTime day,
}) {
  final key = _toWorkDateKey(day);
  final items = attendanceRecords.where((record) {
    if (record.staffProfileId.trim() != staffProfileId.trim()) {
      return false;
    }
    final referenceTime = record.clockInAt ?? record.createdAt;
    if (referenceTime == null) {
      return false;
    }
    return _toWorkDateKey(referenceTime.toLocal()) == key;
  }).toList();
  if (items.isEmpty) {
    return null;
  }
  items.sort((left, right) {
    final leftValue = (left.clockInAt ?? left.createdAt ?? day).toLocal();
    final rightValue = (right.clockInAt ?? right.createdAt ?? day).toLocal();
    return leftValue.compareTo(rightValue);
  });
  return items.first;
}

Map<String, BusinessStaffProfileSummary> _buildStaffMap(
  List<BusinessStaffProfileSummary> staff,
) {
  return {for (final member in staff) member.id: member};
}

String? _resolveSelfStaffRole({
  required List<BusinessStaffProfileSummary> staffList,
  required String? userEmail,
}) {
  if (userEmail == null) {
    return null;
  }
  final normalizedEmail = userEmail.toLowerCase().trim();
  if (normalizedEmail.isEmpty) {
    return null;
  }
  for (final profile in staffList) {
    final profileEmail = (profile.userEmail ?? "").toLowerCase().trim();
    if (profileEmail.isNotEmpty && profileEmail == normalizedEmail) {
      return profile.staffRole;
    }
  }
  return null;
}

bool _canReviewProgress({
  required String? actorRole,
  required String? staffRole,
}) {
  if (actorRole == "business_owner") {
    return true;
  }
  return actorRole == "staff" && staffRole == staffRoleEstateManager;
}

bool _canManageTaskAttendance({
  required String? actorRole,
  required String? staffRole,
}) {
  if (actorRole == "business_owner") {
    return true;
  }
  return actorRole == "staff" &&
      (staffRole == staffRoleEstateManager ||
          staffRole == staffRoleFarmManager);
}

bool _canManageCalendar({
  required String? actorRole,
  required String? staffRole,
}) {
  if (actorRole == "business_owner") {
    return true;
  }
  return actorRole == "staff" &&
      (staffRole == staffRoleEstateManager ||
          staffRole == staffRoleFarmManager ||
          staffRole == staffRoleAssetManager);
}

DateTime _toDayStart(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

bool _isTaskScheduledForDate({
  required ProductionTask task,
  required DateTime workDate,
}) {
  final normalizedWorkDate = _toDayStart(workDate);
  final startDate = task.startDate;
  final dueDate = task.dueDate;
  if (startDate == null && dueDate == null) {
    return true;
  }
  if (startDate != null &&
      normalizedWorkDate.isBefore(_toDayStart(startDate))) {
    return false;
  }
  if (dueDate != null && normalizedWorkDate.isAfter(_toDayStart(dueDate))) {
    return false;
  }
  return true;
}

String _toWorkDateKey(DateTime? date) {
  if (date == null) {
    return "";
  }
  final year = date.year.toString().padLeft(4, "0");
  final month = date.month.toString().padLeft(2, "0");
  final day = date.day.toString().padLeft(2, "0");
  return "$year-$month-$day";
}

List<String> _resolveAssignedStaffIds(ProductionTask task) {
  final ids = task.assignedStaffIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  if (ids.isNotEmpty) {
    return ids;
  }
  final fallback = task.assignedStaffId.trim();
  if (fallback.isEmpty) {
    return <String>[];
  }
  return <String>[fallback];
}

String _resolveStaffDisplayName(
  String staffId,
  Map<String, BusinessStaffProfileSummary> staffMap,
) {
  return staffMap[staffId]?.userName ?? staffMap[staffId]?.userEmail ?? staffId;
}

String _buildAssignedUnitLabel({
  required List<String> assignedUnitIds,
  required Map<String, String> planUnitLabelById,
}) {
  if (assignedUnitIds.isEmpty) {
    return "-";
  }
  final labels = assignedUnitIds
      .map((unitId) {
        final normalized = unitId.trim();
        if (normalized.isEmpty) {
          return "";
        }
        return planUnitLabelById[normalized] ?? normalized;
      })
      .where((label) => label.isNotEmpty)
      .toList();
  if (labels.isEmpty) {
    return "-";
  }
  return labels.join(", ");
}

num _resolveTaskProgressTargetAmount({
  required ProductionTask task,
  required List<String> assignedUnitIds,
}) {
  if (task.weight > 0) {
    return task.weight.toDouble();
  }
  if (assignedUnitIds.isNotEmpty) {
    return assignedUnitIds.length.toDouble();
  }
  if (task.requiredHeadcount > 0) {
    return task.requiredHeadcount.toDouble();
  }
  return 10.0;
}

String _formatProgressAmount(num value) {
  final normalized = value.toDouble();
  if ((normalized - normalized.roundToDouble()).abs() < 0.001) {
    return normalized.round().toString();
  }
  if (((normalized * 10) - (normalized * 10).roundToDouble()).abs() < 0.001) {
    return normalized.toStringAsFixed(1);
  }
  return normalized.toStringAsFixed(2);
}

bool _sameProgressAmount(num left, num right) {
  return (left.toDouble() - right.toDouble()).abs() < 0.001;
}

List<num> _buildProgressAmountOptions({required num maxAmount}) {
  final normalizedMax = maxAmount <= 0 ? 0.0 : maxAmount.toDouble();
  final halfSteps = (normalizedMax * 2).floor();
  final values = List<num>.generate(halfSteps + 1, (index) => index / 2);
  if (values.isEmpty) {
    return <num>[0];
  }
  if (!_sameProgressAmount(values.last, normalizedMax)) {
    values.add(normalizedMax);
  }
  return values;
}

ProductionTimelineRow? _findExistingProgressRowForSelection({
  required List<ProductionTimelineRow> timelineRows,
  required String taskId,
  required DateTime workDate,
  required String? staffId,
  required String? unitId,
}) {
  final normalizedTaskId = taskId.trim();
  final normalizedStaffId = staffId?.trim() ?? "";
  final normalizedUnitId = unitId?.trim() ?? "";
  final workDateKey = _toWorkDateKey(workDate);
  final matches = timelineRows.where((row) {
    return row.taskId.trim() == normalizedTaskId &&
        _toWorkDateKey(row.workDate) == workDateKey &&
        row.staffId.trim() == normalizedStaffId &&
        row.unitId.trim() == normalizedUnitId;
  }).toList();
  if (matches.isEmpty) {
    return null;
  }
  matches.sort((left, right) => left.id.compareTo(right.id));
  return matches.first;
}

String _buildProgressCountHelperText({
  required num targetAmount,
  required num loggedAmount,
  required num remainingAmount,
  required List<String> assignedUnitIds,
  required Map<String, String> planUnitLabelById,
  required String? selectedUnitId,
}) {
  final selectedUnitLabel =
      (selectedUnitId != null && selectedUnitId.trim().isNotEmpty)
      ? (planUnitLabelById[selectedUnitId.trim()] ?? selectedUnitId.trim())
      : "";
  final targetLabel = _formatProgressAmount(targetAmount);
  final loggedLabel = _formatProgressAmount(loggedAmount);
  final remainingLabel = _formatProgressAmount(remainingAmount);
  if (selectedUnitLabel.isNotEmpty) {
    return "Enter only what this one staff completed today. Task target: $targetLabel. Already logged across the task: $loggedLabel. Still available to record: $remainingLabel. Unit: $selectedUnitLabel.";
  }
  if (assignedUnitIds.isNotEmpty) {
    final assignedUnitsLabel = _buildAssignedUnitLabel(
      assignedUnitIds: assignedUnitIds,
      planUnitLabelById: planUnitLabelById,
    );
    return "Enter only what this one staff completed today. Task target: $targetLabel. Already logged across the task: $loggedLabel. Still available to record: $remainingLabel. Assigned plots/units: $assignedUnitsLabel.";
  }
  return "Enter only what this one staff completed today. Task target: $targetLabel. Already logged across the task: $loggedLabel. Still available to record: $remainingLabel.";
}

String _normalizeRole(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "_");
}

List<BusinessStaffProfileSummary> _staffCandidatesForTask({
  required ProductionTask task,
  required List<BusinessStaffProfileSummary> staffList,
}) {
  final normalizedRole = _normalizeRole(task.roleRequired);
  final activeStaff = staffList
      .where((staff) => staff.status.trim().toLowerCase() != "terminated")
      .toList();
  final matching = activeStaff
      .where((staff) => _normalizeRole(staff.staffRole) == normalizedRole)
      .toList();
  if (matching.isNotEmpty) {
    return matching;
  }
  return activeStaff;
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
  return staff.id;
}

String _formatTaskWindow(DateTime? startDate, DateTime? dueDate) {
  if (startDate == null && dueDate == null) {
    return "-";
  }
  if (startDate != null && dueDate != null) {
    final sameDay = _isSameDay(startDate, dueDate);
    final hasTimes =
        startDate.hour != 0 ||
        startDate.minute != 0 ||
        dueDate.hour != 0 ||
        dueDate.minute != 0;
    if (sameDay && hasTimes) {
      return "${formatDateLabel(startDate)} • ${_clockLabel(startDate)} - ${_clockLabel(dueDate)}";
    }
    return "${formatDateLabel(startDate)} - ${formatDateLabel(dueDate)}";
  }
  final single = startDate ?? dueDate;
  return formatDateLabel(single);
}

String _formatAttendanceWindow(ProductionAttendanceRecord? attendance) {
  if (attendance == null || attendance.clockInAt == null) {
    return _attendanceUnsetLabel;
  }
  final clockInAt = attendance.clockInAt!.toLocal();
  final clockOutAt = attendance.clockOutAt?.toLocal();
  final clockInLabel = _clockLabel(clockInAt);
  final clockOutLabel = clockOutAt == null
      ? _attendanceOpenLabel
      : _clockLabel(clockOutAt);
  return "In $clockInLabel • Out $clockOutLabel";
}

String _clockLabel(DateTime value) {
  final hour = value.hour.toString().padLeft(2, "0");
  final minute = value.minute.toString().padLeft(2, "0");
  return "$hour:$minute";
}

DateTime _mergeDateAndTime(DateTime day, TimeOfDay time) {
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

String _formatProgressApproval(String approvalState) {
  switch (approvalState.trim().toLowerCase()) {
    case "approved":
      return "Approved";
    case "needs_review":
      return "Needs review";
    default:
      return "Pending";
  }
}

Future<List<String>?> _showTaskAssignmentDialog(
  BuildContext context, {
  required ProductionTask task,
  required List<BusinessStaffProfileSummary> staffList,
  required Map<String, BusinessStaffProfileSummary> staffMap,
}) async {
  final candidates = _staffCandidatesForTask(task: task, staffList: staffList);
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(_staffDialogEmptyLabel)));
    return null;
  }
  final selected = _resolveAssignedStaffIds(task).toSet();

  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text("Select staff for ${task.title}"),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _removeStaffHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    ...candidates.map((staff) {
                      final checked = selected.contains(staff.id);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selected.add(staff.id);
                            } else {
                              selected.remove(staff.id);
                            }
                          });
                        },
                        title: Text(_staffListLabel(staff)),
                        subtitle: Text(
                          "${formatStaffRoleLabel(staff.staffRole, fallback: staff.staffRole)} • ${staffMap[staff.id]?.status ?? staff.status}",
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(_staffDialogCancelLabel),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(selected.toList());
                },
                child: const Text(_staffDialogApplyLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<_WorkspaceLogProgressInput?> _showWorkspaceLogDialog(
  BuildContext context, {
  required DateTime workDate,
  required ProductionTask task,
  required List<ProductionTimelineRow> timelineRows,
  required Map<String, BusinessStaffProfileSummary> staffMap,
  required Map<String, String> planUnitLabelById,
}) async {
  final assignedStaffIds = _resolveAssignedStaffIds(task);
  final assignedUnitIds = task.assignedUnitIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  String? selectedStaffId = assignedStaffIds.isNotEmpty
      ? assignedStaffIds.first
      : null;
  String? selectedUnitId = assignedUnitIds.isNotEmpty
      ? assignedUnitIds.first
      : null;
  final taskTargetAmount = _resolveTaskProgressTargetAmount(
    task: task,
    assignedUnitIds: assignedUnitIds,
  );
  num selectedActualAmount = 0;
  final notesController = TextEditingController();
  var selectedDelayReason = _delayReasonNone;
  var validationError = "";

  void syncFromExistingSelection() {
    final existingRow = _findExistingProgressRowForSelection(
      timelineRows: timelineRows,
      taskId: task.id,
      workDate: workDate,
      staffId: selectedStaffId,
      unitId: selectedUnitId,
    );
    selectedActualAmount = existingRow?.actualPlots ?? 0;
    final existingDelayReason = existingRow?.delayReason.trim() ?? "";
    selectedDelayReason = _delayReasonOptions.contains(existingDelayReason)
        ? existingDelayReason
        : _delayReasonNone;
    notesController.text = existingRow?.notes ?? "";
  }

  syncFromExistingSelection();

  final result = await showDialog<_WorkspaceLogProgressInput>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final loggedTotal = timelineRows
              .where((row) => row.taskId.trim() == task.id.trim())
              .fold<num>(0, (sum, row) => sum + row.actualPlots);
          final existingSelectionRow = _findExistingProgressRowForSelection(
            timelineRows: timelineRows,
            taskId: task.id,
            workDate: workDate,
            staffId: selectedStaffId,
            unitId: selectedUnitId,
          );
          final existingSelectionAmount =
              existingSelectionRow?.actualPlots ?? 0;
          final remainingAvailable =
              taskTargetAmount - (loggedTotal - existingSelectionAmount);
          final cappedRemaining = remainingAvailable < 0
              ? 0
              : remainingAvailable;
          final progressOptions = _buildProgressAmountOptions(
            maxAmount: cappedRemaining,
          );
          if (progressOptions.isNotEmpty &&
              !progressOptions.any(
                (amount) => _sameProgressAmount(amount, selectedActualAmount),
              )) {
            selectedActualAmount = progressOptions.last;
          }
          final actualHelperText = _buildProgressCountHelperText(
            targetAmount: taskTargetAmount,
            loggedAmount: loggedTotal,
            remainingAmount: cappedRemaining,
            assignedUnitIds: assignedUnitIds,
            planUnitLabelById: planUnitLabelById,
            selectedUnitId: selectedUnitId,
          );
          final remainingAfterSave =
              (cappedRemaining - selectedActualAmount) < 0
              ? 0
              : (cappedRemaining - selectedActualAmount);
          final selectedStaffLabel =
              (selectedStaffId != null && selectedStaffId!.trim().isNotEmpty)
              ? _resolveStaffDisplayName(selectedStaffId!, staffMap)
              : _unassignedLabel;
          return AlertDialog(
            title: const Text(_logDialogTitle),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatDateLabel(workDate)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _logDialogWorkflowHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (assignedStaffIds.isNotEmpty)
                      DropdownButtonFormField<String?>(
                        initialValue: selectedStaffId,
                        decoration: const InputDecoration(
                          labelText: _logDialogStaffLabel,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(_unassignedLabel),
                          ),
                          ...assignedStaffIds.map(
                            (staffId) => DropdownMenuItem<String?>(
                              value: staffId,
                              child: Text(
                                _resolveStaffDisplayName(staffId, staffMap),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedStaffId = value;
                            syncFromExistingSelection();
                          });
                        },
                      ),
                    if (assignedStaffIds.isNotEmpty) const SizedBox(height: 12),
                    if (assignedUnitIds.isNotEmpty)
                      DropdownButtonFormField<String?>(
                        initialValue: selectedUnitId,
                        decoration: const InputDecoration(
                          labelText: _logDialogUnitLabel,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text("-"),
                          ),
                          ...assignedUnitIds.map(
                            (unitId) => DropdownMenuItem<String?>(
                              value: unitId,
                              child: Text(planUnitLabelById[unitId] ?? unitId),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedUnitId = value;
                            syncFromExistingSelection();
                          });
                        },
                      ),
                    if (assignedUnitIds.isNotEmpty) const SizedBox(height: 12),
                    DropdownButtonFormField<num>(
                      initialValue: selectedActualAmount,
                      decoration: InputDecoration(
                        labelText: _logDialogActualLabel,
                        helperText: actualHelperText,
                        helperMaxLines: 3,
                      ),
                      items: progressOptions
                          .map(
                            (amount) => DropdownMenuItem<num>(
                              value: amount,
                              child: Text(_formatProgressAmount(amount)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedActualAmount = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Save preview: ${_formatProgressAmount(selectedActualAmount)} completed by $selectedStaffLabel today • ${_formatProgressAmount(remainingAfterSave)} still available after save.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDelayReason,
                      decoration: const InputDecoration(
                        labelText: _logDialogDelayLabel,
                        helperText: _logDialogDelayHelper,
                        helperMaxLines: 2,
                      ),
                      items: _delayReasonOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_formatDelayReason(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedDelayReason = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: _logDialogNotesLabel,
                        hintText: _logDialogNotesHint,
                      ),
                    ),
                    if (validationError.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        validationError,
                        style: TextStyle(
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
                child: const Text(_logDialogCancelLabel),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedActualAmount == 0 &&
                      selectedDelayReason == _delayReasonNone) {
                    setDialogState(() {
                      validationError = _logDialogDelayRequired;
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    _WorkspaceLogProgressInput(
                      staffId: selectedStaffId,
                      unitId: selectedUnitId,
                      actualPlots: selectedActualAmount,
                      delayReason: selectedDelayReason,
                      notes: notesController.text.trim(),
                    ),
                  );
                },
                child: const Text(_logDialogSaveLabel),
              ),
            ],
          );
        },
      );
    },
  );

  notesController.dispose();
  return result;
}

Future<_AttendanceEditInput?> _showAttendanceDialog(
  BuildContext context, {
  required String staffLabel,
  required String taskTitle,
  required DateTime workDate,
  required ProductionAttendanceRecord? existingAttendance,
}) async {
  DateTime? selectedClockInAt = existingAttendance?.clockInAt?.toLocal();
  DateTime? selectedClockOutAt = existingAttendance?.clockOutAt?.toLocal();
  var validationError = "";

  return showDialog<_AttendanceEditInput>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickClockIn() async {
            final initial = TimeOfDay.fromDateTime(
              selectedClockInAt?.toLocal() ??
                  _mergeDateAndTime(
                    workDate,
                    const TimeOfDay(hour: 8, minute: 0),
                  ),
            );
            final time = await showTimePicker(
              context: dialogContext,
              initialTime: initial,
            );
            if (time == null) {
              return;
            }
            setDialogState(() {
              selectedClockInAt = _mergeDateAndTime(workDate, time);
            });
          }

          Future<void> pickClockOut() async {
            final initial = TimeOfDay.fromDateTime(
              selectedClockOutAt?.toLocal() ??
                  selectedClockInAt?.toLocal() ??
                  _mergeDateAndTime(
                    workDate,
                    const TimeOfDay(hour: 17, minute: 0),
                  ),
            );
            final time = await showTimePicker(
              context: dialogContext,
              initialTime: initial,
            );
            if (time == null) {
              return;
            }
            setDialogState(() {
              selectedClockOutAt = _mergeDateAndTime(workDate, time);
            });
          }

          return AlertDialog(
            title: const Text(_attendanceDialogTitle),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    staffLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$taskTitle • ${_formatCalendarDate(workDate)}",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _attendanceDialogHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: pickClockIn,
                    icon: const Icon(Icons.login_outlined),
                    label: Text(
                      selectedClockInAt == null
                          ? _attendanceDialogClockInLabel
                          : "$_attendanceDialogClockInLabel: ${_clockLabel(selectedClockInAt!)}",
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: pickClockOut,
                    icon: const Icon(Icons.logout_outlined),
                    label: Text(
                      selectedClockOutAt == null
                          ? _attendanceDialogClockOutLabel
                          : "$_attendanceDialogClockOutLabel: ${_clockLabel(selectedClockOutAt!)}",
                    ),
                  ),
                  if (validationError.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(_attendanceCancelLabel),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedClockInAt == null) {
                    setDialogState(() {
                      validationError = _attendanceClockInRequired;
                    });
                    return;
                  }
                  if (selectedClockOutAt != null &&
                      selectedClockOutAt!.isBefore(selectedClockInAt!)) {
                    setDialogState(() {
                      validationError = _attendanceClockOrderInvalid;
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    _AttendanceEditInput(
                      clockInAt: selectedClockInAt!,
                      clockOutAt: selectedClockOutAt,
                    ),
                  );
                },
                child: const Text(_attendanceSaveLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> _showReasonDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(_staffDialogCancelLabel),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text(_staffDialogApplyLabel),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

String _formatDelayReason(String value) {
  if (value == _delayReasonNone) {
    return "None";
  }
  return value
      .replaceAll("_", " ")
      .split(" ")
      .where((part) => part.isNotEmpty)
      .map((part) => "${part[0].toUpperCase()}${part.substring(1)}")
      .join(" ");
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
