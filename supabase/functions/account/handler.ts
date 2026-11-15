// POST /functions/v1/account/delete {"apple_authorization_code"?: string}
// Deletes the signed-in user's account for good, with the app's own session token only.
// 200 {"deleted": true, "household": "kept" | "deleted" | "none",
//      "apple": "revoked" | "not_linked" | "manual"}
// Errors are {"error", "message"}.
import { AuthError } from '../_shared/auth.ts';
import type { HouseholdFate } from '../_shared/db.ts';
import { json, preflight } from '../_shared/http.ts';
import type { AppleRevocation } from './apple.ts';

export type AppleFate = AppleRevocation | 'not_linked';

export type Deleted = { deleted: true; household: HouseholdFate; apple: AppleFate };

export interface Deps {
  /** The session's user; throws an AuthError when it can't. */
  authenticate(req: Request): Promise<{ userId: string }>;
  /** The Apple user id when the account has a Sign in with Apple identity. */
  appleSubject(userId: string): Promise<string | null>;
  revokeApple(grant: { code: string | null; subject: string }): Promise<AppleRevocation>;
  deleteAccount(userId: string): Promise<HouseholdFate>;
  /**
   * Best effort after a deletion: removes the screenshots of the notes the deletion took with it
   * (docs/FEEDBACK.md). Its failure or slowness never changes the answer; the daily sweep catches
   * up.
   */
  afterDeletion?(): Promise<unknown>;
  /** Error tracking for a failure answered with 500 (telemetry.ts); scrubbed there. */
  report?(error: unknown): void;
}

const failures = {
  not_found: [404, 'Unbekannte Adresse.'],
  method: [405, 'Bitte per POST.'],
  bad_request: [400, 'Der Inhalt ist kein gültiges JSON {"apple_authorization_code"?: string}.'],
  server: [500, 'Das Konto konnte nicht gelöscht werden. Bitte versuch es gleich noch einmal.'],
} as const satisfies Record<string, readonly [number, string]>;

/** How long a deletion's answer waits for afterDeletion. */
export const AFTER_DELETION_MS = 5000;

async function bestEffort(work: () => Promise<unknown>, ms: number): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<void>((resolve) => {
    timer = setTimeout(resolve, ms);
  });
  try {
    // Through then(): a work that throws before returning its promise is caught here too.
    await Promise.race([Promise.resolve().then(work).then(() => {}, () => {}), late]);
  } finally {
    clearTimeout(timer);
  }
}

const fail = (error: keyof typeof failures | AuthError) => {
  if (error instanceof AuthError) {
    return json({ error: error.reason, message: error.message }, {
      status: error.status,
      headers: error.status === 401 ? { 'www-authenticate': 'Bearer' } : {},
    });
  }
  const [status, message] = failures[error];
  return json({ error, message }, { status });
};

/** The optional Apple code, or null for a body that is not the documented shape. */
async function readBody(req: Request): Promise<{ appleCode: string | null } | null> {
  const raw = await req.text();
  if (!raw.trim()) return { appleCode: null };
  try {
    const body: unknown = JSON.parse(raw);
    if (typeof body !== 'object' || body === null || Array.isArray(body)) return null;
    const code: unknown = (body as Record<string, unknown>).apple_authorization_code;
    if (code === undefined || code === null) return { appleCode: null };
    return typeof code === 'string' ? { appleCode: code || null } : null;
  } catch {
    return null;
  }
}

export function createHandler(
  deps: Deps,
  afterDeletionMs: number = AFTER_DELETION_MS,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    if (!new URL(req.url).pathname.endsWith('/account/delete')) return fail('not_found');
    if (req.method !== 'POST') {
      const res = fail('method');
      res.headers.set('allow', 'POST, OPTIONS');
      return res;
    }

    let userId: string;
    try {
      ({ userId } = await deps.authenticate(req));
    } catch (e) {
      // The first call deleted the account but its answer never arrived. Whether it got to
      // revoke Apple's grant is unknown, so the app shows the Apple ID hint.
      if (e instanceof AuthError && e.reason === 'user_deleted') {
        return json({ deleted: true, household: 'none', apple: 'manual' } satisfies Deleted);
      }
      if (e instanceof AuthError) return fail(e);
      console.error('account: authenticate failed', e);
      deps.report?.(e);
      return fail('server');
    }

    const body = await readBody(req);
    if (!body) return fail('bad_request');

    try {
      // The Apple user id lives in auth.identities, so it is read before the delete. Apple is
      // called only after the delete succeeded: a failed delete leaves the single-use code unspent
      // for the retry.
      const subject = await deps.appleSubject(userId);
      const household = await deps.deleteAccount(userId);
      const apple: AppleFate = subject
        ? await deps.revokeApple({ code: body.appleCode, subject })
        : 'not_linked';
      if (deps.afterDeletion) await bestEffort(deps.afterDeletion, afterDeletionMs);
      return json({ deleted: true, household, apple } satisfies Deleted);
    } catch (e) {
      console.error('account: deletion failed', e);
      deps.report?.(e);
      return fail('server');
    }
  };
}
