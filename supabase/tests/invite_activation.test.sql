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
    '00000000-0000-4000-8000-000000000000',
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

CREATE TABLE pg_temp.issued (
  label text PRIMARY KEY,
  token text NOT NULL,
  invite_id uuid NOT NULL
);
GRANT ALL ON TABLE pg_temp.issued TO authenticated;
GRANT SELECT ON TABLE pg_temp.issued TO service_role;

CREATE OR REPLACE FUNCTION pg_temp.token_hash_hex(p_token text)
RETURNS text
LANGUAGE sql
AS $$
  SELECT encode(extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex');
$$;

GRANT EXECUTE ON FUNCTION pg_temp.token_hash_hex(text) TO authenticated, service_role;

-- Unactivated patient for invite issue (seed patient is also unactivated).
INSERT INTO public.patients (id, clinic_id)
VALUES (
  'd0000000-0000-4000-8000-000000000020',
  '10000000-0000-4000-8000-000000000001'
);

INSERT INTO public.treatments (id, patient_id, clinic_id, status)
VALUES (
  'd0000000-0000-4000-8000-000000000021',
  'd0000000-0000-4000-8000-000000000020',
  '10000000-0000-4000-8000-000000000001',
  'active'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.patient_invites', 'insert'),
  'authenticated cannot insert patient_invites'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.patient_invites', 'update'),
  'authenticated cannot update patient_invites'
);

SELECT ok(
  NOT has_column_privilege('authenticated', 'public.patients', 'auth_user_id', 'update'),
  'authenticated cannot update patients.auth_user_id'
);

SELECT ok(
  NOT has_column_privilege('authenticated', 'public.patients', 'privacy_accepted_at', 'update'),
  'authenticated cannot update patients.privacy_accepted_at'
);

SELECT ok(
  NOT has_column_privilege('authenticated', 'public.patients', 'pilot_consent_accepted_at', 'update'),
  'authenticated cannot update patients.pilot_consent_accepted_at'
);

SELECT ok(
  NOT has_column_privilege('authenticated', 'public.patients', 'consent_document_version', 'update'),
  'authenticated cannot update patients.consent_document_version'
);

SELECT ok(
  NOT has_column_privilege('authenticated', 'public.patients', 'pilot_cohort', 'update'),
  'authenticated cannot update patients.pilot_cohort'
);

SELECT ok(
  NOT has_column_privilege('authenticated', 'public.treatments', 'pilot_cohort', 'update'),
  'authenticated cannot update treatments.pilot_cohort'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.activate_patient_from_invite(text, uuid, boolean, boolean, text)',
    'execute'
  ),
  'anon cannot execute activate_patient_from_invite'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.activate_patient_from_invite(text, uuid, boolean, boolean, text)',
    'execute'
  ),
  'authenticated cannot execute activate_patient_from_invite'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.lookup_patient_invite_by_hash(text)', 'execute'),
  'anon cannot execute lookup_patient_invite_by_hash'
);

SELECT ok(
  has_function_privilege(
    'service_role',
    'public.activate_patient_from_invite(text, uuid, boolean, boolean, text)',
    'execute'
  ),
  'service_role can execute activate_patient_from_invite'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.issue_patient_invite(uuid, public.pilot_cohort, integer)',
    'execute'
  ),
  'authenticated can execute issue_patient_invite'
);

-- Staff direct bind is denied
SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');

SELECT throws_ok(
  $$UPDATE public.patients
      SET auth_user_id = '10000000-0000-4000-8000-000000000010'
    WHERE id = 'd0000000-0000-4000-8000-000000000020'$$,
  '42501',
  NULL,
  'staff cannot UPDATE patients.auth_user_id'
);

SELECT throws_ok(
  $$UPDATE public.patients
      SET privacy_accepted_at = now(),
          pilot_consent_accepted_at = now(),
          consent_document_version = 'pilot-v0'
    WHERE id = 'd0000000-0000-4000-8000-000000000020'$$,
  '42501',
  NULL,
  'staff cannot UPDATE patient consent columns'
);

SELECT throws_ok(
  $$INSERT INTO public.patient_invites (
      clinic_id, patient_id, treatment_id, token_hash, expires_at,
      created_by_staff_id, pilot_cohort
    ) VALUES (
      '10000000-0000-4000-8000-000000000001',
      'd0000000-0000-4000-8000-000000000020',
      'd0000000-0000-4000-8000-000000000021',
      digest('synthetic-invite-token', 'sha256'),
      now() + interval '7 days',
      '10000000-0000-4000-8000-000000000011',
      'internal_dry_run'
    )$$,
  '42501',
  NULL,
  'staff cannot insert patient_invites directly'
);

