/// lib/app/features/auth/data/auth_session_storage.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Secure local storage for AuthSession (token + user) and last email.
///
/// WHY:
/// - Keeps session across app restarts.
/// - Centralizes storage logic so providers stay clean.
/// - Remembers the last login email for faster sign-in.
///
/// HOW:
/// - Stores token and user JSON separately using flutter_secure_storage.
/// - Rebuilds AuthSession on load.
/// - Stores the last email under a dedicated key (no password saved).
///
/// SAFETY:
/// - Never logs token or password.
/// ------------------------------------------------------------
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/app/core/debug/app_debug.dart';

import '../domain/models/auth_session.dart';

class AuthSessionStorage {
  // WHY: Use consistent keys for read/write/clear.
  static const String _tokenKey = "auth_token";
  static const String _userKey = "auth_user";
  static const String _lastEmailKey = "auth_last_email";

  final FlutterSecureStorage _storage;

  AuthSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// ------------------------------------------------------
  /// SAVE SESSION
  /// ------------------------------------------------------
  Future<void> saveSession(AuthSession session) async {
    AppDebug.log("AUTH_STORAGE", "Saving session to secure storage");

    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(
      key: _userKey,
      value: jsonEncode(session.user.toJson()),
    );
  }

  /// ------------------------------------------------------
  /// SAVE LAST EMAIL
  /// ------------------------------------------------------
  Future<void> saveLastEmail(String email) async {
    // WHY: Never store empty values so prefill remains meaningful.
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      AppDebug.log("AUTH_STORAGE", "Skipped saveLastEmail (empty)");
      return;
    }

    AppDebug.log("AUTH_STORAGE", "Saving last email");
    await _storage.write(key: _lastEmailKey, value: trimmed);
  }

  /// ------------------------------------------------------
  /// READ LAST EMAIL
  /// ------------------------------------------------------
  Future<String?> readLastEmail() async {
    AppDebug.log("AUTH_STORAGE", "Reading last email");

    final email = await _storage.read(key: _lastEmailKey);
    if (email == null || email.isEmpty) {
      AppDebug.log("AUTH_STORAGE", "No last email found");
      return null;
    }

    return email;
  }

  /// ------------------------------------------------------
  /// CLEAR LAST EMAIL
  /// ------------------------------------------------------
  Future<void> clearLastEmail() async {
    AppDebug.log("AUTH_STORAGE", "Clearing last email");
    await _storage.delete(key: _lastEmailKey);
  }

  /// ------------------------------------------------------
  /// READ SESSION
  /// ------------------------------------------------------
  Future<AuthSession?> readSession() async {
    AppDebug.log("AUTH_STORAGE", "Reading session from secure storage");

    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);

    // WHY: If any piece is missing, treat session as invalid.
    if (token == null ||
        token.isEmpty ||
        userJson == null ||
        userJson.isEmpty) {
      AppDebug.log("AUTH_STORAGE", "No stored session found");
      return null;
    }

    final userMap = jsonDecode(userJson) as Map<String, dynamic>;

    // Reuse AuthSession parser to validate token + user.
    return AuthSession.fromJson({"token": token, "user": userMap});
  }

  /// ------------------------------------------------------
  /// CLEAR SESSION
  /// ------------------------------------------------------
  Future<void> clearSession() async {
    AppDebug.log("AUTH_STORAGE", "Clearing session from secure storage");

    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
