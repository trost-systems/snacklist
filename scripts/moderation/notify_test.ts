import { assert, assertEquals } from '@std/assert';
import type { Mail } from '../../supabase/functions/_shared/resend.ts';
import {
  type DecisionRow,
  type Deps,
  maskEmail,
  parseArgs,
  type PendingRow,
  run,
} from './notify.ts';

const EMAIL = 'anna.beispiel@example.org';
const ROW: DecisionRow = {
  id: 12,
  ref: 'M-7KQ2-XW9D',
  locale: 'de',
  name: 'Anna',
  email: EMAIL,
  reportedAt: new Date('2026-11-16T13:05:00Z'),
  outcome: 'removed',
  ground: 'Der Eintrag beleidigt dich nach § 185 StGB.',
  notifiedAt: null,
};

function setup(
  row: DecisionRow | null = ROW,
  over: Partial<Deps> = {},
  pending: PendingRow[] = [],
) {
  const out: string[] = [];
  const sent: { to: string; mail: Mail; key: string }[] = [];
  const marked: number[] = [];
  const confirmed: string[] = [];
  const asked: Date[] = [];
  const deps: Deps = {
    store: {
      decision: () => Promise.resolve(row),
      notified: (id) => {
        marked.push(id);
        return Promise.resolve(true);
      },
      unconfirmed: (before) => {
        asked.push(before);
        return Promise.resolve(pending);
      },
      confirmationSent: (id) => {
        confirmed.push(id);
        return Promise.resolve(true);
      },
    },
    mailer: {
      send(to, mail, key) {
        sent.push({ to, mail, key });
        return Promise.resolve();
      },
    },
    now: () => new Date('2026-11-17T08:00:00Z'),
    print: (line) => out.push(line),
    ...over,
  };
  return { deps, out, sent, marked, confirmed, asked };
}

const noAddress = (out: string[]) =>
  assert(!out.join('\n').includes(EMAIL), 'the address is never printed in full');

Deno.test('parseArgs', () => {
  assertEquals(parseArgs(['--decision', '12']), {
    kind: 'decision',
    decision: 12,
    send: false,
    again: false,
  });
  assertEquals(parseArgs(['--confirmations']), { kind: 'confirmations', send: false });
  assertEquals(parseArgs(['--confirmations', '--send']), { kind: 'confirmations', send: true });
  assertEquals(typeof parseArgs(['--confirmations', '--decision', '12']), 'string');
  assertEquals(typeof parseArgs(['--confirmations', '--send', '--again']), 'string');
  assertEquals(parseArgs(['--decision', '12', '--send', '--again']), {
    kind: 'decision',
    decision: 12,
    send: true,
    again: true,
  });
  assertEquals(typeof parseArgs([]), 'string');
  assertEquals(typeof parseArgs(['--decision', '0']), 'string');
  assertEquals(typeof parseArgs(['--decision', 'M-7KQ2-XW9D']), 'string');
  assertEquals(typeof parseArgs(['--decision', '12', '--again']), 'string');
  assertEquals(typeof parseArgs(['--decision', '12', '--confirm']), 'string');
});

Deno.test('maskEmail keeps the first letters and the top-level domain', () => {
  assertEquals(maskEmail(EMAIL), 'a***@e***.org');
  assertEquals(maskEmail('x@localhost'), 'x***@l***');
});

Deno.test('the dry run prints the B.6a mail with the address masked and sends nothing', async () => {
  const { deps, out, sent, marked } = setup();
  assertEquals(await run({ kind: 'decision', decision: 12, send: false, again: false }, deps), 0);
  assertEquals(out.slice(0, 3), [
    'To: a***@e***.org',
    'Subject: Unsere Entscheidung zu deiner Meldung (M-7KQ2-XW9D)',
    'Idempotency-Key: report-decision/12',
  ]);
  const text = out.join('\n');
  assert(
    text.includes('Hallo Anna, wir haben deine Meldung vom 16.11.2026 (M-7KQ2-XW9D) geprüft.'),
  );
  assert(
    text.includes('Entscheidung: wir haben den Inhalt entfernt. Grund: Der Eintrag beleidigt dich'),
  );
  assert(text.endsWith('dry run: nothing sent. To send: --decision 12 --send'));
  assertEquals([sent.length, marked.length], [0, 0]);
  noAddress(out);
});

Deno.test('--send mails it with the decision key and records the notice', async () => {
  const { deps, out, sent, marked } = setup();
  assertEquals(await run({ kind: 'decision', decision: 12, send: true, again: false }, deps), 0);
  assertEquals(sent.length, 1);
  assertEquals(sent[0]?.to, EMAIL);
  assertEquals(sent[0]?.key, 'report-decision/12');
  assertEquals(sent[0]?.mail.replyTo, 'support@snacklist.app');
  assertEquals(marked, [12]);
  assertEquals(out.at(-1), 'sent to a***@e***.org; notified_at recorded');
  noAddress(out);
});

Deno.test('a decision already notified is refused unless --again', async () => {
  const notified = { ...ROW, notifiedAt: new Date('2026-11-16T18:00:00Z') };
  const first = setup(notified);
  assertEquals(
    await run({ kind: 'decision', decision: 12, send: true, again: false }, first.deps),
    1,
  );
  assertEquals([first.sent.length, first.marked.length], [0, 0]);
  assert(first.out.includes('Already notified: 2026-11-16T18:00:00.000Z'));
  const again = setup(notified);
  assertEquals(
    await run({ kind: 'decision', decision: 12, send: true, again: true }, again.deps),
    0,
  );
  assertEquals([again.sent.length, again.marked.length], [1, 1]);
  // A new key, or Resend would drop the resend as a repeat of the first within 24 hours.
  assertEquals(again.sent[0]?.key, `report-decision/12/${notified.notifiedAt.getTime()}`);
});

