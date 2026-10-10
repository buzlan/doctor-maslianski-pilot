import { withSupabase } from 'npm:@supabase/server';

import { applyInviteCors, inviteOptionsResponse } from '../consume-patient-invite/cors.ts';
import { HANDOFF_TOKEN_RE, sha256Hex } from '../_shared/handoff-token.ts';

const NO_STORE = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json',
} as const;

type ConsumeError = 'invalid' | 'expired' | 'consumed' | 'unusable';

type AdminClient = {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
  auth: {
    admin: {
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

function asRow(data: unknown): { outcome: string; auth_user_id: string | null } | null {
  const row = Array.isArray(data) ? data[0] : data;
  if (row === null || typeof row !== 'object') {
    return null;
  }
  const record = row as { outcome?: unknown; auth_user_id?: unknown };
  if (typeof record.outcome !== 'string') {
    return null;
  }
  return {
    outcome: record.outcome,
    auth_user_id: typeof record.auth_user_id === 'string' ? record.auth_user_id : null,
  };
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

async function sessionForExistingUser(
  admin: AdminClient,
  userId: string,
): Promise<{ access_token: string; refresh_token: string } | null> {
  const { data, error } = await admin.auth.admin.getUserById(userId);
  if (error || data.user === null || typeof data.user.email !== 'string' || data.user.email.length === 0) {
    return null;
  }
  return mintSession(admin, data.user.email);
}

const consumeHandoff = withSupabase({ auth: 'publishable' }, async (req, ctx) => {
  if (req.method !== 'POST') {
    return fail('unusable', 405);
  }

  let body: { token?: unknown };
  try {
    body = (await req.json()) as { token?: unknown };
  } catch {
    return fail('invalid');
  }

  const token = typeof body.token === 'string' ? body.token.trim() : '';
  if (!HANDOFF_TOKEN_RE.test(token)) {
    return fail('invalid');
  }

  const admin = ctx.supabaseAdmin as unknown as AdminClient;
  const { data, error } = await admin.rpc('consume_web_session_handoff', {
    p_token_hash_hex: await sha256Hex(token),
  });
  if (error) {
    return fail('unusable', 500);
  }

  const row = asRow(data);
  if (row === null) {
    return fail('invalid');
  }
  if (row.outcome === 'expired' || row.outcome === 'consumed' || row.outcome === 'invalid') {
    return fail(row.outcome);
  }
  if (row.outcome !== 'ok' || row.auth_user_id === null) {
    return fail('unusable', 500);
  }

  const session = await sessionForExistingUser(admin, row.auth_user_id);
  if (session === null) {
    return fail('unusable', 500);
  }
  return json(session);
});

export default {
  async fetch(req: Request): Promise<Response> {
    const origin = req.headers.get('Origin');
    if (req.method === 'OPTIONS') {
      return inviteOptionsResponse(origin);
    }

    const response = await consumeHandoff(req);
    return applyInviteCors(response, origin);
  },
};
