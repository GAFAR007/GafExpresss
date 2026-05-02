// WHAT: Verifies the production plan summary exposes farm quantity progress.
// WHY: Plan details should show transplant progress, remaining harvest, and
// the latest saved update without forcing operators into another screen.
// HOW: The test overrides plan detail providers with farm timeline data and
// asserts the summary accordion renders the derived quantity metrics.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';

const _planId = 'plan-1';

ProductionPlanDetail _buildFarmPlanDetail() {
  return ProductionPlanDetail.fromJson({
    'plan': {
      'id': _planId,
      'businessId': 'business-1',
      'estateAssetId': 'estate-1',
      'productId': 'product-1',
      'domainContext': 'farm',
      'title': 'Pepper Production',
      'status': 'active',
      'startDate': '2026-03-15',
      'endDate': '2026-07-13',
      'updatedAt': '2026-04-24T08:00:00.000Z',
      'plantingTargets': {
        'materialType': 'seed',
        'plannedPlantingQuantity': 3500,
        'plannedPlantingUnit': 'plant',
        'estimatedHarvestQuantity': 5500,
        'estimatedHarvestUnit': 'kg',
      },
    },
    'timelineRows': [
      {
        'id': 'row-1',
        'planId': _planId,
        'taskId': 'task-1',
        'workDate': '2026-04-24',
        'taskTitle': 'Transplant block A',
        'phaseName': 'Transplant',
        'quantityActivityType': 'transplanted',
        'quantityAmount': 135,
        'quantityUnit': 'plant',
        'approvalState': 'approved',
        'approvedAt': '2026-04-24T11:30:00.000Z',
      },
      {
        'id': 'row-2',
        'planId': _planId,
        'taskId': 'task-2',
        'workDate': '2026-04-24',
        'taskTitle': 'Harvest block A',
        'phaseName': 'Harvest',
        'quantityActivityType': 'harvested',
        'quantityAmount': 120,
        'quantityUnit': 'kg',
        'approvalState': 'approved',
        'approvedAt': '2026-04-24T10:15:00.000Z',
      },
    ],
    'phases': const [],
    'tasks': const [],
    'staffProfiles': const [],
  });
}

ProductionPlanDetail _buildExecutionPlanDetail() {
  return ProductionPlanDetail.fromJson({
    'plan': {
      'id': _planId,
      'businessId': 'business-1',
      'estateAssetId': 'estate-1',
      'productId': 'product-1',
      'domainContext': 'farm',
      'title': 'Pepper Production',
      'status': 'active',
      'startDate': '2026-04-20',
      'endDate': '2026-04-30',
    },
    'phases': [
      {
        'id': 'phase-1',
        'planId': _planId,
        'name': 'Transplant Establishment',
        'phaseType': 'finite',
        'order': 1,
        'startDate': '2026-04-20',
        'endDate': '2026-04-30',
        'status': 'active',
      },
    ],
    'tasks': [
      {
        'id': 'task-1',
        'planId': _planId,
        'phaseId': 'phase-1',
        'title': 'Transplanting - Greenhouse 3',
        'taskType': 'workload',
        'assignedStaffIds': ['staff-1'],
        'requiredHeadcount': 1,
        'assignedCount': 1,
        'status': 'in_progress',
        'approvalStatus': 'pending_approval',
        'startDate': '2026-04-23',
        'dueDate': '2026-04-23',
      },
      {
        'id': 'task-2',
        'planId': _planId,
        'phaseId': 'phase-1',
        'title': 'Supervise',
        'taskType': 'event',
        'assignedStaffIds': ['staff-1'],
        'requiredHeadcount': 1,
        'assignedCount': 1,
        'status': 'done',
        'approvalStatus': 'approved',
        'startDate': '2026-04-23',
        'dueDate': '2026-04-23',
      },
      {
        'id': 'task-3',
        'planId': _planId,
        'phaseId': 'phase-1',
        'title': 'Harvest block A',
        'taskType': 'workload',
        'assignedStaffIds': ['staff-1'],
        'requiredHeadcount': 1,
        'assignedCount': 1,
        'status': 'done',
        'approvalStatus': 'approved',
        'startDate': '2026-04-24',
        'dueDate': '2026-04-24',
      },
      {
        'id': 'task-4',
        'planId': _planId,
        'phaseId': 'phase-1',
        'title': 'Quality check',
        'taskType': 'event',
        'assignedStaffIds': ['staff-1'],
        'requiredHeadcount': 1,
        'assignedCount': 1,
        'status': 'in_progress',
        'approvalStatus': 'pending',
        'startDate': '2026-04-25',
        'dueDate': '2026-04-25',
      },
    ],
    'timelineRows': [
      {
        'id': 'row-1',
        'planId': _planId,
        'taskId': 'task-1',
        'workDate': '2026-04-23',
        'taskTitle': 'Transplanting - Greenhouse 3',
        'phaseName': 'Transplant Establishment',
        'farmerName': 'Odey Musse Ipo',
        'expectedPlots': 5,
        'actualPlots': 2,
        'status': 'in_progress',
        'delay': 'on_time',
        'approvalState': 'pending_approval',
        'clockInTime': '2026-04-23T08:00:00.000Z',
        'proofCount': 1,
      },
      {
        'id': 'row-2',
        'planId': _planId,
        'taskId': 'task-2',
        'workDate': '2026-04-23',
        'taskTitle': 'Supervise',
        'phaseName': 'Transplant Establishment',
        'farmerName': 'Odey Musse Ipo',
        'expectedPlots': 1,
        'actualPlots': 1,
        'status': 'done',
        'delay': 'on_time',
        'approvalState': 'approved',
        'approvedAt': '2026-04-23T16:00:00.000Z',
        'clockInTime': '2026-04-23T10:00:00.000Z',
        'proofCount': 0,
      },
      {
        'id': 'row-3',
        'planId': _planId,
        'taskId': 'task-3',
        'workDate': '2026-04-24',
        'taskTitle': 'Harvest block A',
        'phaseName': 'Harvest',
        'farmerName': 'Odey Musse Ipo',
        'expectedPlots': 5,
        'actualPlots': 5,
        'status': 'done',
        'delay': 'on_time',
        'approvalState': 'approved',
        'approvedAt': '2026-04-24T10:00:00.000Z',
        'proofCount': 2,
      },
    ],
    'staffProfiles': [
      {
        'id': 'staff-1',
        'userId': 'user-1',
        'staffRole': 'farmer',
        'status': 'active',
        'estateAssetId': 'estate-1',
        'user': {'name': 'Odey Musse Ipo', 'email': 'odey@test.local'},
      },
    ],
  });
}

