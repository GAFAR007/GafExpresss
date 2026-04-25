import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_workspace_screen.dart';
import 'package:frontend/app/theme/app_theme.dart';

const _step1Title = "Step 1: How many units did you complete?";
const _step2Title = "Step 2: Upload proof";
const _step3Title = "Step 3: Record activity";
const _step4Title = "Step 4: Add notes";

const _notesLabel = "Daily notes";
const _addProofsLabel = "Add proofs";

ProductionPlan _buildPlan() {
  return const ProductionPlan(
    id: "plan-1",
    businessId: "business-1",
    estateAssetId: "estate-1",
    productId: "product-1",
    domainContext: "farm",
    title: "Pepper Production",
    startDate: null,
    endDate: null,
    status: "active",
    createdBy: "owner-1",
    notes: "Daily production",
    plantingTargets: ProductionPlantingTargets(
      materialType: "seed",
      plannedPlantingQuantity: 2000,
      plannedPlantingUnit: "seeds",
      estimatedHarvestQuantity: 500,
      estimatedHarvestUnit: "crates",
    ),
    workloadContext: ProductionWorkloadContext(
      workUnitLabel: "greenhouses",
      workUnitType: "greenhouse",
      totalWorkUnits: 5,
      minStaffPerUnit: 1,
      maxStaffPerUnit: 2,
      activeStaffAvailabilityPercent: 100,
      hasConfirmedWorkloadContext: true,
    ),
    aiGenerated: false,
    createdAt: null,
    updatedAt: null,
    lastDraftSavedAt: null,
    lastDraftSavedBy: null,
    draftRevisionCount: 0,
    draftAuditTrailCount: 0,
    confidence: null,
  );
}

ProductionTask _buildTask() {
  return const ProductionTask(
    id: "task-1",
    planId: "plan-1",
    phaseId: "phase-1",
    title: "Transplant peppers",
    roleRequired: "farmer",
    assignedStaffId: "staff-1",
    assignedStaffIds: ["staff-1"],
    assignedUnitIds: <String>[],
    requiredHeadcount: 1,
    assignedCount: 1,
    weight: 5,
    manualSortOrder: 0,
    taskType: "",
    sourceTemplateKey: "",
    recurrenceGroupKey: "",
    occurrenceIndex: 0,
    startDate: null,
    dueDate: null,
    status: "in_progress",
    completedAt: null,
    instructions: "Move seedlings to the nursery beds.",
    dependencies: <String>[],
    approvalStatus: "approved",
    rejectionReason: "",
  );
}

ProductionAttendanceRecord _buildAttendance(DateTime workDate) {
  return ProductionAttendanceRecord(
    id: "attendance-1",
    planId: "plan-1",
    taskId: "task-1",
    staffProfileId: "staff-1",
    workDate: workDate,
    clockInAt: workDate.add(const Duration(hours: 8)),
    clockOutAt: null,
    durationMinutes: 0,
    notes: "Clocked in",
    createdAt: workDate,
    proofUrl: null,
    proofPublicId: null,
    proofFilename: null,
    proofMimeType: null,
    proofSizeBytes: null,
    proofUploadedAt: null,
    proofUploadedBy: null,
  );
}

ProductionAttendanceRecord _buildOpenAttendance({
  required String id,
  required DateTime workDate,
  required String taskId,
  required DateTime clockInAt,
}) {
  return ProductionAttendanceRecord(
    id: id,
    planId: "plan-1",
    taskId: taskId,
    staffProfileId: "staff-1",
    workDate: workDate,
    clockInAt: clockInAt,
    clockOutAt: null,
    durationMinutes: 0,
    notes: "Clocked in",
    createdAt: workDate,
    proofUrl: null,
    proofPublicId: null,
    proofFilename: null,
    proofMimeType: null,
    proofSizeBytes: null,
    proofUploadedAt: null,
    proofUploadedBy: null,
  );
}

