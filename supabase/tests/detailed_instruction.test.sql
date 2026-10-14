BEGIN;
-- Synthetic metadata only, rolled back. Match the flag set by Storage API.
SET LOCAL storage.allow_delete_query = 'true';
SELECT * FROM no_plan();
CREATE FUNCTION pg_temp.instruction_login(uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END; $$;
CREATE FUNCTION pg_temp.instruction_logout() RETURNS void LANGUAGE plpgsql AS $$
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
SELECT ok(public.valid_detailed_instruction(NULL), 'instruction optional');
SELECT ok(NOT public.valid_detailed_instruction('{"heading":"","text":"","photo_paths":[]}'), 'empty object rejected; use null');
SELECT ok(NOT public.valid_detailed_instruction('{"heading":null,"text":"x","photo_paths":[]}'), 'invalid heading rejected');
SELECT ok(NOT public.valid_detailed_instruction('{"heading":"","text":"x","photo_paths":[1]}'), 'non-string path rejected');
SELECT is((SELECT public FROM storage.buckets WHERE id='instruction-photos'), false, 'private photos');
SELECT pg_temp.instruction_login('f6100000-0000-4000-8000-000000000003');
SELECT lives_ok($q$INSERT INTO storage.objects(bucket_id,name) VALUES ('instruction-photos','f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.jpg')$q$, 'staff uploads own photo');
SELECT throws_ok($q$INSERT INTO storage.objects(bucket_id,name) VALUES ('instruction-photos','f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.jpg')$q$, '42501', NULL, 'cross-clinic upload denied');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET detailed_instruction='{"heading":"","text":"test","photo_paths":["f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/missing.jpg"]}' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23503', NULL, 'missing photo rejected');
SELECT throws_ok($q$UPDATE public.action_catalog_items SET detailed_instruction='{"heading":"","text":"test","photo_paths":["f6100000-0000-4000-8000-000000000002/f6100000-0000-4000-8000-000000000012/foreign.jpg"]}' WHERE id='f6100000-0000-4000-8000-000000000010'$q$, '23514', NULL, 'cross-clinic reference rejected');
UPDATE public.action_catalog_items SET detailed_instruction='{"heading":"Heading","text":"Long plain text","photo_paths":["f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/one.jpg"]}' WHERE id='f6100000-0000-4000-8000-000000000010';
SELECT is((SELECT status::text FROM public.action_catalog_items WHERE id='f6100000-0000-4000-8000-000000000010'), 'draft', 'instruction changes require reapproval');
SELECT ok((SELECT detailed_instruction IS NULL FROM public.action_assignments WHERE catalog_item_id='f6100000-0000-4000-8000-000000000010'), 'existing assignment unchanged');
UPDATE public.action_catalog_items SET status='approved' WHERE id='f6100000-0000-4000-8000-000000000010';
SELECT public.assign_catalog_item_to_treatment('f6100000-0000-4000-8000-000000000009','f6100000-0000-4000-8000-000000000010',CURRENT_DATE,CURRENT_DATE);
SELECT is((SELECT count(*)::int FROM public.action_assignments WHERE detailed_instruction->>'heading'='Heading'), 1, 'RPC copies instruction snapshot');
SELECT throws_ok($q$UPDATE public.action_assignments SET detailed_instruction=NULL WHERE detailed_instruction IS NOT NULL$q$, '42501', NULL, 'snapshot immutable');
UPDATE public.action_catalog_items SET detailed_instruction=NULL WHERE id='f6100000-0000-4000-8000-000000000010';
SELECT is((SELECT count(*)::int FROM public.action_assignments WHERE detailed_instruction->>'heading'='Heading'), 1, 'catalog removal preserves snapshot');
DELETE FROM storage.objects WHERE bucket_id='instruction-photos';
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='instruction-photos'), 1, 'snapshot protects old photo from staff deletion');
SELECT pg_temp.instruction_logout();
SELECT throws_ok($q$DELETE FROM storage.objects WHERE bucket_id='instruction-photos'$q$, '23503', NULL, 'delete trigger protects snapshot for owner');
SELECT pg_temp.instruction_login('f6100000-0000-4000-8000-000000000005');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='instruction-photos'), 1, 'assigned patient reads snapshot photo');
SELECT throws_ok($q$INSERT INTO storage.objects(bucket_id,name) VALUES ('instruction-photos','f6100000-0000-4000-8000-000000000001/f6100000-0000-4000-8000-000000000010/patient.jpg')$q$, '42501', NULL, 'patient cannot upload');
SELECT pg_temp.instruction_logout();
SELECT pg_temp.instruction_login('f6100000-0000-4000-8000-000000000006');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='instruction-photos'), 0, 'other patient cannot read photos');
SELECT pg_temp.instruction_logout();
SELECT pg_temp.instruction_login('f6100000-0000-4000-8000-000000000004');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='instruction-photos'), 0, 'other clinic cannot read photos');
SELECT pg_temp.instruction_logout();
SELECT pg_temp.instruction_login('f6100000-0000-4000-8000-000000000003');
SELECT public.delete_catalog_item('f6100000-0000-4000-8000-000000000010');
SELECT lives_ok($q$DELETE FROM storage.objects WHERE bucket_id='instruction-photos'$q$, 'staff cleans photos after catalog purge');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='instruction-photos'), 0, 'unreferenced photo removed');
SELECT pg_temp.instruction_logout();
SELECT ok(NOT has_function_privilege('anon','public.instruction_photo_access(text,text)','EXECUTE'), 'anonymous denied');
SELECT * FROM finish();
ROLLBACK;
