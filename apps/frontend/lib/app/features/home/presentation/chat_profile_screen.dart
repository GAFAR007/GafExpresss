/// lib/app/features/home/presentation/chat_profile_screen.dart
/// -----------------------------------------------------------
/// WHAT:
/// - Dedicated profile screen for chat participants.
///
/// WHY:
/// - Gives chat a cleaner, Apple-style profile flow than a bottom sheet.
/// - Lets header/profile taps push to a full screen with better hierarchy.
///
/// HOW:
/// - Loads conversation detail from the existing chat provider.
/// - Focuses one participant when a user id is provided.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_routes.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _profileTitle = "Profile";
const String _fallbackBusiness = "Not assigned";
const String _fallbackEstate = "Not assigned";
const String _fallbackRole = "Member";
const String _fallbackName = "Unknown participant";
const String _membersTitle = "People in this chat";
const String _sectionContact = "Contact";
const String _sectionWorkspace = "Workspace";
const String _sectionIdentity = "Identity";

class ChatProfileScreen extends ConsumerWidget {
  final String conversationId;
  final String? focusUserId;

  const ChatProfileScreen({
    super.key,
    required this.conversationId,
    this.focusUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(
      chatConversationDetailProvider(conversationId),
    );
    final session = ref.watch(authSessionProvider);
    final currentUserId = session?.user.id ?? "";
    final currentUserBusinessId = session?.user.businessId ?? "";

    return Theme(
      data: AppTheme.business(),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surfaceContainerLowest,
            appBar: AppBar(centerTitle: true, title: const Text(_profileTitle)),
            body: detailAsync.when(
              data: (detail) {
                final participants = _resolveParticipants(
                  detail.participants,
                  currentUserId: currentUserId,
                  currentUserBusinessId: currentUserBusinessId,
                );
                final focused = _resolveFocusedParticipant(
                  participants,
                  focusUserId: focusUserId,
                );
                final otherParticipants = participants
                    .where(
                      (participant) => participant.userId != focused?.userId,
                    )
                    .toList();

                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.surfaceContainerLowest,
                        scheme.surfaceContainerLow,
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                    children: [
                      if (focused != null) _ProfileHero(participant: focused),
                      if (focused != null) ...[
                        const SizedBox(height: 18),
                        _ProfileSectionCard(
                          title: _sectionIdentity,
                          children: [
                            _ProfileDetailRow(
                              label: "Role",
                              value: _roleLabel(focused),
                            ),
                            _ProfileDetailRow(
                              label: "Account",
                              value: focused.role.trim().isEmpty
                                  ? _fallbackRole
                                  : focused.role.replaceAll("_", " "),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _ProfileSectionCard(
                          title: _sectionContact,
                          children: [
                            _ProfileDetailRow(
                              label: "Email",
                              value: focused.email.trim().isEmpty
                                  ? "No email on file"
                                  : focused.email,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _ProfileSectionCard(
                          title: _sectionWorkspace,
                          children: [
                            _ProfileDetailRow(
                              label: "Business",
                              value: _businessLabel(focused),
                            ),
                            _ProfileDetailRow(
                              label: "Estate",
                              value: _estateLabel(focused),
                            ),
                          ],
                        ),
                      ],
                      if (otherParticipants.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            _membersTitle,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        ...otherParticipants.map(
                          (participant) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ParticipantListTile(
                              participant: participant,
                              onTap: () {
                                context.go(
                                  buildChatProfileRoute(
                                    conversationId,
                                    userId: participant.userId,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      if (focused == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(child: Text("No profile found")),
                        ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "Unable to load this profile right now.",
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<ChatParticipantSummary> _resolveParticipants(
    List<ChatParticipantSummary> participants, {
    required String currentUserId,
    required String currentUserBusinessId,
  }) {
    final withoutCurrentUser = participants
        .where((participant) => participant.userId != currentUserId)
        .toList();
    if (withoutCurrentUser.isNotEmpty) {
      return withoutCurrentUser;
    }

    final normalizedBusinessId = currentUserBusinessId.trim();
    if (normalizedBusinessId.isNotEmpty) {
      final externalParticipants = participants
          .where(
            (participant) =>
                participant.businessId.trim() != normalizedBusinessId,
          )
          .toList();
      if (externalParticipants.isNotEmpty) {
        return externalParticipants;
      }
    }

    return participants;
  }

  ChatParticipantSummary? _resolveFocusedParticipant(
    List<ChatParticipantSummary> participants, {
    required String? focusUserId,
  }) {
    if (participants.isEmpty) {
      return null;
    }

    final normalizedFocusUserId = (focusUserId ?? "").trim();
    if (normalizedFocusUserId.isEmpty) {
      return participants.first;
    }

    return participants.firstWhere(
      (participant) => participant.userId == normalizedFocusUserId,
      orElse: () => participants.first,
    );
  }

  String _roleLabel(ChatParticipantSummary participant) {
    final normalized = participant.role.trim().replaceAll("_", " ");
    return normalized.isEmpty ? _fallbackRole : normalized;
  }

  String _businessLabel(ChatParticipantSummary participant) {
    if (participant.businessName.trim().isNotEmpty) {
      return participant.businessName;
    }
    if (participant.businessId.trim().isNotEmpty) {
      return participant.businessId;
    }
    return _fallbackBusiness;
  }

  String _estateLabel(ChatParticipantSummary participant) {
    if (participant.estateName.trim().isNotEmpty) {
      return participant.estateName;
    }
    if (participant.estateAssetId.trim().isNotEmpty) {
      return participant.estateAssetId;
    }
    return _fallbackEstate;
  }
}

class _ProfileHero extends StatelessWidget {
  final ChatParticipantSummary participant;

  const _ProfileHero({required this.participant});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayName = participant.name.trim().isEmpty
        ? (participant.email.trim().isEmpty ? _fallbackName : participant.email)
        : participant.name;
    final roleLabel = participant.role.trim().isEmpty
        ? _fallbackRole
        : participant.role.replaceAll("_", " ");
    final businessLabel = participant.businessName.trim().isNotEmpty
        ? participant.businessName
        : _fallbackBusiness;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: scheme.primaryContainer,
            backgroundImage: participant.profileImageUrl.trim().isEmpty
                ? null
                : NetworkImage(participant.profileImageUrl.trim()),
            child: participant.profileImageUrl.trim().isEmpty
                ? Text(
                    displayName.isEmpty ? "?" : displayName[0].toUpperCase(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "$roleLabel • $businessLabel",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ProfileSectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _ProfileDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantListTile extends StatelessWidget {
  final ChatParticipantSummary participant;
  final VoidCallback onTap;

  const _ParticipantListTile({required this.participant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayName = participant.name.trim().isEmpty
        ? (participant.email.trim().isEmpty ? _fallbackName : participant.email)
        : participant.name;
    final roleLabel = participant.role.trim().isEmpty
        ? _fallbackRole
        : participant.role.replaceAll("_", " ");

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: participant.profileImageUrl.trim().isEmpty
                    ? null
                    : NetworkImage(participant.profileImageUrl.trim()),
                child: participant.profileImageUrl.trim().isEmpty
                    ? Text(
                        displayName.isEmpty
                            ? "?"
                            : displayName[0].toUpperCase(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      roleLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
