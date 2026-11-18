import { assert, assertEquals } from '@std/assert';
import { confirmationMail, decisionMail, formatDate, formatDateTime, OUTCOMES } from './mail.ts';
import type { Mail } from '../_shared/resend.ts';

const WINTER = new Date('2026-11-16T13:05:00Z');
const SUMMER = new Date('2027-07-01T22:30:00Z');
const REF = 'M-7KQ2-XW9D';

/** The mail as Legal wrote it, on one line: the greeting's paragraph and the signature joined. */
const oneLine = (mail: Mail) => mail.text.trim().split('\n\n').join(' ');

Deno.test('dates in Berlin: DE with Uhr, EN with CET or CEST', () => {
  assertEquals(formatDateTime('de', WINTER), '16.11.2026, 14:05 Uhr');
  assertEquals(formatDateTime('en', WINTER), '16 November 2026, 14:05 CET');
  assertEquals(formatDateTime('de', SUMMER), '02.07.2027, 00:30 Uhr');
  assertEquals(formatDateTime('en', SUMMER), '2 July 2027, 00:30 CEST');
  assertEquals(formatDate('de', SUMMER), '02.07.2027');
  assertEquals(formatDate('en', WINTER), '16 November 2026');
});

Deno.test('B.4 confirmation, German, word for word', () => {
  const mail = confirmationMail({ locale: 'de', name: 'Anna', createdAt: WINTER, ref: REF });
  assertEquals(mail.subject, `Deine Meldung an Snacklist ist eingegangen (${REF})`);
  assertEquals(mail.from, '"Snacklist Support" <no-reply@snacklist.app>');
  assertEquals(mail.replyTo, 'support@snacklist.app');
  assertEquals(
    oneLine(mail),
    `Hallo Anna, danke für deine Meldung vom 16.11.2026, 14:05 Uhr (Nummer ${REF}). Wir haben sie ` +
      'erhalten und prüfen sie selbst, ohne automatische Entscheidung. Sobald wir entschieden ' +
      'haben, schreiben wir dir, was wir getan haben und warum. Du musst nichts weiter tun. Wenn ' +
      'du etwas ergänzen willst, antworte einfach auf diese E-Mail. – Snacklist Support',
  );
  assert(mail.text.startsWith('Hallo Anna, danke'), 'greeting and body are one paragraph');
  assert(mail.text.endsWith('\n\n– Snacklist Support\n'), 'and so is the signature');
});

Deno.test('B.4 confirmation, English, word for word', () => {
  const mail = confirmationMail({ locale: 'en', name: 'Ann', createdAt: WINTER, ref: REF });
  assertEquals(mail.subject, `We've received your report to Snacklist (${REF})`);
  assertEquals(
    oneLine(mail),
    `Hi Ann, thanks for your report of 16 November 2026, 14:05 CET (number ${REF}). We've ` +
      "received it and review it ourselves, with no automated decision. Once we've decided, " +
      "we'll write to tell you what we did and why. You don't need to do anything else. To add " +
      'something, just reply to this e-mail. – Snacklist Support',
  );
});

Deno.test('without a name the greeting is Hallo, / Hi,', () => {
  const de = confirmationMail({ locale: 'de', name: null, createdAt: WINTER, ref: REF });
  const en = confirmationMail({ locale: 'en', name: null, createdAt: WINTER, ref: REF });
  assert(de.text.startsWith('Hallo, danke für'));
  assert(en.text.startsWith('Hi, thanks for'));
});

