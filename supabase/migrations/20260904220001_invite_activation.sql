-- TASK-033: invite issue/revoke/activate. Hash-only storage. Bind via trusted RPC.
-- Bind authorization is column privileges + SECURITY DEFINER activate RPC
-- (EXECUTE granted only to service_role) + trigger defense-in-depth.
-- A GUC is not the authorization boundary.

-- Pending unused invite TTL. Recovery remint is a separate 15-minute window after consume.
-- INVITE_TTL_DEFAULT_DAYS = 7
-- INVITE_TTL_MIN_DAYS = 1
-- INVITE_TTL_MAX_DAYS = 30
-- INVITE_RECOVERY_WINDOW_MINUTES = 15
-- PILOT_CONSENT_DOCUMENT_VERSION = 'pilot-v0'

REVOKE INSERT, UPDATE ON public.patient_invites FROM authenticated;
GRANT SELECT ON public.patient_invites TO authenticated;

REVOKE UPDATE ON public.patients FROM authenticated;
GRANT SELECT, INSERT ON public.patients TO authenticated;

REVOKE UPDATE ON public.treatments FROM authenticated;
GRANT SELECT, INSERT ON public.treatments TO authenticated;
GRANT UPDATE (status, completed_at, cancelled_at, updated_at)
  ON public.treatments TO authenticated;

CREATE OR REPLACE FUNCTION public.protect_patient_bind_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon', 'service_role') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.auth_user_id IS NOT NULL
       OR NEW.privacy_accepted_at IS NOT NULL
       OR NEW.pilot_consent_accepted_at IS NOT NULL
       OR NEW.consent_document_version IS NOT NULL
       OR NEW.pilot_cohort IS NOT NULL
    THEN
      RAISE EXCEPTION 'privilege: patient bind columns are activation-only'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id
     OR NEW.privacy_accepted_at IS DISTINCT FROM OLD.privacy_accepted_at
     OR NEW.pilot_consent_accepted_at IS DISTINCT FROM OLD.pilot_consent_accepted_at
     OR NEW.consent_document_version IS DISTINCT FROM OLD.consent_document_version
     OR NEW.pilot_cohort IS DISTINCT FROM OLD.pilot_cohort
  THEN
    RAISE EXCEPTION 'privilege: patient bind columns are activation-only'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER patients_protect_bind_columns
  BEFORE INSERT OR UPDATE OF
    auth_user_id,
    privacy_accepted_at,
    pilot_consent_accepted_at,
    consent_document_version,
    pilot_cohort
  ON public.patients
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_patient_bind_columns();

CREATE OR REPLACE FUNCTION public.protect_treatment_bind_cohort()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon', 'service_role') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.pilot_cohort IS NOT NULL THEN
      RAISE EXCEPTION 'privilege: treatment cohort is activation-only'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.pilot_cohort IS DISTINCT FROM OLD.pilot_cohort THEN
    RAISE EXCEPTION 'privilege: treatment cohort is activation-only'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER treatments_protect_bind_cohort
  BEFORE INSERT OR UPDATE OF pilot_cohort ON public.treatments
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_treatment_bind_cohort();

