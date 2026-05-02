/// lib/app/features/home/presentation/production/production_local_video_preview.dart
/// -------------------------------------------------------------------------------------
/// WHAT:
/// - Conditional local video preview for newly captured production proof.
library;

export 'production_local_video_preview_stub.dart'
    if (dart.library.html) 'production_local_video_preview_web.dart';
