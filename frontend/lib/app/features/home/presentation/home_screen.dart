// ignore: dangling_library_doc_comments
/// lib/features/home/presentation/home_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - A placeholder screen to prove routing works.
///
/// WHY:
/// - Before auth, API, state management: confirm navigation works.
///
/// DEBUGGING:
/// - If you can reach this screen, router is correct.

import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint("UI: HomeScreen build()");
    return const Scaffold(body: Center(child: Text("Home ✅")));
  }
}
