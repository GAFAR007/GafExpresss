/// lib/app/features/home/presentation/business_product_form_sheet.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Reusable bottom sheet for creating/updating business products.
///
/// WHY:
/// - Keeps product form logic consistent across screens (plans + inventory).
/// - Avoids duplicating create/update behavior in multiple widgets.
///
/// HOW:
/// - Presents a form with name, description, taxonomy, pricing, stock, and image input.
/// - Supports direct image upload plus structured selling options.
/// - Calls BusinessProductApi to create/update and returns the saved product.
/// - Logs build, submit actions, and API outcomes for diagnostics.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/business_product_selling_fields.dart';
import 'package:frontend/app/features/home/presentation/business_product_taxonomy_fields.dart';
import 'package:frontend/app/features/home/presentation/product_ai_model.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_selling_option.dart';
import 'package:frontend/app/features/home/presentation/product_taxonomy.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/settings/settings_image_picker.dart';

const String _logTag = "BUSINESS_PRODUCT_FORM";
const String _logBuild = "build()";
const String _logOpen = "form_open";
const String _logSubmitTap = "submit_tap";
const String _logSubmitStart = "submit_start";
const String _logSubmitSuccess = "submit_success";
const String _logSubmitFail = "submit_fail";
const String _logAiDraftTap = "ai_draft_tap";
const String _logAiDraftStart = "ai_draft_start";
const String _logAiDraftSuccess = "ai_draft_success";
const String _logAiDraftFail = "ai_draft_fail";
const String _logImagePickTap = "image_pick_tap";
const String _logImagePickFail = "image_pick_fail";
const String _logImageUploadStart = "image_upload_start";
const String _logImageUploadSuccess = "image_upload_success";
const String _logImageUploadFail = "image_upload_fail";

const String _extraModeKey = "mode";
const String _extraProductIdKey = "productId";
const String _extraErrorKey = "error";
const String _extraHasInitialDraftKey = "hasInitialDraft";

const String _modeCreate = "create";
const String _modeEdit = "edit";

const String _titleCreate = "Create product";
const String _titleEdit = "Edit product";
const String _submitCreate = "Create product";
const String _submitEdit = "Save changes";
const String _successCreate = "Product created successfully.";
const String _successEdit = "Product updated successfully.";
const String _requiredFieldsMessage = "Name, price, and stock are required.";
const String _requiredTaxonomyMessage =
    "Category and subcategory are required.";
const String _requiredBrandMessage = "Brand is required before saving.";
const String _requiredSellingUnitsMessage =
    "Add at least one selling option and set a default one.";
const String _requiredPositivePriceMessage =
    "Enter a price greater than zero before saving.";
const String _requiredImageMessage =
    "Upload at least one product image before saving.";
const String _invalidSellingOptionMessage =
    "Selling options need package type, quantity, and measurement unit.";
const String _missingSessionMessage = "Session expired. Please sign in again.";
const String _genericErrorMessage = "Action failed. Please try again.";
const String _aiPromptMissingMessage =
    "Describe the product you want to draft.";
const String _aiDraftAppliedMessage = "AI draft applied to the form.";
const String _aiDraftFailedMessage =
    "Unable to generate a draft. Please refine the prompt and retry.";
const String _imageSelectedMessage = "Image selected.";
const String _imagePickerFailedMessage =
    "Unable to pick an image right now. Please try again.";
const String _imageUploadFailedAfterSaveMessage =
    "Product saved, but one or more image uploads failed.";

const String _labelName = "Name";
const String _labelDescription = "Description";
const String _labelPrice = "Price (NGN)";
const String _labelStock = "Stock";
const String _labelImageSectionTitle = "Product images";
const String _labelImageSectionHint =
    "Upload one or more images from this device. Direct image URLs are no longer used here.";
const String _labelUploadImage = "Upload images";
const String _labelAddMoreImages = "Add more images";
const String _labelRemoveImage = "Remove selected image";
const String _labelSelectedImage = "Selected images";
const String _labelExistingImages = "Existing images";
const String _labelAiPrompt = "Describe the product";
const String _labelAiSectionTitle = "AI draft";
const String _labelAiSectionHint =
    "Describe what to create. AI will draft name, description, category, subcategory, brand, selling options, price, and stock.";
const String _labelAiGenerate = "Generate AI draft";
const String _labelAiRefresh = "Refresh with AI";
const String _labelAiGenerating = "Drafting...";
const String _labelContextAiSectionTitle = "AI farm draft";
const String _labelContextAiSectionHint =
    "Use the current production crop context to fill farm category details, subcategory, selling options, description, and starter pricing. Brand stays manual.";
const String _labelContextAiGenerate = "Draft with AI from current crop";
const String _labelContextAiRefresh = "Refresh from current crop";

const String _hintName = "Executive chair";
const String _hintDescription = "High-back office chair";
const String _hintPrice = "129000";
const String _hintStock = "10";
const String _hintAiPrompt =
    "Example: Adidas sandals in Footwear, sold as pair and carton, NGN 45000, stock 12, lightweight daily wear.";

