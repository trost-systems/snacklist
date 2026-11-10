// Job 31: the alexa function's production wiring (deps.ts) against a database with the repo's
// migrations: Alexa adds go through the Siri add path and classify like the app, two households
// stay apart, the rate limit, the link map and revocation, and the analytics subject. The token
// check is the shared auth.ts (auth_test.ts, and the e2e spec end to end); here a resolver stands
// in for it. The db gate sets FG_DB_TEST=1 and SUPABASE_DB_URL; without them this is skipped.
import { assert, assertEquals } from '@std/assert';
import postgres from 'postgres';
import { AuthError } from '../_shared/auth.ts';
import { CONSENT_TEXT_VERSION } from '../_shared/consent_version.ts';
import { asUser, serviceDb } from '../_shared/db.ts';
import { telemetryFor } from '../_shared/telemetry.ts';
import { productionDeps } from './deps.ts';
import { createHandler, type Linked } from './handler.ts';
import { analyticsSubject } from './store.ts';
import { testSkillId } from './test_ca.ts';
import type { Envelope } from './verify.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const admin = () => postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 1, prepare: false });

interface Member {
  userId: string;
  householdId: string;
  sessionId: string;
}

/** Users with fresh households (and an Alexa session each) for one test, removed afterwards. */
async function withUsers(count: number, work: (users: Member[]) => Promise<void>) {
  const sql = admin();
  const users: Member[] = [];
  try {
    const [client] = await sql<{ id: string }[]>`
      insert into auth.oauth_clients (id, registration_type, redirect_uris, grant_types, client_name,
                                      client_type, token_endpoint_auth_method)
      values (gen_random_uuid(), 'dynamic', 'https://layla.amazon.com/api/skill/link/M1',
              'authorization_code,refresh_token', 'Amazon Alexa', 'confidential',
              'client_secret_basic')
      returning id`;
    for (let i = 0; i < count; i++) {
      const userId = crypto.randomUUID();
      await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
      const householdId = await asUser(userId, async (tx) => {
        const [row] = await tx<{ id: string }[]>`select id from public.create_household('31')`;
        return row.id;
      });
      const sessionId = crypto.randomUUID();
      await sql`insert into auth.sessions (id, user_id, oauth_client_id)
                values (${sessionId}, ${userId}, ${client.id})`;
      users.push({ userId, householdId, sessionId });
    }
    await work(users);
  } finally {
    for (const { userId } of users) {
      await sql`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${userId})`;
      await sql`delete from auth.users where id = ${userId}`;
    }
    await sql`delete from auth.oauth_clients where client_name = 'Amazon Alexa'
              and redirect_uris = 'https://layla.amazon.com/api/skill/link/M1'`;
    await sql.end();
  }
}

/** The handler with the production deps; tokens are "tok-<userId>", resolved from the database. */
function handlerFor() {
  const resolve = async (token: string): Promise<Linked> => {
    const userId = token.replace(/^tok-/, '');
    const sql = serviceDb();
    const [session] = await sql<{ id: string }[]>`
      select id from auth.sessions where user_id = ${userId}::uuid and oauth_client_id is not null`;
    if (!session) throw new AuthError('invalid_token', 'revoked');
    const [member] = await sql<{ household_id: string }[]>`
      select household_id from public.household_members where user_id = ${userId}::uuid`;
    if (!member) throw new AuthError('no_household', 'none');
    return { userId, householdId: member.household_id, sessionId: session.id };
  };
  const verify = (_headers: Headers, body: Uint8Array) =>
    Promise.resolve(JSON.parse(new TextDecoder().decode(body)) as Envelope);
  return createHandler(
    productionDeps(telemetryFor('alexa', { get: () => undefined }), verify, resolve),
  );
}

async function ask(
  userId: string | null,
  request: Record<string, unknown>,
  alexaUser = `amzn1.ask.account.${userId}`,
) {
  const user = { userId: alexaUser, accessToken: userId ? `tok-${userId}` : undefined };
  const res = await handlerFor()(
    new Request('http://local/alexa', {
      method: 'POST',
      body: JSON.stringify({
        version: '1.0',
        context: { System: { application: { applicationId: testSkillId }, user } },
        request: { timestamp: new Date().toISOString(), locale: 'de-DE', ...request },
      }),
    }),
  );
  return await res.json();
}

const add = (items: string) => ({
  type: 'IntentRequest',
  intent: { name: 'AddItemIntent', slots: { items: { name: 'items', value: items } } },
});

async function open(householdId: string): Promise<[string, string | null, string][]> {
  const rows = await serviceDb()<{ name: string; quantity: string | null; category: string }[]>`
    select i.name, i.quantity, c.name as category from public.items i
    join public.categories c on c.id = i.category_id
    where i.household_id = ${householdId} and i.status = 'active' order by i.created_at, i.name`;
  return rows.map((r) => [r.name, r.quantity, r.category]);
}

