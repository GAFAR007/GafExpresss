/// lib/app/features/auth/domain/models/auth_session.dart
/// ------------------------------------------------------
/// WHAT THIS FILE IS:
/// - AuthSession is the “logged-in state payload”.
/// - It can contain:
///   1) `user`  (always required)
///   2) `token` (nullable for now because your backend doesn’t return it yet)
///
/// WHY THIS EXISTS:
/// - Your UI/providers need ONE consistent model after login.
/// - Register does NOT return a token in your backend → Register returns AuthUser only.
/// - Login MAY return token later → so we design AuthSession to support both NOW and LATER.
///
/// IMPORTANT NOTE (CURRENT BACKEND):
/// - Your backend currently returns: { message, user }
/// - It does NOT return: { token, user }
/// - So `token` MUST be nullable to avoid crashing.
///
/// LATER (WHEN YOU ADD JWT):
/// - Backend can return:
///   { token: "...", user: {...} }
///   OR { accessToken: "...", user: {...} }
/// - This file already supports those without changing UI again.
///
/// DEBUGGING:
/// - We log ONLY safe info (never log token/password).
/// - If token is missing, we log that this is expected for now.
/// ------------------------------------------------------

import 'package:frontend/app/core/debug/app_debug.dart';
import 'auth_user.dart';

class AuthSession {
  /// ✅ Nullable for now because your backend login response has NO token yet.
  /// Later, once backend returns token, this will be non-null.
  final String? token;

  /// ✅ Always required: backend returns `user` after login.
  final AuthUser user;

  const AuthSession({required this.user, this.token});

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
  /// - Reads user from json['user'] (your current backend shape)
  /// - Throws a clear error if user is missing
  ///
  /// SAFETY:
  /// - NEVER logs token.
  /// ------------------------------------------------------
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    // ✅ Token can appear under different names depending on backend.
    final dynamic rawToken =
        json['token'] ?? json['accessToken'] ?? json['access_token'];

    final String? token = rawToken?.toString();

    // ✅ Your current backend returns user at top-level: { message, user }
    final Map<String, dynamic> userMap =
        (json['user'] ?? <String, dynamic>{}) as Map<String, dynamic>;

    // ✅ If user is missing, login is not valid for our app.
    if (userMap.isEmpty) {
      throw Exception("Login response missing 'user'");
    }

    // ✅ Helpful debug: confirms why token is null (expected right now).
    if (token == null) {
      AppDebug.log(
        "AUTH_SESSION",
        "No token in login response (OK for now — backend returns {message, user})",
      );
    } else {
      // We only log that token exists, NOT the token itself.
      AppDebug.log("AUTH_SESSION", "Token present in login response");
    }

    return AuthSession(user: AuthUser.fromJson(userMap), token: token);
  }
}
