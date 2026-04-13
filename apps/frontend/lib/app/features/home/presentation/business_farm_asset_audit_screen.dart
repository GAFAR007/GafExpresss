/// lib/app/features/home/presentation/business_farm_asset_audit_screen.dart
/// -----------------------------------------------------------------------
/// WHAT:
/// - Farm equipment/tool register with audit-focused analytics.
///
/// WHY:
/// - Lets teams store machinery, tools, and other farm equipment with
///   categories, audit cadence, and value tracking in one place.
///
/// HOW:
/// - Reads equipment records from the shared business assets API.
/// - Uses a dedicated farm audit analytics endpoint for chart summaries.
/// - Provides an inline add flow for new tools and machinery.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/business_asset_api.dart';
import 'package:frontend/app/features/home/presentation/business_asset_helpers.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_profile_action.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/features/home/presentation/role_access.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';

const List<String> _farmCategoryOptions = [
  'tools',
  'machinery',
  'irrigation',
  'storage',
  'processing',
  'transport',
  'safety',
  'utilities',
  'other',
];

const List<String> _farmCadenceOptions = ['all', 'quarterly', 'yearly'];

class BusinessFarmAssetAuditScreen extends ConsumerStatefulWidget {
  const BusinessFarmAssetAuditScreen({super.key});

  @override
  ConsumerState<BusinessFarmAssetAuditScreen> createState() =>
      _BusinessFarmAssetAuditScreenState();
}

