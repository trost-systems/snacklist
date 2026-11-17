import { assert, assertEquals, assertExists, assertMatch, assertNotEquals } from '@std/assert';
import { createHandler, type Store } from '../../supabase/functions/waitlist/handler.ts';
import { unsubscribeSig } from '../../supabase/functions/waitlist/crypto.ts';
import type { Locale, Platform } from '../../supabase/functions/waitlist/mail.ts';
import { type Mail, MailError } from '../../supabase/functions/_shared/resend.ts';
import { handle } from '../../site/api/_waitlist.mjs';
import {
  type Deps,
  type IosCounts,
  type IosInviteStore,
  type IosRow,
  run,
  type Settings,
  settingsFrom,
} from './ios-invite.ts';

const HMAC = 'hmac-secret-for-tests';
const PROXY = 'proxy-secret-for-tests';
const T0 = new Date('2026-11-24T09:00:00Z');

interface Row {
  id: string;
  email: string;
  platform: Platform;
  locale: Locale;
  confirmed: boolean;
  invitedAt: Date | null;
}

const row = (n: number, email: string, over: Partial<Row> = {}): Row => ({
  id: `00000000-0000-4000-8000-00000000000${n}`,
  email,
  platform: 'ios',
  locale: 'de',
  confirmed: true,
  invitedAt: null,
  ...over,
});

/** The migration's rules over a list: recipients, claim, release, and unsubscribe's delete. */
class FakeWaitlist implements IosInviteStore {
  claims = 0;
  constructor(public rows_: Row[]) {}

  private recipients() {
    return this.rows_.filter((r) => r.platform === 'ios' && r.confirmed && !r.invitedAt);
  }

  counts(): Promise<IosCounts[]> {
    return Promise.resolve((['de', 'en'] as const).map((locale) => {
      const all = this.rows_.filter((r) =>
        r.platform === 'ios' && r.confirmed && r.locale === locale
      );
      const invited = all.filter((r) => r.invitedAt).length;
      return { locale, confirmed: all.length, invited, toInvite: all.length - invited };
    }));
  }

  rows(limit: number | null): Promise<IosRow[]> {
    return Promise.resolve(
      this.recipients().slice(0, limit ?? undefined).map(({ id, email, locale }) => ({
        id,
        email,
        locale,
      })),
    );
  }

  claim(id: string, now: Date) {
    this.claims++;
    const r = this.recipients().find((r) => r.id === id);
    if (r) r.invitedAt = now;
    return Promise.resolve(!!r);
  }

  release(id: string, claimedAt: Date) {
    const r = this.rows_.find((r) => r.id === id && r.invitedAt?.getTime() === claimedAt.getTime());
    if (r) r.invitedAt = null;
    return Promise.resolve(!!r);
  }

  mailed(id: string) {
    return Promise.resolve(this.rows_.some((r) => r.id === id));
  }

  unsubscribe(id: string) {
    const before = this.rows_.length;
    this.rows_ = this.rows_.filter((r) => r.id !== id);
    return Promise.resolve(this.rows_.length < before);
  }
}

const sample = () => [
  row(1, 'test+de@snacklist.app'),
  row(2, 'test+en@snacklist.app', { locale: 'en' }),
  row(3, 'test+android@snacklist.app', { platform: 'android' }),
  row(4, 'test+unconfirmed@snacklist.app', { confirmed: false }),
  row(5, 'test+invited@snacklist.app', { invitedAt: new Date('2026-11-10T09:00:00Z') }),
  row(6, 'someone@example.com', { locale: 'en' }),
];

type SendResult = 'ok' | 'refused' | 'no-answer' | 408 | 409 | 500 | 502 | 504;

function setup(
  rows = sample(),
  over: Partial<Deps> = {},
  answer: (to: string) => SendResult = () => 'ok',
) {
  const store = new FakeWaitlist(rows);
  const out: string[] = [];
  const sent: { to: string; mail: Mail; key: string }[] = [];
  const files = new Map<string, string>();
  const deps: Deps = {
    store,
    mailer: {
      send(to, mail, key) {
        const a = answer(to);
        if (a === 'refused') return Promise.reject(new MailError(422));
        if (a === 'no-answer') return Promise.reject(new TypeError('connection reset'));
        if (typeof a === 'number') return Promise.reject(new MailError(a));
        sent.push({ to, mail, key });
        return Promise.resolve();
      },
    },
    hmacSecret: HMAC,
    allow: 'test',
    now: () => T0,
    print: (line) => out.push(line),
    writeFile: (path, text) => {
      files.set(path, text);
      return Promise.resolve();
    },
    makeTempDir: () => Promise.resolve('/tmp/preview'),
    ...over,
  };
  return { store, deps, out, sent, files };
}

