/// lib/app/features/home/presentation/production/production_stats_screen.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Simple production statistics screen.
///
/// WHY:
/// - Managers need a lightweight overview without opening the production
///   workspace or a specific plan.
///
/// HOW:
/// - Reads existing production plan and portfolio confidence providers.
/// - Groups plans by lifecycle status and renders compact summary cards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';

const String _logTag = "PRODUCTION_STATS";
const String _buildMessage = "build()";
const String _refreshAction = "refresh_stats";
const String _screenTitle = "Production stats";
const String _refreshTooltip = "Refresh";
const String _overviewTitle = "Overview";
const String _statusTitle = "Plans by status";
const String _confidenceTitle = "Portfolio confidence";
const String _recentPlansTitle = "Recent plans";
const String _emptyTitle = "No production stats yet";
const String _emptyMessage = "Create production plans to populate stats.";
const String _totalPlansLabel = "Total plans";
const String _activePlansLabel = "Active";
const String _draftPlansLabel = "Draft";
const String _pausedPlansLabel = "Paused";
const String _completedPlansLabel = "Completed";
const String _archivedPlansLabel = "Archived";
const String _revisionsLabel = "Revisions";
const String _currentLabel = "Current";
const String _baselineLabel = "Baseline";
const String _deltaLabel = "Delta";
const String _weightedUnitsLabel = "Weighted units";
const String _statusActive = "active";
const String _statusDraft = "draft";
const String _statusPaused = "paused";
const String _statusCompleted = "completed";
const String _statusArchived = "archived";
const double _pagePadding = 16;
const double _cardPadding = 16;
const double _cardRadius = 16;
const double _cardSpacing = 12;
const double _gridGap = 12;

