-- Caller-scoped SECURITY DEFINER helpers for RLS. Fixed search_path.
-- EXECUTE is revoked from PUBLIC/anon and granted only to authenticated.

CREATE OR REPLACE FUNCTION public.current_patient_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT id
  FROM public.patients
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_patient_clinic_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT clinic_id
  FROM public.patients
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_staff_clinic_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT clinic_id
  FROM public.clinic_staff
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clinic_staff
    WHERE auth_user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.patient_belongs_to_clinic(p_patient_id uuid, p_clinic_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.patients p
    WHERE p.id = p_patient_id
      AND p.clinic_id = p_clinic_id
      AND (
        p.auth_user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.clinic_staff s
          WHERE s.auth_user_id = auth.uid()
            AND s.clinic_id = p_clinic_id
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.treatment_in_staff_clinic(p_treatment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.treatments t
    JOIN public.clinic_staff s
      ON s.clinic_id = t.clinic_id
     AND s.auth_user_id = auth.uid()
    WHERE t.id = p_treatment_id
  );
$$;

CREATE OR REPLACE FUNCTION public.treatment_owned_by_current_patient(p_treatment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.treatments t
    JOIN public.patients p
      ON p.id = t.patient_id
     AND p.auth_user_id = auth.uid()
    WHERE t.id = p_treatment_id
  );
$$;

DO $$
DECLARE
  sig text;
BEGIN
  FOREACH sig IN ARRAY ARRAY[
    'public.current_patient_id()',
    'public.current_patient_clinic_id()',
    'public.current_staff_clinic_id()',
    'public.is_staff()',
    'public.patient_belongs_to_clinic(uuid, uuid)',
    'public.treatment_in_staff_clinic(uuid)',
    'public.treatment_owned_by_current_patient(uuid)'
  ]
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', sig);
  END LOOP;
END;
$$;
