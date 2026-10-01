const PRODUCTION_ORIGIN = 'https://app.maslianski.by';

const ALLOW_HEADERS = [
  'authorization',
  'apikey',
  'content-type',
  'x-client-info',
  'x-supabase-api-version',
].join(', ');

export function isAllowedInviteOrigin(origin: string): boolean {
  if (origin === PRODUCTION_ORIGIN) {
    return true;
  }

  let url: URL;
  try {
    url = new URL(origin);
  } catch {
    return false;
  }

  if (url.protocol !== 'http:') {
    return false;
  }
  if (url.username.length > 0 || url.password.length > 0) {
    return false;
  }

  return url.hostname === 'localhost' || url.hostname === '127.0.0.1';
}

export function inviteCorsHeaders(origin: string | null): Headers {
  const headers = new Headers();
  if (origin === null || !isAllowedInviteOrigin(origin)) {
    return headers;
  }

  headers.set('Access-Control-Allow-Origin', origin);
  headers.set('Vary', 'Origin');
  return headers;
}

export function inviteOptionsResponse(origin: string | null): Response {
  if (origin === null || !isAllowedInviteOrigin(origin)) {
    return new Response(null, { status: 403 });
  }

  const headers = inviteCorsHeaders(origin);
  headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  headers.set('Access-Control-Allow-Headers', ALLOW_HEADERS);
  headers.set('Access-Control-Max-Age', '86400');
  return new Response(null, { status: 204, headers });
}

export function applyInviteCors(response: Response, origin: string | null): Response {
  const headers = new Headers(response.headers);
  inviteCorsHeaders(origin).forEach((value, key) => {
    headers.set(key, value);
  });
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
