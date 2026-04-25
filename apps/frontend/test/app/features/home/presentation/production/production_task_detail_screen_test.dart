// WHAT: Verifies task detail derived approval and completion labels.
// WHY: Assignment approval must not be rendered as proof-backed completion.
// HOW: The test builds a task with assignment approval but no progress rows and
// confirms the UI stays pending/assigned instead of approved/completed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_task_detail_screen.dart';

const _planId = 'plan-1';
const _phaseId = 'phase-1';
const _taskId = 'task-assignment-approved';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

ProductionPlanDetail _buildAssignmentApprovedTaskDetail() {
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
        'id': _taskId,
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

void main() {
  testWidgets(
    'task detail keeps assignment-approved tasks pending without progress',
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
            ).overrideWith((ref) async => _buildAssignmentApprovedTaskDetail()),
          ],
          child: const MaterialApp(
            home: ProductionTaskDetailScreen(planId: _planId, taskId: _taskId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Approval: Assignment approved'), findsOneWidget);
      expect(find.text('Status: Assigned'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Not completed'), findsOneWidget);
      expect(find.text('No activity yet'), findsWidgets);
    },
  );
}
