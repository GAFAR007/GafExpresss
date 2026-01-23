/// lib/app/features/home/presentation/business_assets_screen.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Business assets management screen with analytics-style layout.
///
/// WHY:
/// - Lets owners/staff track vehicles, equipment, and warehouses.
/// - Provides quick actions + status filtering for daily ops.
///
/// HOW:
/// - Uses businessAssetsProvider for list + filters.
/// - Uses businessAssetSummaryProvider for status counts.
/// - Creates/updates/archives assets via BusinessAssetApi.
///
/// DEBUGGING:
/// - Logs build, taps, and API flows for traceability.
/// ----------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessAssetsScreen extends ConsumerStatefulWidget {
  const BusinessAssetsScreen({super.key});

  @override
  ConsumerState<BusinessAssetsScreen> createState() =>
      _BusinessAssetsScreenState();
}

// WHY: Provide stable select options that match backend enums.
const List<Map<String, String>> _assetTypeOptions = [
  {"value": "vehicle", "label": "Vehicle"},
  {"value": "equipment", "label": "Equipment"},
  {"value": "warehouse", "label": "Warehouse"},
  {"value": "other", "label": "Other"},
];

const List<Map<String, String>> _statusOptions = [
  {"value": "active", "label": "Active"},
  {"value": "maintenance", "label": "Maintenance"},
  {"value": "inactive", "label": "Inactive"},
];

class _BusinessAssetsScreenState extends ConsumerState<BusinessAssetsScreen> {
  String? _busyAssetId;
  bool _isSaving = false;

  void _logTap(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      "BUSINESS_ASSETS",
      "Tap",
      extra: {"action": action, ...?extra},
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_ASSETS", "build()");

    final statusFilter = ref.watch(businessAssetStatusFilterProvider);
    final query = BusinessAssetsQuery(
      status: statusFilter,
      page: 1,
      limit: 20,
    );
    final assetsAsync = ref.watch(businessAssetsProvider(query));
    final summaryAsync = ref.watch(businessAssetSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business assets"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_ASSETS", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-dashboard');
          },
        ),
        actions: [
          IconButton(
            onPressed: () {
              _logTap("refresh");
              ref.invalidate(businessAssetsProvider);
              ref.invalidate(businessAssetSummaryProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _isSaving
                ? null
                : () {
                    _logTap("create_asset");
                    _openAssetSheet(context);
                  },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _logTap("pull_to_refresh");
          ref.invalidate(businessAssetsProvider);
          ref.invalidate(businessAssetSummaryProvider);
        },
        child: assetsAsync.when(
          data: (result) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _AssetsSummaryHeader(summaryAsync: summaryAsync),
                const SizedBox(height: 16),
                _StatusFilterRow(
                  summaryAsync: summaryAsync,
                  selected: statusFilter ?? "all",
                  onTap: (value) {
                    _logTap("filter_change", extra: {"status": value});
                    final next = value == "all" ? null : value;
                    ref
                        .read(businessAssetStatusFilterProvider.notifier)
                        .state = next;
                  },
                ),
                const SizedBox(height: 12),
                _AssetsMeta(count: result.assets.length, total: result.total),
                const SizedBox(height: 12),
                if (result.assets.isEmpty)
                  _EmptyState(
                    onCreate: _isSaving
                        ? null
                        : () {
                            _logTap("empty_state_create");
                            _openAssetSheet(context);
                          },
                  )
                else
                  ...result.assets.map(
                    (asset) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _AssetCard(
                        asset: asset,
                        isBusy: _busyAssetId == asset.id,
                        onOpen: () {
                          _logTap("open_detail", extra: {"assetId": asset.id});
                          context.push(
                            '/business-assets/${asset.id}',
                            extra: asset,
                          );
                        },
                        onEdit: _isSaving
                            ? null
                            : () {
                                _logTap(
                                  "edit_asset",
                                  extra: {"assetId": asset.id},
                                );
                                _openAssetSheet(context, asset: asset);
                              },
                        onDelete: _isSaving
                            ? null
                            : () {
                                _logTap(
                                  "delete_asset",
                                  extra: {"assetId": asset.id},
                                );
                                _confirmDelete(context, asset);
                              },
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            AppDebug.log(
              "BUSINESS_ASSETS",
              "Load failed",
              extra: {"error": error.toString()},
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
                Center(child: Text("Failed to load assets")),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 2,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    AppDebug.log("BUSINESS_ASSETS", "Bottom nav tapped", extra: {"index": index});
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
        context.go('/settings');
        return;
    }
  }

  Future<void> _openAssetSheet(
    BuildContext context, {
    BusinessAsset? asset,
  }) async {
    // WHY: Reuse one modal for both create + edit flows.
    final nameCtrl = TextEditingController(text: asset?.name ?? '');
    final descriptionCtrl = TextEditingController(
      text: asset?.description ?? '',
    );
    final serialCtrl = TextEditingController(text: asset?.serialNumber ?? '');
    final locationCtrl = TextEditingController(text: asset?.location ?? '');

    var selectedType = asset?.assetType ?? 'equipment';
    var selectedStatus = asset?.status ?? 'active';

    _logTap("asset_form_open", extra: {"mode": asset == null ? "create" : "edit"});

    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset == null ? "New asset" : "Edit asset",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: "Asset name"),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: "Asset type"),
                      items: _assetTypeOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option["value"],
                              child: Text(option["label"] ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => selectedType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      decoration: const InputDecoration(labelText: "Status"),
                      items: _statusOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option["value"],
                              child: Text(option["label"] ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => selectedStatus = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: serialCtrl,
                      decoration: const InputDecoration(
                        labelText: "Serial number",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(labelText: "Location"),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Description",
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _logTap("asset_form_cancel");
                              Navigator.of(context).pop();
                            },
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final trimmedName = nameCtrl.text.trim();
                              if (trimmedName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Asset name is required"),
                                  ),
                                );
                                return;
                              }

                              Navigator.of(context).pop({
                                "name": trimmedName,
                                "assetType": selectedType,
                                "status": selectedStatus,
                                "serialNumber": serialCtrl.text.trim(),
                                "location": locationCtrl.text.trim(),
                                "description": descriptionCtrl.text.trim(),
                              });
                            },
                            child: Text(asset == null ? "Create" : "Save"),
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
      },
    );

    if (payload == null) {
      _logTap("asset_form_dismiss");
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _busyAssetId = asset?.id;
    });

