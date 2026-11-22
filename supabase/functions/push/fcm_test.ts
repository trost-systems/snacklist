// fcmSender against a local fake of Google's token endpoint and FCM, with a throwaway RSA key.
import { assert, assertEquals } from '@std/assert';
import { jwtVerify } from 'jose';
import { type FcmMessage, fcmSender, senderFrom, type ServiceAccount } from './fcm.ts';

const PROJECT = 'snacklist-test';
const EMAIL = 'push@snacklist-test.iam.gserviceaccount.com';

async function throwawayKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const base64 = btoa(String.fromCharCode(...der)).replace(/(.{64})/g, '$1\n');
  return {
    pem: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----\n`,
    publicKey: pair.publicKey,
  };
}

const key = await throwawayKey();

interface Fcm {
  url: string;
  account: ServiceAccount;
  exchanges: number;
  sends: { auth: string | null; body: { message: FcmMessage } }[];
  /** What FCM answers for a token. */
  answers: Map<string, { status: number; body: unknown }>;
  expiresIn: number;
  close(): Promise<void>;
}

function fakeGoogle(): Fcm {
  const fcm: Fcm = {
    url: '',
    account: { project_id: PROJECT, client_email: EMAIL, private_key: key.pem, token_uri: '' },
    exchanges: 0,
    sends: [],
    answers: new Map(),
    expiresIn: 3599,
    close: () => server.shutdown(),
  };
  const server = Deno.serve({ port: 0, hostname: '127.0.0.1', onListen() {} }, async (req) => {
    const path = new URL(req.url).pathname;
    if (path === '/token') {
      const form = new URLSearchParams(await req.text());
      assertEquals(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
      const { payload, protectedHeader } = await jwtVerify(
        form.get('assertion') ?? '',
        key.publicKey,
        {
          issuer: EMAIL,
          audience: fcm.account.token_uri,
        },
      );
      assertEquals(protectedHeader.alg, 'RS256');
      assertEquals(payload.scope, 'https://www.googleapis.com/auth/firebase.messaging');
      assertEquals((payload.exp ?? 0) - (payload.iat ?? 0), 3600);
      fcm.exchanges++;
      return Response.json({
        access_token: `access-${fcm.exchanges}`,
        expires_in: fcm.expiresIn,
        token_type: 'Bearer',
      });
    }
    if (path === `/v1/projects/${PROJECT}/messages:send` && req.method === 'POST') {
      const body = await req.json() as { message: FcmMessage };
      fcm.sends.push({ auth: req.headers.get('authorization'), body });
      const answer = fcm.answers.get(body.message.token);
      if (answer) return Response.json(answer.body, { status: answer.status });
      return Response.json({ name: `projects/${PROJECT}/messages/1` });
    }
    return new Response('not found', { status: 418 });
  });
  const { port } = server.addr;
  fcm.url = `http://127.0.0.1:${port}`;
  fcm.account.token_uri = `${fcm.url}/token`;
  return fcm;
}

const message = (token: string): FcmMessage => ({
  token,
  notification: { title: 'Titel', body: 'Text' },
  data: {
    kind: 'list',
    v: '1',
    household_id: '00000000-0000-4000-8000-000000000001',
    list_id: '00000000-0000-4000-8000-000000000002',
  },
  android: { priority: 'high', ttl: '86400s' },
  apns: { headers: { 'apns-expiration': '1795000000' }, payload: { aps: { sound: 'default' } } },
});

const fcmError = (status: number, code: string, details: unknown[]) => ({
  status,
  body: { error: { code: status, message: 'x', status: code, details } },
});

Deno.test('trades a signed JWT for an access token and posts the message with it', async () => {
  const fcm = fakeGoogle();
  try {
    const sender = fcmSender(fcm.account, { apiUrl: fcm.url });
    assertEquals(await sender.send(message('test-token-a')), { outcome: 'sent' });
    assertEquals(fcm.exchanges, 1);
    assertEquals(fcm.sends, [{
      auth: 'Bearer access-1',
      body: { message: message('test-token-a') },
    }]);
  } finally {
    await fcm.close();
  }
});

Deno.test('keeps the access token until a minute before it expires, one exchange for parallel sends', async () => {
  const fcm = fakeGoogle();
  try {
    let now = Date.now();
    const sender = fcmSender(fcm.account, { apiUrl: fcm.url, now: () => now });
    await Promise.all(['a', 'b', 'c'].map((t) => sender.send(message(`test-token-${t}`))));
    assertEquals(fcm.exchanges, 1);
    now += (3599 - 61) * 1000;
    await sender.send(message('test-token-d'));
    assertEquals(fcm.exchanges, 1, 'still fresh 61 s before it expires');
    now += 2000;
    await sender.send(message('test-token-e'));
    assertEquals(fcm.exchanges, 2, 'renewed in its last minute');
    assertEquals(fcm.sends.at(-1)?.auth, 'Bearer access-2');
  } finally {
    await fcm.close();
  }
});

