-- Appointment reminders: 19:30 the day before, and one hour before the visit.
-- Patients can read their own notification events and mark them viewed.

ALTER TABLE public.notification_policy
  ADD COLUMN appointment_same_day_lead interval NOT NULL DEFAULT interval '1 hour';

COMMENT ON COLUMN public.notification_policy.appointment_same_day_lead IS
  'How long before the appointment wall clock the same-day reminder is due.';

UPDATE public.notification_policy
SET appointment_previous_day_time = time '19:30',
    updated_at = now()
WHERE id = 1;

ALTER TABLE public.notification_events
  ADD COLUMN read_at timestamptz;

COMMENT ON COLUMN public.notification_events.read_at IS
  'When the patient viewed this notification in the app. Null means unread.';

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
      'daily_morning',
      '/',
      v_day,
      'morning',
      treatment.patient_id::text || ':' || v_day::text || ':daily:morning'
    FROM public.treatments AS treatment
    WHERE treatment.status = 'active'
      AND public.notification_morning_kind(
        public.patient_actions_pending(treatment.id, v_day),
        public.patient_diary_missing(treatment.id, v_day),
        false
      ) IS NOT NULL
    ON CONFLICT (dedupe_key) DO NOTHING;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    inserted := inserted + row_count;
  END IF;

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
  WHERE treatment.status = 'active'
    AND (p_now AT TIME ZONE policy.time_zone) >= (appointment.wall_clock - policy.appointment_same_day_lead)
    AND (p_now AT TIME ZONE policy.time_zone) < (
      appointment.wall_clock - policy.appointment_same_day_lead + policy.slot_grace
    )
  ON CONFLICT (dedupe_key) DO NOTHING;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  inserted := inserted + row_count;

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

GRANT SELECT ON public.notification_events TO authenticated;
GRANT UPDATE (read_at) ON public.notification_events TO authenticated;

CREATE POLICY notification_events_select_own
  ON public.notification_events
  FOR SELECT
  TO authenticated
  USING (patient_id = public.current_patient_id());

CREATE POLICY notification_events_mark_read
  ON public.notification_events
  FOR UPDATE
  TO authenticated
  USING (patient_id = public.current_patient_id())
  WITH CHECK (patient_id = public.current_patient_id());
