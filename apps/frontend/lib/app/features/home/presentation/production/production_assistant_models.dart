/// lib/app/features/home/presentation/production/production_assistant_models.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Models for production assistant chat turns and plan draft envelopes.
///
/// HOW:
/// - Parses backend assistant turn responses into strongly typed Dart models.
/// - Keeps action-specific payload parsing centralized for screen simplicity.
///
/// WHY:
/// - Prevents brittle map lookups in widgets.
/// - Ensures safe defaults so chat UI never crashes on partial payloads.
library;

import 'package:frontend/app/core/debug/app_debug.dart';

const String _logTag = "PRODUCTION_ASSISTANT_MODELS";

const String productionAssistantActionSuggestions = "suggestions";
const String productionAssistantActionClarify = "clarify";
const String productionAssistantActionDraftProduct = "draft_product";
const String productionAssistantActionPlanDraft = "plan_draft";
const String _assistantPhaseTypeFinite = "finite";
const String _assistantPhaseTypeMonitoring = "monitoring";

// WHY: Assistant preview must preserve lifecycle semantics from backend draft payload.
String _normalizeAssistantPhaseTypeInput(String rawValue) {
  final normalized = rawValue.trim().toLowerCase();
  if (normalized == _assistantPhaseTypeMonitoring) {
    return _assistantPhaseTypeMonitoring;
  }
  return _assistantPhaseTypeFinite;
}

// WHY: Assistant preview week cards already provide week context; remove week suffixes from task titles to avoid duplicated/conflicting labels.
String _stripWeekLabelFromTaskTitle(String rawTitle) {
  final trimmed = rawTitle.trim();
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
  final withoutParenthesizedWeekNumber = withoutAnyParenthesizedWeek.replaceAll(
    RegExp(r"\s*[-–—]?\s*\(\s*week\s*[-:]?\s*\d+\s*\)", caseSensitive: false),
    "",
  );
  final withoutLooseWeek = withoutParenthesizedWeekNumber.replaceAll(
    RegExp(r"\s*[-–—]?\s*week\s*[-:]?\s*\d+\b", caseSensitive: false),
    "",
  );
  final compact = withoutLooseWeek.replaceAll(RegExp(r"\s{2,}"), " ").trim();
  return compact.replaceAll(RegExp(r"\(\s*\)"), "").trim();
}

class ProductionAssistantTurnResponse {
  final String message;
  final ProductionAssistantTurn turn;

  const ProductionAssistantTurnResponse({
    required this.message,
    required this.turn,
  });

  factory ProductionAssistantTurnResponse.fromJson(Map<String, dynamic> json) {
    final turnMap = (json["turn"] ?? const <String, dynamic>{});
    final parsed = ProductionAssistantTurnResponse(
      message: (json["message"] ?? "").toString().trim(),
      turn: ProductionAssistantTurn.fromJson(
        turnMap is Map<String, dynamic> ? turnMap : const <String, dynamic>{},
      ),
    );
    AppDebug.log(
      _logTag,
      "turn parsed",
      extra: {
        "action": parsed.turn.action,
        "messageLength": parsed.message.length,
      },
    );
    return parsed;
  }
}

class ProductionAssistantCatalogSearchResponse {
  final String message;
  final List<ProductionAssistantCatalogItem> items;

  const ProductionAssistantCatalogSearchResponse({
    required this.message,
    required this.items,
  });

  factory ProductionAssistantCatalogSearchResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final items = (json["items"] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductionAssistantCatalogItem.fromJson)
        .toList(growable: false);
    return ProductionAssistantCatalogSearchResponse(
      message: (json["message"] ?? "").toString().trim(),
      items: items,
    );
  }
}

class ProductionAssistantCropLifecyclePreviewResponse {
  final String message;
  final ProductionAssistantCropLifecyclePreview lifecycle;
  final String lifecycleSource;

  const ProductionAssistantCropLifecyclePreviewResponse({
    required this.message,
    required this.lifecycle,
    required this.lifecycleSource,
  });

