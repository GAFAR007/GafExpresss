/// lib/app/core/platform/voice_note_blob.dart
/// ------------------------------------------
/// WHAT:
/// - Platform-safe helpers for browser-recorded voice-note blobs.
///
/// WHY:
/// - Web returns blob URLs, while IO platforms use file paths.
///
/// HOW:
/// - Delegates to web or stub/io implementations with conditional imports.
library;

import 'voice_note_blob_stub.dart'
    if (dart.library.html) 'voice_note_blob_web.dart'
    if (dart.library.io) 'voice_note_blob_io.dart'
    as platform_voice_note_blob;

Future<List<int>> readVoiceNoteBlobBytes(String blobUrl) {
  return platform_voice_note_blob.readVoiceNoteBlobBytes(blobUrl);
}

Future<void> revokeVoiceNoteBlobUrl(String blobUrl) {
  return platform_voice_note_blob.revokeVoiceNoteBlobUrl(blobUrl);
}
