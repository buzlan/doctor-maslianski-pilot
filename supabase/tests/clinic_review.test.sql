BEGIN;

SELECT * FROM no_plan();

CREATE OR REPLACE FUNCTION pg_temp.login(uid uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', uid::text,
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.logout()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.create_auth_user(p_id uuid, p_email text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token,
    is_sso_user, is_anonymous
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    p_id,
    'authenticated',
    'authenticated',
    p_email,
    extensions.crypt('synthetic-test-password', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    now(),
    now(),
    '', '', '', '',
    false,
    false
  );

  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, provider_id
  ) VALUES (
    gen_random_uuid(),
    p_id,
    jsonb_build_object('sub', p_id::text, 'email', p_email),
    'email',
    now(), now(), now(),
    p_id::text
  );
END;
$$;

SELECT pg_temp.create_auth_user(
  'e0000000-0000-4000-8000-000000000012',
  'staff.b.clinic-review@local.test'
);
SELECT pg_temp.create_auth_user(
  'e0000000-0000-4000-8000-0000000000a1',
  'patient.clinic-review@local.test'
);

INSERT INTO public.clinics (id, name, time_zone)
VALUES ('e0000000-0000-4000-8000-000000000002', 'Synthetic Clinic B Review', 'Europe/Minsk');

INSERT INTO public.clinic_staff (id, clinic_id, auth_user_id, display_name)
VALUES (
  'e0000000-0000-4000-8000-000000000013',
  'e0000000-0000-4000-8000-000000000002',
  'e0000000-0000-4000-8000-000000000012',
  'Synthetic Staff B Review'
);

INSERT INTO public.patients (id, clinic_id, clinic_label, auth_user_id)
VALUES (
  'e0000000-0000-4000-8000-0000000000a0',
  '10000000-0000-4000-8000-000000000001',
  'Synthetic Review Patient',
  'e0000000-0000-4000-8000-0000000000a1'
);

-- ---------------------------------------------------------------------------
-- EXECUTE grants
-- ---------------------------------------------------------------------------

SELECT ok(
  NOT has_function_privilege('anon', 'public.create_unactivated_patient(text, date, boolean)', 'execute'),
  'anon cannot execute create_unactivated_patient'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.delete_patient(uuid)', 'execute'),
  'anon cannot execute delete_patient'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.assign_catalog_item_to_treatment(uuid, uuid, date, date)', 'execute'),
  'anon cannot execute assign_catalog_item_to_treatment'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.start_new_treatment_period(uuid, date, date)', 'execute'),
  'anon cannot execute start_new_treatment_period'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.replace_current_appointment(uuid, timestamp)', 'execute'),
  'anon cannot execute replace_current_appointment'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.create_unactivated_patient(text, date, boolean)', 'execute'),
  'authenticated can execute create_unactivated_patient'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.delete_patient(uuid)', 'execute'),
  'authenticated can execute delete_patient'
);

-- ---------------------------------------------------------------------------
-- Non-staff cannot create
-- ---------------------------------------------------------------------------

SELECT pg_temp.login('e0000000-0000-4000-8000-0000000000a1');
SELECT throws_ok(
  $$SELECT public.create_unactivated_patient('Should Fail', DATE '2026-09-04')$$,
  '42501',
  NULL,
  'patient cannot create_unactivated_patient'
);
SELECT pg_temp.logout();

-- ---------------------------------------------------------------------------
-- Staff create + label update; bind columns stay blocked
-- ---------------------------------------------------------------------------

SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');

SELECT lives_ok(
  $$SELECT public.create_unactivated_patient('Clinic Label One', DATE '2026-09-01')$$,
  'staff can create an unactivated patient'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.patients
    WHERE clinic_label = 'Clinic Label One'
      AND auth_user_id IS NULL
      AND pilot_cohort IS NULL
      AND is_test = false
  ),
  1,
  'created patient has label, null bind columns, and is not a test patient'
);

