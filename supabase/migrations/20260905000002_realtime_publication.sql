-- Smallest explicit Realtime publication. action_completions is intentionally
-- omitted: Postgres Changes does not apply RLS to DELETE events.

ALTER PUBLICATION supabase_realtime ADD TABLE
  public.patients,
  public.diary_entries,
  public.patient_photos,
  public.feedback_surveys,
  public.treatments,
  public.treatment_periods,
  public.action_assignments,
  public.appointments,
  public.treatment_milestones,
  public.doctor_milestone_photos;

-- UPDATE filters on treatment_id need the old tuple, not PK-only replica identity.
ALTER TABLE public.action_assignments REPLICA IDENTITY FULL;
ALTER TABLE public.appointments REPLICA IDENTITY FULL;
ALTER TABLE public.treatment_periods REPLICA IDENTITY FULL;