const settings = (env: Record<string, string> = {}, argv: string[] = []): Settings => {
  const s = settingsFrom((k) => env[k], argv);
  if (typeof s === 'string') throw new Error(s);
  return s;
};

/** The dry run's token for [batchSize] over the same rows. */
async function tokenFor(rows: Row[], batchSize: number): Promise<string> {
  const { deps, out } = setup(rows);
  assertEquals(await run(settings({ BATCH_SIZE: String(batchSize) }), deps), 0);
  const token = out.at(-1)?.match(/INVITE_CONFIRM=([0-9a-f]{16})$/)?.[1];
  assertExists(token, out.join('\n'));
  return token;
}

const sendEnv = (batch: number, token: string, extra: Record<string, string> = {}) => ({
  INVITE_SEND: '1',
  BATCH_SIZE: String(batch),
  INVITE_CONFIRM: token,
  ...extra,
});

const assertNoAddress = (lines: Iterable<string>) => {
  for (const line of lines) assert(!/[^\s<]@[a-z]/i.test(line), `no address in "${line}"`);
};

Deno.test('settings: the dry run is the default; a send needs INVITE_SEND=1 exactly', () => {
  assertEquals(settingsFrom(() => undefined, []), {
    send: false,
    batchSize: null,
    confirm: null,
    allowPlaceholders: false,
    previewDir: null,
    exportDir: null,
  });
  assertEquals(settings({ INVITE_SEND: '0', BATCH_SIZE: '25' }).send, false);
  assertEquals(settings({ INVITE_SEND: '1', BATCH_SIZE: '25' }).batchSize, 25);
  for (
    const [env, argv] of [
      [{ INVITE_SEND: 'yes' }, []],
      [{ INVITE_SEND: 'true' }, []],
      [{ BATCH_SIZE: '0' }, []],
      [{ BATCH_SIZE: '-5' }, []],
      [{ BATCH_SIZE: '10x' }, []],
      [{}, ['--export-dir', '/out']],
      [{}, ['--preview-dir']],
      [{}, ['test+x@snacklist.app']],
    ] as const
  ) assertEquals(typeof settingsFrom((k) => env[k as keyof typeof env], [...argv]), 'string');
});

Deno.test('the dry run renders every mail, writes redacted previews, and sends and marks nothing', async () => {
  const { store, deps, out, sent, files } = setup();
  assertEquals(await run(settings({ BATCH_SIZE: '10' }), deps), 0);
  assertEquals(sent.length, 0, 'nothing sent');
  assertEquals(store.claims, 0, 'nothing marked');
  assertEquals(out.slice(0, 4), [
    'iOS invite: confirmed iPhone sign-ups without an invite, in their sign-up language',
    '  de: confirmed 2, already invited 1, to invite 1',
    '  en: confirmed 2, already invited 0, to invite 2',
    'batch: 3 (de 1, en 2), BATCH_SIZE 10; not allowed by WAITLIST_MAIL_ALLOW: 1',
  ]);
  assertMatch(
    out.at(-1) ?? '',
    /^dry run: nothing sent\. To send this batch: INVITE_SEND=1 BATCH_SIZE=10 INVITE_CONFIRM=[0-9a-f]{16}$/,
  );
  assertEquals([...files.keys()].sort(), [
    '/tmp/preview/ios-invite-de.html',
    '/tmp/preview/ios-invite-de.txt',
    '/tmp/preview/ios-invite-en.html',
    '/tmp/preview/ios-invite-en.txt',
  ]);
  const de = files.get('/tmp/preview/ios-invite-de.txt') ?? '';
  assertEquals(de.split('\n').slice(0, 8), [
    'From: "Peter von Snacklist" <hello@snacklist.app>',
    'Reply-To: hello@snacklist.app',
    'To: <recipient>',
    'Subject: Deine Einladung zur Snacklist-Beta',
    'List-Unsubscribe: <https://snacklist.app/api/waitlist/unsubscribe?id={id}&s={sig}&l=de>',
    'List-Unsubscribe-Post: List-Unsubscribe=One-Click',
    'X-Preview-Recipients: 1',
    '',
  ]);
  assert(
    de.includes(
      'Keine E-Mails mehr von uns? Abmelden <https://snacklist.app/de/warteliste/abmelden#id={id}&s={sig}> – ein Klick genügt',
    ),
  );
  assert(
    files.get('/tmp/preview/ios-invite-en.txt')?.includes(
      'Subject: Your invite to the Snacklist beta',
    ),
  );
  for (const text of files.values()) {
    assert(!/[0-9a-f]{64}/.test(text), 'no signature in a preview');
    assert(!text.includes('00000000-0000-4000'), 'no row id in a preview');
  }
  assertNoAddress([
    ...out,
    ...[...files.values()].map((t) =>
      t.replaceAll('hello@snacklist.app', '').replaceAll('support@snacklist.app', '')
    ),
  ]);
});

