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

  /// ------------------------------------------------------
  /// ADDRESS VERIFICATION
  /// ------------------------------------------------------
  Future<UserProfile> verifyAddress({
    required String token,
    required String type,
    required UserAddress address,
    String? placeId,
  }) async {
    // WHY: Avoid calling the backend with an empty token.
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "verifyAddress() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log(
      "PROFILE_API",
      "verifyAddress() start",
      extra: {"type": type},
    );

    final payload = <String, dynamic>{
      "type": type,
      "address": address.toUpdateJson(),
    };

    if (placeId != null && placeId.trim().isNotEmpty) {
      payload["placeId"] = placeId.trim();
    }

    final resp = await _dio.post(
      "/auth/address/verify",
      data: payload,
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    final profileMap =
        (data["profile"] ?? data["user"] ?? {}) as Map<String, dynamic>;

    if (profileMap.isEmpty) {
      throw Exception("Address verify response missing profile");
    }

    final updated = UserProfile.fromJson(profileMap);

    AppDebug.log(
      "PROFILE_API",
      "verifyAddress() success",
      extra: {"userId": updated.id},
    );

    return updated;
  }

  /// ------------------------------------------------------
  /// EMAIL VERIFICATION
  /// ------------------------------------------------------
  Future<Map<String, dynamic>> requestEmailVerification({
    required String token,
    String? email,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "requestEmailVerification() missing token");
      throw Exception("Missing auth token");
    }

    // WHY: Let backend verify the edited email even before a full save.
    final trimmedEmail = email?.trim();

    AppDebug.log(
      "PROFILE_API",
      "requestEmailVerification() start",
      extra: {"email": trimmedEmail},
    );

    final resp = await _dio.post(
      "/auth/email-verification/request",
      // WHY: Only send an email override when the user typed one.
      data: trimmedEmail == null || trimmedEmail.isEmpty
          ? null
          : {"email": trimmedEmail},
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    AppDebug.log("PROFILE_API", "requestEmailVerification() success");
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmEmailVerification({
    required String token,
    required String code,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "confirmEmailVerification() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log("PROFILE_API", "confirmEmailVerification() start");

    final resp = await _dio.post(
      "/auth/email-verification/confirm",
      data: {"code": code.trim()},
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    AppDebug.log("PROFILE_API", "confirmEmailVerification() success");
    return resp.data as Map<String, dynamic>;
  }

  /// ------------------------------------------------------
  /// PHONE VERIFICATION
  /// ------------------------------------------------------
  Future<Map<String, dynamic>> requestPhoneVerification({
    required String token,
    required String phone,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "requestPhoneVerification() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log("PROFILE_API", "requestPhoneVerification() start");

    final resp = await _dio.post(
      "/auth/phone-verification/request",
      data: {"phone": phone.trim()},
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    AppDebug.log("PROFILE_API", "requestPhoneVerification() success");
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmPhoneVerification({
    required String token,
    required String code,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "confirmPhoneVerification() missing token");
      throw Exception("Missing auth token");
    }

    AppDebug.log("PROFILE_API", "confirmPhoneVerification() start");

    final resp = await _dio.post(
      "/auth/phone-verification/confirm",
      data: {"code": code.trim()},
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    AppDebug.log("PROFILE_API", "confirmPhoneVerification() success");
    return resp.data as Map<String, dynamic>;
  }

  /// ------------------------------------------------------
  /// NIN VERIFICATION (SIMULATED)
  /// ------------------------------------------------------
  Future<Map<String, dynamic>> verifyNin({
    required String token,
    required String nin,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "verifyNin() missing token");
      throw Exception("Missing auth token");
    }

    if (nin.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "verifyNin() missing nin");
      throw Exception("Missing NIN");
    }

    AppDebug.log(
      "PROFILE_API",
      "verifyNin() start",
      extra: {"length": nin.trim().length},
    );

    final resp = await _dio.post(
      "/auth/nin/verify",
      data: {"nin": nin.trim()},
      options: Options(
        headers: {"Authorization": "Bearer $token"},
      ),
    );

    AppDebug.log("PROFILE_API", "verifyNin() success");
    return resp.data as Map<String, dynamic>;
  }

  /// ------------------------------------------------------
  /// PROFILE IMAGE UPLOAD
  /// ------------------------------------------------------
  Future<Map<String, dynamic>> uploadProfileImage({
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    if (token.trim().isEmpty) {
      AppDebug.log("PROFILE_API", "uploadProfileImage() missing token");
      throw Exception("Missing auth token");
    }

    if (bytes.isEmpty) {
      AppDebug.log("PROFILE_API", "uploadProfileImage() missing bytes");
      throw Exception("Missing image data");
    }

    AppDebug.log(
      "PROFILE_API",
      "uploadProfileImage() start",
      extra: {"bytes": bytes.length, "filename": filename},
    );

    final formData = FormData.fromMap({
      "image": MultipartFile.fromBytes(bytes, filename: filename),
    });

    final resp = await _dio.post(
      "/auth/profile-image",
      data: formData,
      options: Options(
        headers: {"Authorization": "Bearer $token"},
        contentType: "multipart/form-data",
      ),
    );

    AppDebug.log("PROFILE_API", "uploadProfileImage() success");
    return resp.data as Map<String, dynamic>;
  }
}
