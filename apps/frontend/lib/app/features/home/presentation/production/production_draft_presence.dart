/// lib/app/features/home/presentation/production/production_draft_presence.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Live draft presence models, socket service, and Riverpod wiring.
///
/// WHY:
/// - Lets the production draft editor show who is currently viewing the plan.
/// - Keeps realtime viewer state out of the screen widget tree.
///
/// HOW:
/// - Connects to the backend Socket.IO server with the auth token.
/// - Joins a plan-specific room and listens for viewer snapshots.
/// - Exposes a typed viewer list that the UI can color-code by role.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:frontend/app/core/constants/app_constants.dart';
import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/auth/domain/models/auth_session.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

// WHY: Keep draft-presence event names aligned with the backend socket service.
const String draftPresenceEventJoin = "production:draft:presence:join";
const String draftPresenceEventLeave = "production:draft:presence:leave";
const String draftPresenceEventUpdate = "production:draft:presence:update";
const String draftPresenceEventError = "production:draft:presence:error";
const String draftPresenceRoomPrefix = "production:draft:";

// WHY: Keep logs easy to grep when presence rooms misbehave.
const String _logTag = "DRAFT_PRESENCE_SOCKET";
const String _logConnectStart = "connect_start";
const String _logConnectOk = "connect_ok";
const String _logConnectFail = "connect_fail";
const String _logDisconnect = "disconnect";
const String _logJoin = "join";
const String _logLeave = "leave";
const String _logUpdate = "update";
const String _logError = "error";

const Object _presenceCopySentinel = Object();

String normalizeDraftPresenceRoleKey(String rawRole) {
  return rawRole
      .trim()
      .toLowerCase()
      .replaceAll("-", "_")
      .replaceAll(RegExp(r"\s+"), "_");
}

String formatDraftPresenceRoleLabel(
  String rawRole, {
  String fallback = "Viewer",
}) {
  final normalized = normalizeDraftPresenceRoleKey(rawRole);
  if (normalized.isEmpty) {
    return fallback;
  }

  return normalized
      .split("_")
      .where((segment) => segment.trim().isNotEmpty)
      .map((segment) {
        final lower = segment.toLowerCase();
        return "${lower[0].toUpperCase()}${lower.substring(1)}";
      })
      .join(" ");
}

String formatDraftPresenceDurationLabel(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  if (safeSeconds == 0) {
    return "0s";
  }

  final duration = Duration(seconds: safeSeconds);
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  final remainingSeconds = duration.inSeconds.remainder(60);
  final parts = <String>[];

  if (days > 0) {
    parts.add("${days}d");
  }
  if (hours > 0 || parts.isNotEmpty) {
    parts.add("${hours}h");
  }
  if (minutes > 0 || parts.isNotEmpty) {
    parts.add("${minutes}m");
  }
  if (parts.isEmpty || remainingSeconds > 0) {
    parts.add("${remainingSeconds}s");
  }

  return parts.join(" ");
}

String draftPresenceRoomIdForPlanId(String planId) {
  final normalizedPlanId = planId.trim();
  if (normalizedPlanId.isEmpty) {
    return "";
  }
  return "$draftPresenceRoomPrefix$normalizedPlanId";
}

class ProductionDraftPresenceViewer {
  final String userId;
  final String displayName;
  final String email;
  final String accountRole;
  final String? staffRole;
  final DateTime? enteredAt;
  final DateTime? lastSeenAt;
  final DateTime? leftAt;
  final int activeSocketCount;
  final int currentSessionSeconds;
  final int durationSeconds;
  final int todaySeconds;
  final int weekSeconds;
  final int monthSeconds;
  final int yearSeconds;
  final int totalSeconds;
  final int sessionCount;

  const ProductionDraftPresenceViewer({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.accountRole,
    required this.staffRole,
    required this.enteredAt,
    required this.lastSeenAt,
    required this.leftAt,
    required this.activeSocketCount,
    required this.currentSessionSeconds,
    required this.durationSeconds,
    required this.todaySeconds,
    required this.weekSeconds,
    required this.monthSeconds,
    required this.yearSeconds,
    required this.totalSeconds,
    required this.sessionCount,
  });

