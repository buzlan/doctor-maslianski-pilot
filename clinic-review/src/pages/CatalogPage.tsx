import { FormEvent, useEffect, useRef, useState } from "react";

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
  status: "draft" | "approved";
  icon_storage_path: string | null;
};

export function CatalogPage() {
  const { session } = useStaffAuth();
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [title, setTitle] = useState("");
  const [instruction, setInstruction] = useState("");
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
      .select("id, title, instruction, status, sort_order, icon_storage_path")
      .order("sort_order")
      .order("created_at");

    if (loadError) {
      setError(publicErrorMessage(loadError, "Не удалось загрузить каталог."));
      return;
    }

    setItems(data ?? []);
    setError(null);
  }

  useEffect(() => {
    void load();
  }, []);

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

  return (
    <div className="catalog-page">
      <h1>Каталог действий</h1>
      <p className="muted">
        Название обязательно, инструкция необязательна. Утверждённый текст
        копируется в назначение. Изменение формулировки снова делает пункт
        черновиком. Иконка общая для всех назначений этого действия; её замена
        не требует повторного утверждения.
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
                </div>
              </div>
            </div>
          ))
        )}
      </section>
    </div>
  );
}
