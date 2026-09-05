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

-- ---------------------------------------------------------------------------
-- Helper grants
-- ---------------------------------------------------------------------------

SELECT ok(
  NOT has_function_privilege('anon', 'public.current_patient_id()', 'execute'),
  'anon cannot execute current_patient_id'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.current_staff_clinic_id()', 'execute'),
  'anon cannot execute current_staff_clinic_id'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.is_staff()', 'execute'),
  'anon cannot execute is_staff'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.patient_belongs_to_clinic(uuid, uuid)', 'execute'),
  'anon cannot execute patient_belongs_to_clinic'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.current_patient_id()', 'execute'),
  'authenticated can execute current_patient_id'
);

SELECT ok(
  NOT has_function_privilege('authenticated', 'public.apply_treatment_parent()', 'execute'),
  'authenticated cannot execute apply_treatment_parent'
);

SELECT ok(
  NOT has_table_privilege('anon', 'public.patients', 'select'),
  'anon cannot select patients'
);

SELECT ok(
  NOT has_table_privilege('anon', 'public.treatments', 'select'),
  'anon cannot select treatments'
);

-- ---------------------------------------------------------------------------
-- Fixtures (postgres / bypasses RLS)
-- ---------------------------------------------------------------------------

SELECT pg_temp.create_auth_user(
  'c0000000-0000-4000-8000-0000000000a1',
  'patient.a.synthetic@local.test'
);
SELECT pg_temp.create_auth_user(
  'c0000000-0000-4000-8000-0000000000a2',
  'patient.a2.synthetic@local.test'
);
SELECT pg_temp.create_auth_user(
  'c0000000-0000-4000-8000-0000000000b1',
  'patient.b.synthetic@local.test'
);
SELECT pg_temp.create_auth_user(
  'c0000000-0000-4000-8000-000000000012',
  'staff.b.synthetic@local.test'
);

INSERT INTO public.clinics (id, name, time_zone)
VALUES ('c0000000-0000-4000-8000-000000000002', 'Synthetic Clinic B', 'Europe/Minsk');

INSERT INTO public.clinic_staff (id, clinic_id, auth_user_id, display_name)
VALUES (
  'c0000000-0000-4000-8000-000000000013',
  'c0000000-0000-4000-8000-000000000002',
  'c0000000-0000-4000-8000-000000000012',
  'Synthetic Staff B'
);

INSERT INTO public.patients (id, clinic_id, clinic_label, auth_user_id, pilot_cohort)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000a0',
    '10000000-0000-4000-8000-000000000001',
    'Synthetic Patient A',
    'c0000000-0000-4000-8000-0000000000a1',
    'internal_dry_run'
  ),
  (
    'c0000000-0000-4000-8000-0000000000a3',
    '10000000-0000-4000-8000-000000000001',
    'Synthetic Patient A2',
    'c0000000-0000-4000-8000-0000000000a2',
    'internal_dry_run'
  ),
  (
    'c0000000-0000-4000-8000-0000000000b0',
    'c0000000-0000-4000-8000-000000000002',
    'Synthetic Patient B',
    'c0000000-0000-4000-8000-0000000000b1',
    'internal_dry_run'
  );

INSERT INTO public.treatments (id, patient_id, clinic_id, status, pilot_cohort)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000a4',
    'c0000000-0000-4000-8000-0000000000a0',
    '10000000-0000-4000-8000-000000000001',
    'active',
    'internal_dry_run'
  ),
  (
    'c0000000-0000-4000-8000-0000000000a5',
    'c0000000-0000-4000-8000-0000000000a3',
    '10000000-0000-4000-8000-000000000001',
    'active',
    'internal_dry_run'
  ),
  (
    'c0000000-0000-4000-8000-0000000000b4',
    'c0000000-0000-4000-8000-0000000000b0',
    'c0000000-0000-4000-8000-000000000002',
    'active',
    'internal_dry_run'
  );

INSERT INTO public.treatment_periods (id, treatment_id, clinic_id, started_on)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000a6',
    'c0000000-0000-4000-8000-0000000000a4',
    '10000000-0000-4000-8000-000000000001',
    DATE '2026-08-19'
  ),
  (
    'c0000000-0000-4000-8000-0000000000b6',
    'c0000000-0000-4000-8000-0000000000b4',
    'c0000000-0000-4000-8000-000000000002',
    DATE '2026-08-19'
  );

