#!/usr/bin/env node

/**
 * Local/operator helper for TASK-033. Not the clinic dashboard (TASK-034).
 *
 * Prints a one-time invite URL. The raw token is shown once to stdout.
 * Do not commit the output. Do not log it elsewhere.
 *
 * Usage:
 *   node scripts/issue-invite.mjs \
 *     --treatment 10000000-0000-4000-8000-000000000021 \
 *     --cohort internal_dry_run
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const DEFAULT_TREATMENT = '10000000-0000-4000-8000-000000000021';
const DEFAULT_COHORT = 'internal_dry_run';
const DEFAULT_TTL_DAYS = 7;

function argValue(flag, fallback) {
  const index = process.argv.indexOf(flag);
  if (index === -1 || process.argv[index + 1] === undefined) {
    return fallback;
  }
  return process.argv[index + 1];
}

function readDotEnv(path) {
  try {
    const text = readFileSync(path, 'utf8');
    for (const line of text.split('\n')) {
      const trimmed = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }
      const eq = trimmed.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key = trimmed.slice(0, eq).trim();
      const value = trimmed.slice(eq + 1).trim();
      if (process.env[key] === undefined) {
        process.env[key] = value;
      }
    }
  } catch {
    // .env is optional; supabase status values may already be exported.
  }
}

readDotEnv(resolve(process.cwd(), '.env'));

const url = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const anonKey =
  process.env.SUPABASE_ANON_KEY ?? process.env.SUPABASE_PUBLISHABLE_KEY ?? '';
const treatmentId = argValue('--treatment', DEFAULT_TREATMENT);
const cohort = argValue('--cohort', DEFAULT_COHORT);
const ttlDays = Number(argValue('--ttl-days', String(DEFAULT_TTL_DAYS)));
const staffEmail = argValue('--email', 'staff.synthetic@local.test');
const staffPassword = argValue('--password', 'synthetic-staff-password');

if (anonKey.length === 0) {
  console.error('Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY');
  process.exit(1);
}

const headers = {
  apikey: anonKey,
  Authorization: `Bearer ${anonKey}`,
  'Content-Type': 'application/json',
};

const sessionResponse = await fetch(`${url}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers,
  body: JSON.stringify({ email: staffEmail, password: staffPassword }),
});

if (!sessionResponse.ok) {
  console.error('Staff sign-in failed');
  process.exit(1);
}

const session = await sessionResponse.json();
const accessToken = session.access_token;
if (typeof accessToken !== 'string' || accessToken.length === 0) {
  console.error('Staff sign-in failed');
  process.exit(1);
}

const issueResponse = await fetch(`${url}/rest/v1/rpc/issue_patient_invite`, {
  method: 'POST',
  headers: {
    apikey: anonKey,
    Authorization: `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    p_treatment_id: treatmentId,
    p_pilot_cohort: cohort,
    p_ttl_days: ttlDays,
  }),
});

if (!issueResponse.ok) {
  console.error('issue_patient_invite failed');
  process.exit(1);
}

const issued = await issueResponse.json();
const token = issued?.token;
if (typeof token !== 'string' || token.length === 0) {
  console.error('issue_patient_invite returned no token');
  process.exit(1);
}

const link = `doctormaslianski://invite/${token}`;
process.stdout.write(`${link}\n`);
process.stdout.write(`expires_at=${issued.expires_at}\n`);
process.stdout.write(`invite_id=${issued.invite_id}\n`);
