/// lib/app/core/platform/remote_file_download_io.dart
/// ---------------------------------------------------
/// WHAT:
/// - Mobile/desktop implementation for opening remote files.
///
/// WHY:
/// - Non-web platforms cannot use browser download anchors, so they hand the
///   proof media URL to the operating system.
library;

import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'remote_file_download_descriptor.dart';

Future<int> downloadRemoteFiles({
  required List<RemoteFileDownloadDescriptor> files,
}) async {
  var startedCount = 0;
  for (final file in files) {
    final uri = Uri.tryParse(file.url.trim());
    if (uri == null) {
      continue;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      startedCount += 1;
    }
    if (startedCount < files.length) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
  }
  return startedCount;
}