const String _payloadName = "name";
const String _payloadDescription = "description";
const String _payloadCategory = "category";
const String _payloadSubcategory = "subcategory";
const String _payloadBrand = "brand";
const String _payloadSellingOptions = "sellingOptions";
const String _payloadPrice = "price";
const String _payloadStock = "stock";
const String _payloadIsActive = "isActive";

const double _sheetPadding = 16;
const double _fieldSpacing = 12;
const double _submitSpinnerSize = 16;
const double _submitSpinnerStroke = 2;
const double _aiCardPadding = 12;
const double _aiCardRadius = 12;
const double _aiSpinnerSize = 14;
const double _aiSpinnerStroke = 2;
const int _aiPromptMaxLines = 3;
const double _imagePreviewHeight = 168;
const double _imageThumbnailSize = 72;

String _pickedImageSignature(PickedImageData image) {
  return "${image.filename.trim().toLowerCase()}:${image.bytes.length}";
}

List<PickedImageData> _mergePickedImages(
  Iterable<PickedImageData> current,
  Iterable<PickedImageData> incoming,
) {
  final merged = <PickedImageData>[];
  final seen = <String>{};

  for (final image in [...current, ...incoming]) {
    final signature = _pickedImageSignature(image);
    if (seen.add(signature)) {
      merged.add(image);
    }
  }

  return merged;
}

List<String> _normalizeProductImageUrls(Product? product) {
  if (product == null) {
    return const [];
  }

  return _dedupeTextSuggestions([product.imageUrl, ...product.imageUrls]);
}

String _buildPickedImagesMessage(int count, {required bool appended}) {
  if (count <= 0) {
    return _imageSelectedMessage;
  }

  if (count == 1) {
    return appended ? "1 image added." : "1 image selected.";
  }

  return appended ? "$count images added." : "$count images selected.";
}

void _showProductFormSnack(BuildContext context, String message) {
  // WHY: Keep snack handling consistent for create/edit flows.
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

int? _parseProductStock(String value) {
  // WHY: Guard against empty or non-numeric values from text fields.
  if (value.trim().isEmpty) return null;
  return int.tryParse(value.trim());
}

String _extractProductErrorMessage(Object error) {
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
  return _genericErrorMessage;
}

String _extractAiDraftErrorMessage(Object error) {
  // WHY: Provide a draft-specific fallback without masking backend errors.
  final message = _extractProductErrorMessage(error);
  if (message == _genericErrorMessage) {
    return _aiDraftFailedMessage;
  }
  return message;
}

List<String> _dedupeTextSuggestions(Iterable<String?> values) {
  final suggestions = <String>[];
  final seen = <String>{};

  for (final value in values) {
    final trimmed = value?.trim() ?? "";
    if (trimmed.isEmpty) continue;
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      suggestions.add(trimmed);
    }
  }

  return suggestions;
}

List<ProductSellingOption> _normalizeSellingOptions(
  Iterable<ProductSellingOption> values,
) {
  return normalizeSellingOptions(values);
}

Map<String, dynamic>? _buildProductPayload({
  required TextEditingController nameCtrl,
  required TextEditingController descCtrl,
  required TextEditingController categoryCtrl,
  required TextEditingController subcategoryCtrl,
  required TextEditingController brandCtrl,
  required TextEditingController priceCtrl,
  required TextEditingController stockCtrl,
  required List<ProductSellingOption> sellingOptions,
  required bool requireBrand,
  required void Function(String message) onError,
}) {
  // WHY: Normalize input before hitting the API.
  final name = nameCtrl.text.trim();
  final description = descCtrl.text.trim();
  final category = categoryCtrl.text.trim();
  final subcategory = subcategoryCtrl.text.trim();
  final brand = brandCtrl.text.trim();
  final price = parseNgnToKobo(priceCtrl.text.trim());
  final stock = _parseProductStock(stockCtrl.text.trim());
  final normalizedSellingOptions = _normalizeSellingOptions(sellingOptions);

  if (name.isEmpty || price == null || stock == null) {
    onError(_requiredFieldsMessage);
    return null;
  }
  if (category.isEmpty || subcategory.isEmpty) {
    onError(_requiredTaxonomyMessage);
    return null;
  }
  if (requireBrand && brand.isEmpty) {
    onError(_requiredBrandMessage);
    return null;
  }
  if (normalizedSellingOptions.isEmpty ||
      !normalizedSellingOptions.any((option) => option.isDefault)) {
    onError(_requiredSellingUnitsMessage);
    return null;
  }

  return {
    _payloadName: name,
    _payloadDescription: description,
    _payloadCategory: category,
    _payloadSubcategory: subcategory,
    _payloadBrand: brand,
    _payloadSellingOptions: [
      for (final option in normalizedSellingOptions) option.toJson(),
    ],
    _payloadPrice: price,
    _payloadStock: stock,
    _payloadIsActive: true,
  };
}

