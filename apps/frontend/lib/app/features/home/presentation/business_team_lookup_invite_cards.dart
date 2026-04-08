/// lib/app/features/home/presentation/business_team_lookup_invite_cards.dart
/// --------------------------------------------------------------------
/// WHAT:
/// - Shared lookup + invite widgets for tenant/team flows.
///
/// WHY:
/// - Reuse one search + invite experience across screens.
/// - Prevent duplicated validation and API error handling logic.
///
/// HOW:
/// - BusinessUserLookupCard handles lookup by email/id/phone.
/// - BusinessInviteFormCard sends invites with estate + agreement checks.
/// - Centralizes failure logging + user-facing error mapping.
/// --------------------------------------------------------------------
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_team_providers.dart';
import 'package:frontend/app/features/home/presentation/business_team_user.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';

// WHY: Default to the NG context because tenancy flows are NGN-based.
const String _kDefaultCountry = "NG";
// WHY: Keep service names consistent across logs.
const String businessTeamServiceName = "BUSINESS_TEAM_API";
// WHY: Keep request intent strings reusable across widgets.
const String businessTeamLookupIntent = "Find tenant by email/id/phone";
const String businessTeamInviteIntent = "Invite customer to join team/tenant";
const String businessTeamUpdateRoleIntent = "Assign staff/tenant role";
// WHY: Keep lookup modes consistent across screens.
const String _kLookupModeEmail = "email";
const String _kLookupModeId = "id";
const String _kLookupModePhone = "phone";
// WHY: Keep roles consistent with backend enums.
const String _kRoleStaff = "staff";
const String _kRoleTenant = "tenant";
// WHY: Default staff role prevents empty invite submissions.
const String _kDefaultStaffRole = staffRoleEstateManager;
// WHY: Keep log contexts consistent across widgets.
const String _kLogContextLookup = "Lookup";
const String _kLogContextInvite = "Invite";
// WHY: Keep build log messages consistent across widgets.
const String _kLogLookupBuild = "Lookup build()";
const String _kLogInviteBuild = "Invite build()";
// WHY: Keep operation names consistent across logs.
const String _kOperationLookupUser = "lookupUser";
const String _kOperationCreateInvite = "createInvite";

// WHY: Keep failure classification values in one place.
const String _kFailureInvalidInput = "INVALID_INPUT";
const String _kFailureAuth = "AUTHENTICATION_ERROR";
const String _kFailureRateLimited = "RATE_LIMITED";
const String _kFailureOutage = "PROVIDER_OUTAGE";
const String _kFailureUnknown = "UNKNOWN_PROVIDER_ERROR";

// WHY: Centralize UI copy so we avoid scattered inline strings.
class _Copy {
  static const String lookupTitle = "Find tenant";
  static const String lookupSubtitle =
      "Search by user ID, email, or phone number.";
  static const String lookupEmptyError =
      "Enter a user ID, email, or phone number.";
  static const String sessionExpired = "Session expired. Please sign in again.";
  static const String labelPhone = "Phone number";
  static const String labelUserId = "User ID";
  static const String labelEmail = "Email";
  static const String hintPhone = "e.g. +2348012345678";
  static const String hintUserId = "e.g. 64f0c2...";
  static const String hintEmail = "e.g. user@email.com";
  static const String findUser = "Find user";
  static const String searching = "Searching...";
  static const String inviteTitle = "Send invite link";
  static const String inviteSubtitle =
      "Invite a customer by email to join your team.";
  static const String inviteEmailLabel = "Invitee email";
  static const String inviteEmailHint = "user@email.com";
  static const String inviteRoleLabel = "Role";
  static const String inviteRoleStaff = "Staff";
  static const String inviteRoleTenant = "Tenant";
  static const String inviteStaffRoleLabel = "Staff role";
  static const String inviteMissingStaffRole =
      "Select a staff role for staff invites.";
  static const String staffRoleAssetManager = "Asset manager";
  static const String staffRoleFarmManager = "Farm manager";
  static const String staffRoleEstateManager = "Estate manager";
  static const String staffRoleAccountant = "Accountant";
  static const String staffRoleFieldAgent = "Field agent";
  static const String staffRoleCleaner = "Cleaner";
  static const String staffRoleFarmer = "Farmer";
  static const String staffRoleInventoryKeeper = "Inventory keeper";
  static const String staffRoleAuditor = "Auditor";
  static const String staffRoleSecurity = "Security";
  static const String staffRoleMaintenanceTechnician =
      "Maintenance / Technician";
  static const String staffRoleLogisticsDriver = "Logistics / Driver";
  static const String inviteEstateLabel = "Estate asset";
  static const String inviteAgreementLabel =
      "Agreement text (required for tenants)";
  static const String inviteAgreementHint =
      "Paste the tenancy agreement tenants must accept";
  static const String inviteSend = "Send invite";
  static const String inviteSentPrefix = "Invite sent to ";
  static const String inviteMissingEmail = "Enter an email address.";
  static const String inviteMissingEstate =
      "Select an estate for tenant invites.";
  static const String inviteMissingAgreement =
      "Paste the tenancy agreement text.";
  static const String estateLoading = "Estate assets still loading...";
  static const String estateEmpty = "No estate assets available yet.";
  static const String ninRequired =
      "User must be NIN verified before role upgrade.";
  static const String differentBusiness =
      "User already belongs to another business.";
  static const String userNotFound = "No user found for that lookup.";
  static const String invalidUserId = "Invalid user ID. Check and try again.";
  static const String inviteExpired =
      "Invite link has expired. Send a new invite.";
  static const String inviteEmailMismatch =
      "Invite email does not match your account.";
  static const String inviteEmailRequired = "Invite email is required.";
}

