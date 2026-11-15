// Job 267 and its review 0: feedback screenshots against the local stack's real Storage API, edge
// runtime and database. A client stores nothing itself: no direct upload, no signed upload URL
// (the review's bypass), not even past the quota. Through the function's upload route a session
// stores <own id>/<uuid>.png (again: 200 with the same name); a bad id, no PNG, over 2 MiB, no or
// a foreign session and an API key are refused; at most 10 a day, and a retry of a stored name at
// the quota still answers 200; 15 parallel uploads of one user store exactly 10, and parallel
// uploads of several users stop exactly at the bucket's 250. Clients cannot download, list, sign,
// overwrite or remove any object, their own included. The sweep, through the production store and
// remover, removes a deleted note's image, an account's images (with a note or without, however
// young) right after the account deletion and an orphan older than a day, and keeps a young
// orphan and a note's image. Throwaway accounts, removed after. The db gate sets FG_DB_TEST=1,
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_DB_URL and SUPABASE_SERVICE_ROLE_KEY; without them
// this is skipped.
import { assert, assertEquals } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl } from '../_shared/db.ts';
import {
  BUCKET,
  sqlSweepStore,
  storageRemover,
  sweepFeedbackScreenshots,
} from '../_shared/feedback_screenshots.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
function env(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined) throw new Error(`${name} is not set`);
  return value;
}

const api = () => env('SUPABASE_URL');
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const PASSWORD = `${crypto.randomUUID()}-Aa1`;

type User = { id: string; token: string };