class ProductionStatsScreen extends ConsumerWidget {
  const ProductionStatsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    AppDebug.log(_logTag, _refreshAction);
    ref.invalidate(productionPortfolioConfidenceProvider(null));
    final _ = await ref.refresh(productionPlansProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage);
    final plansAsync = ref.watch(productionPlansProvider);
    final confidenceAsync = ref.watch(
      productionPortfolioConfidenceProvider(null),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        actions: [
          IconButton(
            onPressed: () => _refresh(ref),
            icon: const Icon(Icons.refresh),
            tooltip: _refreshTooltip,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: plansAsync.when(
          data: (plans) {
            if (plans.isEmpty) {
              return const _MessageList(
                icon: Icons.query_stats_outlined,
                title: _emptyTitle,
                message: _emptyMessage,
              );
            }
            final stats = _ProductionStats.fromPlans(plans);
            final confidence = confidenceAsync.valueOrNull?.summary;
            return ListView(
              padding: const EdgeInsets.all(_pagePadding),
              children: [
                _SectionTitle(title: _overviewTitle),
                _ResponsiveStatGrid(
                  stats: [
                    _StatItem(
                      icon: Icons.inventory_2_outlined,
                      label: _totalPlansLabel,
                      value: "${stats.totalPlans}",
                    ),
                    _StatItem(
                      icon: Icons.play_circle_outline,
                      label: _activePlansLabel,
                      value: "${stats.activePlans}",
                    ),
                    _StatItem(
                      icon: Icons.edit_note_outlined,
                      label: _draftPlansLabel,
                      value: "${stats.draftPlans}",
                    ),
                    _StatItem(
                      icon: Icons.history_edu_outlined,
                      label: _revisionsLabel,
                      value: "${stats.revisionCount}",
                    ),
                  ],
                ),
                const SizedBox(height: _cardSpacing),
                _SectionTitle(title: _statusTitle),
                _ResponsiveStatGrid(
                  stats: [
                    _StatItem(
                      icon: Icons.play_arrow_outlined,
                      label: _activePlansLabel,
                      value: "${stats.activePlans}",
                    ),
                    _StatItem(
                      icon: Icons.pause_outlined,
                      label: _pausedPlansLabel,
                      value: "${stats.pausedPlans}",
                    ),
                    _StatItem(
                      icon: Icons.task_alt_outlined,
                      label: _completedPlansLabel,
                      value: "${stats.completedPlans}",
                    ),
                    _StatItem(
                      icon: Icons.archive_outlined,
                      label: _archivedPlansLabel,
                      value: "${stats.archivedPlans}",
                    ),
                  ],
                ),
                if (confidence != null) ...[
                  const SizedBox(height: _cardSpacing),
                  _SectionTitle(title: _confidenceTitle),
                  _ResponsiveStatGrid(
                    stats: [
                      _StatItem(
                        icon: Icons.trending_up,
                        label: _currentLabel,
                        value: _formatPercent(
                          confidence.currentConfidenceScore,
                        ),
                      ),
                      _StatItem(
                        icon: Icons.timeline,
                        label: _baselineLabel,
                        value: _formatPercent(
                          confidence.baselineConfidenceScore,
                        ),
                      ),
                      _StatItem(
                        icon: Icons.compare_arrows_outlined,
                        label: _deltaLabel,
                        value: _formatSignedPercent(
                          confidence.confidenceScoreDelta,
                        ),
                      ),
                      _StatItem(
                        icon: Icons.scale_outlined,
                        label: _weightedUnitsLabel,
                        value: "${confidence.weightedUnitCount}",
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: _cardSpacing),
                _SectionTitle(title: _recentPlansTitle),
                ...stats.recentPlans.map(_RecentPlanCard.new),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _MessageList(
            icon: Icons.error_outline,
            title: "Unable to load stats",
            message: error.toString(),
          ),
        ),
      ),
    );
  }
}

class _ResponsiveStatGrid extends StatelessWidget {
  final List<_StatItem> stats;

  const _ResponsiveStatGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final itemWidth =
            (constraints.maxWidth - (_gridGap * (columns - 1))) / columns;
        return Wrap(
          spacing: _gridGap,
          runSpacing: _gridGap,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: itemWidth,
                  child: _StatCard(stat: stat),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final _StatItem stat;

  const _StatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: Icon(stat.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.value,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.label,
                  style: textTheme.bodySmall?.copyWith(
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

class _RecentPlanCard extends StatelessWidget {
  final ProductionPlan plan;

  const _RecentPlanCard(this.plan);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: _cardSpacing),
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "${formatDateLabel(plan.startDate)} - ${formatDateLabel(plan.endDate)}",
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _StatusBadge(status: plan.status),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageList({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(_pagePadding),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, size: 36, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _ProductionStats {
  final int totalPlans;
  final int activePlans;
  final int draftPlans;
  final int pausedPlans;
  final int completedPlans;
  final int archivedPlans;
  final int revisionCount;
  final List<ProductionPlan> recentPlans;

  const _ProductionStats({
    required this.totalPlans,
    required this.activePlans,
    required this.draftPlans,
    required this.pausedPlans,
    required this.completedPlans,
    required this.archivedPlans,
    required this.revisionCount,
    required this.recentPlans,
  });

  factory _ProductionStats.fromPlans(List<ProductionPlan> plans) {
    final sortedPlans = [...plans]
      ..sort((left, right) {
        final leftDate = left.lastDraftSavedAt ?? left.startDate ?? DateTime(0);
        final rightDate =
            right.lastDraftSavedAt ?? right.startDate ?? DateTime(0);
        return rightDate.compareTo(leftDate);
      });
    return _ProductionStats(
      totalPlans: plans.length,
      activePlans: _countStatus(plans, _statusActive),
      draftPlans: _countStatus(plans, _statusDraft),
      pausedPlans: _countStatus(plans, _statusPaused),
      completedPlans: _countStatus(plans, _statusCompleted),
      archivedPlans: _countStatus(plans, _statusArchived),
      revisionCount: plans.fold<int>(
        0,
        (sum, plan) => sum + plan.draftRevisionCount,
      ),
      recentPlans: sortedPlans.take(5).toList(growable: false),
    );
  }
}

int _countStatus(List<ProductionPlan> plans, String status) {
  return plans
      .where((plan) => plan.status.trim().toLowerCase() == status)
      .length;
}

String _formatPercent(double value) {
  return "${(value * 100).round()}%";
}

String _formatSignedPercent(double value) {
  final percent = (value * 100).round();
  return percent > 0 ? "+$percent%" : "$percent%";
}
