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

  const ProductionAssistantPlanDraftPayload({
    required this.productId,
    required this.productName,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.weeks,
    required this.phases,
    required this.warnings,
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
    final parsed = ProductionAssistantPlanDraftPayload(
      productId: (json["productId"] ?? "").toString().trim(),
      productName: (json["productName"] ?? "").toString().trim(),
      startDate: (json["startDate"] ?? "").toString().trim(),
      endDate: (json["endDate"] ?? "").toString().trim(),
      days: int.tryParse(json["days"]?.toString() ?? "") ?? 0,
      weeks: int.tryParse(json["weeks"]?.toString() ?? "") ?? 0,
      phases: phases,
      warnings: warnings,
    );
    AppDebug.log(
      _logTag,
      "plan_draft payload parsed",
      extra: {
        "phaseCount": parsed.phases.length,
        "warningCount": parsed.warnings.length,
      },
    );
    return parsed;
  }
}

class ProductionAssistantPlanPhase {
  final String name;
  final int order;
  final int estimatedDays;
  final List<ProductionAssistantPlanTask> tasks;

  const ProductionAssistantPlanPhase({
    required this.name,
    required this.order,
    required this.estimatedDays,
    required this.tasks,
  });

  factory ProductionAssistantPlanPhase.fromJson(Map<String, dynamic> json) {
    return ProductionAssistantPlanPhase(
      name: (json["name"] ?? "").toString().trim(),
      order: int.tryParse(json["order"]?.toString() ?? "") ?? 1,
      estimatedDays: int.tryParse(json["estimatedDays"]?.toString() ?? "") ?? 1,
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
  final DateTime? startDate;
  final DateTime? dueDate;
  final List<String> assignedStaffProfileIds;

  const ProductionAssistantPlanTask({
    required this.title,
    required this.roleRequired,
    required this.requiredHeadcount,
    required this.weight,
    required this.instructions,
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