SELECT is(
  (
    SELECT t.status
    FROM public.treatments t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One'
  ),
  'active',
  'created treatment is active sclerotherapy'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.treatment_periods tp
    JOIN public.treatments t ON t.id = tp.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One'
      AND tp.ended_on IS NULL
      AND tp.started_on = DATE '2026-09-01'
  ),
  1,
  'created treatment has one open period'
);

SELECT lives_ok(
  $$UPDATE public.patients
      SET clinic_label = 'Clinic Label One Edited'
    WHERE clinic_label = 'Clinic Label One'$$,
  'staff can update clinic_label'
);

SELECT lives_ok(
  $$UPDATE public.patients
      SET is_test = true
    WHERE clinic_label = 'Clinic Label One Edited'$$,
  'staff can mark a patient as test'
);

SELECT is(
  (
    SELECT is_test FROM public.patients
    WHERE clinic_label = 'Clinic Label One Edited'
  ),
  true,
  'test flag is stored'
);

SELECT lives_ok(
  $$UPDATE public.patients
      SET is_test = false
    WHERE clinic_label = 'Clinic Label One Edited'$$,
  'staff can clear the test flag'
);

SELECT throws_ok(
  $$UPDATE public.patients
      SET auth_user_id = '10000000-0000-4000-8000-000000000010'
    WHERE clinic_label = 'Clinic Label One Edited'$$,
  '42501',
  NULL,
  'staff cannot set patients.auth_user_id'
);

SELECT throws_ok(
  $$UPDATE public.patients
      SET pilot_cohort = 'internal_dry_run'
    WHERE clinic_label = 'Clinic Label One Edited'$$,
  '42501',
  NULL,
  'staff cannot set patients.pilot_cohort'
);

-- ---------------------------------------------------------------------------
-- Catalog approve / assign / re-approval
-- ---------------------------------------------------------------------------

INSERT INTO public.action_catalog_items (id, clinic_id, title, instruction, status)
VALUES (
  'e0000000-0000-4000-8000-0000000000c1',
  '10000000-0000-4000-8000-000000000001',
  'Approved wording',
  'Do the approved thing',
  'approved'
);

INSERT INTO public.action_catalog_items (id, clinic_id, title, instruction, status)
VALUES (
  'e0000000-0000-4000-8000-0000000000c2',
  '10000000-0000-4000-8000-000000000001',
  'Draft wording',
  NULL,
  'draft'
);

SELECT is(
  public.assign_catalog_item_to_treatment(
    (
      SELECT t.id FROM public.treatments t
      JOIN public.patients p ON p.id = t.patient_id
      WHERE p.clinic_label = 'Clinic Label One Edited'
    ),
    'e0000000-0000-4000-8000-0000000000c1',
    DATE '2026-09-01',
    DATE '2026-09-14'
  ) IS NOT NULL,
  true,
  'staff can assign an approved catalog item'
);

SELECT is(
  (
    SELECT a.title
    FROM public.action_assignments a
    JOIN public.treatments t ON t.id = a.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
  ),
  'Approved wording',
  'assignment copies approved title'
);

SELECT throws_ok(
  $$SELECT public.assign_catalog_item_to_treatment(
      (
        SELECT t.id FROM public.treatments t
        JOIN public.patients p ON p.id = t.patient_id
        WHERE p.clinic_label = 'Clinic Label One Edited'
      ),
      'e0000000-0000-4000-8000-0000000000c2',
      DATE '2026-09-01',
      DATE '2026-09-14'
    )$$,
  '23514',
  NULL,
  'assign RPC rejects draft catalog items'
);

SELECT throws_ok(
  $$INSERT INTO public.action_assignments (
      treatment_id, clinic_id, catalog_item_id, title, instruction,
      start_date, end_date
    ) VALUES (
      (
        SELECT t.id FROM public.treatments t
        JOIN public.patients p ON p.id = t.patient_id
        WHERE p.clinic_label = 'Clinic Label One Edited'
      ),
      '10000000-0000-4000-8000-000000000001',
      'e0000000-0000-4000-8000-0000000000c2',
      'Invented draft title',
      'invented',
      DATE '2026-09-01',
      DATE '2026-09-14'
    )$$,
  '23514',
  NULL,
  'direct INSERT cannot assign a draft catalog item'
);

