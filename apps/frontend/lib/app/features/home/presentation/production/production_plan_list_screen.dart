/// lib/app/features/home/presentation/production/production_plan_list_screen.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Lists production plans for owners/staff.
///
/// WHY:
/// - Provides a single entry point to view and create production plans.
/// - Supports draft cleanup and lifecycle actions from the list itself.
///
/// HOW:
/// - Uses productionPlansProvider to fetch plans.
/// - Renders cards with status + dates.
/// - Adds multi-select draft deletion and per-plan action menus.
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
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

const String _logTag = "PRODUCTION_LIST";
const String _buildMessage = "build()";
const String _refreshAction = "refresh_action";
const String _refreshPull = "refresh_pull";
const String _openCreate = "open_create";
const String _openCalendar = "open_calendar";
const String _openArchive = "open_archive";
const String _openDetail = "open_detail";
const String _openPreorderMonitoring = "open_preorder_monitoring";
const String _backTap = "back_tap";
const String _selectDraftAction = "select_draft";
const String _deleteDraftAction = "delete_draft";
const String _deleteDraftBatchAction = "delete_draft_batch";
const String _planLifecycleAction = "plan_lifecycle_action";
const String _screenTitle = "Production plans";
const String _selectionTitle = "Select drafts";
const String _emptyTitle = "No production plans yet";
const String _emptyMessage =
    "Create a plan to organize phases, tasks, and KPI tracking.";
const String _refreshTooltip = "Refresh";
const String _calendarTooltip = "Calendar";
const String _archiveTooltip = "Archive";
const String _monitorTooltip = "Reservations";
const String _createButtonLabel = "Create plan";
const String _deleteSelectedTooltip = "Delete selected drafts";
const String _clearSelectionTooltip = "Clear selection";
const String _businessDashboardRoute = "/business-dashboard";
const String _startLabel = "Start:";
const String _endLabel = "End:";
const String _portfolioConfidenceTitle = "Portfolio confidence";
const String _portfolioPlansLabel = "Plans";
const String _portfolioUnitsLabel = "Weighted units";
const String _portfolioCurrentLabel = "Current";
const String _portfolioBaselineLabel = "Baseline";
const String _portfolioDeltaLabel = "Delta";
const String _portfolioCapacityLabel = "Capacity";
const String _portfolioScheduleLabel = "Schedule";
const String _portfolioReliabilityLabel = "Reliability";
const String _portfolioComplexityLabel = "Complexity";
const String _planConfidenceLabel = "Confidence";
const String _planConfidenceDeltaLabel = "Delta";
const String _draftDeleteConfirmTitle = "Delete selected drafts?";
const String _draftDeleteConfirmMessage =
    "This permanently removes the selected production drafts and their generated tasks.";
const String _draftDeleteCancelLabel = "Cancel";
const String _draftDeleteConfirmLabel = "Delete drafts";
const String _draftDeleteSuccessSingle = "Draft deleted.";
const String _draftDeleteSuccessMany = "Drafts deleted.";
const String _draftDeleteFailure = "Unable to delete one or more drafts.";
const String _planArchiveConfirmTitle = "Archive production plan?";
const String _planArchiveConfirmMessage =
    "Archived plans stay visible for record-keeping but are treated as closed.";
const String _planArchiveConfirmLabel = "Archive";
const String _planStartSuccess = "Production plan started.";
const String _planPauseSuccess = "Production plan paused.";
const String _planResumeSuccess = "Production plan resumed.";
const String _planArchiveSuccess = "Production plan archived.";
const String _planActionFailure = "Unable to update production plan.";
const String _planActionStartLabel = "Start production";
const String _planActionPauseLabel = "Pause process";
const String _planActionResumeLabel = "Resume process";
const String _planActionArchiveLabel = "Archive plan";
const String _planActionDeleteLabel = "Delete draft";
const String _extraPlanIdKey = "planId";
const double _pagePadding = 16;
const double _cardSpacing = 12;
const double _cardRadius = 16;
const double _cardTitleSpacing = 8;
const double _cardRowSpacing = 4;
const double _cardPadding = 16;

const String _ownerRole = "business_owner";
const String _staffRole = "staff";
const String _staffRoleEstateManager = "estate_manager";