// WHY: Keep log action strings consistent across widgets.
class _LogKeys {
  static const String lookupStart = "lookup_start";
  static const String lookupSuccess = "lookup_success";
  static const String lookupFailed = "lookup_failed";
  static const String lookupModeChange = "lookup_mode_change";
  static const String lookupToggle = "lookup_toggle";
  static const String inviteSendStart = "invite_send_start";
  static const String inviteSendSuccess = "invite_send_success";
  static const String inviteSendFailed = "invite_send_failed";
  static const String inviteToggle = "invite_toggle";
}

// WHY: Centralize card spacing so layouts stay consistent.
class _UiSpacing {
  static const double cardPadding = 16;
  static const double titleGap = 6;
  static const double sectionGap = 12;
  static const double tightGap = 4;
  static const double microGap = 2;
  static const double summaryRadius = 12;
}

// WHY: Keep staff role options centralized for dropdowns.
class _StaffRoleOption {
  final String value;
  final String label;

  const _StaffRoleOption(this.value, this.label);
}

const List<_StaffRoleOption> _staffRoleOptions = [
  _StaffRoleOption(staffRoleEstateManager, _Copy.staffRoleEstateManager),
  _StaffRoleOption(staffRoleFarmManager, _Copy.staffRoleFarmManager),
  _StaffRoleOption(staffRoleAssetManager, _Copy.staffRoleAssetManager),
  _StaffRoleOption(staffRoleAccountant, _Copy.staffRoleAccountant),
  _StaffRoleOption(staffRoleFieldAgent, _Copy.staffRoleFieldAgent),
  _StaffRoleOption(staffRoleInventoryKeeper, _Copy.staffRoleInventoryKeeper),
  _StaffRoleOption(staffRoleFarmer, _Copy.staffRoleFarmer),
  _StaffRoleOption(staffRoleCleaner, _Copy.staffRoleCleaner),
  _StaffRoleOption(staffRoleAuditor, _Copy.staffRoleAuditor),
  _StaffRoleOption(staffRoleSecurity, _Copy.staffRoleSecurity),
  _StaffRoleOption(
    staffRoleMaintenanceTechnician,
    _Copy.staffRoleMaintenanceTechnician,
  ),
  _StaffRoleOption(staffRoleLogisticsDriver, _Copy.staffRoleLogisticsDriver),
];

// WHY: Centralize multi-line text input sizing.
const int _kAgreementLines = 4;
// WHY: Keep loader size consistent across widgets.
const double _kLoaderSize = 18;
// WHY: Keep spinners subtle across surfaces.
const double _kLoaderStroke = 2;
// WHY: Prevent oversized error payloads in logs.
const int _kProviderMessageMax = 300;

