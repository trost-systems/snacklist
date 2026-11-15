import { flows, T as chrome } from './flows.js';
import { scenarios, signals, maxDebug } from './model.js';
import { scenKeys, row, debugSignals, debugPoints, exposure, exposureLabel } from './metrics.js';
import { esc, ic } from './ui.js';

const params = new URLSearchParams(location.search);
const S = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: ['100', '130', '200'].includes(params.get('ts')) ? params.get('ts') : '100',
  scen: scenKeys.includes(params.get('scen')) ? params.get('scen') : 'bug',
  view: 'overview',
};
const byId = Object.fromEntries(flows.map((f) => [f.id, f]));
const viewOf = (h) => (byId[h] ? h : h === 'rec' ? 'rec' : 'overview');
S.view = viewOf(location.hash.slice(2));

// Per flow: the attachment switches (shared by its storyboard and its Try-it phone) and the Try-it phone's state.
const att = {};
const tryit = {};
const resetFlow = (f) => {
  att[f.id] = { ...f.defaults };
  tryit[f.id] = { state: f.path[S.scen][0], trail: [] };
};
flows.forEach(resetFlow);

const P = {
  en: {
    title: 'Feedback experience (FB1–FB5)', back: 'All prototype rounds', overview: 'Overview', rec: 'Recommendation',
    compare: 'Five end-to-end ways for users to tell Peter what is wrong or what they want, next to Today (main’s More → Send feedback). Each shows how to enter (and its shake decision), what goes with the note, how it is sent, what the user sees afterwards and what Peter reads.',
    scenario: 'Scenario', light: 'Light', dark: 'Dark', text: 'Text',
    steps: { enter: 'Enter', attach: 'What goes with it', send: 'How it is sent', after: 'Afterwards', peter: 'What Peter reads', also: 'Also' },
    shake: 'Shake', tryIt: 'Try it', shakeBtn: 'Shake the phone', noShake: 'A shake does nothing here', reset: 'Start again',
    tapsSoFar: (n) => `${n} ${n === 1 ? 'action' : 'actions'} so far`, sentAfter: (n) => `Sent after ${n} ${n === 1 ? 'action' : 'actions'}.`,
    table: 'Comparison', cols: ['Option', 'Taps to send (wrong category · change rejected · idea)', `Debug value (points of ${maxDebug}, same order)`, 'Privacy exposure', 'Build effort (estimate)', 'Existing service', 'User hears back', 'Shake'],
    tapsNote: `Taps are measured by driving each path in verify.mjs, the same situation for every option: a shake or long-press counts as one action, typing does not. Debug value weighs what Peter gets by default: the exact error or the user’s own case 3 each (he can fix it without asking back), a screenshot or the last steps 2 each (he can reproduce it), screen, version and system, display, and feature switches 1 each; ${maxDebug} is everything. Privacy exposure is in points: 1 per field sent by default, +2 per list field sent by default, +1 for a field that can carry list content by the user’s choice, +2 per new processor and +1 if it keeps data in the US (low ≤ 5, medium ≤ 8).`,
    days: (d) => (d ? `${d} days` : 'none (live)'), none: 'none, today’s stack', levels: { low: 'low', medium: 'medium', high: 'high' },
    open: 'Open', signals: 'Signals Peter gets here by default', namesItem: ', names the item',
    shakeModes: { none: 'none', on: 'on by default', confirm: 'on, asks first', contextual: 'only near an error', optin: 'opt-in', off: 'off by design' },
  },
  de: {
    title: 'Feedback-Erlebnis (FB1–FB5)', back: 'Alle Prototyp-Runden', overview: 'Überblick', rec: 'Empfehlung',
    compare: 'Fünf durchgehende Wege, wie Nutzer Peter sagen, was nicht stimmt oder was sie sich wünschen, neben Heute (Mehr → Feedback senden auf main). Jeder zeigt den Einstieg (und die Entscheidung zum Schütteln), was mitgeht, wie es gesendet wird, was man danach sieht und was Peter liest.',
    scenario: 'Szenario', light: 'Hell', dark: 'Dunkel', text: 'Text',
    steps: { enter: 'Einstieg', attach: 'Was mitgeht', send: 'Wie es gesendet wird', after: 'Danach', peter: 'Was Peter liest', also: 'Außerdem' },
    shake: 'Schütteln', tryIt: 'Ausprobieren', shakeBtn: 'Telefon schütteln', noShake: 'Schütteln tut hier nichts', reset: 'Neu starten',
    tapsSoFar: (n) => `bisher ${n} ${n === 1 ? 'Aktion' : 'Aktionen'}`, sentAfter: (n) => `Gesendet nach ${n} ${n === 1 ? 'Aktion' : 'Aktionen'}.`,
    table: 'Vergleich', cols: ['Variante', 'Tipps bis gesendet (falsche Kategorie · Änderung abgelehnt · Idee)', `Nutzen fürs Debuggen (Punkte von ${maxDebug}, gleiche Reihenfolge)`, 'Datenschutz-Exposition', 'Bauaufwand (Schätzung)', 'Fertiger Dienst', 'Rückmeldung an Nutzer', 'Schütteln'],
    tapsNote: `Die Tipps misst verify.mjs, indem es jeden Weg durchspielt, für jede Variante dieselbe Situation: Schütteln oder langes Drücken zählt als eine Aktion, Tippen von Text nicht. Nutzen fürs Debuggen gewichtet, was Peter ohne Zutun bekommt: der genaue Fehler oder der eigene Fall je 3 (er kann es ohne Nachfrage beheben), ein Bildschirmfoto oder die letzten Schritte je 2 (er kann es nachstellen), Bildschirm, Version und System, Anzeige und Funktionsschalter je 1; ${maxDebug} ist alles. Datenschutz in Punkten: 1 je standardmäßig gesendetem Feld, +2 je Listenfeld, das standardmäßig mitgeht, +1 für ein Feld, das auf Wunsch Listeninhalt tragen kann, +2 je neuem Auftragsverarbeiter und +1, wenn er Daten in den USA hält (niedrig ≤ 5, mittel ≤ 8).`,
    days: (d) => (d ? `${d} Tage` : 'keiner (live)'), none: 'keiner, unser Stack', levels: { low: 'niedrig', medium: 'mittel', high: 'hoch' },
    open: 'Öffnen', signals: 'Signale, die Peter hier standardmäßig bekommt', namesItem: ', nennt den Eintrag',
    shakeModes: { none: 'keins', on: 'standardmäßig an', confirm: 'an, fragt erst', contextual: 'nur nahe an einem Fehler', optin: 'zum Einschalten', off: 'bewusst aus' },
  },
};
const W = () => P[S.lang];
const name = (f) => f.name[S.lang];
const label = (f) => (f.id === 'today' ? (S.lang === 'de' ? 'Heute' : 'Today') : f.id);

