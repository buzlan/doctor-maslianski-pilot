import { describe, expect, it } from 'vitest';

import {
  copyInviteUrl,
  createInviteState,
  inviteUrlFromToken,
  parseIssuedInvite,
} from '../lib/invite';

const TOKEN = 'abcdefghijklmnopqrstuvwxyzABCDEF';

describe('invite URL', () => {
  it('builds a custom-scheme URL that contains only the token', () => {
    const url = inviteUrlFromToken(TOKEN);
    expect(url).toBe(`doctormaslianski://invite/${TOKEN}`);
    expect(url).not.toContain('clinic_label');
    expect(url).not.toContain('patient');
    expect(url).not.toContain('treatment');
  });

  it('rejects a token that is too short', () => {
    expect(inviteUrlFromToken('short')).toBeNull();
  });

  it('starts issued invite state empty so the token is not persisted', () => {
    expect(createInviteState()).toBeNull();
  });

  it('copies only the same custom-scheme URL as the QR payload', async () => {
    const url = inviteUrlFromToken(TOKEN);
    expect(url).not.toBeNull();
    if (url === null) {
      return;
    }

    const written: string[] = [];
    await expect(
      copyInviteUrl(async (value) => {
        written.push(value);
      }, url),
    ).resolves.toBe('copied');
    expect(written).toEqual([url]);
    expect(written[0]).toBe(`doctormaslianski://invite/${TOKEN}`);
    expect(written[0]).not.toContain('clinic_label');
  });

  it('does not copy a non-invite URL and reports failure when clipboard write throws', async () => {
    await expect(copyInviteUrl(async () => {}, 'https://example.test/invite/abc')).resolves.toBe(
      'failed',
    );
    await expect(
      copyInviteUrl(async () => {
        throw new Error('denied');
      }, `doctormaslianski://invite/${TOKEN}`),
    ).resolves.toBe('failed');
  });

  it('parses the RPC payload without keeping extra fields', () => {
    expect(
      parseIssuedInvite({
        invite_id: '11111111-1111-4111-8111-111111111111',
        expires_at: '2026-09-11T00:00:00.000Z',
        token: TOKEN,
        clinic_label: 'must-not-be-copied',
      }),
    ).toEqual({
      inviteId: '11111111-1111-4111-8111-111111111111',
      expiresAt: '2026-09-11T00:00:00.000Z',
      token: TOKEN,
    });
  });
});
