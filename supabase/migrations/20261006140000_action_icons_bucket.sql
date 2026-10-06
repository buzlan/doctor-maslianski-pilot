-- Catalog action icons. Access policies are added in a subsequent migration.
-- Until then, this private bucket has no client upload/read permissions.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'action-icons',
  'action-icons',
  false,
  2097152,
  ARRAY['image/png', 'image/webp', 'image/jpeg']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
