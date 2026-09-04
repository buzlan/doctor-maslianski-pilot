import { withSupabase } from 'npm:@supabase/server';

const NO_STORE = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json',
} as const;

const TOKEN_RE = /^[A-Za-z0-9_-]{32,128}$/;

type ConsumeError =
  | 'invalid'
  | 'expired'
  | 'revoked'
  | 'consumed'
  | 'unusable';

type LookupRow = {
  invite_id: string;
  invite_status: 'pending' | 'consumed' | 'revoked' | 'expired';
  expires_at: string;
  consumed_at: string | null;
  bound_auth_user_id: string | null;
  recovery_eligible: boolean;
};

type ActivateRow = {
  outcome: 'activated' | 'not_pending' | 'unusable';
  bound_auth_user_id: string | null;
};

type AdminClient = {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
  auth: {
    admin: {
      createUser(args: {
        email: string;
        email_confirm: boolean;
        password?: string;
      }): Promise<{
        data: { user: { id: string; email?: string | null } | null };
        error: { message: string } | null;
      }>;
      deleteUser(id: string): Promise<{ error: { message: string } | null }>;
      getUserById(id: string): Promise<{
        data: { user: { id: string; email?: string | null } | null };
        error: { message: string } | null;
      }>;
      generateLink(args: { type: 'magiclink'; email: string }): Promise<{
        data: {
          properties: { hashed_token?: string; email_otp?: string };
        } | null;
        error: { message: string } | null;
      }>;
    };
    verifyOtp(args: {
      type: 'email';
      token_hash?: string;
      token?: string;
      email?: string;
    }): Promise<{
      data: {
        session: { access_token: string; refresh_token: string } | null;
      };
      error: { message: string } | null;
    }>;
  };
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: NO_STORE });
}

function fail(error: ConsumeError, status = 400): Response {
  return json({ error }, status);
}

function asLookup(data: unknown): LookupRow | null {
  const row = Array.isArray(data) ? data[0] : data;
  if (row === null || typeof row !== 'object') {
    return null;
  }
  const record = row as Partial<LookupRow>;
  if (typeof record.invite_id !== 'string' || typeof record.invite_status !== 'string') {
    return null;
  }
  return record as LookupRow;
}

function asActivate(data: unknown): ActivateRow | null {
  const row = Array.isArray(data) ? data[0] : data;
  if (row === null || typeof row !== 'object') {
    return null;
  }
  const record = row as Partial<ActivateRow>;
  if (record.outcome !== 'activated' && record.outcome !== 'not_pending' && record.outcome !== 'unusable') {
    return null;
  }
  return {
    outcome: record.outcome,
    bound_auth_user_id:
      typeof record.bound_auth_user_id === 'string' ? record.bound_auth_user_id : null,
  };
}

async function sha256Hex(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

async function lookupInvite(admin: AdminClient, hashHex: string): Promise<LookupRow | null> {
  const { data, error } = await admin.rpc('lookup_patient_invite_by_hash', {
    p_token_hash_hex: hashHex,
  });
  if (error) {
    return null;
  }
  return asLookup(data);
}

async function mintSession(
  admin: AdminClient,
  email: string,
): Promise<{ access_token: string; refresh_token: string } | null> {
  const { data: link, error: linkError } = await admin.auth.admin.generateLink({
    type: 'magiclink',
    email,
  });
  if (linkError || link === null) {
    return null;
  }

  const hashedToken = link.properties.hashed_token;
  if (typeof hashedToken === 'string' && hashedToken.length > 0) {
    const { data, error } = await admin.auth.verifyOtp({
      type: 'email',
      token_hash: hashedToken,
    });
    if (!error && data.session) {
      return {
        access_token: data.session.access_token,
        refresh_token: data.session.refresh_token,
      };
    }
  }

  const emailOtp = link.properties.email_otp;
  if (typeof emailOtp === 'string' && emailOtp.length > 0) {
    const { data, error } = await admin.auth.verifyOtp({
      type: 'email',
      email,
      token: emailOtp,
    });
    if (!error && data.session) {
      return {
        access_token: data.session.access_token,
        refresh_token: data.session.refresh_token,
      };
    }
  }

  return null;
}

async function createAuthUser(admin: AdminClient): Promise<{ id: string; email: string } | null> {
  const email = `u.${crypto.randomUUID()}@users.invalid`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.error && created.data.user?.id) {
    return { id: created.data.user.id, email };
  }

  const ephemeral = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const fallback = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    password: ephemeral,
  });
  if (fallback.error || !fallback.data.user?.id) {
    return null;
  }
  return { id: fallback.data.user.id, email };
}

