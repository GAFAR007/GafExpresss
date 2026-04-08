library;

import 'package:flutter/material.dart';

import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class HomePromoSection extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimaryTap;
  final List<String> highlights;

  const HomePromoSection({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimaryTap,
    this.highlights = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.secondaryContainer,
            scheme.primary,
            scheme.tertiary.withValues(alpha: 0.88),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 820;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.86),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: onPrimaryTap,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.onSurface,
                ),
                child: Text(primaryLabel),
              ),
            ],
          );

          final detailPanel = highlights.isEmpty
              ? null
              : Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Why shop this collection",
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (final item in highlights) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: scheme.onPrimary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                item,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onPrimary.withValues(
                                    alpha: 0.88,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                );

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                if (detailPanel != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  detailPanel,
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: content),
              if (detailPanel != null) ...[
                const SizedBox(width: AppSpacing.xl),
                Expanded(flex: 2, child: detailPanel),
              ],
            ],
          );
        },
      ),
    );
  }
}
