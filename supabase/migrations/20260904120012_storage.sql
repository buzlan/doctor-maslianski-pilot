-- Private storage buckets and object policies. No public buckets, no permanent public URLs.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'patient-photos',
    'patient-photos',
    false,
    15728640,
    ARRAY['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
  ),
  (
    'doctor-milestone-photos',
    'doctor-milestone-photos',
    false,
    15728640,
    ARRAY['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
  )
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE OR REPLACE FUNCTION public.storage_path_parts(object_name text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN object_name IS NULL
      OR object_name = ''
      OR object_name LIKE '%://%'
      OR object_name LIKE '%..%'
      OR object_name LIKE '/%'
      OR object_name LIKE '%\%'
    THEN NULL
    ELSE string_to_array(object_name, '/')
  END;
$$;

-- patient-photos: {clinic_id}/{patient_id}/{treatment_id}/{yyyy-mm-dd}/{photo_id}.{ext}
CREATE OR REPLACE FUNCTION public.storage_patient_photo_writable(object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[];
  pid uuid;
BEGIN
  pid := public.current_patient_id();
  IF pid IS NULL THEN
    RETURN false;
  END IF;

  parts := public.storage_path_parts(object_name);
  IF parts IS NULL OR array_length(parts, 1) < 5 THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.treatments t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE p.id = pid
      AND p.auth_user_id = auth.uid()
      AND t.clinic_id::text = parts[1]
      AND t.patient_id::text = parts[2]
      AND t.id::text = parts[3]
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.storage_patient_photo_readable(object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[];
BEGIN
  parts := public.storage_path_parts(object_name);
  IF parts IS NULL OR array_length(parts, 1) < 5 THEN
    RETURN false;
  END IF;

  IF public.current_staff_clinic_id()::text = parts[1] THEN
    RETURN true;
  END IF;

  RETURN public.storage_patient_photo_writable(object_name);
END;
$$;

-- doctor-milestone-photos: {clinic_id}/{treatment_id}/{milestone_id}/{photo_id}.{ext}
CREATE OR REPLACE FUNCTION public.storage_doctor_photo_writable(object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[];
  sid uuid;
BEGIN
  sid := public.current_staff_clinic_id();
  IF sid IS NULL THEN
    RETURN false;
  END IF;

  parts := public.storage_path_parts(object_name);
  IF parts IS NULL OR array_length(parts, 1) < 4 THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.treatment_milestones m
    JOIN public.treatments t ON t.id = m.treatment_id
    WHERE t.clinic_id = sid
      AND t.clinic_id::text = parts[1]
      AND t.id::text = parts[2]
      AND m.id::text = parts[3]
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.storage_doctor_photo_readable(object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[];
BEGIN
  parts := public.storage_path_parts(object_name);
  IF parts IS NULL OR array_length(parts, 1) < 4 THEN
    RETURN false;
  END IF;

  IF public.current_staff_clinic_id()::text = parts[1] THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.treatments t
    JOIN public.patients p ON p.id = t.patient_id AND p.auth_user_id = auth.uid()
    WHERE t.clinic_id::text = parts[1]
      AND t.id::text = parts[2]
  );
END;
$$;

CREATE POLICY patient_photos_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'patient-photos'
    AND public.storage_patient_photo_readable(name)
  );

CREATE POLICY patient_photos_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'patient-photos'
    AND public.storage_patient_photo_writable(name)
  );

CREATE POLICY doctor_photos_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'doctor-milestone-photos'
    AND public.storage_doctor_photo_readable(name)
  );

CREATE POLICY doctor_photos_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'doctor-milestone-photos'
    AND public.storage_doctor_photo_writable(name)
  );

DO $$
DECLARE
  sig text;
BEGIN
  FOREACH sig IN ARRAY ARRAY[
    'public.storage_path_parts(text)',
    'public.storage_patient_photo_writable(text)',
    'public.storage_patient_photo_readable(text)',
    'public.storage_doctor_photo_writable(text)',
    'public.storage_doctor_photo_readable(text)'
  ]
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', sig);
  END LOOP;
END;
$$;
