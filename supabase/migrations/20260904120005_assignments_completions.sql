-- Action assignments (copied wording) and completions. Instruction is nullable.

CREATE TABLE public.action_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  catalog_item_id uuid NOT NULL REFERENCES public.action_catalog_items (id),
  title text NOT NULL,
  instruction text,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status public.assignment_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT action_assignments_date_range CHECK (end_date >= start_date)
);

CREATE INDEX action_assignments_treatment_id_idx ON public.action_assignments (treatment_id);
CREATE INDEX action_assignments_clinic_id_idx ON public.action_assignments (clinic_id);
CREATE INDEX action_assignments_catalog_item_id_idx ON public.action_assignments (catalog_item_id);

CREATE TRIGGER action_assignments_set_updated_at
  BEFORE UPDATE ON public.action_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER action_assignments_apply_parent
  BEFORE INSERT OR UPDATE ON public.action_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent();

CREATE OR REPLACE FUNCTION public.action_assignments_catalog_clinic()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  item_clinic uuid;
BEGIN
  SELECT clinic_id INTO item_clinic
  FROM public.action_catalog_items
  WHERE id = NEW.catalog_item_id;

  IF item_clinic IS NULL THEN
    RAISE EXCEPTION 'integrity: catalog item not found'
      USING ERRCODE = '23503';
  END IF;

  IF item_clinic IS DISTINCT FROM NEW.clinic_id THEN
    RAISE EXCEPTION 'integrity: catalog item clinic mismatch'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER action_assignments_catalog_clinic
  BEFORE INSERT OR UPDATE OF catalog_item_id, clinic_id ON public.action_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.action_assignments_catalog_clinic();

CREATE TABLE public.action_completions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES public.action_assignments (id),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  completed_on date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT action_completions_assignment_date UNIQUE (assignment_id, completed_on)
);

CREATE INDEX action_completions_treatment_id_idx ON public.action_completions (treatment_id);
CREATE INDEX action_completions_patient_id_idx ON public.action_completions (patient_id);
CREATE INDEX action_completions_clinic_id_idx ON public.action_completions (clinic_id);

CREATE TRIGGER action_completions_apply_parent
  BEFORE INSERT OR UPDATE ON public.action_completions
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent('require_active', 'has_patient');

CREATE OR REPLACE FUNCTION public.action_completions_assignment_completable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  a public.action_assignments%ROWTYPE;
  on_date date;
BEGIN
  IF TG_OP = 'DELETE' THEN
    SELECT * INTO a FROM public.action_assignments WHERE id = OLD.assignment_id;
    on_date := OLD.completed_on;
  ELSE
    SELECT * INTO a FROM public.action_assignments WHERE id = NEW.assignment_id;
    on_date := NEW.completed_on;
  END IF;

  IF a.id IS NULL THEN
    RAISE EXCEPTION 'integrity: assignment not found'
      USING ERRCODE = '23503';
  END IF;

  IF TG_OP <> 'DELETE' AND a.treatment_id IS DISTINCT FROM NEW.treatment_id THEN
    RAISE EXCEPTION 'integrity: assignment does not belong to treatment'
      USING ERRCODE = '23514';
  END IF;

  IF a.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'integrity: assignment is not completable'
      USING ERRCODE = '23514';
  END IF;

  IF on_date < a.start_date OR on_date > a.end_date THEN
    RAISE EXCEPTION 'integrity: assignment is not completable on date'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER action_completions_assignment_completable
  BEFORE INSERT OR UPDATE OR DELETE ON public.action_completions
  FOR EACH ROW
  EXECUTE FUNCTION public.action_completions_assignment_completable();

REVOKE ALL ON FUNCTION public.action_assignments_catalog_clinic() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.action_assignments_catalog_clinic() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.action_completions_assignment_completable() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.action_completions_assignment_completable() FROM anon, authenticated;
