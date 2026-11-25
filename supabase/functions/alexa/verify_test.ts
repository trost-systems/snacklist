// AC5: every rule of Alexa's request verification, each on its own. A refused request never
// reaches the handler's database code (handler_test.ts checks that part).
import { assert, assertEquals, assertRejects } from '@std/assert';
import { amazonRootsPem } from './anchors.ts';
import { echoApiCert12 } from './testdata/echo_api_cert_12.ts';
import { makeTestCa, type TestCa, testCertUrl, testSkillId } from './test_ca.ts';
import {
  cachingFetcher,
  certUrlAllowed,
  checkChain,
  parseCertificates,
  type Rejection,
  VerificationError,
  type VerifyDeps,
  verifyRequest,
} from './verify.ts';

const now = new Date();

function envelope(overrides: { timestamp?: string; skill?: string; type?: string } = {}) {
  return JSON.stringify({
    version: '1.0',
    session: { new: true, sessionId: 's', application: { applicationId: testSkillId } },
    context: { System: { application: { applicationId: overrides.skill ?? testSkillId } } },
    request: {
      type: overrides.type ?? 'LaunchRequest',
      requestId: 'r',
      timestamp: overrides.timestamp ?? now.toISOString(),
      locale: 'de-DE',
    },
  });
}

let ca: TestCa | undefined;
const testCa = async () => (ca ??= await makeTestCa());

async function deps(over: Partial<VerifyDeps> = {}): Promise<VerifyDeps> {
  const { root, chainPem } = await testCa();
  return {
    anchors: [root],
    fetchChain: () => Promise.resolve(chainPem),
    skillIds: [testSkillId],
    now: () => now,
    ...over,
  };
}

async function signed(body: string, headers: Record<string, string> = {}) {
  return new Headers({
    signaturecertchainurl: testCertUrl,
    'signature-256': await (await testCa()).sign(body),
    ...headers,
  });
}

async function refused(
  reason: Rejection,
  run: () => Promise<unknown>,
) {
  const error = await assertRejects(run, VerificationError);
  assertEquals(error.reason, reason);
}

const bytes = (text: string) => new TextEncoder().encode(text);

Deno.test('a correctly signed, fresh request for our skill passes', async () => {
  const body = envelope();
  const parsed = await verifyRequest(await signed(body), bytes(body), await deps());
  assertEquals(parsed.request.type, 'LaunchRequest');
});

Deno.test('cert URL rules: https, s3.amazonaws.com, /echo.api/, port 443', () => {
  for (
    const ok of [
      'https://s3.amazonaws.com/echo.api/echo-api-cert.pem',
      'https://s3.amazonaws.com:443/echo.api/echo-api-cert.pem',
      'https://S3.AMAZONAWS.COM/echo.api/echo-api-cert.pem',
      'HTTPS://s3.amazonaws.com/echo.api/echo-api-cert.pem',
      'https://s3.amazonaws.com/echo.api/../echo.api/echo-api-cert.pem',
    ]
  ) assert(certUrlAllowed(ok), ok);
  for (
    const bad of [
      'http://s3.amazonaws.com/echo.api/echo-api-cert.pem',
      'https://notamazon.com/echo.api/echo-api-cert.pem',
      'https://s3.amazonaws.com.evil.example/echo.api/echo-api-cert.pem',
      'https://s3.amazonaws.com/EcHo.aPi/echo-api-cert.pem',
      'https://s3.amazonaws.com/invalid.path/echo-api-cert.pem',
      'https://s3.amazonaws.com/echo.api/../invalid.path/echo-api-cert.pem',
      'https://s3.amazonaws.com:563/echo.api/echo-api-cert.pem',
      'https://user:pw@s3.amazonaws.com/echo.api/echo-api-cert.pem',
      'not a url',
    ]
  ) assertEquals(certUrlAllowed(bad), null, bad);
});

Deno.test('a request without signature headers is refused', async () => {
  const body = envelope();
  const d = await deps();
  await refused('missing_signature', () => verifyRequest(new Headers(), bytes(body), d));
  await refused(
    'missing_signature',
    () => verifyRequest(new Headers({ signaturecertchainurl: testCertUrl }), bytes(body), d),
  );
});

Deno.test('a cert URL off the rules is refused before anything is fetched', async () => {
  const body = envelope();
  let fetched = false;
  const d = await deps({
    fetchChain: () => {
      fetched = true;
      return Promise.resolve('');
    },
  });
  const headers = await signed(body, {
    signaturecertchainurl: 'https://evil.example/echo.api/echo-api-cert.pem',
  });
  await refused('bad_cert_url', () => verifyRequest(headers, bytes(body), d));
  assertEquals(fetched, false);
});

Deno.test('an unreachable or garbled certificate chain is refused', async () => {
  const body = envelope();
  const headers = await signed(body);
  await refused(
    'cert_unavailable',
    async () =>
      verifyRequest(
        headers,
        bytes(body),
        await deps({ fetchChain: () => Promise.reject(new Error('404')) }),
      ),
  );
  await refused(
    'cert_unavailable',
    async () =>
      verifyRequest(headers, bytes(body), await deps({ fetchChain: () => Promise.resolve('x') })),
  );
});

