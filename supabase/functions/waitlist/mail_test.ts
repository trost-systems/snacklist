import { assert, assertEquals, assertExists, assertRejects } from '@std/assert';
import {
  confirmationMail,
  confirmUrl,
  inviteMail,
  type Mail,
  mailAllowFrom,
  recipientAllowed,
  refusal,
  siteOrigin,
  unsubscribeLinks,
  welcomeMail,
} from './mail.ts';
import { MailError, resendMailer } from '../_shared/resend.ts';

const ID = '3f2a8c1e-0b6d-4e7f-9a1b-2c3d4e5f6a7b';
const SIG = 'ab'.repeat(32);
const TOKEN = 'A'.repeat(43);
const unsubscribe = unsubscribeLinks('https://snacklist.app', 'de', ID, SIG);
const unsubscribeEn = unsubscribeLinks('https://snacklist.app', 'en', ID, SIG);
const SITE = 'https://snacklist.app';

const assertNoImagesOrTracking = (mail: Mail) => {
  const glued = mail.text.match(/https?:\/\/[^\s<>]*[.,:;)](?=\s|$)/);
  assert(!glued, `plain text: punctuation glued to a URL: ${glued?.[0]}`);
  assert(!/<img|<script|<link|url\(/i.test(mail.html), 'no images, scripts or remote styles');
  const hrefs = [...mail.html.matchAll(/href="([^"]+)"/g)].map(([, href]) => {
    assertExists(href);
    return href.replaceAll('&amp;', '&');
  });
  for (const href of hrefs) {
    assert(
      href.startsWith('https://snacklist.app/') ||
        href.startsWith('https://play.google.com/apps/testing/') ||
        href === 'https://apps.apple.com/app/testflight/id899247664',
      `a direct link, no redirect: ${href}`,
    );
  }
};

Deno.test('links: confirm and unsubscribe values sit in the fragment; one-click is the POST endpoint', () => {
  assertEquals(
    confirmUrl('https://snacklist.app', 'de', TOKEN),
    `https://snacklist.app/de/warteliste/bestaetigen#t=${TOKEN}`,
  );
  assertEquals(
    confirmUrl('https://snacklist.app', 'en', TOKEN),
    `https://snacklist.app/en/waitlist/confirm#t=${TOKEN}`,
  );
  assertEquals(unsubscribe, {
    page: `https://snacklist.app/de/warteliste/abmelden#id=${ID}&s=${SIG}`,
    oneClick: `https://snacklist.app/api/waitlist/unsubscribe?id=${ID}&s=${SIG}&l=de`,
  });
  assertEquals(
    unsubscribeEn.page,
    `https://snacklist.app/en/waitlist/unsubscribe#id=${ID}&s=${SIG}`,
  );
});

Deno.test('siteOrigin accepts hummlist.com, snacklist.app, previews and a local site, nothing else', () => {
  for (
    const ok of [
      'https://hummlist.com',
      'https://snacklist.app',
      'https://hummlist-site-git-job-82-waitlist-peter-trost.vercel.app',
      'https://hummlist-site-abc123-peter-trost.vercel.app',
      'http://127.0.0.1:4173',
    ]
  ) assertEquals(siteOrigin(ok), ok);
  for (
    const bad of [
      null,
      '',
      'https://www.hummlist.com',
      'http://hummlist.com',
      'https://hummlist.com/',
      'https://hummlist.com.evil.example',
      'https://evil-hummlist-site-x-peter-trost.vercel.app',
      'https://hummlist-site-x-peter-trost.vercel.app.evil.example',
      'http://localhost:4173',
      'https://127.0.0.1:4173',
    ]
  ) assertEquals(siteOrigin(bad), 'https://snacklist.app', String(bad));
});

