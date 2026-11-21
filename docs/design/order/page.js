// The round page and the overview. ?lang=de, ?theme=dark, ?ts=200|310, ?device=android.
import { act, categorical, initial, walk } from './model.js';
import { ids, options } from './options.js';
import { eggsAfter, fixPath, ikeaCost, run } from './paths.js';
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

const cell = (key, html) => {
  const [cap, sub] = W.frames[key];
  return `<figure class="cell" data-frame="${key}"><figcaption>${cap}<small>${sub}</small></figcaption>${html}</figure>`;
};

const start = (id) => initial(options[id].kind, env.lang);

// The frames of an option: states replayed from the same actions the live phone and verify.mjs use.
export const frameStates = (id) => {
  const o = options[id];
  const s = start(id);
  const path = fixPath(id, s);
  const out = [['top', s, ''], ['ikea', s, 'ikea'], ['add', act(s, 'add:ketchup'), 'ketchup']];
  if (o.kind === 'learned') {
    const first = { ...structuredClone(s), seq: { ...s.seq, ikea: categorical(s, walk.ikea, 'ikea') } };
    out.push(['first', first, 'ikea']);
  }
  if (o.fix === 'none') {
    const trip = structuredClone(s);
    const ticked = walk.edeka.slice(0, walk.edeka.indexOf('eggs') + 1);
    trip.open = trip.open.filter((x) => !ticked.includes(x));
    trip.trip = { ticked };
    out.push(['trip', trip, 'chocolate']);
    out.push(['fixed', act(s, 'walkTrip'), 'eggs']);
  } else if (o.fix === 'drag') {
    const mid = run(s, path.slice(0, 2));
    mid.lifted = 'eggs';
    mid.moved = null;
    out.push(['fixing', mid, 'eggs']);
    out.push(['fixed', run(s, path), 'eggs']);
  } else if (o.fix === 'step') {
    out.push(['fixing', run(s, path.slice(0, -1)), '']);
    out.push(['fixed', run(s, path), 'eggs']);
  } else {
    out.push(['sheet', run(s, path.slice(0, 1)), '']);
    out.push(['fixing', run(s, path.slice(0, 2)), '']);
    out.push(['fixed', run(s, path), 'eggs']);
  }
  // IO-Q3: a person who switches headings on in a learned household sees the shared order with a heading at every
  // change of category, after the Eggs fix: Chilled heads a second run, the Eggs after the flour.
  if (o.catsOverLearned) out.push(['catsLearned', act(run(s, path), 'showCats'), 'eggs']);
  if (o.settings) {
    out.push(['settings', act(s, 'screen:stores'), '']);
    out.push(['cats', act(s, 'showCats'), '']);
  }
  return out;
};

const frames = (id) => frameStates(id).map(([key, st, show]) => cell(key, phone(st, options[id], env, { show }))).join('');

