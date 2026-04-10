/// lib/app/features/home/presentation/production/production_plan_detail_screen.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Detail screen for a production plan (KPIs, phases, tasks, approvals).
///
/// WHY:
/// - Gives owners/staff visibility into progress and deadlines.
/// - Enables task status updates and owner approvals.
///
/// HOW:
/// - Uses productionPlanDetailProvider for data.
/// - Renders KPI cards, phase progress, and task lists.
/// - Logs build, refresh, and action taps.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';
import 'package:frontend/app/features/home/presentation/production/production_draft_presence.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_viewer.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_picker.dart';

const String _logTag = "PRODUCTION_DETAIL";
const String _buildMessage = "build()";
const String _refreshAction = "refresh_action";
const String _refreshPull = "refresh_pull";
const String _statusChangeAction = "status_change";
const String _preorderConfigAction = "preorder_config_action";
const String _logProgressAction = "log_progress_action";
const String _batchLogProgressAction = "batch_log_progress_action";
const String _approveProgressAction = "approve_progress_action";
const String _rejectProgressAction = "reject_progress_action";
const String _approveAction = "approve_action";
const String _rejectAction = "reject_action";
const String _reconcilePreorderAction = "reconcile_preorder_action";
const String _acceptVarianceAction = "accept_variance_action";
const String _replanUnitAction = "replan_unit_action";
const String _backTap = "back_tap";
const String _screenTitle = "Production plan";
const String _summaryTitle = "Plan summary";
const String _overviewViewTitle = "Overview";
const String _executionViewTitle = "Execution";
const String _peopleViewTitle = "People";
const String _riskViewTitle = "Risk";
const String _kpiTitle = "KPIs";
const String _attendanceImpactTitle = "HR impact KPIs";
const String _dailyRollupTitle = "Daily execution rollup";
const String _staffProgressTitle = "Farmer progress";
const String _phaseTitle = "Phase progress";
const String _phaseUnitProgressTitle = "Phase unit completion";
const String _unitDivergenceTitle = "Unit divergence";
const String _unitWarningsTitle = "Unit shift warnings";
const String _unitDivergenceDelayLabel = "Behind (days)";
const String _unitDivergenceShiftedTasksLabel = "Shifted tasks";
const String _unitDivergenceWarningCountLabel = "Warnings";
const String _deviationGovernanceTitle = "Deviation governance";
const String _deviationSummaryTotalAlerts = "Total alerts";
const String _deviationSummaryOpenAlerts = "Open alerts";
const String _deviationSummaryLockedUnits = "Locked units";
const String _deviationAlertDeviationLabel = "Deviation";
const String _deviationAlertThresholdLabel = "Threshold";
const String _deviationAcceptLabel = "Accept variance";
const String _deviationReplanLabel = "Re-plan";
const String _deviationLockedTag = "Locked";
const String _deviationUnlockedTag = "Unlocked";
const String _deviationSummaryEmptyTitle = "No governance alerts";
const String _deviationSummaryEmptyMessage =
    "Unit drift alerts will appear here when thresholds are exceeded.";
const String _planConfidenceTitle = "Lifecycle confidence";
const String _planConfidenceCurrentLabel = "Current";
const String _planConfidenceBaselineLabel = "Baseline";
const String _planConfidenceDeltaLabel = "Delta";
const String _planConfidenceCapacityLabel = "Capacity";
const String _planConfidenceScheduleLabel = "Schedule stability";
const String _planConfidenceReliabilityLabel = "Historical reliability";
const String _planConfidenceComplexityLabel = "Complexity risk";
const String _planConfidenceFallback =
    "Confidence will appear after the first deterministic recompute trigger.";
const String _tasksTitle = "Tasks";
const String _assignedLabel = "Assigned";
const String _assignedUnitsLabel = "Assigned units";
const String _roleLabel = "Role";
const String _dueLabel = "Due";
const String _statusLabel = "Status";
const String _phaseUnitRequiredLabel = "Required units";
const String _phaseUnitCompletedLabel = "Completed units";
const String _phaseUnitRemainingLabel = "Remaining units";
const String _timelineExpectedLabel = "Expected Plots";
const String _timelineActualLabel = "Actual Plots";
const String _timelineDelayLabel = "Delay";
const String _timelineEmptyTitle = "No timeline data yet";
const String _timelineEmptyMessage =
    "Task schedule rows will appear when tasks are added.";
const String _phaseUnitEmptyTitle = "No phase unit data yet";
const String _phaseUnitEmptyMessage =
    "Approved task completions will populate per-phase unit progress.";
const String _productionStateLabel = "Product state";
const String _planUnitsLabel = "Plan units";
const String _planUnitsLoadingLabel = "Loading...";
const String _planUnitsUnavailableLabel = "Unavailable";
const String _preorderLabel = "Pre-order";
const String _preorderCapLabel = "Pre-order cap";
const String _effectiveCapLabel = "Effective cap";
const String _confidenceLabel = "Confidence";
const String _preorderRemainingLabel = "Pre-order remaining";
const String _configurePreorderButtonLabel = "Configure pre-order";
const String _preorderConfigTitle = "Pre-order settings";
const String _preorderEnableLabel = "Enable pre-order";
const String _preorderYieldLabel = "Conservative yield quantity";
const String _preorderYieldUnitLabel = "Yield unit";
const String _preorderCapRatioLabel = "Cap ratio (0.1 - 0.9)";
const String _preorderConfigValidation =
    "Provide a positive yield and valid cap ratio.";
const String _preorderConfigSaveLabel = "Save";
const String _preorderConfigCancelLabel = "Cancel";
const String _reconcileButtonLabel = "Reconcile expired holds";
const String _reconcileSummaryTitle = "Reconcile summary";
const String _reconcileSummaryScanned = "Scanned";
const String _reconcileSummaryExpired = "Expired";
const String _reconcileSummarySkipped = "Skipped";
const String _reconcileSummaryErrors = "Errors";
const String _reconcileSummaryDoneLabel = "Done";
const String _reconcileSuccess = "Expired holds reconciled.";
const String _reconcileFailure = "Unable to reconcile expired holds.";
const String _preorderUpdateSuccess = "Pre-order settings updated.";
const String _preorderUpdateFailure = "Unable to update pre-order settings.";
const String _dash = "-";
const String _preorderEnabledLabel = "Enabled";
const String _preorderDisabledLabel = "Disabled";
const String _logProgressLabel = "Log progress";
const String _batchLogProgressLabel = "Batch log progress";
const String _batchLogDialogTitle = "Batch daily logging";
const String _batchLogSubmitLabel = "Submit batch";
const String _batchLogSkipLabel = "Skip";
const String _batchLogStateLabel = "State";
const String _batchLogTableTaskLabel = "Task";
const String _batchLogTableFarmerLabel = "Farmer";
const String _batchLogTableUnitLabel = "Unit";
const String _batchLogTableExpectedLabel = "Expected";
const String _batchLogTableActualLabel = "Actual";
const String _batchLogTableDelayLabel = "Delay";
const String _batchLogTableNotesLabel = "Notes";
const String _batchLogRecordedLabel = "Recorded";
const String _batchLogSkippedLabel = "Skipped";
const String _batchLogReadyLabel = "Ready";
const String _batchLogDateLabel = "Work date";
const String _batchLogDateButtonLabel = "Change date";
const String _batchLogEmptyRows = "No task rows available for selected date.";
const String _batchLogHint =
    "Record multiple task updates at once. Completed logs are locked.";
const String _batchLogValidationFix = "Fix row errors before submitting.";
const String _batchLogValidationSelectRows =
    "Select at least one row to submit.";
const String _batchLogActualRequired = "Enter actual amount";
const String _batchLogActualInvalid = "Use a non-negative number";
const String _batchLogZeroDelayRequired =
    "Select a delay reason when actual amount is zero";
const String _logProgressDialogTitle = "Log daily work";
const String _logProgressDateLabel = "Date";
const String _logProgressFarmerLabel = "Farmer";
const String _logProgressUnitLabel = "Unit";
const String _logProgressActualPlotsLabel = "Actual amount";
const String _logProgressDelayReasonLabel = "Delay reason";
const String _logProgressZeroHelperText =
    "Use this to record absence or blocked workdays";
const String _logProgressNotesLabel = "Notes";
const String _logProgressNotesHint = "Optional context";
const String _logProgressActualInvalidText =
    "Enter a valid non-negative amount";
const String _logProgressStaffRequiredText = "Select a staff member";
const String _logProgressUnitRequiredText = "Select a unit";
const String _logProgressAttendanceRequiredText =
    "Clock in and clock out before logging progress";
const String _logProgressZeroDelayValidationText =
    "Select a delay reason when actual amount is zero";
const String _viewProofLabel = "View proof";
const String _logProgressSaveLabel = "Save";
const String _logProgressCancelLabel = "Cancel";
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
const String _approvalPendingLabel = "Approval pending";
const String _approveLabel = "Approve";
const String _rejectLabel = "Reject";
const String _rejectionPrompt = "Reason for rejection";
const String _rejectionHint = "Add a short reason";
const String _rejectionSubmit = "Reject task";
const String _rejectionCancel = "Cancel";
const String _progressRejectPrompt = "Reason for progress review";
const String _progressRejectHint = "Add a short review reason";
const String _progressRejectSubmit = "Mark for review";
const String _kpiTotalTasks = "Total tasks";
const String _kpiCompleted = "Completed";
const String _kpiOnTime = "On time";
const String _kpiAvgDelay = "Avg delay";
const String _kpiAttendanceCoverage = "Attendance cover";
const String _kpiAbsenteeImpact = "Absentee impact";
const String _kpiLinkedProgress = "Progress linked";
const String _kpiPlotsPerHour = "Plots/attended hr";
const String _kpiTrackedDays = "Tracked days";
const String _phaseCompletionLabel = "Completion";
const String _dailyRollupBlocksLabel = "Blocks";
const String _dailyRollupAssignedLabel = "Assigned";
const String _dailyRollupAttendedAssignedLabel = "Attended(assign)";
const String _dailyRollupAbsentLabel = "Absent(assign)";
const String _dailyRollupExpectedLabel = "Expected";
const String _dailyRollupActualLabel = "Actual";
const String _dailyRollupCoverageLabel = "Coverage";
const String _dailyRollupCompletionLabel = "Completion";
const String _dailyRollupPlotsPerHourLabel = "Plots/hr";
const String _staffProgressEmptyTitle = "No farmer scores yet";
const String _staffProgressEmptyMessage =
    "Farmer support scores appear after daily logs are recorded.";
const String _kpiEmptyTitle = "No KPI data yet";
const String _kpiEmptyMessage = "KPI cards will appear once tasks are tracked.";
const String _attendanceImpactEmptyTitle = "No attendance impact data yet";
const String _attendanceImpactEmptyMessage =
    "Attendance-linked KPI cards appear after attendance and progress logs are recorded.";
const String _dailyRollupEmptyTitle = "No daily rollups yet";
const String _dailyRollupEmptyMessage =
    "Daily rollups appear after schedules, attendance, or progress updates.";
const String _phaseEmptyTitle = "No phase progress yet";
const String _phaseEmptyMessage =
    "Phase completion will appear once tasks are created.";
const String _phaseEmptyTasks = "No tasks in this phase yet.";
const String _unitDivergenceEmptyTitle = "No unit divergence yet";
const String _unitDivergenceEmptyMessage =
    "Units are currently aligned with the baseline schedule.";
const String _unitWarningsEmptyTitle = "No unit warnings yet";
const String _unitWarningsEmptyMessage =
    "Shift conflicts and missing unit context warnings will appear here.";
const String _deviationVarianceSuccess = "Variance accepted.";
const String _deviationVarianceFailure = "Unable to accept variance.";
const String _deviationReplanSuccess = "Unit re-plan applied.";
const String _deviationReplanFailure = "Unable to apply unit re-plan.";
const String _deviationReplanDialogTitle = "Re-plan unit";
const String _deviationReplanShiftLabel = "Shift days";
const String _deviationReplanNoteLabel = "Manager note";
const String _deviationReplanSaveLabel = "Apply re-plan";
const String _deviationReplanSourceTaskMissing =
    "No source task was recorded for this alert.";
const String _deviationReplanSourceTaskDatesMissing =
    "Source task dates are missing, so this alert cannot be replanned here.";
const String _deviationReplanShiftInvalid =
    "Enter a whole-number shift in days.";
const String _deviationVarianceDialogTitle = "Accept variance";
const String _deviationVarianceDialogHint =
    "This keeps baseline dates unchanged and unlocks the unit for future shifts.";
const String _deviationVarianceSaveLabel = "Accept";
const String _deviationVarianceNoteLabel = "Manager note";
const String _approvalApprovedLabel = "Approved";
const String _approvalRejectedLabel = "Rejected";
const String _taskUpdateSuccess = "Task status updated.";
const String _taskUpdateFailure = "Unable to update task.";
const String _taskProgressSuccess = "Daily progress logged.";
const String _taskProgressFailure = "Unable to log daily progress.";
const String _taskProgressBatchSuccess = "Batch progress submitted.";
const String _taskProgressBatchPartial =
    "Batch submitted with some row errors.";
const String _taskProgressBatchFailure = "Unable to submit batch progress.";
const String _progressApproveSuccess = "Progress approved.";
const String _progressApproveFailure = "Unable to approve progress.";
const String _progressRejectSuccess = "Progress marked for review.";
const String _progressRejectFailure = "Unable to mark progress for review.";
const String _approveSuccess = "Task approved.";
const String _approveFailure = "Unable to approve task.";
const String _rejectSuccess = "Task rejected.";
const String _rejectFailure = "Unable to reject task.";
const String _extraPlanIdKey = "planId";
const String _extraTaskIdKey = "taskId";
const String _extraProgressIdKey = "progressId";
const String _extraErrorKey = "error";
const String _ownerRole = "business_owner";
const String _staffRole = "staff";
const String _staffRoleEstateManager = "estate_manager";
const String _staffRoleFarmManager = "farm_manager";
const String _staffRoleAssetManager = "asset_manager";
const String _tasksSuffix = "tasks";
const String _daysSuffix = "days";
const String _percentSuffix = "%";
const double _pagePadding = 16;
const double _sectionSpacing = 16;
const double _cardSpacing = 12;
const double _summaryCardRadius = 16;
const double _summaryCardPadding = 16;
const double _summaryTitleSpacing = 8;
const double _summaryMetaSpacing = 4;
const double _phaseProgressSpacing = 6;
const double _taskCardMarginHorizontal = 16;
const double _taskCardMarginVertical = 8;
const double _taskCardPadding = 12;
const double _taskCardRadius = 12;
const double _taskTitleSpacing = 8;
const double _taskMetaSpacing = 4;
const double _taskActionsSpacing = 12;
const double _approvalTopSpacing = 8;
const double _progressIndicatorHeight = 6;
const double _phaseEmptyPadding = 12;
const double _percentMultiplier = 100;
const double _percentMin = 0;
const double _progressMin = 0;
const double _progressMax = 1;
const int _percentFixedDigits = 0;
const int _delayFixedDigits = 1;
const double _detailSplitBreakpoint = 940;
const double _detailWideSplitBreakpoint = 1120;

