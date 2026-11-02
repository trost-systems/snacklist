// Invites one weekly waitlist batch to the beta (docs/WAITLIST.md "Invites"). Peter runs it on his
// own machine; no agent runs --confirm.
//
//   deno run -A scripts/waitlist/invite.ts --batch 2026-W47
//       counts only: confirmed, already invited, to invite, per platform and locale
//   deno run -A scripts/waitlist/invite.ts --batch 2026-W47 --confirm 2026-W47 [--export-dir <dir>]
//       mails the invite to each uninvited row of the batch and records it; with --export-dir,
//       writes ios.csv and android.csv of the rows invited now for TestFlight and Google Play
//
// Env: SUPABASE_DB_URL; for --confirm also RESEND_API_KEY and WAITLIST_HMAC_SECRET (RESEND_API_URL,
// WAITLIST_MAIL_ALLOW as for the edge function). It prints counts only, never an address, also not
// when something fails. It refuses an invite with ⟦…⟧ placeholders unless --allow-placeholders,
// which works only while WAITLIST_MAIL_ALLOW keeps to test addresses.
import { unsubscribeSig } from '../../supabase/functions/waitlist/crypto.ts';
import {
  hasPlaceholder,
  inviteMail,
  type Locale,
  type MailAllow,
  mailAllowFrom,
  type Platform,
  refusal,
  SITE_ORIGIN,
  unsubscribeLinks,
} from '../../supabase/functions/waitlist/mail.ts';
import {
  type Mailer,
  RESEND_API_URL,
  resendMailer,
} from '../../supabase/functions/waitlist/resend.ts';

export interface Counts {
  platform: Platform;
  locale: Locale;
  confirmed: number;
  invited: number;
  toInvite: number;
}

export interface InviteRow {
  id: string;
  email: string;
  platform: Platform;
  locale: Locale;
}

/** public.waitlist_batch_counts, waitlist_batch_rows and waitlist_mailed. */
export interface InviteStore {
  counts(batch: string): Promise<Counts[]>;
  rows(batch: string): Promise<InviteRow[]>;
  invited(id: string, now: Date): Promise<boolean>;
}

export interface Args {
  batch: string;
  confirm: boolean;
  exportDir: string | null;
  allowPlaceholders: boolean;
}

const BATCH = /^[0-9]{4}-W[0-9]{2}$/;

export function parseArgs(argv: string[]): Args | string {
  const values = new Map<string, string>();
  let allowPlaceholders = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--allow-placeholders') allowPlaceholders = true;
    else if (['--batch', '--confirm', '--export-dir'].includes(argv[i])) {
      values.set(argv[i], argv[++i] ?? '');
    } else return 'unknown argument';
  }
  const batch = values.get('--batch');
  const confirm = values.get('--confirm');
  const exportDir = values.get('--export-dir');
  if (!batch || !BATCH.test(batch)) return '--batch <id> is required, like --batch 2026-W47';
  if (confirm !== undefined && confirm !== batch) {
    return '--confirm must repeat the batch id: --batch 2026-W47 --confirm 2026-W47';
  }
  if (exportDir !== undefined && (!exportDir || confirm === undefined)) {
    return '--export-dir <dir> goes with --confirm';
  }
  return { batch, confirm: confirm !== undefined, exportDir: exportDir ?? null, allowPlaceholders };
}

export interface Deps {
  store: InviteStore;
  /** Null without RESEND_API_KEY. */
  mailer: Mailer | null;
  /** Null without WAITLIST_HMAC_SECRET. */
  hmacSecret: string | null;
  allow: MailAllow;
  now(): Date;
  print(line: string): void;
  writeFile(path: string, text: string): Promise<void>;
}

/** The SQLSTATE or error name only: a Postgres detail or a Resend answer may hold an address. */
const reason = (e: unknown) => {
  const code = (e as { code?: unknown })?.code;
  if (typeof code === 'string' && /^[0-9A-Z]{5}$/.test(code)) return code;
  return e instanceof Error && /^[A-Za-z]+$/.test(e.name) ? e.name : 'error';
};

/** Runs the command; returns the exit code. */
export async function run(args: Args, deps: Deps): Promise<number> {
  try {
    return await invite(args, deps);
  } catch (e) {
    deps.print(`invite: failed (${reason(e)})`);
    return 1;
  }
}

