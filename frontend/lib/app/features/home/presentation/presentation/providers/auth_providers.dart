/// lib/app/features/home/presentation/presentation/providers/auth_providers.dart
/// ---------------------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Riverpod providers that “wire up” networking + AuthApi for the whole app.
///
/// WHY IT'S IMPORTANT:
/// - Keeps creation of Dio/AuthApi in ONE place.
/// - Prevents “import madness” across screens.
/// - Makes it easy to swap baseUrl per platform (Web / Android / iOS).
///
/// HOW IT WORKS:
/// - dioProvider -> creates a single Dio configured with correct baseUrl.
/// - authApiProvider -> builds AuthApi using the Dio from dioProvider.
///
/// DEBUGGING:
/// - Logs when providers are created so we know the app is wired correctly.
///
/// PLATFORM SAFETY:
/// - Works on Web, Android, iOS (no dart:io used here).
/// ---------------------------------------------------------------------------
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/network/dio_client.dart';
import 'package:frontend/app/features/auth/data/auth_api.dart';
import 'package:frontend/app/features/auth/data/auth_session_storage.dart';
import 'package:frontend/app/features/auth/data/profile_api.dart';
import 'package:frontend/app/features/auth/domain/models/auth_session.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/address_autocomplete_api.dart';

/// Provides ONE Dio instance for the app.
///
/// WHY:
/// - Dio holds interceptors, baseUrl, timeouts.
/// - We want ONE consistent networking setup everywhere.
final dioProvider = Provider((ref) {
  AppDebug.log("PROVIDERS", "dioProvider created -> building Dio");
  final dio = buildDio(); // from lib/app/core/network/dio_client.dart
  AppDebug.log("PROVIDERS", "dioProvider ready");
  return dio;
});

/// Provides AuthApi using the shared Dio.
///
/// WHY:
/// - Screens should never create Dio/AuthApi manually.
/// - They just do: ref.read(authApiProvider).login(...)
final authApiProvider = Provider((ref) {
  AppDebug.log("PROVIDERS", "authApiProvider created -> building AuthApi");
  final dio = ref.read(dioProvider);
  final api = AuthApi(dio: dio);
  AppDebug.log("PROVIDERS", "authApiProvider ready");
  return api;
});

/// Provides ProfileApi using the shared Dio.
///
/// WHY:
/// - Profile calls should reuse the same Dio config.
final profileApiProvider = Provider((ref) {
  AppDebug.log(
    "PROVIDERS",
    "profileApiProvider created -> building ProfileApi",
  );
  final dio = ref.read(dioProvider);
  final api = ProfileApi(dio: dio);
  AppDebug.log("PROVIDERS", "profileApiProvider ready");
  return api;
});

/// Provides AddressAutocompleteApi using the shared Dio.
///
/// WHY:
/// - Keeps address suggestion networking centralized.
final addressAutocompleteApiProvider = Provider((ref) {
  AppDebug.log(
    "PROVIDERS",
    "addressAutocompleteApiProvider created -> building AddressAutocompleteApi",
  );
  final dio = ref.read(dioProvider);
  final api = AddressAutocompleteApi(dio: dio);
  AppDebug.log("PROVIDERS", "addressAutocompleteApiProvider ready");
  return api;
});

/// Provides secure session storage.
///
/// WHY:
/// - Keeps token/user persistence in one place.
final authSessionStorageProvider = Provider<AuthSessionStorage>((ref) {
  AppDebug.log("PROVIDERS", "authSessionStorageProvider created");
  return AuthSessionStorage();
});

/// ------------------------------------------------------------
/// AUTH SESSION CONTROLLER
/// ------------------------------------------------------------
/// WHAT:
/// - Holds the current AuthSession (token + user).
///
/// WHY:
/// - Router and UI need a single source of truth for login state.
/// - Enables logout + session restore.
///
/// DEBUGGING:
/// - Logs when session is set/cleared/restored.
class AuthSessionController extends StateNotifier<AuthSession?> {
  final AuthSessionStorage _storage;
  Timer? _expiryTimer;

  AuthSessionController(this._storage) : super(null);

  /// Restore session from secure storage.
  ///
  /// WHY:
  /// - Keeps users logged in across app restarts.
  Future<void> restoreSession() async {
    AppDebug.log("AUTH_SESSION", "restoreSession() start");

    try {
      final session = await _storage.readSession();

      if (session == null || !session.isTokenValid) {
        AppDebug.log("AUTH_SESSION", "No valid stored session");
        state = null;
        await _storage.clearSession();
        return;
      }

      state = session;
      _scheduleAutoLogout(session);
      AppDebug.log(
        "AUTH_SESSION",
        "Session restored",
        extra: {"userId": session.user.id},
      );
    } catch (e) {
      // WHY: Any parse/expiry error should reset session cleanly.
      AppDebug.log(
        "AUTH_SESSION",
        "restoreSession() failed",
        extra: {"error": e.toString()},
      );
      state = null;
      await _storage.clearSession();
    }
  }

