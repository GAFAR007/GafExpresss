/// lib/app/features/home/presentation/business_staff_compensation_section.dart
/// ----------------------------------------------------------------------
/// WHAT:
/// - Staff compensation section with editable salary details.
///
/// WHY:
/// - Gives owners/estate managers a lightweight place to update payroll data.
/// - Keeps team management and compensation edits in one trusted screen.
///
/// HOW:
/// - Reuses staff list provider for profiles.
/// - Opens a bottom sheet to edit salary cadence + amount.
/// - Logs build/actions for traceability.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_compensation_model.dart';
import 'package:frontend/app/features/home/presentation/staff_compensation_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _logTag = "STAFF_COMP_SECTION";
const String _logBuild = "build";
const String _logSheetBuild = "sheet_build";
const String _sectionTitle = "Staff compensation";
const String _sectionSubtitle = "Set salary amount and cadence for your team.";
const String _emptyStaffMessage = "No staff profiles found.";
const String _retryLabel = "Try again";
const String _loadStaffErrorTitle = "Unable to load staff";
const String _loadStaffErrorHint = "If this persists, contact support.";
const String _editSalaryLabel = "Edit salary";
const String _sheetTitle = "Compensation";
const String _sheetSubtitle = "Update salary details for this staff member.";
const String _amountLabel = "Salary amount (NGN)";
const String _cadenceLabel = "Pay cadence";
const String _payDayLabel = "Pay day (optional)";
const String _notesLabel = "Internal notes (optional)";
const String _saveLabel = "Save compensation";
const String _savingLabel = "Saving...";
const String _compMissingLabel = "No salary set yet.";
const String _staffRolePrefix = "Role";
const String _staffStatusPrefix = "Status";
const String _staffScopeEstate = "Estate scoped";
const String _staffScopeBusiness = "Business-wide";
const String _unknownStaffLabel = "Staff member";
const String _cadenceWeekly = "weekly";
const String _cadenceMonthly = "monthly";
const String _cadenceWeeklyLabel = "Weekly";
const String _cadenceMonthlyLabel = "Monthly";
const String _compLoadErrorTitle = "Unable to load compensation";
const String _compLoadErrorHint = "If this persists, contact support.";
const String _compLoadRetryLabel = "Retry";
const String _saveSuccessMessage = "Compensation saved";
const String _formErrorMissingAmount = "Enter a salary amount.";
const String _formErrorMissingCadence = "Select a pay cadence.";
const String _staffCompActionLog = "edit_compensation";
const String _staffCompSaveLog = "save_compensation";
const String _staffCompRetryLog = "retry_compensation";
const String _extraStaffKey = "staffProfileId";
const int _notesMaxLines = 3;
const double _iconSize = 18;
const double _dividerHeight = 1;

const List<String> _cadenceOptions = <String>[_cadenceWeekly, _cadenceMonthly];

class BusinessStaffCompensationSection extends ConsumerWidget {
  const BusinessStaffCompensationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _logBuild);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // WHY: Reuse the staff list provider to avoid duplicating fetch logic.
    final staffAsync = ref.watch(productionStaffProvider);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _sectionTitle,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _sectionSubtitle,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          staffAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _StaffCompensationErrorState(
              message: _loadStaffErrorTitle,
              hint: _loadStaffErrorHint,
              onRetry: () {
                // WHY: Give users a way to retry without leaving the screen.
                AppDebug.log(_logTag, _staffCompRetryLog);
                // WHY: Consume refresh result to satisfy @useResult linting.
                final _ = ref.refresh(productionStaffProvider);
              },
            ),
            data: (staff) {
              if (staff.isEmpty) {
                return Text(
                  _emptyStaffMessage,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              }

              return _StaffCompensationList(staff: staff);
            },
          ),
        ],
      ),
    );
  }
}

class _StaffCompensationList extends StatelessWidget {
  final List<BusinessStaffProfileSummary> staff;

  const _StaffCompensationList({required this.staff});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // WHY: Prevent nested scrolling inside the parent ListView.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: staff.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final profile = staff[index];
        return _StaffCompensationRow(profile: profile);
      },
    );
  }
}

class _StaffCompensationRow extends StatelessWidget {
  final BusinessStaffProfileSummary profile;

  const _StaffCompensationRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final displayName =
        profile.userName ??
        profile.userEmail ??
        profile.userPhone ??
        _unknownStaffLabel;
    final roleLabel = formatStaffRoleLabel(
      profile.staffRole,
      fallback: _unknownStaffLabel,
    );
    final statusLabel = formatStaffRoleLabel(
      profile.status,
      fallback: _unknownStaffLabel,
    );
    final isEstateScoped = profile.estateAssetId != null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                "$_staffRolePrefix: $roleLabel",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                "$_staffStatusPrefix: $statusLabel",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isEstateScoped ? _staffScopeEstate : _staffScopeBusiness,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                // WHY: Keep edits isolated to a focused bottom sheet.
                AppDebug.log(
                  _logTag,
                  _staffCompActionLog,
                  extra: {_extraStaffKey: profile.id},
                );
                _showCompensationSheet(context: context, profile: profile);
              },
              icon: const Icon(Icons.payments_outlined, size: _iconSize),
              label: const Text(_editSalaryLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffCompensationErrorState extends StatelessWidget {
  final String message;
  final String hint;
  final VoidCallback onRetry;

  const _StaffCompensationErrorState({
    required this.message,
    required this.hint,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.error,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRetry, child: const Text(_retryLabel)),
      ],
    );
  }
}

class StaffCompensationSheet extends ConsumerStatefulWidget {
  final BusinessStaffProfileSummary profile;

  const StaffCompensationSheet({super.key, required this.profile});

