/// lib/app/features/home/presentation/business_tenant_applications_screen.dart
/// -----------------------------------------------------------------------
/// WHAT:
/// - Business tenant applications list with filters + estate scoping.
///
/// WHY:
/// - Lets owners/staff review tenant requests before approval.
/// - Keeps tenant oversight separate from customer order flows.
///
/// HOW:
/// - Calls businessTenantApplicationsProvider with status + estate filters.
/// - Displays status badges and a detail link for each application.
/// - Logs build, taps, and refresh so we can trace review behavior.
/// -----------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_profile_action.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_team_lookup_invite_cards.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_providers.dart';
import 'package:frontend/app/features/home/presentation/role_access.dart'
    as role_access;
import 'package:frontend/app/theme/app_theme.dart';

// WHY: Centralize payment history route values for business navigation.
const String _businessTenantPaymentsRoute = "/business-tenant-payments";
const String _tenantNameExtraKey = "tenantName";
const String _viewPaymentsLabel = "View payments";
const String _viewPaymentsAction = "view_payments";
const double _actionSpacing = 8;
const String _tenantInviteTitle = "Send tenant invite";
const String _tenantInviteSubtitle =
    "Invite by email or create a shareable tenant request link.";

class BusinessTenantApplicationsScreen extends ConsumerStatefulWidget {
  final String? estateAssetId;

  const BusinessTenantApplicationsScreen({super.key, this.estateAssetId});

  @override
  ConsumerState<BusinessTenantApplicationsScreen> createState() =>
      _BusinessTenantApplicationsScreenState();
}

