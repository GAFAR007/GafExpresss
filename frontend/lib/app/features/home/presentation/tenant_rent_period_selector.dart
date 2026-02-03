/// lib/app/features/home/presentation/tenant_rent_period_selector.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Dropdown for selecting how many months/quarters/years to pay.
///
/// WHY:
/// - Backend accepts periodCount; UI must let tenant choose within limits.
/// - Reusable and theme-based; no magic numbers.
///
/// HOW:
/// - Uses tenant_rent_constants for max and label per rentPeriod.
/// - Emits integer 1..max; logs selection for debugging.
/// -----------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/tenant_rent_constants.dart';

// WHY: Keep log message stable across selector rebuilds.
const String _logPeriodLimitOverride = "period_limit_override_applied";
// WHY: Ensure we never render an empty dropdown for period selection.
const int _minPeriodsPerPayment = 1;

/// Dropdown to select period count (1..max) for the given [rentPeriod].
class TenantRentPeriodSelector extends StatelessWidget {
  final String rentPeriod;
  final int value;
  final ValueChanged<int> onChanged;
  // WHY: Allow screen to narrow options based on remaining coverage.
  final int? maxPeriodsOverride;

  const TenantRentPeriodSelector({
    super.key,
    required this.rentPeriod,
    required this.value,
    required this.onChanged,
    this.maxPeriodsOverride,
  });

  int _resolveMaxPeriods({
    required RentPeriodLimit limit,
    required int? override,
  }) {
    // WHY: Respect backend-provided remaining coverage without exceeding base max.
    if (override == null) return limit.maxPeriods;
    final safeOverride = override.clamp(_minPeriodsPerPayment, limit.maxPeriods);
    if (safeOverride == limit.maxPeriods) return limit.maxPeriods;

    AppDebug.log(
      "TENANT_VERIFY",
      _logPeriodLimitOverride,
      extra: {
        "rentPeriod": rentPeriod,
        "baseMax": limit.maxPeriods,
        "overrideMax": safeOverride,
      },
    );

    return safeOverride;
  }

  @override
  Widget build(BuildContext context) {
    final limit = getRentPeriodLimit(rentPeriod);
    if (limit == null) return const SizedBox.shrink();

    // WHY: Clamp UI options to backend max or remaining coverage override.
    final effectiveMax =
        _resolveMaxPeriods(limit: limit, override: maxPeriodsOverride);
    final options = List.generate(effectiveMax, (i) => i + 1);
    final safeValue = value.clamp(_minPeriodsPerPayment, effectiveMax);

    return DropdownButtonFormField<int>(
      value: safeValue,
      decoration: InputDecoration(
        labelText: "Number of ${limit.label}",
        border: const OutlineInputBorder(),
      ),
      items: options
          .map(
            (n) => DropdownMenuItem<int>(
              value: n,
              child: Text("$n ${limit.label}"),
            ),
          )
          .toList(),
      onChanged: (int? v) {
        if (v == null) return;
        AppDebug.log(
          "TENANT_VERIFY",
          "period_selected",
          extra: {"rentPeriod": rentPeriod, "periodCount": v},
        );
        onChanged(v);
      },
    );
  }
}
