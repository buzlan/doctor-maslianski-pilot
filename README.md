# Doctor Maslianski Pilot — backend

Supabase schema, RLS, private Storage, and (later) clinic-side tooling for the Doctor Maslianski Pilot MVP.

This repository is **not** the React Native patient app. The patient app remains in a sibling repository and keeps using local mocks until later tasks.

## TASK-029 scope

Postgres schema, SQL migrations, RLS, private photo buckets, synthetic seed data, and pgTAP tests.

Not in this task: clinic dashboard, mobile client, photo upload from the phone, push notifications, auth session UI, Realtime, or a production hosted Supabase project.

## Privacy / security

This work is a **secure foundation** for the pilot. It is **not** a legal, privacy, or compliance approval. A hosted region is **TBD** pending privacy, data-residency, and operational review. Do not treat any region as approved yet.

No real patient data belongs in this repository.

## Local development

See [docs/local-development.md](docs/local-development.md).

```bash
npx supabase start
npx supabase db reset
npx supabase db test
npx supabase gen types typescript --local > supabase/generated-db-types.ts
```

Studio (when the stack is running): http://127.0.0.1:54323

## Synthetic seed

Seed data is labelled synthetic. It is not clinical content and not a real patient.

Local staff login (seed only): `staff.synthetic@local.test` / `synthetic-staff-password`

## TASK-033 invite activation

Issue/revoke RPCs, `consume-patient-invite` Edge Function, and hash-only invite storage. See [docs/invite-links.md](docs/invite-links.md).

Not in this task: clinic dashboard (TASK-034).

Local invite URL (do not commit the printed token):

```bash
node scripts/issue-invite.mjs --treatment 10000000-0000-4000-8000-000000000021 --cohort internal_dry_run
```

## Contract docs

- [docs/schema.md](docs/schema.md) — tables, enums, constraints
- [docs/rls-and-storage.md](docs/rls-and-storage.md) — RLS matrix and storage paths
- [docs/invite-links.md](docs/invite-links.md) — invite URL, TTL, consume Auth APIs