Deno.test('no decision, no address, no Resend key: exit 1, nothing sent', async () => {
  const missing = setup(null);
  assertEquals(
    await run({ kind: 'decision', decision: 99, send: true, again: false }, missing.deps),
    1,
  );
  assertEquals(missing.out, ['notify: no decision 99']);
  const anonymous = setup({ ...ROW, email: null, name: null });
  assertEquals(
    await run({ kind: 'decision', decision: 12, send: true, again: false }, anonymous.deps),
    1,
  );
  assertEquals(anonymous.sent.length, 0);
  const unconfigured = setup(ROW, { mailer: null });
  assertEquals(
    await run({ kind: 'decision', decision: 12, send: true, again: false }, unconfigured.deps),
    1,
  );
  assertEquals(unconfigured.out.at(-1), 'notify: --send needs RESEND_API_KEY');
  assertEquals(unconfigured.marked.length, 0);
});

Deno.test('a failed send prints its status only and records nothing', async () => {
  const { deps, out, marked } = setup(ROW, {
    mailer: {
      send: () => Promise.reject(Object.assign(new Error(`refused ${EMAIL}`), { status: 422 })),
    },
  });
  assertEquals(await run({ kind: 'decision', decision: 12, send: true, again: false }, deps), 1);
  assertEquals(out.at(-1), 'notify: failed (HTTP 422)');
  assertEquals(marked.length, 0);
  noAddress(out);
});

Deno.test('English decision', async () => {
  const { deps, out } = setup({
    ...ROW,
    locale: 'en',
    outcome: 'no_change',
    ground: 'We could not find it',
  });
  assertEquals(await run({ kind: 'decision', decision: 12, send: false, again: false }, deps), 0);
  const text = out.join('\n');
  assert(text.includes('Subject: Our decision on your report (M-7KQ2-XW9D)'));
  assert(
    text.includes('Decision: we changed nothing. Reason: We could not find it. A person made'),
  );
});

const PENDING: PendingRow[] = [
  {
    id: '5ce03c7a-0000-4000-8000-000000000001',
    ref: 'M-AAAA-0001',
    locale: 'de',
    name: 'Anna',
    email: EMAIL,
    createdAt: new Date('2026-11-17T07:00:00Z'),
  },
  {
    id: '5ce03c7a-0000-4000-8000-000000000002',
    ref: 'M-AAAA-0002',
    locale: 'en',
    name: null,
    email: 'test+b@snacklist.app',
    createdAt: new Date('2026-11-17T07:30:00Z'),
  },
];

Deno.test('--confirmations lists what the function missed, 15 minutes back, and sends nothing (N-244)', async () => {
  const { deps, out, sent, confirmed, asked } = setup(null, {}, PENDING);
  assertEquals(await run({ kind: 'confirmations', send: false }, deps), 0);
  assertEquals(asked.map((d) => d.toISOString()), ['2026-11-17T07:45:00.000Z']);
  assert(out.includes('2 report(s) with an address still owe their confirmation'));
  assert(out.some((l) => l.startsWith('M-AAAA-0001') && l.includes('a***@e***.org')));
  assertEquals([sent.length, confirmed.length], [0, 0]);
  noAddress(out);
});

Deno.test("--confirmations --send mails each its B.4 confirmation with the function's key and records it", async () => {
  const { deps, out, sent, confirmed } = setup(null, {}, PENDING);
  assertEquals(await run({ kind: 'confirmations', send: true }, deps), 0);
  assertEquals(sent.map((s) => s.key), PENDING.map((p) => `report-confirm/${p.id}`));
  assertEquals(sent[0]?.mail.subject, 'Deine Meldung an Snacklist ist eingegangen (M-AAAA-0001)');
  assertEquals(sent[1]?.mail.subject, "We've received your report to Snacklist (M-AAAA-0002)");
  assert(sent[1]?.mail.text.startsWith('Hi, thanks for'));
  assertEquals(confirmed, PENDING.map((p) => p.id));
  noAddress(out);
});

Deno.test('--confirmations --send: one failure is reported, the rest go out, exit 1', async () => {
  let n = 0;
  const { deps, out, confirmed } = setup(null, {
    mailer: {
      send: () =>
        ++n === 1
          ? Promise.reject(Object.assign(new Error('x'), { status: 503 }))
          : Promise.resolve(),
    },
  }, PENDING);
  assertEquals(await run({ kind: 'confirmations', send: true }, deps), 1);
  assert(out.includes('M-AAAA-0001: failed (HTTP 503); run it again later'));
  assertEquals(confirmed, [PENDING[1]?.id]);
  noAddress(out);
});

Deno.test('--confirmations with nothing pending, or --send without a Resend key', async () => {
  assertEquals(
    await run({ kind: 'confirmations', send: true }, setup(null, { mailer: null }).deps),
    0,
  );
  const { deps, out } = setup(null, { mailer: null }, PENDING);
  assertEquals(await run({ kind: 'confirmations', send: true }, deps), 1);
  assert(out.includes('notify: --send needs RESEND_API_KEY'));
});