Future<Product?> showBusinessProductFormSheet({
  required BuildContext context,
  Product? product,
  ProductDraft? initialDraft,
  Future<void> Function(Product product)? onSuccess,
  bool requireCompleteSetup = false,
  String? contextAiPrompt,
  String? forcedAiCategory,
  bool preserveBrandOnAiDraft = false,
}) async {
  // WHY: Log sheet opens so we can trace product creation flows.
  AppDebug.log(
    _logTag,
    _logOpen,
    extra: {
      _extraModeKey: product == null ? _modeCreate : _modeEdit,
      if (product != null) _extraProductIdKey: product.id,
      _extraHasInitialDraftKey: initialDraft != null,
    },
  );

  return showModalBottomSheet<Product?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final viewInsets = MediaQuery.of(context).viewInsets;
      return Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: BusinessProductFormSheet(
          product: product,
          initialDraft: initialDraft,
          onSuccess: onSuccess,
          requireCompleteSetup: requireCompleteSetup,
          contextAiPrompt: contextAiPrompt,
          forcedAiCategory: forcedAiCategory,
          preserveBrandOnAiDraft: preserveBrandOnAiDraft,
        ),
      );
    },
  );
}

class BusinessProductFormSheet extends ConsumerStatefulWidget {
  final Product? product;
  final ProductDraft? initialDraft;
  final Future<void> Function(Product product)? onSuccess;
  final bool requireCompleteSetup;
  final String? contextAiPrompt;
  final String? forcedAiCategory;
  final bool preserveBrandOnAiDraft;

  const BusinessProductFormSheet({
    super.key,
    this.product,
    this.initialDraft,
    this.onSuccess,
    this.requireCompleteSetup = false,
    this.contextAiPrompt,
    this.forcedAiCategory,
    this.preserveBrandOnAiDraft = false,
  });

  @override
  ConsumerState<BusinessProductFormSheet> createState() =>
      _BusinessProductFormSheetState();
}

