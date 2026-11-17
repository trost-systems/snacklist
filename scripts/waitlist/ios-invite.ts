// Mails the iOS beta invite to confirmed iPhone sign-ups of the waitlist (docs/WAITLIST.md "iOS
// invite"). One Resend send per recipient in their sign-up locale; nothing goes to a Resend
// audience or broadcast. Peter runs it on his own machine; no agent sets INVITE_SEND.
//
//   deno run -A scripts/waitlist/ios-invite.ts [--preview-dir <dir>]
//       dry run (the default): counts, renders every mail of the batch with its real headers,
//       writes the redacted previews and prints the batch's confirmation token; sends nothing
//   INVITE_SEND=1 BATCH_SIZE=<n> INVITE_CONFIRM=<token> deno run -A scripts/waitlist/ios-invite.ts
//       [--export-dir <dir>]
//       sends that batch; with --export-dir, writes ios.csv of the rows invited now for TestFlight
//
// Env: SUPABASE_DB_URL and WAITLIST_HMAC_SECRET always; RESEND_API_KEY to send (RESEND_API_URL,
// WAITLIST_MAIL_ALLOW as for the edge function). The token covers the batch's rows and the mail,
// so a send after either changed is refused. Each row is marked invited before its send and
// unmarked only when Resend refused it, so no rerun mails anyone twice. It prints counts only,
// never an address, also not when something fails. A mail with a ⟦…⟧ marker is refused unless
// INVITE_ALLOW_PLACEHOLDERS=1, which works only while WAITLIST_MAIL_ALLOW keeps to test addresses.
import { sha256Hex, unsubscribeSig } from '../../supabase/functions/waitlist/crypto.ts';
import {
  hasPlaceholder,
  inviteMail,
  type Locale,
  type Mail,
  type MailAllow,
  mailAllowFrom,
  refusal,
  SITE_ORIGIN,
  unsubscribeLinks,
} from '../../supabase/functions/waitlist/mail.ts';
import {
  type Mailer,
  MailError,
  RESEND_API_URL,
  resendMailer,
} from '../../supabase/functions/_shared/resend.ts';

const LOCALES = ['de', 'en'] as const;

export interface IosCounts {
  locale: Locale;
  confirmed: number;
  invited: number;
  toInvite: number;
}

export interface IosRow {
  id: string;
  email: string;
  locale: Locale;
}

/** public.waitlist_ios_invite_counts, _rows, waitlist_invite_claim, _release, waitlist_mailed. */
export interface IosInviteStore {
  counts(): Promise<IosCounts[]>;
  /** The next [limit] uninvited confirmed iOS rows; null means all. */
  rows(limit: number | null): Promise<IosRow[]>;
  /** Marks the row invited; false when another run did or it is no recipient any more. */
  claim(id: string, now: Date): Promise<boolean>;
  release(id: string, claimedAt: Date): Promise<boolean>;
  mailed(id: string, now: Date): Promise<boolean>;
}

export interface Settings {
  send: boolean;
  batchSize: number | null;
  confirm: string | null;
  allowPlaceholders: boolean;
  previewDir: string | null;
  exportDir: string | null;
}

export function settingsFrom(
  env: (name: string) => string | undefined,
  argv: string[],
): Settings | string {
  const values = new Map<string, string>();
  const args = argv.values();
  for (const arg of args) {
    if (arg === '--preview-dir' || arg === '--export-dir') values.set(arg, args.next().value ?? '');
    else return 'unknown argument';
  }
  const send = env('INVITE_SEND') ?? '';
  if (!['', '0', '1'].includes(send)) return 'INVITE_SEND is 1 to send, unset for the dry run';
  const size = env('BATCH_SIZE') ?? '';
  if (size && !/^[1-9][0-9]{0,5}$/.test(size)) return 'BATCH_SIZE is a positive whole number';
  const previewDir = values.get('--preview-dir');
  const exportDir = values.get('--export-dir');
  if (previewDir === '') return '--preview-dir needs a directory';
  if (exportDir !== undefined && (!exportDir || send !== '1')) {
    return '--export-dir <dir> goes with INVITE_SEND=1';
  }
  return {
    send: send === '1',
    batchSize: size ? Number(size) : null,
    confirm: env('INVITE_CONFIRM') || null,
    allowPlaceholders: env('INVITE_ALLOW_PLACEHOLDERS') === '1',
    previewDir: previewDir ?? null,
    exportDir: exportDir ?? null,
  };
}