INSERT INTO public.action_catalog_items (id, clinic_id, title, instruction, status)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000c1',
    '10000000-0000-4000-8000-000000000001',
    'Synthetic catalog item 1',
    NULL,
    'approved'
  ),
  (
    'c0000000-0000-4000-8000-0000000000c2',
    'c0000000-0000-4000-8000-000000000002',
    'Synthetic catalog item B',
    NULL,
    'approved'
  );

INSERT INTO public.action_assignments (
  id, treatment_id, clinic_id, catalog_item_id, title, instruction,
  start_date, end_date, status
) VALUES
  (
    'c0000000-0000-4000-8000-0000000000d1',
    'c0000000-0000-4000-8000-0000000000a4',
    '10000000-0000-4000-8000-000000000001',
    'c0000000-0000-4000-8000-0000000000c1',
    'Synthetic catalog item 1',
    NULL,
    DATE '2026-08-19',
    DATE '2026-09-30',
    'active'
  ),
  (
    'c0000000-0000-4000-8000-0000000000d2',
    'c0000000-0000-4000-8000-0000000000a4',
    '10000000-0000-4000-8000-000000000001',
    'c0000000-0000-4000-8000-0000000000c1',
    'Synthetic disabled assignment',
    NULL,
    DATE '2026-08-19',
    DATE '2026-09-30',
    'disabled'
  );

INSERT INTO public.treatment_milestones (id, treatment_id, clinic_id, title, occurred_on)
VALUES (
  'c0000000-0000-4000-8000-0000000000e1',
  'c0000000-0000-4000-8000-0000000000a4',
  '10000000-0000-4000-8000-000000000001',
  'Synthetic visit',
  DATE '2026-08-20'
);

-- ---------------------------------------------------------------------------
-- Helper results are caller-scoped
-- ---------------------------------------------------------------------------

SELECT pg_temp.login('c0000000-0000-4000-8000-000000000012');
SELECT is(
  public.current_staff_clinic_id(),
  'c0000000-0000-4000-8000-000000000002'::uuid,
  'staff B helper returns clinic B'
);
SELECT is(
  public.treatment_in_staff_clinic('c0000000-0000-4000-8000-0000000000a4'),
  false,
  'staff B helper does not claim clinic A treatment'
);
SELECT pg_temp.logout();

-- ---------------------------------------------------------------------------
-- Patient isolation
-- ---------------------------------------------------------------------------

SELECT pg_temp.login('c0000000-0000-4000-8000-0000000000a1');

SELECT is(
  (SELECT count(*)::int FROM public.patients),
  1,
  'patient A sees only own patient row'
);

SELECT is(
  (SELECT count(*)::int FROM public.treatments),
  1,
  'patient A sees only own treatment'
);

SELECT is(
  (SELECT count(*)::int FROM public.treatments WHERE id = 'c0000000-0000-4000-8000-0000000000a5'),
  0,
  'patient A cannot read same-clinic other patient treatment'
);

SELECT is(
  (SELECT count(*)::int FROM public.treatments WHERE id = 'c0000000-0000-4000-8000-0000000000b4'),
  0,
  'patient A cannot read clinic B treatment'
);

SELECT lives_ok(
  $$UPDATE public.treatments
    SET status = 'completed'
    WHERE id = 'c0000000-0000-4000-8000-0000000000a4'$$,
  'patient treatment status update does not throw (0 rows / RLS)'
);

SELECT is(
  (SELECT status::text FROM public.treatments WHERE id = 'c0000000-0000-4000-8000-0000000000a4'),
  'active',
  'patient cannot change treatment status'
);

SELECT is(
  (SELECT count(*)::int FROM public.patient_invites),
  0,
  'patient cannot see invite rows'
);

SELECT is(
  (SELECT count(*)::int FROM public.action_catalog_items),
  0,
  'patient cannot read catalog'
);

-- Completions
SELECT lives_ok(
  $$INSERT INTO public.action_completions (
      assignment_id, treatment_id, patient_id, clinic_id, completed_on
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000d1',
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000a0',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-20'
    )$$,
  'patient can complete an active in-range assignment'
);

