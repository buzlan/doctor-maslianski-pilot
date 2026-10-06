import type { ClinicSupabaseClient } from "./supabase";

export const ACTION_ICON_BUCKET = "action-icons";
export const ACTION_ICON_MAX_BYTES = 2 * 1024 * 1024;
export const ACTION_ICON_TYPES = ["image/png", "image/webp", "image/jpeg"];

export function validateActionIcon(file: Pick<File, "type" | "size">): void {
  if (!ACTION_ICON_TYPES.includes(file.type))
    throw new Error("Выберите PNG, WebP или JPEG.");
  if (file.size === 0 || file.size > ACTION_ICON_MAX_BYTES)
    throw new Error("Размер иконки должен быть от 1 байта до 2 МБ.");
}

export async function prepareActionIcon(file: File): Promise<Blob> {
  validateActionIcon(file);
  const bitmap = await createImageBitmap(file);
  try {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 256;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Не удалось обработать изображение.");
    const scale = Math.min(256 / bitmap.width, 256 / bitmap.height);
    const width = bitmap.width * scale;
    const height = bitmap.height * scale;
    context.drawImage(
      bitmap,
      (256 - width) / 2,
      (256 - height) / 2,
      width,
      height,
    );
    return await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob(
        (blob) =>
          blob
            ? resolve(blob)
            : reject(new Error("Не удалось обработать изображение.")),
        "image/png",
      ),
    );
  } finally {
    bitmap.close();
  }
}

export async function removeUnusedIcon(
  client: ClinicSupabaseClient,
  path: string,
): Promise<void> {
  const { data, error } = await client.storage
    .from(ACTION_ICON_BUCKET)
    .remove([path]);
  if (error) throw error;
  if (!data?.some((object) => object.name === path)) {
    const { data: exists, error: existsError } = await client.storage
      .from(ACTION_ICON_BUCKET)
      .exists(path);
    if (existsError) throw existsError;
    if (exists)
      throw new Error("Файл пока не удалён: возможно, он используется.");
  }
}

/** Compare-and-set avoids silently overwriting another editor's icon. */
export async function saveActionIcon(
  client: ClinicSupabaseClient,
  clinicId: string,
  itemId: string,
  oldPath: string | null,
  image: Blob | null,
  cleanup: (path: string) => Promise<void>,
): Promise<void> {
  const path =
    image === null ? null : `${clinicId}/${itemId}/${crypto.randomUUID()}.png`;
  if (image !== null && path !== null) {
    const { error } = await client.storage
      .from(ACTION_ICON_BUCKET)
      .upload(path, image, { contentType: "image/png", upsert: false });
    if (error) throw error;
  }
  try {
    let update = client
      .from("action_catalog_items")
      .update({ icon_storage_path: path })
      .eq("id", itemId)
      .eq("clinic_id", clinicId);
    update =
      oldPath === null
        ? update.is("icon_storage_path", null)
        : update.eq("icon_storage_path", oldPath);
    const { data, error } = await update.select("id");
    if (error) throw error;
    if (data.length !== 1)
      throw new Error("Иконка уже изменена. Обновите каталог и повторите.");
  } catch (error) {
    // Also safe after an ambiguous network error: Storage refuses deleting a referenced file.
    if (path !== null) await cleanup(path);
    throw error;
  }
  if (oldPath !== null && oldPath !== path) await cleanup(oldPath);
}
