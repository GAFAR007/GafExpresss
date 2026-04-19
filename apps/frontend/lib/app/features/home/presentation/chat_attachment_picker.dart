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
/// - Uses ImagePicker on mobile for gallery/camera flows.
/// - Uses FilePicker on web and for document selection.
/// - Returns in-memory bytes + filename for upload.
library;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/app/core/platform/platform_info.dart';

class ChatPickedAttachment {
  final List<int> bytes;
  final String filename;

  const ChatPickedAttachment({required this.bytes, required this.filename});
}

Future<List<ChatPickedAttachment>> pickChatImages() async {
  if (PlatformInfo.isWeb) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      return const [];
    }

    final picked = <ChatPickedAttachment>[];
    for (final file in result.files) {
      final bytes = file.bytes ?? <int>[];
      if (bytes.isEmpty) {
        continue;
      }
      picked.add(ChatPickedAttachment(bytes: bytes, filename: file.name));
    }
    return picked;
  }

  final picker = ImagePicker();
  final images = await picker.pickMultiImage(imageQuality: 85);
  if (images.isEmpty) {
    return const [];
  }

  final picked = <ChatPickedAttachment>[];
  for (final image in images) {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      continue;
    }
    picked.add(ChatPickedAttachment(bytes: bytes, filename: image.name));
  }
  return picked;
}

Future<ChatPickedAttachment?> captureChatImage() async {
  if (PlatformInfo.isWeb) {
    return null;
  }

  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 85,
  );
  if (image == null) {
    return null;
  }

  final bytes = await image.readAsBytes();
  if (bytes.isEmpty) {
    return null;
  }

  return ChatPickedAttachment(bytes: bytes, filename: image.name);
}

Future<ChatPickedAttachment?> pickChatDocument() async {
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

  return ChatPickedAttachment(bytes: bytes, filename: file.name);
}