SELECT throws_ok(
  $$INSERT INTO public.action_completions (
      assignment_id, treatment_id, patient_id, clinic_id, completed_on
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000d2',
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000a0',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-20'
    )$$,
  '23514',
  'integrity: assignment is not completable',
  'patient cannot complete a disabled assignment'
);

SELECT throws_ok(
  $$INSERT INTO public.action_completions (
      assignment_id, treatment_id, patient_id, clinic_id, completed_on
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000d1',
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000a0',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-01'
    )$$,
  '23514',
  'integrity: assignment is not completable on date',
  'patient cannot complete out of range'
);

SELECT lives_ok(
  $$INSERT INTO public.diary_entries (
      treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000a0',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-21',
      3, 2, 'unchanged'
    )$$,
  'patient can insert diary for active treatment'
);

SELECT throws_ok(
  $$INSERT INTO public.diary_entries (
      treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000a0',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-21',
      1, 1, 'better'
    )$$,
  '23505',
  NULL,
  'one diary entry per treatment civil date'
);

SELECT throws_ok(
  $$UPDATE public.diary_entries SET pain = 0$$,
  '42501',
  NULL,
  'diary entries cannot be updated'
);

SELECT lives_ok(
  $$INSERT INTO public.patient_photos (
      treatment_id, patient_id, clinic_id, submitted_on, slot,
      storage_bucket, storage_path, content_type
    ) VALUES
      (
        'c0000000-0000-4000-8000-0000000000a4',
        'c0000000-0000-4000-8000-0000000000a0',
        '10000000-0000-4000-8000-000000000001',
        DATE '2026-08-21', 1, 'patient-photos',
        '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a0/c0000000-0000-4000-8000-0000000000a4/2026-08-21/p1.jpg',
        'image/jpeg'
      ),
      (
        'c0000000-0000-4000-8000-0000000000a4',
        'c0000000-0000-4000-8000-0000000000a0',
        '10000000-0000-4000-8000-000000000001',
        DATE '2026-08-21', 2, 'patient-photos',
        '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a0/c0000000-0000-4000-8000-0000000000a4/2026-08-21/p2.jpg',
        'image/jpeg'
      ),
      (
        'c0000000-0000-4000-8000-0000000000a4',
        'c0000000-0000-4000-8000-0000000000a0',
        '10000000-0000-4000-8000-000000000001',
        DATE '2026-08-21', 3, 'patient-photos',
        '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a0/c0000000-0000-4000-8000-0000000000a4/2026-08-21/p3.jpg',
        'image/jpeg'
      )$$,
  'patient can insert 3 photos for a civil date'
);

SELECT throws_ok(
  $$INSERT INTO public.patient_photos (
      treatment_id, patient_id, clinic_id, submitted_on, slot,
      storage_bucket, storage_path, content_type
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000a0',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-21', 4, 'patient-photos',
      '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a0/c0000000-0000-4000-8000-0000000000a4/2026-08-21/p4.jpg',
      'image/jpeg'
    )$$,
  '23514',
  NULL,
  'fourth patient photo slot is rejected'
);

SELECT lives_ok(
  $$INSERT INTO public.product_events (
      name, occurred_at, pilot_cohort, clinic_id, patient_id, treatment_id
    ) VALUES (
      'app_opened', now(), 'internal_dry_run',
      'c0000000-0000-4000-8000-000000000002',
      'c0000000-0000-4000-8000-0000000000a0',
      'c0000000-0000-4000-8000-0000000000a4'
    )$$,
  'patient insert with forged clinic_id is accepted after overwrite'
);

SELECT is(
  (SELECT count(*)::int FROM public.product_events),
  0,
  'patient cannot SELECT product_events'
);

SELECT throws_ok(
  $$INSERT INTO public.product_events (
      name, occurred_at, pilot_cohort, patient_id, treatment_id,
      usefulness_score, clarity_score
    ) VALUES (
      'task_completed', now(), 'internal_dry_run',
      'c0000000-0000-4000-8000-0000000000a0',
      'c0000000-0000-4000-8000-0000000000a4',
      5, 5
    )$$,
  '23514',
  NULL,
  'non-feedback events cannot carry scores'
);