const ctx = (f, over = {}) => ({ lang: S.lang, scen: S.scen, T: chrome[S.lang], att: { ...att[f.id], ...over } });
const gesturesOf = (f) => (typeof f.gestures === 'function' ? f.gestures(S.scen) : (f.gestures ?? {}));

const phone = (f, state, { over, live } = {}) =>
  `<div class="phone th-${S.theme}" data-flow="${f.id}" data-state="${state}" ${live ? 'data-live="1"' : ''} style="--ts:${Number(S.ts) / 100};--tsn:${Math.min(1.5, Number(S.ts) / 100)}">${f.screens[state](ctx(f, over))}<div class="homeind"><i></i></div></div>`;

const btn = (k, v, text) => `<button data-set="${k}" data-v="${v}" aria-pressed="${S[k] === v}">${text}</button>`;
const controls = () => `<div class="controls">
  <div class="group"><a class="btn" href="#/" aria-current="${S.view === 'overview'}" ${S.view === 'overview' ? 'style="background:var(--hl-color-honey);color:var(--hl-color-on-honey)"' : ''}>${W().overview}</a>${flows
    .map((f) => `<a class="btn" href="#/${f.id}" ${S.view === f.id ? 'style="background:var(--hl-color-honey);color:var(--hl-color-on-honey)" aria-current="page"' : ''}>${label(f)}</a>`)
    .join('')}<a class="btn" href="#/rec" ${S.view === 'rec' ? 'style="background:var(--hl-color-honey);color:var(--hl-color-on-honey)" aria-current="page"' : ''}>${W().rec}</a></div>
  <div class="group"><span class="lbl">${W().scenario}</span>${scenKeys.map((k) => btn('scen', k, scenarios[k].label[S.lang])).join('')}</div>
  <div class="group">${btn('lang', 'en', 'English')}${btn('lang', 'de', 'Deutsch')}<span class="sep"></span>${btn('theme', 'light', W().light)}${btn('theme', 'dark', W().dark)}<span class="sep"></span>${['100', '130', '200'].map((t) => btn('ts', t, `${W().text} ${t} %`)).join('')}</div>
</div>`;

