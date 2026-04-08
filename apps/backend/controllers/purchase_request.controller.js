/**
 * apps/backend/controllers/purchase_request.controller.js
 * -------------------------------------------------------
 * WHAT:
 * - HTTP controller for temporary purchase-request actions.
 *
 * WHY:
 * - Keeps request validation and response shaping out of routes.
 * - Emits chat socket events after structured request messages are created.
 *
 * HOW:
 * - Delegates business logic to purchase_request.service.
 * - Reuses chat socket broadcasting for invoice/proof events.
 */

const debug = require("../utils/debug");
const purchaseRequestService = require("../services/purchase_request.service");
const { emitMessageCreated } = require("../services/chat_socket.service");

function buildContext(req, operation, intent) {
  return {
    route: req.originalUrl,
    requestId: req.id,
    userRole: req.user?.role,
    operation,
    intent,
  };
}

function emitRequestMessage(result) {
  const messages = [];
  if (result?.message) {
    messages.push(result.message);
  }
  if (Array.isArray(result?.followUpMessages)) {
    messages.push(...result.followUpMessages.filter(Boolean));
  }

  messages.forEach((message) => {
    emitMessageCreated({
      conversationId: message.conversationId?.toString(),
      message,
    });
  });
}

async function createPurchaseRequest(req, res) {
  const context = buildContext(
    req,
    "CreatePurchaseRequest",
    "start buyer purchase request",
  );

  try {
    const result = await purchaseRequestService.createPurchaseRequest({
      customerId: req.user?.sub,
      items: req.body?.items,
      deliveryAddress: req.body?.deliveryAddress,
      reservationId: req.body?.reservationId,
      context,
    });

    emitRequestMessage(result);

    return res.status(201).json({
      message: "Purchase request created successfully",
      purchaseRequest: result.purchaseRequest,
      conversation: result.conversation,
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: createPurchaseRequest - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to create purchase request",
    });
  }
}

async function createBatchPurchaseRequests(req, res) {
  const context = buildContext(
    req,
    "CreateBatchPurchaseRequests",
    "start grouped buyer purchase requests",
  );

  try {
    const results = await purchaseRequestService.createBatchPurchaseRequests({
      customerId: req.user?.sub,
      items: req.body?.items,
      deliveryAddress: req.body?.deliveryAddress,
      context,
    });

    results.forEach(emitRequestMessage);

    return res.status(201).json({
      message: "Purchase requests created successfully",
      purchaseRequests: results.map((entry) => entry.purchaseRequest),
      conversations: results.map((entry) => entry.conversation),
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: createBatchPurchaseRequests - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to create purchase requests",
    });
  }
}

async function sendInvoice(req, res) {
  const context = buildContext(
    req,
    "SendPurchaseRequestInvoice",
    "send manual invoice",
  );

  try {
    const result = await purchaseRequestService.sendInvoice({
      requestId: req.params?.id,
      actorUserId: req.user?.sub,
      baseLogisticsFee: req.body?.baseLogisticsFee,
      sellerMarkupPercent:
        req.body?.sellerMarkupPercent,
      estimatedDeliveryDate:
        req.body?.estimatedDeliveryDate,
      paymentInstructions: req.body?.paymentInstructions,
      paymentAccount: req.body?.paymentAccount,
      savePaymentAccount:
        req.body?.savePaymentAccount === true,
      note: req.body?.note,
      context,
    });

    emitRequestMessage(result);

    return res.status(200).json({
      message: "Invoice sent successfully",
      purchaseRequest: result.purchaseRequest,
    });
  } catch (error) {
    debug("PURCHASE_REQUEST_CONTROLLER: sendInvoice - error", error?.message);
    return res.status(400).json({
      error: error?.message || "Unable to send invoice",
    });
  }
}

