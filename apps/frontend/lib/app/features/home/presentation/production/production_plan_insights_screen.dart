/// lib/app/features/home/presentation/production/production_plan_insights_screen.dart
/// ------------------------------------------------------------------------------
/// WHAT:
/// - Wrapper route for the production insights/reporting view.
///
/// WHY:
/// - Keeps the main production plan route calendar-first and operational.
/// - Preserves deeper KPI / governance reporting on a separate screen.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/production/production_plan_detail_screen.dart';

class ProductionPlanInsightsScreen extends StatelessWidget {
  final String planId;

  const ProductionPlanInsightsScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context) {
    return ProductionPlanDetailScreen(planId: planId);
  }
}
