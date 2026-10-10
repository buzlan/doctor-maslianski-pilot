-- One-time opaque credentials for moving an existing patient session
-- from mobile Safari into the iOS Home Screen web app.
-- Raw tokens are never stored. patient_id is intentionally omitted.

CREATE TABLE public.web_session_handoffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash bytea NOT NULL UNIQUE,
  auth_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);

CREATE INDEX web_session_handoffs_auth_user_id_idx
  ON public.web_session_handoffs (auth_user_id);

ALTER TABLE public.web_session_handoffs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.web_session_handoffs FROM PUBLIC;
REVOKE ALL ON TABLE public.web_session_handoffs FROM anon;
REVOKE ALL ON TABLE public.web_session_handoffs FROM authenticated;

CREATE OR REPLACE FUNCTION public.issue_web_session_handoff(
  p_auth_user_id uuid,
  p_token_hash_hex text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  handoff_id uuid;
  v_hash bytea;
BEGIN
  IF p_auth_user_id IS NULL OR p_token_hash_hex IS NULL OR p_token_hash_hex !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'handoff: invalid'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.patients
    WHERE auth_user_id = p_auth_user_id
  ) THEN
    RAISE EXCEPTION 'handoff: not a patient'
      USING ERRCODE = '42501';
  END IF;

  v_hash := decode(p_token_hash_hex, 'hex');

  UPDATE public.web_session_handoffs
  SET consumed_at = now()
  WHERE auth_user_id = p_auth_user_id
    AND consumed_at IS NULL;

  INSERT INTO public.web_session_handoffs (token_hash, auth_user_id, expires_at)
  VALUES (v_hash, p_auth_user_id, now() + interval '10 minutes')
  RETURNING id INTO handoff_id;

  RETURN handoff_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_web_session_handoff(p_token_hash_hex text)
RETURNS TABLE (outcome text, auth_user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  handoff public.web_session_handoffs%ROWTYPE;
  v_hash bytea;
BEGIN
  IF p_token_hash_hex IS NULL OR p_token_hash_hex !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
    RETURN;
  END IF;

  v_hash := decode(p_token_hash_hex, 'hex');

  SELECT * INTO handoff
  FROM public.web_session_handoffs AS handoff_row
  WHERE handoff_row.token_hash = v_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
    RETURN;
  END IF;

  IF handoff.consumed_at IS NOT NULL THEN
    RETURN QUERY SELECT 'consumed'::text, NULL::uuid;
    RETURN;
  END IF;

  IF handoff.expires_at <= now() THEN
    RETURN QUERY SELECT 'expired'::text, NULL::uuid;
    RETURN;
  END IF;

  UPDATE public.web_session_handoffs
  SET consumed_at = now()
  WHERE id = handoff.id
    AND consumed_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'consumed'::text, NULL::uuid;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'ok'::text, handoff.auth_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_web_session_handoff(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.issue_web_session_handoff(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.issue_web_session_handoff(uuid, text) FROM authenticated;
REVOKE ALL ON FUNCTION public.consume_web_session_handoff(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_web_session_handoff(text) FROM anon;
REVOKE ALL ON FUNCTION public.consume_web_session_handoff(text) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.issue_web_session_handoff(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.consume_web_session_handoff(text) TO service_role;
