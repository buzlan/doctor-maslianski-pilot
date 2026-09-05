-- TASK-034 clinic review writes: clinic_label, catalog re-approval,
-- approved-only assignment copy, and SECURITY INVOKER RPCs.

-- ---------------------------------------------------------------------------
-- patients.clinic_label
-- ---------------------------------------------------------------------------

ALTER TABLE public.patients
  ADD COLUMN clinic_label text;

UPDATE public.patients
SET clinic_label = 'Synthetic Patient'
WHERE clinic_label IS NULL;

ALTER TABLE public.patients
  ALTER COLUMN clinic_label SET NOT NULL;

ALTER TABLE public.patients
  ADD CONSTRAINT patients_clinic_label_len
  CHECK (length(btrim(clinic_label)) BETWEEN 1 AND 120);

REVOKE UPDATE ON public.patients FROM authenticated;
GRANT SELECT, INSERT ON public.patients TO authenticated;
GRANT UPDATE (clinic_label, updated_at) ON public.patients TO authenticated;

-- ---------------------------------------------------------------------------
-- Catalog: wording change on an approved item forces draft. Assignments
-- are not rewritten.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.action_catalog_items_reapproval()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status = 'approved'
     AND (
       NEW.title IS DISTINCT FROM OLD.title
       OR NEW.instruction IS DISTINCT FROM OLD.instruction
     )
  THEN
    NEW.status := 'draft';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER action_catalog_items_reapproval
  BEFORE UPDATE ON public.action_catalog_items
  FOR EACH ROW
  EXECUTE FUNCTION public.action_catalog_items_reapproval();

REVOKE ALL ON FUNCTION public.action_catalog_items_reapproval() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.action_catalog_items_reapproval() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Assignments: only approved catalog items; copy wording; snapshot immutable.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.action_assignments_copy_approved_catalog()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  item public.action_catalog_items%ROWTYPE;
BEGIN
  SELECT * INTO item
  FROM public.action_catalog_items
  WHERE id = NEW.catalog_item_id;

  IF item.id IS NULL THEN
    RAISE EXCEPTION 'integrity: catalog item not found'
      USING ERRCODE = '23503';
  END IF;

  IF item.clinic_id IS DISTINCT FROM NEW.clinic_id THEN
    RAISE EXCEPTION 'integrity: catalog item clinic mismatch'
      USING ERRCODE = '23514';
  END IF;

  IF item.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'integrity: catalog item is not approved'
      USING ERRCODE = '23514';
  END IF;

  NEW.title := item.title;
  NEW.instruction := item.instruction;
  RETURN NEW;
END;
$$;

CREATE TRIGGER action_assignments_copy_approved_catalog
  BEFORE INSERT ON public.action_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.action_assignments_copy_approved_catalog();

CREATE OR REPLACE FUNCTION public.action_assignments_protect_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.title IS DISTINCT FROM OLD.title
     OR NEW.instruction IS DISTINCT FROM OLD.instruction
     OR NEW.catalog_item_id IS DISTINCT FROM OLD.catalog_item_id
  THEN
    RAISE EXCEPTION 'integrity: assignment wording is immutable'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER action_assignments_protect_snapshot
  BEFORE UPDATE OF title, instruction, catalog_item_id ON public.action_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.action_assignments_protect_snapshot();