INSERT INTO public.action_assignments (
  treatment_id, clinic_id, catalog_item_id, title, instruction,
  start_date, end_date
) VALUES (
  (
    SELECT t.id FROM public.treatments t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
  ),
  '10000000-0000-4000-8000-000000000001',
  'e0000000-0000-4000-8000-0000000000c1',
  'Invented approved title',
  'invented instruction',
  DATE '2026-09-15',
  DATE '2026-09-20'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.action_assignments
    WHERE title = 'Invented approved title'
  ),
  0,
  'direct INSERT cannot persist invented assignment wording'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.action_assignments a
    JOIN public.treatments t ON t.id = a.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
      AND a.title = 'Approved wording'
      AND a.instruction = 'Do the approved thing'
  ),
  2,
  'direct INSERT of an approved item copies catalog wording'
);

UPDATE public.action_catalog_items
SET title = 'Changed wording', status = 'approved'
WHERE id = 'e0000000-0000-4000-8000-0000000000c1';

SELECT is(
  (
    SELECT status FROM public.action_catalog_items
    WHERE id = 'e0000000-0000-4000-8000-0000000000c1'
  ),
  'draft',
  'editing approved catalog wording forces draft'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.action_assignments
    WHERE catalog_item_id = 'e0000000-0000-4000-8000-0000000000c1'
      AND title = 'Approved wording'
  ),
  2,
  'catalog wording edit does not rewrite assignment snapshots'
);

SELECT throws_ok(
  $$UPDATE public.action_assignments
      SET title = 'Rewrite snapshot'
    WHERE catalog_item_id = 'e0000000-0000-4000-8000-0000000000c1'$$,
  '42501',
  NULL,
  'assignment title cannot be updated'
);

-- ---------------------------------------------------------------------------
-- Period transition atomicity
-- ---------------------------------------------------------------------------

SELECT throws_ok(
  format(
    'SELECT public.start_new_treatment_period(%L, DATE ''2026-09-04'', NULL)',
    (
      SELECT t.id FROM public.treatments t
      JOIN public.patients p ON p.id = t.patient_id
      WHERE p.clinic_label = 'Clinic Label One Edited'
    )
  ),
  '23502',
  NULL,
  'period transition without started_on fails'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.treatment_periods tp
    JOIN public.treatments t ON t.id = tp.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
      AND tp.ended_on IS NULL
      AND tp.started_on = DATE '2026-09-01'
  ),
  1,
  'failed period transition leaves the original open period'
);

SELECT lives_ok(
  format(
    'SELECT public.start_new_treatment_period(%L, DATE ''2026-09-04'', DATE ''2026-09-05'')',
    (
      SELECT t.id FROM public.treatments t
      JOIN public.patients p ON p.id = t.patient_id
      WHERE p.clinic_label = 'Clinic Label One Edited'
    )
  ),
  'staff can start a new treatment period'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.treatment_periods tp
    JOIN public.treatments t ON t.id = tp.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
  ),
  2,
  'historical period is preserved after transition'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.treatment_periods tp
    JOIN public.treatments t ON t.id = tp.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
      AND tp.ended_on IS NULL
      AND tp.started_on = DATE '2026-09-05'
  ),
  1,
  'new period is the only open period'
);

-- ---------------------------------------------------------------------------
-- Appointment replacement
-- ---------------------------------------------------------------------------

SELECT lives_ok(
  format(
    'SELECT public.replace_current_appointment(%L, TIMESTAMP ''2026-09-15 14:30:00'')',
    (
      SELECT t.id FROM public.treatments t
      JOIN public.patients p ON p.id = t.patient_id
      WHERE p.clinic_label = 'Clinic Label One Edited'
    )
  ),
  'staff can set a current appointment'
);

