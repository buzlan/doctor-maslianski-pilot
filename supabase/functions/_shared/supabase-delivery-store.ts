import type { DeliveryStore, PushSubscriptionTarget } from './notification-delivery.ts';

type QueryError = { code?: string } | null;

type LooseQuery = Promise<{ data: unknown; error: QueryError }> & {
  eq(column: string, value: string): LooseQuery;
  is(column: string, value: null): LooseQuery;
};

export type DeliveryAdminClient = {
  from(table: string): {
    select(columns: string): LooseQuery;
    insert(values: Record<string, unknown>): Promise<{ error: QueryError }>;
    update(values: Record<string, unknown>): LooseQuery;
  };
};

function rows<T>(data: unknown): T[] {
  return Array.isArray(data) ? data as T[] : [];
}

export function supabaseDeliveryStore(admin: DeliveryAdminClient): DeliveryStore {
  return {
    async listActiveSubscriptions(patientId) {
      const result = await admin
        .from('push_subscriptions')
        .select('id, endpoint, p256dh, auth')
        .eq('patient_id', patientId)
        .is('disabled_at', null);
      return rows<PushSubscriptionTarget>(result.data);
    },
    async listDeliverySubscriptionIds(eventId) {
      const result = await admin
        .from('push_deliveries')
        .select('push_subscription_id')
        .eq('notification_event_id', eventId);
      return rows<{ push_subscription_id: string }>(result.data).map((row) => row.push_subscription_id);
    },
    async insertPending(eventId, subscriptionId) {
      const result = await admin.from('push_deliveries').insert({
        notification_event_id: eventId,
        push_subscription_id: subscriptionId,
        status: 'pending',
      });
      if (result.error?.code === '23505') {
        return 'duplicate';
      }
      if (result.error) {
        throw new Error('delivery_insert_failed');
      }
      return 'inserted';
    },
    async finishDelivery(eventId, subscriptionId, status, errorCode) {
      const result = await admin
        .from('push_deliveries')
        .update({
          status,
          sent_at: new Date().toISOString(),
          error_code: errorCode,
        })
        .eq('notification_event_id', eventId)
        .eq('push_subscription_id', subscriptionId);
      if (result.error) {
        throw new Error('delivery_update_failed');
      }
    },
    async disableSubscription(subscriptionId) {
      const result = await admin
        .from('push_subscriptions')
        .update({ disabled_at: new Date().toISOString() })
        .eq('id', subscriptionId);
      if (result.error) {
        throw new Error('subscription_disable_failed');
      }
    },
    async markProcessed(eventId) {
      const result = await admin
        .from('notification_events')
        .update({ processed_at: new Date().toISOString() })
        .eq('id', eventId);
      if (result.error) {
        throw new Error('event_processed_failed');
      }
    },
    async countUnread(patientId) {
      const result = await admin
        .from('notification_events')
        .select('id')
        .eq('patient_id', patientId)
        .is('read_at', null);
      if (result.error) {
        return 1;
      }
      const count = rows<{ id: string }>(result.data).length;
      return count > 0 ? count : 1;
    },
  };
}