async function attendPurchaseRequestChat(req, res) {
  const context = buildContext(
    req,
    "AttendPurchaseRequestChat",
    "business actor takes over request chat",
  );

  try {
    const result = await purchaseRequestService.attendPurchaseRequestChat({
      requestId: req.params?.id,
      actorUserId: req.user?.sub,
      context,
    });

    emitRequestMessage(result);

    return res.status(200).json({
      message: "Seller is now attending the request chat",
      purchaseRequest: result.purchaseRequest,
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: attendPurchaseRequestChat - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to attend request chat",
    });
  }
}

async function exitPurchaseRequestChat(req, res) {
  const context = buildContext(
    req,
    "ExitPurchaseRequestChat",
    "return request chat to customer care",
  );

  try {
    const result = await purchaseRequestService.exitPurchaseRequestChat({
      requestId: req.params?.id,
      actorUserId: req.user?.sub,
      context,
    });

    emitRequestMessage(result);

    return res.status(200).json({
      message: "Customer care resumed the request chat",
      purchaseRequest: result.purchaseRequest,
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: exitPurchaseRequestChat - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to return request chat to customer care",
    });
  }
}

async function updatePurchaseRequestAiControl(req, res) {
  const context = buildContext(
    req,
    "UpdatePurchaseRequestAiControl",
    "toggle whether the request assistant is covering chat",
  );

  try {
    const result = await purchaseRequestService.updatePurchaseRequestAiControl({
      requestId: req.params?.id,
      actorUserId: req.user?.sub,
      enabled: req.body?.enabled,
      context,
    });

    emitRequestMessage(result);

    return res.status(200).json({
      message:
        req.body?.enabled === true
          ? "Assistant cover enabled for the request chat"
          : "Assistant cover disabled for the request chat",
      purchaseRequest: result.purchaseRequest,
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: updatePurchaseRequestAiControl - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to update request assistant cover",
    });
  }
}

async function submitPaymentProof(req, res) {
  const context = buildContext(
    req,
    "SubmitPurchaseRequestProof",
    "submit payment proof",
  );

  try {
    const result = await purchaseRequestService.submitPaymentProof({
      requestId: req.params?.id,
      customerId: req.user?.sub,
      attachmentId: req.body?.attachmentId,
      note: req.body?.note,
      context,
    });

    emitRequestMessage(result);

    return res.status(200).json({
      message: "Payment proof submitted successfully",
      purchaseRequest: result.purchaseRequest,
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: submitPaymentProof - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to submit payment proof",
    });
  }
}

async function reviewPaymentProof(req, res) {
  const context = buildContext(
    req,
    "ReviewPurchaseRequestProof",
    "review buyer payment proof",
  );

  try {
    const result = await purchaseRequestService.reviewPaymentProof({
      requestId: req.params?.id,
      actorUserId: req.user?.sub,
      decision: req.body?.decision,
      reviewNote: req.body?.reviewNote,
      approvalPassword: req.body?.approvalPassword,
      context,
    });

    emitRequestMessage(result);

    return res.status(200).json({
      message: "Payment proof reviewed successfully",
      purchaseRequest: result.purchaseRequest,
      order: result.order || null,
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: reviewPaymentProof - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to review payment proof",
    });
  }
}

async function cancelPurchaseRequest(req, res) {
  const context = buildContext(
    req,
    "CancelPurchaseRequest",
    "cancel buyer purchase request",
  );

  try {
    const result = await purchaseRequestService.cancelPurchaseRequest({
      requestId: req.params?.id,
      actorUserId: req.user?.sub,
      reason: req.body?.reason,
      context,
    });

    emitRequestMessage(result);

    return res.status(200).json({
      message: "Purchase request cancelled successfully",
      purchaseRequest: result.purchaseRequest,
    });
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_CONTROLLER: cancelPurchaseRequest - error",
      error?.message,
    );
    return res.status(400).json({
      error: error?.message || "Unable to cancel purchase request",
    });
  }
}

module.exports = {
  createPurchaseRequest,
  createBatchPurchaseRequests,
  attendPurchaseRequestChat,
  exitPurchaseRequestChat,
  updatePurchaseRequestAiControl,
  sendInvoice,
  submitPaymentProof,
  reviewPaymentProof,
  cancelPurchaseRequest,
};
