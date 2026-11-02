// The waitlist's parts of the site (job 82, docs/WAITLIST.md): the sign-up form on the landing
// pages, the questions under it, and the pages behind the links in the mails, where a button
// confirms an address or deletes a sign-up. public/waitlist.js drives them: every element with
// `data-when` shows only in the states it lists, and the page's `data-state` names the current one.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { CopyError } from './landing.mjs';

export const WAITLIST_ANCHOR = { de: 'warteliste', en: 'waitlist' };

export const ACTION_PAGES = {
  confirm: { de: '/de/warteliste/bestaetigen', en: '/en/waitlist/confirm' },
  unsubscribe: { de: '/de/warteliste/abmelden', en: '/en/waitlist/unsubscribe' },
};

// Messages public/waitlist.js copies into a field's error or the status line, by key.
const MESSAGES = {
  'email-missing': 'waitlist.error.email-missing',
  'email-invalid': 'waitlist.error.email-invalid',
  'platform-missing': 'waitlist.error.platform-missing',
  invalid_request: 'waitlist.error.invalid-request',
  rate_limited: 'waitlist.error.rate-limited',
  unavailable: 'waitlist.error.unavailable',
  network: 'waitlist.error.network',
};

const FAQ = ['what', 'when', 'cost', 'account', 'email', 'install-ios', 'install-android', 'wrong-email', 'no-invite'];

const messages = ({ el }, keys) =>
  `<div class="wl-messages" hidden>\n${keys.map((key) => el('p', MESSAGES[key], `data-message="${key}"`)).join('\n')}\n</div>`;

const PRIVACY = { de: '/datenschutz', en: '/en/privacy' };

// The consent text under the button: the newest content/legal/consent/waitlist-<locale>-v<n>.md
// per locale, one paragraph of inline Markdown. Its file name is the version the form sends.
export function readConsent(contentDir) {
  const dir = join(contentDir, 'legal/consent');
  const files = existsSync(dir) ? readdirSync(dir) : [];
  return Object.fromEntries(
    Object.keys(WAITLIST_ANCHOR).map((locale) => {
      const pattern = new RegExp(`^waitlist-${locale}-v(\\d+)\\.md$`);
      const newest = files.filter((f) => pattern.test(f)).sort((a, b) => Number(pattern.exec(b)[1]) - Number(pattern.exec(a)[1]))[0];
      if (!newest) throw new CopyError(`content/legal/consent/waitlist-${locale}-v1.md is missing: the waitlist form shows its consent text`);
      const markdown = readFileSync(join(dir, newest), 'utf8').trim();
      if (markdown === '' || /\n\s*\n/.test(markdown)) throw new CopyError(`content/legal/consent/${newest} must be one paragraph`);
      if (!markdown.includes(`](${PRIVACY[locale]})`)) throw new CopyError(`content/legal/consent/${newest} must link the privacy policy, ${PRIVACY[locale]}`);
      return [locale, { version: newest.slice(0, -3), markdown }];
    }),
  );
}

