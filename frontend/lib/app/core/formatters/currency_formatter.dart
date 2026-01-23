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
/// ------------------------------------------------------------
library;

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
