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
  NOT has_function_privilege('anon', 'public.create_unactivated_patient(text, date)', 'execute'),
  'anon cannot execute create_unactivated_patient'
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
  has_function_privilege('authenticated', 'public.create_unactivated_patient(text, date)', 'execute'),
  'authenticated can execute create_unactivated_patient'
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
  ),
  1,
  'created patient has label and null bind columns'
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

SELECT pg_temp.logout();

SELECT is(
  (
    SELECT clinic_label FROM public.patients
    WHERE clinic_label = 'Clinic Label One Edited'
  ),
  'Clinic Label One Edited',
  'clinic A clinic_label is unchanged after staff B update attempt'
);

SELECT * FROM finish();
ROLLBACK;
