// ignore: dangling_library_doc_comments
/// lib/app/theme/app_spacing.dart
/// ------------------------------
/// WHAT THIS FILE IS:
/// - Standard spacing scale used everywhere.
///
/// WHY THIS EXISTS:
/// - Prevents inconsistent padding/margins.
/// - Makes UI look “designed”, not random.
///
/// HOW IT WORKS:
/// - Widgets use AppSpacing values instead of hardcoded numbers.

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}