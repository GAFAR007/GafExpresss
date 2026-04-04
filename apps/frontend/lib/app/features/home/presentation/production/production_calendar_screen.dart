/// lib/app/features/home/presentation/production/production_calendar_screen.dart
/// ----------------------------------------------------------------------------
/// WHAT:
/// - Month calendar UI for production task schedules.
///
/// HOW:
/// - Fetches calendar items for the visible month via productionCalendarProvider.
/// - Renders a Monday-Sunday month grid with per-day task chips/counts.
/// - Opens a bottom sheet with task details (time range, staff, role, status).
///
/// WHY:
/// - Gives owners/staff a calendar-first view similar to Apple month calendar.
/// - Makes schedule conflicts and daily workload visible at a glance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_calendar_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/theme/app_theme.dart';

const String _logTag = "PRODUCTION_CALENDAR_SCREEN";
const String _logBuild = "build()";
const String _logMonthRange = "month_range_computed";
const String _logPrevMonth = "navigate_prev_month";
const String _logNextMonth = "navigate_next_month";
const String _logToday = "navigate_today";
const String _logDayTap = "day_tap";

const String _screenTitle = "Production calendar";
const String _emptyMonthCopy = "No tasks scheduled this month";
const String _loadingCopy = "Loading production calendar...";
const String _retryLabel = "Retry";
const String _todayLabel = "Today";
const String _prevMonthTooltip = "Previous month";
const String _nextMonthTooltip = "Next month";
const String _todayTooltip = "Jump to today";
const String _daySheetTitlePrefix = "Tasks on";
const String _daySheetEmptyCopy = "No tasks scheduled for this day";
const String _staffFallback = "Unassigned";
const String _moreSuffix = "more";

const List<String> _weekdayLabels = [
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
  "Sun",
];

const double _pagePadding = 12;
const double _calendarSpacing = 10;
const double _weekdayHeaderHeight = 28;
const double _weekdayTileRadius = 8;
const double _dayTileRadius = 10;
const double _dayTilePadding = 6;
const double _dayChipGap = 4;
const int _maxDayChips = 2;

class ProductionCalendarScreen extends ConsumerStatefulWidget {
  const ProductionCalendarScreen({super.key});

  @override
  ConsumerState<ProductionCalendarScreen> createState() =>
      _ProductionCalendarScreenState();
}

