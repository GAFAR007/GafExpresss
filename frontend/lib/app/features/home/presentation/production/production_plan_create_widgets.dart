/// lib/app/features/home/presentation/production/production_plan_create_widgets.dart
/// -----------------------------------------------------------------------------
/// WHAT:
/// - Widgets for production plan creation (form + phase/task editors).
///
/// WHY:
/// - Keeps the create screen under size limits.
/// - Encapsulates reusable form pieces with clear responsibilities.
///
/// HOW:
/// - Uses ProductionPlanDraftController for state updates.
/// - Pulls assets/products/staff from providers.
/// - Logs user actions (adds/removes/submits).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_asset_api.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_product_form_sheet.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/product_ai_model.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_task_table.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';

const String _logTag = "PRODUCTION_CREATE_FORM";
const String _submitAction = "submit_plan";
const String _submitSuccess = "submit_success";
const String _submitFailure = "submit_failure";
const String _addTaskAction = "add_task";
const String _removeTaskAction = "remove_task";
const String _createProductAction = "create_product_tap";
const String _createProductSuccess = "create_product_success";
const String _createProductCancel = "create_product_cancel";
const String _aiDraftAction = "ai_draft_tap";
const String _aiDraftSuccess = "ai_draft_success";
const String _aiDraftFailure = "ai_draft_failure";
const String _aiDraftMissing = "ai_draft_missing_fields";
const String _aiSuggestedProductCreateTap = "ai_suggested_product_create_tap";
const String _aiSuggestedProductCreated = "ai_suggested_product_created";
const String _validationFailure = "validation_failed";
const String _extraErrorKey = "error";
const String _extraProductKey = "productId";
const String _extraPhaseKey = "phase";
const String _extraTaskIdKey = "taskId";
const String _extraHasPromptKey = "hasPrompt";
const String _extraPromptLengthKey = "promptLength";
const String _extraClassificationKey = "classification";
const String _extraErrorCodeKey = "errorCode";
const String _extraRetryAllowedKey = "retryAllowed";
const String _extraRetryReasonKey = "retryReason";

const String _titleLabel = "Plan title";
const String _notesLabel = "Notes";
const String _notesHint = "Optional notes for this plan";
const String _estateLabel = "Estate";
const String _productLabel = "Product";
const String _createProductLabel = "Create product";
const String _createProductHint = "Add a new product for this plan.";
const String _startDateLabel = "Start date";
const String _endDateLabel = "End date";
const String _aiDraftLabel = "AI-generated draft";
const String _aiDraftHelper = "Mark if this plan started as an AI draft.";
const String _aiDraftButtonLabel = "Generate AI draft";
const String _aiAssistantPromptLabel = "AI assistant brief";
const String _aiAssistantPromptHint =
    "Add constraints, priorities, staffing notes, or risks for this draft.";
const String _aiSummaryLabel = "AI draft summary";
const String _aiSummaryTasksLabel = "Tasks";
const String _aiSummaryDaysLabel = "Estimated days";
const String _aiSummaryRisksLabel = "Risk notes";
const String _aiSummaryNoRisks = "No risks flagged";
const String _aiDraftMissingFields =
    "We need a little more context to tailor this plan to your estate. Select an estate to continue.";
const String _aiDraftSuccessMessage = "AI draft applied.";
const String _aiDraftFailureMessage = "Unable to generate AI draft.";
const String _aiDraftErrorTitle = "AI draft could not be applied";
const String _aiDraftErrorDetailsLabel = "Show details";
const String _aiDraftErrorDetailsHideLabel = "Hide details";
const String _aiDraftRetryLabel = "Retry";
const String _aiDraftSuccessInlineMessage =
    "AI draft ready. Review and adjust tasks.";
const String _aiSuggestedTag = "AI suggested";
const String _aiSuggestedDateHint = "AI suggested date. You can edit this.";
const String _aiSuggestedProductTitle = "AI suggested product draft";
const String _aiSuggestedProductHint =
    "Create this product now or choose an existing product from the list.";
const String _aiSuggestedCreateProductLabel = "Create suggested product";
const String _aiSuggestedProductAppliedMessage =
    "Suggested product created and selected.";
