/// lib/app/features/home/presentation/presentation/login_screen.dart
/// -----------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Guest-first login screen that mirrors the Home layout.
///
/// WHY IT'S IMPORTANT:
/// - Lets users browse/search products before signing in.
/// - Keeps checkout, cart, and orders locked until auth succeeds.
/// - Provides a sign-in sheet that feels like a native part of the app.
///
/// HOW IT WORKS:
/// 1) Render a home-like header + guest access callout.
/// 2) Allow search + browse of products (read-only).
/// 3) Tap "Sign in" to open a bottom sheet with login form.
/// 4) Login success -> navigate to /home.
///
/// DEBUGGING STRATEGY:
/// - Logs show:
///   - build()
///   - search input + debounce
///   - button taps (sign-in / register / product)
///   - API start/end (via AuthApi/ProductApi)
///   - navigation events
///
/// SAFETY:
/// - NEVER log password
/// - NEVER log token
/// - Always check context.mounted after await
///
/// MULTI-PLATFORM:
/// - Works on Web / Android / iOS (no dart:io usage here)
/// -----------------------------------------------------------------
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_item_button.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ------------------------------------------------------------
  // CONTROLLERS
  // ------------------------------------------------------------
  // WHY:
  // - We need to read user input safely.
  // - Dispose to avoid memory leaks.
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  late final TextEditingController _searchController;

  // ------------------------------------------------------------
  // LOADING FLAG
  // ------------------------------------------------------------
  // WHY:
  // - Prevent duplicate login requests from double taps.
  bool _isLoading = false;

  // ------------------------------------------------------------
  // SEARCH STATE
  // ------------------------------------------------------------
  // WHY:
  // - Debounce prevents a request on every key press.
  String _pendingQuery = "";
  String _activeQuery = "";
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // WHY: Keep search input stable across rebuilds.
    _searchController = TextEditingController(text: _pendingQuery);
  }

  @override
  void dispose() {
    // WHY: Cancel debounce to avoid callbacks after dispose.
    _searchDebounce?.cancel();
    _searchController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// ------------------------------------------------------------
  /// SEARCH INPUT HANDLER
  /// ------------------------------------------------------------
  void _updateQuery(String value) {
    // WHY: Track raw typing and debounce remote search.
    AppDebug.log("LOGIN", "Search input changed", extra: {"raw": value});
    setState(() => _pendingQuery = value);

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final trimmed = _pendingQuery.trim();
      AppDebug.log("LOGIN", "Search debounce fired", extra: {"q": trimmed});
      setState(() => _activeQuery = trimmed);
    });
  }

  /// ------------------------------------------------------------
  /// LOADING STATE HELPER
  /// ------------------------------------------------------------
  void _setLoading(
    bool value, {
    void Function(void Function())? setModalState,
  }) {
    // WHY: Keep both the screen and sheet in sync when loading changes.
    if (mounted) setState(() => _isLoading = value);
    if (setModalState != null) {
      // WHY: Sheet may close during navigation; ignore if disposed.
      try {
        setModalState(() {});
      } catch (_) {}
    }
  }

  /// ------------------------------------------------------------
  /// LOGIN HANDLER
  /// ------------------------------------------------------------
  Future<void> _onLoginPressed({
    void Function(void Function())? setModalState,
  }) async {
    if (_isLoading) {
      AppDebug.log("LOGIN", "Ignored tap because _isLoading=true");
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    // ------------------------------------------------------------
    // BASIC VALIDATION (UI LEVEL)
    // ------------------------------------------------------------
    if (email.isEmpty || password.isEmpty) {
      AppDebug.log("LOGIN", "Validation failed (empty email/password)");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email and password are required")),
      );
      return;
    }

    _setLoading(true, setModalState: setModalState);

    // Read API from provider (keeps UI away from Dio details)
    final api = ref.read(authApiProvider);

    try {
      // ✅ Never log password
      AppDebug.log("LOGIN", "Starting login()", extra: {"email": email});

      final session = await api.login(email: email, password: password);

      // ✅ Never log token
      AppDebug.log(
        "LOGIN",
        "Login success",
        extra: {"userId": session.user.id},
      );

      // WHY: Persist session so router can guard /home reliably.
      await ref.read(authSessionProvider.notifier).setSession(session);

      _setLoading(false, setModalState: setModalState);

      if (!context.mounted) return;

      // ✅ Navigate to home after successful login
      AppDebug.log("LOGIN", "Navigate -> /home");
      if (Navigator.of(context).canPop()) {
        // WHY: Close the sheet before switching routes.
        Navigator.of(context).pop();
      }
      context.go('/home');
    } catch (e) {
      AppDebug.log("LOGIN", "Login failed", extra: {"error": e.toString()});

      _setLoading(false, setModalState: setModalState);

      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Login failed: $e")));
    }
  }

  /// ------------------------------------------------------------
  /// SIGN-IN SHEET
  /// ------------------------------------------------------------
  void _openSignInSheet() {
    AppDebug.log("LOGIN", "Open sign-in sheet");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // WHY: StatefulBuilder allows the sheet to refresh on loading changes.
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _buildSignInSheet(
              sheetContext: sheetContext,
              setModalState: setModalState,
            );
          },
        );
      },
    );
  }

  Widget _buildSignInSheet({
    required BuildContext sheetContext,
    required void Function(void Function()) setModalState,
  }) {
    final theme = Theme.of(sheetContext);
    final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

    return Padding(
      // WHY: Keep the sheet above the keyboard on mobile.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // WHY: Visual handle hints this is a draggable sheet.
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Sign in to unlock checkout",
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                "Guest mode lets you browse only. Sign in to add items and pay.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password"),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          AppDebug.log("LOGIN", "Sign in button tapped");
                          _onLoginPressed(setModalState: setModalState);
                        },
                  child: Text(_isLoading ? "Signing in..." : "Sign in"),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        AppDebug.log("LOGIN", "Go Register tapped");
                        Navigator.of(sheetContext).pop();
                        AppDebug.log("LOGIN", "Navigate -> /register");
                        context.go("/register");
                      },
                child: const Text("Create account"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ------------------------------------------------------------
  /// GUEST HEADER
  /// ------------------------------------------------------------
  Widget _buildGuestHeader() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Brand + mode text establishes the guest experience.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Office Store",
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Guest access - Browse & search only",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _isLoading
                ? null
                : () {
                    AppDebug.log("LOGIN", "Header sign-in tapped");
                    _openSignInSheet();
                  },
            icon: const Icon(Icons.lock_open, size: 16),
            label: const Text("Sign in"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------
  /// GUEST ACCESS CARD
  /// ------------------------------------------------------------
  Widget _buildGuestAccessCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // WHY: Lock icon visually reinforces restricted features.
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.lock, color: Colors.orange.shade700, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Guest mode",
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  "Sign in to add to cart, checkout, and track orders.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    AppDebug.log("LOGIN", "Guest card sign-in tapped");
                    _openSignInSheet();
                  },
            child: const Text("Sign in"),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------
  /// PRODUCT LIST (READ-ONLY)
  /// ------------------------------------------------------------
  Widget _buildProductsList({
    required List<Product> products,
    required bool hasQuery,
    required bool isTyping,
    required String activeQuery,
    required String pendingQuery,
  }) {
    final theme = Theme.of(context);

    if (products.isEmpty) {
      final emptyLabel = hasQuery
          ? (isTyping ? "Searching..." : "No results for \"$pendingQuery\"")
          : "No products yet";
      return Center(child: Text(emptyLabel));
    }

    final headerText = hasQuery
        ? (isTyping ? "Searching..." : "Results for \"$activeQuery\"")
        : "Featured products";

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: products.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Text(
            headerText,
            style: theme.textTheme.titleMedium,
          );
        }

        final product = products[index - 1];
        final item = ProductItemData(
          id: product.id,
          name: product.name,
          description: product.description,
          priceCents: product.priceCents,
          stock: product.stock,
          imageUrl: product.imageUrl,
        );

        return ProductItemButton(
          item: item,
          onTap: () {
            AppDebug.log("LOGIN", "Product tapped", extra: {"id": product.id});
            AppDebug.log("LOGIN", "Navigate -> /product/:id", extra: {
              "id": product.id,
            });
            context.go('/product/${product.id}');
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "LOGIN",
      "build()",
      extra: {"isLoading": _isLoading, "query": _activeQuery},
    );

    // WHY: Use remote search provider only when the query is active.
    final pendingQuery = _pendingQuery.trim();
    final activeQuery = _activeQuery.trim();
    final hasQuery = activeQuery.isNotEmpty;
    final isTyping = pendingQuery.isNotEmpty && pendingQuery != activeQuery;
    final productsAsync = hasQuery
        ? ref.watch(productsSearchProvider(activeQuery))
        : ref.watch(productsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F7),
      body: SafeArea(
        child: Column(
          children: [
            _buildGuestHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WHY: Search stays visually aligned with Home styling.
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search products",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: _updateQuery,
                    onSubmitted: (value) {
                      AppDebug.log(
                        "LOGIN",
                        "Search submitted",
                        extra: {"q": value},
                      );
                      _updateQuery(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildGuestAccessCard(),
                ],
              ),
            ),
            Expanded(
              child: productsAsync.when(
                data: (products) {
                  AppDebug.log(
                    "LOGIN",
                    "Products ready",
                    extra: {"count": products.length},
                  );
                  return _buildProductsList(
                    products: products,
                    hasQuery: hasQuery,
                    isTyping: isTyping,
                    activeQuery: activeQuery,
                    pendingQuery: pendingQuery,
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) {
                  AppDebug.log(
                    "LOGIN",
                    "Products load failed",
                    extra: {"error": error.toString()},
                  );
                  return const Center(child: Text("Unable to load products"));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
