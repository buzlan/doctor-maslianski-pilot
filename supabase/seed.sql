-- SYNTHETIC / NOT CLINICAL / NOT REAL PATIENTS
-- Development seed only. Do not copy into production. Do not invent medical instructions.

INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token,
  is_sso_user,
  is_anonymous
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-4000-8000-000000000010',
  'authenticated',
  'authenticated',
  'staff.synthetic@local.test',
  extensions.crypt('synthetic-staff-password', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{}',
  now(),
  now(),
  '',
  '',
  '',
  '',
  false,
  false
);

INSERT INTO auth.identities (
  id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at,
  provider_id
) VALUES (
  '10000000-0000-4000-8000-000000000019',
  '10000000-0000-4000-8000-000000000010',
  jsonb_build_object(
    'sub', '10000000-0000-4000-8000-000000000010',
    'email', 'staff.synthetic@local.test'
  ),
  'email',
  now(),
  now(),
  now(),
  '10000000-0000-4000-8000-000000000010'
);

INSERT INTO public.clinics (id, name, time_zone, phone, email, booking_url)
VALUES (
  '10000000-0000-4000-8000-000000000001',
  'Synthetic Pilot Clinic',
  'Europe/Minsk',
  NULL,
  NULL,
  NULL
);

INSERT INTO public.clinic_staff (id, clinic_id, auth_user_id, role, display_name)
VALUES (
  '10000000-0000-4000-8000-000000000011',
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000010',
  'staff',
  'Synthetic Staff'
);

INSERT INTO public.patients (id, clinic_id, clinic_label, auth_user_id, pilot_cohort)
VALUES (
  '10000000-0000-4000-8000-000000000020',
  '10000000-0000-4000-8000-000000000001',
  'Synthetic Patient',
  NULL,
  NULL
);

INSERT INTO public.treatments (
  id,
  patient_id,
  clinic_id,
  treatment_context,
  status
) VALUES (
  '10000000-0000-4000-8000-000000000021',
  '10000000-0000-4000-8000-000000000020',
  '10000000-0000-4000-8000-000000000001',
  'sclerotherapy',
  'active'
);

INSERT INTO public.treatment_periods (id, treatment_id, clinic_id, started_on, ended_on)
VALUES (
  '10000000-0000-4000-8000-000000000022',
  '10000000-0000-4000-8000-000000000021',
  '10000000-0000-4000-8000-000000000001',
  DATE '2026-08-19',
  NULL
);
