// The DSA notice form on /inhalte-melden and /en/report (job 275, Legal Addendum B.3): every word
// comes from the page's `form:` front matter. public/report.js drives it like the waitlist: the
// root's `data-state` names the state, an element with `data-when` shows only in the states it lists.

export const REPORT_CATEGORIES = ['hate', 'personal_rights', 'ip', 'csam', 'danger', 'other'];

// The shape `form:` must have: every key present, no other key, every leaf a non-empty string.
const STRING = 'string';
const FORM_SHAPE = {
  required: STRING,
  recommended: STRING,
  category: { label: STRING, choices: Object.fromEntries(REPORT_CATEGORIES.map((key) => [key, STRING])) },
  location: { label: STRING, help: STRING },
  reason: { label: STRING, help: STRING },
  name: { label: STRING },
  email: { label: STRING },
  'contact_help': STRING,
  'csam_note': STRING,
  'good_faith': STRING,
  footer: STRING,
  submit: STRING,
  done: STRING,
  ui: {
    show_contact: STRING,
    sending: STRING,
    honeypot: STRING,
    invalid: STRING,
    rate_limited: STRING,
    unavailable: STRING,
    network: STRING,
    noscript: STRING,
  },
};

function shapeProblem(value, shape, path) {
  if (shape === STRING) return typeof value === 'string' && value.trim() !== '' ? null : `${path} must be a non-empty string`;
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return `${path} must be a mapping with ${Object.keys(shape).join(', ')}`;
  const missing = Object.keys(shape).filter((key) => !Object.hasOwn(value, key));
  if (missing.length > 0) return `${path} is missing ${missing.map((k) => `${path}.${k}`).join(', ')}`;
  const extra = Object.keys(value).filter((key) => !Object.hasOwn(shape, key));
  if (extra.length > 0) return `${path} has unknown keys ${extra.map((k) => `${path}.${k}`).join(', ')}; it takes ${Object.keys(shape).join(', ')}`;
  for (const [key, inner] of Object.entries(shape)) {
    const problem = shapeProblem(value[key], inner, `${path}.${key}`);
    if (problem) return problem;
  }
  return null;
}

// Why the front matter's `form` can't be rendered, or null.
export function reportFormProblem(form) {
  const problem = shapeProblem(form, FORM_SHAPE, 'form');
  if (problem) return problem;
  if (form.done.split('{ref}').length !== 2) return 'form.done must hold "{ref}" exactly once, where the report number goes';
  return null;
}

// Limits the edge function checks (job 275 contract); the browser checks them first.
const LIMITS = { location: 2000, reason: { min: 20, max: 5000 }, name: 200, email: 254 };

const CHECK = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M9.55 18 3.85 12.3l1.43-1.43 4.27 4.28 9.17-9.18 1.43 1.43Z"/></svg>';

// `inline` renders one line of Markdown (links) to HTML, escaping everything else.
export function reportForm(form, { locale, inline }) {
  const marker = (text) => ` <span class="rf-marker">${inline(text)}</span>`;
  const required = marker(form.required);
  const recommended = marker(form.recommended);
  const choices = REPORT_CATEGORIES.map(
    (key) =>
      `<label class="wl-option rf-choice"><input type="radio" name="category" value="${key}" required><span class="wl-mark"></span><span>${inline(form.category.choices[key])}</span></label>`,
  ).join('\n');
  const count = (n) => new Intl.NumberFormat(locale).format(n);
  const message = (key, text) => `<p data-message="${key}">${inline(text)}</p>`;
  const [beforeRef, afterRef] = inline(form.done).split('{ref}');
  return `<div class="rf-card" data-report data-state="idle">
<noscript><p class="wl-status">${inline(form.ui.noscript)}</p></noscript>
<form class="rf-form" method="post" action="/api/report" data-when="idle sending">
<fieldset class="wl-field rf-category">
<legend>${inline(form.category.label)}${required}</legend>
<div class="rf-choices">
${choices}
</div>
</fieldset>
<div class="wl-field">
<label for="rf-location">${inline(form.location.label)}${required}</label>
<textarea class="wl-input rf-textarea" id="rf-location" name="location" rows="3" required maxlength="${LIMITS.location}" autocomplete="off" aria-describedby="rf-location-help"></textarea>
<p class="wl-hint" id="rf-location-help">${inline(form.location.help)}</p>
</div>
<div class="wl-field">
<label for="rf-reason">${inline(form.reason.label)}${required}</label>
<textarea class="wl-input rf-textarea" id="rf-reason" name="reason" rows="6" required minlength="${LIMITS.reason.min}" maxlength="${LIMITS.reason.max}" autocomplete="off" aria-describedby="rf-reason-help rf-reason-count"></textarea>
<div class="rf-under">
<p class="wl-hint" id="rf-reason-help">${inline(form.reason.help)}</p>
<p class="rf-count" id="rf-reason-count" data-max="${LIMITS.reason.max}">${count(0)} / ${count(LIMITS.reason.max)}</p>
</div>
</div>
<p class="rf-note" data-csam-note hidden>${inline(form.csam_note)}</p>
<p class="rf-show" data-show-contact hidden><button class="rf-link" type="button">${inline(form.ui.show_contact)}</button></p>
<div class="rf-contact" data-contact>
<div class="wl-field">
<label for="rf-name">${inline(form.name.label)}${recommended}</label>
<input class="wl-input" id="rf-name" name="name" type="text" maxlength="${LIMITS.name}" autocomplete="name" aria-describedby="rf-contact-help">
</div>
<div class="wl-field">
<label for="rf-email">${inline(form.email.label)}${recommended}</label>
<input class="wl-input" id="rf-email" name="email" type="email" maxlength="${LIMITS.email}" autocomplete="email" inputmode="email" autocapitalize="off" spellcheck="false" aria-describedby="rf-contact-help">
<p class="wl-hint" id="rf-contact-help">${inline(form.contact_help)}</p>
</div>
</div>
<label class="wl-check rf-check"><input type="checkbox" name="good_faith" required><span class="wl-mark"></span><span>${inline(form.good_faith)}${required}</span></label>
<div class="wl-hp" aria-hidden="true"><label for="rf-website">${inline(form.ui.honeypot)}</label><input id="rf-website" name="website" type="text" tabindex="-1" autocomplete="off"></div>
<p class="wl-status" role="alert"></p>
<button class="hex wl-submit" type="submit"><span class="face"><span data-when="idle">${inline(form.submit)}</span><span data-when="sending" hidden>${inline(form.ui.sending)}</span></span></button>
<p class="wl-small">${inline(form.footer)}</p>
<div class="rf-messages" hidden>
${['invalid', 'rate_limited', 'unavailable', 'network'].map((key) => message(key, form.ui[key])).join('\n')}
</div>
</form>
<div class="wl-done rf-done" data-when="done" hidden tabindex="-1">
<span class="tick hxp" aria-hidden="true">${CHECK}</span>
<p>${beforeRef}<strong data-ref></strong>${afterRef}</p>
</div>
</div>
`;
}

// The form goes after the page's intro, before its first section (Legal: the rules follow the form).
export function insertReportForm(body, formHtml) {
  const at = body.indexOf('<h2');
  return at === -1 ? body + formHtml : body.slice(0, at) + formHtml + body.slice(at);
}
