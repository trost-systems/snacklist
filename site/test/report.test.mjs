// The DSA notice form on /inhalte-melden and /en/report (job 275): what the build renders from
// the pages' `form:` front matter, and the front matter it refuses.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import matter from 'gray-matter';
import { buildSite, guide, htmlRoutes, CONTENT_DIR } from './helpers.mjs';
import { REPORT_CATEGORIES } from '../report.mjs';

const PAGES = {
  de: { route: '/inhalte-melden', file: 'legal/inhalte-melden.md', rules: 'regeln', count: '0 / 5.000', privacy: '/datenschutz#meldungen' },
  en: { route: '/en/report', file: 'legal/report.md', rules: 'rules', count: '0 / 5,000', privacy: '/en/privacy#reports' },
};
const source = (locale) => readFileSync(join(CONTENT_DIR, PAGES[locale].file), 'utf8');
const FORMS = { de: matter(source('de')).data.form, en: matter(source('en')).data.form };

const site = buildSite();
const text = (el) => el.text.replace(/\s+/g, ' ').trim();
// The words a reader sees for the inline Markdown in the front matter (links become their text).
const plain = (s) => s.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
const described = (doc, el) => el.getAttribute('aria-describedby').split(' ').map((id) => text(doc.querySelector(`#${id}`)));

for (const [locale, { route, rules, count, privacy }] of Object.entries(PAGES)) {
  const form = FORMS[locale];

  test(`${route}: the form sits between the intro and the rules, posts to /api/report and leaves checking to the browser`, () => {
    const main = site.page(route).querySelector('main');
    const children = main.childNodes.filter((n) => n.nodeType === 1).map((n) => n.tagName.toLowerCase() + (n.id ? `#${n.id}` : '') + (n.hasAttribute?.('data-report') ? '[data-report]' : ''));
    assert.deepEqual(children.slice(0, 4), ['h1', 'p', 'div[data-report]', `h2#${rules}`]);
    const el = main.querySelector('form');
    assert.equal(el.getAttribute('method'), 'post');
    assert.equal(el.getAttribute('action'), '/api/report');
    assert.equal(el.hasAttribute('novalidate'), false, 'native constraint validation explains problems');
  });

  test(`${route}: six reasons in the contract's order with the front matter's words, required`, () => {
    const doc = site.page(route);
    const fieldset = doc.querySelector('fieldset.rf-category');
    assert.equal(text(fieldset.querySelector('legend')), `${form.category.label} ${form.required}`);
    const radios = fieldset.querySelectorAll('input[type="radio"]');
    assert.deepEqual(radios.map((r) => r.getAttribute('value')), REPORT_CATEGORIES);
    assert.ok(radios.every((r) => r.getAttribute('name') === 'category' && r.hasAttribute('required')));
    assert.deepEqual(fieldset.querySelectorAll('label').map(text), REPORT_CATEGORIES.map((key) => form.category.choices[key]));
  });

  test(`${route}: location and reason are required text areas with their help, limits and counter`, () => {
    const doc = site.page(route);
    const location = doc.querySelector('textarea[name="location"]');
    assert.equal(text(doc.querySelector(`label[for="${location.id}"]`)), `${form.location.label} ${form.required}`);
    assert.ok(location.hasAttribute('required'));
    assert.equal(location.getAttribute('maxlength'), '2000');
    assert.deepEqual(described(doc, location), [form.location.help]);

    const reason = doc.querySelector('textarea[name="reason"]');
    assert.equal(text(doc.querySelector(`label[for="${reason.id}"]`)), `${form.reason.label} ${form.required}`);
    assert.ok(reason.hasAttribute('required'));
    assert.equal(reason.getAttribute('minlength'), '20');
    assert.equal(reason.getAttribute('maxlength'), '5000');
    assert.deepEqual(described(doc, reason), [form.reason.help, count], 'help, then the counter in the locale\'s digits');
    const counter = doc.querySelector('#rf-reason-count');
    assert.ok(!counter.hasAttribute('role') && !counter.hasAttribute('aria-live'), 'the counter is no live region');
  });

  test(`${route}: name and e-mail are recommended, share one help text, and fold away only with JavaScript for CSAM`, () => {
    const doc = site.page(route);
    const name = doc.querySelector('input[name="name"]');
    const email = doc.querySelector('input[name="email"]');
    assert.equal(text(doc.querySelector(`label[for="${name.id}"]`)), `${form.name.label} ${form.recommended}`);
    assert.equal(text(doc.querySelector(`label[for="${email.id}"]`)), `${form.email.label} ${form.recommended}`);
    assert.equal(name.getAttribute('maxlength'), '200');
    assert.equal(email.getAttribute('maxlength'), '254');
    assert.equal(email.getAttribute('type'), 'email');
    for (const input of [name, email]) {
      assert.ok(!input.hasAttribute('required'), input.getAttribute('name'));
      assert.deepEqual(described(doc, input), [form.contact_help], input.getAttribute('name'));
    }
    assert.equal(doc.querySelectorAll('#rf-contact-help').length, 1);
    const contact = doc.querySelector('[data-contact]');
    assert.ok(!contact.hasAttribute('hidden'), 'without JavaScript the fields show');
    assert.ok(contact.querySelector('#rf-contact-help'), 'the help folds with the fields');
    const note = doc.querySelector('[data-csam-note]');
    assert.equal(text(note), form.csam_note);
    assert.ok(note.hasAttribute('hidden'), 'without JavaScript the note stays hidden');
    const show = doc.querySelector('[data-show-contact]');
    assert.ok(show.hasAttribute('hidden'));
    assert.equal(text(show.querySelector('button[type="button"]')), form.ui.show_contact);
  });

  test(`${route}: good faith box, honeypot, status line, button, footer line, messages and the done text`, () => {
    const doc = site.page(route);
    const box = doc.querySelector('input[name="good_faith"]');
    assert.equal(box.getAttribute('type'), 'checkbox');
    assert.ok(box.hasAttribute('required'));
    assert.equal(text(box.parentNode), `${form.good_faith} ${form.required}`);

    const trap = doc.querySelector('input[name="website"]');
    assert.equal(trap.getAttribute('tabindex'), '-1');
    assert.equal(trap.getAttribute('autocomplete'), 'off');
    assert.equal(trap.parentNode.getAttribute('aria-hidden'), 'true');
    assert.equal(text(doc.querySelector(`label[for="${trap.id}"]`)), form.ui.honeypot);

    assert.equal(doc.querySelector('form .wl-status').getAttribute('role'), 'alert');
    const submit = doc.querySelector('form button[type="submit"]');
    assert.deepEqual(submit.querySelectorAll('[data-when]').map((s) => [s.getAttribute('data-when'), text(s)]), [['idle', form.submit], ['sending', form.ui.sending]]);

    const footer = doc.querySelector('form .wl-small');
    assert.equal(text(footer), plain(form.footer));
    assert.equal(footer.querySelector('a').getAttribute('href'), privacy);

    for (const key of ['invalid', 'rate_limited', 'unavailable', 'network']) {
      assert.equal(text(doc.querySelector(`[data-message="${key}"]`)), plain(form.ui[key]), key);
    }
    assert.equal(doc.querySelector('[data-message="rate_limited"] a').getAttribute('href'), 'mailto:support@snacklist.app');
    assert.ok(doc.querySelector('.rf-messages').hasAttribute('hidden'));

    const done = doc.querySelector('.rf-done');
    assert.ok(done.hasAttribute('hidden'));
    assert.equal(done.getAttribute('tabindex'), '-1');
    assert.equal(text(done), form.done.replace('{ref}', ''));
    assert.equal(done.querySelector('[data-ref]').innerHTML, '', 'the number goes in at runtime');
  });

  test(`${route}: the page alone loads the report script and styles; its Markdown twin leaves the form out`, () => {
    const head = site.page(route).querySelector('head');
    assert.ok(head.querySelector('script[type="module"][src="/report.js"]'));
    assert.ok(head.querySelector('link[href="/report.css"]'));
    assert.ok(head.querySelector('link[href="/waitlist.css"]'));
    const twin = readFileSync(join(site.outDir, `${route.slice(1)}.md`), 'utf8');
    assert.ok(twin.includes(`## ${locale === 'de' ? 'Regeln für Inhalte' : 'Content rules'}`));
    for (const word of [count, form.submit, form.ui.honeypot, form.category.choices.hate]) assert.ok(!twin.includes(word), word);
  });
}

