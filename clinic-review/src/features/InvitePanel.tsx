import { FormEvent, useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';

import {
  copyInviteUrl,
  inviteUrlFromToken,
  parseIssuedInvite,
  type IssuedInvite,
} from '../lib/invite';
import { publicErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { EmptyState, Field } from '../ui/primitives';

type PendingInvite = {
  id: string;
  status: 'pending' | 'consumed' | 'revoked' | 'expired';
  expires_at: string;
};

type Props = {
  treatmentId: string;
  activated: boolean;
  treatmentActive: boolean;
  onChanged: () => Promise<void>;
};

export function InvitePanel({ treatmentId, activated, treatmentActive, onChanged }: Props) {
  const [pending, setPending] = useState<PendingInvite | null>(null);
  const [issued, setIssued] = useState<IssuedInvite | null>(null);
  const [cohort, setCohort] = useState<'internal_dry_run' | 'closed_beta' | 'clinic_pilot'>(
    'internal_dry_run',
  );
  const [ttlDays, setTtlDays] = useState(7);
  const [error, setError] = useState<string | null>(null);
  const [copyStatus, setCopyStatus] = useState<'copied' | 'failed' | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    return () => {
      setIssued(null);
      setCopyStatus(null);
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    supabase
      .from('patient_invites')
      .select('id, status, expires_at')
      .eq('treatment_id', treatmentId)
      .eq('status', 'pending')
      .maybeSingle()
      .then(({ data, error: loadError }) => {
        if (cancelled) {
          return;
        }
        if (loadError) {
          setError(publicErrorMessage(loadError, 'Не удалось проверить приглашение.'));
          return;
        }
        setPending(data);
      });
    return () => {
      cancelled = true;
    };
  }, [treatmentId, issued]);

  async function issue(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setCopyStatus(null);
    const { data, error: rpcError } = await supabase.rpc('issue_patient_invite', {
      p_treatment_id: treatmentId,
      p_pilot_cohort: cohort,
      p_ttl_days: ttlDays,
    });
    setBusy(false);
    if (rpcError) {
      setIssued(null);
      setError(publicErrorMessage(rpcError, 'Не удалось выпустить приглашение.'));
      return;
    }
    const parsed = parseIssuedInvite(data);
    if (parsed === null) {
      setIssued(null);
      setError('Сервер не вернул одноразовый токен.');
      return;
    }
    setIssued(parsed);
    await onChanged();
  }

  async function revoke() {
    if (pending === null) {
      return;
    }
    setBusy(true);
    const { error: rpcError } = await supabase.rpc('revoke_patient_invite', {
      p_invite_id: pending.id,
    });
    setBusy(false);
    setIssued(null);
    setCopyStatus(null);
    if (rpcError) {
      setError(publicErrorMessage(rpcError, 'Не удалось отозвать приглашение.'));
      return;
    }
    setPending(null);
    await onChanged();
  }

  const inviteUrl = issued === null ? null : inviteUrlFromToken(issued.token);

  function closeQr() {
    setIssued(null);
    setCopyStatus(null);
  }

  async function copyLink() {
    if (inviteUrl === null) {
      return;
    }
    if (typeof navigator === 'undefined' || navigator.clipboard?.writeText === undefined) {
      setCopyStatus('failed');
      return;
    }
    const result = await copyInviteUrl((value) => navigator.clipboard.writeText(value), inviteUrl);
    setCopyStatus(result);
  }

  if (activated) {
    return (
      <section className="card">
        <h2 className="card-title">Приглашение</h2>
        <EmptyState
          title="Пациент уже активирован"
          body="Повторный выпуск токена невозможен."
        />
      </section>
    );
  }

  if (!treatmentActive) {
    return (
      <section className="card">
        <h2 className="card-title">Приглашение</h2>
        <EmptyState
          title="Лечение не активно"
          body="Приглашение доступно только для активного лечения."
        />
      </section>
    );
  }

  return (
    <section className="card">
      <h2 className="card-title">Приглашение</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {pending !== null && issued === null ? (
        <p className="muted">
          Есть неиспользованное приглашение до {pending.expires_at.slice(0, 16)}. Токен повторно не
          показывается.
        </p>
      ) : null}
      <form className="form-grid" onSubmit={(event) => void issue(event)}>
        <Field label="Когорта">
          <select
            value={cohort}
            onChange={(event) => setCohort(event.target.value as typeof cohort)}
          >
            <option value="internal_dry_run">internal_dry_run</option>
            <option value="closed_beta">closed_beta</option>
            <option value="clinic_pilot">clinic_pilot</option>
          </select>
        </Field>
        <Field label="Срок, дни">
          <input
            type="number"
            min={1}
            max={30}
            value={ttlDays}
            onChange={(event) => setTtlDays(Number(event.target.value))}
          />
        </Field>
        <button type="submit" disabled={busy}>
          Пригласить пациента
        </button>
        {pending !== null ? (
          <button type="button" className="secondary" disabled={busy} onClick={() => void revoke()}>
            Отозвать
          </button>
        ) : null}
      </form>
      {issued !== null && inviteUrl !== null ? (
        <div className="invite-qr" style={{ marginTop: '1rem' }}>
          <div className="qr-box">
            <QRCodeSVG value={inviteUrl} size={192} />
          </div>
          <div>
            <p className="muted">QR содержит только токен. Закройте окно, чтобы забыть токен.</p>
            <div className="row">
              <button type="button" onClick={() => void copyLink()}>
                Скопировать ссылку
              </button>
              <button type="button" className="secondary" onClick={closeQr}>
                Закрыть QR
              </button>
            </div>
            {copyStatus === 'copied' ? <p className="muted">Ссылка скопирована</p> : null}
            {copyStatus === 'failed' ? <p className="error">Не удалось скопировать ссылку</p> : null}
          </div>
        </div>
      ) : null}
    </section>
  );
}
