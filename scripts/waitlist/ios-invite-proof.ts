// Drives ios-invite.ts as a process against a local stack's database, with a fake Resend on
// 127.0.0.1, so no mail can leave the machine. Then it sends the one-click POST of a sent mail
// through the site's /api/waitlist/unsubscribe and the waitlist edge handler over the same
// database. Never point it at production: it refuses a database URL that is not 127.0.0.1.
//
//   deno run -A scripts/waitlist/ios-invite-proof.ts postgresql://postgres:postgres@127.0.0.1:<port>/postgres <out-dir>
//
// Seeds and removes test+280-…@snacklist.app rows only. Prints counts and outcomes, no address.
import { createHandler } from '../../supabase/functions/waitlist/handler.ts';
import { sqlStore } from '../../supabase/functions/waitlist/store.ts';
import { handle } from '../../site/api/_waitlist.mjs';

const [dbUrl, outDir] = Deno.args;
if (!dbUrl || !outDir || !/^postgres(?:ql)?:\/\/[^@]+@127\.0\.0\.1:[0-9]+\//.test(dbUrl)) {
  console.error('usage: ios-invite-proof.ts postgresql://…@127.0.0.1:<port>/postgres <out-dir>');
  Deno.exit(2);
}
const HMAC = 'local-proof-hmac-secret';
const PROXY = 'local-proof-proxy-secret';
const { default: postgres } = await import('postgres');
const sql = postgres(dbUrl, { max: 1, prepare: false, onnotice: () => {} });
const lines: string[] = [];
const say = (line: string) => {
  lines.push(line);
  console.log(line);
};
const check = (ok: boolean, what: string) => {
  say(`${ok ? 'PASS' : 'FAIL'}: ${what}`);
  if (!ok) Deno.exitCode = 1;
};

interface Captured {
  to: string;
  subject: string;
  headers: Record<string, string>;
  key: string;
}
const captured: Captured[] = [];
/** Statuses the fake answers before it goes back to 200, one per request. */
const failNext: number[] = [];
const resend = Deno.serve({ hostname: '127.0.0.1', port: 0, onListen: () => {} }, async (req) => {
  const body = await req.json() as {
    to: string[];
    subject: string;
    headers?: Record<string, string>;
  };
  captured.push({
    to: body.to[0] ?? '',
    subject: body.subject,
    headers: body.headers ?? {},
    key: req.headers.get('idempotency-key') ?? '',
  });
  const status = failNext.shift();
  return status ? new Response('{}', { status }) : Response.json({ id: crypto.randomUUID() });
});

