/// lib/app/features/home/presentation/production/production_plan_list_screen.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Lists production plans for owners/staff.
///
/// WHY:
/// - Provides a single entry point to view and create production plans.
///
/// HOW:
/// - Uses productionPlansProvider to fetch plans.
/// - Renders cards with status + dates.
/// - Logs build, refresh, and navigation taps.
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
const String _openDetail = "open_detail";
const String _openPreorderMonitoring = "open_preorder_monitoring";
const String _backTap = "back_tap";
const String _screenTitle = "Production plans";
const String _emptyTitle = "No production plans yet";
const String _emptyMessage =
    "Create a plan to organize phases, tasks, and KPI tracking.";
const String _refreshTooltip = "Refresh";
const String _calendarTooltip = "Calendar";
const String _monitorTooltip = "Reservations";
const String _createButtonLabel = "Create plan";
const String _businessDashboardRoute = "/business-dashboard";
const String _startLabel = "Start:";
const String _endLabel = "End:";
const String _extraPlanIdKey = "planId";
const double _pagePadding = 16;
const double _cardSpacing = 12;
const double _cardRadius = 16;
const double _cardTitleSpacing = 8;
const double _cardRowSpacing = 4;
const double _cardPadding = 16;

class ProductionPlanListScreen extends ConsumerWidget {
  const ProductionPlanListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage);
    final plansAsync = ref.watch(productionPlansProvider);
    final role = ref.read(authSessionProvider)?.user.role ?? "";
    final canOpenMonitoring = role == "business_owner";

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log(_logTag, _backTap);
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(_businessDashboardRoute);
          },
        ),
        actions: [
          IconButton(
            onPressed: () {
              AppDebug.log(_logTag, _openCalendar);
              context.push(productionCalendarRoute);
            },
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: _calendarTooltip,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          AppDebug.log(_logTag, _openCreate);
          context.push(productionPlanAssistantRoute);
        },
        icon: const Icon(Icons.add),
        label: const Text(_createButtonLabel),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log(_logTag, _refreshPull);
          // WHY: Force a fresh fetch without leaving the screen.
          final _ = await ref.refresh(productionPlansProvider.future);
        },
        child: plansAsync.when(
          data: (plans) {
            if (plans.isEmpty) {
              return const ProductionEmptyState(
                title: _emptyTitle,
                message: _emptyMessage,
              );
            }

            // WHY: Use a list so the screen scales with plan count.
            return ListView.separated(
              padding: const EdgeInsets.all(_pagePadding),
              itemBuilder: (context, index) {
                final plan = plans[index];
                return _PlanCard(
                  plan: plan,
                  onTap: () {
                    AppDebug.log(
                      _logTag,
                      _openDetail,
                      extra: {_extraPlanIdKey: plan.id},
                    );
                    context.push(productionPlanDetailPath(plan.id));
                  },
                );
              },
              separatorBuilder: (context, index) =>
                  const SizedBox(height: _cardSpacing),
              itemCount: plans.length,
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
  final VoidCallback onTap;

  const _PlanCard({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_cardRadius),
      child: Container(
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
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ProductionStatusPill(label: plan.status),
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
          ],
        ),
      ),
    );
  }
}
