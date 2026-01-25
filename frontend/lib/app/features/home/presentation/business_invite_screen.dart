/// lib/app/features/home/presentation/business_invite_screen.dart
/// -------------------------------------------------------------
/// WHAT:
/// - Invite acceptance screen for business team links.
///
/// WHY:
/// - Lets customers accept Brevo invite links securely.
/// - Ensures the user is signed in before role upgrade.
///
/// HOW:
/// - Reads invite token from query params.
/// - Calls BusinessTeamApi.acceptInvite().
/// - Navigates to business dashboard on success.
/// - If not signed in, redirects to /login?next=... so invite resumes after auth.
///
/// DEBUGGING:
/// - Logs key lifecycle + actions (no secrets).
/// -------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_team_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class BusinessInviteScreen extends ConsumerStatefulWidget {
  final String token;

  const BusinessInviteScreen({super.key, required this.token});

  @override
  ConsumerState<BusinessInviteScreen> createState() =>
      _BusinessInviteScreenState();
}

class _BusinessInviteScreenState extends ConsumerState<BusinessInviteScreen> {
  bool _isSubmitting = false;
  String? _error;

  void _log(String message, {Map<String, dynamic>? extra}) {
    // WHY: Central, searchable logs to debug invite flow.
    // NOTE: Do NOT log tokens or passwords.
    AppDebug.log("BUSINESS_INVITE", message, extra: extra);
  }

  @override
  void initState() {
    super.initState();

    // WHY: Catch broken links early (e.g. missing token in URL).
    if (widget.token.trim().isEmpty) {
      _error =
          "Invalid invite link (missing token). Please request a new invite.";
      _log("init_missing_invite_token");
    } else {
      _log("init_ok", extra: {"hasInviteToken": true});
    }
  }

  /// Builds the "next" URL so that after login, the app returns here with the token.
  String _buildNextPath() {
    // WHY: We must preserve the invite token across the login redirect.
    final nextPath = Uri(
      path: '/business-invite',
      queryParameters: {'token': widget.token},
    ).toString();

    return nextPath;
  }

  void _redirectToLogin() {
    final nextPath = _buildNextPath();
    final encodedNext = Uri.encodeComponent(nextPath);

    _log("redirect_to_login", extra: {"nextPath": nextPath});

    // WHY: Using next= lets login screen bring the user back to the invite flow.
    context.go('/login?next=$encodedNext');
  }

  Future<void> _acceptInvite() async {
    _log(
      "accept_tap",
      extra: {"hasInviteToken": widget.token.trim().isNotEmpty},
    );

    // 1) Guard: Invite token must exist
    if (widget.token.trim().isEmpty) {
      setState(() {
        _error =
            "Invalid invite link (missing token). Please request a new invite.";
      });
      _log("accept_blocked_missing_invite_token");
      return;
    }

    // 2) Guard: Must be signed in. If not, REDIRECT (this is the main fix).
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      setState(() {
        _error = "Please sign in to accept the invite.";
      });

      _log("accept_requires_login");

      // ✅ FIX: instead of stopping here, send them to login with next=...
      _redirectToLogin();
      return;
    }

    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    try {
      _log("accept_start", extra: {"hasAuthToken": true});

      final api = ref.read(businessTeamApiProvider);

      // WHY:
      // - token: your authenticated session token (Authorization header)
      // - inviteToken: the invite token from the email link (body payload)
      final invitedUser = await api.acceptInvite(
        token: session.token,
        inviteToken: widget.token,
      );

      _log(
        "accept_success",
        extra: {"role": invitedUser.role, "estate": invitedUser.estateAssetId},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invite accepted successfully")),
      );

      // WHY: Tenant invites go straight to tenant verification.
      if (invitedUser.role == "tenant") {
        context.go('/tenant-verification');
        return;
      }

      // NOTE: Owners/staff head to the business dashboard.
      context.go('/business-dashboard');
    } catch (e) {
      final cleaned = e.toString().replaceAll('Exception:', '').trim();

      _log("accept_fail", extra: {"error": cleaned});

      if (!mounted) return;
      setState(
        () => _error = cleaned.isEmpty ? "Something went wrong." : cleaned,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
      _log("accept_end", extra: {"isSubmitting": false});
    }
  }

  @override
  Widget build(BuildContext context) {
    _log("build", extra: {"hasInviteToken": widget.token.trim().isNotEmpty});

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final inviteTokenOk = widget.token.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business invite"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _log("back_tap");

            if (context.canPop()) {
              context.pop();
              return;
            }

            context.go('/home');
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You have been invited to join a business team.",
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Sign in with the invited email address to accept the role.",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Error message area
            if (_error != null)
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),

            const Spacer(),

            // Accept button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // WHY: disable if submitting OR token is missing (broken link)
                onPressed: (_isSubmitting || !inviteTokenOk)
                    ? null
                    : _acceptInvite,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Accept invite"),
              ),
            ),
            const SizedBox(height: 8),

            // Sign in button (always available unless submitting)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _redirectToLogin,
                child: const Text("Sign in"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
