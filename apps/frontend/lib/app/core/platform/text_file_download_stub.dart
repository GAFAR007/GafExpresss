/// lib/app/core/platform/text_file_download_stub.dart
/// ---------------------------------------------------
/// WHAT:
/// - Fallback implementation when neither Web nor IO is available.
///
/// WHY:
/// - Keeps conditional imports compile-safe across platforms.
///
/// HOW:
/// - Throws an unsupported error so callers can surface a friendly message.
library;

Future<String?> downloadPlainTextFile({
  required String fileName,
  required String contents,
  String mimeType = "text/plain",
}) {
  throw UnsupportedError(
    "Plain-text draft downloads are not supported on this platform.",
  );
}
