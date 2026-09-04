-- Row Level Security. Authorization is not frontend filtering.

ALTER TABLE public.clinics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinic_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_catalog_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treatments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treatment_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treatment_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diary_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doctor_milestone_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback_surveys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_invites ENABLE ROW LEVEL SECURITY;

-- clinics
CREATE POLICY clinics_select_own ON public.clinics
  FOR SELECT TO authenticated
  USING (
    id = public.current_staff_clinic_id()
    OR id = public.current_patient_clinic_id()
  );

-- clinic_staff: staff of the same clinic only
CREATE POLICY clinic_staff_select_own_clinic ON public.clinic_staff
  FOR SELECT TO authenticated
  USING (clinic_id = public.current_staff_clinic_id());

-- patients
CREATE POLICY patients_select ON public.patients
  FOR SELECT TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY patients_insert_staff ON public.patients
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY patients_update_staff ON public.patients
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

-- action_catalog_items: staff only
CREATE POLICY catalog_select_staff ON public.action_catalog_items
  FOR SELECT TO authenticated
  USING (clinic_id = public.current_staff_clinic_id());

CREATE POLICY catalog_insert_staff ON public.action_catalog_items
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY catalog_update_staff ON public.action_catalog_items
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

-- treatments: patients SELECT own; staff SELECT/INSERT/UPDATE clinic
CREATE POLICY treatments_select ON public.treatments
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY treatments_insert_staff ON public.treatments
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY treatments_update_staff ON public.treatments
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

-- Shared child policies: SELECT if own treatment or staff clinic; writes staff-only
-- unless noted.

CREATE POLICY treatment_periods_select ON public.treatment_periods
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY treatment_periods_insert_staff ON public.treatment_periods
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY treatment_periods_update_staff ON public.treatment_periods
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY treatment_milestones_select ON public.treatment_milestones
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY treatment_milestones_insert_staff ON public.treatment_milestones
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY treatment_milestones_update_staff ON public.treatment_milestones
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY action_assignments_select ON public.action_assignments
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY action_assignments_insert_staff ON public.action_assignments
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY action_assignments_update_staff ON public.action_assignments
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY action_completions_select ON public.action_completions
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY action_completions_insert_patient ON public.action_completions
  FOR INSERT TO authenticated
  WITH CHECK (
    patient_id = public.current_patient_id()
    AND public.treatment_owned_by_current_patient(treatment_id)
  );

CREATE POLICY action_completions_delete_patient ON public.action_completions
  FOR DELETE TO authenticated
  USING (
    patient_id = public.current_patient_id()
    AND public.treatment_owned_by_current_patient(treatment_id)
  );

CREATE POLICY appointments_select ON public.appointments
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY appointments_insert_staff ON public.appointments
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY appointments_update_staff ON public.appointments
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY diary_entries_select ON public.diary_entries
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY diary_entries_insert_patient ON public.diary_entries
  FOR INSERT TO authenticated
  WITH CHECK (
    patient_id = public.current_patient_id()
    AND public.treatment_owned_by_current_patient(treatment_id)
  );

CREATE POLICY patient_photos_select ON public.patient_photos
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY patient_photos_insert_patient ON public.patient_photos
  FOR INSERT TO authenticated
  WITH CHECK (
    patient_id = public.current_patient_id()
    AND public.treatment_owned_by_current_patient(treatment_id)
  );

CREATE POLICY doctor_milestone_photos_select ON public.doctor_milestone_photos
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY doctor_milestone_photos_insert_staff ON public.doctor_milestone_photos
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY feedback_surveys_select ON public.feedback_surveys
  FOR SELECT TO authenticated
  USING (
    public.treatment_owned_by_current_patient(treatment_id)
    OR clinic_id = public.current_staff_clinic_id()
  );

CREATE POLICY feedback_surveys_insert_patient ON public.feedback_surveys
  FOR INSERT TO authenticated
  WITH CHECK (
    patient_id = public.current_patient_id()
    AND public.treatment_owned_by_current_patient(treatment_id)
  );

-- product_events: clinic_id is derived in a BEFORE trigger before WITH CHECK.
CREATE POLICY product_events_select_staff ON public.product_events
  FOR SELECT TO authenticated
  USING (clinic_id = public.current_staff_clinic_id());

CREATE POLICY product_events_insert_patient ON public.product_events
  FOR INSERT TO authenticated
  WITH CHECK (
    public.current_patient_id() IS NOT NULL
    AND (
      (
        patient_id = public.current_patient_id()
        AND (
          treatment_id IS NULL
          OR public.treatment_owned_by_current_patient(treatment_id)
        )
      )
      OR (patient_id IS NULL AND treatment_id IS NULL)
    )
  );

CREATE POLICY product_events_insert_staff ON public.product_events
  FOR INSERT TO authenticated
  WITH CHECK (
    public.current_staff_clinic_id() IS NOT NULL
    AND (
      clinic_id = public.current_staff_clinic_id()
      OR clinic_id IS NULL
    )
  );

-- patient_invites: staff only
CREATE POLICY patient_invites_select_staff ON public.patient_invites
  FOR SELECT TO authenticated
  USING (clinic_id = public.current_staff_clinic_id());

CREATE POLICY patient_invites_insert_staff ON public.patient_invites
  FOR INSERT TO authenticated
  WITH CHECK (clinic_id = public.current_staff_clinic_id());

CREATE POLICY patient_invites_update_staff ON public.patient_invites
  FOR UPDATE TO authenticated
  USING (clinic_id = public.current_staff_clinic_id())
  WITH CHECK (clinic_id = public.current_staff_clinic_id());
