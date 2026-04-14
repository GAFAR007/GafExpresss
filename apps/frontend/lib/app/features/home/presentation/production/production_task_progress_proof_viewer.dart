/// lib/app/features/home/presentation/production/production_task_progress_proof_viewer.dart
/// ----------------------------------------------------------------------------------------
/// WHAT:
/// - Proof image browser and preview helpers for production task progress.
///
/// WHY:
/// - Managers need to review saved proof images directly from task logs.
/// - Newly selected proof images should be inspectable before submission.
///
/// HOW:
/// - Uses a date-filtered browser for saved proof records.
/// - Uses an interactive image preview for both saved and newly selected images.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';

const String _browserTitle = "View proof";
const String _browserDateLabel = "Filter by date";
const String _browserDateHint = "Pick another date to inspect proof images.";
const String _browserEmptyTitle = "No proof images for this date";
const String _browserEmptyMessage =
    "Select a different date to see saved proof images.";
const String _browserCloseLabel = "Close";
const String _browserOpenLabel = "View proof";
const String _previewCloseLabel = "Close";
const String _previewMissingLabel = "Proof image is unavailable.";
const String _previewSizeLabel = "Size";
const String _previewDateLabel = "Date";
const String _previewByLabel = "By";
const String _previewDocumentLabel = "Open file";
const String _previewOpenFail = "Unable to open proof file.";
const String _previewMissingUrl = "Proof file link is unavailable.";

Future<void> showProductionTaskProgressPickedProofPreview(
  BuildContext context, {
  required ProductionTaskProgressProofInput proof,
}) async {
  final bytes = proof.bytes.isEmpty ? null : Uint8List.fromList(proof.bytes);
  if (bytes == null) {
    return;
  }

  await _showImagePreviewDialog(
    context,
    title: proof.displayLabel,
    subtitle: _formatProofSize(proof.sizeBytes),
    image: Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return const Center(child: Text(_previewMissingLabel));
      },
    ),
  );
}

