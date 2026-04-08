/// lib/app/features/home/presentation/presentation/forgot_password_screen.dart
/// --------------------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Public forgot-password screen for requesting a reset code and setting a new password.
///
/// WHY IT'S IMPORTANT:
/// - Users need a recovery path when they cannot remember their password.
/// - Keeps reset work outside authenticated settings, so locked-out users can recover access.
///
/// HOW IT WORKS:
/// 1) User enters an email and requests a reset code.
/// 2) Screen reveals the code + new password form.
/// 3) User confirms the code and new password.
/// 4) Screen shows success and links back to sign-in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:go_router/go_router.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isRequesting = false;
  bool _isConfirming = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _hasRequestedCode = false;
  bool _isResetComplete = false;
  String _statusMessage = "";
  DateTime? _expiresAt;
  String? _debugCode;

  @override
  void initState() {
    super.initState();
    final initialEmail = (widget.initialEmail ?? "").trim();
    if (initialEmail.isNotEmpty) {
      // WHY: Preserve the email carried from the login sheet or query string.
      _emailCtrl.text = initialEmail;
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Prefilled email from route",
        extra: {"hasEmail": true},
      );
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestResetCode() async {
    if (_isRequesting || _isConfirming) {
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Ignored request tap because another action is running",
      );
      return;
    }

    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Request validation failed",
        extra: {"reason": "invalid_email"},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid email address")),
      );
      return;
    }

    setState(() => _isRequesting = true);
    final api = ref.read(authApiProvider);

    try {
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Request reset code start",
        extra: {"hasEmail": true},
      );

      final result = await api.requestPasswordReset(email: email);

      if (!mounted) return;

      setState(() {
        _isRequesting = false;
        _hasRequestedCode = true;
        _isResetComplete = false;
        _statusMessage = result.message;
        _expiresAt = result.expiresAt;
        _debugCode = result.debugCode;
      });

      AppDebug.log(
        "FORGOT_PASSWORD",
        "Request reset code success",
        extra: {
          "status": result.status,
          "hasExpiry": result.expiresAt != null,
          "hasDebugCode": result.debugCode != null,
        },
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } catch (error) {
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Request reset code failed",
        extra: {"error": error.toString()},
      );

      if (!mounted) return;

      setState(() => _isRequesting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyErrorText(error))));
    }
  }

  Future<void> _confirmReset() async {
    if (_isRequesting || _isConfirming) {
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Ignored confirm tap because another action is running",
      );
      return;
    }

    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    // WHY: Keep validation local so the user gets immediate guidance.
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid email address")),
      );
      return;
    }

    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Reset code is required")));
      return;
    }

    if (!_isValidPassword(newPassword)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password must be 8+ chars with upper, lower, number, and symbol",
          ),
        ),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
      return;
    }

    setState(() => _isConfirming = true);
    final api = ref.read(authApiProvider);

    try {
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Confirm reset start",
        extra: {"hasEmail": true, "hasCode": code.isNotEmpty},
      );

      final result = await api.confirmPasswordReset(
        email: email,
        code: code,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );

      if (!mounted) return;

      // WHY: Remember the email so the sign-in screen can prefill it later.
      await ref.read(authSessionStorageProvider).saveLastEmail(email);

      setState(() {
        _isConfirming = false;
        _isResetComplete = true;
        _statusMessage = result.message;
        _debugCode = null;
      });

      AppDebug.log(
        "FORGOT_PASSWORD",
        "Confirm reset success",
        extra: {"status": result.status},
      );
    } catch (error) {
      AppDebug.log(
        "FORGOT_PASSWORD",
        "Confirm reset failed",
        extra: {"error": error.toString()},
      );

      if (!mounted) return;

      setState(() => _isConfirming = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyErrorText(error))));
    }
  }

  String _friendlyErrorText(Object error) {
    final raw = error.toString().trim();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length).trim();
    }
    return raw;
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(email.trim());
  }

  bool _isValidPassword(String password) {
    final regex = RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$',
    );
    return regex.hasMatch(password);
  }

  String _expiryLabel(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_statusMessage.isEmpty && _debugCode == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isResetComplete ? "Password updated" : "Reset instructions sent",
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _statusMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
          if (_expiresAt != null && !_isResetComplete) ...[
            const SizedBox(height: 6),
            Text(
              "Code expires around ${_expiryLabel(_expiresAt!)}.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
          if (_debugCode != null &&
              _debugCode!.isNotEmpty &&
              !_isResetComplete) ...[
            const SizedBox(height: 10),
            Text(
              "Development code: $_debugCode",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletedState(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(context),
        const SizedBox(height: 16),
        Text(
          "Use your new password on the sign-in screen.",
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            AppDebug.log("FORGOT_PASSWORD", "Navigate -> /login");
            final encodedEmail = Uri.encodeQueryComponent(
              _emailCtrl.text.trim(),
            );
            context.go('/login?email=$encodedEmail');
          },
          child: const Text("Back to sign in"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "FORGOT_PASSWORD",
      "build()",
      extra: {
        "hasRequestedCode": _hasRequestedCode,
        "isResetComplete": _isResetComplete,
      },
    );

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Forgot password")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Reset your Office Store password",
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  "Enter your email to request a reset code. Then confirm the code with your new password.",
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email"),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isRequesting || _isConfirming
                      ? null
                      : _requestResetCode,
                  child: Text(
                    _isRequesting
                        ? "Sending code..."
                        : _hasRequestedCode
                        ? "Resend code"
                        : "Send reset code",
                  ),
                ),
                const SizedBox(height: 16),
                if (_isResetComplete)
                  _buildCompletedState(context)
                else ...[
                  _buildStatusCard(context),
                  if (_hasRequestedCode) ...[
                    const SizedBox(height: 20),
                    TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Reset code",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newPasswordCtrl,
                      obscureText: !_showNewPassword,
                      decoration: InputDecoration(
                        labelText: "New password",
                        suffixIcon: IconButton(
                          onPressed: () {
                            AppDebug.log(
                              "FORGOT_PASSWORD",
                              "Toggle new password visibility",
                            );
                            setState(
                              () => _showNewPassword = !_showNewPassword,
                            );
                          },
                          icon: Icon(
                            _showNewPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPasswordCtrl,
                      obscureText: !_showConfirmPassword,
                      decoration: InputDecoration(
                        labelText: "Confirm new password",
                        suffixIcon: IconButton(
                          onPressed: () {
                            AppDebug.log(
                              "FORGOT_PASSWORD",
                              "Toggle confirm password visibility",
                            );
                            setState(
                              () =>
                                  _showConfirmPassword = !_showConfirmPassword,
                            );
                          },
                          icon: Icon(
                            _showConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isRequesting || _isConfirming
                          ? null
                          : _confirmReset,
                      child: Text(
                        _isConfirming
                            ? "Updating password..."
                            : "Confirm reset",
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    AppDebug.log("FORGOT_PASSWORD", "Navigate -> /login");
                    final email = _emailCtrl.text.trim();
                    if (email.isEmpty) {
                      context.go('/login');
                      return;
                    }
                    final encodedEmail = Uri.encodeQueryComponent(email);
                    context.go('/login?email=$encodedEmail');
                  },
                  child: const Text("Back to sign in"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
