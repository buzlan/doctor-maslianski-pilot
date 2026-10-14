import { FormEvent, useEffect, useRef, useState } from "react";

import { DetailedInstructionModal } from "../features/DetailedInstructionModal";
import {
  instructionDraft,
  readDetailedInstruction,
  saveDetailedInstruction,
  retryPhotoCleanup,
  queuePhotoCleanup,
  INSTRUCTION_PHOTO_BUCKET,
  type DetailedInstruction,
  type InstructionDraft,
} from "../lib/detailed-instruction";
import { ActionIconInput } from "../features/ActionIconInput";
import {
  prepareActionIcon,
  removeUnusedIcon,
  saveActionIcon,
} from "../lib/action-icons";

import { useStaffAuth } from "../auth/StaffAuth";
import { publicErrorMessage } from "../lib/errors";
import { supabase } from "../lib/supabase";
import { Badge, EmptyState, Field, PageNotice } from "../ui/primitives";

type CatalogItem = {
  id: string;
  title: string;
  instruction: string | null;
  detailed_instruction: DetailedInstruction | null;
  status: "draft" | "approved";
  icon_storage_path: string | null;
};

export function CatalogPage() {
  const { session } = useStaffAuth();
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [title, setTitle] = useState("");
  const [instruction, setInstruction] = useState("");
  const [newDetails, setNewDetails] = useState<InstructionDraft>(() =>
    instructionDraft(null),
  );
  const [detailEditor, setDetailEditor] = useState<{
    item: CatalogItem | null;
    draft: InstructionDraft;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const [iconFile, setIconFile] = useState<File | null>(null);
  const [inputKey, setInputKey] = useState(0);
  const [cleanupPaths, setCleanupPaths] = useState<string[]>([]);
  const [notice, setNotice] = useState<string | null>(null);
  const cleanupKey = session
    ? `action-icon-cleanup:${session.clinicId}:${session.userId}`
    : null;
  const pendingCleanup = useRef<string[]>([]);

  useEffect(() => {
    try {
      const stored: unknown = cleanupKey
        ? JSON.parse(localStorage.getItem(cleanupKey) ?? "[]")
        : [];
      pendingCleanup.current = Array.isArray(stored)
        ? stored.filter(
            (path): path is string =>
              typeof path === "string" &&
              path.startsWith(`${session?.clinicId}/`),
          )
        : [];
    } catch {
      pendingCleanup.current = [];
    }
    setCleanupPaths(pendingCleanup.current);
  }, [cleanupKey]);

  function rememberCleanup(paths: string[]) {
    pendingCleanup.current = paths;
    setCleanupPaths(paths);
    try {
      if (cleanupKey) localStorage.setItem(cleanupKey, JSON.stringify(paths));
    } catch {}
  }

  async function cleanup(path: string) {
    try {
      await removeUnusedIcon(supabase, path);
      rememberCleanup(pendingCleanup.current.filter((value) => value !== path));
    } catch {
      rememberCleanup([...new Set([...pendingCleanup.current, path])]);
    }
  }

  async function changeIcon(item: CatalogItem, file: File | null) {
    if (!session || busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const image = file ? await prepareActionIcon(file) : null;
      await saveActionIcon(
        supabase,
        session.clinicId,
        item.id,
        item.icon_storage_path,
        image,
        cleanup,
      );
      await load();
    } catch (error) {
      await load();
      setError(publicErrorMessage(error, "Не удалось сохранить иконку."));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function retryCleanup() {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    try {
      for (const path of [...pendingCleanup.current]) await cleanup(path);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function load() {
    const { data, error: loadError } = await supabase
      .from("action_catalog_items")
      .select(
        "id, title, instruction, detailed_instruction, status, sort_order, icon_storage_path",
      )
      .order("sort_order")
      .order("created_at");

    if (loadError) {
      setError(publicErrorMessage(loadError, "Не удалось загрузить каталог."));
      return;
    }

    setItems(
      (data ?? []).map((item) => ({
        ...item,
        detailed_instruction: readDetailedInstruction(
          item.detailed_instruction,
        ),
      })),
    );
    setError(null);
  }

  useEffect(() => {
    void load();
  }, []);

  useEffect(() => {
    if (session) void retryPhotoCleanup(supabase, session.clinicId);
  }, [session?.clinicId]);

  async function onCreate(event: FormEvent) {
    event.preventDefault();
    if (!session || busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const image = iconFile ? await prepareActionIcon(iconFile) : null;
      const { data, error: insertError } = await supabase
        .from("action_catalog_items")
        .insert({
          clinic_id: session.clinicId,
          title: title.trim(),
          instruction: instruction.trim() || null,
          status: "draft",
        })
        .select("id")
        .single();
      if (insertError) throw insertError;
      const createdDetails = newDetails;
      setNewDetails(instructionDraft(null));
      setTitle("");
      setInstruction("");
      setIconFile(null);
      setInputKey((value) => value + 1);
      try {
        if (image)
          await saveActionIcon(
            supabase,
            session.clinicId,
            data.id,
            null,
            image,
            cleanup,
          );
      } catch {
        setNotice(
          "Действие создано, но иконку сохранить не удалось. Добавьте её у созданного действия.",
        );
      }
      try {
        await saveDetailedInstruction(
          supabase,
          session.clinicId,
          data.id,
          null,
          createdDetails,
        );
      } catch {
        setNotice(
          "Пункт создан, но подробную инструкцию сохранить не удалось. Она открыта для повторного сохранения.",
        );
        setDetailEditor({
          item: {
            id: data.id,
            title: title.trim(),
            instruction: instruction.trim() || null,
            detailed_instruction: null,
            status: "draft",
            icon_storage_path: null,
          },
          draft: createdDetails,
        });
      }
      await load();
    } catch (error) {
      setError(publicErrorMessage(error, "Не удалось создать пункт каталога."));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function saveItem(item: CatalogItem) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      const { error } = await supabase
        .from("action_catalog_items")
        .update({
          title: item.title.trim(),
          instruction: item.instruction?.trim() || null,
        })
        .eq("id", item.id);
      if (error) throw error;
      await load();
    } catch (error) {
      setError(publicErrorMessage(error, "Не удалось сохранить формулировку."));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function saveDetails(draft: InstructionDraft) {
    if (!detailEditor || !session || busyRef.current) return;
    if (!detailEditor.item) {
      setNewDetails(draft);
      setDetailEditor(null);
      return;
    }
    busyRef.current = true;
    setBusy(true);
    try {
      const item = detailEditor.item;
      const value = await saveDetailedInstruction(
        supabase,
        session.clinicId,
        item.id,
        item.detailed_instruction,
        draft,
      );
      // Preserve any unsaved edits in the existing title/short instruction fields.
      setItems((current) =>
        current.map((row) =>
          row.id === item.id
            ? {
                ...row,
                detailed_instruction: value,
                status:
                  JSON.stringify(value) ===
                  JSON.stringify(item.detailed_instruction)
                    ? row.status
                    : "draft",
              }
            : row,
        ),
      );
      setDetailEditor(null);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function approve(id: string) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      const { error } = await supabase
        .from("action_catalog_items")
        .update({ status: "approved" })
        .eq("id", id);
      if (error) throw error;
      await load();
    } catch (error) {
      setError(publicErrorMessage(error, "Не удалось утвердить пункт."));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  async function removeItem(item: CatalogItem) {
    const label = item.title.trim() || "этот пункт";
    if (
      !window.confirm(
        `Удалить «${label}» из каталога? Назначения этого действия пропадут у пациентов.`,
      )
    ) {
      return;
    }
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const { data, error } = await supabase.rpc("delete_catalog_item", {
        p_item_id: item.id,
      });
      if (error) throw error;
      const path =
        data !== null &&
        typeof data === "object" &&
        "icon_storage_path" in data &&
        typeof data.icon_storage_path === "string"
          ? data.icon_storage_path
          : null;
      if (path !== null) {
        try {
          await removeUnusedIcon(supabase, path);
        } catch {
          rememberCleanup([...new Set([...pendingCleanup.current, path])]);
          setNotice("Пункт удалён, но иконку не удалось стереть из хранилища.");
        }
      }
      if (session) {
        try {
          const prefix = `${session.clinicId}/${item.id}`;
          const { data: photos, error: listError } = await supabase.storage
            .from(INSTRUCTION_PHOTO_BUCKET)
            .list(prefix, { limit: 1000 });
          if (listError) throw listError;
          queuePhotoCleanup(
            session.clinicId,
            (photos ?? []).map((photo) => `${prefix}/${photo.name}`),
          );
          if (await retryPhotoCleanup(supabase, session.clinicId))
            setNotice(
              "Пункт удалён. Очистка неиспользуемых фото будет повторена при открытии каталога.",
            );
        } catch {
          setNotice("Пункт удалён, но очистить фотографии не удалось.");
        }
      }
      await load();
    } catch (error) {
      setError(publicErrorMessage(error, "Не удалось удалить пункт каталога."));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  return (
    <div className="catalog-page">
      <h1>Каталог действий</h1>
      <p className="muted">
        Название обязательно, инструкция необязательна. Утверждённый текст
        копируется в назначение. Изменение формулировки снова делает пункт
        черновиком. Иконка общая для всех назначений этого действия; её замена
        не требует повторного утверждения. Удаление пункта убирает его
        назначения у пациентов. Подробная инструкция необязательна и также
        копируется в назначение.
      </p>
      {error !== null ? <PageNotice tone="error">{error}</PageNotice> : null}
      {notice && <PageNotice>{notice}</PageNotice>}
      {busy && (
        <p role="status" className="muted">
          Сохранение…
        </p>
      )}
      {cleanupPaths.length > 0 && (
        <PageNotice>
          Некоторые неиспользуемые файлы пока не удалены.
          <button
            type="button"
            className="secondary"
            disabled={busy}
            onClick={() => void retryCleanup()}
          >
            Повторить очистку
          </button>
        </PageNotice>
      )}

      <section className="card">
        <h2 className="card-title">Новый пункт</h2>
        <form
          className="catalog-edit-row catalog-create-row"
          onSubmit={(event) => void onCreate(event)}
        >
          <Field label="Название">
            <input
              disabled={busy}
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              required
            />
          </Field>
          <Field label="Инструкция">
            <input
              disabled={busy}
              value={instruction}
              onChange={(event) => setInstruction(event.target.value)}
            />
          </Field>
          <ActionIconInput
            key={inputKey}
            disabled={busy}
            previewSelection
            onSelect={setIconFile}
            onRemove={() => setIconFile(null)}
          />
          <button type="submit" disabled={busy}>
            Добавить черновик
          </button>
          <div className="catalog-details-actions catalog-create-details">
            <button
              type="button"
              className="secondary"
              disabled={busy}
              onClick={() => setDetailEditor({ item: null, draft: newDetails })}
            >
              {newDetails.heading.trim() ||
              newDetails.text.trim() ||
              newDetails.photos.length
                ? "Редактировать инструкцию"
                : "Подробная инструкция"}
            </button>
          </div>
        </form>
      </section>

      <section className="card" style={{ marginTop: "0.9rem" }}>
        <div className="catalog-section-heading">
          <h2 className="card-title">Пункты клиники</h2>
        </div>
        {items.length === 0 ? (
          <EmptyState
            title="Каталог пуст"
            body="Добавьте и утвердите формулировку клиники."
          />
        ) : (
          items.map((item) => (
            <div key={item.id} className="catalog-item">
              <div className="catalog-edit-row">
                <Field label="Название">
                  <input
                    disabled={busy}
                    value={item.title}
                    onChange={(event) =>
                      setItems((current) =>
                        current.map((row) =>
                          row.id === item.id
                            ? { ...row, title: event.target.value }
                            : row,
                        ),
                      )
                    }
                  />
                </Field>
                <Field label="Инструкция">
                  <input
                    disabled={busy}
                    value={item.instruction ?? ""}
                    onChange={(event) =>
                      setItems((current) =>
                        current.map((row) =>
                          row.id === item.id
                            ? { ...row, instruction: event.target.value }
                            : row,
                        ),
                      )
                    }
                  />
                </Field>
                <ActionIconInput
                  path={item.icon_storage_path}
                  disabled={busy}
                  onSelect={(file) => void changeIcon(item, file)}
                  onRemove={() => void changeIcon(item, null)}
                />
                <div className="catalog-row-actions">
                  <Badge
                    tone={item.status === "approved" ? "success" : "warning"}
                  >
                    {item.status === "approved" ? "утверждено" : "черновик"}
                  </Badge>
                  <button
                    type="button"
                    className="secondary"
                    disabled={busy}
                    onClick={() => void saveItem(item)}
                  >
                    Сохранить
                  </button>
                  {item.status === "draft" ? (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void approve(item.id)}
                    >
                      Утвердить
                    </button>
                  ) : null}
                  <button
                    type="button"
                    className="danger"
                    disabled={busy}
                    onClick={() => void removeItem(item)}
                  >
                    Удалить пункт
                  </button>
                </div>
              </div>
              <div className="catalog-details-actions">
                <button
                  type="button"
                  className="secondary"
                  disabled={busy}
                  onClick={() =>
                    setDetailEditor({
                      item,
                      draft: instructionDraft(item.detailed_instruction),
                    })
                  }
                >
                  {item.detailed_instruction
                    ? "Редактировать инструкцию"
                    : "Подробная инструкция"}
                </button>
                {item.detailed_instruction && (
                  <span className="muted">
                    Инструкция добавлена · фото:{" "}
                    {item.detailed_instruction.photo_paths.length}
                  </span>
                )}
              </div>
            </div>
          ))
        )}
      </section>
      {detailEditor && (
        <DetailedInstructionModal
          initial={detailEditor.draft}
          onSave={saveDetails}
          onClose={() => setDetailEditor(null)}
        />
      )}
    </div>
  );
}
