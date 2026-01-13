/// lib/app/features/auth/presentation/login_screen.dart
/// ---------------------------------------------------
/// WHAT THIS FILE IS:
/// - Login screen UI (Phase 3 = UI + real API call + navigation).
///
/// WHY IT'S IMPORTANT:
/// - This is the main entry screen.
/// - You want this flow:
///   ✅ Login success -> go to /home
///   ✅ Login failure -> show message + log error
///   ✅ User can still go to /register
///
/// HOW IT WORKS:
/// 1) User types email + password
/// 2) Tap "Login" -> call AuthApi.login() via authApiProvider
/// 3) Success -> navigate to /home
/// 4) Error -> snackbar
///
/// DEBUGGING STRATEGY:
/// - Logs show:
///   - build()
///   - button tapped
///   - API start
///   - success (userId only)
///   - failure (error only)
///
/// SAFETY:
/// - NEVER log password
/// - NEVER log token
/// - Always check context.mounted after await
///
/// MULTI-PLATFORM:
/// - Works on Web / Android / iOS (no dart:io usage here)
/// ---------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
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

  // ------------------------------------------------------------
  // LOADING FLAG
  // ------------------------------------------------------------
  // WHY:
  // - Prevent duplicate login requests from double taps.
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// ------------------------------------------------------------
  /// LOGIN HANDLER
  /// ------------------------------------------------------------
  Future<void> _onLoginPressed() async {
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

    setState(() => _isLoading = true);

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

      if (mounted) setState(() => _isLoading = false);

      if (!context.mounted) return;

      // ✅ Navigate to home after successful login
      context.go('/home');
    } catch (e) {
      AppDebug.log("LOGIN", "Login failed", extra: {"error": e.toString()});

      if (mounted) setState(() => _isLoading = false);

      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Login failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("LOGIN", "build()", extra: {"isLoading": _isLoading});

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Login"),
                const SizedBox(height: 12),

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

                ElevatedButton(
                  onPressed: _isLoading ? null : _onLoginPressed,
                  child: Text(_isLoading ? "Logging in..." : "Login"),
                ),

                const SizedBox(height: 8),

                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          AppDebug.log("LOGIN", "Go Register tapped");
                          context.go("/register");
                        },
                  child: const Text("Go Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
