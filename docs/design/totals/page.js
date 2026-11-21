// The round page and the overview. ?lang=de, ?theme=dark, ?ts=200|310, ?device=android.
import { ids, options } from './blocks.js';
import { act, initial, stateIds } from './model.js';
import { phone, settle } from './phone.js';
import { text } from './text.js';

const params = new URLSearchParams(location.search);
export const env = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: ['200', '310'].includes(params.get('ts')) ? Number(params.get('ts')) : 100,
  device: params.get('device') === 'android' ? 'android' : 'ios',
};
const W = text[env.lang];

// The app's tokens, light or dark on a class, so a phone can carry its theme.
const themeCss = async (href) => {
  const css = await (await fetch(href)).text();
  const light = css.match(/:root\s*{([^}]*)}/)[1];
  const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];
  const st = document.createElement('style');
  st.textContent = `.th-light{${light}}.th-dark{${dark}}`;
  document.head.append(st);
};

const link = (k, v) => {
  const p = new URLSearchParams(location.search);
  p.set(k, v);
  if ((k === 'lang' && v === 'en') || (k === 'theme' && v === 'light') || (k === 'ts' && v === 100) || (k === 'device' && v === 'ios')) p.delete(k);
  const q = p.toString();
  return `${location.pathname}${q ? `?${q}` : ''}${location.hash}`;
};
const btn = (k, v, label) => `<button aria-pressed="${String(env[k]) === String(v)}" onclick="location.href='${link(k, v)}'">${label}</button>`;
const controls = () => `<div class="controls"><span class="lbl">${W.lang}</span>${btn('lang', 'en', 'English')}${btn('lang', 'de', 'Deutsch')}<span class="sep"></span>
  <span class="lbl">${W.themeLbl}</span>${btn('theme', 'light', W.light)}${btn('theme', 'dark', W.dark)}<span class="sep"></span>
  <span class="lbl">${W.textSize}</span>${btn('ts', 100, '100 %')}${btn('ts', 200, `200 % (${W.androidMax})`)}${btn('ts', 310, `310 % (${W.iosMax})`)}<span class="sep"></span>
  <span class="lbl">${W.phoneLbl}</span>${btn('device', 'ios', 'iPhone 390 × 844')}${btn('device', 'android', 'Android 360 × 640')}</div>`;
const head = (title, back) => `<header class="page-head"><div class="title-row"><h1>${title}</h1>${back ? `<a class="back-link" href="../${location.search}">← ${W.overview}</a>` : ''}</div>
  <p class="note">${W.note}</p>${controls()}</header>`;

// RECOMMENDATION.md on the page: headings, lists, tables, bold, italics and code are all it uses.
const md = (src) => {
  const inline = (x) => x.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>').replace(/\*([^*]+)\*/g, '<i>$1</i>');
  const out = [];
  let list = null;
  const close = () => {
    if (list) out.push(`</${list}>`);
    list = null;
  };
  const lines = src.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const l = lines[i];
    if (l.startsWith('|')) {
      close();
      const rows = [];
      while (lines[i]?.startsWith('|')) rows.push(lines[i++].split('|').slice(1, -1).map((c) => c.trim()));
      i -= 1;
      out.push(`<div class="table-wrap"><table><thead><tr>${rows[0].map((c) => `<th>${inline(c)}</th>`).join('')}</tr></thead><tbody>${rows.slice(2).map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`);
    } else if (/^#{1,3} /.test(l)) {
      close();
      const n = l.indexOf(' ');
      out.push(`<h${n + 1}>${inline(l.slice(n + 1))}</h${n + 1}>`);
    } else if (/^(\d+\.|-) /.test(l)) {
      const kind = l.startsWith('-') ? 'ul' : 'ol';
      if (list !== kind) {
        close();
        out.push(`<${kind}>`);
        list = kind;
      }
      out.push(`<li>${inline(l.replace(/^(\d+\.|-) /, ''))}</li>`);
    } else if (/^\s+\S/.test(l) && list) {
      out[out.length - 1] = out[out.length - 1].replace(/<\/li>$/, `<br>${inline(l.trim())}</li>`);
    } else if (l.trim()) {
      close();
      out.push(`<p>${inline(l)}</p>`);
    }
  }
  close();
  return out.join('');
};

const cell = (caption, html, small = '', key = '') => `<figure class="cell"${key ? ` data-frame="${key}"` : ''}><figcaption>${caption}${small ? `<small>${small}</small>` : ''}</figcaption>${html}</figure>`;

// The live phone: tap a chip to price an item, a row to buy it on a trip, the option's own controls; the state
// buttons above it set (a) to (d).
const mountLive = (el, id) => {
  let s = initial('a');
  const states = el.parentElement.querySelector('.states');
  const draw = () => {
    el.innerHTML = phone(s, options[id], env, { live: true });
    settle(el);
    for (const b of states.querySelectorAll('button')) b.setAttribute('aria-pressed', String(b.dataset.state === s.preset));
  };
  el.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    e.stopPropagation();
    const a = b.dataset.act;
    if (a.startsWith('jump:')) {
      el.querySelector(`[data-divider="${a.slice(5)}"]`)?.scrollIntoView({ block: 'start' });
      return;
    }
    s = { ...act(s, a), preset: null };
    draw();
  });
  states.addEventListener('click', (e) => {
    const b = e.target.closest('[data-state]');
    if (!b) return;
    s = { ...initial(b.dataset.state), preset: b.dataset.state };
    draw();
  });
  s.preset = 'a';
  draw();
};