const shakeTag = (f) => `<span class="tag">${ic('vibration', 'xs')} ${W().shakeModes[f.shake.mode]}</span>`;
const svcTag = (f) => (f.service ? `<span class="tag svc">${esc(f.service[S.lang])}</span>` : `<span class="tag stack">${W().none}</span>`);

const table = () => {
  const rows = flows.map((f) => ({ f, r: row(f) }));
  return `<section class="rec" data-testid="comparison"><h2>${W().table}</h2><div class="table-wrap"><table class="cmp"><tr>${W().cols.map((c) => `<th>${c}</th>`).join('')}</tr>${rows
    .map(
      ({ f, r }) => `<tr data-row="${f.id}" class="${f.id === REC.pick ? 'pick' : ''}"><td><b>${label(f)}</b><br><small>${esc(name(f))}</small></td><td class="num" data-taps="${r.taps.join(',')}">${r.taps.join(' · ')}</td><td class="num" data-debug="${r.debug.join(',')}">${r.debug.join(' · ')}</td><td data-exposure="${r.exposure}">${W().levels[exposureLabel(r.exposure)]} (${r.exposure})${r.listByDefault ? W().namesItem : ''}</td><td data-build="${r.build}">${W().days(r.build)}</td><td data-service="${r.service ? 1 : 0}">${f.service ? esc(f.service[S.lang]) : W().none}</td><td>${esc(f.answer[S.lang])}</td><td>${W().shakeModes[f.shake.mode]}</td></tr>`,
    )
    .join('')}</table></div><p class="note">${W().tapsNote}</p>${flows
    .filter((f) => f.tapsNote)
    .map((f) => `<p class="note">${label(f)}: ${esc(f.tapsNote[S.lang])}.</p>`)
    .join('')}</section>`;
};

const REC = { pick: 'FB3', runnerUp: 'FB2' };
let recHtml = { en: '', de: '' };

const overview = () => `<section class="cards">${flows
    .map((f) => `<a class="card" href="#/${f.id}" data-card="${f.id}"><span><b class="id">${label(f)}</b> ${f.id === REC.pick ? `<span class="tag pick">${S.lang === 'de' ? 'Empfehlung' : 'Pick'}</span>` : f.id === REC.runnerUp ? `<span class="tag">${S.lang === 'de' ? 'Zweite Wahl' : 'Runner-up'}</span>` : ''}</span><b>${esc(name(f))}</b><span class="muted">${esc(f.line[S.lang])}</span><span>${shakeTag(f)} ${svcTag(f)}</span></a>`)
    .join('')}</section>
  ${table()}<article class="rec" data-testid="rec">${recHtml[S.lang]}</article>`;

const stepNo = { enter: 1, attach: 2, send: 3, after: 4, peter: 5, also: '+' };
const caption = (f, fr) =>
  `<figcaption><span class="step"><i>${stepNo[fr.step]}</i>${W().steps[fr.step]}</span><span>${esc((fr.caption ?? f.facts[fr.step])[S.lang])}</span></figcaption>`;

const storyboard = (f) =>
  `<div class="story" data-testid="story">${f
    .story(S.scen)
    .map((fr) => {
      const body =
        fr.step === 'send' ? f.route(ctx(f)) : fr.step === 'peter' ? `<div class="desk-stack">${f.peter(ctx(f))}</div>` : phone(f, fr.state, { over: fr.att });
      return `<figure data-step="${fr.step}" ${fr.state ? `data-frame-state="${fr.state}"` : ''}>${caption(f, fr)}${fr.shake ? `<span class="tag">${ic('vibration', 'xs')} ${W().shakeBtn}</span>` : ''}${body}</figure>`;
    })
    .join('')}</div>`;

