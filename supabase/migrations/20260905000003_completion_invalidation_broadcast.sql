-- Private treatment-scoped Broadcast for action_completions INSERT/DELETE.
-- Payload is an invalidation hint only. Canonical rows stay in Postgres.

CREATE OR REPLACE FUNCTION public.can_subscribe_treatment_topic(topic text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  treatment_id uuid;
BEGIN
  IF topic IS NULL OR topic !~ '^treatment:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RETURN false;
  END IF;

  BEGIN
    treatment_id := substring(topic from 11)::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN false;
  END;

  RETURN public.treatment_owned_by_current_patient(treatment_id)
      OR public.treatment_in_staff_clinic(treatment_id);
END;
$$;

REVOKE ALL ON FUNCTION public.can_subscribe_treatment_topic(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_subscribe_treatment_topic(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_subscribe_treatment_topic(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.notify_completion_invalidation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  tid uuid;
BEGIN
  tid := COALESCE(NEW.treatment_id, OLD.treatment_id);
  PERFORM realtime.send(
    jsonb_build_object('hint', 'action_completions'),
    'invalidate',
    'treatment:' || tid::text,
    true
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION public.notify_completion_invalidation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_completion_invalidation() FROM anon;
REVOKE ALL ON FUNCTION public.notify_completion_invalidation() FROM authenticated;

CREATE TRIGGER action_completions_notify_invalidation
  AFTER INSERT OR DELETE ON public.action_completions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_completion_invalidation();

CREATE POLICY treatment_invalidate_broadcast_select
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  realtime.messages.extension = 'broadcast'
  AND public.can_subscribe_treatment_topic(realtime.topic())
);
