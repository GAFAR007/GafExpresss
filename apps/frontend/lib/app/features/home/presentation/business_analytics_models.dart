/// lib/app/features/home/presentation/business_analytics_models.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Models for business analytics responses.
///
/// WHY:
/// - Keeps analytics parsing out of widgets.
/// - Provides typed access to backend summary values.
///
/// HOW:
/// - Maps JSON to typed fields with safe fallbacks.
/// ------------------------------------------------------------
library;

class BusinessAnalyticsSummary {
  final int totalProducts;
  final int activeProducts;
  final int totalStock;
  final int totalOrders;
  final Map<String, int> ordersByStatus;
  final int revenueTotal;

  const BusinessAnalyticsSummary({
    required this.totalProducts,
    required this.activeProducts,
    required this.totalStock,
    required this.totalOrders,
    required this.ordersByStatus,
    required this.revenueTotal,
  });

  factory BusinessAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    final rawStatuses =
        (json['ordersByStatus'] as Map?)?.cast<String, dynamic>() ?? {};
    final statusMap = <String, int>{};
    for (final entry in rawStatuses.entries) {
      statusMap[entry.key] = _toInt(entry.value);
    }

    return BusinessAnalyticsSummary(
      totalProducts: _toInt(json['totalProducts']),
      activeProducts: _toInt(json['activeProducts']),
      totalStock: _toInt(json['totalStock']),
      totalOrders: _toInt(json['totalOrders']),
      ordersByStatus: statusMap,
      revenueTotal: _toInt(json['revenueTotal']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
