-- Explicit privileges. anon has no table access. authenticated gets narrow DML; RLS still applies.

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT ON public.clinics TO authenticated;
GRANT SELECT ON public.clinic_staff TO authenticated;

GRANT SELECT, INSERT, UPDATE ON public.patients TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.action_catalog_items TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.treatments TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.treatment_periods TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.treatment_milestones TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.action_assignments TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.action_completions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.appointments TO authenticated;
GRANT SELECT, INSERT ON public.diary_entries TO authenticated;
GRANT SELECT, INSERT ON public.patient_photos TO authenticated;
GRANT SELECT, INSERT ON public.doctor_milestone_photos TO authenticated;
GRANT SELECT, INSERT ON public.feedback_surveys TO authenticated;
GRANT SELECT, INSERT ON public.product_events TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.patient_invites TO authenticated;

GRANT SELECT, INSERT ON storage.objects TO authenticated;
GRANT SELECT ON storage.buckets TO authenticated;

-- Re-apply helper EXECUTE grants after REVOKE ALL ON ALL FUNCTIONS.
GRANT EXECUTE ON FUNCTION public.current_patient_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_patient_clinic_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_staff_clinic_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.patient_belongs_to_clinic(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.treatment_in_staff_clinic(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.treatment_owned_by_current_patient(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_path_parts(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_patient_photo_writable(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_patient_photo_readable(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_doctor_photo_writable(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_doctor_photo_readable(text) TO authenticated;

REVOKE ALL ON FUNCTION public.current_patient_id() FROM anon;
REVOKE ALL ON FUNCTION public.current_patient_clinic_id() FROM anon;
REVOKE ALL ON FUNCTION public.current_staff_clinic_id() FROM anon;
REVOKE ALL ON FUNCTION public.is_staff() FROM anon;
REVOKE ALL ON FUNCTION public.patient_belongs_to_clinic(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.treatment_in_staff_clinic(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.treatment_owned_by_current_patient(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.storage_path_parts(text) FROM anon;
REVOKE ALL ON FUNCTION public.storage_patient_photo_writable(text) FROM anon;
REVOKE ALL ON FUNCTION public.storage_patient_photo_readable(text) FROM anon;
REVOKE ALL ON FUNCTION public.storage_doctor_photo_writable(text) FROM anon;
REVOKE ALL ON FUNCTION public.storage_doctor_photo_readable(text) FROM anon;
