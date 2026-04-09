/// lib/app/features/home/presentation/production/production_presence_banner.dart
/// -----------------------------------------------------------------------------
/// WHAT:
/// - Live presence banner for production screens.
///
/// WHY:
/// - Shows who is currently viewing the plan and what role they have.
/// - Makes the active viewer set obvious with color-coded role chips.
///
/// HOW:
/// - Accepts the current viewer plus any remote viewer snapshots.
/// - Merges and sorts the viewer list so the signed-in user stays visible.
/// - Colors each chip by role for quick scanning.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/production/production_draft_presence.dart';
import 'package:frontend/app/theme/app_colors.dart';

class ProductionPresenceBanner extends StatelessWidget {
  final ProductionDraftPresenceViewer currentViewer;
  final List<ProductionDraftPresenceViewer> remoteViewers;
  final bool isConnected;
  final bool isSharedRoom;
  final String? errorMessage;
  final String? planId;
  final DateTime? snapshotAt;

  const ProductionPresenceBanner({
    super.key,
    required this.currentViewer,
    required this.remoteViewers,
    required this.isConnected,
    required this.isSharedRoom,
    required this.errorMessage,
    this.planId,
    this.snapshotAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewers = _mergeProductionPresenceViewers(
      currentViewer: currentViewer,
      remoteViewers: remoteViewers,
    );
    final normalizedPlanId = (planId ?? "").trim();
    final roomId = draftPresenceRoomIdForPlanId(normalizedPlanId);
    final viewerCount = viewers.length;
    final statusColor = isSharedRoom
        ? (isConnected ? AppColors.productionAccent : AppColors.tenantAccent)
        : theme.colorScheme.tertiary;
    final statusLabel = !isSharedRoom
        ? "Local plan"
        : isConnected
        ? "Live"
        : "Connecting";
    final statusBackground = statusColor.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.24 : 0.12,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = constraints.maxWidth < 760;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Currently viewing",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "$viewerCount viewer${viewerCount == 1 ? '' : 's'} on this plan",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSharedRoom
                        ? "Live room presence updates while the plan is open."
                        : "Showing the signed-in account tied to this plan.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );

              final statusChip = Container(
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
                      isConnected
                          ? Icons.wifi_tethering_outlined
                          : Icons.wifi_off_outlined,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );

              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 12),
                    statusChip,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 12),
                  statusChip,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (roomId.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.14 : 0.48,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Debug room",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Plan ID: $normalizedPlanId",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Room: $roomId",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          StreamBuilder<DateTime>(
            stream: Stream<DateTime>.periodic(
              const Duration(seconds: 30),
              (_) => DateTime.now(),
            ),
            initialData: DateTime.now(),
            builder: (context, timeSnapshot) {
              final referenceTime = timeSnapshot.data ?? DateTime.now();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: viewers
                        .map(
                          (viewer) => _ProductionPresenceViewerChip(
                            viewer: viewer,
                            isSelf:
                                _productionPresenceViewerKey(viewer) ==
                                _productionPresenceViewerKey(currentViewer),
                            referenceTime: referenceTime,
                            snapshotAt: snapshotAt,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  ProductionPresenceStatsCard(
                    viewers: viewers,
                    referenceTime: referenceTime,
                    snapshotAt: snapshotAt,
                  ),
                ],
              );
            },
          ),
          if ((errorMessage ?? "").trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              "Live presence is not connected yet. Showing the current viewer and plan state only.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<ProductionDraftPresenceViewer> _mergeProductionPresenceViewers({
  required ProductionDraftPresenceViewer currentViewer,
  required List<ProductionDraftPresenceViewer> remoteViewers,
}) {
  final merged = <String, ProductionDraftPresenceViewer>{};
  final currentKey = _productionPresenceViewerKey(currentViewer);
  if (currentKey.isNotEmpty) {
    merged[currentKey] = currentViewer;
  }

  for (final viewer in remoteViewers) {
    final key = _productionPresenceViewerKey(viewer);
    if (key.isEmpty) {
      continue;
    }
    merged[key] = viewer;
  }

  final viewers = merged.values.toList();
  viewers.sort((left, right) {
    final selfKey = currentKey;
    if (_productionPresenceViewerKey(left) == selfKey &&
        _productionPresenceViewerKey(right) != selfKey) {
      return -1;
    }
    if (_productionPresenceViewerKey(right) == selfKey &&
        _productionPresenceViewerKey(left) != selfKey) {
      return 1;
    }
    final nameCompare = left.resolvedDisplayName.compareTo(
      right.resolvedDisplayName,
    );
    if (nameCompare != 0) {
      return nameCompare;
    }
    return left.userId.compareTo(right.userId);
  });

  return viewers;
}

