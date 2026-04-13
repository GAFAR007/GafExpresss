/// lib/app/features/home/presentation/staff_attendance_proof_flow.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Required proof picker + upload dialog for staff clock-outs.
///
/// WHY:
/// - Attendance sign-out must be backed by a file or picture.
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
    "Upload a file or picture now for this attendance record. After proof is saved, continue the clock-out flow.";
const String _chooseFileLabel = "Upload proof";
const String _replaceFileLabel = "Change proof";
const String _submitLabel = "Submit";
const String _allowedLabel = "Allowed: PDF, JPG, PNG, WEBP. Max 5 MB.";
const String _missingFileMessage = "Choose a proof file or picture first.";
const String _tooLargeMessage = "Proof must be 5 MB or smaller.";
const String _uploadFailedMessage = "Unable to upload proof. Try another file.";
const String _noFileSelectedLabel = "No file selected yet";
const String _subjectPrefix = "Subject";
const String _taskPrefix = "Task";
const String _completedPrefix = "Completed";
const String _remainingPrefix = "Remaining";
const String _unitPrefix = "Unit";
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
  Map<String, dynamic>? clockOutAuditPayload,
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
  final requiredProofs = _resolveRequiredProofCount(
    attendance: attendance,
    clockOutAuditPayload: clockOutAuditPayload,
  );
  final unitsCompleted = _resolveUnitsCompleted(
    attendance: attendance,
    clockOutAuditPayload: clockOutAuditPayload,
  );
  final uploadedProofsByUnitIndex = <int, StaffAttendanceProof>{
    for (final proof in _buildExistingAttendanceProofs(attendance))
      if (proof.isUploaded) proof.unitIndex: proof,
  };
  final selectedFilesByUnitIndex = <int, PickedAttendanceProofData>{};
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
            Future<void> chooseFile(int unitIndex) async {
              final picked = await pickAttendanceProofFile();
              if (picked == null) {
                return;
              }
              setDialogState(() {
                selectedFilesByUnitIndex[unitIndex] = picked;
                errorText = "";
              });
            }

            Future<void> submitProofs() async {
              final latestAttendanceByRef = <StaffAttendanceRecord>[attendance];
              for (
                var unitIndex = 1;
                unitIndex <= requiredProofs;
                unitIndex++
              ) {
                final pickedFile = selectedFilesByUnitIndex[unitIndex];
                final uploadedProof = uploadedProofsByUnitIndex[unitIndex];
                if (pickedFile == null && uploadedProof == null) {
                  setDialogState(() {
                    errorText =
                        "Upload all $requiredProofs required proof${requiredProofs == 1 ? "" : "s"} before clock-out.";
                  });
                  return;
                }
                if (pickedFile != null && pickedFile.bytes.length > _maxBytes) {
                  setDialogState(() {
                    errorText = "Proof $unitIndex: $_tooLargeMessage";
                  });
                  return;
                }
              }
              if (requiredProofs <= 0) {
                setDialogState(() {
                  errorText = _missingFileMessage;
                });
                return;
              }
              setDialogState(() {
                isUploading = true;
                errorText = "";
              });

              try {
                var updatedAttendance = attendance;
                for (
                  var unitIndex = 1;
                  unitIndex <= requiredProofs;
                  unitIndex++
                ) {
                  final pickedFile = selectedFilesByUnitIndex[unitIndex];
                  if (pickedFile == null) {
                    continue;
                  }
                  updatedAttendance = await actions.uploadProof(
                    attendanceId: updatedAttendance.id,
                    bytes: pickedFile.bytes,
                    filename: pickedFile.filename,
                    unitIndex: unitIndex,
                    clockOutAuditPayload: clockOutAuditPayload,
                  );
                  latestAttendanceByRef
                    ..clear()
                    ..add(updatedAttendance);
                  final refreshedProofs = _buildExistingAttendanceProofs(
                    updatedAttendance,
                  );
                  setDialogState(() {
                    selectedFilesByUnitIndex.remove(unitIndex);
                    uploadedProofsByUnitIndex
                      ..clear()
                      ..addEntries(
                        refreshedProofs
                            .where((proof) => proof.isUploaded)
                            .map((proof) => MapEntry(proof.unitIndex, proof)),
                      );
                  });
                }
                if (uploadedProofsByUnitIndex.length != requiredProofs) {
                  throw Exception(
                    "Upload all $requiredProofs required proof${requiredProofs == 1 ? "" : "s"} before clock-out.",
                  );
                }
                if (!dialogContext.mounted) {
                  return;
                }
                AppDebug.log(
                  _logTag,
                  "requireAttendanceProofUpload() success",
                  extra: {
                    "attendanceId": attendance.id,
                    "staffProfileId":
                        latestAttendanceByRef.first.staffProfileId,
                    "requiredProofs": requiredProofs,
                  },
                );
                Navigator.of(dialogContext).pop(latestAttendanceByRef.first);
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
            final auditUnitText = _resolveAuditUnitText(clockOutAuditPayload);
            final auditCompletedText = _resolveAuditAmountText(
              payload: clockOutAuditPayload,
              amountKey: "unitsCompleted",
              unitKey: "progressUnitLabel",
            );
            final auditRemainingText = _resolveAuditAmountText(
              payload: clockOutAuditPayload,
              amountKey: "unitsRemaining",
              unitKey: "progressUnitLabel",
            );
            final proofRequirementLabel = unitsCompleted == null
                ? "$requiredProofs proof${requiredProofs == 1 ? "" : "s"} required"
                : "${_formatAuditAmount(unitsCompleted)} unit${unitsCompleted == 1 ? "" : "s"} completed • $requiredProofs proof${requiredProofs == 1 ? "" : "s"} required";
            final uploadedProofCount = uploadedProofsByUnitIndex.length;
            final readyProofCount = List.generate(requiredProofs, (index) {
              final unitIndex = index + 1;
              return selectedFilesByUnitIndex.containsKey(unitIndex) ||
                  uploadedProofsByUnitIndex.containsKey(unitIndex);
            }).where((isReady) => isReady).length;
            final canSubmitProofs =
                !isUploading &&
                requiredProofs > 0 &&
                readyProofCount == requiredProofs;

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
                      if (auditUnitText.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ProofMetaLine(
                          label: _unitPrefix,
                          value: auditUnitText,
                          icon: Icons.grid_view_outlined,
                        ),
                      ],
                      if (auditCompletedText.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ProofMetaLine(
                          label: _completedPrefix,
                          value: auditCompletedText,
                          icon: Icons.task_alt_outlined,
                        ),
                      ],
                      if (auditRemainingText.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ProofMetaLine(
                          label: _remainingPrefix,
                          value: auditRemainingText,
                          icon: Icons.pending_actions_outlined,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _ProofMetaLine(
                        label: "Proofs",
                        value:
                            "$proofRequirementLabel • uploaded $uploadedProofCount of $requiredProofs",
                        icon: Icons.verified_outlined,
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(requiredProofs, (index) {
                        final unitIndex = index + 1;
                        final selectedFile =
                            selectedFilesByUnitIndex[unitIndex];
                        final uploadedProof =
                            uploadedProofsByUnitIndex[unitIndex];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: unitIndex == requiredProofs ? 0 : 12,
                          ),
                          child: _ProofUploadSlotCard(
                            unitIndex: unitIndex,
                            selectedFile: selectedFile,
                            uploadedProof: uploadedProof,
                            isUploading: isUploading,
                            onChooseFile: () => chooseFile(unitIndex),
                          ),
                        );
                      }),
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
                OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () => chooseFile(
                          _firstMissingProofSlot(
                            requiredProofs: requiredProofs,
                            selectedFilesByUnitIndex: selectedFilesByUnitIndex,
                            uploadedProofsByUnitIndex:
                                uploadedProofsByUnitIndex,
                          ),
                        ),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text(_chooseFileLabel),
                ),
                FilledButton(
                  onPressed: canSubmitProofs ? submitProofs : null,
                  child: Text(isUploading ? "Submitting..." : _submitLabel),
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

class _ProofUploadSlotCard extends StatelessWidget {
  final int unitIndex;
  final PickedAttendanceProofData? selectedFile;
  final StaffAttendanceProof? uploadedProof;
  final bool isUploading;
  final VoidCallback onChooseFile;

  const _ProofUploadSlotCard({
    required this.unitIndex,
    required this.selectedFile,
    required this.uploadedProof,
    required this.isUploading,
    required this.onChooseFile,
  });

  @override
  Widget build(BuildContext context) {
    final displayFilename = selectedFile?.filename ?? uploadedProof?.filename;
    final displaySize = selectedFile?.sizeBytes ?? uploadedProof?.sizeBytes;
    final isSelected = selectedFile != null;
    final isUploaded = uploadedProof?.isUploaded == true && !isSelected;
    final icon = isSelected
        ? (selectedFile!.isImage
              ? Icons.image_outlined
              : Icons.description_outlined)
        : isUploaded
        ? Icons.verified_outlined
        : Icons.pending_outlined;
    final headline = displayFilename?.trim().isNotEmpty == true
        ? displayFilename!.trim()
        : _noFileSelectedLabel;
    final supportingText = isSelected
        ? "Ready to upload • ${_formatBytes(displaySize ?? 0)}"
        : isUploaded
        ? "Uploaded${uploadedProof?.uploadedAt == null ? "" : " • ${_formatUploadMoment(uploadedProof!.uploadedAt!)}"}"
        : _allowedLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Proof $unitIndex",
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      supportingText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isUploading ? null : onChooseFile,
            icon: Icon(
              isUploaded || isSelected
                  ? Icons.refresh_outlined
                  : Icons.upload_file_outlined,
            ),
            label: Text(
              isUploaded || isSelected ? _replaceFileLabel : _chooseFileLabel,
            ),
          ),
        ],
      ),
    );
  }
}

