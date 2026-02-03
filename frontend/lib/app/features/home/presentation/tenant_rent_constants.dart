/// lib/app/features/home/presentation/tenant_rent_constants.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Constants for tenant rent period selection (months/quarters/years).
///
/// WHY:
/// - Single source of truth for max periods and labels; no magic numbers in UI.
/// - Matches backend RENT_PERIOD_LIMITS (monthly 1–12, quarterly 1–4, yearly 1–3).
///
/// HOW:
/// - RentPeriodLimit exposes label and maxPeriods per rent period key.
/// - getRentPeriodLimit(rentPeriod) returns limit or null for unknown period.
/// -----------------------------------------------------------------
library;

/// Max periods per payment and display label per rent cadence.
class RentPeriodLimit {
  final String label;
  final int maxPeriods;

  const RentPeriodLimit({
    required this.label,
    required this.maxPeriods,
  });
}

/// WHY: Backend enforces same limits; frontend must not allow higher.
const Map<String, RentPeriodLimit> rentPeriodLimits = {
  "monthly": RentPeriodLimit(label: "months", maxPeriods: 12),
  "quarterly": RentPeriodLimit(label: "quarters", maxPeriods: 4),
  "yearly": RentPeriodLimit(label: "years", maxPeriods: 3),
};

/// Returns limit for [rentPeriod] (normalized to lowercase), or null if unsupported.
RentPeriodLimit? getRentPeriodLimit(String? rentPeriod) {
  if (rentPeriod == null || rentPeriod.isEmpty) return null;
  return rentPeriodLimits[rentPeriod.trim().toLowerCase()];
}
