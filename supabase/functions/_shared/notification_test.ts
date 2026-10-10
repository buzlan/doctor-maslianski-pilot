import assert from 'node:assert/strict';

import { cronRequestAllowed, manualTestAllowed, parseManualTestRequest } from './notification-access.ts';
import {
  classifyPushStatus,
  dispatchNotificationEvent,
  type DeliveryStore,
  type PushSubscriptionTarget,
} from './notification-delivery.ts';
import { copyForKind, notificationLogLine, pushPayload } from './notification-message.ts';

const PATIENT = '11111111-1111-4111-8111-111111111111';
const EVENT = '22222222-2222-4222-8222-222222222222';

function subscription(id: string): PushSubscriptionTarget {
  return {
    id,
    endpoint: `https://push.example.test/${id}`,
    p256dh: `p256dh-${id}`,
    auth: `auth-${id}`,
  };
}

function memoryStore(subscriptions: PushSubscriptionTarget[]): DeliveryStore & {
  disabled: string[];
  deliveries: { subscriptionId: string; status: string; errorCode: string | null }[];
  processed: boolean;
} {
  const deliveries: { subscriptionId: string; status: string; errorCode: string | null }[] = [];
  const disabled: string[] = [];
  return {
    processed: false,
    deliveries,
    disabled,
    async listActiveSubscriptions() {
      return subscriptions.filter((item) => !disabled.includes(item.id));
    },
    async listDeliverySubscriptionIds() {
      return deliveries.map((item) => item.subscriptionId);
    },
    async insertPending(_eventId, subscriptionId) {
      if (deliveries.some((item) => item.subscriptionId === subscriptionId)) {
        return 'duplicate';
      }
      deliveries.push({ subscriptionId, status: 'pending', errorCode: null });
      return 'inserted';
    },
    async finishDelivery(_eventId, subscriptionId, status, errorCode) {
      const row = deliveries.find((item) => item.subscriptionId === subscriptionId);
      if (row) {
        row.status = status;
        row.errorCode = errorCode;
      }
    },
    async disableSubscription(subscriptionId) {
      disabled.push(subscriptionId);
    },
    async markProcessed() {
      this.processed = true;
    },
    async countUnread() {
      return 2;
    },
  };
}

Deno.test('push payload stays minimal and copy is privacy-safe', () => {
  const payload = pushPayload({ id: EVENT, kind: 'daily_morning', route: '/diary?pain=8', badge: 4 });
  assert.deepEqual(Object.keys(payload).sort(), ['badge', 'eventId', 'kind', 'route']);
  assert.equal(payload.badge, 4);
  assert.equal(pushPayload({ id: EVENT, kind: 'daily_morning', route: '/' }).badge, 1);
  assert.equal(payload.route, '/');
  assert.equal(JSON.stringify(payload).includes('pain'), false);
  assert.equal(copyForKind('manual_test').title, 'Тестовое уведомление. Уведомления работают.');
  assert.equal(copyForKind('manual_test').body, '');
  assert.equal(copyForKind('assignment_changed').title, 'В вашем плане появились изменения.');
  assert.equal(copyForKind('appointment_previous_day').title, 'Уведомляем вас о ближайшей записи.');
  assert.equal(copyForKind('treatment_completed').title, 'Информация в приложении обновлена.');
  const log = notificationLogLine({
    notificationEventId: EVENT,
    kind: 'manual_test',
    subscriptionId: 'sub-1',
    status: 'sent',
    httpStatus: 201,
  });
  assert.equal(log.includes('endpoint'), false);
  assert.equal(log.includes('p256dh'), false);
  assert.equal(log.includes('auth'), false);
});

Deno.test('dead subscriptions are disabled only for 404 and 410', () => {
  assert.equal(classifyPushStatus(404).disableSubscription, true);
  assert.equal(classifyPushStatus(410).disableSubscription, true);
  assert.equal(classifyPushStatus(429).disableSubscription, false);
  assert.equal(classifyPushStatus(500).disableSubscription, false);
  assert.equal(classifyPushStatus(503).disableSubscription, false);
  assert.equal(classifyPushStatus(null).disableSubscription, false);
  assert.equal(classifyPushStatus(201).delivery, 'sent');
  assert.equal(classifyPushStatus(429).delivery, 'failed');
});

