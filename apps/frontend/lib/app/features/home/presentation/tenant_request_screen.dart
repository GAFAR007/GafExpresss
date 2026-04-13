/// lib/app/features/home/presentation/tenant_request_screen.dart
/// --------------------------------------------------------------
/// WHAT:
/// - Public tenant request intake screen.
///
/// WHY:
/// - Lets a tenant open a copied request link without signing in.
/// - Collects identity + unit choice in a lightweight public form.
///
/// HOW:
/// - Loads link context from the token in the URL.
/// - Lets the tenant enter first/last name, NIN, DOB, and identity proof.
/// - Submits the request to the backend using multipart form data.
/// --------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/tenant_document_picker.dart';
import 'package:frontend/app/features/home/presentation/tenant_request_providers.dart';
import 'package:frontend/app/features/home/presentation/tenant_request_model.dart';

class TenantRequestScreen extends ConsumerStatefulWidget {
  final String token;

  const TenantRequestScreen({super.key, required this.token});

  @override
  ConsumerState<TenantRequestScreen> createState() =>
      _TenantRequestScreenState();
}

class _TenantRequestScreenState extends ConsumerState<TenantRequestScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _ninCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String? _selectedUnitType;
  DateTime? _selectedDob;
  PickedDocumentData? _pickedDocument;
  bool _isSubmitting = false;
  String? _error;
  bool _submitted = false;
  String? _submittedApplicationId;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _ninCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  void _log(String message, {Map<String, dynamic>? extra}) {
    AppDebug.log('TENANT_REQUEST', message, extra: extra);
  }

  Future<void> _pickDob(BuildContext context) async {
    final initialDate =
        _selectedDob ?? DateTime.now().subtract(const Duration(days: 365 * 21));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;

    setState(() {
      _selectedDob = picked;
      _dobCtrl.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickDocument() async {
    _log('document_pick_tap');
    final picked = await pickTenantDocument();
    if (picked == null) {
      _log('document_pick_cancel');
      return;
    }

    setState(() => _pickedDocument = picked);
  }

  Future<void> _submit(TenantRequestLinkContext requestContext) async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final nin = _ninCtrl.text.trim();
    final unitType =
        (_selectedUnitType?.trim().isNotEmpty == true
                ? _selectedUnitType
                : (requestContext.unitMix.isNotEmpty
                      ? requestContext.unitMix.first.unitType
                      : null))
            ?.trim() ??
        '';

    if (firstName.isEmpty) {
      setState(() => _error = 'First name is required');
      return;
    }
    if (lastName.isEmpty) {
      setState(() => _error = 'Last name is required');
      return;
    }
    if (nin.isEmpty || nin.replaceAll(RegExp(r'\s+'), '').length != 11) {
      setState(() => _error = 'Enter an 11-digit NIN');
      return;
    }
    if (_selectedDob == null) {
      setState(() => _error = 'Select your date of birth');
      return;
    }
    if (_pickedDocument == null) {
      setState(() => _error = 'Upload a means-of-verification ID');
      return;
    }
    if (unitType.isEmpty) {
      setState(() => _error = 'Select the unit you want to rent');
      return;
    }

    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    _log(
      'submit_start',
      extra: {
        'estateAssetId': requestContext.estateAssetId,
        'unitType': unitType,
      },
    );

    try {
      final api = ref.read(tenantRequestApiProvider);
      final application = await api.submitRequest(
        token: widget.token,
        firstName: firstName,
        lastName: lastName,
        dob: _selectedDob!,
        nin: nin,
        unitType: unitType,
        document: _pickedDocument!,
      );

      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submittedApplicationId = application.id;
      });

      _log('submit_success', extra: {'applicationId': application.id});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request submitted successfully.')),
      );
    } catch (error) {
      _log('submit_fail', extra: {'error': error.toString()});
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('token is required')) {
      return 'This request link is missing a token.';
    }
    if (message.contains('has expired')) {
      return 'This request link has expired. Ask for a fresh link.';
    }
    if (message.contains('not found')) {
      return 'This request link is invalid or expired.';
    }
    if (message.contains('first name')) {
      return 'First name is required.';
    }
    if (message.contains('last name')) {
      return 'Last name is required.';
    }
    if (message.contains('nin')) {
      return 'Enter an 11-digit NIN.';
    }
    if (message.contains('dob')) {
      return 'Select a date of birth.';
    }
    if (message.contains('document')) {
      return 'Upload a means-of-verification ID.';
    }
    if (message.contains('unit type')) {
      return 'Select the unit you want to rent.';
    }
    return 'Unable to submit your request. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      'TENANT_REQUEST',
      'build()',
      extra: {'hasToken': widget.token.trim().isNotEmpty},
    );

    final contextAsync = ref.watch(
      tenantRequestLinkContextProvider(widget.token),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Tenant request')),
      body: SafeArea(
        child: contextAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 80),
                _StateCard(
                  title: 'Request link unavailable',
                  subtitle: _friendlyError(error),
                  actionLabel: 'Retry',
                  onAction: () {
                    ref.invalidate(
                      tenantRequestLinkContextProvider(widget.token),
                    );
                  },
                ),
              ],
            );
          },
          data: (requestContext) {
            final effectiveUnitType =
                _selectedUnitType ??
                (requestContext.unitMix.isNotEmpty
                    ? requestContext.unitMix.first.unitType
                    : null);
            BusinessAssetUnitMix? selectedUnit;
            if (effectiveUnitType != null) {
              for (final unit in requestContext.unitMix) {
                if (unit.unitType == effectiveUnitType) {
                  selectedUnit = unit;
                  break;
                }
              }
            }

            if (_submitted) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 40),
                  _SuccessCard(
                    title: 'Request submitted',
                    subtitle:
                        'Your request has been sent to ${requestContext.businessName} for review.',
                    applicationId: _submittedApplicationId,
                    unitType: effectiveUnitType ?? '',
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ContextHeroCard(requestContext: requestContext),
                const SizedBox(height: 16),
                _IdentityFormCard(
                  firstNameCtrl: _firstNameCtrl,
                  lastNameCtrl: _lastNameCtrl,
                  ninCtrl: _ninCtrl,
                  dobCtrl: _dobCtrl,
                  pickedDocument: _pickedDocument,
                  unitMix: requestContext.unitMix,
                  selectedUnit: selectedUnit,
                  isSubmitting: _isSubmitting,
                  errorText: _error,
                  onPickDob: () => _pickDob(context),
                  onPickDocument: _pickDocument,
                  onUnitChanged: (value) {
                    setState(() => _selectedUnitType = value);
                  },
                  onSubmit: () => _submit(requestContext),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ContextHeroCard extends StatelessWidget {
  final TenantRequestLinkContext requestContext;

  const _ContextHeroCard({required this.requestContext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.secondary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            requestContext.businessName.isEmpty
                ? 'Tenant request'
                : requestContext.businessName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            requestContext.estateName.isEmpty
                ? 'Fill the form below to request a unit.'
                : 'Fill the form below to request a unit at ${requestContext.estateName}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (requestContext.expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Link expires on ${requestContext.expiresAt!.toLocal().toIso8601String().split('T').first}.',
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

class _IdentityFormCard extends StatelessWidget {
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final TextEditingController ninCtrl;
  final TextEditingController dobCtrl;
  final PickedDocumentData? pickedDocument;
  final List<BusinessAssetUnitMix> unitMix;
  final BusinessAssetUnitMix? selectedUnit;
  final bool isSubmitting;
  final String? errorText;
  final VoidCallback onPickDob;
  final VoidCallback onPickDocument;
  final ValueChanged<String?> onUnitChanged;
  final VoidCallback onSubmit;

  const _IdentityFormCard({
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.ninCtrl,
    required this.dobCtrl,
    required this.pickedDocument,
    required this.unitMix,
    required this.selectedUnit,
    required this.isSubmitting,
    required this.errorText,
    required this.onPickDob,
    required this.onPickDocument,
    required this.onUnitChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final unit = selectedUnit;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tenant details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: firstNameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    hintText: 'Enter first name',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: lastNameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    hintText: 'Enter last name',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ninCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'NIN',
              hintText: '11-digit NIN',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: dobCtrl,
            readOnly: true,
            onTap: isSubmitting ? null : onPickDob,
            decoration: const InputDecoration(
              labelText: 'Date of birth',
              hintText: 'Select date of birth',
              suffixIcon: Icon(Icons.calendar_month_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: unit?.unitType,
            decoration: const InputDecoration(labelText: 'Unit to rent'),
            items: unitMix
                .map(
                  (unit) => DropdownMenuItem<String>(
                    value: unit.unitType,
                    child: Text(
                      '${unit.unitType} • ${formatNgnFromCents(unit.rentAmount.round())} / ${unit.rentPeriod}',
                    ),
                  ),
                )
                .toList(),
            onChanged: isSubmitting ? null : onUnitChanged,
          ),
          if (unit != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Selected ${unit.unitType} at ${formatNgnFromCents(unit.rentAmount.round())} per ${unit.rentPeriod}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isSubmitting ? null : onPickDocument,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              pickedDocument == null
                  ? 'Upload verification ID'
                  : 'Replace verification ID',
            ),
          ),
          if (pickedDocument != null) ...[
            const SizedBox(height: 8),
            Text(
              pickedDocument!.filename,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : onSubmit,
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit request'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _StateCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(subtitle),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? applicationId;
  final String unitType;

  const _SuccessCard({
    required this.title,
    required this.subtitle,
    required this.applicationId,
    required this.unitType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (unitType.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Unit: $unitType',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (applicationId != null && applicationId!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Application ID: $applicationId',
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