Deno.test('AC10: the German confirmation mail is doi-mail-de-v2 (M-1) with footer (a), no launch line', () => {
  const mail = confirmationMail('de', {
    confirmUrl: confirmUrl('https://snacklist.app', 'de', TOKEN),
    unsubscribe,
  });
  assertEquals(mail.from, '"Peter · Snacklist" <hello@snacklist.app>');
  assertEquals(mail.replyTo, 'hello@snacklist.app');
  assertEquals(mail.subject, 'Bitte bestätige deine E-Mail für Snacklist');
  assertEquals(mail.headers, {});
  assert(
    mail.html.includes('Ein Tipp, dann stehst du auf der Warteliste für die Beta.'),
    'preheader',
  );
  assert(mail.html.startsWith('<!doctype html>') && mail.html.includes('lang="de"'));
  assertEquals(
    mail.text,
    [
      'Hi,',
      'diese Adresse wurde auf snacklist.app für die Warteliste der Snacklist-Beta eingetragen, von dir selbst oder zum Beispiel von einem KI-Assistenten für dich. Bitte bestätige kurz, dass das deine Adresse ist:',
      `E-Mail bestätigen <https://snacklist.app/de/warteliste/bestaetigen#t=${TOKEN}>`,
      'Der Link gilt 48 Stunden. Sobald du auf der Seite dahinter bestätigt hast, stehst du auf der Liste. Wir laden jede Woche neue Tester:innen ein, deine Einladung kommt per E-Mail.',
      'Du warst das nicht? Dann ignorier diese Mail einfach. Ohne Bestätigung tragen wir dich nicht ein und löschen die Adresse nach 7 Tagen.',
      'Peter',
      '--',
      'Du bekommst diese E-Mail, weil diese Adresse auf snacklist.app für die Warteliste eingetragen wurde. ' +
      `Eintrag sofort löschen <${unsubscribe.page}>`,
      'Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Deutschland · support@snacklist.app\n' +
      'Impressum: https://snacklist.app/impressum · Datenschutz: https://snacklist.app/datenschutz',
    ].join('\n\n') + '\n',
  );
  assert(
    mail.html.includes(`<a href="${unsubscribe.page.replace('&', '&amp;')}"`),
    'the delete link in HTML',
  );
  assert(mail.html.includes('>Eintrag sofort löschen</a>'));
  assert(mail.html.includes('Tester:innen ein, deine Einladung kommt per E-Mail.'));
  assert(!mail.html.includes('offiziell startet'), 'no launch line in HTML either');
  assertNoImagesOrTracking(mail);
});

Deno.test('AC10: the English confirmation mail is doi-mail-en-v2 (M-2) with footer (a), no launch line', () => {
  const mail = confirmationMail('en', {
    confirmUrl: confirmUrl('https://snacklist.app', 'en', TOKEN),
    unsubscribe: unsubscribeEn,
  });
  assertEquals(mail.from, '"Peter · Snacklist" <hello@snacklist.app>');
  assertEquals(mail.subject, 'Please confirm your email for Snacklist');
  assert(mail.html.includes("One tap and you're on the beta waitlist."), 'preheader');
  assertEquals(
    mail.text,
    [
      'Hi,',
      "This address was signed up on snacklist.app for the Snacklist beta waitlist, by you or, for example, by an AI assistant for you. Please confirm that it's yours:",
      `Confirm email <https://snacklist.app/en/waitlist/confirm#t=${TOKEN}>`,
      "The link works for 48 hours. Once you've confirmed on the page it opens, you're on the list. We invite new testers every week; your invite will come by email.",
      "Wasn't you? Just ignore this email. Without confirmation we won't add you, and we delete the address after 7 days.",
      'Peter',
      '--',
      "You're getting this email because this address was signed up for the waitlist on snacklist.app. " +
      `Delete this sign-up now <${unsubscribeEn.page}>`,
      'Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Germany · support@snacklist.app\n' +
      'Imprint: https://snacklist.app/en/imprint · Privacy: https://snacklist.app/en/privacy',
    ].join('\n\n') + '\n',
  );
  assert(!mail.html.includes('officially launches'), 'no launch line');
  assertNoImagesOrTracking(mail);
});

Deno.test('no template carries a ⟦…⟧ marker: every mail passes the placeholder guard', () => {
  const mails = (['de', 'en'] as const).flatMap((locale) => {
    const links = locale === 'de' ? unsubscribe : unsubscribeEn;
    return [
      confirmationMail(locale, { confirmUrl: confirmUrl(SITE, locale, TOKEN), unsubscribe: links }),
      welcomeMail(locale, { unsubscribe: links, launchNews: false }),
      welcomeMail(locale, { unsubscribe: links, launchNews: true }),
      inviteMail(locale, { platform: 'ios', unsubscribe: links }),
      inviteMail(locale, { platform: 'android', unsubscribe: links }),
    ];
  });
  for (const mail of mails) {
    for (const part of [mail.subject, mail.html, mail.text, ...Object.values(mail.headers)]) {
      assert(!part.includes('⟦') && !part.includes('⟧'), `${mail.subject}: no marker`);
    }
    assertEquals(
      refusal('test+x@snacklist.app', mail, { allow: 'test', allowPlaceholders: false }),
      null,
    );
  }
});

