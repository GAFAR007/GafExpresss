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
  // WHY: Classic mode should feel warm, modern, and confident.
  static const Color primary = Color(0xFF1F6F6B); // Deep teal
  static const Color primaryDark = Color(0xFF154B49);

  // ------------------------------------------------------------
  // NEUTRALS (BACKGROUND / SURFACES / TEXT)
  // ------------------------------------------------------------
  static const Color background = Color(0xFFF4EFE7); // Warm paper
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF1E1B16);
  static const Color textSecondary = Color(0xFF6B6257);

  // ------------------------------------------------------------
  // STATUS COLORS
  // ------------------------------------------------------------
  static const Color success = Color(0xFF22C55E); // Delivered
  static const Color warning = Color(0xFFF59E0B); // Pending
  static const Color error = Color(0xFFEF4444); // Cancelled
  static const Color info = Color(0xFF3B82F6); // Shipped
  static const Color paid = Color(0xFF14B8A6); // Paid

  // ------------------------------------------------------------
  // BORDERS / DIVIDERS
  // ------------------------------------------------------------
  static const Color border = Color(0xFFE3DDD3);

  // ------------------------------------------------------------
  // DARK MODE (separate tokens keeps it clean)
  // ------------------------------------------------------------
  // WHY: Dark mode should be calm, not pitch black.
  static const Color darkBackground = Color(0xFF1B2230);
  static const Color darkSurface = Color(0xFF242D3D);

  static const Color darkTextPrimary = Color(0xFFE7ECF3);
  static const Color darkTextSecondary = Color(0xFFA4AFC0);

  static const Color darkBorder = Color(0xFF313A4D);

  // ------------------------------------------------------------
  // BUSINESS MODE (analytics-focused palette)
  // ------------------------------------------------------------
  // WHY: Business mode should feel analytical + premium with layered warmth.
  static const Color businessPrimary = Color(0xFF1B4F4B); // Deep pine
  static const Color businessAccent = Color(0xFFC8A15A); // Brass accent
  static const Color businessBackground = Color(0xFFF3F0E6);
  static const Color businessSurface = Color(0xFFFFFDF8);
  static const Color businessCard = Color(0xFFE8E1D3);
  static const Color businessTextPrimary = Color(0xFF2A2E2E);
  static const Color businessTextSecondary = Color(0xFF667074);
  static const Color businessBorder = Color(0xFFDED6C7);
}
