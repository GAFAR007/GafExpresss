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
import 'package:frontend/app/features/home/presentation/production/production_draft_calendar_preview.dart';
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_task_table.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _logTag = "PRODUCTION_CREATE_FORM";
const String _submitAction = "submit_plan";
const String _submitSuccess = "submit_success";
const String _submitFailure = "submit_failure";
const String _submitPreChatOpen = "submit_pre_chat_open";
const String _submitPreChatContinue = "submit_pre_chat_continue";
const String _submitPreChatCancel = "submit_pre_chat_cancel";
const String _submitPreChatDraft = "submit_pre_chat_draft";
const String _addTaskAction = "add_task";
const String _removeTaskAction = "remove_task";
const String _createProductAction = "create_product_tap";
const String _createProductSuccess = "create_product_success";
const String _createProductCancel = "create_product_cancel";
const String _aiDraftAction = "ai_draft_tap";
const String _aiDraftSuccess = "ai_draft_success";
const String _aiDraftFailure = "ai_draft_failure";
const String _aiDraftPartial = "ai_draft_partial";
const String _aiDraftMissing = "ai_draft_missing_fields";
const String _aiDraftCalendarAddTask = "ai_draft_calendar_add_task";
const String _aiSuggestedProductCreateTap = "ai_suggested_product_create_tap";
const String _aiSuggestedProductCreated = "ai_suggested_product_created";
const String _validationFailure = "validation_failed";
const String _calendarTaskDetailOpen = "calendar_task_detail_open";
const String _calendarTaskDetailSaved = "calendar_task_detail_saved";
const String _extraErrorKey = "error";
const String _extraProductKey = "productId";
const String _extraPhaseKey = "phase";
const String _extraTaskIdKey = "taskId";
const String _extraTaskIndexKey = "taskIndex";
const String _extraStatusKey = "status";
const String _extraHasPromptKey = "hasPrompt";
const String _extraPromptLengthKey = "promptLength";
const String _extraClassificationKey = "classification";
const String _extraErrorCodeKey = "errorCode";
const String _extraIssueTypeKey = "issueType";
const String _extraDomainContextKey = "domainContext";
const String _extraRoleKey = "role";
const String _extraRetryAllowedKey = "retryAllowed";
const String _extraRetryReasonKey = "retryReason";

const String _titleLabel = "Plan title";
const String _notesLabel = "Notes";
const String _notesHint = "Optional notes for this plan";
const String _domainContextLabel = "Business type (optional)";
const String _domainContextHint =
    "Choose a domain to bias AI suggestions. Generic works for any business.";
const String _estateLabel = "Estate";
const String _productLabel = "Product";
const String _createProductLabel = "Create product";
const String _createProductHint = "Add a new product for this plan.";
const String _startDateLabel = "Start date";
const String _endDateLabel = "End date";
const String _aiDraftLabel = "AI-generated draft";
const String _aiDraftHelper = "Mark if this plan started as an AI draft.";
const String _aiDraftApplyButtonLabel = "Draft production";
const String _aiSummaryLabel = "AI draft summary";
const String _aiSummaryTasksLabel = "Tasks";
const String _aiSummaryDaysLabel = "Estimated days";
const String _aiSummaryRisksLabel = "Risk notes";
const String _aiSummaryNoRisks = "No risks flagged";
const String _aiDraftMissingFields =
    "Select estate and product before generating an AI draft.";
const String _aiDraftSuccessMessage = "AI draft applied.";
const String _aiDraftFailureMessage = "Unable to generate AI draft.";
const String _aiDraftErrorTitle = "AI draft could not be applied";
const String _aiDraftErrorDetailsLabel = "Show details";
const String _aiDraftErrorDetailsHideLabel = "Hide details";
const String _aiDraftRetryLabel = "Retry";
const String _aiDraftSuccessInlineMessage =
    "AI draft ready. Review and adjust tasks.";
const String _aiDraftReadyToApplyMessage =
    "Draft generated. Review the calendar preview, then apply it to the form.";
const String _aiDraftCalendarAddTaskMessage = "Task added to draft day.";
const String _calendarTaskDetailTitle = "Task details";
const String _calendarTaskDetailSave = "Save";
const String _calendarTaskDetailCancel = "Cancel";
const String _calendarTaskDetailTaskLabel = "Task";
const String _calendarTaskDetailRoleLabel = "Role";
const String _calendarTaskDetailHeadcountLabel = "Headcount";
const String _calendarTaskDetailStaffLabel = "Staff";
const String _calendarTaskDetailWeightLabel = "Weight";
const String _calendarTaskDetailStatusLabel = "Status";
const String _calendarTaskDetailInstructionsLabel = "Instructions";
const String _calendarTaskDetailHint =
    "Configure this task for the selected day.";
const String _calendarTaskDetailTaskRequiredMessage = "Task title is required.";
const String _aiDraftPartialProductIssue = "PRODUCT_NOT_INFERRED";
const String _aiDraftPartialDateIssue = "DATE_NOT_INFERRED";
const String _aiDraftPartialContextIssue = "INSUFFICIENT_CONTEXT";
const String _aiDraftPartialSchemaIssue = "HARD_SCHEMA_FAILURE";
const String _aiDraftPartialTitle = "We couldn't complete the AI draft yet";
const String _aiDraftPartialProductDescription =
    "The description didn't give enough information to suggest a product.";
const String _aiDraftPartialDateDescription =
    "The description didn't give enough information to suggest plan dates.";
const String _aiDraftPartialContextDescription =
    "The description needs a little more detail so AI can suggest product and schedule.";
const String _aiDraftPartialSchemaDescription =
    "AI output needed manual review, so a safe starter draft was created.";
const String _aiDraftPartialGoodNewsLabel = "Good news:";
const String _aiDraftPartialGoodNewsValue =
    "Your production tasks and plan structure were generated successfully.";
const String _aiDraftPartialSchemaGoodNewsValue =
    "A safe production plan structure was generated for manual completion.";
const String _aiDraftPartialActionsLabel = "Actions:";
const String _aiDraftPartialEditAction = "Edit description";
const String _aiDraftPartialSelectProductAction = "Select product";
const String _aiDraftPartialRetryAction = "Retry AI draft";
const String _aiDraftPartialProductHint =
    "Select a product from the Product field, then retry AI draft.";
const String _aiDraftPartialAppliedMessage =
    "AI draft applied with guidance. Review product and dates before final save.";
const String _aiSuggestedTag = "AI suggested";
const String _aiSuggestedDateHint = "AI suggested date. You can edit this.";
const String _aiSuggestedProductTitle = "AI suggested product draft";
const String _aiSuggestedProductHint =
    "Create this product now or choose an existing product from the list.";
const String _aiSuggestedCreateProductLabel = "Create suggested product";
const String _aiSuggestedProductAppliedMessage =
    "Suggested product created and selected.";
const String _submitLabel = "Create plan";
const String _preCreateChatTitle = "Assistant check-in";
const String _preCreateChatPrompt =
    "Before I create this plan, here are the roles and staff names with IDs linked to the selected estate.";
const String _preCreateChatEstatePrefix = "Estate";
const String _preCreateChatAssistantName = "Plan assistant";
const String _preCreateChatNoEstate =
    "Select an estate first so I can fetch role-to-staff mapping.";
const String _preCreateChatNoStaff =
    "No staff profiles are currently linked to this estate.";
const String _preCreateChatRoleFocusLabel = "Focus roles";
const String _preCreateChatRoleFocusHint =
    "Pick role groups you want AI to prioritize in this production.";
const String _preCreateChatStaffFocusLabel = "Preferred staff";
const String _preCreateChatStaffFocusHint =
    "Pick staff members AI should consider first for these role tracks.";
const String _preCreateChatStrictPromptLabel = "Strict draft prompt";
const String _preCreateChatStrictPromptHint =
    "This prompt will be used to generate a new strict AI draft from your selected roles and staff IDs.";
const String _preCreateChatStrictPromptTapHint =
    "Tap this prompt to draft a new plan now using selected roles and staff IDs.";
const String _preCreateChatCancelLabel = "Back";
const String _preCreateChatContinueLabel = "Continue";
const String _selectPlaceholder = "Select";
const String _submitError = "Unable to create plan.";
const String _submitSuccessMessage = "Plan created successfully.";
const String _assetTypeEstate = "estate";
// WHY: Keep AI draft payload keys centralized.
const String _draftPayloadEstateId = "estateAssetId";
const String _draftPayloadProductId = "productId";
const String _draftPayloadDomainContext = "domainContext";
const String _draftPayloadStartDate = "startDate";
const String _draftPayloadEndDate = "endDate";
const String _draftPayloadAiBrief = "aiBrief";
const String _draftPayloadFocusedRoles = "focusedRoles";
const String _draftPayloadFocusedStaffProfileIds = "focusedStaffProfileIds";
const String _draftPayloadCropSubtype = "cropSubtype";
const String _draftPayloadBusinessType = "businessType";

const double _pagePadding = 16;
const double _sectionSpacing = 16;
const double _fieldSpacing = 12;
const double _submitSpinnerSize = 16;
const double _submitSpinnerStroke = 2;

const int _notesMaxLines = 3;
const int _queryPage = 1;
const int _queryLimit = 50;
const List<int> _taskEditorWeightOptions = <int>[1, 2, 3, 4, 5];
const List<int> _taskEditorHeadcountOptions = <int>[
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
];

enum _AiDraftUiState { idle, generating, success, partial, error }

enum _PreCreateChatAction { cancel, continueCreate, draftFromPrompt }