Deno.test('the welcome mail: footer (b), one-click unsubscribe, the launch sentence only when ticked', () => {
  for (const locale of ['de', 'en'] as const) {
    const links = locale === 'de' ? unsubscribe : unsubscribeEn;
    const mail = welcomeMail(locale, { unsubscribe: links, launchNews: false });
    assertEquals(mail.headers, {
      'List-Unsubscribe': `<${links.oneClick}>`,
      'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
    });
    assert(
      mail.text.includes(
        locale === 'de' ? `Abmelden <${links.page}>` : `Unsubscribe <${links.page}>`,
      ),
    );
    assert(mail.text.includes(locale === 'de' ? 'Art. 21 DSGVO' : 'Art. 21 GDPR'));
    assertNoImagesOrTracking(mail);
    const news = welcomeMail(locale, { unsubscribe: links, launchNews: true });
    const sentence = locale === 'de'
      ? 'Sonst schreiben wir dir nur noch'
      : "Otherwise we'll only email you once more";
    assert(!mail.text.includes(sentence) && news.text.includes(sentence), locale);
  }
});

/** Legal's N-261 footers (batch of 2026-11-17), verbatim; {UNSUBSCRIBE_URL} is the page link. */
const N261 = {
  de: [
    'Du bekommst diese E-Mail, weil du dich auf snacklist.app für die Warteliste der Snacklist-Beta eingetragen und deine Adresse bestätigt hast. Keine E-Mails mehr von uns? [Abmelden]({UNSUBSCRIBE_URL}) – ein Klick genügt, ohne Anmeldung, und wir löschen deine Eintragung. Damit widerrufst du deine Einwilligung und widersprichst der Nutzung deiner Adresse für diese E-Mails (Art. 21 DSGVO). Du kannst auch einfach auf diese E-Mail antworten oder an support@snacklist.app schreiben; Antworten liest Peter Trost selbst.',
    'Absender: Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Deutschland',
    'Impressum: https://snacklist.app/impressum · Datenschutz: https://snacklist.app/datenschutz (Abschnitt 2a)',
  ],
  en: [
    "You're getting this email because you signed up for the Snacklist beta waitlist on snacklist.app and confirmed your address. No more emails from us? [Unsubscribe]({UNSUBSCRIBE_URL}) – one click, no sign-in, and we delete your sign-up. This withdraws your consent and objects to the use of your address for these emails (Art. 21 GDPR). You can also just reply to this email or write to support@snacklist.app; Peter Trost reads replies himself.",
    'Sender: Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Germany',
    'Imprint: https://snacklist.app/en/imprint · Privacy: https://snacklist.app/en/privacy (section 2a)',
  ],
};

Deno.test("the iOS invite ends with Legal's N-261 footer word for word, links written out in the text", () => {
  for (const locale of ['de', 'en'] as const) {
    const links = locale === 'de' ? unsubscribe : unsubscribeEn;
    const mail = inviteMail(locale, { platform: 'ios', unsubscribe: links });
    const [why, sender, imprint] = N261[locale].map((line) =>
      line.replace(/\[(Abmelden|Unsubscribe)\]\(\{UNSUBSCRIBE_URL\}\)/, `$1 <${links.page}>`)
    );
    assertEquals(
      mail.text.slice(mail.text.indexOf('\n--\n') + 4),
      `\n${why}\n\n${sender}\n${imprint}\n`,
    );
    const label = locale === 'de' ? 'Abmelden' : 'Unsubscribe';
    const footerHtml = mail.html.slice(mail.html.indexOf('<hr'));
    assert(
      footerHtml.includes(
        `<a href="${links.page.replaceAll('&', '&amp;')}" style="color:#1a6b3c">${label}</a> – `,
      ),
    );
    const visible = footerHtml.replace(/<br>/g, '\n').replace(/<[^>]+>/g, '')
      .replaceAll('&amp;', '&').trim();
    assertEquals(
      visible,
      N261[locale].join('\n').replace(/\[(Abmelden|Unsubscribe)\]\(\{UNSUBSCRIBE_URL\}\)/, '$1'),
      'the HTML shows the same words, the link on its label',
    );
    assertEquals(
      mail.from,
      IOS_DRAFT[locale].from,
      'N-262 is not applied: the draft keeps its sender name',
    );
  }
});

