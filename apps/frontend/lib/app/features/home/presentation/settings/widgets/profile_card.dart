/// lib/app/features/home/presentation/settings/widgets/profile_card.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Profile header card for the Settings screen.
///
/// WHY:
/// - Keeps the Settings screen slim by extracting the header UI.
///
/// HOW:
/// - Displays initials, name, email, and optional account type badge.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

class ProfileCard extends StatelessWidget {
  final String displayName;
  final String email;
  final String? accountTypeLabel;
  final String initials;
  final String? profileImageUrl;
  final VoidCallback? onAvatarTap;
  final bool showUploadButton;

  const ProfileCard({
    super.key,
    required this.displayName,
    required this.email,
    this.accountTypeLabel,
    required this.initials,
    this.profileImageUrl,
    this.onAvatarTap,
    this.showUploadButton = false,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Hide the badge when account type editing is disabled in Settings.
    final hasAccountType =
        accountTypeLabel != null && accountTypeLabel!.trim().isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 26,
              backgroundColor: scheme.onPrimary.withOpacity(0.18),
              backgroundImage: (profileImageUrl != null &&
                      profileImageUrl!.trim().isNotEmpty)
                  ? NetworkImage(profileImageUrl!)
                  : null,
              child: (profileImageUrl != null &&
                      profileImageUrl!.trim().isNotEmpty)
                  ? null
                  : Text(
                      initials,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isEmpty ? "Guest user" : displayName,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(color: scheme.onPrimary.withOpacity(0.7)),
                ),
                if (showUploadButton && onAvatarTap != null) ...[
                  const SizedBox(height: 8),
                  // WHY: Explicit upload control is clearer than relying on avatar tap.
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onPrimary,
                      side: BorderSide(
                        color: scheme.onPrimary.withOpacity(0.6),
                      ),
                    ),
                    onPressed: onAvatarTap,
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text("Upload"),
                  ),
                ],
              ],
            ),
          ),
          if (hasAccountType)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                accountTypeLabel!,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
