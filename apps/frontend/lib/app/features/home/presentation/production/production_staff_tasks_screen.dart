/// lib/app/features/home/presentation/production/production_staff_tasks_screen.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Shows production tasks assigned to the signed-in staff member.
///
/// WHY:
/// - Staff need a direct task list with clock-in and clock-out controls without
///   opening the full production workspace.
///
/// HOW:
/// - Reuses production list/detail providers to find assigned tasks.
/// - Reuses staff attendance actions for clock-in/out side effects.
/// - Refreshes affected production detail providers after attendance changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_proof_flow.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_providers.dart';

const String _logTag = "PRODUCTION_STAFF_TASKS";
const String _buildMessage = "build()";
const String _fetchStart = "staff_task_list_fetch_start";
const String _fetchPlanFailed = "staff_task_plan_fetch_failed";
const String _refreshAction = "refresh_staff_tasks";
const String _clockInAction = "clock_in_task";
const String _clockOutAction = "clock_out_task";
const String _openTaskAction = "open_task_detail";
const String _screenTitle = "Staff tasks";
const String _emptyProfileTitle = "No staff profile linked";
const String _emptyProfileMessage =
    "This account is not linked to a production staff profile yet.";
const String _emptyTasksTitle = "No assigned production tasks";
const String _emptyTasksMessage =
    "Tasks assigned to your staff profile will show here.";
const String _clockInLabel = "Clock in";
const String _clockOutLabel = "Clock out";
const String _refreshTooltip = "Refresh";
const String _openTaskTooltip = "Open task";
const String _clockInSuccess = "Clocked in.";
const String _clockOutSuccess = "Clocked out.";
const String _clockInFailure = "Unable to clock in.";
const String _clockOutFailure = "Unable to clock out.";
const String _assignedToLabel = "Assigned to";
const String _todayLabel = "Today";
const String _planLabel = "Plan";
const String _phaseLabel = "Phase";
const String _dueLabel = "Due";
const String _statusLabel = "Status";
const String _openSinceLabel = "Open since";
const String _proofsLabel = "Proofs";
const String _taskFallbackTitle = "Production task";
const String _phaseFallbackLabel = "Unassigned phase";
const String _planStatusArchived = "archived";
const String _taskStatusCompleted = "completed";
const String _extraPlanIdKey = "planId";
const String _extraTaskIdKey = "taskId";
const String _extraStaffIdKey = "staffId";
const double _pagePadding = 16;
const double _cardSpacing = 12;
const double _cardRadius = 16;
const double _cardPadding = 16;
const double _rowGap = 8;

final _productionStaffTaskListProvider =
    FutureProvider.autoDispose<_ProductionStaffTaskList>((ref) async {
      AppDebug.log(_logTag, _fetchStart);
      final session = ref.watch(authSessionProvider);
      final profile = await ref
          .watch(userProfileProvider.future)
          .catchError((_) => null);
      final userId = (profile?.id ?? session?.user.id ?? "").trim();
      final userEmail = (profile?.email ?? session?.user.email ?? "")
          .trim()
          .toLowerCase();
      final staffList = await ref.watch(productionStaffProvider.future);
      final selfStaff = _resolveSelfStaffProfile(
        staffList: staffList,
        userId: userId,
        userEmail: userEmail,
      );

      if (selfStaff == null) {
        return const _ProductionStaffTaskList(
          staffProfile: null,
          tasks: <_ProductionStaffTaskSummary>[],
          planIds: <String>[],
          failedPlanCount: 0,
        );
      }

      final plans = await ref.watch(productionPlansProvider.future);
      final activePlans = plans
          .where((plan) => !_isArchivedPlan(plan.status))
          .toList();
      final tasks = <_ProductionStaffTaskSummary>[];
      final planIds = <String>{};
      var failedPlanCount = 0;
      final today = _calendarDay(DateTime.now());

      for (final plan in activePlans) {
        try {
          final detail = await ref.watch(
            productionPlanDetailProvider(plan.id).future,
          );
          planIds.add(plan.id);
          final phaseById = {
            for (final phase in detail.phases) phase.id: phase,
          };
          for (final task in detail.tasks) {
            if (!_isTaskAssignedToStaff(task, selfStaff.id)) {
              continue;
            }
            final attendance = _resolveTaskAttendance(
              records: detail.attendanceRecords,
              staffProfileId: selfStaff.id,
              taskId: task.id,
              workDate: today,
            );
            tasks.add(
              _ProductionStaffTaskSummary(
                plan: detail.plan,
                task: task,
                phase: phaseById[task.phaseId],
                staffProfile: selfStaff,
                openAttendance: attendance.openRecord,
                todaysRecordCount: attendance.todaysRecordCount,
                uploadedProofCount: attendance.uploadedProofCount,
                requiredProofCount: attendance.requiredProofCount,
              ),
            );
          }
        } catch (error) {
          failedPlanCount += 1;
          AppDebug.log(
            _logTag,
            _fetchPlanFailed,
            extra: {_extraPlanIdKey: plan.id, "error": error.toString()},
          );
        }
      }

      tasks.sort(_compareStaffTasks);
      return _ProductionStaffTaskList(
        staffProfile: selfStaff,
        tasks: tasks,
        planIds: planIds.toList(growable: false),
        failedPlanCount: failedPlanCount,
      );
    });

