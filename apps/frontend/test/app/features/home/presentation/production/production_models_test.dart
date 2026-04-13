import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';

void main() {
  group('requiredTaskProgressProofCount', () {
    test('returns zero for zero or negative contributions', () {
      expect(requiredTaskProgressProofCount(0), 0);
      expect(requiredTaskProgressProofCount(-1), 0);
    });

    test(
      'rounds positive decimal contributions up to the next whole proof',
      () {
        expect(requiredTaskProgressProofCount(1), 1);
        expect(requiredTaskProgressProofCount(1.5), 2);
        expect(requiredTaskProgressProofCount(2.5), 3);
        expect(requiredTaskProgressProofCount(3.5), 4);
      },
    );
  });

  group('ProductionTaskDayLedger.fromJson', () {
    test('parses shared unit and activity totals separately', () {
      final ledger = ProductionTaskDayLedger.fromJson({
        'id': 'ledger-1',
        'planId': 'plan-1',
        'taskId': 'task-1',
        'workDate': '2026-04-12T00:00:00.000Z',
        'unitType': 'plots',
        'unitTarget': 5,
        'unitCompleted': 3.5,
        'unitRemaining': 1.5,
        'status': 'in_progress',
        'activityTargets': {
          'planted': 0,
          'transplanted': 2000,
          'harvested': 500,
        },
        'activityCompleted': {
          'planted': 0,
          'transplanted': 500,
          'harvested': 0,
        },
        'activityRemaining': {
          'planted': 0,
          'transplanted': 1500,
          'harvested': 500,
        },
        'activityUnits': {
          'planted': 'seeds',
          'transplanted': 'seeds',
          'harvested': 'crates',
        },
        'createdAt': '2026-04-12T08:00:00.000Z',
        'updatedAt': '2026-04-12T09:00:00.000Z',
      });

      expect(ledger.unitTarget, 5);
      expect(ledger.unitCompleted, 3.5);
      expect(ledger.unitRemaining, 1.5);
      expect(ledger.activityCompleted.transplanted, 500);
      expect(ledger.activityRemaining.transplanted, 1500);
      expect(ledger.activityUnits.transplanted, 'seeds');
      expect(ledger.status, 'in_progress');
    });
  });
}
