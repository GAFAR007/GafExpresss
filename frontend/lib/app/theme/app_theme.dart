// ignore: dangling_library_doc_comments
/// lib/app/theme/app_theme.dart
/// ----------------------------
/// WHAT THIS FILE IS:
/// - Builds ThemeData for Light + Dark themes.
///
/// WHY THIS EXISTS:
/// - Central place to control the entire look/feel of the app.
/// - Ensures consistent components across platforms.
///
/// HOW IT WORKS:
/// - MaterialApp uses AppTheme.light / AppTheme.dark.
/// - Widgets do NOT define styles; they inherit from ThemeData.

import 'package:flutter/material.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'app_radius.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          secondary: AppColors.primaryDark,
          surface: AppColors.surface,
          onPrimary: AppColors.surface,
          onSecondary: AppColors.surface,
          onSurface: AppColors.textPrimary,
          outline: AppColors.border,
          surfaceContainerHighest: AppColors.background,
          onSurfaceVariant: AppColors.textSecondary,
        );

    return ThemeData(
      useMaterial3: true,

      // Global colors
      colorScheme: scheme,

      scaffoldBackgroundColor: AppColors.background,

      // AppBar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.primary,
          secondary: AppColors.primaryDark,
          surface: AppColors.darkSurface,
          onPrimary: AppColors.darkTextPrimary,
          onSecondary: AppColors.darkTextPrimary,
          onSurface: AppColors.darkTextPrimary,
          outline: AppColors.darkBorder,
          surfaceContainerHighest: AppColors.darkSurface,
          onSurfaceVariant: AppColors.darkTextSecondary,
        );

    return ThemeData(
      useMaterial3: true,

      colorScheme: scheme,

      scaffoldBackgroundColor: AppColors.darkBackground,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.darkTextPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }

  static ThemeData business() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.businessPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.businessPrimary,
          secondary: AppColors.businessAccent,
          surface: AppColors.businessSurface,
          onPrimary: AppColors.businessSurface,
          onSecondary: AppColors.businessSurface,
          onSurface: AppColors.businessTextPrimary,
          outline: AppColors.businessBorder,
          surfaceContainerHighest: AppColors.businessCard,
          onSurfaceVariant: AppColors.businessTextSecondary,
        );

    return ThemeData(
      useMaterial3: true,

      // WHY: Business pages need a calmer analytics palette.
      colorScheme: scheme,

      scaffoldBackgroundColor: AppColors.businessBackground,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.businessSurface,
        foregroundColor: AppColors.businessTextPrimary,
        elevation: 0,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.businessSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.businessBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.businessBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(
            color: AppColors.businessPrimary,
            width: 2,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.businessPrimary,
          foregroundColor: AppColors.businessSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}

/// WHY: Centralize status badge colors so they adapt to each theme mode.
enum AppStatusTone { success, info, warning, danger, neutral }

enum AppStatusKind { pending, paid, shipped, delivered, cancelled, neutral }

/// WHY: Keep badge colors consistent and readable across themes.
class AppStatusBadgeColors {
  final Color background;
  final Color foreground;

  const AppStatusBadgeColors({
    required this.background,
    required this.foreground,
  });

  static AppStatusBadgeColors fromTheme({
    required ThemeData theme,
    required AppStatusTone tone,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final isBusiness = theme.colorScheme.primary == AppColors.businessPrimary;

    final Color base = switch (tone) {
      AppStatusTone.success => AppColors.success,
      AppStatusTone.info =>
        isBusiness ? AppColors.businessAccent : theme.colorScheme.primary,
      AppStatusTone.warning => AppColors.warning,
      AppStatusTone.danger => AppColors.error,
      AppStatusTone.neutral => theme.colorScheme.onSurfaceVariant,
    };

    if (tone == AppStatusTone.neutral) {
      return AppStatusBadgeColors(
        background: theme.colorScheme.surfaceContainerHighest,
        foreground: theme.colorScheme.onSurfaceVariant,
      );
    }

    return AppStatusBadgeColors(
      background: base.withOpacity(isDark ? 0.22 : 0.12),
      foreground: base.withOpacity(isDark ? 0.95 : 0.9),
    );
  }

  // WHY: Ensure each order status uses a distinct color across themes.
  static AppStatusBadgeColors fromStatus({
    required ThemeData theme,
    required AppStatusKind status,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    final Color base = switch (status) {
      AppStatusKind.pending => AppColors.warning,
      AppStatusKind.paid => AppColors.paid,
      AppStatusKind.shipped => AppColors.info,
      AppStatusKind.delivered => AppColors.success,
      AppStatusKind.cancelled => AppColors.error,
      AppStatusKind.neutral => theme.colorScheme.onSurfaceVariant,
    };

    if (status == AppStatusKind.neutral) {
      return AppStatusBadgeColors(
        background: theme.colorScheme.surfaceContainerHighest,
        foreground: theme.colorScheme.onSurfaceVariant,
      );
    }

    return AppStatusBadgeColors(
      background: base.withOpacity(isDark ? 0.22 : 0.12),
      foreground: base.withOpacity(isDark ? 0.95 : 0.9),
    );
  }
}
