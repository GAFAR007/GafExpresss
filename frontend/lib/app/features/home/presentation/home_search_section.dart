/// lib/app/features/home/presentation/home_search_section.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Search input + filter action for Home.
///
/// WHY:
/// - Gives users a quick way to find items.
/// - Matches the reference layout without adding heavy logic.
///
/// HOW:
/// - Renders a text field and a small filter icon button.
/// - Parent can hook into submit/tap for later search behavior.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class HomeSearchSection extends StatelessWidget {
  final VoidCallback onFilterTap;
  final ValueChanged<String>? onSearchSubmitted;
  final ValueChanged<String>? onSearchChanged;
  final bool hasActiveFilters;

  const HomeSearchSection({
    super.key,
    required this.onFilterTap,
    this.onSearchSubmitted,
    this.onSearchChanged,
    this.hasActiveFilters = false,
  });

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_SEARCH", "build()");

    return Row(
      children: [
        // WHY: Expanded search field keeps layout balanced with filter button.
        Expanded(
          child: TextField(
            // WHY: Placeholder helps users understand intent quickly.
            decoration: InputDecoration(
              hintText: "Search",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              AppDebug.log("HOME_SEARCH", "Search changed", extra: {"q": value});
              if (onSearchChanged != null) {
                onSearchChanged!(value);
              }
            },
            onSubmitted: (value) {
              AppDebug.log("HOME_SEARCH", "Search submitted", extra: {"q": value});
              if (onSearchSubmitted != null) {
                onSearchSubmitted!(value);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        // WHY: Filter icon keeps the header compact and touch-friendly.
        InkWell(
          onTap: () {
            AppDebug.log("HOME_SEARCH", "Filter tapped");
            onFilterTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune),
              ),
              if (hasActiveFilters)
                // WHY: Small dot signals filters are active without extra text.
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
