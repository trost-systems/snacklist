// POST /functions/v1/feedback-screenshots/sweep, no key: removes the feedback screenshots that are
// due (docs/FEEDBACK.md, "Screenshots"), at most SWEEP_LIMIT per call, and answers
// 200 {"removed": n} with how many objects existed. A failure answers 503 {"error": code}. Anyone
// may call it: it only removes what the database says is due, and is idempotent. The daily
// Keepalive workflow calls it.
import { SweepError } from '../_shared/feedback_screenshots.ts';
import { discardUnreadBody, json, preflight } from '../_shared/http.ts';

export function createHandler(sweep: () => Promise<number>): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const early = preflight(req);
    if (early) return early;
    await discardUnreadBody(req);
    if (!new URL(req.url).pathname.endsWith('/feedback-screenshots/sweep')) {
      return json({ error: 'not_found' }, { status: 404 });
    }
    if (req.method !== 'POST') {
      return json({ error: 'method' }, { status: 405, headers: { allow: 'POST, OPTIONS' } });
    }
    try {
      const removed = await sweep();
      console.log(`feedback-screenshots: removed ${removed}`);
      return json({ removed });
    } catch (e) {
      const code = e instanceof SweepError ? e.code : 'failed';
      console.error(e instanceof SweepError ? e.message : 'feedback-screenshots: failed');
      return json({ error: code }, { status: 503 });
    }
  };
}
