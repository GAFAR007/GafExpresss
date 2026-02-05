/// lib/app/features/home/presentation/chat_inbox_screen.dart
/// ---------------------------------------------------------
/// WHAT:
/// - Chat inbox screen showing all conversations.
///
/// WHY:
/// - Gives users a single entry point for messaging.
/// - Keeps chat navigation separate from other dashboards.
///
/// HOW:
/// - Loads conversations via chatInboxProvider.
/// - Navigates to thread screen on tap.
/// - Allows business roles to start new chats.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_new_conversation_sheet.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_routes.dart';
import 'package:frontend/app/features/home/presentation/chat_widgets.dart';
import 'package:frontend/app/features/home/presentation/cart_providers.dart';
import 'package:frontend/app/features/home/presentation/home_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

const String _logTag = "CHAT_INBOX";
const String _logBuild = "build()";
const String _logOpenThread = "open_thread";
const String _logNewChat = "new_chat";
const String _logRefresh = "refresh";
const String _logNewChatOpen = "new_chat_open";
const String _logFilterChange = "filter_change";
const String _logSearchChange = "search_change";
const String _logContactTap = "contact_tap";
// WHY: Keep layout spacing consistent and easy to tune.
const double _kInboxPaddingHorizontal = 16;
const double _kInboxPaddingTop = 12;
const double _kInboxPaddingBottom = 24;
const double _kSectionSpacing = 12;
const double _kItemSpacing = 8;
const int _kPinnedCount = 2;

// WHY: Keep inbox labels centralized to avoid inline strings.
class _ChatInboxCopy {
  static const String title = "Chat";
  static const String searchHint = "Search messages or people";
  static const String directLabel = "Direct";
  static const String groupLabel = "Group";
  static const String recentLabel = "Pinned";
  static const String allLabel = "All messages";
  static const String emptyTitle = "No conversations yet";
  static const String emptySubtitle = "Start a chat to see it here.";
}

// WHY: Constrain filter choices to the two inbox tabs.
enum _ChatInboxFilter { direct, group }

class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  // WHY: Persist search input across rebuilds.
  final TextEditingController _searchController = TextEditingController();
  _ChatInboxFilter _filter = _ChatInboxFilter.direct;

  void _log(String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(_logTag, message, extra: extra);
  }

  @override
  void dispose() {
    // WHY: Prevent controller leaks when leaving the inbox screen.
    _searchController.dispose();
    super.dispose();
  }

  void _openNewChat(BuildContext context) {
    _log(_logNewChatOpen);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChatNewConversationSheet(
        onCreated: (conversation) {
          _log(_logNewChat, extra: {"id": conversation.id});
          ref.invalidate(chatInboxProvider);
          context.pop();
          context.go(
            "${chatThreadRouteBase}/${conversation.id}",
            extra: conversation,
          );
        },
      ),
    );
  }

  void _handleOpenThread(ChatConversation conversation) {
    _log(_logOpenThread, extra: {"id": conversation.id});
    // WHY: Pass conversation data to avoid refetching on open.
    context.go(
      "${chatThreadRouteBase}/${conversation.id}",
      extra: conversation,
    );
  }

  @override
  Widget build(BuildContext context) {
    _log(_logBuild);
    // WHY: Role controls whether we show the new chat action.
    final session = ref.watch(authSessionProvider);
    final role = session?.user.role ?? "";
    final isBusiness = role == "business_owner" || role == "staff";
    final canCreate = isBusiness;
    final isTenant = role == "tenant";
    final cartState = ref.watch(cartProvider);
    final cartBadgeCount =
        cartState.hasUnseenChanges ? cartState.totalItems : 0;

    final conversationsAsync = ref.watch(chatInboxProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_ChatInboxCopy.title),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => _openNewChat(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: isBusiness
          ? BusinessBottomNav(
              currentIndex: 4,
              onTap: (index) {
                _log("business_nav", extra: {"index": index});
                switch (index) {
                  case 0:
                    context.go('/home');
                    return;
                  case 1:
                    context.go('/business-products');
                    return;
                  case 2:
                    context.go('/business-dashboard');
                    return;
                  case 3:
                    context.go('/business-orders');
                    return;
                  case 4:
                    context.go('/chat');
                    return;
                  case 5:
                    context.go('/settings');
                    return;
                }
              },
            )
          : HomeBottomNav(
              currentIndex: 3,
              cartBadgeCount: cartBadgeCount,
              showTenantTab: isTenant,
              onTap: (index) {
                _log("home_nav", extra: {"index": index});
                if (index == 0) {
                  context.go('/home');
                  return;
                }
                if (index == 1) {
                  context.go('/cart');
                  return;
                }
                if (index == 2) {
                  context.go('/orders');
                  return;
                }
                if (index == 3) {
                  context.go('/chat');
                  return;
                }
                if (isTenant && index == 4) {
                  context.go('/tenant-verification');
                  return;
                }
                if (index == (isTenant ? 5 : 4)) {
                  context.go('/settings');
                }
              },
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          _log(_logRefresh);
          // WHY: Refresh ensures the inbox stays in sync with server changes.
          ref.invalidate(chatInboxProvider);
        },
        child: conversationsAsync.when(
          data: (items) => _ChatInboxContent(
            conversations: items,
            filter: _filter,
            searchController: _searchController,
            onFilterChange: (value) {
              _log(_logFilterChange, extra: {"filter": value.name});
              setState(() => _filter = value);
            },
            onSearchChanged: (value) {
              _log(_logSearchChange, extra: {"length": value.trim().length});
              setState(() {});
            },
            onConversationTap: _handleOpenThread,
            onContactTap: (conversation) {
              _log(_logContactTap, extra: {"id": conversation.id});
              _handleOpenThread(conversation);
            },
          ),
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, _) => const Center(
            child: Text("Unable to load conversations"),
          ),
        ),
      ),
    );
  }
}

