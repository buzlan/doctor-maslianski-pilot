import path from 'node:path';
import { fileURLToPath } from 'node:url';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(rootDir, 'src'),
      '@db-types': path.resolve(rootDir, '../supabase/generated-db-types.ts'),
    },
  },
  server: {
    fs: {
      allow: [path.resolve(rootDir, '..')],
    },
  },
  test: {
    environment: 'node',
  },
});