    try {
      final api = ref.read(businessAssetApiProvider);
      if (asset == null) {
        _logTap("asset_create_request");
        await api.createAsset(token: session.token, payload: payload);
      } else {
        _logTap("asset_update_request", extra: {"assetId": asset.id});
        await api.updateAsset(
          token: session.token,
          id: asset.id,
          payload: payload,
        );
      }

      ref.invalidate(businessAssetsProvider);
      ref.invalidate(businessAssetSummaryProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(asset == null ? "Asset created" : "Asset updated"),
        ),
      );
    } catch (e) {
      AppDebug.log(
        "BUSINESS_ASSETS",
        "Asset save failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to save asset")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _busyAssetId = null;
        });
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, BusinessAsset asset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Archive asset"),
        content: const Text(
          "This will move the asset to inactive status. Continue?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Archive"),
          ),
        ],
      ),
    );

    if (confirm != true) {
      _logTap("asset_delete_cancel", extra: {"assetId": asset.id});
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _busyAssetId = asset.id;
    });

    try {
      final api = ref.read(businessAssetApiProvider);
      await api.deleteAsset(token: session.token, id: asset.id);

      ref.invalidate(businessAssetsProvider);
      ref.invalidate(businessAssetSummaryProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Asset archived")),
      );
    } catch (e) {
      AppDebug.log(
        "BUSINESS_ASSETS",
        "Archive failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to archive asset")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _busyAssetId = null;
        });
      }
    }
  }
}

class _AssetsSummaryHeader extends StatelessWidget {
  final AsyncValue<BusinessAssetSummary> summaryAsync;