async function sessionForUser(
  admin: AdminClient,
  userId: string,
  knownEmail?: string,
): Promise<{ access_token: string; refresh_token: string } | null> {
  let email = knownEmail;
  if (email === undefined || email.length === 0) {
    const { data, error } = await admin.auth.admin.getUserById(userId);
    if (error || data.user === null || typeof data.user.email !== 'string') {
      return null;
    }
    email = data.user.email;
  }
  return mintSession(admin, email);
}

export default {
  fetch: withSupabase({ auth: 'publishable' }, async (req, ctx) => {
    // The publishable key is the allowed low-privilege project API credential.
    // It is public and extractable from a client bundle. It does not prove
    // that the caller is the official Doctor Maslianski app.
    // The opaque invite token is the activation capability.
    const admin = ctx.supabaseAdmin as unknown as AdminClient;

    if (req.method !== 'POST') {
      return fail('invalid', 405);
    }

    let body: {
      token?: unknown;
      privacyAccepted?: unknown;
      pilotConsentAccepted?: unknown;
      consentDocumentVersion?: unknown;
    };
    try {
      body = (await req.json()) as typeof body;
    } catch {
      return fail('invalid');
    }

    const token = typeof body.token === 'string' ? body.token.trim() : '';
    if (!TOKEN_RE.test(token)) {
      return fail('invalid');
    }

    const hashHex = await sha256Hex(token);
    const lookup = await lookupInvite(admin, hashHex);
    if (lookup === null) {
      return fail('invalid');
    }

    if (lookup.invite_status === 'expired') {
      return fail('expired');
    }
    if (lookup.invite_status === 'revoked') {
      return fail('revoked');
    }
    if (lookup.invite_status === 'consumed') {
      if (!lookup.recovery_eligible || lookup.bound_auth_user_id === null) {
        return fail('consumed');
      }
      const session = await sessionForUser(admin, lookup.bound_auth_user_id);
      if (session === null) {
        return fail('unusable', 500);
      }
      return json(session);
    }

    if (lookup.invite_status !== 'pending') {
      return fail('unusable');
    }

    const privacyAccepted = body.privacyAccepted === true;
    const pilotConsentAccepted = body.pilotConsentAccepted === true;
    const consentDocumentVersion =
      typeof body.consentDocumentVersion === 'string' ? body.consentDocumentVersion : '';
    if (!privacyAccepted || !pilotConsentAccepted || consentDocumentVersion !== 'pilot-v0') {
      return fail('unusable');
    }

    const created = await createAuthUser(admin);
    if (created === null) {
      return fail('unusable', 500);
    }

    const { data: activateData, error: activateError } = await admin.rpc(
      'activate_patient_from_invite',
      {
        p_token_hash_hex: hashHex,
        p_auth_user_id: created.id,
        p_privacy_accepted: true,
        p_pilot_consent_accepted: true,
        p_consent_document_version: 'pilot-v0',
      },
    );

    if (activateError) {
      await admin.auth.admin.deleteUser(created.id);
      return fail('unusable', 500);
    }

    const activated = asActivate(activateData);
    if (activated === null || activated.outcome === 'unusable') {
      await admin.auth.admin.deleteUser(created.id);
      return fail('unusable');
    }

    if (activated.outcome === 'not_pending') {
      await admin.auth.admin.deleteUser(created.id);
      const retry = await lookupInvite(admin, hashHex);
      if (retry?.invite_status === 'consumed' && retry.recovery_eligible && retry.bound_auth_user_id) {
        const session = await sessionForUser(admin, retry.bound_auth_user_id);
        if (session === null) {
          return fail('unusable', 500);
        }
        return json(session);
      }
      if (retry?.invite_status === 'expired') {
        return fail('expired');
      }
      if (retry?.invite_status === 'revoked') {
        return fail('revoked');
      }
      if (retry?.invite_status === 'consumed') {
        return fail('consumed');
      }
      return fail('unusable');
    }

    const session = await sessionForUser(admin, created.id, created.email);
    if (session === null) {
      return fail('unusable', 500);
    }
    return json(session);
  }),
};
