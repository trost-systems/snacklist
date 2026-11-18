// Job 275: the report handler in-process against a database with the repo's migrations, through
// the production store (store.ts) and a fake mailer: a report is stored trimmed with its ref and
// an empty name as null, the confirmation goes to the address and marks the row; a filled
// honeypot stores nothing; with LIMITS.perHour web reports in the last hour the next one is 429
// and stored nothing. Test addresses only; the rows it made are removed. The db gate sets
// FG_DB_TEST=1 and SUPABASE_DB_URL; without them this is skipped.
import { assertEquals, assertExists, assertMatch } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl } from '../_shared/db.ts';
import { configFrom, createHandler, LIMITS } from './handler.ts';
import type { Mail } from '../_shared/resend.ts';
import { sqlStore } from './store.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const PROXY = 'integration-proxy-secret';

function harness(sql: postgres.Sql, now: () => Date) {
  const sent: { to: string; mail: Mail; key: string }[] = [];
  const handler = createHandler({
    config: configFrom(new Map([['WAITLIST_PROXY_SECRET', PROXY]])).config,
    store: sqlStore(() => sql),
    mailer: {
      send(to, mail, key) {
        sent.push({ to, mail, key });
        return Promise.resolve();
      },
    },
    now,
    random: (n) => crypto.getRandomValues(new Uint8Array(n)),
    defer: (work) => work(),
    sleep: () => Promise.resolve(),
  });
  const call = (body: unknown) =>
    handler(
      new Request('http://localhost/report', {
        method: 'POST',
        headers: { 'x-waitlist-proxy-secret': PROXY },
        body: JSON.stringify(body),
      }),
    );
  return { sent, call };
}

const form = (email: string, extra: Record<string, unknown> = {}) => ({
  locale: 'en',
  category: 'personal_rights',
  location: '  Household "Flat 3", list Groceries, item "photo of me"  ',
  reason: 'This photo shows me and I never agreed to it being stored.',
  name: '',
  email,
  good_faith: true,
  website: '',
  ...extra,
});

interface Stored {
  id: string;
  ref: string;
  location: string;
  reporterName: string | null;
  reporterEmail: string | null;
  confirmationSentAt: Date | null;
}

Deno.test({
  name: 'a report, its confirmation, the honeypot and the hourly limit through the real database',
  ignore: !enabled,
  async fn() {
    const sql = postgres(databaseUrl(), { max: 2, prepare: false });
    // A time far from now(): the hour's count sees only this test's rows.
    const at = new Date(Date.UTC(2031, 0, 1) + Math.floor(Math.random() * 1e9) * 1000);
    const email = `test+report-${crypto.randomUUID()}@snacklist.app`;
    try {
      const { sent, call } = harness(sql, () => at);
      const res = await call(form(email));
      assertEquals(res.status, 201);
      const { ref } = await res.json();
      assertMatch(ref, /^M-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/);
      const [row] = await sql<Stored[]>`
        select id, ref, location, reporter_name as "reporterName", reporter_email as "reporterEmail",
          confirmation_sent_at as "confirmationSentAt"
        from public.content_reports where ref = ${ref}`;
      assertExists(row);
      assertEquals(row.location, 'Household "Flat 3", list Groceries, item "photo of me"');
      assertEquals([row.reporterName, row.reporterEmail], [null, email]);
      assertEquals(row.confirmationSentAt?.toISOString(), at.toISOString());
      assertEquals(sent.length, 1);
      assertEquals(sent[0]?.to, email);
      assertEquals(sent[0]?.key, `report-confirm/${row.id}`);
      assertEquals(sent[0]?.mail.subject, `We've received your report to Snacklist (${ref})`);

      const honeypot = await call(form(email, { website: 'filled' }));
      assertEquals(honeypot.status, 201);
      const [{ count }] = await sql<[{ count: number }]>`
        select count(*)::int as count from public.content_reports
        where reporter_email = ${email}`;
      assertEquals(count, 1, 'the honeypot stored nothing');

      for (let i = 1; i < LIMITS.perHour; i++) {
        assertEquals((await call(form(email))).status, 201);
      }
      const limited = await call(form(email));
      assertEquals(limited.status, 429);
      const [{ hour }] = await sql<[{ hour: number }]>`
        select count(*)::int as hour from public.content_reports
        where created_at > ${at.toISOString()}::timestamptz - interval '1 hour'
          and created_at <= ${at.toISOString()}::timestamptz`;
      assertEquals(hour, LIMITS.perHour, 'the one over the cap stored nothing');
      assertEquals(
        sent.length,
        LIMITS.perHour,
        'every stored report with the address got its confirmation',
      );
    } finally {
      await sql`delete from public.content_reports where reporter_email = ${email}`;
      await sql.end();
    }
  },
});