class _BusinessTenantApplicationsScreenState
    extends ConsumerState<BusinessTenantApplicationsScreen> {
  // WHY: Filters live in state so list refreshes when a chip is tapped.
  String _statusFilter = 'all';
  final int _page = 1;
  static const int _limit = 10;
  // WHY: Pull enough estate assets for invite selection without paging.
  static const int _estateAssetsLimit = 50;
  // WHY: Keep estate lookup consistent with active inventory.
  static const String _estateStatusActive = "active";

  void _logTap(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      "BUSINESS_TENANTS",
      "Tap",
      extra: {"action": action, ...?extra},
    );
  }

  BusinessTenantQuery _buildQuery() {
    return BusinessTenantQuery(
      status: _statusFilter == 'all' ? null : _statusFilter,
      estateAssetId: widget.estateAssetId,
      page: _page,
      limit: _limit,
    );
  }

  Map<String, int> _countByStatus(List<BusinessTenantApplication> apps) {
    final counts = {"pending": 0, "approved": 0, "rejected": 0, "active": 0};
    for (final app in apps) {
      final key = app.status.toLowerCase();
      if (counts.containsKey(key)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return counts;
  }

  int _readyToApproveCount(List<BusinessTenantApplication> apps) {
    // WHY: "Ready" = pending status with all required contacts verified.
    return apps.where((app) {
      if (app.status.toLowerCase() != 'pending') return false;
      final refsVerified = app.references
          .where((c) => c.isVerified || c.status.toLowerCase() == 'verified')
          .length;
      final guarantorsVerified = app.guarantors
          .where((c) => c.isVerified || c.status.toLowerCase() == 'verified')
          .length;
      final rules = app.tenantRulesSnapshot;
      final refsOk = refsVerified >= rules.referencesMin;
      final guarantorsOk = guarantorsVerified >= rules.guarantorsMin;
      return refsOk && guarantorsOk;
    }).length;
  }

  int _activeCount(List<BusinessTenantApplication> apps) {
    return apps.where((app) => app.status.toLowerCase() == 'active').length;
  }

  String _extractError(Object error) {
    if (error is Exception) return error.toString();
    return "$error";
  }

  List<BusinessTenantApplication> _recentlyUpdated(
    List<BusinessTenantApplication> apps,
  ) {
    // WHY: Show the latest movements without an event feed yet.
    final sorted = [...apps]
      ..sort((a, b) {
        final aDate =
            a.updatedAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.updatedAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    return sorted.take(4).toList();
  }

  AppStatusTone _toneForStatus(String status) {
    switch (status.toLowerCase()) {
      case "active":
        return AppStatusTone.success;
      case "approved":
        return AppStatusTone.success;
      case "rejected":
        return AppStatusTone.danger;
      case "pending":
      default:
        return AppStatusTone.warning;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case "active":
        return "Active";
      case "approved":
        return "Approved";
      case "rejected":
        return "Rejected";
      case "pending":
      default:
        return "Pending";
    }
  }

  void _openTenantPayments({
    required BuildContext context,
    required String tenantId,
    required String tenantName,
  }) {
    // WHY: Payment history lives on a dedicated screen to avoid UI bloat.
    _logTap(_viewPaymentsAction, extra: {"tenantId": tenantId});
    context.push(
      "$_businessTenantPaymentsRoute/$tenantId",
      extra: {_tenantNameExtraKey: tenantName},
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_TENANTS", "build()", extra: {"page": _page});

    final session = ref.watch(authSessionProvider);
    final query = _buildQuery();
    final tenantsAsync = ref.watch(businessTenantApplicationsProvider(query));
    final canSendTenantInvites = role_access.canSendTenantInvites(
      role: session?.user.role,
      staffRole: session?.user.staffRole,
    );
    final isEstateScoped =
        widget.estateAssetId != null && widget.estateAssetId!.isNotEmpty;
    final estateAnalyticsAsync = isEstateScoped
        ? ref.watch(estateAnalyticsProvider(widget.estateAssetId!))
        : null;
    // WHY: Load active estate assets so tenant invites can be scoped correctly.
    final estateAssetsAsync = ref.watch(
      businessAssetsProvider(
        const BusinessAssetsQuery(
          status: _estateStatusActive,
          page: 1,
          limit: _estateAssetsLimit,
        ),
      ),
    );
    final estateAssets = estateAssetsAsync.maybeWhen(
      data: (result) =>
          result.assets.where((asset) => asset.assetType == "estate").toList(),
      orElse: () => <BusinessAsset>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tenant applications"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _logTap("back");
            if (context.canPop()) {
              context.pop();
              return;
            }
            // WHY: Scoped lists usually come from assets; otherwise go dashboard.
            context.go(
              isEstateScoped ? '/business-assets' : '/business-dashboard',
            );
          },
        ),
        actions: [
          IconButton(
            onPressed: () async {
              _logTap("refresh");
              // WHY: Central refresh keeps tenant data in sync across screens.
              await AppRefresh.refreshApp(
                ref: ref,
                source: "business_tenants_refresh",
              );
            },
            icon: const Icon(Icons.refresh),
          ),
          const BusinessProfileAction(logTag: "BUSINESS_TENANTS"),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _logTap("pull_to_refresh");
          // WHY: Central refresh keeps tenant data in sync across screens.
          await AppRefresh.refreshApp(
            ref: ref,
            source: "business_tenants_pull",
          );
        },
        child: tenantsAsync.when(
          data: (result) {
            final apps = result.applications;
            final counts = _countByStatus(apps);
            final readyCount = _readyToApproveCount(apps);
            final activeCount = _activeCount(apps);
            final estateName = apps
                .map((app) => app.estate?.name)
                .firstWhere(
                  (name) => name != null && name.isNotEmpty,
                  orElse: () => null,
                );
            final recent = _recentlyUpdated(apps);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // WHY: Keep lookup/invite ahead of KPIs while allowing collapse.
                BusinessUserLookupCard(
                  source: "BUSINESS_TENANTS",
                  isCollapsible: true,
                  initiallyExpanded: false,
                ),
                const SizedBox(height: 12),
                if (canSendTenantInvites) ...[
                  // WHY: Separate invite form keeps new tenant flow obvious.
                  BusinessInviteFormCard(
                    source: "BUSINESS_TENANTS",
                    title: _tenantInviteTitle,
                    subtitle: _tenantInviteSubtitle,
                    estateAssets: estateAssets,
                    estateAssetsLoading: estateAssetsAsync.isLoading,
                    tenantOnly: true,
                    isCollapsible: true,
                    initiallyExpanded: false,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  const _TenantInviteAccessHint(),
                  const SizedBox(height: 16),
                ],
                if (!isEstateScoped) ...[
                  _NoEstateScopeHint(
                    onViewEstates: () {
                      _logTap("scope_select_estate");
                      context.go('/business-assets');
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (isEstateScoped) ...[
                  _EstateScopeBanner(name: estateName),
                  const SizedBox(height: 12),
                  estateAnalyticsAsync?.when(
                        data: (analytics) =>
                            _EstateAnalyticsKpis(analytics: analytics),
                        loading: () =>
                            _InlineLoader(label: "Loading estate KPIs..."),
                        error: (error, _) =>
                            Text("Analytics error: ${_extractError(error)}"),
                      ) ??
                      const SizedBox.shrink(),
                  const SizedBox(height: 16),
                ],
                _KpiRow(
                  pending: counts["pending"] ?? 0,
                  ready: readyCount,
                  approved: counts["approved"] ?? 0,
                  active: activeCount,
                ),
                const SizedBox(height: 12),
                if (recent.isNotEmpty) ...[
                  _RecentActivityStrip(apps: recent),
                  const SizedBox(height: 12),
                ],
                _StatusFilterRow(
                  selected: _statusFilter,
                  counts: counts,
                  onSelected: (value) {
                    _logTap("filter_change", extra: {"status": value});
                    setState(() => _statusFilter = value);
                  },
                ),
                const SizedBox(height: 12),
                _ResultsMeta(showing: apps.length, total: result.total),
                const SizedBox(height: 16),
                if (apps.isEmpty)
                  const _EmptyState(text: "No tenant applications yet")
                else
                  ...apps.map((application) {
                    // WHY: Payment history is keyed to the tenant user id.
                    final tenantId = application.tenantUserStatus?.id ?? "";
                    // WHY: Disable navigation if tenant id is missing.
                    final canViewPayments = tenantId.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TenantApplicationCard(
                        application: application,
                        statusLabel: _statusLabel(application.status),
                        statusTone: _toneForStatus(application.status),
                        onView: () {
                          _logTap(
                            "open_detail",
                            extra: {"applicationId": application.id},
                          );
                          context.push('/tenant-review/${application.id}');
                        },
                        onViewPayments: canViewPayments
                            ? () => _openTenantPayments(
                                context: context,
                                tenantId: tenantId,
                                tenantName: application.tenantSnapshot.name,
                              )
                            : null,
                      ),
                    );
                  }),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            AppDebug.log(
              "BUSINESS_TENANTS",
              "Load failed",
              extra: {"error": error.toString()},
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
                Center(child: Text("Failed to load tenant applications")),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: BusinessBottomNav(
        // WHY: Tenant list is a business workflow; keep dashboard highlighted.
        currentIndex: 2,
        onTap: (index) {
          _logTap("bottom_nav", extra: {"index": index});
          switch (index) {
            case 0:
              context.go('/home');
              return;
            case 1:
              context.go('/business-products');
              return;
            case 2:
              context.go('/business-dashboard');
              return;
            case 3:
              context.go('/business-orders');
              return;
            case 4:
              context.go('/chat');
              return;
            case 5:
              context.go('/settings');
              return;
          }
        },
      ),
    );
  }
}

class _EstateScopeBanner extends StatelessWidget {
  final String? name;

  const _EstateScopeBanner({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.apartment, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name == null || name!.isEmpty
                  ? "Estate-scoped view"
                  : "Estate: $name",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoEstateScopeHint extends StatelessWidget {
  final VoidCallback onViewEstates;
  const _NoEstateScopeHint({required this.onViewEstates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Scope to an estate to see occupancy and rent KPIs.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onViewEstates,
            child: const Text("View estates"),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterRow extends StatelessWidget {
  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  const _StatusFilterRow({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = [
      _FilterChipData(label: "All", value: "all", count: null),
      _FilterChipData(
        label: "Pending",
        value: "pending",
        count: counts["pending"],
      ),
      _FilterChipData(
        label: "Approved",
        value: "approved",
        count: counts["approved"],
      ),
      _FilterChipData(
        label: "Rejected",
        value: "rejected",
        count: counts["rejected"],
      ),
      _FilterChipData(
        label: "Active",
        value: "active",
        count: counts["active"],
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((chip) {
        final isActive = chip.value == selected;
        return ChoiceChip(
          selected: isActive,
          label: Text(
            chip.count == null ? chip.label : "${chip.label} ${chip.count}",
          ),
          onSelected: (_) => onSelected(chip.value),
          selectedColor: theme.colorScheme.secondaryContainer,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          labelStyle: theme.textTheme.bodySmall?.copyWith(
            color: isActive
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }
}

class _FilterChipData {
  final String label;
  final String value;
  final int? count;

  const _FilterChipData({
    required this.label,
    required this.value,
    required this.count,
  });
}

class _ResultsMeta extends StatelessWidget {
  final int showing;
  final int total;

  const _ResultsMeta({required this.showing, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      "Showing $showing of $total",
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _TenantApplicationCard extends StatelessWidget {
  final BusinessTenantApplication application;
  final String statusLabel;
  final AppStatusTone statusTone;
  final VoidCallback onView;
  final VoidCallback? onViewPayments;

  const _TenantApplicationCard({
    required this.application,
    required this.statusLabel,
    required this.statusTone,
    required this.onView,
    required this.onViewPayments,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: statusTone,
    );
    // WHY: Tenant rent amounts are stored in kobo; format to NGN for display.
    final rentLabel = formatNgnFromCents(application.rentAmount.round());
    final unitLabel = "${application.unitCount} x ${application.unitType}";
    final refs = application.references;
    final refsVerified = refs
        .where((c) => c.isVerified || c.status.toLowerCase() == 'verified')
        .length;
    final refsNeeded = application.tenantRulesSnapshot.referencesMin;
    final refsText = "Refs $refsVerified/$refsNeeded";

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  application.tenantSnapshot.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeColors.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: badgeColors.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            application.tenantSnapshot.email,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _MetaChip(label: "Unit", value: unitLabel),
              _MetaChip(label: "Rent", value: rentLabel),
              _MetaChip(
                label: "Period",
                value: application.rentPeriod.toUpperCase(),
              ),
              _MetaChip(label: refsText, value: ""),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: _actionSpacing,
              children: [
                // WHY: Keep the existing review flow as the primary action.
                TextButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text("View details"),
                ),
                // WHY: Payment history is optional when tenant id is missing.
                TextButton.icon(
                  onPressed: onViewPayments,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text(_viewPaymentsLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value.isEmpty ? label : "$label: $value",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final int pending;
  final int ready;
  final int approved;
  final int active;

  const _KpiRow({
    required this.pending,
    required this.ready,
    required this.approved,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final items = [
      _KpiCard(label: "Pending", value: pending, tone: AppStatusTone.warning),
      _KpiCard(label: "Ready", value: ready, tone: AppStatusTone.info),
      _KpiCard(label: "Approved", value: approved, tone: AppStatusTone.success),
      _KpiCard(label: "Active", value: active, tone: AppStatusTone.success),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: isNarrow ? (constraints.maxWidth) : 160,
                  child: item,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _EstateAnalyticsKpis extends StatelessWidget {
  final EstateAnalytics analytics;
  const _EstateAnalyticsKpis({required this.analytics});

  String _fmtMoney(int kobo) {
    // WHY: Keep money formatting centralized and consistent.
    return formatNgnFromCents(kobo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SmallKpi(
          label: "Active tenants",
          value: analytics.tenants.active.toString(),
          color: AppStatusBadgeColors.fromTheme(
            theme: theme,
            tone: AppStatusTone.success,
          ).foreground,
        ),
        _SmallKpi(
          label: "Pending",
          value: analytics.tenants.pending.toString(),
          color: AppStatusBadgeColors.fromTheme(
            theme: theme,
            tone: AppStatusTone.warning,
          ).foreground,
        ),
        _SmallKpi(
          label: "Due soon",
          value: analytics.tenants.dueSoon.toString(),
          color: colorScheme.primary,
        ),
        _SmallKpi(
          label: "Overdue",
          value: analytics.tenants.overdue.toString(),
          color: AppStatusBadgeColors.fromTheme(
            theme: theme,
            tone: AppStatusTone.danger,
          ).foreground,
        ),
        _SmallKpi(
          label: "Collected (month)",
          value: _fmtMoney(analytics.collections.monthKobo),
          color: colorScheme.primary,
        ),
        _SmallKpi(
          label: "Collected (YTD)",
          value: _fmtMoney(analytics.collections.ytdKobo),
          color: colorScheme.primary,
        ),
        _SmallKpi(
          label: "Potential annual",
          value: _fmtMoney(analytics.estate.potentialAnnualKobo),
          color: colorScheme.onSurface,
        ),
      ],
    );
  }
}

class _SmallKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SmallKpi({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
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
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final int value;
  final AppStatusTone tone;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "$value",
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityStrip extends StatelessWidget {
  final List<BusinessTenantApplication> apps;

  const _RecentActivityStrip({required this.apps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Recent activity",
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: apps.map((app) {
              final statusTone = AppStatusTone.info;
              final badgeColors = AppStatusBadgeColors.fromTheme(
                theme: theme,
                tone: statusTone,
              );
              final date = app.updatedAt ?? app.createdAt;
              final dateLabel = date == null
                  ? ''
                  : "${date.year}-${date.month}-${date.day}";
              return Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.tenantSnapshot.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColors.background,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            app.status,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badgeColors.foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      app.tenantSnapshot.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dateLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _TenantInviteAccessHint extends StatelessWidget {
  const _TenantInviteAccessHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Tenant invites are available to business owners, shareholders, and estate managers.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Status against the plan you approved:

// Slice 1 (schema/validation): DONE. RentPeriod default yearly; rentAmount integer; Payment + TenantApplication have coverage fields (paidThroughDate, nextDueDate, lastRentPaymentAt, coversFrom/To, rentPeriod, periodCount).
// Slice 2 (coverage utils): DONE. utils/rentCoverage.js added with month math + 36‑month cap helpers.
// Slice 3 (payment intent rules): DONE. yearsToPay, max 3 payments/year, auto-reduce to 36‑month cap, coverage fields on Payment, richer response.
// Slice 4 (webhook/verify success): DONE. Uses Payment.amount, allows approved/active, updates paidThrough/nextDue/lastRentPaymentAt, dev mark mirrors webhook, verify returns coverage.
// Tenant summary endpoint + frontend wiring: DONE. Tenant dashboard route + screen, verification CTA now points there.
// Slice 5 (rent summary math fix): NOT done yet.
// Slice 6 (estate analytics endpoint): NOT started.
// Slice 7 (tenant UI polish beyond current state): PARTIAL. Dashboard + verification improved; receipt link still TODO; timeline on review optional.
// Slice 8 (owner/staff analytics UI): NOT started.