// WHY: Share a collapsible shell so lookup + invite cards behave consistently.
class _CollapsibleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final Widget child;

  const _CollapsibleCard({
    required this.title,
    required this.subtitle,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Pull theme tokens so expansion headers match other cards.
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ExpansionTile(
        // WHY: Collapse long forms to keep KPI/content visible on small screens.
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        tilePadding: const EdgeInsets.all(_UiSpacing.cardPadding),
        childrenPadding: const EdgeInsets.only(
          left: _UiSpacing.cardPadding,
          right: _UiSpacing.cardPadding,
          bottom: _UiSpacing.cardPadding,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          const SizedBox(height: _UiSpacing.sectionGap),
          child,
        ],
      ),
    );
  }
}

/// WHY: Map API errors to user-friendly messages.
String businessTeamErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains("User must be NIN verified")) {
    return _Copy.ninRequired;
  }
  if (raw.contains("User belongs to a different business")) {
    return _Copy.differentBusiness;
  }
  if (raw.contains("User not found")) {
    return _Copy.userNotFound;
  }
  if (raw.contains("Invalid user id")) {
    return _Copy.invalidUserId;
  }
  if (raw.contains("Invite has expired")) {
    return _Copy.inviteExpired;
  }
  if (raw.contains("Invite email does not match")) {
    return _Copy.inviteEmailMismatch;
  }
  if (raw.contains("Invite email is required")) {
    return _Copy.inviteEmailRequired;
  }
  return raw.replaceAll("Exception:", "").trim();
}

/// WHY: Log API failures with mandatory diagnostics for support.
void logBusinessTeamApiFailure({
  required String source,
  required String operation,
  required String requestIntent,
  required Map<String, dynamic> requestContext,
  required Object error,
}) {
  final status = _statusCode(error);
  final providerCode = _providerErrorCode(error);
  final providerMessage = _providerErrorMessage(error);
  final classification = _classifyFailure(status);
  final resolutionHint = _resolutionHint(classification);
  final retryMeta = _retryMetadata(classification);

  AppDebug.log(
    businessTeamServiceName,
    "$operation failed",
    extra: {
      "service": businessTeamServiceName,
      "operation": operation,
      "request_intent": requestIntent,
      "request_context": {
        "country": _kDefaultCountry,
        "source": source,
        ...requestContext,
      },
      "http_status": status,
      "provider_error_code": providerCode,
      "provider_error_message": providerMessage,
      "failure_classification": classification,
      if (classification == _kFailureUnknown)
        "failure_justification": "No mappable HTTP status for this error.",
      "resolution_hint": resolutionHint,
      ...retryMeta,
    },
  );
}

// WHY: Normalize lookup labels across widgets.
String _lookupLabel(String mode) {
  switch (mode) {
    case _kLookupModePhone:
      return _Copy.labelPhone;
    case _kLookupModeId:
      return _Copy.labelUserId;
    case _kLookupModeEmail:
    default:
      return _Copy.labelEmail;
  }
}

// WHY: Keep lookup hints consistent per mode.
String _lookupHint(String mode) {
  switch (mode) {
    case _kLookupModePhone:
      return _Copy.hintPhone;
    case _kLookupModeId:
      return _Copy.hintUserId;
    case _kLookupModeEmail:
    default:
      return _Copy.hintEmail;
  }
}

// WHY: Match keyboard type to expected input.
TextInputType _lookupKeyboardType(String mode) {
  switch (mode) {
    case _kLookupModePhone:
      return TextInputType.phone;
    case _kLookupModeEmail:
      return TextInputType.emailAddress;
    case _kLookupModeId:
    default:
      return TextInputType.text;
  }
}

/// ------------------------------------------------------------
/// LOOKUP CARD
/// ------------------------------------------------------------
class BusinessUserLookupCard extends ConsumerStatefulWidget {
  final String source;
  final bool showSummary;
  final ValueChanged<BusinessTeamUser?>? onUserChanged;
  final String title;
  final String subtitle;
  final bool isCollapsible;
  final bool initiallyExpanded;

  const BusinessUserLookupCard({
    super.key,
    required this.source,
    this.showSummary = true,
    this.onUserChanged,
    this.title = _Copy.lookupTitle,
    this.subtitle = _Copy.lookupSubtitle,
    this.isCollapsible = false,
    this.initiallyExpanded = true,
  });

  @override
  ConsumerState<BusinessUserLookupCard> createState() =>
      _BusinessUserLookupCardState();
}

