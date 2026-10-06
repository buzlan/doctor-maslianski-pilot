import { useEffect, useRef, useState } from "react";
import { ACTION_ICON_BUCKET, validateActionIcon } from "../lib/action-icons";
import { publicErrorMessage } from "../lib/errors";
import { supabase } from "../lib/supabase";

export function ActionIconInput({
  path = null,
  disabled,
  previewSelection = false,
  onSelect,
  onRemove,
}: {
  path?: string | null;
  disabled: boolean;
  previewSelection?: boolean;
  onSelect: (file: File) => void;
  onRemove?: () => void;
}) {
  const fileInput = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let cancelled = false;
    setPreview(null);
    setError(null);
    async function resolve() {
      if (!path) return;
      const { data, error } = await supabase.storage
        .from(ACTION_ICON_BUCKET)
        .createSignedUrl(path, 300);
      if (!cancelled) {
        setPreview(data?.signedUrl ?? null);
        if (error) setError("Не удалось загрузить иконку.");
      }
    }
    void resolve();
    const timer = window.setInterval(() => void resolve(), 240000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [path]);
  const [selected, setSelected] = useState<File | null>(null);
  const [localPreview, setLocalPreview] = useState<string | null>(null);
  useEffect(() => {
    if (!selected) {
      setLocalPreview(null);
      return;
    }
    const url = URL.createObjectURL(selected);
    setLocalPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [selected]);
  return (
    <div className="action-icon-input">
      <span className="field-label">Иконка</span>
      <div className="action-icon-controls">
        {(localPreview ?? preview) && (
          <img
            className="action-icon-preview"
            src={localPreview ?? preview ?? ""}
            alt="Иконка действия"
            onError={() => {
              setPreview(null);
              setError("Не удалось показать иконку.");
            }}
          />
        )}
        <button
          className="action-icon-button"
          type="button"
          disabled={disabled}
          onClick={() => fileInput.current?.click()}
        >
          {path || selected ? "Заменить" : "Добавить"}
        </button>
        <input
          ref={fileInput}
          hidden
          aria-label="Выбрать иконку действия"
          type="file"
          accept="image/png,image/webp,image/jpeg"
          disabled={disabled}
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = "";
            if (!file) return;
            try {
              validateActionIcon(file);
              setError(null);
              if (previewSelection) setSelected(file);
              onSelect(file);
            } catch (error) {
              setError(publicErrorMessage(error, "Не удалось выбрать иконку."));
            }
          }}
        />
        {onRemove && (path || selected) && (
          <button
            className="action-icon-button action-icon-button-remove"
            type="button"
            disabled={disabled}
            onClick={() => {
              setSelected(null);
              onRemove();
            }}
          >
            Удалить
          </button>
        )}
      </div>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
