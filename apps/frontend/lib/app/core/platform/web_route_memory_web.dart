/// lib/app/core/platform/web_route_memory_web.dart
/// ------------------------------------------------
/// WHAT:
/// - Web route-memory helpers backed by browser session storage.
///
/// WHY:
/// - Some refresh flows reopen the app shell without preserving the exact
/// - production deep link in a way this app can reliably recover from.
///
/// HOW:
/// - Stores the latest route string in sessionStorage.
/// - Reads it back during router bootstrap.
library;

import 'package:web/web.dart' as web;

const String _routeMemoryKey = 'gafars_route_memory_v1';

String? readRememberedWebRoute() {
  final value = web.window.sessionStorage.getItem(_routeMemoryKey);
  final normalizedValue = value?.trim() ?? '';
  // WHY: "/" is only a shell entry point; remembering it adds no recovery
  // value and can trap the router in a useless root restore loop.
  if (normalizedValue.isEmpty || normalizedValue == '/') {
    return null;
  }
  return normalizedValue;
}

void writeRememberedWebRoute(String route) {
  final normalizedRoute = route.trim();
  // WHY: Persist only meaningful deep links so session restore prefers real
  // screens instead of a root shell redirect.
  if (normalizedRoute.isEmpty || normalizedRoute == '/') {
    return;
  }
  web.window.sessionStorage.setItem(_routeMemoryKey, normalizedRoute);
}
