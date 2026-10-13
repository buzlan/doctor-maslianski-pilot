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
| `can_subscribe_treatment_topic(topic)` | true when topic is `treatment:{uuid}` and the caller may SELECT that treatment |

## Policy matrix

| Table | Patient | Staff (same clinic) |
|---|---|---|
| `clinics` | SELECT own clinic | SELECT own clinic |
| `clinic_staff` | none | SELECT own clinic |
| `patients` | SELECT own | SELECT/INSERT; UPDATE `clinic_label` and `is_test` only (no bind-column UPDATE). Purge is `delete_patient`, not a table DELETE. |
| `storage.objects` `patient-photos`, `doctor-milestone-photos` | existing read/write rules | DELETE own clinic prefix, used when purging a patient |
| `action_catalog_items` | none | SELECT/INSERT/UPDATE. Removal is `delete_catalog_item`, which also deletes that item's assignments and completions. |
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

Staff may UPDATE only `patients.clinic_label` and `patients.updated_at`.

TASK-034 SECURITY INVOKER RPCs (`create_unactivated_patient`, `assign_catalog_item_to_treatment`, `start_new_treatment_period`, `replace_current_appointment`): EXECUTE revoked from `PUBLIC` and `anon`, granted to `authenticated`. Each fails when `current_staff_clinic_id()` is absent. They do not bypass RLS.

Draft catalog items cannot be assigned: the assign RPC and a BEFORE INSERT trigger both require `approved` and copy catalog wording.

`product_events.clinic_id` is set from the patient/treatment row. A client-supplied `clinic_id` is overwritten.

## Storage

All buckets are **private**. Objects are read with short-lived signed URLs at read time (TASK-032 / clinic review). Do not store public URLs. Do not copy paths into `product_events`.

`action-icons` is reserved for catalog action icons: PNG, WebP, or JPEG, up to
2 MiB (2,097,152 bytes) per file. Its bucket configuration is introduced by
`20261006140000_action_icons_bucket.sql`. The access policies in
`20261006142000_action_icons_access.sql` use object paths
`{clinic_id}/{catalog_item_id}/{unique_file_name}.{ext}`. Staff may insert and
read icons only for existing catalog actions in their own clinic. After
`delete_catalog_item` clears the reference, staff may delete that unused object
in their clinic prefix. Patients may
read only the current catalog icon of an action assigned to their own treatment.
Changing or clearing `icon_storage_path` changes patient access without rewriting
assignments. Catalog table access itself remains staff-only.

`20261006143000_catalog_icon_validation.sql` validates catalog icon references
on INSERT and on updates of the icon path, clinic, or action ID. Non-null paths
must match the action and clinic, use a supported extension, and reference an
existing object in `action-icons`. NULL clears the icon. Create the catalog
action first without an icon, upload the file, then save its path. Changing only
the icon preserves catalog approval.

`20261006144000_action_icons_delete_and_patient_read.sql` permits staff to
DELETE unused icons of their own clinic. A trigger protects referenced objects,
including privileged deletes. Reference validation locks the object with KEY
SHARE; deletion locks that row, protecting against simultaneous saves/deletes.
No UPDATE policy is provided: replacements always upload to a new path.
Delete actual files through the Storage API, never direct SQL.

`get_assignment_icons(p_treatment_id)` returns `assignment_id` and nullable
`icon_storage_path` for the caller's own treatment or staff clinic. Catalog table
access stays staff-only. Fetch this RPC on screen refresh, then obtain short-lived
signed URLs from `action-icons`; do not persist signed URLs as catalog data.

| Bucket | Path | Insert | Select |
|---|---|---|---|
| `patient-photos` | `{clinic_id}/{patient_id}/{treatment_id}/{yyyy-mm-dd}/{photo_id}.{ext}` | owning patient | owning patient + clinic staff |
| `doctor-milestone-photos` | `{clinic_id}/{treatment_id}/{milestone_id}/{photo_id}.{ext}` | clinic staff | owning patient + clinic staff |

No UPDATE/DELETE policies on clinical photo objects in TASK-029.

## Realtime

Realtime is notification-only. Canonical reads still go through the table policies above.

Postgres Changes is published for: `patients`, `diary_entries`, `patient_photos`, `feedback_surveys`, `treatments`, `treatment_periods`, `action_assignments`, `appointments`, `treatment_milestones`, `doctor_milestone_photos`.

`action_completions` is not published. Postgres Changes does not apply RLS to DELETE. Completions notify via private Broadcast (`realtime.send`) on topic `treatment:{treatmentId}` with `{ "hint": "action_completions" }` only. Subscribe is authorized by `realtime.messages` SELECT plus `can_subscribe_treatment_topic`. Clients cannot INSERT on that topic.

Realtime filters are traffic scoping, not authorization.

Allowed MIME types: `image/jpeg`, `image/png`, `image/heic`, `image/heif`, `image/webp`.
