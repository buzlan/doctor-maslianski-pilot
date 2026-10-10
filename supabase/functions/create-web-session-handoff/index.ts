import { withSupabase } from 'npm:@supabase/server';

import { applyInviteCors, inviteOptionsResponse } from '../consume-patient-invite/cors.ts';
import { randomHandoffToken, sha256Hex } from '../_shared/handoff-token.ts';

const NO_STORE = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json',
} as const;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: NO_STORE });
}

const createHandoff = withSupabase({ auth: 'user' }, async (req, ctx) => {
  if (req.method !== 'POST') {
    return json({ error: 'unusable' }, 405);
  }

  const userId = ctx.userClaims?.id ?? '';
  if (!UUID_RE.test(userId)) {
    return json({ error: 'unusable' }, 401);
  }

  const token = randomHandoffToken();
  const hash = await sha256Hex(token);
  const { error } = await ctx.supabaseAdmin.rpc('issue_web_session_handoff', {
    p_auth_user_id: userId,
    p_token_hash_hex: hash,
  });

  if (error) {
    return json({ error: 'unusable' }, 403);
  }

  return json({ token });
});

export default {
  async fetch(req: Request): Promise<Response> {
    const origin = req.headers.get('Origin');
    if (req.method === 'OPTIONS') {
      return inviteOptionsResponse(origin);
    }

    const response = await createHandoff(req);
    return applyInviteCors(response, origin);
  },
};