class _BusinessUserLookupCardState
    extends ConsumerState<BusinessUserLookupCard> {
  // WHY: Controllers keep the lookup input stable across rebuilds.
  final _lookupCtrl = TextEditingController();
  String _lookupMode = _kLookupModeEmail;
  bool _isLoading = false;
  BusinessTeamUser? _foundUser;
  String? _error;

  @override
  void dispose() {
    _lookupCtrl.dispose();
    super.dispose();
  }

  void _log(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      widget.source,
      _kLogContextLookup,
      extra: {"action": action, ...?extra},
    );
  }

  Future<void> _lookupUser() async {
    final query = _lookupCtrl.text.trim();
    _log(_LogKeys.lookupStart, extra: {"mode": _lookupMode});

    if (query.isEmpty) {
      setState(() => _error = _Copy.lookupEmptyError);
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      setState(() => _error = _Copy.sessionExpired);
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final api = ref.read(businessTeamApiProvider);
      // WHY: Send only the active lookup field to the API.
      final user = await api.lookupUser(
        token: session.token,
        userId: _lookupMode == _kLookupModeId ? query : null,
        email: _lookupMode == _kLookupModeEmail ? query : null,
        phone: _lookupMode == _kLookupModePhone ? query : null,
      );

      setState(() => _foundUser = user);
      widget.onUserChanged?.call(user);
      _log(_LogKeys.lookupSuccess, extra: {"role": user.role});
    } catch (e) {
      logBusinessTeamApiFailure(
        source: widget.source,
        operation: _kOperationLookupUser,
        requestIntent: businessTeamLookupIntent,
        requestContext: {
          "hasEmail": _lookupMode == _kLookupModeEmail,
          "hasUserId": _lookupMode == _kLookupModeId,
          "hasPhone": _lookupMode == _kLookupModePhone,
        },
        error: e,
      );

      setState(() {
        _foundUser = null;
        _error = businessTeamErrorMessage(e);
      });
      widget.onUserChanged?.call(null);
      _log(_LogKeys.lookupFailed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(widget.source, _kLogLookupBuild);
    // WHY: Build the form once so collapsible and full layouts stay aligned.
    final body = _BusinessUserLookupCardBody(
      title: widget.title,
      subtitle: widget.subtitle,
      lookupCtrl: _lookupCtrl,
      lookupMode: _lookupMode,
      isLoading: _isLoading,
      error: _error,
      showSummary: widget.showSummary,
      foundUser: _foundUser,
      onLookup: _lookupUser,
      onModeChanged: (value) {
        _log(_LogKeys.lookupModeChange, extra: {"mode": value});
        setState(() => _lookupMode = value);
      },
      // WHY: Collapse wrapper renders the header, so skip it here.
      showHeader: !widget.isCollapsible,
      // WHY: Card chrome is handled by the collapsible shell when enabled.
      wrapInCard: !widget.isCollapsible,
    );

    if (!widget.isCollapsible) {
      return body;
    }

    return _CollapsibleCard(
      title: widget.title,
      subtitle: widget.subtitle,
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: (expanded) {
        // WHY: Track expand/collapse to tune tenant lookup UX.
        _log(_LogKeys.lookupToggle, extra: {"expanded": expanded});
      },
      child: body,
    );
  }
}

class _BusinessUserLookupCardBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextEditingController lookupCtrl;
  final String lookupMode;
  final bool isLoading;
  final String? error;
  final bool showSummary;
  final BusinessTeamUser? foundUser;
  final VoidCallback onLookup;
  final ValueChanged<String> onModeChanged;
  final bool showHeader;
  final bool wrapInCard;

  const _BusinessUserLookupCardBody({
    required this.title,
    required this.subtitle,
    required this.lookupCtrl,
    required this.lookupMode,
    required this.isLoading,
    required this.error,
    required this.showSummary,
    required this.foundUser,
    required this.onLookup,
    required this.onModeChanged,
    this.showHeader = true,
    this.wrapInCard = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHY: Let collapsible shells supply the header for tighter layouts.
        if (showHeader) ...[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: _UiSpacing.titleGap),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _UiSpacing.sectionGap),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: lookupCtrl,
                keyboardType: _lookupKeyboardType(lookupMode),
                decoration: InputDecoration(
                  labelText: _lookupLabel(lookupMode),
                  hintText: _lookupHint(lookupMode),
                ),
              ),
            ),
            const SizedBox(width: _UiSpacing.sectionGap),
            DropdownButton<String>(
              value: lookupMode,
              onChanged: isLoading
                  ? null
                  : (value) {
                      if (value == null) return;
                      onModeChanged(value);
                    },
              items: const [
                DropdownMenuItem(
                  value: _kLookupModeId,
                  child: Text(_Copy.labelUserId),
                ),
                DropdownMenuItem(
                  value: _kLookupModeEmail,
                  child: Text(_Copy.labelEmail),
                ),
                DropdownMenuItem(
                  value: _kLookupModePhone,
                  child: Text(_Copy.labelPhone),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: _UiSpacing.sectionGap),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onLookup,
            icon: isLoading
                ? const SizedBox(
                    width: _kLoaderSize,
                    height: _kLoaderSize,
                    child: CircularProgressIndicator(
                      strokeWidth: _kLoaderStroke,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(isLoading ? _Copy.searching : _Copy.findUser),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: _UiSpacing.sectionGap),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (showSummary && foundUser != null) ...[
          const SizedBox(height: _UiSpacing.sectionGap),
          _LookupSummaryCard(user: foundUser!),
        ],
      ],
    );

    // WHY: Collapse wrapper already draws the card chrome.
    if (!wrapInCard) {
      return content;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_UiSpacing.cardPadding),
        child: content,
      ),
    );
  }
}

