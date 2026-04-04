library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class StorefrontColorSwatchRow extends StatelessWidget {
  final List<ProductColorVariant> colors;
  final int maxVisible;
  final double size;

  const StorefrontColorSwatchRow({
    super.key,
    required this.colors,
    this.maxVisible = 4,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) {
      return const SizedBox.shrink();
    }

    final visible = colors.take(maxVisible).toList();
    final hiddenCount = colors.length - visible.length;

    return Row(
      children: [
        for (var index = 0; index < visible.length; index += 1)
          Padding(
            padding: EdgeInsets.only(
              right: index == visible.length - 1 ? 0 : AppSpacing.xs,
            ),
            child: Tooltip(
              message: visible[index].name,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: _parseHexColor(visible[index].hexCode),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.shadow.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (hiddenCount > 0) ...[
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              "+$hiddenCount",
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ],
    );
  }

  Color _parseHexColor(String hexCode) {
    final normalized = hexCode.replaceAll("#", "").trim();
    if (normalized.length == 6) {
      return Color(int.parse("FF$normalized", radix: 16));
    }
    if (normalized.length == 8) {
      return Color(int.parse(normalized, radix: 16));
    }
    return const Color(0xFF111827);
  }
}
