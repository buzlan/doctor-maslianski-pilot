-- Hosted Supabase rejects DELETE on storage.objects (42501) and requires the
-- Storage API. delete_patient still removes database rows and returns the
-- object paths. The clinic dashboard deletes those files after the RPC.
-- A local database without that guard still deletes the objects here.

DROP FUNCTION public.delete_patient(uuid);

CREATE FUNCTION public.delete_patient(p_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  v_clinic_id uuid;
  v_auth_user_id uuid;
  v_patient_photos jsonb := '[]'::jsonb;
  v_doctor_photos jsonb := '[]'::jsonb;
  v_extra jsonb;
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

  v_patient_photos := (
    SELECT COALESCE(jsonb_agg(photo.storage_path), '[]'::jsonb)
    FROM public.patient_photos AS photo
    WHERE photo.patient_id = p_patient_id
  );

  v_doctor_photos := (
    SELECT COALESCE(jsonb_agg(photo.storage_path), '[]'::jsonb)
    FROM public.doctor_milestone_photos AS photo
    JOIN public.treatments AS treatment ON treatment.id = photo.treatment_id
    WHERE treatment.patient_id = p_patient_id
  );

  BEGIN
    SELECT COALESCE(jsonb_agg(object.name), '[]'::jsonb)
      INTO v_extra
    FROM storage.objects AS object
    WHERE object.bucket_id = 'patient-photos'
      AND object.name LIKE v_clinic_id::text || '/' || p_patient_id::text || '/%';
    v_patient_photos := v_patient_photos || COALESCE(v_extra, '[]'::jsonb);

    SELECT COALESCE(jsonb_agg(object.name), '[]'::jsonb)
      INTO v_extra
    FROM storage.objects AS object
    JOIN public.treatments AS treatment
      ON treatment.patient_id = p_patient_id
     AND object.name LIKE treatment.clinic_id::text || '/' || treatment.id::text || '/%'
    WHERE object.bucket_id = 'doctor-milestone-photos';
    v_doctor_photos := v_doctor_photos || COALESCE(v_extra, '[]'::jsonb);
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  -- Completions refuse DELETE once an assignment is no longer completable.
  ALTER TABLE public.action_completions
    DISABLE TRIGGER action_completions_assignment_completable;
  DELETE FROM public.action_completions WHERE patient_id = p_patient_id;
  ALTER TABLE public.action_completions
    ENABLE TRIGGER action_completions_assignment_completable;

  BEGIN
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
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

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

  RETURN jsonb_build_object(
    'patient_photos', v_patient_photos,
    'doctor_milestone_photos', v_doctor_photos
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_patient(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_patient(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_patient(uuid) TO authenticated;

CREATE POLICY patient_photos_storage_delete_staff ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'patient-photos'
    AND (public.storage_path_parts(name))[1] = public.current_staff_clinic_id()::text
  );

CREATE POLICY doctor_photos_storage_delete_staff ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'doctor-milestone-photos'
    AND (public.storage_path_parts(name))[1] = public.current_staff_clinic_id()::text
  );
