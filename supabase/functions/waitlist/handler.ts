// The waitlist function (docs/WAITLIST.md): only the hummlist.com Vercel function calls it.
//   POST /waitlist/signup       {email, platform, locale, launch_news, consent_version, website,
//                               elapsed_ms}: 202 {"status":"ok"}, 400 {"error": ...},
//                               429 rate_limited, 503 unavailable
//   POST /waitlist/confirm      {token}: 200 {"status":"confirmed"|"invalid"}
//   POST /waitlist/unsubscribe  {id, sig}: 200 {"status":"deleted"|"invalid"}
// Everything else, and every request without x-waitlist-proxy-secret, is 404, as is every request
// while WAITLIST_PROXY_SECRET or WAITLIST_HMAC_SECRET is unset.
// Logs are fixed outcome codes ("waitlist: signup_stored"): never an address, token, body, header
// value or a Postgres message (a unique violation's detail names the address).
import { CONSENT_VERSIONS } from './consent.ts';
import { confirmToken, emailHmac, sameSecret, sha256Hex, unsubscribeSig } from './crypto.ts';
import {
  confirmationMail,
  confirmUrl,
  type Locale,
  type Mail,
  type MailAllow,
  mailAllowFrom,
  type Platform,
  recipientAllowed,
  refusal,
  siteOrigin,
  unsubscribeLinks,
  welcomeMail,
} from './mail.ts';
import { type Mailer, RESEND_API_URL, resendMailer } from './resend.ts';

export interface Config {
  proxySecret: string;
  hmacSecret: string;
  allow: MailAllow;
  allowPlaceholders: boolean;
}

/** Null config: the function is off and answers 404. Null mailer: nothing is mailed. */
export function configFrom(
  env: { get(key: string): string | undefined },
): { config: Config | null; mailer: Mailer | null } {
  const proxySecret = env.get('WAITLIST_PROXY_SECRET');
  const hmacSecret = env.get('WAITLIST_HMAC_SECRET');
  const apiKey = env.get('RESEND_API_KEY');
  return {
    config: proxySecret && hmacSecret
      ? {
        proxySecret,
        hmacSecret,
        allow: mailAllowFrom(env.get('WAITLIST_MAIL_ALLOW')),
        // Draft texts go only to test addresses: once everyone may sign up, the flag is ignored.
        allowPlaceholders: env.get('WAITLIST_ALLOW_PLACEHOLDERS') === '1' &&
          mailAllowFrom(env.get('WAITLIST_MAIL_ALLOW')) === 'test',
      }
      : null,
    mailer: apiKey ? resendMailer(apiKey, env.get('RESEND_API_URL') || RESEND_API_URL) : null,
  };
}

export const LIMITS = { perKey: 10, total: 300 };

export interface SignupRow {
  email: string;
  emailHmac: string;
  platform: Platform;
  locale: Locale;
  launchNews: boolean;
  consentVersion: string;
  tokenHash: string;
}

/** A row to mail. */
export interface Recipient {
  id: string;
  email: string;
  locale: Locale;
  launchNews: boolean;
}

/** The waitlist's SQL functions (migration 20261102213606_waitlist.sql). */
export interface Store {
  /** waitlist_rate_hit: false when the key or everyone is over the hour's limit. */
  rateHit(keyHash: string, now: Date, limits: typeof LIMITS): Promise<boolean>;
  /** waitlist_signup: the row to send the confirmation to, or null when nothing is to be sent. */
  signup(row: SignupRow, now: Date): Promise<Recipient | null>;
  /** waitlist_confirm: the confirmed row, or null for a used, unknown or expired token. */
  confirm(tokenHash: string, now: Date): Promise<Recipient | null>;
  /** waitlist_mailed */
  mailed(id: string, kind: 'welcome' | 'invite', now: Date): Promise<boolean>;
  /** waitlist_unsubscribe: false when the row was already gone. */
  unsubscribe(id: string, now: Date): Promise<boolean>;
}

