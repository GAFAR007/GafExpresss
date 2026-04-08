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

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double page = 28;
  static const double section = 40;
}
