-- Clinic-managed action catalog. Title required; instruction nullable (no invented medical text).

CREATE TABLE public.action_catalog_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  title text NOT NULL,
  instruction text,
  status public.catalog_item_status NOT NULL DEFAULT 'draft',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX action_catalog_items_clinic_id_idx ON public.action_catalog_items (clinic_id);

CREATE TRIGGER action_catalog_items_set_updated_at
  BEFORE UPDATE ON public.action_catalog_items
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();
