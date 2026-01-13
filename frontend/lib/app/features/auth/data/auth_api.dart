/// lib/app/features/auth/data/auth_api.dart
/// ------------------------------------------------------------
/// WHAT:
/// - AuthApi talks to backend endpoints.
///
/// WHY:
/// - UI must never call Dio directly.
/// - Keeps your API contract in one place.
///
/// HOW:
/// - Each method calls a backend endpoint and parses into domain models.
///
/// IMPORTANT:
/// - register() returns AuthUser (NO token from backend)
/// - login() returns AuthSession (token required)
/// - login() backend shape today: { message, token, user }
///
/// DEBUGGING:
/// - Logs start/end for each call.
/// - Never logs passwords or tokens.

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

import '../domain/models/auth_user.dart';
import '../domain/models/auth_session.dart';

class AuthApi {
  final Dio _dio;

  AuthApi({required Dio dio}) : _dio = dio;

  /// ------------------------------------------------------
  /// REGISTER
  /// - Backend returns: { message, user }
  /// - Token is NOT returned (this is OK)
  /// ------------------------------------------------------
  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    // Safe debug: email is OK, never log password or token.
    AppDebug.log("AUTH_API", "register() start", extra: {"email": email});

    final resp = await _dio.post(
      "/auth/register",
      data: {
        "name": name.trim(),
        "email": email.trim(),
        "password": password, // DO NOT LOG THIS
      },
    );

    final data = (resp.data as Map<String, dynamic>);
    final userMap = (data["user"] ?? {}) as Map<String, dynamic>;

    // Backend MUST return user.
    if (userMap.isEmpty) {
      throw Exception("Register response missing 'user'");
    }

    final user = AuthUser.fromJson(userMap);

    AppDebug.log("AUTH_API", "register() success", extra: {"userId": user.id});

    return user;
  }

  /// ------------------------------------------------------
  /// LOGIN
  /// - Backend currently returns: { message, token, user }
  /// - Token is REQUIRED (login fails if missing/expired)
  /// ------------------------------------------------------
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    // Safe debug: email is OK, never log password or token.
    AppDebug.log("AUTH_API", "login() start", extra: {"email": email});

    final resp = await _dio.post(
      "/auth/login",
      data: {
        "email": email.trim(),
        "password": password, // DO NOT LOG THIS
      },
    );

    final data = resp.data as Map<String, dynamic>;

    // Delegate ALL parsing logic to AuthSession:
    // - Handles missing token (OK for now)
    // - Throws if user is missing (not OK)
    final session = AuthSession.fromJson(data);

    AppDebug.log(
      "AUTH_API",
      "login() success",
      extra: {"userId": session.user.id},
    );

    return session;
  }
}