  const _AssetsSummaryHeader({required this.summaryAsync});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [scheme.surface, scheme.surfaceVariant],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Operational assets",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Monitor vehicles, equipment, and warehouse readiness.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          summaryAsync.when(
            data: (summary) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(
                  label: "Total",
                  value: summary.total.toString(),
                ),
                _MetricChip(
                  label: "Active",
                  value: summary.active.toString(),
                ),
                _MetricChip(
                  label: "Maintenance",
                  value: summary.maintenance.toString(),
                ),
                _MetricChip(
                  label: "Inactive",
                  value: summary.inactive.toString(),
                ),
              ],
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => Text(
              "Analytics unavailable",
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterRow extends StatelessWidget {
  final AsyncValue<BusinessAssetSummary> summaryAsync;
  final String selected;
  final ValueChanged<String> onTap;

  const _StatusFilterRow({
    required this.summaryAsync,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return summaryAsync.when(
      data: (summary) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatusChip(
            label: "All",
            count: summary.total,
            selected: selected == "all",
            tone: AppStatusTone.neutral,
            onTap: () => onTap("all"),
          ),
          _StatusChip(
            label: "Active",
            count: summary.active,
            selected: selected == "active",
            tone: AppStatusTone.success,
            onTap: () => onTap("active"),
          ),
          _StatusChip(
            label: "Maintenance",
            count: summary.maintenance,
            selected: selected == "maintenance",
            tone: AppStatusTone.warning,
            onTap: () => onTap("maintenance"),
          ),
          _StatusChip(
            label: "Inactive",
            count: summary.inactive,
            selected: selected == "inactive",
            tone: AppStatusTone.neutral,
            onTap: () => onTap("inactive"),
          ),
        ],
      ),
      loading: () => Text(
        "Loading status filters...",
        style: theme.textTheme.bodySmall,
      ),
      error: (_, __) => Text(
        "Unable to load filters",
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final AppStatusTone tone;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);

    return ChoiceChip(
      label: Text("$label $count"),
      selected: selected,
      selectedColor: badge.background,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: selected ? badge.foreground : theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _AssetsMeta extends StatelessWidget {
  final int count;
  final int total;

  const _AssetsMeta({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Text(
      "Showing $count of $total assets",
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  final BusinessAsset asset;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onOpen;
  final bool isBusy;

  const _AssetCard({
    required this.asset,
    required this.isBusy,
    this.onEdit,
    this.onDelete,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = switch (asset.status) {
      "active" => AppStatusTone.success,
      "maintenance" => AppStatusTone.warning,
      _ => AppStatusTone.neutral,
    };
    final badge = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badge.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _assetIcon(asset.assetType),
                  color: badge.foreground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            asset.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isBusy)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _assetTypeLabel(asset.assetType),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Pill(
                          label: _statusLabel(asset.status),
                          background: badge.background,
                          foreground: badge.foreground,
                        ),
                        if (asset.serialNumber != null &&
                            asset.serialNumber!.isNotEmpty)
                          _Pill(
                            label: "SN ${asset.serialNumber}",
                            background: scheme.surfaceVariant,
                            foreground: scheme.onSurfaceVariant,
                          ),
                        if (asset.location != null &&
                            asset.location!.isNotEmpty)
                          _Pill(
                            label: asset.location!,
                            background: scheme.surfaceVariant,
                            foreground: scheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    if (asset.description != null &&
                        asset.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        asset.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == "edit") {
                    onEdit?.call();
                  } else if (value == "delete") {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: "edit",
                    enabled: onEdit != null,
                    child: const Text("Edit"),
                  ),
                  PopupMenuItem(
                    value: "delete",
                    enabled: onDelete != null,
                    child: const Text("Archive"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _assetIcon(String type) {
    switch (type) {
      case "vehicle":
        return Icons.local_shipping_outlined;
      case "equipment":
        return Icons.handyman_outlined;
      case "warehouse":
        return Icons.warehouse_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  String _assetTypeLabel(String type) {
    final option = _assetTypeOptions.firstWhere(
      (item) => item["value"] == type,
      orElse: () => const {"label": "Other"},
    );
    return option["label"] ?? type;
  }

  String _statusLabel(String status) {
    final option = _statusOptions.firstWhere(
      (item) => item["value"] == status,
      orElse: () => const {"label": "Inactive"},
    );
    return option["label"] ?? status;
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onCreate;

  const _EmptyState({this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "No assets yet",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Track vehicles, equipment, and warehouse locations here.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text("Add your first asset"),
          ),
        ],
      ),
    );
  }
}
