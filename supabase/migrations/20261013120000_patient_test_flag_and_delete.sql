-- Staff can mark a patient as an internal test account, and can purge that
-- patient: clinical rows, photo objects, push data, and the linked auth user.

ALTER TABLE public.patients
  ADD COLUMN is_test boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.patients.is_test IS
  'Clinic-facing flag for internal test accounts. Independent of pilot_cohort.';

GRANT UPDATE (is_test) ON public.patients TO authenticated;

-- ---------------------------------------------------------------------------
-- create_unactivated_patient gains an optional test flag. Calls with the
-- previous two arguments still work.
-- ---------------------------------------------------------------------------

DROP FUNCTION public.create_unactivated_patient(text, date);

CREATE FUNCTION public.create_unactivated_patient(
  p_clinic_label text,
  p_started_on date,
  p_is_test boolean DEFAULT false
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

  IF p_is_test IS NULL THEN
    RAISE EXCEPTION 'patient: is_test required'
      USING ERRCODE = '23502';
  END IF;

  label := btrim(p_clinic_label);
  IF length(label) < 1 OR length(label) > 120 THEN
    RAISE EXCEPTION 'patient: clinic_label invalid'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.patients (clinic_id, clinic_label, is_test)
  VALUES (staff_clinic, label, p_is_test)
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

REVOKE ALL ON FUNCTION public.create_unactivated_patient(text, date, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_unactivated_patient(text, date, boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_unactivated_patient(text, date, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- delete_patient: staff of the patient's clinic only. Removes clinical rows,
-- photo objects, invites, analytics, push data, handoffs, and the auth user.
-- Missing and foreign-clinic ids both look like not found.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.delete_patient(p_patient_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  v_clinic_id uuid;
  v_auth_user_id uuid;
BEGIN
  staff_clinic := public.current_staff_clinic_id();
  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  IF p_patient_id IS NULL THEN
    RAISE EXCEPTION 'patient: not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT clinic_id, auth_user_id
    INTO v_clinic_id, v_auth_user_id
  FROM public.patients
  WHERE id = p_patient_id
  FOR UPDATE;

  IF v_clinic_id IS NULL OR v_clinic_id IS DISTINCT FROM staff_clinic THEN
    RAISE EXCEPTION 'patient: not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_auth_user_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.clinic_staff WHERE auth_user_id = v_auth_user_id
  ) THEN
    RAISE EXCEPTION 'integrity: auth user is staff'
      USING ERRCODE = '23514';
  END IF;

  -- Completions refuse DELETE once an assignment is no longer completable.
  -- Disable that trigger only for this statement. The change rolls back
  -- with the transaction if a later delete fails.
  ALTER TABLE public.action_completions
    DISABLE TRIGGER action_completions_assignment_completable;
  DELETE FROM public.action_completions WHERE patient_id = p_patient_id;
  ALTER TABLE public.action_completions
    ENABLE TRIGGER action_completions_assignment_completable;

  DELETE FROM storage.objects AS object
  USING public.patient_photos AS photo
  WHERE photo.patient_id = p_patient_id
    AND object.bucket_id = photo.storage_bucket
    AND object.name = photo.storage_path;

  DELETE FROM storage.objects AS object
  USING public.doctor_milestone_photos AS photo
  JOIN public.treatments AS treatment ON treatment.id = photo.treatment_id
  WHERE treatment.patient_id = p_patient_id
    AND object.bucket_id = photo.storage_bucket
    AND object.name = photo.storage_path;

  DELETE FROM storage.objects
  WHERE bucket_id = 'patient-photos'
    AND name LIKE v_clinic_id::text || '/' || p_patient_id::text || '/%';

  DELETE FROM storage.objects AS object
  USING public.treatments AS treatment
  WHERE treatment.patient_id = p_patient_id
    AND object.bucket_id = 'doctor-milestone-photos'
    AND object.name LIKE treatment.clinic_id::text || '/' || treatment.id::text || '/%';

  DELETE FROM public.appointments
  WHERE treatment_id IN (SELECT id FROM public.treatments WHERE patient_id = p_patient_id);
  DELETE FROM public.diary_entries WHERE patient_id = p_patient_id;
  DELETE FROM public.patient_photos WHERE patient_id = p_patient_id;
  DELETE FROM public.doctor_milestone_photos
  WHERE treatment_id IN (SELECT id FROM public.treatments WHERE patient_id = p_patient_id);
  DELETE FROM public.feedback_surveys WHERE patient_id = p_patient_id;
  DELETE FROM public.patient_invites WHERE patient_id = p_patient_id;
  DELETE FROM public.product_events
  WHERE patient_id = p_patient_id
     OR treatment_id IN (SELECT id FROM public.treatments WHERE patient_id = p_patient_id);
  DELETE FROM public.action_assignments
  WHERE treatment_id IN (SELECT id FROM public.treatments WHERE patient_id = p_patient_id);
  DELETE FROM public.treatment_milestones
  WHERE treatment_id IN (SELECT id FROM public.treatments WHERE patient_id = p_patient_id);
  DELETE FROM public.treatment_periods
  WHERE treatment_id IN (SELECT id FROM public.treatments WHERE patient_id = p_patient_id);
  DELETE FROM public.treatments WHERE patient_id = p_patient_id;

  IF v_auth_user_id IS NOT NULL THEN
    DELETE FROM public.web_session_handoffs WHERE auth_user_id = v_auth_user_id;
  END IF;

  DELETE FROM public.patients WHERE id = p_patient_id;

  IF v_auth_user_id IS NOT NULL THEN
    DELETE FROM auth.users WHERE id = v_auth_user_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_patient(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_patient(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_patient(uuid) TO authenticated;
