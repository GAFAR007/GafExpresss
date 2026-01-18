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
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Centralize status labels to keep row formatting consistent.
    final emailStatus = isEmailVerified ? "Verified" : "Not verified";
    final phoneStatus = isPhoneVerified ? "Verified" : "Not verified";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(
                "NIN Verified",
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _NinRow(label: "First name", value: _fallback(firstName)),
          _NinRow(label: "Middle name", value: _fallback(middleName)),
          _NinRow(label: "Last name", value: _fallback(lastName)),
          _NinRow(label: "DOB", value: _fallback(dob)),
          _NinRow(label: "Email", value: "$email ($emailStatus)"),
          _NinRow(
            label: "Phone",
            value: phone.isEmpty ? "Not provided" : "$phone ($phoneStatus)",
          ),
          _NinRow(label: "NIN", value: "**** ${ninLast4 ?? '----'}"),
        ],
      ),
    );
  }

  String _fallback(String value) => value.isEmpty ? "-" : value;
}

class _NinRow extends StatelessWidget {
  final String label;
  final String value;

  const _NinRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
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
    );
  }
}
