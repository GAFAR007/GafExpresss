/// lib/app/features/home/presentation/production/production_plan_archive_screen.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Lists archived production plans separately from the main workflow.
///
/// WHY:
/// - Keeps the primary production screen focused on active/draft plans.
/// - Preserves archived plans for lookup without cluttering the main list.
///
/// HOW:
/// - Reuses productionPlansProvider and filters for archived status only.
/// - Navigates to the existing plan detail screen on tap.
/// - Lets managers restore archived plans or delete archived records permanently.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';

const String _logTag = "PRODUCTION_ARCHIVE";
const String _buildMessage = "build()";
const String _refreshAction = "refresh_action";
const String _refreshPull = "refresh_pull";
const String _openDetail = "open_detail";
const String _restoreAction = "restore_action";
const String _deleteAction = "delete_action";
const String _screenTitle = "Archived plans";
const String _emptyTitle = "No archived plans";
const String _emptyMessage =
    "Archived production plans will appear here after you archive them.";
const String _refreshTooltip = "Refresh";
const String _restoreConfirmTitle = "Unarchive production plan?";
const String _restoreConfirmMessage =
    "This moves the plan back to your main production list so you can continue managing it.";
const String _restoreConfirmLabel = "Unarchive";
const String _restoreSuccess = "Production plan unarchived.";
const String _restoreFailure = "Unable to unarchive production plan.";
const String _deleteConfirmTitle = "Delete archived production plan?";
const String _deleteConfirmMessage =
    "This permanently deletes the archived plan and its linked phases, tasks, output rows, and schedule records.";
const String _deleteConfirmLabel = "Delete permanently";
const String _deleteSuccess = "Archived production plan deleted.";
const String _deleteFailure = "Unable to delete archived production plan.";
const String _cancelLabel = "Cancel";
const String _startLabel = "Start:";
const String _endLabel = "End:";
const String _extraPlanIdKey = "planId";
const String _extraRestoreStatusKey = "restoreStatus";
const String _planStatusDraft = "draft";
const String _planStatusPaused = "paused";
const String _planStatusCompleted = "completed";
const double _pagePadding = 16;
const double _cardSpacing = 12;
const double _cardRadius = 16;
const double _cardPadding = 16;
const double _cardTitleSpacing = 8;
const double _cardRowSpacing = 4;

enum _ArchivedPlanAction { restore, delete }

class ProductionPlanArchiveScreen extends ConsumerStatefulWidget {
  const ProductionPlanArchiveScreen({super.key});

  @override
  ConsumerState<ProductionPlanArchiveScreen> createState() =>
      _ProductionPlanArchiveScreenState();
}

