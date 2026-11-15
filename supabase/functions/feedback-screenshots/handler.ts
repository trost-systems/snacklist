// Two routes (docs/FEEDBACK.md, "Screenshots"):
//
// POST /functions/v1/feedback-screenshots/upload/<note id>, the app's own session token, body the
// PNG: stores it as <user id>/<note id>.png (upload.ts) and answers 200 {"name"}, also when it is
// there already. 400 bad_request (no lowercase uuid, empty body), 401/403 the shared auth answer
// (403 session_required for API and MCP tokens), 403 quota, 413 too_large, 415 not_png, 503
// storage_failed or db_error.
//
// POST /functions/v1/feedback-screenshots/sweep, no key: removes the feedback screenshots that are
// due, at most SWEEP_LIMIT per call, and answers 200 {"removed": n} with how many objects existed.
// A failure answers 503 {"error": code}. Anyone may call it: it only removes what the database
// says is due, and is idempotent. The daily Keepalive workflow calls it.
//
// Logs carry fixed codes only, never a name or user id.
import { AuthError } from '../_shared/auth.ts';
import { SweepError } from '../_shared/feedback_screenshots.ts';
import { discardUnreadBody, json, preflight } from '../_shared/http.ts';
import { isNoteId, isPng, readCapped, type StoreScreenshot, UploadError } from './upload.ts';

export interface Deps {
  sweep(): Promise<number>;
  /** The session's user; throws an AuthError when it can't (authenticateSession). */
  authenticate(req: Request): Promise<{ userId: string }>;
  store: StoreScreenshot;
}

const UPLOAD = /\/feedback-screenshots\/upload\/(?<id>[^/]*)$/;

function refuse(error: string, status: number): Response {
  console.log(`feedback-screenshots: upload ${error}`);
  return json({ error }, { status });
}

async function upload(deps: Deps, req: Request, id: string): Promise<Response> {
  let userId: string;
  try {
    ({ userId } = await deps.authenticate(req));
  } catch (e) {
    await discardUnreadBody(req);
    if (!(e instanceof AuthError)) {
      console.error('feedback-screenshots: upload db_error auth');
      return json({ error: 'db_error' }, { status: 503 });
    }
    console.log(`feedback-screenshots: upload ${e.reason}`);
    return json({ error: e.reason, message: e.message }, {
      status: e.status,
      headers: e.status === 401 ? { 'www-authenticate': 'Bearer' } : {},
    });
  }
  if (!isNoteId(id)) {
    await discardUnreadBody(req);
    return refuse('bad_request', 400);
  }
  const png = await readCapped(req);
  if (png === 'too_large') return refuse('too_large', 413);
  if (png.byteLength === 0) return refuse('bad_request', 400);
  if (!isPng(png)) return refuse('not_png', 415);
  try {
    const outcome = await deps.store(userId, id, png);
    if (outcome === 'quota') return refuse('quota', 403);
    console.log(`feedback-screenshots: upload ${outcome}`);
    return json({ name: `${userId}/${id}.png` });
  } catch (e) {
    const failure = e instanceof UploadError ? e : new UploadError('db_error', 'unknown');
    console.error(failure.message);
    return json({ error: failure.code }, { status: 503 });
  }
}

async function sweep(deps: Deps): Promise<Response> {
  try {
    const removed = await deps.sweep();
    console.log(`feedback-screenshots: removed ${removed}`);
    return json({ removed });
  } catch (e) {
    const code = e instanceof SweepError ? e.code : 'failed';
    console.error(e instanceof SweepError ? e.message : 'feedback-screenshots: failed');
    return json({ error: code }, { status: 503 });
  }
}

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    const path = new URL(req.url).pathname;
    const id = UPLOAD.exec(path)?.groups?.id;
    if (id === undefined && !path.endsWith('/feedback-screenshots/sweep')) {
      await discardUnreadBody(req);
      return json({ error: 'not_found' }, { status: 404 });
    }
    if (req.method !== 'POST') {
      await discardUnreadBody(req);
      return json({ error: 'method' }, { status: 405, headers: { allow: 'POST, OPTIONS' } });
    }
    if (id !== undefined) return await upload(deps, req, id);
    await discardUnreadBody(req);
    return await sweep(deps);
  };
}
