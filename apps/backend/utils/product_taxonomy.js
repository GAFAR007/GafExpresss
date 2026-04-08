/**
 * utils/product_taxonomy.js
 * -------------------------
 * WHAT:
 * - Shared sanitizers for product taxonomy fields.
 *
 * WHY:
 * - Product categories/subcategories/brands come from UI-controlled catalogs
 *   but still need backend normalization.
 * - Keeps create/update flows consistent across admin and business services.
 */

function normalizeOptionalProductText(value, maxLength = 80) {
  if (value == null) {
    return "";
  }

  const text = value.toString().trim().replace(/\s+/g, " ");
  if (!text) {
    return "";
  }

  return text.slice(0, maxLength);
}

function sanitizeProductTaxonomyFields(data = {}, options = {}) {
  const category = normalizeOptionalProductText(data.category, 80);
  const subcategory = normalizeOptionalProductText(data.subcategory, 80);
  const brand = normalizeOptionalProductText(data.brand, 80);
  const requireBrand = options.requireBrand === true;

  if (!category && subcategory) {
    throw new Error("Category is required when subcategory is set");
  }

  if (requireBrand && !brand) {
    throw new Error("Brand is required");
  }

  return {
    category,
    subcategory,
    brand,
  };
}

function normalizeProductOptionList(values, maxItems = 12, maxLength = 40) {
  if (values == null) {
    return [];
  }

  const rawValues = Array.isArray(values) ? values : [values];
  const normalized = [];
  const seen = new Set();

  for (const value of rawValues) {
    const text = normalizeOptionalProductText(value, maxLength);
    if (!text) {
      continue;
    }

    const key = text.toLowerCase();
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    normalized.push(text);

    if (normalized.length >= maxItems) {
      break;
    }
  }

  return normalized;
}

const LEGACY_MEASURE_UNIT_BY_PACKAGE_TYPE = {
  piece: 'piece',
  pack: 'pack',
  bag: 'bag',
  sack: 'sack',
  carton: 'carton',
  box: 'box',
  bundle: 'bundle',
  pair: 'pair',
  bottle: 'bottle',
  can: 'can',
  jar: 'jar',
  tube: 'tube',
  crate: 'crate',
  tray: 'tray',
  set: 'set',
  dozen: 'dozen',
  roll: 'roll',
  bale: 'bale',
  bunch: 'bunch',
  basket: 'basket',
  sachet: 'sachet',
};

function normalizeMeasureUnit(value, maxLength = 24) {
  const text = normalizeOptionalProductText(value, maxLength);
  if (!text) {
    return '';
  }

  const lowered = text.toLowerCase();
  if (lowered === 'l') {
    return 'L';
  }
  return lowered;
}

function normalizeMeasureQuantity(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }

  return Math.round(parsed * 1000) / 1000;
}

function buildLegacySellingOptions(data = {}) {
  const legacyUnits = normalizeProductOptionList(data.sellingUnits, 12, 40);
  const defaultUnit = normalizeOptionalProductText(data.defaultSellingUnit, 40);

  return legacyUnits.map((packageType, index) => ({
    packageType,
    quantity: 1,
    measurementUnit:
      LEGACY_MEASURE_UNIT_BY_PACKAGE_TYPE[packageType.toLowerCase()] || 'unit',
    isDefault:
      packageType.toLowerCase() === defaultUnit.toLowerCase() ||
      (!defaultUnit && index === 0),
  }));
}

function sanitizeProductSellingFields(data = {}, options = {}) {
  const requireUnits = options.requireUnits === true;
  const defaultPackageType = normalizeOptionalProductText(
    data.defaultSellingUnit,
    40
  ).toLowerCase();
  const rawOptions = Array.isArray(data.sellingOptions)
    ? data.sellingOptions
    : buildLegacySellingOptions(data);
  const seen = new Set();
  let sellingOptions = [];

  for (const rawOption of rawOptions) {
    const packageType = normalizeOptionalProductText(
      rawOption?.packageType || rawOption?.label || rawOption?.name,
      40
    );
    const quantity = normalizeMeasureQuantity(rawOption?.quantity);
    const measurementUnit = normalizeMeasureUnit(
      rawOption?.measurementUnit ||
        rawOption?.measureUnit ||
        rawOption?.unit ||
        rawOption?.measurement
    );

    if (!packageType || quantity == null || !measurementUnit) {
      continue;
    }

    const key = `${packageType.toLowerCase()}|${quantity}|${measurementUnit.toLowerCase()}`;
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    sellingOptions.push({
      packageType,
      quantity,
      measurementUnit,
      isDefault:
        rawOption?.isDefault === true ||
        (defaultPackageType &&
          packageType.toLowerCase() === defaultPackageType),
    });
  }

  if (sellingOptions.length > 0) {
    let defaultIndex = sellingOptions.findIndex(
      (option) => option.isDefault === true
    );
    if (defaultIndex < 0) {
      defaultIndex = 0;
    }

    sellingOptions = sellingOptions.map((option, index) => ({
      ...option,
      isDefault: index === defaultIndex,
    }));
  }

  if (requireUnits && sellingOptions.length === 0) {
    throw new Error('At least one selling option is required');
  }

  const sellingUnits = normalizeProductOptionList(
    sellingOptions.map((option) => option.packageType),
    12,
    40
  );
  const defaultSellingUnit =
    sellingOptions.find((option) => option.isDefault)?.packageType || '';

  return {
    sellingOptions,
    sellingUnits,
    defaultSellingUnit,
  };
}

module.exports = {
  buildLegacySellingOptions,
  normalizeOptionalProductText,
  normalizeMeasureUnit,
  normalizeMeasureQuantity,
  normalizeProductOptionList,
  sanitizeProductTaxonomyFields,
  sanitizeProductSellingFields,
};
