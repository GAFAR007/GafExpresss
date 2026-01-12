/// lib/app/theme/app_colors.dart
/// -----------------------------
/// WHAT THIS FILE IS:
/// - A single place for all colors used in the app.
///
/// WHY THIS EXISTS:
/// - Centralized styling prevents “random colors everywhere”.
/// - Makes the UI consistent across iOS / Android / Web.
/// - Changing the brand color later becomes a 1-file change.
///
/// HOW IT WORKS:
/// - AppTheme reads these constants to build ThemeData.
/// - Widgets never hardcode colors; they reference AppColors.

import 'package:flutter/material.dart';

class AppColors {
  // Prevent instantiation
  AppColors._();

  // ------------------------------------------------------------
  // BRAND COLORS
  // ------------------------------------------------------------
  static const Color primary = Color(0xFF2D6CDF); // Brand blue
  static const Color primaryDark = Color(0xFF1F4BA3);

  // ------------------------------------------------------------
  // NEUTRALS (BACKGROUND / SURFACES / TEXT)
  // ------------------------------------------------------------
  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);

  // ------------------------------------------------------------
  // STATUS COLORS
  // ------------------------------------------------------------
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);

  // ------------------------------------------------------------
  // BORDERS / DIVIDERS
  // ------------------------------------------------------------
  static const Color border = Color(0xFFE5E7EB);

  // ------------------------------------------------------------
  // DARK MODE (separate tokens keeps it clean)
  // ------------------------------------------------------------
  static const Color darkBackground = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF111827);

  static const Color darkTextPrimary = Color(0xFFF9FAFB);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);

  static const Color darkBorder = Color(0xFF1F2937);
}
