import { notificationLogLine, pushPayload } from './notification-message.ts';

export type PushSubscriptionTarget = {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
};

export type PushSendResult = { status: number | null };

export function classifyPushStatus(status: number | null): {
  delivery: 'sent' | 'failed';
  disableSubscription: boolean;
  errorCode: string | null;
} {
  if (status !== null && status >= 200 && status < 300) {
    return { delivery: 'sent', disableSubscription: false, errorCode: null };
  }
  if (status === 404 || status === 410) {
    return { delivery: 'failed', disableSubscription: true, errorCode: `http_${status}` };
  }
  if (status === null) {
    return { delivery: 'failed', disableSubscription: false, errorCode: 'network' };
  }
  return { delivery: 'failed', disableSubscription: false, errorCode: `http_${status}` };
}

export type DeliveryStore = {
  listActiveSubscriptions(patientId: string): Promise<PushSubscriptionTarget[]>;
  listDeliverySubscriptionIds(eventId: string): Promise<string[]>;
  insertPending(eventId: string, subscriptionId: string): Promise<'inserted' | 'duplicate'>;
  finishDelivery(
    eventId: string,
    subscriptionId: string,
    status: 'sent' | 'failed',
    errorCode: string | null,
  ): Promise<void>;
  disableSubscription(subscriptionId: string): Promise<void>;
  markProcessed(eventId: string): Promise<void>;
  countUnread(patientId: string): Promise<number>;
};

export async function dispatchNotificationEvent(
  store: DeliveryStore,
  event: { id: string; patientId: string; kind: string; route: string },
  send: (subscription: PushSubscriptionTarget, payload: string) => Promise<PushSendResult>,
  log: (line: string) => void = (line) => console.info(line),
): Promise<{ attempted: number; disabled: number }> {
  const subscriptions = await store.listActiveSubscriptions(event.patientId);
  const already = new Set(await store.listDeliverySubscriptionIds(event.id));
  const unread = await store.countUnread(event.patientId);
  const payload = JSON.stringify(pushPayload({
    id: event.id,
    kind: event.kind,
    route: event.route,
    badge: unread,
  }));
  let attempted = 0;
  let disabled = 0;

  for (const subscription of subscriptions) {
    if (already.has(subscription.id)) {
      continue;
    }
    const claimed = await store.insertPending(event.id, subscription.id);
    if (claimed === 'duplicate') {
      continue;
    }

    let result: PushSendResult;
    try {
      result = await send(subscription, payload);
    } catch {
      result = { status: null };
    }
    const classified = classifyPushStatus(result.status);
    await store.finishDelivery(event.id, subscription.id, classified.delivery, classified.errorCode);
    if (classified.disableSubscription) {
      await store.disableSubscription(subscription.id);
      disabled += 1;
    }
    log(notificationLogLine({
      notificationEventId: event.id,
      kind: event.kind,
      subscriptionId: subscription.id,
      status: classified.delivery,
      httpStatus: result.status,
    }));
    attempted += 1;
  }

  await store.markProcessed(event.id);
  return { attempted, disabled };
}
