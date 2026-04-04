/// lib/app/core/formatters/email_formatter.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Email input formatter helpers.
///
/// WHY:
/// - Blocks invalid characters at input time.
/// - Normalizes emails consistently before submission.
///
/// HOW:
/// - Filters disallowed characters.
/// - Provides a normalize helper for trimming + lowercasing.
/// ------------------------------------------------------------
library;

import 'package:flutter/services.dart';

// WHY: Allow common email characters and block spaces/special symbols.
final RegExp _allowedEmailChars =
    RegExp(r'[a-zA-Z0-9@._+\-]');

String normalizeEmail(String input) {
  // WHY: Normalize to a consistent lowercase + trimmed value.
  return input.trim().toLowerCase();
}

class EmailInputFormatter extends TextInputFormatter {
  const EmailInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // WHY: Strip invalid characters to prevent malformed emails.
    final filtered = newValue.text
        .split('')
        .where((char) => _allowedEmailChars.hasMatch(char))
        .join();

    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}
