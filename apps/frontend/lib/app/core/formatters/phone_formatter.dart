/// lib/app/core/formatters/phone_formatter.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Phone formatting helpers for Nigerian numbers.
///
/// WHY:
/// - Keeps phone normalization consistent across screens.
/// - Centralizes input formatting and display helpers.
///
/// HOW:
/// - Normalizes to +234 format.
/// - Extracts local digits for UI input.
/// - Provides a TextInputFormatter for digits-only input.
/// ------------------------------------------------------------
library;

import 'package:flutter/services.dart';

String? normalizeNigerianPhone(String input) {
  // WHY: Normalize to a single +234 E.164 representation.
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
  // WHY: Keep only the local 10 digits for display/input.
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
  // WHY: Display consistent +234 prefix with local digits.
  if (rawPhone == null || rawPhone.trim().isEmpty) {
    return '';
  }
  final digits = extractNigerianDigits(rawPhone, maxDigits: maxDigits);
  if (digits.isEmpty) {
    return '';
  }
  return "$prefix$digits";
}

/// ------------------------------------------------------------
/// PHONE INPUT FORMATTER
/// ------------------------------------------------------------
/// WHY:
/// - Keep phone fields digits-only while supporting pasted +234/0 prefixes.
class NigerianPhoneDigitsFormatter extends TextInputFormatter {
  final int maxDigits;

  const NigerianPhoneDigitsFormatter({required this.maxDigits});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // WHY: Strip non-digit characters so the UI only stores numbers.
    final rawDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var digits = rawDigits;

    // WHY: Remove common Nigerian prefixes when pasted.
    if (digits.startsWith('234')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('0') && digits.length == maxDigits + 1) {
      digits = digits.substring(1);
    }

    if (digits.length > maxDigits) {
      digits = digits.substring(0, maxDigits);
    }

    // WHY: Keep cursor at the end for predictable input with +234 prefix.
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
