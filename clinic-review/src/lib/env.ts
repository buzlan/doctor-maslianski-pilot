export type BrowserSupabaseEnv = {
  VITE_SUPABASE_URL?: string;
  VITE_SUPABASE_PUBLISHABLE_KEY?: string;
  VITE_SUPABASE_ANON_KEY?: string;
};

export function resolvePublishableKey(env: BrowserSupabaseEnv): string | null {
  const publishable = env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (publishable !== undefined && publishable.length > 0) {
    return publishable;
  }

  const legacyAnon = env.VITE_SUPABASE_ANON_KEY?.trim();
  if (legacyAnon !== undefined && legacyAnon.length > 0) {
    return legacyAnon;
  }

  return null;
}

export function resolveSupabaseUrl(env: BrowserSupabaseEnv): string | null {
  const url = env.VITE_SUPABASE_URL?.trim();
  if (url === undefined || url.length === 0) {
    return null;
  }
  return url;
}
