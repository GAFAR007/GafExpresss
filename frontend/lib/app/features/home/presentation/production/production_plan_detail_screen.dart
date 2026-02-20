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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';

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
const String _backTap = "back_tap";
const String _screenTitle = "Production plan";
const String _summaryTitle = "Plan summary";
const String _kpiTitle = "KPIs";
const String _staffProgressTitle = "Farmer progress";
const String _phaseTitle = "Phase progress";
const String _timelineTitle = "Timeline table";
const String _tasksTitle = "Tasks";
const String _startLabel = "Start";
const String _endLabel = "End";
const String _assignedLabel = "Assigned";
const String _roleLabel = "Role";
const String _dueLabel = "Due";
const String _statusLabel = "Status";
const String _timelineDateLabel = "Date";
const String _timelineTaskLabel = "Task";
const String _timelinePhaseLabel = "Phase";
const String _timelineFarmerLabel = "Farmer";
const String _timelineExpectedLabel = "Expected Plots";
const String _timelineActualLabel = "Actual Plots";
const String _timelineDelayLabel = "Delay";
const String _timelineApprovalLabel = "Approval";
const String _timelineActionsLabel = "Actions";
const String _timelineNotesLabel = "Notes";
const String _timelineEmptyTitle = "No timeline data yet";
const String _timelineEmptyMessage =
    "Task schedule rows will appear when tasks are added.";
const String _productionStateLabel = "Product state";
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
const String _batchLogActualRequired = "Enter actual plots";
const String _batchLogActualInvalid = "Use a non-negative number";
const String _batchLogZeroDelayRequired =
    "Select a delay reason when actual is zero";
const String _logProgressDialogTitle = "Log daily work";
const String _logProgressDateLabel = "Date";
const String _logProgressFarmerLabel = "Farmer";
const String _logProgressActualPlotsLabel = "Actual plots";
const String _logProgressDelayReasonLabel = "Delay reason";
const String _logProgressZeroHelperText =
    "Use this to record absence or blocked workdays";
const String _logProgressNotesLabel = "Notes";
const String _logProgressNotesHint = "Optional context";
const String _logProgressZeroDelayValidationText =
    "Select a delay reason when actual plots is zero";
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
const String _phaseCompletionLabel = "Completion";
const String _staffProgressEmptyTitle = "No farmer scores yet";
const String _staffProgressEmptyMessage =
    "Farmer support scores appear after daily logs are recorded.";
const String _kpiEmptyTitle = "No KPI data yet";
const String _kpiEmptyMessage = "KPI cards will appear once tasks are tracked.";
const String _phaseEmptyTitle = "No phase progress yet";
const String _phaseEmptyMessage =
    "Phase completion will appear once tasks are created.";
const String _phaseEmptyTasks = "No tasks in this phase yet.";
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

class ProductionPlanDetailScreen extends ConsumerWidget {
  final String planId;

