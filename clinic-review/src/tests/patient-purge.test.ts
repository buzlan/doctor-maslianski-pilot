import { describe, expect, it } from 'vitest';

import { purgedPhotoPaths } from '../lib/patient-purge';

describe('purged photo paths', () => {
  it('reads both buckets and drops empty or duplicate paths', () => {
    expect(
      purgedPhotoPaths({
        patient_photos: ['clinic/patient/a.jpg', 'clinic/patient/a.jpg', ''],
        doctor_milestone_photos: ['clinic/treatment/b.jpg'],
      }),
    ).toEqual({
      patientPhotos: ['clinic/patient/a.jpg'],
      doctorPhotos: ['clinic/treatment/b.jpg'],
    });
  });

  it('returns empty lists when the payload has no paths', () => {
    expect(purgedPhotoPaths(null)).toEqual({ patientPhotos: [], doctorPhotos: [] });
    expect(purgedPhotoPaths({})).toEqual({ patientPhotos: [], doctorPhotos: [] });
  });
});
