-- Icons belong to catalog actions. Assignments keep their existing catalog link
-- and will resolve the current catalog icon when patient data is refreshed.
ALTER TABLE public.action_catalog_items
  ADD COLUMN icon_storage_path text;

COMMENT ON COLUMN public.action_catalog_items.icon_storage_path IS
  'Optional object path in the private action-icons bucket; not a URL. Shared by linked assignments. NULL means no custom icon.';