class _BusinessProductFormSheetState
    extends ConsumerState<BusinessProductFormSheet> {
  // WHY: Controllers keep form inputs stable across rebuilds.
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _subcategoryCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _packageTypeCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: "1");
  final _measurementUnitCtrl = TextEditingController();
  // WHY: Capture AI prompt text for product drafting.
  final _aiPromptCtrl = TextEditingController();
  List<PickedImageData> _pickedImages = const [];

  // WHY: Prevent double submits for create/update actions.
  bool _isSubmitting = false;
  // WHY: Track AI draft requests separately from form submission.
  bool _isDrafting = false;
  bool _useCustomCategory = false;
  bool _useCustomSubcategory = false;
  List<ProductSellingOption> _sellingOptions = const [];

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    // WHY: Pre-fill fields when editing an existing product.
    final product = widget.product;
    if (product != null) {
      _nameCtrl.text = product.name;
      _descCtrl.text = product.description;
      _applyTaxonomy(
        category: product.category,
        subcategory: product.subcategory,
        brand: product.brand,
      );
      _priceCtrl.text = formatNgnInputFromKobo(product.priceCents);
      _stockCtrl.text = product.stock.toString();
      _applySellingOptions(product.sellingOptions);
      return;
    }

    // WHY: Let callers seed the sheet from AI-suggested product values.
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      _applyAiDraft(initialDraft);
      return;
    }

    _applyDefaultTaxonomy();
  }

  @override
  void dispose() {
    // WHY: Avoid memory leaks from controllers.
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    _subcategoryCtrl.dispose();
    _brandCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _packageTypeCtrl.dispose();
    _quantityCtrl.dispose();
    _measurementUnitCtrl.dispose();
    _aiPromptCtrl.dispose();
    super.dispose();
  }

  void _applyAiDraft(
    ProductDraft draft, {
    String? forcedCategory,
    bool preserveBrand = false,
  }) {
    // WHY: Apply AI draft values so users can edit before saving.
    _nameCtrl.text = draft.name.trim();
    _descCtrl.text = draft.description.trim();
    final normalizedForcedCategory = (forcedCategory ?? "").trim();
    _applyTaxonomy(
      category: normalizedForcedCategory.isEmpty
          ? draft.category
          : normalizedForcedCategory,
      subcategory: draft.subcategory,
      brand: preserveBrand ? draft.brand : "",
    );

    final priceKobo = draft.priceNgn > 0 ? draft.priceNgn * 100 : null;
    _priceCtrl.text = priceKobo == null
        ? ""
        : formatNgnInputFromKobo(priceKobo);

    _stockCtrl.text = draft.stock > 0 ? draft.stock.toString() : "";
    _applySellingOptions(draft.sellingOptions);
  }

  void _applyTaxonomy({
    required String category,
    required String subcategory,
    required String brand,
  }) {
    final normalizedCategory = category.trim();
    final normalizedSubcategory = subcategory.trim();
    final normalizedBrand = brand.trim();
    final matchedCategory = findProductTaxonomyCategory(normalizedCategory);
    final matchedSubcategory = findProductTaxonomySubcategory(
      categoryLabel: normalizedCategory,
      subcategoryLabel: normalizedSubcategory,
    );

    _categoryCtrl.text = normalizedCategory;
    _subcategoryCtrl.text = normalizedSubcategory;
    _brandCtrl.text = normalizedBrand;
    _useCustomCategory =
        normalizedCategory.isNotEmpty && matchedCategory == null;
    _useCustomSubcategory =
        normalizedSubcategory.isNotEmpty &&
        matchedCategory != null &&
        matchedSubcategory == null;
  }

  void _applyDefaultTaxonomy() {
    final forcedCategory = (widget.forcedAiCategory ?? "").trim();
    final matchedCategory = findProductTaxonomyCategory(
      forcedCategory.isEmpty
          ? productTaxonomyDefaultCategoryLabel
          : forcedCategory,
    );

    if (matchedCategory == null) {
      _applyTaxonomy(
        category: forcedCategory.isEmpty
            ? productTaxonomyDefaultCategoryLabel
            : forcedCategory,
        subcategory: forcedCategory.isEmpty
            ? productTaxonomyDefaultSubcategoryLabel
            : "",
        brand: "",
      );
      return;
    }

    _applyTaxonomy(
      category: matchedCategory.label,
      subcategory: matchedCategory.subcategories.isNotEmpty
          ? matchedCategory.subcategories.first.label
          : "",
      brand: "",
    );
  }

  void _applySellingOptions(List<ProductSellingOption> sellingOptions) {
    _sellingOptions = _normalizeSellingOptions(sellingOptions);
  }

  void _handleCategorySelected(String? value) {
    setState(() {
      if (value == productTaxonomyCustomValue) {
        _useCustomCategory = true;
        _categoryCtrl.clear();
        _subcategoryCtrl.clear();
        _useCustomSubcategory = false;
        return;
      }

      _useCustomCategory = false;
      _categoryCtrl.text = (value ?? "").trim();
      _useCustomSubcategory = false;

      final category = findProductTaxonomyCategory(_categoryCtrl.text);
      _subcategoryCtrl.text = category?.subcategories.isNotEmpty == true
          ? category!.subcategories.first.label
          : "";
    });
  }

  void _handleSubcategorySelected(String? value) {
    setState(() {
      if (value == productTaxonomyCustomValue) {
        _useCustomSubcategory = true;
        _subcategoryCtrl.clear();
        return;
      }

      _useCustomSubcategory = false;
      _subcategoryCtrl.text = (value ?? "").trim();
    });
  }

  Future<void> _pickImages() async {
    AppDebug.log(_logTag, _logImagePickTap);

    try {
      final picked = await pickProfileImages();
      if (picked.isEmpty) {
        return;
      }

      if (!mounted) return;
      final previousCount = _pickedImages.length;
      final nextImages = _mergePickedImages(_pickedImages, picked);
      final addedCount = nextImages.length - previousCount;

      setState(() => _pickedImages = nextImages);
      _showProductFormSnack(
        context,
        _buildPickedImagesMessage(addedCount, appended: previousCount > 0),
      );
    } catch (error) {
      AppDebug.log(
        _logTag,
        _logImagePickFail,
        extra: {_extraErrorKey: error.toString()},
      );
      if (mounted) {
        _showProductFormSnack(context, _imagePickerFailedMessage);
      }
    }
  }

  void _removePickedImage(PickedImageData image) {
    setState(() {
      _pickedImages = _pickedImages
          .where(
            (item) =>
                _pickedImageSignature(item) != _pickedImageSignature(image),
          )
          .toList();
    });
  }

  void _setSellingPackageType(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return;
    }

    final suggestions = productMeasurementUnitSuggestions(
      categoryLabel: _categoryCtrl.text,
      subcategoryLabel: _subcategoryCtrl.text,
      packageType: normalized,
    );

    setState(() {
      _packageTypeCtrl.text = normalized;
      if (_measurementUnitCtrl.text.trim().isEmpty && suggestions.isNotEmpty) {
        _measurementUnitCtrl.text = suggestions.first;
      }
      if (_quantityCtrl.text.trim().isEmpty) {
        _quantityCtrl.text = "1";
      }
    });
  }

  void _setSellingMeasurementUnit(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return;
    }

    setState(() => _measurementUnitCtrl.text = normalized);
  }

  void _addSellingOption() {
    final packageType = _packageTypeCtrl.text.trim();
    final quantity = parseSellingQuantity(_quantityCtrl.text.trim());
    final measurementUnit = _measurementUnitCtrl.text.trim();

    if (packageType.isEmpty || quantity == null || measurementUnit.isEmpty) {
      _showProductFormSnack(context, _invalidSellingOptionMessage);
      return;
    }

    final pending = ProductSellingOption(
      packageType: packageType,
      quantity: quantity,
      measurementUnit: measurementUnit,
      isDefault: _sellingOptions.isEmpty,
    );
    final previousCount = _sellingOptions.length;
    final nextOptions = _normalizeSellingOptions([..._sellingOptions, pending]);
    final added = nextOptions.length > previousCount;

    setState(() {
      _sellingOptions = nextOptions;
      _packageTypeCtrl.clear();
      _quantityCtrl.text = "1";
      _measurementUnitCtrl.clear();
    });

    if (!added) {
      _showProductFormSnack(context, "That selling option already exists.");
    }
  }

  void _removeSellingOption(ProductSellingOption option) {
    setState(() {
      final nextOptions = _sellingOptions
          .where((item) => item.signature != option.signature)
          .toList();
      _sellingOptions = _normalizeSellingOptions(nextOptions);
    });
  }

  void _setDefaultSellingOption(ProductSellingOption option) {
    setState(() {
      _sellingOptions = _normalizeSellingOptions([
        for (final item in _sellingOptions)
          item.copyWith(isDefault: item.signature == option.signature),
      ]);
    });
  }

  Future<void> _draftWithAi({
    String? promptOverride,
    String? forcedCategory,
    bool preserveBrand = false,
  }) async {
    if (_isDrafting) return;
    // WHY: Log draft taps so AI usage is traceable.
    AppDebug.log(_logTag, _logAiDraftTap);

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (mounted) _showProductFormSnack(context, _missingSessionMessage);
      return;
    }

    final prompt = (promptOverride ?? _aiPromptCtrl.text).trim();
    if (prompt.isEmpty) {
      if (mounted) _showProductFormSnack(context, _aiPromptMissingMessage);
      return;
    }

    setState(() => _isDrafting = true);
    AppDebug.log(
      _logTag,
      _logAiDraftStart,
      extra: {"promptLength": prompt.length},
    );

    try {
      final api = ref.read(businessProductApiProvider);
      final draft = await api.generateProductDraft(
        token: session.token,
        prompt: prompt,
      );

      _applyAiDraft(
        draft,
        forcedCategory: forcedCategory,
        preserveBrand: preserveBrand,
      );

      if (mounted) {
        _showProductFormSnack(context, _aiDraftAppliedMessage);
      }

      AppDebug.log(
        _logTag,
        _logAiDraftSuccess,
        extra: {"hasName": draft.name.trim().isNotEmpty},
      );
    } catch (error) {
      AppDebug.log(
        _logTag,
        _logAiDraftFail,
        extra: {_extraErrorKey: error.toString()},
      );
      if (mounted) {
        _showProductFormSnack(context, _extractAiDraftErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isDrafting = false);
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    // WHY: Log submit taps before validation to trace user actions.
    AppDebug.log(_logTag, _logSubmitTap);

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (mounted) _showProductFormSnack(context, _missingSessionMessage);
      return;
    }

    if (widget.requireCompleteSetup) {
      final price = parseNgnToKobo(_priceCtrl.text.trim());
      if (price == null || price <= 0) {
        if (mounted) {
          _showProductFormSnack(context, _requiredPositivePriceMessage);
        }
        return;
      }
      final existingProduct = widget.product;
      final hasExistingImage =
          (existingProduct?.imageUrl ?? "").trim().isNotEmpty ||
          (existingProduct?.imageUrls.any((item) => item.trim().isNotEmpty) ??
              false);
      if (_pickedImages.isEmpty && !hasExistingImage) {
        if (mounted) {
          _showProductFormSnack(context, _requiredImageMessage);
        }
        return;
      }
    }

    final payload = _buildProductPayload(
      nameCtrl: _nameCtrl,
      descCtrl: _descCtrl,
      categoryCtrl: _categoryCtrl,
      subcategoryCtrl: _subcategoryCtrl,
      brandCtrl: _brandCtrl,
      priceCtrl: _priceCtrl,
      stockCtrl: _stockCtrl,
      sellingOptions: _sellingOptions,
      requireBrand: !_isEditing,
      onError: (message) {
        if (mounted) _showProductFormSnack(context, message);
      },
    );
    if (payload == null) return;

    setState(() => _isSubmitting = true);
    AppDebug.log(_logTag, _logSubmitStart);

    try {
      final api = ref.read(businessProductApiProvider);
      final savedProduct = _isEditing
          ? await api.updateProduct(
              token: session.token,
              id: widget.product!.id,
              payload: payload,
            )
          : await api.createProduct(token: session.token, payload: payload);
      var finalProduct = savedProduct;

      final pickedImages = List<PickedImageData>.from(_pickedImages);
      for (final pickedImage in pickedImages) {
        AppDebug.log(
          _logTag,
          _logImageUploadStart,
          extra: {
            _extraProductIdKey: finalProduct.id,
            "bytes": pickedImage.bytes.length,
            "filename": pickedImage.filename,
            "totalImages": pickedImages.length,
          },
        );

        try {
          finalProduct = await api.uploadProductImage(
            token: session.token,
            id: finalProduct.id,
            bytes: pickedImage.bytes,
            filename: pickedImage.filename,
          );

          AppDebug.log(
            _logTag,
            _logImageUploadSuccess,
            extra: {
              _extraProductIdKey: finalProduct.id,
              "filename": pickedImage.filename,
            },
          );
        } catch (error) {
          AppDebug.log(
            _logTag,
            _logImageUploadFail,
            extra: {
              _extraProductIdKey: finalProduct.id,
              "filename": pickedImage.filename,
              _extraErrorKey: error.toString(),
            },
          );

          if (widget.onSuccess != null) {
            await widget.onSuccess!(finalProduct);
          }

          if (mounted) {
            _showProductFormSnack(context, _imageUploadFailedAfterSaveMessage);
            Navigator.of(context).pop(finalProduct);
          }
          return;
        }
      }

      if (widget.onSuccess != null) {
        // WHY: Allow callers to refresh lists or update selections.
        await widget.onSuccess!(finalProduct);
      }

      if (mounted) {
        _showProductFormSnack(
          context,
          _isEditing ? _successEdit : _successCreate,
        );
      }
      AppDebug.log(
        _logTag,
        _logSubmitSuccess,
        extra: {_extraProductIdKey: finalProduct.id},
      );

      if (mounted) Navigator.of(context).pop(finalProduct);
    } catch (error) {
      AppDebug.log(
        _logTag,
        _logSubmitFail,
        extra: {_extraErrorKey: error.toString()},
      );
      if (mounted) {
        _showProductFormSnack(context, _extractProductErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _logBuild);
    final theme = Theme.of(context);
    final title = _isEditing ? _titleEdit : _titleCreate;
    final submitLabel = _isEditing ? _submitEdit : _submitCreate;
    final session = ref.watch(authSessionProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final businessBrandSuggestions = _dedupeTextSuggestions([
      profile?.companyName,
      profile?.name,
      session?.user.name,
    ]);

    return ListView(
      padding: const EdgeInsets.all(_sheetPadding),
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: _fieldSpacing),
        _ProductAiDraftSection(
          promptCtrl: _aiPromptCtrl,
          isDrafting: _isDrafting,
          generateButtonLabel: _isEditing ? _labelAiRefresh : _labelAiGenerate,
          onGenerate: () =>
              _draftWithAi(preserveBrand: widget.preserveBrandOnAiDraft),
          contextTitle: _labelContextAiSectionTitle,
          contextHint: _labelContextAiSectionHint,
          contextButtonLabel: _isEditing
              ? _labelContextAiRefresh
              : _labelContextAiGenerate,
          onGenerateFromContext: (widget.contextAiPrompt ?? "").trim().isEmpty
              ? null
              : () => _draftWithAi(
                  promptOverride: widget.contextAiPrompt,
                  forcedCategory: widget.forcedAiCategory,
                  preserveBrand: widget.preserveBrandOnAiDraft,
                ),
        ),
        const SizedBox(height: _fieldSpacing),
        _ProductFormFields(
          nameCtrl: _nameCtrl,
          descCtrl: _descCtrl,
          categoryCtrl: _categoryCtrl,
          subcategoryCtrl: _subcategoryCtrl,
          brandCtrl: _brandCtrl,
          extraBrandSuggestions: businessBrandSuggestions,
          useCustomCategory: _useCustomCategory,
          useCustomSubcategory: _useCustomSubcategory,
          onCategorySelected: _handleCategorySelected,
          onSubcategorySelected: _handleSubcategorySelected,
          priceCtrl: _priceCtrl,
          stockCtrl: _stockCtrl,
          sellingOptions: _sellingOptions,
          packageTypeCtrl: _packageTypeCtrl,
          quantityCtrl: _quantityCtrl,
          measurementUnitCtrl: _measurementUnitCtrl,
          pickedImages: _pickedImages,
          existingImageUrls: _normalizeProductImageUrls(widget.product),
          onPackageTypeSuggestion: _setSellingPackageType,
          onMeasurementUnitSuggestion: _setSellingMeasurementUnit,
          onAddSellingOption: _addSellingOption,
          onSetDefaultSellingOption: _setDefaultSellingOption,
          onRemoveSellingOption: _removeSellingOption,
          onPickImages: _pickImages,
          onRemovePickedImage: _removePickedImage,
        ),
        const SizedBox(height: _fieldSpacing),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: _submitSpinnerSize,
                    height: _submitSpinnerSize,
                    child: CircularProgressIndicator(
                      strokeWidth: _submitSpinnerStroke,
                    ),
                  )
                : Text(submitLabel),
          ),
        ),
      ],
    );
  }
}

