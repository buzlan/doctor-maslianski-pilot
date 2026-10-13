import { useEffect, useState } from 'react';

import {
  DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS,
  groupPatientPhotosByDay,
  patientPhotoFileName,
  photoCountLabel,
} from '../lib/photo';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { EmptyState, PageNotice } from '../ui/primitives';

export type PatientPhotoRow = {
  id: string;
  submitted_on: string;
  slot: number;
  storage_path: string;
};

export function PatientPhotosPanel({ photos }: { photos: PatientPhotoRow[] }) {
  const [urls, setUrls] = useState<Record<string, string | null>>({});
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const days = groupPatientPhotosByDay(photos);

  useEffect(() => {
    let cancelled = false;

    async function resolve() {
      const next: Record<string, string | null> = {};
      for (const photo of photos) {
        const { data, error: signError } = await supabase.storage
          .from('patient-photos')
          .createSignedUrl(photo.storage_path, DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS);
        if (cancelled) {
          return;
        }
        next[photo.id] = signError || data?.signedUrl === undefined ? null : data.signedUrl;
      }
      setUrls(next);
    }

    void resolve();
    return () => {
      cancelled = true;
    };
  }, [photos]);

  async function download(photo: PatientPhotoRow) {
    setDownloadingId(photo.id);
    setError(null);
    const { data, error: downloadError } = await supabase.storage
      .from('patient-photos')
      .download(photo.storage_path);
    setDownloadingId(null);
    if (downloadError || data === null) {
      setError(publicErrorMessage(downloadError, 'Не удалось скачать фото.'));
      return;
    }

    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = patientPhotoFileName(photo);
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return (
    <section className="card">
      <h2 className="card-title">Фото пациента</h2>
      {error !== null ? <PageNotice tone="error">{error}</PageNotice> : null}
      {days.length === 0 ? (
        <EmptyState title="Пациент ещё не отправлял фото" />
      ) : (
        days.map((day) => (
          <details key={day.date} className="photo-day" open>
            <summary>
              {day.date}
              <span>{photoCountLabel(day.photos.length)}</span>
            </summary>
            <div className="photo-grid">
              {day.photos.map((photo) => {
                const url = urls[photo.id];
                return (
                  <div key={photo.id} className="photo-tile">
                    {url === undefined ? (
                      <p className="photo-caption">Загрузка…</p>
                    ) : url === null ? (
                      <p className="photo-caption">Не удалось получить подписанный URL.</p>
                    ) : (
                      <img src={url} alt="" />
                    )}
                    <p className="photo-caption">слот {photo.slot}</p>
                    <button
                      type="button"
                      className="secondary"
                      disabled={downloadingId === photo.id}
                      onClick={() => void download(photo)}
                    >
                      {downloadingId === photo.id ? 'Скачивание…' : 'Скачать'}
                    </button>
                  </div>
                );
              })}
            </div>
          </details>
        ))
      )}
    </section>
  );
}
