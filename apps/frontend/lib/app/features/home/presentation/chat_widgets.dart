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
/// - Renders attachment previews + metadata with safe open actions.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
const double _kAttachmentThumbSize = 44;
const double _kAttachmentMaxWidth = 220;
const double _kSpacingXs = 6;
const double _kSpacingSm = 8;
const double _kSpacingMd = 12;
const double _kSpacingLg = 16;
const int _kMaxContactAvatars = 6;
const int _kPreviewMaxLines = 1;
const int _kAttachmentNameLines = 1;
const int _kAttachmentMetaLines = 1;
const int _kTimePad = 2;
const String _kInitialFallback = "?";
const String _kTimeFallback = "N/A";
const String _kLogTag = "CHAT_INBOX";
const String _kLogDisplayNameMissing = "display_name_missing";
const String _kAttachmentLogTag = "CHAT_ATTACHMENTS";
const String _kAttachmentOpenTap = "attachment_open_tap";
const String _kAttachmentOpenFail = "attachment_open_fail";
const String _kAttachmentOpenSuccess = "attachment_open_success";
const String _kAttachmentTypeImage = "image";
const int _kBytesInKb = 1024;
const int _kBytesInMb = 1024 * 1024;

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

// WHY: Centralize attachment copy to avoid inline strings.
class _ChatAttachmentCopy {
  static const String fallbackName = "Attachment";
  static const String imageLabel = "Image";
  static const String documentLabel = "Document";
  static const String openFail = "Unable to open attachment.";
  static const String missingUrl = "Attachment link is unavailable.";
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
    // WHY: Hide the label when vertical space is too tight to avoid overflow.
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabel = constraints.maxHeight >= _kContactAvatarHeight;
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
            if (showLabel) ...[
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
          ],
        );
      },
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
    // WHY: Use a safe label when uploads omit filenames.
    final displayName = attachment.filename.isNotEmpty
        ? attachment.filename
        : _ChatAttachmentCopy.fallbackName;
    // WHY: Show size/type metadata so users understand the file.
    final subtitle = _attachmentSubtitle(attachment);
    return InkWell(
      // WHY: Allow quick preview/open from the message bubble.
      onTap: () => _openAttachment(context, attachment),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: _kAttachmentMaxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AttachmentPreview(attachment: attachment),
            const SizedBox(width: _kSpacingSm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: _kAttachmentNameLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: _kAttachmentMetaLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  final ChatAttachment attachment;

  const _AttachmentPreview({
    required this.attachment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = _isImageAttachment(attachment);
    // WHY: Show a neutral placeholder for documents and unknown types.
    if (!isImage) {
      return Container(
        width: _kAttachmentThumbSize,
        height: _kAttachmentThumbSize,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.insert_drive_file,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    // WHY: Skip image preview when the URL is unavailable to prevent crashes.
    if (attachment.url.trim().isEmpty) {
      return Container(
        width: _kAttachmentThumbSize,
        height: _kAttachmentThumbSize,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.image_not_supported,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        attachment.url,
        width: _kAttachmentThumbSize,
        height: _kAttachmentThumbSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          // WHY: Protect the bubble layout when the image fails to load.
          return Container(
            width: _kAttachmentThumbSize,
            height: _kAttachmentThumbSize,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.image_not_supported,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        },
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
    // WHY: Mirror message attachment metadata in the pending chip.
    final displayName = attachment.filename.isNotEmpty
        ? attachment.filename
        : _ChatAttachmentCopy.fallbackName;
    final subtitle = _attachmentSubtitle(attachment);
    return InputChip(
      // WHY: Let users preview before sending when possible.
      onPressed: () => _openAttachment(context, attachment),
      onDeleted: onRemove,
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayName, style: theme.textTheme.labelSmall),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

String _attachmentSubtitle(ChatAttachment attachment) {
  // WHY: Combine type + size to make attachments easier to scan.
  final sizeLabel = _formatBytes(attachment.sizeBytes);
  final typeLabel = _attachmentTypeLabel(attachment);
  if (sizeLabel.isEmpty && typeLabel.isEmpty) return "";
  if (sizeLabel.isEmpty) return typeLabel;
  if (typeLabel.isEmpty) return sizeLabel;
  return "$typeLabel | $sizeLabel";
}

String _attachmentTypeLabel(ChatAttachment attachment) {
  // WHY: Prefer explicit image labels so users know previews are tappable.
  if (_isImageAttachment(attachment)) {
    return _ChatAttachmentCopy.imageLabel;
  }
  // WHY: Default unknown types to document for safe user expectations.
  if (attachment.mimeType.isNotEmpty || attachment.type.isNotEmpty) {
    return _ChatAttachmentCopy.documentLabel;
  }
  return "";
}

bool _isImageAttachment(ChatAttachment attachment) {
  // WHY: Accept either normalized type or mimeType for image detection.
  if (attachment.type.toLowerCase() == _kAttachmentTypeImage) {
    return true;
  }
  return attachment.mimeType.toLowerCase().startsWith("image/");
}

String _formatBytes(int bytes) {
  // WHY: Render readable file sizes for attachment metadata.
  if (bytes <= 0) return "";
  if (bytes >= _kBytesInMb) {
    final value = (bytes / _kBytesInMb).toStringAsFixed(1);
    return "${value}MB";
  }
  if (bytes >= _kBytesInKb) {
    final value = (bytes / _kBytesInKb).toStringAsFixed(1);
    return "${value}KB";
  }
  return "${bytes}B";
}

Future<void> _openAttachment(
  BuildContext context,
  ChatAttachment attachment,
) async {
  // WHY: Log attachment taps for troubleshooting file-open issues.
  AppDebug.log(
    _kAttachmentLogTag,
    _kAttachmentOpenTap,
    extra: {"attachmentId": attachment.id, "type": attachment.type},
  );

  final url = attachment.url.trim();
  if (url.isEmpty) {
    // WHY: Avoid attempting to open invalid URLs.
    AppDebug.log(
      _kAttachmentLogTag,
      _kAttachmentOpenFail,
      extra: {
        "attachmentId": attachment.id,
        "reason": "missing_url",
        "resolution": "Ensure attachment url is included in API payload.",
      },
    );
    _showAttachmentMessage(context, _ChatAttachmentCopy.missingUrl);
    return;
  }

  if (_isImageAttachment(attachment)) {
    // WHY: Use an in-app preview for images so users do not lose context.
    await showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          insetPadding: const EdgeInsets.all(_kSpacingLg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
    AppDebug.log(
      _kAttachmentLogTag,
      _kAttachmentOpenSuccess,
      extra: {"attachmentId": attachment.id, "type": attachment.type},
    );
    return;
  }

  final uri = Uri.tryParse(url);
  if (uri == null) {
    // WHY: Guard against malformed URLs to prevent launcher errors.
    AppDebug.log(
      _kAttachmentLogTag,
      _kAttachmentOpenFail,
      extra: {
        "attachmentId": attachment.id,
        "reason": "invalid_url",
        "resolution": "Ensure attachment url is a valid http(s) link.",
      },
    );
    _showAttachmentMessage(context, _ChatAttachmentCopy.openFail);
    return;
  }

  final launched = await launchUrl(
    uri,
    mode: LaunchMode.platformDefault,
  );

  if (!launched) {
    // WHY: Tell users when the file cannot be opened by the platform.
    AppDebug.log(
      _kAttachmentLogTag,
      _kAttachmentOpenFail,
      extra: {
        "attachmentId": attachment.id,
        "reason": "launch_failed",
        "resolution": "Ensure a compatible app is installed to open the file.",
      },
    );
    _showAttachmentMessage(context, _ChatAttachmentCopy.openFail);
    return;
  }

  AppDebug.log(
    _kAttachmentLogTag,
    _kAttachmentOpenSuccess,
    extra: {"attachmentId": attachment.id, "type": attachment.type},
  );
}

void _showAttachmentMessage(BuildContext context, String message) {
  // WHY: Provide immediate feedback when attachments cannot be opened.
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
