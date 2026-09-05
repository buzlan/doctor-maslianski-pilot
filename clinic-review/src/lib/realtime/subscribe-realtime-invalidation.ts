import {
  createInvalidationController,
  type InvalidationController,
} from './create-invalidation-controller';
import type { RealtimeInvalidationChannel } from './patient-detail-bindings';

export type RealtimeChannelHandle = {
  on: (
    type: string,
    filter: Record<string, unknown>,
    callback: () => void,
  ) => RealtimeChannelHandle;
  subscribe: (callback?: (status: string) => void) => RealtimeChannelHandle;
};

export type RealtimeInvalidationClient = {
  channel: (
    name: string,
    options?: { config?: { private?: boolean } },
  ) => RealtimeChannelHandle;
  removeChannel: (channel: RealtimeChannelHandle) => Promise<unknown> | unknown;
};

export type SubscribeRealtimeInvalidationOptions = {
  client: RealtimeInvalidationClient;
  channels: readonly RealtimeInvalidationChannel[];
  onInvalidate: () => void | Promise<void>;
  debounceMs?: number;
};

export type RealtimeInvalidationSubscription = {
  unsubscribe: () => void;
  controller: InvalidationController;
};

export function subscribeRealtimeInvalidation(
  options: SubscribeRealtimeInvalidationOptions,
): RealtimeInvalidationSubscription {
  const controller = createInvalidationController({
    debounceMs: options.debounceMs,
    run: options.onInvalidate,
  });

  const opened = options.channels.map((spec) => {
    let channel = options.client.channel(spec.name, {
      config: { private: spec.private === true },
    });

    if (spec.broadcastEvent !== undefined) {
      channel = channel.on('broadcast', { event: spec.broadcastEvent }, () => {
        controller.invalidate();
      });
    }

    for (const binding of spec.postgresChanges) {
      channel = channel.on(
        'postgres_changes',
        {
          event: binding.event,
          schema: 'public',
          table: binding.table,
          filter: binding.filter,
        },
        () => {
          controller.invalidate();
        },
      );
    }

    channel.subscribe();
    return channel;
  });

  return {
    controller,
    unsubscribe() {
      controller.dispose();
      for (const channel of opened) {
        void options.client.removeChannel(channel);
      }
    },
  };
}
