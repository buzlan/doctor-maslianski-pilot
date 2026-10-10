import { useState } from 'react';

import { canSendManualTestPush, manualTestPushBody } from '../lib/test-push';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';

type Props = {
  patientId: string;
  cohort: string | null;
};

export function TestPushPanel({ patientId, cohort }: Props) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!canSendManualTestPush(cohort)) {
    return null;
  }

  async function send() {
    const body = manualTestPushBody(patientId);
    if (body === null) {
      setError('Не удалось отправить тестовое уведомление.');
      return;
    }
    setBusy(true);
    setError(null);
    setMessage(null);
    const { data, error: invokeError } = await supabase.functions.invoke('send-test-push', { body });
    setBusy(false);
    if (invokeError) {
      setError(publicErrorMessage(invokeError, 'Не удалось отправить тестовое уведомление.'));
      return;
    }
    const attempted = data !== null && typeof data === 'object' && 'attempted' in data
      ? Number((data as { attempted?: unknown }).attempted)
      : 0;
    setMessage(
      attempted > 0
        ? 'Тестовое уведомление отправлено.'
        : 'Подписка на уведомления ещё не найдена.',
    );
  }

  return (
    <section className="card">
      <h2 className="card-title">Тестовое уведомление</h2>
      <p className="muted">Только для внутренней проверки. Текст уведомления фиксированный.</p>
      {error !== null ? <p className="error">{error}</p> : null}
      {message !== null ? <p>{message}</p> : null}
      <button type="button" disabled={busy} onClick={() => void send()}>
        Отправить тестовое уведомление
      </button>
    </section>
  );
}
