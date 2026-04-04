/// lib/app/features/auth/domain/models/auth_session.dart
/// ------------------------------------------------------
/// WHAT THIS FILE IS:
/// - AuthSession is the “logged-in state payload”.
/// - It can contain:
///   1) `user`  (always required)
///   2) `token` (required for login; validated here)
///
/// WHY THIS EXISTS:
/// - Your UI/providers need ONE consistent model after login.
/// - Register does NOT return a token in your backend → Register returns AuthUser only.
/// - Login MUST return a token (reject if missing/expired).
///
/// IMPORTANT NOTE (CURRENT BACKEND):
/// - Backend returns: { message, token, user }
/// - If token is missing or expired, login must fail.
///
/// LATER (TOKEN VARIANTS):
/// - Backend can return:
///   { token: "...", user: {...} }
///   OR { accessToken: "...", user: {...} }
/// - This file already supports those without changing UI again.
///
/// DEBUGGING:
/// - We log ONLY safe info (never log token/password).
/// - We log token validation outcome (safe only).
/// ------------------------------------------------------
library;

import 'dart:convert';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'auth_user.dart';

class AuthSession {
  /// ✅ Required for login; validated (present + not expired).
  final String token;

  /// ✅ Always required: backend returns `user` after login.
  final AuthUser user;

  const AuthSession({required this.user, required this.token});

  /// ------------------------------------------------------
  /// WHAT THIS DOES:
  /// - Converts backend JSON into AuthSession.
  ///
  /// WHY THIS EXISTS:
  /// - Keeps parsing rules in one place, so UI stays clean.
  ///
  /// HOW IT WORKS:
  /// - Tries token keys that backends commonly use:
  ///   token / accessToken / access_token
  /// - Reads user from json['user'] (current backend shape)
  /// - Validates JWT expiry (exp)
  /// - Throws a clear error if token/user are missing or expired
  ///
  /// SAFETY:
  /// - NEVER logs token.
  /// ------------------------------------------------------
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    // ✅ Token can appear under different names depending on backend.
    final dynamic rawToken =
        json['token'] ?? json['accessToken'] ?? json['access_token'];

    final String token = (rawToken ?? '').toString().trim();

    // ✅ Your current backend returns user at top-level: { message, user }
    final Map<String, dynamic> userMap =
        (json['user'] ?? <String, dynamic>{}) as Map<String, dynamic>;

    // ✅ If token is missing, login is NOT valid for our app.
    if (token.isEmpty) {
      AppDebug.log("AUTH_SESSION", "Missing token in login response");
      throw Exception("Login response missing 'token'");
    }

    // ✅ If user is missing, login is not valid for our app.
    if (userMap.isEmpty) {
      throw Exception("Login response missing 'user'");
    }

    // ✅ Validate JWT expiry before accepting session.
    final int? exp = _parseJwtExp(token);
    if (exp == null) {
      AppDebug.log("AUTH_SESSION", "Token missing/invalid exp claim");
      throw Exception("Login token missing 'exp' claim");
    }

    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp <= nowSec) {
      AppDebug.log("AUTH_SESSION", "Token expired", extra: {"exp": exp});
      throw Exception("Login token expired");
    }

    AppDebug.log(
      "AUTH_SESSION",
      "Token validated",
      extra: {"exp": exp, "now": nowSec},
    );

    return AuthSession(user: AuthUser.fromJson(userMap), token: token);
  }

  /// ------------------------------------------------------
  /// WHAT:
  /// - Returns true if token is still valid (not expired).
  ///
  /// WHY:
  /// - Router guards and session restore must block expired tokens.
  /// ------------------------------------------------------
  bool get isTokenValid {
    final int? exp = _parseJwtExp(token);
    if (exp == null) return false;

    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return exp > nowSec;
  }

  /// Token expiry as seconds since epoch (JWT exp).
  ///
  /// WHY:
  /// - Allows controllers to schedule auto-logout.
  int? get tokenExpirySeconds {
    return _parseJwtExp(token);
  }

  /// ------------------------------------------------------
  /// WHAT:
  /// - Converts AuthSession into JSON for local storage.
  ///
  /// WHY:
  /// - Enables session persistence across app restarts.
  ///
  /// SAFETY:
  /// - Token is stored via secure storage layer (not logged).
  /// ------------------------------------------------------
  Map<String, dynamic> toJson() {
    return {"token": token, "user": user.toJson()};
  }

  /// ------------------------------------------------------
  /// JWT EXP PARSER (SAFE)
  /// ------------------------------------------------------
  /// WHY:
  /// - We must reject expired tokens immediately.
  /// - We do NOT depend on external packages for this.
  ///
  /// HOW:
  /// - Decode payload (middle JWT segment)
  /// - Read "exp" (seconds since epoch)
  /// ------------------------------------------------------
  static int? _parseJwtExp(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;

    try {
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decoded);

      if (data is! Map<String, dynamic>) return null;

      final exp = data['exp'];
      if (exp is int) return exp;
      if (exp is num) return exp.toInt();
      if (exp is String) return int.tryParse(exp);
    } catch (_) {
      return null;
    }

    return null;
  }
}