REVOKE ALL ON FUNCTION public.protect_patient_bind_columns() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.protect_patient_bind_columns() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.protect_treatment_bind_cohort() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.protect_treatment_bind_cohort() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.issue_patient_invite(
  p_treatment_id uuid,
  p_pilot_cohort public.pilot_cohort,
  p_ttl_days integer DEFAULT 7
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  ttl_days integer;
  staff_row public.clinic_staff%ROWTYPE;
  treatment_row public.treatments%ROWTYPE;
  patient_row public.patients%ROWTYPE;
  raw_token text;
  invite_row public.patient_invites%ROWTYPE;
BEGIN
  ttl_days := COALESCE(p_ttl_days, 7);
  IF ttl_days < 1 OR ttl_days > 30 THEN
    RAISE EXCEPTION 'invite: ttl out of range'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO staff_row
  FROM public.clinic_staff
  WHERE auth_user_id = auth.uid();

  IF staff_row.id IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO treatment_row
  FROM public.treatments
  WHERE id = p_treatment_id;

  IF treatment_row.id IS NULL THEN
    RAISE EXCEPTION 'invite: treatment not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF treatment_row.clinic_id IS DISTINCT FROM staff_row.clinic_id THEN
    RAISE EXCEPTION 'privilege: staff clinic mismatch'
      USING ERRCODE = '42501';
  END IF;

  IF treatment_row.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'invite: treatment is not active'
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO patient_row
  FROM public.patients
  WHERE id = treatment_row.patient_id;

  IF patient_row.auth_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'invite: patient already activated'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.patient_invites
  SET
    status = CASE
      WHEN expires_at <= now() THEN 'expired'::public.invite_status
      ELSE 'revoked'::public.invite_status
    END,
    revoked_at = CASE
      WHEN expires_at <= now() THEN revoked_at
      ELSE now()
    END
  WHERE treatment_id = p_treatment_id
    AND status = 'pending';

  raw_token := replace(replace(rtrim(
    encode(extensions.gen_random_bytes(32), 'base64'),
    '='
  ), '+', '-'), '/', '_');

  INSERT INTO public.patient_invites (
    clinic_id,
    patient_id,
    treatment_id,
    token_hash,
    status,
    expires_at,
    created_by_staff_id,
    pilot_cohort
  ) VALUES (
    staff_row.clinic_id,
    patient_row.id,
    treatment_row.id,
    extensions.digest(convert_to(raw_token, 'UTF8'), 'sha256'),
    'pending',
    now() + make_interval(days => ttl_days),
    staff_row.id,
    p_pilot_cohort
  )
  RETURNING * INTO invite_row;

  INSERT INTO public.product_events (
    name,
    occurred_at,
    pilot_cohort,
    patient_id,
    treatment_id
  ) VALUES (
    'patient_invited',
    now(),
    p_pilot_cohort,
    patient_row.id,
    treatment_row.id
  );

  RETURN jsonb_build_object(
    'invite_id', invite_row.id,
    'expires_at', invite_row.expires_at,
    'token', raw_token
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_patient_invite(p_invite_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  invite_clinic uuid;
  invite_status public.invite_status;
BEGIN
  SELECT clinic_id INTO staff_clinic
  FROM public.clinic_staff
  WHERE auth_user_id = auth.uid();

  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  SELECT clinic_id, status INTO invite_clinic, invite_status
  FROM public.patient_invites
  WHERE id = p_invite_id;

  IF invite_clinic IS NULL THEN
    RAISE EXCEPTION 'invite: not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF invite_clinic IS DISTINCT FROM staff_clinic THEN
    RAISE EXCEPTION 'privilege: staff clinic mismatch'
      USING ERRCODE = '42501';
  END IF;

  IF invite_status IS DISTINCT FROM 'pending' THEN
    RETURN;
  END IF;

  UPDATE public.patient_invites
  SET status = 'revoked', revoked_at = now()
  WHERE id = p_invite_id
    AND status = 'pending';
END;
$$;

CREATE OR REPLACE FUNCTION public.lookup_patient_invite_by_hash(p_token_hash_hex text)
RETURNS TABLE (
  invite_id uuid,
  invite_status public.invite_status,
  expires_at timestamptz,
  consumed_at timestamptz,
  bound_auth_user_id uuid,
  recovery_eligible boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  decoded_hash bytea;
  invite_row public.patient_invites%ROWTYPE;
  bound uuid;
BEGIN
  BEGIN
    decoded_hash := decode(p_token_hash_hex, 'hex');
  EXCEPTION WHEN others THEN
    RETURN;
  END;

  UPDATE public.patient_invites
  SET status = 'expired'
  WHERE token_hash = decoded_hash
    AND patient_invites.status = 'pending'
    AND patient_invites.expires_at <= now();

  SELECT * INTO invite_row
  FROM public.patient_invites
  WHERE patient_invites.token_hash = decoded_hash;

  IF invite_row.id IS NULL THEN
    RETURN;
  END IF;

  SELECT auth_user_id INTO bound
  FROM public.patients
  WHERE id = invite_row.patient_id;

  invite_id := invite_row.id;
  invite_status := invite_row.status;
  expires_at := invite_row.expires_at;
  consumed_at := invite_row.consumed_at;
  bound_auth_user_id := bound;
  recovery_eligible :=
    invite_row.status = 'consumed'
    AND invite_row.consumed_at IS NOT NULL
    AND invite_row.consumed_at > now() - interval '15 minutes';
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_patient_from_invite(
  p_token_hash_hex text,
  p_auth_user_id uuid,
  p_privacy_accepted boolean,
  p_pilot_consent_accepted boolean,
  p_consent_document_version text
)
RETURNS TABLE (
  outcome text,
  bound_auth_user_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  decoded_hash bytea;
  invite_row public.patient_invites%ROWTYPE;
  patient_row public.patients%ROWTYPE;
  treatment_row public.treatments%ROWTYPE;
  updated_id uuid;
BEGIN
  IF COALESCE(p_privacy_accepted, false) IS NOT TRUE
     OR COALESCE(p_pilot_consent_accepted, false) IS NOT TRUE
     OR p_consent_document_version IS DISTINCT FROM 'pilot-v0'
  THEN
    outcome := 'unusable';
    bound_auth_user_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_auth_user_id IS NULL THEN
    outcome := 'unusable';
    bound_auth_user_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    decoded_hash := decode(p_token_hash_hex, 'hex');
  EXCEPTION WHEN others THEN
    outcome := 'unusable';
    bound_auth_user_id := NULL;
    RETURN NEXT;
    RETURN;
  END;

  SELECT * INTO invite_row
  FROM public.patient_invites
  WHERE token_hash = decoded_hash
  FOR UPDATE;

  IF invite_row.id IS NULL THEN
    outcome := 'unusable';
    bound_auth_user_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF invite_row.status IS DISTINCT FROM 'pending' OR invite_row.expires_at <= now() THEN
    IF invite_row.status = 'pending' AND invite_row.expires_at <= now() THEN
      UPDATE public.patient_invites
      SET status = 'expired'
      WHERE id = invite_row.id
        AND status = 'pending';
    END IF;

    SELECT auth_user_id INTO bound_auth_user_id
    FROM public.patients
    WHERE id = invite_row.patient_id;
    outcome := 'not_pending';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO patient_row
  FROM public.patients
  WHERE id = invite_row.patient_id
  FOR UPDATE;

  SELECT * INTO treatment_row
  FROM public.treatments
  WHERE id = invite_row.treatment_id
  FOR UPDATE;

  IF patient_row.auth_user_id IS NOT NULL
     OR treatment_row.status IS DISTINCT FROM 'active'
  THEN
    outcome := 'unusable';
    bound_auth_user_id := patient_row.auth_user_id;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.patient_invites
  SET status = 'consumed', consumed_at = now()
  WHERE id = invite_row.id
    AND status = 'pending'
    AND expires_at > now()
  RETURNING id INTO updated_id;

  IF updated_id IS NULL THEN
    SELECT auth_user_id INTO bound_auth_user_id
    FROM public.patients
    WHERE id = invite_row.patient_id;
    outcome := 'not_pending';
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.patients
  SET
    auth_user_id = p_auth_user_id,
    pilot_cohort = invite_row.pilot_cohort,
    privacy_accepted_at = now(),
    pilot_consent_accepted_at = now(),
    consent_document_version = p_consent_document_version
  WHERE id = patient_row.id
    AND auth_user_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invite: patient bind failed'
      USING ERRCODE = '40001';
  END IF;

  UPDATE public.treatments
  SET pilot_cohort = invite_row.pilot_cohort
  WHERE id = treatment_row.id;

  INSERT INTO public.product_events (
    name,
    occurred_at,
    pilot_cohort,
    patient_id,
    treatment_id
  ) VALUES (
    'patient_activated',
    now(),
    invite_row.pilot_cohort,
    patient_row.id,
    treatment_row.id
  );

  outcome := 'activated';
  bound_auth_user_id := p_auth_user_id;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_patient_invite(uuid, public.pilot_cohort, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_patient_invite(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lookup_patient_invite_by_hash(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_patient_from_invite(text, uuid, boolean, boolean, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.issue_patient_invite(uuid, public.pilot_cohort, integer) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_patient_invite(uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.lookup_patient_invite_by_hash(text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.activate_patient_from_invite(text, uuid, boolean, boolean, text) FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.issue_patient_invite(uuid, public.pilot_cohort, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_patient_invite(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.lookup_patient_invite_by_hash(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.activate_patient_from_invite(text, uuid, boolean, boolean, text) TO service_role;