class _ProductFormFields extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController categoryCtrl;
  final TextEditingController subcategoryCtrl;
  final TextEditingController brandCtrl;
  final List<String> extraBrandSuggestions;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;
  final List<ProductSellingOption> sellingOptions;
  final TextEditingController packageTypeCtrl;
  final TextEditingController quantityCtrl;
  final TextEditingController measurementUnitCtrl;
  final List<PickedImageData> pickedImages;
  final List<String> existingImageUrls;
  final bool useCustomCategory;
  final bool useCustomSubcategory;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<String?> onSubcategorySelected;
  final ValueChanged<String> onPackageTypeSuggestion;
  final ValueChanged<String> onMeasurementUnitSuggestion;
  final VoidCallback onAddSellingOption;
  final ValueChanged<ProductSellingOption> onSetDefaultSellingOption;
  final ValueChanged<ProductSellingOption> onRemoveSellingOption;
  final VoidCallback onPickImages;
  final ValueChanged<PickedImageData> onRemovePickedImage;

  const _ProductFormFields({
    required this.nameCtrl,
    required this.descCtrl,
    required this.categoryCtrl,
    required this.subcategoryCtrl,
    required this.brandCtrl,
    required this.extraBrandSuggestions,
    required this.priceCtrl,
    required this.stockCtrl,
    required this.sellingOptions,
    required this.packageTypeCtrl,
    required this.quantityCtrl,
    required this.measurementUnitCtrl,
    required this.pickedImages,
    required this.existingImageUrls,
    required this.useCustomCategory,
    required this.useCustomSubcategory,
    required this.onCategorySelected,
    required this.onSubcategorySelected,
    required this.onPackageTypeSuggestion,
    required this.onMeasurementUnitSuggestion,
    required this.onAddSellingOption,
    required this.onSetDefaultSellingOption,
    required this.onRemoveSellingOption,
    required this.onPickImages,
    required this.onRemovePickedImage,
  });

  @override
  Widget build(BuildContext context) {
    final packageTypeSuggestions = productPackageTypeSuggestions(
      categoryLabel: categoryCtrl.text,
      subcategoryLabel: subcategoryCtrl.text,
      extraSuggestions: sellingOptions.map((option) => option.packageType),
    );
    final measurementUnitSuggestions = productMeasurementUnitSuggestions(
      categoryLabel: categoryCtrl.text,
      subcategoryLabel: subcategoryCtrl.text,
      packageType: packageTypeCtrl.text,
      extraSuggestions: sellingOptions.map((option) => option.measurementUnit),
    );

    return Column(
      children: [
        _ProductFormField(
          controller: nameCtrl,
          label: _labelName,
          hint: _hintName,
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: _fieldSpacing),
        _ProductFormField(
          controller: descCtrl,
          label: _labelDescription,
          hint: _hintDescription,
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: _fieldSpacing),
        BusinessProductTaxonomyFields(
          categoryCtrl: categoryCtrl,
          subcategoryCtrl: subcategoryCtrl,
          brandCtrl: brandCtrl,
          extraBrandSuggestions: extraBrandSuggestions,
          useCustomCategory: useCustomCategory,
          useCustomSubcategory: useCustomSubcategory,
          onCategorySelected: onCategorySelected,
          onSubcategorySelected: onSubcategorySelected,
        ),
        const SizedBox(height: _fieldSpacing),
        _ProductFormField(
          controller: priceCtrl,
          label: _labelPrice,
          hint: _hintPrice,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // WHY: Auto-format NGN values as the user types.
          inputFormatters: const [NgnInputFormatter()],
        ),
        const SizedBox(height: _fieldSpacing),
        _ProductFormField(
          controller: stockCtrl,
          label: _labelStock,
          hint: _hintStock,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: _fieldSpacing),
        BusinessProductSellingFields(
          sellingOptions: sellingOptions,
          suggestedPackageTypes: packageTypeSuggestions,
          suggestedMeasurementUnits: measurementUnitSuggestions,
          packageTypeCtrl: packageTypeCtrl,
          quantityCtrl: quantityCtrl,
          measurementUnitCtrl: measurementUnitCtrl,
          onPackageTypeSuggestion: onPackageTypeSuggestion,
          onMeasurementUnitSuggestion: onMeasurementUnitSuggestion,
          onAddOption: onAddSellingOption,
          onSetDefault: onSetDefaultSellingOption,
          onRemoveOption: onRemoveSellingOption,
        ),
        const SizedBox(height: _fieldSpacing),
        _ProductImageSection(
          pickedImages: pickedImages,
          existingImageUrls: existingImageUrls,
          onPickImages: onPickImages,
          onRemovePickedImage: onRemovePickedImage,
        ),
      ],
    );
  }
}

