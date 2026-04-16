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
/// - Derives a request queue from request-backed conversations.
/// - Preserves navigation, search, and socket invalidation.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/cart_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_new_conversation_sheet.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_routes.dart';
import 'package:frontend/app/features/home/presentation/home_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_models.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme_mode.dart';

const String _logTag = "CHAT_INBOX";
const String _logBuild = "build()";
const String _logOpenThread = "open_thread";
const String _logNewChat = "new_chat";
const String _logRefresh = "refresh";
const String _logNewChatOpen = "new_chat_open";
const String _logFilterChange = "filter_change";
const String _logSearchChange = "search_change";
const String _logPresenceChange = "presence_change";

const double _kInboxMaxWidth = 760;
const double _kAvatarSize = 44;
const Color _kInboxHeroTop = Color(0xFF082A55);
const Color _kInboxHeroGlass = Color(0xFFFDFEFF);

class _ChatInboxCopy {
  static const String title = "Chats";
  static const String searchHint = "Search messages or people";
  static const String directLabel = "Direct";
  static const String groupLabel = "Group";
  static const String queueLabel = "Queue";
  static const String queueLoading = "Loading request queue";
  static const String queueError = "Unable to load request queue";
  static const String directEmptyTitle = "No direct conversations";
  static const String directEmptySubtitle =
      "Start a conversation and it will appear here.";
  static const String groupEmptyTitle = "No group conversations";
  static const String groupEmptySubtitle =
      "Group threads will appear here when they are available.";
  static const String queueEmptyTitle = "No active requests";
  static const String queueEmptySubtitle =
      "Purchase requests linked to chat will appear here.";
}

enum _ChatInboxFilter { direct, group, queue }

class _QueueConversationEntry {
  final ChatConversation conversation;
  final ChatConversationDetail detail;

  const _QueueConversationEntry({
    required this.conversation,
    required this.detail,
  });

  PurchaseRequest get request => detail.purchaseRequest!;

  DateTime get sortTime =>
      request.updatedAt ??
      request.createdAt ??
      conversation.lastMessageAt ??
      conversation.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

final _chatQueueProvider = FutureProvider<List<_QueueConversationEntry>>((
  ref,
) async {
  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(chatApiProvider);
  final conversations = await ref.watch(chatInboxProvider.future);
  final details = await Future.wait(
    conversations.map((conversation) async {
      try {
        final detail = await api.fetchConversationDetail(
          token: session.token,
          conversationId: conversation.id,
        );
        if (detail.purchaseRequest == null) {
          return null;
        }
        return _QueueConversationEntry(
          conversation: conversation,
          detail: detail,
        );
      } catch (error) {
        AppDebug.log(
          _logTag,
          "queue_detail_load_failed",
          extra: {"conversationId": conversation.id, "error": error.toString()},
        );
        return null;
      }
    }),
  );

  final queueEntries = details.whereType<_QueueConversationEntry>().toList()
    ..sort((left, right) => right.sortTime.compareTo(left.sortTime));
  return queueEntries;
});

class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _joinedConversationIds = <String>{};
  StreamSubscription? _messageSub;
  StreamSubscription? _readSub;

  _ChatInboxFilter _filter = _ChatInboxFilter.direct;
  bool _isOnline = true;

  void _log(String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(_logTag, message, extra: extra);
  }

  @override
  void initState() {
    super.initState();
    _bindRealtime();
  }

  void _bindRealtime() {
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      return;
    }

    final socket = ref.read(chatSocketProvider);
    socket.connect(token: session.token);

    _messageSub ??= socket.messageStream.listen((_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(chatInboxProvider);
    });

