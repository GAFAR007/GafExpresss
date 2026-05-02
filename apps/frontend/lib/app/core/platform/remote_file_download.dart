/// lib/app/core/platform/remote_file_download.dart
/// ------------------------------------------------
/// WHAT:
/// - Platform-safe helper for downloading existing remote files.
///
/// WHY:
/// - Web can trigger browser downloads while mobile/desktop open remote files
///   externally without importing web-only APIs into shared code.
library;

import 'remote_file_download_descriptor.dart';
import 'remote_file_download_stub.dart'
    if (dart.library.html) 'remote_file_download_web.dart'
    if (dart.library.io) 'remote_file_download_io.dart'
    as platform_download;

export 'remote_file_download_descriptor.dart';

Future<int> downloadRemoteFiles({
  required List<RemoteFileDownloadDescriptor> files,
}) {
  return platform_download.downloadRemoteFiles(files: files);
}