const String _submitLabel = "Create plan";
const String _selectPlaceholder = "Select";
const String _submitError = "Unable to create plan.";
const String _submitSuccessMessage = "Plan created successfully.";
const String _assetTypeEstate = "estate";
// WHY: Keep AI draft payload keys centralized.
const String _draftPayloadEstateId = "estateAssetId";
const String _draftPayloadProductId = "productId";
const String _draftPayloadStartDate = "startDate";
const String _draftPayloadEndDate = "endDate";
const String _draftPayloadPrompt = "prompt";

const double _pagePadding = 16;
const double _sectionSpacing = 16;
const double _fieldSpacing = 12;
const double _submitSpinnerSize = 16;
const double _submitSpinnerStroke = 2;

const int _notesMaxLines = 3;
const int _queryPage = 1;
const int _queryLimit = 50;

enum _AiDraftUiState { idle, generating, success, error }

class ProductionPlanCreateBody extends ConsumerStatefulWidget {
  const ProductionPlanCreateBody({super.key});

  @override
  ConsumerState<ProductionPlanCreateBody> createState() =>
      _ProductionPlanCreateBodyState();
}

class _ProductionPlanCreateBodyState
    extends ConsumerState<ProductionPlanCreateBody> {
  bool _isSubmitting = false;

  Future<void> _submitPlan() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
    });

    final controller = ref.read(productionPlanDraftProvider.notifier);
    // WHY: Block submission until required fields + tasks are ready.
    final errors = controller.validate();
    if (errors.isNotEmpty) {
      AppDebug.log(
        _logTag,
        _validationFailure,
        extra: {_extraErrorKey: errors.first},
      );
      _showSnack(errors.first);
      setState(() {
        _isSubmitting = false;
      });
      return;
    }

    // WHY: Log submission intent before API call.
    AppDebug.log(_logTag, _submitAction);
    try {
      final detail = await ref
          .read(productionPlanActionsProvider)
          .createPlan(payload: controller.toPayload());
      controller.reset();
      if (mounted) {
        _showSnack(_submitSuccessMessage);
        context.go(productionPlanDetailPath(detail.plan.id));
      }
      AppDebug.log(_logTag, _submitSuccess);
    } catch (err) {
      AppDebug.log(
        _logTag,
        _submitFailure,
        extra: {_extraErrorKey: err.toString()},
      );
      if (mounted) {
        _showSnack(_submitError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(productionPlanDraftProvider);
    // WHY: Fetch estates and products to populate selectors.
    final assetsAsync = ref.watch(
      businessAssetsProvider(
        const BusinessAssetsQuery(page: _queryPage, limit: _queryLimit),
      ),
    );
    final productsAsync = ref.watch(
      businessProductsProvider(
        const BusinessProductsQuery(page: _queryPage, limit: _queryLimit),
      ),
    );
    // WHY: Staff list is required for task assignments.
    final staffAsync = ref.watch(productionStaffProvider);

    final staffList = staffAsync.valueOrNull ?? [];

    return ListView(
      padding: const EdgeInsets.all(_pagePadding),
      children: [
        _PlanBasicsSection(draft: draft),
        const SizedBox(height: _sectionSpacing),
        _PlanSelectorsSection(
          draft: draft,
          assetsAsync: assetsAsync,
          productsAsync: productsAsync,
        ),
        const SizedBox(height: _sectionSpacing),
        _PlanDatesSection(draft: draft),
        const SizedBox(height: _sectionSpacing),
        _PlanAiSection(draft: draft),
        const SizedBox(height: _sectionSpacing),
        ProductionPlanTaskTable(
          draft: draft,
          staff: staffList,
          onAddTask: (phaseIndex) {
            final phaseName = draft.phases[phaseIndex].name;
            AppDebug.log(
              _logTag,
              _addTaskAction,
              extra: {_extraPhaseKey: phaseName},
            );
            ref.read(productionPlanDraftProvider.notifier).addTask(phaseIndex);
          },
          onRemoveTask: (phaseIndex, taskId) {
            final phaseName = draft.phases[phaseIndex].name;
            AppDebug.log(
              _logTag,
              _removeTaskAction,
              extra: {_extraPhaseKey: phaseName, _extraTaskIdKey: taskId},
            );
            ref
                .read(productionPlanDraftProvider.notifier)
                .removeTask(phaseIndex, taskId);
          },
        ),
        const SizedBox(height: _sectionSpacing),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submitPlan,
          icon: _isSubmitting
              ? const SizedBox(
                  width: _submitSpinnerSize,
                  height: _submitSpinnerSize,
                  child: CircularProgressIndicator(
                    strokeWidth: _submitSpinnerStroke,
                  ),
                )
              : const Icon(Icons.save),
          label: const Text(_submitLabel),
        ),
      ],
    );
  }
}

