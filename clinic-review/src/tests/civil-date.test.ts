import { describe, expect, it } from 'vitest';

import {
  clinicToday,
  dayIndex,
  formatCivilDate,
  parseCivilDate,
  periodDayNumber,
  wallClockFromInput,
} from '../lib/civil-date';

describe('civil dates', () => {
  it('parses and formats a civil date', () => {
    expect(parseCivilDate('2026-08-19')).toEqual({ year: 2026, month: 8, day: 19 });
    expect(formatCivilDate({ year: 2026, month: 8, day: 19 })).toBe('2026-08-19');
  });

  it('computes Day N from the current period start', () => {
    const started = parseCivilDate('2026-08-19');
    const today = parseCivilDate('2026-08-19');
    const later = parseCivilDate('2026-08-20');
    expect(started).not.toBeNull();
    expect(today).not.toBeNull();
    expect(later).not.toBeNull();
    if (started === null || today === null || later === null) {
      return;
    }
    expect(dayIndex(started, today)).toBe(0);
    expect(periodDayNumber(started, today)).toBe(1);
    expect(periodDayNumber(started, later)).toBe(2);
  });

  it('uses the clinic time zone for today', () => {
    const now = new Date('2026-09-04T22:30:00.000Z');
    expect(clinicToday('Europe/Minsk', now)).toEqual({ year: 2026, month: 9, day: 5 });
    expect(clinicToday('UTC', now)).toEqual({ year: 2026, month: 9, day: 4 });
  });

  it('rejects a wall-clock value that includes Z', () => {
    expect(wallClockFromInput('2026-09-15T14:30:00Z')).toBeNull();
    expect(wallClockFromInput('2026-09-15T14:30')).toBe('2026-09-15T14:30:00');
  });
});
