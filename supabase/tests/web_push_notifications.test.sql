BEGIN;

SELECT * FROM no_plan();

CREATE FUNCTION pg_temp.as_user(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE FUNCTION pg_temp.as_super() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

SELECT is(
  (SELECT scheduler_enabled FROM public.notification_policy WHERE id = 1),
  false,
  'scheduled reminders start disabled'
);
SELECT is(
  (SELECT doctor_events_enabled FROM public.notification_policy WHERE id = 1),
  false,
  'doctor-change pushes start disabled'
);
SELECT is(
  (SELECT time_zone FROM public.notification_policy WHERE id = 1),
  'Europe/Minsk',
  'policy timezone is Europe/Minsk'
);
SELECT is(
  (SELECT morning_time FROM public.notification_policy WHERE id = 1),
  time '09:00',
  'morning slot is 09:00'
);
SELECT is(
  (SELECT afternoon_time FROM public.notification_policy WHERE id = 1),
  time '19:00',
  'evening slot is 19:00'
);
SELECT is(
  (SELECT appointment_previous_day_time FROM public.notification_policy WHERE id = 1),
  time '19:30',
  'previous-day slot is 19:30'
);
SELECT is(
  (SELECT appointment_same_day_lead FROM public.notification_policy WHERE id = 1),
  interval '1 hour',
  'same-day appointment reminder is one hour before the visit'
);

SELECT is(
  public.notification_local_date('2026-10-09 21:00:00+00'::timestamptz, 'Europe/Minsk'),
  DATE '2026-10-10',
  'local date uses the policy timezone rather than UTC'
);
SELECT ok(
  public.notification_slot_due(
    '2026-10-10 06:00:00+00'::timestamptz,
    'Europe/Minsk',
    time '09:00',
    interval '15 minutes'
  ),
  '09:00 Minsk is due'
);
SELECT ok(
  public.notification_slot_due(
    '2026-10-10 06:14:00+00'::timestamptz,
    'Europe/Minsk',
    time '09:00',
    interval '15 minutes'
  ),
  '09:14 Minsk is still inside the grace window'
);
SELECT ok(
  NOT public.notification_slot_due(
    '2026-10-10 06:15:00+00'::timestamptz,
    'Europe/Minsk',
    time '09:00',
    interval '15 minutes'
  ),
  '09:15 Minsk is outside the grace window'
);
SELECT is(
  public.notification_morning_kind(true, false, true),
  'daily_morning',
  'pending actions and an appointment merge into one morning event'
);
SELECT is(
  public.notification_morning_kind(false, true, true),
  'daily_morning',
  'a missing diary and an appointment merge into one morning event'
);
SELECT is(
  public.notification_morning_kind(false, false, true),
  'appointment_same_day',
  'an appointment alone uses the appointment morning event'
);
SELECT is(
  public.notification_morning_kind(false, false, false),
  NULL,
  'a clear morning creates no event'
);
SELECT is(
  public.notification_afternoon_kind(false, false),
  NULL,
  'a finished afternoon creates no event'
);
SELECT is(
  public.notification_afternoon_kind(true, false),
  'daily_afternoon',
  'a pending afternoon creates one reminder'
);

INSERT INTO auth.users (id) VALUES
  ('e7100000-0000-4000-8000-000000000002'),
  ('e7100000-0000-4000-8000-000000000003'),
  ('e7100000-0000-4000-8000-000000000004');

INSERT INTO public.clinics (id, name, time_zone)
VALUES ('e7100000-0000-4000-8000-000000000001', 'Synthetic Push Clinic', 'Europe/Minsk');

INSERT INTO public.clinic_staff (clinic_id, auth_user_id, display_name)
VALUES (
  'e7100000-0000-4000-8000-000000000001',
  'e7100000-0000-4000-8000-000000000002',
  'Synthetic Push Staff'
);

INSERT INTO public.patients (id, clinic_id, auth_user_id, clinic_label, pilot_cohort) VALUES
  ('e7100000-0000-4000-8000-000000000011', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000003', 'Synthetic Push A', 'internal_dry_run'),
  ('e7100000-0000-4000-8000-000000000012', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000004', 'Synthetic Push B', 'internal_dry_run'),
  ('e7100000-0000-4000-8000-000000000013', 'e7100000-0000-4000-8000-000000000001', NULL, 'Synthetic Push C', 'internal_dry_run'),
  ('e7100000-0000-4000-8000-000000000014', 'e7100000-0000-4000-8000-000000000001', NULL, 'Synthetic Push D', 'internal_dry_run'),
  ('e7100000-0000-4000-8000-000000000015', 'e7100000-0000-4000-8000-000000000001', NULL, 'Synthetic Push E', 'internal_dry_run'),
  ('e7100000-0000-4000-8000-000000000016', 'e7100000-0000-4000-8000-000000000001', NULL, 'Synthetic Push F', 'internal_dry_run');

INSERT INTO public.treatments (id, patient_id, clinic_id, status) VALUES
  ('e7100000-0000-4000-8000-000000000021', 'e7100000-0000-4000-8000-000000000011', 'e7100000-0000-4000-8000-000000000001', 'active'),
  ('e7100000-0000-4000-8000-000000000022', 'e7100000-0000-4000-8000-000000000012', 'e7100000-0000-4000-8000-000000000001', 'active'),
  ('e7100000-0000-4000-8000-000000000023', 'e7100000-0000-4000-8000-000000000013', 'e7100000-0000-4000-8000-000000000001', 'active'),
  ('e7100000-0000-4000-8000-000000000024', 'e7100000-0000-4000-8000-000000000014', 'e7100000-0000-4000-8000-000000000001', 'active'),
  ('e7100000-0000-4000-8000-000000000025', 'e7100000-0000-4000-8000-000000000015', 'e7100000-0000-4000-8000-000000000001', 'completed'),
  ('e7100000-0000-4000-8000-000000000026', 'e7100000-0000-4000-8000-000000000016', 'e7100000-0000-4000-8000-000000000001', 'active');

INSERT INTO public.action_catalog_items (id, clinic_id, title, status) VALUES
  ('e7100000-0000-4000-8000-000000000031', 'e7100000-0000-4000-8000-000000000001', 'Synthetic action', 'approved');

INSERT INTO public.action_assignments (
  id, treatment_id, clinic_id, catalog_item_id, title, start_date, end_date, status
) VALUES
  (
    'e7100000-0000-4000-8000-000000000041',
    'e7100000-0000-4000-8000-000000000021',
    'e7100000-0000-4000-8000-000000000001',
    'e7100000-0000-4000-8000-000000000031',
    'Synthetic action',
    DATE '2026-10-10',
    DATE '2026-10-10',
    'active'
  ),
  (
    'e7100000-0000-4000-8000-000000000042',
    'e7100000-0000-4000-8000-000000000026',
    'e7100000-0000-4000-8000-000000000001',
    'e7100000-0000-4000-8000-000000000031',
    'Synthetic action',
    DATE '2026-10-12',
    DATE '2026-10-12',
    'active'
  ),
  (
    'e7100000-0000-4000-8000-000000000043',
    'e7100000-0000-4000-8000-000000000023',
    'e7100000-0000-4000-8000-000000000001',
    'e7100000-0000-4000-8000-000000000031',
    'Synthetic action',
    DATE '2026-10-10',
    DATE '2026-10-10',
    'active'
  );

SELECT is(
  public.evaluate_due_notification_events('2026-10-10 06:00:00+00'::timestamptz),
  0,
  'a disabled scheduler creates no events'
);

UPDATE public.notification_policy SET scheduler_enabled = true WHERE id = 1;

SELECT is(
  public.patient_actions_pending('e7100000-0000-4000-8000-000000000021', DATE '2026-10-10'),
  true,
  'an open assignment is pending'
);
SELECT is(
  public.patient_diary_missing('e7100000-0000-4000-8000-000000000021', DATE '2026-10-10'),
  true,
  'an active treatment without a diary entry is missing'
);
SELECT is(
  public.patient_diary_missing('e7100000-0000-4000-8000-000000000025', DATE '2026-10-10'),
  false,
  'a completed treatment does not expect a diary reminder'
);

SELECT cmp_ok(
  public.evaluate_due_notification_events('2026-10-10 06:00:00+00'::timestamptz),
  '>=',
  1,
  'morning evaluation creates events'
);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000011' AND kind = 'daily_morning'
  ),
  1,
  'pending work creates one morning event'
);
SELECT is(
  public.evaluate_due_notification_events('2026-10-10 06:05:00+00'::timestamptz),
  0,
  'a repeated scheduler run does not create a duplicate'
);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000011' AND kind = 'daily_morning'
  ),
  1,
  'the morning dedupe key stays unique'
);

