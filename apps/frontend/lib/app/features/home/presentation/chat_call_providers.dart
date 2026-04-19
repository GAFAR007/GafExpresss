/// lib/app/features/home/presentation/chat_call_providers.dart
/// -----------------------------------------------------------
/// WHAT:
/// - Global Riverpod controller for in-app chat voice calls.
///
/// WHY:
/// - Incoming calls must surface anywhere in the app, not only inside a thread.
/// - Keeps WebRTC, REST, and socket signaling out of widgets.
///
/// HOW:
/// - Reuses ChatApi + ChatSocketService for call lifecycle and signaling.
/// - Manages one active call session at a time with a provider-driven overlay.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/auth_session.dart';
import 'package:frontend/app/features/home/presentation/chat_api.dart';
import 'package:frontend/app/features/home/presentation/chat_constants.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_socket_service.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

const String _logTag = "CHAT_CALL";
const String _logIncoming = "incoming_call";
const String _logStart = "start_call";
const String _logAccept = "accept_call";
const String _logEnd = "end_call";
const String _logSignal = "signal_event";
const String _logPeer = "peer_state";

enum ChatCallPhase { idle, incoming, outgoing, connecting, active }

class ChatCallState {
  final ChatCallSession? call;
  final ChatCallPhase phase;
  final bool isMuted;
  final String connectionLabel;
  final String? errorMessage;

  const ChatCallState({
    required this.call,
    required this.phase,
    required this.isMuted,
    required this.connectionLabel,
    required this.errorMessage,
  });

  factory ChatCallState.initial() {
    return const ChatCallState(
      call: null,
      phase: ChatCallPhase.idle,
      isMuted: false,
      connectionLabel: "",
      errorMessage: null,
    );
  }

  bool get hasActiveOverlay => call != null;