class _PlanBasicsSection extends ConsumerWidget {
  final ProductionPlanDraftState draft;

  const _PlanBasicsSection({required this.draft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(productionPlanDraftProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: draft.title,
          decoration: const InputDecoration(labelText: _titleLabel),
          onChanged: controller.updateTitle,
        ),
        const SizedBox(height: _fieldSpacing),
        TextFormField(
          initialValue: draft.notes,
          decoration: const InputDecoration(
            labelText: _notesLabel,
            hintText: _notesHint,
          ),
          maxLines: _notesMaxLines,
          onChanged: controller.updateNotes,
        ),
      ],
    );
  }
}

class _PlanSelectorsSection extends ConsumerWidget {
  final ProductionPlanDraftState draft;
  final AsyncValue<BusinessAssetsResult> assetsAsync;
  final AsyncValue<List<Product>> productsAsync;

  const _PlanSelectorsSection({
    required this.draft,
    required this.assetsAsync,
    required this.productsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(productionPlanDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        assetsAsync.when(
          data: (result) {
            final estates = result.assets
                .where((asset) => asset.assetType == _assetTypeEstate)
                .toList();
            final selectedEstateId =
                estates.any((asset) => asset.id == draft.estateAssetId)
                ? draft.estateAssetId
                : null;
            return DropdownButtonFormField<String>(
              initialValue: selectedEstateId,
              decoration: const InputDecoration(labelText: _estateLabel),
              hint: const Text(_selectPlaceholder),
              items: estates
                  .map(
                    (asset) => DropdownMenuItem(
                      value: asset.id,
                      child: Text(asset.name),
                    ),
                  )
                  .toList(),
              onChanged: controller.updateEstate,
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text(err.toString()),
        ),
        const SizedBox(height: _fieldSpacing),
        productsAsync.when(
          data: (products) {
            final selectedProductId =
                products.any((product) => product.id == draft.productId)
                ? draft.productId
                : null;
            final suggestedProduct = selectedProductId == null
                ? draft.proposedProduct
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProductId,
                  decoration: const InputDecoration(labelText: _productLabel),
                  hint: const Text(_selectPlaceholder),
                  items: products
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.id,
                          child: Text(product.name),
                        ),
                      )
                      .toList(),
                  onChanged: controller.updateProduct,
                ),
                if (draft.productAiSuggested && suggestedProduct != null) ...[
                  const SizedBox(height: _fieldSpacing),
                  _AiSuggestedProductCard(
                    draft: suggestedProduct,
                    onCreate: () async {
                      AppDebug.log(_logTag, _aiSuggestedProductCreateTap);
                      final created = await showBusinessProductFormSheet(
                        context: context,
                        initialDraft: suggestedProduct,
                        onSuccess: (_) async {
                          // WHY: Refresh list so the newly created product is selectable.
                          ref.invalidate(
                            businessProductsProvider(
                              const BusinessProductsQuery(
                                page: _queryPage,
                                limit: _queryLimit,
                              ),
                            ),
                          );
                        },
                      );

                      if (created == null) {
                        return;
                      }

                      // WHY: Selecting created product clears AI suggestion mode.
                      controller.updateProduct(created.id);
                      AppDebug.log(
                        _logTag,
                        _aiSuggestedProductCreated,
                        extra: {_extraProductKey: created.id},
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(_aiSuggestedProductAppliedMessage),
                          ),
                        );
                      }
                    },
                  ),
                ],
                const SizedBox(height: _fieldSpacing),
                // WHY: Let users add a product without leaving the plan flow.
                TextButton.icon(
                  onPressed: () async {
                    AppDebug.log(_logTag, _createProductAction);
                    final created = await showBusinessProductFormSheet(
                      context: context,
                      onSuccess: (_) async {
                        // WHY: Refresh list so the new product appears in the dropdown.
                        ref.invalidate(
                          businessProductsProvider(
                            const BusinessProductsQuery(
                              page: _queryPage,
                              limit: _queryLimit,
                            ),
                          ),
                        );
                      },
                    );

                    if (created == null) {
                      AppDebug.log(_logTag, _createProductCancel);
                      return;
                    }

                    // WHY: Auto-select newly created product for the plan.
                    controller.updateProduct(created.id);
                    AppDebug.log(
                      _logTag,
                      _createProductSuccess,
                      extra: {_extraProductKey: created.id},
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text(_createProductLabel),
                ),
                Text(
                  _createProductHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text(err.toString()),
        ),
      ],
    );
  }
}

class _PlanDatesSection extends ConsumerWidget {
  final ProductionPlanDraftState draft;

