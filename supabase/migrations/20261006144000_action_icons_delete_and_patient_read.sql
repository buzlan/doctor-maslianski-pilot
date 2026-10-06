CREATE OR REPLACE FUNCTION public.storage_action_icon_unused(object_name text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.action_catalog_items WHERE icon_storage_path = object_name
  );
$$;

REVOKE ALL ON FUNCTION public.storage_action_icon_unused(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.storage_action_icon_unused(text) TO authenticated;
GRANT DELETE ON storage.objects TO authenticated;

CREATE POLICY action_icons_delete_unused_staff ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'action-icons'
    AND public.storage_action_icon_writable(name)
    AND public.storage_action_icon_unused(name));

-- The deleting transaction locks the object row. Reference validation takes
-- KEY SHARE on that row, so concurrent saves/deletes cannot leave a broken link.
CREATE OR REPLACE FUNCTION public.prevent_referenced_action_icon_delete()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.bucket_id = 'action-icons' AND EXISTS (
    SELECT 1 FROM public.action_catalog_items WHERE icon_storage_path = OLD.name
  ) THEN
    RAISE EXCEPTION 'integrity: catalog icon is still referenced' USING ERRCODE = '23503';
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER prevent_referenced_action_icon_delete
  BEFORE DELETE ON storage.objects
  FOR EACH ROW EXECUTE FUNCTION public.prevent_referenced_action_icon_delete();
REVOKE ALL ON FUNCTION public.prevent_referenced_action_icon_delete() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_assignment_icons(p_treatment_id uuid)
RETURNS TABLE (assignment_id uuid, icon_storage_path text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.id, c.icon_storage_path
  FROM public.action_assignments a
  JOIN public.treatments t ON t.id = a.treatment_id AND t.clinic_id = a.clinic_id
  JOIN public.patients p ON p.id = t.patient_id AND p.clinic_id = t.clinic_id
  JOIN public.action_catalog_items c ON c.id = a.catalog_item_id AND c.clinic_id = a.clinic_id
  WHERE t.id = p_treatment_id
    AND (p.auth_user_id = auth.uid() OR t.clinic_id = public.current_staff_clinic_id());
$$;

REVOKE ALL ON FUNCTION public.get_assignment_icons(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_assignment_icons(uuid) TO authenticated;
