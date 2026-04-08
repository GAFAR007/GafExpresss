/// lib/app/theme/app_theme_mode.dart
/// --------------------------------
/// WHAT:
/// - Theme mode enum + persisted state notifier.
///
/// WHY:
/// - Centralizes app theming (classic/dark/business).
/// - Keeps mode consistent across restarts.
///
/// HOW:
/// - Uses flutter_secure_storage to read/write the mode.
/// - Exposes a Riverpod StateNotifier for the UI.
/// --------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

/// WHY: Explicit modes avoid magic strings across the app.
enum AppThemeMode {
  classic,
  dark,
  business,
}

/// WHY: Persist the theme so users keep their preference after restart.
class AppThemeModeStorage {
  // WHY: Reuse a single secure storage instance for reliability.
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _key = 'app_theme_mode';

  Future<AppThemeMode?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    return AppThemeMode.values.cast<AppThemeMode?>().firstWhere(
          (mode) => mode?.name == raw,
          orElse: () => null,
        );
  }

  Future<void> write(AppThemeMode mode) async {
    await _storage.write(key: _key, value: mode.name);
  }
}

/// WHY: Provide storage as a dependency for testability and reuse.
final appThemeModeStorageProvider = Provider<AppThemeModeStorage>((ref) {
  return AppThemeModeStorage();
});

/// WHY: Single source of truth for UI + router theme changes.
final appThemeModeProvider =
    StateNotifierProvider<AppThemeModeNotifier, AppThemeMode>((ref) {
  final storage = ref.read(appThemeModeStorageProvider);
  return AppThemeModeNotifier(storage);
});

/// WHY: Centralizes updates + persistence with clear debug logs.
class AppThemeModeNotifier extends StateNotifier<AppThemeMode> {
  final AppThemeModeStorage _storage;

  AppThemeModeNotifier(this._storage) : super(AppThemeMode.classic);

  Future<void> load() async {
    AppDebug.log("THEME", "Load start");
    final stored = await _storage.read();
    if (stored == null) {
      AppDebug.log("THEME", "No stored theme mode");
      return;
    }
    state = stored;
    AppDebug.log("THEME", "Loaded theme mode", extra: {"mode": stored.name});
  }

  Future<void> setMode(AppThemeMode mode, {required String source}) async {
    if (state == mode) {
      AppDebug.log(
        "THEME",
        "Mode unchanged",
        extra: {"mode": mode.name, "source": source},
      );
      return;
    }

    state = mode;
    AppDebug.log(
      "THEME",
      "Mode updated",
      extra: {"mode": mode.name, "source": source},
    );
    await _storage.write(mode);
  }
}