class _BusinessFarmAssetAuditScreenState
    extends ConsumerState<BusinessFarmAssetAuditScreen> {
  String? _selectedCategory;
  String _selectedCadence = 'all';
  bool _isSaving = false;
  String? _approvalPromptSignature;

  BusinessAssetsQuery get _assetsQuery => BusinessAssetsQuery(
    page: 1,
    limit: 80,
    domainContext: 'farm',
    farmCategory: _selectedCategory,
    auditFrequency: _selectedCadence == 'all' ? null : _selectedCadence,
  );

  FarmAssetAuditQuery get _analyticsQuery => FarmAssetAuditQuery(
    farmCategory: _selectedCategory,
    auditFrequency: _selectedCadence == 'all' ? null : _selectedCadence,
    year: DateTime.now().year,
  );

  void _logTap(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      "BUSINESS_FARM_AUDIT",
      "Tap",
      extra: {"action": action, ...?extra},
    );
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
        (staffRole == staffRoleFarmManager ||
            staffRole == staffRoleAssetManager ||
            staffRole == staffRoleEstateManager);
  }

  void _maybeShowApprovalPrompt({
    required bool canApprove,
    required List<BusinessAsset> pendingAssets,
    required List<BusinessAsset> pendingAuditAssets,
  }) {
    if (!mounted || !canApprove) {
      _approvalPromptSignature = null;
      return;
    }

    final totalRequests = pendingAssets.length + pendingAuditAssets.length;
    if (totalRequests == 0) {
      _approvalPromptSignature = null;
      return;
    }

    final nextSignature = [
      pendingAssets.map((asset) => asset.id).join(','),
      pendingAuditAssets.map((asset) => asset.id).join(','),
    ].join('|');

    if (_approvalPromptSignature == nextSignature) {
      return;
    }

    _approvalPromptSignature = nextSignature;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final previewLines = <String>[
        ...pendingAssets
            .take(2)
            .map(
              (asset) =>
                  "Equipment: ${asset.name} by ${_actorLabel(asset.approvalRequestedBy)}",
            ),
        ...pendingAuditAssets
            .take(2)
            .map(
              (asset) =>
                  "Audit: ${asset.name} by ${_actorLabel(asset.farmProfile?.pendingAuditRequest?.requestedBy)}",
            ),
      ];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Approval required"),
            content: Text(
              [
                [
                  if (pendingAssets.isNotEmpty)
                    "${pendingAssets.length} equipment submission${pendingAssets.length == 1 ? '' : 's'} waiting",
                  if (pendingAuditAssets.isNotEmpty)
                    "${pendingAuditAssets.length} audit request${pendingAuditAssets.length == 1 ? '' : 's'} waiting",
                ].join(" and "),
                if (previewLines.isNotEmpty) ...["", ...previewLines],
              ].join("\n"),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text("Review"),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _refreshAll() async {
    _logTap("refresh");
    await Future.wait([
      _refreshFarmAuditQueries(),
      AppRefresh.refreshApp(ref: ref, source: "business_farm_asset_audit"),
    ]);
  }

  Future<void> _pickDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final initial = parseDateInput(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(kDatePickerFirstYear),
      lastDate: DateTime(kDatePickerLastYear),
    );
    if (picked == null) {
      return;
    }
    controller.text = formatDateInput(picked);
  }

  Future<void> _refreshFarmAuditQueries() async {
    ref.invalidate(businessAssetSummaryProvider);

    try {
      await Future.wait([
        ref.refresh(businessAssetsProvider(_assetsQuery).future),
        ref.refresh(businessFarmAssetAuditProvider(_analyticsQuery).future),
      ]);
    } catch (error) {
      AppDebug.log(
        "BUSINESS_FARM_AUDIT",
        "refresh_queries_failed",
        extra: {"error": error.toString()},
      );
      ref.invalidate(businessAssetsProvider(_assetsQuery));
      ref.invalidate(businessFarmAssetAuditProvider(_analyticsQuery));
    }
  }

  Future<void> _approveRequest(
    BusinessAsset asset, {
    required String requestType,
  }) async {
    if (_isSaving) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = ref.read(businessAssetApiProvider);
      await api.approveFarmAssetRequest(
        token: session.token,
        id: asset.id,
        requestType: requestType,
      );
      await _refreshFarmAuditQueries();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requestType == 'audit'
                ? "Audit request approved"
                : "Equipment request approved",
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requestType == 'audit'
                ? "Unable to approve audit request"
                : "Unable to approve equipment request",
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openAuditRequestSheet(BusinessAsset asset) async {
    if (_isSaving) {
      return;
    }

    final auditDateCtrl = TextEditingController(
      text: formatDateInput(DateTime.now()),
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
                      "Submit audit update",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      "Record the latest audit state for ${asset.name}. Managers can approve pending submissions.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: auditDateCtrl,
                      readOnly: true,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      onTap: () => _pickDate(context, auditDateCtrl),
                      decoration: const InputDecoration(
                        labelText: "Audit date",
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedStatus = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Audit note",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final auditDate = parseDateInput(
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
      if (!mounted) {
        return;
      }
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
      await _refreshFarmAuditQueries();
      if (!mounted) {
        return;
      }
      final hasPendingRequest =
          updated.farmProfile?.pendingAuditRequest?.status ==
          'pending_approval';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasPendingRequest
                ? "Audit submitted for manager approval"
                : "Audit recorded successfully",
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to submit audit update")),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openAddAssetSheet() async {
    if (_isSaving) {
      return;
    }

    final nameCtrl = TextEditingController();
    final farmLabelCtrl = TextEditingController();
    final farmSectionCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final quantityCtrl = TextEditingController(text: '1');
    final unitCtrl = TextEditingController(text: 'units');
    final purchaseCostCtrl = TextEditingController();
    final purchaseDateCtrl = TextEditingController(
      text: formatDateInput(DateTime.now()),
    );
    final usefulLifeCtrl = TextEditingController(text: '36');
    final estimatedValueCtrl = TextEditingController();
    final lastAuditDateCtrl = TextEditingController(
      text: formatDateInput(DateTime.now()),
    );

    var selectedAssetType = 'equipment';
    var selectedCategory = 'tools';
    var selectedCadence = 'quarterly';
    var selectedStatus = 'active';

    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final assetClass = assetClassForType(selectedAssetType);
            final requiresPurchase = requiresPurchaseFields(
              assetClass,
              'owned',
            );

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
                      "Add farm equipment",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      "Register tools, machinery, and supporting farm equipment. Staff submissions can wait for manager approval before they become official.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Asset name",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: selectedAssetType,
                      decoration: const InputDecoration(
                        labelText: "Asset type",
                      ),
                      items: assetTypeOptions
                          .where((option) => option["value"] != "estate")
                          .map(
                            (option) => DropdownMenuItem(
                              value: option["value"],
                              child: Text(option["label"] ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedAssetType = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: "Farm category",
                      ),
                      items: _farmCategoryOptions
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(_prettyLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedCategory = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: farmLabelCtrl,
                      decoration: const InputDecoration(
                        labelText: "Farm label / site",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: farmSectionCtrl,
                      decoration: const InputDecoration(
                        labelText: "Section / block",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: quantityCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Quantity",
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            controller: unitCtrl,
                            decoration: const InputDecoration(
                              labelText: "Unit of measure",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCadence,
                      decoration: const InputDecoration(
                        labelText: "Audit cadence",
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'quarterly',
                          child: Text("Quarterly"),
                        ),
                        DropdownMenuItem(
                          value: 'yearly',
                          child: Text("Yearly"),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedCadence = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(labelText: "Status"),
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
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedStatus = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: lastAuditDateCtrl,
                      readOnly: true,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      onTap: () => _pickDate(context, lastAuditDateCtrl),
                      decoration: const InputDecoration(
                        labelText: "Last audit date",
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (requiresPurchase) ...[
                      TextField(
                        controller: purchaseCostCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [NgnInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: "Purchase cost (NGN)",
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: purchaseDateCtrl,
                        readOnly: true,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        onTap: () => _pickDate(context, purchaseDateCtrl),
                        decoration: const InputDecoration(
                          labelText: "Purchase date",
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: usefulLifeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Useful life (months)",
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    TextField(
                      controller: estimatedValueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [NgnInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: "Estimated current value (optional)",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: serialCtrl,
                      decoration: const InputDecoration(
                        labelText: "Serial / reference number",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(labelText: "Location"),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: descriptionCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Description",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final trimmedName = nameCtrl.text.trim();
                              final quantity = int.tryParse(
                                quantityCtrl.text.trim(),
                              );
                              final lastAuditDate = parseDateInput(
                                lastAuditDateCtrl.text,
                              );
                              final purchaseCost = parseNgnInput(
                                purchaseCostCtrl.text,
                              );
                              final purchaseDate = parseDateInput(
                                purchaseDateCtrl.text,
                              );
                              final usefulLife = int.tryParse(
                                usefulLifeCtrl.text.trim(),
                              );

                              if (trimmedName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Asset name is required"),
                                  ),
                                );
                                return;
                              }
                              if (quantity == null || quantity < 1) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Quantity must be at least 1",
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (lastAuditDate == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Last audit date is required",
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (requiresPurchase &&
                                  (purchaseCost == null ||
                                      purchaseDate == null ||
                                      usefulLife == null ||
                                      usefulLife < 1)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Purchase cost, purchase date, and useful life are required.",
                                    ),
                                  ),
                                );
                                return;
                              }

                              Navigator.of(context).pop({
                                "name": trimmedName,
                                "assetType": selectedAssetType,
                                "ownershipType": "owned",
                                "assetClass": assetClass,
                                "status": selectedStatus,
                                "serialNumber": serialCtrl.text.trim(),
                                "location": locationCtrl.text.trim(),
                                "description": descriptionCtrl.text.trim(),
                                "purchaseCost": purchaseCost,
                                "purchaseDate": purchaseDate?.toIso8601String(),
                                "usefulLifeMonths": usefulLife,
                                "domainContext": "farm",
                                "farmProfile": {
                                  "attachedFarmLabel": farmLabelCtrl.text
                                      .trim(),
                                  "farmSection": farmSectionCtrl.text.trim(),
                                  "farmCategory": selectedCategory,
                                  "auditFrequency": selectedCadence,
                                  "lastAuditDate": lastAuditDate
                                      .toIso8601String(),
                                  "quantity": quantity,
                                  "unitOfMeasure": unitCtrl.text.trim(),
                                  "estimatedCurrentValue":
                                      parseNgnInput(estimatedValueCtrl.text) ??
                                      purchaseCost ??
                                      0,
                                },
                              });
                            },
                            child: const Text("Submit equipment"),
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

    nameCtrl.dispose();
    farmLabelCtrl.dispose();
    farmSectionCtrl.dispose();
    serialCtrl.dispose();
    locationCtrl.dispose();
    descriptionCtrl.dispose();
    quantityCtrl.dispose();
    unitCtrl.dispose();
    purchaseCostCtrl.dispose();
    purchaseDateCtrl.dispose();
    usefulLifeCtrl.dispose();
    estimatedValueCtrl.dispose();
    lastAuditDateCtrl.dispose();

    if (payload == null) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = ref.read(businessAssetApiProvider);
      final created = await api.submitFarmAsset(
        token: session.token,
        payload: payload,
      );
      await _refreshFarmAuditQueries();
      if (!mounted) {
        return;
      }
      final isPending = created.approvalStatus == 'pending_approval';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPending
                ? "Farm equipment submitted for approval"
                : "Farm equipment added",
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to submit farm equipment")),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _handleNavTap(int index) {
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final currentStaffRole = profileAsync.valueOrNull?.staffRole;
    final canApproveRequests = _canApproveFarmRequests(
      actorRole: session?.user.role ?? '',
      staffRole: currentStaffRole,
    );
    final analyticsAsync = ref.watch(
      businessFarmAssetAuditProvider(_analyticsQuery),
    );
    final assetsAsync = ref.watch(businessAssetsProvider(_assetsQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Farm equipment audit"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-assets');
          },
        ),
        actions: [
          IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _isSaving ? null : _openAddAssetSheet,
            icon: const Icon(Icons.add_business_outlined),
            tooltip: "Add equipment",
          ),
          const BusinessProfileAction(logTag: "BUSINESS_FARM_AUDIT"),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: analyticsAsync.when(
          loading: _buildLoadingState,
          error: (error, _) => _buildErrorState(error),
          data: (analytics) {
            return assetsAsync.when(
              loading: _buildLoadingState,
              error: (error, _) => _buildErrorState(error),
              data: (result) {
                final assets =
                    result.assets
                        .where((asset) => asset.domainContext == 'farm')
                        .where((asset) => asset.deletedAt == null)
                        .toList()
                      ..sort(_sortFarmAssets);

                return _buildLoadedState(
                  context,
                  analytics: analytics,
                  assets: assets,
                  canApproveRequests: canApproveRequests,
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 2,
        onTap: _handleNavTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        _LoadingCard(height: 180),
        SizedBox(height: AppSpacing.section),
        _LoadingCard(height: 132),
        SizedBox(height: AppSpacing.section),
        _LoadingCard(height: 360),
      ],
    );
  }

  Widget _buildErrorState(Object error) {
    AppDebug.log(
      "BUSINESS_FARM_AUDIT",
      "Load failed",
      extra: {"error": error.toString()},
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        AppEmptyState(
          icon: Icons.agriculture_outlined,
          title: "Farm audit data unavailable",
          message:
              "We could not load the farm equipment register right now. Pull to refresh and try again.",
          action: OutlinedButton(
            onPressed: _refreshAll,
            child: const Text("Refresh"),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadedState(
    BuildContext context, {
    required FarmAssetAuditAnalytics analytics,
    required List<BusinessAsset> assets,
    required bool canApproveRequests,
  }) {
    final categoryChoices = analytics.categoryBreakdown
        .map((item) => item.label)
        .toList();
    final pendingAssets = assets
        .where((asset) => asset.approvalStatus == 'pending_approval')
        .toList();
    final pendingAuditAssets = assets
        .where(
          (asset) =>
              asset.farmProfile?.pendingAuditRequest?.status ==
              'pending_approval',
        )
        .toList();

    _maybeShowApprovalPrompt(
      canApprove: canApproveRequests,
      pendingAssets: pendingAssets,
      pendingAuditAssets: pendingAuditAssets,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        AppResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.page,
            AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(context, analytics),
              const SizedBox(height: AppSpacing.section),
              _buildApprovalInbox(
                canApproveRequests: canApproveRequests,
                pendingAssets: pendingAssets,
                pendingAuditAssets: pendingAuditAssets,
              ),
              const SizedBox(height: AppSpacing.section),
              _buildMetrics(analytics.summary),
              const SizedBox(height: AppSpacing.section),
              _buildFilters(categoryChoices),
              const SizedBox(height: AppSpacing.section),
              _buildCharts(analytics),
              const SizedBox(height: AppSpacing.section),
              _buildAttentionSection(analytics.attentionAssets),
              const SizedBox(height: AppSpacing.section),
              _buildRegisterSection(
                assets,
                canApproveRequests: canApproveRequests,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHero(BuildContext context, FarmAssetAuditAnalytics analytics) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: LinearGradient(
          colors: [
            scheme.secondaryContainer,
            scheme.primaryContainer,
            scheme.tertiaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 860;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Farm register",
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Track tools, machinery, and equipment with quarterly and yearly audit visibility.",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                "Use categories tied to each farm section, monitor audit cadence, and keep value snapshots visible for annual reviews.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppStatusChip(
                    label: "${analytics.summary.totalAssets} assets",
                    tone: AppStatusTone.info,
                    icon: Icons.agriculture_rounded,
                  ),
                  AppStatusChip(
                    label: "${analytics.summary.overdueCount} overdue",
                    tone: analytics.summary.overdueCount > 0
                        ? AppStatusTone.danger
                        : AppStatusTone.success,
                    icon: Icons.fact_check_rounded,
                  ),
                  AppStatusChip(
                    label:
                        "${analytics.summary.dueThisQuarter} due this quarter",
                    tone: AppStatusTone.warning,
                    icon: Icons.calendar_today_rounded,
                  ),
                ],
              ),
            ],
          );

          final action = SizedBox(
            width: isCompact ? double.infinity : 220,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _openAddAssetSheet,
              icon: const Icon(Icons.add_business_outlined),
              label: Text(_isSaving ? "Saving..." : "Add equipment"),
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: AppSpacing.xl),
                action,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: AppSpacing.xl),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildApprovalInbox({
    required bool canApproveRequests,
    required List<BusinessAsset> pendingAssets,
    required List<BusinessAsset> pendingAuditAssets,
  }) {
    final totalPending = pendingAssets.length + pendingAuditAssets.length;

    if (totalPending == 0) {
      return AppSectionCard(
        tone: AppPanelTone.base,
        child: const AppSectionHeader(
          title: "Approval flow",
          subtitle:
              "Staff submissions route through manager approval before equipment or audit changes become official.",
        ),
      );
    }

    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: canApproveRequests ? "Approval inbox" : "Pending review",
            subtitle: canApproveRequests
                ? "Submitted equipment and audit requests waiting for a farm manager, asset manager, estate manager, or business owner."
                : "Your register contains requests waiting for a farm manager, asset manager, estate manager, or business owner.",
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppStatusChip(
                label: "${pendingAssets.length} equipment requests",
                tone: AppStatusTone.warning,
                icon: Icons.inventory_2_outlined,
              ),
              AppStatusChip(
                label: "${pendingAuditAssets.length} audit requests",
                tone: AppStatusTone.info,
                icon: Icons.fact_check_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (pendingAssets.isNotEmpty)
            Text(
              "Latest equipment request: ${pendingAssets.first.name} by ${_actorLabel(pendingAssets.first.approvalRequestedBy)}",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (pendingAuditAssets.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Latest audit request: ${pendingAuditAssets.first.name} by ${_actorLabel(pendingAuditAssets.first.farmProfile?.pendingAuditRequest?.requestedBy)}",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics(FarmAssetAuditSummary summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = AppLayout.columnsForWidth(
          constraints.maxWidth,
          compact: 1,
          medium: 2,
          large: 3,
          xlarge: 3,
        );
        final spacing = AppSpacing.lg;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        final items = [
          AppMetricCard(
            label: "registered assets",
            value: "${summary.totalAssets}",
            icon: Icons.inventory_2_rounded,
            helper: "Tools, machinery, and support equipment",
          ),
          AppMetricCard(
            label: "tracked quantity",
            value: "${summary.totalQuantity}",
            icon: Icons.precision_manufacturing_rounded,
            helper: "Combined units across the register",
          ),
          AppMetricCard(
            label: "estimated value",
            value: formatNgn(summary.totalEstimatedValue),
            icon: Icons.pie_chart_outline_rounded,
            helper: "Current portfolio estimate",
          ),
          AppMetricCard(
            label: "due this quarter",
            value: "${summary.dueThisQuarter}",
            icon: Icons.event_note_rounded,
            helper: "Upcoming quarterly reviews",
          ),
          AppMetricCard(
            label: "due this year",
            value: "${summary.dueThisYear}",
            icon: Icons.bar_chart_rounded,
            helper: "Annual audit exposure",
          ),
          AppMetricCard(
            label: "overdue audits",
            value: "${summary.overdueCount}",
            icon: Icons.warning_amber_rounded,
            helper: "Needs review attention",
            accentColor: AppColors.error,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items) SizedBox(width: width, child: item),
          ],
        );
      },
    );
  }

  Widget _buildFilters(List<String> categoryChoices) {
    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: "Filters",
            subtitle:
                "Focus the register by audit cadence or a specific farm equipment category.",
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final cadence in _farmCadenceOptions)
                ChoiceChip(
                  selected: _selectedCadence == cadence,
                  label: Text(
                    cadence == 'all' ? "All cadences" : _prettyLabel(cadence),
                  ),
                  onSelected: (_) {
                    _logTap("cadence_filter", extra: {"cadence": cadence});
                    setState(() => _selectedCadence = cadence);
                  },
                ),
            ],
          ),
          if (categoryChoices.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  selected: _selectedCategory == null,
                  label: const Text("All categories"),
                  onSelected: (_) {
                    _logTap("category_filter", extra: {"category": "all"});
                    setState(() => _selectedCategory = null);
                  },
                ),
                for (final category in categoryChoices)
                  ChoiceChip(
                    selected: _selectedCategory == category,
                    label: Text(_prettyLabel(category)),
                    onSelected: (_) {
                      _logTap("category_filter", extra: {"category": category});
                      setState(() {
                        _selectedCategory = _selectedCategory == category
                            ? null
                            : category;
                      });
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCharts(FarmAssetAuditAnalytics analytics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        final pie = _ChartCard(
          title: "Category share",
          subtitle: "Estimated value split across farm equipment categories.",
          child: _FarmCategoryPieCard(data: analytics.categoryBreakdown),
        );
        final bar = _ChartCard(
          title: "Quarterly due audits",
          subtitle:
              "How many farm equipment reviews land in each quarter this year.",
          child: _QuarterBarChart(data: analytics.quarterBreakdown),
        );

        if (!isWide) {
          return Column(
            children: [
              pie,
              const SizedBox(height: AppSpacing.section),
              bar,
              const SizedBox(height: AppSpacing.section),
              _buildBreakdownChips(analytics),
            ],
          );
        }

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: pie),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: bar),
              ],
            ),
            const SizedBox(height: AppSpacing.section),
            _buildBreakdownChips(analytics),
          ],
        );
      },
    );
  }

  Widget _buildBreakdownChips(FarmAssetAuditAnalytics analytics) {
    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: "Audit mix",
            subtitle:
                "Status and cadence segmentation for the current farm register.",
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final bucket in analytics.cadenceBreakdown)
                AppStatusChip(
                  label: "${_prettyLabel(bucket.label)} ${bucket.count}",
                  tone: bucket.label == 'quarterly'
                      ? AppStatusTone.warning
                      : AppStatusTone.info,
                  icon: Icons.schedule_rounded,
                ),
              for (final bucket in analytics.statusBreakdown)
                AppStatusChip(
                  label: "${_prettyLabel(bucket.label)} ${bucket.count}",
                  tone: _statusTone(bucket.label),
                  icon: Icons.inventory_2_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionSection(List<FarmAssetAuditAttentionAsset> assets) {
    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: "Attention queue",
            subtitle:
                "Upcoming and overdue audits so teams know what to review next.",
          ),
          const SizedBox(height: AppSpacing.lg),
          if (assets.isEmpty)
            Text(
              "No scheduled farm audits yet. Add equipment with an audit cadence to populate this queue.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...assets.map(
              (asset) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _AttentionAssetRow(asset: asset),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRegisterSection(
    List<BusinessAsset> assets, {
    required bool canApproveRequests,
  }) {
    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: "Equipment register",
            subtitle:
                "Detailed list of farm tools and machinery currently tracked.",
            trailing: Text(
              "${assets.length} items",
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (assets.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "No farm equipment stored yet.",
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Add tools or machinery to start building quarterly and yearly audit visibility.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else
            ...assets.map(
              (asset) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _FarmAssetCard(
                  asset: asset,
                  canApproveRequests: canApproveRequests,
                  isSaving: _isSaving,
                  onSubmitAudit: () => _openAuditRequestSheet(asset),
                  onApproveAsset: asset.approvalStatus == 'pending_approval'
                      ? () => _approveRequest(asset, requestType: 'asset')
                      : null,
                  onApproveAudit:
                      asset.farmProfile?.pendingAuditRequest?.status ==
                          'pending_approval'
                      ? () => _approveRequest(asset, requestType: 'audit')
                      : null,
                  onOpen: () {
                    _logTap("open_asset", extra: {"assetId": asset.id});
                    context.push('/business-assets/${asset.id}', extra: asset);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _sortFarmAssets(BusinessAsset left, BusinessAsset right) {
    final leftDate = left.farmProfile?.nextAuditDate ?? DateTime(2100);
    final rightDate = right.farmProfile?.nextAuditDate ?? DateTime(2100);
    final compareDate = leftDate.compareTo(rightDate);
    if (compareDate != 0) {
      return compareDate;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  String _actorLabel(BusinessAssetActorSnapshot? actor) {
    if (actor == null) {
      return "Unknown staff";
    }

    final role = actor.staffRole?.trim().isNotEmpty == true
        ? formatStaffRoleLabel(actor.staffRole!, fallback: actor.actorRole)
        : actor.actorRole.trim().isNotEmpty
        ? actor.actorRole
        : "staff";
    final name = actor.name.trim().isNotEmpty ? actor.name.trim() : "Unknown";
    return "$name (${_prettyLabel(role)})";
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _FarmCategoryPieCard extends StatelessWidget {
  final List<FarmAssetAuditCategoryBreakdown> data;

  const _FarmCategoryPieCard({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Text(
        "No category data yet.",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    final palette = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      AppColors.analyticsAccent,
      AppColors.commerceAccent,
      AppColors.tenantAccent,
      AppColors.productionAccent,
      AppColors.recordsAccent,
    ];

    final segments = <_PieSegment>[
      for (var i = 0; i < data.length; i++)
        _PieSegment(
          label: _prettyLabel(data[i].label),
          value: data[i].estimatedValue <= 0
              ? data[i].assetCount.toDouble()
              : data[i].estimatedValue,
          color: palette[i % palette.length],
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 520;
        final chart = SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(
            painter: _PieChartPainter(segments: segments),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${data.fold<int>(0, (sum, item) => sum + item.assetCount)}",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "tracked assets",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < data.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _LegendRow(
                  color: palette[i % palette.length],
                  label: _prettyLabel(data[i].label),
                  value: formatNgn(data[i].estimatedValue),
                ),
              ),
          ],
        );

        if (!isWide) {
          return Column(
            children: [
              chart,
              const SizedBox(height: AppSpacing.lg),
              legend,
            ],
          );
        }

        return Row(
          children: [
            chart,
            const SizedBox(width: AppSpacing.xl),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _QuarterBarChart extends StatelessWidget {
  final List<FarmAssetAuditQuarterBucket> data;

  const _QuarterBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxValue = data.fold<int>(
      0,
      (max, item) => math.max(max, item.dueCount),
    );
    final safeMax = maxValue == 0 ? 1 : maxValue;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 250,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      "${item.dueCount}",
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: item.dueCount / safeMax,
                          widthFactor: 0.72,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [scheme.primary, scheme.tertiary],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttentionAssetRow extends StatelessWidget {
  final FarmAssetAuditAttentionAsset asset;

  const _AttentionAssetRow({required this.asset});

  @override
  Widget build(BuildContext context) {
    final nextAuditLabel = formatDateLabel(
      asset.nextAuditDate,
      fallback: "No audit date",
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          AppIconBadge(
            icon: Icons.build_circle_outlined,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "${_prettyLabel(asset.category)} • ${asset.quantity} units • $nextAuditLabel",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppStatusChip(
                label: _prettyLabel(asset.status),
                tone: _statusTone(asset.status),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                formatNgn(asset.estimatedCurrentValue),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FarmAssetCard extends StatelessWidget {
  final BusinessAsset asset;
  final VoidCallback onOpen;
  final VoidCallback onSubmitAudit;
  final VoidCallback? onApproveAsset;
  final VoidCallback? onApproveAudit;
  final bool canApproveRequests;
  final bool isSaving;

  const _FarmAssetCard({
    required this.asset,
    required this.onOpen,
    required this.onSubmitAudit,
    required this.canApproveRequests,
    required this.isSaving,
    this.onApproveAsset,
    this.onApproveAudit,
  });

  @override
  Widget build(BuildContext context) {
    final farmProfile = asset.farmProfile;
    final pendingAuditRequest = farmProfile?.pendingAuditRequest;
    final hasPendingAssetApproval = asset.approvalStatus == 'pending_approval';
    final hasPendingAuditApproval =
        pendingAuditRequest?.status == 'pending_approval';
    final nextAuditLabel = formatDateLabel(
      farmProfile?.nextAuditDate,
      fallback: "Not scheduled",
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      asset.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppStatusChip(
                    label: _prettyLabel(asset.status),
                    tone: _statusTone(asset.status),
                  ),
                  if (hasPendingAssetApproval) ...[
                    const SizedBox(width: AppSpacing.sm),
                    AppStatusChip(
                      label: "Awaiting approval",
                      tone: AppStatusTone.warning,
                      icon: Icons.pending_actions_outlined,
                    ),
                  ],
                  if (hasPendingAuditApproval) ...[
                    const SizedBox(width: AppSpacing.sm),
                    AppStatusChip(
                      label: "Audit pending",
                      tone: AppStatusTone.info,
                      icon: Icons.fact_check_outlined,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if ((farmProfile?.farmCategory ?? "").isNotEmpty)
                    AppStatusChip(
                      label: _prettyLabel(farmProfile!.farmCategory!),
                      tone: AppStatusTone.info,
                      icon: Icons.category_rounded,
                    ),
                  if ((farmProfile?.auditFrequency ?? "").isNotEmpty)
                    AppStatusChip(
                      label: _prettyLabel(farmProfile!.auditFrequency!),
                      tone: AppStatusTone.warning,
                      icon: Icons.schedule_rounded,
                    ),
                  if ((farmProfile?.farmSection ?? "").isNotEmpty)
                    AppStatusChip(
                      label: farmProfile!.farmSection!,
                      tone: AppStatusTone.success,
                      icon: Icons.place_outlined,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                asset.description?.trim().isNotEmpty == true
                    ? asset.description!
                    : "Open the asset detail page to update lifecycle, depreciation, and operational context.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Added by ${_displayActor(asset.approvalRequestedBy)}",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (hasPendingAuditApproval) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "Audit request by ${_displayActor(pendingAuditRequest?.requestedBy)} for ${formatDateLabel(pendingAuditRequest?.auditDate, fallback: 'pending date')} • wants ${_prettyLabel(pendingAuditRequest?.resultingStatus ?? asset.status)}",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else if ((farmProfile?.lastAuditSubmittedBy?.name ?? '')
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "Last audit by ${_displayActor(farmProfile?.lastAuditSubmittedBy)}",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _RegisterStat(
                      label: "Quantity",
                      value:
                          "${farmProfile?.quantity ?? asset.inventory?.quantity ?? 1} ${(farmProfile?.unitOfMeasure ?? "units").trim()}",
                    ),
                  ),
                  Expanded(
                    child: _RegisterStat(
                      label: "Next audit",
                      value: nextAuditLabel,
                    ),
                  ),
                  Expanded(
                    child: _RegisterStat(
                      label: "Current value",
                      value: formatNgn(
                        farmProfile?.estimatedCurrentValue ??
                            asset.purchaseCost ??
                            0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        (isSaving ||
                            hasPendingAssetApproval ||
                            hasPendingAuditApproval)
                        ? null
                        : onSubmitAudit,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      hasPendingAssetApproval
                          ? "Await equipment approval"
                          : hasPendingAuditApproval
                          ? "Audit awaiting approval"
                          : "Submit audit",
                    ),
                  ),
                  if (canApproveRequests && onApproveAsset != null)
                    ElevatedButton.icon(
                      onPressed: isSaving ? null : onApproveAsset,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text("Approve equipment"),
                    ),
                  if (canApproveRequests && onApproveAudit != null)
                    ElevatedButton.icon(
                      onPressed: isSaving ? null : onApproveAudit,
                      icon: const Icon(Icons.approval_outlined),
                      label: const Text("Approve audit"),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayActor(BusinessAssetActorSnapshot? actor) {
    if (actor == null) {
      return "Unknown staff";
    }

    final role = actor.staffRole?.trim().isNotEmpty == true
        ? formatStaffRoleLabel(actor.staffRole!, fallback: actor.actorRole)
        : actor.actorRole.trim().isNotEmpty
        ? actor.actorRole
        : "staff";
    final name = actor.name.trim().isNotEmpty ? actor.name.trim() : "Unknown";
    return "$name (${_prettyLabel(role)})";
  }
}

class _RegisterStat extends StatelessWidget {
  final String label;
  final String value;

  const _RegisterStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final double height;

  const _LoadingCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
    );
  }
}

class _PieSegment {
  final String label;
  final double value;
  final Color color;

  const _PieSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _PieChartPainter extends CustomPainter {
  final List<_PieSegment> segments;

  const _PieChartPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(
      0,
      (sum, segment) => sum + math.max(0, segment.value),
    );
    if (total <= 0) {
      return;
    }

    final strokeWidth = math.min(size.width, size.height) * 0.22;
    final rect = Offset.zero & size;
    var startAngle = -math.pi / 2;

    for (final segment in segments) {
      final sweepAngle = (segment.value / total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = segment.color;
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.segments != segments;
  }
}

String _prettyLabel(String raw) {
  return raw
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.trim().isNotEmpty)
      .map(
        (part) => "${part[0].toUpperCase()}${part.substring(1).toLowerCase()}",
      )
      .join(" ");
}

AppStatusTone _statusTone(String status) {
  switch (status) {
    case 'active':
      return AppStatusTone.success;
    case 'maintenance':
      return AppStatusTone.warning;
    case 'inactive':
      return AppStatusTone.neutral;
    default:
      return AppStatusTone.info;
  }
}