SELECT throws_ok(
  $$INSERT INTO public.product_events (
      name, occurred_at, pilot_cohort, patient_id, treatment_id, usefulness_score
    ) VALUES (
      'feedback_submitted', now(), 'internal_dry_run',
      'c0000000-0000-4000-8000-0000000000a0',
      'c0000000-0000-4000-8000-0000000000a4',
      5
    )$$,
  '23514',
  NULL,
  'feedback_submitted requires both scores'
);

SELECT pg_temp.logout();

SELECT is(
  (
    SELECT clinic_id
    FROM public.product_events
    WHERE patient_id = 'c0000000-0000-4000-8000-0000000000a0'
      AND name = 'app_opened'
    ORDER BY occurred_at DESC
    LIMIT 1
  ),
  '10000000-0000-4000-8000-000000000001'::uuid,
  'product_events clinic_id is derived from treatment not the client'
);

-- Patient A cannot insert events for patient B
SELECT pg_temp.login('c0000000-0000-4000-8000-0000000000a1');
SELECT throws_ok(
  $$INSERT INTO public.product_events (
      name, occurred_at, pilot_cohort, patient_id, treatment_id
    ) VALUES (
      'app_opened', now(), 'internal_dry_run',
      'c0000000-0000-4000-8000-0000000000b0',
      'c0000000-0000-4000-8000-0000000000b4'
    )$$,
  '42501',
  NULL,
  'patient A cannot insert product_events for clinic B'
);
SELECT pg_temp.logout();

-- ---------------------------------------------------------------------------
-- Staff isolation
-- ---------------------------------------------------------------------------

SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');

SELECT is(
  (SELECT count(*)::int FROM public.patients WHERE clinic_id = 'c0000000-0000-4000-8000-000000000002'),
  0,
  'staff A cannot read clinic B patients'
);

SELECT isnt(
  (SELECT count(*)::int FROM public.patients),
  0,
  'staff A can read own clinic patients'
);

SELECT lives_ok(
  $$UPDATE public.action_assignments
      SET status = 'disabled'
    WHERE id = 'c0000000-0000-4000-8000-0000000000d1'$$,
  'staff can disable an assignment'
);

SELECT is(
  (SELECT count(*)::int FROM public.action_completions WHERE assignment_id = 'c0000000-0000-4000-8000-0000000000d1'),
  1,
  'disabling an assignment does not delete completions'
);

SELECT lives_ok(
  $$INSERT INTO public.action_catalog_items (clinic_id, title, instruction, status)
    VALUES (
      '10000000-0000-4000-8000-000000000001',
      'Synthetic catalog item without instruction',
      NULL,
      'draft'
    )$$,
  'catalog instruction may be null'
);

SELECT lives_ok(
  $$INSERT INTO public.appointments (
      treatment_id, clinic_id, status, wall_clock, time_zone, at_utc
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      '10000000-0000-4000-8000-000000000001',
      'current',
      TIMESTAMP '2026-09-15 14:30:00',
      'UTC',
      TIMESTAMPTZ '2026-09-15 14:30:00+00'
    )$$,
  'staff can insert a current appointment'
);

SELECT is(
  (
    SELECT time_zone FROM public.appointments
    WHERE treatment_id = 'c0000000-0000-4000-8000-0000000000a4'
      AND status = 'current'
  ),
  'Europe/Minsk',
  'appointment time_zone is copied from clinic not the client'
);

SELECT lives_ok(
  $$UPDATE public.appointments
      SET status = 'superseded', superseded_at = now()
    WHERE treatment_id = 'c0000000-0000-4000-8000-0000000000a4'
      AND status = 'current'$$,
  'staff can supersede the current appointment'
);

SELECT lives_ok(
  $$INSERT INTO public.appointments (
      treatment_id, clinic_id, status, wall_clock, time_zone, at_utc
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      '10000000-0000-4000-8000-000000000001',
      'current',
      TIMESTAMP '2026-09-22 10:00:00',
      'Europe/Minsk',
      TIMESTAMPTZ '2026-09-22 10:00:00+03'
    )$$,
  'staff can insert a new current appointment after supersede'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.appointments
    WHERE treatment_id = 'c0000000-0000-4000-8000-0000000000a4'
  ),
  2,
  'appointment history keeps superseded rows'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.appointments
    WHERE treatment_id = 'c0000000-0000-4000-8000-0000000000a4'
      AND status = 'current'
  ),
  1,
  'only one current appointment per treatment'
);

