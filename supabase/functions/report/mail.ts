// The DSA report mails, in Legal's words (Addendum B): the confirmation of receipt (B.4) and the
// decision to the notifier (B.6a), in German and English, as HTML and plain text, with no links,
// images or tracking. No imports beyond this directory but resend.ts's types:
// scripts/moderation/notify.ts renders the decision mail from here.
import type { Mail } from '../_shared/resend.ts';

export type Locale = 'de' | 'en';
export type Outcome = 'removed' | 'made_invisible' | 'account_suspended' | 'no_change';

export const OUTCOMES: readonly Outcome[] = [
  'removed',
  'made_invisible',
  'account_suspended',
  'no_change',
];

const FROM = '"Snacklist Support" <no-reply@snacklist.app>';
const REPLY_TO = 'support@snacklist.app';
const SIGNATURE = '– Snacklist Support';
const ZONE = 'Europe/Berlin';

const part = (parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes): string =>
  parts.find((p) => p.type === type)?.value ?? '';

/** DE "16.11.2026", EN "16 November 2026", in Berlin. */
export function formatDate(locale: Locale, at: Date): string {
  const p = new Intl.DateTimeFormat(locale === 'de' ? 'de-DE' : 'en-GB', {
    timeZone: ZONE,
    day: locale === 'de' ? '2-digit' : 'numeric',
    month: locale === 'de' ? '2-digit' : 'long',
    year: 'numeric',
  }).formatToParts(at);
  return locale === 'de'
    ? `${part(p, 'day')}.${part(p, 'month')}.${part(p, 'year')}`
    : `${part(p, 'day')} ${part(p, 'month')} ${part(p, 'year')}`;
}

/** DE "16.11.2026, 14:05 Uhr", EN "16 November 2026, 14:05 CET" (CEST in summer). */
export function formatDateTime(locale: Locale, at: Date): string {
  const p = new Intl.DateTimeFormat('en-GB', {
    timeZone: ZONE,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZoneName: 'short',
  }).formatToParts(at);
  const time = `${part(p, 'hour')}:${part(p, 'minute')}`;
  return locale === 'de'
    ? `${formatDate(locale, at)}, ${time} Uhr`
    : `${formatDate(locale, at)}, ${time} ${part(p, 'timeZoneName')}`;
}

const escape = (s: string) =>
  s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');

/** Greeting with the body (as Legal wrote them, one paragraph), then the signature. */
function render(locale: Locale, subject: string, paragraphs: string[]): Mail {
  const html = [
    `<!doctype html><html lang="${locale}"><head><meta charset="utf-8">`,
    `<title>${escape(subject)}</title></head>`,
    '<body style="margin:0;padding:24px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5;color:#1b1f1d">',
    ...paragraphs.map((p) =>
      `<p style="margin:0 0 16px">${escape(p).replaceAll('\n', '<br>')}</p>`
    ),
    '</body></html>',
  ].join('');
  return { from: FROM, replyTo: REPLY_TO, subject, html, text: `${paragraphs.join('\n\n')}\n` };
}

/**
 * Whether [name] may stand in the greeting. Anyone can type any address into the form, so a
 * "name" with a link or a message in it would go out under Snacklist's sender: only letters,
 * spaces, apostrophes, hyphens and an abbreviation's dot ("Dr. Anna", "Anna B.") pass, up to 60.
 */
export const greetable = (name: string): boolean =>
  [...name].length <= 60 && /^(?:[\p{L}\p{M}'’ -]|\.(?= |$))+$/u.test(name);

const greeting = (locale: Locale, name: string | null) => {
  const who = name !== null && greetable(name) ? ` ${name}` : '';
  return locale === 'de' ? `Hallo${who},` : `Hi${who},`;
};

export interface Confirmation {
  locale: Locale;
  name: string | null;
  /** The report's created_at. */
  createdAt: Date;
  ref: string;
}

/** B.4: the confirmation of receipt (Art. 16(4) DSA). */
export function confirmationMail(c: Confirmation): Mail {
  const when = formatDateTime(c.locale, c.createdAt);
  if (c.locale === 'de') {
    return render('de', `Deine Meldung an Snacklist ist eingegangen (${c.ref})`, [
      `${
        greeting('de', c.name)
      } danke für deine Meldung vom ${when} (Nummer ${c.ref}). Wir haben sie erhalten und prüfen ` +
      'sie selbst, ohne automatische Entscheidung. Sobald wir entschieden haben, schreiben wir dir, ' +
      'was wir getan haben und warum. Du musst nichts weiter tun. Wenn du etwas ergänzen willst, ' +
      'antworte einfach auf diese E-Mail.',
      SIGNATURE,
    ]);
  }
  return render('en', `We've received your report to Snacklist (${c.ref})`, [
    `${
      greeting('en', c.name)
    } thanks for your report of ${when} (number ${c.ref}). We've received it and review it ` +
    "ourselves, with no automated decision. Once we've decided, we'll write to tell you what we " +
    "did and why. You don't need to do anything else. To add something, just reply to this " +
    'e-mail.',
    SIGNATURE,
  ]);
}

const DECISIONS: Record<Locale, Record<Outcome, string>> = {
  de: {
    removed: 'wir haben den Inhalt entfernt',
    'made_invisible': 'wir haben den Inhalt unsichtbar gemacht',
    'account_suspended': 'wir haben das Konto gesperrt',
    'no_change': 'wir haben nichts geändert',
  },
  en: {
    removed: 'we removed the content',
    'made_invisible': 'we made the content invisible',
    'account_suspended': 'we suspended the account',
    'no_change': 'we changed nothing',
  },
};

export interface Decision {
  locale: Locale;
  name: string | null;
  /** The report's created_at; the mail names its date only. */
  date: Date;
  ref: string;
  outcome: Outcome;
  /** The decision's ground, in Peter's words. */
  reason: string;
}

/** The ground ends the template's "Grund: …." sentence: no second full stop after its own. */
const sentence = (s: string) => /[.!?]$/.test(s.trim()) ? s.trim() : `${s.trim()}.`;

/** B.6a: the decision to the notifier (Art. 16(5) DSA). */
export function decisionMail(d: Decision): Mail {
  const date = formatDate(d.locale, d.date);
  const decision = DECISIONS[d.locale][d.outcome];
  if (d.locale === 'de') {
    return render('de', `Unsere Entscheidung zu deiner Meldung (${d.ref})`, [
      `${
        greeting('de', d.name)
      } wir haben deine Meldung vom ${date} (${d.ref}) geprüft. Entscheidung: ${decision}. ` +
      `Grund: ${sentence(d.reason)} Die Entscheidung hat ein Mensch getroffen, ohne automatische ` +
      'Mittel. Wenn du nicht einverstanden bist, antworte auf diese E-Mail, dann prüfen wir noch ' +
      'einmal. Du kannst außerdem die Zivilgerichte anrufen oder dich bei der Koordinierungsstelle ' +
      'für digitale Dienste der Bundesnetzagentur beschweren.',
      SIGNATURE,
    ]);
  }
  return render('en', `Our decision on your report (${d.ref})`, [
    `${
      greeting('en', d.name)
    } we've reviewed your report of ${date} (${d.ref}). Decision: ${decision}. ` +
    `Reason: ${sentence(d.reason)} A person made this decision, without automated means. If you ` +
    "disagree, reply to this e-mail and we'll review it again. You can also go to the civil " +
    'courts or complain to the Digital Services Coordinator at the Bundesnetzagentur.',
    SIGNATURE,
  ]);
}
