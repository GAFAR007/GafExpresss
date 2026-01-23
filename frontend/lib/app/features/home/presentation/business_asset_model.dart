/// lib/app/features/home/presentation/business_asset_model.dart
/// -----------------------------------------------------------
/// WHAT:
/// - Data model for business assets (vehicles, equipment, warehouses, etc.).
///
/// WHY:
/// - Keeps asset parsing consistent across the assets UI and API layer.
/// - Centralizes field names to avoid fragile Map lookups in widgets.
///
/// HOW:
/// - `fromJson` maps API payloads into a strongly typed model.
/// - Optional fields stay nullable for partial payloads.
library;

class BusinessAsset {
  final String id;
  final String businessId;
  final String assetType;
  final String name;
  final String? description;
  final String? serialNumber;
  final String status;
  final String? location;
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
    required this.name,
    required this.status,
    this.description,
    this.serialNumber,
    this.location,
    this.createdBy,
    this.updatedBy,
    this.deletedBy,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory BusinessAsset.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      final raw = value.toString();
      return DateTime.tryParse(raw);
    }

    return BusinessAsset(
      id: json["_id"]?.toString() ?? '',
      businessId: json["businessId"]?.toString() ?? '',
      assetType: json["assetType"]?.toString() ?? 'other',
      name: json["name"]?.toString() ?? '',
      description: json["description"]?.toString(),
      serialNumber: json["serialNumber"]?.toString(),
      status: json["status"]?.toString() ?? 'inactive',
      location: json["location"]?.toString(),
      createdBy: json["createdBy"]?.toString(),
      updatedBy: json["updatedBy"]?.toString(),
      deletedBy: json["deletedBy"]?.toString(),
      deletedAt: parseDate(json["deletedAt"]),
      createdAt: parseDate(json["createdAt"]),
      updatedAt: parseDate(json["updatedAt"]),
    );
  }
}
