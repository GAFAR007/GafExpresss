/// lib/app/features/home/presentation/chat_thread_screen.dart
/// ----------------------------------------------------------
/// WHAT:
/// - Chat thread screen for a single conversation.
///
/// WHY:
/// - Provides a focused view to read and send messages.
/// - Supports attachments with optimistic UI updates.
///
/// HOW:
/// - Uses ChatThreadController for state + socket updates.
/// - Renders message list + composer with attachment chips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_attachment_picker.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_profile_sheet.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_routes.dart';
import 'package:frontend/app/features/home/presentation/chat_widgets.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

const String _logTag = "CHAT_THREAD";
const String _logBuild = "build()";
const String _logSendTap = "send_tap";
const String _logAttachTap = "attach_tap";
const String _logAttachPick = "attach_pick";
const String _logBackTap = "back_tap";
const String _logProfileTap = "profile_tap";
const String _logCallTap = "call_tap";
const String _logVideoTap = "video_tap";

const String _fallbackTitle = "Chat";
const String _fallbackRole = "unknown";
const String _fallbackBusiness = "Not assigned";
const String _fallbackEstate = "Not assigned";
const String _groupRoleLabel = "Group";
const String _multipleLabel = "Multiple";
const String _metaSeparator = " • ";
const String _conversationTypeGroup = "group";
const String _avatarFallbackInitial = "?";
const String _comingSoonCall = "Calls are coming soon.";
const String _comingSoonVideo = "Video is coming soon.";
const String _tooltipCall = "Call (coming soon)";
const String _tooltipVideo = "Video (coming soon)";
const String _tooltipInfo = "Chat info";

const double _headerMetaSpacing = 2;
const double _appBarInfoHeight = 68;
const double _participantPillAvatarRadius = 12;
const double _participantPillSpacing = 8;
const double _participantPillPaddingH = 8;
const double _participantPillPaddingV = 6;
const double _participantPillRadius = 999;
const EdgeInsets _appBarInfoPadding =
    EdgeInsets.fromLTRB(16, 0, 16, 8);

class ChatThreadArgs {
  final ChatConversation? conversation;

  const ChatThreadArgs({this.conversation});
}

class ChatThreadScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final ChatThreadArgs? args;

  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    this.args,
  });

  @override
  ConsumerState<ChatThreadScreen> createState() =>
      _ChatThreadScreenState();
}

