import { FormEvent, useEffect, useState } from 'react';

import { assignmentCompletionView } from '../lib/completions';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';

export type AssignmentRow = {
  id: string;
  title: string;
  instruction: string | null;
  start_date: string;
  end_date: string;
  status: 'active' | 'disabled';
};

export type CatalogOption = {
  id: string;
  title: string;
};

export type CompletionRow = {
  assignment_id: string;
  completed_on: string;
};

type Props = {
  treatmentId: string;
  treatmentActive: boolean;
  assignments: AssignmentRow[];
  completions: CompletionRow[];
  catalog: CatalogOption[];
  defaultDate: string;
  onChanged: () => Promise<void>;
};

export function AssignmentsPanel({
  treatmentId,
  treatmentActive,
  assignments,
  completions,
  catalog,
  defaultDate,
  onChanged,
}: Props) {
  const [catalogItemId, setCatalogItemId] = useState(catalog[0]?.id ?? '');
  const [startDate, setStartDate] = useState(defaultDate);
  const [endDate, setEndDate] = useState(defaultDate);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (catalogItemId === '' && catalog[0] !== undefined) {
      setCatalogItemId(catalog[0].id);
    }
  }, [catalog, catalogItemId]);

  async function assign(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc('assign_catalog_item_to_treatment', {
      p_treatment_id: treatmentId,
      p_catalog_item_id: catalogItemId,
      p_start_date: startDate,
      p_end_date: endDate,
    });
    setBusy(false);
    if (rpcError) {
      setError(publicErrorMessage(rpcError, 'Не удалось назначить действие.'));
      return;
    }
    await onChanged();
  }

  async function disable(assignmentId: string) {
    setBusy(true);
    const { error: updateError } = await supabase
      .from('action_assignments')
      .update({ status: 'disabled' })
      .eq('id', assignmentId);
    setBusy(false);
    if (updateError) {
      setError(publicErrorMessage(updateError, 'Не удалось отключить назначение.'));
      return;
    }
    await onChanged();
  }

  return (
    <section>
      <h2>Назначения</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {treatmentActive ? (
        catalog.length === 0 ? (
          <p className="muted">Нет утверждённых пунктов каталога. Сначала утвердите формулировку.</p>
        ) : (
          <form className="row" onSubmit={(event) => void assign(event)}>
            <label>
              Пункт каталога
              <select
                value={catalogItemId}
                onChange={(event) => setCatalogItemId(event.target.value)}
              >
                {catalog.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.title}
                  </option>
                ))}
              </select>
            </label>
            <label>
              С
              <input
                type="date"
                value={startDate}
                onChange={(event) => setStartDate(event.target.value)}
                required
              />
            </label>
            <label>
              По
              <input
                type="date"
                value={endDate}
                onChange={(event) => setEndDate(event.target.value)}
                required
              />
            </label>
            <button type="submit" disabled={busy}>
              Назначить
            </button>
          </form>
        )
      ) : (
        <p className="muted">Назначения можно добавлять только в активном лечении.</p>
      )}

      {assignments.length === 0 ? (
        <p className="muted">Назначений пока нет.</p>
      ) : (
        assignments.map((assignment) => {
          const view = assignmentCompletionView(completions, assignment.id, defaultDate);
          return (
            <div key={assignment.id}>
              <h3>
                {assignment.title}{' '}
                <span className="muted">
                  {assignment.start_date} — {assignment.end_date} ·{' '}
                  {assignment.status === 'active' ? 'активно' : 'отключено'}
                </span>
              </h3>
              {assignment.instruction !== null ? <p>{assignment.instruction}</p> : null}
              <p>
                Сегодня:{' '}
                {view.completedToday ? (
                  <strong>выполнено</strong>
                ) : (
                  <span className="muted">не отмечено</span>
                )}
              </p>
              {assignment.status === 'active' && treatmentActive ? (
                <button
                  type="button"
                  className="secondary"
                  disabled={busy}
                  onClick={() => void disable(assignment.id)}
                >
                  Отключить
                </button>
              ) : null}
              {view.historicalDates.length === 0 ? (
                <p className="muted">Других отметок нет.</p>
              ) : (
                <ul>
                  {view.historicalDates.map((date) => (
                    <li key={`${assignment.id}-${date}`}>{date}</li>
                  ))}
                </ul>
              )}
            </div>
          );
        })
      )}
    </section>
  );
}