const String _taskStatusPending = "pending";
const String _taskStatusInProgress = "in_progress";
const String _taskStatusDone = "done";
const List<String> _taskStatusOptions = [
  _taskStatusPending,
  _taskStatusInProgress,
  _taskStatusDone,
];

const String _approvalPending = "pending_approval";
const String _approvalApproved = "approved";
const String _approvalRejected = "rejected";
const String _progressApprovalPending = "pending_approval";
const String _progressApprovalApproved = "approved";
const String _progressApprovalNeedsReview = "needs_review";

enum _DetailViewMode { overview, execution, people, risk }

class ProductionPlanDetailScreen extends ConsumerWidget {
  final String planId;

  const ProductionPlanDetailScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage, extra: {_extraPlanIdKey: planId});
    final detailAsync = ref.watch(productionPlanDetailProvider(planId));
    final staffAsync = ref.watch(productionStaffProvider);
    final session = ref.watch(authSessionProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final profileRole = profileAsync.valueOrNull?.role ?? "";
    final actorRole = profileRole.isNotEmpty ? profileRole : session?.user.role;
    final isOwner = actorRole == _ownerRole;
    ref.listen<ProductionDraftPresenceState>(
      productionDraftPresenceProvider(planId),
      (previous, next) {
        if (previous?.updatedAt == next.updatedAt) {
          return;
        }
        unawaited(ref.refresh(productionPlanDetailProvider(planId).future));
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log(_logTag, _backTap);
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlansRoute);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              AppDebug.log(_logTag, _refreshAction);
              unawaited(
                ref.refresh(productionPlanDetailProvider(planId).future),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log(_logTag, _refreshPull);
          final _ = await ref.refresh(
            productionPlanDetailProvider(planId).future,
          );
        },
        child: detailAsync.when(
          data: (detail) {
            final staffList = staffAsync.valueOrNull ?? [];
            final staffMap = _buildStaffMap(staffList);
            final selfStaffRole = _resolveSelfStaffRole(
              staffList: staffList,
              userEmail: profileAsync.valueOrNull?.email ?? session?.user.email,
            );
            final canLogProgress = _canLogTaskProgress(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canReviewProgress = _canReviewTaskProgress(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canViewPlanUnits = _canViewPlanUnits(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canViewPlanConfidence = _canViewPlanConfidence(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canManageDeviationGovernance = _canManageDeviationGovernance(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            // UNIT-LIFECYCLE: manager view fetches canonical plan unit totals from backend-owned identities.
            final unitsAsync = canViewPlanUnits
                ? ref.watch(productionPlanUnitsProvider(planId))
                : null;
            // UNIT-LIFECYCLE: task cards need id->label lookup to render canonical unit assignments from backend.
            final planUnitLabelById = <String, String>{
              for (final unit
                  in unitsAsync?.valueOrNull?.units ??
                      const <ProductionPlanUnit>[])
                unit.id: unit.label,
            };
            return _PlanDetailBody(
              detail: detail,
              staffMap: staffMap,
              isOwner: isOwner,
              canLogProgress: canLogProgress,
              canReviewProgress: canReviewProgress,
              showPlanUnits: canViewPlanUnits,
              showPlanConfidence: canViewPlanConfidence,
              showDeviationGovernance: canManageDeviationGovernance,
              planUnitLabelById: planUnitLabelById,
              planUnitsCount: unitsAsync?.valueOrNull?.totalUnits,
              planUnitsLoading: unitsAsync?.isLoading == true,
              planUnitsHasError: unitsAsync?.hasError == true,
              onAcceptDeviationVariance: (alertId, note) async {
                AppDebug.log(
                  _logTag,
                  _acceptVarianceAction,
                  extra: {_extraPlanIdKey: planId, "alertId": alertId},
                );
                try {
                  final message = await ref
                      .read(productionPlanActionsProvider)
                      .acceptDeviationVariance(
                        planId: planId,
                        alertId: alertId,
                        note: note,
                      );
                  _showSnack(
                    context,
                    message.trim().isEmpty
                        ? _deviationVarianceSuccess
                        : message,
                  );
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _deviationVarianceFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _deviationVarianceFailure);
                }
              },
              onReplanDeviationUnit: (alertId, taskAdjustments, note) async {
                AppDebug.log(
                  _logTag,
                  _replanUnitAction,
                  extra: {
                    _extraPlanIdKey: planId,
                    "alertId": alertId,
                    "adjustments": taskAdjustments.length,
                  },
                );
                try {
                  final message = await ref
                      .read(productionPlanActionsProvider)
                      .replanDeviationUnit(
                        planId: planId,
                        alertId: alertId,
                        taskAdjustments: taskAdjustments,
                        note: note,
                      );
                  _showSnack(
                    context,
                    message.trim().isEmpty ? _deviationReplanSuccess : message,
                  );
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _deviationReplanFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _deviationReplanFailure);
                }
              },
              onReconcilePreorders: () async {
                AppDebug.log(
                  _logTag,
                  _reconcilePreorderAction,
                  extra: {_extraPlanIdKey: planId},
                );
                try {
                  final summary = await ref
                      .read(productionPlanActionsProvider)
                      .reconcileExpiredPreorders(planId: planId);
                  _showSnack(context, _reconcileSuccess);
                  await _showReconcileSummaryDialog(context, summary: summary);
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _reconcileFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _reconcileFailure);
                }
              },
              onUpdatePreorder: (payload) async {
                AppDebug.log(
                  _logTag,
                  _preorderConfigAction,
                  extra: {
                    _extraPlanIdKey: planId,
                    "intent": "update_preorder_settings",
                  },
                );
                try {
                  await ref
                      .read(productionPlanActionsProvider)
                      .updatePlanPreorder(planId: planId, payload: payload);
                  _showSnack(context, _preorderUpdateSuccess);
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _preorderUpdateFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _preorderUpdateFailure);
                }
              },
              onStatusChange: (taskId, status) async {
                AppDebug.log(
                  _logTag,
                  _statusChangeAction,
                  extra: {_extraTaskIdKey: taskId, _extraPlanIdKey: planId},
                );
                try {
                  await ref
                      .read(productionPlanActionsProvider)
                      .updateTaskStatus(
                        taskId: taskId,
                        status: status,
                        planId: planId,
                      );
                  _showSnack(context, _taskUpdateSuccess);
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _taskUpdateFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _taskUpdateFailure);
                }
              },
              onBatchLogProgress: (workDate, entries) async {
                AppDebug.log(
                  _logTag,
                  _batchLogProgressAction,
                  extra: {_extraPlanIdKey: planId, _extraTaskIdKey: "batch"},
                );
                try {
                  final result = await ref
                      .read(productionPlanActionsProvider)
                      .logTaskProgressBatch(
                        workDate: workDate,
                        entries: entries,
                        planId: planId,
                      );
                  final hasErrors = result.summary.errorCount > 0;
                  _showSnack(
                    context,
                    hasErrors
                        ? _taskProgressBatchPartial
                        : _taskProgressBatchSuccess,
                  );
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _taskProgressBatchFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _taskProgressBatchFailure);
                }
              },
              onApproveProgress: (progressId) async {
                AppDebug.log(
                  _logTag,
                  _approveProgressAction,
                  extra: {
                    _extraProgressIdKey: progressId,
                    _extraPlanIdKey: planId,
                  },
                );
                try {
                  await ref
                      .read(productionPlanActionsProvider)
                      .approveTaskProgress(
                        progressId: progressId,
                        planId: planId,
                      );
                  _showSnack(context, _progressApproveSuccess);
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _progressApproveFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _progressApproveFailure);
                }
              },
              onRejectProgress: (progressId, reason) async {
                AppDebug.log(
                  _logTag,
                  _rejectProgressAction,
                  extra: {
                    _extraProgressIdKey: progressId,
                    _extraPlanIdKey: planId,
                  },
                );
                try {
                  await ref
                      .read(productionPlanActionsProvider)
                      .rejectTaskProgress(
                        progressId: progressId,
                        reason: reason,
                        planId: planId,
                      );
                  _showSnack(context, _progressRejectSuccess);
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _progressRejectFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _progressRejectFailure);
                }
              },
              onApprove: (taskId) async {
                AppDebug.log(
                  _logTag,
                  _approveAction,
                  extra: {_extraTaskIdKey: taskId, _extraPlanIdKey: planId},
                );
                try {
                  await ref
                      .read(productionPlanActionsProvider)
                      .approveTask(taskId: taskId, planId: planId);
                  _showSnack(context, _approveSuccess);
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _approveFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _approveFailure);
                }
              },
              onReject: (taskId, reason) async {
                AppDebug.log(
                  _logTag,
                  _rejectAction,
                  extra: {_extraTaskIdKey: taskId, _extraPlanIdKey: planId},
                );
                try {
                  await ref
                      .read(productionPlanActionsProvider)
                      .rejectTask(
                        taskId: taskId,
                        reason: reason,
                        planId: planId,
                      );
                  _showSnack(context, _rejectSuccess);
                } catch (err) {
                  AppDebug.log(
                    _logTag,
                    _rejectFailure,
                    extra: {_extraErrorKey: err.toString()},
                  );
                  _showSnack(context, _rejectFailure);
                }
              },
              onLogProgress:
                  (
                    taskId,
                    staffId,
                    unitId,
                    workDate,
                    actualPlots,
                    proofs,
                    delayReason,
                    notes,
                  ) async {
                    AppDebug.log(
                      _logTag,
                      _logProgressAction,
                      extra: {_extraTaskIdKey: taskId, _extraPlanIdKey: planId},
                    );
                    try {
                      await ref
                          .read(productionPlanActionsProvider)
                          .logTaskProgress(
                            taskId: taskId,
                            workDate: workDate,
                            staffId: staffId,
                            unitId: unitId,
                            actualPlots: actualPlots,
                            proofs: proofs,
                            delayReason: delayReason,
                            notes: notes,
                            planId: planId,
                          );
                      _showSnack(context, _taskProgressSuccess);
                    } catch (err) {
                      AppDebug.log(
                        _logTag,
                        _taskProgressFailure,
                        extra: {_extraErrorKey: err.toString()},
                      );
                      _showSnack(context, _taskProgressFailure);
                    }
                  },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(_pagePadding),
              child: Text(err.toString()),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanDetailBody extends StatefulWidget {
  final ProductionPlanDetail detail;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final bool canLogProgress;
  final bool canReviewProgress;
  final bool showPlanUnits;
  final bool showPlanConfidence;
  final bool showDeviationGovernance;
  final Map<String, String> planUnitLabelById;
  final int? planUnitsCount;
  final bool planUnitsLoading;
  final bool planUnitsHasError;
  final Future<void> Function(String alertId, String note)
  onAcceptDeviationVariance;
  final Future<void> Function(
    String alertId,
    List<Map<String, dynamic>> taskAdjustments,
    String note,
  )
  onReplanDeviationUnit;
  final Future<void> Function() onReconcilePreorders;
  final Future<void> Function(Map<String, dynamic> payload) onUpdatePreorder;
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(
    DateTime workDate,
    List<ProductionTaskProgressBatchEntryInput> entries,
  )
  onBatchLogProgress;
  final Future<void> Function(String progressId) onApproveProgress;
  final Future<void> Function(String progressId, String reason)
  onRejectProgress;
  final Future<void> Function(
    String taskId,
    String? staffId,
    String? unitId,
    DateTime workDate,
    num actualPlots,
    List<ProductionTaskProgressProofInput> proofs,
    String delayReason,
    String notes,
  )
  onLogProgress;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _PlanDetailBody({
    required this.detail,
    required this.staffMap,
    required this.isOwner,
    required this.canLogProgress,
    required this.canReviewProgress,
    required this.showPlanUnits,
    required this.showPlanConfidence,
    required this.showDeviationGovernance,
    required this.planUnitLabelById,
    required this.planUnitsCount,
    required this.planUnitsLoading,
    required this.planUnitsHasError,
    required this.onAcceptDeviationVariance,
    required this.onReplanDeviationUnit,
    required this.onReconcilePreorders,
    required this.onUpdatePreorder,
    required this.onStatusChange,
    required this.onBatchLogProgress,
    required this.onApproveProgress,
    required this.onRejectProgress,
    required this.onLogProgress,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_PlanDetailBody> createState() => _PlanDetailBodyState();
}

class _PlanDetailBodyState extends State<_PlanDetailBody> {
  _DetailViewMode _viewMode = _DetailViewMode.overview;

  @override
  Widget build(BuildContext context) {
    final tasksByPhase = _groupTasksByPhase(
      widget.detail.phases,
      widget.detail.tasks,
    );

    return LayoutBuilder(
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
                _PlanSummaryCard(
                  plan: widget.detail.plan,
                  preorderSummary: widget.detail.preorderSummary,
                  isOwner: widget.isOwner,
                  showPlanUnits: widget.showPlanUnits,
                  showPlanConfidence: widget.showPlanConfidence,
                  planUnitsCount: widget.planUnitsCount,
                  planUnitsLoading: widget.planUnitsLoading,
                  planUnitsHasError: widget.planUnitsHasError,
                  onReconcilePreorders: widget.onReconcilePreorders,
                  onUpdatePreorder: widget.onUpdatePreorder,
                ),
                const SizedBox(height: _sectionSpacing),
                _DetailViewModePicker(
                  selectedMode: _viewMode,
                  onChanged: (mode) {
                    if (_viewMode == mode) return;
                    setState(() => _viewMode = mode);
                  },
                ),
                const SizedBox(height: _sectionSpacing),
                ...switch (_viewMode) {
                  _DetailViewMode.overview => _buildOverviewSections(context),
                  _DetailViewMode.execution => _buildExecutionSections(
                    context,
                    tasksByPhase,
                  ),
                  _DetailViewMode.people => _buildPeopleSections(context),
                  _DetailViewMode.risk => _buildRiskSections(context),
                },
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildOverviewSections(BuildContext context) {
    final overviewSections = <Widget>[
      _ResponsiveSplit(
        left: _buildSectionPane(
          title: _kpiTitle,
          subtitle:
              "A fast operational read of completion, pace, and delay risk.",
          child: _KpiRow(kpis: widget.detail.kpis),
        ),
        right: _buildSectionPane(
          title: "Output snapshot",
          subtitle: "What this plan has already produced, grouped by unit.",
          child: _OutputSummarySection(
            outputs: widget.detail.outputs,
            outputByUnit: widget.detail.kpis?.outputByUnit ?? const {},
          ),
        ),
        leftFlex: 6,
        rightFlex: 5,
      ),
      _ResponsiveSplit(
        left: _buildSectionPane(
          title: _phaseTitle,
          subtitle: "Which phases are moving and which ones are stalled.",
          child: _PhaseProgressList(kpis: widget.detail.kpis),
        ),
        right: _buildSectionPane(
          title: widget.showPlanConfidence
              ? _planConfidenceTitle
              : "Latest activity",
          subtitle: widget.showPlanConfidence
              ? "Confidence, capacity, and schedule stability in one place."
              : "Most recent task logs, approvals, and delays.",
          child: widget.showPlanConfidence
              ? _PlanConfidenceSection(confidence: widget.detail.confidence)
              : _TimelineTaskTable(
                  rows: widget.detail.timelineRows.take(8).toList(),
                  canReviewProgress: widget.canReviewProgress,
                  onApproveProgress: widget.onApproveProgress,
                  onRejectProgress: widget.onRejectProgress,
                ),
        ),
        leftFlex: 6,
        rightFlex: 5,
      ),
    ];

    if (widget.showPlanConfidence) {
      overviewSections.add(
        _buildSectionPane(
          title: "Latest activity",
          subtitle: "Most recent task logs, approvals, and delays.",
          child: _TimelineTaskTable(
            rows: widget.detail.timelineRows.take(8).toList(),
            canReviewProgress: widget.canReviewProgress,
            onApproveProgress: widget.onApproveProgress,
            onRejectProgress: widget.onRejectProgress,
          ),
        ),
      );
    }

    return _withVerticalSpacing(overviewSections);
  }

  List<Widget> _buildExecutionSections(
    BuildContext context,
    Map<String, List<ProductionTask>> tasksByPhase,
  ) {
    return _withVerticalSpacing([
      _ResponsiveSplit(
        left: _buildSectionPane(
          title: _dailyRollupTitle,
          subtitle:
              "Daily execution, attendance coverage, and how each day landed against plan.",
          child: _DailyRollupTable(rollups: widget.detail.dailyRollups),
        ),
        right: _buildSectionPane(
          title: "Execution feed",
          subtitle:
              "Clean task-by-task activity for approvals and progress review.",
          action: widget.canLogProgress
              ? OutlinedButton.icon(
                  onPressed: () async {
                    final batchInput = await _showBatchLogProgressDialog(
                      context,
                      detail: widget.detail,
                      staffMap: widget.staffMap,
                      planUnitLabelById: widget.planUnitLabelById,
                    );
                    if (batchInput == null) {
                      return;
                    }
                    await widget.onBatchLogProgress(
                      batchInput.workDate,
                      batchInput.entries,
                    );
                  },
                  icon: const Icon(Icons.playlist_add_check_circle_outlined),
                  label: const Text(_batchLogProgressLabel),
                )
              : null,
          child: _TimelineTaskTable(
            rows: widget.detail.timelineRows.take(12).toList(),
            canReviewProgress: widget.canReviewProgress,
            onApproveProgress: widget.onApproveProgress,
            onRejectProgress: widget.onRejectProgress,
          ),
        ),
        breakpoint: _detailWideSplitBreakpoint,
        leftFlex: 6,
        rightFlex: 5,
      ),
      _buildSectionPane(
        title: _tasksTitle,
        subtitle:
            "Expandable phase packs keep task actions operational without turning the page into a report table.",
        child: Column(
          children: widget.detail.phases.map((phase) {
            final phaseTasks = tasksByPhase[phase.id] ?? [];
            return _PhaseTaskSection(
              phase: phase,
              tasks: phaseTasks,
              attendanceRecords: widget.detail.attendanceRecords,
              staffMap: widget.staffMap,
              isOwner: widget.isOwner,
              canLogProgress: widget.canLogProgress,
              showPlanUnits: widget.showPlanUnits,
              planUnitLabelById: widget.planUnitLabelById,
              onStatusChange: widget.onStatusChange,
              onLogProgress: widget.onLogProgress,
              onApprove: widget.onApprove,
              onReject: widget.onReject,
            );
          }).toList(),
        ),
      ),
    ]);
  }

  List<Widget> _buildPeopleSections(BuildContext context) {
    return _withVerticalSpacing([
      _ResponsiveSplit(
        left: _buildSectionPane(
          title: _attendanceImpactTitle,
          subtitle:
              "Attendance-linked production efficiency and staffing coverage.",
          child: _AttendanceImpactSection(
            attendanceImpact: widget.detail.attendanceImpact,
          ),
        ),
        right: _buildSectionPane(
          title: "Attendance activity",
          subtitle:
              "Recent clock-in and clock-out records captured against the plan.",
          child: _AttendanceRecordSection(
            records: widget.detail.attendanceRecords,
            staffMap: widget.staffMap,
          ),
        ),
        leftFlex: 5,
        rightFlex: 6,
      ),
      _buildSectionPane(
        title: _staffProgressTitle,
        subtitle: "How each person is tracking against expected output.",
        child: _StaffProgressList(scores: widget.detail.staffProgressScores),
      ),
    ]);
  }

  List<Widget> _buildRiskSections(BuildContext context) {
    final leftColumn = <Widget>[];
    final rightColumn = <Widget>[];

    if (widget.showPlanConfidence) {
      leftColumn.add(
        _buildSectionPane(
          title: _planConfidenceTitle,
          subtitle: "Confidence and baseline drift for the full lifecycle.",
          child: _PlanConfidenceSection(confidence: widget.detail.confidence),
        ),
      );
    }

    if (widget.showPlanUnits) {
      leftColumn.add(
        _buildSectionPane(
          title: _phaseUnitProgressTitle,
          subtitle:
              "Per-phase unit completion makes remaining field work visible at a glance.",
          child: _PhaseUnitProgressTable(rows: widget.detail.phaseUnitProgress),
        ),
      );
      rightColumn.add(
        _buildSectionPane(
          title: _unitDivergenceTitle,
          subtitle: "Units that are drifting behind the baseline schedule.",
          child: _UnitDivergenceSection(rows: widget.detail.unitDivergence),
        ),
      );
      rightColumn.add(
        _buildSectionPane(
          title: _unitWarningsTitle,
          subtitle:
              "Warnings that need a manager decision before the schedule drifts further.",
          child: _UnitWarningList(warnings: widget.detail.unitScheduleWarnings),
        ),
      );
    }

    if (leftColumn.isEmpty && rightColumn.isEmpty) {
      return _withVerticalSpacing([
        _buildSectionPane(
          title: _riskViewTitle,
          subtitle:
              "This view opens once confidence, unit drift, or governance data is available.",
          child: const _InlineEmptyState(
            title: "No operational risk data yet",
            message:
                "Confidence, unit drift, and governance alerts will appear after the first real production updates.",
          ),
        ),
      ]);
    }

    final sections = <Widget>[
      _ResponsiveSplit(
        left: _buildSectionColumn(leftColumn),
        right: _buildSectionColumn(rightColumn),
        breakpoint: _detailWideSplitBreakpoint,
      ),
    ];

    if (widget.showDeviationGovernance) {
      sections.add(
        _buildSectionPane(
          title: _deviationGovernanceTitle,
          subtitle:
              "Governance actions for drift, locked units, and formal replans.",
          child: _DeviationGovernanceSection(
            summary: widget.detail.deviationGovernanceSummary,
            alerts: widget.detail.deviationAlerts,
            tasks: widget.detail.tasks,
            onAcceptVariance: widget.onAcceptDeviationVariance,
            onReplanUnit: widget.onReplanDeviationUnit,
          ),
        ),
      );
    }

    return _withVerticalSpacing(sections);
  }

  Widget _buildSectionPane({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? action,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ProductionSectionHeader(title: title, subtitle: subtitle),
            ),
            if (action != null) ...[
              const SizedBox(width: _cardSpacing),
              action,
            ],
          ],
        ),
        const SizedBox(height: _cardSpacing),
        child,
      ],
    );
  }

  Widget _buildSectionColumn(List<Widget> sections) {
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _withVerticalSpacing(sections, spacing: _sectionSpacing),
    );
  }

  List<Widget> _withVerticalSpacing(
    List<Widget> children, {
    double spacing = _sectionSpacing,
  }) {
    if (children.isEmpty) {
      return const [];
    }

    return [
      for (int index = 0; index < children.length; index++) ...[
        children[index],
        if (index < children.length - 1) SizedBox(height: spacing),
      ],
    ];
  }
}