String _resolveAuditUnitText(Map<String, dynamic>? payload) {
  if (payload == null) {
    return "";
  }
  final unitLabel = payload["unitLabel"]?.toString().trim() ?? "";
  if (unitLabel.isNotEmpty) {
    return unitLabel;
  }
  final progressUnitLabel =
      payload["progressUnitLabel"]?.toString().trim() ?? "";
  return progressUnitLabel;
}

String _resolveAuditAmountText({
  required Map<String, dynamic>? payload,
  required String amountKey,
  required String unitKey,
}) {
  if (payload == null) {
    return "";
  }
  final rawAmount = payload[amountKey];
  if (rawAmount == null) {
    return "";
  }
  final amount = num.tryParse(rawAmount.toString());
  if (amount == null) {
    return "";
  }
  final unit = payload[unitKey]?.toString().trim() ?? "";
  final formattedAmount = _formatAuditAmount(amount);
  if (unit.isEmpty) {
    return formattedAmount;
  }
  return "$formattedAmount $unit";
}

String _formatAuditAmount(num value) {
  final normalized = value.toDouble();
  if ((normalized - normalized.roundToDouble()).abs() < 0.001) {
    return normalized.round().toString();
  }
  if (((normalized * 10) - (normalized * 10).roundToDouble()).abs() < 0.001) {
    return normalized.toStringAsFixed(1);
  }
  return normalized.toStringAsFixed(2);
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

List<StaffAttendanceProof> _buildExistingAttendanceProofs(
  StaffAttendanceRecord attendance,
) {
  if (attendance.proofs.isNotEmpty) {
    return [...attendance.proofs]
      ..sort((left, right) => left.unitIndex.compareTo(right.unitIndex));
  }
  final hasTopLevelProof =
      attendance.proofUrl?.trim().isNotEmpty == true &&
      attendance.proofFilename?.trim().isNotEmpty == true;
  if (!hasTopLevelProof) {
    return const <StaffAttendanceProof>[];
  }
  return <StaffAttendanceProof>[
    StaffAttendanceProof(
      unitIndex: 1,
      url: attendance.proofUrl!.trim(),
      publicId: attendance.proofPublicId?.trim() ?? "",
      filename: attendance.proofFilename!.trim(),
      mimeType: attendance.proofMimeType?.trim() ?? "",
      type: _resolveProofType(attendance.proofMimeType),
      sizeBytes: attendance.proofSizeBytes,
      uploadedAt: attendance.proofUploadedAt,
      uploadedBy: attendance.proofUploadedBy,
    ),
  ];
}

int _resolveRequiredProofCount({
  required StaffAttendanceRecord attendance,
  required Map<String, dynamic>? clockOutAuditPayload,
}) {
  final unitsCompleted = _resolveUnitsCompleted(
    attendance: attendance,
    clockOutAuditPayload: clockOutAuditPayload,
  );
  if (unitsCompleted != null) {
    final resolvedCount = unitsCompleted.ceil();
    return resolvedCount < 1 ? 1 : resolvedCount;
  }
  final auditRequiredProofs =
      attendance.clockOutAudit?.requiredProofs ?? attendance.requiredProofs;
  if (auditRequiredProofs != null && auditRequiredProofs > 0) {
    return auditRequiredProofs;
  }
  return 1;
}

num? _resolveUnitsCompleted({
  required StaffAttendanceRecord attendance,
  required Map<String, dynamic>? clockOutAuditPayload,
}) {
  final payloadValue = clockOutAuditPayload?["unitsCompleted"];
  final parsedPayload = _parseNum(payloadValue);
  if (parsedPayload != null && parsedPayload >= 0) {
    return parsedPayload;
  }
  final recordValue =
      attendance.clockOutAudit?.unitsCompleted ??
      attendance.numberOfUnitsCompleted;
  if (recordValue != null && recordValue >= 0) {
    return recordValue;
  }
  return null;
}

int _firstMissingProofSlot({
  required int requiredProofs,
  required Map<int, PickedAttendanceProofData> selectedFilesByUnitIndex,
  required Map<int, StaffAttendanceProof> uploadedProofsByUnitIndex,
}) {
  for (var unitIndex = 1; unitIndex <= requiredProofs; unitIndex++) {
    if (selectedFilesByUnitIndex.containsKey(unitIndex)) {
      continue;
    }
    if (uploadedProofsByUnitIndex.containsKey(unitIndex)) {
      continue;
    }
    return unitIndex;
  }
  return requiredProofs;
}

num? _parseNum(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value;
  }
  return num.tryParse(value.toString());
}

String _resolveProofType(String? mimeType) {
  final normalizedMimeType = mimeType?.trim().toLowerCase() ?? "";
  if (normalizedMimeType.startsWith("image/")) {
    return "image";
  }
  if (normalizedMimeType.startsWith("video/")) {
    return "video";
  }
  if (normalizedMimeType.isNotEmpty) {
    return "document";
  }
  return "";
}

String _formatUploadMoment(DateTime value) {
  final localValue = value.toLocal();
  final hour = localValue.hour.toString().padLeft(2, "0");
  final minute = localValue.minute.toString().padLeft(2, "0");
  return "${localValue.year}-${localValue.month.toString().padLeft(2, "0")}-${localValue.day.toString().padLeft(2, "0")} $hour:$minute";
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
