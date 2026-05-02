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
/// - Uses FilePicker for one image or one video per clock-out unit.
/// - Uses ImagePicker camera capture for per-unit clock-out proof.
/// - Restricts selection to supported image/video formats.
library;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/app/features/home/presentation/production/production_models.dart';

enum ProductionTaskProgressProofCaptureKind { image, video }

const List<String> _proofImageExtensions = <String>[
  "png",
  "jpg",
  "jpeg",
  "webp",
];
const List<String> _proofVideoExtensions = <String>[
  "mp4",
  "mov",
  "webm",
  "m4v",
];

Future<List<ProductionTaskProgressProofInput>>
pickTaskProgressProofImages() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>[
      ..._proofImageExtensions,
      ..._proofVideoExtensions,
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

Future<ProductionTaskProgressProofInput?> pickTaskProgressProofForKind({
  required ProductionTaskProgressProofCaptureKind kind,
  int? unitNumber,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: switch (kind) {
      ProductionTaskProgressProofCaptureKind.image => _proofImageExtensions,
      ProductionTaskProgressProofCaptureKind.video => _proofVideoExtensions,
    },
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) {
    return null;
  }

  final file = result.files.first;
  final bytes = file.bytes ?? <int>[];
  if (bytes.isEmpty) {
    return null;
  }

  return ProductionTaskProgressProofInput(
    bytes: bytes,
    filename: _normalizeCapturedProofFilename(
      file.name,
      kind: kind,
      unitNumber: unitNumber,
    ),
    sizeBytes: file.size > 0 ? file.size : bytes.length,
  );
}

Future<ProductionTaskProgressProofInput?> captureTaskProgressProof({
  required ProductionTaskProgressProofCaptureKind kind,
  int? unitNumber,
}) async {
  final picker = ImagePicker();
  final file = switch (kind) {
    ProductionTaskProgressProofCaptureKind.image => await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    ),
    ProductionTaskProgressProofCaptureKind.video => await picker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxDuration: const Duration(seconds: 30),
    ),
  };
  if (file == null) {
    return null;
  }

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    return null;
  }

  return ProductionTaskProgressProofInput(
    bytes: bytes,
    filename: _normalizeCapturedProofFilename(
      file.name,
      kind: kind,
      unitNumber: unitNumber,
    ),
    sizeBytes: bytes.length,
  );
}

String _normalizeCapturedProofFilename(
  String filename, {
  required ProductionTaskProgressProofCaptureKind kind,
  int? unitNumber,
}) {
  final trimmed = filename.trim();
  final isSupported = switch (kind) {
    ProductionTaskProgressProofCaptureKind.image =>
      isSupportedProductionProofImage(filename: trimmed, mimeType: ""),
    ProductionTaskProgressProofCaptureKind.video =>
      isSupportedProductionProofVideo(filename: trimmed, mimeType: ""),
  };
  if (trimmed.isNotEmpty && isSupported) {
    return trimmed;
  }

  final extension = switch (kind) {
    ProductionTaskProgressProofCaptureKind.image => ".jpg",
    ProductionTaskProgressProofCaptureKind.video => ".mp4",
  };
  final unitPrefix = unitNumber == null ? "unit" : "unit-$unitNumber";
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  if (trimmed.isEmpty) {
    return "$unitPrefix-proof-$timestamp$extension";
  }
  return "$trimmed$extension";
}