  const ProductionPlanDetailScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage, extra: {_extraPlanIdKey: planId});
    final detailAsync = ref.watch(productionPlanDetailProvider(planId));
    final staffAsync = ref.watch(productionStaffProvider);
    final session = ref.watch(authSessionProvider);
    final actorRole = session?.user.role;
    final isOwner = actorRole == _ownerRole;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log(_logTag, _backTap);
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              AppDebug.log(_logTag, _refreshAction);
              ref.invalidate(productionPlanDetailProvider(planId));
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
              userEmail: session?.user.email,
            );
            final canLogProgress = _canLogTaskProgress(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            final canReviewProgress = _canReviewTaskProgress(
              actorRole: actorRole,
              staffRole: selfStaffRole,
            );
            return _PlanDetailBody(
              detail: detail,
              staffMap: staffMap,
              isOwner: isOwner,
              canLogProgress: canLogProgress,
              canReviewProgress: canReviewProgress,
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
                    workDate,
                    actualPlots,
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
                            actualPlots: actualPlots,
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

class _PlanDetailBody extends StatelessWidget {
  final ProductionPlanDetail detail;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final bool canLogProgress;
  final bool canReviewProgress;
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
    DateTime workDate,
    num actualPlots,
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
  Widget build(BuildContext context) {
    // WHY: Group tasks by phase to render phase sections.
    final tasksByPhase = _groupTasksByPhase(detail.phases, detail.tasks);

    return ListView(
      padding: const EdgeInsets.all(_pagePadding),
      children: [
        _PlanSummaryCard(
          plan: detail.plan,
          preorderSummary: detail.preorderSummary,
          isOwner: isOwner,
          onReconcilePreorders: onReconcilePreorders,
          onUpdatePreorder: onUpdatePreorder,
        ),
        const SizedBox(height: _sectionSpacing),
        ProductionSectionHeader(title: _kpiTitle),
        const SizedBox(height: _cardSpacing),
        _KpiRow(kpis: detail.kpis),
        const SizedBox(height: _sectionSpacing),
        ProductionSectionHeader(title: _staffProgressTitle),
        const SizedBox(height: _cardSpacing),
        _StaffProgressList(scores: detail.staffProgressScores),
        const SizedBox(height: _sectionSpacing),
        ProductionSectionHeader(title: _phaseTitle),
        const SizedBox(height: _cardSpacing),
        _PhaseProgressList(kpis: detail.kpis),
        const SizedBox(height: _sectionSpacing),
        ProductionSectionHeader(title: _timelineTitle),
        const SizedBox(height: _cardSpacing),
        if (canLogProgress)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () async {
                final batchInput = await _showBatchLogProgressDialog(
                  context,
                  detail: detail,
                  staffMap: staffMap,
                );
                if (batchInput == null) {
                  return;
                }
                await onBatchLogProgress(
                  batchInput.workDate,
                  batchInput.entries,
                );
              },
              icon: const Icon(Icons.table_rows_outlined),
              label: const Text(_batchLogProgressLabel),
            ),
          ),
        if (canLogProgress) const SizedBox(height: _cardSpacing),
        _TimelineTaskTable(
          rows: detail.timelineRows,
          canReviewProgress: canReviewProgress,
          onApproveProgress: onApproveProgress,
          onRejectProgress: onRejectProgress,
        ),
        const SizedBox(height: _sectionSpacing),
        ProductionSectionHeader(title: _tasksTitle),
        const SizedBox(height: _cardSpacing),
        ...detail.phases.map((phase) {
          final phaseTasks = tasksByPhase[phase.id] ?? [];
          return _PhaseTaskSection(
            phase: phase,
            tasks: phaseTasks,
            staffMap: staffMap,
            isOwner: isOwner,
            canLogProgress: canLogProgress,
            onStatusChange: onStatusChange,
            onLogProgress: onLogProgress,
            onApprove: onApprove,
            onReject: onReject,
          );
        }),
      ],
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  final ProductionPlan plan;
  final ProductionPreorderSummary? preorderSummary;
  final bool isOwner;
  final Future<void> Function() onReconcilePreorders;
  final Future<void> Function(Map<String, dynamic> payload) onUpdatePreorder;

  const _PlanSummaryCard({
    required this.plan,
    required this.preorderSummary,
    required this.isOwner,
    required this.onReconcilePreorders,
    required this.onUpdatePreorder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
          Text(
            _summaryTitle,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: _summaryTitleSpacing),
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ProductionStatusPill(label: plan.status),
            ],
          ),
          const SizedBox(height: _summaryTitleSpacing),
          Text(
            "$_startLabel: ${formatDateLabel(plan.startDate)}",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _summaryMetaSpacing),
          Text(
            "$_endLabel: ${formatDateLabel(plan.endDate)}",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _summaryMetaSpacing),
          Text(
            "$_productionStateLabel: ${preorderSummary?.productionState.isNotEmpty == true ? preorderSummary!.productionState : _dash}",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _summaryMetaSpacing),
          Text(
            "$_preorderLabel: ${preorderSummary?.preorderEnabled == true ? _preorderEnabledLabel : _preorderDisabledLabel}",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (preorderSummary != null) ...[
            const SizedBox(height: _summaryMetaSpacing),
            Text(
              "$_preorderCapLabel: ${preorderSummary!.preorderCapQuantity}",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: _summaryMetaSpacing),
            Text(
              "$_effectiveCapLabel: ${preorderSummary!.effectiveCap}",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: _summaryMetaSpacing),
            Text(
              "$_confidenceLabel: $confidencePercent% (coverage $coveragePercent%)",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: _summaryMetaSpacing),
            Text(
              "$_preorderRemainingLabel: ${preorderSummary!.preorderRemainingQuantity}",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (isOwner) ...[
              const SizedBox(height: _summaryTitleSpacing),
              Wrap(
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
              ),
            ],
          ],
        ],
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
      return const ProductionEmptyState(
        title: _kpiEmptyTitle,
        message: _kpiEmptyMessage,
      );
    }

    final completion = "${_formatPercent(kpis!.completionRate)}$_percentSuffix";
    final onTime = "${_formatPercent(kpis!.onTimeRate)}$_percentSuffix";
    final avgDelay =
        "${kpis!.avgDelayDays.toStringAsFixed(_delayFixedDigits)} $_daysSuffix";

    return Wrap(
      spacing: _cardSpacing,
      runSpacing: _cardSpacing,
      children: [
        ProductionKpiCard(label: _kpiTotalTasks, value: "${kpis!.totalTasks}"),
        ProductionKpiCard(
          label: _kpiCompleted,
          value: "${kpis!.completedTasks}",
        ),
        ProductionKpiCard(label: _kpiOnTime, value: onTime),
        ProductionKpiCard(label: _kpiAvgDelay, value: avgDelay),
        ProductionKpiCard(label: _phaseCompletionLabel, value: completion),
      ],
    );
  }
}

class _StaffProgressList extends StatelessWidget {
  final List<ProductionStaffProgressScore> scores;

  const _StaffProgressList({required this.scores});

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return const ProductionEmptyState(
        title: _staffProgressEmptyTitle,
        message: _staffProgressEmptyMessage,
      );
    }

    return Wrap(
      spacing: _cardSpacing,
      runSpacing: _cardSpacing,
      children: scores.map((score) {
        final farmerName = score.farmerName.trim().isEmpty
            ? score.staffId
            : score.farmerName;
        final percent = _formatPercent(score.completionRatio);
        final value = "$percent$_percentSuffix • ${score.status}";
        return ProductionKpiCard(label: farmerName, value: value);
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
      return const ProductionEmptyState(
        title: _phaseEmptyTitle,
        message: _phaseEmptyMessage,
      );
    }

    return Column(
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
      return const ProductionEmptyState(
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
        return leftDate.compareTo(rightDate);
      });

    final columns = <DataColumn>[
      const DataColumn(label: Text(_timelineDateLabel)),
      const DataColumn(label: Text(_timelineTaskLabel)),
      const DataColumn(label: Text(_timelinePhaseLabel)),
      const DataColumn(label: Text(_timelineFarmerLabel)),
      const DataColumn(label: Text(_timelineExpectedLabel)),
      const DataColumn(label: Text(_timelineActualLabel)),
      const DataColumn(label: Text(_statusLabel)),
      const DataColumn(label: Text(_timelineDelayLabel)),
      const DataColumn(label: Text(_timelineApprovalLabel)),
      const DataColumn(label: Text(_timelineNotesLabel)),
    ];
    if (canReviewProgress) {
      columns.add(const DataColumn(label: Text(_timelineActionsLabel)));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: columns,
        rows: sortedRows.map((row) {
          final notes = row.notes.trim().isEmpty ? _dash : row.notes;
          final cells = <DataCell>[
            DataCell(Text(formatDateLabel(row.workDate))),
            DataCell(Text(row.taskTitle)),
            DataCell(Text(row.phaseName)),
            DataCell(Text(row.farmerName)),
            DataCell(Text("${row.expectedPlots}")),
            DataCell(Text("${row.actualPlots}")),
            DataCell(Text(row.status)),
            DataCell(Text(row.delayReason)),
            DataCell(Text(_formatProgressApprovalLabel(row.approvalState))),
            DataCell(Text(notes)),
          ];
          if (canReviewProgress) {
            cells.add(
              DataCell(
                Wrap(
                  spacing: _summaryMetaSpacing,
                  children: [
                    TextButton(
                      onPressed: () {
                        onApproveProgress(row.id);
                      },
                      child: const Text(_approveLabel),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _showProgressRejectDialog(
                          context,
                          onReject: (reason) =>
                              onRejectProgress(row.id, reason),
                        );
                      },
                      child: const Text(_rejectLabel),
                    ),
                  ],
                ),
              ),
            );
          }

          return DataRow(cells: cells);
        }).toList(),
      ),
    );
  }
}

