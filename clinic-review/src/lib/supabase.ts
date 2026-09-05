import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import type { Database } from '@db-types';

import { resolvePublishableKey, resolveSupabaseUrl } from './env';

export type ClinicSupabaseClient = SupabaseClient<Database>;

export function createClinicSupabaseClient(): ClinicSupabaseClient {
  const url = resolveSupabaseUrl(import.meta.env);
  const key = resolvePublishableKey(import.meta.env);

  if (url === null || key === null) {
    throw new Error('Отсутствует VITE_SUPABASE_URL или VITE_SUPABASE_PUBLISHABLE_KEY');
  }

  return createClient<Database>(url, key, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  });
}

export const supabase = createClinicSupabaseClient();
