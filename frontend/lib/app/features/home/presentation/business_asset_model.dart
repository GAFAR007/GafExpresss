/// lib/app/features/home/presentation/business_asset_model.dart
/// -----------------------------------------------------------
/// WHAT:
/// - Data model for business assets (vehicles, equipment, estates, etc.).
///
/// WHY:
/// - Keeps asset parsing consistent across the assets UI and API layer.
/// - Centralizes field names to avoid fragile Map lookups in widgets.
///
/// HOW:
/// - `fromJson` maps API payloads into a strongly typed model.
/// - Optional fields stay nullable for partial payloads.
/// - Nested models keep estate + finance data consistent.
library;

/// -----------------------------------------------------------
/// NESTED MODELS
/// -----------------------------------------------------------
/// WHY:
/// - Keep estate + finance structures explicit and reusable.
class BusinessAssetAddress {
  final String? houseNumber;
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? lga;
  final String? landmark;
  final String? country;

  const BusinessAssetAddress({
    this.houseNumber,
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.lga,
    this.landmark,
    this.country,
  });

  factory BusinessAssetAddress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BusinessAssetAddress();
    return BusinessAssetAddress(
      houseNumber: json["houseNumber"]?.toString(),
      street: json["street"]?.toString(),
      city: json["city"]?.toString(),
      state: json["state"]?.toString(),
      postalCode: json["postalCode"]?.toString(),
      lga: json["lga"]?.toString(),
      landmark: json["landmark"]?.toString(),
      country: json["country"]?.toString(),
    );
  }
}

class BusinessAssetUnitMix {
  final String unitType;
  final int count;
  final double rentAmount;
  final String rentPeriod;

  const BusinessAssetUnitMix({
    required this.unitType,
    required this.count,
    required this.rentAmount,
    required this.rentPeriod,
  });

  factory BusinessAssetUnitMix.fromJson(Map<String, dynamic> json) {
    return BusinessAssetUnitMix(
      unitType: json["unitType"]?.toString() ?? '',
      count: _parseInt(json["count"]) ?? 0,
      rentAmount: _parseDouble(json["rentAmount"]) ?? 0,
      rentPeriod: json["rentPeriod"]?.toString() ?? 'monthly',
    );
  }
}

class BusinessAssetRentSummary {
  final double totalMonthly;
  final double totalAnnual;

  const BusinessAssetRentSummary({
    required this.totalMonthly,
    required this.totalAnnual,
  });

  factory BusinessAssetRentSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BusinessAssetRentSummary(totalMonthly: 0, totalAnnual: 0);
    }
    return BusinessAssetRentSummary(
      totalMonthly: _parseDouble(json["totalMonthly"]) ?? 0,
      totalAnnual: _parseDouble(json["totalAnnual"]) ?? 0,
    );
  }
}

class BusinessAssetTenantRules {
  final int referencesMin;
  final int referencesMax;
  final int guarantorsMin;
  final int guarantorsMax;
  final bool requiresNinVerified;
  final bool requiresAgreementSigned;

  const BusinessAssetTenantRules({
    required this.referencesMin,
    required this.referencesMax,
    required this.guarantorsMin,
    required this.guarantorsMax,
    required this.requiresNinVerified,
    required this.requiresAgreementSigned,
  });

  factory BusinessAssetTenantRules.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BusinessAssetTenantRules(
        referencesMin: 1,
        referencesMax: 2,
        guarantorsMin: 1,
        guarantorsMax: 2,
        requiresNinVerified: true,
        requiresAgreementSigned: true,
      );
    }
    return BusinessAssetTenantRules(
      referencesMin: _parseInt(json["referencesMin"]) ?? 1,
      referencesMax: _parseInt(json["referencesMax"]) ?? 2,
      guarantorsMin: _parseInt(json["guarantorsMin"]) ?? 1,
      guarantorsMax: _parseInt(json["guarantorsMax"]) ?? 2,
      requiresNinVerified: _parseBool(json["requiresNinVerified"]) ?? true,
      requiresAgreementSigned: _parseBool(json["requiresAgreementSigned"]) ?? true,
    );
  }
}

