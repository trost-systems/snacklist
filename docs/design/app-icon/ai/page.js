import { options } from './options.js';
import { copy } from './copy.js';

const params = new URLSearchParams(location.search);
let lang = params.get('lang') === 'de' ? 'de' : 'en';
let theme = params.get('theme') === 'dark' ? 'dark' : 'light';
const measured = await (await fetch('measured.json')).json();
const t = (v) => (typeof v === 'string' ? v : v[lang]);
const img = (id, kind) => `img/${id}/${kind}.png`;

// Generic neighbour apps: plain shapes, no real brand.
const NEIGHBOURS = [
  { label: { en: 'Weather', de: 'Wetter' }, bg: '#4aa3ff', fg: '#ffe24a', g: '<circle cx="50" cy="50" r="20"/>' },
  { label: { en: 'Notes', de: 'Notizen' }, bg: '#fff3c4', fg: '#7a6a3a', g: '<rect x="28" y="32" width="44" height="7" rx="3"/><rect x="28" y="47" width="44" height="7" rx="3"/><rect x="28" y="62" width="30" height="7" rx="3"/>' },
  { label: { en: 'Budget', de: 'Budget' }, bg: '#2f9e62', fg: '#ffffff', g: '<rect x="28" y="52" width="10" height="20" rx="3"/><rect x="45" y="38" width="10" height="34" rx="3"/><rect x="62" y="28" width="10" height="44" rx="3"/>' },
  { label: { en: 'Maps', de: 'Karten' }, bg: '#6c7a89', fg: '#ffffff', g: '<path d="M50 78 L34 52 A19 19 0 1 1 66 52 Z"/><circle cx="50" cy="44" r="7" fill-opacity="0"/>' },
  { label: { en: 'Music', de: 'Musik' }, bg: '#e84a5f', fg: '#ffffff', g: '<circle cx="40" cy="66" r="10"/><rect x="46" y="26" width="7" height="42" rx="3"/><rect x="46" y="26" width="22" height="8" rx="3"/>' },
  { label: { en: 'Clock', de: 'Uhr' }, bg: '#222831', fg: '#ffffff', g: '<circle cx="50" cy="50" r="24" fill="none" stroke="currentColor" stroke-width="6"/><rect x="47" y="34" width="6" height="18" rx="3"/><rect x="47" y="47" width="16" height="6" rx="3"/>' },
  { label: { en: 'Recipes', de: 'Rezepte' }, bg: '#ff8c42', fg: '#ffffff', g: '<path d="M26 48 H74 A24 24 0 0 1 26 48 Z"/><rect x="44" y="26" width="6" height="18" rx="3"/><rect x="54" y="30" width="6" height="14" rx="3"/>' },
];
const STYLE = {
  light: (n) => [n.bg, n.fg, 1],
  dark: (n) => ['#1c1c1e', n.bg === '#fff3c4' ? '#ffe9a0' : n.bg, 1],
  tinted: () => ['#1d160b', '#ffb84a', 1],
  clear: () => ['rgba(255,255,255,.22)', 'rgba(255,255,255,.9)', 1],
  'themed-light': () => ['#d7e8cd', '#102000', 1],
  'themed-dark': () => ['#253420', '#bcecaa', 1],
};
function neighbour(n, style, shape) {
  const [bg, fg] = STYLE[style](n);
  const bgEl = shape === 'circle' ? `<circle cx="50" cy="50" r="50" fill="${bg}"/>` : `<rect width="100" height="100" rx="23" fill="${bg}"/>`;
  return `<div class="app"><div class="ic${style === 'clear' ? ' glass' : ''}"><svg viewBox="0 0 100 100" style="color:${fg}" fill="currentColor" aria-hidden="true">${bgEl}${n.g}</svg></div><span>${t(n.label)}</span></div>`;
}
function home(id, kind, style, wall, shape = 'ios') {
  const mine = `<div class="app"><div class="ic mine${style === 'clear' ? ' glass' : ''}"><img src="${img(id, kind)}" alt="${t(copy.iconAlt)} ${id}"></div><span>Snacklist</span></div>`;
  const apps = NEIGHBOURS.map((n) => neighbour(n, style, shape));
  apps.splice(5, 0, mine);
  return `<div class="home ${wall}${shape === 'circle' ? ' round' : ''}">${apps.join('')}</div>`;
}
const scene = (label, body) => `<div class="scene"><div class="label">${t(label)}</div>${body}</div>`;

