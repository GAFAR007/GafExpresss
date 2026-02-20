/// lib/app/features/home/presentation/production/production_plan_assistant_screen.dart
/// --------------------------------------------------------------------------------
/// WHAT:
/// - Chat-first assistant screen for creating production plans.
///
/// HOW:
/// - Captures estate/product/date context.
/// - Sends each user turn to the backend assistant endpoint.
/// - Applies returned `plan_draft` into the existing create-plan draft state.
///
/// WHY:
/// - Keeps onboarding simple: users can talk first, then review/edit in form.
/// - Reuses existing plan editor so no duplicate save logic is introduced.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_product_form_sheet.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/product_ai_model.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/production/production_assistant_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';

const String _logTag = "PRODUCTION_ASSISTANT_SCREEN";
const String _buildLog = "build()";
const String _sendTurnLog = "send_turn";
const String _sendSuccessLog = "send_success";
const String _sendFailureLog = "send_failure";
const String _openEditorLog = "open_editor";
const String _applyDraftLog = "apply_draft";
const String _focusedDraftEnforcedLog = "focused_draft_enforced";
const String _suggestionTapLog = "suggestion_tap";
const String _choiceTapLog = "choice_tap";
const String _strictGenerateTapLog = "strict_generate_tap";
const String _focusedRoleToggleLog = "focused_role_toggle";
const String _focusedStaffToggleLog = "focused_staff_toggle";
const String _focusedStaffBulkToggleLog = "focused_staff_bulk_toggle";
const String _quickProductSelectTapLog = "quick_product_select_tap";
const String _strictCreateProductTapLog = "strict_create_product_tap";
const String _strictCreateProductSuccessLog = "strict_create_product_success";
const String _createSuggestedProductTapLog = "create_suggested_product_tap";
const String _createSuggestedProductSuccessLog =
    "create_suggested_product_success";

const String _screenTitle = "AI production assistant";
const String _manualEditorTooltip = "Open editor";
const String _welcomeMessage =
    "Let's collect context first: choose estate, choose product or create one, then generate the full timeline draft.";
const String _useDraftButtonLabel = "Draft production";
const String _noPlanDraftMessage =
    "No draft yet. Select estate + product, then generate draft from context.";
const String _createSuggestedProductLabel = "Create Suggested Product";
const String _assistantErrorMessage = "Assistant request failed. Please retry.";
const String _contextPromptTitle = "Context-first planning";
const String _contextPromptGenerateLabel = "Generate draft from context";
const String _contextPromptCreateProductLabel = "Create new product";
const String _contextPromptMissingContextMessage =
    "Select estate and product first, then generate draft.";
const String _contextPromptQuickProductLabel = "Quick product picks";
const String _contextPromptGeneratingLabel = "Generating...";
const String _contextPromptSkipDatesLabel = "Use AI inferred dates";
const String _guideQuestionBusinessType =
    "What business type are you planning for?";
const String _guideQuestionEstate = "Nice. Which estate should I plan for?";
const String _guideQuestionProduct =
    "Great. Use an existing product or create a new product.";
const String _guideQuestionRoleStaff =
    "Great. Select roles and staff I should prioritize in this production.";
const String _guideQuestionDates =
    "Do you want to set dates now, or let me infer dates from lifecycle?";
const String _guideQuestionReady =
    "Perfect. I have enough context. Generate your full draft timeline.";
const String _guideContextLabelPrefix = "Current context";
const String _draftPlanSheetTitle = "Draft production schedule";
const String _draftPlanSheetEmpty = "No scheduled tasks were generated.";
const String _draftPlanCloseLabel = "Close";
const String _draftPlanContinueLabel = "Draft production";
const String _contextPromptRoleFocusLabel = "Focus roles";
const String _contextPromptRoleFocusHint =
    "Pick role groups you want AI to prioritize in this production.";
const String _contextPromptStaffFocusLabel = "Preferred staff";
const String _contextPromptStaffFocusHint =
    "Pick staff members AI should prioritize first for these role tracks.";
const String _contextPromptNoStaffInEstate =
    "No staff IDs are linked to this estate yet. You can continue without staff context.";
const String _contextPromptStaffLoading = "Loading estate staff IDs...";
const String _contextPromptConfirmStaffContextLabel =
    "Continue with selected roles and staff";
const String _contextPromptConfirmStaffContextMissing =
    "Select at least one role and one staff ID before continuing.";

const int _queryPage = 1;
const int _queryLimit = 50;
const String _assetTypeEstate = "estate";

// WHY: Give the assistant explicit role-to-task capability hints to reduce role/task mismatch.
const Map<String, List<String>> _assistantRoleTaskKeywordHints = {
  staffRoleFarmer: [
    "field preparation",
    "soil",
    "moisture",
    "plant",
    "stand count",
    "irrigation",
    "nutrient",
    "weed",
    "pest",
    "harvest",
  ],
  staffRoleFieldAgent: [
    "monitor",
    "inspection",
    "inspect",
    "scout",
    "survey",
    "sampling",
    "observation",
    "field check",
  ],
  staffRoleFarmManager: [
    "plan",
    "planning",
    "schedule",
    "supervise",
    "coordination",
    "resource",
    "allocation",
  ],
  staffRoleEstateManager: [
    "approval",
    "oversight",
    "compliance",
    "audit",
    "budget",
    "procurement",
  ],
  staffRoleMaintenanceTechnician: [
    "maintenance",
    "repair",
    "equipment",
    "machine",
    "tractor",
    "pump",
    "generator",
  ],
  staffRoleSecurity: ["security", "patrol", "guard", "gate", "access"],
  staffRoleCleaner: ["clean", "cleanup", "sanitation", "hygiene", "waste"],
  staffRoleInventoryKeeper: [
    "inventory",
    "stock",
    "store",
    "warehouse",
    "issuance",
    "receiving",
  ],
  staffRoleLogisticsDriver: [
    "transport",
    "delivery",
    "dispatch",
    "logistics",
    "haul",
  ],
  staffRoleAccountant: [
    "cost",
    "expense",
    "invoice",
    "payment",
    "reconciliation",
  ],
  staffRoleAuditor: ["audit", "verification", "review records", "compliance"],
  staffRoleAssetManager: [
    "asset",
    "asset tracking",
    "asset inspection",
    "asset register",
  ],
};

class ProductionPlanAssistantScreen extends ConsumerStatefulWidget {
  const ProductionPlanAssistantScreen({super.key});

  @override
  ConsumerState<ProductionPlanAssistantScreen> createState() =>
      _ProductionPlanAssistantScreenState();
}

