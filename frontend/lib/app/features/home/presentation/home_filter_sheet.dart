/// lib/app/features/home/presentation/home_filter_sheet.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Bottom sheet UI for Home filters.
///
/// WHY:
/// - Keeps HomeScreen clean and reusable.
/// - Provides a simple way to toggle filters.
///
/// HOW:
/// - Holds local state for switches and radios.
/// - Returns HomeFilterOptions on Apply.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

enum ProductSort {
  none,
  newest,
  priceLowHigh,
  priceHighLow,
  nameAZ,
  nameZA,
}

class HomeFilterOptions {
  final bool inStockOnly;
  final ProductSort sort;

  const HomeFilterOptions({
    required this.inStockOnly,
    required this.sort,
  });
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

  @override
  void initState() {
    super.initState();
    _inStockOnly = widget.initial.inStockOnly;
    _sort = widget.initial.sort;
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_FILTER", "build()");

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Filters",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _inStockOnly,
            onChanged: (value) {
              AppDebug.log(
                "HOME_FILTER",
                "In stock toggled",
                extra: {"value": value},
              );
              setState(() => _inStockOnly = value);
            },
            title: const Text("In stock only"),
          ),
          const SizedBox(height: 8),
          Text(
            "Sort by",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          // WHY: These options mirror backend sortable fields (price, name, createdAt).
          RadioListTile<ProductSort>(
            value: ProductSort.none,
            groupValue: _sort,
            onChanged: (value) {
              AppDebug.log("HOME_FILTER", "Sort -> none");
              setState(() => _sort = value ?? ProductSort.none);
            },
            title: const Text("None"),
          ),
          RadioListTile<ProductSort>(
            value: ProductSort.newest,
            groupValue: _sort,
            onChanged: (value) {
              AppDebug.log("HOME_FILTER", "Sort -> newest");
              setState(() => _sort = value ?? ProductSort.newest);
            },
            title: const Text("Newest"),
          ),
          RadioListTile<ProductSort>(
            value: ProductSort.priceLowHigh,
            groupValue: _sort,
            onChanged: (value) {
              AppDebug.log("HOME_FILTER", "Sort -> priceLowHigh");
              setState(() => _sort = value ?? ProductSort.priceLowHigh);
            },
            title: const Text("Price: low to high"),
          ),
          RadioListTile<ProductSort>(
            value: ProductSort.priceHighLow,
            groupValue: _sort,
            onChanged: (value) {
              AppDebug.log("HOME_FILTER", "Sort -> priceHighLow");
              setState(() => _sort = value ?? ProductSort.priceHighLow);
            },
            title: const Text("Price: high to low"),
          ),
          RadioListTile<ProductSort>(
            value: ProductSort.nameAZ,
            groupValue: _sort,
            onChanged: (value) {
              AppDebug.log("HOME_FILTER", "Sort -> nameAZ");
              setState(() => _sort = value ?? ProductSort.nameAZ);
            },
            title: const Text("Name: A to Z"),
          ),
          RadioListTile<ProductSort>(
            value: ProductSort.nameZA,
            groupValue: _sort,
            onChanged: (value) {
              AppDebug.log("HOME_FILTER", "Sort -> nameZA");
              setState(() => _sort = value ?? ProductSort.nameZA);
            },
            title: const Text("Name: Z to A"),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  AppDebug.log("HOME_FILTER", "Clear tapped");
                  setState(() {
                    _inStockOnly = false;
                    _sort = ProductSort.none;
                  });
                },
                child: const Text("Clear"),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  AppDebug.log("HOME_FILTER", "Apply tapped");
                  Navigator.of(context).pop(
                    HomeFilterOptions(
                      inStockOnly: _inStockOnly,
                      sort: _sort,
                    ),
                  );
                },
                child: const Text("Apply"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
