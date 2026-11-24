import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { DEMO_UNSUBSCRIBE_URL, OnboardingFooter, PrimaryButton, onboardingHeaders } from '../src/components/index.ts';
import { AuthLayout } from '../src/layouts.tsx';
import { NudgeDe } from '../src/emails/onboarding.tsx';
import { EmailRenderError, renderEmail } from '../src/render.ts';
import { EMAILS, fillDemo } from '../src/registry.tsx';
import { AUTH_MAILS, subjectTemplate } from '../src/emails/auth.tsx';
import { templateFiles } from '../scripts/build.tsx';

const fixture = (name: string) => readFileSync(new URL(`fixtures/${name}`, import.meta.url), 'utf8');
// AL4's six templates and subjects (fixtures/al4/README.md): the wording the design wraps.
const al4Subjects: Record<string, string> = JSON.parse(fixture('al4/subjects.json'));
const AL4 = Object.keys(al4Subjects);
const al4Branch = (template: string, lang: 'de' | 'en') => {
  const [de, en] = fixture(`al4/${template}.html`).split('{{- else -}}');
  const branch = lang === 'de' ? de : en;
  assert.ok(branch !== undefined, `${template}-${lang}`);
  // AL4's last line was a brand line; the Legal footer took its place.
  return branch.replace(/^\{\{.*$/gm, '').replace(/<p style="color:#6b6b6b[^\n]*<\/p>/, '');
};
const built = await templateFiles();
const rendered = await Promise.all(EMAILS.map(async (email) => ({ email, ...(await renderEmail(email.element)) })));
const auth = rendered.filter((r) => r.email.template);
const renderedMail = (id: string) => {
  const found = rendered.find((r) => r.email.id === id);
  assert.ok(found, id);
  return found;
};

const decode = (s: string) => s.replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, '"').replace(/&gt;/g, '>').replace(/&lt;/g, '<').replace(/&amp;/g, '&');
const words = (s: string) => (s.match(/[\p{L}\p{N}@.]+/gu) ?? []).map((w) => w.replace(/\.+$/, '')).filter(Boolean);
const body = (text: string) => text.split('\n-- \n')[0] ?? '';
const GO_VAR = /\{\{ \.[A-Za-z]+ \}\}/g;

test('every mail renders HTML under 100 KB (Gmail clips at 102 KB) and plain text', () => {
  for (const { email, html, text } of rendered) {
    assert.ok(Buffer.byteLength(html) < 100 * 1024, `${email.id} HTML is ${Buffer.byteLength(html)} bytes`);
    assert.ok(text.trim().length > 50, `${email.id} has no plain text`);
    assert.doesNotMatch(html, /var\(--/, `${email.id} uses CSS variables`);
    assert.doesNotMatch(html, /display:\s*(flex|grid)/, `${email.id} uses flex or grid`);
  }
});

test('every AL4 template is built in both languages, with AL4\'s subjects', () => {
  for (const template of AL4) {
    for (const lang of ['de', 'en'] as const) {
      const email = auth.find((r) => r.email.template === template && r.email.lang === lang)?.email;
      assert.ok(email, `${template}-${lang}`);
      assert.ok(al4Subjects[template]?.includes(`${lang === 'de' ? '{{ if $de }}' : '{{ else }}'}${email.subject}{{`), `${template}-${lang} subject`);
    }
    const mail = AUTH_MAILS.find((m) => m.template === template);
    assert.ok(mail, template);
    assert.equal(subjectTemplate({ de: mail.copy.de.subject, en: mail.copy.en.subject }), al4Subjects[template], `${template}: config.toml subject`);
  }
});

test('auth mails keep AL4\'s wording word for word in both languages, Go template variables unescaped', () => {
  for (const { email, html, text } of auth) {
    const { template } = email;
    if (template === undefined || !AL4.includes(template)) continue;
    const source = al4Branch(template, email.lang);
    for (const v of source.match(GO_VAR) ?? []) assert.ok(html.includes(v), `${email.id} lost ${v} in HTML`);
    assert.doesNotMatch(html, /\{\{[^}]*(&[a-z#0-9]+;)[^}]*\}\}/, `${email.id} escaped a template variable`);
    const theirs = words(decode(source.replace(/<[^>]+>/g, ' ')).replace(GO_VAR, ' '));
    const ours = words(body(text).replace(/^.*:\n\{\{ \.ConfirmationURL \}\}$/m, (m) => m.split(':')[0] ?? '').replace(GO_VAR, ' '));
    assert.deepEqual(ours, theirs, `${email.id} wording changed`);
  }
});

test('a template file is AL4\'s pick with German first and English as the fallback', () => {
  assert.deepEqual([...built.keys()].sort(), [...new Set(auth.map((r) => `${r.email.template}.html`))].sort());
  for (const [name, file] of built) {
    const [head, de, en, ...rest] = file.split(/\{\{ if \$de -\}\}|\{\{- else -\}\}/);
    assert.equal(rest.length, 0, name);
    assert.ok(head !== undefined && de !== undefined && en !== undefined, name);
    assert.ok(head.endsWith('{{- $de := false }}{{ with .Data }}{{ $de = eq (printf "%v" .mail_locale) "de" }}{{ end -}}\n'), `${name} picks by mail_locale`);
    assert.match(de, /^\n<!DOCTYPE[\s\S]*<html dir="ltr" lang="de">/, `${name} German branch`);
    assert.match(en, /^\n<!DOCTYPE[\s\S]*<html dir="ltr" lang="en">[\s\S]*\{\{- end \}\}\n$/, `${name} English branch, last`);
  }
});

test('onboarding mails keep the draft wording word for word', () => {
  const demo = { '{{NAME}}': 'Anna', '{{GOOGLE_EMAIL}}': 'anna.beispiel@example.com', '{{JOIN_URL}}': 'https://play.google.com/apps/internaltest/4700554042680195988' };
  for (const id of ['welcome-android-de', 'welcome-android-en', 'nudge-de', 'nudge-en']) {
    const { text } = renderedMail(id);
    const draft = fillDemo(fixture(`drafts/${id}.txt`), demo);
    // The plain text adds the button's label over its link and the legal footer after the
    // feedback note; the rest is the draft.
    const [main, footer] = text.split('\n-- \n');
    assert.ok(main !== undefined && footer !== undefined, id);
    const ours = `${main.replace(/^[^\n]*:\n(?=https:\/\/play)/m, '')}\n${footer.split('\n\n')[0]}`;
    assert.deepEqual(words(ours), words(draft), `${id} wording changed`);
  }
});

test('no placeholder palette, no "Humm" alone, no remote load outside snacklist.app', () => {
  const links = /^(https:\/\/(snacklist\.app|app\.snacklist\.app)(\/|$)|mailto:hello@snacklist\.app$|\{\{ \.ConfirmationURL \}\}$)/;
  for (const { email, html, text } of rendered) {
    assert.doesNotMatch(html, /#F5B400/i, email.id);
    for (const s of [html, text, email.subject]) assert.doesNotMatch(s, /Humm(?!list)/, `${email.id}: always "Snacklist"`);
    for (const [, url = ''] of html.matchAll(/\ssrc="([^"]*)"/g)) assert.match(url, /^https:\/\/snacklist\.app\//, `${email.id} loads ${url}`);
    assert.doesNotMatch(html, /url\(|@import|<link /, `${email.id} loads CSS or fonts`);
    for (const [, url = ''] of html.matchAll(/\shref="([^"]*)"/g)) {
      const join = email.kind === 'onboarding' && url.startsWith('https://play.google.com/apps/internaltest/');
      assert.ok(join || links.test(decode(url)), `${email.id} links ${url}`);
    }
  }
});

test('transactional mails carry the transactional footer, onboarding mails the unsubscribe footer', () => {
  for (const { email, html, text } of rendered) {
    const de = email.lang === 'de';
    assert.ok(text.includes(de ? 'Rottenburg am Neckar · Deutschland · support@snacklist.app' : 'Rottenburg am Neckar · Germany · support@snacklist.app'), email.id);
    assert.ok(text.includes(de ? 'Impressum: https://snacklist.app/impressum' : 'Imprint: https://snacklist.app/en/imprint'), email.id);
    assert.match(text, /^(Du bekommst|You're getting) diese?|^You're getting this e-mail/m, `${email.id} says why`);
    const unsubscribe = html.includes('data-hl-unsubscribe');
    assert.equal(unsubscribe, email.kind === 'onboarding' || email.kind === 'catalog', `${email.id} unsubscribe link`);
    if (unsubscribe) assert.ok(text.includes(`${de ? 'Abbestellen' : 'Unsubscribe'}: ${DEMO_UNSUBSCRIBE_URL}`), email.id);
  }
});

test('plain text prints the button link on its own line and numbers the steps', () => {
  for (const { email, html, text } of rendered) {
    const href = html.match(/data-hl-href="([^"]*)"/)?.[1];
    if (href) assert.match(text, new RegExp(`^${decode(href).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'm'), `${email.id} link line`);
  }
  const welcome = renderedMail('welcome-android-de').text;
  assert.match(welcome, /^1\. Installieren$\n[\s\S]*^2\. Anmelden$\n[\s\S]*^3\. Haushalt$/m);
});

test('a mail has one primary button', async () => {
  const two = (
    <AuthLayout lang="de" title="t" reason={{ confirmed: 'r' }}>
      <PrimaryButton href="https://app.snacklist.app">Eins</PrimaryButton>
      <PrimaryButton href="https://app.snacklist.app">Zwei</PrimaryButton>
    </AuthLayout>
  );
  await assert.rejects(renderEmail(two), EmailRenderError);
});

test('a production render refuses draft lines and the demo unsubscribe link', async () => {
  const draft = renderedMail('password_changed_notification-de').email.element;
  await assert.rejects(renderEmail(draft, { production: true }), /reason line, Launch to confirm/);
  const demo = renderedMail('nudge-de').email.element;
  await assert.rejects(renderEmail(demo, { production: true }), /demo one/);
  const lower = <NudgeDe name="Anna" unsubscribeUrl="https://app.snacklist.app/email/abmelden?t=demo" />;
  await assert.rejects(renderEmail(lower, { production: true }), /demo one/);
  const confirmed = renderedMail('magic_link-de').email.element;
  await renderEmail(confirmed, { production: true });
});

test('OnboardingFooter refuses a missing unsubscribe link', () => {
  for (const url of ['', 'https://example.com/x', 'https://app.snacklist.app/email/abmelden?t=', 'https://app.snacklist.app/email/abmelden?t=anna@example.com']) {
    // @ts-expect-error -- not an UnsubscribeUrl
    assert.throws(() => OnboardingFooter({ lang: 'de', unsubscribeUrl: url }), /unsubscribe URL/);
  }
});

test('onboarding sends get one-click List-Unsubscribe headers by token, never by address', () => {
  assert.deepEqual(onboardingHeaders('tok_3f9a2b7c'), {
    'List-Unsubscribe': '<https://app.snacklist.app/email/abmelden?t=tok_3f9a2b7c>, <mailto:hello@snacklist.app?subject=unsubscribe>',
    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
  });
  for (const bad of ['', 'anna@example.com', 'a b c d e f g h']) assert.throws(() => onboardingHeaders(bad), /token/);
});

// Legal Review 2026-11-01 N-15, copied from the addendum independently of Footer.tsx.
const LEGAL = {
  de: {
    sender: 'Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Deutschland · support@snacklist.app',
    links: 'Impressum: https://snacklist.app/impressum · Datenschutz: https://snacklist.app/datenschutz',
    onboarding: 'Du bekommst diese E-Mail, weil du bei der Anmeldung Tipps zu Snacklist per E-Mail bestellt hast. Keine Tipps mehr? Abbestellen – ein Klick genügt, ohne Anmeldung. Oder antworte mit „Abbestellen“ an hello@snacklist.app. Dafür entstehen dir nur die Übermittlungskosten nach den Basistarifen. Du kannst deine Einwilligung jederzeit widerrufen und der Nutzung deiner Daten für diese E-Mails jederzeit widersprechen (Art. 21 DSGVO).',
  },
  en: {
    sender: 'Snacklist · Peter Trost · Yalovastr. 5 · 72108 Rottenburg am Neckar · Germany · support@snacklist.app',
    links: 'Imprint: https://snacklist.app/en/imprint · Privacy: https://snacklist.app/en/privacy',
    onboarding: 'You\'re getting this e-mail because you signed up for Snacklist tips by e-mail. No more tips? Unsubscribe: one click, no sign-in. Or reply "Unsubscribe" to hello@snacklist.app. This costs you nothing beyond your normal connection charges. You can withdraw your consent and object to the use of your data for these e-mails at any time (Art. 21 GDPR).',
  },
};

test('footers carry Legal Review\'s text word for word', () => {
  for (const { email, text } of rendered) {
    const lines = text.split('\n');
    const legal = LEGAL[email.lang];
    assert.ok(lines.includes(legal.sender), `${email.id} sender line`);
    assert.ok(lines.includes(legal.links), `${email.id} imprint and privacy`);
    if (email.kind === 'onboarding') assert.ok(lines.includes(legal.onboarding), `${email.id} unsubscribe paragraph`);
  }
  const line = (id: string) => renderedMail(id).text.split('\n');
  assert.ok(line('magic_link-en').includes("You're getting this e-mail because a Snacklist sign-in link was requested for this address. If that wasn't you, just ignore it."));
  assert.ok(line('magic_link-de').includes('Du bekommst diese E-Mail, weil mit dieser Adresse ein Anmeldelink für Snacklist angefordert wurde. Warst du das nicht, ignoriere sie einfach.'));
  assert.ok(line('account-deleted-de').includes('Du bekommst diese E-Mail, weil dein Snacklist-Konto gelöscht wurde.'));
  assert.ok(line('account-deleted-en').includes("You're getting this e-mail because your Snacklist account was deleted."));
});

test('the button is 48 px with a VML twin for Outlook, and dark mode has its overrides', () => {
  for (const { email, html } of rendered) {
    assert.match(html, /@media \(prefers-color-scheme: dark\)/, email.id);
    assert.match(html, /<meta name="color-scheme" content="light dark"\/>/, email.id);
    if (!html.includes('data-hl-cta')) continue;
    assert.match(html, /<v:roundrect [^>]*style="height:48px;/, `${email.id} VML button`);
    assert.match(html, /line-height:44px;min-height:44px/, `${email.id} button inside a 2 px contour: 48 px`);
  }
});

test('plain text keeps a link in a heading or tip in the body, not in the footer', async () => {
  const { text } = await renderEmail(
    <AuthLayout lang="de" title="t" reason={{ confirmed: 'Grund.' }}>
      <h1>Siehe <a href="https://snacklist.app/de">hier</a></h1>
    </AuthLayout>,
  );
  assert.ok(text.indexOf('hier: https://snacklist.app/de') < text.indexOf('\n-- \n'), text);
});
