// Job 82: the waitlist handler in-process against a database with the repo's migrations, through
// the production store (store.ts) and a fake mailer: a sign-up stores one row in any letter case
// and mails the confirmation; its token confirms once and the welcome mail follows; the one-click
// values delete the row and leave a proof record keyed by the address's HMAC; the sixth sign-up
// from one client in an hour is refused. Test addresses only. The db gate sets FG_DB_TEST=1 and
// SUPABASE_DB_URL; without them this is skipped.
import { assert, assertEquals } from '@std/assert';
import postgres from 'postgres';
import { CONSENT_VERSIONS } from './consent.ts';
import { hmacHex, sha256Hex } from './crypto.ts';
import { configFrom, createHandler, LIMITS } from './handler.ts';
import type { Mail } from './mail.ts';
import { sqlStore } from './store.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const PROXY = 'integration-proxy-secret';
const HMAC = 'integration-hmac-secret';

function harness(sql: postgres.Sql) {
  const sent: { to: string; mail: Mail }[] = [];
  const deferred: (() => Promise<void>)[] = [];
  const handler = createHandler({
    config: configFrom(
      new Map([
        ['WAITLIST_PROXY_SECRET', PROXY],
        ['WAITLIST_HMAC_SECRET', HMAC],
        ['WAITLIST_ALLOW_PLACEHOLDERS', '1'],
      ]),
    ).config,
    store: sqlStore(() => sql),
    mailer: {
      send(to, mail) {
        sent.push({ to, mail });
        return Promise.resolve();
      },
    },
    now: () => new Date(),
    random: (n) => crypto.getRandomValues(new Uint8Array(n)),
    defer: (work) => {
      deferred.push(work);
    },
  });
  const call = (route: string, body: unknown, client = 'integration-client') =>
    handler(
      new Request(`http://localhost/waitlist/${route}`, {
        method: 'POST',
        headers: { 'x-waitlist-proxy-secret': PROXY, 'x-waitlist-client': client },
        body: JSON.stringify(body),
      }),
    );
  const flush = async () => {
    while (deferred.length) await deferred.shift()!();
  };
  return { sent, call, flush };
}

const form = (email: string) => ({
  email,
  platform: 'android',
  locale: 'en',
  launch_news: true,
  consent_version: CONSENT_VERSIONS.en,
  website: '',
  elapsed_ms: 8000,
});

Deno.test({
  name: 'sign-up, confirm and one-click unsubscribe through the real database',
  ignore: !enabled,
  async fn() {
    const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 2, prepare: false });
    const email = `hello+it-${crypto.randomUUID()}@hummlist.com`;
    const proofKey = await hmacHex(HMAC, email.toLowerCase());
    const client = crypto.randomUUID();
    try {
      const { sent, call, flush } = harness(sql);
      assertEquals((await call('signup', form(email), client)).status, 202);
      assertEquals((await call('signup', form(email.toUpperCase()), client)).status, 202);
      await flush();
      const rows = await sql<{ id: string; email: string; confirm_token_hash: string }[]>`
        select id, email, confirm_token_hash from public.waitlist where lower(email) = ${email}`;
      assertEquals(rows.length, 1, 'one row in any letter case');
      assertEquals(rows[0].email, email);
      assertEquals(sent.map((s) => s.to), [email], 'one confirmation mail');
      const token = sent[0].mail.text.match(/#t=([A-Za-z0-9_-]{43})/)![1];
      assertEquals(rows[0].confirm_token_hash, await sha256Hex(token), 'only the hash is stored');

      assertEquals(await (await call('confirm', { token })).json(), { status: 'confirmed' });
      assertEquals(await (await call('confirm', { token })).json(), { status: 'invalid' });
      await flush();
      assertEquals(sent.length, 2, 'the welcome mail');
      const [row] = await sql<{ confirmed: boolean; mailed: boolean }[]>`
        select confirmed_at is not null as confirmed, last_mail_at >= confirmed_at as mailed
        from public.waitlist where id = ${rows[0].id}`;
      assertEquals(row, { confirmed: true, mailed: true });

      const url = new URL(sent[1].mail.headers['List-Unsubscribe'].slice(1, -1));
      const id = url.searchParams.get('id')!;
      assertEquals(id, rows[0].id);
      const sig = url.searchParams.get('s')!;
      assertEquals(await (await call('unsubscribe', { id, sig })).json(), { status: 'deleted' });
      const [left] = await sql<{ rows: number; proofs: number }[]>`
        select (select count(*)::int from public.waitlist where lower(email) = ${email}) as rows,
               (select count(*)::int from public.waitlist_consent_proof
                where email_hmac = ${proofKey} and end_reason = 'unsubscribed'
                  and launch_news and locale = 'en') as proofs`;
      assertEquals(left, { rows: 0, proofs: 1 });
      assertEquals(await (await call('unsubscribe', { id, sig })).json(), { status: 'deleted' });
    } finally {
      await sql`delete from public.waitlist where lower(email) = ${email}`;
      await sql`delete from public.waitlist_consent_proof where email_hmac = ${proofKey}`;
      await sql`delete from public.waitlist_rate where key_hash = ${await sha256Hex(client)}`;
      await sql.end();
    }
  },
});

Deno.test({
  name: 'one sign-up over the per-client limit in an hour is refused by waitlist_rate_hit',
  ignore: !enabled,
  async fn() {
    const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 2, prepare: false });
    const client = crypto.randomUUID();
    try {
      const { call } = harness(sql);
      const statuses = [];
      for (let i = 0; i <= LIMITS.perKey; i++) {
        statuses.push(
          (await call('signup', { ...form('x'), email: 'hello+rate@hummlist.com' }, client)).status,
        );
      }
      assertEquals(statuses, [...Array(LIMITS.perKey).fill(202), 429]);
      const [counter] = await sql<{ hits: number }[]>`
        select hits from public.waitlist_rate where key_hash = ${await sha256Hex(client)}`;
      assert(counter.hits === LIMITS.perKey + 1, 'the counter holds the hashed key only');
    } finally {
      await sql`delete from public.waitlist_rate where key_hash = ${await sha256Hex(client)}`;
      await sql.end();
    }
  },
});
