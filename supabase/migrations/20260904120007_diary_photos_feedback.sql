-- Diary, patient photos, doctor milestone photos, feedback surveys.

CREATE OR REPLACE FUNCTION public.assert_storage_ref(p_bucket text, p_path text, p_content_type text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_path IS NULL
     OR p_path = ''
     OR p_path LIKE '%://%'
     OR p_path LIKE '%..%'
     OR p_path LIKE '/%'
     OR p_path LIKE '%\%'
  THEN
    RAISE EXCEPTION 'integrity: invalid storage_path'
      USING ERRCODE = '23514';
  END IF;

  IF p_content_type NOT IN (
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp'
  ) THEN
    RAISE EXCEPTION 'integrity: invalid content_type'
      USING ERRCODE = '23514';
  END IF;

  IF p_bucket NOT IN ('patient-photos', 'doctor-milestone-photos') THEN
    RAISE EXCEPTION 'integrity: invalid storage_bucket'
      USING ERRCODE = '23514';
  END IF;
END;
$$;

CREATE TABLE public.diary_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  submitted_on date NOT NULL,
  pain smallint NOT NULL CHECK (pain >= 0 AND pain <= 10),
  swelling smallint NOT NULL CHECK (swelling >= 0 AND swelling <= 10),
  wellbeing public.wellbeing NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT diary_entries_one_per_day UNIQUE (treatment_id, submitted_on)
);

CREATE INDEX diary_entries_patient_id_idx ON public.diary_entries (patient_id);
CREATE INDEX diary_entries_clinic_id_idx ON public.diary_entries (clinic_id);

CREATE TRIGGER diary_entries_apply_parent
  BEFORE INSERT OR UPDATE ON public.diary_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent('require_active', 'has_patient');

CREATE OR REPLACE FUNCTION public.diary_entries_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'integrity: diary entries are immutable'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER diary_entries_reject_update
  BEFORE UPDATE ON public.diary_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.diary_entries_reject_mutation();

CREATE TABLE public.patient_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  submitted_on date NOT NULL,
  slot smallint NOT NULL CHECK (slot >= 1 AND slot <= 3),
  storage_bucket text NOT NULL CHECK (storage_bucket = 'patient-photos'),
  storage_path text NOT NULL,
  content_type text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT patient_photos_one_per_slot UNIQUE (treatment_id, submitted_on, slot)
);

CREATE INDEX patient_photos_patient_id_idx ON public.patient_photos (patient_id);
CREATE INDEX patient_photos_clinic_id_idx ON public.patient_photos (clinic_id);

CREATE TRIGGER patient_photos_apply_parent
  BEFORE INSERT OR UPDATE ON public.patient_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent('require_active', 'has_patient');

CREATE OR REPLACE FUNCTION public.patient_photos_validate_storage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.assert_storage_ref(NEW.storage_bucket, NEW.storage_path, NEW.content_type);
  RETURN NEW;
END;
$$;

CREATE TRIGGER patient_photos_validate_storage
  BEFORE INSERT OR UPDATE ON public.patient_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.patient_photos_validate_storage();

CREATE TABLE public.doctor_milestone_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  milestone_id uuid NOT NULL REFERENCES public.treatment_milestones (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  storage_bucket text NOT NULL CHECK (storage_bucket = 'doctor-milestone-photos'),
  storage_path text NOT NULL,
  content_type text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX doctor_milestone_photos_treatment_id_idx ON public.doctor_milestone_photos (treatment_id);
CREATE INDEX doctor_milestone_photos_milestone_id_idx ON public.doctor_milestone_photos (milestone_id);
CREATE INDEX doctor_milestone_photos_clinic_id_idx ON public.doctor_milestone_photos (clinic_id);

CREATE TRIGGER doctor_milestone_photos_apply_parent
  BEFORE INSERT OR UPDATE ON public.doctor_milestone_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent();

CREATE OR REPLACE FUNCTION public.doctor_milestone_photos_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  m_treatment uuid;
BEGIN
  PERFORM public.assert_storage_ref(NEW.storage_bucket, NEW.storage_path, NEW.content_type);

  SELECT treatment_id INTO m_treatment
  FROM public.treatment_milestones
  WHERE id = NEW.milestone_id;

  IF m_treatment IS NULL THEN
    RAISE EXCEPTION 'integrity: milestone not found'
      USING ERRCODE = '23503';
  END IF;

  IF m_treatment IS DISTINCT FROM NEW.treatment_id THEN
    RAISE EXCEPTION 'integrity: milestone does not belong to treatment'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER doctor_milestone_photos_validate
  BEFORE INSERT OR UPDATE ON public.doctor_milestone_photos
  FOR EACH ROW
  EXECUTE FUNCTION public.doctor_milestone_photos_validate();

CREATE TABLE public.feedback_surveys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL UNIQUE REFERENCES public.treatments (id),
  patient_id uuid NOT NULL REFERENCES public.patients (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  usefulness_score smallint NOT NULL CHECK (usefulness_score >= 1 AND usefulness_score <= 5),
  clarity_score smallint NOT NULL CHECK (clarity_score >= 1 AND clarity_score <= 5),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX feedback_surveys_patient_id_idx ON public.feedback_surveys (patient_id);
CREATE INDEX feedback_surveys_clinic_id_idx ON public.feedback_surveys (clinic_id);

CREATE TRIGGER feedback_surveys_apply_parent
  BEFORE INSERT OR UPDATE ON public.feedback_surveys
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent('require_completed', 'has_patient');

REVOKE ALL ON FUNCTION public.assert_storage_ref(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assert_storage_ref(text, text, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.diary_entries_reject_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.diary_entries_reject_mutation() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.patient_photos_validate_storage() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.patient_photos_validate_storage() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.doctor_milestone_photos_validate() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.doctor_milestone_photos_validate() FROM anon, authenticated;
