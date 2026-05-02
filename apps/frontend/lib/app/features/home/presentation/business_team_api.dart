/// lib/app/features/home/presentation/business_team_api.dart
/// --------------------------------------------------------
/// WHAT:
/// - BusinessTeamApi for lookup + role assignment.
///
/// WHY:
/// - Keeps team-role networking out of widgets.
/// - Centralizes auth handling + error logs.
///
/// HOW:
/// - GET /business/users/lookup (userId/email/phone)
/// - PATCH /business/users/:id/role (staff/tenant)
/// - POST /business/invites (email invite link)
/// - POST /business/tenant/request-links (copyable tenant request link)
/// - POST /business/invites/accept (accept invite)
///
/// DEBUGGING:
/// - Logs request start/end (safe fields only).
/// --------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'business_team_user.dart';

/// --------------------------------------------------------
/// INVITE ACCEPTANCE RESULT
/// --------------------------------------------------------
/// WHY:
/// - Accept invite can return a fresh auth token when role changes.
/// - Keeps response parsing centralized and typed.
class BusinessInviteAcceptance {
  final BusinessTeamUser user;
  final String? token;

  const BusinessInviteAcceptance({required this.user, required this.token});
}

class BusinessTeamApi {
  final Dio _dio;

  BusinessTeamApi({required Dio dio}) : _dio = dio;

  Options _authOptions(String? token) {
    if (token == null || token.trim().isEmpty) {
      AppDebug.log("BUSINESS_TEAM_API", "Missing auth token");
      throw Exception("Missing auth token");
    }
    return Options(headers: {"Authorization": "Bearer $token"});
  }

  /// ------------------------------------------------------
  /// LOOKUP USER
  /// ------------------------------------------------------
  Future<BusinessTeamUser> lookupUser({
    required String? token,
    String? userId,
    String? email,
    String? phone,
  }) async {
    AppDebug.log(
      "BUSINESS_TEAM_API",
      "lookupUser() start",
      extra: {
        "hasUserId": userId?.isNotEmpty == true,
        "hasEmail": email?.isNotEmpty == true,
        "hasPhone": phone?.isNotEmpty == true,
      },
    );

    final query = <String, dynamic>{};
    if (userId != null && userId.trim().isNotEmpty) {
      // WHY: Allow direct id lookups for exact user targeting.
      query["userId"] = userId.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      query["email"] = email.trim();
    }
    if (phone != null && phone.trim().isNotEmpty) {
      query["phone"] = phone.trim();
    }

    final resp = await _dio.get(
      "/business/users/lookup",
      queryParameters: query,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final userMap = (data["user"] ?? {}) as Map<String, dynamic>;
    final user = BusinessTeamUser.fromJson(userMap);

    AppDebug.log(
      "BUSINESS_TEAM_API",
      "lookupUser() success",
      extra: {"userId": user.id, "role": user.role},
    );

    return user;
  }

  /// ------------------------------------------------------
  /// UPDATE USER ROLE
  /// ------------------------------------------------------
  Future<BusinessTeamUser> updateUserRole({
    required String? token,
    required String userId,
    required String role,
    String? estateAssetId,
  }) async {
    AppDebug.log(
      "BUSINESS_TEAM_API",
      "updateUserRole() start",
      extra: {
        "userId": userId,
        "role": role,
        "hasEstate": estateAssetId != null,
      },
    );

    final resp = await _dio.patch(
      "/business/users/$userId/role",
      data: {
        "role": role,
        if (estateAssetId != null && estateAssetId.trim().isNotEmpty)
          "estateAssetId": estateAssetId.trim(),
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final userMap = (data["user"] ?? {}) as Map<String, dynamic>;
    final user = BusinessTeamUser.fromJson(userMap);

    AppDebug.log(
      "BUSINESS_TEAM_API",
      "updateUserRole() success",
      extra: {"userId": user.id, "role": user.role},
    );

    return user;
  }

  /// ------------------------------------------------------
  /// CREATE INVITE
  /// ------------------------------------------------------
  Future<Map<String, dynamic>> createInvite({
    required String? token,
    required String email,
    required String role,
    String? staffRole,
    String? estateAssetId,
    String? agreementText,
    bool sendEmail = true,
  }) async {
    AppDebug.log(
      "BUSINESS_TEAM_API",
      "createInvite() start",
      extra: {
        "role": role,
        "staffRole": staffRole,
        "hasEstate": estateAssetId != null,
        "sendEmail": sendEmail,
      },
    );

    final resp = await _dio.post(
      "/business/invites",
      data: {
        "email": email.trim(),
        "role": role,
        "sendEmail": sendEmail,
        if (staffRole != null && staffRole.trim().isNotEmpty)
          "staffRole": staffRole.trim(),
        if (estateAssetId != null && estateAssetId.trim().isNotEmpty)
          "estateAssetId": estateAssetId.trim(),
        if (agreementText != null && agreementText.trim().isNotEmpty)
          "agreementText": agreementText.trim(),
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    AppDebug.log(
      "BUSINESS_TEAM_API",
      "createInvite() success",
      extra: {"email": email.trim(), "role": role, "sendEmail": sendEmail},
    );

    return data;
  }

  /// ------------------------------------------------------
  /// CREATE TENANT REQUEST LINK
  /// ------------------------------------------------------
  Future<Map<String, dynamic>> createTenantRequestLink({
    required String? token,
    required String estateAssetId,
  }) async {
    AppDebug.log(
      "BUSINESS_TEAM_API",
      "createTenantRequestLink() start",
      extra: {"hasEstate": estateAssetId.trim().isNotEmpty},
    );

    final resp = await _dio.post(
      "/business/tenant/request-links",
      data: {"estateAssetId": estateAssetId.trim()},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    AppDebug.log(
      "BUSINESS_TEAM_API",
      "createTenantRequestLink() success",
      extra: {
        "hasRequestLink":
            data["requestLink"]?.toString().trim().isNotEmpty == true,
      },
    );

    return data;
  }

  /// ------------------------------------------------------
  /// ACCEPT INVITE
  /// ------------------------------------------------------
  Future<BusinessInviteAcceptance> acceptInvite({
    required String? token,
    required String inviteToken,
  }) async {
    AppDebug.log(
      "BUSINESS_TEAM_API",
      "acceptInvite() start",
      extra: {"hasToken": inviteToken.isNotEmpty},
    );

    final resp = await _dio.post(
      "/business/invites/accept",
      data: {"token": inviteToken.trim()},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final userMap = (data["user"] ?? {}) as Map<String, dynamic>;
    final user = BusinessTeamUser.fromJson(userMap);
    // WHY: Accept invite may return a refreshed auth token.
    final nextToken = data["token"]?.toString();

    AppDebug.log(
      "BUSINESS_TEAM_API",
      "acceptInvite() success",
      extra: {
        "userId": user.id,
        "role": user.role,
        "hasToken": nextToken != null && nextToken.trim().isNotEmpty,
      },
    );

    return BusinessInviteAcceptance(user: user, token: nextToken);
  }
}
