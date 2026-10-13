import type { ClinicSupabaseClient } from './supabase';

const PATIENT_PHOTO_BUCKET = 'patient-photos';
const DOCTOR_PHOTO_BUCKET = 'doctor-milestone-photos';

export type PurgedPhotoPaths = {
  patientPhotos: string[];
  doctorPhotos: string[];
};

export function purgedPhotoPaths(payload: unknown): PurgedPhotoPaths {
  const record =
    payload !== null && typeof payload === 'object' ? (payload as Record<string, unknown>) : {};
  return {
    patientPhotos: stringList(record.patient_photos),
    doctorPhotos: stringList(record.doctor_milestone_photos),
  };
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return [...new Set(value.filter((item): item is string => typeof item === 'string' && item.length > 0))];
}

export async function removePurgedPatientPhotos(
  client: ClinicSupabaseClient,
  payload: unknown,
): Promise<void> {
  const paths = purgedPhotoPaths(payload);
  await removeBucket(client, PATIENT_PHOTO_BUCKET, paths.patientPhotos);
  await removeBucket(client, DOCTOR_PHOTO_BUCKET, paths.doctorPhotos);
}

async function removeBucket(
  client: ClinicSupabaseClient,
  bucket: typeof PATIENT_PHOTO_BUCKET | typeof DOCTOR_PHOTO_BUCKET,
  paths: string[],
): Promise<void> {
  if (paths.length === 0) {
    return;
  }

  const { data, error } = await client.storage.from(bucket).remove(paths);
  if (error) {
    throw error;
  }

  const removed = new Set((data ?? []).map((object) => object.name));
  const leftover = paths.filter((path) => !removed.has(path));
  for (const path of leftover) {
    const { data: exists, error: existsError } = await client.storage.from(bucket).exists(path);
    if (existsError) {
      throw existsError;
    }
    if (exists) {
      throw new Error('Не удалось удалить файл фото.');
    }
  }
}
