import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';

import { useStaffAuth } from '../auth/StaffAuth';
import { clinicToday, parseCivilDate, periodDayNumber } from '../lib/civil-date';
import {
  avatarTone,
  initialsFromLabel,
  treatmentStatusLabel,
  type TreatmentStatus,
} from '../lib/display';
import { publicErrorMessage } from '../lib/errors';
import { patientsListChannel } from '../lib/realtime/patient-detail-bindings';
import { useRealtimeInvalidation } from '../lib/realtime/use-realtime-invalidation';
import { supabase } from '../lib/supabase';
import { Avatar, EmptyState, PageNotice } from '../ui/primitives';

export type PatientListRow = {
  id: string;
  clinic_label: string;
  auth_user_id: string | null;
  created_at: string;
  treatmentStatus: TreatmentStatus;
  dayN: number | null;
  inviteStatus: string | null;
};

type Filter = 'all' | 'active' | 'completed' | 'unactivated';

export function PatientListPanel() {
  const { session } = useStaffAuth();
  const { patientId } = useParams();
  const navigate = useNavigate();
  const [rows, setRows] = useState<PatientListRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
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

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return rows.filter((row) => {
      if (needle.length > 0 && !row.clinic_label.toLowerCase().includes(needle)) {
        return false;
      }
      if (filter === 'active') {
        return row.treatmentStatus === 'active';
      }
      if (filter === 'completed') {
        return row.treatmentStatus === 'completed';
      }
      if (filter === 'unactivated') {
        return row.auth_user_id === null;
      }
      return true;
    });
  }, [filter, query, rows]);

  return (
    <aside className="list-pane">
      <div className="list-pane-header">
        <h1>Пациенты</h1>
        <div className="list-tools">
          <div className="search">
            <span className="search-icon" aria-hidden="true">
              ⌕
            </span>
            <input
              type="search"
              placeholder="Поиск по метке"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
          </div>
          <select value={filter} onChange={(event) => setFilter(event.target.value as Filter)}>
            <option value="all">Все пациенты</option>
            <option value="active">Активное лечение</option>
            <option value="completed">Завершённые</option>
            <option value="unactivated">Не активированы</option>
          </select>
          <button type="button" onClick={() => navigate('/patients/new')}>
            Создать пациента
          </button>
        </div>
      </div>
      <div className="list-body">
        {error !== null ? <PageNotice tone="error">{error}</PageNotice> : null}
        {loading ? <p className="muted">Загрузка…</p> : null}
        {!loading && visible.length === 0 ? (
          <EmptyState
            title="Пациентов не найдено"
            body={
              rows.length === 0
                ? 'В этой клинике пока нет пациентов.'
                : 'Измените поиск или фильтр.'
            }
          />
        ) : null}
        {visible.map((row) => {
          const selected = row.id === patientId;
          const activation = row.auth_user_id === null ? 'не активирован' : 'активирован';
          const invite = row.inviteStatus === 'pending' ? ' · приглашение' : '';
          const day = row.dayN !== null ? `День ${row.dayN}` : treatmentStatusLabel(row.treatmentStatus);
          return (
            <button
              key={row.id}
              type="button"
              className={selected ? 'patient-row is-selected' : 'patient-row'}
              onClick={() => navigate(`/patients/${row.id}`)}
            >
              <Avatar
                label={initialsFromLabel(row.clinic_label)}
                tone={avatarTone(row.clinic_label)}
              />
              <span className="patient-row-copy">
                <span className="patient-row-title">{row.clinic_label}</span>
                <span className="patient-row-meta">
                  {activation}
                  {invite}
                </span>
              </span>
              <span className="patient-row-meta">{day}</span>
            </button>
          );
        })}
      </div>
    </aside>
  );
}
