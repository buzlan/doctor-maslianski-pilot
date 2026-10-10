BEGIN;

SELECT * FROM no_plan();

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

CREATE OR REPLACE FUNCTION pg_temp.token_hash_hex(p_token text)
RETURNS text
LANGUAGE sql
AS $$
  SELECT encode(extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex');
$$;

GRANT EXECUTE ON FUNCTION pg_temp.token_hash_hex(text) TO service_role;

CREATE TABLE pg_temp.handoffs (
  label text PRIMARY KEY,
  token text NOT NULL,
  handoff_id uuid NOT NULL
);
GRANT ALL ON TABLE pg_temp.handoffs TO service_role;

SELECT pg_temp.create_auth_user(
  'e1000000-0000-4000-8000-000000000001',
  'handoff.synthetic@users.invalid'
);
SELECT pg_temp.create_auth_user(
  'e1000000-0000-4000-8000-000000000003',
  'notpatient.synthetic@users.invalid'
);

INSERT INTO public.patients (id, clinic_id, auth_user_id, clinic_label)
VALUES (
  'e1000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000001',
  'Synthetic Handoff Patient'
);

CREATE TEMP TABLE baseline AS
SELECT
  (SELECT count(*) FROM public.patients) AS patients,
  (SELECT count(*) FROM auth.users) AS users;

SET ROLE anon;
SELECT throws_ok(
  $$SELECT public.issue_web_session_handoff(
      'e1000000-0000-4000-8000-000000000001',
      repeat('ab', 32)
    )$$,
  '42501',
  NULL,
  'anon cannot issue a handoff'
);
SELECT throws_ok(
  $$SELECT public.consume_web_session_handoff(repeat('ab', 32))$$,
  '42501',
  NULL,
  'anon cannot consume a handoff'
);
RESET ROLE;

SET ROLE authenticated;
SELECT throws_ok(
  $$SELECT public.issue_web_session_handoff(
      'e1000000-0000-4000-8000-000000000001',
      repeat('ab', 32)
    )$$,
  '42501',
  NULL,
  'authenticated cannot issue a handoff directly'
);
RESET ROLE;

SET ROLE service_role;
SELECT throws_ok(
  $$SELECT public.issue_web_session_handoff(
      'e1000000-0000-4000-8000-000000000003',
      repeat('cd', 32)
    )$$,
  '42501',
  NULL,
  'a non-patient auth user cannot receive a handoff'
);

SELECT lives_ok(
  $$INSERT INTO pg_temp.handoffs (label, token, handoff_id)
    VALUES (
      'first',
      'handoff-token-first-0123456789abcd',
      public.issue_web_session_handoff(
        'e1000000-0000-4000-8000-000000000001',
        pg_temp.token_hash_hex('handoff-token-first-0123456789abcd')
      )
    )$$,
  'service role can issue a handoff for an existing patient'
);
RESET ROLE;

SELECT ok(
  (
    SELECT expires_at <= now() + interval '10 minutes'
       AND expires_at > now() + interval '9 minutes'
    FROM public.web_session_handoffs
    WHERE id = (SELECT handoff_id FROM pg_temp.handoffs WHERE label = 'first')
  ),
  'handoff ttl is 10 minutes'
);

SET ROLE service_role;
SELECT lives_ok(
  $$INSERT INTO pg_temp.handoffs (label, token, handoff_id)
    VALUES (
      'second',
      'handoff-token-second-0123456789abc',
      public.issue_web_session_handoff(
        'e1000000-0000-4000-8000-000000000001',
        pg_temp.token_hash_hex('handoff-token-second-0123456789abc')
      )
    )$$,
  'a newer handoff can be issued for the same patient'
);

SELECT is(
  (
    SELECT outcome FROM public.consume_web_session_handoff(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.handoffs WHERE label = 'first'))
    )
  ),
  'consumed',
  'issuing a new handoff invalidates the previous one'
);

SELECT is(
  (
    SELECT outcome FROM public.consume_web_session_handoff(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.handoffs WHERE label = 'second'))
    )
  ),
  'ok',
  'the current handoff can be consumed once'
);
SELECT is(
  (
    SELECT auth_user_id FROM public.consume_web_session_handoff(
      pg_temp.token_hash_hex('never-issued-handoff-token-0001')
    )
  ),
  NULL,
  'an unknown handoff does not return a user'
);
RESET ROLE;

-- The successful consume above already burned `second`. Re-issue to assert the user id,
-- then cover expiry, invalid, and a second consume.
SET ROLE service_role;
SELECT lives_ok(
  $$INSERT INTO pg_temp.handoffs (label, token, handoff_id)
    VALUES (
      'restore',
      'handoff-token-restore-0123456789ab',
      public.issue_web_session_handoff(
        'e1000000-0000-4000-8000-000000000001',
        pg_temp.token_hash_hex('handoff-token-restore-0123456789ab')
      )
    )$$,
  'issue the handoff that restores the existing user'
);

SELECT is(
  (
    SELECT auth_user_id FROM public.consume_web_session_handoff(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.handoffs WHERE label = 'restore'))
    )
  ),
  'e1000000-0000-4000-8000-000000000001'::uuid,
  'consume returns the same existing auth user'
);

SELECT is(
  (
    SELECT outcome FROM public.consume_web_session_handoff(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.handoffs WHERE label = 'restore'))
    )
  ),
  'consumed',
  'a consumed handoff cannot be used again'
);

SELECT lives_ok(
  $$INSERT INTO pg_temp.handoffs (label, token, handoff_id)
    VALUES (
      'expired',
      'handoff-token-expired-0123456789ab',
      public.issue_web_session_handoff(
        'e1000000-0000-4000-8000-000000000001',
        pg_temp.token_hash_hex('handoff-token-expired-0123456789ab')
      )
    )$$,
  'issue a handoff that will expire'
);
RESET ROLE;

UPDATE public.web_session_handoffs
SET expires_at = now() - interval '1 minute'
WHERE id = (SELECT handoff_id FROM pg_temp.handoffs WHERE label = 'expired');

SET ROLE service_role;
SELECT is(
  (
    SELECT outcome FROM public.consume_web_session_handoff(
      pg_temp.token_hash_hex((SELECT token FROM pg_temp.handoffs WHERE label = 'expired'))
    )
  ),
  'expired',
  'an expired handoff is rejected'
);

SELECT is(
  (
    SELECT outcome FROM public.consume_web_session_handoff('zz')
  ),
  'invalid',
  'a malformed handoff hash is rejected'
);

SELECT is(
  (
    SELECT outcome FROM public.consume_web_session_handoff(repeat('ab', 32))
  ),
  'invalid',
  'an unknown handoff hash is rejected'
);
RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.patients),
  (SELECT patients FROM baseline),
  'handoff issue and consume do not create a second patient'
);
SELECT is(
  (SELECT count(*) FROM auth.users),
  (SELECT users FROM baseline),
  'handoff issue and consume do not create a second auth user'
);

SELECT * FROM finish();
ROLLBACK;
