-- Treatments, periods, milestones. Current period is the row with ended_on IS NULL.

CREATE TABLE public.treatments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  treatment_context text NOT NULL DEFAULT 'sclerotherapy'
    CHECK (treatment_context = 'sclerotherapy'),
  status public.treatment_status NOT NULL DEFAULT 'active',
  pilot_cohort public.pilot_cohort,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX treatments_patient_id_idx ON public.treatments (patient_id);
CREATE INDEX treatments_clinic_id_idx ON public.treatments (clinic_id);

CREATE UNIQUE INDEX treatments_one_active_per_patient
  ON public.treatments (patient_id)
  WHERE status = 'active';

CREATE TRIGGER treatments_set_updated_at
  BEFORE UPDATE ON public.treatments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.treatments_apply_patient_clinic()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  p_clinic uuid;
BEGIN
  SELECT clinic_id INTO p_clinic FROM public.patients WHERE id = NEW.patient_id;
  IF p_clinic IS NULL THEN
    RAISE EXCEPTION 'integrity: patient not found'
      USING ERRCODE = '23503';
  END IF;
  NEW.clinic_id := p_clinic;
  RETURN NEW;
END;
$$;

CREATE TRIGGER treatments_apply_patient_clinic
  BEFORE INSERT OR UPDATE OF patient_id, clinic_id ON public.treatments
  FOR EACH ROW
  EXECUTE FUNCTION public.treatments_apply_patient_clinic();

CREATE OR REPLACE FUNCTION public.treatments_reject_patient_status_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND EXISTS (
       SELECT 1 FROM public.patients
       WHERE auth_user_id = auth.uid()
     )
     AND NOT EXISTS (
       SELECT 1 FROM public.clinic_staff
       WHERE auth_user_id = auth.uid()
     )
  THEN
    RAISE EXCEPTION 'integrity: patients cannot change treatment status'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER treatments_reject_patient_status_change
  BEFORE UPDATE OF status ON public.treatments
  FOR EACH ROW
  EXECUTE FUNCTION public.treatments_reject_patient_status_change();

CREATE OR REPLACE FUNCTION public.apply_treatment_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  t_patient uuid;
  t_clinic uuid;
  t_status public.treatment_status;
  require_active boolean := COALESCE(TG_ARGV[0], '') = 'require_active';
  require_completed boolean := COALESCE(TG_ARGV[0], '') = 'require_completed';
  has_patient boolean := COALESCE(TG_ARGV[1], '') = 'has_patient';
BEGIN
  SELECT patient_id, clinic_id, status
    INTO t_patient, t_clinic, t_status
  FROM public.treatments
  WHERE id = NEW.treatment_id;

  IF t_clinic IS NULL THEN
    RAISE EXCEPTION 'integrity: treatment % not found', NEW.treatment_id
      USING ERRCODE = '23503';
  END IF;

  IF require_active AND t_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'integrity: treatment is not active'
      USING ERRCODE = '23514';
  END IF;

  IF require_completed AND t_status IS DISTINCT FROM 'completed' THEN
    RAISE EXCEPTION 'integrity: treatment is not completed'
      USING ERRCODE = '23514';
  END IF;

  NEW.clinic_id := t_clinic;

  IF has_patient THEN
    IF NEW.patient_id IS DISTINCT FROM t_patient THEN
      RAISE EXCEPTION 'integrity: patient_id does not match treatment'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TABLE public.treatment_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  started_on date NOT NULL,
  ended_on date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT treatment_periods_ended_on_order
    CHECK (ended_on IS NULL OR ended_on >= started_on)
);

CREATE INDEX treatment_periods_treatment_id_idx ON public.treatment_periods (treatment_id);
CREATE INDEX treatment_periods_clinic_id_idx ON public.treatment_periods (clinic_id);

CREATE UNIQUE INDEX treatment_periods_one_current
  ON public.treatment_periods (treatment_id)
  WHERE ended_on IS NULL;

CREATE TRIGGER treatment_periods_set_updated_at
  BEFORE UPDATE ON public.treatment_periods
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER treatment_periods_apply_parent
  BEFORE INSERT OR UPDATE ON public.treatment_periods
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent();

CREATE TABLE public.treatment_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  title text NOT NULL,
  kind text,
  occurred_on date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX treatment_milestones_treatment_id_idx ON public.treatment_milestones (treatment_id);
CREATE INDEX treatment_milestones_clinic_id_idx ON public.treatment_milestones (clinic_id);

CREATE TRIGGER treatment_milestones_set_updated_at
  BEFORE UPDATE ON public.treatment_milestones
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER treatment_milestones_apply_parent
  BEFORE INSERT OR UPDATE ON public.treatment_milestones
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent();

REVOKE ALL ON FUNCTION public.treatments_apply_patient_clinic() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.treatments_apply_patient_clinic() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.treatments_reject_patient_status_change() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.treatments_reject_patient_status_change() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_treatment_parent() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_treatment_parent() FROM anon, authenticated;
