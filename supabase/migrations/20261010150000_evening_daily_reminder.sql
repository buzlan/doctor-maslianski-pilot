-- Unfinished tasks and a missing diary are reminded at 09:00 and 19:00.
-- The second slot used to be 16:00.

ALTER TABLE public.notification_policy
  ALTER COLUMN afternoon_time SET DEFAULT time '19:00';

UPDATE public.notification_policy
SET
  afternoon_time = time '19:00',
  updated_at = now()
WHERE id = 1;
