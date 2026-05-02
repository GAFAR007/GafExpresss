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

  static ThemeData light() => _buildTheme(
    brightness: Brightness.light,
    palette: const _AppThemePalette(
      primary: AppColors.primary,
      onPrimary: Color(0xFFF5F8FF),
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.analyticsAccent,
      onSecondary: Color(0xFFF2F7FF),
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: Color(0xFFF1F6FE),
      tertiary: AppColors.tertiary,
      onTertiary: Color(0xFF221406),
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: Color(0xFFFFE9CF),
      background: AppColors.background,
      surface: AppColors.surface,
      surfaceAlt: AppColors.surfaceAlt,
      surfaceMuted: AppColors.surfaceMuted,
      surfaceTinted: Color(0xFFD0DAEA),
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      border: AppColors.border,
      outlineVariant: AppColors.outlineVariant,
      shadow: AppColors.shadow,
    ),
  );

  static ThemeData dark() => _buildTheme(
    brightness: Brightness.dark,
    palette: const _AppThemePalette(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.primaryDark,
      primaryContainer: AppColors.darkPrimaryContainer,
      onPrimaryContainer: AppColors.darkTextPrimary,
      secondary: AppColors.analyticsAccent,
      onSecondary: Color(0xFFF2F7FF),
      secondaryContainer: AppColors.darkSecondaryContainer,
      onSecondaryContainer: Color(0xFFD5E6FA),
      tertiary: AppColors.businessAccent,
      onTertiary: AppColors.primaryDark,
      tertiaryContainer: AppColors.darkTertiaryContainer,
      onTertiaryContainer: Color(0xFFFFE9CB),
      background: AppColors.darkBackground,
      surface: AppColors.darkSurface,
      surfaceAlt: AppColors.darkSurfaceAlt,
      surfaceMuted: AppColors.darkSurfaceMuted,
      surfaceTinted: Color(0xFF17263D),
      textPrimary: AppColors.darkTextPrimary,
      textSecondary: AppColors.darkTextSecondary,
      border: AppColors.darkBorder,
      outlineVariant: AppColors.darkOutlineVariant,
      shadow: AppColors.darkShadow,
    ),
  );

  static ThemeData business() => _buildTheme(
    brightness: Brightness.dark,
    palette: const _AppThemePalette(
      primary: AppColors.businessPrimary,
      onPrimary: AppColors.primaryDark,
      primaryContainer: AppColors.businessPrimaryContainer,
      onPrimaryContainer: AppColors.businessTextPrimary,
      secondary: AppColors.analyticsAccent,
      onSecondary: Color(0xFFF2F7FF),
      secondaryContainer: AppColors.businessTertiaryContainer,
      onSecondaryContainer: Color(0xFFE0ECFD),
      tertiary: AppColors.businessAccent,
      onTertiary: AppColors.primaryDark,
      tertiaryContainer: AppColors.businessSecondaryContainer,
      onTertiaryContainer: Color(0xFFFFE6C8),
      background: AppColors.businessBackground,
      surface: AppColors.businessSurface,
      surfaceAlt: AppColors.businessSurfaceAlt,
      surfaceMuted: AppColors.businessCard,
      surfaceTinted: Color(0xFF182943),
      textPrimary: AppColors.businessTextPrimary,
      textSecondary: AppColors.businessTextSecondary,
      border: AppColors.businessBorder,
      outlineVariant: AppColors.businessOutlineVariant,
      shadow: AppColors.businessShadow,
    ),
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required _AppThemePalette palette,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: palette.primary,
          brightness: brightness,
        ).copyWith(
          primary: palette.primary,
          onPrimary: palette.onPrimary,
          primaryContainer: palette.primaryContainer,
          onPrimaryContainer: palette.onPrimaryContainer,
          secondary: palette.secondary,
          onSecondary: palette.onSecondary,
          secondaryContainer: palette.secondaryContainer,
          onSecondaryContainer: palette.onSecondaryContainer,
          tertiary: palette.tertiary,
          onTertiary: palette.onTertiary,
          tertiaryContainer: palette.tertiaryContainer,
          onTertiaryContainer: palette.onTertiaryContainer,
          error: AppColors.error,
          onError: Colors.white,
          errorContainer: AppColors.error.withValues(
            alpha: isDark ? 0.24 : 0.12,
          ),
          onErrorContainer: isDark ? const Color(0xFFFFE2DE) : AppColors.error,
          surface: palette.surface,
          onSurface: palette.textPrimary,
          onSurfaceVariant: palette.textSecondary,
          outline: palette.border,
          outlineVariant: palette.outlineVariant,
          shadow: palette.shadow,
          scrim: Colors.black.withValues(alpha: isDark ? 0.62 : 0.42),
          inverseSurface: isDark
              ? const Color(0xFFEFF7F4)
              : const Color(0xFF102019),
          onInverseSurface: isDark
              ? const Color(0xFF0A1411)
              : const Color(0xFFF2F8F5),
          inversePrimary: palette.tertiary,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: palette.background,
          surfaceContainerLow: palette.surface,
          surfaceContainer: palette.surfaceAlt,
          surfaceContainerHigh: palette.surfaceMuted,
          surfaceContainerHighest: palette.surfaceTinted,
        );

    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final textTheme = _buildTextTheme(
      baseTheme.textTheme,
      palette: palette,
      isDark: isDark,
    );
    final resolvedTheme = baseTheme.copyWith(textTheme: textTheme);
    final subtleShadow = palette.shadow.withValues(alpha: isDark ? 0.34 : 0.08);
    final deepShadow = palette.shadow.withValues(alpha: isDark ? 0.46 : 0.14);

    return baseTheme.copyWith(
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      textTheme: textTheme,
      dividerColor: palette.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? palette.surface : palette.background,
        foregroundColor: palette.textPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 12,
        toolbarHeight: 64,
        iconTheme: IconThemeData(color: palette.textPrimary, size: 20),
        actionsIconTheme: IconThemeData(color: palette.textPrimary, size: 20),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        toolbarTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surface,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: subtleShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: palette.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: deepShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: palette.outlineVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
          side: BorderSide(color: palette.outlineVariant),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        shadowColor: subtleShadow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: palette.outlineVariant),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
      ),
      dividerTheme: DividerThemeData(
        color: palette.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: isDark ? palette.surface : palette.surfaceAlt,
        selectedColor: palette.primaryContainer,
        disabledColor: palette.surfaceMuted,
        side: BorderSide(color: palette.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: palette.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? palette.surface : palette.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(
          color: palette.primary,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textSecondary.withValues(alpha: 0.88),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: palette.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          disabledBackgroundColor: palette.surfaceMuted,
          disabledForegroundColor: palette.textSecondary,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: AppButtonStyles.outlined(
          theme: resolvedTheme,
          tone: AppStatusTone.info,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: AppButtonStyles.text(
          theme: resolvedTheme,
          tone: AppStatusTone.info,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: AppButtonStyles.icon(
          theme: resolvedTheme,
          tone: AppStatusTone.neutral,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        elevation: 0,
        hoverElevation: 0,
        focusElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.onPrimary;
          }
          return palette.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.primary;
          }
          return palette.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.primary;
          }
          return palette.textSecondary;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(palette.onPrimary),
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.primary,
        textColor: palette.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(palette.surfaceAlt),
        dataRowColor: WidgetStateProperty.all(palette.surface),
        headingTextStyle: textTheme.labelLarge?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
        ),
        dividerThickness: 1,
        horizontalMargin: 16,
        columnSpacing: 18,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: palette.outlineVariant),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.surfaceMuted,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surface,
        selectedItemColor: palette.primary,
        unselectedItemColor: palette.textSecondary,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 76,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: isSelected ? palette.primary : palette.textSecondary,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? palette.primary : palette.textSecondary,
            size: 22,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.primaryContainer,
        selectedIconTheme: IconThemeData(color: palette.primary, size: 22),
        unselectedIconTheme: IconThemeData(
          color: palette.textSecondary,
          size: 20,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: palette.primary,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: palette.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.primaryContainer;
            }
            return palette.surfaceAlt;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.onPrimaryContainer;
            }
            return palette.textSecondary;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: palette.outlineVariant),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: palette.outlineVariant,
        indicator: BoxDecoration(
          color: palette.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelColor: palette.onPrimaryContainer,
        unselectedLabelColor: palette.textSecondary,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(AppRadius.xl),
          ),
          side: BorderSide(color: palette.outlineVariant),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(
    TextTheme base, {
    required _AppThemePalette palette,
    required bool isDark,
  }) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: palette.textPrimary,
        height: 1.48,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: palette.textPrimary.withValues(alpha: isDark ? 0.98 : 0.96),
        height: 1.46,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: palette.textSecondary.withValues(alpha: isDark ? 0.96 : 0.94),
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      labelSmall: base.labelSmall?.copyWith(
        color: palette.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AppThemePalette {
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceMuted;
  final Color surfaceTinted;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color outlineVariant;
  final Color shadow;

  const _AppThemePalette({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceMuted,
    required this.surfaceTinted,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.outlineVariant,
    required this.shadow,
  });
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

    final Color base = switch (tone) {
      AppStatusTone.success => AppColors.success,
      AppStatusTone.info => AppColors.analyticsAccent,
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
      background: base.withValues(alpha: isDark ? 0.18 : 0.14),
      foreground: base.withValues(alpha: isDark ? 0.96 : 0.92),
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
      AppStatusKind.shipped => AppColors.analyticsAccent,
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
      background: base.withValues(alpha: isDark ? 0.18 : 0.14),
      foreground: base.withValues(alpha: isDark ? 0.96 : 0.92),
    );
  }
}

