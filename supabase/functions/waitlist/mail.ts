// The waitlist's mails (docs/WAITLIST.md "Mails"): confirmation, welcome and beta invite, in German
// and English, as HTML and plain text, with no images and no tracking. No template holds a ⟦…⟧
// draft marker any more; refusal() still keeps a mail with one from going out.
// No imports beyond this directory: scripts/waitlist/ renders the invites from here.

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

export const SITE_ORIGIN = 'https://snacklist.app';
const PLAY_TESTING_URL = 'https://play.google.com/apps/testing/com.snacklist.app';

const ORIGINS = [
  /^https:\/\/hummlist\.com$/,
  /^https:\/\/snacklist\.app$/,
  /^https:\/\/hummlist-site-[a-z0-9-]+-peter-trost\.vercel\.app$/,
  /^http:\/\/127\.0\.0\.1:[0-9]{1,5}$/,
];

/** The site the request came to, for the links in its mails; anything unknown is snacklist.app. */
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

const TEST_ADDRESSES = [
  /^hello\+[^@]+@hummlist\.com$/i,
  /^test(?:\+[^@]+)?@snacklist\.app$/i,
];

export function recipientAllowed(email: string, allow: MailAllow): boolean {
  return allow === 'all' || TEST_ADDRESSES.some((re) => re.test(email));
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

const SENDER = '"Peter · Snacklist" <hello@snacklist.app>';
const IOS_SENDER = {
  de: '"Peter von Snacklist" <hello@snacklist.app>',
  en: '"Peter from Snacklist" <hello@snacklist.app>',
};
const REPLY_TO = 'hello@snacklist.app';

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
  from: string = SENDER,
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
  return { from, replyTo: REPLY_TO, subject, html, text, headers };
}

const IMPRINT = {
  de: [
    'Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Deutschland · ' +
    'support@snacklist.app\nImpressum: ',
    { text: 'https://snacklist.app/impressum', url: 'https://snacklist.app/impressum' },
    ' · Datenschutz: ',
    { text: 'https://snacklist.app/datenschutz', url: 'https://snacklist.app/datenschutz' },
  ],
  en: [
    'Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Germany · ' +
    'support@snacklist.app\nImprint: ',
    { text: 'https://snacklist.app/en/imprint', url: 'https://snacklist.app/en/imprint' },
    ' · Privacy: ',
    { text: 'https://snacklist.app/en/privacy', url: 'https://snacklist.app/en/privacy' },
  ],
} satisfies Record<Locale, Paragraph>;

/** Footer (a), confirmation mail only (Legal handoff §2.6). */
function footerA(locale: Locale, unsubscribe: string): Paragraph[] {
  return [
    locale === 'de'
      ? [
        'Du bekommst diese E-Mail, weil diese Adresse auf snacklist.app für die Warteliste ' +
        'eingetragen wurde. ',
        { text: 'Eintrag sofort löschen', url: unsubscribe },
      ]
      : [
        "You're getting this email because this address was signed up for the waitlist on " +
        'snacklist.app. ',
        { text: 'Delete this sign-up now', url: unsubscribe },
      ],
    IMPRINT[locale],
  ];
}

/** Footer (b): welcome and invite mails (and the launch mail, not built yet). */
function footerB(locale: Locale, unsubscribe: string): Paragraph[] {
  return [
    locale === 'de'
      ? [
        'Du bekommst diese E-Mail, weil du dich auf snacklist.app für die Warteliste der ' +
        'Snacklist-Beta eingetragen und deine Adresse bestätigt hast. Keine Mails mehr? ',
        { text: 'Abmelden', url: unsubscribe },
        ': ein Klick genügt, ohne Anmeldung. Oder schreib an support@snacklist.app. Dafür ' +
        'entstehen dir nur die Übermittlungskosten nach den Basistarifen. Du kannst deine ' +
        'Einwilligung jederzeit widerrufen und der Nutzung deiner Adresse für diese E-Mails ' +
        'jederzeit widersprechen (Art. 21 DSGVO).',
      ]
      : [
        "You're getting this email because you signed up for the Snacklist beta waitlist on " +
        'snacklist.app and confirmed your address. No more emails? ',
        { text: 'Unsubscribe', url: unsubscribe },
        ': one click, no sign-in. Or write to support@snacklist.app. This costs you nothing ' +
        'beyond your normal connection charges. You can withdraw your consent and object to ' +
        'the use of your address for these emails at any time (Art. 21 GDPR).',
      ],
    IMPRINT[locale],
  ];
}

