export type CompletionRow = {
  assignment_id: string;
  completed_on: string;
};

export type AssignmentCompletionView = {
  completedToday: boolean;
  historicalDates: string[];
};

export function assignmentCompletionView(
  completions: readonly CompletionRow[],
  assignmentId: string,
  today: string,
): AssignmentCompletionView {
  const dates = completions
    .filter((item) => item.assignment_id === assignmentId)
    .map((item) => item.completed_on)
    .sort();

  return {
    completedToday: dates.includes(today),
    historicalDates: dates.filter((date) => date !== today),
  };
}
