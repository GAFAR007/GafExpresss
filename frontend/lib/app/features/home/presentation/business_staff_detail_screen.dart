/// lib/app/features/home/presentation/business_staff_detail_screen.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Staff profile detail shell screen.
///
/// WHY:
/// - Provides the drilldown destination for staff directory.
/// - Reserves space for profile, attendance, and compensation modules.
///
/// HOW:
/// - Renders header + section cards with "coming soon" placeholders.
/// - Logs build and navigation actions for diagnostics.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_sections.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _logTag = "STAFF_DETAIL";
const String _logBuild = "build()";
const String _logBackTap = "back_tap";
const String _extraStaffIdKey = "staffProfileId";
const String _screenTitle = "Staff profile";
const String _screenHelper =
    "Review employment, compensation, attendance, and documents.";
const String _summaryTitle = "Summary";
const String _summaryHelper = "Profile overview and key details.";
const String _employmentTitle = "Employment";
const String _employmentHelper = "Role, estate scope, and status.";
const String _compTitle = "Compensation";
const String _compHelper = "Salary, cadence, and pay history.";
const String _attendanceTitle = "Attendance";
const String _attendanceHelper = "Clock-in history and KPIs.";
const String _documentsTitle = "Documents";
const String _documentsHelper = "Contracts and staff files.";
const String _placeholderText = "Coming soon";

class BusinessStaffDetailScreen extends StatelessWidget {
  final String staffProfileId;

  const BusinessStaffDetailScreen({
    super.key,
    required this.staffProfileId,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Track screen renders to debug layout and routing issues.
    AppDebug.log(
      _logTag,
      _logBuild,
      extra: {_extraStaffIdKey: staffProfileId},
    );
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // WHY: Log navigation so routing issues are visible.
            AppDebug.log(_logTag, _logBackTap);
            context.pop();
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            _screenTitle,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _screenHelper,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const StaffDirectorySectionCard(
            title: _summaryTitle,
            helper: _summaryHelper,
            placeholderText: _placeholderText,
          ),
          const SizedBox(height: AppSpacing.md),
          const StaffDirectorySectionCard(
            title: _employmentTitle,
            helper: _employmentHelper,
            placeholderText: _placeholderText,
          ),
          const SizedBox(height: AppSpacing.md),
          const StaffDirectorySectionCard(
            title: _compTitle,
            helper: _compHelper,
            placeholderText: _placeholderText,
          ),
          const SizedBox(height: AppSpacing.md),
          StaffDirectorySectionCard(
            title: _attendanceTitle,
            helper: _attendanceHelper,
            placeholderText: _placeholderText,
            child: BusinessStaffAttendanceSection(
              staffProfileId: staffProfileId,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const StaffDirectorySectionCard(
            title: _documentsTitle,
            helper: _documentsHelper,
            placeholderText: _placeholderText,
          ),
        ],
      ),
    );
  }
}
