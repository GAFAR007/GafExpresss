/// lib/app/features/home/presentation/tenant_verification_screen.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Tenant verification screen for estate onboarding.
///
/// WHY:
/// - Tenants must submit unit selection + references/guarantors for approval.
/// - Keeps NIN-verified identity read-only while collecting tenancy details.
///
/// HOW:
/// - Loads tenant estate via tenantEstateProvider.
/// - Reads tenant profile via userProfileProvider.
/// - Submits verification to /business/tenant/verify with structured payload.
///
/// DEBUGGING:
/// - Logs build, taps, and API calls (no secrets).
/// -----------------------------------------------------------------
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/constants/app_constants.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/core/formatters/email_formatter.dart';
import 'package:frontend/app/core/formatters/phone_formatter.dart';
import 'package:frontend/app/core/platform/platform_info.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart'
    as business_tenant;

import 'package:frontend/app/features/home/presentation/paystack_checkout_screen.dart';
import 'package:frontend/app/features/home/presentation/tenant_document_picker.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_model.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_providers.dart';
import 'package:frontend/app/theme/app_theme.dart';

class TenantVerificationScreen extends ConsumerStatefulWidget {
  const TenantVerificationScreen({super.key});

  @override
  ConsumerState<TenantVerificationScreen> createState() =>
      _TenantVerificationScreenState();
}