const tryPane = (f) => {
  const st = tryit[f.id];
  const shakeTo = gesturesOf(f)[st.state]?.shake;
  const sent = st.state === f.path[S.scen].at(-1);
  return `<h3 class="try-h">${W().tryIt}</h3><div class="try" data-testid="try"><div>${phone(f, st.state, { live: true })}</div><div class="try-side">
    <button class="gesture" data-shake="${shakeTo ?? ''}" ${shakeTo ? '' : 'disabled'} data-testid="shake">${ic('vibration', 'sm')} ${shakeTo ? W().shakeBtn : W().noShake}</button>
    <p class="trail" data-testid="trail" data-count="${st.trail.length}">${sent ? W().sentAfter(st.trail.length) : W().tapsSoFar(st.trail.length)}${st.trail.length ? `: ${st.trail.map(esc).join(' → ')}` : ''}</p>
    <button class="gesture" data-reset="1">${ic('undo', 'sm')} ${W().reset}</button></div></div>`;
};

const optionView = (f) => {
  const sig = debugSignals(f, S.scen);
  const pts = exposure(f, S.scen);
  return `<section class="opt-head"><h2>${label(f)} · ${esc(name(f))}</h2><p>${esc(f.line[S.lang])}</p>
  <details class="facts-box" ${matchMedia('(max-width: 440px)').matches ? '' : 'open'}><summary>${S.lang === 'de' ? 'Die fünf Schritte, Schütteln, Aufwand' : 'The five steps, shake, effort'}</summary><dl class="facts"><dt>${W().shake}</dt><dd data-testid="shake-decision">${shakeTag(f)} ${esc(f.shake.text[S.lang])}</dd>${['enter', 'attach', 'send', 'after', 'peter']
    .map((s) => `<dt>${W().steps[s]}</dt><dd data-fact="${s}">${esc(f.facts[s][S.lang])}</dd>`)
    .join('')}<dt>${W().cols[4]}</dt><dd>${W().days(f.build.days)}: ${esc(f.build.text[S.lang])}</dd><dt>${W().signals}</dt><dd>${sig.map((s) => signals[s][S.lang]).join(', ') || '–'} (${debugPoints(f, S.scen)}/${maxDebug}) · ${W().cols[3]}: ${W().levels[exposureLabel(pts)]} (${pts})</dd></dl></details></section>
  ${storyboard(f)}${tryPane(f)}`;
};

const render = () => {
  document.documentElement.lang = S.lang;
  document.title = W().title;
  const f = byId[S.view];
  const body = f ? optionView(f) : S.view === 'rec' ? `${table()}<article class="rec" data-testid="rec">${recHtml[S.lang]}</article>` : overview();
  const overviewHref = document.body.dataset.overview;
  const html = `<header class="page-head"><div class="title-row"><a class="back-link" href="${overviewHref}?lang=${S.lang}" data-testid="back">← ${W().back}</a><h1>${W().title}</h1></div><p class="note">${W().compare}</p>${controls()}</header><main class="view" data-view="${S.view}" data-scen="${S.scen}">${body}</main>`;
  document.getElementById('app').innerHTML = html;
  // The Try-it phone outlines what leads on along the shortest path.
  if (f) {
    const path = f.path[S.scen];
    const next = path[path.indexOf(tryit[f.id].state) + 1];
    if (next) document.querySelector(`[data-live] [data-go="${next}"]`)?.classList.add('next');
  }
};

const syncUrl = () => {
  const q = new URLSearchParams();
  if (S.lang === 'de') q.set('lang', 'de');
  if (S.theme === 'dark') q.set('theme', 'dark');
  if (S.ts !== '100') q.set('ts', S.ts);
  if (S.scen !== 'bug') q.set('scen', S.scen);
  history.replaceState(null, '', `${location.pathname}${q.size ? `?${q}` : ''}${location.hash}`);
};