async function signUp(): Promise<User> {
  const res = await fetch(`${api()}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: env('SUPABASE_ANON_KEY'), 'content-type': 'application/json' },
    body: JSON.stringify({
      email: `shot-${crypto.randomUUID()}@fg-test.invalid`,
      password: PASSWORD,
    }),
  });
  const session = await res.json();
  assert(session.access_token, JSON.stringify(session));
  return { id: session.user.id, token: session.access_token };
}

const headers = (token: string) => ({
  apikey: env('SUPABASE_ANON_KEY'),
  authorization: `Bearer ${token}`,
});
const service = () => {
  const key = env('SUPABASE_SERVICE_ROLE_KEY');
  return { apikey: key, authorization: `Bearer ${key}` };
};

/** The Storage API's answer as `ok` or `<statusCode> <error>` (it may answer HTTP 400 with them). */
async function outcome(res: Response): Promise<string> {
  const body = await res.json().catch(() => null) as
    | { statusCode?: string; error?: string }
    | unknown[]
    | null;
  if (res.ok) return Array.isArray(body) ? `ok ${body.length}` : 'ok';
  const statusCode = (body as { statusCode?: string })?.statusCode ?? String(res.status);
  return `${statusCode} ${(body as { error?: string })?.error}`;
}

/** The function's answer as `<status> <error or name>`. */
async function answer(res: Response): Promise<string> {
  const body = await res.json() as { error?: string; name?: string };
  return `${res.status} ${body.error ?? body.name}`;
}

/** Through the function: the only way in. */
function upload(
  token: string | null,
  id: string,
  body: Uint8Array<ArrayBuffer> = PNG,
  type = 'image/png',
): Promise<Response> {
  return fetch(`${api()}/functions/v1/feedback-screenshots/upload/${id}`, {
    method: 'POST',
    headers: {
      'content-type': type,
      ...(token === null ? {} : { authorization: `Bearer ${token}` }),
    },
    body,
  });
}

/** Straight to the Storage API, as the client. */
function directUpload(token: string, name: string): Promise<Response> {
  return fetch(`${api()}/storage/v1/object/${BUCKET}/${name}`, {
    method: 'POST',
    headers: { ...headers(token), 'content-type': 'image/png' },
    body: PNG,
  });
}

/**
 * The review's bypass: signed upload URLs, all minted first (signing tries the insert and rolls it
 * back, so it used up no quota), then a PUT to each that came back. Answers how each went.
 */
async function signedUploads(token: string, names: string[]): Promise<string[]> {
  const signed = await Promise.all(names.map(async (name) => {
    const sign = await fetch(`${api()}/storage/v1/object/upload/sign/${BUCKET}/${name}`, {
      method: 'POST',
      headers: headers(token),
    });
    if (!sign.ok) return `sign ${await outcome(sign)}`;
    const { url } = await sign.json() as { url: string };
    return url;
  }));
  const results: string[] = [];
  for (const url of signed) {
    if (!url.startsWith('/')) {
      results.push(url);
      continue;
    }
    const put = await fetch(`${api()}/storage/v1${url}`, {
      method: 'PUT',
      headers: { 'content-type': 'image/png' },
      body: PNG,
    });
    results.push(`put ${await outcome(put)}`);
  }
  return results;
}

/** Whether the service key still finds the object. */
async function stored(name: string): Promise<boolean> {
  const res = await fetch(`${api()}/storage/v1/object/${BUCKET}/${name}`, { headers: service() });
  await res.body?.cancel();
  return res.ok;
}

const nameOf = (user: User, id: string) => `${user.id}/${id}.png`;

Deno.test({
  name: 'feedback screenshots: only the function stores them, within the quotas; the sweep',
  ignore: !enabled,
  async fn() {
    const sql = postgres(databaseUrl(), { max: 2, prepare: false });
    const sweep = () =>
      sweepFeedbackScreenshots(
        sqlSweepStore(() => sql),
        storageRemover(api(), env('SUPABASE_SERVICE_ROLE_KEY')),
      );
    const objectsOf = async (user: User | null) => {
      const prefix = user === null ? '%' : `${user.id}/%`;
      const [row] = await sql<{ n: number }[]>`
        select count(*)::int as n from storage.objects
        where bucket_id = ${BUCKET} and name like ${prefix}`;
      return row?.n;
    };
    const users = await Promise.all(Array.from({ length: 7 }, signUp));
    const [anna, ben, cora, dora, eve, fay, gus] = users;
    assert(anna && ben && cora && dora && eve && fay && gus);
    try {
      const note = async (user: User, id: string) => {
        const res = await fetch(`${api()}/rest/v1/feedback`, {
          method: 'POST',
          headers: {
            ...headers(user.token),
            'content-type': 'application/json',
            prefer: 'return=minimal',
          },
          body: JSON.stringify({
            id,
            message: 'Siehe Bild',
            app_version: '1.0.0',
            build: '1',
            platform: 'ios',
            os_version: 'iOS 18.1',
            locale: 'de',
            screenshot: nameOf(user, id),
          }),
        });
        assertEquals(res.status, 201, await res.text());
      };

      // A client stores nothing itself.
      assertEquals(
        await outcome(await directUpload(anna.token, nameOf(anna, crypto.randomUUID()))),
        '403 Unauthorized',
        'no direct upload',
      );
      assertEquals(
        await signedUploads(anna.token, [nameOf(anna, crypto.randomUUID())]),
        ['sign 403 Unauthorized'],
        'no signed upload URL',
      );
      assertEquals(await objectsOf(anna), 0);

      // Through the function.
      const kept = crypto.randomUUID();
      assertEquals(await answer(await upload(anna.token, kept)), `200 ${nameOf(anna, kept)}`);
      assert(await stored(nameOf(anna, kept)), 'stored');
      assertEquals(
        await answer(await upload(anna.token, kept)),
        `200 ${nameOf(anna, kept)}`,
        'the same name again',
      );
      assertEquals(
        await answer(await upload(anna.token, kept.toUpperCase())),
        '400 bad_request',
        'an uppercase id',
      );
      assertEquals(
        await answer(
          await upload(anna.token, crypto.randomUUID(), new TextEncoder().encode('<svg/>')),
        ),
        '415 not_png',
        'not a PNG, though declared one',
      );
      const big = new Uint8Array(2 * 1024 * 1024 + 1);
      big.set(PNG);
      assertEquals(
        await answer(await upload(anna.token, crypto.randomUUID(), big)),
        '413 too_large',
        'over 2 MiB',
      );
      assertEquals(
        await answer(await upload(anna.token, crypto.randomUUID(), new Uint8Array())),
        '400 bad_request',
        'an empty body',
      );
      assertEquals(await answer(await upload(null, crypto.randomUUID())), '401 missing_token');
      assertEquals(
        await answer(await upload(env('SUPABASE_ANON_KEY'), crypto.randomUUID())),
        '401 invalid_token',
        'the publishable key is no session',
      );
      const [head, payload] = anna.token.split('.');
      assertEquals(
        await answer(await upload(`${head}.${payload}.${'A'.repeat(86)}`, crypto.randomUUID())),
        '401 invalid_token',
        "a token this project did not sign (Anna's claims)",
      );
      assertEquals(
        await answer(await upload(`fgp_${'x'.repeat(43)}`, crypto.randomUUID())),
        '403 session_required',
        'an API, MCP or Siri key',
      );
      assertEquals(await objectsOf(anna), 1, 'none of the refusals stored anything');

      // 10 a day.
      const day: string[] = [];
      for (let i = 0; i < 9; i++) {
        const id = crypto.randomUUID();
        assertEquals(await answer(await upload(anna.token, id)), `200 ${nameOf(anna, id)}`);
        day.push(id);
      }
      assertEquals(await answer(await upload(anna.token, crypto.randomUUID())), '403 quota');
      assertEquals(
        await answer(await upload(anna.token, kept)),
        `200 ${nameOf(anna, kept)}`,
        'a retry at the quota is the upload the app already made',
      );
      // The review's regression: signed upload URLs past the quota, minted while under it (Dora)
      // and at it (Anna).
      const past = (user: User) =>
        Array.from({ length: 12 }, () => nameOf(user, crypto.randomUUID()));
      assertEquals(
        await signedUploads(dora.token, past(dora)),
        Array(12).fill('sign 403 Unauthorized'),
        'no signed upload URL under the quota',
      );
      assertEquals(
        await signedUploads(anna.token, past(anna)),
        Array(12).fill('sign 403 Unauthorized'),
        'nor at it',
      );
      assertEquals([await objectsOf(anna), await objectsOf(dora)], [10, 0], 'nothing more stored');

      // 15 at once from one user: the lock lets exactly 10 through.
      const burst = await Promise.all(
        Array.from({ length: 15 }, () => upload(eve.token, crypto.randomUUID()).then(answer)),
      );
      assertEquals(
        burst.map((a) => a.split(' ')[0]).sort(),
        [...Array(10).fill('200'), ...Array(5).fill('403')],
        burst.join(', '),
      );
      assertEquals(await objectsOf(eve), 10, 'exactly 10 stored');

      // The sweep. kept and deleted carry notes; old and young carry none. Ben's two go with his
      // account, the one without a note too, though it is young.
      const [deleted, old, young] = day;
      assert(deleted && old && young);
      await note(anna, kept);
      await note(anna, deleted);
      const bens = crypto.randomUUID();
      assertEquals(await answer(await upload(ben.token, bens)), `200 ${nameOf(ben, bens)}`);
      await note(ben, bens);
      const bensOrphan = crypto.randomUUID();
      assertEquals(
        await answer(await upload(ben.token, bensOrphan)),
        `200 ${nameOf(ben, bensOrphan)}`,
      );
      const unstored = crypto.randomUUID();
      await note(dora, unstored);
      await sql`update storage.objects set created_at = now() - interval '25 hours'
                where bucket_id = ${BUCKET}
                  and name = any(${[kept, deleted, old].map((id) => nameOf(anna, id))})`;
      await sql`delete from public.feedback where id = any(${[deleted, unstored]}::uuid[])`;
      const [queued] = await sql<{ n: number }[]>`
        select count(*)::int as n from public.feedback_screenshot_removals
        where name = ${nameOf(dora, unstored)}`;
      assertEquals(queued?.n, 0, 'a note naming an image never stored queues nothing');
      await sql`select public.delete_account(${ben.id}::uuid)`;

      assertEquals(await sweep(), 4, "the deleted note's, the account's two and the old orphan");
      assertEquals(
        {
          kept: await stored(nameOf(anna, kept)),
          deleted: await stored(nameOf(anna, deleted)),
          old: await stored(nameOf(anna, old)),
          young: await stored(nameOf(anna, young)),
          bens: await stored(nameOf(ben, bens)),
          bensOrphan: await stored(nameOf(ben, bensOrphan)),
        },
        { kept: true, deleted: false, old: false, young: true, bens: false, bensOrphan: false },
      );
      const [queue] = await sql<{ n: number }[]>`
        select count(*)::int as n from public.feedback_screenshot_removals
        where name = any(${[nameOf(anna, deleted), nameOf(ben, bens)]})`;
      assertEquals(queue?.n, 0, 'the queue is empty again');
      assertEquals(await sweep(), 0, 'a second sweep finds nothing');

      // No way back to an object, not even one's own.
      const name = nameOf(anna, kept);
      const own = (path: string, init: RequestInit = {}) =>
        fetch(`${api()}/storage/v1/object/${path}`, {
          ...init,
          headers: { ...headers(anna.token), 'content-type': 'application/json' },
        });
      assertEquals(await outcome(await own(`${BUCKET}/${name}`)), '404 not_found', 'download');
      assertEquals(
        await outcome(await own(`authenticated/${BUCKET}/${name}`)),
        '404 not_found',
        'authenticated download',
      );
      assertEquals(
        await outcome(
          await own(`list/${BUCKET}`, {
            method: 'POST',
            body: JSON.stringify({ prefix: anna.id }),
          }),
        ),
        'ok 0',
        'list',
      );
      assertEquals(
        await outcome(
          await own(`sign/${BUCKET}/${name}`, {
            method: 'POST',
            body: JSON.stringify({ expiresIn: 60 }),
          }),
        ),
        '404 not_found',
        'signed URL',
      );
      const overwrite = await fetch(`${api()}/storage/v1/object/${BUCKET}/${name}`, {
        method: 'PUT',
        headers: { ...headers(anna.token), 'content-type': 'image/png', 'x-upsert': 'true' },
        body: PNG,
      });
      assertEquals(await outcome(overwrite), '403 Unauthorized', 'overwrite');
      assertEquals(
        await outcome(
          await own(BUCKET, { method: 'DELETE', body: JSON.stringify({ prefixes: [name] }) }),
        ),
        'ok 0',
        'remove',
      );
      assert(await stored(name), 'the image is still there');

      // The bucket-wide cap under 15 parallel uploads of three users with quota left: rows
      // standing in for other users' images fill the bucket to 240, so exactly 10 pass.
      await sql`insert into storage.objects (bucket_id, name)
                select ${BUCKET}, ${anna.id} || '/' || gen_random_uuid() || '.png'
                from generate_series(1, 240 - (select count(*) from storage.objects
                                               where bucket_id = ${BUCKET}))`;
      const crowd = await Promise.all(
        [cora, fay, gus].flatMap((user) =>
          Array.from({ length: 5 }, () => upload(user.token, crypto.randomUUID()).then(answer))
        ),
      );
      assertEquals(
        crowd.map((a) => a.split(' ')[0]).sort(),
        [...Array(10).fill('200'), ...Array(5).fill('403')],
        crowd.join(', '),
      );
      assertEquals(await objectsOf(null), 250, 'the bucket stops at 250');
      assertEquals(
        await answer(await upload(dora.token, crypto.randomUUID())),
        '403 quota',
        'a full bucket refuses a user with quota left',
      );
      assertEquals(
        await answer(await upload(anna.token, kept)),
        `200 ${name}`,
        'a retry at the bucket cap is still 200',
      );
    } finally {
      // Rows without a file go by SQL; every account goes, so the sweep removes the rest.
      await sql.begin(async (tx) => {
        await tx`set local storage.allow_delete_query = 'true'`;
        await tx`delete from storage.objects o where o.bucket_id = ${BUCKET}
                 and o.name like ${`${anna.id}/%`} and o.metadata is null`;
      });
      await sql`delete from auth.users where id = any(${users.map((u) => u.id)}::uuid[])`;
      while (await sweep() > 0) { /* at most 500 per sweep */ }
      await sql.end();
    }
  },
});
