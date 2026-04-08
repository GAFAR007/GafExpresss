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
const String _logThemeChange = "theme_change";

const double _kInboxMaxWidth = 760;
const double _kAvatarSize = 44;
const Color _kInboxHeroTop = Color(0xFFFFDABF);
const Color _kInboxHeroMiddle = Color(0xFFD4E3FF);
const Color _kInboxHeroBottom = Color(0xFFD8F2E1);
const Color _kInboxHeroPeach = Color(0xFFFFBB8A);
const Color _kInboxHeroBlue = Color(0xFFA8C4FF);
const Color _kInboxHeroMint = Color(0xFF9EDAB2);
const Color _kInboxHeroDarkTop = Color(0xFF2A2131);
const Color _kInboxHeroDarkMiddle = Color(0xFF1B3761);
const Color _kInboxHeroDarkBottom = Color(0xFF18392E);
const Color _kInboxHeroDarkPeach = Color(0xFF9A624C);
const Color _kInboxHeroDarkBlue = Color(0xFF4569A8);
const Color _kInboxHeroDarkMint = Color(0xFF2F6A55);
const Color _kInboxHeroGlass = Color(0xFFFDFEFF);

class _ChatInboxCopy {
  static const String title = "Chats";
  static const String searchHint = "Search messages or people";
  static const String directLabel = "Direct";
  static const String groupLabel = "Group";
  static const String queueLabel = "Queue";
  static const String onlineLabel = "Online";
  static const String offlineLabel = "Offline";
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
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
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
                    onThemeChanged: (mode) {
                      _log(_logThemeChange, extra: {"mode": mode.name});
                      ref
                          .read(appThemeModeProvider.notifier)
                          .setMode(mode, source: "chat_inbox_header");
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
  final ValueChanged<AppThemeMode> onThemeChanged;
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
    required this.onThemeChanged,
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

    return SafeArea(
      top: false,
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kInboxMaxWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: AppSpacing.section),
            children: [
              _InboxHeroSection(
                isOnline: isOnline,
                filter: filter,
                controller: searchController,
                onOpenProfile: onOpenProfile,
                onPresenceChanged: onPresenceChanged,
                onThemeChanged: onThemeChanged,
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
}

class _InboxBackdrop extends StatelessWidget {
  const _InboxBackdrop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = _isDarkScheme(scheme);

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
  final bool isOnline;
  final _ChatInboxFilter filter;
  final TextEditingController controller;
  final VoidCallback onOpenProfile;
  final ValueChanged<bool> onPresenceChanged;
  final ValueChanged<AppThemeMode> onThemeChanged;
  final ValueChanged<_ChatInboxFilter> onFilterChange;
  final ValueChanged<String> onSearchChanged;

  const _InboxHeroSection({
    required this.isOnline,
    required this.filter,
    required this.controller,
    required this.onOpenProfile,
    required this.onPresenceChanged,
    required this.onThemeChanged,
    required this.onFilterChange,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = _isDarkScheme(scheme);
    final topInset = MediaQuery.of(context).viewPadding.top;
    const radius = BorderRadius.only(
      bottomLeft: Radius.circular(34),
      bottomRight: Radius.circular(34),
    );
    final topColor = isDark ? _kInboxHeroDarkTop : _kInboxHeroTop;
    final middleColor = isDark ? _kInboxHeroDarkMiddle : _kInboxHeroMiddle;
    final bottomColor = isDark ? _kInboxHeroDarkBottom : _kInboxHeroBottom;
    final peachColor = isDark ? _kInboxHeroDarkPeach : _kInboxHeroPeach;
    final blueColor = isDark ? _kInboxHeroDarkBlue : _kInboxHeroBlue;
    final mintColor = isDark ? _kInboxHeroDarkMint : _kInboxHeroMint;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topColor, middleColor, bottomColor],
          stops: const [0, 0.52, 1],
        ),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned(
              top: -88,
              right: -54,
              child: _BackdropBloom(size: 238, color: peachColor),
            ),
            Positioned(
              top: 66,
              right: 8,
              child: _BackdropBloom(size: 210, color: blueColor),
            ),
            Positioned(
              left: -72,
              bottom: 26,
              child: _BackdropBloom(size: 220, color: mintColor),
            ),
            Positioned(
              top: 12,
              left: -24,
              child: _BackdropBloom(size: 132, color: peachColor),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.03 : 0.12),
                      Colors.white.withValues(alpha: isDark ? 0.01 : 0.02),
                      Colors.white.withValues(alpha: isDark ? 0.02 : 0.07),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                topInset + AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InboxHeader(
                    isOnline: isOnline,
                    onOpenProfile: onOpenProfile,
                    onPresenceChanged: onPresenceChanged,
                    onThemeChanged: onThemeChanged,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _InboxSearchBar(
                    controller: controller,
                    onChanged: onSearchChanged,
                    onClear: () {
                      controller.clear();
                      onSearchChanged('');
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _InboxTabBar(filter: filter, onChanged: onFilterChange),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxHeader extends StatelessWidget {
  final bool isOnline;
  final VoidCallback onOpenProfile;
  final ValueChanged<bool> onPresenceChanged;
  final ValueChanged<AppThemeMode> onThemeChanged;

  const _InboxHeader({
    required this.isOnline,
    required this.onOpenProfile,
    required this.onPresenceChanged,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ChatInboxCopy.title,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      height: 0.9,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs + 1),
                  Text(
                    "Your active conversations and request queue in one place.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ProfileActionButton(onPressed: onOpenProfile),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _PresenceToggle(isOnline: isOnline, onChanged: onPresenceChanged),
            _ThemeModeMiniToggle(onChanged: onThemeChanged),
          ],
        ),
      ],
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ProfileActionButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        overlayColor: _interactiveOverlay(scheme),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              scheme.surface.withValues(alpha: 0.84),
              _kInboxHeroGlass.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(
                  alpha: _isDarkScheme(scheme) ? 0.12 : 0.05,
                ),
                blurRadius: _isDarkScheme(scheme) ? 14 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

class _PresenceToggle extends StatelessWidget {
  final bool isOnline;
  final ValueChanged<bool> onChanged;

  const _PresenceToggle({required this.isOnline, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onlineAccent = AppColors.success;
    final offlineAccent = scheme.onSurfaceVariant.withValues(alpha: 0.56);

    Widget buildChoice({
      required bool selected,
      required String label,
      required Color accent,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          overlayColor: _interactiveOverlay(scheme),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 36,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.surface.withValues(alpha: 0.92)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.shadow.withValues(
                          alpha: _isDarkScheme(scheme) ? 0.08 : 0.025,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: selected ? 9 : 7,
                  height: selected ? 9 : 7,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.xs + 1),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 0.68),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.08,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildChoice(
            selected: isOnline,
            label: _ChatInboxCopy.onlineLabel,
            accent: onlineAccent,
            onTap: () => onChanged(true),
          ),
          buildChoice(
            selected: !isOnline,
            label: _ChatInboxCopy.offlineLabel,
            accent: offlineAccent,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeMiniToggle extends ConsumerWidget {
  final ValueChanged<AppThemeMode> onChanged;

  const _ThemeModeMiniToggle({required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = ref.watch(appThemeModeProvider);
    final activeMode = mode == AppThemeMode.classic
        ? AppThemeMode.classic
        : AppThemeMode.dark;

    Widget buildModeChip({
      required AppThemeMode value,
      required String semanticLabel,
      required IconData icon,
    }) {
      final selected = activeMode == value;
      return Tooltip(
        message: semanticLabel,
        child: Semantics(
          button: true,
          label: semanticLabel,
          selected: selected,
          child: InkWell(
            onTap: selected ? null : () => onChanged(value),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            overlayColor: _interactiveOverlay(scheme),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.surface.withValues(alpha: 0.92)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected
                      ? scheme.outlineVariant.withValues(alpha: 0.3)
                      : Colors.transparent,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: scheme.shadow.withValues(
                            alpha: _isDarkScheme(scheme) ? 0.08 : 0.022,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 17,
                color: selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withValues(alpha: 0.82),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildModeChip(
            value: AppThemeMode.classic,
            semanticLabel: "Classic theme",
            icon: Icons.wb_sunny_outlined,
          ),
          const SizedBox(width: 2),
          buildModeChip(
            value: AppThemeMode.dark,
            semanticLabel: "Dark theme",
            icon: Icons.dark_mode_outlined,
          ),
        ],
      ),
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
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: _kInboxHeroGlass.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: _isDarkScheme(scheme) ? 0.14 : 0.08,
            ),
            blurRadius: _isDarkScheme(scheme) ? 18 : 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        cursorColor: scheme.primary,
        style: theme.textTheme.titleSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: _ChatInboxCopy.searchHint,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.62),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
            size: 18,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 42,
            minHeight: 42,
          ),
          suffixIcon: controller.text.trim().isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  iconSize: 18,
                  splashRadius: 18,
                  visualDensity: VisualDensity.compact,
                  color: scheme.onSurfaceVariant,
                  icon: const Icon(Icons.close_rounded),
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.md + 1,
          ),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _InboxTabButton(
            label: _ChatInboxCopy.directLabel,
            selected: filter == _ChatInboxFilter.direct,
            onTap: () => onChanged(_ChatInboxFilter.direct),
          ),
          const SizedBox(width: AppSpacing.lg),
          _InboxTabButton(
            label: _ChatInboxCopy.groupLabel,
            selected: filter == _ChatInboxFilter.group,
            onTap: () => onChanged(_ChatInboxFilter.group),
          ),
          const SizedBox(width: AppSpacing.lg),
          _InboxTabButton(
            label: _ChatInboxCopy.queueLabel,
            selected: filter == _ChatInboxFilter.queue,
            onTap: () => onChanged(_ChatInboxFilter.queue),
          ),
        ],
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

    return InkWell(
      onTap: onTap,
      overlayColor: _interactiveOverlay(scheme),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + 1,
          vertical: AppSpacing.sm + 1,
        ),
        decoration: BoxDecoration(
          color: selected
              ? _kInboxHeroGlass.withValues(alpha: 0.7)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.shadow.withValues(
                      alpha: _isDarkScheme(scheme) ? 0.08 : 0.035,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.64),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: -0.15,
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
    final radius = BorderRadius.circular(AppRadius.xxl);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _blendTone(
          scheme.primary,
          scheme.surface,
          alpha: _isDarkScheme(scheme) ? 0.045 : 0.012,
        ),
        borderRadius: radius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: _isDarkScheme(scheme) ? 0.14 : 0.04,
            ),
            blurRadius: _isDarkScheme(scheme) ? 18 : 14,
            offset: const Offset(0, 10),
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
      color: scheme.surface.withValues(alpha: 0.72),
      child: InkWell(
        onTap: onTap,
        overlayColor: _interactiveOverlay(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          letterSpacing: -0.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xxs + 1),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.76,
                          ),
                          fontWeight: FontWeight.w500,
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
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  timeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.04,
                  ),
                ),
              ),
            ],
          ),
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
    final request = entry.request;
    final title = _queueTitle(entry);
    final subtitle = _queueSubtitle(request);
    final accent = _queueStatusColor(request.progressStage, scheme);
    final statusLabel = _queueStatusLabel(request.progressStage);
    final timeLabel = _formatInboxTime(entry.sortTime);

    return Material(
      color: scheme.surface.withValues(alpha: 0.72),
      child: InkWell(
        onTap: onTap,
        overlayColor: _interactiveOverlay(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          letterSpacing: -0.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xxs + 1),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.76,
                          ),
                          fontWeight: FontWeight.w500,
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
                  Text(
                    timeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm - 1,
                      vertical: AppSpacing.xxs + 1,
                    ),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        accent.withValues(alpha: 0.09),
                        scheme.surface,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: accent.withValues(alpha: 0.12)),
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
        border: Border.all(color: scheme.surface.withValues(alpha: 0.82)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: _isDarkScheme(scheme) ? 0.18 : 0.06,
            ),
            blurRadius: _isDarkScheme(scheme) ? 12 : 8,
            offset: const Offset(0, 4),
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
      indent: AppSpacing.md + 2 + _kAvatarSize + AppSpacing.md,
      endIndent: AppSpacing.md,
      color: scheme.outlineVariant.withValues(alpha: 0.18),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: _blendTone(
          scheme.primary,
          scheme.surface,
          alpha: _isDarkScheme(scheme) ? 0.04 : 0.012,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: _isDarkScheme(scheme) ? 0.14 : 0.04,
            ),
            blurRadius: _isDarkScheme(scheme) ? 16 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            color: scheme.onSurfaceVariant,
            size: 28,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: _blendTone(
          Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.surface,
          alpha: _isDarkScheme(Theme.of(context).colorScheme) ? 0.04 : 0.012,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(label),
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
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(
              alpha: _isDarkScheme(scheme) ? 0.24 : 0.18,
            ),
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
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.surface.withValues(
              alpha: _isDarkScheme(scheme) ? 0.08 : 0.88,
            ),
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
