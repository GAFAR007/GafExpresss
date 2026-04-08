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

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/production/production_draft_presence.dart';
import 'package:frontend/app/theme/app_colors.dart';

class ProductionPresenceBanner extends StatelessWidget {
  final ProductionDraftPresenceViewer currentViewer;
  final List<ProductionDraftPresenceViewer> remoteViewers;
  final bool isConnected;
  final bool isSharedRoom;
  final String? errorMessage;

  const ProductionPresenceBanner({
    super.key,
    required this.currentViewer,
    required this.remoteViewers,
    required this.isConnected,
    required this.isSharedRoom,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewers = _mergeProductionPresenceViewers(
      currentViewer: currentViewer,
      remoteViewers: remoteViewers,
    );
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
                  ),
                )
                .toList(),
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

  const _ProductionPresenceViewerChip({
    required this.viewer,
    required this.isSelf,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
