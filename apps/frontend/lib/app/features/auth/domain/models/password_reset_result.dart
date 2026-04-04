/// lib/app/features/auth/domain/models/password_reset_result.dart
/// -------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Domain models for forgot-password request and confirmation responses.
///
/// WHY IT'S IMPORTANT:
/// - Keeps reset-flow parsing out of widgets.
/// - Gives the UI typed fields for generic status, expiry, and success messages.
///
/// HOW IT WORKS:
/// - `PasswordResetRequestResult` parses the public request response.
/// - `PasswordResetConfirmResult` parses the public confirmation response.
library;

class PasswordResetRequestResult {
  final String status;
  final String message;
  final String email;
  final DateTime? expiresAt;
  final String? debugCode;

  const PasswordResetRequestResult({
    required this.status,
    required this.message,
    required this.email,
    required this.expiresAt,
    required this.debugCode,
  });

  factory PasswordResetRequestResult.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequestResult(
      status: (json['status'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      // WHY: Expiry is optional because non-existent accounts keep the response generic.
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()),
      debugCode: (json['code'] ?? '').toString().trim().isEmpty
          ? null
          : (json['code'] ?? '').toString().trim(),
    );
  }
}

class PasswordResetConfirmResult {
  final String status;
  final String message;
  final String email;

  const PasswordResetConfirmResult({
    required this.status,
    required this.message,
    required this.email,
  });

  factory PasswordResetConfirmResult.fromJson(Map<String, dynamic> json) {
    return PasswordResetConfirmResult(
      status: (json['status'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}
