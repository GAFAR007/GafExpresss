/// lib/app/features/home/presentation/production/production_task_detail_screen.dart
/// ------------------------------------------------------------------------------
/// WHAT:
/// - Shows one production task with compact operational detail and recent work.
///
/// WHY:
/// - Phase dashboard rows should open a focused task page so managers can inspect
///   approval, proof, output, and recency without digging through the full plan.
///
/// HOW:
/// - Reuses the plan detail payload, derives one task summary, and renders a
///   concise header, KPI strip, metadata blocks, and activity history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_viewer.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _logTag = "PRODUCTION_TASK_DETAIL";
const String _buildLog = "build()";
const String _proofTapAction = "openProofPreview()";

const String _screenTitle = "Task detail";
const String _notFoundTitle = "Task not found";
const String _notFoundMessage =
    "The requested task is no longer available in this production plan.";
const String _activityEmptyTitle = "No activity yet";
const String _activityEmptyMessage =
    "Progress logs, proof uploads, and approval updates will appear here after work starts.";
const String _dash = "—";
const String _unassigned = "Unassigned";
const String _noProof = "No proof";
const String _noActivity = "No activity yet";
const String _notCompleted = "Not completed";
const String _overviewTitle = "Task snapshot";
const String _overviewSubtitle =
    "Daily truth for progress, proof, output, and assignment coverage.";
const String _metaTitle = "Task setup";
const String _metaSubtitle =
    "Operational context for dates, ownership, approval, and scope.";
const String _historyTitle = "Activity history";
const String _historySubtitle =
    "Recent work rows, proof attachments, and approval outcomes for this task.";
const double _pagePadding = 16;
const double _sectionSpacing = 16;

class ProductionTaskDetailScreen extends ConsumerWidget {
  final String planId;
  final String taskId;

