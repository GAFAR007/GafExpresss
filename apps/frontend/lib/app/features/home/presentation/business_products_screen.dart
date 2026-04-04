/// lib/app/features/home/presentation/business_products_screen.dart
/// ---------------------------------------------------------------
/// WHAT:
/// - Business products management screen (list + CRUD actions).
///
/// WHY:
/// - Business owners/staff need to manage their inventory in-app.
/// - Keeps business tooling separate from customer browsing.
///
/// HOW:
/// - Loads /business/products via providers.
/// - Uses bottom sheets for create/edit forms.
/// - Soft delete + restore actions call backend endpoints.
///
/// DEBUGGING:
/// - Logs build, button taps, and API actions.
/// ---------------------------------------------------------------
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_profile_action.dart';
import 'package:frontend/app/features/home/presentation/business_product_form_sheet.dart';
import 'package:frontend/app/features/home/presentation/business_analytics_models.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/settings/settings_image_picker.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessProductsScreen extends ConsumerStatefulWidget {
  const BusinessProductsScreen({super.key});

  @override
  ConsumerState<BusinessProductsScreen> createState() =>
      _BusinessProductsScreenState();
}

class _BusinessProductsScreenState
    extends ConsumerState<BusinessProductsScreen> {
  static const String _preorderSnapshotLabel = "Pre-order snapshot";
  static const String _openPlanLabel = "Open plan";
  static const String _openDetailLabel = "Open detail";

  // WHY: Track filter state to show active vs archived items.
  bool _showArchivedOnly = false;
  // WHY: Prevent concurrent product image uploads.
  bool _isUploadingImage = false;
  // WHY: Prevent overlapping image deletes on the same screen.
  bool _isDeletingImage = false;

  void _logFlow(String step, String message, {Map<String, dynamic>? extra}) {
    // WHY: Consistent logs help trace user flows and failures.
    AppDebug.log("BUSINESS_PRODUCTS", "$step | $message", extra: extra);
  }

  BusinessProductsQuery _buildQuery() {
    // WHY: The backend supports isActive filtering for active/archived items.
    return BusinessProductsQuery(isActive: _showArchivedOnly ? false : true);
  }

  Future<void> _refreshProducts() async {
    _logFlow("REFRESH", "Refreshing products");
    // WHY: Central refresh keeps business data in sync across screens.
    await AppRefresh.refreshApp(ref: ref, source: "business_products_refresh");
  }

  Future<void> _openProductForm({Product? product}) async {
    // WHY: Use one form for both create and edit to keep UX consistent.
    _logFlow(
      "FORM_OPEN",
      product == null ? "Create product" : "Edit product",
      extra: {"id": product?.id},
    );

    final saved = await showBusinessProductFormSheet(
      context: context,
      product: product,
      onSuccess: (_) async {
        // WHY: Refresh list so the new/updated product appears immediately.
        await _refreshProducts();
      },
    );

    if (saved == null) {
      _logFlow("FORM_CANCEL", "Product form dismissed");
      return;
    }

    _logFlow("FORM_DONE", "Product saved", extra: {"id": saved.id});
  }

  Future<void> _softDeleteProduct(String id) async {
    _logFlow("DELETE_TAP", "Soft delete tapped", extra: {"id": id});

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _showSnack("Session expired. Please sign in again.");
      return;
    }

    try {
      final api = ref.read(businessProductApiProvider);
      _logFlow("DELETE_REQUEST", "Soft delete request", extra: {"id": id});
      await api.softDeleteProduct(token: session.token, id: id);
      await _refreshProducts();
      _showSnack("Product archived.");
    } catch (e) {
      _logFlow(
        "DELETE_FAIL",
        "Soft delete failed",
        extra: {"error": e.toString()},
      );
      _showSnack(_extractErrorMessage(e));
    }
  }

  Future<void> _restoreProduct(String id) async {
    _logFlow("RESTORE_TAP", "Restore tapped", extra: {"id": id});

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _showSnack("Session expired. Please sign in again.");
      return;
    }

    try {
      final api = ref.read(businessProductApiProvider);
      _logFlow("RESTORE_REQUEST", "Restore request", extra: {"id": id});
      await api.restoreProduct(token: session.token, id: id);
      await _refreshProducts();
      _showSnack("Product restored.");
    } catch (e) {
      _logFlow(
        "RESTORE_FAIL",
        "Restore failed",
        extra: {"error": e.toString()},
      );
      _showSnack(_extractErrorMessage(e));
    }
  }

  Future<void> _uploadProductImage(Product product) async {
    if (_isUploadingImage) return;

    _logFlow(
      "IMAGE_UPLOAD_TAP",
      "Upload image tapped",
      extra: {"id": product.id},
    );

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _showSnack("Session expired. Please sign in again.");
      return;
    }

    // WHY: Reuse the cross-platform picker helper for gallery uploads.
    final pickedImages = await pickProfileImages();
    if (pickedImages.isEmpty) {
      _logFlow("IMAGE_UPLOAD_CANCEL", "User cancelled image picker");
      return;
    }

    setState(() => _isUploadingImage = true);

    try {
      final api = ref.read(businessProductApiProvider);
      for (final picked in pickedImages) {
        _logFlow(
          "IMAGE_UPLOAD_REQUEST",
          "Uploading product image",
          extra: {
            "bytes": picked.bytes.length,
            "filename": picked.filename,
            "totalImages": pickedImages.length,
          },
        );

        await api.uploadProductImage(
          token: session.token,
          id: product.id,
          bytes: picked.bytes,
          filename: picked.filename,
        );
      }

      await _refreshProducts();
      _showSnack(
        pickedImages.length == 1
            ? "Image uploaded successfully."
            : "${pickedImages.length} images uploaded successfully.",
      );
    } catch (e) {
      _logFlow(
        "IMAGE_UPLOAD_FAIL",
        "Image upload failed",
        extra: {"error": e.toString()},
      );
      _showSnack(_extractErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _deleteProductImage({
    required Product product,
    required String imageUrl,
  }) async {
    if (_isDeletingImage) return;

    _logFlow(
      "IMAGE_DELETE_TAP",
      "Delete image tapped",
      extra: {"id": product.id},
    );

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _showSnack("Session expired. Please sign in again.");
      return;
    }

    final confirmed = await _confirmDeleteImage();
    if (!confirmed) {
      _logFlow("IMAGE_DELETE_CANCEL", "Delete cancelled");
      return;
    }

    setState(() => _isDeletingImage = true);

    try {
      final api = ref.read(businessProductApiProvider);
      _logFlow(
        "IMAGE_DELETE_REQUEST",
        "Deleting product image",
        extra: {"id": product.id},
      );

      await api.deleteProductImage(
        token: session.token,
        id: product.id,
        imageUrl: imageUrl,
      );

      await _refreshProducts();
      _showSnack("Image deleted successfully.");
    } catch (e) {
      _logFlow(
        "IMAGE_DELETE_FAIL",
        "Image delete failed",
        extra: {"error": e.toString()},
      );
      _showSnack(_extractErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isDeletingImage = false);
    }
  }

  Future<bool> _confirmDeleteImage() async {
    _logFlow("IMAGE_DELETE_CONFIRM", "Asking for delete confirmation");

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete image?"),
        content: const Text("This removes the image from this product."),
        actions: [
          TextButton(
            onPressed: () {
              _logFlow("IMAGE_DELETE_CANCEL", "Delete dialog cancelled");
              Navigator.of(context).pop(false);
            },
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              _logFlow("IMAGE_DELETE_CONFIRM", "Delete dialog confirmed");
              Navigator.of(context).pop(true);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _extractErrorMessage(Object error) {
    // WHY: Prefer backend error payloads so the UI stays "dumb".
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data["error"] ?? data["message"];
        if (message != null) {
          return message.toString();
        }
      }
    }
    return "Action failed. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_PRODUCTS", "build()");

    final productsAsync = ref.watch(businessProductsProvider(_buildQuery()));
    final summaryAsync = ref.watch(businessAnalyticsSummaryProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Business products"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // WHY: Log navigation to help trace user flow.
            AppDebug.log("BUSINESS_PRODUCTS", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-dashboard');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openProductForm(),
            tooltip: "Create product",
          ),
          const BusinessProfileAction(logTag: "BUSINESS_PRODUCTS"),
        ],
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 1,
        onTap: (index) => _handleNavTap(index),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshProducts(),
        child: productsAsync.when(
          data: (products) {
            final summaryCard = summaryAsync.when(
              data: (summary) => _buildSummaryCard(summary),
              loading: () => _buildSummaryCard(_emptySummary()),
              error: (error, _) {
                AppDebug.log(
                  "BUSINESS_PRODUCTS",
                  "Analytics summary failed",
                  extra: {"error": error.toString()},
                );
                return _buildSummaryCard(
                  _emptySummary(),
                  helper: "Summary unavailable",
                );
              },
            );

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                AppResponsiveContent(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.page,
                    AppSpacing.page,
                    AppSpacing.section,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionCard(
                        tone: AppPanelTone.hero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppSectionHeader(
                              title: "Inventory command center",
                              subtitle:
                                  "Manage product records, stock visibility, imagery, and linked production context from one place.",
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: const [
                                AppStatusChip(
                                  label: "Product records",
                                  tone: AppStatusTone.info,
                                  icon: Icons.inventory_2_outlined,
                                ),
                                AppStatusChip(
                                  label: "Operational stock",
                                  tone: AppStatusTone.success,
                                  icon: Icons.stacked_bar_chart_rounded,
                                ),
                                AppStatusChip(
                                  label: "Image-ready catalog",
                                  tone: AppStatusTone.warning,
                                  icon: Icons.image_outlined,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.section),
                      summaryCard,
                      const SizedBox(height: AppSpacing.lg),
                      _buildFilterRow(productCount: products.length),
                      const SizedBox(height: AppSpacing.lg),
                      if (products.isEmpty)
                        const AppEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: "No products found",
                          message:
                              "Create a product to populate this inventory view and unlock analytics, stock, and production signals.",
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = AppLayout.columnsForWidth(
                              constraints.maxWidth,
                              compact: 1,
                              medium: 2,
                              large: 2,
                              xlarge: 3,
                            );
                            final spacing = AppSpacing.lg;
                            final itemWidth =
                                (constraints.maxWidth -
                                    (spacing * (columns - 1))) /
                                columns;

                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: products
                                  .map(
                                    (product) => SizedBox(
                                      width: itemWidth,
                                      child: _buildProductCard(product),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 180),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              AppResponsiveContent(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  120,
                  AppSpacing.page,
                  AppSpacing.section,
                ),
                child: AppEmptyState(
                  icon: Icons.warning_amber_rounded,
                  title: "Product data unavailable",
                  message: _extractErrorMessage(error),
                  action: OutlinedButton(
                    onPressed: _refreshProducts,
                    child: const Text("Refresh"),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleNavTap(int index) {
    AppDebug.log(
      "BUSINESS_PRODUCTS",
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

  void _openProductDetail(Product product) {
    _logFlow("DETAIL_OPEN", "Product tapped", extra: {"id": product.id});
    context.go('/business-products/${product.id}');
  }

  Widget _buildProductCard(Product product) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryImage = _primaryImageUrl(product);
    final galleryUrls = _galleryImageUrls(product, primaryImage);
    final priceLabel = formatNgnFromCents(product.priceCents);
    final statusLabel = product.isActive ? "Active" : "Archived";
    final productionState = product.productionState.trim();
    final hasLinkedPlan = (product.productionPlanId ?? "").trim().isNotEmpty;
    final hasPreorderSignals =
        productionState.isNotEmpty ||
        product.preorderEnabled ||
        product.preorderCapQuantity > 0 ||
        product.preorderReservedQuantity > 0;
    final preorderRemaining =
        (product.preorderCapQuantity - product.preorderReservedQuantity) < 0
        ? 0
        : product.preorderCapQuantity - product.preorderReservedQuantity;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProductDetail(product),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProductThumbnail(
                      primaryImage,
                      size: 108,
                      onDelete: primaryImage == null
                          ? null
                          : () => _deleteProductImage(
                              product: product,
                              imageUrl: primaryImage,
                            ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              _buildStatusPill(product.isActive),
                              if (product.category.trim().isNotEmpty)
                                _buildMetaChip(product.category.trim()),
                              if (product.brand.trim().isNotEmpty)
                                _buildMetaChip(product.brand.trim()),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            product.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (product.description.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              product.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              _buildMetaChip(priceLabel),
                              _buildMetaChip("Stock ${product.stock}"),
                              if (product.subcategory.trim().isNotEmpty)
                                _buildMetaChip(product.subcategory.trim()),
                              if (product.defaultSellingOption != null)
                                _buildMetaChip(
                                  "Sold as ${product.defaultSellingOption!.displayLabel}",
                                ),
                              _buildMetaChip(
                                statusLabel,
                                isActive: product.isActive,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == "edit") {
                          _openProductForm(product: product);
                          return;
                        }
                        if (value == "upload") {
                          _uploadProductImage(product);
                          return;
                        }
                        if (value == "archive") {
                          _softDeleteProduct(product.id);
                          return;
                        }
                        if (value == "restore") {
                          _restoreProduct(product.id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: "edit", child: Text("Edit")),
                        const PopupMenuItem(
                          value: "upload",
                          child: Text("Upload image"),
                        ),
                        if (product.isActive)
                          const PopupMenuItem(
                            value: "archive",
                            child: Text("Archive"),
                          )
                        else
                          const PopupMenuItem(
                            value: "restore",
                            child: Text("Restore"),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _buildRecordMetric(
                        label: "Unit price",
                        value: priceLabel,
                        icon: Icons.payments_outlined,
                        accent: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildRecordMetric(
                        label: "Inventory",
                        value: "${product.stock} units",
                        icon: Icons.inventory_2_outlined,
                        accent: AppColors.productionAccent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildRecordMetric(
                        label: "Selling unit",
                        value:
                            product.defaultSellingOption?.displayLabel ??
                            "Standard",
                        icon: Icons.straighten_outlined,
                        accent: AppColors.recordsAccent,
                      ),
                    ),
                  ],
                ),
                if (galleryUrls.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: "Gallery",
                    subtitle:
                        "Additional product visuals attached to this record.",
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 54,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: galleryUrls.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final url = galleryUrls[index];
                        return _buildGalleryThumbnail(
                          url,
                          onDelete: () => _deleteProductImage(
                            product: product,
                            imageUrl: url,
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (hasPreorderSignals) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _preorderSnapshotLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            _buildMetaChip(
                              "State ${productionState.isEmpty ? "—" : productionState}",
                            ),
                            _buildMetaChip(
                              "Pre-order ${product.preorderEnabled ? "on" : "off"}",
                            ),
                            _buildMetaChip(
                              "Cap ${product.preorderCapQuantity}",
                            ),
                            _buildMetaChip(
                              "Reserved ${product.preorderReservedQuantity}",
                            ),
                            _buildMetaChip("Remaining $preorderRemaining"),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            if (hasLinkedPlan)
                              OutlinedButton.icon(
                                onPressed: () {
                                  final planId =
                                      (product.productionPlanId ?? "").trim();
                                  _logFlow(
                                    "PLAN_OPEN",
                                    "Linked plan opened from list card",
                                    extra: {
                                      "productId": product.id,
                                      "planId": planId,
                                    },
                                  );
                                  context.push(
                                    productionPlanDetailPath(planId),
                                  );
                                },
                                icon: const Icon(Icons.open_in_new),
                                label: const Text(_openPlanLabel),
                              ),
                            TextButton.icon(
                              onPressed: () => _openProductDetail(product),
                              icon: const Icon(Icons.chevron_right),
                              label: const Text(_openDetailLabel),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _primaryImageUrl(Product product) {
    final gallery = product.imageUrls;
    if (gallery.isNotEmpty) return gallery.first;
    if (product.imageUrl.isNotEmpty) return product.imageUrl;
    return null;
  }

  List<String> _galleryImageUrls(Product product, String? primary) {
    // WHY: Remove duplicates + exclude primary to avoid repeating thumbnails.
    final urls = <String>{};
    urls.addAll(product.imageUrls.where((url) => url.isNotEmpty));
    if (primary != null) {
      urls.remove(primary);
    }
    return urls.toList();
  }

  Widget _buildProductThumbnail(
    String? url, {
    double size = 72,
    VoidCallback? onDelete,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null)
              Icon(Icons.image, color: colorScheme.onSurfaceVariant)
            else
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.broken_image,
                  color: colorScheme.onSurfaceVariant,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress.expectedTotalBytes == null
                            ? null
                            : progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!,
                      ),
                    ),
                  );
                },
              ),
            if (url != null && onDelete != null)
              Positioned(
                right: 4,
                top: 4,
                child: InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      // WHY: Scrim keeps the delete icon visible on images.
                      color: colorScheme.scrim.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      // WHY: Use onSurface for consistent contrast in all modes.
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryThumbnail(String url, {VoidCallback? onDelete}) {
    // WHY: Keep small thumbs for quick scanning without overwhelming the card.
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.broken_image, color: colorScheme.onSurfaceVariant),
            ),
            if (onDelete != null)
              Positioned(
                right: 2,
                top: 2,
                child: InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colorScheme.scrim.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 10,
                      // WHY: Keep delete icon legible on scrim across themes.
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(String label, {bool? isActive}) {
    final theme = Theme.of(context);
    final tone = isActive == null
        ? AppStatusTone.neutral
        : isActive
        ? AppStatusTone.success
        : AppStatusTone.warning;
    // WHY: Use centralized badge colors so chips adapt to theme modes.
    final badge = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badge.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: badge.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStatusPill(bool isActive) {
    final label = isActive ? "Active" : "Archived";
    final theme = Theme.of(context);
    final badge = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: isActive ? AppStatusTone.success : AppStatusTone.warning,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badge.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: badge.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRecordMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow({required int productCount}) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSectionCard(
      tone: AppPanelTone.base,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showArchivedOnly
                      ? "Archived records view"
                      : "Active inventory view",
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _showArchivedOnly
                      ? "Showing archived products only for review and restoration."
                      : "Showing active products that are currently part of the live catalog.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppStatusChip(
                  label: "$productCount records visible",
                  tone: _showArchivedOnly
                      ? AppStatusTone.warning
                      : AppStatusTone.success,
                  icon: Icons.inventory_2_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Switch.adaptive(
                value: _showArchivedOnly,
                onChanged: (value) {
                  _logFlow(
                    "FILTER_TOGGLE",
                    "Archived filter toggled",
                    extra: {"archivedOnly": value},
                  );
                  setState(() => _showArchivedOnly = value);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: () => _openProductForm(),
                icon: const Icon(Icons.add),
                label: const Text("New product"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BusinessAnalyticsSummary summary, {String? helper}) {
    final metrics = [
      (
        label: "Total records",
        value: summary.totalProducts.toString(),
        helper: "All catalog items",
        icon: Icons.inventory_2_outlined,
        accent: AppColors.analyticsAccent,
      ),
      (
        label: "Active",
        value: summary.activeProducts.toString(),
        helper: "Visible in the live catalog",
        icon: Icons.verified_outlined,
        accent: AppColors.productionAccent,
      ),
      (
        label: "Stock",
        value: summary.totalStock.toString(),
        helper: "Units currently tracked",
        icon: Icons.stacked_line_chart_rounded,
        accent: AppColors.recordsAccent,
      ),
      (
        label: "Revenue",
        value: formatNgnFromCents(summary.revenueTotal),
        helper: helper ?? "Order value attached to product sales",
        icon: Icons.payments_outlined,
        accent: AppColors.commerceAccent,
      ),
    ];

    return AppSectionCard(
      tone: AppPanelTone.base,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = AppLayout.columnsForWidth(
            constraints.maxWidth,
            compact: 1,
            medium: 2,
            large: 4,
            xlarge: 4,
          );
          final spacing = AppSpacing.lg;
          final width =
              (constraints.maxWidth - (spacing * (columns - 1))) / columns;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                title: "Inventory summary",
                subtitle:
                    "Track the scale and health of the product catalog before drilling into individual records.",
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: metrics.map((metric) {
                  return SizedBox(
                    width: width,
                    child: AppMetricCard(
                      label: metric.label,
                      value: metric.value,
                      helper: metric.helper,
                      icon: metric.icon,
                      accentColor: metric.accent,
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  BusinessAnalyticsSummary _emptySummary() {
    // WHY: Keep the UI stable when analytics are still loading.
    return const BusinessAnalyticsSummary(
      totalProducts: 0,
      activeProducts: 0,
      totalStock: 0,
      totalOrders: 0,
      ordersByStatus: {},
      revenueTotal: 0,
    );
  }
}
