// FCM's HTTP v1 API with a service account (docs/PUSH.md, "Secrets of the function"): a JWT
// signed with the account's key is traded at its token_uri for an access token, which is kept
// until a minute before it expires.
import { importPKCS8, SignJWT } from 'jose';
import { z } from 'zod';

export const FCM_API_URL = 'https://fcm.googleapis.com';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TIMEOUT_MS = 10_000;

/** The message FCM gets, as docs/PUSH.md has it. */
export interface FcmMessage {
  token: string;
  notification: { title: string; body: string };
  data: { kind: 'list'; v: '1'; 'household_id': string; 'list_id': string };
  android: { priority: 'high'; ttl: string };
  apns: { headers: { 'apns-expiration': string }; payload: { aps: { sound: 'default' } } };
}

/** `unregistered`: FCM says the token is gone or no token at all; delete it. */
export type SendResult =
  | { outcome: 'sent' }
  | { outcome: 'unregistered' }
  | { outcome: 'failed'; status: number };

export interface Sender {
  /** Never throws: a network error or a timeout is `failed` with status 0. */
  send(message: FcmMessage): Promise<SendResult>;
}

export const ServiceAccount = z.object({
  project_id: z.string().regex(/^[a-z0-9-]+$/),
  client_email: z.string().min(1),
  private_key: z.string().min(1),
  token_uri: z.url(),
});
export type ServiceAccount = z.infer<typeof ServiceAccount>;

const AccessToken = z.object({ access_token: z.string().min(1), expires_in: z.number() });

const FcmError = z.object({
  error: z.object({
    details: z.array(
      z.object({
        errorCode: z.string().optional(),
        fieldViolations: z.array(z.object({ field: z.string().optional() })).optional(),
      }).loose(),
    ).optional(),
  }).loose(),
}).loose();

/** Whether an error answer says the token itself is unknown or malformed. */
async function tokenGone(res: Response): Promise<boolean> {
  // Only FCM's own word: a bare 404 (a wrong project id or URL) must not wipe every device.
  const parsed = FcmError.safeParse(await res.json().catch(() => undefined));
  const details = parsed.success ? parsed.data.error.details ?? [] : [];
  return details.some((d) =>
    d.errorCode === 'UNREGISTERED' ||
    (res.status === 400 && (d.fieldViolations ?? []).some((v) => v.field === 'message.token'))
  );
}

export function fcmSender(
  account: ServiceAccount,
  opts: { apiUrl?: string; now?: () => number } = {},
): Sender {
  const apiUrl = opts.apiUrl ?? FCM_API_URL;
  const now = opts.now ?? Date.now;
  const sendUrl = `${apiUrl}/v1/projects/${account.project_id}/messages:send`;
  let cached: { token: string; expiresAt: number } | null = null;
  let pending: Promise<string> | null = null;

  async function exchange(): Promise<string> {
    const key = await importPKCS8(account.private_key, 'RS256');
    const issued = Math.floor(now() / 1000);
    const assertion = await new SignJWT({ scope: SCOPE })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(account.client_email)
      .setAudience(account.token_uri)
      .setIssuedAt(issued)
      .setExpirationTime(issued + 3600)
      .sign(key);
    const res = await fetch(account.token_uri, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) {
      await res.body?.cancel();
      throw new Error(`token exchange ${res.status}`);
    }
    const token = AccessToken.parse(await res.json());
    cached = { token: token.access_token, expiresAt: now() + (token.expires_in - 60) * 1000 };
    return token.access_token;
  }

  /** One exchange at a time: concurrent sends share it. */
  function accessToken(): Promise<string> {
    if (cached && now() < cached.expiresAt) return Promise.resolve(cached.token);
    pending ??= exchange().finally(() => {
      pending = null;
    });
    return pending;
  }

  return {
    async send(message) {
      try {
        const res = await fetch(sendUrl, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${await accessToken()}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({ message }),
          signal: AbortSignal.timeout(TIMEOUT_MS),
        });
        if (res.ok) {
          await res.body?.cancel();
          return { outcome: 'sent' };
        }
        if (res.status === 401) cached = null;
        if (await tokenGone(res)) return { outcome: 'unregistered' };
        return { outcome: 'failed', status: res.status };
      } catch {
        return { outcome: 'failed', status: 0 };
      }
    },
  };
}

/** The sender FCM_SERVICE_ACCOUNT_JSON configures, or null without it or when it does not parse. */
export function senderFrom(env: { get(key: string): string | undefined }): Sender | null {
  const raw = env.get('FCM_SERVICE_ACCOUNT_JSON');
  if (!raw) return null;
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    console.log('push: fcm_config_invalid');
    return null;
  }
  const account = ServiceAccount.safeParse(json);
  if (!account.success) {
    console.log('push: fcm_config_invalid');
    return null;
  }
  return fcmSender(account.data, { apiUrl: env.get('FCM_API_URL') || FCM_API_URL });
}
