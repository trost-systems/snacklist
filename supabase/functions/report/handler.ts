// The DSA report function (job 275, Legal Addendum B.4): only the snacklist.app Vercel function
// (site/api/report.mjs) calls it, with the waitlist's proxy secret.
//   POST /report  {locale, category, location, reason, name, email, good_faith, website}
//     201 {"ref":"M-XXXX-XXXX"}  stored; the confirmation mail follows when an address was given.
//                                A filled honeypot gets the same answer with a ref of its own,
//                                and nothing is stored or mailed.
//     400 invalid_request, 429 rate_limited (LIMITS.perHour web reports in the last hour, for
//     everyone), 503 unavailable
// Everything else, and every request without the secret, is 404, as is every request while
// WAITLIST_PROXY_SECRET is unset.
// Logs are fixed codes ("report: stored", "report 429"): never a body, address, name or a Postgres
// message (a check violation's detail holds the row).
import { confirmationMail, type Locale } from './mail.ts';
import { type Mailer, RESEND_API_URL, resendMailer } from '../_shared/resend.ts';
import { sameSecret } from '../waitlist/crypto.ts';

export interface Config {
  proxySecret: string;
}

/** Null config: the function is off and answers 404. Null mailer: nothing is mailed. */
export function configFrom(
  env: { get(key: string): string | undefined },
): { config: Config | null; mailer: Mailer | null } {
  const proxySecret = env.get('WAITLIST_PROXY_SECRET');
  const apiKey = env.get('RESEND_API_KEY');
  return {
    config: proxySecret ? { proxySecret } : null,
    mailer: apiKey ? resendMailer(apiKey, env.get('RESEND_API_URL') || RESEND_API_URL) : null,
  };
}

/** A circuit breaker for floods, far above any real load (Legal N-242); never per address (N-241). */
export const LIMITS = { perHour: 200 };

/**
 * Waits before each new try of a failed confirmation (Legal N-244). The key report-confirm/<id>
 * makes a retry safe: Resend sends one key once. What still fails is caught by
 * notify.ts --confirmations from the reports without confirmation_sent_at.
 */
export const CONFIRM_RETRY_MS = [2_000, 8_000];

export const CATEGORIES = ['hate', 'personal_rights', 'ip', 'csam', 'danger', 'other'] as const;
export type Category = (typeof CATEGORIES)[number];

/** A valid report, trimmed; an empty name or address is null. */
export interface Report {
  locale: Locale;
  category: Category;
  location: string;
  reason: string;
  name: string | null;
  email: string | null;
}

export interface Stored {
  id: string;
  ref: string;
  /** Mail the confirmation: an address was given. */
  confirm: boolean;
}

/** The SQL functions of migration *_content_reports.sql. */
export interface Store {
  /** content_report_submit: null when the hour's limit is reached and nothing was stored. */
  submit(report: Report, now: Date, limits: typeof LIMITS): Promise<Stored | null>;
  /** content_report_confirmation_sent */
  confirmationSent(id: string, now: Date): Promise<boolean>;
}

export interface Deps {
  config: Config | null;
  store: Store;
  mailer: Mailer | null;
  now(): Date;
  random(bytes: number): Uint8Array;
  /**
   * Runs [work] after the response (EdgeRuntime.waitUntil). A returned promise holds the answer
   * until the work is done: the local stack only, where workers may drop background work.
   */
  defer(work: () => Promise<void>): Promise<void> | void;
  sleep(ms: number): Promise<void>;
}

const log = (code: string) => console.log(`report: ${code}`);

/** The SQLSTATE of a failure, never its message. */
const failure = (code: string, e: unknown) => {
  const state = (e as { code?: unknown })?.code;
  log(typeof state === 'string' && /^[0-9A-Z]{5}$/.test(state) ? `${code} ${state}` : code);
};

const answer = (status: number, body: unknown) => {
  if (status >= 300) console.log(`report ${status}`);
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
};

const notFound = () => answer(404, { error: 'not_found' });
const invalidRequest = () => answer(400, { error: 'invalid_request' });

export const MAX_BODY = 64 * 1024;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const CONTROL = /\p{Cc}/u;
/** Control characters but line breaks and tabs, which a location or reason may hold. */
const CONTROL_IN_TEXT = /(?![\n\r\t])\p{Cc}/u;
const REF_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/** Code points, as Postgres's char_length counts them. */
const length = (s: string) => [...s].length;

type Body = Record<string, unknown>;