/** The iOS invite's footer: Legal's N-261 (batch of 2026-11-17, Q17), word for word. */
function footerInvite(locale: Locale, unsubscribe: string): Paragraph[] {
  const link = (url: string) => ({ text: url, url });
  return locale === 'de'
    ? [
      [
        'Du bekommst diese E-Mail, weil du dich auf snacklist.app für die Warteliste der ' +
        'Snacklist-Beta eingetragen und deine Adresse bestätigt hast. Keine E-Mails mehr von uns? ',
        { text: 'Abmelden', url: unsubscribe },
        ' – ein Klick genügt, ohne Anmeldung, und wir löschen deine Eintragung. Damit widerrufst ' +
        'du deine Einwilligung und widersprichst der Nutzung deiner Adresse für diese E-Mails ' +
        '(Art. 21 DSGVO). Du kannst auch einfach auf diese E-Mail antworten oder an ' +
        'support@snacklist.app schreiben; Antworten liest Peter Trost selbst.',
      ],
      [
        'Absender: Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · ' +
        'Deutschland\nImpressum: ',
        link('https://snacklist.app/impressum'),
        ' · Datenschutz: ',
        link('https://snacklist.app/datenschutz'),
        ' (Abschnitt 2a)',
      ],
    ]
    : [
      [
        "You're getting this email because you signed up for the Snacklist beta waitlist on " +
        'snacklist.app and confirmed your address. No more emails from us? ',
        { text: 'Unsubscribe', url: unsubscribe },
        ' – one click, no sign-in, and we delete your sign-up. This withdraws your consent and ' +
        'objects to the use of your address for these emails (Art. 21 GDPR). You can also just ' +
        'reply to this email or write to support@snacklist.app; Peter Trost reads replies himself.',
      ],
      [
        'Sender: Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · ' +
        'Germany\nImprint: ',
        link('https://snacklist.app/en/imprint'),
        ' · Privacy: ',
        link('https://snacklist.app/en/privacy'),
        ' (section 2a)',
      ],
    ];
}

const oneClickHeaders = (u: Unsubscribe) => ({
  'List-Unsubscribe': `<${u.oneClick}>`,
  'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
});

/**
 * The double opt-in mail (Legal handoff §2.5, text doi-mail-<locale>-v2 of 2026-11-04): no logo,
 * no welcome, no promotion, and no launch news, which only the confirmation page asks for.
 */
export function confirmationMail(
  locale: Locale,
  m: { confirmUrl: string; unsubscribe: Unsubscribe },
): Mail {
  if (locale === 'de') {
    return render(
      'de',
      'Bitte bestätige deine E-Mail für Snacklist',
      'Ein Tipp, dann stehst du auf der Warteliste für die Beta.',
      [
        ['Hi,'],
        [
          'diese Adresse wurde auf snacklist.app für die Warteliste der Snacklist-Beta ' +
          'eingetragen, von dir selbst oder zum Beispiel von einem KI-Assistenten für dich. ' +
          'Bitte bestätige kurz, dass das deine Adresse ist:',
        ],
        [{ text: 'E-Mail bestätigen', url: m.confirmUrl }],
        [
          'Der Link gilt 48 Stunden. Sobald du auf der Seite dahinter bestätigt hast, stehst ' +
          'du auf der Liste. Wir laden jede Woche neue Tester:innen ein, deine Einladung kommt ' +
          'per E-Mail.',
        ],
        [
          'Du warst das nicht? Dann ignorier diese Mail einfach. Ohne Bestätigung tragen wir ' +
          'dich nicht ein und löschen die Adresse nach 7 Tagen.',
        ],
        ['Peter'],
      ],
      footerA('de', m.unsubscribe.page),
    );
  }
  return render(
    'en',
    'Please confirm your email for Snacklist',
    "One tap and you're on the beta waitlist.",
    [
      ['Hi,'],
      [
        'This address was signed up on snacklist.app for the Snacklist beta waitlist, by you or, ' +
        "for example, by an AI assistant for you. Please confirm that it's yours:",
      ],
      [{ text: 'Confirm email', url: m.confirmUrl }],
      [
        "The link works for 48 hours. Once you've confirmed on the page it opens, you're on the " +
        'list. We invite new testers every week; your invite will come by email.',
      ],
      [
        "Wasn't you? Just ignore this email. Without confirmation we won't add you, and we " +
        'delete the address after 7 days.',
      ],
      ['Peter'],
    ],
    footerA('en', m.unsubscribe.page),
  );
}

