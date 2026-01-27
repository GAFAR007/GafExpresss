/// lib/app/features/home/presentation/presentation/login_screen.dart
/// -----------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Guest-first login screen that mirrors the Home layout.
///
/// WHY IT'S IMPORTANT:
/// - Lets users browse products before signing in.
/// - Keeps checkout, cart, and orders locked until auth succeeds.
/// - Provides a sign-in sheet that feels like a native part of the app.
/// - Remembers the last login email so users only enter passwords next time.
///
/// HOW IT WORKS:
/// 1) Render a home-like header + guest access callout.
/// 2) Allow search + browse of products (read-only).
/// 3) Tap "Sign in" to open a bottom sheet with login form.
/// 4) Login success -> navigate to /home (or ?next=...).
///
/// DEBUGGING STRATEGY:
/// - Logs show:
///   - build()
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/home_popular_section.dart';
import 'package:frontend/app/features/home/presentation/home_promo_section.dart';
import 'package:frontend/app/features/home/presentation/product_item_button.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart'
    as product_providers;
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class LoginScreen extends ConsumerStatefulWidget {
  // WHY: Capture optional redirect target for invite links or deep links.
  final String? redirectTo;

  const LoginScreen({super.key, this.redirectTo});

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
  // ------------------------------------------------------------
  // LOADING FLAG
  // ------------------------------------------------------------
  // WHY:
  // - Prevent duplicate login requests from double taps.
  bool _isLoading = false;

  // ------------------------------------------------------------
  // PASSWORD VISIBILITY
  // ------------------------------------------------------------
  // WHY:
  // - Lets users confirm password entry in the sign-in sheet.
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    // WHY: Load remembered email without blocking first paint.
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// ------------------------------------------------------------
  /// LOAD SAVED EMAIL
  /// ------------------------------------------------------------
  Future<void> _loadSavedEmail() async {
    // WHY: Pull last email from secure storage for a faster login.
    AppDebug.log("LOGIN", "Loading saved email");
    final storage = ref.read(authSessionStorageProvider);
    final savedEmail = await storage.readLastEmail();

    if (!mounted) {
      // WHY: Avoid touching controllers after dispose.
      AppDebug.log("LOGIN", "Skip saved email (screen disposed)");
      return;
    }

    if (savedEmail == null || savedEmail.isEmpty) {
      AppDebug.log("LOGIN", "No saved email to prefill");
      return;
    }

    // WHY: Prefill only the email so password stays private.
    _emailCtrl.text = savedEmail;
    AppDebug.log("LOGIN", "Prefilled saved email");
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
    final storage = ref.read(authSessionStorageProvider);

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

      // WHY: Remember the last email for quick re-login.
      await storage.saveLastEmail(email);

      // WHY: Persist session so router can guard /home reliably.
      await ref.read(authSessionProvider.notifier).setSession(session);

      _setLoading(false, setModalState: setModalState);

      if (!context.mounted) return;

      // WHY: Respect invite/deep-link target if provided.
      final redirectTarget =
          widget.redirectTo == null || widget.redirectTo!.trim().isEmpty
          ? null
          : Uri.decodeComponent(widget.redirectTo!.trim());

      // ✅ Navigate to home or redirect target after successful login
      AppDebug.log(
        "LOGIN",
        "Navigate after login",
        extra: {"target": redirectTarget ?? "/home"},
      );
      if (Navigator.of(context).canPop()) {
        // WHY: Close the sheet before switching routes.
        Navigator.of(context).pop();
      }
      context.go(redirectTarget ?? '/home');
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
      // WHY: Keep sheet backdrop aligned with the current theme.
      backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0),
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
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

    return Padding(
      // WHY: Keep the sheet above the keyboard on mobile.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: scheme.surface,
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
                    color: scheme.outlineVariant,
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
                  color: scheme.onSurfaceVariant,
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
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    onPressed: () {
                      // WHY: Help users verify password without retyping.
                      AppDebug.log("LOGIN", "Toggle password visibility");
                      setState(() => _showPassword = !_showPassword);
                    },
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
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
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
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
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Guest access - Browse products only",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary.withOpacity(0.7),
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
              foregroundColor: scheme.onPrimary,
              side: BorderSide(color: scheme.onPrimary.withOpacity(0.7)),
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
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.08),
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
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.lock,
              color: scheme.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Guest mode", style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  "Sign in to add to cart, checkout, and track orders.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
  Widget _buildProductsList({required List<Product> products}) {
    final theme = Theme.of(context);

    if (products.isEmpty) {
      return const Center(child: Text("No products yet"));
    }

    const headerText = "Browse all items";
    final totalItems = products.length + 3;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: totalItems,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return HomePromoSection(
            products: products,
            onSeeAllTap: () {
              // WHY: Provide a friendly hint without introducing new routes.
              AppDebug.log("LOGIN", "Special for you see all tapped");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Scroll to browse all items")),
              );
            },
            onPromoTap: (product) {
              AppDebug.log(
                "LOGIN",
                "Special for you tapped",
                extra: {"id": product.id},
              );
              AppDebug.log(
                "LOGIN",
                "Navigate -> /product/:id",
                extra: {"id": product.id},
              );
              context.go('/product/${product.id}');
            },
          );
        }

        if (index == 1) {
          return HomePopularSection(
            products: products,
            onSeeAllTap: () {
              // WHY: Keep guest flow simple while encouraging browsing.
              AppDebug.log("LOGIN", "Popular items see all tapped");
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("More items below")));
            },
            onProductTap: (product) {
              AppDebug.log(
                "LOGIN",
                "Popular item tapped",
                extra: {"id": product.id},
              );
              AppDebug.log(
                "LOGIN",
                "Navigate -> /product/:id",
                extra: {"id": product.id},
              );
              context.go('/product/${product.id}');
            },
          );
        }

        if (index == 2) {
          return Text(headerText, style: theme.textTheme.titleMedium);
        }

        final product = products[index - 3];
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
            AppDebug.log(
              "LOGIN",
              "Navigate -> /product/:id",
              extra: {"id": product.id},
            );
            context.go('/product/${product.id}');
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("LOGIN", "build()", extra: {"isLoading": _isLoading});

    // WHY: Guest mode is browse-only, so we always load the full list.
    final productsAsync = ref.watch(product_providers.productsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildGuestHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildGuestAccessCard()],
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
                  return _buildProductsList(products: products);
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
