/// lib/app/features/home/presentation/settings/widgets/nin_id_card.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Compact identity card for verified NIN profiles.
///
/// WHY:
/// - Keeps the verified state clean while showing key identity fields.
///
/// HOW:
/// - Renders labeled rows (name, dob, email, phone, NIN last4).
/// - Annotates email/phone with verification status text.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:frontend/app/core/debug/app_debug.dart';

class NinIdCard extends StatelessWidget {
  final String firstName;
  final String middleName;
  final String lastName;
  final String dob;
  final String email;
  final bool isEmailVerified;
  final String phone;
  final bool isPhoneVerified;
  final String? ninLast4;
  final String? profileImageUrl;

  const NinIdCard({
    super.key,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.dob,
    required this.email,
    required this.isEmailVerified,
    required this.phone,
    required this.isPhoneVerified,
    required this.ninLast4,
    required this.profileImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Track rebuilds so verification UI issues are easy to trace.
    AppDebug.log(
      "NIN_ID_CARD",
      "build()",
      extra: {
        "emailVerified": isEmailVerified,
        "phoneVerified": isPhoneVerified,
        "hasNinLast4": (ninLast4 ?? '').isNotEmpty,
        "hasProfileImage": (profileImageUrl ?? '').trim().isNotEmpty,
      },
    );

    // WHY: Keep a single formatted name line for the card layout.
    final fullName = [
      firstName.trim(),
      middleName.trim(),
      lastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    // WHY: Use a compact badge icon instead of verbose "Verified" text.
    final verifiedIcon = Icon(
      Icons.verified,
      color: Colors.green.shade600,
      size: 16,
    );

    final hasProfileImage =
        profileImageUrl != null && profileImageUrl!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        // WHY: White card base keeps the design close to an ID layout.
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blueGrey.shade100),
        boxShadow: [
          // WHY: Soft shadow adds a physical card feel without heavy contrast.
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // WHY: Top bar mimics the ID header strip in the reference image.
          Stack(
            alignment: Alignment.topCenter,
            children: [
              Container(
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade400,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
              ),
              // WHY: Small notch keeps a subtle "badge" feel without extra UI.
              Positioned(
                top: 6,
                child: Container(
                  height: 12,
                  width: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade400, width: 2),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // WHY: Photo block anchors the layout and signals identity.
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueGrey.shade200),
                    image: hasProfileImage
                        ? DecorationImage(
                            image: NetworkImage(profileImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: hasProfileImage
                      ? null
                      : Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.blueGrey.shade300,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // WHY: Compact verified marker keeps the card clean.
                      Row(
                        children: [
                          Icon(
                            Icons.verified,
                            color: Colors.green.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Verified ID",
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey.shade700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _NinRow(label: "Name", value: _fallback(fullName)),
                      _NinRow(label: "DOB", value: _fallback(dob)),
                      _NinRow(
                        label: "Email",
                        value: email,
                        // WHY: Show the verified badge only when confirmed.
                        leading: isEmailVerified ? verifiedIcon : null,
                      ),
                      _NinRow(
                        label: "Phone",
                        value: phone.isEmpty ? "Not provided" : phone,
                        // WHY: Keep verified state visible without extra text.
                        leading: isPhoneVerified ? verifiedIcon : null,
                      ),
                      _NinRow(label: "NIN", value: "**** ${ninLast4 ?? '----'}"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fallback(String value) => value.isEmpty ? "-" : value;
}

class _NinRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? leading;

  const _NinRow({
    required this.label,
    required this.value,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep label/value pairs aligned for fast scanning.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // WHY: Fixed label width keeps the right column aligned.
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  // WHY: Keep the verification badge aligned with the value text.
                  leading!,
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blueGrey.shade800,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
