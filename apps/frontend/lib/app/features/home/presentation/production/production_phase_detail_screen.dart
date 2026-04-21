library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_progress_proof_viewer.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _phaseScreenTitle = "Phase detail";
const String _phaseTasksTitle = "All tasks in this phase";
const String _phaseTasksSubtitle =
    "Every task scheduled under this phase, including dates, status, and saved activity.";
const String _phaseProofsTitle = "Completed work with proof";
const String _phaseProofsSubtitle =
    "Saved production activity rows in this phase that already carry proof files from the backend.";
const String _phaseRemainingTitle = "What is left";
const String _phaseRemainingSubtitle =
    "Tasks that still need work or an approved completion record in this phase.";
const String _phaseNotFoundTitle = "Phase not found";
const String _phaseNotFoundMessage =
    "The requested phase is not available in this production plan anymore.";
const String _phaseNoProofTitle = "No proof-backed work yet";
const String _phaseNoProofMessage =
    "Proof-backed progress will appear here once activity in this phase is logged and saved.";
const String _phaseNoOpenTasksTitle = "Nothing left in this phase";
const String _phaseNoOpenTasksMessage =
    "All tasks in this phase are already completed or have approved progress on the backend.";
const String _phaseNoTasksTitle = "No tasks in this phase";
const String _phaseNoTasksMessage =
    "This phase does not have any scheduled tasks yet.";
const String _phaseDoneLabel = "Done in phase";
const String _phaseLeftLabel = "Left in phase";
const String _phaseTotalLabel = "Total tasks";
const String _phaseProofTaskLabel = "Tasks with proof";
const String _phaseProofLogLabel = "Proof rows";
const String _phaseWindowLabel = "Window";
const String _phaseLastWorkLabel = "Last work";
const String _phaseStartLabel = "Start";
const String _phaseDueLabel = "Due";
const String _phaseCompletedLabel = "Completed";
const String _phaseLogsLabel = "Logs";
const String _phaseProofCountLabel = "Proofs";
const String _phaseActualLabel = "Actual";
const String _phaseApprovalLabel = "Approval";
const String _phaseStaffLabel = "Staff";
const String _phaseDateLabel = "Date";
const String _phaseTypeLabel = "Type";
const String _phaseTaskTypeLabel = "Task type";
const String _phaseHeadcountLabel = "Headcount";
const String _phaseInstructionsLabel = "Notes";
const String _phaseViewProofLabel = "View proof";
const String _phaseDash = "—";
const double _phasePagePadding = 16;
const double _phaseSectionSpacing = 18;
const double _phaseCardSpacing = 12;

class ProductionPhaseDetailScreen extends ConsumerWidget {
  final String planId;
  final String phaseId;