export interface Deps {
  store: IosInviteStore;
  /** Null without RESEND_API_KEY. */
  mailer: Mailer | null;
  /** Null without WAITLIST_HMAC_SECRET. */
  hmacSecret: string | null;
  allow: MailAllow;
  now(): Date;
  print(line: string): void;
  writeFile(path: string, text: string): Promise<void>;
  makeTempDir(): Promise<string>;
}

const iosInvite = (locale: Locale, id: string, sig: string): Mail =>
  inviteMail(locale, {
    platform: 'ios',
    unsubscribe: unsubscribeLinks(SITE_ORIGIN, locale, id, sig),
  });

/** The mail every recipient of [locale] gets, with the link values as `{id}` and `{sig}`. */
const preview = (locale: Locale) => iosInvite(locale, '{id}', '{sig}');

const redact = (mail: Mail, id: string, sig: string): Mail => {
  const r = (s: string) => s.replaceAll(id, '{id}').replaceAll(sig, '{sig}');
  return {
    ...mail,
    subject: r(mail.subject),
    html: r(mail.html),
    text: r(mail.text),
    headers: Object.fromEntries(Object.entries(mail.headers).map(([k, v]) => [k, r(v)])),
  };
};

function previewText(mail: Mail, recipients: number): string {
  return [
    `From: ${mail.from}`,
    `Reply-To: ${mail.replyTo}`,
    'To: <recipient>',
    `Subject: ${mail.subject}`,
    ...Object.entries(mail.headers).map(([k, v]) => `${k}: ${v}`),
    `X-Preview-Recipients: ${recipients}`,
    '',
    mail.text,
  ].join('\n');
}

/**
 * Only a 4xx says Resend did not take the mail; a 5xx can come after it did, 408 is a timeout and
 * 409 an idempotency conflict with a send of the same key.
 */
const refusedForSure = (e: unknown): boolean =>
  e instanceof MailError && e.status >= 400 && e.status < 500 && e.status !== 408 &&
  e.status !== 409;

/** The SQLSTATE or error name only: a Postgres detail or a Resend answer may hold an address. */
const reason = (e: unknown) => {
  const code = (e as { code?: unknown })?.code;
  if (typeof code === 'string' && /^[0-9A-Z]{5}$/.test(code)) return code;
  return e instanceof Error && /^[A-Za-z]+$/.test(e.name) ? e.name : 'error';
};

/** Runs the command; returns the exit code. */
export async function run(settings: Settings, deps: Deps): Promise<number> {
  try {
    return await invite(settings, deps);
  } catch (e) {
    deps.print(`ios-invite: failed (${reason(e)})`);
    return 1;
  }
}

