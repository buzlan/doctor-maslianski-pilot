export const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

export type IssuedInvite = {
  inviteId: string;
  expiresAt: string;
  token: string;
};

export const PATIENT_INVITE_ORIGIN = 'https://app.maslianski.by';

export function inviteUrlFromToken(token: string): string | null {
  if (!INVITE_TOKEN_PATTERN.test(token)) {
    return null;
  }
  return `${PATIENT_INVITE_ORIGIN}/invite/${token}`;
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

export function isPatientInviteUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    if (parsed.origin !== PATIENT_INVITE_ORIGIN) {
      return false;
    }
    const parts = parsed.pathname.split('/').filter((part) => part.length > 0);
    const token = parts[1];
    return (
      parts.length === 2 &&
      parts[0] === 'invite' &&
      token !== undefined &&
      INVITE_TOKEN_PATTERN.test(token)
    );
  } catch {
    return false;
  }
}

export async function copyInviteUrl(
  writeText: ClipboardWriteText,
  url: string,
): Promise<'copied' | 'failed'> {
  if (!isPatientInviteUrl(url)) {
    return 'failed';
  }

  try {
    await writeText(url);
    return 'copied';
  } catch {
    return 'failed';
  }
}