class _LookupSummaryCard extends StatelessWidget {
  final BusinessTeamUser user;

  const _LookupSummaryCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(_UiSpacing.sectionGap),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_UiSpacing.summaryRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user.displayName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: _UiSpacing.tightGap),
          Text(
            user.email,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (user.phone != null && user.phone!.trim().isNotEmpty) ...[
            const SizedBox(height: _UiSpacing.microGap),
            Text(
              user.phone!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// INVITE CARD
/// ------------------------------------------------------------
class BusinessInviteFormCard extends ConsumerStatefulWidget {
  final String source;
  final List<BusinessAsset> estateAssets;
  final bool estateAssetsLoading;
  final ValueChanged<String>? onInviteSent;
  final String title;
  final String subtitle;
  final bool isCollapsible;
  final bool initiallyExpanded;

  const BusinessInviteFormCard({
    super.key,
    required this.source,
    required this.estateAssets,
    this.estateAssetsLoading = false,
    this.onInviteSent,
    this.title = _Copy.inviteTitle,
    this.subtitle = _Copy.inviteSubtitle,
    this.isCollapsible = false,
    this.initiallyExpanded = true,
  });

  @override
  ConsumerState<BusinessInviteFormCard> createState() =>
      _BusinessInviteFormCardState();
}

class _BusinessInviteFormCardState
    extends ConsumerState<BusinessInviteFormCard> {
  // WHY: Controllers keep the invite input stable across rebuilds.
  final _emailCtrl = TextEditingController();
  final _agreementCtrl = TextEditingController();
  String _role = _kRoleStaff;
  String _staffRole = _kDefaultStaffRole;
  String? _estateAssetId;
  String? _error;
  bool _isSending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _agreementCtrl.dispose();
    super.dispose();
  }

  void _log(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      widget.source,
      _kLogContextInvite,
      extra: {"action": action, ...?extra},
    );
  }

  Future<void> _sendInvite() async {
    // WHY: Normalize email casing so lookup/identity checks stay consistent.
    final email = _emailCtrl.text.trim().toLowerCase();
    // WHY: Require minimum tenant invite inputs before calling the API.
    if (email.isEmpty) {
      setState(() => _error = _Copy.inviteMissingEmail);
      return;
    }
    if (_role == _kRoleTenant && _estateAssetId == null) {
      setState(() => _error = _Copy.inviteMissingEstate);
      return;
    }
    if (_role == _kRoleTenant && _agreementCtrl.text.trim().isEmpty) {
      setState(() => _error = _Copy.inviteMissingAgreement);
      return;
    }
    if (_role == _kRoleStaff && _staffRole.trim().isEmpty) {
      setState(() => _error = _Copy.inviteMissingStaffRole);
      return;
    }

    final session = ref.read(authSessionProvider);
    // WHY: Block sending when the auth session is not valid.
    if (session == null || !session.isTokenValid) {
      setState(() => _error = _Copy.sessionExpired);
      return;
    }

    setState(() {
      // WHY: Clear old errors and lock the form while submitting.
      _error = null;
      _isSending = true;
    });

    _log(
      _LogKeys.inviteSendStart,
      extra: {
        "role": _role,
        "staffRole": _staffRole,
        "hasEstate": _estateAssetId != null,
      },
    );

    try {
      final api = ref.read(businessTeamApiProvider);
      // WHY: Send invite data with tenant-only agreement text.
      await api.createInvite(
        token: session.token,
        email: email,
        role: _role,
        staffRole: _role == _kRoleStaff ? _staffRole : null,
        estateAssetId: _estateAssetId,
        agreementText: _role == _kRoleTenant ? _agreementCtrl.text : null,
      );

      _log(_LogKeys.inviteSendSuccess, extra: {"role": _role});
      widget.onInviteSent?.call(email);
      if (!mounted) return;
      // WHY: Confirm success at the boundary so the user can proceed.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${_Copy.inviteSentPrefix}$email")),
      );
      setState(() {
        // WHY: Reset the form so the next invite starts clean.
        _emailCtrl.clear();
        _agreementCtrl.clear();
        _estateAssetId = null;
        _role = _kRoleStaff;
        _staffRole = _kDefaultStaffRole;
      });
    } catch (e) {
      logBusinessTeamApiFailure(
        source: widget.source,
        operation: _kOperationCreateInvite,
        requestIntent: businessTeamInviteIntent,
        requestContext: {
          "hasEstate": _estateAssetId != null,
          "hasAgreement": _agreementCtrl.text.trim().isNotEmpty,
          "role": _role,
          "staffRole": _staffRole,
        },
        error: e,
      );
      // WHY: Surface user-friendly errors while keeping diagnostics in logs.
      setState(() => _error = businessTeamErrorMessage(e));
      _log(_LogKeys.inviteSendFailed);
    } finally {
      // WHY: Always unlock the form after the request completes.
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(widget.source, _kLogInviteBuild);
    // WHY: Build once to keep collapsible and full layouts in sync.
    final body = _BusinessInviteFormBody(
      title: widget.title,
      subtitle: widget.subtitle,
      emailCtrl: _emailCtrl,
      agreementCtrl: _agreementCtrl,
      role: _role,
      staffRole: _staffRole,
      estateAssetId: _estateAssetId,
      error: _error,
      isSending: _isSending,
      estateAssets: widget.estateAssets,
      estateAssetsLoading: widget.estateAssetsLoading,
      onRoleChanged: (value) {
        if (value == null) return;
        // WHY: Update role state so required fields re-render immediately.
        setState(() {
          _role = value;
          if (_role != _kRoleTenant) {
            _estateAssetId = null;
          }
          if (_role == _kRoleStaff && _staffRole.trim().isEmpty) {
            _staffRole = _kDefaultStaffRole;
          }
        });
      },
      onStaffRoleChanged: (value) {
        if (value == null) return;
        // WHY: Track staff role selection for staff invites.
        setState(() => _staffRole = value);
      },
      onEstateChanged: (value) {
        // WHY: Track estate selection for tenant invites.
        setState(() => _estateAssetId = value);
      },
      onSendInvite: _sendInvite,
      // WHY: Collapsible shell renders the header when enabled.
      showHeader: !widget.isCollapsible,
      // WHY: Card shell moves to the collapsible wrapper when enabled.
      wrapInCard: !widget.isCollapsible,
    );

    if (!widget.isCollapsible) {
      return body;
    }

    return _CollapsibleCard(
      title: widget.title,
      subtitle: widget.subtitle,
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: (expanded) {
        // WHY: Track expand/collapse to tune invite UX on tenant lists.
        _log(_LogKeys.inviteToggle, extra: {"expanded": expanded});
      },
      child: body,
    );
  }
}

class _BusinessInviteFormBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextEditingController emailCtrl;
  final TextEditingController agreementCtrl;
  final String role;
  final String staffRole;
  final String? estateAssetId;
  final String? error;
  final bool isSending;
  final bool estateAssetsLoading;
  final List<BusinessAsset> estateAssets;
  final ValueChanged<String?> onRoleChanged;
  final ValueChanged<String?> onStaffRoleChanged;
  final ValueChanged<String?> onEstateChanged;
  final VoidCallback onSendInvite;
  final bool showHeader;
  final bool wrapInCard;

  const _BusinessInviteFormBody({
    required this.title,
    required this.subtitle,
    required this.emailCtrl,
    required this.agreementCtrl,
    required this.role,
    required this.staffRole,
    required this.estateAssetId,
    required this.error,
    required this.isSending,
    required this.estateAssetsLoading,
    required this.estateAssets,
    required this.onRoleChanged,
    required this.onStaffRoleChanged,
    required this.onEstateChanged,
    required this.onSendInvite,
    this.showHeader = true,
    this.wrapInCard = true,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Tenant-only fields keep staff invites uncluttered.
    final showTenantFields = role == _kRoleTenant;
    // WHY: Staff role is required when inviting staff.
    final showStaffRole = role == _kRoleStaff;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHY: Collapse wrapper can render the header to keep cards compact.
        if (showHeader) ...[
          _InviteHeader(title: title, subtitle: subtitle),
          const SizedBox(height: _UiSpacing.sectionGap),
        ],
        _InviteEmailField(controller: emailCtrl),
        const SizedBox(height: _UiSpacing.sectionGap),
        _InviteRoleField(
          role: role,
          isSending: isSending,
          onRoleChanged: onRoleChanged,
        ),
        if (showStaffRole) ...[
          const SizedBox(height: _UiSpacing.sectionGap),
          _InviteStaffRoleField(
            staffRole: staffRole,
            isSending: isSending,
            onStaffRoleChanged: onStaffRoleChanged,
          ),
        ],
        if (showTenantFields) ...[
          const SizedBox(height: _UiSpacing.sectionGap),
          _InviteTenantFields(
            estateAssetId: estateAssetId,
            estateAssetsLoading: estateAssetsLoading,
            estateAssets: estateAssets,
            isSending: isSending,
            agreementCtrl: agreementCtrl,
            onEstateChanged: onEstateChanged,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: _UiSpacing.sectionGap),
          _InviteErrorText(message: error!),
        ],
        const SizedBox(height: _UiSpacing.sectionGap),
        _InviteSendButton(isSending: isSending, onSendInvite: onSendInvite),
      ],
    );

    // WHY: Collapse wrapper already supplies card padding + chrome.
    if (!wrapInCard) {
      return content;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_UiSpacing.cardPadding),
        child: content,
      ),
    );
  }
}