class AppButtonStyles {
  AppButtonStyles._();

  static ButtonStyle filled({
    required ThemeData theme,
    AppStatusTone tone = AppStatusTone.info,
    Size minimumSize = const Size(0, 52),
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 18,
      vertical: 14,
    ),
    TextStyle? textStyle,
  }) {
    final palette = _AppButtonPalette.resolve(theme: theme, tone: tone);
    return FilledButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: palette.fill,
      foregroundColor: palette.onFill,
      disabledBackgroundColor: theme.colorScheme.surfaceContainerHigh,
      disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
      minimumSize: minimumSize,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      textStyle:
          textStyle ??
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  static ButtonStyle tonal({
    required ThemeData theme,
    AppStatusTone tone = AppStatusTone.info,
    Size minimumSize = const Size(0, 52),
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 18,
      vertical: 14,
    ),
    TextStyle? textStyle,
  }) {
    final palette = _AppButtonPalette.resolve(theme: theme, tone: tone);
    return FilledButton.styleFrom(
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: palette.surface,
      foregroundColor: palette.accent,
      disabledBackgroundColor: theme.colorScheme.surfaceContainerHigh,
      disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
      minimumSize: minimumSize,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: palette.border),
      ),
      textStyle:
          textStyle ??
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  static ButtonStyle outlined({
    required ThemeData theme,
    AppStatusTone tone = AppStatusTone.info,
    Size minimumSize = const Size(0, 50),
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),
    TextStyle? textStyle,
  }) {
    final palette = _AppButtonPalette.resolve(theme: theme, tone: tone);
    return OutlinedButton.styleFrom(
      foregroundColor: palette.accent,
      backgroundColor: palette.surface,
      disabledBackgroundColor: theme.colorScheme.surfaceContainerHigh,
      disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
      side: BorderSide(color: palette.border),
      minimumSize: minimumSize,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      textStyle:
          textStyle ??
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static ButtonStyle text({
    required ThemeData theme,
    AppStatusTone tone = AppStatusTone.info,
    Size minimumSize = const Size(0, 40),
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 6,
    ),
    TextStyle? textStyle,
  }) {
    final palette = _AppButtonPalette.resolve(theme: theme, tone: tone);
    return TextButton.styleFrom(
      foregroundColor: palette.accent,
      backgroundColor: tone == AppStatusTone.neutral ? null : palette.surface,
      disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
      minimumSize: minimumSize,
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      textStyle:
          textStyle ??
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static ButtonStyle icon({
    required ThemeData theme,
    AppStatusTone tone = AppStatusTone.info,
    Size minimumSize = const Size(40, 40),
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
  }) {
    final palette = _AppButtonPalette.resolve(theme: theme, tone: tone);
    return IconButton.styleFrom(
      foregroundColor: palette.accent,
      backgroundColor: palette.surface,
      disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
      minimumSize: minimumSize,
      padding: padding,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: palette.border),
      ),
    );
  }

  static Color accentColor({
    required ThemeData theme,
    AppStatusTone tone = AppStatusTone.info,
  }) {
    return _AppButtonPalette.resolve(theme: theme, tone: tone).accent;
  }
}

