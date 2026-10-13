import { describe, expect, it } from 'vitest';

import { assignmentHistoryLabel, groupAssignments } from '../lib/assignments';

const today = '2026-10-13';

function row(
  id: string,
  title: string,
  start: string,
  end: string,
  status: 'active' | 'disabled' = 'active',
) {
  return {
    id,
    title,
    start_date: start,
    end_date: end,
    status,
    icon_storage_path: null,
  };
}

describe('groupAssignments', () => {
  it('keeps only prescriptions that cover today in the current list', () => {
    const groups = groupAssignments(
      [
        row('now', 'Пить воду', '2026-10-10', '2026-10-15'),
        row('ended', 'Пить воду', '2026-10-01', '2026-10-12'),
        row('later', 'Анальгин', '2026-10-20', '2026-10-22'),
        row('off', 'Анальгин', '2026-10-10', '2026-10-20', 'disabled'),
      ],
      today,
    );

    expect(groups.current.map((item) => item.id)).toEqual(['now']);
    expect(groups.upcoming.map((item) => item.id)).toEqual(['later']);
    expect(groups.history.map((group) => group.title)).toEqual(['Анальгин', 'Пить воду']);
    expect(groups.history[1]?.items.map((item) => item.id)).toEqual(['ended']);
  });

  it('stacks repeated past ranges of the same title newest first', () => {
    const groups = groupAssignments(
      [
        row('early', 'Пить воду', '2026-10-01', '2026-10-02'),
        row('late', 'Пить воду', '2026-10-08', '2026-10-09'),
      ],
      today,
    );

    expect(groups.history).toHaveLength(1);
    expect(groups.history[0]?.items.map((item) => item.id)).toEqual(['late', 'early']);
  });
});

describe('assignmentHistoryLabel', () => {
  it('prefers a disabled mark over an expired range', () => {
    expect(
      assignmentHistoryLabel(
        { status: 'disabled', start_date: '2026-10-01', end_date: '2026-10-02' },
        today,
      ),
    ).toBe('отключено');
    expect(
      assignmentHistoryLabel(
        { status: 'active', start_date: '2026-10-01', end_date: '2026-10-02' },
        today,
      ),
    ).toBe('срок истёк');
  });
});
