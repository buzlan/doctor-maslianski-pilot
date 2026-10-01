import assert from 'node:assert/strict';

import {
  applyInviteCors,
  inviteOptionsResponse,
  isAllowedInviteOrigin,
} from './cors.ts';

Deno.test('invite CORS allows the patient web origin and local Expo web', () => {
  assert.equal(isAllowedInviteOrigin('https://app.maslianski.by'), true);
  assert.equal(isAllowedInviteOrigin('http://localhost:8081'), true);
  assert.equal(isAllowedInviteOrigin('http://127.0.0.1:19006'), true);
  assert.equal(isAllowedInviteOrigin('https://evil.example'), false);
  assert.equal(isAllowedInviteOrigin('http://localhost.evil.example'), false);
  assert.equal(isAllowedInviteOrigin('https://localhost:8081'), false);
});

Deno.test('OPTIONS preflight is specific and POST responses echo the allowed origin', async () => {
  const allowed = inviteOptionsResponse('https://app.maslianski.by');
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), 'https://app.maslianski.by');
  assert.equal(allowed.headers.get('Access-Control-Allow-Methods'), 'POST, OPTIONS');
  assert.equal(allowed.headers.get('Access-Control-Allow-Headers')?.includes('apikey'), true);

  const denied = inviteOptionsResponse('https://evil.example');
  assert.equal(denied.status, 403);
  assert.equal(denied.headers.get('Access-Control-Allow-Origin'), null);

  const post = applyInviteCors(
    new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Cache-Control': 'no-store', 'Content-Type': 'application/json' },
    }),
    'http://localhost:8081',
  );
  assert.equal(post.headers.get('Access-Control-Allow-Origin'), 'http://localhost:8081');
  assert.equal(post.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(await post.json(), { ok: true });

  const native = applyInviteCors(new Response('{}', { status: 200 }), null);
  assert.equal(native.headers.get('Access-Control-Allow-Origin'), null);
});
