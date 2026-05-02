/// lib/app/core/platform/remote_file_download_web.dart
/// ----------------------------------------------------
/// WHAT:
/// - Browser implementation for downloading remote files.
///
/// WHY:
/// - Managers downloading proof media from web expect files to land in the
///   browser download flow instead of only opening preview tabs.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'remote_file_download_descriptor.dart';

Future<int> downloadRemoteFiles({
  required List<RemoteFileDownloadDescriptor> files,
}) async {
  var startedCount = 0;
  for (final file in files) {
    final url = file.url.trim();
    if (url.isEmpty) {
      continue;
    }
    await _clickDownloadAnchor(
      href: await _resolveDownloadHref(url),
      fileName: file.fileName,
    );
    startedCount += 1;
    if (startedCount < files.length) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
  }
  return startedCount;
}

Future<String> _resolveDownloadHref(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) {
      return url;
    }
    final blob = await response.blob().toDart;
    final objectUrl = web.URL.createObjectURL(blob);
    unawaited(
      Future<void>.delayed(const Duration(seconds: 8), () {
        web.URL.revokeObjectURL(objectUrl);
      }),
    );
    return objectUrl;
  } catch (_) {
    return url;
  }
}

Future<void> _clickDownloadAnchor({
  required String href,
  required String fileName,
}) async {
  final anchor = web.HTMLAnchorElement()
    ..href = href
    ..download = fileName.trim()
    ..target = "_blank"
    ..style.display = "none";
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
