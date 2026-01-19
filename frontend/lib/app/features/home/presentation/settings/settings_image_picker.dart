/// lib/app/features/home/presentation/settings/settings_image_picker.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Cross-platform image picker helper for Settings.
///
/// WHY:
/// - Web cannot use the same picker as mobile.
/// - Keeps platform branching out of the UI layer.
///
/// HOW:
/// - Uses ImagePicker on mobile.
/// - Uses FilePicker on web.
/// ------------------------------------------------------------
library;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/app/core/platform/platform_info.dart';

class PickedImageData {
  final List<int> bytes;
  final String filename;

  const PickedImageData({
    required this.bytes,
    required this.filename,
  });
}

Future<PickedImageData?> pickProfileImage() async {
  if (PlatformInfo.isWeb) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    final bytes = file.bytes ?? <int>[];
    if (bytes.isEmpty) {
      return null;
    }

    return PickedImageData(
      bytes: bytes,
      filename: file.name,
    );
  }

  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
  );

  if (image == null) {
    return null;
  }

  final bytes = await image.readAsBytes();
  if (bytes.isEmpty) {
    return null;
  }

  return PickedImageData(
    bytes: bytes,
    filename: image.name,
  );
}
