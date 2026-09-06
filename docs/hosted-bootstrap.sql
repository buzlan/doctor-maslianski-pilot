-- SYNTHETIC / NOT CLINICAL / NOT REAL PATIENTS
-- Hosted Pilot clinic row only. Run after `npx supabase db push` on an empty project.
-- Create the staff Auth user in the Dashboard first, then insert clinic_staff
-- with that auth.users.id (see docs/hosted-pilot.md).

INSERT INTO public.clinics (id, name, time_zone, phone, email, booking_url)
VALUES (
  '20000000-0000-4000-8000-000000000001',
  'Synthetic Pilot Clinic',
  'Europe/Minsk',
  NULL,
  NULL,
  NULL
);
