/// lib/app/core/platform/text_file_download_web.dart
/// --------------------------------------------------
/// WHAT:
/// - Web text-based download implementation.
///
/// WHY:
/// - Browser users expect a direct file download.
///
/// HOW:
/// - Generates a text data URL and clicks a temporary anchor element.
library;

import 'dart:convert';

import 'package:web/web.dart' as web;

Future<String?> downloadPlainTextFile({
  required String fileName,
  required String contents,
  String mimeType = "text/plain",
}) async {
  final href = Uri.dataFromString(
    contents,
    mimeType: mimeType,
    encoding: utf8,
  ).toString();
  final anchor = web.HTMLAnchorElement()
    ..href = href
    ..download = fileName
    ..style.display = "none";
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return null;
}
