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

  const PickedImageData({required this.bytes, required this.filename});
}

Future<PickedImageData?> pickProfileImage() async {
  final images = await pickProfileImages();
  if (images.isEmpty) {
    return null;
  }

  return images.first;
}

Future<List<PickedImageData>> pickProfileImages() async {
  if (PlatformInfo.isWeb) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      return const [];
    }

    final picked = <PickedImageData>[];
    for (final file in result.files) {
      final bytes = file.bytes ?? <int>[];
      if (bytes.isEmpty) {
        continue;
      }

      picked.add(PickedImageData(bytes: bytes, filename: file.name));
    }

    return picked;
  }

  final picker = ImagePicker();
  final images = await picker.pickMultiImage(imageQuality: 85);

  if (images.isEmpty) {
    return const [];
  }

  final picked = <PickedImageData>[];
  for (final image in images) {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      continue;
    }

    picked.add(PickedImageData(bytes: bytes, filename: image.name));
  }

  return picked;
}
