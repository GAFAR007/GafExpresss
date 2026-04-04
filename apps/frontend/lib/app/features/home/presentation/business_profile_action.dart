/// lib/app/features/home/presentation/business_profile_action.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Shared app-bar action for opening the business profile/settings screen.
///
/// WHY:
/// - Keeps profile access in one consistent location across business pages.
/// - Prevents each screen from re-implementing slightly different behavior.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class BusinessProfileAction extends StatelessWidget {
  final String logTag;

  const BusinessProfileAction({super.key, required this.logTag});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.person_outline_rounded),
      tooltip: "Profile",
      onPressed: () {
        AppDebug.log(logTag, "Tap", extra: {"action": "profile"});
        context.go('/settings');
      },
    );
  }
}