class _ProductionPlanAssistantScreenState
    extends ConsumerState<ProductionPlanAssistantScreen> {
  final ScrollController _messagesScrollCtrl = ScrollController();
  final Set<String> _focusedRoleKeys = <String>{};
  final Set<String> _focusedStaffProfileIds = <String>{};
  bool _hasConfirmedStaffContext = false;

  String? _selectedEstateAssetId;
  String? _selectedProductId;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _useAiInferredDates = false;
  String _domainContext = productionDomainDefault;
  bool _domainExplicitlySelected = false;
  bool _isSending = false;
  String _lastAutoGenerateKey = "";
  final List<_ChatMessage> _messages = [];
  ProductionAssistantTurn? _lastTurn;

  static const Map<String, List<String>> _domainProductKeywords = {
    productionDomainFarm: [
      "rice",
      "bean",
      "maize",
      "cassava",
      "yam",
      "wheat",
      "crop",
      "seed",
      "plant",
      "paddy",
      "tomato",
      "pepper",
    ],
    productionDomainFashion: [
      "shoe",
      "sneaker",
      "shirt",
      "dress",
      "bag",
      "wear",
      "fashion",
      "jacket",
      "jean",
      "trouser",
    ],
    productionDomainFood: [
      "food",
      "snack",
      "meal",
      "bread",
      "drink",
      "juice",
      "sauce",
      "oil",
      "spice",
      "flour",
    ],
    productionDomainCosmetics: [
      "cream",
      "soap",
      "lotion",
      "powder",
      "perfume",
      "cosmetic",
      "serum",
      "oil",
    ],
    productionDomainManufacturing: [
      "part",
      "component",
      "assembly",
      "machine",
      "material",
      "pack",
      "carton",
      "unit",
    ],
    productionDomainConstruction: [
      "cement",
      "block",
      "brick",
      "tile",
      "beam",
      "pipe",
      "paint",
      "wood",
    ],
    productionDomainMedia: [
      "content",
      "video",
      "audio",
      "podcast",
      "ad",
      "campaign",
      "media",
    ],
  };

  @override
  void initState() {
    super.initState();
    // WHY: Greeting message keeps the empty screen actionable immediately.
    _messages.add(
      const _ChatMessage(fromAssistant: true, text: _welcomeMessage),
    );
    _messages.add(
      const _ChatMessage(fromAssistant: true, text: _guideQuestionBusinessType),
    );
  }

  @override
  void dispose() {
    _messagesScrollCtrl.dispose();
    super.dispose();
  }

  void _appendMessage(_ChatMessage message) {
    setState(() => _messages.add(message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollCtrl.hasClients) return;
      _messagesScrollCtrl.animateTo(
        _messagesScrollCtrl.position.maxScrollExtent + 72,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _appendAssistantMessageOnce(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_messages.isNotEmpty) {
      final last = _messages.last;
      if (last.fromAssistant && last.text.trim() == trimmed) {
        return;
      }
    }
    _appendMessage(_ChatMessage(fromAssistant: true, text: trimmed));
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendTurn({String? forcedMessage}) async {
    if (_isSending) return;
    final outbound = (forcedMessage ?? "").trim();
    if (outbound.isEmpty) return;

    AppDebug.log(
      _logTag,
      _sendTurnLog,
      extra: {
        "hasEstate": (_selectedEstateAssetId ?? "").isNotEmpty,
        "hasProduct": (_selectedProductId ?? "").isNotEmpty,
        "hasStartDate": _startDate != null,
        "hasEndDate": _endDate != null,
        "focusedRoleCount": _focusedRoleKeys.length,
        "focusedStaffCount": _focusedStaffProfileIds.length,
      },
    );

    _appendMessage(_ChatMessage(fromAssistant: false, text: outbound));
    setState(() => _isSending = true);

    try {
      final focusedRoles = _focusedRoleKeys.toList()..sort();
      final staffProfiles =
          ref.read(productionStaffProvider).valueOrNull ??
          const <BusinessStaffProfileSummary>[];
      final focusedStaffProfiles = _selectedFocusedStaffProfiles(
        staffProfiles: staffProfiles,
      );
      final focusedStaffProfilesPayload = _buildFocusedStaffProfilesPayload(
        focusedStaffProfiles: focusedStaffProfiles,
      );
      final focusedStaffByRolePayload =
          _buildFocusedStaffProfileIdsByRolePayload(
            focusedStaffProfilesPayload: focusedStaffProfilesPayload,
          );
      final turnResponse = await ref
          .read(productionPlanActionsProvider)
          .runAssistantTurn(
            payload: {
              "userInput": outbound,
              "estateAssetId": _selectedEstateAssetId ?? "",
              "productId": _selectedProductId ?? "",
              "startDate": _startDate == null
                  ? ""
                  : formatDateInput(_startDate!),
              "endDate": _endDate == null ? "" : formatDateInput(_endDate!),
              "domainContext": _domainContext,
              "businessType": _domainContext,
              "focusedRoles": focusedRoles,
              "focusedStaffProfileIds": _focusedStaffProfileIds.toList()
                ..sort(),
              "focusedStaffProfiles": focusedStaffProfilesPayload,
              "focusedStaffByRole": focusedStaffByRolePayload,
              "focusedRoleTaskHints": {
                for (final role in focusedRoles)
                  role:
                      _assistantRoleTaskKeywordHints[_normalizeRoleKey(role)] ??
                      const <String>[],
              },
              "cropSubtype": "",
            },
          );
      final assistantText = turnResponse.turn.message.isNotEmpty
          ? turnResponse.turn.message
          : turnResponse.message;
      _appendMessage(_ChatMessage(fromAssistant: true, text: assistantText));
      final resolvedTurn = _applyFocusedContextToPlanDraftTurn(
        turn: turnResponse.turn,
      );
      setState(() => _lastTurn = resolvedTurn);
      AppDebug.log(
        _logTag,
        _sendSuccessLog,
        extra: {
          "action": resolvedTurn.action,
          "hasPlanDraft": resolvedTurn.planDraftPayload != null,
        },
      );
    } catch (error) {
      AppDebug.log(
        _logTag,
        _sendFailureLog,
        extra: {"error": error.toString()},
      );
      _appendMessage(
        _ChatMessage(
          fromAssistant: true,
          text: _assistantErrorMessage,
          isError: true,
        ),
      );
      _showSnack(_assistantErrorMessage);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(kDatePickerFirstYear),
      lastDate: DateTime(kDatePickerLastYear),
      initialDate: initialDate,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      // WHY: Manual date picking should switch away from AI-inferred date mode.
      _useAiInferredDates = false;
      _lastAutoGenerateKey = "";
    });
    if (_startDate != null && _endDate != null) {
      _appendAssistantMessageOnce(_resolveGuideQuestion());
      _tryAutoGenerateDraftFromContext(
        trigger: "manual_dates_ready",
        inferredMode: false,
      );
      return;
    }
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  Future<void> _openManualEditor() async {
    final notifier = ref.read(productionPlanDraftProvider.notifier);
    // WHY: Manual editor entry should still preserve selected context.
    notifier.reset();
    notifier.updateDomainContext(_domainContext);
    notifier.updateEstate(_selectedEstateAssetId);
    notifier.updateProduct(_selectedProductId);
    notifier.updateStartDate(_startDate);
    notifier.updateEndDate(_endDate);
    AppDebug.log(_logTag, _openEditorLog, extra: {"mode": "manual"});
    if (!mounted) return;
    context.push(productionPlanCreateRoute);
  }

  Future<void> _createSuggestedProduct(
    ProductionAssistantDraftProductPayload payload,
  ) async {
    AppDebug.log(_logTag, _createSuggestedProductTapLog);
    final initialDraft = ProductDraft(
      name: payload.createProductPayload.name,
      description: payload.createProductPayload.notes,
      priceNgn: 0,
      stock: 0,
      imageUrl: "",
    );
    final created = await showBusinessProductFormSheet(
      context: context,
      initialDraft: initialDraft,
      onSuccess: (_) async {
        ref.invalidate(
          businessProductsProvider(
            const BusinessProductsQuery(page: _queryPage, limit: _queryLimit),
          ),
        );
      },
    );
    if (created == null) {
      return;
    }
    setState(() => _selectedProductId = created.id);
    AppDebug.log(
      _logTag,
      _createSuggestedProductSuccessLog,
      extra: {"productId": created.id},
    );
    _showSnack("Suggested product created and selected.");
  }

  Future<void> _createProductFromContext() async {
    AppDebug.log(_logTag, _strictCreateProductTapLog);
    final created = await showBusinessProductFormSheet(
      context: context,
      onSuccess: (_) async {
        ref.invalidate(
          businessProductsProvider(
            const BusinessProductsQuery(page: _queryPage, limit: _queryLimit),
          ),
        );
      },
    );
    if (created == null) {
      return;
    }
    setState(() => _selectedProductId = created.id);
    AppDebug.log(
      _logTag,
      _strictCreateProductSuccessLog,
      extra: {"productId": created.id},
    );
    _showSnack("Product created and selected.");
  }

  Future<void> _applyDraftAndOpenEditor(
    ProductionAssistantPlanDraftPayload payload,
  ) async {
    final scopedPayload = _sanitizePlanDraftPayloadForFocusedContext(
      payload: payload,
    );
    final resolvedProductId = scopedPayload.productId.trim().isNotEmpty
        ? scopedPayload.productId
        : (_selectedProductId ?? "");
    final phases = scopedPayload.phases
        .map(
          (phase) => ProductionPhaseDraft(
            name: phase.name.isEmpty ? "Phase ${phase.order}" : phase.name,
            order: phase.order < 1 ? 1 : phase.order,
            estimatedDays: phase.estimatedDays < 1 ? 1 : phase.estimatedDays,
            tasks: phase.tasks
                .asMap()
                .entries
                .map(
                  (entry) => ProductionTaskDraft(
                    id: "assistant_${phase.order}_${entry.key}_${DateTime.now().millisecondsSinceEpoch}",
                    title: entry.value.title.isEmpty
                        ? "Task"
                        : _normalizeLifecycleTaskTitle(entry.value.title),
                    roleRequired: entry.value.roleRequired.isEmpty
                        ? "farmer"
                        : entry.value.roleRequired,
                    assignedStaffId: entry.value.assignedStaffProfileIds.isEmpty
                        ? null
                        : entry.value.assignedStaffProfileIds.first,
                    assignedStaffProfileIds:
                        entry.value.assignedStaffProfileIds,
                    requiredHeadcount: entry.value.requiredHeadcount < 1
                        ? 1
                        : entry.value.requiredHeadcount,
                    weight: entry.value.weight < 1 ? 1 : entry.value.weight,
                    instructions: entry.value.instructions,
                    status: ProductionTaskStatus.notStarted,
                    completedAt: null,
                    completedByStaffId: null,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    final totalTasks = phases.fold<int>(
      0,
      (sum, phase) => sum + phase.tasks.length,
    );
    final startDate = DateTime.tryParse(scopedPayload.startDate);
    final endDate = DateTime.tryParse(scopedPayload.endDate);
    final riskNotes = scopedPayload.warnings
        .map((warning) => warning.message.trim())
        .where((message) => message.isNotEmpty)
        .toList();

    // WHY: Apply assistant draft into the existing create form state.
    final nextState = ProductionPlanDraftState(
      title:
          "${scopedPayload.productName.isEmpty ? 'Production' : scopedPayload.productName} Plan",
      notes: _messages
          .where((message) => message.fromAssistant)
          .map((message) => message.text.trim())
          .where((message) => message.isNotEmpty)
          .take(2)
          .join("\n"),
      domainContext: _domainContext,
      estateAssetId: _selectedEstateAssetId,
      productId: resolvedProductId.isEmpty ? null : resolvedProductId,
      startDate: startDate,
      endDate: endDate,
      proposedProduct: null,
      productAiSuggested: false,
      startDateAiSuggested: false,
      endDateAiSuggested: false,
      aiGenerated: true,
      totalTasks: totalTasks,
      totalEstimatedDays: scopedPayload.days > 0 ? scopedPayload.days : 1,
      riskNotes: riskNotes,
      phases: phases,
    );
    ref.read(productionPlanDraftProvider.notifier).applyDraft(nextState);
    AppDebug.log(
      _logTag,
      _applyDraftLog,
      extra: {
        "weeks": scopedPayload.weeks,
        "days": scopedPayload.days,
        "taskCount": totalTasks,
      },
    );
    if (!mounted) return;
    context.push(productionPlanCreateRoute);
  }

  DateTime _startOfWeekMonday(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  String _formatTaskTime(DateTime? value) {
    if (value == null) return "--:--";
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, "0");
    final minute = local.minute.toString().padLeft(2, "0");
    return "$hour:$minute";
  }

  List<_AssistantWeeklySchedule> _buildWeeklyScheduleRows(
    ProductionAssistantPlanDraftPayload payload,
  ) {
    final startRaw = DateTime.tryParse(payload.startDate);
    final endRaw = DateTime.tryParse(payload.endDate);
    if (startRaw == null || endRaw == null) {
      AppDebug.log(
        _logTag,
        "draft_schedule_invalid_range",
        extra: {"startDate": payload.startDate, "endDate": payload.endDate},
      );
      return const <_AssistantWeeklySchedule>[];
    }

    final startDate = DateTime(startRaw.year, startRaw.month, startRaw.day);
    final endDate = DateTime(endRaw.year, endRaw.month, endRaw.day);
    final tasksByDay = <String, List<_AssistantScheduleTask>>{};

    for (final phase in payload.phases) {
      for (final task in phase.tasks) {
        if (task.startDate == null || task.dueDate == null) {
          AppDebug.log(
            _logTag,
            "draft_schedule_skip_task_missing_dates",
            extra: {"title": task.title, "phase": phase.name},
          );
          continue;
        }
        final taskStart = task.startDate!.toLocal();
        final taskDue = task.dueDate!.toLocal();
        final day = DateTime(taskStart.year, taskStart.month, taskStart.day);
        final dayKey = formatDateInput(day);
        final list = tasksByDay.putIfAbsent(
          dayKey,
          () => <_AssistantScheduleTask>[],
        );
        final normalizedTitle = _normalizeLifecycleTaskTitle(task.title);
        if (normalizedTitle != task.title) {
          AppDebug.log(
            _logTag,
            "draft_task_title_week_removed",
            extra: {"rawTitle": task.title, "normalizedTitle": normalizedTitle},
          );
        }
        list.add(
          _AssistantScheduleTask(
            title: normalizedTitle,
            phaseName: phase.name,
            roleRequired: task.roleRequired,
            requiredHeadcount: task.requiredHeadcount,
            assignedStaffProfileIds: task.assignedStaffProfileIds,
            startDate: taskStart,
            dueDate: taskDue,
          ),
        );
      }
    }

    for (final entry in tasksByDay.entries) {
      entry.value.sort((left, right) {
        final leftMs = left.startDate.millisecondsSinceEpoch;
        final rightMs = right.startDate.millisecondsSinceEpoch;
        return leftMs.compareTo(rightMs);
      });
    }

    final weeks = <_AssistantWeeklySchedule>[];
    DateTime weekCursor = _startOfWeekMonday(startDate);
    final weekEnd = _startOfWeekMonday(endDate);
    while (!weekCursor.isAfter(weekEnd)) {
      final days = <_AssistantDailySchedule>[];
      for (int offset = 0; offset < 7; offset += 1) {
        final day = weekCursor.add(Duration(days: offset));
        if (day.isBefore(startDate) || day.isAfter(endDate)) {
          continue;
        }
        final dayKey = formatDateInput(day);
        days.add(
          _AssistantDailySchedule(
            date: day,
            tasks: tasksByDay[dayKey] ?? const <_AssistantScheduleTask>[],
          ),
        );
      }
      weeks.add(_AssistantWeeklySchedule(weekStart: weekCursor, days: days));
      weekCursor = weekCursor.add(const Duration(days: 7));
    }

    AppDebug.log(
      _logTag,
      "draft_schedule_grouped",
      extra: {
        "weeks": weeks.length,
        "days": payload.days,
        "taskCount": payload.phases.fold<int>(
          0,
          (sum, phase) => sum + phase.tasks.length,
        ),
      },
    );
    return weeks;
  }

  Future<void> _previewDraftProductionSchedule(
    ProductionAssistantPlanDraftPayload payload,
  ) async {
    final scopedPayload = _sanitizePlanDraftPayloadForFocusedContext(
      payload: payload,
    );
    final weeklyRows = _buildWeeklyScheduleRows(scopedPayload);
    AppDebug.log(
      _logTag,
      "draft_production_preview_open",
      extra: {
        "weeks": weeklyRows.length,
        "days": scopedPayload.days,
        "phaseCount": scopedPayload.phases.length,
      },
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _draftPlanSheetTitle,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Range: ${scopedPayload.startDate} to ${scopedPayload.endDate} (${scopedPayload.weeks} weeks)",
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: weeklyRows.isEmpty
                          ? Center(
                              child: Text(
                                _draftPlanSheetEmpty,
                                style: Theme.of(
                                  sheetContext,
                                ).textTheme.bodyMedium,
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: weeklyRows.length,
                              itemBuilder: (context, weekIndex) {
                                final week = weeklyRows[weekIndex];
                                final weekLabelStart = formatDateLabel(
                                  week.weekStart,
                                );
                                final weekLabelEnd = formatDateLabel(
                                  week.weekStart.add(const Duration(days: 6)),
                                );
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Week ${weekIndex + 1}: $weekLabelStart to $weekLabelEnd",
                                          style: Theme.of(
                                            sheetContext,
                                          ).textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 8),
                                        ...week.days.map((day) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "${_weekdayLabel(day.date.weekday)} ${formatDateLabel(day.date)}",
                                                  style: Theme.of(
                                                    sheetContext,
                                                  ).textTheme.bodyMedium,
                                                ),
                                                const SizedBox(height: 4),
                                                if (day.tasks.isEmpty)
                                                  Text(
                                                    "No task scheduled.",
                                                    style: Theme.of(
                                                      sheetContext,
                                                    ).textTheme.bodySmall,
                                                  )
                                                else
                                                  ...day.tasks.map(
                                                    (task) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 8,
                                                            bottom: 4,
                                                          ),
                                                      child: Text(
                                                        "${_formatTaskTime(task.startDate)} - ${_formatTaskTime(task.dueDate)} | ${_normalizeLifecycleTaskTitle(task.title)} | ${task.roleRequired} x${task.requiredHeadcount}${task.assignedStaffProfileIds.isEmpty ? "" : " | ${task.assignedStaffProfileIds.join(", ")}"}",
                                                        style: Theme.of(
                                                          sheetContext,
                                                        ).textTheme.bodySmall,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text(_draftPlanCloseLabel),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            await _applyDraftAndOpenEditor(scopedPayload);
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text(_draftPlanContinueLabel),
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
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return "Mon";
      case DateTime.tuesday:
        return "Tue";
      case DateTime.wednesday:
        return "Wed";
      case DateTime.thursday:
        return "Thu";
      case DateTime.friday:
        return "Fri";
      case DateTime.saturday:
        return "Sat";
      case DateTime.sunday:
        return "Sun";
      default:
        return "";
    }
  }

  String _buildStrictGeneratePrompt({
    required String estateName,
    required String productName,
    required List<String> focusedRoles,
    required List<BusinessStaffProfileSummary> focusedStaff,
  }) {
    final safeEstate = estateName.trim().isEmpty
        ? "selected estate"
        : estateName.trim();
    final safeProduct = productName.trim().isEmpty
        ? "selected product"
        : productName.trim();
    final startDateText = _startDate == null
        ? ""
        : formatDateInput(_startDate!);
    final endDateText = _endDate == null ? "" : formatDateInput(_endDate!);
    final hasDateRange = startDateText.isNotEmpty && endDateText.isNotEmpty;
    final dateInstruction = hasDateRange
        ? "Use startDate $startDateText and endDate $endDateText."
        : "Infer startDate and endDate from lifecycle and return the total weeks.";
    final roleAlignmentInstruction = _buildRoleAlignmentInstruction(
      focusedRoles: focusedRoles,
    );
    final roleInstruction = focusedRoles.isEmpty
        ? ""
        : " Use ONLY these role tracks for roleRequired: ${focusedRoles.map(formatStaffRoleLabel).join(", ")}. Do not introduce roles outside this list.";
    final focusedStaffProfilesPayload = _buildFocusedStaffProfilesPayload(
      focusedStaffProfiles: focusedStaff,
    );
    final focusedStaffByRolePayload = _buildFocusedStaffProfileIdsByRolePayload(
      focusedStaffProfilesPayload: focusedStaffProfilesPayload,
    );
    final staffByRoleInstruction = focusedStaffByRolePayload.isEmpty
        ? ""
        : " Staff IDs by role: ${focusedStaffByRolePayload.entries.map((entry) => "${formatStaffRoleLabel(entry.key)}=[${entry.value.join(", ")}]").join("; ")}.";
    final staffInstruction = focusedStaff.isEmpty
        ? ""
        : " Assign using these staff profiles (name | role | profileId): ${focusedStaff.map((profile) => "${_resolveAssistantStaffDisplayName(profile)} | ${formatStaffRoleLabel(profile.staffRole)} | ${profile.id}").join("; ")}. assignedStaffProfileIds must be from this list.";
    const lifecycleInstruction =
        " Do not include '(Week N)' inside task titles.";
    return "Generate a strict full production plan for $safeProduct at $safeEstate. $dateInstruction$roleInstruction$roleAlignmentInstruction$staffByRoleInstruction$staffInstruction$lifecycleInstruction Include full-range phases, daily tasks, roleRequired, requiredHeadcount, assignedStaffProfileIds, and warnings.";
  }

  String _resolveSelectedEstateNameFromProvider() {
    final assetsAsync = ref.read(
      businessAssetsProvider(
        const BusinessAssetsQuery(page: _queryPage, limit: _queryLimit),
      ),
    );
    return assetsAsync.maybeWhen(
      data: (result) {
        for (final asset in result.assets) {
          if (asset.assetType != _assetTypeEstate) {
            continue;
          }
          if (asset.id == _selectedEstateAssetId) {
            return asset.name;
          }
        }
        return "";
      },
      orElse: () => "",
    );
  }

  String _resolveSelectedProductNameFromProvider() {
    final productsAsync = ref.read(
      businessProductsProvider(
        const BusinessProductsQuery(page: _queryPage, limit: _queryLimit),
      ),
    );
    return productsAsync.maybeWhen(
      data: (products) {
        for (final product in products) {
          if (product.id == _selectedProductId) {
            return product.name;
          }
        }
        return "";
      },
      orElse: () => "",
    );
  }

  String _buildAutoGenerateKey({required bool inferredMode}) {
    final estateId = (_selectedEstateAssetId ?? "").trim();
    final productId = (_selectedProductId ?? "").trim();
    final startText = _startDate == null ? "" : formatDateInput(_startDate!);
    final endText = _endDate == null ? "" : formatDateInput(_endDate!);
    final dateMode = inferredMode ? "infer" : "$startText|$endText";
    final focusedRoles = _focusedRoleKeys.toList()..sort();
    final focusedStaffIds = _focusedStaffProfileIds.toList()..sort();
    return "$estateId|$productId|$dateMode|$_domainContext|${focusedRoles.join(",")}|${focusedStaffIds.join(",")}";
  }

  Future<void> _tryAutoGenerateDraftFromContext({
    required String trigger,
    required bool inferredMode,
  }) async {
    if (_isSending) return;
    final hasEstate = (_selectedEstateAssetId ?? "").trim().isNotEmpty;
    final hasProduct = (_selectedProductId ?? "").trim().isNotEmpty;
    if (!hasEstate || !hasProduct) {
      return;
    }
    if (!inferredMode && !(_startDate != null && _endDate != null)) {
      return;
    }
    if (!_isFocusedStaffContextReadyForDraft()) {
      AppDebug.log(
        _logTag,
        "auto_generate_waiting_staff_context",
        extra: {
          "trigger": trigger,
          "requiresStaffContext": _requiresFocusedStaffContext(),
          "focusedRoleCount": _focusedRoleKeys.length,
          "focusedStaffCount": _focusedStaffProfileIds.length,
        },
      );
      return;
    }

    final nextKey = _buildAutoGenerateKey(inferredMode: inferredMode);
    if (nextKey == _lastAutoGenerateKey) {
      AppDebug.log(
        _logTag,
        "auto_generate_skipped_duplicate",
        extra: {"trigger": trigger, "key": nextKey},
      );
      return;
    }
    _lastAutoGenerateKey = nextKey;

    final estateName = _resolveSelectedEstateNameFromProvider();
    final productName = _resolveSelectedProductNameFromProvider();
    AppDebug.log(
      _logTag,
      "auto_generate_draft",
      extra: {
        "trigger": trigger,
        "inferredMode": inferredMode,
        "hasStartDate": _startDate != null,
        "hasEndDate": _endDate != null,
      },
    );
    await _generateDraftFromContext(
      estateName: estateName,
      productName: productName,
    );
  }

  String _resolveGuideQuestion() {
    final hasEstate = (_selectedEstateAssetId ?? "").trim().isNotEmpty;
    final hasProduct = (_selectedProductId ?? "").trim().isNotEmpty;
    final hasBothDates = _startDate != null && _endDate != null;
    final hasResolvedDateMode = hasBothDates || _useAiInferredDates;

    if (!_domainExplicitlySelected) {
      return _guideQuestionBusinessType;
    }
    if (!hasEstate) {
      return _guideQuestionEstate;
    }
    if (!hasProduct) {
      return _guideQuestionProduct;
    }
    if (!_isFocusedStaffContextReadyForDraft()) {
      return _guideQuestionRoleStaff;
    }
    if (!hasResolvedDateMode) {
      return _guideQuestionDates;
    }
    return _guideQuestionReady;
  }

  List<Product> _filterQuickProductsByDomain({
    required List<Product> products,
    required String domainContext,
  }) {
    final normalizedDomain = normalizeProductionDomainContext(domainContext);
    final keywords =
        _domainProductKeywords[normalizedDomain] ?? const <String>[];
    if (keywords.isEmpty) {
      return products.take(6).toList();
    }
    final ranked = products.where((product) {
      final text = "${product.name} ${product.description}".toLowerCase();
      return keywords.any((keyword) => text.contains(keyword));
    }).toList();
    if (ranked.isNotEmpty) {
      return ranked.take(6).toList();
    }
    return products.take(6).toList();
  }

  String _normalizeRoleKey(String rawRole) {
    // WHY: Role matching must tolerate snake_case, spaces, and case differences.
    return rawRole
        .trim()
        .toLowerCase()
        .replaceAll("-", "_")
        .replaceAll(" ", "_");
  }

  int _taskRoleMatchScore({
    required String taskTitle,
    required String roleKey,
  }) {
    final normalizedTitle = taskTitle.trim().toLowerCase();
    if (normalizedTitle.isEmpty) {
      return 0;
    }
    final normalizedRole = _normalizeRoleKey(roleKey);
    final hints =
        _assistantRoleTaskKeywordHints[normalizedRole] ?? const <String>[];
    if (hints.isEmpty) {
      return 0;
    }
    var score = 0;
    for (final hint in hints) {
      final keyword = hint.trim().toLowerCase();
      if (keyword.isEmpty) {
        continue;
      }
      if (normalizedTitle.contains(keyword)) {
        score += 1;
      }
    }
    return score;
  }

  String _resolveBestRoleForTaskTitle({
    required String taskTitle,
    required List<String> selectedRoleKeys,
    required Map<String, List<String>> focusedStaffIdsByRole,
  }) {
    final normalizedRoles =
        selectedRoleKeys
            .map(_normalizeRoleKey)
            .where((role) => role.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (normalizedRoles.isEmpty) {
      return staffRoleFarmer;
    }
    final rolesWithStaff = normalizedRoles
        .where(
          (role) =>
              (focusedStaffIdsByRole[role] ?? const <String>[]).isNotEmpty,
        )
        .toSet();
    final candidatePool = rolesWithStaff.isEmpty
        ? normalizedRoles
        : normalizedRoles.where(rolesWithStaff.contains).toList();

    String bestRole = candidatePool.first;
    var bestScore = _taskRoleMatchScore(
      taskTitle: taskTitle,
      roleKey: bestRole,
    );
    for (final roleKey in candidatePool.skip(1)) {
      final score = _taskRoleMatchScore(taskTitle: taskTitle, roleKey: roleKey);
      if (score > bestScore) {
        bestRole = roleKey;
        bestScore = score;
      }
    }
    // WHY: Most production execution tasks should bias to farmer when title is ambiguous.
    if (bestScore == 0 && candidatePool.contains(staffRoleFarmer)) {
      return staffRoleFarmer;
    }
    return bestRole;
  }

  List<Map<String, String>> _buildFocusedStaffProfilesPayload({
    required List<BusinessStaffProfileSummary> focusedStaffProfiles,
  }) {
    final rows = focusedStaffProfiles
        .map((profile) {
          return <String, String>{
            "profileId": profile.id.trim(),
            "role": _normalizeRoleKey(profile.staffRole),
            "name": _resolveAssistantStaffDisplayName(profile),
          };
        })
        .where((row) {
          return (row["profileId"] ?? "").isNotEmpty &&
              (row["role"] ?? "").isNotEmpty;
        })
        .toList();
    rows.sort((left, right) {
      final roleCompare = (left["role"] ?? "").compareTo(right["role"] ?? "");
      if (roleCompare != 0) {
        return roleCompare;
      }
      return (left["profileId"] ?? "").compareTo(right["profileId"] ?? "");
    });
    return rows;
  }

  Map<String, List<String>> _buildFocusedStaffProfileIdsByRolePayload({
    required List<Map<String, String>> focusedStaffProfilesPayload,
  }) {
    final grouped = <String, Set<String>>{};
    for (final row in focusedStaffProfilesPayload) {
      final role = (row["role"] ?? "").trim();
      final profileId = (row["profileId"] ?? "").trim();
      if (role.isEmpty || profileId.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(role, () => <String>{}).add(profileId);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: entry.value.toList()..sort(),
    };
  }

  String _buildRoleAlignmentInstruction({required List<String> focusedRoles}) {
    if (focusedRoles.isEmpty) {
      return "";
    }
    final roleHints = focusedRoles.map((role) {
      final normalizedRole = _normalizeRoleKey(role);
      final hints =
          _assistantRoleTaskKeywordHints[normalizedRole] ?? const <String>[];
      if (hints.isEmpty) {
        return "${formatStaffRoleLabel(normalizedRole)}: keep semantic alignment.";
      }
      return "${formatStaffRoleLabel(normalizedRole)} handles ${hints.take(5).join(", ")}.";
    }).toList();
    return " Role-task alignment rules: ${roleHints.join(" ")} Match each task title to the most suitable selected role.";
  }

  List<String> _normalizeDistinctProfileIds(List<String> ids) {
    // WHY: Keep assignment IDs stable when assistant payload has duplicates.
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  bool _hasSameNormalizedIds(List<String> first, List<String> second) {
    final normalizedFirst = _normalizeDistinctProfileIds(first);
    final normalizedSecond = _normalizeDistinctProfileIds(second);
    if (normalizedFirst.length != normalizedSecond.length) {
      return false;
    }
    for (int index = 0; index < normalizedFirst.length; index += 1) {
      if (normalizedFirst[index] != normalizedSecond[index]) {
        return false;
      }
    }
    return true;
  }

  Map<String, List<String>> _buildFocusedStaffIdsByRole({
    required List<BusinessStaffProfileSummary> estateScopedStaffProfiles,
    required Set<String> focusedStaffProfileIds,
  }) {
    if (focusedStaffProfileIds.isEmpty) {
      return const <String, List<String>>{};
    }
    final grouped = <String, Set<String>>{};
    for (final profile in estateScopedStaffProfiles) {
      final profileId = profile.id.trim();
      if (!focusedStaffProfileIds.contains(profileId)) {
        continue;
      }
      final normalizedRole = _normalizeRoleKey(profile.staffRole);
      if (normalizedRole.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(normalizedRole, () => <String>{}).add(profileId);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: entry.value.toList()..sort(),
    };
  }

  String _resolveFallbackRoleForTask({
    required String taskTitle,
    required List<String> selectedRoleKeys,
    required Map<String, List<String>> focusedStaffIdsByRole,
  }) {
    return _resolveBestRoleForTaskTitle(
      taskTitle: taskTitle,
      selectedRoleKeys: selectedRoleKeys,
      focusedStaffIdsByRole: focusedStaffIdsByRole,
    );
  }

  List<String> _resolveFocusedIdsForTask({
    required String normalizedRole,
    required int requiredHeadcount,
    required List<String> existingAssignedIds,
    required Map<String, List<String>> focusedStaffIdsByRole,
    required Set<String> focusedStaffProfileIds,
  }) {
    final safeHeadcount = requiredHeadcount < 1 ? 1 : requiredHeadcount;
    final roleMatches =
        focusedStaffIdsByRole[normalizedRole] ?? const <String>[];
    if (roleMatches.isNotEmpty) {
      // WHY: Role-matched focused staff should always win in strict mode.
      return roleMatches.take(safeHeadcount).toList();
    }
    if (focusedStaffProfileIds.isEmpty) {
      return _normalizeDistinctProfileIds(existingAssignedIds);
    }
    final existingFocused = _normalizeDistinctProfileIds(
      existingAssignedIds,
    ).where(focusedStaffProfileIds.contains).toList();
    if (existingFocused.isNotEmpty) {
      return existingFocused.take(safeHeadcount).toList();
    }
    final fallback = focusedStaffProfileIds.toList()..sort();
    return fallback.take(safeHeadcount).toList();
  }

  // WHY: Calendar week labels in titles conflict with UI week grouping on this screen.
  String _normalizeLifecycleTaskTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final withoutAnyParenthesizedWeek = trimmed.replaceAll(
      RegExp(
        r"\s*[-–—]?\s*[\(（][^\)）]*\bweek\b[^\)）]*[\)）]",
        caseSensitive: false,
      ),
      "",
    );
    final withoutParenthesizedWeekNumber = withoutAnyParenthesizedWeek
        .replaceAll(
          RegExp(
            r"\s*[-–—]?\s*\(\s*week\s*[-:]?\s*\d+\s*\)",
            caseSensitive: false,
          ),
          "",
        );
    final withoutLooseWeek = withoutParenthesizedWeekNumber.replaceAll(
      RegExp(r"\s*[-–—]?\s*week\s*[-:]?\s*\d+\b", caseSensitive: false),
      "",
    );
    final compact = withoutLooseWeek.replaceAll(RegExp(r"\s{2,}"), " ").trim();
    return compact.replaceAll(RegExp(r"\(\s*\)"), "").trim();
  }

  // WHY: Keep preview/editor text consistent even when provider still emits "(Week N)" in titles.
  ProductionAssistantPlanDraftPayload _normalizeLifecycleLabelsInDraftPayload({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    var normalizedTitleCount = 0;
    final normalizedPhases = payload.phases.map((phase) {
      final normalizedTasks = phase.tasks.map((task) {
        final normalizedTitle = _normalizeLifecycleTaskTitle(task.title);
        if (normalizedTitle == task.title) {
          return task;
        }
        normalizedTitleCount += 1;
        return ProductionAssistantPlanTask(
          title: normalizedTitle,
          roleRequired: task.roleRequired,
          requiredHeadcount: task.requiredHeadcount,
          weight: task.weight,
          instructions: task.instructions,
          startDate: task.startDate,
          dueDate: task.dueDate,
          assignedStaffProfileIds: task.assignedStaffProfileIds,
        );
      }).toList();
      return ProductionAssistantPlanPhase(
        name: phase.name,
        order: phase.order,
        estimatedDays: phase.estimatedDays,
        tasks: normalizedTasks,
      );
    }).toList();
    if (normalizedTitleCount == 0) {
      return payload;
    }
    AppDebug.log(
      _logTag,
      "draft_titles_week_label_removed",
      extra: {
        "phaseCount": payload.phases.length,
        "normalizedTitleCount": normalizedTitleCount,
      },
    );
    return ProductionAssistantPlanDraftPayload(
      productId: payload.productId,
      productName: payload.productName,
      startDate: payload.startDate,
      endDate: payload.endDate,
      days: payload.days,
      weeks: payload.weeks,
      phases: normalizedPhases,
      warnings: payload.warnings,
    );
  }

  ProductionAssistantPlanDraftPayload
  _sanitizePlanDraftPayloadForFocusedContext({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    final lifecycleNormalizedPayload = _normalizeLifecycleLabelsInDraftPayload(
      payload: payload,
    );
    final focusedRoleKeys =
        _focusedRoleKeys
            .map(_normalizeRoleKey)
            .where((role) => role.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final focusedRoleSet = focusedRoleKeys.toSet();
    final focusedStaffProfileIds = _focusedStaffProfileIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (focusedRoleSet.isEmpty && focusedStaffProfileIds.isEmpty) {
      return lifecycleNormalizedPayload;
    }
    final allStaffProfiles =
        ref.read(productionStaffProvider).valueOrNull ??
        const <BusinessStaffProfileSummary>[];
    final estateScopedStaffProfiles = _staffForSelectedEstate(
      staffProfiles: allStaffProfiles,
    );
    final focusedStaffIdsByRole = _buildFocusedStaffIdsByRole(
      estateScopedStaffProfiles: estateScopedStaffProfiles,
      focusedStaffProfileIds: focusedStaffProfileIds,
    );
    var didMutate = false;
    var roleReplacementCount = 0;
    var assignmentReplacementCount = 0;

    final updatedPhases = lifecycleNormalizedPayload.phases.map((phase) {
      final updatedTasks = phase.tasks.map((task) {
        final originalRole = _normalizeRoleKey(task.roleRequired);
        String resolvedRole = originalRole;
        final semanticRole = _resolveBestRoleForTaskTitle(
          taskTitle: task.title,
          selectedRoleKeys: focusedRoleKeys,
          focusedStaffIdsByRole: focusedStaffIdsByRole,
        );
        if (focusedRoleSet.isNotEmpty &&
            !focusedRoleSet.contains(resolvedRole)) {
          resolvedRole = _resolveFallbackRoleForTask(
            taskTitle: task.title,
            selectedRoleKeys: focusedRoleKeys,
            focusedStaffIdsByRole: focusedStaffIdsByRole,
          );
        } else if (focusedRoleSet.isNotEmpty &&
            semanticRole != resolvedRole &&
            _taskRoleMatchScore(taskTitle: task.title, roleKey: semanticRole) >
                _taskRoleMatchScore(
                  taskTitle: task.title,
                  roleKey: resolvedRole,
                )) {
          // WHY: If AI picked a weak role match, prefer the stronger semantic match within selected roles.
          resolvedRole = semanticRole;
        }
        if (resolvedRole.isEmpty) {
          resolvedRole = focusedRoleKeys.isEmpty
              ? "farmer"
              : focusedRoleKeys.first;
        }
        final resolvedAssignedIds = _resolveFocusedIdsForTask(
          normalizedRole: resolvedRole,
          requiredHeadcount: task.requiredHeadcount,
          existingAssignedIds: task.assignedStaffProfileIds,
          focusedStaffIdsByRole: focusedStaffIdsByRole,
          focusedStaffProfileIds: focusedStaffProfileIds,
        );
        final normalizedHeadcount = task.requiredHeadcount < 1
            ? 1
            : task.requiredHeadcount;
        final resolvedHeadcount =
            resolvedAssignedIds.length > normalizedHeadcount
            ? resolvedAssignedIds.length
            : normalizedHeadcount;
        final roleChanged = resolvedRole != originalRole;
        final assignmentChanged = !_hasSameNormalizedIds(
          task.assignedStaffProfileIds,
          resolvedAssignedIds,
        );
        final headcountChanged = resolvedHeadcount != normalizedHeadcount;
        if (!roleChanged && !assignmentChanged && !headcountChanged) {
          return task;
        }
        didMutate = true;
        if (roleChanged) {
          roleReplacementCount += 1;
        }
        if (assignmentChanged) {
          assignmentReplacementCount += 1;
        }
        return ProductionAssistantPlanTask(
          title: task.title,
          roleRequired: resolvedRole,
          requiredHeadcount: resolvedHeadcount,
          weight: task.weight,
          instructions: task.instructions,
          startDate: task.startDate,
          dueDate: task.dueDate,
          assignedStaffProfileIds: resolvedAssignedIds,
        );
      }).toList();
      return ProductionAssistantPlanPhase(
        name: phase.name,
        order: phase.order,
        estimatedDays: phase.estimatedDays,
        tasks: updatedTasks,
      );
    }).toList();

    if (!didMutate) {
      return lifecycleNormalizedPayload;
    }
    final warningCode = "focused_role_scope_enforced";
    final warningAlreadyExists = lifecycleNormalizedPayload.warnings.any(
      (warning) => warning.code.trim().toLowerCase() == warningCode,
    );
    final warnings = <ProductionAssistantPlanWarning>[
      ...lifecycleNormalizedPayload.warnings,
      if (!warningAlreadyExists)
        ProductionAssistantPlanWarning(
          code: warningCode,
          message:
              "Adjusted $roleReplacementCount tasks to selected roles and refreshed $assignmentReplacementCount staff assignments from focused IDs.",
        ),
    ];
    AppDebug.log(
      _logTag,
      _focusedDraftEnforcedLog,
      extra: {
        "taskCount": payload.phases.fold<int>(
          0,
          (sum, phase) => sum + phase.tasks.length,
        ),
        "lifecycleTitleNormalized": lifecycleNormalizedPayload.phases.fold<int>(
          0,
          (sum, phase) =>
              sum +
              phase.tasks
                  .where(
                    (task) => RegExp(
                      r"\blifecycle\s+\d+\b",
                      caseSensitive: false,
                    ).hasMatch(task.title),
                  )
                  .length,
        ),
        "roleReplacementCount": roleReplacementCount,
        "assignmentReplacementCount": assignmentReplacementCount,
        "focusedRoleCount": focusedRoleKeys.length,
        "focusedStaffCount": focusedStaffProfileIds.length,
      },
    );
    return ProductionAssistantPlanDraftPayload(
      productId: lifecycleNormalizedPayload.productId,
      productName: lifecycleNormalizedPayload.productName,
      startDate: lifecycleNormalizedPayload.startDate,
      endDate: lifecycleNormalizedPayload.endDate,
      days: lifecycleNormalizedPayload.days,
      weeks: lifecycleNormalizedPayload.weeks,
      phases: updatedPhases,
      warnings: warnings,
    );
  }

  ProductionAssistantTurn _applyFocusedContextToPlanDraftTurn({
    required ProductionAssistantTurn turn,
  }) {
    final payload = turn.planDraftPayload;
    if (!turn.isPlanDraft || payload == null) {
      return turn;
    }
    final scopedPayload = _sanitizePlanDraftPayloadForFocusedContext(
      payload: payload,
    );
    return ProductionAssistantTurn(
      action: turn.action,
      message: turn.message,
      suggestionsPayload: turn.suggestionsPayload,
      clarifyPayload: turn.clarifyPayload,
      draftProductPayload: turn.draftProductPayload,
      planDraftPayload: scopedPayload,
    );
  }

  List<BusinessStaffProfileSummary> _staffForSelectedEstate({
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) {
    final estateId = (_selectedEstateAssetId ?? "").trim();
    if (estateId.isEmpty) {
      return const <BusinessStaffProfileSummary>[];
    }
    return staffProfiles.where((profile) {
      return (profile.estateAssetId ?? "").trim() == estateId;
    }).toList();
  }

  List<String> _availableFocusedRoleKeysForEstate({
    required List<BusinessStaffProfileSummary> estateScopedStaff,
  }) {
    final seen = <String>{};
    final roles = <String>[];
    for (final profile in estateScopedStaff) {
      final key = _normalizeRoleKey(profile.staffRole);
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      roles.add(key);
    }
    roles.sort();
    return roles;
  }

  List<BusinessStaffProfileSummary> _selectedFocusedStaffProfiles({
    required List<BusinessStaffProfileSummary> staffProfiles,
  }) {
    final selectedIds = _focusedStaffProfileIds;
    if (selectedIds.isEmpty) {
      return const <BusinessStaffProfileSummary>[];
    }
    final estateScoped = _staffForSelectedEstate(staffProfiles: staffProfiles);
    return estateScoped.where((profile) {
      return selectedIds.contains(profile.id.trim());
    }).toList();
  }

  bool _requiresFocusedStaffContext() {
    if ((_selectedEstateAssetId ?? "").trim().isEmpty) {
      return false;
    }
    if ((_selectedProductId ?? "").trim().isEmpty) {
      return false;
    }
    final staffAsync = ref.read(productionStaffProvider);
    return staffAsync.maybeWhen(
      data: (staffProfiles) {
        return _staffForSelectedEstate(staffProfiles: staffProfiles).isNotEmpty;
      },
      loading: () => true,
      orElse: () => false,
    );
  }

  bool _isFocusedStaffContextReadyForDraft() {
    if (!_requiresFocusedStaffContext()) {
      return true;
    }
    return _hasConfirmedStaffContext &&
        _focusedRoleKeys.isNotEmpty &&
        _focusedStaffProfileIds.isNotEmpty;
  }

  void _onFocusedRoleToggle(String roleKey) {
    final normalizedRole = _normalizeRoleKey(roleKey);
    if (normalizedRole.isEmpty) {
      return;
    }
    setState(() {
      final isSelected = _focusedRoleKeys.contains(normalizedRole);
      if (isSelected) {
        _focusedRoleKeys.remove(normalizedRole);
      } else {
        _focusedRoleKeys.add(normalizedRole);
      }

      // WHY: Keep selected staff aligned with selected role focus.
      if (_focusedRoleKeys.isNotEmpty) {
        final staffAsync = ref.read(productionStaffProvider);
        final selectedRoleSet = _focusedRoleKeys;
        final allowedStaffIds = staffAsync.maybeWhen(
          data: (staffProfiles) {
            return _staffForSelectedEstate(staffProfiles: staffProfiles)
                .where((profile) {
                  return selectedRoleSet.contains(
                    _normalizeRoleKey(profile.staffRole),
                  );
                })
                .map((profile) => profile.id.trim())
                .toSet();
          },
          orElse: () => <String>{},
        );
        if (allowedStaffIds.isNotEmpty) {
          _focusedStaffProfileIds.removeWhere(
            (staffId) => !allowedStaffIds.contains(staffId),
          );
        }
      }
      _hasConfirmedStaffContext = false;
      _lastAutoGenerateKey = "";
    });

    AppDebug.log(
      _logTag,
      _focusedRoleToggleLog,
      extra: {
        "role": normalizedRole,
        "selectedRoleCount": _focusedRoleKeys.length,
        "selectedStaffCount": _focusedStaffProfileIds.length,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _onFocusedStaffToggle(BusinessStaffProfileSummary profile) {
    final profileId = profile.id.trim();
    if (profileId.isEmpty) {
      return;
    }
    final normalizedRole = _normalizeRoleKey(profile.staffRole);
    setState(() {
      final isSelected = _focusedStaffProfileIds.contains(profileId);
      if (isSelected) {
        _focusedStaffProfileIds.remove(profileId);
      } else {
        _focusedStaffProfileIds.add(profileId);
        if (normalizedRole.isNotEmpty) {
          _focusedRoleKeys.add(normalizedRole);
        }
      }
      _hasConfirmedStaffContext = false;
      _lastAutoGenerateKey = "";
    });

    AppDebug.log(
      _logTag,
      _focusedStaffToggleLog,
      extra: {
        "staffProfileId": profileId,
        "staffRole": normalizedRole,
        "selectedRoleCount": _focusedRoleKeys.length,
        "selectedStaffCount": _focusedStaffProfileIds.length,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _onBulkFocusedStaffSelection({
    required List<BusinessStaffProfileSummary> staffOptions,
    required bool shouldSelectAll,
  }) {
    final selectableIds = staffOptions
        .map((profile) => profile.id.trim())
        .where((profileId) => profileId.isNotEmpty)
        .toSet();
    if (selectableIds.isEmpty) {
      return;
    }
    setState(() {
      // WHY: Bulk selection saves repetitive taps when many staff IDs are valid.
      if (shouldSelectAll) {
        _focusedStaffProfileIds.addAll(selectableIds);
        for (final profile in staffOptions) {
          final normalizedRole = _normalizeRoleKey(profile.staffRole);
          if (normalizedRole.isNotEmpty) {
            _focusedRoleKeys.add(normalizedRole);
          }
        }
      } else {
        _focusedStaffProfileIds.removeWhere(selectableIds.contains);
      }
      _hasConfirmedStaffContext = false;
      _lastAutoGenerateKey = "";
    });
    AppDebug.log(
      _logTag,
      _focusedStaffBulkToggleLog,
      extra: {
        "action": shouldSelectAll ? "select_all" : "clear_all",
        "affectedStaffCount": selectableIds.length,
        "selectedRoleCount": _focusedRoleKeys.length,
        "selectedStaffCount": _focusedStaffProfileIds.length,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _confirmFocusedStaffContext() {
    if (!_requiresFocusedStaffContext()) {
      return;
    }
    if (_focusedRoleKeys.isEmpty || _focusedStaffProfileIds.isEmpty) {
      _showSnack(_contextPromptConfirmStaffContextMissing);
      return;
    }
    setState(() {
      _hasConfirmedStaffContext = true;
      _lastAutoGenerateKey = "";
    });
    _appendMessage(
      _ChatMessage(
        fromAssistant: false,
        text:
            "Prioritize roles (${_focusedRoleKeys.length}) and staff IDs (${_focusedStaffProfileIds.length}).",
      ),
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
    _tryAutoGenerateDraftFromContext(
      trigger: "staff_context_confirmed",
      inferredMode: _useAiInferredDates,
    );
  }

  void _onDomainContextChanged(String? value) {
    final nextDomain = normalizeProductionDomainContext(value);
    if (nextDomain == _domainContext && _domainExplicitlySelected) {
      return;
    }
    setState(() {
      _domainContext = nextDomain;
      _domainExplicitlySelected = true;
      _lastAutoGenerateKey = "";
    });
    _appendMessage(
      _ChatMessage(
        fromAssistant: false,
        text: "Business type: ${formatProductionDomainLabel(nextDomain)}",
      ),
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _skipDateSelectionAndInfer() {
    setState(() {
      _startDate = null;
      _endDate = null;
      // WHY: Explicitly marking this choice prevents date-step loops.
      _useAiInferredDates = true;
      _lastAutoGenerateKey = "";
    });
    _appendMessage(
      const _ChatMessage(fromAssistant: false, text: "Use AI inferred dates."),
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
    _tryAutoGenerateDraftFromContext(
      trigger: "ai_inferred_dates_selected",
      inferredMode: true,
    );
  }

  void _onEstateChanged({
    required String? estateId,
    required String estateName,
  }) {
    if ((_selectedEstateAssetId ?? "") == (estateId ?? "")) {
      return;
    }
    setState(() {
      _selectedEstateAssetId = estateId;
      // WHY: Staff context is estate-scoped, so selection resets when estate changes.
      _focusedRoleKeys.clear();
      _focusedStaffProfileIds.clear();
      _hasConfirmedStaffContext = false;
      _lastAutoGenerateKey = "";
    });
    if ((estateId ?? "").trim().isNotEmpty) {
      _appendMessage(
        _ChatMessage(fromAssistant: false, text: "Estate: $estateName"),
      );
    }
    final canAutoWithManualDates = _startDate != null && _endDate != null;
    if (_useAiInferredDates || canAutoWithManualDates) {
      _appendAssistantMessageOnce(_resolveGuideQuestion());
      _tryAutoGenerateDraftFromContext(
        trigger: "estate_selected_context_ready",
        inferredMode: _useAiInferredDates,
      );
      return;
    }
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _onProductChanged({
    required String? productId,
    required String productName,
  }) {
    if ((_selectedProductId ?? "") == (productId ?? "")) {
      return;
    }
    setState(() {
      _selectedProductId = productId;
      _lastAutoGenerateKey = "";
    });
    if ((productId ?? "").trim().isNotEmpty) {
      _appendMessage(
        _ChatMessage(fromAssistant: false, text: "Product: $productName"),
      );
    }
    final canAutoWithManualDates = _startDate != null && _endDate != null;
    if (_useAiInferredDates || canAutoWithManualDates) {
      _appendAssistantMessageOnce(_resolveGuideQuestion());
      _tryAutoGenerateDraftFromContext(
        trigger: "product_selected_context_ready",
        inferredMode: _useAiInferredDates,
      );
      return;
    }
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  Future<void> _generateDraftFromContext({
    required String estateName,
    required String productName,
  }) async {
    final hasEstate = (_selectedEstateAssetId ?? "").trim().isNotEmpty;
    final hasProduct = (_selectedProductId ?? "").trim().isNotEmpty;
    if (!hasEstate || !hasProduct) {
      _appendMessage(
        const _ChatMessage(
          fromAssistant: true,
          text: _contextPromptMissingContextMessage,
          isError: true,
        ),
      );
      _showSnack(_contextPromptMissingContextMessage);
      return;
    }
    if (!_isFocusedStaffContextReadyForDraft()) {
      _appendMessage(
        const _ChatMessage(
          fromAssistant: true,
          text: _guideQuestionRoleStaff,
          isError: true,
        ),
      );
      _showSnack("Select focus roles and staff IDs first.");
      return;
    }
    final focusedRoles = _focusedRoleKeys.toList()..sort();
    final focusedStaff = _selectedFocusedStaffProfiles(
      staffProfiles: ref.read(productionStaffProvider).valueOrNull ?? const [],
    );
    final prompt = _buildStrictGeneratePrompt(
      estateName: estateName,
      productName: productName,
      focusedRoles: focusedRoles,
      focusedStaff: focusedStaff,
    );
    AppDebug.log(
      _logTag,
      _strictGenerateTapLog,
      extra: {
        "hasEstate": hasEstate,
        "hasProduct": hasProduct,
        "hasStartDate": _startDate != null,
        "hasEndDate": _endDate != null,
        "focusedRoleCount": focusedRoles.length,
        "focusedStaffCount": focusedStaff.length,
      },
    );
    await _sendTurn(forcedMessage: prompt);
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _buildLog);
    final theme = Theme.of(context);
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
    final staffAsync = ref.watch(productionStaffProvider);
    final selectedEstateName = assetsAsync.maybeWhen(
      data: (result) {
        for (final asset in result.assets) {
          if (asset.assetType != _assetTypeEstate) {
            continue;
          }
          if (asset.id == _selectedEstateAssetId) {
            return asset.name;
          }
        }
        return "";
      },
      orElse: () => "",
    );
    final estateNamesById = assetsAsync.maybeWhen(
      data: (result) {
        final map = <String, String>{};
        for (final asset in result.assets) {
          if (asset.assetType != _assetTypeEstate) {
            continue;
          }
          map[asset.id] = asset.name;
        }
        return map;
      },
      orElse: () => const <String, String>{},
    );
    final selectedProductName = productsAsync.maybeWhen(
      data: (products) {
        for (final product in products) {
          if (product.id == _selectedProductId) {
            return product.name;
          }
        }
        return "";
      },
      orElse: () => "",
    );
    final quickProducts = productsAsync.maybeWhen(
      data: (products) => _filterQuickProductsByDomain(
        products: products,
        domainContext: _domainContext,
      ),
      orElse: () => const <Product>[],
    );
    final estateScopedStaffProfiles = staffAsync.maybeWhen(
      data: (staffProfiles) =>
          _staffForSelectedEstate(staffProfiles: staffProfiles),
      orElse: () => const <BusinessStaffProfileSummary>[],
    );
    final availableFocusedRoleKeys = _availableFocusedRoleKeysForEstate(
      estateScopedStaff: estateScopedStaffProfiles,
    );
    final selectedFocusedRoles = _focusedRoleKeys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        actions: [
          IconButton(
            tooltip: _manualEditorTooltip,
            onPressed: _openManualEditor,
            icon: const Icon(Icons.edit_note_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _messagesScrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                ..._messages.map((entry) => _ChatBubble(message: entry)),
                _StrictContextPromptPanel(
                  question: _resolveGuideQuestion(),
                  domainContext: _domainContext,
                  domainExplicitlySelected: _domainExplicitlySelected,
                  hasEstate: (_selectedEstateAssetId ?? "").trim().isNotEmpty,
                  hasProduct: (_selectedProductId ?? "").trim().isNotEmpty,
                  hasStartDate: _startDate != null,
                  hasEndDate: _endDate != null,
                  useAiInferredDates: _useAiInferredDates,
                  selectedEstateName: selectedEstateName,
                  selectedProductName: selectedProductName,
                  selectedEstateAssetId: _selectedEstateAssetId,
                  estateNamesById: estateNamesById,
                  startDate: _startDate,
                  endDate: _endDate,
                  isSending: _isSending,
                  quickProducts: quickProducts,
                  selectedProductId: _selectedProductId,
                  isStaffLoading: staffAsync.isLoading,
                  availableFocusedRoleKeys: availableFocusedRoleKeys,
                  selectedFocusedRoleKeys: selectedFocusedRoles,
                  estateScopedStaffProfiles: estateScopedStaffProfiles,
                  selectedFocusedStaffProfileIds: _focusedStaffProfileIds,
                  hasConfirmedStaffContext: _hasConfirmedStaffContext,
                  onDomainSelect: (domain) => _onDomainContextChanged(domain),
                  onEstateSelect: (estateId) => _onEstateChanged(
                    estateId: estateId,
                    estateName: estateNamesById[estateId] ?? "Selected estate",
                  ),
                  onPickStartDate: () => _pickDate(isStart: true),
                  onPickEndDate: () => _pickDate(isStart: false),
                  onSkipDates: _skipDateSelectionAndInfer,
                  onQuickProductTap: (product) {
                    AppDebug.log(
                      _logTag,
                      _quickProductSelectTapLog,
                      extra: {
                        "productId": product.id,
                        "productName": product.name,
                      },
                    );
                    _onProductChanged(
                      productId: product.id,
                      productName: product.name,
                    );
                  },
                  onCreateProductTap: _createProductFromContext,
                  onFocusedRoleToggle: _onFocusedRoleToggle,
                  onFocusedStaffToggle: _onFocusedStaffToggle,
                  onBulkFocusedStaffSelection:
                      (staffOptions, shouldSelectAll) =>
                          _onBulkFocusedStaffSelection(
                            staffOptions: staffOptions,
                            shouldSelectAll: shouldSelectAll,
                          ),
                  onConfirmFocusedStaffContext: _confirmFocusedStaffContext,
                  onGenerateTap: () => _generateDraftFromContext(
                    estateName: selectedEstateName,
                    productName: selectedProductName,
                  ),
                ),
                _TurnActionPanel(
                  turn: _lastTurn,
                  onSuggestionTap: (value) async {
                    AppDebug.log(
                      _logTag,
                      _suggestionTapLog,
                      extra: {"value": value},
                    );
                    await _sendTurn(forcedMessage: value);
                  },
                  onChoiceTap: (value) async {
                    AppDebug.log(
                      _logTag,
                      _choiceTapLog,
                      extra: {"value": value},
                    );
                    await _sendTurn(forcedMessage: value);
                  },
                  onCreateSuggestedProduct: _createSuggestedProduct,
                  onApplyDraft: _previewDraftProductionSchedule,
                ),
                if (_lastTurn == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    child: Text(
                      _noPlanDraftMessage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StrictContextPromptPanel extends StatelessWidget {
  final String question;
  final String domainContext;
  final bool domainExplicitlySelected;
  final bool hasEstate;
  final bool hasProduct;
  final bool hasStartDate;
  final bool hasEndDate;
  final bool useAiInferredDates;
  final String selectedEstateName;
  final String selectedProductName;
  final String? selectedEstateAssetId;
  final Map<String, String> estateNamesById;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isSending;
  final bool isStaffLoading;
  final List<Product> quickProducts;
  final String? selectedProductId;
  final List<String> availableFocusedRoleKeys;
  final List<String> selectedFocusedRoleKeys;
  final List<BusinessStaffProfileSummary> estateScopedStaffProfiles;
  final Set<String> selectedFocusedStaffProfileIds;
  final bool hasConfirmedStaffContext;
  final ValueChanged<String> onDomainSelect;
  final ValueChanged<String> onEstateSelect;
  final ValueChanged<String> onFocusedRoleToggle;
  final ValueChanged<BusinessStaffProfileSummary> onFocusedStaffToggle;
  final void Function(List<BusinessStaffProfileSummary>, bool)
  onBulkFocusedStaffSelection;
  final VoidCallback onConfirmFocusedStaffContext;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final VoidCallback onSkipDates;
  final VoidCallback onCreateProductTap;
  final VoidCallback onGenerateTap;
  final ValueChanged<Product> onQuickProductTap;

  const _StrictContextPromptPanel({
    required this.question,
    required this.domainContext,
    required this.domainExplicitlySelected,
    required this.hasEstate,
    required this.hasProduct,
    required this.hasStartDate,
    required this.hasEndDate,
    required this.useAiInferredDates,
    required this.selectedEstateName,
    required this.selectedProductName,
    required this.selectedEstateAssetId,
    required this.estateNamesById,
    required this.startDate,
    required this.endDate,
    required this.isSending,
    required this.isStaffLoading,
    required this.quickProducts,
    required this.selectedProductId,
    required this.availableFocusedRoleKeys,
    required this.selectedFocusedRoleKeys,
    required this.estateScopedStaffProfiles,
    required this.selectedFocusedStaffProfileIds,
    required this.hasConfirmedStaffContext,
    required this.onDomainSelect,
    required this.onEstateSelect,
    required this.onFocusedRoleToggle,
    required this.onFocusedStaffToggle,
    required this.onBulkFocusedStaffSelection,
    required this.onConfirmFocusedStaffContext,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onSkipDates,
    required this.onCreateProductTap,
    required this.onGenerateTap,
    required this.onQuickProductTap,
  });

  String _normalizeRoleKey(String rawRole) {
    return rawRole
        .trim()
        .toLowerCase()
        .replaceAll("-", "_")
        .replaceAll(" ", "_");
  }

  _GuidedStep _resolveStep() {
    if (!domainExplicitlySelected) {
      return _GuidedStep.businessType;
    }
    if (!hasEstate) {
      return _GuidedStep.estate;
    }
    if (!hasProduct) {
      return _GuidedStep.product;
    }
    final requiresRoleAndStaff =
        estateScopedStaffProfiles.isNotEmpty || isStaffLoading;
    final hasFocusedRole = selectedFocusedRoleKeys.isNotEmpty;
    final hasFocusedStaff = selectedFocusedStaffProfileIds.isNotEmpty;
    if (requiresRoleAndStaff &&
        (!hasFocusedRole || !hasFocusedStaff || !hasConfirmedStaffContext)) {
      return _GuidedStep.roleAndStaff;
    }
    if ((!hasStartDate || !hasEndDate) && !useAiInferredDates) {
      return _GuidedStep.dates;
    }
    return _GuidedStep.generate;
  }

  String _stepHintText(_GuidedStep step) {
    final hasRoleStep = estateScopedStaffProfiles.isNotEmpty || isStaffLoading;
    switch (step) {
      case _GuidedStep.businessType:
        return hasRoleStep
            ? "Step 1 of 6: choose business type."
            : "Step 1 of 5: choose business type.";
      case _GuidedStep.estate:
        return hasRoleStep
            ? "Step 2 of 6: choose estate."
            : "Step 2 of 5: choose estate.";
      case _GuidedStep.product:
        return hasRoleStep
            ? "Step 3 of 6: choose or create product."
            : "Step 3 of 5: choose or create product.";
      case _GuidedStep.roleAndStaff:
        return "Step 4 of 6: choose focused roles and staff IDs.";
      case _GuidedStep.dates:
        return hasRoleStep
            ? "Step 5 of 6: choose dates or infer dates."
            : "Step 4 of 5: choose dates or infer dates.";
      case _GuidedStep.generate:
        return hasRoleStep
            ? "Step 6 of 6: generate draft."
            : "Step 5 of 5: generate draft.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate = hasEstate && hasProduct;
    final currentStep = _resolveStep();
    final selectedRoleSet = selectedFocusedRoleKeys
        .map(_normalizeRoleKey)
        .where((value) => value.isNotEmpty)
        .toSet();
    final focusStaffOptions = selectedRoleSet.isEmpty
        ? estateScopedStaffProfiles
        : estateScopedStaffProfiles.where((profile) {
            return selectedRoleSet.contains(
              _normalizeRoleKey(profile.staffRole),
            );
          }).toList();
    final selectableFocusStaffIds = focusStaffOptions
        .map((profile) => profile.id.trim())
        .where((profileId) => profileId.isNotEmpty)
        .toSet();
    final allPreferredStaffSelected =
        selectableFocusStaffIds.isNotEmpty &&
        selectableFocusStaffIds.every(selectedFocusedStaffProfileIds.contains);
    final contextLabel = [
      "Business: ${formatProductionDomainLabel(domainContext)}",
      "Estate: ${selectedEstateName.trim().isEmpty ? "Not selected" : selectedEstateName}",
      "Product: ${selectedProductName.trim().isEmpty ? "Not selected" : selectedProductName}",
      "Dates: ${hasStartDate && hasEndDate ? "Set" : "AI infer"}",
      "Focused roles: ${selectedFocusedRoleKeys.length}",
      "Focused staff IDs: ${selectedFocusedStaffProfileIds.length}",
    ].join(" | ");
    final estateEntries = estateNamesById.entries.take(8).toList();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _contextPromptTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(question, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            Text(
              _guideContextLabelPrefix,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(contextLabel, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (currentStep == _GuidedStep.businessType)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: productionDomainValues
                    .map(
                      (domain) => ChoiceChip(
                        label: Text(formatProductionDomainLabel(domain)),
                        selected:
                            normalizeProductionDomainContext(domainContext) ==
                                normalizeProductionDomainContext(domain) &&
                            domainExplicitlySelected,
                        onSelected: (_) => onDomainSelect(domain),
                      ),
                    )
                    .toList(),
              ),
            if (currentStep == _GuidedStep.estate) ...[
              if (estateEntries.isEmpty)
                Text(
                  "No estates yet. Create an estate in Assets, then continue.",
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: estateEntries
                      .map(
                        (entry) => ChoiceChip(
                          label: Text(entry.value),
                          selected: entry.key == selectedEstateAssetId,
                          onSelected: (_) => onEstateSelect(entry.key),
                        ),
                      )
                      .toList(),
                ),
            ],
            if (currentStep == _GuidedStep.product) ...[
              if (quickProducts.isNotEmpty) ...[
                Text(
                  _contextPromptQuickProductLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickProducts
                      .map(
                        (product) => ChoiceChip(
                          label: Text(product.name),
                          selected: product.id == selectedProductId,
                          onSelected: (_) => onQuickProductTap(product),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: isSending ? null : onCreateProductTap,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text(_contextPromptCreateProductLabel),
              ),
            ],
            if (currentStep == _GuidedStep.roleAndStaff) ...[
              Text(
                _contextPromptRoleFocusLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _contextPromptRoleFocusHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (isStaffLoading)
                Text(
                  _contextPromptStaffLoading,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else if (availableFocusedRoleKeys.isEmpty)
                Text(
                  _contextPromptNoStaffInEstate,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableFocusedRoleKeys
                      .map(
                        (roleKey) => FilterChip(
                          label: Text(formatStaffRoleLabel(roleKey)),
                          selected: selectedRoleSet.contains(
                            _normalizeRoleKey(roleKey),
                          ),
                          onSelected: (_) => onFocusedRoleToggle(roleKey),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 10),
              Text(
                _contextPromptStaffFocusLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _contextPromptStaffFocusHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (focusStaffOptions.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onBulkFocusedStaffSelection(
                      focusStaffOptions,
                      !allPreferredStaffSelected,
                    ),
                    icon: Icon(
                      allPreferredStaffSelected
                          ? Icons.clear_all
                          : Icons.done_all,
                    ),
                    label: Text(
                      allPreferredStaffSelected
                          ? "Clear all preferred staff"
                          : "Select all preferred staff",
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (focusStaffOptions.isEmpty)
                Text(
                  _contextPromptNoStaffInEstate,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: focusStaffOptions.length,
                    itemBuilder: (context, index) {
                      final profile = focusStaffOptions[index];
                      final profileId = profile.id.trim();
                      return CheckboxListTile(
                        value: selectedFocusedStaffProfileIds.contains(
                          profileId,
                        ),
                        onChanged: (_) => onFocusedStaffToggle(profile),
                        title: Text(_resolveAssistantStaffDisplayName(profile)),
                        subtitle: Text(
                          "${formatStaffRoleLabel(profile.staffRole)} | $profileId",
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed:
                    isStaffLoading ||
                        selectedRoleSet.isEmpty ||
                        selectedFocusedStaffProfileIds.isEmpty
                    ? null
                    : onConfirmFocusedStaffContext,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(_contextPromptConfirmStaffContextLabel),
              ),
            ],
            if (currentStep == _GuidedStep.dates) ...[
              Row(
                children: [
                  Expanded(
                    child: _DatePickField(
                      label: "Start date",
                      value: startDate,
                      onTap: onPickStartDate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DatePickField(
                      label: "End date",
                      value: endDate,
                      onTap: onPickEndDate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: isSending ? null : onSkipDates,
                child: const Text(_contextPromptSkipDatesLabel),
              ),
            ],
            if (currentStep == _GuidedStep.generate)
              FilledButton.icon(
                onPressed: isSending || !canGenerate ? null : onGenerateTap,
                icon: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  isSending
                      ? _contextPromptGeneratingLabel
                      : _contextPromptGenerateLabel,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _stepHintText(currentStep),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

enum _GuidedStep {
  businessType,
  estate,
  product,
  roleAndStaff,
  dates,
  generate,
}

class _DatePickField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DatePickField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value == null ? "Select" : formatDateLabel(value)),
      ),
    );
  }
}

String _resolveAssistantStaffDisplayName(BusinessStaffProfileSummary profile) {
  final name = profile.userName?.trim() ?? "";
  if (name.isNotEmpty) {
    return name;
  }
  final email = profile.userEmail?.trim() ?? "";
  if (email.isNotEmpty) {
    return email;
  }
  final phone = profile.userPhone?.trim() ?? "";
  if (phone.isNotEmpty) {
    return phone;
  }
  return profile.id;
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = message.fromAssistant
        ? Alignment.centerLeft
        : Alignment.centerRight;
    final bgColor = message.fromAssistant
        ? (message.isError
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest)
        : theme.colorScheme.primaryContainer;
    final fgColor = message.fromAssistant
        ? (message.isError
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSurface)
        : theme.colorScheme.onPrimaryContainer;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyMedium?.copyWith(color: fgColor),
        ),
      ),
    );
  }
}

class _TurnActionPanel extends StatelessWidget {
  final ProductionAssistantTurn? turn;
  final Future<void> Function(String value) onSuggestionTap;
  final Future<void> Function(String value) onChoiceTap;
  final Future<void> Function(ProductionAssistantDraftProductPayload payload)
  onCreateSuggestedProduct;
  final Future<void> Function(ProductionAssistantPlanDraftPayload payload)
  onApplyDraft;

  const _TurnActionPanel({
    required this.turn,
    required this.onSuggestionTap,
    required this.onChoiceTap,
    required this.onCreateSuggestedProduct,
    required this.onApplyDraft,
  });

  @override
  Widget build(BuildContext context) {
    final currentTurn = turn;
    if (currentTurn == null) {
      return const SizedBox.shrink();
    }

    final suggestionPayload = currentTurn.suggestionsPayload;
    if (currentTurn.isSuggestions && suggestionPayload != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestionPayload.suggestions
              .map(
                (entry) => ActionChip(
                  label: Text(entry),
                  onPressed: () => onSuggestionTap(entry),
                ),
              )
              .toList(),
        ),
      );
    }

    final clarifyPayload = currentTurn.clarifyPayload;
    if (currentTurn.isClarify && clarifyPayload != null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clarifyPayload.question,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (clarifyPayload.contextSummary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  clarifyPayload.contextSummary,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (clarifyPayload.choices.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: clarifyPayload.choices
                      .map(
                        (entry) => ActionChip(
                          label: Text(entry),
                          onPressed: () => onChoiceTap(entry),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final draftProductPayload = currentTurn.draftProductPayload;
    if (currentTurn.isDraftProduct && draftProductPayload != null) {
      final draft = draftProductPayload.draftProduct;
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Suggested product",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(draft.name),
              Text("Category: ${draft.category}"),
              Text("Unit: ${draft.unit}"),
              Text("Lifecycle: ${draft.lifecycleDaysEstimate} days"),
              if (draft.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(draft.notes, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => onCreateSuggestedProduct(draftProductPayload),
                icon: const Icon(Icons.add_box_outlined),
                label: const Text(_createSuggestedProductLabel),
              ),
            ],
          ),
        ),
      );
    }

    final planDraftPayload = currentTurn.planDraftPayload;
    if (currentTurn.isPlanDraft && planDraftPayload != null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Draft ready: ${planDraftPayload.weeks} weeks (${planDraftPayload.days} days)",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text("Start: ${planDraftPayload.startDate}"),
              Text("End: ${planDraftPayload.endDate}"),
              Text("Phases: ${planDraftPayload.phases.length}"),
              if (planDraftPayload.warnings.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...planDraftPayload.warnings
                    .take(3)
                    .map((warning) => Text("- ${warning.message}")),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => onApplyDraft(planDraftPayload),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(_useDraftButtonLabel),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ChatMessage {
  final bool fromAssistant;
  final String text;
  final bool isError;

  const _ChatMessage({
    required this.fromAssistant,
    required this.text,
    this.isError = false,
  });
}

class _AssistantScheduleTask {
  final String title;
  final String phaseName;
  final String roleRequired;
  final int requiredHeadcount;
  final List<String> assignedStaffProfileIds;
  final DateTime startDate;
  final DateTime dueDate;

  const _AssistantScheduleTask({
    required this.title,
    required this.phaseName,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.assignedStaffProfileIds,
    required this.startDate,
    required this.dueDate,
  });
}

class _AssistantDailySchedule {
  final DateTime date;
  final List<_AssistantScheduleTask> tasks;

  const _AssistantDailySchedule({required this.date, required this.tasks});
}

class _AssistantWeeklySchedule {
  final DateTime weekStart;
  final List<_AssistantDailySchedule> days;

  const _AssistantWeeklySchedule({required this.weekStart, required this.days});
}
