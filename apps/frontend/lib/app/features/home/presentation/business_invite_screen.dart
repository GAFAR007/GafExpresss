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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/auth_session.dart';
import 'package:frontend/app/features/auth/domain/models/auth_user.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/business_team_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class BusinessInviteScreen extends ConsumerStatefulWidget {
  final String token;

  const BusinessInviteScreen({super.key, required this.token});

  @override
  ConsumerState<BusinessInviteScreen> createState() =>
      _BusinessInviteScreenState();
}

// WHY: Centralize invite copy to avoid inline strings.
class _Copy {
  static const String title = "Business invite";
  static const String heading =
      "You have been invited to join a business team.";
  static const String subheading =
      "Complete your invite to unlock the business workspace.";
  static const String stepOne = "Sign in with the invited email.";
  static const String stepTwo = "Accept the invite to continue.";
  static const String autoAcceptHint =
      "We will accept the invite automatically after you sign in.";
  static const String signedInHint =
      "You are signed in. Accept your invite to continue.";
  static const String acceptInvite = "Accept invite";
  static const String signInToAccept = "Sign in to accept";
  static const String inviteAccepted = "Invite accepted successfully";
  static const String missingTokenError =
      "Invalid invite link (missing token). Please request a new invite.";
  static const String loginRequired = "Please sign in to accept the invite.";
  static const String genericError = "Something went wrong.";
  static const String inviteReady = "Invite ready";
  static const String invitePending = "Sign-in required";
  static const String supportHint =
      "If this keeps happening, please contact support.";
  static const String errorTitle = "We couldn’t accept this invite.";
  static const String retryLater = "Please try again shortly.";
  static const String emailMismatch =
      "Sign in with the invited email address to accept this invite.";
  static const String ninRequired =
      "NIN verification is required before accepting this invite.";
  static const String roleNotEligible =
      "Only customer accounts can accept this invite.";
  static const String differentBusiness =
      "This account belongs to a different business.";
  static const String missingEstate =
      "This invite is missing an estate assignment.";
  static const String invalidInvite =
      "This invite link is invalid or has expired.";

  // WHY: Keep backend error matching phrases centralized.
  static const String _errEmailMismatch =
      "Invite email does not match signed-in user";
  static const String _errNinRequired = "User must be NIN verified";
  static const String _errRoleNotEligible = "Only customers can be upgraded";
  static const String _errDifferentBusiness =
      "User belongs to a different business";
  static const String _errMissingEstate = "Estate asset is required";
  static const String _errMissingToken = "Invite token is required";
}

class _BusinessInviteScreenState extends ConsumerState<BusinessInviteScreen> {
  bool _isSubmitting = false;
  String? _error;
  bool _autoAcceptTriggered = false;

  void _log(String message, {Map<String, dynamic>? extra}) {
    // WHY: Central, searchable logs to debug invite flow.
    // NOTE: Do NOT log tokens or passwords.
    AppDebug.log("BUSINESS_INVITE", message, extra: extra);
  }

