/// lib/app/features/home/presentation/business_product_detail_screen.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Business product detail screen with editable fields + audit snapshot.
///
/// WHY:
/// - Lets owners/staff edit product data in one place.
/// - Shows backend-only audit fields for compliance and traceability.
///
/// HOW:
/// - Fetches product via businessProductByIdProvider.
/// - Prefills controllers once and submits PATCH updates.
/// - Displays audit info read-only (no client edits).
///
/// DEBUGGING:
/// - Logs screen build, button taps, and update results.
/// -------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';

class BusinessProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const BusinessProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<BusinessProductDetailScreen> createState() =>
      _BusinessProductDetailScreenState();
}

class _BusinessProductDetailScreenState
    extends ConsumerState<BusinessProductDetailScreen> {
  static const String _ownerRole = "business_owner";
  static const String _preorderSectionTitle = "Linked production pre-order";
  static const String _preorderSectionHint =
      "Configure conservative pre-order controls for this product's linked plan.";
  static const String _preorderNoPlanTitle = "No linked production plan";
  static const String _preorderNoPlanMessage =
      "Create or attach a production plan to manage pre-order controls.";
  static const String _configurePreorderLabel = "Configure pre-order";
  static const String _reconcilePreorderLabel = "Reconcile expired holds";
  static const String _openPlanLabel = "Open plan detail";
  static const String _preorderConfigTitle = "Pre-order settings";
  static const String _preorderEnableLabel = "Enable pre-order";
  static const String _preorderYieldLabel = "Conservative yield quantity";
  static const String _preorderYieldUnitLabel = "Yield unit";
  static const String _preorderCapRatioLabel = "Cap ratio (0.1 - 0.9)";
  static const String _preorderConfigSaveLabel = "Save";
  static const String _preorderConfigCancelLabel = "Cancel";
  static const String _preorderConfigValidation =
      "Provide positive yield quantity and cap ratio between 0.1 and 0.9.";

  // WHY: Controllers keep form values stable across rebuilds.
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();

  // WHY: Avoid double-submit on slow networks.
  bool _isSaving = false;
  // WHY: Prevents re-prefill clobbering user edits.
  bool _didPrefill = false;
  // WHY: Track active flag separately for toggle input.
  bool _isActive = true;

  @override
  void dispose() {
    // WHY: Dispose controllers to avoid memory leaks.
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  void _logFlow(String step, String message, {Map<String, dynamic>? extra}) {
    // WHY: Consistent logs keep product edit flows traceable.
    AppDebug.log("BUSINESS_PRODUCT_DETAIL", "$step | $message", extra: extra);
  }

  void _applyProduct(Product product) {
    // WHY: Prefill only once so active edits remain intact.
    if (_didPrefill) return;

    _nameCtrl.text = product.name;
    _descCtrl.text = product.description;
    // WHY: Display product price in NGN while storing minor units.
    _priceCtrl.text = formatNgnInputFromKobo(product.priceCents);
    _stockCtrl.text = product.stock.toString();
    _isActive = product.isActive;

    _didPrefill = true;
  }

  int? _parseInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  double _derivePreorderCapRatio(ProductionPreorderSummary? summary) {
    if (summary == null) {
      return 0.5;
    }
    final cap = summary.preorderCapQuantity;
    final yield = summary.conservativeYieldQuantity;
    if (yield == null || yield <= 0 || cap <= 0) {
      return 0.5;
    }
    return (cap / yield).clamp(0.1, 0.9).toDouble();
  }

  Future<Map<String, dynamic>?> _showPreorderConfigDialog({
    required ProductionPreorderSummary? summary,
  }) async {
    bool allowPreorder = summary?.preorderEnabled == true;
    final yieldController = TextEditingController(
      text: summary?.conservativeYieldQuantity?.toString() ?? "",
    );
    final yieldUnitController = TextEditingController(
      text: (summary?.conservativeYieldUnit ?? "").trim().isEmpty
          ? "units"
          : summary!.conservativeYieldUnit,
    );
    final capRatioController = TextEditingController(
      text: _derivePreorderCapRatio(summary).toStringAsFixed(2),
    );
    String validationError = "";

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (statefulContext, setDialogState) {
            return AlertDialog(
              title: const Text(_preorderConfigTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(_preorderEnableLabel),
                    value: allowPreorder,
                    onChanged: (value) {
                      setDialogState(() {
                        allowPreorder = value;
                        validationError = "";
                      });
                    },
                  ),
                  if (allowPreorder) ...[
                    TextField(
                      controller: yieldController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: _preorderYieldLabel,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: yieldUnitController,
                      decoration: const InputDecoration(
                        labelText: _preorderYieldUnitLabel,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: capRatioController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: _preorderCapRatioLabel,
                      ),
                    ),
                  ],
                  if (validationError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationError,
                      style: Theme.of(statefulContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(statefulContext).colorScheme.error,
                          ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text(_preorderConfigCancelLabel),
                ),
                TextButton(
                  onPressed: () {
                    if (!allowPreorder) {
                      Navigator.of(dialogContext).pop({"allowPreorder": false});
                      return;
                    }

                    final yieldQuantity = num.tryParse(
                      yieldController.text.trim(),
                    );
                    final capRatio = num.tryParse(
                      capRatioController.text.trim(),
                    );
                    final yieldUnit = yieldUnitController.text.trim().isEmpty
                        ? "units"
                        : yieldUnitController.text.trim();

                    final validYield =
                        yieldQuantity != null && yieldQuantity > 0;
                    final validRatio =
                        capRatio != null && capRatio >= 0.1 && capRatio <= 0.9;
                    if (!validYield || !validRatio) {
                      setDialogState(() {
                        validationError = _preorderConfigValidation;
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop({
                      "allowPreorder": true,
                      "conservativeYieldQuantity": yieldQuantity,
                      "conservativeYieldUnit": yieldUnit,
                      "preorderCapRatio": capRatio,
                    });
                  },
                  child: const Text(_preorderConfigSaveLabel),
                ),
              ],
            );
          },
        );
      },
    );

    yieldController.dispose();
    yieldUnitController.dispose();
    capRatioController.dispose();
    return payload;
  }

  Future<void> _updatePlanPreorder({
    required String planId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await ref
          .read(productionPlanActionsProvider)
          .updatePlanPreorder(planId: planId, payload: payload);
      ref.invalidate(productionPlanDetailProvider(planId));
      ref.invalidate(businessProductByIdProvider(widget.productId));
      _showSnack("Pre-order settings updated.");
    } catch (error) {
      _logFlow(
        "PREORDER_UPDATE_FAIL",
        "Unable to update linked plan preorder settings",
        extra: {"planId": planId, "error": error.toString()},
      );
      _showSnack("Unable to update pre-order settings.");
    }
  }

  Future<void> _reconcileExpiredPreorders({required String planId}) async {
    try {
      final summary = await ref
          .read(productionPlanActionsProvider)
          .reconcileExpiredPreorders(planId: planId);
      ref.invalidate(productionPlanDetailProvider(planId));
      ref.invalidate(businessProductByIdProvider(widget.productId));
      _showSnack(
        "Reconcile complete: expired ${summary.expiredCount}, errors ${summary.errorCount}.",
      );
    } catch (error) {
      _logFlow(
        "PREORDER_RECONCILE_FAIL",
        "Unable to reconcile linked plan preorder holds",
        extra: {"planId": planId, "error": error.toString()},
      );
      _showSnack("Unable to reconcile expired holds.");
    }
  }

  Widget _buildPreorderSummaryRows(ProductionPreorderSummary summary) {
    final confidencePercent = (summary.confidenceScore * 100).clamp(0, 100);
    final coveragePercent = (summary.approvedProgressCoverage * 100).clamp(
      0,
      100,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAuditRow(
          "State",
          summary.productionState.trim().isEmpty
              ? "—"
              : summary.productionState,
        ),
        _buildAuditRow("Enabled", summary.preorderEnabled ? "Yes" : "No"),
        _buildAuditRow("Cap", "${summary.preorderCapQuantity}"),
        _buildAuditRow("Effective cap", "${summary.effectiveCap}"),
        _buildAuditRow("Reserved", "${summary.preorderReservedQuantity}"),
        _buildAuditRow("Remaining", "${summary.preorderRemainingQuantity}"),
        _buildAuditRow(
          "Confidence",
          "${confidencePercent.toStringAsFixed(0)}% (coverage ${coveragePercent.toStringAsFixed(0)}%)",
        ),
        _buildAuditRow(
          "Conservative yield",
          "${summary.conservativeYieldQuantity ?? "—"} ${summary.conservativeYieldUnit}",
        ),
      ],
    );
  }

  Future<void> _saveProduct(Product product) async {
    if (_isSaving) return;

    _logFlow("SAVE_TAP", "Save changes tapped", extra: {"id": product.id});

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _logFlow("SAVE_BLOCK", "Missing session");
      _showSnack("Session expired. Please sign in again.");
      return;
    }

    final payload = <String, dynamic>{};
    final name = _nameCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final price = parseNgnToKobo(_priceCtrl.text);
    final stock = _parseInt(_stockCtrl.text);

    if (name.isNotEmpty && name != product.name) payload["name"] = name;
    if (description != product.description) {
      payload["description"] = description;
    }
    if (price != null && price != product.priceCents) {
      payload["price"] = price;
    }
    if (stock != null && stock != product.stock) {
      payload["stock"] = stock;
    }
    if (_isActive != product.isActive) payload["isActive"] = _isActive;

    if (payload.isEmpty) {
      _showSnack("No changes to save.");
      return;
    }

    setState(() => _isSaving = true);

    try {
      final api = ref.read(businessProductApiProvider);
      _logFlow("SAVE_REQUEST", "Updating product", extra: {"id": product.id});
      await api.updateProduct(
        token: session.token,
        id: product.id,
        payload: payload,
      );

      // WHY: Refresh product detail so audit fields stay accurate.
      ref.invalidate(businessProductByIdProvider(widget.productId));
      ref.invalidate(businessProductsProvider);

      _showSnack("Product updated successfully.");
    } catch (e) {
      _logFlow(
        "SAVE_FAIL",
        "Product update failed",
        extra: {"error": e.toString()},
      );
      _showSnack("Update failed. Please try again.");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDate(DateTime? value) {
    // WHY: Keep audit date labels consistent across detail screens.
    return formatDateLabel(value, fallback: kDateFallbackDash);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  Widget _buildAuditRow(String label, String value) {
    // WHY: Keep audit rows compact and easy to scan.
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "BUSINESS_PRODUCT_DETAIL",
      "build()",
      extra: {"productId": widget.productId, "isSaving": _isSaving},
    );
    final colorScheme = Theme.of(context).colorScheme;
    final session = ref.watch(authSessionProvider);
    final isOwner = session?.user.role == _ownerRole;

    final productAsync = ref.watch(
      businessProductByIdProvider(widget.productId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Product details"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _logFlow("NAV_BACK", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-products');
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _logFlow("REFRESH", "Manual refresh");
          // WHY: Central refresh keeps business data in sync across screens.
          await AppRefresh.refreshApp(
            ref: ref,
            source: "business_product_detail_pull",
          );
        },
        child: productAsync.when(
          data: (product) {
            _applyProduct(product);
            final linkedPlanId = (product.productionPlanId ?? "").trim();
            final hasLinkedPlan = linkedPlanId.isNotEmpty;
            final linkedPlanAsync = hasLinkedPlan
                ? ref.watch(productionPlanDetailProvider(linkedPlanId))
                : null;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  "Editable fields",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Update the product details below. Audit info is read-only.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _nameCtrl,
                  label: "Name",
                  hint: "Executive chair",
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _descCtrl,
                  label: "Description",
                  hint: "High-back office chair",
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _priceCtrl,
                  label: "Price (NGN)",
                  hint: "129000",
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  // WHY: Auto-format NGN values as the user types.
                  inputFormatters: const [NgnInputFormatter()],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _stockCtrl,
                  label: "Stock",
                  hint: "10",
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _isActive,
                  onChanged: (value) {
                    _logFlow(
                      "TOGGLE_ACTIVE",
                      "Status toggled",
                      extra: {"value": value},
                    );
                    setState(() => _isActive = value);
                  },
                  title: const Text("Active listing"),
                  subtitle: const Text("Disable to archive this product."),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : () => _saveProduct(product),
                    child: Text(_isSaving ? "Saving..." : "Save changes"),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _preorderSectionTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _preorderSectionHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: !hasLinkedPlan
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _preorderNoPlanTitle,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _preorderNoPlanMessage,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        )
                      : linkedPlanAsync!.when(
                          data: (planDetail) {
                            final summary = planDetail.preorderSummary;
                            if (summary == null) {
                              return const Text(
                                "Pre-order summary is unavailable for this plan.",
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildPreorderSummaryRows(summary),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        final payload =
                                            await _showPreorderConfigDialog(
                                              summary: summary,
                                            );
                                        if (payload == null) {
                                          return;
                                        }
                                        await _updatePlanPreorder(
                                          planId: linkedPlanId,
                                          payload: payload,
                                        );
                                      },
                                      icon: const Icon(Icons.tune),
                                      label: const Text(
                                        _configurePreorderLabel,
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: !isOwner
                                          ? null
                                          : () async {
                                              await _reconcileExpiredPreorders(
                                                planId: linkedPlanId,
                                              );
                                            },
                                      icon: const Icon(
                                        Icons.restore_from_trash_outlined,
                                      ),
                                      label: const Text(
                                        _reconcilePreorderLabel,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        context.push(
                                          productionPlanDetailPath(
                                            linkedPlanId,
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text(_openPlanLabel),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => Text(
                            "Unable to load linked plan details.",
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.error),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Audit snapshot",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    // WHY: Use surface tokens for audit block contrast.
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAuditRow("Product ID", product.id),
                      _buildAuditRow("Business ID", product.businessId ?? "—"),
                      _buildAuditRow(
                        "Created at",
                        _formatDate(product.createdAt),
                      ),
                      _buildAuditRow(
                        "Updated at",
                        _formatDate(product.updatedAt),
                      ),
                      _buildAuditRow("Created by", product.createdBy ?? "—"),
                      _buildAuditRow("Updated by", product.updatedBy ?? "—"),
                      _buildAuditRow(
                        "Deleted at",
                        _formatDate(product.deletedAt),
                      ),
                      _buildAuditRow("Deleted by", product.deletedBy ?? "—"),
                      _buildAuditRow(
                        "Gallery images",
                        product.imageUrls.length.toString(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              SizedBox(height: 140),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 140),
              Center(child: Text("Unable to load product details.")),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  _logFlow("RETRY", "Retry fetch tapped");
                  ref.invalidate(businessProductByIdProvider(widget.productId));
                },
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
