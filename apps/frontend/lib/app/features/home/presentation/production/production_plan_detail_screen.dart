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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/core/platform/text_file_download.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';
import 'package:frontend/app/features/home/presentation/production/production_draft_presence.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_progress_report_dialogs.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_viewer.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_picker.dart';
import 'package:frontend/app/features/home/presentation/role_access.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _logTag = "PRODUCTION_DETAIL";
const String _buildMessage = "build()";
const String _refreshAction = "refresh_action";
const String _refreshPull = "refresh_pull";
const String _statusChangeAction = "status_change";
const String _logProgressAction = "log_progress_action";
const String _batchLogProgressAction = "batch_log_progress_action";
const String _approveProgressAction = "approve_progress_action";
const String _rejectProgressAction = "reject_progress_action";
const String _approveAction = "approve_action";
const String _rejectAction = "reject_action";
const String _acceptVarianceAction = "accept_variance_action";
const String _replanUnitAction = "replan_unit_action";
const String _backTap = "back_tap";
const String _screenTitle = "Production plan";
const String _summaryTitle = "Plan summary";
const String _overviewViewTitle = "Overview";
const String _executionViewTitle = "Execution";
const String _peopleViewTitle = "People";
const String _riskViewTitle = "Risk";
const String _downloadProgressLabel = "Download progress";
const String _emailProgressLabel = "Email progress";
const String _copyProgressLinkLabel = "Copy view link";
const String _downloadProgressSuccess = "Progress report downloaded.";
const String _downloadProgressFailure = "Unable to download progress report.";
const String _emailProgressFailure = "Unable to email progress report.";
const String _copyProgressLinkSuccess = "View link copied.";
const String _copyProgressLinkFailure = "Unable to copy view link.";
const String _presenceRefreshSkipped = "presence_refresh_skipped";
const String _kpiTitle = "KPIs";
const String _attendanceImpactTitle = "HR impact KPIs";
const String _dailyRollupTitle = "Stacked task progress by day";
const String _weeklyRollupTitle = "Weekly execution rollup";
const String _monthlyRollupTitle = "Monthly execution rollup";
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
const String _executionChartSubtitle =
    "Follow the work week at a glance. Each column represents an operational day, and each visible task uses one equal-height block so the chart compares workload structure, not raw numeric values.";
const String _executionChartVisibleTasksLabel = "Visible tasks";
const String _executionChartBestDayLabel = "Best day";
const String _executionChartApprovedSegmentsLabel = "Approved segments";
const String _executionChartInProgressLabel = "In progress";
const String _executionChartCompletedApprovedLabel = "Completed / approved";
const String _executionChartTaskCountLabel = "Task count";
const String _executionChartSnapshotSummaryLabel = "Snapshot";
const String _executionChartAssignedPeopleLabel = "Assigned people";
const String _executionChartTaskDetailsTitle = "Task details";
const String _executionChartTaskDetailsMessage =
    "Tap any day column to inspect the visible tasks and jump directly to the task detail screen.";
const String _executionChartEmptyTitle = "No execution activity yet";
const String _executionChartEmptyMessage =
    "Scheduled task blocks and saved execution rows will appear here once work is planned.";
const String _executionChartCurrentProgressLabel = "Current progress";
const String _executionChartExpectedQuantityLabel = "Expected quantity";
const String _executionChartActualQuantityLabel = "Actual quantity";
const String _executionChartDateLabel = "Date";
const String _executionChartDetailsAction = "selectExecutionChartDay()";
const String _executionChartTaskNavigationAction =
    "openExecutionChartTaskDetail()";
const String _executionChartRevealAction = "revealExecutionChartSection()";
const double _executionChartColumnMinWidth = 80;
const double _executionChartUnitHeight = 72;
const double _executionChartSegmentHeight = 64;
const double _executionChartSegmentWidth = 36;
const double _executionChartSegmentGap = 2;
const double _executionChartBaselineThickness = 2;
const double _executionChartTopLabelHeight = 32;
const double _executionChartXAxisLabelHeight = 54;
const String _weeklyRollupEmptyTitle = "No weekly rollups yet";
const String _weeklyRollupEmptyMessage =
    "Weekly rollups are derived from the saved daily execution rows.";
const String _monthlyRollupEmptyTitle = "No monthly rollups yet";
const String _monthlyRollupEmptyMessage =
    "Monthly rollups are derived from the saved daily execution rows.";
const String _phaseUnitEmptyTitle = "No phase unit data yet";
const String _phaseUnitEmptyMessage =
    "Approved task completions will populate per-phase unit progress.";
const String _productionStateLabel = "Product state";
const String _planUnitsLabel = "Plan units";
const String _planUnitsLoadingLabel = "Loading...";
const String _planUnitsUnavailableLabel = "Unavailable";
const String _dash = "-";
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
    "Clock in before logging progress";
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
const double _summaryMetaSpacing = 4;
const double _phaseProgressSpacing = 6;
const double _compactBottomNavOffset = 12;
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
const Color _summaryLightSurface = Color(0xFFFFFFFF);
const Color _summaryLightSubtleSurface = Color(0xFFF8FAFC);
const Color _summaryLightBorder = Color(0xFFE5EAF1);

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

_DetailViewMode _parseDetailViewMode(String rawValue) {
  switch (rawValue.trim().toLowerCase()) {
    case "execution":
      return _DetailViewMode.execution;
    case "people":
      return _DetailViewMode.people;
    case "risk":
      return _DetailViewMode.risk;
    case "overview":
    default:
      return _DetailViewMode.overview;
  }
}

String? _detailViewModeQueryValue(_DetailViewMode mode) {
  switch (mode) {
    case _DetailViewMode.overview:
      return null;
    case _DetailViewMode.execution:
      return "execution";
    case _DetailViewMode.people:
      return "people";
    case _DetailViewMode.risk:
      return "risk";
  }
}

class ProductionPlanDetailScreen extends ConsumerWidget {
  final String planId;
  final String initialView;

  const ProductionPlanDetailScreen({
    super.key,
    required this.planId,
    this.initialView = "",
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage, extra: {_extraPlanIdKey: planId});
    final detailAsync = ref.watch(productionPlanDetailProvider(planId));
    final cachedDetail = ref.watch(
      productionPlanDetailSnapshotProvider.select(
        (snapshots) => snapshots[planId],
      ),
    );
    final displayDetailAsync =
        detailAsync.valueOrNull == null && cachedDetail != null
        ? AsyncValue<ProductionPlanDetail>.data(cachedDetail)
        : detailAsync;
    final isRefreshingDetail =
        detailAsync.isLoading &&
        (detailAsync.valueOrNull != null || cachedDetail != null);
    final staffAsync = ref.watch(productionStaffProvider);
    final session = ref.watch(authSessionProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final profileRole = profileAsync.valueOrNull?.role ?? "";
    final actorRole = profileRole.isNotEmpty ? profileRole : session?.user.role;
    final selfStaffRole = _resolveSelfStaffRole(
      staffList:
          staffAsync.valueOrNull ?? const <BusinessStaffProfileSummary>[],
      userEmail: profileAsync.valueOrNull?.email ?? session?.user.email,
    );
    final isOwner = canUseBusinessOwnerEquivalentAccess(
      role: actorRole,
      staffRole: selfStaffRole,
    );
    final preferredEmail =
        (profileAsync.valueOrNull?.email ?? session?.user.email ?? "").trim();

    Future<void> downloadProgressReport() async {
      try {
        final report = await ref
            .read(productionPlanActionsProvider)
            .fetchPlanProgressReport(
              planId: planId,
              routePath: productionPlanInsightsPath(planId),
            );
        await downloadPlainTextFile(
          fileName: report.fileName,
          contents: report.html,
          mimeType: "text/html",
        );
        if (context.mounted) {
          _showSnack(context, _downloadProgressSuccess);
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(
            context,
            _resolveProductionDetailErrorMessage(
              error,
              fallback: _downloadProgressFailure,
            ),
          );
        }
      }
    }

    Future<void> emailProgressReport() async {
      final toEmail = await showProductionProgressReportEmailDialog(
        context,
        initialEmail: preferredEmail,
      );
      if (toEmail == null || toEmail.trim().isEmpty) {
        return;
      }

      try {
        final response = await ref
            .read(productionPlanActionsProvider)
            .emailPlanProgressReport(
              planId: planId,
              toEmail: toEmail.trim(),
              routePath: productionPlanInsightsPath(planId),
            );
        if (context.mounted) {
          _showSnack(context, "${response.message} to ${response.toEmail}.");
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(
            context,
            _resolveProductionDetailErrorMessage(
              error,
              fallback: _emailProgressFailure,
            ),
          );
        }
      }
    }

    Future<void> copyProgressReportLink() async {
      final toEmail = await showProductionProgressReportLinkDialog(
        context,
        initialEmail: preferredEmail,
      );
      if (toEmail == null || toEmail.trim().isEmpty) {
        return;
      }

      try {
        final report = await ref
            .read(productionPlanActionsProvider)
            .fetchPlanProgressReport(
              planId: planId,
              routePath: productionPlanInsightsPath(planId),
              toEmail: toEmail.trim(),
            );
        await Clipboard.setData(ClipboardData(text: report.reportUrl));
        if (context.mounted) {
          _showSnack(
            context,
            "$_copyProgressLinkSuccess for ${toEmail.trim()}.",
          );
        }
      } catch (error) {
        if (context.mounted) {
          _showSnack(
            context,
            _resolveProductionDetailErrorMessage(
              error,
              fallback: _copyProgressLinkFailure,
            ),
          );
        }
      }
    }

    ref.listen<ProductionDraftPresenceState>(
      productionDraftPresenceProvider(planId),
      (previous, next) {
        if (previous?.updatedAt == next.updatedAt) {
          return;
        }
        final currentDetailState = ref.read(
          productionPlanDetailProvider(planId),
        );
        // WHY: Presence updates can arrive while the first browser-refresh
        // detail request is still loading. Refreshing at that moment restarts
        // the same provider and can leave the route stuck on first-load UI.
        if (currentDetailState.isLoading) {
          AppDebug.log(
            _logTag,
            _presenceRefreshSkipped,
            extra: {
              _extraPlanIdKey: planId,
              "reason": "detail_provider_loading",
            },
          );
          return;
        }
        unawaited(ref.refresh(productionPlanDetailProvider(planId).future));
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          style: AppButtonStyles.icon(
            theme: Theme.of(context),
            tone: AppStatusTone.neutral,
          ),
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
            style: AppButtonStyles.icon(
              theme: Theme.of(context),
              tone: AppStatusTone.info,
            ),
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
        child: displayDetailAsync.when(
          skipError: cachedDetail != null,
          skipLoadingOnReload: true,
          data: (detail) {
            final staffList = staffAsync.valueOrNull ?? [];
            final staffMap = _buildStaffMap(staffList);
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
            return ProductionRefreshOverlay(
              isRefreshing: isRefreshingDetail,
              child: _PlanDetailBody(
                detail: detail,
                initialViewMode: _parseDetailViewMode(initialView),
                staffMap: staffMap,
                isOwner: isOwner,
                canLogProgress: canLogProgress,
                canReviewProgress: canReviewProgress,
                showPlanUnits: canViewPlanUnits,
                showDeviationGovernance: canManageDeviationGovernance,
                planUnitLabelById: planUnitLabelById,
                planUnits:
                    unitsAsync?.valueOrNull?.units ??
                    const <ProductionPlanUnit>[],
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
                      message.trim().isEmpty
                          ? _deviationReplanSuccess
                          : message,
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
                onDownloadProgressReport: downloadProgressReport,
                onEmailProgressReport: emailProgressReport,
                onCopyProgressReportLink: copyProgressReportLink,
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
                        extra: {
                          _extraTaskIdKey: taskId,
                          _extraPlanIdKey: planId,
                        },
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
              ),
            );
          },
          loading: () => const ProductionLoadingState(),
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
  final _DetailViewMode initialViewMode;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final bool canLogProgress;
  final bool canReviewProgress;
  final bool showPlanUnits;
  final bool showDeviationGovernance;
  final Map<String, String> planUnitLabelById;
  final List<ProductionPlanUnit> planUnits;
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
  final Future<void> Function() onDownloadProgressReport;
  final Future<void> Function() onEmailProgressReport;
  final Future<void> Function() onCopyProgressReportLink;
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
    required this.initialViewMode,
    required this.staffMap,
    required this.isOwner,
    required this.canLogProgress,
    required this.canReviewProgress,
    required this.showPlanUnits,
    required this.showDeviationGovernance,
    required this.planUnitLabelById,
    required this.planUnits,
    required this.planUnitsCount,
    required this.planUnitsLoading,
    required this.planUnitsHasError,
    required this.onAcceptDeviationVariance,
    required this.onReplanDeviationUnit,
    required this.onDownloadProgressReport,
    required this.onEmailProgressReport,
    required this.onCopyProgressReportLink,
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
  final ScrollController _contentScrollController = ScrollController();
  final GlobalKey _executionChartSectionKey = GlobalKey();
  Timer? _dayRefreshTimer;

  @override
  void initState() {
    super.initState();
    _viewMode = widget.initialViewMode;
    _scheduleDayRefresh();
    if (_viewMode == _DetailViewMode.execution) {
      _revealExecutionChartSection();
    }
  }

  @override
  void didUpdateWidget(covariant _PlanDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialViewMode != widget.initialViewMode &&
        widget.initialViewMode != _viewMode) {
      _viewMode = widget.initialViewMode;
      if (_viewMode == _DetailViewMode.execution) {
        _revealExecutionChartSection();
      }
    }
  }

  @override
  void dispose() {
    _dayRefreshTimer?.cancel();
    _contentScrollController.dispose();
    super.dispose();
  }

  void _updateViewMode(_DetailViewMode mode) {
    final modeChanged = _viewMode != mode;
    if (modeChanged) {
      setState(() => _viewMode = mode);
      context.go(
        productionPlanInsightsPath(
          widget.detail.plan.id,
          view: _detailViewModeQueryValue(mode),
        ),
      );
    }
    if (mode == _DetailViewMode.execution) {
      _revealExecutionChartSection();
    }
  }

  void _revealExecutionChartSection({int remainingAttempts = 2}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final sectionContext = _executionChartSectionKey.currentContext;
      AppDebug.log(
        _logTag,
        _executionChartRevealAction,
        extra: {
          _extraPlanIdKey: widget.detail.plan.id,
          "hasSectionContext": sectionContext != null,
          "remainingAttempts": remainingAttempts,
        },
      );
      if (sectionContext == null) {
        if (_contentScrollController.hasClients) {
          final position = _contentScrollController.position;
          final fallbackOffset =
              (position.pixels + (position.viewportDimension * 0.9)).clamp(
                0.0,
                position.maxScrollExtent,
              );
          if ((fallbackOffset - position.pixels).abs() > 1) {
            // WHY: On compact lists Flutter may not build the off-screen chart
            // section yet. Move the list near the execution region first, then
            // retry with ensureVisible once the section mounts.
            _contentScrollController.jumpTo(fallbackOffset);
          }
        }
        if (remainingAttempts > 0) {
          _revealExecutionChartSection(
            remainingAttempts: remainingAttempts - 1,
          );
        }
        return;
      }
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  void _scheduleDayRefresh() {
    _dayRefreshTimer?.cancel();
    final now = DateTime.now();
    final nextLocalMidnight = DateTime(now.year, now.month, now.day + 1);
    _dayRefreshTimer = Timer(
      nextLocalMidnight.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) {
          return;
        }
        setState(() {});
        _scheduleDayRefresh();
      },
    );
  }

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
        final isCompact = constraints.maxWidth < 760;
        final contentChildren = <Widget>[
          _PlanSummaryCard(
            plan: widget.detail.plan,
            timelineRows: widget.detail.timelineRows,
            preorderSummary: widget.detail.preorderSummary,
            showPlanUnits: widget.showPlanUnits,
            planUnits: widget.planUnits,
            planUnitsCount: widget.planUnitsCount,
            planUnitsLoading: widget.planUnitsLoading,
            planUnitsHasError: widget.planUnitsHasError,
            onDownloadProgressReport: widget.onDownloadProgressReport,
            onEmailProgressReport: widget.onEmailProgressReport,
            onCopyProgressReportLink: widget.onCopyProgressReportLink,
          ),
          const SizedBox(height: _sectionSpacing),
          if (!isCompact) ...[
            _DetailViewModePicker(
              selectedMode: _viewMode,
              onChanged: _updateViewMode,
            ),
            const SizedBox(height: _sectionSpacing),
          ],
          ...switch (_viewMode) {
            _DetailViewMode.overview => _buildOverviewSections(context),
            _DetailViewMode.execution => _buildExecutionSections(
              context,
              tasksByPhase,
            ),
            _DetailViewMode.people => _buildPeopleSections(context),
            _DetailViewMode.risk => _buildRiskSections(context),
          },
        ];
        final contentList = ListView(
          controller: _contentScrollController,
          padding: EdgeInsets.fromLTRB(
            _pagePadding,
            _pagePadding,
            _pagePadding,
            isCompact ? 104 : _pagePadding,
          ),
          children: contentChildren,
        );
        final content = isCompact
            ? Stack(
                fit: StackFit.expand,
                children: [
                  contentList,
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(
                        _pagePadding,
                        0,
                        _pagePadding,
                        _compactBottomNavOffset,
                      ),
                      child: _DetailViewModePicker(
                        selectedMode: _viewMode,
                        compact: true,
                        onChanged: _updateViewMode,
                      ),
                    ),
                  ),
                ],
              )
            : contentList;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: content,
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
      _buildSectionPane(
        title: _phaseTitle,
        subtitle: "Which phases are moving and which ones are stalled.",
        child: _PhaseProgressList(
          planId: widget.detail.plan.id,
          kpis: widget.detail.kpis,
        ),
      ),
    ];

