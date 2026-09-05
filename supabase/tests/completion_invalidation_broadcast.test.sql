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

SELECT pg_temp.create_auth_user(
  'f0000000-0000-4000-8000-000000000012',
  'staff.b.realtime@local.test'
);
SELECT pg_temp.create_auth_user(
  'f0000000-0000-4000-8000-0000000000a1',
  'patient.a.realtime@local.test'
);
SELECT pg_temp.create_auth_user(
  'f0000000-0000-4000-8000-0000000000b1',
  'patient.b.realtime@local.test'
);

INSERT INTO public.clinics (id, name, time_zone)
VALUES ('f0000000-0000-4000-8000-000000000002', 'Synthetic Clinic B Realtime', 'Europe/Minsk');

INSERT INTO public.clinic_staff (id, clinic_id, auth_user_id, display_name)
VALUES (
  'f0000000-0000-4000-8000-000000000013',
  'f0000000-0000-4000-8000-000000000002',
  'f0000000-0000-4000-8000-000000000012',
  'Synthetic Staff B Realtime'
);

UPDATE public.patients
SET auth_user_id = 'f0000000-0000-4000-8000-0000000000a1'
WHERE id = '10000000-0000-4000-8000-000000000020';

INSERT INTO public.patients (id, clinic_id, clinic_label, auth_user_id)
VALUES (
  'f0000000-0000-4000-8000-0000000000b0',
  'f0000000-0000-4000-8000-000000000002',
  'Synthetic Clinic B Patient',
  'f0000000-0000-4000-8000-0000000000b1'
);

INSERT INTO public.treatments (
  id, patient_id, clinic_id, treatment_context, status
) VALUES (
  'f0000000-0000-4000-8000-0000000000b2',
  'f0000000-0000-4000-8000-0000000000b0',
  'f0000000-0000-4000-8000-000000000002',
  'sclerotherapy',
  'active'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'action_completions'
      AND NOT t.tgisinternal
      AND t.tgname = 'action_completions_notify_invalidation'
  ),
  'action_completions has AFTER INSERT/DELETE invalidation trigger'
);

SELECT ok(
  position('realtime.send' IN pg_get_functiondef('public.notify_completion_invalidation()'::regprocedure)) > 0,
  'notify_completion_invalidation calls realtime.send'
);

SELECT ok(
  position('broadcast_changes' IN pg_get_functiondef('public.notify_completion_invalidation()'::regprocedure)) = 0,
  'notify_completion_invalidation does not call broadcast_changes'
);

SELECT ok(
  position('''hint''' IN pg_get_functiondef('public.notify_completion_invalidation()'::regprocedure)) > 0,
  'completion broadcast payload is a hint only'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.can_subscribe_treatment_topic(text)', 'execute'),
  'anon cannot execute can_subscribe_treatment_topic'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.can_subscribe_treatment_topic(text)', 'execute'),
  'authenticated can execute can_subscribe_treatment_topic'
);

SELECT ok(
  NOT has_function_privilege('authenticated', 'public.notify_completion_invalidation()', 'execute'),
  'authenticated cannot execute notify_completion_invalidation'
);

SELECT pg_temp.login('10000000-0000-4000-8000-000000000010');
SELECT ok(
  public.can_subscribe_treatment_topic('treatment:10000000-0000-4000-8000-000000000021'),
  'staff A can subscribe to own-clinic treatment topic'
);
SELECT ok(
  NOT public.can_subscribe_treatment_topic('treatment:f0000000-0000-4000-8000-0000000000b2'),
  'staff A cannot subscribe to clinic B treatment topic'
);
SELECT ok(
  NOT public.can_subscribe_treatment_topic('patients-list'),
  'staff A cannot subscribe to a non-treatment topic'
);
SELECT pg_temp.logout();

SELECT pg_temp.login('f0000000-0000-4000-8000-000000000012');
SELECT ok(
  public.can_subscribe_treatment_topic('treatment:f0000000-0000-4000-8000-0000000000b2'),
  'staff B can subscribe to own-clinic treatment topic'
);
SELECT ok(
  NOT public.can_subscribe_treatment_topic('treatment:10000000-0000-4000-8000-000000000021'),
  'staff B cannot subscribe to clinic A treatment topic'
);
SELECT pg_temp.logout();

SELECT pg_temp.login('f0000000-0000-4000-8000-0000000000a1');
SELECT ok(
  public.can_subscribe_treatment_topic('treatment:10000000-0000-4000-8000-000000000021'),
  'patient A can subscribe to own treatment topic'
);
SELECT ok(
  NOT public.can_subscribe_treatment_topic('treatment:f0000000-0000-4000-8000-0000000000b2'),
  'patient A cannot subscribe to another patient treatment topic'
);
SELECT pg_temp.logout();

SELECT pg_temp.login('f0000000-0000-4000-8000-0000000000b1');
SELECT ok(
  NOT public.can_subscribe_treatment_topic('treatment:10000000-0000-4000-8000-000000000021'),
  'patient B cannot subscribe to patient A treatment topic'
);
SELECT pg_temp.logout();

SELECT * FROM finish();
ROLLBACK;