/** PM's iOS invite draft of 2026-11-16 (plain-text twin, above the footer), verbatim. */
const IOS_DRAFT = {
  de: {
    from: '"Peter von Snacklist" <hello@snacklist.app>',
    preheader:
      'Deine Einladung zur Beta ist da. Den Zugang über TestFlight schickt dir Apple in einer eigenen Mail.',
    body: `Hallo,

du hast dich auf snacklist.app für die Warteliste eingetragen. Jetzt bist du bei der Beta dabei.

Ich bin Peter und baue Snacklist, eine Einkaufsliste für den ganzen Haushalt. Die gemeinsame Liste ist bei allen sofort aktuell, und es gibt keine Werbung.

Auf dem iPhone testest du über TestFlight, Apples App für Testversionen. Die Einladung dazu schickt dir Apple in einer eigenen Mail an diese Adresse.

So kommst du rein:

1. TestFlight laden
Lad dir „TestFlight“ aus dem App Store.

2. Apples Mail öffnen
Öffne die Einladungsmail von TestFlight auf deinem iPhone und tipp auf den Knopf darin. Dann installierst du Snacklist über TestFlight.

3. Loslegen
Öffne Snacklist und tipp auf „Los geht's“. Die App fragt dich, mit wem du einkaufst, und richtet den Haushalt mit dir ein. Am Ende legst du dein Konto an. Wer mit dir einkauft, braucht für die Beta eine eigene Einladung. Am einfachsten trägt sich die Person selbst auf snacklist.app in die Warteliste ein. Sobald Snacklist bei ihr installiert ist, kann sie deinem Haushalt beitreten.

TestFlight im App Store: https://apps.apple.com/app/testflight/id899247664

Keine Mail von Apple da? Schau auch im Spam-Ordner nach. Ist diese Adresse nicht die E-Mail deiner Apple-ID? Dann trag dich auf snacklist.app einfach noch mal mit der richtigen Adresse ein.

Was dir auffällt, gut oder schlecht, kannst du direkt in der App schicken: Mehr › „Feedback senden“. Jede Rückmeldung hilft.

Viel Spaß beim Testen,
Peter

`,
  },
  en: {
    from: '"Peter from Snacklist" <hello@snacklist.app>',
    preheader: 'Your beta invite is here. Apple sends your TestFlight access in a separate email.',
    body: `Hi,

You signed up for the waitlist on snacklist.app. You're now in the beta.

I'm Peter, and I'm building Snacklist, a grocery list for your whole household. The shared list is up to date for everyone right away, and there are no ads.

On iPhone, you test through TestFlight, Apple's app for test versions. Apple sends you the invite in a separate email to this address.

Here's how to get in:

1. Get TestFlight
Download "TestFlight" from the App Store.

2. Open Apple's email
Open the TestFlight invite email on your iPhone and tap the button in it. Then install Snacklist in TestFlight.

3. Get started
Open Snacklist and tap "Get started". The app asks who you shop with and sets up the household with you. At the end you create your account. Anyone who shops with you needs their own beta invite. The easiest way is for them to join the waitlist on snacklist.app/en themselves. Once Snacklist is installed on their phone, they can join your household.

TestFlight on the App Store: https://apps.apple.com/app/testflight/id899247664

No email from Apple? Check your spam folder too. If this address isn't the email of your Apple ID, just sign up again on snacklist.app/en with the right one.

Anything you notice, good or bad, you can send right in the app: More › "Send feedback". Every bit helps.

Have fun testing,
Peter

`,
  },
};

Deno.test("the iOS invite is PM's draft word for word, with the draft's preheader and sender", () => {
  for (const locale of ['de', 'en'] as const) {
    const mail = inviteMail(locale, {
      platform: 'ios',
      unsubscribe: locale === 'de' ? unsubscribe : unsubscribeEn,
    });
    const draft = IOS_DRAFT[locale];
    assertEquals(mail.from, draft.from);
    assertEquals(mail.text.slice(0, mail.text.indexOf('\n--\n')).trimEnd(), draft.body.trimEnd());
    assert(mail.html.includes(`>${draft.preheader}</div>`));
    assert(mail.html.includes('https://apps.apple.com/app/testflight/id899247664'));
  }
});

