import { describe, expect, it } from 'vitest';

import { canSendManualTestPush, manualTestPushBody } from '../lib/test-push';

const patientId = '11111111-1111-4111-8111-111111111111';

describe('manual test push', () => {
  it('sends only a synthetic patient id', () => {
    expect(manualTestPushBody(patientId)).toEqual({ patientId });
    expect(manualTestPushBody('not-a-patient')).toBeNull();
    expect(canSendManualTestPush('internal_dry_run')).toBe(true);
    expect(canSendManualTestPush('clinic_pilot')).toBe(false);
    expect(canSendManualTestPush(null)).toBe(false);
  });
});
