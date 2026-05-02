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
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_asset_helpers.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';

import 'package:frontend/app/features/home/presentation/business_tenant_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/features/home/presentation/role_access.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessAssetDetailScreen extends ConsumerStatefulWidget {
  final BusinessAsset? asset;
  final bool isCreateMode;
  final String screenTitle;
  final String initialAssetType;
  final String initialOwnershipType;

  const BusinessAssetDetailScreen({super.key, required this.asset})
    : assert(asset != null),
      isCreateMode = false,
      screenTitle = "Asset details",
      initialAssetType = "equipment",
      initialOwnershipType = "owned";

  const BusinessAssetDetailScreen.createEstate({super.key})
    : asset = null,
      isCreateMode = true,
      screenTitle = "Add estate asset",
      initialAssetType = "estate",
      initialOwnershipType = "rented_out";

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
  BusinessAsset? _assetSnapshot;
  final List<_UnitMixControllers> _unitMixRows = [];

  static const List<Map<String, String>> _statusOptions = [
    {"value": "active", "label": "Active"},
    {"value": "maintenance", "label": "Maintenance"},
    {"value": "inactive", "label": "Inactive"},
  ];

  void _logFlow(String step, String message, {Map<String, dynamic>? extra}) {
    AppDebug.log("BUSINESS_ASSET_DETAIL", "$step | $message", extra: extra);
  }

  @override
  void initState() {
    super.initState();
    _assetSnapshot = widget.asset;
    if (_assetSnapshot != null) {
      _applyAsset(_assetSnapshot!);
    } else {
      _applyCreateDefaults();
    }
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
    _inventoryReorderCtrl.text = asset.inventory?.reorderLevel.toString() ?? '';
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

  void _applyCreateDefaults() {
    _nameCtrl.clear();
    _descriptionCtrl.clear();
    _serialCtrl.clear();
    _locationCtrl.clear();
    _purchaseCostCtrl.clear();
    _purchaseDateCtrl.clear();
    _usefulLifeCtrl.clear();
    _salvageCtrl.clear();
    _leaseStartCtrl.clear();
    _leaseEndCtrl.clear();
    _leaseCostCtrl.clear();
    _lessorCtrl.clear();
    _leaseTermsCtrl.clear();
    _managementFeeCtrl.clear();
    _clientNameCtrl.clear();
    _serviceTermsCtrl.clear();
    _inventoryQtyCtrl.clear();
    _inventoryUnitCostCtrl.clear();
    _inventoryReorderCtrl.clear();
    _inventoryUnitCtrl.clear();
    _estateHouseCtrl.clear();
    _estateStreetCtrl.clear();
    _estateCityCtrl.clear();
    _estateStateCtrl.clear();
    _estatePostalCtrl.clear();
    _estateLgaCtrl.clear();
    _estateLandmarkCtrl.clear();
    _referencesMinCtrl.text = '1';
    _referencesMaxCtrl.text = '2';
    _guarantorsMinCtrl.text = '1';
    _guarantorsMaxCtrl.text = '2';

    _assetType = widget.initialAssetType;
    _ownershipType = widget.initialOwnershipType;
    _assetClass = assetClassForType(widget.initialAssetType);
    _status = 'active';
    _leasePeriod = 'monthly';
    _managementPeriod = 'monthly';

    _unitMixRows
      ..clear()
      ..add(_UnitMixControllers.empty());
  }

  /// ------------------------------------------------------------
  /// INPUT PARSERS
  /// ------------------------------------------------------------
  /// WHY:
  /// - Keep numeric + date parsing safe and consistent.
  double? _parseDoubleInput(String value) {
    // WHY: Accept formatted NGN values (commas/prefixes) for money fields.
    return parseNgnInput(value);
  }

  int? _parseIntInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  DateTime? _parseDateInput(String value) {
    // WHY: Centralize date parsing for form inputs.
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

  BusinessAsset? get _currentAsset => _assetSnapshot ?? widget.asset;

  bool _isFarmAsset(BusinessAsset? asset) {
    return asset?.domainContext == 'farm';
  }

  bool _canApproveFarmRequests({
    required String actorRole,
    required String? staffRole,
  }) {
    if (canUseBusinessOwnerEquivalentAccess(
      role: actorRole,
      staffRole: staffRole,
    )) {
      return true;
    }

    return actorRole == 'staff' &&
        (staffRole == staffRoleEstateManager ||
            staffRole == staffRoleFarmManager ||
            staffRole == staffRoleAssetManager);
  }

  void _replaceAssetSnapshot(BusinessAsset asset) {
    _assetSnapshot = asset;
    _applyAsset(asset);
  }

  Future<void> _refreshAssetRelatedProviders() async {
    ref.invalidate(businessAssetsProvider);
    ref.invalidate(businessAssetSummaryProvider);
    ref.invalidate(businessFarmAssetAuditProvider);
  }

  String _formatActor(BusinessAssetActorSnapshot? actor) {
    if (actor == null) {
      return "Unknown staff";
    }

    final name = actor.name.trim().isEmpty
        ? "Unknown staff"
        : actor.name.trim();
    final role = actor.staffRole?.trim().isNotEmpty == true
        ? formatStaffRoleLabel(actor.staffRole!, fallback: actor.actorRole)
        : actor.actorRole.trim().isNotEmpty
        ? actor.actorRole
        : '';
    if (role.trim().isEmpty) {
      return name;
    }
    return "$name (${role.replaceAll('_', ' ')})";
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return "Not available";
    }
    final dateLabel = formatDateLabel(value, fallback: "");
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return "$dateLabel $hour:$minute";
  }

  String _formatUsageWindow(BusinessAssetProductionUsageRequest request) {
    final dateLabel = formatDateLabel(
      request.productionDate,
      fallback: "No date",
    );
    final start = request.usageStartTime.trim();
    final end = request.usageEndTime.trim();
    if (start.isEmpty && end.isEmpty) {
      return dateLabel;
    }
    if (end.isEmpty) {
      return "$dateLabel • $start";
    }
    return "$dateLabel • $start - $end";
  }

  Future<void> _pickTime(
    TextEditingController controller, {
    required String field,
  }) async {
    _logFlow("TIME_PICK_OPEN", "Time picker opened", extra: {"field": field});

    TimeOfDay initial = TimeOfDay.now();
    final raw = controller.text.trim();
    if (raw.contains(':')) {
      final parts = raw.split(':');
      final hour = int.tryParse(parts.first);
      final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (hour != null && minute != null) {
        initial = TimeOfDay(hour: hour, minute: minute);
      }
    }

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (!mounted || picked == null) {
      return;
    }

    controller.text =
        "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
    _logFlow(
      "TIME_PICK_SELECTED",
      "Time selected",
      extra: {"field": field, "time": controller.text},
    );
  }

  Future<void> _pickDate(
    TextEditingController controller, {
    required String field,
  }) async {
    // WHY: Log user intent before opening the calendar picker.
    _logFlow("DATE_PICK_OPEN", "Date picker opened", extra: {"field": field});

    final initial = _parseDateInput(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // WHY: Keep the current value visible when reopening the picker.
      initialDate: initial,
      // WHY: Use shared picker range to keep date inputs consistent.
      firstDate: DateTime(kDatePickerFirstYear),
      lastDate: DateTime(kDatePickerLastYear),
    );

    if (!mounted) {
      // WHY: Avoid updating controllers after the screen is disposed.
      return;
    }

    if (picked == null) {
      // WHY: Log cancellations for easier support debugging.
      _logFlow(
        "DATE_PICK_CANCEL",
        "Date picker cancelled",
        extra: {"field": field},
      );
      return;
    }

    controller.text = _formatDateInput(picked);
    // WHY: Capture selected dates for troubleshooting asset updates.
    _logFlow(
      "DATE_PICK_SELECTED",
      "Date selected",
      extra: {"field": field, "date": controller.text},
    );
  }

  Future<void> _approveFarmRequest(
    BusinessAsset asset, {
    required String requestType,
    String? requestId,
  }) async {
    if (_isSaving) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = ref.read(businessAssetApiProvider);
      final updated = await api.approveFarmAssetRequest(
        token: session.token,
        id: asset.id,
        requestType: requestType,
        requestId: requestId,
      );
      await _refreshAssetRelatedProviders();
      if (!mounted) {
        return;
      }
      setState(() => _replaceAssetSnapshot(updated));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requestType == 'usage'
                ? "Tool usage approved successfully"
                : requestType == 'audit'
                ? "Audit approved successfully"
                : "Equipment approved successfully",
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requestType == 'usage'
                ? "Unable to approve tool usage"
                : requestType == 'audit'
                ? "Unable to approve audit request"
                : "Unable to approve equipment request",
          ),
        ),
      );
      _logFlow(
        "APPROVAL_FAIL",
        "Farm approval failed",
        extra: {
          "assetId": asset.id,
          "requestType": requestType,
          "requestId": requestId ?? '',
          "error": error.toString(),
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openFarmAuditSheet(BusinessAsset asset) async {
    if (_isSaving) {
      return;
    }

    final auditDateCtrl = TextEditingController(
      text: _formatDateInput(DateTime.now()),
    );
    final estimatedValueCtrl = TextEditingController(
      text: formatNgnInput(
        asset.farmProfile?.estimatedCurrentValue ?? asset.purchaseCost ?? 0,
      ),
    );
    final noteCtrl = TextEditingController(
      text: asset.farmProfile?.lastAuditNote ?? '',
    );
    var selectedStatus = asset.status;

    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Do an audit",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Record the latest audit result for ${asset.name}. Staff submissions route to manager approval automatically.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: auditDateCtrl,
                      readOnly: true,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      onTap: () =>
                          _pickDate(auditDateCtrl, field: "audit_date"),
                      decoration: const InputDecoration(
                        labelText: "Audit date",
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: "Resulting status",
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'active',
                          child: Text("Active"),
                        ),
                        DropdownMenuItem(
                          value: 'maintenance',
                          child: Text("Maintenance"),
                        ),
                        DropdownMenuItem(
                          value: 'inactive',
                          child: Text("Inactive"),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => selectedStatus = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: estimatedValueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [NgnInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: "Estimated current value (NGN)",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Audit note",
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final auditDate = _parseDateInput(
                                auditDateCtrl.text,
                              );
                              if (auditDate == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Audit date is required"),
                                  ),
                                );
                                return;
                              }

                              Navigator.of(context).pop({
                                "auditDate": auditDate.toIso8601String(),
                                "status": selectedStatus,
                                "estimatedCurrentValue":
                                    parseNgnInput(estimatedValueCtrl.text) ?? 0,
                                "note": noteCtrl.text.trim(),
                              });
                            },
                            child: const Text("Submit audit"),
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

    auditDateCtrl.dispose();
    estimatedValueCtrl.dispose();
    noteCtrl.dispose();

    if (payload == null) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = ref.read(businessAssetApiProvider);
      final updated = await api.submitFarmAssetAudit(
        token: session.token,
        id: asset.id,
        payload: payload,
      );
      await _refreshAssetRelatedProviders();
      if (!mounted) {
        return;
      }
      setState(() => _replaceAssetSnapshot(updated));
      final hasPendingRequest =
          updated.farmProfile?.pendingAuditRequest?.status ==
          'pending_approval';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasPendingRequest
                ? "Audit submitted for approval"
                : "Audit recorded successfully",
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to submit audit update")),
      );
      _logFlow(
        "AUDIT_SUBMIT_FAIL",
        "Farm audit submission failed",
        extra: {"assetId": asset.id, "error": error.toString()},
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openToolUsageSheet(BusinessAsset asset) async {
    if (_isSaving) {
      return;
    }

    final productionDateCtrl = TextEditingController(
      text: _formatDateInput(DateTime.now()),
    );
    final startTimeCtrl = TextEditingController(text: "08:00");
    final endTimeCtrl = TextEditingController(text: "12:00");
    final quantityAvailable =
        asset.farmProfile?.quantity ?? asset.inventory?.quantity ?? 1;
    final quantityRequestedCtrl = TextEditingController(text: "1");
    final quantityUsedCtrl = TextEditingController(text: "1");
    final activityCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Request tool usage",
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  "Track daily production usage for ${asset.name}. Farmers can submit requests and managers approve them.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Tracked quantity: $quantityAvailable ${(asset.farmProfile?.unitOfMeasure ?? 'units').trim()}",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: productionDateCtrl,
                  readOnly: true,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  onTap: () =>
                      _pickDate(productionDateCtrl, field: "production_date"),
                  decoration: const InputDecoration(
                    labelText: "Production date",
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startTimeCtrl,
                        readOnly: true,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        onTap: () =>
                            _pickTime(startTimeCtrl, field: "usage_start_time"),
                        decoration: const InputDecoration(
                          labelText: "Start time",
                          suffixIcon: Icon(Icons.access_time_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: endTimeCtrl,
                        readOnly: true,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        onTap: () =>
                            _pickTime(endTimeCtrl, field: "usage_end_time"),
                        decoration: const InputDecoration(
                          labelText: "End time",
                          suffixIcon: Icon(Icons.access_time_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: activityCtrl,
                  decoration: const InputDecoration(
                    labelText: "Production activity",
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: quantityRequestedCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Requested quantity",
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: quantityUsedCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Used quantity",
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: "Usage note"),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final productionDate = _parseDateInput(
                            productionDateCtrl.text,
                          );
                          final requestedQty = _parseIntInput(
                            quantityRequestedCtrl.text,
                          );
                          final usedQty = _parseIntInput(quantityUsedCtrl.text);
                          if (productionDate == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Production date is required"),
                              ),
                            );
                            return;
                          }
                          if (requestedQty == null || requestedQty <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Requested quantity is required"),
                              ),
                            );
                            return;
                          }
                          if (usedQty == null || usedQty <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Used quantity is required"),
                              ),
                            );
                            return;
                          }

                          Navigator.of(context).pop({
                            "productionDate": productionDate.toIso8601String(),
                            "usageStartTime": startTimeCtrl.text.trim(),
                            "usageEndTime": endTimeCtrl.text.trim(),
                            "productionActivity": activityCtrl.text.trim(),
                            "quantityRequested": requestedQty,
                            "quantityUsed": usedQty,
                            "note": noteCtrl.text.trim(),
                          });
                        },
                        child: const Text("Submit usage"),
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

    productionDateCtrl.dispose();
    startTimeCtrl.dispose();
    endTimeCtrl.dispose();
    quantityRequestedCtrl.dispose();
    quantityUsedCtrl.dispose();
    activityCtrl.dispose();
    noteCtrl.dispose();

    if (payload == null) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = ref.read(businessAssetApiProvider);
      final updated = await api.submitFarmToolUsageRequest(
        token: session.token,
        id: asset.id,
        payload: payload,
      );
      await _refreshAssetRelatedProviders();
      if (!mounted) {
        return;
      }
      setState(() => _replaceAssetSnapshot(updated));
      final latestUsage =
          updated.farmProfile?.productionUsageRequests.isNotEmpty == true
          ? updated.farmProfile!.productionUsageRequests.first
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            latestUsage?.status == 'pending_approval'
                ? "Tool usage submitted for approval"
                : "Tool usage logged successfully",
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to submit tool usage")),
      );
      _logFlow(
        "USAGE_SUBMIT_FAIL",
        "Tool usage submission failed",
        extra: {"assetId": asset.id, "error": error.toString()},
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) {
      _logFlow("SAVE_BLOCK", "Save ignored (already saving)");
      return;
    }

    _logFlow(
      "SAVE_TAP",
      widget.isCreateMode ? "Create tapped" : "Save tapped",
      extra: {"assetId": _currentAsset?.id ?? "new"},
    );

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Asset name is required")));
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
            content: Text("Purchase cost, date, and useful life are required."),
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
          const SnackBar(content: Text("Management fee amount is required.")),
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
          const SnackBar(content: Text("Estate address fields are required.")),
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
      "purchaseDate": _parseDateInput(
        _purchaseDateCtrl.text,
      )?.toIso8601String(),
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
      (key, value) =>
          value == null || (value is String && value.trim().isEmpty),
    );

    try {
      final api = ref.read(businessAssetApiProvider);
      BusinessAsset savedAsset;
      if (widget.isCreateMode) {
        _logFlow(
          "SAVE_REQUEST",
          "Creating estate asset",
          extra: {"assetType": _assetType},
        );
        savedAsset = await api.createAsset(
          token: session.token,
          payload: payload,
        );
      } else {
        final assetId = _currentAsset!.id;
        _logFlow("SAVE_REQUEST", "Updating asset", extra: {"assetId": assetId});
        savedAsset = await api.updateAsset(
          token: session.token,
          id: assetId,
          payload: payload,
        );
      }

      // WHY: Refresh list + summary so analytics stay in sync.
      await _refreshAssetRelatedProviders();

      if (!mounted) return;
      if (!widget.isCreateMode) {
        setState(() => _replaceAssetSnapshot(savedAsset));
      }
      _logFlow(
        "SAVE_OK",
        widget.isCreateMode ? "Asset created" : "Asset updated",
        extra: {"assetId": savedAsset.id},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isCreateMode
                ? "Estate asset created successfully"
                : "Asset updated successfully",
          ),
        ),
      );
      if (widget.isCreateMode) {
        context.go('/business-assets/${savedAsset.id}', extra: savedAsset);
      }
    } catch (e) {
      _logFlow(
        "SAVE_FAIL",
        widget.isCreateMode ? "Asset create failed" : "Asset update failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isCreateMode
                ? "Unable to create estate asset"
                : "Unable to update asset",
          ),
        ),
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
      extra: {"assetId": widget.asset?.id ?? "new"},
    );

    final theme = Theme.of(context);
    final currentAsset = _currentAsset;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final canApproveFarmRequests = _canApproveFarmRequests(
      actorRole: profile?.role ?? '',
      staffRole: profile?.staffRole,
    );
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
        title: Text(widget.screenTitle),
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
        actions: [
          if (!widget.isCreateMode)
            if (currentAsset != null && _isFarmAsset(currentAsset))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _openFarmAuditSheet(currentAsset),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text("Do audit"),
                ),
              ),
          if (!widget.isCreateMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () {
                  _logFlow("FARM_AUDIT_OPEN", "Open farm audit register");
                  context.push('/business-assets/farm-audit');
                },
                icon: const Icon(Icons.agriculture_outlined),
                label: const Text("Farm audit"),
              ),
            ),
        ],
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
                    currentAsset?.name ?? "New estate asset",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
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
          if (!widget.isCreateMode &&
              currentAsset != null &&
              isEstateType(_assetType)) ...[
            const SizedBox(height: 12),
            _EstateAnalyticsStrip(
              assetId: currentAsset.id,
              onViewTenants: () {
                _logFlow(
                  "TENANT_LIST_OPEN",
                  "Open tenant applications from analytics strip",
                  extra: {"assetId": currentAsset.id},
                );
                context.go(
                  '/business-tenants?estateAssetId=${currentAsset.id}',
                );
              },
            ),
          ],
          if (!widget.isCreateMode &&
              currentAsset != null &&
              _isFarmAsset(currentAsset)) ...[
            const SizedBox(height: 12),
            _buildFarmOperationsCard(
              theme,
              currentAsset,
              canApproveFarmRequests: canApproveFarmRequests,
            ),
          ],
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
            onChanged: _isSaving || widget.isCreateMode
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // WHY: Auto-format money inputs with commas/decimals.
              inputFormatters: const [NgnInputFormatter()],
              decoration: const InputDecoration(
                labelText: "Purchase cost (NGN)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purchaseDateCtrl,
              readOnly: true,
              // WHY: Block manual typing so dates stay picker-driven.
              enableInteractiveSelection: false,
              showCursor: false,
              // WHY: Use the calendar picker to prevent manual date errors.
              onTap: () => _pickDate(_purchaseDateCtrl, field: "purchase_date"),
              decoration: const InputDecoration(
                labelText: "Purchase date (YYYY-MM-DD)",
                suffixIcon: Icon(Icons.calendar_today_outlined),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // WHY: Auto-format money inputs with commas/decimals.
              inputFormatters: const [NgnInputFormatter()],
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
              readOnly: true,
              // WHY: Block manual typing so dates stay picker-driven.
              enableInteractiveSelection: false,
              showCursor: false,
              // WHY: Keep lease dates aligned with the picker UI.
              onTap: () => _pickDate(_leaseStartCtrl, field: "lease_start"),
              decoration: const InputDecoration(
                labelText: "Lease start (YYYY-MM-DD)",
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _leaseEndCtrl,
              readOnly: true,
              // WHY: Block manual typing so dates stay picker-driven.
              enableInteractiveSelection: false,
              showCursor: false,
              // WHY: Avoid manual typing for lease end dates.
              onTap: () => _pickDate(_leaseEndCtrl, field: "lease_end"),
              decoration: const InputDecoration(
                labelText: "Lease end (YYYY-MM-DD)",
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _leaseCostCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // WHY: Auto-format money inputs with commas/decimals.
              inputFormatters: const [NgnInputFormatter()],
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
              decoration: const InputDecoration(
                labelText: "Lessor name (optional)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _leaseTermsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Lease terms (optional)",
              ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // WHY: Auto-format money inputs with commas/decimals.
              inputFormatters: const [NgnInputFormatter()],
              decoration: const InputDecoration(
                labelText: "Management fee amount",
              ),
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
              decoration: const InputDecoration(
                labelText: "Client name (optional)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serviceTermsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Service terms (optional)",
              ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // WHY: Auto-format money inputs with commas/decimals.
              inputFormatters: const [NgnInputFormatter()],
              decoration: const InputDecoration(labelText: "Unit cost"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inventoryReorderCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Reorder level (optional)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inventoryUnitCtrl,
              decoration: const InputDecoration(
                labelText: "Unit of measure (optional)",
              ),
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
                if (!widget.isCreateMode && currentAsset != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      // WHY: Quick jump to tenant review for this estate asset.
                      _logFlow(
                        "TENANT_LIST_OPEN",
                        "Open tenant applications",
                        extra: {"assetId": currentAsset.id},
                      );
                      context.go(
                        '/business-tenants?estateAssetId=${currentAsset.id}',
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
              decoration: const InputDecoration(
                labelText: "Postal code (optional)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estateLgaCtrl,
              decoration: const InputDecoration(labelText: "LGA (optional)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estateLandmarkCtrl,
              decoration: const InputDecoration(
                labelText: "Landmark (optional)",
              ),
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
                              inputFormatters: const [NgnInputFormatter()],
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
                    decoration: const InputDecoration(
                      labelText: "Min references",
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _referencesMaxCtrl,
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
                    controller: _guarantorsMinCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Min guarantors",
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _guarantorsMaxCtrl,
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!widget.isCreateMode && currentAsset != null) ...[
            const SizedBox(height: 20),
            Text(
              "Audit info",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _ReadOnlyRow(
              label: "Created",
              value: _formatDate(currentAsset.createdAt),
            ),
            const SizedBox(height: 8),
            _ReadOnlyRow(
              label: "Updated",
              value: _formatDate(currentAsset.updatedAt),
            ),
            const SizedBox(height: 8),
            _ReadOnlyRow(
              label: "Updated by",
              value: currentAsset.updatedBy ?? "System",
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: Text(
                _isSaving
                    ? (widget.isCreateMode ? "Creating..." : "Saving...")
                    : (widget.isCreateMode
                          ? "Create estate asset"
                          : "Save changes"),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFarmOperationsCard(
    ThemeData theme,
    BusinessAsset asset, {
    required bool canApproveFarmRequests,
  }) {
    final usageRequests = [...?asset.farmProfile?.productionUsageRequests]
      ..sort(
        (left, right) => (right.requestedAt ?? DateTime(1900)).compareTo(
          left.requestedAt ?? DateTime(1900),
        ),
      );
    final pendingUsageRequests = usageRequests
        .where((request) => request.status == 'pending_approval')
        .toList();
    final approvedUsageRequests = usageRequests
        .where((request) => request.status == 'approved')
        .toList();
    final pendingAudit = asset.farmProfile?.pendingAuditRequest;
    final pendingAssetApproval = asset.approvalStatus == 'pending_approval';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Farm operations",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                asset.farmProfile?.farmSection ??
                    asset.location ??
                    "Farm equipment",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Submit audits, track daily production usage, and approve farm requests from this asset.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _isSaving || pendingAssetApproval
                    ? null
                    : () => _openFarmAuditSheet(asset),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text("Do audit"),
              ),
              OutlinedButton.icon(
                onPressed: _isSaving || pendingAssetApproval
                    ? null
                    : () => _openToolUsageSheet(asset),
                icon: const Icon(Icons.build_circle_outlined),
                label: const Text("Request tool usage"),
              ),
              if (canApproveFarmRequests && pendingAssetApproval)
                OutlinedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _approveFarmRequest(asset, requestType: 'asset'),
                  icon: const Icon(Icons.approval_outlined),
                  label: const Text("Approve equipment"),
                ),
              if (canApproveFarmRequests &&
                  pendingAudit?.status == 'pending_approval')
                OutlinedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _approveFarmRequest(asset, requestType: 'audit'),
                  icon: const Icon(Icons.task_alt_outlined),
                  label: const Text("Approve audit"),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FarmInfoChip(
                label: "Usage logs",
                value: usageRequests.length.toString(),
              ),
              _FarmInfoChip(
                label: "Pending usage",
                value: pendingUsageRequests.length.toString(),
              ),
              _FarmInfoChip(
                label: "Approved usage",
                value: approvedUsageRequests.length.toString(),
              ),
            ],
          ),
          if (pendingAssetApproval) ...[
            const SizedBox(height: 12),
            _FarmNotice(
              title: "Equipment approval pending",
              body:
                  "Submitted by ${_formatActor(asset.approvalRequestedBy)} on ${_formatDateTime(asset.approvalRequestedAt)}.",
              tone: Colors.orange,
            ),
          ],
          if (pendingAudit?.status == 'pending_approval') ...[
            const SizedBox(height: 12),
            _FarmNotice(
              title: "Audit approval pending",
              body:
                  "${_formatActor(pendingAudit?.requestedBy)} requested ${pendingAudit?.resultingStatus ?? asset.status} on ${_formatDateTime(pendingAudit?.auditDate)}.",
              tone: Colors.blue,
            ),
          ],
          if (usageRequests.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              "Daily production usage",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...usageRequests
                .take(6)
                .map(
                  (request) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildUsageRequestTile(
                      theme,
                      asset,
                      request,
                      canApproveFarmRequests: canApproveFarmRequests,
                    ),
                  ),
                ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              "No daily production usage logged yet.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUsageRequestTile(
    ThemeData theme,
    BusinessAsset asset,
    BusinessAssetProductionUsageRequest request, {
    required bool canApproveFarmRequests,
  }) {
    final isPending = request.status == 'pending_approval';
    final statusTone = isPending
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.primaryContainer;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  request.productionActivity.trim().isEmpty
                      ? "Production usage request"
                      : request.productionActivity,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusTone,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  request.status.replaceAll('_', ' ').toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatUsageWindow(request),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Requested by ${_formatActor(request.requestedBy)} • requested ${request.quantityRequested} • used ${request.quantityUsed}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (request.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              request.note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (request.approvedBy != null || request.approvedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              "Approved by ${_formatActor(request.approvedBy)} on ${_formatDateTime(request.approvedAt)}",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (isPending && canApproveFarmRequests) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _approveFarmRequest(
                        asset,
                        requestType: 'usage',
                        requestId: request.id,
                      ),
                icon: const Icon(Icons.approval_outlined),
                label: const Text("Approve usage"),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    // WHY: Use the shared date helper for consistent audit labels.
    return formatDateLabel(value, fallback: "Not available");
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

class _FarmInfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _FarmInfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmNotice extends StatelessWidget {
  final String title;
  final String body;
  final Color tone;

  const _FarmNotice({
    required this.title,
    required this.body,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// Estate analytics strip (owner/staff)
/// ------------------------------------------------------------
/// WHAT:
/// - Shows quick KPIs for the current estate asset.
///
/// WHY:
/// - Keeps the asset detail page aligned with the scoped tenant
///   applications view so owners/staff don’t need to hop screens
///   to see rent health.
///
/// HOW:
/// - Uses estateAnalyticsProvider with the assetId.
/// - Surfaces totals, collections, and a shortcut to the tenant list.
class _EstateAnalyticsStrip extends ConsumerWidget {
  final String assetId;
  final VoidCallback onViewTenants;

  const _EstateAnalyticsStrip({
    required this.assetId,
    required this.onViewTenants,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final analyticsAsync = ref.watch(estateAnalyticsProvider(assetId));

    return analyticsAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              "Loading estate analytics...",
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Analytics unavailable. Open Tenants and pull to refresh.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      data: (analytics) {
        final chips = <Widget>[
          _kpiChip(
            context,
            label: "Active",
            value: analytics.tenants.active.toString(),
            tone: AppStatusTone.success,
          ),
          _kpiChip(
            context,
            label: "Pending",
            value: analytics.tenants.pending.toString(),
            tone: AppStatusTone.warning,
          ),
          _kpiChip(
            context,
            label: "Due soon",
            value: analytics.tenants.dueSoon.toString(),
            tone: AppStatusTone.info,
          ),
          _kpiChip(
            context,
            label: "Overdue",
            value: analytics.tenants.overdue.toString(),
            tone: AppStatusTone.danger,
          ),
          _moneyChip(
            context,
            label: "Collected (month)",
            kobo: analytics.collections.monthKobo,
          ),
          _moneyChip(
            context,
            label: "Collected (YTD)",
            kobo: analytics.collections.ytdKobo,
          ),
          _moneyChip(
            context,
            label: "Potential annual",
            kobo: analytics.estate.potentialAnnualKobo,
          ),
        ];

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "Estate KPIs",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    analytics.estate.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onViewTenants,
                    icon: const Icon(Icons.people_outline),
                    label: const Text("View tenants"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: chips),
            ],
          ),
        );
      },
    );
  }

  Widget _kpiChip(
    BuildContext context, {
    required String label,
    required String value,
    required AppStatusTone tone,
  }) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyChip(
    BuildContext context, {
    required String label,
    required int kobo,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            formatNgnFromCents(kobo),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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

  // WHY: Dispose controllers once the screen closes.
  void dispose() {
    unitTypeCtrl.dispose();
    countCtrl.dispose();
    rentAmountCtrl.dispose();
  }
}