/** After confirming; the launch sentence confirms the box ticked on the confirmation page. */
export function welcomeMail(
  locale: Locale,
  m: { unsubscribe: Unsubscribe; launchNews: boolean },
): Mail {
  if (locale === 'de') {
    return render(
      'de',
      'Du stehst auf der Warteliste für Snacklist',
      'Deine Adresse ist bestätigt.',
      [
        ['Hi,'],
        [
          'deine Adresse ist bestätigt: Du stehst auf der Warteliste für die Snacklist-Beta. ' +
          'Wenn die Beta startet, bekommst du von uns die Einladung.' +
          (m.launchNews
            ? '\nSonst schreiben wir dir nur noch einmal, wenn die App offiziell startet.'
            : ''),
        ],
        ['Peter'],
      ],
      footerB('de', m.unsubscribe.page),
      oneClickHeaders(m.unsubscribe),
    );
  }
  return render(
    'en',
    "You're on the Snacklist waitlist",
    'Your address is confirmed.',
    [
      ['Hi,'],
      [
        "Your address is confirmed: you're on the waitlist for the Snacklist beta. When the " +
        "beta starts, we'll send you the invite." +
        (m.launchNews ? "\nOtherwise we'll only email you once more, when the app launches." : ''),
      ],
      ['Peter'],
    ],
    footerB('en', m.unsubscribe.page),
    oneClickHeaders(m.unsubscribe),
  );
}

