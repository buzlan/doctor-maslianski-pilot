-- Web Push subscriptions, logical notification events, and deliveries.
-- Scheduled reminders and doctor-change pushes start disabled.
-- Hours and the clinic timezone live only in notification_policy.

CREATE TYPE public.notification_kind AS ENUM (
  'daily_morning',
  'daily_afternoon',
  'appointment_previous_day',
  'appointment_same_day',
  'assignment_changed',
  'appointment_changed',
  'appointment_cancelled',
  'treatment_updated',
  'treatment_completed',
  'manual_test'
);

CREATE TYPE public.push_delivery_status AS ENUM (
  'pending',
  'sent',
  'failed'
);

CREATE TABLE public.notification_policy (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  time_zone text NOT NULL DEFAULT 'Europe/Minsk',
  morning_time time NOT NULL DEFAULT time '09:00',
  afternoon_time time NOT NULL DEFAULT time '16:00',
  appointment_previous_day_time time NOT NULL DEFAULT time '19:00',
  appointment_same_day_time time NOT NULL DEFAULT time '09:00',
  slot_grace interval NOT NULL DEFAULT interval '15 minutes',
  coalesce_minutes integer NOT NULL DEFAULT 5 CHECK (coalesce_minutes BETWEEN 1 AND 60),
  scheduler_enabled boolean NOT NULL DEFAULT false,
  doctor_events_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.notification_policy (id) VALUES (1);

COMMENT ON TABLE public.notification_policy IS
  'Single source for notification timezone, slot times, and feature flags.';
COMMENT ON COLUMN public.notification_policy.scheduler_enabled IS
  'Scheduled reminders. Starts false until a physical iPhone test is approved.';
COMMENT ON COLUMN public.notification_policy.doctor_events_enabled IS
  'Doctor-change pushes. Starts false until a physical iPhone test is approved.';

CREATE TABLE public.push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  endpoint text NOT NULL UNIQUE CHECK (endpoint LIKE 'https://%' AND length(endpoint) BETWEEN 12 AND 2048),
  p256dh text NOT NULL CHECK (length(p256dh) BETWEEN 8 AND 256),
  auth text NOT NULL CHECK (length(auth) BETWEEN 8 AND 256),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  disabled_at timestamptz
);

CREATE INDEX push_subscriptions_patient_id_idx ON public.push_subscriptions (patient_id);

CREATE TRIGGER push_subscriptions_set_updated_at
  BEFORE UPDATE ON public.push_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.notification_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  kind public.notification_kind NOT NULL,
  route text NOT NULL CHECK (route IN ('/', '/diary', '/treatment', '/completed')),
  local_date date,
  slot text,
  dedupe_key text NOT NULL UNIQUE CHECK (length(dedupe_key) BETWEEN 8 AND 300),
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

CREATE INDEX notification_events_patient_id_idx ON public.notification_events (patient_id);
CREATE INDEX notification_events_unprocessed_idx
  ON public.notification_events (created_at)
  WHERE processed_at IS NULL;

CREATE TABLE public.push_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_event_id uuid NOT NULL REFERENCES public.notification_events (id) ON DELETE CASCADE,
  push_subscription_id uuid NOT NULL REFERENCES public.push_subscriptions (id) ON DELETE CASCADE,
  status public.push_delivery_status NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  error_code text,
  CONSTRAINT push_deliveries_event_subscription_unique
    UNIQUE (notification_event_id, push_subscription_id)
);

CREATE INDEX push_deliveries_subscription_id_idx ON public.push_deliveries (push_subscription_id);

ALTER TABLE public.notification_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_deliveries ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.notification_policy FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.push_subscriptions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.notification_events FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.push_deliveries FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE ON public.push_subscriptions TO authenticated;
GRANT ALL ON TABLE public.notification_policy TO service_role;
GRANT ALL ON TABLE public.push_subscriptions TO service_role;
GRANT ALL ON TABLE public.notification_events TO service_role;
GRANT ALL ON TABLE public.push_deliveries TO service_role;

CREATE POLICY push_subscriptions_select_own ON public.push_subscriptions
  FOR SELECT TO authenticated
  USING (patient_id = public.current_patient_id());

CREATE POLICY push_subscriptions_insert_own ON public.push_subscriptions
  FOR INSERT TO authenticated
  WITH CHECK (patient_id = public.current_patient_id());

CREATE POLICY push_subscriptions_update_own ON public.push_subscriptions
  FOR UPDATE TO authenticated
  USING (patient_id = public.current_patient_id())
  WITH CHECK (patient_id = public.current_patient_id());

-- ---------------------------------------------------------------------------
-- Clock and product rules. Hours are read from notification_policy.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.notification_local_date(p_now timestamptz, p_time_zone text)
RETURNS date
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT (p_now AT TIME ZONE p_time_zone)::date;
$$;

