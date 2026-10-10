import { createClient } from 'npm:@supabase/supabase-js@2';
import { withSupabase } from 'npm:@supabase/server';

import { manualTestAllowed, parseManualTestRequest } from '../_shared/notification-access.ts';
import { dispatchNotificationEvent } from '../_shared/notification-delivery.ts';
import { supabaseDeliveryStore, type DeliveryAdminClient } from '../_shared/supabase-delivery-store.ts';
import { sendWebPush } from '../_shared/web-push-sender.ts';

const NO_STORE = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json',
} as const;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CLINIC_ORIGINS = new Set([
  'https://doctor-maslianski-clinic-review.vercel.app',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
]);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: NO_STORE });
}

function corsHeaders(origin: string | null): Headers {
  const headers = new Headers();
  if (origin !== null && CLINIC_ORIGINS.has(origin)) {
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Vary', 'Origin');
    headers.set('Access-Control-Allow-Headers', 'authorization, apikey, content-type, x-client-info');
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  }
  return headers;
}

function withCors(response: Response, origin: string | null): Response {
  const headers = new Headers(response.headers);
  corsHeaders(origin).forEach((value, key) => headers.set(key, value));
  return new Response(response.body, { status: response.status, headers });
}

function adminClient() {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

const sendTest = withSupabase({ auth: 'user' }, async (req, ctx) => {
  if (req.method !== 'POST') {
    return json({ error: 'method' }, 405);
  }

  const userId = ctx.userClaims?.id ?? '';
  if (!UUID_RE.test(userId)) {
    return json({ error: 'unauthorized' }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid' }, 400);
  }
  const parsed = parseManualTestRequest(body);
  if (parsed === null) {
    return json({ error: 'invalid' }, 400);
  }

  const admin = adminClient();
  const staff = await admin
    .from('clinic_staff')
    .select('id')
    .eq('auth_user_id', userId)
    .maybeSingle();
  if (staff.error || staff.data === null) {
    return json({ error: 'forbidden' }, 403);
  }

  const patient = await admin
    .from('patients')
    .select('pilot_cohort')
    .eq('id', parsed.patientId)
    .maybeSingle();
  const cohort = patient.data === null ? null : patient.data.pilot_cohort;
  if (patient.error || !manualTestAllowed({ isStaff: true, cohort })) {
    return json({ error: 'forbidden' }, 403);
  }

  const created = await admin
    .from('notification_events')
    .insert({
      patient_id: parsed.patientId,
      kind: 'manual_test',
      route: '/',
      dedupe_key: `manual:${parsed.patientId}:${crypto.randomUUID()}`,
    })
    .select('id, patient_id, kind, route')
    .single();
  if (created.error || created.data === null) {
    console.info(JSON.stringify({ status: 'manual_test_create_failed', kind: 'manual_test' }));
    return json({ error: 'unavailable' }, 500);
  }

  const result = await dispatchNotificationEvent(
    supabaseDeliveryStore(admin as unknown as DeliveryAdminClient),
    {
      id: created.data.id,
      patientId: created.data.patient_id,
      kind: created.data.kind,
      route: created.data.route,
    },
    sendWebPush,
  );

  return json({ ok: true, eventId: created.data.id, attempted: result.attempted });
});

export default {
  async fetch(req: Request): Promise<Response> {
    const origin = req.headers.get('Origin');
    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }
    return withCors(await sendTest(req), origin);
  },
};