class _InviteHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _InviteHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    // WHY: Keep title + subtitle grouped for consistent spacing.
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: _UiSpacing.titleGap),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InviteEmailField extends StatelessWidget {
  final TextEditingController controller;

  const _InviteEmailField({required this.controller});

  @override
  Widget build(BuildContext context) {
    // WHY: Email is the primary identifier for sending invites.
    return TextField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: _Copy.inviteEmailLabel,
        hintText: _Copy.inviteEmailHint,
      ),
    );
  }
}

class _InviteRoleField extends StatelessWidget {
  final String role;
  final bool isSending;
  final ValueChanged<String?> onRoleChanged;

  const _InviteRoleField({
    required this.role,
    required this.isSending,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Role selection controls which tenant-specific inputs appear.
    return DropdownButtonFormField<String>(
      initialValue: role,
      decoration: const InputDecoration(labelText: _Copy.inviteRoleLabel),
      items: const [
        DropdownMenuItem(
          value: _kRoleStaff,
          child: Text(_Copy.inviteRoleStaff),
        ),
        DropdownMenuItem(
          value: _kRoleTenant,
          child: Text(_Copy.inviteRoleTenant),
        ),
      ],
      onChanged: isSending ? null : onRoleChanged,
    );
  }
}

class _InviteStaffRoleField extends StatelessWidget {
  final String staffRole;
  final bool isSending;
  final ValueChanged<String?> onStaffRoleChanged;