  String get resolvedDisplayName {
    final name = displayName.trim();
    if (name.isNotEmpty) {
      return name;
    }

    final mail = email.trim();
    if (mail.isNotEmpty) {
      return mail;
    }

    final id = userId.trim();
    return id.isNotEmpty ? id : "Unknown viewer";
  }

  String get roleKey {
    final normalizedAccountRole = normalizeDraftPresenceRoleKey(accountRole);
    final normalizedStaffRole = normalizeDraftPresenceRoleKey(staffRole ?? "");
    if (normalizedAccountRole == "staff" && normalizedStaffRole.isNotEmpty) {
      return normalizedStaffRole;
    }
    return normalizedAccountRole;
  }

  String get roleLabel {
    return formatDraftPresenceRoleLabel(roleKey);
  }

  bool get hasPresenceMetrics {
    return enteredAt != null ||
        currentSessionSeconds > 0 ||
        todaySeconds > 0 ||
        weekSeconds > 0 ||
        monthSeconds > 0 ||
        yearSeconds > 0 ||
        totalSeconds > 0 ||
        sessionCount > 0;
  }

  String get enteredAtLabel {
    return formatDateTimeLabel(enteredAt, fallback: "");
  }

  String get currentSessionDurationLabel {
    return formatDraftPresenceDurationLabel(currentSessionSeconds);
  }

  String get todayDurationLabel {
    return formatDraftPresenceDurationLabel(todaySeconds);
  }

  String get weekDurationLabel {
    return formatDraftPresenceDurationLabel(weekSeconds);
  }

  String get monthDurationLabel {
    return formatDraftPresenceDurationLabel(monthSeconds);
  }

  String get yearDurationLabel {
    return formatDraftPresenceDurationLabel(yearSeconds);
  }

  int _liveElapsedSinceSnapshotSeconds({
    required DateTime referenceTime,
    DateTime? snapshotAt,
  }) {
    final effectiveSnapshot = snapshotAt ?? referenceTime;
    final deltaSeconds = referenceTime.difference(effectiveSnapshot).inSeconds;
    return deltaSeconds < 0 ? 0 : deltaSeconds;
  }

  int liveCurrentSessionSeconds({
    required DateTime referenceTime,
    DateTime? snapshotAt,
  }) {
    if (leftAt != null || enteredAt == null) {
      return currentSessionSeconds;
    }

    return currentSessionSeconds +
        _liveElapsedSinceSnapshotSeconds(
          referenceTime: referenceTime,
          snapshotAt: snapshotAt,
        );
  }

  int liveTodaySeconds({
    required DateTime referenceTime,
    DateTime? snapshotAt,
  }) {
    if (leftAt != null || enteredAt == null) {
      return todaySeconds;
    }

    return todaySeconds +
        _liveElapsedSinceSnapshotSeconds(
          referenceTime: referenceTime,
          snapshotAt: snapshotAt,
        );
  }

  int liveMonthSeconds({
    required DateTime referenceTime,
    DateTime? snapshotAt,
  }) {
    if (leftAt != null || enteredAt == null) {
      return monthSeconds;
    }

    return monthSeconds +
        _liveElapsedSinceSnapshotSeconds(
          referenceTime: referenceTime,
          snapshotAt: snapshotAt,
        );
  }

  int liveWeekSeconds({required DateTime referenceTime, DateTime? snapshotAt}) {
    if (leftAt != null || enteredAt == null) {
      return weekSeconds;
    }

    return weekSeconds +
        _liveElapsedSinceSnapshotSeconds(
          referenceTime: referenceTime,
          snapshotAt: snapshotAt,
        );
  }

