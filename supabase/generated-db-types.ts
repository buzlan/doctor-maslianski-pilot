export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      action_assignments: {
        Row: {
          catalog_item_id: string
          clinic_id: string
          created_at: string
          end_date: string
          id: string
          instruction: string | null
          start_date: string
          status: Database["public"]["Enums"]["assignment_status"]
          title: string
          treatment_id: string
          updated_at: string
        }
        Insert: {
          catalog_item_id: string
          clinic_id: string
          created_at?: string
          end_date: string
          id?: string
          instruction?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["assignment_status"]
          title: string
          treatment_id: string
          updated_at?: string
        }
        Update: {
          catalog_item_id?: string
          clinic_id?: string
          created_at?: string
          end_date?: string
          id?: string
          instruction?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["assignment_status"]
          title?: string
          treatment_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "action_assignments_catalog_item_id_fkey"
            columns: ["catalog_item_id"]
            isOneToOne: false
            referencedRelation: "action_catalog_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "action_assignments_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "action_assignments_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      action_catalog_items: {
        Row: {
          clinic_id: string
          created_at: string
          id: string
          instruction: string | null
          sort_order: number
          status: Database["public"]["Enums"]["catalog_item_status"]
          title: string
          updated_at: string
        }
        Insert: {
          clinic_id: string
          created_at?: string
          id?: string
          instruction?: string | null
          sort_order?: number
          status?: Database["public"]["Enums"]["catalog_item_status"]
          title: string
          updated_at?: string
        }
        Update: {
          clinic_id?: string
          created_at?: string
          id?: string
          instruction?: string | null
          sort_order?: number
          status?: Database["public"]["Enums"]["catalog_item_status"]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "action_catalog_items_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
        ]
      }
      action_completions: {
        Row: {
          assignment_id: string
          clinic_id: string
          completed_on: string
          created_at: string
          id: string
          patient_id: string
          treatment_id: string
        }
        Insert: {
          assignment_id: string
          clinic_id: string
          completed_on: string
          created_at?: string
          id?: string
          patient_id: string
          treatment_id: string
        }
        Update: {
          assignment_id?: string
          clinic_id?: string
          completed_on?: string
          created_at?: string
          id?: string
          patient_id?: string
          treatment_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "action_completions_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "action_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "action_completions_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "action_completions_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "action_completions_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      appointments: {
        Row: {
          at_utc: string
          clinic_id: string
          created_at: string
          id: string
          status: Database["public"]["Enums"]["appointment_record_status"]
          superseded_at: string | null
          time_zone: string
          treatment_id: string
          updated_at: string
          wall_clock: string
        }
        Insert: {
          at_utc: string
          clinic_id: string
          created_at?: string
          id?: string
          status: Database["public"]["Enums"]["appointment_record_status"]
          superseded_at?: string | null
          time_zone: string
          treatment_id: string
          updated_at?: string
          wall_clock: string
        }
        Update: {
          at_utc?: string
          clinic_id?: string
          created_at?: string
          id?: string
          status?: Database["public"]["Enums"]["appointment_record_status"]
          superseded_at?: string | null
          time_zone?: string
          treatment_id?: string
          updated_at?: string
          wall_clock?: string
        }
        Relationships: [
          {
            foreignKeyName: "appointments_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      clinic_staff: {
        Row: {
          auth_user_id: string
          clinic_id: string
          created_at: string
          display_name: string
          id: string
          role: Database["public"]["Enums"]["staff_role"]
          updated_at: string
        }
        Insert: {
          auth_user_id: string
          clinic_id: string
          created_at?: string
          display_name: string
          id?: string
          role?: Database["public"]["Enums"]["staff_role"]
          updated_at?: string
        }
        Update: {
          auth_user_id?: string
          clinic_id?: string
          created_at?: string
          display_name?: string
          id?: string
          role?: Database["public"]["Enums"]["staff_role"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clinic_staff_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
        ]
      }
      clinics: {
        Row: {
          booking_url: string | null
          created_at: string
          email: string | null
          id: string
          name: string
          phone: string | null
          time_zone: string
          updated_at: string
        }
        Insert: {
          booking_url?: string | null
          created_at?: string
          email?: string | null
          id?: string
          name: string
          phone?: string | null
          time_zone?: string
          updated_at?: string
        }
        Update: {
          booking_url?: string | null
          created_at?: string
          email?: string | null
          id?: string
          name?: string
          phone?: string | null
          time_zone?: string
          updated_at?: string
        }
        Relationships: []
      }
      diary_entries: {
        Row: {
          clinic_id: string
          created_at: string
          id: string
          pain: number
          patient_id: string
          submitted_on: string
          swelling: number
          treatment_id: string
          wellbeing: Database["public"]["Enums"]["wellbeing"]
        }
        Insert: {
          clinic_id: string
          created_at?: string
          id?: string
          pain: number
          patient_id: string
          submitted_on: string
          swelling: number
          treatment_id: string
          wellbeing: Database["public"]["Enums"]["wellbeing"]
        }
        Update: {
          clinic_id?: string
          created_at?: string
          id?: string
          pain?: number
          patient_id?: string
          submitted_on?: string
          swelling?: number
          treatment_id?: string
          wellbeing?: Database["public"]["Enums"]["wellbeing"]
        }
        Relationships: [
          {
            foreignKeyName: "diary_entries_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diary_entries_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diary_entries_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      doctor_milestone_photos: {
        Row: {
          clinic_id: string
          content_type: string
          created_at: string
          id: string
          milestone_id: string
          storage_bucket: string
          storage_path: string
          treatment_id: string
        }
        Insert: {
          clinic_id: string
          content_type: string
          created_at?: string
          id?: string
          milestone_id: string
          storage_bucket: string
          storage_path: string
          treatment_id: string
        }
        Update: {
          clinic_id?: string
          content_type?: string
          created_at?: string
          id?: string
          milestone_id?: string
          storage_bucket?: string
          storage_path?: string
          treatment_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "doctor_milestone_photos_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "doctor_milestone_photos_milestone_id_fkey"
            columns: ["milestone_id"]
            isOneToOne: false
            referencedRelation: "treatment_milestones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "doctor_milestone_photos_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      feedback_surveys: {
        Row: {
          clarity_score: number
          clinic_id: string
          created_at: string
          id: string
          patient_id: string
          submitted_at: string
          treatment_id: string
          usefulness_score: number
        }
        Insert: {
          clarity_score: number
          clinic_id: string
          created_at?: string
          id?: string
          patient_id: string
          submitted_at?: string
          treatment_id: string
          usefulness_score: number
        }
        Update: {
          clarity_score?: number
          clinic_id?: string
          created_at?: string
          id?: string
          patient_id?: string
          submitted_at?: string
          treatment_id?: string
          usefulness_score?: number
        }
        Relationships: [
          {
            foreignKeyName: "feedback_surveys_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_surveys_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_surveys_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: true
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_invites: {
        Row: {
          clinic_id: string
          consumed_at: string | null
          created_at: string
          created_by_staff_id: string
          expires_at: string
          id: string
          patient_id: string
          pilot_cohort: Database["public"]["Enums"]["pilot_cohort"]
          revoked_at: string | null
          status: Database["public"]["Enums"]["invite_status"]
          token_hash: string
          treatment_id: string
          updated_at: string
        }
        Insert: {
          clinic_id: string
          consumed_at?: string | null
          created_at?: string
          created_by_staff_id: string
          expires_at: string
          id?: string
          patient_id: string
          pilot_cohort: Database["public"]["Enums"]["pilot_cohort"]
          revoked_at?: string | null
          status?: Database["public"]["Enums"]["invite_status"]
          token_hash: string
          treatment_id: string
          updated_at?: string
        }
        Update: {
          clinic_id?: string
          consumed_at?: string | null
          created_at?: string
          created_by_staff_id?: string
          expires_at?: string
          id?: string
          patient_id?: string
          pilot_cohort?: Database["public"]["Enums"]["pilot_cohort"]
          revoked_at?: string | null
          status?: Database["public"]["Enums"]["invite_status"]
          token_hash?: string
          treatment_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "patient_invites_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_invites_created_by_staff_id_fkey"
            columns: ["created_by_staff_id"]
            isOneToOne: false
            referencedRelation: "clinic_staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_invites_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_invites_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      patient_photos: {
        Row: {
          clinic_id: string
          content_type: string
          created_at: string
          id: string
          patient_id: string
          slot: number
          storage_bucket: string
          storage_path: string
          submitted_on: string
          treatment_id: string
        }
        Insert: {
          clinic_id: string
          content_type: string
          created_at?: string
          id?: string
          patient_id: string
          slot: number
          storage_bucket: string
          storage_path: string
          submitted_on: string
          treatment_id: string
        }
        Update: {
          clinic_id?: string
          content_type?: string
          created_at?: string
          id?: string
          patient_id?: string
          slot?: number
          storage_bucket?: string
          storage_path?: string
          submitted_on?: string
          treatment_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "patient_photos_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_photos_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "patient_photos_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      patients: {
        Row: {
          auth_user_id: string | null
          clinic_id: string
          clinic_label: string
          consent_document_version: string | null
          created_at: string
          id: string
          pilot_cohort: Database["public"]["Enums"]["pilot_cohort"] | null
          pilot_consent_accepted_at: string | null
          privacy_accepted_at: string | null
          updated_at: string
        }
        Insert: {
          auth_user_id?: string | null
          clinic_id: string
          clinic_label: string
          consent_document_version?: string | null
          created_at?: string
          id?: string
          pilot_cohort?: Database["public"]["Enums"]["pilot_cohort"] | null
          pilot_consent_accepted_at?: string | null
          privacy_accepted_at?: string | null
          updated_at?: string
        }
        Update: {
          auth_user_id?: string | null
          clinic_id?: string
          clinic_label?: string
          consent_document_version?: string | null
          created_at?: string
          id?: string
          pilot_cohort?: Database["public"]["Enums"]["pilot_cohort"] | null
          pilot_consent_accepted_at?: string | null
          privacy_accepted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "patients_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
        ]
      }
      product_events: {
        Row: {
          clarity_score: number | null
          clinic_id: string | null
          created_at: string
          entity_id: string | null
          id: string
          name: string
          occurred_at: string
          patient_id: string | null
          pilot_cohort: Database["public"]["Enums"]["pilot_cohort"]
          treatment_id: string | null
          usefulness_score: number | null
        }
        Insert: {
          clarity_score?: number | null
          clinic_id?: string | null
          created_at?: string
          entity_id?: string | null
          id?: string
          name: string
          occurred_at?: string
          patient_id?: string | null
          pilot_cohort: Database["public"]["Enums"]["pilot_cohort"]
          treatment_id?: string | null
          usefulness_score?: number | null
        }
        Update: {
          clarity_score?: number | null
          clinic_id?: string | null
          created_at?: string
          entity_id?: string | null
          id?: string
          name?: string
          occurred_at?: string
          patient_id?: string | null
          pilot_cohort?: Database["public"]["Enums"]["pilot_cohort"]
          treatment_id?: string | null
          usefulness_score?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "product_events_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_events_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_events_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      treatment_milestones: {
        Row: {
          clinic_id: string
          created_at: string
          id: string
          kind: string | null
          occurred_on: string | null
          title: string
          treatment_id: string
          updated_at: string
        }
        Insert: {
          clinic_id: string
          created_at?: string
          id?: string
          kind?: string | null
          occurred_on?: string | null
          title: string
          treatment_id: string
          updated_at?: string
        }
        Update: {
          clinic_id?: string
          created_at?: string
          id?: string
          kind?: string | null
          occurred_on?: string | null
          title?: string
          treatment_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "treatment_milestones_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "treatment_milestones_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      treatment_periods: {
        Row: {
          clinic_id: string
          created_at: string
          ended_on: string | null
          id: string
          started_on: string
          treatment_id: string
          updated_at: string
        }
        Insert: {
          clinic_id: string
          created_at?: string
          ended_on?: string | null
          id?: string
          started_on: string
          treatment_id: string
          updated_at?: string
        }
        Update: {
          clinic_id?: string
          created_at?: string
          ended_on?: string | null
          id?: string
          started_on?: string
          treatment_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "treatment_periods_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "treatment_periods_treatment_id_fkey"
            columns: ["treatment_id"]
            isOneToOne: false
            referencedRelation: "treatments"
            referencedColumns: ["id"]
          },
        ]
      }
      treatments: {
        Row: {
          cancelled_at: string | null
          clinic_id: string
          completed_at: string | null
          created_at: string
          id: string
          patient_id: string
          pilot_cohort: Database["public"]["Enums"]["pilot_cohort"] | null
          status: Database["public"]["Enums"]["treatment_status"]
          treatment_context: string
          updated_at: string
        }
        Insert: {
          cancelled_at?: string | null
          clinic_id: string
          completed_at?: string | null
          created_at?: string
          id?: string
          patient_id: string
          pilot_cohort?: Database["public"]["Enums"]["pilot_cohort"] | null
          status?: Database["public"]["Enums"]["treatment_status"]
          treatment_context?: string
          updated_at?: string
        }
        Update: {
          cancelled_at?: string | null
          clinic_id?: string
          completed_at?: string | null
          created_at?: string
          id?: string
          patient_id?: string
          pilot_cohort?: Database["public"]["Enums"]["pilot_cohort"] | null
          status?: Database["public"]["Enums"]["treatment_status"]
          treatment_context?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "treatments_clinic_id_fkey"
            columns: ["clinic_id"]
            isOneToOne: false
            referencedRelation: "clinics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "treatments_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      activate_patient_from_invite: {
        Args: {
          p_auth_user_id: string
          p_consent_document_version: string
          p_pilot_consent_accepted: boolean
          p_privacy_accepted: boolean
          p_token_hash_hex: string
        }
        Returns: {
          bound_auth_user_id: string
          outcome: string
        }[]
      }
      assert_storage_ref: {
        Args: { p_bucket: string; p_content_type: string; p_path: string }
        Returns: undefined
      }
      assign_catalog_item_to_treatment: {
        Args: {
          p_catalog_item_id: string
          p_end_date: string
          p_start_date: string
          p_treatment_id: string
        }
        Returns: string
      }
      create_unactivated_patient: {
        Args: { p_clinic_label: string; p_started_on: string }
        Returns: Json
      }
      current_patient_clinic_id: { Args: never; Returns: string }
      current_patient_id: { Args: never; Returns: string }
      current_staff_clinic_id: { Args: never; Returns: string }
      is_staff: { Args: never; Returns: boolean }
      issue_patient_invite: {
        Args: {
          p_pilot_cohort: Database["public"]["Enums"]["pilot_cohort"]
          p_treatment_id: string
          p_ttl_days?: number
        }
        Returns: Json
      }
      lookup_patient_invite_by_hash: {
        Args: { p_token_hash_hex: string }
        Returns: {
          bound_auth_user_id: string
          consumed_at: string
          expires_at: string
          invite_id: string
          invite_status: Database["public"]["Enums"]["invite_status"]
          recovery_eligible: boolean
        }[]
      }
      patient_belongs_to_clinic: {
        Args: { p_clinic_id: string; p_patient_id: string }
        Returns: boolean
      }
      replace_current_appointment: {
        Args: { p_treatment_id: string; p_wall_clock: string }
        Returns: string
      }
      revoke_patient_invite: {
        Args: { p_invite_id: string }
        Returns: undefined
      }
      start_new_treatment_period: {
        Args: {
          p_ended_on: string
          p_started_on: string
          p_treatment_id: string
        }
        Returns: string
      }
      storage_doctor_photo_readable: {
        Args: { object_name: string }
        Returns: boolean
      }
      storage_doctor_photo_writable: {
        Args: { object_name: string }
        Returns: boolean
      }
      storage_path_parts: { Args: { object_name: string }; Returns: string[] }
      storage_patient_photo_readable: {
        Args: { object_name: string }
        Returns: boolean
      }
      storage_patient_photo_writable: {
        Args: { object_name: string }
        Returns: boolean
      }
      treatment_in_staff_clinic: {
        Args: { p_treatment_id: string }
        Returns: boolean
      }
      treatment_owned_by_current_patient: {
        Args: { p_treatment_id: string }
        Returns: boolean
      }
    }
    Enums: {
      appointment_record_status: "current" | "superseded"
      assignment_status: "active" | "disabled"
      catalog_item_status: "draft" | "approved"
      invite_status: "pending" | "consumed" | "revoked" | "expired"
      pilot_cohort: "internal_dry_run" | "closed_beta" | "clinic_pilot"
      staff_role: "staff"
      treatment_status: "active" | "completed" | "cancelled"
      wellbeing: "better" | "unchanged" | "worse"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      appointment_record_status: ["current", "superseded"],
      assignment_status: ["active", "disabled"],
      catalog_item_status: ["draft", "approved"],
      invite_status: ["pending", "consumed", "revoked", "expired"],
      pilot_cohort: ["internal_dry_run", "closed_beta", "clinic_pilot"],
      staff_role: ["staff"],
      treatment_status: ["active", "completed", "cancelled"],
      wellbeing: ["better", "unchanged", "worse"],
    },
  },
} as const

