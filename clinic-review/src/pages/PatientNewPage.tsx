import { FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';

import { useStaffAuth } from '../auth/StaffAuth';
import { clinicToday, formatCivilDate } from '../lib/civil-date';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';

type CreatedIds = {
  patient_id: string;
};

function parseCreated(payload: unknown): CreatedIds | null {
  if (payload === null || typeof payload !== 'object') {
    return null;
  }
  const record = payload as Record<string, unknown>;
  if (typeof record.patient_id !== 'string') {
    return null;
  }
  return { patient_id: record.patient_id };
}

export function PatientNewPage() {
  const { session } = useStaffAuth();
  const navigate = useNavigate();
  const defaultDate = session === null ? '' : formatCivilDate(clinicToday(session.timeZone));
  const [label, setLabel] = useState('');
  const [startedOn, setStartedOn] = useState(defaultDate);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { data, error: rpcError } = await supabase.rpc('create_unactivated_patient', {
      p_clinic_label: label.trim(),
      p_started_on: startedOn,
    });

    if (rpcError) {
      setError(publicErrorMessage(rpcError, 'Не удалось создать пациента.'));
      setBusy(false);
      return;
    }

    const created = parseCreated(data);
    if (created === null) {
      setError('Пациент создан, но ответ сервера неполный.');
      setBusy(false);
      return;
    }

    navigate(`/patients/${created.patient_id}`, { replace: true });
  }

  return (
    <>
      <p>
        <Link to="/patients">← К списку</Link>
      </p>
      <section>
        <h1>Новый пациент</h1>
        <p className="muted">
          Создаётся неактивированный пациент, активное лечение sclerotherapy и первый период. Cohort
          назначается только при приглашении.
        </p>
        {error !== null ? <p className="banner error">{error}</p> : null}
        <form className="row" onSubmit={(event) => void onSubmit(event)}>
          <label>
            Метка клиники
            <input
              value={label}
              onChange={(event) => setLabel(event.target.value)}
              maxLength={120}
              required
            />
          </label>
          <label>
            Начало периода
            <input
              type="date"
              value={startedOn}
              onChange={(event) => setStartedOn(event.target.value)}
              required
            />
          </label>
          <button type="submit" disabled={busy}>
            {busy ? 'Создание…' : 'Создать'}
          </button>
        </form>
      </section>
    </>
  );
}