Deno.test('an expired or not yet valid signing certificate is refused', async () => {
  const day = 86_400_000;
  for (
    const window of [
      { notBefore: new Date(now.getTime() - 9 * day), notAfter: new Date(now.getTime() - day) },
      { notBefore: new Date(now.getTime() + day), notAfter: new Date(now.getTime() + 9 * day) },
    ]
  ) {
    const other = await makeTestCa(window);
    const body = envelope();
    const headers = new Headers({
      signaturecertchainurl: testCertUrl,
      'signature-256': await other.sign(body),
    });
    await refused(
      'cert_expired',
      async () =>
        verifyRequest(
          headers,
          bytes(body),
          await deps({ anchors: [other.root], fetchChain: () => Promise.resolve(other.chainPem) }),
        ),
    );
  }
});

Deno.test('a certificate for another host than echo-api.amazon.com is refused', async () => {
  const other = await makeTestCa({ host: 'echo-api.amazon.com.evil.example' });
  const body = envelope();
  const headers = new Headers({
    signaturecertchainurl: testCertUrl,
    'signature-256': await other.sign(body),
  });
  await refused(
    'cert_wrong_host',
    async () =>
      verifyRequest(
        headers,
        bytes(body),
        await deps({ anchors: [other.root], fetchChain: () => Promise.resolve(other.chainPem) }),
      ),
  );
});

Deno.test('a chain that does not end in a pinned root is refused', async () => {
  // A self-made chain, perfectly signed, checked against Amazon's real roots.
  const body = envelope();
  const headers = await signed(body);
  await refused(
    'cert_untrusted',
    async () =>
      verifyRequest(
        headers,
        bytes(body),
        await deps({ anchors: parseCertificates(amazonRootsPem) }),
      ),
  );
});

Deno.test('an intermediate that is not a CA breaks the chain', async () => {
  const other = await makeTestCa({ intermediateNotCa: true });
  const body = envelope();
  const headers = new Headers({
    signaturecertchainurl: testCertUrl,
    'signature-256': await other.sign(body),
  });
  await refused(
    'cert_untrusted',
    async () =>
      verifyRequest(
        headers,
        bytes(body),
        await deps({ anchors: [other.root], fetchChain: () => Promise.resolve(other.chainPem) }),
      ),
  );
});

Deno.test('a real Amazon chain checks out against the pinned roots, at a time it was valid', async () => {
  const pem = echoApiCert12;
  const anchors = parseCertificates(amazonRootsPem);
  const leaf = await checkChain(pem, anchors, new Date('2023-07-01T00:00:00Z'));
  assertEquals(leaf.subject, 'CN=echo-api.amazon.com');
  // The same chain today: its leaf expired in 2023.
  const error = await assertRejects(() => checkChain(pem, anchors, now), VerificationError);
  assertEquals(error.reason, 'cert_expired');
});

Deno.test('a body changed after signing, or a bad signature, is refused', async () => {
  const body = envelope();
  const headers = await signed(body);
  const d = await deps();
  const tampered = body.replace('LaunchRequest', 'IntentRequest');
  await refused('bad_signature', () => verifyRequest(headers, bytes(tampered), d));
  for (const signature of ['', 'not base64!', btoa('x'.repeat(256))]) {
    const h = new Headers(headers);
    h.set('signature-256', signature);
    await refused(
      signature === '' ? 'missing_signature' : 'bad_signature',
      () => verifyRequest(h, bytes(body), d),
    );
  }
});

Deno.test('a chain that passed is checked again once a certificate in it expired', async () => {
  const day = 86_400_000;
  const other = await makeTestCa({ intermediateNotAfter: new Date(now.getTime() + 2 * day) });
  const at = (ms: number) => new Date(now.getTime() + ms);
  const d = (when: Date) => ({
    anchors: [other.root],
    fetchChain: () => Promise.resolve(other.chainPem),
    skillIds: [testSkillId],
    now: () => when,
  });
  const anchors = [other.root];
  const request = async (when: Date, sign = other.sign) => {
    const body = envelope({ timestamp: when.toISOString() });
    const headers = new Headers({
      signaturecertchainurl: testCertUrl,
      'signature-256': await sign(body),
    });
    return () => verifyRequest(headers, bytes(body), { ...d(when), anchors });
  };
  await (await request(now))();
  await (await request(at(day)))();
  // The signature is checked on every request, also with a chain that passed.
  const stranger = await makeTestCa();
  await refused('bad_signature', await request(at(day), stranger.sign));
  // The intermediate expired on day 2, the leaf on day 7: the same chain no longer passes.
  await refused('cert_untrusted', await request(at(3 * day)));
  await refused('cert_expired', await request(at(8 * day)));
  // A pass against these anchors is not one against others.
  await refused(
    'cert_untrusted',
    async () => {
      const body = envelope();
      return verifyRequest(
        new Headers({
          signaturecertchainurl: testCertUrl,
          'signature-256': await other.sign(body),
        }),
        bytes(body),
        { ...d(now), anchors: parseCertificates(amazonRootsPem) },
      );
    },
  );
});

