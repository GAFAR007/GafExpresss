/// lib/app/features/home/presentation/business_team_user.dart
/// ---------------------------------------------------------
/// WHAT:
/// - BusinessTeamUser model for role assignment flows.
///
/// WHY:
/// - Keeps business-team lookup responses typed and predictable.
/// - Avoids leaking sensitive user fields into the UI layer.
///
/// HOW:
/// - Maps minimal user fields returned by /business/users/lookup.
/// - Provides helpers for safe display names.
/// ---------------------------------------------------------
library;

class BusinessTeamUser {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final bool isNinVerified;
  final String? businessId;
  final String? estateAssetId;

  const BusinessTeamUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isNinVerified,
    this.phone,
    this.businessId,
    this.estateAssetId,
  });

  factory BusinessTeamUser.fromJson(Map<String, dynamic> json) {
    return BusinessTeamUser(
      id: json["_id"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      email: json["email"]?.toString() ?? "",
      phone: json["phone"]?.toString(),
      role: json["role"]?.toString() ?? "customer",
      isNinVerified: json["isNinVerified"] == true,
      businessId: json["businessId"]?.toString(),
      estateAssetId: json["estateAssetId"]?.toString(),
    );
  }

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? "Unnamed user" : trimmed;
  }
}