/** PM's iOS invite draft of 2026-11-16, word for word: greeting, three steps, store link. */
function iosInviteBody(locale: Locale): { preheader: string; body: Paragraph[] } {
  const testflight = 'https://apps.apple.com/app/testflight/id899247664';
  const link = { text: testflight, url: testflight };
  return locale === 'de'
    ? {
      preheader:
        'Deine Einladung zur Beta ist da. Den Zugang über TestFlight schickt dir Apple in einer ' +
        'eigenen Mail.',
      body: [
        ['Hallo,'],
        [
          'du hast dich auf snacklist.app für die Warteliste eingetragen. Jetzt bist du bei ' +
          'der Beta dabei.',
        ],
        [
          'Ich bin Peter und baue Snacklist, eine Einkaufsliste für den ganzen Haushalt. Die ' +
          'gemeinsame Liste ist bei allen sofort aktuell, und es gibt keine Werbung.',
        ],
        [
          'Auf dem iPhone testest du über TestFlight, Apples App für Testversionen. Die ' +
          'Einladung dazu schickt dir Apple in einer eigenen Mail an diese Adresse.',
        ],
        ['So kommst du rein:'],
        ['1. TestFlight laden\nLad dir „TestFlight“ aus dem App Store.'],
        [
          '2. Apples Mail öffnen\nÖffne die Einladungsmail von TestFlight auf deinem iPhone und ' +
          'tipp auf den Knopf darin. Dann installierst du Snacklist über TestFlight.',
        ],
        [
          "3. Loslegen\nÖffne Snacklist und tipp auf „Los geht's“. Die App fragt dich, mit wem " +
          'du einkaufst, und richtet den Haushalt mit dir ein. Am Ende legst du dein Konto an. ' +
          'Wer mit dir einkauft, braucht für die Beta eine eigene Einladung. Am einfachsten ' +
          'trägt sich die Person selbst auf snacklist.app in die Warteliste ein. Sobald ' +
          'Snacklist bei ihr installiert ist, kann sie deinem Haushalt beitreten.',
        ],
        ['TestFlight im App Store: ', link],
        [
          'Keine Mail von Apple da? Schau auch im Spam-Ordner nach. Ist diese Adresse nicht die ' +
          'E-Mail deiner Apple-ID? Dann trag dich auf snacklist.app einfach noch mal mit der ' +
          'richtigen Adresse ein.',
        ],
        [
          'Was dir auffällt, gut oder schlecht, kannst du direkt in der App schicken: Mehr › ' +
          '„Feedback senden“. Jede Rückmeldung hilft.',
        ],
        ['Viel Spaß beim Testen,\nPeter'],
      ],
    }
    : {
      preheader:
        'Your beta invite is here. Apple sends your TestFlight access in a separate email.',
      body: [
        ['Hi,'],
        ["You signed up for the waitlist on snacklist.app. You're now in the beta."],
        [
          "I'm Peter, and I'm building Snacklist, a grocery list for your whole household. The " +
          'shared list is up to date for everyone right away, and there are no ads.',
        ],
        [
          "On iPhone, you test through TestFlight, Apple's app for test versions. Apple sends " +
          'you the invite in a separate email to this address.',
        ],
        ["Here's how to get in:"],
        ['1. Get TestFlight\nDownload "TestFlight" from the App Store.'],
        [
          "2. Open Apple's email\nOpen the TestFlight invite email on your iPhone and tap the " +
          'button in it. Then install Snacklist in TestFlight.',
        ],
        [
          '3. Get started\nOpen Snacklist and tap "Get started". The app asks who you shop with ' +
          'and sets up the household with you. At the end you create your account. Anyone who ' +
          'shops with you needs their own beta invite. The easiest way is for them to join the ' +
          'waitlist on snacklist.app/en themselves. Once Snacklist is installed on their phone, ' +
          'they can join your household.',
        ],
        ['TestFlight on the App Store: ', link],
        [
          "No email from Apple? Check your spam folder too. If this address isn't the email of " +
          'your Apple ID, just sign up again on snacklist.app/en with the right one.',
        ],
        [
          'Anything you notice, good or bad, you can send right in the app: More › ' +
          '"Send feedback". Every bit helps.',
        ],
        ['Have fun testing,\nPeter'],
      ],
    };
}

/** The beta invite: iOS from scripts/waitlist/ios-invite.ts, Android from invite.ts. */
export function inviteMail(
  locale: Locale,
  m: { platform: Platform; unsubscribe: Unsubscribe },
): Mail {
  if (m.platform === 'ios') {
    const { preheader, body } = iosInviteBody(locale);
    return render(
      locale,
      locale === 'de' ? 'Deine Einladung zur Snacklist-Beta' : 'Your invite to the Snacklist beta',
      preheader,
      body,
      footerInvite(locale, m.unsubscribe.page),
      oneClickHeaders(m.unsubscribe),
      IOS_SENDER[locale],
    );
  }
  const androidLine: Record<Locale, Paragraph> = {
    de: [
      'Für dein Android-Handy haben wir diese Adresse bei Google Play als Tester eingetragen. ' +
      'Öffne auf dem Handy, angemeldet mit dem Google-Konto dieser Adresse, diesen Link und ' +
      'tippe auf „Tester werden“: ',
      { text: PLAY_TESTING_URL, url: PLAY_TESTING_URL },
    ],
    en: [
      "For your Android phone we've added this address as a tester on Google Play. On your " +
      'phone, signed in with the Google account of this address, open this link and tap ' +
      '"Become a tester": ',
      { text: PLAY_TESTING_URL, url: PLAY_TESTING_URL },
    ],
  };
  const de = locale === 'de';
  return render(
    locale,
    de ? 'Deine Einladung zur Snacklist-Beta' : 'Your invite to the Snacklist beta',
    de ? 'Die Beta ist offen.' : 'The beta is open.',
    [
      ['Hi,'],
      [
        de
          ? 'die Snacklist-Beta ist offen, und du bist dabei.'
          : "The Snacklist beta is open, and you're in.",
      ],
      androidLine[locale],
      ['Peter'],
    ],
    footerB(locale, m.unsubscribe.page),
    oneClickHeaders(m.unsubscribe),
  );
}