Deno.test('the dry run without BATCH_SIZE previews all recipients and prints no token', async () => {
  const { deps, out, sent } = setup();
  assertEquals(await run(settings(), deps), 0);
  assertEquals(sent.length, 0);
  assert(
    out.includes(
      'batch: 3 (de 1, en 2), all (no BATCH_SIZE); not allowed by WAITLIST_MAIL_ALLOW: 1',
    ),
  );
  assertEquals(
    out.at(-1),
    'dry run: nothing sent. To send, run the dry run again with BATCH_SIZE=<n> for its token',
  );
});

Deno.test('recipients: only confirmed iPhone rows without an invite, each in their sign-up language', async () => {
  const rows = sample();
  const token = await tokenFor(rows, 10);
  const { deps, sent, out, files } = setup(rows);
  assertEquals(await run(settings(sendEnv(10, token)), deps), 0, out.join('\n'));
  assertEquals(files.size, 0, 'a send writes no previews unless asked');
  assertEquals(sent.map((s) => [s.to, s.mail.subject, s.key]), [
    ['test+de@snacklist.app', 'Deine Einladung zur Snacklist-Beta', `ios-invite/${rows[0]?.id}`],
    ['test+en@snacklist.app', 'Your invite to the Snacklist beta', `ios-invite/${rows[1]?.id}`],
  ]);
  assert(out.includes(
    'sent 2, skipped 1 (not allowed by WAITLIST_MAIL_ALLOW), already invited by another run 0, ' +
      'refused by Resend 0 (left uninvited for a later run)',
  ));
  assertNoAddress(out);
});

Deno.test('every mail has the sender, a signed unsubscribe link and RFC 8058 headers', async () => {
  const rows = sample();
  const { deps, sent } = setup(rows);
  await run(settings(sendEnv(10, await tokenFor(rows, 10))), deps);
  assertEquals(sent.length, 2);
  for (const { mail, key } of sent) {
    const id = key.replace('ios-invite/', '');
    const sig = await unsubscribeSig(HMAC, id);
    const l = mail.subject.startsWith('Deine') ? 'de' : 'en';
    assertEquals(
      mail.from,
      l === 'de'
        ? '"Peter von Snacklist" <hello@snacklist.app>'
        : '"Peter from Snacklist" <hello@snacklist.app>',
    );
    assertEquals(mail.replyTo, 'hello@snacklist.app');
    assertEquals(mail.headers, {
      'List-Unsubscribe':
        `<https://snacklist.app/api/waitlist/unsubscribe?id=${id}&s=${sig}&l=${l}>`,
      'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
    });
    const page = l === 'de'
      ? `https://snacklist.app/de/warteliste/abmelden#id=${id}&s=${sig}`
      : `https://snacklist.app/en/waitlist/unsubscribe#id=${id}&s=${sig}`;
    assert(mail.text.includes(`<${page}>`), 'the [UNSUBSCRIBE_URL] slot holds the page link');
  }
});

Deno.test("a real send needs BATCH_SIZE, the dry run's token and the Resend key", async () => {
  const rows = sample();
  const token = await tokenFor(rows, 10);
  const cases: [Record<string, string>, Partial<Deps>, string][] = [
    [
      { INVITE_SEND: '1', INVITE_CONFIRM: token },
      {},
      'ios-invite: INVITE_SEND=1 needs BATCH_SIZE',
    ],
    [
      { INVITE_SEND: '1', BATCH_SIZE: '10' },
      {},
      'ios-invite: INVITE_SEND=1 needs INVITE_CONFIRM, the token of the dry run',
    ],
    [sendEnv(10, token), { mailer: null }, 'ios-invite: INVITE_SEND=1 needs RESEND_API_KEY'],
    [
      sendEnv(10, token, { INVITE_ALLOW_PLACEHOLDERS: '1' }),
      { allow: 'all' },
      'ios-invite: INVITE_ALLOW_PLACEHOLDERS works only while WAITLIST_MAIL_ALLOW is unset',
    ],
    [
      sendEnv(10, '0123456789abcdef'),
      {},
      "ios-invite: refused, INVITE_CONFIRM is not this batch's token (the recipients or the mail changed since that dry run); run the dry run again",
    ],
    [
      sendEnv(5, token),
      {},
      "ios-invite: refused, INVITE_CONFIRM is not this batch's token (the recipients or the mail changed since that dry run); run the dry run again",
    ],
  ];
  for (const [env, over, message] of cases) {
    const { store, deps, out, sent } = setup(sample(), over);
    assertEquals(await run(settings(env), deps), 1, message);
    assertEquals(out.at(-1), message);
    assertEquals(sent.length, 0, message);
    assertEquals(store.claims, 0, message);
  }
  const { deps } = setup(sample(), { hmacSecret: null });
  assertEquals(await run(settings(), deps), 1, 'even the dry run signs real links');
});