SELECT is(
  (
    SELECT a.time_zone
    FROM public.appointments a
    JOIN public.treatments t ON t.id = a.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
      AND a.status = 'current'
  ),
  'Europe/Minsk',
  'appointment time_zone is copied from the clinic'
);

SELECT lives_ok(
  format(
    'SELECT public.replace_current_appointment(%L, TIMESTAMP ''2026-09-20 10:00:00'')',
    (
      SELECT t.id FROM public.treatments t
      JOIN public.patients p ON p.id = t.patient_id
      WHERE p.clinic_label = 'Clinic Label One Edited'
    )
  ),
  'staff can replace the current appointment'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM public.appointments a
    JOIN public.treatments t ON t.id = a.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
      AND a.status = 'superseded'
  ),
  1,
  'previous appointment remains as superseded history'
);

SELECT is(
  (
    SELECT a.wall_clock
    FROM public.appointments a
    JOIN public.treatments t ON t.id = a.treatment_id
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.clinic_label = 'Clinic Label One Edited'
      AND a.status = 'current'
  ),
  TIMESTAMP '2026-09-20 10:00:00',
  'current appointment uses the new wall-clock'
);

SELECT pg_temp.logout();

-- ---------------------------------------------------------------------------
-- Cross-clinic isolation
-- ---------------------------------------------------------------------------

SELECT pg_temp.login('e0000000-0000-4000-8000-000000000012');

SELECT is(
  (
    SELECT count(*)::int FROM public.patients
    WHERE clinic_label = 'Clinic Label One Edited'
  ),
  0,
  'staff B cannot see clinic A patient created by RPC'
);

SELECT throws_ok(
  $$SELECT public.assign_catalog_item_to_treatment(
      '10000000-0000-4000-8000-000000000021',
      'e0000000-0000-4000-8000-0000000000c1',
      DATE '2026-09-01',
      DATE '2026-09-14'
    )$$,
  'P0002',
  NULL,
  'staff B cannot assign clinic A catalog or seed treatment'
);

SELECT throws_ok(
  $$SELECT public.start_new_treatment_period(
      '10000000-0000-4000-8000-000000000021',
      DATE '2026-09-04',
      DATE '2026-09-05'
    )$$,
  'P0002',
  NULL,
  'staff B cannot start a period on clinic A treatment'
);

UPDATE public.patients
SET clinic_label = 'Hijacked'
WHERE clinic_label = 'Clinic Label One Edited';

SELECT is(
  (
    SELECT count(*)::int FROM public.patients
    WHERE clinic_label = 'Hijacked'
  ),
  0,
  'staff B cannot update clinic A clinic_label'
);

UPDATE public.patients
SET is_test = true
WHERE clinic_label = 'Clinic Label One Edited';

SELECT is(
  (
    SELECT count(*)::int FROM public.patients
    WHERE clinic_label = 'Clinic Label One Edited'
      AND is_test
  ),
  0,
  'staff B cannot mark a clinic A patient as test'
);

SELECT pg_temp.logout();

SELECT is(
  (
    SELECT clinic_label FROM public.patients
    WHERE clinic_label = 'Clinic Label One Edited'
  ),
  'Clinic Label One Edited',
  'clinic A clinic_label is unchanged after staff B update attempt'
);

SELECT is(
  (
    SELECT is_test FROM public.patients
    WHERE clinic_label = 'Clinic Label One Edited'
  ),
  false,
  'clinic A test flag is unchanged after staff B update attempt'
);

-- ---------------------------------------------------------------------------
-- Test flag on create, and a full patient purge
-- ---------------------------------------------------------------------------

SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');

SELECT lives_ok(
  $$SELECT public.create_unactivated_patient('Test Account', DATE '2026-09-02', true)$$,
  'staff can create a test patient'
);

SELECT is(
  (
    SELECT is_test FROM public.patients
    WHERE clinic_label = 'Test Account'
  ),
  true,
  'create_unactivated_patient stores the test flag'
);

SELECT pg_temp.logout();

SELECT pg_temp.create_auth_user(
  'e0000000-0000-4000-8000-0000000000e2',
  'purge.patient@local.test'
);

