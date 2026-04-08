/// lib/app/features/home/presentation/home_filter_sheet.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Bottom sheet UI for Home filters.
///
/// WHY:
/// - Gives search segmentation a stronger information-architecture role.
/// - Uses chips and grouped controls instead of a long generic radio list.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

enum ProductSort { none, newest, priceLowHigh, priceHighLow, nameAZ, nameZA }

class HomeFilterOptions {
  final bool inStockOnly;
  final ProductSort sort;

  const HomeFilterOptions({required this.inStockOnly, required this.sort});
}

class HomeFilterSheet extends StatefulWidget {
  final HomeFilterOptions initial;

  const HomeFilterSheet({super.key, required this.initial});

  @override
  State<HomeFilterSheet> createState() => _HomeFilterSheetState();
}

class _HomeFilterSheetState extends State<HomeFilterSheet> {
  late bool _inStockOnly;
  late ProductSort _sort;

  static const List<({ProductSort value, String label, String helper})>
  _sortOptions = [
    (
      value: ProductSort.none,
      label: "Default",
      helper: "Use the base catalog order",
    ),
    (
      value: ProductSort.newest,
      label: "Newest",
      helper: "Prioritize recent additions",
    ),
    (
      value: ProductSort.priceLowHigh,
      label: "Price up",
      helper: "Low price to high price",
    ),
    (
      value: ProductSort.priceHighLow,
      label: "Price down",
      helper: "High price to low price",
    ),
    (
      value: ProductSort.nameAZ,
      label: "A to Z",
      helper: "Alphabetical ascending",
    ),
    (
      value: ProductSort.nameZA,
      label: "Z to A",
      helper: "Alphabetical descending",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _inStockOnly = widget.initial.inStockOnly;
    _sort = widget.initial.sort;
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_FILTER", "build()");
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const AppSectionHeader(
              title: "Refine the catalog",
              subtitle:
                  "Adjust stock visibility and sort priority without leaving the storefront.",
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              tone: AppPanelTone.muted,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  const AppIconBadge(icon: Icons.inventory_2_outlined),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "In-stock products only",
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          "Hide sold-out items so the catalog stays focused on what customers can browse right now.",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Switch.adaptive(
                    value: _inStockOnly,
                    onChanged: (value) {
                      AppDebug.log(
                        "HOME_FILTER",
                        "in_stock_toggle",
                        extra: {"value": value},
                      );
                      setState(() => _inStockOnly = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "Sort priority",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Choose how the catalog should be ordered while you browse.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _sortOptions.map((option) {
                final selected = _sort == option.value;
                return ChoiceChip(
                  selected: selected,
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option.label),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        option.helper,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  onSelected: (_) {
                    AppDebug.log(
                      "HOME_FILTER",
                      "sort_change",
                      extra: {"sort": option.value.name},
                    );
                    setState(() => _sort = option.value);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      AppDebug.log("HOME_FILTER", "clear_tap");
                      setState(() {
                        _inStockOnly = false;
                        _sort = ProductSort.none;
                      });
                    },
                    child: const Text("Reset"),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      AppDebug.log("HOME_FILTER", "apply_tap");
                      Navigator.of(context).pop(
                        HomeFilterOptions(
                          inStockOnly: _inStockOnly,
                          sort: _sort,
                        ),
                      );
                    },
                    child: const Text("Apply filters"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
