/// lib/app/features/home/presentation/business_tenant_review_screen.dart
/// --------------------------------------------------------------------
/// WHAT:
/// - Tenant application review screen for business owners/staff.
///
/// WHY:
/// - Gives operators a single place to audit tenant details, rules,
///   and verification status before approval workflows.
///
/// HOW:
/// - Fetches application detail via businessTenantByIdProvider.
/// - Renders read-only sections for identity, estate context, and audit meta.
/// - Logs build + user taps so support can trace review actions.
/// --------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/settings/widgets/read_only_value.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessTenantReviewScreen extends ConsumerStatefulWidget {
  final String applicationId;

  const BusinessTenantReviewScreen({super.key, required this.applicationId});

  @override
  ConsumerState<BusinessTenantReviewScreen> createState() =>
      _BusinessTenantReviewScreenState();
}

class _BusinessTenantReviewScreenState
    extends ConsumerState<BusinessTenantReviewScreen> {
  void _logTap(String action, {Map<String, dynamic>? extra}) {
    // WHY: Track review actions for audit and debugging.
    AppDebug.log(
      "BUSINESS_TENANT_REVIEW",
      "Tap",
      extra: {"action": action, ...?extra},
    );
  }

  bool _isContactVerified(TenantContact contact) {
    // WHY: Contacts can be marked verified via status or boolean flag.
    return contact.isVerified ||
        contact.status.toLowerCase() == 'verified';
  }

  Future<String?> _openNoteDialog({
    required String title,
  }) async {
    // WHY: Capture optional verification notes for audit.
    String noteValue = '';

    return showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            autofocus: true,
            maxLines: 2,
            onChanged: (value) {
              noteValue = value;
            },
            decoration: const InputDecoration(
              labelText: "Note (optional)",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _logTap("note_cancel");
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(noteValue.trim());
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _verifyContact({
    required String applicationId,
    required String type,
    required int index,
    required String label,
  }) async {
    _logTap(
      "verify_contact",
      extra: {"type": type, "index": index},
    );

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _logTap("verify_contact_block", extra: {"reason": "no_session"});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    final note = await _openNoteDialog(
      title: "Verify $label",
    );
    if (note == null) {
      _logTap("verify_contact_cancel");
      return;
    }

    try {
      final api = ref.read(businessTenantApiProvider);
      await api.verifyTenantContact(
        token: session.token,
        applicationId: applicationId,
        type: type,
        index: index,
        status: "verified",
        note: note,
      );

      ref.invalidate(businessTenantByIdProvider(applicationId));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$label verified")),
      );
    } catch (error) {
      _logTap(
        "verify_contact_fail",
        extra: {"error": error.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Verification failed. ${error.toString()}")),
      );
    }
  }

  Future<void> _approveTenant({
    required String applicationId,
  }) async {
    _logTap("approve_tenant", extra: {"applicationId": applicationId});

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _logTap("approve_tenant_block", extra: {"reason": "no_session"});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    try {
      final api = ref.read(businessTenantApiProvider);
      await api.approveTenantApplication(
        token: session.token,
        applicationId: applicationId,
      );

      ref.invalidate(businessTenantByIdProvider(applicationId));
      ref.invalidate(businessTenantApplicationsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tenant approved successfully")),
      );
    } catch (error) {
      _logTap(
        "approve_tenant_fail",
        extra: {"error": error.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Approval failed. ${error.toString()}")),
      );
    }
  }

  AppStatusTone _toneForStatus(String status) {
    // WHY: Keep status colors consistent with other business surfaces.
    switch (status.toLowerCase()) {
      case 'approved':
        return AppStatusTone.success;
      case 'rejected':
        return AppStatusTone.danger;
      case 'pending':
      default:
        return AppStatusTone.warning;
    }
  }

  String _formatDate(DateTime? date) {
    // WHY: Avoid intl dependency for a simple ISO date display.
    if (date == null) return "Not provided";
    return date.toIso8601String().split('T').first;
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "BUSINESS_TENANT_REVIEW",
      "build()",
      extra: {"applicationId": widget.applicationId},
    );

    final session = ref.watch(authSessionProvider);
    final role = session?.user.role ?? 'unknown';
    final isAdminView = role != 'tenant';
    final canVerify = role == 'business_owner' || role == 'staff';
    final canApprove = role == 'business_owner';

    final detailAsync = ref.watch(
      businessTenantByIdProvider(widget.applicationId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tenant review"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _logTap("back");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-tenants');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _logTap("refresh");
              ref.invalidate(businessTenantByIdProvider(widget.applicationId));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _logTap("pull_to_refresh");
          ref.invalidate(businessTenantByIdProvider(widget.applicationId));
        },
        child: detailAsync.when(
          data: (application) {
            final theme = Theme.of(context);
            final tone = _toneForStatus(application.status);
            final badge = AppStatusBadgeColors.fromTheme(
              theme: theme,
              tone: tone,
            );
            final rentLabel = formatNgn(application.rentAmount);
            final unitLabel =
                "${application.unitCount} x ${application.unitType}";
            final rules = application.tenantRulesSnapshot;
            final estate = application.estate;
            final userStatus = application.tenantUserStatus;
            final requiredReferences = rules.referencesMin;
            final requiredGuarantors = rules.guarantorsMin;
            final verifiedReferences = application.references
                .where(_isContactVerified)
                .length;
            final verifiedGuarantors = application.guarantors
                .where(_isContactVerified)
                .length;
            final meetsReferenceRequirement =
                verifiedReferences >= requiredReferences &&
                    application.references.length >= requiredReferences;
            final meetsGuarantorRequirement =
                verifiedGuarantors >= requiredGuarantors &&
                    application.guarantors.length >= requiredGuarantors;
            final canApproveNow = meetsReferenceRequirement &&
                meetsGuarantorRequirement &&
                application.status.toLowerCase() == 'pending';
            final isAlreadyApproved =
                application.status.toLowerCase() == 'approved' ||
                    application.status.toLowerCase() == 'active';

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (isAdminView)
                  Text(
                    "View as admin (${role.replaceAll('_', ' ')}).",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (isAdminView) const SizedBox(height: 8),
                _StatusHeaderCard(
                  badge: badge,
                  statusLabel: application.status.toUpperCase(),
                  tenantName: application.tenantSnapshot.name,
                  unitLabel: unitLabel,
                  rentLabel: rentLabel,
                  moveInDate: _formatDate(application.moveInDate),
                  referencesProgress:
                      "$verifiedReferences / $requiredReferences refs",
                  guarantorsProgress:
                      "$verifiedGuarantors / $requiredGuarantors guar",
                  paymentStatus: application.paymentStatus,
                ),
                const SizedBox(height: 16),
                _PaymentStatusCard(
                  paymentStatus: application.paymentStatus,
                  paidAt: application.paidAt,
                  amountLabel: rentLabel,
                ),
                const SizedBox(height: 16),
                _ReviewTimeline(
                  createdAt: application.createdAt,
                  reviewedAt: application.reviewedAt,
                  paidAt: application.paidAt,
                  status: application.status,
                  paymentStatus: application.paymentStatus,
                ),
                const SizedBox(height: 16),
                _VerificationChecklist(
                  refs: application.references,
                  guar: application.guarantors,
                  rules: rules,
                ),
                const SizedBox(height: 16),
                _SectionTitle(title: "Tenant identity"),
                const SizedBox(height: 8),
                ReadOnlyValue(
                  label: "Full name",
                  value: application.tenantSnapshot.name,
                ),
                const SizedBox(height: 12),
                ReadOnlyValueWithStatus(
                  label: "Email",
                  value: application.tenantSnapshot.email,
                  isVerified: userStatus?.isEmailVerified ?? false,
                ),
                const SizedBox(height: 12),
                ReadOnlyValueWithStatus(
                  label: "Phone",
                  value: application.tenantSnapshot.phone,
                  isVerified: userStatus?.isPhoneVerified ?? false,
                ),
                const SizedBox(height: 12),
                ReadOnlyValueWithStatus(
                  label: "NIN",
                  value: application.tenantSnapshot.ninLast4.isEmpty
                      ? "Not provided"
                      : "**** ${application.tenantSnapshot.ninLast4}",
                  isVerified: userStatus?.isNinVerified ?? false,
                ),
                if (userStatus != null) ...[
                  const SizedBox(height: 12),
                  ReadOnlyValue(
                    label: "Current role",
                    value: userStatus.role.replaceAll('_', ' '),
                  ),
                ],
                const SizedBox(height: 20),
                _SectionTitle(title: "Estate context"),
                const SizedBox(height: 8),
                ReadOnlyValue(
                  label: "Estate",
                  value: estate?.name ?? "Unknown estate",
                ),
                const SizedBox(height: 12),
                ReadOnlyValue(label: "Requested unit", value: unitLabel),
                const SizedBox(height: 12),
                ReadOnlyValue(
                  label: "Rent schedule",
                  value: "$rentLabel / ${application.rentPeriod}",
                ),
                const SizedBox(height: 12),
                ReadOnlyValue(
                  label: "Move-in date",
                  value: _formatDate(application.moveInDate),
                ),
                if (estate != null && estate.unitMix.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _UnitMixCard(unitMix: estate.unitMix),
                ],
                const SizedBox(height: 20),
                _SectionTitle(title: "Tenant rules"),
                const SizedBox(height: 8),
                _RulesRow(
                  label: "References",
                  value: "${rules.referencesMin} - ${rules.referencesMax}",
                ),
                const SizedBox(height: 6),
                _RulesRow(
                  label: "Guarantors",
                  value: "${rules.guarantorsMin} - ${rules.guarantorsMax}",
                ),
                const SizedBox(height: 6),
                _RulesRow(
                  label: "Agreement required",
                  value: rules.requiresAgreementSigned ? "Yes" : "No",
                ),
                const SizedBox(height: 20),
                _SectionTitle(title: "References"),
                const SizedBox(height: 8),
                _ContactList(
                  contacts: application.references,
                  emptyText: "No references submitted.",
                  canVerify: canVerify,
                  onVerify: (index) {
                    _verifyContact(
                      applicationId: application.id,
                      type: "reference",
                      index: index,
                      label: "Reference",
                    );
                  },
                  isVerified: _isContactVerified,
                ),
                const SizedBox(height: 16),
                _SectionTitle(title: "Guarantors"),
                const SizedBox(height: 8),
                _ContactList(
                  contacts: application.guarantors,
                  emptyText: "No guarantors submitted.",
                  canVerify: canVerify,
                  onVerify: (index) {
                    _verifyContact(
                      applicationId: application.id,
                      type: "guarantor",
                      index: index,
                      label: "Guarantor",
                    );
                  },
                  isVerified: _isContactVerified,
                ),
                const SizedBox(height: 20),
                _SectionTitle(title: "Review metadata"),
                const SizedBox(height: 8),
                ReadOnlyValue(
                  label: "Status",
                  value: application.status.toUpperCase(),
                ),
                const SizedBox(height: 12),
                ReadOnlyValue(
                  label: "Reviewed at",
                  value: _formatDate(application.reviewedAt),
                ),
                const SizedBox(height: 12),
                ReadOnlyValue(
                  label: "Reviewed by",
                  value: application.reviewedBy?.isEmpty ?? true
                      ? "Not reviewed"
                      : application.reviewedBy!,
                ),
                const SizedBox(height: 12),
                ReadOnlyValue(
                  label: "Review notes",
                  value: application.reviewNotes?.isEmpty ?? true
                      ? "No notes"
                      : application.reviewNotes!,
                ),
                if (canApprove && !isAlreadyApproved) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: canApproveNow
                          ? () => _approveTenant(
                                applicationId: application.id,
                              )
                          : null,
                      icon: const Icon(Icons.verified_user),
                      label: Text(
                        canApproveNow
                            ? "Approve tenant"
                            : "Verify contacts to approve",
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () {
                    _logTap("open_applications_list");
                    context.go('/business-tenants');
                  },
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text("Back to applications"),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            AppDebug.log(
              "BUSINESS_TENANT_REVIEW",
              "Load failed",
              extra: {"error": error.toString()},
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 200),
                Center(child: Text("Failed to load tenant application")),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusHeaderCard extends StatelessWidget {
  final AppStatusBadgeColors badge;
  final String statusLabel;
  final String tenantName;
  final String unitLabel;
  final String rentLabel;
  final String moveInDate;
  final String referencesProgress;
  final String guarantorsProgress;
  final String paymentStatus;

  const _StatusHeaderCard({
    required this.badge,
    required this.statusLabel,
    required this.tenantName,
    required this.unitLabel,
    required this.rentLabel,
    required this.moveInDate,
    required this.referencesProgress,
    required this.guarantorsProgress,
    required this.paymentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badge.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: badge.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.verified_user, color: badge.foreground),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tenantName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Unit: $unitLabel",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Rent: $rentLabel",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Move-in: $moveInDate",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Pill(text: referencesProgress),
              _Pill(text: guarantorsProgress),
              _Pill(text: "Payment: ${paymentStatus.toUpperCase()}"),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _RulesRow extends StatelessWidget {
  final String label;
  final String value;

  const _RulesRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PaymentStatusCard extends StatelessWidget {
  final String paymentStatus;
  final DateTime? paidAt;
  final String amountLabel;

  const _PaymentStatusCard({
    required this.paymentStatus,
    required this.paidAt,
    required this.amountLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = paymentStatus.toLowerCase() == 'paid'
        ? AppStatusTone.success
        : AppStatusTone.info;
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Payment status",
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  paymentStatus.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Amount: $amountLabel",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            paidAt == null
                ? "No payment recorded yet"
                : "Paid at: ${paidAt!.toLocal()}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VerificationChecklist extends StatelessWidget {
  final List<TenantContact> refs;
  final List<TenantContact> guar;
  final TenantRulesSnapshot rules;

  const _VerificationChecklist({
    required this.refs,
    required this.guar,
    required this.rules,
  });

  int _verified(List<TenantContact> list) {
    return list
        .where(
          (c) => c.isVerified || c.status.toLowerCase() == 'verified',
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refsVerified = _verified(refs);
    final guarVerified = _verified(guar);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Verification checklist",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _ChecklistRow(
            label: "References",
            progress: "$refsVerified / ${rules.referencesMin}",
            isDone: refsVerified >= rules.referencesMin,
          ),
          const SizedBox(height: 8),
          _ChecklistRow(
            label: "Guarantors",
            progress: "$guarVerified / ${rules.guarantorsMin}",
            isDone: guarVerified >= rules.guarantorsMin,
          ),
          const SizedBox(height: 8),
          _ChecklistRow(
            label: "Agreement",
            progress: rules.requiresAgreementSigned ? "Required" : "Not required",
            isDone: rules.requiresAgreementSigned ? false : true,
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final String label;
  final String progress;
  final bool isDone;

  const _ChecklistRow({
    required this.label,
    required this.progress,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isDone
              ? AppStatusBadgeColors.fromTheme(
                      theme: theme, tone: AppStatusTone.success)
                  .foreground
              : theme.colorScheme.onSurfaceVariant,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          progress,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ReviewTimeline extends StatelessWidget {
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final DateTime? paidAt;
  final String status;
  final String paymentStatus;

  const _ReviewTimeline({
    required this.createdAt,
    required this.reviewedAt,
    required this.paidAt,
    required this.status,
    required this.paymentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      _TimelineItem(
        label: "Submitted",
        date: createdAt,
        done: createdAt != null,
      ),
      _TimelineItem(
        label: "Approved",
        date: reviewedAt,
        done: status.toLowerCase() == "approved" ||
            status.toLowerCase() == "active",
      ),
      _TimelineItem(
        label: "Payment",
        date: paidAt,
        done: paymentStatus.toLowerCase() == "paid",
      ),
      _TimelineItem(
        label: "Active",
        date: status.toLowerCase() == "active" ? paidAt ?? reviewedAt : null,
        done: status.toLowerCase() == "active",
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Timeline",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Column(
            children: steps
                .map(
                  (s) => _TimelineRow(
                    item: s,
                    doneColor: AppStatusBadgeColors.fromTheme(
                      theme: theme,
                      tone: AppStatusTone.success,
                    ).foreground,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem {
  final String label;
  final DateTime? date;
  final bool done;

  const _TimelineItem({
    required this.label,
    required this.date,
    required this.done,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineItem item;
  final Color doneColor;

  const _TimelineRow({required this.item, required this.doneColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText =
        item.date == null ? "" : "${item.date!.year}-${item.date!.month}-${item.date!.day}";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            item.done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: item.done ? doneColor : theme.colorScheme.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            dateText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactList extends StatelessWidget {
  final List<TenantContact> contacts;
  final String emptyText;
  final bool canVerify;
  final void Function(int index)? onVerify;
  final bool Function(TenantContact contact)? isVerified;

  const _ContactList({
    required this.contacts,
    required this.emptyText,
    required this.canVerify,
    required this.onVerify,
    required this.isVerified,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (contacts.isEmpty) {
      return Text(
        emptyText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      children: contacts.asMap().entries.map((entry) {
        final index = entry.key;
        final contact = entry.value;
        final contactVerified = isVerified?.call(contact) ?? false;
        final statusLabel = contact.status.isEmpty
            ? (contactVerified ? "verified" : "pending")
            : contact.status;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contact.phone?.isNotEmpty == true
                            ? contact.phone!
                            : "Phone not provided",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusLabel.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: contactVerified
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canVerify && !contactVerified && onVerify != null)
                  TextButton(
                    onPressed: () => onVerify?.call(index),
                    child: const Text("Verify"),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _UnitMixCard extends StatelessWidget {
  final List<EstateUnitMix> unitMix;

  const _UnitMixCard({required this.unitMix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Unit mix",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ...unitMix.map((unit) {
            final rentLabel = formatNgn(unit.rentAmount);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${unit.count} x ${unit.unitType}",
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    "$rentLabel / ${unit.rentPeriod}",
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
