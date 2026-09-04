# RLS and Storage (TASK-029)

Authorization is enforced in Postgres. Do not rely on frontend filtering.

Helpers are `SECURITY DEFINER` with `search_path = public, pg_temp`. `EXECUTE` is revoked from `PUBLIC` and `anon`, and granted only to `authenticated`.

| Helper | Meaning |
|---|---|
| `current_patient_id()` | caller’s patient row |
| `current_patient_clinic_id()` | caller’s patient clinic |
| `current_staff_clinic_id()` | caller’s staff clinic |
| `is_staff()` | caller has a staff row |
| `patient_belongs_to_clinic(patient_id, clinic_id)` | true only for the caller’s own patient or staff clinic |
| `treatment_in_staff_clinic(treatment_id)` | treatment in caller’s staff clinic |
| `treatment_owned_by_current_patient(treatment_id)` | treatment owned by caller’s patient |

## Policy matrix

| Table | Patient | Staff (same clinic) |
|---|---|---|
| `clinics` | SELECT own clinic | SELECT own clinic |
| `clinic_staff` | none | SELECT own clinic |
| `patients` | SELECT own | SELECT/INSERT (no bind-column UPDATE) |
| `action_catalog_items` | none | SELECT/INSERT/UPDATE |
| `treatments` | SELECT own | SELECT/INSERT/UPDATE except `pilot_cohort` |
| `treatment_periods` | SELECT own treatment | SELECT/INSERT/UPDATE |
| `treatment_milestones` | SELECT own | SELECT/INSERT/UPDATE |
| `action_assignments` | SELECT own | SELECT/INSERT/UPDATE |
| `action_completions` | SELECT/INSERT/DELETE own | SELECT |
| `appointments` | SELECT own | SELECT/INSERT/UPDATE |
| `diary_entries` | SELECT/INSERT own | SELECT |
| `patient_photos` | SELECT/INSERT own | SELECT |
| `doctor_milestone_photos` | SELECT own treatment | SELECT/INSERT |
| `feedback_surveys` | SELECT/INSERT own | SELECT |
| `product_events` | INSERT own ids only | SELECT clinic-scoped; INSERT if derived `clinic_id` matches |
| `patient_invites` | none | SELECT; issue/revoke via RPC |

`anon` has no table privileges.

Patients cannot mark treatment complete: no effective UPDATE on `treatments` plus a trigger that rejects status changes when the caller is a patient.

`patients.auth_user_id`, consent columns, `patients.pilot_cohort`, and `treatments.pilot_cohort` cannot be written by staff, patients, or anon. Bind is `activate_patient_from_invite` (SECURITY DEFINER, EXECUTE granted only to `service_role`). See [invite-links.md](invite-links.md).

`product_events.clinic_id` is set from the patient/treatment row. A client-supplied `clinic_id` is overwritten.

## Storage

Both buckets are **private**. Objects are read with short-lived signed URLs at read time (TASK-032 / clinic review). Do not store public URLs. Do not copy paths into `product_events`.

| Bucket | Path | Insert | Select |
|---|---|---|---|
| `patient-photos` | `{clinic_id}/{patient_id}/{treatment_id}/{yyyy-mm-dd}/{photo_id}.{ext}` | owning patient | owning patient + clinic staff |
| `doctor-milestone-photos` | `{clinic_id}/{treatment_id}/{milestone_id}/{photo_id}.{ext}` | clinic staff | owning patient + clinic staff |

No UPDATE/DELETE policies on clinical photo objects in TASK-029.

Allowed MIME types: `image/jpeg`, `image/png`, `image/heic`, `image/heif`, `image/webp`.