  /// Save session after login.
  Future<void> setSession(AuthSession session) async {
    AppDebug.log(
      "AUTH_SESSION",
      "setSession()",
      extra: {"userId": session.user.id},
    );
    state = session;
    _scheduleAutoLogout(session);
    await _storage.saveSession(session);
  }

  /// Clear session on logout.
  Future<void> logout() async {
    AppDebug.log("AUTH_SESSION", "logout()");
    state = null;
    _expiryTimer?.cancel();
    await _storage.clearSession();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  /// ----------------------------------------------------------
  /// AUTO LOGOUT SCHEDULER
  /// ----------------------------------------------------------
  /// WHY:
  /// - Token exp should immediately block protected routes.
  void _scheduleAutoLogout(AuthSession session) {
    _expiryTimer?.cancel();

    final exp = session.tokenExpirySeconds;
    if (exp == null) {
      AppDebug.log("AUTH_SESSION", "Token missing exp for auto-logout");
      return;
    }

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final secondsLeft = exp - nowSec;

    if (secondsLeft <= 0) {
      AppDebug.log("AUTH_SESSION", "Token already expired -> logout");
      // Avoid awaiting inside sync context.
      Future.microtask(() => logout());
      return;
    }

    AppDebug.log(
      "AUTH_SESSION",
      "Auto-logout scheduled",
      extra: {"secondsLeft": secondsLeft},
    );

    _expiryTimer = Timer(Duration(seconds: secondsLeft), () async {
      AppDebug.log("AUTH_SESSION", "Token expired -> auto logout");
      await logout();
    });
  }
}

/// Provides the current auth session (null when logged out).
final authSessionProvider =
    StateNotifierProvider<AuthSessionController, AuthSession?>((ref) {
      AppDebug.log("PROVIDERS", "authSessionProvider created");
      final storage = ref.read(authSessionStorageProvider);
      return AuthSessionController(storage);
    });

/// ------------------------------------------------------------
/// PROFILE PROVIDER
/// ------------------------------------------------------------
/// WHAT:
/// - Fetches the current user's profile for settings screens.
///
/// WHY:
/// - Keeps profile fetching centralized and cacheable.
///
/// DEBUGGING:
/// - Logs start, missing session, and success.
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  AppDebug.log("PROVIDERS", "userProfileProvider fetch start");

  final session = ref.watch(authSessionProvider);
  if (session == null) {
    AppDebug.log("PROVIDERS", "userProfileProvider missing session");
    return null;
  }

  // WHY: Avoid backend calls when token is already expired.
  if (!session.isTokenValid) {
    AppDebug.log("PROVIDERS", "userProfileProvider token invalid");
    return null;
  }

  final api = ref.read(profileApiProvider);
  final profile = await api.fetchProfile(token: session.token);

  AppDebug.log(
    "PROVIDERS",
    "userProfileProvider success",
    extra: {"userId": profile.id},
  );

  return profile;
});

/// ------------------------------------------------------------
/// ADMIN CHECK PROVIDER
/// ------------------------------------------------------------
/// WHAT:
/// - Verifies admin role via backend (/auth/admin-test).
///
/// WHY:
/// - Keeps UI logic honest by using server validation.
/// - Prevents relying only on client-side role checks.
///
/// HOW:
/// - Uses AuthApi.verifyAdmin with the current token.
/// - Returns false when session is missing or invalid.
///
/// DEBUGGING:
/// - Logs start + outcome for visibility.
final isAdminProvider = FutureProvider<bool>((ref) async {
  AppDebug.log("PROVIDERS", "isAdminProvider fetch start");

  final session = ref.watch(authSessionProvider);
  if (session == null) {
    AppDebug.log("PROVIDERS", "isAdminProvider missing session");
    return false;
  }

  // WHY: Avoid backend calls when token is already expired.
  if (!session.isTokenValid) {
    AppDebug.log("PROVIDERS", "isAdminProvider token invalid");
    return false;
  }

  final api = ref.read(authApiProvider);
  final isAdmin = await api.verifyAdmin(token: session.token);

  AppDebug.log(
    "PROVIDERS",
    "isAdminProvider success",
    extra: {"isAdmin": isAdmin},
  );

  return isAdmin;
});
