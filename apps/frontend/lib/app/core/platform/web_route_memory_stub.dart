/// lib/app/core/platform/web_route_memory_stub.dart
/// ------------------------------------------------
/// WHAT:
/// - Stub route-memory helpers for non-web platforms.
///
/// WHY:
/// - Keeps conditional imports compile-safe where browser storage is absent.
///
/// HOW:
/// - Returns null on reads and ignores writes.
library;

String? readRememberedWebRoute() => null;

void writeRememberedWebRoute(String route) {}
