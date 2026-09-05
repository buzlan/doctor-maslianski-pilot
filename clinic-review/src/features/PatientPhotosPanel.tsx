import { useEffect, useState } from 'react';

import { DOCTOR_PHOTO_SIGNED_URL_TTL_SECONDS } from '../lib/photo';
import { supabase } from '../lib/supabase';
import { EmptyState } from '../ui/primitives';

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
    <section className="card">
      <h2 className="card-title">Фото пациента</h2>
      {photos.length === 0 ? (
        <EmptyState title="Пациент ещё не отправлял фото" />
      ) : (
        <div className="photo-grid">
          {photos.map((photo) => {
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
                <p className="photo-caption">
                  {photo.submitted_on} · слот {photo.slot}
                </p>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
