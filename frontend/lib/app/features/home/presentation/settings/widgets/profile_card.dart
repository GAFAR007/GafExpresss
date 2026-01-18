/// lib/app/features/home/presentation/settings/widgets/profile_card.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Profile header card for the Settings screen.
///
/// WHY:
/// - Keeps the Settings screen slim by extracting the header UI.
///
/// HOW:
/// - Displays initials, name, email, and account type badge.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

class ProfileCard extends StatelessWidget {
  final String displayName;
  final String email;
  final String accountTypeLabel;
  final String initials;

  const ProfileCard({
    super.key,
    required this.displayName,
    required this.email,
    required this.accountTypeLabel,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              accountTypeLabel,
              style: const TextStyle(
                color: Colors.white,
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
