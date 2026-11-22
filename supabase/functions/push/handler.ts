// Server push through FCM (docs/PUSH.md). Internal: pg_net or another function posts here.
//   POST /push   x-push-secret = PUSH_SEND_SECRET: sends one notification per recipient to the
//                devices of the recipients who are members of the household, when the list is
//                one of its lists. 200 sent or dry_run, 400 invalid_request, 401 unauthorized,
//                422 unknown_list, 503 not_configured, 500 failed (the database).
// Answers and logs carry counts, fixed codes and, for a dry run, the first message's shape with
// the household and list ids: never a token, a user id or a notification's text. pg_net keeps
// answers in net._http_response.
import { z } from 'zod';
import { sameSecret } from '../waitlist/crypto.ts';
import { type FcmMessage, type Sender, senderFrom } from './fcm.ts';

const id = z.guid().transform((s) => s.toLowerCase());

export const PushRequest = z.object({
  household_id: id,
  list_id: id,
  recipients: z.array(z.object({
    user_id: id,
    title: z.string().min(1).max(100),
    body: z.string().max(400),
  })).min(1).max(50).refine(
    (rs) => new Set(rs.map((r) => r.user_id)).size === rs.length,
    'one entry per user',
  ),
  dry_run: z.boolean().default(false),
  ttl_seconds: z.int().min(60).max(86400).default(86400),
});
export type PushRequest = z.infer<typeof PushRequest>;

/** One device of a recipient, as the store finds it. */
export interface Device {
  userId: string;
  token: string;
}

export interface Store {
  /** The recipients' devices, null when the list is not one of the household's. */
  devices(householdId: string, listId: string, userIds: readonly string[]): Promise<
    Device[] | null
  >;
  /** Deletes the devices FCM called unregistered; how many went. */
  forget(devices: readonly Device[]): Promise<number>;
}

export interface Deps {
  /** PUSH_SEND_SECRET; null answers every request 503. */
  secret: string | null;
  /** Null without FCM_SERVICE_ACCOUNT_JSON: only dry runs work. */
  sender: Sender | null;
  store: Store;
  now(): Date;
}

export function configFrom(
  env: { get(key: string): string | undefined },
): Pick<Deps, 'secret' | 'sender'> {
  return {
    secret: env.get('PUSH_SEND_SECRET') || null,
    sender: senderFrom(env),
  };
}

/** How many messages are in flight at once. */
export const SEND_CONCURRENCY = 8;

const log = (code: string) => console.log(`push: ${code}`);

/** The SQLSTATE of a failure, never its message. */
function failure(code: string, e: unknown) {
  const state = typeof e === 'object' && e !== null && 'code' in e ? e.code : undefined;
  log(typeof state === 'string' && /^[0-9A-Z]{5}$/.test(state) ? `${code} ${state}` : code);
}

const answer = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });

export function fcmMessage(
  req: PushRequest,
  recipient: PushRequest['recipients'][number],
  token: string,
  now: Date,
): FcmMessage {
  return {
    token,
    notification: { title: recipient.title, body: recipient.body },
    data: { kind: 'list', v: '1', household_id: req.household_id, list_id: req.list_id },
    android: { priority: 'high', ttl: `${req.ttl_seconds}s` },
    apns: {
      headers: { 'apns-expiration': String(Math.floor(now.getTime() / 1000) + req.ttl_seconds) },
      payload: { aps: { sound: 'default' } },
    },
  };
}

/** Runs `work` over `items`, at most `limit` at a time. */
async function eachLimited<T>(
  items: readonly T[],
  limit: number,
  work: (item: T) => Promise<void>,
): Promise<void> {
  let next = 0;
  const worker = async () => {
    for (let i = next++; i < items.length; i = next++) {
      const item = items[i];
      if (item !== undefined) await work(item);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
}

const ROUTE = /^\/(?:functions\/v1\/)?push\/?$/;

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  async function run(req: PushRequest, sender: Sender | null): Promise<Response> {
    const devices = await deps.store.devices(
      req.household_id,
      req.list_id,
      req.recipients.map((r) => r.user_id),
    );
    if (devices === null) {
      log('unknown_list');
      return answer(422, { error: 'unknown_list' });
    }
    const now = deps.now();
    const texts = new Map(req.recipients.map((r) => [r.user_id, r]));
    const messages = devices.flatMap((device) => {
      const recipient = texts.get(device.userId);
      return recipient ? [{ device, message: fcmMessage(req, recipient, device.token, now) }] : [];
    });
    if (sender === null) {
      const first = messages[0];
      log('dry_run');
      return answer(200, {
        status: 'dry_run',
        devices: messages.length,
        message: first
          ? {
            ...first.message,
            token: '<token>',
            notification: { title: '<title>', body: '<body>' },
          }
          : null,
      });
    }
    let sent = 0;
    let failed = 0;
    const gone: Device[] = [];
    await eachLimited(messages, SEND_CONCURRENCY, async ({ device, message }) => {
      const result = await sender.send(message);
      if (result.outcome === 'sent') sent++;
      else {
        failed++;
        if (result.outcome === 'unregistered') gone.push(device);
        else log(`send_failed ${result.status}`);
      }
    });
    const removed = gone.length > 0 ? await deps.store.forget(gone) : 0;
    log('sent');
    return answer(200, { status: 'sent', devices: messages.length, sent, failed, removed });
  }

  return async (req) => {
    if (!ROUTE.test(new URL(req.url).pathname) || req.method !== 'POST') {
      return answer(404, { error: 'not_found' });
    }
    if (!deps.secret) {
      log('not_configured');
      return answer(503, { error: 'not_configured' });
    }
    if (!await sameSecret(req.headers.get('x-push-secret') ?? '', deps.secret)) {
      log('unauthorized');
      return answer(401, { error: 'unauthorized' });
    }
    const parsed = PushRequest.safeParse(await req.json().catch(() => undefined));
    if (!parsed.success) {
      log('invalid_request');
      return answer(400, { error: 'invalid_request' });
    }
    if (!parsed.data.dry_run && !deps.sender) {
      log('not_configured');
      return answer(503, { error: 'not_configured' });
    }
    try {
      return await run(parsed.data, parsed.data.dry_run ? null : deps.sender);
    } catch (e) {
      failure('db_error', e);
      return answer(500, { error: 'failed' });
    }
  };
}
