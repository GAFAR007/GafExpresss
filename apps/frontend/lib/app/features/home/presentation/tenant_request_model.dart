/// lib/app/features/home/presentation/tenant_request_model.dart
/// -------------------------------------------------------------
/// WHAT:
/// - Models for public tenant request links.
///
/// WHY:
/// - Keeps the unauthenticated tenant intake payloads typed.
/// - Avoids parsing nested estate/unit maps directly in the screen.
///
/// HOW:
/// - Maps the link context response into a typed structure.
/// - Reuses the existing business unit mix model for unit selection.
/// -------------------------------------------------------------
library;

import 'package:frontend/app/features/home/presentation/business_asset_model.dart';

class TenantRequestLinkContext {
  final String requestLinkId;
  final String businessId;
  final String businessName;
  final String estateAssetId;
  final String estateName;
  final List<BusinessAssetUnitMix> unitMix;
  final DateTime? expiresAt;

  const TenantRequestLinkContext({
    required this.requestLinkId,
    required this.businessId,
    required this.businessName,
    required this.estateAssetId,
    required this.estateName,
    required this.unitMix,
    required this.expiresAt,
  });

  factory TenantRequestLinkContext.fromJson(Map<String, dynamic> json) {
    final businessMap = json['business'];
    final estateMap = json['estate'];
    final unitMixRaw = estateMap is Map<String, dynamic>
        ? (estateMap['unitMix'] ?? []) as List<dynamic>
        : const <dynamic>[];

    return TenantRequestLinkContext(
      requestLinkId: (json['requestLinkId'] ?? '').toString(),
      businessId: businessMap is Map<String, dynamic>
          ? (businessMap['id'] ?? '').toString()
          : '',
      businessName: businessMap is Map<String, dynamic>
          ? (businessMap['name'] ?? '').toString()
          : '',
      estateAssetId: estateMap is Map<String, dynamic>
          ? (estateMap['id'] ?? '').toString()
          : '',
      estateName: estateMap is Map<String, dynamic>
          ? (estateMap['name'] ?? '').toString()
          : '',
      unitMix: unitMixRaw
          .whereType<Map<String, dynamic>>()
          .map(BusinessAssetUnitMix.fromJson)
          .toList(),
      expiresAt: _parseDate(json['expiresAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
