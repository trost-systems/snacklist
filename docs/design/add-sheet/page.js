// A round's page: back link, controls, the phones side by side (one at a time on a phone), the measured table and the
// recommendation. The round comes from <body data-round>; its options, scenarios and frames from <round>/options.js.
import { Phone, esc } from './sandbox.js';

const dir = document.body.dataset.round;
const { round } = await import(`./${dir}/options.js`);
const params = new URLSearchParams(location.search);
const scenIds = Object.keys(round.scenarios);
const S = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: params.get('ts') === '200' ? 200 : 100,
  scen: scenIds.includes(params.get('scen')) ? params.get('scen') : scenIds[0],
  motion: params.get('motion') === 'reduce' || matchMedia('(prefers-reduced-motion: reduce)').matches ? 'reduce' : 'full',
  cell: 0,
};
const W = {
  en: { back: 'Prototype overview', light: 'Light', dark: 'Dark', text: 'Text', largest: 'largest (200 %)', scen: 'Scenario', table: 'Comparison (measured)', tableNote: 'Measured by verify.mjs in Chromium on the 390 × 844 phone; the same numbers are in RECOMMENDATION.md.', motion: 'Reduced motion', pick: 'Pick', runner: 'Runner-up', reset: 'Reset phones' },
  de: { back: 'Prototypen-Übersicht', light: 'Hell', dark: 'Dunkel', text: 'Text', largest: 'größte (200 %)', scen: 'Szenario', table: 'Vergleich (gemessen)', tableNote: 'Gemessen von verify.mjs in Chromium auf dem 390 × 844 Telefon; dieselben Zahlen stehen in RECOMMENDATION.de.md.', motion: 'Reduzierte Bewegung', pick: 'Wahl', runner: 'Zweite Wahl', reset: 'Telefone zurücksetzen' },
}[S.lang];
const L = (o) => (typeof o === 'string' ? o : o?.[S.lang] ?? '');
// Today and the RI control have no code of their own: their name is their label.
const coded = (o) => /^[A-Z]{2}\d$/.test(o.id);
const label = (o) => (coded(o) ? o.id : L(o.name));
const cells = round.options.flatMap((o) => round.frames.map((f) => ({ o, f })));

export const phones = {};
const mountPhones = () => {
  for (const host of document.querySelectorAll('[data-host]')) {
    const o = round.options.find((x) => x.id === host.dataset.opt);
    const ph = new Phone({ opt: o, lang: S.lang, theme: S.theme, ts: S.ts, list: round.list, latency: round.latency?.(S.scen) ?? 0, frozen: true, motion: S.motion });
    round.setup(ph, S.scen, host.dataset.frame);
    ph.mount(host);
    phones[`${o.id}:${host.dataset.frame}`] = ph;
  }
};

// A play drives every phone of the round at once: open, type the word key by key, the reply after its latency.
const play = (p) => {
  const word = { en: 'Milk', de: 'Milch' }[S.lang];
  for (const ph of Object.values(phones)) {
    ph.wake();
    ph.latency = p.latency ?? round.latency(S.scen);
    ph.close();
    ph.sheet.open = false;
    ph.open();
    ph.cache = {};
    ph.render();
    [...word].forEach((_, i) =>
      setTimeout(() => {
        ph.type(word.slice(0, i + 1));
        ph.render();
      }, i * p.gap),
    );
  }
};

const btn = (k, v, text, on) => `<button data-set="${k}" data-v="${v}" aria-pressed="${on}">${esc(text)}</button>`;
const controls = () => `<div class="controls">
  <div class="group" data-group="scenario"><span class="lbl">${esc(L(round.scenarioLabel) || W.scen)}</span>${scenIds.map((k) => btn('scen', k, L(round.scenarios[k].name), S.scen === k)).join('')}</div>
  ${round.plays ? `<div class="group" data-group="plays">${round.plays.map((p) => `<button data-play="${p.id}">▶ ${esc(L(p.name))}</button>`).join('')}${btn('motion', S.motion === 'reduce' ? 'full' : 'reduce', W.motion, S.motion === 'reduce')}</div>` : ''}
  <div class="group" data-group="look">${btn('lang', 'en', 'English', S.lang === 'en')}${btn('lang', 'de', 'Deutsch', S.lang === 'de')}<span class="sep"></span>${btn('theme', 'light', W.light, S.theme === 'light')}${btn('theme', 'dark', W.dark, S.theme === 'dark')}<span class="sep"></span>${btn('ts', '100', `${W.text} 100 %`, S.ts === 100)}${btn('ts', '200', `${W.text} ${W.largest}`, S.ts === 200)}<span class="sep"></span><button data-reset="1">${W.reset}</button></div>
</div>`;

const tag = (o) => (o.id === round.rec.pick ? `<span class="tag pick">${W.pick}</span>` : o.id === round.rec.runnerUp ? `<span class="tag runner">${W.runner}</span>` : '');
const grid = () => `<div class="strip" role="tablist">${cells.map(({ o, f }, i) => `<button role="tab" data-cell="${i}" aria-selected="${i === S.cell}">${esc(label(o))} · ${esc(L(f.name).split(',')[0])}</button>`).join('')}</div>
  <div class="grid">${round.options
    .map(
      (o) => `<section class="option" data-option="${o.id}"><header class="opt-h"><h2><b>${esc(label(o))}</b> ${coded(o) ? esc(L(o.name)) : ''} ${tag(o)}</h2><p class="muted">${esc(L(o.line))}</p></header>
      <div class="frames">${round.frames
        .map((f) => {
          const i = cells.findIndex((c) => c.o === o && c.f === f);
          return `<figure class="cell ${i === S.cell ? 'on' : ''}" data-cell-i="${i}"><figcaption>${esc(L(f.name))}</figcaption><div class="host" data-host data-opt="${o.id}" data-frame="${f.id}"></div></figure>`;
        })
        .join('')}</div></section>`,
    )
    .join('')}</div>`;

