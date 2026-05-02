/// lib/app/core/platform/voice_note_blob_web.dart
/// -----------------------------------------------
/// WHAT:
/// - Browser helpers for reading and cleaning up recorded voice-note blobs.
///
/// WHY:
/// - The recorder package returns blob URLs on web instead of file paths.
///
/// HOW:
/// - Fetches the blob URL, converts the ArrayBuffer to bytes, and revokes it.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<List<int>> readVoiceNoteBlobBytes(String blobUrl) async {
  final response = await web.window.fetch(blobUrl.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  return Uint8List.view(buffer.toDart).toList(growable: false);
}

Future<void> revokeVoiceNoteBlobUrl(String blobUrl) async {
  web.URL.revokeObjectURL(blobUrl);
}