class BusinessAssetOperatingCosts {
  final double managementMonthly;
  final double cleaningMonthly;
  final double maintenanceMonthly;
  final double insuranceAnnual;
  final double taxAnnual;

  const BusinessAssetOperatingCosts({
    required this.managementMonthly,
    required this.cleaningMonthly,
    required this.maintenanceMonthly,
    required this.insuranceAnnual,
    required this.taxAnnual,
  });

  factory BusinessAssetOperatingCosts.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BusinessAssetOperatingCosts(
        managementMonthly: 0,
        cleaningMonthly: 0,
        maintenanceMonthly: 0,
        insuranceAnnual: 0,
        taxAnnual: 0,
      );
    }
    return BusinessAssetOperatingCosts(
      managementMonthly: _parseDouble(json["managementMonthly"]) ?? 0,
      cleaningMonthly: _parseDouble(json["cleaningMonthly"]) ?? 0,
      maintenanceMonthly: _parseDouble(json["maintenanceMonthly"]) ?? 0,
      insuranceAnnual: _parseDouble(json["insuranceAnnual"]) ?? 0,
      taxAnnual: _parseDouble(json["taxAnnual"]) ?? 0,
    );
  }
}

class BusinessAssetEstate {
  final BusinessAssetAddress? propertyAddress;
  final List<BusinessAssetUnitMix> unitMix;
  final int? totalUnits;
  final int? rentableUnits;
  final double? occupancyRate;
  final int? leaseTermMonths;
  final BusinessAssetRentSummary rentSummary;
  final BusinessAssetOperatingCosts operatingCosts;
  final BusinessAssetTenantRules tenantRules;

  const BusinessAssetEstate({
    this.propertyAddress,
    required this.unitMix,
    this.totalUnits,
    this.rentableUnits,
    this.occupancyRate,
    this.leaseTermMonths,
    required this.rentSummary,
    required this.operatingCosts,
    required this.tenantRules,
  });

  static BusinessAssetEstate? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final unitMixRaw = (json["unitMix"] ?? []) as List<dynamic>;
    return BusinessAssetEstate(
      propertyAddress: BusinessAssetAddress.fromJson(
        json["propertyAddress"] as Map<String, dynamic>?,
      ),
      unitMix: unitMixRaw
          .map((item) => BusinessAssetUnitMix.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalUnits: _parseInt(json["totalUnits"]),
      rentableUnits: _parseInt(json["rentableUnits"]),
      occupancyRate: _parseDouble(json["occupancyRate"]),
      leaseTermMonths: _parseInt(json["leaseTermMonths"]),
      rentSummary: BusinessAssetRentSummary.fromJson(
        json["rentSummary"] as Map<String, dynamic>?,
      ),
      operatingCosts: BusinessAssetOperatingCosts.fromJson(
        json["operatingCosts"] as Map<String, dynamic>?,
      ),
      tenantRules: BusinessAssetTenantRules.fromJson(
        json["tenantRules"] as Map<String, dynamic>?,
      ),
    );
  }
}

class BusinessAssetInventory {
  final int quantity;
  final double unitCost;
  final int reorderLevel;
  final String? unitOfMeasure;

  const BusinessAssetInventory({
    required this.quantity,
    required this.unitCost,
    required this.reorderLevel,
    this.unitOfMeasure,
  });

  factory BusinessAssetInventory.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BusinessAssetInventory(
        quantity: 0,
        unitCost: 0,
        reorderLevel: 0,
      );
    }
    return BusinessAssetInventory(
      quantity: _parseInt(json["quantity"]) ?? 0,
      unitCost: _parseDouble(json["unitCost"]) ?? 0,
      reorderLevel: _parseInt(json["reorderLevel"]) ?? 0,
      unitOfMeasure: json["unitOfMeasure"]?.toString(),
    );
  }
}

