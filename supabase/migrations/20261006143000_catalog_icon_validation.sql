-- Validate icon references independently of caller visibility in Storage.
CREATE OR REPLACE FUNCTION public.action_catalog_items_validate_icon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[];
BEGIN
  IF NEW.icon_storage_path IS NULL THEN
    RETURN NEW;
  END IF;

  parts := public.storage_path_parts(NEW.icon_storage_path);
  IF parts IS NULL OR array_length(parts, 1) <> 3
     OR parts[1] IS DISTINCT FROM NEW.clinic_id::text
     OR parts[2] IS DISTINCT FROM NEW.id::text
     OR parts[3] !~ '^[A-Za-z0-9_-]+\.(png|webp|jpg|jpeg)$'
  THEN
    RAISE EXCEPTION 'integrity: invalid catalog icon path'
      USING ERRCODE = '23514';
  END IF;

  PERFORM 1 FROM storage.objects
  WHERE bucket_id = 'action-icons' AND name = NEW.icon_storage_path
  FOR KEY SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrity: catalog icon object not found'
      USING ERRCODE = '23503';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER action_catalog_items_validate_icon
  BEFORE INSERT OR UPDATE OF icon_storage_path, clinic_id, id
  ON public.action_catalog_items
  FOR EACH ROW
  EXECUTE FUNCTION public.action_catalog_items_validate_icon();

REVOKE ALL ON FUNCTION public.action_catalog_items_validate_icon()
  FROM PUBLIC, anon, authenticated;