  const _PlanDatesSection({required this.draft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(productionPlanDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateField(
          label: _startDateLabel,
          value: draft.startDate,
          aiSuggested: draft.startDateAiSuggested,
          onSelected: controller.updateStartDate,
        ),
        const SizedBox(height: _fieldSpacing),
        _DateField(
          label: _endDateLabel,
          value: draft.endDate,
          aiSuggested: draft.endDateAiSuggested,
          onSelected: controller.updateEndDate,
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool aiSuggested;
  final ValueChanged<DateTime?> onSelected;

  const _DateField({
    required this.label,
    required this.value,
    required this.aiSuggested,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            // WHY: Use a date picker to prevent invalid date input.
            final now = DateTime.now();
            final initial = value ?? now;
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(kDatePickerFirstYear),
              lastDate: DateTime(kDatePickerLastYear),
              initialDate: initial,
            );
            if (picked != null) {
              onSelected(picked);
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: Text(
              value == null ? _selectPlaceholder : formatDateLabel(value),
            ),
          ),
        ),
        if (aiSuggested) ...[
          const SizedBox(height: 6),
          const _AiSuggestedHint(message: _aiSuggestedDateHint),
        ],
      ],
    );
  }
}

class _AiSuggestedProductCard extends StatelessWidget {
  final ProductDraft draft;
  final VoidCallback onCreate;

  const _AiSuggestedProductCard({required this.draft, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_fieldSpacing),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AiSuggestedHint(message: _aiSuggestedTag),
          const SizedBox(height: 8),
          Text(
            _aiSuggestedProductTitle,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(draft.name, style: textTheme.bodyMedium),
          if (draft.description.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              draft.description,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                "Price: NGN ${draft.priceNgn}",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                "Stock: ${draft.stock}",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _aiSuggestedProductHint,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_box_outlined),
            label: const Text(_aiSuggestedCreateProductLabel),
          ),
        ],
      ),
    );
  }
}

class _AiSuggestedHint extends StatelessWidget {
  final String message;

