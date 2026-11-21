// Round RD's page: an overview (pick, table, every option's list side by side) and one view per option with its six
// frames and a live meter under each. ?opt=RD3 &theme=dark &lang=de &ts=200|310.
import { fit, measure } from './measure.js';
import { byId, frameName, frames, ids, options } from './options.js';
import { esc, frame } from './render.js';
import { pick, rec, runnerUp } from './recommend.js';

const q = new URLSearchParams(location.search);
const s = {
  view: ids.includes(q.get('opt')) ? q.get('opt') : 'overview',
  theme: q.get('theme') === 'dark' ? 'dark' : 'light',
  lang: q.get('lang') === 'de' ? 'de' : 'en',
  ts: { 200: 2, 310: 3.1 }[q.get('ts')] ?? 1,
};
document.documentElement.lang = s.lang;
document.body.className = `page th-${s.theme}`;
const L = (en, de) => (s.lang === 'de' ? de : en);
const costName = {
  none: L('the app today', 'die App heute'),
  tokens: L('cheap: tokens only', 'günstig: nur Tokens'),
  widgets: L('medium: widgets redrawn', 'mittel: Widgets neu gezeichnet'),
  structure: L('structural: navigation or layout', 'strukturell: Navigation oder Aufbau'),
};

const go = (patch) => {
  const n = { ...s, ...patch };
  const p = new URLSearchParams();
  if (n.view !== 'overview') p.set('opt', n.view);
  if (n.theme === 'dark') p.set('theme', 'dark');
  if (n.lang === 'de') p.set('lang', 'de');
  if (n.ts !== 1) p.set('ts', n.ts === 2 ? '200' : '310');
  location.search = p.toString();
};
const btn = (label, on, patch) => `<button aria-pressed="${on}" data-go='${JSON.stringify(patch)}'>${label}</button>`;

const head = `<header class="page-head">
  <a class="back-link" href="../../">${L('← All prototype rounds', '← Alle Prototyp-Runden')}</a>
  <h1>${L('Snacklist without hexagons: ten directions (round RD)', 'Snacklist ohne Sechsecke: zehn Richtungen (Runde RD)')}</h1>
  <p class="note">${L('Mock data only (the fictional Brandt family). Base: the list with categories hidden (hide-categories) and the TE1 total. Colours are exactly today’s tokens; shapes, menus, rows, ticks and type are open. Every phone is a 390 × 844 iPhone screen with its status bar and home indicator. Dotted words are new; the rest are the app’s own strings.', 'Nur Beispieldaten (die erfundene Familie Brandt). Basis: die Liste ohne Kategorien (hide-categories) mit der TE1-Summe. Die Farben sind exakt die heutigen Tokens; Formen, Menüs, Zeilen, Haken und Schrift sind offen. Jedes Handy ist ein 390 × 844 iPhone-Bildschirm mit Statusleiste und Home-Balken. Gepunktet unterstrichene Wörter sind neu, der Rest sind die Texte der App.')}</p>
  <div class="controls"><span class="lbl">${L('View', 'Ansicht')}</span>${btn(L('Overview', 'Übersicht'), s.view === 'overview', { view: 'overview' })}${options.map((o) => btn(o.id === 'today' ? esc(o.name[s.lang]) : o.id, s.view === o.id, { view: o.id })).join('')}</div>
  <div class="controls"><span class="lbl">${L('Theme', 'Design')}</span>${btn(L('Light', 'Hell'), s.theme === 'light', { theme: 'light' })}${btn(L('Dark', 'Dunkel'), s.theme === 'dark', { theme: 'dark' })}
    <span class="lbl">${L('Text size', 'Textgröße')}</span>${btn('100 %', s.ts === 1, { ts: 1 })}${btn('200 %', s.ts === 2, { ts: 2 })}${btn(L('310 % (largest)', '310 % (größte)'), s.ts === 3.1, { ts: 3.1 })}
    <span class="lbl">${L('Language', 'Sprache')}</span>${btn('English', s.lang === 'en', { lang: 'en' })}${btn('Deutsch', s.lang === 'de', { lang: 'de' })}</div>
</header>`;

