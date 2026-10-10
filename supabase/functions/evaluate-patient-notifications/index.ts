import { createClient } from 'npm:@supabase/supabase-js@2';

import { cronRequestAllowed } from '../_shared/notification-access.ts';
import { dispatchNotificationEvent } from '../_shared/notification-delivery.ts';
import { supabaseDeliveryStore, type DeliveryAdminClient } from '../_shared/supabase-delivery-store.ts';
import { sendWebPush } from '../_shared/web-push-sender.ts';

const NO_STORE = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json',
} as const;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: NO_STORE });
}

type EventRow = {
  id: string;
  patient_id: string;
  kind: string;
  route: string;
};

function adminClient() {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export default {
  async fetch(req: Request): Promise<Response> {
    if (req.method !== 'POST') {
      return json({ error: 'method' }, 405);
    }
    if (!cronRequestAllowed(req.headers.get('x-notification-cron-secret'), Deno.env.get('NOTIFICATION_CRON_SECRET'))) {
      return json({ error: 'unauthorized' }, 401);
    }

    const admin = adminClient();
    const evaluated = await admin.rpc('evaluate_due_notification_events');
    if (evaluated.error) {
      console.info(JSON.stringify({ status: 'evaluate_failed' }));
      return json({ error: 'unavailable' }, 500);
    }

    const pending = await admin
      .from('notification_events')
      .select('id, patient_id, kind, route')
      .is('processed_at', null)
      .order('created_at', { ascending: true })
      .limit(50);
    if (pending.error) {
      console.info(JSON.stringify({ status: 'queue_failed' }));
      return json({ error: 'unavailable' }, 500);
    }

    const store = supabaseDeliveryStore(admin as unknown as DeliveryAdminClient);
    const events = (pending.data ?? []) as EventRow[];
    let attempted = 0;
    for (const event of events) {
      const result = await dispatchNotificationEvent(store, {
        id: event.id,
        patientId: event.patient_id,
        kind: event.kind,
        route: event.route,
      }, sendWebPush);
      attempted += result.attempted;
    }

    return json({ ok: true, events: events.length, attempted });
  },
};
