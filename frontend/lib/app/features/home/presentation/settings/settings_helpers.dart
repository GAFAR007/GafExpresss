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
  final raw = input.replaceAll(RegExp(r'\s+'), '').trim();
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final e164 = RegExp(r'^\+234\d{10}$');
  final local = RegExp(r'^0\d{10}$');
  final plain = RegExp(r'^234\d{10}$');
  final digitsOnly = RegExp(r'^\d{10}$');

  if (e164.hasMatch(raw)) return raw;
  if (local.hasMatch(raw)) return '+234${raw.substring(1)}';
  if (plain.hasMatch(raw)) return '+$raw';
  if (digitsOnly.hasMatch(digits)) return '+234$digits';

  return null;
}

String extractNigerianDigits(String input, {required int maxDigits}) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('234') && digits.length >= 13) {
    return digits.substring(3, 13);
  }
  if (digits.startsWith('0') && digits.length == 11) {
    return digits.substring(1);
  }
  if (digits.length <= maxDigits) {
    return digits;
  }
  return digits.substring(0, maxDigits);
}

String formatPhoneDisplay(
  String? rawPhone, {
  required String prefix,
  required int maxDigits,
}) {
  if (rawPhone == null || rawPhone.trim().isEmpty) {
    return '';
  }
  final digits = extractNigerianDigits(rawPhone, maxDigits: maxDigits);
  if (digits.isEmpty) {
    return '';
  }
  return "$prefix$digits";
}
