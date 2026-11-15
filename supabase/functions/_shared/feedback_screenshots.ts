// Removes feedback screenshots whose note is gone, and uploads that never got a note
// (docs/FEEDBACK.md, "Screenshots"). The database says which object names are due
// (public.feedback_screenshots_due); the Storage API removes them, since SQL cannot delete the
// files; then the names leave the queue. Run by the feedback-screenshots function (the daily
// Keepalive) and by the account function right after a deletion. Logs carry fixed codes and
// counts only, never an object name: each one starts with a user id.
import type { Sql } from './db.ts';

export const BUCKET = 'feedback-screenshots';

/** At most this many names per sweep; the Storage API takes up to 1000 per request. */
export const SWEEP_LIMIT = 500;

export type SweepFailure = 'db_error' | 'storage_failed';

export class SweepError extends Error {
  constructor(readonly code: SweepFailure, readonly detail: string) {
    super(`feedback-screenshots: ${code} ${detail}`);
  }
}

export interface SweepStore {
  due(limit: number): Promise<string[]>;
  /** Drops the names from the queue (orphans are not in it); idempotent. */
  removed(names: readonly string[]): Promise<void>;
}

/** Removes the objects; answers how many existed. Names already gone are no error. */
export type RemoveObjects = (names: readonly string[]) => Promise<number>;

/**
 * One bounded sweep: removes at most `limit` due objects and answers how many existed. Safe to run
 * twice at once or again after a failure: the Storage API's removal is idempotent, and a name
 * leaves the queue only once the removal answered.
 */
export async function sweepFeedbackScreenshots(
  store: SweepStore,
  remove: RemoveObjects,
  limit: number = SWEEP_LIMIT,
): Promise<number> {
  const names = await store.due(limit).catch((e) => {
    throw new SweepError('db_error', pgCode(e));
  });
  if (names.length === 0) return 0;
  const removed = await remove(names);
  await store.removed(names).catch((e) => {
    throw new SweepError('db_error', pgCode(e));
  });
  return removed;
}

/** A Postgres error's SQLSTATE for logs, else "unknown": never its message. */
export function pgCode(e: unknown): string {
  const { code } = (e ?? {}) as { code?: unknown };
  return typeof code === 'string' && /^[0-9A-Z]{5}$/.test(code) ? code : 'unknown';
}

export function sqlSweepStore(db: () => Sql): SweepStore {
  return {
    async due(limit) {
      const rows = await db()<{ name: string }[]>`
        select name from public.feedback_screenshots_due(${limit}) as name`;
      return rows.map((r) => r.name);
    },
    async removed(names) {
      await db()`select public.feedback_screenshots_removed(${[...names]}::text[])`;
    },
  };
}

/** Removal through the Storage API with the project's secret key. */
export function storageRemover(
  supabaseUrl: string,
  secretKey: string,
  doFetch: typeof fetch = fetch,
): RemoveObjects {
  return async (names) => {
    let res: Response;
    try {
      res = await doFetch(`${supabaseUrl}/storage/v1/object/${BUCKET}`, {
        method: 'DELETE',
        headers: {
          apikey: secretKey,
          authorization: `Bearer ${secretKey}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({ prefixes: names }),
        signal: AbortSignal.timeout(20_000),
      });
    } catch {
      throw new SweepError('storage_failed', 'fetch');
    }
    const body: unknown = await res.json().catch(() => null);
    if (!res.ok || !Array.isArray(body)) {
      throw new SweepError('storage_failed', String(res.status));
    }
    return body.length;
  };
}
