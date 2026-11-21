// The round page and the overview. ?lang=de, ?theme=dark, ?ts=200|310, ?device=android.
import { act, backId, initial, scenarios, tickId } from './model.js';
import { all, ids, options } from './options.js';
import { measure, phone, settle, updatePeek } from './phone.js';
import { text } from './text.js';

const params = new URLSearchParams(location.search);
export const env = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: ['200', '310'].includes(params.get('ts')) ? Number(params.get('ts')) : 100,
  device: params.get('device') === 'android' ? 'android' : 'ios',
};
const W = text[env.lang];
const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

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
  ${btn('theme', 'light', W.light)}${btn('theme', 'dark', W.dark)}<span class="sep"></span>
  ${btn('ts', 100, `${W.textSize} 100 %`)}${btn('ts', 200, `${W.textSize} 200 % (${W.androidMax})`)}${btn('ts', 310, `${W.textSize} 310 % (${W.iosMax})`)}<span class="sep"></span>
  ${btn('device', 'ios', 'iPhone 390 × 844')}${btn('device', 'android', 'Android 360 × 640')}</div>`;
const head = (title, back) => `<header class="page-head"><div class="title-row"><h1>${title}</h1>${back ? `<a class="back-link" href="../${location.search}">← ${W.overview}</a>` : ''}</div>
  <p class="note">${W.note}</p>${controls()}</header>`;

// RECOMMENDATION.md on the page: headings, lists, tables, bold, italics and code are all it uses; comments are skipped.
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
    if (l.startsWith('<!--')) continue;
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

// The live phones read RU1's fold from this device (localStorage); a frame never does.
const foldKey = (id) => `ru-folded-${id}`;
export const start = (id, scenario, { live = false } = {}) => {
  const o = options[id];
  const remembered = live && o.remember ? localStorage.getItem(foldKey(id)) === '1' : false;
  return initial(scenario, env.lang, { folded: o.folded || remembered });
};

// The frames of an option: states replayed from the same actions the live phone and verify.mjs use.
export const frameStates = (id) => {
  const s3 = start(id, 'short-3');
  const out = [['short-0', start(id, 'short-0')], ['short-3', s3]];
  if (id === 'today') out.push(['open', act(s3, 'fold')]);
  out.push(['short-15', start(id, 'short-15')], ['long-15', start(id, 'long-15')]);
  const l15 = start(id, 'long-15');
  out.push(['scrolled', id === 'today' ? act(l15, 'fold') : l15, 'recent']);
  out.push(['tick-start', { ...s3, anim: { id: tickId, phase: 'start' } }], ['tick-mid', { ...s3, anim: { id: tickId, phase: 'mid' } }], ['tick-landed', act(s3, `tick:${tickId}`), 'recent']);
  out.push(['back', act(id === 'today' ? act(s3, 'fold') : s3, `back:${backId}`)]);
  if (options[id].limit) out.push(['all', act(start(id, 'short-15'), 'showAll'), 'recent']);
  return out;
};

const cell = (key, html) => {
  const [cap, sub] = W.frames[key];
  return `<figure class="cell" data-frame="${key}"><figcaption>${cap}<small>${sub}</small></figcaption>${html}</figure>`;
};
const frames = (id) => frameStates(id).map(([key, st, show]) => cell(key, phone(st, options[id], env, { show }))).join('');

// A tick: the check flashes (150 ms), the row folds away (250 ms; RU3 shrinks it towards the chips, RU2 sends a ghost
// pill into the peek when the tray is off screen), then the state changes and the landed item fades its highlight.
const tickMotion = async (el, id, rid) => {
  const ph = el.querySelector('.phone');
  const rowEl = ph.querySelector(`[data-row="${rid}"]`);
  if (!rowEl || reduced()) return;
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  rowEl.classList.add('checking');
  await wait(150);
  const h = rowEl.offsetHeight;
  const o = options[id];
  rowEl.style.height = `${h}px`;
  rowEl.classList.add(o.motion === 'shrink' ? 'ru3-shrink' : 'collapsing');
  const peek = ph.querySelector('[data-peek]:not([hidden]) [data-peek-pill]');
  if (o.motion === 'fly' && peek) {
    const screen = ph.querySelector('.screen').getBoundingClientRect();
    const a = rowEl.getBoundingClientRect();
    const b = peek.getBoundingClientRect();
    const g = document.createElement('div');
    g.className = 'ghost';
    g.innerHTML = rowEl.querySelector('.emo').outerHTML + rowEl.querySelector('.nm').innerHTML;
    Object.assign(g.style, { left: `${a.left - screen.left + 16}px`, top: `${a.top - screen.top}px`, height: `${a.height}px` });
    ph.querySelector('.screen').append(g);
    void g.offsetWidth;
    g.style.transform = `translate(${b.left - a.left - 16}px, ${b.top - a.top}px) scale(0.85)`;
    g.style.opacity = '0.4';
  }
  void rowEl.offsetWidth;
  Object.assign(rowEl.style, { height: '0px', minHeight: '0px', opacity: '0', paddingTop: '0px', paddingBottom: '0px' });
  if (o.motion === 'shrink') rowEl.style.transform = 'scale(0.5)';
  await wait(250);
};

const mountLive = (el, id) => {
  const o = options[id];
  let scenario = 'short-3';
  let s = start(id, scenario, { live: true });
  let busy = false;
  const scenes = el.parentElement.querySelector('.states');
  const draw = (keep) => {
    const top = keep ? el.querySelector('[data-scroll]')?.scrollTop ?? 0 : 0;
    el.innerHTML = phone(s, o, env, { live: true });
    const ph = el.querySelector('.phone');
    ph.dataset.keepScroll = '1';
    settle(el);
    const sc = ph.querySelector('[data-scroll]');
    sc.scrollTop = top;
    updatePeek(ph);
    sc.addEventListener('scroll', () => updatePeek(ph), { passive: true });
    for (const b of scenes.querySelectorAll('[data-scene]')) b.setAttribute('aria-pressed', String(b.dataset.scene === scenario));
  };
  const go = (a) => {
    s = act(s, a);
    if (a === 'fold' && o.remember) localStorage.setItem(foldKey(id), s.folded ? '1' : '0');
    draw(true);
  };
  el.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-act]');
    if (!b || busy) return;
    const a = b.dataset.act;
    if (a === 'scrollTray') {
      const ph = el.querySelector('.phone');
      const sc = ph.querySelector('[data-scroll]');
      const sec = ph.querySelector('[data-recent-section]');
      sc.scrollTo({ top: sec.offsetTop - ph.querySelector('[data-topbar]').offsetHeight - 8, behavior: reduced() ? 'auto' : 'smooth' });
      return;
    }
    if (a.startsWith('tick:')) {
      busy = true;
      el.dataset.busy = '1';
      await tickMotion(el, id, a.slice(5));
      busy = false;
      delete el.dataset.busy;
    }
    go(a);
  });
  scenes.addEventListener('click', (e) => {
    const b = e.target.closest('[data-scene]');
    if (!b) return;
    if (b.dataset.scene !== 'reset') scenario = b.dataset.scene;
    s = start(id, scenario, { live: true });
    draw(false);
  });
  draw(false);
};

const sceneKeys = ['short-0', 'short-3', 'short-15', 'long-3', 'long-15', 'reset'];
const cellOf = (m, id, scenario, dev = env.device, ts = env.ts, lang = env.lang) => m?.[lang]?.[dev]?.[ts]?.[scenario]?.[id];
const tsFor = (dev) => (dev === 'ios' ? [100, 310] : [100, 200]);

const meter = (m, id) => {
  const ts = tsFor(env.device).includes(env.ts) ? env.ts : 100;
  const s3 = cellOf(m, id, 'short-3', env.device, ts);
  const l15 = cellOf(m, id, 'long-15', env.device, ts);
  if (!s3 || !l15) return '';
  return `<p class="meter" data-meter>${W.meterLine({ s3: { active: s3.active, recent: s3.recent, to: s3.toFirstRecent }, l15: { active: l15.active, recent: l15.recent, to: l15.toFirstRecent, px: l15.sectionPx } }).replace('iPhone at 100 %', `${env.device === 'ios' ? 'iPhone' : 'Android'} at ${ts} %`).replace('iPhone bei 100 %', `${env.device === 'ios' ? 'iPhone' : 'Android'} bei ${ts} %`)}</p>`;
};

const optionSection = (id, m) => {
  const o = W.options[id];
  const live = `<div class="live"><figure class="cell"><figcaption>${W.liveCap}</figcaption><div class="states">${sceneKeys.map((k) => `<button data-scene="${k}">${W.scenes[k]}</button>`).join('')}</div><div data-live-phone="${id}"></div></figure></div>`;
  const title = id === 'today' ? W.today : `${id} ${o.name}`;
  return `<section class="option" id="${id}"><h2>${title}${m?.pick === id ? `<span class="tag pick">${W.pick}</span>` : ''}${m?.runner === id ? `<span class="tag runner">${W.runner}</span>` : ''}</h2>
    ${id === 'today' ? W.todayFacts : ''}<p>${o.what}</p>${meter(m, id)}
    <div class="frames">${live}${frames(id)}${id === 'today' ? realShots() : ''}</div></section>`;
};

const table = (m) => {
  if (!m) return '';
  const fmt = (c) => (c ? `${c.active} / ${c.recent} / ${c.toFirstRecent ?? '—'}` : '…');
  const rows = all.flatMap((id) => ['ios', 'android'].flatMap((dev) => tsFor(dev).map((ts) => {
    const c = (sc) => cellOf(m, id, sc, dev, ts);
    return `<tr data-row="${id}-${dev}-${ts}"><td><b>${id === 'today' ? W.today : `${id} ${W.options[id].name}`}</b></td><td>${dev === 'ios' ? 'iPhone' : 'Android'} ${ts} %</td>
      <td data-c="short-3">${fmt(c('short-3'))}</td><td data-c="short-15">${fmt(c('short-15'))}</td><td data-c="long-15">${fmt(c('long-15'))}</td><td>${c('short-3')?.sectionPx ?? '…'} / ${c('short-15')?.sectionPx ?? '…'}</td></tr>`;
  })));
  return `<section class="facts" id="table"><h2>${W.tableTitle}</h2><p class="note">${W.tableNote}</p><div class="table-wrap"><table>
    <thead><tr>${W.tableHead.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`;
};

const realShots = () => {
  if (env.device !== 'ios' || env.ts === 200) return '';
  const tag = `${env.lang}-${env.ts}`;
  return ['collapsed', 'expanded'].map((k) => `<figure class="cell" data-frame="real-${k}"><figcaption>${W.real}<small>${tag}-${k}.png</small></figcaption><img class="realshot" src="real/${tag}-${k}.png" width="390" alt="" onerror="this.closest('figure').remove()"></figure>`).join('');
};

// Every scenario in every option at scroll top, for the current lang, device and text size (tools/measure.mjs and
// verify.mjs call this).
export const measureAll = async () => {
  const box = document.createElement('div');
  box.style.cssText = 'position:absolute;left:-5000px;top:0;';
  document.body.append(box);
  const out = {};
  for (const scenario of scenarios) {
    out[scenario] = {};
    for (const id of all) {
      box.innerHTML = phone(start(id, scenario), options[id], env);
      settle(box);
      out[scenario][id] = measure(box.querySelector('.phone'));
    }
  }
  box.remove();
  return out;
};

export const round = async () => {
  await themeCss('../../../../site/public/tokens.css');
  document.title = W.roundTitle;
  document.documentElement.lang = env.lang;
  const m = await fetch('measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  document.body.innerHTML = `${head(W.roundTitle, true)}<main class="view">
    ${all.map((id) => optionSection(id, m)).join('')}
    ${table(m)}
    <section class="rec" id="rec">${md(await fetch(env.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md').then((r) => (r.ok ? r.text() : '')))}</section></main>`;
  document.body.className = `th-${env.theme}`;
  for (const el of document.querySelectorAll('[data-live-phone]')) mountLive(el, el.dataset.livePhone);
  await document.fonts.ready;
  settle(document);
  window.ru = { measureAll };
  document.body.dataset.ready = '1';
};

export const overview = async () => {
  await themeCss('../../../site/public/tokens.css');
  document.title = W.overviewTitle;
  document.documentElement.lang = env.lang;
  const m = await fetch('ru/measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  document.body.innerHTML = `${head(W.overviewTitle, false)}<main class="view"><div class="cards">
    <a class="ocard" href="ru/${location.search}"><h2>${W.roundTitle}</h2><p>${W.roundBlurb}</p>
    ${m?.pick ? `<p><span class="tag pick">${W.pick}</span> ${m.pick} ${W.options[m.pick].name}${m.runner ? ` · <span class="tag runner">${W.runner}</span> ${m.runner} ${W.options[m.runner].name}` : ''}</p>` : ''}</a></div></main>`;
  document.body.className = `th-${env.theme}`;
  document.body.dataset.ready = '1';
};
export { ids };
