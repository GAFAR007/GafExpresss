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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_model.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_providers.dart';

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
  String? _selectedUnitType;
  String? _selectedRentPeriod;
  String? _lastRulesKey;

  // WHY: Allow tenant to pick a rent cadence (backend validates if needed).
  static const List<String> _rentPeriods = ["monthly", "quarterly", "yearly"];

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
    // WHY: Show readable NGN values without relying on cents formatting.
    final value = amount.toStringAsFixed(2);
    final parts = value.split(".");
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ",",
    );
    return "NGN $whole.${parts.length > 1 ? parts[1] : '00'}";
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$year-$month-$day";
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

    if (estate.tenantRules.requiresAgreementSigned && !_agreementSigned) {
      _log("submit_block_agreement_required");
      _showMessage("Agreement must be signed before verification.");
      return;
    }

    final references = _referenceCtrls
        .map((ctrl) => ctrl.toContact())
        .where((contact) => contact != null)
        .cast<TenantContact>()
        .toList();
    final guarantors = _guarantorCtrls
        .map((ctrl) => ctrl.toContact())
        .where((contact) => contact != null)
        .cast<TenantContact>()
        .toList();

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(tenantVerificationApiProvider);
      _log(
        "submit_request",
        extra: {
          "unitType": unitType,
          "references": references.length,
          "guarantors": guarantors.length,
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
      );

      _log("submit_success");

      if (!mounted) return;
      _showMessage("Tenant verification submitted successfully.");
      context.pop();
    } catch (error) {
      final message = _extractErrorMessage(error);
      _log("submit_fail", extra: {"error": message});
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
            context.go('/settings');
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _log("refresh_tap");
          ref.invalidate(tenantEstateProvider);
          ref.invalidate(userProfileProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isAdminViewer) ...[
              _AdminViewNote(role: role),
              const SizedBox(height: 12),
            ],
            profileAsync.when(
              data: (profile) {
                if (profile == null) {
                  return const Text("Unable to load profile.");
                }
                return _buildProfileSummary(profile);
              },
              loading: () => const _InlineLoader(label: "Loading profile..."),
              error: (error, _) =>
                  Text("Profile error: ${_extractErrorMessage(error)}"),
            ),
            const SizedBox(height: 16),
            estateAsync.when(
              data: (estate) {
                final rules = estate.tenantRules;
                _syncContactLists(rules);

                _selectedUnitType ??= estate.unitMix.isNotEmpty
                    ? estate.unitMix.first.unitType
                    : null;
                _selectedRentPeriod ??= estate.unitMix.isNotEmpty
                    ? estate.unitMix.first.rentPeriod
                    : null;

                return _buildEstateForm(estate, rules);
              },
              loading: () => const _InlineLoader(label: "Loading estate..."),
              error: (error, _) =>
                  Text("Estate error: ${_extractErrorMessage(error)}"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSummary(UserProfile profile) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
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
          value: profile.phone?.isNotEmpty == true
              ? profile.phone!
              : "Not provided",
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
    );
  }

  Widget _buildEstateForm(TenantEstate estate, BusinessAssetTenantRules rules) {
    final colorScheme = Theme.of(context).colorScheme;
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
          value: _selectedUnitType,
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
          value: _selectedRentPeriod,
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
        TextField(
          controller: _moveInCtrl,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: "Move-in date",
            hintText: "Select a date",
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
        Row(
          children: [
            Checkbox(
              value: _agreementSigned,
              onChanged: (value) {
                _log("agreement_toggle", extra: {"value": value});
                setState(() => _agreementSigned = value ?? false);
              },
            ),
            Expanded(
              child: Text(
                "I confirm the tenancy agreement is signed.",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting
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

class _ContactControllers {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;

  _ContactControllers({required this.nameCtrl, required this.phoneCtrl});

  factory _ContactControllers.empty() {
    return _ContactControllers(
      nameCtrl: TextEditingController(),
      phoneCtrl: TextEditingController(),
    );
  }

  TenantContact? toContact() {
    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    if (name.isEmpty) return null;
    return TenantContact(name: name, phone: phone.isEmpty ? null : phone);
  }

  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
  }
}

class _ContactRow extends StatelessWidget {
  final int index;
  final _ContactControllers controllers;
  final VoidCallback? onRemove;

  const _ContactRow({
    required this.index,
    required this.controllers,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final _ = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controllers.nameCtrl,
            decoration: InputDecoration(labelText: "Name ${index + 1}"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controllers.phoneCtrl,
            decoration: const InputDecoration(labelText: "Phone"),
            keyboardType: TextInputType.phone,
          ),
        ),
        if (onRemove != null) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: "Remove",
          ),
        ],
      ],
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
