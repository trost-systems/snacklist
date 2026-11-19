// Job 281: the app route against the local stack's edge runtime and database. A session token of
// a fresh account stores an app report with its target, screenshot and sender row, with CORS
// headers and without the proxy secret; no token, an API key's prefix and junk are refused; after
// APP_LIMITS.perUserHour reports the user gets 429 and nothing more is stored, while a second user
// still gets through. Throwaway accounts and test addresses; the rows it made are removed. The db
// gate sets FG_DB_TEST=1, SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_DB_URL; without them this
// is skipped.
import { assert, assertEquals, assertExists, assertMatch } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl } from '../_shared/db.ts';
import { APP_LIMITS } from './handler.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
function env(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined) throw new Error(`${name} is not set`);
  return value;
}

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);
const PASSWORD = `${crypto.randomUUID()}-Aa1`;
const REF = /^M-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;

type User = { id: string; token: string };

async function signUp(): Promise<User> {
  const res = await fetch(`${env('SUPABASE_URL')}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: env('SUPABASE_ANON_KEY'), 'content-type': 'application/json' },
    body: JSON.stringify({
      email: `report-app-${crypto.randomUUID()}@fg-test.invalid`,
      password: PASSWORD,
    }),
  });
  const session = await res.json();
  assert(session.access_token, JSON.stringify(session));
  return { id: session.user.id, token: session.access_token };
}

function report(token: string | null, body: unknown): Promise<Response> {
  return fetch(`${env('SUPABASE_URL')}/functions/v1/report/app`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token === null ? {} : { authorization: `Bearer ${token}` }),
    },
    body: JSON.stringify(body),
  });
}

const form = (email: string, extra: Record<string, unknown> = {}) => ({
  locale: 'en',
  category: 'personal_rights',
  target: { kind: 'item', id: '7c9e6679-7425-40de-944b-e07fc1f90ae7' },
  location: 'item "Foto" in list "Einkauf", household "WG"',
  reason: 'This item names me and my address without my consent.',
  name: '',
  email,
  good_faith: true,
  screenshot: btoa(String.fromCharCode(...PNG)),
  ...extra,
});

/** The function's answer as `<status> <error or "ref">`. */
async function outcome(res: Response): Promise<string> {
  const body = await res.json() as { error?: string; ref?: string };
  return `${res.status} ${body.error ?? (body.ref ? 'ref' : JSON.stringify(body))}`;
}

Deno.test({
  name: 'app reports through the edge runtime: stored with target and screenshot, limited per user',
  ignore: !enabled,
  async fn() {
    const sql = postgres(databaseUrl(), { max: 2, prepare: false });
    const email = `test+report-app-${crypto.randomUUID()}@snacklist.app`;
    const [first, second] = await Promise.all([signUp(), signUp()]);
    const refs: string[] = [];
    try {
      assertEquals(await outcome(await report(null, form(email))), '401 missing_token');
      assertEquals(
        await outcome(await report('fgp_not-a-session', form(email))),
        '403 session_required',
      );
      assertEquals(await outcome(await report('junk', form(email))), '401 invalid_token');

      const res = await report(first.token, form(email));
      assertEquals(res.headers.get('access-control-allow-origin'), '*');
      const { ref } = await res.json();
      assertEquals(res.status, 201);
      assertMatch(ref, REF);
      refs.push(ref);
      const [row] = await sql<
        { source: string; targetKind: string; targetId: string; email: string; png: Uint8Array }[]
      >`
        select r.source, r.target_kind as "targetKind", r.target_id::text as "targetId",
          r.reporter_email as email, s.png
        from public.content_reports r join public.content_report_screenshots s on s.report_id = r.id
        where r.ref = ${ref}`;
      assertExists(row);
      assertEquals(
        [row.source, row.targetKind, row.targetId, row.email],
        ['app', 'item', '7c9e6679-7425-40de-944b-e07fc1f90ae7', email],
      );
      assertEquals(new Uint8Array(row.png), PNG);
      const [{ senders }] = await sql<[{ senders: number }]>`
        select count(*)::int as senders from public.content_report_app_senders
        where user_id = ${first.id}::uuid`;
      assertEquals(senders, 1, 'the sender row counts toward the user limit');

      for (let i = 1; i < APP_LIMITS.perUserHour; i++) {
        const more = await report(first.token, form(email, { target: { kind: 'elsewhere' } }));
        assertEquals(more.status, 201);
        refs.push((await more.json()).ref);
      }
      assertEquals(await outcome(await report(first.token, form(email))), '429 rate_limited');
      const [{ stored }] = await sql<[{ stored: number }]>`
        select count(*)::int as stored from public.content_reports where reporter_email = ${email}`;
      assertEquals(stored, APP_LIMITS.perUserHour, 'the refused report stored nothing');

      const other = await report(second.token, form(email));
      assertEquals(other.status, 201, 'a second user is limited on their own');
      refs.push((await other.json()).ref);
    } finally {
      await sql`delete from public.content_reports where reporter_email = ${email}`;
      await sql`delete from public.content_report_app_senders
        where user_id in (${first.id}::uuid, ${second.id}::uuid)`;
      await sql`delete from auth.users where id in (${first.id}::uuid, ${second.id}::uuid)`;
      await sql.end();
    }
    assertEquals(refs.length, APP_LIMITS.perUserHour + 1);
  },
});
