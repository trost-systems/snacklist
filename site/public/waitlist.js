// The waitlist form on /de and /en and the pages behind the mail links (job 82, docs/WAITLIST.md).
// Each [data-waitlist] root has a state in data-state; an element with data-when shows only in
// the states it lists. Messages are copied from the page's [data-message] templates, so every
// word stays in content/landing/copy.yml.
(() => {
  // The same rule the edge function applies (docs/WAITLIST.md, "Edge function waitlist").
  const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  const CONTROL = /\p{Cc}/u;
  const emailProblem = (value) => {
    if (value === '') return 'email-missing';
    if (value.length > 254 || CONTROL.test(value) || !EMAIL.test(value)) return 'email-invalid';
    return null;
  };

  const show = (root, state) => {
    root.dataset.state = state;
    for (const el of root.querySelectorAll('[data-when]')) el.hidden = !el.dataset.when.split(' ').includes(state);
  };

  const say = (root, target, key) => {
    const template = root.querySelector(`[data-message="${key}"]`);
    target.replaceChildren(...(template ? template.cloneNode(true).childNodes : []));
  };

  // The server's answer by status; a failed request throws, which the callers show as "network".
  const post = async (path, body) => {
    const response = await fetch(path, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
      credentials: 'omit',
      cache: 'no-store',
    });
    const data = await response.json().catch(() => null);
    return { status: response.status, error: data?.error, result: data?.status };
  };

  const failure = (status) => (status === 429 ? 'rate_limited' : status === 400 ? 'invalid_request' : 'unavailable');

  function signup(root) {
    const form = root.querySelector('form');
    const loaded = performance.now();
    const status = form.querySelector('.wl-status');
    const email = form.elements.namedItem('email');
    const radios = [...form.querySelectorAll('input[name="platform"]')];
    const fields = {
      email: { inputs: [email], error: form.querySelector('#wl-email-error'), hint: email.getAttribute('aria-describedby') },
      platform: { inputs: radios, error: form.querySelector('#wl-platform-error'), hint: null },
    };

    const mark = (name, key) => {
      const { inputs, error, hint } = fields[name];
      error.hidden = key === null;
      if (key === null) error.replaceChildren();
      else say(root, error, key);
      for (const input of inputs) {
        input.setAttribute('aria-invalid', String(key !== null));
        const ids = [hint, key === null ? null : error.id].filter(Boolean).join(' ');
        if (ids) input.setAttribute('aria-describedby', ids);
        else input.removeAttribute('aria-describedby');
      }
    };
    const problems = () => ({
      email: emailProblem(email.value.trim()),
      platform: radios.some((r) => r.checked) ? null : 'platform-missing',
    });

    // Once an error shows, it follows the input, so it goes away as soon as the value is fine.
    email.addEventListener('input', () => {
      if (email.getAttribute('aria-invalid') === 'true') mark('email', problems().email);
    });
    for (const radio of radios) radio.addEventListener('change', () => mark('platform', null));

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (root.dataset.state === 'sending') return;
      status.replaceChildren();
      const found = problems();
      for (const name of Object.keys(fields)) mark(name, found[name]);
      const first = Object.keys(fields).find((name) => found[name] !== null);
      if (first) {
        fields[first].inputs[0].focus();
        return;
      }
      show(root, 'sending');
      try {
        const answer = await post('/api/waitlist', {
          email: email.value.trim(),
          platform: radios.find((r) => r.checked).value,
          locale: document.documentElement.lang,
          launch_news: form.elements.namedItem('launch_news').checked,
          consent_version: form.querySelector('[data-legal]').dataset.legal,
          website: form.elements.namedItem('website').value,
          elapsed_ms: Math.round(performance.now() - loaded),
        });
        if (answer.status === 202) {
          show(root, 'done');
          root.querySelector('.wl-done').focus();
          return;
        }
        show(root, 'idle');
        const field = answer.status === 400 && { invalid_email: ['email', 'email-invalid'], invalid_platform: ['platform', 'platform-missing'] }[answer.error];
        if (field) {
          mark(...field);
          fields[field[0]].inputs[0].focus();
        } else say(root, status, failure(answer.status));
      } catch {
        show(root, 'idle');
        say(root, status, 'network');
      }
    });
  }

  // Confirm and unsubscribe: the values come in the fragment and go out only on the button.
  const ACTIONS = {
    confirm: { done: 'confirmed', body: (p) => ({ token: p.get('t') }) },
    unsubscribe: { done: 'deleted', body: (p) => ({ id: p.get('id'), sig: p.get('s') }) },
  };

  function action(root, name) {
    const { done, body } = ACTIONS[name];
    const values = body(new URLSearchParams(location.hash.slice(1)));
    const languages = [...document.querySelectorAll('nav.lang a')];
    const heading = root.querySelector('#wl-heading');
    const status = root.querySelector('.wl-status');
    const finish = (state) => {
      history.replaceState(null, '', location.pathname);
      for (const a of languages) a.hash = '';
      show(root, state);
      heading.focus();
    };
    if (Object.values(values).some((v) => !v)) {
      show(root, 'invalid');
      return;
    }
    for (const a of languages) a.hash = location.hash;
    root.querySelector('.wl-action').addEventListener('click', async () => {
      if (root.dataset.state === 'sending') return;
      status.replaceChildren();
      show(root, 'sending');
      try {
        const answer = await post(`/api/waitlist/${name}`, values);
        if (answer.status === 200 && [done, 'invalid'].includes(answer.result)) return finish(answer.result);
        show(root, 'failed');
        say(root, status, failure(answer.status));
      } catch {
        show(root, 'failed');
        say(root, status, 'network');
      }
    });
  }

  for (const root of document.querySelectorAll('[data-waitlist]')) {
    const kind = root.dataset.waitlist;
    if (kind === 'signup') signup(root);
    else action(root, kind);
  }
})();
