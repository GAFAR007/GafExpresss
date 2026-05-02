/// lib/app/core/platform/remote_file_download_stub.dart
/// -----------------------------------------------------
/// WHAT:
/// - Fallback implementation for remote file downloads.
///
/// WHY:
/// - Keeps conditional imports compile-safe on unsupported platforms.
library;

import 'remote_file_download_descriptor.dart';

Future<int> downloadRemoteFiles({
  required List<RemoteFileDownloadDescriptor> files,
}) {
  throw UnsupportedError(
    "Remote file downloads are not supported on this platform.",
  );
}