class _DetailViewModePicker extends StatelessWidget {
  final _DetailViewMode selectedMode;
  final ValueChanged<_DetailViewMode> onChanged;

  const _DetailViewModePicker({
    required this.selectedMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = <(_DetailViewMode, IconData, String)>[
      (
        _DetailViewMode.overview,
        Icons.dashboard_customize_outlined,
        _overviewViewTitle,
      ),
      (
        _DetailViewMode.execution,
        Icons.playlist_play_outlined,
        _executionViewTitle,
      ),
      (_DetailViewMode.people, Icons.groups_2_outlined, _peopleViewTitle),
      (_DetailViewMode.risk, Icons.shield_outlined, _riskViewTitle),
    ];

    return Wrap(
      spacing: _cardSpacing,
      runSpacing: _cardSpacing,
      children: options.map((option) {
        final isSelected = selectedMode == option.$1;
        return ChoiceChip(
          selected: isSelected,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(option.$2, size: 18),
              const SizedBox(width: 8),
              Text(option.$3),
            ],
          ),
          onSelected: (_) => onChanged(option.$1),
        );
      }).toList(),
    );
  }
}

ProductionAttendanceRecord? _findCompletedAttendanceForStaffOnDate({
  required List<ProductionAttendanceRecord> attendanceRecords,
  required String staffProfileId,
  required DateTime workDate,
}) {
  final normalizedStaffId = staffProfileId.trim();
  if (normalizedStaffId.isEmpty) {
    return null;
  }

  final dayStart = DateTime(workDate.year, workDate.month, workDate.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  for (final record in attendanceRecords) {
    if (record.staffProfileId.trim() != normalizedStaffId) {
      continue;
    }
    final clockInAt = record.clockInAt;
    final clockOutAt = record.clockOutAt;
    if (clockInAt == null || clockOutAt == null) {
      continue;
    }
    if (clockInAt.isBefore(dayEnd) && !clockOutAt.isBefore(dayStart)) {
      return record;
    }
  }
  return null;
}

class _DetailPanel extends StatelessWidget {
  final Widget child;

  const _DetailPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_summaryCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_summaryCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _ResponsiveSplit extends StatelessWidget {
  final Widget left;
  final Widget right;
  final double breakpoint;
  final int leftFlex;
  final int rightFlex;

  const _ResponsiveSplit({
    required this.left,
    required this.right,
    this.breakpoint = _detailSplitBreakpoint,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: _sectionSpacing),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            const SizedBox(width: _sectionSpacing),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData? icon;
  final String label;

  const _InfoPill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? accentColor;

  const _MiniMetricCard({
    required this.label,
    required this.value,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              accentColor?.withValues(alpha: 0.18) ??
              colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputSummarySection extends StatelessWidget {
  final List<ProductionOutput> outputs;
  final Map<String, num> outputByUnit;

  const _OutputSummarySection({
    required this.outputs,
    required this.outputByUnit,
  });

  @override
  Widget build(BuildContext context) {
    if (outputs.isEmpty && outputByUnit.isEmpty) {
      return const _InlineEmptyState(
        title: "No outputs recorded yet",
        message:
            "Harvest or production outputs will appear here once the plan starts producing saleable units.",
      );
    }

    final entries = outputByUnit.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final readyCount = outputs.where((output) => output.readyForSale).length;

    return _DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: _cardSpacing,
            runSpacing: _cardSpacing,
            children: [
              _MiniMetricCard(
                label: "Output records",
                value: "${outputs.length}",
              ),
              _MiniMetricCard(label: "Ready for sale", value: "$readyCount"),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: _cardSpacing),
            Wrap(
              spacing: _cardSpacing,
              runSpacing: _cardSpacing,
              children: entries
                  .map(
                    (entry) => _InfoPill(
                      icon: Icons.inventory_2_outlined,
                      label: "${entry.value} ${entry.key}",
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceRecordSection extends StatelessWidget {
  final List<ProductionAttendanceRecord> records;
  final Map<String, BusinessStaffProfileSummary> staffMap;

  const _AttendanceRecordSection({
    required this.records,
    required this.staffMap,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _InlineEmptyState(
        title: "No attendance activity yet",
        message:
            "Clock-in and clock-out records for this plan will appear here once staff starts logging workdays.",
      );
    }

    final sortedRecords = [...records]
      ..sort((left, right) {
        final leftDate =
            left.clockInAt ??
            left.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.clockInAt ??
            right.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

    return Column(
      children: sortedRecords.take(8).map((record) {
        final staffName = _resolveStaffDisplayName(
          record.staffProfileId,
          staffMap,
        );
        final timeRange =
            "${formatDateTimeLabel(record.clockInAt)} -> ${formatDateTimeLabel(record.clockOutAt)}";
        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        staffName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _InfoPill(
                      icon: Icons.schedule_outlined,
                      label: "${record.durationMinutes} mins",
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(timeRange, style: Theme.of(context).textTheme.bodyMedium),
                if (record.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    record.notes,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PlanConfidenceSection extends StatelessWidget {
  final ProductionPlanConfidence? confidence;

  const _PlanConfidenceSection({required this.confidence});

  @override
  Widget build(BuildContext context) {
    if (confidence == null) {
      return const _InlineEmptyState(
        title: _planConfidenceTitle,
        message: _planConfidenceFallback,
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentPercent =
        "${_formatPercent(confidence!.currentConfidenceScore)}$_percentSuffix";
    final baselinePercent =
        "${_formatPercent(confidence!.baselineConfidenceScore)}$_percentSuffix";
    final deltaRaw = confidence!.confidenceScoreDelta * _percentMultiplier;
    final deltaPercent =
        "${deltaRaw >= 0 ? "+" : ""}${deltaRaw.toStringAsFixed(1)}$_percentSuffix";

    Widget buildRow(String label, String value) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(_summaryCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_summaryCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildRow(_planConfidenceCurrentLabel, currentPercent),
          const SizedBox(height: _summaryMetaSpacing),
          buildRow(_planConfidenceBaselineLabel, baselinePercent),
          const SizedBox(height: _summaryMetaSpacing),
          buildRow(_planConfidenceDeltaLabel, deltaPercent),
          const SizedBox(height: _summaryTitleSpacing),
          buildRow(
            _planConfidenceCapacityLabel,
            "${_formatPercent(confidence!.currentBreakdown.capacity)}$_percentSuffix",
          ),
          const SizedBox(height: _summaryMetaSpacing),
          buildRow(
            _planConfidenceScheduleLabel,
            "${_formatPercent(confidence!.currentBreakdown.scheduleStability)}$_percentSuffix",
          ),
          const SizedBox(height: _summaryMetaSpacing),
          buildRow(
            _planConfidenceReliabilityLabel,
            "${_formatPercent(confidence!.currentBreakdown.historicalReliability)}$_percentSuffix",
          ),
          const SizedBox(height: _summaryMetaSpacing),
          buildRow(
            _planConfidenceComplexityLabel,
            "${_formatPercent(confidence!.currentBreakdown.complexityRisk)}$_percentSuffix",
          ),
        ],
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  final ProductionPlan plan;
  final ProductionPreorderSummary? preorderSummary;
  final bool isOwner;
  final bool showPlanUnits;
  final bool showPlanConfidence;
  final int? planUnitsCount;
  final bool planUnitsLoading;
  final bool planUnitsHasError;
  final Future<void> Function() onReconcilePreorders;
  final Future<void> Function(Map<String, dynamic> payload) onUpdatePreorder;

  const _PlanSummaryCard({
    required this.plan,
    required this.preorderSummary,
    required this.isOwner,
    required this.showPlanUnits,
    required this.showPlanConfidence,
    required this.planUnitsCount,
    required this.planUnitsLoading,
    required this.planUnitsHasError,
    required this.onReconcilePreorders,
    required this.onUpdatePreorder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final domainLabel = formatProductionDomainLabel(plan.domainContext);
    final plantingTargets = plan.plantingTargets;
    String formatTargetNumber(double value) {
      if (value <= 0) {
        return "0";
      }
      final rounded = value.roundToDouble();
      if (rounded == value) {
        return rounded.toInt().toString();
      }
      return value.toStringAsFixed(value < 10 ? 2 : 1);
    }

    String formatMaterialLabel(String value) {
      switch (value.trim().toLowerCase()) {
        case "seed":
          return "seed";
        case "seedling":
          return "seedling";
        case "root":
          return "root";
        case "stem":
          return "stem";
        case "cutting":
          return "cutting";
        case "tuber":
          return "tuber";
        case "sucker":
          return "sucker";
        case "runner":
          return "runner";
        default:
          return value.trim().isEmpty ? "material" : value.trim().toLowerCase();
      }
    }

    final confidencePercent = preorderSummary == null
        ? 0
        : (preorderSummary!.confidenceScore * _percentMultiplier)
              .clamp(_percentMin, _percentMultiplier)
              .toDouble()
              .round();
    final coveragePercent = preorderSummary == null
        ? 0
        : (preorderSummary!.approvedProgressCoverage * _percentMultiplier)
              .clamp(_percentMin, _percentMultiplier)
              .toDouble()
              .round();
    final planUnitsValue = planUnitsLoading
        ? _planUnitsLoadingLabel
        : planUnitsHasError
        ? _planUnitsUnavailableLabel
        : "${planUnitsCount ?? 0}";
    final scheduleRange = _formatReadableDateRange(
      plan.startDate,
      plan.endDate,
    );
    final durationLabel = _formatPlanDuration(plan.startDate, plan.endDate);
    final summaryActions = preorderSummary != null && isOwner
        ? Wrap(
            spacing: _summaryMetaSpacing,
            runSpacing: _summaryMetaSpacing,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final payload = await _showPreorderConfigDialog(
                    context,
                    summary: preorderSummary,
                  );
                  if (payload == null) {
                    return;
                  }
                  await onUpdatePreorder(payload);
                },
                icon: const Icon(Icons.tune),
                label: const Text(_configurePreorderButtonLabel),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await onReconcilePreorders();
                },
                icon: const Icon(Icons.restore_from_trash_outlined),
                label: const Text(_reconcileButtonLabel),
              ),
            ],
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(_summaryCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_summaryCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _detailSplitBreakpoint;
          final signalTiles = Wrap(
            spacing: _cardSpacing,
            runSpacing: _cardSpacing,
            children: [
              _SummarySignalTile(
                icon: Icons.category_outlined,
                label: "Context",
                value: domainLabel,
              ),
              _SummarySignalTile(
                icon: Icons.date_range_outlined,
                label: "Window",
                value: scheduleRange,
              ),
              _SummarySignalTile(
                icon: Icons.timelapse_outlined,
                label: "Duration",
                value: durationLabel,
              ),
              if (plantingTargets?.isConfigured == true)
                _SummarySignalTile(
                  icon: Icons.grass_outlined,
                  label: "Planting",
                  value:
                      "${formatTargetNumber(plantingTargets!.plannedPlantingQuantity)} ${plantingTargets.plannedPlantingUnit} (${formatMaterialLabel(plantingTargets.materialType)})",
                  helper:
                      "Harvest est. ${formatTargetNumber(plantingTargets.estimatedHarvestQuantity)} ${plantingTargets.estimatedHarvestUnit}",
                ),
              if (showPlanUnits)
                _SummarySignalTile(
                  icon: Icons.grid_view_outlined,
                  label: _planUnitsLabel,
                  value: planUnitsValue,
                ),
              _SummarySignalTile(
                icon: Icons.inventory_2_outlined,
                label: _productionStateLabel,
                value: preorderSummary?.productionState.isNotEmpty == true
                    ? preorderSummary!.productionState
                    : _dash,
              ),
              _SummarySignalTile(
                icon: Icons.sell_outlined,
                label: _preorderLabel,
                value: preorderSummary?.preorderEnabled == true
                    ? _preorderEnabledLabel
                    : _preorderDisabledLabel,
              ),
              if (preorderSummary != null)
                _SummarySignalTile(
                  icon: Icons.stacked_bar_chart_outlined,
                  label: _preorderCapLabel,
                  value: "${preorderSummary!.preorderCapQuantity}",
                ),
              if (preorderSummary != null)
                _SummarySignalTile(
                  icon: Icons.precision_manufacturing_outlined,
                  label: _effectiveCapLabel,
                  value: "${preorderSummary!.effectiveCap}",
                ),
              if (preorderSummary != null)
                _SummarySignalTile(
                  icon: Icons.shopping_bag_outlined,
                  label: _preorderRemainingLabel,
                  value: "${preorderSummary!.preorderRemainingQuantity}",
                ),
              if (showPlanConfidence && preorderSummary != null)
                _SummarySignalTile(
                  icon: Icons.verified_outlined,
                  label: _confidenceLabel,
                  value: "$confidencePercent%",
                  helper: "Coverage $coveragePercent%",
                ),
            ],
          );

          final leadColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _summaryTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _summaryTitleSpacing),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.title,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _InfoPill(
                              icon: Icons.spa_outlined,
                              label: domainLabel,
                            ),
                            _InfoPill(
                              icon: Icons.event_available_outlined,
                              label: scheduleRange,
                            ),
                            _InfoPill(
                              icon: Icons.history_toggle_off_outlined,
                              label: durationLabel,
                            ),
                            if (plantingTargets?.isConfigured == true)
                              _InfoPill(
                                icon: Icons.grass_outlined,
                                label:
                                    "${formatTargetNumber(plantingTargets!.plannedPlantingQuantity)} ${plantingTargets.plannedPlantingUnit} (${formatMaterialLabel(plantingTargets.materialType)})",
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _cardSpacing),
                  ProductionStatusPill(label: plan.status),
                ],
              ),
              const SizedBox(height: _sectionSpacing),
              signalTiles,
            ],
          );

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leadColumn,
                if (summaryActions != null) ...[
                  const SizedBox(height: _sectionSpacing),
                  summaryActions,
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: leadColumn),
              const SizedBox(width: _sectionSpacing),
              if (summaryActions != null)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Owner actions",
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: _summaryTitleSpacing),
                      Text(
                        "Keep pre-order controls and expired hold clean-up in one place.",
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: _cardSpacing),
                      summaryActions,
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final ProductionKpis? kpis;

  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) {
    if (kpis == null) {
      return const _InlineEmptyState(
        title: _kpiEmptyTitle,
        message: _kpiEmptyMessage,
      );
    }

    final completion = "${_formatPercent(kpis!.completionRate)}$_percentSuffix";
    final onTime = "${_formatPercent(kpis!.onTimeRate)}$_percentSuffix";
    final avgDelay =
        "${kpis!.avgDelayDays.toStringAsFixed(_delayFixedDigits)} $_daysSuffix";

    return _DetailPanel(
      child: Wrap(
        spacing: _cardSpacing,
        runSpacing: _cardSpacing,
        children: [
          ProductionKpiCard(
            label: _kpiTotalTasks,
            value: "${kpis!.totalTasks}",
          ),
          ProductionKpiCard(
            label: _kpiCompleted,
            value: "${kpis!.completedTasks}",
          ),
          ProductionKpiCard(label: _kpiOnTime, value: onTime),
          ProductionKpiCard(label: _kpiAvgDelay, value: avgDelay),
          ProductionKpiCard(label: _phaseCompletionLabel, value: completion),
        ],
      ),
    );
  }
}

class _AttendanceImpactSection extends StatelessWidget {
  final ProductionAttendanceImpact? attendanceImpact;

  const _AttendanceImpactSection({required this.attendanceImpact});

  @override
  Widget build(BuildContext context) {
    if (attendanceImpact == null || attendanceImpact!.totalRollupDays <= 0) {
      return const _InlineEmptyState(
        title: _attendanceImpactEmptyTitle,
        message: _attendanceImpactEmptyMessage,
      );
    }

    final coverage =
        "${_formatPercent(attendanceImpact!.attendanceCoverageRate)}$_percentSuffix";
    final absenteeImpact =
        "${_formatPercent(attendanceImpact!.absenteeImpactRate)}$_percentSuffix";
    final linkedProgress =
        "${_formatPercent(attendanceImpact!.attendanceLinkedProgressRate)}$_percentSuffix";
    final plotsPerHour = attendanceImpact!.plotsPerAttendedHour.toStringAsFixed(
      _delayFixedDigits,
    );

    return _DetailPanel(
      child: Wrap(
        spacing: _cardSpacing,
        runSpacing: _cardSpacing,
        children: [
          ProductionKpiCard(label: _kpiAttendanceCoverage, value: coverage),
          ProductionKpiCard(label: _kpiAbsenteeImpact, value: absenteeImpact),
          ProductionKpiCard(label: _kpiLinkedProgress, value: linkedProgress),
          ProductionKpiCard(label: _kpiPlotsPerHour, value: plotsPerHour),
          ProductionKpiCard(
            label: _kpiTrackedDays,
            value:
                "${attendanceImpact!.scheduledDays}/${attendanceImpact!.totalRollupDays}",
          ),
        ],
      ),
    );
  }
}

class _DailyRollupTable extends StatelessWidget {
  final List<ProductionDailyRollup> rollups;

  const _DailyRollupTable({required this.rollups});

  @override
  Widget build(BuildContext context) {
    if (rollups.isEmpty) {
      return const _InlineEmptyState(
        title: _dailyRollupEmptyTitle,
        message: _dailyRollupEmptyMessage,
      );
    }

    final sortedRollups = [...rollups]
      ..sort((left, right) {
        final leftDate =
            left.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

    return Column(
      children: sortedRollups.map((rollup) {
        final coverage =
            "${_formatPercent(rollup.attendanceCoverageRate)}$_percentSuffix";
        final completion =
            "${_formatPercent(rollup.completionRate)}$_percentSuffix";
        final plotsPerHour = rollup.plotsPerAttendedHour.toStringAsFixed(
          _delayFixedDigits,
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatDateLabel(rollup.workDate),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ProductionStatusPill(
                      label: rollup.completionRate >= 1
                          ? _taskStatusDone
                          : rollup.actualPlots > 0
                          ? _taskStatusInProgress
                          : _taskStatusPending,
                    ),
                  ],
                ),
                const SizedBox(height: _cardSpacing),
                Wrap(
                  spacing: _cardSpacing,
                  runSpacing: _cardSpacing,
                  children: [
                    _MiniMetricCard(
                      label: _dailyRollupBlocksLabel,
                      value: "${rollup.scheduledTaskBlocks}",
                    ),
                    _MiniMetricCard(
                      label: _dailyRollupAssignedLabel,
                      value: "${rollup.assignedStaffCount}",
                    ),
                    _MiniMetricCard(
                      label: _dailyRollupAttendedAssignedLabel,
                      value: "${rollup.attendedAssignedStaffCount}",
                    ),
                    _MiniMetricCard(
                      label: _dailyRollupAbsentLabel,
                      value: "${rollup.absentAssignedStaffCount}",
                    ),
                  ],
                ),
                const SizedBox(height: _cardSpacing),
                Wrap(
                  spacing: _cardSpacing,
                  runSpacing: _cardSpacing,
                  children: [
                    _InfoPill(
                      icon: Icons.track_changes_outlined,
                      label:
                          "$_dailyRollupExpectedLabel: ${rollup.expectedPlots}",
                    ),
                    _InfoPill(
                      icon: Icons.done_all_outlined,
                      label: "$_dailyRollupActualLabel: ${rollup.actualPlots}",
                    ),
                    _InfoPill(
                      icon: Icons.groups_outlined,
                      label: "$_dailyRollupCoverageLabel: $coverage",
                    ),
                    _InfoPill(
                      icon: Icons.speed_outlined,
                      label: "$_dailyRollupPlotsPerHourLabel: $plotsPerHour",
                    ),
                    _InfoPill(
                      icon: Icons.event_note_outlined,
                      label: "${rollup.rowsLogged} logs",
                    ),
                    _InfoPill(
                      icon: Icons.flag_outlined,
                      label: "$_dailyRollupCompletionLabel: $completion",
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StaffProgressList extends StatelessWidget {
  final List<ProductionStaffProgressScore> scores;

  const _StaffProgressList({required this.scores});

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return const _InlineEmptyState(
        title: _staffProgressEmptyTitle,
        message: _staffProgressEmptyMessage,
      );
    }

    final sortedScores = [...scores]
      ..sort(
        (left, right) => right.completionRatio.compareTo(left.completionRatio),
      );

    return Column(
      children: sortedScores.map((score) {
        final farmerName = score.farmerName.trim().isEmpty
            ? score.staffId
            : score.farmerName;
        final percent = _formatPercent(score.completionRatio);
        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        farmerName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ProductionStatusPill(label: score.status),
                  ],
                ),
                const SizedBox(height: _cardSpacing),
                Wrap(
                  spacing: _cardSpacing,
                  runSpacing: _cardSpacing,
                  children: [
                    _MiniMetricCard(
                      label: "Expected",
                      value: "${score.totalExpected}",
                    ),
                    _MiniMetricCard(
                      label: "Actual",
                      value: "${score.totalActual}",
                    ),
                    _MiniMetricCard(
                      label: "Completion",
                      value: "$percent$_percentSuffix",
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PhaseProgressList extends StatelessWidget {
  final ProductionKpis? kpis;

  const _PhaseProgressList({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final phaseCompletion = kpis?.phaseCompletion ?? [];
    if (phaseCompletion.isEmpty) {
      return const _InlineEmptyState(
        title: _phaseEmptyTitle,
        message: _phaseEmptyMessage,
      );
    }

    return _DetailPanel(
      child: Column(
        children: phaseCompletion.map((phase) {
          final progressValue = phase.completionRate
              .clamp(_progressMin, _progressMax)
              .toDouble();
          final percent =
              "${_formatPercent(phase.completionRate)}$_percentSuffix";
          return Padding(
            padding: const EdgeInsets.only(bottom: _cardSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: _phaseProgressSpacing),
                LinearProgressIndicator(
                  value: progressValue,
                  minHeight: _progressIndicatorHeight,
                ),
                const SizedBox(height: _phaseProgressSpacing),
                Text(
                  "${phase.completedTasks}/${phase.totalTasks} ($percent)",
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PhaseUnitProgressTable extends StatelessWidget {
  final List<ProductionPhaseUnitProgress> rows;

  const _PhaseUnitProgressTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _InlineEmptyState(
        title: _phaseUnitEmptyTitle,
        message: _phaseUnitEmptyMessage,
      );
    }

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.phaseName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (row.isLocked)
                      const _InfoPill(
                        icon: Icons.lock_outline,
                        label: _deviationLockedTag,
                      ),
                  ],
                ),
                const SizedBox(height: _cardSpacing),
                Wrap(
                  spacing: _cardSpacing,
                  runSpacing: _cardSpacing,
                  children: [
                    _MiniMetricCard(
                      label: _phaseUnitRequiredLabel,
                      value: "${row.requiredUnits}",
                    ),
                    _MiniMetricCard(
                      label: _phaseUnitCompletedLabel,
                      value: "${row.completedUnitCount}",
                    ),
                    _MiniMetricCard(
                      label: _phaseUnitRemainingLabel,
                      value: "${row.remainingUnits}",
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _UnitDivergenceSection extends StatelessWidget {
  final List<ProductionUnitDivergence> rows;

  const _UnitDivergenceSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _InlineEmptyState(
        title: _unitDivergenceEmptyTitle,
        message: _unitDivergenceEmptyMessage,
      );
    }

    final sortedRows = [...rows]
      ..sort((left, right) {
        final delayedCompare = right.delayedByDays.compareTo(
          left.delayedByDays,
        );
        if (delayedCompare != 0) {
          return delayedCompare;
        }
        return left.unitIndex.compareTo(right.unitIndex);
      });

    return Column(
      children: sortedRows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.unitLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (row.updatedAt != null)
                      _InfoPill(
                        icon: Icons.update_outlined,
                        label: formatDateLabel(row.updatedAt),
                      ),
                  ],
                ),
                const SizedBox(height: _cardSpacing),
                Wrap(
                  spacing: _cardSpacing,
                  runSpacing: _cardSpacing,
                  children: [
                    _MiniMetricCard(
                      label: _unitDivergenceDelayLabel,
                      value: "${row.delayedByDays}",
                      accentColor: row.delayedByDays > 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    _MiniMetricCard(
                      label: _unitDivergenceShiftedTasksLabel,
                      value: "${row.shiftedTaskCount}",
                    ),
                    _MiniMetricCard(
                      label: _unitDivergenceWarningCountLabel,
                      value: "${row.warningCount}",
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _UnitWarningList extends StatelessWidget {
  final List<ProductionUnitScheduleWarning> warnings;

  const _UnitWarningList({required this.warnings});

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) {
      return const _InlineEmptyState(
        title: _unitWarningsEmptyTitle,
        message: _unitWarningsEmptyMessage,
      );
    }

    final sortedWarnings = [...warnings]
      ..sort((left, right) {
        final leftDate =
            left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

    return Column(
      children: sortedWarnings.map((warning) {
        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        warning.unitLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _InfoPill(
                      icon: Icons.warning_amber_rounded,
                      label: "${warning.severity} • ${warning.warningType}",
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  warning.taskTitle.trim().isEmpty ? _dash : warning.taskTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  warning.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: _cardSpacing),
                Wrap(
                  spacing: _cardSpacing,
                  runSpacing: _cardSpacing,
                  children: [
                    _InfoPill(
                      icon: Icons.swap_horiz_outlined,
                      label: "${warning.shiftDays} $_daysSuffix",
                    ),
                    _InfoPill(
                      icon: Icons.event_outlined,
                      label: formatDateLabel(warning.createdAt),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DeviationGovernanceSection extends StatelessWidget {
  final ProductionDeviationGovernanceSummary? summary;
  final List<ProductionDeviationAlert> alerts;
  final List<ProductionTask> tasks;
  final Future<void> Function(String alertId, String note) onAcceptVariance;
  final Future<void> Function(
    String alertId,
    List<Map<String, dynamic>> taskAdjustments,
    String note,
  )
  onReplanUnit;

  const _DeviationGovernanceSection({
    required this.summary,
    required this.alerts,
    required this.tasks,
    required this.onAcceptVariance,
    required this.onReplanUnit,
  });

  @override
  Widget build(BuildContext context) {
    if (summary == null && alerts.isEmpty) {
      return const _InlineEmptyState(
        title: _deviationSummaryEmptyTitle,
        message: _deviationSummaryEmptyMessage,
      );
    }

    final taskById = {for (final task in tasks) task.id: task};
    final sortedAlerts = [...alerts]
      ..sort((left, right) {
        final leftOpen = left.status == "open" ? 0 : 1;
        final rightOpen = right.status == "open" ? 0 : 1;
        final statusCompare = leftOpen.compareTo(rightOpen);
        if (statusCompare != 0) {
          return statusCompare;
        }
        final leftDate =
            left.triggeredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.triggeredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          Wrap(
            spacing: _cardSpacing,
            runSpacing: _cardSpacing,
            children: [
              _DeviationMetricCard(
                title: _deviationSummaryTotalAlerts,
                value: "${summary!.totalAlerts}",
              ),
              _DeviationMetricCard(
                title: _deviationSummaryOpenAlerts,
                value: "${summary!.openAlerts}",
              ),
              _DeviationMetricCard(
                title: _deviationSummaryLockedUnits,
                value: "${summary!.lockedUnits}",
              ),
            ],
          ),
        if (sortedAlerts.isNotEmpty) ...[
          const SizedBox(height: _cardSpacing),
          Column(
            children: sortedAlerts.map((alert) {
              final sourceTask = taskById[alert.sourceTaskId];
              final canReplan = sourceTask != null;
              final statusLabel = _formatDeviationStatus(alert.status);
              final lockLabel = alert.unitLocked
                  ? _deviationLockedTag
                  : _deviationUnlockedTag;
              final sourceTaskTitle = alert.sourceTaskTitle.trim().isEmpty
                  ? _dash
                  : alert.sourceTaskTitle;
              final hasResolutionNote = alert.resolutionNote.trim().isNotEmpty;

              return Padding(
                padding: const EdgeInsets.only(bottom: _cardSpacing),
                child: _DetailPanel(
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
                                  alert.unitLabel,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  sourceTaskTitle,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: _cardSpacing),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              _InfoPill(
                                icon: Icons.policy_outlined,
                                label: statusLabel,
                              ),
                              _InfoPill(
                                icon: alert.unitLocked
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined,
                                label: lockLabel,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: _cardSpacing),
                      Text(
                        alert.message,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: _cardSpacing),
                      Wrap(
                        spacing: _cardSpacing,
                        runSpacing: _cardSpacing,
                        children: [
                          _MiniMetricCard(
                            label: _deviationAlertDeviationLabel,
                            value:
                                "${alert.cumulativeDeviationDays} $_daysSuffix",
                          ),
                          _MiniMetricCard(
                            label: _deviationAlertThresholdLabel,
                            value: "${alert.thresholdDays} $_daysSuffix",
                          ),
                        ],
                      ),
                      const SizedBox(height: _cardSpacing),
                      Wrap(
                        spacing: _cardSpacing,
                        runSpacing: _cardSpacing,
                        children: [
                          _InfoPill(
                            icon: Icons.event_outlined,
                            label: formatDateLabel(alert.triggeredAt),
                          ),
                          if (alert.resolvedAt != null)
                            _InfoPill(
                              icon: Icons.task_alt_outlined,
                              label:
                                  "Resolved ${formatDateLabel(alert.resolvedAt)}",
                            ),
                          if (alert.unitLockedAt != null)
                            _InfoPill(
                              icon: Icons.schedule_outlined,
                              label:
                                  "Locked ${formatDateLabel(alert.unitLockedAt)}",
                            ),
                        ],
                      ),
                      if (hasResolutionNote) ...[
                        const SizedBox(height: _cardSpacing),
                        Text(
                          alert.resolutionNote,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      const SizedBox(height: _cardSpacing),
                      Wrap(
                        spacing: _cardSpacing,
                        runSpacing: _cardSpacing,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final note = await _showDeviationVarianceDialog(
                                context,
                                alert: alert,
                              );
                              if (note == null) {
                                return;
                              }
                              await onAcceptVariance(alert.alertId, note);
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text(_deviationAcceptLabel),
                          ),
                          OutlinedButton.icon(
                            onPressed: canReplan
                                ? () async {
                                    final input =
                                        await _showDeviationReplanDialog(
                                          context,
                                          alert: alert,
                                          sourceTask: sourceTask,
                                        );
                                    if (input == null) {
                                      return;
                                    }
                                    await onReplanUnit(
                                      alert.alertId,
                                      input.taskAdjustments,
                                      input.note,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.event_repeat_outlined),
                            label: const Text(_deviationReplanLabel),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _DeviationMetricCard extends StatelessWidget {
  final String title;
  final String value;

  const _DeviationMetricCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 170,
      padding: const EdgeInsets.all(_summaryCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_summaryCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _summaryMetaSpacing),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SummarySignalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? helper;

  const _SummarySignalTile({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (helper != null && helper!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              helper!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String title;
  final String message;

  const _InlineEmptyState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_summaryCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_summaryCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.spa_outlined, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class _TimelineTaskTable extends StatelessWidget {
  final List<ProductionTimelineRow> rows;
  final bool canReviewProgress;
  final Future<void> Function(String progressId) onApproveProgress;
  final Future<void> Function(String progressId, String reason)
  onRejectProgress;

  const _TimelineTaskTable({
    required this.rows,
    required this.canReviewProgress,
    required this.onApproveProgress,
    required this.onRejectProgress,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _InlineEmptyState(
        title: _timelineEmptyTitle,
        message: _timelineEmptyMessage,
      );
    }

    final sortedRows = [...rows]
      ..sort((left, right) {
        final leftDate =
            left.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateCompare = rightDate.compareTo(leftDate);
        if (dateCompare != 0) {
          return dateCompare;
        }
        return left.taskTitle.compareTo(right.taskTitle);
      });

    final groupedRows = <String, List<ProductionTimelineRow>>{};
    final groupOrder = <String>[];
    for (final row in sortedRows) {
      final date = row.workDate;
      final key = date == null
          ? "undated"
          : "${date.year}-${date.month}-${date.day}";
      if (!groupedRows.containsKey(key)) {
        groupedRows[key] = <ProductionTimelineRow>[];
        groupOrder.add(key);
      }
      groupedRows[key]!.add(row);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groupOrder.map((groupKey) {
        final dayRows = groupedRows[groupKey]!;
        final dayLabel = formatDateLabel(dayRows.first.workDate);
        return Padding(
          padding: const EdgeInsets.only(bottom: _sectionSpacing),
          child: _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dayLabel,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _InfoPill(
                      icon: Icons.event_note_outlined,
                      label: "${dayRows.length} $_tasksSuffix",
                    ),
                  ],
                ),
                const SizedBox(height: _cardSpacing),
                Column(
                  children: dayRows.map((row) {
                    final notes = row.notes.trim().isEmpty ? "" : row.notes;
                    final delayReason = row.delayReason.trim();
                    final approvalLabel = _formatProgressApprovalLabel(
                      row.approvalState,
                    );
                    final canAction =
                        canReviewProgress &&
                        row.approvalState != _progressApprovalApproved;

                    return Container(
                      margin: const EdgeInsets.only(bottom: _cardSpacing),
                      padding: const EdgeInsets.all(_summaryCardPadding),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(_summaryCardRadius),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
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
                                      row.taskTitle,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "${row.phaseName} • ${row.farmerName}",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: _cardSpacing),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ProductionStatusPill(label: row.status),
                                  const SizedBox(height: 8),
                                  _InfoPill(
                                    icon: Icons.verified_outlined,
                                    label: approvalLabel,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: _cardSpacing),
                          Wrap(
                            spacing: _cardSpacing,
                            runSpacing: _cardSpacing,
                            children: [
                              _MiniMetricCard(
                                label: _timelineExpectedLabel,
                                value: "${row.expectedPlots}",
                              ),
                              _MiniMetricCard(
                                label: _timelineActualLabel,
                                value: "${row.actualPlots}",
                              ),
                              _MiniMetricCard(
                                label: _timelineDelayLabel,
                                value: row.delay.trim().isEmpty
                                    ? _dash
                                    : row.delay,
                              ),
                            ],
                          ),
                          const SizedBox(height: _cardSpacing),
                          Wrap(
                            spacing: _cardSpacing,
                            runSpacing: _cardSpacing,
                            children: [
                              if (delayReason.isNotEmpty &&
                                  delayReason != _delayReasonNone)
                                _InfoPill(
                                  icon: Icons.warning_amber_outlined,
                                  label: delayReason,
                                ),
                              if (row.approvedAt != null)
                                _InfoPill(
                                  icon: Icons.schedule_outlined,
                                  label:
                                      "Approved ${formatDateLabel(row.approvedAt)}",
                                ),
                              if (row.approvedBy.trim().isNotEmpty)
                                _InfoPill(
                                  icon: Icons.person_outline,
                                  label: row.approvedBy,
                                ),
                              if (row.proofs.isNotEmpty)
                                _InfoPill(
                                  icon: Icons.photo_library_outlined,
                                  label: "${row.proofCount} proof(s)",
                                ),
                            ],
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: _cardSpacing),
                            Text(
                              notes,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                          if (row.proofs.isNotEmpty) ...[
                            const SizedBox(height: _cardSpacing),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  showProductionTaskProgressProofBrowser(
                                    context,
                                    rows: rows,
                                    initialDate: row.workDate,
                                  );
                                },
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text(_viewProofLabel),
                              ),
                            ),
                          ],
                          if (canAction) ...[
                            const SizedBox(height: _cardSpacing),
                            Wrap(
                              spacing: _cardSpacing,
                              runSpacing: _cardSpacing,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await onApproveProgress(row.id);
                                  },
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text(_approveLabel),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await _showProgressRejectDialog(
                                      context,
                                      onReject: (reason) =>
                                          onRejectProgress(row.id, reason),
                                    );
                                  },
                                  icon: const Icon(Icons.rate_review_outlined),
                                  label: const Text(_rejectLabel),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PhaseTaskSection extends StatelessWidget {
  final ProductionPhase phase;
  final List<ProductionTask> tasks;
  final List<ProductionAttendanceRecord> attendanceRecords;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final bool canLogProgress;
  final bool showPlanUnits;
  final Map<String, String> planUnitLabelById;
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(
    String taskId,
    String? staffId,
    String? unitId,
    DateTime workDate,
    num actualPlots,
    List<ProductionTaskProgressProofInput> proofs,
    String delayReason,
    String notes,
  )
  onLogProgress;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _PhaseTaskSection({
    required this.phase,
    required this.tasks,
    required this.attendanceRecords,
    required this.staffMap,
    required this.isOwner,
    required this.canLogProgress,
    required this.showPlanUnits,
    required this.planUnitLabelById,
    required this.onStatusChange,
    required this.onLogProgress,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(phase.name),
      subtitle: Text("${tasks.length} $_tasksSuffix"),
      children: tasks.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(_phaseEmptyPadding),
                child: Text(_phaseEmptyTasks),
              ),
            ]
          : tasks
                .map(
                  (task) => _TaskCard(
                    task: task,
                    attendanceRecords: attendanceRecords,
                    staffMap: staffMap,
                    isOwner: isOwner,
                    canLogProgress: canLogProgress,
                    showPlanUnits: showPlanUnits,
                    planUnitLabelById: planUnitLabelById,
                    onStatusChange: onStatusChange,
                    onLogProgress: onLogProgress,
                    onApprove: onApprove,
                    onReject: onReject,
                  ),
                )
                .toList(),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final ProductionTask task;
  final List<ProductionAttendanceRecord> attendanceRecords;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final bool canLogProgress;
  final bool showPlanUnits;
  final Map<String, String> planUnitLabelById;
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(
    String taskId,
    String? staffId,
    String? unitId,
    DateTime workDate,
    num actualPlots,
    List<ProductionTaskProgressProofInput> proofs,
    String delayReason,
    String notes,
  )
  onLogProgress;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _TaskCard({
    required this.task,
    required this.attendanceRecords,
    required this.staffMap,
    required this.isOwner,
    required this.canLogProgress,
    required this.showPlanUnits,
    required this.planUnitLabelById,
    required this.onStatusChange,
    required this.onLogProgress,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final assignedStaffIds = _resolveAssignedStaffIds(task);
    final staffName = _buildAssignedStaffLabel(assignedStaffIds, staffMap);
    final assignedUnitsLabel = _buildAssignedUnitLabel(
      assignedUnitIds: task.assignedUnitIds,
      planUnitLabelById: planUnitLabelById,
    );

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: _taskCardMarginHorizontal,
        vertical: _taskCardMarginVertical,
      ),
      padding: const EdgeInsets.all(_taskCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_taskCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ProductionStatusPill(label: task.status),
            ],
          ),
          const SizedBox(height: _taskTitleSpacing),
          Text(
            "$_assignedLabel: $staffName",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _taskMetaSpacing),
          Text(
            "$_roleLabel: ${task.roleRequired}",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (showPlanUnits) ...[
            // UNIT-LIFECYCLE: manager preview exposes concrete units assigned to each scheduled task.
            const SizedBox(height: _taskMetaSpacing),
            Text(
              "$_assignedUnitsLabel: $assignedUnitsLabel",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: _taskMetaSpacing),
          Text(
            "$_dueLabel: ${formatDateLabel(task.dueDate)}",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _taskActionsSpacing),
          _TaskStatusDropdown(
            currentStatus: task.status,
            onChanged: (value) {
              if (value == null || value == task.status) return;
              onStatusChange(task.id, value);
            },
          ),
          if (canLogProgress)
            Padding(
              padding: const EdgeInsets.only(top: _approvalTopSpacing),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final input = await _showLogProgressDialog(
                    context,
                    assignedStaffIds: assignedStaffIds,
                    assignedUnitIds: task.assignedUnitIds,
                    staffMap: staffMap,
                    planUnitLabelById: planUnitLabelById,
                    attendanceRecords: attendanceRecords,
                    taskTargetPlots: task.weight,
                  );
                  if (input == null) {
                    return;
                  }
                  await onLogProgress(
                    task.id,
                    input.staffId,
                    input.unitId,
                    input.workDate,
                    input.actualPlots,
                    input.proofs,
                    input.delayReason,
                    input.notes,
                  );
                },
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text(_logProgressLabel),
              ),
            ),
          if (task.approvalStatus == _approvalPending)
            _ApprovalActions(
              isOwner: isOwner,
              onApprove: () => onApprove(task.id),
              onReject: () => _showRejectDialog(
                context,
                onReject: (reason) => onReject(task.id, reason),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: _approvalTopSpacing),
              child: Text(
                _approvalLabel(task.approvalStatus),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskStatusDropdown extends StatelessWidget {
  final String currentStatus;
  final ValueChanged<String?> onChanged;

  const _TaskStatusDropdown({
    required this.currentStatus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: currentStatus,
      decoration: const InputDecoration(
        labelText: _statusLabel,
        border: OutlineInputBorder(),
      ),
      // WHY: Status options mirror backend task statuses.
      items: _taskStatusOptions
          .map((status) => DropdownMenuItem(value: status, child: Text(status)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _ApprovalActions extends StatelessWidget {
  final bool isOwner;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalActions({
    required this.isOwner,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOwner) {
      return Padding(
        padding: const EdgeInsets.only(top: _approvalTopSpacing),
        child: Text(
          _approvalPendingLabel,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: _approvalTopSpacing),
      child: Wrap(
        spacing: _taskActionsSpacing,
        children: [
          TextButton(onPressed: onApprove, child: const Text(_approveLabel)),
          TextButton(onPressed: onReject, child: const Text(_rejectLabel)),
        ],
      ),
    );
  }
}

class _LogProgressInput {
  final String? staffId;
  final String? unitId;
  final DateTime workDate;
  final num actualPlots;
  final List<ProductionTaskProgressProofInput> proofs;
  final String delayReason;
  final String notes;

  const _LogProgressInput({
    required this.staffId,
    required this.unitId,
    required this.workDate,
    required this.actualPlots,
    required this.proofs,
    required this.delayReason,
    required this.notes,
  });
}

class _DeviationReplanInput {
  final List<Map<String, dynamic>> taskAdjustments;
  final String note;

  const _DeviationReplanInput({
    required this.taskAdjustments,
    required this.note,
  });
}

class _BatchLogProgressInput {
  final DateTime workDate;
  final List<ProductionTaskProgressBatchEntryInput> entries;

  const _BatchLogProgressInput({required this.workDate, required this.entries});
}

class _BatchLogRowDraft {
  final String rowId;
  final String taskId;
  final String taskTitle;
  final String phaseName;
  final String staffId;
  final String staffName;
  final String unitId;
  final String unitLabel;
  final num expectedPlots;
  final bool isRecordedLocked;
  bool skip;
  String actualPlotsText;
  String delayReason;
  String notes;
  String validationError;

  _BatchLogRowDraft({
    required this.rowId,
    required this.taskId,
    required this.taskTitle,
    required this.phaseName,
    required this.staffId,
    required this.staffName,
    required this.unitId,
    required this.unitLabel,
    required this.expectedPlots,
    required this.isRecordedLocked,
    required this.skip,
    required this.actualPlotsText,
    required this.delayReason,
    required this.notes,
    required this.validationError,
  });
}

Future<_BatchLogProgressInput?> _showBatchLogProgressDialog(
  BuildContext context, {
  required ProductionPlanDetail detail,
  required Map<String, BusinessStaffProfileSummary> staffMap,
  required Map<String, String> planUnitLabelById,
}) async {
  // WHY: Batch logging lets managers submit multiple real daily updates in one pass.
  DateTime selectedDate = DateTime.now();
  List<_BatchLogRowDraft> rows = _buildBatchLogRowsForDate(
    workDate: selectedDate,
    detail: detail,
    staffMap: staffMap,
    planUnitLabelById: planUnitLabelById,
  );
  String formError = "";

  final result = await showDialog<_BatchLogProgressInput>(
    context: context,
    builder: (dialogBuildContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text(_batchLogDialogTitle),
            content: SizedBox(
              width: 1100,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$_batchLogDateLabel: ${formatDateLabel(selectedDate)}"),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedDate = picked;
                        rows = _buildBatchLogRowsForDate(
                          workDate: selectedDate,
                          detail: detail,
                          staffMap: staffMap,
                          planUnitLabelById: planUnitLabelById,
                        );
                        formError = "";
                      });
                    },
                    child: const Text(_batchLogDateButtonLabel),
                  ),
                  Text(
                    _batchLogHint,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: _summaryMetaSpacing),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text(_batchLogEmptyRows))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text(_batchLogSkipLabel)),
                                  DataColumn(
                                    label: Text(_batchLogTableTaskLabel),
                                  ),
                                  DataColumn(
                                    label: Text(_batchLogTableFarmerLabel),
                                  ),
                                  DataColumn(
                                    label: Text(_batchLogTableUnitLabel),
                                  ),
                                  DataColumn(
                                    label: Text(_batchLogTableExpectedLabel),
                                  ),
                                  DataColumn(
                                    label: Text(_batchLogTableActualLabel),
                                  ),
                                  DataColumn(
                                    label: Text(_batchLogTableDelayLabel),
                                  ),
                                  DataColumn(
                                    label: Text(_batchLogTableNotesLabel),
                                  ),
                                  DataColumn(label: Text(_batchLogStateLabel)),
                                ],
                                rows: rows.map((row) {
                                  final isEditable =
                                      !row.isRecordedLocked && !row.skip;
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        row.isRecordedLocked
                                            ? const Icon(Icons.lock_clock)
                                            : Checkbox(
                                                value: !row.skip,
                                                onChanged: (value) {
                                                  setDialogState(() {
                                                    row.skip = !(value == true);
                                                    if (row.skip) {
                                                      row.validationError = "";
                                                    }
                                                    formError = "";
                                                  });
                                                },
                                              ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 180,
                                          child: Text(
                                            "${row.taskTitle}\n${row.phaseName}",
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 140,
                                          child: Text(row.staffName),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 150,
                                          child: Text(row.unitLabel),
                                        ),
                                      ),
                                      DataCell(Text("${row.expectedPlots}")),
                                      DataCell(
                                        SizedBox(
                                          width: 110,
                                          child: row.isRecordedLocked
                                              ? Text(
                                                  row.actualPlotsText.isEmpty
                                                      ? _dash
                                                      : row.actualPlotsText,
                                                )
                                              : TextFormField(
                                                  key: ValueKey(
                                                    "${row.rowId}_actual",
                                                  ),
                                                  initialValue:
                                                      row.actualPlotsText,
                                                  enabled: isEditable,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                      ),
                                                  onChanged: (value) {
                                                    setDialogState(() {
                                                      row.actualPlotsText =
                                                          value.trim();
                                                      row.validationError = "";
                                                      formError = "";
                                                    });
                                                  },
                                                ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 170,
                                          child: row.isRecordedLocked
                                              ? Text(row.delayReason)
                                              : DropdownButtonFormField<String>(
                                                  key: ValueKey(
                                                    "${row.rowId}_delay",
                                                  ),
                                                  initialValue: row.delayReason,
                                                  isExpanded: true,
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                      ),
                                                  items: _delayReasonOptions
                                                      .map(
                                                        (reason) =>
                                                            DropdownMenuItem(
                                                              value: reason,
                                                              child: Text(
                                                                reason,
                                                              ),
                                                            ),
                                                      )
                                                      .toList(),
                                                  onChanged: isEditable
                                                      ? (value) {
                                                          setDialogState(() {
                                                            row.delayReason =
                                                                value ??
                                                                _delayReasonNone;
                                                            row.validationError =
                                                                "";
                                                            formError = "";
                                                          });
                                                        }
                                                      : null,
                                                ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 170,
                                          child: row.isRecordedLocked
                                              ? Text(
                                                  row.notes.trim().isEmpty
                                                      ? _dash
                                                      : row.notes,
                                                )
                                              : TextFormField(
                                                  key: ValueKey(
                                                    "${row.rowId}_notes",
                                                  ),
                                                  initialValue: row.notes,
                                                  enabled: isEditable,
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                      ),
                                                  onChanged: (value) {
                                                    setDialogState(() {
                                                      row.notes = value.trim();
                                                      formError = "";
                                                    });
                                                  },
                                                ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 160,
                                          child: Text(
                                            row.isRecordedLocked
                                                ? _batchLogRecordedLabel
                                                : row.skip
                                                ? _batchLogSkippedLabel
                                                : row.validationError
                                                      .trim()
                                                      .isEmpty
                                                ? _batchLogReadyLabel
                                                : row.validationError,
                                            style:
                                                row.validationError
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : Theme.of(dialogContext)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Theme.of(
                                                          dialogContext,
                                                        ).colorScheme.error,
                                                      ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                  ),
                  if (formError.trim().isNotEmpty) ...[
                    const SizedBox(height: _summaryMetaSpacing),
                    Text(
                      formError,
                      style: Theme.of(dialogContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text(_logProgressCancelLabel),
              ),
              TextButton(
                onPressed: () {
                  final entries = <ProductionTaskProgressBatchEntryInput>[];
                  bool hasValidationErrors = false;
                  for (final row in rows) {
                    row.validationError = "";

                    if (row.isRecordedLocked || row.skip) {
                      continue;
                    }

                    final actualRaw = row.actualPlotsText.trim();
                    if (actualRaw.isEmpty) {
                      row.validationError = _batchLogActualRequired;
                      hasValidationErrors = true;
                      continue;
                    }

                    final actualPlots = num.tryParse(actualRaw);
                    if (actualPlots == null || actualPlots < 0) {
                      row.validationError = _batchLogActualInvalid;
                      hasValidationErrors = true;
                      continue;
                    }
                    if (actualPlots == 0 &&
                        row.delayReason == _delayReasonNone) {
                      row.validationError = _batchLogZeroDelayRequired;
                      hasValidationErrors = true;
                      continue;
                    }

                    entries.add(
                      ProductionTaskProgressBatchEntryInput(
                        taskId: row.taskId,
                        staffId: row.staffId,
                        unitId: row.unitId,
                        actualPlots: actualPlots,
                        delayReason: row.delayReason,
                        notes: row.notes.trim(),
                      ),
                    );
                  }

                  if (entries.isEmpty) {
                    setDialogState(() {
                      formError = _batchLogValidationSelectRows;
                    });
                    return;
                  }
                  if (hasValidationErrors) {
                    setDialogState(() {
                      formError = _batchLogValidationFix;
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    _BatchLogProgressInput(
                      workDate: selectedDate,
                      entries: entries,
                    ),
                  );
                },
                child: const Text(_batchLogSubmitLabel),
              ),
            ],
          );
        },
      );
    },
  );

  return result;
}

List<_BatchLogRowDraft> _buildBatchLogRowsForDate({
  required DateTime workDate,
  required ProductionPlanDetail detail,
  required Map<String, BusinessStaffProfileSummary> staffMap,
  required Map<String, String> planUnitLabelById,
}) {
  final selectedDateKey = _toWorkDateKey(workDate);
  final existingByTaskStaffUnit = <String, ProductionTimelineRow>{};
  for (final row in detail.timelineRows) {
    if (_toWorkDateKey(row.workDate) != selectedDateKey) {
      continue;
    }
    final key = "${row.taskId}|${row.staffId}|${row.unitId}";
    existingByTaskStaffUnit[key] = row;
  }

  final phaseNameById = {
    for (final phase in detail.phases) phase.id: phase.name,
  };
  final rows = <_BatchLogRowDraft>[];
  for (final task in detail.tasks) {
    final taskScheduledForDate = _isTaskScheduledForDate(
      task: task,
      workDate: workDate,
    );
    final assignedStaffIds = _resolveAssignedStaffIds(task);
    final assignedUnitIds = task.assignedUnitIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    final unitIdsForRows = assignedUnitIds.isNotEmpty
        ? assignedUnitIds
        : const <String>[""];
    for (final staffId in assignedStaffIds) {
      for (final unitId in unitIdsForRows) {
        final key = "${task.id}|$staffId|$unitId";
        final existingProgress = existingByTaskStaffUnit[key];
        if (!taskScheduledForDate && existingProgress == null) {
          continue;
        }
        final isRecordedLocked = existingProgress != null;
        final unitLabel = unitId.isNotEmpty
            ? (planUnitLabelById[unitId] ?? unitId)
            : _dash;
        rows.add(
          _BatchLogRowDraft(
            rowId:
                "${task.id}_${staffId}_${unitId.isEmpty ? "no_unit" : unitId}",
            taskId: task.id,
            taskTitle: task.title,
            phaseName: phaseNameById[task.phaseId] ?? _dash,
            staffId: staffId,
            staffName: _resolveStaffDisplayName(staffId, staffMap),
            unitId: unitId,
            unitLabel: unitLabel,
            expectedPlots: task.weight,
            isRecordedLocked: isRecordedLocked,
            skip: isRecordedLocked,
            actualPlotsText: isRecordedLocked
                ? "${existingProgress.actualPlots}"
                : "",
            delayReason: isRecordedLocked
                ? existingProgress.delayReason
                : _delayReasonNone,
            notes: isRecordedLocked ? existingProgress.notes : "",
            validationError: "",
          ),
        );
      }
    }
  }

  rows.sort((left, right) {
    final taskCompare = left.taskTitle.toLowerCase().compareTo(
      right.taskTitle.toLowerCase(),
    );
    if (taskCompare != 0) {
      return taskCompare;
    }
    final staffCompare = left.staffName.toLowerCase().compareTo(
      right.staffName.toLowerCase(),
    );
    if (staffCompare != 0) {
      return staffCompare;
    }
    return left.unitLabel.toLowerCase().compareTo(
      right.unitLabel.toLowerCase(),
    );
  });

  return rows;
}

Future<_LogProgressInput?> _showLogProgressDialog(
  BuildContext context, {
  required List<String> assignedStaffIds,
  required List<String> assignedUnitIds,
  required Map<String, BusinessStaffProfileSummary> staffMap,
  required Map<String, String> planUnitLabelById,
  required List<ProductionAttendanceRecord> attendanceRecords,
  required num taskTargetPlots,
}) async {
  // WHY: Managers need a small, focused form for daily execution logging.
  DateTime selectedDate = DateTime.now();
  String selectedDelayReason = _delayReasonNone;
  String validationMessage = "";
  final normalizedAssignedStaffIds = assignedStaffIds
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
  final hasMultipleAssignedStaff = normalizedAssignedStaffIds.length > 1;
  String? selectedStaffId = hasMultipleAssignedStaff
      ? normalizedAssignedStaffIds.first
      : null;
  final normalizedAssignedUnitIds = assignedUnitIds
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
  final hasMultipleAssignedUnits = normalizedAssignedUnitIds.length > 1;
  String? selectedUnitId = hasMultipleAssignedUnits
      ? normalizedAssignedUnitIds.first
      : normalizedAssignedUnitIds.length == 1
      ? normalizedAssignedUnitIds.first
      : null;
  final actualPlotsCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final attendanceRecordsSnapshot = attendanceRecords;
  List<ProductionTaskProgressProofInput> selectedProofs = [];

  final result = await showDialog<_LogProgressInput>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final parsedActualPlots = num.tryParse(actualPlotsCtrl.text.trim());
          final requiredProofCount = parsedActualPlots == null
              ? 0
              : requiredTaskProgressProofCount(parsedActualPlots);
          final proofCountMatches = requiredProofCount == 0
              ? selectedProofs.isEmpty
              : selectedProofs.length == requiredProofCount;
          final remainingAfterSave = parsedActualPlots == null
              ? 0
              : (taskTargetPlots - parsedActualPlots) < 0
              ? 0
              : (taskTargetPlots - parsedActualPlots);
          final remainingAfterSaveLabel = remainingAfterSave % 1 == 0
              ? remainingAfterSave.toStringAsFixed(0)
              : remainingAfterSave.toStringAsFixed(1);
          final shouldShowFollowUpSuggestion =
              parsedActualPlots != null &&
              parsedActualPlots > 0 &&
              remainingAfterSave > 0;

          Future<void> chooseProofs() async {
            final picked = await pickTaskProgressProofImages();
            if (!dialogContext.mounted || picked.isEmpty) {
              return;
            }
            setDialogState(() {
              selectedProofs = picked;
              validationMessage = "";
            });
          }

          final selectedAttendanceStaffId = hasMultipleAssignedStaff
              ? selectedStaffId
              : (normalizedAssignedStaffIds.isNotEmpty
                    ? normalizedAssignedStaffIds.first
                    : null);
          final selectedAttendance = selectedAttendanceStaffId == null
              ? null
              : _findCompletedAttendanceForStaffOnDate(
                  attendanceRecords: attendanceRecordsSnapshot,
                  staffProfileId: selectedAttendanceStaffId,
                  workDate: selectedDate,
                );
          final selectedAttendanceComplete =
              selectedAttendance?.clockInAt != null &&
              selectedAttendance?.clockOutAt != null;
          return AlertDialog(
            title: const Text(_logProgressDialogTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$_logProgressDateLabel: ${formatDateLabel(selectedDate)}",
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedDate = picked;
                      });
                    },
                    child: const Text(_logProgressDateLabel),
                  ),
                  TextField(
                    controller: actualPlotsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: _logProgressActualPlotsLabel,
                    ),
                    onChanged: (_) {
                      setDialogState(() {
                        validationMessage = "";
                        if (requiredTaskProgressProofCount(
                              num.tryParse(actualPlotsCtrl.text.trim()) ?? 0,
                            ) ==
                            0) {
                          selectedProofs = [];
                        }
                      });
                    },
                  ),
                  const SizedBox(height: _summaryMetaSpacing),
                  Text(
                    _logProgressZeroHelperText,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  if (hasMultipleAssignedStaff) ...[
                    const SizedBox(height: _summaryMetaSpacing),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStaffId,
                      decoration: const InputDecoration(
                        labelText: _logProgressFarmerLabel,
                      ),
                      items: normalizedAssignedStaffIds
                          .map(
                            (staffId) => DropdownMenuItem(
                              value: staffId,
                              child: Text(
                                _resolveStaffDisplayName(staffId, staffMap),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedStaffId = value;
                        });
                      },
                    ),
                  ],
                  if (hasMultipleAssignedUnits) ...[
                    const SizedBox(height: _summaryMetaSpacing),
                    DropdownButtonFormField<String>(
                      initialValue: selectedUnitId,
                      decoration: const InputDecoration(
                        labelText: _logProgressUnitLabel,
                      ),
                      items: normalizedAssignedUnitIds
                          .map(
                            (unitId) => DropdownMenuItem(
                              value: unitId,
                              child: Text(planUnitLabelById[unitId] ?? unitId),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedUnitId = value;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: _summaryMetaSpacing),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedAttendanceComplete
                          ? Theme.of(dialogContext).colorScheme.primaryContainer
                          : Theme.of(
                              dialogContext,
                            ).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedAttendanceComplete
                            ? Theme.of(
                                dialogContext,
                              ).colorScheme.primary.withValues(alpha: 0.18)
                            : Theme.of(
                                dialogContext,
                              ).colorScheme.tertiary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selectedAttendanceComplete
                              ? Icons.verified_outlined
                              : Icons.lock_outline,
                          size: 18,
                          color: selectedAttendanceComplete
                              ? Theme.of(dialogContext).colorScheme.primary
                              : Theme.of(dialogContext).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedAttendanceComplete
                                ? "Attendance complete for this staff on ${formatDateLabel(selectedDate)}."
                                : _logProgressAttendanceRequiredText,
                            style: Theme.of(dialogContext).textTheme.bodySmall
                                ?.copyWith(
                                  color: selectedAttendanceComplete
                                      ? Theme.of(
                                          dialogContext,
                                        ).colorScheme.primary
                                      : Theme.of(
                                          dialogContext,
                                        ).colorScheme.tertiary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _summaryMetaSpacing),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Proof images",
                          style: Theme.of(dialogContext).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          requiredProofCount == 0
                              ? "Enter a positive actual amount to unlock proof uploads."
                              : proofCountMatches
                              ? "Upload exactly $requiredProofCount proof image(s) before saving."
                              : "Selected ${selectedProofs.length} of $requiredProofCount required proof image(s).",
                          style: Theme.of(dialogContext).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  dialogContext,
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
                          label: Text(
                            selectedProofs.isEmpty
                                ? "Add proof images"
                                : "Replace proof images",
                          ),
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
                                        dialogContext,
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
                    const SizedBox(height: _summaryMetaSpacing),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.tertiaryContainer.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.tertiary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Suggested follow-up",
                            style: Theme.of(dialogContext).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Give the staff a 2 hour break, then create a follow-up task for $remainingAfterSaveLabel work unit(s) remaining.",
                            style: Theme.of(dialogContext).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    dialogContext,
                                  ).colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: _summaryMetaSpacing),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDelayReason,
                    decoration: const InputDecoration(
                      labelText: _logProgressDelayReasonLabel,
                    ),
                    items: _delayReasonOptions
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason,
                            child: Text(reason),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedDelayReason = value ?? _delayReasonNone;
                        validationMessage = "";
                      });
                    },
                  ),
                  if (validationMessage.isNotEmpty) ...[
                    const SizedBox(height: _summaryMetaSpacing),
                    Text(
                      validationMessage,
                      style: Theme.of(dialogContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                    ),
                  ],
                  const SizedBox(height: _summaryMetaSpacing),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: _logProgressNotesLabel,
                      hintText: _logProgressNotesHint,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text(_logProgressCancelLabel),
              ),
              TextButton(
                onPressed: selectedAttendanceComplete
                    ? () {
                        final actualPlots = num.tryParse(
                          actualPlotsCtrl.text.trim(),
                        );
                        if (actualPlots == null || actualPlots < 0) {
                          setDialogState(() {
                            validationMessage = _logProgressActualInvalidText;
                          });
                          return;
                        }
                        final requiredProofCount =
                            requiredTaskProgressProofCount(actualPlots);
                        if (requiredProofCount == 0 &&
                            selectedProofs.isNotEmpty) {
                          setDialogState(() {
                            validationMessage =
                                "Proof images are not allowed when actual amount is 0.";
                          });
                          return;
                        }
                        if (requiredProofCount > 0 &&
                            selectedProofs.length != requiredProofCount) {
                          setDialogState(() {
                            validationMessage =
                                "Upload exactly $requiredProofCount proof image(s).";
                          });
                          return;
                        }
                        if (hasMultipleAssignedStaff &&
                            selectedStaffId == null) {
                          setDialogState(() {
                            validationMessage = _logProgressStaffRequiredText;
                          });
                          return;
                        }
                        if (hasMultipleAssignedUnits &&
                            selectedUnitId == null) {
                          setDialogState(() {
                            validationMessage = _logProgressUnitRequiredText;
                          });
                          return;
                        }
                        if (actualPlots == 0 &&
                            selectedDelayReason == _delayReasonNone) {
                          setDialogState(() {
                            validationMessage =
                                _logProgressZeroDelayValidationText;
                          });
                          return;
                        }
                        Navigator.of(dialogContext).pop(
                          _LogProgressInput(
                            staffId: hasMultipleAssignedStaff
                                ? selectedStaffId
                                : null,
                            unitId: selectedUnitId,
                            workDate: selectedDate,
                            actualPlots: actualPlots,
                            proofs: List<ProductionTaskProgressProofInput>.from(
                              selectedProofs,
                            ),
                            delayReason: selectedDelayReason,
                            notes: notesCtrl.text.trim(),
                          ),
                        );
                      }
                    : null,
                child: const Text(_logProgressSaveLabel),
              ),
            ],
          );
        },
      );
    },
  );

  actualPlotsCtrl.dispose();
  notesCtrl.dispose();
  return result;
}

Future<void> _showRejectDialog(
  BuildContext context, {
  required ValueChanged<String> onReject,
}) async {
  // WHY: Capture a short rejection reason for audit clarity.
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text(_rejectionPrompt),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: _rejectionHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(_rejectionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(_rejectionSubmit),
          ),
        ],
      );
    },
  );

  if (result != null && result.trim().isNotEmpty) {
    onReject(result.trim());
  }
}

Future<void> _showProgressRejectDialog(
  BuildContext context, {
  required ValueChanged<String> onReject,
}) async {
  // WHY: Progress review requires a reason so supervisors can follow up.
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text(_progressRejectPrompt),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: _progressRejectHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(_rejectionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(_progressRejectSubmit),
          ),
        ],
      );
    },
  );

  controller.dispose();
  if (result != null && result.trim().isNotEmpty) {
    onReject(result.trim());
  }
}

Future<String?> _showDeviationVarianceDialog(
  BuildContext context, {
  required ProductionDeviationAlert alert,
}) async {
  // WHY: Managers should record a short note when accepting variance for governance audit clarity.
  final noteController = TextEditingController(text: alert.resolutionNote);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text(_deviationVarianceDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(_deviationVarianceDialogHint),
            const SizedBox(height: _summaryMetaSpacing),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: _deviationVarianceNoteLabel,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(_logProgressCancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(noteController.text.trim()),
            child: const Text(_deviationVarianceSaveLabel),
          ),
        ],
      );
    },
  );
  noteController.dispose();
  return result;
}

Future<_DeviationReplanInput?> _showDeviationReplanDialog(
  BuildContext context, {
  required ProductionDeviationAlert alert,
  required ProductionTask? sourceTask,
}) async {
  // WHY: Re-plan needs explicit manager input and must produce deterministic task adjustments for backend validation.
  if (sourceTask == null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(_deviationReplanDialogTitle),
          content: const Text(_deviationReplanSourceTaskMissing),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(_reconcileSummaryDoneLabel),
            ),
          ],
        );
      },
    );
    return null;
  }
  if (sourceTask.startDate == null || sourceTask.dueDate == null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(_deviationReplanDialogTitle),
          content: const Text(_deviationReplanSourceTaskDatesMissing),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(_reconcileSummaryDoneLabel),
            ),
          ],
        );
      },
    );
    return null;
  }

  final shiftController = TextEditingController(text: "1");
  final noteController = TextEditingController();
  String validationMessage = "";

  final result = await showDialog<_DeviationReplanInput>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text(_deviationReplanDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${alert.unitLabel} • ${sourceTask.title}"),
                const SizedBox(height: _summaryMetaSpacing),
                TextField(
                  controller: shiftController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: _deviationReplanShiftLabel,
                  ),
                ),
                const SizedBox(height: _summaryMetaSpacing),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: _deviationReplanNoteLabel,
                  ),
                ),
                if (validationMessage.trim().isNotEmpty) ...[
                  const SizedBox(height: _summaryMetaSpacing),
                  Text(
                    validationMessage,
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text(_logProgressCancelLabel),
              ),
              TextButton(
                onPressed: () {
                  final shiftDays = int.tryParse(shiftController.text.trim());
                  if (shiftDays == null) {
                    setDialogState(() {
                      validationMessage = _deviationReplanShiftInvalid;
                    });
                    return;
                  }

                  final nextStartDate = sourceTask.startDate!.add(
                    Duration(days: shiftDays),
                  );
                  final nextDueDate = sourceTask.dueDate!.add(
                    Duration(days: shiftDays),
                  );
                  Navigator.of(dialogContext).pop(
                    _DeviationReplanInput(
                      taskAdjustments: [
                        {
                          "taskId": sourceTask.id,
                          "startDate": nextStartDate.toIso8601String(),
                          "dueDate": nextDueDate.toIso8601String(),
                        },
                      ],
                      note: noteController.text.trim(),
                    ),
                  );
                },
                child: const Text(_deviationReplanSaveLabel),
              ),
            ],
          );
        },
      );
    },
  );

  shiftController.dispose();
  noteController.dispose();
  return result;
}

String _formatPercent(double value) {
  final percent = (value * _percentMultiplier).clamp(
    _percentMin,
    _percentMultiplier,
  );
  return percent.toStringAsFixed(_percentFixedDigits);
}

const List<String> _readableMonthNames = [
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

String _formatReadableDate(DateTime? value) {
  if (value == null) {
    return _dash;
  }
  final local = value.toLocal();
  final month = _readableMonthNames[local.month - 1];
  final day = local.day.toString().padLeft(2, '0');
  return "$day $month ${local.year}";
}

String _formatReadableDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) {
    return _dash;
  }
  if (start == null) {
    return _formatReadableDate(end);
  }
  if (end == null) {
    return _formatReadableDate(start);
  }
  return "${_formatReadableDate(start)} - ${_formatReadableDate(end)}";
}

String _formatPlanDuration(DateTime? start, DateTime? end) {
  if (start == null || end == null) {
    return _dash;
  }
  final startDate = DateTime(start.year, start.month, start.day);
  final endDate = DateTime(end.year, end.month, end.day);
  final duration = endDate.difference(startDate).inDays + 1;
  if (duration <= 0) {
    return _dash;
  }
  return "$duration $_daysSuffix";
}

String _approvalLabel(String status) {
  if (status == _approvalApproved) {
    return _approvalApprovedLabel;
  }
  if (status == _approvalRejected) {
    return _approvalRejectedLabel;
  }
  return _approvalPendingLabel;
}

String _formatProgressApprovalLabel(String approvalState) {
  if (approvalState == _progressApprovalApproved) {
    return "✔ Approved";
  }
  if (approvalState == _progressApprovalNeedsReview) {
    return "⚠ Needs review";
  }
  if (approvalState == _progressApprovalPending) {
    return "Pending approval";
  }
  return "Pending approval";
}

String _formatDeviationStatus(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized == "open") {
    return "Open";
  }
  if (normalized == "variance_accepted") {
    return "Variance accepted";
  }
  if (normalized == "replanned") {
    return "Replanned";
  }
  return "Open";
}

String? _resolveSelfStaffRole({
  required List<BusinessStaffProfileSummary> staffList,
  required String? userEmail,
}) {
  if (userEmail == null) {
    return null;
  }
  const empty = "";
  final normalizedEmail = userEmail.toLowerCase().trim();
  if (normalizedEmail.isEmpty) {
    return null;
  }

  for (final profile in staffList) {
    final profileEmail = (profile.userEmail ?? empty).toLowerCase().trim();
    if (profileEmail.isNotEmpty && profileEmail == normalizedEmail) {
      return profile.staffRole;
    }
  }

  return null;
}

bool _canReviewTaskProgress({
  required String? actorRole,
  required String? staffRole,
}) {
  if (actorRole == _ownerRole) {
    return true;
  }

  return actorRole == _staffRole &&
      (staffRole == _staffRoleEstateManager ||
          staffRole == _staffRoleFarmManager ||
          staffRole == _staffRoleAssetManager);
}

bool _canLogTaskProgress({
  required String? actorRole,
  required String? staffRole,
}) {
  if (actorRole == _ownerRole) {
    return true;
  }

  return actorRole == _staffRole &&
      (staffRole == _staffRoleEstateManager ||
          staffRole == _staffRoleFarmManager ||
          staffRole == _staffRoleAssetManager);
}

bool _canViewPlanUnits({
  required String? actorRole,
  required String? staffRole,
}) {
  // WHY: Unit visibility follows operational manager permissions used for production execution.
  return _canLogTaskProgress(actorRole: actorRole, staffRole: staffRole);
}

bool _canViewPlanConfidence({
  required String? actorRole,
  required String? staffRole,
}) {
  // CONFIDENCE-SCORE
  // WHY: Confidence visibility follows manager/owner governance permissions.
  return _canLogTaskProgress(actorRole: actorRole, staffRole: staffRole);
}

bool _canManageDeviationGovernance({
  required String? actorRole,
  required String? staffRole,
}) {
  // WHY: Governance actions are restricted to manager-capable production roles.
  return _canLogTaskProgress(actorRole: actorRole, staffRole: staffRole);
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

List<String> _resolveAssignedStaffIds(ProductionTask task) {
  final normalizedAssignedIds = task.assignedStaffIds
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
  if (normalizedAssignedIds.isNotEmpty) {
    return normalizedAssignedIds;
  }
  if (task.assignedStaffId.trim().isEmpty) {
    return <String>[];
  }
  return <String>[task.assignedStaffId.trim()];
}

String _resolveStaffDisplayName(
  String staffId,
  Map<String, BusinessStaffProfileSummary> staffMap,
) {
  return staffMap[staffId]?.userName ?? staffMap[staffId]?.userEmail ?? staffId;
}

String _buildAssignedStaffLabel(
  List<String> assignedStaffIds,
  Map<String, BusinessStaffProfileSummary> staffMap,
) {
  if (assignedStaffIds.isEmpty) {
    return _dash;
  }
  return assignedStaffIds
      .map((staffId) => _resolveStaffDisplayName(staffId, staffMap))
      .join(", ");
}

String _buildAssignedUnitLabel({
  required List<String> assignedUnitIds,
  required Map<String, String> planUnitLabelById,
}) {
  if (assignedUnitIds.isEmpty) {
    return _dash;
  }

  final labels = assignedUnitIds
      .map((unitId) {
        final normalizedId = unitId.trim();
        if (normalizedId.isEmpty) {
          return "";
        }
        return planUnitLabelById[normalizedId] ?? normalizedId;
      })
      .where((label) => label.isNotEmpty)
      .toList();

  if (labels.isEmpty) {
    return _dash;
  }
  return labels.join(", ");
}

Map<String, BusinessStaffProfileSummary> _buildStaffMap(
  List<BusinessStaffProfileSummary> staff,
) {
  final map = <String, BusinessStaffProfileSummary>{};
  for (final member in staff) {
    map[member.id] = member;
  }
  return map;
}

Map<String, List<ProductionTask>> _groupTasksByPhase(
  List<ProductionPhase> phases,
  List<ProductionTask> tasks,
) {
  final map = {for (final phase in phases) phase.id: <ProductionTask>[]};
  for (final task in tasks) {
    map.putIfAbsent(task.phaseId, () => []).add(task);
  }
  return map;
}

double _deriveCapRatio(ProductionPreorderSummary? summary) {
  if (summary == null) {
    return 0.5;
  }
  final yieldQuantity = summary.conservativeYieldQuantity;
  final cap = summary.preorderCapQuantity;
  if (yieldQuantity == null || yieldQuantity <= 0 || cap <= 0) {
    return 0.5;
  }

  final raw = cap / yieldQuantity;
  return raw.clamp(0.1, 0.9).toDouble();
}

Future<Map<String, dynamic>?> _showPreorderConfigDialog(
  BuildContext context, {
  required ProductionPreorderSummary? summary,
}) async {
  bool allowPreorder = summary?.preorderEnabled == true;
  final yieldController = TextEditingController(
    text: summary?.conservativeYieldQuantity?.toString() ?? "",
  );
  final unitController = TextEditingController(
    text: (summary?.conservativeYieldUnit ?? "").trim().isEmpty
        ? "units"
        : summary!.conservativeYieldUnit,
  );
  final ratioController = TextEditingController(
    text: _deriveCapRatio(summary).toStringAsFixed(2),
  );
  String validationError = "";

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (statefulContext, setDialogState) {
          return AlertDialog(
            title: const Text(_preorderConfigTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(_preorderEnableLabel),
                  value: allowPreorder,
                  onChanged: (value) {
                    setDialogState(() {
                      allowPreorder = value;
                      validationError = "";
                    });
                  },
                ),
                if (allowPreorder) ...[
                  TextField(
                    controller: yieldController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: _preorderYieldLabel,
                    ),
                  ),
                  const SizedBox(height: _summaryMetaSpacing),
                  TextField(
                    controller: unitController,
                    decoration: const InputDecoration(
                      labelText: _preorderYieldUnitLabel,
                    ),
                  ),
                  const SizedBox(height: _summaryMetaSpacing),
                  TextField(
                    controller: ratioController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: _preorderCapRatioLabel,
                    ),
                  ),
                ],
                if (validationError.isNotEmpty) ...[
                  const SizedBox(height: _summaryMetaSpacing),
                  Text(
                    validationError,
                    style: Theme.of(statefulContext).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(statefulContext).colorScheme.error,
                        ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text(_preorderConfigCancelLabel),
              ),
              TextButton(
                onPressed: () {
                  if (!allowPreorder) {
                    Navigator.of(dialogContext).pop({"allowPreorder": false});
                    return;
                  }

                  final yieldQuantity = num.tryParse(
                    yieldController.text.trim(),
                  );
                  final capRatio = num.tryParse(ratioController.text.trim());
                  final unit = unitController.text.trim().isEmpty
                      ? "units"
                      : unitController.text.trim();

                  final isValidYield =
                      yieldQuantity != null && yieldQuantity > 0;
                  final isValidRatio =
                      capRatio != null && capRatio >= 0.1 && capRatio <= 0.9;
                  if (!isValidYield || !isValidRatio) {
                    setDialogState(() {
                      validationError = _preorderConfigValidation;
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop({
                    "allowPreorder": true,
                    "conservativeYieldQuantity": yieldQuantity,
                    "conservativeYieldUnit": unit,
                    "preorderCapRatio": capRatio,
                  });
                },
                child: const Text(_preorderConfigSaveLabel),
              ),
            ],
          );
        },
      );
    },
  );

  yieldController.dispose();
  unitController.dispose();
  ratioController.dispose();
  return result;
}

Future<void> _showReconcileSummaryDialog(
  BuildContext context, {
  required ProductionPreorderReconcileSummary summary,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text(_reconcileSummaryTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$_reconcileSummaryScanned: ${summary.scannedCount}"),
            Text("$_reconcileSummaryExpired: ${summary.expiredCount}"),
            Text("$_reconcileSummarySkipped: ${summary.skippedCount}"),
            Text("$_reconcileSummaryErrors: ${summary.errorCount}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(_reconcileSummaryDoneLabel),
          ),
        ],
      );
    },
  );
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
