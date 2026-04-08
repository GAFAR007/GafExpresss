/// lib/app/features/home/presentation/settings/settings_helpers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Pure helper utilities for Settings screen formatting and parsing.
///
/// WHY:
/// - Keeps Settings UI lean by moving repeated logic into one place.
///
/// HOW:
/// - Provides name splitting, initials, and Nigerian phone formatting.
/// ------------------------------------------------------------
library;

import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/core/formatters/phone_formatter.dart'
    as phone_formatter;

class SplitName {
  final String firstName;
  final String lastName;

  const SplitName(this.firstName, this.lastName);
}

SplitName splitFullName(String? firstName, String? lastName, String? fullName) {
  final cleanFirst = (firstName ?? '').trim();
  final cleanLast = (lastName ?? '').trim();

  if (cleanFirst.isNotEmpty || cleanLast.isNotEmpty) {
    return SplitName(cleanFirst, cleanLast);
  }

  final cleanFull = (fullName ?? '').trim();
  if (cleanFull.isEmpty) {
    return const SplitName('', '');
  }

  final parts =
      cleanFull.split(' ').where((part) => part.isNotEmpty).toList();
  if (parts.length == 1) {
    return SplitName(parts.first, '');
  }

  return SplitName(parts.first, parts.sublist(1).join(' '));
}

String initialsForProfile(UserProfile profile) {
  final split = splitFullName(profile.firstName, profile.lastName, profile.name);
  final combined = "${split.firstName} ${split.lastName}".trim();
  if (combined.isEmpty) return 'GU';
  final parts = combined.split(' ').where((part) => part.isNotEmpty).toList();
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return "${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}"
      .toUpperCase();
}

String? normalizeNigerianPhone(String input) {
  // WHY: Reuse the shared formatter so all screens normalize consistently.
  return phone_formatter.normalizeNigerianPhone(input);
}

String extractNigerianDigits(String input, {required int maxDigits}) {
  // WHY: Reuse the shared formatter so display stays consistent.
  return phone_formatter.extractNigerianDigits(
    input,
    maxDigits: maxDigits,
  );
}

String formatPhoneDisplay(
  String? rawPhone, {
  required String prefix,
  required int maxDigits,
}) {
  // WHY: Delegate to shared formatter for consistent output.
  return phone_formatter.formatPhoneDisplay(
    rawPhone,
    prefix: prefix,
    maxDigits: maxDigits,
  );
}