Deno.test('HTML: the same paragraphs, escaped, no links, images or scripts', () => {
  const mail = decisionMail({
    locale: 'de',
    name: 'Anna',
    date: WINTER,
    ref: REF,
    outcome: 'no_change',
    reason: 'Der Eintrag <b>Brot</b> & "Butter" ist erlaubt',
  });
  assert(
    mail.html.includes('Der Eintrag &lt;b&gt;Brot&lt;/b&gt; &amp; &quot;Butter&quot; ist erlaubt.'),
  );
  assert(mail.html.includes('<html lang="de">'));
  assert(!/<a |<img|<script|<link|url\(|https?:/i.test(mail.html), 'nothing remote');
  assertEquals((mail.html.match(/<p /g) ?? []).length, 2);
  assert(
    mail.text.includes('Der Eintrag <b>Brot</b> & "Butter" ist erlaubt.'),
    'plain text keeps it as typed',
  );
});

Deno.test('B.6a decision, German, each outcome word for word', () => {
  const phrases = {
    removed: 'wir haben den Inhalt entfernt',
    'made_invisible': 'wir haben den Inhalt unsichtbar gemacht',
    'account_suspended': 'wir haben das Konto gesperrt',
    'no_change': 'wir haben nichts geändert',
  };
  for (const outcome of OUTCOMES) {
    const mail = decisionMail({
      locale: 'de',
      name: 'Anna',
      date: WINTER,
      ref: REF,
      outcome,
      reason: 'Der Eintrag ist eine Beleidigung nach § 185 StGB',
    });
    assertEquals(mail.subject, `Unsere Entscheidung zu deiner Meldung (${REF})`);
    assertEquals(
      oneLine(mail),
      `Hallo Anna, wir haben deine Meldung vom 16.11.2026 (${REF}) geprüft. Entscheidung: ` +
        `${phrases[outcome]}. Grund: Der Eintrag ist eine Beleidigung nach § 185 StGB. Die ` +
        'Entscheidung hat ein Mensch getroffen, ohne automatische Mittel. Wenn du nicht ' +
        'einverstanden bist, antworte auf diese E-Mail, dann prüfen wir noch einmal. Du kannst ' +
        'außerdem die Zivilgerichte anrufen oder dich bei der Koordinierungsstelle für digitale ' +
        'Dienste der Bundesnetzagentur beschweren. – Snacklist Support',
    );
  }
});

Deno.test('B.6a decision, English, each outcome word for word', () => {
  const phrases = {
    removed: 'we removed the content',
    'made_invisible': 'we made the content invisible',
    'account_suspended': 'we suspended the account',
    'no_change': 'we changed nothing',
  };
  for (const outcome of OUTCOMES) {
    const mail = decisionMail({
      locale: 'en',
      name: null,
      date: WINTER,
      ref: REF,
      outcome,
      reason: "We couldn't find the item.",
    });
    assertEquals(mail.subject, `Our decision on your report (${REF})`);
    assertEquals(
      oneLine(mail),
      `Hi, we've reviewed your report of 16 November 2026 (${REF}). Decision: ` +
        `${phrases[outcome]}. Reason: We couldn't find the item. A person made this decision, ` +
        "without automated means. If you disagree, reply to this e-mail and we'll review it " +
        'again. You can also go to the civil courts or complain to the Digital Services ' +
        'Coordinator at the Bundesnetzagentur. – Snacklist Support',
    );
  }
});

Deno.test('a multi-line ground keeps its lines, as <br> in HTML', () => {
  const mail = decisionMail({
    locale: 'de',
    name: 'Anna',
    date: WINTER,
    ref: REF,
    outcome: 'no_change',
    reason: 'Erstens.\nZweitens.',
  });
  assert(mail.text.includes('Grund: Erstens.\nZweitens. Die Entscheidung'));
  assert(mail.html.includes('Grund: Erstens.<br>Zweitens. Die Entscheidung'));
});

Deno.test('a name that is no plain name is left out of the greeting', () => {
  for (const name of ['Anna', 'Anna-Lena Müller', "D'Souza", 'Dr. Anna', 'Anna B.', 'Zoë Ñúñez']) {
    const mail = confirmationMail({ locale: 'de', name, createdAt: WINTER, ref: REF });
    assert(mail.text.startsWith(`Hallo ${name}, danke`), name);
  }
  for (
    const name of [
      'Gewinner! Ihr Paket wartet: https://evil.example/login',
      'evil.example',
      'www.evil.example',
      'mail me at a@b.de',
      'Anna 0800 123456',
      'A'.repeat(61),
    ]
  ) {
    const mail = confirmationMail({ locale: 'en', name, createdAt: WINTER, ref: REF });
    assert(mail.text.startsWith('Hi, thanks for'), name);
    assert(!mail.html.includes(name.slice(0, 10)), `${name}: not in the HTML either`);
  }
});