    return _withVerticalSpacing(overviewSections);
  }

  List<Widget> _buildExecutionSections(
    BuildContext context,
    Map<String, List<ProductionTask>> tasksByPhase,
  ) {
    // WHY: The chart should cover the full scheduled workload, while the feed
    // still exposes every saved execution row for approvals and review.
    final executionRows = widget.detail.timelineRows;
    final taskById = <String, ProductionTask>{
      for (final phaseTasks in tasksByPhase.values)
        for (final task in phaseTasks) task.id: task,
    };

    return _withVerticalSpacing([
      Container(
        key: _executionChartSectionKey,
        child: _ResponsiveSplit(
          left: _buildSectionPane(
            title: _dailyRollupTitle,
            subtitle: _executionChartSubtitle,
            child: _ExecutionDayStackChart(
              planId: widget.detail.plan.id,
              rows: executionRows,
              taskById: taskById,
              staffMap: widget.staffMap,
            ),
          ),
          right: _buildSectionPane(
            title: "Execution feed",
            subtitle:
                "Clean task-by-task activity for approvals and progress review.",
            action: widget.canLogProgress
                ? OutlinedButton.icon(
                    style: AppButtonStyles.outlined(
                      theme: Theme.of(context),
                      tone: AppStatusTone.warning,
                    ),
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
              rows: executionRows,
              canReviewProgress: widget.canReviewProgress,
              onApproveProgress: widget.onApproveProgress,
              onRejectProgress: widget.onRejectProgress,
            ),
          ),
          breakpoint: _detailWideSplitBreakpoint,
          leftFlex: 6,
          rightFlex: 5,
        ),
      ),
      _ResponsiveSplit(
        left: _buildSectionPane(
          title: _weeklyRollupTitle,
          subtitle:
              "Weekly rollups are derived from the same saved daily execution rows.",
          child: _PeriodRollupTable(
            rollups: widget.detail.weeklyRollups,
            emptyTitle: _weeklyRollupEmptyTitle,
            emptyMessage: _weeklyRollupEmptyMessage,
          ),
        ),
        right: _buildSectionPane(
          title: _monthlyRollupTitle,
          subtitle:
              "Monthly rollups summarize the same daily execution truth into a longer horizon.",
          child: _PeriodRollupTable(
            rollups: widget.detail.monthlyRollups,
            emptyTitle: _monthlyRollupEmptyTitle,
            emptyMessage: _monthlyRollupEmptyMessage,
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
              "This view opens once unit drift or governance data is available.",
          child: const _InlineEmptyState(
            title: "No operational risk data yet",
            message:
                "Unit drift and governance alerts will appear after the first real production updates.",
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
  final bool compact;

  const _DetailViewModePicker({
    required this.selectedMode,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <(_DetailViewMode, IconData, String, AppStatusTone)>[
      (
        _DetailViewMode.overview,
        Icons.dashboard_customize_outlined,
        _overviewViewTitle,
        AppStatusTone.info,
      ),
      (
        _DetailViewMode.execution,
        Icons.playlist_play_outlined,
        _executionViewTitle,
        AppStatusTone.warning,
      ),
      (
        _DetailViewMode.people,
        Icons.groups_2_outlined,
        _peopleViewTitle,
        AppStatusTone.success,
      ),
      (
        _DetailViewMode.risk,
        Icons.shield_outlined,
        _riskViewTitle,
        AppStatusTone.danger,
      ),
    ];

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _summarySurfaceColor(theme),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _summaryBorderColor(theme)),
          boxShadow: _summarySoftShadow(theme),
        ),
        child: Row(
          children: options
              .map(
                (option) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: option == options.last ? 0 : 6,
                    ),
                    child: _DetailViewModeButton(
                      icon: option.$2,
                      label: option.$3,
                      tone: option.$4,
                      compact: true,
                      isSelected: selectedMode == option.$1,
                      onTap: () => onChanged(option.$1),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    return Wrap(
      spacing: _cardSpacing,
      runSpacing: _cardSpacing,
      children: options
          .map(
            (option) => _DetailViewModeButton(
              icon: option.$2,
              label: option.$3,
              tone: option.$4,
              isSelected: selectedMode == option.$1,
              onTap: () => onChanged(option.$1),
            ),
          )
          .toList(),
    );
  }
}

class _DetailViewModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusTone tone;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _DetailViewModeButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.isSelected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final badgeColors = _toneBadgeColors(context, tone);
    final accent = _toneAccentColor(context, tone);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? badgeColors.background
                : _summarySurfaceColor(theme),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.22)
                  : _summaryBorderColor(theme),
            ),
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: badgeColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 16,
                        color: badgeColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: badgeColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 16,
                        color: badgeColors.foreground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isSelected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
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
    final recordWorkDate = record.workDate;
    if (recordWorkDate != null) {
      final recordDayStart = DateTime(
        recordWorkDate.year,
        recordWorkDate.month,
        recordWorkDate.day,
      );
      if (recordDayStart == dayStart && record.clockInAt != null) {
        return record;
      }
    }
    final clockInAt = record.clockInAt;
    final clockOutAt = record.clockOutAt;
    if (clockInAt == null) {
      continue;
    }
    if (clockOutAt == null) {
      if (clockInAt.isBefore(dayEnd) && !clockInAt.isBefore(dayStart)) {
        return record;
      }
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

AppStatusBadgeColors _toneBadgeColors(
  BuildContext context,
  AppStatusTone tone,
) {
  return AppStatusBadgeColors.fromTheme(theme: Theme.of(context), tone: tone);
}

Color _toneAccentColor(BuildContext context, AppStatusTone tone) {
  final theme = Theme.of(context);
  if (tone == AppStatusTone.neutral) {
    return theme.colorScheme.primary;
  }
  return AppButtonStyles.accentColor(theme: theme, tone: tone);
}

Color _summarySurfaceColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surface
      : _summaryLightSurface;
}

Color _summarySubtleSurfaceColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerLow
      : _summaryLightSubtleSurface;
}

Color _summaryBorderColor(ThemeData theme) {
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.outlineVariant
      : _summaryLightBorder;
}

List<BoxShadow> _summarySoftShadow(ThemeData theme) {
  if (theme.brightness == Brightness.dark) {
    return const [];
  }
  return [
    BoxShadow(
      color: theme.colorScheme.shadow.withValues(alpha: 0.035),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

double _resolveSummaryMetricWidth(double maxWidth) {
  if (maxWidth >= 900) {
    return (maxWidth - (_cardSpacing * 2)) / 3;
  }
  if (maxWidth >= 360) {
    return (maxWidth - _cardSpacing) / 2;
  }
  return maxWidth;
}

AppStatusTone _summaryStatusTone(String rawLabel) {
  switch (rawLabel.trim().toLowerCase()) {
    case "active":
    case "approved":
    case "completed":
    case "done":
    case "in_progress":
    case "on_track":
    case "enabled":
      return AppStatusTone.success;
    case "pending":
    case "paused":
    case "needs_review":
      return AppStatusTone.warning;
    case "blocked":
    case "rejected":
    case "delayed":
    case "disabled":
    case "archived":
      return AppStatusTone.danger;
    case _dash:
    case "":
      return AppStatusTone.neutral;
    default:
      return AppStatusTone.info;
  }
}

const String _quantityActivityTransplant = "transplanted";
const String _quantityActivityHarvest = "harvested";

class _PlanFarmQuantitySummary {
  final String plantingUnit;
  final String harvestUnit;
  final num transplantLogged;
  final num harvestLogged;
  final num transplantRemaining;
  final num harvestRemaining;

  const _PlanFarmQuantitySummary({
    required this.plantingUnit,
    required this.harvestUnit,
    required this.transplantLogged,
    required this.harvestLogged,
    required this.transplantRemaining,
    required this.harvestRemaining,
  });
}

num _sumPlanQuantityForActivity({
  required List<ProductionTimelineRow> timelineRows,
  required String activityType,
}) {
  return timelineRows
      .where(
        (row) =>
            row.quantityActivityType.trim().toLowerCase() == activityType &&
            row.approvalState != _progressApprovalNeedsReview,
      )
      .fold<num>(0, (sum, row) => sum + row.quantityAmount);
}

_PlanFarmQuantitySummary? _summarizePlanFarmQuantities({
  required ProductionPlan plan,
  required List<ProductionTimelineRow> timelineRows,
}) {
  final plantingTargets = plan.plantingTargets;
  if (plantingTargets?.isConfigured != true) {
    return null;
  }

  final configuredTargets = plantingTargets!;
  final transplantLogged = _sumPlanQuantityForActivity(
    timelineRows: timelineRows,
    activityType: _quantityActivityTransplant,
  );
  final harvestLogged = _sumPlanQuantityForActivity(
    timelineRows: timelineRows,
    activityType: _quantityActivityHarvest,
  );
  final transplantRemaining =
      configuredTargets.plannedPlantingQuantity > transplantLogged
      ? configuredTargets.plannedPlantingQuantity - transplantLogged
      : 0;
  final harvestRemaining =
      configuredTargets.estimatedHarvestQuantity > harvestLogged
      ? configuredTargets.estimatedHarvestQuantity - harvestLogged
      : 0;

  return _PlanFarmQuantitySummary(
    plantingUnit: configuredTargets.plannedPlantingUnit,
    harvestUnit: configuredTargets.estimatedHarvestUnit,
    transplantLogged: transplantLogged,
    harvestLogged: harvestLogged,
    transplantRemaining: transplantRemaining,
    harvestRemaining: harvestRemaining,
  );
}

DateTime? _resolvePlanLatestUpdate({
  required ProductionPlan plan,
  required List<ProductionTimelineRow> timelineRows,
}) {
  var latest = _latestDateTime(plan.updatedAt, plan.lastDraftSavedAt);
  for (final row in timelineRows) {
    latest = _latestDateTime(
      latest,
      row.approvedAt,
      row.clockOutTime,
      row.clockInTime,
      row.workDate,
    );
  }
  return latest;
}

DateTime? _latestDateTime(
  DateTime? current, [
  DateTime? next,
  DateTime? third,
  DateTime? fourth,
  DateTime? fifth,
]) {
  final values = <DateTime?>[current, next, third, fourth, fifth];
  DateTime? latest;
  for (final value in values) {
    if (value == null) {
      continue;
    }
    if (latest == null || value.isAfter(latest)) {
      latest = value;
    }
  }
  return latest;
}

String _formatPlanProgressAmount(num value) {
  final normalized = value.toDouble();
  if ((normalized - normalized.roundToDouble()).abs() < 0.001) {
    return normalized.round().toString();
  }
  if (((normalized * 10) - (normalized * 10).roundToDouble()).abs() < 0.001) {
    return normalized.toStringAsFixed(1);
  }
  return normalized.toStringAsFixed(2);
}

AppStatusTone _progressTone(double value) {
  if (value >= 1) {
    return AppStatusTone.success;
  }
  if (value > 0) {
    return AppStatusTone.warning;
  }
  return AppStatusTone.neutral;
}

AppStatusTone _ratioTone(double value) {
  if (value >= 0.75) {
    return AppStatusTone.success;
  }
  if (value >= 0.3) {
    return AppStatusTone.warning;
  }
  return AppStatusTone.danger;
}

AppStatusTone _inverseRatioTone(double value) {
  if (value <= 0.05) {
    return AppStatusTone.success;
  }
  if (value <= 0.2) {
    return AppStatusTone.warning;
  }
  return AppStatusTone.danger;
}

AppStatusTone _delayTone(double value) {
  if (value <= 0.25) {
    return AppStatusTone.success;
  }
  if (value <= 1) {
    return AppStatusTone.warning;
  }
  return AppStatusTone.danger;
}

AppStatusTone _severityTone(String severity) {
  switch (severity.trim().toLowerCase()) {
    case "critical":
    case "high":
      return AppStatusTone.danger;
    case "medium":
      return AppStatusTone.warning;
    case "low":
      return AppStatusTone.info;
    default:
      return AppStatusTone.neutral;
  }
}

class _InfoPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final AppStatusTone tone;

  const _InfoPill({
    required this.label,
    this.icon,
    this.tone = AppStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final badgeColors = _toneBadgeColors(context, tone);
    final usesTone = tone != AppStatusTone.neutral;
    final isDark = theme.brightness == Brightness.dark;
    final iconBackground = usesTone
        ? badgeColors.background.withValues(alpha: isDark ? 0.72 : 0.44)
        : colorScheme.surfaceContainerHighest;
    final iconForeground = usesTone
        ? badgeColors.foreground.withValues(alpha: isDark ? 0.96 : 0.88)
        : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _summarySurfaceColor(theme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: usesTone
              ? badgeColors.foreground.withValues(alpha: isDark ? 0.24 : 0.16)
              : _summaryBorderColor(theme),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(icon, size: 14, color: iconForeground),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: usesTone ? iconForeground : colorScheme.onSurfaceVariant,
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
  final AppStatusTone tone;

  const _MiniMetricCard({
    required this.label,
    required this.value,
    this.tone = AppStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final resolvedAccent = tone == AppStatusTone.neutral
        ? null
        : _toneAccentColor(context, tone);
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: resolvedAccent == null
            ? colorScheme.surfaceContainerHighest
            : resolvedAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              resolvedAccent?.withValues(alpha: 0.22) ??
              colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color:
                  resolvedAccent?.withValues(alpha: 0.88) ??
                  colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: resolvedAccent,
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
                tone: AppStatusTone.info,
              ),
              _MiniMetricCard(
                label: "Ready for sale",
                value: "$readyCount",
                tone: readyCount > 0
                    ? AppStatusTone.success
                    : AppStatusTone.neutral,
              ),
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
                      tone: AppStatusTone.info,
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
                      tone: AppStatusTone.info,
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

class _PlanSummaryCard extends StatelessWidget {
  final ProductionPlan plan;
  final List<ProductionTimelineRow> timelineRows;
  final ProductionPreorderSummary? preorderSummary;
  final bool showPlanUnits;
  final List<ProductionPlanUnit> planUnits;
  final int? planUnitsCount;
  final bool planUnitsLoading;
  final bool planUnitsHasError;
  final Future<void> Function() onDownloadProgressReport;
  final Future<void> Function() onEmailProgressReport;
  final Future<void> Function() onCopyProgressReportLink;

  const _PlanSummaryCard({
    required this.plan,
    required this.timelineRows,
    required this.preorderSummary,
    required this.showPlanUnits,
    required this.planUnits,
    required this.planUnitsCount,
    required this.planUnitsLoading,
    required this.planUnitsHasError,
    required this.onDownloadProgressReport,
    required this.onEmailProgressReport,
    required this.onCopyProgressReportLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
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

    final planUnitsSummary = _resolvePlanUnitDisplaySummary(
      plan: plan,
      planUnits: planUnits,
      planUnitsCount: planUnitsCount,
      planUnitsLoading: planUnitsLoading,
      planUnitsHasError: planUnitsHasError,
    );
    final scheduleRange = _formatReadableDateRange(
      plan.startDate,
      plan.endDate,
    );
    final durationLabel = _formatPlanDuration(plan.startDate, plan.endDate);
    // WHY: Keep plan details aligned with the execution workspace so the
    // baseline targets and current quantity progress stay visible together.
    final farmQuantitySummary = _summarizePlanFarmQuantities(
      plan: plan,
      timelineRows: timelineRows,
    );
    // WHY: Operators need the freshest saved timestamp even when the newest
    // change came from a task log rather than the plan record itself.
    final latestUpdateAt = _resolvePlanLatestUpdate(
      plan: plan,
      timelineRows: timelineRows,
    );
    final configuredPlantingTargets = plantingTargets?.isConfigured == true
        ? plantingTargets!
        : null;
    final plantingSummary = configuredPlantingTargets == null
        ? null
        : "${formatTargetNumber(configuredPlantingTargets.plannedPlantingQuantity)} ${configuredPlantingTargets.plannedPlantingUnit}";
    final plantingDetail = configuredPlantingTargets == null
        ? null
        : "${formatTargetNumber(configuredPlantingTargets.plannedPlantingQuantity)} ${configuredPlantingTargets.plannedPlantingUnit} (${formatMaterialLabel(configuredPlantingTargets.materialType)})";
    final plantingHelper = configuredPlantingTargets == null
        ? null
        : "Harvest est. ${formatTargetNumber(configuredPlantingTargets.estimatedHarvestQuantity)} ${configuredPlantingTargets.estimatedHarvestUnit}";
    final productionStateValue =
        preorderSummary?.productionState.isNotEmpty == true
        ? preorderSummary!.productionState
        : _dash;
    final headerChips = <_SummaryHeaderChipData>[
      _SummaryHeaderChipData(
        icon: Icons.agriculture_outlined,
        label: domainLabel,
        tone: AppStatusTone.success,
      ),
      _SummaryHeaderChipData(
        icon: Icons.calendar_today_outlined,
        label: scheduleRange,
        tone: AppStatusTone.info,
      ),
      _SummaryHeaderChipData(
        icon: Icons.schedule_outlined,
        label: durationLabel,
        tone: AppStatusTone.warning,
      ),
      if (plantingSummary != null)
        _SummaryHeaderChipData(
          icon: Icons.grass_outlined,
          label: plantingSummary,
          tone: AppStatusTone.success,
        ),
    ];

    final coreMetrics = <_SummaryMetricData>[
      _SummaryMetricData(
        icon: Icons.inventory_2_outlined,
        label: _productionStateLabel,
        value: productionStateValue,
        tone: _summaryStatusTone(productionStateValue),
      ),
      if (showPlanUnits)
        _SummaryMetricData(
          icon: Icons.grid_view_outlined,
          label: _planUnitsLabel,
          value: planUnitsSummary.value,
          helper: planUnitsSummary.helper,
          tone: planUnitsSummary.tone,
        ),
    ];

    final planDetailsMetrics = <_SummaryMetricData>[
      _SummaryMetricData(
        icon: Icons.agriculture_outlined,
        label: "Farm",
        value: domainLabel,
        tone: AppStatusTone.success,
      ),
      _SummaryMetricData(
        icon: Icons.calendar_today_outlined,
        label: "Date range",
        value: scheduleRange,
        tone: AppStatusTone.info,
      ),
      _SummaryMetricData(
        icon: Icons.schedule_outlined,
        label: "Duration",
        value: durationLabel,
        tone: AppStatusTone.warning,
      ),
      if (plantingDetail != null)
        _SummaryMetricData(
          icon: Icons.grass_outlined,
          label: "Planting",
          value: plantingDetail,
          helper: plantingHelper,
          tone: AppStatusTone.success,
        ),
      if (configuredPlantingTargets != null && farmQuantitySummary != null)
        _SummaryMetricData(
          icon: Icons.swap_horiz_outlined,
          label: "Transplant",
          value:
              "${_formatPlanProgressAmount(farmQuantitySummary.transplantLogged)} / ${_formatPlanProgressAmount(configuredPlantingTargets.plannedPlantingQuantity)}",
          helper:
              "${_formatPlanProgressAmount(farmQuantitySummary.transplantRemaining)} left ${farmQuantitySummary.plantingUnit}",
          tone: AppStatusTone.info,
        ),
      if (configuredPlantingTargets != null && farmQuantitySummary != null)
        _SummaryMetricData(
          icon: Icons.agriculture_outlined,
          label: "Remaining harvest",
          value:
              "${_formatPlanProgressAmount(farmQuantitySummary.harvestRemaining)} ${farmQuantitySummary.harvestUnit}",
          helper:
              "${_formatPlanProgressAmount(farmQuantitySummary.harvestLogged)} / ${_formatPlanProgressAmount(configuredPlantingTargets.estimatedHarvestQuantity)} harvested",
          tone: farmQuantitySummary.harvestRemaining > 0
              ? AppStatusTone.warning
              : AppStatusTone.success,
        ),
      _SummaryMetricData(
        icon: Icons.update_outlined,
        label: "Latest update",
        value: formatDateTimeLabel(latestUpdateAt, fallback: _dash),
        helper: latestUpdateAt == null
            ? "No saved plan or progress updates yet."
            : "Most recent saved plan or execution activity.",
        tone: latestUpdateAt == null
            ? AppStatusTone.neutral
            : AppStatusTone.info,
      ),
    ];

    final actionItems =
        <
          ({
            IconData icon,
            String label,
            AppStatusTone tone,
            Future<void> Function() onPressed,
          })
        >[
          (
            icon: Icons.download_outlined,
            label: _downloadProgressLabel,
            tone: AppStatusTone.info,
            onPressed: onDownloadProgressReport,
          ),
          (
            icon: Icons.mail_outline,
            label: _emailProgressLabel,
            tone: AppStatusTone.info,
            onPressed: onEmailProgressReport,
          ),
          (
            icon: Icons.link_outlined,
            label: _copyProgressLinkLabel,
            tone: AppStatusTone.info,
            onPressed: onCopyProgressReportLink,
          ),
        ];

    Widget buildPlanDetailsSection({required bool compact}) {
      return _SummaryMetricWrap(
        metrics: planDetailsMetrics,
        compact: compact,
        singleColumn: compact,
      );
    }

    Widget buildActionList({required bool compact}) {
      if (compact) {
        return Column(
          children: [
            for (int index = 0; index < actionItems.length; index++) ...[
              SizedBox(
                width: double.infinity,
                child: _SummaryActionButton(
                  icon: actionItems[index].icon,
                  label: actionItems[index].label,
                  tone: actionItems[index].tone,
                  onPressed: () async {
                    await actionItems[index].onPressed();
                  },
                ),
              ),
              if (index < actionItems.length - 1)
                const SizedBox(height: _summaryMetaSpacing),
            ],
          ],
        );
      }
      return Wrap(
        spacing: _summaryMetaSpacing,
        runSpacing: _summaryMetaSpacing,
        children: actionItems
            .map(
              (action) => _SummaryActionButton(
                icon: action.icon,
                label: action.label,
                tone: action.tone,
                onPressed: () async {
                  await action.onPressed();
                },
              ),
            )
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        final cardPadding = isCompact ? 12.0 : 16.0;

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _summaryTitle,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            if (isCompact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SummaryStatusBadge(label: plan.status),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      plan.title,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _SummaryStatusBadge(label: plan.status),
                ],
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: headerChips
                  .map(
                    (chip) => _SummaryHeaderChip(
                      icon: chip.icon,
                      label: chip.label,
                      tone: chip.tone,
                    ),
                  )
                  .toList(),
            ),
          ],
        );

        final coreMetricsSection = _SummaryMetricWrap(
          metrics: coreMetrics,
          compact: isCompact,
        );

        final detailsDesktopSection = _SummaryAccordionSection(
          title: "Plan details",
          subtitle: "Context, window, quantities, and latest update.",
          initiallyExpanded: true,
          child: buildPlanDetailsSection(compact: false),
        );
        final actionDesktopSection = _SummaryAccordionSection(
          title: "Plan actions",
          subtitle: "Download and share progress reports from one panel.",
          initiallyExpanded: true,
          child: buildActionList(compact: false),
        );

        final content = isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 12),
                  coreMetricsSection,
                  const SizedBox(height: 12),
                  _SummaryAccordionSection(
                    title: "Plan details",
                    subtitle: "Context, window, quantities, latest update",
                    initiallyExpanded: true,
                    child: buildPlanDetailsSection(compact: true),
                  ),
                  const SizedBox(height: 8),
                  _SummaryAccordionSection(
                    title: "Plan actions",
                    subtitle: "Download, email, and copy progress reports",
                    child: buildActionList(compact: true),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: LayoutBuilder(
                      builder: (context, leftConstraints) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            header,
                            const SizedBox(height: 14),
                            coreMetricsSection,
                            const SizedBox(height: 14),
                            SizedBox(
                              width: leftConstraints.maxWidth,
                              child: detailsDesktopSection,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(flex: 4, child: actionDesktopSection),
                ],
              );

        return Container(
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            color: _summarySurfaceColor(theme),
            borderRadius: BorderRadius.circular(_summaryCardRadius),
            border: Border.all(color: _summaryBorderColor(theme)),
            boxShadow: _summarySoftShadow(theme),
          ),
          child: content,
        );
      },
    );
  }
}

class _PlanUnitDisplaySummary {
  final String value;
  final String? helper;
  final AppStatusTone tone;

  const _PlanUnitDisplaySummary({
    required this.value,
    required this.helper,
    required this.tone,
  });
}

_PlanUnitDisplaySummary _resolvePlanUnitDisplaySummary({
  required ProductionPlan plan,
  required List<ProductionPlanUnit> planUnits,
  required int? planUnitsCount,
  required bool planUnitsLoading,
  required bool planUnitsHasError,
}) {
  final responseCount = planUnitsCount ?? 0;
  final listedCount = planUnits.length;
  final workloadCount = plan.workloadContext?.totalWorkUnits ?? 0;
  final resolvedCount = responseCount > 0
      ? responseCount
      : listedCount > 0
      ? listedCount
      : workloadCount > 0
      ? workloadCount
      : 0;

  if (planUnitsLoading && resolvedCount <= 0) {
    return const _PlanUnitDisplaySummary(
      value: _planUnitsLoadingLabel,
      helper: null,
      tone: AppStatusTone.warning,
    );
  }

  if (planUnitsHasError && resolvedCount <= 0) {
    return const _PlanUnitDisplaySummary(
      value: _planUnitsUnavailableLabel,
      helper: null,
      tone: AppStatusTone.danger,
    );
  }

  final baseLabel = _resolvePlanUnitDisplayBaseLabel(
    plan: plan,
    planUnits: planUnits,
  );
  final unitLabel = resolvedCount == 1
      ? _singularizePlanUnitPhrase(baseLabel)
      : _pluralizePlanUnitPhrase(baseLabel);
  final helper = planUnitsLoading
      ? "Syncing backend unit list."
      : planUnitsHasError
      ? "Using saved workload context."
      : null;

  return _PlanUnitDisplaySummary(
    value: "$resolvedCount $unitLabel",
    helper: helper,
    tone: resolvedCount > 0 ? AppStatusTone.info : AppStatusTone.neutral,
  );
}

String _resolvePlanUnitDisplayBaseLabel({
  required ProductionPlan plan,
  required List<ProductionPlanUnit> planUnits,
}) {
  final inferredUnitLabel = _resolvePlanUnitStemFromPlanUnits(planUnits);
  final contextUnitLabel = _extractPlanUnitStem(
    plan.workloadContext?.resolvedWorkUnitLabel ?? "",
  );

  if (!_isGenericPlanUnitStem(inferredUnitLabel)) {
    return inferredUnitLabel;
  }
  if (!_isGenericPlanUnitStem(contextUnitLabel)) {
    return contextUnitLabel;
  }
  if (inferredUnitLabel.isNotEmpty) {
    return inferredUnitLabel;
  }
  if (contextUnitLabel.isNotEmpty) {
    return contextUnitLabel;
  }
  return "work unit";
}

String _resolvePlanUnitStemFromPlanUnits(List<ProductionPlanUnit> planUnits) {
  final stems =
      planUnits
          .map((unit) => _extractPlanUnitStem(unit.label))
          .where((stem) => stem.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  if (stems.length == 1) {
    return stems.first;
  }
  return "";
}

bool _isGenericPlanUnitStem(String value) {
  final normalized = _extractPlanUnitStem(value);
  return normalized.isEmpty ||
      normalized == "unit" ||
      normalized == "work unit";
}

bool _looksLikePlanUnitIdentifierToken(String token) {
  final normalized = token.trim().replaceAll("#", "");
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r"^[A-Za-z]?\d+[A-Za-z]?$").hasMatch(normalized) ||
      RegExp(r"^[A-Za-z]$").hasMatch(normalized);
}

String _extractPlanUnitStem(String label) {
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
  while (tokens.length > 1 && _looksLikePlanUnitIdentifierToken(tokens.last)) {
    tokens.removeLast();
  }
  final stem = tokens.join(" ").trim().toLowerCase();
  return stem.isEmpty ? normalized.toLowerCase() : stem;
}

String _pluralizePlanUnitWord(String value) {
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

String _singularizePlanUnitWord(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  final lower = normalized.toLowerCase();
  if (lower.endsWith("ies") && normalized.length > 3) {
    return "${normalized.substring(0, normalized.length - 3)}y";
  }
  if ((lower.endsWith("ches") ||
          lower.endsWith("shes") ||
          lower.endsWith("xes") ||
          lower.endsWith("zes")) &&
      normalized.length > 2) {
    return normalized.substring(0, normalized.length - 2);
  }
  if (lower.endsWith("s") && !lower.endsWith("ss") && normalized.length > 1) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

String _pluralizePlanUnitPhrase(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return "work units";
  }
  final tokens = normalized
      .split(" ")
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty) {
    return "work units";
  }
  final lastToken = tokens.removeLast();
  tokens.add(_pluralizePlanUnitWord(lastToken));
  return tokens.join(" ");
}

String _singularizePlanUnitPhrase(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return "work unit";
  }
  final tokens = normalized
      .split(" ")
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty) {
    return "work unit";
  }
  final lastToken = tokens.removeLast();
  tokens.add(_singularizePlanUnitWord(lastToken));
  return tokens.join(" ");
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

    return _DetailPanel(
      child: Wrap(
        spacing: _cardSpacing,
        runSpacing: _cardSpacing,
        children: [
          ProductionKpiCard(
            label: _kpiTotalTasks,
            value: "${kpis!.totalTasks}",
            icon: Icons.format_list_numbered_rounded,
            tone: AppStatusTone.info,
          ),
          ProductionKpiCard(
            label: _kpiCompleted,
            value: "${kpis!.completedTasks}",
            icon: Icons.check_circle_outline_rounded,
            tone: AppStatusTone.success,
          ),
          ProductionKpiCard(
            label: _kpiOnTime,
            value: "${_formatPercent(kpis!.onTimeRate)}$_percentSuffix",
            icon: Icons.schedule_rounded,
            tone: _ratioTone(kpis!.onTimeRate),
          ),
          ProductionKpiCard(
            label: _kpiAvgDelay,
            value:
                "${kpis!.avgDelayDays.toStringAsFixed(_delayFixedDigits)} $_daysSuffix",
            icon: Icons.timelapse_rounded,
            tone: _delayTone(kpis!.avgDelayDays),
          ),
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
          ProductionKpiCard(
            label: _kpiAttendanceCoverage,
            value: coverage,
            icon: Icons.groups_rounded,
            tone: _ratioTone(attendanceImpact!.attendanceCoverageRate),
          ),
          ProductionKpiCard(
            label: _kpiAbsenteeImpact,
            value: absenteeImpact,
            icon: Icons.person_off_rounded,
            tone: _inverseRatioTone(attendanceImpact!.absenteeImpactRate),
          ),
          ProductionKpiCard(
            label: _kpiLinkedProgress,
            value: linkedProgress,
            icon: Icons.link_rounded,
            tone: _ratioTone(attendanceImpact!.attendanceLinkedProgressRate),
          ),
          ProductionKpiCard(
            label: _kpiPlotsPerHour,
            value: plotsPerHour,
            icon: Icons.speed_rounded,
            tone: AppStatusTone.info,
          ),
          ProductionKpiCard(
            label: _kpiTrackedDays,
            value:
                "${attendanceImpact!.scheduledDays}/${attendanceImpact!.totalRollupDays}",
            icon: Icons.event_note_rounded,
            tone: AppStatusTone.info,
          ),
        ],
      ),
    );
  }
}

class _ExecutionChartTaskEntry {
  final ProductionTimelineRow row;
  final ProductionTask? task;
  final String workerLabel;
  final bool isCompleted;
  final String statusLabel;

  const _ExecutionChartTaskEntry({
    required this.row,
    required this.task,
    required this.workerLabel,
    required this.isCompleted,
    required this.statusLabel,
  });

  String get approvalLabel => _formatProgressApprovalLabel(row.approvalState);

  String get delayLabel {
    final delay = row.delay.trim();
    if (delay.isNotEmpty) {
      return delay;
    }
    final delayReason = row.delayReason.trim();
    if (delayReason.isNotEmpty && delayReason != _delayReasonNone) {
      return delayReason;
    }
    return _dash;
  }

  String get progressLabel {
    if (row.expectedPlots <= 0) {
      return row.actualPlots > 0 ? "Saved" : _dash;
    }
    final ratio = (row.actualPlots / row.expectedPlots).clamp(0, 1).toDouble();
    return "${_formatPercent(ratio)}$_percentSuffix";
  }
}

class _ExecutionChartDayGroup {
  final String dayKey;
  final DateTime? workDate;
  final List<_ExecutionChartTaskEntry> tasks;

  const _ExecutionChartDayGroup({
    required this.dayKey,
    required this.workDate,
    required this.tasks,
  });

  int get totalTasks => tasks.length;

  int get completedCount => tasks.where((task) => task.isCompleted).length;

  int get inProgressCount => totalTasks - completedCount;

  String get assignedPeopleSummary =>
      _buildExecutionChartAssignedPeopleSummary(tasks);

  String get completionSnapshot {
    if (totalTasks == 0) {
      return _dash;
    }
    final ratio = completedCount / totalTasks;
    return "$completedCount/$totalTasks (${_formatPercent(ratio)}$_percentSuffix)";
  }
}

List<_ExecutionChartDayGroup> _buildExecutionChartDayGroups({
  required List<ProductionTimelineRow> rows,
  required Map<String, ProductionTask> taskById,
  required Map<String, BusinessStaffProfileSummary> staffMap,
}) {
  final sortedRows = [...rows]
    ..sort((left, right) {
      final leftDate = left.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate =
          right.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateCompare = leftDate.compareTo(rightDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return left.taskTitle.compareTo(right.taskTitle);
    });
  final rowsByTaskDay = <String, List<ProductionTimelineRow>>{};
  final taskIdsByDay = <String, Set<String>>{};
  final workDateByKey = <String, DateTime?>{};

  void registerTaskDay({
    required String dayKey,
    required DateTime? workDate,
    required String taskId,
  }) {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isNotEmpty) {
      taskIdsByDay.putIfAbsent(dayKey, () => <String>{}).add(normalizedTaskId);
    } else {
      taskIdsByDay.putIfAbsent(dayKey, () => <String>{});
    }
    final normalizedWorkDate = workDate == null ? null : _toDayStart(workDate);
    if (!workDateByKey.containsKey(dayKey) || workDateByKey[dayKey] == null) {
      workDateByKey[dayKey] = normalizedWorkDate;
    }
  }

  for (final task in taskById.values) {
    for (final scheduledDate in _resolveExecutionChartTaskDates(task)) {
      final dayKey = _toExecutionChartDayKey(scheduledDate);
      registerTaskDay(dayKey: dayKey, workDate: scheduledDate, taskId: task.id);
    }
  }

  for (final row in sortedRows) {
    final normalizedWorkDate = row.workDate == null
        ? null
        : _toDayStart(row.workDate!);
    final dayKey = _toExecutionChartDayKey(normalizedWorkDate);
    registerTaskDay(
      dayKey: dayKey,
      workDate: normalizedWorkDate,
      taskId: row.taskId,
    );
    rowsByTaskDay
        .putIfAbsent("${row.taskId}|$dayKey", () => <ProductionTimelineRow>[])
        .add(row);
  }

  final sortedGroupKeys = taskIdsByDay.keys.toList()
    ..sort((left, right) {
      final leftDate = workDateByKey[left];
      final rightDate = workDateByKey[right];
      if (leftDate == null && rightDate == null) {
        return left.compareTo(right);
      }
      if (leftDate == null) {
        return 1;
      }
      if (rightDate == null) {
        return -1;
      }
      final dateCompare = leftDate.compareTo(rightDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return left.compareTo(right);
    });

  return sortedGroupKeys.map((groupKey) {
    final entries = taskIdsByDay[groupKey]!.map((taskId) {
      final task = taskById[taskId];
      final groupedTaskRows = [...?rowsByTaskDay["$taskId|$groupKey"]]
        ..sort((left, right) {
          final leftEntryIndex = left.entryIndex;
          final rightEntryIndex = right.entryIndex;
          final entryCompare = leftEntryIndex.compareTo(rightEntryIndex);
          if (entryCompare != 0) {
            return entryCompare;
          }
          return left.taskTitle.compareTo(right.taskTitle);
        });
      final aggregateRow = _buildExecutionChartAggregateRow(
        task: task,
        rows: groupedTaskRows,
        workDate: workDateByKey[groupKey],
      );
      return _ExecutionChartTaskEntry(
        row: aggregateRow,
        task: task,
        workerLabel: _resolveExecutionChartWorkerLabel(
          rows: groupedTaskRows,
          task: task,
          staffMap: staffMap,
        ),
        isCompleted: _isExecutionChartTaskCompleted(
          task: task,
          rows: groupedTaskRows,
        ),
        statusLabel: _resolveExecutionChartTaskStatusLabel(
          task: task,
          rows: groupedTaskRows,
          aggregateRow: aggregateRow,
        ),
      );
    }).toList()..sort(_compareExecutionChartTaskEntriesByTime);
    return _ExecutionChartDayGroup(
      dayKey: groupKey,
      workDate:
          workDateByKey[groupKey] ??
          (entries.isEmpty ? null : entries.first.row.workDate),
      tasks: entries,
    );
  }).toList();
}

String _toExecutionChartDayKey(DateTime? workDate) {
  final key = _toWorkDateKey(workDate);
  return key.isEmpty ? "undated" : key;
}

int _compareExecutionChartTaskEntriesByTime(
  _ExecutionChartTaskEntry left,
  _ExecutionChartTaskEntry right,
) {
  final timeCompare = _compareExecutionChartNullableDate(
    _resolveExecutionChartEntrySortTime(left),
    _resolveExecutionChartEntrySortTime(right),
  );
  if (timeCompare != 0) {
    return timeCompare;
  }

  final entryCompare = left.row.entryIndex.compareTo(right.row.entryIndex);
  if (entryCompare != 0) {
    return entryCompare;
  }

  final manualOrderCompare =
      (left.task?.manualSortOrder ?? 0) - (right.task?.manualSortOrder ?? 0);
  if (manualOrderCompare != 0) {
    return manualOrderCompare;
  }

  final occurrenceCompare =
      (left.task?.occurrenceIndex ?? 0) - (right.task?.occurrenceIndex ?? 0);
  if (occurrenceCompare != 0) {
    return occurrenceCompare;
  }

  return left.row.taskTitle.toLowerCase().compareTo(
    right.row.taskTitle.toLowerCase(),
  );
}

DateTime? _resolveExecutionChartEntrySortTime(_ExecutionChartTaskEntry entry) {
  // WHY: Logged work can have clock times, while scheduled-only tasks only
  // have dates. Prefer the most precise operational time before falling back
  // to the task schedule so the visual stack reads in execution order.
  return entry.row.clockInTime ??
      entry.row.clockOutTime ??
      entry.row.workDate ??
      entry.task?.startDate ??
      entry.task?.dueDate;
}

int _compareExecutionChartNullableDate(DateTime? left, DateTime? right) {
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

Iterable<DateTime?> _resolveExecutionChartTaskDates(ProductionTask task) sync* {
  final normalizedStart = task.startDate == null
      ? null
      : _toDayStart(task.startDate!);
  final normalizedDue = task.dueDate == null
      ? null
      : _toDayStart(task.dueDate!);

  if (normalizedStart == null && normalizedDue == null) {
    yield null;
    return;
  }

  var rangeStart = normalizedStart ?? normalizedDue!;
  var rangeEnd = normalizedDue ?? normalizedStart!;
  if (rangeEnd.isBefore(rangeStart)) {
    final originalStart = rangeStart;
    rangeStart = rangeEnd;
    rangeEnd = originalStart;
  }

  for (
    DateTime current = rangeStart;
    !current.isAfter(rangeEnd);
    current = current.add(const Duration(days: 1))
  ) {
    yield current;
  }
}

ProductionTimelineRow _buildExecutionChartAggregateRow({
  required ProductionTask? task,
  required List<ProductionTimelineRow> rows,
  required DateTime? workDate,
}) {
  final exemplar = rows.isEmpty ? null : rows.last;
  final proofs = rows.expand((row) => row.proofs).toList();
  final approvalState = _resolveExecutionChartAggregateApprovalState(
    task: task,
    rows: rows,
  );
  final status = _resolveExecutionChartAggregateStatus(
    task: task,
    rows: rows,
    approvalState: approvalState,
  );

  return ProductionTimelineRow(
    id:
        exemplar?.id ??
        "${task?.id ?? "execution-task"}-${_toExecutionChartDayKey(workDate)}",
    workDate: workDate ?? exemplar?.workDate,
    taskId: task?.id ?? exemplar?.taskId ?? "",
    planId: task?.planId ?? exemplar?.planId ?? "",
    entryIndex: exemplar?.entryIndex ?? 1,
    staffId: exemplar?.staffId ?? "",
    attendanceId: exemplar?.attendanceId ?? "",
    unitId: exemplar?.unitId ?? "",
    taskDayLedgerId: exemplar?.taskDayLedgerId ?? "",
    taskTitle: _resolveExecutionChartTaskTitle(task: task, rows: rows),
    phaseName: exemplar?.phaseName ?? "",
    farmerName: exemplar?.farmerName ?? "",
    expectedPlots: rows.fold<num>(0, (sum, row) => sum + row.expectedPlots),
    actualPlots: rows.fold<num>(0, (sum, row) => sum + row.actualPlots),
    unitContribution: rows.fold<num>(
      0,
      (sum, row) => sum + row.unitContribution,
    ),
    quantityActivityType: exemplar?.quantityActivityType ?? "",
    quantityAmount: rows.fold<num>(0, (sum, row) => sum + row.quantityAmount),
    activityType: exemplar?.activityType ?? "",
    activityQuantity: rows.fold<num>(
      0,
      (sum, row) => sum + row.activityQuantity,
    ),
    quantityUnit: exemplar?.quantityUnit ?? "",
    status: status,
    delay: _firstExecutionChartNonEmptyValue(
      rows.map((row) => row.delay.trim()),
    ),
    delayReason: _firstExecutionChartNonEmptyValue(
      rows.map((row) => row.delayReason.trim()),
    ),
    approvalState: approvalState,
    approvedBy: exemplar?.approvedBy ?? "",
    approvedAt: _resolveExecutionChartLatestApprovedAt(rows),
    notes: exemplar?.notes ?? "",
    proofs: proofs,
    proofCount: rows.fold<int>(0, (sum, row) => sum + row.proofCount),
    proofCountRequired: rows.fold<int>(
      0,
      (currentMax, row) => row.proofCountRequired > currentMax
          ? row.proofCountRequired
          : currentMax,
    ),
    proofCountUploaded: rows.fold<int>(
      0,
      (sum, row) => sum + row.proofCountUploaded,
    ),
    sessionStatus: exemplar?.sessionStatus ?? "",
    clockInTime: exemplar?.clockInTime,
    clockOutTime: exemplar?.clockOutTime,
  );
}

String _resolveExecutionChartTaskTitle({
  required ProductionTask? task,
  required List<ProductionTimelineRow> rows,
}) {
  final taskTitle = task?.title.trim() ?? "";
  if (taskTitle.isNotEmpty) {
    return taskTitle;
  }
  return rows.isEmpty ? _dash : rows.first.taskTitle;
}

String _resolveExecutionChartAggregateApprovalState({
  required ProductionTask? task,
  required List<ProductionTimelineRow> rows,
}) {
  if (rows.isNotEmpty) {
    if (rows.any((row) => row.approvalState == _progressApprovalNeedsReview)) {
      return _progressApprovalNeedsReview;
    }
    if (rows.every((row) => row.approvalState == _progressApprovalApproved)) {
      return _progressApprovalApproved;
    }
    return _progressApprovalPending;
  }

  final taskApprovalStatus = task?.approvalStatus.trim().toLowerCase() ?? "";
  if (taskApprovalStatus == _approvalApproved) {
    return _progressApprovalApproved;
  }
  if (taskApprovalStatus == _approvalRejected) {
    return _progressApprovalNeedsReview;
  }
  return _progressApprovalPending;
}

String _resolveExecutionChartAggregateStatus({
  required ProductionTask? task,
  required List<ProductionTimelineRow> rows,
  required String approvalState,
}) {
  if (approvalState == _progressApprovalApproved) {
    return _taskStatusDone;
  }
  final taskStatus = task?.status.trim() ?? "";
  if (taskStatus.isNotEmpty) {
    return taskStatus;
  }
  if (rows.isNotEmpty) {
    return rows.last.status;
  }
  return _taskStatusPending;
}

bool _isExecutionChartTaskCompleted({
  required ProductionTask? task,
  required List<ProductionTimelineRow> rows,
}) {
  final taskStatus = task?.status.trim().toLowerCase() ?? "";
  final taskApprovalStatus = task?.approvalStatus.trim().toLowerCase() ?? "";
  if (taskApprovalStatus == _approvalApproved ||
      taskStatus == _taskStatusDone ||
      taskStatus == "completed" ||
      taskStatus == _approvalApproved) {
    return true;
  }
  if (rows.isEmpty) {
    return false;
  }
  return rows.every(_isExecutionChartRowCompleted);
}

String _resolveExecutionChartTaskStatusLabel({
  required ProductionTask? task,
  required List<ProductionTimelineRow> rows,
  required ProductionTimelineRow aggregateRow,
}) {
  final taskStatus = task?.status.trim() ?? "";
  if (aggregateRow.approvalState == _progressApprovalApproved) {
    return "completed";
  }
  if (taskStatus.isNotEmpty) {
    return taskStatus;
  }
  if (rows.isNotEmpty) {
    return _resolveTimelineStatusLabel(aggregateRow);
  }
  return _taskStatusPending;
}

DateTime? _resolveExecutionChartLatestApprovedAt(
  List<ProductionTimelineRow> rows,
) {
  DateTime? latestApprovedAt;
  for (final row in rows) {
    final approvedAt = row.approvedAt;
    if (approvedAt == null) {
      continue;
    }
    if (latestApprovedAt == null || approvedAt.isAfter(latestApprovedAt)) {
      latestApprovedAt = approvedAt;
    }
  }
  return latestApprovedAt;
}

String _firstExecutionChartNonEmptyValue(Iterable<String> values) {
  for (final value in values) {
    if (value.trim().isNotEmpty) {
      return value;
    }
  }
  return "";
}

bool _isExecutionChartRowCompleted(ProductionTimelineRow row) {
  if (row.approvalState == _progressApprovalApproved) {
    return true;
  }
  final normalizedStatus = row.status.trim().toLowerCase();
  return normalizedStatus == _taskStatusDone ||
      normalizedStatus == "completed" ||
      normalizedStatus == _approvalApproved;
}

String _resolveExecutionChartWorkerLabel({
  required List<ProductionTimelineRow> rows,
  required ProductionTask? task,
  required Map<String, BusinessStaffProfileSummary> staffMap,
}) {
  for (final row in rows) {
    if (row.farmerName.trim().isNotEmpty) {
      return row.farmerName;
    }
  }
  if (task != null) {
    final assignedStaffLabel = _buildAssignedStaffLabel(
      _resolveAssignedStaffIds(task),
      staffMap,
    );
    if (assignedStaffLabel.trim().isNotEmpty && assignedStaffLabel != _dash) {
      return assignedStaffLabel;
    }
  }
  for (final row in rows) {
    if (row.staffId.trim().isNotEmpty) {
      return _resolveStaffDisplayName(row.staffId, staffMap);
    }
  }
  return _dash;
}

String _buildExecutionChartAssignedPeopleSummary(
  List<_ExecutionChartTaskEntry> tasks,
) {
  final uniqueNames = tasks
      .map((task) => task.workerLabel.trim())
      .where((label) => label.isNotEmpty && label != _dash)
      .toSet()
      .toList();
  if (uniqueNames.isEmpty) {
    return _dash;
  }
  if (uniqueNames.length <= 2) {
    return uniqueNames.join(", ");
  }
  return "${uniqueNames.take(2).join(", ")} +${uniqueNames.length - 2}";
}

String _formatExecutionChartWeekday(DateTime? date) {
  if (date == null) {
    return "Day";
  }
  const weekdayLabels = <String>[
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
    "Sun",
  ];
  return weekdayLabels[date.weekday - 1];
}

String _formatExecutionChartDayDate(DateTime? date) {
  if (date == null) {
    return _dash;
  }
  const monthLabels = <String>[
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
  return "${date.day.toString().padLeft(2, "0")} ${monthLabels[date.month - 1]}";
}

_ExecutionChartDayGroup? _resolveExecutionChartBestDay(
  List<_ExecutionChartDayGroup> groups,
) {
  if (groups.isEmpty) {
    return null;
  }
  var bestDay = groups.first;
  for (final group in groups.skip(1)) {
    if (group.completedCount > bestDay.completedCount) {
      bestDay = group;
      continue;
    }
    if (group.completedCount == bestDay.completedCount &&
        group.totalTasks > bestDay.totalTasks) {
      bestDay = group;
      continue;
    }
    final groupDate = group.workDate;
    final bestDayDate = bestDay.workDate;
    if (group.completedCount == bestDay.completedCount &&
        group.totalTasks == bestDay.totalTasks &&
        groupDate != null &&
        bestDayDate != null &&
        groupDate.isAfter(bestDayDate)) {
      bestDay = group;
    }
  }
  return bestDay;
}

String _resolveInitialExecutionChartDayKey(
  List<_ExecutionChartDayGroup> groups, {
  DateTime? referenceDate,
}) {
  if (groups.isEmpty) {
    return "";
  }

  final normalizedReferenceDate = _toDayStart(referenceDate ?? DateTime.now());
  final referenceDayKey = _toExecutionChartDayKey(normalizedReferenceDate);
  for (final group in groups) {
    if (group.dayKey == referenceDayKey) {
      return group.dayKey;
    }
  }

  _ExecutionChartDayGroup? latestPastGroup;
  for (final group in groups) {
    final workDate = group.workDate;
    if (workDate == null) {
      continue;
    }
    if (_toDayStart(workDate).isAfter(normalizedReferenceDate)) {
      break;
    }
    latestPastGroup = group;
  }

  if (latestPastGroup != null) {
    return latestPastGroup.dayKey;
  }
  return groups.first.dayKey;
}

String _buildExecutionChartBestDayLabel(_ExecutionChartDayGroup? group) {
  if (group == null) {
    return _dash;
  }
  return "${_formatExecutionChartWeekday(group.workDate)} ${group.completedCount}";
}

String _buildExecutionChartTooltip(_ExecutionChartDayGroup group) {
  return "${formatDateLabel(group.workDate)}\n"
      "Total visible tasks: ${group.totalTasks}\n"
      "In progress: ${group.inProgressCount}\n"
      "Completed / approved: ${group.completedCount}\n"
      "Assigned people: ${group.assignedPeopleSummary}\n"
      "Snapshot: ${group.completionSnapshot}";
}

class _ExecutionDayStackChart extends StatefulWidget {
  final String planId;
  final List<ProductionTimelineRow> rows;
  final Map<String, ProductionTask> taskById;
  final Map<String, BusinessStaffProfileSummary> staffMap;

  const _ExecutionDayStackChart({
    required this.planId,
    required this.rows,
    required this.taskById,
    required this.staffMap,
  });

  @override
  State<_ExecutionDayStackChart> createState() =>
      _ExecutionDayStackChartState();
}

class _ExecutionDayStackChartState extends State<_ExecutionDayStackChart> {
  final ScrollController _chartScrollController = ScrollController();
  String? _selectedDayKey;
  String? _lastAutoAlignedDayKey;
  int? _lastAutoAlignedGroupCount;

  void _selectDay(_ExecutionChartDayGroup group) {
    AppDebug.log(
      _logTag,
      _executionChartDetailsAction,
      extra: {
        _extraPlanIdKey: widget.planId,
        "dayKey": group.dayKey,
        "visibleTasks": group.totalTasks,
      },
    );
    setState(() {
      _selectedDayKey = group.dayKey;
    });
  }

  void _alignDefaultSelectedDay({
    required List<_ExecutionChartDayGroup> groups,
    required String selectedDayKey,
    required double barWidth,
    required bool requiresScroll,
  }) {
    if (_selectedDayKey != null || !requiresScroll) {
      return;
    }
    if (_lastAutoAlignedDayKey == selectedDayKey &&
        _lastAutoAlignedGroupCount == groups.length) {
      return;
    }

    _lastAutoAlignedDayKey = selectedDayKey;
    _lastAutoAlignedGroupCount = groups.length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chartScrollController.hasClients) {
        return;
      }
      final selectedIndex = groups.indexWhere(
        (group) => group.dayKey == selectedDayKey,
      );
      if (selectedIndex < 0) {
        return;
      }

      final position = _chartScrollController.position;
      final targetOffset =
          (selectedIndex * barWidth) -
          ((position.viewportDimension - barWidth) / 2);
      final clampedOffset = targetOffset.clamp(0.0, position.maxScrollExtent);
      if ((_chartScrollController.offset - clampedOffset).abs() < 1) {
        return;
      }

      // WHY: The default selected day should be visible immediately so the
      // chart and the detail card open on the same operational date.
      _chartScrollController.jumpTo(clampedOffset);
    });
  }

  void _openTaskDetail(_ExecutionChartTaskEntry taskEntry) {
    AppDebug.log(
      _logTag,
      _executionChartTaskNavigationAction,
      extra: {
        _extraPlanIdKey: widget.planId,
        _extraTaskIdKey: taskEntry.row.taskId,
        "workDate": _toWorkDateKey(taskEntry.row.workDate),
      },
    );
    context.push(
      productionPlanTaskDetailPath(
        planId: widget.planId,
        taskId: taskEntry.row.taskId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _buildExecutionChartDayGroups(
      rows: widget.rows,
      taskById: widget.taskById,
      staffMap: widget.staffMap,
    );
    if (groups.isEmpty) {
      return const _InlineEmptyState(
        title: _executionChartEmptyTitle,
        message: _executionChartEmptyMessage,
      );
    }

    final selectedDayKey =
        _selectedDayKey ?? _resolveInitialExecutionChartDayKey(groups);
    final selectedGroup = groups.firstWhere(
      (group) => group.dayKey == selectedDayKey,
      orElse: () => groups.last,
    );
    final totalVisibleTasks = groups
        .expand((group) => group.tasks.map((task) => task.row.taskId.trim()))
        .where((taskId) => taskId.isNotEmpty)
        .toSet()
        .length;
    final approvedSegments = groups.fold<int>(
      0,
      (sum, group) => sum + group.completedCount,
    );
    final bestDay = _resolveExecutionChartBestDay(groups);
    final maxTasks = groups.fold<int>(
      0,
      (currentMax, group) =>
          group.totalTasks > currentMax ? group.totalTasks : currentMax,
    );
    final chartTaskCount = maxTasks == 0 ? 1 : maxTasks;
    final chartHeight = chartTaskCount * _executionChartUnitHeight;
    final chartFrameHeight =
        chartHeight +
        _executionChartTopLabelHeight +
        _executionChartXAxisLabelHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: _cardSpacing,
          runSpacing: _cardSpacing,
          children: const [
            _InfoPill(
              icon: Icons.hourglass_top_outlined,
              label: _executionChartInProgressLabel,
              tone: AppStatusTone.warning,
            ),
            _InfoPill(
              icon: Icons.check_circle_outline,
              label: _executionChartCompletedApprovedLabel,
              tone: AppStatusTone.success,
            ),
          ],
        ),
        const SizedBox(height: _cardSpacing),
        Wrap(
          spacing: _cardSpacing,
          runSpacing: _cardSpacing,
          children: [
            ProductionKpiCard(
              label: _executionChartVisibleTasksLabel,
              value: "$totalVisibleTasks",
              icon: Icons.stacked_bar_chart_outlined,
              tone: AppStatusTone.info,
            ),
            ProductionKpiCard(
              label: _executionChartBestDayLabel,
              value: _buildExecutionChartBestDayLabel(bestDay),
              icon: Icons.emoji_events_outlined,
              tone: bestDay == null || bestDay.completedCount == 0
                  ? AppStatusTone.neutral
                  : AppStatusTone.success,
            ),
            ProductionKpiCard(
              label: _executionChartApprovedSegmentsLabel,
              value: "$approvedSegments",
              icon: Icons.verified_outlined,
              tone: approvedSegments > 0
                  ? AppStatusTone.success
                  : AppStatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: _cardSpacing),
        _DetailPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _executionChartTaskCountLabel.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: chartFrameHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      height: chartFrameHeight,
                      child: Column(
                        children: [
                          const SizedBox(height: _executionChartTopLabelHeight),
                          SizedBox(
                            height: chartHeight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                for (
                                  int level = chartTaskCount;
                                  level >= 0;
                                  level--
                                )
                                  Text(
                                    "$level",
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(
                            height: _executionChartXAxisLabelHeight,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final requiresScroll =
                              groups.length * _executionChartColumnMinWidth >
                              constraints.maxWidth;
                          final barWidth = requiresScroll
                              ? _executionChartColumnMinWidth
                              : constraints.maxWidth / groups.length;
                          final chartWidth = requiresScroll
                              ? groups.length * _executionChartColumnMinWidth
                              : constraints.maxWidth;

                          _alignDefaultSelectedDay(
                            groups: groups,
                            selectedDayKey: selectedGroup.dayKey,
                            barWidth: barWidth,
                            requiresScroll: requiresScroll,
                          );

                          return SingleChildScrollView(
                            key: const ValueKey("execution-chart-scroll"),
                            controller: _chartScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: chartWidth,
                              height: chartFrameHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: groups.map((group) {
                                        return SizedBox(
                                          width: barWidth,
                                          height: chartFrameHeight,
                                          child: _ExecutionChartBar(
                                            interactionKey: ValueKey(
                                              "execution-chart-bar-${group.dayKey}",
                                            ),
                                            group: group,
                                            plotHeight: chartHeight,
                                            isSelected:
                                                selectedGroup.dayKey ==
                                                group.dayKey,
                                            onTap: () => _selectDay(group),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top:
                                        _executionChartTopLabelHeight +
                                        chartHeight -
                                        _executionChartBaselineThickness,
                                    child: IgnorePointer(
                                      child: Container(
                                        key: const ValueKey(
                                          "execution-chart-zero-baseline",
                                        ),
                                        height:
                                            _executionChartBaselineThickness,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant
                                              .withValues(alpha: 0.95),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _cardSpacing),
        _DetailPanel(
          child: Column(
            key: const ValueKey("execution-chart-day-details"),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ProductionSectionHeader(
                      title:
                          "$_executionChartTaskDetailsTitle · ${formatDateLabel(selectedGroup.workDate)}",
                      subtitle: _executionChartTaskDetailsMessage,
                    ),
                  ),
                  const SizedBox(width: _cardSpacing),
                  _InfoPill(
                    icon: Icons.event_note_outlined,
                    label: "${selectedGroup.totalTasks} $_tasksSuffix",
                    tone: AppStatusTone.info,
                  ),
                ],
              ),
              const SizedBox(height: _cardSpacing),
              Wrap(
                spacing: _cardSpacing,
                runSpacing: _cardSpacing,
                children: [
                  _InfoPill(
                    icon: Icons.analytics_outlined,
                    label:
                        "$_executionChartSnapshotSummaryLabel: ${selectedGroup.completionSnapshot}",
                    tone: selectedGroup.completedCount > 0
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                  ),
                  _InfoPill(
                    icon: Icons.groups_outlined,
                    label:
                        "$_executionChartAssignedPeopleLabel: ${selectedGroup.assignedPeopleSummary}",
                    tone: AppStatusTone.info,
                  ),
                ],
              ),
              const SizedBox(height: _cardSpacing),
              Column(
                children: selectedGroup.tasks.map((taskEntry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: _cardSpacing),
                    child: _ExecutionChartTaskCard(
                      interactionKey: ValueKey(
                        "execution-chart-task-${taskEntry.row.taskId}",
                      ),
                      entry: taskEntry,
                      onTap: () => _openTaskDetail(taskEntry),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _chartScrollController.dispose();
    super.dispose();
  }
}

class _ExecutionChartBar extends StatelessWidget {
  final Key? interactionKey;
  final _ExecutionChartDayGroup group;
  final double plotHeight;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExecutionChartBar({
    this.interactionKey,
    required this.group,
    required this.plotHeight,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedBorder = isSelected
        ? colorScheme.primary.withValues(alpha: 0.22)
        : Colors.transparent;
    final selectedSurface = isSelected
        ? colorScheme.surfaceContainerLow
        : Colors.transparent;
    final orderedSegments = [
      for (int index = 0; index < group.tasks.length; index++)
        (entry: group.tasks[index], segmentIndex: index + 1),
    ];

    return Tooltip(
      message: _buildExecutionChartTooltip(group),
      waitDuration: const Duration(milliseconds: 150),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: interactionKey,
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height:
                  _executionChartTopLabelHeight +
                  plotHeight +
                  _executionChartXAxisLabelHeight,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selectedSurface,
                borderRadius: BorderRadius.circular(18),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selectedBorder),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: _executionChartTopLabelHeight,
                    child: Center(
                      child: Text(
                        "${group.totalTasks}",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: plotHeight,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: _executionChartBaselineThickness,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // WHY: Reversing only the render pass keeps the
                            // chronological task order intact while placing
                            // segment 1 on the zero line and stacking upward.
                            for (final segment in orderedSegments.reversed)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: segment.segmentIndex == 1
                                      ? 0
                                      : _executionChartSegmentGap,
                                ),
                                child: _ExecutionChartSegment(
                                  entry: segment.entry,
                                  segmentIndex: segment.segmentIndex,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _executionChartXAxisLabelHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatExecutionChartWeekday(group.workDate),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatExecutionChartDayDate(group.workDate),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExecutionChartSegment extends StatelessWidget {
  final _ExecutionChartTaskEntry entry;
  final int segmentIndex;

  const _ExecutionChartSegment({
    required this.entry,
    required this.segmentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final tone = entry.isCompleted
        ? AppStatusTone.success
        : AppStatusTone.warning;
    final accent = _toneAccentColor(context, tone);

    return Container(
      key: ValueKey(
        "execution-chart-segment-${entry.row.taskId}-${_toExecutionChartDayKey(entry.row.workDate)}",
      ),
      height: _executionChartSegmentHeight,
      width: _executionChartSegmentWidth,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.94),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              "$segmentIndex",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExecutionChartTaskCard extends StatelessWidget {
  final Key? interactionKey;
  final _ExecutionChartTaskEntry entry;
  final VoidCallback onTap;

  const _ExecutionChartTaskCard({
    this.interactionKey,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: interactionKey,
        borderRadius: BorderRadius.circular(_summaryCardRadius),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(_summaryCardPadding),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_summaryCardRadius),
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
                          entry.row.taskTitle,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.workerLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _cardSpacing),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ProductionStatusPill(label: entry.statusLabel),
                      const SizedBox(height: 8),
                      _InfoPill(
                        icon: Icons.verified_outlined,
                        label: entry.approvalLabel,
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
                    label: _executionChartCurrentProgressLabel,
                    value: entry.progressLabel,
                    tone: entry.isCompleted
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                  ),
                  _MiniMetricCard(
                    label: _executionChartExpectedQuantityLabel,
                    value: _formatPlanProgressAmount(entry.row.expectedPlots),
                    tone: AppStatusTone.info,
                  ),
                  _MiniMetricCard(
                    label: _executionChartActualQuantityLabel,
                    value: _formatPlanProgressAmount(entry.row.actualPlots),
                    tone: entry.row.actualPlots > 0
                        ? AppStatusTone.success
                        : AppStatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: _cardSpacing),
              Wrap(
                spacing: _cardSpacing,
                runSpacing: _cardSpacing,
                children: [
                  _InfoPill(
                    icon: Icons.warning_amber_outlined,
                    label: "Delay: ${entry.delayLabel}",
                    tone: entry.delayLabel == _dash
                        ? AppStatusTone.neutral
                        : AppStatusTone.warning,
                  ),
                  _InfoPill(
                    icon: Icons.photo_library_outlined,
                    label: "${entry.row.proofCount} proof(s)",
                    tone: entry.row.proofCount > 0
                        ? AppStatusTone.info
                        : AppStatusTone.neutral,
                  ),
                  _InfoPill(
                    icon: Icons.event_note_outlined,
                    label:
                        "$_executionChartDateLabel: ${formatDateLabel(entry.row.workDate)}",
                    tone: AppStatusTone.info,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodRollupTable extends StatelessWidget {
  final List<ProductionPeriodRollup> rollups;
  final String emptyTitle;
  final String emptyMessage;

  const _PeriodRollupTable({
    required this.rollups,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (rollups.isEmpty) {
      return _InlineEmptyState(title: emptyTitle, message: emptyMessage);
    }

    final sortedRollups = [...rollups]
      ..sort((left, right) {
        final leftDate =
            left.periodStart ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.periodStart ?? DateTime.fromMillisecondsSinceEpoch(0);
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
        final periodLabel = _formatPeriodRangeLabel(
          rollup.periodStart,
          rollup.periodEnd,
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
                        periodLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ProductionStatusPill(label: "${rollup.daysCovered} days"),
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
                      tone: AppStatusTone.info,
                    ),
                    _MiniMetricCard(
                      label: _dailyRollupAssignedLabel,
                      value: "${rollup.assignedStaffCount}",
                      tone: AppStatusTone.info,
                    ),
                    _MiniMetricCard(
                      label: _dailyRollupAttendedAssignedLabel,
                      value: "${rollup.attendedAssignedStaffCount}",
                      tone: AppStatusTone.success,
                    ),
                    _MiniMetricCard(
                      label: _dailyRollupAbsentLabel,
                      value: "${rollup.absentAssignedStaffCount}",
                      tone: rollup.absentAssignedStaffCount > 0
                          ? AppStatusTone.warning
                          : AppStatusTone.success,
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
                      tone: AppStatusTone.info,
                    ),
                    _InfoPill(
                      icon: Icons.done_all_outlined,
                      label: "$_dailyRollupActualLabel: ${rollup.actualPlots}",
                      tone: rollup.actualPlots > 0
                          ? AppStatusTone.success
                          : AppStatusTone.neutral,
                    ),
                    _InfoPill(
                      icon: Icons.groups_outlined,
                      label: "$_dailyRollupCoverageLabel: $coverage",
                      tone: _ratioTone(rollup.attendanceCoverageRate),
                    ),
                    _InfoPill(
                      icon: Icons.speed_outlined,
                      label: "$_dailyRollupPlotsPerHourLabel: $plotsPerHour",
                      tone: AppStatusTone.info,
                    ),
                    _InfoPill(
                      icon: Icons.event_note_outlined,
                      label: "${rollup.rowsLogged} logs",
                      tone: AppStatusTone.info,
                    ),
                    _InfoPill(
                      icon: Icons.flag_outlined,
                      label: "$_dailyRollupCompletionLabel: $completion",
                      tone: _ratioTone(rollup.completionRate),
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
                      tone: AppStatusTone.info,
                    ),
                    _MiniMetricCard(
                      label: "Actual",
                      value: "${score.totalActual}",
                      tone: score.totalActual > 0
                          ? AppStatusTone.success
                          : AppStatusTone.neutral,
                    ),
                    _MiniMetricCard(
                      label: "Completion",
                      value: "$percent$_percentSuffix",
                      tone: _ratioTone(score.completionRatio),
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
  final String planId;
  final ProductionKpis? kpis;

  const _PhaseProgressList({required this.planId, required this.kpis});

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
          final colorScheme = Theme.of(context).colorScheme;
          final progressValue = phase.completionRate
              .clamp(_progressMin, _progressMax)
              .toDouble();
          final tone = _progressTone(progressValue);
          final accent = tone == AppStatusTone.neutral
              ? colorScheme.outline
              : _toneAccentColor(context, tone);
          final percent =
              "${_formatPercent(phase.completionRate)}$_percentSuffix";
          return Padding(
            padding: const EdgeInsets.only(bottom: _cardSpacing),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(_summaryCardRadius),
                onTap: () {
                  context.push(
                    productionPlanPhaseDetailPath(
                      planId: planId,
                      phaseId: phase.phaseId,
                    ),
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.all(_cardSpacing),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(_summaryCardRadius),
                    border: Border.all(
                      color: tone == AppStatusTone.neutral
                          ? colorScheme.outlineVariant
                          : accent.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              phase.name,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: tone == AppStatusTone.neutral
                                ? colorScheme.onSurfaceVariant
                                : accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: _phaseProgressSpacing),
                      LinearProgressIndicator(
                        value: progressValue,
                        minHeight: _progressIndicatorHeight,
                        color: accent,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(height: _phaseProgressSpacing),
                      Text(
                        "${phase.completedTasks}/${phase.totalTasks} ($percent)",
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tone == AppStatusTone.neutral ? null : accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Open ${phase.name} tasks, proof, and remaining work.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
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
                        tone: AppStatusTone.danger,
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
                      tone: AppStatusTone.info,
                    ),
                    _MiniMetricCard(
                      label: _phaseUnitCompletedLabel,
                      value: "${row.completedUnitCount}",
                      tone: row.completedUnitCount > 0
                          ? AppStatusTone.success
                          : AppStatusTone.neutral,
                    ),
                    _MiniMetricCard(
                      label: _phaseUnitRemainingLabel,
                      value: "${row.remainingUnits}",
                      tone: row.remainingUnits > 0
                          ? AppStatusTone.warning
                          : AppStatusTone.success,
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
                        tone: AppStatusTone.info,
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
                      tone: row.delayedByDays > 0
                          ? AppStatusTone.danger
                          : AppStatusTone.success,
                    ),
                    _MiniMetricCard(
                      label: _unitDivergenceShiftedTasksLabel,
                      value: "${row.shiftedTaskCount}",
                      tone: row.shiftedTaskCount > 0
                          ? AppStatusTone.warning
                          : AppStatusTone.neutral,
                    ),
                    _MiniMetricCard(
                      label: _unitDivergenceWarningCountLabel,
                      value: "${row.warningCount}",
                      tone: row.warningCount > 0
                          ? AppStatusTone.danger
                          : AppStatusTone.success,
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
                      tone: _severityTone(warning.severity),
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
                      tone: warning.shiftDays > 0
                          ? AppStatusTone.warning
                          : AppStatusTone.neutral,
                    ),
                    _InfoPill(
                      icon: Icons.event_outlined,
                      label: formatDateLabel(warning.createdAt),
                      tone: AppStatusTone.info,
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
                tone: summary!.totalAlerts > 0
                    ? AppStatusTone.info
                    : AppStatusTone.neutral,
              ),
              _DeviationMetricCard(
                title: _deviationSummaryOpenAlerts,
                value: "${summary!.openAlerts}",
                tone: summary!.openAlerts > 0
                    ? AppStatusTone.warning
                    : AppStatusTone.success,
              ),
              _DeviationMetricCard(
                title: _deviationSummaryLockedUnits,
                value: "${summary!.lockedUnits}",
                tone: summary!.lockedUnits > 0
                    ? AppStatusTone.danger
                    : AppStatusTone.success,
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
                                tone: alert.status == "open"
                                    ? AppStatusTone.warning
                                    : AppStatusTone.success,
                              ),
                              _InfoPill(
                                icon: alert.unitLocked
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined,
                                label: lockLabel,
                                tone: alert.unitLocked
                                    ? AppStatusTone.danger
                                    : AppStatusTone.success,
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
                            tone: alert.cumulativeDeviationDays > 0
                                ? AppStatusTone.danger
                                : AppStatusTone.success,
                          ),
                          _MiniMetricCard(
                            label: _deviationAlertThresholdLabel,
                            value: "${alert.thresholdDays} $_daysSuffix",
                            tone: AppStatusTone.warning,
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
                            tone: AppStatusTone.info,
                          ),
                          if (alert.resolvedAt != null)
                            _InfoPill(
                              icon: Icons.task_alt_outlined,
                              label:
                                  "Resolved ${formatDateLabel(alert.resolvedAt)}",
                              tone: AppStatusTone.success,
                            ),
                          if (alert.unitLockedAt != null)
                            _InfoPill(
                              icon: Icons.schedule_outlined,
                              label:
                                  "Locked ${formatDateLabel(alert.unitLockedAt)}",
                              tone: AppStatusTone.warning,
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
                            style: AppButtonStyles.outlined(
                              theme: Theme.of(context),
                              tone: AppStatusTone.success,
                            ),
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
                            style: AppButtonStyles.outlined(
                              theme: Theme.of(context),
                              tone: AppStatusTone.warning,
                            ),
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
  final AppStatusTone tone;

  const _DeviationMetricCard({
    required this.title,
    required this.value,
    this.tone = AppStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final badgeColors = _toneBadgeColors(context, tone);
    final usesTone = tone != AppStatusTone.neutral;

    return Container(
      width: 170,
      padding: const EdgeInsets.all(_summaryCardPadding),
      decoration: BoxDecoration(
        color: usesTone
            ? badgeColors.background
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_summaryCardRadius),
        border: Border.all(
          color: usesTone
              ? badgeColors.foreground.withValues(alpha: 0.18)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.bodySmall?.copyWith(
              color: usesTone
                  ? badgeColors.foreground.withValues(alpha: 0.88)
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _summaryMetaSpacing),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: usesTone ? badgeColors.foreground : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryHeaderChipData {
  final IconData icon;
  final String label;
  final AppStatusTone tone;

  const _SummaryHeaderChipData({
    required this.icon,
    required this.label,
    required this.tone,
  });
}

class _SummaryMetricData {
  final IconData icon;
  final String label;
  final String value;
  final String? helper;
  final AppStatusTone tone;

  const _SummaryMetricData({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
    this.tone = AppStatusTone.neutral,
  });
}

class _SummaryMetricWrap extends StatelessWidget {
  final List<_SummaryMetricData> metrics;
  final bool compact;
  final bool singleColumn;

  const _SummaryMetricWrap({
    required this.metrics,
    this.compact = false,
    this.singleColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = singleColumn
            ? constraints.maxWidth
            : _resolveSummaryMetricWidth(constraints.maxWidth);
        return Wrap(
          spacing: compact ? 8 : _cardSpacing,
          runSpacing: compact ? 8 : _cardSpacing,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: tileWidth,
                  child: _SummaryMetricCard(
                    icon: metric.icon,
                    label: metric.label,
                    value: metric.value,
                    helper: metric.helper,
                    tone: metric.tone,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SummaryStatusBadge extends StatelessWidget {
  final String label;

  const _SummaryStatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final badgeColors = _toneBadgeColors(context, _summaryStatusTone(label));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: badgeColors.foreground.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        formatProductionStatusLabel(label),
        style: textTheme.labelSmall?.copyWith(
          color: badgeColors.foreground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _SummaryHeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusTone tone;

  const _SummaryHeaderChip({
    required this.icon,
    required this.label,
    this.tone = AppStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final badgeColors = _toneBadgeColors(context, tone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _summarySurfaceColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _summaryBorderColor(theme)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: badgeColors.background,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 12, color: badgeColors.foreground),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? helper;
  final AppStatusTone tone;

  const _SummaryMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
    this.tone = AppStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final badgeColors = _toneBadgeColors(context, tone);

    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _summarySurfaceColor(theme),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _summaryBorderColor(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: badgeColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: badgeColors.foreground),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (helper != null && helper!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
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

class _SummaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusTone tone;
  final Future<void> Function() onPressed;

  const _SummaryActionButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final badgeColors = _toneBadgeColors(context, tone);

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: _summarySurfaceColor(theme),
        side: BorderSide(color: _summaryBorderColor(theme)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.centerLeft,
      ),
      onPressed: () async {
        await onPressed();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: badgeColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: badgeColors.foreground),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryAccordionSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool initiallyExpanded;

  const _SummaryAccordionSection({
    required this.title,
    this.subtitle,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: _summarySubtleSurfaceColor(theme),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _summaryBorderColor(theme)),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: _summaryBorderColor(theme), height: 1),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
          ],
        ),
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
                    final effectiveStatusLabel = _resolveTimelineStatusLabel(
                      row,
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
                                  ProductionStatusPill(
                                    label: effectiveStatusLabel,
                                  ),
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
                                style: AppButtonStyles.text(
                                  theme: Theme.of(context),
                                  tone: AppStatusTone.info,
                                ),
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
                                  style: AppButtonStyles.outlined(
                                    theme: Theme.of(context),
                                    tone: AppStatusTone.success,
                                  ),
                                  onPressed: () async {
                                    await onApproveProgress(row.id);
                                  },
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text(_approveLabel),
                                ),
                                OutlinedButton.icon(
                                  style: AppButtonStyles.outlined(
                                    theme: Theme.of(context),
                                    tone: AppStatusTone.warning,
                                  ),
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
                style: AppButtonStyles.outlined(
                  theme: Theme.of(context),
                  tone: AppStatusTone.info,
                ),
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
          TextButton(
            onPressed: onApprove,
            style: AppButtonStyles.text(
              theme: Theme.of(context),
              tone: AppStatusTone.success,
            ),
            child: const Text(_approveLabel),
          ),
          TextButton(
            onPressed: onReject,
            style: AppButtonStyles.text(
              theme: Theme.of(context),
              tone: AppStatusTone.danger,
            ),
            child: const Text(_rejectLabel),
          ),
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
              : hasRequiredTaskProgressProofMix(
                  selectedProofs,
                  requiredProofCount,
                );
          final readyProofCount = selectedProofs.length;
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
          final selectedAttendanceReady = selectedAttendance?.clockInAt != null;
          final selectedAttendanceComplete =
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
                      color: selectedAttendanceReady
                          ? Theme.of(dialogContext).colorScheme.primaryContainer
                          : Theme.of(
                              dialogContext,
                            ).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedAttendanceReady
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
                              : selectedAttendanceReady
                              ? Icons.logout_outlined
                              : Icons.lock_outline,
                          size: 18,
                          color: selectedAttendanceReady
                              ? Theme.of(dialogContext).colorScheme.primary
                              : Theme.of(dialogContext).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedAttendanceComplete
                                ? "Attendance complete for this staff on ${formatDateLabel(selectedDate)}."
                                : selectedAttendanceReady
                                ? "Clocked in for this staff on ${formatDateLabel(selectedDate)}. Submit will clock them out automatically."
                                : _logProgressAttendanceRequiredText,
                            style: Theme.of(dialogContext).textTheme.bodySmall
                                ?.copyWith(
                                  color: selectedAttendanceReady
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
                          "Proof media",
                          style: Theme.of(dialogContext).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          requiredProofCount == 0
                              ? "Enter a positive actual amount to unlock proof uploads."
                              : proofCountMatches
                              ? "$readyProofCount / $requiredProofCount proofs ready."
                              : buildTaskProgressProofRequirementText(
                                  requiredProofCount,
                                  exact: false,
                                ),
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
                          style: AppButtonStyles.outlined(
                            theme: Theme.of(dialogContext),
                            tone: AppStatusTone.info,
                          ),
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
                                ? "Add proofs"
                                : "Replace proofs",
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
                                    avatar: Icon(
                                      proof.isVideo
                                          ? Icons.videocam_outlined
                                          : Icons.image_outlined,
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
                onPressed: selectedAttendanceReady
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
                                "Proof uploads are not allowed when actual amount is 0.";
                          });
                          return;
                        }
                        if (requiredProofCount > 0 &&
                            !hasRequiredTaskProgressProofMix(
                              selectedProofs,
                              requiredProofCount,
                            )) {
                          setDialogState(() {
                            validationMessage =
                                buildTaskProgressProofRequirementText(
                                  requiredProofCount,
                                );
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
              child: const Text("Done"),
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
              child: const Text("Done"),
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

String _formatPeriodRangeLabel(DateTime? start, DateTime? end) {
  if (start == null && end == null) {
    return _dash;
  }
  if (start == null) {
    return formatDateLabel(end);
  }
  if (end == null) {
    return formatDateLabel(start);
  }
  return "${formatDateLabel(start)} - ${formatDateLabel(end)}";
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

String _resolveTimelineStatusLabel(ProductionTimelineRow row) {
  if (row.approvalState == _progressApprovalApproved) {
    return "completed";
  }
  return row.status;
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
  if (canUseBusinessOwnerEquivalentAccess(
    role: actorRole,
    staffRole: staffRole,
  )) {
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
  if (canUseBusinessOwnerEquivalentAccess(
    role: actorRole,
    staffRole: staffRole,
  )) {
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
  if (canUseBusinessOwnerEquivalentAccess(
    role: actorRole,
    staffRole: staffRole,
  )) {
    return true;
  }
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

String _resolveProductionDetailErrorMessage(
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

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
