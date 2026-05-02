/// lib/app/core/platform/web_route_memory.dart
/// -------------------------------------------
/// WHAT:
/// - Platform-safe helper for remembering the latest web route.
///
/// WHY:
/// - Browser refresh should reopen the same deep-linked page when possible.
///
/// HOW:
/// - Delegates to web storage on browser builds.
/// - Falls back to no-op stubs on non-web platforms.
library;

import 'web_route_memory_stub.dart'
    if (dart.library.html) 'web_route_memory_web.dart'
    as platform_memory;

String? readRememberedWebRoute() {
  return platform_memory.readRememberedWebRoute();
}

void writeRememberedWebRoute(String route) {
  platform_memory.writeRememberedWebRoute(route);
}
