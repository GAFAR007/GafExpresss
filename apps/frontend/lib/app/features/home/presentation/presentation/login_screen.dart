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
  // WHY: Lets auth-adjacent flows return users with their email already filled in.
  final String? initialEmail;

  const LoginScreen({super.key, this.redirectTo, this.initialEmail});

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
  // WHY:
  // - Keeps sign-in failures visible inside the sheet instead of behind it.
  String? _loginErrorMessage;

  // ------------------------------------------------------------
  // PASSWORD VISIBILITY
  // ------------------------------------------------------------
  // WHY:
  // - Lets users confirm password entry in the sign-in sheet.
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final initialEmail = (widget.initialEmail ?? "").trim();
    if (initialEmail.isNotEmpty) {
      // WHY: Route-provided email should win over remembered storage state.
      _emailCtrl.text = initialEmail;
      AppDebug.log("LOGIN", "Prefilled route email");
    }
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

    if (_emailCtrl.text.trim().isNotEmpty) {
      // WHY: Do not overwrite a more specific email passed from another flow.
      AppDebug.log("LOGIN", "Skip saved email (email already present)");
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

  void _setLoginError(
    String? message, {
    void Function(void Function())? setModalState,
  }) {
    if (mounted) {
      setState(() => _loginErrorMessage = message);
    }
    if (setModalState != null) {
      try {
        setModalState(() {});
      } catch (_) {}
    }
  }

  String _friendlyLoginErrorText(Object error) {
    final raw = error.toString().trim();
    if (raw.startsWith("Exception: ")) {
      return raw.substring("Exception: ".length).trim();
    }
    return raw;
  }

  void _goToForgotPassword(BuildContext sheetContext) {
    AppDebug.log("LOGIN", "Forgot password tapped");
    Navigator.of(sheetContext).pop();
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      context.go("/forgot-password");
      return;
    }
    final encodedEmail = Uri.encodeQueryComponent(email);
    context.go("/forgot-password?email=$encodedEmail");
  }

  Widget _buildLoginErrorCard(BuildContext context) {
    final message = _loginErrorMessage;
    if (message == null || message.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onErrorContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
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
      _setLoginError(
        "Enter both your email and password to sign in.",
        setModalState: setModalState,
      );
      return;
    }

    _setLoginError(null, setModalState: setModalState);
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

      // WHY: Resolve redirect target from explicit next param or cached invite.
      final rawRedirect = widget.redirectTo;
      final decodedRedirect = rawRedirect == null || rawRedirect.trim().isEmpty
          ? null
          : Uri.decodeComponent(rawRedirect.trim());
      String? redirectTarget =
          decodedRedirect != null && decodedRedirect.startsWith('/')
          ? decodedRedirect
          : null;

      if (redirectTarget == null) {
        // WHY: Recover invite flow when next= is lost during login.
        final pendingInvite = await storage.readPendingInviteToken();
        if (pendingInvite != null && pendingInvite.trim().isNotEmpty) {
          // WHY: Keep pending invite in memory for router redirects.
          ref.read(pendingInviteTokenProvider.notifier).state = pendingInvite
              .trim();
          redirectTarget = Uri(
            path: '/business-invite',
            queryParameters: {'token': pendingInvite.trim()},
          ).toString();
          AppDebug.log(
            "LOGIN",
            "Resolved pending invite token",
            extra: {"hasPendingInvite": true},
          );
        } else {
          AppDebug.log("LOGIN", "No pending invite token");
        }
      } else {
        // WHY: Clear pending invite token unless we are going back to invite.
        final isInviteRedirect = redirectTarget.startsWith('/business-invite');
        if (!isInviteRedirect) {
          await storage.clearPendingInviteToken();
          ref.read(pendingInviteTokenProvider.notifier).state = null;
          AppDebug.log(
            "LOGIN",
            "Cleared pending invite token (non-invite redirect)",
          );
        }
      }

      _setLoading(false, setModalState: setModalState);

      if (!mounted) return;

      // ✅ Navigate to home or redirect target after successful login
      final safeTarget =
          redirectTarget != null &&
              redirectTarget.startsWith('/business-invite')
          ? '/business-invite?token=***'
          : redirectTarget ?? '/home';
      AppDebug.log(
        "LOGIN",
        "Navigate after login",
        extra: {"target": safeTarget},
      );
      if (Navigator.of(context).canPop()) {
        // WHY: Close the sheet before switching routes.
        Navigator.of(context).pop();
      }
      context.go(redirectTarget ?? '/home');
    } catch (e) {
      AppDebug.log("LOGIN", "Login failed", extra: {"error": e.toString()});

      _setLoading(false, setModalState: setModalState);
      _setLoginError(_friendlyLoginErrorText(e), setModalState: setModalState);

      if (!mounted) return;
    }
  }

  /// ------------------------------------------------------------
  /// SIGN-IN SHEET
  /// ------------------------------------------------------------
  void _openSignInSheet() {
    AppDebug.log("LOGIN", "Open sign-in sheet");
    _setLoginError(null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // WHY: Keep sheet backdrop aligned with the current theme.
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0),
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
                onChanged: (_) =>
                    _setLoginError(null, setModalState: setModalState),
                decoration: const InputDecoration(labelText: "Email"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                onChanged: (_) =>
                    _setLoginError(null, setModalState: setModalState),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _goToForgotPassword(sheetContext),
                    icon: const Icon(Icons.key_outlined, size: 16),
                    label: const Text("Forgot password?"),
                  ),
                  const Spacer(),
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
              _buildLoginErrorCard(sheetContext),
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
                    color: scheme.onPrimary.withValues(alpha: 0.7),
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
              side: BorderSide(color: scheme.onPrimary.withValues(alpha: 0.7)),
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
            color: scheme.shadow.withValues(alpha: 0.08),
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
            eyebrow: "Guest storefront",
            title: "Fresh styles and farm essentials in one place",
            subtitle:
                "Browse fashion, groceries, and farm produce before signing in.",
            primaryLabel: "Explore products",
            onPrimaryTap: () {
              AppDebug.log("LOGIN", "Guest storefront promo tapped");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Scroll to browse all items")),
              );
            },
            highlights: const [
              "Curated picks across fashion, groceries, and produce",
              "Preview pricing, stock, and product details before sign in",
            ],
          );
        }

        if (index == 1) {
          return HomePopularSection(
            title: "Trending now",
            subtitle:
                "Customer-facing picks with clearer pricing and product metadata.",
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
