-- Appointments: clinic wall-clock is the display source; at_utc is for ordering only.

CREATE TABLE public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  treatment_id uuid NOT NULL REFERENCES public.treatments (id),
  clinic_id uuid NOT NULL REFERENCES public.clinics (id),
  status public.appointment_record_status NOT NULL,
  wall_clock timestamp WITHOUT TIME ZONE NOT NULL,
  time_zone text NOT NULL,
  at_utc timestamptz NOT NULL,
  superseded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX appointments_treatment_id_idx ON public.appointments (treatment_id);
CREATE INDEX appointments_clinic_id_idx ON public.appointments (clinic_id);
CREATE INDEX appointments_at_utc_idx ON public.appointments (at_utc);

CREATE UNIQUE INDEX appointments_one_current
  ON public.appointments (treatment_id)
  WHERE status = 'current';

CREATE TRIGGER appointments_set_updated_at
  BEFORE UPDATE ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER appointments_apply_parent
  BEFORE INSERT OR UPDATE ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_treatment_parent();

CREATE OR REPLACE FUNCTION public.appointments_normalize_datetime()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  clinic_tz text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT c.time_zone INTO clinic_tz
    FROM public.clinics c
    WHERE c.id = NEW.clinic_id;

    IF clinic_tz IS NULL THEN
      RAISE EXCEPTION 'integrity: clinic timezone missing'
        USING ERRCODE = '23514';
    END IF;

    NEW.time_zone := clinic_tz;
    NEW.at_utc := NEW.wall_clock AT TIME ZONE NEW.time_zone;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.wall_clock := OLD.wall_clock;
    NEW.time_zone := OLD.time_zone;
    NEW.at_utc := OLD.at_utc;
    NEW.treatment_id := OLD.treatment_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER appointments_normalize_datetime
  BEFORE INSERT OR UPDATE ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION public.appointments_normalize_datetime();

REVOKE ALL ON FUNCTION public.appointments_normalize_datetime() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.appointments_normalize_datetime() FROM anon, authenticated;
