/// lib/app/features/home/presentation/chat_widgets.dart
/// ----------------------------------------------------
/// WHAT:
/// - Reusable UI widgets for chat inbox + thread views.
///
/// WHY:
/// - Keeps screen widgets small and readable.
/// - Ensures consistent styling across chat surfaces.
///
/// HOW:
/// - Provides conversation tiles, message bubbles, and attachment chips.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';

// WHY: Keep inbox sizing consistent across reusable widgets.
const double _kAvatarSize = 44;
const double _kAvatarSmall = 36;
// WHY: Reserve space for the label so the avatar strip doesn't overflow.
// WHY: Reserve space for the label so the avatar strip doesn't overflow.
const double _kContactAvatarHeight = _kAvatarSmall + _kSpacingSm + 18;
const double _kChipRadius = 16;
const double _kCardRadius = 20;
const double _kTileRadius = 16;
const double _kHeroOpacity = 0.18;
const double _kChevronSize = 18;
const double _kSpacingXs = 6;
const double _kSpacingSm = 8;
const double _kSpacingMd = 12;
const double _kSpacingLg = 16;
const int _kMaxContactAvatars = 6;
const int _kPreviewMaxLines = 1;
const int _kTimePad = 2;
const String _kInitialFallback = "?";
const String _kTimeFallback = "N/A";
const String _kLogTag = "CHAT_INBOX";
const String _kLogDisplayNameMissing = "display_name_missing";

// WHY: Keep chat type labels centralized to avoid inline strings.
class _ChatInboxCopy {
  static const String overviewTitle = "Chat overview";
  static const String conversationsLabel = "Conversations";
  static const String directLabel = "Direct";
  static const String groupLabel = "Group";
  static const String searchLabel = "Search";
  static const String noDirectContacts = "No direct chats yet";
  static const String missingDisplayName = "Unknown participant";
  static const String noMessages = "No messages yet";
}

class ChatInboxHeroCard extends StatelessWidget {
  final int totalCount;
  final int directCount;
  final int groupCount;

