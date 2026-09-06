# Hosted Pilot (synthetic verification)

This runbook deploys the local Supabase stack and clinic-review to a **Pilot** project. It does not change product or domain behavior.

Local development remains the default. See [local-development.md](local-development.md).

## Scope

- Hosted Supabase Pilot project
- Deployed clinic-review on Vercel
- Synthetic staff / patients only (`internal_dry_run`)
- No real patient data
- No public App Store release

## Region (this Pilot only)

Chosen at first hosted deploy: **eu-central-1 (Frankfurt)**.

This is an execution choice for the current Pilot project. It is **not** a standing data-residency or privacy decision for real patients. Re-review region before any real-patient Phase 2.

This Pilot project is **Postgres 17.6** in **eu-central-1**.

| Item | Value |
| --- | --- |
| Project ref | `fyfyyjxbcujkpuyfcgjs` |
| Project URL | `https://fyfyyjxbcujkpuyfcgjs.supabase.co` |
| clinic-review | https://doctor-maslianski-clinic-review.vercel.app |
| Synthetic staff email | `staff.synthetic@pilot.test` |
| Staff password | gitignored `.env.hosted` (`HOSTED_STAFF_PASSWORD`) |

Do not commit `.env.hosted`. Do not put `service_role` / `sb_secret_` in Vercel, EAS, or client env.

## Never

- Do not `supabase config push` from local `config.toml` (it would publish `site_url = http://127.0.0.1:3000`).
- Do not put `service_role` / `sb_secret_` in Vercel, EAS, clinic-review, or the mobile app.
- Do not `supabase db reset --linked` after any non-synthetic row exists.
- Do not point hosted clients at `localhost` / `127.0.0.1`.

## Commands

```bash
cd /Users/ihar/doctor-maslianski-pilot
npx supabase login
npx supabase link --project-ref fyfyyjxbcujkpuyfcgjs
npx supabase db push --skip-vault --yes
npx supabase functions deploy consume-patient-invite --no-verify-jwt --use-api --yes
```

This network blocks outbound Postgres `5432`/`6543` (IPv4 pooler timeout; direct host is IPv6-only). First apply used the Management API `POST /v1/projects/{ref}/database/migrations` over HTTPS, then repaired `supabase_migrations.schema_migrations.version` to the local prefixes so a later `db push` does not replay them. Do not `supabase config push`.

## Dashboard after link

Set these in the hosted project. Do not copy them from local `config.toml`.

- Auth: public signup **off**
- Auth: email provider **on**
- Auth: email confirmations **off** (or create a confirmed staff user)
- Auth Site URL + redirect URLs = the Vercel clinic-review origin (update after first deploy)
- Realtime **on**
- Edge Function `consume-patient-invite`: JWT verification **off** (`verify_jwt = false`)

Copy only the Project URL and the **publishable** key into client env. Keep the service_role key in the Dashboard and, if needed, the gitignored operator `.env`.

## Synthetic bootstrap

Preferred path on a new empty project (after `db push`):

1. Create one clinic row in SQL.
2. Create a staff user in Auth (email + password, confirmed). Use a synthetic address such as `staff.synthetic@pilot.test`.
3. Insert `clinic_staff` linking that `auth.users.id` to the clinic.
4. In clinic-review: create a synthetic patient, one catalog item, approve it, assign it, set an appointment, issue invite with `internal_dry_run`.

Optional: run `supabase/seed.sql` **once** on a brand-new empty project if Auth inserts succeed. Seed catalog is empty — still create and approve a catalog item. Never re-apply seed after non-synthetic data exists.

Example clinic + staff link (replace the auth user UUID):

```sql
INSERT INTO public.clinics (id, name, time_zone, phone, email, booking_url)
VALUES (
  '20000000-0000-4000-8000-000000000001',
  'Synthetic Pilot Clinic',
  'Europe/Minsk',
  NULL,
  NULL,
  NULL
);

INSERT INTO public.clinic_staff (id, clinic_id, auth_user_id, role, display_name)
VALUES (
  '20000000-0000-4000-8000-000000000011',
  '20000000-0000-4000-8000-000000000001',
  '<AUTH_USER_UUID>',
  'staff',
  'Synthetic Staff'
);
```

## clinic-review (Vercel)

Deploy from the **repo root** so Vite/tsc can resolve `@db-types` → `supabase/generated-db-types.ts`. Root `vercel.json` builds `clinic-review` and rewrites SPA routes to `index.html`. `.vercelignore` excludes operator env files.

```bash
cd /Users/ihar/doctor-maslianski-pilot
npx vercel login
npx vercel link --yes --project doctor-maslianski-clinic-review
# Vercel Production env (publishable only):
#   VITE_SUPABASE_URL=https://fyfyyjxbcujkpuyfcgjs.supabase.co
#   VITE_SUPABASE_PUBLISHABLE_KEY=<publishable>
npx vercel --prod
```

`clinic-review/.env.local` stays on `127.0.0.1` for local Vite. Do not `vercel env pull` into it.

Auth Site URL + redirects are `https://doctor-maslianski-clinic-review.vercel.app`.

## Invite verification

Primary path: copy `doctormaslianski://invite/{token}` from the dashboard, open/tap it on the physical iPhone, confirm the development build activates the synthetic patient.

Camera QR is optional. iOS Camera failing to open a non-HTTPS custom-scheme QR is not a blocker. HTTPS Universal Links are TASK-037.

## Rollback

- Keep local `npx supabase start` and `clinic-review/.env.local` on `127.0.0.1`.
- Vercel: Instant Rollback to the previous Production deployment.
- Supabase: migrations are append-only. Unlink (`npx supabase unlink`) if abandoning the Pilot project. Pause or delete the hosted project only if it never held real data.
- Rotate the publishable key in Dashboard + Vercel + EAS if it leaked into chat or logs.
