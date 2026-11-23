import { assertEquals, assertRejects, assertThrows } from 'jsr:@std/assert@^1';
import {
  describe,
  grantedForGood,
  grantEntitlement,
  parseArgs,
  premiumEntitlementId,
  reconcileUrl,
} from './promotional.ts';
import { RevenueCatUnavailable } from '../../supabase/functions/purchases/promotional.ts';

const HOME = 'eb021cef-9284-4e67-91a8-2c63780db5ae';

Deno.test('parseArgs: a household id, dry run unless --apply', () => {
  assertEquals(parseArgs(['status', '--household', HOME]), {
    action: 'status',
    appUserId: HOME,
    apply: false,
  });
  assertEquals(parseArgs(['reconcile', '--household', HOME.toUpperCase(), '--apply']), {
    action: 'reconcile',
    appUserId: HOME,
    apply: true,
  });
  assertThrows(() => parseArgs(['status', '--household', HOME, '--apply']));
  assertThrows(() => parseArgs(['reconcile', '--household', 'peter@example.com']));
  assertThrows(() => parseArgs(['reconcile']));
  assertEquals(parseArgs(['grant', '--household', HOME, '--apply']).apply, true);
  assertThrows(() => parseArgs(['revoke', '--household', HOME]));
});

Deno.test('describe says what RevenueCat grants, and until when', () => {
  assertEquals(describe({ active: false }), 'no promotional premium at RevenueCat');
  assertEquals(
    describe({ active: true, expiresAt: new Date('2100-01-01T00:00:00Z') }),
    'promotional premium at RevenueCat until 2100-01-01T00:00:00.000Z',
  );
  assertEquals(
    describe({ active: true, expiresAt: null }),
    'promotional premium at RevenueCat, without end',
  );
});

Deno.test('reconcileUrl: the hosted project by default, the local stack on request', () => {
  const env = (vars: Record<string, string>) => (k: string) => vars[k];
  assertEquals(
    reconcileUrl(env({})),
    'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/purchases/revenuecat/reconcile' +
      '?forceFunctionRegion=eu-central-1',
  );
  assertEquals(
    reconcileUrl(env({ PURCHASES_URL: 'http://127.0.0.1:54321/functions/v1/purchases/' })),
    'http://127.0.0.1:54321/functions/v1/purchases/revenuecat/reconcile',
  );
  assertThrows(() => reconcileUrl(env({ SUPABASE_PROJECT_REF: 'evil.example/x' })));
});

Deno.test('grantedForGood: an endless grant, or one to 2100, is left alone; anything less is granted', () => {
  assertEquals(grantedForGood({ active: false }), false);
  assertEquals(grantedForGood({ active: true, expiresAt: null }), true);
  assertEquals(grantedForGood({ active: true, expiresAt: new Date('2100-01-01T00:00:00Z') }), true);
  assertEquals(
    grantedForGood({ active: true, expiresAt: new Date('2027-01-01T00:00:00Z') }),
    false,
  );
});

Deno.test('grantEntitlement: grants premium until 2100, creating an unknown customer first', async () => {
  const calls: { url: string; body: unknown }[] = [];
  let known = false;
  const fetch = (url: string | URL | Request, init?: RequestInit) => {
    const u = String(url);
    calls.push({ url: u, body: JSON.parse(String(init?.body)) });
    if (u.endsWith('/customers')) {
      known = true;
      return Promise.resolve(new Response('{}', { status: 201 }));
    }
    return Promise.resolve(new Response('{}', { status: known ? 201 : 404 }));
  };
  await grantEntitlement(
    { secretKey: 'sk_test', projectId: 'proj1' },
    HOME,
    fetch as typeof globalThis.fetch,
  );
  const grant = { entitlement_id: premiumEntitlementId, expires_at: Date.UTC(2100, 0, 1) };
  assertEquals(calls, [
    {
      url:
        `https://api.revenuecat.com/v2/projects/proj1/customers/${HOME}/actions/grant_entitlement`,
      body: grant,
    },
    { url: 'https://api.revenuecat.com/v2/projects/proj1/customers', body: { id: HOME } },
    {
      url:
        `https://api.revenuecat.com/v2/projects/proj1/customers/${HOME}/actions/grant_entitlement`,
      body: grant,
    },
  ]);
});

Deno.test('grantEntitlement: a refusal fails', async () => {
  const fetch = () => Promise.resolve(new Response('{}', { status: 403 }));
  await assertRejects(() =>
    grantEntitlement(
      { secretKey: 'sk_test', projectId: 'proj1' },
      HOME,
      fetch as typeof globalThis.fetch,
    )
  );
});

Deno.test('grantEntitlement: RevenueCat never answering times out as RevenueCatUnavailable', async () => {
  const hang = () => new Promise<Response>(() => {});
  await assertRejects(
    () => grantEntitlement({ secretKey: 'sk_test', projectId: 'proj1' }, HOME, hang, 20),
    RevenueCatUnavailable,
  );
});

Deno.test('parseArgs: --user takes an account id like --household', () => {
  assertEquals(parseArgs(['grant', '--user', HOME, '--apply']), {
    action: 'grant',
    appUserId: HOME,
    apply: true,
  });
});
