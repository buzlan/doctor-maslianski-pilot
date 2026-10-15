import { useEffect, useRef, useState } from "react";
import {
  INSTRUCTION_PHOTO_BUCKET,
  type DetailedInstruction,
} from "../lib/detailed-instruction";
import { supabase } from "../lib/supabase";
import "./DetailedInstructionViewer.css";

function InstructionPhoto({ path, index }: { path: string; index: number }) {
  const [url, setUrl] = useState<string | null>(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    let active = true;
    setUrl(null);
    setError(false);
    void supabase.storage
      .from(INSTRUCTION_PHOTO_BUCKET)
      .createSignedUrl(path, 3600)
      .then(({ data, error }) => {
        if (active) {
          setUrl(data?.signedUrl ?? null);
          setError(Boolean(error) || !data?.signedUrl);
        }
      })
      .catch(() => {
        if (active) setError(true);
      });
    return () => {
      active = false;
    };
  }, [path]);
  return url ? (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={`Открыть фото ${index + 1}`}
    >
      <img
        src={url}
        alt={`Фото ${index + 1} к инструкции`}
        onError={() => {
          setUrl(null);
          setError(true);
        }}
      />
    </a>
  ) : (
    <p role="status">
      {error ? "Не удалось загрузить фото." : "Загрузка фото…"}
    </p>
  );
}

export function DetailedInstructionViewer({
  title,
  instruction,
  onClose,
}: {
  title: string;
  instruction: DetailedInstruction;
  onClose: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
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
  return (
    <dialog
      ref={dialog}
      className="instruction-dialog"
      aria-labelledby="instruction-viewer-title"
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
    >
      <div className="instruction-viewer-layout">
        <header className="instruction-dialog-header">
          <h2 id="instruction-viewer-title">Подробная инструкция</h2>
          <button
            autoFocus
            type="button"
            className="secondary"
            aria-label="Закрыть"
            onClick={onClose}
          >
            ×
          </button>
        </header>
        <div className="instruction-dialog-body">
          <p className="muted">{title}</p>
          {instruction.heading && <h3>{instruction.heading}</h3>}
          {instruction.text && (
            <p className="instruction-viewer-text">{instruction.text}</p>
          )}
          {instruction.photo_paths.length > 0 && (
            <div className="instruction-viewer-photos">
              {instruction.photo_paths.map((path, index) => (
                <InstructionPhoto
                  key={`${path}-${index}`}
                  path={path}
                  index={index}
                />
              ))}
            </div>
          )}
        </div>
        <footer className="instruction-dialog-footer">
          <button type="button" className="secondary" onClick={onClose}>
            Закрыть
          </button>
        </footer>
      </div>
    </dialog>
  );
}
