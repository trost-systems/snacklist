// The DSA notice form on /inhalte-melden and /en/report (job 275, site/report.mjs). The browser's
// own constraint validation explains a missing or too short field; this script adds the edge
// function's rules the attributes can't say (trimmed text, code points, the address pattern),
// the character counter, the CSAM toggle and the request. Every word comes from the page.

// The edge function's rules (job 275 contract): trimmed, counted in code points.
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
// Control characters but line breaks and tabs, which a location or reason may hold.
const CONTROL = /(?![\n\r\t])\p{Cc}/u;
const LINE_CONTROL = /\p{Cc}/u;
const points = (s) => [...s].length;

const show = (root, state) => {
  root.dataset.state = state;
  for (const el of root.querySelectorAll('[data-when]')) el.hidden = !el.dataset.when.split(' ').includes(state);
};

const say = (root, target, key) => {
  const template = root.querySelector(`[data-message="${key}"]`);
  target.replaceChildren(...(template ? template.cloneNode(true).childNodes : []));
};

const STATUS_MESSAGES = { 400: 'invalid', 429: 'rate_limited' };

function report(root) {
  const form = root.querySelector('form');
  const field = (name) => form.elements.namedItem(name);
  const [location, reason, name, email, website, goodFaith] = ['location', 'reason', 'name', 'email', 'website', 'good_faith'].map(field);
  const radios = [...form.querySelectorAll('input[name="category"]')];
  const status = form.querySelector('.wl-status');
  const counter = form.querySelector('#rf-reason-count');
  const note = form.querySelector('[data-csam-note]');
  const showContact = form.querySelector('[data-show-contact]');
  const contact = form.querySelector('[data-contact]');
  const invalidText = root.querySelector('[data-message="invalid"]').textContent;
  const number = new Intl.NumberFormat(document.documentElement.lang);
  const max = Number(counter.dataset.max);
  let contactAsked = false;

  const category = () => radios.find((r) => r.checked)?.value ?? null;

  // Problems the attributes miss; an empty field is left to `required`.
  const rules = [
    [location, (v) => v === '' || (points(v.trim()) >= 1 && points(v.trim()) <= 2000 && !CONTROL.test(v))],
    [reason, (v) => v === '' || (points(v.trim()) >= 20 && points(v.trim()) <= max && !CONTROL.test(v))],
    [name, (v) => v.trim() === '' || (points(v.trim()) <= 200 && !LINE_CONTROL.test(v))],
    [email, (v) => v.trim() === '' || (v.trim().length <= 254 && !LINE_CONTROL.test(v) && EMAIL.test(v.trim()))],
  ];
  const check = () => {
    for (const [input, ok] of rules) input.setCustomValidity(ok(input.value) ? '' : invalidText);
  };

  const count = () => {
    counter.textContent = `${number.format(points(reason.value))} / ${number.format(max)}`;
  };

  // Child sexual abuse material can be reported without name and address: those fields fold away
  // behind a button, unless something is typed in them already.
  const toggle = () => {
    const csam = category() === 'csam';
    if (csam && (name.value.trim() !== '' || email.value.trim() !== '')) contactAsked = true;
    const hide = csam && !contactAsked;
    note.hidden = !csam;
    contact.hidden = hide;
    // A disabled field is left out of validation; its value stays for when it shows again.
    name.disabled = hide;
    email.disabled = hide;
    showContact.hidden = !hide;
  };

  showContact.querySelector('button').addEventListener('click', () => {
    contactAsked = true;
    toggle();
    name.focus();
  });
  for (const radio of radios) radio.addEventListener('change', toggle);
  form.addEventListener('input', check);
  reason.addEventListener('input', count);
  count();
  check();
  toggle();

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (root.dataset.state === 'sending') return;
    check();
    if (!form.reportValidity()) return;
    status.replaceChildren();
    show(root, 'sending');
    const hidden = contact.hidden;
    try {
      const response = await fetch('/api/report', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          locale: document.documentElement.lang,
          category: category(),
          location: location.value.trim(),
          reason: reason.value.trim(),
          name: hidden ? '' : name.value.trim(),
          email: hidden ? '' : email.value.trim(),
          good_faith: goodFaith.checked,
          website: website.value,
        }),
        credentials: 'omit',
        cache: 'no-store',
      });
      const data = await response.json().catch(() => null);
      if (response.status === 201 && typeof data?.ref === 'string') {
        root.querySelector('[data-ref]').textContent = data.ref;
        show(root, 'done');
        const done = root.querySelector('.rf-done');
        // The form folds away under the reader; bring the number to them, not just the focus.
        done.focus({ preventScroll: true });
        done.scrollIntoView({ block: 'center' });
        return;
      }
      show(root, 'idle');
      say(root, status, STATUS_MESSAGES[response.status] ?? 'unavailable');
    } catch {
      show(root, 'idle');
      say(root, status, 'network');
    }
  });
}

for (const root of document.querySelectorAll('[data-report]')) report(root);
