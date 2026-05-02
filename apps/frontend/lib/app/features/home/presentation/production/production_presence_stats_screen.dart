/// lib/app/features/home/presentation/production/production_presence_stats_screen.dart
/// -----------------------------------------------------------------------------
/// WHAT:
/// - Dedicated full-screen view for production draft/workspace presence stats.
///
/// WHY:
/// - Keeps the draft/workspace presence banners compact.
/// - Gives staff a predictable place to inspect joined-time bar charts.
///
/// HOW:
/// - Reads the live presence room snapshot for the current plan.
/// - Renders the same staff-duration bar chart used by the inline banner.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/production/production_draft_presence.dart';
import 'package:frontend/app/features/home/presentation/production/production_presence_banner.dart';
import 'package:frontend/app/theme/app_colors.dart';

const String _logTag = "PRODUCTION_PRESENCE_STATS";
const String _buildLog = "build()";
const String _backTapLog = "back_tap";
const String _screenTitle = "Staff joined stats";
const String _screenSubtitle =
    "Use this screen to review who joined the draft room and how long each person stayed active.";
const String _planIdLabel = "Plan ID";
const String _roomIdLabel = "Room";
const String _viewerCountLabel = "Joined staff";
const String _emptyPlanTitle = "Plan id missing";
const String _emptyPlanMessage =
    "Open this screen from a draft or workspace that already has a plan id.";

class ProductionPresenceStatsScreen extends ConsumerWidget {
  final String planId;

  const ProductionPresenceStatsScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildLog, extra: {"planId": planId});

    final theme = Theme.of(context);
    final normalizedPlanId = planId.trim();
    final roomId = draftPresenceRoomIdForPlanId(normalizedPlanId);

    if (normalizedPlanId.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _StatsEmptyState(
                  title: _emptyPlanTitle,
                  message: _emptyPlanMessage,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final presenceState = ref.watch(
      productionDraftPresenceProvider(normalizedPlanId),
    );
    final viewerCount = presenceState.viewers.length;
    final statusColor = presenceState.isConnected
        ? AppColors.productionAccent
        : AppColors.tenantAccent;
    final statusBackground = statusColor.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton.filled(
                          onPressed: () {
                            AppDebug.log(_logTag, _backTapLog);
                            context.pop();
                          },
                          icon: const Icon(Icons.arrow_back),
                          tooltip: "Back",
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _screenTitle,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _screenSubtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: statusBackground,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.42),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                presenceState.isConnected
                                    ? Icons.wifi_tethering_outlined
                                    : Icons.wifi_off_outlined,
                                size: 16,
                                color: statusColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                presenceState.isConnected
                                    ? "Live"
                                    : "Connecting",
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatsInfoChip(
                            label: _planIdLabel,
                            value: normalizedPlanId,
                          ),
                          _StatsInfoChip(label: _roomIdLabel, value: roomId),
                          _StatsInfoChip(
                            label: _viewerCountLabel,
                            value:
                                "$viewerCount viewer${viewerCount == 1 ? '' : 's'}",
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    StreamBuilder<DateTime>(
                      stream: Stream<DateTime>.periodic(
                        const Duration(seconds: 30),
                        (_) => DateTime.now(),
                      ),
                      initialData: DateTime.now(),
                      builder: (context, timeSnapshot) {
                        final referenceTime =
                            timeSnapshot.data ?? DateTime.now();
                        return ProductionPresenceStatsCard(
                          viewers: presenceState.viewers,
                          referenceTime: referenceTime,
                          snapshotAt: presenceState.updatedAt,
                        );
                      },
                    ),
                    if ((presenceState.error ?? "").trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        "Live presence is not fully connected yet. The chart is showing the latest known room snapshot.",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsInfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatsInfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsEmptyState extends StatelessWidget {
  final String title;
  final String message;

  const _StatsEmptyState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bar_chart_rounded,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
