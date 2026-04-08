/**
 * utils/rentCoverage.js
 * ---------------------
 * WHAT:
 * - Helpers to compute rent coverage windows for tenant payments.
 *
 * WHY:
 * - Centralises all period math (monthly/quarterly/yearly) so intents,
 *   webhooks, and analytics stay consistent and safe.
 *
 * HOW:
 * - Provides small pure functions for months-per-period, coversTo date math,
 *   and 36‑month prepay caps. All functions are deterministic and log via
 *   the shared debug helper for traceability.
 */

const dayjs = require('dayjs');
const debug = require('./debug');

const RENT_PERIODS = ['monthly', 'quarterly', 'yearly'];
const MONTHS_IN_YEAR = 12;

// WHY: Avoid magic numbers sprinkled across services.
function monthsPerPeriod(rentPeriod) {
  switch ((rentPeriod || '').toLowerCase()) {
    case 'monthly':
      return 1;
    case 'quarterly':
      return 3;
    case 'yearly':
      return 12;
    default:
      return null;
  }
}

// WHY: Compute the coverage end date (inclusive) given a start, count, and period.
function computeCoversTo(coversFrom, periodCount, rentPeriod) {
  const months = monthsPerPeriod(rentPeriod);
  if (!months || !periodCount || !coversFrom) return null;

  const totalMonths = months * periodCount;
  const start = dayjs(coversFrom);
  // Subtract one day so coverage is inclusive of the final day.
  return start.add(totalMonths, 'month').subtract(1, 'day').toDate();
}

// WHY: Enforce the 36‑month cap while allowing auto‑reduction.
function computeMaxPeriodsWithin36Months(coversFrom, rentPeriod) {
  const months = monthsPerPeriod(rentPeriod);
  if (!months || !coversFrom) return 0;

  const capEnd = dayjs(coversFrom).add(36, 'month').subtract(1, 'day');
  let max = 0;

  // Increment periods until the next one would exceed the cap.
  while (true) {
    const tentativePeriods = max + 1;
    const tentativeEnd = computeCoversTo(coversFrom, tentativePeriods, rentPeriod);
    if (!tentativeEnd) break;
    if (dayjs(tentativeEnd).isAfter(capEnd)) break;
    max = tentativePeriods;
  }

  debug('RENT_COVERAGE: max periods computed', {
    rentPeriod,
    coversFrom,
    capEnd: capEnd.toDate(),
    max,
  });

  return max;
}

// WHY: Helper for scenarios where we convert years to periods.
function periodCountFromYears(rentPeriod, yearsToPay) {
  const months = monthsPerPeriod(rentPeriod);
  if (!months || !yearsToPay) return 0;
  return (MONTHS_IN_YEAR / months) * yearsToPay;
}

// WHY: Convert rent cadence into the number of periods in a calendar year.
function periodsPerYear(rentPeriod) {
  const months = monthsPerPeriod(rentPeriod);
  if (!months) return 0;
  return MONTHS_IN_YEAR / months;
}

module.exports = {
  RENT_PERIODS,
  monthsPerPeriod,
  computeCoversTo,
  computeMaxPeriodsWithin36Months,
  periodCountFromYears,
  periodsPerYear,
};
