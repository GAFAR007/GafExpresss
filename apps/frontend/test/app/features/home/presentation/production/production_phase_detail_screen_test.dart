// WHAT: Verifies the production phase detail screen defaults and filter UI.
// WHY: The screen should open with the full phase task pack visible and keep
// the compact filter toolbar usable on narrow viewports.
// HOW: The test builds plan data relative to the current date and interacts
// with the date picker to confirm filtering updates.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_phase_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';

const _planId = 'plan-1';
const _phaseId = 'phase-1';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _alternateDate(DateTime today) {
  final nextDay = today.add(const Duration(days: 1));
  if (nextDay.month == today.month) {
    return nextDay;
  }
  return today.subtract(const Duration(days: 1));
}

ProductionPlanDetail _buildPlanDetail() {
  final today = _today();
  final alternateDate = _alternateDate(today);
  final phaseStart = alternateDate.isBefore(today) ? alternateDate : today;
  final phaseEnd = alternateDate.isAfter(today) ? alternateDate : today;
  return ProductionPlanDetail.fromJson({
    'plan': {
      'id': _planId,
      'businessId': 'business-1',
      'estateAssetId': 'estate-1',
      'productId': 'product-1',
      'domainContext': 'farm',
      'title': 'Pepper Production',
      'status': 'active',
    },
    'phases': [
      {
        'id': _phaseId,
        'planId': _planId,
        'name': 'Transplant Establishment',
        'phaseType': 'finite',
        'order': 1,
        'startDate': formatDateInput(phaseStart),
        'endDate': formatDateInput(phaseEnd),
        'status': 'active',
      },
    ],
    'tasks': [
      {
        'id': 'task-1',
        'planId': _planId,
        'phaseId': _phaseId,
        'title': 'Transplanting - Greenhouse 1',
        'taskType': 'workload',
        'assignedStaffIds': ['staff-1'],
        'requiredHeadcount': 1,
        'assignedCount': 1,
        'status': 'done',
        'approvalStatus': 'approved',
        'startDate': formatDateInput(alternateDate),
        'dueDate': formatDateInput(alternateDate),
        'completedAt': '${formatDateInput(alternateDate)}T16:00:00.000Z',
      },
      {
        'id': 'task-2',
        'planId': _planId,
        'phaseId': _phaseId,
        'title': 'Transplanting - Greenhouse 2',
        'taskType': 'workload',
        'assignedStaffIds': ['staff-1'],
        'requiredHeadcount': 1,
        'assignedCount': 1,
        'status': 'done',
        'approvalStatus': 'approved',
        'startDate': formatDateInput(today),
        'dueDate': formatDateInput(today),
        'completedAt': '${formatDateInput(today)}T18:00:00.000Z',
      },
    ],
    'timelineRows': [
      {
        'id': 'row-1',
        'planId': _planId,
        'taskId': 'task-1',
        'workDate': formatDateInput(alternateDate),
        'taskTitle': 'Transplanting - Greenhouse 1',
        'phaseName': 'Transplant Establishment',
        'farmerName': 'Odey Musse Ipo',
        'actualPlots': 5,
        'proofCount': 1,
        'approvalState': 'approved',
        'approvedAt': '${formatDateInput(alternateDate)}T16:00:00.000Z',
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

ProductionPlanDetail _buildAssignmentApprovedDetail() {
  final today = _today();
  return ProductionPlanDetail.fromJson({
    'plan': {
      'id': _planId,
      'businessId': 'business-1',
      'estateAssetId': 'estate-1',
      'productId': 'product-1',
      'domainContext': 'farm',
      'title': 'Pepper Production',
      'status': 'active',
    },
    'phases': [
      {
        'id': _phaseId,
        'planId': _planId,
        'name': 'Transplant Establishment',
        'phaseType': 'finite',
        'order': 1,
        'startDate': formatDateInput(today),
        'endDate': formatDateInput(today),
        'status': 'active',
      },
    ],
    'tasks': [
      {
        'id': 'task-assignment-approved',
        'planId': _planId,
        'phaseId': _phaseId,
        'title': 'Supervise',
        'taskType': 'event',
        'assignedStaffIds': ['staff-1'],
        'requiredHeadcount': 1,
        'assignedCount': 1,
        'status': 'pending',
        'approvalStatus': 'approved',
        'startDate': formatDateInput(today),
        'dueDate': formatDateInput(today),
      },
    ],
    'timelineRows': const [],
    'staffProfiles': [
      {
        'id': 'staff-1',
        'userId': 'user-1',
        'staffRole': 'supervisor',
        'status': 'active',
        'estateAssetId': 'estate-1',
        'user': {'name': 'Muhammad Umar Ribadu', 'email': 'umar@test.local'},
      },
    ],
  });
}

ProductionPlanDetail _buildEmptyPhaseDetail() {
  final today = _today();
  return ProductionPlanDetail.fromJson({
    'plan': {
      'id': _planId,
      'businessId': 'business-1',
      'estateAssetId': 'estate-1',
      'productId': 'product-1',
      'domainContext': 'farm',
      'title': 'Pepper Production',
      'status': 'active',
    },
    'phases': [
      {
        'id': _phaseId,
        'planId': _planId,
        'name': 'Transplant Establishment',
        'phaseType': 'finite',
        'order': 1,
        'startDate': formatDateInput(today),
        'endDate': formatDateInput(today),
        'status': 'active',
      },
    ],
    'tasks': const [],
    'timelineRows': const [],
    'staffProfiles': const [],
  });
}

void main() {
  testWidgets('defaults to all dates with collapsed search controls', (
    tester,
  ) async {
    final alternateDateLabel = formatDateInput(_alternateDate(_today()));
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productionPlanDetailProvider(
            _planId,
          ).overrideWith((ref) async => _buildPlanDetail()),
        ],
        child: const MaterialApp(
          home: ProductionPhaseDetailScreen(planId: _planId, phaseId: _phaseId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('phase-task-date-filter')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phase-task-search-field')), findsNothing);
    expect(find.byKey(const ValueKey('phase-task-date-value')), findsOneWidget);

    final initialDateText = tester.widget<Text>(
      find.byKey(const ValueKey('phase-task-date-value')),
    );
    expect(initialDateText.data, 'All dates');
    expect(find.text('Transplanting - Greenhouse 2'), findsOneWidget);
    expect(find.text('Transplanting - Greenhouse 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('phase-task-date-filter')));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    await tester.tap(
      find
          .descendant(
            of: dialog,
            matching: find.text('${_alternateDate(_today()).day}'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final updatedDateText = tester.widget<Text>(
      find.byKey(const ValueKey('phase-task-date-value')),
    );
    expect(updatedDateText.data, alternateDateLabel);
    expect(find.text('Transplanting - Greenhouse 2'), findsNothing);
    expect(find.text('Transplanting - Greenhouse 1'), findsOneWidget);
  });

  testWidgets(
    'assignment approval alone does not mark a task done in phase detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productionPlanDetailProvider(
              _planId,
            ).overrideWith((ref) async => _buildAssignmentApprovedDetail()),
          ],
          child: const MaterialApp(
            home: ProductionPhaseDetailScreen(
              planId: _planId,
              phaseId: _phaseId,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Approved / done 1'), findsNothing);
      expect(find.textContaining('Assigned / idle'), findsOneWidget);
      expect(find.text('Assignment approved'), findsOneWidget);
      expect(find.text('Progress: Assigned and waiting'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    },
  );

  testWidgets('empty phase still exposes add day task action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productionPlanDetailProvider(
            _planId,
          ).overrideWith((ref) async => _buildEmptyPhaseDetail()),
        ],
        child: const MaterialApp(
          home: ProductionPhaseDetailScreen(planId: _planId, phaseId: _phaseId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add day task'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Add day task'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('No tasks in this phase'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('No tasks in this phase'), findsOneWidget);
  });
}