async function invite(settings: Settings, deps: Deps): Promise<number> {
  if (!deps.hmacSecret) {
    deps.print('ios-invite: needs WAITLIST_HMAC_SECRET for the unsubscribe links');
    return 1;
  }
  const hmacSecret = deps.hmacSecret;
  const counts = await deps.store.counts();
  deps.print('iOS invite: confirmed iPhone sign-ups without an invite, in their sign-up language');
  for (const c of counts) {
    deps.print(
      `  ${c.locale}: confirmed ${c.confirmed}, already invited ${c.invited}, to invite ${c.toInvite}`,
    );
  }

  const rows = await deps.store.rows(settings.batchSize);
  const previews = { de: preview('de'), en: preview('en') };
  const planned = await Promise.all(rows.map(async (row) => {
    const sig = await unsubscribeSig(hmacSecret, row.id);
    const mail = iosInvite(row.locale, row.id, sig);
    // The previews are the review: a mail that differs from its preview beyond the link values
    // is a bug and stops the run.
    if (JSON.stringify(redact(mail, row.id, sig)) !== JSON.stringify(previews[row.locale])) {
      throw new Error('PreviewMismatch');
    }
    return { row, mail };
  }));
  const policy = { allow: deps.allow, allowPlaceholders: settings.allowPlaceholders };
  const perLocale = (locale: Locale) => planned.filter((p) => p.row.locale === locale).length;
  const notAllowed = planned.filter((p) => refusal(p.row.email, p.mail, policy) === 'recipient');
  deps.print(
    `batch: ${planned.length} (de ${perLocale('de')}, en ${perLocale('en')})` +
      (settings.batchSize ? `, BATCH_SIZE ${settings.batchSize}` : ', all (no BATCH_SIZE)') +
      `; not allowed by WAITLIST_MAIL_ALLOW: ${notAllowed.length}`,
  );

  // A send writes previews only when asked: the dry run before it showed them.
  if (!settings.send || settings.previewDir) {
    const dir = settings.previewDir ?? await deps.makeTempDir();
    for (const locale of LOCALES) {
      await deps.writeFile(
        `${dir}/ios-invite-${locale}.txt`,
        previewText(previews[locale], perLocale(locale)),
      );
      await deps.writeFile(`${dir}/ios-invite-${locale}.html`, previews[locale].html);
    }
    deps.print(`previews (link values redacted): ${dir}/ios-invite-{de,en}.{txt,html}`);
  }
  const drafty = LOCALES.some((l) => hasPlaceholder(previews[l]));
  if (drafty) deps.print('the mail still has ⟦…⟧ placeholders');

  const token = (await sha256Hex(JSON.stringify({
    batchSize: settings.batchSize,
    ids: planned.map((p) => p.row.id),
    previews,
  }))).slice(0, 16);

  if (!settings.send) {
    deps.print(
      settings.batchSize
        ? `dry run: nothing sent. To send this batch: INVITE_SEND=1 BATCH_SIZE=${settings.batchSize} ` +
          `INVITE_CONFIRM=${token}`
        : 'dry run: nothing sent. To send, run the dry run again with BATCH_SIZE=<n> for its token',
    );
    return 0;
  }

  if (!settings.batchSize) {
    deps.print('ios-invite: INVITE_SEND=1 needs BATCH_SIZE');
    return 1;
  }
  if (!settings.confirm) {
    deps.print('ios-invite: INVITE_SEND=1 needs INVITE_CONFIRM, the token of the dry run');
    return 1;
  }
  if (!deps.mailer) {
    deps.print('ios-invite: INVITE_SEND=1 needs RESEND_API_KEY');
    return 1;
  }
  if (settings.allowPlaceholders && deps.allow === 'all') {
    deps.print(
      'ios-invite: INVITE_ALLOW_PLACEHOLDERS works only while WAITLIST_MAIL_ALLOW is unset',
    );
    return 1;
  }
  if (drafty && !settings.allowPlaceholders) {
    deps.print('ios-invite: refused, the mail still has ⟦…⟧ placeholders');
    return 1;
  }
  if (settings.confirm !== token) {
    deps.print(
      "ios-invite: refused, INVITE_CONFIRM is not this batch's token (the recipients or the mail " +
        'changed since that dry run); run the dry run again',
    );
    return 1;
  }

  const result = { sent: 0, skipped: 0, taken: 0, failed: 0 };
  const invited: string[] = [];
  let unanswered = false;
  for (const { row, mail } of planned) {
    if (refusal(row.email, mail, policy)) {
      result.skipped++;
      continue;
    }
    const claimedAt = deps.now();
    if (!await deps.store.claim(row.id, claimedAt)) {
      result.taken++;
      continue;
    }
    try {
      await deps.mailer.send(row.email, mail, `ios-invite/${row.id}`);
    } catch (e) {
      if (refusedForSure(e)) {
        await deps.store.release(row.id, claimedAt);
        result.failed++;
        continue;
      }
      // No answer, a 5xx, a timeout or an idempotency conflict: the mail may have gone out, so
      // the row stays marked and the run stops.
      unanswered = true;
      break;
    }
    await deps.store.mailed(row.id, deps.now());
    invited.push(row.email);
    result.sent++;
  }
  deps.print(
    `sent ${result.sent}, skipped ${result.skipped} (not allowed by WAITLIST_MAIL_ALLOW), ` +
      `already invited by another run ${result.taken}, refused by Resend ${result.failed} ` +
      '(left uninvited for a later run)',
  );
  if (unanswered) {
    deps.print(
      'ios-invite: stopped, one send got no clear answer from Resend (none, or 408, 409 or 5xx); ' +
        'its row stays marked invited ' +
        '(Resend log, idempotency key ios-invite/<id>)',
    );
  }
  if (settings.exportDir) {
    // TestFlight imports first name, last name, email.
    await deps.writeFile(`${settings.exportDir}/ios.csv`, invited.map((e) => `,,${e}\n`).join(''));
    deps.print(`wrote ios.csv (${invited.length}) to ${settings.exportDir}`);
  }
  return result.failed || unanswered ? 1 : 0;
}

