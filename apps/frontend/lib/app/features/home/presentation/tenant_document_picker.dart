/// lib/app/features/home/presentation/tenant_document_picker.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Cross-platform document picker for tenant verification.
///
/// WHY:
/// - References/guarantors may require PDF or image evidence.
/// - Keeps picker logic out of the screen widget.
///
/// HOW:
/// - Uses FilePicker with PDF/image extensions and in-memory bytes.
/// ------------------------------------------------------------
library;

import 'package:file_picker/file_picker.dart';

class PickedDocumentData {
  final List<int> bytes;
  final String filename;

  const PickedDocumentData({
    required this.bytes,
    required this.filename,
  });
}

Future<PickedDocumentData?> pickTenantDocument() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ["pdf", "png", "jpg", "jpeg"],
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

  return PickedDocumentData(
    bytes: bytes,
    filename: file.name,
  );
}
