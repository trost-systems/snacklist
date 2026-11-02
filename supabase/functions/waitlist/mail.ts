// The waitlist's mails (docs/WAITLIST.md "Mails"): confirmation, welcome and beta invite, in German
// and English, as HTML and plain text, with no images and no tracking. Texts that still wait for
// Peter's approval sit between ⟦…⟧ markers; refusal() keeps such a mail from going out.
// No imports beyond this directory: scripts/waitlist/invite.ts renders the invite from here.

export type Locale = 'de' | 'en';
export type Platform = 'ios' | 'android';

export interface Mail {
  from: string;
  replyTo: string;
  subject: string;
  html: string;
  text: string;
  /** Extra mail headers: List-Unsubscribe on every mail after the confirmation. */
  headers: Record<string, string>;
}

/** Where the unsubscribe links of one row point. */
export interface Unsubscribe {
  /** The unsubscribe page; the id and signature sit in the fragment. */
  page: string;
  /** RFC 8058 one-click target (POST) for the List-Unsubscribe header. */
  oneClick: string;
}

export const SITE_ORIGIN = 'https://hummlist.com';
const PLAY_TESTING_URL = 'https://play.google.com/apps/testing/com.hummlist.app';

const ORIGINS = [
  /^https:\/\/hummlist\.com$/,
  /^https:\/\/hummlist-site-[a-z0-9-]+-peter-trost\.vercel\.app$/,
  /^http:\/\/127\.0\.0\.1:[0-9]{1,5}$/,
];

/** The site the request came to, for the links in its mails; anything unknown is hummlist.com. */
export function siteOrigin(header: string | null): string {
  return header && ORIGINS.some((o) => o.test(header)) ? header : SITE_ORIGIN;
}

const PATHS = {
  de: { confirm: '/de/warteliste/bestaetigen', unsubscribe: '/de/warteliste/abmelden' },
  en: { confirm: '/en/waitlist/confirm', unsubscribe: '/en/waitlist/unsubscribe' },
};

export function confirmUrl(origin: string, locale: Locale, token: string): string {
  return `${origin}${PATHS[locale].confirm}#t=${token}`;
}

export function unsubscribeLinks(
  origin: string,
  locale: Locale,
  id: string,
  sig: string,
): Unsubscribe {
  return {
    page: `${origin}${PATHS[locale].unsubscribe}#id=${id}&s=${sig}`,
    oneClick: `${origin}/api/waitlist/unsubscribe?id=${id}&s=${sig}&l=${locale}`,
  };
}

// Mail recipients ------------------------------------------------------------------------------

/** WAITLIST_MAIL_ALLOW: unset means Peter's test addresses only, `*` everyone. */
export type MailAllow = 'test' | 'all';

export const mailAllowFrom = (value: string | undefined): MailAllow =>
  value?.trim() === '*' ? 'all' : 'test';

const TEST_ADDRESS = /^hello\+[^@]+@hummlist\.com$/i;

export function recipientAllowed(email: string, allow: MailAllow): boolean {
  return allow === 'all' || TEST_ADDRESS.test(email);
}

export const hasPlaceholder = (mail: Mail): boolean =>
  [mail.subject, mail.html, mail.text].some((s) => s.includes('⟦'));

export interface SendPolicy {
  allow: MailAllow;
  /** WAITLIST_ALLOW_PLACEHOLDERS=1: drafts may go out (to test addresses). */
  allowPlaceholders: boolean;
}

/** Why [mail] must not go to [to], or null when it may. */
export function refusal(
  to: string,
  mail: Mail,
  policy: SendPolicy,
): 'recipient' | 'placeholder' | null {
  if (!recipientAllowed(to, policy.allow)) return 'recipient';
  if (!policy.allowPlaceholders && hasPlaceholder(mail)) return 'placeholder';
  return null;
}

// Rendering ------------------------------------------------------------------------------------

/** A paragraph: text runs and links; '\n' breaks the line. */
type Segment = string | { text: string; url: string };
type Paragraph = Segment[];

const SENDER = {
  de: '"Peter von Hummlist" <hello@hummlist.com>',
  en: '"Peter from Hummlist" <hello@hummlist.com>',
};
const REPLY_TO = 'hello@hummlist.com';

const escape = (s: string) =>
  s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const htmlParagraph = (p: Paragraph, style: string) =>
  `<p style="${style}">${
    p.map((s) =>
      typeof s === 'string'
        ? escape(s).replaceAll('\n', '<br>')
        : `<a href="${escape(s.url)}" style="color:#1a6b3c">${escape(s.text)}</a>`
    ).join('')
  }</p>`;

// A labeled link becomes "Abmelden <url>": the brackets end the URL for the reader's mail
// client, which would otherwise take the footer's following ":" into the link.
const textParagraph = (p: Paragraph) =>
  p.map((s) => typeof s === 'string' ? s : s.text === s.url ? s.url : `${s.text} <${s.url}>`)
    .join('');