if (import.meta.main) {
  const settings = settingsFrom((name) => Deno.env.get(name), Deno.args);
  if (typeof settings === 'string') {
    console.error(`ios-invite: ${settings}`);
    Deno.exit(2);
  }
  const { default: postgres } = await import('postgres');
  const url = Deno.env.get('SUPABASE_DB_URL');
  if (!url) {
    console.error('ios-invite: SUPABASE_DB_URL is not set');
    Deno.exit(2);
  }
  const sql = postgres(url, { max: 1, prepare: false, onnotice: () => {} });
  const flag = async (q: Promise<{ ok: boolean }[]>) => (await q)[0]?.ok === true;
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const code = await run(settings, {
    store: {
      counts: () =>
        sql<IosCounts[]>`
          select locale, confirmed, invited, to_invite as "toInvite"
          from public.waitlist_ios_invite_counts()`,
      rows: (limit) =>
        sql<IosRow[]>`select id, email, locale from public.waitlist_ios_invite_rows(${limit})`,
      claim: (id, now) =>
        flag(sql<{ ok: boolean }[]>`
          select public.waitlist_invite_claim(${id}::uuid, ${now.toISOString()}::timestamptz)
            as ok`),
      release: (id, claimedAt) =>
        flag(sql<{ ok: boolean }[]>`
          select public.waitlist_invite_release(${id}::uuid, ${claimedAt.toISOString()}::timestamptz)
            as ok`),
      mailed: (id, now) =>
        flag(sql<{ ok: boolean }[]>`
          select public.waitlist_mailed(${id}::uuid, 'invite', ${now.toISOString()}::timestamptz)
            as ok`),
    },
    mailer: apiKey ? resendMailer(apiKey, Deno.env.get('RESEND_API_URL') || RESEND_API_URL) : null,
    hmacSecret: Deno.env.get('WAITLIST_HMAC_SECRET') || null,
    allow: mailAllowFrom(Deno.env.get('WAITLIST_MAIL_ALLOW')),
    now: () => new Date(),
    print: (line) => console.log(line),
    writeFile: (path, text) => Deno.writeTextFile(path, text, { mode: 0o600 }),
    makeTempDir: () => Deno.makeTempDir({ prefix: 'ios-invite-' }),
  });
  await sql.end();
  Deno.exit(code);
}