  ChatCallState copyWith({
    ChatCallSession? call,
    bool clearCall = false,
    ChatCallPhase? phase,
    bool? isMuted,
    String? connectionLabel,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatCallState(
      call: clearCall ? null : (call ?? this.call),
      phase: phase ?? this.phase,
      isMuted: isMuted ?? this.isMuted,
      connectionLabel: connectionLabel ?? this.connectionLabel,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ChatCallController extends StateNotifier<ChatCallState> {
  final Ref _ref;
  StreamSubscription? _incomingSub;
  StreamSubscription? _updateSub;
  StreamSubscription? _endedSub;
  StreamSubscription? _signalSub;
  Timer? _ringTimeout;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  Future<void>? _rendererReady;
  final List<ChatCallSignalPayload> _pendingCandidates =
      <ChatCallSignalPayload>[];
  bool _remoteDescriptionReady = false;
  bool _offerSent = false;
  String _peerCallId = "";
  bool _disposed = false;

  ChatCallController({required Ref ref})
    : _ref = ref,
      super(ChatCallState.initial()) {
    _rendererReady = _initializeRenderers();
    _bindSocketStreams();
    updateSession(_ref.read(authSessionProvider));
  }

  ChatSocketService get _socket => _ref.read(chatSocketProvider);
  ChatApi get _api => _ref.read(chatApiProvider);

  AuthSession? get _session => _ref.read(authSessionProvider);

  String get _currentUserId => _session?.user.id ?? "";

  Future<void> _initializeRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  void _bindSocketStreams() {
    _incomingSub = _socket.incomingCallStream.listen((event) {
      _handleIncomingCall(event.call);
    });
    _updateSub = _socket.callUpdateStream.listen((event) {
      _handleCallUpdate(event.call);
    });
    _endedSub = _socket.callEndedStream.listen((event) {
      _handleTerminalCall(event.call);
    });
    _signalSub = _socket.callSignalStream.listen((event) {
      unawaited(_handleSignalEvent(event));
    });
  }

  void updateSession(AuthSession? session) {
    if (_disposed) return;
    if (session == null || !session.isTokenValid) {
      _socket.disconnect();
      unawaited(_resetTransport());
      state = ChatCallState.initial();
      return;
    }
    _socket.connect(token: session.token);
  }

  Future<String?> startOutgoingCall({required String conversationId}) async {
    if (state.call != null && !(state.call?.isTerminal ?? false)) {
      return "Finish the current call before starting another one.";
    }

    final session = _session;
    if (session == null || !session.isTokenValid) {
      return "Session expired. Please sign in again.";
    }

    try {
      await _ensureLocalStream();
      AppDebug.log(
        _logTag,
        _logStart,
        extra: {"conversationId": conversationId},
      );
      final call = await _api.startCall(
        token: session.token,
        conversationId: conversationId,
        mediaMode: chatCallMediaModeAudio,
      );
      _applyCall(
        call,
        phase: ChatCallPhase.outgoing,
        connectionLabel: "Calling...",
      );
      _armRingTimeout(call);
      return null;
    } catch (error) {
      await _resetTransport();
      return _resolveCallError(error);
    }
  }

  Future<void> acceptIncomingCall() async {
    final call = state.call;
    final session = _session;
    if (call == null || session == null || !session.isTokenValid) {
      return;
    }

    try {
      await _ensureLocalStream();
      AppDebug.log(_logTag, _logAccept, extra: {"callId": call.id});
      final updated = await _api.acceptCall(
        token: session.token,
        callId: call.id,
      );
      _applyCall(
        updated,
        phase: ChatCallPhase.connecting,
        connectionLabel: "Connecting...",
      );
      await _activateCall(updated);
    } catch (error) {
      state = state.copyWith(errorMessage: _resolveCallError(error));
    }
  }

  Future<void> declineIncomingCall({String reason = "declined"}) async {
    final call = state.call;
    final session = _session;
    if (call == null || session == null || !session.isTokenValid) {
      return;
    }

    try {
      await _api.declineCall(
        token: session.token,
        callId: call.id,
        reason: reason,
      );
    } catch (_) {
      // WHY: Socket updates will reconcile the terminal state if the request won.
    } finally {
      await _finishCallLocally();
    }
  }

  Future<void> endCurrentCall({String? reason}) async {
    final call = state.call;
    final session = _session;
    if (call == null || session == null || !session.isTokenValid) {
      return;
    }

    final currentReason =
        reason ??
        (call.isRinging
            ? (call.isIncomingFor(_currentUserId) ? "declined" : "cancelled")
            : "ended");

    try {
      AppDebug.log(
        _logTag,
        _logEnd,
        extra: {"callId": call.id, "reason": currentReason},
      );
      if (currentReason == "declined" || currentReason == "busy") {
        await _api.declineCall(
          token: session.token,
          callId: call.id,
          reason: currentReason,
        );
      } else {
        await _api.endCall(
          token: session.token,
          callId: call.id,
          reason: currentReason,
        );
      }
    } catch (_) {
      // WHY: The call UI should still close when the local user chooses to hang up.
    } finally {
      await _finishCallLocally();
    }
  }

  void toggleMute() {
    final nextMuted = !state.isMuted;
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = !nextMuted;
    }
    state = state.copyWith(isMuted: nextMuted);
  }

  void _handleIncomingCall(ChatCallSession call) {
    if (_disposed || _currentUserId.isEmpty) return;
    if (!call.isIncomingFor(_currentUserId)) return;

    AppDebug.log(_logTag, _logIncoming, extra: {"callId": call.id});
    final existing = state.call;
    if (existing != null && !existing.isTerminal && existing.id != call.id) {
      unawaited(_autoDeclineBusy(call.id));
      return;
    }

    _cancelRingTimeout();
    _applyCall(
      call,
      phase: ChatCallPhase.incoming,
      connectionLabel: "Incoming voice call",
    );
  }

  void _handleCallUpdate(ChatCallSession call) {
    if (_disposed || _currentUserId.isEmpty) return;
    final activeId = state.call?.id ?? "";
    if (activeId.isNotEmpty && activeId != call.id) {
      return;
    }
    if (call.isTerminal) {
      unawaited(_handleTerminalCall(call));
      return;
    }

    if (call.isRinging) {
      final phase = call.isIncomingFor(_currentUserId)
          ? ChatCallPhase.incoming
          : ChatCallPhase.outgoing;
      _applyCall(
        call,
        phase: phase,
        connectionLabel: call.isIncomingFor(_currentUserId)
            ? "Incoming voice call"
            : "Calling...",
      );
      if (!call.isIncomingFor(_currentUserId)) {
        _armRingTimeout(call);
      }
      return;
    }

    _cancelRingTimeout();
    _applyCall(
      call,
      phase: state.phase == ChatCallPhase.active
          ? ChatCallPhase.active
          : ChatCallPhase.connecting,
      connectionLabel: state.phase == ChatCallPhase.active
          ? "Connected"
          : "Connecting...",
    );
    unawaited(_activateCall(call));
  }

  Future<void> _handleTerminalCall(ChatCallSession call) async {
    if (_disposed) return;
    if (state.call?.id.isNotEmpty == true && state.call?.id != call.id) {
      return;
    }
    await _finishCallLocally();
  }

  Future<void> _activateCall(ChatCallSession call) async {
    try {
      await _ensureLocalStream();
      await _ensurePeerConnection(call.id);
      if (call.callerUserId == _currentUserId && !_offerSent) {
        final offer = await _peerConnection!.createOffer(<String, dynamic>{
          "offerToReceiveAudio": true,
          "offerToReceiveVideo": false,
        });
        await _peerConnection!.setLocalDescription(offer);
        _offerSent = true;
        _socket.emitCallSignal(
          callId: call.id,
          signal: ChatCallSignalPayload(
            type: offer.type ?? "offer",
            sdp: offer.sdp ?? "",
            candidate: "",
            sdpMid: "",
            sdpMLineIndex: null,
          ),
        );
      }
    } catch (error) {
      state = state.copyWith(errorMessage: _resolveCallError(error));
    }
  }

  Future<void> _handleSignalEvent(ChatSocketCallSignalEvent event) async {
    final call = state.call;
    if (_disposed || call == null || call.id != event.callId) {
      return;
    }

    AppDebug.log(
      _logTag,
      _logSignal,
      extra: {"callId": event.callId, "type": event.signal.type},
    );

    try {
      await _ensureLocalStream();
      await _ensurePeerConnection(event.callId);

      if (event.signal.isOffer) {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(event.signal.sdp, event.signal.type),
        );
        _remoteDescriptionReady = true;
        await _flushPendingCandidates();

        final answer = await _peerConnection!.createAnswer(<String, dynamic>{
          "offerToReceiveAudio": true,
          "offerToReceiveVideo": false,
        });
        await _peerConnection!.setLocalDescription(answer);
        _socket.emitCallSignal(
          callId: event.callId,
          signal: ChatCallSignalPayload(
            type: answer.type ?? "answer",
            sdp: answer.sdp ?? "",
            candidate: "",
            sdpMid: "",
            sdpMLineIndex: null,
          ),
        );
        return;
      }

      if (event.signal.isAnswer) {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(event.signal.sdp, event.signal.type),
        );
        _remoteDescriptionReady = true;
        await _flushPendingCandidates();
        return;
      }

      if (!event.signal.isCandidate) {
        return;
      }

      if (!_remoteDescriptionReady) {
        _pendingCandidates.add(event.signal);
        return;
      }

      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          event.signal.candidate,
          event.signal.sdpMid.isEmpty ? null : event.signal.sdpMid,
          event.signal.sdpMLineIndex,
        ),
      );
    } catch (error) {
      state = state.copyWith(errorMessage: _resolveCallError(error));
    }
  }

  Future<void> _flushPendingCandidates() async {
    while (_pendingCandidates.isNotEmpty && _peerConnection != null) {
      final candidate = _pendingCandidates.removeAt(0);
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          candidate.candidate,
          candidate.sdpMid.isEmpty ? null : candidate.sdpMid,
          candidate.sdpMLineIndex,
        ),
      );
    }
  }

  Future<void> _ensureLocalStream() async {
    if (_localStream != null) {
      return;
    }
    await _rendererReady;
    final stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
      "audio": true,
      "video": false,
    });
    _localStream = stream;
    localRenderer.srcObject = stream;
    if (state.isMuted) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = false;
      }
    }
  }

  Future<void> _ensurePeerConnection(String callId) async {
    if (_peerConnection != null && _peerCallId == callId) {
      return;
    }

    await _disposePeerConnection();
    _peerCallId = callId;
    _offerSent = false;
    _remoteDescriptionReady = false;
    _pendingCandidates.clear();

    final connection = await createPeerConnection(<String, dynamic>{
      "iceServers": <Map<String, dynamic>>[
        <String, dynamic>{
          "urls": <String>[
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302",
          ],
        },
      ],
      "sdpSemantics": "unified-plan",
    });

    connection.onIceCandidate = (candidate) {
      final activeCall = state.call;
      if (activeCall == null) return;
      final rawCandidate = candidate.candidate ?? "";
      if (rawCandidate.trim().isEmpty) return;
      _socket.emitCallSignal(
        callId: activeCall.id,
        signal: ChatCallSignalPayload(
          type: "candidate",
          sdp: "",
          candidate: rawCandidate,
          sdpMid: candidate.sdpMid ?? "",
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };

    connection.onTrack = (event) async {
      final streams = event.streams;
      if (streams.isEmpty) return;
      _remoteStream = streams.first;
      await _rendererReady;
      remoteRenderer.srcObject = _remoteStream;
      state = state.copyWith(
        phase: ChatCallPhase.active,
        connectionLabel: "Connected",
        clearError: true,
      );
    };

    connection.onConnectionState = (peerState) {
      final normalized = peerState.toString().split(".").last.toLowerCase();
      AppDebug.log(_logTag, _logPeer, extra: {"state": normalized});
      if (normalized.contains("connected")) {
        state = state.copyWith(
          phase: ChatCallPhase.active,
          connectionLabel: "Connected",
          clearError: true,
        );
        return;
      }
      if (normalized.contains("disconnected")) {
        state = state.copyWith(connectionLabel: "Reconnecting...");
        return;
      }
      if (normalized.contains("failed")) {
        state = state.copyWith(connectionLabel: "Connection failed");
      }
    };

    _peerConnection = connection;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }
  }

  void _applyCall(
    ChatCallSession call, {
    required ChatCallPhase phase,
    required String connectionLabel,
  }) {
    state = state.copyWith(
      call: call,
      phase: phase,
      connectionLabel: connectionLabel,
      clearError: true,
    );
  }

  void _armRingTimeout(ChatCallSession call) {
    _cancelRingTimeout();
    final timeoutAt = call.ringTimeoutAt;
    if (timeoutAt == null) return;
    final duration = timeoutAt.difference(DateTime.now());
    _ringTimeout = Timer(duration.isNegative ? Duration.zero : duration, () {
      if (state.call?.id != call.id || !(state.call?.isRinging ?? false)) {
        return;
      }
      unawaited(endCurrentCall(reason: "missed"));
    });
  }

  void _cancelRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = null;
  }

  Future<void> _autoDeclineBusy(String callId) async {
    final session = _session;
    if (session == null || !session.isTokenValid) {
      return;
    }
    try {
      await _api.declineCall(
        token: session.token,
        callId: callId,
        reason: "busy",
      );
    } catch (_) {
      // WHY: Best-effort busy handling should not interrupt the current call.
    }
  }

  Future<void> _finishCallLocally() async {
    _cancelRingTimeout();
    await _resetTransport();
    state = ChatCallState.initial();
  }

  Future<void> _resetTransport() async {
    await _disposePeerConnection();
    await _disposeStream(_localStream);
    await _disposeStream(_remoteStream);
    _localStream = null;
    _remoteStream = null;
    await _rendererReady;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _offerSent = false;
    _peerCallId = "";
    _remoteDescriptionReady = false;
    _pendingCandidates.clear();
  }

  Future<void> _disposePeerConnection() async {
    final connection = _peerConnection;
    _peerConnection = null;
    if (connection == null) return;
    try {
      await connection.close();
    } catch (_) {
      // WHY: Closing an already-closed peer connection is harmless.
    }
    await connection.dispose();
  }

  Future<void> _disposeStream(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {
        // WHY: Track stop errors should not block call teardown.
      }
    }
    try {
      await stream.dispose();
    } catch (_) {
      // WHY: Stream disposal is best-effort across plugin platforms.
    }
  }

  String _resolveCallError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data["error"] != null) {
        final message = data["error"].toString().trim();
        if (message.isNotEmpty) {
          return message;
        }
      }
      final message = error.message?.toString().trim() ?? "";
      if (message.isNotEmpty) {
        return message;
      }
    }

    final cleaned = error.toString().replaceFirst("Exception:", "").trim();
    if (cleaned.isEmpty) {
      return "Unable to complete the call action.";
    }
    return cleaned;
  }

  @override
  void dispose() {
    _disposed = true;
    _incomingSub?.cancel();
    _updateSub?.cancel();
    _endedSub?.cancel();
    _signalSub?.cancel();
    _cancelRingTimeout();
    unawaited(_disposePeerConnection());
    unawaited(_disposeStream(_localStream));
    unawaited(_disposeStream(_remoteStream));
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}

final chatCallProvider =
    StateNotifierProvider<ChatCallController, ChatCallState>((ref) {
      final controller = ChatCallController(ref: ref);
      ref.listen<AuthSession?>(
        authSessionProvider,
        (_, next) => controller.updateSession(next),
      );
      return controller;
    });
