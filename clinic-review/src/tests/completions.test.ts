import { describe, expect, it } from 'vitest';

import { assignmentCompletionView } from '../lib/completions';

describe('assignmentCompletionView', () => {
  const rows = [
    { assignment_id: 'a1', completed_on: '2026-09-03' },
    { assignment_id: 'a1', completed_on: '2026-09-05' },
    { assignment_id: 'a2', completed_on: '2026-09-05' },
  ];

  it('marks today from action_completions rows only', () => {
    expect(assignmentCompletionView(rows, 'a1', '2026-09-05')).toEqual({
      completedToday: true,
      historicalDates: ['2026-09-03'],
    });
  });

  it('keeps historical dates when today is not completed', () => {
    expect(assignmentCompletionView(rows, 'a1', '2026-09-04')).toEqual({
      completedToday: false,
      historicalDates: ['2026-09-03', '2026-09-05'],
    });
  });

  it('returns empty history for an assignment with no rows', () => {
    expect(assignmentCompletionView(rows, 'missing', '2026-09-05')).toEqual({
      completedToday: false,
      historicalDates: [],
    });
  });
});