  const ProductionPhaseDetailScreen({
    super.key,
    required this.planId,
    required this.phaseId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(productionPlanDetailProvider(planId));

    return Scaffold(
      appBar: AppBar(
        title: const Text(_phaseScreenTitle),
        leading: IconButton(
          style: AppButtonStyles.icon(
            theme: Theme.of(context),
            tone: AppStatusTone.neutral,
          ),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlanInsightsPath(planId));
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
              ref.invalidate(productionPlanDetailProvider(planId));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(productionPlanDetailProvider(planId));
          await ref.read(productionPlanDetailProvider(planId).future);
        },
        child: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(_phasePagePadding),
              child: Text(error.toString()),
            ),
          ),
          data: (detail) {
            final phase = _findPhaseById(detail.phases, phaseId);
            if (phase == null) {
              return ListView(
                padding: const EdgeInsets.all(_phasePagePadding),
                children: const [
                  ProductionEmptyState(
                    title: _phaseNotFoundTitle,
                    message: _phaseNotFoundMessage,
                  ),
                ],
              );
            }

            final phaseTasks = _sortPhaseTasks(
              detail.tasks.where((task) => task.phaseId == phase.id).toList(),
            );
            final phaseKpi = _findPhaseKpi(detail.kpis, phase.id);
            final phaseTaskIds = phaseTasks.map((task) => task.id).toSet();
            final phaseRows = _sortTimelineRows(
              detail.timelineRows
                  .where((row) => phaseTaskIds.contains(row.taskId))
                  .toList(),
            );
            final proofRows = phaseRows
                .where((row) => row.proofs.isNotEmpty)
                .toList();
            final proofTaskCount = proofRows
                .map((row) => row.taskId)
                .toSet()
                .length;
            final scheduledStart = _resolvePhaseStart(phase, phaseTasks);
            final scheduledEnd = _resolvePhaseEnd(phase, phaseTasks);
            final taskActivityById = _buildTaskActivityById(phaseRows);
            final locallyCompletedTaskCount = phaseTasks.where((task) {
              final activity =
                  taskActivityById[task.id] ??
                  const _PhaseTaskActivitySummary.empty();
              return _isTaskClosed(task, activity);
            }).length;
            final openTasks = phaseTasks.where((task) {
              final activity =
                  taskActivityById[task.id] ??
                  const _PhaseTaskActivitySummary.empty();
              return !_isTaskClosed(task, activity);
            }).toList();
            final totalTasks = phaseKpi?.totalTasks ?? phaseTasks.length;
            final completedTasks =
                phaseKpi?.completedTasks ?? locallyCompletedTaskCount;
            final remainingTasks = totalTasks >= completedTasks
                ? totalTasks - completedTasks
                : openTasks.length;

            return ListView(
              padding: const EdgeInsets.all(_phasePagePadding),
              children: [
                _PhaseHeroCard(
                  planTitle: detail.plan.title,
                  phase: phase,
                  completedTasks: completedTasks,
                  totalTasks: totalTasks,
                  remainingTasks: remainingTasks,
                  scheduledStart: scheduledStart,
                  scheduledEnd: scheduledEnd,
                  proofRowCount: proofRows.length,
                ),
                const SizedBox(height: _phaseSectionSpacing),
                _PhaseSectionCard(
                  title: "Phase snapshot",
                  subtitle:
                      "Backend-driven counts for how much of ${phase.name} is done and how much is still left.",
                  child: Wrap(
                    spacing: _phaseCardSpacing,
                    runSpacing: _phaseCardSpacing,
                    children: [
                      ProductionKpiCard(
                        label: _phaseTotalLabel,
                        value: "$totalTasks",
                      ),
                      ProductionKpiCard(
                        label: _phaseDoneLabel,
                        value: "$completedTasks",
                        helper: phaseKpi == null
                            ? "Phase KPI is not available for this viewer."
                            : "${_formatPercent(phaseKpi.completionRate)}%",
                      ),
                      ProductionKpiCard(
                        label: _phaseLeftLabel,
                        value: "$remainingTasks",
                        helper: "Left according to backend phase progress.",
                      ),
                      ProductionKpiCard(
                        label: _phaseProofTaskLabel,
                        value: "$proofTaskCount",
                        helper: "Tasks in this phase with saved proof rows.",
                      ),
                      ProductionKpiCard(
                        label: _phaseProofLogLabel,
                        value: "${proofRows.length}",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: _phaseSectionSpacing),
                _PhaseSectionCard(
                  title: _phaseTasksTitle,
                  subtitle: _phaseTasksSubtitle,
                  child: phaseTasks.isEmpty
                      ? const ProductionEmptyState(
                          title: _phaseNoTasksTitle,
                          message: _phaseNoTasksMessage,
                        )
                      : Column(
                          children: phaseTasks.map((task) {
                            final activity =
                                taskActivityById[task.id] ??
                                const _PhaseTaskActivitySummary.empty();
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: _phaseCardSpacing,
                              ),
                              child: _PhaseTaskCard(
                                task: task,
                                activity: activity,
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: _phaseSectionSpacing),
                _PhaseSectionCard(
                  title: _phaseProofsTitle,
                  subtitle: _phaseProofsSubtitle,
                  child: proofRows.isEmpty
                      ? const ProductionEmptyState(
                          title: _phaseNoProofTitle,
                          message: _phaseNoProofMessage,
                        )
                      : Column(
                          children: proofRows.map((row) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: _phaseCardSpacing,
                              ),
                              child: _PhaseProofActivityCard(row: row),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: _phaseSectionSpacing),
                _PhaseSectionCard(
                  title: _phaseRemainingTitle,
                  subtitle: _phaseRemainingSubtitle,
                  child: openTasks.isEmpty
                      ? const ProductionEmptyState(
                          title: _phaseNoOpenTasksTitle,
                          message: _phaseNoOpenTasksMessage,
                        )
                      : Column(
                          children: openTasks.map((task) {
                            final activity =
                                taskActivityById[task.id] ??
                                const _PhaseTaskActivitySummary.empty();
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: _phaseCardSpacing,
                              ),
                              child: _PhaseTaskCard(
                                task: task,
                                activity: activity,
                                emphasizeRemaining: true,
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PhaseHeroCard extends StatelessWidget {
  final String planTitle;
  final ProductionPhase phase;
  final int completedTasks;
  final int totalTasks;
  final int remainingTasks;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final int proofRowCount;

  const _PhaseHeroCard({
    required this.planTitle,
    required this.phase,
    required this.completedTasks,
    required this.totalTasks,
    required this.remainingTasks,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.proofRowCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? 0.34 : 0.16),
            colorScheme.secondary.withValues(alpha: isDark ? 0.22 : 0.12),
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
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phase.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Review every task in ${phase.name}, inspect proof-backed work already completed, and see what is still left in this phase.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ProductionStatusPill(label: phase.status),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PhaseMetaChip(
                icon: Icons.category_outlined,
                label:
                    "$_phaseTypeLabel: ${formatProductionStatusLabel(phase.phaseType)}",
                tone: AppStatusTone.neutral,
              ),
              _PhaseMetaChip(
                icon: Icons.calendar_month_outlined,
                label:
                    "$_phaseWindowLabel: ${_formatWindow(scheduledStart, scheduledEnd)}",
                tone: AppStatusTone.info,
              ),
              _PhaseMetaChip(
                icon: Icons.task_alt_outlined,
                label: "$completedTasks of $totalTasks done",
                tone: AppStatusTone.success,
              ),
              _PhaseMetaChip(
                icon: Icons.pending_actions_outlined,
                label: "$remainingTasks left",
                tone: remainingTasks > 0
                    ? AppStatusTone.warning
                    : AppStatusTone.success,
              ),
              _PhaseMetaChip(
                icon: Icons.photo_library_outlined,
                label: "$proofRowCount proof row(s)",
                tone: AppStatusTone.info,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhaseSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _PhaseSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductionSectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PhaseTaskCard extends StatelessWidget {
  final ProductionTask task;
  final _PhaseTaskActivitySummary activity;
  final bool emphasizeRemaining;

  const _PhaseTaskCard({
    required this.task,
    required this.activity,
    this.emphasizeRemaining = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isClosed = _isTaskClosed(task, activity);
    final backgroundColor = emphasizeRemaining
        ? colorScheme.errorContainer.withValues(alpha: 0.24)
        : colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: emphasizeRemaining
              ? colorScheme.error.withValues(alpha: 0.22)
              : colorScheme.outlineVariant,
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
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PhaseMetaChip(
                          icon: Icons.play_arrow_outlined,
                          label:
                              "$_phaseStartLabel: ${_formatOptionalDate(task.startDate)}",
                          tone: AppStatusTone.info,
                        ),
                        _PhaseMetaChip(
                          icon: Icons.event_outlined,
                          label:
                              "$_phaseDueLabel: ${_formatOptionalDate(task.dueDate)}",
                          tone: AppStatusTone.warning,
                        ),
                        _PhaseMetaChip(
                          icon: Icons.check_circle_outline,
                          label:
                              "$_phaseCompletedLabel: ${_formatOptionalDate(task.completedAt)}",
                          tone: isClosed
                              ? AppStatusTone.success
                              : AppStatusTone.neutral,
                        ),
                        _PhaseMetaChip(
                          icon: Icons.verified_outlined,
                          label:
                              "$_phaseApprovalLabel: ${_formatTaskApproval(task, activity)}",
                          tone: _taskApprovalTone(task, activity),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ProductionStatusPill(label: isClosed ? "completed" : task.status),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PhaseStatChip(
                label: _phaseTaskTypeLabel,
                value: formatProductionStatusLabel(task.taskType),
              ),
              _PhaseStatChip(
                label: _phaseHeadcountLabel,
                value: "${task.assignedCount}/${task.requiredHeadcount}",
              ),
              _PhaseStatChip(
                label: _phaseLogsLabel,
                value: "${activity.logCount}",
              ),
              _PhaseStatChip(
                label: _phaseProofCountLabel,
                value: "${activity.proofCount}",
              ),
              _PhaseStatChip(
                label: _phaseActualLabel,
                value: "${activity.actualTotal}",
              ),
              _PhaseStatChip(
                label: _phaseLastWorkLabel,
                value: _formatOptionalDate(activity.lastWorkDate),
              ),
            ],
          ),
          if (task.instructions.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              "$_phaseInstructionsLabel: ${task.instructions.trim()}",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhaseProofActivityCard extends StatelessWidget {
  final ProductionTimelineRow row;

  const _PhaseProofActivityCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
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
                      row.taskTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PhaseMetaChip(
                          icon: Icons.event_note_outlined,
                          label:
                              "$_phaseDateLabel: ${_formatOptionalDate(row.workDate)}",
                          tone: AppStatusTone.info,
                        ),
                        _PhaseMetaChip(
                          icon: Icons.person_outline,
                          label:
                              "$_phaseStaffLabel: ${row.farmerName.trim().isEmpty ? _phaseDash : row.farmerName.trim()}",
                          tone: AppStatusTone.neutral,
                        ),
                        _PhaseMetaChip(
                          icon: Icons.verified_outlined,
                          label:
                              "$_phaseApprovalLabel: ${_formatApprovalState(row.approvalState)}",
                          tone: _approvalTone(row.approvalState),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ProductionStatusPill(
                label: row.status.trim().isEmpty ? "completed" : row.status,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PhaseStatChip(
                label: _phaseActualLabel,
                value: "${row.actualPlots}",
              ),
              _PhaseStatChip(
                label: _phaseProofCountLabel,
                value: "${row.proofCount}",
              ),
              if (row.delayReason.trim().isNotEmpty)
                _PhaseStatChip(
                  label: "Delay",
                  value: formatProductionStatusLabel(row.delayReason),
                ),
            ],
          ),
          if (row.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              row.notes.trim(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: row.proofs.asMap().entries.map((entry) {
              final proof = entry.value;
              final proofLabel = proof.filename.trim().isNotEmpty
                  ? proof.filename.trim()
                  : "$_phaseViewProofLabel ${entry.key + 1}";
              final proofColors = _badgeColors(
                context,
                proof.hasUrl ? AppStatusTone.info : AppStatusTone.neutral,
              );
              return ActionChip(
                avatar: Icon(
                  Icons.photo_library_outlined,
                  size: 18,
                  color: proofColors.foreground,
                ),
                backgroundColor: proofColors.background,
                side: BorderSide(
                  color: proofColors.foreground.withValues(alpha: 0.18),
                ),
                labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: proofColors.foreground,
                  fontWeight: FontWeight.w600,
                ),
                label: Text(proofLabel),
                onPressed: proof.hasUrl
                    ? () {
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
      ),
    );
  }
}

class _PhaseMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusTone tone;

  const _PhaseMetaChip({
    required this.icon,
    required this.label,
    this.tone = AppStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeColors = _badgeColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone == AppStatusTone.neutral
            ? colorScheme.surface.withValues(alpha: 0.7)
            : badgeColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tone == AppStatusTone.neutral
              ? colorScheme.outlineVariant
              : badgeColors.foreground.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: tone == AppStatusTone.neutral
                ? colorScheme.primary
                : badgeColors.foreground,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tone == AppStatusTone.neutral
                  ? colorScheme.onSurface
                  : badgeColors.foreground,
              fontWeight: tone == AppStatusTone.neutral
                  ? FontWeight.w500
                  : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseStatChip extends StatelessWidget {
  final String label;
  final String value;

  const _PhaseStatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
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
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PhaseTaskActivitySummary {
  final int logCount;
  final int proofCount;
  final num actualTotal;
  final DateTime? lastWorkDate;
  final bool hasApprovedProgress;

  const _PhaseTaskActivitySummary({
    required this.logCount,
    required this.proofCount,
    required this.actualTotal,
    required this.lastWorkDate,
    required this.hasApprovedProgress,
  });

  const _PhaseTaskActivitySummary.empty()
    : logCount = 0,
      proofCount = 0,
      actualTotal = 0,
      lastWorkDate = null,
      hasApprovedProgress = false;
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

ProductionPhaseKpi? _findPhaseKpi(ProductionKpis? kpis, String phaseId) {
  final normalizedPhaseId = phaseId.trim();
  if (kpis == null) {
    return null;
  }
  for (final phase in kpis.phaseCompletion) {
    if (phase.phaseId == normalizedPhaseId) {
      return phase;
    }
  }
  return null;
}

List<ProductionTask> _sortPhaseTasks(List<ProductionTask> tasks) {
  tasks.sort((left, right) {
    final leftStart = left.startDate ?? left.dueDate;
    final rightStart = right.startDate ?? right.dueDate;
    final startCompare = _compareDate(leftStart, rightStart);
    if (startCompare != 0) {
      return startCompare;
    }
    final dueCompare = _compareDate(left.dueDate, right.dueDate);
    if (dueCompare != 0) {
      return dueCompare;
    }
    final manualCompare = left.manualSortOrder.compareTo(right.manualSortOrder);
    if (manualCompare != 0) {
      return manualCompare;
    }
    return left.title.toLowerCase().compareTo(right.title.toLowerCase());
  });
  return tasks;
}

List<ProductionTimelineRow> _sortTimelineRows(
  List<ProductionTimelineRow> rows,
) {
  rows.sort((left, right) {
    final dateCompare = _compareDate(right.workDate, left.workDate);
    if (dateCompare != 0) {
      return dateCompare;
    }
    final entryCompare = right.entryIndex.compareTo(left.entryIndex);
    if (entryCompare != 0) {
      return entryCompare;
    }
    return left.taskTitle.toLowerCase().compareTo(
      right.taskTitle.toLowerCase(),
    );
  });
  return rows;
}

Map<String, _PhaseTaskActivitySummary> _buildTaskActivityById(
  List<ProductionTimelineRow> rows,
) {
  final summaries = <String, _PhaseTaskActivitySummary>{};
  final logCountByTaskId = <String, int>{};
  final proofCountByTaskId = <String, int>{};
  final actualByTaskId = <String, num>{};
  final lastWorkByTaskId = <String, DateTime?>{};
  final hasApprovedProgressByTaskId = <String, bool>{};

  for (final row in rows) {
    final taskId = row.taskId.trim();
    if (taskId.isEmpty) {
      continue;
    }
    logCountByTaskId[taskId] = (logCountByTaskId[taskId] ?? 0) + 1;
    proofCountByTaskId[taskId] =
        (proofCountByTaskId[taskId] ?? 0) + row.proofCount;
    actualByTaskId[taskId] = (actualByTaskId[taskId] ?? 0) + row.actualPlots;
    final currentLast = lastWorkByTaskId[taskId];
    if (currentLast == null ||
        (row.workDate != null && row.workDate!.isAfter(currentLast))) {
      lastWorkByTaskId[taskId] = row.workDate;
    }
    if (_isApprovedProgressRow(row)) {
      hasApprovedProgressByTaskId[taskId] = true;
    }
  }

  for (final taskId in logCountByTaskId.keys) {
    summaries[taskId] = _PhaseTaskActivitySummary(
      logCount: logCountByTaskId[taskId] ?? 0,
      proofCount: proofCountByTaskId[taskId] ?? 0,
      actualTotal: actualByTaskId[taskId] ?? 0,
      lastWorkDate: lastWorkByTaskId[taskId],
      hasApprovedProgress: hasApprovedProgressByTaskId[taskId] ?? false,
    );
  }
  return summaries;
}

bool _isTaskClosed(ProductionTask task, [_PhaseTaskActivitySummary? activity]) {
  final normalizedStatus = task.status.trim().toLowerCase();
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  return normalizedStatus == "done" ||
      task.completedAt != null ||
      normalizedApproval == "approved" ||
      (activity?.hasApprovedProgress ?? false);
}

DateTime? _resolvePhaseStart(
  ProductionPhase phase,
  List<ProductionTask> tasks,
) {
  DateTime? value = phase.startDate;
  for (final task in tasks) {
    final candidate = task.startDate ?? task.dueDate;
    if (candidate == null) {
      continue;
    }
    if (value == null || candidate.isBefore(value)) {
      value = candidate;
    }
  }
  return value;
}

DateTime? _resolvePhaseEnd(ProductionPhase phase, List<ProductionTask> tasks) {
  DateTime? value = phase.endDate;
  for (final task in tasks) {
    final candidate = task.dueDate ?? task.startDate;
    if (candidate == null) {
      continue;
    }
    if (value == null || candidate.isAfter(value)) {
      value = candidate;
    }
  }
  return value;
}

String _formatWindow(DateTime? start, DateTime? end) {
  final startLabel = _formatOptionalDate(start);
  final endLabel = _formatOptionalDate(end);
  if (start == null && end == null) {
    return _phaseDash;
  }
  return "$startLabel → $endLabel";
}

String _formatOptionalDate(DateTime? value) {
  return value == null ? _phaseDash : formatDateLabel(value);
}

String _formatApprovalState(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return _phaseDash;
  }
  return formatProductionStatusLabel(trimmed);
}

String _formatTaskApproval(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
) {
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  if (activity.hasApprovedProgress || normalizedApproval == "approved") {
    return "Approved";
  }
  if (normalizedApproval == "rejected") {
    return "Rejected";
  }
  if (activity.logCount > 0 || normalizedApproval == "pending_approval") {
    return "Pending approval";
  }
  return "Open";
}

AppStatusTone _taskApprovalTone(
  ProductionTask task,
  _PhaseTaskActivitySummary activity,
) {
  final normalizedApproval = task.approvalStatus.trim().toLowerCase();
  if (activity.hasApprovedProgress || normalizedApproval == "approved") {
    return AppStatusTone.success;
  }
  if (normalizedApproval == "rejected") {
    return AppStatusTone.danger;
  }
  if (activity.logCount > 0 || normalizedApproval == "pending_approval") {
    return AppStatusTone.warning;
  }
  return AppStatusTone.neutral;
}

AppStatusTone _approvalTone(String approvalState) {
  switch (approvalState.trim().toLowerCase()) {
    case "approved":
      return AppStatusTone.success;
    case "needs_review":
    case "pending_approval":
      return AppStatusTone.warning;
    case "rejected":
      return AppStatusTone.danger;
    default:
      return AppStatusTone.neutral;
  }
}

bool _isApprovedProgressRow(ProductionTimelineRow row) {
  final normalizedApproval = row.approvalState.trim().toLowerCase();
  return normalizedApproval == "approved" || row.approvedAt != null;
}

AppStatusBadgeColors _badgeColors(BuildContext context, AppStatusTone tone) {
  return AppStatusBadgeColors.fromTheme(theme: Theme.of(context), tone: tone);
}

String _formatPercent(double value) {
  return (value * 100).round().toString();
}

int _compareDate(DateTime? left, DateTime? right) {
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