class _ChatInboxContent extends StatelessWidget {
  final List<ChatConversation> conversations;
  final _ChatInboxFilter filter;
  final TextEditingController searchController;
  final ValueChanged<_ChatInboxFilter> onFilterChange;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ChatConversation> onConversationTap;
  final ValueChanged<ChatConversation> onContactTap;

  const _ChatInboxContent({
    required this.conversations,
    required this.filter,
    required this.searchController,
    required this.onFilterChange,
    required this.onSearchChanged,
    required this.onConversationTap,
    required this.onContactTap,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Split the inbox into direct/group counts for quick scanning.
    final directChats = _filterByType(conversations, _ChatInboxFilter.direct);
    final groupChats = _filterByType(conversations, _ChatInboxFilter.group);
    final visibleChats = _applySearch(
      _filterByType(conversations, filter),
      searchController.text,
    );
    final pinnedChats = _extractPinned(visibleChats);
    final remainingChats = visibleChats.skip(pinnedChats.length).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        _kInboxPaddingHorizontal,
        _kInboxPaddingTop,
        _kInboxPaddingHorizontal,
        _kInboxPaddingBottom,
      ),
      children: [
        ChatInboxHeroCard(
          totalCount: conversations.length,
          directCount: directChats.length,
          groupCount: groupChats.length,
        ),
        const SizedBox(height: _kSectionSpacing),
        ChatInboxContactStrip(
          conversations: directChats,
          onTap: onContactTap,
        ),
        const SizedBox(height: _kSectionSpacing),
        ChatInboxSearchField(
          controller: searchController,
          hintText: _ChatInboxCopy.searchHint,
          onChanged: onSearchChanged,
          onClear: () {
            searchController.clear();
            onSearchChanged('');
          },
        ),
        const SizedBox(height: _kSectionSpacing),
        ChatInboxFilterRow(
          directCount: directChats.length,
          groupCount: groupChats.length,
          isDirectSelected: filter == _ChatInboxFilter.direct,
          onSelectDirect: () => onFilterChange(_ChatInboxFilter.direct),
          onSelectGroup: () => onFilterChange(_ChatInboxFilter.group),
        ),
        const SizedBox(height: _kSectionSpacing),
        if (visibleChats.isEmpty)
          const ChatInboxEmptyState(
            title: _ChatInboxCopy.emptyTitle,
            subtitle: _ChatInboxCopy.emptySubtitle,
          ),
        if (pinnedChats.isNotEmpty) ...[
          const ChatInboxSectionHeader(label: _ChatInboxCopy.recentLabel),
          const SizedBox(height: _kItemSpacing),
          ...pinnedChats.map(
            (conversation) => Padding(
              padding: const EdgeInsets.only(bottom: _kItemSpacing),
              child: ChatConversationTile(
                conversation: conversation,
                onTap: () => onConversationTap(conversation),
              ),
            ),
          ),
        ],
        if (remainingChats.isNotEmpty) ...[
          const ChatInboxSectionHeader(label: _ChatInboxCopy.allLabel),
          const SizedBox(height: _kItemSpacing),
          ...remainingChats.map(
            (conversation) => Padding(
              padding: const EdgeInsets.only(bottom: _kItemSpacing),
              child: ChatConversationTile(
                conversation: conversation,
                onTap: () => onConversationTap(conversation),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<ChatConversation> _filterByType(
    List<ChatConversation> items,
    _ChatInboxFilter filter,
  ) {
    final match = filter == _ChatInboxFilter.direct ? "direct" : "group";
    // WHY: Normalize to lowercase to prevent casing mismatches.
    return items.where((conversation) {
      final type = conversation.type.trim().toLowerCase();
      if (type.isEmpty && match == "direct") {
        return true;
      }
      return type == match;
    }).toList();
  }

  List<ChatConversation> _applySearch(
    List<ChatConversation> items,
    String query,
  ) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return items;
    // WHY: Match on title and preview so users can find chats by context.
    return items.where((conversation) {
      final title = conversation.title.toLowerCase();
      final preview = conversation.lastMessagePreview.toLowerCase();
      return title.contains(trimmed) || preview.contains(trimmed);
    }).toList();
  }

  List<ChatConversation> _extractPinned(List<ChatConversation> items) {
    if (items.isEmpty) return [];
    final sorted = [...items];
    // WHY: Surface the most recent chats in the pinned section.
    sorted.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt ?? DateTime(1970);
      final bTime = b.lastMessageAt ?? b.createdAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return sorted.take(_kPinnedCount).toList();
  }
}