INSERT INTO public.action_completions (
  assignment_id, treatment_id, patient_id, clinic_id, completed_on
) VALUES (
  'e7100000-0000-4000-8000-000000000041',
  'e7100000-0000-4000-8000-000000000021',
  'e7100000-0000-4000-8000-000000000011',
  'e7100000-0000-4000-8000-000000000001',
  DATE '2026-10-10'
);
INSERT INTO public.diary_entries (
  treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
) VALUES (
  'e7100000-0000-4000-8000-000000000021',
  'e7100000-0000-4000-8000-000000000011',
  'e7100000-0000-4000-8000-000000000001',
  DATE '2026-10-10',
  0, 0, 'unchanged'
);

SELECT is(
  public.patient_actions_pending('e7100000-0000-4000-8000-000000000021', DATE '2026-10-10'),
  false,
  'a completion clears the pending action'
);
SELECT is(
  public.patient_diary_missing('e7100000-0000-4000-8000-000000000021', DATE '2026-10-10'),
  false,
  'a diary entry clears the missing diary'
);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000011'
      AND kind IN ('assignment_changed', 'treatment_updated')
  ),
  0,
  'a patient completion and diary save do not create a push event'
);
SELECT public.evaluate_due_notification_events('2026-10-10 16:00:00+00'::timestamptz);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000011' AND kind = 'daily_afternoon'
  ),
  0,
  'afternoon stays empty when the day is done'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000013' AND kind = 'daily_afternoon'
  ),
  1,
  'unfinished work creates one afternoon reminder'
);
SELECT is(
  public.evaluate_due_notification_events('2026-10-10 16:05:00+00'::timestamptz),
  0,
  'a repeated afternoon run does not duplicate'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000015'
  ),
  0,
  'an inactive treatment does not get a daily reminder'
);