const tags = (o) => `<span class="chiplet ${o.cost}">${esc(costName[o.cost])}</span>${o.id === pick ? `<span class="chiplet pick">${L('Pick', 'Empfehlung')}</span>` : ''}${o.id === runnerUp ? `<span class="chiplet runner">${L('Runner-up', 'Zweite Wahl')}</span>` : ''}`;
const optHead = (o) => `<div class="opt-head"><h2>${o.id === 'today' ? '' : `${o.id} · `}${esc(o.name[s.lang])}</h2><div class="facts">${tags(o)}</div>
  <p>${esc(o.rationale[s.lang])}</p>
  <p class="meter"><b>${L('Corners', 'Ecken')}:</b> ${esc(o.radius[s.lang])}. <b>${L('Menu', 'Menü')}:</b> ${esc(o.navName[s.lang])}.</p>
  ${o.revisits[s.lang].length ? `<ul>${o.revisits[s.lang].map((r) => `<li>${esc(r)}</li>`).join('')}</ul>` : ''}</div>`;

const meterLine = (m, kind) => {
  const bad = (cond, text) => (cond ? `<span class="bad">${text}</span>` : text);
  const parts = [];
  if (kind === 'list') parts.push(`<b>${m.rows}</b> ${L('whole rows', 'ganze Zeilen')}`);
  parts.push(`${L('smallest tap', 'kleinstes Ziel')} ${bad(m.minTap < 44, `<b>${m.minTap}</b> px`)}`);
  parts.push(`${L('text contrast', 'Textkontrast')} ${bad(m.lowText.length, `<b>${m.contrast}</b>`)}`);
  if (m.ui !== null) parts.push(`${L('borders', 'Ränder')} ${bad(m.lowUi.length, `<b>${m.ui}</b>`)}`);
  parts.push(bad(m.overflow.length, `${m.overflow.length} ${L('overflows', 'Überläufe')}`));
  return `<p class="meter" title="${esc([...m.smallTaps, ...m.lowText, ...m.lowUi, ...m.overflow].join('\n'))}">${parts.join(' · ')}</p>`;
};

const cell = (o, kind) => `<figure class="cell" data-cell="${o.id}-${kind}"><figcaption>${esc(frameName[kind][s.lang])}</figcaption>${frame(s, o, kind)}<div class="live"></div></figure>`;

const optionView = (o) => `<section class="option" data-option-view="${o.id}">${optHead(o)}<div class="frames">${frames.map((k) => cell(o, k)).join('')}</div></section>`;

