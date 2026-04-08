/**
 * apps/backend/models/ProductionLifecycleProfile.js
 * ------------------------------------------------
 * WHAT:
 * - Stores business-scoped lifecycle reference profiles for production planner V2.
 *
 * WHY:
 * - Keeps crop lifecycle knowledge separate from commerce Product records.
 * - Lets planner V2 reuse resolved lifecycle ranges without repeated API/AI calls.
 * - Preserves tenant safety by scoping cached lifecycle lookups to one business.
 * - Shares the existing productionoutputs collection so we do not need a new Mongo collection on capped Atlas tiers.
 *
 * HOW:
 * - Stores a normalized product key plus optional crop subtype/domain context.
 * - Persists lifecycle min/max days, canonical ordered phases, and source metadata.
 * - Exposes indexed lookup fields so resolver precedence stays deterministic.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const {
  PRODUCTION_DOMAIN_CONTEXTS,
  DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
} = require("../utils/production_engine.config");

debug("Loading ProductionLifecycleProfile model...");

const PRODUCTION_LIFECYCLE_COLLECTION_NAME =
  "productionoutputs";
const PRODUCTION_LIFECYCLE_RECORD_TYPE =
  "crop_profile";

const PRODUCTION_LIFECYCLE_PROFILE_SOURCES = [
  "catalog",
  "cache",
  "agriculture_api",
  "ai_estimate",
  "manifest_seed",
  "source_import",
];

const PRODUCTION_CROP_PROFILE_KINDS = [
  "crop",
  "fruit",
  "plant",
];
const PRODUCTION_CROP_PROFILE_VERIFICATION_STATUSES =
  [
    "seed_manifest",
    "source_pending",
    "source_verified",
    "review_required",
    "manual_verified",
  ];
const PRODUCTION_CROP_PROFILE_LIFECYCLE_STATUSES =
  [
    "missing",
    "estimated",
    "verified",
  ];

const productionLifecycleProfileSchema =
  new mongoose.Schema(
    {
      // WHY: Lifecycle cache must remain tenant-safe when product descriptions differ by business.
      businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        required: true,
        index: true,
      },
      recordType: {
        type: String,
        enum: [PRODUCTION_LIFECYCLE_RECORD_TYPE],
        default: PRODUCTION_LIFECYCLE_RECORD_TYPE,
        index: true,
      },
      // WHY: Product key makes lifecycle lookups deterministic even when display names vary slightly.
      productKey: {
        type: String,
        required: true,
        trim: true,
        lowercase: true,
        index: true,
      },
      // WHY: Persisting the resolved product name keeps lifecycle metadata readable in admin tools.
      productName: {
        type: String,
        required: true,
        trim: true,
      },
      // WHY: Search must find verified crop profiles by common names and provider aliases.
      aliases: {
        type: [String],
        default: [],
      },
      // WHY: Profile kind lets the same store cover staple crops, fruits, and broader plant profiles.
      profileKind: {
        type: String,
        enum: PRODUCTION_CROP_PROFILE_KINDS,
        default: "crop",
        index: true,
      },
      // WHY: Category supports richer search/filter UX than lifecycle alone.
      category: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Variety stores the resolved cultivar/type when a vetted source provides it.
      variety: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Plant type keeps broad classifications like vine/tree/herb visible in the picker.
      plantType: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Search cards need a concise crop summary once richer plant metadata lands.
      summary: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Scientific names are essential for trustworthy crop identity across sources.
      scientificName: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Family helps group related crops and reduce confusion between similar common names.
      family: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Crop subtype allows lifecycle variants such as sweet corn vs grain corn without new tables.
      cropSubtype: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Domain context future-proofs the resolver while keeping farm-first V2 explicit.
      domainContext: {
        type: String,
        enum: PRODUCTION_DOMAIN_CONTEXTS,
        default: DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
        index: true,
      },
      // WHY: Biological bounds must be explicit so validation can reject impossible date ranges.
      minDays: {
        type: Number,
        min: 1,
        default: null,
      },
      maxDays: {
        type: Number,
        min: 1,
        default: null,
      },
      // WHY: Canonical ordered phases drive lifecycle-safe AI prompts and validation.
      phases: {
        type: [String],
        default: [],
      },
      // WHY: Search/import flows need to distinguish missing lifecycle from verified lifecycle.
      lifecycleStatus: {
        type: String,
        enum:
          PRODUCTION_CROP_PROFILE_LIFECYCLE_STATUSES,
        default: "missing",
        index: true,
      },
      // WHY: Source metadata keeps rollout diagnostics explainable and cache precedence observable.
      source: {
        type: String,
        enum: PRODUCTION_LIFECYCLE_PROFILE_SOURCES,
        required: true,
      },
      // WHY: Confidence helps distinguish deterministic catalog records from weaker AI estimates.
      sourceConfidence: {
        type: Number,
        min: 0,
        max: 1,
        default: 1,
      },
      // WHY: Verification state separates seed targets from trusted imported crop profiles.
      verificationStatus: {
        type: String,
        enum:
          PRODUCTION_CROP_PROFILE_VERIFICATION_STATUSES,
        default: "source_pending",
        index: true,
      },
      // WHY: Climate requirements belong in the same store so planner search can surface agronomy context.
      climate: {
        type: {
          climateZones: {
            type: [String],
            default: [],
          },
          lightPreference: {
            type: String,
            trim: true,
            default: "",
          },
          humidityPreference: {
            type: String,
            trim: true,
            default: "",
          },
          temperatureMinC: {
            type: Number,
            default: null,
          },
          temperatureMaxC: {
            type: Number,
            default: null,
          },
          rainfallMinMm: {
            type: Number,
            default: null,
          },
          rainfallMaxMm: {
            type: Number,
            default: null,
          },
          notes: {
            type: String,
            trim: true,
            default: "",
          },
        },
        default: {},
      },
      // WHY: Soil guidance is a core crop detail for production setup and estate matching.
      soil: {
        type: {
          textures: {
            type: [String],
            default: [],
          },
          drainage: {
            type: String,
            trim: true,
            default: "",
          },
          fertility: {
            type: String,
            trim: true,
            default: "",
          },
          phMin: {
            type: Number,
            default: null,
          },
          phMax: {
            type: Number,
            default: null,
          },
          notes: {
            type: String,
            trim: true,
            default: "",
          },
        },
        default: {},
      },
      // WHY: Water demand should be searchable without re-calling source APIs.
      water: {
        type: {
          requirement: {
            type: String,
            trim: true,
            default: "",
          },
          irrigationNotes: {
            type: String,
            trim: true,
            default: "",
          },
          minimumPrecipitationMm: {
            type: Number,
            default: null,
          },
          maximumPrecipitationMm: {
            type: Number,
            default: null,
          },
        },
        default: {},
      },
      // WHY: Propagation method matters for nurseries, seed planning, and variety handling.
      propagation: {
        type: {
          methods: {
            type: [String],
            default: [],
          },
          notes: {
            type: String,
            trim: true,
            default: "",
          },
        },
        default: {},
      },
      // WHY: Harvest window detail should remain available even when lifecycle days are approximate.
      harvestWindow: {
        type: {
          earliestDays: {
            type: Number,
            default: null,
          },
          latestDays: {
            type: Number,
            default: null,
          },
          seasons: {
            type: [String],
            default: [],
          },
          notes: {
            type: String,
            trim: true,
            default: "",
          },
        },
        default: {},
      },
      // WHY: Source provenance must remain explicit when multiple official datasets contribute one crop profile.
      sourceProvenance: {
        type: [
          new mongoose.Schema(
            {
              sourceKey: {
                type: String,
                trim: true,
                default: "",
              },
              sourceLabel: {
                type: String,
                trim: true,
                default: "",
              },
              authority: {
                type: String,
                trim: true,
                default: "",
              },
              sourceUrl: {
                type: String,
                trim: true,
                default: "",
              },
              citation: {
                type: String,
                trim: true,
                default: "",
              },
              license: {
                type: String,
                trim: true,
                default: "",
              },
              externalId: {
                type: String,
                trim: true,
                default: "",
              },
              confidence: {
                type: Number,
                min: 0,
                max: 1,
                default: null,
              },
              verificationStatus: {
                type: String,
                enum:
                  PRODUCTION_CROP_PROFILE_VERIFICATION_STATUSES,
                default: "source_pending",
              },
              fetchedAt: {
                type: Date,
                default: null,
              },
              notes: {
                type: String,
                trim: true,
                default: "",
              },
            },
            { _id: false },
          ),
        ],
        default: [],
      },
      // WHY: Resolver metadata is kept loose so stub API/AI adapters can add safe breadcrumbs.
      metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {},
      },
      // WHY: External lifecycle verification should record when the store was last refreshed.
      lastVerifiedAt: {
        type: Date,
        default: null,
      },
      // WHY: Resolver freshness matters for future lifecycle refresh policies.
      resolvedAt: {
        type: Date,
        default: Date.now,
      },
    },
    {
      timestamps: true,
      // WHY: Planner V2 cache is optional; avoid implicit index/collection creation attempts on capped Mongo plans.
      autoIndex: false,
      collection: PRODUCTION_LIFECYCLE_COLLECTION_NAME,
    },
  );

function applyCropProfileRecordTypeFilter() {
  this.where({
    recordType: PRODUCTION_LIFECYCLE_RECORD_TYPE,
  });
}

[
  "find",
  "findOne",
  "findOneAndUpdate",
  "findOneAndDelete",
  "findOneAndReplace",
  "countDocuments",
  "deleteMany",
  "updateOne",
  "updateMany",
].forEach((hook) => {
  productionLifecycleProfileSchema.pre(
    hook,
    applyCropProfileRecordTypeFilter,
  );
});

productionLifecycleProfileSchema.index(
  {
    businessId: 1,
    productKey: 1,
    cropSubtype: 1,
    domainContext: 1,
  },
  {
    unique: true,
    name: "production_lifecycle_profile_scope_lookup",
    partialFilterExpression: {
      recordType: PRODUCTION_LIFECYCLE_RECORD_TYPE,
    },
  },
);

productionLifecycleProfileSchema.index(
  {
    businessId: 1,
    domainContext: 1,
    productName: 1,
  },
  {
    name: "production_lifecycle_profile_name_lookup",
    partialFilterExpression: {
      recordType: PRODUCTION_LIFECYCLE_RECORD_TYPE,
    },
  },
);

productionLifecycleProfileSchema.index(
  {
    businessId: 1,
    domainContext: 1,
    aliases: 1,
  },
  {
    name: "production_lifecycle_profile_alias_lookup",
    partialFilterExpression: {
      recordType: PRODUCTION_LIFECYCLE_RECORD_TYPE,
    },
  },
);

productionLifecycleProfileSchema.index(
  {
    businessId: 1,
    domainContext: 1,
    profileKind: 1,
    category: 1,
    verificationStatus: 1,
    lifecycleStatus: 1,
  },
  {
    name: "production_crop_profile_discovery_lookup",
    partialFilterExpression: {
      recordType: PRODUCTION_LIFECYCLE_RECORD_TYPE,
    },
  },
);

const ProductionLifecycleProfile =
  mongoose.model(
    "ProductionLifecycleProfile",
    productionLifecycleProfileSchema,
  );

module.exports = ProductionLifecycleProfile;
module.exports.PRODUCTION_LIFECYCLE_PROFILE_SOURCES =
  PRODUCTION_LIFECYCLE_PROFILE_SOURCES;
module.exports.PRODUCTION_CROP_PROFILE_KINDS =
  PRODUCTION_CROP_PROFILE_KINDS;
module.exports.PRODUCTION_CROP_PROFILE_VERIFICATION_STATUSES =
  PRODUCTION_CROP_PROFILE_VERIFICATION_STATUSES;
module.exports.PRODUCTION_CROP_PROFILE_LIFECYCLE_STATUSES =
  PRODUCTION_CROP_PROFILE_LIFECYCLE_STATUSES;
