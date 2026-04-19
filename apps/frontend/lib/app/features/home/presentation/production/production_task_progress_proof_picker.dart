/// lib/app/features/home/presentation/production/production_task_progress_proof_picker.dart
/// -------------------------------------------------------------------------------------
/// WHAT:
/// - Cross-platform image picker for production task progress proofs.
///
/// WHY:
/// - Progress proof capture needs the same web/mobile branching as other upload flows.
/// - Keeps picker details out of the task progress dialogs.
///
/// HOW:
/// - Uses FilePicker on web.
/// - Uses ImagePicker multi-select on mobile.
library;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/app/core/platform/platform_info.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';

Future<List<ProductionTaskProgressProofInput>>
pickTaskProgressProofImages() async {
  if (PlatformInfo.isWeb) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      return const [];
    }

    final picked = <ProductionTaskProgressProofInput>[];
    for (final file in result.files) {
      final bytes = file.bytes ?? <int>[];
      if (bytes.isEmpty) {
        continue;
      }
      picked.add(
        ProductionTaskProgressProofInput(
          bytes: bytes,
          filename: file.name,
          sizeBytes: file.size,
        ),
      );
    }

    return picked;
  }

  final picker = ImagePicker();
  final images = await picker.pickMultiImage(imageQuality: 85);

  if (images.isEmpty) {
    return const [];
  }

  final picked = <ProductionTaskProgressProofInput>[];
  for (final image in images) {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      continue;
    }
    picked.add(
      ProductionTaskProgressProofInput(
        bytes: bytes,
        filename: image.name,
        sizeBytes: bytes.length,
      ),
    );
  }

  return picked;
}
