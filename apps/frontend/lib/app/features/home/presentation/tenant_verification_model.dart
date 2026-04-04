library;

import 'package:frontend/app/features/home/presentation/business_asset_model.dart';

/// =========================
/// TENANT ESTATE
/// =========================
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

  List<BusinessAssetUnitMix> get unitMix => estate?.unitMix ?? const [];

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

/// =========================
/// TENANT CONTACT
/// =========================
class TenantContact {
  final String name;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String email;
  final String phone;
  final String? documentUrl;
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

/// =========================
/// TENANT VERIFICATION STATE
/// =========================
/// WHY:
/// - Holds transient UI state for rent period + coverage selection.
/// - Used by TenantVerificationNotifier (Riverpod).
/// - Keeps rent defaults and user intent consistent.
class TenantVerificationState {
  final String rentPeriod;
  final int periodCount;

  /// WHY:
  /// - Once the user manually changes the count,
  ///   we must not auto-reset it when rentPeriod changes.
  final bool hasUserManuallyChangedPeriodCount;

  const TenantVerificationState({
    required this.rentPeriod,
    required this.periodCount,
    required this.hasUserManuallyChangedPeriodCount,
  });

  TenantVerificationState copyWith({
    String? rentPeriod,
    int? periodCount,
    bool? hasUserManuallyChangedPeriodCount,
  }) {
    return TenantVerificationState(
      rentPeriod: rentPeriod ?? this.rentPeriod,
      periodCount: periodCount ?? this.periodCount,
      hasUserManuallyChangedPeriodCount:
          hasUserManuallyChangedPeriodCount ??
          this.hasUserManuallyChangedPeriodCount,
    );
  }
}