ProductionTaskDayLedger _buildLedger(DateTime workDate) {
  return ProductionTaskDayLedger(
    id: "ledger-1",
    planId: "plan-1",
    taskId: "task-1",
    workDate: workDate,
    unitType: "greenhouses",
    unitTarget: 5,
    unitCompleted: 0,
    unitRemaining: 5,
    status: "active",
    activityTargets: const ProductionTaskDayActivityTargets(
      planted: 2000,
      transplanted: 1500,
      harvested: 500,
    ),
    activityCompleted: const ProductionTaskDayActivityTotals(
      planted: 0,
      transplanted: 0,
      harvested: 0,
    ),
    activityRemaining: const ProductionTaskDayActivityTargets(
      planted: 2000,
      transplanted: 1500,
      harvested: 500,
    ),
    activityUnits: const ProductionTaskDayActivityUnits(
      planted: "seeds",
      transplanted: "seedlings",
      harvested: "crates",
    ),
    createdAt: workDate,
    updatedAt: workDate,
  );
}

BusinessStaffProfileSummary _buildStaff() {
  return const BusinessStaffProfileSummary(
    id: "staff-1",
    userId: "user-1",
    staffRole: "farmer",
    status: "active",
    estateAssetId: "estate-1",
    userName: "Odey Musse Ipo",
    userEmail: "odey@test.local",
    userPhone: null,
  );
}

ProductionTaskProgressProofInput _proof(String filename) {
  return ProductionTaskProgressProofInput(
    bytes: const [1, 2, 3, 4],
    filename: filename,
    sizeBytes: 4,
  );
}

Finder _choiceChipWithLabel(String label) {
  return find.widgetWithText(ChoiceChip, label);
}

Future<void> _tapChoiceChip(WidgetTester tester, String label) async {
  final chip = _choiceChipWithLabel(label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> _pumpWizardHost(
  WidgetTester tester, {
  required Size size,
  required bool useBottomSheet,
  required ProductionClockOutWizardSheet wizard,
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? ThemeData.light(useMaterial3: true),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: FilledButton(
                onPressed: () {
                  if (useBottomSheet) {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) {
                        return SizedBox(
                          height: size.height * 0.96,
                          child: wizard,
                        );
                      },
                    );
                    return;
                  }

                  showDialog<void>(
                    context: context,
                    builder: (_) {
                      return Dialog(
                        child: SizedBox(width: 720, height: 820, child: wizard),
                      );
                    },
                  );
                },
                child: const Text("Open"),
              ),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text("Open"));
  await tester.pumpAndSettle();
}

