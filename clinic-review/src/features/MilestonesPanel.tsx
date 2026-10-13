import { FormEvent, useEffect, useRef, useState } from 'react';

import { useStaffAuth } from '../auth/StaffAuth';
import { formatCivilDateRu } from '../lib/civil-date';
import { publicErrorMessage } from '../lib/errors';
import {
  contentTypeFromFile,
  DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS,
  doctorMilestonePhotoPath,
} from '../lib/photo';
import { supabase } from '../lib/supabase';
import { EmptyState, Field } from '../ui/primitives';

export type MilestoneRow = {
  id: string;
  title: string;
  occurred_on: string | null;
};

export type DoctorPhotoRow = {
  id: string;
  milestone_id: string;
  storage_path: string;
  content_type: string;
};

type Props = {
  treatmentId: string;
  treatmentActive: boolean;
  milestones: MilestoneRow[];
  photos: DoctorPhotoRow[];
  defaultDate: string;
  onChanged: () => Promise<void>;
};

type PhotoView = {
  url: string | null;
  missing: boolean;
};

type PendingPhoto = {
  id: string;
  file: File;
  previewUrl: string;
};

export function MilestonesPanel({
  treatmentId,
  treatmentActive,
  milestones,
  photos,
  defaultDate,
  onChanged,
}: Props) {
  const { session } = useStaffAuth();
  const [title, setTitle] = useState('');
  const [occurredOn, setOccurredOn] = useState(defaultDate);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [views, setViews] = useState<Record<string, PhotoView>>({});
  const [pending, setPending] = useState<Record<string, PendingPhoto[]>>({});
  const pendingRef = useRef(pending);
  const fileInputs = useRef<Record<string, HTMLInputElement | null>>({});
  pendingRef.current = pending;

  useEffect(() => {
    return () => {
      for (const items of Object.values(pendingRef.current)) {
        for (const item of items) {
          URL.revokeObjectURL(item.previewUrl);
        }
      }
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function resolve() {
      const next: Record<string, PhotoView> = {};
      for (const photo of photos) {
        const { data, error: signError } = await supabase.storage
          .from('doctor-milestone-photos')
          .createSignedUrl(photo.storage_path, DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS);
        if (cancelled) {
          return;
        }
        if (signError || data?.signedUrl === undefined || data.signedUrl.length === 0) {
          next[photo.id] = { url: null, missing: true };
        } else {
          next[photo.id] = { url: data.signedUrl, missing: false };
        }
      }
      setViews(next);
    }

    void resolve();
    return () => {
      cancelled = true;
    };
  }, [photos]);

  async function createMilestone(event: FormEvent) {
    event.preventDefault();
    if (session === null) {
      return;
    }
    setBusy(true);
    setError(null);
    const { error: insertError } = await supabase.from('treatment_milestones').insert({
      treatment_id: treatmentId,
      clinic_id: session.clinicId,
      title: title.trim(),
      occurred_on: occurredOn,
    });
    setBusy(false);
    if (insertError) {
      setError(publicErrorMessage(insertError, 'Не удалось создать визит.'));
      return;
    }
    setTitle('');
    await onChanged();
  }

  async function uploadNew(milestoneId: string, file: File): Promise<'saved' | 'metadata-failed' | 'file-failed'> {
    if (session === null) {
      return 'metadata-failed';
    }
    const contentType = contentTypeFromFile(file);
    if (contentType === null) {
      setError('Допустимы только jpeg, png, heic, heif, webp.');
      return 'metadata-failed';
    }
    const photoId = crypto.randomUUID();
    const storagePath = doctorMilestonePhotoPath({
      clinicId: session.clinicId,
      treatmentId,
      milestoneId,
      photoId,
      contentType,
    });

    const { error: metaError } = await supabase.from('doctor_milestone_photos').insert({
      id: photoId,
      treatment_id: treatmentId,
      milestone_id: milestoneId,
      clinic_id: session.clinicId,
      storage_bucket: 'doctor-milestone-photos',
      storage_path: storagePath,
      content_type: contentType,
    });
    if (metaError) {
      setError(publicErrorMessage(metaError, 'Не удалось сохранить карточку фото.'));
      return 'metadata-failed';
    }

    const { error: uploadError } = await supabase.storage
      .from('doctor-milestone-photos')
      .upload(storagePath, file, { contentType, upsert: false });
    if (uploadError) {
      setError('Карточка создана, но файл не загружен. Повторите загрузку для этой же записи.');
      return 'file-failed';
    }
    return 'saved';
  }

  function addPending(milestoneId: string, files: FileList | null) {
    if (files === null || files.length === 0) {
      return;
    }
    const accepted: PendingPhoto[] = [];
    let rejected = false;
    for (const file of files) {
      if (contentTypeFromFile(file) === null) {
        rejected = true;
        continue;
      }
      accepted.push({
        id: crypto.randomUUID(),
        file,
        previewUrl: URL.createObjectURL(file),
      });
    }
    if (rejected) {
      setError('Допустимы только jpeg, png, heic, heif, webp.');
    } else {
      setError(null);
    }
    if (accepted.length === 0) {
      return;
    }
    setPending((current) => ({
      ...current,
      [milestoneId]: [...(current[milestoneId] ?? []), ...accepted],
    }));
  }

  function removePending(milestoneId: string, photoId: string) {
    setPending((current) => {
      const items = current[milestoneId] ?? [];
      const target = items.find((item) => item.id === photoId);
      if (target !== undefined) {
        URL.revokeObjectURL(target.previewUrl);
      }
      return {
        ...current,
        [milestoneId]: items.filter((item) => item.id !== photoId),
      };
    });
  }

  async function sendPending(milestoneId: string) {
    const queue = pending[milestoneId] ?? [];
    if (queue.length === 0 || session === null) {
      return;
    }
    setBusy(true);
    setError(null);
    const failed: PendingPhoto[] = [];
    for (let index = 0; index < queue.length; index += 1) {
      const item = queue[index];
      const result = await uploadNew(milestoneId, item.file);
      if (result === 'metadata-failed') {
        failed.push(...queue.slice(index));
        break;
      }
      URL.revokeObjectURL(item.previewUrl);
    }
    setPending((current) => ({ ...current, [milestoneId]: failed }));
    setBusy(false);
    await onChanged();
  }

  async function retryUpload(photo: DoctorPhotoRow, file: File) {
    setBusy(true);
    setError(null);
    const { error: uploadError } = await supabase.storage
      .from('doctor-milestone-photos')
      .upload(photo.storage_path, file, {
        contentType: photo.content_type,
        upsert: false,
      });
    setBusy(false);
    if (uploadError) {
      setError(publicErrorMessage(uploadError, 'Повторная загрузка не удалась.'));
      return;
    }
    await onChanged();
  }

  return (
    <section className="card">
      <h2 className="card-title">Визиты и фото врача</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {treatmentActive ? (
        <form className="form-grid" onSubmit={(event) => void createMilestone(event)}>
          <Field label="Название визита">
            <input value={title} onChange={(event) => setTitle(event.target.value)} required />
          </Field>
          <Field label="Дата">
            <input
              type="date"
              value={occurredOn}
              onChange={(event) => setOccurredOn(event.target.value)}
              required
            />
          </Field>
          <button type="submit" disabled={busy}>
            Добавить визит
          </button>
          {occurredOn.length > 0 ? (
            <p className="muted form-note">Дата визита: {formatCivilDateRu(occurredOn)}</p>
          ) : null}
        </form>
      ) : null}

      {milestones.length === 0 ? <EmptyState title="Визитов пока нет" /> : null}
      {milestones.map((milestone) => {
        const milestonePhotos = photos.filter((photo) => photo.milestone_id === milestone.id);
        const draft = pending[milestone.id] ?? [];
        const occurred =
          milestone.occurred_on === null ? 'без даты' : formatCivilDateRu(milestone.occurred_on);
        return (
          <div key={milestone.id} className="visit-item">
            <div className="visit-heading">
              <h3>{milestone.title}</h3>
              <span className="muted">{occurred}</span>
            </div>
            {milestonePhotos.length === 0 && draft.length === 0 ? (
              <p className="muted">Фотографий этого визита нет.</p>
            ) : null}
            {milestonePhotos.length > 0 ? (
              <div className="photo-grid">
                {milestonePhotos.map((photo) => {
                  const view = views[photo.id];
                  if (view?.url !== undefined && view.url !== null) {
                    return (
                      <div key={photo.id} className="photo-tile">
                        <img src={view.url} alt="" />
                      </div>
                    );
                  }
                  return (
                    <div key={photo.id} className="photo-tile">
                      <p className="photo-caption">
                        Файл ещё не загружен. Повторите загрузку в ту же запись.
                      </p>
                      <input
                        type="file"
                        accept="image/jpeg,image/png,image/heic,image/heif,image/webp"
                        disabled={busy}
                        onChange={(event) => {
                          const file = event.target.files?.[0];
                          event.target.value = '';
                          if (file !== undefined) {
                            void retryUpload(photo, file);
                          }
                        }}
                      />
                    </div>
                  );
                })}
              </div>
            ) : null}
            {treatmentActive ? (
              <div className="visit-composer">
                {draft.length > 0 ? (
                  <div className="photo-grid">
                    {draft.map((item) => (
                      <div key={item.id} className="photo-tile photo-tile-pending">
                        <img src={item.previewUrl} alt="" />
                        <p className="photo-caption">{item.file.name}</p>
                        <button
                          type="button"
                          className="photo-remove"
                          aria-label={`Убрать ${item.file.name}`}
                          disabled={busy}
                          onClick={() => removePending(milestone.id, item.id)}
                        >
                          ×
                        </button>
                      </div>
                    ))}
                  </div>
                ) : null}
                <div className="visit-composer-actions">
                  <input
                    ref={(node) => {
                      fileInputs.current[milestone.id] = node;
                    }}
                    className="visit-file-input"
                    type="file"
                    accept="image/jpeg,image/png,image/heic,image/heif,image/webp"
                    multiple
                    disabled={busy}
                    onChange={(event) => {
                      addPending(milestone.id, event.target.files);
                      event.target.value = '';
                    }}
                  />
                  <button
                    type="button"
                    className="secondary"
                    disabled={busy}
                    onClick={() => fileInputs.current[milestone.id]?.click()}
                  >
                    Добавить фото
                  </button>
                  <button
                    type="button"
                    disabled={busy || draft.length === 0}
                    onClick={() => {
                      void sendPending(milestone.id);
                    }}
                  >
                    {busy ? 'Отправка…' : 'Отправить'}
                  </button>
                </div>
              </div>
            ) : null}
          </div>
        );
      })}
    </section>
  );
}