CREATE OR REPLACE FUNCTION public.notification_slot_due(
  p_now timestamptz,
  p_time_zone text,
  p_slot time,
  p_grace interval
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT (p_now AT TIME ZONE p_time_zone)::time >= p_slot
     AND (p_now AT TIME ZONE p_time_zone)::time < (p_slot + p_grace);
$$;

CREATE OR REPLACE FUNCTION public.notification_morning_kind(
  p_actions_pending boolean,
  p_diary_missing boolean,
  p_appointment_today boolean
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN p_actions_pending OR p_diary_missing THEN 'daily_morning'
    WHEN p_appointment_today THEN 'appointment_same_day'
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.notification_afternoon_kind(
  p_actions_pending boolean,
  p_diary_missing boolean
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN p_actions_pending OR p_diary_missing THEN 'daily_afternoon'
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.patient_actions_pending(p_treatment_id uuid, p_local_date date)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.treatments AS treatment
    JOIN public.action_assignments AS assignment
      ON assignment.treatment_id = treatment.id
    WHERE treatment.id = p_treatment_id
      AND treatment.status = 'active'
      AND assignment.status = 'active'
      AND p_local_date BETWEEN assignment.start_date AND assignment.end_date
      AND NOT EXISTS (
        SELECT 1
        FROM public.action_completions AS completion
        WHERE completion.assignment_id = assignment.id
          AND completion.completed_on = p_local_date
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.patient_diary_missing(p_treatment_id uuid, p_local_date date)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.treatments AS treatment
    WHERE treatment.id = p_treatment_id
      AND treatment.status = 'active'
      AND NOT EXISTS (
        SELECT 1
        FROM public.diary_entries AS entry
        WHERE entry.treatment_id = treatment.id
          AND entry.submitted_on = p_local_date
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.notification_target_subscription_ids(p_patient_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT subscription.id
  FROM public.push_subscriptions AS subscription
  WHERE subscription.patient_id = p_patient_id
    AND subscription.disabled_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.evaluate_due_notification_events(p_now timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  policy public.notification_policy%ROWTYPE;
  v_day date;
  inserted integer := 0;
  row_count integer := 0;
BEGIN
  SELECT * INTO policy FROM public.notification_policy WHERE id = 1;
  IF NOT FOUND OR NOT policy.scheduler_enabled THEN
    RETURN 0;
  END IF;

  v_day := public.notification_local_date(p_now, policy.time_zone);

  IF public.notification_slot_due(p_now, policy.time_zone, policy.morning_time, policy.slot_grace) THEN
    INSERT INTO public.notification_events (patient_id, kind, route, local_date, slot, dedupe_key)
    SELECT
      treatment.patient_id,
      chosen.kind::public.notification_kind,
      '/',
      v_day,
      CASE WHEN chosen.kind = 'daily_morning' THEN 'morning' ELSE 'appointment_same_day' END,
      CASE
        WHEN chosen.kind = 'daily_morning'
          THEN treatment.patient_id::text || ':' || v_day::text || ':daily:morning'
        ELSE treatment.patient_id::text || ':' || appointment.id::text || ':same-day'
      END
    FROM public.treatments AS treatment
    LEFT JOIN LATERAL (
      SELECT current_appointment.id
      FROM public.appointments AS current_appointment
      WHERE current_appointment.treatment_id = treatment.id
        AND current_appointment.status = 'current'
        AND current_appointment.wall_clock::date = v_day
      LIMIT 1
    ) AS appointment ON true
    CROSS JOIN LATERAL (
      SELECT public.notification_morning_kind(
        public.patient_actions_pending(treatment.id, v_day),
        public.patient_diary_missing(treatment.id, v_day),
        policy.appointment_same_day_time = policy.morning_time AND appointment.id IS NOT NULL
      ) AS kind
    ) AS chosen
    WHERE treatment.status = 'active'
      AND chosen.kind IS NOT NULL
    ON CONFLICT (dedupe_key) DO NOTHING;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    inserted := inserted + row_count;
  END IF;

  IF policy.appointment_same_day_time IS DISTINCT FROM policy.morning_time
     AND public.notification_slot_due(
       p_now,
       policy.time_zone,
       policy.appointment_same_day_time,
       policy.slot_grace
     )
  THEN
    INSERT INTO public.notification_events (patient_id, kind, route, local_date, slot, dedupe_key)
    SELECT
      treatment.patient_id,
      'appointment_same_day',
      '/',
      v_day,
      'appointment_same_day',
      treatment.patient_id::text || ':' || appointment.id::text || ':same-day'
    FROM public.treatments AS treatment
    JOIN public.appointments AS appointment
      ON appointment.treatment_id = treatment.id
     AND appointment.status = 'current'
     AND appointment.wall_clock::date = v_day
    WHERE treatment.status = 'active'
      AND public.notification_morning_kind(
        public.patient_actions_pending(treatment.id, v_day),
        public.patient_diary_missing(treatment.id, v_day),
        false
      ) IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.notification_events AS existing
        WHERE existing.patient_id = treatment.patient_id
          AND existing.local_date = v_day
          AND existing.kind = 'daily_morning'
      )
    ON CONFLICT (dedupe_key) DO NOTHING;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    inserted := inserted + row_count;
  END IF;

  IF public.notification_slot_due(p_now, policy.time_zone, policy.afternoon_time, policy.slot_grace) THEN
    INSERT INTO public.notification_events (patient_id, kind, route, local_date, slot, dedupe_key)
    SELECT
      treatment.patient_id,
      'daily_afternoon',
      '/',
      v_day,
      'afternoon',
      treatment.patient_id::text || ':' || v_day::text || ':daily:afternoon'
    FROM public.treatments AS treatment
    WHERE treatment.status = 'active'
      AND public.notification_afternoon_kind(
        public.patient_actions_pending(treatment.id, v_day),
        public.patient_diary_missing(treatment.id, v_day)
      ) IS NOT NULL
    ON CONFLICT (dedupe_key) DO NOTHING;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    inserted := inserted + row_count;
  END IF;

  IF public.notification_slot_due(
    p_now,
    policy.time_zone,
    policy.appointment_previous_day_time,
    policy.slot_grace
  ) THEN
    INSERT INTO public.notification_events (patient_id, kind, route, local_date, slot, dedupe_key)
    SELECT
      treatment.patient_id,
      'appointment_previous_day',
      '/',
      v_day,
      'appointment_previous_day',
      treatment.patient_id::text || ':' || appointment.id::text || ':previous-day'
    FROM public.treatments AS treatment
    JOIN public.appointments AS appointment
      ON appointment.treatment_id = treatment.id
     AND appointment.status = 'current'
     AND appointment.wall_clock::date = v_day + 1
    WHERE treatment.status = 'active'
    ON CONFLICT (dedupe_key) DO NOTHING;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    inserted := inserted + row_count;
  END IF;

  RETURN inserted;
END;
$$;

-- ---------------------------------------------------------------------------
-- Doctor changes. Events follow the committed row. Patient writes do not.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enqueue_doctor_notification(
  p_patient_id uuid,
  p_kind public.notification_kind,
  p_route text,
  p_subject text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  policy public.notification_policy%ROWTYPE;
  bucket bigint;
  event_id uuid;
BEGIN
  IF p_kind NOT IN (
    'assignment_changed',
    'appointment_changed',
    'appointment_cancelled',
    'treatment_updated',
    'treatment_completed'
  ) OR p_route NOT IN ('/', '/diary', '/treatment', '/completed') THEN
    RETURN NULL;
  END IF;

  SELECT * INTO policy FROM public.notification_policy WHERE id = 1;
  IF NOT FOUND OR NOT policy.doctor_events_enabled OR NOT public.is_staff() THEN
    RETURN NULL;
  END IF;

  bucket := floor(extract(epoch FROM clock_timestamp()) / (policy.coalesce_minutes * 60));

  INSERT INTO public.notification_events (patient_id, kind, route, dedupe_key)
  VALUES (
    p_patient_id,
    p_kind,
    p_route,
    p_patient_id::text || ':' || p_subject || ':' || p_kind::text || ':' || bucket::text
  )
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING id INTO event_id;

  IF event_id IS NOT NULL THEN
    PERFORM public.request_notification_dispatch();
  END IF;

  RETURN event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.action_assignments_enqueue_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  patient uuid;
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.start_date IS NOT DISTINCT FROM OLD.start_date
     AND NEW.end_date IS NOT DISTINCT FROM OLD.end_date
  THEN
    RETURN NULL;
  END IF;

  SELECT treatment.patient_id INTO patient
  FROM public.treatments AS treatment
  WHERE treatment.id = NEW.treatment_id;

  IF patient IS NOT NULL THEN
    PERFORM public.enqueue_doctor_notification(
      patient,
      'assignment_changed',
      '/',
      'assignment:' || NEW.id::text
    );
  END IF;

  RETURN NULL;
END;
$$;

CREATE TRIGGER action_assignments_enqueue_notification
  AFTER INSERT OR UPDATE OF status, start_date, end_date ON public.action_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.action_assignments_enqueue_notification();

CREATE OR REPLACE FUNCTION public.appointments_enqueue_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  patient uuid;
BEGIN
  SELECT treatment.patient_id INTO patient
  FROM public.treatments AS treatment
  WHERE treatment.id = NEW.treatment_id;

  IF patient IS NULL THEN
    RETURN NULL;
  END IF;

  IF NEW.status = 'current' THEN
    PERFORM public.enqueue_doctor_notification(
      patient,
      'appointment_changed',
      '/',
      'appointment:' || NEW.treatment_id::text
    );
  ELSIF NEW.status = 'superseded' AND NOT EXISTS (
    SELECT 1
    FROM public.appointments AS current_appointment
    WHERE current_appointment.treatment_id = NEW.treatment_id
      AND current_appointment.status = 'current'
  ) THEN
    PERFORM public.enqueue_doctor_notification(
      patient,
      'appointment_cancelled',
      '/',
      'appointment:' || NEW.treatment_id::text
    );
  END IF;

  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER appointments_enqueue_notification
  AFTER INSERT OR UPDATE OF status ON public.appointments
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.appointments_enqueue_notification();

CREATE OR REPLACE FUNCTION public.treatments_enqueue_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NULL;
  END IF;

  IF NEW.status = 'completed' THEN
    PERFORM public.enqueue_doctor_notification(
      NEW.patient_id,
      'treatment_completed',
      '/',
      'treatment:' || NEW.id::text
    );
  ELSE
    PERFORM public.enqueue_doctor_notification(
      NEW.patient_id,
      'treatment_updated',
      '/treatment',
      'treatment:' || NEW.id::text
    );
  END IF;

  RETURN NULL;
END;
$$;

CREATE TRIGGER treatments_enqueue_notification
  AFTER UPDATE OF status ON public.treatments
  FOR EACH ROW
  EXECUTE FUNCTION public.treatments_enqueue_notification();

CREATE OR REPLACE FUNCTION public.treatment_periods_enqueue_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  patient uuid;
BEGIN
  IF (
    SELECT count(*)
    FROM public.treatment_periods AS period
    WHERE period.treatment_id = NEW.treatment_id
  ) < 2 THEN
    RETURN NULL;
  END IF;

  SELECT treatment.patient_id INTO patient
  FROM public.treatments AS treatment
  WHERE treatment.id = NEW.treatment_id;

  IF patient IS NOT NULL THEN
    PERFORM public.enqueue_doctor_notification(
      patient,
      'treatment_updated',
      '/treatment',
      'treatment:' || NEW.treatment_id::text
    );
  END IF;

  RETURN NULL;
END;
$$;

CREATE TRIGGER treatment_periods_enqueue_notification
  AFTER INSERT ON public.treatment_periods
  FOR EACH ROW
  EXECUTE FUNCTION public.treatment_periods_enqueue_notification();

-- Best-effort wake-up for the delivery function. Never blocks the doctor write.
CREATE OR REPLACE FUNCTION public.request_notification_dispatch()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  dispatch_url text;
  dispatch_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RETURN;
  END IF;

  SELECT decrypted_secret INTO dispatch_url
  FROM vault.decrypted_secrets
  WHERE name = 'notification_dispatch_url'
  LIMIT 1;

  SELECT decrypted_secret INTO dispatch_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notification_cron_secret'
  LIMIT 1;

  IF dispatch_url IS NULL OR dispatch_secret IS NULL OR dispatch_url = '' OR dispatch_secret = '' THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := dispatch_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notification-cron-secret', dispatch_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
EXCEPTION WHEN OTHERS THEN
  RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_notification_evaluation()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.request_notification_dispatch();
$$;

DO $extensions$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_net unavailable';
END;
$extensions$;

DO $extensions$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron unavailable';
END;
$extensions$;

DO $schedule$
BEGIN
  IF to_regnamespace('cron') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM cron.job WHERE jobname = 'evaluate-patient-notifications'
     )
  THEN
    PERFORM cron.schedule(
      'evaluate-patient-notifications',
      '*/10 * * * *',
      'SELECT public.request_notification_evaluation()'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'notification cron not scheduled';
END;
$schedule$;

REVOKE ALL ON FUNCTION public.notification_local_date(timestamptz, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notification_slot_due(timestamptz, text, time, interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notification_morning_kind(boolean, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notification_afternoon_kind(boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.patient_actions_pending(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.patient_diary_missing(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notification_target_subscription_ids(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.evaluate_due_notification_events(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enqueue_doctor_notification(uuid, public.notification_kind, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.action_assignments_enqueue_notification() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.appointments_enqueue_notification() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.treatments_enqueue_notification() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.treatment_periods_enqueue_notification() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.request_notification_dispatch() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.request_notification_evaluation() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.notification_local_date(timestamptz, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.notification_slot_due(timestamptz, text, time, interval) TO service_role;
GRANT EXECUTE ON FUNCTION public.notification_morning_kind(boolean, boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.notification_afternoon_kind(boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.patient_actions_pending(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.patient_diary_missing(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.notification_target_subscription_ids(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.evaluate_due_notification_events(timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_notification_evaluation() TO service_role;