  int liveYearSeconds({required DateTime referenceTime, DateTime? snapshotAt}) {
    if (leftAt != null || enteredAt == null) {
      return yearSeconds;
    }

    return yearSeconds +
        _liveElapsedSinceSnapshotSeconds(
          referenceTime: referenceTime,
          snapshotAt: snapshotAt,
        );
  }

  String presenceSummaryLabel({
    required DateTime referenceTime,
    DateTime? snapshotAt,
  }) {
    final enteredLabel = enteredAtLabel;
    if (enteredLabel.isEmpty && !hasPresenceMetrics) {
      return "";
    }

    final liveCurrentSeconds = liveCurrentSessionSeconds(
      referenceTime: referenceTime,
      snapshotAt: snapshotAt,
    );
    final liveTodaySecondsValue = liveTodaySeconds(
      referenceTime: referenceTime,
      snapshotAt: snapshotAt,
    );
    final liveWeekSecondsValue = liveWeekSeconds(
      referenceTime: referenceTime,
      snapshotAt: snapshotAt,
    );
    final liveMonthSecondsValue = liveMonthSeconds(
      referenceTime: referenceTime,
      snapshotAt: snapshotAt,
    );
    final liveYearSecondsValue = liveYearSeconds(
      referenceTime: referenceTime,
      snapshotAt: snapshotAt,
    );
    final lines = <String>[];

    if (enteredLabel.isNotEmpty) {
      lines.add("Entered $enteredLabel");
    }
    lines.add(
      [
        "Current ${formatDraftPresenceDurationLabel(liveCurrentSeconds)}",
        "Today ${formatDraftPresenceDurationLabel(liveTodaySecondsValue)}",
        "Week ${formatDraftPresenceDurationLabel(liveWeekSecondsValue)}",
        "Month ${formatDraftPresenceDurationLabel(liveMonthSecondsValue)}",
        "Year ${formatDraftPresenceDurationLabel(liveYearSecondsValue)}",
      ].join(" · "),
    );
    return lines.join("\n");
  }

  factory ProductionDraftPresenceViewer.fromJson(Map<String, dynamic> json) {
    return ProductionDraftPresenceViewer(
      userId: (json["userId"] ?? json["id"] ?? "").toString(),
      displayName: (json["displayName"] ?? json["name"] ?? "").toString(),
      email: (json["email"] ?? "").toString(),
      accountRole: normalizeDraftPresenceRoleKey(
        (json["accountRole"] ?? json["role"] ?? "").toString(),
      ),
      staffRole: _nullIfBlank(json["staffRole"]),
      enteredAt: _parseDateTime(json["enteredAt"]),
      lastSeenAt: _parseDateTime(json["lastSeenAt"]),
      leftAt: _parseDateTime(json["leftAt"]),
      activeSocketCount: _parseNonNegativeInt(json["activeSocketCount"]),
      currentSessionSeconds: _parseNonNegativeInt(
        json["currentSessionSeconds"],
      ),
      durationSeconds: _parseNonNegativeInt(json["durationSeconds"]),
      todaySeconds: _parseNonNegativeInt(json["todaySeconds"]),
      weekSeconds: _parseNonNegativeInt(json["weekSeconds"]),
      monthSeconds: _parseNonNegativeInt(json["monthSeconds"]),
      yearSeconds: _parseNonNegativeInt(json["yearSeconds"]),
      totalSeconds: _parseNonNegativeInt(json["totalSeconds"]),
      sessionCount: _parseNonNegativeInt(json["sessionCount"]),
    );
  }
}

class ProductionDraftPresenceState {
  final String planId;
  final List<ProductionDraftPresenceViewer> viewers;
  final bool isConnected;
  final String? error;
  final DateTime? updatedAt;

  const ProductionDraftPresenceState({
    required this.planId,
    required this.viewers,
    required this.isConnected,
    required this.error,
    required this.updatedAt,
  });

  factory ProductionDraftPresenceState.initial({String planId = ""}) {
    return ProductionDraftPresenceState(
      planId: planId,
      viewers: const <ProductionDraftPresenceViewer>[],
      isConnected: false,
      error: null,
      updatedAt: null,
    );
  }

