/// lib/app/core/platform/voice_note_blob_io.dart
/// ----------------------------------------------
/// WHAT:
/// - IO fallback for browser-only voice-note blob helpers.
///
/// WHY:
/// - Mobile/Desktop use file paths, not browser blob URLs.
///
/// HOW:
/// - Throws if called unexpectedly and keeps the API symmetric.
library;

Future<List<int>> readVoiceNoteBlobBytes(String blobUrl) {
  throw UnsupportedError(
    "Voice-note blob URLs should not be used on IO platforms.",
  );
}

Future<void> revokeVoiceNoteBlobUrl(String blobUrl) async {}
