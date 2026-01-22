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
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/business_analytics_models.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/settings/settings_image_picker.dart';

class BusinessProductsScreen extends ConsumerStatefulWidget {
  const BusinessProductsScreen({super.key});

  @override
  ConsumerState<BusinessProductsScreen> createState() =>
      _BusinessProductsScreenState();
}

class _BusinessProductsScreenState
    extends ConsumerState<BusinessProductsScreen> {
  // WHY: Track filter state to show active vs archived items.
  bool _showArchivedOnly = false;
  // WHY: Prevent double submits for create/update actions.
  bool _isSubmitting = false;
  // WHY: Prevent concurrent product image uploads.
  bool _isUploadingImage = false;
  // WHY: Prevent overlapping image deletes on the same screen.
  bool _isDeletingImage = false;

  // WHY: Controllers keep form inputs stable across rebuilds.
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();

  @override
  void dispose() {
    // WHY: Avoid memory leaks from controllers.
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

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
    ref.invalidate(businessProductsProvider(_buildQuery()));
  }

  Future<void> _openProductForm({Product? product}) async {
    // WHY: Use one form for both create and edit to keep UX consistent.
    final isEditing = product != null;

    _nameCtrl.text = isEditing ? product.name : '';
    _descCtrl.text = isEditing ? product.description : '';
    _priceCtrl.text = isEditing ? product.priceCents.toString() : '';
    _stockCtrl.text = isEditing ? product.stock.toString() : '';
    _imageCtrl.text = isEditing ? product.imageUrl : '';

    _logFlow(
      "FORM_OPEN",
      isEditing ? "Edit product" : "Create product",
      extra: {"id": product?.id},
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                isEditing ? "Edit product" : "Create product",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
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
              _buildTextField(
                controller: _imageCtrl,
                label: "Image URL",
                hint: "https://example.com/item.png",
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          if (isEditing) {
                            await _updateProduct(product.id);
                          } else {
                            await _createProduct();
                          }

                          if (!mounted) return;
                          Navigator.of(context).pop();
                        },
                  child: Text(isEditing ? "Save changes" : "Create product"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createProduct() async {
    if (_isSubmitting) return;

    _logFlow("CREATE_TAP", "Create product tapped");

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _logFlow("CREATE_BLOCK", "Missing session");
      _showSnack("Session expired. Please sign in again.");
      return;
    }

    final name = _nameCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final price = _parseInt(_priceCtrl.text.trim());
    final stock = _parseInt(_stockCtrl.text.trim());
    final imageUrl = _imageCtrl.text.trim();

    if (name.isEmpty || price == null || stock == null) {
      _showSnack("Name, price, and stock are required.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(businessProductApiProvider);
      _logFlow("CREATE_REQUEST", "Creating product");
      await api.createProduct(
        token: session.token,
        payload: {
          "name": name,
          "description": description,
          "price": price,
          "stock": stock,
          "imageUrl": imageUrl,
          "isActive": true,
        },
      );
      await _refreshProducts();
      _showSnack("Product created successfully.");
    } catch (e) {
      _logFlow(
        "CREATE_FAIL",
        "Create product failed",
        extra: {"error": e.toString()},
      );
      _showSnack(_extractErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _updateProduct(String id) async {
    if (_isSubmitting) return;

    _logFlow("UPDATE_TAP", "Update product tapped", extra: {"id": id});

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _logFlow("UPDATE_BLOCK", "Missing session");
      _showSnack("Session expired. Please sign in again.");
      return;
    }

    final payload = <String, dynamic>{};

    final name = _nameCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final price = _parseInt(_priceCtrl.text.trim());
    final stock = _parseInt(_stockCtrl.text.trim());
    final imageUrl = _imageCtrl.text.trim();

    if (name.isNotEmpty) payload["name"] = name;
    if (description.isNotEmpty) payload["description"] = description;
    if (price != null) payload["price"] = price;
    if (stock != null) payload["stock"] = stock;
    if (imageUrl.isNotEmpty) payload["imageUrl"] = imageUrl;

    if (payload.isEmpty) {
      _showSnack("No changes to save.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(businessProductApiProvider);
      _logFlow("UPDATE_REQUEST", "Updating product", extra: {"id": id});
      await api.updateProduct(token: session.token, id: id, payload: payload);
      await _refreshProducts();
      _showSnack("Product updated successfully.");
    } catch (e) {
      _logFlow(
        "UPDATE_FAIL",
        "Update product failed",
        extra: {"error": e.toString()},
      );
      _showSnack(_extractErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
    final picked = await pickProfileImage();
    if (picked == null) {
      _logFlow("IMAGE_UPLOAD_CANCEL", "User cancelled image picker");
      return;
    }

    setState(() => _isUploadingImage = true);

    try {
      final api = ref.read(businessProductApiProvider);
      _logFlow(
        "IMAGE_UPLOAD_REQUEST",
        "Uploading product image",
        extra: {"bytes": picked.bytes.length, "filename": picked.filename},
      );

      await api.uploadProductImage(
        token: session.token,
        id: product.id,
        bytes: picked.bytes,
        filename: picked.filename,
      );

      await _refreshProducts();
      _showSnack("Image uploaded successfully.");
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

  int? _parseInt(String value) {
    // WHY: Guard against empty or non-numeric values from text fields.
    if (value.trim().isEmpty) return null;
    return int.tryParse(value.trim());
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_PRODUCTS", "build()");

    final productsAsync = ref.watch(businessProductsProvider(_buildQuery()));
    final summaryAsync = ref.watch(businessAnalyticsSummaryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EF),
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
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  "Inventory overview",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Track items, stock, and updates across your catalog.",
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                summaryCard,
                const SizedBox(height: 16),
                _buildFilterRow(),
                const SizedBox(height: 12),
                if (products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text("No products found.")),
                  )
                else
                  Column(
                    children: products
                        .map((product) => _buildProductCard(product))
                        .toList(),
                  ),
              ],
            );
          },
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              SizedBox(height: 120),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 120),
              Center(child: Text(_extractErrorMessage(error))),
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
        context.go('/settings');
        return;
    }
  }

  void _openProductDetail(Product product) {
    _logFlow("DETAIL_OPEN", "Product tapped", extra: {"id": product.id});
    context.go('/business-products/${product.id}');
  }

  Widget _buildProductCard(Product product) {
    // WHY: Prefer the first gallery item so the list reflects latest uploads.
    final primaryImage = _primaryImageUrl(product);
    final galleryUrls = _galleryImageUrls(product, primaryImage);
    final priceLabel = "NGN ${product.priceCents}";
    final statusLabel = product.isActive ? "Active" : "Archived";

    return InkWell(
      onTap: () => _openProductDetail(product),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7E0D6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProductThumbnail(
                  primaryImage,
                  onDelete: primaryImage == null
                      ? null
                      : () => _deleteProductImage(
                            product: product,
                            imageUrl: primaryImage,
                          ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (product.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          product.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildMetaChip(priceLabel),
                          _buildMetaChip("Stock ${product.stock}"),
                          _buildMetaChip(
                            statusLabel,
                            isActive: product.isActive,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
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
                    const SizedBox(height: 6),
                    _buildStatusPill(product.isActive),
                  ],
                ),
              ],
            ),
            if (galleryUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                "Gallery",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: galleryUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
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
            ],
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

  Widget _buildProductThumbnail(String? url, {VoidCallback? onDelete}) {
    // WHY: Keep a consistent square frame so the list stays aligned.
    return Container(
      height: 72,
      width: 72,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null)
              Icon(Icons.image, color: Colors.grey.shade400)
            else
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.broken_image,
                  color: Colors.grey.shade400,
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
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
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
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image,
                color: Colors.grey.shade400,
              ),
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
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 10,
                      color: Colors.white,
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
    final color = isActive == null
        ? Colors.blueGrey.shade50
        : isActive
            ? Colors.green.shade50
            : Colors.orange.shade50;
    final textColor = isActive == null
        ? Colors.blueGrey.shade700
        : isActive
            ? Colors.green.shade700
            : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildStatusPill(bool isActive) {
    final label = isActive ? "Active" : "Archived";
    final color = isActive ? Colors.green.shade50 : Colors.orange.shade50;
    final textColor = isActive ? Colors.green.shade700 : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E0D6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Archived view",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Show inactive items only",
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
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
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BusinessAnalyticsSummary summary, {
    String? helper,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E0D6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helper != null && helper.trim().isNotEmpty) ...[
            Text(
              helper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _buildStatBubble("Total", summary.totalProducts.toString()),
              const SizedBox(width: 10),
              _buildStatBubble("Active", summary.activeProducts.toString()),
              const SizedBox(width: 10),
              _buildStatBubble("Stock", summary.totalStock.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBubble(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
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
