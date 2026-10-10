export const NOTIFICATION_KINDS = [
  'daily_morning',
  'daily_afternoon',
  'appointment_previous_day',
  'appointment_same_day',
  'assignment_changed',
  'appointment_changed',
  'appointment_cancelled',
  'treatment_updated',
  'treatment_completed',
  'manual_test',
] as const;

export type NotificationKind = (typeof NOTIFICATION_KINDS)[number];

const COPY: Record<NotificationKind, { title: string; body: string }> = {
  daily_morning: { title: 'У вас есть действие на сегодня.', body: '' },
  daily_afternoon: { title: 'У вас есть действие на сегодня.', body: '' },
  appointment_previous_day: { title: 'Уведомляем вас о ближайшей записи.', body: '' },
  appointment_same_day: { title: 'Уведомляем вас о ближайшей записи.', body: '' },
  assignment_changed: { title: 'В вашем плане появились изменения.', body: '' },
  appointment_changed: { title: 'В вашем плане появились изменения.', body: '' },
  appointment_cancelled: { title: 'Информация в приложении обновлена.', body: '' },
  treatment_updated: { title: 'Информация в приложении обновлена.', body: '' },
  treatment_completed: { title: 'Информация в приложении обновлена.', body: '' },
  manual_test: { title: 'Тестовое уведомление. Уведомления работают.', body: '' },
};

const KIND_ROUTES: Record<NotificationKind, string> = {
  daily_morning: '/',
  daily_afternoon: '/',
  appointment_previous_day: '/',
  appointment_same_day: '/',
  assignment_changed: '/',
  appointment_changed: '/',
  appointment_cancelled: '/',
  treatment_updated: '/treatment',
  treatment_completed: '/',
  manual_test: '/',
};

const ALLOWED_ROUTES = new Set(['/', '/diary', '/treatment', '/completed']);

export function isNotificationKind(value: string): value is NotificationKind {
  return Object.prototype.hasOwnProperty.call(COPY, value);
}

export function routeForKind(kind: string, route: string | null | undefined): string {
  if (typeof route === 'string' && ALLOWED_ROUTES.has(route)) {
    return route;
  }
  if (isNotificationKind(kind)) {
    return KIND_ROUTES[kind];
  }
  return '/';
}

export function copyForKind(kind: string): { title: string; body: string } {
  if (isNotificationKind(kind)) {
    return COPY[kind];
  }
  return COPY.treatment_updated;
}

export function pushPayload(event: { id: string; kind: string; route: string; badge?: number }): {
  eventId: string;
  kind: string;
  route: string;
  badge: number;
} {
  const badge = Number.isInteger(event.badge) && (event.badge ?? 0) > 0
    ? Math.min(event.badge as number, 99)
    : 1;
  return {
    eventId: event.id,
    kind: event.kind,
    route: routeForKind(event.kind, event.route),
    badge,
  };
}

export function notificationLogLine(entry: {
  notificationEventId: string;
  kind: string;
  subscriptionId: string;
  status: string;
  httpStatus: number | null;
}): string {
  return JSON.stringify({
    notificationEventId: entry.notificationEventId,
    kind: entry.kind,
    subscriptionId: entry.subscriptionId,
    status: entry.status,
    httpStatus: entry.httpStatus,
  });
}