INSERT INTO public.patients (id, clinic_id, clinic_label, auth_user_id, is_test)
VALUES (
  'e0000000-0000-4000-8000-0000000000e1',
  '10000000-0000-4000-8000-000000000001',
  'Purge Me',
  'e0000000-0000-4000-8000-0000000000e2',
  true
);

INSERT INTO public.treatments (id, patient_id, clinic_id, treatment_context, status)
VALUES (
  'e0000000-0000-4000-8000-0000000000e3',
  'e0000000-0000-4000-8000-0000000000e1',
  '10000000-0000-4000-8000-000000000001',
  'sclerotherapy',
  'active'
);

INSERT INTO public.treatment_periods (id, treatment_id, clinic_id, started_on)
VALUES (
  'e0000000-0000-4000-8000-0000000000e4',
  'e0000000-0000-4000-8000-0000000000e3',
  '10000000-0000-4000-8000-000000000001',
  DATE '2026-09-01'
);

INSERT INTO public.treatment_milestones (id, treatment_id, clinic_id, title, occurred_on)
VALUES (
  'e0000000-0000-4000-8000-0000000000e5',
  'e0000000-0000-4000-8000-0000000000e3',
  '10000000-0000-4000-8000-000000000001',
  'Visit',
  DATE '2026-09-02'
);

INSERT INTO public.action_assignments (
  id, treatment_id, clinic_id, catalog_item_id, title, start_date, end_date
) VALUES (
  'e0000000-0000-4000-8000-0000000000e6',
  'e0000000-0000-4000-8000-0000000000e3',
  '10000000-0000-4000-8000-000000000001',
  'e0000000-0000-4000-8000-0000000000c1',
  'placeholder',
  DATE '2026-09-01',
  DATE '2026-09-14'
);

INSERT INTO public.action_completions (
  id, assignment_id, treatment_id, patient_id, clinic_id, completed_on
) VALUES (
  'e0000000-0000-4000-8000-0000000000e7',
  'e0000000-0000-4000-8000-0000000000e6',
  'e0000000-0000-4000-8000-0000000000e3',
  'e0000000-0000-4000-8000-0000000000e1',
  '10000000-0000-4000-8000-000000000001',
  DATE '2026-09-02'
);

UPDATE public.action_assignments
SET status = 'disabled'
WHERE id = 'e0000000-0000-4000-8000-0000000000e6';

INSERT INTO public.diary_entries (
  treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
) VALUES (
  'e0000000-0000-4000-8000-0000000000e3',
  'e0000000-0000-4000-8000-0000000000e1',
  '10000000-0000-4000-8000-000000000001',
  DATE '2026-09-02',
  1,
  1,
  'unchanged'
);

INSERT INTO public.patient_photos (
  id, treatment_id, patient_id, clinic_id, submitted_on, slot,
  storage_bucket, storage_path, content_type
) VALUES (
  'e0000000-0000-4000-8000-0000000000e9',
  'e0000000-0000-4000-8000-0000000000e3',
  'e0000000-0000-4000-8000-0000000000e1',
  '10000000-0000-4000-8000-000000000001',
  DATE '2026-09-02',
  1,
  'patient-photos',
  '10000000-0000-4000-8000-000000000001/e0000000-0000-4000-8000-0000000000e1/e0000000-0000-4000-8000-0000000000e3/2026-09-02/e0000000-0000-4000-8000-0000000000e9.jpg',
  'image/jpeg'
);

INSERT INTO public.doctor_milestone_photos (
  id, treatment_id, milestone_id, clinic_id, storage_bucket, storage_path, content_type
) VALUES (
  'e0000000-0000-4000-8000-0000000000ea',
  'e0000000-0000-4000-8000-0000000000e3',
  'e0000000-0000-4000-8000-0000000000e5',
  '10000000-0000-4000-8000-000000000001',
  'doctor-milestone-photos',
  '10000000-0000-4000-8000-000000000001/e0000000-0000-4000-8000-0000000000e3/e0000000-0000-4000-8000-0000000000e5/e0000000-0000-4000-8000-0000000000ea.jpg',
  'image/jpeg'
);

