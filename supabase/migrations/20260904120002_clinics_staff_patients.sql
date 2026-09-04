-- Clinics, staff, patients. Patients may exist before auth.users is linked.

CREATE TABLE public.clinics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  time_zone text NOT NULL DEFAULT 'Europe/Minsk',
  phone text,
  email text,
  booking_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER clinics_set_updated_at
  BEFORE UPDATE ON public.clinics
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.clinic_staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users (id),
  role public.staff_role NOT NULL DEFAULT 'staff',
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX clinic_staff_clinic_id_idx ON public.clinic_staff (clinic_id);

CREATE TRIGGER clinic_staff_set_updated_at
  BEFORE UPDATE ON public.clinic_staff
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.patients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  auth_user_id uuid UNIQUE REFERENCES auth.users (id),
  pilot_cohort public.pilot_cohort,
  privacy_accepted_at timestamptz,
  pilot_consent_accepted_at timestamptz,
  consent_document_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX patients_clinic_id_idx ON public.patients (clinic_id);

CREATE UNIQUE INDEX patients_auth_user_id_unique
  ON public.patients (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

CREATE TRIGGER patients_set_updated_at
  BEFORE UPDATE ON public.patients
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.prevent_staff_patient_auth_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_TABLE_NAME = 'patients' AND NEW.auth_user_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.clinic_staff WHERE auth_user_id = NEW.auth_user_id
    ) THEN
      RAISE EXCEPTION 'integrity: auth user cannot be both staff and patient'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_TABLE_NAME = 'clinic_staff' THEN
    IF EXISTS (
      SELECT 1 FROM public.patients WHERE auth_user_id = NEW.auth_user_id
    ) THEN
      RAISE EXCEPTION 'integrity: auth user cannot be both staff and patient'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER patients_prevent_staff_overlap
  BEFORE INSERT OR UPDATE OF auth_user_id ON public.patients
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_staff_patient_auth_overlap();

CREATE TRIGGER clinic_staff_prevent_patient_overlap
  BEFORE INSERT OR UPDATE OF auth_user_id ON public.clinic_staff
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_staff_patient_auth_overlap();

REVOKE ALL ON FUNCTION public.prevent_staff_patient_auth_overlap() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prevent_staff_patient_auth_overlap() FROM anon, authenticated;