REVOKE ALL ON FUNCTION public.action_assignments_copy_approved_catalog() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.action_assignments_copy_approved_catalog() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.action_assignments_protect_snapshot() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.action_assignments_protect_snapshot() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- SECURITY INVOKER RPCs. RLS remains authoritative. Fail if caller is not staff.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_unactivated_patient(
  p_clinic_label text,
  p_started_on date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  label text;
  patient_id uuid;
  treatment_id uuid;
  period_id uuid;
BEGIN
  staff_clinic := public.current_staff_clinic_id();
  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  IF p_started_on IS NULL THEN
    RAISE EXCEPTION 'patient: started_on required'
      USING ERRCODE = '23502';
  END IF;

  label := btrim(p_clinic_label);
  IF length(label) < 1 OR length(label) > 120 THEN
    RAISE EXCEPTION 'patient: clinic_label invalid'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.patients (clinic_id, clinic_label)
  VALUES (staff_clinic, label)
  RETURNING id INTO patient_id;

  INSERT INTO public.treatments (patient_id, clinic_id, treatment_context, status)
  VALUES (patient_id, staff_clinic, 'sclerotherapy', 'active')
  RETURNING id INTO treatment_id;

  INSERT INTO public.treatment_periods (treatment_id, clinic_id, started_on)
  VALUES (treatment_id, staff_clinic, p_started_on)
  RETURNING id INTO period_id;

  RETURN jsonb_build_object(
    'patient_id', patient_id,
    'treatment_id', treatment_id,
    'period_id', period_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_catalog_item_to_treatment(
  p_treatment_id uuid,
  p_catalog_item_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  item public.action_catalog_items%ROWTYPE;
  treatment_row public.treatments%ROWTYPE;
  assignment_id uuid;
BEGIN
  staff_clinic := public.current_staff_clinic_id();
  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RAISE EXCEPTION 'assignment: date range invalid'
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO item
  FROM public.action_catalog_items
  WHERE id = p_catalog_item_id;

  IF item.id IS NULL THEN
    RAISE EXCEPTION 'assignment: catalog item not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF item.clinic_id IS DISTINCT FROM staff_clinic THEN
    RAISE EXCEPTION 'privilege: staff clinic mismatch'
      USING ERRCODE = '42501';
  END IF;

  IF item.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'assignment: catalog item is not approved'
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO treatment_row
  FROM public.treatments
  WHERE id = p_treatment_id;

  IF treatment_row.id IS NULL THEN
    RAISE EXCEPTION 'assignment: treatment not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF treatment_row.clinic_id IS DISTINCT FROM staff_clinic THEN
    RAISE EXCEPTION 'privilege: staff clinic mismatch'
      USING ERRCODE = '42501';
  END IF;

  IF treatment_row.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'assignment: treatment is not active'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.action_assignments (
    treatment_id,
    clinic_id,
    catalog_item_id,
    title,
    instruction,
    start_date,
    end_date,
    status
  ) VALUES (
    treatment_row.id,
    staff_clinic,
    item.id,
    item.title,
    item.instruction,
    p_start_date,
    p_end_date,
    'active'
  )
  RETURNING id INTO assignment_id;

  RETURN assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_new_treatment_period(
  p_treatment_id uuid,
  p_ended_on date,
  p_started_on date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  treatment_row public.treatments%ROWTYPE;
  current_period public.treatment_periods%ROWTYPE;
  period_id uuid;
BEGIN
  staff_clinic := public.current_staff_clinic_id();
  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  IF p_ended_on IS NULL OR p_started_on IS NULL THEN
    RAISE EXCEPTION 'period: dates required'
      USING ERRCODE = '23502';
  END IF;

  SELECT * INTO treatment_row
  FROM public.treatments
  WHERE id = p_treatment_id
  FOR UPDATE;

  IF treatment_row.id IS NULL THEN
    RAISE EXCEPTION 'period: treatment not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF treatment_row.clinic_id IS DISTINCT FROM staff_clinic THEN
    RAISE EXCEPTION 'privilege: staff clinic mismatch'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO current_period
  FROM public.treatment_periods
  WHERE treatment_id = p_treatment_id
    AND ended_on IS NULL
  FOR UPDATE;

  IF current_period.id IS NULL THEN
    RAISE EXCEPTION 'period: no current period'
      USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.treatment_periods
  SET ended_on = p_ended_on
  WHERE id = current_period.id;

  INSERT INTO public.treatment_periods (treatment_id, clinic_id, started_on)
  VALUES (treatment_row.id, staff_clinic, p_started_on)
  RETURNING id INTO period_id;

  RETURN period_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.replace_current_appointment(
  p_treatment_id uuid,
  p_wall_clock timestamp
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  treatment_row public.treatments%ROWTYPE;
  appointment_id uuid;
BEGIN
  staff_clinic := public.current_staff_clinic_id();
  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  IF p_wall_clock IS NULL THEN
    RAISE EXCEPTION 'appointment: wall_clock required'
      USING ERRCODE = '23502';
  END IF;

  SELECT * INTO treatment_row
  FROM public.treatments
  WHERE id = p_treatment_id
  FOR UPDATE;

  IF treatment_row.id IS NULL THEN
    RAISE EXCEPTION 'appointment: treatment not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF treatment_row.clinic_id IS DISTINCT FROM staff_clinic THEN
    RAISE EXCEPTION 'privilege: staff clinic mismatch'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.appointments
  SET status = 'superseded', superseded_at = now()
  WHERE treatment_id = p_treatment_id
    AND status = 'current';

  INSERT INTO public.appointments (
    treatment_id,
    clinic_id,
    status,
    wall_clock,
    time_zone,
    at_utc
  ) VALUES (
    treatment_row.id,
    staff_clinic,
    'current',
    p_wall_clock,
    'UTC',
    now()
  )
  RETURNING id INTO appointment_id;

  RETURN appointment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_unactivated_patient(text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_unactivated_patient(text, date) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.assign_catalog_item_to_treatment(uuid, uuid, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assign_catalog_item_to_treatment(uuid, uuid, date, date) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.start_new_treatment_period(uuid, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_new_treatment_period(uuid, date, date) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.replace_current_appointment(uuid, timestamp) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.replace_current_appointment(uuid, timestamp) FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_unactivated_patient(text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_catalog_item_to_treatment(uuid, uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_new_treatment_period(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_current_appointment(uuid, timestamp) TO authenticated;
