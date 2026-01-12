// ignore: dangling_library_doc_comments
/// lib/app/theme/app_text_styles.dart
/// ----------------------------------
/// WHAT THIS FILE IS:
/// - Central text styles used throughout the app.
///
/// WHY THIS EXISTS:
/// - Prevents random font sizes everywhere.
/// - Creates consistent typography across iOS/Android/Web.
///
/// HOW IT WORKS:
/// - AppTheme wires these styles into ThemeData.textTheme.
/// - Widgets can also use these directly when needed.

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
}
