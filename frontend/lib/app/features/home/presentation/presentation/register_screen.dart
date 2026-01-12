/// lib/app/features/auth/presentation/register_screen.dart
/// ------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Register screen UI (Phase 3 = UI + real API call + navigation).
///
/// WHY IT'S IMPORTANT:
/// - You want this flow:
///   ✅ Register success -> show message -> go back to /login
///   ✅ Register failure -> show error message (and log where it failed)
///
/// HOW IT WORKS:
/// 1) User taps "Register"
/// 2) We call AuthApi.register() via Riverpod provider (authApiProvider)
/// 3) On success -> snackbar -> context.go('/login')
/// 4) On error -> snackbar -> log error (NO password logging)
///
/// DEBUGGING STRATEGY:
/// - Every important step logs to console with a consistent TAG ("REGISTER").
/// - We log:
///   - build()
///   - button tapped
///   - API call start
///   - success + userId
///   - failure + error string
///
/// MULTI-PLATFORM:
/// - Works on Web / Android / iOS (no dart:io usage here)
/// - Uses Riverpod provider access (ref.read)
///
/// SAFETY:
/// - NEVER log password
/// - Always check context.mounted after await before using context
/// ------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  // ------------------------------------------------------------
  // CONTROLLERS
  // ------------------------------------------------------------
  // WHY:
  // - We need to read what the user typed.
  // - We dispose them to avoid memory leaks.
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // ------------------------------------------------------------
  // LOADING FLAG
  // ------------------------------------------------------------
  // WHY:
  // - Prevents double taps / duplicate requests.
  // - Makes debugging easier (you know when the request started/ended).
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// ------------------------------------------------------------
  /// REGISTER HANDLER
  /// ------------------------------------------------------------
  /// This is the only place we do the async register action.
  /// We keep it in a method so the UI stays clean.
  Future<void> _onRegisterPressed() async {
    // Prevent double tap while request is already running
    if (_isLoading) {
      AppDebug.log("REGISTER", "Ignored tap because _isLoading=true");
      return;
    }

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    // ------------------------------------------------------------
    // BASIC VALIDATION (UI LEVEL)
    // ------------------------------------------------------------
    // WHY:
    // - Avoid hitting backend with empty fields.
    // - Gives user immediate feedback.
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      AppDebug.log("REGISTER", "Validation failed (empty field)");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("All fields are required")));
      return;
    }

    // ------------------------------------------------------------
    // START LOADING
    // ------------------------------------------------------------
    setState(() => _isLoading = true);

    // Read API from provider
    final api = ref.read(authApiProvider);

    try {
      // ✅ DO NOT LOG password
      AppDebug.log("REGISTER", "Starting register()", extra: {"email": email});

      final user = await api.register(
        name: name,
        email: email,
        password: password,
      );

      AppDebug.log("REGISTER", "Register success", extra: {"userId": user.id});

      // Always stop loading after await
      if (mounted) setState(() => _isLoading = false);

      // SAFETY: context can be disposed during await
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registration successful. Please login.")),
      );

      // ✅ IMPORTANT: Return user to sign-in after successful register
      context.go('/login');
    } catch (e) {
      AppDebug.log(
        "REGISTER",
        "Register failed",
        extra: {"error": e.toString()},
      );

      // Always stop loading after failure too
      if (mounted) setState(() => _isLoading = false);

      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Register failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("REGISTER", "build()", extra: {"isLoading": _isLoading});

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Register"),
                const SizedBox(height: 12),

                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: "Full name"),
                ),
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
                  onPressed: _isLoading ? null : _onRegisterPressed,
                  child: Text(_isLoading ? "Registering..." : "Register"),
                ),

                const SizedBox(height: 8),

                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          AppDebug.log("REGISTER", "Back to login tapped");
                          context.go("/login");
                        },
                  child: const Text("Back to login"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