UPDATE public.notification_policy SET morning_time = time '10:00' WHERE id = 1;
SELECT is(
  public.evaluate_due_notification_events('2026-10-12 06:00:00+00'::timestamptz),
  0,
  '09:00 does nothing after the policy morning hour moves'
);
SELECT public.evaluate_due_notification_events('2026-10-12 07:00:00+00'::timestamptz);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000016'
      AND kind = 'daily_morning'
      AND local_date = DATE '2026-10-12'
  ),
  1,
  'the moved policy hour creates the morning event'
);
UPDATE public.notification_policy SET morning_time = time '09:00' WHERE id = 1;

INSERT INTO public.diary_entries (
  treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
) VALUES (
  'e7100000-0000-4000-8000-000000000022',
  'e7100000-0000-4000-8000-000000000012',
  'e7100000-0000-4000-8000-000000000001',
  DATE '2026-10-11',
  0, 0, 'unchanged'
);
INSERT INTO public.appointments (
  id, treatment_id, clinic_id, status, wall_clock, time_zone, at_utc
) VALUES (
  'e7100000-0000-4000-8000-000000000051',
  'e7100000-0000-4000-8000-000000000022',
  'e7100000-0000-4000-8000-000000000001',
  'current',
  timestamp '2026-10-11 11:00:00',
  'Europe/Minsk',
  timestamp '2026-10-11 11:00:00' AT TIME ZONE 'Europe/Minsk'
);
SET CONSTRAINTS appointments_enqueue_notification IMMEDIATE;

SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE kind = 'appointment_changed'
  ),
  0,
  'creating an appointment while doctor pushes are disabled does not notify'
);
SELECT cmp_ok(
  public.evaluate_due_notification_events('2026-10-10 16:35:00+00'::timestamptz),
  '>=',
  1,
  'the previous-day slot creates an appointment reminder'
);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000012'
      AND kind = 'appointment_previous_day'
  ),
  1,
  'a current appointment is reminded the previous evening'
);

UPDATE public.appointments
SET status = 'superseded', superseded_at = now()
WHERE id = 'e7100000-0000-4000-8000-000000000051';
SET CONSTRAINTS appointments_enqueue_notification IMMEDIATE;
SELECT is(
  public.evaluate_due_notification_events('2026-10-10 16:05:00+00'::timestamptz),
  0,
  'a cancelled appointment is not reminded again'
);

