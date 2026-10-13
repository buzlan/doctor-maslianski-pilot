export type AssignmentSchedule = {
  id: string;
  title: string;
  start_date: string;
  end_date: string;
  status: 'active' | 'disabled';
  icon_storage_path: string | null;
};

export type AssignmentHistoryGroup<T extends AssignmentSchedule> = {
  title: string;
  icon_storage_path: string | null;
  items: T[];
};

export type AssignmentGroups<T extends AssignmentSchedule> = {
  current: T[];
  upcoming: T[];
  history: AssignmentHistoryGroup<T>[];
};

export function groupAssignments<T extends AssignmentSchedule>(
  assignments: readonly T[],
  today: string,
): AssignmentGroups<T> {
  const current: T[] = [];
  const upcoming: T[] = [];
  const past: T[] = [];

  for (const assignment of assignments) {
    if (
      assignment.status === 'active' &&
      assignment.start_date <= today &&
      assignment.end_date >= today
    ) {
      current.push(assignment);
    } else if (assignment.status === 'active' && assignment.start_date > today) {
      upcoming.push(assignment);
    } else {
      past.push(assignment);
    }
  }

  current.sort(
    (left, right) =>
      left.title.localeCompare(right.title, 'ru') || left.start_date.localeCompare(right.start_date),
  );
  upcoming.sort((left, right) => left.start_date.localeCompare(right.start_date));
  past.sort(
    (left, right) =>
      right.start_date.localeCompare(left.start_date) || right.end_date.localeCompare(left.end_date),
  );

  const history: AssignmentHistoryGroup<T>[] = [];
  for (const item of past) {
    const group = history.find((entry) => entry.title === item.title);
    if (group === undefined) {
      history.push({
        title: item.title,
        icon_storage_path: item.icon_storage_path,
        items: [item],
      });
    } else {
      group.items.push(item);
    }
  }

  return { current, upcoming, history };
}

export function assignmentHistoryLabel(
  assignment: Pick<AssignmentSchedule, 'status' | 'start_date' | 'end_date'>,
  today: string,
): string {
  if (assignment.status === 'disabled') {
    return 'отключено';
  }
  if (assignment.end_date < today) {
    return 'срок истёк';
  }
  return 'не действует';
}
