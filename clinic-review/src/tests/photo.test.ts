import { describe, expect, it } from 'vitest';

import {
  doctorMilestonePhotoPath,
  extensionForContentType,
  isAllowedDoctorPhotoType,
} from '../lib/photo';

describe('doctor milestone photo path', () => {
  it('builds a deterministic private path from the photo UUID', () => {
    const photoId = '22222222-2222-4222-8222-222222222222';
    const path = doctorMilestonePhotoPath({
      clinicId: 'clinic-1',
      treatmentId: 'treatment-1',
      milestoneId: 'milestone-1',
      photoId,
      contentType: 'image/jpeg',
    });

    expect(path).toBe(`clinic-1/treatment-1/milestone-1/${photoId}.jpg`);
    expect(extensionForContentType('image/png')).toBe('png');
  });

  it('reuses the same UUID and path for a metadata-first retry', () => {
    const input = {
      clinicId: 'clinic-1',
      treatmentId: 'treatment-1',
      milestoneId: 'milestone-1',
      photoId: '33333333-3333-4333-8333-333333333333',
      contentType: 'image/webp' as const,
    };

    expect(doctorMilestonePhotoPath(input)).toBe(doctorMilestonePhotoPath(input));
  });

  it('allows only private-bucket MIME types', () => {
    expect(isAllowedDoctorPhotoType('image/jpeg')).toBe(true);
    expect(isAllowedDoctorPhotoType('application/pdf')).toBe(false);
  });
});