INSERT INTO public.diary_entries (
  treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
) VALUES (
  'e7100000-0000-4000-8000-000000000024',
  'e7100000-0000-4000-8000-000000000014',
  'e7100000-0000-4000-8000-000000000001',
  DATE '2026-10-13',
  0, 0, 'unchanged'
);
INSERT INTO public.appointments (
  id, treatment_id, clinic_id, status, wall_clock, time_zone, at_utc
) VALUES (
  'e7100000-0000-4000-8000-000000000052',
  'e7100000-0000-4000-8000-000000000024',
  'e7100000-0000-4000-8000-000000000001',
  'current',
  timestamp '2026-10-13 11:00:00',
  'Europe/Minsk',
  timestamp '2026-10-13 11:00:00' AT TIME ZONE 'Europe/Minsk'
);
SET CONSTRAINTS appointments_enqueue_notification IMMEDIATE;
SELECT public.evaluate_due_notification_events('2026-10-13 07:05:00+00'::timestamptz);
SELECT is(
  (
    SELECT kind::text FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000014'
      AND local_date = DATE '2026-10-13'
  ),
  'appointment_same_day',
  'an appointment is reminded one hour before the visit'
);

INSERT INTO public.appointments (
  id, treatment_id, clinic_id, status, wall_clock, time_zone, at_utc
) VALUES (
  'e7100000-0000-4000-8000-000000000053',
  'e7100000-0000-4000-8000-000000000023',
  'e7100000-0000-4000-8000-000000000001',
  'current',
  timestamp '2026-10-14 11:00:00',
  'Europe/Minsk',
  timestamp '2026-10-14 11:00:00' AT TIME ZONE 'Europe/Minsk'
);
SET CONSTRAINTS appointments_enqueue_notification IMMEDIATE;
SELECT public.evaluate_due_notification_events('2026-10-14 06:00:00+00'::timestamptz);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000013'
      AND kind = 'daily_morning'
      AND local_date = DATE '2026-10-14'
  ),
  1,
  'pending work plus an appointment is one morning event'
);
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000013'
      AND kind = 'appointment_same_day'
  ),
  0,
  'the merged morning does not also send an appointment push'
);

UPDATE public.notification_policy SET doctor_events_enabled = true WHERE id = 1;
SELECT pg_temp.as_user('e7100000-0000-4000-8000-000000000002');

SELECT lives_ok(
  $$UPDATE public.action_assignments
    SET end_date = DATE '2026-10-11'
    WHERE id = 'e7100000-0000-4000-8000-000000000041'$$,
  'staff can change an assignment'
);
SELECT lives_ok(
  $$UPDATE public.action_assignments
    SET end_date = DATE '2026-10-12'
    WHERE id = 'e7100000-0000-4000-8000-000000000041'$$,
  'a second quick save still succeeds'
);

SELECT pg_temp.as_super();
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000011'
      AND kind = 'assignment_changed'
  ),
  1,
  'rapid assignment saves coalesce into one event'
);

SELECT pg_temp.as_user('e7100000-0000-4000-8000-000000000002');
SELECT lives_ok(
  $$SELECT public.replace_current_appointment(
    'e7100000-0000-4000-8000-000000000022',
    timestamp '2026-10-20 15:00:00'
  )$$,
  'staff can replace an appointment'
);
SELECT lives_ok(
  $$SELECT public.replace_current_appointment(
    'e7100000-0000-4000-8000-000000000022',
    timestamp '2026-10-21 15:00:00'
  )$$,
  'a second appointment save succeeds'
);
SET CONSTRAINTS appointments_enqueue_notification IMMEDIATE;
SELECT pg_temp.as_super();
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000012'
      AND kind = 'appointment_changed'
  ),
  1,
  'rapid appointment changes coalesce into one event'
);

