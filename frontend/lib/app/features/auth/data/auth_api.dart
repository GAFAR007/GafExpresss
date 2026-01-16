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

  /// ------------------------------------------------------
  /// ADMIN CHECK
  /// - Backend returns 200 only for admin users
  /// ------------------------------------------------------
  Future<bool> verifyAdmin({required String token}) async {
    // WHY: Avoid calling the backend with an empty token.
    if (token.trim().isEmpty) {
      AppDebug.log("AUTH_API", "verifyAdmin() missing token");
      return false;
    }

    AppDebug.log("AUTH_API", "verifyAdmin() start");

    try {
      final resp = await _dio.get(
        "/auth/admin-test",
        options: Options(
          headers: {"Authorization": "Bearer $token"},
        ),
      );

      final isAdmin = resp.statusCode == 200;

      AppDebug.log(
        "AUTH_API",
        "verifyAdmin() success",
        extra: {"isAdmin": isAdmin},
      );

      return isAdmin;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;

      // WHY: 401/403 means not admin or not authorized.
      if (status == 401 || status == 403) {
        AppDebug.log(
          "AUTH_API",
          "verifyAdmin() not admin",
          extra: {"status": status},
        );
        return false;
      }

      AppDebug.log(
        "AUTH_API",
        "verifyAdmin() failed",
        extra: {"status": status, "error": e.message ?? "unknown"},
      );

      // WHY: Fail closed so categories stay hidden on errors.
      return false;
    }
  }
}