Deno.test('the invite mail has an iPhone and an Android line, its footer and one-click unsubscribe', () => {
  const ios = inviteMail('de', { platform: 'ios', unsubscribe });
  const android = inviteMail('en', { platform: 'android', unsubscribe: unsubscribeEn });
  assert(ios.text.includes('TestFlight') && !ios.text.includes('play.google.com'));
  assert(android.text.includes('https://play.google.com/apps/testing/com.snacklist.app'));
  assert(!android.text.includes('TestFlight'));
  assertEquals(ios.headers['List-Unsubscribe'], `<${unsubscribe.oneClick}>`);
  assertEquals(android.headers['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click');
  assert(ios.text.includes('Abmelden') && android.text.includes('Unsubscribe'));
  assertNoImagesOrTracking(ios);
  assertNoImagesOrTracking(android);
});

Deno.test('the HTML escapes what it interpolates', () => {
  const mail = confirmationMail('de', {
    confirmUrl: 'https://snacklist.app/de/warteliste/bestaetigen#t="><script>',
    unsubscribe,
  });
  assert(!mail.html.includes('<script>'));
  assert(mail.html.includes('#t=&quot;&gt;&lt;script&gt;'));
});

Deno.test('refusal: test addresses only unless *, and no draft text without the override', () => {
  const approved = welcomeMail('de', { unsubscribe, launchNews: false });
  const draft = { ...approved, text: `⟦LAUNCH COPY⟧\n${approved.text}` };
  assertEquals(mailAllowFrom(undefined), 'test');
  assertEquals(mailAllowFrom(''), 'test');
  assertEquals(mailAllowFrom('yes'), 'test');
  assertEquals(mailAllowFrom('*'), 'all');
  for (
    const ok of [
      'hello+x@hummlist.com',
      'HELLO+waitlisttest@HUMMLIST.COM',
      'test@snacklist.app',
      'test+x@snacklist.app',
      'TEST+waitlisttest@SNACKLIST.APP',
    ]
  ) {
    assert(recipientAllowed(ok, 'test'), ok);
  }
  for (
    const no of [
      'hello@hummlist.com',
      'peter@example.com',
      'hello+x@hummlist.com.evil.de',
      'xhello+x@hummlist.com',
      'hello+@hummlist.com',
      'test+@snacklist.app',
      'test@snacklist.app.evil.de',
      'xtest@snacklist.app',
      'test@snacklist.appx',
      'hello+x@snacklist.app',
      'test@hummlist.com',
      'testing@snacklist.app',
    ]
  ) {
    assert(!recipientAllowed(no, 'test'), no);
  }
  assert(recipientAllowed('peter@example.com', 'all'));
  const test = { allow: 'test' as const, allowPlaceholders: false };
  assertEquals(refusal('peter@example.com', approved, test), 'recipient');
  assertEquals(refusal('test+x@snacklist.app', draft, test), 'placeholder');
  assertEquals(refusal('test+x@snacklist.app', draft, { ...test, allowPlaceholders: true }), null);
  assertEquals(refusal('test+x@snacklist.app', approved, test), null);
  assertEquals(refusal('test@snacklist.app', approved, test), null);
  assertEquals(refusal('test+x@snacklist.app', approved, test), null);
  assertEquals(refusal('test@snacklist.app', draft, test), 'placeholder');
  assertEquals(
    refusal('peter@example.com', approved, { allow: 'all', allowPlaceholders: false }),
    null,
  );
});

Deno.test('From is the language-neutral Peter · Snacklist (U+00B7) for DE and EN, and Resend gets that exact UTF-8 string', async () => {
  const from = '"Peter \u00B7 Snacklist" <hello@snacklist.app>';
  assertEquals(from, '"Peter · Snacklist" <hello@snacklist.app>');
  assertEquals(from.codePointAt(from.indexOf('\u00B7')), 0x00B7);
  const de = confirmationMail('de', {
    confirmUrl: confirmUrl('https://snacklist.app', 'de', TOKEN),
    unsubscribe,
  });
  const en = confirmationMail('en', {
    confirmUrl: confirmUrl('https://snacklist.app', 'en', TOKEN),
    unsubscribe: unsubscribeEn,
  });
  const welcome = welcomeMail('en', { unsubscribe: unsubscribeEn, launchNews: false });
  const invite = inviteMail('de', { platform: 'android', unsubscribe });
  for (const mail of [de, en, welcome, invite]) {
    assertEquals(mail.from, from);
    assertEquals(mail.replyTo, 'hello@snacklist.app');
  }
  const requests: Request[] = [];
  const mailer = resendMailer('re_test_key', 'https://resend.test/', (input, init) => {
    requests.push(new Request(input, init));
    return Promise.resolve(new Response('{"id":"x"}', { status: 200 }));
  });
  await mailer.send('test+resend@snacklist.app', en, 'confirm/from');
  assertEquals(requests.length, 1);
  const [req] = requests;
  assertExists(req, 'the request');
  const raw = new Uint8Array(await req.arrayBuffer());
  const decoded = new TextDecoder().decode(raw);
  assertEquals(JSON.parse(decoded).from, from);
  // Resend's JSON body carries U+00B7 as UTF-8 C2 B7, not as a \\u escape or ASCII substitute.
  // Quotes around the display name are JSON-escaped, so search the name itself.
  const utf8Name = new TextEncoder().encode('Peter \u00B7 Snacklist');
  let found = false;
  for (let i = 0; i <= raw.length - utf8Name.length; i++) {
    if (utf8Name.every((b, j) => raw[i + j] === b)) {
      found = true;
      break;
    }
  }
  assert(found, 'the Resend payload encodes the display name as UTF-8 (U+00B7 is C2 B7)');
  assert(!decoded.includes('\\u00b7') && !decoded.includes('\\u00B7'));
});

Deno.test('Resend: one single send with an idempotency key, reply-to and the mail headers, no tags', async () => {
  const requests: Request[] = [];
  const mailer = resendMailer('re_test_key', 'https://resend.test/', (input, init) => {
    requests.push(new Request(input, init));
    return Promise.resolve(new Response('{"id":"x"}', { status: 200 }));
  });
  const mail = welcomeMail('de', { unsubscribe, launchNews: false });
  await mailer.send('test+resend@snacklist.app', mail, `welcome/${ID}`);
  assertEquals(requests.length, 1);
  const [req] = requests;
  assertExists(req, 'the request');
  assertEquals([req.method, req.url], ['POST', 'https://resend.test/emails']);
  assertEquals(req.headers.get('authorization'), 'Bearer re_test_key');
  assertEquals(req.headers.get('idempotency-key'), `welcome/${ID}`);
  assertEquals(await req.json(), {
    from: '"Peter · Snacklist" <hello@snacklist.app>',
    to: ['test+resend@snacklist.app'],
    reply_to: 'hello@snacklist.app',
    subject: mail.subject,
    html: mail.html,
    text: mail.text,
    headers: mail.headers,
  });

  const confirmation = confirmationMail('de', {
    confirmUrl: 'https://snacklist.app/x',
    unsubscribe,
  });
  await mailer.send('test+resend@snacklist.app', confirmation, 'confirm/x');
  const second = requests[1];
  assertExists(second, 'the second request');
  assertEquals(Object.keys(await second.json()).sort(), [
    'from',
    'html',
    'reply_to',
    'subject',
    'text',
    'to',
  ]);
});

Deno.test('Resend: a refusal names the status, never the answer', async () => {
  const mailer = resendMailer(
    'k',
    undefined,
    () =>
      Promise.resolve(
        new Response('{"message":"test+x@snacklist.app is invalid"}', { status: 422 }),
      ),
  );
  const e = await assertRejects(
    () =>
      mailer.send(
        'test+x@snacklist.app',
        welcomeMail('en', { unsubscribe: unsubscribeEn, launchNews: false }),
        'k',
      ),
    MailError,
  );
  assertEquals(e.message, 'resend answered 422');
});

Deno.test('no mail names Hummlist or hummlist.com (G1 name and domain swap)', () => {
  const mails = [
    confirmationMail('de', { confirmUrl: confirmUrl(SITE, 'de', TOKEN), unsubscribe }),
    confirmationMail('en', {
      confirmUrl: confirmUrl(SITE, 'en', TOKEN),
      unsubscribe: unsubscribeEn,
    }),
    welcomeMail('de', { launchNews: true, unsubscribe }),
    welcomeMail('en', { launchNews: false, unsubscribe: unsubscribeEn }),
    inviteMail('de', { platform: 'ios', unsubscribe }),
    inviteMail('en', { platform: 'android', unsubscribe: unsubscribeEn }),
  ];
  for (const mail of mails) {
    for (const part of [mail.subject, mail.text, mail.html, ...Object.values(mail.headers ?? {})]) {
      assert(
        !/hummlist/i.test(part),
        `${mail.subject}: ${part.match(/.{0,30}hummlist.{0,30}/i)?.[0]}`,
      );
    }
  }
});