class _ProductionCalendarScreenState
    extends ConsumerState<ProductionCalendarScreen> {
  DateTime _visibleMonth = _firstDayOfMonth(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final from = _visibleMonth;
    final to = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    final query = ProductionCalendarQuery(from: from, to: to);

    // WHY: Month range logging is required for debugging provider/data mismatches.
    AppDebug.log(
      _logTag,
      _logBuild,
      extra: {"month": _monthLabel(_visibleMonth)},
    );
    AppDebug.log(
      _logTag,
      _logMonthRange,
      extra: {"from": formatDateInput(from), "to": formatDateInput(to)},
    );

    final calendarAsync = ref.watch(productionCalendarProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        actions: [
          IconButton(
            tooltip: _prevMonthTooltip,
            onPressed: _goToPreviousMonth,
            icon: const Icon(Icons.chevron_left),
          ),
          Tooltip(
            message: _todayTooltip,
            child: TextButton(
              onPressed: _goToToday,
              child: const Text(_todayLabel),
            ),
          ),
          IconButton(
            tooltip: _nextMonthTooltip,
            onPressed: _goToNextMonth,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(_pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonthHeader(label: _monthLabel(_visibleMonth)),
            const SizedBox(height: _calendarSpacing),
            const _WeekdayHeader(),
            const SizedBox(height: _calendarSpacing),
            Expanded(
              child: calendarAsync.when(
                loading: () => const _CalendarLoadingState(),
                error: (error, _) => _CalendarErrorState(
                  message: error.toString(),
                  onRetry: () {
                    ref.invalidate(productionCalendarProvider(query));
                  },
                ),
                data: (response) {
                  final monthDays = _buildMonthGridDays(_visibleMonth);
                  final allMonthTasks = _tasksForMonth(
                    items: response.items,
                    monthStart: from,
                    nextMonthStart: to,
                  );
                  final hasAnyTask = allMonthTasks.isNotEmpty;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!hasAnyTask)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: _CalendarEmptyState(),
                        ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final gridHeight = constraints.maxHeight;
                            final rows = (monthDays.length / 7).ceil();
                            final cellHeight =
                                (gridHeight - ((rows - 1) * _calendarSpacing)) /
                                rows;

                            return GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    mainAxisSpacing: _calendarSpacing,
                                    crossAxisSpacing: _calendarSpacing,
                                    childAspectRatio:
                                        constraints.maxWidth / (7 * cellHeight),
                                  ),
                              itemCount: monthDays.length,
                              itemBuilder: (context, index) {
                                final day = monthDays[index];
                                if (day == null) {
                                  return const SizedBox.shrink();
                                }
                                final dayTasks = _tasksForDay(
                                  day: day,
                                  items: response.items,
                                );
                                return _DayTile(
                                  day: day,
                                  dayTasks: dayTasks,
                                  onTap: () => _openDaySheet(
                                    day: day,
                                    dayTasks: dayTasks,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToPreviousMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    AppDebug.log(_logTag, _logPrevMonth, extra: {"month": _monthLabel(next)});
    setState(() {
      _visibleMonth = next;
    });
  }

  void _goToNextMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    AppDebug.log(_logTag, _logNextMonth, extra: {"month": _monthLabel(next)});
    setState(() {
      _visibleMonth = next;
    });
  }

  void _goToToday() {
    final next = _firstDayOfMonth(DateTime.now());
    AppDebug.log(_logTag, _logToday, extra: {"month": _monthLabel(next)});
    setState(() {
      _visibleMonth = next;
    });
  }

  void _openDaySheet({
    required DateTime day,
    required List<ProductionCalendarItem> dayTasks,
  }) {
    AppDebug.log(
      _logTag,
      _logDayTap,
      extra: {"day": formatDateInput(day), "count": dayTasks.length},
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _DayTasksBottomSheet(day: day, tasks: dayTasks);
      },
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final String label;

  const _MonthHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _weekdayHeaderHeight,
      child: Row(
        children: _weekdayLabels
            .map(
              (label) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(_weekdayTileRadius),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  final DateTime day;
  final List<ProductionCalendarItem> dayTasks;
  final VoidCallback onTap;

  const _DayTile({
    required this.day,
    required this.dayTasks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipsToShow = dayTasks.take(_maxDayChips).toList();
    final hiddenCount = dayTasks.length - chipsToShow.length;
    final isToday = _isSameDay(day, DateTime.now());

    return InkWell(
      borderRadius: BorderRadius.circular(_dayTileRadius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(_dayTilePadding),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(_dayTileRadius),
          border: Border.all(
            color: isToday
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              day.day.toString(),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isToday
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: _dayChipGap),
            if (dayTasks.isEmpty)
              Expanded(child: Text("", style: theme.textTheme.bodySmall)),
            if (dayTasks.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...chipsToShow.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: _dayChipGap),
                        child: _DayTaskChip(item: item),
                      ),
                    ),
                    if (hiddenCount > 0)
                      Text(
                        "+$hiddenCount $_moreSuffix",
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayTaskChip extends StatelessWidget {
  final ProductionCalendarItem item;

  const _DayTaskChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _statusTone(item.status);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.35)),
      ),
      child: Text(
        item.title.isEmpty ? "Task" : item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CalendarLoadingState extends StatelessWidget {
  const _CalendarLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 10),
          Text(_loadingCopy),
        ],
      ),
    );
  }
}

class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState();

  @override
  Widget build(BuildContext context) {
    return Text(
      _emptyMonthCopy,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _CalendarErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CalendarErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text(_retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTasksBottomSheet extends StatelessWidget {
  final DateTime day;
  final List<ProductionCalendarItem> tasks;

  const _DayTasksBottomSheet({required this.day, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final sortedTasks = [...tasks]
      ..sort((a, b) {
        final aStart = a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bStart = b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aStart.compareTo(bStart);
      });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$_daySheetTitlePrefix ${formatDateInput(day)}",
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (sortedTasks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(_daySheetEmptyCopy),
              ),
            if (sortedTasks.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sortedTasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = sortedTasks[index];
                    return _DayTaskListItem(item: item);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayTaskListItem extends StatelessWidget {
  final ProductionCalendarItem item;

  const _DayTaskListItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _statusTone(item.status);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTimeRange(item.startDate, item.dueDate),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Staff: ${item.assignedStaffName.isEmpty ? _staffFallback : item.assignedStaffName}",
            style: theme.textTheme.bodySmall,
          ),
          Text("Role: ${item.roleRequired}", style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colors.foreground.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              item.status,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _firstDayOfMonth(DateTime value) {
  return DateTime(value.year, value.month, 1);
}

String _monthLabel(DateTime month) {
  const monthNames = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  return "${monthNames[month.month - 1]} ${month.year}";
}

List<DateTime?> _buildMonthGridDays(DateTime month) {
  final firstDay = DateTime(month.year, month.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

  // WHY: DateTime.weekday is 1-7 (Mon-Sun), so this gives leading blanks for Monday-first calendars.
  final leadingEmptyCells = firstDay.weekday - 1;
  final totalDayCells = leadingEmptyCells + daysInMonth;
  final totalGridCells = ((totalDayCells / 7).ceil()) * 7;

  final grid = <DateTime?>[];
  for (var i = 0; i < totalGridCells; i += 1) {
    if (i < leadingEmptyCells) {
      grid.add(null);
      continue;
    }
    final dayNumber = i - leadingEmptyCells + 1;
    if (dayNumber > daysInMonth) {
      grid.add(null);
      continue;
    }
    grid.add(DateTime(month.year, month.month, dayNumber));
  }

  return grid;
}

List<ProductionCalendarItem> _tasksForMonth({
  required List<ProductionCalendarItem> items,
  required DateTime monthStart,
  required DateTime nextMonthStart,
}) {
  return items
      .where(
        (item) => _overlapsRange(
          item: item,
          start: monthStart,
          endExclusive: nextMonthStart,
        ),
      )
      .toList();
}

List<ProductionCalendarItem> _tasksForDay({
  required DateTime day,
  required List<ProductionCalendarItem> items,
}) {
  final dayStart = DateTime(day.year, day.month, day.day, 0, 0, 0);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final filtered =
      items
          .where(
            (item) => _overlapsRange(
              item: item,
              start: dayStart,
              endExclusive: dayEnd,
            ),
          )
          .toList()
        ..sort((a, b) {
          final aStart = a.startDate ?? dayStart;
          final bStart = b.startDate ?? dayStart;
          return aStart.compareTo(bStart);
        });

  return filtered;
}

bool _overlapsRange({
  required ProductionCalendarItem item,
  required DateTime start,
  required DateTime endExclusive,
}) {
  final itemStart = item.startDate ?? start;
  final itemEnd = item.dueDate ?? itemStart;

  final startsBeforeRangeEnd = itemStart.isBefore(endExclusive);
  final endsAfterRangeStart =
      itemEnd.isAfter(start) || itemEnd.isAtSameMomentAs(start);
  return startsBeforeRangeEnd && endsAfterRangeStart;
}

String _formatTimeRange(DateTime? start, DateTime? end) {
  final safeStart = start?.toLocal();
  final safeEnd = end?.toLocal();
  if (safeStart == null || safeEnd == null) {
    return "--:-- \u2013 --:--";
  }
  return "${_formatTime(safeStart)} \u2013 ${_formatTime(safeEnd)}";
}

String _formatTime(DateTime value) {
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return "$hh:$mm";
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

AppStatusTone _statusTone(String statusRaw) {
  final status = statusRaw.trim().toLowerCase();
  switch (status) {
    case "done":
      return AppStatusTone.success;
    case "in_progress":
      return AppStatusTone.info;
    case "pending":
      return AppStatusTone.warning;
    default:
      return AppStatusTone.neutral;
  }
}
