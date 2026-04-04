/// lib/app/features/home/presentation/production/production_plan_assistant_screen.dart
/// --------------------------------------------------------------------------------
/// WHAT:
/// - Chat-first assistant screen for creating production plans.
// ignore_for_file: unused_element, unused_field, unused_element_parameter, unnecessary_underscores
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

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/core/platform/text_file_download.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_product_form_sheet.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_routes.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_ai_model.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_selling_option.dart';
import 'package:frontend/app/features/home/presentation/production/production_assistant_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_domain_context.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_task_table.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';

const String _logTag = "PRODUCTION_ASSISTANT_SCREEN";
const String _buildLog = "build()";
const String _sendTurnLog = "send_turn";
const String _sendSuccessLog = "send_success";
const String _sendFailureLog = "send_failure";
const String _draftQualitySnapshotLog = "draft_quality_snapshot";
const String _draftQualityIssueLog = "draft_quality_issue_detected";
const String _openEditorLog = "open_editor";
const String _applyDraftLog = "apply_draft";
const String _focusedDraftEnforcedLog = "focused_draft_enforced";
const String _staffingBoundsEnforcedLog = "staffing_bounds_enforced";
const String _managementCoverageEnforcedLog = "management_coverage_enforced";
const String _suggestionTapLog = "suggestion_tap";
const String _choiceTapLog = "choice_tap";
const String _strictGenerateTapLog = "strict_generate_tap";
const String _focusedRoleToggleLog = "focused_role_toggle";
const String _focusedStaffToggleLog = "focused_staff_toggle";
const String _focusedStaffBulkToggleLog = "focused_staff_bulk_toggle";
const String _workloadContextUpdateLog = "workload_context_update";
const String _workloadContextConfirmLog = "workload_context_confirm";
const String _createSuggestedProductTapLog = "create_suggested_product_tap";
const String _createSuggestedProductSuccessLog =
    "create_suggested_product_success";
const String _previewStaffProfileTapLog = "preview_staff_profile_tap";
const String _previewStaffProfileNavigateLog = "preview_staff_profile_navigate";
const String _downloadDraftTapLog = "download_draft_tap";
const String _downloadDraftSuccessLog = "download_draft_success";
const String _downloadDraftFailureLog = "download_draft_failure";
const String _inspectDraftTapLog = "inspect_draft_tap";
const String _improveDraftSuccessLog = "improve_draft_success";
const String _improveDraftFailureLog = "improve_draft_failure";
const String _populateDraftFromPdfTapLog = "populate_draft_from_pdf_tap";
const String _populateDraftFromPdfSuccessLog =
    "populate_draft_from_pdf_success";
const String _populateDraftFromPdfFailureLog =
    "populate_draft_from_pdf_failure";
const String _plannerCropSearchTapLog = "planner_crop_search_tap";
const String _plannerCropSearchSelectLog = "planner_crop_search_select";
const String _plannerCropAutoCreateProductStartLog =
    "planner_crop_auto_create_product_start";
const String _plannerCropAutoCreateProductSuccessLog =
    "planner_crop_auto_create_product_success";
const String _plannerCropAutoCreateProductFailLog =
    "planner_crop_auto_create_product_fail";
const List<String> _monthLabels = <String>[
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const String _screenTitle = "Digital production plan with AI assistant";
const String _workspacePrimaryTitle = "Production Intelligence";
const String _workspaceSecondaryTitle = "AI production assistant";
const String _workspaceAlignmentLabel = "AI Insight";
const String _workspaceViewTimelineLabel = "View timeline";
const String _workspaceAskAiLabel = "Ask AI";
const String _workspaceAddPlanLabel = "Add plan";
const String _workspaceConversationTitle = "Assistant conversation";
const String _workspaceDraftStatusDraft = "draft";
const String _workspaceDraftStatusContext = "context";
const String _workspaceScheduleAlignedSuffix = "aligned with schedule.";
const String _manualEditorTooltip = "Open editor";
const String _welcomeMessage =
    "Let's collect context first: choose estate, search one crop from the planner source, then generate the full timeline draft.";
const String _useDraftButtonLabel = "Draft production";
const String _noPlanDraftMessage =
    "No draft yet. Select estate + crop, then generate draft from context.";
const String _createSuggestedProductLabel = "Create Suggested Product";
const String _assistantErrorMessage = "Assistant request failed. Please retry.";
const String _assistantErrorResponseKey = "error";
const String _assistantErrorCodeKey = "error_code";
const String _assistantClassificationKey = "classification";
const String _assistantResolutionHintKey = "resolution_hint";
const String _assistantRetryAllowedKey = "retry_allowed";
const String _assistantRetryReasonKey = "retry_reason";
const String _assistantUnknownFailureClassification = "UNKNOWN_PROVIDER_ERROR";
const String _assistantUnknownFailureResolutionHint =
    "Check backend /business assistant logs, then retry with estate and product selected.";
const String _contextPromptTitle = "Context-first planning";
const String _contextPromptGenerateLabel = "Generate draft from context";
const String _contextPromptMissingContextMessage =
    "Select estate and crop first, then generate draft.";
const String _contextPromptSearchProductLabel = "Search planner crop database";
const String _contextPromptSearchProductHint =
    "Search one crop from the planner source instead of browsing farm product chips.";
const String _contextPromptSelectedProductLabel = "Selected crop";
const String _contextPromptChangeProductLabel = "Change crop";
const String _contextPromptGeneratingLabel = "Generating...";
const String _contextPromptSkipDatesLabel = "Use lifecycle dates";
const String _guideQuestionBusinessType =
    "What business type are you planning for?";
const String _guideQuestionEstate = "Nice. Which estate should I plan for?";
const String _guideQuestionProduct =
    "Great. Search and select the crop you want the planner to use.";
const String _guideQuestionRoleStaff =
    "Great. Select roles and staff I should prioritize in this production.";
const String _guideQuestionWorkload =
    "Good. Tell me your workload setup before dates: work-unit type, total units, and staffing limits.";
const String _guideQuestionDates =
    "Do you want to set dates now, or use product lifecycle dates?";
const String _guideQuestionReady =
    "Perfect. I have enough context. Generate your full draft timeline.";
const String _guideContextLabelPrefix = "Current context";
const String _draftPlanSheetTitle = "Draft production schedule";
const String _draftPlanSheetEmpty = "No scheduled tasks were generated.";
const String _draftPlanCloseLabel = "Close";
const String _draftPlanDownloadLabel = "Download draft";
const String _draftPlanContinueLabel = "Draft production";
const String _draftPlanProjectedCoverageLabel = "Projected full-task coverage";
const String _draftPlanProjectedRemainingLabel = "Worst task left";
const String _draftPlanProjectedTrackCountLabel = "Task tracks covered";
const String _draftPlanTaskProjectedLabel = "Planned in this block (task)";
const String _draftPlanTaskRemainingLabel = "Left for this task";
const String _draftStudioImproveLabel = "Improve draft";
const String _draftStudioDownloadLabel = "Download plan";
const String _draftStudioPopulateFromPdfLabel = "Populate from PDF";
const String _draftRepairUnresolvedCoverageWarningCode =
    "draft_repair_unresolved_coverage";
const String _draftRepairYieldBasisWarningCode =
    "draft_repair_yield_basis_tracking";
const int _documentImportCharacterLimit = 12000;
const List<String> _documentImportAllowedExtensions = [
  "pdf",
  "html",
  "htm",
  "txt",
];
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
const String _contextPromptWorkloadLabel = "Workload setup";
const String _contextPromptWorkloadHint =
    "Set unit size and staffing assumptions so AI can distribute workload realistically.";
const String _contextPromptTotalUnitsSliderLabel = "Total work units";
const String _contextPromptActiveStaffAssumptionLabel =
    "Expected active selected staff";
const String _contextPromptTotalUnitsQuickPickLabel = "Quick unit picks";
const String _contextPromptMinStaffQuickPickLabel = "Min staff quick picks";
const String _contextPromptMaxStaffQuickPickLabel = "Max staff quick picks";
const String _contextPromptConfirmWorkloadContextLabel =
    "Continue with workload setup";
const String _contextPromptConfirmWorkloadContextMissing =
    "Set work unit, total units, and min/max staff per unit before continuing.";
const String _contextPromptWorkUnitOptionLabel = "Work unit options";
const String _plannerCropSheetTitle = "Search planner crop database";
const String _plannerCropSheetHint =
    "Search verified planner crops, fruits, and plants with offline lifecycle coverage first, then refresh from vetted agriculture sources when available.";
const String _plannerCropSearchFieldLabel = "Search crops";
const String _plannerCropSearchFieldHint = "Try beans, corn, rice, tomato";
const String _plannerCropSearchEmptyState =
    "No planner crops matched that search. Try another crop name.";
const String _plannerCropSearchMinimumState =
    "Start typing or pick one of the planner crop suggestions.";
const String _plannerCropSearchErrorState =
    "Crop search failed. Retry in a moment.";
const String _plannerCropLifecyclePendingLabel = "Lifecycle pending";
const String _plannerCropLifecycleFallbackSnack =
    "Crop selected. Lifecycle details could not be refreshed right now, so the planner kept the best available local data.";
const String _plannerCropAutoCreateProductSuccessSnack =
    "Farm product setup complete. The planner crop is now linked.";
const String _plannerCropAutoCreateProductFailureSnack =
    "Complete the farm product setup before continuing with this crop.";
const int _plannerCropSearchMinimumQueryLength = 2;
const Duration _plannerCropSearchDebounce = Duration(milliseconds: 420);
const List<int> _contextPromptTotalUnitsQuickPicks = [5, 10, 20, 50, 100];
const List<int> _contextPromptMinStaffPerUnitQuickPicks = [1, 2, 3, 4, 5];
const List<int> _contextPromptMaxStaffPerUnitQuickPicks = [2, 3, 4, 5, 7, 10];
const String _focusedRoleScopeEnforcedWarningCode =
    "focused_role_scope_enforced";
const String _workloadStaffingBoundsWarningCode =
    "workload_staffing_bounds_enforced";
const String _workloadStaffingShortageWarningCode =
    "workload_staffing_minimum_unmet";
const String _managementCoverageEnforcedWarningCode =
    "management_weekly_coverage_enforced";
const String _managementCoverageMissingWarningCode =
    "management_weekly_coverage_unmet";
const String _fallbackThroughputBoostWarningCode =
    "fallback_throughput_staffing_boost_applied";
const String _phaseGateLockedWarningCode = "phase_locked_unit_budget_exhausted";
const String _phaseGateCappedWarningCode = "draft_capped_remaining_units";
const String _assistantPhaseTypeFinite = "finite";
const String _assistantPhaseTypeMonitoring = "monitoring";
const String _stageGateResequencedWarningCode = "stage_gate_resequenced";
const String _stageGateBlockedWarningCode = "stage_gate_blocked";
const String _stageGateAutofillWarningCode = "stage_gate_autofill_applied";
const int _projectionRecommendedPlotsPerStaffPerDay = 2;
const int _projectionHoursPerDay = 8;
const double _projectionMinimumDurationRatio = 0.125;
// WHY: Downstream finite execution must not start until prerequisite work units are fully completed.
const double _stageGateStartThresholdRatio = 1.0;
const List<String> _projectionRepeatableDailyKeywords = [
  "daily",
  "water",
  "watering",
  "irrigation",
];
const List<String> _projectionRepeatableWeeklyKeywords = [
  "weekly",
  "weed",
  "pest",
  "inspection",
  "monitor",
  "monitoring",
  "scout",
  "survey",
  "quality",
];
const List<String> _projectionRepeatableMonthlyKeywords = [
  "monthly",
  "audit",
  "deep maintenance",
  "service review",
];
const List<String> _draftRepairUnsupportedSpiceAliases = [
  "black_pepper",
  "peppercorn",
];
const List<String> _draftRepairTransplantFruitingCropAliases = [
  "pepper",
  "peppers",
  "bell_pepper",
  "bell_peppers",
  "sweet_pepper",
  "sweet_peppers",
  "capsicum",
  "capsicums",
  "chilli",
  "chillies",
  "chili",
  "chilies",
  "hot_pepper",
  "hot_peppers",
  "scotch_bonnet",
  "habanero",
  "jalapeno",
  "cayenne",
  "birds_eye",
  "bird_eye",
  "birds_eye_chilli",
  "tomato",
  "tomatoes",
  "cherry_tomato",
  "cherry_tomatoes",
  "plum_tomato",
  "roma_tomato",
  "beefsteak_tomato",
  "grape_tomato",
  "heirloom_tomato",
  "paste_tomato",
  "eggplant",
  "eggplants",
  "aubergine",
  "aubergines",
  "garden_egg",
  "garden_eggs",
  "african_eggplant",
  "gboma",
  "nsuu",
];
const List<String> _draftRepairLegumeCropAliases = [
  "bean",
  "beans",
  "green_bean",
  "green_beans",
  "snap_bean",
  "snap_beans",
  "french_bean",
  "french_beans",
  "kidney_bean",
  "kidney_beans",
  "black_bean",
  "black_beans",
  "navy_bean",
  "navy_beans",
  "lima_bean",
  "lima_beans",
  "mung_bean",
  "mung_beans",
  "cowpea",
  "cowpeas",
  "black_eyed_pea",
  "black_eyed_peas",
  "soy",
  "soybean",
  "soybeans",
  "groundnut",
  "groundnuts",
  "peanut",
  "peanuts",
  "bambara_groundnut",
  "bambara_groundnuts",
  "chickpea",
  "chickpeas",
  "pigeon_pea",
  "pigeon_peas",
  "lentil",
  "lentils",
  "garden_pea",
  "garden_peas",
  "field_pea",
  "field_peas",
  "green_pea",
  "green_peas",
  "snap_pea",
  "snap_peas",
  "snow_pea",
  "snow_peas",
  "sugar_snap_pea",
  "sugar_snap_peas",
  "broad_bean",
  "broad_beans",
  "fava_bean",
  "fava_beans",
];
const List<String> _draftRepairGrainCropAliases = [
  "rice",
  "paddy",
  "maize",
  "corn",
  "sweet_corn",
  "dent_corn",
  "flint_corn",
  "popcorn",
  "baby_corn",
  "sorghum",
  "millet",
  "pearl_millet",
  "finger_millet",
  "foxtail_millet",
  "proso_millet",
  "barnyard_millet",
  "wheat",
  "barley",
  "oat",
  "oats",
  "rye",
  "teff",
  "fonio",
  "triticale",
];
const List<String> _draftRepairDirectFruitingCropAliases = [
  "okra",
  "okro",
  "cucumber",
  "cucumbers",
  "gherkin",
  "gherkins",
  "pickling_cucumber",
  "watermelon",
  "watermelons",
  "melon",
  "melons",
  "cantaloupe",
  "muskmelon",
  "muskmelons",
  "honeydew",
  "pumpkin",
  "pumpkins",
  "squash",
  "squashes",
  "zucchini",
  "zucchinis",
  "courgette",
  "courgettes",
  "bottle_gourd",
  "bottle_gourds",
  "bitter_gourd",
  "bitter_gourds",
  "sponge_gourd",
  "ridge_gourd",
  "luffa",
  "calabash",
  "marrow",
  "butternut",
  "butternut_squash",
  "kabocha",
  "winter_squash",
  "snake_gourd",
  "ash_gourd",
];
const List<String> _projectionStagePreparationKeywords = [
  "prepare",
  "preparation",
  "clear",
  "clearing",
  "soil",
  "moisture",
  "land",
  "till",
  "level",
  "safety check",
  "procure",
  "purchase",
  "buy",
  "parts",
  "material",
  "foundation",
];
const List<String> _projectionStageExecutionKeywords = [
  "plant",
  "sow",
  "assemble",
  "assembly",
  "build",
  "construct",
  "install",
  "fabricate",
  "produce",
];
const List<String> _projectionStageOperationsKeywords = [
  "monitor",
  "inspection",
  "inspect",
  "quality",
  "irrigation",
  "nutrient",
  "weed",
  "pest",
  "maintain",
  "maintenance",
  "test",
];
const List<String> _projectionStageClosureKeywords = [
  "harvest",
  "finish",
  "final",
  "finalize",
  "dispatch",
  "delivery",
  "handover",
];

const int _queryPage = 1;
const int _queryLimit = 50;
const String _assetTypeEstate = "estate";
const double _assistantDesktopLayoutBreakpoint = 1120;
const double _assistantTabletLayoutBreakpoint = 820;
const double _assistantDesktopSidebarMinWidth = 320;
const double _assistantDesktopSidebarMaxWidth = 380;

// WHY: Give the assistant explicit role-to-task capability hints to reduce role/task mismatch.
const Map<String, List<String>> _assistantRoleTaskKeywordHints = {
  staffRoleFarmer: [
    "seed",
    "sowing",
    "germination",
    "seedling",
    "tray",
    "emergence",
    "field preparation",
    "soil",
    "moisture",
    "plant",
    "stand count",
    "transplant",
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

enum _CreateWizardStep { productionType, estate, crop, timing, people, review }

enum _DraftStudioPanel { overview, staffing, notes, settings }

class _ProductionPlanAssistantScreenState
    extends ConsumerState<ProductionPlanAssistantScreen> {
  final ScrollController _messagesScrollCtrl = ScrollController();
  final TextEditingController _draftTitleCtrl = TextEditingController();
  final TextEditingController _draftNotesCtrl = TextEditingController();
  final Set<String> _focusedRoleKeys = <String>{};
  final Set<String> _focusedStaffProfileIds = <String>{};
  bool _hasConfirmedStaffContext = false;
  bool _hasConfirmedWorkloadContext = false;
  bool _syncingDraftControllers = false;
  bool _isInitializingSession = true;
  bool _isLinkingPlannerCropProduct = false;
  bool _isImportingDraftDocument = false;
  bool _isImprovingDraft = false;

  String? _selectedEstateAssetId;
  String? _selectedProductId;
  ProductionAssistantCatalogItem? _selectedPlannerCatalogItem;
  String _selectedProductName = "";
  String _selectedProductLifecycleLabel = "";
  String _selectedProductSourceLabel = "";
  String _workUnitLabel = "";
  int? _totalWorkUnits;
  int? _minStaffPerUnit;
  int? _maxStaffPerUnit;
  int _activeStaffAvailabilityPercent = 70;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _useAiInferredDates = false;
  String _domainContext = productionDomainDefault;
  bool _domainExplicitlySelected = false;
  bool _isSending = false;
  bool _showDraftStudio = false;
  String _lastAutoGenerateKey = "";
  _CreateWizardStep _currentWizardStep = _CreateWizardStep.productionType;
  _DraftStudioPanel _draftStudioPanel = _DraftStudioPanel.overview;
  final List<_ChatMessage> _messages = [];
  ProductionAssistantTurn? _lastTurn;
  _DraftImprovementReport? _lastDraftImprovementReport;

  @override
  void initState() {
    super.initState();
    _draftTitleCtrl.addListener(_onDraftTitleChanged);
    _draftNotesCtrl.addListener(_onDraftNotesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _resetPlannerSession(showSnack: false, announce: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializingSession = false;
      });
    });
  }

  @override
  void dispose() {
    _messagesScrollCtrl.dispose();
    _draftTitleCtrl.dispose();
    _draftNotesCtrl.dispose();
    super.dispose();
  }

  void _onDraftTitleChanged() {
    if (_syncingDraftControllers) {
      return;
    }
    ref
        .read(productionPlanDraftProvider.notifier)
        .updateTitle(_draftTitleCtrl.text);
  }

  void _onDraftNotesChanged() {
    if (_syncingDraftControllers) {
      return;
    }
    ref
        .read(productionPlanDraftProvider.notifier)
        .updateNotes(_draftNotesCtrl.text);
  }

  void _syncDraftEditors(ProductionPlanDraftState draft) {
    _syncingDraftControllers = true;
    if (_draftTitleCtrl.text != draft.title) {
      _draftTitleCtrl.value = TextEditingValue(
        text: draft.title,
        selection: TextSelection.collapsed(offset: draft.title.length),
      );
    }
    if (_draftNotesCtrl.text != draft.notes) {
      _draftNotesCtrl.value = TextEditingValue(
        text: draft.notes,
        selection: TextSelection.collapsed(offset: draft.notes.length),
      );
    }
    _syncingDraftControllers = false;
  }

  void _resetPlannerSession({required bool showSnack, bool announce = true}) {
    ref.read(productionPlanDraftProvider.notifier).reset();
    final defaultDomain = productionDomainDefault;
    final defaultWorkUnit = _defaultWorkUnitLabelForDomain(defaultDomain);
    if (mounted) {
      setState(() {
        _focusedRoleKeys.clear();
        _focusedStaffProfileIds.clear();
        _hasConfirmedStaffContext = false;
        _hasConfirmedWorkloadContext = false;
        _selectedEstateAssetId = null;
        _selectedProductId = null;
        _selectedPlannerCatalogItem = null;
        _selectedProductName = "";
        _selectedProductLifecycleLabel = "";
        _selectedProductSourceLabel = "";
        _workUnitLabel = defaultWorkUnit;
        _totalWorkUnits = 10;
        _minStaffPerUnit = 1;
        _maxStaffPerUnit = 3;
        _activeStaffAvailabilityPercent = 70;
        _startDate = null;
        _endDate = null;
        _useAiInferredDates = false;
        _domainContext = defaultDomain;
        _domainExplicitlySelected = false;
        _isSending = false;
        _showDraftStudio = false;
        _lastAutoGenerateKey = "";
        _currentWizardStep = _CreateWizardStep.productionType;
        _draftStudioPanel = _DraftStudioPanel.overview;
        _lastTurn = null;
        _lastDraftImprovementReport = null;
        _messages
          ..clear()
          ..add(const _ChatMessage(fromAssistant: true, text: _welcomeMessage))
          ..add(
            const _ChatMessage(
              fromAssistant: true,
              text: _guideQuestionBusinessType,
            ),
          );
      });
    } else {
      _focusedRoleKeys.clear();
      _focusedStaffProfileIds.clear();
      _hasConfirmedStaffContext = false;
      _hasConfirmedWorkloadContext = false;
      _selectedEstateAssetId = null;
      _selectedProductId = null;
      _selectedPlannerCatalogItem = null;
      _selectedProductName = "";
      _selectedProductLifecycleLabel = "";
      _selectedProductSourceLabel = "";
      _workUnitLabel = defaultWorkUnit;
      _totalWorkUnits = 10;
      _minStaffPerUnit = 1;
      _maxStaffPerUnit = 3;
      _activeStaffAvailabilityPercent = 70;
      _startDate = null;
      _endDate = null;
      _useAiInferredDates = false;
      _domainContext = defaultDomain;
      _domainExplicitlySelected = false;
      _isSending = false;
      _showDraftStudio = false;
      _lastAutoGenerateKey = "";
      _currentWizardStep = _CreateWizardStep.productionType;
      _draftStudioPanel = _DraftStudioPanel.overview;
      _lastTurn = null;
      _lastDraftImprovementReport = null;
      _messages
        ..clear()
        ..add(const _ChatMessage(fromAssistant: true, text: _welcomeMessage))
        ..add(
          const _ChatMessage(
            fromAssistant: true,
            text: _guideQuestionBusinessType,
          ),
        );
    }
    _syncDraftEditors(ref.read(productionPlanDraftProvider));
    if (showSnack && mounted) {
      _showSnack("Started a blank production plan.");
    }
    if (announce) {
      AppDebug.log(_logTag, "planner_session_reset");
    }
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

  Widget _buildDraftRepairSummaryChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            "$label: $value",
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  bool _hasSelectedProduct() {
    return (_selectedProductId ?? "").trim().isNotEmpty ||
        _selectedProductName.trim().isNotEmpty;
  }

  String _resolveProductSourceLabel(String rawSource) {
    switch (rawSource.trim()) {
      case "agriculture_api_geoglam":
        return "Agriculture API (GEOGLAM)";
      case "agriculture_api_trefle":
        return "Agriculture API (Trefle)";
      case "verified_store":
        return "Verified lifecycle store";
      case "cache":
        return "Planner lifecycle cache";
      case "catalog":
      case "planner_catalog":
        return "Planner crop database";
      case "business_product":
        return "Business product";
      default:
        return rawSource.trim();
    }
  }

  String _resolveCropVerificationLabel(String rawStatus) {
    switch (rawStatus.trim()) {
      case "source_verified":
        return "Source verified";
      case "manual_verified":
        return "Manual review complete";
      case "review_required":
        return "Needs review";
      case "seed_manifest":
        return "Seed target";
      case "source_pending":
        return "Source pending";
      default:
        return rawStatus.trim().replaceAll("_", " ");
    }
  }

  String _buildPlannerCropAutoCreatedProductDescription(
    ProductionAssistantCatalogItem selected,
  ) {
    final parts = <String>[
      if (selected.summary.trim().isNotEmpty) selected.summary.trim(),
      if (selected.scientificName.trim().isNotEmpty)
        "Scientific name: ${selected.scientificName.trim()}",
      if (selected.family.trim().isNotEmpty)
        "Family: ${selected.family.trim()}",
      if (selected.lifecycleLabel.trim().isNotEmpty)
        "Lifecycle estimate: ${selected.lifecycleLabel.trim()}",
      "Pre-filled from planner crop selection for production planning. Complete pricing, stock, selling options, and images before saving.",
    ];
    return parts.join(" ");
  }

  String _buildSelectedPlannerCropAutoCreatedProductDescription(
    String productName,
  ) {
    final parts = <String>[
      if (productName.trim().isNotEmpty) "Planner crop: ${productName.trim()}",
      if (_selectedProductLifecycleLabel.trim().isNotEmpty)
        "Lifecycle estimate: ${_selectedProductLifecycleLabel.trim()}",
      "Pre-filled from planner crop selection for production planning. Complete pricing, stock, selling options, and images before saving.",
    ];
    return parts.join(" ");
  }

  String _normalizePlannerCropLookupText(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "_");
  }

  String _resolvePlannerCropProductSubcategory({
    ProductionAssistantCatalogItem? selected,
    required String productName,
  }) {
    final catalogCategory = selected?.category.trim().toLowerCase() ?? "";
    final plantType = selected?.plantType.trim().toLowerCase() ?? "";
    final normalizedName = _normalizePlannerCropLookupText(productName);
    final aliasPool = <String>[
      normalizedName,
      if ((selected?.cropKey ?? "").trim().isNotEmpty)
        _normalizePlannerCropLookupText(selected!.cropKey),
      if ((selected?.variety ?? "").trim().isNotEmpty)
        _normalizePlannerCropLookupText(selected!.variety),
      for (final alias in selected?.aliases ?? const <String>[])
        _normalizePlannerCropLookupText(alias),
    ].join(" ");

    if (catalogCategory.contains("legume") ||
        _draftRepairMatchesAnyAlias(aliasPool, _draftRepairLegumeCropAliases)) {
      return "Legumes";
    }
    if (catalogCategory.contains("grain") ||
        catalogCategory.contains("cereal") ||
        _draftRepairMatchesAnyAlias(aliasPool, _draftRepairGrainCropAliases)) {
      return "Grains & Cereals";
    }
    if (catalogCategory.contains("fruit")) {
      return "Fruits";
    }
    if (catalogCategory.contains("herb") || catalogCategory.contains("spice")) {
      return "Herbs & Spices";
    }
    if (catalogCategory.contains("seed") ||
        plantType.contains("seedling") ||
        aliasPool.contains("seedling")) {
      return "Seeds & Seedlings";
    }
    if (catalogCategory.contains("tuber") ||
        aliasPool.contains("cassava") ||
        aliasPool.contains("yam") ||
        aliasPool.contains("potato")) {
      return "Tubers";
    }
    if (catalogCategory.contains("vegetable") ||
        plantType.contains("vine") ||
        plantType.contains("shrub") ||
        _draftRepairMatchesAnyAlias(
          aliasPool,
          _draftRepairDirectFruitingCropAliases,
        )) {
      return "Vegetables";
    }
    return "Vegetables";
  }

  List<ProductSellingOption> _resolvePlannerCropSellingOptions({
    required String subcategory,
  }) {
    switch (subcategory) {
      case "Grains & Cereals":
        return const [
          ProductSellingOption(
            packageType: "Bag",
            quantity: 5,
            measurementUnit: "kg",
            isDefault: true,
          ),
          ProductSellingOption(
            packageType: "Bag",
            quantity: 20,
            measurementUnit: "kg",
            isDefault: false,
          ),
          ProductSellingOption(
            packageType: "Sack",
            quantity: 50,
            measurementUnit: "kg",
            isDefault: false,
          ),
        ];
      case "Legumes":
        return const [
          ProductSellingOption(
            packageType: "Bag",
            quantity: 5,
            measurementUnit: "kg",
            isDefault: true,
          ),
          ProductSellingOption(
            packageType: "Bag",
            quantity: 25,
            measurementUnit: "kg",
            isDefault: false,
          ),
          ProductSellingOption(
            packageType: "Sack",
            quantity: 50,
            measurementUnit: "kg",
            isDefault: false,
          ),
        ];
      case "Fruits":
        return const [
          ProductSellingOption(
            packageType: "Piece",
            quantity: 1,
            measurementUnit: "piece",
            isDefault: true,
          ),
          ProductSellingOption(
            packageType: "Basket",
            quantity: 5,
            measurementUnit: "kg",
            isDefault: false,
          ),
          ProductSellingOption(
            packageType: "Crate",
            quantity: 20,
            measurementUnit: "kg",
            isDefault: false,
          ),
        ];
      case "Vegetables":
      case "Herbs & Spices":
        return const [
          ProductSellingOption(
            packageType: "Basket",
            quantity: 5,
            measurementUnit: "kg",
            isDefault: true,
          ),
          ProductSellingOption(
            packageType: "Bag",
            quantity: 20,
            measurementUnit: "kg",
            isDefault: false,
          ),
          ProductSellingOption(
            packageType: "Carton",
            quantity: 10,
            measurementUnit: "kg",
            isDefault: false,
          ),
        ];
      case "Seeds & Seedlings":
        return const [
          ProductSellingOption(
            packageType: "Piece",
            quantity: 1,
            measurementUnit: "piece",
            isDefault: true,
          ),
          ProductSellingOption(
            packageType: "Pack",
            quantity: 10,
            measurementUnit: "piece",
            isDefault: false,
          ),
          ProductSellingOption(
            packageType: "Tray",
            quantity: 50,
            measurementUnit: "piece",
            isDefault: false,
          ),
        ];
      case "Tubers":
        return const [
          ProductSellingOption(
            packageType: "Piece",
            quantity: 1,
            measurementUnit: "piece",
            isDefault: true,
          ),
          ProductSellingOption(
            packageType: "Basket",
            quantity: 10,
            measurementUnit: "kg",
            isDefault: false,
          ),
          ProductSellingOption(
            packageType: "Bag",
            quantity: 20,
            measurementUnit: "kg",
            isDefault: false,
          ),
        ];
      default:
        return const [
          ProductSellingOption(
            packageType: "Piece",
            quantity: 1,
            measurementUnit: "piece",
            isDefault: true,
          ),
        ];
    }
  }

  ProductDraft _buildPlannerCropInitialDraft({
    ProductionAssistantCatalogItem? selected,
    required String productName,
  }) {
    final subcategory = _resolvePlannerCropProductSubcategory(
      selected: selected,
      productName: productName,
    );
    final sellingOptions = _resolvePlannerCropSellingOptions(
      subcategory: subcategory,
    );

    return ProductDraft(
      name: productName.trim(),
      description: selected != null
          ? _buildPlannerCropAutoCreatedProductDescription(selected)
          : _buildSelectedPlannerCropAutoCreatedProductDescription(productName),
      category: "Farm & Agro",
      subcategory: subcategory,
      brand: "",
      sellingOptions: sellingOptions,
      sellingUnits: sellingOptions.map((option) => option.packageType).toList(),
      defaultSellingUnit: sellingOptions.first.packageType,
      priceNgn: 0,
      stock: 0,
    );
  }

  String _buildPlannerCropContextAiPrompt({
    ProductionAssistantCatalogItem? selected,
    required String productName,
  }) {
    final subcategory = _resolvePlannerCropProductSubcategory(
      selected: selected,
      productName: productName,
    );
    final aliasText = (selected?.aliases ?? const <String>[])
        .where((item) => item.trim().isNotEmpty)
        .take(6)
        .join(", ");
    final phaseText = (selected?.phases ?? const <String>[])
        .where((item) => item.trim().isNotEmpty)
        .take(6)
        .join(", ");

    return [
      "Draft a business product for a production-planning farm crop.",
      "Product name: ${productName.trim()}.",
      "Category must be exactly Farm & Agro.",
      "Infer the best farm subcategory for this crop and fill it.",
      "Do not invent or autofill brand. Return brand as an empty string.",
      "Suggest realistic farm selling options for this crop in market packaging, not generic retail packaging.",
      "Beans and similar legumes are commonly sold in bags or sacks.",
      "Peppers and similar vegetables are commonly sold in baskets, bags, cartons, or crates.",
      "If price or stock is uncertain, return a practical starter value rather than leaving the draft empty.",
      "Keep the description useful for a real product setup, not a botanical essay.",
      "Crop family/subtype target: $subcategory.",
      if ((selected?.summary ?? "").trim().isNotEmpty)
        "Planner summary: ${selected!.summary.trim()}",
      if ((selected?.scientificName ?? "").trim().isNotEmpty)
        "Scientific name: ${selected!.scientificName.trim()}",
      if ((selected?.family ?? "").trim().isNotEmpty)
        "Family: ${selected!.family.trim()}",
      if ((selected?.category ?? "").trim().isNotEmpty)
        "Planner crop category: ${selected!.category.trim()}",
      if ((selected?.plantType ?? "").trim().isNotEmpty)
        "Plant type: ${selected!.plantType.trim()}",
      if ((selected?.variety ?? "").trim().isNotEmpty)
        "Variety hint: ${selected!.variety.trim()}",
      if (aliasText.isNotEmpty) "Known aliases: $aliasText",
      if ((selected?.lifecycleLabel ?? "").trim().isNotEmpty)
        "Lifecycle estimate: ${selected!.lifecycleLabel.trim()}",
      if (phaseText.isNotEmpty) "Lifecycle phases: $phaseText",
      if ((selected?.source ?? "").trim().isNotEmpty)
        "Planner source: ${selected!.source.trim()}",
    ].join("\n");
  }

  bool _isBusinessProductReadyForProduction(Product product) {
    final hasImage =
        product.imageUrl.trim().isNotEmpty ||
        product.imageUrls.any((item) => item.trim().isNotEmpty);
    return product.name.trim().isNotEmpty &&
        product.category.trim().isNotEmpty &&
        product.subcategory.trim().isNotEmpty &&
        product.priceCents > 0 &&
        product.sellingOptions.isNotEmpty &&
        product.defaultSellingOption != null &&
        hasImage;
  }

  List<String> _missingBusinessProductRequirements(Product product) {
    final missing = <String>[];
    if (product.category.trim().isEmpty) {
      missing.add("category");
    }
    if (product.subcategory.trim().isEmpty) {
      missing.add("subcategory");
    }
    if (product.priceCents <= 0) {
      missing.add("price");
    }
    if (product.sellingOptions.isEmpty ||
        product.defaultSellingOption == null) {
      missing.add("selling options");
    }
    final hasImage =
        product.imageUrl.trim().isNotEmpty ||
        product.imageUrls.any((item) => item.trim().isNotEmpty);
    if (!hasImage) {
      missing.add("image");
    }
    return missing;
  }

  Future<Product?> _fetchBusinessProductById({
    required String productId,
  }) async {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      return null;
    }
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      return null;
    }
    try {
      return await ref
          .read(businessProductApiProvider)
          .fetchProductById(token: session.token, id: normalizedProductId);
    } catch (_) {
      return null;
    }
  }

  Future<Product?> _findExistingBusinessProductByName({
    required String productName,
  }) async {
    final normalizedProductName = productName.trim();
    if (normalizedProductName.isEmpty) {
      return null;
    }
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      return null;
    }
    final products = await ref
        .read(businessProductApiProvider)
        .fetchProducts(
          token: session.token,
          page: 1,
          limit: 10,
          searchQuery: normalizedProductName,
        );
    for (final product in products) {
      if (product.name.trim().toLowerCase() ==
          normalizedProductName.toLowerCase()) {
        return product.id.trim().isEmpty ? null : product;
      }
    }
    return null;
  }

  Future<Product?> _openPlannerCropProductSetup({
    required String productName,
    required ProductionAssistantCatalogItem? selected,
    Product? existingProduct,
  }) async {
    final saved = await showBusinessProductFormSheet(
      context: context,
      product: existingProduct,
      initialDraft: existingProduct == null
          ? _buildPlannerCropInitialDraft(
              selected: selected,
              productName: productName,
            )
          : null,
      requireCompleteSetup: true,
      contextAiPrompt: _buildPlannerCropContextAiPrompt(
        selected: selected,
        productName: productName,
      ),
      forcedAiCategory: "Farm & Agro",
      preserveBrandOnAiDraft: false,
      onSuccess: (_) async {
        ref.invalidate(
          businessProductsProvider(
            const BusinessProductsQuery(page: _queryPage, limit: _queryLimit),
          ),
        );
      },
    );
    if (saved == null) {
      return null;
    }
    if (!_isBusinessProductReadyForProduction(saved)) {
      _showSnack(
        "Complete ${_missingBusinessProductRequirements(saved).join(", ")} before this crop can be used in production.",
      );
      return null;
    }
    return saved.id.trim().isEmpty ? null : saved;
  }

  Future<Product?> _resolvePlannerCropBusinessProduct({
    required String productName,
    required ProductionAssistantCatalogItem? selected,
  }) async {
    final linkedProductId = (selected?.linkedProductId ?? "").trim();
    Product? existingProduct;
    if (linkedProductId.isNotEmpty) {
      existingProduct = await _fetchBusinessProductById(
        productId: linkedProductId,
      );
    }
    existingProduct ??= await _findExistingBusinessProductByName(
      productName: productName,
    );

    if (existingProduct != null &&
        _isBusinessProductReadyForProduction(existingProduct)) {
      return existingProduct;
    }

    return _openPlannerCropProductSetup(
      productName: productName,
      selected: selected,
      existingProduct: existingProduct,
    );
  }

  Future<String?> _autoCreateBusinessProductForPlannerCrop({
    required ProductionAssistantCatalogItem selected,
  }) async {
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      return null;
    }

    AppDebug.log(
      _logTag,
      _plannerCropAutoCreateProductStartLog,
      extra: {"cropKey": selected.cropKey, "productName": selected.name},
    );

    try {
      final resolvedProduct = await _resolvePlannerCropBusinessProduct(
        productName: selected.name,
        selected: selected,
      );
      if (resolvedProduct == null) {
        _showSnack(_plannerCropAutoCreateProductFailureSnack);
        return null;
      }
      ref.invalidate(
        businessProductsProvider(
          const BusinessProductsQuery(page: _queryPage, limit: _queryLimit),
        ),
      );
      AppDebug.log(
        _logTag,
        _plannerCropAutoCreateProductSuccessLog,
        extra: {
          "cropKey": selected.cropKey,
          "productId": resolvedProduct.id,
          "mode": "linked_ready",
        },
      );
      _showSnack(_plannerCropAutoCreateProductSuccessSnack);
      return resolvedProduct.id.trim().isEmpty
          ? null
          : resolvedProduct.id.trim();
    } catch (error) {
      AppDebug.log(
        _logTag,
        _plannerCropAutoCreateProductFailLog,
        extra: {
          "cropKey": selected.cropKey,
          "productName": selected.name,
          "error": error.toString(),
        },
      );
      _showSnack(_plannerCropAutoCreateProductFailureSnack);
      return null;
    }
  }

  Future<String?> _ensureCurrentSelectedCropLinkedProduct({
    bool announceSuccess = true,
  }) async {
    final existingSelectedProductId = (_selectedProductId ?? "").trim();
    if (existingSelectedProductId.isNotEmpty) {
      final existingSelectedProduct = await _fetchBusinessProductById(
        productId: existingSelectedProductId,
      );
      if (existingSelectedProduct != null &&
          _isBusinessProductReadyForProduction(existingSelectedProduct)) {
        return existingSelectedProductId;
      }
    }
    final productName = _resolveSelectedProductName().trim();
    if (productName.isEmpty) {
      return null;
    }
    if (_isLinkingPlannerCropProduct) {
      return null;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      return null;
    }

    setState(() {
      _isLinkingPlannerCropProduct = true;
    });

    try {
      final resolvedProduct = await _resolvePlannerCropBusinessProduct(
        productName: productName,
        selected: _selectedPlannerCatalogItem,
      );
      final resolvedProductId = resolvedProduct?.id.trim().isEmpty ?? true
          ? null
          : resolvedProduct!.id.trim();
      if (resolvedProductId == null) {
        _showSnack(_plannerCropAutoCreateProductFailureSnack);
        return null;
      }
      ref.invalidate(
        businessProductsProvider(
          const BusinessProductsQuery(page: _queryPage, limit: _queryLimit),
        ),
      );
      if (!mounted) {
        return resolvedProductId;
      }
      setState(() {
        _applySelectedProductState(
          productId: resolvedProductId,
          productName: productName,
          productLifecycleLabel: _selectedProductLifecycleLabel,
          productSourceLabel: _selectedProductSourceLabel,
        );
      });
      if (announceSuccess) {
        _showSnack(_plannerCropAutoCreateProductSuccessSnack);
      }
      return resolvedProductId;
    } catch (error) {
      AppDebug.log(
        _logTag,
        _plannerCropAutoCreateProductFailLog,
        extra: {
          "productName": productName,
          "error": error.toString(),
          "mode": "review_recovery",
        },
      );
      _showSnack(_plannerCropAutoCreateProductFailureSnack);
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isLinkingPlannerCropProduct = false;
        });
      }
    }
  }

  Future<void> _resolveSelectedPlannerCropLifecycle({
    required ProductionAssistantCatalogItem selected,
    String? linkedProductIdOverride,
  }) async {
    final normalizedOverride = (linkedProductIdOverride ?? "").trim();
    final selectedProductId = normalizedOverride.isNotEmpty
        ? normalizedOverride
        : selected.linkedProductId.isEmpty
        ? null
        : selected.linkedProductId;
    try {
      final preview = await ref
          .read(productionPlanActionsProvider)
          .previewAssistantCropLifecycle(
            productName: selected.name,
            domainContext: _domainContext,
            estateAssetId: _selectedEstateAssetId,
          );
      if (!mounted) {
        return;
      }
      if (_resolveSelectedProductName() != selected.name.trim()) {
        return;
      }
      setState(() {
        _applySelectedProductState(
          productId: selectedProductId,
          productName: selected.name,
          productLifecycleLabel: preview.lifecycle.lifecycleLabel,
          productSourceLabel: _resolveProductSourceLabel(
            preview.lifecycleSource,
          ),
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (_resolveSelectedProductName() != selected.name.trim()) {
        return;
      }
      setState(() {
        _applySelectedProductState(
          productId: selectedProductId,
          productName: selected.name,
          productLifecycleLabel: _plannerCropLifecyclePendingLabel,
          productSourceLabel: _resolveProductSourceLabel(selected.source),
        );
      });
      _showSnack(_plannerCropLifecycleFallbackSnack);
    }
  }

  String _resolveSelectedProductName() {
    if (_selectedProductName.trim().isNotEmpty) {
      return _selectedProductName.trim();
    }
    return _resolveSelectedProductNameFromProvider();
  }

  void _applySelectedProductState({
    required String? productId,
    required String productName,
    String productLifecycleLabel = "",
    String productSourceLabel = "",
  }) {
    final normalizedProductId = (productId ?? "").trim();
    _selectedProductId = normalizedProductId.isEmpty
        ? null
        : normalizedProductId;
    _selectedProductName = productName.trim();
    _selectedProductLifecycleLabel = productLifecycleLabel.trim();
    _selectedProductSourceLabel = productSourceLabel.trim();
  }

  void _syncSelectedProductFromDraft(
    ProductionAssistantPlanDraftPayload? payload,
  ) {
    if (payload == null) {
      return;
    }
    final nextProductId = payload.productId.trim();
    final nextProductName = payload.productName.trim();
    if (nextProductId.isEmpty && nextProductName.isEmpty) {
      return;
    }
    _applySelectedProductState(
      productId: nextProductId.isEmpty ? _selectedProductId : nextProductId,
      productName: nextProductName.isEmpty
          ? _resolveSelectedProductName()
          : nextProductName,
      productLifecycleLabel: _selectedProductLifecycleLabel,
      productSourceLabel: _selectedProductSourceLabel.trim().isEmpty
          ? _resolveProductSourceLabel("planner_catalog")
          : _selectedProductSourceLabel,
    );
  }

  Map<String, dynamic> _buildDirectDraftGenerationPayload({
    required String prompt,
    required List<String> focusedRoles,
    required List<BusinessStaffProfileSummary> focusedStaffProfiles,
  }) {
    final focusedStaffProfilesPayload = _buildFocusedStaffProfilesPayload(
      focusedStaffProfiles: focusedStaffProfiles,
    );
    final focusedStaffByRolePayload = _buildFocusedStaffProfileIdsByRolePayload(
      focusedStaffProfilesPayload: focusedStaffProfilesPayload,
    );
    return {
      "aiBrief": prompt,
      "prompt": prompt,
      "estateAssetId": _selectedEstateAssetId ?? "",
      "productId": _selectedProductId ?? "",
      "productSearchName": _resolveSelectedProductName(),
      "startDate": _startDate == null ? "" : formatDateInput(_startDate!),
      "endDate": _endDate == null ? "" : formatDateInput(_endDate!),
      "domainContext": _domainContext,
      "businessType": _domainContext,
      "focusedRoles": focusedRoles,
      "focusedStaffProfileIds": _focusedStaffProfileIds.toList()..sort(),
      "focusedStaffProfiles": focusedStaffProfilesPayload,
      "focusedStaffByRole": focusedStaffByRolePayload,
      "focusedRoleTaskHints": {
        for (final role in focusedRoles)
          role:
              _assistantRoleTaskKeywordHints[_normalizeRoleKey(role)] ??
              const <String>[],
      },
      "workloadContext": {
        "workUnitLabel": _workUnitLabel.trim(),
        "totalWorkUnits": _totalWorkUnits ?? 0,
        "minStaffPerUnit": _minStaffPerUnit ?? 0,
        "maxStaffPerUnit": _maxStaffPerUnit ?? 0,
        "activeStaffAvailabilityPercent": _activeStaffAvailabilityPercent,
        "hasConfirmedWorkloadContext": _hasConfirmedWorkloadContext,
      },
      "cropSubtype": "",
    };
  }

  String _normalizeDraftPreviewMatchSegment(String value) {
    return _normalizeLifecycleTaskTitle(
      value,
    ).trim().toLowerCase().replaceAll(RegExp(r"\s+"), " ");
  }

  String _buildDraftPreviewStrictKey({
    required String phaseName,
    required String title,
    required String roleRequired,
  }) {
    return "${_normalizeDraftPreviewMatchSegment(phaseName)}|${_normalizeDraftPreviewMatchSegment(title)}|${_normalizeRoleKey(roleRequired)}";
  }

  String _buildDraftPreviewLooseKey({
    required String title,
    required String roleRequired,
  }) {
    return "${_normalizeDraftPreviewMatchSegment(title)}|${_normalizeRoleKey(roleRequired)}";
  }

  ProductionAssistantPlanDraftPayload
  _buildAssistantPlanDraftPayloadFromAiDraft({
    required ProductionAiDraftResult draftResult,
    required String fallbackProductName,
  }) {
    final strictPreviewBuckets = <String, List<ProductionAiDraftTaskPreview>>{};
    final loosePreviewBuckets = <String, List<ProductionAiDraftTaskPreview>>{};

    void addPreviewBucket({
      required Map<String, List<ProductionAiDraftTaskPreview>> buckets,
      required String key,
      required ProductionAiDraftTaskPreview preview,
    }) {
      final bucket = buckets.putIfAbsent(
        key,
        () => <ProductionAiDraftTaskPreview>[],
      );
      bucket.add(preview);
    }

    for (final preview in draftResult.tasks) {
      addPreviewBucket(
        buckets: strictPreviewBuckets,
        key: _buildDraftPreviewStrictKey(
          phaseName: preview.phaseName,
          title: preview.title,
          roleRequired: preview.roleRequired,
        ),
        preview: preview,
      );
      addPreviewBucket(
        buckets: loosePreviewBuckets,
        key: _buildDraftPreviewLooseKey(
          title: preview.title,
          roleRequired: preview.roleRequired,
        ),
        preview: preview,
      );
    }

    ProductionAiDraftTaskPreview? takePreviewForTask({
      required String phaseName,
      required ProductionTaskDraft task,
    }) {
      final strictKey = _buildDraftPreviewStrictKey(
        phaseName: phaseName,
        title: task.title,
        roleRequired: task.roleRequired,
      );
      final strictBucket = strictPreviewBuckets[strictKey];
      if (strictBucket != null && strictBucket.isNotEmpty) {
        return strictBucket.removeAt(0);
      }
      final looseKey = _buildDraftPreviewLooseKey(
        title: task.title,
        roleRequired: task.roleRequired,
      );
      final looseBucket = loosePreviewBuckets[looseKey];
      if (looseBucket != null && looseBucket.isNotEmpty) {
        return looseBucket.removeAt(0);
      }
      return null;
    }

    final mappedPhases = draftResult.draft.phases
        .map((phase) {
          final mappedTasks = phase.tasks
              .map((task) {
                final preview = takePreviewForTask(
                  phaseName: phase.name,
                  task: task,
                );
                return ProductionAssistantPlanTask(
                  title: task.title,
                  roleRequired: task.roleRequired,
                  requiredHeadcount: task.requiredHeadcount,
                  weight: task.weight,
                  instructions: task.instructions,
                  taskType: task.taskType,
                  sourceTemplateKey: task.sourceTemplateKey,
                  recurrenceGroupKey: task.recurrenceGroupKey,
                  occurrenceIndex: task.occurrenceIndex,
                  startDate: preview?.startDate,
                  dueDate: preview?.dueDate,
                  assignedStaffProfileIds:
                      preview?.assignedStaffProfileIds ??
                      task.assignedStaffProfileIds,
                );
              })
              .toList(growable: false);
          return ProductionAssistantPlanPhase(
            name: phase.name,
            order: phase.order,
            estimatedDays: phase.estimatedDays,
            phaseType: phase.phaseType,
            requiredUnits: phase.requiredUnits,
            minRatePerFarmerHour: phase.minRatePerFarmerHour,
            targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
            plannedHoursPerDay: phase.plannedHoursPerDay,
            biologicalMinDays: phase.biologicalMinDays,
            tasks: mappedTasks,
          );
        })
        .toList(growable: false);

    final warningPayloads = draftResult.warnings
        .map((message) => message.trim())
        .where((message) => message.isNotEmpty)
        .toList(growable: false);
    final startDate =
        draftResult.summary?.startDate ?? draftResult.draft.startDate;
    final endDate = draftResult.summary?.endDate ?? draftResult.draft.endDate;
    return ProductionAssistantPlanDraftPayload(
      productId:
          draftResult.summary?.productId ??
          (draftResult.draft.productId ?? "").trim(),
      productName: fallbackProductName.trim(),
      startDate: startDate == null ? "" : formatDateInput(startDate),
      endDate: endDate == null ? "" : formatDateInput(endDate),
      days: draftResult.summary?.days ?? draftResult.draft.totalEstimatedDays,
      weeks: draftResult.summary?.weeks ?? 0,
      phases: mappedPhases,
      warnings: warningPayloads
          .asMap()
          .entries
          .map((entry) {
            return ProductionAssistantPlanWarning(
              code: "draft_warning_${entry.key + 1}",
              message: entry.value,
            );
          })
          .toList(growable: false),
      plannerMeta: draftResult.plannerMeta,
      lifecycle: draftResult.lifecycle,
    );
  }

  ProductionAssistantTurn _buildAssistantTurnFromAiDraft({
    required ProductionAiDraftResult draftResult,
    required String fallbackProductName,
  }) {
    return ProductionAssistantTurn(
      action: productionAssistantActionPlanDraft,
      message: draftResult.message.trim().isNotEmpty
          ? draftResult.message.trim()
          : "Planner V2 generated a lifecycle-safe production draft.",
      suggestionsPayload: null,
      clarifyPayload: null,
      draftProductPayload: null,
      planDraftPayload: _buildAssistantPlanDraftPayloadFromAiDraft(
        draftResult: draftResult,
        fallbackProductName: fallbackProductName,
      ),
    );
  }

  String _resolveDirectDraftFailureMessage(Object error) {
    if (error is ProductionAiDraftError && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    final dioError = error is DioException ? error : null;
    final responseData = dioError?.response?.data;
    final responseMap = responseData is Map<String, dynamic>
        ? responseData
        : const <String, dynamic>{};
    final backendErrorMessage = (responseMap[_assistantErrorResponseKey] ?? "")
        .toString()
        .trim();
    if (backendErrorMessage.isNotEmpty) {
      return backendErrorMessage;
    }
    return _assistantErrorMessage;
  }

  Future<void> _runDirectDraftGeneration({
    required String prompt,
    required String productName,
    required List<String> focusedRoles,
    required List<BusinessStaffProfileSummary> focusedStaff,
    String? displayPrompt,
  }) async {
    _appendMessage(
      _ChatMessage(
        fromAssistant: false,
        text: (displayPrompt ?? prompt).trim().isEmpty
            ? prompt
            : (displayPrompt ?? prompt).trim(),
      ),
    );
    setState(() => _isSending = true);

    try {
      final payload = _buildDirectDraftGenerationPayload(
        prompt: prompt,
        focusedRoles: focusedRoles,
        focusedStaffProfiles: focusedStaff,
      );
      final draftResult = await ref
          .read(productionPlanActionsProvider)
          .generateAiDraft(payload: payload);
      final synthesizedTurn = _applyFocusedContextToPlanDraftTurn(
        turn: _buildAssistantTurnFromAiDraft(
          draftResult: draftResult,
          fallbackProductName: productName,
        ),
      );
      final assistantText = synthesizedTurn.message.isNotEmpty
          ? synthesizedTurn.message
          : draftResult.message;
      _appendMessage(_ChatMessage(fromAssistant: true, text: assistantText));
      if (mounted) {
        setState(() {
          _syncSelectedProductFromDraft(synthesizedTurn.planDraftPayload);
          _lastTurn = synthesizedTurn;
        });
      } else {
        _syncSelectedProductFromDraft(synthesizedTurn.planDraftPayload);
        _lastTurn = synthesizedTurn;
      }
      Map<String, Object?>? draftQualitySummary;
      final resolvedPlanDraft = synthesizedTurn.planDraftPayload;
      if (synthesizedTurn.isPlanDraft && resolvedPlanDraft != null) {
        draftQualitySummary = _logDraftQualitySnapshot(
          payload: resolvedPlanDraft,
          sourceAction: synthesizedTurn.action,
        );
        await _applyDraftToStudio(resolvedPlanDraft);
      }
      AppDebug.log(
        _logTag,
        _sendSuccessLog,
        extra: {
          "action": synthesizedTurn.action,
          "path": "direct_ai_draft",
          "hasPlanDraft": synthesizedTurn.planDraftPayload != null,
          if (draftQualitySummary != null) ...draftQualitySummary,
        },
      );
    } catch (error) {
      final message = _resolveDirectDraftFailureMessage(error);
      AppDebug.log(
        _logTag,
        _sendFailureLog,
        extra: {
          "serviceName": "production_assistant_service",
          "operationName": "generateAiDraftFromContext",
          "requestIntent":
              "Generate production draft directly from selected estate/product context.",
          "error": error.toString(),
          "message": message,
          "hasEstate": (_selectedEstateAssetId ?? "").isNotEmpty,
          "hasProduct": _hasSelectedProduct(),
          "focusedRoleCount": focusedRoles.length,
          "focusedStaffCount": focusedStaff.length,
        },
      );
      _appendMessage(
        _ChatMessage(fromAssistant: true, text: message, isError: true),
      );
      _showSnack(message);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
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
        "hasProduct": _hasSelectedProduct(),
        "workUnitLabel": _workUnitLabel.trim(),
        "totalWorkUnits": _totalWorkUnits ?? 0,
        "minStaffPerUnit": _minStaffPerUnit ?? 0,
        "maxStaffPerUnit": _maxStaffPerUnit ?? 0,
        "activeStaffAvailabilityPercent": _activeStaffAvailabilityPercent,
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
              "productSearchName": _resolveSelectedProductName(),
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
              "workloadContext": {
                "workUnitLabel": _workUnitLabel.trim(),
                "totalWorkUnits": _totalWorkUnits ?? 0,
                "minStaffPerUnit": _minStaffPerUnit ?? 0,
                "maxStaffPerUnit": _maxStaffPerUnit ?? 0,
                "activeStaffAvailabilityPercent":
                    _activeStaffAvailabilityPercent,
                "hasConfirmedWorkloadContext": _hasConfirmedWorkloadContext,
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
      setState(() {
        _syncSelectedProductFromDraft(resolvedTurn.planDraftPayload);
        _lastTurn = resolvedTurn;
      });
      Map<String, Object?>? draftQualitySummary;
      final resolvedPlanDraft = resolvedTurn.planDraftPayload;
      if (resolvedTurn.isPlanDraft && resolvedPlanDraft != null) {
        // WHY: Operators requested hard console evidence of weak drafts; this snapshot captures structural quality for review.
        draftQualitySummary = _logDraftQualitySnapshot(
          payload: resolvedPlanDraft,
          sourceAction: resolvedTurn.action,
        );
      }
      AppDebug.log(
        _logTag,
        _sendSuccessLog,
        extra: {
          "action": resolvedTurn.action,
          "hasPlanDraft": resolvedTurn.planDraftPayload != null,
          if (draftQualitySummary != null) ...draftQualitySummary,
        },
      );
    } catch (error) {
      // WHY: Backend assistant failures can include actionable metadata that should be surfaced to operators and logs.
      final dioError = error is DioException ? error : null;
      final responseData = dioError?.response?.data;
      final responseMap = responseData is Map<String, dynamic>
          ? responseData
          : const <String, dynamic>{};
      final providerErrorMessageRaw =
          (responseMap[_assistantErrorResponseKey] ?? "").toString().trim();
      final providerErrorCodeRaw = (responseMap[_assistantErrorCodeKey] ?? "")
          .toString()
          .trim();
      final failureClassificationRaw =
          (responseMap[_assistantClassificationKey] ?? "").toString().trim();
      final resolutionHintRaw = (responseMap[_assistantResolutionHintKey] ?? "")
          .toString()
          .trim();
      final retryReasonRaw = (responseMap[_assistantRetryReasonKey] ?? "")
          .toString()
          .trim();
      final uiErrorMessage = providerErrorMessageRaw.isNotEmpty
          ? providerErrorMessageRaw
          : _assistantErrorMessage;
      final providerErrorCode = providerErrorCodeRaw.isNotEmpty
          ? providerErrorCodeRaw
          : "unknown";
      final failureClassification = failureClassificationRaw.isNotEmpty
          ? failureClassificationRaw
          : _assistantUnknownFailureClassification;
      final resolutionHint = resolutionHintRaw.isNotEmpty
          ? resolutionHintRaw
          : _assistantUnknownFailureResolutionHint;
      final retryReason = retryReasonRaw.isNotEmpty
          ? retryReasonRaw
          : "unknown";
      final retryAllowed = responseMap[_assistantRetryAllowedKey] == true;
      AppDebug.log(
        _logTag,
        _sendFailureLog,
        extra: {
          "serviceName": "production_assistant_service",
          "operationName": "runAssistantTurn",
          "requestIntent":
              "Generate or refine a production lifecycle draft from user context.",
          "sanitizedRequestContext": {
            "source": "production_plan_assistant_screen",
            "hasEstate": (_selectedEstateAssetId ?? "").isNotEmpty,
            "hasProduct": _hasSelectedProduct(),
            "hasStartDate": _startDate != null,
            "hasEndDate": _endDate != null,
            "workloadConfigured": _hasWorkloadContextValues(),
          },
          "httpStatus": dioError?.response?.statusCode ?? "unknown",
          "providerErrorCode": providerErrorCode,
          "providerErrorMessage": providerErrorMessageRaw.isNotEmpty
              ? providerErrorMessageRaw
              : error.toString(),
          "failureClassification": failureClassification,
          "resolutionHint": resolutionHint,
          "retry_allowed": retryAllowed,
          "retry_reason": retryReason,
        },
      );
      _appendMessage(
        _ChatMessage(fromAssistant: true, text: uiErrorMessage, isError: true),
      );
      _showSnack(uiErrorMessage);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Map<String, Object?> _logDraftQualitySnapshot({
    required ProductionAssistantPlanDraftPayload payload,
    required String sourceAction,
  }) {
    final taskCountByPhase = <String, int>{};
    final roleCountByKey = <String, int>{};
    final sampleTasks = <Map<String, Object?>>[];
    var totalTaskCount = 0;
    var phasesWithNoTasksCount = 0;
    var tasksMissingRoleCount = 0;
    var tasksMissingDatesCount = 0;
    var tasksWithInvertedDatesCount = 0;
    var tasksWithNoAssigneeCount = 0;
    var tasksWithInvalidHeadcountCount = 0;
    var tasksWithWeakInstructionsCount = 0;
    DateTime? earliestStartDate;
    DateTime? latestDueDate;

    for (final phase in payload.phases) {
      final safePhaseName = phase.name.trim().isEmpty
          ? "Phase ${phase.order}"
          : phase.name.trim();
      final phaseKey = "${phase.order}:$safePhaseName";
      taskCountByPhase[phaseKey] = phase.tasks.length;
      if (phase.tasks.isEmpty) {
        phasesWithNoTasksCount += 1;
      }
      for (final task in phase.tasks) {
        totalTaskCount += 1;
        final roleKey = _normalizeRoleKey(task.roleRequired);
        if (roleKey.isEmpty) {
          tasksMissingRoleCount += 1;
        } else {
          roleCountByKey[roleKey] = (roleCountByKey[roleKey] ?? 0) + 1;
        }
        if (task.requiredHeadcount < 1) {
          tasksWithInvalidHeadcountCount += 1;
        }
        if (task.instructions.trim().length < 8) {
          tasksWithWeakInstructionsCount += 1;
        }
        final assignedCount = task.assignedStaffProfileIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .length;
        if (assignedCount < 1) {
          tasksWithNoAssigneeCount += 1;
        }

        final startDate = task.startDate;
        final dueDate = task.dueDate;
        if (startDate == null || dueDate == null) {
          tasksMissingDatesCount += 1;
        } else {
          if (dueDate.isBefore(startDate)) {
            tasksWithInvertedDatesCount += 1;
          }
          if (earliestStartDate == null ||
              startDate.isBefore(earliestStartDate)) {
            earliestStartDate = startDate;
          }
          if (latestDueDate == null || dueDate.isAfter(latestDueDate)) {
            latestDueDate = dueDate;
          }
        }

        if (sampleTasks.length < 10) {
          sampleTasks.add({
            "phaseOrder": phase.order,
            "phaseName": safePhaseName,
            "title": task.title,
            "roleRequired": task.roleRequired,
            "requiredHeadcount": task.requiredHeadcount,
            "assignedStaffCount": assignedCount,
            "startDate": startDate?.toIso8601String() ?? "",
            "dueDate": dueDate?.toIso8601String() ?? "",
          });
        }
      }
    }

    final warningCodes = payload.warnings
        .map((warning) => warning.code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toList();
    final warningMessages = payload.warnings
        .map((warning) => warning.message.trim())
        .where((message) => message.isNotEmpty)
        .take(8)
        .toList();
    final qualityIssues = <String>[];
    if (totalTaskCount == 0) {
      qualityIssues.add("No tasks generated.");
    }
    if (phasesWithNoTasksCount > 0) {
      qualityIssues.add("$phasesWithNoTasksCount phase(s) have no tasks.");
    }
    if (tasksMissingRoleCount > 0) {
      qualityIssues.add("$tasksMissingRoleCount task(s) missing roleRequired.");
    }
    if (tasksMissingDatesCount > 0) {
      qualityIssues.add(
        "$tasksMissingDatesCount task(s) missing start/due dates.",
      );
    }
    if (tasksWithInvertedDatesCount > 0) {
      qualityIssues.add(
        "$tasksWithInvertedDatesCount task(s) have dueDate earlier than startDate.",
      );
    }
    if (tasksWithNoAssigneeCount > 0) {
      qualityIssues.add("$tasksWithNoAssigneeCount task(s) have no assignees.");
    }
    if (tasksWithInvalidHeadcountCount > 0) {
      qualityIssues.add(
        "$tasksWithInvalidHeadcountCount task(s) have invalid required headcount.",
      );
    }
    if (tasksWithWeakInstructionsCount > 0) {
      qualityIssues.add(
        "$tasksWithWeakInstructionsCount task(s) have weak instructions.",
      );
    }

    var qualityScore = 100;
    qualityScore -= warningCodes.length * 6;
    qualityScore -= phasesWithNoTasksCount * 10;
    qualityScore -= tasksMissingRoleCount * 8;
    qualityScore -= tasksMissingDatesCount * 8;
    qualityScore -= tasksWithInvertedDatesCount * 12;
    qualityScore -= tasksWithNoAssigneeCount * 3;
    qualityScore -= tasksWithInvalidHeadcountCount * 6;
    qualityScore -= tasksWithWeakInstructionsCount * 2;
    if (totalTaskCount == 0) {
      qualityScore = 0;
    }
    qualityScore = qualityScore.clamp(0, 100).toInt();
    final qualityBand = qualityScore >= 75
        ? "good"
        : qualityScore >= 50
        ? "needs_review"
        : "poor";

    final snapshot = <String, Object?>{
      "sourceAction": sourceAction,
      "qualityBand": qualityBand,
      "qualityScore": qualityScore,
      "startDate": payload.startDate,
      "endDate": payload.endDate,
      "days": payload.days,
      "weeks": payload.weeks,
      "phaseCount": payload.phases.length,
      "taskCount": totalTaskCount,
      "warningCount": payload.warnings.length,
      "taskCountByPhase": taskCountByPhase,
      "roleCountByKey": roleCountByKey,
      "warningCodes": warningCodes,
      "warningMessagesPreview": warningMessages,
      "qualityIssues": qualityIssues,
      "earliestTaskStart": earliestStartDate?.toIso8601String() ?? "",
      "latestTaskDue": latestDueDate?.toIso8601String() ?? "",
      "sampleTasks": sampleTasks,
      "nextAction": qualityBand == "poor"
          ? "Share this snapshot with engineering and regenerate after refining context."
          : qualityBand == "needs_review"
          ? "Review warnings and phase/task balance before committing."
          : "Preview and confirm schedule details.",
    };

    AppDebug.log(_logTag, _draftQualitySnapshotLog, extra: snapshot);

    if (qualityBand == "poor") {
      AppDebug.log(
        _logTag,
        _draftQualityIssueLog,
        extra: {
          "qualityBand": qualityBand,
          "qualityScore": qualityScore,
          "topIssues": qualityIssues.take(5).toList(),
          "warningCodes": warningCodes,
          "nextAction":
              "Use this console payload to compare assistant output before/after sanitization.",
        },
      );
    }
    return {
      "qualityBand": qualityBand,
      "qualityScore": qualityScore,
      "qualityIssueCount": qualityIssues.length,
    };
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
        final averageLifecycleDays =
            _resolveSelectedProductLifecycleAverageDays();
        if (averageLifecycleDays != null && averageLifecycleDays > 0) {
          _endDate = picked.add(Duration(days: averageLifecycleDays - 1));
        }
      } else {
        _endDate = picked;
      }
      // WHY: Manual date picking should switch away from AI-inferred date mode.
      _useAiInferredDates = false;
      _lastAutoGenerateKey = "";
    });
    final draftNotifier = ref.read(productionPlanDraftProvider.notifier);
    draftNotifier.updateStartDate(_startDate);
    draftNotifier.updateEndDate(_endDate);
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

  int? _resolveInclusiveActivityDays({
    required DateTime? startDate,
    required DateTime? endDate,
  }) {
    if (startDate == null || endDate == null) {
      return null;
    }
    final safeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final safeEnd = DateTime(endDate.year, endDate.month, endDate.day);
    if (safeEnd.isBefore(safeStart)) {
      return null;
    }
    return safeEnd.difference(safeStart).inDays + 1;
  }

  List<String> _buildInclusiveActivityBreakdown({
    required DateTime? startDate,
    required DateTime? endDate,
  }) {
    if (startDate == null || endDate == null) {
      return const <String>[];
    }
    final safeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final safeEnd = DateTime(endDate.year, endDate.month, endDate.day);
    if (safeEnd.isBefore(safeStart)) {
      return const <String>[];
    }
    final lines = <String>[];
    var cursor = safeStart;
    while (!cursor.isAfter(safeEnd)) {
      final monthEnd = DateTime(cursor.year, cursor.month + 1, 0);
      final segmentEnd = monthEnd.isBefore(safeEnd) ? monthEnd : safeEnd;
      final days = segmentEnd.difference(cursor).inDays + 1;
      lines.add(
        "${_formatMonthDayRange(cursor, segmentEnd)} = $days ${days == 1 ? 'day' : 'days'}",
      );
      cursor = segmentEnd.add(const Duration(days: 1));
    }
    return lines;
  }

  String _formatMonthDayRange(DateTime startDate, DateTime endDate) {
    final startMonth = _monthLabels[startDate.month - 1];
    if (startDate.year == endDate.year && startDate.month == endDate.month) {
      return "$startMonth ${startDate.day}\u2013${endDate.day}";
    }
    final endMonth = _monthLabels[endDate.month - 1];
    return "$startMonth ${startDate.day} \u2013 $endMonth ${endDate.day}";
  }

  Widget _buildEstimatedActivityWindowCard({
    required ThemeData theme,
    required DateTime? startDate,
    required DateTime? endDate,
  }) {
    final totalDays = _resolveInclusiveActivityDays(
      startDate: startDate,
      endDate: endDate,
    );
    if (totalDays == null) {
      return const SizedBox.shrink();
    }
    final breakdownLines = _buildInclusiveActivityBreakdown(
      startDate: startDate,
      endDate: endDate,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${formatDateInput(startDate)} - ${formatDateInput(endDate)}",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Quick breakdown",
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...breakdownLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Total (inclusive) = $totalDays ${totalDays == 1 ? 'day' : 'days'}",
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  int? _resolveSelectedProductLifecycleAverageDays() {
    final selected = _selectedPlannerCatalogItem;
    final fromSelected = _resolveLifecycleAverageDays(
      minDays: selected?.minDays ?? 0,
      maxDays: selected?.maxDays ?? 0,
    );
    if (fromSelected != null) {
      return fromSelected;
    }
    return _parseLifecycleAverageDays(_selectedProductLifecycleLabel);
  }

  int? _resolveLifecycleAverageDays({
    required int minDays,
    required int maxDays,
  }) {
    final normalizedMin = minDays > 0 ? minDays : 0;
    final normalizedMax = maxDays > 0 ? maxDays : 0;
    if (normalizedMin > 0 && normalizedMax > 0) {
      return ((normalizedMin + normalizedMax) / 2).round();
    }
    if (normalizedMax > 0) {
      return normalizedMax;
    }
    if (normalizedMin > 0) {
      return normalizedMin;
    }
    return null;
  }

  int? _parseLifecycleAverageDays(String rawLabel) {
    final label = rawLabel.trim();
    if (label.isEmpty) {
      return null;
    }
    final rangeMatch = RegExp(r"(\d+)\s*-\s*(\d+)").firstMatch(label);
    if (rangeMatch != null) {
      final minDays = int.tryParse(rangeMatch.group(1) ?? "") ?? 0;
      final maxDays = int.tryParse(rangeMatch.group(2) ?? "") ?? 0;
      return _resolveLifecycleAverageDays(minDays: minDays, maxDays: maxDays);
    }
    final singleMatch = RegExp(r"(\d+)").firstMatch(label);
    if (singleMatch == null) {
      return null;
    }
    return int.tryParse(singleMatch.group(1) ?? "");
  }

  Future<void> _openManualEditor() async {
    final notifier = ref.read(productionPlanDraftProvider.notifier);
    notifier.reset();
    notifier.updateDomainContext(_domainContext);
    notifier.updateEstate(_selectedEstateAssetId);
    notifier.updateProduct(_selectedProductId);
    notifier.updateStartDate(_startDate);
    notifier.updateEndDate(_endDate);
    notifier.updateTitle(
      "${_resolveSelectedProductName().trim().isEmpty ? 'Production' : _resolveSelectedProductName().trim()} Plan",
    );
    notifier.updateNotes("");
    AppDebug.log(_logTag, _openEditorLog, extra: {"mode": "manual"});
    _syncDraftEditors(ref.read(productionPlanDraftProvider));
    if (!mounted) {
      return;
    }
    setState(() {
      _showDraftStudio = true;
      _draftStudioPanel = _DraftStudioPanel.settings;
    });
  }

  Future<void> _createSuggestedProduct(
    ProductionAssistantDraftProductPayload payload,
  ) async {
    AppDebug.log(_logTag, _createSuggestedProductTapLog);
    final initialDraft = ProductDraft(
      name: payload.createProductPayload.name,
      description: payload.createProductPayload.notes,
      category: payload.createProductPayload.category,
      subcategory: "",
      brand: "",
      sellingOptions: const [
        ProductSellingOption(
          packageType: "Piece",
          quantity: 1,
          measurementUnit: "piece",
          isDefault: true,
        ),
      ],
      sellingUnits: const ["Piece"],
      defaultSellingUnit: "Piece",
      priceNgn: 0,
      stock: 0,
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
    setState(() {
      _applySelectedProductState(
        productId: created.id,
        productName: created.name,
        productLifecycleLabel:
            "${payload.draftProduct.lifecycleDaysEstimate} days",
        productSourceLabel: _resolveProductSourceLabel("business_product"),
      );
    });
    AppDebug.log(
      _logTag,
      _createSuggestedProductSuccessLog,
      extra: {"productId": created.id},
    );
    _showSnack("Suggested product created and selected.");
  }

  Future<void> _applyDraftAndOpenEditor(
    ProductionAssistantPlanDraftPayload payload,
  ) async {
    await _applyDraftToStudio(payload);
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

  int _resolveSafeTotalWorkUnitsForPreview() {
    final configuredTotal = _totalWorkUnits ?? 0;
    return configuredTotal < 1 ? 1 : configuredTotal;
  }

  int _resolveTaskHeadcountForProjection(_AssistantScheduleTask task) {
    final assignedCount = task.assignedStaffProfileIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
    if (assignedCount > 0) {
      return assignedCount;
    }
    final requiredCount = task.requiredHeadcount < 1
        ? 1
        : task.requiredHeadcount;
    return requiredCount;
  }

  bool _isPlotExecutionRoleForPreview(String rawRole) {
    final normalizedRole = _normalizeRoleKey(rawRole);
    return normalizedRole == _normalizeRoleKey(staffRoleFarmer) ||
        normalizedRole == _normalizeRoleKey(staffRoleFieldAgent);
  }

  double _resolveTaskDurationHoursForProjection(_AssistantScheduleTask task) {
    final durationMinutes = task.dueDate.difference(task.startDate).inMinutes;
    if (durationMinutes <= 0) {
      return 4;
    }
    return durationMinutes / 60;
  }

  double _resolveEffectiveTaskDurationHoursForProjection(
    _AssistantScheduleTask task,
  ) {
    final rawDurationHours = _resolveTaskDurationHoursForProjection(task);
    final minimumDurationHours =
        _projectionHoursPerDay * _projectionMinimumDurationRatio;
    final boundedDurationHours = rawDurationHours < minimumDurationHours
        ? minimumDurationHours
        : rawDurationHours;
    // WHY: Multi-day windows are expanded per calendar day; cap each day to a humane working-day ceiling.
    return boundedDurationHours > _projectionHoursPerDay
        ? _projectionHoursPerDay.toDouble()
        : boundedDurationHours;
  }

  double _resolveTaskPlotsPerFarmerHourForProjection(
    _AssistantScheduleTask task,
  ) {
    final recommendedRatePerHour =
        _projectionRecommendedPlotsPerStaffPerDay / _projectionHoursPerDay;
    final phaseTargetRate = task.phaseTargetRatePerFarmerHour;
    if (phaseTargetRate > 0) {
      return phaseTargetRate;
    }
    final phaseMinRate = task.phaseMinRatePerFarmerHour;
    if (phaseMinRate > 0) {
      return phaseMinRate;
    }
    return recommendedRatePerHour;
  }

  // WHY: Multi-day tasks must appear on each covered day so weekly preview does not collapse into false "empty" gaps.
  List<_AssistantTaskDailyWindow> _expandTaskAcrossDailyWindows({
    required DateTime taskStart,
    required DateTime taskDue,
  }) {
    final safeStart = taskStart;
    final safeDue = taskDue.isBefore(taskStart)
        ? taskStart.add(const Duration(minutes: 30))
        : taskDue;
    final windows = <_AssistantTaskDailyWindow>[];
    var dayCursor = DateTime(safeStart.year, safeStart.month, safeStart.day);
    final finalDay = DateTime(safeDue.year, safeDue.month, safeDue.day);

    while (!dayCursor.isAfter(finalDay)) {
      final dayStart = DateTime(dayCursor.year, dayCursor.month, dayCursor.day);
      final dayEnd = DateTime(
        dayCursor.year,
        dayCursor.month,
        dayCursor.day,
        23,
        59,
      );

      final windowStart = safeStart.isAfter(dayStart) ? safeStart : dayStart;
      final windowEnd = safeDue.isBefore(dayEnd) ? safeDue : dayEnd;
      if (windowEnd.isAfter(windowStart)) {
        windows.add(
          _AssistantTaskDailyWindow(startDate: windowStart, dueDate: windowEnd),
        );
      }

      dayCursor = dayCursor.add(const Duration(days: 1));
    }

    if (windows.isEmpty) {
      windows.add(
        _AssistantTaskDailyWindow(
          startDate: safeStart,
          dueDate: safeStart.add(const Duration(minutes: 30)),
        ),
      );
    }
    return windows;
  }

  int _estimateProjectedWorkUnitsForTask({
    required _AssistantScheduleTask task,
    required int remainingWorkUnits,
    required int safeTotalWorkUnits,
    required int safeMinStaffPerWorkUnit,
  }) {
    if (remainingWorkUnits < 1) {
      return 0;
    }
    if (!_isPlotExecutionRoleForPreview(task.roleRequired)) {
      return 0;
    }
    final safeHeadcount = _resolveTaskHeadcountForProjection(task);
    final staffPerUnit = safeMinStaffPerWorkUnit < 1
        ? 1
        : safeMinStaffPerWorkUnit;
    if (safeHeadcount < staffPerUnit) {
      return 0;
    }
    final durationHours = _resolveEffectiveTaskDurationHoursForProjection(task);
    final plotsPerFarmerHour = _resolveTaskPlotsPerFarmerHourForProjection(
      task,
    );
    // WHY: Finite execution preview must reflect actual group throughput, not collapse to a single unit because of staffing-group hints.
    var throughputCapacity =
        (safeHeadcount * plotsPerFarmerHour * durationHours).ceil();
    if (throughputCapacity < 1) {
      throughputCapacity = 1;
    }
    var projectedWorkUnits = throughputCapacity;
    if (projectedWorkUnits > safeTotalWorkUnits) {
      projectedWorkUnits = safeTotalWorkUnits;
    }
    if (projectedWorkUnits > remainingWorkUnits) {
      projectedWorkUnits = remainingWorkUnits;
    }
    return projectedWorkUnits < 1 ? 0 : projectedWorkUnits;
  }

  String _buildProjectionWorkstreamKey({required _AssistantScheduleTask task}) {
    final normalizedTitle = _normalizeLifecycleTaskTitle(
      task.title,
    ).trim().toLowerCase();
    final normalizedRole = _normalizeRoleKey(task.roleRequired);
    if (normalizedTitle.isEmpty || normalizedRole.isEmpty) {
      return "";
    }
    return "$normalizedTitle|$normalizedRole";
  }

  int _resolveProjectionCadenceDaysForTrack({
    required String normalizedTitle,
    required List<DateTime> occurrenceDates,
  }) {
    if (_projectionTitleContainsAnyKeyword(
      normalizedTitle: normalizedTitle,
      keywords: _projectionRepeatableDailyKeywords,
    )) {
      return 1;
    }
    if (_projectionTitleContainsAnyKeyword(
      normalizedTitle: normalizedTitle,
      keywords: _projectionRepeatableWeeklyKeywords,
    )) {
      return 7;
    }
    if (_projectionTitleContainsAnyKeyword(
      normalizedTitle: normalizedTitle,
      keywords: _projectionRepeatableMonthlyKeywords,
    )) {
      return 30;
    }
    // WHY: Date-gap inference can incorrectly mark finite multi-day tasks as repeatable cycles.
    // Repeatability is enabled only when task intent is explicit via cadence keywords.
    if (occurrenceDates.length >= 2) {
      AppDebug.log(
        _logTag,
        "draft_projection_cadence_gap_inference_skipped",
        extra: {
          "normalizedTitle": normalizedTitle,
          "occurrenceCount": occurrenceDates.length,
          "nextAction":
              "Use explicit daily/weekly/monthly task wording for repeatable monitoring tracks.",
        },
      );
    }
    return 0;
  }

  // WHY: Preparation/execution tracks are finite lifecycle work and must not reset by monitoring cadence.
  bool _isRepeatableCadenceAllowedForLifecycleRank({
    required int lifecycleRank,
  }) {
    return lifecycleRank >= 2;
  }

  int _resolveProjectionCycleIndex({
    required DateTime planStartDate,
    required DateTime taskDate,
    required int cadenceDays,
  }) {
    if (cadenceDays < 1) {
      return 0;
    }
    final safePlanStart = DateTime(
      planStartDate.year,
      planStartDate.month,
      planStartDate.day,
    );
    final safeTaskDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
    final diffDays = safeTaskDate.difference(safePlanStart).inDays;
    if (diffDays <= 0) {
      return 0;
    }
    return diffDays ~/ cadenceDays;
  }

  String _buildProjectionCycleKey({
    required String trackKey,
    required DateTime planStartDate,
    required DateTime taskDate,
    required int cadenceDays,
  }) {
    if (cadenceDays < 1) {
      return trackKey;
    }
    final cycleIndex = _resolveProjectionCycleIndex(
      planStartDate: planStartDate,
      taskDate: taskDate,
      cadenceDays: cadenceDays,
    );
    return "$trackKey|cycle:$cycleIndex";
  }

  String _projectionCadenceLabel(int cadenceDays) {
    if (cadenceDays == 1) {
      return "daily reset";
    }
    if (cadenceDays == 7) {
      return "weekly reset";
    }
    if (cadenceDays == 30) {
      return "monthly reset";
    }
    if (cadenceDays > 1) {
      return "reset every $cadenceDays days";
    }
    return "";
  }

  bool _projectionTitleContainsAnyKeyword({
    required String normalizedTitle,
    required List<String> keywords,
  }) {
    for (final keyword in keywords) {
      final safeKeyword = keyword.trim().toLowerCase();
      if (safeKeyword.isEmpty) {
        continue;
      }
      if (normalizedTitle.contains(safeKeyword)) {
        return true;
      }
    }
    return false;
  }

  // WHY: Phase type is authoritative lifecycle metadata for finite vs monitoring projection behavior.
  String _normalizeAssistantPhaseType(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    if (normalized == _assistantPhaseTypeMonitoring) {
      return _assistantPhaseTypeMonitoring;
    }
    return _assistantPhaseTypeFinite;
  }

  int _resolveProjectionLifecycleRankForTask({
    required _AssistantScheduleTask task,
  }) {
    final normalizedTitle = _normalizeLifecycleTaskTitle(
      task.title,
    ).trim().toLowerCase();
    if (_projectionTitleContainsAnyKeyword(
      normalizedTitle: normalizedTitle,
      keywords: _projectionStageClosureKeywords,
    )) {
      return 3;
    }
    if (_projectionTitleContainsAnyKeyword(
      normalizedTitle: normalizedTitle,
      keywords: _projectionStagePreparationKeywords,
    )) {
      return 0;
    }
    if (_projectionTitleContainsAnyKeyword(
      normalizedTitle: normalizedTitle,
      keywords: _projectionStageExecutionKeywords,
    )) {
      return 1;
    }
    if (_projectionTitleContainsAnyKeyword(
      normalizedTitle: normalizedTitle,
      keywords: _projectionStageOperationsKeywords,
    )) {
      return 2;
    }
    final safePhaseOrder = task.phaseOrder < 1 ? 1 : task.phaseOrder;
    return safePhaseOrder - 1;
  }

  int? _resolveProjectionImmediatePrerequisiteRank({
    required int currentRank,
    required Iterable<int> allRanks,
  }) {
    int? previousRank;
    for (final rank in allRanks) {
      if (rank >= currentRank) {
        continue;
      }
      if (previousRank == null || rank > previousRank) {
        previousRank = rank;
      }
    }
    return previousRank;
  }

  int _resolveProjectionUnlockedWorkUnitsForTrack({
    required String trackKey,
    required int currentRank,
    required Map<String, int> lifecycleRankByTrack,
    required Map<String, int> completedWorkUnitsByTrack,
    required int safeTotalWorkUnits,
  }) {
    final prerequisiteRank = _resolveProjectionImmediatePrerequisiteRank(
      currentRank: currentRank,
      allRanks: lifecycleRankByTrack.values.toSet(),
    );
    if (prerequisiteRank == null) {
      return safeTotalWorkUnits;
    }
    final prerequisiteTrackKeys = lifecycleRankByTrack.entries
        .where((entry) => entry.value == prerequisiteRank)
        .map((entry) => entry.key)
        .toList();
    if (prerequisiteTrackKeys.isEmpty) {
      return safeTotalWorkUnits;
    }
    // WHY: A downstream track can only progress as far as the least-completed prerequisite track.
    var unlockedWorkUnits = safeTotalWorkUnits;
    for (final prerequisiteKey in prerequisiteTrackKeys) {
      final completedUnits = completedWorkUnitsByTrack[prerequisiteKey] ?? 0;
      if (completedUnits < unlockedWorkUnits) {
        unlockedWorkUnits = completedUnits;
      }
    }
    final safeUnlocked = unlockedWorkUnits.clamp(0, safeTotalWorkUnits).toInt();
    final stageStartThresholdUnits = _resolveStageGateStartThresholdUnits(
      safeTotalWorkUnits: safeTotalWorkUnits,
    );
    final strictUnlocked = safeUnlocked < stageStartThresholdUnits
        ? 0
        : safeUnlocked;
    AppDebug.log(
      _logTag,
      "draft_projection_stage_gate_applied",
      extra: {
        "trackKey": trackKey,
        "currentRank": currentRank,
        "prerequisiteRank": prerequisiteRank,
        "prerequisiteTrackCount": prerequisiteTrackKeys.length,
        "unlockedWorkUnits": strictUnlocked,
        "rawUnlockedWorkUnits": safeUnlocked,
        "stageStartThresholdUnits": stageStartThresholdUnits,
      },
    );
    return strictUnlocked;
  }

  int _resolveStageGateStartThresholdUnits({required int safeTotalWorkUnits}) {
    if (safeTotalWorkUnits < 1) {
      return 1;
    }
    final threshold = (safeTotalWorkUnits * _stageGateStartThresholdRatio)
        .ceil()
        .clamp(1, safeTotalWorkUnits)
        .toInt();
    return threshold;
  }

  int _resolveProjectionLifecycleRankForPlanTask({
    required ProductionAssistantPlanTask task,
    required int phaseOrder,
    required String phaseType,
    required double phaseMinRatePerFarmerHour,
    required double phaseTargetRatePerFarmerHour,
  }) {
    final safeStart = task.startDate ?? DateTime.now();
    final safeDue = task.dueDate ?? safeStart.add(const Duration(hours: 1));
    final previewTask = _AssistantScheduleTask(
      title: task.title,
      phaseName: "",
      phaseOrder: phaseOrder,
      phaseType: phaseType,
      roleRequired: task.roleRequired,
      requiredHeadcount: task.requiredHeadcount,
      assignedStaffProfileIds: task.assignedStaffProfileIds,
      startDate: safeStart,
      dueDate: safeDue,
      phaseMinRatePerFarmerHour: phaseMinRatePerFarmerHour,
      phaseTargetRatePerFarmerHour: phaseTargetRatePerFarmerHour,
    );
    return _resolveProjectionLifecycleRankForTask(task: previewTask);
  }

  int _estimateProjectedWorkUnitsForPlanTask({
    required ProductionAssistantPlanTask task,
    required ProductionAssistantPlanPhase phase,
    required int safeMinStaffPerWorkUnit,
    required int safeTotalWorkUnits,
  }) {
    final safeStart = task.startDate ?? DateTime.now();
    final safeDue = task.dueDate ?? safeStart.add(const Duration(hours: 1));
    final previewTask = _AssistantScheduleTask(
      title: task.title,
      phaseName: "",
      phaseOrder: phase.order,
      phaseType: phase.phaseType,
      roleRequired: task.roleRequired,
      requiredHeadcount: task.requiredHeadcount,
      assignedStaffProfileIds: task.assignedStaffProfileIds,
      startDate: safeStart,
      dueDate: safeDue,
      phaseMinRatePerFarmerHour: phase.minRatePerFarmerHour,
      phaseTargetRatePerFarmerHour: phase.targetRatePerFarmerHour,
    );
    return _estimateProjectedWorkUnitsForTask(
      task: previewTask,
      remainingWorkUnits: safeTotalWorkUnits,
      safeTotalWorkUnits: safeTotalWorkUnits,
      safeMinStaffPerWorkUnit: safeMinStaffPerWorkUnit,
    );
  }

  _StageGateResequenceResult _resequencePlanDraftForStageGate({
    required List<ProductionAssistantPlanPhase> phases,
    required int safeTotalWorkUnits,
    required int safeMinStaffPerWorkUnit,
  }) {
    final executionEntries = <_StageGateTaskEntry>[];
    for (int phaseIndex = 0; phaseIndex < phases.length; phaseIndex += 1) {
      final phase = phases[phaseIndex];
      final normalizedPhaseType = _normalizeAssistantPhaseType(phase.phaseType);
      for (int taskIndex = 0; taskIndex < phase.tasks.length; taskIndex += 1) {
        final task = phase.tasks[taskIndex];
        final startDate = task.startDate;
        final dueDate = task.dueDate;
        if (startDate == null || dueDate == null) {
          continue;
        }
        if (!_isPlotExecutionRoleForPreview(task.roleRequired)) {
          continue;
        }
        if (normalizedPhaseType == _assistantPhaseTypeMonitoring) {
          continue;
        }
        executionEntries.add(
          _StageGateTaskEntry(
            phaseIndex: phaseIndex,
            taskIndex: taskIndex,
            phaseOrder: phase.order,
            task: task,
            startDate: startDate,
            dueDate: dueDate,
            lifecycleRank: _resolveProjectionLifecycleRankForPlanTask(
              task: task,
              phaseOrder: phase.order,
              phaseType: phase.phaseType,
              phaseMinRatePerFarmerHour: phase.minRatePerFarmerHour,
              phaseTargetRatePerFarmerHour: phase.targetRatePerFarmerHour,
            ),
            projectedWorkUnits: _estimateProjectedWorkUnitsForPlanTask(
              task: task,
              phase: phase,
              safeMinStaffPerWorkUnit: safeMinStaffPerWorkUnit,
              safeTotalWorkUnits: safeTotalWorkUnits,
            ),
          ),
        );
      }
    }
    if (executionEntries.length < 2) {
      return _StageGateResequenceResult(
        phases: phases,
        resequencedTaskCount: 0,
        blockedTaskCount: 0,
        autofilledBlockedSlotCount: 0,
      );
    }

    final slots = executionEntries.toList()
      ..sort((left, right) {
        final startCompare = left.startDate.compareTo(right.startDate);
        if (startCompare != 0) {
          return startCompare;
        }
        return left.dueDate.compareTo(right.dueDate);
      });
    final rankSortedEntries = executionEntries.toList()
      ..sort((left, right) {
        final rankCompare = left.lifecycleRank.compareTo(right.lifecycleRank);
        if (rankCompare != 0) {
          return rankCompare;
        }
        final startCompare = left.startDate.compareTo(right.startDate);
        if (startCompare != 0) {
          return startCompare;
        }
        return left.dueDate.compareTo(right.dueDate);
      });
    final availableRanks =
        rankSortedEntries.map((entry) => entry.lifecycleRank).toSet().toList()
          ..sort();
    final templateEntriesByRank = <int, List<_StageGateTaskEntry>>{};
    for (final entry in rankSortedEntries) {
      templateEntriesByRank.putIfAbsent(
        entry.lifecycleRank,
        () => <_StageGateTaskEntry>[],
      );
      templateEntriesByRank[entry.lifecycleRank]!.add(entry);
    }
    final templateCursorByRank = <int, int>{};
    _StageGateTaskEntry? nextTemplateForRank(int rank) {
      final templates = templateEntriesByRank[rank];
      if (templates == null || templates.isEmpty) {
        return null;
      }
      final currentCursor = templateCursorByRank[rank] ?? 0;
      final safeIndex = currentCursor % templates.length;
      final selected = templates[safeIndex];
      templateCursorByRank[rank] = safeIndex + 1;
      return selected;
    }

    final stageStartThresholdUnits = _resolveStageGateStartThresholdUnits(
      safeTotalWorkUnits: safeTotalWorkUnits,
    );
    final completedByRank = <int, int>{};
    final replacementTaskByPosition = <String, ProductionAssistantPlanTask>{};
    var resequencedTaskCount = 0;
    var blockedTaskCount = 0;
    var autofilledBlockedSlotCount = 0;

    final slotCount = slots.length < rankSortedEntries.length
        ? slots.length
        : rankSortedEntries.length;
    for (int index = 0; index < slotCount; index += 1) {
      final slot = slots[index];
      final chosenEntry = rankSortedEntries[index];
      var activeEntry = chosenEntry;
      var activeRank = chosenEntry.lifecycleRank;
      int? activePrerequisiteRank = _resolveProjectionImmediatePrerequisiteRank(
        currentRank: activeRank,
        allRanks: availableRanks,
      );
      var prerequisiteCompleted = activePrerequisiteRank == null
          ? safeTotalWorkUnits
          : (completedByRank[activePrerequisiteRank] ?? 0);
      var currentCompletedBefore = completedByRank[activeRank] ?? 0;
      var isBlockedByStageGate =
          activePrerequisiteRank != null &&
          (prerequisiteCompleted < stageStartThresholdUnits ||
              currentCompletedBefore >= prerequisiteCompleted);
      var usedAutofillFallback = false;
      if (isBlockedByStageGate) {
        final fallbackTemplate = nextTemplateForRank(activePrerequisiteRank);
        if (fallbackTemplate != null) {
          usedAutofillFallback = true;
          activeEntry = fallbackTemplate;
          activeRank = fallbackTemplate.lifecycleRank;
          activePrerequisiteRank = _resolveProjectionImmediatePrerequisiteRank(
            currentRank: activeRank,
            allRanks: availableRanks,
          );
          prerequisiteCompleted = activePrerequisiteRank == null
              ? safeTotalWorkUnits
              : (completedByRank[activePrerequisiteRank] ?? 0);
          currentCompletedBefore = completedByRank[activeRank] ?? 0;
          isBlockedByStageGate =
              activePrerequisiteRank != null &&
              (prerequisiteCompleted < stageStartThresholdUnits ||
                  currentCompletedBefore >= prerequisiteCompleted);
        }
      }
      if (isBlockedByStageGate) {
        blockedTaskCount += 1;
      }
      if (usedAutofillFallback) {
        autofilledBlockedSlotCount += 1;
      }
      var projectedUnits = activeEntry.projectedWorkUnits;
      if (activePrerequisiteRank != null) {
        final unlockedUnits = prerequisiteCompleted - currentCompletedBefore;
        if (unlockedUnits < projectedUnits) {
          projectedUnits = unlockedUnits < 0 ? 0 : unlockedUnits;
        }
      }
      final currentCompletedAfter = (currentCompletedBefore + projectedUnits)
          .clamp(0, safeTotalWorkUnits)
          .toInt();
      completedByRank[activeRank] = currentCompletedAfter;

      final reassignedTask = ProductionAssistantPlanTask(
        title: activeEntry.task.title,
        roleRequired: activeEntry.task.roleRequired,
        requiredHeadcount: activeEntry.task.requiredHeadcount,
        weight: activeEntry.task.weight,
        instructions: activeEntry.task.instructions,
        taskType: activeEntry.task.taskType,
        sourceTemplateKey: activeEntry.task.sourceTemplateKey,
        recurrenceGroupKey: activeEntry.task.recurrenceGroupKey,
        occurrenceIndex: activeEntry.task.occurrenceIndex,
        startDate: slot.startDate,
        dueDate: slot.dueDate,
        assignedStaffProfileIds: activeEntry.task.assignedStaffProfileIds,
      );
      final moved =
          activeEntry.startDate.millisecondsSinceEpoch !=
              slot.startDate.millisecondsSinceEpoch ||
          activeEntry.dueDate.millisecondsSinceEpoch !=
              slot.dueDate.millisecondsSinceEpoch;
      if (moved) {
        resequencedTaskCount += 1;
      }
      final positionKey = "${slot.phaseIndex}:${slot.taskIndex}";
      replacementTaskByPosition[positionKey] = reassignedTask;
    }

    if (replacementTaskByPosition.isEmpty) {
      return _StageGateResequenceResult(
        phases: phases,
        resequencedTaskCount: 0,
        blockedTaskCount: blockedTaskCount,
        autofilledBlockedSlotCount: autofilledBlockedSlotCount,
      );
    }

    final resequencedPhases = phases.asMap().entries.map((phaseEntry) {
      final phaseIndex = phaseEntry.key;
      final phase = phaseEntry.value;
      final resequencedTasks = phase.tasks.asMap().entries.map((taskEntry) {
        final positionKey = "$phaseIndex:${taskEntry.key}";
        return replacementTaskByPosition[positionKey] ?? taskEntry.value;
      }).toList();
      return ProductionAssistantPlanPhase(
        name: phase.name,
        order: phase.order,
        estimatedDays: phase.estimatedDays,
        phaseType: phase.phaseType,
        requiredUnits: phase.requiredUnits,
        minRatePerFarmerHour: phase.minRatePerFarmerHour,
        targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
        plannedHoursPerDay: phase.plannedHoursPerDay,
        biologicalMinDays: phase.biologicalMinDays,
        tasks: resequencedTasks,
      );
    }).toList();

    AppDebug.log(
      _logTag,
      "draft_stage_gate_resequenced",
      extra: {
        "executionTaskCount": executionEntries.length,
        "resequencedTaskCount": resequencedTaskCount,
        "blockedTaskCount": blockedTaskCount,
        "autofilledBlockedSlotCount": autofilledBlockedSlotCount,
        "stageStartThresholdUnits": stageStartThresholdUnits,
        "safeTotalWorkUnits": safeTotalWorkUnits,
        "nextAction": blockedTaskCount > 0
            ? "Increase prerequisite capacity or extend timeline for remaining blocked downstream slots."
            : "Preview stage-gated draft order.",
      },
    );
    return _StageGateResequenceResult(
      phases: resequencedPhases,
      resequencedTaskCount: resequencedTaskCount,
      blockedTaskCount: blockedTaskCount,
      autofilledBlockedSlotCount: autofilledBlockedSlotCount,
    );
  }

  _AssistantProjectionSummary _resolveProjectedSummaryFromRows({
    required List<_AssistantWeeklySchedule> weeklyRows,
    required int safeTotalWorkUnits,
  }) {
    // WHY: Coverage should prioritize finite execution tracks before repeatable monitoring cycles.
    final remainingByTrack = <String, int>{};
    final nonRepeatableTrackKeys = <String>{};
    for (final week in weeklyRows) {
      for (final day in week.days) {
        for (final task in day.tasks) {
          final trackKey = task.projectionWorkstreamKey.trim();
          if (trackKey.isEmpty) {
            continue;
          }
          final safeRemaining = task.projectedWorkUnitsRemaining < 0
              ? 0
              : task.projectedWorkUnitsRemaining;
          remainingByTrack[trackKey] = safeRemaining;
          if (!task.projectionIsRepeatable) {
            nonRepeatableTrackKeys.add(trackKey);
          }
        }
      }
    }
    if (remainingByTrack.isEmpty) {
      return _AssistantProjectionSummary(
        expectedWorkUnitsPerTrack: safeTotalWorkUnits,
        executionTaskTrackCount: 0,
        fullyCoveredTrackCount: 0,
        minimumCoveredAcrossTracks: 0,
        maximumRemainingAcrossTracks: safeTotalWorkUnits,
      );
    }

    final selectedTrackKeys = nonRepeatableTrackKeys.isNotEmpty
        ? nonRepeatableTrackKeys
        : remainingByTrack.keys.toSet();
    final selectedRemainingValues = selectedTrackKeys
        .map((trackKey) => remainingByTrack[trackKey] ?? safeTotalWorkUnits)
        .toList();
    var maximumRemainingAcrossTracks = 0;
    var fullyCoveredTrackCount = 0;
    for (final remaining in selectedRemainingValues) {
      if (remaining > maximumRemainingAcrossTracks) {
        maximumRemainingAcrossTracks = remaining;
      }
      if (remaining == 0) {
        fullyCoveredTrackCount += 1;
      }
    }
    final minimumCoveredAcrossTracks =
        (safeTotalWorkUnits - maximumRemainingAcrossTracks)
            .clamp(0, safeTotalWorkUnits)
            .toInt();
    return _AssistantProjectionSummary(
      expectedWorkUnitsPerTrack: safeTotalWorkUnits,
      executionTaskTrackCount: selectedTrackKeys.length,
      fullyCoveredTrackCount: fullyCoveredTrackCount,
      minimumCoveredAcrossTracks: minimumCoveredAcrossTracks,
      maximumRemainingAcrossTracks: maximumRemainingAcrossTracks,
    );
  }

  String _formatWorkUnitsCountForPreview({
    required int value,
    required String workUnitLabel,
  }) {
    final safeValue = value < 0 ? 0 : value;
    final safeLabel = workUnitLabel.trim().isEmpty
        ? "work unit"
        : workUnitLabel.trim();
    return "$safeValue $safeLabel";
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
    final safeTotalWorkUnits = _resolveSafeTotalWorkUnitsForPreview();
    final safeMinStaffPerWorkUnit = _resolveSafeMinStaffPerWorkUnit();
    final tasksByDay = <String, List<_AssistantScheduleTask>>{};

    var expandedTaskWindowCount = 0;
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
        final normalizedTitle = _normalizeLifecycleTaskTitle(task.title);
        if (normalizedTitle != task.title) {
          AppDebug.log(
            _logTag,
            "draft_task_title_week_removed",
            extra: {"rawTitle": task.title, "normalizedTitle": normalizedTitle},
          );
        }
        final taskWindows = _expandTaskAcrossDailyWindows(
          taskStart: taskStart,
          taskDue: taskDue,
        );
        expandedTaskWindowCount += taskWindows.length;
        for (final taskWindow in taskWindows) {
          final day = DateTime(
            taskWindow.startDate.year,
            taskWindow.startDate.month,
            taskWindow.startDate.day,
          );
          final dayKey = formatDateInput(day);
          final list = tasksByDay.putIfAbsent(
            dayKey,
            () => <_AssistantScheduleTask>[],
          );
          list.add(
            _AssistantScheduleTask(
              title: normalizedTitle,
              phaseName: phase.name,
              phaseOrder: phase.order,
              phaseType: phase.phaseType,
              roleRequired: task.roleRequired,
              requiredHeadcount: task.requiredHeadcount,
              assignedStaffProfileIds: task.assignedStaffProfileIds,
              startDate: taskWindow.startDate,
              dueDate: taskWindow.dueDate,
              phaseMinRatePerFarmerHour: phase.minRatePerFarmerHour,
              phaseTargetRatePerFarmerHour: phase.targetRatePerFarmerHour,
            ),
          );
        }
      }
    }

    for (final entry in tasksByDay.entries) {
      entry.value.sort((left, right) {
        final leftMs = left.startDate.millisecondsSinceEpoch;
        final rightMs = right.startDate.millisecondsSinceEpoch;
        return leftMs.compareTo(rightMs);
      });
    }

    // WHY: Remaining plots are tracked by task track and reset by cadence for repeatable maintenance tasks.
    final completedWorkUnitsByTrackGlobal = <String, int>{};
    final completedWorkUnitsByTrackCycle = <String, int>{};
    final lifecycleRankByTrack = <String, int>{};
    final cadenceDaysByTrack = <String, int>{};
    final sortedDayKeys = tasksByDay.keys.toList()..sort();
    final occurrenceDatesByTrack = <String, List<DateTime>>{};
    for (final dayKey in sortedDayKeys) {
      final dayTasks = tasksByDay[dayKey] ?? const <_AssistantScheduleTask>[];
      for (final task in dayTasks) {
        if (!_isPlotExecutionRoleForPreview(task.roleRequired)) {
          continue;
        }
        final trackKey = _buildProjectionWorkstreamKey(task: task);
        if (trackKey.isEmpty) {
          continue;
        }
        occurrenceDatesByTrack.putIfAbsent(trackKey, () => <DateTime>[]);
        occurrenceDatesByTrack[trackKey]!.add(task.startDate);
        if (!lifecycleRankByTrack.containsKey(trackKey)) {
          lifecycleRankByTrack[trackKey] =
              _resolveProjectionLifecycleRankForTask(task: task);
        }
      }
    }
    for (final entry in occurrenceDatesByTrack.entries) {
      final trackKey = entry.key;
      final normalizedTitle = trackKey.split("|").isEmpty
          ? ""
          : trackKey.split("|").first;
      cadenceDaysByTrack[trackKey] = _resolveProjectionCadenceDaysForTrack(
        normalizedTitle: normalizedTitle,
        occurrenceDates: entry.value,
      );
    }
    for (final dayKey in sortedDayKeys) {
      final dayTasks = tasksByDay[dayKey] ?? const <_AssistantScheduleTask>[];
      final projectedDayTasks = <_AssistantScheduleTask>[];
      for (final task in dayTasks) {
        final trackKey = _isPlotExecutionRoleForPreview(task.roleRequired)
            ? _buildProjectionWorkstreamKey(task: task)
            : "";
        final currentRank = trackKey.isEmpty
            ? 0
            : (lifecycleRankByTrack[trackKey] ??
                  _resolveProjectionLifecycleRankForTask(task: task));
        final normalizedPhaseType = _normalizeAssistantPhaseType(
          task.phaseType,
        );
        final isMonitoringPhase =
            normalizedPhaseType == _assistantPhaseTypeMonitoring;
        final inferredCadenceDays = trackKey.isEmpty
            ? 0
            : (cadenceDaysByTrack[trackKey] ?? 0);
        final cadenceDays =
            isMonitoringPhase &&
                _isRepeatableCadenceAllowedForLifecycleRank(
                  lifecycleRank: currentRank,
                )
            ? inferredCadenceDays
            : 0;
        final isRepeatableTrack = cadenceDays > 0;
        final cycleKey = trackKey.isEmpty
            ? ""
            : _buildProjectionCycleKey(
                trackKey: trackKey,
                planStartDate: startDate,
                taskDate: task.startDate,
                cadenceDays: cadenceDays,
              );
        final cycleCompletedSoFar = cycleKey.isEmpty
            ? 0
            : (completedWorkUnitsByTrackCycle[cycleKey] ?? 0);
        final trackRemaining = cycleKey.isEmpty
            ? 0
            : (safeTotalWorkUnits - cycleCompletedSoFar)
                  .clamp(0, safeTotalWorkUnits)
                  .toInt();
        final unlockedForTrack = trackKey.isEmpty
            ? 0
            : _resolveProjectionUnlockedWorkUnitsForTrack(
                trackKey: trackKey,
                currentRank: currentRank,
                lifecycleRankByTrack: lifecycleRankByTrack,
                completedWorkUnitsByTrack: completedWorkUnitsByTrackGlobal,
                safeTotalWorkUnits: safeTotalWorkUnits,
              );
        final unlockedRemainingForTrack = trackKey.isEmpty
            ? 0
            : (unlockedForTrack - cycleCompletedSoFar)
                  .clamp(0, safeTotalWorkUnits)
                  .toInt();
        final allowedRemainingForTrack = isRepeatableTrack
            ? trackRemaining
            : (trackRemaining < unlockedRemainingForTrack
                  ? trackRemaining
                  : unlockedRemainingForTrack);
        final projectedWorkUnits = _estimateProjectedWorkUnitsForTask(
          task: task,
          remainingWorkUnits: allowedRemainingForTrack,
          safeTotalWorkUnits: safeTotalWorkUnits,
          safeMinStaffPerWorkUnit: safeMinStaffPerWorkUnit,
        );
        final completedAfterTaskCycle = cycleKey.isEmpty
            ? 0
            : (cycleCompletedSoFar + projectedWorkUnits)
                  .clamp(0, safeTotalWorkUnits)
                  .toInt();
        final projectedRemaining = cycleKey.isEmpty
            ? 0
            : (safeTotalWorkUnits - completedAfterTaskCycle)
                  .clamp(0, safeTotalWorkUnits)
                  .toInt();
        if (cycleKey.isNotEmpty) {
          completedWorkUnitsByTrackCycle[cycleKey] = completedAfterTaskCycle;
        }
        if (trackKey.isNotEmpty) {
          final globalBefore = completedWorkUnitsByTrackGlobal[trackKey] ?? 0;
          final globalAfter = completedAfterTaskCycle > globalBefore
              ? completedAfterTaskCycle
              : globalBefore;
          completedWorkUnitsByTrackGlobal[trackKey] = globalAfter;
        }
        projectedDayTasks.add(
          task.copyWithProjection(
            projectedWorkUnits: projectedWorkUnits,
            projectedWorkUnitsRemaining: projectedRemaining,
            projectionWorkstreamKey: trackKey,
            projectionIsRepeatable: isRepeatableTrack,
            projectionCadenceDays: cadenceDays,
          ),
        );
      }
      tasksByDay[dayKey] = projectedDayTasks;
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
        "expandedTaskWindowCount": expandedTaskWindowCount,
        "workUnitLabel": _resolveSafeWorkUnitLabelForStaffing(),
        "totalWorkUnits": safeTotalWorkUnits,
        "projectionTrackCount": completedWorkUnitsByTrackGlobal.length,
        "projectionMaxRemaining": completedWorkUnitsByTrackGlobal.values.isEmpty
            ? safeTotalWorkUnits
            : completedWorkUnitsByTrackGlobal.values
                  .map((completed) => safeTotalWorkUnits - completed)
                  .reduce((left, right) => left > right ? left : right),
        "projectionLifecycleRanks": lifecycleRankByTrack.values.toSet().toList()
          ..sort(),
        "repeatableTrackCount": cadenceDaysByTrack.values
            .where((cadenceDays) => cadenceDays > 0)
            .length,
        "nextAction": completedWorkUnitsByTrackGlobal.isEmpty
            ? "No execution-role tasks found for projection."
            : "Review stage-gated projections before drafting.",
      },
    );
    return weeks;
  }

  String _staffPreviewLabel({
    required String staffProfileId,
    required BusinessStaffProfileSummary? profile,
  }) {
    if (profile != null) {
      final displayName = _resolveAssistantStaffDisplayName(profile).trim();
      if (displayName.isNotEmpty && displayName != staffProfileId) {
        return displayName;
      }
    }
    if (staffProfileId.length <= 8) {
      return staffProfileId;
    }
    return "${staffProfileId.substring(0, 6)}...";
  }

  String _staffPreviewInitials({
    required String staffProfileId,
    required BusinessStaffProfileSummary? profile,
  }) {
    final label = _staffPreviewLabel(
      staffProfileId: staffProfileId,
      profile: profile,
    );
    if (label.isEmpty) {
      return "?";
    }
    final words = label
        .split(RegExp(r"\s+"))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    if (words.length >= 2) {
      final first = words.first.trim().substring(0, 1).toUpperCase();
      final second = words.last.trim().substring(0, 1).toUpperCase();
      return "$first$second";
    }
    return label.substring(0, 1).toUpperCase();
  }

  void _openStaffProfileFromPreview({
    required String staffProfileId,
    required BuildContext sheetContext,
  }) {
    final safeId = staffProfileId.trim();
    if (safeId.isEmpty) {
      return;
    }
    AppDebug.log(
      _logTag,
      _previewStaffProfileTapLog,
      extra: {"staffProfileId": safeId},
    );
    Navigator.of(sheetContext).pop();
    if (!mounted) return;
    AppDebug.log(
      _logTag,
      _previewStaffProfileNavigateLog,
      extra: {
        "staffProfileId": safeId,
        "route": businessStaffDetailPath(safeId),
      },
    );
    context.push(businessStaffDetailPath(safeId));
  }

  Widget _buildAssignedStaffChipsForPreview({
    required BuildContext sheetContext,
    required List<String> assignedStaffProfileIds,
    required Map<String, BusinessStaffProfileSummary> staffById,
  }) {
    final theme = Theme.of(sheetContext);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: assignedStaffProfileIds.map((staffId) {
        final safeId = staffId.trim();
        if (safeId.isEmpty) {
          return const SizedBox.shrink();
        }
        final profile = staffById[safeId];
        final label = _staffPreviewLabel(
          staffProfileId: safeId,
          profile: profile,
        );
        final initials = _staffPreviewInitials(
          staffProfileId: safeId,
          profile: profile,
        );
        return Tooltip(
          message: "$label | $safeId",
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openStaffProfileFromPreview(
              staffProfileId: safeId,
              sheetContext: sheetContext,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      initials,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _previewDraftProductionSchedule(
    ProductionAssistantPlanDraftPayload payload,
  ) async {
    final scopedPayload = _sanitizePlanDraftPayloadForFocusedContext(
      payload: payload,
    );
    final weeklyRows = _buildWeeklyScheduleRows(scopedPayload);
    final safeWorkUnitLabel = _resolveSafeWorkUnitLabelForStaffing();
    final safeTotalWorkUnits = _resolveSafeTotalWorkUnitsForPreview();
    final projectedSummary = _resolveProjectedSummaryFromRows(
      weeklyRows: weeklyRows,
      safeTotalWorkUnits: safeTotalWorkUnits,
    );
    final previewStaffProfiles =
        ref.read(productionStaffProvider).valueOrNull ??
        const <BusinessStaffProfileSummary>[];
    final previewStaffById = <String, BusinessStaffProfileSummary>{
      for (final profile in previewStaffProfiles)
        if (profile.id.trim().isNotEmpty) profile.id.trim(): profile,
    };
    AppDebug.log(
      _logTag,
      "draft_production_preview_open",
      extra: {
        "weeks": weeklyRows.length,
        "days": scopedPayload.days,
        "phaseCount": scopedPayload.phases.length,
        "staffLookupCount": previewStaffById.length,
        "workUnitLabel": safeWorkUnitLabel,
        "totalWorkUnits": safeTotalWorkUnits,
        "projectionTrackCount": projectedSummary.executionTaskTrackCount,
        "projectionCoveredAcrossTracks":
            projectedSummary.minimumCoveredAcrossTracks,
        "projectionWorstRemaining":
            projectedSummary.maximumRemainingAcrossTracks,
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
                    const SizedBox(height: 2),
                    if (projectedSummary.hasExecutionTaskTracks) ...[
                      Text(
                        "$_draftPlanProjectedCoverageLabel: ${_formatWorkUnitsCountForPreview(value: projectedSummary.minimumCoveredAcrossTracks, workUnitLabel: safeWorkUnitLabel)} / ${_formatWorkUnitsCountForPreview(value: projectedSummary.expectedWorkUnitsPerTrack, workUnitLabel: safeWorkUnitLabel)} | $_draftPlanProjectedRemainingLabel: ${_formatWorkUnitsCountForPreview(value: projectedSummary.maximumRemainingAcrossTracks, workUnitLabel: safeWorkUnitLabel)}",
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      Text(
                        "$_draftPlanProjectedTrackCountLabel: ${projectedSummary.fullyCoveredTrackCount}/${projectedSummary.executionTaskTrackCount}",
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                    ],
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
                                final scheduledDays = week.days
                                    .where((day) => day.tasks.isNotEmpty)
                                    .toList();
                                final hiddenEmptyDayCount =
                                    week.days.length - scheduledDays.length;
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
                                        if (scheduledDays.isEmpty)
                                          Text(
                                            "No task scheduled this week.",
                                            style: Theme.of(
                                              sheetContext,
                                            ).textTheme.bodySmall,
                                          )
                                        else ...[
                                          if (hiddenEmptyDayCount > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Text(
                                                "$hiddenEmptyDayCount empty day(s) hidden for clarity.",
                                                style: Theme.of(sheetContext)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          Theme.of(sheetContext)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                              ),
                                            ),
                                          ...scheduledDays.map((day) {
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
                                                  ...day.tasks.map(
                                                    (task) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 8,
                                                            bottom: 4,
                                                          ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            "${_formatTaskTime(task.startDate)} - ${_formatTaskTime(task.dueDate)} | ${_normalizeLifecycleTaskTitle(task.title)} | ${task.roleRequired} x${task.requiredHeadcount}",
                                                            style: Theme.of(
                                                              sheetContext,
                                                            ).textTheme.bodySmall,
                                                          ),
                                                          if (_isPlotExecutionRoleForPreview(
                                                            task.roleRequired,
                                                          ))
                                                            if (task.projectionIsRepeatable ||
                                                                task.projectedWorkUnits >
                                                                    0 ||
                                                                task.projectedWorkUnitsRemaining >
                                                                    0)
                                                              Text(
                                                                "$_draftPlanTaskProjectedLabel: ${_formatWorkUnitsCountForPreview(value: task.projectedWorkUnits, workUnitLabel: safeWorkUnitLabel)} | $_draftPlanTaskRemainingLabel: ${_formatWorkUnitsCountForPreview(value: task.projectedWorkUnitsRemaining, workUnitLabel: safeWorkUnitLabel)}${task.projectionIsRepeatable ? " (${_projectionCadenceLabel(task.projectionCadenceDays)})" : ""}",
                                                                style: Theme.of(sheetContext)
                                                                    .textTheme
                                                                    .bodySmall
                                                                    ?.copyWith(
                                                                      color: Theme.of(
                                                                        sheetContext,
                                                                      ).colorScheme.onSurfaceVariant,
                                                                    ),
                                                              ),
                                                          if (task
                                                              .assignedStaffProfileIds
                                                              .isNotEmpty) ...[
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            _buildAssignedStaffChipsForPreview(
                                                              sheetContext:
                                                                  sheetContext,
                                                              assignedStaffProfileIds:
                                                                  task.assignedStaffProfileIds,
                                                              staffById:
                                                                  previewStaffById,
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final useVerticalActions = constraints.maxWidth < 540;
                        final closeButton = OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text(_draftPlanCloseLabel),
                        );
                        final downloadButton = OutlinedButton.icon(
                          onPressed: () async {
                            await _downloadDraftProductionSchedulePreview(
                              payload: scopedPayload,
                              weeklyRows: weeklyRows,
                              projectedSummary: projectedSummary,
                              safeWorkUnitLabel: safeWorkUnitLabel,
                              staffById: previewStaffById,
                            );
                          },
                          icon: const Icon(Icons.download_outlined),
                          label: const Text(_draftPlanDownloadLabel),
                        );
                        final continueButton = FilledButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            await _applyDraftAndOpenEditor(scopedPayload);
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text(_draftPlanContinueLabel),
                        );

                        if (useVerticalActions) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              closeButton,
                              const SizedBox(height: 8),
                              downloadButton,
                              const SizedBox(height: 8),
                              continueButton,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            closeButton,
                            const SizedBox(width: 8),
                            downloadButton,
                            const Spacer(),
                            continueButton,
                          ],
                        );
                      },
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

  Future<void> _downloadDraftProductionSchedulePreview({
    required ProductionAssistantPlanDraftPayload payload,
    required List<_AssistantWeeklySchedule> weeklyRows,
    required _AssistantProjectionSummary projectedSummary,
    required String safeWorkUnitLabel,
    required Map<String, BusinessStaffProfileSummary> staffById,
  }) async {
    final assetsAsync = ref.read(
      businessAssetsProvider(
        const BusinessAssetsQuery(page: _queryPage, limit: _queryLimit),
      ),
    );
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
    final selectedProductName = _resolveSelectedProductName();
    final focusedRoles = _focusedRoleKeys.toList()..sort();
    final focusedStaffProfileIds = _focusedStaffProfileIds.toList()..sort();
    final alignmentPercent =
        (_resolveWorkspaceAlignmentScore(payload: payload) * 100).round();
    final fileName = _buildDraftScheduleDownloadFileName(payload);
    final draftContents = _buildDraftScheduleDownloadContents(
      payload: payload,
      weeklyRows: weeklyRows,
      projectedSummary: projectedSummary,
      safeWorkUnitLabel: safeWorkUnitLabel,
      staffById: staffById,
      selectedEstateName: selectedEstateName,
      selectedProductName: selectedProductName,
      focusedRoles: focusedRoles,
      focusedStaffProfileIds: focusedStaffProfileIds,
      alignmentPercent: alignmentPercent,
    );
    AppDebug.log(
      _logTag,
      _downloadDraftTapLog,
      extra: {
        "intent": "download draft preview for offline review",
        "fileName": fileName,
        "weeks": weeklyRows.length,
        "phaseCount": payload.phases.length,
        "warningCount": payload.warnings.length,
      },
    );

    try {
      final savedPath = await downloadPlainTextFile(
        fileName: fileName,
        contents: draftContents,
        mimeType: "text/html",
      );
      AppDebug.log(
        _logTag,
        _downloadDraftSuccessLog,
        extra: {
          "fileName": fileName,
          "savedPath": savedPath ?? "browser-download",
          "contentLength": draftContents.length,
        },
      );
      if (!mounted) return;
      _showSnack(
        savedPath == null
            ? "Draft download started as $fileName."
            : "Draft saved to $savedPath",
      );
    } catch (error) {
      AppDebug.log(
        _logTag,
        _downloadDraftFailureLog,
        extra: {
          "intent": "download draft preview for offline review",
          "classification": _assistantUnknownFailureClassification,
          "justification":
              "Local file export failed outside provider/network flows.",
          "fileName": fileName,
          "error": error.toString(),
          "nextStep":
              "Retry the export. If it keeps failing, inspect platform file permissions.",
        },
      );
      if (!mounted) return;
      _showSnack("Couldn't download the draft yet. Please try again.");
    }
  }

  int _estimateDraftWeeks({
    required ProductionPlanDraftState draft,
    required int safeTotalDays,
  }) {
    final startDate = draft.startDate;
    final endDate = draft.endDate;
    if (startDate != null && endDate != null && !endDate.isBefore(startDate)) {
      final inclusiveDays = endDate.difference(startDate).inDays + 1;
      return ((inclusiveDays / 7).ceil().clamp(1, 9999) as num).toInt();
    }
    return ((safeTotalDays / 7).ceil().clamp(1, 9999) as num).toInt();
  }

  ProductionAssistantPlanDraftPayload _buildPlanDraftPayloadFromStudioDraft({
    required ProductionPlanDraftState draft,
  }) {
    final timingSeedPayload = _lastTurn?.planDraftPayload;
    final strictTimingBuckets = <String, List<ProductionAssistantPlanTask>>{};
    final phaseIndexTimingBuckets =
        <String, List<ProductionAssistantPlanTask>>{};

    void addTimingBucket({
      required Map<String, List<ProductionAssistantPlanTask>> buckets,
      required String key,
      required ProductionAssistantPlanTask task,
    }) {
      final bucket = buckets.putIfAbsent(
        key,
        () => <ProductionAssistantPlanTask>[],
      );
      bucket.add(task);
    }

    if (timingSeedPayload != null) {
      for (final phase in timingSeedPayload.phases) {
        for (
          var taskIndex = 0;
          taskIndex < phase.tasks.length;
          taskIndex += 1
        ) {
          final task = phase.tasks[taskIndex];
          addTimingBucket(
            buckets: strictTimingBuckets,
            key:
                "${phase.name.trim().toLowerCase()}|${_normalizeLifecycleTaskTitle(task.title).trim().toLowerCase()}|${_normalizeRoleKey(task.roleRequired)}",
            task: task,
          );
          addTimingBucket(
            buckets: phaseIndexTimingBuckets,
            key: "${phase.order}|$taskIndex",
            task: task,
          );
        }
      }
    }

    ProductionAssistantPlanTask? takeTimingSeedTask({
      required ProductionPhaseDraft phase,
      required ProductionTaskDraft task,
      required int taskIndex,
    }) {
      final strictKey =
          "${phase.name.trim().toLowerCase()}|${_normalizeLifecycleTaskTitle(task.title).trim().toLowerCase()}|${_normalizeRoleKey(task.roleRequired)}";
      final strictBucket = strictTimingBuckets[strictKey];
      if (strictBucket != null && strictBucket.isNotEmpty) {
        return strictBucket.removeAt(0);
      }
      final fallbackBucket =
          phaseIndexTimingBuckets["${phase.order}|$taskIndex"];
      if (fallbackBucket != null && fallbackBucket.isNotEmpty) {
        return fallbackBucket.removeAt(0);
      }
      return null;
    }

    final resolvedProductName = _resolveSelectedProductName().trim().isNotEmpty
        ? _resolveSelectedProductName().trim()
        : draft.title.trim().replaceAll(
            RegExp(r"\s+plan$", caseSensitive: false),
            "",
          );
    final safeProductName = resolvedProductName.isEmpty
        ? "Production"
        : resolvedProductName;
    final safeTotalDays = draft.totalEstimatedDays > 0
        ? draft.totalEstimatedDays
        : draft.phases.fold<int>(
            0,
            (sum, phase) =>
                sum + (phase.estimatedDays < 1 ? 1 : phase.estimatedDays),
          );
    final safeWeeks = _estimateDraftWeeks(
      draft: draft,
      safeTotalDays: safeTotalDays < 1 ? 1 : safeTotalDays,
    );
    final payloadWarnings = draft.riskNotes
        .map((note) => note.trim())
        .where((note) => note.isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map(
          (entry) => ProductionAssistantPlanWarning(
            code: "draft_warning_${entry.key + 1}",
            message: entry.value,
          ),
        )
        .toList(growable: false);
    final payloadPhases = draft.phases
        .map(
          (phase) => ProductionAssistantPlanPhase(
            name: phase.name.trim().isEmpty
                ? "Phase ${phase.order}"
                : phase.name.trim(),
            order: phase.order < 1 ? 1 : phase.order,
            estimatedDays: phase.estimatedDays < 1 ? 1 : phase.estimatedDays,
            phaseType: phase.phaseType,
            requiredUnits: phase.requiredUnits,
            minRatePerFarmerHour: phase.minRatePerFarmerHour,
            targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
            plannedHoursPerDay: phase.plannedHoursPerDay,
            biologicalMinDays: phase.biologicalMinDays,
            tasks: phase.tasks
                .asMap()
                .entries
                .map((entry) {
                  final task = entry.value;
                  final timingSeedTask = takeTimingSeedTask(
                    phase: phase,
                    task: task,
                    taskIndex: entry.key,
                  );
                  return ProductionAssistantPlanTask(
                    title: task.title.trim().isEmpty
                        ? "Task"
                        : task.title.trim(),
                    roleRequired: task.roleRequired.trim().isEmpty
                        ? "farmer"
                        : task.roleRequired.trim(),
                    requiredHeadcount: task.requiredHeadcount < 1
                        ? 1
                        : task.requiredHeadcount,
                    weight: task.weight < 1 ? 1 : task.weight,
                    instructions: task.instructions.trim(),
                    taskType: task.taskType.trim(),
                    sourceTemplateKey: task.sourceTemplateKey.trim(),
                    recurrenceGroupKey: task.recurrenceGroupKey.trim(),
                    occurrenceIndex: task.occurrenceIndex,
                    startDate: timingSeedTask?.startDate,
                    dueDate: timingSeedTask?.dueDate,
                    assignedStaffProfileIds: task.assignedStaffProfileIds,
                  );
                })
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    return ProductionAssistantPlanDraftPayload(
      productId: (draft.productId ?? _selectedProductId ?? "").trim(),
      productName: safeProductName,
      startDate: draft.startDate == null
          ? ""
          : formatDateInput(draft.startDate!),
      endDate: draft.endDate == null ? "" : formatDateInput(draft.endDate!),
      days: safeTotalDays < 1 ? 1 : safeTotalDays,
      weeks: safeWeeks,
      phases: payloadPhases,
      warnings: payloadWarnings,
      plannerMeta: _lastTurn?.planDraftPayload?.plannerMeta,
      lifecycle: _lastTurn?.planDraftPayload?.lifecycle,
    );
  }

  Future<void> _inspectAndImproveCurrentDraft({
    required ProductionPlanDraftState draft,
  }) async {
    if (_isSending || _isImportingDraftDocument || _isImprovingDraft) {
      return;
    }
    final hasDraftTasks = draft.phases.any((phase) => phase.tasks.isNotEmpty);
    if (!hasDraftTasks) {
      _showSnack("Generate or build a draft before improving it.");
      return;
    }

    final report = _buildDraftImprovementReport(draft: draft);
    AppDebug.log(
      _logTag,
      _inspectDraftTapLog,
      extra: {
        "issueCount": report.issueSummaries.length,
        "changeCount": report.changeSummaries.length,
        "genericTaskCount": report.genericTaskCount,
        "phaseMismatchCount": report.phaseMismatchCount,
        "redundantSupervisionCount": report.redundantSupervisionCount,
        "underfilledWeekCount": report.underfilledWeekCount,
        "oneDayWeekCount": report.oneDayWeekCount,
        "twoDayWeekCount": report.twoDayWeekCount,
      },
    );
    if (!mounted) {
      return;
    }

    final shouldApply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final issueColor = theme.colorScheme.tertiary;
        final changeColor = theme.colorScheme.primary;
        final unresolvedColor = theme.colorScheme.error;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Improve draft",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Inspect the current draft first, then apply bounded repairs without regenerating the whole plan.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildDraftRepairSummaryChip(
                        icon: Icons.warning_amber_rounded,
                        label: "Issues",
                        value: "${report.issueSummaries.length}",
                      ),
                      _buildDraftRepairSummaryChip(
                        icon: Icons.auto_fix_high_outlined,
                        label: "Planned fixes",
                        value: "${report.changeSummaries.length}",
                      ),
                      _buildDraftRepairSummaryChip(
                        icon: Icons.track_changes_outlined,
                        label: "Coverage",
                        value: report.beforeCoverageLabel,
                      ),
                      _buildDraftRepairSummaryChip(
                        icon: Icons.task_alt_outlined,
                        label: "After repair",
                        value: report.afterCoverageLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    "What looks wrong",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (report.issueSummaries.isEmpty)
                    Text(
                      "No obvious structural issues were detected in this pass.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...report.issueSummaries.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.report_problem_outlined,
                              size: 18,
                              color: issueColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(line)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    "What will change",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (report.changeSummaries.isEmpty)
                    Text(
                      "This pass did not find safe automatic changes to apply.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...report.changeSummaries.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.auto_fix_high_outlined,
                              size: 18,
                              color: changeColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(line)),
                          ],
                        ),
                      ),
                    ),
                  if (report.unresolvedWarnings.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      "Still needs review",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...report.unresolvedWarnings.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 18,
                              color: unresolvedColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(line)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: const Text("Close"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: report.hasChanges
                              ? () => Navigator.of(sheetContext).pop(true)
                              : null,
                          icon: const Icon(Icons.auto_fix_high_outlined),
                          label: const Text(_draftStudioImproveLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldApply == true) {
      await _applyDraftImprovementsToStudio(draft: draft, report: report);
    }
  }

  Future<void> _applyDraftImprovementsToStudio({
    required ProductionPlanDraftState draft,
    required _DraftImprovementReport report,
  }) async {
    if (_isImprovingDraft) {
      return;
    }
    setState(() {
      _isImprovingDraft = true;
    });

    try {
      final improvedState = _buildStudioDraftStateFromImprovedPayload(
        currentDraft: draft,
        currentPayload: report.currentPayload,
        improvedPayload: report.improvedPayload,
      );
      final currentTurn = _lastTurn;
      final nextTurn = currentTurn == null
          ? ProductionAssistantTurn(
              action: productionAssistantActionPlanDraft,
              message: "Draft improved locally.",
              suggestionsPayload: null,
              clarifyPayload: null,
              draftProductPayload: null,
              planDraftPayload: report.improvedPayload,
            )
          : ProductionAssistantTurn(
              action: currentTurn.action,
              message: currentTurn.message,
              suggestionsPayload: currentTurn.suggestionsPayload,
              clarifyPayload: currentTurn.clarifyPayload,
              draftProductPayload: currentTurn.draftProductPayload,
              planDraftPayload: report.improvedPayload,
            );
      ref.read(productionPlanDraftProvider.notifier).applyDraft(improvedState);
      _syncDraftEditors(improvedState);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastTurn = nextTurn;
        _lastDraftImprovementReport = report;
        _showDraftStudio = true;
        _draftStudioPanel = _DraftStudioPanel.overview;
      });
      AppDebug.log(
        _logTag,
        _improveDraftSuccessLog,
        extra: {
          "expandedGenericTaskCount": report.expandedGenericTaskCount,
          "removedSupervisionCount": report.removedSupervisionCount,
          "phaseRebucketedCount": report.phaseRebucketedCount,
          "instructionsAddedCount": report.instructionsAddedCount,
          "roleAdjustedCount": report.roleAdjustedCount,
          "insertedSupportTaskCount": report.insertedSupportTaskCount,
          "stretchedTaskWindowCount": report.stretchedTaskWindowCount,
          "densifiedWeekCount": report.densifiedWeekCount,
        },
      );
      _showSnack(report.snackSummary);
    } catch (error) {
      AppDebug.log(
        _logTag,
        _improveDraftFailureLog,
        extra: {"error": error.toString()},
      );
      if (mounted) {
        _showSnack("Couldn't improve the draft yet.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImprovingDraft = false;
        });
      } else {
        _isImprovingDraft = false;
      }
    }
  }

  _DraftImprovementReport _buildDraftImprovementReport({
    required ProductionPlanDraftState draft,
  }) {
    final currentPayload = _buildPlanDraftPayloadFromStudioDraft(draft: draft);
    final safeTotalWorkUnits = _resolveSafeTotalWorkUnitsForPreview();
    final beforeRows = _buildWeeklyScheduleRows(currentPayload);
    final beforeProjection = _resolveProjectedSummaryFromRows(
      weeklyRows: beforeRows,
      safeTotalWorkUnits: safeTotalWorkUnits,
    );
    final beforeDensity = _analyzeDraftScheduleDensity(payload: currentPayload);
    final genericTaskCount = _countGenericDraftTasks(payload: currentPayload);
    final missingInstructionCount = _countDraftTasksMissingInstructions(
      payload: currentPayload,
    );
    final phaseMismatchCount = _findDraftPhaseMismatchCount(
      payload: currentPayload,
    );
    final redundantManagementInfo = _findDraftRedundantManagementInfo(
      payload: currentPayload,
    );
    final selectedRoleKeys = _buildDraftRepairRoleKeys(payload: currentPayload);
    final focusedStaffIdsByRole = _buildFocusedStaffIdsByRole(
      estateScopedStaffProfiles: _staffForSelectedEstate(
        staffProfiles:
            ref.read(productionStaffProvider).valueOrNull ??
            const <BusinessStaffProfileSummary>[],
      ),
      focusedStaffProfileIds: _focusedStaffProfileIds,
    );
    final mutation = _repairDraftPayload(
      payload: currentPayload,
      selectedRoleKeys: selectedRoleKeys,
      focusedStaffIdsByRole: focusedStaffIdsByRole,
    );
    var improvedPayload = mutation.payload;
    final afterRows = _buildWeeklyScheduleRows(improvedPayload);
    final afterProjection = _resolveProjectedSummaryFromRows(
      weeklyRows: afterRows,
      safeTotalWorkUnits: safeTotalWorkUnits,
    );
    final afterDensity = _analyzeDraftScheduleDensity(payload: improvedPayload);
    final unresolvedWarnings = <String>[];
    if (afterProjection.hasExecutionTaskTracks &&
        afterProjection.maximumRemainingAcrossTracks > 0) {
      unresolvedWarnings.add(
        "Coverage is still short after repair: ${afterProjection.minimumCoveredAcrossTracks}/${afterProjection.expectedWorkUnitsPerTrack} ${_resolveSafeWorkUnitLabelForStaffing()} fully covered across execution tracks.",
      );
    }
    if (afterProjection.executionTaskTrackCount > 0 &&
        afterProjection.fullyCoveredTrackCount <
            afterProjection.executionTaskTrackCount) {
      unresolvedWarnings.add(
        "Not every execution track is fully covered yet. Review workload, staffing, or timeline before saving.",
      );
    }
    if (afterDensity.underfilledWeekCount > 0) {
      unresolvedWarnings.add(
        "Calendar still has ${afterDensity.underfilledWeekCount} underfilled week(s) with two or fewer active days. Review thin weeks before saving.",
      );
    }
    for (final warning in currentPayload.warnings) {
      final normalizedCode = warning.code.trim().toLowerCase();
      if (normalizedCode.contains("stage_gate") ||
          normalizedCode.contains("coverage") ||
          normalizedCode.contains("locked") ||
          normalizedCode.contains("capped")) {
        unresolvedWarnings.add(warning.message.trim());
      }
    }
    if (unresolvedWarnings.isNotEmpty) {
      final warningList = <ProductionAssistantPlanWarning>[
        ...improvedPayload.warnings,
      ];
      for (final message in unresolvedWarnings.toSet()) {
        warningList.add(
          ProductionAssistantPlanWarning(
            code: _draftRepairUnresolvedCoverageWarningCode,
            message: message,
          ),
        );
      }
      improvedPayload = ProductionAssistantPlanDraftPayload(
        productId: improvedPayload.productId,
        productName: improvedPayload.productName,
        startDate: improvedPayload.startDate,
        endDate: improvedPayload.endDate,
        days: improvedPayload.days,
        weeks: improvedPayload.weeks,
        phases: improvedPayload.phases,
        warnings: _dedupeDraftWarnings(warningList),
        plannerMeta: improvedPayload.plannerMeta,
        lifecycle: improvedPayload.lifecycle,
      );
    }
    final improvedCropName = improvedPayload.productName.trim().isEmpty
        ? _resolveSelectedProductName()
        : improvedPayload.productName.trim();
    final improvedCropKey = _resolveDraftRepairCropKey(improvedCropName);
    if (_supportsDraftRepairPlantingCounts(improvedCropKey) &&
        _countDraftYieldBasisTrackingTasks(payload: improvedPayload) > 0 &&
        !improvedPayload.warnings.any(
          (warning) =>
              warning.code.trim().toLowerCase() ==
              _draftRepairYieldBasisWarningCode,
        )) {
      improvedPayload = ProductionAssistantPlanDraftPayload(
        productId: improvedPayload.productId,
        productName: improvedPayload.productName,
        startDate: improvedPayload.startDate,
        endDate: improvedPayload.endDate,
        days: improvedPayload.days,
        weeks: improvedPayload.weeks,
        phases: improvedPayload.phases,
        warnings: _dedupeDraftWarnings([
          ...improvedPayload.warnings,
          ProductionAssistantPlanWarning(
            code: _draftRepairYieldBasisWarningCode,
            message:
                "Improve draft added seed, establishment, and yield-basis tracking tasks. Record counts from sowing through established stands, and forecast expected yield from surviving plants or stands rather than raw seed used.",
          ),
        ]),
        plannerMeta: improvedPayload.plannerMeta,
        lifecycle: improvedPayload.lifecycle,
      );
    }
    return _DraftImprovementReport(
      currentPayload: currentPayload,
      improvedPayload: improvedPayload,
      beforeProjection: beforeProjection,
      afterProjection: afterProjection,
      genericTaskCount: genericTaskCount,
      missingInstructionCount: missingInstructionCount,
      phaseMismatchCount: phaseMismatchCount,
      underfilledWeekCount: beforeDensity.underfilledWeekCount,
      oneDayWeekCount: beforeDensity.oneDayWeekCount,
      twoDayWeekCount: beforeDensity.twoDayWeekCount,
      afterUnderfilledWeekCount: afterDensity.underfilledWeekCount,
      redundantSupervisionCount: redundantManagementInfo.redundantTaskCount,
      supervisionOnlyWeekCount:
          redundantManagementInfo.supervisionOnlyWeekKeys.length,
      expandedGenericTaskCount: mutation.expandedGenericTaskCount,
      removedSupervisionCount: mutation.removedSupervisionCount,
      phaseRebucketedCount: mutation.phaseRebucketedCount,
      instructionsAddedCount: mutation.instructionsAddedCount,
      roleAdjustedCount: mutation.roleAdjustedCount,
      insertedSupportTaskCount: mutation.insertedSupportTaskCount,
      stretchedTaskWindowCount: mutation.stretchedTaskWindowCount,
      densifiedWeekCount: mutation.densifiedWeekCount,
      propagationTaskFixedCount: mutation.propagationTaskFixedCount,
      unresolvedWarnings: unresolvedWarnings.toSet().toList(),
    );
  }

  int _countGenericDraftTasks({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    var count = 0;
    for (final phase in payload.phases) {
      for (final task in phase.tasks) {
        if (_isGenericDraftTaskTitle(task.title)) {
          count += 1;
        }
      }
    }
    return count;
  }

  int _countDraftTasksMissingInstructions({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    var count = 0;
    for (final phase in payload.phases) {
      for (final task in phase.tasks) {
        if (task.instructions.trim().isEmpty) {
          count += 1;
        }
      }
    }
    return count;
  }

  int _countDraftYieldBasisTrackingTasks({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    var count = 0;
    for (final phase in payload.phases) {
      for (final task in phase.tasks) {
        final normalizedTitle = _normalizeDraftRepairKey(
          _normalizeLifecycleTaskTitle(task.title),
        );
        final normalizedInstructions = _normalizeDraftRepairKey(
          task.instructions,
        );
        final tracksYieldBasis =
            normalizedTitle.contains("yield_basis") ||
            normalizedInstructions.contains("yield_basis") ||
            (normalizedTitle.contains("established") &&
                (normalizedTitle.contains("stand") ||
                    normalizedTitle.contains("plant"))) ||
            (normalizedInstructions.contains("established") &&
                (normalizedInstructions.contains("stand") ||
                    normalizedInstructions.contains("plant")));
        if (tracksYieldBasis) {
          count += 1;
        }
      }
    }
    return count;
  }

  List<String> _buildDraftRepairRoleKeys({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    final focusedRoles =
        _focusedRoleKeys
            .map(_normalizeRoleKey)
            .where((role) => role.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (focusedRoles.isNotEmpty) {
      return focusedRoles;
    }
    final payloadRoles =
        payload.phases
            .expand((phase) => phase.tasks)
            .map((task) => _normalizeRoleKey(task.roleRequired))
            .where((role) => role.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return payloadRoles.isEmpty ? <String>[staffRoleFarmer] : payloadRoles;
  }

  _DraftScheduleDensityInfo _analyzeDraftScheduleDensity({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    final weeklyRows = _buildWeeklyScheduleRows(payload);
    final underfilledWeekKeys = <String>{};
    final activeSparseWeekKeys = <String>{};
    final fieldSparseWeekKeys = <String>{};
    final emptyWeekKeys = <String>{};
    final supervisionOnlyWeekKeys = <String>{};
    final scheduledDayCountByWeekKey = <String, int>{};
    final nonManagementDayCountByWeekKey = <String, int>{};
    var oneDayWeekCount = 0;
    var twoDayWeekCount = 0;

    for (final week in weeklyRows) {
      final weekKey = formatDateInput(week.weekStart);
      var scheduledDayCount = 0;
      var nonManagementDayCount = 0;
      var hasManagementTask = false;
      var hasNonManagementTask = false;
      for (final day in week.days) {
        if (day.tasks.isEmpty) {
          continue;
        }
        scheduledDayCount += 1;
        var dayHasNonManagementTask = false;
        for (final task in day.tasks) {
          if (_isManagementOversightScheduleTask(task)) {
            hasManagementTask = true;
            continue;
          }
          hasNonManagementTask = true;
          dayHasNonManagementTask = true;
        }
        if (dayHasNonManagementTask) {
          nonManagementDayCount += 1;
        }
      }
      scheduledDayCountByWeekKey[weekKey] = scheduledDayCount;
      nonManagementDayCountByWeekKey[weekKey] = nonManagementDayCount;
      if (scheduledDayCount == 0) {
        emptyWeekKeys.add(weekKey);
      }
      if (scheduledDayCount <= 2) {
        underfilledWeekKeys.add(weekKey);
        if (scheduledDayCount > 0) {
          activeSparseWeekKeys.add(weekKey);
        }
      }
      if (nonManagementDayCount > 0 && nonManagementDayCount <= 2) {
        fieldSparseWeekKeys.add(weekKey);
      }
      if (scheduledDayCount == 1) {
        oneDayWeekCount += 1;
      }
      if (scheduledDayCount == 2) {
        twoDayWeekCount += 1;
      }
      if (hasManagementTask && !hasNonManagementTask) {
        supervisionOnlyWeekKeys.add(weekKey);
      }
    }

    return _DraftScheduleDensityInfo(
      underfilledWeekKeys: underfilledWeekKeys,
      activeSparseWeekKeys: activeSparseWeekKeys,
      fieldSparseWeekKeys: fieldSparseWeekKeys,
      emptyWeekKeys: emptyWeekKeys,
      supervisionOnlyWeekKeys: supervisionOnlyWeekKeys,
      scheduledDayCountByWeekKey: scheduledDayCountByWeekKey,
      nonManagementDayCountByWeekKey: nonManagementDayCountByWeekKey,
      oneDayWeekCount: oneDayWeekCount,
      twoDayWeekCount: twoDayWeekCount,
    );
  }

  _DraftRedundantManagementInfo _findDraftRedundantManagementInfo({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    final density = _analyzeDraftScheduleDensity(payload: payload);
    final supervisionOnlyWeekKeys = density.supervisionOnlyWeekKeys;
    var redundantTaskCount = 0;
    for (final phase in payload.phases) {
      for (final task in phase.tasks) {
        if (!_isManagementOversightTask(task)) {
          continue;
        }
        final weekKey = _draftRepairWeekKeyForTask(task);
        if (weekKey.isNotEmpty && supervisionOnlyWeekKeys.contains(weekKey)) {
          redundantTaskCount += 1;
        }
      }
    }
    return _DraftRedundantManagementInfo(
      supervisionOnlyWeekKeys: supervisionOnlyWeekKeys,
      redundantTaskCount: redundantTaskCount,
    );
  }

  int _findDraftPhaseMismatchCount({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    final phaseWindows = _buildDraftPhaseWindows(payload: payload);
    if (phaseWindows.isEmpty) {
      return 0;
    }
    var mismatchCount = 0;
    for (var phaseIndex = 0; phaseIndex < payload.phases.length; phaseIndex++) {
      final phase = payload.phases[phaseIndex];
      for (final task in phase.tasks) {
        final targetPhaseIndex = _findClosestPhaseWindowIndex(
          task: task,
          phaseWindows: phaseWindows,
        );
        if (targetPhaseIndex != null && targetPhaseIndex != phaseIndex) {
          mismatchCount += 1;
        }
      }
    }
    return mismatchCount;
  }

  _DraftImprovementMutation _repairDraftPayload({
    required ProductionAssistantPlanDraftPayload payload,
    required List<String> selectedRoleKeys,
    required Map<String, List<String>> focusedStaffIdsByRole,
  }) {
    final cropName = payload.productName.trim().isEmpty
        ? _resolveSelectedProductName()
        : payload.productName.trim();
    final cropKey = _resolveDraftRepairCropKey(cropName);
    final allowCropSpecificTemplates =
        cropKey.isNotEmpty &&
        (_selectedProductLifecycleLabel.trim().isNotEmpty ||
            _selectedProductSourceLabel.trim().toLowerCase().contains(
              "planner",
            ) ||
            (payload.lifecycle?.phases.isNotEmpty ?? false));
    final templateCursorByPhase = <String, int>{};
    var expandedGenericTaskCount = 0;
    var instructionsAddedCount = 0;
    var roleAdjustedCount = 0;
    var propagationTaskFixedCount = 0;

    final expandedPhases = payload.phases
        .map((phase) {
          final phaseKey = _resolveDraftRepairPhaseKey(phase.name);
          final templates = _resolveDraftRepairTemplates(
            cropKey: cropKey,
            cropName: cropName,
            phaseKey: phaseKey,
            allowCropSpecificTemplates: allowCropSpecificTemplates,
          );
          final nextTasks = phase.tasks
              .map((task) {
                final wasGenericTitle = _isGenericDraftTaskTitle(task.title);
                final needsInstruction = task.instructions.trim().isEmpty;
                final propagationRepairTemplate =
                    _resolveDraftPropagationRepairTemplate(
                      cropKey: cropKey,
                      cropName: cropName,
                      phaseKey: phaseKey,
                      rawTaskTitle: task.title,
                    );
                final needsPropagationRepair =
                    propagationRepairTemplate != null;
                if (!wasGenericTitle &&
                    !needsInstruction &&
                    !needsPropagationRepair) {
                  return task;
                }

                final templateKey =
                    "${cropKey.isEmpty ? 'generic' : cropKey}|$phaseKey";
                final templateIndex = templateCursorByPhase[templateKey] ?? 0;
                final template = templates.isEmpty
                    ? null
                    : templates[templateIndex % templates.length];
                templateCursorByPhase[templateKey] = templateIndex + 1;

                final repairedTemplate = propagationRepairTemplate ?? template;
                final nextTitle = needsPropagationRepair
                    ? repairedTemplate!.title.trim()
                    : wasGenericTitle
                    ? (repairedTemplate?.title.trim().isNotEmpty == true
                          ? repairedTemplate!.title.trim()
                          : _buildFallbackDraftRepairTitle(
                              cropName: cropName,
                              phaseName: phase.name,
                            ))
                    : task.title.trim();
                final nextInstructions =
                    needsPropagationRepair || needsInstruction
                    ? (repairedTemplate?.instructions.trim().isNotEmpty == true
                          ? repairedTemplate!.instructions.trim()
                          : _buildFallbackDraftRepairInstruction(
                              cropName: cropName,
                              phaseName: phase.name,
                              taskTitle: nextTitle,
                            ))
                    : task.instructions.trim();
                var nextRole = _normalizeRoleKey(task.roleRequired);
                if (nextRole.isEmpty) {
                  nextRole = staffRoleFarmer;
                }
                final bestRole = _resolveBestRoleForTaskTitle(
                  taskTitle: nextTitle,
                  selectedRoleKeys: selectedRoleKeys,
                  focusedStaffIdsByRole: focusedStaffIdsByRole,
                );
                if (bestRole.isNotEmpty &&
                    bestRole != nextRole &&
                    _taskRoleMatchScore(
                          taskTitle: nextTitle,
                          roleKey: bestRole,
                        ) >
                        _taskRoleMatchScore(
                          taskTitle: nextTitle,
                          roleKey: nextRole,
                        )) {
                  nextRole = bestRole;
                  roleAdjustedCount += 1;
                }
                if (wasGenericTitle && nextTitle != task.title.trim()) {
                  expandedGenericTaskCount += 1;
                }
                if (needsInstruction && nextInstructions.isNotEmpty) {
                  instructionsAddedCount += 1;
                }
                if (needsPropagationRepair &&
                    (nextTitle != task.title.trim() ||
                        nextInstructions != task.instructions.trim())) {
                  propagationTaskFixedCount += 1;
                }
                return ProductionAssistantPlanTask(
                  title: nextTitle,
                  roleRequired: nextRole,
                  requiredHeadcount: task.requiredHeadcount < 1
                      ? 1
                      : task.requiredHeadcount,
                  weight: task.weight < 1 ? 1 : task.weight,
                  instructions: nextInstructions,
                  taskType: task.taskType,
                  sourceTemplateKey: task.sourceTemplateKey,
                  recurrenceGroupKey: task.recurrenceGroupKey,
                  occurrenceIndex: task.occurrenceIndex,
                  startDate: task.startDate,
                  dueDate: task.dueDate,
                  assignedStaffProfileIds: task.assignedStaffProfileIds,
                );
              })
              .toList(growable: false);
          return ProductionAssistantPlanPhase(
            name: phase.name,
            order: phase.order,
            estimatedDays: phase.estimatedDays,
            phaseType: phase.phaseType,
            requiredUnits: phase.requiredUnits,
            minRatePerFarmerHour: phase.minRatePerFarmerHour,
            targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
            plannedHoursPerDay: phase.plannedHoursPerDay,
            biologicalMinDays: phase.biologicalMinDays,
            tasks: nextTasks,
          );
        })
        .toList(growable: false);

    var repairedPayload = ProductionAssistantPlanDraftPayload(
      productId: payload.productId,
      productName: payload.productName,
      startDate: payload.startDate,
      endDate: payload.endDate,
      days: payload.days,
      weeks: payload.weeks,
      phases: expandedPhases,
      warnings: payload.warnings,
      plannerMeta: payload.plannerMeta,
      lifecycle: payload.lifecycle,
    );

    final phaseWindows = _buildDraftPhaseWindows(payload: repairedPayload);
    var phaseRebucketedCount = 0;
    if (phaseWindows.isNotEmpty) {
      final rebucketedTasks = List.generate(
        repairedPayload.phases.length,
        (_) => <ProductionAssistantPlanTask>[],
      );
      for (
        var phaseIndex = 0;
        phaseIndex < repairedPayload.phases.length;
        phaseIndex += 1
      ) {
        final phase = repairedPayload.phases[phaseIndex];
        for (final task in phase.tasks) {
          final targetPhaseIndex = _findClosestPhaseWindowIndex(
            task: task,
            phaseWindows: phaseWindows,
          );
          final resolvedPhaseIndex = targetPhaseIndex ?? phaseIndex;
          if (resolvedPhaseIndex != phaseIndex) {
            phaseRebucketedCount += 1;
          }
          rebucketedTasks[resolvedPhaseIndex].add(task);
        }
      }
      final rebucketedPhases = repairedPayload.phases
          .asMap()
          .entries
          .map((entry) {
            final tasks = [...rebucketedTasks[entry.key]]
              ..sort((left, right) {
                final leftStart = left.startDate?.millisecondsSinceEpoch ?? 0;
                final rightStart = right.startDate?.millisecondsSinceEpoch ?? 0;
                if (leftStart != rightStart) {
                  return leftStart.compareTo(rightStart);
                }
                return left.title.compareTo(right.title);
              });
            return ProductionAssistantPlanPhase(
              name: entry.value.name,
              order: entry.value.order,
              estimatedDays: entry.value.estimatedDays,
              phaseType: entry.value.phaseType,
              requiredUnits: entry.value.requiredUnits,
              minRatePerFarmerHour: entry.value.minRatePerFarmerHour,
              targetRatePerFarmerHour: entry.value.targetRatePerFarmerHour,
              plannedHoursPerDay: entry.value.plannedHoursPerDay,
              biologicalMinDays: entry.value.biologicalMinDays,
              tasks: tasks,
            );
          })
          .toList(growable: false);
      repairedPayload = ProductionAssistantPlanDraftPayload(
        productId: repairedPayload.productId,
        productName: repairedPayload.productName,
        startDate: repairedPayload.startDate,
        endDate: repairedPayload.endDate,
        days: repairedPayload.days,
        weeks: repairedPayload.weeks,
        phases: rebucketedPhases,
        warnings: repairedPayload.warnings,
        plannerMeta: repairedPayload.plannerMeta,
        lifecycle: repairedPayload.lifecycle,
      );
    }

    final redundantManagementInfo = _findDraftRedundantManagementInfo(
      payload: repairedPayload,
    );
    var removedSupervisionCount = 0;
    if (redundantManagementInfo.supervisionOnlyWeekKeys.isNotEmpty) {
      final filteredPhases = repairedPayload.phases
          .map((phase) {
            final tasks = phase.tasks
                .where((task) {
                  if (!_isManagementOversightTask(task)) {
                    return true;
                  }
                  final weekKey = _draftRepairWeekKeyForTask(task);
                  final shouldRemove =
                      weekKey.isNotEmpty &&
                      redundantManagementInfo.supervisionOnlyWeekKeys.contains(
                        weekKey,
                      );
                  if (shouldRemove) {
                    removedSupervisionCount += 1;
                  }
                  return !shouldRemove;
                })
                .toList(growable: false);
            return ProductionAssistantPlanPhase(
              name: phase.name,
              order: phase.order,
              estimatedDays: phase.estimatedDays,
              phaseType: phase.phaseType,
              requiredUnits: phase.requiredUnits,
              minRatePerFarmerHour: phase.minRatePerFarmerHour,
              targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
              plannedHoursPerDay: phase.plannedHoursPerDay,
              biologicalMinDays: phase.biologicalMinDays,
              tasks: tasks,
            );
          })
          .toList(growable: false);
      repairedPayload = ProductionAssistantPlanDraftPayload(
        productId: repairedPayload.productId,
        productName: repairedPayload.productName,
        startDate: repairedPayload.startDate,
        endDate: repairedPayload.endDate,
        days: repairedPayload.days,
        weeks: repairedPayload.weeks,
        phases: filteredPhases,
        warnings: repairedPayload.warnings,
        plannerMeta: repairedPayload.plannerMeta,
        lifecycle: repairedPayload.lifecycle,
      );
    }

    final calendarRepair = _repairDraftCalendarDensity(
      payload: repairedPayload,
      cropKey: cropKey,
      cropName: cropName,
      allowCropSpecificTemplates: allowCropSpecificTemplates,
      selectedRoleKeys: selectedRoleKeys,
      focusedStaffIdsByRole: focusedStaffIdsByRole,
    );
    repairedPayload = calendarRepair.payload;

    return _DraftImprovementMutation(
      payload: repairedPayload,
      expandedGenericTaskCount: expandedGenericTaskCount,
      removedSupervisionCount: removedSupervisionCount,
      phaseRebucketedCount: phaseRebucketedCount,
      instructionsAddedCount: instructionsAddedCount,
      roleAdjustedCount: roleAdjustedCount,
      insertedSupportTaskCount: calendarRepair.insertedSupportTaskCount,
      stretchedTaskWindowCount: calendarRepair.stretchedTaskWindowCount,
      densifiedWeekCount: calendarRepair.densifiedWeekCount,
      propagationTaskFixedCount: propagationTaskFixedCount,
    );
  }

  _DraftCalendarRepairResult _repairDraftCalendarDensity({
    required ProductionAssistantPlanDraftPayload payload,
    required String cropKey,
    required String cropName,
    required bool allowCropSpecificTemplates,
    required List<String> selectedRoleKeys,
    required Map<String, List<String>> focusedStaffIdsByRole,
  }) {
    final beforeDensity = _analyzeDraftScheduleDensity(payload: payload);
    var repairedPayload = payload;
    var insertedSupportTaskCount = 0;
    var stretchedTaskWindowCount = 0;

    if (allowCropSpecificTemplates && cropKey.isNotEmpty) {
      final phaseWindows = _buildDraftPhaseWindows(payload: repairedPayload);
      if (phaseWindows.isNotEmpty) {
        final density = _analyzeDraftScheduleDensity(payload: repairedPayload);
        final phaseWindowByIndex = <int, _DraftPhaseWindow>{
          for (final window in phaseWindows) window.phaseIndex: window,
        };
        final injectedPhases = repairedPayload.phases
            .asMap()
            .entries
            .map((entry) {
              final phase = entry.value;
              final phaseWindow = phaseWindowByIndex[entry.key];
              if (phaseWindow == null) {
                return phase;
              }
              final phaseKey = _resolveDraftRepairPhaseKey(phase.name);
              final recurringTemplates = _resolveDraftRecurringRepairTemplates(
                cropKey: cropKey,
                cropName: cropName,
                phaseKey: phaseKey,
                allowCropSpecificTemplates: allowCropSpecificTemplates,
              );
              if (recurringTemplates.isEmpty) {
                return phase;
              }
              final phaseDensity = _buildDraftRepairWeekDensityForPhase(
                density: density,
                phaseStart: phaseWindow.startDate,
                phaseEnd: phaseWindow.endDate,
              );
              if (!_shouldApplyDraftRecurringRepair(
                phaseDensity: phaseDensity,
                phaseStart: phaseWindow.startDate,
                phaseEnd: phaseWindow.endDate,
              )) {
                return phase;
              }
              final tasks = <ProductionAssistantPlanTask>[...phase.tasks];
              for (final recurringTemplate in recurringTemplates) {
                final occurrenceDates = _buildDraftRepairRecurringDates(
                  phaseStart: phaseWindow.startDate,
                  phaseEnd: phaseWindow.endDate,
                  cadenceDays: recurringTemplate.cadenceDays,
                  preferredWeekday: recurringTemplate.preferredWeekday,
                );
                var occurrenceIndex = 0;
                for (final occurrenceDate in occurrenceDates) {
                  final weekKey = formatDateInput(
                    _startOfWeekMonday(occurrenceDate),
                  );
                  final scheduledDayCount =
                      density.scheduledDayCountByWeekKey[weekKey] ?? 0;
                  final nonManagementDayCount =
                      density.nonManagementDayCountByWeekKey[weekKey] ?? 0;
                  if (scheduledDayCount > 3 && nonManagementDayCount > 2) {
                    continue;
                  }
                  if (_hasSimilarDraftTaskNearDate(
                    tasks: tasks,
                    title: recurringTemplate.title,
                    targetDate: occurrenceDate,
                    toleranceDays: _resolveDraftRepairDuplicateToleranceDays(
                      cadenceDays: recurringTemplate.cadenceDays,
                    ),
                  )) {
                    continue;
                  }
                  final resolvedRole = _resolveDraftRepairRoleForRecurringTask(
                    template: recurringTemplate,
                    selectedRoleKeys: selectedRoleKeys,
                    focusedStaffIdsByRole: focusedStaffIdsByRole,
                  );
                  final requiredHeadcount = _resolveDraftRepairHeadcountForRole(
                    roleKey: resolvedRole,
                  );
                  final assignedStaffProfileIds =
                      _resolveDraftRepairAssignedStaffIds(
                        roleKey: resolvedRole,
                        requiredHeadcount: requiredHeadcount,
                        focusedStaffIdsByRole: focusedStaffIdsByRole,
                      );
                  occurrenceIndex += 1;
                  final taskStart = DateTime(
                    occurrenceDate.year,
                    occurrenceDate.month,
                    occurrenceDate.day,
                    recurringTemplate.startHour,
                    0,
                  );
                  final taskDue = taskStart.add(
                    Duration(hours: recurringTemplate.durationHours),
                  );
                  tasks.add(
                    ProductionAssistantPlanTask(
                      title: recurringTemplate.title,
                      roleRequired: resolvedRole,
                      requiredHeadcount: requiredHeadcount,
                      weight: 1,
                      instructions: recurringTemplate.instructions,
                      taskType: "event",
                      sourceTemplateKey:
                          "draft_repair_${cropKey}_${phaseKey}_${_normalizeDraftRepairKey(recurringTemplate.title)}_${formatDateInput(occurrenceDate)}",
                      recurrenceGroupKey:
                          "draft_repair_${cropKey}_${phaseKey}_${_normalizeDraftRepairKey(recurringTemplate.title)}",
                      occurrenceIndex: occurrenceIndex,
                      startDate: taskStart,
                      dueDate: taskDue,
                      assignedStaffProfileIds: assignedStaffProfileIds,
                    ),
                  );
                  insertedSupportTaskCount += 1;
                }
              }
              if (tasks.length == phase.tasks.length) {
                return phase;
              }
              _sortDraftRepairTasks(tasks);
              return ProductionAssistantPlanPhase(
                name: phase.name,
                order: phase.order,
                estimatedDays: phase.estimatedDays,
                phaseType: phase.phaseType,
                requiredUnits: phase.requiredUnits,
                minRatePerFarmerHour: phase.minRatePerFarmerHour,
                targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
                plannedHoursPerDay: phase.plannedHoursPerDay,
                biologicalMinDays: phase.biologicalMinDays,
                tasks: tasks,
              );
            })
            .toList(growable: false);
        repairedPayload = ProductionAssistantPlanDraftPayload(
          productId: repairedPayload.productId,
          productName: repairedPayload.productName,
          startDate: repairedPayload.startDate,
          endDate: repairedPayload.endDate,
          days: repairedPayload.days,
          weeks: repairedPayload.weeks,
          phases: injectedPhases,
          warnings: repairedPayload.warnings,
          plannerMeta: repairedPayload.plannerMeta,
          lifecycle: repairedPayload.lifecycle,
        );
      }
    }

    if (allowCropSpecificTemplates && cropKey.isNotEmpty) {
      final phaseWindows = _buildDraftPhaseWindows(payload: repairedPayload);
      if (phaseWindows.isNotEmpty) {
        final density = _analyzeDraftScheduleDensity(payload: repairedPayload);
        final phaseWindowByIndex = <int, _DraftPhaseWindow>{
          for (final window in phaseWindows) window.phaseIndex: window,
        };
        final injectedPhases = repairedPayload.phases
            .asMap()
            .entries
            .map((entry) {
              final phase = entry.value;
              final phaseWindow = phaseWindowByIndex[entry.key];
              if (phaseWindow == null) {
                return phase;
              }
              final phaseKey = _resolveDraftRepairPhaseKey(phase.name);
              if (!_canInjectCropSpecificSupportTasks(
                cropKey: cropKey,
                phaseKey: phaseKey,
                allowCropSpecificTemplates: allowCropSpecificTemplates,
              )) {
                return phase;
              }
              final recurringTemplates = _resolveDraftRecurringRepairTemplates(
                cropKey: cropKey,
                cropName: cropName,
                phaseKey: phaseKey,
                allowCropSpecificTemplates: allowCropSpecificTemplates,
              );
              if (recurringTemplates.isNotEmpty) {
                return phase;
              }
              final cadenceDays = _resolveDraftRepairCadenceDays(
                phaseKey: phaseKey,
              );
              if (cadenceDays < 7) {
                return phase;
              }
              final phaseWeekKeys = _buildDraftRepairWeekKeysForRange(
                startDate: phaseWindow.startDate,
                endDate: phaseWindow.endDate,
              );
              if (phaseWeekKeys.length < 2) {
                return phase;
              }
              final templates = _resolveDraftRepairTemplates(
                cropKey: cropKey,
                cropName: cropName,
                phaseKey: phaseKey,
                allowCropSpecificTemplates: allowCropSpecificTemplates,
              );
              if (templates.isEmpty) {
                return phase;
              }
              final tasks = <ProductionAssistantPlanTask>[...phase.tasks];
              final stepWeeks = ((cadenceDays / 7).ceil()).clamp(1, 4);
              var templateCursor = 0;
              for (
                var weekIndex = 0;
                weekIndex < phaseWeekKeys.length;
                weekIndex += stepWeeks
              ) {
                final weekKey = phaseWeekKeys[weekIndex];
                final scheduledDayCount =
                    density.scheduledDayCountByWeekKey[weekKey] ?? 0;
                final nonManagementDayCount =
                    density.nonManagementDayCountByWeekKey[weekKey] ?? 0;
                if (scheduledDayCount > 2 || nonManagementDayCount > 1) {
                  continue;
                }
                final weekStart = DateTime.tryParse(weekKey);
                if (weekStart == null) {
                  continue;
                }
                final template = templates[templateCursor % templates.length];
                templateCursor += 1;
                if (_hasSimilarDraftTaskInWeek(
                  tasks: tasks,
                  title: template.title,
                  weekKey: weekKey,
                )) {
                  continue;
                }
                final supportStart = _resolveDraftRepairSupportTaskStartDate(
                  weekStart: weekStart,
                  phaseStart: phaseWindow.startDate,
                  phaseEnd: phaseWindow.endDate,
                );
                if (supportStart == null) {
                  continue;
                }
                final resolvedRole = _resolveBestRoleForTaskTitle(
                  taskTitle: template.title,
                  selectedRoleKeys: selectedRoleKeys,
                  focusedStaffIdsByRole: focusedStaffIdsByRole,
                );
                final requiredHeadcount = _resolveDraftRepairHeadcountForRole(
                  roleKey: resolvedRole,
                );
                final assignedStaffProfileIds =
                    _resolveDraftRepairAssignedStaffIds(
                      roleKey: resolvedRole,
                      requiredHeadcount: requiredHeadcount,
                      focusedStaffIdsByRole: focusedStaffIdsByRole,
                    );
                tasks.add(
                  ProductionAssistantPlanTask(
                    title: template.title,
                    roleRequired: resolvedRole,
                    requiredHeadcount: requiredHeadcount,
                    weight: 1,
                    instructions: template.instructions,
                    taskType: "event",
                    sourceTemplateKey:
                        "draft_repair_${cropKey}_${phaseKey}_${weekKey}_$templateCursor",
                    recurrenceGroupKey:
                        "draft_repair_${cropKey}_${phaseKey}_cadence",
                    occurrenceIndex: weekIndex + 1,
                    startDate: supportStart,
                    dueDate: DateTime(
                      supportStart.year,
                      supportStart.month,
                      supportStart.day,
                      16,
                      0,
                    ),
                    assignedStaffProfileIds: assignedStaffProfileIds,
                  ),
                );
                insertedSupportTaskCount += 1;
              }
              _sortDraftRepairTasks(tasks);
              return ProductionAssistantPlanPhase(
                name: phase.name,
                order: phase.order,
                estimatedDays: phase.estimatedDays,
                phaseType: phase.phaseType,
                requiredUnits: phase.requiredUnits,
                minRatePerFarmerHour: phase.minRatePerFarmerHour,
                targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
                plannedHoursPerDay: phase.plannedHoursPerDay,
                biologicalMinDays: phase.biologicalMinDays,
                tasks: tasks,
              );
            })
            .toList(growable: false);
        repairedPayload = ProductionAssistantPlanDraftPayload(
          productId: repairedPayload.productId,
          productName: repairedPayload.productName,
          startDate: repairedPayload.startDate,
          endDate: repairedPayload.endDate,
          days: repairedPayload.days,
          weeks: repairedPayload.weeks,
          phases: injectedPhases,
          warnings: repairedPayload.warnings,
          plannerMeta: repairedPayload.plannerMeta,
          lifecycle: repairedPayload.lifecycle,
        );
      }
    }

    final densityBeforeStretch = _analyzeDraftScheduleDensity(
      payload: repairedPayload,
    );
    if (densityBeforeStretch.fieldSparseWeekKeys.isNotEmpty) {
      final phaseWindows = _buildDraftPhaseWindows(payload: repairedPayload);
      final phaseWindowByIndex = <int, _DraftPhaseWindow>{
        for (final window in phaseWindows) window.phaseIndex: window,
      };
      final stretchedWeekKeys = <String>{};
      final stretchedPhases = repairedPayload.phases
          .asMap()
          .entries
          .map((entry) {
            final phase = entry.value;
            final phaseWindow = phaseWindowByIndex[entry.key];
            if (phaseWindow == null) {
              return phase;
            }
            final tasks = phase.tasks
                .map((task) {
                  if (task.startDate == null ||
                      task.dueDate == null ||
                      _isManagementOversightTask(task) ||
                      !_isPlotExecutionRoleForPreview(task.roleRequired)) {
                    return task;
                  }
                  final weekKey = _draftRepairWeekKeyForTask(task);
                  if (weekKey.isEmpty ||
                      stretchedWeekKeys.contains(weekKey) ||
                      !densityBeforeStretch.fieldSparseWeekKeys.contains(
                        weekKey,
                      )) {
                    return task;
                  }
                  final extendedDue = _extendDraftRepairDueDateWithinWeek(
                    task: task,
                    phaseWindowEnd: phaseWindow.endDate,
                  );
                  if (extendedDue == null ||
                      !extendedDue.isAfter(task.dueDate!)) {
                    return task;
                  }
                  stretchedWeekKeys.add(weekKey);
                  stretchedTaskWindowCount += 1;
                  return ProductionAssistantPlanTask(
                    title: task.title,
                    roleRequired: task.roleRequired,
                    requiredHeadcount: task.requiredHeadcount,
                    weight: task.weight,
                    instructions: task.instructions,
                    taskType: task.taskType,
                    sourceTemplateKey: task.sourceTemplateKey,
                    recurrenceGroupKey: task.recurrenceGroupKey,
                    occurrenceIndex: task.occurrenceIndex,
                    startDate: task.startDate,
                    dueDate: extendedDue,
                    assignedStaffProfileIds: task.assignedStaffProfileIds,
                  );
                })
                .toList(growable: false);
            _sortDraftRepairTasks(tasks);
            return ProductionAssistantPlanPhase(
              name: phase.name,
              order: phase.order,
              estimatedDays: phase.estimatedDays,
              phaseType: phase.phaseType,
              requiredUnits: phase.requiredUnits,
              minRatePerFarmerHour: phase.minRatePerFarmerHour,
              targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
              plannedHoursPerDay: phase.plannedHoursPerDay,
              biologicalMinDays: phase.biologicalMinDays,
              tasks: tasks,
            );
          })
          .toList(growable: false);
      repairedPayload = ProductionAssistantPlanDraftPayload(
        productId: repairedPayload.productId,
        productName: repairedPayload.productName,
        startDate: repairedPayload.startDate,
        endDate: repairedPayload.endDate,
        days: repairedPayload.days,
        weeks: repairedPayload.weeks,
        phases: stretchedPhases,
        warnings: repairedPayload.warnings,
        plannerMeta: repairedPayload.plannerMeta,
        lifecycle: repairedPayload.lifecycle,
      );
    }

    final afterDensity = _analyzeDraftScheduleDensity(payload: repairedPayload);
    final densifiedWeekCount =
        beforeDensity.underfilledWeekCount > afterDensity.underfilledWeekCount
        ? beforeDensity.underfilledWeekCount - afterDensity.underfilledWeekCount
        : 0;
    return _DraftCalendarRepairResult(
      payload: repairedPayload,
      insertedSupportTaskCount: insertedSupportTaskCount,
      stretchedTaskWindowCount: stretchedTaskWindowCount,
      densifiedWeekCount: densifiedWeekCount,
    );
  }

  bool _canInjectCropSpecificSupportTasks({
    required String cropKey,
    required String phaseKey,
    required bool allowCropSpecificTemplates,
  }) {
    if (!allowCropSpecificTemplates || cropKey.trim().isEmpty) {
      return false;
    }
    if (_draftRepairIsTransplantFruitingCrop(cropKey) ||
        _draftRepairIsLegumeCrop(cropKey) ||
        _draftRepairIsGrainCrop(cropKey) ||
        _draftRepairIsDirectFruitingCrop(cropKey)) {
      return phaseKey == "vegetative_growth" ||
          phaseKey == "fruit_set" ||
          phaseKey == "harvest";
    }
    switch (cropKey) {
      case "cassava":
        return phaseKey == "vegetative_growth" ||
            phaseKey == "root_initiation" ||
            phaseKey == "root_bulking" ||
            phaseKey == "harvest";
      default:
        return false;
    }
  }

  List<_DraftRecurringRepairTemplate>
  _resolveTransplantFruitingRecurringRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "nursery":
        return [
          _DraftRecurringRepairTemplate(
            title: "Sow $cropName seeds in trays and record nursery targets",
            instructions: _buildDraftRepairNurserySowingInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 21,
            preferredWeekday: DateTime.monday,
            startHour: 8,
            durationHours: 3,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Check $cropName nursery moisture and irrigation flow",
            instructions:
                "Inspect trays or seedbed moisture every two days, correct irrigation drift early, and keep seedlings on a stable watering rhythm.",
            cadenceDays: 2,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Count $cropName germination and viable nursery trays",
            instructions: _buildDraftRepairGerminationCountInstruction(
              cropName: cropName,
            ),
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Inspect $cropName nursery media pH and tray health",
            instructions:
                "Review nursery pH, tray condition, and early stress signs weekly so seedlings stay uniform ahead of transplanting.",
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
        ];
      case "transplant_establishment":
      case "establishment":
        return [
          _DraftRecurringRepairTemplate(
            title: "Transplant $cropName seedlings and record planted stands",
            instructions: _buildDraftRepairTransplantInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 21,
            preferredWeekday: DateTime.monday,
            startHour: 8,
            durationHours: 4,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Check $cropName transplant moisture and irrigation lines",
            instructions:
                "Review transplant moisture every two days, check irrigation delivery, and correct avoidable water stress before stand loss grows.",
            cadenceDays: 2,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title:
                "Scout $cropName stand establishment and replace weak plants",
            instructions:
                "Inspect the stand weekly, replace weak or missing plants quickly, and keep establishment uniform.",
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 9,
            durationHours: 3,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Count established $cropName plants and update yield basis",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 11,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "vegetative_growth":
        return [
          _DraftRecurringRepairTemplate(
            title: "Check $cropName irrigation and soil moisture",
            instructions:
                "Review irrigation delivery and soil moisture every two days so plants do not drift into avoidable stress.",
            cadenceDays: 2,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Weed $cropName beds and maintain mulch cover",
            instructions:
                "Run a weekly weeding pass, keep beds accessible, and maintain mulch or soil cover where the field requires it.",
            cadenceDays: 7,
            preferredWeekday: DateTime.wednesday,
            startHour: 8,
            durationHours: 3,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Scout $cropName field for pests and disease",
            instructions:
                "Inspect leaves, stems, and canopy condition weekly so pest and disease problems are escalated before they hurt flowering.",
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName plants and update yield basis",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "fruit_set":
        return [
          _DraftRecurringRepairTemplate(
            title: "Check $cropName irrigation and fruit-set moisture balance",
            instructions:
                "Inspect irrigation and field moisture every two days to protect flowering, fruit retention, and early fruit development.",
            cadenceDays: 2,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Inspect $cropName nutrient and pH stability",
            instructions:
                "Run a weekly nutrient and pH review so fruit-set decline is caught early and corrective action can be scheduled.",
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Scout $cropName flowers and fruit set",
            instructions:
                "Inspect flowers, fruit set, and pest pressure weekly so poor fruit retention is escalated before harvest windows slip.",
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName plants and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      default:
        return const <_DraftRecurringRepairTemplate>[];
    }
  }

  List<_DraftRecurringRepairTemplate> _resolveLegumeRecurringRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "establishment":
      case "transplant_establishment":
        return [
          _DraftRecurringRepairTemplate(
            title: "Plant $cropName seed and record seed count by plot",
            instructions: _buildDraftRepairDirectSeedInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 21,
            preferredWeekday: DateTime.monday,
            startHour: 8,
            durationHours: 4,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Inspect $cropName stand emergence and field moisture",
            instructions:
                "Review emergence and field moisture each week, close stand gaps early, and flag sections drifting off target.",
            cadenceDays: 7,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Count emerged $cropName stands and close gaps",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "vegetative_growth":
        return [
          _DraftRecurringRepairTemplate(
            title: "Weed $cropName rows and maintain access paths",
            instructions:
                "Run a weekly weeding pass to keep rows clear and prevent avoidable competition during canopy growth.",
            cadenceDays: 7,
            preferredWeekday: DateTime.wednesday,
            startHour: 8,
            durationHours: 3,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title:
                "Scout $cropName field for pests, disease, and nutrient stress",
            instructions:
                "Inspect leaves and stems weekly, then flag hotspots before stress spreads across the field.",
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "fruit_set":
        return [
          _DraftRecurringRepairTemplate(
            title:
                "Scout $cropName field for pests, disease, and nutrient stress",
            instructions:
                "Inspect flowering and pod-setting sections weekly so pressure points are contained before yield drops.",
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Check $cropName field moisture and pH trend",
            instructions:
                "Review moisture and pH conditions weekly so reproductive-stage stress is caught early and support work can be scheduled.",
            cadenceDays: 7,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      default:
        return const <_DraftRecurringRepairTemplate>[];
    }
  }

  List<_DraftRecurringRepairTemplate> _resolveGrainRecurringRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "nursery":
        return [
          _DraftRecurringRepairTemplate(
            title: "Sow $cropName nursery seedbeds and record seed targets",
            instructions: _buildDraftRepairNurserySowingInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 21,
            preferredWeekday: DateTime.monday,
            startHour: 8,
            durationHours: 3,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Count $cropName germination and viable nursery sections",
            instructions: _buildDraftRepairGerminationCountInstruction(
              cropName: cropName,
            ),
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "establishment":
      case "transplant_establishment":
        return [
          _DraftRecurringRepairTemplate(
            title: "Plant $cropName seed and record seed count by plot",
            instructions: _buildDraftRepairDirectSeedInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 21,
            preferredWeekday: DateTime.monday,
            startHour: 8,
            durationHours: 4,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Inspect $cropName emergence and field moisture",
            instructions:
                "Review emergence and field moisture weekly, then close stand gaps before canopy development drifts off target.",
            cadenceDays: 7,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Count emerged $cropName stands and close gaps",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "vegetative_growth":
        return [
          _DraftRecurringRepairTemplate(
            title: "Check $cropName field moisture and nutrient balance",
            instructions:
                "Review moisture and nutrient balance every few days so the crop does not drift into avoidable vegetative stress.",
            cadenceDays: 3,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Weed $cropName rows and maintain access paths",
            instructions:
                "Remove weed pressure, keep movement paths open, and reduce competition during active canopy growth.",
            cadenceDays: 7,
            preferredWeekday: DateTime.wednesday,
            startHour: 8,
            durationHours: 3,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Scout $cropName field for pests and disease pressure",
            instructions:
                "Inspect leaves and stems weekly, then flag hotspots before pressure spreads across the block.",
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "fruit_set":
        return [
          _DraftRecurringRepairTemplate(
            title: "Scout $cropName flowering and grain set",
            instructions:
                "Inspect flowering or heading blocks weekly so pressure points are contained before yield drops.",
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Check $cropName field moisture and nutrient balance",
            instructions:
                "Review moisture and nutrient balance weekly so reproductive-stage stress is caught early and support work can be scheduled.",
            cadenceDays: 7,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      default:
        return const <_DraftRecurringRepairTemplate>[];
    }
  }

  List<_DraftRecurringRepairTemplate>
  _resolveDirectFruitingRecurringRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "establishment":
      case "transplant_establishment":
        return [
          _DraftRecurringRepairTemplate(
            title: "Plant $cropName seed and record seed count by plot",
            instructions: _buildDraftRepairDirectSeedInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 21,
            preferredWeekday: DateTime.monday,
            startHour: 8,
            durationHours: 4,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Inspect $cropName emergence and field moisture",
            instructions:
                "Review emergence and field moisture weekly, then close stand gaps before canopy development drifts off target.",
            cadenceDays: 7,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Count emerged $cropName stands and close gaps",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "vegetative_growth":
        return [
          _DraftRecurringRepairTemplate(
            title: "Check $cropName irrigation and soil moisture",
            instructions:
                "Review field moisture every few days so the crop does not drift into avoidable stress during active canopy growth.",
            cadenceDays: 3,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Weed $cropName beds and maintain access paths",
            instructions:
                "Remove weed pressure, keep movement paths open, and reduce competition during active vegetative growth.",
            cadenceDays: 7,
            preferredWeekday: DateTime.wednesday,
            startHour: 8,
            durationHours: 3,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Scout $cropName field for pests and disease",
            instructions:
                "Inspect leaves, stems, and canopy condition weekly so pest and disease problems are escalated before flowering shifts.",
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      case "fruit_set":
        return [
          _DraftRecurringRepairTemplate(
            title: "Check $cropName irrigation and fruit-set moisture balance",
            instructions:
                "Inspect irrigation and field moisture every few days to protect flowering, fruit set, and early fill.",
            cadenceDays: 3,
            preferredWeekday: DateTime.tuesday,
            startHour: 8,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
          _DraftRecurringRepairTemplate(
            title: "Inspect $cropName nutrient and pH stability",
            instructions:
                "Run a weekly nutrient and pH review so fruit-set decline is caught early and corrective action can be scheduled.",
            cadenceDays: 7,
            preferredWeekday: DateTime.thursday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Scout $cropName flowers and fruit set",
            instructions:
                "Inspect flowers, fruit set, and pest pressure weekly so poor fruit retention is escalated before harvest windows slip.",
            cadenceDays: 7,
            preferredWeekday: DateTime.friday,
            startHour: 10,
            durationHours: 2,
            preferredRole: staffRoleFieldAgent,
          ),
          _DraftRecurringRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
            cadenceDays: 14,
            preferredWeekday: DateTime.monday,
            startHour: 9,
            durationHours: 2,
            preferredRole: staffRoleFarmer,
          ),
        ];
      default:
        return const <_DraftRecurringRepairTemplate>[];
    }
  }

  List<_DraftRecurringRepairTemplate> _resolveDraftRecurringRepairTemplates({
    required String cropKey,
    required String cropName,
    required String phaseKey,
    required bool allowCropSpecificTemplates,
  }) {
    if (!allowCropSpecificTemplates || cropKey.trim().isEmpty) {
      return const <_DraftRecurringRepairTemplate>[];
    }
    if (_draftRepairIsTransplantFruitingCrop(cropKey)) {
      return _resolveTransplantFruitingRecurringRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    if (_draftRepairIsLegumeCrop(cropKey)) {
      return _resolveLegumeRecurringRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    if (_draftRepairIsGrainCrop(cropKey)) {
      return _resolveGrainRecurringRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    if (_draftRepairIsDirectFruitingCrop(cropKey)) {
      return _resolveDirectFruitingRecurringRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    switch (cropKey) {
      case "cassava":
        switch (phaseKey) {
          case "vegetative_growth":
            return const [
              _DraftRecurringRepairTemplate(
                title: "Weed cassava rows and clean inter-row paths",
                instructions:
                    "Run a recurring weeding pass, keep cassava rows open, and clear weed pressure before it slows canopy development.",
                cadenceDays: 7,
                preferredWeekday: DateTime.wednesday,
                startHour: 8,
                durationHours: 4,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Scout cassava field for pest and disease pressure",
                instructions:
                    "Inspect leaves, stems, and stand vigor, then flag pest or disease hotspots before they spread across the block.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
            ];
          case "root_initiation":
            return const [
              _DraftRecurringRepairTemplate(
                title: "Check cassava soil moisture and pH trend",
                instructions:
                    "Review soil moisture and pH conditions, note stressed sections early, and escalate nutrient or drainage issues before bulking slows.",
                cadenceDays: 14,
                preferredWeekday: DateTime.tuesday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title: "Scout cassava field for pest and disease pressure",
                instructions:
                    "Inspect stand vigor, leaves, and stems each week so pest and disease problems are contained before they affect root development.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
            ];
          case "root_bulking":
            return const [
              _DraftRecurringRepairTemplate(
                title: "Monitor cassava root bulking and moisture stress",
                instructions:
                    "Review field moisture, plant condition, and bulking risk signals each week so yield loss is caught before harvest planning.",
                cadenceDays: 7,
                preferredWeekday: DateTime.wednesday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title: "Keep cassava bulking rows weed-free",
                instructions:
                    "Carry out late-season weed control to protect bulking roots and keep harvest access paths clean.",
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 3,
                preferredRole: staffRoleFarmer,
              ),
            ];
        }
        break;
      case "pepper":
        switch (phaseKey) {
          case "nursery":
            return [
              _DraftRecurringRepairTemplate(
                title:
                    "Sow $cropName seeds in trays and record nursery targets",
                instructions: _buildDraftRepairNurserySowingInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 21,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 3,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Check bell pepper nursery moisture and irrigation flow",
                instructions:
                    "Inspect trays or seedbed moisture every two days, correct irrigation drift early, and keep seedlings on a stable watering rhythm.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Count bell pepper germination and viable nursery trays",
                instructions: _buildDraftRepairGerminationCountInstruction(
                  cropName: cropName,
                ),
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Inspect bell pepper nursery media pH and tray health",
                instructions:
                    "Review nursery pH, tray condition, and early stress signs weekly so seedlings stay uniform ahead of transplanting.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
            ];
          case "transplant_establishment":
          case "establishment":
            return [
              _DraftRecurringRepairTemplate(
                title:
                    "Transplant $cropName seedlings and record planted stands",
                instructions: _buildDraftRepairTransplantInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 21,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 4,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Check bell pepper transplant moisture and irrigation lines",
                instructions:
                    "Review transplant moisture every two days, check irrigation delivery, and correct avoidable water stress before stand loss grows.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Scout bell pepper stand establishment and replace weak plants",
                instructions:
                    "Inspect the stand weekly, replace weak or missing plants quickly, and keep transplant establishment uniform.",
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 9,
                durationHours: 3,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Count established $cropName plants and update yield basis",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                    includeGapClosure: true,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 11,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "vegetative_growth":
            return [
              _DraftRecurringRepairTemplate(
                title: "Check bell pepper irrigation and soil moisture",
                instructions:
                    "Review irrigation delivery and soil moisture every two days so bell pepper plants do not drift into avoidable stress.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Weed bell pepper beds and maintain mulch cover",
                instructions:
                    "Run a weekly weeding pass, keep beds accessible, and maintain mulch or soil cover where the field requires it.",
                cadenceDays: 7,
                preferredWeekday: DateTime.wednesday,
                startHour: 8,
                durationHours: 3,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Scout bell pepper field for pests and disease",
                instructions:
                    "Inspect leaves, stems, and canopy condition weekly so pest and disease problems are escalated before they hurt flowering.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName plants and update yield basis",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "fruit_set":
            return [
              _DraftRecurringRepairTemplate(
                title:
                    "Check bell pepper irrigation and fruit-set moisture balance",
                instructions:
                    "Inspect irrigation and field moisture every two days to protect flower retention and early fruit development.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Inspect bell pepper nutrient and pH stability",
                instructions:
                    "Run a weekly nutrient and pH review so fruit-set decline is caught early and corrective action can be scheduled.",
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title: "Scout bell pepper flowers and fruit set",
                instructions:
                    "Inspect flowers, fruit set, and pest pressure weekly so poor fruit retention is escalated before harvest windows slip.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName plants and update yield basis",
                instructions: _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
        }
        break;
      case "tomato":
        switch (phaseKey) {
          case "nursery":
            return [
              _DraftRecurringRepairTemplate(
                title:
                    "Sow $cropName seeds in trays and record nursery targets",
                instructions: _buildDraftRepairNurserySowingInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 21,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 3,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Check tomato nursery moisture and irrigation flow",
                instructions:
                    "Inspect trays or seedbed moisture every two days, correct irrigation drift early, and keep seedlings on a stable watering rhythm.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Count tomato germination and viable nursery trays",
                instructions: _buildDraftRepairGerminationCountInstruction(
                  cropName: cropName,
                ),
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Inspect tomato nursery media pH and tray health",
                instructions:
                    "Review nursery pH, tray condition, and early stress signs weekly so seedlings stay uniform ahead of transplanting.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
            ];
          case "transplant_establishment":
          case "establishment":
            return [
              _DraftRecurringRepairTemplate(
                title:
                    "Transplant $cropName seedlings and record planted stands",
                instructions: _buildDraftRepairTransplantInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 21,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 4,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Check tomato transplant moisture and irrigation lines",
                instructions:
                    "Review transplant moisture every two days, check irrigation delivery, and correct avoidable water stress before stand loss grows.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Scout tomato stand establishment and replace weak plants",
                instructions:
                    "Inspect the stand weekly, replace weak or missing plants quickly, and keep transplant establishment uniform.",
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 9,
                durationHours: 3,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Count established $cropName plants and update yield basis",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                    includeGapClosure: true,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 11,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "vegetative_growth":
            return [
              _DraftRecurringRepairTemplate(
                title: "Check tomato irrigation and soil moisture",
                instructions:
                    "Review irrigation delivery and soil moisture every two days so tomato plants do not drift into avoidable stress.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Weed tomato beds and maintain mulch cover",
                instructions:
                    "Run a weekly weeding pass, keep beds accessible, and maintain mulch or soil cover where the field requires it.",
                cadenceDays: 7,
                preferredWeekday: DateTime.wednesday,
                startHour: 8,
                durationHours: 3,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Scout tomato field for pests and disease",
                instructions:
                    "Inspect leaves, stems, and canopy condition weekly so pest and disease problems are escalated before they hurt flowering.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName plants and update yield basis",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "fruit_set":
            return [
              _DraftRecurringRepairTemplate(
                title: "Check tomato irrigation and fruit-set moisture balance",
                instructions:
                    "Inspect irrigation and field moisture every two days to protect flower retention and early fruit development.",
                cadenceDays: 2,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Inspect tomato nutrient and pH stability",
                instructions:
                    "Run a weekly nutrient and pH review so fruit-set decline is caught early and corrective action can be scheduled.",
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title: "Scout tomato flowers and fruit set",
                instructions:
                    "Inspect flowers, fruit set, and pest pressure weekly so poor fruit retention is escalated before harvest windows slip.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName plants and update yield basis",
                instructions: _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
        }
        break;
      case "beans":
        switch (phaseKey) {
          case "establishment":
          case "transplant_establishment":
            return [
              _DraftRecurringRepairTemplate(
                title: "Plant $cropName seed and record seed count by plot",
                instructions: _buildDraftRepairDirectSeedInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 21,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 4,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Inspect bean stand emergence and field moisture",
                instructions:
                    "Review emergence and field moisture each week, close stand gaps early, and flag sections drifting off target.",
                cadenceDays: 7,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title: "Count emerged $cropName stands and close gaps",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                    includeGapClosure: true,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "vegetative_growth":
            return [
              _DraftRecurringRepairTemplate(
                title: "Weed bean rows and maintain access paths",
                instructions:
                    "Run a weekly weeding pass to keep bean rows clear and prevent avoidable competition during canopy growth.",
                cadenceDays: 7,
                preferredWeekday: DateTime.wednesday,
                startHour: 8,
                durationHours: 3,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Scout bean field for pests, disease, and nutrient stress",
                instructions:
                    "Inspect leaves and stems weekly, then flag hotspots before stress spreads across the field.",
                cadenceDays: 7,
                preferredWeekday: DateTime.friday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName stands and update yield basis",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "fruit_set":
            return [
              _DraftRecurringRepairTemplate(
                title:
                    "Scout bean field for pests, disease, and nutrient stress",
                instructions:
                    "Inspect flowering and pod-setting sections weekly so pressure points are contained before yield drops.",
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title: "Check bean field moisture and pH trend",
                instructions:
                    "Review moisture and pH conditions weekly so fruit-set stress is caught early and support work can be scheduled.",
                cadenceDays: 7,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName stands and update yield basis",
                instructions: _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
        }
        break;
      case "rice":
        switch (phaseKey) {
          case "nursery":
            return [
              _DraftRecurringRepairTemplate(
                title: "Sow $cropName seedbeds and record nursery seed targets",
                instructions: _buildDraftRepairNurserySowingInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 21,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 3,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Count rice germination and viable nursery sections",
                instructions: _buildDraftRepairGerminationCountInstruction(
                  cropName: cropName,
                ),
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "establishment":
          case "transplant_establishment":
            return [
              _DraftRecurringRepairTemplate(
                title: "Plant $cropName seed and record seed count by plot",
                instructions: _buildDraftRepairDirectSeedInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 21,
                preferredWeekday: DateTime.monday,
                startHour: 8,
                durationHours: 4,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title: "Count emerged $cropName stands and close gaps",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                    includeGapClosure: true,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "vegetative_growth":
            return [
              _DraftRecurringRepairTemplate(
                title: "Check rice field water balance and soil condition",
                instructions:
                    "Review water balance and field condition every few days so rice plants do not drift into avoidable stress.",
                cadenceDays: 3,
                preferredWeekday: DateTime.tuesday,
                startHour: 8,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName stands and update yield basis",
                instructions: [
                  _buildDraftRepairEstablishedStandInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                  _buildDraftRepairYieldBasisInstruction(
                    cropName: cropName,
                    cropKey: cropKey,
                  ),
                ].join(" "),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
          case "fruit_set":
            return [
              _DraftRecurringRepairTemplate(
                title: "Scout rice crop pressure and heading progress",
                instructions:
                    "Inspect the field weekly, note pressure points early, and track any development risk that could reduce expected harvest.",
                cadenceDays: 7,
                preferredWeekday: DateTime.thursday,
                startHour: 10,
                durationHours: 2,
                preferredRole: staffRoleFieldAgent,
              ),
              _DraftRecurringRepairTemplate(
                title:
                    "Review established $cropName stands and update yield basis",
                instructions: _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
                cadenceDays: 14,
                preferredWeekday: DateTime.monday,
                startHour: 9,
                durationHours: 2,
                preferredRole: staffRoleFarmer,
              ),
            ];
        }
        break;
    }
    return const <_DraftRecurringRepairTemplate>[];
  }

  Map<String, int> _buildDraftRepairWeekDensityForPhase({
    required _DraftScheduleDensityInfo density,
    required DateTime phaseStart,
    required DateTime phaseEnd,
  }) {
    final counts = <String, int>{};
    for (final weekKey in _buildDraftRepairWeekKeysForRange(
      startDate: phaseStart,
      endDate: phaseEnd,
    )) {
      counts[weekKey] = density.scheduledDayCountByWeekKey[weekKey] ?? 0;
    }
    return counts;
  }

  bool _shouldApplyDraftRecurringRepair({
    required Map<String, int> phaseDensity,
    required DateTime phaseStart,
    required DateTime phaseEnd,
  }) {
    if (phaseDensity.isEmpty) {
      return false;
    }
    final underfilledWeeks = phaseDensity.values.where((count) => count <= 2);
    if (underfilledWeeks.isNotEmpty) {
      return true;
    }
    final totalDays = _normalizeDraftRepairDate(
      phaseEnd,
    ).difference(_normalizeDraftRepairDate(phaseStart)).inDays;
    return totalDays >= 10;
  }

  List<DateTime> _buildDraftRepairRecurringDates({
    required DateTime phaseStart,
    required DateTime phaseEnd,
    required int cadenceDays,
    required int preferredWeekday,
  }) {
    if (cadenceDays < 1) {
      return const <DateTime>[];
    }
    final safePhaseStart = _normalizeDraftRepairDate(phaseStart);
    final safePhaseEnd = _normalizeDraftRepairDate(phaseEnd);
    if (safePhaseEnd.isBefore(safePhaseStart)) {
      return const <DateTime>[];
    }

    DateTime alignStart(DateTime start) {
      var candidate = start;
      if (candidate.weekday > DateTime.friday) {
        candidate = candidate.add(
          Duration(days: DateTime.monday + 7 - candidate.weekday),
        );
      }
      if (preferredWeekday >= DateTime.monday &&
          preferredWeekday <= DateTime.friday &&
          cadenceDays >= 7) {
        final daysUntilPreferred =
            (preferredWeekday - candidate.weekday + 7) % 7;
        candidate = candidate.add(Duration(days: daysUntilPreferred));
      }
      return candidate;
    }

    final baseStart = alignStart(safePhaseStart);
    final dates = <DateTime>[];
    final seenKeys = <String>{};
    var index = 0;
    while (true) {
      final rawDate = baseStart.add(Duration(days: cadenceDays * index));
      if (rawDate.isAfter(safePhaseEnd)) {
        break;
      }
      var candidate = rawDate;
      if (candidate.weekday > DateTime.friday) {
        candidate = candidate.add(
          Duration(days: DateTime.monday + 7 - candidate.weekday),
        );
      }
      if (!candidate.isBefore(safePhaseStart) &&
          !candidate.isAfter(safePhaseEnd)) {
        final key = formatDateInput(candidate);
        if (!seenKeys.contains(key)) {
          dates.add(candidate);
          seenKeys.add(key);
        }
      }
      index += 1;
    }
    return dates;
  }

  int _resolveDraftRepairDuplicateToleranceDays({required int cadenceDays}) {
    if (cadenceDays <= 2) {
      return 1;
    }
    if (cadenceDays <= 7) {
      return 3;
    }
    return 6;
  }

  bool _hasSimilarDraftTaskNearDate({
    required List<ProductionAssistantPlanTask> tasks,
    required String title,
    required DateTime targetDate,
    required int toleranceDays,
  }) {
    final normalizedTitle = _normalizeDraftRepairKey(
      _normalizeLifecycleTaskTitle(title),
    );
    if (normalizedTitle.isEmpty) {
      return false;
    }
    final safeTarget = _normalizeDraftRepairDate(targetDate);
    for (final task in tasks) {
      if (task.startDate == null) {
        continue;
      }
      final taskTitle = _normalizeDraftRepairKey(
        _normalizeLifecycleTaskTitle(task.title),
      );
      if (taskTitle != normalizedTitle) {
        continue;
      }
      final safeTaskDate = _normalizeDraftRepairDate(task.startDate!);
      final dayGap = safeTaskDate.difference(safeTarget).inDays.abs();
      if (dayGap <= toleranceDays) {
        return true;
      }
    }
    return false;
  }

  String _resolveDraftRepairRoleForRecurringTask({
    required _DraftRecurringRepairTemplate template,
    required List<String> selectedRoleKeys,
    required Map<String, List<String>> focusedStaffIdsByRole,
  }) {
    final normalizedPreferredRole = _normalizeRoleKey(template.preferredRole);
    final normalizedSelectedRoles = selectedRoleKeys
        .map(_normalizeRoleKey)
        .where((role) => role.isNotEmpty)
        .toSet();
    if (normalizedPreferredRole.isNotEmpty &&
        normalizedSelectedRoles.contains(normalizedPreferredRole)) {
      return normalizedPreferredRole;
    }
    return _resolveBestRoleForTaskTitle(
      taskTitle: template.title,
      selectedRoleKeys: selectedRoleKeys,
      focusedStaffIdsByRole: focusedStaffIdsByRole,
    );
  }

  int _resolveDraftRepairCadenceDays({required String phaseKey}) {
    switch (phaseKey) {
      case "nursery":
      case "harvest":
        return 7;
      case "vegetative_growth":
      case "root_initiation":
      case "fruit_set":
        return 14;
      case "root_bulking":
        return 21;
      default:
        return 0;
    }
  }

  List<String> _buildDraftRepairWeekKeysForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final weekKeys = <String>[];
    var cursor = _startOfWeekMonday(startDate);
    final finalWeek = _startOfWeekMonday(endDate);
    while (!cursor.isAfter(finalWeek)) {
      weekKeys.add(formatDateInput(cursor));
      cursor = cursor.add(const Duration(days: 7));
    }
    return weekKeys;
  }

  DateTime? _resolveDraftRepairSupportTaskStartDate({
    required DateTime weekStart,
    required DateTime phaseStart,
    required DateTime phaseEnd,
  }) {
    final safePhaseStart = _normalizeDraftRepairDate(phaseStart);
    final safePhaseEnd = _normalizeDraftRepairDate(phaseEnd);
    const preferredOffsets = <int>[2, 3, 1, 4, 0];
    for (final offset in preferredOffsets) {
      final candidateDate = weekStart.add(Duration(days: offset));
      final safeCandidate = _normalizeDraftRepairDate(candidateDate);
      if (safeCandidate.isBefore(safePhaseStart) ||
          safeCandidate.isAfter(safePhaseEnd) ||
          safeCandidate.weekday > DateTime.friday) {
        continue;
      }
      return DateTime(
        safeCandidate.year,
        safeCandidate.month,
        safeCandidate.day,
        8,
        0,
      );
    }
    return null;
  }

  int _resolveDraftRepairHeadcountForRole({required String roleKey}) {
    final normalizedRole = _normalizeRoleKey(roleKey);
    if (normalizedRole == _normalizeRoleKey(staffRoleFarmer)) {
      return _resolveSafeMinStaffPerWorkUnit();
    }
    return 1;
  }

  List<String> _resolveDraftRepairAssignedStaffIds({
    required String roleKey,
    required int requiredHeadcount,
    required Map<String, List<String>> focusedStaffIdsByRole,
  }) {
    final normalizedRole = _normalizeRoleKey(roleKey);
    final pool = focusedStaffIdsByRole[normalizedRole] ?? const <String>[];
    final safeHeadcount = requiredHeadcount < 1 ? 1 : requiredHeadcount;
    if (pool.isEmpty) {
      return const <String>[];
    }
    return pool.take(safeHeadcount).toList(growable: false);
  }

  bool _hasSimilarDraftTaskInWeek({
    required List<ProductionAssistantPlanTask> tasks,
    required String title,
    required String weekKey,
  }) {
    final normalizedTitle = _normalizeDraftRepairKey(
      _normalizeLifecycleTaskTitle(title),
    );
    if (normalizedTitle.isEmpty || weekKey.trim().isEmpty) {
      return false;
    }
    for (final task in tasks) {
      if (_draftRepairWeekKeyForTask(task) != weekKey) {
        continue;
      }
      final taskTitle = _normalizeDraftRepairKey(
        _normalizeLifecycleTaskTitle(task.title),
      );
      if (taskTitle == normalizedTitle) {
        return true;
      }
    }
    return false;
  }

  void _sortDraftRepairTasks(List<ProductionAssistantPlanTask> tasks) {
    tasks.sort((left, right) {
      final leftStart = left.startDate?.millisecondsSinceEpoch ?? 0;
      final rightStart = right.startDate?.millisecondsSinceEpoch ?? 0;
      if (leftStart != rightStart) {
        return leftStart.compareTo(rightStart);
      }
      final leftDue = left.dueDate?.millisecondsSinceEpoch ?? 0;
      final rightDue = right.dueDate?.millisecondsSinceEpoch ?? 0;
      if (leftDue != rightDue) {
        return leftDue.compareTo(rightDue);
      }
      return left.title.compareTo(right.title);
    });
  }

  DateTime _normalizeDraftRepairDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  int _resolveDraftRepairTargetWorkdaySpan({
    required ProductionAssistantPlanTask task,
  }) {
    final normalizedTitle = _normalizeDraftRepairKey(
      _normalizeLifecycleTaskTitle(task.title),
    );
    if (normalizedTitle.contains("harvest") ||
        normalizedTitle.contains("plant") ||
        normalizedTitle.contains("transplant") ||
        normalizedTitle.contains("prepare") ||
        normalizedTitle.contains("weed") ||
        normalizedTitle.contains("fertilizer") ||
        normalizedTitle.contains("fertilise") ||
        normalizedTitle.contains("fertilize") ||
        normalizedTitle.contains("apply") ||
        normalizedTitle.contains("sort") ||
        normalizedTitle.contains("grade") ||
        normalizedTitle.contains("load") ||
        normalizedTitle.contains("pick")) {
      return 3;
    }
    if (normalizedTitle.contains("monitor") ||
        normalizedTitle.contains("inspect") ||
        normalizedTitle.contains("inspection") ||
        normalizedTitle.contains("scout") ||
        normalizedTitle.contains("survey") ||
        normalizedTitle.contains("field_check")) {
      return 2;
    }
    return _normalizeRoleKey(task.roleRequired) ==
            _normalizeRoleKey(staffRoleFarmer)
        ? 2
        : 1;
  }

  int _countDraftRepairWorkingDays({
    required DateTime startDate,
    required DateTime dueDate,
  }) {
    return _buildDraftRepairWorkingDays(
      startDate: startDate,
      endDate: dueDate,
    ).length;
  }

  List<DateTime> _buildDraftRepairWorkingDays({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final safeStart = _normalizeDraftRepairDate(startDate);
    final safeEnd = _normalizeDraftRepairDate(endDate);
    if (safeEnd.isBefore(safeStart)) {
      return <DateTime>[safeStart];
    }
    final days = <DateTime>[];
    var cursor = safeStart;
    while (!cursor.isAfter(safeEnd)) {
      if (cursor.weekday <= DateTime.friday) {
        days.add(cursor);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return days.isEmpty ? <DateTime>[safeStart] : days;
  }

  DateTime _endOfDraftRepairWorkWeek(DateTime value) {
    final weekStart = _startOfWeekMonday(value);
    return weekStart.add(const Duration(days: 4));
  }

  DateTime? _extendDraftRepairDueDateWithinWeek({
    required ProductionAssistantPlanTask task,
    required DateTime phaseWindowEnd,
  }) {
    final taskStart = task.startDate;
    final taskDue = task.dueDate;
    if (taskStart == null || taskDue == null) {
      return null;
    }
    final targetSpan = _resolveDraftRepairTargetWorkdaySpan(task: task);
    final currentSpan = _countDraftRepairWorkingDays(
      startDate: taskStart,
      dueDate: taskDue,
    );
    if (currentSpan >= targetSpan) {
      return null;
    }
    final safeStart = _normalizeDraftRepairDate(taskStart);
    final safePhaseEnd = _normalizeDraftRepairDate(phaseWindowEnd);
    final safeWeekEnd = _endOfDraftRepairWorkWeek(taskStart);
    final capDate = safePhaseEnd.isBefore(safeWeekEnd)
        ? safePhaseEnd
        : safeWeekEnd;
    if (capDate.isBefore(safeStart)) {
      return null;
    }
    final workingDays = _buildDraftRepairWorkingDays(
      startDate: safeStart,
      endDate: capDate,
    );
    final targetIndex = (targetSpan - 1).clamp(0, workingDays.length - 1);
    final targetDate = workingDays[targetIndex];
    final extendedDue = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      16,
      0,
    );
    return extendedDue.isAfter(taskDue) ? extendedDue : null;
  }

  ProductionPlanDraftState _buildStudioDraftStateFromImprovedPayload({
    required ProductionPlanDraftState currentDraft,
    required ProductionAssistantPlanDraftPayload currentPayload,
    required ProductionAssistantPlanDraftPayload improvedPayload,
  }) {
    final strictBuckets = <String, List<_DraftTaskStateSeed>>{};
    final dateBuckets = <String, List<_DraftTaskStateSeed>>{};
    final positionBuckets = <String, List<_DraftTaskStateSeed>>{};

    void addSeedBucket({
      required Map<String, List<_DraftTaskStateSeed>> buckets,
      required String key,
      required _DraftTaskStateSeed seed,
    }) {
      if (key.isEmpty) {
        return;
      }
      final bucket = buckets.putIfAbsent(key, () => <_DraftTaskStateSeed>[]);
      bucket.add(seed);
    }

    for (
      var phaseIndex = 0;
      phaseIndex < currentDraft.phases.length &&
          phaseIndex < currentPayload.phases.length;
      phaseIndex += 1
    ) {
      final draftPhase = currentDraft.phases[phaseIndex];
      final payloadPhase = currentPayload.phases[phaseIndex];
      for (
        var taskIndex = 0;
        taskIndex < draftPhase.tasks.length &&
            taskIndex < payloadPhase.tasks.length;
        taskIndex += 1
      ) {
        final draftTask = draftPhase.tasks[taskIndex];
        final payloadTask = payloadPhase.tasks[taskIndex];
        final seed = _DraftTaskStateSeed(task: draftTask);
        addSeedBucket(
          buckets: strictBuckets,
          key: _buildImprovedDraftStateStrictKey(
            phaseName: draftPhase.name,
            title: draftTask.title,
            roleRequired: draftTask.roleRequired,
          ),
          seed: seed,
        );
        addSeedBucket(
          buckets: dateBuckets,
          key: _buildImprovedDraftStateDateKey(
            startDate: payloadTask.startDate,
            dueDate: payloadTask.dueDate,
            roleRequired: payloadTask.roleRequired,
          ),
          seed: seed,
        );
        addSeedBucket(
          buckets: positionBuckets,
          key: "${payloadPhase.order}|$taskIndex",
          seed: seed,
        );
      }
    }

    _DraftTaskStateSeed? takeSeed({
      required ProductionAssistantPlanPhase phase,
      required ProductionAssistantPlanTask task,
      required int taskIndex,
    }) {
      final strictKey = _buildImprovedDraftStateStrictKey(
        phaseName: phase.name,
        title: task.title,
        roleRequired: task.roleRequired,
      );
      final strictBucket = strictBuckets[strictKey];
      if (strictBucket != null && strictBucket.isNotEmpty) {
        return strictBucket.removeAt(0);
      }
      final dateKey = _buildImprovedDraftStateDateKey(
        startDate: task.startDate,
        dueDate: task.dueDate,
        roleRequired: task.roleRequired,
      );
      final dateBucket = dateBuckets[dateKey];
      if (dateBucket != null && dateBucket.isNotEmpty) {
        return dateBucket.removeAt(0);
      }
      final positionBucket = positionBuckets["${phase.order}|$taskIndex"];
      if (positionBucket != null && positionBucket.isNotEmpty) {
        return positionBucket.removeAt(0);
      }
      return null;
    }

    final phases = improvedPayload.phases
        .map((phase) {
          final tasks = phase.tasks
              .asMap()
              .entries
              .map((entry) {
                final task = entry.value;
                final seed = takeSeed(
                  phase: phase,
                  task: task,
                  taskIndex: entry.key,
                );
                return ProductionTaskDraft(
                  id:
                      seed?.task.id ??
                      "assistant_${phase.order}_${entry.key}_${DateTime.now().millisecondsSinceEpoch}",
                  title: task.title.trim().isEmpty ? "Task" : task.title.trim(),
                  roleRequired: task.roleRequired.trim().isEmpty
                      ? "farmer"
                      : task.roleRequired.trim(),
                  assignedStaffId: task.assignedStaffProfileIds.isEmpty
                      ? null
                      : task.assignedStaffProfileIds.first,
                  assignedStaffProfileIds: task.assignedStaffProfileIds,
                  requiredHeadcount: task.requiredHeadcount < 1
                      ? 1
                      : task.requiredHeadcount,
                  weight: task.weight < 1 ? 1 : task.weight,
                  instructions: task.instructions.trim(),
                  taskType: task.taskType.trim(),
                  sourceTemplateKey: task.sourceTemplateKey.trim(),
                  recurrenceGroupKey: task.recurrenceGroupKey.trim(),
                  occurrenceIndex: task.occurrenceIndex,
                  status: seed?.task.status ?? ProductionTaskStatus.notStarted,
                  completedAt: seed?.task.completedAt,
                  completedByStaffId: seed?.task.completedByStaffId,
                );
              })
              .toList(growable: false);
          return ProductionPhaseDraft(
            name: phase.name.trim().isEmpty
                ? "Phase ${phase.order}"
                : phase.name,
            order: phase.order < 1 ? 1 : phase.order,
            estimatedDays: phase.estimatedDays < 1 ? 1 : phase.estimatedDays,
            phaseType: phase.phaseType,
            requiredUnits: phase.requiredUnits,
            minRatePerFarmerHour: phase.minRatePerFarmerHour,
            targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
            plannedHoursPerDay: phase.plannedHoursPerDay,
            biologicalMinDays: phase.biologicalMinDays,
            tasks: tasks,
          );
        })
        .toList(growable: false);
    final resolvedStartDate =
        DateTime.tryParse(improvedPayload.startDate) ?? currentDraft.startDate;
    final resolvedEndDate =
        DateTime.tryParse(improvedPayload.endDate) ?? currentDraft.endDate;
    final riskNotes = improvedPayload.warnings
        .map((warning) => warning.message.trim())
        .where((message) => message.isNotEmpty)
        .toList(growable: false);
    final resolvedTitle = currentDraft.title.trim().isNotEmpty
        ? currentDraft.title
        : "${improvedPayload.productName.isEmpty ? 'Production' : improvedPayload.productName} Plan";
    return ProductionPlanDraftState(
      title: resolvedTitle,
      notes: currentDraft.notes,
      domainContext: currentDraft.domainContext,
      estateAssetId: currentDraft.estateAssetId ?? _selectedEstateAssetId,
      productId: improvedPayload.productId.trim().isEmpty
          ? currentDraft.productId
          : improvedPayload.productId.trim(),
      startDate: resolvedStartDate,
      endDate: resolvedEndDate,
      proposedProduct: currentDraft.proposedProduct,
      productAiSuggested: currentDraft.productAiSuggested,
      startDateAiSuggested: currentDraft.startDateAiSuggested,
      endDateAiSuggested: currentDraft.endDateAiSuggested,
      aiGenerated: true,
      totalTasks: phases.fold<int>(0, (sum, phase) => sum + phase.tasks.length),
      totalEstimatedDays: improvedPayload.days > 0
          ? improvedPayload.days
          : currentDraft.totalEstimatedDays,
      riskNotes: riskNotes,
      phases: phases,
    );
  }

  String _buildImprovedDraftStateStrictKey({
    required String phaseName,
    required String title,
    required String roleRequired,
  }) {
    return "${_normalizeDraftRepairKey(phaseName)}|${_normalizeDraftRepairKey(title)}|${_normalizeRoleKey(roleRequired)}";
  }

  String _buildImprovedDraftStateDateKey({
    required DateTime? startDate,
    required DateTime? dueDate,
    required String roleRequired,
  }) {
    if (startDate == null || dueDate == null) {
      return "";
    }
    final safeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final safeEnd = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return "${formatDateInput(safeStart)}|${formatDateInput(safeEnd)}|${_normalizeRoleKey(roleRequired)}";
  }

  List<_DraftPhaseWindow> _buildDraftPhaseWindows({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    final startDate = DateTime.tryParse(payload.startDate);
    final endDate = DateTime.tryParse(payload.endDate);
    if (startDate == null || endDate == null || payload.phases.isEmpty) {
      return const <_DraftPhaseWindow>[];
    }
    final safeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final safeEnd = DateTime(endDate.year, endDate.month, endDate.day);
    if (safeEnd.isBefore(safeStart)) {
      return const <_DraftPhaseWindow>[];
    }
    final totalActualDays = safeEnd.difference(safeStart).inDays + 1;
    final totalEstimatedDays = payload.phases.fold<int>(
      0,
      (sum, phase) => sum + (phase.estimatedDays < 1 ? 1 : phase.estimatedDays),
    );
    var remainingActualDays = totalActualDays;
    var remainingEstimatedDays = totalEstimatedDays < 1
        ? payload.phases.length
        : totalEstimatedDays;
    var cursor = safeStart;
    final windows = <_DraftPhaseWindow>[];
    for (var index = 0; index < payload.phases.length; index += 1) {
      final phase = payload.phases[index];
      final isLastPhase = index == payload.phases.length - 1;
      int allocatedDays;
      if (isLastPhase) {
        allocatedDays = remainingActualDays < 1 ? 1 : remainingActualDays;
      } else {
        final safeEstimatedDays = phase.estimatedDays < 1
            ? 1
            : phase.estimatedDays;
        allocatedDays =
            ((remainingActualDays * safeEstimatedDays) / remainingEstimatedDays)
                .round();
        final remainingPhases = payload.phases.length - index - 1;
        final maxForPhase = remainingActualDays - remainingPhases;
        final safeMaxForPhase = maxForPhase < 1 ? 1 : maxForPhase;
        if (allocatedDays < 1) {
          allocatedDays = 1;
        }
        if (allocatedDays > safeMaxForPhase) {
          allocatedDays = safeMaxForPhase;
        }
      }
      final windowStart = cursor;
      final windowEnd = windowStart.add(Duration(days: allocatedDays - 1));
      windows.add(
        _DraftPhaseWindow(
          phaseIndex: index,
          startDate: windowStart,
          endDate: windowEnd,
        ),
      );
      cursor = windowEnd.add(const Duration(days: 1));
      remainingActualDays -= allocatedDays;
      remainingEstimatedDays -= phase.estimatedDays < 1
          ? 1
          : phase.estimatedDays;
    }
    return windows;
  }

  int? _findClosestPhaseWindowIndex({
    required ProductionAssistantPlanTask task,
    required List<_DraftPhaseWindow> phaseWindows,
  }) {
    if (task.startDate == null ||
        task.dueDate == null ||
        phaseWindows.isEmpty) {
      return null;
    }
    final taskStart = DateTime(
      task.startDate!.year,
      task.startDate!.month,
      task.startDate!.day,
    );
    final taskEnd = DateTime(
      task.dueDate!.year,
      task.dueDate!.month,
      task.dueDate!.day,
    );
    final midpoint = taskStart.add(
      Duration(days: taskEnd.difference(taskStart).inDays ~/ 2),
    );
    for (final window in phaseWindows) {
      if (!midpoint.isBefore(window.startDate) &&
          !midpoint.isAfter(window.endDate)) {
        return window.phaseIndex;
      }
    }
    int bestIndex = phaseWindows.first.phaseIndex;
    int bestDistance = midpoint
        .difference(phaseWindows.first.startDate)
        .inDays
        .abs();
    for (final window in phaseWindows.skip(1)) {
      final distance = midpoint.isBefore(window.startDate)
          ? window.startDate.difference(midpoint).inDays.abs()
          : midpoint.difference(window.endDate).inDays.abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = window.phaseIndex;
      }
    }
    return bestIndex;
  }

  String _normalizeDraftRepairKey(String rawValue) {
    return rawValue
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), "_")
        .replaceAll(RegExp(r"_+"), "_")
        .replaceAll(RegExp(r"^_|_$"), "");
  }

  bool _draftRepairMatchesAnyAlias(String normalized, List<String> aliases) {
    if (normalized.trim().isEmpty) {
      return false;
    }
    final paddedNormalized = "_${normalized}_";
    for (final alias in aliases) {
      final normalizedAlias = _normalizeDraftRepairKey(alias);
      if (normalizedAlias.isEmpty) {
        continue;
      }
      if (normalized == normalizedAlias) {
        return true;
      }
      if (paddedNormalized.contains("_${normalizedAlias}_")) {
        return true;
      }
    }
    return false;
  }

  String _resolveDraftRepairCropKey(String rawProductName) {
    final normalized = _normalizeDraftRepairKey(rawProductName);
    if (normalized.isEmpty ||
        _draftRepairMatchesAnyAlias(
          normalized,
          _draftRepairUnsupportedSpiceAliases,
        )) {
      return "";
    }
    if (normalized.contains("cassava") ||
        normalized.contains("manioc") ||
        normalized.contains("yuca")) {
      return "cassava";
    }
    if (normalized.contains("bell_pepper") ||
        normalized.contains("sweet_pepper") ||
        normalized.contains("pepper")) {
      return "pepper";
    }
    if (normalized.contains("eggplant") || normalized.contains("aubergine")) {
      return "eggplant";
    }
    if (normalized.contains("garden_egg") ||
        normalized.contains("gboma") ||
        normalized.contains("nsuu")) {
      return "eggplant";
    }
    if (normalized.contains("bean") ||
        normalized == "beans" ||
        normalized.contains("cowpea") ||
        normalized.contains("soybean")) {
      return "beans";
    }
    if (normalized.contains("groundnut") || normalized.contains("peanut")) {
      return "groundnut";
    }
    if (normalized.contains("chickpea")) {
      return "chickpea";
    }
    if (normalized.contains("pigeon_pea") || normalized.contains("pigeon")) {
      return "pigeon_pea";
    }
    if (normalized.contains("tomato")) {
      return "tomato";
    }
    if (normalized.contains("rice") || normalized.contains("paddy")) {
      return "rice";
    }
    if (normalized.contains("maize") || normalized.contains("corn")) {
      return "maize";
    }
    if (normalized.contains("sorghum")) {
      return "sorghum";
    }
    if (normalized.contains("millet")) {
      return "millet";
    }
    if (normalized.contains("okra") || normalized.contains("okro")) {
      return "okra";
    }
    if (normalized.contains("cucumber") || normalized.contains("gherkin")) {
      return "cucumber";
    }
    if (normalized.contains("watermelon")) {
      return "watermelon";
    }
    if (normalized == "melon" ||
        normalized.endsWith("_melon") ||
        normalized.contains("cantaloupe") ||
        normalized.contains("muskmelon") ||
        normalized.contains("honeydew")) {
      return "melon";
    }
    if (normalized.contains("pumpkin")) {
      return "pumpkin";
    }
    if (_draftRepairMatchesAnyAlias(
      normalized,
      _draftRepairTransplantFruitingCropAliases,
    )) {
      return "transplant_fruiting_crop";
    }
    if (_draftRepairMatchesAnyAlias(
      normalized,
      _draftRepairLegumeCropAliases,
    )) {
      return "legume_crop";
    }
    if (_draftRepairMatchesAnyAlias(normalized, _draftRepairGrainCropAliases)) {
      return "grain_crop";
    }
    if (_draftRepairMatchesAnyAlias(
      normalized,
      _draftRepairDirectFruitingCropAliases,
    )) {
      return "direct_fruiting_crop";
    }
    return "";
  }

  bool _draftRepairIsTransplantFruitingCrop(String cropKey) {
    switch (cropKey) {
      case "transplant_fruiting_crop":
      case "pepper":
      case "tomato":
      case "eggplant":
        return true;
      default:
        return false;
    }
  }

  bool _draftRepairIsLegumeCrop(String cropKey) {
    switch (cropKey) {
      case "legume_crop":
      case "beans":
      case "groundnut":
      case "soybean":
      case "cowpea":
      case "chickpea":
      case "pigeon_pea":
        return true;
      default:
        return false;
    }
  }

  bool _draftRepairIsGrainCrop(String cropKey) {
    switch (cropKey) {
      case "grain_crop":
      case "rice":
      case "maize":
      case "sorghum":
      case "millet":
        return true;
      default:
        return false;
    }
  }

  bool _draftRepairIsDirectFruitingCrop(String cropKey) {
    switch (cropKey) {
      case "direct_fruiting_crop":
      case "okra":
      case "cucumber":
      case "watermelon":
      case "melon":
      case "pumpkin":
        return true;
      default:
        return false;
    }
  }

  bool _supportsDraftRepairPlantingCounts(String cropKey) {
    return _draftRepairUsesNurseryTransplantFlow(cropKey) ||
        _draftRepairUsesDirectSeedingFlow(cropKey) ||
        _draftRepairIsLegumeCrop(cropKey) ||
        _draftRepairIsGrainCrop(cropKey) ||
        _draftRepairIsDirectFruitingCrop(cropKey);
  }

  bool _draftRepairUsesNurseryTransplantFlow(String cropKey) {
    return _draftRepairIsTransplantFruitingCrop(cropKey);
  }

  bool _draftRepairUsesDirectSeedingFlow(String cropKey) {
    return cropKey == "beans" ||
        cropKey == "rice" ||
        _draftRepairIsLegumeCrop(cropKey) ||
        _draftRepairIsGrainCrop(cropKey) ||
        _draftRepairIsDirectFruitingCrop(cropKey);
  }

  String _buildDraftRepairWorkloadContextLabel() {
    return _formatWorkUnitsCountForPreview(
      value: _resolveSafeTotalWorkUnitsForPreview(),
      workUnitLabel: _resolveSafeWorkUnitLabelForStaffing(),
    );
  }

  String _buildDraftRepairPlantUnitLabel(String cropKey) {
    if (_draftRepairUsesNurseryTransplantFlow(cropKey)) {
      return "plants";
    }
    if (cropKey == "rice") {
      return "stands";
    }
    return "stands";
  }

  String _buildDraftRepairNurserySowingInstruction({
    required String cropName,
    required String cropKey,
  }) {
    final workloadLabel = _buildDraftRepairWorkloadContextLabel();
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    final seedContext = _draftRepairUsesNurseryTransplantFlow(cropKey)
        ? "Record tray counts, seed counts, and target seedlings for the current $workloadLabel plan"
        : "Record seedbed counts, seed counts, and target seedlings for the current $workloadLabel plan";
    return "Sow $safeCropName evenly in the nursery, keep moisture steady for uniform emergence, and $seedContext before the stand moves into establishment planning.";
  }

  String _buildDraftRepairGerminationCountInstruction({
    required String cropName,
  }) {
    final workloadLabel = _buildDraftRepairWorkloadContextLabel();
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    return "Count germinated $safeCropName seedlings, record viable trays or nursery sections for the current $workloadLabel plan, and separate weak stock before transplant decisions are made.";
  }

  String _buildDraftRepairDirectSeedInstruction({
    required String cropName,
    required String cropKey,
  }) {
    final workloadLabel = _buildDraftRepairWorkloadContextLabel();
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    final seedRateLabel = cropKey == "rice"
        ? "seed rate or nursery block counts"
        : "seed count and planting-line counts";
    return "Plant $safeCropName on the planned spacing, record $seedRateLabel by plot for the current $workloadLabel plan, and note any sections likely to need early gap follow-up.";
  }

  String _buildDraftRepairTransplantInstruction({
    required String cropName,
    required String cropKey,
  }) {
    final workloadLabel = _buildDraftRepairWorkloadContextLabel();
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    final standUnitLabel = _buildDraftRepairPlantUnitLabel(cropKey);
    return "Transplant healthy $safeCropName seedlings at the planned spacing, water them in immediately, and record transplanted $standUnitLabel per plot and total for the current $workloadLabel plan.";
  }

  String _buildDraftRepairEstablishedStandInstruction({
    required String cropName,
    required String cropKey,
    bool includeGapClosure = false,
  }) {
    final workloadLabel = _buildDraftRepairWorkloadContextLabel();
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    final standUnitLabel = _buildDraftRepairPlantUnitLabel(cropKey);
    final gapCopy = includeGapClosure
        ? " Close gaps quickly where emergence or transplant survival is weak."
        : "";
    return "Count established $safeCropName $standUnitLabel per plot and in total for the current $workloadLabel plan, record survival or emergence loss, and keep the stand register current.$gapCopy";
  }

  String _buildDraftRepairYieldBasisInstruction({
    required String cropName,
    required String cropKey,
  }) {
    final workloadLabel = _buildDraftRepairWorkloadContextLabel();
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    final standUnitLabel = _buildDraftRepairPlantUnitLabel(cropKey);
    return "Update the expected $safeCropName yield basis for the current $workloadLabel plan using established $standUnitLabel per plot, survival rate, and the business yield baseline. Do not forecast expected yield from raw seed count alone.";
  }

  bool _isDraftPropagationTrackingTaskTitle(String rawTitle) {
    final normalized = _normalizeDraftRepairKey(
      _normalizeLifecycleTaskTitle(rawTitle),
    );
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.contains("seed") ||
        normalized.contains("sow") ||
        normalized.contains("nursery") ||
        normalized.contains("tray") ||
        normalized.contains("germin") ||
        normalized.contains("seedling") ||
        normalized.contains("emerg") ||
        normalized.contains("transplant") ||
        normalized.contains("stand");
  }

  _DraftRepairTemplate? _resolveDraftPropagationRepairTemplate({
    required String cropKey,
    required String cropName,
    required String phaseKey,
    required String rawTaskTitle,
  }) {
    if (!_supportsDraftRepairPlantingCounts(cropKey)) {
      return null;
    }
    final normalizedTitle = _normalizeDraftRepairKey(
      _normalizeLifecycleTaskTitle(rawTaskTitle),
    );
    if (normalizedTitle.isEmpty) {
      return null;
    }
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    final isNurseryFlowCrop = _draftRepairUsesNurseryTransplantFlow(cropKey);
    final isDirectSeedCrop = _draftRepairUsesDirectSeedingFlow(cropKey);

    if (phaseKey == "nursery" && isNurseryFlowCrop) {
      if (normalizedTitle.contains("germin") ||
          normalizedTitle.contains("tray") ||
          normalizedTitle.contains("seedling") ||
          normalizedTitle.contains("viable")) {
        return _DraftRepairTemplate(
          title: "Count $safeCropName germination and viable nursery trays",
          instructions: _buildDraftRepairGerminationCountInstruction(
            cropName: safeCropName,
          ),
        );
      }
      if (normalizedTitle.contains("seed") ||
          normalizedTitle.contains("sow") ||
          normalizedTitle.contains("nursery")) {
        return _DraftRepairTemplate(
          title: "Sow $safeCropName seeds in trays and record nursery targets",
          instructions: _buildDraftRepairNurserySowingInstruction(
            cropName: safeCropName,
            cropKey: cropKey,
          ),
        );
      }
    }

    if (phaseKey == "transplant_establishment" || phaseKey == "establishment") {
      if (isNurseryFlowCrop) {
        if (normalizedTitle.contains("count") ||
            normalizedTitle.contains("stand") ||
            normalizedTitle.contains("replace")) {
          return _DraftRepairTemplate(
            title:
                "Count established $safeCropName plants and update yield basis",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: safeCropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: safeCropName,
                cropKey: cropKey,
              ),
            ].join(" "),
          );
        }
        if (normalizedTitle.contains("seed") ||
            normalizedTitle.contains("sow") ||
            normalizedTitle.contains("transplant") ||
            normalizedTitle.contains("seedling") ||
            normalizedTitle.contains("plant")) {
          return _DraftRepairTemplate(
            title:
                "Transplant $safeCropName seedlings and record planted stands",
            instructions: _buildDraftRepairTransplantInstruction(
              cropName: safeCropName,
              cropKey: cropKey,
            ),
          );
        }
      }
      if (isDirectSeedCrop) {
        if (normalizedTitle.contains("count") ||
            normalizedTitle.contains("stand") ||
            normalizedTitle.contains("emerg") ||
            normalizedTitle.contains("transplant")) {
          return _DraftRepairTemplate(
            title: "Count emerged $safeCropName stands and close gaps",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: safeCropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: safeCropName,
                cropKey: cropKey,
              ),
            ].join(" "),
          );
        }
        if (normalizedTitle.contains("seed") ||
            normalizedTitle.contains("sow") ||
            normalizedTitle.contains("plant")) {
          return _DraftRepairTemplate(
            title: "Plant $safeCropName seed and record seed count by plot",
            instructions: _buildDraftRepairDirectSeedInstruction(
              cropName: safeCropName,
              cropKey: cropKey,
            ),
          );
        }
      }
    }

    if (phaseKey == "vegetative_growth" ||
        phaseKey == "fruit_set" ||
        phaseKey == "harvest") {
      if (_isDraftPropagationTrackingTaskTitle(rawTaskTitle)) {
        return _DraftRepairTemplate(
          title:
              "Review established $safeCropName ${_buildDraftRepairPlantUnitLabel(cropKey)} and update yield basis",
          instructions: [
            _buildDraftRepairEstablishedStandInstruction(
              cropName: safeCropName,
              cropKey: cropKey,
            ),
            _buildDraftRepairYieldBasisInstruction(
              cropName: safeCropName,
              cropKey: cropKey,
            ),
          ].join(" "),
        );
      }
    }

    return null;
  }

  String _resolveDraftRepairPhaseKey(String rawPhaseName) {
    final normalized = _normalizeDraftRepairKey(rawPhaseName);
    if (normalized.contains("stem_cutting")) {
      return "stem_cutting_establishment";
    }
    if (normalized.contains("nursery")) {
      return "nursery";
    }
    if (normalized.contains("transplant")) {
      return "transplant_establishment";
    }
    if (normalized.contains("establish") || normalized.contains("plant")) {
      return "establishment";
    }
    if (normalized.contains("canopy") || normalized.contains("vegetative")) {
      return "vegetative_growth";
    }
    if (normalized.contains("root_bulking")) {
      return "root_bulking";
    }
    if (normalized.contains("root_init")) {
      return "root_initiation";
    }
    if (normalized.contains("flower") || normalized.contains("fruit_set")) {
      return "fruit_set";
    }
    if (normalized.contains("harvest")) {
      return "harvest";
    }
    return normalized;
  }

  bool _isGenericDraftTaskTitle(String rawTitle) {
    final normalized = _normalizeDraftRepairKey(
      _normalizeLifecycleTaskTitle(rawTitle),
    );
    const genericKeys = <String>{
      "task",
      "phase_execution",
      "phase_monitoring",
      "phase_work",
      "execution",
      "monitoring",
      "general_task",
      "field_work",
      "field_check",
      "field_upkeep",
      "crop_health_check",
    };
    if (normalized.isEmpty) {
      return true;
    }
    return genericKeys.contains(normalized) ||
        normalized.startsWith("phase_execution") ||
        normalized.startsWith("phase_monitoring");
  }

  bool _isManagementRole(String rawRole) {
    final normalizedRole = _normalizeRoleKey(rawRole);
    return normalizedRole == _normalizeRoleKey(staffRoleFarmManager) ||
        normalizedRole == _normalizeRoleKey(staffRoleEstateManager) ||
        normalizedRole == _normalizeRoleKey(staffRoleAssetManager);
  }

  bool _isManagementOversightTask(ProductionAssistantPlanTask task) {
    if (!_isManagementRole(task.roleRequired)) {
      return false;
    }
    final normalizedTitle = _normalizeDraftRepairKey(task.title);
    return normalizedTitle.contains("supervision") ||
        normalizedTitle.contains("oversight") ||
        normalizedTitle.contains("operations_review");
  }

  bool _isManagementOversightScheduleTask(_AssistantScheduleTask task) {
    if (!_isManagementRole(task.roleRequired)) {
      return false;
    }
    final normalizedTitle = _normalizeDraftRepairKey(task.title);
    return normalizedTitle.contains("supervision") ||
        normalizedTitle.contains("oversight");
  }

  List<_DraftRepairTemplate> _resolveTransplantFruitingRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "nursery":
        return [
          _DraftRepairTemplate(
            title: "Prepare $cropName nursery trays or seedbed",
            instructions:
                "Ready the nursery media, confirm drainage and spacing, and stage the nursery area for consistent seed placement.",
          ),
          _DraftRepairTemplate(
            title: "Sow $cropName seeds in trays and record nursery targets",
            instructions: _buildDraftRepairNurserySowingInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
          _DraftRepairTemplate(
            title: "Count $cropName germination and viable nursery trays",
            instructions: _buildDraftRepairGerminationCountInstruction(
              cropName: cropName,
            ),
          ),
        ];
      case "transplant_establishment":
      case "establishment":
        return [
          _DraftRepairTemplate(
            title: "Harden $cropName seedlings before transplanting",
            instructions:
                "Reduce transplant shock by hardening seedlings, checking vigor, and staging only healthy plants for field movement.",
          ),
          _DraftRepairTemplate(
            title: "Transplant $cropName seedlings and record planted stands",
            instructions: _buildDraftRepairTransplantInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
          _DraftRepairTemplate(
            title: "Count established $cropName plants and update yield basis",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
          ),
        ];
      case "vegetative_growth":
        return [
          _DraftRepairTemplate(
            title: "Weed $cropName beds and maintain mulch cover",
            instructions:
                "Remove competing weeds, maintain bed access, and preserve mulch or soil cover where the block requires it.",
          ),
          _DraftRepairTemplate(
            title: "Apply fertilizer to support $cropName canopy growth",
            instructions:
                "Apply the planned nutrient input and monitor plant response so canopy growth stays even across the block.",
          ),
          _DraftRepairTemplate(
            title: "Review established $cropName plants and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
        ];
      case "fruit_set":
        return [
          _DraftRepairTemplate(
            title: "Scout $cropName flowers and fruit set",
            instructions:
                "Inspect flowering and early fruit set, record stress signals, and flag pests or nutrient issues early.",
          ),
          _DraftRepairTemplate(
            title: "Support $cropName fruit set with irrigation checks",
            instructions:
                "Review field moisture, correct avoidable stress, and keep fruit set stable across the active production block.",
          ),
          _DraftRepairTemplate(
            title: "Review established $cropName plants and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
        ];
      case "harvest":
        return [
          _DraftRepairTemplate(
            title: "Pick mature $cropName for market",
            instructions:
                "Harvest market-ready produce carefully, separate damaged units, and keep harvested produce shaded and moving.",
          ),
          _DraftRepairTemplate(
            title: "Grade, sort, and pack harvested $cropName",
            instructions:
                "Sort harvested produce by quality, remove rejects, and pack clean units for storage or dispatch.",
          ),
        ];
      default:
        return const <_DraftRepairTemplate>[];
    }
  }

  List<_DraftRepairTemplate> _resolveLegumeRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "establishment":
      case "transplant_establishment":
        return [
          _DraftRepairTemplate(
            title: "Prepare $cropName field and planting lines",
            instructions:
                "Mark planting lines, check spacing, and prepare the field so seed placement and early emergence stay uniform.",
          ),
          _DraftRepairTemplate(
            title: "Plant $cropName seed and record seed count by plot",
            instructions: _buildDraftRepairDirectSeedInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
          _DraftRepairTemplate(
            title: "Count emerged $cropName stands and close gaps",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
          ),
        ];
      case "vegetative_growth":
      case "fruit_set":
        return [
          _DraftRepairTemplate(
            title: "Weed $cropName rows and maintain access paths",
            instructions:
                "Remove weed pressure, keep movement paths open, and reduce competition during active crop growth.",
          ),
          _DraftRepairTemplate(
            title:
                "Scout $cropName field for pests, disease, and nutrient stress",
            instructions:
                "Inspect leaves and stems, note hotspots early, and escalate any field section showing avoidable production risk.",
          ),
          _DraftRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
        ];
      case "harvest":
        return [
          _DraftRepairTemplate(
            title: "Harvest mature $cropName",
            instructions:
                "Harvest mature produce at the planned stage, separate damaged units, and keep batches organized for drying or storage.",
          ),
          _DraftRepairTemplate(
            title: "Dry, shell or thresh, and bag harvested $cropName",
            instructions:
                "Dry harvested material to the target level, shell or thresh carefully, and bag clean output for handling or storage.",
          ),
        ];
      default:
        return const <_DraftRepairTemplate>[];
    }
  }

  List<_DraftRepairTemplate> _resolveGrainRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "nursery":
        return [
          _DraftRepairTemplate(
            title: "Prepare nursery setup for $cropName",
            instructions:
                "Ready the nursery area, confirm bed or tray condition, and stage inputs before active nursery work starts.",
          ),
          _DraftRepairTemplate(
            title: "Sow $cropName nursery seedbeds and record seed targets",
            instructions: _buildDraftRepairNurserySowingInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
          _DraftRepairTemplate(
            title: "Count $cropName germination and viable nursery sections",
            instructions: _buildDraftRepairGerminationCountInstruction(
              cropName: cropName,
            ),
          ),
        ];
      case "establishment":
      case "transplant_establishment":
        return [
          _DraftRepairTemplate(
            title: "Prepare $cropName field and planting lines",
            instructions:
                "Ready the field, confirm spacing and water control, and remove blockers before full establishment work begins.",
          ),
          _DraftRepairTemplate(
            title: "Plant $cropName seed and record seed count by plot",
            instructions: _buildDraftRepairDirectSeedInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
          _DraftRepairTemplate(
            title: "Count emerged $cropName stands and close gaps",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
          ),
        ];
      case "vegetative_growth":
      case "fruit_set":
        return [
          _DraftRepairTemplate(
            title: "Check $cropName field moisture and nutrient balance",
            instructions:
                "Review moisture and nutrient balance, then correct field sections drifting into avoidable stress.",
          ),
          _DraftRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
        ];
      case "harvest":
        return [
          _DraftRepairTemplate(
            title: "Harvest mature $cropName blocks",
            instructions:
                "Harvest mature crop blocks carefully, keep cut sections organized, and move material promptly into drying or threshing flow.",
          ),
          _DraftRepairTemplate(
            title: "Dry, thresh, and bag harvested $cropName",
            instructions:
                "Dry harvested material to the target level, thresh carefully, and bag clean grain for handling or storage.",
          ),
        ];
      default:
        return const <_DraftRepairTemplate>[];
    }
  }

  List<_DraftRepairTemplate> _resolveDirectFruitingRepairTemplates({
    required String cropName,
    required String cropKey,
    required String phaseKey,
  }) {
    switch (phaseKey) {
      case "establishment":
      case "transplant_establishment":
        return [
          _DraftRepairTemplate(
            title: "Prepare $cropName field and planting lines",
            instructions:
                "Mark planting lines, check spacing, and prepare the field so seed placement and early emergence stay uniform.",
          ),
          _DraftRepairTemplate(
            title: "Plant $cropName seed and record seed count by plot",
            instructions: _buildDraftRepairDirectSeedInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
          _DraftRepairTemplate(
            title: "Count emerged $cropName stands and close gaps",
            instructions: [
              _buildDraftRepairEstablishedStandInstruction(
                cropName: cropName,
                cropKey: cropKey,
                includeGapClosure: true,
              ),
              _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ].join(" "),
          ),
        ];
      case "vegetative_growth":
      case "fruit_set":
        return [
          _DraftRepairTemplate(
            title: "Weed $cropName beds and maintain access paths",
            instructions:
                "Remove weed pressure, keep movement paths open, and reduce competition during active crop growth.",
          ),
          _DraftRepairTemplate(
            title: "Scout $cropName field for pests and disease",
            instructions:
                "Inspect leaves and stems, note hotspots early, and escalate any field section showing avoidable production risk.",
          ),
          _DraftRepairTemplate(
            title: "Review established $cropName stands and update yield basis",
            instructions: _buildDraftRepairYieldBasisInstruction(
              cropName: cropName,
              cropKey: cropKey,
            ),
          ),
        ];
      case "harvest":
        return [
          _DraftRepairTemplate(
            title: "Harvest mature $cropName",
            instructions:
                "Harvest mature produce carefully, separate damaged units, and keep batches organized for grading or dispatch.",
          ),
          _DraftRepairTemplate(
            title: "Sort, grade, and move harvested $cropName",
            instructions:
                "Sort harvested produce by quality, remove rejects, and move clean units quickly into storage or dispatch flow.",
          ),
        ];
      default:
        return const <_DraftRepairTemplate>[];
    }
  }

  String _draftRepairWeekKeyForTask(ProductionAssistantPlanTask task) {
    if (task.startDate == null) {
      return "";
    }
    final start = DateTime(
      task.startDate!.year,
      task.startDate!.month,
      task.startDate!.day,
    );
    return formatDateInput(_startOfWeekMonday(start));
  }

  List<_DraftRepairTemplate> _resolveDraftRepairTemplates({
    required String cropKey,
    required String cropName,
    required String phaseKey,
    required bool allowCropSpecificTemplates,
  }) {
    if (allowCropSpecificTemplates &&
        _draftRepairIsTransplantFruitingCrop(cropKey)) {
      return _resolveTransplantFruitingRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    if (allowCropSpecificTemplates && _draftRepairIsLegumeCrop(cropKey)) {
      return _resolveLegumeRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    if (allowCropSpecificTemplates && _draftRepairIsGrainCrop(cropKey)) {
      return _resolveGrainRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    if (allowCropSpecificTemplates &&
        _draftRepairIsDirectFruitingCrop(cropKey)) {
      return _resolveDirectFruitingRepairTemplates(
        cropName: cropName,
        cropKey: cropKey,
        phaseKey: phaseKey,
      );
    }
    if (allowCropSpecificTemplates && cropKey == "cassava") {
      switch (phaseKey) {
        case "stem_cutting_establishment":
          return const [
            _DraftRepairTemplate(
              title: "Prepare cassava stem cuttings for planting",
              instructions:
                  "Select healthy mature stems, cut viable stakes, discard damaged material, and stage bundles for planting.",
            ),
            _DraftRepairTemplate(
              title: "Lay out ridges or mounds for cassava planting",
              instructions:
                  "Mark planting lines, shape ridges or mounds, and confirm spacing before the field team starts planting.",
            ),
            _DraftRepairTemplate(
              title: "Plant cassava cuttings and verify spacing",
              instructions:
                  "Set cuttings at the correct angle and depth, keep spacing consistent, and record planted units for follow-up.",
            ),
          ];
        case "vegetative_growth":
          return const [
            _DraftRepairTemplate(
              title: "Weed cassava rows and clean inter-row paths",
              instructions:
                  "Clear early weed pressure, open access paths, and remove growth that competes with cassava stand establishment.",
            ),
            _DraftRepairTemplate(
              title: "Replace weak cassava stands and stabilize canopy",
              instructions:
                  "Check stand gaps, replace failed plants where needed, and confirm canopy development is uniform across the field.",
            ),
            _DraftRepairTemplate(
              title: "Apply manure or fertilizer to support cassava growth",
              instructions:
                  "Apply the planned nutrient input, avoid root-zone damage, and record any sections needing follow-up.",
            ),
          ];
        case "root_initiation":
          return const [
            _DraftRepairTemplate(
              title: "Scout cassava field for pest and disease pressure",
              instructions:
                  "Inspect leaves, stems, and stand vigor, note pest or disease hotspots, and flag any section requiring intervention.",
            ),
            _DraftRepairTemplate(
              title: "Inspect root initiation and stand vigor",
              instructions:
                  "Check plant health and early root development signals, then report weak sections before they affect later bulking.",
            ),
          ];
        case "root_bulking":
          return const [
            _DraftRepairTemplate(
              title: "Monitor cassava root bulking and moisture stress",
              instructions:
                  "Inspect plant condition, look for moisture stress or nutrient decline, and note any yield risks before harvest.",
            ),
            _DraftRepairTemplate(
              title: "Keep cassava bulking rows weed-free",
              instructions:
                  "Remove late weed competition and keep root bulking blocks accessible for field checks and harvest preparation.",
            ),
          ];
        case "harvest":
          return const [
            _DraftRepairTemplate(
              title: "Prepare cassava harvest crew and collection points",
              instructions:
                  "Confirm crew readiness, clear harvest access, and set temporary collection points before lifting roots.",
            ),
            _DraftRepairTemplate(
              title: "Harvest mature cassava roots",
              instructions:
                  "Lift mature roots carefully, separate damaged produce, and keep harvested units moving to the collection area.",
            ),
            _DraftRepairTemplate(
              title: "Sort, load, and move harvested cassava",
              instructions:
                  "Sort marketable roots, load clean batches, and move harvested cassava promptly to avoid avoidable quality loss.",
            ),
          ];
      }
    }
    if (allowCropSpecificTemplates && cropKey == "pepper") {
      switch (phaseKey) {
        case "nursery":
          return [
            _DraftRepairTemplate(
              title: "Prepare bell pepper nursery trays or seedbed",
              instructions:
                  "Ready the nursery media, confirm drainage and spacing, and stage the nursery area for consistent seed placement.",
            ),
            _DraftRepairTemplate(
              title:
                  "Sow bell pepper seeds in trays and record nursery targets",
              instructions: _buildDraftRepairNurserySowingInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
            _DraftRepairTemplate(
              title: "Count bell pepper germination and viable nursery trays",
              instructions: _buildDraftRepairGerminationCountInstruction(
                cropName: cropName,
              ),
            ),
          ];
        case "transplant_establishment":
        case "establishment":
          return [
            _DraftRepairTemplate(
              title: "Harden bell pepper seedlings before transplanting",
              instructions:
                  "Reduce transplant shock by hardening seedlings, checking vigor, and staging only healthy plants for field movement.",
            ),
            _DraftRepairTemplate(
              title:
                  "Transplant bell pepper seedlings and record planted stands",
              instructions: _buildDraftRepairTransplantInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
            _DraftRepairTemplate(
              title: "Replace weak bell pepper transplants",
              instructions:
                  "Review the field for failed or weak transplants, replace them quickly, and keep stand counts consistent.",
            ),
            _DraftRepairTemplate(
              title:
                  "Count established bell pepper plants and update yield basis",
              instructions: [
                _buildDraftRepairEstablishedStandInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                  includeGapClosure: true,
                ),
                _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
              ].join(" "),
            ),
          ];
        case "vegetative_growth":
          return [
            _DraftRepairTemplate(
              title: "Weed bell pepper beds and maintain mulch cover",
              instructions:
                  "Remove competing weeds, maintain bed access, and preserve mulch or soil cover where the block requires it.",
            ),
            _DraftRepairTemplate(
              title: "Apply fertilizer to support bell pepper canopy growth",
              instructions:
                  "Apply the planned nutrient input and monitor plant response so canopy growth stays even across the block.",
            ),
            _DraftRepairTemplate(
              title:
                  "Review established bell pepper plants and update yield basis",
              instructions: _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
          ];
        case "fruit_set":
          return [
            _DraftRepairTemplate(
              title: "Scout bell pepper flowers and fruit set",
              instructions:
                  "Inspect flowering and early fruit set, record stress signals, and flag pests or nutrient issues early.",
            ),
            _DraftRepairTemplate(
              title: "Support bell pepper fruit set with irrigation checks",
              instructions:
                  "Review field moisture, correct avoidable stress, and keep fruit set stable across the active production block.",
            ),
            _DraftRepairTemplate(
              title:
                  "Review established bell pepper plants and update yield basis",
              instructions: _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
          ];
        case "harvest":
          return const [
            _DraftRepairTemplate(
              title: "Pick mature bell peppers for market",
              instructions:
                  "Harvest market-ready fruit carefully, separate damaged peppers, and keep harvested produce shaded and moving.",
            ),
            _DraftRepairTemplate(
              title: "Grade, sort, and pack harvested bell peppers",
              instructions:
                  "Sort harvested peppers by quality, remove rejects, and pack clean produce for storage or dispatch.",
            ),
          ];
      }
    }
    if (allowCropSpecificTemplates && cropKey == "tomato") {
      switch (phaseKey) {
        case "nursery":
          return [
            _DraftRepairTemplate(
              title: "Prepare tomato nursery trays or seedbed",
              instructions:
                  "Ready the nursery media, confirm drainage and spacing, and stage the nursery area for consistent seed placement.",
            ),
            _DraftRepairTemplate(
              title: "Sow tomato seeds in trays and record nursery targets",
              instructions: _buildDraftRepairNurserySowingInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
            _DraftRepairTemplate(
              title: "Count tomato germination and viable nursery trays",
              instructions: _buildDraftRepairGerminationCountInstruction(
                cropName: cropName,
              ),
            ),
          ];
        case "transplant_establishment":
        case "establishment":
          return [
            _DraftRepairTemplate(
              title: "Harden tomato seedlings before transplanting",
              instructions:
                  "Reduce transplant shock by hardening seedlings, checking vigor, and staging only healthy plants for field movement.",
            ),
            _DraftRepairTemplate(
              title: "Transplant tomato seedlings and record planted stands",
              instructions: _buildDraftRepairTransplantInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
            _DraftRepairTemplate(
              title: "Count established tomato plants and update yield basis",
              instructions: [
                _buildDraftRepairEstablishedStandInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                  includeGapClosure: true,
                ),
                _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
              ].join(" "),
            ),
          ];
        case "vegetative_growth":
          return [
            _DraftRepairTemplate(
              title: "Weed tomato beds and maintain mulch cover",
              instructions:
                  "Remove competing weeds, maintain bed access, and preserve mulch or soil cover where the block requires it.",
            ),
            _DraftRepairTemplate(
              title: "Apply fertilizer to support tomato canopy growth",
              instructions:
                  "Apply the planned nutrient input and monitor plant response so canopy growth stays even across the block.",
            ),
            _DraftRepairTemplate(
              title: "Review established tomato plants and update yield basis",
              instructions: _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
          ];
        case "fruit_set":
          return [
            _DraftRepairTemplate(
              title: "Scout tomato flowers and fruit set",
              instructions:
                  "Inspect flowering and early fruit set, record stress signals, and flag pests or nutrient issues early.",
            ),
            _DraftRepairTemplate(
              title: "Support tomato fruit set with irrigation checks",
              instructions:
                  "Review field moisture, correct avoidable stress, and keep fruit set stable across the active production block.",
            ),
            _DraftRepairTemplate(
              title: "Review established tomato plants and update yield basis",
              instructions: _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
          ];
        case "harvest":
          return const [
            _DraftRepairTemplate(
              title: "Pick mature tomatoes for market",
              instructions:
                  "Harvest market-ready fruit carefully, separate damaged tomatoes, and keep harvested produce shaded and moving.",
            ),
            _DraftRepairTemplate(
              title: "Grade, sort, and pack harvested tomatoes",
              instructions:
                  "Sort harvested tomatoes by quality, remove rejects, and pack clean produce for storage or dispatch.",
            ),
          ];
      }
    }
    if (allowCropSpecificTemplates && cropKey == "beans") {
      switch (phaseKey) {
        case "establishment":
        case "transplant_establishment":
          return [
            _DraftRepairTemplate(
              title: "Prepare bean field and planting lines",
              instructions:
                  "Mark planting lines, check spacing, and prepare the field so seed placement and early emergence stay uniform.",
            ),
            _DraftRepairTemplate(
              title: "Plant bean seed and record seed count by plot",
              instructions: _buildDraftRepairDirectSeedInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
            _DraftRepairTemplate(
              title: "Count emerged bean stands and close gaps",
              instructions: [
                _buildDraftRepairEstablishedStandInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                  includeGapClosure: true,
                ),
                _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
              ].join(" "),
            ),
          ];
        case "vegetative_growth":
        case "fruit_set":
          return [
            _DraftRepairTemplate(
              title: "Weed bean rows and maintain access paths",
              instructions:
                  "Remove weed pressure, keep movement paths open, and reduce competition during active bean growth.",
            ),
            _DraftRepairTemplate(
              title: "Scout bean field for pests, disease, and nutrient stress",
              instructions:
                  "Inspect leaves and stems, note hotspots early, and escalate any field section showing avoidable production risk.",
            ),
            _DraftRepairTemplate(
              title: "Review established bean stands and update yield basis",
              instructions: _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
          ];
        case "harvest":
          return const [
            _DraftRepairTemplate(
              title: "Harvest mature bean pods",
              instructions:
                  "Harvest mature pods at the planned stage, separate damaged produce, and keep batches organized for drying or storage.",
            ),
            _DraftRepairTemplate(
              title: "Dry, thresh, and bag harvested beans",
              instructions:
                  "Dry harvested material to the target level, thresh carefully, and bag clean beans for handling or storage.",
            ),
          ];
      }
    }
    if (allowCropSpecificTemplates && cropKey == "rice") {
      switch (phaseKey) {
        case "nursery":
          return [
            _DraftRepairTemplate(
              title: "Prepare rice nursery beds or trays",
              instructions:
                  "Ready nursery media or seedbed condition, confirm drainage, and stage inputs before active rice nursery work starts.",
            ),
            _DraftRepairTemplate(
              title: "Sow rice seedbeds and record nursery seed targets",
              instructions: _buildDraftRepairNurserySowingInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
            _DraftRepairTemplate(
              title: "Count rice germination and viable nursery sections",
              instructions: _buildDraftRepairGerminationCountInstruction(
                cropName: cropName,
              ),
            ),
          ];
        case "establishment":
        case "transplant_establishment":
          return [
            _DraftRepairTemplate(
              title: "Prepare rice field and planting lines",
              instructions:
                  "Ready the field, confirm water control and spacing, and remove blockers before full establishment work begins.",
            ),
            _DraftRepairTemplate(
              title: "Plant rice seed and record seed count by plot",
              instructions: _buildDraftRepairDirectSeedInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
            _DraftRepairTemplate(
              title: "Count emerged rice stands and close gaps",
              instructions: [
                _buildDraftRepairEstablishedStandInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                  includeGapClosure: true,
                ),
                _buildDraftRepairYieldBasisInstruction(
                  cropName: cropName,
                  cropKey: cropKey,
                ),
              ].join(" "),
            ),
          ];
        case "vegetative_growth":
        case "fruit_set":
          return [
            _DraftRepairTemplate(
              title: "Check rice field water balance and soil condition",
              instructions:
                  "Review water balance and soil condition, then correct field sections drifting into avoidable stress.",
            ),
            _DraftRepairTemplate(
              title: "Review established rice stands and update yield basis",
              instructions: _buildDraftRepairYieldBasisInstruction(
                cropName: cropName,
                cropKey: cropKey,
              ),
            ),
          ];
        case "harvest":
          return const [
            _DraftRepairTemplate(
              title: "Harvest mature rice blocks",
              instructions:
                  "Harvest mature rice carefully, keep cut blocks organized, and move grain promptly into drying or threshing flow.",
            ),
            _DraftRepairTemplate(
              title: "Dry, thresh, and bag harvested rice",
              instructions:
                  "Dry harvested material to the target level, thresh carefully, and bag clean grain for handling or storage.",
            ),
          ];
      }
    }
    return _buildGenericDraftRepairTemplates(
      cropName: cropName,
      phaseKey: phaseKey,
    );
  }

  List<_DraftRepairTemplate> _buildGenericDraftRepairTemplates({
    required String cropName,
    required String phaseKey,
  }) {
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    switch (phaseKey) {
      case "nursery":
        return [
          _DraftRepairTemplate(
            title: "Prepare nursery setup for $safeCropName",
            instructions:
                "Ready the nursery area, confirm trays or seedbed condition, and stage inputs before active nursery work starts.",
          ),
          _DraftRepairTemplate(
            title: "Manage early nursery work for $safeCropName",
            instructions:
                "Carry out nursery operations carefully, track germination or establishment progress, and record follow-up needs.",
          ),
        ];
      case "stem_cutting_establishment":
      case "transplant_establishment":
      case "establishment":
        return [
          _DraftRepairTemplate(
            title: "Prepare field establishment work for $safeCropName",
            instructions:
                "Ready the field, confirm spacing and input availability, and remove blockers before full establishment work begins.",
          ),
          _DraftRepairTemplate(
            title: "Establish $safeCropName in the field",
            instructions:
                "Carry out the main establishment activity, keep spacing consistent, and record any gaps or weak sections for follow-up.",
          ),
        ];
      case "vegetative_growth":
        return [
          _DraftRepairTemplate(
            title: "Maintain active vegetative growth for $safeCropName",
            instructions:
                "Manage weeds, nutrition, and field access so the crop can continue strong vegetative development.",
          ),
        ];
      case "root_initiation":
      case "root_bulking":
      case "fruit_set":
        return [
          _DraftRepairTemplate(
            title: "Monitor critical development stage for $safeCropName",
            instructions:
                "Inspect crop progress closely, note stress signals early, and record any action needed to protect expected yield.",
          ),
        ];
      case "harvest":
        return [
          _DraftRepairTemplate(
            title: "Prepare $safeCropName harvest operations",
            instructions:
                "Confirm field readiness, labor flow, and handling steps before active harvest begins.",
          ),
          _DraftRepairTemplate(
            title: "Harvest and handle $safeCropName",
            instructions:
                "Harvest the crop carefully, separate damaged produce, and move harvested units promptly for storage or dispatch.",
          ),
        ];
      default:
        return [
          _DraftRepairTemplate(
            title: _buildFallbackDraftRepairTitle(
              cropName: safeCropName,
              phaseName: phaseKey,
            ),
            instructions: _buildFallbackDraftRepairInstruction(
              cropName: safeCropName,
              phaseName: phaseKey,
              taskTitle: "Maintain production flow",
            ),
          ),
        ];
    }
  }

  String _buildFallbackDraftRepairTitle({
    required String cropName,
    required String phaseName,
  }) {
    final safeCropName = cropName.trim().isEmpty ? "Crop" : cropName.trim();
    final safePhaseName = phaseName.trim().isEmpty
        ? "production"
        : phaseName.trim().replaceAll("_", " ");
    return "Carry out $safeCropName work for $safePhaseName";
  }

  String _buildFallbackDraftRepairInstruction({
    required String cropName,
    required String phaseName,
    required String taskTitle,
  }) {
    final safeCropName = cropName.trim().isEmpty ? "the crop" : cropName.trim();
    final safePhaseName = phaseName.trim().isEmpty
        ? "this phase"
        : phaseName.trim().replaceAll("_", " ");
    final safeTaskTitle = taskTitle.trim().isEmpty
        ? "the task"
        : taskTitle.trim();
    return "Carry out $safeTaskTitle for $safeCropName during $safePhaseName, record blockers early, and confirm the block is ready for the next step.";
  }

  List<ProductionAssistantPlanWarning> _dedupeDraftWarnings(
    List<ProductionAssistantPlanWarning> warnings,
  ) {
    final seen = <String>{};
    final deduped = <ProductionAssistantPlanWarning>[];
    for (final warning in warnings) {
      final code = warning.code.trim().toLowerCase();
      final message = warning.message.trim();
      final key = "${code.isEmpty ? 'message' : code}|${message.toLowerCase()}";
      if (message.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      deduped.add(warning);
    }
    return deduped;
  }

  Future<void> _downloadCurrentStudioDraft({
    required ProductionPlanDraftState draft,
  }) async {
    final payload = _buildPlanDraftPayloadFromStudioDraft(draft: draft);
    final scopedPayload = _sanitizePlanDraftPayloadForFocusedContext(
      payload: payload,
    );
    final weeklyRows = _buildWeeklyScheduleRows(scopedPayload);
    final safeWorkUnitLabel = _resolveSafeWorkUnitLabelForStaffing();
    final safeTotalWorkUnits = _resolveSafeTotalWorkUnitsForPreview();
    final projectedSummary = _resolveProjectedSummaryFromRows(
      weeklyRows: weeklyRows,
      safeTotalWorkUnits: safeTotalWorkUnits,
    );
    final previewStaffProfiles =
        ref.read(productionStaffProvider).valueOrNull ??
        const <BusinessStaffProfileSummary>[];
    final previewStaffById = <String, BusinessStaffProfileSummary>{
      for (final profile in previewStaffProfiles)
        if (profile.id.trim().isNotEmpty) profile.id.trim(): profile,
    };
    await _downloadDraftProductionSchedulePreview(
      payload: scopedPayload,
      weeklyRows: weeklyRows,
      projectedSummary: projectedSummary,
      safeWorkUnitLabel: safeWorkUnitLabel,
      staffById: previewStaffById,
    );
  }

  Future<void> _populateDraftUsingImportedDocument({
    required String selectedEstateName,
    required String selectedProductName,
  }) async {
    if (_isSending || _isImportingDraftDocument) {
      return;
    }
    final hasEstate = (_selectedEstateAssetId ?? "").trim().isNotEmpty;
    final hasProduct = _hasSelectedProduct();
    if (!hasEstate || !hasProduct) {
      _showSnack(_contextPromptMissingContextMessage);
      return;
    }
    if (!_isWorkloadContextReadyForDraft()) {
      _showSnack(_contextPromptConfirmWorkloadContextMissing);
      return;
    }

    setState(() {
      _isImportingDraftDocument = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _documentImportAllowedExtensions,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes ?? <int>[];
      if (bytes.isEmpty) {
        _showSnack("That file could not be read for draft import.");
        return;
      }
      final importedText = _extractImportableDocumentText(
        bytes: bytes,
        filename: file.name,
      );
      if (importedText.trim().isEmpty) {
        _showSnack(
          "No readable planning text was found in that PDF. Try a text-based PDF or a downloaded HTML plan export.",
        );
        return;
      }

      final focusedRoles = _focusedRoleKeys.toList()..sort();
      final focusedStaff = _selectedFocusedStaffProfiles(
        staffProfiles:
            ref.read(productionStaffProvider).valueOrNull ?? const [],
      );
      final prompt = _buildImportedDocumentDraftPrompt(
        estateName: selectedEstateName,
        productName: selectedProductName,
        focusedRoles: focusedRoles,
        focusedStaff: focusedStaff,
        fileName: file.name,
        importedText: importedText,
      );
      AppDebug.log(
        _logTag,
        _populateDraftFromPdfTapLog,
        extra: {
          "fileName": file.name,
          "extension": _extractImportFileExtension(file.name),
          "textLength": importedText.length,
        },
      );
      await _runDirectDraftGeneration(
        prompt: prompt,
        productName: selectedProductName,
        focusedRoles: focusedRoles,
        focusedStaff: focusedStaff,
        displayPrompt:
            "Populate draft from imported document: ${file.name.trim()}",
      );
      AppDebug.log(
        _logTag,
        _populateDraftFromPdfSuccessLog,
        extra: {"fileName": file.name, "textLength": importedText.length},
      );
    } catch (error) {
      AppDebug.log(
        _logTag,
        _populateDraftFromPdfFailureLog,
        extra: {"error": error.toString()},
      );
      if (mounted) {
        _showSnack("Couldn't populate the draft from that document yet.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImportingDraftDocument = false;
        });
      } else {
        _isImportingDraftDocument = false;
      }
    }
  }

  String _buildImportedDocumentDraftPrompt({
    required String estateName,
    required String productName,
    required List<String> focusedRoles,
    required List<BusinessStaffProfileSummary> focusedStaff,
    required String fileName,
    required String importedText,
  }) {
    final basePrompt = _buildStrictGeneratePrompt(
      estateName: estateName,
      productName: productName,
      focusedRoles: focusedRoles,
      focusedStaff: focusedStaff,
    );
    final safeFileName = fileName.trim().isEmpty
        ? "uploaded-document"
        : fileName.trim();
    final truncatedText = importedText.length > _documentImportCharacterLimit
        ? importedText.substring(0, _documentImportCharacterLimit)
        : importedText;
    final wasTruncated = importedText.length > truncatedText.length;
    final truncationInstruction = wasTruncated
        ? " The imported document was truncated to the first $_documentImportCharacterLimit characters for prompt safety."
        : "";
    return "$basePrompt Use the imported planning document below as the primary source material for the draft. Preserve explicit phase names, task titles, sequencing, durations, staffing counts, and notes where they are coherent. Convert the source into a lifecycle-safe editable production draft for the currently selected crop and estate instead of copying the document blindly.$truncationInstruction Source document: $safeFileName.\n\nIMPORTED DOCUMENT START\n$truncatedText\nIMPORTED DOCUMENT END";
  }

  String _extractImportableDocumentText({
    required List<int> bytes,
    required String filename,
  }) {
    final extension = _extractImportFileExtension(filename);
    switch (extension) {
      case "html":
      case "htm":
        return _normalizeImportedDocumentText(
          _stripHtmlTags(utf8.decode(bytes, allowMalformed: true)),
        );
      case "txt":
        return _normalizeImportedDocumentText(
          utf8.decode(bytes, allowMalformed: true),
        );
      case "pdf":
        final extractedPdfText = _extractTextFromPdfBytes(bytes);
        return _normalizeImportedDocumentText(extractedPdfText);
      default:
        return _normalizeImportedDocumentText(
          utf8.decode(bytes, allowMalformed: true),
        );
    }
  }

  String _extractImportFileExtension(String filename) {
    final segments = filename.trim().toLowerCase().split(".");
    return segments.length < 2 ? "" : segments.last.trim();
  }

  String _stripHtmlTags(String rawHtml) {
    return rawHtml
        .replaceAll(
          RegExp(
            r"<script[^>]*>.*?</script>",
            caseSensitive: false,
            dotAll: true,
          ),
          " ",
        )
        .replaceAll(
          RegExp(
            r"<style[^>]*>.*?</style>",
            caseSensitive: false,
            dotAll: true,
          ),
          " ",
        )
        .replaceAll(RegExp(r"<br\s*/?>", caseSensitive: false), "\n")
        .replaceAll(RegExp(r"</p>", caseSensitive: false), "\n")
        .replaceAll(RegExp(r"<[^>]+>"), " ")
        .replaceAll("&nbsp;", " ")
        .replaceAll("&amp;", "&")
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&quot;", "\"")
        .replaceAll("&#39;", "'");
  }

  String _normalizeImportedDocumentText(String rawText) {
    final cleaned = rawText
        .replaceAll(RegExp(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]"), " ")
        .replaceAll(RegExp(r"[ \t]+"), " ");
    final lines = cleaned
        .split(RegExp(r"[\r\n]+"))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join("\n");
  }

  String _extractTextFromPdfBytes(List<int> bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final collected = <String>[];

    void collectFragment(String rawFragment) {
      final decoded = _decodePdfLiteralString(rawFragment).trim();
      if (decoded.isEmpty) {
        return;
      }
      if (decoded.length < 2) {
        return;
      }
      collected.add(decoded);
    }

    final literalPattern = RegExp(r"\(((?:\\.|[^\\()])*)\)\s*Tj");
    for (final match in literalPattern.allMatches(raw)) {
      final fragment = match.group(1);
      if (fragment != null) {
        collectFragment(fragment);
      }
    }

    final arrayPattern = RegExp(r"\[(.*?)\]\s*TJ", dotAll: true);
    for (final match in arrayPattern.allMatches(raw)) {
      final arrayText = match.group(1) ?? "";
      for (final inner in RegExp(
        r"\(((?:\\.|[^\\()])*)\)",
      ).allMatches(arrayText)) {
        final fragment = inner.group(1);
        if (fragment != null) {
          collectFragment(fragment);
        }
      }
    }

    if (collected.isNotEmpty) {
      return collected.join("\n");
    }

    final printableRuns = RegExp(r"[A-Za-z][A-Za-z0-9 ,.;:()/_\-]{24,}")
        .allMatches(raw)
        .map((match) => match.group(0)?.trim() ?? "")
        .where((line) => line.isNotEmpty)
        .toList();
    return printableRuns.join("\n");
  }

  String _decodePdfLiteralString(String value) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < value.length) {
      final current = value[index];
      if (current != "\\") {
        buffer.write(current);
        index += 1;
        continue;
      }
      if (index + 1 >= value.length) {
        break;
      }
      final next = value[index + 1];
      switch (next) {
        case "n":
          buffer.write("\n");
          index += 2;
          break;
        case "r":
          buffer.write("\r");
          index += 2;
          break;
        case "t":
          buffer.write("\t");
          index += 2;
          break;
        case "b":
          buffer.write("\b");
          index += 2;
          break;
        case "f":
          buffer.write("\f");
          index += 2;
          break;
        case "\\":
        case "(":
        case ")":
          buffer.write(next);
          index += 2;
          break;
        default:
          final octalMatch = RegExp(
            r"^[0-7]{1,3}",
          ).matchAsPrefix(value.substring(index + 1));
          if (octalMatch != null) {
            final octalValue = int.tryParse(octalMatch.group(0)!, radix: 8);
            if (octalValue != null) {
              buffer.writeCharCode(octalValue);
              index += 1 + octalMatch.group(0)!.length;
              break;
            }
          }
          buffer.write(next);
          index += 2;
          break;
      }
    }
    return buffer.toString();
  }

  String _buildDraftScheduleDownloadFileName(
    ProductionAssistantPlanDraftPayload payload,
  ) {
    final rawProductName = payload.productName.trim().isEmpty
        ? "production"
        : payload.productName.trim().toLowerCase();
    final slug = rawProductName
        .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
        .replaceAll(RegExp(r"-{2,}"), "-")
        .replaceAll(RegExp(r"^-+|-+$"), "");
    final safeSlug = slug.isEmpty ? "production" : slug;
    final safeStartDate = payload.startDate.trim().isEmpty
        ? formatDateInput(DateTime.now())
        : payload.startDate.trim();
    return "draft-$safeSlug-$safeStartDate.html";
  }

  String _buildDraftScheduleDownloadContents({
    required ProductionAssistantPlanDraftPayload payload,
    required List<_AssistantWeeklySchedule> weeklyRows,
    required _AssistantProjectionSummary projectedSummary,
    required String safeWorkUnitLabel,
    required Map<String, BusinessStaffProfileSummary> staffById,
    required String selectedEstateName,
    required String selectedProductName,
    required List<String> focusedRoles,
    required List<String> focusedStaffProfileIds,
    required int alignmentPercent,
  }) {
    final productTitle = payload.productName.trim().isEmpty
        ? "Untitled production"
        : payload.productName.trim();
    final resolvedEstateName = selectedEstateName.trim().isEmpty
        ? "Not selected"
        : selectedEstateName.trim();
    final resolvedEstateId = (_selectedEstateAssetId ?? "").trim();
    final resolvedProductName = selectedProductName.trim().isEmpty
        ? productTitle
        : selectedProductName.trim();
    final resolvedProductId = (_selectedProductId ?? "").trim();
    final resolvedStartDate = _startDate == null
        ? payload.startDate
        : formatDateInput(_startDate!);
    final resolvedEndDate = _endDate == null
        ? payload.endDate
        : formatDateInput(_endDate!);
    final hasExplicitDates = _startDate != null && _endDate != null;
    final dateMode = _useAiInferredDates
        ? "Lifecycle-derived dates"
        : (hasExplicitDates ? "Manual dates selected" : "Not confirmed");
    final workloadSummary =
        "${_totalWorkUnits ?? 0} $safeWorkUnitLabel units, min ${_minStaffPerUnit ?? 0}/unit, max ${_maxStaffPerUnit ?? 0}/unit, $_activeStaffAvailabilityPercent% active";
    final contextSummary = [
      "Business: ${formatProductionDomainLabel(_domainContext)}",
      "Estate: $resolvedEstateName",
      "Crop: $resolvedProductName",
      "Workload: $workloadSummary",
      "Dates: $dateMode",
      "Focused roles: ${focusedRoles.length}",
      "Focused staff: ${focusedStaffProfileIds.length}",
    ].join(" | ");
    final plannerMeta = payload.plannerMeta;
    final lifecycle = payload.lifecycle;
    final lifecyclePhasesHtml = lifecycle == null || lifecycle.phases.isEmpty
        ? '<div class="empty-state compact">No lifecycle phases were attached to this draft.</div>'
        : lifecycle.phases
              .map(
                (phase) =>
                    _buildDraftHtmlTag(label: phase.replaceAll("_", " ")),
              )
              .join();
    final lifecycleSectionHtml = lifecycle == null
        ? '<div class="empty-state">Planner metadata was not attached to this draft.</div>'
        : '''
            <div class="metric-grid">
              ${_buildDraftHtmlMetricCard(label: "Lifecycle product", value: lifecycle.product.isEmpty ? productTitle : lifecycle.product, detail: "Resolved biological profile used before scheduling.")}
              ${_buildDraftHtmlMetricCard(label: "Lifecycle range", value: "${lifecycle.minDays}-${lifecycle.maxDays} days", detail: "Accepted duration window for this crop lifecycle.", accentClass: "cool")}
              ${_buildDraftHtmlMetricCard(label: "Planner version", value: plannerMeta?.version.isNotEmpty == true ? plannerMeta!.version : "legacy", detail: "Schedule source: ${plannerMeta?.scheduleSource.isNotEmpty == true ? plannerMeta!.scheduleSource : "unknown"}", accentClass: "warm")}
              ${_buildDraftHtmlMetricCard(label: "Lifecycle source", value: plannerMeta?.lifecycleSource.isNotEmpty == true ? plannerMeta!.lifecycleSource : "unknown", detail: "Retries used: ${plannerMeta?.retryCount ?? 0}")}
            </div>
            <div style="height: 14px;"></div>
            <div class="tag-wrap">$lifecyclePhasesHtml</div>
          ''';
    final focusedRolesHtml = focusedRoles.isEmpty
        ? '<div class="empty-state compact">No focused roles selected yet.</div>'
        : focusedRoles
              .map(
                (role) => _buildDraftHtmlTag(
                  label: formatStaffRoleLabel(role, fallback: role),
                ),
              )
              .join();
    final focusedStaffHtml = focusedStaffProfileIds.isEmpty
        ? '<div class="empty-state compact">No focused staff selected yet.</div>'
        : focusedStaffProfileIds.map((staffId) {
            final safeId = staffId.trim();
            final profile = staffById[safeId];
            final displayName = _staffPreviewLabel(
              staffProfileId: safeId,
              profile: profile,
            );
            final roleLabel = profile == null
                ? "Unknown role"
                : formatStaffRoleLabel(
                    profile.staffRole,
                    fallback: profile.staffRole,
                  );
            return '''
              <div class="staff-row">
                <div class="staff-avatar">${_escapeHtml(_staffPreviewInitials(staffProfileId: safeId, profile: profile))}</div>
                <div class="staff-copy">
                  <div class="staff-name">${_escapeHtml(displayName)}</div>
                  <div class="staff-meta">${_escapeHtml(roleLabel)} | ${_escapeHtml(safeId)}</div>
                </div>
              </div>
            ''';
          }).join();
    final projectionHtml = projectedSummary.hasExecutionTaskTracks
        ? [
            _buildDraftHtmlMetricCard(
              label: _draftPlanProjectedCoverageLabel,
              value:
                  "${_formatWorkUnitsCountForPreview(value: projectedSummary.minimumCoveredAcrossTracks, workUnitLabel: safeWorkUnitLabel)} / ${_formatWorkUnitsCountForPreview(value: projectedSummary.expectedWorkUnitsPerTrack, workUnitLabel: safeWorkUnitLabel)}",
              detail: "Lowest fully covered execution track.",
            ),
            _buildDraftHtmlMetricCard(
              label: _draftPlanProjectedRemainingLabel,
              value: _formatWorkUnitsCountForPreview(
                value: projectedSummary.maximumRemainingAcrossTracks,
                workUnitLabel: safeWorkUnitLabel,
              ),
              detail: "Highest remaining execution workload.",
              accentClass: "warm",
            ),
            _buildDraftHtmlMetricCard(
              label: _draftPlanProjectedTrackCountLabel,
              value:
                  "${projectedSummary.fullyCoveredTrackCount}/${projectedSummary.executionTaskTrackCount}",
              detail: "Execution tracks with full projected coverage.",
              accentClass: "cool",
            ),
          ].join()
        : '<div class="empty-state">No execution-track projection was generated for this draft.</div>';
    final warningsHtml = payload.warnings.isEmpty
        ? '<div class="empty-state">No warnings were added to this draft.</div>'
        : payload.warnings
              .map((warning) => _buildDraftHtmlWarningCard(warning))
              .join();
    final conversationHtml = _messages.isEmpty
        ? '<div class="empty-state">No assistant conversation messages were captured.</div>'
        : _messages
              .asMap()
              .entries
              .map(
                (entry) => _buildDraftHtmlConversationMessage(
                  index: entry.key,
                  message: entry.value,
                ),
              )
              .join();
    final scheduleHtml = weeklyRows.isEmpty
        ? '<div class="empty-state">$_draftPlanSheetEmpty</div>'
        : weeklyRows
              .asMap()
              .entries
              .map(
                (entry) => _buildDraftHtmlWeek(
                  weekIndex: entry.key,
                  week: entry.value,
                  safeWorkUnitLabel: safeWorkUnitLabel,
                  staffById: staffById,
                ),
              )
              .join();
    final safeGeneratedDate = formatDateInput(DateTime.now());
    return '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${_escapeHtml(productTitle)} draft schedule</title>
    <style>
      :root {
        --page-bg: #f4fbf8;
        --surface: #ffffff;
        --surface-soft: #edf8f4;
        --border: #d8e8e3;
        --border-strong: #c4dad3;
        --text: #14332f;
        --muted: #617a75;
        --accent: #16796f;
        --accent-soft: #d6f2ec;
        --warning-bg: #fff7e3;
        --warning-line: #d58e11;
        --warning-border: #f0d38b;
        --assistant-bg: #f7f1e8;
        --user-bg: #d8f5ef;
        --error-bg: #fde9e7;
        --error-line: #d96a60;
        --shadow: 0 18px 48px rgba(14, 59, 54, 0.08);
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        background:
          radial-gradient(circle at top left, rgba(22, 121, 111, 0.08), transparent 28%),
          linear-gradient(180deg, #f8fcfb 0%, var(--page-bg) 100%);
        color: var(--text);
        font-family: "SF Pro Display", "Segoe UI", "Helvetica Neue", Arial, sans-serif;
        line-height: 1.55;
      }

      .page-shell {
        max-width: 1320px;
        margin: 0 auto;
        padding: 24px;
      }

      .hero-card {
        border-radius: 28px;
        overflow: hidden;
        background: linear-gradient(135deg, #0f4f4a 0%, #16796f 58%, #2da494 100%);
        color: #ffffff;
        box-shadow: var(--shadow);
      }

      .hero-card-inner {
        display: grid;
        grid-template-columns: minmax(0, 1.7fr) minmax(280px, 1fr);
        gap: 22px;
        padding: 28px;
      }

      .hero-eyebrow {
        margin: 0 0 8px;
        text-transform: uppercase;
        letter-spacing: 0.14em;
        font-size: 12px;
        font-weight: 700;
        opacity: 0.86;
      }

      .hero-title {
        margin: 0;
        font-size: clamp(28px, 4vw, 42px);
        line-height: 1.08;
      }

      .hero-copy {
        margin: 12px 0 0;
        max-width: 720px;
        color: rgba(255, 255, 255, 0.92);
      }

      .hero-summary {
        margin-top: 16px;
        padding: 16px 18px;
        border-radius: 18px;
        background: rgba(255, 255, 255, 0.12);
        border-left: 5px solid rgba(255, 255, 255, 0.8);
      }

      .hero-kpis {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px;
        align-content: start;
      }

      .hero-kpi {
        padding: 16px;
        border-radius: 18px;
        background: rgba(255, 255, 255, 0.12);
        border: 1px solid rgba(255, 255, 255, 0.18);
      }

      .hero-kpi-label {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        opacity: 0.8;
      }

      .hero-kpi-value {
        margin-top: 8px;
        font-size: 28px;
        font-weight: 700;
        line-height: 1.1;
      }

      .hero-kpi-detail {
        margin-top: 6px;
        font-size: 13px;
        opacity: 0.86;
      }

      .report-grid {
        display: grid;
        grid-template-columns: repeat(12, minmax(0, 1fr));
        gap: 18px;
        margin-top: 20px;
      }

      .section-card {
        grid-column: span 6;
        padding: 22px;
        border-radius: 24px;
        background: var(--surface);
        border: 1px solid var(--border);
        box-shadow: var(--shadow);
      }

      .section-span {
        grid-column: 1 / -1;
      }

      .section-header {
        display: flex;
        gap: 14px;
        align-items: flex-start;
        margin-bottom: 16px;
      }

      .section-line {
        width: 5px;
        min-height: 54px;
        border-radius: 999px;
        background: linear-gradient(180deg, #16796f, #67c4b7);
        flex-shrink: 0;
      }

      .section-kicker {
        margin: 0 0 4px;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        color: var(--accent);
        font-weight: 700;
      }

      .section-title {
        margin: 0;
        font-size: 24px;
        line-height: 1.15;
      }

      .section-subtitle {
        margin: 6px 0 0;
        color: var(--muted);
        font-size: 14px;
      }

      .summary-banner {
        padding: 16px 18px;
        margin-bottom: 16px;
        border-radius: 18px;
        background: var(--surface-soft);
        border: 1px solid var(--border);
        border-left: 6px solid var(--accent);
      }

      .metric-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 12px;
      }

      .metric-card {
        padding: 16px;
        border-radius: 18px;
        background: #fcfffe;
        border: 1px solid var(--border);
        border-top: 4px solid var(--accent);
      }

      .metric-card.cool {
        border-top-color: #2d6bc8;
        background: #f7fbff;
      }

      .metric-card.warm {
        border-top-color: #d89b1d;
        background: #fffaf1;
      }

      .metric-label {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted);
        font-weight: 700;
      }

      .metric-value {
        margin-top: 8px;
        font-size: 22px;
        font-weight: 700;
        line-height: 1.18;
      }

      .metric-detail {
        margin-top: 8px;
        color: var(--muted);
        font-size: 14px;
      }

      .tag-wrap {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .tag {
        display: inline-flex;
        align-items: center;
        min-height: 34px;
        padding: 8px 12px;
        border-radius: 999px;
        background: var(--accent-soft);
        border: 1px solid #bfe3db;
        color: var(--text);
        font-size: 13px;
        font-weight: 600;
      }

      .staff-list {
        display: grid;
        gap: 10px;
      }

      .staff-row {
        display: flex;
        gap: 12px;
        align-items: center;
        padding: 12px 14px;
        border-radius: 18px;
        border: 1px solid var(--border);
        border-left: 5px solid var(--accent);
        background: #fcfffe;
      }

      .staff-avatar {
        width: 38px;
        height: 38px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        background: var(--accent-soft);
        color: var(--accent);
        font-weight: 700;
      }

      .staff-name { font-weight: 700; }

      .staff-meta {
        color: var(--muted);
        font-size: 13px;
      }

      .warning-stack {
        display: grid;
        gap: 12px;
      }

      .warning-card {
        padding: 16px 18px;
        border-radius: 18px;
        background: var(--warning-bg);
        border: 1px solid var(--warning-border);
        border-left: 6px solid var(--warning-line);
      }

      .warning-code {
        display: inline-flex;
        align-items: center;
        min-height: 28px;
        padding: 6px 10px;
        border-radius: 999px;
        background: rgba(213, 142, 17, 0.12);
        color: #7b4d00;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
      }

      .warning-message {
        margin-top: 10px;
        font-size: 15px;
      }

      .conversation-stack {
        display: grid;
        gap: 12px;
      }

      .message-row {
        display: flex;
      }

      .message-row.user {
        justify-content: flex-end;
      }

      .message-bubble {
        width: min(100%, 820px);
        padding: 14px 16px;
        border-radius: 20px;
        border: 1px solid var(--border);
        background: var(--assistant-bg);
      }

      .message-row.user .message-bubble {
        background: var(--user-bg);
        border-color: #b8e7dd;
      }

      .message-row.error .message-bubble {
        background: var(--error-bg);
        border-color: #efb0aa;
        border-left: 5px solid var(--error-line);
      }

      .message-meta {
        margin-bottom: 8px;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted);
        font-weight: 700;
      }

      .message-text {
        white-space: pre-wrap;
        word-break: break-word;
      }

      .schedule-stack {
        display: grid;
        gap: 16px;
      }

      .week-card {
        padding: 18px;
        border-radius: 22px;
        border: 1px solid var(--border);
        background: linear-gradient(180deg, #ffffff 0%, #f8fcfb 100%);
      }

      .week-head {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        align-items: flex-start;
        flex-wrap: wrap;
        margin-bottom: 14px;
      }

      .week-label {
        margin: 0;
        font-size: 22px;
      }

      .week-note {
        color: var(--muted);
        font-size: 14px;
      }

      .day-grid {
        display: grid;
        gap: 12px;
      }

      .day-card {
        padding: 14px;
        border-radius: 18px;
        border: 1px solid var(--border);
        border-left: 5px solid #6fc3b6;
        background: #ffffff;
      }

      .day-title {
        margin: 0 0 10px;
        font-size: 18px;
      }

      .task-stack {
        display: grid;
        gap: 10px;
      }

      .task-card {
        padding: 12px 14px;
        border-radius: 16px;
        border: 1px solid var(--border);
        border-left: 6px solid var(--task-accent, var(--accent));
        background: #fcfffe;
      }

      .task-top {
        display: flex;
        justify-content: space-between;
        gap: 10px;
        flex-wrap: wrap;
        color: var(--muted);
        font-size: 13px;
        font-weight: 600;
      }

      .task-title {
        margin: 8px 0 6px;
        font-size: 18px;
      }

      .task-subcopy {
        color: var(--muted);
        font-size: 14px;
        margin-bottom: 10px;
      }

      .task-inline {
        margin-top: 8px;
        padding: 10px 12px;
        border-radius: 14px;
        background: var(--surface-soft);
        border: 1px solid var(--border);
        font-size: 14px;
      }

      .empty-state {
        padding: 16px 18px;
        border-radius: 18px;
        background: var(--surface-soft);
        border: 1px dashed var(--border-strong);
        color: var(--muted);
      }

      .empty-state.compact {
        padding: 12px 14px;
      }

      .footer-note {
        margin-top: 20px;
        color: var(--muted);
        font-size: 13px;
        text-align: center;
      }

      @media (max-width: 980px) {
        .hero-card-inner {
          grid-template-columns: 1fr;
        }

        .section-card {
          grid-column: 1 / -1;
        }
      }

      @media (max-width: 720px) {
        .page-shell {
          padding: 14px;
        }

        .hero-card-inner,
        .section-card {
          padding: 18px;
        }

        .hero-kpis {
          grid-template-columns: 1fr 1fr;
        }

        .metric-grid {
          grid-template-columns: 1fr;
        }

        .section-title {
          font-size: 21px;
        }

        .week-label,
        .day-title,
        .task-title {
          font-size: 17px;
        }
      }
    </style>
  </head>
  <body>
    <div class="page-shell">
      <header class="hero-card">
        <div class="hero-card-inner">
          <div>
            <p class="hero-eyebrow">AI Production Draft Export</p>
            <h1 class="hero-title">${_escapeHtml(productTitle)}</h1>
            <p class="hero-copy">
              Structured draft report with planning context, full assistant conversation, warnings, and the generated weekly schedule.
            </p>
            <div class="hero-summary">${_escapeHtml(contextSummary)}</div>
          </div>
          <div class="hero-kpis">
            <div class="hero-kpi">
              <div class="hero-kpi-label">Range</div>
              <div class="hero-kpi-value">${_escapeHtml("${payload.startDate} to ${payload.endDate}")}</div>
              <div class="hero-kpi-detail">${_escapeHtml("${payload.weeks} week(s)")}</div>
            </div>
            <div class="hero-kpi">
              <div class="hero-kpi-label">Alignment</div>
              <div class="hero-kpi-value">${_escapeHtml("$alignmentPercent%")}</div>
              <div class="hero-kpi-detail">Current assistant confidence snapshot</div>
            </div>
            <div class="hero-kpi">
              <div class="hero-kpi-label">Duration</div>
              <div class="hero-kpi-value">${_escapeHtml("${payload.days} day(s)")}</div>
              <div class="hero-kpi-detail">${_escapeHtml("${payload.phases.length} phase(s) in plan")}</div>
            </div>
            <div class="hero-kpi">
              <div class="hero-kpi-label">Generated on</div>
              <div class="hero-kpi-value">${_escapeHtml(safeGeneratedDate)}</div>
              <div class="hero-kpi-detail">Full context + conversation included</div>
            </div>
          </div>
        </div>
      </header>

      <main class="report-grid">
        <section class="section-card">
          ${_buildDraftHtmlSectionHeader(title: "Planning context", subtitle: "The exact setup used before the draft was generated.")}
          <div class="metric-grid">
            ${_buildDraftHtmlMetricCard(label: "Business type", value: "${formatProductionDomainLabel(_domainContext)}${_domainExplicitlySelected ? "" : " (default)"}", detail: "Current assistant business mode.")}
            ${_buildDraftHtmlMetricCard(label: "Estate", value: "$resolvedEstateName${resolvedEstateId.isEmpty ? "" : " [$resolvedEstateId]"}", detail: "Selected estate scope.", accentClass: "cool")}
            ${_buildDraftHtmlMetricCard(label: "Product", value: "$resolvedProductName${resolvedProductId.isEmpty ? "" : " [$resolvedProductId]"}", detail: "Draft target product.", accentClass: "cool")}
            ${_buildDraftHtmlMetricCard(label: "Dates", value: dateMode, detail: "Start: ${resolvedStartDate.trim().isEmpty ? "Not set" : resolvedStartDate} | End: ${resolvedEndDate.trim().isEmpty ? "Not set" : resolvedEndDate}", accentClass: "warm")}
            ${_buildDraftHtmlMetricCard(label: "Workload", value: "${_totalWorkUnits ?? 0} $safeWorkUnitLabel", detail: "Min ${_minStaffPerUnit ?? 0}/unit | Max ${_maxStaffPerUnit ?? 0}/unit")}
            ${_buildDraftHtmlMetricCard(label: "Workload confirmation", value: _hasConfirmedWorkloadContext ? "Confirmed" : "Not confirmed", detail: "Active staff assumption: $_activeStaffAvailabilityPercent%", accentClass: _hasConfirmedWorkloadContext ? "cool" : "warm")}
          </div>
        </section>

        <section class="section-card">
          ${_buildDraftHtmlSectionHeader(title: "Lifecycle summary", subtitle: "The biological planning envelope and planner version used for this draft.")}
          $lifecycleSectionHtml
        </section>

        <section class="section-card">
          ${_buildDraftHtmlSectionHeader(title: "Focused staffing", subtitle: "Roles and people the assistant was asked to prioritize.")}
          <div class="summary-banner">Focused roles: ${_escapeHtml("${focusedRoles.length}")} | Focused staff: ${_escapeHtml("${focusedStaffProfileIds.length}")} | Staff context confirmed: ${_escapeHtml(_hasConfirmedStaffContext ? "Yes" : "No")}</div>
          <div class="tag-wrap">$focusedRolesHtml</div>
          <div style="height: 14px;"></div>
          <div class="staff-list">$focusedStaffHtml</div>
        </section>

        <section class="section-card section-span">
          ${_buildDraftHtmlSectionHeader(title: "Projection overview", subtitle: "Top-level schedule coverage and draft quality signals.")}
          <div class="metric-grid">$projectionHtml</div>
        </section>

        <section class="section-card section-span">
          ${_buildDraftHtmlSectionHeader(title: "Validation warnings", subtitle: "Every warning returned with the draft so the reviewer can spot risk quickly.")}
          <div class="warning-stack">$warningsHtml</div>
        </section>

        <section class="section-card section-span">
          ${_buildDraftHtmlSectionHeader(title: "Conversation transcript", subtitle: "Full conversation transcript used to shape this draft.")}
          <div class="summary-banner">Messages captured: ${_escapeHtml("${_messages.length}")} | Export includes the full prompt chain from welcome to final draft request.</div>
          <div class="conversation-stack">$conversationHtml</div>
        </section>

        <section class="section-card section-span">
          ${_buildDraftHtmlSectionHeader(title: "Weekly schedule", subtitle: "Weekly schedule blocks with day-by-day tasks, projections, and assigned staff.")}
          <div class="schedule-stack">$scheduleHtml</div>
        </section>
      </main>

      <div class="footer-note">
        Exported from ${_escapeHtml(_screenTitle)}. Review warnings and staff assignments before committing the production draft.
      </div>
    </div>
  </body>
</html>
''';
  }

  String _buildDraftHtmlSectionHeader({
    required String title,
    required String subtitle,
  }) {
    return '''
      <div class="section-header">
        <div class="section-line"></div>
        <div>
          <p class="section-kicker">Draft overview</p>
          <h2 class="section-title">${_escapeHtml(title)}</h2>
          <p class="section-subtitle">${_escapeHtml(subtitle)}</p>
        </div>
      </div>
    ''';
  }

  String _buildDraftHtmlMetricCard({
    required String label,
    required String value,
    required String detail,
    String accentClass = "",
  }) {
    final safeAccentClass = accentClass.trim().isEmpty ? "" : " $accentClass";
    return '''
      <article class="metric-card$safeAccentClass">
        <div class="metric-label">${_escapeHtml(label)}</div>
        <div class="metric-value">${_escapeHtml(value)}</div>
        <div class="metric-detail">${_escapeHtml(detail)}</div>
      </article>
    ''';
  }

  String _buildDraftHtmlTag({required String label}) {
    return '<span class="tag">${_escapeHtml(label)}</span>';
  }

  String _buildDraftHtmlWarningCard(ProductionAssistantPlanWarning warning) {
    final safeMessage = warning.message.trim().isEmpty
        ? "No warning message provided."
        : warning.message.trim();
    final safeCode = warning.code.trim().isEmpty
        ? "warning"
        : warning.code.trim();
    return '''
      <article class="warning-card">
        <div class="warning-code">${_escapeHtml(safeCode)}</div>
        <div class="warning-message">${_escapeHtml(safeMessage)}</div>
      </article>
    ''';
  }

  String _buildDraftHtmlConversationMessage({
    required int index,
    required _ChatMessage message,
  }) {
    final rowClass = [
      "message-row",
      if (!message.fromAssistant) "user",
      if (message.isError) "error",
    ].join(" ");
    final speaker = message.fromAssistant
        ? (message.isError ? "Assistant error" : "Assistant")
        : "You";
    final safeMessage = message.text.trim().isEmpty
        ? "No message text."
        : message.text.trim();
    return '''
      <div class="$rowClass">
        <article class="message-bubble">
          <div class="message-meta">${_escapeHtml("${index + 1}. $speaker")}</div>
          <div class="message-text">${_escapeHtml(safeMessage)}</div>
        </article>
      </div>
    ''';
  }

  String _buildDraftHtmlWeek({
    required int weekIndex,
    required _AssistantWeeklySchedule week,
    required String safeWorkUnitLabel,
    required Map<String, BusinessStaffProfileSummary> staffById,
  }) {
    final scheduledDays = week.days
        .where((day) => day.tasks.isNotEmpty)
        .toList();
    final hiddenEmptyDayCount = week.days.length - scheduledDays.length;
    final dayHtml = scheduledDays.isEmpty
        ? '<div class="empty-state">No task scheduled this week.</div>'
        : scheduledDays
              .map(
                (day) => _buildDraftHtmlDay(
                  day: day,
                  safeWorkUnitLabel: safeWorkUnitLabel,
                  staffById: staffById,
                ),
              )
              .join();
    final weekNote = hiddenEmptyDayCount > 0
        ? "$hiddenEmptyDayCount empty day(s) hidden for clarity."
        : "${scheduledDays.length} scheduled day(s) in this week.";
    return '''
      <article class="week-card">
        <div class="week-head">
          <div>
            <h3 class="week-label">${_escapeHtml("Week ${weekIndex + 1}: ${formatDateLabel(week.weekStart)} to ${formatDateLabel(week.weekStart.add(const Duration(days: 6)))}")}</h3>
            <div class="week-note">${_escapeHtml(weekNote)}</div>
          </div>
        </div>
        <div class="day-grid">$dayHtml</div>
      </article>
    ''';
  }

  String _buildDraftHtmlDay({
    required _AssistantDailySchedule day,
    required String safeWorkUnitLabel,
    required Map<String, BusinessStaffProfileSummary> staffById,
  }) {
    final tasksHtml = day.tasks
        .map(
          (task) => _buildDraftHtmlTask(
            task: task,
            safeWorkUnitLabel: safeWorkUnitLabel,
            staffById: staffById,
          ),
        )
        .join();
    return '''
      <article class="day-card">
        <h4 class="day-title">${_escapeHtml("${_weekdayLabel(day.date.weekday)} ${formatDateLabel(day.date)}")}</h4>
        <div class="task-stack">$tasksHtml</div>
      </article>
    ''';
  }

  String _buildDraftHtmlTask({
    required _AssistantScheduleTask task,
    required String safeWorkUnitLabel,
    required Map<String, BusinessStaffProfileSummary> staffById,
  }) {
    final roleLabel = formatStaffRoleLabel(
      task.roleRequired,
      fallback: task.roleRequired,
    );
    final assignedStaffLabels = task.assignedStaffProfileIds
        .map(
          (staffId) => _staffPreviewLabel(
            staffProfileId: staffId.trim(),
            profile: staffById[staffId.trim()],
          ),
        )
        .where((label) => label.trim().isNotEmpty)
        .toList();
    final projectionHtml =
        _isPlotExecutionRoleForPreview(task.roleRequired) &&
            (task.projectionIsRepeatable ||
                task.projectedWorkUnits > 0 ||
                task.projectedWorkUnitsRemaining > 0)
        ? '''
          <div class="task-inline">
            ${_escapeHtml("$_draftPlanTaskProjectedLabel: ${_formatWorkUnitsCountForPreview(value: task.projectedWorkUnits, workUnitLabel: safeWorkUnitLabel)} | $_draftPlanTaskRemainingLabel: ${_formatWorkUnitsCountForPreview(value: task.projectedWorkUnitsRemaining, workUnitLabel: safeWorkUnitLabel)}${task.projectionIsRepeatable ? " (${_projectionCadenceLabel(task.projectionCadenceDays)})" : ""}")}
          </div>
        '''
        : "";
    final staffHtml = assignedStaffLabels.isEmpty
        ? '<div class="task-inline">No staff assigned in this preview block.</div>'
        : '<div class="task-inline">Staff: ${_escapeHtml(assignedStaffLabels.join(", "))}</div>';
    return '''
      <article class="task-card" style="--task-accent: ${_downloadRoleAccentColor(task.roleRequired)};">
        <div class="task-top">
          <div>${_escapeHtml("${_formatTaskTime(task.startDate)} - ${_formatTaskTime(task.dueDate)}")}</div>
          <div>${_escapeHtml("$roleLabel x${task.requiredHeadcount}")}</div>
        </div>
        <h5 class="task-title">${_escapeHtml(_normalizeLifecycleTaskTitle(task.title))}</h5>
        <div class="task-subcopy">${_escapeHtml(task.phaseName)}</div>
        $projectionHtml
        $staffHtml
      </article>
    ''';
  }

  String _downloadRoleAccentColor(String rawRole) {
    switch (_normalizeRoleKey(rawRole)) {
      case staffRoleEstateManager:
        return "#1b7b71";
      case staffRoleFarmManager:
        return "#2f855a";
      case staffRoleFieldAgent:
        return "#2d6bc8";
      case staffRoleFarmer:
        return "#d18d12";
      default:
        return "#16796f";
    }
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
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
        : "Derive startDate and endDate from the resolved product lifecycle and return the total weeks.";
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
    final staffCapacityInstruction = focusedStaffByRolePayload.isEmpty
        ? ""
        : " Focused staff capacity by role: ${focusedStaffByRolePayload.entries.map((entry) => "${formatStaffRoleLabel(entry.key)}=${entry.value.length}").join("; ")}.";
    final staffInstruction = focusedStaff.isEmpty
        ? ""
        : " Plan against ${focusedStaff.length} selected staff profiles only.";
    final safeWorkUnitLabel = _workUnitLabel.trim().isEmpty
        ? _defaultWorkUnitLabelForDomain(_domainContext)
        : _workUnitLabel.trim();
    final safeTotalWorkUnits = (_totalWorkUnits ?? 0) > 0 ? _totalWorkUnits : 1;
    final int safeMinStaffPerUnit = (_minStaffPerUnit ?? 0) > 0
        ? (_minStaffPerUnit ?? 1)
        : 1;
    final int safeMaxStaffPerUnitRaw = (_maxStaffPerUnit ?? 0) > 0
        ? (_maxStaffPerUnit ?? safeMinStaffPerUnit)
        : safeMinStaffPerUnit;
    final int safeMaxStaffPerUnit = safeMaxStaffPerUnitRaw < safeMinStaffPerUnit
        ? safeMinStaffPerUnit
        : safeMaxStaffPerUnitRaw;
    final workloadInstruction =
        " Workload context: $safeTotalWorkUnits $safeWorkUnitLabel units, min $safeMinStaffPerUnit and max $safeMaxStaffPerUnit staff per $safeWorkUnitLabel, expected active selected staff $_activeStaffAvailabilityPercent% per block.";
    final staffingRuleInstruction =
        " Keep requiredHeadcount realistic for that staffing range, and add warnings if workload exceeds likely capacity.";
    final stageGateInstruction =
        " Enforce lifecycle stage-gates: prerequisite tracks (for example preparation/procurement) must unlock work units before dependent tracks (for example planting/assembly/operations). Do not schedule dependent blocks with zero unlocked units. If unlock is insufficient, schedule more prerequisite blocks first and explain the constraint in warnings.";
    const executionTruthInstruction =
        " Prefer tasks that can be tracked by work unit and time block.";
    const lifecycleInstruction =
        " Use lifecycle-based dates from trusted product lifecycle data. Do not assign final staff IDs or hand-write dated schedule blocks; the backend scheduler owns that.";
    const outputInstruction =
        " Return lifecycle-safe phases, semantic tasks, roleRequired, requiredHeadcount, and warnings.";
    return "Generate a lifecycle-safe production draft for $safeProduct at $safeEstate. $dateInstruction$roleInstruction$roleAlignmentInstruction$staffCapacityInstruction$staffInstruction$workloadInstruction$staffingRuleInstruction$stageGateInstruction$executionTruthInstruction$lifecycleInstruction$outputInstruction";
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
    return _selectedProductName.trim();
  }

  String _buildAutoGenerateKey({required bool inferredMode}) {
    final estateId = (_selectedEstateAssetId ?? "").trim();
    final productKey = (_selectedProductId ?? "").trim().isNotEmpty
        ? (_selectedProductId ?? "").trim()
        : _resolveSelectedProductName().toLowerCase();
    final startText = _startDate == null ? "" : formatDateInput(_startDate!);
    final endText = _endDate == null ? "" : formatDateInput(_endDate!);
    final dateMode = inferredMode ? "infer" : "$startText|$endText";
    final focusedRoles = _focusedRoleKeys.toList()..sort();
    final focusedStaffIds = _focusedStaffProfileIds.toList()..sort();
    final workloadKey =
        "${_workUnitLabel.trim()}|${_totalWorkUnits ?? 0}|${_minStaffPerUnit ?? 0}|${_maxStaffPerUnit ?? 0}|$_activeStaffAvailabilityPercent|${_hasConfirmedWorkloadContext ? 1 : 0}";
    return "$estateId|$productKey|$dateMode|$_domainContext|${focusedRoles.join(",")}|${focusedStaffIds.join(",")}|$workloadKey";
  }

  Future<void> _tryAutoGenerateDraftFromContext({
    required String trigger,
    required bool inferredMode,
  }) async {
    AppDebug.log(
      _logTag,
      "auto_generate_disabled_for_redesign",
      extra: {"trigger": trigger, "inferredMode": inferredMode},
    );
  }

  String _resolveGuideQuestion() {
    final hasEstate = (_selectedEstateAssetId ?? "").trim().isNotEmpty;
    final hasProduct = _hasSelectedProduct();
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
    if (!_isWorkloadContextReadyForDraft()) {
      return _guideQuestionWorkload;
    }
    if (!hasResolvedDateMode) {
      return _guideQuestionDates;
    }
    return _guideQuestionReady;
  }

  String _defaultWorkUnitLabelForDomain(String rawDomain) {
    switch (normalizeProductionDomainContext(rawDomain)) {
      case productionDomainFarm:
        return "plot";
      case productionDomainManufacturing:
        return "batch";
      case productionDomainConstruction:
        return "zone";
      case productionDomainMedia:
        return "shoot block";
      case productionDomainFood:
        return "batch";
      case productionDomainCosmetics:
        return "batch";
      case productionDomainFashion:
        return "line";
      case productionDomainCustom:
      default:
        return "work unit";
    }
  }

  List<String> _workUnitOptionsForDomain(String rawDomain) {
    switch (normalizeProductionDomainContext(rawDomain)) {
      case productionDomainFarm:
        return const ["plot", "greenhouse", "acre block", "field strip"];
      case productionDomainManufacturing:
        return const ["batch", "line", "station"];
      case productionDomainConstruction:
        return const ["zone", "site section", "floor"];
      case productionDomainMedia:
        return const ["shoot block", "scene set", "segment"];
      case productionDomainFood:
        return const ["batch", "kitchen run", "prep block"];
      case productionDomainCosmetics:
        return const ["batch", "blend run", "pack run"];
      case productionDomainFashion:
        return const ["line", "bundle", "stitch block"];
      case productionDomainCustom:
      default:
        return const ["work unit", "job block", "task bundle"];
    }
  }

  bool _hasWorkloadContextValues() {
    return _workUnitLabel.trim().isNotEmpty &&
        (_totalWorkUnits ?? 0) > 0 &&
        (_minStaffPerUnit ?? 0) > 0 &&
        (_maxStaffPerUnit ?? 0) >= (_minStaffPerUnit ?? 0);
  }

  bool _isWorkloadContextReadyForDraft() {
    return _hasConfirmedWorkloadContext && _hasWorkloadContextValues();
  }

  int _resolveSafeMinStaffPerWorkUnit() {
    final configuredMin = _minStaffPerUnit ?? 0;
    return configuredMin < 1 ? 1 : configuredMin;
  }

  int _resolveSafeMaxStaffPerWorkUnit({required int safeMinStaffPerWorkUnit}) {
    final configuredMax = _maxStaffPerUnit ?? 0;
    final safeMax = configuredMax < 1 ? safeMinStaffPerWorkUnit : configuredMax;
    return safeMax < safeMinStaffPerWorkUnit
        ? safeMinStaffPerWorkUnit
        : safeMax;
  }

  String _resolveSafeWorkUnitLabelForStaffing() {
    final configuredLabel = _workUnitLabel.trim();
    if (configuredLabel.isNotEmpty) {
      return configuredLabel;
    }
    return _defaultWorkUnitLabelForDomain(_domainContext);
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
    required Map<String, int> roleRoundRobinCursorByRole,
  }) {
    final safeHeadcount = requiredHeadcount < 1 ? 1 : requiredHeadcount;
    final roleMatches =
        focusedStaffIdsByRole[normalizedRole] ?? const <String>[];
    if (roleMatches.isNotEmpty) {
      // WHY: Round-robin prevents deterministic first-N bias across same-role tasks.
      final poolSize = roleMatches.length;
      final assignmentCount = safeHeadcount <= poolSize
          ? safeHeadcount
          : poolSize;
      final startIndex = roleRoundRobinCursorByRole[normalizedRole] ?? 0;
      final selected = <String>[];
      for (int offset = 0; offset < assignmentCount; offset += 1) {
        final roleIndex = (startIndex + offset) % poolSize;
        selected.add(roleMatches[roleIndex]);
      }
      roleRoundRobinCursorByRole[normalizedRole] =
          (startIndex + assignmentCount) % poolSize;
      return selected;
    }
    if (focusedStaffProfileIds.isEmpty) {
      // WHY: Even without focused staff context, keep assignment size bounded by requested headcount.
      final normalizedExisting = _normalizeDistinctProfileIds(
        existingAssignedIds,
      );
      return normalizedExisting.take(safeHeadcount).toList();
    }
    // WHY: Strict-role mode forbids cross-role fallback; leave task short and warn later.
    return const <String>[];
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
          taskType: task.taskType,
          sourceTemplateKey: task.sourceTemplateKey,
          recurrenceGroupKey: task.recurrenceGroupKey,
          occurrenceIndex: task.occurrenceIndex,
          startDate: task.startDate,
          dueDate: task.dueDate,
          assignedStaffProfileIds: task.assignedStaffProfileIds,
        );
      }).toList();
      return ProductionAssistantPlanPhase(
        name: phase.name,
        order: phase.order,
        estimatedDays: phase.estimatedDays,
        phaseType: phase.phaseType,
        requiredUnits: phase.requiredUnits,
        minRatePerFarmerHour: phase.minRatePerFarmerHour,
        targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
        plannedHoursPerDay: phase.plannedHoursPerDay,
        biologicalMinDays: phase.biologicalMinDays,
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
      plannerMeta: payload.plannerMeta,
      lifecycle: payload.lifecycle,
    );
  }

  ProductionAssistantPlanDraftPayload
  _sanitizePlanDraftPayloadForFocusedContext({
    required ProductionAssistantPlanDraftPayload payload,
  }) {
    final lifecycleNormalizedPayload = _normalizeLifecycleLabelsInDraftPayload(
      payload: payload,
    );
    final safeTotalWorkUnits = (_totalWorkUnits ?? 0) > 0
        ? (_totalWorkUnits ?? 1)
        : 1;
    final safeMinStaffPerWorkUnit = _resolveSafeMinStaffPerWorkUnit();
    final safeMaxStaffPerWorkUnit = _resolveSafeMaxStaffPerWorkUnit(
      safeMinStaffPerWorkUnit: safeMinStaffPerWorkUnit,
    );
    final safeWorkUnitLabel = _resolveSafeWorkUnitLabelForStaffing();
    final isFallbackStarterDraft = lifecycleNormalizedPayload.warnings.any((
      warning,
    ) {
      final warningCode = warning.code.trim().toUpperCase();
      final warningMessage = warning.message.trim().toLowerCase();
      return warningCode == "DAILY_FALLBACK_GENERATED" ||
          warningMessage.contains("safe starter draft") ||
          warningMessage.contains("no scheduled tasks") ||
          warningMessage.contains("could not be parsed");
    });
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
    final shouldEnforceFocusedScope =
        focusedRoleSet.isNotEmpty || focusedStaffProfileIds.isNotEmpty;
    final focusedStaffIdsByRole = shouldEnforceFocusedScope
        ? _buildFocusedStaffIdsByRole(
            estateScopedStaffProfiles: _staffForSelectedEstate(
              staffProfiles:
                  ref.read(productionStaffProvider).valueOrNull ??
                  const <BusinessStaffProfileSummary>[],
            ),
            focusedStaffProfileIds: focusedStaffProfileIds,
          )
        : const <String, List<String>>{};
    var didMutate = false;
    var roleReplacementCount = 0;
    var assignmentReplacementCount = 0;
    var headcountNormalizationCount = 0;
    var workloadBoundsAdjustmentCount = 0;
    var minStaffShortageCount = 0;
    var managementCoverageGapCount = 0;
    var managementOversightInjectedCount = 0;
    var fallbackThroughputBoostTaskCount = 0;
    var stageGateResequencedTaskCount = 0;
    var stageGateBlockedTaskCount = 0;
    var stageGateAutofilledSlotCount = 0;
    final selectedFocusedStaffCount = focusedStaffProfileIds.length;
    // WHY: Persist cursor across all tasks so same-role allocation rotates fairly.
    final roleRoundRobinCursorByRole = <String, int>{};
    final managementRoleTitleByRole = <String, String>{
      _normalizeRoleKey(staffRoleFarmManager):
          "Weekly farm operations supervision",
      _normalizeRoleKey(staffRoleEstateManager):
          "Weekly estate operations oversight",
      _normalizeRoleKey(staffRoleAssetManager):
          "Weekly asset readiness and utilization review",
    };

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
        final normalizedHeadcount = task.requiredHeadcount < 1
            ? 1
            : task.requiredHeadcount;
        final normalizedAssignedIdsBefore = _normalizeDistinctProfileIds(
          task.assignedStaffProfileIds,
        );
        // WHY: Enforce workload staffing limits so weak assistant output is corrected before preview/editor.
        var boundedHeadcount = normalizedHeadcount
            .clamp(safeMinStaffPerWorkUnit, safeMaxStaffPerWorkUnit)
            .toInt();
        final rolePoolSize =
            (focusedStaffIdsByRole[resolvedRole] ?? const <String>[]).length;
        final isManagementRole = managementRoleTitleByRole.containsKey(
          resolvedRole,
        );
        if (isFallbackStarterDraft && !isManagementRole && rolePoolSize > 0) {
          // WHY: Safe fallback drafts often under-estimate headcount; use active role capacity to improve delivery speed realism.
          final activeRoleStaff =
              ((rolePoolSize * _activeStaffAvailabilityPercent) / 100)
                  .ceil()
                  .clamp(1, rolePoolSize)
                  .toInt();
          final throughputHeadcount = activeRoleStaff
              .clamp(safeMinStaffPerWorkUnit, safeMaxStaffPerWorkUnit)
              .toInt();
          if (throughputHeadcount > boundedHeadcount) {
            boundedHeadcount = throughputHeadcount;
            fallbackThroughputBoostTaskCount += 1;
          }
        }
        final resolvedAssignedIds = _resolveFocusedIdsForTask(
          normalizedRole: resolvedRole,
          requiredHeadcount: boundedHeadcount,
          existingAssignedIds: task.assignedStaffProfileIds,
          focusedStaffIdsByRole: focusedStaffIdsByRole,
          focusedStaffProfileIds: focusedStaffProfileIds,
          roleRoundRobinCursorByRole: roleRoundRobinCursorByRole,
        );
        final cappedAssignedIds =
            resolvedAssignedIds.length > safeMaxStaffPerWorkUnit
            ? resolvedAssignedIds.take(safeMaxStaffPerWorkUnit).toList()
            : resolvedAssignedIds;
        if (cappedAssignedIds.length < safeMinStaffPerWorkUnit) {
          minStaffShortageCount += 1;
        }
        final resolvedHeadcount = cappedAssignedIds.length > boundedHeadcount
            ? cappedAssignedIds.length
            : boundedHeadcount;
        final roleChanged = resolvedRole != originalRole;
        final assignmentChanged = !_hasSameNormalizedIds(
          task.assignedStaffProfileIds,
          cappedAssignedIds,
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
        if (headcountChanged) {
          headcountNormalizationCount += 1;
        }
        final staffingRangeAdjusted =
            headcountChanged ||
            (normalizedAssignedIdsBefore.length > safeMaxStaffPerWorkUnit &&
                cappedAssignedIds.length <= safeMaxStaffPerWorkUnit) ||
            (normalizedAssignedIdsBefore.length < safeMinStaffPerWorkUnit &&
                cappedAssignedIds.length >= safeMinStaffPerWorkUnit);
        if (staffingRangeAdjusted) {
          workloadBoundsAdjustmentCount += 1;
        }
        return ProductionAssistantPlanTask(
          title: task.title,
          roleRequired: resolvedRole,
          requiredHeadcount: resolvedHeadcount,
          weight: task.weight,
          instructions: task.instructions,
          taskType: task.taskType,
          sourceTemplateKey: task.sourceTemplateKey,
          recurrenceGroupKey: task.recurrenceGroupKey,
          occurrenceIndex: task.occurrenceIndex,
          startDate: task.startDate,
          dueDate: task.dueDate,
          assignedStaffProfileIds: cappedAssignedIds,
        );
      }).toList();
      return ProductionAssistantPlanPhase(
        name: phase.name,
        order: phase.order,
        estimatedDays: phase.estimatedDays,
        phaseType: phase.phaseType,
        requiredUnits: phase.requiredUnits,
        minRatePerFarmerHour: phase.minRatePerFarmerHour,
        targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
        plannedHoursPerDay: phase.plannedHoursPerDay,
        biologicalMinDays: phase.biologicalMinDays,
        tasks: updatedTasks,
      );
    }).toList();

    var enforcedPhases = updatedPhases;
    final selectedManagementRoles = managementRoleTitleByRole.keys.where((
      roleKey,
    ) {
      return focusedRoleSet.contains(roleKey) &&
          (focusedStaffIdsByRole[roleKey] ?? const <String>[]).isNotEmpty;
    }).toList()..sort();
    if (selectedManagementRoles.isNotEmpty && enforcedPhases.isNotEmpty) {
      final parsedRangeStart = DateTime.tryParse(
        lifecycleNormalizedPayload.startDate,
      );
      final parsedRangeEnd = DateTime.tryParse(
        lifecycleNormalizedPayload.endDate,
      );
      final rangeStart = parsedRangeStart == null
          ? null
          : DateTime(
              parsedRangeStart.year,
              parsedRangeStart.month,
              parsedRangeStart.day,
            );
      final rangeEnd = parsedRangeEnd == null
          ? null
          : DateTime(
              parsedRangeEnd.year,
              parsedRangeEnd.month,
              parsedRangeEnd.day,
            );
      final weekKeysToEvaluate = <String>{};
      if (rangeStart != null &&
          rangeEnd != null &&
          !rangeStart.isAfter(rangeEnd)) {
        // WHY: Weekly manager oversight should be explicit for each production week.
        var weekCursor = _startOfWeekMonday(rangeStart);
        while (!weekCursor.isAfter(rangeEnd)) {
          weekKeysToEvaluate.add(formatDateInput(weekCursor));
          weekCursor = weekCursor.add(const Duration(days: 7));
        }
      }
      final coveredRolesByWeek = <String, Set<String>>{};
      for (final phase in enforcedPhases) {
        for (final task in phase.tasks) {
          if (task.startDate == null) {
            continue;
          }
          final taskRoleKey = _normalizeRoleKey(task.roleRequired);
          if (!selectedManagementRoles.contains(taskRoleKey)) {
            continue;
          }
          final taskDate = task.startDate!.toLocal();
          final dayDate = DateTime(taskDate.year, taskDate.month, taskDate.day);
          final weekKey = formatDateInput(_startOfWeekMonday(dayDate));
          coveredRolesByWeek
              .putIfAbsent(weekKey, () => <String>{})
              .add(taskRoleKey);
          weekKeysToEvaluate.add(weekKey);
        }
      }
      for (final weekKey in weekKeysToEvaluate.toList()..sort()) {
        final weekStart = DateTime.tryParse(weekKey);
        if (weekStart == null) {
          continue;
        }
        var taskDay = DateTime(weekStart.year, weekStart.month, weekStart.day);
        if (rangeStart != null && taskDay.isBefore(rangeStart)) {
          taskDay = rangeStart;
        }
        if (rangeEnd != null && taskDay.isAfter(rangeEnd)) {
          continue;
        }
        final weekCoverage = coveredRolesByWeek.putIfAbsent(
          weekKey,
          () => <String>{},
        );
        for (final managementRole in selectedManagementRoles) {
          if (weekCoverage.contains(managementRole)) {
            continue;
          }
          managementCoverageGapCount += 1;
          final oversightTitle =
              managementRoleTitleByRole[managementRole] ??
              "Weekly management oversight";
          final oversightStart = DateTime(
            taskDay.year,
            taskDay.month,
            taskDay.day,
            8,
            0,
          );
          final oversightDue = DateTime(
            taskDay.year,
            taskDay.month,
            taskDay.day,
            9,
            0,
          );
          final boundedOversightHeadcount = safeMinStaffPerWorkUnit
              .clamp(safeMinStaffPerWorkUnit, safeMaxStaffPerWorkUnit)
              .toInt();
          final oversightAssignedIds = _resolveFocusedIdsForTask(
            normalizedRole: managementRole,
            requiredHeadcount: boundedOversightHeadcount,
            existingAssignedIds: const <String>[],
            focusedStaffIdsByRole: focusedStaffIdsByRole,
            focusedStaffProfileIds: focusedStaffProfileIds,
            roleRoundRobinCursorByRole: roleRoundRobinCursorByRole,
          );
          final cappedOversightAssignedIds =
              oversightAssignedIds.length > safeMaxStaffPerWorkUnit
              ? oversightAssignedIds.take(safeMaxStaffPerWorkUnit).toList()
              : oversightAssignedIds;
          if (cappedOversightAssignedIds.length < safeMinStaffPerWorkUnit) {
            minStaffShortageCount += 1;
          }
          final resolvedOversightHeadcount =
              cappedOversightAssignedIds.length > boundedOversightHeadcount
              ? cappedOversightAssignedIds.length
              : boundedOversightHeadcount;
          final oversightTask = ProductionAssistantPlanTask(
            title: oversightTitle,
            roleRequired: managementRole,
            requiredHeadcount: resolvedOversightHeadcount,
            weight: 1,
            instructions:
                "Supervise active $safeWorkUnitLabel execution, review daily progress evidence, and confirm risk/asset readiness for this week.",
            taskType: "event",
            sourceTemplateKey:
                "management_weekly_oversight_${managementRole}_${oversightStart.millisecondsSinceEpoch}",
            recurrenceGroupKey: "management_weekly_oversight_$managementRole",
            occurrenceIndex: oversightStart.day,
            startDate: oversightStart,
            dueDate: oversightDue,
            assignedStaffProfileIds: cappedOversightAssignedIds,
          );
          final targetPhase = enforcedPhases.first;
          final targetTasks = <ProductionAssistantPlanTask>[
            ...targetPhase.tasks,
            oversightTask,
          ];
          final updatedTargetPhase = ProductionAssistantPlanPhase(
            name: targetPhase.name,
            order: targetPhase.order,
            estimatedDays: targetPhase.estimatedDays,
            phaseType: targetPhase.phaseType,
            requiredUnits: targetPhase.requiredUnits,
            minRatePerFarmerHour: targetPhase.minRatePerFarmerHour,
            targetRatePerFarmerHour: targetPhase.targetRatePerFarmerHour,
            plannedHoursPerDay: targetPhase.plannedHoursPerDay,
            biologicalMinDays: targetPhase.biologicalMinDays,
            tasks: targetTasks,
          );
          enforcedPhases = <ProductionAssistantPlanPhase>[
            updatedTargetPhase,
            ...enforcedPhases.skip(1),
          ];
          weekCoverage.add(managementRole);
          managementOversightInjectedCount += 1;
          workloadBoundsAdjustmentCount += 1;
          didMutate = true;
        }
      }
    }
    if (enforcedPhases.isNotEmpty) {
      final stageGateResequenceResult = _resequencePlanDraftForStageGate(
        phases: enforcedPhases,
        safeTotalWorkUnits: safeTotalWorkUnits,
        safeMinStaffPerWorkUnit: safeMinStaffPerWorkUnit,
      );
      enforcedPhases = stageGateResequenceResult.phases;
      stageGateResequencedTaskCount =
          stageGateResequenceResult.resequencedTaskCount;
      stageGateBlockedTaskCount = stageGateResequenceResult.blockedTaskCount;
      stageGateAutofilledSlotCount =
          stageGateResequenceResult.autofilledBlockedSlotCount;
      if (stageGateResequencedTaskCount > 0) {
        didMutate = true;
      }
    }

    final warningKeys = lifecycleNormalizedPayload.warnings
        .map((warning) => warning.code.trim().toLowerCase())
        .toSet();
    final warnings = <ProductionAssistantPlanWarning>[
      ...lifecycleNormalizedPayload.warnings,
    ];
    if (shouldEnforceFocusedScope &&
        (roleReplacementCount > 0 || assignmentReplacementCount > 0) &&
        !warningKeys.contains(_focusedRoleScopeEnforcedWarningCode)) {
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _focusedRoleScopeEnforcedWarningCode,
          message:
              "Adjusted $roleReplacementCount tasks to selected roles and refreshed $assignmentReplacementCount staff assignments from focused IDs.",
        ),
      );
      warningKeys.add(_focusedRoleScopeEnforcedWarningCode);
    }
    if (managementOversightInjectedCount > 0 &&
        !warningKeys.contains(_managementCoverageEnforcedWarningCode)) {
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _managementCoverageEnforcedWarningCode,
          message:
              "Added $managementOversightInjectedCount weekly management oversight tasks for selected manager roles to preserve supervision cadence.",
        ),
      );
      warningKeys.add(_managementCoverageEnforcedWarningCode);
    }
    if (managementCoverageGapCount > managementOversightInjectedCount &&
        !warningKeys.contains(_managementCoverageMissingWarningCode)) {
      final uncoveredCount =
          managementCoverageGapCount - managementOversightInjectedCount;
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _managementCoverageMissingWarningCode,
          message:
              "Management coverage warning: $uncoveredCount weekly manager oversight slots are still missing. Add manager staff IDs or relax role focus.",
        ),
      );
      warningKeys.add(_managementCoverageMissingWarningCode);
    }
    if (fallbackThroughputBoostTaskCount > 0 &&
        !warningKeys.contains(_fallbackThroughputBoostWarningCode)) {
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _fallbackThroughputBoostWarningCode,
          message:
              "Fallback staffing boost applied on $fallbackThroughputBoostTaskCount execution tasks using $_activeStaffAvailabilityPercent% active role capacity to improve timeline realism.",
        ),
      );
      warningKeys.add(_fallbackThroughputBoostWarningCode);
    }
    if (stageGateResequencedTaskCount > 0 &&
        !warningKeys.contains(_stageGateResequencedWarningCode)) {
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _stageGateResequencedWarningCode,
          message:
              "Resequenced $stageGateResequencedTaskCount execution tasks to keep prerequisite work ahead of dependent tasks for realistic flow.",
        ),
      );
      warningKeys.add(_stageGateResequencedWarningCode);
    }
    if (stageGateAutofilledSlotCount > 0 &&
        !warningKeys.contains(_stageGateAutofillWarningCode)) {
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _stageGateAutofillWarningCode,
          message:
              "Converted $stageGateAutofilledSlotCount blocked downstream slots into prerequisite blocks to keep simulation practical.",
        ),
      );
      warningKeys.add(_stageGateAutofillWarningCode);
    }
    if (stageGateBlockedTaskCount > 0 &&
        !warningKeys.contains(_stageGateBlockedWarningCode)) {
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _stageGateBlockedWarningCode,
          message:
              "Stage-gate warning: $stageGateBlockedTaskCount downstream blocks still have limited unlock from prerequisite coverage. Add more prerequisite slots or extend timeline.",
        ),
      );
      warningKeys.add(_stageGateBlockedWarningCode);
    }
    if (workloadBoundsAdjustmentCount > 0 &&
        !warningKeys.contains(_workloadStaffingBoundsWarningCode)) {
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _workloadStaffingBoundsWarningCode,
          message:
              "Enforced staffing bounds on $workloadBoundsAdjustmentCount tasks: each scheduled $safeWorkUnitLabel block now targets between $safeMinStaffPerWorkUnit and $safeMaxStaffPerWorkUnit staff.",
        ),
      );
      warningKeys.add(_workloadStaffingBoundsWarningCode);
    }
    if (minStaffShortageCount > 0 &&
        !warningKeys.contains(_workloadStaffingShortageWarningCode)) {
      final shortageContext = selectedFocusedStaffCount == 0
          ? "No selected staff IDs were available for assignment."
          : "Only $selectedFocusedStaffCount selected staff IDs were available.";
      warnings.add(
        ProductionAssistantPlanWarning(
          code: _workloadStaffingShortageWarningCode,
          message:
              "Staffing warning: $minStaffShortageCount tasks are still below the minimum of $safeMinStaffPerWorkUnit staff per $safeWorkUnitLabel. $shortageContext Select more staff IDs or reduce the minimum.",
        ),
      );
      warningKeys.add(_workloadStaffingShortageWarningCode);
    }

    if (!didMutate &&
        warnings.length == lifecycleNormalizedPayload.warnings.length) {
      return lifecycleNormalizedPayload;
    }
    final didFocusedScopeMutate =
        shouldEnforceFocusedScope &&
        (roleReplacementCount > 0 || assignmentReplacementCount > 0);
    final enforcementLogEvent = managementOversightInjectedCount > 0
        ? _managementCoverageEnforcedLog
        : didFocusedScopeMutate
        ? _focusedDraftEnforcedLog
        : _staffingBoundsEnforcedLog;
    AppDebug.log(
      _logTag,
      enforcementLogEvent,
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
        "headcountNormalizationCount": headcountNormalizationCount,
        "workloadBoundsAdjustmentCount": workloadBoundsAdjustmentCount,
        "minStaffShortageCount": minStaffShortageCount,
        "managementCoverageGapCount": managementCoverageGapCount,
        "managementOversightInjectedCount": managementOversightInjectedCount,
        "isFallbackStarterDraft": isFallbackStarterDraft,
        "fallbackThroughputBoostTaskCount": fallbackThroughputBoostTaskCount,
        "stageGateResequencedTaskCount": stageGateResequencedTaskCount,
        "stageGateBlockedTaskCount": stageGateBlockedTaskCount,
        "stageGateAutofilledSlotCount": stageGateAutofilledSlotCount,
        "safeTotalWorkUnits": safeTotalWorkUnits,
        "safeMinStaffPerWorkUnit": safeMinStaffPerWorkUnit,
        "safeMaxStaffPerWorkUnit": safeMaxStaffPerWorkUnit,
        "safeWorkUnitLabel": safeWorkUnitLabel,
        "focusedRoleCount": focusedRoleKeys.length,
        "focusedStaffCount": focusedStaffProfileIds.length,
        "roundRobinRoleCount": roleRoundRobinCursorByRole.length,
        "nextAction": stageGateBlockedTaskCount > 0
            ? "Add more prerequisite capacity or extend timeline for blocked downstream slots."
            : managementCoverageGapCount > managementOversightInjectedCount
            ? "Add manager staff IDs or relax manager role focus for weekly oversight coverage."
            : minStaffShortageCount > 0
            ? "Select more staff IDs or reduce min staff per work unit."
            : "Preview draft and confirm schedule.",
      },
    );
    return ProductionAssistantPlanDraftPayload(
      productId: lifecycleNormalizedPayload.productId,
      productName: lifecycleNormalizedPayload.productName,
      startDate: lifecycleNormalizedPayload.startDate,
      endDate: lifecycleNormalizedPayload.endDate,
      days: lifecycleNormalizedPayload.days,
      weeks: lifecycleNormalizedPayload.weeks,
      phases: didMutate ? enforcedPhases : lifecycleNormalizedPayload.phases,
      warnings: warnings,
      plannerMeta: lifecycleNormalizedPayload.plannerMeta,
      lifecycle: lifecycleNormalizedPayload.lifecycle,
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
    if (!_hasSelectedProduct()) {
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

  void _onWorkUnitLabelChanged(String value) {
    final nextValue = value.trim();
    setState(() {
      _workUnitLabel = nextValue;
      _hasConfirmedWorkloadContext = false;
      _lastAutoGenerateKey = "";
    });
    AppDebug.log(
      _logTag,
      _workloadContextUpdateLog,
      extra: {
        "field": "workUnitLabel",
        "value": nextValue,
        "hasConfirmedWorkloadContext": _hasConfirmedWorkloadContext,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _onTotalWorkUnitsChanged(int? value) {
    final safeValue = value == null || value < 1 ? null : value;
    setState(() {
      _totalWorkUnits = safeValue;
      _hasConfirmedWorkloadContext = false;
      _lastAutoGenerateKey = "";
    });
    AppDebug.log(
      _logTag,
      _workloadContextUpdateLog,
      extra: {
        "field": "totalWorkUnits",
        "value": _totalWorkUnits ?? 0,
        "hasConfirmedWorkloadContext": _hasConfirmedWorkloadContext,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _onMinStaffPerUnitChanged(int? value) {
    final safeValue = value == null || value < 1 ? null : value;
    setState(() {
      _minStaffPerUnit = safeValue;
      if (safeValue != null &&
          _maxStaffPerUnit != null &&
          (_maxStaffPerUnit ?? 0) < safeValue) {
        _maxStaffPerUnit = safeValue;
      }
      _hasConfirmedWorkloadContext = false;
      _lastAutoGenerateKey = "";
    });
    AppDebug.log(
      _logTag,
      _workloadContextUpdateLog,
      extra: {
        "field": "minStaffPerUnit",
        "value": _minStaffPerUnit ?? 0,
        "hasConfirmedWorkloadContext": _hasConfirmedWorkloadContext,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _onMaxStaffPerUnitChanged(int? value) {
    final safeValue = value == null || value < 1 ? null : value;
    setState(() {
      if (safeValue != null &&
          _minStaffPerUnit != null &&
          safeValue < (_minStaffPerUnit ?? 0)) {
        _maxStaffPerUnit = _minStaffPerUnit;
      } else {
        _maxStaffPerUnit = safeValue;
      }
      _hasConfirmedWorkloadContext = false;
      _lastAutoGenerateKey = "";
    });
    AppDebug.log(
      _logTag,
      _workloadContextUpdateLog,
      extra: {
        "field": "maxStaffPerUnit",
        "value": _maxStaffPerUnit ?? 0,
        "hasConfirmedWorkloadContext": _hasConfirmedWorkloadContext,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _onActiveStaffAvailabilityPercentChanged(int value) {
    final safeValue = value.clamp(40, 100);
    setState(() {
      _activeStaffAvailabilityPercent = safeValue;
      _hasConfirmedWorkloadContext = false;
      _lastAutoGenerateKey = "";
    });
    AppDebug.log(
      _logTag,
      _workloadContextUpdateLog,
      extra: {
        "field": "activeStaffAvailabilityPercent",
        "value": _activeStaffAvailabilityPercent,
        "hasConfirmedWorkloadContext": _hasConfirmedWorkloadContext,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
  }

  void _confirmWorkloadContext() {
    if (!_hasWorkloadContextValues()) {
      _showSnack(_contextPromptConfirmWorkloadContextMissing);
      return;
    }
    setState(() {
      _hasConfirmedWorkloadContext = true;
      _lastAutoGenerateKey = "";
    });
    _appendMessage(
      _ChatMessage(
        fromAssistant: false,
        text:
            "Workload: ${_totalWorkUnits ?? 0} ${_workUnitLabel.trim()} units, min ${_minStaffPerUnit ?? 0} and max ${_maxStaffPerUnit ?? 0} staff per unit, $_activeStaffAvailabilityPercent% active staff assumption.",
      ),
    );
    AppDebug.log(
      _logTag,
      _workloadContextConfirmLog,
      extra: {
        "workUnitLabel": _workUnitLabel.trim(),
        "totalWorkUnits": _totalWorkUnits ?? 0,
        "minStaffPerUnit": _minStaffPerUnit ?? 0,
        "maxStaffPerUnit": _maxStaffPerUnit ?? 0,
        "activeStaffAvailabilityPercent": _activeStaffAvailabilityPercent,
      },
    );
    _appendAssistantMessageOnce(_resolveGuideQuestion());
    _tryAutoGenerateDraftFromContext(
      trigger: "workload_context_confirmed",
      inferredMode: _useAiInferredDates,
    );
  }

  void _onDomainContextChanged(String? value) {
    final nextDomain = normalizeProductionDomainContext(value);
    if (nextDomain == _domainContext && _domainExplicitlySelected) {
      return;
    }
    setState(() {
      final previousDomain = _domainContext;
      _domainContext = nextDomain;
      _domainExplicitlySelected = true;
      final previousDefaultWorkUnit = _defaultWorkUnitLabelForDomain(
        previousDomain,
      );
      if (_workUnitLabel.trim().isEmpty ||
          _workUnitLabel.trim() == previousDefaultWorkUnit) {
        _workUnitLabel = _defaultWorkUnitLabelForDomain(nextDomain);
      }
      _hasConfirmedWorkloadContext = false;
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
      const _ChatMessage(
        fromAssistant: false,
        text: "Use lifecycle-based dates.",
      ),
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
      _workUnitLabel = _defaultWorkUnitLabelForDomain(_domainContext);
      _totalWorkUnits = 10;
      _minStaffPerUnit = 1;
      _maxStaffPerUnit = 3;
      _activeStaffAvailabilityPercent = 70;
      _hasConfirmedWorkloadContext = false;
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

  Future<void> _openPlannerCropSearch() async {
    AppDebug.log(_logTag, _plannerCropSearchTapLog);
    final selected = await _showPlannerCropSearchSheet();
    if (selected == null) {
      return;
    }
    final selectedProductId = await _autoCreateBusinessProductForPlannerCrop(
      selected: selected,
    );
    if (!mounted) {
      return;
    }
    if ((selectedProductId ?? "").trim().isEmpty) {
      return;
    }
    _selectedPlannerCatalogItem = selected;
    AppDebug.log(
      _logTag,
      _plannerCropSearchSelectLog,
      extra: {
        "cropKey": selected.cropKey,
        "productName": selected.name,
        "linkedProductId": selected.linkedProductId,
        "resolvedProductId":
            selectedProductId ??
            (selected.linkedProductId.trim().isEmpty
                ? null
                : selected.linkedProductId.trim()),
      },
    );
    _onProductChanged(
      productId: selectedProductId,
      productName: selected.name,
      productLifecycleLabel: selected.lifecycleLabel,
      productSourceLabel: _resolveProductSourceLabel(selected.source),
    );
    await _resolveSelectedPlannerCropLifecycle(
      selected: selected,
      linkedProductIdOverride: selectedProductId,
    );
  }

  Future<ProductionAssistantCatalogItem?> _showPlannerCropSearchSheet() async {
    final initialQuery = _resolveSelectedProductName();
    final searchCtrl = TextEditingController(text: initialQuery);
    Timer? debounce;
    List<ProductionAssistantCatalogItem> results =
        const <ProductionAssistantCatalogItem>[];
    bool isLoading = false;
    bool hasInitialized = false;
    String? errorText;

    Future<void> runSearch(
      String rawQuery,
      void Function(VoidCallback fn) setModalState,
    ) async {
      final query = rawQuery.trim();
      final shouldLoadFeatured = query.isEmpty;
      if (!shouldLoadFeatured &&
          query.length < _plannerCropSearchMinimumQueryLength) {
        setModalState(() {
          results = const <ProductionAssistantCatalogItem>[];
          isLoading = false;
          errorText = null;
        });
        return;
      }
      setModalState(() {
        isLoading = true;
        errorText = null;
      });
      try {
        final response = await ref
            .read(productionPlanActionsProvider)
            .searchAssistantCrops(
              query: shouldLoadFeatured ? "" : query,
              domainContext: _domainContext,
              estateAssetId: _selectedEstateAssetId,
              limit: 8,
            );
        if (!mounted) {
          return;
        }
        setModalState(() {
          results = response.items;
          isLoading = false;
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setModalState(() {
          results = const <ProductionAssistantCatalogItem>[];
          isLoading = false;
          errorText = _plannerCropSearchErrorState;
        });
      }
    }

    final selected = await showModalBottomSheet<ProductionAssistantCatalogItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!hasInitialized) {
              hasInitialized = true;
              Future<void>.microtask(
                () => runSearch(initialQuery, setModalState),
              );
            }
            final theme = Theme.of(context);
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: SizedBox(
                  height: 520,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _plannerCropSheetTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _plannerCropSheetHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          onChanged: (value) {
                            setModalState(() {});
                            debounce?.cancel();
                            debounce = Timer(
                              _plannerCropSearchDebounce,
                              () => runSearch(value, setModalState),
                            );
                          },
                          decoration: InputDecoration(
                            labelText: _plannerCropSearchFieldLabel,
                            hintText: _plannerCropSearchFieldHint,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      searchCtrl.clear();
                                      setModalState(() {});
                                      runSearch("", setModalState);
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              if (isLoading) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (errorText != null) {
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        errorText!,
                                        style: theme.textTheme.bodyMedium,
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton.tonal(
                                        onPressed: () => runSearch(
                                          searchCtrl.text,
                                          setModalState,
                                        ),
                                        child: const Text("Retry"),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              if (results.isEmpty) {
                                final normalizedQuery = searchCtrl.text.trim();
                                return Center(
                                  child: Text(
                                    normalizedQuery.isNotEmpty &&
                                            normalizedQuery.length <
                                                _plannerCropSearchMinimumQueryLength
                                        ? _plannerCropSearchMinimumState
                                        : _plannerCropSearchEmptyState,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }
                              return ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = results[index];
                                  final aliases = item.aliases
                                      .where(
                                        (alias) =>
                                            alias.trim().toLowerCase() !=
                                            item.name.trim().toLowerCase(),
                                      )
                                      .take(3)
                                      .join(", ");
                                  final phaseCount = item.phases.length;
                                  final cropTypeBits = <String>[
                                    if (item.category.trim().isNotEmpty)
                                      item.category.trim(),
                                    if (item.plantType.trim().isNotEmpty)
                                      item.plantType.trim(),
                                    if (item.variety.trim().isNotEmpty)
                                      item.variety.trim(),
                                  ];
                                  final identityBits = <String>[
                                    if (item.scientificName.trim().isNotEmpty)
                                      item.scientificName.trim(),
                                    if (item.family.trim().isNotEmpty)
                                      "Family: ${item.family.trim()}",
                                  ];
                                  final agronomyBits = <String>[
                                    if (item
                                        .climate
                                        .temperatureLabel
                                        .isNotEmpty)
                                      "Temp ${item.climate.temperatureLabel}",
                                    if (item.climate.rainfallLabel.isNotEmpty)
                                      "Rain ${item.climate.rainfallLabel}",
                                    if (item.climate.lightPreference
                                        .trim()
                                        .isNotEmpty)
                                      "Light ${item.climate.lightPreference.trim()}",
                                    if (item.soil.phLabel.isNotEmpty)
                                      "pH ${item.soil.phLabel}",
                                    if (item.water.requirement
                                        .trim()
                                        .isNotEmpty)
                                      "Water ${item.water.requirement.trim()}",
                                  ];
                                  final provenanceLabel = item
                                      .primarySourceLabel
                                      .trim();
                                  final verificationLabel =
                                      _resolveCropVerificationLabel(
                                        item.verificationStatus,
                                      );
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () =>
                                        Navigator.of(sheetContext).pop(item),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
                                        color: theme.colorScheme.surface,
                                      ),
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name,
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: theme
                                                      .colorScheme
                                                      .primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  item.lifecycleLabel,
                                                  style: theme
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .onPrimaryContainer,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            item.hasLinkedProduct
                                                ? "Already linked to your business"
                                                : provenanceLabel.isNotEmpty
                                                ? provenanceLabel
                                                : "Planner crop source",
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                          if (item.summary
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              item.summary.trim(),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                          if (cropTypeBits.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              cropTypeBits.join(" • "),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                          if (identityBits.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              identityBits.join(" • "),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                          if (verificationLabel.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              verificationLabel,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .secondary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                          if (agronomyBits.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              agronomyBits.take(3).join(" • "),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                          if (aliases.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              "Aliases: $aliases",
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                          if (phaseCount > 0) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              "$phaseCount lifecycle phases ready for planning",
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    debounce?.cancel();
    searchCtrl.dispose();
    return selected;
  }

  void _onProductChanged({
    required String? productId,
    required String productName,
    String productLifecycleLabel = "",
    String productSourceLabel = "",
  }) {
    final normalizedProductId = (productId ?? "").trim();
    final normalizedProductName = productName.trim();
    if ((_selectedProductId ?? "").trim() == normalizedProductId &&
        _selectedProductName.trim() == normalizedProductName) {
      return;
    }
    setState(() {
      _applySelectedProductState(
        productId: normalizedProductId,
        productName: normalizedProductName,
        productLifecycleLabel: productLifecycleLabel,
        productSourceLabel: productSourceLabel,
      );
      _hasConfirmedWorkloadContext = false;
      _lastAutoGenerateKey = "";
    });
    if (normalizedProductName.isNotEmpty) {
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
    final hasProduct = _hasSelectedProduct();
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
    await _ensureCurrentSelectedCropLinkedProduct(announceSuccess: false);
    if (!mounted) {
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
    if (!_isWorkloadContextReadyForDraft()) {
      _appendMessage(
        const _ChatMessage(
          fromAssistant: true,
          text: _guideQuestionWorkload,
          isError: true,
        ),
      );
      _showSnack(_contextPromptConfirmWorkloadContextMissing);
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
    await _runDirectDraftGeneration(
      prompt: prompt,
      productName: productName,
      focusedRoles: focusedRoles,
      focusedStaff: focusedStaff,
    );
  }

  // WHY: Workspace UI needs a deterministic alignment score even when only context is available.
  double _resolveWorkspaceAlignmentScore({
    required ProductionAssistantPlanDraftPayload? payload,
  }) {
    if (payload == null) {
      return 0.72;
    }
    final warningCount = payload.warnings.length;
    final baseScore = 0.86;
    final warningPenalty = (warningCount * 0.05).clamp(0.0, 0.4);
    final score = baseScore - warningPenalty;
    return score.clamp(0.4, 0.95);
  }

  // WHY: Left-side intelligence card needs one concise date-range label sourced from draft or manual context.
  String _resolveWorkspacePlanRangeLabel({
    required ProductionAssistantPlanDraftPayload? payload,
  }) {
    if (payload != null) {
      final start = DateTime.tryParse(payload.startDate);
      final end = DateTime.tryParse(payload.endDate);
      if (start != null && end != null) {
        return "${formatDateLabel(start)} -> ${formatDateLabel(end)}";
      }
    }
    if (_startDate != null && _endDate != null) {
      return "${formatDateLabel(_startDate)} -> ${formatDateLabel(_endDate)}";
    }
    return "Set dates or infer with AI";
  }

  List<_ChatMessage> _resolveWorkspaceRecentMessages() {
    if (_messages.length <= 4) {
      return List<_ChatMessage>.from(_messages);
    }
    return _messages.sublist(_messages.length - 4);
  }

  bool _hasResolvedDateMode() {
    return _useAiInferredDates || (_startDate != null && _endDate != null);
  }

  bool _hasDraftStudioContent(ProductionPlanDraftState draft) {
    return draft.phases.any((phase) => phase.tasks.isNotEmpty);
  }

  bool _hasStartedPlan(ProductionPlanDraftState draft) {
    return _domainExplicitlySelected ||
        (_selectedEstateAssetId ?? "").trim().isNotEmpty ||
        _hasSelectedProduct() ||
        _hasResolvedDateMode() ||
        _focusedRoleKeys.isNotEmpty ||
        _focusedStaffProfileIds.isNotEmpty ||
        _hasDraftStudioContent(draft);
  }

  List<_CreateWizardStep> _wizardSteps() {
    return _CreateWizardStep.values;
  }

  int _wizardStepNumber(_CreateWizardStep step) {
    return _wizardSteps().indexOf(step) + 1;
  }

  String _wizardStepTitle(_CreateWizardStep step) {
    switch (step) {
      case _CreateWizardStep.productionType:
        return "Production type";
      case _CreateWizardStep.estate:
        return "Estate / location";
      case _CreateWizardStep.crop:
        return "Crop / variety";
      case _CreateWizardStep.timing:
        return "Timing / workload";
      case _CreateWizardStep.people:
        return "People / resources";
      case _CreateWizardStep.review:
        return "Review & draft";
    }
  }

  String _wizardStepHint(_CreateWizardStep step) {
    switch (step) {
      case _CreateWizardStep.productionType:
        return "Choose the operating context so the planner speaks the right language.";
      case _CreateWizardStep.estate:
        return "Pick the estate or working location for this production cycle.";
      case _CreateWizardStep.crop:
        return "Search the planner crop database and lock the crop you want to plan.";
      case _CreateWizardStep.timing:
        return "Set lifecycle dates or exact dates, then define the workload assumptions.";
      case _CreateWizardStep.people:
        return "Focus the roles and staff that should anchor this plan.";
      case _CreateWizardStep.review:
        return "Confirm the setup, then generate the editable production timeline.";
    }
  }

  bool _isWizardStepComplete({
    required _CreateWizardStep step,
    required List<BusinessStaffProfileSummary> estateScopedStaffProfiles,
  }) {
    switch (step) {
      case _CreateWizardStep.productionType:
        return _domainExplicitlySelected;
      case _CreateWizardStep.estate:
        return (_selectedEstateAssetId ?? "").trim().isNotEmpty;
      case _CreateWizardStep.crop:
        return _hasSelectedProduct();
      case _CreateWizardStep.timing:
        return _isWorkloadContextReadyForDraft() && _hasResolvedDateMode();
      case _CreateWizardStep.people:
        if (estateScopedStaffProfiles.isEmpty) {
          return true;
        }
        return _isFocusedStaffContextReadyForDraft();
      case _CreateWizardStep.review:
        return false;
    }
  }

  bool _canOpenWizardStep({
    required _CreateWizardStep step,
    required List<BusinessStaffProfileSummary> estateScopedStaffProfiles,
  }) {
    final targetIndex = _wizardStepNumber(step) - 1;
    final steps = _wizardSteps();
    for (var index = 0; index < targetIndex; index++) {
      if (!_isWizardStepComplete(
        step: steps[index],
        estateScopedStaffProfiles: estateScopedStaffProfiles,
      )) {
        return false;
      }
    }
    return true;
  }

  Future<void> _advanceWizard({
    required List<BusinessStaffProfileSummary> estateScopedStaffProfiles,
    required String selectedEstateName,
    required String selectedProductName,
  }) async {
    switch (_currentWizardStep) {
      case _CreateWizardStep.productionType:
        if (!_domainExplicitlySelected) {
          _showSnack("Choose a production type first.");
          return;
        }
        setState(() {
          _currentWizardStep = _CreateWizardStep.estate;
        });
        return;
      case _CreateWizardStep.estate:
        if ((_selectedEstateAssetId ?? "").trim().isEmpty) {
          _showSnack("Choose an estate to continue.");
          return;
        }
        setState(() {
          _currentWizardStep = _CreateWizardStep.crop;
        });
        return;
      case _CreateWizardStep.crop:
        if (!_hasSelectedProduct()) {
          _showSnack("Select one crop from the planner database.");
          return;
        }
        if ((_selectedProductId ?? "").trim().isEmpty) {
          final linkedProductId = await _ensureCurrentSelectedCropLinkedProduct(
            announceSuccess: false,
          );
          if (!mounted) {
            return;
          }
          if ((linkedProductId ?? "").trim().isEmpty) {
            _showSnack(
              "Complete the farm product setup before moving to timing and workload.",
            );
            return;
          }
        }
        setState(() {
          _currentWizardStep = _CreateWizardStep.timing;
        });
        return;
      case _CreateWizardStep.timing:
        if (!_hasResolvedDateMode()) {
          _showSnack("Set dates now or choose lifecycle-based dates.");
          return;
        }
        if (!_hasWorkloadContextValues()) {
          _showSnack(_contextPromptConfirmWorkloadContextMissing);
          return;
        }
        _confirmWorkloadContext();
        if (!mounted) {
          return;
        }
        setState(() {
          _currentWizardStep = _CreateWizardStep.people;
        });
        return;
      case _CreateWizardStep.people:
        if (estateScopedStaffProfiles.isNotEmpty) {
          if (_focusedRoleKeys.isEmpty || _focusedStaffProfileIds.isEmpty) {
            _showSnack("Pick the roles and staff to prioritize.");
            return;
          }
          _confirmFocusedStaffContext();
          if (!mounted) {
            return;
          }
        }
        await _ensureCurrentSelectedCropLinkedProduct(announceSuccess: false);
        if (!mounted) {
          return;
        }
        if ((_selectedProductId ?? "").trim().isEmpty) {
          _showSnack(
            "Complete the farm product setup before opening the review step.",
          );
          return;
        }
        setState(() {
          _currentWizardStep = _CreateWizardStep.review;
        });
        return;
      case _CreateWizardStep.review:
        await _generateDraftFromContext(
          estateName: selectedEstateName,
          productName: selectedProductName,
        );
        return;
    }
  }

  void _goBackWizard() {
    final currentIndex = _wizardStepNumber(_currentWizardStep) - 1;
    if (currentIndex <= 0) {
      return;
    }
    setState(() {
      _currentWizardStep = _wizardSteps()[currentIndex - 1];
    });
  }

  void _jumpToWizardStep({
    required _CreateWizardStep step,
    required List<BusinessStaffProfileSummary> estateScopedStaffProfiles,
  }) {
    if (!_canOpenWizardStep(
      step: step,
      estateScopedStaffProfiles: estateScopedStaffProfiles,
    )) {
      return;
    }
    setState(() {
      _currentWizardStep = step;
    });
  }

  Future<void> _openAiCopilot({
    required bool hasDraftStudioContent,
    required String selectedEstateName,
    required String selectedProductName,
  }) async {
    final panel = _AiCopilotSheet(
      selectedEstateName: selectedEstateName,
      selectedProductName: selectedProductName,
      selectedProductLifecycleLabel: _selectedProductLifecycleLabel,
      latestAssistantMessage: _lastTurn?.message ?? "",
      hasDraft: hasDraftStudioContent,
      canGenerateDraft:
          !_isSending &&
          (_selectedEstateAssetId ?? "").trim().isNotEmpty &&
          _hasSelectedProduct(),
      onSearchCrop: () async {
        await _openPlannerCropSearch();
      },
      onUseLifecycleDates: () async {
        _skipDateSelectionAndInfer();
      },
      onGenerateDraft: () async {
        await _generateDraftFromContext(
          estateName: selectedEstateName,
          productName: selectedProductName,
        );
      },
      onPreviewDraft: _lastTurn?.planDraftPayload == null
          ? null
          : () async {
              await _previewDraftProductionSchedule(
                _lastTurn!.planDraftPayload!,
              );
            },
      onStartManualDraft: () async {
        await _openManualEditor();
      },
    );

    if (!mounted) {
      return;
    }

    final width = MediaQuery.of(context).size.width;
    if (width >= _assistantDesktopLayoutBreakpoint) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Close AI copilot",
        barrierColor: Colors.black54,
        pageBuilder: (_, __, ___) {
          return SafeArea(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(width: 420, child: panel),
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: panel,
          ),
        );
      },
    );
  }

  Future<void> _applyDraftToStudio(
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
            phaseType: phase.phaseType,
            requiredUnits: phase.requiredUnits,
            minRatePerFarmerHour: phase.minRatePerFarmerHour,
            targetRatePerFarmerHour: phase.targetRatePerFarmerHour,
            plannedHoursPerDay: phase.plannedHoursPerDay,
            biologicalMinDays: phase.biologicalMinDays,
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
                    taskType: entry.value.taskType,
                    sourceTemplateKey: entry.value.sourceTemplateKey,
                    recurrenceGroupKey: entry.value.recurrenceGroupKey,
                    occurrenceIndex: entry.value.occurrenceIndex,
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
    final notes = <String>[
      if ((_lastTurn?.message ?? "").trim().isNotEmpty)
        _lastTurn!.message.trim(),
      if (riskNotes.isNotEmpty)
        "Review notes: ${riskNotes.take(3).join(" • ")}",
    ].join("\n\n");
    final nextState = ProductionPlanDraftState(
      title:
          "${scopedPayload.productName.isEmpty ? 'Production' : scopedPayload.productName} Plan",
      notes: notes,
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
    _syncDraftEditors(nextState);
    if (!mounted) {
      return;
    }
    setState(() {
      _showDraftStudio = true;
      _draftStudioPanel = _DraftStudioPanel.overview;
      _lastDraftImprovementReport = null;
    });
  }

  Future<void> _saveDraftPlan() async {
    if (_isSending) {
      return;
    }
    final controller = ref.read(productionPlanDraftProvider.notifier);
    final errors = controller.validate();
    if (errors.isNotEmpty) {
      _showSnack(errors.first);
      return;
    }

    setState(() {
      _isSending = true;
    });
    try {
      final detail = await ref
          .read(productionPlanActionsProvider)
          .createPlan(payload: controller.toPayload());
      controller.reset();
      if (!mounted) {
        return;
      }
      _showSnack("Plan created successfully.");
      context.go(productionPlanDetailPath(detail.plan.id));
    } catch (error) {
      AppDebug.log(
        _logTag,
        "save_plan_failed",
        extra: {"error": error.toString()},
      );
      if (mounted) {
        _showSnack("Unable to create plan.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _buildLog);
    final theme = Theme.of(context);
    if (_isInitializingSession) {
      return Scaffold(
        appBar: AppBar(title: const Text("New production plan")),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surfaceContainerLowest,
                theme.colorScheme.surface,
                theme.colorScheme.surfaceContainerHigh,
              ],
            ),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final draft = ref.watch(productionPlanDraftProvider);
    _syncDraftEditors(draft);
    final assetsAsync = ref.watch(
      businessAssetsProvider(
        const BusinessAssetsQuery(page: _queryPage, limit: _queryLimit),
      ),
    );
    final staffAsync = ref.watch(productionStaffProvider);
    final staffList =
        staffAsync.valueOrNull ?? const <BusinessStaffProfileSummary>[];
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
    final estateOptions = estateNamesById.entries.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    final selectedProductName = _resolveSelectedProductName();
    final estateScopedStaffProfiles = staffAsync.maybeWhen(
      data: (staffProfiles) =>
          _staffForSelectedEstate(staffProfiles: staffProfiles),
      orElse: () => const <BusinessStaffProfileSummary>[],
    );
    final availableFocusedRoleKeys = _availableFocusedRoleKeysForEstate(
      estateScopedStaff: estateScopedStaffProfiles,
    );
    final hasDraftStudio = _showDraftStudio || _hasDraftStudioContent(draft);
    final hasStartedPlan = _hasStartedPlan(draft);
    final selectedFocusedRoles = _focusedRoleKeys.toList()..sort();
    final latestPlanDraft = _lastTurn?.planDraftPayload;

    String domainDescription(String value) {
      switch (normalizeProductionDomainContext(value)) {
        case productionDomainFarm:
          return "Crops, orchards, greenhouse cycles, nursery work, and field operations.";
        case productionDomainManufacturing:
          return "Batch production, stations, throughput planning, and plant operations.";
        case productionDomainConstruction:
          return "Site sections, build phases, crews, and delivery windows.";
        case productionDomainMedia:
          return "Shoot blocks, production segments, crew scheduling, and delivery pacing.";
        case productionDomainFood:
          return "Kitchen runs, prep blocks, shelf-life-sensitive production, and dispatch.";
        case productionDomainCosmetics:
          return "Blend runs, pack runs, QA gates, and regulated production windows.";
        case productionDomainFashion:
          return "Lines, bundles, stitching blocks, and workshop throughput.";
        case productionDomainCustom:
        default:
          return "A flexible production engine for any workflow that still needs structure.";
      }
    }

    Widget buildShellCard({
      required String title,
      required String subtitle,
      required Widget child,
      EdgeInsetsGeometry padding = const EdgeInsets.all(24),
    }) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              blurRadius: 32,
              offset: const Offset(0, 16),
              color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            ),
          ],
        ),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            child,
          ],
        ),
      );
    }

    Widget buildSummaryChip(IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              "$label: ",
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildMetricCard({
      required String label,
      required String value,
      required IconData icon,
    }) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSelectionCard({
      required String title,
      required String subtitle,
      required bool selected,
      required VoidCallback? onTap,
      IconData icon = Icons.check_circle_outline,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    selected ? Icons.check_circle : icon,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.82,
                        )
                      : theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildWizardStepper() {
      final steps = _wizardSteps();
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: steps.map((step) {
          final complete = _isWizardStepComplete(
            step: step,
            estateScopedStaffProfiles: estateScopedStaffProfiles,
          );
          final active = _currentWizardStep == step;
          final openable = _canOpenWizardStep(
            step: step,
            estateScopedStaffProfiles: estateScopedStaffProfiles,
          );
          final number = _wizardStepNumber(step);
          final completedStep = complete && !active;
          final chipBackgroundColor = active
              ? theme.colorScheme.primaryContainer
              : completedStep
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surfaceContainerLow;
          final chipBorderColor = active
              ? theme.colorScheme.primary
              : completedStep
              ? theme.colorScheme.primary.withValues(alpha: 0.42)
              : theme.colorScheme.outlineVariant;
          final chipForegroundColor = active
              ? theme.colorScheme.onPrimaryContainer
              : completedStep
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant;
          final numberBackgroundColor = active
              ? theme.colorScheme.primary
              : completedStep
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : theme.colorScheme.surface;
          final numberForegroundColor = active
              ? theme.colorScheme.onPrimary
              : completedStep
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: openable
                ? () => _jumpToWizardStep(
                    step: step,
                    estateScopedStaffProfiles: estateScopedStaffProfiles,
                  )
                : null,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                // WHY: onPrimary is intentionally dark in business mode, so the
                // active step uses primaryContainer/onPrimaryContainer instead.
                color: chipBackgroundColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: chipBorderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: numberBackgroundColor,
                    child: Text(
                      "$number",
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: numberForegroundColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _wizardStepTitle(step),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: chipForegroundColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    Widget buildTimingFields() {
      final workUnitOptions = <String>{
        ..._workUnitOptionsForDomain(_domainContext),
        if (_workUnitLabel.trim().isNotEmpty) _workUnitLabel.trim(),
      }.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 720;
              final manualCard = buildSelectionCard(
                title: "Set exact dates",
                subtitle: _startDate != null && _endDate != null
                    ? "${formatDateLabel(_startDate)} → ${formatDateLabel(_endDate)}"
                    : "Choose a real start date and end date for this production cycle.",
                selected: !_useAiInferredDates,
                onTap: () {
                  setState(() {
                    _useAiInferredDates = false;
                  });
                },
                icon: Icons.event_outlined,
              );
              final lifecycleCard = buildSelectionCard(
                title: "Use lifecycle dates",
                subtitle: _selectedProductLifecycleLabel.trim().isEmpty
                    ? "Let the planner infer dates from crop lifecycle coverage."
                    : "Use $_selectedProductLifecycleLabel from the planner crop profile.",
                selected: _useAiInferredDates,
                onTap: _skipDateSelectionAndInfer,
                icon: Icons.auto_awesome_outlined,
              );
              if (useColumn) {
                return Column(
                  children: [
                    manualCard,
                    const SizedBox(height: 12),
                    lifecycleCard,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: manualCard),
                  const SizedBox(width: 12),
                  Expanded(child: lifecycleCard),
                ],
              );
            },
          ),
          if (!_useAiInferredDates) ...[
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final useColumn = constraints.maxWidth < 720;
                final startButton = OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: true),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _startDate == null
                        ? "Pick start date"
                        : formatDateLabel(_startDate),
                  ),
                );
                final endButton = OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: false),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    _endDate == null
                        ? "Pick end date"
                        : formatDateLabel(_endDate),
                  ),
                );
                if (useColumn) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      startButton,
                      const SizedBox(height: 12),
                      endButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: startButton),
                    const SizedBox(width: 12),
                    Expanded(child: endButton),
                  ],
                );
              },
            ),
            if (_startDate != null && _endDate != null) ...[
              const SizedBox(height: 14),
              _buildEstimatedActivityWindowCard(
                theme: theme,
                startDate: _startDate,
                endDate: _endDate,
              ),
            ],
          ],
          const SizedBox(height: 22),
          Text(
            "Workload setup",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _workUnitLabel.trim().isEmpty ? null : _workUnitLabel,
            decoration: const InputDecoration(
              labelText: "Work unit",
              border: OutlineInputBorder(),
            ),
            items: workUnitOptions
                .map(
                  (option) =>
                      DropdownMenuItem(value: option, child: Text(option)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              _onWorkUnitLabelChanged(value);
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 860;
              final totalField = TextFormField(
                initialValue: _totalWorkUnits?.toString() ?? "",
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Total work units",
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    _onTotalWorkUnitsChanged(int.tryParse(value.trim())),
              );
              final minField = TextFormField(
                initialValue: _minStaffPerUnit?.toString() ?? "",
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Min staff / unit",
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    _onMinStaffPerUnitChanged(int.tryParse(value.trim())),
              );
              final maxField = TextFormField(
                initialValue: _maxStaffPerUnit?.toString() ?? "",
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Max staff / unit",
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    _onMaxStaffPerUnitChanged(int.tryParse(value.trim())),
              );
              final children = <Widget>[
                Expanded(child: totalField),
                const SizedBox(width: 12),
                Expanded(child: minField),
                const SizedBox(width: 12),
                Expanded(child: maxField),
              ];
              if (useColumn) {
                return Column(
                  children: [
                    totalField,
                    const SizedBox(height: 12),
                    minField,
                    const SizedBox(height: 12),
                    maxField,
                  ],
                );
              }
              return Row(children: children);
            },
          ),
          const SizedBox(height: 18),
          Text(
            "Expected active staff: $_activeStaffAvailabilityPercent%",
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Slider(
            value: _activeStaffAvailabilityPercent.toDouble(),
            min: 40,
            max: 100,
            divisions: 12,
            label: "$_activeStaffAvailabilityPercent%",
            onChanged: (value) =>
                _onActiveStaffAvailabilityPercentChanged(value.round()),
          ),
        ],
      );
    }

    Widget buildPeopleContent() {
      if (staffAsync.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (estateScopedStaffProfiles.isEmpty) {
        return buildSelectionCard(
          title: "No estate staff linked yet",
          subtitle:
              "You can continue without focused staff. The timeline will still generate from crop lifecycle and workload assumptions.",
          selected: true,
          onTap: null,
          icon: Icons.groups_2_outlined,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Focus roles",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: availableFocusedRoleKeys.map((roleKey) {
              final selected = _focusedRoleKeys.contains(roleKey);
              return FilterChip(
                label: Text(formatStaffRoleLabel(roleKey)),
                selected: selected,
                onSelected: (_) => _onFocusedRoleToggle(roleKey),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                "Preferred staff",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _onBulkFocusedStaffSelection(
                  staffOptions: estateScopedStaffProfiles,
                  shouldSelectAll: true,
                ),
                child: const Text("Select all"),
              ),
              TextButton(
                onPressed: () => _onBulkFocusedStaffSelection(
                  staffOptions: estateScopedStaffProfiles,
                  shouldSelectAll: false,
                ),
                child: const Text("Clear"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...estateScopedStaffProfiles.map((profile) {
            final selected = _focusedStaffProfileIds.contains(
              profile.id.trim(),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: buildSelectionCard(
                title: (profile.userName ?? "").trim().isEmpty
                    ? profile.id.trim()
                    : (profile.userName ?? "").trim(),
                subtitle:
                    "${formatStaffRoleLabel(profile.staffRole)}${profile.estateAssetId?.trim().isNotEmpty == true ? " • ${selectedEstateName.trim().isEmpty ? 'Selected estate' : selectedEstateName}" : ""}",
                selected: selected,
                onTap: () => _onFocusedStaffToggle(profile),
                icon: Icons.person_outline,
              ),
            );
          }),
        ],
      );
    }

    Widget buildReviewContent() {
      final reviewRows = <Widget>[
        buildSummaryChip(
          Icons.category_outlined,
          "Production",
          formatProductionDomainLabel(_domainContext),
        ),
        if (selectedEstateName.trim().isNotEmpty)
          buildSummaryChip(
            Icons.location_on_outlined,
            "Estate",
            selectedEstateName,
          ),
        if (selectedProductName.trim().isNotEmpty)
          buildSummaryChip(Icons.spa_outlined, "Crop", selectedProductName),
        if (_hasResolvedDateMode())
          buildSummaryChip(
            Icons.schedule_outlined,
            "Timing",
            _useAiInferredDates
                ? (_selectedProductLifecycleLabel.trim().isEmpty
                      ? "Lifecycle-derived"
                      : _selectedProductLifecycleLabel)
                : "${formatDateLabel(_startDate)} → ${formatDateLabel(_endDate)}",
          ),
        buildSummaryChip(
          Icons.view_timeline_outlined,
          "Workload",
          "${_totalWorkUnits ?? 0} ${_resolveSafeWorkUnitLabelForStaffing()}",
        ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 10, runSpacing: 10, children: reviewRows),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "What the generator will do",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Create a timeline-first production draft using the selected crop lifecycle, workload assumptions, focused staff, and your selected estate context.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  "Focused roles: ${selectedFocusedRoles.isEmpty ? 'None explicitly selected' : selectedFocusedRoles.map(formatStaffRoleLabel).join(", ")}",
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  "Preferred staff: ${_focusedStaffProfileIds.length}",
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if ((_selectedProductId ?? "").trim().isEmpty &&
              selectedProductName.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer.withValues(
                  alpha: 0.65,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "This crop is coming from the planner database and is not linked to a business product yet. Open the farm product form to finish price, stock, selling options, and images before saving the final production plan.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isLinkingPlannerCropProduct
                        ? null
                        : () async {
                            await _ensureCurrentSelectedCropLinkedProduct();
                          },
                    icon: _isLinkingPlannerCropProduct
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_outlined),
                    label: Text(
                      _isLinkingPlannerCropProduct
                          ? "Opening product setup..."
                          : "Complete farm product setup",
                    ),
                  ),
                ],
              ),
            ),
          ],
          if ((_selectedProductId ?? "").trim().isEmpty &&
              selectedProductName.trim().isNotEmpty &&
              _isLinkingPlannerCropProduct) ...[
            const SizedBox(height: 8),
            Text(
              "Trying to match an existing business product first. If none is found, the farm product setup form will open.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (latestPlanDraft != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _previewDraftProductionSchedule(latestPlanDraft),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text("Preview latest AI draft"),
            ),
          ],
        ],
      );
    }

    Widget buildWizardContent() {
      Widget content;
      switch (_currentWizardStep) {
        case _CreateWizardStep.productionType:
          content = LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 760;
              final cards = productionDomainValues.map((domain) {
                final selected =
                    _domainExplicitlySelected && _domainContext == domain;
                return buildSelectionCard(
                  title: formatProductionDomainLabel(domain),
                  subtitle: domainDescription(domain),
                  selected: selected,
                  onTap: () => _onDomainContextChanged(domain),
                  icon: Icons.auto_mode_outlined,
                );
              }).toList();
              if (useColumn) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards
                    .map(
                      (card) => SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: card,
                      ),
                    )
                    .toList(),
              );
            },
          );
          break;
        case _CreateWizardStep.estate:
          content = assetsAsync.when(
            data: (_) {
              if (estateOptions.isEmpty) {
                return buildSelectionCard(
                  title: "No estates found",
                  subtitle:
                      "Add an estate asset first, then come back to create a production plan.",
                  selected: true,
                  onTap: null,
                  icon: Icons.location_off_outlined,
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final useColumn = constraints.maxWidth < 760;
                  if (useColumn) {
                    return Column(
                      children: estateOptions.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: buildSelectionCard(
                            title: entry.value,
                            subtitle:
                                "Production will be scoped to this estate.",
                            selected: _selectedEstateAssetId == entry.key,
                            onTap: () => _onEstateChanged(
                              estateId: entry.key,
                              estateName: entry.value,
                            ),
                            icon: Icons.agriculture_outlined,
                          ),
                        );
                      }).toList(),
                    );
                  }
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: estateOptions.map((entry) {
                      return SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: buildSelectionCard(
                          title: entry.value,
                          subtitle: "Production will be scoped to this estate.",
                          selected: _selectedEstateAssetId == entry.key,
                          onTap: () => _onEstateChanged(
                            estateId: entry.key,
                            estateName: entry.value,
                          ),
                          icon: Icons.agriculture_outlined,
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => buildSelectionCard(
              title: "Could not load estates",
              subtitle: "Refresh the page and try again.",
              selected: true,
              onTap: null,
              icon: Icons.error_outline,
            ),
          );
          break;
        case _CreateWizardStep.crop:
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedProductName.trim().isNotEmpty)
                buildSelectionCard(
                  title: selectedProductName,
                  subtitle: [
                    if (_selectedProductLifecycleLabel.trim().isNotEmpty)
                      _selectedProductLifecycleLabel.trim(),
                    if (_selectedProductSourceLabel.trim().isNotEmpty)
                      _selectedProductSourceLabel.trim(),
                    if ((_selectedProductId ?? "").trim().isEmpty)
                      "Not linked to a business product yet",
                  ].join(" • "),
                  selected: true,
                  onTap: null,
                  icon: Icons.spa_outlined,
                )
              else
                buildSelectionCard(
                  title: "No crop selected yet",
                  subtitle:
                      "Search the planner crop database to choose the crop this plan should use.",
                  selected: false,
                  onTap: _openPlannerCropSearch,
                  icon: Icons.search_outlined,
                ),
              if (selectedProductName.trim().isNotEmpty &&
                  (_selectedProductId ?? "").trim().isEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "This planner crop still needs a complete farm product before the production flow can continue.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Finish the business product details now: category, subcategory, price, selling options, and image.",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _isLinkingPlannerCropProduct
                            ? null
                            : () async {
                                await _ensureCurrentSelectedCropLinkedProduct();
                              },
                        icon: _isLinkingPlannerCropProduct
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.inventory_2_outlined),
                        label: Text(
                          _isLinkingPlannerCropProduct
                              ? "Opening farm product setup..."
                              : "Complete farm product setup",
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openPlannerCropSearch,
                icon: const Icon(Icons.search),
                label: Text(
                  selectedProductName.trim().isEmpty
                      ? "Search planner crop database"
                      : "Change crop",
                ),
              ),
            ],
          );
          break;
        case _CreateWizardStep.timing:
          content = buildTimingFields();
          break;
        case _CreateWizardStep.people:
          content = buildPeopleContent();
          break;
        case _CreateWizardStep.review:
          content = buildReviewContent();
          break;
      }

      return buildShellCard(
        title: _wizardStepTitle(_currentWizardStep),
        subtitle: _wizardStepHint(_currentWizardStep),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [buildWizardStepper(), const SizedBox(height: 24), content],
        ),
      );
    }

    Widget buildStudioInspector() {
      Widget panelContent;
      switch (_draftStudioPanel) {
        case _DraftStudioPanel.overview:
          panelContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _draftTitleCtrl,
                decoration: const InputDecoration(
                  labelText: "Plan title",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  buildSummaryChip(
                    Icons.location_on_outlined,
                    "Estate",
                    selectedEstateName.trim().isEmpty
                        ? "Not selected"
                        : selectedEstateName,
                  ),
                  buildSummaryChip(
                    Icons.spa_outlined,
                    "Crop",
                    selectedProductName.trim().isEmpty
                        ? "Not selected"
                        : selectedProductName,
                  ),
                  buildSummaryChip(
                    Icons.schedule_outlined,
                    "Timeline",
                    draft.startDate != null && draft.endDate != null
                        ? "${formatDateLabel(draft.startDate)} → ${formatDateLabel(draft.endDate)}"
                        : "Dates unresolved",
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                "This studio is timeline-first. Use the calendar/list switch below to shape the draft, then save when the structure is clean.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (_lastDraftImprovementReport != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Latest improvement pass",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._lastDraftImprovementReport!.changeSummaries
                          .take(4)
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.auto_fix_high_outlined,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(line)),
                                ],
                              ),
                            ),
                          ),
                      if (_lastDraftImprovementReport!.changeSummaries.isEmpty)
                        Text(
                          "No safe automatic changes were applied in the last pass.",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_lastDraftImprovementReport!
                          .unresolvedWarnings
                          .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _lastDraftImprovementReport!.unresolvedWarnings.first,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
          break;
        case _DraftStudioPanel.staffing:
          panelContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Focused roles",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (selectedFocusedRoles.isEmpty)
                Text(
                  "No explicit role focus was selected.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: selectedFocusedRoles
                      .map(
                        (role) => Chip(label: Text(formatStaffRoleLabel(role))),
                      )
                      .toList(),
                ),
              const SizedBox(height: 18),
              Text(
                "Preferred staff",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (_focusedStaffProfileIds.isEmpty)
                Text(
                  "No preferred staff selected.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...estateScopedStaffProfiles
                    .where(
                      (profile) =>
                          _focusedStaffProfileIds.contains(profile.id.trim()),
                    )
                    .map(
                      (profile) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            (profile.userName ?? "").trim().isEmpty
                                ? profile.id.trim().characters.first
                                : (profile.userName ?? "")
                                      .trim()
                                      .characters
                                      .first,
                          ),
                        ),
                        title: Text(
                          (profile.userName ?? "").trim().isEmpty
                              ? profile.id.trim()
                              : (profile.userName ?? "").trim(),
                        ),
                        subtitle: Text(formatStaffRoleLabel(profile.staffRole)),
                      ),
                    ),
            ],
          );
          break;
        case _DraftStudioPanel.notes:
          panelContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _draftNotesCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: "Manager notes",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Warnings & planner notes",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (draft.riskNotes.isEmpty)
                Text(
                  "No planner warnings were returned for this draft.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...draft.riskNotes.map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(note)),
                      ],
                    ),
                  ),
                ),
            ],
          );
          break;
        case _DraftStudioPanel.settings:
          panelContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildSummaryChip(
                Icons.category_outlined,
                "Production type",
                formatProductionDomainLabel(_domainContext),
              ),
              const SizedBox(height: 10),
              buildSummaryChip(
                Icons.view_timeline_outlined,
                "Work unit",
                _resolveSafeWorkUnitLabelForStaffing(),
              ),
              const SizedBox(height: 10),
              buildSummaryChip(
                Icons.stacked_bar_chart_outlined,
                "Total units",
                "${_totalWorkUnits ?? 0}",
              ),
              const SizedBox(height: 18),
              Text(
                "Adjust dates",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _pickDate(isStart: true),
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  draft.startDate == null
                      ? "Set start date"
                      : formatDateLabel(draft.startDate),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _pickDate(isStart: false),
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  draft.endDate == null
                      ? "Set end date"
                      : formatDateLabel(draft.endDate),
                ),
              ),
              if (draft.startDate != null && draft.endDate != null) ...[
                const SizedBox(height: 14),
                _buildEstimatedActivityWindowCard(
                  theme: theme,
                  startDate: draft.startDate,
                  endDate: draft.endDate,
                ),
              ],
            ],
          );
          break;
      }

      return buildShellCard(
        title: "Draft inspector",
        subtitle: "Secondary controls live here so the timeline stays primary.",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_DraftStudioPanel>(
              segments: const [
                ButtonSegment<_DraftStudioPanel>(
                  value: _DraftStudioPanel.overview,
                  label: Text("Overview"),
                  icon: Icon(Icons.dashboard_outlined),
                ),
                ButtonSegment<_DraftStudioPanel>(
                  value: _DraftStudioPanel.staffing,
                  label: Text("Staffing"),
                  icon: Icon(Icons.groups_outlined),
                ),
                ButtonSegment<_DraftStudioPanel>(
                  value: _DraftStudioPanel.notes,
                  label: Text("Notes"),
                  icon: Icon(Icons.sticky_note_2_outlined),
                ),
                ButtonSegment<_DraftStudioPanel>(
                  value: _DraftStudioPanel.settings,
                  label: Text("Settings"),
                  icon: Icon(Icons.tune_outlined),
                ),
              ],
              selected: {_draftStudioPanel},
              onSelectionChanged: (selection) {
                setState(() {
                  _draftStudioPanel = selection.first;
                });
              },
            ),
            const SizedBox(height: 20),
            panelContent,
          ],
        ),
      );
    }

    Widget buildDraftStudioContent() {
      final metricCards = [
        buildMetricCard(
          label: "Phases",
          value: "${draft.phases.length}",
          icon: Icons.layers_outlined,
        ),
        buildMetricCard(
          label: "Tasks",
          value: "${draft.totalTasks}",
          icon: Icons.task_alt_outlined,
        ),
        buildMetricCard(
          label: "Estimated days",
          value: "${draft.totalEstimatedDays}",
          icon: Icons.timelapse_outlined,
        ),
        buildMetricCard(
          label: "Warnings",
          value: "${draft.riskNotes.length}",
          icon: Icons.warning_amber_rounded,
        ),
      ];

      final timelineCard = buildShellCard(
        title: "Timeline-first draft studio",
        subtitle:
            "Review the timeline first, then adjust tasks, staffing, notes, and plan settings from the inspector.",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      metricCards[0],
                      const SizedBox(height: 12),
                      metricCards[1],
                      const SizedBox(height: 12),
                      metricCards[2],
                      const SizedBox(height: 12),
                      metricCards[3],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: metricCards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: metricCards[1]),
                    const SizedBox(width: 12),
                    Expanded(child: metricCards[2]),
                    const SizedBox(width: 12),
                    Expanded(child: metricCards[3]),
                  ],
                );
              },
            ),
            if ((draft.productId ?? "").trim().isEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer.withValues(
                    alpha: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  "This draft is editable, but the selected crop is not linked to a business product yet. Saving the production plan will still require a linked product.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            ProductionPlanTaskTable(
              draft: draft,
              staff: staffList,
              onAddTask: (phaseIndex) {
                ref
                    .read(productionPlanDraftProvider.notifier)
                    .addTask(phaseIndex);
              },
              onRemoveTask: (phaseIndex, taskId) {
                ref
                    .read(productionPlanDraftProvider.notifier)
                    .removeTask(phaseIndex, taskId);
              },
            ),
          ],
        ),
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          final isDesktopLayout =
              constraints.maxWidth >= _assistantDesktopLayoutBreakpoint;
          if (isDesktopLayout) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: timelineCard),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: buildStudioInspector()),
              ],
            );
          }
          return Column(
            children: [
              timelineCard,
              const SizedBox(height: 18),
              buildStudioInspector(),
            ],
          );
        },
      );
    }

    final summaryChips = <Widget>[
      if (_domainExplicitlySelected)
        buildSummaryChip(
          Icons.category_outlined,
          "Type",
          formatProductionDomainLabel(_domainContext),
        ),
      if (selectedEstateName.trim().isNotEmpty)
        buildSummaryChip(
          Icons.location_on_outlined,
          "Estate",
          selectedEstateName,
        ),
      if (selectedProductName.trim().isNotEmpty)
        buildSummaryChip(Icons.spa_outlined, "Crop", selectedProductName),
      if (_hasResolvedDateMode())
        buildSummaryChip(
          Icons.schedule_outlined,
          "Dates",
          _useAiInferredDates
              ? (_selectedProductLifecycleLabel.trim().isEmpty
                    ? "Lifecycle-derived"
                    : _selectedProductLifecycleLabel)
              : "${formatDateLabel(_startDate)} → ${formatDateLabel(_endDate)}",
        ),
      if ((_totalWorkUnits ?? 0) > 0)
        buildSummaryChip(
          Icons.view_timeline_outlined,
          "Workload",
          "${_totalWorkUnits ?? 0} ${_resolveSafeWorkUnitLabelForStaffing()}",
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          hasDraftStudio ? "Production draft studio" : "New production plan",
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlansRoute);
          },
        ),
        actions: [
          if (hasStartedPlan)
            TextButton.icon(
              onPressed: () =>
                  _resetPlannerSession(showSnack: true, announce: true),
              icon: const Icon(Icons.refresh),
              label: Text(hasDraftStudio ? "New plan" : "Clear plan"),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useColumn = constraints.maxWidth < 760;
            if (hasDraftStudio) {
              final children = <Widget>[
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _showDraftStudio = false;
                    _currentWizardStep = _CreateWizardStep.review;
                  }),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text("Edit setup"),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openAiCopilot(
                    hasDraftStudioContent: hasDraftStudio,
                    selectedEstateName: selectedEstateName,
                    selectedProductName: selectedProductName,
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text("Ask AI"),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      (_isSending ||
                          _isImportingDraftDocument ||
                          _isImprovingDraft)
                      ? null
                      : () => _inspectAndImproveCurrentDraft(draft: draft),
                  icon: _isImprovingDraft
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  label: Text(
                    _isImprovingDraft
                        ? "Improving..."
                        : _draftStudioImproveLabel,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      (_isSending ||
                          _isImportingDraftDocument ||
                          _isImprovingDraft)
                      ? null
                      : () => _populateDraftUsingImportedDocument(
                          selectedEstateName: selectedEstateName,
                          selectedProductName: selectedProductName,
                        ),
                  icon: _isImportingDraftDocument
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    _isImportingDraftDocument
                        ? "Importing..."
                        : _draftStudioPopulateFromPdfLabel,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      (_isSending ||
                          _isImportingDraftDocument ||
                          _isImprovingDraft)
                      ? null
                      : () => _downloadCurrentStudioDraft(draft: draft),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text(_draftStudioDownloadLabel),
                ),
                FilledButton.icon(
                  onPressed: (_isSending || _isImprovingDraft)
                      ? null
                      : _saveDraftPlan,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text("Save plan"),
                ),
              ];
              final secondaryActions = children.sublist(0, children.length - 1);
              final primaryAction = children.last;
              return Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: useColumn
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < secondaryActions.length;
                            index++
                          ) ...[
                            secondaryActions[index],
                            if (index < secondaryActions.length - 1)
                              const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 10),
                          primaryAction,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: secondaryActions,
                            ),
                          ),
                          const SizedBox(width: 10),
                          primaryAction,
                        ],
                      ),
              );
            }

            final primaryLabel = _currentWizardStep == _CreateWizardStep.review
                ? "Generate draft"
                : "Continue";
            final secondaryChildren = <Widget>[
              if (_currentWizardStep != _CreateWizardStep.productionType)
                OutlinedButton.icon(
                  onPressed: _goBackWizard,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("Back"),
                ),
              FilledButton.tonalIcon(
                onPressed: () => _openAiCopilot(
                  hasDraftStudioContent: hasDraftStudio,
                  selectedEstateName: selectedEstateName,
                  selectedProductName: selectedProductName,
                ),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text("Ask AI"),
              ),
              if (_currentWizardStep == _CreateWizardStep.review)
                OutlinedButton.icon(
                  onPressed: _openManualEditor,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text("Start manually"),
                ),
              FilledButton.icon(
                onPressed: _isSending
                    ? null
                    : () => _advanceWizard(
                        estateScopedStaffProfiles: estateScopedStaffProfiles,
                        selectedEstateName: selectedEstateName,
                        selectedProductName: selectedProductName,
                      ),
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _currentWizardStep == _CreateWizardStep.review
                            ? Icons.auto_awesome
                            : Icons.arrow_forward,
                      ),
                label: Text(primaryLabel),
              ),
            ];

            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: useColumn
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = 0;
                          index < secondaryChildren.length;
                          index++
                        ) ...[
                          secondaryChildren[index],
                          if (index != secondaryChildren.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    )
                  : Row(
                      children: [
                        if (_currentWizardStep !=
                            _CreateWizardStep.productionType)
                          secondaryChildren[0],
                        if (_currentWizardStep !=
                            _CreateWizardStep.productionType)
                          const SizedBox(width: 10),
                        secondaryChildren[_currentWizardStep !=
                                _CreateWizardStep.productionType
                            ? 1
                            : 0],
                        if (_currentWizardStep == _CreateWizardStep.review) ...[
                          const SizedBox(width: 10),
                          secondaryChildren[_currentWizardStep !=
                                  _CreateWizardStep.productionType
                              ? 2
                              : 1],
                        ],
                        const Spacer(),
                        secondaryChildren.last,
                      ],
                    ),
            );
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surfaceContainerLowest,
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHigh,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasDraftStudio
                      ? "Edit the draft, not the chaos."
                      : "Blank start. One clear step at a time.",
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasDraftStudio
                      ? "The timeline is primary. AI stays optional. You can adjust tasks, staffing, notes, and dates without getting trapped in a chat UI."
                      : "Build the production context first, then generate a timeline you can actually understand and edit.",
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: hasDraftStudio
                      ? 1
                      : _wizardStepNumber(_currentWizardStep) /
                            _wizardSteps().length,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                if (summaryChips.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < summaryChips.length;
                          index++
                        ) ...[
                          summaryChips[index],
                          if (index != summaryChips.length - 1)
                            const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: hasDraftStudio ? 1340 : 980,
                        ),
                        child: hasDraftStudio
                            ? buildDraftStudioContent()
                            : buildWizardContent(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiCopilotSheet extends StatelessWidget {
  final String selectedEstateName;
  final String selectedProductName;
  final String selectedProductLifecycleLabel;
  final String latestAssistantMessage;
  final bool hasDraft;
  final bool canGenerateDraft;
  final Future<void> Function() onSearchCrop;
  final Future<void> Function() onUseLifecycleDates;
  final Future<void> Function() onGenerateDraft;
  final Future<void> Function()? onPreviewDraft;
  final Future<void> Function() onStartManualDraft;

  const _AiCopilotSheet({
    required this.selectedEstateName,
    required this.selectedProductName,
    required this.selectedProductLifecycleLabel,
    required this.latestAssistantMessage,
    required this.hasDraft,
    required this.canGenerateDraft,
    required this.onSearchCrop,
    required this.onUseLifecycleDates,
    required this.onGenerateDraft,
    required this.onPreviewDraft,
    required this.onStartManualDraft,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Future<void> closeThen(Future<void> Function() action) async {
      Navigator.of(context).pop();
      await action();
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            blurRadius: 28,
            offset: const Offset(0, 16),
            color: theme.colorScheme.shadow.withValues(alpha: 0.14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "AI copilot",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            "Use AI only when you want help. The main flow still works without chat.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (selectedEstateName.trim().isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.location_on_outlined, size: 16),
                  label: Text(selectedEstateName),
                ),
              if (selectedProductName.trim().isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.spa_outlined, size: 16),
                  label: Text(selectedProductName),
                ),
              if (selectedProductLifecycleLabel.trim().isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.schedule_outlined, size: 16),
                  label: Text(selectedProductLifecycleLabel),
                ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: () => closeThen(onSearchCrop),
            icon: const Icon(Icons.search_outlined),
            label: const Text("Search planner crop database"),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => closeThen(onUseLifecycleDates),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text("Use lifecycle dates"),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: canGenerateDraft
                ? () => closeThen(onGenerateDraft)
                : null,
            icon: const Icon(Icons.auto_awesome),
            label: Text(hasDraft ? "Regenerate draft" : "Generate draft"),
          ),
          if (onPreviewDraft != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => closeThen(onPreviewDraft!),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text("Preview latest AI draft"),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => closeThen(onStartManualDraft),
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text("Start manual timeline"),
          ),
          if (latestAssistantMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                latestAssistantMessage.trim(),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceTag extends StatelessWidget {
  final String text;

  const _WorkspaceTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _WorkspaceScopeChip extends StatelessWidget {
  final String label;
  final String value;

  const _WorkspaceScopeChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        "$label: $value",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
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
  final String selectedProductLifecycleLabel;
  final String selectedProductSourceLabel;
  final String? selectedEstateAssetId;
  final Map<String, String> estateNamesById;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isSending;
  final bool isStaffLoading;
  final List<String> availableFocusedRoleKeys;
  final List<String> selectedFocusedRoleKeys;
  final List<BusinessStaffProfileSummary> estateScopedStaffProfiles;
  final Set<String> selectedFocusedStaffProfileIds;
  final bool hasConfirmedStaffContext;
  final List<String> availableWorkUnitLabels;
  final String workUnitLabel;
  final int? totalWorkUnits;
  final int? minStaffPerUnit;
  final int? maxStaffPerUnit;
  final int activeStaffAvailabilityPercent;
  final bool hasConfirmedWorkloadContext;
  final ValueChanged<String> onDomainSelect;
  final ValueChanged<String> onEstateSelect;
  final ValueChanged<String> onFocusedRoleToggle;
  final ValueChanged<BusinessStaffProfileSummary> onFocusedStaffToggle;
  final void Function(List<BusinessStaffProfileSummary>, bool)
  onBulkFocusedStaffSelection;
  final VoidCallback onConfirmFocusedStaffContext;
  final ValueChanged<String> onWorkUnitLabelChanged;
  final ValueChanged<int?> onTotalWorkUnitsChanged;
  final ValueChanged<int?> onMinStaffPerUnitChanged;
  final ValueChanged<int?> onMaxStaffPerUnitChanged;
  final ValueChanged<int> onActiveStaffAvailabilityPercentChanged;
  final VoidCallback onConfirmWorkloadContext;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final VoidCallback onSkipDates;
  final VoidCallback onSearchProductTap;
  final VoidCallback onGenerateTap;
  final bool embedded;

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
    required this.selectedProductLifecycleLabel,
    required this.selectedProductSourceLabel,
    required this.selectedEstateAssetId,
    required this.estateNamesById,
    required this.startDate,
    required this.endDate,
    required this.isSending,
    required this.isStaffLoading,
    required this.availableFocusedRoleKeys,
    required this.selectedFocusedRoleKeys,
    required this.estateScopedStaffProfiles,
    required this.selectedFocusedStaffProfileIds,
    required this.hasConfirmedStaffContext,
    required this.availableWorkUnitLabels,
    required this.workUnitLabel,
    required this.totalWorkUnits,
    required this.minStaffPerUnit,
    required this.maxStaffPerUnit,
    required this.activeStaffAvailabilityPercent,
    required this.hasConfirmedWorkloadContext,
    required this.onDomainSelect,
    required this.onEstateSelect,
    required this.onFocusedRoleToggle,
    required this.onFocusedStaffToggle,
    required this.onBulkFocusedStaffSelection,
    required this.onConfirmFocusedStaffContext,
    required this.onWorkUnitLabelChanged,
    required this.onTotalWorkUnitsChanged,
    required this.onMinStaffPerUnitChanged,
    required this.onMaxStaffPerUnitChanged,
    required this.onActiveStaffAvailabilityPercentChanged,
    required this.onConfirmWorkloadContext,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onSkipDates,
    required this.onSearchProductTap,
    required this.onGenerateTap,
    this.embedded = false,
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
    final hasWorkloadValues =
        workUnitLabel.trim().isNotEmpty &&
        (totalWorkUnits ?? 0) > 0 &&
        (minStaffPerUnit ?? 0) > 0 &&
        (maxStaffPerUnit ?? 0) >= (minStaffPerUnit ?? 0);
    if (!hasWorkloadValues || !hasConfirmedWorkloadContext) {
      return _GuidedStep.workload;
    }
    if ((!hasStartDate || !hasEndDate) && !useAiInferredDates) {
      return _GuidedStep.dates;
    }
    return _GuidedStep.generate;
  }

  int _totalStepCount() {
    final hasRoleStep = estateScopedStaffProfiles.isNotEmpty || isStaffLoading;
    return hasRoleStep ? 7 : 6;
  }

  int _stepNumber(_GuidedStep step) {
    final hasRoleStep = estateScopedStaffProfiles.isNotEmpty || isStaffLoading;
    switch (step) {
      case _GuidedStep.businessType:
        return 1;
      case _GuidedStep.estate:
        return 2;
      case _GuidedStep.product:
        return 3;
      case _GuidedStep.roleAndStaff:
        return 4;
      case _GuidedStep.workload:
        return hasRoleStep ? 5 : 4;
      case _GuidedStep.dates:
        return hasRoleStep ? 6 : 5;
      case _GuidedStep.generate:
        return hasRoleStep ? 7 : 6;
    }
  }

  String _stepHintText(_GuidedStep step) {
    final totalSteps = _totalStepCount();
    final stepNumber = _stepNumber(step);
    switch (step) {
      case _GuidedStep.businessType:
        return "Step $stepNumber of $totalSteps: choose business type.";
      case _GuidedStep.estate:
        return "Step $stepNumber of $totalSteps: choose estate.";
      case _GuidedStep.product:
        return "Step $stepNumber of $totalSteps: search and select crop.";
      case _GuidedStep.roleAndStaff:
        return "Step $stepNumber of $totalSteps: choose focused roles and staff IDs.";
      case _GuidedStep.workload:
        return "Step $stepNumber of $totalSteps: set workload and staffing assumptions.";
      case _GuidedStep.dates:
        return "Step $stepNumber of $totalSteps: choose dates or use lifecycle dates.";
      case _GuidedStep.generate:
        return "Step $stepNumber of $totalSteps: generate draft.";
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
    final hasWorkloadValues =
        workUnitLabel.trim().isNotEmpty &&
        (totalWorkUnits ?? 0) > 0 &&
        (minStaffPerUnit ?? 0) > 0 &&
        (maxStaffPerUnit ?? 0) >= (minStaffPerUnit ?? 0);
    final safeTotalWorkUnitsForSlider =
        (totalWorkUnits ?? _contextPromptTotalUnitsQuickPicks.first)
            .clamp(1, 200)
            .toInt();
    final safeMinStaffForSelection =
        (minStaffPerUnit ?? _contextPromptMinStaffPerUnitQuickPicks.first)
            .clamp(1, 10)
            .toInt();
    final safeMaxStaffForSelectionRaw =
        (maxStaffPerUnit ?? _contextPromptMaxStaffPerUnitQuickPicks.first)
            .clamp(1, 20)
            .toInt();
    final safeMaxStaffForSelection =
        safeMaxStaffForSelectionRaw < safeMinStaffForSelection
        ? safeMinStaffForSelection
        : safeMaxStaffForSelectionRaw;
    final workloadSummary = hasWorkloadValues
        ? "${totalWorkUnits ?? 0} ${workUnitLabel.trim()} units, min ${minStaffPerUnit ?? 0}/unit, max ${maxStaffPerUnit ?? 0}/unit, $activeStaffAvailabilityPercent% active"
        : "Not set";
    final contextLabel = [
      "Business: ${formatProductionDomainLabel(domainContext)}",
      "Estate: ${selectedEstateName.trim().isEmpty ? "Not selected" : selectedEstateName}",
      "Crop: ${selectedProductName.trim().isEmpty ? "Not selected" : selectedProductName}",
      "Workload: $workloadSummary",
      "Dates: ${hasStartDate && hasEndDate ? "Set" : "Lifecycle-derived"}",
      "Focused roles: ${selectedFocusedRoleKeys.length}",
      "Focused staff IDs: ${selectedFocusedStaffProfileIds.length}",
    ].join(" | ");
    final estateEntries = estateNamesById.entries.take(8).toList();
    final showEstateSelector =
        domainExplicitlySelected || estateEntries.isNotEmpty || hasEstate;
    final showProductSelector = hasEstate || hasProduct;
    final showRoleAndStaffSelector = hasEstate;
    final showWorkloadSelector = hasEstate;
    final showDatesSelector = hasEstate && hasProduct;
    final panelContent = Padding(
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
          if (showEstateSelector) ...[
            if (currentStep != _GuidedStep.estate) ...[
              Text("Estate", style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
            ],
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
            if ((selectedEstateAssetId ?? "").trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                "Selected estate ID: ${selectedEstateAssetId!.trim()}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
          ],
          if (showProductSelector) ...[
            if (currentStep != _GuidedStep.product) ...[
              Text("Crop", style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
            ],
            Text(
              _contextPromptSearchProductHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (selectedProductName.trim().isNotEmpty)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _contextPromptSelectedProductLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedProductName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (selectedProductLifecycleLabel.trim().isNotEmpty ||
                        selectedProductSourceLabel.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (selectedProductLifecycleLabel.trim().isNotEmpty)
                            Chip(
                              label: Text(selectedProductLifecycleLabel),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (selectedProductSourceLabel.trim().isNotEmpty)
                            Chip(
                              label: Text(selectedProductSourceLabel),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            if (selectedProductName.trim().isNotEmpty)
              const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: isSending ? null : onSearchProductTap,
              icon: const Icon(Icons.search),
              label: Text(
                selectedProductName.trim().isEmpty
                    ? _contextPromptSearchProductLabel
                    : _contextPromptChangeProductLabel,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (showRoleAndStaffSelector) ...[
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
                      value: selectedFocusedStaffProfileIds.contains(profileId),
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
            const SizedBox(height: 10),
          ],
          if (showWorkloadSelector) ...[
            Text(
              _contextPromptWorkloadLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              _contextPromptWorkloadHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              _contextPromptWorkUnitOptionLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableWorkUnitLabels
                  .map(
                    (optionLabel) => ChoiceChip(
                      label: Text(optionLabel),
                      selected:
                          optionLabel.trim().toLowerCase() ==
                          workUnitLabel.trim().toLowerCase(),
                      onSelected: isSending
                          ? null
                          : (_) => onWorkUnitLabelChanged(optionLabel),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              "$_contextPromptTotalUnitsSliderLabel: $safeTotalWorkUnitsForSlider",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Slider(
              min: 1,
              max: 200,
              divisions: 199,
              value: safeTotalWorkUnitsForSlider.toDouble(),
              label: "$safeTotalWorkUnitsForSlider",
              onChanged: isSending
                  ? null
                  : (value) => onTotalWorkUnitsChanged(value.round()),
            ),
            const SizedBox(height: 8),
            Text(
              _contextPromptTotalUnitsQuickPickLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _contextPromptTotalUnitsQuickPicks
                  .map(
                    (units) => ChoiceChip(
                      label: Text("$units"),
                      selected: (totalWorkUnits ?? 0) == units,
                      onSelected: isSending
                          ? null
                          : (_) => onTotalWorkUnitsChanged(units),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              _contextPromptMinStaffQuickPickLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _contextPromptMinStaffPerUnitQuickPicks
                  .map(
                    (staffCount) => ChoiceChip(
                      label: Text("$staffCount"),
                      selected: safeMinStaffForSelection == staffCount,
                      onSelected: isSending
                          ? null
                          : (_) => onMinStaffPerUnitChanged(staffCount),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              _contextPromptMaxStaffQuickPickLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _contextPromptMaxStaffPerUnitQuickPicks
                  .map(
                    (staffCount) => ChoiceChip(
                      label: Text("$staffCount"),
                      selected: safeMaxStaffForSelection == staffCount,
                      onSelected:
                          isSending || staffCount < safeMinStaffForSelection
                          ? null
                          : (_) => onMaxStaffPerUnitChanged(staffCount),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              "$_contextPromptActiveStaffAssumptionLabel: $activeStaffAvailabilityPercent%",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Slider(
              min: 40,
              max: 100,
              divisions: 12,
              value: activeStaffAvailabilityPercent.toDouble(),
              label: "$activeStaffAvailabilityPercent%",
              onChanged: isSending
                  ? null
                  : (value) =>
                        onActiveStaffAvailabilityPercentChanged(value.round()),
            ),
            FilledButton.icon(
              onPressed: hasWorkloadValues ? onConfirmWorkloadContext : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(_contextPromptConfirmWorkloadContextLabel),
            ),
            const SizedBox(height: 10),
          ],
          if (showDatesSelector) ...[
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
            const SizedBox(height: 10),
          ],
          if (canGenerate)
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
    );
    if (embedded) {
      // WHY: Embedded mode reuses the same guided prompt body inside workspace cards without nested Card margins.
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: panelContent,
      );
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: panelContent,
    );
  }
}

enum _GuidedStep {
  businessType,
  estate,
  product,
  roleAndStaff,
  workload,
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
  final bool embedded;

  const _TurnActionPanel({
    required this.turn,
    required this.onSuggestionTap,
    required this.onChoiceTap,
    required this.onCreateSuggestedProduct,
    required this.onApplyDraft,
    this.embedded = false,
  });

  Widget _buildPanelSurface({
    required BuildContext context,
    required Widget child,
  }) {
    if (embedded) {
      // WHY: Embedded mode keeps this panel visually consistent with workspace cards and avoids duplicate Card margins.
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: child,
      );
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTurn = turn;
    if (currentTurn == null) {
      return const SizedBox.shrink();
    }

    final suggestionPayload = currentTurn.suggestionsPayload;
    if (currentTurn.isSuggestions && suggestionPayload != null) {
      final suggestions = Wrap(
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
      );
      if (embedded) {
        return suggestions;
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: suggestions,
      );
    }

    final clarifyPayload = currentTurn.clarifyPayload;
    if (currentTurn.isClarify && clarifyPayload != null) {
      return _buildPanelSurface(
        context: context,
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
      );
    }

    final draftProductPayload = currentTurn.draftProductPayload;
    if (currentTurn.isDraftProduct && draftProductPayload != null) {
      final draft = draftProductPayload.draftProduct;
      return _buildPanelSurface(
        context: context,
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
      );
    }

    final planDraftPayload = currentTurn.planDraftPayload;
    if (currentTurn.isPlanDraft && planDraftPayload != null) {
      // PHASE-GATE-LAYER
      // WHY: Lock/cap warnings must always be visible in preview so managers understand lifecycle gate effects.
      final phaseGateWarnings = planDraftPayload.warnings.where((warning) {
        final normalizedCode = warning.code.trim().toLowerCase();
        return normalizedCode == _phaseGateLockedWarningCode ||
            normalizedCode == _phaseGateCappedWarningCode;
      }).toList();
      final nonPhaseGateWarnings = planDraftPayload.warnings.where((warning) {
        final normalizedCode = warning.code.trim().toLowerCase();
        return normalizedCode != _phaseGateLockedWarningCode &&
            normalizedCode != _phaseGateCappedWarningCode;
      }).toList();
      final previewWarnings = <ProductionAssistantPlanWarning>[
        ...phaseGateWarnings,
        ...nonPhaseGateWarnings.take(3),
      ];
      return _buildPanelSurface(
        context: context,
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
            if (previewWarnings.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...previewWarnings.map((warning) => Text("- ${warning.message}")),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => onApplyDraft(planDraftPayload),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(_useDraftButtonLabel),
            ),
          ],
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

class _AssistantTaskDailyWindow {
  final DateTime startDate;
  final DateTime dueDate;

  const _AssistantTaskDailyWindow({
    required this.startDate,
    required this.dueDate,
  });
}

class _AssistantScheduleTask {
  final String title;
  final String phaseName;
  final int phaseOrder;
  final String phaseType;
  final double phaseMinRatePerFarmerHour;
  final double phaseTargetRatePerFarmerHour;
  final String roleRequired;
  final int requiredHeadcount;
  final List<String> assignedStaffProfileIds;
  final DateTime startDate;
  final DateTime dueDate;
  final int projectedWorkUnits;
  final int projectedWorkUnitsRemaining;
  final String projectionWorkstreamKey;
  final bool projectionIsRepeatable;
  final int projectionCadenceDays;

  const _AssistantScheduleTask({
    required this.title,
    required this.phaseName,
    required this.phaseOrder,
    required this.phaseType,
    this.phaseMinRatePerFarmerHour = 0,
    this.phaseTargetRatePerFarmerHour = 0,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.assignedStaffProfileIds,
    required this.startDate,
    required this.dueDate,
    this.projectedWorkUnits = 0,
    this.projectedWorkUnitsRemaining = 0,
    this.projectionWorkstreamKey = "",
    this.projectionIsRepeatable = false,
    this.projectionCadenceDays = 0,
  });

  _AssistantScheduleTask copyWithProjection({
    required int projectedWorkUnits,
    required int projectedWorkUnitsRemaining,
    String? projectionWorkstreamKey,
    bool? projectionIsRepeatable,
    int? projectionCadenceDays,
  }) {
    return _AssistantScheduleTask(
      title: title,
      phaseName: phaseName,
      phaseOrder: phaseOrder,
      phaseType: phaseType,
      phaseMinRatePerFarmerHour: phaseMinRatePerFarmerHour,
      phaseTargetRatePerFarmerHour: phaseTargetRatePerFarmerHour,
      roleRequired: roleRequired,
      requiredHeadcount: requiredHeadcount,
      assignedStaffProfileIds: assignedStaffProfileIds,
      startDate: startDate,
      dueDate: dueDate,
      projectedWorkUnits: projectedWorkUnits,
      projectedWorkUnitsRemaining: projectedWorkUnitsRemaining,
      projectionWorkstreamKey:
          projectionWorkstreamKey ?? this.projectionWorkstreamKey,
      projectionIsRepeatable:
          projectionIsRepeatable ?? this.projectionIsRepeatable,
      projectionCadenceDays:
          projectionCadenceDays ?? this.projectionCadenceDays,
    );
  }
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

class _AssistantProjectionSummary {
  final int expectedWorkUnitsPerTrack;
  final int executionTaskTrackCount;
  final int fullyCoveredTrackCount;
  final int minimumCoveredAcrossTracks;
  final int maximumRemainingAcrossTracks;

  const _AssistantProjectionSummary({
    required this.expectedWorkUnitsPerTrack,
    required this.executionTaskTrackCount,
    required this.fullyCoveredTrackCount,
    required this.minimumCoveredAcrossTracks,
    required this.maximumRemainingAcrossTracks,
  });

  bool get hasExecutionTaskTracks => executionTaskTrackCount > 0;
}

class _DraftRepairTemplate {
  final String title;
  final String instructions;

  const _DraftRepairTemplate({required this.title, required this.instructions});
}

class _DraftRecurringRepairTemplate {
  final String title;
  final String instructions;
  final int cadenceDays;
  final int preferredWeekday;
  final int startHour;
  final int durationHours;
  final String preferredRole;

  const _DraftRecurringRepairTemplate({
    required this.title,
    required this.instructions,
    required this.cadenceDays,
    this.preferredWeekday = DateTime.wednesday,
    this.startHour = 8,
    this.durationHours = 2,
    this.preferredRole = "",
  });
}

class _DraftPhaseWindow {
  final int phaseIndex;
  final DateTime startDate;
  final DateTime endDate;

  const _DraftPhaseWindow({
    required this.phaseIndex,
    required this.startDate,
    required this.endDate,
  });
}

class _DraftRedundantManagementInfo {
  final Set<String> supervisionOnlyWeekKeys;
  final int redundantTaskCount;

  const _DraftRedundantManagementInfo({
    required this.supervisionOnlyWeekKeys,
    required this.redundantTaskCount,
  });
}

class _DraftScheduleDensityInfo {
  final Set<String> underfilledWeekKeys;
  final Set<String> activeSparseWeekKeys;
  final Set<String> fieldSparseWeekKeys;
  final Set<String> emptyWeekKeys;
  final Set<String> supervisionOnlyWeekKeys;
  final Map<String, int> scheduledDayCountByWeekKey;
  final Map<String, int> nonManagementDayCountByWeekKey;
  final int oneDayWeekCount;
  final int twoDayWeekCount;

  const _DraftScheduleDensityInfo({
    required this.underfilledWeekKeys,
    required this.activeSparseWeekKeys,
    required this.fieldSparseWeekKeys,
    required this.emptyWeekKeys,
    required this.supervisionOnlyWeekKeys,
    required this.scheduledDayCountByWeekKey,
    required this.nonManagementDayCountByWeekKey,
    required this.oneDayWeekCount,
    required this.twoDayWeekCount,
  });

  int get underfilledWeekCount => underfilledWeekKeys.length;
}

class _DraftTaskStateSeed {
  final ProductionTaskDraft task;

  const _DraftTaskStateSeed({required this.task});
}

class _DraftImprovementMutation {
  final ProductionAssistantPlanDraftPayload payload;
  final int expandedGenericTaskCount;
  final int removedSupervisionCount;
  final int phaseRebucketedCount;
  final int instructionsAddedCount;
  final int roleAdjustedCount;
  final int insertedSupportTaskCount;
  final int stretchedTaskWindowCount;
  final int densifiedWeekCount;
  final int propagationTaskFixedCount;

  const _DraftImprovementMutation({
    required this.payload,
    required this.expandedGenericTaskCount,
    required this.removedSupervisionCount,
    required this.phaseRebucketedCount,
    required this.instructionsAddedCount,
    required this.roleAdjustedCount,
    required this.insertedSupportTaskCount,
    required this.stretchedTaskWindowCount,
    required this.densifiedWeekCount,
    required this.propagationTaskFixedCount,
  });
}

class _DraftCalendarRepairResult {
  final ProductionAssistantPlanDraftPayload payload;
  final int insertedSupportTaskCount;
  final int stretchedTaskWindowCount;
  final int densifiedWeekCount;

  const _DraftCalendarRepairResult({
    required this.payload,
    required this.insertedSupportTaskCount,
    required this.stretchedTaskWindowCount,
    required this.densifiedWeekCount,
  });
}

class _DraftImprovementReport {
  final ProductionAssistantPlanDraftPayload currentPayload;
  final ProductionAssistantPlanDraftPayload improvedPayload;
  final _AssistantProjectionSummary beforeProjection;
  final _AssistantProjectionSummary afterProjection;
  final int genericTaskCount;
  final int missingInstructionCount;
  final int phaseMismatchCount;
  final int underfilledWeekCount;
  final int oneDayWeekCount;
  final int twoDayWeekCount;
  final int afterUnderfilledWeekCount;
  final int redundantSupervisionCount;
  final int supervisionOnlyWeekCount;
  final int expandedGenericTaskCount;
  final int removedSupervisionCount;
  final int phaseRebucketedCount;
  final int instructionsAddedCount;
  final int roleAdjustedCount;
  final int insertedSupportTaskCount;
  final int stretchedTaskWindowCount;
  final int densifiedWeekCount;
  final int propagationTaskFixedCount;
  final List<String> unresolvedWarnings;

  const _DraftImprovementReport({
    required this.currentPayload,
    required this.improvedPayload,
    required this.beforeProjection,
    required this.afterProjection,
    required this.genericTaskCount,
    required this.missingInstructionCount,
    required this.phaseMismatchCount,
    required this.underfilledWeekCount,
    required this.oneDayWeekCount,
    required this.twoDayWeekCount,
    required this.afterUnderfilledWeekCount,
    required this.redundantSupervisionCount,
    required this.supervisionOnlyWeekCount,
    required this.expandedGenericTaskCount,
    required this.removedSupervisionCount,
    required this.phaseRebucketedCount,
    required this.instructionsAddedCount,
    required this.roleAdjustedCount,
    required this.insertedSupportTaskCount,
    required this.stretchedTaskWindowCount,
    required this.densifiedWeekCount,
    required this.propagationTaskFixedCount,
    required this.unresolvedWarnings,
  });

  bool get hasChanges =>
      expandedGenericTaskCount > 0 ||
      removedSupervisionCount > 0 ||
      phaseRebucketedCount > 0 ||
      instructionsAddedCount > 0 ||
      roleAdjustedCount > 0 ||
      insertedSupportTaskCount > 0 ||
      stretchedTaskWindowCount > 0 ||
      densifiedWeekCount > 0 ||
      propagationTaskFixedCount > 0;

  List<String> get issueSummaries {
    final lines = <String>[];
    if (genericTaskCount > 0) {
      lines.add(
        "$genericTaskCount tasks still read like placeholders such as Phase execution or Phase monitoring.",
      );
    }
    if (underfilledWeekCount > 0) {
      lines.add(
        "$underfilledWeekCount weeks are still underfilled with two or fewer active days; $oneDayWeekCount of them only show one active day.",
      );
    }
    if (redundantSupervisionCount > 0) {
      lines.add(
        "$redundantSupervisionCount management supervision rows sit in $supervisionOnlyWeekCount mostly empty weeks.",
      );
    }
    if (missingInstructionCount > 0) {
      lines.add(
        "$missingInstructionCount tasks are missing useful instructions or reviewer notes.",
      );
    }
    if (phaseMismatchCount > 0) {
      lines.add(
        "$phaseMismatchCount dated tasks appear to sit under stale phase labels.",
      );
    }
    if (beforeProjection.hasExecutionTaskTracks &&
        beforeProjection.maximumRemainingAcrossTracks > 0) {
      lines.add(
        "Coverage is still incomplete at ${beforeProjection.minimumCoveredAcrossTracks}/${beforeProjection.expectedWorkUnitsPerTrack} units across execution tracks.",
      );
    }
    return lines;
  }

  List<String> get changeSummaries {
    final lines = <String>[];
    if (expandedGenericTaskCount > 0) {
      lines.add(
        "Expanded $expandedGenericTaskCount generic tasks into clearer crop or phase actions.",
      );
    }
    if (propagationTaskFixedCount > 0) {
      lines.add(
        "Corrected $propagationTaskFixedCount seed, transplant, or stand-count tasks so they track establishment and yield basis in the right phase.",
      );
    }
    if (insertedSupportTaskCount > 0) {
      lines.add(
        "Added $insertedSupportTaskCount recurring crop-specific tasks to fill thin lifecycle weeks.",
      );
    }
    if (stretchedTaskWindowCount > 0) {
      lines.add(
        "Extended $stretchedTaskWindowCount field task windows across more realistic working days.",
      );
    }
    if (densifiedWeekCount > 0) {
      lines.add(
        "Improved calendar density across $densifiedWeekCount underfilled weeks.",
      );
    }
    if (removedSupervisionCount > 0) {
      lines.add(
        "Removed $removedSupervisionCount redundant supervision rows from empty weeks.",
      );
    }
    if (phaseRebucketedCount > 0) {
      lines.add(
        "Moved $phaseRebucketedCount dated tasks into better matching phase windows.",
      );
    }
    if (instructionsAddedCount > 0) {
      lines.add(
        "Filled instructions on $instructionsAddedCount tasks that were missing execution guidance.",
      );
    }
    if (roleAdjustedCount > 0) {
      lines.add(
        "Adjusted role logic on $roleAdjustedCount tasks where the title strongly matched another selected role.",
      );
    }
    return lines;
  }

  String get beforeCoverageLabel {
    if (!beforeProjection.hasExecutionTaskTracks) {
      return "No execution tracks";
    }
    return "${beforeProjection.minimumCoveredAcrossTracks}/${beforeProjection.expectedWorkUnitsPerTrack}";
  }

  String get afterCoverageLabel {
    if (!afterProjection.hasExecutionTaskTracks) {
      return "No execution tracks";
    }
    return "${afterProjection.minimumCoveredAcrossTracks}/${afterProjection.expectedWorkUnitsPerTrack}";
  }

  String get snackSummary {
    final segments = <String>[];
    if (expandedGenericTaskCount > 0) {
      segments.add("expanded $expandedGenericTaskCount tasks");
    }
    if (propagationTaskFixedCount > 0) {
      segments.add("fixed $propagationTaskFixedCount planting tasks");
    }
    if (insertedSupportTaskCount > 0) {
      segments.add("added $insertedSupportTaskCount recurring tasks");
    }
    if (stretchedTaskWindowCount > 0) {
      segments.add("stretched $stretchedTaskWindowCount task windows");
    }
    if (densifiedWeekCount > 0) {
      segments.add("densified $densifiedWeekCount weeks");
    }
    if (removedSupervisionCount > 0) {
      segments.add("removed $removedSupervisionCount supervision rows");
    }
    if (phaseRebucketedCount > 0) {
      segments.add("fixed $phaseRebucketedCount phase labels");
    }
    if (instructionsAddedCount > 0) {
      segments.add("filled $instructionsAddedCount task notes");
    }
    if (roleAdjustedCount > 0) {
      segments.add("realigned $roleAdjustedCount task roles");
    }
    if (segments.isEmpty) {
      return "Draft inspected. No safe automatic changes were applied.";
    }
    return "Draft improved: ${segments.join(", ")}.";
  }
}

class _StageGateTaskEntry {
  final int phaseIndex;
  final int taskIndex;
  final int phaseOrder;
  final ProductionAssistantPlanTask task;
  final DateTime startDate;
  final DateTime dueDate;
  final int lifecycleRank;
  final int projectedWorkUnits;

  const _StageGateTaskEntry({
    required this.phaseIndex,
    required this.taskIndex,
    required this.phaseOrder,
    required this.task,
    required this.startDate,
    required this.dueDate,
    required this.lifecycleRank,
    required this.projectedWorkUnits,
  });
}

class _StageGateResequenceResult {
  final List<ProductionAssistantPlanPhase> phases;
  final int resequencedTaskCount;
  final int blockedTaskCount;
  final int autofilledBlockedSlotCount;

  const _StageGateResequenceResult({
    required this.phases,
    required this.resequencedTaskCount,
    required this.blockedTaskCount,
    required this.autofilledBlockedSlotCount,
  });
}