Deno.test('one event creates one delivery per active device and does not retry', async () => {
  const store = memoryStore([subscription('phone-a'), subscription('phone-b')]);
  const statuses = new Map<string, number>([['phone-a', 201], ['phone-b', 410]]);
  const sent: string[] = [];
  const payloads: string[] = [];
  await dispatchNotificationEvent(store, {
    id: EVENT,
    patientId: PATIENT,
    kind: 'daily_morning',
    route: '/',
  }, async (subscriptionTarget, payload) => {
    sent.push(subscriptionTarget.id);
    payloads.push(payload);
    return { status: statuses.get(subscriptionTarget.id) ?? 500 };
  }, () => undefined);
  assert.equal(JSON.parse(payloads[0] ?? '{}').badge, 2);

  assert.deepEqual(sent, ['phone-a', 'phone-b']);
  assert.equal(store.deliveries.length, 2);
  assert.deepEqual(store.disabled, ['phone-b']);
  assert.equal(store.processed, true);

  const again = await dispatchNotificationEvent(store, {
    id: EVENT,
    patientId: PATIENT,
    kind: 'daily_morning',
    route: '/',
  }, async () => {
    throw new Error('should not send again');
  }, () => undefined);
  assert.equal(again.attempted, 0);
});

Deno.test('429 and 5xx keep the subscription enabled', async () => {
  const store = memoryStore([subscription('phone-a')]);
  await dispatchNotificationEvent(store, {
    id: EVENT,
    patientId: PATIENT,
    kind: 'manual_test',
    route: '/',
  }, async () => ({ status: 429 }), () => undefined);
  assert.deepEqual(store.disabled, []);
  assert.equal(store.deliveries[0]?.errorCode, 'http_429');

  const server = memoryStore([subscription('phone-c')]);
  await dispatchNotificationEvent(server, {
    id: EVENT,
    patientId: PATIENT,
    kind: 'manual_test',
    route: '/',
  }, async () => ({ status: 503 }), () => undefined);
  assert.deepEqual(server.disabled, []);
  assert.equal(server.deliveries[0]?.status, 'failed');
});

Deno.test('manual test accepts only a staff synthetic patient id', () => {
  assert.equal(parseManualTestRequest({ patientId: PATIENT })?.patientId, PATIENT);
  assert.equal(parseManualTestRequest({ patientId: PATIENT, body: 'Боль 8' }), null);
  assert.equal(parseManualTestRequest({ title: 'Доктор Маслянский' }), null);
  assert.equal(parseManualTestRequest(null), null);
  assert.equal(manualTestAllowed({ isStaff: true, cohort: 'internal_dry_run' }), true);
  assert.equal(manualTestAllowed({ isStaff: true, cohort: 'clinic_pilot' }), false);
  assert.equal(manualTestAllowed({ isStaff: false, cohort: 'internal_dry_run' }), false);
  assert.equal(manualTestAllowed({ isStaff: true, cohort: null }), false);
  assert.equal(cronRequestAllowed(null, 'short'), false);
  assert.equal(cronRequestAllowed('cron-secret-value', 'cron-secret-value'), true);
  assert.equal(cronRequestAllowed('wrong-secret-value', 'cron-secret-value'), false);
});

Deno.test('function sources do not log push secrets', async () => {
  const files = [
    './notification-delivery.ts',
    './notification-message.ts',
    './web-push-sender.ts',
    '../evaluate-patient-notifications/index.ts',
    '../send-test-push/index.ts',
  ];
  for (const file of files) {
    const source = await Deno.readTextFile(new URL(file, import.meta.url));
    assert.equal(source.includes('console.log'), false, file);
    assert.equal(source.includes('EXPO_PUBLIC_'), false, file);
  }
});
