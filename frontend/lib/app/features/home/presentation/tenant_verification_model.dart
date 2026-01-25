/// lib/app/features/home/presentation/tenant_verification_model.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Models for tenant verification (estate + contact input).
///
/// WHY:
/// - Keeps tenant onboarding payloads typed and consistent.
/// - Avoids ad-hoc Map access in the UI.
///
/// HOW:
/// - TenantEstate maps the /business/tenant/estate payload.
/// - TenantContact captures reference/guarantor entries for POST body.
/// -----------------------------------------------------------------
library;

import 'package:frontend/app/features/home/presentation/business_asset_model.dart';

class TenantEstate {
  final String id;
  final String name;
  final BusinessAssetEstate? estate;

  const TenantEstate({
    required this.id,
    required this.name,
    required this.estate,
  });

  factory TenantEstate.fromJson(Map<String, dynamic> json) {
    return TenantEstate(
      id: json["id"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      estate: BusinessAssetEstate.fromJson(
        json["estate"] as Map<String, dynamic>?,
      ),
    );
  }

  // WHY: Keep unit options access safe for null estates.
  List<BusinessAssetUnitMix> get unitMix => estate?.unitMix ?? const [];

  // WHY: Use rule defaults if the backend estate is missing rules.
  BusinessAssetTenantRules get tenantRules =>
      estate?.tenantRules ??
      const BusinessAssetTenantRules(
        referencesMin: 1,
        referencesMax: 2,
        guarantorsMin: 1,
        guarantorsMax: 2,
        requiresNinVerified: true,
        requiresAgreementSigned: true,
      );
}

class TenantContact {
  final String name;
  final String? phone;

  const TenantContact({
    required this.name,
    this.phone,
  });

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "phone": phone,
    };
  }
}
