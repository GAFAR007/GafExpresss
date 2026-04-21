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
library;

import 'package:flutter/material.dart';

class AppColors {
  // Prevent instantiation
  AppColors._();

  // ------------------------------------------------------------
  // BRAND COLORS
  // ------------------------------------------------------------
  // WHY: The refreshed system uses deeper slate-blue foundations with warm
  // and domain-aware accents so the product feels more analytical and durable.
  static const Color primary = Color(0xFF3558A8);
  static const Color primaryDark = Color(0xFF101B35);
  static const Color primaryContainer = Color(0xFFD9E4FF);
  static const Color secondaryContainer = Color(0xFF233B63);
  static const Color tertiary = Color(0xFFD99A3C);
  static const Color tertiaryContainer = Color(0xFF5E4019);

  // ------------------------------------------------------------
  // CATEGORY / DOMAIN ACCENTS
  // ------------------------------------------------------------
  static const Color productionAccent = Color(0xFF2E8B62);
  static const Color analyticsAccent = Color(0xFF5B80FF);
  static const Color tenantAccent = Color(0xFFA88445);
  static const Color commerceAccent = Color(0xFFE06F3D);
  static const Color recordsAccent = Color(0xFF657792);

  // ------------------------------------------------------------
  // NEUTRALS (BACKGROUND / SURFACES / TEXT)
  // ------------------------------------------------------------
  static const Color background = Color(0xFFE9EEF6);
  static const Color surface = Color(0xFFF4F7FC);
  static const Color surfaceAlt = Color(0xFFDDE6F2);
  static const Color surfaceMuted = Color(0xFFCCD7E6);

  static const Color textPrimary = Color(0xFF121C2F);
  static const Color textSecondary = Color(0xFF586781);

  // ------------------------------------------------------------
  // STATUS COLORS
  // ------------------------------------------------------------
  static const Color success = Color(0xFF2F9961);
  static const Color warning = Color(0xFFD79B3F);
  static const Color error = Color(0xFFD85A4E);
  static const Color info = Color(0xFF5D86FF);
  static const Color paid = Color(0xFF6170F3);

  // ------------------------------------------------------------
  // BORDERS / DIVIDERS
  // ------------------------------------------------------------
  static const Color border = Color(0xFFAFBCCF);
  static const Color outlineVariant = Color(0xFFC6D1E0);
  static const Color shadow = Color(0xFF0A1222);

  // ------------------------------------------------------------
  // DARK MODE (separate tokens keeps it clean)
  // ------------------------------------------------------------
  // WHY: Dark mode should feel vivid and sharp, not greyed out.
  static const Color darkBackground = Color(0xFF09111F);
  static const Color darkSurface = Color(0xFF101A2C);
  static const Color darkSurfaceAlt = Color(0xFF142031);
  static const Color darkSurfaceMuted = Color(0xFF18253A);
  static const Color darkPrimary = Color(0xFF87A8FF);
  static const Color darkPrimaryContainer = Color(0xFF25355F);
  static const Color darkSecondaryContainer = Color(0xFF22365A);
  static const Color darkTertiaryContainer = Color(0xFF5E451E);

  static const Color darkTextPrimary = Color(0xFFF4F7FE);
  static const Color darkTextSecondary = Color(0xFFB5BFD4);

  static const Color darkBorder = Color(0xFF2B3953);
  static const Color darkOutlineVariant = Color(0xFF223149);
  static const Color darkShadow = Color(0xFF000000);

  // ------------------------------------------------------------
  // BUSINESS MODE (analytics-focused palette)
  // ------------------------------------------------------------
  // WHY: Business mode should feel like an operations cockpit.
  static const Color businessPrimary = Color(0xFF6F90FF);
  static const Color businessAccent = Color(0xFFE0A64D);
  static const Color businessBackground = Color(0xFF09111B);
  static const Color businessSurface = Color(0xFF101A2A);
  static const Color businessSurfaceAlt = Color(0xFF131F30);
  static const Color businessCard = Color(0xFF17263A);
  static const Color businessPrimaryContainer = Color(0xFF1D3151);
  static const Color businessSecondaryContainer = Color(0xFF5A4020);
  static const Color businessTertiaryContainer = Color(0xFF1E3D69);
  static const Color businessTextPrimary = Color(0xFFF4F7FD);
  static const Color businessTextSecondary = Color(0xFFB4BED4);
  static const Color businessBorder = Color(0xFF2B3D59);
  static const Color businessOutlineVariant = Color(0xFF223149);
  static const Color businessShadow = Color(0xFF020505);
}
