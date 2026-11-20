// Round AM's page. ?lang=de, ?theme=dark, ?ts=200|310, ?device=android.
import { cell, controls, env, md, themeCss } from '../page.js';
import { act, copy, initial, run, summary } from './model.js';
import { ids, options, phone, settle } from './phone.js';
import { classify, frames, outcomes, paths, words } from './walk.js';
import { text } from './text.js';

const W = text[env.lang];

// What Enter does on the exact open match and on the ticked one, from the reducer.
export const enterOutcome = (id, scenario, lang) => {
  const before = run([`type:${words[scenario][lang]}`], lang, options[id]);
  return classify(before, act(before, 'enter', lang, options[id]), scenario === 'ticked' ? 't0' : 'o0');
};
const taps = (id, o) => paths[id][o]?.[1].length ?? null;

const head = () => `<header class="page-head"><div class="title-row"><h1>${W.roundTitle}</h1><a class="back-link" href="../${location.search}">← ${W.overview}</a></div>
  <p class="note">${W.note}</p>${controls()}</header>`;

const mountLive = (el, id) => {
  const opt = options[id];
  let s = initial(env.lang);
  let n = 0;
  const draw = (focus = true) => {
    el.innerHTML = phone(s, opt, env, { live: true });
    settle(el);
    el.dataset.taps = String(n);
    el.dataset.items = JSON.stringify(summary(s, env.lang));
    const f = el.querySelector('[data-input="text"]');
    if (focus && f) {
      f.focus();
      f.setSelectionRange(f.value.length, f.value.length);
    }
  };
  const go = (a) => {
    s = act(s, a, env.lang, opt);
    draw();
  };
  el.addEventListener('click', (e) => {
    if (e.target.closest('input')) return;
    const b = e.target.closest('[data-act]');
    if (!b) return;
    n += 1;
    go(b.dataset.act);
  });
  el.addEventListener('input', (e) => {
    const f = e.target.dataset.input;
    go(`${f === 'text' ? 'type' : f}:${e.target.value}`);
  });
  el.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.target.dataset.input === 'text') {
      n += 1;
      go('enter');
    }
  });
  el.reset = () => {
    s = initial(env.lang);
    n = 0;
    draw();
  };
  draw(false);
};

const optionSection = (id, m) => {
  const o = W.options[id];
  const name = (x) => W.outcomeName[x];
  const st = (key) => frames(id, env.lang).find(([k]) => k === key)[1];
  const outcomeOf = { exactEnter: name(enterOutcome(id, 'exact', env.lang)), tickedEnter: name(enterOutcome(id, 'ticked', env.lang)) };
  const tapsOf = { merged: taps(id, 'merge'), tickedOff: taps(id, 'tick') };
  const mm = m?.ios?.[id];
  const meter = W.meterLine({
    enter: name(enterOutcome(id, 'exact', env.lang)), enterTicked: name(enterOutcome(id, 'ticked', env.lang)),
    tick: taps(id, 'tick') ?? '–', merge: taps(id, 'merge'), new: taps(id, 'new'), back: taps(id, 'back'), h3: mm?.several ?? '…',
  });
  return `<section class="option" id="${id}"><h2>${id} ${o.name}${m?.pick === id ? `<span class="tag pick">${W.pick}</span>` : ''}${m?.runner === id ? `<span class="tag runner">${W.runner}</span>` : ''}</h2>
    <p>${o.what}</p><p class="meter">${meter}</p>
    <div class="frames">
      <div class="live">${cell(W.liveCap, `<div data-live-phone="${id}"></div>`)}<button class="resetbtn" data-reset="${id}">${W.reset}</button><p class="hint">${W.liveHint}</p></div>
      ${W.frameOrder
        .map(([k, cap, sub]) => {
          const acts = st(k);
          const small = typeof sub === 'function' ? sub(outcomeOf[k], tapsOf[k]) : sub;
          return acts ? cell(cap, phone(run(acts, env.lang, options[id]), options[id], env), small, k) : cell(cap, `<div class="phone-none ${env.device}"></div>`, small, k);
        })
        .join('')}
    </div></section>`;
};

const fitsText = (f) => {
  if (!f) return '';
  const de = env.lang === 'de';
  if (f.max === 0) return de ? 'nein' : 'no';
  return f.max === f.largest ? `${de ? 'ja' : 'yes'} (100–${f.largest} %)` : `${de ? 'bis' : 'up to'} ${f.max} %`;
};

// measured.json lists the English app strings; the page shows them in its language.
const uiWord = (w) => copy[env.lang][Object.keys(copy.en).find((k) => copy.en[k] === w)] ?? w;

const table = (m) => {
  if (!m) return '';
  const rows = ids.map((id) => {
    const t = (o) => taps(id, o) ?? W.notOffered;
    return `<tr><td><b>${id} ${W.options[id].name}</b></td><td>${W.outcomeName[enterOutcome(id, 'exact', env.lang)]}</td><td>${W.outcomeName[enterOutcome(id, 'ticked', env.lang)]}</td>
      ${['tick', 'merge', 'new', 'back'].map((o) => `<td>${t(o)}</td>`).join('')}
      <td>${m.ios[id].one} / ${m.android[id].one} px</td><td>${m.ios[id].several} / ${m.android[id].several} px</td>
      ${['ios', 'android'].map((d) => `<td>${fitsText(m[d].fitsOne[id])}; ${fitsText(m[d].fits[id])}</td>`).join('')}<td>${m.words[id].length ? m.words[id].map(uiWord).join(', ') : '–'}</td></tr>`;
  });
  return `<section class="facts" id="table"><h2>${W.tableTitle}</h2><p class="note">${W.tableNote(m)}</p><div class="table-wrap"><table>
    <thead><tr>${W.tableHead.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`;
};

export const round = async () => {
  await themeCss('../../../../site/public/tokens.css');
  document.title = W.roundTitle;
  const m = await fetch('measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  document.body.innerHTML = `${head()}<main class="view">
    <section class="facts" id="today"><h2>${W.today}</h2>${W.todayFacts}</section>
    <section class="facts" id="outcomes"><h2>${W.outcomesTitle}</h2>${W.outcomes}</section>
    ${ids.map((id) => optionSection(id, m)).join('')}
    ${table(m)}
    <section class="rec" id="rec">${md(await fetch(W.recFile).then((r) => (r.ok ? r.text() : '')))}</section></main>`;
  for (const el of document.querySelectorAll('[data-live-phone]')) mountLive(el, el.dataset.livePhone);
  for (const b of document.querySelectorAll('[data-reset]')) b.addEventListener('click', () => document.querySelector(`[data-live-phone="${b.dataset.reset}"]`).reset());
  await document.fonts.ready;
  settle(document);
  document.body.dataset.ready = '1';
};

export { outcomes };
