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

import 'package:flutter/material.dart';
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
    super.dispose();
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

    AppDebug.log("SETTINGS", "Prefilling profile form");

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
    _phoneCtrl.text = profile.phone ?? '';
    _companyNameCtrl.text = profile.companyName ?? '';
    _companyEmailCtrl.text = profile.companyEmail ?? '';
    _companyPhoneCtrl.text = profile.companyPhone ?? '';
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
    AppDebug.log("SETTINGS", "Verify email tapped");

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Verify email blocked (missing session)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    try {
      final api = ref.read(profileApiProvider);
      final response = await api.requestEmailVerification(token: session.token);
      final recipient =
          response["email"]?.toString().trim() ?? _emailCtrl.text.trim();

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
      if (code == null) return;

      await api.confirmEmailVerification(token: session.token, code: code);

      // WHY: Refresh profile to update verification badges.
      ref.invalidate(userProfileProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email verified successfully")),
      );
    } catch (e) {
      AppDebug.log("SETTINGS", "Verify email failed", extra: {"error": e.toString()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Email verification failed: $e")),
      );
    }
  }

  Future<void> _verifyPhone() async {
    AppDebug.log("SETTINGS", "Verify phone tapped");

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Verify phone blocked (missing session)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    final phone = _phoneCtrl.text.trim();
    final normalizedPhone = _normalizeNigerianPhone(phone);

    if (phone.isEmpty) {
      AppDebug.log("SETTINGS", "Verify phone blocked (missing phone)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a phone number first")),
      );
      return;
    }

    if (normalizedPhone == null) {
      AppDebug.log("SETTINGS", "Verify phone blocked (invalid phone)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Use format +234XXXXXXXXXX for Nigerian numbers"),
        ),
      );
      return;
    }

    // WHY: Keep normalized format for API + SMS.
    _phoneCtrl.text = normalizedPhone;

    try {
      final api = ref.read(profileApiProvider);
      await api.requestPhoneVerification(
        token: session.token,
        phone: normalizedPhone,
      );

      if (!mounted) return;
      final code = await _openCodeDialog(
        title: "Phone verification",
        message: "Enter the OTP sent to your phone number.",
      );
      if (code == null) return;

      await api.confirmPhoneVerification(token: session.token, code: code);

      ref.invalidate(userProfileProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone verified successfully")),
      );
    } catch (e) {
      AppDebug.log("SETTINGS", "Verify phone failed", extra: {"error": e.toString()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Phone verification failed: $e")),
      );
    }
  }

  Future<String?> _openCodeDialog({
    required String title,
    required String message,
  }) async {
    AppDebug.log("SETTINGS", "Open verification dialog", extra: {"title": title});

    final controller = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Verification code"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final code = controller.text.trim();
                Navigator.of(context).pop(code.isEmpty ? null : code);
              },
              child: const Text("Verify"),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || result.isEmpty) {
      AppDebug.log("SETTINGS", "Verification dialog dismissed");
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

    AppDebug.log("SETTINGS", "Save tapped");

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Save blocked (missing session)");
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
    final normalizedPhone = _normalizeNigerianPhone(_phoneCtrl.text);

    if (_phoneCtrl.text.trim().isNotEmpty && normalizedPhone == null) {
      AppDebug.log("SETTINGS", "Save blocked (invalid phone)");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter a valid Nigerian phone number (+234XXXXXXXXXX)"),
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    if (normalizedPhone != null) {
      // WHY: Normalize to E.164 so backend + SMS are consistent.
      _phoneCtrl.text = normalizedPhone;
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
      phone: _phoneCtrl.text.trim(),
      companyName: _companyNameCtrl.text.trim(),
      companyEmail: _companyEmailCtrl.text.trim(),
      companyPhone: _companyPhoneCtrl.text.trim(),
      companyAddress: _companyAddressCtrl.text.trim(),
      companyWebsite: _companyWebsiteCtrl.text.trim(),
      companyRegistration: _companyRegCtrl.text.trim(),
    );

    try {
      final api = ref.read(profileApiProvider);
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
      AppDebug.log("SETTINGS", "Save failed", extra: {"error": e.toString()});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Update failed: $e")),
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
    final e164 = RegExp(r'^\+234\d{10}$');
    final local = RegExp(r'^0\d{10}$');
    final plain = RegExp(r'^234\d{10}$');

    if (e164.hasMatch(raw)) return raw;
    if (local.hasMatch(raw)) return '+234${raw.substring(1)}';
    if (plain.hasMatch(raw)) return '+$raw';

    return null;
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
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
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
      body: profileAsync.when(
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
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                _buildFieldWithAction(
                  controller: _phoneCtrl,
                  label: "Phone number",
                  actionLabel: "Verify",
                  isVerified: activeProfile.isPhoneVerified,
                  onActionTap: _verifyPhone,
                  hint: "e.g. +2348012345678",
                  keyboardType: TextInputType.phone,
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
                      Icon(Icons.workspace_premium, color: Colors.orange.shade700),
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
                    hint: "+234 800 000 0000",
                    keyboardType: TextInputType.phone,
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          AppDebug.log(
            "SETTINGS",
            "Profile screen error",
            extra: {"error": error.toString()},
          );
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
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
            ),
          );
        },
      ),
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
