export const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

export type IssuedInvite = {
  inviteId: string;
  expiresAt: string;
  token: string;
};

export function inviteUrlFromToken(token: string): string | null {
  if (!INVITE_TOKEN_PATTERN.test(token)) {
    return null;
  }
  return `doctormaslianski://invite/${token}`;
}

export function parseIssuedInvite(payload: unknown): IssuedInvite | null {
  if (payload === null || typeof payload !== 'object') {
    return null;
  }

  const record = payload as Record<string, unknown>;
  const inviteId = record.invite_id;
  const expiresAt = record.expires_at;
  const token = record.token;

  if (typeof inviteId !== 'string' || inviteId.length === 0) {
    return null;
  }
  if (typeof expiresAt !== 'string' || expiresAt.length === 0) {
    return null;
  }
  if (typeof token !== 'string' || !INVITE_TOKEN_PATTERN.test(token)) {
    return null;
  }

  return { inviteId, expiresAt, token };
}

export function createInviteState(): IssuedInvite | null {
  return null;
}

export type ClipboardWriteText = (value: string) => Promise<void>;

export async function copyInviteUrl(
  writeText: ClipboardWriteText,
  url: string,
): Promise<'copied' | 'failed'> {
  if (!url.startsWith('doctormaslianski://invite/')) {
    return 'failed';
  }

  try {
    await writeText(url);
    return 'copied';
  } catch {
    return 'failed';
  }
}
