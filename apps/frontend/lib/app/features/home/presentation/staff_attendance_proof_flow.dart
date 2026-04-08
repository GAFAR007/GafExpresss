/// lib/app/features/home/presentation/staff_attendance_proof_flow.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Required proof picker + upload dialog for staff clock-outs.
///
/// WHY:
/// - Clock-out must be backed by a file or picture immediately after save.
/// - Keeps proof upload logic out of the calling screens.
///
/// HOW:
/// - Uses FilePicker to choose a PDF/image file in memory.
/// - Blocks dismissal until the upload succeeds.
library;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_providers.dart';

const String _logTag = "STAFF_ATTENDANCE_PROOF_FLOW";
const String _dialogTitle = "Upload proof";
const String _dialogBody =
    "Upload a file or picture now to complete this clock-out.";
const String _chooseFileLabel = "Choose file";
const String _replaceFileLabel = "Replace file";
const String _uploadLabel = "Upload proof";
const String _allowedLabel = "Allowed: PDF, JPG, PNG, WEBP. Max 5 MB.";
const String _missingFileMessage = "Choose a proof file or picture first.";
const String _tooLargeMessage = "Proof must be 5 MB or smaller.";
const String _uploadFailedMessage = "Unable to upload proof. Try another file.";
const String _noFileSelectedLabel = "No file selected yet";
const String _subjectPrefix = "Subject";
const String _taskPrefix = "Task";
const int _maxBytes = 5 * 1024 * 1024;
const List<String> _allowedExtensions = ["pdf", "png", "jpg", "jpeg", "webp"];

class PickedAttendanceProofData {
  final List<int> bytes;
  final String filename;
  final int sizeBytes;

  const PickedAttendanceProofData({
    required this.bytes,
    required this.filename,
    required this.sizeBytes,
  });

  bool get isImage {
    final name = filename.trim().toLowerCase();
    return name.endsWith(".png") ||
        name.endsWith(".jpg") ||
        name.endsWith(".jpeg") ||
        name.endsWith(".webp");
  }
}

Future<PickedAttendanceProofData?> pickAttendanceProofFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _allowedExtensions,
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

  return PickedAttendanceProofData(
    bytes: bytes,
    filename: file.name,
    sizeBytes: file.size,
  );
}

Future<StaffAttendanceRecord> requireAttendanceProofUpload({
  required BuildContext context,
  required WidgetRef ref,
  required StaffAttendanceRecord attendance,
  String? subjectLabel,
  String? taskLabel,
}) async {
  AppDebug.log(
    _logTag,
    "requireAttendanceProofUpload() start",
    extra: {
      "attendanceId": attendance.id,
      "staffProfileId": attendance.staffProfileId,
    },
  );

  final actions = StaffAttendanceActions(ref);
  PickedAttendanceProofData? selectedFile;
  bool isUploading = false;
  String errorText = "";
  final uploaded = await showDialog<StaffAttendanceRecord>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> chooseFile() async {
              final picked = await pickAttendanceProofFile();
              if (picked == null) {
                return;
              }
              setDialogState(() {
                selectedFile = picked;
                errorText = "";
              });
            }

            Future<void> uploadProof() async {
              if (selectedFile == null) {
                setDialogState(() {
                  errorText = _missingFileMessage;
                });
                return;
              }
              if (selectedFile!.bytes.length > _maxBytes) {
                setDialogState(() {
                  errorText = _tooLargeMessage;
                });
                return;
              }
              setDialogState(() {
                isUploading = true;
                errorText = "";
              });

              try {
                final updatedAttendance = await actions.uploadProof(
                  attendanceId: attendance.id,
                  bytes: selectedFile!.bytes,
                  filename: selectedFile!.filename,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                AppDebug.log(
                  _logTag,
                  "requireAttendanceProofUpload() success",
                  extra: {
                    "attendanceId": attendance.id,
                    "staffProfileId": updatedAttendance.staffProfileId,
                  },
                );
                Navigator.of(dialogContext).pop(updatedAttendance);
              } catch (error) {
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  isUploading = false;
                  errorText = _resolveProofUploadErrorMessage(error);
                });
              }
            }

            final subjectText = subjectLabel?.trim().isNotEmpty == true
                ? subjectLabel!.trim()
                : "";
            final taskText = taskLabel?.trim().isNotEmpty == true
                ? taskLabel!.trim()
                : "";

            return AlertDialog(
              title: const Text(_dialogTitle),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dialogBody,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (subjectText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _ProofMetaLine(
                          label: _subjectPrefix,
                          value: subjectText,
                          icon: Icons.person_outline,
                        ),
                      ],
                      if (taskText.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ProofMetaLine(
                          label: _taskPrefix,
                          value: taskText,
                          icon: Icons.assignment_outlined,
                        ),
                      ],
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: isUploading ? null : chooseFile,
                        icon: Icon(
                          selectedFile == null
                              ? Icons.attach_file_outlined
                              : Icons.refresh_outlined,
                        ),
                        label: Text(
                          selectedFile == null
                              ? _chooseFileLabel
                              : _replaceFileLabel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              selectedFile == null
                                  ? Icons.pending_outlined
                                  : selectedFile!.isImage
                                  ? Icons.image_outlined
                                  : Icons.description_outlined,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedFile == null
                                        ? _noFileSelectedLabel
                                        : selectedFile!.filename,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    selectedFile == null
                                        ? _allowedLabel
                                        : "Proof selected • ${_formatBytes(selectedFile!.sizeBytes)}",
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (errorText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        _allowedLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isUploading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(minHeight: 3),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: isUploading ? null : uploadProof,
                  child: Text(isUploading ? "Uploading..." : _uploadLabel),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  if (uploaded == null) {
    throw Exception(_uploadFailedMessage);
  }

  return uploaded;
}

class _ProofMetaLine extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ProofMetaLine({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$label: $value",
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

String _resolveProofUploadErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data["error"] ?? data["message"];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
  }

  final text = error.toString().trim();
  if (text.startsWith("Exception: ")) {
    return text.substring("Exception: ".length);
  }
  return text.isEmpty ? _uploadFailedMessage : text;
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return "0 B";
  }
  const kb = 1024;
  const mb = 1024 * 1024;
  if (bytes >= mb) {
    return "${(bytes / mb).toStringAsFixed(1)} MB";
  }
  if (bytes >= kb) {
    return "${(bytes / kb).toStringAsFixed(1)} KB";
  }
  return "$bytes B";
}
