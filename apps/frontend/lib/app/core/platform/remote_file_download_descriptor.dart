/// lib/app/core/platform/remote_file_download_descriptor.dart
/// ---------------------------------------------------------
/// WHAT:
/// - Shared descriptor for downloading remote files across platforms.
///
/// WHY:
/// - Conditional imports need one compile-safe type shared by each backend.
library;

class RemoteFileDownloadDescriptor {
  final String url;
  final String fileName;

  const RemoteFileDownloadDescriptor({
    required this.url,
    required this.fileName,
  });
}