const table = (measured) => {
  if (!measured) return '';
  const rows = options.map((o) => {
    const m = measured.summary[o.id];
    return `<tr class="${o.id === pick ? 'pick' : ''}"><td>${o.id === 'today' ? esc(o.name[s.lang]) : `${o.id} ${esc(o.name[s.lang])}`}</td><td>${esc(costName[o.cost])}</td>
      <td>${m.rows100}</td><td>${m.rows310}</td><td>${m.minTap} px</td><td>${m.contrastLight} / ${m.contrastDark}</td><td>${m.uiLight ?? '–'} / ${m.uiDark ?? '–'}</td><td>${m.overflow310}</td><td>${m.broken310}</td><td>${m.offPalette}</td></tr>`;
  }).join('');
  return `<div class="table-wrap"><table class="m"><thead><tr><th>${L('Option', 'Option')}</th><th>${L('Cost', 'Aufwand')}</th><th>${L('Whole rows, 100 %', 'Ganze Zeilen, 100 %')}</th><th>${L('Whole rows, 310 %', 'Ganze Zeilen, 310 %')}</th>
    <th>${L('Smallest tap target', 'Kleinstes Tippziel')}</th><th>${L('Lowest text contrast, light / dark', 'Niedrigster Textkontrast, hell / dunkel')}</th><th>${L('Lowest border contrast, light / dark', 'Niedrigster Randkontrast, hell / dunkel')}</th>
    <th>${L('Overflows at 310 % (all frames, both themes and languages)', 'Überläufe bei 310 % (alle Frames, beide Designs und Sprachen)')}</th><th>${L('Words broken at 310 % (light)', 'Getrennte Wörter bei 310 % (hell)')}</th><th>${L('Colours off the palette', 'Farben außerhalb der Palette')}</th></tr></thead><tbody>${rows}</tbody></table></div>
    <p class="note">${L(`Measured by verify.mjs (${measured.checks} checks) in Chromium, every option × frame × light/dark × 100/200/310 % × English/German. Rows: item rows wholly between the bars on the list frame, English, light. Targets: the smallest side of anything tappable that is not covered. Contrast: WCAG ratio of text against what is painted under it (4.5, large text 3); borders: a control’s drawn edge against its ground (3).`, `Gemessen von verify.mjs (${measured.checks} Prüfungen) in Chromium, jede Option × Frame × hell/dunkel × 100/200/310 % × Englisch/Deutsch. Zeilen: Artikelzeilen ganz zwischen den Leisten im Listen-Frame, Englisch, hell. Ziele: die kleinste Seite von allem Tippbaren, das nicht verdeckt ist. Kontrast: WCAG-Verhältnis von Text zu dem, was darunter gemalt ist (4,5, große Schrift 3); Ränder: der gezeichnete Rand eines Bedienelements zu seinem Grund (3).`)}</p>`;
};

const overview = (measured) => `<section class="rec">${rec[s.lang]}</section>
  <section>${table(measured)}</section>
  <section><h2 class="opt-head">${L('Every option’s list', 'Die Liste jeder Option')}</h2><div class="grid-all">${options.map((o) => `<figure class="cell" data-cell="${o.id}-list"><figcaption><a href="?${new URLSearchParams({ opt: o.id, ...(s.theme === 'dark' ? { theme: 'dark' } : {}), ...(s.lang === 'de' ? { lang: 'de' } : {}) })}">${o.id === 'today' ? '' : `${o.id} · `}${esc(o.name[s.lang])}</a> <small>${esc(costName[o.cost])}</small></figcaption>${frame(s, o, 'list')}<div class="live"></div></figure>`).join('')}</div></section>`;

// verify.mjs: one phone alone at the page's top left, so every point of it is inside the viewport.
const solo = async () => {
  document.body.className = 'solo';
  globalThis.show = async (id, kind, theme, ts, lang, palette) => {
    document.getElementById('app').innerHTML = frame({ theme, ts, lang }, byId[id], kind);
    const phone = document.querySelector('.phone');
    phone.getBoundingClientRect();
    await document.fonts.ready;
    fit(phone);
    return measure(phone, palette);
  };
  document.body.dataset.ready = '1';
};

const run = async () => {
  if (q.has('solo')) return solo();
  let measured = null;
  try { measured = await (await fetch('measured.json')).json(); } catch { measured = null; }
  document.getElementById('app').innerHTML = `${head}<main class="view">${s.view === 'overview' ? overview(measured) : optionView(byId[s.view])}</main>`;
  for (const b of document.querySelectorAll('[data-go]')) b.addEventListener('click', () => go(JSON.parse(b.dataset.go)));
  await document.fonts.ready;
  for (const fig of document.querySelectorAll('figure.cell')) {
    const phone = fig.querySelector('.phone');
    fit(phone);
    const m = measured?.frames?.[`${phone.dataset.option}/${phone.dataset.frame}/${s.theme}/${s.ts}/${s.lang}`];
    if (m) fig.querySelector('.live').innerHTML = meterLine(m, phone.dataset.frame);
    for (const r of phone.querySelectorAll('[data-row]')) r.addEventListener('click', (e) => { if (!e.target.closest('.pchip, .ptext, .pleader')) r.classList.toggle('ticked'); });
  }
  document.body.dataset.ready = '1';
};
run();