String _productionPresenceViewerKey(ProductionDraftPresenceViewer viewer) {
  final userId = viewer.userId.trim();
  if (userId.isNotEmpty) {
    return userId;
  }

  final displayName = viewer.resolvedDisplayName.trim();
  final roleKey = viewer.roleKey.trim();
  if (displayName.isEmpty && roleKey.isEmpty) {
    return "";
  }

  return "$displayName|$roleKey";
}

Color _resolveProductionPresenceAccentColor(ThemeData theme, String roleKey) {
  switch (normalizeDraftPresenceRoleKey(roleKey)) {
    case "business_owner":
      return AppColors.tertiary;
    case "estate_manager":
      return AppColors.analyticsAccent;
    case "farm_manager":
      return AppColors.productionAccent;
    case "asset_manager":
      return AppColors.commerceAccent;
    case "admin":
      return AppColors.recordsAccent;
    default:
      return theme.colorScheme.primary;
  }
}

String _presenceViewerInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r"\s+"))
      .where((word) => word.trim().isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return "?";
  }

  final first = words.first.trim();
  final second = words.length > 1 ? words[1].trim() : "";
  final buffer = StringBuffer();
  buffer.write(first.substring(0, 1));
  if (second.isNotEmpty) {
    buffer.write(second.substring(0, 1));
  } else if (first.length > 1) {
    buffer.write(first.substring(first.length - 1));
  }
  return buffer.toString().toUpperCase();
}

class _ProductionPresenceViewerChip extends StatelessWidget {
  final ProductionDraftPresenceViewer viewer;
  final bool isSelf;
  final DateTime referenceTime;
  final DateTime? snapshotAt;