export interface Deps {
  config: Config | null;
  store: Store;
  mailer: Mailer | null;
  now(): Date;
  random(bytes: number): Uint8Array;
  /**
   * Runs [work] after the response (EdgeRuntime.waitUntil). A returned promise holds the answer
   * until the work is done: the local stack only, where oneshot workers drop background work.
   */
  defer(work: () => Promise<void>): Promise<void> | void;
}

const log = (code: string) => console.log(`waitlist: ${code}`);

/** The SQLSTATE of a failure, never its message. */
const failure = (code: string, e: unknown) => {
  const state = (e as { code?: unknown })?.code;
  log(typeof state === 'string' && /^[0-9A-Z]{5}$/.test(state) ? `${code} ${state}` : code);
};

const answer = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });

const notFound = () => answer(404, { error: 'not_found' });
const invalidRequest = () => answer(400, { error: 'invalid_request' });

const MAX_BODY = 2048;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const CONTROL = /\p{Cc}/u;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const MIN_ELAPSED_MS = 1500;

export interface SignupRequest {
  email: string;
  platform: Platform;
  locale: Locale;
  launchNews: boolean;
  consentVersion: string;
  /** Answered like any sign-up, then dropped. */
  bot: 'honeypot' | 'too_fast' | null;
}

type Body = Record<string, unknown>;

/** The sign-up body, or the error the form shows. */
export function parseSignup(
  b: Body,
): SignupRequest | 'invalid_email' | 'invalid_platform' | 'invalid_request' {
  const email = typeof b.email === 'string' ? b.email.trim() : '';
  if (email.length > 254 || !EMAIL.test(email) || CONTROL.test(email)) return 'invalid_email';
  if (b.platform !== 'ios' && b.platform !== 'android') return 'invalid_platform';
  if (b.locale !== 'de' && b.locale !== 'en') return 'invalid_request';
  if (b.consent_version !== CONSENT_VERSIONS[b.locale]) return 'invalid_request';
  if (b.launch_news !== undefined && typeof b.launch_news !== 'boolean') return 'invalid_request';
  const honeypot = b.website !== undefined && b.website !== '';
  const elapsed = typeof b.elapsed_ms === 'number' ? b.elapsed_ms : 0;
  return {
    email,
    platform: b.platform,
    locale: b.locale,
    launchNews: b.launch_news === true,
    consentVersion: CONSENT_VERSIONS[b.locale],
    bot: honeypot ? 'honeypot' : elapsed < MIN_ELAPSED_MS ? 'too_fast' : null,
  };
}