// Android's 108 dp canvas drawn at 216 px (2 px per dp): the 72 dp visible square and the 66 dp safe circle.
const safeOverlay = `<svg viewBox="0 0 216 216" aria-hidden="true"><rect x="36" y="36" width="144" height="144" fill="none" stroke="#fff" stroke-width="1.5" stroke-dasharray="4 3"/><circle cx="108" cy="108" r="66" fill="none" stroke="#ff5b3a" stroke-width="2"/></svg>`;

const fmt = (n, d = 1) => (lang === 'de' ? n.toFixed(d).replace('.', ',') : n.toFixed(d));
const thinPx = (v) => `<span class="${v < 1.5 ? 'bad' : v >= 2 ? 'good' : ''}">${fmt(v)} px</span>`;

function table() {
  const rows = options.map((o) => {
    const m = measured[o.id];
    return `<tr><th scope="row">${o.id}<br><span class="sub">${t(o.name)}</span></th>
      <td class="num">${thinPx(m.thinnest29)} / ${thinPx(m.thinnest48)}<br><span class="hint">${t(copy.roles[m.thinnest] ?? { en: m.thinnest, de: m.thinnest })}</span></td>
      <td class="num">${thinPx(m.monoThinnest29)}</td>
      <td class="num">${fmt(m.keyLight, 2)} / ${fmt(m.keyDark, 2)}</td>
      <td class="num"><span class="${m.contrastLight.ratio < 1.5 ? 'bad' : ''}">${fmt(m.contrastLight.ratio, 2)}</span> / <span class="${m.contrastDark.ratio < 1.5 ? 'bad' : ''}">${fmt(m.contrastDark.ratio, 2)}</span></td>
      <td class="num"><span class="${m.tileOnWall.light < 1.5 ? 'bad' : ''}">${fmt(m.tileOnWall.light, 2)}</span></td>
      <td class="num">${fmt(m.reachDp)} dp ${m.inside ? '✓' : '<span class="bad">✗</span>'}<br><span class="hint">${fmt((m.reachDp / 33) * 100, 0)} %</span></td>
      <td>${t(o.keeps)}</td></tr>`;
  }).join('');
  return `<div class="scroll"><table><thead><tr>${copy.cols.map((c) => `<th scope="col">${t(c)}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table></div>`;
}

function strip() {
  return `<div class="strip">${options.map((o) => `<figure>
    <img class="big" src="${img(o.id, 'ios-light')}" alt="${t(copy.iconAlt)} ${o.id}">
    <figcaption>${o.id}<br><span class="sub">${t(o.name)}</span></figcaption>
    <div class="realsize"><img src="${img(o.id, 'settings-87-light')}" width="29" height="29" alt=""><img src="${img(o.id, 'settings-87-dark')}" width="29" height="29" alt=""><img class="pix" src="${img(o.id, 'launcher-48-light')}" width="48" height="48" alt=""></div>
  </figure>`).join('')}</div><p class="hint">${t(copy.stripHint)}</p>`;
}

function option(o) {
  const id = o.id;
  const zoom = ['settings-29-light', 'settings-29-dark', 'launcher-48-light', 'notification-24', 'notification-48'].map((k) => {
    const size = Number(k.match(/\d+/)[0]);
    return `<figure><img class="pix" src="${img(id, k)}" width="96" height="96" alt=""><figcaption>${size} px${k.includes('dark') ? ` · ${t(copy.dark)}` : ''}</figcaption></figure>`;
  }).join('');
  return `<section class="opt" id="${id}">
    <h2><span class="id">${id}</span> ${t(o.name)}</h2>
    <p>${t(o.what)}</p>
    <p class="keeps">${t(copy.keepsLabel)}: ${t(o.keeps)}</p>
    <h3>iOS 26</h3>
    <div class="scenes">
      ${scene(copy.iosLight, home(id, 'ios-light', 'light', 'wall-light'))}
      ${scene(copy.iosDark, home(id, 'ios-dark', 'dark', 'wall-dark'))}
      ${scene(copy.iosTinted, home(id, 'ios-tinted', 'tinted', 'wall-tint'))}
      ${scene(copy.iosClear, home(id, 'ios-clear', 'clear', 'wall-clear'))}
    </div>
    <h3>Android</h3>
    <div class="scenes">
      ${scene(copy.androidCircle, home(id, 'android-circle', 'light', 'wall-android', 'circle'))}
      ${scene(copy.androidSquircle, home(id, 'android-squircle', 'light', 'wall-android'))}
      ${scene(copy.themedLight, home(id, 'android-themed-light', 'themed-light', 'wall-android', 'circle'))}
      ${scene(copy.themedDark, home(id, 'android-themed-dark', 'themed-dark', 'wall-android-dark', 'circle'))}
      ${scene(copy.safe, `<div class="canvasbox"><img src="${img(id, 'android-canvas')}" alt="">${safeOverlay}</div><div class="legend">${t(copy.safeLegend)} ${fmt(measured[id].reachDp)} dp</div>`)}
    </div>
    <h3>${t(copy.smallHead)}</h3>
    <div class="scenes">
      ${scene(copy.notification, `<div class="statusbar dark"><span>9:41</span><img src="${img(id, 'notification-48')}" width="24" height="24" alt=""><span style="margin-left:auto">5G</span></div><div class="statusbar light"><span>9:41</span><img src="${img(id, 'notification-48')}" width="24" height="24" alt=""><span style="margin-left:auto">5G</span></div>`)}
      ${scene(copy.settings, `<div class="settingsrow"><img src="${img(id, 'settings-87-light')}" width="29" height="29" alt=""><span>Snacklist</span><span class="chev">›</span></div><div class="settingsrow dark"><img src="${img(id, 'settings-87-dark')}" width="29" height="29" alt=""><span>Snacklist</span><span class="chev">›</span></div>`)}
      ${scene(copy.pixels, `<div class="zoom">${zoom}</div>`)}
    </div>
    <h3>${t(copy.storeHead)}</h3>
    <div class="scenes">
      ${scene(copy.appStore, `<div class="store"><img src="${img(id, 'store-app')}" alt=""><div class="meta"><div class="n">Snacklist</div><div class="s">${t(copy.subtitle)}</div></div><span class="get">${t(copy.get)}</span></div>`)}
      ${scene(copy.play, `<div class="store play"><img src="${img(id, 'store-play')}" alt=""><div class="meta"><div class="n">Snacklist</div><div class="s">Trost Systems</div></div><span class="get">${t(copy.install)}</span></div>`)}
    </div>
    ${id === 'Today' ? '' : `<p class="hint">${t(copy.assets)} <code>docs/design/app-icon/ai/assets/${id}/</code> · <code>node design/app-icon/build.mjs --art design/app-icon/art/${id.toLowerCase()}.mjs</code></p>`}
  </section>`;
}

function render() {
  document.documentElement.lang = lang;
  document.documentElement.dataset.theme = theme;
  document.title = t(copy.title);
  const btn = (key, val, label, on) => `<button class="t" data-${key}="${val}" aria-pressed="${on}">${label}</button>`;
  document.getElementById('page').innerHTML = `
    <div class="bar"><a href="../../">${t(copy.back)}</a><div class="toggles">${btn('lang', 'en', 'EN', lang === 'en')}${btn('lang', 'de', 'DE', lang === 'de')}${btn('theme', theme === 'dark' ? 'light' : 'dark', t(theme === 'dark' ? copy.light : copy.dark), false)}</div></div>
    <h1>${t(copy.title)}</h1>
    <p>${t(copy.question)}</p>
    <div class="card rec"><h2 style="margin-top:0">${t(copy.recHead)}</h2>${t(copy.rec)}</div>
    ${strip()}
    <h2>${t(copy.measureHead)}</h2>
    ${table()}
    <div class="hint">${t(copy.measureNotes).replace('{tintIos}', fmt(measured.AI1.tinted.ios)).replace('{tintAL}', fmt(measured.AI1.tinted.androidLight)).replace('{tintAD}', fmt(measured.AI1.tinted.androidDark))}</div>
    ${options.map(option).join('')}
    <h2>${t(copy.qHead)}</h2>
    ${t(copy.questions)}
    <h2>${t(copy.swapHead)}</h2>
    ${t(copy.swap)}`;
  for (const b of document.querySelectorAll('button[data-lang]')) b.onclick = () => { lang = b.dataset.lang; sync(); };
  for (const b of document.querySelectorAll('button[data-theme]')) b.onclick = () => { theme = b.dataset.theme; sync(); };
}
function sync() {
  const q = new URLSearchParams(location.search);
  q.set('lang', lang);
  q.set('theme', theme);
  history.replaceState(null, '', `?${q}${location.hash}`);
  render();
}
render();
