/// lib/app/features/home/presentation/chat_profile_sheet.dart
/// ----------------------------------------------------------
/// WHAT:
/// - Bottom sheet for viewing chat participant profiles.
///
/// WHY:
/// - Gives users quick context (role + business) while chatting.
/// - Keeps profile UI reusable across chat threads.
///
/// HOW:
/// - Renders a summary header and participant cards.
/// - Uses theme tokens for safe styling in all themes.
///
/// DEBUGGING:
/// - Logs open events for traceability.
/// ----------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';

const String _logTag = "CHAT_PROFILE_SHEET";
const String _logOpen = "profile_sheet_open";
const String _logTapClose = "profile_sheet_close";

const String _title = "Profile";
const String _sectionMembers = "Members";
const String _labelRole = "Role";
const String _labelBusiness = "Business";
const String _labelEstate = "Estate";
const String _labelStatus = "Status";
const String _fallbackBusiness = "Not assigned";
const String _fallbackEstate = "Not assigned";
const String _fallbackRole = "unknown";
const String _statusMember = "Member";
const String _avatarFallbackInitial = "?";
const String _tooltipClose = "Close";

const double _sheetPadding = 16;
const double _cardSpacing = 12;
const double _chipSpacing = 6;
const double _avatarRadius = 20;

Future<void> showChatProfileSheet({
  required BuildContext context,
  required List<ChatParticipantSummary> participants,
}) async {
  AppDebug.log(
    _logTag,
    _logOpen,
    extra: {"count": participants.length},
  );

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _ChatProfileSheet(
      participants: participants,
    ),
  );
}

class _ChatProfileSheet extends StatelessWidget {
  final List<ChatParticipantSummary> participants;

  const _ChatProfileSheet({
    required this.participants,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(_sheetPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_title, style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: () {
                  AppDebug.log(_logTag, _logTapClose);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close),
                tooltip: _tooltipClose,
              ),
            ],
          ),
          const SizedBox(height: _cardSpacing),
          Text(
            _sectionMembers,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _cardSpacing),
          ...participants.map(
            (participant) =>
                _ParticipantProfileCard(participant: participant),
          ),
        ],
      ),
    );
  }
}

class _ParticipantProfileCard extends StatelessWidget {
  final ChatParticipantSummary participant;

  const _ParticipantProfileCard({
    required this.participant,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = participant.name.trim().isEmpty
        ? participant.email
        : participant.name;
    final avatarUrl = participant.profileImageUrl.trim();
    final businessLabel = participant.businessName.trim().isNotEmpty
        ? participant.businessName
        : (participant.businessId.trim().isNotEmpty
            ? participant.businessId
            : _fallbackBusiness);
    final estateLabel = participant.estateName.trim().isNotEmpty
        ? participant.estateName
        : participant.estateAssetId.trim().isNotEmpty
            ? participant.estateAssetId
            : _fallbackEstate;
    final roleLabel = participant.role.trim().isEmpty
        ? _fallbackRole
        : participant.role.replaceAll("_", " ");

    return Container(
      margin: const EdgeInsets.only(bottom: _cardSpacing),
      padding: const EdgeInsets.all(_sheetPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: _avatarRadius,
            backgroundColor: colorScheme.primaryContainer,
            // WHY: Use avatar when provided to improve recognition.
            backgroundImage:
                avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
            child: avatarUrl.isEmpty
                ? Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : _avatarFallbackInitial,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: _cardSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: theme.textTheme.titleSmall),
                if (participant.email.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    participant.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: _chipSpacing),
                Wrap(
                  spacing: _chipSpacing,
                  runSpacing: _chipSpacing,
                  children: [
                    _MetaChip(
                      label: _labelRole,
                      value: roleLabel,
                    ),
                    _MetaChip(
                      label: _labelBusiness,
                      value: businessLabel,
                    ),
                    _MetaChip(
                      label: _labelEstate,
                      value: estateLabel,
                    ),
                    _MetaChip(
                      label: _labelStatus,
                      // WHY: Status reflects membership (not online presence).
                      value: _statusMember,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Chip(
      label: Text(
        "$label: $value",
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: colorScheme.surface,
      side: BorderSide(color: colorScheme.outlineVariant),
    );
  }
}
