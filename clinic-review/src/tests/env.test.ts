import { describe, expect, it } from 'vitest';

import { resolvePublishableKey, resolveSupabaseUrl } from '../lib/env';

describe('resolvePublishableKey', () => {
  it('prefers VITE_SUPABASE_PUBLISHABLE_KEY over the legacy anon key', () => {
    expect(
      resolvePublishableKey({
        VITE_SUPABASE_PUBLISHABLE_KEY: 'publishable-key',
        VITE_SUPABASE_ANON_KEY: 'anon-key',
      }),
    ).toBe('publishable-key');
  });

  it('falls back to the legacy anon key when the publishable key is unset', () => {
    expect(
      resolvePublishableKey({
        VITE_SUPABASE_ANON_KEY: 'anon-key',
      }),
    ).toBe('anon-key');
  });

  it('returns null when neither browser key is present', () => {
    expect(resolvePublishableKey({})).toBeNull();
  });
});

describe('resolveSupabaseUrl', () => {
  it('returns a trimmed URL', () => {
    expect(resolveSupabaseUrl({ VITE_SUPABASE_URL: ' http://127.0.0.1:54321 ' })).toBe(
      'http://127.0.0.1:54321',
    );
  });
});