class ProductionStaffTasksScreen extends ConsumerStatefulWidget {
  const ProductionStaffTasksScreen({super.key});

  @override
  ConsumerState<ProductionStaffTasksScreen> createState() =>
      _ProductionStaffTasksScreenState();
}

class _ProductionStaffTasksScreenState
    extends ConsumerState<ProductionStaffTasksScreen> {
  String? _busyTaskId;

  Future<void> _refresh() async {
    AppDebug.log(_logTag, _refreshAction);
    final current = ref.read(_productionStaffTaskListProvider).valueOrNull;
    for (final planId in current?.planIds ?? const <String>[]) {
      ref.invalidate(productionPlanDetailProvider(planId));
    }
    ref.invalidate(productionPlansProvider);
    ref.invalidate(productionStaffProvider);
    final _ = await ref.refresh(_productionStaffTaskListProvider.future);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _invalidateTask(_ProductionStaffTaskSummary summary) {
    ref.invalidate(productionPlanDetailProvider(summary.plan.id));
    ref.invalidate(_productionStaffTaskListProvider);
  }

  Future<void> _clockIn(_ProductionStaffTaskSummary summary) async {
    if (_busyTaskId != null || summary.isCompleted) {
      return;
    }
    setState(() {
      _busyTaskId = summary.task.id;
    });
    AppDebug.log(
      _logTag,
      _clockInAction,
      extra: {
        _extraPlanIdKey: summary.plan.id,
        _extraTaskIdKey: summary.task.id,
        _extraStaffIdKey: summary.staffProfile.id,
      },
    );

    try {
      final now = DateTime.now();
      await StaffAttendanceActions(ref).clockIn(
        staffProfileId: summary.staffProfile.id,
        clockInAt: now,
        workDate: _calendarDay(now),
        planId: summary.plan.id,
        taskId: summary.task.id,
        notes: "Clocked in from staff production task list",
      );
      _invalidateTask(summary);
      if (mounted) {
        _showSnack(_clockInSuccess);
      }
    } catch (error) {
      if (mounted) {
        _showSnack(_resolveErrorMessage(error, fallback: _clockInFailure));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyTaskId = null;
        });
      }
    }
  }

  Future<void> _clockOut(_ProductionStaffTaskSummary summary) async {
    final openAttendance = summary.openAttendance;
    if (_busyTaskId != null || openAttendance == null) {
      return;
    }
    setState(() {
      _busyTaskId = summary.task.id;
    });
    AppDebug.log(
      _logTag,
      _clockOutAction,
      extra: {
        _extraPlanIdKey: summary.plan.id,
        _extraTaskIdKey: summary.task.id,
        _extraStaffIdKey: summary.staffProfile.id,
      },
    );

    try {
      final workDate = openAttendance.workDate ?? _calendarDay(DateTime.now());
      final attendance = await StaffAttendanceActions(ref).clockOut(
        staffProfileId: summary.staffProfile.id,
        attendanceId: openAttendance.id,
        clockOutAt: DateTime.now(),
        workDate: workDate,
        planId: summary.plan.id,
        taskId: summary.task.id,
        notes: "Clocked out from staff production task list",
      );
      if (!mounted || !context.mounted) {
        return;
      }
      final attendanceWithProof = await requireAttendanceProofUpload(
        context: context,
        ref: ref,
        attendance: attendance,
        subjectLabel: _staffDisplayName(summary.staffProfile),
        taskLabel: summary.taskTitle,
      );
      AppDebug.log(
        _logTag,
        "clock_out_proof_status",
        extra: {
          _extraTaskIdKey: summary.task.id,
          "proofStatus": attendanceWithProof.proofStatus,
        },
      );
      _invalidateTask(summary);
      if (mounted) {
        _showSnack(_clockOutSuccess);
      }
    } catch (error) {
      if (mounted) {
        _showSnack(_resolveErrorMessage(error, fallback: _clockOutFailure));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyTaskId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _buildMessage);
    final taskListAsync = ref.watch(_productionStaffTaskListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: _refreshTooltip,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: taskListAsync.when(
          data: (taskList) {
            if (taskList.staffProfile == null) {
              return const _MessageList(
                icon: Icons.badge_outlined,
                title: _emptyProfileTitle,
                message: _emptyProfileMessage,
              );
            }
            if (taskList.tasks.isEmpty) {
              return _MessageList(
                icon: Icons.assignment_outlined,
                title: _emptyTasksTitle,
                message: taskList.failedPlanCount > 0
                    ? "$_emptyTasksMessage Some plans could not be checked."
                    : _emptyTasksMessage,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(_pagePadding),
              itemCount: taskList.tasks.length + 1,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: _cardSpacing),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _StaffSummaryHeader(
                    staffProfile: taskList.staffProfile!,
                    taskCount: taskList.tasks.length,
                    failedPlanCount: taskList.failedPlanCount,
                  );
                }
                final summary = taskList.tasks[index - 1];
                return _StaffTaskCard(
                  summary: summary,
                  busy: _busyTaskId == summary.task.id,
                  anyBusy: _busyTaskId != null,
                  onClockIn: () => _clockIn(summary),
                  onClockOut: () => _clockOut(summary),
                  onOpenTask: () {
                    AppDebug.log(
                      _logTag,
                      _openTaskAction,
                      extra: {
                        _extraPlanIdKey: summary.plan.id,
                        _extraTaskIdKey: summary.task.id,
                      },
                    );
                    context.push(
                      productionPlanTaskDetailPath(
                        planId: summary.plan.id,
                        taskId: summary.task.id,
                      ),
                    );
                  },
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _MessageList(
            icon: Icons.error_outline,
            title: "Unable to load staff tasks",
            message: _resolveErrorMessage(error, fallback: error.toString()),
          ),
        ),
      ),
    );
  }
}

class _StaffSummaryHeader extends StatelessWidget {
  final BusinessStaffProfileSummary staffProfile;
  final int taskCount;
  final int failedPlanCount;

  const _StaffSummaryHeader({
    required this.staffProfile,
    required this.taskCount,
    required this.failedPlanCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: const Icon(Icons.badge_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$_assignedToLabel ${_staffDisplayName(staffProfile)}",
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$taskCount tasks • ${staffProfile.staffRole}",
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (failedPlanCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    "$failedPlanCount plans could not be checked.",
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffTaskCard extends StatelessWidget {
  final _ProductionStaffTaskSummary summary;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;
  final VoidCallback onOpenTask;

  const _StaffTaskCard({
    required this.summary,
    required this.busy,
    required this.anyBusy,
    required this.onClockIn,
    required this.onClockOut,
    required this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canClockIn =
        !anyBusy && !summary.hasOpenAttendance && !summary.isCompleted;
    final canClockOut = !anyBusy && summary.hasOpenAttendance;

    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.taskTitle,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$_planLabel: ${summary.plan.title}",
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onOpenTask,
                icon: const Icon(Icons.open_in_new),
                tooltip: _openTaskTooltip,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: _rowGap,
            runSpacing: _rowGap,
            children: [
              _InfoChip(
                icon: Icons.layers_outlined,
                label: "$_phaseLabel: ${summary.phaseName}",
              ),
              _InfoChip(
                icon: Icons.flag_outlined,
                label: "$_statusLabel: ${summary.task.status}",
              ),
              _InfoChip(
                icon: Icons.event_outlined,
                label: "$_dueLabel: ${formatDateLabel(summary.task.dueDate)}",
              ),
              if (summary.hasOpenAttendance)
                _InfoChip(
                  icon: Icons.timer_outlined,
                  label:
                      "$_openSinceLabel: ${_formatTime(summary.openAttendance?.clockInAt)}",
                )
              else if (summary.todaysRecordCount > 0)
                _InfoChip(
                  icon: Icons.check_circle_outline,
                  label: "$_todayLabel: ${summary.todaysRecordCount}",
                ),
              if (summary.requiredProofCount > 0)
                _InfoChip(
                  icon: Icons.attachment_outlined,
                  label:
                      "$_proofsLabel: ${summary.uploadedProofCount}/${summary.requiredProofCount}",
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canClockIn ? onClockIn : null,
                  icon: busy && !summary.hasOpenAttendance
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text(_clockInLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canClockOut ? onClockOut : null,
                  icon: busy && summary.hasOpenAttendance
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          summary.hasOpenAttendance
                              ? Icons.logout
                              : Icons.task_alt,
                        ),
                  label: const Text(_clockOutLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageList({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(_pagePadding),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, size: 36, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductionStaffTaskList {
  final BusinessStaffProfileSummary? staffProfile;
  final List<_ProductionStaffTaskSummary> tasks;
  final List<String> planIds;
  final int failedPlanCount;

  const _ProductionStaffTaskList({
    required this.staffProfile,
    required this.tasks,
    required this.planIds,
    required this.failedPlanCount,
  });
}

class _ProductionStaffTaskSummary {
  final ProductionPlan plan;
  final ProductionTask task;
  final ProductionPhase? phase;
  final BusinessStaffProfileSummary staffProfile;
  final ProductionAttendanceRecord? openAttendance;
  final int todaysRecordCount;
  final int uploadedProofCount;
  final int requiredProofCount;

  const _ProductionStaffTaskSummary({
    required this.plan,
    required this.task,
    required this.phase,
    required this.staffProfile,
    required this.openAttendance,
    required this.todaysRecordCount,
    required this.uploadedProofCount,
    required this.requiredProofCount,
  });

  bool get hasOpenAttendance => openAttendance != null;

  bool get isCompleted =>
      task.status.trim().toLowerCase() == _taskStatusCompleted;

  String get taskTitle {
    final title = task.title.trim();
    return title.isEmpty ? _taskFallbackTitle : title;
  }

  String get phaseName {
    final name = phase?.name.trim() ?? "";
    return name.isEmpty ? _phaseFallbackLabel : name;
  }
}

class _TaskAttendanceState {
  final ProductionAttendanceRecord? openRecord;
  final int todaysRecordCount;
  final int uploadedProofCount;
  final int requiredProofCount;

  const _TaskAttendanceState({
    required this.openRecord,
    required this.todaysRecordCount,
    required this.uploadedProofCount,
    required this.requiredProofCount,
  });
}

BusinessStaffProfileSummary? _resolveSelfStaffProfile({
  required List<BusinessStaffProfileSummary> staffList,
  required String userId,
  required String userEmail,
}) {
  if (userId.isNotEmpty) {
    for (final profile in staffList) {
      if (profile.userId.trim() == userId) {
        return profile;
      }
    }
  }
  if (userEmail.isEmpty) {
    return null;
  }
  for (final profile in staffList) {
    final profileEmail = (profile.userEmail ?? "").trim().toLowerCase();
    if (profileEmail.isNotEmpty && profileEmail == userEmail) {
      return profile;
    }
  }
  return null;
}

bool _isArchivedPlan(String status) {
  return status.trim().toLowerCase() == _planStatusArchived;
}

bool _isTaskAssignedToStaff(ProductionTask task, String staffProfileId) {
  final normalizedStaffId = staffProfileId.trim();
  if (normalizedStaffId.isEmpty) {
    return false;
  }
  final assignedIds = task.assignedStaffIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final legacyId = task.assignedStaffId.trim();
  if (legacyId.isNotEmpty) {
    assignedIds.add(legacyId);
  }
  return assignedIds.contains(normalizedStaffId);
}

_TaskAttendanceState _resolveTaskAttendance({
  required List<ProductionAttendanceRecord> records,
  required String staffProfileId,
  required String taskId,
  required DateTime workDate,
}) {
  final matchingRecords = records.where((record) {
    return record.staffProfileId.trim() == staffProfileId.trim() &&
        record.taskId.trim() == taskId.trim() &&
        _sameCalendarDay(record.workDate ?? record.clockInAt, workDate);
  }).toList();
  matchingRecords.sort((left, right) {
    final leftTime = left.clockInAt ?? left.createdAt ?? DateTime(1900);
    final rightTime = right.clockInAt ?? right.createdAt ?? DateTime(1900);
    return rightTime.compareTo(leftTime);
  });

  final openRecords = matchingRecords
      .where((record) => record.clockInAt != null && record.clockOutAt == null)
      .toList();
  final proofCount = matchingRecords.fold<int>(
    0,
    (sum, record) => sum + record.proofCountUploaded,
  );
  final requiredProofs = matchingRecords.fold<int>(0, (max, record) {
    final requiredProofs = record.effectiveRequiredProofs;
    return requiredProofs > max ? requiredProofs : max;
  });

  return _TaskAttendanceState(
    openRecord: openRecords.isEmpty ? null : openRecords.first,
    todaysRecordCount: matchingRecords.length,
    uploadedProofCount: proofCount,
    requiredProofCount: requiredProofs,
  );
}

int _compareStaffTasks(
  _ProductionStaffTaskSummary left,
  _ProductionStaffTaskSummary right,
) {
  final rankComparison = _taskSortRank(left).compareTo(_taskSortRank(right));
  if (rankComparison != 0) {
    return rankComparison;
  }
  final leftDue = left.task.dueDate ?? DateTime(2100);
  final rightDue = right.task.dueDate ?? DateTime(2100);
  final dueComparison = leftDue.compareTo(rightDue);
  if (dueComparison != 0) {
    return dueComparison;
  }
  return left.taskTitle.compareTo(right.taskTitle);
}

int _taskSortRank(_ProductionStaffTaskSummary summary) {
  if (summary.hasOpenAttendance) {
    return 0;
  }
  if (summary.isCompleted) {
    return 2;
  }
  return 1;
}

DateTime _calendarDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _sameCalendarDay(DateTime? value, DateTime expectedDay) {
  if (value == null) {
    return false;
  }
  final local = value.toLocal();
  return local.year == expectedDay.year &&
      local.month == expectedDay.month &&
      local.day == expectedDay.day;
}

String _formatTime(DateTime? value) {
  if (value == null) {
    return kDateFallbackDash;
  }
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, "0");
  final minute = local.minute.toString().padLeft(2, "0");
  return "$hour:$minute";
}

String _staffDisplayName(BusinessStaffProfileSummary profile) {
  final name = profile.userName?.trim() ?? "";
  if (name.isNotEmpty) {
    return name;
  }
  final email = profile.userEmail?.trim() ?? "";
  if (email.isNotEmpty) {
    return email;
  }
  return profile.id;
}

String _resolveErrorMessage(Object error, {required String fallback}) {
  final message = error.toString().replaceFirst("Exception: ", "").trim();
  return message.isEmpty ? fallback : message;
}
