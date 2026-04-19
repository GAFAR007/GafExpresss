/// lib/app/features/home/presentation/chat_call_overlay.dart
/// ---------------------------------------------------------
/// WHAT:
/// - Full-screen in-app overlay for incoming, outgoing, and active calls.
///
/// WHY:
/// - The call UI must stay visible across routes while a call is in progress.
///
/// HOW:
/// - Watches the global chatCallProvider and renders above the router child.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:frontend/app/features/home/presentation/chat_call_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class ChatCallOverlayHost extends ConsumerWidget {
  const ChatCallOverlayHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatCallProvider);
    final session = ref.watch(authSessionProvider);
    final call = state.call;

    if (call == null || session == null || !session.isTokenValid) {
      return const SizedBox.shrink();
    }

    final controller = ref.read(chatCallProvider.notifier);
    final currentUserId = session.user.id;
    final peerName = call.peerNameFor(currentUserId);
    final peerAvatar = call.peerProfileImageUrlFor(currentUserId);
    final isIncoming = call.isRinging && call.isIncomingFor(currentUserId);

    String subtitle;
    switch (state.phase) {
      case ChatCallPhase.incoming:
        subtitle = "Incoming voice call";
        break;
      case ChatCallPhase.outgoing:
        subtitle = "Calling...";
        break;
      case ChatCallPhase.connecting:
        subtitle = state.connectionLabel.trim().isEmpty
            ? "Connecting..."
            : state.connectionLabel.trim();
        break;
      case ChatCallPhase.active:
        subtitle = "Voice call in progress";
        break;
      case ChatCallPhase.idle:
        subtitle = "";
        break;
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.64),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 28,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 42,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              backgroundImage: peerAvatar.trim().isNotEmpty
                                  ? NetworkImage(peerAvatar)
                                  : null,
                              child: peerAvatar.trim().isEmpty
                                  ? Text(
                                      peerName.trim().isEmpty
                                          ? "?"
                                          : peerName.trim()[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              peerName.trim().isEmpty ? "Voice call" : peerName,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                            ),
                            if (state.phase == ChatCallPhase.active &&
                                call.answeredAt != null) ...[
                              const SizedBox(height: 8),
                              _CallDurationLabel(startedAt: call.answeredAt!),
                            ] else if (state.connectionLabel
                                    .trim()
                                    .isNotEmpty &&
                                state.phase == ChatCallPhase.connecting) ...[
                              const SizedBox(height: 8),
                              Text(
                                state.connectionLabel.trim(),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                            if (state.errorMessage?.trim().isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 14),
                              Text(
                                state.errorMessage!.trim(),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFFFD7D2),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            if (state.phase == ChatCallPhase.incoming)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        controller.declineIncomingCall();
                                      },
                                      icon: const Icon(Icons.call_end_rounded),
                                      label: const Text("Decline"),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.34,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        controller.acceptIncomingCall();
                                      },
                                      icon: const Icon(Icons.call_rounded),
                                      label: const Text("Accept"),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF2F9961,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _OverlayActionButton(
                                    icon: state.isMuted
                                        ? Icons.mic_off_rounded
                                        : Icons.mic_rounded,
                                    label: state.isMuted ? "Unmute" : "Mute",
                                    onPressed: () {
                                      controller.toggleMute();
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  _OverlayActionButton(
                                    icon: Icons.call_end_rounded,
                                    label: isIncoming ? "Decline" : "End",
                                    danger: true,
                                    onPressed: () {
                                      controller.endCurrentCall();
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.001,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: RTCVideoView(controller.remoteRenderer),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 2,
              top: 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.001,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: RTCVideoView(controller.localRenderer),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onPressed;

  const _OverlayActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? const Color(0xFFD85A4E)
        : Colors.white.withValues(alpha: 0.18);

    return Expanded(
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _CallDurationLabel extends StatefulWidget {
  final DateTime startedAt;

  const _CallDurationLabel({required this.startedAt});

  @override
  State<_CallDurationLabel> createState() => _CallDurationLabelState();
}

class _CallDurationLabelState extends State<_CallDurationLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = DateTime.now()
        .difference(widget.startedAt)
        .inSeconds
        .clamp(0, 86400);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    final hours = minutes ~/ 60;
    final minutePart = minutes % 60;
    final label = hours > 0
        ? "${hours.toString().padLeft(2, "0")}:${minutePart.toString().padLeft(2, "0")}:${remainder.toString().padLeft(2, "0")}"
        : "${minutePart.toString().padLeft(2, "0")}:${remainder.toString().padLeft(2, "0")}";

    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Colors.white.withValues(alpha: 0.74),
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}
