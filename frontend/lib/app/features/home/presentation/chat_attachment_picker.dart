/// lib/app/features/home/presentation/chat_attachment_picker.dart
/// ------------------------------------------------------------
/// WHAT:
/// - File picker for chat attachments (images + docs).
///
/// WHY:
/// - Provides a single, reusable picker for chat uploads.
/// - Ensures attachment types align with backend validation.
///
/// HOW:
/// - Uses FilePicker with allowed extensions.
/// - Returns in-memory bytes + filename for upload.
library;

import 'package:file_picker/file_picker.dart';

class ChatPickedAttachment {
  final List<int> bytes;
  final String filename;

  const ChatPickedAttachment({
    required this.bytes,
    required this.filename,
  });
}

Future<ChatPickedAttachment?> pickChatAttachment() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ["pdf", "png", "jpg", "jpeg", "webp", "docx"],
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

  return ChatPickedAttachment(
    bytes: bytes,
    filename: file.name,
  );
}
