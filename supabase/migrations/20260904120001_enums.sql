-- Enums and shared updated_at helper.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TYPE public.pilot_cohort AS ENUM (
  'internal_dry_run',
  'closed_beta',
  'clinic_pilot'
);

CREATE TYPE public.treatment_status AS ENUM (
  'active',
  'completed',
  'cancelled'
);

CREATE TYPE public.assignment_status AS ENUM (
  'active',
  'disabled'
);

CREATE TYPE public.appointment_record_status AS ENUM (
  'current',
  'superseded'
);

CREATE TYPE public.catalog_item_status AS ENUM (
  'draft',
  'approved'
);

CREATE TYPE public.wellbeing AS ENUM (
  'better',
  'unchanged',
  'worse'
);

CREATE TYPE public.invite_status AS ENUM (
  'pending',
  'consumed',
  'revoked',
  'expired'
);

CREATE TYPE public.staff_role AS ENUM (
  'staff'
);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_updated_at() FROM anon, authenticated;
