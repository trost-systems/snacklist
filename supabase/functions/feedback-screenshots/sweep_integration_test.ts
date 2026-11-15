// Job 267: feedback screenshots against the local stack's real Storage API and database. A
// signed-in user uploads <own id>/<uuid>.png once (again: a duplicate); not into another folder or
// bucket, no other type, nothing over 2 MiB, nothing signed out, at most 10 a day and none while
// the bucket holds 250 images (a retry of an uploaded name still answers duplicate); and cannot
// download, list, sign, overwrite or remove any object, their own included. The sweep, through
// the production store and remover, removes a deleted note's image, an account's images (with a
// note or without, however young) right after the account deletion and an orphan older than a
// day, and keeps a young orphan and a note's image: the service key's download then answers not
// found. Throwaway accounts, removed after. The db
// gate sets FG_DB_TEST=1, SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_DB_URL and
// SUPABASE_SERVICE_ROLE_KEY; without them this is skipped.
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

/** The Storage API's error as `<statusCode> <error>` (it answers HTTP 400 with them in the body). */
async function outcome(res: Response): Promise<string> {
  const body = await res.json().catch(() => null) as
    | { statusCode?: string; error?: string }
    | unknown[]
    | null;
  if (res.ok) return Array.isArray(body) ? `ok ${body.length}` : 'ok';
  return `${(body as { statusCode?: string })?.statusCode} ${(body as { error?: string })?.error}`;
}

function upload(
  token: string,
  name: string,
  init: { bucket?: string; type?: string; body?: Uint8Array<ArrayBuffer> } = {},
): Promise<Response> {
  return fetch(`${api()}/storage/v1/object/${init.bucket ?? BUCKET}/${name}`, {
    method: 'POST',
    headers: { ...headers(token), 'content-type': init.type ?? 'image/png' },
    body: init.body ?? PNG,
  });
}

/** Whether the service key still finds the object. */
async function stored(name: string): Promise<boolean> {
  const res = await fetch(`${api()}/storage/v1/object/${BUCKET}/${name}`, { headers: service() });
  await res.body?.cancel();
  return res.ok;
}

const shot = (user: User) => `${user.id}/${crypto.randomUUID()}.png`;
const idOf = (name: string) => name.slice(name.indexOf('/') + 1, -'.png'.length);

