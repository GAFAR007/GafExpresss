/// lib/app/core/platform/text_file_download_io.dart
/// -------------------------------------------------
/// WHAT:
/// - Mobile/Desktop text-based file save implementation.
///
/// WHY:
/// - Non-web platforms need a real local file path for offline review.
///
/// HOW:
/// - Prefers a downloads directory when available.
/// - Falls back to the app documents directory.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> downloadPlainTextFile({
  required String fileName,
  required String contents,
  String mimeType = "text/plain",
}) async {
  Directory targetDirectory;
  try {
    targetDirectory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  } catch (_) {
    targetDirectory = await getApplicationDocumentsDirectory();
  }

  final draftsDirectory = Directory(
    "${targetDirectory.path}${Platform.pathSeparator}production_drafts",
  );
  if (!draftsDirectory.existsSync()) {
    await draftsDirectory.create(recursive: true);
  }

  final file = File(
    "${draftsDirectory.path}${Platform.pathSeparator}$fileName",
  );
  await file.writeAsString(contents, flush: true);
  return file.path;
}