SELECT pg_temp.as_user('e7100000-0000-4000-8000-000000000002');
SELECT lives_ok(
  $$UPDATE public.appointments
    SET status = 'superseded', superseded_at = now()
    WHERE treatment_id = 'e7100000-0000-4000-8000-000000000024'
      AND status = 'current'$$,
  'staff can cancel the current appointment'
);
SET CONSTRAINTS appointments_enqueue_notification IMMEDIATE;
SELECT pg_temp.as_super();
SELECT is(
  (
    SELECT count(*)::int FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000014'
      AND kind = 'appointment_cancelled'
  ),
  1,
  'cancelling an appointment creates one event'
);

SELECT pg_temp.as_user('e7100000-0000-4000-8000-000000000002');
SELECT lives_ok(
  $$UPDATE public.treatments
    SET status = 'completed', completed_at = now()
    WHERE id = 'e7100000-0000-4000-8000-000000000026'$$,
  'staff can complete a treatment'
);
SELECT pg_temp.as_super();
SELECT is(
  (
    SELECT route FROM public.notification_events
    WHERE patient_id = 'e7100000-0000-4000-8000-000000000016'
      AND kind = 'treatment_completed'
  ),
  '/',
  'treatment completion notifies without a second patient or invite'
);

SELECT pg_temp.as_user('e7100000-0000-4000-8000-000000000003');
SELECT throws_ok(
  $$INSERT INTO public.notification_events (patient_id, kind, route, dedupe_key)
    VALUES (
      'e7100000-0000-4000-8000-000000000011',
      'manual_test',
      '/',
      'patient-forged-manual-test'
    )$$,
  '42501',
  NULL,
  'a patient cannot insert notification events'
);

SELECT lives_ok(
  $$INSERT INTO public.push_subscriptions (patient_id, endpoint, p256dh, auth)
    VALUES (
      'e7100000-0000-4000-8000-000000000011',
      'https://push.example.test/device-a',
      'p256dh-device-a',
      'auth-device-a'
    )$$,
  'a patient can store their own subscription'
);
SELECT lives_ok(
  $$INSERT INTO public.push_subscriptions (patient_id, endpoint, p256dh, auth)
    VALUES (
      'e7100000-0000-4000-8000-000000000011',
      'https://push.example.test/device-b',
      'p256dh-device-b',
      'auth-device-b'
    )$$,
  'the same patient can store a second device'
);
SELECT throws_ok(
  $$INSERT INTO public.push_subscriptions (patient_id, endpoint, p256dh, auth)
    VALUES (
      'e7100000-0000-4000-8000-000000000011',
      'https://push.example.test/device-a',
      'p256dh-device-a2',
      'auth-device-a2'
    )$$,
  '23505',
  NULL,
  'a duplicate endpoint is rejected'
);
SELECT throws_ok(
  $$INSERT INTO public.push_subscriptions (patient_id, endpoint, p256dh, auth)
    VALUES (
      'e7100000-0000-4000-8000-000000000012',
      'https://push.example.test/foreign',
      'p256dh-foreign',
      'auth-foreign'
    )$$,
  '42501',
  NULL,
  'a patient cannot store a subscription for someone else'
);
SELECT is(
  (SELECT count(*)::int FROM public.push_subscriptions),
  2,
  'the patient sees only their own subscriptions'
);

SELECT pg_temp.as_user('e7100000-0000-4000-8000-000000000002');
SELECT is(
  (SELECT count(*)::int FROM public.push_subscriptions),
  0,
  'staff cannot read push subscription secrets'
);

SELECT pg_temp.as_super();
UPDATE public.push_subscriptions
SET disabled_at = now()
WHERE endpoint = 'https://push.example.test/device-b';
SELECT is(
  (
    SELECT count(*)::int
    FROM public.notification_target_subscription_ids('e7100000-0000-4000-8000-000000000011')
  ),
  1,
  'a disabled endpoint is ignored'
);

SET ROLE anon;
SELECT throws_ok(
  $$SELECT * FROM public.push_subscriptions$$,
  '42501',
  NULL,
  'anon cannot read subscriptions'
);
RESET ROLE;

SELECT throws_ok(
  $$INSERT INTO public.notification_events (patient_id, kind, route, dedupe_key)
    VALUES (
      'e7100000-0000-4000-8000-000000000011',
      'daily_morning',
      '/',
      'e7100000-0000-4000-8000-000000000011:2026-10-10:daily:morning'
    )$$,
  '23505',
  NULL,
  'the dedupe key unique constraint blocks a second morning event'
);

SELECT * FROM finish();
ROLLBACK;