SELECT lives_ok(
  $$INSERT INTO pg_temp.issued (label, token, invite_id)
    SELECT 'first', issued->>'token', (issued->>'invite_id')::uuid
    FROM (SELECT public.issue_patient_invite(
      'd0000000-0000-4000-8000-000000000021',
      'internal_dry_run',
      7
    ) AS issued) s$$,
  'staff can issue an invite via RPC'
);

SELECT is(
  (
    SELECT status FROM public.patient_invites
    WHERE id = (SELECT invite_id FROM pg_temp.issued WHERE label = 'first')
  ),
  'pending',
  'issued invite is pending'
);

SELECT lives_ok(
  $$INSERT INTO pg_temp.issued (label, token, invite_id)
    SELECT 'reissue', issued->>'token', (issued->>'invite_id')::uuid
    FROM (SELECT public.issue_patient_invite(
      'd0000000-0000-4000-8000-000000000021',
      'clinic_pilot',
      7
    ) AS issued) s$$,
  'staff can reissue an invite via RPC'
);

SELECT is(
  (
    SELECT encode(token_hash, 'hex')
    FROM public.patient_invites
    WHERE id = (SELECT invite_id FROM pg_temp.issued WHERE label = 'reissue')
  ),
  (
    SELECT pg_temp.token_hash_hex(token)
    FROM pg_temp.issued
    WHERE label = 'reissue'
  ),
  'reissue stores SHA-256 of the returned token, not the raw secret'
);

SELECT isnt(
  (SELECT token FROM pg_temp.issued WHERE label = 'reissue'),
  (
    SELECT encode(token_hash, 'escape')
    FROM public.patient_invites
    WHERE id = (SELECT invite_id FROM pg_temp.issued WHERE label = 'reissue')
  ),
  'raw token is not stored in token_hash'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.patient_invites
    WHERE treatment_id = 'd0000000-0000-4000-8000-000000000021'
      AND status = 'pending'
  ),
  1,
  'reissue leaves at most one pending invite per treatment'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.patient_invites
    WHERE treatment_id = 'd0000000-0000-4000-8000-000000000021'
      AND status = 'revoked'
  ),
  1,
  'reissue revokes the prior pending invite'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.product_events
    WHERE name = 'patient_invited'
      AND treatment_id = 'd0000000-0000-4000-8000-000000000021'
  ),
  2,
  'issue emits patient_invited without medical payload'
);

SELECT pg_temp.logout();

SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');
SELECT lives_ok(
  $$INSERT INTO pg_temp.issued (label, token, invite_id)
    SELECT 'seed', issued->>'token', (issued->>'invite_id')::uuid
    FROM (SELECT public.issue_patient_invite(
      '10000000-0000-4000-8000-000000000021',
      'closed_beta',
      7
    ) AS issued) s$$,
  'staff can issue an invite for the seed treatment'
);
SELECT pg_temp.logout();

SELECT pg_temp.create_auth_user(
  'd0000000-0000-4000-8000-0000000000aa',
  'u.activate@users.invalid'
);

SET ROLE service_role;

SELECT is(
  (
    SELECT outcome FROM public.activate_patient_from_invite(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.issued WHERE label = 'seed')),
      'd0000000-0000-4000-8000-0000000000aa',
      true,
      true,
      'pilot-v0'
    )
  ),
  'activated',
  'trusted activation path binds the patient'
);

RESET ROLE;

SELECT is(
  (
    SELECT auth_user_id FROM public.patients
    WHERE id = '10000000-0000-4000-8000-000000000020'
  ),
  'd0000000-0000-4000-8000-0000000000aa'::uuid,
  'activation assigns auth_user_id'
);

SELECT is(
  (
    SELECT pilot_cohort FROM public.patients
    WHERE id = '10000000-0000-4000-8000-000000000020'
  ),
  'closed_beta',
  'activation copies cohort onto the patient'
);

SELECT is(
  (
    SELECT pilot_cohort FROM public.treatments
    WHERE id = '10000000-0000-4000-8000-000000000021'
  ),
  'closed_beta',
  'activation copies cohort onto the treatment'
);