function render(
  locale: Locale,
  subject: string,
  preheader: string,
  body: Paragraph[],
  footer: Paragraph[],
  headers: Record<string, string> = {},
): Mail {
  const html = [
    '<!doctype html>',
    `<html lang="${locale}"><head><meta charset="utf-8">`,
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${escape(subject)}</title></head>`,
    '<body style="margin:0;padding:0;background:#ffffff;color:#1f2421;' +
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif\">",
    `<div style="display:none;max-height:0;overflow:hidden">${escape(preheader)}</div>`,
    '<div style="max-width:560px;margin:0 auto;padding:24px 20px">',
    ...body.map((p) => htmlParagraph(p, 'margin:0 0 16px;font-size:16px;line-height:1.5')),
    '<hr style="border:none;border-top:1px solid #dde3df;margin:24px 0">',
    ...footer.map((p) =>
      htmlParagraph(p, 'margin:0 0 12px;font-size:12px;line-height:1.5;color:#5b645f')
    ),
    '</div></body></html>',
  ].join('\n');
  const text = [...body.map(textParagraph), '--', ...footer.map(textParagraph)].join('\n\n') +
    '\n';
  return { from: SENDER[locale], replyTo: REPLY_TO, subject, html, text, headers };
}

/** Text between ⟦marker⟧ and ⟦/marker⟧ waits for approval; deleting both lines approves it. */
const pending = (marker: string, paragraphs: Paragraph[]): Paragraph[] => [
  [`⟦${marker}⟧`],
  ...paragraphs,
  [`⟦/${marker}⟧`],
];

const IMPRINT = {
  de: [
    'Hummlist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Deutschland · ' +
    'support@hummlist.com\nImpressum: ',
    { text: 'https://hummlist.com/impressum', url: 'https://hummlist.com/impressum' },
    ' · Datenschutz: ',
    { text: 'https://hummlist.com/datenschutz', url: 'https://hummlist.com/datenschutz' },
  ],
  en: [
    'Hummlist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Germany · ' +
    'support@hummlist.com\nImprint: ',
    { text: 'https://hummlist.com/en/imprint', url: 'https://hummlist.com/en/imprint' },
    ' · Privacy: ',
    { text: 'https://hummlist.com/en/privacy', url: 'https://hummlist.com/en/privacy' },
  ],
} satisfies Record<Locale, Paragraph>;

/** Footer (a), confirmation mail only (Legal handoff §2.6). */
function footerA(locale: Locale, unsubscribe: string): Paragraph[] {
  return pending('LEGAL FOOTER', [
    locale === 'de'
      ? [
        'Du bekommst diese E-Mail, weil diese Adresse auf hummlist.com für die Warteliste ' +
        'eingetragen wurde. ',
        { text: 'Eintrag sofort löschen', url: unsubscribe },
      ]
      : [
        "You're getting this email because this address was signed up for the waitlist on " +
        'hummlist.com. ',
        { text: 'Delete this sign-up now', url: unsubscribe },
      ],
    IMPRINT[locale],
  ]);
}

/** Footer (b): welcome and invite mails (and the launch mail, not built yet). */
function footerB(locale: Locale, unsubscribe: string): Paragraph[] {
  return pending('LEGAL FOOTER', [
    locale === 'de'
      ? [
        'Du bekommst diese E-Mail, weil du dich auf hummlist.com für die Warteliste der ' +
        'Hummlist-Beta eingetragen und deine Adresse bestätigt hast. Keine Mails mehr? ',
        { text: 'Abmelden', url: unsubscribe },
        ': ein Klick genügt, ohne Anmeldung. Oder schreib an support@hummlist.com. Dafür ' +
        'entstehen dir nur die Übermittlungskosten nach den Basistarifen. Du kannst deine ' +
        'Einwilligung jederzeit widerrufen und der Nutzung deiner Adresse für diese E-Mails ' +
        'jederzeit widersprechen (Art. 21 DSGVO).',
      ]
      : [
        "You're getting this email because you signed up for the Hummlist beta waitlist on " +
        'hummlist.com and confirmed your address. No more emails? ',
        { text: 'Unsubscribe', url: unsubscribe },
        ': one click, no sign-in. Or write to support@hummlist.com. This costs you nothing ' +
        'beyond your normal connection charges. You can withdraw your consent and object to ' +
        'the use of your address for these emails at any time (Art. 21 GDPR).',
      ],
    IMPRINT[locale],
  ]);
}

const oneClickHeaders = (u: Unsubscribe) => ({
  'List-Unsubscribe': `<${u.oneClick}>`,
  'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
});

/** The double opt-in mail (Legal handoff §2.5): no logo, no welcome, no promotion. */
export function confirmationMail(
  locale: Locale,
  m: { confirmUrl: string; unsubscribe: Unsubscribe; launchNews: boolean },
): Mail {
  if (locale === 'de') {
    return render(
      'de',
      'Bitte bestätige deine E-Mail für Hummlist',
      'Ein Tipp, dann stehst du auf der Warteliste für die Beta.',
      pending('LEGAL W2', [
        ['Hi,'],
        [
          'diese Adresse wurde auf hummlist.com für die Warteliste der Hummlist-Beta ' +
          'eingetragen. Bitte bestätige kurz, dass das deine Adresse ist:',
        ],
        [{ text: 'E-Mail bestätigen', url: m.confirmUrl }],
        [
          'Der Link gilt 48 Stunden. Danach stehst du auf der Liste und bekommst die Einladung ' +
          'zur Beta.' +
          (m.launchNews
            ? '\nAußerdem schreiben wir dir einmal, wenn die App offiziell startet.'
            : ''),
        ],
        [
          'Du warst das nicht? Dann ignorier diese Mail einfach. Ohne Bestätigung tragen wir ' +
          'dich nicht ein und löschen die Adresse nach 7 Tagen.',
        ],
        ['Peter'],
      ]),
      footerA('de', m.unsubscribe.page),
    );
  }
  return render(
    'en',
    'Please confirm your email for Hummlist',
    "One tap and you're on the beta waitlist.",
    pending('LEGAL W2', [
      ['Hi,'],
      [
        'This address was signed up on hummlist.com for the Hummlist beta waitlist. Please ' +
        "confirm that it's yours:",
      ],
      [{ text: 'Confirm email', url: m.confirmUrl }],
      [
        "The link works for 48 hours. After that you're on the list and will get the beta " +
        'invite.' +
        (m.launchNews ? "\nWe'll also email you once when the app officially launches." : ''),
      ],
      [
        "Wasn't you? Just ignore this email. Without confirmation we won't add you, and we " +
        'delete the address after 7 days.',
      ],
      ['Peter'],
    ]),
    footerA('en', m.unsubscribe.page),
  );
}

/** After confirming. A neutral draft until Hummlist Launch's text (5b) replaces it. */
export function welcomeMail(
  locale: Locale,
  m: { unsubscribe: Unsubscribe; launchNews: boolean },
): Mail {
  if (locale === 'de') {
    return render(
      'de',
      'Du stehst auf der Warteliste für Hummlist',
      'Deine Adresse ist bestätigt.',
      pending('LAUNCH COPY', [
        ['Hi,'],
        [
          'deine Adresse ist bestätigt: Du stehst auf der Warteliste für die Hummlist-Beta. ' +
          'Wenn die Beta startet, bekommst du von uns die Einladung.' +
          (m.launchNews
            ? '\nSonst schreiben wir dir nur noch einmal, wenn die App offiziell startet.'
            : ''),
        ],
        ['Peter'],
      ]),
      footerB('de', m.unsubscribe.page),
      oneClickHeaders(m.unsubscribe),
    );
  }
  return render(
    'en',
    "You're on the Hummlist waitlist",
    'Your address is confirmed.',
    pending('LAUNCH COPY', [
      ['Hi,'],
      [
        "Your address is confirmed: you're on the waitlist for the Hummlist beta. When the " +
        "beta starts, we'll send you the invite." +
        (m.launchNews ? "\nOtherwise we'll only email you once more, when the app launches." : ''),
      ],
      ['Peter'],
    ]),
    footerB('en', m.unsubscribe.page),
    oneClickHeaders(m.unsubscribe),
  );
}

/** The beta invite, sent by scripts/waitlist/invite.ts. A neutral draft until Launch's text. */
export function inviteMail(
  locale: Locale,
  m: { platform: Platform; unsubscribe: Unsubscribe },
): Mail {
  const platformLine: Record<Locale, Record<Platform, Paragraph>> = {
    de: {
      ios: [
        'Für dein iPhone kommt die Einladung von Apple: TestFlight schickt dir eine eigene ' +
        'E-Mail an diese Adresse. Installier zuerst die App TestFlight aus dem App Store und ' +
        'öffne dann die Einladung von Apple auf deinem iPhone.',
      ],
      android: [
        'Für dein Android-Handy haben wir diese Adresse bei Google Play als Tester eingetragen. ' +
        'Öffne auf dem Handy, angemeldet mit dem Google-Konto dieser Adresse, diesen Link und ' +
        'tippe auf „Tester werden“: ',
        { text: PLAY_TESTING_URL, url: PLAY_TESTING_URL },
      ],
    },
    en: {
      ios: [
        'For your iPhone the invite comes from Apple: TestFlight sends you its own email at ' +
        'this address. Install the TestFlight app from the App Store first, then open the ' +
        'invite from Apple on your iPhone.',
      ],
      android: [
        "For your Android phone we've added this address as a tester on Google Play. On your " +
        'phone, signed in with the Google account of this address, open this link and tap ' +
        '"Become a tester": ',
        { text: PLAY_TESTING_URL, url: PLAY_TESTING_URL },
      ],
    },
  };
  const de = locale === 'de';
  return render(
    locale,
    de ? 'Deine Einladung zur Hummlist-Beta' : 'Your invite to the Hummlist beta',
    de ? 'Die Beta ist offen.' : 'The beta is open.',
    pending('LAUNCH COPY', [
      ['Hi,'],
      [
        de
          ? 'die Hummlist-Beta ist offen, und du bist dabei.'
          : "The Hummlist beta is open, and you're in.",
      ],
      platformLine[locale][m.platform],
      ['Peter'],
    ]),
    footerB(locale, m.unsubscribe.page),
    oneClickHeaders(m.unsubscribe),
  );
}