SELECT lives_ok(
  $$INSERT INTO public.doctor_milestone_photos (
      treatment_id, milestone_id, clinic_id, storage_bucket, storage_path, content_type
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000e1',
      '10000000-0000-4000-8000-000000000001',
      'doctor-milestone-photos',
      '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a4/c0000000-0000-4000-8000-0000000000e1/d1.jpg',
      'image/jpeg'
    )$$,
  'staff can insert a doctor milestone photo'
);

SELECT is(
  (SELECT count(*)::int FROM public.product_events WHERE clinic_id = 'c0000000-0000-4000-8000-000000000002'),
  0,
  'staff A cannot select clinic B product_events'
);

SELECT throws_ok(
  $$INSERT INTO public.patient_invites (
      clinic_id, patient_id, treatment_id, token_hash, expires_at,
      created_by_staff_id, pilot_cohort
    ) VALUES (
      '10000000-0000-4000-8000-000000000001',
      'c0000000-0000-4000-8000-0000000000a0',
      'c0000000-0000-4000-8000-0000000000a4',
      digest('synthetic-invite-token', 'sha256'),
      now() + interval '7 days',
      '10000000-0000-4000-8000-000000000011',
      'internal_dry_run'
    )$$,
  '42501',
  NULL,
  'staff cannot insert patient_invites directly'
);

SELECT pg_temp.logout();

-- Staff B cannot insert events for clinic A patient
SELECT pg_temp.login('c0000000-0000-4000-8000-000000000012');
SELECT throws_ok(
  $$INSERT INTO public.product_events (
      name, occurred_at, pilot_cohort, patient_id, treatment_id
    ) VALUES (
      'patient_invited', now(), 'internal_dry_run',
      'c0000000-0000-4000-8000-0000000000a0',
      'c0000000-0000-4000-8000-0000000000a4'
    )$$,
  '42501',
  NULL,
  'staff B cannot insert product_events for clinic A'
);
SELECT is(
  (SELECT count(*)::int FROM public.treatments WHERE clinic_id = '10000000-0000-4000-8000-000000000001'),
  0,
  'staff B cannot read clinic A treatments'
);
SELECT pg_temp.logout();

-- Patient cannot uncomplete after assignment is disabled
SELECT pg_temp.login('c0000000-0000-4000-8000-0000000000a1');
SELECT throws_ok(
  $$DELETE FROM public.action_completions
    WHERE assignment_id = 'c0000000-0000-4000-8000-0000000000d1'$$,
  '23514',
  'integrity: assignment is not completable',
  'patient cannot uncomplete after assignment is disabled'
);
SELECT is(
  (SELECT count(*)::int FROM public.doctor_milestone_photos),
  1,
  'patient can read own doctor milestone photos'
);
SELECT pg_temp.logout();

-- ---------------------------------------------------------------------------
-- Integrity: diary/photos require active matching treatment
-- ---------------------------------------------------------------------------

UPDATE public.treatments
SET status = 'completed', completed_at = now()
WHERE id = 'c0000000-0000-4000-8000-0000000000a5';

SELECT pg_temp.login('c0000000-0000-4000-8000-0000000000a2');
SELECT throws_ok(
  $$INSERT INTO public.diary_entries (
      treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a5',
      'c0000000-0000-4000-8000-0000000000a3',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-22',
      1, 1, 'better'
    )$$,
  '23514',
  'integrity: treatment is not active',
  'diary insert rejected when treatment is not active'
);

SELECT throws_ok(
  $$INSERT INTO public.patient_photos (
      treatment_id, patient_id, clinic_id, submitted_on, slot,
      storage_bucket, storage_path, content_type
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a5',
      'c0000000-0000-4000-8000-0000000000a3',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-22', 1, 'patient-photos',
      '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a3/c0000000-0000-4000-8000-0000000000a5/2026-08-22/p1.jpg',
      'image/jpeg'
    )$$,
  '23514',
  'integrity: treatment is not active',
  'patient photo insert rejected when treatment is not active'
);

