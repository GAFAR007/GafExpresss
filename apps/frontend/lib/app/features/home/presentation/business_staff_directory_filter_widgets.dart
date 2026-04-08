/// lib/app/features/home/presentation/business_staff_directory_filter_widgets.dart
/// -----------------------------------------------------------------------------
/// WHAT:
/// - Reusable filter dropdown widgets for the staff directory.
///
/// WHY:
/// - Keeps the filter section file small and readable.
/// - Reuses dropdown UI across staff filters.
///
/// HOW:
/// - Provides role, status, and estate dropdowns with shared styles.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class StaffRoleDropdown extends StatelessWidget {
  final String label;
  final String? selected;
  final List<String> roles;
  final String allRolesLabel;
  final String Function(String value) formatLabel;
  final ValueChanged<String?> onChanged;

  const StaffRoleDropdown({
    super.key,
    required this.label,
    required this.selected,
    required this.roles,
    required this.allRolesLabel,
    required this.formatLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Offer an "All roles" option to reset role filtering.
    return DropdownButtonFormField<String>(
      initialValue: selected ?? allRolesLabel,
      decoration: InputDecoration(labelText: label),
      items: <String>[allRolesLabel, ...roles]
          .map(
            (value) =>
                DropdownMenuItem(value: value, child: Text(formatLabel(value))),
          )
          .toList(),
      onChanged: (value) {
        final next = value == allRolesLabel ? null : value;
        onChanged(next);
      },
    );
  }
}

class StaffStatusDropdown extends StatelessWidget {
  final String label;
  final String? selected;
  final List<String> statuses;
  final String allStatusesLabel;
  final String Function(String value) formatLabel;
  final ValueChanged<String?> onChanged;

  const StaffStatusDropdown({
    super.key,
    required this.label,
    required this.selected,
    required this.statuses,
    required this.allStatusesLabel,
    required this.formatLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Offer an "All statuses" option to reset status filtering.
    return DropdownButtonFormField<String>(
      initialValue: selected ?? allStatusesLabel,
      decoration: InputDecoration(labelText: label),
      items: <String>[allStatusesLabel, ...statuses]
          .map(
            (value) =>
                DropdownMenuItem(value: value, child: Text(formatLabel(value))),
          )
          .toList(),
      onChanged: (value) {
        final next = value == allStatusesLabel ? null : value;
        onChanged(next);
      },
    );
  }
}

class StaffEstateDropdown extends StatelessWidget {
  final String label;
  final List<BusinessAsset> assets;
  final String? selected;
  final String allEstatesLabel;
  final ValueChanged<String?> onChanged;

  const StaffEstateDropdown({
    super.key,
    required this.label,
    required this.assets,
    required this.selected,
    required this.allEstatesLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Show estate choices only when assets are available.
    final sortedAssets = [...assets]..sort((a, b) => a.name.compareTo(b.name));
    final hasSelection =
        selected != null && sortedAssets.any((asset) => asset.id == selected);
    return DropdownButtonFormField<String>(
      initialValue: hasSelection ? selected : allEstatesLabel,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<String>>[
        DropdownMenuItem(value: allEstatesLabel, child: Text(allEstatesLabel)),
        ...sortedAssets.map(
          (asset) => DropdownMenuItem(value: asset.id, child: Text(asset.name)),
        ),
      ],
      onChanged: (value) {
        final next = value == allEstatesLabel ? null : value;
        onChanged(next);
      },
    );
  }
}

class StaffEstateLoadingDropdown extends StatelessWidget {
  final String label;
  final String valueLabel;

  const StaffEstateLoadingDropdown({
    super.key,
    required this.label,
    required this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: valueLabel,
      decoration: InputDecoration(labelText: label),
      items: [DropdownMenuItem(value: valueLabel, child: Text(valueLabel))],
      onChanged: null,
    );
  }
}

class StaffEstateErrorState extends StatelessWidget {
  final String message;
  final String hint;
  final String retryLabel;
  final VoidCallback onRetry;

  const StaffEstateErrorState({
    super.key,
    required this.message,
    required this.hint,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(onPressed: onRetry, child: Text(retryLabel)),
      ],
    );
  }
}
