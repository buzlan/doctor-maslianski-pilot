export const DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS = 300;

export const DOCTOR_PHOTO_CONTENT_TYPES = [
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/heif',
  'image/webp',
] as const;

export type DoctorPhotoContentType = (typeof DOCTOR_PHOTO_CONTENT_TYPES)[number];

const EXTENSION_BY_TYPE: Record<DoctorPhotoContentType, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/webp': 'webp',
};

export function isAllowedDoctorPhotoType(value: string): value is DoctorPhotoContentType {
  return (DOCTOR_PHOTO_CONTENT_TYPES as readonly string[]).includes(value);
}

export function extensionForContentType(contentType: DoctorPhotoContentType): string {
  return EXTENSION_BY_TYPE[contentType];
}

export function doctorMilestonePhotoPath(input: {
  clinicId: string;
  treatmentId: string;
  milestoneId: string;
  photoId: string;
  contentType: DoctorPhotoContentType;
}): string {
  return [
    input.clinicId,
    input.treatmentId,
    input.milestoneId,
    `${input.photoId}.${extensionForContentType(input.contentType)}`,
  ].join('/');
}

export function patientPhotoFileName(photo: {
  submitted_on: string;
  slot: number;
  storage_path: string;
}): string {
  const extension = photo.storage_path.split('.').pop()?.toLowerCase() ?? '';
  const safeExtension = /^[a-z0-9]{2,5}$/.test(extension) ? extension : 'jpg';
  return `${photo.submitted_on}-slot-${photo.slot}.${safeExtension}`;
}

export type PatientPhotoDay<T extends { submitted_on: string; slot: number }> = {
  date: string;
  photos: T[];
};

export function groupPatientPhotosByDay<T extends { submitted_on: string; slot: number }>(
  photos: readonly T[],
): PatientPhotoDay<T>[] {
  const sorted = [...photos].sort((left, right) => {
    const byDate = right.submitted_on.localeCompare(left.submitted_on);
    if (byDate !== 0) {
      return byDate;
    }
    return left.slot - right.slot;
  });

  const days: PatientPhotoDay<T>[] = [];
  for (const photo of sorted) {
    const current = days[days.length - 1];
    if (current === undefined || current.date !== photo.submitted_on) {
      days.push({ date: photo.submitted_on, photos: [photo] });
    } else {
      current.photos.push(photo);
    }
  }
  return days;
}

export function photoCountLabel(count: number): string {
  const mod10 = count % 10;
  const mod100 = count % 100;
  if (mod10 === 1 && mod100 !== 11) {
    return `${count} файл`;
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return `${count} файла`;
  }
  return `${count} файлов`;
}

export function contentTypeFromFile(file: File): DoctorPhotoContentType | null {
  if (isAllowedDoctorPhotoType(file.type)) {
    return file.type;
  }

  const name = file.name.toLowerCase();
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (name.endsWith('.png')) {
    return 'image/png';
  }
  if (name.endsWith('.heic')) {
    return 'image/heic';
  }
  if (name.endsWith('.heif')) {
    return 'image/heif';
  }
  if (name.endsWith('.webp')) {
    return 'image/webp';
  }
  return null;
}
