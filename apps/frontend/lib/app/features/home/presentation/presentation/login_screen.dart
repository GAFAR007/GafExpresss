/// lib/app/features/home/presentation/presentation/login_screen.dart
/// -----------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Guest-first login screen that now reuses the Home storefront patterns.
///
/// WHY IT'S IMPORTANT:
/// - Lets users browse products before signing in.
/// - Keeps checkout, cart, and orders locked until auth succeeds.
/// - Makes `/login` feel like a real storefront instead of a separate flow.
///
/// HOW IT WORKS:
/// 1) Render a home-style hero, search, category shortcuts, and product rows.
/// 2) Allow browse-only discovery in guest mode.
/// 3) Send cart-like actions to the sign-in sheet.
/// 4) Login success -> navigate to /home (or ?next=...).
/// -----------------------------------------------------------------
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/data/auth_session_storage.dart';
import 'package:frontend/app/features/auth/domain/models/login_shortcut_bundle.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/home_categories_section.dart';
import 'package:frontend/app/features/home/presentation/home_filter_sheet.dart';
import 'package:frontend/app/features/home/presentation/home_hero_section.dart';
import 'package:frontend/app/features/home/presentation/home_product_section.dart';
import 'package:frontend/app/features/home/presentation/home_promo_section.dart';
import 'package:frontend/app/features/home/presentation/home_search_results_section.dart';
import 'package:frontend/app/features/home/presentation/home_search_section.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart'
    as product_providers;
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? redirectTo;
  final String? initialEmail;

  const LoginScreen({super.key, this.redirectTo, this.initialEmail});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _searchController = TextEditingController();
  final GlobalKey _featuredKey = GlobalKey();
  final GlobalKey _categoriesKey = GlobalKey();

  bool _isLoading = false;
  String? _loginErrorMessage;
  bool _showPassword = false;
  StoredLoginCredentials _storedCredentials = const StoredLoginCredentials();
  _LoginShortcutRole _selectedShortcutRole = _LoginShortcutRole.user;
  final Map<_LoginShortcutRole, Future<LoginShortcutBundle>>
  _loginShortcutFutures = {};

  String _pendingQuery = "";
  String _activeQuery = "";
  String? _selectedCategory;
  String? _selectedSubcategory;
  bool _inStockOnly = false;
  ProductSort _sort = ProductSort.none;
  Set<String> _favoriteIds = <String>{};
  Timer? _searchDebounce;

  bool get _hasFilters =>
      _inStockOnly ||
      _sort != ProductSort.none ||
      _selectedCategory != null ||
      _selectedSubcategory != null;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_handleCredentialFieldChanged);
    _passwordCtrl.addListener(_handleCredentialFieldChanged);
    _primeLoginAccountsFuture(_selectedShortcutRole);
    final initialEmail = (widget.initialEmail ?? "").trim();
    if (initialEmail.isNotEmpty) {
      _emailCtrl.text = initialEmail;
      AppDebug.log("LOGIN", "Prefilled route email");
    }
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _emailCtrl.removeListener(_handleCredentialFieldChanged);
    _passwordCtrl.removeListener(_handleCredentialFieldChanged);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleCredentialFieldChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<LoginShortcutBundle> _createLoginAccountsFuture(
    _LoginShortcutRole role,
  ) {
    AppDebug.log("LOGIN", "Load login accounts", extra: {"role": role.apiRole});
    return ref.read(authApiProvider).fetchLoginShortcuts(role: role.apiRole);
  }

  Future<LoginShortcutBundle> _primeLoginAccountsFuture(
    _LoginShortcutRole role,
  ) {
    return _loginShortcutFutures.putIfAbsent(
      role,
      () => _createLoginAccountsFuture(role),
    );
  }

  void _refreshLoginAccountsFuture(
    _LoginShortcutRole role, {
    void Function(void Function())? setModalState,
  }) {
    _loginShortcutFutures[role] = _createLoginAccountsFuture(role);
    if (mounted) {
      setState(() {});
    }
    if (setModalState != null) {
      setModalState(() {});
    }
  }

  Future<void> _loadSavedCredentials() async {
    AppDebug.log("LOGIN", "Loading saved credentials");
    final storage = ref.read(authSessionStorageProvider);
    final storedCredentials = await storage.readLastCredentials();

    if (!mounted) {
      AppDebug.log("LOGIN", "Skip saved credentials (screen disposed)");
      return;
    }

    _storedCredentials = storedCredentials;

    final savedEmail = storedCredentials.email;
    if ((savedEmail ?? "").isNotEmpty && _emailCtrl.text.trim().isEmpty) {
      _emailCtrl.text = savedEmail!;
      AppDebug.log("LOGIN", "Prefilled saved email");
    }

    _maybeApplyStoredPassword(
      email: _emailCtrl.text,
      overwrite: _passwordCtrl.text.isEmpty,
    );
    setState(() {});
  }

  void _maybeApplyStoredPassword({
    required String email,
    bool overwrite = false,
    void Function(void Function())? setModalState,
  }) {
    final storedPassword = _storedCredentials.passwordFor(email);
    if (storedPassword == null || storedPassword.isEmpty) {
      return;
    }

    if (!overwrite && _passwordCtrl.text.isNotEmpty) {
      return;
    }

    _passwordCtrl.text = storedPassword;
    if (mounted) {
      setState(() {});
    }
    if (setModalState != null) {
      setModalState(() {});
    }
  }

  String? _resolveShortcutPassword(LoginShortcutAccount account) {
    return _storedCredentials.passwordFor(account.email);
  }

  void _applyLoginShortcut(
    LoginShortcutAccount account, {
    void Function(void Function())? setModalState,
  }) {
    final password = _resolveShortcutPassword(account);

    _emailCtrl.text = account.email;
    _passwordCtrl.text = password ?? "";
    _setLoginError(null, setModalState: setModalState);

    if (mounted) {
      setState(() {});
    }
    if (setModalState != null) {
      setModalState(() {});
    }
  }

  Future<void> _handleRefresh() async {
    AppDebug.log("LOGIN", "Refresh guest storefront");
    ref.invalidate(product_providers.productsProvider);
    await ref.read(product_providers.productsProvider.future);
  }

  void _setLoading(
    bool value, {
    void Function(void Function())? setModalState,
  }) {
    if (mounted) {
      setState(() => _isLoading = value);
    }
    if (setModalState != null) {
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

  String _formatAccountLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    return trimmed
        .split('_')
        .where((segment) => segment.trim().isNotEmpty)
        .map(
          (segment) =>
              segment[0].toUpperCase() + segment.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  void _togglePasswordVisibility({
    required void Function(void Function()) setModalState,
  }) {
    final selection = _passwordCtrl.selection;
    setState(() => _showPassword = !_showPassword);
    setModalState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final fallbackSelection = TextSelection.collapsed(
        offset: _passwordCtrl.text.length,
      );
      _passwordCtrl.selection = selection.isValid
          ? selection
          : fallbackSelection;
    });
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

  Future<void> _onLoginPressed({
    void Function(void Function())? setModalState,
  }) async {
    if (_isLoading) {
      AppDebug.log("LOGIN", "Ignored tap because _isLoading=true");
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

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

    final api = ref.read(authApiProvider);
    final storage = ref.read(authSessionStorageProvider);

    try {
      AppDebug.log("LOGIN", "Starting login()", extra: {"email": email});

      final session = await api.login(email: email, password: password);

      AppDebug.log(
        "LOGIN",
        "Login success",
        extra: {"userId": session.user.id},
      );

      await storage.saveLastCredentials(email: email, password: password);
      _storedCredentials = _storedCredentials.withSavedPassword(
        email: email,
        password: password,
      );
      TextInput.finishAutofillContext(shouldSave: true);
      await ref.read(authSessionProvider.notifier).setSession(session);

      final rawRedirect = widget.redirectTo;
      final decodedRedirect = rawRedirect == null || rawRedirect.trim().isEmpty
          ? null
          : Uri.decodeComponent(rawRedirect.trim());
      String? redirectTarget =
          decodedRedirect != null && decodedRedirect.startsWith('/')
          ? decodedRedirect
          : null;

      if (redirectTarget == null) {
        final pendingInvite = await storage.readPendingInviteToken();
        if (pendingInvite != null && pendingInvite.trim().isNotEmpty) {
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

      if (!mounted) {
        return;
      }

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
        Navigator.of(context).pop();
      }
      context.go(redirectTarget ?? '/home');
    } catch (e) {
      AppDebug.log("LOGIN", "Login failed", extra: {"error": e.toString()});
      _setLoading(false, setModalState: setModalState);
      _setLoginError(_friendlyLoginErrorText(e), setModalState: setModalState);
    }
  }

  void _openSignInSheet() {
    AppDebug.log("LOGIN", "Open sign-in sheet");
    _setLoginError(null);
    _maybeApplyStoredPassword(
      email: _emailCtrl.text,
      overwrite: _passwordCtrl.text.isEmpty,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0),
      builder: (sheetContext) {
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
    final shortcutBundleFuture = _primeLoginAccountsFuture(
      _selectedShortcutRole,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 860),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  "Sign in to continue checkout",
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Browse in guest mode, then sign back into the right workspace with your email and password.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                AppSectionCard(
                  tone: AppPanelTone.hero,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppIconBadge(
                            icon: _selectedShortcutRole.icon,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Choose account",
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  "Pick a role, then tap any real account from MongoDB to fill the email field. If this device already remembers that password, it will be applied automatically.",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 640;
                          final buttons = _LoginShortcutRole.values
                              .map(
                                (role) => SizedBox(
                                  width: isCompact
                                      ? constraints.maxWidth
                                      : (constraints.maxWidth -
                                                AppSpacing.md * 2) /
                                            3,
                                  child: _buildShortcutRoleButton(
                                    context: context,
                                    role: role,
                                    setModalState: setModalState,
                                  ),
                                ),
                              )
                              .toList();

                          return Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.md,
                            children: buttons,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _buildShortcutAccountsSection(
                        context: sheetContext,
                        shortcutBundleFuture: shortcutBundleFuture,
                        setModalState: setModalState,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (value) {
                    _setLoginError(null, setModalState: setModalState);
                    _maybeApplyStoredPassword(
                      email: value,
                      overwrite: _passwordCtrl.text.isEmpty,
                      setModalState: setModalState,
                    );
                  },
                  decoration: const InputDecoration(labelText: "Email"),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: ValueKey(
                    'login-password-field-${_showPassword ? "visible" : "hidden"}',
                  ),
                  controller: _passwordCtrl,
                  keyboardType: TextInputType.visiblePassword,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) =>
                      _onLoginPressed(setModalState: setModalState),
                  onChanged: (_) =>
                      _setLoginError(null, setModalState: setModalState),
                  decoration: InputDecoration(
                    labelText: "Password",
                    helperText:
                        _storedCredentials.passwordFor(_emailCtrl.text) != null
                        ? "Saved password available for this email on this device."
                        : "Tap an account above to fill your email faster.",
                    suffixIcon: IconButton(
                      onPressed: () {
                        AppDebug.log("LOGIN", "Toggle password visibility");
                        _togglePasswordVisibility(setModalState: setModalState);
                      },
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 520;
                    final actions = [
                      TextButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _goToForgotPassword(sheetContext),
                        icon: const Icon(Icons.key_outlined, size: 16),
                        label: const Text("Forgot password?"),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                AppDebug.log("LOGIN", "Go Register tapped");
                                Navigator.of(sheetContext).pop();
                                context.go("/register");
                              },
                        child: const Text("Create account"),
                      ),
                    ];

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: actions
                            .map(
                              (action) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: action,
                              ),
                            )
                            .toList(),
                      );
                    }

                    return Row(
                      children: [actions.first, const Spacer(), actions.last],
                    );
                  },
                ),
                _buildLoginErrorCard(sheetContext),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading
                        ? null
                        : () => _onLoginPressed(setModalState: setModalState),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                    ),
                    child: Text(_isLoading ? "Signing in..." : "Sign in"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutRoleButton({
    required BuildContext context,
    required _LoginShortcutRole role,
    required void Function(void Function()) setModalState,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected = _selectedShortcutRole == role;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () {
          if (_selectedShortcutRole == role) {
            return;
          }
          setState(() => _selectedShortcutRole = role);
          _primeLoginAccountsFuture(role);
          setModalState(() {});
        },
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                role.icon,
                size: 18,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? scheme.primary
                            : theme.textTheme.labelLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      role.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutAccountsSection({
    required BuildContext context,
    required Future<LoginShortcutBundle> shortcutBundleFuture,
    required void Function(void Function()) setModalState,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<LoginShortcutBundle>(
      future: shortcutBundleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.connectionState == ConnectionState.active) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Loading ${_selectedShortcutRole.label.toLowerCase()} accounts...",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(minHeight: 3),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _friendlyLoginErrorText(snapshot.error!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => _refreshLoginAccountsFuture(
                    _selectedShortcutRole,
                    setModalState: setModalState,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text("Retry"),
                ),
              ],
            ),
          );
        }

        final bundle = snapshot.data;
        if (bundle == null) {
          return const SizedBox.shrink();
        }

        final savedPasswordCount = bundle.accounts
            .where(
              (account) =>
                  _storedCredentials.passwordFor(account.email) != null,
            )
            .length;
        final verifiedCount = bundle.accounts
            .where((account) => account.isFullyVerified)
            .length;

        if (bundle.accounts.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              "No ${_selectedShortcutRole.label.toLowerCase()} accounts are available right now.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppStatusChip(
                  label: "${bundle.accounts.length} accounts",
                  tone: AppStatusTone.info,
                  icon: Icons.groups_rounded,
                ),
                AppStatusChip(
                  label: savedPasswordCount > 0
                      ? "$savedPasswordCount saved on this device"
                      : "No saved passwords yet",
                  tone: savedPasswordCount > 0
                      ? AppStatusTone.success
                      : AppStatusTone.warning,
                  icon: savedPasswordCount > 0
                      ? Icons.lock_person_rounded
                      : Icons.password_rounded,
                ),
                AppStatusChip(
                  label: verifiedCount > 0
                      ? "$verifiedCount verified"
                      : "No verified accounts yet",
                  tone: verifiedCount > 0
                      ? AppStatusTone.success
                      : AppStatusTone.warning,
                  icon: verifiedCount > 0
                      ? Icons.verified_rounded
                      : Icons.pending_outlined,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 680 ? 2 : 1;
                final gap = AppSpacing.md;
                final width = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - gap) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: bundle.accounts
                      .map(
                        (account) => SizedBox(
                          width: width,
                          child: _buildShortcutAccountCard(
                            context: context,
                            account: account,
                            setModalState: setModalState,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildShortcutAccountCard({
    required BuildContext context,
    required LoginShortcutAccount account,
    required void Function(void Function()) setModalState,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected =
        _emailCtrl.text.trim().toLowerCase() == account.email.toLowerCase();
    final password = _resolveShortcutPassword(account);
    final hasPassword = (password ?? "").isNotEmpty;
    final accountRoleLabel = _formatAccountLabel(
      (account.staffRole ?? '').isNotEmpty ? account.staffRole! : account.role,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _applyLoginShortcut(account, setModalState: setModalState),
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      account.fullName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle_rounded, color: scheme.primary),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                account.email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "ID: ${account.id}",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if ((account.subtitle ?? "").isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  account.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if ((account.addressLabel ?? "").isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        account.addressLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppStatusChip(
                    label: accountRoleLabel,
                    tone: AppStatusTone.info,
                    icon: (account.staffRole ?? '').isNotEmpty
                        ? Icons.badge_rounded
                        : _selectedShortcutRole.icon,
                  ),
                  AppStatusChip(
                    label: account.isFullyVerified
                        ? "Verified"
                        : "Verification pending",
                    tone: account.isFullyVerified
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                    icon: account.isFullyVerified
                        ? Icons.verified_rounded
                        : Icons.pending_outlined,
                  ),
                  AppStatusChip(
                    label: hasPassword ? "Saved on device" : "Enter password",
                    tone: hasPassword
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                    icon: hasPassword
                        ? Icons.password_rounded
                        : Icons.edit_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptGuestSignIn({required String source}) {
    AppDebug.log(
      "LOGIN",
      "Guest action requires sign-in",
      extra: {"source": source},
    );
    _openSignInSheet();
  }

  void _openProduct(Product product) {
    AppDebug.log(
      "LOGIN",
      "Navigate -> /product/:id",
      extra: {"id": product.id},
    );
    context.go('/product/${product.id}');
  }

  void _updateQuery(String value) {
    setState(() => _pendingQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() => _activeQuery = value.trim());
    });
  }

  void _toggleCategory(String label) {
    final normalized = label.trim();
    setState(() {
      final isSameCategory =
          (_selectedCategory ?? "").toLowerCase() == normalized.toLowerCase();
      _selectedCategory = normalized.isEmpty || isSameCategory
          ? null
          : normalized;
      _selectedSubcategory = null;
    });
  }

  void _toggleSubcategory(StorefrontCategorySummary summary) {
    setState(() {
      final isSameSubcategory =
          (_selectedSubcategory ?? "").trim().toLowerCase() ==
          summary.label.trim().toLowerCase();
      _selectedSubcategory = isSameSubcategory ? null : summary.label;
      if (!isSameSubcategory &&
          (summary.parentCategory ?? "").trim().isNotEmpty) {
        _selectedCategory = summary.parentCategory!.trim();
      }
    });
  }

  void _toggleFavorite(Product product) {
    setState(() {
      if (_favoriteIds.contains(product.id)) {
        _favoriteIds = {..._favoriteIds}..remove(product.id);
      } else {
        _favoriteIds = {..._favoriteIds, product.id};
      }
    });
  }

  void _clearDiscovery() {
    setState(() {
      _pendingQuery = "";
      _activeQuery = "";
      _selectedCategory = null;
      _selectedSubcategory = null;
      _inStockOnly = false;
      _sort = ProductSort.none;
      _searchController.clear();
    });
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<HomeFilterOptions>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => HomeFilterSheet(
        initial: HomeFilterOptions(inStockOnly: _inStockOnly, sort: _sort),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _inStockOnly = result.inStockOnly;
      _sort = result.sort;
    });
  }

  Future<void> _scrollToKey(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) {
      return;
    }

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Widget _buildGuestAccessCard({
    required List<Product> products,
    required List<StorefrontCategorySummary> categories,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inStockCount = products.where((product) => product.stock > 0).length;

    return AppSectionCard(
      tone: AppPanelTone.muted,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 860;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIconBadge(
                    icon: Icons.lock_open_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      "Guest storefront access",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                "Browse the same catalog structure as the home page, open product details, and sign in when you are ready to add items to cart and checkout.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppStatusChip(
                    label: "${products.length} products",
                    tone: AppStatusTone.info,
                    icon: Icons.inventory_2_rounded,
                  ),
                  AppStatusChip(
                    label: "${categories.length} categories",
                    tone: AppStatusTone.success,
                    icon: Icons.category_rounded,
                  ),
                  AppStatusChip(
                    label: "$inStockCount in stock",
                    tone: AppStatusTone.success,
                    icon: Icons.local_shipping_rounded,
                  ),
                  const AppStatusChip(
                    label: "Checkout locked",
                    tone: AppStatusTone.warning,
                    icon: Icons.lock_outline_rounded,
                  ),
                ],
              ),
            ],
          );

          final actions = isCompact
              ? Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _promptGuestSignIn(
                                source: "guest_access_primary",
                              ),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text("Sign in"),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.go("/register"),
                        child: const Text("Create account"),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(
                      width: 184,
                      child: FilledButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _promptGuestSignIn(
                                source: "guest_access_primary",
                              ),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text("Sign in"),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: 184,
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.go("/register"),
                        child: const Text("Create account"),
                      ),
                    ),
                  ],
                );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                summary,
                const SizedBox(height: AppSpacing.lg),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: summary),
              const SizedBox(width: AppSpacing.xl),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoadedState({
    required BuildContext context,
    required List<Product> products,
  }) {
    if (products.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: AppResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.section,
            AppSpacing.page,
            AppSpacing.section,
          ),
          child: AppEmptyState(
            icon: Icons.shopping_bag_outlined,
            title: "No products available yet",
            message:
                "The storefront is ready, but there are no active products to browse in guest mode right now.",
            action: OutlinedButton(
              onPressed: _handleRefresh,
              child: const Text("Refresh"),
            ),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final categorySummaries = _buildCategorySummaries(
      products: products,
      colorScheme: colorScheme,
    );
    final subcategorySummaries = _buildSubcategorySummaries(
      products: products,
      colorScheme: colorScheme,
      categoryLabel: _selectedCategory,
    );
    final filteredProducts = _applyFilters(products);
    final hasSearchIntent = _activeQuery.isNotEmpty || _hasFilters;

    final featuredProducts = [...products]..sort(_compareFeaturedProducts);
    final newArrivals = [...products]..sort(_sortNewest);
    final popularProducts = [...products]..sort(_scoreByDemand);
    final deals = products.where((product) => product.hasDiscount).toList()
      ..sort(_compareFeaturedProducts);
    final highlightedCategory = categorySummaries.isNotEmpty
        ? categorySummaries.first.label
        : null;
    final heroMetrics = _buildHeroMetrics(
      products: products,
      categories: categorySummaries,
    );
    final quickCategories = categorySummaries
        .take(4)
        .map((item) => item.label)
        .toList();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeHeroSection(
            topLabel: "Storefront",
            catalogLabel: _buildCatalogLabel(categorySummaries),
            headline: "Browse the store before you sign in",
            subtitle: _buildGuestHeroSubtitle(
              products: products,
              categories: categorySummaries,
            ),
            promoEyebrow: highlightedCategory ?? "Guest access",
            promoTitle: highlightedCategory == null
                ? "Preview the latest collection"
                : "Preview $highlightedCategory",
            promoBody:
                "Search, filter, and explore the full catalog now. Sign in only when you are ready to add items and checkout.",
            primaryLabel: "Browse products",
            secondaryLabel: "Browse categories",
            promoLabel: highlightedCategory == null
                ? "See all categories"
                : "Shop $highlightedCategory",
            cartBadgeCount: 0,
            metrics: heroMetrics,
            onCartTap: () => _promptGuestSignIn(source: "hero_cart"),
            onPrimaryTap: () => _scrollToKey(_featuredKey),
            onSecondaryTap: () => _scrollToKey(_categoriesKey),
            onPromoTap: highlightedCategory == null
                ? () => _scrollToKey(_categoriesKey)
                : () => _toggleCategory(highlightedCategory),
          ),
          AppResponsiveContent(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuestAccessCard(
                  products: products,
                  categories: categorySummaries,
                ),
                const SizedBox(height: AppSpacing.section),
                HomeSearchSection(
                  controller: _searchController,
                  onFilterTap: _openFilterSheet,
                  onSearchChanged: _updateQuery,
                  onSearchSubmitted: _updateQuery,
                  hasActiveFilters: _hasFilters,
                  quickCategories: quickCategories,
                  selectedCategory: _selectedCategory,
                  onCategorySelected: _toggleCategory,
                ),
                if (_pendingQuery.trim().isNotEmpty &&
                    _pendingQuery.trim() != _activeQuery) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Searching products...",
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (hasSearchIntent) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (_activeQuery.isNotEmpty)
                        AppStatusChip(
                          label: 'Search: "$_activeQuery"',
                          tone: AppStatusTone.info,
                          icon: Icons.search_rounded,
                        ),
                      if (_selectedCategory != null)
                        AppStatusChip(
                          label: _selectedCategory!,
                          tone: AppStatusTone.warning,
                          icon: Icons.category_rounded,
                        ),
                      if (_selectedSubcategory != null)
                        AppStatusChip(
                          label: _selectedSubcategory!,
                          tone: AppStatusTone.info,
                          icon: Icons.sell_rounded,
                        ),
                      if (_inStockOnly)
                        const AppStatusChip(
                          label: "In stock only",
                          tone: AppStatusTone.success,
                          icon: Icons.inventory_2_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _clearDiscovery,
                    child: const Text("Clear search and filters"),
                  ),
                ],
                const SizedBox(height: AppSpacing.section),
                KeyedSubtree(
                  key: _categoriesKey,
                  child: HomeCategoriesSection(
                    categories: categorySummaries,
                    subcategories: subcategorySummaries,
                    selectedCategory: _selectedCategory,
                    selectedSubcategory: _selectedSubcategory,
                    onCategoryTap: _toggleCategory,
                    onSubcategoryTap: _toggleSubcategory,
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                if (hasSearchIntent) ...[
                  if (filteredProducts.isEmpty)
                    AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: "No products matched",
                      message:
                          "Try a different search term, switch category, or reset your filters.",
                      action: OutlinedButton(
                        onPressed: _clearDiscovery,
                        child: const Text("Reset filters"),
                      ),
                    )
                  else
                    HomeSearchResultsSection(
                      title: _activeQuery.isNotEmpty
                          ? 'Results for "$_activeQuery"'
                          : _selectedSubcategory != null
                          ? "${_selectedSubcategory!} products"
                          : _selectedCategory != null
                          ? "${_selectedCategory!} products"
                          : "Filtered products",
                      subtitle:
                          "Browse matching products in guest mode, then sign in when you are ready to add items to cart.",
                      results: filteredProducts,
                      onProductTap: _openProduct,
                      onPrimaryAction: (_) =>
                          _promptGuestSignIn(source: "search_results_primary"),
                      onFavoriteToggle: _toggleFavorite,
                      favoriteIds: _favoriteIds,
                    ),
                ] else ...[
                  KeyedSubtree(
                    key: _featuredKey,
                    child: HomeProductSection(
                      title: "Featured products",
                      subtitle:
                          "Start with standout picks chosen for availability, imagery, and freshness.",
                      products: featuredProducts,
                      featuredCards: true,
                      favoriteIds: _favoriteIds,
                      onProductTap: _openProduct,
                      onPrimaryAction: (_) =>
                          _promptGuestSignIn(source: "featured_primary"),
                      onFavoriteToggle: _toggleFavorite,
                      onSeeAllTap: () => _scrollToKey(_categoriesKey),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  HomePromoSection(
                    eyebrow: highlightedCategory ?? "Guest storefront",
                    title: "Preview the catalog, then unlock checkout",
                    subtitle:
                        "Explore the same discovery experience as the home page and sign in only when you are ready to buy.",
                    primaryLabel: "Sign in to continue",
                    onPrimaryTap: () =>
                        _promptGuestSignIn(source: "promo_primary"),
                    highlights: _buildGuestPromoHighlights(
                      products,
                      categorySummaries,
                    ),
                  ),
                  if (newArrivals.length > 1) ...[
                    const SizedBox(height: AppSpacing.section),
                    HomeProductSection(
                      title: "New arrivals",
                      subtitle:
                          "Recently added products, ordered by the latest arrivals in the store.",
                      products: newArrivals,
                      favoriteIds: _favoriteIds,
                      onProductTap: _openProduct,
                      onPrimaryAction: (_) =>
                          _promptGuestSignIn(source: "new_arrivals_primary"),
                      onFavoriteToggle: _toggleFavorite,
                    ),
                  ],
                  if (popularProducts.length > 1) ...[
                    const SizedBox(height: AppSpacing.section),
                    HomeProductSection(
                      title: "Popular right now",
                      subtitle:
                          "Popular picks based on availability, freshness, and complete product details.",
                      products: popularProducts,
                      favoriteIds: _favoriteIds,
                      onProductTap: _openProduct,
                      onPrimaryAction: (_) =>
                          _promptGuestSignIn(source: "popular_primary"),
                      onFavoriteToggle: _toggleFavorite,
                    ),
                  ],
                  if (deals.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    HomeProductSection(
                      title: "Deals",
                      subtitle:
                          "Products with discount pricing available in the storefront right now.",
                      products: deals,
                      favoriteIds: _favoriteIds,
                      onProductTap: _openProduct,
                      onPrimaryAction: (_) =>
                          _promptGuestSignIn(source: "deals_primary"),
                      onFavoriteToggle: _toggleFavorite,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Product> _applyFilters(List<Product> products) {
    final query = _activeQuery.trim().toLowerCase();
    final selectedCategory = (_selectedCategory ?? "").trim().toLowerCase();
    final selectedSubcategory = (_selectedSubcategory ?? "")
        .trim()
        .toLowerCase();

    final filtered = products.where((product) {
      if (_inStockOnly && product.stock <= 0) {
        return false;
      }

      if (selectedCategory.isNotEmpty &&
          product.category.trim().toLowerCase() != selectedCategory) {
        return false;
      }

      if (selectedSubcategory.isNotEmpty &&
          product.subcategory.trim().toLowerCase() != selectedSubcategory) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = [
        product.name,
        product.description,
        product.longDescription,
        product.category,
        product.subcategory,
        product.brand,
      ].join(" ").toLowerCase();

      return haystack.contains(query);
    }).toList();

    filtered.sort(_compareBySort);
    return filtered;
  }

  int _compareBySort(Product left, Product right) {
    switch (_sort) {
      case ProductSort.newest:
        return _sortNewest(left, right);
      case ProductSort.priceLowHigh:
        return left.priceCents.compareTo(right.priceCents);
      case ProductSort.priceHighLow:
        return right.priceCents.compareTo(left.priceCents);
      case ProductSort.nameAZ:
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      case ProductSort.nameZA:
        return right.name.toLowerCase().compareTo(left.name.toLowerCase());
      case ProductSort.none:
        return _compareFeaturedProducts(left, right);
    }
  }

  int _compareFeaturedProducts(Product left, Product right) {
    final leftScore = _featuredScore(left);
    final rightScore = _featuredScore(right);
    if (leftScore != rightScore) {
      return rightScore.compareTo(leftScore);
    }
    return _sortNewest(left, right);
  }

  int _featuredScore(Product product) {
    var score = 0;
    if (product.primaryImageUrl.trim().isNotEmpty) {
      score += 10;
    }
    if (product.stock > 0) {
      score += 8;
    }
    if (product.preorderEnabled) {
      score += 3;
    }
    if (product.hasDiscount) {
      score += 2;
    }
    score += product.stock.clamp(0, 50);
    final createdAt = product.createdAt;
    if (createdAt != null) {
      final freshness = 30 - DateTime.now().difference(createdAt).inDays;
      score += freshness.clamp(0, 30);
    }
    return score;
  }

  int _sortNewest(Product left, Product right) {
    final leftDate =
        left.updatedAt ??
        left.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate =
        right.updatedAt ??
        right.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return rightDate.compareTo(leftDate);
  }

  int _scoreByDemand(Product left, Product right) {
    final leftScore = _demandScore(left);
    final rightScore = _demandScore(right);
    if (leftScore != rightScore) {
      return rightScore.compareTo(leftScore);
    }
    return _sortNewest(left, right);
  }

  int _demandScore(Product product) {
    var score = 0;
    if (product.stock > 0) {
      score += 6;
    }
    if (product.primaryImageUrl.trim().isNotEmpty) {
      score += 4;
    }
    if (product.preorderEnabled) {
      score += 2;
    }
    score += product.stock.clamp(0, 40);
    final updatedAt =
        product.updatedAt ??
        product.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    score += (30 - DateTime.now().difference(updatedAt).inDays).clamp(0, 30);
    return score;
  }

  List<StorefrontCategorySummary> _buildCategorySummaries({
    required List<Product> products,
    required ColorScheme colorScheme,
  }) {
    final grouped = <String, List<Product>>{};

    for (final product in products) {
      final label = product.category.trim();
      if (label.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(label, () => []).add(product);
    }

    final summaries = <StorefrontCategorySummary>[];
    for (final entry in grouped.entries) {
      final label = entry.key;
      final items = entry.value;
      final helper = _buildCategoryHelper(items);
      summaries.add(
        StorefrontCategorySummary(
          label: label,
          helper: helper,
          itemCount: items.length,
          icon: _iconForCategory(label, helper),
          accent: _accentForCategory(label, colorScheme),
        ),
      );
    }

    summaries.sort((left, right) => right.itemCount.compareTo(left.itemCount));
    return summaries;
  }

  List<StorefrontCategorySummary> _buildSubcategorySummaries({
    required List<Product> products,
    required ColorScheme colorScheme,
    required String? categoryLabel,
  }) {
    final grouped = <String, List<Product>>{};
    final parentBySubcategory = <String, String>{};
    final normalizedCategory = (categoryLabel ?? "").trim().toLowerCase();

    for (final product in products) {
      final parentCategory = product.category.trim();
      final subcategory = product.subcategory.trim();
      if (subcategory.isEmpty) {
        continue;
      }
      if (normalizedCategory.isNotEmpty &&
          parentCategory.toLowerCase() != normalizedCategory) {
        continue;
      }

      grouped.putIfAbsent(subcategory, () => []).add(product);
      parentBySubcategory.putIfAbsent(subcategory, () => parentCategory);
    }

    final summaries = <StorefrontCategorySummary>[];
    for (final entry in grouped.entries) {
      final label = entry.key;
      final items = entry.value;
      final parentCategory = parentBySubcategory[label];
      summaries.add(
        StorefrontCategorySummary(
          label: label,
          helper: parentCategory ?? "",
          itemCount: items.length,
          icon: _iconForCategory(parentCategory ?? label, label),
          accent: _accentForCategory(parentCategory ?? label, colorScheme),
          parentCategory: parentCategory,
        ),
      );
    }

    summaries.sort((left, right) {
      final countCompare = right.itemCount.compareTo(left.itemCount);
      if (countCompare != 0) {
        return countCompare;
      }
      return left.label.toLowerCase().compareTo(right.label.toLowerCase());
    });
    return summaries;
  }

  String _buildCategoryHelper(List<Product> products) {
    final subcategoryCounts = <String, int>{};
    final brandCounts = <String, int>{};

    for (final product in products) {
      final subcategory = product.subcategory.trim();
      final brand = product.brand.trim();
      if (subcategory.isNotEmpty) {
        subcategoryCounts.update(
          subcategory,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      if (brand.isNotEmpty) {
        brandCounts.update(brand, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    if (subcategoryCounts.isNotEmpty) {
      final topSubcategories = subcategoryCounts.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
      return topSubcategories.take(2).map((entry) => entry.key).join(" • ");
    }

    if (brandCounts.isNotEmpty) {
      final topBrands = brandCounts.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
      return topBrands.take(2).map((entry) => entry.key).join(" • ");
    }

    return products.length == 1
        ? "1 active product"
        : "${products.length} active products";
  }

  String _buildCatalogLabel(List<StorefrontCategorySummary> categories) {
    if (categories.isEmpty) {
      return "In store";
    }
    return categories.take(2).map((item) => item.label).join(" • ");
  }

  List<HomeHeroMetric> _buildHeroMetrics({
    required List<Product> products,
    required List<StorefrontCategorySummary> categories,
  }) {
    final inStockCount = products.where((product) => product.stock > 0).length;
    final brandCount = products
        .map((product) => product.brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .length;

    final metrics = <HomeHeroMetric>[
      HomeHeroMetric(
        label: "products",
        value: "${products.length}",
        icon: Icons.inventory_2_rounded,
      ),
      HomeHeroMetric(
        label: "categories",
        value: "${categories.length}",
        icon: Icons.category_rounded,
      ),
      HomeHeroMetric(
        label: "available now",
        value: "$inStockCount",
        icon: Icons.local_shipping_rounded,
      ),
    ];

    if (brandCount > 0) {
      metrics.insert(
        2,
        HomeHeroMetric(
          label: brandCount == 1 ? "brand" : "brands",
          value: "$brandCount",
          icon: Icons.sell_rounded,
        ),
      );
    }

    return metrics;
  }

  String _buildGuestHeroSubtitle({
    required List<Product> products,
    required List<StorefrontCategorySummary> categories,
  }) {
    if (categories.isEmpty) {
      return "Browse the latest products, filter the catalog, and open product details before signing in.";
    }

    final topBrands = products
        .map((product) => product.brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .take(2)
        .toList();
    final brandText = topBrands.isEmpty ? "the store" : topBrands.join(" and ");

    if (categories.length == 1) {
      return "Browse ${categories.first.label} products from $brandText, compare what is available, and open product details before signing in.";
    }

    return "Browse ${categories.first.label} and ${categories[1].label}, discover products from $brandText, and preview the catalog before you sign in.";
  }

  List<String> _buildGuestPromoHighlights(
    List<Product> products,
    List<StorefrontCategorySummary> categories,
  ) {
    final highlights = <String>[
      "Browse the full storefront and open product details in guest mode",
    ];

    if (categories.isNotEmpty) {
      highlights.add(
        "${categories.length} categories ready for quick browsing",
      );
    }

    final brands = products
        .map((product) => product.brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .toList();
    if (brands.isNotEmpty) {
      highlights.add(
        brands.length == 1
            ? "Browse products from ${brands.first}"
            : "Shop across ${brands.length} active brands",
      );
    }

    final inStockCount = products.where((product) => product.stock > 0).length;
    highlights.add(
      inStockCount == 1
          ? "1 product currently in stock"
          : "$inStockCount products currently in stock",
    );

    return highlights.take(3).toList();
  }

  IconData _iconForCategory(String label, String helper) {
    final normalized = "$label $helper".toLowerCase();
    if (normalized.contains("foot") ||
        normalized.contains("shoe") ||
        normalized.contains("sneaker")) {
      return Icons.hiking_rounded;
    }
    if (normalized.contains("farm") || normalized.contains("agro")) {
      return Icons.agriculture_rounded;
    }
    if (normalized.contains("kitchen") || normalized.contains("home")) {
      return Icons.kitchen_rounded;
    }
    if (normalized.contains("grain") || normalized.contains("cereal")) {
      return Icons.rice_bowl_rounded;
    }
    if (normalized.contains("vegetable")) {
      return Icons.eco_rounded;
    }
    return Icons.category_rounded;
  }

  Color _accentForCategory(String label, ColorScheme colorScheme) {
    final normalized = label.toLowerCase();
    if (normalized.contains("farm") || normalized.contains("agro")) {
      return colorScheme.secondary;
    }
    if (normalized.contains("home") || normalized.contains("kitchen")) {
      return colorScheme.tertiary;
    }
    return colorScheme.primary;
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: AppResponsiveContent(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.section,
          AppSpacing.page,
          AppSpacing.section,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LoadingBlock(height: 260, radius: AppRadius.xl),
            const SizedBox(height: AppSpacing.section),
            const _LoadingBlock(height: 152, radius: AppRadius.xl),
            const SizedBox(height: AppSpacing.section),
            const _LoadingBlock(height: 108, radius: AppRadius.xl),
            const SizedBox(height: AppSpacing.section),
            SizedBox(
              height: 430,
              child: Row(
                children: const [
                  Expanded(
                    child: _LoadingBlock(height: 430, radius: AppRadius.xl),
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _LoadingBlock(height: 430, radius: AppRadius.xl),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    AppDebug.log(
      "LOGIN",
      "Products load failed",
      extra: {"error": error.toString()},
    );

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: AppResponsiveContent(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.section,
          AppSpacing.page,
          AppSpacing.section,
        ),
        child: AppEmptyState(
          icon: Icons.storefront_outlined,
          title: "Storefront unavailable",
          message:
              "We could not load the latest products right now. Pull to refresh and try again.",
          action: OutlinedButton(
            onPressed: _handleRefresh,
            child: const Text("Refresh"),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("LOGIN", "build()", extra: {"isLoading": _isLoading});
    final productsAsync = ref.watch(product_providers.productsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: productsAsync.when(
            data: (products) {
              AppDebug.log(
                "LOGIN",
                "Products ready",
                extra: {"count": products.length},
              );
              return _buildLoadedState(context: context, products: products);
            },
            loading: _buildLoadingState,
            error: (error, _) => _buildErrorState(error),
          ),
        ),
      ),
    );
  }
}

enum _LoginShortcutRole { user, businessOwner, tenant, staff, admin }

extension on _LoginShortcutRole {
  String get apiRole => switch (this) {
    _LoginShortcutRole.user => 'customer',
    _LoginShortcutRole.businessOwner => 'business_owner',
    _LoginShortcutRole.tenant => 'tenant',
    _LoginShortcutRole.staff => 'staff',
    _LoginShortcutRole.admin => 'admin',
  };

  String get label => switch (this) {
    _LoginShortcutRole.user => 'User',
    _LoginShortcutRole.businessOwner => 'Business owner',
    _LoginShortcutRole.tenant => 'Tenant',
    _LoginShortcutRole.staff => 'Staff',
    _LoginShortcutRole.admin => 'Admin',
  };

  String get description => switch (this) {
    _LoginShortcutRole.user => 'Customers and shoppers',
    _LoginShortcutRole.businessOwner => 'Owners and operators',
    _LoginShortcutRole.tenant => 'Residents and lease customers',
    _LoginShortcutRole.staff => 'Team members and field staff',
    _LoginShortcutRole.admin => 'Platform control account',
  };

  IconData get icon => switch (this) {
    _LoginShortcutRole.user => Icons.person_rounded,
    _LoginShortcutRole.businessOwner => Icons.storefront_rounded,
    _LoginShortcutRole.tenant => Icons.apartment_rounded,
    _LoginShortcutRole.staff => Icons.badge_rounded,
    _LoginShortcutRole.admin => Icons.admin_panel_settings_rounded,
  };
}

class _LoadingBlock extends StatelessWidget {
  final double height;
  final double radius;

  const _LoadingBlock({required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
