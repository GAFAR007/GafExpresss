/// lib/app/features/home/presentation/business_asset_detail_screen.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Detail + edit screen for a single business asset.
///
/// WHY:
/// - Lets owners/staff update asset fields with full context.
/// - Keeps audits readable by surfacing immutable metadata.
///
/// HOW:
/// - Receives BusinessAsset via route `extra`.
/// - Prefills form controllers and updates via BusinessAssetApi.
/// - Logs build, taps, and API flow for traceability.
/// ------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_asset_helpers.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessAssetDetailScreen extends ConsumerStatefulWidget {
  final BusinessAsset asset;

  const BusinessAssetDetailScreen({super.key, required this.asset});

  @override
  ConsumerState<BusinessAssetDetailScreen> createState() =>
      _BusinessAssetDetailScreenState();
}

class _BusinessAssetDetailScreenState
    extends ConsumerState<BusinessAssetDetailScreen> {
  // WHY: Controllers keep user input stable across rebuilds.
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _purchaseCostCtrl = TextEditingController();
  final _purchaseDateCtrl = TextEditingController();
  final _usefulLifeCtrl = TextEditingController();
  final _salvageCtrl = TextEditingController();
  final _leaseStartCtrl = TextEditingController();
  final _leaseEndCtrl = TextEditingController();
  final _leaseCostCtrl = TextEditingController();
  final _lessorCtrl = TextEditingController();
  final _leaseTermsCtrl = TextEditingController();
  final _managementFeeCtrl = TextEditingController();
  final _clientNameCtrl = TextEditingController();
  final _serviceTermsCtrl = TextEditingController();
  final _inventoryQtyCtrl = TextEditingController();
  final _inventoryUnitCostCtrl = TextEditingController();
  final _inventoryReorderCtrl = TextEditingController();
  final _inventoryUnitCtrl = TextEditingController();
  final _estateHouseCtrl = TextEditingController();
  final _estateStreetCtrl = TextEditingController();
  final _estateCityCtrl = TextEditingController();
  final _estateStateCtrl = TextEditingController();
  final _estatePostalCtrl = TextEditingController();
  final _estateLgaCtrl = TextEditingController();
  final _estateLandmarkCtrl = TextEditingController();
  final _referencesMinCtrl = TextEditingController();
  final _referencesMaxCtrl = TextEditingController();
  final _guarantorsMinCtrl = TextEditingController();
  final _guarantorsMaxCtrl = TextEditingController();

  // WHY: Track dropdown values separately for controlled updates.
  String _assetType = 'equipment';
  String _ownershipType = 'owned';
  String _assetClass = 'fixed';
  String _status = 'active';
  String _leasePeriod = 'monthly';
  String _managementPeriod = 'monthly';

  bool _isSaving = false;
  final List<_UnitMixControllers> _unitMixRows = [];

  static const List<Map<String, String>> _statusOptions = [
    {"value": "active", "label": "Active"},
    {"value": "maintenance", "label": "Maintenance"},
    {"value": "inactive", "label": "Inactive"},
  ];

  void _logFlow(String step, String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      "BUSINESS_ASSET_DETAIL",
      "$step | $message",
      extra: extra,
    );
  }

  @override
  void initState() {
    super.initState();
    _applyAsset(widget.asset);
  }

  @override
  void dispose() {
    // WHY: Dispose controllers to prevent memory leaks.
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _serialCtrl.dispose();
    _locationCtrl.dispose();
    _purchaseCostCtrl.dispose();
    _purchaseDateCtrl.dispose();
    _usefulLifeCtrl.dispose();
    _salvageCtrl.dispose();
    _leaseStartCtrl.dispose();
    _leaseEndCtrl.dispose();
    _leaseCostCtrl.dispose();
    _lessorCtrl.dispose();
    _leaseTermsCtrl.dispose();
    _managementFeeCtrl.dispose();
    _clientNameCtrl.dispose();
    _serviceTermsCtrl.dispose();
    _inventoryQtyCtrl.dispose();
    _inventoryUnitCostCtrl.dispose();
    _inventoryReorderCtrl.dispose();
    _inventoryUnitCtrl.dispose();
    _estateHouseCtrl.dispose();
    _estateStreetCtrl.dispose();
    _estateCityCtrl.dispose();
    _estateStateCtrl.dispose();
    _estatePostalCtrl.dispose();
    _estateLgaCtrl.dispose();
    _estateLandmarkCtrl.dispose();
    _referencesMinCtrl.dispose();
    _referencesMaxCtrl.dispose();
    _guarantorsMinCtrl.dispose();
    _guarantorsMaxCtrl.dispose();
    for (final row in _unitMixRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _applyAsset(BusinessAsset asset) {
    // WHY: Prefill fields so the edit form starts with known values.
    _nameCtrl.text = asset.name;
    _descriptionCtrl.text = asset.description ?? '';
    _serialCtrl.text = asset.serialNumber ?? '';
    _locationCtrl.text = asset.location ?? '';
    _assetType = asset.assetType;
    _ownershipType = asset.ownershipType;
    _assetClass = asset.assetClass;
    _status = asset.status;
    _leasePeriod = asset.leaseCostPeriod ?? 'monthly';
    _managementPeriod = asset.managementFeePeriod ?? 'monthly';
    _purchaseCostCtrl.text = _formatNumberInput(asset.purchaseCost);
    _purchaseDateCtrl.text = _formatDateInput(asset.purchaseDate);
    _usefulLifeCtrl.text = asset.usefulLifeMonths?.toString() ?? '';
    _salvageCtrl.text = _formatNumberInput(asset.salvageValue);
    _leaseStartCtrl.text = _formatDateInput(asset.leaseStart);
    _leaseEndCtrl.text = _formatDateInput(asset.leaseEnd);
    _leaseCostCtrl.text = _formatNumberInput(asset.leaseCostAmount);
    _lessorCtrl.text = asset.lessorName ?? '';
    _leaseTermsCtrl.text = asset.leaseTerms ?? '';
    _managementFeeCtrl.text = _formatNumberInput(asset.managementFeeAmount);
    _clientNameCtrl.text = asset.clientName ?? '';
    _serviceTermsCtrl.text = asset.serviceTerms ?? '';
    _inventoryQtyCtrl.text = asset.inventory?.quantity.toString() ?? '';
    _inventoryUnitCostCtrl.text = _formatNumberInput(asset.inventory?.unitCost);
    _inventoryReorderCtrl.text =
        asset.inventory?.reorderLevel.toString() ?? '';
    _inventoryUnitCtrl.text = asset.inventory?.unitOfMeasure ?? '';
    _estateHouseCtrl.text = asset.estate?.propertyAddress?.houseNumber ?? '';
    _estateStreetCtrl.text = asset.estate?.propertyAddress?.street ?? '';
    _estateCityCtrl.text = asset.estate?.propertyAddress?.city ?? '';
    _estateStateCtrl.text = asset.estate?.propertyAddress?.state ?? '';
    _estatePostalCtrl.text = asset.estate?.propertyAddress?.postalCode ?? '';
    _estateLgaCtrl.text = asset.estate?.propertyAddress?.lga ?? '';
    _estateLandmarkCtrl.text = asset.estate?.propertyAddress?.landmark ?? '';
    _referencesMinCtrl.text =
        asset.estate?.tenantRules.referencesMin.toString() ?? '1';
    _referencesMaxCtrl.text =
        asset.estate?.tenantRules.referencesMax.toString() ?? '2';
    _guarantorsMinCtrl.text =
        asset.estate?.tenantRules.guarantorsMin.toString() ?? '1';
    _guarantorsMaxCtrl.text =
        asset.estate?.tenantRules.guarantorsMax.toString() ?? '2';

    // WHY: Reset unit mix list before re-populating from the asset.
    _unitMixRows
      ..clear()
      ..addAll(
        asset.estate?.unitMix
                .map((unit) => _UnitMixControllers.fromUnit(unit))
                .toList() ??
            [],
      );

    // WHY: Estate assets must always show at least one unit row.
    if (isEstateType(_assetType) && _unitMixRows.isEmpty) {
      _unitMixRows.add(_UnitMixControllers.empty());
    }
  }

  /// ------------------------------------------------------------
  /// INPUT PARSERS
  /// ------------------------------------------------------------
  /// WHY:
  /// - Keep numeric + date parsing safe and consistent.
  double? _parseDoubleInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  int? _parseIntInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  DateTime? _parseDateInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }

  String _formatDateInput(DateTime? value) {
    if (value == null) return '';
    return value.toIso8601String().split('T').first;
  }

  String _formatNumberInput(num? value) {
    if (value == null) return '';
    return value.toString();
  }

  Future<void> _saveChanges() async {
    if (_isSaving) {
      _logFlow("SAVE_BLOCK", "Save ignored (already saving)");
      return;
    }

    _logFlow("SAVE_TAP", "Save tapped", extra: {"assetId": widget.asset.id});

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _logFlow("SAVE_BLOCK", "Missing session");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.isEmpty) {
      _logFlow("SAVE_BLOCK", "Missing asset name");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Asset name is required")),
      );
      return;
    }

    // WHY: Enforce required finance fields before submit.
    if (requiresPurchaseFields(_assetClass, _ownershipType)) {
      final cost = _parseDoubleInput(_purchaseCostCtrl.text);
      final date = _parseDateInput(_purchaseDateCtrl.text);
      final life = _parseIntInput(_usefulLifeCtrl.text);
      if (cost == null || date == null || life == null) {
        _logFlow("SAVE_BLOCK", "Missing fixed asset fields");
        if (!mounted) return;
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

    if (requiresLeaseFields(_ownershipType)) {
      final leaseStart = _parseDateInput(_leaseStartCtrl.text);
      final leaseEnd = _parseDateInput(_leaseEndCtrl.text);
      final leaseCost = _parseDoubleInput(_leaseCostCtrl.text);
      if (leaseStart == null || leaseEnd == null || leaseCost == null) {
        _logFlow("SAVE_BLOCK", "Missing lease fields");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Lease start, end, and cost are required."),
          ),
        );
        return;
      }
    }

    if (requiresManagementFields(_ownershipType)) {
      final fee = _parseDoubleInput(_managementFeeCtrl.text);
      if (fee == null) {
        _logFlow("SAVE_BLOCK", "Missing management fee");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Management fee amount is required."),
          ),
        );
        return;
      }
    }

    if (isEstateType(_assetType)) {
      if (_estateHouseCtrl.text.trim().isEmpty ||
          _estateStreetCtrl.text.trim().isEmpty ||
          _estateCityCtrl.text.trim().isEmpty ||
          _estateStateCtrl.text.trim().isEmpty) {
        _logFlow("SAVE_BLOCK", "Missing estate address fields");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Estate address fields are required."),
          ),
        );
        return;
      }

      final invalidUnit = _unitMixRows.any(
        (row) =>
            row.unitTypeCtrl.text.trim().isEmpty ||
            _parseIntInput(row.countCtrl.text) == null ||
            _parseDoubleInput(row.rentAmountCtrl.text) == null,
      );
      if (invalidUnit) {
        _logFlow("SAVE_BLOCK", "Invalid unit mix rows");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Each unit needs type, count, and rent."),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    final payload = {
      "name": trimmedName,
      "assetType": _assetType,
      "ownershipType": _ownershipType,
      "assetClass": _assetClass,
      "status": _status,
      "serialNumber": _serialCtrl.text.trim(),
      "location": _locationCtrl.text.trim(),
      "description": _descriptionCtrl.text.trim(),
      "purchaseCost": _parseDoubleInput(_purchaseCostCtrl.text),
      "purchaseDate": _parseDateInput(_purchaseDateCtrl.text)?.toIso8601String(),
      "usefulLifeMonths": _parseIntInput(_usefulLifeCtrl.text),
      "salvageValue": _parseDoubleInput(_salvageCtrl.text),
      "leaseStart": _parseDateInput(_leaseStartCtrl.text)?.toIso8601String(),
      "leaseEnd": _parseDateInput(_leaseEndCtrl.text)?.toIso8601String(),
      "leaseCostAmount": _parseDoubleInput(_leaseCostCtrl.text),
      "leaseCostPeriod": _leasePeriod,
      "lessorName": _lessorCtrl.text.trim(),
      "leaseTerms": _leaseTermsCtrl.text.trim(),
      "managementFeeAmount": _parseDoubleInput(_managementFeeCtrl.text),
      "managementFeePeriod": _managementPeriod,
      "clientName": _clientNameCtrl.text.trim(),
      "serviceTerms": _serviceTermsCtrl.text.trim(),
    };

    if (isInventoryType(_assetType)) {
      payload["inventory"] = {
        "quantity": _parseIntInput(_inventoryQtyCtrl.text) ?? 0,
        "unitCost": _parseDoubleInput(_inventoryUnitCostCtrl.text) ?? 0,
        "reorderLevel": _parseIntInput(_inventoryReorderCtrl.text) ?? 0,
        "unitOfMeasure": _inventoryUnitCtrl.text.trim(),
      };
    }

    if (isEstateType(_assetType)) {
      payload["estate"] = {
        "propertyAddress": {
          "houseNumber": _estateHouseCtrl.text.trim(),
          "street": _estateStreetCtrl.text.trim(),
          "city": _estateCityCtrl.text.trim(),
          "state": _estateStateCtrl.text.trim(),
          "postalCode": _estatePostalCtrl.text.trim(),
          "lga": _estateLgaCtrl.text.trim(),
          "landmark": _estateLandmarkCtrl.text.trim(),
          "country": "Nigeria",
        },
        "unitMix": _unitMixRows
            .map(
              (row) => {
                "unitType": row.unitTypeCtrl.text.trim(),
                "count": _parseIntInput(row.countCtrl.text) ?? 0,
                "rentAmount": _parseDoubleInput(row.rentAmountCtrl.text) ?? 0,
                "rentPeriod": row.rentPeriod,
              },
            )
            .toList(),
        "tenantRules": {
          "referencesMin": _parseIntInput(_referencesMinCtrl.text) ?? 1,
          "referencesMax": _parseIntInput(_referencesMaxCtrl.text) ?? 2,
          "guarantorsMin": _parseIntInput(_guarantorsMinCtrl.text) ?? 1,
          "guarantorsMax": _parseIntInput(_guarantorsMaxCtrl.text) ?? 2,
          "requiresNinVerified": true,
          "requiresAgreementSigned": true,
        },
      };
    }

    payload.removeWhere(
      (key, value) => value == null || (value is String && value.trim().isEmpty),
    );

    try {
      final api = ref.read(businessAssetApiProvider);
      _logFlow("SAVE_REQUEST", "Updating asset", extra: {"assetId": widget.asset.id});
      await api.updateAsset(
        token: session.token,
        id: widget.asset.id,
        payload: payload,
      );

      // WHY: Refresh list + summary so analytics stay in sync.
      ref.invalidate(businessAssetsProvider);
      ref.invalidate(businessAssetSummaryProvider);

      if (!mounted) return;
      _logFlow("SAVE_OK", "Asset updated", extra: {"assetId": widget.asset.id});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Asset updated successfully")),
      );
    } catch (e) {
      _logFlow("SAVE_FAIL", "Asset update failed", extra: {"error": e.toString()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to update asset")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "BUSINESS_ASSET_DETAIL",
      "build()",
      extra: {"assetId": widget.asset.id},
    );

    final theme = Theme.of(context);
    final statusColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: _status == "active"
          ? AppStatusTone.success
          : _status == "maintenance"
          ? AppStatusTone.warning
          : AppStatusTone.neutral,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Asset details"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _logFlow("BACK_TAP", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-assets');
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.asset.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColors.background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _status.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Editable fields",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: "Asset name"),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _assetType,
            decoration: const InputDecoration(labelText: "Asset type"),
            items: assetTypeOptions
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
                    _logFlow(
                      "TYPE_CHANGE",
                      "Asset type changed",
                      extra: {"type": value},
                    );
                    setState(() {
                      _assetType = value;
                      _assetClass = assetClassForType(value);
                      if (isEstateType(value) && _unitMixRows.isEmpty) {
                        _unitMixRows.add(_UnitMixControllers.empty());
                      }
                    });
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _ownershipType,
            decoration: const InputDecoration(labelText: "Ownership type"),
            items: ownershipTypeOptions
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
                    _logFlow(
                      "OWNERSHIP_CHANGE",
                      "Ownership type changed",
                      extra: {"ownershipType": value},
                    );
                    setState(() => _ownershipType = value);
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _assetClass,
            decoration: const InputDecoration(labelText: "Asset class"),
            items: assetClassOptions
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
                    _logFlow(
                      "CLASS_CHANGE",
                      "Asset class changed",
                      extra: {"assetClass": value},
                    );
                    setState(() => _assetClass = value);
                  },
          ),
          const SizedBox(height: 6),
          Text(
            "Tip: We suggest '${assetClassForType(_assetType)}' for this type.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: "Status"),
            items: _statusOptions
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
                    _logFlow(
                      "STATUS_CHANGE",
                      "Status changed",
                      extra: {"status": value},
                    );
                    setState(() => _status = value);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _serialCtrl,
            decoration: const InputDecoration(labelText: "Serial number"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(labelText: "Location"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "Description"),
          ),
          const SizedBox(height: 16),
          if (requiresPurchaseFields(_assetClass, _ownershipType)) ...[
            Text(
              "Fixed asset details",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _purchaseCostCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Purchase cost (NGN)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purchaseDateCtrl,
              decoration: const InputDecoration(
                labelText: "Purchase date (YYYY-MM-DD)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usefulLifeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Useful life (months)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salvageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Salvage value (optional)",
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (requiresLeaseFields(_ownershipType)) ...[
            Text(
              "Lease details",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _leaseStartCtrl,
              decoration: const InputDecoration(
                labelText: "Lease start (YYYY-MM-DD)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _leaseEndCtrl,
              decoration: const InputDecoration(labelText: "Lease end (YYYY-MM-DD)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _leaseCostCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Lease cost amount"),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _leasePeriod,
              decoration: const InputDecoration(labelText: "Lease cost period"),
              items: feePeriodOptions
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
                      _logFlow(
                        "LEASE_PERIOD_CHANGE",
                        "Lease period changed",
                        extra: {"period": value},
                      );
                      setState(() => _leasePeriod = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lessorCtrl,
              decoration: const InputDecoration(labelText: "Lessor name (optional)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _leaseTermsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: "Lease terms (optional)"),
            ),
            const SizedBox(height: 16),
          ],
          if (requiresManagementFields(_ownershipType)) ...[
            Text(
              "Management fees",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _managementFeeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Management fee amount"),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _managementPeriod,
              decoration: const InputDecoration(labelText: "Fee period"),
              items: feePeriodOptions
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
                      _logFlow(
                        "FEE_PERIOD_CHANGE",
                        "Management fee period changed",
                        extra: {"period": value},
                      );
                      setState(() => _managementPeriod = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientNameCtrl,
              decoration: const InputDecoration(labelText: "Client name (optional)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serviceTermsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: "Service terms (optional)"),
            ),
            const SizedBox(height: 16),
          ],
          if (isInventoryType(_assetType)) ...[
            Text(
              "Inventory snapshot",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inventoryQtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Quantity"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inventoryUnitCostCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Unit cost"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inventoryReorderCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Reorder level (optional)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inventoryUnitCtrl,
              decoration: const InputDecoration(labelText: "Unit of measure (optional)"),
            ),
            const SizedBox(height: 16),
          ],
          if (isEstateType(_assetType)) ...[
            Row(
              children: [
                Text(
                  "Estate details",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    // WHY: Quick jump to tenant review for this estate asset.
                    _logFlow(
                      "TENANT_LIST_OPEN",
                      "Open tenant applications",
                      extra: {"assetId": widget.asset.id},
                    );
                    context.go(
                      '/business-tenants?estateAssetId=${widget.asset.id}',
                    );
                  },
                  icon: const Icon(Icons.people_outline),
                  label: const Text("Tenants"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _estateHouseCtrl,
              decoration: const InputDecoration(labelText: "House number"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estateStreetCtrl,
              decoration: const InputDecoration(labelText: "Street"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estateCityCtrl,
              decoration: const InputDecoration(labelText: "City"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estateStateCtrl,
              decoration: const InputDecoration(labelText: "State"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estatePostalCtrl,
              decoration: const InputDecoration(labelText: "Postal code (optional)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estateLgaCtrl,
              decoration: const InputDecoration(labelText: "LGA (optional)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estateLandmarkCtrl,
              decoration: const InputDecoration(labelText: "Landmark (optional)"),
            ),
            const SizedBox(height: 16),
            Text(
              "Unit mix",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ..._unitMixRows.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
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
                            onPressed: _unitMixRows.length == 1
                                ? null
                                : () {
                                    _logFlow(
                                      "UNIT_MIX_REMOVE",
                                      "Remove unit mix row",
                                      extra: {"index": index},
                                    );
                                    setState(() {
                                      _unitMixRows.removeAt(index);
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
                              decoration: const InputDecoration(labelText: "Units"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: row.rentAmountCtrl,
                              keyboardType: TextInputType.number,
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
                        decoration: const InputDecoration(labelText: "Rent period"),
                        items: rentPeriodOptions
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
                                _logFlow(
                                  "UNIT_MIX_PERIOD_CHANGE",
                                  "Unit rent period changed",
                                  extra: {"period": value},
                                );
                                setState(() => row.rentPeriod = value);
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
                onPressed: _isSaving
                    ? null
                    : () {
                        _logFlow("UNIT_MIX_ADD", "Add unit mix row");
                        setState(() {
                          _unitMixRows.add(_UnitMixControllers.empty());
                        });
                      },
                icon: const Icon(Icons.add),
                label: const Text("Add unit"),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Tenant rules",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _referencesMinCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Min references"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _referencesMaxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Max references"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _guarantorsMinCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Min guarantors"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _guarantorsMaxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Max guarantors"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Tenants must be NIN verified and sign agreements before payment.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 20),
          Text(
            "Audit info",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _ReadOnlyRow(label: "Created", value: _formatDate(widget.asset.createdAt)),
          const SizedBox(height: 8),
          _ReadOnlyRow(label: "Updated", value: _formatDate(widget.asset.updatedAt)),
          const SizedBox(height: 8),
          _ReadOnlyRow(
            label: "Updated by",
            value: widget.asset.updatedBy ?? "System",
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: Text(_isSaving ? "Saving..." : "Save changes"),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return "Not available";
    final date = value.toIso8601String().split('T').first;
    return date;
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
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
      rentAmountCtrl: TextEditingController(text: unit.rentAmount.toString()),
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

  // WHY: Dispose controllers once the screen closes.
  void dispose() {
    unitTypeCtrl.dispose();
    countCtrl.dispose();
    rentAmountCtrl.dispose();
  }
}