// Holding a row 400 ms (or a right click) opens its edit sheet; a click ticks it. In IO3's sort mode a handle drags.
const mountLive = (el, id) => {
  const o = options[id];
  let s = start(id);
  const scenes = el.parentElement.querySelector('.states');
  let show = '';
  const draw = () => {
    el.innerHTML = phone(s, o, env, { live: true, show });
    const ph = el.querySelector('.phone');
    if (!show && !s.sheet) ph.dataset.keepScroll = '1';
    const sc = ph.querySelector('[data-scroll]');
    const keep = el.dataset.scrollTop;
    settle(el);
    if (keep && !show && !s.sheet) sc.scrollTop = Number(keep);
    show = '';
  };
  const go = (a) => {
    s = act(s, a);
    el.dataset.scrollTop = el.querySelector('[data-scroll]')?.scrollTop ?? '';
    draw();
  };
  let timer = null;
  let held = false;
  el.addEventListener('pointerdown', (e) => {
    const h = e.target.closest('[data-handle]');
    if (h) {
      dragStart(e, h.dataset.handle);
      return;
    }
    const r = e.target.closest('[data-hold]');
    if (!r || s.sortMode || s.sheet || s.screen !== 'list') return;
    held = false;
    timer = setTimeout(() => {
      held = true;
      go(`hold:${r.dataset.hold}`);
    }, 400);
  });
  el.addEventListener('pointerup', () => clearTimeout(timer));
  el.addEventListener('pointerleave', () => clearTimeout(timer));
  el.addEventListener('contextmenu', (e) => {
    const r = e.target.closest('[data-hold]');
    if (!r || s.sortMode) return;
    e.preventDefault();
    go(`hold:${r.dataset.hold}`);
  });
  el.addEventListener('click', (e) => {
    if (held) {
      held = false;
      return;
    }
    const b = e.target.closest('[data-act]');
    if (!b || !b.dataset.act || e.target.closest('[data-handle]')) return;
    if (b.dataset.act.startsWith('tick:') && (s.sheet || s.sortMode)) return;
    go(b.dataset.act);
  });
  // A drag in sort mode: the row follows the pointer, the others make room; the drop lands after the row above.
  const dragStart = (e, rid) => {
    e.preventDefault();
    const row = el.querySelector(`[data-row="${rid}"]`);
    const sec = row.closest('section');
    const rows = [...sec.querySelectorAll('.item')];
    const y0 = e.clientY;
    const h = row.offsetHeight;
    const from = rows.indexOf(row);
    row.classList.add('dragging');
    let to = from;
    const move = (ev) => {
      const dy = ev.clientY - y0;
      row.style.transform = `translateY(${dy}px)`;
      to = Math.max(0, Math.min(rows.length - 1, from + Math.round(dy / h)));
      rows.forEach((r, k) => {
        if (r === row) return;
        r.classList.add('shift');
        r.style.transform = k > from && k <= to ? `translateY(${-h}px)` : k < from && k >= to ? `translateY(${h}px)` : '';
      });
    };
    const up = () => {
      el.removeEventListener('pointermove', move);
      el.removeEventListener('pointerup', up);
      const others = rows.filter((r) => r !== row).map((r) => r.dataset.row);
      const anchor = to === 0 ? 'first' : others[to - 1];
      go(`drop:${rid}:${anchor}`);
    };
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', up);
  };
  scenes.addEventListener('click', (e) => {
    const b = e.target.closest('[data-scene]');
    if (!b) return;
    const k = b.dataset.scene;
    if (k === 'reset' || k === 'top') s = start(id);
    if (k === 'ikea') show = 'ikea';
    if (k === 'add') { s = act(s, 'add:ketchup'); show = 'ketchup'; }
    if (k === 'addIkea') { s = act(s, 'add:hangers'); show = 'hangers'; }
    if (k === 'trip') { s = act(s, 'walkTrip'); show = 'eggs'; }
    delete el.dataset.scrollTop;
    draw();
  });
  draw();
};

const sceneKeys = (id) => ['top', 'ikea', 'add', 'addIkea', ...(options[id].kind === 'learned' ? ['trip'] : []), 'reset'];

const rowsOf = (m, id, dev = env.device, ts = env.ts, lang = env.lang) => m?.[lang]?.[dev]?.[ts]?.[id];

const meter = (m, id) => {
  const s = start(id);
  const taps = fixPath(id, s).length;
  return `<p class="meter">${W.meterLine({ rows: rowsOf(m, id) ?? '…', today: rowsOf(m, 'today') ?? '…', taps: options[id].fix === 'none' ? W.taps(0) : W.taps(taps), ikea: W.ikeaText(ikeaCost(id, env.lang)) })}</p>`;
};

const optionSection = (id, m) => {
  const o = W.options[id];
  const live = id === 'today' ? '' : `<div class="live">${`<figure class="cell"><figcaption>${W.liveCap}</figcaption><div class="states">${sceneKeys(id).map((k) => `<button data-scene="${k}">${W.scenes[k]}</button>`).join('')}</div><div data-live-phone="${id}"></div></figure>`}</div>`;
  return `<section class="option" id="${id}"><h2>${id} ${o.name}${m?.pick === id ? `<span class="tag pick">${W.pick}</span>` : ''}${m?.runner === id ? `<span class="tag runner">${W.runner}</span>` : ''}</h2>
    <p>${o.what}</p>${meter(m, id)}
    <div class="frames">${live}${frames(id)}</div></section>`;
};

