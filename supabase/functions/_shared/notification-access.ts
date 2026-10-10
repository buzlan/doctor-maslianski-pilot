const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function secretsMatch(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  if (a.length === 0 || a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) {
    diff |= a[index] ^ b[index];
  }
  return diff === 0;
}

export function cronRequestAllowed(header: string | null, secret: string | undefined): boolean {
  if (secret === undefined || secret.length < 16 || header === null) {
    return false;
  }
  return secretsMatch(header, secret);
}

export function parseManualTestRequest(body: unknown): { patientId: string } | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return null;
  }
  const record = body as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length !== 1 || keys[0] !== 'patientId' || typeof record.patientId !== 'string') {
    return null;
  }
  if (!UUID_RE.test(record.patientId)) {
    return null;
  }
  return { patientId: record.patientId };
}

export function manualTestAllowed(input: { isStaff: boolean; cohort: string | null }): boolean {
  return input.isStaff && input.cohort === 'internal_dry_run';
}
