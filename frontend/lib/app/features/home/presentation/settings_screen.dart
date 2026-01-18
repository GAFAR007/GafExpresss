/// lib/app/features/home/presentation/settings_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Profile + settings screen with a full account form.
///
/// WHY:
/// - Lets customers update personal details and upgrade to business tiers.
/// - Surfaces saved profile data and keeps settings centralized.
///
/// HOW:
/// - Fetches profile via userProfileProvider.
/// - Prefills controllers when profile loads.
/// - Saves updates through ProfileApi with auth token.
/// ------------------------------------------------------------
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ------------------------------------------------------------
  // CONTROLLERS
  // ------------------------------------------------------------
  // WHY:
  // - Text controllers keep form values stable across rebuilds.
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _companyEmailCtrl = TextEditingController();
  final _companyPhoneCtrl = TextEditingController();
  final _companyAddressCtrl = TextEditingController();
  final _companyWebsiteCtrl = TextEditingController();
  final _companyRegCtrl = TextEditingController();

  // ------------------------------------------------------------
  // UI STATE
  // ------------------------------------------------------------
  // WHY:
  // - Prevent duplicate saves and control conditional sections.
  bool _isSaving = false;
  bool _didPrefill = false;
  String _accountType = 'personal';
  UserProfile? _currentProfile;
  bool _isRefreshing = false;
  Timer? _autoRefreshTimer;
  String? _lastPhoneOtp;

  // WHY: Periodically re-fetch profile so verification badges stay fresh.
  static const Duration _autoRefreshInterval = Duration(seconds: 45);

  // WHY: Nigerian numbers are fixed at +234 and 10 digits for local input.
  static const String _ngPhonePrefix = "+234";
  static const int _ngPhoneDigits = 10;

  // WHY: Normalize pasted values and keep digits-only input consistent.
  static final List<TextInputFormatter> _ngPhoneInputFormatters = [
    _NigerianPhoneDigitsFormatter(maxDigits: _ngPhoneDigits),
  ];

  // WHY: Centralize debug formatting so logs are consistent and easy to scan.
  void _logFlow(String step, String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      "SETTINGS_FLOW",
      "$step | $message",
      extra: extra,
    );
  }

  // WHY: Track account type choices in one place for UI + payloads.
  static const List<Map<String, String>> _accountTypeOptions = [
    {"value": "personal", "label": "Personal"},
    {"value": "sole_proprietorship", "label": "Business Name"},
    {"value": "partnership", "label": "Partnership"},
    {
      "value": "limited_liability_company",
      "label": "Limited Liability Company (Ltd)",
    },
    {
      "value": "public_limited_company",
      "label": "Public Limited Company (Plc)",
    },
    {
      "value": "incorporated_trustees",
      "label": "Incorporated Trustees / NGO",
    },
  ];

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    // WHY: Dispose controllers to avoid memory leaks.
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _companyNameCtrl.dispose();
    _companyEmailCtrl.dispose();
    _companyPhoneCtrl.dispose();
    _companyAddressCtrl.dispose();
    _companyWebsiteCtrl.dispose();
    _companyRegCtrl.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  /// ------------------------------------------------------------
  /// REFRESH HELPERS
  /// ------------------------------------------------------------
  Future<void> _refreshProfile({required String source}) async {
    // WHY: Avoid overlapping refresh calls from pull-to-refresh + auto refresh.
    if (_isRefreshing) {
      AppDebug.log(
        "SETTINGS",
        "Profile refresh skipped",
        extra: {"source": source, "reason": "already_refreshing"},
      );
      return;
    }

    if (_isSaving) {
      AppDebug.log(
        "SETTINGS",
        "Profile refresh skipped",
        extra: {"source": source, "reason": "saving"},
      );
      return;
    }

    _isRefreshing = true;
    _logFlow("REFRESH_START", "Profile refresh start", extra: {"source": source});

    try {
      await ref.refresh(userProfileProvider.future);
      _logFlow("REFRESH_OK", "Profile refresh success", extra: {"source": source});
    } catch (e) {
      _logFlow(
        "REFRESH_FAIL",
        "Profile refresh failed",
        extra: {"source": source, "error": e.toString()},
      );
    } finally {
      _isRefreshing = false;
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _logFlow(
      "AUTO_REFRESH",
      "Auto refresh scheduled",
      extra: {"seconds": _autoRefreshInterval.inSeconds},
    );

    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) async {
      if (!mounted) return;
      await _refreshProfile(source: "auto");
    });
  }

  /// ------------------------------------------------------------
  /// APPLY PROFILE TO FORM
  /// ------------------------------------------------------------
  void _applyProfile(UserProfile profile) {
    // WHY: Avoid re-prefill if we already applied the same profile.
    if (_didPrefill && _currentProfile?.id == profile.id) {
      // WHY: Keep backend verification status in sync without clobbering edits.
      _currentProfile = _currentProfile?.copyWith(
        isEmailVerified: profile.isEmailVerified,
        isPhoneVerified: profile.isPhoneVerified,
      );
      return;
    }

    _logFlow("PREFILL", "Prefilling profile form", extra: {"userId": profile.id});

    _currentProfile = profile;
    _accountType = profile.accountType;

    final split = _splitFullName(
      profile.firstName,
      profile.lastName,
      profile.name,
    );
    _firstNameCtrl.text = split.firstName;
    _lastNameCtrl.text = split.lastName;
    _emailCtrl.text = profile.email;
    _phoneCtrl.text = profile.phone == null
        ? ''
        : _extractNigerianDigits(profile.phone ?? '');
    _companyNameCtrl.text = profile.companyName ?? '';
    _companyEmailCtrl.text = profile.companyEmail ?? '';
    _companyPhoneCtrl.text = profile.companyPhone == null
        ? ''
        : _extractNigerianDigits(profile.companyPhone ?? '');
    _companyAddressCtrl.text = profile.companyAddress ?? '';
    _companyWebsiteCtrl.text = profile.companyWebsite ?? '';
    _companyRegCtrl.text = profile.companyRegistration ?? '';

    _didPrefill = true;

    if (mounted) {
      // WHY: Ensure account type badge + conditional fields update.
      setState(() {});
    }
  }

  /// ------------------------------------------------------------
  /// VERIFICATION HANDLERS
  /// ------------------------------------------------------------
  Future<void> _verifyEmail() async {
    final emailInput = _emailCtrl.text.trim();
    _logFlow("EMAIL_VERIFY_TAP", "Verify email tapped", extra: {"email": emailInput});

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Verify email blocked (missing session)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    // WHY: Avoid sending a verify request without a target email.
    if (emailInput.isEmpty) {
      AppDebug.log("SETTINGS", "Verify email blocked (missing email)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an email address")),
      );
      return;
    }

    try {
      final api = ref.read(profileApiProvider);
      _logFlow("EMAIL_VERIFY_REQUEST", "Requesting email OTP");
      final response = await api.requestEmailVerification(
        token: session.token,
        email: emailInput,
      );
      final recipient =
          response["email"]?.toString().trim() ?? _emailCtrl.text.trim();
      _logFlow(
        "EMAIL_VERIFY_SENT",
        "Email OTP sent",
        extra: {"email": recipient},
      );

      AppDebug.log(
        "SETTINGS",
        "Email verification sent",
        extra: {"email": recipient},
      );

      if (!mounted) return;
      if (recipient.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Code sent to $recipient")),
        );
      }

      if (!mounted) return;
      final code = await _openCodeDialog(
        title: "Email verification",
        message: "Enter the code sent to your email address.",
      );
      if (code == null) {
        _logFlow("EMAIL_VERIFY_CANCEL", "User cancelled email code input");
        return;
      }

      _logFlow("EMAIL_VERIFY_CONFIRM", "Confirming email OTP");
      await api.confirmEmailVerification(token: session.token, code: code);

      // WHY: Refresh profile to update verification badges.
      ref.invalidate(userProfileProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email verified successfully")),
      );
    } catch (e) {
      _logFlow(
        "EMAIL_VERIFY_FAIL",
        "Email verification failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Email verification failed. ${_friendlyErrorMessage(e)}",
          ),
        ),
      );
    }
  }

  Future<void> _verifyPhone() async {
    _logFlow("PHONE_VERIFY_TAP", "Verify phone tapped");

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Verify phone blocked (missing session)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    final phoneDigits = _phoneCtrl.text.trim();
    final normalizedPhone = _normalizeNigerianPhone(phoneDigits);

    if (phoneDigits.isEmpty) {
      _logFlow("PHONE_VERIFY_BLOCK", "Missing phone number");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a phone number first")),
      );
      return;
    }

    if (normalizedPhone == null) {
      _logFlow("PHONE_VERIFY_BLOCK", "Invalid phone number");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter 10 digits after +234 (e.g. 8012345678)"),
        ),
      );
      return;
    }

    // WHY: Keep normalized format for API + SMS without mutating digits-only input.

    try {
      final api = ref.read(profileApiProvider);
      _logFlow("PHONE_VERIFY_REQUEST", "Requesting phone OTP");
      final response = await api.requestPhoneVerification(
        token: session.token,
        phone: normalizedPhone,
      );

      final debugCode = response["code"]?.toString().trim();
      if (debugCode != null && debugCode.isNotEmpty) {
        AppDebug.log(
          "SETTINGS",
          "Phone OTP debug code received",
          extra: {"length": debugCode.length},
        );
        _lastPhoneOtp = debugCode;
        if (mounted) {
          // WHY: Dev-only helper when DEBUG_SHOW_OTP=true.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("DEV OTP: $debugCode")),
          );
        }
      }

      if (!mounted) return;
      final code = await _openCodeDialog(
        title: "Phone verification",
        message: "Enter the OTP sent to your phone number.",
      );
      if (code == null) {
        _logFlow("PHONE_VERIFY_CANCEL", "User cancelled phone code input");
        return;
      }

      _logFlow("PHONE_VERIFY_CONFIRM", "Confirming phone OTP");
      await api.confirmPhoneVerification(token: session.token, code: code);

      ref.invalidate(userProfileProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone verified successfully")),
      );
    } catch (e) {
      _logFlow(
        "PHONE_VERIFY_FAIL",
        "Phone verification failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Phone verification failed. ${_friendlyErrorMessage(e)}",
          ),
        ),
      );
    }
  }

  Future<String?> _openCodeDialog({
    required String title,
    required String message,
  }) async {
    _logFlow("OTP_SHEET_OPEN", "Open verification sheet", extra: {"title": title});
    String codeValue = '';

    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                if (_lastPhoneOtp != null &&
                    _lastPhoneOtp!.isNotEmpty &&
                    title.toLowerCase().contains("phone")) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bug_report,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "DEV OTP: $_lastPhoneOtp",
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    codeValue = value;
                  },
                  decoration: const InputDecoration(
                    labelText: "Verification code",
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _logFlow("OTP_SHEET_CANCEL", "Cancel tapped");
                          Navigator.of(context).pop();
                        },
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final code = codeValue.trim();
                          Navigator.of(context).pop(code.isEmpty ? null : code);
                        },
                        child: const Text("Verify"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null || result.isEmpty) {
      _logFlow("OTP_SHEET_DISMISS", "Verification sheet dismissed");
      return null;
    }

    return result;
  }

  /// ------------------------------------------------------------
  /// SAVE HANDLER
  /// ------------------------------------------------------------
  Future<void> _onSavePressed() async {
    if (_isSaving) {
      AppDebug.log("SETTINGS", "Save ignored (already saving)");
      return;
    }

    _logFlow("SAVE_TAP", "Save tapped");

    final session = ref.read(authSessionProvider);
    if (session == null) {
      _logFlow("SAVE_BLOCK", "Missing session");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() => _isSaving = true);

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final fullName = "$firstName $lastName".trim();
    final phoneDigits = _phoneCtrl.text.trim();
    final normalizedPhone = _normalizeNigerianPhone(phoneDigits);
    final companyPhoneDigits = _companyPhoneCtrl.text.trim();
    final normalizedCompanyPhone =
        _normalizeNigerianPhone(companyPhoneDigits);

    if (phoneDigits.isNotEmpty && normalizedPhone == null) {
      _logFlow("SAVE_BLOCK", "Invalid phone number");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter 10 digits after +234 for Nigerian numbers"),
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    if (companyPhoneDigits.isNotEmpty && normalizedCompanyPhone == null) {
      _logFlow("SAVE_BLOCK", "Invalid company phone");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Company phone must be 10 digits after +234"),
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    // WHY: Verification flags should reflect backend truth, not local UI state.
    final latestProfile = ref.read(userProfileProvider).value ?? _currentProfile;

    final profile = UserProfile(
      id: _currentProfile?.id ?? session.user.id,
      name: fullName.isEmpty ? session.user.name : fullName,
      firstName: firstName.isEmpty ? null : firstName,
      lastName: lastName.isEmpty ? null : lastName,
      email: _emailCtrl.text.trim().isEmpty
          ? session.user.email
          : _emailCtrl.text.trim(),
      role: _currentProfile?.role ?? session.user.role,
      accountType: _accountType,
      isEmailVerified: latestProfile?.isEmailVerified ?? false,
      isPhoneVerified: latestProfile?.isPhoneVerified ?? false,
      // WHY: Send normalized +234 numbers to the backend.
      phone: normalizedPhone ?? '',
      companyName: _companyNameCtrl.text.trim(),
      companyEmail: _companyEmailCtrl.text.trim(),
      companyPhone: normalizedCompanyPhone ?? '',
      companyAddress: _companyAddressCtrl.text.trim(),
      companyWebsite: _companyWebsiteCtrl.text.trim(),
      companyRegistration: _companyRegCtrl.text.trim(),
    );

    try {
      final api = ref.read(profileApiProvider);
      _logFlow("SAVE_REQUEST", "Saving profile");
      final updated = await api.updateProfile(
        token: session.token,
        profile: profile,
      );

      // WHY: Refresh cached profile so other screens stay in sync.
      ref.invalidate(userProfileProvider);

      _applyProfile(updated);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully")),
      );
    } catch (e) {
      _logFlow("SAVE_FAIL", "Save failed", extra: {"error": e.toString()});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Update failed. ${_friendlyErrorMessage(e)}")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// ------------------------------------------------------------
  /// SECTION HELPERS
  /// ------------------------------------------------------------
  bool get _hasBusinessInfo {
    return _companyNameCtrl.text.trim().isNotEmpty ||
        _companyEmailCtrl.text.trim().isNotEmpty ||
        _companyPhoneCtrl.text.trim().isNotEmpty ||
        _companyAddressCtrl.text.trim().isNotEmpty ||
        _companyWebsiteCtrl.text.trim().isNotEmpty ||
        _companyRegCtrl.text.trim().isNotEmpty;
  }

  bool get _showBusinessFields {
    return _accountType != 'personal' || _hasBusinessInfo;
  }

  String _initialsForProfile(UserProfile profile) {
    final first = profile.firstName?.trim() ?? '';
    final last = profile.lastName?.trim() ?? '';
    final combined = "$first $last".trim();
    if (combined.isEmpty) return 'GU';
    final parts = combined.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return "${parts.first.characters.first}${parts.last.characters.first}"
        .toUpperCase();
  }

  /// ------------------------------------------------------------
  /// ACCOUNT TYPE LABEL
  /// ------------------------------------------------------------
  /// WHY:
  /// - Keep UI-friendly labels for account types stored as enums.
  String _accountTypeLabel(String value) {
    for (final option in _accountTypeOptions) {
      if (option["value"] == value) {
        return option["label"] ?? value;
      }
    }
    return value.replaceAll('_', ' ').toUpperCase();
  }

  /// ------------------------------------------------------------
  /// FULL NAME SPLIT
  /// ------------------------------------------------------------
  /// WHY:
  /// - Older profiles may only store a full name.
  _SplitName _splitFullName(
    String? firstName,
    String? lastName,
    String? fullName,
  ) {
    final cleanFirst = (firstName ?? '').trim();
    final cleanLast = (lastName ?? '').trim();

    if (cleanFirst.isNotEmpty || cleanLast.isNotEmpty) {
      return _SplitName(cleanFirst, cleanLast);
    }

    final cleanFull = (fullName ?? '').trim();
    if (cleanFull.isEmpty) {
      return const _SplitName('', '');
    }

    final parts = cleanFull.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) {
      return _SplitName(parts.first, '');
    }

    return _SplitName(parts.first, parts.sublist(1).join(' '));
  }

  /// ------------------------------------------------------------
  /// PHONE NORMALIZATION
  /// ------------------------------------------------------------
  /// WHY:
  /// - Ensure phone follows Nigerian +234 format for OTP delivery.
  String? _normalizeNigerianPhone(String input) {
    final raw = input.replaceAll(RegExp(r'\s+'), '').trim();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final e164 = RegExp(r'^\+234\d{10}$');
    final local = RegExp(r'^0\d{10}$');
    final plain = RegExp(r'^234\d{10}$');
    final digitsOnly = RegExp(r'^\d{10}$');

    if (e164.hasMatch(raw)) return raw;
    if (local.hasMatch(raw)) return '+234${raw.substring(1)}';
    if (plain.hasMatch(raw)) return '+$raw';
    if (digitsOnly.hasMatch(digits)) return '+234$digits';

    return null;
  }

  /// WHY: Show digits-only input while keeping +234 in the UI prefix.
  String _extractNigerianDigits(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('234') && digits.length >= 13) {
      return digits.substring(3, 13);
    }
    if (digits.startsWith('0') && digits.length == 11) {
      return digits.substring(1);
    }
    if (digits.length <= _ngPhoneDigits) {
      return digits;
    }
    return digits.substring(0, _ngPhoneDigits);
  }

  /// ------------------------------------------------------------
  /// FRIENDLY ERROR MESSAGES
  /// ------------------------------------------------------------
  /// WHY:
  /// - Replace raw Dio errors with short, user-friendly hints.
  String _friendlyErrorMessage(Object error) {
    final raw = error.toString();

    if (raw.contains("Phone number already in use")) {
      return "This phone number is already linked to another account.";
    }
    if (raw.contains("Email already registered")) {
      return "This email is already registered.";
    }
    if (raw.contains("SMS delivery failed")) {
      return "SMS could not be delivered. Check provider setup.";
    }
    if (raw.contains("Invalid Nigerian phone number")) {
      return "Enter 10 digits after +234.";
    }
    if (raw.contains("Verification code expired")) {
      return "Code expired. Request a new one.";
    }
    if (raw.contains("Invalid verification code")) {
      return "Code is incorrect. Try again.";
    }
    if (raw.contains("Session expired")) {
      return "Session expired. Please sign in again.";
    }

    // WHY: Avoid dumping long exceptions to users.
    return "Please try again.";
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
      ),
    );
  }

  Widget _buildFieldWithAction({
    required TextEditingController controller,
    required String label,
    required String actionLabel,
    required bool isVerified,
    required VoidCallback onActionTap,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    bool readOnly = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildTextField(
            controller: controller,
            label: label,
            hint: hint,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            prefixText: prefixText,
            readOnly: readOnly,
          ),
        ),
        const SizedBox(width: 12),
        _buildVerificationButton(
          isVerified: isVerified,
          label: actionLabel,
          onTap: onActionTap,
        ),
      ],
    );
  }

  Widget _buildVerificationButton({
    required bool isVerified,
    required String label,
    required VoidCallback onTap,
  }) {
    if (isVerified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Text(
              "Verified",
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return OutlinedButton(
      onPressed: onTap,
      child: Text(label),
    );
  }

  Widget _buildProfileCard(UserProfile profile) {
    final split = _splitFullName(
      profile.firstName,
      profile.lastName,
      profile.name,
    );
    final displayName = "${split.firstName} ${split.lastName}".trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              _initialsForProfile(profile),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isEmpty ? "Guest user" : displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.email,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _accountTypeLabel(profile.accountType),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("SETTINGS", "build()", extra: {"isSaving": _isSaving});

    // WHY: Listen in build for provider updates (initState is too early).
    ref.listen<AsyncValue<UserProfile?>>(userProfileProvider, (prev, next) {
      next.when(
        data: (profile) {
          if (profile == null) {
            AppDebug.log("SETTINGS", "Profile load returned null");
            return;
          }
          _applyProfile(profile);
        },
        loading: () {
          AppDebug.log("SETTINGS", "Profile loading");
        },
        error: (error, _) {
          AppDebug.log(
            "SETTINGS",
            "Profile load failed",
            extra: {"error": error.toString()},
          );
        },
      );
    });

    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile & Settings"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("SETTINGS", "Back tapped");
            // WHY: Prefer popping if possible, otherwise return home.
            if (context.canPop()) {
              context.pop();
              return;
            }
            AppDebug.log("SETTINGS", "Navigate -> /home");
            context.go('/home');
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshProfile(source: "pull_to_refresh"),
        child: profileAsync.when(
          data: (profile) {
            // WHY: Fallback to a minimal profile if API returns null.
            final session = ref.read(authSessionProvider);
            final fallbackProfile = session == null
                ? UserProfile(
                    id: '',
                    name: '',
                    firstName: '',
                    lastName: '',
                    email: '',
                    role: 'customer',
                    accountType: 'personal',
                    isEmailVerified: false,
                    isPhoneVerified: false,
                  )
                : UserProfile(
                    id: session.user.id,
                    name: session.user.name,
                    firstName: _splitFullName(null, null, session.user.name)
                        .firstName,
                    lastName: _splitFullName(null, null, session.user.name)
                        .lastName,
                    email: session.user.email,
                    role: session.user.role,
                    accountType: _accountType,
                    isEmailVerified: false,
                    isPhoneVerified: false,
                  );

            final activeProfile = profile ?? _currentProfile ?? fallbackProfile;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileCard(activeProfile),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    "Personal details",
                    "Keep your account contact info up to date.",
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _firstNameCtrl,
                    label: "First name",
                    hint: "Your first name",
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _lastNameCtrl,
                    label: "Last name",
                    hint: "Your last name",
                  ),
                  const SizedBox(height: 12),
                  _buildFieldWithAction(
                    controller: _emailCtrl,
                    label: "Email address",
                    actionLabel: "Verify",
                    isVerified: activeProfile.isEmailVerified,
                    onActionTap: _verifyEmail,
                    hint: "Your email",
                    // WHY: Allow edits only until the backend confirms verification.
                    readOnly: activeProfile.isEmailVerified,
                  ),
                  const SizedBox(height: 12),
                  _buildFieldWithAction(
                    controller: _phoneCtrl,
                    label: "Phone number",
                    actionLabel: "Verify",
                    isVerified: activeProfile.isPhoneVerified,
                    onActionTap: _verifyPhone,
                    hint: "8012345678",
                    keyboardType: TextInputType.phone,
                    // WHY: Keep phone input strict and prefix country code in UI.
                    inputFormatters: _ngPhoneInputFormatters,
                    prefixText: _ngPhonePrefix,
                  ),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    "Account type",
                    "Upgrade your account to unlock business features.",
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _accountType,
                    decoration: const InputDecoration(labelText: "Account type"),
                    items: _accountTypeOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option["value"],
                            child: Text(option["label"] ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            AppDebug.log(
                              "SETTINGS",
                              "Account type changed",
                              extra: {"type": value},
                            );
                            setState(() => _accountType = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.workspace_premium,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Upgrade to a registered business type for team tools and priority support.",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showBusinessFields) ...[
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      "Controlled business profile",
                      "Add company details for invoices and approvals.",
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _companyNameCtrl,
                      label: "Company name",
                      hint: "Your business name",
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _companyEmailCtrl,
                      label: "Company email",
                      hint: "billing@company.com",
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _companyPhoneCtrl,
                      label: "Company phone",
                      hint: "8012345678",
                      keyboardType: TextInputType.phone,
                      // WHY: Enforce digits-only input for Nigerian numbers.
                      inputFormatters: _ngPhoneInputFormatters,
                      prefixText: _ngPhonePrefix,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _companyAddressCtrl,
                      label: "Company address",
                      hint: "Street, city, state",
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _companyWebsiteCtrl,
                      label: "Company website",
                      hint: "https://company.com",
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _companyRegCtrl,
                      label: "Registration ID",
                      hint: "CAC / RC / Tax ID",
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _onSavePressed,
                      child: Text(_isSaving ? "Saving..." : "Save changes"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () async {
                              AppDebug.log("SETTINGS", "Logout tapped");
                              await ref
                                  .read(authSessionProvider.notifier)
                                  .logout();

                              if (!context.mounted) return;
                              AppDebug.log("SETTINGS", "Navigate -> /login");
                              context.go("/login");
                            },
                      icon: const Icon(Icons.logout),
                      label: const Text("Logout"),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) {
            AppDebug.log(
              "SETTINGS",
              "Profile screen error",
              extra: {"error": error.toString()},
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Unable to load profile right now."),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        AppDebug.log("SETTINGS", "Retry profile fetch tapped");
                        ref.invalidate(userProfileProvider);
                      },
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// PHONE INPUT FORMATTER
/// ------------------------------------------------------------
/// WHY:
/// - Keep phone fields digits-only while supporting pasted +234/0 prefixes.
class _NigerianPhoneDigitsFormatter extends TextInputFormatter {
  final int maxDigits;

  const _NigerianPhoneDigitsFormatter({required this.maxDigits});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // WHY: Strip non-digit characters so the UI only stores numbers.
    final rawDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var digits = rawDigits;

    // WHY: Remove common Nigerian prefixes when pasted.
    if (digits.startsWith('234')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('0') && digits.length == maxDigits + 1) {
      digits = digits.substring(1);
    }

    if (digits.length > maxDigits) {
      digits = digits.substring(0, maxDigits);
    }

    // WHY: Keep cursor at the end for predictable input with +234 prefix.
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// ------------------------------------------------------------
/// NAME SPLIT MODEL
/// ------------------------------------------------------------
/// WHY:
/// - Keeps helper return values explicit and readable.
class _SplitName {
  final String firstName;
  final String lastName;

  const _SplitName(this.firstName, this.lastName);
}
