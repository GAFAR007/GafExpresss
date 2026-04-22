/// lib/app/features/home/presentation/production/production_task_progress_proof_picker.dart
/// -------------------------------------------------------------------------------------
/// WHAT:
/// - Cross-platform media picker for production task progress proofs.
///
/// WHY:
/// - Production proof capture now requires one photo and one short video.
/// - Keeps picker details out of the task progress dialogs.
///
/// HOW:
/// - Uses FilePicker on every platform.
/// - Restricts selection to supported image/video formats.
library;

import 'package:file_picker/file_picker.dart';

import 'package:frontend/app/features/home/presentation/production/production_models.dart';

Future<List<ProductionTaskProgressProofInput>>
pickTaskProgressProofImages() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>[
      "png",
      "jpg",
      "jpeg",
      "webp",
      "mp4",
      "mov",
      "webm",
      "m4v",
    ],
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
