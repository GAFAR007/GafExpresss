/// lib/app/core/formatters/currency_formatter.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Centralized currency formatting helpers.
///
/// WHY:
/// - Keeps money display consistent across the app.
/// - Avoids copy/paste formatting logic in multiple screens.
///
/// HOW:
/// - Converts integer cents to NGN text with commas and 2 decimals.
/// - Parses formatted inputs and auto-formats rent fields.
/// ------------------------------------------------------------
library;

import 'package:flutter/services.dart';

// WHY: Keep kobo conversion consistent across money inputs.
const int _koboPerNaira = 100;
// WHY: Limit decimal precision for user inputs to avoid accidental extra cents.
const int _maxDecimalDigits = 2;

// WHY: Reuse the same thousands separator logic for input formatting.
String _formatWholeWithCommas(String digits) {
  if (digits.isEmpty) return "0";
  // WHY: Trim leading zeros so grouping stays predictable.
  final normalized = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final safe = normalized.isEmpty ? "0" : normalized;
  return safe.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ",",
  );
}

/// WHY: Format raw user input without forcing trailing decimals on every keystroke.
String formatNgnInputText(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return '';

  final hasTrailingDot = cleaned.endsWith('.');
  final dotIndex = cleaned.indexOf('.');

  String wholeRaw;
  String decimalRaw;
  if (dotIndex == -1) {
    wholeRaw = cleaned;
    decimalRaw = '';
  } else {
    wholeRaw = cleaned.substring(0, dotIndex);
    // WHY: Collapse extra dots so only the first is treated as the decimal.
    decimalRaw = cleaned.substring(dotIndex + 1).replaceAll('.', '');
  }

  final whole = _formatWholeWithCommas(wholeRaw);
  final decimals = decimalRaw.length > _maxDecimalDigits
      ? decimalRaw.substring(0, _maxDecimalDigits)
      : decimalRaw;

  if (decimals.isEmpty) {
    return hasTrailingDot ? "$whole." : whole;
  }

  return "$whole.$decimals";
}

/// WHY: We store monetary values in cents, then format safely for display.
String formatNgnFromCents(int priceCents) {
  final value = (priceCents / 100).toStringAsFixed(2);
  final parts = value.split(".");
  // WHY: Insert commas for readability on large values.
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ",",
  );
  final decimals = parts.length > 1 ? parts[1] : "00";
  return "NGN $whole.$decimals";
}

/// WHY: Some modules (estate rent, asset costs) store amounts in NGN directly.
String formatNgn(num amount) {
  final value = amount.toDouble().toStringAsFixed(2);
  final parts = value.split(".");
  // WHY: Insert commas for readability on large values.
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ",",
  );
  final decimals = parts.length > 1 ? parts[1] : "00";
  return "NGN $whole.$decimals";
}

/// WHY: Input fields should show formatted amounts without the currency prefix.
String formatNgnInput(num amount) {
  return formatNgn(amount).replaceFirst("NGN ", "");
}

/// WHY: Normalize stored kobo values for rent inputs in forms.
String formatNgnInputFromKobo(num kobo) {
  final naira = kobo / _koboPerNaira;
  return formatNgnInput(naira);
}

/// WHY: Parse formatted NGN inputs (commas/prefixes) safely.
double? parseNgnInput(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final cleaned = trimmed.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// WHY: Convert NGN input into kobo for storage (minor units).
int? parseNgnToKobo(String value) {
  final parsed = parseNgnInput(value);
  if (parsed == null) return null;
  return (parsed * _koboPerNaira).round();
}

/// WHY: Keep rent inputs readable by auto-formatting as the user types.
class NgnInputFormatter extends TextInputFormatter {
  const NgnInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.trim().isEmpty) {
      return const TextEditingValue(text: '');
    }

    // WHY: Preserve user intent while inserting thousand separators.
    final formatted = formatNgnInputText(newValue.text);
    if (formatted.isEmpty) {
      return const TextEditingValue(text: '');
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: formatted.length,
      ),
    );
  }
}
