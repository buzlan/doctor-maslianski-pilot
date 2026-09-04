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

## Seed

Synthetic only. Not clinical content. Not real patients.

- Clinic: `Synthetic Pilot Clinic`, `time_zone = Europe/Minsk`, empty contact
- Staff: `staff.synthetic@local.test` / `synthetic-staff-password`
- One unactivated patient (`auth_user_id` null) with an active sclerotherapy treatment and one open period starting `2026-08-19`
- Empty action catalog

## Notes

Realtime is disabled in `config.toml`.

`auto_expose_new_tables` is false; table access uses explicit GRANTs plus RLS.