  const _AiSuggestedHint({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        message,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PlanAiSection extends ConsumerStatefulWidget {
  final ProductionPlanDraftState draft;

  const _PlanAiSection({required this.draft});

  @override
  ConsumerState<_PlanAiSection> createState() => _PlanAiSectionState();
}

class _PlanAiSectionState extends ConsumerState<_PlanAiSection> {
  _AiDraftUiState _uiState = _AiDraftUiState.idle;
  ProductionAiDraftError? _lastError;
  bool _showErrorDetails = false;
  // WHY: Prompt lets users steer AI output with operational context.
  final TextEditingController _assistantPromptCtrl = TextEditingController();

  @override
  void dispose() {
    _assistantPromptCtrl.dispose();
    super.dispose();
  }

  bool get _hasRequiredFields {
    // WHY: Intent-first draft generation only requires estate anchoring context.
    return widget.draft.estateAssetId != null &&
        widget.draft.estateAssetId!.trim().isNotEmpty;
  }

  Future<void> _generateDraft() async {
    if (_uiState == _AiDraftUiState.generating) return;
    if (!_hasRequiredFields) {
      final missingFieldsError = ProductionAiDraftError(
        message: _aiDraftMissingFields,
        classification: "MISSING_REQUIRED_FIELD",
        errorCode: "PRODUCTION_AI_CONTEXT_REQUIRED",
        resolutionHint: "Select the estate to anchor this draft, then retry.",
        details: const <String, dynamic>{
          "missing": [_draftPayloadEstateId],
          "invalid": [],
        },
        retryAllowed: true,
        retryReason: "missing_required_context",
        statusCode: 400,
      );
      // WHY: Prevent unnecessary AI calls when required fields are missing.
      AppDebug.log(
        _logTag,
        _aiDraftMissing,
        extra: {
          _extraErrorKey: missingFieldsError.message,
          _extraClassificationKey: missingFieldsError.classification,
          _extraErrorCodeKey: missingFieldsError.errorCode,
        },
      );
      if (mounted) {
        setState(() {
          _uiState = _AiDraftUiState.error;
          _lastError = missingFieldsError;
          _showErrorDetails = false;
        });
      }
      return;
    }

    setState(() {
      // WHY: Keep state explicit to drive loading/success/error UI.
      _uiState = _AiDraftUiState.generating;
      _lastError = null;
      _showErrorDetails = false;
    });

    // WHY: Log the generation tap for UX analytics.
    final prompt = _assistantPromptCtrl.text.trim();
    AppDebug.log(
      _logTag,
      _aiDraftAction,
      extra: {
        _extraHasPromptKey: prompt.isNotEmpty,
        _extraPromptLengthKey: prompt.length,
      },
    );
    try {
      final payload = {
        _draftPayloadEstateId: widget.draft.estateAssetId,
        _draftPayloadProductId: widget.draft.productId,
        _draftPayloadStartDate: widget.draft.startDate?.toIso8601String(),
        _draftPayloadEndDate: widget.draft.endDate?.toIso8601String(),
        _draftPayloadPrompt: prompt,
      };
      // WHY: Call backend AI draft endpoint and apply to local draft state.
      final draftState = await ref
          .read(productionPlanActionsProvider)
          .generateAiDraft(payload: payload);
      ref.read(productionPlanDraftProvider.notifier).applyDraft(draftState);
      // WHY: Mark success so the user knows the draft updated.
      AppDebug.log(_logTag, _aiDraftSuccess);
      if (mounted) {
        setState(() {
          _uiState = _AiDraftUiState.success;
          _lastError = null;
          _showErrorDetails = false;
        });
        _showSnack(_aiDraftSuccessMessage);
      }
    } catch (err) {
      final mappedError = _toAiDraftError(err);
      // WHY: Log failures with details to debug AI draft generation.
      AppDebug.log(
        _logTag,
        _aiDraftFailure,
        extra: {
          _extraErrorKey: mappedError.message,
          _extraClassificationKey: mappedError.classification,
          _extraErrorCodeKey: mappedError.errorCode,
          _extraRetryAllowedKey: mappedError.retryAllowed,
          _extraRetryReasonKey: mappedError.retryReason,
        },
      );
      if (mounted) {
        setState(() {
          _uiState = _AiDraftUiState.error;
          _lastError = mappedError;
          _showErrorDetails = false;
        });
        _showSnack(_aiDraftFailureMessage);
      }
    } finally {
      if (mounted) {
        // WHY: No-op; state transitions are explicit in success/error branches.
      }
    }
  }

  void _showSnack(String message) {
    // WHY: Snackbars provide lightweight feedback for async actions.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final isGenerating = _uiState == _AiDraftUiState.generating;
    final summaryValues = [
      (label: _aiSummaryTasksLabel, value: widget.draft.totalTasks.toString()),
      (
        label: _aiSummaryDaysLabel,
        value: widget.draft.totalEstimatedDays.toString(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHY: Keeps AI attribution visible for manual edits.
        SwitchListTile(
          value: widget.draft.aiGenerated,
          onChanged: controller.updateAiGenerated,
          title: const Text(_aiDraftLabel),
          subtitle: const Text(_aiDraftHelper),
        ),
        const SizedBox(height: _fieldSpacing),
        TextField(
          controller: _assistantPromptCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: _aiAssistantPromptLabel,
            hintText: _aiAssistantPromptHint,
          ),
        ),
        const SizedBox(height: _fieldSpacing),
        // WHY: Button triggers AI draft generation for faster setup.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isGenerating ? null : _generateDraft,
            icon: isGenerating
                ? const SizedBox(
                    width: _submitSpinnerSize,
                    height: _submitSpinnerSize,
                    child: CircularProgressIndicator(
                      strokeWidth: _submitSpinnerStroke,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_aiDraftButtonLabel),
          ),
        ),
        if (_uiState == _AiDraftUiState.success) ...[
          const SizedBox(height: _fieldSpacing),
          _AiInlineStatusBanner(
            message: _aiDraftSuccessInlineMessage,
            icon: Icons.check_circle_outline,
          ),
        ],
        if (_uiState == _AiDraftUiState.error && _lastError != null) ...[
          const SizedBox(height: _fieldSpacing),
          _AiDraftErrorPanel(
            error: _lastError!,
            showDetails: _showErrorDetails,
            onToggleDetails: () {
              setState(() => _showErrorDetails = !_showErrorDetails);
            },
            onRetry: _generateDraft,
          ),
        ],
        if (widget.draft.aiGenerated) ...[
          const SizedBox(height: _fieldSpacing),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(_fieldSpacing),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _aiSummaryLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: summaryValues
                      .map(
                        (item) => RichText(
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodySmall,
                            children: [
                              TextSpan(text: "${item.label}: "),
                              TextSpan(
                                text: item.value,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Text(
                  _aiSummaryRisksLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                if (widget.draft.riskNotes.isEmpty)
                  Text(
                    _aiSummaryNoRisks,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (widget.draft.riskNotes.isNotEmpty)
                  ...widget.draft.riskNotes.map(
                    (risk) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        "- $risk",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  ProductionAiDraftError _toAiDraftError(Object error) {
    if (error is ProductionAiDraftError) {
      return error;
    }
    return ProductionAiDraftError(
      message: _aiDraftFailureMessage,
      classification: "UNKNOWN_PROVIDER_ERROR",
      errorCode: "PRODUCTION_AI_DRAFT_FAILED",
      resolutionHint:
          "Retry the draft generation and adjust the assistant brief.",
      details: {_extraErrorKey: error.toString()},
      retryAllowed: true,
      retryReason: "unexpected_error",
      statusCode: 500,
    );
  }
}

class _AiInlineStatusBanner extends StatelessWidget {
  final String message;
  final IconData icon;

  const _AiInlineStatusBanner({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_fieldSpacing),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiDraftErrorPanel extends StatelessWidget {
  final ProductionAiDraftError error;
  final bool showDetails;
  final VoidCallback onToggleDetails;
  final VoidCallback onRetry;

  const _AiDraftErrorPanel({
    required this.error,
    required this.showDetails,
    required this.onToggleDetails,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailsLines = <String>[
      if (error.details["missing"] is List)
        "Missing: ${(error.details["missing"] as List).join(", ")}",
      if (error.details["invalid"] is List)
        "Invalid: ${(error.details["invalid"] as List).join(", ")}",
      if (error.details["providerMessage"] != null &&
          error.details["providerMessage"].toString().trim().isNotEmpty)
        "Provider: ${error.details["providerMessage"]}",
    ].where((line) => line.trim().isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_fieldSpacing),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _aiDraftErrorTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "${error.classification} • ${error.errorCode}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.resolutionHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: error.retryAllowed ? onRetry : null,
                icon: const Icon(Icons.refresh),
                label: const Text(_aiDraftRetryLabel),
              ),
              const SizedBox(width: 8),
              if (detailsLines.isNotEmpty)
                TextButton(
                  onPressed: onToggleDetails,
                  child: Text(
                    showDetails
                        ? _aiDraftErrorDetailsHideLabel
                        : _aiDraftErrorDetailsLabel,
                  ),
                ),
            ],
          ),
          if (showDetails && detailsLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final line in detailsLines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
