// Work a request causes that its answer does not wait for: bookkeeping and analytics. Supabase's
// edge runtime keeps the worker alive for a promise handed to EdgeRuntime.waitUntil, so the answer
// goes out first. What that work queues for PostHog (events, or the exception it ended in) is sent
// when it ends. Without the edge runtime (tests, scripts) the work runs before the answer, and a
// failure reaches the caller, as before.
import type { Telemetry } from './telemetry.ts';

interface EdgeRuntime {
  waitUntil(work: Promise<unknown>): void;
}

const edgeRuntime = (): EdgeRuntime | undefined =>
  (globalThis as { EdgeRuntime?: EdgeRuntime }).EdgeRuntime;

export function afterResponse(work: () => Promise<void>, telemetry: Telemetry): Promise<void> {
  const runtime = edgeRuntime();
  if (!runtime) return work();
  runtime.waitUntil(
    work().catch((e) => telemetry.exception(e)).finally(() => telemetry.flush()),
  );
  return Promise.resolve();
}
