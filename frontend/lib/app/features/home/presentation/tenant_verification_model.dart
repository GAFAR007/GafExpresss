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
  final String agreementText;

  const TenantEstate({
    required this.id,
    required this.name,
    required this.estate,
    required this.agreementText,
  });

  factory TenantEstate.fromJson(Map<String, dynamic> json) {
    return TenantEstate(
      id: json["id"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      estate: BusinessAssetEstate.fromJson(
        json["estate"] as Map<String, dynamic>?,
      ),
      agreementText: (json["agreementText"] ?? "").toString(),
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
  // WHY: Split names support cleaner verification and review display.
  final String firstName;
  // WHY: Middle name stays optional for legacy and usability.
  final String? middleName;
  // WHY: Last name is required for contact verification.
  final String lastName;
  // WHY: Email is required for contact verification workflows.
  final String email;
  // WHY: Phone is required for contact verification workflows.
  final String phone;
  // WHY: Optional document evidence for references/guarantors.
  final String? documentUrl;
  // WHY: Cloudinary id enables future clean-up if needed.
  final String? documentPublicId;

  const TenantContact({
    required this.name,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.documentUrl,
    required this.documentPublicId,
  });

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "firstName": firstName,
      "middleName": middleName,
      "lastName": lastName,
      "email": email,
      "phone": phone,
      "documentUrl": documentUrl,
      "documentPublicId": documentPublicId,
    };
  }
}
