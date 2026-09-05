import { FormEvent, useState } from 'react';

import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';

export type PeriodRow = {
  id: string;
  started_on: string;
  ended_on: string | null;
};

type Props = {
  treatmentId: string;
  treatmentActive: boolean;
  periods: PeriodRow[];
  defaultDate: string;
  onChanged: () => Promise<void>;
};

export function PeriodsPanel({
  treatmentId,
  treatmentActive,
  periods,
  defaultDate,
  onChanged,
}: Props) {
  const [endedOn, setEndedOn] = useState(defaultDate);
  const [startedOn, setStartedOn] = useState(defaultDate);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function startNext(event: FormEvent) {
    event.preventDefault();
    if (!window.confirm('Закрыть текущий период и начать новый? День N в приложении станет 1.')) {
      return;
    }
    setBusy(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc('start_new_treatment_period', {
      p_treatment_id: treatmentId,
      p_ended_on: endedOn,
      p_started_on: startedOn,
    });
    setBusy(false);
    if (rpcError) {
      setError(publicErrorMessage(rpcError, 'Не удалось начать новый период.'));
      return;
    }
    await onChanged();
  }

  return (
    <section>
      <h2>Периоды</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {periods.length === 0 ? <p className="muted">Периодов нет.</p> : null}
      <ul>
        {periods.map((period) => (
          <li key={period.id}>
            {period.started_on} — {period.ended_on ?? 'текущий'}
          </li>
        ))}
      </ul>
      {treatmentActive ? (
        <form className="row" onSubmit={(event) => void startNext(event)}>
          <label>
            Конец текущего
            <input
              type="date"
              value={endedOn}
              onChange={(event) => setEndedOn(event.target.value)}
              required
            />
          </label>
          <label>
            Начало нового
            <input
              type="date"
              value={startedOn}
              onChange={(event) => setStartedOn(event.target.value)}
              required
            />
          </label>
          <button type="submit" disabled={busy}>
            Начать новый период
          </button>
        </form>
      ) : null}
    </section>
  );
}
