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
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_asset_helpers.dart';
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
    final query = BusinessAssetsQuery(status: statusFilter, page: 1, limit: 20);
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
            onPressed: () async {
              _logTap("refresh");
              // WHY: Central refresh keeps business data in sync across screens.
              await AppRefresh.refreshApp(
                ref: ref,
                source: "business_assets_refresh",
              );
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
          // WHY: Central refresh keeps business data in sync across screens.
          await AppRefresh.refreshApp(
            ref: ref,
            source: "business_assets_pull",
          );
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
                    ref.read(businessAssetStatusFilterProvider.notifier).state =
                        next;
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
    AppDebug.log(
      "BUSINESS_ASSETS",
      "Bottom nav tapped",
      extra: {"index": index},
    );
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
  }

  /// ------------------------------------------------------------
  /// INPUT PARSERS
  /// ------------------------------------------------------------
  /// WHY:
  /// - Keep form parsing consistent for numeric + date fields.
  double? _parseDoubleInput(String value) {
    // WHY: Allow formatted NGN values with commas/prefixes.
    return parseNgnInput(value);
  }

  int? _parseIntInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  DateTime? _parseDateInput(String value) {
    // WHY: Centralize date parsing to keep input handling consistent.
    return parseDateInput(value);
  }

  String _formatDateInput(DateTime? value) {
    // WHY: Centralize date formatting for input fields.
    return formatDateInput(value);
  }

  String _formatNumberInput(num? value) {
    if (value == null) return '';
    // WHY: Format monetary values for display in input fields.
    return formatNgnInput(value);
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
    final purchaseCostCtrl = TextEditingController(
      text: _formatNumberInput(asset?.purchaseCost),
    );
    final purchaseDateCtrl = TextEditingController(
      text: _formatDateInput(asset?.purchaseDate),
    );
    final usefulLifeCtrl = TextEditingController(
      text: asset?.usefulLifeMonths?.toString() ?? '',
    );
    final salvageCtrl = TextEditingController(
      text: _formatNumberInput(asset?.salvageValue),
    );
    final leaseStartCtrl = TextEditingController(
      text: _formatDateInput(asset?.leaseStart),
    );
    final leaseEndCtrl = TextEditingController(
      text: _formatDateInput(asset?.leaseEnd),
    );
    final leaseCostCtrl = TextEditingController(
      text: _formatNumberInput(asset?.leaseCostAmount),
    );
    final lessorCtrl = TextEditingController(text: asset?.lessorName ?? '');
    final leaseTermsCtrl = TextEditingController(text: asset?.leaseTerms ?? '');
    final managementFeeCtrl = TextEditingController(
      text: _formatNumberInput(asset?.managementFeeAmount),
    );
    final clientNameCtrl = TextEditingController(text: asset?.clientName ?? '');
    final serviceTermsCtrl = TextEditingController(
      text: asset?.serviceTerms ?? '',
    );
    final inventoryQtyCtrl = TextEditingController(
      text: asset?.inventory?.quantity.toString() ?? '',
    );
    final inventoryUnitCostCtrl = TextEditingController(
      text: _formatNumberInput(asset?.inventory?.unitCost),
    );
    final inventoryReorderCtrl = TextEditingController(
      text: asset?.inventory?.reorderLevel.toString() ?? '',
    );
    final inventoryUnitCtrl = TextEditingController(
      text: asset?.inventory?.unitOfMeasure ?? '',
    );
    final estateHouseCtrl = TextEditingController(
      text: asset?.estate?.propertyAddress?.houseNumber ?? '',
    );
    final estateStreetCtrl = TextEditingController(
      text: asset?.estate?.propertyAddress?.street ?? '',
    );
    final estateCityCtrl = TextEditingController(
      text: asset?.estate?.propertyAddress?.city ?? '',
    );
    final estateStateCtrl = TextEditingController(
      text: asset?.estate?.propertyAddress?.state ?? '',
    );
    final estatePostalCtrl = TextEditingController(
      text: asset?.estate?.propertyAddress?.postalCode ?? '',
    );
    final estateLgaCtrl = TextEditingController(
      text: asset?.estate?.propertyAddress?.lga ?? '',
    );
    final estateLandmarkCtrl = TextEditingController(
      text: asset?.estate?.propertyAddress?.landmark ?? '',
    );
    final referencesMinCtrl = TextEditingController(
      text: asset?.estate?.tenantRules.referencesMin.toString() ?? '1',
    );
    final referencesMaxCtrl = TextEditingController(
      text: asset?.estate?.tenantRules.referencesMax.toString() ?? '2',
    );
    final guarantorsMinCtrl = TextEditingController(
      text: asset?.estate?.tenantRules.guarantorsMin.toString() ?? '1',
    );
    final guarantorsMaxCtrl = TextEditingController(
      text: asset?.estate?.tenantRules.guarantorsMax.toString() ?? '2',
    );

    var selectedType = asset?.assetType ?? 'equipment';
    var selectedOwnership = asset?.ownershipType ?? 'owned';
    var selectedAssetClass =
        asset?.assetClass ?? assetClassForType(selectedType);
    var selectedStatus = asset?.status ?? 'active';
    var selectedLeasePeriod = asset?.leaseCostPeriod ?? 'monthly';
    var selectedManagementPeriod = asset?.managementFeePeriod ?? 'monthly';

    final unitMixRows = <_UnitMixControllers>[
      ...?asset?.estate?.unitMix.map(
        (unit) => _UnitMixControllers.fromUnit(unit),
      ),
    ];

    // WHY: Estate assets require at least one unit definition.
    if (unitMixRows.isEmpty) {
      unitMixRows.add(_UnitMixControllers.empty());
    }

    _logTap(
      "asset_form_open",
      extra: {"mode": asset == null ? "create" : "edit"},
    );

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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset == null ? "New asset" : "Edit asset",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Asset name",
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(
                          labelText: "Asset type",
                        ),
                        items: assetTypeOptions
                            .map(
                              (option) => DropdownMenuItem(
                                value: option["value"],
                                child: Text(option["label"] ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          // WHY: Keep asset class aligned with the selected type.
                          setSheetState(() {
                            selectedType = value;
                            selectedAssetClass = assetClassForType(value);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedOwnership,
                        decoration: const InputDecoration(
                          labelText: "Ownership type",
                        ),
                        items: ownershipTypeOptions
                            .map(
                              (option) => DropdownMenuItem(
                                value: option["value"],
                                child: Text(option["label"] ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => selectedOwnership = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedAssetClass,
                        decoration: const InputDecoration(
                          labelText: "Asset class",
                        ),
                        items: assetClassOptions
                            .map(
                              (option) => DropdownMenuItem(
                                value: option["value"],
                                child: Text(option["label"] ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => selectedAssetClass = value);
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Tip: We suggest '${assetClassForType(selectedType)}' for this type.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
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
                        decoration: const InputDecoration(
                          labelText: "Location",
                        ),
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
                      if (requiresPurchaseFields(
                        selectedAssetClass,
                        selectedOwnership,
                      )) ...[
                        Text(
                          "Fixed asset details",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: purchaseCostCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          // WHY: Auto-format money inputs with commas/decimals.
                          inputFormatters: const [
                            NgnInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: "Purchase cost (NGN)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: purchaseDateCtrl,
                          keyboardType: TextInputType.datetime,
                          decoration: const InputDecoration(
                            labelText: "Purchase date (YYYY-MM-DD)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: usefulLifeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Useful life (months)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: salvageCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          // WHY: Auto-format money inputs with commas/decimals.
                          inputFormatters: const [
                            NgnInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: "Salvage value (optional)",
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (requiresLeaseFields(selectedOwnership)) ...[
                        Text(
                          "Lease details",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: leaseStartCtrl,
                          keyboardType: TextInputType.datetime,
                          decoration: const InputDecoration(
                            labelText: "Lease start (YYYY-MM-DD)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: leaseEndCtrl,
                          keyboardType: TextInputType.datetime,
                          decoration: const InputDecoration(
                            labelText: "Lease end (YYYY-MM-DD)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: leaseCostCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          // WHY: Auto-format money inputs with commas/decimals.
                          inputFormatters: const [
                            NgnInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: "Lease cost amount",
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedLeasePeriod,
                          decoration: const InputDecoration(
                            labelText: "Lease cost period",
                          ),
                          items: feePeriodOptions
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option["value"],
                                  child: Text(option["label"] ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => selectedLeasePeriod = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: lessorCtrl,
                          decoration: const InputDecoration(
                            labelText: "Lessor name (optional)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: leaseTermsCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: "Lease terms (optional)",
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (requiresManagementFields(selectedOwnership)) ...[
                        Text(
                          "Management fees",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: managementFeeCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          // WHY: Auto-format money inputs with commas/decimals.
                          inputFormatters: const [
                            NgnInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: "Management fee amount",
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedManagementPeriod,
                          decoration: const InputDecoration(
                            labelText: "Fee period",
                          ),
                          items: feePeriodOptions
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option["value"],
                                  child: Text(option["label"] ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(
                              () => selectedManagementPeriod = value,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: clientNameCtrl,
                          decoration: const InputDecoration(
                            labelText: "Client name (optional)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: serviceTermsCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: "Service terms (optional)",
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (isInventoryType(selectedType)) ...[
                        Text(
                          "Inventory snapshot",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: inventoryQtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Quantity",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: inventoryUnitCostCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          // WHY: Auto-format money inputs with commas/decimals.
                          inputFormatters: const [
                            NgnInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: "Unit cost",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: inventoryReorderCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Reorder level (optional)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: inventoryUnitCtrl,
                          decoration: const InputDecoration(
                            labelText: "Unit of measure (optional)",
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (isEstateType(selectedType)) ...[
                        Text(
                          "Estate details",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: estateHouseCtrl,
                          decoration: const InputDecoration(
                            labelText: "House number",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estateStreetCtrl,
                          decoration: const InputDecoration(
                            labelText: "Street",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estateCityCtrl,
                          decoration: const InputDecoration(labelText: "City"),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estateStateCtrl,
                          decoration: const InputDecoration(labelText: "State"),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estatePostalCtrl,
                          decoration: const InputDecoration(
                            labelText: "Postal code (optional)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estateLgaCtrl,
                          decoration: const InputDecoration(
                            labelText: "LGA (optional)",
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: estateLandmarkCtrl,
                          decoration: const InputDecoration(
                            labelText: "Landmark (optional)",
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Unit mix",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ...unitMixRows.asMap().entries.map((entry) {
                          final index = entry.key;
                          final row = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: row.unitTypeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: "Unit type",
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: unitMixRows.length == 1
                                            ? null
                                            : () {
                                                _logTap(
                                                  "unit_mix_remove",
                                                  extra: {"index": index},
                                                );
                                                setSheetState(() {
                                                  unitMixRows.removeAt(index);
                                                });
                                              },
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: row.countCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: "Units",
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: row.rentAmountCtrl,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          // WHY: Auto-format rent values as NGN inputs.
                                          inputFormatters: const [
                                            NgnInputFormatter(),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: "Rent amount",
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: row.rentPeriod,
                                    decoration: const InputDecoration(
                                      labelText: "Rent period",
                                    ),
                                    items: rentPeriodOptions
                                        .map(
                                          (option) => DropdownMenuItem(
                                            value: option["value"],
                                            child: Text(option["label"] ?? ''),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setSheetState(
                                        () => row.rentPeriod = value,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _logTap("unit_mix_add");
                              setSheetState(() {
                                unitMixRows.add(_UnitMixControllers.empty());
                              });
                            },
                            icon: const Icon(Icons.add),
                            label: const Text("Add unit"),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Tenant rules",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: referencesMinCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Min references",
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: referencesMaxCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Max references",
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: guarantorsMinCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Min guarantors",
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: guarantorsMaxCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Max guarantors",
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Tenants must be NIN verified and sign agreements before payment.",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                      ],
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

                                // WHY: Enforce required finance fields before submit.
                                if (requiresPurchaseFields(
                                  selectedAssetClass,
                                  selectedOwnership,
                                )) {
                                  final cost = _parseDoubleInput(
                                    purchaseCostCtrl.text,
                                  );
                                  final date = _parseDateInput(
                                    purchaseDateCtrl.text,
                                  );
                                  final life = _parseIntInput(
                                    usefulLifeCtrl.text,
                                  );
                                  if (cost == null ||
                                      date == null ||
                                      life == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Purchase cost, date, and useful life are required.",
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                }

                                if (requiresLeaseFields(selectedOwnership)) {
                                  final leaseStart = _parseDateInput(
                                    leaseStartCtrl.text,
                                  );
                                  final leaseEnd = _parseDateInput(
                                    leaseEndCtrl.text,
                                  );
                                  final leaseCost = _parseDoubleInput(
                                    leaseCostCtrl.text,
                                  );
                                  if (leaseStart == null ||
                                      leaseEnd == null ||
                                      leaseCost == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Lease start, end, and cost are required.",
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                }

                                if (requiresManagementFields(
                                  selectedOwnership,
                                )) {
                                  final fee = _parseDoubleInput(
                                    managementFeeCtrl.text,
                                  );
                                  if (fee == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Management fee amount is required.",
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                }

                                if (isEstateType(selectedType)) {
                                  if (estateHouseCtrl.text.trim().isEmpty ||
                                      estateStreetCtrl.text.trim().isEmpty ||
                                      estateCityCtrl.text.trim().isEmpty ||
                                      estateStateCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Estate address fields are required.",
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  final invalidUnit = unitMixRows.any(
                                    (row) =>
                                        row.unitTypeCtrl.text.trim().isEmpty ||
                                        _parseIntInput(row.countCtrl.text) ==
                                            null ||
                                        _parseDoubleInput(
                                              row.rentAmountCtrl.text,
                                            ) ==
                                            null,
                                  );
                                  if (invalidUnit) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Each unit needs type, count, and rent.",
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                }

                                final payload = <String, dynamic>{
                                  "name": trimmedName,
                                  "assetType": selectedType,
                                  "ownershipType": selectedOwnership,
                                  "assetClass": selectedAssetClass,
                                  "status": selectedStatus,
                                  "serialNumber": serialCtrl.text.trim(),
                                  "location": locationCtrl.text.trim(),
                                  "description": descriptionCtrl.text.trim(),
                                  "purchaseCost": _parseDoubleInput(
                                    purchaseCostCtrl.text,
                                  ),
                                  "purchaseDate": _parseDateInput(
                                    purchaseDateCtrl.text,
                                  )?.toIso8601String(),
                                  "usefulLifeMonths": _parseIntInput(
                                    usefulLifeCtrl.text,
                                  ),
                                  "salvageValue": _parseDoubleInput(
                                    salvageCtrl.text,
                                  ),
                                  "leaseStart": _parseDateInput(
                                    leaseStartCtrl.text,
                                  )?.toIso8601String(),
                                  "leaseEnd": _parseDateInput(
                                    leaseEndCtrl.text,
                                  )?.toIso8601String(),
                                  "leaseCostAmount": _parseDoubleInput(
                                    leaseCostCtrl.text,
                                  ),
                                  "leaseCostPeriod": selectedLeasePeriod,
                                  "lessorName": lessorCtrl.text.trim(),
                                  "leaseTerms": leaseTermsCtrl.text.trim(),
                                  "managementFeeAmount": _parseDoubleInput(
                                    managementFeeCtrl.text,
                                  ),
                                  "managementFeePeriod":
                                      selectedManagementPeriod,
                                  "clientName": clientNameCtrl.text.trim(),
                                  "serviceTerms": serviceTermsCtrl.text.trim(),
                                };

                                if (isInventoryType(selectedType)) {
                                  payload["inventory"] = {
                                    "quantity":
                                        _parseIntInput(inventoryQtyCtrl.text) ??
                                        0,
                                    "unitCost":
                                        _parseDoubleInput(
                                          inventoryUnitCostCtrl.text,
                                        ) ??
                                        0,
                                    "reorderLevel":
                                        _parseIntInput(
                                          inventoryReorderCtrl.text,
                                        ) ??
                                        0,
                                    "unitOfMeasure": inventoryUnitCtrl.text
                                        .trim(),
                                  };
                                }

                                if (isEstateType(selectedType)) {
                                  payload["estate"] = {
                                    "propertyAddress": {
                                      "houseNumber": estateHouseCtrl.text
                                          .trim(),
                                      "street": estateStreetCtrl.text.trim(),
                                      "city": estateCityCtrl.text.trim(),
                                      "state": estateStateCtrl.text.trim(),
                                      "postalCode": estatePostalCtrl.text
                                          .trim(),
                                      "lga": estateLgaCtrl.text.trim(),
                                      "landmark": estateLandmarkCtrl.text
                                          .trim(),
                                      "country": "Nigeria",
                                    },
                                    "unitMix": unitMixRows
                                        .map(
                                          (row) => {
                                            "unitType": row.unitTypeCtrl.text
                                                .trim(),
                                            "count":
                                                _parseIntInput(
                                                  row.countCtrl.text,
                                                ) ??
                                                0,
                                            "rentAmount":
                                                _parseDoubleInput(
                                                  row.rentAmountCtrl.text,
                                                ) ??
                                                0,
                                            "rentPeriod": row.rentPeriod,
                                          },
                                        )
                                        .toList(),
                                    "tenantRules": {
                                      "referencesMin":
                                          _parseIntInput(
                                            referencesMinCtrl.text,
                                          ) ??
                                          1,
                                      "referencesMax":
                                          _parseIntInput(
                                            referencesMaxCtrl.text,
                                          ) ??
                                          2,
                                      "guarantorsMin":
                                          _parseIntInput(
                                            guarantorsMinCtrl.text,
                                          ) ??
                                          1,
                                      "guarantorsMax":
                                          _parseIntInput(
                                            guarantorsMaxCtrl.text,
                                          ) ??
                                          2,
                                      "requiresNinVerified": true,
                                      "requiresAgreementSigned": true,
                                    },
                                  };
                                }

                                payload.removeWhere(
                                  (key, value) =>
                                      value == null ||
                                      (value is String && value.trim().isEmpty),
                                );

                                Navigator.of(context).pop(payload);
                              },
                              child: Text(asset == null ? "Create" : "Save"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // WHY: Dispose modal controllers after the sheet closes to avoid leaks.
    void disposeControllers() {
      nameCtrl.dispose();
      descriptionCtrl.dispose();
      serialCtrl.dispose();
      locationCtrl.dispose();
      purchaseCostCtrl.dispose();
      purchaseDateCtrl.dispose();
      usefulLifeCtrl.dispose();
      salvageCtrl.dispose();
      leaseStartCtrl.dispose();
      leaseEndCtrl.dispose();
      leaseCostCtrl.dispose();
      lessorCtrl.dispose();
      leaseTermsCtrl.dispose();
      managementFeeCtrl.dispose();
      clientNameCtrl.dispose();
      serviceTermsCtrl.dispose();
      inventoryQtyCtrl.dispose();
      inventoryUnitCostCtrl.dispose();
      inventoryReorderCtrl.dispose();
      inventoryUnitCtrl.dispose();
      estateHouseCtrl.dispose();
      estateStreetCtrl.dispose();
      estateCityCtrl.dispose();
      estateStateCtrl.dispose();
      estatePostalCtrl.dispose();
      estateLgaCtrl.dispose();
      estateLandmarkCtrl.dispose();
      referencesMinCtrl.dispose();
      referencesMaxCtrl.dispose();
      guarantorsMinCtrl.dispose();
      guarantorsMaxCtrl.dispose();
      for (final row in unitMixRows) {
        row.dispose();
      }
    }

    disposeControllers();

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
      // WHY: Refresh shared data so other screens reflect asset changes.
      await AppRefresh.refreshApp(
        ref: ref,
        source: asset == null
            ? "business_asset_create_success"
            : "business_asset_update_success",
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Unable to save asset")));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Asset archived")));
    } catch (e) {
      AppDebug.log(
        "BUSINESS_ASSETS",
        "Archive failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Unable to archive asset")));
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
          colors: [scheme.surface, scheme.surfaceContainerHighest],
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
                _MetricChip(label: "Total", value: summary.total.toString()),
                _MetricChip(label: "Active", value: summary.active.toString()),
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
      loading: () =>
          Text("Loading status filters...", style: theme.textTheme.bodySmall),
      error: (_, __) =>
          Text("Unable to load filters", style: theme.textTheme.bodySmall),
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
                            background: scheme.surfaceContainerHighest,
                            foreground: scheme.onSurfaceVariant,
                          ),
                        if (asset.location != null &&
                            asset.location!.isNotEmpty)
                          _Pill(
                            label: asset.location!,
                            background: scheme.surfaceContainerHighest,
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
    final option = assetTypeOptions.firstWhere(
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

/// ------------------------------------------------------------
/// UNIT MIX CONTROLLERS
/// ------------------------------------------------------------
/// WHY:
/// - Keeps unit mix inputs grouped so estate assets can be edited cleanly.
class _UnitMixControllers {
  final TextEditingController unitTypeCtrl;
  final TextEditingController countCtrl;
  final TextEditingController rentAmountCtrl;
  String rentPeriod;

  _UnitMixControllers({
    required this.unitTypeCtrl,
    required this.countCtrl,
    required this.rentAmountCtrl,
    required this.rentPeriod,
  });

  // WHY: Seed rows from existing estate unit data.
  factory _UnitMixControllers.fromUnit(BusinessAssetUnitMix unit) {
    return _UnitMixControllers(
      unitTypeCtrl: TextEditingController(text: unit.unitType),
      countCtrl: TextEditingController(text: unit.count.toString()),
      rentAmountCtrl: TextEditingController(
        text: formatNgnInputFromKobo(unit.rentAmount),
      ),
      rentPeriod: unit.rentPeriod,
    );
  }

  // WHY: Provide a blank row for new estate unit mix entries.
  factory _UnitMixControllers.empty() {
    return _UnitMixControllers(
      unitTypeCtrl: TextEditingController(),
      countCtrl: TextEditingController(),
      rentAmountCtrl: TextEditingController(),
      rentPeriod: 'monthly',
    );
  }

  // WHY: Dispose controllers once the sheet closes.
  void dispose() {
    unitTypeCtrl.dispose();
    countCtrl.dispose();
    rentAmountCtrl.dispose();
  }
}
