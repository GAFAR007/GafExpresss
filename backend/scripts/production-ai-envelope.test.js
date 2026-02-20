/**
 * backend/scripts/production-ai-envelope.test.js
 * ----------------------------------------------
 * WHAT:
 * - Contract tests for strict AI envelope parsing in production_plan_ai.service.
 *
 * HOW:
 * - Mocks createAiChatCompletion() by temporarily replacing ai.service in require cache.
 * - Loads production_plan_ai.service fresh for each test case.
 * - Asserts success/partial outcomes for all envelope actions and strict schema failures.
 *
 * WHY:
 * - Prevents regressions that would trigger 422 due to malformed AI responses.
 * - Ensures the service safely handles non-plan actions (suggestions/clarify/draft_product)
 *   while still producing a safe partial draft for the UI to recover.
 */

const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const debug = require("../utils/debug");

const TEST_LOG_TAG =
  "PRODUCTION_AI_ENVELOPE_TEST";
const aiServiceModulePath =
  require.resolve(
    "../services/ai.service",
  );
const productionServiceModulePath =
  require.resolve(
    "../services/production_plan_ai.service",
  );

const TEST_START_DATE =
  "2026-03-01";
const TEST_END_DATE =
  "2026-04-30";
const TEST_PRODUCT_ID =
  "65f000000000000000000002";
const TEST_ESTATE_ID =
  "65f000000000000000000001";

const BASE_CALL_INPUT = {
  productName:
    "Bean Bags",
  estateName:
    "Gafars Estate",
  startDate: TEST_START_DATE,
  endDate: TEST_END_DATE,
  domainContext: "farm",
  estateAssetId: TEST_ESTATE_ID,
  productId: TEST_PRODUCT_ID,
  staffProfiles: [],
  assistantPrompt:
    "Plan beans production for multiple weeks.",
  useReasoning: false,
  context: {
    requestId: "ai-envelope-test",
    route:
      "/business/production/plans/ai-draft",
    userRole:
      "business_owner",
    businessId:
      "65f0000000000000000000aa",
  },
};

function cloneBaseCallInput() {
  return JSON.parse(
    JSON.stringify(BASE_CALL_INPUT),
  );
}

async function invokeWithMockedAiResponse({
  content,
  overrides = {},
}) {
  const previousAiCache =
    require.cache[
      aiServiceModulePath
    ];
  const previousProductionCache =
    require.cache[
      productionServiceModulePath
    ];

  // WHY: Override AI provider once per test to keep assertions deterministic.
  require.cache[
    aiServiceModulePath
  ] = {
    id: aiServiceModulePath,
    filename:
      aiServiceModulePath,
    loaded: true,
    exports: {
      createAiChatCompletion:
        async () => ({
          model:
            "mock-envelope-model",
          content,
        }),
    },
  };
  delete require.cache[
    productionServiceModulePath
  ];

  try {
    const {
      generateProductionPlanDraft,
    } = require(
      "../services/production_plan_ai.service"
    );
    const result =
      await generateProductionPlanDraft({
        ...cloneBaseCallInput(),
        ...overrides,
      });
    return result;
  } finally {
    // WHY: Restore module cache so this test file never leaks global side effects.
    delete require.cache[
      productionServiceModulePath
    ];
    if (previousProductionCache) {
      require.cache[
        productionServiceModulePath
      ] = previousProductionCache;
    }
    if (previousAiCache) {
      require.cache[
        aiServiceModulePath
      ] = previousAiCache;
    } else {
      delete require.cache[
        aiServiceModulePath
      ];
    }
  }
}

function buildPlanDraftEnvelope({
  days = 61,
  weeks = 9,
  extraPayload = {},
}) {
  return {
    action: "plan_draft",
    message:
      "Draft plan generated successfully",
    payload: {
      productId: TEST_PRODUCT_ID,
      productName:
        "Bean Bags",
      startDate:
        TEST_START_DATE,
      endDate: TEST_END_DATE,
      days,
      weeks,
      phases: [
        {
          name: "Land preparation",
          order: 1,
          estimatedDays: 12,
          tasks: [
            {
              title:
                "Clear plot and prepare seed beds",
              roleRequired:
                "farmer",
              requiredHeadcount: 3,
              weight: 2,
              instructions:
                "Clear weeds and align seed beds for the first cycle.",
              startDate:
                "2026-03-01T09:00:00Z",
              dueDate:
                "2026-03-03T16:00:00Z",
              assignedStaffProfileIds:
                [],
            },
          ],
        },
        {
          name: "Planting and care",
          order: 2,
          estimatedDays: 49,
          tasks: [
            {
              title:
                "Sow seeds and monitor moisture",
              roleRequired:
                "farmer",
              requiredHeadcount: 2,
              weight: 3,
              instructions:
                "Plant beans in rows and monitor soil moisture daily.",
              startDate:
                "2026-03-04T09:00:00Z",
              dueDate:
                "2026-04-30T16:00:00Z",
              assignedStaffProfileIds:
                [],
            },
          ],
        },
      ],
      warnings: [],
      ...extraPayload,
    },
  };
}

