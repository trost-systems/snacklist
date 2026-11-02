import { assert, assertEquals } from 'jsr:@std/assert@^1';
import type { Mail } from '../../supabase/functions/waitlist/mail.ts';
import { type Args, type Counts, type Deps, type InviteRow, parseArgs, run } from './invite.ts';

const BATCH = '2026-W47';
const ROWS: InviteRow[] = [
  {
    id: '00000000-0000-4000-8000-000000000001',
    email: 'hello+ios@hummlist.com',
    platform: 'ios',
    locale: 'de',
  },
  {
    id: '00000000-0000-4000-8000-000000000002',
    email: 'hello+android@hummlist.com',
    platform: 'android',
    locale: 'en',
  },
  {
    id: '00000000-0000-4000-8000-000000000003',
    email: 'someone@example.com',
    platform: 'ios',
    locale: 'en',
  },
];
const COUNTS: Counts[] = [
  { platform: 'android', locale: 'en', confirmed: 1, invited: 0, toInvite: 1 },
  { platform: 'ios', locale: 'de', confirmed: 3, invited: 2, toInvite: 1 },
  { platform: 'ios', locale: 'en', confirmed: 1, invited: 0, toInvite: 1 },
];

function setup(over: Partial<Deps> = {}, failFor: string | null = null) {
  const out: string[] = [];
  const sent: { to: string; mail: Mail; key: string }[] = [];
  const marked: string[] = [];
  const files = new Map<string, string>();
  let rowsRead = 0;
  const deps: Deps = {
    store: {
      counts: () => Promise.resolve(COUNTS),
      rows: () => {
        rowsRead++;
        return Promise.resolve(ROWS);
      },
      invited: (id) => {
        marked.push(id);
        return Promise.resolve(true);
      },
    },
    mailer: {
      send(to, mail, key) {
        if (to === failFor) return Promise.reject(new Error(`resend refused ${to}`));
        sent.push({ to, mail, key });
        return Promise.resolve();
      },
    },
    hmacSecret: 'hmac',
    allow: 'test',
    now: () => new Date('2026-11-24T09:00:00Z'),
    print: (line) => out.push(line),
    writeFile: (path, text) => {
      files.set(path, text);
      return Promise.resolve();
    },
    ...over,
  };
  return { deps, out, sent, marked, files, rowsRead: () => rowsRead };
}

const args = (argv: string[]) => {
  const a = parseArgs(argv);
  if (typeof a === 'string') throw new Error(a);
  return a;
};

const assertNoAddress = (out: string[]) => {
  for (const line of out) assert(!line.includes('@'), `no address in "${line}"`);
};

Deno.test('arguments: --confirm repeats the batch id, --export-dir only with it', () => {
  assertEquals(parseArgs(['--batch', BATCH]), {
    batch: BATCH,
    confirm: false,
    exportDir: null,
    allowPlaceholders: false,
  });
  assertEquals(
    (parseArgs(['--batch', BATCH, '--confirm', BATCH, '--export-dir', '/tmp/x']) as Args).exportDir,
    '/tmp/x',
  );
  for (
    const bad of [
      [],
      ['--batch'],
      ['--batch', '2026-47'],
      ['--confirm', BATCH],
      ['--batch', BATCH, '--confirm'],
      ['--batch', BATCH, '--confirm', '2026-W48'],
      ['--batch', BATCH, '--export-dir', '/tmp/x'],
      ['--batch', BATCH, '--send'],
      ['--batch', BATCH, 'hello+x@hummlist.com'],
    ]
  ) assertEquals(typeof parseArgs(bad), 'string', bad.join(' '));
});

Deno.test('the dry run prints counts only and reads no address', async () => {
  const { deps, out, sent, rowsRead } = setup();
  assertEquals(await run(args(['--batch', BATCH]), deps), 0);
  assertEquals(out, [
    'batch 2026-W47 (ISO week of confirmation, Europe/Berlin)',
    '  android en: confirmed 1, already invited 0, to invite 1',
    '  ios     de: confirmed 3, already invited 2, to invite 1',
    '  ios     en: confirmed 1, already invited 0, to invite 1',
    '  total     : confirmed 5, already invited 2, to invite 3',
    'dry run: nothing sent. To send: --batch 2026-W47 --confirm 2026-W47',
  ]);
  assertEquals(rowsRead(), 0);
  assertEquals(sent.length, 0);
});

