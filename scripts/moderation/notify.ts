// Mails Peter's decision on a DSA report to the person who reported it (Legal Addendum B.6a), and
// confirmations the report function could not send (Legal N-244; docs/MODERATION.md). Peter runs
// it on his own machine; no agent runs --send.
//
//   deno run -A scripts/moderation/notify.ts --decision 12
//       prints the decision mail as it would go out, the address masked; sends nothing
//   deno run -A scripts/moderation/notify.ts --decision 12 --send [--again]
//       sends it through Resend and records notified_at; --again for a decision already notified
//   deno run -A scripts/moderation/notify.ts --confirmations [--send]
//       lists reports with an address and no confirmation_sent_at, stored over 15 minutes ago
//       (a failed send); --send mails each its confirmation (same key as the function's, so
//       Resend never sends one twice) and records confirmation_sent_at
//
// Env: SUPABASE_DB_URL; for --send also RESEND_API_KEY (RESEND_API_URL optional). It never prints
// an address unmasked, also not when something fails.
import {
  confirmationMail,
  decisionMail,
  type Locale,
  type Outcome,
} from '../../supabase/functions/report/mail.ts';
import {
  type Mailer,
  RESEND_API_URL,
  resendMailer,
} from '../../supabase/functions/_shared/resend.ts';

/** A decision with what its mail needs from the report. */
export interface DecisionRow {
  id: number;
  ref: string;
  locale: Locale;
  name: string | null;
  email: string | null;
  reportedAt: Date;
  outcome: Outcome;
  ground: string;
  notifiedAt: Date | null;
}

/** A report that still owes its confirmation of receipt. */
export interface PendingRow {
  id: string;
  ref: string;
  locale: Locale;
  name: string | null;
  email: string;
  createdAt: Date;
}

/** How long the function's own send and retries may take before a report counts as missed. */
export const CONFIRMATION_GRACE_MS = 15 * 60 * 1000;

/** Reads content_report_decisions with its report; content_report_notified; the unconfirmed. */
export interface NotifyStore {
  decision(id: number): Promise<DecisionRow | null>;
  notified(id: number, now: Date): Promise<boolean>;
  /** Reports with an address, no confirmation_sent_at, stored before [before], oldest first. */
  unconfirmed(before: Date): Promise<PendingRow[]>;
  /** content_report_confirmation_sent */
  confirmationSent(id: string, now: Date): Promise<boolean>;
}

export type Args =
  | { kind: 'decision'; decision: number; send: boolean; again: boolean }
  | { kind: 'confirmations'; send: boolean };

export function parseArgs(argv: string[]): Args | string {
  let decision: number | null = null;
  let send = false;
  let again = false;
  let confirmations = false;
  const args = argv.values();
  for (const arg of args) {
    if (arg === '--send') send = true;
    else if (arg === '--again') again = true;
    else if (arg === '--confirmations') confirmations = true;
    else if (arg === '--decision') {
      const value = args.next().value ?? '';
      decision = /^[1-9][0-9]{0,17}$/.test(value) ? Number(value) : null;
    } else return 'unknown argument';
  }
  if (confirmations) {
    if (decision !== null || again) return '--confirmations takes only --send';
    return { kind: 'confirmations', send };
  }
  if (decision === null) {
    return '--decision <id> or --confirmations is required, like --decision 12';
  }
  if (again && !send) return '--again goes with --send';
  return { kind: 'decision', decision, send, again };
}

/** a***@e***.com: enough to recognise, not to read. */
export function maskEmail(email: string): string {
  const at = email.lastIndexOf('@');
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const dot = domain.lastIndexOf('.');
  const host = dot > 0 ? domain.slice(0, dot) : domain;
  const tld = dot > 0 ? domain.slice(dot) : '';
  return `${local.slice(0, 1)}***@${host.slice(0, 1)}***${tld}`;
}

export interface Deps {
  store: NotifyStore;
  /** Null without RESEND_API_KEY. */
  mailer: Mailer | null;
  now(): Date;
  print(line: string): void;
}

/** The SQLSTATE or error name only: a Postgres detail or a Resend answer may hold an address. */
const reason = (e: unknown) => {
  const code = (e as { code?: unknown })?.code;
  if (typeof code === 'string' && /^[0-9A-Z]{5}$/.test(code)) return code;
  const status = (e as { status?: unknown })?.status;
  if (typeof status === 'number') return `HTTP ${status}`;
  return e instanceof Error && /^[A-Za-z]+$/.test(e.name) ? e.name : 'error';
};

/** Runs the command; returns the exit code. */
export async function run(args: Args, deps: Deps): Promise<number> {
  try {
    return await notify(args, deps);
  } catch (e) {
    deps.print(`notify: failed (${reason(e)})`);
    return 1;
  }
}

