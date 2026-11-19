// The round page and the overview. ?lang=de, ?theme=dark, ?ts=200|310, ?device=android.
import { act, initial, run } from './model.js';
import { options, phone, settle } from './phone.js';
import { frames, storeCat, todayFrame } from './walk.js';
import { text } from './text.js';

const params = new URLSearchParams(location.search);
const env = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: ['200', '310'].includes(params.get('ts')) ? Number(params.get('ts')) : 100,
  device: params.get('device') === 'android' ? 'android' : 'ios',
};
const W = text[env.lang];
const ids = ['AS1', 'AS2', 'AS3', 'AS4', 'AS5'];

// The app's tokens, light or dark on a class, so both themes can sit on one page.
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

const cell = (caption, html, small = '') => `<figure class="cell"><figcaption>${caption}${small ? `<small>${small}</small>` : ''}</figcaption>${html}</figure>`;

// The live phone: click through it like the app. Typing in the field suggests; Enter adds the first row.
const lives = new Map();
const mountLive = (el, id) => {
  let s = initial();
  const draw = (focusName) => {
    el.innerHTML = phone(s, options[id], env, { live: true });
    settle(el);
    if (focusName) {
      const f = el.querySelector(`[data-input="${focusName}"]`);
      if (f) {
        f.focus();
        f.setSelectionRange(f.value.length, f.value.length);
      }
    }
    el.dataset.taps = String(taps);
  };
  let taps = 0;
  const go = (a, focusName) => {
    s = act(s, a, env.lang);
    draw(focusName);
  };
  el.addEventListener('click', (e) => {
    if (e.target.closest('input')) return;
    const b = e.target.closest('[data-act]');
    if (!b || b.hasAttribute('data-inert')) return;
    taps += 1;
    const a = b.dataset.act;
    go(a, a.startsWith('open:details') ? 'details' : 'text');
  });
  el.addEventListener('input', (e) => {
    const f = e.target.dataset.input;
    go(`${f === 'text' ? 'type' : f}:${e.target.value}`, f);
  });
  el.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.target.dataset.input) go('enter', 'text');
  });
  let y0 = null;
  el.addEventListener('pointerdown', (e) => {
    if (e.target.closest('[data-grab]')) y0 = e.clientY;
  });
  el.addEventListener('pointerup', (e) => {
    if (y0 !== null && e.clientY - y0 > 30) go('dismiss');
    y0 = null;
  });
  lives.set(id, {
    reset: () => {
      s = initial();
      taps = 0;
      draw('text');
    },
  });
  draw();
};

const optionSection = (id, m) => {
  const o = W.options[id];
  const st = (key) => {
    const [, acts, gesture] = frames(id, env.lang).find(([k]) => k === key);
    return phone(run(acts, env.lang), options[id], env, { gesture });
  };
  const mm = m?.[env.device]?.[id];
  const metric = mm
    ? `<p class="meter">${W.meterLine({ h: mm.editH, saved: m[env.device].today.editH - mm.editH, taps: storeCat[id].length, brand: options[id].brand, fits: m[env.device].fits[id] })}</p>`
    : '';
  return `<section class="option" id="${id}"><h2>${id} ${o.name}${m?.pick === id ? `<span class="tag pick">${W.pick}</span>` : ''}${m?.runner === id ? `<span class="tag runner">${W.runner}</span>` : ''}</h2>
    <p>${o.what}</p>${metric}
    <div class="frames">
      <div class="live">${cell(W.liveCap, `<div data-live-phone="${id}"></div>`)}<button class="resetbtn" data-reset="${id}">${W.reset}</button><p class="hint">${W.liveHint}</p></div>
      ${W.frameOrder.map(([k, cap, sub]) => cell(cap, st(k), typeof sub === 'function' ? sub(id) : sub)).join('')}
    </div></section>`;
};

const table = (m) => {
  if (!m) return '';
  const rows = ['today', ...ids].map((id) => {
    const d = (dev) => m[dev][id];
    const saved = (dev) => m[dev].today.editH - d(dev).editH;
    const fits = (dev) => m[dev].fits[id];
    return `<tr><td><b>${id === 'today' ? W.today : `${id} ${W.options[id].name}`}</b></td>
      ${['ios', 'android'].map((dev) => `<td>${d(dev).editH} px${id === 'today' ? '' : ` (−${saved(dev)})`}${d(dev).editHde !== undefined && d(dev).editHde !== d(dev).editH ? `; ${W.german} ${d(dev).editHde} px` : ''}</td>`).join('')}
      <td>${storeCat[id].length}${id !== 'today' && d('android').swipes ? ` ${W.plusSwipe}` : ''}</td><td>${id === 'today' ? W.yes : options[id].brand ? W.yes : W.no}</td>
      <td>${id === 'today' ? W.no : W.fitsCell(fits('ios'))}</td><td>${id === 'today' ? W.no : W.fitsCell(fits('android'))}</td>
      <td>${id === 'today' ? '–' : W.listLeft(d('android'))}</td></tr>`;
  });
  return `<section class="facts" id="table"><h2>${W.tableTitle}</h2><p class="note">${W.tableNote}</p><div class="table-wrap"><table>
    <thead><tr>${W.tableHead.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`;
};

export const round = async () => {
  await themeCss('../../../../site/public/tokens.css');
  document.title = W.roundTitle;
  const m = await fetch('../measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  const todayState = run(todayFrame(env.lang), env.lang);
  document.body.innerHTML = `${head(W.roundTitle, true)}<main class="view">
    <section class="facts" id="today"><h2>${W.today}</h2>${W.todayFacts}
      <div class="frames">${cell(W.todayCap, phone(todayState, options.today, env))}</div></section>
    ${ids.map((id) => optionSection(id, m)).join('')}
    ${table(m)}
    <section class="rec" id="rec">${md(await fetch(`../${W.recFile}`).then((r) => r.text()))}</section></main>`;
  for (const el of document.querySelectorAll('[data-live-phone]')) mountLive(el, el.dataset.livePhone);
  for (const b of document.querySelectorAll('[data-reset]')) b.addEventListener('click', () => lives.get(b.dataset.reset).reset());
  settle(document);
  document.body.dataset.ready = '1';
};

export const overview = async () => {
  await themeCss('../../../site/public/tokens.css');
  document.title = W.overviewTitle;
  const m = await fetch('measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  document.body.innerHTML = `${head(W.overviewTitle, false)}<main class="view"><div class="cards">
    <a class="ocard" href="as/${location.search}"><h2>${W.roundTitle}</h2><p>${W.roundBlurb}</p>
    ${m ? `<p><span class="tag pick">${W.pick}</span> ${m.pick} ${W.options[m.pick].name} · <span class="tag runner">${W.runner}</span> ${m.runner} ${W.options[m.runner].name}</p>` : ''}</a></div></main>`;
  document.body.className = `th-${env.theme}`;
  document.body.dataset.ready = '1';
};
