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
/// - Presents a form with name, description, price, stock, and image URL.
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
import 'package:frontend/app/features/home/presentation/product_ai_model.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

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
const String _missingSessionMessage = "Session expired. Please sign in again.";
const String _genericErrorMessage = "Action failed. Please try again.";
const String _aiPromptMissingMessage =
    "Describe the product you want to draft.";
const String _aiDraftAppliedMessage = "AI draft applied to the form.";
const String _aiDraftFailedMessage =
    "Unable to generate a draft. Please refine the prompt and retry.";

const String _labelName = "Name";
const String _labelDescription = "Description";
const String _labelPrice = "Price (NGN)";
const String _labelStock = "Stock";
const String _labelImage = "Image URL";
const String _labelAiPrompt = "Describe the product";
const String _labelAiSectionTitle = "AI draft";
const String _labelAiSectionHint =
    "Describe what to create. AI will draft name, description, price, stock, and image.";
const String _labelAiGenerate = "Generate AI draft";
const String _labelAiGenerating = "Drafting...";

const String _hintName = "Executive chair";
const String _hintDescription = "High-back office chair";
const String _hintPrice = "129000";
const String _hintStock = "10";
const String _hintImage = "https://example.com/item.png";
const String _hintAiPrompt =
    "Example: Premium office chair, ergonomic, NGN 120000, with 20 in stock.";

const String _payloadName = "name";
const String _payloadDescription = "description";
const String _payloadPrice = "price";
const String _payloadStock = "stock";
const String _payloadImageUrl = "imageUrl";
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

Map<String, dynamic>? _buildProductPayload({
  required TextEditingController nameCtrl,
  required TextEditingController descCtrl,
  required TextEditingController priceCtrl,
  required TextEditingController stockCtrl,
  required TextEditingController imageCtrl,
  required void Function(String message) onError,
}) {
  // WHY: Normalize input before hitting the API.
  final name = nameCtrl.text.trim();
  final description = descCtrl.text.trim();
  final price = parseNgnToKobo(priceCtrl.text.trim());
  final stock = _parseProductStock(stockCtrl.text.trim());
  final imageUrl = imageCtrl.text.trim();

  if (name.isEmpty || price == null || stock == null) {
    onError(_requiredFieldsMessage);
    return null;
  }

  return {
    _payloadName: name,
    _payloadDescription: description,
    _payloadPrice: price,
    _payloadStock: stock,
    _payloadImageUrl: imageUrl,
    _payloadIsActive: true,
  };
}

Future<Product?> showBusinessProductFormSheet({
  required BuildContext context,
  Product? product,
  ProductDraft? initialDraft,
  Future<void> Function(Product product)? onSuccess,
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
        ),
      );
    },
  );
}

class BusinessProductFormSheet extends ConsumerStatefulWidget {
  final Product? product;
  final ProductDraft? initialDraft;
  final Future<void> Function(Product product)? onSuccess;

  const BusinessProductFormSheet({
    super.key,
    this.product,
    this.initialDraft,
    this.onSuccess,
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
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  // WHY: Capture AI prompt text for product drafting.
  final _aiPromptCtrl = TextEditingController();

  // WHY: Prevent double submits for create/update actions.
  bool _isSubmitting = false;
  // WHY: Track AI draft requests separately from form submission.
  bool _isDrafting = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    // WHY: Pre-fill fields when editing an existing product.
    final product = widget.product;
    if (product != null) {
      _nameCtrl.text = product.name;
      _descCtrl.text = product.description;
      _priceCtrl.text = formatNgnInputFromKobo(product.priceCents);
      _stockCtrl.text = product.stock.toString();
      _imageCtrl.text = product.imageUrl;
      return;
    }

    // WHY: Let callers seed the sheet from AI-suggested product values.
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      _applyAiDraft(initialDraft);
    }
  }

  @override
  void dispose() {
    // WHY: Avoid memory leaks from controllers.
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _imageCtrl.dispose();
    _aiPromptCtrl.dispose();
    super.dispose();
  }

  void _applyAiDraft(ProductDraft draft) {
    // WHY: Apply AI draft values so users can edit before saving.
    _nameCtrl.text = draft.name.trim();
    _descCtrl.text = draft.description.trim();

    final priceKobo = draft.priceNgn > 0 ? draft.priceNgn * 100 : null;
    _priceCtrl.text = priceKobo == null
        ? ""
        : formatNgnInputFromKobo(priceKobo);

    _stockCtrl.text = draft.stock > 0 ? draft.stock.toString() : "";
    _imageCtrl.text = draft.imageUrl.trim();
  }

  Future<void> _draftWithAi() async {
    if (_isDrafting) return;
    // WHY: Log draft taps so AI usage is traceable.
    AppDebug.log(_logTag, _logAiDraftTap);

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (mounted) _showProductFormSnack(context, _missingSessionMessage);
      return;
    }

    final prompt = _aiPromptCtrl.text.trim();
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

      _applyAiDraft(draft);

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

    final payload = _buildProductPayload(
      nameCtrl: _nameCtrl,
      descCtrl: _descCtrl,
      priceCtrl: _priceCtrl,
      stockCtrl: _stockCtrl,
      imageCtrl: _imageCtrl,
      onError: (message) {
        if (mounted) _showProductFormSnack(context, message);
      },
    );
    if (payload == null) return;

    setState(() => _isSubmitting = true);
    AppDebug.log(_logTag, _logSubmitStart);

    try {
      final api = ref.read(businessProductApiProvider);
      final product = _isEditing
          ? await api.updateProduct(
              token: session.token,
              id: widget.product!.id,
              payload: payload,
            )
          : await api.createProduct(token: session.token, payload: payload);

      if (widget.onSuccess != null) {
        // WHY: Allow callers to refresh lists or update selections.
        await widget.onSuccess!(product);
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
        extra: {_extraProductIdKey: product.id},
      );

      if (mounted) Navigator.of(context).pop(product);
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

    return ListView(
      padding: const EdgeInsets.all(_sheetPadding),
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: _fieldSpacing),
        if (!_isEditing) ...[
          _ProductAiDraftSection(
            promptCtrl: _aiPromptCtrl,
            isDrafting: _isDrafting,
            onGenerate: _draftWithAi,
          ),
          const SizedBox(height: _fieldSpacing),
        ],
        _ProductFormFields(
          nameCtrl: _nameCtrl,
          descCtrl: _descCtrl,
          priceCtrl: _priceCtrl,
          stockCtrl: _stockCtrl,
          imageCtrl: _imageCtrl,
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
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;
  final TextEditingController imageCtrl;

  const _ProductFormFields({
    required this.nameCtrl,
    required this.descCtrl,
    required this.priceCtrl,
    required this.stockCtrl,
    required this.imageCtrl,
  });

  @override
  Widget build(BuildContext context) {
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
        _ProductFormField(
          controller: imageCtrl,
          label: _labelImage,
          hint: _hintImage,
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }
}

class _ProductAiDraftSection extends StatelessWidget {
  final TextEditingController promptCtrl;
  final bool isDrafting;
  final VoidCallback? onGenerate;

  const _ProductAiDraftSection({
    required this.promptCtrl,
    required this.isDrafting,
    required this.onGenerate,
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
              label: Text(isDrafting ? _labelAiGenerating : _labelAiGenerate),
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