INSERT INTO storage.objects (bucket_id, name) VALUES
  (
    'patient-photos',
    '10000000-0000-4000-8000-000000000001/e0000000-0000-4000-8000-0000000000e1/e0000000-0000-4000-8000-0000000000e3/2026-09-02/e0000000-0000-4000-8000-0000000000e9.jpg'
  ),
  (
    'patient-photos',
    '10000000-0000-4000-8000-000000000001/e0000000-0000-4000-8000-0000000000e1/e0000000-0000-4000-8000-0000000000e3/2026-09-02/orphan.jpg'
  ),
  (
    'doctor-milestone-photos',
    '10000000-0000-4000-8000-000000000001/e0000000-0000-4000-8000-0000000000e3/e0000000-0000-4000-8000-0000000000e5/e0000000-0000-4000-8000-0000000000ea.jpg'
  ),
  (
    'patient-photos',
    '10000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000020/keep.jpg'
  );

INSERT INTO public.appointments (
  id, treatment_id, clinic_id, status, wall_clock, time_zone, at_utc
) VALUES (
  'e0000000-0000-4000-8000-0000000000eb',
  'e0000000-0000-4000-8000-0000000000e3',
  '10000000-0000-4000-8000-000000000001',
  'current',
  TIMESTAMP '2026-09-10 10:00',
  'Europe/Minsk',
  TIMESTAMPTZ '2026-09-10 07:00+00'
);

INSERT INTO public.patient_invites (
  id, clinic_id, patient_id, treatment_id, token_hash, expires_at, created_by_staff_id, pilot_cohort
) VALUES (
  'e0000000-0000-4000-8000-0000000000ec',
  '10000000-0000-4000-8000-000000000001',
  'e0000000-0000-4000-8000-0000000000e1',
  'e0000000-0000-4000-8000-0000000000e3',
  decode(repeat('cd', 32), 'hex'),
  now() + interval '7 days',
  '10000000-0000-4000-8000-000000000011',
  'internal_dry_run'
);

INSERT INTO public.product_events (name, pilot_cohort, patient_id, treatment_id)
VALUES (
  'app_opened',
  'internal_dry_run',
  'e0000000-0000-4000-8000-0000000000e1',
  'e0000000-0000-4000-8000-0000000000e3'
);

INSERT INTO public.push_subscriptions (patient_id, endpoint, p256dh, auth)
VALUES (
  'e0000000-0000-4000-8000-0000000000e1',
  'https://push.example.test/purge-e1',
  'p256dh-key-value',
  'auth-key-value'
);

INSERT INTO public.notification_events (patient_id, kind, route, dedupe_key)
VALUES (
  'e0000000-0000-4000-8000-0000000000e1',
  'manual_test',
  '/',
  'purge-patient-e1-manual'
);

INSERT INTO public.web_session_handoffs (token_hash, auth_user_id, expires_at)
VALUES (
  decode(repeat('ab', 32), 'hex'),
  'e0000000-0000-4000-8000-0000000000e2',
  now() + interval '10 minutes'
);

UPDATE public.treatments
SET status = 'completed', completed_at = now()
WHERE id = 'e0000000-0000-4000-8000-0000000000e3';

INSERT INTO public.feedback_surveys (
  treatment_id, patient_id, clinic_id, usefulness_score, clarity_score
) VALUES (
  'e0000000-0000-4000-8000-0000000000e3',
  'e0000000-0000-4000-8000-0000000000e1',
  '10000000-0000-4000-8000-000000000001',
  4,
  5
);

SELECT pg_temp.login('e0000000-0000-4000-8000-0000000000a1');

UPDATE public.patients
SET is_test = true
WHERE id = 'e0000000-0000-4000-8000-0000000000a0';

SELECT pg_temp.logout();

SELECT is(
  (
    SELECT is_test FROM public.patients
    WHERE id = 'e0000000-0000-4000-8000-0000000000a0'
  ),
  false,
  'patient cannot mark themselves as test'
);

