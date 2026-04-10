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

import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_draft_presence.dart';
import 'package:frontend/app/features/home/presentation/production/production_calendar_visuals.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_presence_banner.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_viewer.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_picker.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_proof_flow.dart';
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
const String _openDraftLabel = "Open draft";
const String _returnToDraftLabel = "Return to draft";
const String _viewInsightsTooltip = "Open plan insights";
const String _refreshTooltip = "Refresh";
const String _returnToDraftSuccess = "Production plan returned to draft.";
const String _returnToDraftFailure = "Unable to return the plan to draft.";
const String _returnToDraftConfirmTitle = "Return this plan to draft?";
const String _returnToDraftConfirmMessage =
    "This stops the live production lifecycle and reopens the same plan in draft mode so you can edit the saved schedule directly.";
const String _returnToDraftConfirmLabel = "Return to draft";
const String _todayLabel = "Today";
const String _unassignedLabel = "Unassigned";
const String _assignStaffLabel = "Manage staff";
const String _removeStaffHint = "Leave everything unchecked to remove staff.";
const String _logProgressLabel = "Log progress";
const String _editProgressLabel = "Edit progress";
const String _taskApproveLabel = "Approve task";
const String _taskRejectLabel = "Reject task";
const String _progressApproveLabel = "Approve log";
const String _progressRejectLabel = "Review log";
const String _scheduleLabel = "Schedule";
const String _roleLabel = "Role";
const String _assignedLabel = "Assigned";
const String _assignedStaffFallbackLabel = "Assigned staff";
const String _unitsLabel = "Units";
const String _instructionsLabel = "Notes";
const String _activityLabel = "Activity";
const String _logsLabel = "Logs";
const String _expectedLabel = "Expected";
const String _actualLabel = "Actual";
const String _workingOnLabel = "Working on";
const String _doneTodayLabel = "Done today";
const String _leftTodayLabel = "Left today";
const String _approvalLabel = "Approval";
const String _noActivityLabel = "No progress logs yet for this day.";
const String _estimatedDatesLabel = "Estimated";
const String _clockedInLabel = "Clocked in";
const String _clockedOutLabel = "Clocked out";
const String _attendanceClockInUnsetLabel = "Not clocked in";
const String _attendanceClockOutUnsetLabel = "Not clocked out";
const String _attendanceClockOutPendingLabel = "Awaiting clock-out";
const String _setAttendanceLabel = "Set time";
const String _editAttendanceLabel = "Edit time";
const String _attendanceQuickClockInSuccess = "Clock-in recorded.";
const String _attendanceQuickClockOutSuccess = "Clock-out and proof saved.";
const String _attendanceNotStartedHint =
    "Use Clock in to start this shift, or Set time if you need to backfill the exact hours.";
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
const String _taskProgressNeedsAssignedStaff =
    "Assign staff to this task before logging daily progress.";
const String _taskProgressAttendanceRequired =
    "Clock in and clock out before logging progress.";
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
const String _logDialogActualInvalid = "Select a valid progress amount.";
const String _logDialogStaffLabel = "Staff who did this work today";
const String _logDialogDelayLabel = "Delay reason";
const String _logDialogDelayHelper =
    "Use None when work was completed. Choose the real reason only if this staff completed 0 today.";
const String _logDialogQuantityActivityLabel = "Farm production activity";
const String _logDialogQuantityAmountLabel = "Quantity completed today";
const String _logDialogQuantityHelper =
    "Track planting, transplant, or harvest quantities against the farm estimate. This updates the remaining target immediately.";
