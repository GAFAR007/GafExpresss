/**
 * apps/backend/services/planner/cropProfileSources.js
 * ---------------------------------------------------
 * WHAT:
 * - Source registry + provenance helpers for crop profile imports.
 *
 * WHY:
 * - Crop profile records must keep provenance explicit when multiple vetted datasets are mixed.
 * - Scripts need one normalization point for seed manifests, API imports, and future source snapshots.
 */

const CROP_PROFILE_SOURCE_REGISTRY =
  Object.freeze({
    manifest_seed: {
      key: "manifest_seed",
      label: "Seed manifest",
      authority:
        "Internal crop curation queue",
      sourceUrl: "",
      license: "internal",
      verificationStatus: "seed_manifest",
    },
    trefle: {
      key: "trefle",
      label: "Trefle",
      authority:
        "Trefle plant species API",
      sourceUrl: "https://trefle.io/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    geoglam: {
      key: "geoglam",
      label: "GEOGLAM",
      authority:
        "GEOGLAM crop monitor / crop calendar",
      sourceUrl:
        "https://cropmonitor.org/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    fao_ecocrop: {
      key: "fao_ecocrop",
      label: "FAO EcoCrop",
      authority:
        "Food and Agriculture Organization",
      sourceUrl:
        "https://ecocrop.apps.fao.org/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    world_flora_online: {
      key: "world_flora_online",
      label: "World Flora Online",
      authority:
        "World Flora Online Consortium",
      sourceUrl:
        "https://www.worldfloraonline.org/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    usda_grin: {
      key: "usda_grin",
      label: "USDA GRIN",
      authority:
        "United States Department of Agriculture",
      sourceUrl:
        "https://npgsweb.ars-grin.gov/gringlobal/search",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    source_import: {
      key: "source_import",
      label: "Source import",
      authority:
        "Normalized crop profile snapshot import",
      sourceUrl: "",
      license: "varies",
      verificationStatus:
        "source_pending",
    },
    umn_extension: {
      key: "umn_extension",
      label: "UMN Extension",
      authority:
        "University of Minnesota Extension",
      sourceUrl: "https://extension.umn.edu/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    uf_ifas: {
      key: "uf_ifas",
      label: "UF/IFAS",
      authority:
        "University of Florida Institute of Food and Agricultural Sciences",
      sourceUrl: "https://edis.ifas.ufl.edu/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    clemson_extension: {
      key: "clemson_extension",
      label: "Clemson Extension",
      authority:
        "Clemson Cooperative Extension",
      sourceUrl: "https://hgic.clemson.edu/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    arizona_extension: {
      key: "arizona_extension",
      label: "University of Arizona Extension",
      authority:
        "University of Arizona Cooperative Extension",
      sourceUrl: "https://extension.arizona.edu/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    iita: {
      key: "iita",
      label: "IITA",
      authority:
        "International Institute of Tropical Agriculture",
      sourceUrl: "https://www.iita.org/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    irri: {
      key: "irri",
      label: "IRRI",
      authority:
        "International Rice Research Institute",
      sourceUrl: "https://www.irri.org/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
    icco: {
      key: "icco",
      label: "ICCO",
      authority:
        "International Cocoa Organization",
      sourceUrl: "https://www.icco.org/",
      license: "Provider terms",
      verificationStatus:
        "source_verified",
    },
  });

function normalizeCropProfileSourceKey(
  value,
) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function resolveCropProfileSourceDescriptor(
  value,
) {
  const normalizedKey =
    normalizeCropProfileSourceKey(value);
  return (
    CROP_PROFILE_SOURCE_REGISTRY[
      normalizedKey
    ] ||
    CROP_PROFILE_SOURCE_REGISTRY
      .source_import
  );
}

function buildCropProfileProvenanceEntry({
  sourceKey,
  externalId = "",
  sourceUrl = "",
  citation = "",
  notes = "",
  confidence = null,
  verificationStatus = "",
}) {
  const descriptor =
    resolveCropProfileSourceDescriptor(
      sourceKey,
    );
  return {
    sourceKey: descriptor.key,
    sourceLabel: descriptor.label,
    authority: descriptor.authority,
    sourceUrl:
      (sourceUrl || descriptor.sourceUrl || "")
        .toString()
        .trim(),
    citation: (citation || "")
      .toString()
      .trim(),
    license:
      (descriptor.license || "")
        .toString()
        .trim(),
    externalId: (externalId || "")
      .toString()
      .trim(),
    confidence:
      Number.isFinite(Number(confidence)) ?
        Number(confidence)
      : null,
    verificationStatus:
      (verificationStatus ||
        descriptor.verificationStatus ||
        "source_pending")
        .toString()
        .trim(),
    fetchedAt: new Date(),
    notes: (notes || "")
      .toString()
      .trim(),
  };
}

module.exports = {
  CROP_PROFILE_SOURCE_REGISTRY,
  normalizeCropProfileSourceKey,
  resolveCropProfileSourceDescriptor,
  buildCropProfileProvenanceEntry,
};
