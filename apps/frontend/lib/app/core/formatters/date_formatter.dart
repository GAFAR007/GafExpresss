/// lib/app/core/formatters/date_formatter.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Centralized date formatting helpers for input/display.
///
/// WHY:
/// - Keeps date parsing/formatting consistent across screens.
/// - Avoids duplicating YYYY-MM-DD formatting logic.
///
/// HOW:
/// - Formats DateTime as ISO date (YYYY-MM-DD) for inputs.
/// - Formats DateTime labels for read-only display.
/// - Parses ISO date strings safely for form submissions.
/// ------------------------------------------------------------
library;

// WHY: Default fallback label when a date is unavailable.
const String kDateFallbackLabel = "N/A";
// WHY: Dash fallback keeps compact UI rows readable for missing timestamps.
const String kDateFallbackDash = "\u2014";
// WHY: Keep date picker ranges consistent across screens.
const int kDatePickerFirstYear = 1900;
// WHY: Limit forward selection to avoid unrealistic future dates.
const int kDatePickerLastYear = 2100;

/// WHY: Provide a consistent YYYY-MM-DD string for date inputs.
String formatDateInput(DateTime? value) {
  if (value == null) return '';
  return value.toLocal().toIso8601String().split('T').first;
}

/// WHY: Keep read-only date labels consistent with input formatting.
String formatDateLabel(
  DateTime? value, {
  String fallback = kDateFallbackLabel,
}) {
  if (value == null) return fallback;
  return formatDateInput(value);
}

/// WHY: Provide a consistent YYYY-MM-DD HH:mm label for timelines/audits.
String formatDateTimeLabel(
  DateTime? value, {
  String fallback = kDateFallbackDash,
}) {
  if (value == null) return fallback;
  final local = value.toLocal();
  final date = formatDateInput(local);
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return "$date $hour:$minute";
}

/// WHY: Parse YYYY-MM-DD (or ISO) safely from text fields.
DateTime? parseDateInput(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed);
}