Deno.test({
  name: 'feedback screenshots over the real Storage API: upload rules, no reads, the sweep',
  ignore: !enabled,
  async fn() {
    const sql = postgres(databaseUrl(), { max: 2, prepare: false });
    const sweep = () =>
      sweepFeedbackScreenshots(
        sqlSweepStore(() => sql),
        storageRemover(api(), env('SUPABASE_SERVICE_ROLE_KEY')),
      );
    const anna = await signUp();
    const ben = await signUp();
    const cora = await signUp();
    const other = `other-${crypto.randomUUID()}`;
    try {
      const note = async (user: User, name: string) => {
        const res = await fetch(`${api()}/rest/v1/feedback`, {
          method: 'POST',
          headers: {
            ...headers(user.token),
            'content-type': 'application/json',
            prefer: 'return=minimal',
          },
          body: JSON.stringify({
            id: idOf(name),
            message: 'Siehe Bild',
            app_version: '1.0.0',
            build: '1',
            platform: 'ios',
            os_version: 'iOS 18.1',
            locale: 'de',
            screenshot: name,
          }),
        });
        assertEquals(res.status, 201, await res.text());
      };

      // Uploads.
      const kept = shot(anna);
      assertEquals(await outcome(await upload(anna.token, kept)), 'ok', 'own folder');
      assertEquals(
        await outcome(await upload(anna.token, kept)),
        '409 Duplicate',
        'same name again',
      );
      assertEquals(
        await outcome(await upload(anna.token, shot(ben))),
        '403 Unauthorized',
        "another user's folder",
      );
      assertEquals(
        await outcome(await upload(anna.token, shot(anna), { type: 'image/jpeg' })),
        '415 invalid_mime_type',
        'not a PNG',
      );
      assertEquals(
        await outcome(
          await upload(anna.token, shot(anna), { body: new Uint8Array(2 * 1024 * 1024 + 1) }),
        ),
        '413 Payload too large',
        'over 2 MiB',
      );
      assertEquals(
        await outcome(await upload(env('SUPABASE_ANON_KEY'), shot(anna))),
        '403 Unauthorized',
        'signed out',
      );
      const bucket = await fetch(`${api()}/storage/v1/bucket`, {
        method: 'POST',
        headers: { ...service(), 'content-type': 'application/json' },
        body: JSON.stringify({ id: other, name: other, public: false }),
      });
      assertEquals(bucket.status, 200, await bucket.text());
      assertEquals(
        await outcome(await upload(anna.token, shot(anna), { bucket: other })),
        '403 Unauthorized',
        'another bucket',
      );

      // No way back to an object, not even one's own.
      const own = (path: string, init: RequestInit = {}) =>
        fetch(`${api()}/storage/v1/object/${path}`, {
          ...init,
          headers: { ...headers(anna.token), 'content-type': 'application/json' },
        });
      assertEquals(await outcome(await own(`${BUCKET}/${kept}`)), '404 not_found', 'download');
      assertEquals(
        await outcome(await own(`authenticated/${BUCKET}/${kept}`)),
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
          await own(`sign/${BUCKET}/${kept}`, {
            method: 'POST',
            body: JSON.stringify({ expiresIn: 60 }),
          }),
        ),
        '404 not_found',
        'signed URL',
      );
      const overwrite = await fetch(`${api()}/storage/v1/object/${BUCKET}/${kept}`, {
        method: 'PUT',
        headers: { ...headers(anna.token), 'content-type': 'image/png' },
        body: PNG,
      });
      assertEquals(await outcome(overwrite), '403 Unauthorized', 'overwrite');
      const upsert = await fetch(`${api()}/storage/v1/object/${BUCKET}/${kept}`, {
        method: 'POST',
        headers: { ...headers(anna.token), 'content-type': 'image/png', 'x-upsert': 'true' },
        body: PNG,
      });
      assertEquals(await outcome(upsert), '403 Unauthorized', 'upsert');
      assertEquals(
        await outcome(
          await own(BUCKET, { method: 'DELETE', body: JSON.stringify({ prefixes: [kept] }) }),
        ),
        'ok 0',
        'remove',
      );
      assert(await stored(kept), 'the image is still there');

      // 10 a day.
      const day: string[] = [];
      for (let i = 0; i < 9; i++) {
        const name = shot(anna);
        assertEquals(await outcome(await upload(anna.token, name)), 'ok', `upload ${i + 2}`);
        day.push(name);
      }
      assertEquals(
        await outcome(await upload(anna.token, shot(anna))),
        '403 Unauthorized',
        'the 11th upload of the day',
      );
      assertEquals(
        await outcome(await upload(anna.token, kept)),
        '409 Duplicate',
        'a retry at the quota is the duplicate the app counts as uploaded',
      );

      // The sweep. kept and deleted carry notes; old and young carry none. Ben's two go with his
      // account, the one without a note too, though it is young.
      const [deleted, old, young, ...unused] = day;
      assert(deleted && old && young);
      await note(anna, kept);
      await note(anna, deleted);
      const bens = shot(ben);
      assertEquals(await outcome(await upload(ben.token, bens)), 'ok');
      await note(ben, bens);
      const bensOrphan = shot(ben);
      assertEquals(await outcome(await upload(ben.token, bensOrphan)), 'ok');
      await sql`update storage.objects set created_at = now() - interval '25 hours'
                where bucket_id = ${BUCKET} and name = any(${[kept, deleted, old]})`;
      await sql`delete from public.feedback where id = ${idOf(deleted)}`;
      await sql`select public.delete_account(${ben.id}::uuid)`;

      assertEquals(await sweep(), 4, "the deleted note's, the account's two and the old orphan");
      assertEquals(
        {
          kept: await stored(kept),
          deleted: await stored(deleted),
          old: await stored(old),
          young: await stored(young),
          bens: await stored(bens),
          bensOrphan: await stored(bensOrphan),
        },
        { kept: true, deleted: false, old: false, young: true, bens: false, bensOrphan: false },
      );
      const [queue] = await sql<{ n: number }[]>`
        select count(*)::int as n from public.feedback_screenshot_removals
        where name = any(${[deleted, bens]})`;
      assertEquals(queue?.n, 0, 'the queue is empty again');
      assertEquals(await sweep(), 0, 'a second sweep finds nothing');
      assertEquals(unused.length, 6);

      // The bucket-wide cap: rows standing in for other users' images fill it to 250.
      await sql`insert into storage.objects (bucket_id, name)
                select ${BUCKET}, ${anna.id} || '/' || gen_random_uuid() || '.png'
                from generate_series(1, 250 - (select count(*) from storage.objects
                                               where bucket_id = ${BUCKET}))`;
      assertEquals(
        await outcome(await upload(cora.token, shot(cora))),
        '403 Unauthorized',
        'a full bucket refuses a user with quota left',
      );
      assertEquals(
        await outcome(await upload(anna.token, kept)),
        '409 Duplicate',
        'a retry at the bucket cap is still the duplicate',
      );
    } finally {
      // Everything Anna uploaded becomes due: her notes are deleted with her, the rest is aged.
      await sql.begin(async (tx) => {
        await tx`set local storage.allow_delete_query = 'true'`;
        await tx`delete from storage.objects o where o.bucket_id = ${BUCKET}
                 and o.name like ${`${anna.id}/%`} and o.metadata is null`;
      });
      await sql`delete from auth.users where id = any(${[anna.id, ben.id, cora.id]}::uuid[])`;
      await sql`update storage.objects set created_at = now() - interval '25 hours'
                where bucket_id = ${BUCKET} and name like ${`${anna.id}/%`}`;
      await sweep();
      const gone = await fetch(`${api()}/storage/v1/bucket/${other}`, {
        method: 'DELETE',
        headers: service(),
      });
      await gone.body?.cancel();
      await sql.end();
    }
  },
});
