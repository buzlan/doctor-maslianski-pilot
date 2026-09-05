# Local development (TASK-029)

TASK-029 is complete against the local Supabase stack. A hosted project is not required.

Hosted region is **TBD** before any hosted project is created, pending privacy, data-residency, and operational review. Do not treat Frankfurt or any other region as approved in this repository.

## Commands

```bash
npx supabase start
npx supabase db reset
npx supabase db test
npx supabase gen types typescript --local > supabase/generated-db-types.ts
npx supabase status -o env
```

Studio: http://127.0.0.1:54323

API: http://127.0.0.1:54321

Copy local keys into `.env` from `npx supabase status -o env`. Never commit `.env`. Never ship `service_role` in the patient app.

Issue a local invite (prints `doctormaslianski://invite/{token}` once):

```bash
node scripts/issue-invite.mjs --treatment 10000000-0000-4000-8000-000000000021 --cohort internal_dry_run
```

See [invite-links.md](invite-links.md).

## Clinic dashboard (TASK-034)

```bash
cd clinic-review
# copy VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY into .env.local
npm install
npm run dev
```

Open http://127.0.0.1:5173 and sign in as synthetic staff.

`VITE_SUPABASE_PUBLISHABLE_KEY` is the canonical browser key. `VITE_SUPABASE_ANON_KEY` is an optional fallback only. Never put `service_role` in clinic-review env.

See [clinic-review.md](clinic-review.md).

## Seed

Synthetic only. Not clinical content. Not real patients.

- Clinic: `Synthetic Pilot Clinic`, `time_zone = Europe/Minsk`, empty contact
- Staff: `staff.synthetic@local.test` / `synthetic-staff-password` (email provider on; public signup off)
- One unactivated patient (`clinic_label = Synthetic Patient`, `auth_user_id` null) with an active sclerotherapy treatment and one open period starting `2026-08-19`
- Empty action catalog

## Notes

Realtime is enabled in `config.toml`. Restart the local stack after changing that flag (`npx supabase stop` then `npx supabase start`). Then `npx supabase db reset` so the publication and completion Broadcast migrations apply.

Ten public tables are in `supabase_realtime`. `action_completions` is not published; completion INSERT/DELETE emit a private Broadcast hint on `treatment:{treatmentId}`. Filters are not authorization — table RLS still governs canonical reads.

`auto_expose_new_tables` is false; table access uses explicit GRANTs plus RLS.