test(
  "plan_draft envelope returns ai_draft_success",
  async () => {
    debug(
      TEST_LOG_TAG,
      "Running plan_draft success case",
    );
    const content = JSON.stringify(
      buildPlanDraftEnvelope({}),
    );
    const result =
      await invokeWithMockedAiResponse({
        content,
      });

    assert.equal(
      result.status,
      "ai_draft_success",
    );
    assert.equal(
      result.draft.startDate,
      TEST_START_DATE,
    );
    assert.equal(
      result.draft.endDate,
      TEST_END_DATE,
    );
    assert.equal(
      result.draft.productId,
      TEST_PRODUCT_ID,
    );
    assert.equal(
      result.draft.summary.totalTasks,
      2,
    );
    assert.equal(
      result.draft.phases.length,
      2,
    );
  },
);

test(
  "suggestions envelope returns ai_draft_partial with safe fallback",
  async () => {
    debug(
      TEST_LOG_TAG,
      "Running suggestions partial case",
    );
    const content = JSON.stringify({
      action: "suggestions",
      message:
        "Here are starter suggestions for your estate.",
      payload: {
        suggestions: [
          "Plan beans for 10-12 weeks with staggered weeding.",
          "Add irrigation checks every 2 days.",
          "Reserve harvest logistics early.",
        ],
      },
    });
    const result =
      await invokeWithMockedAiResponse({
        content,
      });

    assert.equal(
      result.status,
      "ai_draft_partial",
    );
    assert.equal(
      result.issueType,
      "INSUFFICIENT_CONTEXT",
    );
    assert.equal(
      Array.isArray(
        result.draft.phases,
      ),
      true,
    );
    assert.ok(
      result.warnings.some(
        (warning) =>
          warning.code ===
          "ENVELOPE_ACTION",
      ),
    );
  },
);

test(
  "clarify envelope with requiredField=startDate maps to DATE_NOT_INFERRED",
  async () => {
    debug(
      TEST_LOG_TAG,
      "Running clarify partial case",
    );
    const content = JSON.stringify({
      action: "clarify",
      message:
        "Need your preferred start date.",
      payload: {
        question:
          "What start date should we use?",
        choices: [
          "Next Monday",
          "First day of next month",
          "I will type a date",
        ],
        requiredField:
          "startDate",
        contextSummary:
          "Product selected but start date missing.",
      },
    });
    const result =
      await invokeWithMockedAiResponse({
        content,
      });

    assert.equal(
      result.status,
      "ai_draft_partial",
    );
    assert.equal(
      result.issueType,
      "DATE_NOT_INFERRED",
    );
    assert.ok(
      result.message
        .toLowerCase()
        .includes("start"),
    );
  },
);

test(
  "draft_product envelope maps to PRODUCT_NOT_INFERRED and proposedProduct fallback",
  async () => {
    debug(
      TEST_LOG_TAG,
      "Running draft_product partial case",
    );
    const content = JSON.stringify({
      action: "draft_product",
      message:
        "I prepared a draft product for your confirmation.",
      payload: {
        draftProduct: {
          name: "Cowpea Beans",
          category: "legumes",
          unit: "bags",
          notes:
            "Fast-maturing bean variety for dry season.",
          lifecycleDaysEstimate: 90,
        },
        createProductPayload: {
          name: "Cowpea Beans",
          category: "legumes",
          unit: "bags",
          notes:
            "Fast-maturing bean variety for dry season.",
        },
        confirmationQuestion:
          "Create Cowpea Beans product and continue planning?",
      },
    });
    const result =
      await invokeWithMockedAiResponse({
        content,
        overrides: {
          productId: null,
          productName: "",
        },
      });

    assert.equal(
      result.status,
      "ai_draft_partial",
    );
    assert.equal(
      result.issueType,
      "PRODUCT_NOT_INFERRED",
    );
    assert.equal(
      result.draft.productId,
      null,
    );
    assert.equal(
      result.draft
        .proposedProduct.name,
      "Cowpea Beans",
    );
  },
);

test(
  "plan_draft envelope with extra keys triggers safe partial fallback",
  async () => {
    debug(
      TEST_LOG_TAG,
      "Running strict key rejection case",
    );
    const invalidEnvelope =
      buildPlanDraftEnvelope({
        extraPayload: {
          monthApprox: 2,
        },
      });
    const content = JSON.stringify(
      invalidEnvelope,
    );
    const result =
      await invokeWithMockedAiResponse({
        content,
      });

    assert.equal(
      result.status,
      "ai_draft_partial",
    );
    assert.equal(
      result.issueType,
      "HARD_SCHEMA_FAILURE",
    );
    assert.ok(
      result.warnings.some(
        (warning) =>
          warning.code ===
          "HARD_SCHEMA_FAILURE",
      ),
    );
  },
);

test(
  "plan_draft envelope with incorrect days/weeks triggers strict fallback",
  async () => {
    debug(
      TEST_LOG_TAG,
      "Running planning range mismatch case",
    );
    const content = JSON.stringify(
      buildPlanDraftEnvelope({
        days: 10,
        weeks: 1,
      }),
    );
    const result =
      await invokeWithMockedAiResponse({
        content,
      });

    assert.equal(
      result.status,
      "ai_draft_partial",
    );
    assert.equal(
      result.issueType,
      "HARD_SCHEMA_FAILURE",
    );
    assert.ok(
      result.warnings.some(
        (warning) =>
          warning.code ===
          "HARD_SCHEMA_FAILURE",
      ),
    );
  },
);