  factory ProductionDraftPresenceState.fromJson(Map<String, dynamic> json) {
    final viewerList = (json["viewers"] ?? []) as List<dynamic>;
    return ProductionDraftPresenceState(
      planId: (json["planId"] ?? "").toString(),
      viewers: viewerList
          .whereType<Map<String, dynamic>>()
          .map(ProductionDraftPresenceViewer.fromJson)
          .toList(),
      isConnected: true,
      error: null,
      updatedAt: DateTime.tryParse((json["updatedAt"] ?? "").toString()),
    );
  }

  ProductionDraftPresenceState copyWith({
    String? planId,
    List<ProductionDraftPresenceViewer>? viewers,
    bool? isConnected,
    Object? error = _presenceCopySentinel,
    DateTime? updatedAt,
  }) {
    return ProductionDraftPresenceState(
      planId: planId ?? this.planId,
      viewers: viewers ?? this.viewers,
      isConnected: isConnected ?? this.isConnected,
      error: identical(error, _presenceCopySentinel)
          ? this.error
          : error as String?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ProductionDraftPresenceSocketService {
  io.Socket? _socket;
  String? _token;
  final Set<String> _trackedPlanIds = <String>{};
  final StreamController<ProductionDraftPresenceState> _stateController =
      StreamController<ProductionDraftPresenceState>.broadcast();
  ProductionDraftPresenceState _state = ProductionDraftPresenceState.initial();

  Stream<ProductionDraftPresenceState> get stateStream =>
      _stateController.stream;

  ProductionDraftPresenceState get currentState => _state;

  bool get isConnected => _socket?.connected ?? false;

  void connect({required String token}) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return;
    }

    if (_socket != null && _token == normalizedToken) {
      if (isConnected) {
        _rejoinTrackedPlans();
        return;
      }
      _socket?.connect();
      return;
    }

    final tokenChanged = _token != null && _token != normalizedToken;
    _disposeSocket(clearTrackedPlans: tokenChanged);
    _token = normalizedToken;

    AppDebug.log(_logTag, _logConnectStart);

    _socket = io.io(
      AppConstants.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({"token": "Bearer $normalizedToken"})
          .enableForceNew()
          .build(),
    );

    _socket?.onConnect((_) {
      AppDebug.log(_logTag, _logConnectOk);
      _emitState(_state.copyWith(isConnected: true, error: null));
      _rejoinTrackedPlans();
    });

    _socket?.onDisconnect((_) {
      AppDebug.log(_logTag, _logDisconnect);
      _emitState(_state.copyWith(isConnected: false));
    });

    _socket?.onConnectError((error) {
      AppDebug.log(
        _logTag,
        _logConnectFail,
        extra: {"error": error.toString()},
      );
      _emitState(_state.copyWith(isConnected: false, error: error.toString()));
    });

    _socket?.on(draftPresenceEventUpdate, (payload) {
      AppDebug.log(_logTag, _logUpdate);
      if (payload is! Map) {
        return;
      }

      final map = Map<String, dynamic>.from(payload);
      final nextState = ProductionDraftPresenceState.fromJson(map);
      _emitState(nextState.copyWith(isConnected: true, error: null));
    });

    _socket?.on(draftPresenceEventError, (payload) {
      AppDebug.log(_logTag, _logError, extra: {"payload": payload.toString()});
      _emitState(
        _state.copyWith(
          isConnected: false,
          error: payload?.toString() ?? "Draft presence error",
        ),
      );
    });

    _socket?.connect();
  }

  void joinPlan(String planId) {
    final normalizedPlanId = planId.trim();
    if (normalizedPlanId.isEmpty) {
      return;
    }

    final currentCount = _trackedPlanIds.contains(normalizedPlanId) ? 1 : 0;
    _trackedPlanIds.add(normalizedPlanId);

    if (currentCount > 0) {
      if (!isConnected) {
        _socket?.connect();
      }
      return;
    }

    AppDebug.log(_logTag, _logJoin, extra: {"planId": normalizedPlanId});

    if (isConnected) {
      _emitJoin(normalizedPlanId);
      return;
    }

    _socket?.connect();
  }

  void leavePlan(String planId) {
    final normalizedPlanId = planId.trim();
    if (normalizedPlanId.isEmpty) {
      return;
    }

    final wasTracked = _trackedPlanIds.remove(normalizedPlanId);
    if (!wasTracked) {
      return;
    }

    AppDebug.log(_logTag, _logLeave, extra: {"planId": normalizedPlanId});

    if (isConnected) {
      _socket?.emit(draftPresenceEventLeave, {"planId": normalizedPlanId});
    }

    if (_trackedPlanIds.isEmpty) {
      _emitState(ProductionDraftPresenceState.initial());
      _socket?.disconnect();
    }
  }

  void _rejoinTrackedPlans() {
    if (!isConnected) {
      return;
    }

    for (final planId in _trackedPlanIds) {
      _emitJoin(planId);
    }
  }

  void _emitJoin(String planId) {
    _socket?.emit(draftPresenceEventJoin, {"planId": planId});
  }

  void _emitState(ProductionDraftPresenceState nextState) {
    _state = nextState;
    if (_stateController.isClosed) {
      return;
    }
    _stateController.add(nextState);
  }

  void _disposeSocket({required bool clearTrackedPlans}) {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    if (clearTrackedPlans) {
      _trackedPlanIds.clear();
      _emitState(ProductionDraftPresenceState.initial());
    }
  }

  void dispose() {
    _disposeSocket(clearTrackedPlans: true);
    _stateController.close();
  }
}

class ProductionDraftPresenceController
    extends StateNotifier<ProductionDraftPresenceState> {
  final ProductionDraftPresenceSocketService _service;
  final String planId;
  StreamSubscription<ProductionDraftPresenceState>? _subscription;

  ProductionDraftPresenceController({
    required ProductionDraftPresenceSocketService service,
    required AuthSession? session,
    required this.planId,
  }) : _service = service,
       super(ProductionDraftPresenceState.initial(planId: planId)) {
    _subscription = _service.stateStream.listen((nextState) {
      state = nextState;
    });

    _syncSession(session);
  }

  void _syncSession(AuthSession? session) {
    final normalizedPlanId = planId.trim();
    if (normalizedPlanId.isEmpty || session == null || !session.isTokenValid) {
      _service.leavePlan(planId);
      state = ProductionDraftPresenceState.initial(planId: planId);
      return;
    }

    _service.connect(token: session.token);
    _service.joinPlan(normalizedPlanId);
  }

  @override
  void dispose() {
    _service.leavePlan(planId);
    _subscription?.cancel();
    super.dispose();
  }
}

final productionDraftPresenceSocketProvider =
    Provider<ProductionDraftPresenceSocketService>((ref) {
      final service = ProductionDraftPresenceSocketService();
      ref.onDispose(service.dispose);
      return service;
    });

final productionDraftPresenceProvider = StateNotifierProvider.autoDispose
    .family<
      ProductionDraftPresenceController,
      ProductionDraftPresenceState,
      String
    >((ref, planId) {
      final session = ref.watch(authSessionProvider);
      final service = ref.watch(productionDraftPresenceSocketProvider);
      return ProductionDraftPresenceController(
        service: service,
        session: session,
        planId: planId,
      );
    });

String? _nullIfBlank(dynamic value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _parseDateTime(dynamic value) {
  final text = _nullIfBlank(value);
  if (text == null) {
    return null;
  }
  return DateTime.tryParse(text);
}

int _parseNonNegativeInt(dynamic value) {
  if (value == null) {
    return 0;
  }
  final parsed = int.tryParse(value.toString());
  if (parsed == null || parsed < 0) {
    return 0;
  }
  return parsed;
}