Deno.test('--confirm refuses while the invite still has placeholders', async () => {
  const { deps, out, sent, rowsRead } = setup();
  assertEquals(await run(args(['--batch', BATCH, '--confirm', BATCH]), deps), 1);
  assertEquals(out.at(-1), 'invite: refused, the invite mail still has ⟦…⟧ placeholders');
  assertEquals([sent.length, rowsRead()], [0, 0]);
});

Deno.test('--allow-placeholders works only for test addresses', async () => {
  const { deps, out, sent } = setup({ allow: 'all' });
  assertEquals(
    await run(args(['--batch', BATCH, '--confirm', BATCH, '--allow-placeholders']), deps),
    1,
  );
  assertEquals(
    out.at(-1),
    'invite: --allow-placeholders works only while WAITLIST_MAIL_ALLOW is unset',
  );
  assertEquals(sent.length, 0);
});

Deno.test('--confirm without the mail secrets sends nothing', async () => {
  for (const over of [{ mailer: null }, { hmacSecret: null }]) {
    const { deps, out, rowsRead } = setup(over);
    assertEquals(
      await run(args(['--batch', BATCH, '--confirm', BATCH, '--allow-placeholders']), deps),
      1,
    );
    assertEquals(out.at(-1), 'invite: --confirm needs RESEND_API_KEY and WAITLIST_HMAC_SECRET');
    assertEquals(rowsRead(), 0);
  }
});

Deno.test('--confirm mails each allowed row once, records it and exports the lists', async () => {
  const { deps, out, sent, marked, files } = setup();
  const code = await run(
    args(['--batch', BATCH, '--confirm', BATCH, '--allow-placeholders', '--export-dir', '/out']),
    deps,
  );
  assertEquals(code, 0);
  assertEquals(sent.map((s) => [s.to, s.key]), [
    ['hello+ios@hummlist.com', `invite/${BATCH}/${ROWS[0].id}`],
    ['hello+android@hummlist.com', `invite/${BATCH}/${ROWS[1].id}`],
  ]);
  assert(
    sent[0].mail.text.includes('TestFlight') && sent[0].mail.from.includes('Peter von Hummlist'),
  );
  assert(
    sent[1].mail.text.includes('play.google.com') &&
      sent[1].mail.from.includes('Peter from Hummlist'),
  );
  assertEquals(sent[1].mail.headers['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click');
  assert(
    sent[0].mail.headers['List-Unsubscribe'].startsWith(
      `<https://hummlist.com/api/waitlist/unsubscribe?id=${ROWS[0].id}&s=`,
    ),
  );
  assertEquals(
    marked,
    [ROWS[0].id, ROWS[1].id],
    'the address outside the allow-list is not invited',
  );
  assertEquals(files.get('/out/ios.csv'), ',,hello+ios@hummlist.com\n');
  assertEquals(files.get('/out/android.csv'), 'hello+android@hummlist.com\n');
  assertEquals(out.slice(-2), [
    'sent 2, skipped 1 (not allowed by WAITLIST_MAIL_ALLOW), failed 0',
    'wrote ios.csv (1) and android.csv (1) to /out',
  ]);
  assertNoAddress(out);
});

Deno.test('a failed send is counted, not recorded, and never printed with its address', async () => {
  const { deps, out, marked } = setup({}, 'hello+android@hummlist.com');
  assertEquals(
    await run(args(['--batch', BATCH, '--confirm', BATCH, '--allow-placeholders']), deps),
    1,
  );
  assertEquals(marked, [ROWS[0].id]);
  assertEquals(out.at(-1), 'sent 1, skipped 1 (not allowed by WAITLIST_MAIL_ALLOW), failed 1');
  assertNoAddress(out);
});

Deno.test('a database error prints its code, not its detail', async () => {
  const error = Object.assign(
    new Error('Key (lower(email))=(hello+x@hummlist.com) already exists'),
    {
      code: '23505',
    },
  );
  const { deps, out } = setup({
    store: {
      counts: () => Promise.reject(error),
      rows: () => Promise.resolve([]),
      invited: () => Promise.resolve(true),
    },
  });
  assertEquals(await run(args(['--batch', BATCH]), deps), 1);
  assertEquals(out, ['invite: failed (23505)']);
});