  factory ProductionAssistantCropLifecyclePreviewResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final lifecycleMap = (json["lifecycle"] ?? const <String, dynamic>{});
    return ProductionAssistantCropLifecyclePreviewResponse(
      message: (json["message"] ?? "").toString().trim(),
      lifecycle: ProductionAssistantCropLifecyclePreview.fromJson(
        lifecycleMap is Map<String, dynamic>
            ? lifecycleMap
            : const <String, dynamic>{},
      ),
      lifecycleSource: (json["lifecycleSource"] ?? "").toString().trim(),
    );
  }
}

class ProductionAssistantCropLifecyclePreview {
  final String product;
  final int minDays;
  final int maxDays;
  final List<String> phases;

  const ProductionAssistantCropLifecyclePreview({
    required this.product,
    required this.minDays,
    required this.maxDays,
    required this.phases,
  });

  String get lifecycleLabel {
    if (minDays > 0 && maxDays > 0) {
      return "$minDays-$maxDays days";
    }
    if (maxDays > 0) {
      return "$maxDays days";
    }
    return "Lifecycle unresolved";
  }

  factory ProductionAssistantCropLifecyclePreview.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionAssistantCropLifecyclePreview(
      product: (json["product"] ?? "").toString().trim(),
      minDays: int.tryParse(json["minDays"]?.toString() ?? "") ?? 0,
      maxDays: int.tryParse(json["maxDays"]?.toString() ?? "") ?? 0,
      phases: (json["phases"] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ProductionAssistantCatalogItem {
  final String id;
  final String cropKey;
  final String name;
  final List<String> aliases;
  final String source;
  final int minDays;
  final int maxDays;
  final List<String> phases;
  final String profileKind;
  final String category;
  final String variety;
  final String plantType;
  final String summary;
  final String scientificName;
  final String family;
  final String verificationStatus;
  final ProductionAssistantClimateDetails climate;
  final ProductionAssistantSoilDetails soil;
  final ProductionAssistantWaterDetails water;
  final ProductionAssistantPropagationDetails propagation;
  final ProductionAssistantHarvestWindowDetails harvestWindow;
  final List<ProductionAssistantSourceProvenanceEntry> sourceProvenance;
  final String linkedProductId;
  final String linkedProductName;
  final bool linkedProductActive;

  const ProductionAssistantCatalogItem({
    required this.id,
    required this.cropKey,
    required this.name,
    required this.aliases,
    required this.source,
    required this.minDays,
    required this.maxDays,
    required this.phases,
    required this.profileKind,
    required this.category,
    required this.variety,
    required this.plantType,
    required this.summary,
    required this.scientificName,
    required this.family,
    required this.verificationStatus,
    required this.climate,
    required this.soil,
    required this.water,
    required this.propagation,
    required this.harvestWindow,
    required this.sourceProvenance,
    required this.linkedProductId,
    required this.linkedProductName,
    required this.linkedProductActive,
  });

  bool get hasLinkedProduct => linkedProductId.trim().isNotEmpty;
  bool get hasLifecycle => minDays > 0 || maxDays > 0;
  bool get hasScientificIdentity =>
      scientificName.trim().isNotEmpty || family.trim().isNotEmpty;
  bool get hasAgronomyDetails =>
      climate.hasDetails ||
      soil.hasDetails ||
      water.hasDetails ||
      propagation.hasDetails ||
      harvestWindow.hasDetails;
  String get primarySourceLabel =>
      sourceProvenance.isNotEmpty ? sourceProvenance.first.sourceLabel : "";

  String get lifecycleLabel {
    if (minDays > 0 && maxDays > 0) {
      return "$minDays-$maxDays days";
    }
    if (maxDays > 0) {
      return "$maxDays days";
    }
    return "Resolve lifecycle";
  }

  factory ProductionAssistantCatalogItem.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantCatalogItem(
      id: (json["id"] ?? "").toString().trim(),
      cropKey: (json["cropKey"] ?? "").toString().trim(),
      name: (json["name"] ?? "").toString().trim(),
      aliases: (json["aliases"] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      source: (json["source"] ?? "").toString().trim(),
      minDays: int.tryParse(json["minDays"]?.toString() ?? "") ?? 0,
      maxDays: int.tryParse(json["maxDays"]?.toString() ?? "") ?? 0,
      phases: (json["phases"] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      profileKind: (json["profileKind"] ?? "").toString().trim(),
      category: (json["category"] ?? "").toString().trim(),
      variety: (json["variety"] ?? "").toString().trim(),
      plantType: (json["plantType"] ?? "").toString().trim(),
      summary: (json["summary"] ?? "").toString().trim(),
      scientificName: (json["scientificName"] ?? "").toString().trim(),
      family: (json["family"] ?? "").toString().trim(),
      verificationStatus: (json["verificationStatus"] ?? "").toString().trim(),
      climate: ProductionAssistantClimateDetails.fromJson(
        (json["climate"] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      ),
      soil: ProductionAssistantSoilDetails.fromJson(
        (json["soil"] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      ),
      water: ProductionAssistantWaterDetails.fromJson(
        (json["water"] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      ),
      propagation: ProductionAssistantPropagationDetails.fromJson(
        (json["propagation"] as Map<String, dynamic>? ??
            const <String, dynamic>{}),
      ),
      harvestWindow: ProductionAssistantHarvestWindowDetails.fromJson(
        (json["harvestWindow"] as Map<String, dynamic>? ??
            const <String, dynamic>{}),
      ),
      sourceProvenance: (json["sourceProvenance"] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProductionAssistantSourceProvenanceEntry.fromJson)
          .toList(growable: false),
      linkedProductId: (json["linkedProductId"] ?? "").toString().trim(),
      linkedProductName: (json["linkedProductName"] ?? "").toString().trim(),
      linkedProductActive: json["linkedProductActive"] == true,
    );
  }
}

class ProductionAssistantClimateDetails {
  final String lightPreference;
  final String humidityPreference;
  final double? temperatureMinC;
  final double? temperatureMaxC;
  final double? rainfallMinMm;
  final double? rainfallMaxMm;

  const ProductionAssistantClimateDetails({
    required this.lightPreference,
    required this.humidityPreference,
    required this.temperatureMinC,
    required this.temperatureMaxC,
    required this.rainfallMinMm,
    required this.rainfallMaxMm,
  });

  bool get hasDetails =>
      lightPreference.isNotEmpty ||
      humidityPreference.isNotEmpty ||
      temperatureMinC != null ||
      temperatureMaxC != null ||
      rainfallMinMm != null ||
      rainfallMaxMm != null;

  String get temperatureLabel {
    if (temperatureMinC != null && temperatureMaxC != null) {
      return "${temperatureMinC!.toStringAsFixed(0)}-${temperatureMaxC!.toStringAsFixed(0)} C";
    }
    if (temperatureMaxC != null) {
      return "${temperatureMaxC!.toStringAsFixed(0)} C";
    }
    return "";
  }

  String get rainfallLabel {
    if (rainfallMinMm != null && rainfallMaxMm != null) {
      return "${rainfallMinMm!.toStringAsFixed(0)}-${rainfallMaxMm!.toStringAsFixed(0)} mm";
    }
    if (rainfallMaxMm != null) {
      return "${rainfallMaxMm!.toStringAsFixed(0)} mm";
    }
    return "";
  }

  factory ProductionAssistantClimateDetails.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionAssistantClimateDetails(
      lightPreference: (json["lightPreference"] ?? "").toString().trim(),
      humidityPreference: (json["humidityPreference"] ?? "").toString().trim(),
      temperatureMinC: double.tryParse(
        json["temperatureMinC"]?.toString() ?? "",
      ),
      temperatureMaxC: double.tryParse(
        json["temperatureMaxC"]?.toString() ?? "",
      ),
      rainfallMinMm: double.tryParse(json["rainfallMinMm"]?.toString() ?? ""),
      rainfallMaxMm: double.tryParse(json["rainfallMaxMm"]?.toString() ?? ""),
    );
  }
}

class ProductionAssistantSoilDetails {
  final double? phMin;
  final double? phMax;
  final String fertility;
  final String drainage;

  const ProductionAssistantSoilDetails({
    required this.phMin,
    required this.phMax,
    required this.fertility,
    required this.drainage,
  });

  bool get hasDetails =>
      phMin != null ||
      phMax != null ||
      fertility.isNotEmpty ||
      drainage.isNotEmpty;

  String get phLabel {
    if (phMin != null && phMax != null) {
      return "${phMin!.toStringAsFixed(1)}-${phMax!.toStringAsFixed(1)}";
    }
    if (phMax != null) {
      return phMax!.toStringAsFixed(1);
    }
    return "";
  }

  factory ProductionAssistantSoilDetails.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantSoilDetails(
      phMin: double.tryParse(json["phMin"]?.toString() ?? ""),
      phMax: double.tryParse(json["phMax"]?.toString() ?? ""),
      fertility: (json["fertility"] ?? "").toString().trim(),
      drainage: (json["drainage"] ?? "").toString().trim(),
    );
  }
}

class ProductionAssistantWaterDetails {
  final String requirement;

  const ProductionAssistantWaterDetails({required this.requirement});

  bool get hasDetails => requirement.isNotEmpty;

  factory ProductionAssistantWaterDetails.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantWaterDetails(
      requirement: (json["requirement"] ?? "").toString().trim(),
    );
  }
}

class ProductionAssistantPropagationDetails {
  final List<String> methods;

  const ProductionAssistantPropagationDetails({required this.methods});

  bool get hasDetails => methods.isNotEmpty;

  factory ProductionAssistantPropagationDetails.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionAssistantPropagationDetails(
      methods: (json["methods"] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ProductionAssistantHarvestWindowDetails {
  final int earliestDays;
  final int latestDays;

  const ProductionAssistantHarvestWindowDetails({
    required this.earliestDays,
    required this.latestDays,
  });

  bool get hasDetails => earliestDays > 0 || latestDays > 0;

  factory ProductionAssistantHarvestWindowDetails.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionAssistantHarvestWindowDetails(
      earliestDays: int.tryParse(json["earliestDays"]?.toString() ?? "") ?? 0,
      latestDays: int.tryParse(json["latestDays"]?.toString() ?? "") ?? 0,
    );
  }
}

class ProductionAssistantSourceProvenanceEntry {
  final String sourceKey;
  final String sourceLabel;

  const ProductionAssistantSourceProvenanceEntry({
    required this.sourceKey,
    required this.sourceLabel,
  });

  factory ProductionAssistantSourceProvenanceEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProductionAssistantSourceProvenanceEntry(
      sourceKey: (json["sourceKey"] ?? "").toString().trim(),
      sourceLabel: (json["sourceLabel"] ?? "").toString().trim(),
    );
  }
}

class ProductionAssistantTurn {
  final String action;
  final String message;
  final ProductionAssistantSuggestionsPayload? suggestionsPayload;
  final ProductionAssistantClarifyPayload? clarifyPayload;
  final ProductionAssistantDraftProductPayload? draftProductPayload;
  final ProductionAssistantPlanDraftPayload? planDraftPayload;

  const ProductionAssistantTurn({
    required this.action,
    required this.message,
    required this.suggestionsPayload,
    required this.clarifyPayload,
    required this.draftProductPayload,
    required this.planDraftPayload,
  });

  bool get isSuggestions => action == productionAssistantActionSuggestions;
  bool get isClarify => action == productionAssistantActionClarify;
  bool get isDraftProduct => action == productionAssistantActionDraftProduct;
  bool get isPlanDraft => action == productionAssistantActionPlanDraft;

  factory ProductionAssistantTurn.fromJson(Map<String, dynamic> json) {
    final action = (json["action"] ?? "").toString().trim();
    final payloadMap = (json["payload"] ?? const <String, dynamic>{});
    final payload = payloadMap is Map<String, dynamic>
        ? payloadMap
        : const <String, dynamic>{};

    final suggestionsPayload = action == productionAssistantActionSuggestions
        ? ProductionAssistantSuggestionsPayload.fromJson(payload)
        : null;
    final clarifyPayload = action == productionAssistantActionClarify
        ? ProductionAssistantClarifyPayload.fromJson(payload)
        : null;
    final draftProductPayload = action == productionAssistantActionDraftProduct
        ? ProductionAssistantDraftProductPayload.fromJson(payload)
        : null;
    final planDraftPayload = action == productionAssistantActionPlanDraft
        ? ProductionAssistantPlanDraftPayload.fromJson(payload)
        : null;

    return ProductionAssistantTurn(
      action: action,
      message: (json["message"] ?? "").toString().trim(),
      suggestionsPayload: suggestionsPayload,
      clarifyPayload: clarifyPayload,
      draftProductPayload: draftProductPayload,
      planDraftPayload: planDraftPayload,
    );
  }
}

class ProductionAssistantSuggestionsPayload {
  final List<String> suggestions;

  const ProductionAssistantSuggestionsPayload({required this.suggestions});

  factory ProductionAssistantSuggestionsPayload.fromJson(
    Map<String, dynamic> json,
  ) {
    final suggestions = (json["suggestions"] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    AppDebug.log(
      _logTag,
      "suggestions payload parsed",
      extra: {"count": suggestions.length},
    );
    return ProductionAssistantSuggestionsPayload(suggestions: suggestions);
  }
}

class ProductionAssistantClarifyPayload {
  final String question;
  final List<String> choices;
  final String requiredField;
  final String contextSummary;

  const ProductionAssistantClarifyPayload({
    required this.question,
    required this.choices,
    required this.requiredField,
    required this.contextSummary,
  });

  factory ProductionAssistantClarifyPayload.fromJson(
    Map<String, dynamic> json,
  ) {
    final choices = (json["choices"] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return ProductionAssistantClarifyPayload(
      question: (json["question"] ?? "").toString().trim(),
      choices: choices,
      requiredField: (json["requiredField"] ?? "").toString().trim(),
      contextSummary: (json["contextSummary"] ?? "").toString().trim(),
    );
  }
}

class ProductionAssistantDraftProductPayload {
  final ProductionAssistantDraftProduct draftProduct;
  final ProductionAssistantDraftProduct createProductPayload;
  final String confirmationQuestion;

  const ProductionAssistantDraftProductPayload({
    required this.draftProduct,
    required this.createProductPayload,
    required this.confirmationQuestion,
  });

  factory ProductionAssistantDraftProductPayload.fromJson(
    Map<String, dynamic> json,
  ) {
    final draftMap = json["draftProduct"];
    final createMap = json["createProductPayload"];
    return ProductionAssistantDraftProductPayload(
      draftProduct: ProductionAssistantDraftProduct.fromJson(
        draftMap is Map<String, dynamic> ? draftMap : const <String, dynamic>{},
      ),
      createProductPayload: ProductionAssistantDraftProduct.fromJson(
        createMap is Map<String, dynamic>
            ? createMap
            : const <String, dynamic>{},
      ),
      confirmationQuestion: (json["confirmationQuestion"] ?? "")
          .toString()
          .trim(),
    );
  }
}

class ProductionAssistantDraftProduct {
  final String name;
  final String category;
  final String unit;
  final String notes;
  final int lifecycleDaysEstimate;

  const ProductionAssistantDraftProduct({
    required this.name,
    required this.category,
    required this.unit,
    required this.notes,
    required this.lifecycleDaysEstimate,
  });

  factory ProductionAssistantDraftProduct.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantDraftProduct(
      name: (json["name"] ?? "").toString().trim(),
      category: (json["category"] ?? "").toString().trim(),
      unit: (json["unit"] ?? "").toString().trim(),
      notes: (json["notes"] ?? "").toString().trim(),
      lifecycleDaysEstimate:
          int.tryParse(json["lifecycleDaysEstimate"]?.toString() ?? "") ?? 1,
    );
  }
}

class ProductionAssistantPlanDraftPayload {
  final String productId;
  final String productName;
  final String startDate;
  final String endDate;
  final int days;
  final int weeks;
  final List<ProductionAssistantPlanPhase> phases;
  final List<ProductionAssistantPlanWarning> warnings;
  final ProductionAssistantPlannerMeta? plannerMeta;
  final ProductionAssistantLifecycle? lifecycle;

  const ProductionAssistantPlanDraftPayload({
    required this.productId,
    required this.productName,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.weeks,
    required this.phases,
    required this.warnings,
    required this.plannerMeta,
    required this.lifecycle,
  });

  factory ProductionAssistantPlanDraftPayload.fromJson(
    Map<String, dynamic> json,
  ) {
    final phases = (json["phases"] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductionAssistantPlanPhase.fromJson)
        .toList();
    final warnings = (json["warnings"] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductionAssistantPlanWarning.fromJson)
        .toList();
    final plannerMetaMap = json["plannerMeta"];
    final lifecycleMap = json["lifecycle"];
    final parsed = ProductionAssistantPlanDraftPayload(
      productId: (json["productId"] ?? "").toString().trim(),
      productName: (json["productName"] ?? "").toString().trim(),
      startDate: (json["startDate"] ?? "").toString().trim(),
      endDate: (json["endDate"] ?? "").toString().trim(),
      days: int.tryParse(json["days"]?.toString() ?? "") ?? 0,
      weeks: int.tryParse(json["weeks"]?.toString() ?? "") ?? 0,
      phases: phases,
      warnings: warnings,
      plannerMeta: plannerMetaMap is Map<String, dynamic>
          ? ProductionAssistantPlannerMeta.fromJson(plannerMetaMap)
          : null,
      lifecycle: lifecycleMap is Map<String, dynamic>
          ? ProductionAssistantLifecycle.fromJson(lifecycleMap)
          : null,
    );
    AppDebug.log(
      _logTag,
      "plan_draft payload parsed",
      extra: {
        "phaseCount": parsed.phases.length,
        "warningCount": parsed.warnings.length,
        "plannerVersion": parsed.plannerMeta?.version ?? "legacy",
      },
    );
    return parsed;
  }
}

class ProductionAssistantPlannerMeta {
  final String version;
  final String lifecycleSource;
  final int retryCount;
  final String scheduleSource;

  const ProductionAssistantPlannerMeta({
    required this.version,
    required this.lifecycleSource,
    required this.retryCount,
    required this.scheduleSource,
  });

  factory ProductionAssistantPlannerMeta.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantPlannerMeta(
      version: (json["version"] ?? "").toString().trim(),
      lifecycleSource: (json["lifecycleSource"] ?? "").toString().trim(),
      retryCount: int.tryParse(json["retryCount"]?.toString() ?? "") ?? 0,
      scheduleSource: (json["scheduleSource"] ?? "").toString().trim(),
    );
  }
}

class ProductionAssistantLifecycle {
  final String product;
  final int minDays;
  final int maxDays;
  final List<String> phases;

  const ProductionAssistantLifecycle({
    required this.product,
    required this.minDays,
    required this.maxDays,
    required this.phases,
  });

  factory ProductionAssistantLifecycle.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantLifecycle(
      product: (json["product"] ?? "").toString().trim(),
      minDays: int.tryParse(json["minDays"]?.toString() ?? "") ?? 0,
      maxDays: int.tryParse(json["maxDays"]?.toString() ?? "") ?? 0,
      phases: (json["phases"] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }
}

class ProductionAssistantPlanPhase {
  final String name;
  final int order;
  final int estimatedDays;
  final String phaseType;
  final int requiredUnits;
  final double minRatePerFarmerHour;
  final double targetRatePerFarmerHour;
  final double plannedHoursPerDay;
  final int biologicalMinDays;
  final List<ProductionAssistantPlanTask> tasks;

  const ProductionAssistantPlanPhase({
    required this.name,
    required this.order,
    required this.estimatedDays,
    required this.phaseType,
    required this.requiredUnits,
    this.minRatePerFarmerHour = 0.1,
    this.targetRatePerFarmerHour = 0.2,
    this.plannedHoursPerDay = 3,
    this.biologicalMinDays = 0,
    required this.tasks,
  });

  factory ProductionAssistantPlanPhase.fromJson(Map<String, dynamic> json) {
    final minRatePerFarmerHourRaw =
        double.tryParse(json["minRatePerFarmerHour"]?.toString() ?? "") ?? 0.1;
    final minRatePerFarmerHour = minRatePerFarmerHourRaw <= 0
        ? 0.1
        : minRatePerFarmerHourRaw;
    final targetRatePerFarmerHourRaw =
        double.tryParse(json["targetRatePerFarmerHour"]?.toString() ?? "") ??
        0.2;
    final plannedHoursPerDay =
        double.tryParse(json["plannedHoursPerDay"]?.toString() ?? "") ?? 3;
    final biologicalMinDays =
        int.tryParse(json["biologicalMinDays"]?.toString() ?? "") ?? 0;
    return ProductionAssistantPlanPhase(
      name: (json["name"] ?? "").toString().trim(),
      order: int.tryParse(json["order"]?.toString() ?? "") ?? 1,
      estimatedDays: int.tryParse(json["estimatedDays"]?.toString() ?? "") ?? 1,
      phaseType: _normalizeAssistantPhaseTypeInput(
        (json["phaseType"] ?? "").toString(),
      ),
      requiredUnits: int.tryParse(json["requiredUnits"]?.toString() ?? "") ?? 0,
      minRatePerFarmerHour: minRatePerFarmerHour,
      targetRatePerFarmerHour: targetRatePerFarmerHourRaw < minRatePerFarmerHour
          ? minRatePerFarmerHour
          : targetRatePerFarmerHourRaw,
      plannedHoursPerDay: plannedHoursPerDay <= 0 ? 3 : plannedHoursPerDay,
      biologicalMinDays: biologicalMinDays < 0 ? 0 : biologicalMinDays,
      tasks: (json["tasks"] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProductionAssistantPlanTask.fromJson)
          .toList(),
    );
  }
}

class ProductionAssistantPlanTask {
  final String title;
  final String roleRequired;
  final int requiredHeadcount;
  final int weight;
  final String instructions;
  final String taskType;
  final String sourceTemplateKey;
  final String recurrenceGroupKey;
  final int occurrenceIndex;
  final DateTime? startDate;
  final DateTime? dueDate;
  final List<String> assignedStaffProfileIds;

  const ProductionAssistantPlanTask({
    required this.title,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.weight,
    required this.instructions,
    required this.taskType,
    required this.sourceTemplateKey,
    required this.recurrenceGroupKey,
    required this.occurrenceIndex,
    required this.startDate,
    required this.dueDate,
    required this.assignedStaffProfileIds,
  });

  factory ProductionAssistantPlanTask.fromJson(Map<String, dynamic> json) {
    final assignedIds =
        (json["assignedStaffProfileIds"] as List<dynamic>? ?? const [])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
    final rawTitle = (json["title"] ?? "").toString().trim();
    return ProductionAssistantPlanTask(
      title: _stripWeekLabelFromTaskTitle(rawTitle),
      roleRequired: (json["roleRequired"] ?? "").toString().trim(),
      requiredHeadcount:
          int.tryParse(json["requiredHeadcount"]?.toString() ?? "") ?? 1,
      weight: int.tryParse(json["weight"]?.toString() ?? "") ?? 1,
      instructions: (json["instructions"] ?? "").toString().trim(),
      taskType: (json["taskType"] ?? "").toString().trim(),
      sourceTemplateKey: (json["sourceTemplateKey"] ?? "").toString().trim(),
      recurrenceGroupKey: (json["recurrenceGroupKey"] ?? "").toString().trim(),
      occurrenceIndex:
          int.tryParse(json["occurrenceIndex"]?.toString() ?? "") ?? 0,
      startDate: DateTime.tryParse((json["startDate"] ?? "").toString()),
      dueDate: DateTime.tryParse((json["dueDate"] ?? "").toString()),
      assignedStaffProfileIds: assignedIds,
    );
  }
}

class ProductionAssistantPlanWarning {
  final String code;
  final String message;

  const ProductionAssistantPlanWarning({
    required this.code,
    required this.message,
  });

  factory ProductionAssistantPlanWarning.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantPlanWarning(
      code: (json["code"] ?? "").toString().trim(),
      message: (json["message"] ?? "").toString().trim(),
    );
  }
}