let measured = null;
const table = () => {
  const tb = measured?.table?.[S.lang];
  if (!tb) return '';
  return `<section class="rec" data-testid="comparison"><h2>${W.table}</h2><div class="table-wrap"><table class="cmp"><tr>${tb.cols.map((c) => `<th>${esc(c)}</th>`).join('')}</tr>${tb.rows
    .map((r, i) => `<tr data-row="${round.options[i]?.id}" class="${round.options[i]?.id === round.rec.pick ? 'pick' : ''}">${r.map((c, j) => `<td data-col="${j}">${j ? esc(c) : `<b>${esc(c)}</b>`}</td>`).join('')}</tr>`)
    .join('')}</table></div><p class="note">${W.tableNote}</p></section>`;
};

// Just enough Markdown for the recommendation files: headings, paragraphs, bullets, numbered lists, bold, code.
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
      if (block.startsWith('<!--') || lines[0].startsWith('|')) return '';
      if (lines.every((l) => /^\s*- /.test(l) || /^\s{2,}\S/.test(l))) return `<ul>${block.split(/\n(?=- )/).map((l) => `<li>${inline(l.replace(/^- /, '').replace(/\n\s+/g, ' '))}</li>`).join('')}</ul>`;
      if (/^\d+\. /.test(lines[0])) return `<ol>${block.split(/\n(?=\d+\. )/).map((l) => `<li>${inline(l.replace(/^\d+\. /, '').replace(/\n\s+/g, ' '))}</li>`).join('')}</ol>`;
      return `<p>${inline(block.replace(/\n/g, ' '))}</p>`;
    })
    .join('');
const recHtml = {};

const render = () => {
  document.documentElement.lang = S.lang;
  document.title = L(round.title);
  for (const k of Object.keys(phones)) delete phones[k];
  const back = `${document.body.dataset.overview}${S.lang === 'de' ? '?lang=de' : ''}`;
  document.getElementById('app').innerHTML = `<header class="page-head"><div class="title-row"><a class="back-link" href="${back}" data-testid="back">← ${W.back}</a><h1>${esc(L(round.title))}</h1></div>
    <p class="note compare">${esc(L(round.compare))}</p>${controls()}</header>
    <main class="view" data-scen="${S.scen}">${grid()}${table()}<article class="rec" data-testid="rec">${recHtml[S.lang] ?? ''}</article></main>`;
  mountPhones();
};

const syncUrl = () => {
  const q = new URLSearchParams();
  if (S.lang === 'de') q.set('lang', 'de');
  if (S.theme === 'dark') q.set('theme', 'dark');
  if (S.ts === 200) q.set('ts', '200');
  if (S.scen !== scenIds[0]) q.set('scen', S.scen);
  if (S.motion === 'reduce') q.set('motion', 'reduce');
  history.replaceState(null, '', `${location.pathname}${q.size ? `?${q}` : ''}`);
};

document.addEventListener('click', (e) => {
  const set = e.target.closest('[data-set]');
  if (set) {
    const { set: k, v } = set.dataset;
    S[k] = k === 'ts' ? Number(v) : v;
    syncUrl();
    if (k === 'lang') return location.reload();
    return render();
  }
  if (e.target.closest('[data-reset]')) return render();
  const p = e.target.closest('[data-play]');
  if (p) return play(round.plays.find((x) => x.id === p.dataset.play));
  const c = e.target.closest('[data-cell]');
  if (c) {
    S.cell = Number(c.dataset.cell);
    document.querySelectorAll('[data-cell]').forEach((b) => b.setAttribute('aria-selected', String(b === c)));
    document.querySelectorAll('.cell').forEach((f) => f.classList.toggle('on', f.dataset.cellI === c.dataset.cell));
    const host = document.querySelector('.cell.on [data-host]');
    phones[`${host.dataset.opt}:${host.dataset.frame}`]?.render();
  }
});

// The phone gets both themes from the app's tokens, independent of the device setting.
const themeTokens = async () => {
  const css = await (await fetch(document.querySelector('link[data-tokens]').href)).text();
  const light = css.match(/:root\s*{([^}]*)}/)[1];
  const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];
  const st = document.createElement('style');
  st.textContent = `.th-light{${light}color-scheme:light}.th-dark{${dark}color-scheme:dark}`;
  document.head.append(st);
};
const load = async () => {
  const get = async (f) => {
    const res = await fetch(new URL(`./${dir}/${f}`, import.meta.url));
    return res.ok ? res.text() : '';
  };
  measured = JSON.parse((await get('measured.json')) || 'null');
  for (const [lang, f] of [['en', 'RECOMMENDATION.md'], ['de', 'RECOMMENDATION.de.md']]) recHtml[lang] = markdown(await get(f));
};

await Promise.all([themeTokens(), load(), document.fonts.ready]);
await Promise.all(['400 15px Inter', '800 20px "Bricolage Grotesque"'].map((f) => document.fonts.load(f)));
render();
window.__page = { phones, round, S, play, render };