const frame = (id, st, extra = {}, show = '') => phone({ ...initial(st), ...extra }, options[id], env, { show });
const frames = (id) => {
  const list = stateIds.map((st) => cell(W.states[st], frame(id, st), W.stateSub[st], st));
  if (id === 'TE1') list.push(cell(W.states.b1, frame(id, 'b1'), W.stateSub.b1, 'b1'));
  if (id === 'TE2') list.push(cell(W.extra.TE2, frame(id, 'b', { open: true }), '', 'b-open'));
  if (id === 'TE5') list.push(cell(W.extra.TE5, frame(id, 'b', { sheet: true }), '', 'b-sheet'));
  if (id === 'TE3') list.push(cell(W.extra.TE3, frame(id, 'b', {}, 'lidl'), '', 'b-top'));
  return list.join('');
};

const meter = (m, id) => {
  const r = m?.[env.device]?.[env.ts];
  if (!r) return '';
  const g = (o, st) => r[o][st].h;
  const sv = (st) => r[id][st].saved;
  return `<p class="meter">${W.meterLine({ a: g(id, 'a'), b: g(id, 'b'), c: g(id, 'c'), d: g(id, 'd'), ta: g('today', 'a'), tb: g('today', 'b'), tc: g('today', 'c'), td: g('today', 'd'), sa: sv('a'), sb: sv('b'), sc: sv('c'), sd: sv('d') })}</p>`;
};

const optionSection = (id, m) => {
  const o = W.options[id];
  return `<section class="option" id="${id}"><h2>${id} ${o.name}${m?.pick === id ? `<span class="tag pick">${W.pick}</span>` : ''}${m?.runner === id ? `<span class="tag runner">${W.runner}</span>` : ''}</h2>
    <p>${o.what}</p>${meter(m, id)}
    <div class="frames">
      <div class="live">${cell(W.liveCap, `<div class="states">${stateIds.map((st) => `<button data-state="${st}">${W.states[st]}</button>`).join('')}</div><div data-live-phone="${id}"></div>`)}</div>
      ${frames(id)}
    </div></section>`;
};

const table = (m) => {
  if (!m) return '';
  const rows = [];
  for (const id of ['today', ...ids]) {
    for (const [dev, ts] of [['ios', 100], ['ios', 310], ['android', 100], ['android', 200]]) {
      const r = m[dev][ts][id];
      const de = m[dev][ts].de?.[id];
      const cut = (st) => (r[st].cut ? `, ${W.cut}` : de?.[st].cut ? ` (${W.german}: ${W.cut})` : '');
      const cellOf = (st) => `${r[st].h} px${de && de[st].h !== r[st].h ? ` (${W.german} ${de[st].h})` : ''}${id === 'today' ? '' : `, ${W.saved(r[st].saved)}`}${cut(st)}`;
      rows.push(`<tr data-row="${id}-${dev}-${ts}"><td><b>${id === 'today' ? W.today : `${id} ${W.options[id].name}`}</b></td><td>${dev === 'ios' ? 'iPhone' : 'Android'} ${ts} %</td>${stateIds.map((st) => `<td data-state="${st}">${cellOf(st)}</td>`).join('')}</tr>`);
    }
  }
  return `<section class="facts" id="table"><h2>${W.tableTitle}</h2><p class="note">${W.tableNote}</p><div class="table-wrap"><table>
    <thead><tr>${W.tableHead.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`;
};

export const round = async () => {
  await themeCss('../../../../site/public/tokens.css');
  document.title = W.roundTitle;
  const m = await fetch('measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  const real = `real/${env.lang}-${env.theme}-${env.device === 'android' ? '100-android' : env.ts === 310 ? '310' : '100'}-a.png`;
  document.body.innerHTML = `${head(W.roundTitle, true)}<main class="view">
    <section class="facts" id="today"><h2>${W.today}</h2>${W.todayFacts}${meter(m, 'today').replace(/Rows saved.*<\/b>\./, '').replace(/Gesparte Zeilen.*<\/b>\./, '')}
      <div class="frames">${[...stateIds, 'b1'].map((st) => cell(W.states[st], frame('today', st), W.stateSub[st], st)).join('')}
      ${cell(W.real, `<img class="realshot" src="${real}" width="${env.device === 'android' ? 360 : 390}" alt="" onerror="this.closest('figure').remove()">`)}</div></section>
    ${ids.map((id) => optionSection(id, m)).join('')}
    ${table(m)}
    <section class="rec" id="rec">${md(await fetch(env.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md').then((r) => (r.ok ? r.text() : '')))}</section></main>`;
  document.body.className = `th-${env.theme}`;
  for (const el of document.querySelectorAll('[data-live-phone]')) mountLive(el, el.dataset.livePhone);
  await document.fonts.ready;
  settle(document);
  document.body.dataset.ready = '1';
};

export const overview = async () => {
  await themeCss('../../../site/public/tokens.css');
  document.title = W.overviewTitle;
  const m = await fetch('te/measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  document.body.innerHTML = `${head(W.overviewTitle, false)}<main class="view"><div class="cards">
    <a class="ocard" href="te/${location.search}"><h2>${W.roundTitle}</h2><p>${W.roundBlurb}</p>
    ${m?.pick ? `<p><span class="tag pick">${W.pick}</span> ${m.pick} ${W.options[m.pick].name} · <span class="tag runner">${W.runner}</span> ${m.runner} ${W.options[m.runner].name}</p>` : ''}</a></div></main>`;
  document.body.className = `th-${env.theme}`;
  document.body.dataset.ready = '1';
};
