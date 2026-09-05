export type PostgresChangeEvent = 'INSERT' | 'UPDATE' | 'DELETE' | '*';

export type PostgresChangeBinding = {
  table: string;
  event: PostgresChangeEvent;
  filter?: string;
};

export type RealtimeInvalidationChannel = {
  name: string;
  private?: boolean;
  broadcastEvent?: string;
  postgresChanges: PostgresChangeBinding[];
};

export function treatmentBroadcastTopic(treatmentId: string): string {
  return `treatment:${treatmentId}`;
}

export function patientsListChannel(clinicId: string): RealtimeInvalidationChannel {
  return {
    name: `clinic-review:patients-list:${clinicId}`,
    postgresChanges: [
      { table: 'patients', event: 'INSERT' },
      { table: 'patients', event: 'UPDATE' },
    ],
  };
}

export function patientDetailChannels(input: {
  patientId: string;
  treatmentId: string | null;
}): RealtimeInvalidationChannel[] {
  const channels: RealtimeInvalidationChannel[] = [
    {
      name: `clinic-review:patient:${input.patientId}`,
      postgresChanges: [
        { table: 'patients', event: 'UPDATE', filter: `id=eq.${input.patientId}` },
      ],
    },
  ];

  if (input.treatmentId === null) {
    return channels;
  }

  channels.push({
    name: treatmentBroadcastTopic(input.treatmentId),
    private: true,
    broadcastEvent: 'invalidate',
    postgresChanges: [
      {
        table: 'diary_entries',
        event: 'INSERT',
        filter: `treatment_id=eq.${input.treatmentId}`,
      },
      {
        table: 'patient_photos',
        event: 'INSERT',
        filter: `treatment_id=eq.${input.treatmentId}`,
      },
      {
        table: 'feedback_surveys',
        event: 'INSERT',
        filter: `treatment_id=eq.${input.treatmentId}`,
      },
    ],
  });

  return channels;
}

export function channelBindsActionCompletions(
  channels: readonly RealtimeInvalidationChannel[],
): boolean {
  return channels.some((channel) =>
    channel.postgresChanges.some((binding) => binding.table === 'action_completions'),
  );
}
