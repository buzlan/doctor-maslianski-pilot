const PATIENT_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function manualTestPushBody(patientId: string): { patientId: string } | null {
  if (!PATIENT_ID.test(patientId)) {
    return null;
  }
  return { patientId };
}

export function canSendManualTestPush(cohort: string | null): boolean {
  return cohort === 'internal_dry_run';
}