async function notify(args: Args, deps: Deps): Promise<number> {
  if (args.kind === 'confirmations') return await confirmations(args.send, deps);
  const d = await deps.store.decision(args.decision);
  if (!d) {
    deps.print(`notify: no decision ${args.decision}`);
    return 1;
  }
  if (!d.email) {
    deps.print(`notify: report ${d.ref} has no e-mail address; there is no one to tell`);
    return 1;
  }
  const mail = decisionMail({
    locale: d.locale,
    name: d.name,
    date: d.reportedAt,
    ref: d.ref,
    outcome: d.outcome,
    reason: d.ground,
  });
  // A rerun after a crash keeps the key, so Resend sends it only once within 24 hours; --again
  // after a send that went through needs a new one, or Resend would drop it.
  const key = `report-decision/${d.id}${d.notifiedAt ? `/${d.notifiedAt.getTime()}` : ''}`;
  deps.print(`To: ${maskEmail(d.email)}`);
  deps.print(`Subject: ${mail.subject}`);
  deps.print(`Idempotency-Key: ${key}`);
  if (d.notifiedAt) deps.print(`Already notified: ${d.notifiedAt.toISOString()}`);
  deps.print('');
  for (const line of mail.text.trimEnd().split('\n')) deps.print(line);
  deps.print('');
  if (!args.send) {
    deps.print(`dry run: nothing sent. To send: --decision ${d.id} --send`);
    return 0;
  }
  if (d.notifiedAt && !args.again) {
    deps.print('notify: refused, this decision was already mailed; --again sends it once more');
    return 1;
  }
  if (!deps.mailer) {
    deps.print('notify: --send needs RESEND_API_KEY');
    return 1;
  }
  await deps.mailer.send(d.email, mail, key);
  await deps.store.notified(d.id, deps.now());
  deps.print(`sent to ${maskEmail(d.email)}; notified_at recorded`);
  return 0;
}

/** Legal N-244: every report with an address gets its confirmation, also after a failed send. */
async function confirmations(send: boolean, deps: Deps): Promise<number> {
  const rows = await deps.store.unconfirmed(
    new Date(deps.now().getTime() - CONFIRMATION_GRACE_MS),
  );
  deps.print(`${rows.length} report(s) with an address still owe their confirmation`);
  for (const r of rows) {
    deps.print(`${r.ref}  ${r.createdAt.toISOString()}  ${maskEmail(r.email)}`);
  }
  if (rows.length === 0) return 0;
  if (!send) {
    deps.print('dry run: nothing sent. To send: --confirmations --send');
    return 0;
  }
  if (!deps.mailer) {
    deps.print('notify: --send needs RESEND_API_KEY');
    return 1;
  }
  let failed = 0;
  for (const r of rows) {
    const mail = confirmationMail({
      locale: r.locale,
      name: r.name,
      createdAt: r.createdAt,
      ref: r.ref,
    });
    try {
      await deps.mailer.send(r.email, mail, `report-confirm/${r.id}`);
      await deps.store.confirmationSent(r.id, deps.now());
      deps.print(`${r.ref}: sent; confirmation_sent_at recorded`);
    } catch (e) {
      failed++;
      deps.print(`${r.ref}: failed (${reason(e)}); run it again later`);
    }
  }
  return failed === 0 ? 0 : 1;
}

if (import.meta.main) {
  const args = parseArgs(Deno.args);
  if (typeof args === 'string') {
    console.error(`notify: ${args}`);
    Deno.exit(2);
  }
  const { default: postgres } = await import('postgres');
  const url = Deno.env.get('SUPABASE_DB_URL');
  if (!url) {
    console.error('notify: SUPABASE_DB_URL is not set');
    Deno.exit(2);
  }
  const sql = postgres(url, { max: 1, prepare: false, onnotice: () => {} });
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const code = await run(args, {
    store: {
      decision: async (id) => {
        const [row] = await sql<DecisionRow[]>`
          select d.id::int as id, r.ref, r.locale, r.reporter_name as name,
                 r.reporter_email as email, r.created_at as "reportedAt", d.outcome, d.ground,
                 d.notified_at as "notifiedAt"
          from public.content_report_decisions d
          join public.content_reports r on r.id = d.report_id
          where d.id = ${id}`;
        return row ?? null;
      },
      notified: async (id, now) => {
        const [row] = await sql<{ ok: boolean }[]>`
          select public.content_report_notified(${id}, ${now.toISOString()}::timestamptz) as ok`;
        return row?.ok ?? false;
      },
      unconfirmed: (before) =>
        sql<PendingRow[]>`
          select r.id, r.ref, r.locale, r.reporter_name as name, r.reporter_email as email,
                 r.created_at as "createdAt"
          from public.content_reports r
          where r.reporter_email is not null and r.confirmation_sent_at is null
            and r.created_at < ${before.toISOString()}::timestamptz
          order by r.created_at`,
      confirmationSent: async (id, now) => {
        const [row] = await sql<{ ok: boolean }[]>`
          select public.content_report_confirmation_sent(${id}::uuid,
            ${now.toISOString()}::timestamptz) as ok`;
        return row?.ok ?? false;
      },
    },
    mailer: apiKey ? resendMailer(apiKey, Deno.env.get('RESEND_API_URL') || RESEND_API_URL) : null,
    now: () => new Date(),
    print: (line) => console.log(line),
  });
  await sql.end();
  Deno.exit(code);
}