    _readSub ??= socket.readStream.listen((_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(chatInboxProvider);
    });
  }

  void _syncConversationRooms(List<ChatConversation> conversations) {
    final socket = ref.read(chatSocketProvider);
    final nextIds = conversations
        .map((conversation) => conversation.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final conversationId in nextIds.difference(_joinedConversationIds)) {
      socket.joinConversation(conversationId);
    }

    for (final conversationId in _joinedConversationIds.difference(nextIds)) {
      socket.leaveConversation(conversationId);
    }

    _joinedConversationIds
      ..clear()
      ..addAll(nextIds);
  }

  @override
  void dispose() {
    final socket = ref.read(chatSocketProvider);
    for (final conversationId in _joinedConversationIds) {
      socket.leaveConversation(conversationId);
    }
    _messageSub?.cancel();
    _readSub?.cancel();
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
            "$chatThreadRouteBase/${conversation.id}",
            extra: conversation,
          );
        },
      ),
    );
  }

  void _handleOpenThread(ChatConversation conversation) {
    _log(_logOpenThread, extra: {"id": conversation.id});
    context.go("$chatThreadRouteBase/${conversation.id}", extra: conversation);
  }

  Future<void> _handleRefresh() async {
    _log(_logRefresh);
    ref.invalidate(chatInboxProvider);
    ref.invalidate(_chatQueueProvider);
  }

  @override
  Widget build(BuildContext context) {
    _log(_logBuild);

    final session = ref.watch(authSessionProvider);
    final role = session?.user.role ?? "";
    final isBusiness = role == "business_owner" || role == "staff";
    final canCreate = isBusiness;
    final isTenant = role == "tenant";
    final cartState = ref.watch(cartProvider);
    final cartBadgeCount = cartState.hasUnseenChanges
        ? cartState.totalItems
        : 0;

    final conversationsAsync = ref.watch(chatInboxProvider);
    final queueAsync = _filter == _ChatInboxFilter.queue
        ? ref.watch(_chatQueueProvider)
        : null;

    final scheme = Theme.of(context).colorScheme;
    final isDark = _isDarkScheme(scheme);
    return Scaffold(
      backgroundColor: isDark
          ? scheme.surfaceContainerLowest
          : _kInboxHeroGlass,
      floatingActionButton: canCreate
          ? _InboxFab(
              onPressed: () => _openNewChat(context),
              icon: Icons.chat_bubble_rounded,
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
      body: Stack(
        children: [
          const Positioned.fill(child: _InboxBackdrop()),
          Positioned.fill(
            child: conversationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  const Center(child: Text("Unable to load conversations")),
              data: (conversations) {
                _syncConversationRooms(conversations);
                return RefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: _ChatInboxContent(
                    conversations: conversations,
                    queueAsync: queueAsync,
                    filter: _filter,
                    isOnline: _isOnline,
                    searchController: _searchController,
                    onOpenProfile: () => context.go('/settings'),
                    onPresenceChanged: (value) {
                      _log(_logPresenceChange, extra: {"online": value});
                      setState(() => _isOnline = value);
                    },
                    onFilterChange: (value) {
                      _log(_logFilterChange, extra: {"filter": value.name});
                      setState(() => _filter = value);
                    },
                    onSearchChanged: (value) {
                      _log(
                        _logSearchChange,
                        extra: {"length": value.trim().length},
                      );
                      setState(() {});
                    },
                    onConversationTap: _handleOpenThread,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInboxContent extends StatelessWidget {
  final List<ChatConversation> conversations;
  final AsyncValue<List<_QueueConversationEntry>>? queueAsync;
  final _ChatInboxFilter filter;
  final bool isOnline;
  final TextEditingController searchController;
  final VoidCallback onOpenProfile;
  final ValueChanged<bool> onPresenceChanged;
  final ValueChanged<_ChatInboxFilter> onFilterChange;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ChatConversation> onConversationTap;

  const _ChatInboxContent({
    required this.conversations,
    required this.queueAsync,
    required this.filter,
    required this.isOnline,
    required this.searchController,
    required this.onOpenProfile,
    required this.onPresenceChanged,
    required this.onFilterChange,
    required this.onSearchChanged,
    required this.onConversationTap,
  });

  @override
  Widget build(BuildContext context) {
    final directChats = _applyConversationSearch(
      _sortConversations(_filterByType(conversations, _ChatInboxFilter.direct)),
      searchController.text,
    );
    final groupChats = _applyConversationSearch(
      _sortConversations(_filterByType(conversations, _ChatInboxFilter.group)),
      searchController.text,
    );
    final sectionTitle = _sectionTitle(filter);
    final sectionCountLabel = _sectionCountLabel(
      filter: filter,
      directChats: directChats,
      groupChats: groupChats,
      queueAsync: queueAsync,
      query: searchController.text,
    );

    return SafeArea(
      top: false,
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kInboxMaxWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(bottom: AppSpacing.xxxl + 4),
                children: [
                  _InboxHeroSection(
                    filter: filter,
                    isOnline: isOnline,
                    isWide: isWide,
                    controller: searchController,
                    onOpenProfile: onOpenProfile,
                    onPresenceChanged: onPresenceChanged,
                    onFilterChange: onFilterChange,
                    onSearchChanged: onSearchChanged,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      0,
                    ),
                    child: _InboxSectionHeader(
                      title: sectionTitle,
                      countLabel: sectionCountLabel,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs + 2,
                      AppSpacing.lg,
                      0,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: switch (filter) {
                        _ChatInboxFilter.direct => _ConversationSection(
                          key: const ValueKey("direct"),
                          conversations: directChats,
                          emptyTitle: _ChatInboxCopy.directEmptyTitle,
                          emptySubtitle: _ChatInboxCopy.directEmptySubtitle,
                          onTap: onConversationTap,
                        ),
                        _ChatInboxFilter.group => _ConversationSection(
                          key: const ValueKey("group"),
                          conversations: groupChats,
                          emptyTitle: _ChatInboxCopy.groupEmptyTitle,
                          emptySubtitle: _ChatInboxCopy.groupEmptySubtitle,
                          onTap: onConversationTap,
                        ),
                        _ChatInboxFilter.queue => _QueueSection(
                          key: const ValueKey("queue"),
                          queueAsync: queueAsync,
                          query: searchController.text,
                          onTap: onConversationTap,
                        ),
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<ChatConversation> _filterByType(
    List<ChatConversation> items,
    _ChatInboxFilter nextFilter,
  ) {
    final isGroupTab = nextFilter == _ChatInboxFilter.group;
    return items.where((conversation) {
      final type = conversation.type.trim().toLowerCase();
      if (isGroupTab) {
        return type == "group";
      }
      return type != "group";
    }).toList();
  }

  String _sectionTitle(_ChatInboxFilter currentFilter) {
    return switch (currentFilter) {
      _ChatInboxFilter.direct => "Direct chats",
      _ChatInboxFilter.group => "Group chats",
      _ChatInboxFilter.queue => "Request queue",
    };
  }

  String _sectionCountLabel({
    required _ChatInboxFilter filter,
    required List<ChatConversation> directChats,
    required List<ChatConversation> groupChats,
    required AsyncValue<List<_QueueConversationEntry>>? queueAsync,
    required String query,
  }) {
    if (filter == _ChatInboxFilter.queue) {
      return queueAsync?.when(
            data: (entries) {
              final count = _applyQueueSearch(entries, query).length;
              return count == 1 ? "1 request" : "$count requests";
            },
            loading: () => "Syncing",
            error: (error, _) => "Unavailable",
          ) ??
          "0 requests";
    }

    final count = switch (filter) {
      _ChatInboxFilter.direct => directChats.length,
      _ChatInboxFilter.group => groupChats.length,
      _ChatInboxFilter.queue => 0,
    };
    final label = count == 1 ? "chat" : "chats";
    return "$count $label";
  }
}

class _InboxSectionHeader extends StatelessWidget {
  final String title;
  final String countLabel;

  const _InboxSectionHeader({required this.title, required this.countLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = _isDarkScheme(scheme);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.xs + 1,
          ),
          decoration: BoxDecoration(
            color: _blendTone(
              scheme.primary,
              scheme.surface,
              alpha: isDark ? 0.18 : 0.08,
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14),
            ),
          ),
          child: Text(
            countLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _InboxBackdrop extends StatelessWidget {
  const _InboxBackdrop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = _isDarkScheme(scheme);

    if (!isDark) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: _kInboxHeroGlass),
        child: SizedBox.expand(),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _blendTone(
              scheme.primary,
              scheme.surfaceContainerLowest,
              alpha: isDark ? 0.09 : 0.03,
            ),
            _blendTone(
              scheme.secondary,
              scheme.surfaceContainerLow,
              alpha: isDark ? 0.05 : 0.018,
            ),
            scheme.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -112,
            right: -84,
            child: _BackdropBloom(
              size: 280,
              color: _blendTone(
                scheme.primary,
                scheme.surfaceContainerHighest,
                alpha: isDark ? 0.36 : 0.22,
              ),
            ),
          ),
          Positioned(
            top: 76,
            left: -124,
            child: _BackdropBloom(
              size: 248,
              color: _blendTone(
                scheme.tertiary,
                scheme.surfaceContainer,
                alpha: isDark ? 0.22 : 0.1,
              ),
            ),
          ),
          Positioned(
            bottom: 168,
            right: -102,
            child: _BackdropBloom(
              size: 228,
              color: _blendTone(
                scheme.secondary,
                scheme.surfaceContainer,
                alpha: isDark ? 0.18 : 0.08,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropBloom extends StatelessWidget {
  final double size;
  final Color color;

  const _BackdropBloom({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.92),
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0.02),
                Colors.transparent,
              ],
              stops: const [0, 0.42, 0.72, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class _InboxHeroSection extends StatelessWidget {
  final _ChatInboxFilter filter;
  final bool isOnline;
  final bool isWide;
  final TextEditingController controller;
  final VoidCallback onOpenProfile;
  final ValueChanged<bool> onPresenceChanged;
  final ValueChanged<_ChatInboxFilter> onFilterChange;
  final ValueChanged<String> onSearchChanged;

  const _InboxHeroSection({
    required this.filter,
    required this.isOnline,
    required this.isWide,
    required this.controller,
    required this.onOpenProfile,
    required this.onPresenceChanged,
    required this.onFilterChange,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    final horizontalPadding = isWide ? AppSpacing.lg : AppSpacing.md;
    final topPadding = topInset + (isWide ? AppSpacing.lg : AppSpacing.md);
    final bottomPadding = isWide ? AppSpacing.lg : AppSpacing.md + 2;
    const radius = BorderRadius.only(
      bottomLeft: Radius.circular(30),
      bottomRight: Radius.circular(30),
    );

    return Container(
      decoration: BoxDecoration(
        color: _kInboxHeroTop,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InboxHeader(
                isOnline: isOnline,
                isWide: isWide,
                onOpenProfile: onOpenProfile,
                onPresenceChanged: onPresenceChanged,
              ),
              SizedBox(height: isWide ? AppSpacing.md + 2 : AppSpacing.sm),
              _InboxTopControls(
                controller: controller,
                filter: filter,
                onSearchChanged: onSearchChanged,
                onFilterChange: onFilterChange,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxHeader extends ConsumerWidget {
  final bool isOnline;
  final bool isWide;
  final VoidCallback onOpenProfile;
  final ValueChanged<bool> onPresenceChanged;

  const _InboxHeader({
    required this.isOnline,
    required this.isWide,
    required this.onOpenProfile,
    required this.onPresenceChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(appThemeModeProvider);
    final isNightMode = mode == AppThemeMode.dark;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _ChatInboxCopy.title,
          style:
              (isWide
                      ? theme.textTheme.displaySmall
                      : theme.textTheme.headlineMedium)
                  ?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: isWide ? -1.2 : -0.9,
                    height: 0.94,
                  ),
        ),
        const SizedBox(height: AppSpacing.xxs + 1),
        Text(
          "Your active conversations and request queue in one place.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.84),
            fontWeight: FontWeight.w500,
            height: 1.18,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            SizedBox(width: isWide ? AppSpacing.lg : AppSpacing.sm),
            _ProfileActionButton(onPressed: onOpenProfile),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _HeaderPresenceIconToggle(
              isOnline: isOnline,
              onChanged: onPresenceChanged,
            ),
            _HeaderThemeIconToggle(
              isNight: isNightMode,
              onChanged: (nextIsNight) {
                final nextMode = nextIsNight
                    ? AppThemeMode.dark
                    : AppThemeMode.classic;
                AppDebug.log(
                  _logTag,
                  "theme_toggle",
                  extra: {"mode": nextMode.name},
                );
                ref
                    .read(appThemeModeProvider.notifier)
                    .setMode(nextMode, source: "chat_inbox_theme_toggle");
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderPresenceIconToggle extends StatelessWidget {
  final bool isOnline;
  final ValueChanged<bool> onChanged;

  const _HeaderPresenceIconToggle({
    required this.isOnline,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _HeaderIconToggle(
      isRightSelected: !isOnline,
      leftSemanticLabel: "Online",
      rightSemanticLabel: "Offline",
      leftIcon: Icons.circle_rounded,
      rightIcon: Icons.circle_rounded,
      leftIconSize: 15,
      rightIconSize: 15,
      leftActiveColor: Colors.white,
      leftInactiveColor: Colors.white.withValues(alpha: 0.42),
      rightActiveColor: Colors.white,
      rightInactiveColor: Colors.white.withValues(alpha: 0.42),
      leftTrackColors: const [Color(0xFFFFFFFF), Color(0xFFEAF0F8)],
      rightTrackColors: const [Color(0xFFFFFFFF), Color(0xFFEAF0F8)],
      leftBorderColor: Colors.white,
      rightBorderColor: Colors.white,
      onRightSelectedChanged: (isOffline) => onChanged(!isOffline),
    );
  }
}

class _HeaderThemeIconToggle extends StatelessWidget {
  final bool isNight;
  final ValueChanged<bool> onChanged;

  const _HeaderThemeIconToggle({
    required this.isNight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _HeaderIconToggle(
      isRightSelected: isNight,
      leftSemanticLabel: "Day mode",
      rightSemanticLabel: "Night mode",
      leftIcon: Icons.wb_sunny_outlined,
      rightIcon: Icons.dark_mode_outlined,
      leftIconSize: 22,
      rightIconSize: 22,
      leftActiveColor: Colors.white,
      leftInactiveColor: Colors.white.withValues(alpha: 0.42),
      rightActiveColor: Colors.white,
      rightInactiveColor: Colors.white.withValues(alpha: 0.42),
      leftTrackColors: const [Color(0xFFFFFFFF), Color(0xFFEAF0F8)],
      rightTrackColors: const [Color(0xFFFFFFFF), Color(0xFFEAF0F8)],
      leftBorderColor: Colors.white,
      rightBorderColor: Colors.white,
      onRightSelectedChanged: onChanged,
    );
  }
}

class _HeaderIconToggle extends StatelessWidget {
  final bool isRightSelected;
  final String leftSemanticLabel;
  final String rightSemanticLabel;
  final IconData leftIcon;
  final IconData rightIcon;
  final double leftIconSize;
  final double rightIconSize;
  final Color leftActiveColor;
  final Color leftInactiveColor;
  final Color rightActiveColor;
  final Color rightInactiveColor;
  final List<Color> leftTrackColors;
  final List<Color> rightTrackColors;
  final Color leftBorderColor;
  final Color rightBorderColor;
  final ValueChanged<bool> onRightSelectedChanged;

  const _HeaderIconToggle({
    required this.isRightSelected,
    required this.leftSemanticLabel,
    required this.rightSemanticLabel,
    required this.leftIcon,
    required this.rightIcon,
    required this.leftIconSize,
    required this.rightIconSize,
    required this.leftActiveColor,
    required this.leftInactiveColor,
    required this.rightActiveColor,
    required this.rightInactiveColor,
    required this.leftTrackColors,
    required this.rightTrackColors,
    required this.leftBorderColor,
    required this.rightBorderColor,
    required this.onRightSelectedChanged,
  });

  @override
  Widget build(BuildContext context) {
    const trackWidth = 66.0;
    const trackHeight = 32.0;
    const knobSize = 30.0;
    const knobInset = 1.0;
    final knobLeft = isRightSelected
        ? trackWidth - knobSize - knobInset
        : knobInset;
    final leftColor = isRightSelected ? leftInactiveColor : leftActiveColor;
    final rightColor = isRightSelected ? rightActiveColor : rightInactiveColor;
    final activeTrackColors = isRightSelected
        ? rightTrackColors
        : leftTrackColors;
    final activeBorderColor = isRightSelected
        ? rightBorderColor
        : leftBorderColor;

    return Semantics(
      button: true,
      toggled: isRightSelected,
      label: isRightSelected ? rightSemanticLabel : leftSemanticLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: () => onRightSelectedChanged(!isRightSelected),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.09);
            }
            return null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(leftIcon, size: leftIconSize, color: leftColor),
                const SizedBox(width: 8),
                SizedBox(
                  width: trackWidth,
                  height: trackHeight,
                  child: Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: trackWidth,
                        height: trackHeight,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: activeTrackColors,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: activeBorderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isRightSelected ? 0.22 : 0.18,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.48),
                              blurRadius: 3,
                              offset: const Offset(-1, -1),
                            ),
                          ],
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 230),
                        curve: Curves.easeOutCubic,
                        left: knobLeft,
                        top: knobInset,
                        width: knobSize,
                        height: knobSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kInboxHeroTop,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 9,
                                offset: const Offset(0, 3),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.72),
                                blurRadius: 2,
                                offset: const Offset(-1, -1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(rightIcon, size: rightIconSize, color: rightColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ProfileActionButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        overlayColor: WidgetStateProperty.all(
          _kInboxHeroTop.withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: _kInboxHeroTop,
          ),
        ),
      ),
    );
  }
}

class _InboxTopControls extends StatelessWidget {
  final TextEditingController controller;
  final _ChatInboxFilter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ChatInboxFilter> onFilterChange;

  const _InboxTopControls({
    required this.controller,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InboxSearchBar(
          controller: controller,
          onChanged: onSearchChanged,
          onClear: () {
            controller.clear();
            onSearchChanged('');
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        _InboxTabBar(filter: filter, onChanged: onFilterChange),
      ],
    );
  }
}

class _InboxSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _InboxSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const searchFill = Color(0xFF38506F);
    final searchBorder = Colors.white.withValues(alpha: 0.08);
    const searchTextColor = Colors.white;
    final searchHintColor = Colors.white.withValues(alpha: 0.58);
    final searchIconColor = Colors.white.withValues(alpha: 0.72);

    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        cursorColor: Colors.white,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: searchTextColor,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: searchFill,
          hintText: _ChatInboxCopy.searchHint,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: searchHintColor,
            fontWeight: FontWeight.w500,
            height: 1.1,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: searchIconColor,
            size: 17,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 36,
          ),
          suffixIcon: controller.text.trim().isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  iconSize: 17,
                  splashRadius: 17,
                  visualDensity: VisualDensity.compact,
                  color: searchIconColor,
                  icon: const Icon(Icons.close_rounded),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: searchBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 10,
          ),
          isDense: true,
        ),
      ),
    );
  }
}

class _InboxTabBar extends StatelessWidget {
  final _ChatInboxFilter filter;
  final ValueChanged<_ChatInboxFilter> onChanged;

  const _InboxTabBar({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final activeIndex = switch (filter) {
      _ChatInboxFilter.direct => 0,
      _ChatInboxFilter.group => 1,
      _ChatInboxFilter.queue => 2,
    };

    return SizedBox(
      height: 38,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / 3;

          return Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: _InboxTabButton(
                        label: _ChatInboxCopy.directLabel,
                        selected: filter == _ChatInboxFilter.direct,
                        onTap: () => onChanged(_ChatInboxFilter.direct),
                      ),
                    ),
                    Expanded(
                      child: _InboxTabButton(
                        label: _ChatInboxCopy.groupLabel,
                        selected: filter == _ChatInboxFilter.group,
                        onTap: () => onChanged(_ChatInboxFilter.group),
                      ),
                    ),
                    Expanded(
                      child: _InboxTabButton(
                        label: _ChatInboxCopy.queueLabel,
                        selected: filter == _ChatInboxFilter.queue,
                        onTap: () => onChanged(_ChatInboxFilter.queue),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: tabWidth * activeIndex,
                bottom: 0,
                width: tabWidth,
                height: 2,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InboxTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _InboxTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        overlayColor: _interactiveOverlay(scheme),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style:
                theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.58),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.1,
                ) ??
                TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.58),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _ConversationSection extends StatelessWidget {
  final List<ChatConversation> conversations;
  final String emptyTitle;
  final String emptySubtitle;
  final ValueChanged<ChatConversation> onTap;

  const _ConversationSection({
    super.key,
    required this.conversations,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) {
      return _InboxEmptyState(title: emptyTitle, subtitle: emptySubtitle);
    }

    return _InboxListSurface(
      children: [
        for (var index = 0; index < conversations.length; index++) ...[
          _ConversationRow(
            conversation: conversations[index],
            onTap: () => onTap(conversations[index]),
          ),
          if (index + 1 < conversations.length) const _InboxDivider(),
        ],
      ],
    );
  }
}

class _QueueSection extends StatelessWidget {
  final AsyncValue<List<_QueueConversationEntry>>? queueAsync;
  final String query;
  final ValueChanged<ChatConversation> onTap;

  const _QueueSection({
    super.key,
    required this.queueAsync,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final async = queueAsync;
    if (async == null) {
      return const SizedBox.shrink();
    }

    return async.when(
      loading: () =>
          const _InboxLoadingState(label: _ChatInboxCopy.queueLoading),
      error: (error, _) => const _InboxEmptyState(
        title: _ChatInboxCopy.queueError,
        subtitle: "Try refreshing the inbox.",
      ),
      data: (entries) {
        final visible = _applyQueueSearch(entries, query);
        if (visible.isEmpty) {
          return const _InboxEmptyState(
            title: _ChatInboxCopy.queueEmptyTitle,
            subtitle: _ChatInboxCopy.queueEmptySubtitle,
          );
        }

        return _InboxListSurface(
          children: [
            for (var index = 0; index < visible.length; index++) ...[
              _QueueRow(
                entry: visible[index],
                onTap: () => onTap(visible[index].conversation),
              ),
              if (index + 1 < visible.length) const _InboxDivider(),
            ],
          ],
        );
      },
    );
  }
}

class _InboxListSurface extends StatelessWidget {
  final List<Widget> children;

  const _InboxListSurface({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = _isDarkScheme(scheme);
    final radius = BorderRadius.circular(28);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? _blendTone(scheme.primary, scheme.surface, alpha: 0.055)
            : Colors.white,
        borderRadius: radius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.38),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.16 : 0.06),
            blurRadius: isDark ? 20 : 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(children: children),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;

  const _ConversationRow({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = _isDarkScheme(scheme);
    final hasUnread = conversation.unreadCount > 0;
    final title = _conversationTitle(conversation);
    final subtitle = conversation.lastMessagePreview.trim().isNotEmpty
        ? conversation.lastMessagePreview.trim()
        : "No messages yet";
    final timeLabel = _formatInboxTime(
      conversation.lastMessageAt ?? conversation.createdAt,
    );
    final accent = _accentForConversation(conversation, scheme);
    final avatarUrl = conversation.displayAvatar.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        overlayColor: _interactiveOverlay(scheme),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: hasUnread
                ? _blendTone(
                    scheme.primary,
                    scheme.surface,
                    alpha: isDark ? 0.14 : 0.045,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasUnread
                  ? scheme.primary.withValues(alpha: isDark ? 0.18 : 0.08)
                  : Colors.transparent,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md + 2,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConversationAvatar(
                  title: title,
                  avatarUrl: avatarUrl,
                  accent: accent,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: hasUnread
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: scheme.onSurface,
                            letterSpacing: -0.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xxs + 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: hasUnread ? 0.9 : 0.76,
                            ),
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 13.2,
                            height: 1.16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs + 2,
                        ),
                        decoration: BoxDecoration(
                          color: _blendTone(
                            scheme.primary,
                            scheme.surface,
                            alpha: hasUnread
                                ? (isDark ? 0.18 : 0.09)
                                : (isDark ? 0.12 : 0.04),
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: scheme.primary.withValues(
                              alpha: hasUnread ? 0.16 : 0.08,
                            ),
                          ),
                        ),
                        child: Text(
                          timeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hasUnread
                                ? scheme.primary
                                : scheme.onSurfaceVariant.withValues(
                                    alpha: 0.68,
                                  ),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.02,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(height: AppSpacing.xs + 1),
                        _UnreadCountBadge(count: conversation.unreadCount),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadCountBadge extends StatelessWidget {
  final int count;

  const _UnreadCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = count > 99 ? "99+" : "$count";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final _QueueConversationEntry entry;
  final VoidCallback onTap;

  const _QueueRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = _isDarkScheme(scheme);
    final hasUnread = entry.conversation.unreadCount > 0;
    final request = entry.request;
    final title = _queueTitle(entry);
    final subtitle = _queueSubtitle(request);
    final accent = _queueStatusColor(request.progressStage, scheme);
    final statusLabel = _queueStatusLabel(request.progressStage);
    final timeLabel = _formatInboxTime(entry.sortTime);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        overlayColor: _interactiveOverlay(scheme),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: hasUnread
                ? _blendTone(
                    scheme.primary,
                    scheme.surface,
                    alpha: isDark ? 0.14 : 0.045,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasUnread
                  ? scheme.primary.withValues(alpha: isDark ? 0.18 : 0.08)
                  : Colors.transparent,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md + 2,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConversationAvatar(
                  title: title,
                  avatarUrl: entry.conversation.displayAvatar.trim(),
                  accent: accent,
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: hasUnread
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: scheme.onSurface,
                            letterSpacing: -0.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xxs + 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: hasUnread ? 0.9 : 0.76,
                            ),
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 13,
                            height: 1.16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: _blendTone(
                          scheme.primary,
                          scheme.surface,
                          alpha: hasUnread
                              ? (isDark ? 0.18 : 0.09)
                              : (isDark ? 0.12 : 0.04),
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: scheme.primary.withValues(
                            alpha: hasUnread ? 0.16 : 0.08,
                          ),
                        ),
                      ),
                      child: Text(
                        timeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hasUnread
                              ? scheme.primary
                              : scheme.onSurfaceVariant.withValues(alpha: 0.68),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.02,
                        ),
                      ),
                    ),
                    if (hasUnread) ...[
                      const SizedBox(height: AppSpacing.xs + 1),
                      _UnreadCountBadge(count: entry.conversation.unreadCount),
                    ],
                    const SizedBox(height: AppSpacing.xs + 1),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          accent.withValues(alpha: isDark ? 0.16 : 0.1),
                          scheme.surface,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.08,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  final String title;
  final String avatarUrl;
  final Color accent;
  final IconData? icon;

  const _ConversationAvatar({
    required this.title,
    required this.avatarUrl,
    required this.accent,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAvatar = avatarUrl.isNotEmpty;
    final scheme = theme.colorScheme;
    final isDark = _isDarkScheme(scheme);
    return Container(
      width: _kAvatarSize,
      height: _kAvatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasAvatar
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(accent, scheme.surface, 0.08) ?? accent,
                  Color.lerp(accent, scheme.primary, 0.3) ?? accent,
                ],
              ),
        image: hasAvatar
            ? DecorationImage(image: NetworkImage(avatarUrl), fit: BoxFit.cover)
            : null,
        border: Border.all(
          color: isDark
              ? scheme.surface.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.94),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: isDark ? 12 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: hasAvatar
          ? null
          : icon != null
          ? Icon(icon, color: Colors.white, size: 17)
          : Text(
              _initialsFor(title),
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _InboxDivider extends StatelessWidget {
  const _InboxDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: AppSpacing.md + 8 + _kAvatarSize + AppSpacing.md,
      endIndent: AppSpacing.md + 8,
      color: scheme.outlineVariant.withValues(alpha: 0.22),
    );
  }
}

class _InboxEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _InboxEmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = _isDarkScheme(scheme);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: isDark
            ? _blendTone(scheme.primary, scheme.surface, alpha: 0.055)
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.28 : 0.38),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.14 : 0.06),
            blurRadius: isDark ? 18 : 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            color: scheme.primary,
            size: 30,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.84),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InboxLoadingState extends StatelessWidget {
  final String label;

  const _InboxLoadingState({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = _isDarkScheme(scheme);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: isDark
            ? _blendTone(scheme.primary, scheme.surface, alpha: 0.055)
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.28 : 0.38),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.14 : 0.06),
            blurRadius: isDark ? 18 : 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxFab extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;

  const _InboxFab({required this.onPressed, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = _isDarkScheme(scheme);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: isDark ? 0.24 : 0.2),
            blurRadius: _isDarkScheme(scheme) ? 26 : 20,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: _isDarkScheme(scheme) ? 0.16 : 0.06,
            ),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton(
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: scheme.surface.withValues(alpha: isDark ? 0.08 : 0.92),
          ),
        ),
        onPressed: onPressed,
        child: Icon(icon, size: 22),
      ),
    );
  }
}

List<ChatConversation> _sortConversations(List<ChatConversation> items) {
  final sorted = [...items];
  sorted.sort((left, right) {
    final leftTime = left.lastMessageAt ?? left.createdAt ?? DateTime(1970);
    final rightTime = right.lastMessageAt ?? right.createdAt ?? DateTime(1970);
    return rightTime.compareTo(leftTime);
  });
  return sorted;
}

List<ChatConversation> _applyConversationSearch(
  List<ChatConversation> items,
  String query,
) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return items;
  }

  return items.where((conversation) {
    final title = _conversationTitle(conversation).toLowerCase();
    final preview = conversation.lastMessagePreview.toLowerCase();
    return title.contains(trimmed) || preview.contains(trimmed);
  }).toList();
}

List<_QueueConversationEntry> _applyQueueSearch(
  List<_QueueConversationEntry> items,
  String query,
) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return items;
  }

  return items.where((entry) {
    final request = entry.request;
    final haystacks = <String>[
      _queueTitle(entry),
      _queueSubtitle(request),
      request.id,
      request.status,
      entry.conversation.lastMessagePreview,
      ...request.items.map((item) => item.name),
    ].map((value) => value.toLowerCase());

    return haystacks.any((value) => value.contains(trimmed));
  }).toList();
}

String _conversationTitle(ChatConversation conversation) {
  final displayName = conversation.displayName.trim();
  if (displayName.isNotEmpty) {
    return displayName;
  }

  final title = conversation.title.trim();
  if (title.isNotEmpty) {
    return title;
  }

  return "Unknown chat";
}

String _queueTitle(_QueueConversationEntry entry) {
  final title = _conversationTitle(entry.conversation);
  if (title.trim().isNotEmpty && title != "Unknown chat") {
    return title;
  }
  return "Request #${_shortRequestId(entry.request.id)}";
}

String _queueSubtitle(PurchaseRequest request) {
  final firstItem = request.items.isEmpty ? "" : request.items.first.name;
  final extraItemCount = request.items.length > 1
      ? request.items.length - 1
      : 0;
  final itemSummary = firstItem.isEmpty
      ? ""
      : extraItemCount > 0
      ? "$firstItem +$extraItemCount more"
      : firstItem;
  return itemSummary.isEmpty
      ? _queueStatusLabel(request.progressStage)
      : itemSummary;
}

String _queueStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case "requested":
      return "Accepted";
    case "quoted":
      return "Quoted";
    case "proof_submitted":
      return "Proof";
    case "approved":
      return "Approved";
    case "shipped":
      return "Shipped";
    case "delivered":
      return "Delivered";
    case "cancelled":
      return "Cancelled";
    case "rejected":
      return "Rejected";
    default:
      return "Pending";
  }
}

Color _queueStatusColor(String status, ColorScheme scheme) {
  switch (status.trim().toLowerCase()) {
    case "requested":
      return scheme.tertiary;
    case "quoted":
      return scheme.secondary;
    case "proof_submitted":
      return scheme.primary;
    case "approved":
      return AppColors.success;
    case "shipped":
      return scheme.secondary;
    case "delivered":
      return AppColors.success;
    case "cancelled":
    case "rejected":
      return scheme.error;
    default:
      return scheme.primary;
  }
}

String _shortRequestId(String id) {
  final trimmed = id.trim();
  if (trimmed.length <= 6) {
    return trimmed.toUpperCase();
  }
  return trimmed.substring(trimmed.length - 6).toUpperCase();
}

String _formatInboxTime(DateTime? value) {
  if (value == null) {
    return "";
  }

  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(local.year, local.month, local.day);
  final difference = today.difference(target).inDays;
  if (difference == 0) {
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }
  if (difference > 0 && difference < 7) {
    const weekdays = <String>["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return weekdays[local.weekday - 1];
  }
  return "${local.day}/${local.month}";
}

String _initialsFor(String value) {
  final parts = value.trim().split(RegExp(r"\s+"));
  if (parts.isEmpty || parts.first.isEmpty) {
    return "?";
  }
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }
  return "${parts.first.characters.first.toUpperCase()}${parts.last.characters.first.toUpperCase()}";
}

Color _accentForConversation(
  ChatConversation conversation,
  ColorScheme scheme,
) {
  if (conversation.type.trim().toLowerCase() == "group") {
    return scheme.tertiary;
  }
  return _accentForName(_conversationTitle(conversation), scheme);
}

Color _accentForName(String value, ColorScheme scheme) {
  final palette = <Color>[
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
    _blendTone(
      scheme.primary,
      scheme.secondary,
      alpha: _isDarkScheme(scheme) ? 0.32 : 0.22,
    ),
  ];
  final hash = value.runes.fold<int>(0, (sum, rune) => sum + rune);
  return palette[hash % palette.length];
}

WidgetStateProperty<Color?> _interactiveOverlay(ColorScheme scheme) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return scheme.primary.withValues(alpha: 0.08);
    }
    if (states.contains(WidgetState.hovered)) {
      return scheme.primary.withValues(alpha: 0.05);
    }
    if (states.contains(WidgetState.focused)) {
      return scheme.primary.withValues(alpha: 0.06);
    }
    return null;
  });
}

bool _isDarkScheme(ColorScheme scheme) {
  return ThemeData.estimateBrightnessForColor(scheme.surface) ==
      Brightness.dark;
}

Color _blendTone(Color tint, Color base, {required double alpha}) {
  return Color.alphaBlend(tint.withValues(alpha: alpha), base);
}
