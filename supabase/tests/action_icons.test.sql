BEGIN;
-- Synthetic metadata only, rolled back. Match the flag set by Storage API.
SET LOCAL storage.allow_delete_query = 'true';
SELECT * FROM no_plan();
CREATE FUNCTION pg_temp.icon_login(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END; $$;
CREATE FUNCTION pg_temp.icon_logout() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
END; $$;
INSERT INTO auth.users (id) VALUES ('f6100000-0000-4000-8000-000000000003'), ('f6100000-0000-4000-8000-000000000004'), ('f6100000-0000-4000-8000-000000000005'), ('f6100000-0000-4000-8000-000000000006');
INSERT INTO public.clinics (id, name) VALUES ('f6100000-0000-4000-8000-000000000001', 'Synthetic Icons A'), ('f6100000-0000-4000-8000-000000000002', 'Synthetic Icons B');
INSERT INTO public.clinic_staff (clinic_id, auth_user_id, display_name) VALUES
('f6100000-0000-4000-8000-000000000001', 'f6100000-0000-4000-8000-000000000003', 'Synthetic Icons Staff A'), ('f6100000-0000-4000-8000-000000000002', 'f6100000-0000-4000-8000-000000000004', 'Synthetic Icons Staff B');
INSERT INTO public.patients (id, clinic_id, auth_user_id, clinic_label) VALUES
('f6100000-0000-4000-8000-000000000007', 'f6100000-0000-4000-8000-000000000001', 'f6100000-0000-4000-8000-000000000005', 'Synthetic Icons Patient A'), ('f6100000-0000-4000-8000-000000000008', 'f6100000-0000-4000-8000-000000000001', 'f6100000-0000-4000-8000-000000000006', 'Synthetic Icons Patient B');
INSERT INTO public.treatments (id, patient_id, clinic_id) VALUES ('f6100000-0000-4000-8000-000000000009', 'f6100000-0000-4000-8000-000000000007', 'f6100000-0000-4000-8000-000000000001');
INSERT INTO storage.objects (bucket_id, name) VALUES ('action-icons', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'), ('action-icons', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000011/other.png'), ('action-icons', 'f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.png');
INSERT INTO public.action_catalog_items (id, clinic_id, title, status, icon_storage_path) VALUES
('f6100000-0000-4000-8000-000000000010', 'f6100000-0000-4000-8000-000000000001', 'Synthetic icon action', 'approved', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'),
('f6100000-0000-4000-8000-000000000011', 'f6100000-0000-4000-8000-000000000001', 'Synthetic unassigned action', 'approved', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000011/other.png'),
('f6100000-0000-4000-8000-000000000012', 'f6100000-0000-4000-8000-000000000002', 'Synthetic foreign action', 'approved', 'f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.png');
INSERT INTO public.action_assignments (treatment_id, clinic_id, catalog_item_id, title, start_date, end_date)
VALUES ('f6100000-0000-4000-8000-000000000009', 'f6100000-0000-4000-8000-000000000001', 'f6100000-0000-4000-8000-000000000010', 'Synthetic', CURRENT_DATE, CURRENT_DATE);
SELECT is((SELECT public FROM storage.buckets WHERE id='action-icons'), false, 'bucket is private');
SELECT is((SELECT file_size_limit FROM storage.buckets WHERE id='action-icons'), 2097152::bigint, 'bucket limit is 2 MiB');
SELECT is((SELECT allowed_mime_types FROM storage.buckets WHERE id='action-icons'), ARRAY['image/png','image/webp','image/jpeg'], 'bucket formats');
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000003');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name IN ('f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000011/other.png', 'f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.png')), 2, 'staff sees own clinic only');
SELECT lives_ok($q$INSERT INTO storage.objects (bucket_id,name) VALUES ('action-icons','f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp')$q$, 'staff uploads own action icon');
SELECT throws_ok($q$INSERT INTO storage.objects (bucket_id,name) VALUES ('action-icons','f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/new.png')$q$, '42501', NULL, 'staff cannot upload foreign icon');
SELECT throws_ok($q$INSERT INTO storage.objects (bucket_id,name) VALUES ('action-icons','f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000099/new.png')$q$, '42501', NULL, 'unknown catalog action rejected');
SELECT ok(NOT public.storage_action_icon_writable('f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/../bad.png'), 'malformed path rejected');
SELECT ok(NOT public.storage_action_icon_writable('f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/file.svg'), 'unsupported extension rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23514', NULL, 'empty icon path rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='https://example.com/icon.png' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23514', NULL, 'external URL rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/../bad.png' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23514', NULL, 'traversal rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000011/other.png' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23514', NULL, 'another action icon rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.png' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23514', NULL, 'another clinic icon rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/absent.png' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23503', NULL, 'missing object rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/bad.svg' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23514', NULL, 'unsupported format rejected');
SELECT lives_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, 'staff saves existing own icon');
SELECT is((SELECT status::text FROM public.action_catalog_items WHERE id='f6100000-0000-4000-8000-000000000010'), 'approved', 'icon change preserves approval');
SELECT lives_ok($q$UPDATE public.action_catalog_items SET icon_storage_path=NULL WHERE id='f6100000-0000-4000-8000-000000000010'$q$, 'staff can clear icon');
SELECT lives_ok($q$UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, 'staff restores icon');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET id='f6100000-0000-4000-8000-000000000098' WHERE id='f6100000-0000-4000-8000-000000000011'$q$, '23514', NULL, 'changing action id cannot invalidate icon prefix');
SELECT pg_temp.icon_logout();
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000004');
SELECT is((SELECT count(*)::int FROM public.get_assignment_icons('f6100000-0000-4000-8000-000000000009')), 0, 'RPC denies foreign staff');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name IN ('f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000011/other.png', 'f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.png')), 1, 'other staff sees only other clinic');
SELECT pg_temp.icon_logout();
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000005');
SELECT is((SELECT count(*)::int FROM public.get_assignment_icons('f6100000-0000-4000-8000-000000000009')), 1, 'patient RPC returns own assignment');
SELECT is((SELECT icon_storage_path FROM public.get_assignment_icons('f6100000-0000-4000-8000-000000000009')), 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png', 'RPC returns current icon');
SELECT lives_ok($q$DELETE FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'$q$, 'patient delete filtered');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'), 1, 'patient cannot delete');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name IN ('f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000011/other.png', 'f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.png')), 1, 'patient sees only assigned current icon');
SELECT is((SELECT count(*)::int FROM public.action_catalog_items), 0, 'patient catalog remains private');
SELECT throws_ok($q$INSERT INTO storage.objects (bucket_id,name) VALUES ('action-icons','f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/patient.png')$q$, '42501', NULL, 'patient cannot upload');
SELECT lives_ok($q$UPDATE storage.objects SET name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/changed.png' WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'$q$, 'update has no permission and affects no rows');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'), 1, 'patient cannot modify icon');
SELECT pg_temp.icon_logout();
UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp' WHERE id='f6100000-0000-4000-8000-000000000010';
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000005');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'), 0, 'replaced icon no longer readable by patient');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp'), 1, 'new icon readable without assignment changes');
SELECT pg_temp.icon_logout();
UPDATE public.action_catalog_items SET icon_storage_path=NULL WHERE id='f6100000-0000-4000-8000-000000000010';
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000005');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name LIKE 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/%'), 0, 'removed icon no longer readable');
SELECT pg_temp.icon_logout();
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000006');
SELECT is((SELECT count(*)::int FROM public.get_assignment_icons('f6100000-0000-4000-8000-000000000009')), 0, 'RPC denies other patient');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name IN ('f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png', 'f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000011/other.png', 'f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.png')), 0, 'unassigned patient sees no icons');
SELECT pg_temp.icon_logout();
SELECT ok(NOT has_function_privilege('anon','public.storage_action_icon_readable(text)','EXECUTE'), 'anonymous cannot call read helper');
SET LOCAL ROLE anon;
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons'), 0, 'anonymous sees no icons');
RESET ROLE;
SELECT ok(NOT has_function_privilege('authenticated', 'public.action_catalog_items_validate_icon()', 'EXECUTE'), 'validation trigger is not callable by client');
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000003');
SELECT is((SELECT count(*)::int FROM public.get_assignment_icons('f6100000-0000-4000-8000-000000000009')), 1, 'RPC allows own staff');
SELECT ok((SELECT icon_storage_path IS NULL FROM public.get_assignment_icons('f6100000-0000-4000-8000-000000000009')), 'RPC includes assignments without icon');
SELECT lives_ok($q$DELETE FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'$q$, 'staff deletes unused own icon');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.png'), 0, 'unused icon deleted');
UPDATE public.action_catalog_items SET icon_storage_path='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp' WHERE id='f6100000-0000-4000-8000-000000000010';
SELECT lives_ok($q$DELETE FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp'$q$, 'referenced delete filtered');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp'), 1, 'referenced icon retained');
SELECT pg_temp.icon_logout();
SELECT throws_ok($q$DELETE FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp'$q$, '23503', NULL, 'trigger protects references even for owner');
SELECT pg_temp.icon_login('f6100000-0000-4000-8000-000000000004');
SELECT lives_ok($q$DELETE FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp'$q$, 'foreign delete filtered');
SELECT pg_temp.icon_logout();
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='action-icons' AND name='f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/new.webp'), 1, 'foreign delete retained file');
SELECT ok(NOT has_function_privilege('anon','public.get_assignment_icons(uuid)','EXECUTE'), 'anonymous RPC forbidden');
SELECT * FROM finish();
ROLLBACK;