const table = (m) => {
  if (!m) return '';
  const rows = ['today', ...ids].map((id) => {
    const s = start(id);
    const path = fixPath(id, s);
    const after = options[id].fix === 'none' ? eggsAfter(act(s, 'walkTrip'), id) : eggsAfter(run(s, path), id);
    const r = (dev, ts) => {
      const en = rowsOf(m, id, dev, ts, env.lang);
      const other = rowsOf(m, id, dev, ts, env.lang === 'en' ? 'de' : 'en');
      return `${en}${other !== en ? ` (${env.lang === 'en' ? W.german : 'English'} ${other})` : ''}`;
    };
    return `<tr data-row="${id}"><td><b>${id === 'today' ? W.today : `${id} ${W.options[id].name}`}</b></td><td data-c="rows">${r('ios', 100)}</td><td>${r('ios', 310)}</td><td>${r('android', 100)}</td><td>${r('android', 200)}</td>
      <td data-c="taps">${options[id].fix === 'none' ? W.taps(0) : W.taps(path.length)}</td><td>${W.eggsWhere[after === 'flour' ? 'flour' : options[id].fix === 'none' ? 'flour' : 'passata']}</td><td>${W.ikeaText(ikeaCost(id, env.lang))}</td></tr>`;
  });
  return `<section class="facts" id="table"><h2>${W.tableTitle}</h2><p class="note">${W.tableNote}</p><div class="table-wrap"><table>
    <thead><tr>${W.tableHead.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`;
};

const realShots = () => {
  const tag = `${env.lang}-${env.theme === 'dark' && env.lang === 'en' && env.ts === 100 && env.device === 'ios' ? 'dark' : 'light'}-${env.ts === 310 ? 310 : env.device === 'android' && env.ts === 200 ? 200 : 100}${env.device === 'android' ? '-android' : ''}`;
  const shots = env.ts === 100 ? ['top', 'ikea', 'sheet'] : ['top'];
  return shots.map((k) => `<figure class="cell" data-frame="real-${k}"><figcaption>${W.real}<small>${tag}-${k}.png</small></figcaption><img class="realshot" src="real/${tag}-${k}.png" width="${env.device === 'android' ? 360 : 390}" alt="" onerror="this.closest('figure').remove()"></figure>`).join('');
};

export const round = async () => {
  await themeCss('../../../../site/public/tokens.css');
  document.title = W.roundTitle;
  document.documentElement.lang = env.lang;
  const m = await fetch('measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  const todayFrames = frameStates('today').map(([key, st, show]) => cell(key, phone(st, options.today, env, { show }))).join('');
  document.body.innerHTML = `${head(W.roundTitle, true)}<main class="view">
    <section class="facts" id="today"><h2>${W.today}</h2>${W.todayFacts}<p><a href="../APPROACHES.md">${W.approaches}</a></p>${meter(m, 'today')}
      <div class="frames">${todayFrames}${realShots()}</div></section>
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
  document.documentElement.lang = env.lang;
  const m = await fetch('io/measured.json').then((r) => (r.ok ? r.json() : null)).catch(() => null);
  document.body.innerHTML = `${head(W.overviewTitle, false)}<main class="view"><div class="cards">
    <a class="ocard" href="io/${location.search}"><h2>${W.roundTitle}</h2><p>${W.roundBlurb}</p>
    ${m?.pick ? `<p><span class="tag pick">${W.pick}</span> ${m.pick} ${W.options[m.pick].name} · <span class="tag runner">${W.runner}</span> ${m.runner} ${W.options[m.runner].name}</p>` : ''}</a>
    <a class="ocard" href="APPROACHES.md"><h2>APPROACHES.md</h2><p>${W.approaches}</p></a></div></main>`;
  document.body.className = `th-${env.theme}`;
  document.body.dataset.ready = '1';
};
