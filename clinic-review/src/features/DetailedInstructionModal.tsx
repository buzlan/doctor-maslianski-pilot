import { useEffect, useRef, useState } from "react";
import {
  INSTRUCTION_PHOTO_BUCKET,
  INSTRUCTION_PHOTO_MAX_COUNT,
  type InstructionDraft,
  validateInstructionPhoto,
} from "../lib/detailed-instruction";
import { supabase } from "../lib/supabase";
import { publicErrorMessage } from "../lib/errors";
import { Field } from "../ui/primitives";

function PhotoPreview({ photo }: { photo: string | File }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let active = true;
    if (typeof photo !== "string") {
      const localUrl = URL.createObjectURL(photo);
      setUrl(localUrl);
      return () => URL.revokeObjectURL(localUrl);
    }
    void supabase.storage
      .from(INSTRUCTION_PHOTO_BUCKET)
      .createSignedUrl(photo, 3600)
      .then(({ data, error }) => {
        if (active) {
          setUrl(data?.signedUrl ?? null);
          setFailed(Boolean(error));
        }
      });
    return () => {
      active = false;
    };
  }, [photo]);
  return url ? (
    <img
      src={url}
      alt="Фото к инструкции"
      onError={() => {
        setUrl(null);
        setFailed(true);
      }}
    />
  ) : (
    <span>{failed ? "Не удалось загрузить превью" : "Загрузка…"}</span>
  );
}

export function DetailedInstructionModal({
  initial,
  onSave,
  onClose,
}: {
  initial: InstructionDraft;
  onSave: (draft: InstructionDraft) => Promise<void>;
  onClose: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [draft, setDraft] = useState<InstructionDraft>(() => ({
    ...initial,
    photos: [...initial.photos],
  }));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const saving = useRef(false);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      element?.close();
      document.body.style.overflow = overflow;
    };
  }, []);
  async function save() {
    if (saving.current) return;
    saving.current = true;
    setBusy(true);
    setError(null);
    try {
      await onSave(draft);
    } catch (error) {
      setError(publicErrorMessage(error, "Не удалось сохранить инструкцию."));
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }
  return (
    <dialog
      ref={dialog}
      className="instruction-dialog"
      aria-labelledby="instruction-dialog-title"
      onCancel={(event) => {
        event.preventDefault();
        if (!saving.current) onClose();
      }}
    >
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void save();
        }}
      >
        <header className="instruction-dialog-header">
          <h2 id="instruction-dialog-title">Подробная инструкция</h2>
          <button
            type="button"
            className="secondary"
            aria-label="Закрыть"
            disabled={busy}
            onClick={onClose}
          >
            ×
          </button>
        </header>
        <div className="instruction-dialog-body">
          <Field label="Заголовок">
            <input
              autoFocus
              maxLength={300}
              disabled={busy}
              value={draft.heading}
              onChange={(event) =>
                setDraft({ ...draft, heading: event.target.value })
              }
            />
          </Field>
          <Field label="Основной текст">
            <textarea
              rows={12}
              maxLength={50000}
              disabled={busy}
              value={draft.text}
              onChange={(event) =>
                setDraft({ ...draft, text: event.target.value })
              }
            />
          </Field>
          <Field label="Добавить фото">
            <input
              type="file"
              accept="image/png,image/jpeg,image/webp"
              multiple
              disabled={
                busy || draft.photos.length >= INSTRUCTION_PHOTO_MAX_COUNT
              }
              onChange={(event) => {
                const files = Array.from(event.target.files ?? []);
                event.target.value = "";
                try {
                  if (
                    draft.photos.length + files.length >
                    INSTRUCTION_PHOTO_MAX_COUNT
                  )
                    throw new Error("Можно добавить не больше 10 фотографий.");
                  files.forEach(validateInstructionPhoto);
                  setDraft({ ...draft, photos: [...draft.photos, ...files] });
                  setError(null);
                } catch (error) {
                  setError(
                    publicErrorMessage(error, "Не удалось добавить фото."),
                  );
                }
              }}
            />
          </Field>
          <div className="instruction-photos">
            {draft.photos.map((photo, index) => (
              <div
                className="instruction-photo"
                key={
                  typeof photo === "string" ? photo : `${photo.name}-${index}`
                }
              >
                <PhotoPreview photo={photo} />
                <button
                  type="button"
                  className="secondary"
                  disabled={busy}
                  aria-label={`Удалить фото ${index + 1}`}
                  onClick={() =>
                    setDraft({
                      ...draft,
                      photos: draft.photos.filter((_, i) => i !== index),
                    })
                  }
                >
                  Удалить фото
                </button>
              </div>
            ))}
          </div>
          {error && (
            <p role="alert" className="banner banner-error">
              {error}
            </p>
          )}
        </div>
        <footer className="instruction-dialog-footer">
          <button
            type="button"
            className="secondary"
            disabled={busy}
            onClick={onClose}
          >
            Отмена
          </button>
          <button type="submit" disabled={busy}>
            {busy ? "Сохранение…" : "Сохранить"}
          </button>
        </footer>
      </form>
    </dialog>
  );
}
