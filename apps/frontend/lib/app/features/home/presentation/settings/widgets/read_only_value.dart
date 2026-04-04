/// lib/app/features/home/presentation/settings/widgets/read_only_value.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Read-only field widgets used in Settings.
///
/// WHY:
/// - Avoid controller creation for display-only rows.
/// - Keep verification status pills consistent across the screen.
///
/// HOW:
/// - Renders an InputDecorator with value text.
/// - Optionally appends a verified status pill.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/theme/app_theme.dart';

class ReadOnlyValue extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;

  const ReadOnlyValue({
    super.key,
    required this.label,
    required this.value,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Use InputDecorator to keep visual parity with TextField styling.
    return InputDecorator(
      decoration: InputDecoration(labelText: label, hintText: hint),
      child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class ReadOnlyValueWithStatus extends StatelessWidget {
  final String label;
  final String value;
  final bool isVerified;
  final String? hint;

  const ReadOnlyValueWithStatus({
    super.key,
    required this.label,
    required this.value,
    required this.isVerified,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ReadOnlyValue(label: label, value: value, hint: hint),
        ),
        const SizedBox(width: 12),
        VerificationStatusPill(isVerified: isVerified),
      ],
    );
  }
}

class VerificationStatusPill extends StatelessWidget {
  final bool isVerified;

  const VerificationStatusPill({super.key, required this.isVerified});

  @override
  Widget build(BuildContext context) {
    if (!isVerified) {
      return const SizedBox.shrink();
    }

    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: AppStatusTone.success,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: badgeColors.foreground, size: 16),
          const SizedBox(width: 6),
          Text(
            "Verified",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: badgeColors.foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: AppStatusTone.success,
    );

    return Row(
      children: [
        Icon(Icons.check_circle, color: badgeColors.foreground, size: 18),
        const SizedBox(width: 8),
        Text(
          "Verified",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: badgeColors.foreground,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
