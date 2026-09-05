import { useEffect, useState } from 'react';

import { DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS } from '../lib/photo';
import { supabase } from '../lib/supabase';

export type PatientPhotoRow = {
  id: string;
  submitted_on: string;
  slot: number;
  storage_path: string;
};

export function PatientPhotosPanel({ photos }: { photos: PatientPhotoRow[] }) {
  const [urls, setUrls] = useState<Record<string, string | null>>({});

  useEffect(() => {
    let cancelled = false;

    async function resolve() {
      const next: Record<string, string | null> = {};
      for (const photo of photos) {
        const { data, error } = await supabase.storage
          .from('patient-photos')
          .createSignedUrl(photo.storage_path, DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS);
        if (cancelled) {
          return;
        }
        next[photo.id] = error || data?.signedUrl === undefined ? null : data.signedUrl;
      }
      setUrls(next);
    }

    void resolve();
    return () => {
      cancelled = true;
    };
  }, [photos]);

  return (
    <section>
      <h2>Фото пациента</h2>
      {photos.length === 0 ? (
        <p className="muted">Пациент ещё не отправлял фото.</p>
      ) : (
        <div className="photo-grid">
          {photos.map((photo) => {
            const url = urls[photo.id];
            return (
              <div key={photo.id}>
                <p className="muted">
                  {photo.submitted_on} · слот {photo.slot}
                </p>
                {url === undefined ? (
                  <p className="muted">Загрузка…</p>
                ) : url === null ? (
                  <p className="muted">Не удалось получить подписанный URL.</p>
                ) : (
                  <img src={url} alt="" />
                )}
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