class _ChatThreadScreenState
    extends ConsumerState<ChatThreadScreen> {
  final TextEditingController _messageCtrl =
      TextEditingController();

  void _log(String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(_logTag, message, extra: extra);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _resolveTitle({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
    required String currentUserId,
  }) {
    // WHY: Prefer explicit titles, then fall back to the other participant.
    final title = conversation?.title.trim() ?? "";
    if (title.isNotEmpty) return title;

    if (participants.isEmpty) return _fallbackTitle;
    final other = participants.firstWhere(
      (participant) => participant.userId != currentUserId,
      orElse: () => participants.first,
    );
    return other.name.trim().isNotEmpty
        ? other.name
        : other.email.trim().isNotEmpty
            ? other.email
            : _fallbackTitle;
  }

  List<ChatParticipantSummary> _resolveParticipants({
    required ChatConversationDetail? detail,
    required String currentUserId,
  }) {
    // WHY: Hide the current user when showing profile cards.
    if (detail == null) return [];
    return detail.participants
        .where((participant) => participant.userId != currentUserId)
        .toList();
  }

  ChatParticipantSummary? _resolvePrimaryParticipant(
    List<ChatParticipantSummary> participants,
  ) {
    // WHY: Use a single participant to derive direct chat metadata.
    return participants.isEmpty ? null : participants.first;
  }

  String _resolveRoleLabel({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
  }) {
    // WHY: Group chats should show a group label instead of a person role.
    if (conversation?.type == _conversationTypeGroup) {
      return _groupRoleLabel;
    }
    final participant = _resolvePrimaryParticipant(participants);
    final role = participant?.role.trim() ?? "";
    return role.isEmpty ? _fallbackRole : role.replaceAll("_", " ");
  }

  String _resolveGroupValue(
    List<ChatParticipantSummary> participants,
    String Function(ChatParticipantSummary participant) selector,
    String fallback,
  ) {
    // WHY: Aggregate group metadata without misleading single-user values.
    final values = participants
        .map(selector)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (values.isEmpty) return fallback;
    if (values.length == 1) return values.first;
    return _multipleLabel;
  }

  String _resolveBusinessLabel({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
  }) {
    // WHY: Prefer business display names while keeping group context safe.
    if (conversation?.type == _conversationTypeGroup) {
      return _resolveGroupValue(
        participants,
        (participant) =>
            participant.businessName.isNotEmpty
                ? participant.businessName
                : participant.businessId,
        _fallbackBusiness,
      );
    }
    final participant = _resolvePrimaryParticipant(participants);
    if (participant == null) return _fallbackBusiness;
    if (participant.businessName.trim().isNotEmpty) {
      return participant.businessName;
    }
    return participant.businessId.trim().isNotEmpty
        ? participant.businessId
        : _fallbackBusiness;
  }

  String _resolveEstateLabel({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
  }) {
    // WHY: Avoid showing a single estate for group chats unless consistent.
    if (conversation?.type == _conversationTypeGroup) {
      return _resolveGroupValue(
        participants,
        (participant) =>
            participant.estateName.isNotEmpty
                ? participant.estateName
                : participant.estateAssetId,
        _fallbackEstate,
      );
    }
    final participant = _resolvePrimaryParticipant(participants);
    if (participant == null) return _fallbackEstate;
    if (participant.estateName.trim().isNotEmpty) {
      return participant.estateName;
    }
    return participant.estateAssetId.trim().isNotEmpty
        ? participant.estateAssetId
        : _fallbackEstate;
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAttach(ChatThreadController controller) async {
    _log(_logAttachTap);
    final picked = await pickChatAttachment();
    if (picked == null) return;
    _log(_logAttachPick, extra: {"name": picked.filename});
    await controller.addAttachment(
      bytes: picked.bytes,
      filename: picked.filename,
    );
  }

  @override
  Widget build(BuildContext context) {
    _log(_logBuild);

    // WHY: Current user id is needed to align message bubbles.
    final session = ref.watch(authSessionProvider);
    final currentUserId = session?.user.id ?? "";
    final state = ref.watch(chatThreadProvider(widget.conversationId));
    final controller =
        ref.read(chatThreadProvider(widget.conversationId).notifier);
    final detailAsync =
        ref.watch(chatConversationDetailProvider(widget.conversationId));
    final detail = detailAsync.asData?.value;

    final conversation = detail?.conversation ?? widget.args?.conversation;
    final participants = _resolveParticipants(
      detail: detail,
      currentUserId: currentUserId,
    );
    final title = _resolveTitle(
      conversation: conversation,
      participants: detail?.participants ?? [],
      currentUserId: currentUserId,
    );
    // WHY: These labels keep the header consistent for direct + group chats.
    final roleLabel = _resolveRoleLabel(
      conversation: conversation,
      participants: participants,
    );
    final businessLabel = _resolveBusinessLabel(
      conversation: conversation,
      participants: participants,
    );
    final estateLabel = _resolveEstateLabel(
      conversation: conversation,
      participants: participants,
    );

    return Scaffold(
      appBar: AppBar(
        title: _ThreadHeaderTitle(
          title: title,
          roleLabel: roleLabel,
          businessLabel: businessLabel,
          estateLabel: estateLabel,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _log(_logBackTap);
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(chatInboxRoute);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            onPressed: () {
              _log(_logCallTap);
              _showMessage(_comingSoonCall);
            },
            tooltip: _tooltipCall,
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () {
              _log(_logVideoTap);
              _showMessage(_comingSoonVideo);
            },
            tooltip: _tooltipVideo,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: participants.isEmpty
                ? null
                : () {
                    _log(_logProfileTap);
                    showChatProfileSheet(
                      context: context,
                      participants: participants,
                    );
                  },
            tooltip: _tooltipInfo,
          ),
        ],
        bottom: participants.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(_appBarInfoHeight),
                child: _ThreadInfoBar(participants: participants),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _MessageList(
                    messages: state.messages,
                    currentUserId: currentUserId,
                  ),
          ),
          if (state.pendingAttachments.isNotEmpty)
            // WHY: Show pending attachments before send for clarity.
            _AttachmentRow(
              attachments: state.pendingAttachments,
              onRemove: (id) => controller.removeAttachment(id),
            ),
          _Composer(
            controller: _messageCtrl,
            isSending: state.isSending,
            onAttach: () => _handleAttach(controller),
            onSend: () {
              _log(_logSendTap);
              final text = _messageCtrl.text;
              // WHY: Send uses optimistic UI in the controller.
              controller.sendMessage(body: text);
              _messageCtrl.clear();
            },
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentUserId;

  const _MessageList({
    required this.messages,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Text("No messages yet"),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMine = message.senderUserId == currentUserId;
        return ChatMessageBubble(
          message: message,
          isMine: isMine,
        );
      },
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final List<ChatAttachment> attachments;
  final void Function(String id) onRemove;

  const _AttachmentRow({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: attachments
            .map(
              (attachment) => ChatAttachmentChip(
                attachment: attachment,
                onRemove: () => onRemove(attachment.id),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ThreadHeaderTitle extends StatelessWidget {
  final String title;
  final String roleLabel;
  final String businessLabel;
  final String estateLabel;

  const _ThreadHeaderTitle({
    required this.title,
    required this.roleLabel,
    required this.businessLabel,
    required this.estateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Stack name and metadata to match the requested header layout.
    final metaText =
        "$roleLabel$_metaSeparator$businessLabel$_metaSeparator$estateLabel";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: _headerMetaSpacing),
        Text(
          metaText,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ThreadInfoBar extends StatelessWidget {
  final List<ChatParticipantSummary> participants;

  const _ThreadInfoBar({
    required this.participants,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep participant context visible without leaving the thread.
    return Container(
      width: double.infinity,
      padding: _appBarInfoPadding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: participants
              .map(
                (participant) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ParticipantInfoPill(
                    participant: participant,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ParticipantInfoPill extends StatelessWidget {
  final ChatParticipantSummary participant;

  const _ParticipantInfoPill({
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
    final roleLabel = participant.role.trim().isEmpty
        ? _fallbackRole
        : participant.role.replaceAll("_", " ");

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _participantPillPaddingH,
        vertical: _participantPillPaddingV,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_participantPillRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: _participantPillAvatarRadius,
            backgroundColor: colorScheme.primaryContainer,
            // WHY: Use avatars when provided; fall back to initials.
            backgroundImage:
                avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
            child: avatarUrl.isEmpty
                ? Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : _avatarFallbackInitial,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: _participantPillSpacing),
          Chip(
            label: Text(
              roleLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: colorScheme.surface,
            side: BorderSide(color: colorScheme.outlineVariant),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onAttach,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: onAttach,
              color: theme.colorScheme.primary,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: "Type a message",
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: isSending ? null : onSend,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