export function signupForm({ locale, reader, consent, anchor }) {
  const { text, md, el, inline } = reader;
  return `<section class="wl-card" id="${anchor}" aria-labelledby="wl-title" data-waitlist="signup" data-state="idle">
<form class="wl-form" novalidate data-when="idle sending">
${el('h2', 'waitlist.form.title', 'class="title" id="wl-title"')}
${el('p', 'waitlist.form.intro', 'class="wl-intro"')}
<div class="wl-field">
${el('label', 'waitlist.form.email', 'for="wl-email"')}
<input class="wl-input" id="wl-email" name="email" type="email" required autocomplete="email" inputmode="email" autocapitalize="off" spellcheck="false" maxlength="254" placeholder="${text('waitlist.form.email-placeholder')}" aria-describedby="wl-email-hint">
${el('p', 'waitlist.form.email-hint', 'class="wl-hint" id="wl-email-hint"')}
<p class="wl-error" id="wl-email-error" hidden></p>
</div>
<fieldset class="wl-field wl-platform">
${el('legend', 'waitlist.form.platform')}
<div class="wl-options">
<label class="wl-option"><input type="radio" name="platform" value="ios" required><span class="wl-mark"></span><span data-copy-id="waitlist.form.ios">${md('waitlist.form.ios')}</span></label>
<label class="wl-option"><input type="radio" name="platform" value="android" required><span class="wl-mark"></span><span data-copy-id="waitlist.form.android">${md('waitlist.form.android')}</span></label>
</div>
<p class="wl-error" id="wl-platform-error" hidden></p>
</fieldset>
<label class="wl-check"><input type="checkbox" name="launch_news"><span class="wl-mark"></span><span data-copy-id="waitlist.form.launch-news">${md('waitlist.form.launch-news')}</span></label>
<div class="wl-hp" aria-hidden="true">${el('label', 'waitlist.form.honeypot', 'for="wl-website"')}<input id="wl-website" name="website" type="text" tabindex="-1" autocomplete="off"></div>
<p class="wl-status" role="alert"></p>
<button class="hex wl-submit" type="submit"><span class="face"><span data-copy-id="waitlist.cta" data-when="idle">${md('waitlist.cta')}</span><span data-copy-id="waitlist.form.sending" data-when="sending" hidden>${md('waitlist.form.sending')}</span></span></button>
<p class="wl-consent" data-legal="${consent.version}">${inline(consent.markdown)}</p>
${messages(reader, Object.keys(MESSAGES))}
</form>
<div class="wl-done" data-when="done" hidden tabindex="-1">
<span class="tick hxp" aria-hidden="true">${CHECK}</span>
${el('h2', 'waitlist.thanks.title', 'class="title"')}
${el('p', 'waitlist.thanks.body')}
${el('p', 'waitlist.thanks.small', 'class="wl-small"')}
</div>
</section>`;
}

const CHECK = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M9.55 18 3.85 12.3l1.43-1.43 4.27 4.28 9.17-9.18 1.43 1.43Z"/></svg>';

export function faqItems({ el }) {
  return FAQ.map(
    (key) => `<details class="faq-item">
${el('summary', `waitlist.faq.${key}.q`)}
${el('p', `waitlist.faq.${key}.a`)}
</details>`,
  ).join('\n');
}

// A page behind a mail link: the values sit in the fragment, and nothing happens until the
// button is pressed (mail scanners open links). States: ready, sending, failed (the button
// again, with a message), then done or invalid.
const back = (locale, { md }) => `<p><a class="link-strong" href="/${locale}" data-copy-id="waitlist.back">${md('waitlist.back')}</a></p>`;
const ACTIONS = {
  confirm: {
    done: 'confirmed',
    button: 'hex',
    afterDone: (locale, reader) => `${reader.el('p', 'waitlist.confirm.done-line')}\n${back(locale, reader)}`,
    afterInvalid: (locale, { md }) => `<p><a class="hex" href="/${locale}#${WAITLIST_ANCHOR[locale]}"><span class="face" data-copy-id="waitlist.cta">${md('waitlist.cta')}</span></a></p>`,
  },
  unsubscribe: { done: 'deleted', button: 'hex hex--tomato', afterDone: back, afterInvalid: back },
};

export function actionPage(action, { locale, reader }) {
  const { el, md } = reader;
  const { done, button, afterDone, afterInvalid } = ACTIONS[action];
  const id = (name) => `waitlist.${action}.${name}`;
  return `<div class="wl-page" data-waitlist="${action}" data-state="ready">
<h1 id="wl-heading" tabindex="-1"><span data-copy-id="${id('title')}" data-when="ready sending failed">${md(id('title'))}</span><span data-copy-id="${id('done-title')}" data-when="${done}" hidden>${md(id('done-title'))}</span><span data-copy-id="${id('invalid-title')}" data-when="invalid" hidden>${md(id('invalid-title'))}</span></h1>
<div class="wl-panel" data-when="ready sending failed">
${el('p', id('body'))}
<p class="wl-status" role="alert"></p>
<button class="${button} wl-action" type="button"><span class="face"><span data-copy-id="${id('button')}" data-when="ready failed">${md(id('button'))}</span><span data-copy-id="waitlist.form.sending" data-when="sending" hidden>${md('waitlist.form.sending')}</span></span></button>
</div>
<div class="wl-panel" data-when="${done}" hidden>
${el('p', id('done-body'))}
${afterDone(locale, reader)}
</div>
<div class="wl-panel" data-when="invalid" hidden>
${el('p', id('invalid-body'))}
${afterInvalid(locale, reader)}
</div>
${messages(reader, ['rate_limited', 'unavailable', 'network', 'invalid_request'])}
</div>`;
}