class _ProductImageSection extends StatelessWidget {
  final List<PickedImageData> pickedImages;
  final List<String> existingImageUrls;
  final VoidCallback onPickImages;
  final ValueChanged<PickedImageData> onRemovePickedImage;

  const _ProductImageSection({
    required this.pickedImages,
    required this.existingImageUrls,
    required this.onPickImages,
    required this.onRemovePickedImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPendingImages = pickedImages.isNotEmpty;
    final hasExistingImages = existingImageUrls.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_labelImageSectionTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          _labelImageSectionHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: _fieldSpacing),
        Container(
          width: double.infinity,
          height: _imagePreviewHeight,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_aiCardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_aiCardRadius - 1),
            child: _ProductImagePreview(
              pickedImages: pickedImages,
              existingImageUrls: existingImageUrls,
            ),
          ),
        ),
        if (hasPendingImages) ...[
          const SizedBox(height: _fieldSpacing),
          Text(
            "$_labelSelectedImage: ${pickedImages.length}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _imageThumbnailSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pickedImages.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final image = pickedImages[index];
                return _ProductThumbnailTile.memory(
                  bytes: image.bytes,
                  onRemove: () => onRemovePickedImage(image),
                );
              },
            ),
          ),
        ],
        if (hasExistingImages) ...[
          const SizedBox(height: _fieldSpacing),
          Text(
            "$_labelExistingImages: ${existingImageUrls.length}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _imageThumbnailSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: existingImageUrls.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final imageUrl = existingImageUrls[index];
                return _ProductThumbnailTile.network(imageUrl: imageUrl);
              },
            ),
          ),
        ],
        const SizedBox(height: _fieldSpacing),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPickImages,
            icon: const Icon(Icons.upload_file),
            label: Text(
              hasPendingImages || hasExistingImages
                  ? _labelAddMoreImages
                  : _labelUploadImage,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductImagePreview extends StatelessWidget {
  final List<PickedImageData> pickedImages;
  final List<String> existingImageUrls;

  const _ProductImagePreview({
    required this.pickedImages,
    required this.existingImageUrls,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalImages = pickedImages.length + existingImageUrls.length;

    if (pickedImages.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            Uint8List.fromList(pickedImages.first.bytes),
            fit: BoxFit.cover,
          ),
          if (totalImages > 1) _ProductImageCountBadge(count: totalImages),
        ],
      );
    }

    if (existingImageUrls.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            existingImageUrls.first,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stackTrace) =>
                _buildEmptyState(colorScheme: colorScheme),
          ),
          if (totalImages > 1) _ProductImageCountBadge(count: totalImages),
        ],
      );
    }

    return _buildEmptyState(colorScheme: colorScheme);
  }

  Widget _buildEmptyState({required ColorScheme colorScheme}) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProductImageCountBadge extends StatelessWidget {
  final int count;

  const _ProductImageCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      top: 12,
      right: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.scrim.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            "$count images",
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductThumbnailTile extends StatelessWidget {
  final List<int>? bytes;
  final String? imageUrl;
  final VoidCallback? onRemove;

  const _ProductThumbnailTile.memory({required this.bytes, this.onRemove})
    : imageUrl = null;

  const _ProductThumbnailTile.network({required this.imageUrl})
    : bytes = null,
      onRemove = null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _imageThumbnailSize,
      height: _imageThumbnailSize,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.expand(
                child: bytes != null
                    ? Image.memory(
                        Uint8List.fromList(bytes!),
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.image_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: Tooltip(
                message: _labelRemoveImage,
                child: Material(
                  color: colorScheme.scrim.withValues(alpha: 0.7),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onRemove,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductAiDraftSection extends StatelessWidget {
  final TextEditingController promptCtrl;
  final bool isDrafting;
  final String generateButtonLabel;
  final VoidCallback? onGenerate;
  final String? contextTitle;
  final String? contextHint;
  final String? contextButtonLabel;
  final VoidCallback? onGenerateFromContext;

  const _ProductAiDraftSection({
    required this.promptCtrl,
    required this.isDrafting,
    required this.generateButtonLabel,
    required this.onGenerate,
    this.contextTitle,
    this.contextHint,
    this.contextButtonLabel,
    this.onGenerateFromContext,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep AI draft helpers visually grouped before manual fields.
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(_aiCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_aiCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onGenerateFromContext != null) ...[
            Text(
              contextTitle ?? _labelContextAiSectionTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: _fieldSpacing),
            Text(
              contextHint ?? _labelContextAiSectionHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isDrafting ? null : onGenerateFromContext,
                icon: isDrafting
                    ? const SizedBox(
                        width: _aiSpinnerSize,
                        height: _aiSpinnerSize,
                        child: CircularProgressIndicator(
                          strokeWidth: _aiSpinnerStroke,
                        ),
                      )
                    : const Icon(Icons.agriculture_outlined),
                label: Text(
                  isDrafting
                      ? _labelAiGenerating
                      : (contextButtonLabel ?? _labelContextAiGenerate),
                ),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: _fieldSpacing),
          ],
          Text(_labelAiSectionTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: _fieldSpacing),
          Text(
            _labelAiSectionHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _fieldSpacing),
          TextField(
            controller: promptCtrl,
            maxLines: _aiPromptMaxLines,
            decoration: const InputDecoration(
              labelText: _labelAiPrompt,
              hintText: _hintAiPrompt,
            ),
          ),
          const SizedBox(height: _fieldSpacing),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isDrafting ? null : onGenerate,
              icon: isDrafting
                  ? const SizedBox(
                      width: _aiSpinnerSize,
                      height: _aiSpinnerSize,
                      child: CircularProgressIndicator(
                        strokeWidth: _aiSpinnerStroke,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                isDrafting ? _labelAiGenerating : generateButtonLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _ProductFormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep form field styling consistent across product forms.
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}