class _PhaseTaskSection extends StatelessWidget {
  final ProductionPhase phase;
  final List<ProductionTask> tasks;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final bool canLogProgress;
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(
    String taskId,
    String? staffId,
    DateTime workDate,
    num actualPlots,
    String delayReason,
    String notes,
  )
  onLogProgress;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _PhaseTaskSection({
    required this.phase,
    required this.tasks,
    required this.staffMap,
    required this.isOwner,
    required this.canLogProgress,
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
                    staffMap: staffMap,
                    isOwner: isOwner,
                    canLogProgress: canLogProgress,
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
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final bool canLogProgress;
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(
    String taskId,
    String? staffId,
    DateTime workDate,
    num actualPlots,
    String delayReason,
    String notes,
  )
  onLogProgress;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _TaskCard({
    required this.task,
    required this.staffMap,
    required this.isOwner,
    required this.canLogProgress,
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
                    staffMap: staffMap,
                  );
                  if (input == null) {
                    return;
                  }
                  await onLogProgress(
                    task.id,
                    input.staffId,
                    input.workDate,
                    input.actualPlots,
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
  final DateTime workDate;
  final num actualPlots;
  final String delayReason;
  final String notes;

  const _LogProgressInput({
    required this.staffId,
    required this.workDate,
    required this.actualPlots,
    required this.delayReason,
    required this.notes,
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
}) async {
  // WHY: Batch logging lets managers submit multiple real daily updates in one pass.
  DateTime selectedDate = DateTime.now();
  List<_BatchLogRowDraft> rows = _buildBatchLogRowsForDate(
    workDate: selectedDate,
    detail: detail,
    staffMap: staffMap,
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
}) {
  final selectedDateKey = _toWorkDateKey(workDate);
  final existingByTaskStaff = <String, ProductionTimelineRow>{};
  for (final row in detail.timelineRows) {
    if (_toWorkDateKey(row.workDate) != selectedDateKey) {
      continue;
    }
    final key = "${row.taskId}|${row.staffId}";
    existingByTaskStaff[key] = row;
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
    for (final staffId in assignedStaffIds) {
      final key = "${task.id}|$staffId";
      final existingProgress = existingByTaskStaff[key];
      if (!taskScheduledForDate && existingProgress == null) {
        continue;
      }
      final isRecordedLocked = existingProgress != null;
      rows.add(
        _BatchLogRowDraft(
          rowId: "${task.id}_$staffId",
          taskId: task.id,
          taskTitle: task.title,
          phaseName: phaseNameById[task.phaseId] ?? _dash,
          staffId: staffId,
          staffName: _resolveStaffDisplayName(staffId, staffMap),
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

  rows.sort((left, right) {
    final taskCompare = left.taskTitle.toLowerCase().compareTo(
      right.taskTitle.toLowerCase(),
    );
    if (taskCompare != 0) {
      return taskCompare;
    }
    return left.staffName.toLowerCase().compareTo(
      right.staffName.toLowerCase(),
    );
  });

  return rows;
}

Future<_LogProgressInput?> _showLogProgressDialog(
  BuildContext context, {
  required List<String> assignedStaffIds,
  required Map<String, BusinessStaffProfileSummary> staffMap,
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
  final actualPlotsCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  final result = await showDialog<_LogProgressInput>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
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
                onPressed: () {
                  final actualPlots = num.tryParse(actualPlotsCtrl.text.trim());
                  if (actualPlots == null || actualPlots < 0) {
                    setDialogState(() {
                      validationMessage = "";
                    });
                    return;
                  }
                  if (hasMultipleAssignedStaff && selectedStaffId == null) {
                    setDialogState(() {
                      validationMessage = "";
                    });
                    return;
                  }
                  if (actualPlots == 0 &&
                      selectedDelayReason == _delayReasonNone) {
                    setDialogState(() {
                      validationMessage = _logProgressZeroDelayValidationText;
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    _LogProgressInput(
                      staffId: hasMultipleAssignedStaff
                          ? selectedStaffId
                          : null,
                      workDate: selectedDate,
                      actualPlots: actualPlots,
                      delayReason: selectedDelayReason,
                      notes: notesCtrl.text.trim(),
                    ),
                  );
                },
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

String _formatPercent(double value) {
  final percent = (value * _percentMultiplier).clamp(
    _percentMin,
    _percentMultiplier,
  );
  return percent.toStringAsFixed(_percentFixedDigits);
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

  return actorRole == _staffRole && staffRole == _staffRoleEstateManager;
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
