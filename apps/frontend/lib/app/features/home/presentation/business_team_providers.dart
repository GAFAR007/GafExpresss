/// lib/app/features/home/presentation/business_team_providers.dart
/// -------------------------------------------------------------
/// WHAT:
/// - Providers for business team role operations.
///
/// WHY:
/// - Reuses shared Dio + auth session wiring.
/// - Keeps API construction out of widgets.
///
/// HOW:
/// - businessTeamApiProvider builds BusinessTeamApi.
/// -------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'business_team_api.dart';

final businessTeamApiProvider = Provider<BusinessTeamApi>((ref) {
  AppDebug.log("PROVIDERS", "businessTeamApiProvider created");
  final dio = ref.read(dioProvider);
  return BusinessTeamApi(dio: dio);
});
