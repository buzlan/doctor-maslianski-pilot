# Schema contract (TASK-029)

Postgres is the source of truth for the Pilot MVP. This document is the contract for later mobile (TASK-030/031) and clinic review (TASK-034) work.

This is not a legal or compliance approval.

## Treatment context

One context: `sclerotherapy`. There is no protocol snapshot, no telangiectasia path, and no protocol-version table.

## Civil dates

Assignment ranges, Day N, diary, and patient photos use Postgres `date` (no timezone). Day N is not stored; it is `1 + (on_date - period.started_on)`.

TASK-031 should compute “today” in `clinics.time_zone`, not the device zone.

## Appointment datetime

Each appointment stores:

- `wall_clock` — timestamp without time zone (doctor-intended local date/time; display source)
- `time_zone` — IANA name copied from the clinic at insert
- `at_utc` — instant for ordering only

Mobile `Appointment.at` must be serialized from `wall_clock` (optionally with the clinic offset). Do not emit a UTC `Z` string that would change the displayed wall-clock time.

A change supersedes the current row and inserts a new `current` row. There is at most one `current` appointment per treatment.

## Enums

| Enum | Values |
|---|---|
| `pilot_cohort` | `internal_dry_run`, `closed_beta`, `clinic_pilot` |
| `treatment_status` | `active`, `completed`, `cancelled` |
| `assignment_status` | `active`, `disabled` |
| `appointment_record_status` | `current`, `superseded` |
| `catalog_item_status` | `draft`, `approved` |
| `wellbeing` | `better`, `unchanged`, `worse` |
| `invite_status` | `pending`, `consumed`, `revoked`, `expired` |
| `staff_role` | `staff` |

## Tables

| Table | Notes |
|---|---|
| `clinics` | `time_zone`, optional contact fields |
| `clinic_staff` | `auth_user_id` required |
| `patients` | `clinic_label` required (1–120 trimmed chars, clinic-facing, may be identifying). `auth_user_id` nullable until invite activation; consent timestamps + `consent_document_version`. Bind columns are activation-RPC only. Never put `clinic_label` in ProductEvent, QR, analytics, or logs. |
| `action_catalog_items` | `title` required, `instruction` nullable. Editing title/instruction on an `approved` row forces `draft`. |
| `treatments` | one `active` per patient; `clinic_id` copied from patient |
| `treatment_periods` | current period is `ended_on IS NULL`. Clinic transition is `start_new_treatment_period`. |
| `treatment_milestones` | clinic `title`; optional `kind` (no clinical enum) |
| `action_assignments` | copied `title`; copied `instruction` (nullable). Insert copies approved catalog wording; title/instruction/`catalog_item_id` are immutable after insert. |
| `action_completions` | unique `(assignment_id, completed_on)` |
| `appointments` | see datetime section. Clinic replacement is `replace_current_appointment`. |
| `diary_entries` | unique `(treatment_id, submitted_on)`; VAS 0–10; wellbeing enum; immutable |
| `patient_photos` | unique `(treatment_id, submitted_on, slot)` slot 1–3 |
| `doctor_milestone_photos` | attached to a milestone |
| `feedback_surveys` | both scores `NOT NULL` 1–5; treatment must be `completed` |
| `product_events` | analytics only; `clinic_id` derived; no jsonb |
| `patient_invites` | `token_hash` only; no medical columns. Issue/revoke/consume are RPCs. Pending TTL default 7 days. Recovery remint window is 15 minutes after `consumed_at`. |

## ProductEvent allowlist

Columns: `name`, `occurred_at`, `pilot_cohort`, `clinic_id`, `patient_id`, `treatment_id`, `entity_id`, `usefulness_score`, `clarity_score`.

`feedback_submitted` requires both scores 1–5. Other names must have both scores null.

Do not store diary answers, free text, photo paths/URLs, instructions, diagnoses, or `protocol_kind` / `protocol_version`.

## Integrity

Triggers reject (or overwrite `clinic_id` from the parent) when denormalized ids do not match. Diary and patient photos additionally require `treatments.status = active`. Completions require an active, in-range assignment. Patients cannot change `treatments.status`.

Assignment insert requires an `approved` catalog item and overwrites title/instruction from that row. Catalog wording edits on approved items force `draft` and do not rewrite existing assignments.

Clinic write RPCs (SECURITY INVOKER, staff-only): `create_unactivated_patient`, `assign_catalog_item_to_treatment`, `start_new_treatment_period`, `replace_current_appointment`. EXECUTE is granted to `authenticated` only. RLS remains authoritative.