  const ProductionTaskDetailScreen({
    super.key,
    required this.planId,
    required this.taskId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(
      _logTag,
      _buildLog,
      extra: {"planId": planId, "taskId": taskId},
    );
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          style: AppButtonStyles.icon(
            theme: theme,
            tone: AppStatusTone.neutral,
          ),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlanDetailPath(planId));
          },
        ),
      ),
      body: displayDetailAsync.when(
        skipError: cachedDetail != null,
        skipLoadingOnReload: true,
        loading: () => const ProductionLoadingState(),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(_pagePadding),
          children: [Text(error.toString())],
        ),
        data: (detail) {
          final task = _findTaskById(detail.tasks, taskId);
          if (task == null) {
            return ProductionRefreshOverlay(
              isRefreshing: isRefreshingDetail,
              child: ListView(
                padding: const EdgeInsets.all(_pagePadding),
                children: const [
                  ProductionEmptyState(
                    title: _notFoundTitle,
                    message: _notFoundMessage,
                  ),
                ],
              ),
            );
          }

          final phase = _findPhaseById(detail.phases, task.phaseId);
          final staffById = _buildStaffMap(detail.staffProfiles);
          final rows = _sortRows(
            detail.timelineRows.where((row) => row.taskId == task.id).toList(),
          );
          final activity = _buildTaskActivity(rows);
          final assigneeLabel = _buildAssignedStaffLabel(task, staffById);
          final approvalLabel = _taskApprovalLabel(task, activity);
          final approvalTone = _taskApprovalTone(task, activity);
          final taskStatus = _deriveTaskStatus(task, activity);
          final progressPercent =
              "${(taskStatus.progressValue * 100).round()}%";

          return ProductionRefreshOverlay(
            isRefreshing: isRefreshingDetail,
            child: ListView(
              padding: const EdgeInsets.all(_pagePadding),
              children: [
                _TaskHero(
                  task: task,
                  phaseName: phase?.name ?? _dash,
                  planTitle: detail.plan.title,
                  assigneeLabel: assigneeLabel,
                  approvalLabel: approvalLabel,
                  approvalTone: approvalTone,
                  taskStatus: taskStatus,
                ),
                const SizedBox(height: _sectionSpacing),
                _TaskOverviewSection(
                  rowsLogged: activity.logCount,
                  proofCount: activity.proofCount,
                  actualTotal: activity.actualTotal,
                  lastWorkDate: activity.lastWorkDate,
                  headcountLabel:
                      "${task.assignedCount}/${task.requiredHeadcount}",
                  progressPercent: progressPercent,
                  progressTone: taskStatus.tone,
                ),
                const SizedBox(height: _sectionSpacing),
                _TaskMetaSection(
                  task: task,
                  phaseName: phase?.name ?? _dash,
                  assigneeLabel: assigneeLabel,
                  approvalLabel: approvalLabel,
                  approvalTone: approvalTone,
                ),
                const SizedBox(height: _sectionSpacing),
                _TaskHistorySection(rows: rows),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TaskHero extends StatelessWidget {
  final ProductionTask task;
  final String phaseName;
  final String planTitle;
  final String assigneeLabel;
  final String approvalLabel;
  final AppStatusTone approvalTone;
  final _DerivedTaskStatus taskStatus;

  const _TaskHero({
    required this.task,
    required this.phaseName,
    required this.planTitle,
    required this.assigneeLabel,
    required this.approvalLabel,
    required this.approvalTone,
    required this.taskStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerLow,
            colorScheme.primary.withValues(alpha: isDark ? 0.14 : 0.08),
            colorScheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planTitle.trim().isEmpty ? "Untitled production plan" : planTitle,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title.trim().isEmpty ? "Untitled task" : task.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      task.instructions.trim().isEmpty
                          ? "Inspect the latest execution truth, proof coverage, and approval state for this scheduled task."
                          : task.instructions.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroChip(
                icon: Icons.layers_outlined,
                label: "Phase: $phaseName",
                tone: AppStatusTone.info,
              ),
              _HeroChip(
                icon: Icons.person_outline,
                label: "Assignee: $assigneeLabel",
                tone: AppStatusTone.neutral,
              ),
              _HeroChip(
                icon: Icons.verified_outlined,
                label: "Approval: $approvalLabel",
                tone: approvalTone,
              ),
              _HeroChip(
                icon: Icons.speed_outlined,
                label: "Status: ${taskStatus.label}",
                tone: taskStatus.tone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusTone tone;

  const _HeroChip({
    required this.icon,
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: tone,
    );
    final usesTone = tone != AppStatusTone.neutral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: usesTone ? badgeColors.background : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: usesTone
              ? badgeColors.foreground.withValues(alpha: 0.18)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: usesTone
                ? badgeColors.foreground
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: usesTone
                  ? badgeColors.foreground
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskOverviewSection extends StatelessWidget {
  final int rowsLogged;
  final int proofCount;
  final num actualTotal;
  final DateTime? lastWorkDate;
  final String headcountLabel;
  final String progressPercent;
  final AppStatusTone progressTone;

  const _TaskOverviewSection({
    required this.rowsLogged,
    required this.proofCount,
    required this.actualTotal,
    required this.lastWorkDate,
    required this.headcountLabel,
    required this.progressPercent,
    required this.progressTone,
  });

  @override
  Widget build(BuildContext context) {
    final stats = <_OverviewTileData>[
      _OverviewTileData(
        label: "Rows logged",
        value: rowsLogged.toString(),
        icon: Icons.list_alt_rounded,
        tone: rowsLogged > 0 ? AppStatusTone.info : AppStatusTone.neutral,
      ),
      _OverviewTileData(
        label: "Proofs",
        value: proofCount <= 0 ? _noProof : proofCount.toString(),
        icon: Icons.photo_library_outlined,
        tone: proofCount > 0 ? AppStatusTone.info : AppStatusTone.neutral,
      ),
      _OverviewTileData(
        label: "Actual output",
        value: _formatActualValue(actualTotal, hasData: rowsLogged > 0),
        icon: Icons.equalizer_outlined,
        tone: actualTotal > 0 ? AppStatusTone.success : AppStatusTone.neutral,
      ),
      _OverviewTileData(
        label: "Last work",
        value: lastWorkDate == null
            ? _noActivity
            : formatDateLabel(lastWorkDate),
        icon: Icons.event_note_outlined,
        tone: lastWorkDate != null ? AppStatusTone.info : AppStatusTone.neutral,
      ),
      _OverviewTileData(
        label: "Headcount",
        value: headcountLabel,
        icon: Icons.groups_outlined,
        tone: AppStatusTone.neutral,
      ),
      _OverviewTileData(
        label: "Progress",
        value: progressPercent,
        icon: Icons.insights_outlined,
        tone: progressTone,
        emphasize: true,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProductionSectionHeader(
          title: _overviewTitle,
          subtitle: _overviewSubtitle,
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            // WHY: Tiles need enough height for empty-state values like
            // "No activity yet" without clipping on desktop or tablet widths.
            mainAxisExtent: 156,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: stats.length,
          itemBuilder: (context, index) {
            return _OverviewTile(data: stats[index]);
          },
        ),
      ],
    );
  }
}

class _OverviewTileData {
  final String label;
  final String value;
  final IconData icon;
  final AppStatusTone tone;
  final bool emphasize;

  const _OverviewTileData({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.emphasize = false,
  });
}

class _OverviewTile extends StatelessWidget {
  final _OverviewTileData data;

  const _OverviewTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: data.tone,
    );
    final usesTone = data.tone != AppStatusTone.neutral;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: data.emphasize
            ? badgeColors.background
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: data.emphasize
              ? badgeColors.foreground.withValues(alpha: 0.22)
              : usesTone
              ? badgeColors.foreground.withValues(alpha: 0.12)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                data.icon,
                size: 16,
                color: data.emphasize
                    ? badgeColors.foreground
                    : usesTone
                    ? badgeColors.foreground
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: data.emphasize
                        ? badgeColors.foreground
                        : usesTone
                        ? badgeColors.foreground
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            data.value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: data.emphasize
                  ? badgeColors.foreground
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskMetaSection extends StatelessWidget {
  final ProductionTask task;
  final String phaseName;
  final String assigneeLabel;
  final String approvalLabel;
  final AppStatusTone approvalTone;

  const _TaskMetaSection({
    required this.task,
    required this.phaseName,
    required this.assigneeLabel,
    required this.approvalLabel,
    required this.approvalTone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProductionSectionHeader(
            title: _metaTitle,
            subtitle: _metaSubtitle,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 14,
            children: [
              _MetaField(label: "Phase", value: phaseName),
              _MetaField(
                label: "Task type",
                value: task.taskType.trim().isEmpty
                    ? _dash
                    : formatProductionStatusLabel(task.taskType),
              ),
              _MetaField(
                label: "Role",
                value: task.roleRequired.trim().isEmpty
                    ? _dash
                    : formatProductionStatusLabel(task.roleRequired),
              ),
              _MetaField(label: "Assignee", value: assigneeLabel),
              _MetaField(
                label: "Start",
                value: _formatOptionalDate(task.startDate),
              ),
              _MetaField(
                label: "Due",
                value: _formatOptionalDate(task.dueDate),
              ),
              _MetaField(
                label: "Completed",
                value: task.completedAt == null
                    ? _notCompleted
                    : formatDateLabel(task.completedAt),
              ),
              _MetaField(
                label: "Approval",
                value: approvalLabel,
                tone: approvalTone,
              ),
              _MetaField(
                label: "Dependencies",
                value: task.dependencies.isEmpty
                    ? _dash
                    : task.dependencies.join(", "),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaField extends StatelessWidget {
  final String label;
  final String value;
  final AppStatusTone? tone;

  const _MetaField({required this.label, required this.value, this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final badgeColors = tone == null
        ? null
        : AppStatusBadgeColors.fromTheme(theme: theme, tone: tone!);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          if (badgeColors == null)
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColors.background,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: badgeColors.foreground.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                value,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: badgeColors.foreground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskHistorySection extends StatelessWidget {
  final List<ProductionTimelineRow> rows;

  const _TaskHistorySection({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProductionSectionHeader(
          title: _historyTitle,
          subtitle: _historySubtitle,
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const ProductionEmptyState(
            title: _activityEmptyTitle,
            message: _activityEmptyMessage,
          )
        else
          Column(
            children: rows.map((row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActivityRowCard(row: row),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _ActivityRowCard extends StatelessWidget {
  final ProductionTimelineRow row;

  const _ActivityRowCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final approvalTone = _approvalTone(row.approvalState);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
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
                      row.workDate == null
                          ? "Unscheduled activity"
                          : formatDateLabel(row.workDate),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.farmerName.trim().isEmpty
                          ? _unassigned
                          : row.farmerName.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ProductionStatusPill(label: row.status),
                  const SizedBox(height: 8),
                  _ApprovalBadge(
                    label: _approvalLabel(row.approvalState),
                    tone: approvalTone,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InlineMetric(
                label: "Actual",
                value: _formatActualValue(row.actualPlots, hasData: true),
              ),
              _InlineMetric(
                label: "Proofs",
                value: row.proofCount <= 0
                    ? _noProof
                    : row.proofCount.toString(),
              ),
              _InlineMetric(
                label: "Session",
                value: row.sessionStatus.trim().isEmpty
                    ? _dash
                    : formatProductionStatusLabel(row.sessionStatus),
              ),
            ],
          ),
          if (row.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              row.notes.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (row.proofs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: row.proofs.asMap().entries.map((entry) {
                final proof = entry.value;
                final proofLabel = proof.filename.trim().isNotEmpty
                    ? proof.filename.trim()
                    : "Proof ${entry.key + 1}";
                return ActionChip(
                  avatar: Icon(
                    Icons.photo_library_outlined,
                    size: 18,
                    color: AppColors.analyticsAccent,
                  ),
                  label: Text(proofLabel),
                  onPressed: proof.hasUrl
                      ? () {
                          AppDebug.log(
                            _logTag,
                            _proofTapAction,
                            extra: {"rowId": row.id, "proofLabel": proofLabel},
                          );
                          showProductionTaskProgressSavedProofPreview(
                            context,
                            title: proofLabel,
                            proof: proof,
                          );
                        }
                      : null,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  final String label;
  final String value;

  const _InlineMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(text: "$label: "),
            TextSpan(
              text: value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalBadge extends StatelessWidget {
  final String label;
  final AppStatusTone tone;

  const _ApprovalBadge({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: tone,
    );

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
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: badgeColors.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

ProductionTask? _findTaskById(List<ProductionTask> tasks, String taskId) {
  final normalizedTaskId = taskId.trim();
  for (final task in tasks) {
    if (task.id == normalizedTaskId) {
      return task;
    }
  }
  return null;
}

ProductionPhase? _findPhaseById(List<ProductionPhase> phases, String phaseId) {
  final normalizedPhaseId = phaseId.trim();
  for (final phase in phases) {
    if (phase.id == normalizedPhaseId) {
      return phase;
    }
  }
  return null;
}

Map<String, BusinessStaffProfileSummary> _buildStaffMap(
  List<BusinessStaffProfileSummary> staffProfiles,
) {
  return <String, BusinessStaffProfileSummary>{
    for (final staff in staffProfiles) staff.id: staff,
  };
}

String _buildAssignedStaffLabel(
  ProductionTask task,
  Map<String, BusinessStaffProfileSummary> staffById,
) {
  final assignedStaffIds = task.assignedStaffIds
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
  if (assignedStaffIds.isEmpty && task.assignedStaffId.trim().isNotEmpty) {
    assignedStaffIds.add(task.assignedStaffId.trim());
  }
  if (assignedStaffIds.isEmpty) {
    return _unassigned;
  }
  final labels = assignedStaffIds.map((staffId) {
    final profile = staffById[staffId];
    return profile?.userName?.trim().isNotEmpty == true
        ? profile!.userName!.trim()
        : profile?.userEmail?.trim().isNotEmpty == true
        ? profile!.userEmail!.trim()
        : staffId;
  }).toList();
  return labels.join(", ");
}

List<ProductionTimelineRow> _sortRows(List<ProductionTimelineRow> rows) {
  rows.sort((left, right) {
    final dateCompare = _compareNullableDateDesc(left.workDate, right.workDate);
    if (dateCompare != 0) {
      return dateCompare;
    }
    return right.entryIndex.compareTo(left.entryIndex);
  });
  return rows;
}

_TaskActivity _buildTaskActivity(List<ProductionTimelineRow> rows) {
  var proofCount = 0;
  num actualTotal = 0;
  DateTime? lastWorkDate;
  var hasApprovedProgress = false;

  for (final row in rows) {
    proofCount += row.proofCount;
    actualTotal += row.actualPlots;
    if (lastWorkDate == null ||
        (row.workDate != null && row.workDate!.isAfter(lastWorkDate))) {
      lastWorkDate = row.workDate;
    }
    if (_isApprovedRow(row)) {
      hasApprovedProgress = true;
    }
  }

  return _TaskActivity(
    logCount: rows.length,
    proofCount: proofCount,
    actualTotal: actualTotal,
    lastWorkDate: lastWorkDate,
    hasApprovedProgress: hasApprovedProgress,
  );
}

class _TaskActivity {
  final int logCount;
  final int proofCount;
  final num actualTotal;
  final DateTime? lastWorkDate;
  final bool hasApprovedProgress;

  const _TaskActivity({
    required this.logCount,
    required this.proofCount,
    required this.actualTotal,
    required this.lastWorkDate,
    required this.hasApprovedProgress,
  });
}

String _taskApprovalLabel(ProductionTask task, _TaskActivity activity) {
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  // WHY: Assignment approval means the task can proceed. It does not mean the
  // work itself was completed or approved.
  if (activity.hasApprovedProgress) {
    return "Approved";
  }
  if (activity.logCount > 0) {
    return "Pending progress approval";
  }
  if (normalizedApproval == "rejected") {
    return "Assignment rejected";
  }
  if (normalizedApproval == "pending_approval") {
    return "Assignment pending";
  }
  if (normalizedApproval == "approved") {
    return "Assignment approved";
  }
  return "Open";
}

AppStatusTone _taskApprovalTone(ProductionTask task, _TaskActivity activity) {
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  if (activity.hasApprovedProgress) {
    return AppStatusTone.success;
  }
  if (activity.logCount > 0) {
    return AppStatusTone.warning;
  }
  if (normalizedApproval == "rejected") {
    return AppStatusTone.danger;
  }
  if (normalizedApproval == "pending_approval") {
    return AppStatusTone.warning;
  }
  if (normalizedApproval == "approved") {
    return AppStatusTone.info;
  }
  return AppStatusTone.neutral;
}

_DerivedTaskStatus _deriveTaskStatus(
  ProductionTask task,
  _TaskActivity activity,
) {
  final normalizedStatus = task.status.trim().toLowerCase();
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  final hasProgress =
      activity.logCount > 0 ||
      activity.proofCount > 0 ||
      activity.actualTotal > 0;
  final isClosed =
      normalizedStatus == "done" ||
      task.completedAt != null ||
      activity.hasApprovedProgress;

  if (normalizedStatus == "blocked" ||
      normalizedStatus == "failed" ||
      normalizedStatus == "delayed" ||
      normalizedStatus == "overdue" ||
      normalizedApproval == "rejected") {
    return const _DerivedTaskStatus(
      label: "Blocked",
      tone: AppStatusTone.danger,
      progressValue: 0.28,
    );
  }
  if (isClosed) {
    return const _DerivedTaskStatus(
      label: "Completed",
      tone: AppStatusTone.success,
      progressValue: 1,
    );
  }
  if (normalizedStatus == "in_progress" ||
      normalizedStatus == "active" ||
      normalizedStatus == "clocked_in" ||
      hasProgress) {
    return const _DerivedTaskStatus(
      label: "In progress",
      tone: AppStatusTone.warning,
      progressValue: 0.56,
    );
  }
  return const _DerivedTaskStatus(
    label: "Assigned",
    tone: AppStatusTone.neutral,
    progressValue: 0,
  );
}

class _DerivedTaskStatus {
  final String label;
  final AppStatusTone tone;
  final double progressValue;

  const _DerivedTaskStatus({
    required this.label,
    required this.tone,
    required this.progressValue,
  });
}

bool _isApprovedRow(ProductionTimelineRow row) {
  final normalized = row.approvalState.trim().toLowerCase();
  return normalized == "approved" || row.approvedAt != null;
}

String _approvalLabel(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return "Open";
  }
  return formatProductionStatusLabel(trimmed);
}

AppStatusTone _approvalTone(String rawValue) {
  switch (rawValue.trim().toLowerCase()) {
    case "approved":
      return AppStatusTone.success;
    case "rejected":
      return AppStatusTone.danger;
    case "pending_approval":
    case "needs_review":
      return AppStatusTone.warning;
    default:
      return AppStatusTone.neutral;
  }
}

String _formatOptionalDate(DateTime? value) {
  return value == null ? _dash : formatDateLabel(value);
}

String _formatActualValue(num value, {required bool hasData}) {
  if (!hasData && value <= 0) {
    return _dash;
  }
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

int _compareNullableDateDesc(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return right.compareTo(left);
}
