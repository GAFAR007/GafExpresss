/// lib/app/features/home/presentation/chat_new_conversation_sheet.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Bottom sheet for creating a new staff chat conversation.
///
/// WHY:
/// - Lets business owners/staff start direct or group chats quickly.
/// - Keeps selection logic out of the inbox screen.
///
/// HOW:
/// - Loads staff list from productionStaffProvider.
/// - Sends createConversation via ChatApi.
/// - Returns the created conversation via callback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_constants.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

const String _logTag = "CHAT_NEW_SHEET";
const String _logBuild = "build()";
const String _logCreateTap = "create_tap";
const String _logCreateSuccess = "create_success";
const String _logCreateFail = "create_fail";
const String _logToggle = "group_toggle";
const String _logSelect = "staff_select";
const String _titleHint = "Group title";
const String _submitLabel = "Create chat";
const String _missingTitle = "Provide a group title.";
const String _missingSelection = "Select at least one staff member.";
const String _missingGroupSelection = "Select at least two staff members.";
const String _missingUserIdLabel = "Profile not linked";
const double _staffListHeight = 320;

class ChatNewConversationSheet extends ConsumerStatefulWidget {
  final void Function(ChatConversation conversation) onCreated;

  const ChatNewConversationSheet({super.key, required this.onCreated});

  @override
  ConsumerState<ChatNewConversationSheet> createState() =>
      _ChatNewConversationSheetState();
}

class _ChatNewConversationSheetState
    extends ConsumerState<ChatNewConversationSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  final Set<String> _selected = {};
  bool _isGroup = false;
  bool _isSubmitting = false;

  void _log(String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(_logTag, message, extra: extra);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String _displayName(BusinessStaffProfileSummary staff) {
    return staff.userName ?? staff.userEmail ?? staff.userPhone ?? "Staff";
  }

  void _toggleSelection(String userId, bool selected) {
    _log(_logSelect, extra: {"userId": userId, "selected": selected});
    setState(() {
      if (selected) {
        // WHY: Direct chats should only allow one selection.
        if (!_isGroup) {
          _selected
            ..clear()
            ..add(userId);
        } else {
          // WHY: Group chats allow multiple selections.
          _selected.add(userId);
        }
      } else {
        _selected.remove(userId);
      }
    });
  }

  Future<void> _createConversation() async {
    if (_isSubmitting) return;

    _log(_logCreateTap, extra: {"isGroup": _isGroup});

    if (_selected.isEmpty) {
      _showMessage(_missingSelection);
      return;
    }
    if (_isGroup && _selected.length < 2) {
      _showMessage(_missingGroupSelection);
      return;
    }
    if (_isGroup && _titleCtrl.text.trim().isEmpty) {
      _showMessage(_missingTitle);
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _showMessage("Session expired. Please sign in again.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(chatApiProvider);
      // WHY: Backend will enforce business scope + roles.
      final conversation = await api.createConversation(
        token: session.token,
        payload: {
          "type": _isGroup
              ? chatConversationTypeGroup
              : chatConversationTypeDirect,
          "title": _titleCtrl.text.trim(),
          "participantUserIds": _selected.toList(),
        },
      );

      _log(_logCreateSuccess, extra: {"id": conversation.id});
      // WHY: Hand the new conversation back to the inbox for navigation.
      widget.onCreated(conversation);
    } catch (error) {
      _log(_logCreateFail, extra: {"error": error.toString()});
      _showMessage("Unable to create chat. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    _log(_logBuild);
    final staffAsync = ref.watch(productionStaffProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text("New chat", style: theme.textTheme.titleMedium),
                const Spacer(),
                Switch(
                  value: _isGroup,
                  onChanged: (value) {
                    _log(_logToggle, extra: {"isGroup": value});
                    setState(() {
                      _isGroup = value;
                      if (!_isGroup && _selected.length > 1) {
                        _selected..removeWhere((id) => id != _selected.first);
                      }
                    });
                  },
                ),
                Text(
                  _isGroup ? "Group" : "Direct",
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            if (_isGroup) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: _titleHint),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: _staffListHeight,
              child: staffAsync.when(
                data: (staff) {
                  if (staff.isEmpty) {
                    return const Center(child: Text("No staff available"));
                  }
                  return ListView.separated(
                    itemCount: staff.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = staff[index];
                      // WHY: Conversations must target user ids, not staff ids.
                      final userId = entry.userId.trim();
                      final isSelectable = userId.isNotEmpty;
                      final isSelected = _selected.contains(userId);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: isSelectable
                            ? (value) =>
                                _toggleSelection(userId, value ?? false)
                            : null,
                        title: Text(_displayName(entry)),
                        subtitle: Text(
                          isSelectable ? entry.staffRole : _missingUserIdLabel,
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(
                    "Unable to load staff",
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _createConversation,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(_submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
