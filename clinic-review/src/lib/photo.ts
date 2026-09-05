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
