/// lib/app/features/home/presentation/product_selling_option.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Shared structured selling option model for products.
///
/// WHY:
/// - Products can be sold as package + quantity + measurement, not just text.
/// - Keeps form, API, and list labels aligned on one shape.
library;

const Map<String, String> _legacyMeasureUnitByPackageType = {
  "piece": "piece",
  "pack": "pack",
  "bag": "bag",
  "sack": "sack",
  "carton": "carton",
  "box": "box",
  "bundle": "piece",
  "pair": "pair",
  "bottle": "bottle",
  "can": "can",
  "jar": "jar",
  "tube": "tube",
  "crate": "crate",
  "tray": "tray",
  "set": "set",
  "dozen": "piece",
  "roll": "roll",
  "bale": "piece",
  "bunch": "piece",
  "basket": "kg",
  "sachet": "piece",
  "tin": "piece",
  "packet": "piece",
};

String _normalizeSellingText(String? value, {int maxLength = 40}) {
  final text = (value ?? "").trim().replaceAll(RegExp(r"\s+"), " ");
  if (text.isEmpty) {
    return "";
  }
  return text.length <= maxLength ? text : text.substring(0, maxLength);
}

double? parseSellingQuantity(dynamic value) {
  if (value == null) {
    return null;
  }

  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value.toString().trim());
  if (parsed == null || !parsed.isFinite || parsed <= 0) {
    return null;
  }
  return double.parse(parsed.toStringAsFixed(3));
}

String formatSellingQuantity(num value) {
  final normalized = value.toDouble();
  if (normalized == normalized.roundToDouble()) {
    return value.toInt().toString();
  }

  final text = normalized.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r"0+$"), "").replaceFirst(RegExp(r"\.$"), "");
}

String _normalizeMeasureUnit(String? value) {
  final text = _normalizeSellingText(value, maxLength: 24);
  if (text.isEmpty) {
    return "";
  }
  final lowered = text.toLowerCase();
  if (lowered == "l") {
    return "L";
  }
  return lowered;
}

class ProductSellingOption {
  final String packageType;
  final double quantity;
  final String measurementUnit;
  final bool isDefault;

  const ProductSellingOption({
    required this.packageType,
    required this.quantity,
    required this.measurementUnit,
    required this.isDefault,
  });

  String get quantityLabel => formatSellingQuantity(quantity);

  String get displayLabel => "$packageType • $quantityLabel $measurementUnit";

  String get summaryLabel => "$packageType of $quantityLabel $measurementUnit";

  String get signature =>
      "${packageType.toLowerCase()}|${quantityLabel.toLowerCase()}|${measurementUnit.toLowerCase()}";

  Map<String, dynamic> toJson() {
    return {
      "packageType": packageType,
      "quantity": quantity,
      "measurementUnit": measurementUnit,
      "isDefault": isDefault,
    };
  }

  ProductSellingOption copyWith({
    String? packageType,
    double? quantity,
    String? measurementUnit,
    bool? isDefault,
  }) {
    return ProductSellingOption(
      packageType: packageType ?? this.packageType,
      quantity: quantity ?? this.quantity,
      measurementUnit: measurementUnit ?? this.measurementUnit,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  factory ProductSellingOption.fromJson(Map<String, dynamic> json) {
    final packageType = _normalizeSellingText(
      (json["packageType"] ?? json["label"] ?? json["name"]).toString(),
    );
    final quantity = parseSellingQuantity(json["quantity"]) ?? 1;
    final measurementUnit = _normalizeMeasureUnit(
      (json["measurementUnit"] ??
              json["measureUnit"] ??
              json["unit"] ??
              json["measurement"])
          ?.toString(),
    );

    return ProductSellingOption(
      packageType: packageType,
      quantity: quantity,
      measurementUnit: measurementUnit.isEmpty ? "unit" : measurementUnit,
      isDefault: json["isDefault"] == true,
    );
  }
}

List<ProductSellingOption> normalizeSellingOptions(
  Iterable<ProductSellingOption> values,
) {
  final options = <ProductSellingOption>[];
  final seen = <String>{};

  for (final value in values) {
    final packageType = _normalizeSellingText(value.packageType);
    final quantity = parseSellingQuantity(value.quantity);
    final measurementUnit = _normalizeMeasureUnit(value.measurementUnit);
    if (packageType.isEmpty || quantity == null || measurementUnit.isEmpty) {
      continue;
    }

    final option = ProductSellingOption(
      packageType: packageType,
      quantity: quantity,
      measurementUnit: measurementUnit,
      isDefault: value.isDefault,
    );
    if (seen.add(option.signature)) {
      options.add(option);
    }
  }

  if (options.isEmpty) {
    return const [];
  }

  var defaultIndex = options.indexWhere((item) => item.isDefault);
  if (defaultIndex < 0) {
    defaultIndex = 0;
  }

  return [
    for (var index = 0; index < options.length; index += 1)
      options[index].copyWith(isDefault: index == defaultIndex),
  ];
}

List<ProductSellingOption> parseProductSellingOptions({
  dynamic rawSellingOptions,
  dynamic rawSellingUnits,
  dynamic rawDefaultSellingUnit,
}) {
  final parsedOptions = rawSellingOptions is List
      ? rawSellingOptions.whereType<Map>().map(
          (item) =>
              ProductSellingOption.fromJson(Map<String, dynamic>.from(item)),
        )
      : const <ProductSellingOption>[];

  final normalizedOptions = normalizeSellingOptions(parsedOptions);
  if (normalizedOptions.isNotEmpty) {
    return normalizedOptions;
  }

  final legacyDefault = _normalizeSellingText(
    rawDefaultSellingUnit?.toString(),
  ).toLowerCase();
  final legacyUnits = rawSellingUnits is List
      ? rawSellingUnits.map((item) => _normalizeSellingText(item.toString()))
      : const <String>[];

  return normalizeSellingOptions([
    for (var index = 0; index < legacyUnits.length; index += 1)
      ProductSellingOption(
        packageType: legacyUnits.elementAt(index),
        quantity: 1,
        measurementUnit:
            _legacyMeasureUnitByPackageType[legacyUnits
                .elementAt(index)
                .toLowerCase()] ??
            "unit",
        isDefault:
            legacyUnits.elementAt(index).toLowerCase() == legacyDefault ||
            (legacyDefault.isEmpty && index == 0),
      ),
  ]);
}

List<String> deriveSellingUnitsFromOptions(List<ProductSellingOption> options) {
  final units = <String>[];
  final seen = <String>{};

  for (final option in options) {
    final key = option.packageType.toLowerCase();
    if (seen.add(key)) {
      units.add(option.packageType);
    }
  }

  return units;
}

String deriveDefaultSellingUnitFromOptions(List<ProductSellingOption> options) {
  for (final option in options) {
    if (option.isDefault) {
      return option.packageType;
    }
  }
  return options.isNotEmpty ? options.first.packageType : "";
}
