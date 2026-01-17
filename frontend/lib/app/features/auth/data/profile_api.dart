/// lib/app/features/auth/data/profile_api.dart
/// ------------------------------------------------------------
/// WHAT:
/// - ProfileApi talks to backend profile endpoints.
///
/// WHY:
/// - Keeps Dio usage out of UI widgets.
/// - Centralizes request/response parsing for profile data.
///
/// HOW:
/// - fetchProfile() hits GET /auth/profile
/// - updateProfile() hits PATCH /auth/profile
/// - Both return UserProfile models.
/// ------------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';

class ProfileApi {
  final Dio _dio;

  ProfileApi({required Dio dio}) : _dio = dio;

  /// ------------------------------------------------------
  /// FETCH PROFILE
  /// ------------------------------------------------------
  Future<UserProfile> fetchProfile({required String token}) async {
    // WHY: Avoid calling the backend with an empty token.
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "fetchProfile() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log("PROFILE_API", "fetchProfile() start");

    final resp = await _dio.get(
      "/auth/profile",
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final profileMap =
        (data["profile"] ?? data["user"] ?? {}) as Map<String, dynamic>;

    if (profileMap.isEmpty) {
      throw Exception("Profile response missing data");
    }

    final profile = UserProfile.fromJson(profileMap);

    AppDebug.log(
      "PROFILE_API",
      "fetchProfile() success",
      extra: {"userId": profile.id},
    );

    return profile;
  }

  /// ------------------------------------------------------
  /// UPDATE PROFILE
  /// ------------------------------------------------------
  Future<UserProfile> updateProfile({
    required String token,
    required UserProfile profile,
  }) async {
    // WHY: Avoid calling the backend with an empty token.
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "updateProfile() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log(
      "PROFILE_API",
      "updateProfile() start",
      extra: {"userId": profile.id},
    );

    final resp = await _dio.patch(
      "/auth/profile",
      data: profile.toUpdateJson(),
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final profileMap =
        (data["profile"] ?? data["user"] ?? {}) as Map<String, dynamic>;

    if (profileMap.isEmpty) {
      throw Exception("Profile update response missing data");
    }

    final updated = UserProfile.fromJson(profileMap);

    AppDebug.log(
      "PROFILE_API",
      "updateProfile() success",
      extra: {"userId": updated.id},
    );

    return updated;
  }
}
