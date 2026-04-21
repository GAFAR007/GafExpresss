/// lib/app/features/home/presentation/settings/widgets/settings_address_section.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Structured address section for Settings (home/company).
///
/// WHY:
/// - Keeps SettingsScreen clean while still showing all address fields.
/// - Groups verification controls with address inputs for clarity.
///
/// HOW:
/// - Renders a header, verify action, and structured text fields.
/// ---------------------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/settings/widgets/address_autocomplete_field.dart';
import 'package:frontend/app/features/home/presentation/settings/widgets/settings_form_fields.dart';
import 'package:frontend/app/theme/app_theme.dart';

class SettingsAddressSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isVerified;
  final bool canVerify;
  final String? statusText;
  final AddressStatusTone statusTone;
  final VoidCallback onVerifyTap;
  final String sourceTag;
  final TextEditingController houseNumberCtrl;
  final TextEditingController streetCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController stateCtrl;
  final TextEditingController postalCodeCtrl;
  final TextEditingController lgaCtrl;
  final TextEditingController landmarkCtrl;
  final void Function(String placeId, UserAddress address)? onPlaceSelected;

  const SettingsAddressSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isVerified,
    required this.canVerify,
    this.statusText,
    this.statusTone = AddressStatusTone.neutral,
    required this.onVerifyTap,
    required this.sourceTag,
    required this.houseNumberCtrl,
    required this.streetCtrl,
    required this.cityCtrl,
    required this.stateCtrl,
    required this.postalCodeCtrl,
    required this.lgaCtrl,
    required this.landmarkCtrl,
    this.onPlaceSelected,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep the verify action tied to the address context.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SettingsSectionHeader(title: title, subtitle: subtitle),
            ),
            _AddressVerifyButton(
              isVerified: isVerified,
              canVerify: canVerify,
              onTap: onVerifyTap,
            ),
          ],
        ),
        if (statusText != null && statusText!.isNotEmpty) ...[
          const SizedBox(height: 6),
          _AddressStatusLine(text: statusText!, tone: statusTone),
        ],
        const SizedBox(height: 12),
        AddressAutocompleteField(
          label: "Search address",
          hint: "Start typing to autofill",
          sourceTag: sourceTag,
          houseNumberCtrl: houseNumberCtrl,
          streetCtrl: streetCtrl,
          cityCtrl: cityCtrl,
          stateCtrl: stateCtrl,
          postalCtrl: postalCodeCtrl,
          lgaCtrl: lgaCtrl,
          landmarkCtrl: landmarkCtrl,
          onPlaceSelected: onPlaceSelected,
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          controller: houseNumberCtrl,
          label: "House number",
          hint: "e.g. 12",
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          controller: streetCtrl,
          label: "Street",
          hint: "e.g. Allen Avenue",
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          controller: cityCtrl,
          label: "City",
          hint: "e.g. Ikeja",
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          controller: stateCtrl,
          label: "State",
          hint: "e.g. Lagos",
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          controller: postalCodeCtrl,
          label: "Postal code (optional)",
          hint: "e.g. 100001",
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          controller: lgaCtrl,
          label: "LGA (optional)",
          hint: "e.g. Ikeja",
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          controller: landmarkCtrl,
          label: "Landmark (optional)",
          hint: "e.g. Near City Mall",
        ),
      ],
    );
  }
}

enum AddressStatusTone { neutral, busy, success, error }

class _AddressStatusLine extends StatelessWidget {
  final String text;
  final AddressStatusTone tone;

  const _AddressStatusLine({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toneColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: switch (tone) {
        AddressStatusTone.success => AppStatusTone.success,
        AddressStatusTone.busy => AppStatusTone.warning,
        AddressStatusTone.error => AppStatusTone.danger,
        AddressStatusTone.neutral => AppStatusTone.neutral,
      },
    );
    final color = toneColors.foreground;

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _AddressVerifyButton extends StatelessWidget {
  final bool isVerified;
  final bool canVerify;
  final VoidCallback onTap;

  const _AddressVerifyButton({
    required this.isVerified,
    required this.canVerify,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isVerified) {
      final badgeColors = AppStatusBadgeColors.fromTheme(
        theme: Theme.of(context),
        tone: AppStatusTone.success,
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: badgeColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, size: 16, color: badgeColors.foreground),
            const SizedBox(width: 6),
            Text(
              "Verified",
              style: TextStyle(
                color: badgeColors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // WHY: Disable verify until required fields are present.
    return OutlinedButton(
      onPressed: canVerify ? onTap : null,
      style: AppButtonStyles.outlined(
        theme: Theme.of(context),
        tone: AppStatusTone.info,
      ),
      child: const Text("Verify"),
    );
  }
}