/** A trimmed text of [min]..[max] code points without control characters, or null. */
function text(value: unknown, min: number, max: number, control: RegExp): string | null {
  if (typeof value !== 'string') return null;
  const s = value.trim();
  return length(s) >= min && length(s) <= max && !control.test(s) ? s : null;
}

/** An optional field: absent or '' is null; anything else must pass [valid]. */
function optional(value: unknown, valid: (s: string) => boolean): string | null | undefined {
  if (value === undefined) return null;
  if (typeof value !== 'string') return undefined;
  const s = value.trim();
  if (s === '') return null;
  return valid(s) ? s : undefined;
}

const isCategory = (v: unknown): v is Category => CATEGORIES.some((c) => c === v);

/** The report body; 'honeypot' for a valid body with the hidden field filled; null when invalid. */
export function parseReport(b: Body): Report | 'honeypot' | null {
  if (b.locale !== 'de' && b.locale !== 'en') return null;
  if (!isCategory(b.category)) return null;
  if (b.good_faith !== true) return null;
  const location = text(b.location, 1, 2000, CONTROL_IN_TEXT);
  const reason = text(b.reason, 20, 5000, CONTROL_IN_TEXT);
  const name = optional(b.name, (s) => length(s) <= 200 && !CONTROL.test(s));
  const email = optional(
    b.email,
    (s) => length(s) <= 254 && EMAIL.test(s) && !CONTROL.test(s),
  );
  if (location === null || reason === null || name === undefined || email === undefined) {
    return null;
  }
  if (b.website !== undefined && b.website !== '') return 'honeypot';
  return { locale: b.locale, category: b.category, location, reason, name, email };
}

/** M-XXXX-XXXX from 8 random bytes; 256 is a multiple of 32, so no letter is likelier. */
export function randomRef(bytes: Uint8Array): string {
  const letters = [...bytes.slice(0, 8)].map((b) => REF_ALPHABET.charAt(b % 32)).join('');
  return `M-${letters.slice(0, 4)}-${letters.slice(4, 8)}`;
}

/** The body as JSON object, or null when it is longer than MAX_BODY or no object. */
async function readBody(req: Request): Promise<Body | null> {
  const declared = Number(req.headers.get('content-length') ?? '0');
  if (declared > MAX_BODY || !req.body) return null;
  const chunks: Uint8Array[] = [];
  let size = 0;
  for await (const chunk of req.body) {
    size += chunk.length;
    if (size > MAX_BODY) return null;
    chunks.push(chunk);
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, at);
    at += chunk.length;
  }
  try {
    const body: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    return body && typeof body === 'object' && !Array.isArray(body) ? body as Body : null;
  } catch {
    return null;
  }
}

const ROUTE = /^\/(?:functions\/v1\/)?report\/?$/;

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  const { store } = deps;
  if (!deps.config) return () => Promise.resolve(notFound());
  const config: Config = deps.config;

  async function confirm(report: Report, stored: Stored, createdAt: Date) {
    if (!report.email) return;
    if (!deps.mailer) return log('mail_unconfigured');
    const mail = confirmationMail({
      locale: report.locale,
      name: report.name,
      createdAt,
      ref: stored.ref,
    });
    for (let attempt = 0;; attempt++) {
      try {
        await deps.mailer.send(report.email, mail, `report-confirm/${stored.id}`);
        break;
      } catch (e) {
        const wait = CONFIRM_RETRY_MS[attempt];
        if (wait === undefined) return failure('mail_failed', e);
        failure('mail_retry', e);
        await deps.sleep(wait);
      }
    }
    await store.confirmationSent(stored.id, deps.now());
    log('confirmation_sent');
  }

  return async (req) => {
    const secret = req.headers.get('x-waitlist-proxy-secret') ?? '';
    if (!await sameSecret(secret, config.proxySecret)) return notFound();
    if (!ROUTE.test(new URL(req.url).pathname) || req.method !== 'POST') return notFound();
    try {
      const body = await readBody(req);
      const report = body && parseReport(body);
      if (!report) return invalidRequest();
      if (report === 'honeypot') {
        log('honeypot');
        return answer(201, { ref: randomRef(deps.random(8)) });
      }
      const now = deps.now();
      const stored = await store.submit(report, now, LIMITS);
      if (!stored) {
        log('global_cap_hit');
        return answer(429, { error: 'rate_limited' });
      }
      log('stored');
      if (stored.confirm) {
        await deps.defer(() =>
          confirm(report, stored, now).catch((e) => failure('confirmation_failed', e))
        );
      }
      return answer(201, { ref: stored.ref });
    } catch (e) {
      failure('failed', e);
      return answer(503, { error: 'unavailable' });
    }
  };
}