const _viewerProfile = UserProfile(
  id: 'user-1',
  name: 'Viewer',
  email: 'viewer@test.local',
  role: 'customer',
  accountType: 'personal',
  isEmailVerified: true,
  isPhoneVerified: false,
  isNinVerified: false,
);

const _ownerProfile = UserProfile(
  id: 'owner-1',
  name: 'Owner',
  email: 'owner@test.local',
  role: 'business_owner',
  accountType: 'business',
  isEmailVerified: true,
  isPhoneVerified: false,
  isNinVerified: false,
);

Widget _buildPlanDetailRouterApp(
  ProductionPlanDetail detail, {
  String? initialLocation,
  UserProfile profile = _viewerProfile,
  ProductionPlanUnitsResponse? planUnitsResponse,
}) {
  final router = GoRouter(
    initialLocation: initialLocation ?? productionPlanInsightsPath(_planId),
    routes: [
      GoRoute(
        path: productionPlanInsightsRoute,
        builder: (context, state) => ProductionPlanDetailScreen(
          planId: state.pathParameters['id'] ?? _planId,
          initialView: state.uri.queryParameters['view'] ?? '',
        ),
      ),
      GoRoute(
        path: productionPlanTaskDetailRoute,
        builder: (context, state) => Scaffold(
          body: Text(
            'Task detail ${state.pathParameters['taskId']}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    ],
  );

  final overrides = [
    productionPlanDetailProvider(_planId).overrideWith((ref) async => detail),
    productionStaffProvider.overrideWith((ref) async => detail.staffProfiles),
    userProfileProvider.overrideWith((ref) async => profile),
    if (planUnitsResponse != null)
      productionPlanUnitsProvider(
        _planId,
      ).overrideWith((ref) async => planUnitsResponse),
  ];

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
    'plan details shows transplant, remaining harvest, and latest update',
    (tester) async {
      final latestUpdateLabel = formatDateTimeLabel(
        DateTime.parse('2026-04-24T11:30:00.000Z'),
      );
      await tester.binding.setSurfaceSize(const Size(1440, 1400));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productionPlanDetailProvider(
              _planId,
            ).overrideWith((ref) async => _buildFarmPlanDetail()),
            productionStaffProvider.overrideWith((ref) async => const []),
            userProfileProvider.overrideWith((ref) async => _viewerProfile),
          ],
          child: const MaterialApp(
            home: ProductionPlanDetailScreen(planId: _planId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transplant'), findsOneWidget);
      expect(find.text('135 / 3500'), findsOneWidget);
      expect(find.text('3365 left plant'), findsOneWidget);

      expect(find.text('Remaining harvest'), findsOneWidget);
      expect(find.text('5380 kg'), findsOneWidget);
      expect(find.text('120 / 5500 harvested'), findsOneWidget);

      expect(find.text('Latest update'), findsOneWidget);
      expect(find.text(latestUpdateLabel), findsOneWidget);
    },
  );

  testWidgets(
    'plan summary shows named backend units without preorder or confidence',
    (tester) async {
      final detail = ProductionPlanDetail.fromJson({
        'plan': {
          'id': _planId,
          'businessId': 'business-1',
          'estateAssetId': 'estate-1',
          'productId': 'product-1',
          'domainContext': 'farm',
          'title': 'Bell Pepper Plan',
          'status': 'active',
          'startDate': '2026-03-15',
          'endDate': '2026-07-13',
          'workloadContext': {
            'workUnitLabel': 'plot',
            'workUnitType': 'plot',
            'totalWorkUnits': 12,
            'minStaffPerUnit': 1,
            'maxStaffPerUnit': 2,
            'activeStaffAvailabilityPercent': 100,
            'hasConfirmedWorkloadContext': true,
          },
        },
        'preorderSummary': {
          'productionState': 'in_production',
          'preorderEnabled': false,
          'preorderCapQuantity': 0,
          'effectiveCap': 0,
          'confidenceScore': 1,
          'approvedProgressCoverage': 1,
          'preorderReservedQuantity': 0,
          'preorderRemainingQuantity': 0,
        },
        'timelineRows': const [],
        'phases': const [],
        'tasks': const [],
        'staffProfiles': const [],
      });
      final unitsResponse = ProductionPlanUnitsResponse.fromJson({
        'message': 'ok',
        'planId': _planId,
        'totalUnits': 0,
        'units': [
          {
            'id': 'unit-1',
            'planId': _planId,
            'unitIndex': 1,
            'label': 'Greenhouse 1',
          },
          {
            'id': 'unit-2',
            'planId': _planId,
            'unitIndex': 2,
            'label': 'Greenhouse 2',
          },
        ],
      });

      await tester.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        _buildPlanDetailRouterApp(
          detail,
          profile: _ownerProfile,
          planUnitsResponse: unitsResponse,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Product state'), findsOneWidget);
      expect(find.text('in_production'), findsOneWidget);
      expect(find.text('Plan units'), findsOneWidget);
      expect(find.text('2 greenhouses'), findsOneWidget);
      expect(find.text('Pre-order'), findsNothing);
      expect(find.text('Pre-order details'), findsNothing);
      expect(find.text('Confidence'), findsNothing);
      expect(find.text('Lifecycle confidence'), findsNothing);
    },
  );

  testWidgets(
    'execution tab shows stacked day chart details and task navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1600));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        _buildPlanDetailRouterApp(
          _buildExecutionPlanDetail(),
          initialLocation: productionPlanInsightsPath(
            _planId,
            view: 'execution',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stacked task progress by day'), findsOneWidget);
      expect(find.text('Visible tasks'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
      expect(find.text('Approved segments'), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      final taskOneSegment = find.byKey(
        const ValueKey('execution-chart-segment-task-1-2026-04-23'),
      );
      final taskTwoSegment = find.byKey(
        const ValueKey('execution-chart-segment-task-2-2026-04-23'),
      );
      final zeroBaseline = find.byKey(
        const ValueKey('execution-chart-zero-baseline'),
      );
      expect(taskOneSegment, findsOneWidget);
      expect(taskTwoSegment, findsOneWidget);
      expect(zeroBaseline, findsOneWidget);

      final taskOneRect = tester.getRect(taskOneSegment);
      final taskTwoRect = tester.getRect(taskTwoSegment);
      final baselineRect = tester.getRect(zeroBaseline);
      expect(taskOneRect.top, greaterThan(taskTwoRect.top));
      expect(baselineRect.height, closeTo(2, 0.1));
      expect(baselineRect.width, greaterThan(240));
      expect(taskOneRect.bottom, closeTo(baselineRect.top, 0.1));

      await tester.tap(
        find.byKey(const ValueKey('execution-chart-bar-2026-04-23')),
      );
      await tester.pumpAndSettle();

      final detailsPanel = find.byKey(
        const ValueKey('execution-chart-day-details'),
      );
      expect(detailsPanel, findsOneWidget);
      expect(
        find.descendant(
          of: detailsPanel,
          matching: find.text('Transplanting - Greenhouse 3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detailsPanel, matching: find.text('Supervise')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('execution-chart-bar-2026-04-25')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: detailsPanel, matching: find.text('Quality check')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('execution-chart-bar-2026-04-23')),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.descendant(
          of: detailsPanel,
          matching: find.byKey(const ValueKey('execution-chart-task-task-1')),
        ),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: detailsPanel,
          matching: find.byKey(const ValueKey('execution-chart-task-task-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Task detail task-1'), findsOneWidget);
    },
  );

  testWidgets(
    'execution tab defaults chart details to today when today exists',
    (tester) async {
      final today = DateTime.now();
      final todayDate = formatDateInput(today);
      final firstVisibleDate = today.subtract(const Duration(days: 11));
      final firstVisibleDateLabel = formatDateInput(firstVisibleDate);
      final timelineRows = List.generate(12, (index) {
        final workDate = firstVisibleDate.add(Duration(days: index));
        final workDateLabel = formatDateInput(workDate);
        return <String, dynamic>{
          'id': 'row-$index',
          'planId': _planId,
          'taskId': 'task-$index',
          'workDate': '${workDateLabel}T00:00:00.000Z',
          'taskTitle': index == 11 ? 'Today task' : 'Task $index',
          'phaseName': 'Execution',
          'approvalState': 'approved',
        };
      });

      final detail = ProductionPlanDetail.fromJson({
        'plan': {
          'id': _planId,
          'businessId': 'business-1',
          'estateAssetId': 'estate-1',
          'productId': 'product-1',
          'domainContext': 'farm',
          'title': 'Pepper Production',
          'status': 'active',
          'startDate': firstVisibleDateLabel,
          'endDate': todayDate,
        },
        'timelineRows': timelineRows,
        'phases': const [],
        'tasks': const [],
        'staffProfiles': const [],
      });

      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        _buildPlanDetailRouterApp(
          detail,
          initialLocation: productionPlanInsightsPath(
            _planId,
            view: 'execution',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final detailsPanel = find.byKey(
        const ValueKey('execution-chart-day-details'),
      );
      expect(detailsPanel, findsOneWidget);
      expect(
        find.descendant(
          of: detailsPanel,
          matching: find.text('Task details · $todayDate'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detailsPanel, matching: find.text('Today task')),
        findsOneWidget,
      );

      final todayBar = find.byKey(ValueKey('execution-chart-bar-$todayDate'));
      final scrollViewport = find.byKey(
        const ValueKey('execution-chart-scroll'),
      );
      final todayBarRect = tester.getRect(todayBar);
      final scrollViewportRect = tester.getRect(scrollViewport);
      expect(todayBarRect.left, greaterThanOrEqualTo(scrollViewportRect.left));
      expect(
        todayBarRect.right,
        lessThanOrEqualTo(scrollViewportRect.right + 1),
      );
    },
  );

  testWidgets('compact execution view keeps the bar chart visible on load', (
    tester,
  ) async {
    final detail = ProductionPlanDetail.fromJson({
      'plan': {
        'id': _planId,
        'businessId': 'business-1',
        'estateAssetId': 'estate-1',
        'productId': 'product-1',
        'domainContext': 'farm',
        'title': 'Pepper Production',
        'status': 'active',
        'startDate': '2026-04-23',
        'endDate': '2026-04-26',
      },
      'timelineRows': [
        {
          'id': 'row-1',
          'planId': _planId,
          'taskId': 'task-1',
          'workDate': '2026-04-23',
          'taskTitle': 'Task A',
          'phaseName': 'Exec',
          'farmerName': 'A',
          'approvalState': 'approved',
        },
        {
          'id': 'row-2',
          'planId': _planId,
          'taskId': 'task-2',
          'workDate': '2026-04-24',
          'taskTitle': 'Task B',
          'phaseName': 'Exec',
          'farmerName': 'B',
          'approvalState': 'pending_approval',
        },
        {
          'id': 'row-3',
          'planId': _planId,
          'taskId': 'task-3',
          'workDate': '2026-04-25',
          'taskTitle': 'Task C',
          'phaseName': 'Exec',
          'farmerName': 'C',
          'approvalState': 'pending_approval',
        },
      ],
      'phases': const [],
      'tasks': const [],
      'staffProfiles': const [],
    });

    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _buildPlanDetailRouterApp(
        detail,
        initialLocation: productionPlanInsightsPath(_planId, view: 'execution'),
      ),
    );
    await tester.pumpAndSettle();

    final chartScroll = find.byKey(const ValueKey('execution-chart-scroll'));
    final chartScrollRect = tester.getRect(chartScroll);
    final viewportRect = tester.getRect(find.byType(ListView).first);

    expect(chartScroll, findsOneWidget);
    expect(chartScrollRect.top, greaterThanOrEqualTo(viewportRect.top));
    expect(chartScrollRect.top, lessThan(viewportRect.bottom));
  });
}