const String _logDialogNotesLabel = "Daily notes";
const String _rejectDialogTitle = "Reject task";
const String _rejectDialogHint = "Add a short reason";
const String _rejectProgressDialogTitle = "Mark progress for review";
const String _viewProofLabel = "View proof";
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
const String _quantityActivityNone = "none";
const String _quantityActivityPlanting = "planting";
const String _quantityActivityTransplant = "transplant";
const String _quantityActivityHarvest = "harvest";
const List<String> _delayReasonOptions = [
  _delayReasonNone,
  _delayReasonRain,
  _delayReasonEquipmentFailure,
  _delayReasonLabourShortage,
  _delayReasonHealth,
  _delayReasonInputUnavailable,
  _delayReasonManagementDelay,
];
const List<String> _quantityActivityOptions = [
  _quantityActivityNone,
  _quantityActivityPlanting,
  _quantityActivityTransplant,
  _quantityActivityHarvest,
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
const double _agendaCardPadding = 14;
const int _workspaceAssetQueryPage = 1;
const int _workspaceAssetQueryLimit = 200;
const Color _workspaceBlue = Color(0xFF2856C3);
const Color _workspaceTeal = Color(0xFF127B68);
const Color _workspaceAmber = Color(0xFFC57612);
const Color _workspaceBerry = Color(0xFF8B4DC9);
const Color _workspaceNavy = Color(0xFF1C3159);
const Color _workspaceSoftBlue = Color(0xFFE7F0FF);
const Color _workspaceSoftTeal = Color(0xFFE1F5EF);
const Color _workspaceSoftAmber = Color(0xFFFFF0D9);
const Color _workspaceSoftBerry = Color(0xFFF4E7FF);
const Color _workspaceSoftSlate = Color(0xFFEEF4FC);
final RegExp _importedProjectDayPattern = RegExp(
  r"Project day\s+\d+\s+\((\d{4}-\d{2}-\d{2})\)\.",
  caseSensitive: false,
);

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

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _logBuild, extra: {"planId": widget.planId});
    final detailAsync = ref.watch(productionPlanDetailProvider(widget.planId));
    final staffAsync = ref.watch(productionStaffProvider);
    final session = ref.watch(authSessionProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final profileRole = profileAsync.valueOrNull?.role ?? "";
    final actorRole = profileRole.isNotEmpty ? profileRole : session?.user.role;
    final presenceState = ref.watch(
      productionDraftPresenceProvider(widget.planId),
    );
    ref.listen<ProductionDraftPresenceState>(
      productionDraftPresenceProvider(widget.planId),
      (previous, next) {
        if (previous?.updatedAt == next.updatedAt) {
          return;
        }
        ref.invalidate(productionPlanDetailProvider(widget.planId));
        ref.invalidate(productionPlansProvider);
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
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
            final assetsAsync = ref.watch(
              businessAssetsProvider(
                const BusinessAssetsQuery(
                  page: _workspaceAssetQueryPage,
                  limit: _workspaceAssetQueryLimit,
                ),
              ),
            );
            final staffList = <BusinessStaffProfileSummary>[
              ...(staffAsync.valueOrNull ?? <BusinessStaffProfileSummary>[]),
              ...detail.staffProfiles,
            ];
            final staffMap = _buildStaffMap(staffList);
            final selfStaffRole = _resolveSelfStaffRole(
              staffList: staffList,
              userEmail: profileAsync.valueOrNull?.email ?? session?.user.email,
            );
            final selfStaffId = _resolveSelfStaffId(
              staffList: staffList,
              userEmail: profileAsync.valueOrNull?.email ?? session?.user.email,
            );
            final canManageCalendar = _canManageCalendar(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canManageLifecycle = _canManagePlanLifecycle(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canSubmitOwnProgress =
                actorRole == "staff" && selfStaffId.trim().isNotEmpty;
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
            final planUnitsResponse = ref
                .watch(productionPlanUnitsProvider(widget.planId))
                .valueOrNull;
            final planUnitLabelById = <String, String>{
              for (final unit
                  in (planUnitsResponse?.units ?? const <ProductionPlanUnit>[]))
                unit.id: unit.label,
            };
            final workScopeSummary = _resolveWorkspaceWorkScopeSummary(
              plan: detail.plan,
              planUnitsResponse: planUnitsResponse,
            );
            final tasksForDay = _tasksForDay(detail.tasks, selectedDay);
            final rowsForDay = _rowsForDay(detail.timelineRows, selectedDay);
            final phaseById = {
              for (final phase in detail.phases) phase.id: phase,
            };
            final selectedEstateName = assetsAsync.maybeWhen(
              data: (result) {
                for (final asset in result.assets) {
                  if (asset.id == detail.plan.estateAssetId) {
                    return asset.name;
                  }
                }
                return "";
              },
              orElse: () => "",
            );
            final inferredProductName = _inferProductNameFromPlanTitle(
              detail.plan.title,
            );
            final productAsync = detail.plan.productId.trim().isEmpty
                ? null
                : ref.watch(businessProductByIdProvider(detail.plan.productId));
            final selectedProductName =
                productAsync?.valueOrNull?.name.trim().isNotEmpty == true
                ? productAsync!.valueOrNull!.name.trim()
                : inferredProductName;
            final currentUserId = profileAsync.valueOrNull?.id.trim();
            final currentUserName = profileAsync.valueOrNull?.name.trim();
            final currentUserEmail = profileAsync.valueOrNull?.email.trim();
            final currentAccountRole = profileRole.trim();
            final currentViewer = ProductionDraftPresenceViewer(
              userId: (currentUserId != null && currentUserId.isNotEmpty)
                  ? currentUserId
                  : (session?.user.id ?? "").trim(),
              displayName:
                  (currentUserName != null && currentUserName.isNotEmpty)
                  ? currentUserName
                  : (session?.user.name ?? "").trim(),
              email: (currentUserEmail != null && currentUserEmail.isNotEmpty)
                  ? currentUserEmail
                  : (session?.user.email ?? "").trim(),
              accountRole: currentAccountRole.isNotEmpty
                  ? currentAccountRole
                  : (session?.user.role ?? "").trim(),
              staffRole: selfStaffRole,
              enteredAt: null,
              lastSeenAt: null,
              leftAt: null,
              activeSocketCount: 0,
              currentSessionSeconds: 0,
              durationSeconds: 0,
              todaySeconds: 0,
              weekSeconds: 0,
              monthSeconds: 0,
              yearSeconds: 0,
              totalSeconds: 0,
              sessionCount: 0,
            );
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
                  detail: detail,
                  plan: detail.plan,
                  workScopeSummary: workScopeSummary,
                  selectedEstateName: selectedEstateName,
                  selectedProductName: selectedProductName,
                  selectedDay: selectedDay,
                  scheduledTaskCount: tasksForDay.length,
                  timelineRows: detail.timelineRows,
                  onOpenDraft: () {
                    context.push(
                      productionPlanDraftStudioPath(planId: widget.planId),
                    );
                  },
                  onViewInsights: () {
                    context.push(productionPlanInsightsPath(widget.planId));
                  },
                  onReturnToDraft:
                      canManageLifecycle &&
                          (detail.plan.status == "active" ||
                              detail.plan.status == "paused")
                      ? () async {
                          final confirmed = await _confirmAction(
                            title: _returnToDraftConfirmTitle,
                            message: _returnToDraftConfirmMessage,
                            confirmLabel: _returnToDraftConfirmLabel,
                          );
                          if (!confirmed) {
                            return;
                          }
                          try {
                            await ref
                                .read(productionPlanActionsProvider)
                                .updatePlanStatus(
                                  planId: widget.planId,
                                  status: "draft",
                                );
                            if (!mounted || !this.context.mounted) {
                              return;
                            }
                            setState(() {
                              _visibleMonth = null;
                              _selectedDay = null;
                            });
                            _showSnackSafe(_returnToDraftSuccess);
                            GoRouter.of(this.context).go(
                              productionPlanDraftStudioPath(
                                planId: widget.planId,
                              ),
                            );
                          } catch (error) {
                            _showSnackSafe(
                              _resolveProductionWorkspaceErrorMessage(
                                error,
                                fallback: _returnToDraftFailure,
                              ),
                            );
                          }
                        }
                      : null,
                ),
                const SizedBox(height: _sectionSpacing),
                ProductionPresenceBanner(
                  currentViewer: currentViewer,
                  remoteViewers: presenceState.viewers,
                  isConnected: presenceState.isConnected,
                  isSharedRoom: widget.planId.trim().isNotEmpty,
                  errorMessage: presenceState.error,
                  planId: widget.planId,
                  snapshotAt: presenceState.updatedAt,
                  onOpenStats: widget.planId.trim().isEmpty
                      ? null
                      : () => context.push(
                          productionPlanPresenceStatsPath(widget.planId),
                        ),
                ),
                const SizedBox(height: _sectionSpacing),
                ProductionSectionHeader(
                  title: _workspaceTitle,
                  subtitle:
                      "$_workspaceSubtitle Working on ${workScopeSummary.countLabel}.",
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
                    workScopeSummary: workScopeSummary,
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
                    workScopeSummary: workScopeSummary,
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
                    workScopeSummary: workScopeSummary,
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
                    final assignedStaffIdsForTask = _resolveAssignedStaffIds(
                      task,
                    );
                    final canLogProgressForTask =
                        assignedStaffIdsForTask.isNotEmpty &&
                        (canManageCalendar ||
                            (canSubmitOwnProgress &&
                                assignedStaffIdsForTask.contains(selfStaffId)));
                    final progressEnabledStaffIds = canManageCalendar
                        ? assignedStaffIdsForTask.toSet()
                        : (canSubmitOwnProgress &&
                              selfStaffId.trim().isNotEmpty &&
                              assignedStaffIdsForTask.contains(selfStaffId))
                        ? <String>{selfStaffId}
                        : <String>{};
                    final attendanceActions = StaffAttendanceActions(ref);

                    Future<ProductionAttendanceRecord?>
                    setAttendanceForTaskStaff(
                      String staffProfileId,
                      ProductionAttendanceRecord? existingAttendance,
                    ) async {
                      final staffLabel = _resolveStaffDisplayLabel(
                        staffProfileId,
                        staffMap,
                        fallbackRole: task.roleRequired,
                      );
                      final input = await _showAttendanceDialog(
                        context,
                        staffLabel: staffLabel,
                        taskTitle: task.title,
                        workDate: selectedDay,
                        existingAttendance: existingAttendance,
                      );
                      if (input == null) {
                        return null;
                      }
                      try {
                        final note = "Updated from production workspace";
                        StaffAttendanceRecord attendanceRecord;
                        final existingClockInAt = existingAttendance?.clockInAt
                            ?.toLocal();
                        final existingClockOutAt = existingAttendance
                            ?.clockOutAt
                            ?.toLocal();
                        final shouldSetClockOutFirst =
                            existingAttendance != null &&
                            input.clockOutAt != null &&
                            existingClockOutAt != null &&
                            input.clockInAt.isAfter(existingClockOutAt) &&
                            !(existingClockInAt != null &&
                                input.clockOutAt!.isBefore(existingClockInAt));
                        if (shouldSetClockOutFirst) {
                          final updatedClockOut = await attendanceActions
                              .clockOut(
                                staffProfileId: staffProfileId,
                                attendanceId: existingAttendance.id,
                                clockOutAt: input.clockOutAt,
                                workDate: selectedDay,
                                planId: widget.planId,
                                taskId: task.id,
                                notes: note,
                              );
                          await requireAttendanceProofUpload(
                            context: context,
                            ref: ref,
                            attendance: updatedClockOut,
                            subjectLabel: staffLabel,
                            taskLabel: task.title,
                          );
                          attendanceRecord = await attendanceActions.clockIn(
                            staffProfileId: staffProfileId,
                            attendanceId: updatedClockOut.id,
                            clockInAt: input.clockInAt,
                            workDate: selectedDay,
                            planId: widget.planId,
                            taskId: task.id,
                            notes: note,
                          );
                        } else {
                          attendanceRecord = await attendanceActions.clockIn(
                            staffProfileId: staffProfileId,
                            attendanceId: existingAttendance?.id,
                            clockInAt: input.clockInAt,
                            workDate: selectedDay,
                            planId: widget.planId,
                            taskId: task.id,
                            notes: note,
                          );
                          if (input.clockOutAt != null) {
                            attendanceRecord = await attendanceActions.clockOut(
                              staffProfileId: staffProfileId,
                              attendanceId: attendanceRecord.id,
                              clockOutAt: input.clockOutAt,
                              workDate: selectedDay,
                              planId: widget.planId,
                              taskId: task.id,
                              notes: note,
                            );
                            attendanceRecord =
                                await requireAttendanceProofUpload(
                                  context: context,
                                  ref: ref,
                                  attendance: attendanceRecord,
                                  subjectLabel: staffLabel,
                                  taskLabel: task.title,
                                );
                          }
                        }
                        ref.invalidate(
                          productionPlanDetailProvider(widget.planId),
                        );
                        _showSnackSafe(_attendanceUpdateSuccess);
                        return _toProductionAttendanceRecord(attendanceRecord);
                      } catch (_) {
                        _showSnackSafe(_attendanceUpdateFailure);
                        return null;
                      }
                    }

                    Future<ProductionAttendanceRecord?>
                    quickClockInForTaskStaff(
                      String staffProfileId,
                      ProductionAttendanceRecord? existingAttendance,
                    ) async {
                      if (existingAttendance != null) {
                        return null;
                      }
                      try {
                        final clockInAt = _resolveQuickAttendanceTime(
                          selectedDay,
                        );
                        final attendanceRecord = await attendanceActions
                            .clockIn(
                              staffProfileId: staffProfileId,
                              clockInAt: clockInAt,
                              workDate: selectedDay,
                              planId: widget.planId,
                              taskId: task.id,
                              notes: "Clocked in from production workspace",
                            );
                        ref.invalidate(
                          productionPlanDetailProvider(widget.planId),
                        );
                        _showSnackSafe(_attendanceQuickClockInSuccess);
                        return _toProductionAttendanceRecord(attendanceRecord);
                      } catch (error) {
                        _showSnackSafe(
                          _resolveProductionWorkspaceErrorMessage(
                            error,
                            fallback: _attendanceUpdateFailure,
                          ),
                        );
                        return null;
                      }
                    }

                    Future<ProductionAttendanceRecord?>
                    quickClockOutForTaskStaff(
                      String staffProfileId,
                      ProductionAttendanceRecord? existingAttendance,
                    ) async {
                      final openAttendance = existingAttendance;
                      if (openAttendance == null ||
                          openAttendance.clockOutAt != null) {
                        return null;
                      }
                      final clockInAt = openAttendance.clockInAt?.toLocal();
                      if (clockInAt == null) {
                        return null;
                      }
                      try {
                        final clockOutAt = _resolveQuickClockOutTime(
                          workDate: selectedDay,
                          clockInAt: clockInAt,
                        );
                        final attendanceRecord = await attendanceActions
                            .clockOut(
                              staffProfileId: staffProfileId,
                              attendanceId: openAttendance.id,
                              clockOutAt: clockOutAt,
                              workDate: selectedDay,
                              planId: widget.planId,
                              taskId: task.id,
                              notes: "Clocked out from production workspace",
                            );
                        final attendanceWithProof =
                            await requireAttendanceProofUpload(
                              context: context,
                              ref: ref,
                              attendance: attendanceRecord,
                              subjectLabel: _resolveStaffDisplayLabel(
                                staffProfileId,
                                staffMap,
                                fallbackRole: task.roleRequired,
                              ),
                              taskLabel: task.title,
                            );
                        ref.invalidate(
                          productionPlanDetailProvider(widget.planId),
                        );
                        _showSnackSafe(_attendanceQuickClockOutSuccess);
                        return _toProductionAttendanceRecord(
                          attendanceWithProof,
                        );
                      } catch (error) {
                        _showSnackSafe(
                          _resolveProductionWorkspaceErrorMessage(
                            error,
                            fallback: _attendanceUpdateFailure,
                          ),
                        );
                        return null;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: _cardSpacing),
                      child: _AgendaTaskCard(
                        task: task,
                        phaseName:
                            phaseById[task.phaseId]?.name ?? task.phaseId,
                        staffMap: staffMap,
                        currentActorStaffId: selfStaffId,
                        planUnitLabelById: planUnitLabelById,
                        fallbackTotalUnits: workScopeSummary.totalUnits,
                        fallbackWorkUnitLabel: workScopeSummary.singularLabel,
                        planContextText:
                            "${detail.plan.title} ${detail.plan.notes}",
                        selectedDay: selectedDay,
                        attendanceRecords: detail.attendanceRecords,
                        timelineRows: detail.timelineRows,
                        rowsForDay: rowsForTask,
                        canManageCalendar: canManageCalendar,
                        canManageTaskAttendance: canManageTaskAttendance,
                        canReviewProgress: canReviewProgress,
                        isOwner: actorRole == "business_owner",
                        progressEnabledStaffIds: progressEnabledStaffIds,
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
                                await setAttendanceForTaskStaff(
                                  staffProfileId,
                                  existingAttendance,
                                );
                              }
                            : null,
                        onQuickClockInForStaff: canManageTaskAttendance
                            ? (staffProfileId, existingAttendance) async {
                                await quickClockInForTaskStaff(
                                  staffProfileId,
                                  existingAttendance,
                                );
                              }
                            : null,
                        onQuickClockOutForStaff: canManageTaskAttendance
                            ? (staffProfileId, existingAttendance) async {
                                await quickClockOutForTaskStaff(
                                  staffProfileId,
                                  existingAttendance,
                                );
                              }
                            : null,
                        onLogProgressForStaff: progressEnabledStaffIds.isEmpty
                            ? null
                            : (staffProfileId) async {
                                final input = await _showWorkspaceLogDialog(
                                  context,
                                  workDate: selectedDay,
                                  task: task,
                                  plan: detail.plan,
                                  timelineRows: detail.timelineRows,
                                  staffMap: staffMap,
                                  planUnitLabelById: planUnitLabelById,
                                  fallbackTotalUnits:
                                      workScopeSummary.totalUnits,
                                  fallbackWorkUnitLabel:
                                      workScopeSummary.singularLabel,
                                  attendanceRecords: detail.attendanceRecords,
                                  actorStaffId: staffProfileId,
                                  canPickAnyAssignedStaff: false,
                                  canManageAttendance: canManageTaskAttendance,
                                  onSetAttendanceForStaff:
                                      canManageTaskAttendance
                                      ? setAttendanceForTaskStaff
                                      : null,
                                  onQuickClockInForStaff:
                                      (canManageTaskAttendance ||
                                          (selfStaffId.trim().isNotEmpty &&
                                              selfStaffId.trim() ==
                                                  staffProfileId.trim()))
                                      ? quickClockInForTaskStaff
                                      : null,
                                  onQuickClockOutForStaff:
                                      (canManageTaskAttendance ||
                                          (selfStaffId.trim().isNotEmpty &&
                                              selfStaffId.trim() ==
                                                  staffProfileId.trim()))
                                      ? quickClockOutForTaskStaff
                                      : null,
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
                                    "staffId": input.staffId,
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
                                        quantityActivityType:
                                            input.quantityActivityType,
                                        quantityAmount: input.quantityAmount,
                                        quantityUnit: input.quantityUnit,
                                        proofs: input.proofs,
                                        delayReason: input.delayReason,
                                        notes: input.notes,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_taskProgressSuccess);
                                } catch (error) {
                                  _showSnackSafe(
                                    _resolveProductionWorkspaceErrorMessage(
                                      error,
                                      fallback: _taskProgressFailure,
                                    ),
                                  );
                                }
                              },
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
                        onLogProgress: canLogProgressForTask
                            ? () async {
                                final input = await _showWorkspaceLogDialog(
                                  context,
                                  workDate: selectedDay,
                                  task: task,
                                  plan: detail.plan,
                                  timelineRows: detail.timelineRows,
                                  staffMap: staffMap,
                                  planUnitLabelById: planUnitLabelById,
                                  fallbackTotalUnits:
                                      workScopeSummary.totalUnits,
                                  fallbackWorkUnitLabel:
                                      workScopeSummary.singularLabel,
                                  attendanceRecords: detail.attendanceRecords,
                                  actorStaffId: selfStaffId.trim().isEmpty
                                      ? null
                                      : selfStaffId,
                                  canPickAnyAssignedStaff: canManageCalendar,
                                  canManageAttendance: canManageTaskAttendance,
                                  onSetAttendanceForStaff:
                                      canManageTaskAttendance
                                      ? setAttendanceForTaskStaff
                                      : null,
                                  onQuickClockInForStaff:
                                      canManageTaskAttendance ||
                                          selfStaffId.trim().isNotEmpty
                                      ? quickClockInForTaskStaff
                                      : null,
                                  onQuickClockOutForStaff:
                                      canManageTaskAttendance ||
                                          selfStaffId.trim().isNotEmpty
                                      ? quickClockOutForTaskStaff
                                      : null,
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
                                        quantityActivityType:
                                            input.quantityActivityType,
                                        quantityAmount: input.quantityAmount,
                                        quantityUnit: input.quantityUnit,
                                        proofs: input.proofs,
                                        delayReason: input.delayReason,
                                        notes: input.notes,
                                        planId: widget.planId,
                                      );
                                  _showSnackSafe(_taskProgressSuccess);
                                } catch (error) {
                                  _showSnackSafe(
                                    _resolveProductionWorkspaceErrorMessage(
                                      error,
                                      fallback: _taskProgressFailure,
                                    ),
                                  );
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

class _WorkspaceSummaryMetrics {
  final int phaseCount;
  final int totalTasks;
  final int unassignedTasks;
  final int totalProjectDays;

  const _WorkspaceSummaryMetrics({
    required this.phaseCount,
    required this.totalTasks,
    required this.unassignedTasks,
    required this.totalProjectDays,
  });

  factory _WorkspaceSummaryMetrics.fromDetail(ProductionPlanDetail detail) {
    final totalProjectDays =
        detail.plan.startDate == null || detail.plan.endDate == null
        ? 0
        : detail.plan.endDate!.difference(detail.plan.startDate!).inDays + 1;
    return _WorkspaceSummaryMetrics(
      phaseCount: detail.phases.length,
      totalTasks: detail.tasks.length,
      unassignedTasks: detail.tasks
          .where((task) => task.assignedStaffIds.isEmpty)
          .length,
      totalProjectDays: math.max(0, totalProjectDays),
    );
  }
}

class _WorkspaceWorkScopeSummary {
  final int totalUnits;
  final String baseUnitLabel;

  const _WorkspaceWorkScopeSummary({
    required this.totalUnits,
    required this.baseUnitLabel,
  });

  String get singularLabel => _normalizeWorkspaceUnitLabel(baseUnitLabel);

  String get pluralLabel => _pluralizeWorkspaceUnitLabel(baseUnitLabel);

  String get countLabel =>
      "${totalUnits < 0 ? 0 : totalUnits} ${totalUnits == 1 ? singularLabel : pluralLabel}";

  String get helperLabel =>
      "${_capitalizeWorkspaceLabel(pluralLabel)} from draft";
}

class _TaskUnitProgressSummary {
  final String singularUnitLabel;
  final num plannedAmount;
  final num loggedAmount;

  const _TaskUnitProgressSummary({
    required this.singularUnitLabel,
    required this.plannedAmount,
    required this.loggedAmount,
  });

  num get remainingAmount => math.max(0, plannedAmount - loggedAmount);

  String get workingOnLabel => _formatProgressAmountWithUnit(
    amount: plannedAmount,
    singularUnitLabel: singularUnitLabel,
  );

  String get doneTodayLabel => _formatProgressAmountWithUnit(
    amount: loggedAmount,
    singularUnitLabel: singularUnitLabel,
  );

  String get leftTodayLabel => _formatProgressAmountWithUnit(
    amount: remainingAmount,
    singularUnitLabel: singularUnitLabel,
  );
}

class _WorkspaceSummaryCard extends StatelessWidget {
  final ProductionPlanDetail detail;
  final ProductionPlan plan;
  final _WorkspaceWorkScopeSummary workScopeSummary;
  final String selectedEstateName;
  final String selectedProductName;
  final DateTime selectedDay;
  final int scheduledTaskCount;
  final List<ProductionTimelineRow> timelineRows;
  final VoidCallback onOpenDraft;
  final VoidCallback onViewInsights;
  final VoidCallback? onReturnToDraft;

  const _WorkspaceSummaryCard({
    required this.detail,
    required this.plan,
    required this.workScopeSummary,
    required this.selectedEstateName,
    required this.selectedProductName,
    required this.selectedDay,
    required this.scheduledTaskCount,
    required this.timelineRows,
    required this.onOpenDraft,
    required this.onViewInsights,
    this.onReturnToDraft,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metrics = _WorkspaceSummaryMetrics.fromDetail(detail);
    final farmQuantitySummary = _summarizeFarmQuantities(
      plan: plan,
      timelineRows: timelineRows,
    );
    final lastSavedLabel = plan.lastDraftSavedBy?.displayLabel ?? "";

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            Color.alphaBlend(
              _workspaceSoftBlue.withValues(alpha: 0.72),
              colorScheme.surfaceContainerLow,
            ),
            Color.alphaBlend(
              _workspaceSoftTeal.withValues(alpha: 0.42),
              colorScheme.surfaceContainerLow,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _workspaceBlue.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: _workspaceNavy.withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = constraints.maxWidth < 860;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Production workspace",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    plan.title.trim().isEmpty
                        ? "Untitled production plan"
                        : plan.title.trim(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Run the live schedule here, keep staffing and progress current day by day, and jump back to the draft only when you need to revise the saved baseline.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              );
              final statusBlock = Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ProductionStatusPill(label: plan.status),
                  Chip(
                    avatar: const Icon(Icons.history_outlined, size: 16),
                    label: Text(
                      "${plan.draftRevisionCount} saved revision${plan.draftRevisionCount == 1 ? '' : 's'}",
                    ),
                  ),
                ],
              );
              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 14),
                    statusBlock,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 16),
                  Flexible(child: statusBlock),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryPill(
                icon: Icons.location_on_outlined,
                label: selectedEstateName.trim().isEmpty
                    ? "Estate not resolved"
                    : selectedEstateName,
              ),
              _SummaryPill(
                icon: Icons.spa_outlined,
                label: selectedProductName.trim().isEmpty
                    ? _inferProductNameFromPlanTitle(plan.title)
                    : selectedProductName,
              ),
              _SummaryPill(
                icon: Icons.schedule_outlined,
                label: _formatDisplayDateRange(plan.startDate, plan.endDate),
              ),
              _SummaryPill(
                icon: Icons.grid_view_rounded,
                label: "Working on ${workScopeSummary.countLabel}",
              ),
              if (productionDomainRequiresPlantingTargets(plan.domainContext))
                _SummaryPill(
                  icon: Icons.grass_outlined,
                  label: plan.plantingTargets?.isConfigured == true
                      ? "${_formatProductionQuantity(plan.plantingTargets!.plannedPlantingQuantity)} ${plan.plantingTargets!.plannedPlantingUnit} ${formatProductionPlantingMaterialType(plan.plantingTargets!.materialType).toLowerCase()} → ${_formatProductionQuantity(plan.plantingTargets!.estimatedHarvestQuantity)} ${plan.plantingTargets!.estimatedHarvestUnit}"
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
                    child: _WorkspaceHeroMetricTile(
                      label: "Phases",
                      value: metrics.phaseCount.toString(),
                      helper: "Stage groups",
                      icon: Icons.alt_route_outlined,
                      accentColor: _workspaceBlue,
                      softColor: _workspaceSoftBlue,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _WorkspaceHeroMetricTile(
                      label: "Tasks",
                      value: metrics.totalTasks.toString(),
                      helper: "Live workload",
                      icon: Icons.checklist_rtl_outlined,
                      accentColor: _workspaceNavy,
                      softColor: _workspaceSoftSlate,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _WorkspaceHeroMetricTile(
                      label: "Needs staff",
                      value: metrics.unassignedTasks.toString(),
                      helper: "Unassigned tasks",
                      icon: Icons.person_search_outlined,
                      accentColor: metrics.unassignedTasks == 0
                          ? _workspaceTeal
                          : _workspaceAmber,
                      softColor: metrics.unassignedTasks == 0
                          ? _workspaceSoftTeal
                          : _workspaceSoftAmber,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _WorkspaceHeroMetricTile(
                      label: "Work units",
                      value: workScopeSummary.totalUnits.toString(),
                      helper: workScopeSummary.helperLabel,
                      icon: Icons.grid_view_rounded,
                      accentColor: _workspaceBerry,
                      softColor: _workspaceSoftBerry,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              plan.lastDraftSavedAt == null
                  ? "This production plan does not have a recorded draft save yet."
                  : "Draft baseline last saved ${formatDateTimeLabel(plan.lastDraftSavedAt)}${lastSavedLabel.trim().isEmpty ? '' : ' by $lastSavedLabel'}.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
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
              if (farmQuantitySummary != null) ...[
                _SummaryPill(
                  icon: Icons.grass_outlined,
                  label:
                      "Planted left ${_formatProgressAmount(farmQuantitySummary.plantingRemaining)} ${farmQuantitySummary.plantingUnit}",
                ),
                _SummaryPill(
                  icon: Icons.swap_horiz_outlined,
                  label:
                      "Transplant left ${_formatProgressAmount(farmQuantitySummary.transplantRemaining)} ${farmQuantitySummary.plantingUnit}",
                ),
                _SummaryPill(
                  icon: Icons.agriculture_outlined,
                  label:
                      "Harvest left ${_formatProgressAmount(farmQuantitySummary.harvestRemaining)} ${farmQuantitySummary.harvestUnit}",
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "Keep this screen operational. Open draft to compare or revise the saved plan, and use insights for KPIs, governance, and longer-form reporting.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenDraft,
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text(_openDraftLabel),
              ),
              if (onReturnToDraft != null)
                OutlinedButton.icon(
                  onPressed: onReturnToDraft,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text(_returnToDraftLabel),
                ),
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

class _WorkspaceHeroMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color accentColor;
  final Color softColor;

  const _WorkspaceHeroMetricTile({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.accentColor,
    required this.softColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            Color.alphaBlend(
              softColor.withValues(alpha: 0.88),
              colorScheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: _workspaceNavy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  helper,
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
  final _WorkspaceWorkScopeSummary workScopeSummary;
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
    required this.workScopeSummary,
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
    final monthRows = timelineRows.where((row) {
      final workDate = row.workDate?.toLocal();
      return workDate?.year == month.year && workDate?.month == month.month;
    }).toList();
    final theme = Theme.of(context);
    final completedCount = monthTasks
        .where((task) => task.status == _taskStatusDone)
        .length;
    final palette = ProductionCalendarVisuals.palette(
      theme: theme,
      taskCount: monthTasks.length,
      completedCount: completedCount,
      warning: monthTasks.any(_workspaceTaskHasStaffGap),
    );
    final shellColor = palette.badgeBackground;
    final shellForeground = palette.badgeForeground;
    final shellSurface = shellForeground.withValues(alpha: 0.12);
    final shellBorder = shellForeground.withValues(alpha: 0.16);
    final metricIconColor = shellForeground.withValues(alpha: 0.82);
    final completedMetricAccent = completedCount > 0
        ? ProductionCalendarVisuals.palette(
            theme: theme,
            taskCount: completedCount,
            completedCount: completedCount,
          ).accent
        : metricIconColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: shellBorder, width: 1.4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              shellForeground.withValues(alpha: 0.04),
              shellColor,
            ),
            shellColor,
            Color.alphaBlend(
              palette.accent.withValues(alpha: 0.08),
              shellColor,
            ),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: shellSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: shellBorder),
                      ),
                      child: Icon(
                        Icons.calendar_view_month_rounded,
                        color: shellForeground,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _monthTitle(month),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: shellForeground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              ProductionCalendarMetricPill(
                                icon: Icons.checklist_rounded,
                                value: "${monthTasks.length}",
                                accent: shellForeground,
                                compact: true,
                                filled: false,
                                padding: EdgeInsets.zero,
                                foregroundColor: shellForeground,
                                iconColor: metricIconColor,
                                tooltip: "Tasks",
                              ),
                              ProductionCalendarMetricPill(
                                icon: Icons.done_all_rounded,
                                value: "$completedCount",
                                accent: completedMetricAccent,
                                compact: true,
                                filled: false,
                                padding: EdgeInsets.zero,
                                foregroundColor: shellForeground,
                                iconColor: completedMetricAccent,
                                tooltip: "Completed",
                              ),
                              ProductionCalendarMetricPill(
                                icon: Icons.grid_view_rounded,
                                value: workScopeSummary.countLabel,
                                accent: shellForeground,
                                compact: true,
                                filled: false,
                                padding: EdgeInsets.zero,
                                foregroundColor: shellForeground,
                                iconColor: metricIconColor,
                                tooltip: "Draft work scope",
                              ),
                              if (timelineRows.isNotEmpty)
                                ProductionCalendarMetricPill(
                                  icon: Icons.waterfall_chart_rounded,
                                  value: "${monthRows.length}",
                                  accent: shellForeground,
                                  compact: true,
                                  filled: false,
                                  padding: EdgeInsets.zero,
                                  foregroundColor: shellForeground,
                                  iconColor: metricIconColor,
                                  tooltip: "Logs",
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  foregroundColor: shellForeground,
                  backgroundColor: shellSurface,
                ),
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: shellForeground,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: onToday,
                child: const Text(_todayLabel),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  foregroundColor: shellForeground,
                  backgroundColor: shellSurface,
                ),
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MonthWeekdayHeader(
            textColor: shellForeground.withValues(alpha: 0.86),
            backgroundColor: shellSurface,
            borderColor: shellBorder,
          ),
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
  final Color? textColor;
  final Color? backgroundColor;
  final Color? borderColor;

  const _MonthWeekdayHeader({
    this.textColor,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: _weekdayLabels
          .map(
            (label) => Expanded(
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color:
                      backgroundColor ??
                      Color.alphaBlend(
                        colorScheme.primary.withValues(alpha: 0.08),
                        colorScheme.surfaceContainerHighest,
                      ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color:
                        borderColor ??
                        colorScheme.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: textColor ?? colorScheme.onSurfaceVariant,
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
  final _WorkspaceWorkScopeSummary workScopeSummary;
  final List<ProductionTask> tasks;
  final VoidCallback onPreviousYear;
  final VoidCallback onNextYear;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelectDay;

  const _YearCalendarCard({
    required this.year,
    required this.selectedDay,
    required this.workScopeSummary,
    required this.tasks,
    required this.onPreviousYear,
    required this.onNextYear,
    required this.onToday,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final yearTasks = tasks.where((task) {
      final start = task.startDate?.toLocal();
      final due = task.dueDate?.toLocal();
      return (start?.year == year) || (due?.year == year);
    }).toList();
    final completedCount = yearTasks
        .where((task) => task.status == _taskStatusDone)
        .length;
    final palette = ProductionCalendarVisuals.palette(
      theme: theme,
      taskCount: yearTasks.length,
      completedCount: completedCount,
      warning: yearTasks.any(_workspaceTaskHasStaffGap),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ProductionCalendarVisuals.shellDecoration(
        theme: theme,
        palette: palette,
        radius: 22,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: palette.badgeBackground,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.grid_view_rounded,
                        color: palette.badgeForeground,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "$year",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ProductionCalendarMetricPill(
                                icon: Icons.checklist_rounded,
                                value: "${yearTasks.length}",
                                accent: palette.accent,
                                compact: true,
                              ),
                              ProductionCalendarMetricPill(
                                icon: Icons.done_all_rounded,
                                value: "$completedCount",
                                accent: completedCount > 0
                                    ? ProductionCalendarVisuals.palette(
                                        theme: theme,
                                        taskCount: completedCount,
                                        completedCount: completedCount,
                                      ).accent
                                    : palette.accent,
                                compact: true,
                              ),
                              ProductionCalendarMetricPill(
                                icon: Icons.grid_view_rounded,
                                value: workScopeSummary.countLabel,
                                accent: palette.accent,
                                compact: true,
                                tooltip: "Draft work scope",
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
          const SizedBox(height: 12),
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
    final monthTasks = tasks.where((task) {
      return _taskTouchesMonth(task: task, month: month);
    }).toList();
    final palette = ProductionCalendarVisuals.palette(
      theme: theme,
      taskCount: monthTasks.length,
      completedCount: monthTasks
          .where((task) => task.status == _taskStatusDone)
          .length,
      warning: monthTasks.any(_workspaceTaskHasStaffGap),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: ProductionCalendarVisuals.tileDecoration(
        theme: theme,
        palette: palette,
        radius: 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _monthName(month.month),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: palette.badgeForeground,
                  ),
                ),
              ),
              if (monthTasks.isNotEmpty)
                ProductionCalendarActivityDots(
                  count: monthTasks.length,
                  accent: palette.accent,
                  compact: true,
                ),
            ],
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
                final cellPalette = ProductionCalendarVisuals.palette(
                  theme: theme,
                  taskCount: dayTasks.length,
                  completedCount: dayTasks
                      .where((task) => task.status == _taskStatusDone)
                      .length,
                  selected: isSelected,
                  today: _isSameDay(day, DateTime.now()),
                  warning: dayTasks.any(_workspaceTaskHasStaffGap),
                );
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelectDay(day),
                  child: Container(
                    decoration: BoxDecoration(
                      color: dayTasks.isEmpty
                          ? Colors.transparent
                          : cellPalette.badgeBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: cellPalette.border)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "${day.day}",
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: dayTasks.isNotEmpty
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: isSelected
                                ? cellPalette.badgeForeground
                                : colorScheme.onSurface,
                          ),
                        ),
                        if (dayTasks.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: cellPalette.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
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
    final completed = tasks
        .where((task) => task.status == _taskStatusDone)
        .length;
    final palette = ProductionCalendarVisuals.palette(
      theme: theme,
      taskCount: tasks.length,
      completedCount: completed,
      selected: selected,
      today: _isSameDay(day, DateTime.now()),
      warning: tasks.any(_workspaceTaskHasStaffGap),
    );
    final previewTaskTitle = tasks.isNotEmpty ? tasks.first.title : null;
    final tilePadding = compact ? 6.0 : 8.0;
    final titleStyle = compact
        ? theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          )
        : theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          );
    final previewStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.15,
      fontWeight: FontWeight.w600,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(_dayTileRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(tilePadding),
        decoration: ProductionCalendarVisuals.tileDecoration(
          theme: theme,
          palette: palette,
          radius: _dayTileRadius,
          emphasized: selected || _isSameDay(day, DateTime.now()),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.waterfall_chart_rounded,
                          size: compact ? 12 : 13,
                          color: palette.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${rows.length}",
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              SizedBox(height: compact ? 4 : 6),
              if (tasks.isNotEmpty) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      size: compact ? 12 : 13,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "${tasks.length}",
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (tasks.any(_workspaceTaskHasStaffGap)) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.warning_amber_rounded,
                        size: compact ? 12 : 13,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ] else if (completed > 0) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.done_all_rounded,
                        size: compact ? 12 : 13,
                        color: ProductionCalendarVisuals.palette(
                          theme: theme,
                          taskCount: completed,
                          completedCount: completed,
                        ).accent,
                      ),
                    ],
                  ],
                ),
              ],
              if (showPreview && previewTaskTitle != null) ...[
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      palette.accent.withValues(alpha: 0.08),
                      theme.colorScheme.surface,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.spa_outlined,
                        size: 14,
                        color: palette.badgeForeground,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          previewTaskTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: previewStyle,
                        ),
                      ),
                    ],
                  ),
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
    const metricWidth = 168.0;
    return Wrap(
      spacing: _cardSpacing,
      runSpacing: _cardSpacing,
      children: [
        SizedBox(
          width: metricWidth,
          child: _WorkspaceDayMetricCard(
            label: _daySummaryTasksLabel,
            value: "${tasks.length}",
            accentColor: _workspaceBlue,
            softColor: _workspaceSoftBlue,
            icon: Icons.checklist_outlined,
          ),
        ),
        SizedBox(
          width: metricWidth,
          child: _WorkspaceDayMetricCard(
            label: _daySummaryAssignedLabel,
            value: "$assignedCount",
            accentColor: _workspaceTeal,
            softColor: _workspaceSoftTeal,
            icon: Icons.groups_2_outlined,
          ),
        ),
        SizedBox(
          width: metricWidth,
          child: _WorkspaceDayMetricCard(
            label: _daySummaryLoggedLabel,
            value: "${rows.length}",
            accentColor: _workspaceAmber,
            softColor: _workspaceSoftAmber,
            icon: Icons.edit_note_outlined,
          ),
        ),
        SizedBox(
          width: metricWidth,
          child: _WorkspaceDayMetricCard(
            label: _daySummaryDoneLabel,
            value: "$doneCount",
            accentColor: _workspaceBerry,
            softColor: _workspaceSoftBerry,
            icon: Icons.task_alt_outlined,
          ),
        ),
      ],
    );
  }
}

class _WorkspaceDayMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;
  final Color softColor;
  final IconData icon;

  const _WorkspaceDayMetricCard({
    required this.label,
    required this.value,
    this.accentColor = _workspaceBlue,
    this.softColor = _workspaceSoftBlue,
    this.icon = Icons.analytics_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            Color.alphaBlend(
              softColor.withValues(alpha: 0.92),
              colorScheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: _workspaceNavy,
                    fontWeight: FontWeight.w900,
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

class _AgendaTaskCard extends StatelessWidget {
  final ProductionTask task;
  final String phaseName;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final String currentActorStaffId;
  final Map<String, String> planUnitLabelById;
  final int fallbackTotalUnits;
  final String fallbackWorkUnitLabel;
  final String planContextText;
  final DateTime selectedDay;
  final List<ProductionAttendanceRecord> attendanceRecords;
  final List<ProductionTimelineRow> timelineRows;
  final List<ProductionTimelineRow> rowsForDay;
  final bool canManageCalendar;
  final bool canManageTaskAttendance;
  final bool canReviewProgress;
  final bool isOwner;
  final Set<String> progressEnabledStaffIds;
  final Future<void> Function()? onManageStaff;
  final Future<void> Function(
    String staffProfileId,
    ProductionAttendanceRecord? attendance,
  )?
  onSetAttendanceForStaff;
  final Future<void> Function(
    String staffProfileId,
    ProductionAttendanceRecord? attendance,
  )?
  onQuickClockInForStaff;
  final Future<void> Function(
    String staffProfileId,
    ProductionAttendanceRecord? attendance,
  )?
  onQuickClockOutForStaff;
  final Future<void> Function(String staffProfileId)? onLogProgressForStaff;
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
    required this.currentActorStaffId,
    required this.planUnitLabelById,
    required this.fallbackTotalUnits,
    required this.fallbackWorkUnitLabel,
    required this.planContextText,
    required this.selectedDay,
    required this.attendanceRecords,
    required this.timelineRows,
    required this.rowsForDay,
    required this.canManageCalendar,
    required this.canManageTaskAttendance,
    required this.canReviewProgress,
    required this.isOwner,
    required this.progressEnabledStaffIds,
    required this.onManageStaff,
    required this.onSetAttendanceForStaff,
    required this.onQuickClockInForStaff,
    required this.onQuickClockOutForStaff,
    required this.onLogProgressForStaff,
    required this.onStatusSelected,
    required this.onLogProgress,
    required this.onApproveTask,
    required this.onRejectTask,
    required this.onApproveProgress,
    required this.onRejectProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final assignedStaffIds = _resolveAssignedStaffIds(task);
    final assignedUnitIds = task.assignedUnitIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final effectiveWindow = _resolveEffectiveTaskWindow(task);
    final estimatedWindow = _formatTaskWindow(
      startDate: effectiveWindow.startDate,
      dueDate: effectiveWindow.dueDate,
    );
    final assignedUnitsLabel = _buildAssignedUnitLabel(
      assignedUnitIds: assignedUnitIds,
      planUnitLabelById: planUnitLabelById,
      fallbackWorkUnitLabel: fallbackWorkUnitLabel,
      contextText:
          "${task.title} ${task.instructions} ${task.taskType} $fallbackWorkUnitLabel",
    );
    final taskProgressSummary = _buildTaskUnitProgressSummary(
      task: task,
      timelineRows: rowsForDay,
      planUnitLabelById: planUnitLabelById,
      fallbackTotalUnits: fallbackTotalUnits,
      fallbackWorkUnitLabel: fallbackWorkUnitLabel,
      contextText: "$planContextText ${task.title} ${task.instructions}",
    );

    return Container(
      padding: const EdgeInsets.all(_agendaCardPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            Color.alphaBlend(
              _workspaceSoftSlate.withValues(alpha: 0.96),
              colorScheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _workspaceBlue.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: _workspaceNavy.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: _workspaceNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phaseName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
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
                label: "$_scheduleLabel: $estimatedWindow",
                icon: Icons.schedule_outlined,
                backgroundColor: _workspaceSoftBlue,
                foregroundColor: _workspaceBlue,
                borderColor: _workspaceBlue.withValues(alpha: 0.18),
              ),
              _InfoChip(
                label:
                    "$_roleLabel: ${formatStaffRoleLabel(task.roleRequired, fallback: task.roleRequired)} x${task.requiredHeadcount}",
                icon: Icons.shield_outlined,
                backgroundColor: _workspaceSoftBerry,
                foregroundColor: _workspaceBerry,
                borderColor: _workspaceBerry.withValues(alpha: 0.18),
              ),
              _InfoChip(
                label: "$_assignedLabel: ${assignedStaffIds.length}",
                icon: Icons.groups_outlined,
                backgroundColor: _workspaceSoftTeal,
                foregroundColor: _workspaceTeal,
                borderColor: _workspaceTeal.withValues(alpha: 0.18),
              ),
              if (assignedUnitsLabel != "-")
                _InfoChip(
                  label: "$_unitsLabel: $assignedUnitsLabel",
                  icon: Icons.grid_view_outlined,
                  backgroundColor: _workspaceSoftAmber,
                  foregroundColor: _workspaceAmber,
                  borderColor: _workspaceAmber.withValues(alpha: 0.18),
                ),
              _InfoChip(
                label: "$_logsLabel: ${rowsForDay.length}",
                icon: Icons.receipt_long_outlined,
                backgroundColor: _workspaceSoftSlate,
                foregroundColor: _workspaceNavy,
                borderColor: _workspaceNavy.withValues(alpha: 0.12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 680;
              final workingOnCard = _TaskSnapshotCard(
                label: _workingOnLabel,
                value: taskProgressSummary.workingOnLabel,
                helper: "Planned task scope for today",
                accentColor: _workspaceAmber,
                softColor: _workspaceSoftAmber,
                icon: Icons.event_note_outlined,
              );
              final doneTodayCard = _TaskSnapshotCard(
                label: _doneTodayLabel,
                value: taskProgressSummary.doneTodayLabel,
                helper: "Captured from today’s logs",
                accentColor: _workspaceTeal,
                softColor: _workspaceSoftTeal,
                icon: Icons.insights_outlined,
              );
              final leftTodayCard = _TaskSnapshotCard(
                label: _leftTodayLabel,
                value: taskProgressSummary.leftTodayLabel,
                helper: "Still open on this task today",
                accentColor: _workspaceBlue,
                softColor: _workspaceSoftBlue,
                icon: Icons.track_changes_outlined,
              );
              if (stacked) {
                return Column(
                  children: [
                    workingOnCard,
                    const SizedBox(height: 10),
                    doneTodayCard,
                    const SizedBox(height: 10),
                    leftTodayCard,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: workingOnCard),
                  const SizedBox(width: 10),
                  Expanded(child: doneTodayCard),
                  const SizedBox(width: 10),
                  Expanded(child: leftTodayCard),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: _workspaceBlue),
              const SizedBox(width: 8),
              Text(
                _assignedLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _workspaceNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
                final clockInAt = attendance?.clockInAt?.toLocal();
                final clockOutAt = attendance?.clockOutAt?.toLocal();
                final hasLoggedProgress = rowsForDay.any(
                  (row) => row.staffId == staffId,
                );
                final canClockOwnTaskAttendance =
                    currentActorStaffId.trim().isNotEmpty &&
                    currentActorStaffId.trim() == staffId.trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Builder(
                    builder: (context) {
                      final staffIdentity = _resolveStaffIdentity(
                        staffId,
                        staffMap,
                        fallbackRole: task.roleRequired,
                      );
                      return _AssignedStaffAttendanceRow(
                        staffName: staffIdentity.displayName,
                        staffRoleLabel: staffIdentity.roleLabel,
                        estimatedWindow: estimatedWindow,
                        clockInValue: _formatAttendanceTimeValue(
                          clockInAt,
                          emptyLabel: _attendanceClockInUnsetLabel,
                        ),
                        clockOutValue: clockOutAt != null
                            ? _clockLabel(clockOutAt)
                            : (clockInAt != null
                                  ? _attendanceClockOutPendingLabel
                                  : _attendanceClockOutUnsetLabel),
                        hasClockIn: attendance?.clockInAt != null,
                        hasClockOut: attendance?.clockOutAt != null,
                        canManageAttendance: canManageTaskAttendance,
                        canClockSelfAttendance:
                            !canManageTaskAttendance &&
                            currentActorStaffId.trim().isNotEmpty &&
                            currentActorStaffId.trim() == staffId.trim(),
                        canLogProgress:
                            progressEnabledStaffIds.contains(staffId) &&
                            (attendance?.clockInAt != null &&
                                attendance?.clockOutAt != null),
                        attendanceLockedForProgress:
                            progressEnabledStaffIds.contains(staffId) &&
                            !(attendance?.clockInAt != null &&
                                attendance?.clockOutAt != null),
                        hasLoggedProgress: hasLoggedProgress,
                        onQuickClockIn:
                            onQuickClockInForStaff != null &&
                                (canManageTaskAttendance ||
                                    canClockOwnTaskAttendance)
                            ? () => onQuickClockInForStaff!(staffId, attendance)
                            : null,
                        onQuickClockOut:
                            onQuickClockOutForStaff != null &&
                                (canManageTaskAttendance ||
                                    canClockOwnTaskAttendance)
                            ? () =>
                                  onQuickClockOutForStaff!(staffId, attendance)
                            : null,
                        onSetAttendance: onSetAttendanceForStaff == null
                            ? null
                            : () =>
                                  onSetAttendanceForStaff!(staffId, attendance),
                        onLogProgress:
                            onLogProgressForStaff == null ||
                                !progressEnabledStaffIds.contains(staffId) ||
                                !(attendance?.clockInAt != null &&
                                    attendance?.clockOutAt != null)
                            ? null
                            : () => onLogProgressForStaff!(staffId),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          if (task.instructions.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.notes_outlined, size: 18, color: _workspaceBerry),
                const SizedBox(width: 8),
                Text(
                  _instructionsLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: _workspaceNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
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
          Row(
            children: [
              Icon(Icons.timeline_outlined, size: 18, color: _workspaceTeal),
              const SizedBox(width: 8),
              Text(
                _activityLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _workspaceNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
                  expectedTargetAmount: taskProgressSummary.plannedAmount,
                  singularUnitLabel: taskProgressSummary.singularUnitLabel,
                  canReviewProgress: canReviewProgress,
                  onViewProof: row.proofs.isNotEmpty
                      ? () {
                          showProductionTaskProgressProofBrowser(
                            context,
                            rows: timelineRows,
                            initialDate: row.workDate,
                          );
                        }
                      : null,
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
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  const _InfoChip({
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedForeground = foregroundColor ?? colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: resolvedForeground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: resolvedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskSnapshotCard extends StatelessWidget {
  final String label;
  final String value;
  final String helper;
  final Color accentColor;
  final Color softColor;
  final IconData icon;

  const _TaskSnapshotCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.accentColor,
    required this.softColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accentColor.withValues(alpha: 0.16),
              colorScheme.surface,
            ),
            Color.alphaBlend(
              softColor.withValues(alpha: 0.98),
              colorScheme.surface,
            ),
            Color.alphaBlend(
              accentColor.withValues(alpha: 0.08),
              colorScheme.surfaceContainerHigh,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.34),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor,
                  Color.alphaBlend(
                    accentColor.withValues(alpha: 0.24),
                    _workspaceNavy,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: _workspaceNavy,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  helper,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _workspaceNavy.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
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

class _AssignedStaffAttendanceRow extends StatelessWidget {
  final String staffName;
  final String staffRoleLabel;
  final String estimatedWindow;
  final String clockInValue;
  final String clockOutValue;
  final bool hasClockIn;
  final bool hasClockOut;
  final bool canManageAttendance;
  final bool canClockSelfAttendance;
  final bool canLogProgress;
  final bool attendanceLockedForProgress;
  final bool hasLoggedProgress;
  final Future<void> Function()? onQuickClockIn;
  final Future<void> Function()? onQuickClockOut;
  final Future<void> Function()? onSetAttendance;
  final Future<void> Function()? onLogProgress;

  const _AssignedStaffAttendanceRow({
    required this.staffName,
    required this.staffRoleLabel,
    required this.estimatedWindow,
    required this.clockInValue,
    required this.clockOutValue,
    required this.hasClockIn,
    required this.hasClockOut,
    required this.canManageAttendance,
    required this.canClockSelfAttendance,
    required this.canLogProgress,
    required this.attendanceLockedForProgress,
    required this.hasLoggedProgress,
    required this.onQuickClockIn,
    required this.onQuickClockOut,
    required this.onSetAttendance,
    required this.onLogProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actualAccent = hasClockIn && hasClockOut
        ? _workspaceTeal
        : hasClockIn || hasClockOut
        ? _workspaceBlue
        : _workspaceNavy;
    final actualSoft = hasClockIn && hasClockOut
        ? _workspaceSoftTeal
        : hasClockIn || hasClockOut
        ? _workspaceSoftBlue
        : _workspaceSoftSlate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            Color.alphaBlend(
              _workspaceSoftSlate.withValues(alpha: 0.96),
              colorScheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: actualAccent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: actualAccent.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _workspaceSoftBlue,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person_outline, color: _workspaceBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staffName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _workspaceNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (staffRoleLabel.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        staffRoleLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if ((canManageAttendance || canClockSelfAttendance) &&
                      !hasClockIn &&
                      !hasClockOut &&
                      onQuickClockIn != null)
                    FilledButton.tonalIcon(
                      onPressed: onQuickClockIn,
                      icon: const Icon(Icons.login_outlined, size: 18),
                      label: const Text(_attendanceDialogClockInLabel),
                    ),
                  if ((canManageAttendance || canClockSelfAttendance) &&
                      hasClockIn &&
                      !hasClockOut &&
                      onQuickClockOut != null)
                    FilledButton.tonalIcon(
                      onPressed: onQuickClockOut,
                      icon: const Icon(Icons.logout_outlined, size: 18),
                      label: const Text(_attendanceDialogClockOutLabel),
                    ),
                  if (canManageAttendance && onSetAttendance != null)
                    OutlinedButton.icon(
                      onPressed: onSetAttendance,
                      icon: Icon(
                        hasClockIn || hasClockOut
                            ? Icons.edit_calendar_outlined
                            : Icons.schedule_outlined,
                        size: 18,
                      ),
                      label: Text(
                        hasClockIn || hasClockOut
                            ? _editAttendanceLabel
                            : _setAttendanceLabel,
                      ),
                    ),
                  if (canLogProgress)
                    FilledButton.tonalIcon(
                      onPressed: onLogProgress,
                      icon: Icon(
                        hasLoggedProgress
                            ? Icons.edit_note_outlined
                            : Icons.playlist_add_check_circle_outlined,
                        size: 18,
                      ),
                      label: Text(
                        hasLoggedProgress
                            ? _editProgressLabel
                            : _logProgressLabel,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 820;
              final estimatedCard = _AttendanceTimingCard(
                label: _estimatedDatesLabel,
                value: estimatedWindow,
                accentColor: _workspaceAmber,
                softColor: _workspaceSoftAmber,
                icon: Icons.event_outlined,
              );
              final clockInCard = _AttendanceTimingCard(
                label: _clockedInLabel,
                value: clockInValue,
                accentColor: hasClockIn ? _workspaceTeal : _workspaceBlue,
                softColor: hasClockIn ? _workspaceSoftTeal : _workspaceSoftBlue,
                icon: Icons.login_outlined,
              );
              final clockOutCard = _AttendanceTimingCard(
                label: _clockedOutLabel,
                value: clockOutValue,
                accentColor: hasClockOut
                    ? _workspaceBerry
                    : (hasClockIn ? _workspaceBlue : _workspaceNavy),
                softColor: hasClockOut
                    ? _workspaceSoftBerry
                    : (hasClockIn ? _workspaceSoftBlue : _workspaceSoftSlate),
                icon: hasClockOut
                    ? Icons.logout_outlined
                    : (hasClockIn
                          ? Icons.timelapse_outlined
                          : Icons.pending_outlined),
              );
              if (stacked) {
                return Column(
                  children: [
                    estimatedCard,
                    const SizedBox(height: 10),
                    clockInCard,
                    const SizedBox(height: 10),
                    clockOutCard,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: estimatedCard),
                  const SizedBox(width: 10),
                  Expanded(child: clockInCard),
                  const SizedBox(width: 10),
                  Expanded(child: clockOutCard),
                ],
              );
            },
          ),
          if (attendanceLockedForProgress) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _workspaceSoftAmber,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _workspaceAmber.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: _workspaceAmber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _taskProgressAttendanceRequired,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _workspaceAmber,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                actualSoft.withValues(alpha: 0.92),
                colorScheme.surface,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: actualAccent.withValues(alpha: 0.14)),
            ),
            child: Text(
              hasClockIn && hasClockOut
                  ? _attendanceReadyForProgressHint
                  : hasClockIn
                  ? _attendanceShiftOpenHint
                  : _attendanceNotStartedHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: actualAccent,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceTimingCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;
  final Color softColor;
  final IconData icon;

  const _AttendanceTimingCard({
    required this.label,
    required this.value,
    required this.accentColor,
    required this.softColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            Color.alphaBlend(
              softColor.withValues(alpha: 0.96),
              colorScheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accentColor.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _workspaceNavy,
                    fontWeight: FontWeight.w900,
                    height: 1.3,
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

class _TimelineLogRow extends StatelessWidget {
  final ProductionTimelineRow row;
  final num expectedTargetAmount;
  final String singularUnitLabel;
  final bool canReviewProgress;
  final VoidCallback? onViewProof;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _TimelineLogRow({
    required this.row,
    required this.expectedTargetAmount,
    required this.singularUnitLabel,
    required this.canReviewProgress,
    required this.onViewProof,
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
                icon: Icons.person_outline,
                backgroundColor: _workspaceSoftBlue,
                foregroundColor: _workspaceBlue,
                borderColor: _workspaceBlue.withValues(alpha: 0.16),
              ),
              _InfoChip(
                label:
                    "$_expectedLabel: ${_formatProgressAmountWithUnit(amount: expectedTargetAmount, singularUnitLabel: singularUnitLabel)}",
                icon: Icons.event_outlined,
                backgroundColor: _workspaceSoftAmber,
                foregroundColor: _workspaceAmber,
                borderColor: _workspaceAmber.withValues(alpha: 0.16),
              ),
              _InfoChip(
                label:
                    "$_actualLabel: ${_formatProgressAmountWithUnit(amount: row.actualPlots, singularUnitLabel: singularUnitLabel)}",
                icon: Icons.insights_outlined,
                backgroundColor: _workspaceSoftTeal,
                foregroundColor: _workspaceTeal,
                borderColor: _workspaceTeal.withValues(alpha: 0.16),
              ),
              _InfoChip(
                label:
                    "$_approvalLabel: ${_formatProgressApproval(row.approvalState)}",
                icon: Icons.verified_user_outlined,
                backgroundColor: _workspaceSoftBerry,
                foregroundColor: _workspaceBerry,
                borderColor: _workspaceBerry.withValues(alpha: 0.16),
              ),
              if (row.proofs.isNotEmpty)
                _InfoChip(
                  label: "${row.proofCount} proof(s)",
                  icon: Icons.photo_library_outlined,
                  backgroundColor: _workspaceSoftSlate,
                  foregroundColor: _workspaceNavy,
                  borderColor: _workspaceNavy.withValues(alpha: 0.12),
                ),
              if (row.quantityAmount > 0 &&
                  row.quantityActivityType.trim().isNotEmpty &&
                  row.quantityActivityType != _quantityActivityNone)
                _InfoChip(
                  label:
                      "${_formatQuantityActivityLabel(row.quantityActivityType)}: ${_formatProgressAmount(row.quantityAmount)} ${row.quantityUnit}",
                  icon: Icons.agriculture_outlined,
                  backgroundColor: _workspaceSoftSlate,
                  foregroundColor: _workspaceNavy,
                  borderColor: _workspaceNavy.withValues(alpha: 0.12),
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
          if (row.proofs.isNotEmpty && onViewProof != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onViewProof,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text(_viewProofLabel),
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
  final List<ProductionTaskProgressProofInput> proofs;
  final String quantityActivityType;
  final num quantityAmount;
  final String quantityUnit;
  final String delayReason;
  final String notes;

  const _WorkspaceLogProgressInput({
    required this.staffId,
    required this.unitId,
    required this.actualPlots,
    required this.proofs,
    required this.quantityActivityType,
    required this.quantityAmount,
    required this.quantityUnit,
    required this.delayReason,
    required this.notes,
  });
}

class _FarmQuantitySummary {
  final String plantingUnit;
  final String harvestUnit;
  final num plantingLogged;
  final num transplantLogged;
  final num harvestLogged;
  final num plantingRemaining;
  final num transplantRemaining;
  final num harvestRemaining;

  const _FarmQuantitySummary({
    required this.plantingUnit,
    required this.harvestUnit,
    required this.plantingLogged,
    required this.transplantLogged,
    required this.harvestLogged,
    required this.plantingRemaining,
    required this.transplantRemaining,
    required this.harvestRemaining,
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
  required _WorkspaceWorkScopeSummary workScopeSummary,
}) {
  return "${_formatCalendarDate(day)} • $taskCount tasks • $logCount logs • ${workScopeSummary.countLabel}";
}

_WorkspaceWorkScopeSummary _resolveWorkspaceWorkScopeSummary({
  required ProductionPlan plan,
  ProductionPlanUnitsResponse? planUnitsResponse,
}) {
  final workloadContext = plan.workloadContext;
  final explicitLabel = workloadContext?.resolvedWorkUnitLabel.trim() ?? "";
  final inferredLabel = _resolveWorkspaceUnitStemFromPlanUnits(
    planUnitsResponse?.units ?? const <ProductionPlanUnit>[],
  );
  final preferredContextLabel = _resolvePreferredProgressUnitStem(
    fallbackWorkUnitLabel: explicitLabel,
    contextText: "${plan.title} ${plan.notes}",
  );
  final baseUnitLabel = inferredLabel.isNotEmpty
      ? preferredContextLabel.isNotEmpty
            ? preferredContextLabel
            : inferredLabel
      : preferredContextLabel.isNotEmpty
      ? preferredContextLabel
      : explicitLabel.isNotEmpty
      ? explicitLabel
      : "work unit";
  final workloadUnits = workloadContext?.totalWorkUnits ?? 0;
  final responseUnits = planUnitsResponse?.totalUnits ?? 0;
  final totalUnits = responseUnits > 0
      ? responseUnits
      : workloadUnits > 0
      ? workloadUnits
      : (planUnitsResponse?.units.length ?? 0);
  return _WorkspaceWorkScopeSummary(
    totalUnits: totalUnits < 0 ? 0 : totalUnits,
    baseUnitLabel: baseUnitLabel,
  );
}

String _resolveWorkspaceUnitStemFromPlanUnits(
  List<ProductionPlanUnit> planUnits,
) {
  final stems =
      planUnits
          .map((unit) => _extractUnitStem(unit.label))
          .where((stem) => stem.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  if (stems.length == 1) {
    return stems.first;
  }
  return "";
}

String _normalizeWorkspaceUnitLabel(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? "work unit" : normalized;
}

String _pluralizeWorkspaceUnitLabel(String value) {
  final normalized = _normalizeWorkspaceUnitLabel(value);
  if (normalized.toLowerCase().endsWith("s")) {
    return normalized;
  }
  return _pluralizeUnitPhrase(normalized);
}

String _capitalizeWorkspaceLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  return "${normalized[0].toUpperCase()}${normalized.substring(1)}";
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

String _inferProductNameFromPlanTitle(String title) {
  var normalizedTitle = title.trim();
  normalizedTitle = normalizedTitle.replaceAll(
    RegExp(r"\s+production\s+plan$", caseSensitive: false),
    "",
  );
  normalizedTitle = normalizedTitle.replaceAll(
    RegExp(r"\s+plan$", caseSensitive: false),
    "",
  );
  return normalizedTitle.trim();
}

String _formatProductionQuantity(num value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.0001) {
    return rounded.toInt().toString();
  }
  return value.toStringAsFixed(value.abs() >= 100 ? 1 : 2);
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
  final effectiveWindow = _resolveEffectiveTaskWindow(task);
  final taskStart = effectiveWindow.startDate != null
      ? _toDayStart(effectiveWindow.startDate!)
      : monthStart;
  final taskEnd = effectiveWindow.dueDate != null
      ? _toDayStart(effectiveWindow.dueDate!)
      : taskStart;
  return !taskEnd.isBefore(monthStart) && taskStart.isBefore(nextMonthStart);
}

List<ProductionTask> _tasksForDay(List<ProductionTask> tasks, DateTime day) {
  final items = tasks.where((task) {
    return _isTaskScheduledForDate(task: task, workDate: day);
  }).toList();
  items.sort((left, right) {
    final leftWindow = _resolveEffectiveTaskWindow(left);
    final rightWindow = _resolveEffectiveTaskWindow(right);
    final leftStart = leftWindow.startDate ?? leftWindow.dueDate ?? day;
    final rightStart = rightWindow.startDate ?? rightWindow.dueDate ?? day;
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

ProductionAttendanceRecord _toProductionAttendanceRecord(
  StaffAttendanceRecord record,
) {
  final computedDurationMinutes = record.clockOutAt != null
      ? record.clockOutAt!.difference(record.clockInAt).inMinutes
      : 0;
  return ProductionAttendanceRecord(
    id: record.id,
    staffProfileId: record.staffProfileId,
    clockInAt: record.clockInAt,
    clockOutAt: record.clockOutAt,
    durationMinutes: record.durationMinutes ?? computedDurationMinutes,
    notes: record.notes ?? "",
    createdAt: record.createdAt,
    proofUrl: record.proofUrl,
    proofPublicId: record.proofPublicId,
    proofFilename: record.proofFilename,
    proofMimeType: record.proofMimeType,
    proofSizeBytes: record.proofSizeBytes,
    proofUploadedAt: record.proofUploadedAt,
    proofUploadedBy: record.proofUploadedBy,
  );
}

Map<String, BusinessStaffProfileSummary> _buildStaffMap(
  List<BusinessStaffProfileSummary> staff,
) {
  final map = <String, BusinessStaffProfileSummary>{};
  for (final member in staff) {
    final profileId = member.id.trim();
    if (profileId.isNotEmpty) {
      map[profileId] = member;
    }
    final userId = member.userId.trim();
    if (userId.isNotEmpty) {
      map[userId] = member;
    }
  }
  return map;
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

String _resolveSelfStaffId({
  required List<BusinessStaffProfileSummary> staffList,
  required String? userEmail,
}) {
  if (userEmail == null) {
    return "";
  }
  final normalizedEmail = userEmail.toLowerCase().trim();
  if (normalizedEmail.isEmpty) {
    return "";
  }
  for (final profile in staffList) {
    final profileEmail = (profile.userEmail ?? "").toLowerCase().trim();
    if (profileEmail.isNotEmpty && profileEmail == normalizedEmail) {
      return profile.id.trim();
    }
  }
  return "";
}

bool _canReviewProgress({
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

bool _canManagePlanLifecycle({
  required String? actorRole,
  required String? staffRole,
}) {
  if (actorRole == "business_owner") {
    return true;
  }
  return actorRole == "staff" && staffRole == staffRoleEstateManager;
}

String _resolveProductionWorkspaceErrorMessage(
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

DateTime _toDayStart(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

bool _isTaskScheduledForDate({
  required ProductionTask task,
  required DateTime workDate,
}) {
  final normalizedWorkDate = _toDayStart(workDate);
  final effectiveWindow = _resolveEffectiveTaskWindow(task);
  final startDate = effectiveWindow.startDate;
  final dueDate = effectiveWindow.dueDate;
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

DateTime? _resolveImportedPinnedDay(ProductionTask task) {
  // WHY: Imported PDF tasks carry their canonical work date inside the
  // instructions body. Use that as the single source of truth when present so
  // the workspace agenda reflects the authored draft instead of a broad phase
  // span left over from scheduling.
  final sourceTemplateKey = task.sourceTemplateKey.trim().toLowerCase();
  if (!sourceTemplateKey.startsWith("imported_source_day_")) {
    return null;
  }
  final match = _importedProjectDayPattern.firstMatch(task.instructions);
  final isoDate = match?.group(1)?.trim() ?? "";
  if (isoDate.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

({DateTime? startDate, DateTime? dueDate}) _resolveEffectiveTaskWindow(
  ProductionTask task,
) {
  final pinnedImportedDay = _resolveImportedPinnedDay(task);
  if (pinnedImportedDay != null) {
    return (startDate: pinnedImportedDay, dueDate: pinnedImportedDay);
  }
  return (startDate: task.startDate, dueDate: task.dueDate);
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

bool _workspaceTaskHasStaffGap(ProductionTask task) {
  final assignedCount = _resolveAssignedStaffIds(task).length;
  final requiredHeadcount = task.requiredHeadcount < 1
      ? 1
      : task.requiredHeadcount;
  return assignedCount < requiredHeadcount;
}

String _resolveStaffDisplayLabel(
  String staffId,
  Map<String, BusinessStaffProfileSummary> staffMap, {
  String fallbackRole = "",
}) {
  final identity = _resolveStaffIdentity(
    staffId,
    staffMap,
    fallbackRole: fallbackRole,
  );
  if (identity.roleLabel.trim().isEmpty) {
    return identity.displayName;
  }
  return "${identity.displayName} • ${identity.roleLabel}";
}

class _WorkspaceStaffIdentity {
  final String displayName;
  final String roleLabel;

  const _WorkspaceStaffIdentity({
    required this.displayName,
    required this.roleLabel,
  });
}

_WorkspaceStaffIdentity _resolveStaffIdentity(
  String staffId,
  Map<String, BusinessStaffProfileSummary> staffMap, {
  String fallbackRole = "",
}) {
  final normalizedStaffId = staffId.trim();
  final profile = staffMap[normalizedStaffId];
  final displayName =
      _staffListLabel(profile) ??
      (_looksLikeOpaqueId(normalizedStaffId)
          ? _assignedStaffFallbackLabel
          : normalizedStaffId);
  final resolvedRole = profile == null
      ? (fallbackRole.trim().isEmpty
            ? ""
            : formatStaffRoleLabel(fallbackRole, fallback: fallbackRole))
      : formatStaffRoleLabel(profile.staffRole, fallback: profile.staffRole);
  if (profile == null) {
    return _WorkspaceStaffIdentity(
      displayName: displayName,
      roleLabel: resolvedRole,
    );
  }
  return _WorkspaceStaffIdentity(
    displayName: displayName,
    roleLabel: resolvedRole,
  );
}

bool _looksLikeOpaqueId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r"^[a-f0-9]{24}$", caseSensitive: false).hasMatch(normalized);
}

String _buildAssignedUnitLabel({
  required List<String> assignedUnitIds,
  required Map<String, String> planUnitLabelById,
  String fallbackWorkUnitLabel = "",
  String contextText = "",
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
        if (!planUnitLabelById.containsKey(normalized) &&
            RegExp(
              r"^[a-f0-9]{24}$",
              caseSensitive: false,
            ).hasMatch(normalized)) {
          return "";
        }
        return _normalizeProgressUnitDisplayLabel(
          planUnitLabelById[normalized] ?? normalized,
          fallbackWorkUnitLabel: fallbackWorkUnitLabel,
          contextText: contextText,
        );
      })
      .where((label) => label.isNotEmpty)
      .toList();
  if (labels.isEmpty) {
    return "-";
  }
  return labels.join(", ");
}

List<String> _resolveAssignedUnitLabels({
  required List<String> assignedUnitIds,
  required Map<String, String> planUnitLabelById,
  String fallbackWorkUnitLabel = "",
  String contextText = "",
}) {
  return assignedUnitIds
      .map((unitId) {
        final normalized = unitId.trim();
        if (normalized.isEmpty) {
          return "";
        }
        if (!planUnitLabelById.containsKey(normalized) &&
            RegExp(
              r"^[a-f0-9]{24}$",
              caseSensitive: false,
            ).hasMatch(normalized)) {
          return "";
        }
        return _normalizeProgressUnitDisplayLabel(
          planUnitLabelById[normalized] ?? normalized,
          fallbackWorkUnitLabel: fallbackWorkUnitLabel,
          contextText: contextText,
        );
      })
      .where((label) => label.isNotEmpty)
      .toList();
}

bool _looksLikeUnitIdentifierToken(String token) {
  final normalized = token.trim().replaceAll("#", "");
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r"^[A-Za-z]?\d+[A-Za-z]?$").hasMatch(normalized) ||
      RegExp(r"^[A-Za-z]$").hasMatch(normalized);
}

String _extractUnitStem(String label) {
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
  while (tokens.length > 1 && _looksLikeUnitIdentifierToken(tokens.last)) {
    tokens.removeLast();
  }
  final stem = tokens.join(" ").trim().toLowerCase();
  return stem.isEmpty ? normalized.toLowerCase() : stem;
}

String _pluralizeWord(String value) {
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

String _pluralizeUnitPhrase(String value) {
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
  tokens.add(_pluralizeWord(lastToken));
  return tokens.join(" ");
}

String _resolveProgressUnitSingularLabel({
  required List<String> assignedUnitIds,
  required Map<String, String> planUnitLabelById,
  required String? selectedUnitId,
  String fallbackWorkUnitLabel = "",
  String contextText = "",
}) {
  final preferredFallbackStem = _resolvePreferredProgressUnitStem(
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText: contextText,
  );
  final selectedUnitLabel = _normalizeProgressUnitDisplayLabel(
    (selectedUnitId != null && selectedUnitId.trim().isNotEmpty)
        ? (planUnitLabelById[selectedUnitId.trim()] ?? selectedUnitId.trim())
        : "",
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText: contextText,
  );
  final selectedStem = _extractUnitStem(selectedUnitLabel);
  if (selectedStem.isNotEmpty) {
    return _isGenericProgressUnitStem(selectedStem) &&
            preferredFallbackStem.isNotEmpty
        ? preferredFallbackStem
        : selectedStem;
  }
  final labels = _resolveAssignedUnitLabels(
    assignedUnitIds: assignedUnitIds,
    planUnitLabelById: planUnitLabelById,
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText: contextText,
  );
  final stems = labels
      .map(_extractUnitStem)
      .where((stem) => stem.isNotEmpty)
      .toSet();
  if (stems.length == 1) {
    final onlyStem = stems.first;
    return _isGenericProgressUnitStem(onlyStem) &&
            preferredFallbackStem.isNotEmpty
        ? preferredFallbackStem
        : onlyStem;
  }
  if (labels.length == 1) {
    final labelStem = _extractUnitStem(labels.first);
    if (labelStem.isNotEmpty) {
      return _isGenericProgressUnitStem(labelStem) &&
              preferredFallbackStem.isNotEmpty
          ? preferredFallbackStem
          : labelStem;
    }
  }
  if (preferredFallbackStem.isNotEmpty) {
    return preferredFallbackStem;
  }
  return "work unit";
}

bool _isGenericProgressUnitStem(String value) {
  final normalized = _extractUnitStem(value);
  return normalized.isEmpty ||
      normalized == "plot" ||
      normalized == "unit" ||
      normalized == "work unit";
}

String _resolvePreferredProgressUnitStem({
  required String fallbackWorkUnitLabel,
  String contextText = "",
}) {
  final inferredStem = _inferProgressUnitStemFromContext(
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText: contextText,
  );
  if (!_isGenericProgressUnitStem(inferredStem)) {
    return inferredStem;
  }
  final fallbackStem = _extractUnitStem(fallbackWorkUnitLabel);
  if (!_isGenericProgressUnitStem(fallbackStem)) {
    return fallbackStem;
  }
  return "";
}

String _normalizeProgressUnitDisplayLabel(
  String label, {
  String fallbackWorkUnitLabel = "",
  String contextText = "",
}) {
  final normalized = label
      .trim()
      .replaceAll(RegExp(r"[_-]+"), " ")
      .replaceAll(RegExp(r"\s+"), " ");
  final preferredStem = _resolvePreferredProgressUnitStem(
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText: contextText,
  );
  if (normalized.isEmpty || preferredStem.isEmpty) {
    return normalized;
  }
  final currentStem = _extractUnitStem(normalized);
  if (!_isGenericProgressUnitStem(currentStem)) {
    return normalized;
  }
  final labelTokens = normalized
      .split(" ")
      .where((token) => token.isNotEmpty)
      .toList();
  final stemTokens = currentStem
      .split(" ")
      .where((token) => token.isNotEmpty)
      .toList();
  final suffixTokens = labelTokens.length > stemTokens.length
      ? labelTokens.sublist(stemTokens.length)
      : const <String>[];
  final preferredLabel = _titleCaseProgressUnitLabel(preferredStem);
  if (suffixTokens.isEmpty) {
    return preferredLabel;
  }
  return "$preferredLabel ${suffixTokens.join(' ')}";
}

String _titleCaseProgressUnitLabel(String value) {
  return value
      .split(" ")
      .where((token) => token.isNotEmpty)
      .map(
        (token) =>
            "${token[0].toUpperCase()}${token.length > 1 ? token.substring(1) : ''}",
      )
      .join(" ");
}

String _inferProgressUnitStemFromContext({
  required String fallbackWorkUnitLabel,
  String contextText = "",
}) {
  final normalizedFallback = _extractUnitStem(fallbackWorkUnitLabel);
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
  if (fallbackIsGeneric &&
      (normalizedContext.contains("man hour") ||
          normalizedContext.contains("man-hour") ||
          normalizedContext.contains("labour hour") ||
          normalizedContext.contains("labor hour") ||
          normalizedContext.contains("work hour") ||
          normalizedContext.contains("hours"))) {
    return "hour";
  }
  return "";
}

String _formatProgressAmountWithUnit({
  required num amount,
  required String singularUnitLabel,
}) {
  final normalizedUnit = singularUnitLabel.trim().isEmpty
      ? "work unit"
      : singularUnitLabel.trim();
  final unitLabel = _sameProgressAmount(amount, 1)
      ? normalizedUnit
      : _pluralizeUnitPhrase(normalizedUnit);
  return "${_formatProgressAmount(amount)} $unitLabel";
}

String _buildProgressWorkflowHint({required String singularUnitLabel}) {
  final pluralUnitLabel = _pluralizeUnitPhrase(
    singularUnitLabel.trim().isEmpty ? "work unit" : singularUnitLabel.trim(),
  );
  return "Select only what one assigned staff actually completed on this date. The combined total cannot go above the planned task target. Example: if 6 $pluralUnitLabel are planned and Aisha completed 2.5, pick 2.5 here.";
}

String _buildProgressActualLabel({required String singularUnitLabel}) {
  final pluralUnitLabel = _pluralizeUnitPhrase(
    singularUnitLabel.trim().isEmpty ? "work unit" : singularUnitLabel.trim(),
  );
  return "Actual $pluralUnitLabel this staff completed today";
}

String _buildProgressNotesHint({required String singularUnitLabel}) {
  final pluralUnitLabel = _pluralizeUnitPhrase(
    singularUnitLabel.trim().isEmpty ? "work unit" : singularUnitLabel.trim(),
  );
  return "Example: completed 2.7 $pluralUnitLabel and noted any follow-up issues.";
}

bool _supportsFarmQuantityTracking(ProductionPlan plan) {
  return productionDomainRequiresPlantingTargets(plan.domainContext) &&
      plan.plantingTargets?.isConfigured == true;
}

String _formatQuantityActivityLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case _quantityActivityPlanting:
      return "Planted";
    case _quantityActivityTransplant:
      return "Transplanted";
    case _quantityActivityHarvest:
      return "Harvested";
    default:
      return "Quantity";
  }
}

num _sumQuantityForActivity({
  required List<ProductionTimelineRow> timelineRows,
  required String activityType,
}) {
  return timelineRows
      .where(
        (row) =>
            row.quantityActivityType.trim() == activityType &&
            row.approvalState != "needs_review",
      )
      .fold<num>(0, (sum, row) => sum + row.quantityAmount);
}

_FarmQuantitySummary? _summarizeFarmQuantities({
  required ProductionPlan plan,
  required List<ProductionTimelineRow> timelineRows,
}) {
  final plantingTargets = plan.plantingTargets;
  if (!_supportsFarmQuantityTracking(plan) || plantingTargets == null) {
    return null;
  }
  final plantingLogged = _sumQuantityForActivity(
    timelineRows: timelineRows,
    activityType: _quantityActivityPlanting,
  );
  final transplantLogged = _sumQuantityForActivity(
    timelineRows: timelineRows,
    activityType: _quantityActivityTransplant,
  );
  final harvestLogged = _sumQuantityForActivity(
    timelineRows: timelineRows,
    activityType: _quantityActivityHarvest,
  );
  return _FarmQuantitySummary(
    plantingUnit: plantingTargets.plannedPlantingUnit,
    harvestUnit: plantingTargets.estimatedHarvestUnit,
    plantingLogged: plantingLogged,
    transplantLogged: transplantLogged,
    harvestLogged: harvestLogged,
    plantingRemaining: math.max(
      0,
      plantingTargets.plannedPlantingQuantity - plantingLogged,
    ),
    transplantRemaining: math.max(
      0,
      plantingTargets.plannedPlantingQuantity - transplantLogged,
    ),
    harvestRemaining: math.max(
      0,
      plantingTargets.estimatedHarvestQuantity - harvestLogged,
    ),
  );
}

String _suggestQuantityActivityType(ProductionTask task) {
  final text = "${task.title} ${task.instructions} ${task.taskType}"
      .toLowerCase();
  if (text.contains("harvest")) {
    return _quantityActivityHarvest;
  }
  if (text.contains("transplant")) {
    return _quantityActivityTransplant;
  }
  if (text.contains("nursery") ||
      text.contains("seed") ||
      text.contains("seedling") ||
      text.contains("sow") ||
      text.contains("plant")) {
    return _quantityActivityPlanting;
  }
  return _quantityActivityNone;
}

num _resolveTaskProgressTargetAmount({
  required ProductionTask task,
  required List<String> assignedUnitIds,
  int fallbackTotalUnits = 0,
}) {
  final unitTarget = assignedUnitIds.length;
  final fallbackUnitTarget = fallbackTotalUnits > 0 ? fallbackTotalUnits : 0;
  final weightTarget = task.weight < 1 ? 1 : task.weight;
  if (unitTarget > 0) {
    return math.max(weightTarget.toDouble(), unitTarget.toDouble());
  }
  if (fallbackUnitTarget > 0) {
    return math.max(weightTarget.toDouble(), fallbackUnitTarget.toDouble());
  }
  return weightTarget.toDouble();
}

_TaskUnitProgressSummary _buildTaskUnitProgressSummary({
  required ProductionTask task,
  required List<ProductionTimelineRow> timelineRows,
  required Map<String, String> planUnitLabelById,
  int fallbackTotalUnits = 0,
  String fallbackWorkUnitLabel = "",
  String contextText = "",
  String? selectedUnitId,
}) {
  final assignedUnitIds = task.assignedUnitIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  final plannedAmount = _resolveTaskProgressTargetAmount(
    task: task,
    assignedUnitIds: assignedUnitIds,
    fallbackTotalUnits: fallbackTotalUnits,
  );
  final loggedAmount = timelineRows.fold<num>(
    0,
    (sum, row) => sum + row.actualPlots,
  );
  final singularUnitLabel = _resolveProgressUnitSingularLabel(
    assignedUnitIds: assignedUnitIds,
    planUnitLabelById: planUnitLabelById,
    selectedUnitId: selectedUnitId,
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText:
        "$contextText ${task.title} ${task.instructions} ${task.taskType} $fallbackWorkUnitLabel",
  );
  return _TaskUnitProgressSummary(
    singularUnitLabel: singularUnitLabel,
    plannedAmount: plannedAmount,
    loggedAmount: loggedAmount,
  );
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

List<num> _buildQuantityAmountOptions({required num maxAmount}) {
  final normalizedMax = maxAmount <= 0 ? 0.0 : maxAmount.toDouble();
  if (normalizedMax <= 12) {
    final values = List<num>.generate(
      normalizedMax.floor() + 1,
      (index) => index.toDouble(),
    );
    if (!_sameProgressAmount(values.last, normalizedMax)) {
      values.add(normalizedMax);
    }
    return values;
  }
  final values = <num>{0};
  var scale = 1.0;
  while (scale <= normalizedMax) {
    for (final seed in const <double>[1, 2, 5]) {
      final nextValue = seed * scale;
      if (nextValue <= normalizedMax) {
        values.add(nextValue);
      }
    }
    scale *= 10;
  }
  values.add(normalizedMax);
  final ordered = values.toList()..sort((left, right) => left.compareTo(right));
  return ordered;
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
  String fallbackWorkUnitLabel = "",
  String contextText = "",
}) {
  final selectedUnitLabel = _normalizeProgressUnitDisplayLabel(
    (selectedUnitId != null && selectedUnitId.trim().isNotEmpty)
        ? (planUnitLabelById[selectedUnitId.trim()] ?? selectedUnitId.trim())
        : "",
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText: contextText,
  );
  final singularUnitLabel = _resolveProgressUnitSingularLabel(
    assignedUnitIds: assignedUnitIds,
    planUnitLabelById: planUnitLabelById,
    selectedUnitId: selectedUnitId,
    fallbackWorkUnitLabel: fallbackWorkUnitLabel,
    contextText: contextText,
  );
  final pluralUnitLabel = _pluralizeUnitPhrase(singularUnitLabel);
  final targetLabel = _formatProgressAmountWithUnit(
    amount: targetAmount,
    singularUnitLabel: singularUnitLabel,
  );
  final loggedLabel = _formatProgressAmountWithUnit(
    amount: loggedAmount,
    singularUnitLabel: singularUnitLabel,
  );
  final remainingLabel = _formatProgressAmountWithUnit(
    amount: remainingAmount,
    singularUnitLabel: singularUnitLabel,
  );
  if (selectedUnitLabel.isNotEmpty) {
    return "Pick only what this one staff completed today. Planned target: $targetLabel. Already logged: $loggedLabel. Remaining now: $remainingLabel. Selected $singularUnitLabel: $selectedUnitLabel.";
  }
  if (assignedUnitIds.isNotEmpty) {
    final assignedUnitsLabel = _buildAssignedUnitLabel(
      assignedUnitIds: assignedUnitIds,
      planUnitLabelById: planUnitLabelById,
      fallbackWorkUnitLabel: fallbackWorkUnitLabel,
      contextText: contextText,
    );
    return "Pick only what this one staff completed today. Planned target: $targetLabel. Already logged: $loggedLabel. Remaining now: $remainingLabel. Assigned $pluralUnitLabel: $assignedUnitsLabel.";
  }
  return "Pick only what this one staff completed today. Planned target: $targetLabel. Already logged: $loggedLabel. Remaining now: $remainingLabel.";
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

String? _staffListLabel(BusinessStaffProfileSummary? staff) {
  if (staff == null) {
    return null;
  }
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

String _formatTaskWindow({
  required DateTime? startDate,
  required DateTime? dueDate,
}) {
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

String _clockLabel(DateTime value) {
  final hour = value.hour.toString().padLeft(2, "0");
  final minute = value.minute.toString().padLeft(2, "0");
  return "$hour:$minute";
}

String _formatAttendanceTimeValue(
  DateTime? value, {
  required String emptyLabel,
}) {
  if (value == null) {
    return emptyLabel;
  }
  return _clockLabel(value);
}

DateTime _mergeDateAndTime(DateTime day, TimeOfDay time) {
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

DateTime _resolveQuickAttendanceTime(DateTime workDate) {
  final now = DateTime.now();
  return DateTime(
    workDate.year,
    workDate.month,
    workDate.day,
    now.hour,
    now.minute,
  );
}

DateTime _resolveQuickClockOutTime({
  required DateTime workDate,
  required DateTime clockInAt,
}) {
  final quickCandidate = _resolveQuickAttendanceTime(workDate);
  if (quickCandidate.isAfter(clockInAt)) {
    return quickCandidate;
  }
  return clockInAt.add(const Duration(minutes: 1));
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
                        title: Text(_staffListLabel(staff) ?? staff.id),
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
  required ProductionPlan plan,
  required List<ProductionTimelineRow> timelineRows,
  required List<ProductionAttendanceRecord> attendanceRecords,
  required Map<String, BusinessStaffProfileSummary> staffMap,
  required Map<String, String> planUnitLabelById,
  required int fallbackTotalUnits,
  required String fallbackWorkUnitLabel,
  String? actorStaffId,
  required bool canPickAnyAssignedStaff,
  required bool canManageAttendance,
  Future<ProductionAttendanceRecord?> Function(
    String staffProfileId,
    ProductionAttendanceRecord? existingAttendance,
  )?
  onSetAttendanceForStaff,
  Future<ProductionAttendanceRecord?> Function(
    String staffProfileId,
    ProductionAttendanceRecord? existingAttendance,
  )?
  onQuickClockInForStaff,
  Future<ProductionAttendanceRecord?> Function(
    String staffProfileId,
    ProductionAttendanceRecord? existingAttendance,
  )?
  onQuickClockOutForStaff,
}) async {
  final assignedStaffIds = _resolveAssignedStaffIds(task);
  if (assignedStaffIds.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_taskProgressNeedsAssignedStaff)),
    );
    return null;
  }
  final assignedUnitIds = task.assignedUnitIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  final normalizedActorStaffId = actorStaffId?.trim() ?? "";
  String? selectedStaffId =
      !canPickAnyAssignedStaff &&
          normalizedActorStaffId.isNotEmpty &&
          assignedStaffIds.contains(normalizedActorStaffId)
      ? normalizedActorStaffId
      : (assignedStaffIds.isNotEmpty ? assignedStaffIds.first : null);
  String? selectedUnitId = assignedUnitIds.isNotEmpty
      ? assignedUnitIds.first
      : null;
  final taskTargetAmount = _resolveTaskProgressTargetAmount(
    task: task,
    assignedUnitIds: assignedUnitIds,
    fallbackTotalUnits: fallbackTotalUnits,
  );
  final progressContextText = [
    plan.title,
    plan.notes,
    task.title,
    task.instructions,
    fallbackWorkUnitLabel,
  ].join(" ");
  final farmQuantitySummary = _summarizeFarmQuantities(
    plan: plan,
    timelineRows: timelineRows,
  );
  final supportsFarmQuantityTracking = farmQuantitySummary != null;
  final suggestedQuantityActivityType = supportsFarmQuantityTracking
      ? _suggestQuantityActivityType(task)
      : _quantityActivityNone;
  num? selectedActualAmount;
  var selectedQuantityActivityType = suggestedQuantityActivityType;
  num selectedQuantityAmount = 0;
  final notesController = TextEditingController();
  var selectedDelayReason = _delayReasonNone;
  var validationError = "";
  final attendanceOverridesByStaffId = <String, ProductionAttendanceRecord>{};
  List<ProductionTaskProgressProofInput> selectedProofs = [];

  ProductionAttendanceRecord? resolveDialogAttendance(String? staffProfileId) {
    final normalizedStaffId = staffProfileId?.trim() ?? "";
    if (normalizedStaffId.isEmpty) {
      return null;
    }
    return attendanceOverridesByStaffId[normalizedStaffId] ??
        _attendanceForStaffOnDay(
          attendanceRecords: attendanceRecords,
          staffProfileId: normalizedStaffId,
          day: workDate,
        );
  }

  String resolveQuantityUnit(String activityType) {
    switch (activityType) {
      case _quantityActivityPlanting:
      case _quantityActivityTransplant:
        return farmQuantitySummary?.plantingUnit ?? "";
      case _quantityActivityHarvest:
        return farmQuantitySummary?.harvestUnit ?? "";
      default:
        return "";
    }
  }

  num resolveQuantityTarget(String activityType) {
    final plantingTargets = plan.plantingTargets;
    if (plantingTargets == null) {
      return 0;
    }
    switch (activityType) {
      case _quantityActivityPlanting:
      case _quantityActivityTransplant:
        return plantingTargets.plannedPlantingQuantity;
      case _quantityActivityHarvest:
        return plantingTargets.estimatedHarvestQuantity;
      default:
        return 0;
    }
  }

  num resolveQuantityLogged(String activityType) {
    if (farmQuantitySummary == null) {
      return 0;
    }
    switch (activityType) {
      case _quantityActivityPlanting:
        return farmQuantitySummary.plantingLogged;
      case _quantityActivityTransplant:
        return farmQuantitySummary.transplantLogged;
      case _quantityActivityHarvest:
        return farmQuantitySummary.harvestLogged;
      default:
        return 0;
    }
  }

  void syncFromExistingSelection({
    bool preserveSelectedQuantityActivity = false,
  }) {
    final existingRow = _findExistingProgressRowForSelection(
      timelineRows: timelineRows,
      taskId: task.id,
      workDate: workDate,
      staffId: selectedStaffId,
      unitId: selectedUnitId,
    );
    selectedActualAmount = existingRow?.actualPlots;
    final existingDelayReason = existingRow?.delayReason.trim() ?? "";
    selectedDelayReason = _delayReasonOptions.contains(existingDelayReason)
        ? existingDelayReason
        : _delayReasonNone;
    notesController.text = existingRow?.notes ?? "";
    if (supportsFarmQuantityTracking) {
      final existingQuantityActivityType =
          existingRow?.quantityActivityType.trim() ?? "";
      if (existingRow != null &&
          existingRow.quantityAmount > 0 &&
          existingQuantityActivityType.isNotEmpty &&
          existingQuantityActivityType != _quantityActivityNone) {
        selectedQuantityActivityType = existingQuantityActivityType;
        selectedQuantityAmount = existingRow.quantityAmount;
      } else {
        if (!preserveSelectedQuantityActivity) {
          selectedQuantityActivityType = suggestedQuantityActivityType;
        }
        selectedQuantityAmount = 0;
      }
    }
  }

  syncFromExistingSelection();
  final rowsForTaskOnWorkDate = _rowsForDay(
    timelineRows,
    workDate,
  ).where((row) => row.taskId.trim() == task.id.trim()).toList();

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
          final existingSelectionProofCount =
              existingSelectionRow?.proofCount ?? 0;
          final loggedAmountExcludingSelection =
              loggedTotal - existingSelectionAmount;
          final remainingAgainstPlan =
              taskTargetAmount - loggedAmountExcludingSelection;
          final cappedRemainingAgainstPlan = remainingAgainstPlan < 0
              ? 0
              : remainingAgainstPlan;
          final strictActualMax = cappedRemainingAgainstPlan.toDouble();
          final progressOptions = _buildProgressAmountOptions(
            maxAmount: strictActualMax,
          );
          final selectedActualAmountValue = selectedActualAmount ?? 0;
          final hasSelectedActualAmount = selectedActualAmount != null;
          final selectedActualSelectionValid =
              hasSelectedActualAmount &&
              progressOptions.any(
                (amount) =>
                    _sameProgressAmount(amount, selectedActualAmountValue),
              );
          final actualHelperText = _buildProgressCountHelperText(
            targetAmount: taskTargetAmount,
            loggedAmount: loggedAmountExcludingSelection,
            remainingAmount: cappedRemainingAgainstPlan,
            assignedUnitIds: assignedUnitIds,
            planUnitLabelById: planUnitLabelById,
            selectedUnitId: selectedUnitId,
            fallbackWorkUnitLabel: fallbackWorkUnitLabel,
            contextText: progressContextText,
          );
          final progressUnitSingularLabel = _resolveProgressUnitSingularLabel(
            assignedUnitIds: assignedUnitIds,
            planUnitLabelById: planUnitLabelById,
            selectedUnitId: selectedUnitId,
            fallbackWorkUnitLabel: fallbackWorkUnitLabel,
            contextText: progressContextText,
          );
          final dailyTaskProgressSummary = _buildTaskUnitProgressSummary(
            task: task,
            timelineRows: rowsForTaskOnWorkDate,
            planUnitLabelById: planUnitLabelById,
            fallbackTotalUnits: fallbackTotalUnits,
            fallbackWorkUnitLabel: fallbackWorkUnitLabel,
            contextText: progressContextText,
            selectedUnitId: selectedUnitId,
          );
          final progressWorkflowHint = _buildProgressWorkflowHint(
            singularUnitLabel: progressUnitSingularLabel,
          );
          final progressActualLabel = _buildProgressActualLabel(
            singularUnitLabel: progressUnitSingularLabel,
          );
          final editableAllowanceLabel = _formatProgressAmountWithUnit(
            amount: strictActualMax,
            singularUnitLabel: progressUnitSingularLabel,
          );
          final totalLoggedAfterSave =
              loggedAmountExcludingSelection + selectedActualAmountValue;
          final remainingAfterSave =
              (taskTargetAmount - totalLoggedAfterSave) < 0
              ? 0
              : (taskTargetAmount - totalLoggedAfterSave);
          final requiredProofCount = requiredTaskProgressProofCount(
            selectedActualAmountValue,
          );
          final proofCountMatchesSelectedAmount = requiredProofCount == 0
              ? selectedProofs.isEmpty
              : selectedProofs.isNotEmpty
              ? selectedProofs.length == requiredProofCount
              : existingSelectionProofCount == requiredProofCount;
          final proofInstructionText = requiredProofCount == 0
              ? "Enter a positive actual amount to unlock proof uploads."
              : proofCountMatchesSelectedAmount
              ? selectedProofs.isEmpty
                    ? existingSelectionProofCount > 0 &&
                              existingSelectionProofCount == requiredProofCount
                          ? "This staff/unit already has $existingSelectionProofCount proof image(s) saved."
                          : "Upload exactly $requiredProofCount proof image(s) before saving."
                    : "Selected ${selectedProofs.length} of $requiredProofCount required proof image(s)."
              : "Selected ${selectedProofs.length} of $requiredProofCount required proof image(s).";
          final proofButtonLabel = selectedProofs.isEmpty
              ? (existingSelectionProofCount > 0
                    ? "Update proof images"
                    : "Add proof images")
              : "Replace proof images";
          final selectedAttendance = resolveDialogAttendance(selectedStaffId);
          final selectedClockInAt = selectedAttendance?.clockInAt?.toLocal();
          final selectedClockOutAt = selectedAttendance?.clockOutAt?.toLocal();
          final selectedClockInValue = _formatAttendanceTimeValue(
            selectedClockInAt,
            emptyLabel: _attendanceClockInUnsetLabel,
          );
          final selectedClockOutValue = selectedClockOutAt != null
              ? _clockLabel(selectedClockOutAt)
              : (selectedClockInAt != null
                    ? _attendanceClockOutPendingLabel
                    : _attendanceClockOutUnsetLabel);
          final hasSelectedClockIn = selectedAttendance?.clockInAt != null;
          final hasSelectedClockOut = selectedAttendance?.clockOutAt != null;
          final selectedAttendanceComplete =
              hasSelectedClockIn && hasSelectedClockOut;
          final selectedStaffIsActor =
              normalizedActorStaffId.isNotEmpty &&
              selectedStaffId != null &&
              selectedStaffId!.trim() == normalizedActorStaffId;
          final canClockSelectedStaff =
              canManageAttendance || selectedStaffIsActor;
          final canSubmitProgress =
              selectedAttendanceComplete &&
              selectedActualSelectionValid &&
              proofCountMatchesSelectedAmount;
          final selectedStaffLabel =
              (selectedStaffId != null && selectedStaffId!.trim().isNotEmpty)
              ? _resolveStaffDisplayLabel(
                  selectedStaffId!,
                  staffMap,
                  fallbackRole: task.roleRequired,
                )
              : _unassignedLabel;

          Future<void> chooseProofs() async {
            final picked = await pickTaskProgressProofImages();
            if (!dialogContext.mounted || picked.isEmpty) {
              return;
            }
            setDialogState(() {
              selectedProofs = picked;
              validationError = "";
            });
          }

          Future<void> applyAttendanceAction(
            Future<ProductionAttendanceRecord?> Function(
              String staffProfileId,
              ProductionAttendanceRecord? existingAttendance,
            )
            action,
          ) async {
            final currentStaffId = selectedStaffId?.trim() ?? "";
            if (currentStaffId.isEmpty) {
              return;
            }
            final updatedAttendance = await action(
              currentStaffId,
              resolveDialogAttendance(currentStaffId),
            );
            if (!dialogContext.mounted || updatedAttendance == null) {
              return;
            }
            setDialogState(() {
              attendanceOverridesByStaffId[currentStaffId] = updatedAttendance;
            });
          }

          final existingSelectionQuantityAmount =
              existingSelectionRow?.quantityActivityType.trim() ==
                  selectedQuantityActivityType
              ? existingSelectionRow?.quantityAmount ?? 0
              : 0;
          final quantityTarget = resolveQuantityTarget(
            selectedQuantityActivityType,
          );
          final quantityLogged = resolveQuantityLogged(
            selectedQuantityActivityType,
          );
          final quantityRemaining =
              quantityTarget -
              (quantityLogged - existingSelectionQuantityAmount);
          final cappedQuantityRemaining = quantityRemaining < 0
              ? 0
              : quantityRemaining;
          final selectedQuantityUnitLabel = resolveQuantityUnit(
            selectedQuantityActivityType,
          );
          final quantityOptions =
              selectedQuantityActivityType == _quantityActivityNone
              ? const <num>[0]
              : _buildQuantityAmountOptions(maxAmount: cappedQuantityRemaining);
          if (quantityOptions.isNotEmpty &&
              !quantityOptions.any(
                (amount) => _sameProgressAmount(amount, selectedQuantityAmount),
              )) {
            selectedQuantityAmount = quantityOptions.last;
          }
          final quantityRemainingAfterSave =
              (cappedQuantityRemaining - selectedQuantityAmount) < 0
              ? 0
              : (cappedQuantityRemaining - selectedQuantityAmount);
          final shouldShowFollowUpSuggestion =
              hasSelectedActualAmount &&
              (remainingAfterSave > 0 || quantityRemainingAfterSave > 0);
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
                        progressWorkflowHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (assignedStaffIds.isNotEmpty && canPickAnyAssignedStaff)
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
                                _resolveStaffDisplayLabel(
                                  staffId,
                                  staffMap,
                                  fallbackRole: task.roleRequired,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedStaffId = value;
                            syncFromExistingSelection(
                              preserveSelectedQuantityActivity: true,
                            );
                          });
                        },
                      ),
                    if (assignedStaffIds.isNotEmpty && canPickAnyAssignedStaff)
                      const SizedBox(height: 12),
                    if (assignedStaffIds.isNotEmpty && !canPickAnyAssignedStaff)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          "Logging as $selectedStaffLabel",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    if (assignedStaffIds.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.surface,
                              Color.alphaBlend(
                                _workspaceSoftSlate.withValues(alpha: 0.94),
                                Theme.of(context).colorScheme.surface,
                              ),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _workspaceNavy.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedStaffId != null &&
                                      selectedStaffId!.trim().isNotEmpty
                                  ? "Attendance for $selectedStaffLabel"
                                  : "Attendance",
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: _workspaceNavy,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            if (selectedStaffId == null ||
                                selectedStaffId!.trim().isEmpty)
                              Text(
                                "Select a staff member to view or update clock-in and clock-out time.",
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                              )
                            else ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _InfoChip(
                                    label:
                                        "$_clockedInLabel: $selectedClockInValue",
                                    icon: Icons.login_outlined,
                                    backgroundColor: hasSelectedClockIn
                                        ? _workspaceSoftTeal
                                        : _workspaceSoftBlue,
                                    foregroundColor: hasSelectedClockIn
                                        ? _workspaceTeal
                                        : _workspaceBlue,
                                    borderColor:
                                        (hasSelectedClockIn
                                                ? _workspaceTeal
                                                : _workspaceBlue)
                                            .withValues(alpha: 0.18),
                                  ),
                                  _InfoChip(
                                    label:
                                        "$_clockedOutLabel: $selectedClockOutValue",
                                    icon: Icons.logout_outlined,
                                    backgroundColor: hasSelectedClockOut
                                        ? _workspaceSoftTeal
                                        : _workspaceSoftSlate,
                                    foregroundColor: hasSelectedClockOut
                                        ? _workspaceTeal
                                        : _workspaceNavy,
                                    borderColor:
                                        (hasSelectedClockOut
                                                ? _workspaceTeal
                                                : _workspaceNavy)
                                            .withValues(alpha: 0.14),
                                  ),
                                ],
                              ),
                              if (!selectedAttendanceComplete) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _workspaceSoftAmber,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _workspaceAmber.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                        color: _workspaceAmber,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _taskProgressAttendanceRequired,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: _workspaceAmber,
                                                fontWeight: FontWeight.w800,
                                                height: 1.35,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (canClockSelectedStaff &&
                                  (onQuickClockInForStaff != null ||
                                      onQuickClockOutForStaff != null ||
                                      onSetAttendanceForStaff != null)) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (!hasSelectedClockIn &&
                                        !hasSelectedClockOut &&
                                        onQuickClockInForStaff != null)
                                      FilledButton.tonalIcon(
                                        onPressed: () => applyAttendanceAction(
                                          onQuickClockInForStaff,
                                        ),
                                        icon: const Icon(
                                          Icons.login_outlined,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          _attendanceDialogClockInLabel,
                                        ),
                                      ),
                                    if (hasSelectedClockIn &&
                                        !hasSelectedClockOut &&
                                        onQuickClockOutForStaff != null)
                                      FilledButton.tonalIcon(
                                        onPressed: () => applyAttendanceAction(
                                          onQuickClockOutForStaff,
                                        ),
                                        icon: const Icon(
                                          Icons.logout_outlined,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          _attendanceDialogClockOutLabel,
                                        ),
                                      ),
                                    if (onSetAttendanceForStaff != null)
                                      OutlinedButton.icon(
                                        onPressed: () => applyAttendanceAction(
                                          onSetAttendanceForStaff,
                                        ),
                                        icon: Icon(
                                          hasSelectedClockIn ||
                                                  hasSelectedClockOut
                                              ? Icons.edit_calendar_outlined
                                              : Icons.schedule_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          hasSelectedClockIn ||
                                                  hasSelectedClockOut
                                              ? _editAttendanceLabel
                                              : _setAttendanceLabel,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    if (assignedUnitIds.isNotEmpty)
                      DropdownButtonFormField<String?>(
                        initialValue: selectedUnitId,
                        decoration: InputDecoration(
                          labelText:
                              "Assigned ${progressUnitSingularLabel.trim().isEmpty ? 'work unit' : progressUnitSingularLabel}",
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text("-"),
                          ),
                          ...assignedUnitIds.map(
                            (unitId) => DropdownMenuItem<String?>(
                              value: unitId,
                              child: Text(
                                _normalizeProgressUnitDisplayLabel(
                                  planUnitLabelById[unitId] ?? unitId,
                                  fallbackWorkUnitLabel: fallbackWorkUnitLabel,
                                  contextText: progressContextText,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedUnitId = value;
                            syncFromExistingSelection(
                              preserveSelectedQuantityActivity: true,
                            );
                          });
                        },
                      ),
                    if (assignedUnitIds.isNotEmpty) const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.surface,
                            Color.alphaBlend(
                              _workspaceSoftBlue.withValues(alpha: 0.92),
                              Theme.of(context).colorScheme.surface,
                            ),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _workspaceBlue.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            progressActualLabel,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: _workspaceBlue,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoChip(
                                label:
                                    "$_workingOnLabel: ${dailyTaskProgressSummary.workingOnLabel}",
                                icon: Icons.track_changes_outlined,
                                backgroundColor: _workspaceSoftAmber,
                                foregroundColor: _workspaceAmber,
                                borderColor: _workspaceAmber.withValues(
                                  alpha: 0.16,
                                ),
                              ),
                              _InfoChip(
                                label:
                                    "$_doneTodayLabel: ${dailyTaskProgressSummary.doneTodayLabel}",
                                icon: Icons.insights_outlined,
                                backgroundColor: _workspaceSoftTeal,
                                foregroundColor: _workspaceTeal,
                                borderColor: _workspaceTeal.withValues(
                                  alpha: 0.16,
                                ),
                              ),
                              _InfoChip(
                                label:
                                    "$_leftTodayLabel: ${dailyTaskProgressSummary.leftTodayLabel}",
                                icon: Icons.rule_folder_outlined,
                                backgroundColor: _workspaceSoftBlue,
                                foregroundColor: _workspaceBlue,
                                borderColor: _workspaceBlue.withValues(
                                  alpha: 0.16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Quick pick",
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: _workspaceNavy,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            existingSelectionAmount > 0
                                ? "Allowed now: $editableAllowanceLabel. This staff/unit already has ${_formatProgressAmountWithUnit(amount: existingSelectionAmount, singularUnitLabel: progressUnitSingularLabel)} saved, so the picker frees that amount while you edit."
                                : "Allowed now: $editableAllowanceLabel.",
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: progressOptions.map((amount) {
                              final selected =
                                  hasSelectedActualAmount &&
                                  _sameProgressAmount(
                                    amount,
                                    selectedActualAmountValue,
                                  );
                              return ChoiceChip(
                                label: Text(_formatProgressAmount(amount)),
                                selected: selected,
                                showCheckmark: false,
                                labelStyle: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: selected
                                          ? Colors.white
                                          : _workspaceNavy,
                                      fontWeight: FontWeight.w800,
                                    ),
                                selectedColor: _workspaceBlue,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                side: BorderSide(
                                  color: selected
                                      ? _workspaceBlue
                                      : _workspaceBlue.withValues(alpha: 0.18),
                                ),
                                onSelected: (_) {
                                  setDialogState(() {
                                    selectedActualAmount = amount;
                                    if (_sameProgressAmount(amount, 0)) {
                                      selectedProofs = [];
                                    }
                                    validationError = "";
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: hasSelectedActualAmount
                                  ? _workspaceSoftTeal
                                  : _workspaceSoftSlate,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    (hasSelectedActualAmount
                                            ? _workspaceTeal
                                            : _workspaceBlue)
                                        .withValues(alpha: 0.14),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hasSelectedActualAmount
                                      ? Icons.task_alt_outlined
                                      : Icons.pending_actions_outlined,
                                  size: 18,
                                  color: hasSelectedActualAmount
                                      ? _workspaceTeal
                                      : _workspaceBlue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    hasSelectedActualAmount
                                        ? "Selected ${_formatProgressAmountWithUnit(amount: selectedActualAmountValue, singularUnitLabel: progressUnitSingularLabel)} for this staff."
                                        : "Select the completed amount from the allowed values below.",
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: _workspaceNavy,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            actualHelperText,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Proof images",
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  proofInstructionText,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        height: 1.3,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: requiredProofCount == 0
                                      ? null
                                      : chooseProofs,
                                  icon: Icon(
                                    selectedProofs.isEmpty
                                        ? Icons.add_photo_alternate_outlined
                                        : Icons.refresh_outlined,
                                  ),
                                  label: Text(proofButtonLabel),
                                ),
                                if (selectedProofs.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: selectedProofs
                                        .map(
                                          (proof) => ActionChip(
                                            avatar: const Icon(
                                              Icons.image_outlined,
                                              size: 18,
                                            ),
                                            label: Text(proof.displayLabel),
                                            onPressed: () {
                                              showProductionTaskProgressPickedProofPreview(
                                                context,
                                                proof: proof,
                                              );
                                            },
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (shouldShowFollowUpSuggestion) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _workspaceSoftAmber,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _workspaceAmber.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Suggested follow-up",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: _workspaceAmber,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (remainingAfterSave > 0)
                                    Text(
                                      "Give the staff a 2 hour break, then create a follow-up task for ${_formatProgressAmountWithUnit(amount: remainingAfterSave, singularUnitLabel: progressUnitSingularLabel)} remaining.",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: _workspaceNavy,
                                            height: 1.4,
                                          ),
                                    ),
                                  if (remainingAfterSave > 0 &&
                                      quantityRemainingAfterSave > 0)
                                    const SizedBox(height: 8),
                                  if (quantityRemainingAfterSave > 0)
                                    Text(
                                      "Create another ${_formatQuantityActivityLabel(selectedQuantityActivityType)} task for ${_formatProgressAmount(quantityRemainingAfterSave)} $selectedQuantityUnitLabel left after save.",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: _workspaceNavy,
                                            height: 1.4,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasSelectedActualAmount
                          ? "Save preview: ${_formatProgressAmountWithUnit(amount: selectedActualAmountValue, singularUnitLabel: progressUnitSingularLabel)} completed by $selectedStaffLabel today. Task total after save: ${_formatProgressAmountWithUnit(amount: totalLoggedAfterSave, singularUnitLabel: progressUnitSingularLabel)} against a planned target of ${_formatProgressAmountWithUnit(amount: taskTargetAmount, singularUnitLabel: progressUnitSingularLabel)}. Remaining against plan after save: ${_formatProgressAmountWithUnit(amount: remainingAfterSave, singularUnitLabel: progressUnitSingularLabel)}."
                          : "Select a completed amount to preview the save.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (supportsFarmQuantityTracking) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedQuantityActivityType,
                        decoration: const InputDecoration(
                          labelText: _logDialogQuantityActivityLabel,
                          helperText: _logDialogQuantityHelper,
                          helperMaxLines: 2,
                        ),
                        items: _quantityActivityOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  value == _quantityActivityNone
                                      ? "No quantity update"
                                      : _formatQuantityActivityLabel(value),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedQuantityActivityType = value;
                            selectedQuantityAmount = 0;
                          });
                        },
                      ),
                      if (selectedQuantityActivityType !=
                          _quantityActivityNone) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<num>(
                          initialValue: selectedQuantityAmount,
                          decoration: InputDecoration(
                            labelText: _logDialogQuantityAmountLabel,
                            helperText:
                                "Target ${_formatProgressAmount(quantityTarget)} $selectedQuantityUnitLabel • logged ${_formatProgressAmount(quantityLogged)} $selectedQuantityUnitLabel • remaining ${_formatProgressAmount(cappedQuantityRemaining)} $selectedQuantityUnitLabel",
                            helperMaxLines: 2,
                          ),
                          items: quantityOptions
                              .map(
                                (amount) => DropdownMenuItem<num>(
                                  value: amount,
                                  child: Text(
                                    "${_formatProgressAmount(amount)} $selectedQuantityUnitLabel",
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              selectedQuantityAmount = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "${_formatQuantityActivityLabel(selectedQuantityActivityType)} preview: ${_formatProgressAmount(selectedQuantityAmount)} $selectedQuantityUnitLabel today • ${_formatProgressAmount(quantityRemainingAfterSave)} $selectedQuantityUnitLabel left after save.",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
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
                      decoration: InputDecoration(
                        labelText: _logDialogNotesLabel,
                        hintText: _buildProgressNotesHint(
                          singularUnitLabel: progressUnitSingularLabel,
                        ),
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
                onPressed: canSubmitProgress
                    ? () {
                        if (!selectedAttendanceComplete) {
                          setDialogState(() {
                            validationError = _taskProgressAttendanceRequired;
                          });
                          return;
                        }
                        if (!hasSelectedActualAmount ||
                            !selectedActualSelectionValid) {
                          setDialogState(() {
                            validationError = _logDialogActualInvalid;
                          });
                          return;
                        }
                        if (!proofCountMatchesSelectedAmount) {
                          setDialogState(() {
                            validationError = requiredProofCount == 0
                                ? "Proof images are not allowed when actual amount is 0."
                                : "Upload exactly $requiredProofCount proof image(s).";
                          });
                          return;
                        }
                        if (selectedActualAmountValue == 0 &&
                            selectedQuantityAmount == 0 &&
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
                            actualPlots: selectedActualAmountValue,
                            proofs: List<ProductionTaskProgressProofInput>.from(
                              selectedProofs,
                            ),
                            quantityActivityType: selectedQuantityActivityType,
                            quantityAmount: selectedQuantityAmount,
                            quantityUnit:
                                selectedQuantityActivityType ==
                                    _quantityActivityNone
                                ? ""
                                : resolveQuantityUnit(
                                    selectedQuantityActivityType,
                                  ),
                            delayReason: selectedDelayReason,
                            notes: notesController.text.trim(),
                          ),
                        );
                      }
                    : null,
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
