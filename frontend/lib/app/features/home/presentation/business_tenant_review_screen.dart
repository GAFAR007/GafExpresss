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
                ReadOnlyValue(
                  label: "Requested unit",
                  value: unitLabel,
                ),
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
                ),
                const SizedBox(height: 16),
                _SectionTitle(title: "Guarantors"),
                const SizedBox(height: 8),
                _ContactList(
                  contacts: application.guarantors,
                  emptyText: "No guarantors submitted.",
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

  const _StatusHeaderCard({
    required this.badge,
    required this.statusLabel,
    required this.tenantName,
    required this.unitLabel,
    required this.rentLabel,
    required this.moveInDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
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

class _ContactList extends StatelessWidget {
  final List<TenantContact> contacts;
  final String emptyText;

  const _ContactList({
    required this.contacts,
    required this.emptyText,
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
      children: contacts.map((contact) {
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
                    ],
                  ),
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