void main() {
  final workDate = DateTime.utc(2026, 4, 13);
  final plan = _buildPlan();
  final task = _buildTask();
  final attendance = _buildAttendance(workDate);
  final ledger = _buildLedger(workDate);
  final staff = _buildStaff();

  test(
    "workspace attendance display prefers an unresolved open session over a same-day completed row",
    () {
      final completedTaskAttendance = ProductionAttendanceRecord(
        id: "attendance-complete",
        planId: "plan-1",
        taskId: "task-1",
        staffProfileId: "staff-1",
        workDate: workDate,
        clockInAt: workDate.add(const Duration(hours: 8)),
        clockOutAt: workDate.add(const Duration(hours: 12)),
        durationMinutes: 240,
        notes: "Completed shift",
        createdAt: workDate,
        proofUrl: null,
        proofPublicId: null,
        proofFilename: null,
        proofMimeType: null,
        proofSizeBytes: null,
        proofUploadedAt: null,
        proofUploadedBy: null,
      );
      final openAttendanceFromPreviousDay = _buildOpenAttendance(
        id: "attendance-open",
        workDate: workDate.subtract(const Duration(days: 1)),
        taskId: "task-other",
        clockInAt: workDate.subtract(const Duration(days: 1, hours: 2)),
      );

      final resolvedAttendance = resolveProductionWorkspaceDisplayAttendance(
        attendanceRecords: [
          completedTaskAttendance,
          openAttendanceFromPreviousDay,
        ],
        staffProfileId: staff.id,
        day: workDate,
        taskId: task.id,
      );

      expect(resolvedAttendance?.id, "attendance-open");
      expect(resolvedAttendance?.clockOutAt, isNull);
    },
  );

  test(
    "clock-out wizard resolves an open attendance session from another task before save",
    () {
      final openAttendanceFromOtherTask = _buildOpenAttendance(
        id: "attendance-open-other-task",
        workDate: workDate,
        taskId: "task-other",
        clockInAt: workDate.add(const Duration(hours: 7, minutes: 49)),
      );

      final resolvedAttendance =
          resolveProductionWorkspaceActiveClockOutAttendance(
            attendanceRecords: [openAttendanceFromOtherTask],
            staffProfileId: staff.id,
            day: workDate,
            taskId: task.id,
          );

      expect(resolvedAttendance?.id, "attendance-open-other-task");
      expect(resolvedAttendance?.clockInAt, isNotNull);
      expect(resolvedAttendance?.clockOutAt, isNull);
    },
  );

  testWidgets(
    "clock-out wizard exposes decimal quick-pick options for low unit counts",
    (tester) async {
      await _pumpWizardHost(
        tester,
        size: const Size(1280, 900),
        useBottomSheet: false,
        wizard: ProductionClockOutWizardSheet(
          workDate: workDate,
          task: task,
          plan: plan,
          timelineRows: const <ProductionTimelineRow>[],
          taskDayLedgers: [ledger],
          attendanceRecords: [attendance],
          activeAttendance: attendance,
          staffMap: {staff.id: staff},
          planUnitLabelById: const <String, String>{},
          fallbackTotalUnits: 5,
          fallbackWorkUnitLabel: "greenhouses",
          staffId: staff.id,
          onPickProofs: () async => const <ProductionTaskProgressProofInput>[],
          onSubmit: (_) async {},
        ),
      );

      expect(_choiceChipWithLabel("0"), findsOneWidget);
      expect(_choiceChipWithLabel("0.1"), findsOneWidget);
      expect(_choiceChipWithLabel("0.5"), findsOneWidget);
      expect(_choiceChipWithLabel("0.7"), findsOneWidget);
      expect(_choiceChipWithLabel("1"), findsOneWidget);
    },
  );

  testWidgets(
    "clock-out wizard keeps heading and chip text readable in dark theme",
    (tester) async {
      await _pumpWizardHost(
        tester,
        size: const Size(1280, 900),
        useBottomSheet: false,
        theme: AppTheme.dark(),
        wizard: ProductionClockOutWizardSheet(
          workDate: workDate,
          task: task,
          plan: plan,
          timelineRows: const <ProductionTimelineRow>[],
          taskDayLedgers: [ledger],
          attendanceRecords: [attendance],
          activeAttendance: attendance,
          staffMap: {staff.id: staff},
          planUnitLabelById: const <String, String>{},
          fallbackTotalUnits: 5,
          fallbackWorkUnitLabel: "greenhouses",
          staffId: staff.id,
          onPickProofs: () async => const <ProductionTaskProgressProofInput>[],
          onSubmit: (_) async {},
        ),
      );

      final titleText = tester.widget<Text>(find.text(_step1Title));
      final unitsTitle = tester.widget<Text>(find.text("Units completed now"));
      final amountChip = tester.widget<ChoiceChip>(_choiceChipWithLabel("1"));
      final dialogContext = tester.element(find.text(_step1Title));
      final colorScheme = Theme.of(dialogContext).colorScheme;

      expect(titleText.style?.color, colorScheme.onSurface);
      expect(unitsTitle.style?.color, colorScheme.onSurface);
      expect(amountChip.labelStyle?.color, colorScheme.onSurface);
    },
  );

  testWidgets(
    "guided clock-out reveals one step at a time and finishes with a single save action",
    (tester) async {
      ProductionTaskLogProgressInput? submittedInput;

      await _pumpWizardHost(
        tester,
        size: const Size(1280, 900),
        useBottomSheet: false,
        wizard: ProductionClockOutWizardSheet(
          workDate: workDate,
          task: task,
          plan: plan,
          timelineRows: const <ProductionTimelineRow>[],
          taskDayLedgers: [ledger],
          attendanceRecords: [attendance],
          activeAttendance: attendance,
          staffMap: {staff.id: staff},
          planUnitLabelById: const <String, String>{},
          fallbackTotalUnits: 5,
          fallbackWorkUnitLabel: "greenhouses",
          staffId: staff.id,
          onPickProofs: () async => [
            _proof("proof-1.jpg"),
            _proof("proof-1.mp4"),
          ],
          onSubmit: (input) async {
            submittedInput = input;
          },
        ),
      );

      expect(find.text(_step1Title), findsOneWidget);
      expect(find.text(_step2Title), findsNothing);
      expect(find.text(_step3Title), findsNothing);
      expect(find.text(_step4Title), findsNothing);

      await _tapChoiceChip(tester, "1");
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step1Title), findsNothing);
      expect(find.text(_step2Title), findsOneWidget);
      expect(find.text(_step3Title), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, _addProofsLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step2Title), findsNothing);
      expect(find.text(_step3Title), findsOneWidget);
      expect(find.text(_step4Title), findsNothing);

      await _tapChoiceChip(tester, "Planted");
      await _tapChoiceChip(tester, "500 seeds");
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step3Title), findsNothing);
      expect(find.text(_step4Title), findsOneWidget);
      expect(find.widgetWithText(FilledButton, "Clock out"), findsNothing);
      expect(find.widgetWithText(FilledButton, "Finish"), findsOneWidget);

      await tester.enterText(
        _textFieldWithLabel(_notesLabel),
        "Seedlings moved.",
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, "Finish"));
      await tester.pumpAndSettle();

      expect(submittedInput, isNotNull);
      expect(submittedInput!.unitContribution, 1);
      expect(submittedInput!.proofs.length, 2);
      expect(submittedInput!.activityType, "planted");
      expect(submittedInput!.activityQuantity, 500);
      expect(submittedInput!.quantityUnit, "seeds");
      expect(submittedInput!.delayReason, "none");
      expect(submittedInput!.notes, "Seedlings moved.");
      expect(find.text(_step4Title), findsNothing);
    },
  );

  testWidgets(
    "proof step requires matching picture and video counts for the selected units",
    (tester) async {
      await _pumpWizardHost(
        tester,
        size: const Size(1280, 900),
        useBottomSheet: false,
        wizard: ProductionClockOutWizardSheet(
          workDate: workDate,
          task: task,
          plan: plan,
          timelineRows: const <ProductionTimelineRow>[],
          taskDayLedgers: [ledger],
          attendanceRecords: [attendance],
          activeAttendance: attendance,
          staffMap: {staff.id: staff},
          planUnitLabelById: const <String, String>{},
          fallbackTotalUnits: 5,
          fallbackWorkUnitLabel: "greenhouses",
          staffId: staff.id,
          onPickProofs: () async => [
            _proof("proof-1.jpg"),
            _proof("proof-1.mp4"),
            _proof("proof-2.jpg"),
            _proof("proof-2.mp4"),
            _proof("proof-3.jpg"),
            _proof("proof-3.mp4"),
            _proof("proof-4.jpg"),
            _proof("proof-4.mp4"),
            _proof("proof-5.jpg"),
            _proof("proof-5.mp4"),
          ],
          onSubmit: (_) async {},
        ),
      );

      await _tapChoiceChip(tester, "5");
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Select exactly 10 proofs: 5 pictures and 5 videos of the greenhouse, plot, or unit.",
        ),
        findsOneWidget,
      );
      expect(find.text("0 / 5"), findsNWidgets(2));

      await tester.tap(find.widgetWithText(OutlinedButton, _addProofsLabel));
      await tester.pumpAndSettle();

      expect(find.text("5 / 5"), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step3Title), findsOneWidget);
    },
  );

  testWidgets("successful proof replacement clears a stale proof error banner", (
    tester,
  ) async {
    var pickAttempts = 0;

    await _pumpWizardHost(
      tester,
      size: const Size(1280, 900),
      useBottomSheet: false,
      wizard: ProductionClockOutWizardSheet(
        workDate: workDate,
        task: task,
        plan: plan,
        timelineRows: const <ProductionTimelineRow>[],
        taskDayLedgers: [ledger],
        attendanceRecords: [attendance],
        activeAttendance: attendance,
        staffMap: {staff.id: staff},
        planUnitLabelById: const <String, String>{},
        fallbackTotalUnits: 5,
        fallbackWorkUnitLabel: "greenhouses",
        staffId: staff.id,
        onPickProofs: () async {
          pickAttempts += 1;
          if (pickAttempts == 1) {
            throw Exception(
              "Upload every required picture and video for the completed units.",
            );
          }
          return [
            _proof("proof-1.jpg"),
            _proof("proof-1.mp4"),
            _proof("proof-2.jpg"),
            _proof("proof-2.mp4"),
            _proof("proof-3.jpg"),
            _proof("proof-3.mp4"),
            _proof("proof-4.jpg"),
            _proof("proof-4.mp4"),
            _proof("proof-5.jpg"),
            _proof("proof-5.mp4"),
          ];
        },
        onSubmit: (_) async {},
      ),
    );

    await _tapChoiceChip(tester, "5");
    await tester.tap(find.widgetWithText(FilledButton, "Continue"));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, _addProofsLabel));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Upload every required picture and video"),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, _addProofsLabel));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Upload every required picture and video"),
      findsNothing,
    );
  });

  testWidgets(
    "mobile clock-out sheet keeps the user in proof step after a failed upload and allows retry",
    (tester) async {
      var pickAttempts = 0;
      var submitCalls = 0;

      await _pumpWizardHost(
        tester,
        size: const Size(390, 844),
        useBottomSheet: true,
        wizard: ProductionClockOutWizardSheet(
          workDate: workDate,
          task: task,
          plan: plan,
          timelineRows: const <ProductionTimelineRow>[],
          taskDayLedgers: [ledger],
          attendanceRecords: [attendance],
          activeAttendance: attendance,
          staffMap: {staff.id: staff},
          planUnitLabelById: const <String, String>{},
          fallbackTotalUnits: 5,
          fallbackWorkUnitLabel: "greenhouses",
          staffId: staff.id,
          onPickProofs: () async {
            pickAttempts += 1;
            if (pickAttempts == 1) {
              throw Exception("Upload failed");
            }
            return [_proof("proof-1.jpg"), _proof("proof-1.mp4")];
          },
          onSubmit: (_) async {
            submitCalls += 1;
          },
        ),
      );

      await _tapChoiceChip(tester, "1");
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step2Title), findsOneWidget);
      expect(find.text("Step 2 of 4"), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, _addProofsLabel));
      await tester.pumpAndSettle();

      expect(find.textContaining("Upload failed"), findsOneWidget);
      expect(find.text(_step2Title), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, _addProofsLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step3Title), findsOneWidget);
      expect(pickAttempts, 2);
      expect(submitCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    "recoverable save errors preserve wizard state and allow finishing without a second clock-out action",
    (tester) async {
      var submitAttempts = 0;
      final submittedInputs = <ProductionTaskLogProgressInput>[];

      await _pumpWizardHost(
        tester,
        size: const Size(1180, 900),
        useBottomSheet: false,
        wizard: ProductionClockOutWizardSheet(
          workDate: workDate,
          task: task,
          plan: plan,
          timelineRows: const <ProductionTimelineRow>[],
          taskDayLedgers: [ledger],
          attendanceRecords: [attendance],
          activeAttendance: attendance,
          staffMap: {staff.id: staff},
          planUnitLabelById: const <String, String>{},
          fallbackTotalUnits: 5,
          fallbackWorkUnitLabel: "greenhouses",
          staffId: staff.id,
          onPickProofs: () async => [
            _proof("proof-1.jpg"),
            _proof("proof-1.mp4"),
          ],
          onSubmit: (input) async {
            submitAttempts += 1;
            if (submitAttempts == 1) {
              throw Exception("Temporary save error");
            }
            submittedInputs.add(input);
          },
        ),
      );

      await _tapChoiceChip(tester, "1");
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, _addProofsLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      await _tapChoiceChip(tester, "No quantity update");
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      await tester.enterText(
        _textFieldWithLabel(_notesLabel),
        "Keep this note",
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, "Finish"));
      await tester.pumpAndSettle();

      expect(find.text(_step4Title), findsOneWidget);
      expect(find.textContaining("Temporary save error"), findsOneWidget);
      expect(find.text("Keep this note"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, "Clock out"), findsNothing);
      expect(find.widgetWithText(FilledButton, "Finish"), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, "Finish"));
      await tester.pumpAndSettle();

      expect(submitAttempts, 2);
      expect(submittedInputs, hasLength(1));
      expect(submittedInputs.single.unitContribution, 1);
      expect(submittedInputs.single.activityType, "none");
      expect(submittedInputs.single.notes, "Keep this note");
      expect(find.text(_step4Title), findsNothing);
    },
  );
}
