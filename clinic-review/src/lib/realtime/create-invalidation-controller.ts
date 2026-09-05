export type InvalidationController = {
  invalidate: () => void;
  dispose: () => void;
};

export function createInvalidationController(options: {
  run: () => void | Promise<void>;
  debounceMs?: number;
}): InvalidationController {
  const debounceMs = options.debounceMs ?? 200;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let inFlight = false;
  let pending = false;
  let disposed = false;

  async function runLoop(): Promise<void> {
    if (disposed) {
      return;
    }

    inFlight = true;
    try {
      do {
        pending = false;
        await options.run();
      } while (pending && !disposed);
    } finally {
      inFlight = false;
    }
  }

  function kick(): void {
    if (disposed) {
      return;
    }

    if (inFlight) {
      pending = true;
      return;
    }

    void runLoop();
  }

  return {
    invalidate() {
      if (disposed) {
        return;
      }

      if (timer !== null) {
        clearTimeout(timer);
      }

      timer = setTimeout(() => {
        timer = null;
        kick();
      }, debounceMs);
    },
    dispose() {
      disposed = true;
      if (timer !== null) {
        clearTimeout(timer);
        timer = null;
      }
    },
  };
}
