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
  const transparentPngBytes = <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    13,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    248,
    15,
    4,
    0,
    9,
    251,
    3,
    253,
    167,
    69,
    129,
    29,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ];
  final bytes = filename.toLowerCase().endsWith(".mp4")
      ? const <int>[0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50]
      : transparentPngBytes;
  return ProductionTaskProgressProofInput(
    bytes: bytes,
    filename: filename,
    sizeBytes: bytes.length,
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

Finder _completedAmountDropdown() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<num> &&
        widget.decoration.labelText == "Completed amount",
  );
}

Future<void> _selectCompletedAmount(WidgetTester tester, num amount) async {
  final dropdown = tester.widget<DropdownButtonFormField<num>>(
    _completedAmountDropdown(),
  );
  dropdown.onChanged?.call(amount);
  await tester.pumpAndSettle();
}

Future<ProductionTaskProgressProofInput?> _captureProof({
  required bool isVideo,
  required int unitNumber,
}) async {
  return _proof("proof-$unitNumber.${isVideo ? 'mp4' : 'jpg'}");
}

Future<void> _tapFirstProofButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(OutlinedButton, label).first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapFirstTooltip(WidgetTester tester, String message) async {
  final control = find.byTooltip(message).first;
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _captureProofsForUnits(WidgetTester tester, int unitCount) async {
  for (var index = 0; index < unitCount; index++) {
    await _tapFirstProofButton(tester, "Upload image");
    await _tapFirstProofButton(tester, "Upload video");
  }
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

  testWidgets("clock-out wizard uses a compact dropdown for low unit counts", (
    tester,
  ) async {
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

    expect(_completedAmountDropdown(), findsOneWidget);
    expect(_choiceChipWithLabel("0.1"), findsNothing);
    expect(find.text("5 greenhouses"), findsWidgets);
  });

  testWidgets("clock-out wizard defaults the completed amount to the maximum", (
    tester,
  ) async {
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

    expect(find.text("5 greenhouses"), findsWidgets);
    expect(
      find.text("After save, shared remaining will be 0 greenhouses."),
      findsOneWidget,
    );
  });

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
      final dialogContext = tester.element(find.text(_step1Title));
      final colorScheme = Theme.of(dialogContext).colorScheme;

      expect(titleText.style?.color, colorScheme.onSurface);
      expect(unitsTitle.style?.color, colorScheme.onSurface);
      expect(_completedAmountDropdown(), findsOneWidget);
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
          onCaptureProof: _captureProof,
          onSubmit: (input) async {
            submittedInput = input;
          },
        ),
      );

      expect(find.text(_step1Title), findsOneWidget);
      expect(find.text(_step2Title), findsNothing);
      expect(find.text(_step3Title), findsNothing);
      expect(find.text(_step4Title), findsNothing);

      await _selectCompletedAmount(tester, 1);
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step1Title), findsNothing);
      expect(find.text(_step2Title), findsOneWidget);
      expect(find.text(_step3Title), findsNothing);

      await _captureProofsForUnits(tester, 1);
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
          onCaptureProof: _captureProof,
          onSubmit: (_) async {},
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text("Greenhouse 1"), findsOneWidget);
      expect(find.text("Greenhouse 5"), findsOneWidget);
      expect(find.text("0/1 image"), findsNWidgets(5));
      expect(find.text("0/1 video"), findsNWidgets(5));
      expect(
        find.widgetWithText(OutlinedButton, "Upload image"),
        findsNWidgets(5),
      );
      expect(
        find.widgetWithText(OutlinedButton, "Upload video"),
        findsNWidgets(5),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, "Continue"))
            .onPressed,
        isNull,
      );

      await _tapFirstProofButton(tester, "Upload image");

      expect(find.text("Image"), findsOneWidget);
      expect(find.text("Video"), findsNothing);

      await _tapFirstProofButton(tester, "Upload video");

      expect(find.text("Image"), findsOneWidget);
      expect(find.text("Video"), findsOneWidget);

      await _captureProofsForUnits(tester, 4);

      expect(find.text("1/1 ready"), findsNWidgets(10));
      expect(find.text("Replace image"), findsNWidgets(5));
      expect(find.text("Replace video"), findsNWidgets(5));
      expect(find.text("Image"), findsNWidgets(5));
      expect(find.text("Video"), findsNWidgets(5));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, "Continue"))
            .onPressed,
        isNotNull,
      );

      await _tapFirstTooltip(tester, "Remove video proof");

      expect(find.text("Replace image"), findsNWidgets(5));
      expect(find.text("Replace video"), findsNWidgets(4));
      expect(find.text("Upload video"), findsOneWidget);
      expect(find.text("Video"), findsNWidgets(4));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, "Continue"))
            .onPressed,
        isNull,
      );

      await _tapFirstProofButton(tester, "Upload video");

      expect(find.text("Replace video"), findsNWidgets(5));
      expect(find.text("Video"), findsNWidgets(5));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, "Continue"))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step3Title), findsOneWidget);
    },
  );

  testWidgets("proof checklist uses the configured work unit label", (
    tester,
  ) async {
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
        fallbackWorkUnitLabel: "plots",
        staffId: staff.id,
        onPickProofs: () async => const <ProductionTaskProgressProofInput>[],
        onSubmit: (_) async {},
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, "Continue"));
    await tester.pumpAndSettle();

    expect(find.text("Plot 1"), findsOneWidget);
    expect(find.text("Plot 5"), findsOneWidget);
    expect(
      find.text(
        "Upload one image and one video for each plot. Each upload replaces that unit’s previous file.",
      ),
      findsOneWidget,
    );
  });

  testWidgets("successful proof replacement clears a stale proof error banner", (
    tester,
  ) async {
    var captureAttempts = 0;

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
        onCaptureProof: ({required isVideo, required unitNumber}) async {
          captureAttempts += 1;
          if (captureAttempts == 1) {
            throw Exception(
              "Upload every required picture and video for the completed units.",
            );
          }
          return _proof("proof-$unitNumber.${isVideo ? 'mp4' : 'jpg'}");
        },
        onSubmit: (_) async {},
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, "Continue"));
    await tester.pumpAndSettle();

    await _tapFirstProofButton(tester, "Upload image");

    expect(
      find.textContaining("Upload every required picture and video"),
      findsOneWidget,
    );

    await _captureProofsForUnits(tester, 5);

    expect(
      find.textContaining("Upload every required picture and video"),
      findsNothing,
    );
  });

  testWidgets(
    "mobile clock-out sheet keeps the user in proof step after a failed upload and allows retry",
    (tester) async {
      var captureAttempts = 0;
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
          onCaptureProof: ({required isVideo, required unitNumber}) async {
            captureAttempts += 1;
            if (captureAttempts == 1) {
              throw Exception("Upload failed");
            }
            return _proof("proof-$unitNumber.${isVideo ? 'mp4' : 'jpg'}");
          },
          onSubmit: (_) async {
            submitCalls += 1;
          },
        ),
      );

      await _selectCompletedAmount(tester, 1);
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step2Title), findsOneWidget);
      expect(find.text("Step 2 of 4"), findsOneWidget);

      await _tapFirstProofButton(tester, "Upload image");

      expect(find.textContaining("Upload failed"), findsOneWidget);
      expect(find.text(_step2Title), findsOneWidget);

      await _captureProofsForUnits(tester, 1);
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      expect(find.text(_step3Title), findsOneWidget);
      expect(captureAttempts, 3);
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
          onCaptureProof: _captureProof,
          onSubmit: (input) async {
            submitAttempts += 1;
            if (submitAttempts == 1) {
              throw Exception("Temporary save error");
            }
            submittedInputs.add(input);
          },
        ),
      );

      await _selectCompletedAmount(tester, 1);
      await tester.tap(find.widgetWithText(FilledButton, "Continue"));
      await tester.pumpAndSettle();

      await _captureProofsForUnits(tester, 1);
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
