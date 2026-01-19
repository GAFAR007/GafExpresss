/// lib/app/features/home/presentation/settings/widgets/settings_form_fields.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Form field widgets for the Settings screen.
///
/// WHY:
/// - Keep SettingsScreen small by extracting reusable field builders.
///
/// HOW:
/// - Provides section header, text field, and field-with-action components.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const SettingsSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
        ),
      ],
    );
  }
}

class SettingsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;
  final bool readOnly;

  const SettingsTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.prefixText,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
      ),
    );
  }
}

class SettingsFieldWithAction extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String actionLabel;
  final bool isVerified;
  final VoidCallback onActionTap;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;
  final bool readOnly;

  const SettingsFieldWithAction({
    super.key,
    required this.controller,
    required this.label,
    required this.actionLabel,
    required this.isVerified,
    required this.onActionTap,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.prefixText,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SettingsTextField(
            controller: controller,
            label: label,
            hint: hint,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            prefixText: prefixText,
            readOnly: readOnly,
          ),
        ),
        const SizedBox(width: 12),
        _VerificationButton(
          isVerified: isVerified,
          label: actionLabel,
          onTap: onActionTap,
        ),
      ],
    );
  }
}

class SettingsProfileImageRow extends StatelessWidget {
  final String label;
  final String initials;
  final String? profileImageUrl;
  final bool isUploading;
  final VoidCallback onUploadTap;

  const SettingsProfileImageRow({
    super.key,
    required this.label,
    required this.initials,
    required this.profileImageUrl,
    required this.isUploading,
    required this.onUploadTap,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Avoid showing broken images when no profile image exists.
    final hasImage = profileImageUrl != null && profileImageUrl!.trim().isNotEmpty;

    return Row(
      children: [
        // WHY: Show the user their current avatar so the upload action is clear.
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.green.shade100,
          backgroundImage: hasImage ? NetworkImage(profileImageUrl!) : null,
          child: hasImage
              ? null
              : Text(
                  initials,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                hasImage ? "Image uploaded" : "Upload a profile photo",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            ],
          ),
        ),
        // WHY: Keep the upload CTA visible even when an image exists.
        OutlinedButton.icon(
          onPressed: isUploading ? null : onUploadTap,
          icon: isUploading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload, size: 16),
          label: Text(isUploading ? "Uploading..." : "Upload"),
        ),
      ],
    );
  }
}

class _VerificationButton extends StatelessWidget {
  final bool isVerified;
  final String label;
  final VoidCallback onTap;

  const _VerificationButton({
    required this.isVerified,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isVerified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Text(
              "Verified",
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return OutlinedButton(onPressed: onTap, child: Text(label));
  }
}
