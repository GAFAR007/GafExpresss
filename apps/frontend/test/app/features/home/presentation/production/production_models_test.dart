import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';

ProductionTaskProgressProofInput _proof(String filename) {
  return ProductionTaskProgressProofInput(
    bytes: const [1, 2, 3],
    filename: filename,
    sizeBytes: 3,
  );
}

void main() {
  group('requiredTaskProgressProofCount', () {
    test('returns zero for zero or negative contributions', () {
      expect(requiredTaskProgressProofMediaCount(0), 0);
      expect(requiredTaskProgressProofCount(0), 0);
      expect(requiredTaskProgressProofCount(-1), 0);
    });

    test(
      'requires one picture and one video for each rounded-up contribution',
      () {
        expect(requiredTaskProgressProofMediaCount(1), 1);
        expect(requiredTaskProgressProofCount(1), 2);
        expect(requiredTaskProgressProofCount(1.5), 4);
        expect(requiredTaskProgressProofCount(2.5), 6);
        expect(requiredTaskProgressProofCount(3.5), 8);
      },
    );
  });

  group('hasRequiredTaskProgressProofMix', () {
    test('accepts the required picture and video split', () {
      expect(
        hasRequiredTaskProgressProofMix([
          _proof('proof-1.jpg'),
          _proof('proof-1.mp4'),
          _proof('proof-2.jpg'),
          _proof('proof-2.mov'),
        ], 4),
        isTrue,
      );
    });

    test('rejects proofs when the picture and video mix is incomplete', () {
      expect(
        hasRequiredTaskProgressProofMix([
          _proof('proof-1.jpg'),
          _proof('proof-2.jpg'),
          _proof('proof-3.jpg'),
          _proof('proof-1.mp4'),
        ], 4),
        isFalse,
      );
    });
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

  group('ProductionTimelineRow.fromJson', () {
    test('preserves calendar work dates for UTC midnight payloads', () {
      final row = ProductionTimelineRow.fromJson({
        'id': 'row-1',
        'planId': 'plan-1',
        'taskId': 'task-1',
        'workDate': '2026-04-24T00:00:00.000Z',
        'taskTitle': 'Transplant block A',
      });

      expect(row.workDate, isNotNull);
      expect(row.workDate!.isUtc, isFalse);
      expect(row.workDate!.year, 2026);
      expect(row.workDate!.month, 4);
      expect(row.workDate!.day, 24);
    });
  });
}