const String _planStatusDraft = "draft";
const String _planStatusActive = "active";
const String _planStatusPaused = "paused";
const String _planStatusCompleted = "completed";
const String _planStatusArchived = "archived";

enum _PlanCardAction { start, pause, resume, archive, deleteDraft }

class ProductionPlanListScreen extends ConsumerStatefulWidget {
  const ProductionPlanListScreen({super.key});

  @override
  ConsumerState<ProductionPlanListScreen> createState() =>
      _ProductionPlanListScreenState();
}

class _ProductionPlanListScreenState
    extends ConsumerState<ProductionPlanListScreen> {
  final Set<String> _selectedDraftIds = <String>{};
  bool _isApplyingAction = false;

  bool get _selectionMode => _selectedDraftIds.isNotEmpty;

  void _clearSelection() {
    if (_selectedDraftIds.isEmpty) {
      return;
    }
    setState(() {
      _selectedDraftIds.clear();
    });
  }

  void _toggleDraftSelection(ProductionPlan plan) {
    if (!_isDraftPlan(plan.status)) {
      return;
    }
    setState(() {
      if (_selectedDraftIds.contains(plan.id)) {
        _selectedDraftIds.remove(plan.id);
      } else {
        _selectedDraftIds.add(plan.id);
      }
    });
    AppDebug.log(
      _logTag,
      _selectDraftAction,
      extra: {
        _extraPlanIdKey: plan.id,
        "selected": _selectedDraftIds.contains(plan.id),
      },
    );
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
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
              child: const Text(_draftDeleteCancelLabel),
            ),
            FilledButton(
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

  Future<void> _deleteDraftPlans(List<ProductionPlan> plans) async {
    if (plans.isEmpty || _isApplyingAction) {
      return;
    }
    final confirmed = await _confirmDialog(
      title: _draftDeleteConfirmTitle,
      message: _draftDeleteConfirmMessage,
      confirmLabel: _draftDeleteConfirmLabel,
    );
    if (!confirmed) {
      return;
    }

    setState(() {
      _isApplyingAction = true;
    });

    final actions = ref.read(productionPlanActionsProvider);
    var deletedCount = 0;
    Object? lastError;

    for (final plan in plans) {
      AppDebug.log(
        _logTag,
        plans.length == 1 ? _deleteDraftAction : _deleteDraftBatchAction,
        extra: {_extraPlanIdKey: plan.id},
      );
      try {
        await actions.deletePlan(planId: plan.id);
        deletedCount += 1;
      } catch (err) {
        lastError = err;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isApplyingAction = false;
      for (final plan in plans) {
        _selectedDraftIds.remove(plan.id);
      }
    });

    if (deletedCount > 0) {
      _showSnack(
        deletedCount == 1 ? _draftDeleteSuccessSingle : _draftDeleteSuccessMany,
      );
    }
    if (lastError != null) {
      _showSnack(_draftDeleteFailure);
    }
  }

  Future<void> _handlePlanAction(
    ProductionPlan plan,
    _PlanCardAction action,
  ) async {
    if (_isApplyingAction) {
      return;
    }

    if (action == _PlanCardAction.deleteDraft) {
      await _deleteDraftPlans(<ProductionPlan>[plan]);
      return;
    }

    if (action == _PlanCardAction.archive) {
      final confirmed = await _confirmDialog(
        title: _planArchiveConfirmTitle,
        message: _planArchiveConfirmMessage,
        confirmLabel: _planArchiveConfirmLabel,
      );
      if (!confirmed) {
        return;
      }
    }

    final nextStatus = switch (action) {
      _PlanCardAction.start => _planStatusActive,
      _PlanCardAction.pause => _planStatusPaused,
      _PlanCardAction.resume => _planStatusActive,
      _PlanCardAction.archive => _planStatusArchived,
      _PlanCardAction.deleteDraft => _planStatusDraft,
    };

    setState(() {
      _isApplyingAction = true;
    });

    AppDebug.log(
      _logTag,
      _planLifecycleAction,
      extra: {_extraPlanIdKey: plan.id, "from": plan.status, "to": nextStatus},
    );

    try {
      await ref
          .read(productionPlanActionsProvider)
          .updatePlanStatus(planId: plan.id, status: nextStatus);
      if (!mounted) {
        return;
      }
      final message = switch (action) {
        _PlanCardAction.start => _planStartSuccess,
        _PlanCardAction.pause => _planPauseSuccess,
        _PlanCardAction.resume => _planResumeSuccess,
        _PlanCardAction.archive => _planArchiveSuccess,
        _PlanCardAction.deleteDraft => _draftDeleteSuccessSingle,
      };
      _showSnack(message);
    } catch (err) {
      if (mounted) {
        _showSnack(_planActionFailure);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingAction = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, _buildMessage);
    final plansAsync = ref.watch(productionPlansProvider);
    final portfolioAsync = ref.watch(
      productionPortfolioConfidenceProvider(null),
    );
    final role = ref.watch(authSessionProvider)?.user.role ?? "";
    final userEmail = ref.watch(authSessionProvider)?.user.email;
    final canOpenMonitoring = role == _ownerRole;
    final staffAsync = ref.watch(productionStaffProvider);
    final selfStaffRole = _resolveSelfStaffRole(
      staffList:
          staffAsync.valueOrNull ?? const <BusinessStaffProfileSummary>[],
      userEmail: userEmail,
    );
    final canManageLifecycle = _canManagePlanLifecycle(
      actorRole: role,
      staffRole: selfStaffRole,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? "$_selectionTitle (${_selectedDraftIds.length})"
              : _screenTitle,
        ),
        leading: IconButton(
          icon: Icon(_selectionMode ? Icons.close : Icons.arrow_back),
          tooltip: _selectionMode
              ? _clearSelectionTooltip
              : MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (_selectionMode) {
              _clearSelection();
              return;
            }
            AppDebug.log(_logTag, _backTap);
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(_businessDashboardRoute);
          },
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  onPressed: _isApplyingAction
                      ? null
                      : () {
                          final plans =
                              plansAsync.valueOrNull ??
                              const <ProductionPlan>[];
                          final selectedPlans = plans
                              .where(
                                (plan) => _selectedDraftIds.contains(plan.id),
                              )
                              .toList();
                          _deleteDraftPlans(selectedPlans);
                        },
                  icon: const Icon(Icons.delete_outline),
                  tooltip: _deleteSelectedTooltip,
                ),
              ]
            : [
                IconButton(
                  onPressed: () {
                    AppDebug.log(_logTag, _openCalendar);
                    context.push(productionCalendarRoute);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  tooltip: _calendarTooltip,
                ),
                IconButton(
                  onPressed: () {
                    AppDebug.log(_logTag, _openArchive);
                    context.push(productionPlanArchiveRoute);
                  },
                  icon: const Icon(Icons.archive_outlined),
                  tooltip: _archiveTooltip,
                ),
                if (canOpenMonitoring)
                  IconButton(
                    onPressed: () {
                      AppDebug.log(_logTag, _openPreorderMonitoring);
                      context.push(productionPreorderReservationsRoute);
                    },
                    icon: const Icon(Icons.list_alt_outlined),
                    tooltip: _monitorTooltip,
                  ),
                IconButton(
                  onPressed: () {
                    AppDebug.log(_logTag, _refreshAction);
                    ref.invalidate(productionPlansProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  tooltip: _refreshTooltip,
                ),
              ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                AppDebug.log(_logTag, _openCreate);
                context.push(productionPlanCreateRoute);
              },
              icon: const Icon(Icons.add),
              label: const Text(_createButtonLabel),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log(_logTag, _refreshPull);
          final _ = await ref.refresh(productionPlansProvider.future);
        },
        child: plansAsync.when(
          data: (plans) {
            final visiblePlans = plans
                .where(
                  (plan) =>
                      plan.status.trim().toLowerCase() != _planStatusArchived,
                )
                .toList();
            if (_selectionMode) {
              final validIds = visiblePlans
                  .where((plan) => _isDraftPlan(plan.status))
                  .map((plan) => plan.id)
                  .toSet();
              final staleIds = _selectedDraftIds.difference(validIds);
              if (staleIds.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _selectedDraftIds.removeAll(staleIds);
                  });
                });
              }
            }

            if (visiblePlans.isEmpty) {
              return const ProductionEmptyState(
                title: _emptyTitle,
                message: _emptyMessage,
              );
            }
            final portfolioSummary = portfolioAsync.valueOrNull?.summary;

            return ListView(
              padding: const EdgeInsets.all(_pagePadding),
              children: [
                if (portfolioSummary != null) ...[
                  _PortfolioConfidenceCard(summary: portfolioSummary),
                  const SizedBox(height: _cardSpacing),
                ],
                for (var index = 0; index < visiblePlans.length; index++) ...[
                  _PlanCard(
                    plan: visiblePlans[index],
                    canManageLifecycle: canManageLifecycle,
                    selectionMode: _selectionMode,
                    selected: _selectedDraftIds.contains(
                      visiblePlans[index].id,
                    ),
                    busy: _isApplyingAction,
                    onTap: () {
                      final plan = visiblePlans[index];
                      if (_selectionMode) {
                        _toggleDraftSelection(plan);
                        return;
                      }
                      AppDebug.log(
                        _logTag,
                        _openDetail,
                        extra: {_extraPlanIdKey: plan.id},
                      );
                      context.push(productionPlanDetailPath(plan.id));
                    },
                    onLongPress: () {
                      final plan = visiblePlans[index];
                      if (!canManageLifecycle || !_isDraftPlan(plan.status)) {
                        return;
                      }
                      _toggleDraftSelection(plan);
                    },
                    onActionSelected: (action) =>
                        _handlePlanAction(visiblePlans[index], action),
                  ),
                  if (index < visiblePlans.length - 1)
                    const SizedBox(height: _cardSpacing),
                ],
              ],
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

class _PlanCard extends StatelessWidget {
  final ProductionPlan plan;
  final bool canManageLifecycle;
  final bool selectionMode;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<_PlanCardAction> onActionSelected;

  const _PlanCard({
    required this.plan,
    required this.canManageLifecycle,
    required this.selectionMode,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onLongPress,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final confidence = plan.confidence;
    final availableActions = _planActionsForStatus(plan.status);
    final isSelectableDraft = _isDraftPlan(plan.status);

    return InkWell(
      onTap: busy ? null : onTap,
      onLongPress: busy || !isSelectableDraft ? null : onLongPress,
      borderRadius: BorderRadius.circular(_cardRadius),
      child: Container(
        padding: const EdgeInsets.all(_cardPadding),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
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
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selectionMode && isSelectableDraft) ...[
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? colorScheme.primary : colorScheme.outline,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                ],
                ProductionStatusPill(label: plan.status),
                if (!selectionMode &&
                    canManageLifecycle &&
                    availableActions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<_PlanCardAction>(
                    tooltip: "Plan actions",
                    onSelected: onActionSelected,
                    itemBuilder: (context) {
                      return availableActions
                          .map(
                            (action) => PopupMenuItem<_PlanCardAction>(
                              value: action,
                              child: Row(
                                children: [
                                  Icon(_iconForPlanAction(action), size: 18),
                                  const SizedBox(width: 10),
                                  Text(_labelForPlanAction(action)),
                                ],
                              ),
                            ),
                          )
                          .toList();
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: _cardTitleSpacing),
            Text(
              "$_startLabel ${formatDateLabel(plan.startDate)}",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: _cardRowSpacing),
            Text(
              "$_endLabel ${formatDateLabel(plan.endDate)}",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (confidence != null) ...[
              const SizedBox(height: _cardRowSpacing),
              Text(
                "$_planConfidenceLabel: ${_formatScorePercent(confidence.currentConfidenceScore)}",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: _cardRowSpacing),
              Text(
                "$_planConfidenceDeltaLabel: ${_formatDeltaPercent(confidence.confidenceScoreDelta)}",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PortfolioConfidenceCard extends StatelessWidget {
  final ProductionPortfolioConfidenceSummary summary;

  const _PortfolioConfidenceCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget row(String label, String value) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _portfolioConfidenceTitle,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: _cardTitleSpacing),
          row(_portfolioPlansLabel, "${summary.planCount}"),
          const SizedBox(height: _cardRowSpacing),
          row(_portfolioUnitsLabel, "${summary.weightedUnitCount}"),
          const SizedBox(height: _cardRowSpacing),
          row(
            _portfolioCurrentLabel,
            _formatScorePercent(summary.currentConfidenceScore),
          ),
          const SizedBox(height: _cardRowSpacing),
          row(
            _portfolioBaselineLabel,
            _formatScorePercent(summary.baselineConfidenceScore),
          ),
          const SizedBox(height: _cardRowSpacing),
          row(
            _portfolioDeltaLabel,
            _formatDeltaPercent(summary.confidenceScoreDelta),
          ),
          const SizedBox(height: _cardTitleSpacing),
          row(
            _portfolioCapacityLabel,
            _formatScorePercent(summary.currentBreakdown.capacity),
          ),
          const SizedBox(height: _cardRowSpacing),
          row(
            _portfolioScheduleLabel,
            _formatScorePercent(summary.currentBreakdown.scheduleStability),
          ),
          const SizedBox(height: _cardRowSpacing),
          row(
            _portfolioReliabilityLabel,
            _formatScorePercent(summary.currentBreakdown.historicalReliability),
          ),
          const SizedBox(height: _cardRowSpacing),
          row(
            _portfolioComplexityLabel,
            _formatScorePercent(summary.currentBreakdown.complexityRisk),
          ),
        ],
      ),
    );
  }
}

List<_PlanCardAction> _planActionsForStatus(String rawStatus) {
  final status = rawStatus.trim().toLowerCase();
  return switch (status) {
    _planStatusDraft => const <_PlanCardAction>[
      _PlanCardAction.start,
      _PlanCardAction.archive,
      _PlanCardAction.deleteDraft,
    ],
    _planStatusActive => const <_PlanCardAction>[
      _PlanCardAction.pause,
      _PlanCardAction.archive,
    ],
    _planStatusPaused => const <_PlanCardAction>[
      _PlanCardAction.resume,
      _PlanCardAction.archive,
    ],
    _planStatusCompleted => const <_PlanCardAction>[_PlanCardAction.archive],
    _planStatusArchived => const <_PlanCardAction>[],
    _ => const <_PlanCardAction>[],
  };
}

String _labelForPlanAction(_PlanCardAction action) {
  return switch (action) {
    _PlanCardAction.start => _planActionStartLabel,
    _PlanCardAction.pause => _planActionPauseLabel,
    _PlanCardAction.resume => _planActionResumeLabel,
    _PlanCardAction.archive => _planActionArchiveLabel,
    _PlanCardAction.deleteDraft => _planActionDeleteLabel,
  };
}

IconData _iconForPlanAction(_PlanCardAction action) {
  return switch (action) {
    _PlanCardAction.start => Icons.play_arrow_outlined,
    _PlanCardAction.pause => Icons.pause_circle_outline,
    _PlanCardAction.resume => Icons.play_circle_outline,
    _PlanCardAction.archive => Icons.archive_outlined,
    _PlanCardAction.deleteDraft => Icons.delete_outline,
  };
}

bool _isDraftPlan(String status) =>
    status.trim().toLowerCase() == _planStatusDraft;

String? _resolveSelfStaffRole({
  required List<BusinessStaffProfileSummary> staffList,
  required String? userEmail,
}) {
  final normalizedEmail = (userEmail ?? "").trim().toLowerCase();
  if (normalizedEmail.isEmpty) {
    return null;
  }

  for (final profile in staffList) {
    final profileEmail = (profile.userEmail ?? "").trim().toLowerCase();
    if (profileEmail.isNotEmpty && profileEmail == normalizedEmail) {
      return profile.staffRole;
    }
  }
  return null;
}

bool _canManagePlanLifecycle({
  required String actorRole,
  required String? staffRole,
}) {
  if (actorRole == _ownerRole) {
    return true;
  }

  return actorRole == _staffRole && staffRole == _staffRoleEstateManager;
}

String _formatScorePercent(double value) {
  final percent = (value * 100).clamp(0, 100).toDouble();
  return "${percent.toStringAsFixed(0)}%";
}

String _formatDeltaPercent(double value) {
  final percent = (value * 100).toDouble();
  final prefix = percent >= 0 ? "+" : "";
  return "$prefix${percent.toStringAsFixed(1)}%";
}