class ProductionPlanCreateBody extends ConsumerStatefulWidget {
  const ProductionPlanCreateBody({super.key});

  @override
  ConsumerState<ProductionPlanCreateBody> createState() =>
      _ProductionPlanCreateBodyState();
}

class _ProductionPlanCreateBodyState
    extends ConsumerState<ProductionPlanCreateBody> {
  bool _isSubmitting = false;
  // WHY: Retain focused role selection so strict AI prompts can include role context.
  final Set<String> _aiFocusedRoles = <String>{};
  // WHY: Retain focused staff IDs so AI can prioritize selected workers in drafts.
  final Set<String> _aiFocusedStaffProfileIds = <String>{};
  // WHY: Keeps compatibility with prompt-triggered AI draft actions in the legacy flow.
  final GlobalKey<_PlanAiSectionState> _planAiSectionKey =
      GlobalKey<_PlanAiSectionState>();
  final Map<String, DateTimeRange> _taskScheduleOverrides =
      <String, DateTimeRange>{};

  Future<void> _addTaskAtAndOpenDetailDialog({
    required int phaseIndex,
    required int taskIndex,
    required List<BusinessStaffProfileSummary> staffProfiles,
    DateTime? day,
    DateTime? suggestedStart,
    DateTime? suggestedDue,
  }) async {
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final before = ref.read(productionPlanDraftProvider);
    if (phaseIndex < 0 || phaseIndex >= before.phases.length) {
      return;
    }
    final safeTaskIndex = taskIndex.clamp(
      0,
      before.phases[phaseIndex].tasks.length,
    );
    controller.addTaskAt(phaseIndex, safeTaskIndex);

    final after = ref.read(productionPlanDraftProvider);
    if (phaseIndex < 0 || phaseIndex >= after.phases.length) {
      return;
    }
    if (after.phases[phaseIndex].tasks.isEmpty) {
      return;
    }
    final resolvedTaskIndex = safeTaskIndex.clamp(
      0,
      after.phases[phaseIndex].tasks.length - 1,
    );
    final task = after.phases[phaseIndex].tasks[resolvedTaskIndex];
    if (suggestedStart != null &&
        suggestedDue != null &&
        suggestedDue.isAfter(suggestedStart)) {
      setState(() {
        _taskScheduleOverrides[task.id] = DateTimeRange(
          start: suggestedStart,
          end: suggestedDue,
        );
      });
    }

    AppDebug.log(
      _logTag,
      _calendarTaskDetailOpen,
      extra: {
        _extraPhaseKey: after.phases[phaseIndex].name,
        _extraTaskIdKey: task.id,
        _extraTaskIndexKey: resolvedTaskIndex,
        if (day != null) "day": formatDateInput(day),
        if (suggestedStart != null)
          "suggestedStart": suggestedStart.toIso8601String(),
        if (suggestedDue != null)
          "suggestedDue": suggestedDue.toIso8601String(),
      },
    );

    if (!mounted) {
      return;
    }
    await _openTaskDetailDialog(
      phaseIndex: phaseIndex,
      taskId: task.id,
      staffProfiles: staffProfiles,
    );
  }

  Future<void> _openTaskDetailDialog({
    required int phaseIndex,
    required String taskId,
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) async {
    final draft = ref.read(productionPlanDraftProvider);
    if (phaseIndex < 0 || phaseIndex >= draft.phases.length) {
      return;
    }
    ProductionTaskDraft? task;
    for (final entry in draft.phases[phaseIndex].tasks) {
      if (entry.id == taskId) {
        task = entry;
        break;
      }
    }
    if (task == null) {
      return;
    }
    final originalRole = task.roleRequired;

    final titleController = TextEditingController(text: task.title);
    final instructionsController = TextEditingController(
      text: task.instructions,
    );
    String selectedRole = task.roleRequired;
    String? selectedStaffId = task.assignedStaffId;
    int selectedHeadcount = task.requiredHeadcount < 1
        ? 1
        : task.requiredHeadcount;
    int selectedWeight = task.weight;
    ProductionTaskStatus selectedStatus = task.status;

    List<BusinessStaffProfileSummary> roleScopedStaff() {
      final normalizedRole = selectedRole.trim().toLowerCase();
      return staffProfiles.where((profile) {
        return profile.staffRole.trim().toLowerCase() == normalizedRole;
      }).toList();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final roleStaff = roleScopedStaff();
            final staffStillValid =
                selectedStaffId != null &&
                roleStaff.any((profile) => profile.id == selectedStaffId);
            if (!staffStillValid) {
              selectedStaffId = null;
            }
            final headcountOptions = <int>{
              ..._taskEditorHeadcountOptions,
              if (selectedHeadcount > 10) selectedHeadcount,
            }.toList()..sort();

            return AlertDialog(
              title: const Text(_calendarTaskDetailTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _calendarTaskDetailHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailTaskLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<ProductionTaskStatus>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailStatusLabel,
                      ),
                      items: ProductionTaskStatus.values
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(_taskStatusLabel(status)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedStatus = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailRoleLabel,
                      ),
                      items: staffRoleValues
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(
                                formatStaffRoleLabel(role, fallback: role),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedRole = value;
                          selectedStaffId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStaffId,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailStaffLabel,
                      ),
                      hint: const Text("Select"),
                      items: roleStaff
                          .map(
                            (profile) => DropdownMenuItem(
                              value: profile.id,
                              child: Text(
                                profile.userName ??
                                    profile.userEmail ??
                                    profile.id,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: roleStaff.isEmpty
                          ? null
                          : (value) {
                              setLocalState(() {
                                selectedStaffId = value;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: selectedHeadcount,
                      decoration: InputDecoration(
                        labelText: _calendarTaskDetailHeadcountLabel,
                        helperText:
                            "${selectedStaffId == null ? 0 : 1}/$selectedHeadcount",
                      ),
                      items: headcountOptions
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedHeadcount = value < 1 ? 1 : value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: selectedWeight,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailWeightLabel,
                      ),
                      items: _taskEditorWeightOptions
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedWeight = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: instructionsController,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailInstructionsLabel,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(_calendarTaskDetailCancel),
                ),
                FilledButton(
                  onPressed: () {
                    final controller = ref.read(
                      productionPlanDraftProvider.notifier,
                    );
                    final trimmedTitle = titleController.text.trim();
                    final normalizedTitle = trimmedTitle.isEmpty
                        ? "Task"
                        : trimmedTitle;
                    final normalizedInstructions = instructionsController.text
                        .trim();
                    final normalizedHeadcount = selectedHeadcount < 1
                        ? 1
                        : selectedHeadcount;

                    controller.updateTaskTitle(
                      phaseIndex,
                      taskId,
                      normalizedTitle,
                    );
                    if (selectedRole != originalRole) {
                      controller.updateTaskRole(
                        phaseIndex,
                        taskId,
                        selectedRole,
                      );
                    }
                    controller.updateTaskRequiredHeadcount(
                      phaseIndex,
                      taskId,
                      normalizedHeadcount,
                    );
                    controller.updateTaskWeight(
                      phaseIndex,
                      taskId,
                      selectedWeight,
                    );
                    controller.updateTaskInstructions(
                      phaseIndex,
                      taskId,
                      normalizedInstructions,
                    );
                    controller.updateTaskStaff(
                      phaseIndex,
                      taskId,
                      selectedStaffId,
                    );
                    controller.updateTaskStatus(
                      phaseIndex,
                      taskId,
                      selectedStatus,
                    );

                    AppDebug.log(
                      _logTag,
                      _calendarTaskDetailSaved,
                      extra: {
                        _extraTaskIdKey: taskId,
                        _extraPhaseKey: draft.phases[phaseIndex].name,
                        _extraStatusKey: selectedStatus.name,
                        _extraRoleKey: selectedRole,
                      },
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text(_calendarTaskDetailSave),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitPlan({
    required String? estateAssetId,
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) async {
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

    final preCreateAction = await _showPreCreateAssistantChat(
      estateAssetId: estateAssetId,
      staffProfiles: staffProfiles,
    );
    switch (preCreateAction) {
      case _PreCreateChatAction.cancel:
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
        return;
      case _PreCreateChatAction.draftFromPrompt:
        await _triggerAiDraftFromPromptTap(staffProfiles: staffProfiles);
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
        return;
      case _PreCreateChatAction.continueCreate:
        break;
    }

    // WHY: Log submission intent before API call.
    AppDebug.log(_logTag, _submitAction);
    try {
      final detail = await ref
          .read(productionPlanActionsProvider)
          .createPlan(payload: controller.toPayload());
      controller.reset();
      _taskScheduleOverrides.clear();
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

  Future<void> _triggerAiDraftFromPromptTap({
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) async {
    // WHY: Wait one frame so AI section receives the latest selected roles/staff IDs.
    await WidgetsBinding.instance.endOfFrame;
    final aiSectionState = _planAiSectionKey.currentState;
    if (aiSectionState == null) {
      // WHY: Fallback removes UI-state dependency so prompt tap always drafts.
      await _generateAndApplyFocusedDraftFallback(staffProfiles: staffProfiles);
      return;
    }
    await aiSectionState.generateDraftFromPromptTap();
  }

  Future<void> _generateAndApplyFocusedDraftFallback({
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) async {
    final draft = ref.read(productionPlanDraftProvider);
    if (draft.estateAssetId == null ||
        draft.estateAssetId!.trim().isEmpty ||
        draft.productId == null ||
        draft.productId!.trim().isEmpty) {
      // WHY: AI draft endpoint requires estate + product context.
      AppDebug.log(
        _logTag,
        _aiDraftMissing,
        extra: {
          _extraClassificationKey: "MISSING_REQUIRED_FIELD",
          _extraErrorCodeKey: "PRODUCTION_AI_CONTEXT_REQUIRED",
          _extraErrorKey:
              "Prompt tap fallback skipped because estate or product is missing.",
          _extraRetryAllowedKey: true,
          _extraRetryReasonKey: "missing_required_context",
        },
      );
      _showSnack(_aiDraftMissingFields);
      return;
    }

    final strictPrompt = _buildStrictDraftPromptFromSelection(
      selectedRoleLabels: _aiFocusedRoles,
      selectedStaffOptions: _selectedStaffOptionsForPrompt(
        allOptions: _buildEstateStaffPromptOptions(
          estateAssetId: draft.estateAssetId!.trim(),
          staffProfiles: staffProfiles,
        ),
        selectedStaffProfileIds: _aiFocusedStaffProfileIds,
      ),
    );
    final payload = {
      _draftPayloadEstateId: draft.estateAssetId,
      _draftPayloadProductId: draft.productId,
      _draftPayloadDomainContext: normalizeProductionDomainContext(
        draft.domainContext,
      ),
      _draftPayloadStartDate: draft.startDate?.toIso8601String(),
      _draftPayloadEndDate: draft.endDate?.toIso8601String(),
      _draftPayloadAiBrief: strictPrompt,
      _draftPayloadFocusedRoles: _aiFocusedRoles.toList()..sort(),
      _draftPayloadFocusedStaffProfileIds: _aiFocusedStaffProfileIds.toList()
        ..sort(),
      _draftPayloadBusinessType: normalizeProductionDomainContext(
        draft.domainContext,
      ),
      _draftPayloadCropSubtype: "",
    };

    AppDebug.log(
      _logTag,
      _aiDraftAction,
      extra: {
        _extraHasPromptKey: strictPrompt.isNotEmpty,
        _extraPromptLengthKey: strictPrompt.length,
        _draftPayloadFocusedRoles: payload[_draftPayloadFocusedRoles],
        _draftPayloadFocusedStaffProfileIds:
            payload[_draftPayloadFocusedStaffProfileIds],
        _extraDomainContextKey: normalizeProductionDomainContext(
          draft.domainContext,
        ),
      },
    );
    try {
      final generated = await ref
          .read(productionPlanActionsProvider)
          .generateAiDraft(payload: payload);
      final focusedApplied = _applyFocusedStaffToAiDraftResult(
        draftResult: generated,
        staffProfiles: staffProfiles,
        focusedStaffProfileIds: _aiFocusedStaffProfileIds.toList(),
      );
      ref
          .read(productionPlanDraftProvider.notifier)
          .applyDraft(focusedApplied.draft);
      AppDebug.log(
        _logTag,
        "ai_draft_applied_from_prompt_fallback",
        extra: {
          "taskCount": focusedApplied.tasks.length,
          "warningCount": focusedApplied.warnings.length,
          _draftPayloadFocusedRoles: _aiFocusedRoles.toList()..sort(),
          _draftPayloadFocusedStaffProfileIds:
              _aiFocusedStaffProfileIds.toList()..sort(),
        },
      );
      _showSnack(_aiDraftSuccessMessage);
    } catch (err) {
      if (err is ProductionAiDraftError) {
        AppDebug.log(
          _logTag,
          _aiDraftFailure,
          extra: {
            _extraErrorKey: err.message,
            _extraClassificationKey: err.classification,
            _extraErrorCodeKey: err.errorCode,
            _extraRetryAllowedKey: err.retryAllowed,
            _extraRetryReasonKey: err.retryReason,
          },
        );
      } else {
        AppDebug.log(
          _logTag,
          _aiDraftFailure,
          extra: {
            _extraErrorKey: err.toString(),
            _extraClassificationKey: "UNKNOWN_PROVIDER_ERROR",
            _extraErrorCodeKey: "PRODUCTION_AI_DRAFT_FAILED",
            _extraRetryAllowedKey: true,
            _extraRetryReasonKey: "unexpected_error",
          },
        );
      }
      _showSnack(_aiDraftFailureMessage);
    }
  }

  List<_EstateStaffPromptOption> _buildEstateStaffPromptOptions({
    required String estateAssetId,
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) {
    final options = <_EstateStaffPromptOption>[];
    for (final profile in staffProfiles) {
      final profileEstateId = (profile.estateAssetId ?? "").trim();
      if (profileEstateId != estateAssetId) {
        continue;
      }
      final profileId = profile.id.trim();
      if (profileId.isEmpty) {
        continue;
      }
      final roleLabel = formatStaffRoleLabel(
        profile.staffRole,
        fallback: profile.staffRole,
      );
      options.add(
        _EstateStaffPromptOption(
          id: profileId,
          roleLabel: roleLabel,
          displayName: _resolvePreCreateStaffDisplayName(profile),
        ),
      );
    }
    options.sort((a, b) {
      final roleDiff = a.roleLabel.compareTo(b.roleLabel);
      if (roleDiff != 0) {
        return roleDiff;
      }
      return a.displayLabel.compareTo(b.displayLabel);
    });
    return options;
  }

  Map<String, List<String>> _buildEstateRoleStaffMapFromOptions(
    List<_EstateStaffPromptOption> options,
  ) {
    final grouped = <String, Set<String>>{};
    for (final option in options) {
      grouped
          .putIfAbsent(option.roleLabel, () => <String>{})
          .add(option.displayLabel);
    }
    final sortedRoles = grouped.keys.toList()..sort();
    return {
      for (final role in sortedRoles) role: (grouped[role]!.toList()..sort()),
    };
  }

  String _resolvePreCreateStaffDisplayName(
    BusinessStaffProfileSummary profile,
  ) {
    // WHY: Human-readable names make the pre-create review actionable.
    final userName = (profile.userName ?? "").trim();
    if (userName.isNotEmpty) {
      return userName;
    }
    final userEmail = (profile.userEmail ?? "").trim();
    if (userEmail.isNotEmpty) {
      return userEmail;
    }
    return profile.id.trim();
  }

  List<_EstateStaffPromptOption> _selectedStaffOptionsForPrompt({
    required List<_EstateStaffPromptOption> allOptions,
    required Set<String> selectedStaffProfileIds,
  }) {
    final selected = allOptions
        .where((option) => selectedStaffProfileIds.contains(option.id))
        .toList();
    selected.sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
    return selected;
  }

  String _buildStrictDraftPromptFromSelection({
    required Set<String> selectedRoleLabels,
    required List<_EstateStaffPromptOption> selectedStaffOptions,
  }) {
    final sortedRoles = selectedRoleLabels.toList()..sort();
    final lines = <String>[
      "STRICT_DRAFT_MODE: Generate a NEW production plan draft.",
      "The draft must strongly prioritize the selected roles and staff profile IDs.",
      "Use profile IDs for assignment context; do not use staff names in task assignment fields.",
      if (sortedRoles.isNotEmpty)
        "Required role focus: ${sortedRoles.join(", ")}.",
      if (selectedStaffOptions.isNotEmpty)
        "Preferred staff profiles (use first where role matches): ${selectedStaffOptions.map((option) => "${option.displayName} [role: ${option.roleLabel}, profileId: ${option.id}]").join("; ")}.",
      "If preferred staff are insufficient for workload, keep the selected role tracks and flag staffing gaps explicitly in warnings.",
    ];
    return lines.join("\n");
  }

  Future<_PreCreateChatAction> _showPreCreateAssistantChat({
    required String? estateAssetId,
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) async {
    final scopedEstateId = estateAssetId?.trim() ?? "";
    final estateStaffOptions = scopedEstateId.isEmpty
        ? const <_EstateStaffPromptOption>[]
        : _buildEstateStaffPromptOptions(
            estateAssetId: scopedEstateId,
            staffProfiles: staffProfiles,
          );
    final roleStaffMap = _buildEstateRoleStaffMapFromOptions(
      estateStaffOptions,
    );
    final roleLabels = roleStaffMap.keys.toList()..sort();
    final roleByStaffId = {
      for (final option in estateStaffOptions) option.id: option.roleLabel,
    };
    final roleCount = roleStaffMap.length;
    final staffCount = estateStaffOptions.length;
    final availableStaffIds = estateStaffOptions
        .map((option) => option.id)
        .toSet();
    final selectedRoleLabels = _aiFocusedRoles
        .where(roleLabels.contains)
        .toSet();
    final selectedStaffProfileIds = _aiFocusedStaffProfileIds
        .where(availableStaffIds.contains)
        .toSet();
    AppDebug.log(
      _logTag,
      _submitPreChatOpen,
      extra: {
        _draftPayloadEstateId: scopedEstateId,
        "roleCount": roleCount,
        "staffCount": staffCount,
      },
    );

    final canContinue = scopedEstateId.isNotEmpty;
    final shouldContinue = await showModalBottomSheet<_PreCreateChatAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final viewInsets = MediaQuery.viewInsetsOf(sheetContext);
        return StatefulBuilder(
          builder: (context, setModalState) {
            final visibleStaffOptions = selectedRoleLabels.isEmpty
                ? estateStaffOptions
                : estateStaffOptions
                      .where(
                        (option) =>
                            selectedRoleLabels.contains(option.roleLabel),
                      )
                      .toList();
            final selectedStaffOptions = _selectedStaffOptionsForPrompt(
              allOptions: estateStaffOptions,
              selectedStaffProfileIds: selectedStaffProfileIds,
            );
            final strictPromptPreview = _buildStrictDraftPromptFromSelection(
              selectedRoleLabels: selectedRoleLabels,
              selectedStaffOptions: selectedStaffOptions,
            );
            void applyFocusedSelection() {
              // WHY: Save selected role/staff context before either drafting or continuing.
              setState(() {
                _aiFocusedRoles
                  ..clear()
                  ..addAll(selectedRoleLabels);
                _aiFocusedStaffProfileIds
                  ..clear()
                  ..addAll(selectedStaffProfileIds);
              });
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                _pagePadding,
                8,
                _pagePadding,
                _pagePadding + viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _preCreateChatTitle,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // WHY: First assistant bubble gives the user context before commit.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _preCreateChatAssistantName,
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _preCreateChatPrompt,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "$_preCreateChatEstatePrefix: "
                            "${scopedEstateId.isEmpty ? _selectPlaceholder : scopedEstateId}",
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (scopedEstateId.isEmpty)
                      Text(
                        _preCreateChatNoEstate,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else if (roleStaffMap.isEmpty)
                      Text(
                        _preCreateChatNoStaff,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else ...[
                      Text(
                        _preCreateChatRoleFocusLabel,
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _preCreateChatRoleFocusHint,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: roleLabels
                            .map(
                              (roleLabel) => FilterChip(
                                selected: selectedRoleLabels.contains(
                                  roleLabel,
                                ),
                                label: Text(roleLabel),
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      selectedRoleLabels.add(roleLabel);
                                    } else {
                                      selectedRoleLabels.remove(roleLabel);
                                      selectedStaffProfileIds.removeWhere(
                                        (profileId) =>
                                            roleByStaffId[profileId] ==
                                            roleLabel,
                                      );
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _preCreateChatStaffFocusLabel,
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _preCreateChatStaffFocusHint,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: SingleChildScrollView(
                            child: Column(
                              children: visibleStaffOptions
                                  .map(
                                    (option) => CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      value: selectedStaffProfileIds.contains(
                                        option.id,
                                      ),
                                      title: Text(
                                        option.displayName,
                                        style: textTheme.bodySmall,
                                      ),
                                      subtitle: Text(
                                        "${option.roleLabel} | ${option.id}",
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      onChanged: (selected) {
                                        setModalState(() {
                                          if (selected == true) {
                                            selectedStaffProfileIds.add(
                                              option.id,
                                            );
                                          } else {
                                            selectedStaffProfileIds.remove(
                                              option.id,
                                            );
                                          }
                                        });
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Selected roles: ${selectedRoleLabels.length} | Selected staff: ${selectedStaffProfileIds.length}",
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      _preCreateChatStrictPromptLabel,
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _preCreateChatStrictPromptHint,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: canContinue
                            ? () {
                                applyFocusedSelection();
                                Navigator.of(
                                  sheetContext,
                                ).pop(_PreCreateChatAction.draftFromPrompt);
                              }
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _preCreateChatStrictPromptTapHint,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 150,
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    strictPromptPreview,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(
                              sheetContext,
                            ).pop(_PreCreateChatAction.cancel),
                            child: const Text(_preCreateChatCancelLabel),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: canContinue
                                ? () {
                                    applyFocusedSelection();
                                    Navigator.of(
                                      sheetContext,
                                    ).pop(_PreCreateChatAction.continueCreate);
                                  }
                                : null,
                            child: const Text(_preCreateChatContinueLabel),
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

    final action = shouldContinue ?? _PreCreateChatAction.cancel;
    final focusedRoles = _aiFocusedRoles.toList()..sort();
    final focusedStaffProfileIds = _aiFocusedStaffProfileIds.toList()..sort();
    final strictPrompt = _buildStrictDraftPromptFromSelection(
      selectedRoleLabels: _aiFocusedRoles,
      selectedStaffOptions: _selectedStaffOptionsForPrompt(
        allOptions: estateStaffOptions,
        selectedStaffProfileIds: _aiFocusedStaffProfileIds,
      ),
    );
    AppDebug.log(
      _logTag,
      switch (action) {
        _PreCreateChatAction.cancel => _submitPreChatCancel,
        _PreCreateChatAction.continueCreate => _submitPreChatContinue,
        _PreCreateChatAction.draftFromPrompt => _submitPreChatDraft,
      },
      extra: {
        _draftPayloadEstateId: scopedEstateId,
        "roleCount": roleCount,
        "staffCount": staffCount,
        _draftPayloadFocusedRoles: focusedRoles,
        _draftPayloadFocusedStaffProfileIds: focusedStaffProfileIds,
        _extraHasPromptKey: strictPrompt.isNotEmpty,
        _extraPromptLengthKey: strictPrompt.length,
      },
    );
    return action;
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
        _PlanAiSection(
          key: _planAiSectionKey,
          draft: draft,
          staffProfiles: staffList,
          focusedRoles: _aiFocusedRoles.toList()..sort(),
          focusedStaffProfileIds: _aiFocusedStaffProfileIds.toList()..sort(),
        ),
        const SizedBox(height: _sectionSpacing),
        ProductionPlanTaskTable(
          draft: draft,
          staff: staffList,
          taskScheduleOverrides: _taskScheduleOverrides,
          onAddTask: (phaseIndex) {
            final phaseName = draft.phases[phaseIndex].name;
            AppDebug.log(
              _logTag,
              _addTaskAction,
              extra: {_extraPhaseKey: phaseName},
            );
            ref.read(productionPlanDraftProvider.notifier).addTask(phaseIndex);
          },
          onAddTaskAt:
              (phaseIndex, taskIndex, day, suggestedStart, suggestedDue) async {
                final phaseName = draft.phases[phaseIndex].name;
                AppDebug.log(
                  _logTag,
                  _addTaskAction,
                  extra: {
                    _extraPhaseKey: phaseName,
                    _extraTaskIndexKey: taskIndex,
                    "day": formatDateInput(day),
                    "suggestedStart": suggestedStart.toIso8601String(),
                    "suggestedDue": suggestedDue.toIso8601String(),
                  },
                );
                await _addTaskAtAndOpenDetailDialog(
                  phaseIndex: phaseIndex,
                  taskIndex: taskIndex,
                  staffProfiles: staffList,
                  day: day,
                  suggestedStart: suggestedStart,
                  suggestedDue: suggestedDue,
                );
              },
          onRemoveTask: (phaseIndex, taskId) {
            final phaseName = draft.phases[phaseIndex].name;
            AppDebug.log(
              _logTag,
              _removeTaskAction,
              extra: {_extraPhaseKey: phaseName, _extraTaskIdKey: taskId},
            );
            _taskScheduleOverrides.remove(taskId);
            ref
                .read(productionPlanDraftProvider.notifier)
                .removeTask(phaseIndex, taskId);
          },
        ),
        const SizedBox(height: _sectionSpacing),
        ElevatedButton.icon(
          onPressed: _isSubmitting
              ? null
              : () => _submitPlan(
                  estateAssetId: draft.estateAssetId,
                  staffProfiles: staffList,
                ),
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

class _EstateStaffPromptOption {
  final String id;
  final String roleLabel;
  final String displayName;

  const _EstateStaffPromptOption({
    required this.id,
    required this.roleLabel,
    required this.displayName,
  });

  String get displayLabel => displayName == id ? id : "$displayName ($id)";
}

String _normalizeRoleKeyForFocusMatching(String rawRole) {
  // WHY: Role matching must tolerate snake_case, spaces, and case differences.
  return rawRole
      .trim()
      .toLowerCase()
      .replaceAll("_", " ")
      .replaceAll(RegExp(r"\s+"), " ");
}

List<String> _normalizeDistinctProfileIds(List<String> ids) {
  // WHY: AI payloads may include duplicates/whitespace; keep assignment IDs clean.
  return ids
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
}

bool _hasSameNormalizedIds(List<String> first, List<String> second) {
  final normalizedFirst = _normalizeDistinctProfileIds(first)..sort();
  final normalizedSecond = _normalizeDistinctProfileIds(second)..sort();
  if (normalizedFirst.length != normalizedSecond.length) {
    return false;
  }
  for (var index = 0; index < normalizedFirst.length; index += 1) {
    if (normalizedFirst[index] != normalizedSecond[index]) {
      return false;
    }
  }
  return true;
}

Map<String, List<String>> _buildFocusedStaffIdsByRole({
  required List<BusinessStaffProfileSummary> staffProfiles,
  required List<String> focusedStaffProfileIds,
}) {
  final focusedIds = focusedStaffProfileIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (focusedIds.isEmpty) {
    return const {};
  }

  final grouped = <String, Set<String>>{};
  for (final profile in staffProfiles) {
    final profileId = profile.id.trim();
    if (!focusedIds.contains(profileId)) {
      continue;
    }
    final normalizedRole = _normalizeRoleKeyForFocusMatching(profile.staffRole);
    if (normalizedRole.isEmpty) {
      continue;
    }
    grouped.putIfAbsent(normalizedRole, () => <String>{}).add(profileId);
  }

  return {
    for (final entry in grouped.entries)
      entry.key: (entry.value.toList()..sort()),
  };
}

List<String> _resolveFocusedIdsForRole({
  required String roleRequired,
  required int requiredHeadcount,
  required List<String> existingAssignedIds,
  required Map<String, List<String>> focusedStaffIdsByRole,
}) {
  final normalizedExisting = _normalizeDistinctProfileIds(existingAssignedIds);
  final normalizedRole = _normalizeRoleKeyForFocusMatching(roleRequired);
  final candidates = focusedStaffIdsByRole[normalizedRole] ?? const <String>[];
  if (candidates.isNotEmpty) {
    // WHY: Selected staff IDs should take priority in strict draft mode.
    final safeHeadcount = requiredHeadcount < 1 ? 1 : requiredHeadcount;
    return candidates.take(safeHeadcount).toList();
  }
  return normalizedExisting;
}

ProductionAiDraftResult _applyFocusedStaffToAiDraftResult({
  required ProductionAiDraftResult draftResult,
  required List<BusinessStaffProfileSummary> staffProfiles,
  required List<String> focusedStaffProfileIds,
}) {
  final focusedStaffIdsByRole = _buildFocusedStaffIdsByRole(
    staffProfiles: staffProfiles,
    focusedStaffProfileIds: focusedStaffProfileIds,
  );
  if (focusedStaffIdsByRole.isEmpty) {
    return draftResult;
  }

  var didMutateDraft = false;
  final updatedPhases = draftResult.draft.phases.map((phase) {
    final updatedTasks = phase.tasks.map((task) {
      final resolvedIds = _resolveFocusedIdsForRole(
        roleRequired: task.roleRequired,
        requiredHeadcount: task.requiredHeadcount,
        existingAssignedIds: task.assignedStaffProfileIds,
        focusedStaffIdsByRole: focusedStaffIdsByRole,
      );
      if (resolvedIds.isEmpty ||
          _hasSameNormalizedIds(task.assignedStaffProfileIds, resolvedIds)) {
        return task;
      }
      didMutateDraft = true;
      final normalizedHeadcount = task.requiredHeadcount < resolvedIds.length
          ? resolvedIds.length
          : task.requiredHeadcount;
      return task.copyWith(
        assignedStaffId: resolvedIds.first,
        assignedStaffProfileIds: resolvedIds,
        requiredHeadcount: normalizedHeadcount,
      );
    }).toList();
    return phase.copyWith(tasks: updatedTasks);
  }).toList();

  var didMutatePreview = false;
  final updatedPreviewTasks = draftResult.tasks.map((task) {
    final resolvedIds = _resolveFocusedIdsForRole(
      roleRequired: task.roleRequired,
      requiredHeadcount: task.requiredHeadcount,
      existingAssignedIds: task.assignedStaffProfileIds,
      focusedStaffIdsByRole: focusedStaffIdsByRole,
    );
    if (resolvedIds.isEmpty ||
        _hasSameNormalizedIds(task.assignedStaffProfileIds, resolvedIds)) {
      return task;
    }
    didMutatePreview = true;
    final normalizedHeadcount = task.requiredHeadcount < resolvedIds.length
        ? resolvedIds.length
        : task.requiredHeadcount;
    final availableCapacity = draftResult.capacity?.availableForRole(
      task.roleRequired,
    );
    final hasShortage = availableCapacity == null
        ? task.hasShortage
        : normalizedHeadcount > availableCapacity;
    return ProductionAiDraftTaskPreview(
      id: task.id,
      title: task.title,
      phaseName: task.phaseName,
      roleRequired: task.roleRequired,
      requiredHeadcount: normalizedHeadcount,
      assignedCount: resolvedIds.length,
      assignedStaffProfileIds: resolvedIds,
      status: task.status,
      startDate: task.startDate,
      dueDate: task.dueDate,
      instructions: task.instructions,
      hasShortage: hasShortage,
    );
  }).toList();

  if (!didMutateDraft && !didMutatePreview) {
    return draftResult;
  }

  return ProductionAiDraftResult(
    draft: didMutateDraft
        ? draftResult.draft.copyWith(phases: updatedPhases)
        : draftResult.draft,
    status: draftResult.status,
    partialIssue: draftResult.partialIssue,
    message: draftResult.message,
    summary: draftResult.summary,
    schedulePolicy: draftResult.schedulePolicy,
    capacity: draftResult.capacity,
    warnings: List<String>.from(draftResult.warnings),
    tasks: didMutatePreview ? updatedPreviewTasks : draftResult.tasks,
  );
}

String _taskStatusLabel(ProductionTaskStatus status) {
  switch (status) {
    case ProductionTaskStatus.notStarted:
      return "Not started";
    case ProductionTaskStatus.inProgress:
      return "In progress";
    case ProductionTaskStatus.blocked:
      return "Blocked";
    case ProductionTaskStatus.done:
      return "Done";
  }
}

String _taskStatusApiValue(ProductionTaskStatus status) {
  switch (status) {
    case ProductionTaskStatus.notStarted:
      return "not_started";
    case ProductionTaskStatus.inProgress:
      return "in_progress";
    case ProductionTaskStatus.blocked:
      return "blocked";
    case ProductionTaskStatus.done:
      return "done";
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
        const SizedBox(height: _fieldSpacing),
        DropdownButtonFormField<String>(
          initialValue: normalizeProductionDomainContext(draft.domainContext),
          decoration: const InputDecoration(
            labelText: _domainContextLabel,
            helperText: _domainContextHint,
          ),
          items: productionDomainValues
              .map(
                (domain) => DropdownMenuItem(
                  value: domain,
                  child: Text(formatProductionDomainLabel(domain)),
                ),
              )
              .toList(),
          onChanged: controller.updateDomainContext,
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
  final List<BusinessStaffProfileSummary> staffProfiles;
  final List<String> focusedRoles;
  final List<String> focusedStaffProfileIds;

  const _PlanAiSection({
    super.key,
    required this.draft,
    required this.staffProfiles,
    required this.focusedRoles,
    required this.focusedStaffProfileIds,
  });

  @override
  ConsumerState<_PlanAiSection> createState() => _PlanAiSectionState();
}

class _PlanAiSectionState extends ConsumerState<_PlanAiSection> {
  _AiDraftUiState _uiState = _AiDraftUiState.idle;
  ProductionAiDraftError? _lastError;
  ProductionAiDraftPartialIssue? _lastPartialIssue;
  ProductionAiDraftResult? _generatedDraft;
  Map<int, ProductionDraftTaskOverride> _draftTaskOverrides =
      <int, ProductionDraftTaskOverride>{};
  bool _showErrorDetails = false;
  // WHY: Prompt lets users steer AI output with operational context.
  final TextEditingController _assistantPromptCtrl = TextEditingController();
  final FocusNode _assistantPromptFocusNode = FocusNode();

  @override
  void dispose() {
    _assistantPromptCtrl.dispose();
    _assistantPromptFocusNode.dispose();
    super.dispose();
  }

  bool get _hasRequiredFields {
    // WHY: Estate + product are mandatory; AI may infer start/end when they are not provided.
    return widget.draft.estateAssetId != null &&
        widget.draft.estateAssetId!.trim().isNotEmpty &&
        widget.draft.productId != null &&
        widget.draft.productId!.trim().isNotEmpty;
  }

  Future<void> generateDraftFromPromptTap() async {
    // WHY: Parent sheet prompt tap should trigger the same strict AI draft flow.
    await _generateDraft(autoApply: true);
  }

  String _buildFocusedAiContextPrompt() {
    final normalizedRoles =
        widget.focusedRoles
            .map((role) => role.trim())
            .where((role) => role.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final focusedStaffIdSet = widget.focusedStaffProfileIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final selectedStaff =
        widget.staffProfiles
            .where((profile) => focusedStaffIdSet.contains(profile.id.trim()))
            .toList()
          ..sort(
            (a, b) => _resolveFocusedStaffDisplayName(
              a,
            ).compareTo(_resolveFocusedStaffDisplayName(b)),
          );

    if (normalizedRoles.isEmpty && selectedStaff.isEmpty) {
      return "";
    }

    final lines = <String>[
      "STRICT_DRAFT_MODE: Generate a NEW production plan draft.",
      "The draft must strongly prioritize the selected roles and staff profile IDs.",
      "Use profile IDs for assignment context; do not use staff names in task assignment fields.",
      if (normalizedRoles.isNotEmpty)
        "Required role focus: ${normalizedRoles.join(", ")}.",
      if (selectedStaff.isNotEmpty)
        "Preferred staff profiles (use first where role matches): ${selectedStaff.map((profile) {
          final displayName = _resolveFocusedStaffDisplayName(profile);
          final roleLabel = formatStaffRoleLabel(profile.staffRole, fallback: profile.staffRole);
          return "$displayName [role: $roleLabel, profileId: ${profile.id}]";
        }).join("; ")}.",
      "If preferred staff are insufficient for workload, keep the selected role tracks and flag staffing gaps explicitly in warnings.",
    ];
    return lines.join("\n");
  }

  String _resolveFocusedStaffDisplayName(BusinessStaffProfileSummary profile) {
    final name = (profile.userName ?? "").trim();
    if (name.isNotEmpty) {
      return name;
    }
    final email = (profile.userEmail ?? "").trim();
    if (email.isNotEmpty) {
      return email;
    }
    return profile.id.trim();
  }

  Future<void> _generateDraft({bool autoApply = false}) async {
    if (_uiState == _AiDraftUiState.generating) return;
    if (!_hasRequiredFields) {
      final missingFieldsError = ProductionAiDraftError(
        message: _aiDraftMissingFields,
        classification: "MISSING_REQUIRED_FIELD",
        errorCode: "PRODUCTION_AI_CONTEXT_REQUIRED",
        resolutionHint:
            "Select estate/product and retry. Start/end dates are optional because AI can infer them.",
        details: <String, dynamic>{
          "missing": [
            if (widget.draft.estateAssetId == null ||
                widget.draft.estateAssetId!.trim().isEmpty)
              _draftPayloadEstateId,
            if (widget.draft.productId == null ||
                widget.draft.productId!.trim().isEmpty)
              _draftPayloadProductId,
          ],
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
          _lastPartialIssue = null;
          _generatedDraft = null;
          _draftTaskOverrides = <int, ProductionDraftTaskOverride>{};
          _showErrorDetails = false;
        });
      }
      return;
    }

    setState(() {
      // WHY: Keep state explicit to drive loading/success/error UI.
      _uiState = _AiDraftUiState.generating;
      _lastError = null;
      _lastPartialIssue = null;
      _generatedDraft = null;
      _draftTaskOverrides = <int, ProductionDraftTaskOverride>{};
      _showErrorDetails = false;
    });

    // WHY: Log the generation tap for UX analytics.
    final userPrompt = _assistantPromptCtrl.text.trim();
    final focusedContextPrompt = _buildFocusedAiContextPrompt();
    final prompt = [
      userPrompt,
      focusedContextPrompt,
    ].where((value) => value.trim().isNotEmpty).join("\n\n");
    AppDebug.log(
      _logTag,
      _aiDraftAction,
      extra: {
        _extraHasPromptKey: prompt.isNotEmpty,
        _extraPromptLengthKey: prompt.length,
        _draftPayloadFocusedRoles: widget.focusedRoles,
        _draftPayloadFocusedStaffProfileIds: widget.focusedStaffProfileIds,
        _extraDomainContextKey: normalizeProductionDomainContext(
          widget.draft.domainContext,
        ),
      },
    );
    try {
      final payload = {
        _draftPayloadEstateId: widget.draft.estateAssetId,
        _draftPayloadProductId: widget.draft.productId,
        _draftPayloadDomainContext: normalizeProductionDomainContext(
          widget.draft.domainContext,
        ),
        _draftPayloadStartDate: widget.draft.startDate?.toIso8601String(),
        _draftPayloadEndDate: widget.draft.endDate?.toIso8601String(),
        _draftPayloadAiBrief: prompt,
        _draftPayloadFocusedRoles: widget.focusedRoles,
        _draftPayloadFocusedStaffProfileIds: widget.focusedStaffProfileIds,
        _draftPayloadBusinessType: normalizeProductionDomainContext(
          widget.draft.domainContext,
        ),
        _draftPayloadCropSubtype: "",
      };
      // WHY: Generate draft first; managers should preview calendar before apply.
      final draftResult = await ref
          .read(productionPlanActionsProvider)
          .generateAiDraft(payload: payload);
      final draftResultWithFocusedStaff = _applyFocusedStaffToAiDraftResult(
        draftResult: draftResult,
        staffProfiles: widget.staffProfiles,
        focusedStaffProfileIds: widget.focusedStaffProfileIds,
      );
      final partialIssue = draftResultWithFocusedStaff.partialIssue;
      if (partialIssue != null) {
        // WHY: Partial AI drafts should guide users without blocking progress.
        AppDebug.log(
          _logTag,
          _aiDraftPartial,
          extra: {_extraIssueTypeKey: partialIssue.issueType},
        );
      } else {
        // WHY: Mark success so the user knows the draft updated.
        AppDebug.log(_logTag, _aiDraftSuccess);
      }
      if (mounted) {
        setState(() {
          _uiState = partialIssue == null
              ? _AiDraftUiState.success
              : _AiDraftUiState.partial;
          _lastError = null;
          _lastPartialIssue = partialIssue;
          _generatedDraft = draftResultWithFocusedStaff;
          _showErrorDetails = false;
        });
        if (autoApply) {
          _applyGeneratedDraftResult(
            generated: draftResultWithFocusedStaff,
            trigger: "prompt_tap_auto_apply",
          );
        } else {
          _showSnack(
            partialIssue == null
                ? _aiDraftReadyToApplyMessage
                : _aiDraftPartialAppliedMessage,
          );
        }
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
          _lastPartialIssue = null;
          _generatedDraft = null;
          _draftTaskOverrides = <int, ProductionDraftTaskOverride>{};
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

  void _applyGeneratedDraftResult({
    required ProductionAiDraftResult generated,
    required String trigger,
  }) {
    final draftWithOverrides = _buildDraftWithOverrides(generated.draft);
    ref
        .read(productionPlanDraftProvider.notifier)
        .applyDraft(draftWithOverrides);
    AppDebug.log(
      _logTag,
      "ai_draft_applied_after_preview",
      extra: {
        "trigger": trigger,
        "taskCount": generated.tasks.length,
        "warningCount": generated.warnings.length,
        "overrideCount": _draftTaskOverrides.length,
      },
    );
    _showSnack(_aiDraftSuccessMessage);
  }

  void _applyGeneratedDraft() {
    final generated = _generatedDraft;
    if (generated == null) return;
    _applyGeneratedDraftResult(generated: generated, trigger: "manual_apply");
  }

  Future<void> _onPreviewAddTaskForDay(
    DateTime day,
    String phaseNameHint,
  ) async {
    final generated = _generatedDraft;
    if (generated == null) {
      return;
    }

    // WHY: Apply existing preview overrides first so no user edits are lost.
    final baseDraft = _buildDraftWithOverrides(generated.draft);
    if (baseDraft.phases.isEmpty) {
      return;
    }

    final phaseIndex = _resolvePhaseIndexForCalendarPreview(
      phases: baseDraft.phases,
      phaseNameHint: phaseNameHint,
      day: day,
      planStartDate: baseDraft.startDate ?? generated.summary?.startDate,
      planEndDate: baseDraft.endDate ?? generated.summary?.endDate,
    );
    final targetPhase = baseDraft.phases[phaseIndex];
    final phaseTasks = <ProductionTaskDraft>[...targetPhase.tasks];
    final insertTaskIndex = phaseTasks.length;
    final flatInsertIndex = _flattenedTaskOffsetForPhase(
      phases: baseDraft.phases,
      phaseIndex: phaseIndex,
    );

    final startLocal = _resolveCalendarDayTaskStart(
      day: day,
      policy: generated.schedulePolicy,
    );
    final dueLocal = _resolveCalendarDayTaskEnd(
      startLocal: startLocal,
      policy: generated.schedulePolicy,
    );

    final nextTaskId = "task_${DateTime.now().microsecondsSinceEpoch}";
    final fallbackRole = targetPhase.tasks.isNotEmpty
        ? targetPhase.tasks.first.roleRequired
        : "farmer";
    final nextRequiredHeadcount = 1;

    final nextDraftTask = ProductionTaskDraft(
      id: nextTaskId,
      title: "Task",
      roleRequired: fallbackRole,
      assignedStaffId: null,
      assignedStaffProfileIds: const <String>[],
      requiredHeadcount: nextRequiredHeadcount,
      weight: 1,
      instructions: "Task added from draft calendar day view.",
      status: ProductionTaskStatus.notStarted,
      completedAt: null,
      completedByStaffId: null,
    );
    phaseTasks.insert(insertTaskIndex, nextDraftTask);

    final updatedPhases = <ProductionPhaseDraft>[...baseDraft.phases];
    updatedPhases[phaseIndex] = targetPhase.copyWith(tasks: phaseTasks);

    final updatedDraft = baseDraft.copyWith(
      phases: updatedPhases,
      totalTasks: baseDraft.totalTasks + 1,
    );

    final nextPreviewTask = ProductionAiDraftTaskPreview(
      id: nextTaskId,
      title: nextDraftTask.title,
      phaseName: targetPhase.name,
      roleRequired: fallbackRole,
      requiredHeadcount: nextRequiredHeadcount,
      assignedCount: 0,
      assignedStaffProfileIds: const <String>[],
      status: "not_started",
      startDate: startLocal.toUtc(),
      dueDate: dueLocal.toUtc(),
      instructions: nextDraftTask.instructions,
      hasShortage: generated.capacity != null
          ? nextRequiredHeadcount >
                generated.capacity!.availableForRole(fallbackRole)
          : false,
    );

    final updatedPreviewTasks = <ProductionAiDraftTaskPreview>[
      ...generated.tasks,
    ];
    final safePreviewInsertIndex = (flatInsertIndex + insertTaskIndex).clamp(
      0,
      updatedPreviewTasks.length,
    );
    updatedPreviewTasks.insert(safePreviewInsertIndex, nextPreviewTask);

    final updatedResult = ProductionAiDraftResult(
      draft: updatedDraft,
      status: generated.status,
      partialIssue: generated.partialIssue,
      message: generated.message,
      summary: generated.summary,
      schedulePolicy: generated.schedulePolicy,
      capacity: generated.capacity,
      warnings: List<String>.from(generated.warnings),
      tasks: updatedPreviewTasks,
    );

    setState(() {
      _generatedDraft = updatedResult;
      // WHY: Index-based overrides are no longer stable after inserting a task.
      _draftTaskOverrides = <int, ProductionDraftTaskOverride>{};
    });

    if (!mounted) {
      return;
    }
    // WHY: Calendar "Add task" should open the same detailed edit flow immediately.
    await _openGeneratedDraftTaskDetailDialog(
      phaseIndex: phaseIndex,
      taskId: nextTaskId,
    );

    AppDebug.log(
      _logTag,
      _aiDraftCalendarAddTask,
      extra: {
        "day": formatDateInput(day),
        "phaseNameHint": phaseNameHint,
        "phaseIndex": phaseIndex,
        "flatInsertIndex": safePreviewInsertIndex,
        "taskId": nextTaskId,
      },
    );
    _showSnack(_aiDraftCalendarAddTaskMessage);
  }

  Future<void> _openGeneratedDraftTaskDetailDialog({
    required int phaseIndex,
    required String taskId,
  }) async {
    final generated = _generatedDraft;
    if (generated == null) {
      return;
    }
    if (phaseIndex < 0 || phaseIndex >= generated.draft.phases.length) {
      return;
    }
    final phase = generated.draft.phases[phaseIndex];
    final taskIndex = phase.tasks.indexWhere((entry) => entry.id == taskId);
    if (taskIndex < 0) {
      return;
    }
    final task = phase.tasks[taskIndex];

    final titleController = TextEditingController(text: task.title);
    final instructionsController = TextEditingController(
      text: task.instructions,
    );
    String selectedRole = task.roleRequired;
    String? selectedStaffId = task.assignedStaffId;
    int selectedHeadcount = task.requiredHeadcount < 1
        ? 1
        : task.requiredHeadcount;
    int selectedWeight = task.weight;
    ProductionTaskStatus selectedStatus = task.status;

    List<BusinessStaffProfileSummary> roleScopedStaff() {
      final normalizedRole = selectedRole.trim().toLowerCase();
      return widget.staffProfiles.where((profile) {
        return profile.staffRole.trim().toLowerCase() == normalizedRole;
      }).toList();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final roleStaff = roleScopedStaff();
            final staffStillValid =
                selectedStaffId != null &&
                roleStaff.any((profile) => profile.id == selectedStaffId);
            if (!staffStillValid) {
              selectedStaffId = null;
            }
            final headcountOptions = <int>{
              ..._taskEditorHeadcountOptions,
              if (selectedHeadcount > 10) selectedHeadcount,
            }.toList()..sort();

            return AlertDialog(
              title: const Text(_calendarTaskDetailTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _calendarTaskDetailHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailTaskLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<ProductionTaskStatus>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailStatusLabel,
                      ),
                      items: ProductionTaskStatus.values
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(_taskStatusLabel(status)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedStatus = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailRoleLabel,
                      ),
                      items: staffRoleValues
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(
                                formatStaffRoleLabel(role, fallback: role),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedRole = value;
                          selectedStaffId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: selectedHeadcount,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailHeadcountLabel,
                      ),
                      items: headcountOptions
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setLocalState(() {
                          selectedHeadcount = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStaffId,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailStaffLabel,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text(_selectPlaceholder),
                        ),
                        ...roleStaff.map(
                          (staff) => DropdownMenuItem<String>(
                            value: staff.id,
                            child: Text(
                              staff.userName ?? staff.userEmail ?? staff.id,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setLocalState(() {
                          selectedStaffId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: selectedWeight,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailWeightLabel,
                      ),
                      items: _taskEditorWeightOptions
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() {
                          selectedWeight = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: instructionsController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: _calendarTaskDetailInstructionsLabel,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(_calendarTaskDetailCancel),
                ),
                FilledButton(
                  onPressed: () {
                    final nextTitle = titleController.text.trim();
                    if (nextTitle.isEmpty) {
                      _showSnack(_calendarTaskDetailTaskRequiredMessage);
                      return;
                    }
                    final nextInstructions = instructionsController.text.trim();
                    final nextAssignedIds =
                        selectedStaffId == null ||
                            selectedStaffId!.trim().isEmpty
                        ? const <String>[]
                        : <String>[selectedStaffId!.trim()];
                    final nextRequiredHeadcount =
                        selectedHeadcount < nextAssignedIds.length
                        ? nextAssignedIds.length
                        : selectedHeadcount;
                    final nextAssignedStaffId = nextAssignedIds.isEmpty
                        ? null
                        : nextAssignedIds.first;
                    final updatedTask = task.copyWith(
                      title: nextTitle,
                      roleRequired: selectedRole,
                      assignedStaffId: nextAssignedStaffId,
                      assignedStaffProfileIds: nextAssignedIds,
                      requiredHeadcount: nextRequiredHeadcount,
                      weight: selectedWeight,
                      instructions: nextInstructions,
                      status: selectedStatus,
                      completedAt: selectedStatus == ProductionTaskStatus.done
                          ? DateTime.now()
                          : null,
                      completedByStaffId:
                          selectedStatus == ProductionTaskStatus.done
                          ? nextAssignedStaffId
                          : null,
                    );
                    final nextPhaseTasks = <ProductionTaskDraft>[
                      ...phase.tasks,
                    ];
                    nextPhaseTasks[taskIndex] = updatedTask;
                    final nextPhases = <ProductionPhaseDraft>[
                      ...generated.draft.phases,
                    ];
                    nextPhases[phaseIndex] = phase.copyWith(
                      tasks: nextPhaseTasks,
                    );
                    final updatedDraft = generated.draft.copyWith(
                      phases: nextPhases,
                    );

                    final previewTaskIndex = generated.tasks.indexWhere(
                      (entry) => entry.id == task.id,
                    );
                    final updatedPreviewTasks = <ProductionAiDraftTaskPreview>[
                      ...generated.tasks,
                    ];
                    if (previewTaskIndex >= 0) {
                      final basePreviewTask = generated.tasks[previewTaskIndex];
                      final hasShortage = generated.capacity != null
                          ? nextRequiredHeadcount >
                                generated.capacity!.availableForRole(
                                  selectedRole,
                                )
                          : basePreviewTask.hasShortage;
                      updatedPreviewTasks[previewTaskIndex] =
                          ProductionAiDraftTaskPreview(
                            id: basePreviewTask.id,
                            title: nextTitle,
                            phaseName: phase.name,
                            roleRequired: selectedRole,
                            requiredHeadcount: nextRequiredHeadcount,
                            assignedCount: nextAssignedIds.length,
                            assignedStaffProfileIds: nextAssignedIds,
                            status: _taskStatusApiValue(selectedStatus),
                            startDate: basePreviewTask.startDate,
                            dueDate: basePreviewTask.dueDate,
                            instructions: nextInstructions,
                            hasShortage: hasShortage,
                          );
                    }

                    setState(() {
                      _generatedDraft = ProductionAiDraftResult(
                        draft: updatedDraft,
                        status: generated.status,
                        partialIssue: generated.partialIssue,
                        message: generated.message,
                        summary: generated.summary,
                        schedulePolicy: generated.schedulePolicy,
                        capacity: generated.capacity,
                        warnings: generated.warnings,
                        tasks: updatedPreviewTasks,
                      );
                    });

                    AppDebug.log(
                      _logTag,
                      _calendarTaskDetailSaved,
                      extra: {
                        _extraPhaseKey: phase.name,
                        _extraTaskIdKey: task.id,
                        _extraRoleKey: selectedRole,
                        "requiredHeadcount": nextRequiredHeadcount,
                        "assignedCount": nextAssignedIds.length,
                      },
                    );

                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text(_calendarTaskDetailSave),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _resolvePhaseIndexForCalendarPreview({
    required List<ProductionPhaseDraft> phases,
    required String phaseNameHint,
    required DateTime day,
    required DateTime? planStartDate,
    required DateTime? planEndDate,
  }) {
    // WHY: Calendar add-task should map by selected day first so phase tags align
    // with date ranges instead of defaulting to the first phase.
    final dateMappedPhaseIndex = _resolvePhaseIndexByPlanDateRange(
      phases: phases,
      day: day,
      planStartDate: planStartDate,
      planEndDate: planEndDate,
    );
    if (dateMappedPhaseIndex != null) {
      return dateMappedPhaseIndex;
    }

    final normalizedHint = phaseNameHint.trim().toLowerCase();
    if (normalizedHint.isEmpty) {
      return 0;
    }

    final exactIndex = phases.indexWhere(
      (phase) => phase.name.trim().toLowerCase() == normalizedHint,
    );
    if (exactIndex >= 0) {
      return exactIndex;
    }

    final partialIndex = phases.indexWhere(
      (phase) =>
          phase.name.trim().toLowerCase().contains(normalizedHint) ||
          normalizedHint.contains(phase.name.trim().toLowerCase()),
    );
    if (partialIndex >= 0) {
      return partialIndex;
    }

    return 0;
  }

  int? _resolvePhaseIndexByPlanDateRange({
    required List<ProductionPhaseDraft> phases,
    required DateTime day,
    required DateTime? planStartDate,
    required DateTime? planEndDate,
  }) {
    if (phases.isEmpty || planStartDate == null || planEndDate == null) {
      return null;
    }

    final normalizedStart = DateTime.utc(
      planStartDate.year,
      planStartDate.month,
      planStartDate.day,
      0,
      0,
      0,
      0,
      0,
    );
    var normalizedEnd = DateTime.utc(
      planEndDate.year,
      planEndDate.month,
      planEndDate.day,
      23,
      59,
      59,
      999,
      999,
    );
    if (!normalizedEnd.isAfter(normalizedStart)) {
      normalizedEnd = normalizedStart.add(const Duration(days: 1));
    }

    final dayPivotUtc = DateTime.utc(
      day.year,
      day.month,
      day.day,
      12,
      0,
      0,
      0,
      0,
    );
    if (dayPivotUtc.isBefore(normalizedStart)) {
      return 0;
    }
    if (dayPivotUtc.isAfter(normalizedEnd)) {
      return phases.length - 1;
    }

    final totalMs =
        normalizedEnd.millisecondsSinceEpoch -
        normalizedStart.millisecondsSinceEpoch;
    final phaseCount = phases.length;
    if (phaseCount <= 0) {
      return null;
    }
    final rawBaseMs = totalMs ~/ phaseCount;
    final baseMs = rawBaseMs <= 0 ? 1 : rawBaseMs;

    var cursorMs = normalizedStart.millisecondsSinceEpoch;
    final dayMs = dayPivotUtc.millisecondsSinceEpoch;
    for (var index = 0; index < phaseCount; index += 1) {
      final isLast = index == phaseCount - 1;
      final phaseEndMs = isLast
          ? normalizedEnd.millisecondsSinceEpoch
          : cursorMs + baseMs;
      final inPhase =
          dayMs >= cursorMs &&
          (isLast ? dayMs <= phaseEndMs : dayMs < phaseEndMs);
      if (inPhase) {
        return index;
      }
      cursorMs = phaseEndMs;
    }

    return phaseCount - 1;
  }

  int _flattenedTaskOffsetForPhase({
    required List<ProductionPhaseDraft> phases,
    required int phaseIndex,
  }) {
    var offset = 0;
    for (var index = 0; index < phaseIndex; index += 1) {
      offset += phases[index].tasks.length;
    }
    return offset;
  }

  DateTime _resolveCalendarDayTaskStart({
    required DateTime day,
    required ProductionAiDraftSchedulePolicy? policy,
  }) {
    final firstBlock = policy?.blocks.isNotEmpty == true
        ? policy!.blocks.first
        : null;
    final parsedStart = _parseClockToHourMinute(firstBlock?.start);
    final hour = parsedStart?.$1 ?? 9;
    final minute = parsedStart?.$2 ?? 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  DateTime _resolveCalendarDayTaskEnd({
    required DateTime startLocal,
    required ProductionAiDraftSchedulePolicy? policy,
  }) {
    final minSlot = policy?.minSlotMinutes ?? 60;
    final safeMinSlot = minSlot.clamp(15, 240);
    var due = startLocal.add(Duration(minutes: safeMinSlot));

    final firstBlock = policy?.blocks.isNotEmpty == true
        ? policy!.blocks.first
        : null;
    final parsedEnd = _parseClockToHourMinute(firstBlock?.end);
    if (parsedEnd != null) {
      final blockEnd = DateTime(
        startLocal.year,
        startLocal.month,
        startLocal.day,
        parsedEnd.$1,
        parsedEnd.$2,
      );
      if (due.isAfter(blockEnd)) {
        due = blockEnd.isAfter(startLocal)
            ? blockEnd
            : startLocal.add(const Duration(minutes: 30));
      }
    }

    return due;
  }

  (int, int)? _parseClockToHourMinute(String? value) {
    final raw = (value ?? "").trim();
    if (raw.isEmpty) {
      return null;
    }
    final parts = raw.split(":");
    if (parts.length < 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return (hour, minute);
  }

  void _onDraftOverridesChanged(
    Map<int, ProductionDraftTaskOverride> overrides,
  ) {
    // WHY: Parent consumes preview staffing edits only when user applies draft.
    _draftTaskOverrides = Map<int, ProductionDraftTaskOverride>.from(overrides);
    AppDebug.log(
      _logTag,
      "ai_draft_preview_overrides_changed",
      extra: {"overrideCount": _draftTaskOverrides.length},
    );
  }

  List<String> _resolveAssignedStaffProfileIds({
    required ProductionTaskDraft baseTask,
    required ProductionDraftTaskOverride? override,
  }) {
    final source = override?.assignedStaffProfileIds != null
        ? override!.assignedStaffProfileIds!
        : baseTask.assignedStaffProfileIds;
    final normalized = source
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final legacyAssignedId = baseTask.assignedStaffId?.trim() ?? "";
    if (legacyAssignedId.isNotEmpty && !normalized.contains(legacyAssignedId)) {
      normalized.insert(0, legacyAssignedId);
    }
    return normalized;
  }

  ProductionPlanDraftState _buildDraftWithOverrides(
    ProductionPlanDraftState draft,
  ) {
    if (_draftTaskOverrides.isEmpty) {
      return draft;
    }

    var taskCursor = 0;
    final updatedPhases = draft.phases.map((phase) {
      final updatedTasks = phase.tasks.map((task) {
        final override = _draftTaskOverrides[taskCursor];
        taskCursor += 1;
        if (override == null) {
          return task;
        }

        final nextHeadcount = override.requiredHeadcount != null
            ? (override.requiredHeadcount! < 1
                  ? 1
                  : override.requiredHeadcount!)
            : task.requiredHeadcount;
        final nextAssignedIds = _resolveAssignedStaffProfileIds(
          baseTask: task,
          override: override,
        );
        // WHY: Persisted draft should not carry fewer required slots than selected assignees.
        final normalizedHeadcount = nextAssignedIds.length > nextHeadcount
            ? nextAssignedIds.length
            : nextHeadcount;

        return task.copyWith(
          requiredHeadcount: normalizedHeadcount,
          assignedStaffProfileIds: nextAssignedIds,
          assignedStaffId: nextAssignedIds.isEmpty
              ? null
              : nextAssignedIds.first,
        );
      }).toList();

      return phase.copyWith(tasks: updatedTasks);
    }).toList();

    return draft.copyWith(phases: updatedPhases);
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
    final generatedDraft = _generatedDraft;
    final generatedSummary = generatedDraft?.summary;
    final summaryValues = [
      (
        label: _aiSummaryTasksLabel,
        value:
            generatedDraft?.tasks.length.toString() ??
            widget.draft.totalTasks.toString(),
      ),
      (
        label: _aiSummaryDaysLabel,
        value:
            generatedSummary?.days.toString() ??
            widget.draft.totalEstimatedDays.toString(),
      ),
      (label: "Weeks", value: generatedSummary?.weeks.toString() ?? "-"),
      (
        label: "Month approx",
        value: generatedSummary?.monthApprox.toString() ?? "-",
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
        if (_uiState == _AiDraftUiState.success) ...[
          const SizedBox(height: _fieldSpacing),
          _AiInlineStatusBanner(
            message: generatedDraft == null
                ? _aiDraftSuccessInlineMessage
                : _aiDraftReadyToApplyMessage,
            icon: Icons.check_circle_outline,
          ),
        ],
        if (_uiState == _AiDraftUiState.partial &&
            _lastPartialIssue != null) ...[
          const SizedBox(height: _fieldSpacing),
          _AiDraftPartialPanel(
            issue: _lastPartialIssue!,
            onEditDescription: () {
              // WHY: Prompt focus helps users quickly refine context.
              _assistantPromptFocusNode.requestFocus();
            },
            onSelectProduct: () {
              // WHY: Product reminder keeps draft progress moving toward final save.
              _showSnack(_aiDraftPartialProductHint);
            },
            onRetry: _generateDraft,
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
        if (generatedDraft != null) ...[
          const SizedBox(height: _fieldSpacing),
          if (generatedDraft.warnings.isNotEmpty)
            _AiWarningsCard(warnings: generatedDraft.warnings),
          if (generatedDraft.warnings.isNotEmpty)
            const SizedBox(height: _fieldSpacing),
          ProductionDraftCalendarPreview(
            tasks: generatedDraft.tasks,
            schedulePolicy: generatedDraft.schedulePolicy,
            staffProfiles: widget.staffProfiles,
            onOverridesChanged: _onDraftOverridesChanged,
            onAddTaskForDay: _onPreviewAddTaskForDay,
          ),
          const SizedBox(height: _fieldSpacing),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyGeneratedDraft,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(_aiDraftApplyButtonLabel),
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
          "Retry the draft generation after updating focused roles or staff selection.",
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

class _AiWarningsCard extends StatelessWidget {
  final List<String> warnings;

  const _AiWarningsCard({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final colors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: AppStatusTone.warning,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_fieldSpacing),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Warnings",
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ...warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                "- $warning",
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.foreground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiDraftPartialPanel extends StatelessWidget {
  final ProductionAiDraftPartialIssue issue;
  final VoidCallback onEditDescription;
  final VoidCallback onSelectProduct;
  final VoidCallback onRetry;

  const _AiDraftPartialPanel({
    required this.issue,
    required this.onEditDescription,
    required this.onSelectProduct,
    required this.onRetry,
  });

  String _resolveDescription() {
    switch (issue.issueType) {
      case _aiDraftPartialProductIssue:
        return _aiDraftPartialProductDescription;
      case _aiDraftPartialDateIssue:
        return _aiDraftPartialDateDescription;
      case _aiDraftPartialSchemaIssue:
        return _aiDraftPartialSchemaDescription;
      case _aiDraftPartialContextIssue:
        return _aiDraftPartialContextDescription;
      default:
        return issue.message.trim().isNotEmpty
            ? issue.message
            : _aiDraftPartialContextDescription;
    }
  }

  String _resolveGoodNewsValue() {
    if (issue.issueType == _aiDraftPartialSchemaIssue) {
      return _aiDraftPartialSchemaGoodNewsValue;
    }
    return _aiDraftPartialGoodNewsValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = _resolveDescription();
    final goodNewsValue = _resolveGoodNewsValue();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_fieldSpacing),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _aiDraftPartialTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _aiDraftPartialGoodNewsLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            goodNewsValue,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _aiDraftPartialActionsLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          _AiPartialActionLine(
            icon: Icons.edit_outlined,
            label: _aiDraftPartialEditAction,
          ),
          _AiPartialActionLine(
            icon: Icons.inventory_2_outlined,
            label: _aiDraftPartialSelectProductAction,
          ),
          _AiPartialActionLine(
            icon: Icons.refresh,
            label: _aiDraftPartialRetryAction,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onEditDescription,
                icon: const Icon(Icons.edit_outlined),
                label: const Text(_aiDraftPartialEditAction),
              ),
              OutlinedButton.icon(
                onPressed: onSelectProduct,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text(_aiDraftPartialSelectProductAction),
              ),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text(_aiDraftPartialRetryAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiPartialActionLine extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AiPartialActionLine({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
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
            "${error.classification} - ${error.errorCode}",
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
