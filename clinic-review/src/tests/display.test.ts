import { describe, expect, it } from 'vitest';

import { initialsFromLabel, shortId, treatmentStatusLabel } from '../lib/display';

describe('display helpers', () => {
  it('builds initials from a clinic label', () => {
    expect(initialsFromLabel('Анна К.')).toBe('АК');
    expect(initialsFromLabel('Pilot')).toBe('PI');
    expect(initialsFromLabel('  ')).toBe('—');
  });

  it('shortens an id without inventing a clinic number', () => {
    expect(shortId('10000000-0000-4000-8000-000000000020')).toBe('10000000');
  });

  it('keeps treatment status labels aligned with the list', () => {
    expect(treatmentStatusLabel('active')).toBe('активно');
    expect(treatmentStatusLabel(null)).toBe('нет лечения');
  });
});
