import { useCallback, useEffect, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';

import { useStaffAuth } from '../auth/StaffAuth';
import { AppointmentsPanel, type AppointmentRow } from '../features/AppointmentsPanel';
import {
  AssignmentsPanel,
  type AssignmentRow,
  type CatalogOption,
  type CompletionRow,
} from '../features/AssignmentsPanel';
import { DiaryPanel, type DiaryRow } from '../features/DiaryPanel';
import { FeedbackPanel, type FeedbackRow } from '../features/FeedbackPanel';
import { InvitePanel } from '../features/InvitePanel';
import {
  MilestonesPanel,
  type DoctorPhotoRow,
  type MilestoneRow,
} from '../features/MilestonesPanel';
import { PatientPhotosPanel, type PatientPhotoRow } from '../features/PatientPhotosPanel';
import { PeriodsPanel, type PeriodRow } from '../features/PeriodsPanel';
import { assignmentCompletionView } from '../lib/completions';
import {
  clinicToday,
  formatCivilDate,
  parseCivilDate,
  periodDayNumber,
} from '../lib/civil-date';
import {
  avatarTone,
  initialsFromLabel,
  shortId,
  treatmentStatusLabel,
  treatmentStatusTone,
} from '../lib/display';
import { publicErrorMessage } from '../lib/errors';
import { patientDetailChannels } from '../lib/realtime/patient-detail-bindings';
import { useRealtimeInvalidation } from '../lib/realtime/use-realtime-invalidation';
import { supabase } from '../lib/supabase';
import { Avatar, Badge, EmptyState, KpiCard, PageNotice } from '../ui/primitives';
import { TabPanel, Tabs } from '../ui/tabs';

type PatientHeader = {
  id: string;
  clinic_label: string;
  auth_user_id: string | null;
};

type TreatmentRow = {
  id: string;
  status: 'active' | 'completed' | 'cancelled';
  completed_at: string | null;
};

type DetailState = {
  patient: PatientHeader;
  treatment: TreatmentRow | null;
  periods: PeriodRow[];
  assignments: AssignmentRow[];
  completions: CompletionRow[];
  catalog: CatalogOption[];
  diary: DiaryRow[];
  patientPhotos: PatientPhotoRow[];
  milestones: MilestoneRow[];
  doctorPhotos: DoctorPhotoRow[];
  appointments: AppointmentRow[];
  feedback: FeedbackRow | null;
};

type DetailTab =
  | 'overview'
  | 'assignments'
  | 'diary'
  | 'photos'
  | 'visits'
  | 'access'
  | 'feedback';

const TABS: { id: DetailTab; label: string }[] = [
  { id: 'overview', label: 'Обзор' },
  { id: 'assignments', label: 'Назначения' },
  { id: 'diary', label: 'Дневник' },
  { id: 'photos', label: 'Фото' },
  { id: 'visits', label: 'Визиты' },
  { id: 'access', label: 'Доступ' },
  { id: 'feedback', label: 'Отзыв' },
];

export function PatientDetailPage() {
  const { patientId } = useParams();
  const { session } = useStaffAuth();
  const [state, setState] = useState<DetailState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [tab, setTab] = useState<DetailTab>('overview');
  const loadGenerationRef = useRef(0);

  const load = useCallback(async () => {
    if (patientId === undefined) {
      return;
    }
    const generation = loadGenerationRef.current + 1;
    loadGenerationRef.current = generation;

    const { data: patient, error: patientError } = await supabase
      .from('patients')
      .select('id, clinic_label, auth_user_id')
      .eq('id', patientId)
      .maybeSingle();

    if (patientError || patient === null) {
      if (loadGenerationRef.current !== generation) {
        return;
      }
      setState(null);
      setError(publicErrorMessage(patientError, 'Пациент не найден.'));
      return;
    }

    const { data: treatments, error: treatmentError } = await supabase
      .from('treatments')
      .select('id, status, completed_at, created_at')
      .eq('patient_id', patient.id)
      .order('created_at', { ascending: false });

    if (treatmentError) {
      if (loadGenerationRef.current !== generation) {
        return;
      }
      setError(publicErrorMessage(treatmentError, 'Не удалось загрузить лечение.'));
      return;
    }

    const treatment =
      treatments?.find((item) => item.status === 'active') ?? treatments?.[0] ?? null;

    if (treatment === null) {
      if (loadGenerationRef.current !== generation) {
        return;
      }
      setState({
        patient,
        treatment: null,
        periods: [],
        assignments: [],
        completions: [],
        catalog: [],
        diary: [],
        patientPhotos: [],
        milestones: [],
        doctorPhotos: [],
        appointments: [],
        feedback: null,
      });
      setError(null);
      return;
    }

    const [
      periodsRes,
      assignmentsRes,
      completionsRes,
      catalogRes,
      diaryRes,
      photosRes,
      milestonesRes,
      doctorPhotosRes,
      appointmentsRes,
      feedbackRes,
    ] = await Promise.all([
      supabase
        .from('treatment_periods')
        .select('id, started_on, ended_on')
        .eq('treatment_id', treatment.id)
        .order('started_on'),
      supabase
        .from('action_assignments')
        .select('id, title, instruction, start_date, end_date, status')
        .eq('treatment_id', treatment.id)
        .order('created_at'),
      supabase
        .from('action_completions')
        .select('assignment_id, completed_on')
        .eq('treatment_id', treatment.id)
        .order('completed_on'),
      supabase
        .from('action_catalog_items')
        .select('id, title')
        .eq('status', 'approved')
        .order('sort_order'),
      supabase
        .from('diary_entries')
        .select('id, submitted_on, pain, swelling, wellbeing')
        .eq('treatment_id', treatment.id)
        .order('submitted_on', { ascending: false }),
      supabase
        .from('patient_photos')
        .select('id, submitted_on, slot, storage_path')
        .eq('treatment_id', treatment.id)
        .order('submitted_on', { ascending: false }),
      supabase
        .from('treatment_milestones')
        .select('id, title, occurred_on')
        .eq('treatment_id', treatment.id)
        .order('occurred_on'),
      supabase
        .from('doctor_milestone_photos')
        .select('id, milestone_id, storage_path, content_type')
        .eq('treatment_id', treatment.id)
        .order('created_at'),
      supabase
        .from('appointments')
        .select('id, status, wall_clock, superseded_at')
        .eq('treatment_id', treatment.id)
        .order('created_at', { ascending: false }),
      supabase
        .from('feedback_surveys')
        .select('usefulness_score, clarity_score, submitted_at')
        .eq('treatment_id', treatment.id)
        .maybeSingle(),
    ]);

    const firstError =
      periodsRes.error ??
      assignmentsRes.error ??
      completionsRes.error ??
      catalogRes.error ??
      diaryRes.error ??
      photosRes.error ??
      milestonesRes.error ??
      doctorPhotosRes.error ??
      appointmentsRes.error ??
      feedbackRes.error;

    if (firstError) {
      if (loadGenerationRef.current !== generation) {
        return;
      }
      setError(publicErrorMessage(firstError, 'Не удалось загрузить карточку.'));
      return;
    }

    if (loadGenerationRef.current !== generation) {
      return;
    }

    setState({
      patient,
      treatment,
      periods: periodsRes.data ?? [],
      assignments: assignmentsRes.data ?? [],
      completions: completionsRes.data ?? [],
      catalog: catalogRes.data ?? [],
      diary: diaryRes.data ?? [],
      patientPhotos: photosRes.data ?? [],
      milestones: milestonesRes.data ?? [],
      doctorPhotos: doctorPhotosRes.data ?? [],
      appointments: appointmentsRes.data ?? [],
      feedback: feedbackRes.data,
    });
    setError(null);
  }, [patientId]);

  useEffect(() => {
    void load();
  }, [load]);

  const scopedTreatmentId =
    state !== null && patientId !== undefined && state.patient.id === patientId
      ? (state.treatment?.id ?? null)
      : null;

  useRealtimeInvalidation({
    enabled: patientId !== undefined,
    channels:
      patientId === undefined
        ? []
        : patientDetailChannels({
            patientId,
            treatmentId: scopedTreatmentId,
          }),
    onInvalidate: load,
  });

  useEffect(() => {
    function refetchIfVisible() {
      if (document.visibilityState === 'visible') {
        void load();
      }
    }

    function onFocus() {
      void load();
    }

    document.addEventListener('visibilitychange', refetchIfVisible);
    window.addEventListener('focus', onFocus);
    return () => {
      document.removeEventListener('visibilitychange', refetchIfVisible);
      window.removeEventListener('focus', onFocus);
    };
  }, [load]);

  async function refresh() {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  }

  async function completeTreatment() {
    if (state?.treatment === null || state === null) {
      return;
    }
    if (
      !window.confirm(
        'Завершить лечение? Пациент увидит экран завершения. Это действие нужно подтвердить сознательно.',
      )
    ) {
      return;
    }
    setBusy(true);
    const { error: updateError } = await supabase
      .from('treatments')
      .update({
        status: 'completed',
        completed_at: new Date().toISOString(),
      })
      .eq('id', state.treatment.id);
    setBusy(false);
    if (updateError) {
      setError(publicErrorMessage(updateError, 'Не удалось завершить лечение.'));
      return;
    }
    await load();
  }

  if (session === null) {
    return null;
  }

  const today = formatCivilDate(clinicToday(session.timeZone));
  const currentPeriod = state?.periods.find((period) => period.ended_on === null);
  const startedOn = currentPeriod === undefined ? null : parseCivilDate(currentPeriod.started_on);
  const dayN =
    state?.treatment?.status === 'active' && startedOn !== null
      ? periodDayNumber(startedOn, clinicToday(session.timeZone))
      : null;

  const dueToday = (state?.assignments ?? []).filter(
    (assignment) =>
      assignment.status === 'active' &&
      assignment.start_date <= today &&
      assignment.end_date >= today,
  );
  const completedTodayCount = dueToday.filter(
    (assignment) => assignmentCompletionView(state?.completions ?? [], assignment.id, today).completedToday,
  ).length;
  const diaryToday = (state?.diary ?? []).some((entry) => entry.submitted_on === today);

  return (
    <section className="workspace">
      {error !== null ? <PageNotice tone="error">{error}</PageNotice> : null}
      {state === null ? (
        <p className="muted">Загрузка…</p>
      ) : (
        <>
          <div className="detail-header">
            <div className="detail-identity">
              <Avatar
                label={initialsFromLabel(state.patient.clinic_label)}
                tone={avatarTone(state.patient.clinic_label)}
                size="lg"
              />
              <div>
                <h1 className="detail-title">{state.patient.clinic_label}</h1>
                <div className="detail-meta">
                  <span>{shortId(state.patient.id)}</span>
                  <Badge tone={treatmentStatusTone(state.treatment?.status ?? null)}>
                    {treatmentStatusLabel(state.treatment?.status ?? null)}
                  </Badge>
                  <Badge tone={state.patient.auth_user_id === null ? 'warning' : 'success'}>
                    {state.patient.auth_user_id === null ? 'не активирован' : 'активирован'}
                  </Badge>
                  {dayN !== null ? <span>День {dayN}</span> : null}
                  {currentPeriod !== undefined ? <span>период с {currentPeriod.started_on}</span> : null}
                </div>
              </div>
            </div>
            <div className="detail-actions">
              <button
                type="button"
                className="secondary"
                disabled={refreshing}
                onClick={() => void refresh()}
              >
                {refreshing ? 'Обновление…' : 'Обновить'}
              </button>
              {state.treatment?.status === 'active' ? (
                <button
                  type="button"
                  className="danger"
                  disabled={busy}
                  onClick={() => void completeTreatment()}
                >
                  Завершить лечение
                </button>
              ) : null}
            </div>
          </div>

          {state.treatment === null ? (
            <EmptyState title="У пациента нет лечения" />
          ) : (
            <>
              <div className="kpi-row">
                <KpiCard
                  label="Период"
                  value={dayN !== null ? `День ${dayN}` : '—'}
                  hint={currentPeriod === undefined ? 'Нет текущего периода' : `с ${currentPeriod.started_on}`}
                  tone="blue"
                />
                <KpiCard
                  label="Назначения сегодня"
                  value={`${completedTodayCount} / ${dueToday.length}`}
                  hint={dueToday.length === 0 ? 'Нет активных на сегодня' : 'отмечено из активных'}
                  tone="green"
                  current={completedTodayCount}
                  total={dueToday.length}
                />
                <KpiCard
                  label="Дневник"
                  value={diaryToday ? 'есть сегодня' : 'нет сегодня'}
                  hint={`${state.diary.length} записей всего`}
                  tone="amber"
                />
                <KpiCard
                  label="Фото пациента"
                  value={String(state.patientPhotos.length)}
                  hint={state.feedback === null ? 'отзыв ещё не отправлен' : 'отзыв получен'}
                  tone="purple"
                />
              </div>

              <Tabs items={TABS} value={tab} onChange={setTab} />

              <TabPanel active={tab === 'overview'}>
                <div className="section-grid">
                  <PeriodsPanel
                    treatmentId={state.treatment.id}
                    treatmentActive={state.treatment.status === 'active'}
                    periods={state.periods}
                    defaultDate={today}
                    onChanged={load}
                  />
                  <AppointmentsPanel
                    treatmentId={state.treatment.id}
                    treatmentActive={state.treatment.status === 'active'}
                    appointments={state.appointments}
                    onChanged={load}
                  />
                </div>
              </TabPanel>
              <TabPanel active={tab === 'assignments'}>
                <AssignmentsPanel
                  treatmentId={state.treatment.id}
                  treatmentActive={state.treatment.status === 'active'}
                  assignments={state.assignments}
                  completions={state.completions}
                  catalog={state.catalog}
                  defaultDate={today}
                  onChanged={load}
                />
              </TabPanel>
              <TabPanel active={tab === 'diary'}>
                <DiaryPanel entries={state.diary} />
              </TabPanel>
              <TabPanel active={tab === 'photos'}>
                <PatientPhotosPanel photos={state.patientPhotos} />
              </TabPanel>
              <TabPanel active={tab === 'visits'}>
                <MilestonesPanel
                  treatmentId={state.treatment.id}
                  treatmentActive={state.treatment.status === 'active'}
                  milestones={state.milestones}
                  photos={state.doctorPhotos}
                  defaultDate={today}
                  onChanged={load}
                />
              </TabPanel>
              <TabPanel active={tab === 'access'}>
                <InvitePanel
                  treatmentId={state.treatment.id}
                  activated={state.patient.auth_user_id !== null}
                  treatmentActive={state.treatment.status === 'active'}
                  onChanged={load}
                />
              </TabPanel>
              <TabPanel active={tab === 'feedback'}>
                <FeedbackPanel feedback={state.feedback} />
              </TabPanel>
            </>
          )}
        </>
      )}
    </section>
  );
}