  const _ProductionPresenceViewerChip({
    required this.viewer,
    required this.isSelf,
    required this.referenceTime,
    required this.snapshotAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _resolveProductionPresenceAccentColor(theme, viewer.roleKey);
    final background = accent.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12,
    );
    final initials = _presenceViewerInitials(viewer.resolvedDisplayName);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent.withValues(alpha: isSelf ? 0.72 : 0.42),
            width: isSelf ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          viewer.resolvedDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.24
                                  : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            "You",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    viewer.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (viewer.hasPresenceMetrics) ...[
                    const SizedBox(height: 4),
                    Text(
                      viewer.presenceSummaryLabel(
                        referenceTime: referenceTime,
                        snapshotAt: snapshotAt,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProductionPresenceStatsPeriod { day, week, month }

extension _ProductionPresenceStatsPeriodLabel
    on _ProductionPresenceStatsPeriod {
  String get label {
    switch (this) {
      case _ProductionPresenceStatsPeriod.day:
        return "Day";
      case _ProductionPresenceStatsPeriod.week:
        return "Week";
      case _ProductionPresenceStatsPeriod.month:
        return "Month";
    }
  }

  String get subtitle {
    switch (this) {
      case _ProductionPresenceStatsPeriod.day:
        return "Today";
      case _ProductionPresenceStatsPeriod.week:
        return "This week";
      case _ProductionPresenceStatsPeriod.month:
        return "This month";
    }
  }
}

class ProductionPresenceStatsCard extends StatefulWidget {
  final List<ProductionDraftPresenceViewer> viewers;
  final DateTime referenceTime;
  final DateTime? snapshotAt;

  const ProductionPresenceStatsCard({
    super.key,
    required this.viewers,
    required this.referenceTime,
    required this.snapshotAt,
  });

  @override
  State<ProductionPresenceStatsCard> createState() =>
      _ProductionPresenceStatsCardState();
}

class _ProductionPresenceStatsCardState
    extends State<ProductionPresenceStatsCard> {
  _ProductionPresenceStatsPeriod _period = _ProductionPresenceStatsPeriod.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _buildProductionPresenceStatsEntries(
      viewers: widget.viewers,
      period: _period,
      referenceTime: widget.referenceTime,
      snapshotAt: widget.snapshotAt,
    );
    final totalSeconds = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.seconds,
    );
    final activeCount = entries.length;
    final averageSeconds = activeCount == 0
        ? 0
        : (totalSeconds / activeCount).round();
    final peakSeconds = entries.fold<int>(
      0,
      (peak, entry) => math.max(peak, entry.seconds),
    );
    final summaryColor = theme.colorScheme.primary;
    final selectedBackground = theme.colorScheme.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.14 : 0.5,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = constraints.maxWidth < 720;
              final header = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Staff joined stats",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${_period.subtitle} hours spent in the room by staff.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );

              final periodChips = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ProductionPresenceStatsPeriod.values.map((period) {
                  final selected = period == _period;
                  return ChoiceChip(
                    label: Text(period.label),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: selectedBackground,
                    side: BorderSide(
                      color: selected
                          ? summaryColor.withValues(alpha: 0.5)
                          : theme.colorScheme.outlineVariant,
                    ),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? summaryColor
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _period = period;
                      });
                    },
                  );
                }).toList(),
              );

              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [header, const SizedBox(height: 12), periodChips],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: header),
                  const SizedBox(width: 12),
                  periodChips,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PresenceStatsMetricChip(
                label: "Staff",
                value: "${entries.length}",
              ),
              _PresenceStatsMetricChip(
                label: "Total",
                value: _formatPresenceHoursLabel(totalSeconds),
              ),
              _PresenceStatsMetricChip(
                label: "Average",
                value: _formatPresenceHoursLabel(averageSeconds),
              ),
              _PresenceStatsMetricChip(
                label: "Peak",
                value: _formatPresenceHoursLabel(peakSeconds),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.12 : 0.22,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.55,
                  ),
                ),
              ),
              child: Text(
                "No staff time tracked for this period yet.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            SizedBox(
              height: 248,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _PresenceStatsGrid(
                      lineColor: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: entries
                            .map(
                              (entry) => _PresenceStatsBarCard(
                                entry: entry,
                                maxSeconds: peakSeconds,
                              ),
                            )
                            .toList(),
                      ),
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

class _PresenceStatsMetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _PresenceStatsMetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.24 : 0.38,
        ),
        borderRadius: BorderRadius.circular(14),
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
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresenceStatsGrid extends StatelessWidget {
  final Color lineColor;

  const _PresenceStatsGrid({required this.lineColor});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: List.generate(
          5,
          (index) => Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Divider(
                height: 1,
                thickness: 1,
                color: index == 4
                    ? lineColor.withValues(alpha: 0.18)
                    : lineColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresenceStatsBarCard extends StatelessWidget {
  final _ProductionPresenceStatsEntry entry;
  final int maxSeconds;

  const _PresenceStatsBarCard({required this.entry, required this.maxSeconds});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _resolveProductionPresenceAccentColor(
      theme,
      entry.viewer.roleKey,
    );
    final fillRatio = maxSeconds <= 0 ? 0.0 : entry.seconds / maxSeconds;
    final barHeight = 168 * fillRatio.clamp(0.0, 1.0);
    final barHeightPixels = math.max(10.0, barHeight);
    final initials = _presenceViewerInitials(entry.viewer.resolvedDisplayName);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 132,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              entry.viewer.resolvedDisplayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.viewer.roleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 176,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 28,
                      height: barHeightPixels,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withValues(alpha: 0.96),
                            accent.withValues(alpha: 0.68),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.18),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _formatPresenceHoursLabel(entry.seconds),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.viewer.enteredAtLabel.isNotEmpty
                  ? "Joined ${entry.viewer.enteredAtLabel}"
                  : "Joined --",
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductionPresenceStatsEntry {
  final ProductionDraftPresenceViewer viewer;
  final int seconds;

  const _ProductionPresenceStatsEntry({
    required this.viewer,
    required this.seconds,
  });
}

List<_ProductionPresenceStatsEntry> _buildProductionPresenceStatsEntries({
  required List<ProductionDraftPresenceViewer> viewers,
  required _ProductionPresenceStatsPeriod period,
  required DateTime referenceTime,
  required DateTime? snapshotAt,
}) {
  final entries = viewers
      .map(
        (viewer) => _ProductionPresenceStatsEntry(
          viewer: viewer,
          seconds: _productionPresenceStatsSecondsForPeriod(
            viewer,
            period,
            referenceTime: referenceTime,
            snapshotAt: snapshotAt,
          ),
        ),
      )
      .toList();
  entries.sort((left, right) => right.seconds.compareTo(left.seconds));
  return entries;
}

int _productionPresenceStatsSecondsForPeriod(
  ProductionDraftPresenceViewer viewer,
  _ProductionPresenceStatsPeriod period, {
  required DateTime referenceTime,
  DateTime? snapshotAt,
}) {
  switch (period) {
    case _ProductionPresenceStatsPeriod.day:
      return viewer.liveTodaySeconds(
        referenceTime: referenceTime,
        snapshotAt: snapshotAt,
      );
    case _ProductionPresenceStatsPeriod.week:
      return viewer.liveWeekSeconds(
        referenceTime: referenceTime,
        snapshotAt: snapshotAt,
      );
    case _ProductionPresenceStatsPeriod.month:
      return viewer.liveMonthSeconds(
        referenceTime: referenceTime,
        snapshotAt: snapshotAt,
      );
  }
}

String _formatPresenceHoursLabel(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  if (safeSeconds == 0) {
    return "0h";
  }

  final hours = safeSeconds / 3600;
  if (hours >= 10) {
    return "${hours.toStringAsFixed(0)}h";
  }
  if (hours >= 1) {
    return "${hours.toStringAsFixed(1)}h";
  }

  final minutes = (safeSeconds / 60).round();
  return "${minutes}m";
}
