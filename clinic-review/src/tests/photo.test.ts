import { describe, expect, it } from 'vitest';

import {
  doctorMilestonePhotoPath,
  extensionForContentType,
  groupPatientPhotosByDay,
  isAllowedDoctorPhotoType,
  patientPhotoFileName,
  photoCountLabel,
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

describe('patient photo days', () => {
  it('groups photos into one folder per day, newest day first', () => {
    const days = groupPatientPhotosByDay([
      { submitted_on: '2026-10-10', slot: 2 },
      { submitted_on: '2026-10-12', slot: 1 },
      { submitted_on: '2026-10-10', slot: 1 },
    ]);

    expect(days.map((day) => day.date)).toEqual(['2026-10-12', '2026-10-10']);
    expect(days[1]?.photos.map((photo) => photo.slot)).toEqual([1, 2]);
  });

  it('names a download from the day, slot, and file extension', () => {
    expect(
      patientPhotoFileName({
        submitted_on: '2026-10-10',
        slot: 1,
        storage_path: 'clinic/patient/treatment/2026-10-10/photo.jpg',
      }),
    ).toBe('2026-10-10-slot-1.jpg');
    expect(photoCountLabel(1)).toBe('1 файл');
    expect(photoCountLabel(3)).toBe('3 файла');
    expect(photoCountLabel(5)).toBe('5 файлов');
  });
});
