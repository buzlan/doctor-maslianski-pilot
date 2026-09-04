# Invite links (TASK-033)

Clinic-issued access. The QR / link contains **only** an opaque invite token. It must not contain patient id, treatment id, name, diagnosis, assignments, appointment, photo URLs, or other medical data.

This is not the clinic dashboard (TASK-034).

## URL shape

| Environment | URL |
|---|---|
| MVP / Expo / local | `doctormaslianski://invite/{token}` |
| Future store (not implemented here) | `https://app.maslianski.by/invite/{token}` |

The token is 32 random bytes, unpadded base64url. Postgres stores **only** `digest(convert_to(token, 'UTF8'), 'sha256')`.

## Constants

| Name | Value |
|---|---|
| `INVITE_TTL_DEFAULT_DAYS` | 7 |
| `INVITE_TTL_MIN_DAYS` | 1 |
| `INVITE_TTL_MAX_DAYS` | 30 |
| `INVITE_RECOVERY_WINDOW_MINUTES` | 15 |
| `PILOT_CONSENT_DOCUMENT_VERSION` | `pilot-v0` |

Pending unused invites expire after the TTL. After first successful consume, the token is not a standing session credential. Lost-response remint is allowed only until `consumed_at + 15 minutes`. After that, the persisted Auth refresh session is the patient’s access. A copied QR must not mint days later.

## Issue

Authenticated clinic staff call `issue_patient_invite(treatment_id, cohort, ttl_days)`.

Local helper (prints the URL once; do not commit the output):

```bash
node scripts/issue-invite.mjs \
  --treatment 10000000-0000-4000-8000-000000000021 \
  --cohort internal_dry_run
```

## Consume

`consume-patient-invite` is called **before** the patient has a user session.

- `verify_jwt = false`
- `@supabase/server` `auth: 'publishable'`
- The publishable key is the allowed low-privilege **project API credential**. It is public and extractable from a client bundle. It is **not** proof that the caller is the official Doctor Maslianski app.
- The opaque invite token is the activation capability.

Session minting (server only, no patient password stored):

1. `auth.admin.createUser({ email: u.{uuid}@users.invalid, email_confirm: true })`
2. `auth.admin.generateLink({ type: 'magiclink', email })` — does not send mail
3. `auth.verifyOtp({ token_hash, type: 'email' })`

Responses that include session credentials use `Cache-Control: no-store`. Do not log `access_token`, `refresh_token`, the raw invite token, or `Authorization` / `apikey` headers.

## Bind

`patients.auth_user_id`, consent columns, and bind-time `pilot_cohort` are written only by `activate_patient_from_invite` (SECURITY DEFINER, `EXECUTE` granted only to `service_role`). Staff, patients, and anon cannot UPDATE those columns. Column privileges and a bind trigger deny direct DML; a GUC is not the authorization boundary.