Deno.test({
  name: 'Alexa adds classify like the app, stay in the household, and are read back',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withUsers(2, async ([peter, max]) => {
      const said = await ask(peter.userId, add('Milch und Eier'));
      assertEquals(
        said.response.outputSpeech.text,
        'Ich habe Milch und Eier auf die Snacklist gesetzt.',
      );
      // Typed in the app: a plain insert, classified by the same trigger.
      await asUser(max.userId, (tx) =>
        tx`insert into public.items (household_id, name) values
             (${max.householdId}, 'Milch'), (${max.householdId}, 'Eier')`);
      const typed = (await open(max.householdId)).map(([n, , c]) => [n, c]);
      const spoken = (await open(peter.householdId)).map(([n, , c]) => [n, c]);
      assertEquals(spoken.sort(), typed.sort(), 'the same categories as typed in the app');

      const more = await ask(
        peter.userId,
        add('zwei Liter Hafermilch, ein Kilo Äpfel, Weißwurst und noch Milch'),
      );
      assertEquals(
        more.response.outputSpeech.text,
        'Ich habe 2 Liter Hafermilch, 1 Kilo Äpfel und Weißwurst auf die Snacklist gesetzt. Schon auf der Snacklist: Milch.',
      );
      const items = await open(peter.householdId);
      assertEquals(items.length, 5);
      assert(items.some(([n, q]) => n === 'Hafermilch' && q === '2 l'));
      assertEquals((await open(max.householdId)).length, 2, "Max's household is untouched");

      const read = await ask(peter.userId, {
        type: 'IntentRequest',
        intent: { name: 'ReadListIntent' },
      });
      assert(
        read.response.outputSpeech.text.startsWith('Auf der Snacklist stehen 5 Sachen: '),
        read.response.outputSpeech.text,
      );

      // Max moves to Peter's household: his next add goes there, attributed to him.
      await serviceDb()`update public.household_members set household_id = ${peter.householdId}
                        where user_id = ${max.userId}`;
      await ask(max.userId, add('Brot'));
      const [brot] = await serviceDb()<{ household_id: string; added_by: string }[]>`
        select household_id, added_by from public.items where name = 'Brot'
        and household_id = ${peter.householdId}`;
      assertEquals(brot, { household_id: peter.householdId, added_by: max.userId });
    });
  },
});

Deno.test({
  name: 'rate limit, links and revocation against the database',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withUsers(1, async ([peter]) => {
      const thirty = Array.from({ length: 30 }, (_, i) => `Teil${i}`).join(', ');
      await ask(peter.userId, add(thirty));
      const limited = await ask(peter.userId, add('Milch'));
      assert(limited.response.outputSpeech.text.startsWith('Das waren gerade sehr viele'));
      assertEquals((await open(peter.householdId)).length, 30);

      const [link] = await serviceDb()<{ n: number }[]>`
        select count(*)::int as n from public.alexa_links where user_id = ${peter.userId}`;
      assertEquals(link.n, 1, 'the request remembered its session');
      const disabled = await ask(
        null,
        { type: 'AlexaSkillEvent.SkillDisabled', body: {} },
        `amzn1.ask.account.${peter.userId}`,
      );
      assertEquals(disabled, { version: '1.0', response: {} });
      const [left] = await serviceDb()<{ n: number }[]>`
        select count(*)::int as n from auth.sessions where id = ${peter.sessionId}`;
      assertEquals(left.n, 0, 'disabling the skill deleted the session');
      const after = await ask(peter.userId, add('Milch'));
      assertEquals(after.response.card, { type: 'LinkAccount' });
    });
  },
});

Deno.test({
  name: 'the analytics subject is the newest answer, and only a yes',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withUsers(1, async ([peter]) => {
      const sql = serviceDb();
      assertEquals(await analyticsSubject(sql, peter.userId), null, 'no answer: nothing');
      const phone = crypto.randomUUID();
      const laptop = crypto.randomUUID();
      const record = (
        install: string,
        consent: boolean,
        version: string | null = CONSENT_TEXT_VERSION,
      ) =>
        asUser(
          peter.userId,
          (tx) =>
            tx`select public.record_analytics_consent(${install}::uuid, ${consent}, false, true, ${version})`,
        );
      // Legal Review 2026-11-01, 12:35: a yes counts only for the current consent text.
      await record(phone, true, null);
      assertEquals(await analyticsSubject(sql, peter.userId), null, 'a yes without a version');
      await record(phone, true, '2026-10-30');
      assertEquals(await analyticsSubject(sql, peter.userId), null, 'a yes to an older text');
      await asUser(
        peter.userId,
        (tx) => tx`select public.record_analytics_consent(${phone}::uuid, true)`,
      );
      assertEquals(await analyticsSubject(sql, peter.userId), null, 'a yes from an older build');
      // Job 178 (Legal N-125): the notice names new data, so earlier texts no longer count.
      await record(phone, true, '2026-11-01');
      assertEquals(await analyticsSubject(sql, peter.userId), null, "Hummlist's text");
      await record(phone, true, '2026-11-10');
      assertEquals(await analyticsSubject(sql, peter.userId), null, 'the text before job 178');
      await record(phone, true);
      assertEquals(await analyticsSubject(sql, peter.userId), {
        installId: phone,
        internal: false,
        householdId: peter.householdId,
        role: 'owner',
        householdSize: 1,
      });
      await sql`update public.analytics_consents set decided_at = now() - interval '1 minute'
                where install_id = ${phone}`;
      await record(laptop, false);
      assertEquals(await analyticsSubject(sql, peter.userId), null, 'a newer no wins');
    });
  },
});

Deno.test({
  name: 'job 32b: Alexa adds Karotten with Möhren open, keeps both and names Möhren',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await withUsers(1, async ([peter]) => {
      await ask(peter.userId, add('500 Gramm Möhren'));
      const said = await ask(peter.userId, add('ein Kilo Karotten'));
      assertEquals(
        said.response.outputSpeech.text,
        'Ich habe 1 Kilo Karotten auf die Snacklist gesetzt. Schon auf der Snacklist: Möhren.',
      );
      assertEquals((await open(peter.householdId)).map(([n, q]) => [n, q]), [
        ['Möhren', '500 g'],
        ['Karotten', '1 kg'],
      ]);
    });
  },
});