async function readBody(req: Request): Promise<Body | null> {
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (bytes.length > MAX_BODY) return null;
  try {
    const body = JSON.parse(new TextDecoder().decode(bytes));
    return body && typeof body === 'object' && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

const ROUTE = /^\/(?:functions\/v1\/)?waitlist\/(signup|confirm|unsubscribe)\/?$/;

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  const { store } = deps;
  if (!deps.config) return () => Promise.resolve(notFound());
  const config: Config = deps.config;
  const unsubscribeFor = async (origin: string, row: Recipient) =>
    unsubscribeLinks(origin, row.locale, row.id, await unsubscribeSig(config.hmacSecret, row.id));

  async function deliver(to: string, mail: Mail, key: string): Promise<boolean> {
    const refused = refusal(to, mail, config);
    if (refused) {
      log(`mail_refused_${refused}`);
      return false;
    }
    if (!deps.mailer) {
      log('mail_unconfigured');
      return false;
    }
    try {
      await deps.mailer.send(to, mail, key);
      return true;
    } catch (e) {
      failure('mail_failed', e);
      return false;
    }
  }

  /** After the answer: the same answer went out for a new, known or dropped address. */
  async function storeSignup(s: SignupRequest, origin: string) {
    if (s.bot) return log(`signup_dropped_${s.bot}`);
    if (!recipientAllowed(s.email, config.allow)) return log('signup_dropped_recipient');
    const token = confirmToken(deps.random(32));
    const tokenHash = await sha256Hex(token);
    const row = await store.signup({
      email: s.email,
      emailHmac: await emailHmac(config.hmacSecret, s.email),
      platform: s.platform,
      locale: s.locale,
      launchNews: s.launchNews,
      consentVersion: s.consentVersion,
      tokenHash,
    }, deps.now());
    if (!row) return log('signup_unchanged');
    log('signup_stored');
    const mail = confirmationMail(row.locale, {
      confirmUrl: confirmUrl(origin, row.locale, token),
      unsubscribe: await unsubscribeFor(origin, row),
      launchNews: row.launchNews,
    });
    if (await deliver(row.email, mail, `confirm/${row.id}/${tokenHash.slice(0, 16)}`)) {
      log('confirmation_sent');
    }
  }

  async function signup(body: Body, client: string | null, origin: string) {
    const parsed = parseSignup(body);
    if (typeof parsed === 'string') return answer(400, { error: parsed });
    if (!client) return invalidRequest();
    if (!await store.rateHit(await sha256Hex(client), deps.now(), LIMITS)) {
      log('signup_rate_limited');
      return answer(429, { error: 'rate_limited' });
    }
    await deps.defer(() => storeSignup(parsed, origin).catch((e) => failure('signup_failed', e)));
    return answer(202, { status: 'ok' });
  }

  async function sendWelcome(row: Recipient, origin: string) {
    const mail = welcomeMail(row.locale, {
      unsubscribe: await unsubscribeFor(origin, row),
      launchNews: row.launchNews,
    });
    if (await deliver(row.email, mail, `welcome/${row.id}`)) {
      await store.mailed(row.id, 'welcome', deps.now());
      log('welcome_sent');
    }
  }

  async function confirm(body: Body, origin: string) {
    const token = typeof body.token === 'string' ? body.token : '';
    const row = TOKEN.test(token) ? await store.confirm(await sha256Hex(token), deps.now()) : null;
    if (!row) {
      log('confirm_invalid');
      return answer(200, { status: 'invalid' });
    }
    log('confirm_ok');
    await deps.defer(() => sendWelcome(row, origin).catch((e) => failure('welcome_failed', e)));
    return answer(200, { status: 'confirmed' });
  }

  async function unsubscribe(body: Body) {
    const id = typeof body.id === 'string' ? body.id.toLowerCase() : '';
    const sig = typeof body.sig === 'string' ? body.sig.toLowerCase() : '';
    const valid = UUID.test(id) && HEX64.test(sig) &&
      await sameSecret(sig, await unsubscribeSig(config.hmacSecret, id));
    if (!valid) {
      log('unsubscribe_invalid');
      return answer(200, { status: 'invalid' });
    }
    // A second press of the same link finds the row gone: it is just as deleted.
    log(await store.unsubscribe(id, deps.now()) ? 'unsubscribe_deleted' : 'unsubscribe_gone');
    return answer(200, { status: 'deleted' });
  }

  return async (req) => {
    const secret = req.headers.get('x-waitlist-proxy-secret') ?? '';
    if (!await sameSecret(secret, config.proxySecret)) return notFound();
    const route = new URL(req.url).pathname.match(ROUTE)?.[1];
    if (!route || req.method !== 'POST') return notFound();
    const origin = siteOrigin(req.headers.get('x-waitlist-origin'));
    try {
      const body = await readBody(req);
      if (!body) return invalidRequest();
      if (route === 'signup') {
        return await signup(body, req.headers.get('x-waitlist-client'), origin);
      }
      if (route === 'confirm') return await confirm(body, origin);
      return await unsubscribe(body);
    } catch (e) {
      failure(`${route}_failed`, e);
      return answer(503, { error: 'unavailable' });
    }
  };
}
