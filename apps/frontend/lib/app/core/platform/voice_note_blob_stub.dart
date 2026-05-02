/// lib/app/core/platform/voice_note_blob_stub.dart
/// ------------------------------------------------
/// WHAT:
/// - Fallback voice-note blob helpers for unsupported platforms.
///
/// WHY:
/// - Keeps conditional imports compile-safe.
///
/// HOW:
/// - Throws when blob URLs are requested outside the browser.
library;

Future<List<int>> readVoiceNoteBlobBytes(String blobUrl) {
  throw UnsupportedError(
    "Voice-note blob URLs are only available in the browser.",
  );
}

Future<void> revokeVoiceNoteBlobUrl(String blobUrl) async {}
