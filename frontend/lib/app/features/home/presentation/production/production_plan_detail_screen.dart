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
const String _approveAction = "approve_action";
const String _rejectAction = "reject_action";
const String _backTap = "back_tap";
const String _screenTitle = "Production plan";
const String _summaryTitle = "Plan summary";
const String _kpiTitle = "KPIs";
const String _phaseTitle = "Phase progress";
const String _tasksTitle = "Tasks";
const String _startLabel = "Start";
const String _endLabel = "End";
const String _assignedLabel = "Assigned";
const String _roleLabel = "Role";
const String _dueLabel = "Due";
const String _statusLabel = "Status";
const String _approvalPendingLabel = "Approval pending";
const String _approveLabel = "Approve";
const String _rejectLabel = "Reject";
const String _rejectionPrompt = "Reason for rejection";
const String _rejectionHint = "Add a short reason";
const String _rejectionSubmit = "Reject task";
const String _rejectionCancel = "Cancel";
const String _kpiTotalTasks = "Total tasks";
const String _kpiCompleted = "Completed";
const String _kpiOnTime = "On time";
const String _kpiAvgDelay = "Avg delay";
const String _phaseCompletionLabel = "Completion";
const String _kpiEmptyTitle = "No KPI data yet";
const String _kpiEmptyMessage =
    "KPI cards will appear once tasks are tracked.";
const String _phaseEmptyTitle = "No phase progress yet";
const String _phaseEmptyMessage =
    "Phase completion will appear once tasks are created.";
const String _phaseEmptyTasks = "No tasks in this phase yet.";
const String _approvalApprovedLabel = "Approved";
const String _approvalRejectedLabel = "Rejected";
const String _taskUpdateSuccess = "Task status updated.";
const String _taskUpdateFailure = "Unable to update task.";
const String _approveSuccess = "Task approved.";
const String _approveFailure = "Unable to approve task.";
const String _rejectSuccess = "Task rejected.";
const String _rejectFailure = "Unable to reject task.";
const String _extraPlanIdKey = "planId";
const String _extraTaskIdKey = "taskId";
const String _extraErrorKey = "error";
const String _ownerRole = "business_owner";
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

class ProductionPlanDetailScreen extends ConsumerWidget {
  final String planId;

  const ProductionPlanDetailScreen({
    super.key,
    required this.planId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage, extra: {_extraPlanIdKey: planId});
    final detailAsync = ref.watch(productionPlanDetailProvider(planId));
    final staffAsync = ref.watch(productionStaffProvider);
    final session = ref.watch(authSessionProvider);
    final isOwner = session?.user.role == _ownerRole;

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
          final _ = await ref.refresh(productionPlanDetailProvider(planId).future);
        },
        child: detailAsync.when(
          data: (detail) {
            final staffMap = _buildStaffMap(staffAsync.valueOrNull ?? []);
            return _PlanDetailBody(
              detail: detail,
              staffMap: staffMap,
              isOwner: isOwner,
              onStatusChange: (taskId, status) async {
                AppDebug.log(
                  _logTag,
                  _statusChangeAction,
                  extra: {_extraTaskIdKey: taskId, _extraPlanIdKey: planId},
                );
                try {
                  await ref.read(productionPlanActionsProvider).updateTaskStatus(
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
              onApprove: (taskId) async {
                AppDebug.log(
                  _logTag,
                  _approveAction,
                  extra: {_extraTaskIdKey: taskId, _extraPlanIdKey: planId},
                );
                try {
                  await ref.read(productionPlanActionsProvider).approveTask(
                        taskId: taskId,
                        planId: planId,
                      );
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
                  await ref.read(productionPlanActionsProvider).rejectTask(
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
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _PlanDetailBody({
    required this.detail,
    required this.staffMap,
    required this.isOwner,
    required this.onStatusChange,
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
        _PlanSummaryCard(plan: detail.plan),
        const SizedBox(height: _sectionSpacing),
        ProductionSectionHeader(title: _kpiTitle),
        const SizedBox(height: _cardSpacing),
        _KpiRow(kpis: detail.kpis),
        const SizedBox(height: _sectionSpacing),
        ProductionSectionHeader(title: _phaseTitle),
        const SizedBox(height: _cardSpacing),
        _PhaseProgressList(kpis: detail.kpis),
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
            onStatusChange: onStatusChange,
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

  const _PlanSummaryCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
        ProductionKpiCard(label: _kpiCompleted, value: "${kpis!.completedTasks}"),
        ProductionKpiCard(label: _kpiOnTime, value: onTime),
        ProductionKpiCard(label: _kpiAvgDelay, value: avgDelay),
        ProductionKpiCard(label: _phaseCompletionLabel, value: completion),
      ],
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
        final progressValue =
            phase.completionRate.clamp(_progressMin, _progressMax).toDouble();
        final percent = "${_formatPercent(phase.completionRate)}$_percentSuffix";
        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                phase.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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

class _PhaseTaskSection extends StatelessWidget {
  final ProductionPhase phase;
  final List<ProductionTask> tasks;
  final Map<String, BusinessStaffProfileSummary> staffMap;
  final bool isOwner;
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _PhaseTaskSection({
    required this.phase,
    required this.tasks,
    required this.staffMap,
    required this.isOwner,
    required this.onStatusChange,
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
                  onStatusChange: onStatusChange,
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
  final Future<void> Function(String taskId, String status) onStatusChange;
  final Future<void> Function(String taskId) onApprove;
  final Future<void> Function(String taskId, String reason) onReject;

  const _TaskCard({
    required this.task,
    required this.staffMap,
    required this.isOwner,
    required this.onStatusChange,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final staffName = staffMap[task.assignedStaffId]?.userName ??
        staffMap[task.assignedStaffId]?.userEmail ??
        task.assignedStaffId;

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
      value: currentStatus,
      decoration: const InputDecoration(
        labelText: _statusLabel,
        border: OutlineInputBorder(),
      ),
      // WHY: Status options mirror backend task statuses.
      items: _taskStatusOptions
          .map(
            (status) => DropdownMenuItem(
              value: status,
              child: Text(status),
            ),
          )
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
            child: const Text(_approveLabel),
          ),
          TextButton(
            onPressed: onReject,
            child: const Text(_rejectLabel),
          ),
        ],
      ),
    );
  }
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

String _formatPercent(double value) {
  final percent = (value * _percentMultiplier)
      .clamp(_percentMin, _percentMultiplier);
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

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
