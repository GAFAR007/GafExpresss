/// lib/app/features/home/presentation/production/production_plan_create_screen.dart
/// ----------------------------------------------------------------------------
/// WHAT:
/// - Screen shell for creating a production plan.
///
/// WHY:
/// - Keeps the create form isolated from list/detail screens.
///
/// HOW:
/// - Renders ProductionPlanCreateBody and logs navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_create_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';

const String _logTag = "PRODUCTION_CREATE";
const String _buildMessage = "build()";
const String _backTap = "back_tap";
const String _screenTitle = "Create production plan";

class ProductionPlanCreateScreen extends ConsumerWidget {
  const ProductionPlanCreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage);
    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log(_logTag, _backTap);
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlansRoute);
          },
        ),
      ),
      // WHY: Form content lives in a separate widget to keep this screen small.
      body: const ProductionPlanCreateBody(),
    );
  }
}