const move = (f, to, how) => {
  const st = tryit[f.id];
  st.trail.push(how);
  st.state = to;
};

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-set],[data-go],[data-tog],[data-shake],[data-reset]');
  if (!el) return;
  if (el.dataset.set) {
    S[el.dataset.set] = el.dataset.v;
    if (el.dataset.set === 'scen') flows.forEach(resetFlow);
    syncUrl();
    return render();
  }
  const f = byId[S.view];
  if (!f) return;
  if (el.dataset.reset) {
    resetFlow(f);
    return render();
  }
  if (el.dataset.shake) {
    move(f, el.dataset.shake, S.lang === 'de' ? 'schütteln' : 'shake');
    render();
    const p = document.querySelector('[data-live]');
    p?.classList.add('shaken');
    return;
  }
  if (el.dataset.tog) {
    e.preventDefault();
    const k = el.dataset.tog;
    att[f.id][k] = !att[f.id][k];
    return render();
  }
  // Only the Try-it phone moves; the storyboard frames are fixed moments.
  if (el.dataset.go && el.closest('[data-live]')) {
    const what = el.dataset.gesture === 'long-press' ? (S.lang === 'de' ? 'lange drücken' : 'long-press') : (el.textContent.trim() || el.getAttribute('aria-label') || el.dataset.go).slice(0, 40);
    move(f, el.dataset.go, what);
    render();
  }
});
addEventListener('hashchange', () => {
  S.view = viewOf(location.hash.slice(2));
  render();
  scrollTo(0, 0);
});

// The phone gets both themes from the site tokens, independent of the device setting.
const themeTokens = async () => {
  const css = await (await fetch(document.querySelector('link[data-tokens]').href)).text();
  const light = css.match(/:root\s*{([^}]*)}/)[1];
  const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];
  const st = document.createElement('style');
  st.textContent = `.th-light{${light}color-scheme:light}.th-dark{${dark}color-scheme:dark}`;
  document.head.append(st);
};

// Just enough Markdown for RECOMMENDATION*.md: headings, paragraphs, bullets, numbered lists, one table, bold, code.
const inline = (t) => esc(t).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`(.+?)`/g, '<code>$1</code>');
const markdown = (md) =>
  md
    .trim()
    .split(/\n{2,}/)
    .map((block) => {
      const lines = block.split('\n');
      if (block.startsWith('### ')) return `<h3>${inline(block.slice(4))}</h3>`;
      if (block.startsWith('## ')) return `<h3>${inline(block.slice(3))}</h3>`;
      if (block.startsWith('# ')) return `<h2>${inline(block.slice(2))}</h2>`;
      if (block.startsWith('<!--')) return '';
      if (lines.every((l) => l.startsWith('- '))) return `<ul>${lines.map((l) => `<li>${inline(l.slice(2))}</li>`).join('')}</ul>`;
      if (lines.every((l) => /^\d+\. /.test(l))) return `<ol>${lines.map((l) => `<li>${inline(l.replace(/^\d+\. /, ''))}</li>`).join('')}</ol>`;
      if (lines[0].startsWith('|')) {
        const cells = (l) => l.split('|').slice(1, -1).map((c) => c.trim());
        const [head, , ...rest] = lines;
        return `<div class="table-wrap"><table class="cmp"><tr>${cells(head).map((c) => `<th>${inline(c)}</th>`).join('')}</tr>${rest.map((r) => `<tr>${cells(r).map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</table></div>`;
      }
      return `<p>${inline(block)}</p>`;
    })
    .join('');

const loadRec = async () => {
  for (const [lang, file] of [['en', 'RECOMMENDATION.md'], ['de', 'RECOMMENDATION.de.md']]) {
    const res = await fetch(new URL(file, import.meta.url));
    // The page shows the pick, reasons and questions; the table above it is the live one, so the file's copy is skipped.
    recHtml[lang] = res.ok ? markdown((await res.text()).replace(/<!-- table -->[\s\S]*?<!-- \/table -->/, '')) : '';
  }
};

await Promise.all([themeTokens(), loadRec(), document.fonts.ready]);
render();