class _ProductionPlanArchiveScreenState
    extends ConsumerState<ProductionPlanArchiveScreen> {
  bool _isApplyingAction = false;

  Future<bool> _confirmArchiveAction({
    required String title,
    required String message,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(_cancelLabel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(
                        dialogContext,
                      ).colorScheme.error,
                      foregroundColor: Theme.of(
                        dialogContext,
                      ).colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleArchivedPlanAction(
    ProductionPlan plan,
    _ArchivedPlanAction action,
  ) async {
    if (_isApplyingAction) {
      return;
    }

    final confirmed = await _confirmArchiveAction(
      title: action == _ArchivedPlanAction.restore
          ? _restoreConfirmTitle
          : _deleteConfirmTitle,
      message: action == _ArchivedPlanAction.restore
          ? _restoreConfirmMessage
          : _deleteConfirmMessage,
      confirmLabel: action == _ArchivedPlanAction.restore
          ? _restoreConfirmLabel
          : _deleteConfirmLabel,
      destructive: action == _ArchivedPlanAction.delete,
    );
    if (!confirmed) {
      return;
    }

    setState(() => _isApplyingAction = true);

    try {
      final actions = ref.read(productionPlanActionsProvider);
      if (action == _ArchivedPlanAction.restore) {
        final restoreStatus = _resolveUnarchiveStatus(plan);
        AppDebug.log(
          _logTag,
          _restoreAction,
          extra: {
            _extraPlanIdKey: plan.id,
            _extraRestoreStatusKey: restoreStatus,
          },
        );
        await actions.updatePlanStatus(planId: plan.id, status: restoreStatus);
        if (mounted) {
          _showSnack(_restoreSuccess);
        }
      } else {
        AppDebug.log(_logTag, _deleteAction, extra: {_extraPlanIdKey: plan.id});
        await actions.deletePlan(planId: plan.id);
        if (mounted) {
          _showSnack(_deleteSuccess);
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(
        action == _ArchivedPlanAction.restore
            ? _restoreFailure
            : _deleteFailure,
      );
      AppDebug.log(
        _logTag,
        "archive_plan_action_failed",
        extra: {
          _extraPlanIdKey: plan.id,
          "action": action.name,
          "error": error.toString(),
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isApplyingAction = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _buildMessage);
    final plansAsync = ref.watch(productionPlansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(productionPlansRoute);
          },
        ),
        actions: [
          IconButton(
            onPressed: _isApplyingAction
                ? null
                : () {
                    AppDebug.log(_logTag, _refreshAction);
                    ref.invalidate(productionPlansProvider);
                  },
            icon: const Icon(Icons.refresh),
            tooltip: _refreshTooltip,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log(_logTag, _refreshPull);
          final _ = await ref.refresh(productionPlansProvider.future);
        },
        child: plansAsync.when(
          data: (plans) {
            final archivedPlans = plans
                .where((plan) => plan.status.trim().toLowerCase() == "archived")
                .toList();
            if (archivedPlans.isEmpty) {
              return const ProductionEmptyState(
                title: _emptyTitle,
                message: _emptyMessage,
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(_pagePadding),
              itemCount: archivedPlans.length,
              separatorBuilder: (_, _) => const SizedBox(height: _cardSpacing),
              itemBuilder: (context, index) {
                final plan = archivedPlans[index];
                return InkWell(
                  onTap: _isApplyingAction
                      ? null
                      : () {
                          AppDebug.log(
                            _logTag,
                            _openDetail,
                            extra: {_extraPlanIdKey: plan.id},
                          );
                          context.push(productionPlanDetailPath(plan.id));
                        },
                  borderRadius: BorderRadius.circular(_cardRadius),
                  child: Container(
                    padding: const EdgeInsets.all(_cardPadding),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(_cardRadius),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                plan.title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            ProductionStatusPill(label: plan.status),
                            const SizedBox(width: 8),
                            PopupMenuButton<_ArchivedPlanAction>(
                              enabled: !_isApplyingAction,
                              tooltip: "Plan actions",
                              onSelected: (action) =>
                                  _handleArchivedPlanAction(plan, action),
                              itemBuilder: (context) => const [
                                PopupMenuItem<_ArchivedPlanAction>(
                                  value: _ArchivedPlanAction.restore,
                                  child: Row(
                                    children: [
                                      Icon(Icons.unarchive_outlined, size: 18),
                                      SizedBox(width: 10),
                                      Text("Unarchive plan"),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<_ArchivedPlanAction>(
                                  value: _ArchivedPlanAction.delete,
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 18),
                                      SizedBox(width: 10),
                                      Text("Delete permanently"),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: _cardTitleSpacing),
                        Text(
                          "$_startLabel ${formatDateLabel(plan.startDate)}",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: _cardRowSpacing),
                        Text(
                          "$_endLabel ${formatDateLabel(plan.endDate)}",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(_pagePadding),
              child: Text(err.toString()),
            ),
          ),
        ),
      ),
    );
  }
}

String _resolveUnarchiveStatus(ProductionPlan plan) {
  final now = DateTime.now();
  final startDate = plan.startDate;
  final endDate = plan.endDate;

  if (startDate != null && now.isBefore(startDate)) {
    return _planStatusDraft;
  }
  if (endDate != null && now.isAfter(endDate)) {
    return _planStatusCompleted;
  }
  return _planStatusPaused;
}
