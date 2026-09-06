# Clinic review dashboard (TASK-034)

Minimal staff web app in `clinic-review/`. Not a SaaS admin, not a patient portal.

## Local login

Seed staff only:

- email: `staff.synthetic@local.test`
- password: `synthetic-staff-password`

Public signup is disabled (`[auth] enable_signup = false`). The email provider stays enabled so this seeded staff account can sign in. There is no clinic picker.

Browser env (in `clinic-review/.env.local`):

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY` (canonical)
- `VITE_SUPABASE_ANON_KEY` optional fallback only

Never put `service_role` in the dashboard env.

```bash
cd clinic-review
npm install
npm run dev
```

## Routes

- `/login`
- `/patients`
- `/patients/new`
- `/patients/:patientId`
- `/catalog`

## Write paths

Staff writes go through existing RLS plus SECURITY INVOKER RPCs:

- `create_unactivated_patient` — patient + active sclerotherapy treatment + first period
- `assign_catalog_item_to_treatment` — approved catalog only; copies title/instruction
- `start_new_treatment_period` — close current period and open the next in one transaction
- `replace_current_appointment` — supersede current and insert the new wall-clock row
- `issue_patient_invite` / `revoke_patient_invite` — existing TASK-033 RPCs

Disable assignment and mark treatment complete use column-limited table UPDATE.

Doctor milestone photos are metadata-first: insert `doctor_milestone_photos`, then upload the same UUID/path. Retry uses that same row.

## `clinic_label`

Clinic-facing identifier. It may contain personally identifying text. Display it in the dashboard. Do not put it in ProductEvent, QR/invite payload, analytics, or logs.

## Invite / QR

Button «Пригласить пациента» calls `issue_patient_invite` and renders a QR for:

`doctormaslianski://invite/{token}`

The raw token lives only in the open invite panel state. Closing the QR forgets it. It is not written to localStorage, the URL, or the database (Postgres stores `token_hash` only).

Primary device check: copy `doctormaslianski://invite/{token}` and open/tap that URL on the physical iPhone. Camera QR is optional; iOS Camera failing to recognize a non-HTTPS custom-scheme QR is not a TASK-036 blocker.

HTTPS universal links are TASK-037.

## Realtime

The dashboard does not treat Realtime payloads as domain state. Signals only refetch the existing page loaders under RLS.

Patients list subscribes to `patients` INSERT/UPDATE.

Patient detail:

- `patients` UPDATE for the open patient
- `diary_entries` / `patient_photos` / `feedback_surveys` INSERT for the open treatment
- private Broadcast `invalidate` on `treatment:{treatmentId}` for completion mark/undo

There is no `postgres_changes` binding on `action_completions`. «Обновить», tab focus, and visibility refetch stay as recovery fallbacks.

## Manual two-app check

With local Supabase, clinic-review, and the patient app open on the same activated patient:

1. Mark / undo a completion on the phone — dashboard «Сегодня» updates without refresh.
2. Submit diary and upload a patient photo — those sections update.
3. From the dashboard, change an assignment, appointment, period, visit, or visit photo — the open mobile screens update.
4. «Завершить лечение» — mobile tabs disappear and the completed shell appears without reload.
5. Background the phone, change an assignment, foreground — data is current and only one treatment channel exists.

Repeat on iOS Simulator, Android Emulator, and the dashboard browser.