  /// ------------------------------------------------------
  /// ERROR HANDLING HELPERS
  /// ------------------------------------------------------
  String _extractErrorMessage(Object error) {
    // WHY: Prefer backend error messages over raw Dio exceptions.
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data["error"]?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
      return error.message?.toString().trim() ?? error.toString();
    }
    return error.toString().replaceAll("Exception:", "").trim();
  }

  String _friendlyInviteError(String message, int? statusCode) {
    final lower = message.toLowerCase();
    // WHY: Provide clear, actionable guidance per common backend errors.
    if (lower.contains(_Copy._errEmailMismatch.toLowerCase())) {
      return _Copy.emailMismatch;
    }
    if (lower.contains(_Copy._errNinRequired.toLowerCase())) {
      return _Copy.ninRequired;
    }
    if (lower.contains(_Copy._errRoleNotEligible.toLowerCase())) {
      return _Copy.roleNotEligible;
    }
    if (lower.contains(_Copy._errDifferentBusiness.toLowerCase())) {
      return _Copy.differentBusiness;
    }
    if (lower.contains(_Copy._errMissingEstate.toLowerCase())) {
      return _Copy.missingEstate;
    }
    if (lower.contains(_Copy._errMissingToken.toLowerCase())) {
      return _Copy.invalidInvite;
    }
    if (statusCode == 404) {
      return _Copy.invalidInvite;
    }
    if (statusCode != null && statusCode >= 500) {
      return _Copy.retryLater;
    }
    return _Copy.genericError;
  }

  String _classifyInviteFailure({
    required String message,
    required int? statusCode,
  }) {
    final lower = message.toLowerCase();
    // WHY: Use mandatory failure classes for external calls.
    if (statusCode == 401 || statusCode == 403) {
      return "AUTHENTICATION_ERROR";
    }
    if (lower.contains(_Copy._errMissingToken.toLowerCase())) {
      return "MISSING_REQUIRED_FIELD";
    }
    if (lower.contains(_Copy._errMissingEstate.toLowerCase())) {
      return "MISSING_REQUIRED_FIELD";
    }
    if (lower.contains("rate") && lower.contains("limit")) {
      return "RATE_LIMITED";
    }
    if (statusCode != null && statusCode >= 500) {
      return "PROVIDER_OUTAGE";
    }
    return "INVALID_INPUT";
  }

  String _resolutionHintForFailure(String classification) {
    // WHY: Provide a clear next action per failure classification.
    switch (classification) {
      case "AUTHENTICATION_ERROR":
        return "Sign in again with the invited email, then retry.";
      case "MISSING_REQUIRED_FIELD":
        return "Request a fresh invite link and try again.";
      case "RATE_LIMITED":
        return "Wait a few minutes and retry.";
      case "PROVIDER_OUTAGE":
        return "Try again shortly or contact support.";
      case "INVALID_INPUT":
      default:
        return "Verify the invited email and try again.";
    }
  }

  /// ------------------------------------------------------
  /// CACHE PENDING INVITE TOKEN
  /// ------------------------------------------------------
  Future<void> _cachePendingInviteToken() async {
    final trimmed = widget.token.trim();
    if (trimmed.isEmpty) return;

    // WHY: Persist invite token so login can return here even if query params
    // are lost or overwritten during auth.
    final storage = ref.read(authSessionStorageProvider);
    await storage.savePendingInviteToken(trimmed);
    // WHY: Keep an in-memory copy for router redirects.
    ref.read(pendingInviteTokenProvider.notifier).state = trimmed;
    _log("pending_invite_saved", extra: {"hasInviteToken": true});
  }

  @override
  void initState() {
    super.initState();

    // WHY: Catch broken links early (e.g. missing token in URL).
    if (widget.token.trim().isEmpty) {
      _error = _Copy.missingTokenError;
      _log("init_missing_invite_token");

      // WHY: Clear any stale pending token so it doesn't hijack login later.
      final storage = ref.read(authSessionStorageProvider);
      storage.clearPendingInviteToken().then((_) {
        _log("pending_invite_cleared_invalid_link");
      });
      // WHY: Clear in-memory pending token as well.
      ref.read(pendingInviteTokenProvider.notifier).state = null;
    } else {
      _log("init_ok", extra: {"hasInviteToken": true});
      // WHY: Save token now so login can recover the invite flow.
      _cachePendingInviteToken();
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

    // WHY: Ensure token is cached before leaving this screen.
    _cachePendingInviteToken();

    _log("redirect_to_login", extra: {"hasInviteToken": true});

    // WHY: Using next= lets login screen bring the user back to the invite flow.
    context.go('/login?next=$encodedNext');
  }

  void _maybeAutoAccept() {
    if (_autoAcceptTriggered) return;
    if (widget.token.trim().isEmpty) return;

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) return;

    _autoAcceptTriggered = true;
    _log("auto_accept_queued");

    // WHY: Defer to next frame to avoid calling setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _acceptInvite();
    });
  }

  Future<void> _acceptInvite() async {
    _log(
      "accept_tap",
      extra: {"hasInviteToken": widget.token.trim().isNotEmpty},
    );

    // 1) Guard: Invite token must exist
    if (widget.token.trim().isEmpty) {
      setState(() {
        _error = _Copy.missingTokenError;
      });
      _log("accept_blocked_missing_invite_token");
      return;
    }

    // 2) Guard: Must be signed in. If not, REDIRECT (this is the main fix).
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      setState(() {
        _error = _Copy.loginRequired;
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
      final acceptance = await api.acceptInvite(
        token: session.token,
        inviteToken: widget.token,
      );
      final invitedUser = acceptance.user;

      _log(
        "accept_success",
        extra: {"role": invitedUser.role, "estate": invitedUser.estateAssetId},
      );

      // WHY: Clear pending invite token once the backend confirms acceptance.
      final storage = ref.read(authSessionStorageProvider);
      await storage.clearPendingInviteToken();
      ref.read(pendingInviteTokenProvider.notifier).state = null;
      _log("pending_invite_cleared_success");

      final nextToken = acceptance.token?.trim() ?? "";
      if (nextToken.isNotEmpty) {
        // WHY: Refresh the session token so backend role checks pass immediately.
        final updatedUser = AuthUser.fromJson({
          ...session.user.toJson(),
          "role": invitedUser.role,
          // WHY: Prefer invite-linked business scope when available.
          "businessId": invitedUser.businessId ?? session.user.businessId,
          if (invitedUser.staffRole != null) "staffRole": invitedUser.staffRole,
        });
        final updatedSession = AuthSession(user: updatedUser, token: nextToken);
        await ref.read(authSessionProvider.notifier).setSession(updatedSession);
        _log(
          "session_refreshed",
          extra: {"role": invitedUser.role, "hasToken": true},
        );
      } else {
        // WHY: Fallback to role update if token refresh is unavailable.
        await ref
            .read(authSessionProvider.notifier)
            .updateUserRole(
              role: invitedUser.role,
              staffRole: invitedUser.staffRole,
              source: "business_invite_accept_missing_token",
            );
        _log(
          "session_role_only",
          extra: {"role": invitedUser.role, "hasToken": false},
        );
      }

      // WHY: Refresh cached data so tenant/business nav updates immediately.
      await AppRefresh.refreshApp(
        ref: ref,
        source: "business_invite_accept_success",
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(_Copy.inviteAccepted)));

      // WHY: Tenant invites go straight to tenant verification.
      if (invitedUser.role == "tenant") {
        context.go('/tenant-verification');
        return;
      }

      // NOTE: Owners/staff head to the business dashboard.
      context.go('/business-dashboard');
    } catch (e) {
      final cleaned = _extractErrorMessage(e);
      final statusCode = e is DioException ? e.response?.statusCode : null;
      final classification = _classifyInviteFailure(
        message: cleaned,
        statusCode: statusCode,
      );
      final resolutionHint = _resolutionHintForFailure(classification);

      _log(
        "accept_fail",
        extra: {
          "service": "business_invites",
          "operation": "acceptInvite",
          "intent": "accept business invite",
          "country": "unknown",
          "source": "business_invite_screen",
          "context": {
            "hasInviteToken": widget.token.trim().isNotEmpty,
            "hasAuthSession": session.isTokenValid,
          },
          "http_status": statusCode ?? 0,
          "provider_error_code": null,
          "provider_error_message": cleaned,
          "failure_classification": classification,
          "resolution_hint": resolutionHint,
          "retry_skipped": true,
          "retry_reason": "User action required",
        },
      );

      if (!mounted) return;
      setState(() {
        _error = _friendlyInviteError(cleaned, statusCode);
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
      _log("accept_end", extra: {"isSubmitting": false});
    }
  }

  @override
  Widget build(BuildContext context) {
    _log("build", extra: {"hasInviteToken": widget.token.trim().isNotEmpty});

    final session = ref.watch(authSessionProvider);
    final isSignedIn = session != null && session.isTokenValid;
    _maybeAutoAccept();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final inviteTokenOk = widget.token.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_Copy.title),
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
            // WHY: Use a welcoming hero card to focus the invite context.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.handshake_outlined,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _Copy.heading,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _Copy.subheading,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // WHY: Make the signed-in status explicit before the CTA.
            Row(
              children: [
                Icon(
                  isSignedIn ? Icons.check_circle : Icons.lock_outline,
                  color: isSignedIn ? colorScheme.primary : colorScheme.outline,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isSignedIn ? _Copy.inviteReady : _Copy.invitePending,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // WHY: Show the minimal steps so the flow feels clear.
            _InviteStep(text: _Copy.stepOne),
            const SizedBox(height: 8),
            _InviteStep(text: _Copy.stepTwo),
            const SizedBox(height: 12),
            Text(
              isSignedIn ? _Copy.signedInHint : _Copy.autoAcceptHint,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Error message area
            if (_error != null) ...[
              Text(
                _Copy.errorTitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _Copy.supportHint,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            const Spacer(),

            // Single CTA button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // WHY: disable if submitting OR token is missing (broken link)
                onPressed: (_isSubmitting || !inviteTokenOk)
                    ? null
                    : isSignedIn
                    ? _acceptInvite
                    : _redirectToLogin,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        isSignedIn ? _Copy.acceptInvite : _Copy.signInToAccept,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteStep extends StatelessWidget {
  final String text;

  const _InviteStep({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Reuse a small bullet layout for each step line.
    return Row(
      children: [
        Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
