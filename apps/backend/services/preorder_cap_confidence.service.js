/**
 * apps/backend/services/preorder_cap_confidence.service.js
 * --------------------------------------------------------
 * WHAT:
 * - Computes read-only pre-order cap confidence from approved task progress.
 *
 * WHY:
 * - Surfaces delivery confidence to UI without changing reservation enforcement yet.
 *
 * HOW:
 * - Resolves the product's linked plan.
 * - Measures approved TaskProgress coverage for that plan.
 * - Returns base/effective cap plus confidence metrics.
 */

const debug = require("../utils/debug");
const ProductionPlan = require("../models/ProductionPlan");
const TaskProgress = require("../models/TaskProgress");

const PREORDER_CONFIDENCE_DECIMALS = 4;

function clamp01(value) {
  if (!Number.isFinite(value)) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

function normalizeCap(value) {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed <= 0
  ) {
    return 0;
  }
  return Math.floor(parsed);
}

function roundScore(value) {
  return Number(
    clamp01(value).toFixed(
      PREORDER_CONFIDENCE_DECIMALS,
    ),
  );
}

function buildDefaultConfidenceSummary(
  baseCap,
) {
  return {
    baseCap,
    effectiveCap: baseCap,
    confidenceScore: 1,
    approvedProgressCoverage: 0,
  };
}

async function resolvePlanId({
  planId,
  productId,
  businessId,
}) {
  if (planId) {
    return planId;
  }

  const latestPlan =
    await ProductionPlan.findOne({
      productId,
      businessId,
    })
      .sort({ createdAt: -1, _id: -1 })
      .select({ _id: 1 })
      .lean();

  return latestPlan?._id || null;
}

async function buildPreorderCapConfidenceSummary({
  productId = null,
  businessId = null,
  planId = null,
  baseCap = 0,
} = {}) {
  const normalizedBaseCap =
    normalizeCap(baseCap);
  const defaultSummary =
    buildDefaultConfidenceSummary(
      normalizedBaseCap,
    );

  if (!productId || !businessId) {
    return defaultSummary;
  }

  const resolvedPlanId =
    await resolvePlanId({
      planId,
      productId,
      businessId,
    });
  if (!resolvedPlanId) {
    return defaultSummary;
  }

  const [
    totalProgressCount,
    approvedProgressCount,
  ] = await Promise.all([
    TaskProgress.countDocuments({
      planId: resolvedPlanId,
    }),
    TaskProgress.countDocuments({
      planId: resolvedPlanId,
      approvedAt: { $ne: null },
    }),
  ]);

  const approvedProgressCoverage =
    totalProgressCount > 0 ?
      approvedProgressCount /
      totalProgressCount
    : 0;

  // WHY: Read-only rollout keeps no-progress plans neutral until enforcement step.
  const confidenceScore =
    totalProgressCount > 0 ?
      approvedProgressCoverage
    : 1;

  const effectiveCap = Math.max(
    0,
    Math.min(
      normalizedBaseCap,
      Math.floor(
        normalizedBaseCap *
          confidenceScore,
      ),
    ),
  );

  const summary = {
    baseCap: normalizedBaseCap,
    effectiveCap,
    confidenceScore: roundScore(
      confidenceScore,
    ),
    approvedProgressCoverage:
      roundScore(
        approvedProgressCoverage,
      ),
  };

  debug(
    "PREORDER CAP CONFIDENCE: computed",
    {
      productId: productId.toString(),
      businessId: businessId.toString(),
      planId:
        resolvedPlanId?.toString() ||
        null,
      totalProgressCount,
      approvedProgressCount,
      ...summary,
    },
  );

  return summary;
}

module.exports = {
  buildPreorderCapConfidenceSummary,
};
