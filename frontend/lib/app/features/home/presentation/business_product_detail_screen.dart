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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class BusinessProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const BusinessProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<BusinessProductDetailScreen> createState() =>
      _BusinessProductDetailScreenState();
}

class _BusinessProductDetailScreenState
    extends ConsumerState<BusinessProductDetailScreen> {
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
    _priceCtrl.text = product.priceCents.toString();
    _stockCtrl.text = product.stock.toString();
    _isActive = product.isActive;

    _didPrefill = true;
  }

  int? _parseInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
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
    final price = _parseInt(_priceCtrl.text);
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
    if (value == null) return "—";
    return "${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}";
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
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
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurface),
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

    final productAsync =
        ref.watch(businessProductByIdProvider(widget.productId));

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
          ref.invalidate(businessProductByIdProvider(widget.productId));
        },
        child: productAsync.when(
          data: (product) {
            _applyProduct(product);

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
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
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
                  keyboardType: TextInputType.number,
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
                    _logFlow("TOGGLE_ACTIVE", "Status toggled", extra: {
                      "value": value,
                    });
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
                    color: colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAuditRow("Product ID", product.id),
                      _buildAuditRow(
                        "Business ID",
                        product.businessId ?? "—",
                      ),
                      _buildAuditRow(
                        "Created at",
                        _formatDate(product.createdAt),
                      ),
                      _buildAuditRow(
                        "Updated at",
                        _formatDate(product.updatedAt),
                      ),
                      _buildAuditRow(
                        "Created by",
                        product.createdBy ?? "—",
                      ),
                      _buildAuditRow(
                        "Updated by",
                        product.updatedBy ?? "—",
                      ),
                      _buildAuditRow(
                        "Deleted at",
                        _formatDate(product.deletedAt),
                      ),
                      _buildAuditRow(
                        "Deleted by",
                        product.deletedBy ?? "—",
                      ),
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
