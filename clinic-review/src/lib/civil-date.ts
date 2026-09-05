export type CivilDate = {
  year: number;
  month: number;
  day: number;
};

const CIVIL_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

export function parseCivilDate(value: string): CivilDate | null {
  const match = CIVIL_DATE_PATTERN.exec(value.trim());
  if (match === null) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
    return null;
  }

  const utc = new Date(Date.UTC(year, month - 1, day));
  if (
    utc.getUTCFullYear() !== year ||
    utc.getUTCMonth() !== month - 1 ||
    utc.getUTCDate() !== day
  ) {
    return null;
  }

  return { year, month, day };
}

export function formatCivilDate(date: CivilDate): string {
  const month = String(date.month).padStart(2, '0');
  const day = String(date.day).padStart(2, '0');
  return `${date.year}-${month}-${day}`;
}

export function dayIndex(start: CivilDate, onDate: CivilDate): number {
  const startUtc = Date.UTC(start.year, start.month - 1, start.day);
  const onUtc = Date.UTC(onDate.year, onDate.month - 1, onDate.day);
  return Math.trunc((onUtc - startUtc) / 86_400_000);
}

export function periodDayNumber(
  startedOn: CivilDate,
  onDate: CivilDate,
  endedOn: CivilDate | null = null,
): number | null {
  if (dayIndex(startedOn, onDate) < 0) {
    return null;
  }
  if (endedOn !== null && dayIndex(onDate, endedOn) < 0) {
    return null;
  }
  return 1 + dayIndex(startedOn, onDate);
}

export function clinicToday(timeZone: string, now: Date = new Date()): CivilDate {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);

  const year = Number(parts.find((part) => part.type === 'year')?.value);
  const month = Number(parts.find((part) => part.type === 'month')?.value);
  const day = Number(parts.find((part) => part.type === 'day')?.value);
  return { year, month, day };
}

export function wallClockInputValue(wallClock: string): string {
  return wallClock.trim().replace(' ', 'T').replace(/Z$/i, '').slice(0, 16);
}

export function wallClockFromInput(value: string): string | null {
  const trimmed = value.trim();
  if (trimmed.length === 0 || /Z$/i.test(trimmed)) {
    return null;
  }
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(trimmed)) {
    return null;
  }
  return `${trimmed}:00`;
}