  const _InviteStaffRoleField({
    required this.staffRole,
    required this.isSending,
    required this.onStaffRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Staff role selection is required for staff invites.
    return DropdownButtonFormField<String>(
      initialValue: staffRole,
      onChanged: isSending ? null : onStaffRoleChanged,
      decoration: const InputDecoration(labelText: _Copy.inviteStaffRoleLabel),
      items: _staffRoleOptions
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.value,
              child: Text(option.label),
            ),
          )
          .toList(),
    );
  }
}

class _InviteTenantFields extends StatelessWidget {
  final String? estateAssetId;
  final bool estateAssetsLoading;
  final List<BusinessAsset> estateAssets;
  final bool isSending;
  final TextEditingController agreementCtrl;
  final ValueChanged<String?> onEstateChanged;

  const _InviteTenantFields({
    required this.estateAssetId,
    required this.estateAssetsLoading,
    required this.estateAssets,
    required this.isSending,
    required this.agreementCtrl,
    required this.onEstateChanged,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Tenant invites need estate + agreement inputs.
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: estateAssetId,
          decoration: const InputDecoration(labelText: _Copy.inviteEstateLabel),
          items: estateAssets
              .map(
                (asset) =>
                    DropdownMenuItem(value: asset.id, child: Text(asset.name)),
              )
              .toList(),
          onChanged: isSending ? null : onEstateChanged,
        ),
        if (estateAssetsLoading) ...[
          const SizedBox(height: _UiSpacing.titleGap),
          Text(
            _Copy.estateLoading,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ] else if (estateAssets.isEmpty) ...[
          const SizedBox(height: _UiSpacing.titleGap),
          Text(
            _Copy.estateEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: _UiSpacing.sectionGap),
        // WHY: Tenants must receive and accept a required agreement.
        TextField(
          controller: agreementCtrl,
          maxLines: _kAgreementLines,
          decoration: const InputDecoration(
            labelText: _Copy.inviteAgreementLabel,
            hintText: _Copy.inviteAgreementHint,
          ),
        ),
      ],
    );
  }
}

