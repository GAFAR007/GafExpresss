/// lib/app/features/home/presentation/chat_thread_screen.dart
/// ----------------------------------------------------------
/// WHAT:
/// - Chat thread screen for a single conversation.
///
/// WHY:
/// - Provides a focused view to read and send messages.
/// - Supports attachments with optimistic UI updates.
///
/// HOW:
/// - Uses ChatThreadController for state + socket updates.
/// - Renders message list + composer with attachment chips.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/core/platform/platform_info.dart';
import 'package:frontend/app/features/home/presentation/business_order_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_attachment_picker.dart';
import 'package:frontend/app/features/home/presentation/chat_call_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_routes.dart';
import 'package:frontend/app/features/home/presentation/chat_widgets.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_models.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_providers.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_quote_screen.dart';
import 'package:frontend/app/features/home/presentation/role_access.dart';
import 'package:frontend/app/theme/app_colors.dart';

const String _logTag = "CHAT_THREAD";
const String _logBuild = "build()";
const String _logSendTap = "send_tap";
const String _logAttachTap = "attach_tap";
const String _logAttachPick = "attach_pick";
const String _logBackTap = "back_tap";
const String _logProfileTap = "profile_tap";
const String _logCallTap = "call_tap";
const String _logAiToggleTap = "ai_toggle_tap";
const String _logAttendTap = "attend_tap";
const String _logOverflowTap = "overflow_tap";
const String _logRetryTap = "retry_tap";

const String _fallbackTitle = "Chat";
const String _fallbackRole = "unknown";
const String _fallbackBusiness = "Not assigned";
const String _fallbackEstate = "Not assigned";
const String _groupRoleLabel = "Group";
const String _multipleLabel = "Multiple";
const String _metaSeparator = " • ";
const String _conversationTypeGroup = "group";
const String _tooltipAiToggle = "Toggle AI assistant";
const String _tooltipAttend = "Attend this chat";
const String _tooltipMore = "More actions";
const String _tooltipInfo = "Open profile";
const String _tooltipCall = "Start voice call";
const Color _threadHeroTop = Color(0xFF082A55);
const Color _threadCanvas = Color(0xFFF8FAFC);

const double _headerMetaSpacing = 2;
const double _appBarInfoHeight = 60;
const EdgeInsets _appBarInfoPadding = EdgeInsets.fromLTRB(16, 0, 16, 8);

class ChatThreadArgs {
  final ChatConversation? conversation;

  const ChatThreadArgs({this.conversation});
}

enum _ComposerAttachmentAction { photos, camera, files }

enum _ThreadOverflowAction { viewProfile, hideRequest, showRequest, returnToAi }

class ChatThreadScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final ChatThreadArgs? args;

  const ChatThreadScreen({super.key, required this.conversationId, this.args});

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final TextEditingController _messageCtrl = TextEditingController();
  bool _isSubmittingRequestAction = false;
  String _hiddenRequestId = "";
  bool _hasDraftText = false;
  bool _isUploadingAttachments = false;
  late final AudioRecorder _voiceRecorder;
  final Stopwatch _voiceRecordingStopwatch = Stopwatch();
  Timer? _voiceRecordingTicker;
  bool _isVoiceRecording = false;
  bool _isProcessingVoiceNote = false;
  Duration _voiceRecordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _voiceRecorder = AudioRecorder();
    _messageCtrl.addListener(_handleComposerChanged);
  }

  void _handleComposerChanged() {
    final hasDraftText = _messageCtrl.text.trim().isNotEmpty;
    if (hasDraftText == _hasDraftText || !mounted) {
      return;
    }
    setState(() => _hasDraftText = hasDraftText);
  }

  void _log(String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(_logTag, message, extra: extra);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _hideRequestSummary(String requestId) {
    if (!mounted) return;
    setState(() => _hiddenRequestId = requestId);
  }

  void _showRequestSummary() {
    if (!mounted) return;
    setState(() => _hiddenRequestId = "");
  }

  bool _isBusinessRole(String role) {
    return role == "business_owner" || role == "staff";
  }

  Future<void> _refreshPurchaseRequestState() async {
    ref.invalidate(chatConversationDetailProvider(widget.conversationId));
    ref.invalidate(chatInboxProvider);
    ref.invalidate(myOrdersProvider);
    ref.invalidate(businessOrdersProvider);
  }

  Future<void> _openQuotationScreen(PurchaseRequest request) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PurchaseRequestQuoteScreen(
          conversationId: widget.conversationId,
          request: request,
        ),
      ),
    );
    if (changed == true) {
      await _refreshPurchaseRequestState();
      if (!mounted) return;
      _showMessage(
        request.invoice.isSent ? "Quotation updated" : "Quotation created",
      );
    }
  }

  Future<String?> _openTextPrompt({
    required String title,
    required String label,
    String initialValue = "",
    String submitLabel = "Save",
  }) async {
    final controller = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(submitLabel),
            ),
          ],
        );
      },
    );
  }

  Future<_ProofApprovalDraft?> _openProofApprovalDialog() async {
    final noteController = TextEditingController();
    final passwordController = TextEditingController();

    return showDialog<_ProofApprovalDraft>(
      context: context,
      builder: (context) {
        String? errorText;
        bool obscurePassword = true;

        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text("Approve payment proof"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Audit note (optional)",
                        hintText: "Add an internal note for this approval",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password confirmation",
                        hintText: "Enter your account password",
                        suffixIcon: IconButton(
                          onPressed: () => setLocalState(
                            () => obscurePassword = !obscurePassword,
                          ),
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () {
                    final approvalPassword = passwordController.text;
                    if (approvalPassword.trim().isEmpty) {
                      setLocalState(
                        () => errorText = "Password is required for approval",
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                      _ProofApprovalDraft(
                        reviewNote: noteController.text.trim(),
                        approvalPassword: approvalPassword,
                      ),
                    );
                  },
                  child: const Text("Approve"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_DispatchDraft?> _openDispatchDialog(PurchaseRequest request) async {
    final carrierCtrl = TextEditingController(
      text: request.fulfillment?.carrierName ?? "",
    );
    final trackingCtrl = TextEditingController(
      text: request.fulfillment?.trackingReference ?? "",
    );
    final noteCtrl = TextEditingController(
      text: request.fulfillment?.dispatchNote ?? "",
    );

    return showDialog<_DispatchDraft>(
      context: context,
      builder: (context) {
        String? errorText;
        DateTime? selectedDate =
            request.fulfillment?.estimatedDeliveryDate ??
            request.activeEstimatedDeliveryDate;

        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text("Add dispatch info"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: carrierCtrl,
                      decoration: const InputDecoration(
                        labelText: "Carrier name",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: trackingCtrl,
                      decoration: const InputDecoration(
                        labelText: "Tracking reference",
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? now,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(kDatePickerLastYear),
                        );
                        if (picked != null) {
                          setLocalState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Estimated delivery date",
                        ),
                        child: Text(
                          formatDateLabel(
                            selectedDate,
                            fallback: "Select a delivery date",
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Dispatch note",
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () {
                    if (carrierCtrl.text.trim().isEmpty) {
                      setLocalState(
                        () => errorText = "Carrier name is required",
                      );
                      return;
                    }
                    if (trackingCtrl.text.trim().isEmpty) {
                      setLocalState(
                        () => errorText = "Tracking reference is required",
                      );
                      return;
                    }
                    if (selectedDate == null) {
                      setLocalState(
                        () => errorText = "Estimated delivery date is required",
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                      _DispatchDraft(
                        carrierName: carrierCtrl.text.trim(),
                        trackingReference: trackingCtrl.text.trim(),
                        dispatchNote: noteCtrl.text.trim(),
                        estimatedDeliveryDate: selectedDate!,
                      ),
                    );
                  },
                  child: const Text("Mark shipped"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleShipOrder(PurchaseRequest request) async {
    final session = ref.read(authSessionProvider);
    if (session == null ||
        !session.isTokenValid ||
        _isSubmittingRequestAction ||
        request.linkedOrderId.trim().isEmpty) {
      return;
    }

    final draft = await _openDispatchDialog(request);
    if (draft == null) return;

    setState(() => _isSubmittingRequestAction = true);
    try {
      final api = ref.read(businessOrderApiProvider);
      await api.updateOrderStatus(
        token: session.token,
        orderId: request.linkedOrderId,
        status: "shipped",
        carrierName: draft.carrierName,
        trackingReference: draft.trackingReference,
        dispatchNote: draft.dispatchNote,
        estimatedDeliveryDate: draft.estimatedDeliveryDate,
      );
      await _refreshPurchaseRequestState();
      _showMessage("Order marked as shipped");
    } catch (error) {
      _showMessage("Unable to ship order: $error");
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequestAction = false);
      }
    }
  }

  Future<void> _handleMarkDelivered(PurchaseRequest request) async {
    final session = ref.read(authSessionProvider);
    if (session == null ||
        !session.isTokenValid ||
        _isSubmittingRequestAction ||
        request.linkedOrderId.trim().isEmpty) {
      return;
    }

    setState(() => _isSubmittingRequestAction = true);
    try {
      final api = ref.read(businessOrderApiProvider);
      await api.updateOrderStatus(
        token: session.token,
        orderId: request.linkedOrderId,
        status: "delivered",
      );
      await _refreshPurchaseRequestState();
      _showMessage("Order marked as delivered");
    } catch (error) {
      _showMessage("Unable to update delivery: $error");
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequestAction = false);
      }
    }
  }

  Future<void> _handleUploadProof(PurchaseRequest request) async {
    final session = ref.read(authSessionProvider);
    if (session == null ||
        !session.isTokenValid ||
        _isSubmittingRequestAction) {
      return;
    }

    final picked = await pickChatDocument();
    if (picked == null) return;

    setState(() => _isSubmittingRequestAction = true);
    try {
      final chatApi = ref.read(chatApiProvider);
      final attachment = await chatApi.uploadAttachment(
        token: session.token,
        conversationId: widget.conversationId,
        bytes: picked.bytes,
        filename: picked.filename,
        mimeType: picked.mimeType,
      );
      final api = ref.read(purchaseRequestApiProvider);
      await api.submitPaymentProof(
        token: session.token,
        requestId: request.id,
        attachmentId: attachment.id,
      );
      await _refreshPurchaseRequestState();
      _showMessage("Payment proof uploaded");
    } catch (error) {
      _showMessage("Upload failed: $error");
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequestAction = false);
      }
    }
  }

  Future<void> _handleUpdateAiControl(
    PurchaseRequest request,
    bool enabled,
  ) async {
    final session = ref.read(authSessionProvider);
    if (session == null ||
        !session.isTokenValid ||
        _isSubmittingRequestAction) {
      return;
    }

    setState(() => _isSubmittingRequestAction = true);
    try {
      final api = ref.read(purchaseRequestApiProvider);
      await api.updateAiControl(
        token: session.token,
        requestId: request.id,
        enabled: enabled,
      );
      await _refreshPurchaseRequestState();
      _showMessage(
        enabled
            ? "${request.assistantName} is covering this request again"
            : "You are now attending this request",
      );
    } catch (error) {
      _showMessage(
        enabled
            ? "Unable to enable assistant cover: $error"
            : "Unable to take over chat: $error",
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequestAction = false);
      }
    }
  }

  Future<void> _handleAttendChat(PurchaseRequest request) async {
    final session = ref.read(authSessionProvider);
    if (session == null ||
        !session.isTokenValid ||
        _isSubmittingRequestAction) {
      return;
    }

    setState(() => _isSubmittingRequestAction = true);
    try {
      final api = ref.read(purchaseRequestApiProvider);
      await api.attendChat(token: session.token, requestId: request.id);
      await _refreshPurchaseRequestState();
      _showMessage("You are now attending this request");
    } catch (error) {
      _showMessage("Unable to attend chat: $error");
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequestAction = false);
      }
    }
  }

  Future<void> _handleReviewProof({
    required PurchaseRequest request,
    required String decision,
  }) async {
    final session = ref.read(authSessionProvider);
    if (session == null ||
        !session.isTokenValid ||
        _isSubmittingRequestAction) {
      return;
    }

    String reviewNote = "";
    String approvalPassword = "";
    if (decision == "rejected") {
      final note = await _openTextPrompt(
        title: "Reject payment proof",
        label: "Reason",
        submitLabel: "Reject",
      );
      if (note == null) return;
      reviewNote = note;
    } else {
      final draft = await _openProofApprovalDialog();
      if (draft == null) return;
      reviewNote = draft.reviewNote;
      approvalPassword = draft.approvalPassword;
    }

    setState(() => _isSubmittingRequestAction = true);
    try {
      final api = ref.read(purchaseRequestApiProvider);
      await api.reviewPaymentProof(
        token: session.token,
        requestId: request.id,
        decision: decision,
        reviewNote: reviewNote,
        approvalPassword: approvalPassword,
      );
      await _refreshPurchaseRequestState();
      _showMessage(
        decision == "approved" ? "Proof approved" : "Proof rejected",
      );
    } catch (error) {
      _showMessage("Review failed: $error");
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequestAction = false);
      }
    }
  }

  Future<void> _handleCancelRequest(PurchaseRequest request) async {
    final session = ref.read(authSessionProvider);
    if (session == null ||
        !session.isTokenValid ||
        _isSubmittingRequestAction) {
      return;
    }

    final reason = await _openTextPrompt(
      title: "Cancel request",
      label: "Reason (optional)",
      submitLabel: "Cancel request",
    );
    if (reason == null) return;

    setState(() => _isSubmittingRequestAction = true);
    try {
      final api = ref.read(purchaseRequestApiProvider);
      await api.cancelPurchaseRequest(
        token: session.token,
        requestId: request.id,
        reason: reason,
      );
      await _refreshPurchaseRequestState();
      _showMessage("Request cancelled");
    } catch (error) {
      _showMessage("Cancel failed: $error");
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequestAction = false);
      }
    }
  }

  String _resolveTitle({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
    required String currentUserId,
  }) {
    // WHY: Prefer explicit titles, then fall back to the other participant.
    final title = conversation?.title.trim() ?? "";
    if (title.isNotEmpty) return title;

    if (participants.isEmpty) return _fallbackTitle;
    final other = participants.firstWhere(
      (participant) => participant.userId != currentUserId,
      orElse: () => participants.first,
    );
    return other.name.trim().isNotEmpty
        ? other.name
        : other.email.trim().isNotEmpty
        ? other.email
        : _fallbackTitle;
  }

  bool _isCurrentParticipant(
    ChatParticipantSummary participant, {
    required String currentUserId,
    required String currentUserEmail,
  }) {
    final normalizedUserId = currentUserId.trim();
    if (normalizedUserId.isNotEmpty &&
        participant.userId.trim() == normalizedUserId) {
      return true;
    }

    final normalizedEmail = currentUserEmail.trim().toLowerCase();
    return normalizedEmail.isNotEmpty &&
        participant.email.trim().toLowerCase() == normalizedEmail;
  }

  bool _requestMatchesCurrentBusiness({
    required PurchaseRequest request,
    required ChatConversation? conversation,
    required String currentUserRole,
    required String currentUserId,
    required String currentUserBusinessId,
  }) {
    if (!_isBusinessRole(currentUserRole)) {
      return false;
    }

    final requestBusinessId = request.businessId.trim();
    if (requestBusinessId.isEmpty) {
      return false;
    }

    final candidateIds = <String>{
      currentUserId.trim(),
      currentUserBusinessId.trim(),
      conversation?.businessId.trim() ?? "",
    }..removeWhere((value) => value.isEmpty);

    for (final candidate in candidateIds) {
      if (candidate == requestBusinessId) {
        return true;
      }
    }

    return false;
  }

  List<ChatParticipantSummary> _resolveParticipants({
    required ChatConversationDetail? detail,
    required PurchaseRequest? purchaseRequest,
    required String currentUserId,
    required String currentUserEmail,
    required String currentUserRole,
    required String currentUserBusinessId,
  }) {
    // WHY: Seller-side manager views should focus on the external buyer party.
    if (detail == null) return [];
    final participants = detail.participants;
    if (purchaseRequest != null) {
      final isBuyerActor =
          isBuyerRole(currentUserRole) ||
          currentUserId.trim() == purchaseRequest.customerId.trim();
      if (isBuyerActor) {
        final sellerParticipants = participants.where((participant) {
          return participant.userId.trim() ==
                  purchaseRequest.businessId.trim() ||
              participant.businessId.trim() ==
                  purchaseRequest.businessId.trim();
        }).toList();
        if (sellerParticipants.isNotEmpty) {
          return sellerParticipants;
        }
      } else {
        final customerParticipants = participants.where((participant) {
          return participant.userId.trim() == purchaseRequest.customerId.trim();
        }).toList();
        if (customerParticipants.isNotEmpty) {
          return customerParticipants;
        }
      }
    }

    final hasCurrentUserParticipant = participants.any(
      (participant) => _isCurrentParticipant(
        participant,
        currentUserId: currentUserId,
        currentUserEmail: currentUserEmail,
      ),
    );
    if (hasCurrentUserParticipant) {
      return participants
          .where(
            (participant) => !_isCurrentParticipant(
              participant,
              currentUserId: currentUserId,
              currentUserEmail: currentUserEmail,
            ),
          )
          .toList();
    }

    final businessId = currentUserBusinessId.trim();
    if (businessId.isNotEmpty) {
      final externalParticipants = participants
          .where((participant) => participant.businessId.trim() != businessId)
          .toList();
      if (externalParticipants.isNotEmpty) {
        return externalParticipants;
      }
    }

    return participants;
  }

  ChatParticipantSummary? _resolvePrimaryParticipant(
    List<ChatParticipantSummary> participants,
  ) {
    // WHY: Use a single participant to derive direct chat metadata.
    return participants.isEmpty ? null : participants.first;
  }

  void _openProfileScreen(
    BuildContext context,
    List<ChatParticipantSummary> participants, {
    String? userId,
  }) {
    if (participants.isEmpty) {
      return;
    }

    final focusedUserId = (userId ?? "").trim().isNotEmpty
        ? userId!.trim()
        : _resolvePrimaryParticipant(participants)?.userId ?? "";
    context.push(
      buildChatProfileRoute(widget.conversationId, userId: focusedUserId),
    );
  }

  ChatParticipantSummary? _findParticipantByUserId(
    List<ChatParticipantSummary> participants,
    String userId,
  ) {
    for (final participant in participants) {
      if (participant.userId.trim() == userId.trim()) {
        return participant;
      }
    }
    return null;
  }

  Future<void> _handleOverflowAction({
    required _ThreadOverflowAction action,
    required List<ChatParticipantSummary> profileParticipants,
    required PurchaseRequest? purchaseRequest,
    required bool isRequestSummaryHidden,
  }) async {
    switch (action) {
      case _ThreadOverflowAction.viewProfile:
        _log(_logProfileTap);
        _openProfileScreen(context, profileParticipants);
        return;
      case _ThreadOverflowAction.hideRequest:
        if (purchaseRequest != null) {
          _hideRequestSummary(purchaseRequest.id);
        }
        return;
      case _ThreadOverflowAction.showRequest:
        _showRequestSummary();
        return;
      case _ThreadOverflowAction.returnToAi:
        if (purchaseRequest != null) {
          await _handleUpdateAiControl(purchaseRequest, true);
        }
        return;
    }
  }

  String _resolveRoleLabel({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
  }) {
    // WHY: Group chats should show a group label instead of a person role.
    if (conversation?.type == _conversationTypeGroup) {
      return _groupRoleLabel;
    }
    final participant = _resolvePrimaryParticipant(participants);
    final role = participant?.role.trim() ?? "";
    return role.isEmpty ? _fallbackRole : role.replaceAll("_", " ");
  }

  String _resolveGroupValue(
    List<ChatParticipantSummary> participants,
    String Function(ChatParticipantSummary participant) selector,
    String fallback,
  ) {
    // WHY: Aggregate group metadata without misleading single-user values.
    final values = participants
        .map(selector)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (values.isEmpty) return fallback;
    if (values.length == 1) return values.first;
    return _multipleLabel;
  }

  String _resolveBusinessLabel({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
  }) {
    // WHY: Prefer business display names while keeping group context safe.
    if (conversation?.type == _conversationTypeGroup) {
      return _resolveGroupValue(
        participants,
        (participant) => participant.businessName.isNotEmpty
            ? participant.businessName
            : participant.businessId,
        _fallbackBusiness,
      );
    }
    final participant = _resolvePrimaryParticipant(participants);
    if (participant == null) return _fallbackBusiness;
    if (participant.businessName.trim().isNotEmpty) {
      return participant.businessName;
    }
    return participant.businessId.trim().isNotEmpty
        ? participant.businessId
        : _fallbackBusiness;
  }

  String _resolveEstateLabel({
    required ChatConversation? conversation,
    required List<ChatParticipantSummary> participants,
  }) {
    // WHY: Avoid showing a single estate for group chats unless consistent.
    if (conversation?.type == _conversationTypeGroup) {
      return _resolveGroupValue(
        participants,
        (participant) => participant.estateName.isNotEmpty
            ? participant.estateName
            : participant.estateAssetId,
        _fallbackEstate,
      );
    }
    final participant = _resolvePrimaryParticipant(participants);
    if (participant == null) return _fallbackEstate;
    if (participant.estateName.trim().isNotEmpty) {
      return participant.estateName;
    }
    return participant.estateAssetId.trim().isNotEmpty
        ? participant.estateAssetId
        : _fallbackEstate;
  }

  String _titleCaseWords(String value) {
    return value
        .split(" ")
        .where((part) => part.trim().isNotEmpty)
        .map(
          (part) =>
              "${part[0].toUpperCase()}${part.substring(1).toLowerCase()}",
        )
        .join(" ");
  }

  String _resolveConversationStatusLabel({
    required PurchaseRequest? purchaseRequest,
  }) {
    if (purchaseRequest == null) {
      return "Active";
    }

    switch (purchaseRequest.status.trim().toLowerCase()) {
      case "requested":
        return purchaseRequest.customerCare.hasHumanAttendant
            ? "Active"
            : "Pending";
      case "quoted":
      case "rejected":
        return "Waiting for customer";
      case "proof_submitted":
        return "Pending review";
      case "approved":
        if (purchaseRequest.linkedOrderStatus.toLowerCase() == "delivered") {
          return "Resolved";
        }
        return "Active";
      case "cancelled":
        return "Resolved";
      default:
        return "Active";
    }
  }

  Color _conversationStatusAccent(String statusLabel) {
    switch (statusLabel.trim().toLowerCase()) {
      case "resolved":
        return AppColors.success;
      case "pending":
      case "pending review":
        return AppColors.commerceAccent;
      case "waiting for customer":
        return AppColors.analyticsAccent;
      default:
        return AppColors.businessAccent;
    }
  }

  @override
  void dispose() {
    _voiceRecordingTicker?.cancel();
    unawaited(_voiceRecorder.dispose());
    _messageCtrl.removeListener(_handleComposerChanged);
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _queuePickedAttachments({
    required ChatThreadController controller,
    required List<ChatPickedAttachment> picked,
    required String singularLabel,
    required String pluralLabel,
  }) async {
    if (picked.isEmpty || _isUploadingAttachments) {
      return;
    }

    setState(() => _isUploadingAttachments = true);
    var addedCount = 0;

    try {
      for (final attachment in picked) {
        _log(
          _logAttachPick,
          extra: {"name": attachment.filename, "kind": singularLabel},
        );
        final beforeCount = ref
            .read(chatThreadProvider(widget.conversationId))
            .pendingAttachments
            .length;
        await controller.addAttachment(
          bytes: attachment.bytes,
          filename: attachment.filename,
          mimeType: attachment.mimeType,
        );
        final afterCount = ref
            .read(chatThreadProvider(widget.conversationId))
            .pendingAttachments
            .length;
        if (afterCount > beforeCount) {
          addedCount += 1;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAttachments = false);
      }
    }

    if (!mounted || addedCount == 0) {
      return;
    }

    final noun = addedCount == 1 ? singularLabel : pluralLabel;
    _showMessage("$addedCount $noun ready to send");
  }

  Future<void> _handleAttachPhotos(ChatThreadController controller) async {
    _log(_logAttachTap, extra: {"kind": "photos"});
    final picked = await pickChatImages();
    await _queuePickedAttachments(
      controller: controller,
      picked: picked,
      singularLabel: "photo",
      pluralLabel: "photos",
    );
  }

  Future<void> _handleCapturePhoto(ChatThreadController controller) async {
    _log(_logAttachTap, extra: {"kind": "camera"});
    final picked = await captureChatImage();
    if (picked == null) {
      return;
    }
    await _queuePickedAttachments(
      controller: controller,
      picked: [picked],
      singularLabel: "photo",
      pluralLabel: "photos",
    );
  }

  Future<void> _handleAttachFiles(ChatThreadController controller) async {
    _log(_logAttachTap, extra: {"kind": "files"});
    final picked = await pickChatFiles();
    await _queuePickedAttachments(
      controller: controller,
      picked: picked,
      singularLabel: "file",
      pluralLabel: "files",
    );
  }

  Future<void> _openAttachmentSheet(
    ChatThreadController controller, {
    required bool supportsCamera,
  }) async {
    if (_isUploadingAttachments ||
        _isProcessingVoiceNote ||
        _isVoiceRecording) {
      return;
    }

    final selection = await showModalBottomSheet<_ComposerAttachmentAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Add to chat",
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Choose a quick action just like a chat app attachment menu.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (supportsCamera)
                      _ComposerAttachOption(
                        icon: Icons.camera_alt_rounded,
                        label: "Camera",
                        tone: const Color(0xFF0F766E),
                        onTap: () => Navigator.of(
                          sheetContext,
                        ).pop(_ComposerAttachmentAction.camera),
                      ),
                    _ComposerAttachOption(
                      icon: Icons.photo_library_rounded,
                      label: "Photos",
                      tone: const Color(0xFF1D4ED8),
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop(_ComposerAttachmentAction.photos),
                    ),
                    _ComposerAttachOption(
                      icon: Icons.folder_rounded,
                      label: "Files",
                      tone: const Color(0xFF4F46E5),
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop(_ComposerAttachmentAction.files),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selection == null) {
      return;
    }

    switch (selection) {
      case _ComposerAttachmentAction.photos:
        await _handleAttachPhotos(controller);
        return;
      case _ComposerAttachmentAction.camera:
        await _handleCapturePhoto(controller);
        return;
      case _ComposerAttachmentAction.files:
        await _handleAttachFiles(controller);
        return;
    }
  }

  Future<void> _toggleVoiceRecording(ChatThreadController controller) async {
    if (_isVoiceRecording) {
      await _stopVoiceRecording(controller);
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (_isVoiceRecording || _isProcessingVoiceNote) {
      return;
    }
    if (!(PlatformInfo.isAndroid || PlatformInfo.isIOS)) {
      _showMessage("Voice notes are available in the mobile app right now.");
      return;
    }

    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) {
      _showMessage("Microphone permission is required for voice notes.");
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final filename = "voice-note-${DateTime.now().millisecondsSinceEpoch}.wav";
    final path = "${tempDir.path}/$filename";

    await _voiceRecorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: path,
    );

    _voiceRecordingTicker?.cancel();
    _voiceRecordingStopwatch
      ..reset()
      ..start();

    if (!mounted) {
      return;
    }

    setState(() {
      _isVoiceRecording = true;
      _voiceRecordingDuration = Duration.zero;
    });

    _voiceRecordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceRecordingDuration = _voiceRecordingStopwatch.elapsed;
      });
    });
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isVoiceRecording) {
      return;
    }

    _voiceRecordingTicker?.cancel();
    _voiceRecordingStopwatch
      ..stop()
      ..reset();
    await _voiceRecorder.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _isVoiceRecording = false;
      _voiceRecordingDuration = Duration.zero;
    });
  }

  Future<void> _stopVoiceRecording(ChatThreadController controller) async {
    if (!_isVoiceRecording) {
      return;
    }

    _voiceRecordingTicker?.cancel();
    _voiceRecordingStopwatch.stop();

    if (mounted) {
      setState(() {
        _isVoiceRecording = false;
        _isProcessingVoiceNote = true;
        _voiceRecordingDuration = _voiceRecordingStopwatch.elapsed;
      });
    }

    try {
      final path = await _voiceRecorder.stop();
      if (path == null || path.trim().isEmpty) {
        throw Exception("Recording was not saved.");
      }

      final beforeCount = ref
          .read(chatThreadProvider(widget.conversationId))
          .pendingAttachments
          .length;
      final filename =
          "voice-note-${DateTime.now().millisecondsSinceEpoch}.wav";

      await controller.addAttachmentFile(
        filePath: path,
        filename: filename,
        mimeType: "audio/wav",
      );

      final afterCount = ref
          .read(chatThreadProvider(widget.conversationId))
          .pendingAttachments
          .length;
      if (afterCount <= beforeCount) {
        throw Exception("Voice note upload did not complete.");
      }

      await controller.sendMessage(body: "");
    } catch (error) {
      _showMessage("Unable to send voice note: $error");
    } finally {
      _voiceRecordingStopwatch.reset();
      if (mounted) {
        setState(() {
          _isProcessingVoiceNote = false;
          _voiceRecordingDuration = Duration.zero;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _log(_logBuild);

    // WHY: Current user id is needed to align message bubbles.
    final session = ref.watch(authSessionProvider);
    final currentUserId = session?.user.id ?? "";
    final currentUserEmail = session?.user.email ?? "";
    final currentUserBusinessId = session?.user.businessId ?? "";
    final profileAsync = ref.watch(userProfileProvider);
    final state = ref.watch(chatThreadProvider(widget.conversationId));
    final controller = ref.read(
      chatThreadProvider(widget.conversationId).notifier,
    );
    final detailAsync = ref.watch(
      chatConversationDetailProvider(widget.conversationId),
    );
    final detail = detailAsync.asData?.value;
    final purchaseRequest = detail?.purchaseRequest;
    final isRequestSummaryHidden =
        purchaseRequest != null &&
        _hiddenRequestId.trim() == purchaseRequest.id.trim();
    final currentUserRole = session?.user.role ?? "";
    final callState = ref.watch(chatCallProvider);
    final currentStaffRole = profileAsync.valueOrNull?.staffRole ?? "";
    final conversation = detail?.conversation ?? widget.args?.conversation;
    final matchesRequestBusinessScope = purchaseRequest == null
        ? false
        : _requestMatchesCurrentBusiness(
            request: purchaseRequest,
            conversation: conversation,
            currentUserRole: currentUserRole,
            currentUserId: currentUserId,
            currentUserBusinessId: currentUserBusinessId,
          );
    final isBusinessActor = purchaseRequest == null
        ? _isBusinessRole(currentUserRole)
        : _isBusinessRole(currentUserRole) && matchesRequestBusinessScope;
    final canManageSellerRequest = purchaseRequest == null
        ? canManageSellerRequests(
            role: currentUserRole,
            staffRole: currentStaffRole,
          )
        : canManageSellerRequests(
                role: currentUserRole,
                staffRole: currentStaffRole,
              ) &&
              matchesRequestBusinessScope;
    final canSendRequestInvoice = purchaseRequest == null
        ? canSendSellerRequestInvoice(
            role: currentUserRole,
            staffRole: currentStaffRole,
          )
        : canSendSellerRequestInvoice(
                role: currentUserRole,
                staffRole: currentStaffRole,
              ) &&
              matchesRequestBusinessScope;
    final canManageRequestFulfillment = purchaseRequest == null
        ? canManageSellerRequestFulfillment(
            role: currentUserRole,
            staffRole: currentStaffRole,
          )
        : canManageSellerRequestFulfillment(
                role: currentUserRole,
                staffRole: currentStaffRole,
              ) &&
              matchesRequestBusinessScope;
    final isBuyer = purchaseRequest == null
        ? currentUserRole == "customer"
        : currentUserId == purchaseRequest.customerId;

    final allParticipants =
        detail?.participants ?? const <ChatParticipantSummary>[];
    final displayParticipants = _resolveParticipants(
      detail: detail,
      purchaseRequest: purchaseRequest,
      currentUserId: currentUserId,
      currentUserEmail: currentUserEmail,
      currentUserRole: currentUserRole,
      currentUserBusinessId: currentUserBusinessId,
    );
    final currentParticipant = _findParticipantByUserId(
      allParticipants,
      currentUserId,
    );
    final supportConversation =
        purchaseRequest != null && (isBusinessActor || canManageSellerRequest);
    final supportRequest = supportConversation ? purchaseRequest : null;
    final isAiEnabled = purchaseRequest?.customerCare.aiControlEnabled ?? false;
    final currentAttendantId =
        purchaseRequest?.customerCare.currentAttendantUserId.trim() ?? "";
    final isCurrentAttendant =
        currentAttendantId.isNotEmpty && currentAttendantId == currentUserId;
    final hasHumanAttendant =
        purchaseRequest?.customerCare.hasHumanAttendant ?? false;
    final assignedStaffName = hasHumanAttendant
        ? purchaseRequest!.customerCare.currentAttendantName.trim()
        : purchaseRequest?.assistantName.trim().isNotEmpty == true
        ? purchaseRequest!.assistantName
        : "Unassigned";
    final assignedStaffLabel = hasHumanAttendant
        ? _titleCaseWords(
            purchaseRequest?.customerCare.attendantLabel.trim().isNotEmpty ==
                    true
                ? purchaseRequest!.customerCare.attendantLabel
                : "Team member",
          )
        : "AI assistant";
    final conversationStatus = _resolveConversationStatusLabel(
      purchaseRequest: purchaseRequest,
    );
    final conversationStatusAccent = _conversationStatusAccent(
      conversationStatus,
    );
    final canToggleAi =
        supportRequest != null &&
        !supportRequest.isCancelled &&
        !_isSubmittingRequestAction;
    final canAttendChat =
        supportRequest != null &&
        !supportRequest.isCancelled &&
        !isCurrentAttendant &&
        !_isSubmittingRequestAction;
    final attendLabel = isCurrentAttendant ? "In Chat" : "Attend Chat";
    final supportsCamera = PlatformInfo.isAndroid || PlatformInfo.isIOS;
    final supportsVoiceRecording = PlatformInfo.isAndroid || PlatformInfo.isIOS;
    final hasLiveCall =
        callState.call != null && !(callState.call?.isTerminal ?? true);
    final canVoiceCall =
        conversation?.type != _conversationTypeGroup &&
        displayParticipants.isNotEmpty &&
        !hasLiveCall;
    final canSendMessage =
        (_hasDraftText || state.pendingAttachments.isNotEmpty) &&
        !state.isSending &&
        !_isUploadingAttachments &&
        !_isProcessingVoiceNote &&
        !_isVoiceRecording;
    final canRecordVoice =
        supportsVoiceRecording &&
        !_hasDraftText &&
        state.pendingAttachments.isEmpty &&
        !state.isSending &&
        !_isUploadingAttachments &&
        !_isProcessingVoiceNote;
    final title = _resolveTitle(
      conversation: conversation,
      participants: displayParticipants,
      currentUserId: currentUserId,
    );
    // WHY: These labels keep the header consistent for direct + group chats.
    final roleLabel = _resolveRoleLabel(
      conversation: conversation,
      participants: displayParticipants,
    );
    final businessLabel = _resolveBusinessLabel(
      conversation: conversation,
      participants: displayParticipants,
    );
    final estateLabel = _resolveEstateLabel(
      conversation: conversation,
      participants: displayParticipants,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? colorScheme.surfaceContainerLowest
          : _threadCanvas,
      appBar: AppBar(
        backgroundColor: _threadHeroTop,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: supportConversation
            ? _SupportThreadHeaderTitle(
                title: title,
                customerStatusLabel: _titleCaseWords(roleLabel),
                assignedStaffName: assignedStaffName,
              )
            : _ThreadHeaderTitle(
                title: title,
                roleLabel: roleLabel,
                businessLabel: businessLabel,
                estateLabel: estateLabel,
              ),
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _ThreadToolbarButton(
            icon: Icons.arrow_back_rounded,
            tooltip: "Back",
            heroStyle: true,
            onPressed: () {
              _log(_logBackTap);
              if (context.canPop()) {
                context.pop();
                return;
              }
              context.go(chatInboxRoute);
            },
          ),
        ),
        actions: supportConversation
            ? [
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: _ThreadToolbarButton(
                    icon: Icons.call_rounded,
                    tooltip: _tooltipCall,
                    heroStyle: true,
                    onPressed: !canVoiceCall
                        ? null
                        : () async {
                            _log(_logCallTap);
                            final error = await ref
                                .read(chatCallProvider.notifier)
                                .startOutgoingCall(
                                  conversationId: widget.conversationId,
                                );
                            if (error != null && mounted) {
                              _showMessage(error);
                            }
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: _HeaderAiToggleButton(
                    enabled: isAiEnabled,
                    isBusy: _isSubmittingRequestAction,
                    onPressed: canToggleAi
                        ? () {
                            _log(_logAiToggleTap);
                            _handleUpdateAiControl(
                              supportRequest,
                              !isAiEnabled,
                            );
                          }
                        : null,
                  ),
                ),
                _HeaderAttendChatButton(
                  label: attendLabel,
                  enabled: canAttendChat,
                  isActive: isCurrentAttendant,
                  isBusy: _isSubmittingRequestAction,
                  onPressed: canAttendChat
                      ? () {
                          _log(_logAttendTap);
                          _handleAttendChat(supportRequest);
                        }
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ThreadOverflowMenu(
                    tooltip: _tooltipMore,
                    purchaseRequest: purchaseRequest,
                    hasProfile: displayParticipants.isNotEmpty,
                    isRequestSummaryHidden: isRequestSummaryHidden,
                    onSelected: (action) {
                      _log(_logOverflowTap, extra: {"action": action.name});
                      _handleOverflowAction(
                        action: action,
                        profileParticipants: displayParticipants,
                        purchaseRequest: purchaseRequest,
                        isRequestSummaryHidden: isRequestSummaryHidden,
                      );
                    },
                  ),
                ),
              ]
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _ThreadToolbarButton(
                    icon: Icons.call_rounded,
                    tooltip: _tooltipCall,
                    heroStyle: true,
                    onPressed: !canVoiceCall
                        ? null
                        : () async {
                            _log(_logCallTap);
                            final error = await ref
                                .read(chatCallProvider.notifier)
                                .startOutgoingCall(
                                  conversationId: widget.conversationId,
                                );
                            if (error != null && mounted) {
                              _showMessage(error);
                            }
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ThreadToolbarButton(
                    icon: Icons.person_outline_rounded,
                    tooltip: _tooltipInfo,
                    heroStyle: true,
                    onPressed: displayParticipants.isEmpty
                        ? null
                        : () {
                            _log(_logProfileTap);
                            _openProfileScreen(context, displayParticipants);
                          },
                  ),
                ),
              ],
        bottom: supportConversation
            ? PreferredSize(
                preferredSize: const Size.fromHeight(_appBarInfoHeight),
                child: _StaffSupportHeaderBar(
                  assignedStaffName: assignedStaffName,
                  assignedStaffLabel: assignedStaffLabel,
                  conversationStatus: conversationStatus,
                  conversationStatusAccent: conversationStatusAccent,
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _ThreadBackdrop()),
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _MessageList(
                          messages: state.messages,
                          participants: allParticipants,
                          currentUserId: currentUserId,
                          currentParticipant: currentParticipant,
                          onRetryMessage: (message) {
                            _log(
                              _logRetryTap,
                              extra: {"messageId": message.id},
                            );
                            controller.retryMessage(message.id);
                          },
                        ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: purchaseRequest == null
                      ? const SizedBox.shrink()
                      : isRequestSummaryHidden
                      ? Padding(
                          key: const ValueKey("request_restore"),
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _RequestRestoreButton(
                            onPressed: _showRequestSummary,
                          ),
                        )
                      : Padding(
                          key: ValueKey("request_panel_${purchaseRequest.id}"),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: _PurchaseRequestPanel(
                            request: purchaseRequest,
                            isBusinessActor: isBusinessActor,
                            canSendInvoice: canSendRequestInvoice,
                            canManageFulfillment: canManageRequestFulfillment,
                            canReviewProof: canManageSellerRequest,
                            isBuyer: isBuyer,
                            isSubmitting: _isSubmittingRequestAction,
                            onOpenQuotation: () =>
                                _openQuotationScreen(purchaseRequest),
                            onUploadProof: () =>
                                _handleUploadProof(purchaseRequest),
                            onApproveProof: () => _handleReviewProof(
                              request: purchaseRequest,
                              decision: "approved",
                            ),
                            onRejectProof: () => _handleReviewProof(
                              request: purchaseRequest,
                              decision: "rejected",
                            ),
                            onShipOrder: () =>
                                _handleShipOrder(purchaseRequest),
                            onMarkDelivered: () =>
                                _handleMarkDelivered(purchaseRequest),
                            onCancelRequest: () =>
                                _handleCancelRequest(purchaseRequest),
                            onHide: () =>
                                _hideRequestSummary(purchaseRequest.id),
                          ),
                        ),
                ),
                _Composer(
                  controller: _messageCtrl,
                  attachments: state.pendingAttachments,
                  isSending: state.isSending,
                  isUploadingAttachments: _isUploadingAttachments,
                  isVoiceRecording: _isVoiceRecording,
                  isProcessingVoiceNote: _isProcessingVoiceNote,
                  voiceRecordingDuration: _voiceRecordingDuration,
                  canSend: canSendMessage,
                  canRecordVoice: canRecordVoice,
                  onRemoveAttachment: (id) => controller.removeAttachment(id),
                  onOpenAttachmentOptions: () => _openAttachmentSheet(
                    controller,
                    supportsCamera: supportsCamera,
                  ),
                  onToggleVoiceRecording: () =>
                      _toggleVoiceRecording(controller),
                  onCancelVoiceRecording: _cancelVoiceRecording,
                  onSend: () {
                    if (!canSendMessage) {
                      return;
                    }
                    _log(_logSendTap);
                    final text = _messageCtrl.text;
                    controller.sendMessage(body: text);
                    _messageCtrl.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadBackdrop extends StatelessWidget {
  const _ThreadBackdrop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    if (!isDark) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: _threadCanvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                _threadHeroTop.withValues(alpha: 0.05),
                _threadCanvas,
              ),
              _threadCanvas,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _blendThreadTone(
              scheme.primary,
              scheme.surfaceContainerLowest,
              alpha: 0.08,
            ),
            _blendThreadTone(
              scheme.secondary,
              scheme.surfaceContainerLow,
              alpha: 0.05,
            ),
            scheme.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -92,
            right: -84,
            child: _ThreadBloom(
              size: 250,
              color: _blendThreadTone(
                scheme.primary,
                scheme.surfaceContainerHighest,
                alpha: 0.3,
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -104,
            child: _ThreadBloom(
              size: 220,
              color: _blendThreadTone(
                scheme.tertiary,
                scheme.surfaceContainer,
                alpha: 0.18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadBloom extends StatelessWidget {
  final double size;
  final Color color;

  const _ThreadBloom({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.92),
                color.withValues(alpha: 0.26),
                color.withValues(alpha: 0.02),
                Colors.transparent,
              ],
              stops: const [0, 0.42, 0.74, 1],
            ),
          ),
        ),
      ),
    );
  }
}

Color _blendThreadTone(Color accent, Color base, {double alpha = 0.08}) {
  return Color.alphaBlend(accent.withValues(alpha: alpha), base);
}

class _MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final List<ChatParticipantSummary> participants;
  final String currentUserId;
  final ChatParticipantSummary? currentParticipant;
  final ValueChanged<ChatMessage> onRetryMessage;

  const _MessageList({
    required this.messages,
    required this.participants,
    required this.currentUserId,
    required this.currentParticipant,
    required this.onRetryMessage,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final ScrollController _scrollController = ScrollController();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToBottom();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final messageCountChanged =
        oldWidget.messages.length != widget.messages.length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      if (messageCountChanged && _stickToBottom) {
        _jumpToBottom(animate: oldWidget.messages.isNotEmpty);
      }
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    _stickToBottom = (position.maxScrollExtent - position.pixels) < 72;
  }

  void _jumpToBottom({bool animate = false}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _scrollController.jumpTo(target);
  }

  bool _isAssistantMessage(ChatMessage message) {
    return (message.eventData?["presentation"] ?? "").toString() == "assistant";
  }

  bool _isSystemMessage(ChatMessage message) {
    return message.type == "system" || message.eventType.trim().isNotEmpty;
  }

  bool _canGroupMessages(ChatMessage message) {
    return !_isSystemMessage(message);
  }

  bool _belongsToSameCluster(ChatMessage left, ChatMessage right) {
    if (!_canGroupMessages(left) || !_canGroupMessages(right)) {
      return false;
    }
    if (left.senderUserId.trim() != right.senderUserId.trim()) {
      return false;
    }
    if (_isAssistantMessage(left) != _isAssistantMessage(right)) {
      return false;
    }
    final leftTime = left.createdAt;
    final rightTime = right.createdAt;
    if (leftTime == null || rightTime == null) {
      return true;
    }
    return rightTime.difference(leftTime).inMinutes.abs() <= 8;
  }

  bool _isSameCalendarDay(DateTime? left, DateTime? right) {
    if (left == null || right == null) {
      return false;
    }
    final leftLocal = left.toLocal();
    final rightLocal = right.toLocal();
    return leftLocal.year == rightLocal.year &&
        leftLocal.month == rightLocal.month &&
        leftLocal.day == rightLocal.day;
  }

  String _formatThreadDateLabel(DateTime? value) {
    if (value == null) {
      return "Earlier";
    }

    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final difference = today.difference(target).inDays;
    if (difference == 0) {
      return "Today";
    }
    if (difference == 1) {
      return "Yesterday";
    }

    const months = <String>[
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${months[local.month - 1]} ${local.day}, ${local.year}";
  }

  bool _shouldShowUnreadDivider(ChatMessage message, DateTime? lastReadAt) {
    final createdAt = message.createdAt;
    if (lastReadAt == null || createdAt == null) {
      return false;
    }
    if (message.senderUserId.trim() == widget.currentUserId.trim()) {
      return false;
    }
    return createdAt.isAfter(lastReadAt);
  }

  String _resolveSenderLabel(
    ChatMessage message,
    ChatParticipantSummary? participant,
  ) {
    final senderName = message.senderName.trim();
    if (senderName.isNotEmpty) {
      return senderName;
    }
    if (participant == null) {
      return "";
    }
    if (participant.name.trim().isNotEmpty) {
      return participant.name;
    }
    return participant.email;
  }

  String _resolveSenderRoleLabel(
    ChatMessage message,
    ChatParticipantSummary? participant,
  ) {
    final raw = message.senderRole.trim().isNotEmpty
        ? message.senderRole
        : participant?.roleAtJoin.trim().isNotEmpty == true
        ? participant!.roleAtJoin
        : participant?.role ?? "";
    return raw.replaceAll("_", " ").trim();
  }

  ChatMessageStatus? _resolveDisplayStatus(ChatMessage message) {
    if (message.senderUserId.trim() != widget.currentUserId.trim()) {
      return null;
    }
    if (message.status == ChatMessageStatus.failed ||
        message.status == ChatMessageStatus.sending) {
      return message.status;
    }
    if (message.seenAt != null) {
      return ChatMessageStatus.seen;
    }
    final createdAt = message.createdAt;
    if (createdAt != null) {
      final otherHasSeen = widget.participants.any((participant) {
        if (participant.userId.trim() == widget.currentUserId.trim()) {
          return false;
        }
        final lastReadAt = participant.lastReadAt;
        return lastReadAt != null && !createdAt.isAfter(lastReadAt);
      });
      if (otherHasSeen) {
        return ChatMessageStatus.seen;
      }
    }
    if (message.deliveredAt != null) {
      return ChatMessageStatus.delivered;
    }
    return message.status ?? ChatMessageStatus.sent;
  }

  List<_ThreadListEntry> _buildEntries(
    Map<String, ChatParticipantSummary> participantsByUserId,
  ) {
    final entries = <_ThreadListEntry>[];
    final lastReadAt = widget.currentParticipant?.lastReadAt;
    var unreadInserted = false;

    for (var index = 0; index < widget.messages.length; index++) {
      final message = widget.messages[index];
      final previous = index > 0 ? widget.messages[index - 1] : null;
      final next = index + 1 < widget.messages.length
          ? widget.messages[index + 1]
          : null;

      if (index == 0 ||
          !_isSameCalendarDay(previous?.createdAt, message.createdAt)) {
        entries.add(
          _ThreadDateEntry(_formatThreadDateLabel(message.createdAt)),
        );
      }

      if (!unreadInserted && _shouldShowUnreadDivider(message, lastReadAt)) {
        entries.add(const _ThreadUnreadEntry());
        unreadInserted = true;
      }

      final participant = participantsByUserId[message.senderUserId];
      entries.add(
        _ThreadMessageEntry(
          message: message,
          isMine: message.senderUserId.trim() == widget.currentUserId.trim(),
          senderLabel: _resolveSenderLabel(message, participant),
          senderRoleLabel: _resolveSenderRoleLabel(message, participant),
          showSenderLabel:
              previous == null || !_belongsToSameCluster(previous, message),
          mergeWithPrevious:
              previous != null && _belongsToSameCluster(previous, message),
          mergeWithNext: next != null && _belongsToSameCluster(message, next),
          status: _resolveDisplayStatus(message),
        ),
      );
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return const Center(child: Text("No messages yet"));
    }
    final participantsByUserId = <String, ChatParticipantSummary>{
      for (final participant in widget.participants)
        participant.userId: participant,
    };
    final entries = _buildEntries(participantsByUserId);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        late final Widget child;
        if (entry is _ThreadDateEntry) {
          child = _ThreadDateDivider(
            key: ValueKey("date_${entry.label}"),
            label: entry.label,
          );
        } else if (entry is _ThreadUnreadEntry) {
          child = const _ThreadUnreadDivider(key: ValueKey("unread_divider"));
        } else {
          final messageEntry = entry as _ThreadMessageEntry;
          child = ChatMessageBubble(
            key: ValueKey(
              "message_${messageEntry.message.id}_${messageEntry.status?.name ?? "none"}",
            ),
            message: messageEntry.message,
            isMine: messageEntry.isMine,
            senderLabel: messageEntry.senderLabel,
            senderRoleLabel: messageEntry.senderRoleLabel,
            showSenderLabel: messageEntry.showSenderLabel,
            mergeWithPrevious: messageEntry.mergeWithPrevious,
            mergeWithNext: messageEntry.mergeWithNext,
            status: messageEntry.status,
            onRetry: messageEntry.status == ChatMessageStatus.failed
                ? () => widget.onRetryMessage(messageEntry.message)
                : null,
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}

abstract class _ThreadListEntry {
  const _ThreadListEntry();
}

class _ThreadDateEntry extends _ThreadListEntry {
  final String label;

  const _ThreadDateEntry(this.label);
}

class _ThreadUnreadEntry extends _ThreadListEntry {
  const _ThreadUnreadEntry();
}

class _ThreadMessageEntry extends _ThreadListEntry {
  final ChatMessage message;
  final bool isMine;
  final String senderLabel;
  final String senderRoleLabel;
  final bool showSenderLabel;
  final bool mergeWithPrevious;
  final bool mergeWithNext;
  final ChatMessageStatus? status;

  const _ThreadMessageEntry({
    required this.message,
    required this.isMine,
    required this.senderLabel,
    required this.senderRoleLabel,
    required this.showSenderLabel,
    required this.mergeWithPrevious,
    required this.mergeWithNext,
    required this.status,
  });
}

class _ThreadDateDivider extends StatelessWidget {
  final String label;

  const _ThreadDateDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
              thickness: 0.8,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
              thickness: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadUnreadDivider extends StatelessWidget {
  const _ThreadUnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: scheme.primary.withValues(alpha: 0.45),
              thickness: 1,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.18),
                scheme.surface,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
            ),
            child: Text(
              "Unread",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: scheme.primary.withValues(alpha: 0.45),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final List<ChatAttachment> attachments;
  final void Function(String id) onRemove;

  const _AttachmentRow({required this.attachments, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: attachments
          .map(
            (attachment) => ChatAttachmentChip(
              attachment: attachment,
              onRemove: () => onRemove(attachment.id),
            ),
          )
          .toList(),
    );
  }
}

class _DispatchDraft {
  final String carrierName;
  final String trackingReference;
  final String dispatchNote;
  final DateTime estimatedDeliveryDate;

  const _DispatchDraft({
    required this.carrierName,
    required this.trackingReference,
    required this.dispatchNote,
    required this.estimatedDeliveryDate,
  });
}

Color _requestAccentForStatus(String status) {
  switch (status.trim().toLowerCase()) {
    case "accepted":
    case "requested":
      return AppColors.businessAccent;
    case "approved":
    case "delivered":
      return AppColors.success;
    case "shipped":
      return AppColors.analyticsAccent;
    case "quoted":
    case "proof_submitted":
    case "proof uploaded":
      return AppColors.commerceAccent;
    case "rejected":
    case "cancelled":
      return AppColors.error;
    default:
      return AppColors.businessAccent;
  }
}

Color _requestAssistantAccent(bool isCovering) {
  return isCovering ? const Color(0xFF35D6B4) : AppColors.commerceAccent;
}

class _PurchaseRequestPanel extends StatelessWidget {
  final PurchaseRequest request;
  final bool isBusinessActor;
  final bool canSendInvoice;
  final bool canManageFulfillment;
  final bool canReviewProof;
  final bool isBuyer;
  final bool isSubmitting;
  final VoidCallback onOpenQuotation;
  final VoidCallback onUploadProof;
  final VoidCallback onApproveProof;
  final VoidCallback onRejectProof;
  final VoidCallback onShipOrder;
  final VoidCallback onMarkDelivered;
  final VoidCallback onCancelRequest;
  final VoidCallback onHide;

  const _PurchaseRequestPanel({
    required this.request,
    required this.isBusinessActor,
    required this.canSendInvoice,
    required this.canManageFulfillment,
    required this.canReviewProof,
    required this.isBuyer,
    required this.isSubmitting,
    required this.onOpenQuotation,
    required this.onUploadProof,
    required this.onApproveProof,
    required this.onRejectProof,
    required this.onShipOrder,
    required this.onMarkDelivered,
    required this.onCancelRequest,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final address = request.deliveryAddress?.address;
    final requestAccent = _requestAccentForStatus(request.status);
    final customerStepLabel = _displayRequestStatusLabel(request);
    final canCancel =
        (isBusinessActor || isBuyer) &&
        !request.isCancelled &&
        !request.isApproved;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;

              return Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        requestAccent.withValues(alpha: 0.14),
                        scheme.surface,
                      ),
                      Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.1),
                        scheme.surfaceContainerLow,
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: requestAccent.withValues(alpha: 0.34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: requestAccent.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  "Purchase request",
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "Request #${request.id.length > 6 ? request.id.substring(request.id.length - 6).toUpperCase() : request.id}",
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: requestAccent.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RequestStatusChip(status: customerStepLabel),
                        const SizedBox(width: 8),
                        _InlineDismissButton(onPressed: onHide),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (request.isCancelled || request.isRejected) ...[
                      _RequestTerminalBanner(
                        request: request,
                        accent: requestAccent,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _RequestProgressStepper(
                      request: request,
                      accent: requestAccent,
                    ),
                    const SizedBox(height: 12),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _RequestSummarySection(
                                  request: request,
                                  accent: requestAccent,
                                  addressLabel: address == null
                                      ? ""
                                      : _addressLabel(address),
                                ),
                                if (isBusinessActor) ...[
                                  const SizedBox(height: 10),
                                  _SellerInternalSummary(
                                    request: request,
                                    accent: requestAccent,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _CustomerCareStatus(
                                  customerCare: request.customerCare,
                                  compact: true,
                                ),
                                const SizedBox(height: 10),
                                _RequestPrimaryActionSection(
                                  request: request,
                                  accent: requestAccent,
                                  isBusinessActor: isBusinessActor,
                                  canSendInvoice: canSendInvoice,
                                  canManageFulfillment: canManageFulfillment,
                                  canReviewProof: canReviewProof,
                                  isBuyer: isBuyer,
                                  isSubmitting: isSubmitting,
                                  onOpenQuotation: onOpenQuotation,
                                  onUploadProof: onUploadProof,
                                  onApproveProof: onApproveProof,
                                  onRejectProof: onRejectProof,
                                  onShipOrder: onShipOrder,
                                  onMarkDelivered: onMarkDelivered,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _CustomerCareStatus(
                        customerCare: request.customerCare,
                        compact: true,
                      ),
                      const SizedBox(height: 10),
                      _RequestPrimaryActionSection(
                        request: request,
                        accent: requestAccent,
                        isBusinessActor: isBusinessActor,
                        canSendInvoice: canSendInvoice,
                        canManageFulfillment: canManageFulfillment,
                        canReviewProof: canReviewProof,
                        isBuyer: isBuyer,
                        isSubmitting: isSubmitting,
                        onOpenQuotation: onOpenQuotation,
                        onUploadProof: onUploadProof,
                        onApproveProof: onApproveProof,
                        onRejectProof: onRejectProof,
                        onShipOrder: onShipOrder,
                        onMarkDelivered: onMarkDelivered,
                      ),
                      const SizedBox(height: 10),
                      _RequestSummarySection(
                        request: request,
                        accent: requestAccent,
                        addressLabel: address == null
                            ? ""
                            : _addressLabel(address),
                      ),
                      if (isBusinessActor) ...[
                        const SizedBox(height: 10),
                        _SellerInternalSummary(
                          request: request,
                          accent: requestAccent,
                        ),
                      ],
                    ],
                    if (canCancel) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: _compactTextRequestActionStyle(context),
                          onPressed: isSubmitting ? null : onCancelRequest,
                          icon: const Icon(Icons.block_rounded, size: 16),
                          label: const Text("Cancel"),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _addressLabel(dynamic address) {
    final parts =
        [
              address.houseNumber?.toString(),
              address.street?.toString(),
              address.city?.toString(),
              address.state?.toString(),
            ]
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
    return parts.join(", ");
  }
}

String _displayRequestStatusLabel(PurchaseRequest request) {
  if (request.isCancelled) return "Cancelled";
  if (request.isRejected) return "Rejected";
  switch (request.progressStage) {
    case "requested":
      return "Accepted";
    case "quoted":
      return "Quoted";
    case "proof_submitted":
      return "Proof Uploaded";
    case "approved":
      return "Approved";
    case "shipped":
      return "Shipped";
    case "delivered":
      return "Delivered";
    default:
      return request.status.replaceAll("_", " ");
  }
}

int _requestProgressIndex(PurchaseRequest request) {
  if (request.isRejected) return 2;
  if (request.isCancelled) {
    if (request.proof.isSubmitted) return 2;
    if (request.invoice.isSent) return 1;
    return 0;
  }

  switch (request.progressStage) {
    case "quoted":
      return 1;
    case "proof_submitted":
      return 2;
    case "approved":
      return 3;
    case "shipped":
      return 4;
    case "delivered":
      return 5;
    default:
      return 0;
  }
}

class _RequestTerminalBanner extends StatelessWidget {
  final PurchaseRequest request;
  final Color accent;

  const _RequestTerminalBanner({required this.request, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = request.isCancelled ? "Cancelled" : "Proof rejected";
    final body = request.isCancelled
        ? (request.cancelReason.trim().isNotEmpty
              ? request.cancelReason
              : "This purchase request was cancelled before fulfillment.")
        : (request.proof.reviewNote.trim().isNotEmpty
              ? request.proof.reviewNote
              : "The seller rejected the uploaded proof. The buyer can upload a replacement after clarification.");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.14), scheme.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestProgressStepper extends StatelessWidget {
  final PurchaseRequest request;
  final Color accent;

  const _RequestProgressStepper({required this.request, required this.accent});

  @override
  Widget build(BuildContext context) {
    const labels = <String>[
      "Accepted",
      "Quoted",
      "Proof",
      "Approved",
      "Shipped",
      "Delivered",
    ];
    final currentIndex = _requestProgressIndex(request);
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(labels.length, (index) {
          final isComplete = index < currentIndex;
          final isCurrent = index == currentIndex;
          final tone = isCurrent || isComplete
              ? accent
              : scheme.outlineVariant.withValues(alpha: 0.6);

          return Row(
            children: [
              if (index > 0)
                Container(
                  width: 44,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: index <= currentIndex
                        ? accent.withValues(alpha: 0.55)
                        : scheme.outlineVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Color.alphaBlend(
                              accent.withValues(alpha: 0.2),
                              scheme.surface,
                            )
                          : isComplete
                          ? accent
                          : scheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tone,
                        width: isCurrent ? 1.8 : 1.2,
                      ),
                    ),
                    child: Center(
                      child: isComplete
                          ? Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: scheme.surface,
                            )
                          : Text(
                              "${index + 1}",
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: isCurrent
                                        ? accent
                                        : scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 68,
                    child: Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isCurrent || isComplete
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: isCurrent
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _RequestSummarySection extends StatelessWidget {
  final PurchaseRequest request;
  final Color accent;
  final String addressLabel;

  const _RequestSummarySection({
    required this.request,
    required this.accent,
    required this.addressLabel,
  });

  @override
  Widget build(BuildContext context) {
    final itemSummary = request.items.isEmpty
        ? "No items"
        : "${request.items.first.quantity} x ${request.items.first.name}${request.items.length > 1 ? " +${request.items.length - 1} more" : ""}";
    final detailWidgets = <Widget>[
      _RequestMetaChip(
        icon: Icons.inventory_2_outlined,
        label: "Item cost",
        value: formatNgnFromCents(request.subtotalAmountCents),
        accent: accent,
        emphasize: true,
      ),
      _RequestMetaChip(
        icon: Icons.local_shipping_outlined,
        label: "Logistics",
        value: request.invoice.isSent || request.isApproved
            ? formatNgnFromCents(request.customerVisibleLogisticsFeeCents)
            : "Pending quote",
        accent: accent,
      ),
      _RequestMetaChip(
        icon: Icons.calendar_month_outlined,
        label: "ETA",
        value: formatDateLabel(
          request.activeEstimatedDeliveryDate,
          fallback: request.invoice.isSent ? "Awaiting date" : "Not set",
        ),
        accent: accent,
      ),
      _RequestMetaChip(
        icon: Icons.storefront_outlined,
        label: "Service",
        value: request.invoice.isSent || request.isApproved
            ? formatNgnFromCents(request.charges.serviceChargeCents)
            : "5% at quote",
        accent: accent,
      ),
      if (request.invoice.isSent || request.isApproved)
        _RequestMetaChip(
          icon: Icons.payments_outlined,
          label: "Total due",
          value: formatNgnFromCents(request.totalAmountCents),
          accent: accent,
          emphasize: true,
        ),
      _RequestMetaChip(
        icon: Icons.view_list_outlined,
        label: "Items",
        value: itemSummary,
        accent: accent,
      ),
      if (addressLabel.trim().isNotEmpty)
        _RequestMetaChip(
          icon: Icons.location_on_outlined,
          label: "Delivery",
          value: addressLabel,
          accent: accent,
        ),
    ];

    return _RequestSectionCard(
      title: "Customer view",
      accent: accent,
      child: Wrap(spacing: 8, runSpacing: 8, children: detailWidgets),
    );
  }
}

class _SellerInternalSummary extends StatelessWidget {
  final PurchaseRequest request;
  final Color accent;

  const _SellerInternalSummary({required this.request, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _RequestSectionCard(
      title: "Seller breakdown",
      accent: accent,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _RequestMetaChip(
            icon: Icons.local_shipping_outlined,
            label: "Base logistics",
            value: formatNgnFromCents(request.charges.baseLogisticsFeeCents),
            accent: accent,
          ),
          _RequestMetaChip(
            icon: Icons.percent_rounded,
            label: "Seller markup",
            value: request.charges.sellerMarkupPercent <= 0
                ? "0%"
                : "${request.charges.sellerMarkupPercent.toStringAsFixed(request.charges.sellerMarkupPercent % 1 == 0 ? 0 : 2)}%",
            accent: accent,
          ),
          _RequestMetaChip(
            icon: Icons.add_card_outlined,
            label: "Markup value",
            value: formatNgnFromCents(request.charges.sellerMarkupAmountCents),
            accent: accent,
          ),
          if (request.invoice.invoiceNumber.trim().isNotEmpty)
            _RequestMetaChip(
              icon: Icons.receipt_long_outlined,
              label: "Invoice",
              value: request.invoice.invoiceNumber,
              accent: accent,
            ),
        ],
      ),
    );
  }
}

class _RequestPrimaryActionSection extends StatelessWidget {
  final PurchaseRequest request;
  final Color accent;
  final bool isBusinessActor;
  final bool canSendInvoice;
  final bool canManageFulfillment;
  final bool canReviewProof;
  final bool isBuyer;
  final bool isSubmitting;
  final VoidCallback onOpenQuotation;
  final VoidCallback onUploadProof;
  final VoidCallback onApproveProof;
  final VoidCallback onRejectProof;
  final VoidCallback onShipOrder;
  final VoidCallback onMarkDelivered;

  const _RequestPrimaryActionSection({
    required this.request,
    required this.accent,
    required this.isBusinessActor,
    required this.canSendInvoice,
    required this.canManageFulfillment,
    required this.canReviewProof,
    required this.isBuyer,
    required this.isSubmitting,
    required this.onOpenQuotation,
    required this.onUploadProof,
    required this.onApproveProof,
    required this.onRejectProof,
    required this.onShipOrder,
    required this.onMarkDelivered,
  });

  @override
  Widget build(BuildContext context) {
    if (isBusinessActor && canSendInvoice && request.canSellerEditInvoice) {
      return _RequestQuotationLaunchCard(
        request: request,
        accent: accent,
        isSubmitting: isSubmitting,
        onOpenQuotation: onOpenQuotation,
      );
    }

    if (request.canSellerReviewProof && canReviewProof) {
      return _RequestSectionCard(
        title: "Review payment proof",
        accent: accent,
        trailing: _HandoffStateChip(label: "Password required", accent: accent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.proof.filename.trim().isNotEmpty
                  ? "Proof file: ${request.proof.filename}"
                  : "The buyer uploaded a payment proof. Approval still requires account password confirmation.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  style: _compactRequestActionStyle(context),
                  onPressed: isSubmitting ? null : onApproveProof,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text("Approve proof"),
                ),
                OutlinedButton.icon(
                  style: _compactOutlinedRequestActionStyle(context),
                  onPressed: isSubmitting ? null : onRejectProof,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text("Reject proof"),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (request.isApproved) {
      return _RequestFulfillmentSection(
        request: request,
        accent: accent,
        canManageFulfillment: canManageFulfillment,
        isSubmitting: isSubmitting,
        onShipOrder: onShipOrder,
        onMarkDelivered: onMarkDelivered,
      );
    }

    if (isBuyer && request.canBuyerSubmitProof) {
      return _RequestSectionCard(
        title: "Upload payment proof",
        accent: accent,
        trailing: _HandoffStateChip(label: "Awaiting proof", accent: accent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request.invoice.paymentInstructions.trim().isNotEmpty)
              Text(
                request.invoice.paymentInstructions,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              style: _compactRequestActionStyle(context),
              onPressed: isSubmitting ? null : onUploadProof,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(
                request.isRejected
                    ? "Upload replacement proof"
                    : "Upload proof",
              ),
            ),
          ],
        ),
      );
    }

    if (request.isQuoted || request.isRejected) {
      return _RequestSectionCard(
        title: "Awaiting buyer action",
        accent: accent,
        trailing: _HandoffStateChip(label: "Quoted", accent: accent),
        child: Text(
          request.invoice.paymentInstructions.trim().isNotEmpty
              ? request.invoice.paymentInstructions
              : "The invoice has been sent. The buyer can review the total and upload payment proof in this chat.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      );
    }

    return _RequestSectionCard(
      title: "Awaiting seller quote",
      accent: accent,
      child: Text(
        "The team still needs to confirm delivery cost, service charge, and payment instructions before the invoice can be sent.",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    );
  }
}

class _RequestSectionCard extends StatelessWidget {
  final String title;
  final Color accent;
  final Widget child;
  final Widget? trailing;

  const _RequestSectionCard({
    required this.title,
    required this.accent,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.08),
          scheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _RequestQuotationLaunchCard extends StatelessWidget {
  final PurchaseRequest request;
  final Color accent;
  final bool isSubmitting;
  final VoidCallback onOpenQuotation;

  const _RequestQuotationLaunchCard({
    required this.request,
    required this.accent,
    required this.isSubmitting,
    required this.onOpenQuotation,
  });

  @override
  Widget build(BuildContext context) {
    final isEditingExisting = request.invoice.isSent;
    final etaLabel = formatDateLabel(
      request.invoice.estimatedDeliveryDate,
      fallback: "Not set",
    );

    return _RequestSectionCard(
      title: isEditingExisting ? "Quotation ready" : "Awaiting quotation",
      accent: accent,
      trailing: _HandoffStateChip(
        label: isEditingExisting ? "Edit" : "Create",
        accent: accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditingExisting
                ? "Open the dedicated quotation screen to update pricing, service percentage, payment instructions, or ETA without crowding the chat card."
                : "Open the quotation screen to prepare the seller quote with logistics, seller service percentage, payment instructions, and delivery date.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RequestMetaChip(
                icon: Icons.receipt_long_outlined,
                label: "Action",
                value: isEditingExisting
                    ? "Edit quotation"
                    : "Create quotation",
                accent: accent,
              ),
              _RequestMetaChip(
                icon: Icons.percent_rounded,
                label: "Service %",
                value: request.charges.sellerMarkupPercent <= 0
                    ? "0%"
                    : "${request.charges.sellerMarkupPercent.toStringAsFixed(request.charges.sellerMarkupPercent % 1 == 0 ? 0 : 2)}%",
                accent: accent,
              ),
              _RequestMetaChip(
                icon: Icons.calendar_month_outlined,
                label: "ETA",
                value: etaLabel,
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              style: _compactRequestActionStyle(context),
              onPressed: isSubmitting ? null : onOpenQuotation,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                isEditingExisting ? "Edit quotation" : "Create quotation",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestFulfillmentSection extends StatelessWidget {
  final PurchaseRequest request;
  final Color accent;
  final bool canManageFulfillment;
  final bool isSubmitting;
  final VoidCallback onShipOrder;
  final VoidCallback onMarkDelivered;

  const _RequestFulfillmentSection({
    required this.request,
    required this.accent,
    required this.canManageFulfillment,
    required this.isSubmitting,
    required this.onShipOrder,
    required this.onMarkDelivered,
  });

  @override
  Widget build(BuildContext context) {
    final fulfillment = request.fulfillment;
    final linkedStatus = request.linkedOrderStatus.toLowerCase();

    return _RequestSectionCard(
      title: "Fulfillment",
      accent: accent,
      trailing: _HandoffStateChip(
        label: _displayRequestStatusLabel(request),
        accent: accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (fulfillment?.carrierName.trim().isNotEmpty == true)
                _RequestMetaChip(
                  icon: Icons.local_shipping_outlined,
                  label: "Carrier",
                  value: fulfillment!.carrierName,
                  accent: accent,
                ),
              if (fulfillment?.trackingReference.trim().isNotEmpty == true)
                _RequestMetaChip(
                  icon: Icons.route_outlined,
                  label: "Tracking",
                  value: fulfillment!.trackingReference,
                  accent: accent,
                ),
              _RequestMetaChip(
                icon: Icons.calendar_month_outlined,
                label: "ETA",
                value: formatDateLabel(
                  fulfillment?.estimatedDeliveryDate ??
                      request.invoice.estimatedDeliveryDate,
                  fallback: "Awaiting dispatch",
                ),
                accent: accent,
              ),
              if (fulfillment?.shippedAt != null)
                _RequestMetaChip(
                  icon: Icons.move_to_inbox_outlined,
                  label: "Shipped",
                  value: formatDateTimeLabel(fulfillment?.shippedAt),
                  accent: accent,
                ),
              if (fulfillment?.deliveredAt != null)
                _RequestMetaChip(
                  icon: Icons.check_circle_outline_rounded,
                  label: "Delivered",
                  value: formatDateTimeLabel(fulfillment?.deliveredAt),
                  accent: accent,
                ),
            ],
          ),
          if (fulfillment?.dispatchNote.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              fulfillment!.dispatchNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (canManageFulfillment) ...[
            const SizedBox(height: 10),
            if (linkedStatus.isEmpty || linkedStatus == "paid")
              FilledButton.tonalIcon(
                style: _compactRequestActionStyle(context),
                onPressed: isSubmitting ? null : onShipOrder,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text("Add dispatch info"),
              )
            else if (linkedStatus == "shipped")
              FilledButton.tonalIcon(
                style: _compactRequestActionStyle(context),
                onPressed: isSubmitting ? null : onMarkDelivered,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text("Mark delivered"),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProofApprovalDraft {
  final String reviewNote;
  final String approvalPassword;

  const _ProofApprovalDraft({
    required this.reviewNote,
    required this.approvalPassword,
  });
}

class _CustomerCareStatus extends StatelessWidget {
  final PurchaseRequestCustomerCare customerCare;
  final bool compact;

  const _CustomerCareStatus({required this.customerCare, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final assistantName = customerCare.assistantName.trim().isEmpty
        ? "Amara"
        : customerCare.assistantName.trim();
    final isCovering = customerCare.aiControlEnabled;
    final modeAccent = _requestAssistantAccent(isCovering);
    final roleLabel = customerCare.attendantLabel.trim().isEmpty
        ? "Team member"
        : customerCare.attendantLabel
              .replaceAll("_", " ")
              .split(" ")
              .where((part) => part.trim().isNotEmpty)
              .map(
                (part) =>
                    "${part[0].toUpperCase()}${part.substring(1).toLowerCase()}",
              )
              .join(" ");
    final statusText = isCovering
        ? "$assistantName is covering this conversation."
        : customerCare.currentAttendantName.trim().isNotEmpty
        ? "${customerCare.currentAttendantName} is currently attending as $roleLabel."
        : "A human agent is currently attending this request.";
    final showAttendant =
        !isCovering && customerCare.currentAttendantName.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 9 : 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              modeAccent.withValues(alpha: 0.2),
              scheme.surfaceContainerHigh,
            ),
            Color.alphaBlend(
              (isCovering ? scheme.primary : AppColors.businessAccent)
                  .withValues(alpha: 0.08),
              scheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: modeAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Request assistant",
                  style:
                      (compact
                              ? theme.textTheme.labelSmall
                              : theme.textTheme.labelSmall)
                          ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              _HandoffStateChip(
                label: isCovering ? "AI active" : "Human active",
                accent: modeAccent,
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            statusText,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style:
                (compact
                        ? theme.textTheme.labelMedium
                        : theme.textTheme.bodySmall)
                    ?.copyWith(
                      height: compact ? 1.2 : 1.35,
                      color: scheme.onSurface.withValues(alpha: 0.88),
                    ),
          ),
          if (showAttendant) ...[
            SizedBox(height: compact ? 6 : 10),
            _AttendantCompactChip(
              accent: modeAccent,
              name: customerCare.currentAttendantName,
              roleLabel: roleLabel,
              dense: compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendantCompactChip extends StatelessWidget {
  final Color accent;
  final String name;
  final String roleLabel;
  final bool dense;

  const _AttendantCompactChip({
    required this.accent,
    required this.name,
    required this.roleLabel,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.12), scheme.surface),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 24 : 28,
            height: dense ? 24 : 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              size: dense ? 14 : 16,
              color: accent,
            ),
          ),
          SizedBox(width: dense ? 6 : 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (dense
                              ? theme.textTheme.labelSmall
                              : theme.textTheme.labelMedium)
                          ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

ButtonStyle _compactRequestActionStyle(BuildContext context) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

ButtonStyle _compactOutlinedRequestActionStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

ButtonStyle _compactTextRequestActionStyle(BuildContext context) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 30),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    textStyle: Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _RequestMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final bool emphasize;

  const _RequestMetaChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.1), scheme.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: accent.withValues(alpha: 0.94)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  height: 1.25,
                ),
                children: [
                  TextSpan(
                    text: "$label: ",
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent.withValues(alpha: 0.94),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style:
                        (emphasize
                                ? theme.textTheme.labelLarge
                                : theme.textTheme.labelMedium)
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: emphasize
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandoffStateChip extends StatelessWidget {
  final String label;
  final Color accent;

  const _HandoffStateChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.18), scheme.surface),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class _HeaderAiToggleButton extends StatelessWidget {
  final bool enabled;
  final bool isBusy;
  final VoidCallback? onPressed;

  const _HeaderAiToggleButton({
    required this.enabled,
    required this.isBusy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = enabled ? const Color(0xFF2DE0C4) : scheme.onSurfaceVariant;

    return Tooltip(
      message: _tooltipAiToggle,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: isBusy ? 0.72 : 1,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                accent.withValues(alpha: enabled ? 0.22 : 0.08),
                scheme.surfaceContainerLow,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accent.withValues(alpha: enabled ? 0.42 : 0.2),
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  enabled ? "AI ON" : "AI OFF",
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: enabled ? accent : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
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

class _HeaderAttendChatButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool isActive;
  final bool isBusy;
  final VoidCallback? onPressed;

  const _HeaderAttendChatButton({
    required this.label,
    required this.enabled,
    required this.isActive,
    required this.isBusy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isActive
        ? const Color(0xFFFFA35C)
        : AppColors.businessAccent;

    return Tooltip(
      message: _tooltipAttend,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: isBusy ? 0.72 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: FilledButton.tonalIcon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(
              isActive ? Icons.mode_comment_rounded : Icons.headset_mic_rounded,
              size: 16,
            ),
            label: Text(label),
            style: FilledButton.styleFrom(
              foregroundColor: enabled
                  ? accent
                  : scheme.onSurfaceVariant.withValues(alpha: 0.72),
              backgroundColor: Color.alphaBlend(
                accent.withValues(alpha: isActive ? 0.2 : 0.12),
                scheme.surfaceContainerLow,
              ),
              disabledForegroundColor: scheme.onSurfaceVariant.withValues(
                alpha: 0.72,
              ),
              disabledBackgroundColor: scheme.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: accent.withValues(alpha: enabled ? 0.34 : 0.14),
                ),
              ),
              textStyle: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadOverflowMenu extends StatelessWidget {
  final String tooltip;
  final PurchaseRequest? purchaseRequest;
  final bool hasProfile;
  final bool isRequestSummaryHidden;
  final ValueChanged<_ThreadOverflowAction> onSelected;

  const _ThreadOverflowMenu({
    required this.tooltip,
    required this.purchaseRequest,
    required this.hasProfile,
    required this.isRequestSummaryHidden,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final request = purchaseRequest;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: PopupMenuButton<_ThreadOverflowAction>(
        tooltip: tooltip,
        iconColor: Colors.white,
        onSelected: onSelected,
        offset: const Offset(0, 42),
        color: Color.alphaBlend(
          scheme.surface.withValues(alpha: 0.92),
          scheme.surfaceContainerHigh,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        itemBuilder: (context) {
          return [
            if (hasProfile)
              const PopupMenuItem(
                value: _ThreadOverflowAction.viewProfile,
                child: _ThreadOverflowItem(
                  icon: Icons.person_outline_rounded,
                  label: "View profile",
                ),
              ),
            if (purchaseRequest != null && !isRequestSummaryHidden)
              const PopupMenuItem(
                value: _ThreadOverflowAction.hideRequest,
                child: _ThreadOverflowItem(
                  icon: Icons.visibility_off_outlined,
                  label: "Hide request",
                ),
              ),
            if (purchaseRequest != null && isRequestSummaryHidden)
              const PopupMenuItem(
                value: _ThreadOverflowAction.showRequest,
                child: _ThreadOverflowItem(
                  icon: Icons.visibility_outlined,
                  label: "Show request",
                ),
              ),
            if (request != null &&
                !request.customerCare.aiControlEnabled &&
                !request.isCancelled)
              const PopupMenuItem(
                value: _ThreadOverflowAction.returnToAi,
                child: _ThreadOverflowItem(
                  icon: Icons.auto_awesome_rounded,
                  label: "Return to AI",
                ),
              ),
          ];
        },
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.more_horiz_rounded, size: 20),
        ),
      ),
    );
  }
}

class _ThreadOverflowItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ThreadOverflowItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

class _InlineDismissButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _InlineDismissButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          Icons.close_rounded,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RequestRestoreButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RequestRestoreButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.center,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.unfold_more_rounded, size: 14),
          label: const Text("Show request"),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outlineVariant),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestStatusChip extends StatelessWidget {
  final String status;

  const _RequestStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = status.toLowerCase();
    final accent = _requestAccentForStatus(normalized);
    final background = Color.alphaBlend(
      accent.withValues(alpha: 0.2),
      scheme.surface,
    );
    final foreground = accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Text(
        status.replaceAll("_", " ").toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SupportThreadHeaderTitle extends StatelessWidget {
  final String title;
  final String customerStatusLabel;
  final String assignedStaffName;

  const _SupportThreadHeaderTitle({
    required this.title,
    required this.customerStatusLabel,
    required this.assignedStaffName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: _headerMetaSpacing),
        Text(
          "$customerStatusLabel$_metaSeparator$assignedStaffName",
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _StaffSupportHeaderBar extends StatelessWidget {
  final String assignedStaffName;
  final String assignedStaffLabel;
  final String conversationStatus;
  final Color conversationStatusAccent;

  const _StaffSupportHeaderBar({
    required this.assignedStaffName,
    required this.assignedStaffLabel,
    required this.conversationStatus,
    required this.conversationStatusAccent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: _appBarInfoPadding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _SupportMetaChip(
              icon: Icons.badge_outlined,
              title: "Assigned",
              value: assignedStaffName,
              tone: scheme.primary,
              subtitle: assignedStaffLabel,
            ),
            const SizedBox(width: 10),
            _SupportMetaChip(
              icon: Icons.flag_outlined,
              title: "Status",
              value: conversationStatus,
              tone: conversationStatusAccent,
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportMetaChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color tone;
  final String subtitle;

  const _SupportMetaChip({
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
    this.subtitle = "",
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tone.withValues(alpha: 0.12), scheme.surface),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: tone),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle.trim().isNotEmpty)
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThreadToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool heroStyle;

  const _ThreadToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.heroStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = heroStyle
        ? Colors.white.withValues(alpha: 0.12)
        : colorScheme.surfaceContainerLow;
    final borderColor = heroStyle
        ? Colors.white.withValues(alpha: 0.12)
        : colorScheme.outlineVariant;
    final iconColor = heroStyle
        ? Colors.white
        : onPressed == null
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: IconButton(
        color: iconColor,
        disabledColor: iconColor.withValues(alpha: 0.42),
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _ThreadHeaderTitle extends StatelessWidget {
  final String title;
  final String roleLabel;
  final String businessLabel;
  final String estateLabel;

  const _ThreadHeaderTitle({
    required this.title,
    required this.roleLabel,
    required this.businessLabel,
    required this.estateLabel,
  });

  String? _buildMetaText() {
    final labels = <String>[];
    final seen = <String>{};
    final hiddenValues = <String>{
      _fallbackRole.toLowerCase(),
      _fallbackBusiness.toLowerCase(),
      _fallbackEstate.toLowerCase(),
    };

    void addLabel(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      final normalized = trimmed.toLowerCase();
      if (hiddenValues.contains(normalized) || !seen.add(normalized)) {
        return;
      }
      labels.add(trimmed);
    }

    addLabel(roleLabel);
    addLabel(businessLabel);
    addLabel(estateLabel);
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(_metaSeparator);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaText = _buildMetaText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (metaText != null) ...[
          const SizedBox(height: _headerMetaSpacing),
          Text(
            metaText,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final List<ChatAttachment> attachments;
  final bool isSending;
  final bool isUploadingAttachments;
  final bool isVoiceRecording;
  final bool isProcessingVoiceNote;
  final Duration voiceRecordingDuration;
  final bool canSend;
  final bool canRecordVoice;
  final void Function(String id) onRemoveAttachment;
  final VoidCallback onOpenAttachmentOptions;
  final VoidCallback onToggleVoiceRecording;
  final VoidCallback onCancelVoiceRecording;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.attachments,
    required this.isSending,
    required this.isUploadingAttachments,
    required this.isVoiceRecording,
    required this.isProcessingVoiceNote,
    required this.voiceRecordingDuration,
    required this.canSend,
    required this.canRecordVoice,
    required this.onRemoveAttachment,
    required this.onOpenAttachmentOptions,
    required this.onToggleVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onSend,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;
  static const List<String> _quickEmojis = [
    "😀",
    "😂",
    "😍",
    "🙏",
    "👍",
    "🔥",
    "✅",
    "🎉",
    "❤️",
    "🙂",
    "🤝",
    "📌",
    "📦",
    "🧾",
    "📍",
    "🚚",
    "📸",
    "🎤",
    "💬",
    "👀",
  ];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!mounted) {
      return;
    }
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (!widget.canSend || widget.isSending) {
      return KeyEventResult.handled;
    }

    widget.onSend();
    return KeyEventResult.handled;
  }

  void _insertAtCursor(String text) {
    final value = widget.controller.value;
    final selection = value.selection;
    final hasSelection = selection.isValid;
    final start = hasSelection ? selection.start : value.text.length;
    final end = hasSelection ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);

    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
    _focusNode.requestFocus();
  }

  Future<void> _showEmojiPickerSheet() async {
    if (widget.isVoiceRecording || widget.isProcessingVoiceNote) {
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Add emoji",
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _quickEmojis
                      .map(
                        (emoji) => InkWell(
                          onTap: () => Navigator.of(sheetContext).pop(emoji),
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected.isEmpty) {
      return;
    }
    _insertAtCursor(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final composerSurface = isDark
        ? scheme.surfaceContainerLow
        : const Color(0xFFF7F9FD);
    final isBusy =
        widget.isSending ||
        widget.isUploadingAttachments ||
        widget.isProcessingVoiceNote;
    final showSendAction = widget.canSend;
    final voiceButtonEnabled =
        widget.isVoiceRecording || (widget.canRecordVoice && !isBusy);
    final actionTooltip = widget.isVoiceRecording
        ? "Stop and send voice note"
        : showSendAction
        ? "Send"
        : "Record voice note";
    final actionColor = widget.isVoiceRecording
        ? const Color(0xFFDC2626)
        : showSendAction
        ? scheme.primary
        : (isDark ? const Color(0xFF20304D) : const Color(0xFFE2E8F0));
    final actionIconColor = widget.isVoiceRecording || showSendAction
        ? Colors.white
        : scheme.onSurfaceVariant;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: composerSurface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: isDark ? 0.16 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isUploadingAttachments || widget.isProcessingVoiceNote)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.isUploadingAttachments
                          ? "Adding selected attachments..."
                          : "Preparing voice note...",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.isVoiceRecording)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A1620)
                      : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF5C2230)
                        : const Color(0xFFF3B4BF),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fiber_manual_record_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Recording ${_formatComposerDuration(widget.voiceRecordingDuration)}",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.onCancelVoiceRecording,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text("Cancel"),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        textStyle: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.attachments.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF19263B)
                      : const Color(0xFFF0F4FB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2B3A54)
                        : const Color(0xFFD6E0EF),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${widget.attachments.length} attachment${widget.attachments.length == 1 ? "" : "s"} ready to send",
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _AttachmentRow(
                      attachments: widget.attachments,
                      onRemove: widget.onRemoveAttachment,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF162133) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _hasFocus
                            ? (isDark
                                  ? const Color(0xFF7F95E8)
                                  : const Color(0xFF8AA0EB))
                            : (isDark
                                  ? const Color(0xFF2A3851)
                                  : const Color(0xFFD4DFEE)),
                      ),
                      boxShadow: _hasFocus
                          ? [
                              BoxShadow(
                                color: scheme.primary.withValues(
                                  alpha: isDark ? 0.14 : 0.1,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : const [],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _ComposerInlineIconButton(
                          tooltip: "Add attachment",
                          icon: Icons.attach_file_rounded,
                          onPressed: isBusy || widget.isVoiceRecording
                              ? null
                              : widget.onOpenAttachmentOptions,
                        ),
                        Expanded(
                          child: widget.isVoiceRecording
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    "Tap stop to send your voice note",
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : Focus(
                                  focusNode: _focusNode,
                                  onKeyEvent: _handleKeyEvent,
                                  child: TextField(
                                    controller: widget.controller,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    minLines: 1,
                                    maxLines: 5,
                                    decoration: InputDecoration(
                                      hintText: widget.attachments.isEmpty
                                          ? "Message"
                                          : "Add a caption or send now",
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                ),
                        ),
                        _ComposerInlineIconButton(
                          tooltip: "Add emoji",
                          icon: Icons.emoji_emotions_outlined,
                          onPressed: isBusy || widget.isVoiceRecording
                              ? null
                              : _showEmojiPickerSheet,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: actionTooltip,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: actionColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: widget.canSend || widget.isVoiceRecording
                          ? [
                              BoxShadow(
                                color: actionColor.withValues(alpha: 0.24),
                                blurRadius: 14,
                                offset: const Offset(0, 7),
                              ),
                            ]
                          : const [],
                    ),
                    child: IconButton(
                      tooltip: actionTooltip,
                      onPressed: widget.isSending
                          ? null
                          : widget.canSend
                          ? widget.onSend
                          : voiceButtonEnabled
                          ? widget.onToggleVoiceRecording
                          : null,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: widget.isSending || widget.isProcessingVoiceNote
                            ? SizedBox(
                                key: const ValueKey("composer_action_loading"),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : widget.isVoiceRecording
                            ? Icon(
                                Icons.stop_rounded,
                                key: const ValueKey("composer_stop_voice"),
                                color: actionIconColor,
                              )
                            : Icon(
                                widget.canSend
                                    ? Icons.send_rounded
                                    : Icons.mic_rounded,
                                key: ValueKey(
                                  widget.canSend
                                      ? "composer_send"
                                      : "composer_mic",
                                ),
                                color: actionIconColor,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatComposerDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, "0");
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, "0");
  return "$minutes:$seconds";
}

class _ComposerInlineIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _ComposerInlineIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: scheme.onSurfaceVariant,
      disabledColor: scheme.onSurfaceVariant.withValues(alpha: 0.42),
      icon: Icon(icon),
    );
  }
}

class _ComposerAttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  const _ComposerAttachOption({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tone.withValues(alpha: 0.22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: tone),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
