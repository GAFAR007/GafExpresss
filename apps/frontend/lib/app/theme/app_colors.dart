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
  static const Color darkBackground = Color(0xFF07111C);
  static const Color darkSurface = Color(0xFF0D1828);
  static const Color darkSurfaceAlt = Color(0xFF111D30);
  static const Color darkSurfaceMuted = Color(0xFF16243A);
  static const Color darkPrimary = Color(0xFF7EA1FF);
  static const Color darkPrimaryContainer = Color(0xFF1D3152);
  static const Color darkSecondaryContainer = Color(0xFF152846);
  static const Color darkTertiaryContainer = Color(0xFF4C391A);

  static const Color darkTextPrimary = Color(0xFFF5F8FF);
  static const Color darkTextSecondary = Color(0xFFA7B4CC);

  static const Color darkBorder = Color(0xFF253753);
  static const Color darkOutlineVariant = Color(0xFF1C2C44);
  static const Color darkShadow = Color(0xFF01050B);

  // ------------------------------------------------------------
  // BUSINESS MODE (analytics-focused palette)
  // ------------------------------------------------------------
  // WHY: Business mode should feel like an operations cockpit.
  static const Color businessPrimary = Color(0xFF6F90FF);
  static const Color businessAccent = Color(0xFFE0A64D);
  static const Color businessBackground = Color(0xFF08111C);
  static const Color businessSurface = Color(0xFF0D1828);
  static const Color businessSurfaceAlt = Color(0xFF111F31);
  static const Color businessCard = Color(0xFF15243A);
  static const Color businessPrimaryContainer = Color(0xFF1E3153);
  static const Color businessSecondaryContainer = Color(0xFF54401E);
  static const Color businessTertiaryContainer = Color(0xFF183154);
  static const Color businessTextPrimary = Color(0xFFF4F7FD);
  static const Color businessTextSecondary = Color(0xFFABB8CF);
  static const Color businessBorder = Color(0xFF263956);
  static const Color businessOutlineVariant = Color(0xFF1D2D45);
  static const Color businessShadow = Color(0xFF01050B);
}