test('no other page loads the report script or styles', () => {
  for (const route of htmlRoutes(site.outDir).filter((r) => !['/inhalte-melden', '/en/report'].includes(r))) {
    const doc = site.page(route);
    assert.equal(doc.querySelector('script[src="/report.js"], link[href="/report.css"], [data-report]'), null, route);
  }
});

const broken = (from, to) => {
  const text = source('de');
  assert.ok(text.includes(from), from);
  return () => buildSite({ files: { [PAGES.de.file]: text.replace(from, to) } });
};

test('a form front matter with a missing, unknown, empty or non-string key fails the build with file and key', () => {
  const file = /legal\/inhalte-melden\.md: frontmatter field form/;
  assert.throws(broken('      csam: Darstellung sexuellen Kindesmissbrauchs\n', ''), new RegExp(`${file.source}\\.category\\.choices is missing form\\.category\\.choices\\.csam`));
  assert.throws(broken('      other: Anderer Rechtsverstoß\n', '      other: Anderer Rechtsverstoß\n      spam: Spam\n'), /form\.category\.choices has unknown keys form\.category\.choices\.spam/);
  assert.throws(broken('  submit: Meldung senden\n', '  submit: 3\n'), /form\.submit must be a non-empty string/);
  assert.throws(broken('  submit: Meldung senden\n', '  submit: ""\n'), /form\.submit must be a non-empty string/);
  assert.throws(broken('  ui:\n    show_contact', '  ui: []\n  ux:\n    show_contact'), /inhalte-melden\.md: frontmatter field form has unknown keys form\.ux/);
  assert.throws(broken('  location:\n    label: Wo ist der Inhalt?\n', '  location: Wo ist der Inhalt?\n  where:\n    label: x\n'), /form\.location must be a mapping with label, help|unknown keys form\.where/);
  assert.throws(broken('Nummer: {ref}.', 'Nummer folgt.'), /form\.done must hold "\{ref\}" exactly once/);
  assert.throws(broken('form:\n  required: Pflicht\n', 'form: [Pflicht]\nunused:\n  required: Pflicht\n'), /frontmatter field form must be a mapping/);
});

test('a form on anything but a legal page fails the build', () => {
  const body = '# Guide\n\nText.\n';
  const text = guide({ locale: 'en', slug: 'with-form', body }).replace('---\n\n', 'form: {}\n---\n\n');
  assert.throws(() => buildSite({ files: { 'guides/en/with-form.md': text } }), /guides\/en\/with-form\.md: frontmatter field "form" \(the report form\) is only allowed on legal pages/);
});