Deno.test('the token changes when a recipient joins or leaves the batch', async () => {
  const rows = sample();
  const before = await tokenFor(rows, 10);
  assertNotEquals(await tokenFor([...rows, row(7, 'test+new@snacklist.app')], 10), before);
  assertNotEquals(await tokenFor(rows.slice(1), 10), before);
  assertEquals(await tokenFor(sample(), 10), before);
});

Deno.test('BATCH_SIZE caps the send at the earliest recipients', async () => {
  const rows = sample();
  const { deps, sent } = setup(rows);
  assertEquals(await run(settings(sendEnv(1, await tokenFor(rows, 1))), deps), 0);
  assertEquals(sent.map((s) => s.to), ['test+de@snacklist.app']);
});

Deno.test('idempotent: a rerun with the same token sends nothing, a fresh dry run finds no one', async () => {
  const rows = sample();
  const token = await tokenFor(rows, 10);
  const first = setup(rows);
  assertEquals(await run(settings(sendEnv(10, token)), first.deps), 0);
  assertEquals(first.sent.length, 2);

  const again = setup(first.store.rows_);
  assertEquals(await run(settings(sendEnv(10, token)), again.deps), 1);
  assertEquals(again.sent.length, 0, 'the rerun is refused: the batch changed');

  const fresh = setup(first.store.rows_);
  assertEquals(
    await run(settings(sendEnv(10, await tokenFor(first.store.rows_, 10))), fresh.deps),
    0,
  );
  assertEquals(
    fresh.sent.length,
    0,
    'only the address outside the allow-list is left, and it is skipped',
  );
});

Deno.test('idempotent: a row another run marked between the read and the send is not mailed', async () => {
  const rows = sample();
  const token = await tokenFor(rows, 10);
  const { store, deps, sent, out } = setup(rows);
  const claim = store.claim.bind(store);
  store.claim = (id, now) => {
    if (id === rows[0]?.id) {
      const r = store.rows_.find((r) => r.id === id);
      if (r) r.invitedAt = new Date('2026-11-24T08:59:00Z');
    }
    return claim(id, now);
  };
  assertEquals(await run(settings(sendEnv(10, token)), deps), 0);
  assertEquals(sent.map((s) => s.to), ['test+en@snacklist.app']);
  assert(out.some((l) => l.includes('already invited by another run 1')));
});

Deno.test('a mail Resend refused (4xx) is unmarked for a later run; no answer or a 5xx keeps it marked and stops the run', async () => {
  const rows = sample();
  const token = await tokenFor(rows, 10);
  const refused = setup(rows, {}, (to) => to === 'test+de@snacklist.app' ? 'refused' : 'ok');
  assertEquals(await run(settings(sendEnv(10, token)), refused.deps), 1);
  assertEquals(refused.sent.map((s) => s.to), ['test+en@snacklist.app']);
  assertEquals((await refused.store.rows(null)).map((r) => r.email), [
    'test+de@snacklist.app',
    'someone@example.com',
  ]);

  for (const unclear of ['no-answer', 408, 409, 500, 502, 504] as const) {
    const lost = setup(sample(), {}, (to) => to === 'test+de@snacklist.app' ? unclear : 'ok');
    assertEquals(await run(settings(sendEnv(10, token)), lost.deps), 1, String(unclear));
    assertEquals(lost.sent.length, 0, `${unclear}: the run stops at the first unclear answer`);
    assertEquals((await lost.store.rows(null)).map((r) => r.email), [
      'test+en@snacklist.app',
      'someone@example.com',
    ], `${unclear}: the row stays marked, so a rerun never mails it twice`);
    assertEquals(
      lost.out.at(-1),
      'ios-invite: stopped, one send got no clear answer from Resend (none, or 408, 409 or 5xx); ' +
        'its row stays marked invited (Resend log, idempotency key ios-invite/<id>)',
    );
    assertNoAddress(lost.out);
  }
  assertNoAddress(refused.out);
});

