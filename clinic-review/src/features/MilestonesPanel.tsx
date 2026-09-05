import { FormEvent, useEffect, useState } from 'react';

import { useStaffAuth } from '../auth/StaffAuth';
import { publicErrorMessage } from '../lib/errors';
import {
  contentTypeFromFile,
  DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS,
  doctorMilestonePhotoPath,
} from '../lib/photo';
import { supabase } from '../lib/supabase';

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

  async function uploadNew(milestoneId: string, file: File) {
    if (session === null) {
      return;
    }
    const contentType = contentTypeFromFile(file);
    if (contentType === null) {
      setError('Допустимы только jpeg, png, heic, heif, webp.');
      return;
    }
    const photoId = crypto.randomUUID();
    const storagePath = doctorMilestonePhotoPath({
      clinicId: session.clinicId,
      treatmentId,
      milestoneId,
      photoId,
      contentType,
    });

    setBusy(true);
    setError(null);
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
      setBusy(false);
      setError(publicErrorMessage(metaError, 'Не удалось сохранить карточку фото.'));
      return;
    }

    const { error: uploadError } = await supabase.storage
      .from('doctor-milestone-photos')
      .upload(storagePath, file, { contentType, upsert: false });
    setBusy(false);
    if (uploadError) {
      setError('Карточка создана, но файл не загружен. Повторите загрузку для этой же записи.');
      await onChanged();
      return;
    }
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
    <section>
      <h2>Визиты и фото врача</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {treatmentActive ? (
        <form className="row" onSubmit={(event) => void createMilestone(event)}>
          <label>
            Название визита
            <input value={title} onChange={(event) => setTitle(event.target.value)} required />
          </label>
          <label>
            Дата
            <input
              type="date"
              value={occurredOn}
              onChange={(event) => setOccurredOn(event.target.value)}
              required
            />
          </label>
          <button type="submit" disabled={busy}>
            Добавить визит
          </button>
        </form>
      ) : null}

      {milestones.length === 0 ? <p className="muted">Визитов пока нет.</p> : null}
      {milestones.map((milestone) => {
        const milestonePhotos = photos.filter((photo) => photo.milestone_id === milestone.id);
        return (
          <div key={milestone.id}>
            <h3>
              {milestone.title}{' '}
              <span className="muted">{milestone.occurred_on ?? 'без даты'}</span>
            </h3>
            {treatmentActive ? (
              <label>
                Прикрепить фото врача
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/heic,image/heif,image/webp"
                  disabled={busy}
                  onChange={(event) => {
                    const file = event.target.files?.[0];
                    event.target.value = '';
                    if (file !== undefined) {
                      void uploadNew(milestone.id, file);
                    }
                  }}
                />
              </label>
            ) : null}
            <div className="photo-grid">
              {milestonePhotos.map((photo) => {
                const view = views[photo.id];
                if (view?.url !== undefined && view.url !== null) {
                  return <img key={photo.id} src={view.url} alt="" />;
                }
                return (
                  <div key={photo.id}>
                    <p className="muted">Файл ещё не загружен. Повторите загрузку в ту же запись.</p>
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
          </div>
        );
      })}
    </section>
  );
}
