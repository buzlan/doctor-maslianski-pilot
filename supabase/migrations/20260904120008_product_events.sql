-- Product analytics only. No jsonb payload. clinic_id is derived from patient/treatment.

CREATE TABLE public.product_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (name IN (
    'patient_invited',
    'patient_activated',
    'treatment_started',
    'task_scheduled',
    'task_completed',
    'checkin_requested',
    'checkin_submitted',
    'photo_checkpoint_requested',
    'photo_checkpoint_completed',
    'patient_photo_added',
    'treatment_journey_completed',
    'feedback_submitted',
    'app_opened'
  )),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  pilot_cohort public.pilot_cohort NOT NULL,
  clinic_id uuid REFERENCES public.clinics (id),
  patient_id uuid REFERENCES public.patients (id),
  treatment_id uuid REFERENCES public.treatments (id),
  entity_id text,
  usefulness_score smallint,
  clarity_score smallint,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_events_entity_id_safe CHECK (
    entity_id IS NULL
    OR (
      entity_id NOT LIKE '%://%'
      AND entity_id NOT LIKE '%..%'
      AND entity_id NOT LIKE '%/%'
    )
  ),
  CONSTRAINT product_events_scores_match_name CHECK (
    (
      name <> 'feedback_submitted'
      AND usefulness_score IS NULL
      AND clarity_score IS NULL
    )
    OR (
      name = 'feedback_submitted'
      AND usefulness_score IS NOT NULL
      AND clarity_score IS NOT NULL
      AND usefulness_score BETWEEN 1 AND 5
      AND clarity_score BETWEEN 1 AND 5
    )
  ),
  CONSTRAINT product_events_feedback_ids CHECK (
    name <> 'feedback_submitted'
    OR (patient_id IS NOT NULL AND treatment_id IS NOT NULL)
  ),
  CONSTRAINT product_events_clinic_when_ids CHECK (
    (patient_id IS NULL AND treatment_id IS NULL) = (clinic_id IS NULL)
  )
);

CREATE INDEX product_events_clinic_occurred_idx
  ON public.product_events (clinic_id, occurred_at);
CREATE INDEX product_events_cohort_name_occurred_idx
  ON public.product_events (pilot_cohort, name, occurred_at);
CREATE INDEX product_events_treatment_name_entity_idx
  ON public.product_events (treatment_id, name, entity_id);
CREATE INDEX product_events_patient_id_idx ON public.product_events (patient_id);

CREATE OR REPLACE FUNCTION public.product_events_derive_clinic()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  t_patient uuid;
  t_clinic uuid;
  p_clinic uuid;
BEGIN
  IF NEW.treatment_id IS NOT NULL THEN
    SELECT patient_id, clinic_id INTO t_patient, t_clinic
    FROM public.treatments
    WHERE id = NEW.treatment_id;

    IF t_clinic IS NULL THEN
      RAISE EXCEPTION 'integrity: treatment not found'
        USING ERRCODE = '23503';
    END IF;

    IF NEW.patient_id IS NOT NULL AND NEW.patient_id IS DISTINCT FROM t_patient THEN
      RAISE EXCEPTION 'integrity: patient_id does not match treatment'
        USING ERRCODE = '23514';
    END IF;

    NEW.clinic_id := t_clinic;
  ELSIF NEW.patient_id IS NOT NULL THEN
    SELECT clinic_id INTO p_clinic
    FROM public.patients
    WHERE id = NEW.patient_id;

    IF p_clinic IS NULL THEN
      RAISE EXCEPTION 'integrity: patient not found'
        USING ERRCODE = '23503';
    END IF;

    NEW.clinic_id := p_clinic;
  ELSE
    NEW.clinic_id := NULL;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER product_events_derive_clinic
  BEFORE INSERT OR UPDATE ON public.product_events
  FOR EACH ROW
  EXECUTE FUNCTION public.product_events_derive_clinic();

REVOKE ALL ON FUNCTION public.product_events_derive_clinic() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.product_events_derive_clinic() FROM anon, authenticated;
