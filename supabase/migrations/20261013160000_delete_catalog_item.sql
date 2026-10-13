-- Staff can remove a catalog item. Assignments copied from it, and their
-- completion marks, go with it. The completion trigger rejects DELETE once an
-- assignment is disabled or outside its dates, so it is disabled only for
-- this purge and re-enabled in the same transaction.

CREATE FUNCTION public.delete_catalog_item(p_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  staff_clinic uuid;
  item public.action_catalog_items%ROWTYPE;
BEGIN
  staff_clinic := public.current_staff_clinic_id();
  IF staff_clinic IS NULL THEN
    RAISE EXCEPTION 'privilege: staff only'
      USING ERRCODE = '42501';
  END IF;

  IF p_item_id IS NULL THEN
    RAISE EXCEPTION 'catalog: not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT *
    INTO item
  FROM public.action_catalog_items
  WHERE id = p_item_id
  FOR UPDATE;

  IF item.id IS NULL OR item.clinic_id IS DISTINCT FROM staff_clinic THEN
    RAISE EXCEPTION 'catalog: not found'
      USING ERRCODE = 'P0002';
  END IF;

  ALTER TABLE public.action_completions
    DISABLE TRIGGER action_completions_assignment_completable;
  DELETE FROM public.action_completions
  WHERE assignment_id IN (
    SELECT id
    FROM public.action_assignments
    WHERE catalog_item_id = item.id
  );
  ALTER TABLE public.action_completions
    ENABLE TRIGGER action_completions_assignment_completable;

  DELETE FROM public.action_assignments
  WHERE catalog_item_id = item.id;

  UPDATE public.action_catalog_items
  SET icon_storage_path = NULL
  WHERE id = item.id;

  IF item.icon_storage_path IS NOT NULL THEN
    BEGIN
      DELETE FROM storage.objects
      WHERE bucket_id = 'action-icons'
        AND name = item.icon_storage_path;
    EXCEPTION
      WHEN insufficient_privilege THEN
        NULL;
    END;
  END IF;

  DELETE FROM public.action_catalog_items
  WHERE id = item.id;

  RETURN jsonb_build_object('icon_storage_path', item.icon_storage_path);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_catalog_item(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_catalog_item(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_catalog_item(uuid) TO authenticated;

-- After the catalog row is gone, the old delete rule still required that row.
-- Staff may remove an unused icon that belongs to their clinic prefix.
CREATE FUNCTION public.storage_action_icon_deletable(object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[] := public.storage_path_parts(object_name);
BEGIN
  IF parts IS NULL OR array_length(parts, 1) <> 3
     OR parts[3] !~ '^[A-Za-z0-9_-]+\.(png|webp|jpg|jpeg)$' THEN
    RETURN false;
  END IF;
  RETURN parts[1] = public.current_staff_clinic_id()::text
    AND public.storage_action_icon_unused(object_name);
END;
$$;

REVOKE ALL ON FUNCTION public.storage_action_icon_deletable(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.storage_action_icon_deletable(text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.storage_action_icon_deletable(text) TO authenticated;

DROP POLICY action_icons_delete_unused_staff ON storage.objects;

CREATE POLICY action_icons_delete_unused_staff ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'action-icons'
    AND public.storage_action_icon_deletable(name)
  );