/// -----------------------------------------------------------
/// PRIMARY MODEL
/// -----------------------------------------------------------
/// WHY:
/// - Keep asset metadata + financial fields in one place.
class BusinessAsset {
  final String id;
  final String businessId;
  final String assetType;
  final String ownershipType;
  final String assetClass;
  final String name;
  final String? description;
  final String? serialNumber;
  final String status;
  final String? location;
  final String currency;
  final double? purchaseCost;
  final DateTime? purchaseDate;
  final int? usefulLifeMonths;
  final double? salvageValue;
  final String? depreciationMethod;
  final DateTime? leaseStart;
  final DateTime? leaseEnd;
  final double? leaseCostAmount;
  final String? leaseCostPeriod;
  final String? lessorName;
  final String? leaseTerms;
  final double? managementFeeAmount;
  final String? managementFeePeriod;
  final String? clientName;
  final String? serviceTerms;
  final BusinessAssetInventory? inventory;
  final BusinessAssetEstate? estate;
  final String? createdBy;
  final String? updatedBy;
  final String? deletedBy;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BusinessAsset({
    required this.id,
    required this.businessId,
    required this.assetType,
    required this.ownershipType,
    required this.assetClass,
    required this.name,
    required this.status,
    required this.currency,
    this.description,
    this.serialNumber,
    this.location,
    this.purchaseCost,
    this.purchaseDate,
    this.usefulLifeMonths,
    this.salvageValue,
    this.depreciationMethod,
    this.leaseStart,
    this.leaseEnd,
    this.leaseCostAmount,
    this.leaseCostPeriod,
    this.lessorName,
    this.leaseTerms,
    this.managementFeeAmount,
    this.managementFeePeriod,
    this.clientName,
    this.serviceTerms,
    this.inventory,
    this.estate,
    this.createdBy,
    this.updatedBy,
    this.deletedBy,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory BusinessAsset.fromJson(Map<String, dynamic> json) {
    return BusinessAsset(
      id: json["_id"]?.toString() ?? '',
      businessId: json["businessId"]?.toString() ?? '',
      assetType: json["assetType"]?.toString() ?? 'other',
      ownershipType: json["ownershipType"]?.toString() ?? 'owned',
      assetClass: json["assetClass"]?.toString() ?? 'fixed',
      name: json["name"]?.toString() ?? '',
      description: json["description"]?.toString(),
      serialNumber: json["serialNumber"]?.toString(),
      status: json["status"]?.toString() ?? 'inactive',
      location: json["location"]?.toString(),
      currency: json["currency"]?.toString() ?? 'NGN',
      purchaseCost: _parseDouble(json["purchaseCost"]),
      purchaseDate: _parseDate(json["purchaseDate"]),
      usefulLifeMonths: _parseInt(json["usefulLifeMonths"]),
      salvageValue: _parseDouble(json["salvageValue"]),
      depreciationMethod: json["depreciationMethod"]?.toString(),
      leaseStart: _parseDate(json["leaseStart"]),
      leaseEnd: _parseDate(json["leaseEnd"]),
      leaseCostAmount: _parseDouble(json["leaseCostAmount"]),
      leaseCostPeriod: json["leaseCostPeriod"]?.toString(),
      lessorName: json["lessorName"]?.toString(),
      leaseTerms: json["leaseTerms"]?.toString(),
      managementFeeAmount: _parseDouble(json["managementFeeAmount"]),
      managementFeePeriod: json["managementFeePeriod"]?.toString(),
      clientName: json["clientName"]?.toString(),
      serviceTerms: json["serviceTerms"]?.toString(),
      inventory: BusinessAssetInventory.fromJson(
        json["inventory"] as Map<String, dynamic>?,
      ),
      estate: BusinessAssetEstate.fromJson(
        json["estate"] as Map<String, dynamic>?,
      ),
      createdBy: json["createdBy"]?.toString(),
      updatedBy: json["updatedBy"]?.toString(),
      deletedBy: json["deletedBy"]?.toString(),
      deletedAt: _parseDate(json["deletedAt"]),
      createdAt: _parseDate(json["createdAt"]),
      updatedAt: _parseDate(json["updatedAt"]),
    );
  }
}

/// -----------------------------------------------------------
/// PARSING HELPERS
/// -----------------------------------------------------------
/// WHY:
/// - Keep parsing logic consistent across nested models.
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool? _parseBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  final raw = value.toString().toLowerCase();
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  return null;
}