SELECT pg_temp.login('e0000000-0000-4000-8000-0000000000a1');
SELECT throws_ok(
  $$SELECT public.delete_patient('e0000000-0000-4000-8000-0000000000e1')$$,
  '42501',
  NULL,
  'patient cannot delete_patient'
);
SELECT pg_temp.logout();

SELECT pg_temp.login('e0000000-0000-4000-8000-000000000012');
SELECT throws_ok(
  $$SELECT public.delete_patient('e0000000-0000-4000-8000-0000000000e1')$$,
  'P0002',
  NULL,
  'staff B cannot delete a clinic A patient'
);
SELECT pg_temp.logout();

SELECT is(
  (SELECT count(*)::int FROM public.patients WHERE id = 'e0000000-0000-4000-8000-0000000000e1'),
  1,
  'foreign delete leaves the patient in place'
);

SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');
SELECT lives_ok(
  $$SELECT public.delete_patient('e0000000-0000-4000-8000-0000000000e1')$$,
  'staff can delete a patient in their clinic'
);
SELECT pg_temp.logout();

SELECT is(
  (SELECT count(*)::int FROM public.patients WHERE id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged patient row is gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.treatments WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged treatments are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.treatment_periods WHERE id = 'e0000000-0000-4000-8000-0000000000e4'),
  0,
  'purged periods are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.treatment_milestones WHERE id = 'e0000000-0000-4000-8000-0000000000e5'),
  0,
  'purged milestones are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.action_assignments WHERE id = 'e0000000-0000-4000-8000-0000000000e6'),
  0,
  'purged assignments are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.action_completions WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged completions are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.diary_entries WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged diary entries are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.patient_photos WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged patient photo rows are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.doctor_milestone_photos WHERE id = 'e0000000-0000-4000-8000-0000000000ea'),
  0,
  'purged doctor photo rows are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.appointments WHERE id = 'e0000000-0000-4000-8000-0000000000eb'),
  0,
  'purged appointments are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.patient_invites WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged invites are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.feedback_surveys WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged feedback is gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.product_events WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged product events are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.push_subscriptions WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged push subscriptions are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.notification_events WHERE patient_id = 'e0000000-0000-4000-8000-0000000000e1'),
  0,
  'purged notification events are gone'
);
SELECT is(
  (SELECT count(*)::int FROM public.web_session_handoffs WHERE auth_user_id = 'e0000000-0000-4000-8000-0000000000e2'),
  0,
  'purged web session handoffs are gone'
);
SELECT is(
  (SELECT count(*)::int FROM auth.users WHERE id = 'e0000000-0000-4000-8000-0000000000e2'),
  0,
  'purged auth user is gone'
);
SELECT is(
  (SELECT count(*)::int FROM auth.identities WHERE user_id = 'e0000000-0000-4000-8000-0000000000e2'),
  0,
  'purged auth identity is gone'
);
SELECT is(
  (
    SELECT count(*)::int FROM storage.objects
    WHERE name LIKE '10000000-0000-4000-8000-000000000001/e0000000-0000-4000-8000-0000000000e1/%'
       OR name LIKE '10000000-0000-4000-8000-000000000001/e0000000-0000-4000-8000-0000000000e3/%'
  ),
  0,
  'purged photo objects are gone'
);
SELECT is(
  (
    SELECT count(*)::int FROM storage.objects
    WHERE name = '10000000-0000-4000-8000-000000000001/10000000-0000-4000-8000-000000000020/keep.jpg'
  ),
  1,
  'another patient photo object is kept'
);
SELECT is(
  (SELECT count(*)::int FROM public.patients WHERE clinic_label = 'Clinic Label One Edited'),
  1,
  'another patient in the clinic is kept'
);
SELECT is(
  (SELECT count(*)::int FROM public.patients WHERE clinic_label = 'Test Account'),
  1,
  'the other test patient is kept'
);

SELECT * FROM finish();
ROLLBACK;