async function invite(args: Args, deps: Deps): Promise<number> {
  const { batch } = args;
  const counts = await deps.store.counts(batch);
  const sum = (key: 'confirmed' | 'invited' | 'toInvite') => counts.reduce((n, c) => n + c[key], 0);
  deps.print(`batch ${batch} (ISO week of confirmation, Europe/Berlin)`);
  for (const c of counts) {
    deps.print(
      `  ${c.platform.padEnd(7)} ${c.locale}: confirmed ${c.confirmed}, already invited ` +
        `${c.invited}, to invite ${c.toInvite}`,
    );
  }
  deps.print(
    `  total     : confirmed ${sum('confirmed')}, already invited ${sum('invited')}, to invite ` +
      `${sum('toInvite')}`,
  );
  if (!args.confirm) {
    deps.print(`dry run: nothing sent. To send: --batch ${batch} --confirm ${batch}`);
    return 0;
  }

  if (!deps.mailer || !deps.hmacSecret) {
    deps.print('invite: --confirm needs RESEND_API_KEY and WAITLIST_HMAC_SECRET');
    return 1;
  }
  if (args.allowPlaceholders && deps.allow === 'all') {
    deps.print('invite: --allow-placeholders works only while WAITLIST_MAIL_ALLOW is unset');
    return 1;
  }
  const policy = { allow: deps.allow, allowPlaceholders: args.allowPlaceholders };
  const draft = (['de', 'en'] as const).flatMap((locale) =>
    (['ios', 'android'] as const).map((platform) =>
      inviteMail(locale, { platform, unsubscribe: unsubscribeLinks(SITE_ORIGIN, locale, '', '') })
    )
  ).some(hasPlaceholder);
  if (draft && !policy.allowPlaceholders) {
    deps.print('invite: refused, the invite mail still has ⟦…⟧ placeholders');
    return 1;
  }

  const result = { sent: 0, skipped: 0, failed: 0 };
  const invited: Record<Platform, string[]> = { ios: [], android: [] };
  for (const row of await deps.store.rows(batch)) {
    const sig = await unsubscribeSig(deps.hmacSecret, row.id);
    const mail = inviteMail(row.locale, {
      platform: row.platform,
      unsubscribe: unsubscribeLinks(SITE_ORIGIN, row.locale, row.id, sig),
    });
    if (refusal(row.email, mail, policy)) {
      result.skipped++;
      continue;
    }
    try {
      // The same key on a rerun after a crash: Resend sends it only once.
      await deps.mailer.send(row.email, mail, `invite/${batch}/${row.id}`);
    } catch {
      result.failed++;
      continue;
    }
    await deps.store.invited(row.id, deps.now());
    invited[row.platform].push(row.email);
    result.sent++;
  }
  deps.print(
    `sent ${result.sent}, skipped ${result.skipped} (not allowed by WAITLIST_MAIL_ALLOW), ` +
      `failed ${result.failed}`,
  );
  if (args.exportDir) {
    // TestFlight imports first name, last name, email; Google Play's email list one address a line.
    await deps.writeFile(
      `${args.exportDir}/ios.csv`,
      invited.ios.map((e) => `,,${e}\n`).join(''),
    );
    await deps.writeFile(
      `${args.exportDir}/android.csv`,
      invited.android.map((e) => `${e}\n`).join(''),
    );
    deps.print(
      `wrote ios.csv (${invited.ios.length}) and android.csv (${invited.android.length}) to ` +
        args.exportDir,
    );
  }
  return result.failed ? 1 : 0;
}

if (import.meta.main) {
  const args = parseArgs(Deno.args);
  if (typeof args === 'string') {
    console.error(`invite: ${args}`);
    Deno.exit(2);
  }
  const { default: postgres } = await import('npm:postgres@3.4.9');
  const url = Deno.env.get('SUPABASE_DB_URL');
  if (!url) {
    console.error('invite: SUPABASE_DB_URL is not set');
    Deno.exit(2);
  }
  const sql = postgres(url, { max: 1, prepare: false, onnotice: () => {} });
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const code = await run(args, {
    store: {
      counts: (batch) =>
        sql<Counts[]>`
          select platform, locale, confirmed, invited, to_invite as "toInvite"
          from public.waitlist_batch_counts(${batch})`,
      rows: (batch) =>
        sql<InviteRow[]>`select id, email, platform, locale
          from public.waitlist_batch_rows(${batch})`,
      invited: async (id, now) => {
        const [r] = await sql<{ ok: boolean }[]>`
          select public.waitlist_mailed(${id}::uuid, 'invite', ${now.toISOString()}::timestamptz)
            as ok`;
        return r.ok;
      },
    },
    mailer: apiKey ? resendMailer(apiKey, Deno.env.get('RESEND_API_URL') || RESEND_API_URL) : null,
    hmacSecret: Deno.env.get('WAITLIST_HMAC_SECRET') || null,
    allow: mailAllowFrom(Deno.env.get('WAITLIST_MAIL_ALLOW')),
    now: () => new Date(),
    print: (line) => console.log(line),
    writeFile: (path, text) => Deno.writeTextFile(path, text, { mode: 0o600 }),
  });
  await sql.end();
  Deno.exit(code);
}