Future<void> showProductionTaskProgressProofBrowser(
  BuildContext context, {
  required List<ProductionTimelineRow> rows,
  DateTime? initialDate,
}) async {
  DateTime selectedDate = _normalizeDay(
    initialDate ?? DateTime.now().toLocal(),
  );

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredRows = _rowsForDate(rows: rows, day: selectedDate);
          final proofRows = filteredRows
              .where((row) => row.proofs.isNotEmpty)
              .toList();
          final proofImageCount = proofRows.fold<int>(
            0,
            (sum, row) => sum + row.proofCount,
          );

          proofRows.sort((left, right) {
            final leftDate =
                left.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            final rightDate =
                right.workDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            final dateCompare = leftDate.compareTo(rightDate);
            if (dateCompare != 0) {
              return dateCompare;
            }
            final taskCompare = left.taskTitle.compareTo(right.taskTitle);
            if (taskCompare != 0) {
              return taskCompare;
            }
            return left.farmerName.compareTo(right.farmerName);
          });

          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _browserTitle,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _browserDateHint,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text(_browserCloseLabel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020, 1, 1),
                              lastDate: DateTime(2100, 12, 31),
                            );
                            if (picked == null) {
                              return;
                            }
                            setDialogState(() {
                              selectedDate = _normalizeDay(picked);
                            });
                          },
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(
                            "$_browserDateLabel: ${formatDateLabel(selectedDate)}",
                          ),
                        ),
                        Chip(
                          avatar: const Icon(Icons.image_outlined, size: 18),
                          label: Text("$proofImageCount proof image(s)"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: proofRows.isEmpty
                          ? Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.image_search_outlined,
                                      size: 44,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _browserEmptyTitle,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _browserEmptyMessage,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: proofRows.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final row = proofRows[index];
                                return _ProofRowCard(
                                  row: row,
                                  onOpenProof: (proof, proofIndex) {
                                    final title = proof.filename.isNotEmpty
                                        ? proof.filename
                                        : "$_browserOpenLabel ${proofIndex + 1}";
                                    showProductionTaskProgressSavedProofPreview(
                                      dialogContext,
                                      title: title,
                                      proof: proof,
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showProductionTaskProgressSavedProofPreview(
  BuildContext context, {
  required String title,
  required ProductionTaskProgressProofRecord proof,
}) async {
  final url = proof.url.trim();
  if (url.isEmpty) {
    _showProofMessage(context, _previewMissingUrl);
    return;
  }

  if (_isImageProof(proof)) {
    await _showImagePreviewDialog(
      context,
      title: title,
      subtitle: _buildNetworkProofSubtitle(proof),
      image: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Center(child: Text(_previewMissingLabel));
        },
      ),
    );
    return;
  }

  final uri = Uri.tryParse(url);
  if (uri == null) {
    _showProofMessage(context, _previewOpenFail);
    return;
  }
  final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
  if (!context.mounted) {
    return;
  }
  if (!opened) {
    _showProofMessage(context, _previewOpenFail);
  }
}

String _buildNetworkProofSubtitle(ProductionTaskProgressProofRecord proof) {
  final parts = <String>[];
  if (proof.uploadedAt != null) {
    parts.add("$_previewDateLabel: ${formatDateLabel(proof.uploadedAt)}");
  }
  if (proof.mimeType.trim().isNotEmpty) {
    parts.add(proof.mimeType.trim());
  }
  if (proof.sizeBytes > 0) {
    parts.add("$_previewSizeLabel: ${_formatProofSize(proof.sizeBytes)}");
  }
  if (proof.uploadedBy.trim().isNotEmpty &&
      !_looksLikeObjectId(proof.uploadedBy)) {
    parts.add("$_previewByLabel: ${proof.uploadedBy.trim()}");
  }
  if (parts.isEmpty) {
    return "";
  }
  return parts.join(" • ");
}

Future<void> _showImagePreviewDialog(
  BuildContext context, {
  required String title,
  required Widget image,
  String? subtitle,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 780),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle != null &&
                              subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle.trim(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(_previewCloseLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Center(child: image),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(_previewCloseLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _formatProofSize(int sizeBytes) {
  if (sizeBytes <= 0) {
    return "0 B";
  }
  if (sizeBytes < 1024) {
    return "$sizeBytes B";
  }
  if (sizeBytes < 1024 * 1024) {
    final kb = sizeBytes / 1024;
    return "${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB";
  }
  final mb = sizeBytes / (1024 * 1024);
  return "${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB";
}

bool _looksLikeObjectId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r"^[a-f0-9]{24}$", caseSensitive: false).hasMatch(normalized);
}

bool _isImageProof(ProductionTaskProgressProofRecord proof) {
  final mimeType = proof.mimeType.trim().toLowerCase();
  if (mimeType.startsWith("image/")) {
    return true;
  }
  final filename = proof.filename.trim().toLowerCase();
  return filename.endsWith(".png") ||
      filename.endsWith(".jpg") ||
      filename.endsWith(".jpeg") ||
      filename.endsWith(".gif") ||
      filename.endsWith(".webp") ||
      filename.endsWith(".bmp") ||
      filename.endsWith(".heic");
}

void _showProofMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

String _proofRowTitle(ProductionTimelineRow row) {
  final taskTitle = row.taskTitle.trim();
  if (taskTitle.isNotEmpty) {
    return taskTitle;
  }
  return _browserTitle;
}

List<ProductionTimelineRow> _rowsForDate({
  required List<ProductionTimelineRow> rows,
  required DateTime day,
}) {
  final normalizedDay = _normalizeDay(day);
  final items = rows
      .where((row) => _isSameDay(row.workDate?.toLocal(), normalizedDay))
      .toList();
  items.sort((left, right) {
    final leftTask = left.taskTitle.toLowerCase();
    final rightTask = right.taskTitle.toLowerCase();
    final taskCompare = leftTask.compareTo(rightTask);
    if (taskCompare != 0) {
      return taskCompare;
    }
    return left.farmerName.toLowerCase().compareTo(
      right.farmerName.toLowerCase(),
    );
  });
  return items;
}

bool _isSameDay(DateTime? left, DateTime right) {
  if (left == null) {
    return false;
  }
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

DateTime _normalizeDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

class _ProofRowCard extends StatelessWidget {
  final ProductionTimelineRow row;
  final void Function(ProductionTaskProgressProofRecord proof, int index)
  onOpenProof;

  const _ProofRowCard({required this.row, required this.onOpenProof});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final proofs = row.proofs;
    final rowDate = row.workDate == null
        ? "Undated"
        : formatDateLabel(row.workDate);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _proofRowTitle(row),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${rowDate.isEmpty ? "Unscheduled date" : rowDate} • ${row.farmerName.trim().isEmpty ? "Unassigned" : row.farmerName.trim()}",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Chip(
                avatar: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text("${row.proofCount} proof(s)"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniInfoChip(
                context,
                label: "Actual amount: ${row.actualPlots}",
                icon: Icons.insights_outlined,
              ),
              if (row.phaseName.trim().isNotEmpty)
                _miniInfoChip(
                  context,
                  label: row.phaseName.trim(),
                  icon: Icons.segment_outlined,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in proofs.asMap().entries)
                TextButton.icon(
                  onPressed: entry.value.url.trim().isEmpty
                      ? null
                      : () => onOpenProof(entry.value, entry.key),
                  icon: Icon(
                    _isImageProof(entry.value)
                        ? Icons.visibility_outlined
                        : Icons.attach_file_outlined,
                  ),
                  label: Text(
                    entry.value.filename.trim().isNotEmpty
                        ? entry.value.filename.trim()
                        : (_isImageProof(entry.value)
                              ? "$_browserOpenLabel ${entry.key + 1}"
                              : "$_previewDocumentLabel ${entry.key + 1}"),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _miniInfoChip(
  BuildContext context, {
  required String label,
  required IconData icon,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: colorScheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