class _TenantVerificationScreenState
    extends ConsumerState<TenantVerificationScreen> {
  // WHY: Keep input stable across rebuilds.
  final _moveInCtrl = TextEditingController();

  // WHY: Dynamic contact lists for references + guarantors.
  final List<_ContactControllers> _referenceCtrls = [];
  final List<_ContactControllers> _guarantorCtrls = [];

  bool _agreementSigned = false;
  bool _isSubmitting = false;
  bool _isPaying = false;
  String? _selectedUnitType;
  String? _selectedRentPeriod;
  String? _lastRulesKey;

  // WHY: Allow tenant to pick a rent cadence (backend validates if needed).
  static const List<String> _rentPeriods = ["monthly", "quarterly", "yearly"];
  // WHY: Keep Nigerian phone format consistent with Settings.
  static const String _ngPhonePrefix = "+234";
  static const int _ngPhoneDigits = 10;
  // WHY: Centralize contact error copy to avoid inline strings.
  static const String _contactMissingFields =
      "Each reference/guarantor needs first name, last name, email, and phone.";
  static const String _contactInvalidPhone =
      "Enter 10 digits after +234 for Nigerian numbers.";
  static const String _contactInvalidEmail =
      "Enter a valid email address for each contact.";
  static const String _contactUploadFailed =
      "Document upload failed. Try again.";
  static const String _statusErrorMessage =
      "We couldn't load your tenant status yet.";
  static const String _estateErrorMessage =
      "We couldn't load your estate details yet.";
  static const String _profileErrorMessage =
      "We couldn't load your tenant profile yet.";
  static const String _authErrorMessage =
      "Your session needs a refresh. Please sign out and sign in again.";
  static const String _missingApplicationMessage =
      "No tenant application found yet. Complete the form below.";
  static const String _missingEstateMessage =
      "Your tenant estate is not assigned yet. Please contact support.";
  static const String _genericErrorMessage =
      "Please try again or contact support if this keeps happening.";
  // WHY: Keep tenant error UI copy and actions consistent across sections.
  static const String _statusErrorTitle = "Tenant status unavailable";
  static const String _estateErrorTitle = "Estate details unavailable";
  static const String _profileErrorTitle = "Tenant profile unavailable";
  static const String _authErrorTitle = "Sign-in needed";
  static const String _actionRefreshLabel = "Refresh";
  static const String _actionSettingsLabel = "Open settings";
  static const String _settingsRoute = "/settings";
  static const String _refreshSourceStatus =
      "tenant_verification_status_refresh";
  static const String _refreshSourceEstate =
      "tenant_verification_estate_refresh";
  static const String _refreshSourceProfile =
      "tenant_verification_profile_refresh";
  // WHY: Use named HTTP codes to avoid magic numbers in error mapping.
  static const int _httpBadRequest = 400;
  static const int _httpUnauthorized = 401;
  static const int _httpForbidden = 403;
  static const int _httpNotFound = 404;

  void _log(String message, {Map<String, dynamic>? extra}) {
    AppDebug.log("TENANT_VERIFY", message, extra: extra);
  }

  @override
  void dispose() {
    _moveInCtrl.dispose();
    for (final ctrl in _referenceCtrls) {
      ctrl.dispose();
    }
    for (final ctrl in _guarantorCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // WHY: Initialize reference/guarantor lists to match estate rules.
  void _syncContactLists(BusinessAssetTenantRules rules) {
    final key =
        "${rules.referencesMin}-${rules.referencesMax}-${rules.guarantorsMin}-${rules.guarantorsMax}";
    if (_lastRulesKey == key) return;

    _lastRulesKey = key;

    _ensureMinContacts(_referenceCtrls, rules.referencesMin);
    _ensureMinContacts(_guarantorCtrls, rules.guarantorsMin);

    _log(
      "rules_sync",
      extra: {
        "referencesMin": rules.referencesMin,
        "guarantorsMin": rules.guarantorsMin,
      },
    );
  }

  void _ensureMinContacts(List<_ContactControllers> list, int min) {
    // WHY: Ensure the UI always shows the required minimum entries.
    if (list.length >= min) return;
    final missing = min - list.length;
    for (var i = 0; i < missing; i++) {
      list.add(_ContactControllers.empty());
    }
  }

  void _addContact(List<_ContactControllers> list) {
    setState(() => list.add(_ContactControllers.empty()));
  }

  void _removeContact(List<_ContactControllers> list, int index) {
    if (index < 0 || index >= list.length) return;
    final ctrl = list.removeAt(index);
    ctrl.dispose();
    setState(() {});
  }

  String _formatRent(double amount) {
    // WHY: Centralize money formatting for rent values.
    return formatNgnFromCents(amount.round());
  }

  String _formatDate(DateTime date) {
    // WHY: Reuse shared date formatting for move-in and summary labels.
    return formatDateLabel(date);
  }

  String _formatMoneyKobo(int kobo) {
    // WHY: Centralize money formatting for payment summaries.
    return formatNgnFromCents(kobo);
  }

  bool _isValidEmail(String input) {
    // WHY: Keep a minimal email validation to block obvious mistakes.
    final normalized = normalizeEmail(input);
    if (!normalized.contains("@")) return false;
    final parts = normalized.split("@");
    if (parts.length != 2) return false;
    return parts.last.contains(".");
  }

  List<TenantContact>? _buildContacts(List<_ContactControllers> controllers) {
    final contacts = <TenantContact>[];

    for (final ctrl in controllers) {
      final firstName = ctrl.firstNameCtrl.text.trim();
      final lastName = ctrl.lastNameCtrl.text.trim();
      final emailRaw = ctrl.emailCtrl.text.trim();
      final phoneDigits = ctrl.phoneCtrl.text.trim();

      if (firstName.isEmpty || lastName.isEmpty) {
        _log("contact_validation_failed", extra: {"reason": "name"});
        _showMessage(_contactMissingFields);
        return null;
      }

      if (emailRaw.isEmpty || !_isValidEmail(emailRaw)) {
        _log("contact_validation_failed", extra: {"reason": "email"});
        _showMessage(_contactInvalidEmail);
        return null;
      }

      final normalizedPhone = normalizeNigerianPhone(phoneDigits);
      if (phoneDigits.isEmpty || normalizedPhone == null) {
        _log("contact_validation_failed", extra: {"reason": "phone"});
        _showMessage(_contactInvalidPhone);
        return null;
      }

      final contact = ctrl.toContact(
        normalizedPhone: normalizedPhone,
        normalizedEmail: normalizeEmail(emailRaw),
      );

      if (contact == null) {
        _log("contact_validation_failed", extra: {"reason": "contact"});
        _showMessage(_contactMissingFields);
        return null;
      }

      contacts.add(contact);
    }

    return contacts;
  }

  Future<void> _uploadContactDocument(_ContactControllers controller) async {
    if (controller.isUploading) {
      _log("contact_doc_upload_skip_busy");
      return;
    }

    _log("contact_doc_upload_tap");
    final picked = await pickTenantDocument();
    if (picked == null) {
      _log("contact_doc_upload_cancel");
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null) {
      _log("contact_doc_upload_block_session");
      _showMessage("Session expired. Please sign in again.");
      return;
    }

    setState(() => controller.isUploading = true);

    try {
      final api = ref.read(tenantVerificationApiProvider);
      _log("contact_doc_upload_start", extra: {"bytes": picked.bytes.length});
      final data = await api.uploadTenantContactDocument(
        token: session.token,
        bytes: picked.bytes,
        filename: picked.filename,
      );

      final url = data["documentUrl"]?.toString().trim() ?? "";
      final publicId = data["documentPublicId"]?.toString().trim() ?? "";

      if (url.isEmpty) {
        throw Exception("Document URL missing");
      }

      setState(() {
        controller.documentUrl = url;
        controller.documentPublicId = publicId.isEmpty ? null : publicId;
        controller.documentName = picked.filename;
      });

      _log(
        "contact_doc_upload_success",
        extra: {"hasPublicId": publicId.isNotEmpty},
      );
    } catch (error) {
      _log(
        "contact_doc_upload_fail",
        extra: {"error": _extractErrorMessage(error)},
      );
      _showMessage(_contactUploadFailed);
    } finally {
      if (mounted) {
        setState(() => controller.isUploading = false);
      }
    }
  }

  void _clearContactDocument(_ContactControllers controller) {
    _log("contact_doc_remove_tap");
    setState(() {
      controller.documentUrl = null;
      controller.documentPublicId = null;
      controller.documentName = null;
    });
  }

  Future<void> _pickMoveInDate() async {
    _log("move_in_pick_tap");
    final now = DateTime.now();
    final initial = now.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      initialDate: initial,
    );
    if (picked == null) return;

    setState(() {
      _moveInCtrl.text = _formatDate(picked);
    });
    _log("move_in_pick_ok", extra: {"date": _moveInCtrl.text});
  }

  Future<void> _submitTenantVerification({
    required TenantEstate estate,
    required UserProfile profile,
  }) async {
    if (_isSubmitting) {
      _log("submit_skip_busy");
      return;
    }

    _log("submit_tap");

    final session = ref.read(authSessionProvider);
    if (session == null) {
      _log("submit_block_missing_session");
      _showMessage("Session expired. Please sign in again.");
      return;
    }

    if (!profile.isNinVerified) {
      _log("submit_block_nin");
      _showMessage("You must be NIN verified to proceed.");
      return;
    }

    final application = ref.read(tenantApplicationProvider).asData?.value;
    final agreementText = (application?.agreementText.isNotEmpty ?? false)
        ? application!.agreementText
        : estate.agreementText;

    final unitType = _selectedUnitType?.trim() ?? "";
    if (unitType.isEmpty) {
      _log("submit_block_unit_missing");
      _showMessage("Select a unit type to continue.");
      return;
    }

    if (_moveInCtrl.text.trim().isEmpty) {
      _log("submit_block_move_in_missing");
      _showMessage("Select a move-in date.");
      return;
    }

    final rentPeriod = (_selectedRentPeriod ?? "").trim();
    if (rentPeriod.isEmpty) {
      _log("submit_block_rent_period_missing");
      _showMessage("Select a rent period.");
      return;
    }

    if (estate.tenantRules.requiresAgreementSigned && agreementText.isEmpty) {
      _log("submit_block_agreement_missing");
      _showMessage(
        "Agreement is missing. Ask your owner to resend the invite with the agreement attached.",
      );
      return;
    }

    if (estate.tenantRules.requiresAgreementSigned && !_agreementSigned) {
      _log("submit_block_agreement_required");
      _showMessage("Agreement must be signed before verification.");
      return;
    }

    final references = _buildContacts(_referenceCtrls);
    if (references == null) return;
    final guarantors = _buildContacts(_guarantorCtrls);
    if (guarantors == null) return;

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(tenantVerificationApiProvider);
      _log(
        "submit_request",
        extra: {
          "unitType": unitType,
          "references": references.length,
          "guarantors": guarantors.length,
          "hasAgreement": agreementText.isNotEmpty,
        },
      );

      await api.submitTenantVerification(
        token: session.token,
        unitType: unitType,
        rentPeriod: rentPeriod,
        moveInDate: _moveInCtrl.text.trim(),
        references: references,
        guarantors: guarantors,
        agreementSigned: _agreementSigned,
        agreementText: agreementText,
      );

      _log("submit_success");

      if (!mounted) return;
      // WHY: Refresh tenant dashboard + verification state after submission.
      await AppRefresh.refreshApp(
        ref: ref,
        source: "tenant_verification_submit_success",
      );
      _showMessage("Tenant verification submitted successfully.");
      // WHY: Guard pop to avoid GoError when this is a top-level route.
      if (context.canPop()) {
        _log("submit_nav_pop");
        context.pop();
      } else {
        _log("submit_nav_fallback", extra: {"to": "/tenant-dashboard"});
        context.go("/tenant-dashboard");
      }
    } catch (error) {
      final message = _extractErrorMessage(error);
      _log("submit_fail", extra: {"error": message});
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _startTenantPayment({
    required business_tenant.BusinessTenantApplication application,
  }) async {
    if (_isPaying) {
      _log("pay_skip_busy");
      return;
    }

    _log("pay_tap", extra: {"status": application.status});

    final session = ref.read(authSessionProvider);
    if (session == null) {
      _log("pay_block_missing_session");
      _showMessage("Session expired. Please sign in again.");
      return;
    }

    setState(() => _isPaying = true);

    try {
      final api = ref.read(tenantVerificationApiProvider);
      _log("pay_intent_request", extra: {"tenantId": session.user.id});

      final callbackUrl = _buildCallbackUrl();
      if (callbackUrl == null || callbackUrl.isEmpty) {
        throw Exception("Paystack callback URL not configured");
      }

      final data = await api.createTenantPaymentIntent(
        token: session.token,
        tenantId: session.user.id,
        callbackUrl: callbackUrl,
      );

      final authorizationUrl =
          data["authorizationUrl"]?.toString().trim() ?? "";
      final reference = data["reference"]?.toString().trim() ?? "";

      if (authorizationUrl.isEmpty) {
        throw Exception("Payment authorization URL missing");
      }

      await _openPaystack(
        authorizationUrl: authorizationUrl,
        callbackUrl: callbackUrl,
      );

      _log("pay_intent_opened", extra: {"hasReference": reference.isNotEmpty});
    } catch (error) {
      final message = _extractErrorMessage(error);
      _log("pay_intent_fail", extra: {"error": message});
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  Future<void> _openPaystack({
    required String authorizationUrl,
    required String callbackUrl,
  }) async {
    if (PlatformInfo.isWeb) {
      final uri = Uri.parse(authorizationUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: "_self",
      );

      if (!launched) {
        throw Exception("Failed to open Paystack");
      }

      return;
    }

    _log("paystack_nav");

    if (!mounted) return;
    await context.push(
      "/paystack",
      extra: PaystackCheckoutArgs(
        authorizationUrl: authorizationUrl,
        callbackUrl: callbackUrl,
        // WHY: Tenant rent success should land on tenant dashboard.
        successRedirect: "/tenant-dashboard",
      ),
    );
  }

  String? _buildCallbackUrl() {
    // WHY: Attach next route so web callbacks can redirect correctly.
    const nextRoute = "/tenant-dashboard";
    if (PlatformInfo.isWeb) {
      return Uri(
        scheme: Uri.base.scheme,
        host: Uri.base.host,
        port: Uri.base.hasPort ? Uri.base.port : null,
        path: "/payment-success",
        queryParameters: {"next": nextRoute},
      ).toString();
    }

    if (AppConstants.paystackCallbackBaseUrl.isEmpty) {
      return null;
    }

    final baseUri = Uri.parse(AppConstants.paystackCallbackBaseUrl);
    // WHY: Preserve scheme/host while appending payment-success path.
    final basePath = baseUri.path;
    final callbackPath = basePath.endsWith("/payment-success")
        ? basePath
        : basePath.isEmpty || basePath == "/"
        ? "/payment-success"
        : "${basePath}/payment-success";
    return baseUri
        .replace(
          path: callbackPath,
          queryParameters: {"next": nextRoute},
        )
        .toString();
  }

  String _extractErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data["error"]?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    }
    return error.toString().replaceAll('Exception:', '').trim();
  }

  Widget _buildSectionError(Object error, _TenantErrorSection section) {
    // WHY: Provide a consistent, friendly error card per section.
    final resolution = _resolveSectionError(error, section);
    return _TenantSectionError(
      title: resolution.title,
      message: resolution.message,
      hint: resolution.hint,
      actionLabel: resolution.actionLabel,
      actionIcon: resolution.actionIcon,
      onAction: resolution.onAction,
    );
  }

  _TenantErrorResolution _resolveSectionError(
    Object error,
    _TenantErrorSection section,
  ) {
    // WHY: Map transport errors into actionable, tenant-friendly guidance.
    final statusCode = error is DioException
        ? error.response?.statusCode
        : null;
    final title = _titleForSection(section);
    final baseMessage = _baseMessageForSection(section);

    if (statusCode == _httpUnauthorized || statusCode == _httpForbidden) {
      return _TenantErrorResolution(
        title: _authErrorTitle,
        message: _authErrorMessage,
        hint: _genericErrorMessage,
        actionLabel: _actionSettingsLabel,
        actionIcon: Icons.settings,
        onAction: () => _openSettingsFromError(section),
      );
    }

    if (statusCode == _httpNotFound) {
      return _TenantErrorResolution(
        title: title,
        message: _missingMessageForSection(section),
        hint: _genericErrorMessage,
        actionLabel: _actionRefreshLabel,
        actionIcon: Icons.refresh,
        onAction: () => _handleSectionRefresh(section),
      );
    }

    if (statusCode == _httpBadRequest) {
      return _TenantErrorResolution(
        title: title,
        message: baseMessage,
        hint: _genericErrorMessage,
        actionLabel: _actionRefreshLabel,
        actionIcon: Icons.refresh,
        onAction: () => _handleSectionRefresh(section),
      );
    }

    return _TenantErrorResolution(
      title: title,
      message: baseMessage,
      hint: _genericErrorMessage,
      actionLabel: _actionRefreshLabel,
      actionIcon: Icons.refresh,
      onAction: () => _handleSectionRefresh(section),
    );
  }

  String _titleForSection(_TenantErrorSection section) {
    // WHY: Keep titles consistent across error cards.
    switch (section) {
      case _TenantErrorSection.status:
        return _statusErrorTitle;
      case _TenantErrorSection.estate:
        return _estateErrorTitle;
      case _TenantErrorSection.profile:
        return _profileErrorTitle;
    }
  }

  String _baseMessageForSection(_TenantErrorSection section) {
    // WHY: Provide a default message when no special case applies.
    switch (section) {
      case _TenantErrorSection.status:
        return _statusErrorMessage;
      case _TenantErrorSection.estate:
        return _estateErrorMessage;
      case _TenantErrorSection.profile:
        return _profileErrorMessage;
    }
  }

  String _missingMessageForSection(_TenantErrorSection section) {
    // WHY: Clarify what is missing so tenants know the next step.
    switch (section) {
      case _TenantErrorSection.status:
        return _missingApplicationMessage;
      case _TenantErrorSection.estate:
        return _missingEstateMessage;
      case _TenantErrorSection.profile:
        return _profileErrorMessage;
    }
  }

  Future<void> _handleSectionRefresh(_TenantErrorSection section) async {
    // WHY: Let tenants retry loading without leaving the screen.
    _log("section_refresh_tap", extra: {"section": section.name});
    await AppRefresh.refreshApp(
      ref: ref,
      source: _refreshSourceForSection(section),
    );
  }

  void _openSettingsFromError(_TenantErrorSection section) {
    // WHY: Settings provides the logout path to recover session errors.
    _log("section_settings_tap", extra: {"section": section.name});
    context.go(_settingsRoute);
  }

  String _refreshSourceForSection(_TenantErrorSection section) {
    // WHY: Keep refresh telemetry stable per section.
    switch (section) {
      case _TenantErrorSection.status:
        return _refreshSourceStatus;
      case _TenantErrorSection.estate:
        return _refreshSourceEstate;
      case _TenantErrorSection.profile:
        return _refreshSourceProfile;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _displayName(UserProfile profile) {
    final parts = [
      profile.firstName?.trim() ?? '',
      profile.middleName?.trim() ?? '',
      profile.lastName?.trim() ?? '',
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? profile.name : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    _log("build");

    final session = ref.watch(authSessionProvider);
    final role = session?.user.role ?? "";
    // WHY: Owners/staff may review tenant submissions from their account.
    final isAdminViewer = role == "business_owner" || role == "staff";

    final profileAsync = ref.watch(userProfileProvider);
    final estateAsync = ref.watch(tenantEstateProvider);
    final applicationAsync = ref.watch(tenantApplicationProvider);
    final summaryAsync = ref.watch(tenantSummaryProvider);
    final application = applicationAsync.asData?.value;
    if (application?.agreementSigned == true && !_agreementSigned) {
      _agreementSigned = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tenant verification"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _log("back_tap");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(_settingsRoute);
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _log("refresh_tap");
          // WHY: Central refresh keeps tenant data in sync across screens.
          await AppRefresh.refreshApp(
            ref: ref,
            source: "tenant_verification_pull",
          );
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isAdminViewer) ...[
              _AdminViewNote(role: role),
              const SizedBox(height: 12),
            ],
            applicationAsync.when(
              data: (application) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summaryAsync.when(
                    data: (summary) => _buildTenantStatusCard(
                      application: application,
                      summary: summary,
                    ),
                    loading: () =>
                        _buildTenantStatusCard(application: application),
                    error: (_, __) =>
                        _buildTenantStatusCard(application: application),
                  ),
                  const SizedBox(height: 12),
                  _buildMiniTimeline(application),
                ],
              ),
              loading: () =>
                  const _InlineLoader(label: "Loading tenant status..."),
              error: (error, _) =>
                  _buildSectionError(error, _TenantErrorSection.status),
            ),
            const SizedBox(height: 16),
            profileAsync.when(
              data: (profile) {
                if (profile == null) {
                  return const Text("Unable to load profile.");
                }
                return _buildProfileSummary(profile);
              },
              loading: () => const _InlineLoader(label: "Loading profile..."),
              error: (error, _) =>
                  _buildSectionError(error, _TenantErrorSection.profile),
            ),
            const SizedBox(height: 16),
            estateAsync.when(
              data: (estate) {
                final rules = estate.tenantRules;
                _syncContactLists(rules);

                final status = (application?.status ?? "").toLowerCase();
                final showForm =
                    application == null ||
                    status == "pending" ||
                    status == "rejected";

                _selectedUnitType ??= estate.unitMix.isNotEmpty
                    ? estate.unitMix.first.unitType
                    : null;
                _selectedRentPeriod ??= estate.unitMix.isNotEmpty
                    ? estate.unitMix.first.rentPeriod
                    : null;

                if (!showForm) {
                  return _buildEstateSummary(
                    estate: estate,
                    application: application,
                  );
                }

                return _buildEstateForm(
                  estate,
                  rules,
                  application: application,
                );
              },
              loading: () => const _InlineLoader(label: "Loading estate..."),
              error: (error, _) =>
                  _buildSectionError(error, _TenantErrorSection.estate),
            ),
            const _HelpFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantStatusCard({
    required business_tenant.BusinessTenantApplication? application,
    business_tenant.TenantSummary? summary,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (application == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          "No tenant application yet. Complete the form below.",
          style: textTheme.bodyMedium,
        ),
      );
    }

    final status = application.status.toLowerCase();
    final paymentStatus = application.paymentStatus.toLowerCase();
    final paidThroughDate = summary?.paidThroughDate ?? application.paidAt;
    final nextDueDate = summary?.nextDueDate;
    final payments = summary?.paymentsSummary;
    final isApproved = status == "approved";
    final isActive = status == "active";
    final isRejected = status == "rejected";
    final isPaid = paymentStatus == "paid";

    final title = isActive
        ? "Tenant active"
        : isApproved
        ? "Approved — payment required"
        : isRejected
        ? "Application rejected"
        : "Application pending";

    final subtitle = isActive
        ? "Your rent payment is confirmed."
        : isApproved
        ? "Pay the rent to activate your tenancy."
        : isRejected
        ? "You can submit a new application."
        : "We are reviewing your references and guarantors.";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(status: status),
              const SizedBox(width: 8),
              Text(title, style: textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _StatusValue(
                label: "Paid through",
                value: paidThroughDate == null
                    ? "Awaiting payment"
                    : _formatDate(paidThroughDate),
              ),
              _StatusValue(
                label: "Next due",
                value: nextDueDate == null
                    ? "Awaiting payment"
                    : _formatDate(nextDueDate),
              ),
              if (payments != null)
                _StatusValue(
                  label: "Paid YTD",
                  value: _formatMoneyKobo(payments.totalPaidKoboYtd),
                ),
              if (payments != null)
                _StatusValue(
                  label: "Payments this year",
                  value: payments.paymentsThisYear.toString(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ReadOnlyRow(label: "Unit", value: application.unitType),
          _ReadOnlyRow(
            label: "Rent",
            value:
                "${_formatRent(application.rentAmount)} / ${application.rentPeriod}",
          ),
          _ReadOnlyRow(
            label: "Move-in",
            value: application.moveInDate == null
                ? "Not set"
                : _formatDate(application.moveInDate!),
          ),
          if (isApproved && !isPaid) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isPaying
                    ? null
                    : () => _startTenantPayment(application: application),
                child: _isPaying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Pay rent"),
              ),
            ),
          ],
          if (isPaid) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _log(
                    "view_receipt",
                    extra: {"applicationId": application.id},
                  );
                  // TODO: wire to receipts page when available.
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text("View payment receipt"),
              ),
            ),
          ],
          if (isApproved || isActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _log("cta_dashboard");
                      context.go('/tenant-dashboard');
                    },
                    child: const Text("Go to dashboard"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _log("cta_view_verification");
                      // Already on verification; keep for explicit affordance.
                    },
                    child: const Text("View verification"),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniTimeline(
    business_tenant.BusinessTenantApplication? application,
  ) {
    final theme = Theme.of(context);
    if (application == null) return const SizedBox.shrink();
    final steps = [
      _TimelineStep(label: "Submitted", done: application.createdAt != null),
      _TimelineStep(
        label: "Approved",
        done:
            application.status.toLowerCase() == "approved" ||
            application.status.toLowerCase() == "active",
      ),
      _TimelineStep(
        label: "Paid",
        done: application.paymentStatus.toLowerCase() == "paid",
      ),
      _TimelineStep(
        label: "Active",
        done: application.status.toLowerCase() == "active",
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: steps
            .map(
              (s) => Column(
                children: [
                  Icon(
                    s.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: s.done
                        ? AppStatusBadgeColors.fromTheme(
                            theme: theme,
                            tone: AppStatusTone.success,
                          ).foreground
                        : theme.colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildEstateSummary({
    required TenantEstate estate,
    required business_tenant.BusinessTenantApplication? application,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Estate details", style: textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          estate.name.isEmpty ? "Assigned estate" : estate.name,
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _ReadOnlyRow(
          label: "Unit mix",
          value: estate.unitMix.isEmpty
              ? "No units configured"
              : "${estate.unitMix.length} types",
        ),
        if (application != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Your selection", style: textTheme.titleSmall),
                const SizedBox(height: 8),
                _ReadOnlyRow(label: "Unit", value: application.unitType),
                _ReadOnlyRow(
                  label: "Rent",
                  value:
                      "${_formatRent(application.rentAmount)} / ${application.rentPeriod}",
                ),
                _ReadOnlyRow(
                  label: "Move-in",
                  value: application.moveInDate == null
                      ? "Not set"
                      : _formatDate(application.moveInDate!),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProfileSummary(UserProfile profile) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Tenant profile", style: textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            "Your verified identity is locked for tenancy checks.",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _ReadOnlyRow(label: "Name", value: _displayName(profile)),
          _ReadOnlyRow(label: "Email", value: profile.email),
          _ReadOnlyRow(
            label: "Phone",
            value: (() {
              // WHY: Format verified phone with the same +234 display style.
              final phone = formatPhoneDisplay(
                profile.phone,
                prefix: _ngPhonePrefix,
                maxDigits: _ngPhoneDigits,
              );
              return phone.isNotEmpty ? phone : "Not provided";
            })(),
          ),
          _ReadOnlyRow(
            label: "NIN",
            value: profile.ninLast4 == null
                ? "Not verified"
                : "**** ${profile.ninLast4}",
          ),
          if (!profile.isNinVerified) ...[
            const SizedBox(height: 8),
            Text(
              "NIN verification is required before submission.",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEstateForm(
    TenantEstate estate,
    BusinessAssetTenantRules rules, {
    business_tenant.BusinessTenantApplication? application,
  }) {
    final textTheme = Theme.of(context).textTheme;

    final unitMix = estate.unitMix;
    final selectedUnit = unitMix.firstWhere(
      (unit) => unit.unitType == _selectedUnitType,
      orElse: () => unitMix.isNotEmpty
          ? unitMix.first
          : BusinessAssetUnitMix(
              unitType: '',
              count: 0,
              rentAmount: 0,
              rentPeriod: 'monthly',
            ),
    );

    final rentPeriods = {
      ..._rentPeriods,
      if (selectedUnit.rentPeriod.isNotEmpty) selectedUnit.rentPeriod,
    }.toList();

    final agreementText = (application?.agreementText.isNotEmpty ?? false)
        ? application!.agreementText
        : estate.agreementText;
    final bool isAgreementMissing =
        rules.requiresAgreementSigned && agreementText.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Estate details", style: textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          estate.name.isEmpty ? "Assigned estate" : estate.name,
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _ReadOnlyRow(
          label: "Unit mix",
          value: unitMix.isEmpty
              ? "No units configured"
              : "${unitMix.length} types",
        ),
        const SizedBox(height: 16),
        Text("Select unit", style: textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedUnitType,
          decoration: const InputDecoration(labelText: "Unit type"),
          items: unitMix
              .map(
                (unit) => DropdownMenuItem(
                  value: unit.unitType,
                  child: Text("${unit.unitType} (${unit.count} units)"),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            _log("unit_select", extra: {"unitType": value});
            setState(() {
              _selectedUnitType = value;
              final match = unitMix.firstWhere(
                (unit) => unit.unitType == value,
                orElse: () => selectedUnit,
              );
              _selectedRentPeriod = match.rentPeriod;
            });
          },
        ),
        const SizedBox(height: 12),
        _ReadOnlyRow(
          label: "Rent amount",
          value: _formatRent(selectedUnit.rentAmount),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedRentPeriod,
          decoration: const InputDecoration(labelText: "Rent period"),
          items: rentPeriods
              .map(
                (period) =>
                    DropdownMenuItem(value: period, child: Text(period)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            _log("rent_period_change", extra: {"rentPeriod": value});
            setState(() => _selectedRentPeriod = value);
          },
        ),
        const SizedBox(height: 12),
        if (isAgreementMissing)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.errorContainer.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "No agreement is attached. Ask your owner to resend the invite with the tenancy agreement.",
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else if (agreementText.isNotEmpty) ...[
          _AgreementCard(
            agreementText: agreementText,
            accepted: _agreementSigned,
            onAccept: _agreementSigned
                ? null
                : () {
                    _log("agreement_accept");
                    setState(() => _agreementSigned = true);
                  },
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _moveInCtrl,
          readOnly: true,
          // WHY: Prevent manual input so all dates come from the picker.
          enableInteractiveSelection: false,
          showCursor: false,
          decoration: const InputDecoration(
            labelText: "Move-in date",
            hintText: "Select a date",
            suffixIcon: Icon(Icons.calendar_today_outlined),
          ),
          onTap: _pickMoveInDate,
        ),
        const SizedBox(height: 20),
        _buildContactsSection(
          title: "References",
          subtitle:
              "Min ${rules.referencesMin}, max ${rules.referencesMax} references.",
          controllers: _referenceCtrls,
          onAdd: rules.referencesMax > _referenceCtrls.length
              ? () => _addContact(_referenceCtrls)
              : null,
          onRemove: rules.referencesMin < _referenceCtrls.length
              ? (index) => _removeContact(_referenceCtrls, index)
              : null,
        ),
        const SizedBox(height: 20),
        _buildContactsSection(
          title: "Guarantors",
          subtitle:
              "Min ${rules.guarantorsMin}, max ${rules.guarantorsMax} guarantors.",
          controllers: _guarantorCtrls,
          onAdd: rules.guarantorsMax > _guarantorCtrls.length
              ? () => _addContact(_guarantorCtrls)
              : null,
          onRemove: rules.guarantorsMin < _guarantorCtrls.length
              ? (index) => _removeContact(_guarantorCtrls, index)
              : null,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting || isAgreementMissing
                ? null
                : () async {
                    final profile = ref.read(userProfileProvider).value;
                    if (profile == null) {
                      _showMessage("Profile not available yet.");
                      return;
                    }
                    await _submitTenantVerification(
                      estate: estate,
                      profile: profile,
                    );
                  },
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Submit verification"),
          ),
        ),
      ],
    );
  }

  Widget _buildContactsSection({
    required String title,
    required String subtitle,
    required List<_ContactControllers> controllers,
    required VoidCallback? onAdd,
    required void Function(int index)? onRemove,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < controllers.length; i++) ...[
          _ContactRow(
            index: i,
            controllers: controllers[i],
            onRemove: onRemove == null ? null : () => onRemove(i),
            onUpload: () => _uploadContactDocument(controllers[i]),
            onClear: controllers[i].documentUrl == null
                ? null
                : () => _clearContactDocument(controllers[i]),
            isUploading: controllers[i].isUploading,
            documentName: controllers[i].documentName,
          ),
          const SizedBox(height: 12),
        ],
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text("Add"),
        ),
      ],
    );
  }
}

class _AdminViewNote extends StatelessWidget {
  final String role;

  const _AdminViewNote({required this.role});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility,
            color: colorScheme.onSecondaryContainer,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "View as admin (${role.replaceAll('_', ' ')}).",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TenantErrorSection { status, estate, profile }

class _TenantErrorResolution {
  final String title;
  final String message;
  final String? hint;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const _TenantErrorResolution({
    required this.title,
    required this.message,
    required this.hint,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });
}

class _TenantSectionError extends StatelessWidget {
  final String title;
  final String message;
  final String? hint;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const _TenantSectionError({
    required this.title,
    required this.message,
    required this.hint,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final hasAction =
        actionLabel != null && onAction != null && actionIcon != null;

    // WHY: Provide a compact, accessible error card with optional retry action.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (hasAction) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final bool done;

  const _TimelineStep({required this.label, required this.done});
}

class _HelpFooter extends StatelessWidget {
  const _HelpFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.help_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Need help with your tenancy? Contact support.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // Placeholder: add deep link to support when available.
            },
            child: const Text("Get help"),
          ),
        ],
      ),
    );
  }
}

// WHY: Centralize contact field copy to avoid inline strings.
class _ContactCopy {
  static const String firstNameLabel = "First name";
  static const String middleNameLabel = "Middle name";
  static const String lastNameLabel = "Last name";
  static const String emailLabel = "Email";
  static const String phoneLabel = "Phone";
  static const String noDocument = "No document uploaded";
  static const String upload = "Upload";
  static const String uploading = "Uploading...";
  static const String remove = "Remove";
}

class _ContactControllers {
  // WHY: Split name fields make validation and display explicit.
  final TextEditingController firstNameCtrl;
  // WHY: Middle name is optional but stored for completeness.
  final TextEditingController middleNameCtrl;
  // WHY: Last name is required for verification checks.
  final TextEditingController lastNameCtrl;
  // WHY: Email is required for contact verification.
  final TextEditingController emailCtrl;
  // WHY: Phone is required and normalized to +234 format.
  final TextEditingController phoneCtrl;
  // WHY: Keep document metadata attached per contact entry.
  String? documentUrl;
  String? documentPublicId;
  String? documentName;
  // WHY: Track upload state per contact to disable repeat uploads.
  bool isUploading = false;

  _ContactControllers({
    required this.firstNameCtrl,
    required this.middleNameCtrl,
    required this.lastNameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
  });

  factory _ContactControllers.empty() {
    return _ContactControllers(
      firstNameCtrl: TextEditingController(),
      middleNameCtrl: TextEditingController(),
      lastNameCtrl: TextEditingController(),
      emailCtrl: TextEditingController(),
      phoneCtrl: TextEditingController(),
    );
  }

  TenantContact? toContact({
    required String normalizedPhone,
    required String normalizedEmail,
  }) {
    // WHY: Build a display name from split fields for legacy name support.
    final firstName = firstNameCtrl.text.trim();
    final middleName = middleNameCtrl.text.trim();
    final lastName = lastNameCtrl.text.trim();
    final displayName = [
      firstName,
      middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(" ");

    if (firstName.isEmpty || lastName.isEmpty) {
      return null;
    }

    return TenantContact(
      name: displayName,
      firstName: firstName,
      middleName: middleName.isEmpty ? null : middleName,
      lastName: lastName,
      email: normalizedEmail,
      phone: normalizedPhone,
      documentUrl: documentUrl,
      documentPublicId: documentPublicId,
    );
  }

  void dispose() {
    firstNameCtrl.dispose();
    middleNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }
}

class _ContactRow extends StatelessWidget {
  final int index;
  final _ContactControllers controllers;
  final VoidCallback? onRemove;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final bool isUploading;
  final String? documentName;

  const _ContactRow({
    required this.index,
    required this.controllers,
    required this.onRemove,
    required this.onUpload,
    required this.onClear,
    required this.isUploading,
    required this.documentName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 640;
            final firstNameField = _ContactTextField(
              controller: controllers.firstNameCtrl,
              label: "${_ContactCopy.firstNameLabel} ${index + 1}",
            );
            final middleNameField = _ContactTextField(
              controller: controllers.middleNameCtrl,
              label: _ContactCopy.middleNameLabel,
            );
            final lastNameField = _ContactTextField(
              controller: controllers.lastNameCtrl,
              label: _ContactCopy.lastNameLabel,
            );

            if (isNarrow) {
              return Column(
                children: [
                  firstNameField,
                  const SizedBox(height: 12),
                  middleNameField,
                  const SizedBox(height: 12),
                  lastNameField,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: firstNameField),
                const SizedBox(width: 12),
                Expanded(child: middleNameField),
                const SizedBox(width: 12),
                Expanded(child: lastNameField),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 640;
            final emailField = _ContactTextField(
              controller: controllers.emailCtrl,
              label: _ContactCopy.emailLabel,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: const [EmailInputFormatter()],
            );
            final phoneField = _ContactTextField(
              controller: controllers.phoneCtrl,
              label: _ContactCopy.phoneLabel,
              keyboardType: TextInputType.phone,
              prefixText: _TenantVerificationScreenState._ngPhonePrefix,
              inputFormatters: const [
                NigerianPhoneDigitsFormatter(
                  maxDigits: _TenantVerificationScreenState._ngPhoneDigits,
                ),
              ],
            );

            if (isNarrow) {
              return Column(
                children: [emailField, const SizedBox(height: 12), phoneField],
              );
            }

            return Row(
              children: [
                Expanded(child: emailField),
                const SizedBox(width: 12),
                Expanded(child: phoneField),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        _ContactDocumentRow(
          isUploading: isUploading,
          documentName: documentName,
          onUpload: onUpload,
          onClear: onClear,
        ),
        if (onRemove != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: _ContactCopy.remove,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _ContactTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;

  const _ContactTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
    this.prefixText,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep contact fields consistent across reference/guarantor sections.
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(labelText: label, prefixText: prefixText),
    );
  }
}

class _ContactDocumentRow extends StatelessWidget {
  final bool isUploading;
  final String? documentName;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;

  const _ContactDocumentRow({
    required this.isUploading,
    required this.documentName,
    required this.onUpload,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDocument = documentName != null && documentName!.trim().isNotEmpty;

    return Row(
      children: [
        Icon(Icons.attach_file, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hasDocument ? documentName! : _ContactCopy.noDocument,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: isUploading ? null : onUpload,
          icon: isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file),
          label: Text(
            isUploading ? _ContactCopy.uploading : _ContactCopy.upload,
          ),
        ),
        if (hasDocument && onClear != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: onClear,
            child: const Text(_ContactCopy.remove),
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final label = status.isEmpty
        ? "unknown"
        : status.replaceAll('_', ' ').toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _AgreementCard extends StatelessWidget {
  final String agreementText;
  final bool accepted;
  final VoidCallback? onAccept;

  const _AgreementCard({
    required this.agreementText,
    required this.accepted,
    this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Tenancy agreement",
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Chip(
                label: Text(accepted ? "Accepted" : "Pending"),
                backgroundColor: accepted
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                labelStyle: theme.textTheme.labelSmall?.copyWith(
                  color: accepted
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(agreementText, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: accepted ? null : onAccept,
              child: Text(
                accepted ? "Agreement accepted" : "Accept & continue",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineLoader extends StatelessWidget {
  final String label;

  const _InlineLoader({required this.label});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(label, style: textTheme.bodySmall),
      ],
    );
  }
}

class _StatusValue extends StatelessWidget {
  final String label;
  final String value;

  const _StatusValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
