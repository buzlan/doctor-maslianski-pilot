-- Object names: {clinic_id}/{catalog_item_id}/{unique_file_name}.{ext}.
CREATE FUNCTION public.storage_action_icon_writable(object_name text)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[] := public.storage_path_parts(object_name);
BEGIN
  IF parts IS NULL OR array_length(parts, 1) <> 3
     OR parts[3] !~ '^[A-Za-z0-9_-]+\.(png|webp|jpg|jpeg)$' THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.action_catalog_items c
    WHERE c.clinic_id = public.current_staff_clinic_id()
      AND c.clinic_id::text = parts[1]
      AND c.id::text = parts[2]
  );
END;
$$;

CREATE FUNCTION public.storage_action_icon_readable(object_name text)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[] := public.storage_path_parts(object_name);
BEGIN
  IF parts IS NULL OR array_length(parts, 1) <> 3
     OR parts[3] !~ '^[A-Za-z0-9_-]+\.(png|webp|jpg|jpeg)$' THEN
    RETURN false;
  END IF;
  IF public.storage_action_icon_writable(object_name) THEN
    RETURN true;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.action_catalog_items c
    JOIN public.action_assignments a ON a.catalog_item_id = c.id
      AND a.clinic_id = c.clinic_id
    JOIN public.treatments t ON t.id = a.treatment_id
      AND t.clinic_id = c.clinic_id
    JOIN public.patients p ON p.id = t.patient_id
      AND p.clinic_id = c.clinic_id
    WHERE p.auth_user_id = auth.uid()
      AND c.icon_storage_path = object_name
      AND c.clinic_id::text = parts[1]
      AND c.id::text = parts[2]
  );
END;
$$;

REVOKE ALL ON FUNCTION public.storage_action_icon_writable(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.storage_action_icon_readable(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.storage_action_icon_writable(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_action_icon_readable(text) TO authenticated;

CREATE POLICY action_icons_insert_staff ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'action-icons' AND public.storage_action_icon_writable(name));

CREATE POLICY action_icons_select ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'action-icons' AND public.storage_action_icon_readable(name));

-- Replacement uploads use a new path. UPDATE/DELETE permissions are deliberately
-- deferred until reference validation and unused-object cleanup are implemented.
