import { FormEvent, useEffect, useState } from 'react';

import {
  formatWallClock,
  wallClockFromParts,
  wallClockParts,
} from '../lib/civil-date';
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

const HOURS = Array.from({ length: 24 }, (_, hour) => String(hour).padStart(2, '0'));
const MINUTES = Array.from({ length: 60 }, (_, minute) => String(minute).padStart(2, '0'));

export function AppointmentsPanel({
  treatmentId,
  treatmentActive,
  appointments,
  onChanged,
}: Props) {
  const current = appointments.find((item) => item.status === 'current');
  const currentClock = current?.wall_clock;
  const initial = currentClock === undefined ? null : wallClockParts(currentClock);
  const [date, setDate] = useState(initial?.date ?? '');
  const [hour, setHour] = useState(initial?.hour ?? '09');
  const [minute, setMinute] = useState(initial?.minute ?? '00');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const preview = wallClockFromParts(date, hour, minute);

  useEffect(() => {
    if (currentClock === undefined) {
      return;
    }
    const parts = wallClockParts(currentClock);
    if (parts === null) {
      return;
    }
    setDate(parts.date);
    setHour(parts.hour);
    setMinute(parts.minute);
  }, [currentClock]);

  async function cancel() {
    if (current === undefined) {
      return;
    }
    setBusy(true);
    setError(null);
    const { error: updateError } = await supabase
      .from('appointments')
      .update({ status: 'superseded', superseded_at: new Date().toISOString() })
      .eq('id', current.id);
    setBusy(false);
    if (updateError) {
      setError(publicErrorMessage(updateError, 'Не удалось отменить приём.'));
      return;
    }
    await onChanged();
  }

  async function replace(event: FormEvent) {
    event.preventDefault();
    if (preview === null) {
      setError('Укажите дату и время приёма.');
      return;
    }
    setBusy(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc('replace_current_appointment', {
      p_treatment_id: treatmentId,
      p_wall_clock: preview,
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
            <strong>{formatWallClock(current.wall_clock)}</strong>
          </div>
        </div>
      )}
      {treatmentActive ? (
        <form className="form-grid" onSubmit={(event) => void replace(event)}>
          <Field label="Дата">
            <input type="date" value={date} onChange={(event) => setDate(event.target.value)} required />
          </Field>
          <Field label="Часы">
            <select value={hour} onChange={(event) => setHour(event.target.value)}>
              {HOURS.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Минуты">
            <select value={minute} onChange={(event) => setMinute(event.target.value)}>
              {MINUTES.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </Field>
          {preview !== null ? (
            <p className="muted appointment-preview">Выбрано: {formatWallClock(preview)}</p>
          ) : null}
          <button type="submit" disabled={busy || date.length === 0}>
            Сохранить приём
          </button>
          {current !== undefined ? (
            <button
              type="button"
              className="secondary"
              disabled={busy}
              onClick={() => {
                void cancel();
              }}
            >
              Отменить запись
            </button>
          ) : null}
        </form>
      ) : null}
      {appointments.filter((item) => item.status === 'superseded').length > 0 ? (
        <ul>
          {appointments
            .filter((item) => item.status === 'superseded')
            .map((item) => (
              <li key={item.id} className="muted">
                заменён: {formatWallClock(item.wall_clock)}
              </li>
            ))}
        </ul>
      ) : null}
    </section>
  );
}