async function invite(env: Record<string, string>, args: string[] = []): Promise<string[]> {
  const out = await new Deno.Command(Deno.execPath(), {
    args: ['run', '-A', new URL('./ios-invite.ts', import.meta.url).pathname, ...args],
    clearEnv: true,
    env: {
      PATH: Deno.env.get('PATH') ?? '',
      HOME: Deno.env.get('HOME') ?? '',
      SUPABASE_DB_URL: dbUrl ?? '',
      WAITLIST_HMAC_SECRET: HMAC,
      RESEND_API_KEY: 're_local_proof_not_a_key',
      RESEND_API_URL: `http://127.0.0.1:${resend.addr.port}`,
      ...env,
    },
    stdout: 'piped',
    stderr: 'piped',
  }).output();
  const text = new TextDecoder().decode(out.stdout) + new TextDecoder().decode(out.stderr);
  const printed = text.trimEnd().split('\n');
  for (const l of printed) {
    const tmp = l.match(/(\/tmp\/ios-invite-[0-9a-z]+)\//)?.[1];
    if (tmp) await Deno.remove(tmp, { recursive: true });
    say(
      `  | ${
        l.replaceAll(outDir ?? '', '<out-dir>').replace(/\/tmp\/ios-invite-[0-9a-z]+/, '<temp-dir>')
      }`,
    );
  }
  say(`  | (exit ${out.code})`);
  return printed;
}

const seed = async () => {
  await sql`delete from public.waitlist where email like 'test+280-%@snacklist.app'`;
  await sql`
    insert into public.waitlist (email, email_hmac, platform, locale, consent_text_version,
      created_at, confirm_token_hash, confirm_expires_at, confirmed_at, invite_sent_at)
    select v.email, encode(extensions.digest(v.email, 'sha256'), 'hex'), v.platform, v.locale,
      'waitlist-' || v.locale || '-v2', now() - interval '3 days',
      case when v.confirmed then null else encode(extensions.digest('t' || v.email, 'sha256'), 'hex') end,
      case when v.confirmed then null else now() + interval '1 day' end,
      case when v.confirmed then now() - interval '2 days' end,
      case when v.invited then now() - interval '1 day' end
    from (values
      ('test+280-ios-de@snacklist.app', 'ios', 'de', true, false),
      ('test+280-ios-en@snacklist.app', 'ios', 'en', true, false),
      ('test+280-android@snacklist.app', 'android', 'de', true, false),
      ('test+280-unconfirmed@snacklist.app', 'ios', 'en', false, false),
      ('test+280-invited@snacklist.app', 'ios', 'de', true, true)
    ) v(email, platform, locale, confirmed, invited)`;
};
const invitedCount = async () =>
  (await sql<{ n: number }[]>`
    select count(*)::integer as n from public.waitlist
    where email like 'test+280-%@snacklist.app' and invite_sent_at is not null`)[0]?.n ?? -1;

try {
  const others = (await sql<{ n: number }[]>`
    select count(*)::integer as n from public.waitlist where email not like 'test+280-%@snacklist.app'`)[
    0
  ]
    ?.n;
  if (others !== 0) {
    throw new Error('the database holds other waitlist rows: use a fresh local stack');
  }
  await seed();
  say('seeded: iOS de and en confirmed, Android confirmed, iOS unconfirmed, iOS already invited');

  say('\n1. dry run (no INVITE_SEND), BATCH_SIZE=10');
  const dry = await invite({ BATCH_SIZE: '10' }, ['--preview-dir', outDir]);
  const token = dry.at(-1)?.match(/INVITE_CONFIRM=([0-9a-f]{16})$/)?.[1] ?? '';
  check(captured.length === 0, 'the dry run sent nothing to Resend');
  check(await invitedCount() === 1, 'the dry run marked no row');

  say('\n2. send with the token (WAITLIST_MAIL_ALLOW unset: test addresses only)');
  const send = {
    INVITE_SEND: '1',
    BATCH_SIZE: '10',
    INVITE_CONFIRM: token,
  };
  await invite(send);
  check(captured.length === 2, 'two mails, one per iPhone recipient');
  check(
    captured.map((c) => `${c.to.replace(/^test\+280-|@snacklist\.app$/g, '')}: ${c.subject}`).sort()
      .join(
        ', ',
      ) ===
      'ios-de: Deine Einladung zur Snacklist-Beta, ios-en: Your invite to the Snacklist beta',
    'each in its sign-up language; no Android, unconfirmed or invited row',
  );
  check(
    captured.every((c) =>
      /^<https:\/\/snacklist\.app\/api\/waitlist\/unsubscribe\?id=[0-9a-f-]{36}&s=[0-9a-f]{64}&l=(de|en)>$/
        .test(c.headers['List-Unsubscribe'] ?? '') &&
      c.headers['List-Unsubscribe-Post'] === 'List-Unsubscribe=One-Click' &&
      /^ios-invite\/[0-9a-f-]{36}$/.test(c.key)
    ),
    'List-Unsubscribe (https), List-Unsubscribe-Post One-Click and an idempotency key on each',
  );
  check(await invitedCount() === 3, 'both rows are marked invited');

  say('\n3. the same send again');
  await invite(send);
  say('   and a fresh dry run');
  const again = await invite({ BATCH_SIZE: '10' });
  check(captured.length === 2, 'no second mail');
  check(again.some((l) => l.startsWith('batch: 0 ')), 'no recipient left');

  say("\n4. one-click POST of the German mail's List-Unsubscribe URL");
  const de = captured.find((c) => c.subject.startsWith('Deine'));
  const url = new URL(de?.headers['List-Unsubscribe']?.slice(1, -1) ?? 'https://invalid');
  const edge = createHandler({
    config: { proxySecret: PROXY, hmacSecret: HMAC, allow: 'test', allowPlaceholders: false },
    store: sqlStore(() => sql),
    mailer: null,
    now: () => new Date(),
    random: (n) => crypto.getRandomValues(new Uint8Array(n)),
    defer: (work) => work(),
  });
  const res = await handle(
    'unsubscribe',
    new Request(url, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded', host: url.host },
      body: 'List-Unsubscribe=One-Click',
    }),
    {
      env: {
        WAITLIST_UPSTREAM_URL: 'https://edge.local/functions/v1/waitlist',
        WAITLIST_PROXY_SECRET: PROXY,
      },
      fetch: (u: string, init: RequestInit) => edge(new Request(u, init)),
      now: new Date(),
    },
  );
  const answer = await res.text();
  say(`  | ${res.status} ${answer}`);
  const gone = (await sql<{ n: number }[]>`
    select count(*)::integer as n from public.waitlist where id = ${
    url.searchParams.get('id') ?? ''
  }::uuid`)[0]?.n;
  check(
    res.status === 200 && answer === '{"status":"deleted"}' && gone === 0,
    'the entry is deleted at once',
  );

  say('\n5. Resend answers 502 to the first send of a fresh batch');
  await seed();
  captured.length = 0;
  failNext.push(502);
  const dry5 = await invite({ BATCH_SIZE: '10' });
  const token5 = dry5.at(-1)?.match(/INVITE_CONFIRM=([0-9a-f]{16})$/)?.[1] ?? '';
  await invite({ ...send, INVITE_CONFIRM: token5 });
  check(captured.length === 1 && await invitedCount() === 2, 'the run stops; the row stays marked');
  say('   a fresh dry run and send');
  const dry6 = await invite({ BATCH_SIZE: '10' });
  const token6 = dry6.at(-1)?.match(/INVITE_CONFIRM=([0-9a-f]{16})$/)?.[1] ?? '';
  await invite({ ...send, INVITE_CONFIRM: token6 });
  const keys = captured.map((c) => c.key);
  check(
    captured.length === 2 && new Set(keys).size === 2,
    'the later run mails only the other row: nobody gets the invite twice',
  );
} finally {
  await sql`delete from public.waitlist where email like 'test+280-%@snacklist.app'`;
  await sql`delete from public.waitlist_consent_proof
    where email_hmac = encode(extensions.digest('test+280-ios-de@snacklist.app', 'sha256'), 'hex')`;
  await sql.end();
  await resend.shutdown();
  await Deno.writeTextFile(`${outDir}/proof.txt`, lines.join('\n') + '\n');
}
