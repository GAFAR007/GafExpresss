/**
 * apps/backend/services/planner/expandRecurringTasks.js
 * -----------------------------------------------------
 * WHAT:
 * - Expands recurring semantic tasks into concrete day anchors within a phase window.
 *
 * WHY:
 * - Recurring farm work such as irrigation and weeding must become real schedule rows.
 * - Expansion must remain deterministic and bounded by the phase window.
 *
 * HOW:
 * - Starts from the phase start plus an optional offset.
 * - Steps forward by the configured recurrence frequency.
 * - Returns concrete occurrence dates clamped to the phase range.
 */

function startOfDayUtc(value) {
  const date = new Date(value);
  return new Date(
    Date.UTC(
      date.getUTCFullYear(),
      date.getUTCMonth(),
      date.getUTCDate(),
      0,
      0,
      0,
      0,
    ),
  );
}

function expandRecurringTaskDates({
  phaseStart,
  phaseEnd,
  frequencyEveryDays,
  firstOccurrenceOffsetDays = 1,
}) {
  const safeFrequency = Math.max(
    1,
    Math.floor(Number(frequencyEveryDays || 1)),
  );
  const safeOffset = Math.max(
    0,
    Math.floor(Number(firstOccurrenceOffsetDays || 0)),
  );
  const occurrences = [];
  const rangeStart = startOfDayUtc(phaseStart);
  const rangeEnd = startOfDayUtc(phaseEnd);
  let cursor = new Date(
    rangeStart.getTime() + safeOffset * 86400000,
  );

  while (cursor.getTime() <= rangeEnd.getTime()) {
    occurrences.push(new Date(cursor));
    cursor = new Date(
      cursor.getTime() + safeFrequency * 86400000,
    );
  }

  return occurrences;
}

module.exports = {
  expandRecurringTaskDates,
};
