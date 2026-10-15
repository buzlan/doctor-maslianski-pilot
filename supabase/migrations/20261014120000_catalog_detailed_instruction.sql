-- Optional instruction snapshot: heading, plain text, ordered private photos.
ALTER TABLE public.action_catalog_items ADD COLUMN detailed_instruction jsonb;
ALTER TABLE public.action_assignments ADD COLUMN detailed_instruction jsonb;

CREATE FUNCTION public.valid_detailed_instruction(value jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = public, pg_temp AS $$
BEGIN
  IF value IS NULL THEN RETURN true; END IF;
  IF jsonb_typeof(value) <> 'object'
    OR NOT value ?& ARRAY['heading','text','photo_paths']
    OR value - ARRAY['heading','text','photo_paths'] <> '{}'::jsonb
    OR jsonb_typeof(value->'heading') <> 'string'
    OR jsonb_typeof(value->'text') <> 'string'
    OR jsonb_typeof(value->'photo_paths') <> 'array' THEN RETURN false; END IF;
  RETURN length(value->>'heading') <= 300
    AND length(value->>'text') <= 50000
    AND jsonb_array_length(value->'photo_paths') <= 10
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(value->'photo_paths') p
      WHERE jsonb_typeof(p) <> 'string')
    AND (length(btrim(value->>'heading')) > 0 OR length(btrim(value->>'text')) > 0
      OR jsonb_array_length(value->'photo_paths') > 0);
END;
$$;
ALTER TABLE public.action_catalog_items ADD CONSTRAINT catalog_detailed_instruction_valid
  CHECK (public.valid_detailed_instruction(detailed_instruction));
ALTER TABLE public.action_assignments ADD CONSTRAINT assignment_detailed_instruction_valid
  CHECK (public.valid_detailed_instruction(detailed_instruction));

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('instruction-photos','instruction-photos',false,10485760,ARRAY['image/png','image/webp','image/jpeg']);

CREATE FUNCTION public.instruction_photo_access(object_name text, operation text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE parts text[] := public.storage_path_parts(object_name);
BEGIN
  IF parts IS NULL OR array_length(parts,1) <> 3
    OR parts[3] !~ '^[A-Za-z0-9_-]+\.(png|webp|jpg|jpeg)$' THEN RETURN false; END IF;
  IF parts[1] = public.current_staff_clinic_id()::text THEN
    IF operation = 'read' THEN RETURN true; END IF;
    IF operation = 'write' THEN
      RETURN EXISTS (SELECT 1 FROM public.action_catalog_items c
        WHERE c.id::text = parts[2] AND c.clinic_id::text = parts[1]);
    END IF;
    IF operation = 'delete' THEN
      RETURN NOT EXISTS (SELECT 1 FROM public.action_catalog_items c
        WHERE c.detailed_instruction->'photo_paths' ? object_name)
        AND NOT EXISTS (SELECT 1 FROM public.action_assignments a
        WHERE a.detailed_instruction->'photo_paths' ? object_name);
    END IF;
  END IF;
  IF operation = 'read' THEN
    RETURN EXISTS (SELECT 1 FROM public.action_assignments a
      JOIN public.treatments t ON t.id = a.treatment_id AND t.clinic_id = a.clinic_id
      JOIN public.patients p ON p.id = t.patient_id AND p.clinic_id = t.clinic_id
      WHERE p.auth_user_id = auth.uid() AND a.clinic_id::text = parts[1]
        AND a.catalog_item_id::text = parts[2]
        AND a.detailed_instruction->'photo_paths' ? object_name);
  END IF;
  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.instruction_photo_access(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.instruction_photo_access(text,text) TO authenticated;
CREATE POLICY instruction_photos_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'instruction-photos' AND public.instruction_photo_access(name,'read'));
CREATE POLICY instruction_photos_upload ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'instruction-photos' AND public.instruction_photo_access(name,'write'));
CREATE POLICY instruction_photos_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'instruction-photos' AND public.instruction_photo_access(name,'delete'));

CREATE FUNCTION public.validate_catalog_instruction_photos()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE path text; parts text[];
BEGIN
  IF NOT public.valid_detailed_instruction(NEW.detailed_instruction) THEN
    RAISE EXCEPTION 'integrity: invalid detailed instruction' USING ERRCODE = '23514';
  END IF;
  FOR path IN SELECT jsonb_array_elements_text(NEW.detailed_instruction->'photo_paths') LOOP
    parts := public.storage_path_parts(path);
    IF parts IS NULL OR array_length(parts,1) <> 3
      OR parts[1] IS DISTINCT FROM NEW.clinic_id::text
      OR parts[2] IS DISTINCT FROM NEW.id::text
      OR parts[3] !~ '^[A-Za-z0-9_-]+\.(png|webp|jpg|jpeg)$' THEN
      RAISE EXCEPTION 'integrity: invalid instruction photo path' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM storage.objects WHERE bucket_id = 'instruction-photos' AND name = path FOR KEY SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'integrity: instruction photo missing' USING ERRCODE = '23503';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;
CREATE TRIGGER validate_catalog_instruction_photos BEFORE INSERT OR UPDATE OF detailed_instruction, id, clinic_id
  ON public.action_catalog_items FOR EACH ROW EXECUTE FUNCTION public.validate_catalog_instruction_photos();
REVOKE ALL ON FUNCTION public.validate_catalog_instruction_photos() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.prevent_referenced_instruction_photo_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF OLD.bucket_id = 'instruction-photos' AND (
    EXISTS (SELECT 1 FROM public.action_catalog_items WHERE detailed_instruction->'photo_paths' ? OLD.name)
    OR EXISTS (SELECT 1 FROM public.action_assignments WHERE detailed_instruction->'photo_paths' ? OLD.name)) THEN
    RAISE EXCEPTION 'integrity: instruction photo is still referenced' USING ERRCODE = '23503';
  END IF;
  RETURN OLD;
END;
$$;
CREATE TRIGGER prevent_referenced_instruction_photo_delete BEFORE DELETE ON storage.objects
  FOR EACH ROW EXECUTE FUNCTION public.prevent_referenced_instruction_photo_delete();
REVOKE ALL ON FUNCTION public.prevent_referenced_instruction_photo_delete() FROM PUBLIC, anon, authenticated;
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
       OR NEW.detailed_instruction IS DISTINCT FROM OLD.detailed_instruction
     )
  THEN
    NEW.status := 'draft';
  END IF;
  RETURN NEW;
END;
$$;

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
  WHERE id = NEW.catalog_item_id FOR SHARE;

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
  NEW.detailed_instruction := item.detailed_instruction;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.action_assignments_protect_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.title IS DISTINCT FROM OLD.title
     OR NEW.instruction IS DISTINCT FROM OLD.instruction
       OR NEW.detailed_instruction IS DISTINCT FROM OLD.detailed_instruction
     OR NEW.catalog_item_id IS DISTINCT FROM OLD.catalog_item_id
  THEN
    RAISE EXCEPTION 'integrity: assignment wording is immutable'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER action_assignments_protect_snapshot ON public.action_assignments;
CREATE TRIGGER action_assignments_protect_snapshot
  BEFORE UPDATE OF title, instruction, catalog_item_id, detailed_instruction ON public.action_assignments
  FOR EACH ROW EXECUTE FUNCTION public.action_assignments_protect_snapshot();

CREATE INDEX catalog_instruction_photos_idx ON public.action_catalog_items USING gin ((detailed_instruction->'photo_paths'));
CREATE INDEX assignment_instruction_photos_idx ON public.action_assignments USING gin ((detailed_instruction->'photo_paths'));
