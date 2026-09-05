import { useCallback, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';

import { useStaffAuth } from '../auth/StaffAuth';
import {
  clinicToday,
  parseCivilDate,
  periodDayNumber,
} from '../lib/civil-date';
import { publicErrorMessage } from '../lib/errors';
import { patientsListChannel } from '../lib/realtime/patient-detail-bindings';
import { useRealtimeInvalidation } from '../lib/realtime/use-realtime-invalidation';
import { supabase } from '../lib/supabase';

type PatientRow = {
  id: string;
  clinic_label: string;
  auth_user_id: string | null;
  created_at: string;
  treatmentStatus: 'active' | 'completed' | 'cancelled' | null;
  dayN: number | null;
  inviteStatus: string | null;
};

export function PatientsPage() {
  const { session } = useStaffAuth();
  const [rows, setRows] = useState<PatientRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const cancelledRef = useRef(false);
  const initialLoadRef = useRef(true);

  const load = useCallback(async () => {
    if (session === null) {
      return;
    }

    if (initialLoadRef.current) {
      setLoading(true);
    }

    const today = clinicToday(session.timeZone);

    const [patientsRes, treatmentsRes, periodsRes, invitesRes] = await Promise.all([
      supabase
        .from('patients')
        .select('id, clinic_label, auth_user_id, created_at')
        .order('created_at', { ascending: false }),
      supabase.from('treatments').select('id, patient_id, status'),
      supabase.from('treatment_periods').select('treatment_id, started_on, ended_on'),
      supabase.from('patient_invites').select('patient_id, status').eq('status', 'pending'),
    ]);

    if (cancelledRef.current) {
      return;
    }

    const firstError =
      patientsRes.error ?? treatmentsRes.error ?? periodsRes.error ?? invitesRes.error;
    if (firstError) {
      setError(publicErrorMessage(firstError, 'Не удалось загрузить список пациентов.'));
      setLoading(false);
      return;
    }

    const treatments = treatmentsRes.data ?? [];
    const periods = periodsRes.data ?? [];
    const invites = invitesRes.data ?? [];

    setRows(
      (patientsRes.data ?? []).map((patient) => {
        const treatment = treatments.find((item) => item.patient_id === patient.id);
        const currentPeriod = periods.find(
          (item) => item.treatment_id === treatment?.id && item.ended_on === null,
        );
        const startedOn = currentPeriod ? parseCivilDate(currentPeriod.started_on) : null;
        const dayN =
          treatment?.status === 'active' && startedOn !== null
            ? periodDayNumber(startedOn, today)
            : null;
        const invite = invites.find((item) => item.patient_id === patient.id);

        return {
          id: patient.id,
          clinic_label: patient.clinic_label,
          auth_user_id: patient.auth_user_id,
          created_at: patient.created_at,
          treatmentStatus: treatment?.status ?? null,
          dayN,
          inviteStatus: invite?.status ?? null,
        };
      }),
    );
    setError(null);
    initialLoadRef.current = false;
    setLoading(false);
  }, [session]);

  useEffect(() => {
    cancelledRef.current = false;
    void load();
    return () => {
      cancelledRef.current = true;
    };
  }, [load]);

  useRealtimeInvalidation({
    enabled: session !== null,
    channels: session === null ? [] : [patientsListChannel(session.clinicId)],
    onInvalidate: load,
  });

  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <h1>Пациенты</h1>
        <Link to="/patients/new">
          <button type="button">Создать пациента</button>
        </Link>
      </div>
      {error !== null ? <p className="banner error">{error}</p> : null}
      {loading ? <p className="muted">Загрузка…</p> : null}
      {!loading && rows.length === 0 ? (
        <p className="muted">В этой клинике пока нет пациентов.</p>
      ) : null}
      {rows.length > 0 ? (
        <section>
          <table>
            <thead>
              <tr>
                <th>Метка</th>
                <th>Лечение</th>
                <th>Активация</th>
                <th>День N</th>
                <th>Приглашение</th>
                <th>Создан</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id}>
                  <td>
                    <Link to={`/patients/${row.id}`}>{row.clinic_label}</Link>
                  </td>
                  <td>{statusLabel(row.treatmentStatus)}</td>
                  <td>{row.auth_user_id === null ? 'не активирован' : 'активирован'}</td>
                  <td>{row.dayN ?? '—'}</td>
                  <td>{row.inviteStatus === 'pending' ? 'ожидает' : '—'}</td>
                  <td>{row.created_at.slice(0, 10)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      ) : null}
    </>
  );
}

function statusLabel(status: PatientRow['treatmentStatus']): string {
  if (status === 'active') {
    return 'активно';
  }
  if (status === 'completed') {
    return 'завершено';
  }
  if (status === 'cancelled') {
    return 'отменено';
  }
  return 'нет лечения';
}
