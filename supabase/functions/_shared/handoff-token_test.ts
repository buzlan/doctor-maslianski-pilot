import assert from 'node:assert/strict';

import { HANDOFF_TOKEN_RE, randomHandoffToken, sha256Hex } from './handoff-token.ts';

Deno.test('handoff token is opaque, single-use shaped, and only its hash is comparable', async () => {
  const first = randomHandoffToken();
  const second = randomHandoffToken();
  assert.equal(HANDOFF_TOKEN_RE.test(first), true);
  assert.notEqual(first, second);

  const hash = await sha256Hex(first);
  assert.equal(/^[0-9a-f]{64}$/.test(hash), true);
  assert.equal(hash.includes(first), false);
  assert.equal(await sha256Hex(first), hash);
});

Deno.test('consume handoff does not create users or patients', async () => {
  const source = await Deno.readTextFile(new URL('../consume-web-session-handoff/index.ts', import.meta.url));
  assert.equal(source.includes('createUser'), false);
  assert.equal(source.includes('createAuthUser'), false);
  assert.equal(source.includes('INSERT INTO public.patients'), false);
  assert.equal(source.includes('console.log'), false);
});
