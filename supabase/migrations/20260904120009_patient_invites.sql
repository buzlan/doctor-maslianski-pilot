-- Invite table foundation only. No activate RPC, QR helper, or email sending.

CREATE TABLE public.patient_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  token_hash bytea NOT NULL UNIQUE,
  status public.invite_status NOT NULL DEFAULT 'pending',
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  revoked_at timestamptz,
  created_by_staff_id uuid NOT NULL REFERENCES public.clinic_staff (id),
  pilot_cohort public.pilot_cohort NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX patient_invites_clinic_id_idx ON public.patient_invites (clinic_id);
CREATE INDEX patient_invites_patient_id_idx ON public.patient_invites (patient_id);
CREATE INDEX patient_invites_treatment_id_idx ON public.patient_invites (treatment_id);

CREATE UNIQUE INDEX patient_invites_one_pending_per_treatment
  ON public.patient_invites (treatment_id)
  WHERE status = 'pending';

CREATE TRIGGER patient_invites_set_updated_at
  BEFORE UPDATE ON public.patient_invites
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER patient_invites_apply_parent
  BEFORE INSERT OR UPDATE ON public.patient_invites
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent('none', 'has_patient');

CREATE OR REPLACE FUNCTION public.patient_invites_staff_clinic()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
BEGIN
  SELECT clinic_id INTO staff_clinic
  FROM public.clinic_staff
  WHERE id = NEW.created_by_staff_id;

  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'integrity: staff not found'
      USING ERRCODE = '23503';
  END IF;

  IF staff_clinic IS DISTINCT FROM NEW.clinic_id THEN
    RAISE EXCEPTION 'integrity: invite staff clinic mismatch'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER patient_invites_staff_clinic
  BEFORE INSERT OR UPDATE OF created_by_staff_id, clinic_id ON public.patient_invites
  FOR EACH ROW
  EXECUTE FUNCTION public.patient_invites_staff_clinic();

REVOKE ALL ON FUNCTION public.patient_invites_staff_clinic() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.patient_invites_staff_clinic() FROM anon, authenticated;
