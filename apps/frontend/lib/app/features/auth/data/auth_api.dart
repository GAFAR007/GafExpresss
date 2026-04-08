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
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/password_reset_result.dart';
import 'package:frontend/app/features/auth/domain/models/login_shortcut_bundle.dart';

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
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    // Safe debug: email is OK, never log password or token.
    AppDebug.log("AUTH_API", "register() start", extra: {"email": email});

    final resp = await _dio.post(
      "/auth/register",
      data: {
        "firstName": firstName.trim(),
        "lastName": lastName.trim(),
        "email": email.trim(),
        "password": password, // DO NOT LOG THIS
        "confirmPassword": confirmPassword, // DO NOT LOG THIS
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

    try {
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
    } on DioException catch (error) {
      final message = _friendlyAuthErrorMessage(
        error,
        operation: "login",
        fallback: "We couldn't sign you in right now.",
      );
      AppDebug.log("AUTH_API", "login() failed", extra: {"error": message});
      throw Exception(message);
    }
  }

  /// ------------------------------------------------------
  /// LOGIN ACCOUNTS
  /// - Backend returns: { role, accounts[] }
  /// - Public route; fills the login form with real Mongo-backed account data
  /// ------------------------------------------------------
  Future<LoginShortcutBundle> fetchLoginShortcuts({
    required String role,
  }) async {
    AppDebug.log(
      "AUTH_API",
      "fetchLoginShortcuts() start",
      extra: {"role": role},
    );

    try {
      final resp = await _dio.get("/auth/login-accounts/$role");
      final data = resp.data as Map<String, dynamic>;
      final bundle = LoginShortcutBundle.fromJson(data);

      AppDebug.log(
        "AUTH_API",
        "fetchLoginShortcuts() success",
        extra: {"role": bundle.role, "count": bundle.accounts.length},
      );

      return bundle;
    } on DioException catch (error) {
      final message = _friendlyAuthErrorMessage(
        error,
        operation: "login_shortcuts",
        fallback: "Unable to load login accounts",
      );
      AppDebug.log(
        "AUTH_API",
        "fetchLoginShortcuts() failed",
        extra: {"role": role, "error": message},
      );
      throw Exception(message);
    }
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
        options: Options(headers: {"Authorization": "Bearer $token"}),
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

  /// ------------------------------------------------------
  /// REQUEST PASSWORD RESET
  /// - Backend returns: { message, status, email, expiresAt?, code? }
  /// - Public route; no auth token required
  /// ------------------------------------------------------
  Future<PasswordResetRequestResult> requestPasswordReset({
    required String email,
  }) async {
    AppDebug.log(
      "AUTH_API",
      "requestPasswordReset() start",
      extra: {"email": email},
    );

    try {
      final resp = await _dio.post(
        "/auth/password-reset/request",
        data: {"email": email.trim()},
      );

      final data = resp.data as Map<String, dynamic>;
      final result = PasswordResetRequestResult.fromJson(data);

      AppDebug.log(
        "AUTH_API",
        "requestPasswordReset() success",
        extra: {
          "status": result.status,
          "hasExpiry": result.expiresAt != null,
          "hasDebugCode": result.debugCode != null,
        },
      );

      return result;
    } on DioException catch (error) {
      final message = _friendlyAuthErrorMessage(
        error,
        operation: "password_reset_request",
        fallback: "Unable to send password reset code",
      );
      AppDebug.log(
        "AUTH_API",
        "requestPasswordReset() failed",
        extra: {"error": message},
      );
      throw Exception(message);
    }
  }

  /// ------------------------------------------------------
  /// CONFIRM PASSWORD RESET
  /// - Backend returns: { message, status, email }
  /// - Public route; no auth token required
  /// ------------------------------------------------------
  Future<PasswordResetConfirmResult> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    AppDebug.log(
      "AUTH_API",
      "confirmPasswordReset() start",
      extra: {"email": email, "hasCode": code.trim().isNotEmpty},
    );

    try {
      final resp = await _dio.post(
        "/auth/password-reset/confirm",
        data: {
          "email": email.trim(),
          "code": code.trim(),
          "newPassword": newPassword,
          "confirmPassword": confirmPassword,
        },
      );

      final data = resp.data as Map<String, dynamic>;
      final result = PasswordResetConfirmResult.fromJson(data);

      AppDebug.log(
        "AUTH_API",
        "confirmPasswordReset() success",
        extra: {"status": result.status},
      );

      return result;
    } on DioException catch (error) {
      final message = _friendlyAuthErrorMessage(
        error,
        operation: "password_reset_confirm",
        fallback: "Unable to reset password",
      );
      AppDebug.log(
        "AUTH_API",
        "confirmPasswordReset() failed",
        extra: {"error": message},
      );
      throw Exception(message);
    }
  }

  String _readErrorMessage(DioException error, {required String fallback}) {
    final data = error.response?.data;

    if (data is Map<String, dynamic>) {
      final backendError = (data["error"] ?? "").toString().trim();
      final backendMessage = (data["message"] ?? "").toString().trim();
      if (backendError.isNotEmpty) return backendError;
      if (backendMessage.isNotEmpty) return backendMessage;
    }

    final message = (error.message ?? "").trim();
    if (message.isNotEmpty) return message;

    return fallback;
  }

  String _friendlyAuthErrorMessage(
    DioException error, {
    required String operation,
    required String fallback,
  }) {
    final status = error.response?.statusCode ?? 0;

    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return "We couldn't reach the server. Check that the backend is running and try again.";
    }

    if (operation == "login" && status == 401) {
      return "Email or password is incorrect. Check your details and try again.";
    }

    if (status == 404) {
      if (operation == "password_reset_request" ||
          operation == "password_reset_confirm") {
        return "Password reset is not available yet on the backend. Restart the backend and try again.";
      }
      return "This action is temporarily unavailable. Refresh the app and try again.";
    }

    if (status >= 500) {
      return "The server hit a problem. Please try again in a moment.";
    }

    return _readErrorMessage(error, fallback: fallback);
  }
}