class _AppButtonPalette {
  final Color accent;
  final Color surface;
  final Color border;
  final Color fill;
  final Color onFill;

  const _AppButtonPalette({
    required this.accent,
    required this.surface,
    required this.border,
    required this.fill,
    required this.onFill,
  });

  static _AppButtonPalette resolve({
    required ThemeData theme,
    required AppStatusTone tone,
  }) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (tone == AppStatusTone.neutral) {
      final neutralFill = colorScheme.surfaceContainerHigh;
      return _AppButtonPalette(
        accent: colorScheme.onSurface,
        surface: colorScheme.surfaceContainerLow,
        border: colorScheme.outlineVariant,
        fill: neutralFill,
        onFill: colorScheme.onSurface,
      );
    }

    final Color base = switch (tone) {
      AppStatusTone.success => AppColors.success,
      AppStatusTone.info => AppColors.analyticsAccent,
      AppStatusTone.warning => AppColors.warning,
      AppStatusTone.danger => AppColors.error,
      AppStatusTone.neutral => colorScheme.onSurfaceVariant,
    };
    final fill = base;
    final onFill = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : colorScheme.onSurface;

    return _AppButtonPalette(
      accent: base.withValues(alpha: isDark ? 0.98 : 0.9),
      surface: base.withValues(alpha: isDark ? 0.22 : 0.1),
      border: base.withValues(alpha: isDark ? 0.4 : 0.22),
      fill: fill,
      onFill: onFill,
    );
  }
}
