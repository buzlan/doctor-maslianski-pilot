BEGIN;

SELECT * FROM no_plan();

SELECT is(
  (
    SELECT count(*)::int
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
  ),
  10,
  'exactly 10 public tables are in supabase_realtime'
);

SELECT set_eq(
  $$
    SELECT tablename
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
  $$,
  ARRAY[
    'patients',
    'diary_entries',
    'patient_photos',
    'feedback_surveys',
    'treatments',
    'treatment_periods',
    'action_assignments',
    'appointments',
    'treatment_milestones',
    'doctor_milestone_photos'
  ],
  'published tables match the intended invalidation set'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename IN ('action_completions', 'product_events', 'patient_invites')
  ),
  'action_completions, product_events, and patient_invites are not published'
);

SELECT is(
  (
    SELECT c.relreplident
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'action_assignments'
  ),
  'f',
  'action_assignments replica identity is FULL'
);

SELECT is(
  (
    SELECT c.relreplident
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'appointments'
  ),
  'f',
  'appointments replica identity is FULL'
);

SELECT is(
  (
    SELECT c.relreplident
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'treatment_periods'
  ),
  'f',
  'treatment_periods replica identity is FULL'
);

SELECT is(
  (
    SELECT c.relreplident
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'action_completions'
  ),
  'd',
  'action_completions replica identity stays DEFAULT'
);

SELECT is(
  (
    SELECT c.relreplident
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'patients'
  ),
  'd',
  'patients replica identity stays DEFAULT'
);

SELECT is(
  (
    SELECT c.relreplident
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'treatments'
  ),
  'd',
  'treatments replica identity stays DEFAULT'
);

SELECT * FROM finish();
ROLLBACK;
