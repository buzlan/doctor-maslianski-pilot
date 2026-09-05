import { FormEvent, useState } from 'react';

import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { Badge, EmptyState, Field } from '../ui/primitives';

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
    <section className="card">
      <h2 className="card-title">Периоды</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {periods.length === 0 ? <EmptyState title="Периодов нет" /> : null}
      <div className="kv">
        {periods.map((period) => (
          <div key={period.id} className="kv-row">
            <span className="kv-label">{period.started_on}</span>
            <span>
              {period.ended_on ?? 'текущий'}{' '}
              {period.ended_on === null ? <Badge tone="success">открыт</Badge> : null}
            </span>
          </div>
        ))}
      </div>
      {treatmentActive ? (
        <form className="form-grid" onSubmit={(event) => void startNext(event)}>
          <Field label="Конец текущего">
            <input
              type="date"
              value={endedOn}
              onChange={(event) => setEndedOn(event.target.value)}
              required
            />
          </Field>
          <Field label="Начало нового">
            <input
              type="date"
              value={startedOn}
              onChange={(event) => setStartedOn(event.target.value)}
              required
            />
          </Field>
          <button type="submit" disabled={busy}>
            Начать новый период
          </button>
        </form>
      ) : null}
    </section>
  );
}