  const ChatInboxHeroCard({
    super.key,
    required this.totalCount,
    required this.directCount,
    required this.groupCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Highlight inbox stats in a friendly, glanceable card.
    return Container(
      padding: const EdgeInsets.all(_kSpacingLg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(_kHeroOpacity),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ChatInboxCopy.overviewTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: _kSpacingSm),
          Row(
            children: [
              _StatChip(
                label: _ChatInboxCopy.conversationsLabel,
                value: totalCount.toString(),
              ),
              const SizedBox(width: _kSpacingSm),
              _StatChip(
                label: _ChatInboxCopy.directLabel,
                value: directCount.toString(),
              ),
              const SizedBox(width: _kSpacingSm),
              _StatChip(
                label: _ChatInboxCopy.groupLabel,
                value: groupCount.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _kSpacingSm,
        vertical: _kSpacingXs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(_kChipRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: _kSpacingXs),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatInboxContactStrip extends StatelessWidget {
  final List<ChatConversation> conversations;
  final ValueChanged<ChatConversation> onTap;

  const ChatInboxContactStrip({
    super.key,
    required this.conversations,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contacts = conversations.take(_kMaxContactAvatars).toList();
    // WHY: Provide quick access to recent direct chats.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _ChatInboxCopy.directLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: _kSpacingSm),
        if (contacts.isEmpty)
          Text(
            _ChatInboxCopy.noDirectContacts,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          SizedBox(
            height: _kContactAvatarHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const SizedBox(width: _kSpacingSm),
              itemBuilder: (context, index) {
                final conversation = contacts[index];
                return GestureDetector(
                  onTap: () => onTap(conversation),
                  child: _ChatContactAvatar(
                    label: _conversationTitle(conversation),
                    avatarUrl: conversation.displayAvatar,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ChatContactAvatar extends StatelessWidget {
  final String label;
  final String avatarUrl;

  const _ChatContactAvatar({
    required this.label,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _initialsFor(label);
    final hasAvatar = avatarUrl.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: _kAvatarSmall / 2,
          backgroundColor: theme.colorScheme.secondaryContainer,
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
          child: hasAvatar
              ? null
              : Text(
                  initials,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: _kSpacingXs),
        SizedBox(
          width: _kAvatarSmall + _kSpacingSm,
          child: Text(
            label,
            style: theme.textTheme.labelSmall,
            maxLines: _kPreviewMaxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class ChatInboxSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const ChatInboxSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Provide a dedicated search input for quick filtering.
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: _ChatInboxCopy.searchLabel,
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class ChatInboxFilterRow extends StatelessWidget {
  final int directCount;
  final int groupCount;
  final bool isDirectSelected;
  final VoidCallback onSelectDirect;
  final VoidCallback onSelectGroup;

  const ChatInboxFilterRow({
    super.key,
    required this.directCount,
    required this.groupCount,
    required this.isDirectSelected,
    required this.onSelectDirect,
    required this.onSelectGroup,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Use pill toggles to switch between direct/group views.
    return Container(
      padding: const EdgeInsets.all(_kSpacingXs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_kChipRadius + 4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FilterChip(
              label: "${_ChatInboxCopy.directLabel} ($directCount)",
              selected: isDirectSelected,
              onTap: onSelectDirect,
            ),
          ),
          const SizedBox(width: _kSpacingSm),
          Expanded(
            child: _FilterChip(
              label: "${_ChatInboxCopy.groupLabel} ($groupCount)",
              selected: !isDirectSelected,
              onTap: onSelectGroup,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_kChipRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: _kSpacingSm,
          horizontal: _kSpacingSm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(_kChipRadius),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class ChatInboxSectionHeader extends StatelessWidget {
  final String label;

  const ChatInboxSectionHeader({
    super.key,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class ChatInboxEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const ChatInboxEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(_kSpacingLg),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: _kSpacingSm),
          Text(
            title,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: _kSpacingXs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class ChatConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;

  const ChatConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Provide a stable label when a direct chat has no title.
    final displayName = conversation.displayName.trim();
    final titleFallback = conversation.title.trim();
    final resolvedTitle =
        displayName.isNotEmpty ? displayName : titleFallback;
    // WHY: Log if backend fails to provide displayName/title so we can fix the API.
    if (resolvedTitle.isEmpty) {
      AppDebug.log(
        _kLogTag,
        _kLogDisplayNameMissing,
        extra: {
          "conversationId": conversation.id,
          "type": conversation.type,
          "title": conversation.title,
          "resolution":
              "Ensure backend returns displayName for direct/group chats.",
        },
      );
    }
    final title = resolvedTitle.isNotEmpty
        ? resolvedTitle
        : _ChatInboxCopy.missingDisplayName;
    // WHY: Show a friendly placeholder when no messages exist.
    final subtitle = conversation.lastMessagePreview.isNotEmpty
        ? conversation.lastMessagePreview
        : _ChatInboxCopy.noMessages;
    final timeLabel = _formatConversationTime(
      conversation.lastMessageAt ?? conversation.createdAt,
    );
    final avatarUrl = conversation.displayAvatar.trim();
    final hasAvatar = avatarUrl.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_kTileRadius),
      child: Container(
        padding: const EdgeInsets.all(_kSpacingMd),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(_kTileRadius),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: _kAvatarSize / 2,
              backgroundColor: theme.colorScheme.secondaryContainer,
              backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              child: hasAvatar
                  ? null
                  : Text(
                      _initialsFor(title),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(width: _kSpacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: _kSpacingXs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: _kPreviewMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: _kSpacingSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: _kSpacingXs),
                Icon(
                  Icons.chevron_right,
                  size: _kChevronSize,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Use different bubble colors for sender vs receiver.
    final bubbleColor = isMine
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    // WHY: Ensure contrast against the chosen bubble background.
    final textColor = isMine
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.body.isNotEmpty)
              Text(
                message.body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                ),
              ),
            if (message.attachments.isNotEmpty) ...[
              if (message.body.isNotEmpty) const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.attachments
                    .map((attachment) => _AttachmentChip(attachment: attachment))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _conversationTitle(ChatConversation conversation) {
  final displayName = conversation.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final titleFallback = conversation.title.trim();
  if (titleFallback.isNotEmpty) return titleFallback;
  AppDebug.log(
    _kLogTag,
    _kLogDisplayNameMissing,
    extra: {
      "conversationId": conversation.id,
      "type": conversation.type,
      "title": conversation.title,
      "resolution":
          "Ensure backend returns displayName or title for inbox rendering.",
    },
  );
  return _ChatInboxCopy.missingDisplayName;
}

String _initialsFor(String name) {
  final parts = name.trim().split(RegExp(r"\s+"));
  if (parts.isEmpty || parts.first.isEmpty) return _kInitialFallback;
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  final first = parts.first.characters.first;
  final last = parts.last.characters.first;
  return "${first.toUpperCase()}${last.toUpperCase()}";
}

String _formatConversationTime(DateTime? value) {
  if (value == null) return _kTimeFallback;
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(_kTimePad, '0');
  final minute = local.minute.toString().padLeft(_kTimePad, '0');
  return "$hour:$minute";
}

class _AttachmentChip extends StatelessWidget {
  final ChatAttachment attachment;

  const _AttachmentChip({
    required this.attachment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.attach_file,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            attachment.filename.isNotEmpty ? attachment.filename : "Attachment",
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatAttachmentChip extends StatelessWidget {
  final ChatAttachment attachment;
  final VoidCallback onRemove;

  const ChatAttachmentChip({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(
        attachment.filename.isNotEmpty ? attachment.filename : "Attachment",
        style: theme.textTheme.labelSmall,
      ),
      onDeleted: onRemove,
    );
  }
}
