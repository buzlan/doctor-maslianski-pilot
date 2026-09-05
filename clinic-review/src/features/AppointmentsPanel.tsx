import { FormEvent, useState } from 'react';

import { wallClockFromInput, wallClockInputValue } from '../lib/civil-date';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { EmptyState, Field } from '../ui/primitives';

export type AppointmentRow = {
  id: string;
  status: 'current' | 'superseded';
  wall_clock: string;
  superseded_at: string | null;
};

type Props = {
  treatmentId: string;
  treatmentActive: boolean;
  appointments: AppointmentRow[];
  onChanged: () => Promise<void>;
};

export function AppointmentsPanel({
  treatmentId,
  treatmentActive,
  appointments,
  onChanged,
}: Props) {
  const current = appointments.find((item) => item.status === 'current');
  const [wallClock, setWallClock] = useState(
    current === undefined ? '' : wallClockInputValue(current.wall_clock),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function replace(event: FormEvent) {
    event.preventDefault();
    const payload = wallClockFromInput(wallClock);
    if (payload === null) {
      setError('Укажите локальное время клиники без зоны Z.');
      return;
    }
    setBusy(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc('replace_current_appointment', {
      p_treatment_id: treatmentId,
      p_wall_clock: payload,
    });
    setBusy(false);
    if (rpcError) {
      setError(publicErrorMessage(rpcError, 'Не удалось сохранить приём.'));
      return;
    }
    await onChanged();
  }

  return (
    <section className="card">
      <h2 className="card-title">Приёмы</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {current === undefined ? (
        <EmptyState title="Текущего приёма нет" />
      ) : (
        <div className="kv">
          <div className="kv-row">
            <span className="kv-label">Сейчас</span>
            <strong>{current.wall_clock}</strong>
          </div>
        </div>
      )}
      {treatmentActive ? (
        <form className="form-grid" onSubmit={(event) => void replace(event)}>
          <Field label="Следующий приём (время клиники)">
            <input
              type="datetime-local"
              value={wallClock}
              onChange={(event) => setWallClock(event.target.value)}
              required
            />
          </Field>
          <button type="submit" disabled={busy}>
            Сохранить приём
          </button>
        </form>
      ) : null}
      {appointments.filter((item) => item.status === 'superseded').length > 0 ? (
        <ul>
          {appointments
            .filter((item) => item.status === 'superseded')
            .map((item) => (
              <li key={item.id} className="muted">
                заменён: {item.wall_clock}
              </li>
            ))}
        </ul>
      ) : null}
    </section>
  );
}