SELECT ok(
  (
    SELECT privacy_accepted_at IS NOT NULL
       AND pilot_consent_accepted_at IS NOT NULL
       AND consent_document_version = 'pilot-v0'
    FROM public.patients
    WHERE id = '10000000-0000-4000-8000-000000000020'
  ),
  'activation records consent timestamps and document version'
);

SELECT is(
  (
    SELECT status FROM public.patient_invites
    WHERE id = (SELECT invite_id FROM pg_temp.issued WHERE label = 'seed')
  ),
  'consumed',
  'activation consumes the invite'
);

SELECT is(
  (
    SELECT count(*)::int FROM public.product_events
    WHERE name = 'patient_activated'
      AND patient_id = '10000000-0000-4000-8000-000000000020'
  ),
  1,
  'activation emits patient_activated once'
);

-- Recovery eligible inside 15 minutes
SET ROLE service_role;
SELECT ok(
  (
    SELECT recovery_eligible FROM public.lookup_patient_invite_by_hash(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.issued WHERE label = 'seed'))
    )
  ),
  'consumed invite is recovery-eligible within 15 minutes'
);
RESET ROLE;

UPDATE public.patient_invites
SET consumed_at = now() - interval '3 days'
WHERE id = (SELECT invite_id FROM pg_temp.issued WHERE label = 'seed');

SET ROLE service_role;
SELECT is(
  (
    SELECT recovery_eligible FROM public.lookup_patient_invite_by_hash(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.issued WHERE label = 'seed'))
    )
  ),
  false,
  'copied QR days after activation cannot remint'
);

SELECT is(
  (
    SELECT outcome FROM public.activate_patient_from_invite(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.issued WHERE label = 'seed')),
      'd0000000-0000-4000-8000-0000000000aa',
      true,
      true,
      'pilot-v0'
    )
  ),
  'not_pending',
  'activate does not bind twice after consume'
);
RESET ROLE;

-- Patient and anon cannot bind
SELECT pg_temp.create_auth_user(
  'd0000000-0000-4000-8000-0000000000ab',
  'patient.bind.synthetic@local.test'
);

INSERT INTO public.patients (id, clinic_id, auth_user_id)
VALUES (
  'd0000000-0000-4000-8000-0000000000ac',
  '10000000-0000-4000-8000-000000000001',
  'd0000000-0000-4000-8000-0000000000ab'
);

SELECT pg_temp.login('d0000000-0000-4000-8000-0000000000ab');
SELECT throws_ok(
  $$UPDATE public.patients
      SET auth_user_id = 'd0000000-0000-4000-8000-0000000000ab'
    WHERE id = 'd0000000-0000-4000-8000-000000000020'$$,
  '42501',
  NULL,
  'patient cannot UPDATE patients.auth_user_id'
);
SELECT pg_temp.logout();

SET ROLE anon;
SELECT throws_ok(
  $$UPDATE public.patients
      SET auth_user_id = 'd0000000-0000-4000-8000-0000000000ab'
    WHERE id = 'd0000000-0000-4000-8000-000000000020'$$,
  '42501',
  NULL,
  'anon cannot UPDATE patients.auth_user_id'
);
RESET ROLE;

-- Expired pending invite is marked expired on lookup
INSERT INTO public.patients (id, clinic_id)
VALUES (
  'd0000000-0000-4000-8000-000000000030',
  '10000000-0000-4000-8000-000000000001'
);
INSERT INTO public.treatments (id, patient_id, clinic_id, status)
VALUES (
  'd0000000-0000-4000-8000-000000000031',
  'd0000000-0000-4000-8000-000000000030',
  '10000000-0000-4000-8000-000000000001',
  'active'
);

SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');
SELECT lives_ok(
  $$INSERT INTO pg_temp.issued (label, token, invite_id)
    SELECT 'expire', issued->>'token', (issued->>'invite_id')::uuid
    FROM (SELECT public.issue_patient_invite(
      'd0000000-0000-4000-8000-000000000031',
      'internal_dry_run',
      1
    ) AS issued) s$$,
  'staff can issue a short-ttl invite'
);
SELECT pg_temp.logout();

UPDATE public.patient_invites
SET expires_at = now() - interval '1 hour'
WHERE id = (SELECT invite_id FROM pg_temp.issued WHERE label = 'expire');

SET ROLE service_role;
SELECT is(
  (
    SELECT invite_status FROM public.lookup_patient_invite_by_hash(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.issued WHERE label = 'expire'))
    )
  ),
  'expired',
  'lookup marks a lapsed pending invite expired'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