  @override
  ConsumerState<StaffCompensationSheet> createState() =>
      _StaffCompensationSheetState();
}

class _StaffCompensationSheetState
    extends ConsumerState<StaffCompensationSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _payDayController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _initialized = false;
  bool _isSaving = false;
  String? _selectedCadence;
  String? _formError;

  @override
  void initState() {
    super.initState();

    // WHY: Populate the form once compensation data is loaded.
    ref.listen<AsyncValue<StaffCompensation?>>(
      staffCompensationProvider(widget.profile.id),
      (previous, next) {
        next.whenData((compensation) {
          if (_initialized) return;
          _initialized = true;
          if (compensation == null) return;
          _amountController.text = formatNgnInputFromKobo(
            compensation.salaryAmountKobo,
          );
          _selectedCadence = compensation.salaryCadence;
          _payDayController.text = compensation.payDay;
          _notesController.text = compensation.notes;
          setState(() {});
        });
      },
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _payDayController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      _logTag,
      _logSheetBuild,
      extra: {_extraStaffKey: widget.profile.id},
    );
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // WHY: Fetch compensation here so the sheet always reflects latest data.
    final staffAsync = ref.watch(staffCompensationProvider(widget.profile.id));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _sheetTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _sheetSubtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.profile.userName ?? _unknownStaffLabel,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: _dividerHeight,
              child: Divider(color: colorScheme.outlineVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            staffAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _CompensationErrorState(
                onRetry: () {
                  // WHY: Allow retrying the fetch from inside the sheet.
                  AppDebug.log(_logTag, _staffCompRetryLog);
                  // WHY: Consume refresh result to satisfy @useResult linting.
                  final _ =
                      ref.refresh(staffCompensationProvider(widget.profile.id));
                },
              ),
              data: (compensation) => _CompensationForm(
                amountController: _amountController,
                cadence: _selectedCadence,
                payDayController: _payDayController,
                notesController: _notesController,
                isSaving: _isSaving,
                formError: _formError,
                onCadenceChanged: (value) {
                  // WHY: Keep cadence in state for validation on save.
                  setState(() => _selectedCadence = value);
                },
                onSave: () => _saveCompensation(context),
                hasCompensation: compensation != null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCompensation(BuildContext context) async {
    if (_isSaving) return;

    setState(() => _formError = null);

    // WHY: Convert NGN input into kobo for backend storage.
    final salaryAmountKobo = parseNgnToKobo(_amountController.text);
    if (salaryAmountKobo == null || salaryAmountKobo <= 0) {
      setState(() => _formError = _formErrorMissingAmount);
      return;
    }

    if (_selectedCadence == null || _selectedCadence!.trim().isEmpty) {
      setState(() => _formError = _formErrorMissingCadence);
      return;
    }

    setState(() => _isSaving = true);
    AppDebug.log(
      _logTag,
      _staffCompSaveLog,
      extra: {_extraStaffKey: widget.profile.id},
    );

    try {
      final actions = StaffCompensationActions(ref as Ref<Object?>);
      await actions.upsertCompensation(
        staffProfileId: widget.profile.id,
        salaryAmountKobo: salaryAmountKobo,
        salaryCadence: _selectedCadence,
        payDay: _payDayController.text,
        notes: _notesController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(_saveSuccessMessage)));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _CompensationForm extends StatelessWidget {
  final TextEditingController amountController;
  final TextEditingController payDayController;
  final TextEditingController notesController;
  final String? cadence;
  final bool isSaving;
  final String? formError;
  final ValueChanged<String?> onCadenceChanged;
  final VoidCallback onSave;
  final bool hasCompensation;

  const _CompensationForm({
    required this.amountController,
    required this.cadence,
    required this.payDayController,
    required this.notesController,
    required this.isSaving,
    required this.formError,
    required this.onCadenceChanged,
    required this.onSave,
    required this.hasCompensation,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasCompensation) ...[
          // WHY: Make it clear when payroll data has not been configured yet.
          Text(
            _compMissingLabel,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextFormField(
          controller: amountController,
          // WHY: Amounts are captured in NGN for clarity, then converted to kobo.
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [NgnInputFormatter()],
          decoration: const InputDecoration(labelText: _amountLabel),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          value: cadence,
          decoration: const InputDecoration(labelText: _cadenceLabel),
          items: _cadenceOptions
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_formatCadenceLabel(value)),
                ),
              )
              .toList(),
          onChanged: onCadenceChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: payDayController,
          // WHY: Pay day is numeric-only to avoid invalid payroll values.
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: _payDayLabel),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: notesController,
          // WHY: Notes are optional but provide internal payroll context.
          maxLines: _notesMaxLines,
          decoration: const InputDecoration(labelText: _notesLabel),
        ),
        const SizedBox(height: AppSpacing.md),
        if (formError != null) ...[
          Text(
            formError!,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isSaving ? null : onSave,
            child: Text(isSaving ? _savingLabel : _saveLabel),
          ),
        ),
      ],
    );
  }
}

class _CompensationErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _CompensationErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _compLoadErrorTitle,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.error,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _compLoadErrorHint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRetry, child: const Text(_compLoadRetryLabel)),
      ],
    );
  }
}

void _showCompensationSheet({
  required BuildContext context,
  required BusinessStaffProfileSummary profile,
}) {
  // WHY: Use a modal sheet to keep edits focused without leaving the screen.
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => StaffCompensationSheet(profile: profile),
  );
}

String _formatCadenceLabel(String cadence) {
  switch (cadence) {
    case _cadenceWeekly:
      return _cadenceWeeklyLabel;
    case _cadenceMonthly:
      return _cadenceMonthlyLabel;
    default:
      return cadence;
  }
}
