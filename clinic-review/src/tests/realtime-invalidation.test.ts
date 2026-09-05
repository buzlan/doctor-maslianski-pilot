import { afterEach, describe, expect, it, vi } from 'vitest';

import { createInvalidationController } from '../lib/realtime/create-invalidation-controller';
import {
  channelBindsActionCompletions,
  patientDetailChannels,
  patientsListChannel,
  treatmentBroadcastTopic,
} from '../lib/realtime/patient-detail-bindings';
import {
  subscribeRealtimeInvalidation,
  type RealtimeChannelHandle,
  type RealtimeInvalidationClient,
} from '../lib/realtime/subscribe-realtime-invalidation';

afterEach(() => {
  vi.useRealTimers();
});

describe('createInvalidationController', () => {
  it('coalesces a burst into one run', async () => {
    vi.useFakeTimers();
    const run = vi.fn(async () => undefined);
    const controller = createInvalidationController({ run, debounceMs: 200 });

    controller.invalidate();
    controller.invalidate();
    controller.invalidate();
    controller.invalidate();
    controller.invalidate();

    expect(run).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(200);
    expect(run).toHaveBeenCalledTimes(1);
    controller.dispose();
  });

  it('runs at most one follow-up when invalidated during an in-flight run', async () => {
    vi.useFakeTimers();
    let release!: () => void;
    const first = new Promise<void>((resolve) => {
      release = resolve;
    });
    const run = vi.fn(async () => {
      if (run.mock.calls.length === 1) {
        await first;
      }
    });
    const controller = createInvalidationController({ run, debounceMs: 200 });

    controller.invalidate();
    await vi.advanceTimersByTimeAsync(200);
    expect(run).toHaveBeenCalledTimes(1);

    controller.invalidate();
    controller.invalidate();
    await vi.advanceTimersByTimeAsync(200);
    release();
    await vi.advanceTimersByTimeAsync(0);
    await Promise.resolve();
    await Promise.resolve();

    expect(run).toHaveBeenCalledTimes(2);
    controller.dispose();
  });
});

describe('patient detail bindings', () => {
  it('opens a private treatment broadcast and never binds action_completions', () => {
    const channels = patientDetailChannels({
      patientId: 'patient-1',
      treatmentId: 'treatment-1',
    });

    expect(channels.map((channel) => channel.name)).toEqual([
      'clinic-review:patient:patient-1',
      'treatment:treatment-1',
    ]);
    expect(treatmentBroadcastTopic('treatment-1')).toBe('treatment:treatment-1');
    expect(channels[1]?.private).toBe(true);
    expect(channels[1]?.broadcastEvent).toBe('invalidate');
    expect(channelBindsActionCompletions(channels)).toBe(false);
    expect(
      channels.flatMap((channel) => channel.postgresChanges.map((binding) => binding.table)),
    ).toEqual(['patients', 'diary_entries', 'patient_photos', 'feedback_surveys']);
  });

  it('subscribes only to patients when there is no treatment', () => {
    const channels = patientDetailChannels({
      patientId: 'patient-1',
      treatmentId: null,
    });

    expect(channels).toHaveLength(1);
    expect(channels[0]?.postgresChanges).toEqual([
      { table: 'patients', event: 'UPDATE', filter: 'id=eq.patient-1' },
    ]);
  });
});

type RecordedBinding = {
  type: string;
  filter: Record<string, unknown>;
};

function createFakeRealtimeClient() {
  const removed: string[] = [];
  const opened: Array<{
    name: string;
    private?: boolean;
    bindings: RecordedBinding[];
    callbacks: Array<() => void>;
  }> = [];

  const client: RealtimeInvalidationClient & {
    opened: typeof opened;
    removed: string[];
  } = {
    opened,
    removed,
    channel(name, options) {
      const record = {
        name,
        private: options?.config?.private,
        bindings: [] as RecordedBinding[],
        callbacks: [] as Array<() => void>,
      };
      opened.push(record);

      const handle: RealtimeChannelHandle & { name: string } = {
        name,
        on(type, filter, callback) {
          record.bindings.push({ type, filter });
          record.callbacks.push(callback);
          return handle;
        },
        subscribe() {
          return handle;
        },
      };
      return handle;
    },
    removeChannel(channel) {
      removed.push((channel as unknown as { name: string }).name);
      return undefined;
    },
  };

  return client;
}

describe('subscribeRealtimeInvalidation', () => {
  it('subscribes recorded channels and removes them on unsubscribe', () => {
    const client = createFakeRealtimeClient();
    const onInvalidate = vi.fn();
    const subscription = subscribeRealtimeInvalidation({
      client,
      channels: patientDetailChannels({
        patientId: 'patient-1',
        treatmentId: 'treatment-1',
      }),
      onInvalidate,
    });

    expect(client.opened.map((channel) => channel.name)).toEqual([
      'clinic-review:patient:patient-1',
      'treatment:treatment-1',
    ]);
    expect(client.opened[1]?.private).toBe(true);
    expect(
      client.opened.flatMap((channel) =>
        channel.bindings
          .filter((binding) => binding.type === 'postgres_changes')
          .map((binding) => binding.filter.table),
      ),
    ).not.toContain('action_completions');

    subscription.unsubscribe();
    expect(client.removed).toHaveLength(2);
  });

  it('coalesces broadcast and postgres_changes callbacks into one invalidator', async () => {
    vi.useFakeTimers();
    const client = createFakeRealtimeClient();
    const onInvalidate = vi.fn(async () => undefined);
    const subscription = subscribeRealtimeInvalidation({
      client,
      channels: patientDetailChannels({
        patientId: 'patient-1',
        treatmentId: 'treatment-1',
      }),
      onInvalidate,
      debounceMs: 200,
    });

    for (const callback of client.opened.flatMap((channel) => channel.callbacks)) {
      callback();
    }

    await vi.advanceTimersByTimeAsync(200);
    expect(onInvalidate).toHaveBeenCalledTimes(1);
    subscription.unsubscribe();
  });

  it('patient switch unsubscribes the previous channels before opening the next', () => {
    const client = createFakeRealtimeClient();
    const first = subscribeRealtimeInvalidation({
      client,
      channels: patientDetailChannels({
        patientId: 'patient-a',
        treatmentId: 'treatment-a',
      }),
      onInvalidate: () => undefined,
    });
    first.unsubscribe();

    subscribeRealtimeInvalidation({
      client,
      channels: patientDetailChannels({
        patientId: 'patient-b',
        treatmentId: 'treatment-b',
      }),
      onInvalidate: () => undefined,
    }).unsubscribe();

    expect(client.removed).toEqual([
      'clinic-review:patient:patient-a',
      'treatment:treatment-a',
      'clinic-review:patient:patient-b',
      'treatment:treatment-b',
    ]);
    expect(client.opened.map((channel) => channel.name)).toEqual([
      'clinic-review:patient:patient-a',
      'treatment:treatment-a',
      'clinic-review:patient:patient-b',
      'treatment:treatment-b',
    ]);
  });

  it('builds a patients-list channel without action_completions', () => {
    const channel = patientsListChannel('clinic-1');
    expect(channel.name).toBe('clinic-review:patients-list:clinic-1');
    expect(channelBindsActionCompletions([channel])).toBe(false);
  });
});
