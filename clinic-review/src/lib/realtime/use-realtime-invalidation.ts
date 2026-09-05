import { useEffect } from 'react';

import { supabase } from '../supabase';
import type { RealtimeInvalidationChannel } from './patient-detail-bindings';
import {
  subscribeRealtimeInvalidation,
  type RealtimeInvalidationClient,
} from './subscribe-realtime-invalidation';

export function useRealtimeInvalidation(options: {
  enabled: boolean;
  channels: readonly RealtimeInvalidationChannel[];
  onInvalidate: () => void | Promise<void>;
  debounceMs?: number;
}): void {
  const channelKey = options.channels
    .map((channel) => channel.name)
    .join('|');

  useEffect(() => {
    if (!options.enabled || options.channels.length === 0) {
      return;
    }

    const subscription = subscribeRealtimeInvalidation({
      client: supabase as unknown as RealtimeInvalidationClient,
      channels: options.channels,
      onInvalidate: options.onInvalidate,
      debounceMs: options.debounceMs,
    });

    return () => {
      subscription.unsubscribe();
    };
    // channelKey captures the scoped patient/treatment identity.
    // onInvalidate is expected to be a stable useCallback.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [options.enabled, channelKey, options.onInvalidate, options.debounceMs]);
}