class _InviteErrorText extends StatelessWidget {
  final String message;

  const _InviteErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    // WHY: Highlight validation/API errors close to the form.
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.error,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InviteSendButton extends StatelessWidget {
  final bool isSending;
  final VoidCallback onSendInvite;

  const _InviteSendButton({
    required this.isSending,
    required this.onSendInvite,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep the primary action full-width for easy access.
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isSending ? null : onSendInvite,
        child: isSending
            ? const SizedBox(
                width: _kLoaderSize,
                height: _kLoaderSize,
                child: CircularProgressIndicator(strokeWidth: _kLoaderStroke),
              )
            : const Text(_Copy.inviteSend),
      ),
    );
  }
}

int? _statusCode(Object error) {
  if (error is DioException) return error.response?.statusCode;
  return null;
}

String? _providerErrorCode(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      return data["code"]?.toString() ?? data["errorCode"]?.toString();
    }
  }
  return null;
}

String _providerErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data == null) return error.message ?? "Unknown provider error";
    final raw = data.toString();
    // WHY: Cap provider messages to keep logs readable.
    return raw.length > _kProviderMessageMax
        ? raw.substring(0, _kProviderMessageMax)
        : raw;
  }
  return error.toString();
}

String _classifyFailure(int? status) {
  if (status == null) return _kFailureUnknown;
  if (status == 400) return _kFailureInvalidInput;
  if (status == 401 || status == 403) return _kFailureAuth;
  if (status == 404) return _kFailureInvalidInput;
  if (status == 429) return _kFailureRateLimited;
  if (status >= 500) return _kFailureOutage;
  return _kFailureUnknown;
}

String _resolutionHint(String classification) {
  switch (classification) {
    case _kFailureAuth:
      return "Re-authenticate and retry the request.";
    case _kFailureInvalidInput:
      return "Verify the input values and try again.";
    case _kFailureRateLimited:
      return "Wait before retrying to avoid rate limits.";
    case _kFailureOutage:
      return "Retry later or check provider status.";
    case _kFailureUnknown:
    default:
      return "Check server logs for more context.";
  }
}

Map<String, dynamic> _retryMetadata(String classification) {
  switch (classification) {
    case _kFailureRateLimited:
      return {"retry_allowed": true, "retry_reason": "rate_limited"};
    case _kFailureOutage:
      return {"retry_allowed": true, "retry_reason": "provider_outage"};
    case _kFailureAuth:
      return {"retry_skipped": true, "retry_reason": "reauth_required"};
    case _kFailureInvalidInput:
      return {"retry_skipped": true, "retry_reason": "invalid_input"};
    case _kFailureUnknown:
    default:
      return {"retry_skipped": true, "retry_reason": "unknown_failure"};
  }
}