Deno.test("--export-dir writes TestFlight's CSV of the rows invited now", async () => {
  const rows = sample();
  const { deps, files, out } = setup(rows);
  assertEquals(
    await run(settings(sendEnv(10, await tokenFor(rows, 10)), ['--export-dir', '/out']), deps),
    0,
  );
  assertEquals(files.get('/out/ios.csv'), ',,test+de@snacklist.app\n,,test+en@snacklist.app\n');
  assertEquals(out.at(-1), 'wrote ios.csv (2) to /out');
});

Deno.test('a database error prints its code, not its detail', async () => {
  const error = Object.assign(new Error('Key (lower(email))=(test+x@snacklist.app)'), {
    code: '23505',
  });
  const { deps, out } = setup();
  deps.store.counts = () => Promise.reject(error);
  assertEquals(await run(settings(), deps), 1);
  assertEquals(out, ['ios-invite: failed (23505)']);
});

/** The site's /api/waitlist/unsubscribe in front of the waitlist edge function over [store]. */
function unsubscribeEndpoint(store: FakeWaitlist) {
  const unused = () => Promise.reject(new Error('not in this test'));
  const backend: Store = {
    rateHit: unused,
    signup: unused,
    confirm: unused,
    mailed: unused,
    unsubscribe: (id) => store.unsubscribe(id),
  };
  const edge = createHandler({
    config: { proxySecret: PROXY, hmacSecret: HMAC, allow: 'test', allowPlaceholders: false },
    store: backend,
    mailer: null,
    now: () => T0,
    random: (n) => new Uint8Array(n),
    defer: (work) => work(),
  });
  return (request: Request) =>
    handle('unsubscribe', request, {
      env: {
        WAITLIST_UPSTREAM_URL: 'https://edge.test/functions/v1/waitlist',
        WAITLIST_PROXY_SECRET: PROXY,
      },
      fetch: (url: string, init: RequestInit) => edge(new Request(url, init)),
      now: T0,
    });
}

const sentMail = async () => {
  const rows = sample();
  const { store, deps, sent } = setup(rows);
  await run(settings(sendEnv(1, await tokenFor(rows, 1))), deps);
  const [first] = sent;
  assertExists(first);
  const oneClick = first.mail.headers?.['List-Unsubscribe']?.slice(1, -1) ?? '';
  return { store, mail: first.mail, oneClick: new URL(oneClick), id: rows[0]?.id };
};

Deno.test('one-click: a POST to the List-Unsubscribe URL deletes the entry at once (RFC 8058)', async () => {
  const { store, oneClick, id } = await sentMail();
  const endpoint = unsubscribeEndpoint(store);
  const res = await endpoint(
    new Request(oneClick, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded', host: oneClick.host },
      body: 'List-Unsubscribe=One-Click',
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: 'deleted' });
  assert(!store.rows_.some((r) => r.id === id), 'the row is gone, no confirmation page');
});

Deno.test("signed link roundtrip: the page link's id and signature unsubscribe; a forged one does not", async () => {
  const { store, mail, oneClick, id } = await sentMail();
  const page = mail.text.match(/<(https:\/\/snacklist\.app\/de\/warteliste\/abmelden#[^>]+)>/)?.[1];
  assertExists(page);
  const fragment = new URLSearchParams(new URL(page).hash.slice(1));
  assertEquals(fragment.get('id'), id);
  const endpoint = unsubscribeEndpoint(store);
  const press = (body: unknown) =>
    endpoint(
      new Request('https://snacklist.app/api/waitlist/unsubscribe', {
        method: 'POST',
        headers: { 'content-type': 'application/json', host: 'snacklist.app' },
        body: JSON.stringify(body),
      }),
    );

  const get = await endpoint(new Request(oneClick, { headers: { host: oneClick.host } }));
  assertEquals(get.status, 303, 'GET on the header URL opens the page and deletes nothing');
  assertEquals(
    get.headers.get('location'),
    `/de/warteliste/abmelden#id=${id}&s=${fragment.get('s')}`,
  );
  assert(store.rows_.some((r) => r.id === id));

  const forged = await press({ id, sig: '0'.repeat(64) });
  assertEquals(await forged.json(), { status: 'invalid' });
  assert(store.rows_.some((r) => r.id === id), 'a forged signature deletes nothing');

  const res = await press({ id: fragment.get('id'), sig: fragment.get('s') });
  assertEquals(await res.json(), { status: 'deleted' });
  assert(!store.rows_.some((r) => r.id === id));
});
