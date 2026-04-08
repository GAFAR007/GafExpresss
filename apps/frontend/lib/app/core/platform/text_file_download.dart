/// lib/app/core/platform/text_file_download.dart
/// ----------------------------------------------
/// WHAT:
/// - Platform-safe text-based file download helper.
///
/// WHY:
/// - Web needs a browser download.
/// - Mobile/Desktop need a local file save without importing web APIs.
///
/// HOW:
/// - Uses conditional imports to delegate to Web or IO implementations.
/// - Returns a saved file path when the platform writes locally.
/// - Returns null when the browser download is triggered directly.
library;

import 'text_file_download_stub.dart'
    if (dart.library.html) 'text_file_download_web.dart'
    if (dart.library.io) 'text_file_download_io.dart'
    as platform_download;

Future<String?> downloadPlainTextFile({
  required String fileName,
  required String contents,
  String mimeType = "text/plain",
}) {
  return platform_download.downloadPlainTextFile(
    fileName: fileName,
    contents: contents,
    mimeType: mimeType,
  );
}
