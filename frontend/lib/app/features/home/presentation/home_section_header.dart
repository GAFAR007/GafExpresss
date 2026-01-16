/// lib/app/features/home/presentation/home_section_header.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Reusable section header with optional action.
///
/// WHY:
/// - Keeps section titles consistent across the Home layout.
/// - Avoids repeating the same row markup in multiple widgets.
///
/// HOW:
/// - Renders a title on the left and an action button on the right.
/// - Parent provides the tap handler for logging/navigation.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';

class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback? onActionTap;

  const HomeSectionHeader({
    super.key,
    required this.title,
    this.actionLabel = "See all",
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // WHY: Title anchors the section and improves scanability.
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        // WHY: Optional action enables navigation without clutter.
        if (actionLabel.isNotEmpty)
          TextButton(
            // WHY: Parent decides what "See all" means (route or filter).
            onPressed: onActionTap,
            child: Text(actionLabel),
          ),
      ],
    );
  }
}