Deno.test('404 UNREGISTERED is unregistered', async () => {
  const fcm = fakeGoogle();
  try {
    fcm.answers.set(
      'test-token-gone',
      fcmError(404, 'NOT_FOUND', [{
        '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
        errorCode: 'UNREGISTERED',
      }]),
    );
    const sender = fcmSender(fcm.account, { apiUrl: fcm.url });
    assertEquals(await sender.send(message('test-token-gone')), { outcome: 'unregistered' });
  } finally {
    await fcm.close();
  }
});

Deno.test('a bare 404 (a wrong project or URL) is a failure, not an unregistered token', async () => {
  const fcm = fakeGoogle();
  try {
    fcm.answers.set('test-token-a', fcmError(404, 'NOT_FOUND', []));
    const sender = fcmSender(fcm.account, { apiUrl: fcm.url });
    assertEquals(await sender.send(message('test-token-a')), { outcome: 'failed', status: 404 });
  } finally {
    await fcm.close();
  }
});

Deno.test('400 INVALID_ARGUMENT on message.token is unregistered; on anything else it is a failure', async () => {
  const fcm = fakeGoogle();
  try {
    fcm.answers.set(
      'test-token-bad',
      fcmError(400, 'INVALID_ARGUMENT', [
        {
          '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
          errorCode: 'INVALID_ARGUMENT',
        },
        {
          '@type': 'type.googleapis.com/google.rpc.BadRequest',
          fieldViolations: [{ field: 'message.token', description: 'Invalid registration token' }],
        },
      ]),
    );
    fcm.answers.set(
      'test-token-payload',
      fcmError(400, 'INVALID_ARGUMENT', [
        {
          '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
          errorCode: 'INVALID_ARGUMENT',
        },
        {
          '@type': 'type.googleapis.com/google.rpc.BadRequest',
          fieldViolations: [{ field: 'message.android.ttl', description: 'Invalid duration' }],
        },
      ]),
    );
    fcm.answers.set('test-token-busy', fcmError(503, 'UNAVAILABLE', []));
    const sender = fcmSender(fcm.account, { apiUrl: fcm.url });
    assertEquals(await sender.send(message('test-token-bad')), { outcome: 'unregistered' });
    assertEquals(await sender.send(message('test-token-payload')), {
      outcome: 'failed',
      status: 400,
    });
    assertEquals(await sender.send(message('test-token-busy')), { outcome: 'failed', status: 503 });
  } finally {
    await fcm.close();
  }
});

Deno.test('a 401 drops the access token, so the next send trades again', async () => {
  const fcm = fakeGoogle();
  try {
    fcm.answers.set('test-token-401', fcmError(401, 'UNAUTHENTICATED', []));
    const sender = fcmSender(fcm.account, { apiUrl: fcm.url });
    assertEquals(await sender.send(message('test-token-401')), { outcome: 'failed', status: 401 });
    await sender.send(message('test-token-a'));
    assertEquals(fcm.exchanges, 2);
  } finally {
    await fcm.close();
  }
});

Deno.test('a failed exchange or an unreachable FCM is a failure, never a throw', async () => {
  const fcm = fakeGoogle();
  try {
    const wrongKey = { ...fcm.account, 'token_uri': `${fcm.url}/nowhere` };
    assertEquals(await fcmSender(wrongKey, { apiUrl: fcm.url }).send(message('test-token-a')), {
      outcome: 'failed',
      status: 0,
    });
  } finally {
    await fcm.close();
  }
  assertEquals(await fcmSender(fcm.account, { apiUrl: fcm.url }).send(message('test-token-a')), {
    outcome: 'failed',
    status: 0,
  });
});

Deno.test('senderFrom points the sender at FCM_API_URL', async () => {
  const fcm = fakeGoogle();
  try {
    const sender = senderFrom({
      get: (k) =>
        ({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify(fcm.account), FCM_API_URL: fcm.url })[k],
    });
    assert(sender);
    assertEquals(await sender.send(message('test-token-a')), { outcome: 'sent' });
    assertEquals(fcm.sends.length, 1);
  } finally {
    await fcm.close();
  }
});
