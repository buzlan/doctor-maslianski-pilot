import type { Json } from "@db-types";
import type { ClinicSupabaseClient } from "./supabase";

export const INSTRUCTION_PHOTO_BUCKET = "instruction-photos";
export const INSTRUCTION_PHOTO_MAX_BYTES = 10 * 1024 * 1024;
export const INSTRUCTION_PHOTO_MAX_COUNT = 10;
export type DetailedInstruction = {
  heading: string;
  text: string;
  photo_paths: string[];
};
export type InstructionDraft = {
  heading: string;
  text: string;
  photos: (string | File)[];
};

export function readDetailedInstruction(
  value: Json | null,
): DetailedInstruction | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  if (
    typeof value.heading !== "string" ||
    typeof value.text !== "string" ||
    !Array.isArray(value.photo_paths)
  )
    return null;
  return {
    heading: value.heading,
    text: value.text,
    photo_paths: value.photo_paths.filter(
      (path): path is string => typeof path === "string",
    ),
  };
}

export function instructionDraft(
  value: DetailedInstruction | null,
): InstructionDraft {
  return {
    heading: value?.heading ?? "",
    text: value?.text ?? "",
    photos: [...(value?.photo_paths ?? [])],
  };
}

export function normalizeInstruction(
  draft: DetailedInstruction,
): DetailedInstruction | null {
  const heading = draft.heading.trim();
  const text = draft.text.trim();
  return heading || text || draft.photo_paths.length
    ? { heading, text, photo_paths: draft.photo_paths }
    : null;
}

export function validateInstructionPhoto(file: Pick<File, "type" | "size">) {
  if (!["image/png", "image/jpeg", "image/webp"].includes(file.type))
    throw new Error("Выберите фото в формате PNG, JPEG или WebP.");
  if (file.size === 0 || file.size > INSTRUCTION_PHOTO_MAX_BYTES)
    throw new Error("Размер фотографии должен быть от 1 байта до 10 МБ.");
}

const cleanupKey = (clinicId: string) =>
  `instruction-photo-cleanup:${clinicId}`;
export function queuePhotoCleanup(clinicId: string, paths: string[]) {
  try {
    const stored: unknown = JSON.parse(
      localStorage.getItem(cleanupKey(clinicId)) ?? "[]",
    );
    const previous = Array.isArray(stored)
      ? stored.filter(
          (p): p is string =>
            typeof p === "string" && p.startsWith(`${clinicId}/`),
        )
      : [];
    localStorage.setItem(
      cleanupKey(clinicId),
      JSON.stringify([...new Set([...previous, ...paths])]),
    );
  } catch {
    /* Storage cleanup can be retried when available. */
  }
}
export async function retryPhotoCleanup(
  client: ClinicSupabaseClient,
  clinicId: string,
): Promise<number> {
  let pending: string[] = [];
  try {
    const stored: unknown = JSON.parse(
      localStorage.getItem(cleanupKey(clinicId)) ?? "[]",
    );
    if (Array.isArray(stored))
      pending = stored.filter(
        (p): p is string =>
          typeof p === "string" && p.startsWith(`${clinicId}/`),
      );
  } catch {
    return 0;
  }
  const remaining: string[] = [];
  for (const path of pending) {
    try {
      const { error } = await client.storage
        .from(INSTRUCTION_PHOTO_BUCKET)
        .remove([path]);
      if (error) throw error;
      const { data: exists, error: existsError } = await client.storage
        .from(INSTRUCTION_PHOTO_BUCKET)
        .exists(path);
      if (existsError || exists) remaining.push(path);
    } catch {
      remaining.push(path);
    }
  }
  try {
    localStorage.setItem(cleanupKey(clinicId), JSON.stringify(remaining));
  } catch {}
  return remaining.length;
}

/** Upload immutable objects, then atomically replace the instruction. Old assignment photos stay protected by Storage. */
export async function saveDetailedInstruction(
  client: ClinicSupabaseClient,
  clinicId: string,
  itemId: string,
  oldValue: DetailedInstruction | null,
  draft: InstructionDraft,
): Promise<DetailedInstruction | null> {
  if (
    draft.heading.length > 300 ||
    draft.text.length > 50000 ||
    draft.photos.length > INSTRUCTION_PHOTO_MAX_COUNT
  )
    throw new Error(
      "Превышен размер инструкции: заголовок до 300 символов, текст до 50 000, до 10 фото.",
    );
  draft.photos.forEach((photo) => {
    if (typeof photo !== "string") validateInstructionPhoto(photo);
  });
  const uploaded: string[] = [];
  const paths: string[] = [];
  let value: DetailedInstruction | null;
  try {
    for (const photo of draft.photos) {
      if (typeof photo === "string") {
        paths.push(photo);
        continue;
      }
      const extension =
        photo.type === "image/jpeg"
          ? "jpg"
          : photo.type === "image/webp"
            ? "webp"
            : "png";
      const path = `${clinicId}/${itemId}/${crypto.randomUUID()}.${extension}`;
      // Queue before upload: even an ambiguous upload response remains recoverable.
      queuePhotoCleanup(clinicId, [path]);
      uploaded.push(path);
      const { error } = await client.storage
        .from(INSTRUCTION_PHOTO_BUCKET)
        .upload(path, photo, { contentType: photo.type, upsert: false });
      if (error) throw error;
      paths.push(path);
    }
    value = normalizeInstruction({
      heading: draft.heading,
      text: draft.text,
      photo_paths: paths,
    });
    let query = client
      .from("action_catalog_items")
      .update({ detailed_instruction: value })
      .eq("id", itemId)
      .eq("clinic_id", clinicId);
    query =
      oldValue === null
        ? query.is("detailed_instruction", null)
        : query.eq("detailed_instruction", JSON.stringify(oldValue));
    const { data, error } = await query.select("id");
    if (error) throw error;
    if (data.length !== 1)
      throw new Error(
        "Инструкция уже изменена другим сотрудником. Закройте окно, обновите каталог и повторите.",
      );
  } catch (error) {
    queuePhotoCleanup(clinicId, uploaded);
    await retryPhotoCleanup(client, clinicId);
    throw error;
  }
  try {
    const stored: unknown = JSON.parse(
      localStorage.getItem(cleanupKey(clinicId)) ?? "[]",
    );
    if (Array.isArray(stored))
      localStorage.setItem(
        cleanupKey(clinicId),
        JSON.stringify(stored.filter((path) => !paths.includes(path))),
      );
  } catch {}
  queuePhotoCleanup(
    clinicId,
    oldValue?.photo_paths.filter((path) => !paths.includes(path)) ?? [],
  );
  // Referenced paths are deliberately retained in the queue until no snapshots need them.
  await retryPhotoCleanup(client, clinicId);
  return value;
}