Deno.test('a timestamp more than 150 s away is refused, an hour for skill events', async () => {
  const d = await deps();
  const at = (ms: number) => new Date(now.getTime() + ms).toISOString();
  for (const skew of [-151_000, 151_000]) {
    const body = envelope({ timestamp: at(skew) });
    await refused('stale_timestamp', async () => verifyRequest(await signed(body), bytes(body), d));
  }
  for (const skew of [-149_000, 149_000]) {
    const body = envelope({ timestamp: at(skew) });
    await verifyRequest(await signed(body), bytes(body), d);
  }
  const garbled = envelope({ timestamp: 'yesterday' });
  await refused(
    'stale_timestamp',
    async () => verifyRequest(await signed(garbled), bytes(garbled), d),
  );
  const event = envelope({ timestamp: at(-1_800_000), type: 'AlexaSkillEvent.SkillDisabled' });
  await verifyRequest(await signed(event), bytes(event), d);
  const late = envelope({ timestamp: at(-3_700_000), type: 'AlexaSkillEvent.SkillDisabled' });
  await refused('stale_timestamp', async () => verifyRequest(await signed(late), bytes(late), d));
});

Deno.test('a request for another skill, or with no skill id configured, is refused', async () => {
  const body = envelope({ skill: 'amzn1.ask.skill.someone-else' });
  await refused(
    'wrong_skill',
    async () => verifyRequest(await signed(body), bytes(body), await deps()),
  );
  const ours = envelope();
  await refused(
    'wrong_skill',
    async () => verifyRequest(await signed(ours), bytes(ours), await deps({ skillIds: [] })),
  );
});

Deno.test('a signed body that is not an Alexa request is refused', async () => {
  const body = '{"hello": "world"}';
  await refused(
    'bad_body',
    async () => verifyRequest(await signed(body), bytes(body), await deps()),
  );
});

Deno.test('the chain fetcher keeps a chain, retries after a failure, and caps the size', async () => {
  let calls = 0;
  let fail = true;
  const fetcher = cachingFetcher(
    (() => {
      calls++;
      if (fail) return Promise.resolve(new Response('nope', { status: 503 }));
      return Promise.resolve(new Response('PEM'));
    }) as typeof fetch,
  );
  const url = new URL(testCertUrl);
  await assertRejects(() => fetcher(url));
  fail = false;
  assertEquals(await fetcher(url), 'PEM');
  assertEquals(await fetcher(url), 'PEM');
  assertEquals(calls, 2);
  const big = cachingFetcher(() => Promise.resolve(new Response('x'.repeat(70_000))));
  await assertRejects(() => big(url));
});

Deno.test('the chain fetcher keeps one entry per path, whatever the query, and at most 16', async () => {
  const fetched: string[] = [];
  const fetcher = cachingFetcher(
    ((input: string | URL | Request) => {
      fetched.push(String(input));
      return Promise.resolve(new Response('PEM'));
    }) as typeof fetch,
  );
  for (const suffix of ['', '?a=1', '?a=2', '#x']) await fetcher(new URL(testCertUrl + suffix));
  assertEquals(fetched, [testCertUrl], 'one fetch, without the query');

  const other = (n: number) => new URL(`https://s3.amazonaws.com/echo.api/other-${n}.pem`);
  for (let n = 1; n <= 16; n++) await fetcher(other(n));
  assertEquals(fetched.length, 17);
  await fetcher(other(16));
  assertEquals(fetched.length, 17, 'the newest is kept');
  await fetcher(new URL(testCertUrl));
  assertEquals(fetched.length, 18, 'the oldest made room');
});

Deno.test('the chain fetcher gives no place to a path that cannot be fetched', async () => {
  const fetched: string[] = [];
  const fetcher = cachingFetcher(
    ((input: string | URL | Request) => {
      fetched.push(String(input));
      const missing = String(input).includes('/made-up-');
      return Promise.resolve(missing ? new Response('no', { status: 403 }) : new Response('PEM'));
    }) as typeof fetch,
  );
  await fetcher(new URL(testCertUrl));
  const madeUp = Array.from(
    { length: 40 },
    (_, n) => fetcher(new URL(`https://s3.amazonaws.com/echo.api/made-up-${n}.pem`)),
  );
  const [again, ...refused] = await Promise.allSettled([fetcher(new URL(testCertUrl)), ...madeUp]);
  assertEquals(again, { status: 'fulfilled', value: 'PEM' });
  assertEquals(refused.filter((r) => r.status === 'rejected').length, 40);
  await fetcher(new URL(testCertUrl));
  assertEquals(fetched.filter((url) => url === testCertUrl).length, 1, 'the chain kept its place');
});