SELECT lives_ok(
  $$INSERT INTO public.feedback_surveys (
      treatment_id, patient_id, clinic_id, usefulness_score, clarity_score
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a5',
      'c0000000-0000-4000-8000-0000000000a3',
      '10000000-0000-4000-8000-000000000001',
      4, 5
    )$$,
  'feedback survey requires completed treatment and both scores'
);

SELECT lives_ok(
  $$INSERT INTO public.product_events (
      name, occurred_at, pilot_cohort, patient_id, treatment_id,
      usefulness_score, clarity_score
    ) VALUES (
      'feedback_submitted', now(), 'internal_dry_run',
      'c0000000-0000-4000-8000-0000000000a3',
      'c0000000-0000-4000-8000-0000000000a5',
      4, 5
    )$$,
  'feedback_submitted event with both scores succeeds'
);

SELECT throws_ok(
  $$INSERT INTO public.diary_entries (
      treatment_id, patient_id, clinic_id, submitted_on, pain, swelling, wellbeing
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000a3',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-23',
      1, 1, 'worse'
    )$$,
  '23514',
  'integrity: patient_id does not match treatment',
  'diary insert rejected when patient_id does not match treatment'
);

SELECT pg_temp.logout();

-- Wrong patient_id as postgres still rejected by trigger
SELECT throws_ok(
  $$INSERT INTO public.patient_photos (
      treatment_id, patient_id, clinic_id, submitted_on, slot,
      storage_bucket, storage_path, content_type
    ) VALUES (
      'c0000000-0000-4000-8000-0000000000a4',
      'c0000000-0000-4000-8000-0000000000b0',
      '10000000-0000-4000-8000-000000000001',
      DATE '2026-08-24', 1, 'patient-photos',
      'x/y/z/2026-08-24/p.jpg',
      'image/jpeg'
    )$$,
  '23514',
  'integrity: patient_id does not match treatment',
  'patient photo parent-id mismatch is rejected even as table owner'
);

-- ---------------------------------------------------------------------------
-- Storage object RLS
-- ---------------------------------------------------------------------------

INSERT INTO storage.objects (bucket_id, name)
VALUES (
  'doctor-milestone-photos',
  '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a4/c0000000-0000-4000-8000-0000000000e1/d1.jpg'
);

INSERT INTO storage.objects (bucket_id, name)
VALUES (
  'patient-photos',
  '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a0/c0000000-0000-4000-8000-0000000000a4/2026-08-21/p1.jpg'
);

SELECT pg_temp.login('c0000000-0000-4000-8000-0000000000a1');
SELECT is(
  (
    SELECT count(*)::int FROM storage.objects
    WHERE bucket_id = 'doctor-milestone-photos'
  ),
  1,
  'patient can read own doctor-milestone-photos object'
);
SELECT is(
  (
    SELECT count(*)::int FROM storage.objects
    WHERE bucket_id = 'patient-photos'
  ),
  1,
  'patient can read own patient-photos object'
);
SELECT pg_temp.logout();

SELECT pg_temp.login('c0000000-0000-4000-8000-0000000000a2');
SELECT is(
  (
    SELECT count(*)::int FROM storage.objects
    WHERE bucket_id = 'patient-photos'
  ),
  0,
  'other patient cannot read patient-photos prefix'
);
SELECT pg_temp.logout();

SELECT pg_temp.login('c0000000-0000-4000-8000-0000000000a1');
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name)
    VALUES (
      'patient-photos',
      '10000000-0000-4000-8000-000000000001/c0000000-0000-4000-8000-0000000000a0/c0000000-0000-4000-8000-0000000000a4/2026-08-21/new.jpg'
    )$$,
  'patient can insert into own patient-photos path'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name)
    VALUES (
      'patient-photos',
      'c0000000-0000-4000-8000-000000000002/c0000000-0000-4000-8000-0000000000b0/c0000000-0000-4000-8000-0000000000b4/2026-08-21/x.jpg'
    )$$,
  '42501',
  NULL,
  'patient cannot insert into another clinic patient-photos path'
);
SELECT pg_temp.logout();

SELECT * FROM finish();
ROLLBACK;
