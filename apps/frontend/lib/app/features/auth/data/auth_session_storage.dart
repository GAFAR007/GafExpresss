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
/// - Stores the last successful email + password under dedicated secure keys.
///
/// SAFETY:
/// - Never logs token or password and only keeps credentials in secure storage.
/// ------------------------------------------------------------
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/app/core/debug/app_debug.dart';

import '../domain/models/auth_session.dart';

class StoredLoginCredentials {
  final String? email;
  final String? password;
  final Map<String, String> passwordsByEmail;

  const StoredLoginCredentials({
    this.email,
    this.password,
    this.passwordsByEmail = const {},
  });

  bool matchesEmail(String email) {
    final normalizedStoredEmail = (this.email ?? '').trim().toLowerCase();
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedStoredEmail.isEmpty || normalizedEmail.isEmpty) {
      return false;
    }
    return normalizedStoredEmail == normalizedEmail;
  }

  String? passwordFor(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      return null;
    }

    final rememberedPassword =
        passwordsByEmail[normalizedEmail] ??
        (matchesEmail(email) ? password : null);
    final trimmedPassword = (rememberedPassword ?? '').trim();
    if (trimmedPassword.isEmpty) {
      return null;
    }
    return rememberedPassword;
  }

  StoredLoginCredentials withSavedPassword({
    required String email,
    required String password,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      return this;
    }

    return StoredLoginCredentials(
      email: email.trim(),
      password: password,
      passwordsByEmail: {...passwordsByEmail, normalizedEmail: password},
    );
  }
}

class AuthSessionStorage {
  // WHY: Use consistent keys for read/write/clear.
  static const String _tokenKey = "auth_token";
  static const String _userKey = "auth_user";
  static const String _lastEmailKey = "auth_last_email";
  static const String _lastPasswordKey = "auth_last_password";
  static const String _lastPasswordEmailKey = "auth_last_password_email";
  static const String _savedPasswordsKey = "auth_saved_passwords";
  static const String _pendingInviteKey = "auth_pending_invite";

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
  /// SAVE LAST PASSWORD
  /// ------------------------------------------------------
  Future<void> saveLastPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      AppDebug.log("AUTH_STORAGE", "Skipped saveLastPassword (missing data)");
      return;
    }

    AppDebug.log("AUTH_STORAGE", "Saving last password");
    final savedPasswords = await _readSavedPasswordMap();
    savedPasswords[normalizedEmail] = password;
    await _writeSavedPasswordMap(savedPasswords);
    await _storage.write(key: _lastPasswordKey, value: password);
    await _storage.write(key: _lastPasswordEmailKey, value: normalizedEmail);
  }

  /// ------------------------------------------------------
  /// SAVE LAST LOGIN CREDENTIALS
  /// ------------------------------------------------------
  Future<void> saveLastCredentials({
    required String email,
    required String password,
  }) async {
    await saveLastEmail(email);
    await saveLastPassword(email: email, password: password);
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
  /// READ LAST PASSWORD
  /// ------------------------------------------------------
  Future<String?> readLastPassword({String? forEmail}) async {
    AppDebug.log("AUTH_STORAGE", "Reading last password");

    final targetEmail = (forEmail ?? "").trim().toLowerCase();
    final savedPasswords = await _readSavedPasswordMap();
    final savedPassword = savedPasswords[targetEmail];
    if ((savedPassword ?? '').isNotEmpty) {
      return savedPassword;
    }

    final password = await _storage.read(key: _lastPasswordKey);
    final passwordEmail = await _storage.read(key: _lastPasswordEmailKey);
    if (password == null || password.isEmpty) {
      AppDebug.log("AUTH_STORAGE", "No last password found");
      return null;
    }

    final normalizedPasswordEmail = (passwordEmail ?? "").trim().toLowerCase();
    if (targetEmail.isNotEmpty &&
        normalizedPasswordEmail.isNotEmpty &&
        normalizedPasswordEmail != targetEmail) {
      AppDebug.log("AUTH_STORAGE", "Skipped last password (email mismatch)");
      return null;
    }

    return password;
  }

  /// ------------------------------------------------------
  /// READ LAST LOGIN CREDENTIALS
  /// ------------------------------------------------------
  Future<StoredLoginCredentials> readLastCredentials() async {
    AppDebug.log("AUTH_STORAGE", "Reading last credentials");

    final email = await readLastEmail();
    final savedPasswords = await _readSavedPasswordMap();
    if (email == null || email.isEmpty) {
      return StoredLoginCredentials(passwordsByEmail: savedPasswords);
    }

    final password = await readLastPassword(forEmail: email);
    final normalizedEmail = email.trim().toLowerCase();

    return StoredLoginCredentials(
      email: email,
      password: password,
      passwordsByEmail: {
        ...savedPasswords,
        if ((password ?? '').isNotEmpty) normalizedEmail: password!,
      },
    );
  }

  /// ------------------------------------------------------
  /// CLEAR LAST EMAIL
  /// ------------------------------------------------------
  Future<void> clearLastEmail() async {
    AppDebug.log("AUTH_STORAGE", "Clearing last email");
    await _storage.delete(key: _lastEmailKey);
  }

  /// ------------------------------------------------------
  /// CLEAR LAST PASSWORD
  /// ------------------------------------------------------
  Future<void> clearLastPassword() async {
    AppDebug.log("AUTH_STORAGE", "Clearing last password");
    await _storage.delete(key: _lastPasswordKey);
    await _storage.delete(key: _lastPasswordEmailKey);
    await _storage.delete(key: _savedPasswordsKey);
  }

  /// ------------------------------------------------------
  /// SAVE PENDING INVITE TOKEN
  /// ------------------------------------------------------
  Future<void> savePendingInviteToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      AppDebug.log("AUTH_STORAGE", "Skipped savePendingInviteToken (empty)");
      return;
    }

    AppDebug.log("AUTH_STORAGE", "Saving pending invite token");
    await _storage.write(key: _pendingInviteKey, value: trimmed);
  }

  /// ------------------------------------------------------
  /// READ PENDING INVITE TOKEN
  /// ------------------------------------------------------
  Future<String?> readPendingInviteToken() async {
    AppDebug.log("AUTH_STORAGE", "Reading pending invite token");
    final token = await _storage.read(key: _pendingInviteKey);
    if (token == null || token.isEmpty) {
      AppDebug.log("AUTH_STORAGE", "No pending invite token found");
      return null;
    }
    return token;
  }

  /// ------------------------------------------------------
  /// CLEAR PENDING INVITE TOKEN
  /// ------------------------------------------------------
  Future<void> clearPendingInviteToken() async {
    AppDebug.log("AUTH_STORAGE", "Clearing pending invite token");
    await _storage.delete(key: _pendingInviteKey);
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

  Future<Map<String, String>> _readSavedPasswordMap() async {
    final rawValue = await _storage.read(key: _savedPasswordsKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) {
        return {};
      }

      final entries = <String, String>{};
      for (final entry in decoded.entries) {
        final email = entry.key.toString().trim().toLowerCase();
        final password = entry.value?.toString() ?? '';
        if (email.isEmpty || password.isEmpty) {
          continue;
        }
        entries[email] = password;
      }
      return entries;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeSavedPasswordMap(Map<String, String> passwords) async {
    await _storage.write(key: _savedPasswordsKey, value: jsonEncode(passwords));
  }
}
