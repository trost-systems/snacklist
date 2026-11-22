// Round SC's page: the controls, Today, SC1..SC5 in states a-e, what a tap leads to, the measurements, the
// recommendation and the open questions (RECOMMENDATION.md / .de.md, rendered here). `globalThis.show` renders one
// phone at zoom 1 for verify.mjs.
import { phone, measure, optionIds, multi } from './phone.mjs';

const params = new URLSearchParams(location.search);
const env = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: params.get('ts') === '310' ? 3.1 : 1,
  device: params.get('device') === 'android' ? 'android' : 'iphone',
  links: params.get('links') === 'today' ? 'today' : 'assumed',
};

const T = {
  en: {
    title: 'After the last item of a store: the card (round SC)',
    question: 'When the user has ticked off every item of a store that has an app link, its section hides and the “Open app” key in its header goes with it. Which card at the top of the list best helps at checkout?',
    base: 'Base: the list as it launches. RD1 look, categories hidden, compact add sheet, open-store-app on. Prices, totals, trips and the grocery log are off, so no card relies on them. Mock data only (the Brandt family). The phones are calibrated against the release web build (sc/real/).',
    legal: 'Store names are plain text with a neutral store icon. Legal Addendum D allows no retailer logos, brand colours or lookalike lettering, so the “colour/logo” idea of SC1 is the plain name.',
    controls: { lang: 'Language', theme: 'Theme', ts: 'Text size', device: 'Phone', links: 'SC2 card link' },
    vals: { en: 'English', de: 'Deutsch', light: 'Light', dark: 'Dark', 100: '100 %', 310: '310 % (largest)', iphone: 'iPhone 390×844', android: 'Android 360×640', assumed: 'If a deep link existed', today: 'Today (none verified)' },
    states: { a: '(a) REWE just finished, Lidl and dm still open', b: '(b) the last store on the list just finished', c: '(c) REWE, then Lidl finished; dm still open', d: '(d) a long store name', e: '(e) (a) at the largest text size' },
    today: 'Today, no card',
    todayBlurb: 'Left: REWE with its last item and the “Open REWE” key. Then the same list a moment later: the tick hid the section and the key. Nothing on screen opens the REWE app at the till.',
    before: 'Before the tick',
    opts: {
      SC1: ['Compact identity', 'Store icon and name, “REWE is done”, “Open REWE”, X. Smallest extra height, manual dismiss, no other action. Two finished stores: two cards, newest on top.'],
      SC2: ['Loyalty and payment', 'Store identity, “Open REWE”, and a second button straight to the customer card in the store’s app. Two finished stores: the newest only.'],
      SC3: ['Recap and undo', '“9 items bought at REWE” with the first names (a count, never money), “Open REWE”, and “Undo last tick”, which puts the last item and the REWE section back. Manual dismiss. Two finished stores: the newest only.'],
      SC4: ['Next store', 'Compact card plus “Next: Lidl · 7 left”, which scrolls to that section. No next row when it was the last store. “Open app” closes the card, with an undo snackbar. Two finished stores: the newest only.'],
      SC5: ['Session close, no trip mode', '“Finished at REWE?” with “Open REWE” and “I’m done”, which only closes the card (no trip, no log entry). Two finished stores: one combined card, “2 stores done”, one line per store.'],
    },
    sc2Note: 'No verified deep link to a customer card or payment screen exists for any chain (job 314 dropped DL2–DL4; registry: app links open the app’s start screen only). The build would hide “Customer card” until one is verified, which makes SC2 look like SC1 with a second row (switch “SC2 card link” to “Today”). See SC-Q4.',
    next: 'What a tap leads to',
    nexts: {
      SC3: 'SC3 “Undo last tick”: Apples and the REWE section with its key are back; the card is gone.',
      SC4: 'SC4 “Open REWE”: the card closes, a snackbar offers Undo (4 s). Back from the REWE app, the list shows no card.',
      SC4next: 'SC4 in (a) and (d): Lidl already starts right under the card, so “Next: Lidl” scrolls nowhere. It helps only when the next store is below the fold.',
    },
    measured: 'Measured (iPhone 390×844, English, light)',
    measuredNote: 'Rows: whole open item rows between the list’s top and the add field at scroll top. Extra: the card slot’s height (card plus 8 px above and below), which pushes every row down. Extra (c): the same with two stores finished. Last column: the states (state, language, phone) where the primary “Open” button sits under the add field at 310 % until the user scrolls. No card has text or a button outside it, overlapping, or under 44 px anywhere. Read by verify.mjs from these phones.',
    cols: ['Option', 'Rows (a)', 'Rows (b)', 'Rows (c)', 'Extra 100 %', 'Extra 310 %', 'Extra (c)', 'Primary under the add field at 310 %'],
    none: 'none',
    rec: 'Recommendation and open questions',
    copyTitle: 'New words',
    copyNote: 'Reused: “Open {app}” (storeAppOpen), “Close”, “Undo”. New, one key each:',
  },
  de: {
    title: 'Nach dem letzten Artikel eines Ladens: die Karte (Runde SC)',
    question: 'Wenn alle Artikel eines Ladens mit App-Link abgehakt sind, verschwindet sein Abschnitt und mit ihm der „App öffnen“-Knopf in der Kopfzeile. Welche Karte oben in der Liste hilft an der Kasse am meisten?',
    base: 'Basis: die Liste zum Start. RD1-Look, Kategorien ausgeblendet, kompaktes Hinzufügen, open-store-app an. Preise, Summen, Einkäufe und der Verlauf sind aus, keine Karte braucht sie. Nur Beispieldaten (Familie Brandt). Die Telefone sind am Release-Web-Build ausgemessen (sc/real/).',
    legal: 'Ladennamen stehen als einfacher Text mit einem neutralen Laden-Symbol. Rechtlicher Nachtrag D erlaubt keine Händler-Logos, Markenfarben oder nachgemachte Schrift, darum ist SC1s „Farbe/Logo“ hier der Name.',
    controls: { lang: 'Sprache', theme: 'Design', ts: 'Textgröße', device: 'Telefon', links: 'SC2 Kartenlink' },
    vals: { en: 'English', de: 'Deutsch', light: 'Hell', dark: 'Dunkel', 100: '100 %', 310: '310 % (größte)', iphone: 'iPhone 390×844', android: 'Android 360×640', assumed: 'Falls es einen Deep Link gäbe', today: 'Heute (keiner geprüft)' },
    states: { a: '(a) REWE gerade fertig, Lidl und dm noch offen', b: '(b) der letzte Laden der Liste gerade fertig', c: '(c) REWE, dann Lidl fertig; dm noch offen', d: '(d) ein langer Ladenname', e: '(e) (a) in der größten Textgröße' },
    today: 'Heute, keine Karte',
    todayBlurb: 'Links: REWE mit dem letzten Artikel und dem Knopf „REWE öffnen“. Dann dieselbe Liste einen Moment später: der Haken hat den Abschnitt und den Knopf ausgeblendet. An der Kasse öffnet nichts mehr die REWE-App.',
    before: 'Vor dem Haken',
    opts: {
      SC1: ['Kompakt mit Laden', 'Laden-Symbol und Name, „REWE ist erledigt“, „REWE öffnen“, X. Am wenigsten zusätzliche Höhe, Schließen von Hand, sonst nichts. Zwei fertige Läden: zwei Karten, die neueste oben.'],
      SC2: ['Kundenkarte und Bezahlen', 'Laden, „REWE öffnen“ und ein zweiter Knopf direkt zur Kundenkarte in der App des Ladens. Zwei fertige Läden: nur der neueste.'],
      SC3: ['Rückblick und Zurücknehmen', '„9 Artikel bei REWE gekauft“ mit den ersten Namen (eine Anzahl, nie Geld), „REWE öffnen“ und „Letzten Haken zurücknehmen“, das den letzten Artikel und den REWE-Abschnitt zurückholt. Schließen von Hand. Zwei fertige Läden: nur der neueste.'],
      SC4: ['Nächster Laden', 'Kompakte Karte plus „Weiter: Lidl · noch 7“, das zu diesem Abschnitt scrollt. Keine Weiter-Zeile, wenn es der letzte Laden war. „App öffnen“ schließt die Karte, mit Rückgängig in einer Snackbar. Zwei fertige Läden: nur der neueste.'],
      SC5: ['Abschluss ohne Einkaufsmodus', '„Fertig bei REWE?“ mit „REWE öffnen“ und „Ich bin fertig“, das nur die Karte schließt (kein Einkauf, kein Verlaufseintrag). Zwei fertige Läden: eine gemeinsame Karte, „2 Läden erledigt“, eine Zeile je Laden.'],
    },
    sc2Note: 'Für keine Kette gibt es einen geprüften Deep Link zur Kundenkarte oder zum Bezahlen (Job 314 hat DL2–DL4 gestrichen; im Register öffnen App-Links nur den Startbildschirm der App). Der Build würde „Kundenkarte“ ausblenden, bis einer geprüft ist; dann sieht SC2 aus wie SC1 mit einer zweiten Zeile („SC2 Kartenlink“ auf „Heute“ stellen). Siehe SC-Q4.',
    next: 'Wohin ein Tipp führt',
    nexts: {
      SC3: 'SC3 „Letzten Haken zurücknehmen“: Äpfel und der REWE-Abschnitt mit seinem Knopf sind zurück, die Karte ist weg.',
      SC4: 'SC4 „REWE öffnen“: die Karte schließt sich, eine Snackbar bietet Rückgängig (4 s). Zurück aus der REWE-App zeigt die Liste keine Karte.',
      SC4next: 'SC4 in (a) und (d): Lidl beginnt schon direkt unter der Karte, „Weiter: Lidl“ scrollt nirgendwohin. Es hilft nur, wenn der nächste Laden unter dem sichtbaren Bereich liegt.',
    },
    measured: 'Gemessen (iPhone 390×844, Englisch, hell)',
    measuredNote: 'Zeilen: ganze offene Artikelzeilen zwischen Listenanfang und Eingabefeld, ganz oben gescrollt. Zusätzlich: die Höhe des Kartenplatzes (Karte plus je 8 px darüber und darunter), um die jede Zeile nach unten rutscht. Zusätzlich (c): dasselbe mit zwei fertigen Läden. Letzte Spalte: die Fälle (Zustand, Sprache, Telefon), in denen der Hauptknopf „öffnen“ bei 310 % unter dem Eingabefeld liegt, bis man scrollt. Keine Karte hat Text oder Knöpfe außerhalb, überlappend oder unter 44 px. verify.mjs liest das aus diesen Telefonen.',
    cols: ['Option', 'Zeilen (a)', 'Zeilen (b)', 'Zeilen (c)', 'Zusätzlich 100 %', 'Zusätzlich 310 %', 'Zusätzlich (c)', 'Hauptknopf unter dem Eingabefeld bei 310 %'],
    none: 'keiner',
    rec: 'Empfehlung und offene Fragen',
    copyTitle: 'Neue Wörter',
    copyNote: 'Wiederverwendet: „{app} öffnen“ (storeAppOpen), „Schließen“, „Rückgängig“. Neu, je ein Schlüssel:',
  },
};

const newWords = [
  ['storeCardDone', 'REWE is done', 'REWE ist erledigt', 'SC1, SC2, SC4'],
  ['storeCardCustomerCard', 'Customer card', 'Kundenkarte', 'SC2'],
  ['storeCardBought', '9 items bought at REWE', '9 Artikel bei REWE gekauft', 'SC3'],
  ['storeCardUndoTick', 'Undo last tick', 'Letzten Haken zurücknehmen', 'SC3'],
  ['storeCardNext / Left', 'Next: Lidl · 7 left', 'Weiter: Lidl · noch 7', 'SC4'],
  ['storeCardHidden', 'REWE card hidden', 'Karte für REWE ausgeblendet', 'SC4'],
  ['storeCardFinished', 'Finished at REWE?', 'Fertig bei REWE?', 'SC5'],
  ['storeCardStoresDone', '2 stores done', '2 Läden erledigt', 'SC5'],
  ['storeCardImDone', 'I’m done', 'Ich bin fertig', 'SC5'],
];

const t = T[env.lang];
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const url = (patch) => {
  const p = new URLSearchParams(location.search);
  for (const [k, v] of Object.entries(patch)) p.set(k, v);
  return `?${p}`;
};
const seg = (key, values, current) => `<div class="seg"><span>${t.controls[key]}</span>${values.map(([v, label]) => `<a href="${url({ [key]: v })}"${String(current) === String(v) ? ' class="on"' : ''}>${esc(label)}</a>`).join('')}</div>`;

const frame = (label, opts) => `<figure class="frame"><figcaption>${esc(label)}</figcaption><div class="ph">${phone({ ...env, ...opts })}</div></figure>`;

function md(text) {
  const lines = text.split('\n');
  let html = '';
  let list = null;
  let table = [];
  const inline = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`(.+?)`/g, '<code>$1</code>');
  const flush = () => {
    if (list) html += `</${list}>`;
    list = null;
    if (table.length) {
      const [head, , ...body] = table;
      const cells = (r) => r.split('|').slice(1, -1).map((c) => c.trim());
      html += `<table><thead><tr>${cells(head).map((c) => `<th>${inline(c)}</th>`).join('')}</tr></thead><tbody>${body.map((r) => `<tr>${cells(r).map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
      table = [];
    }
  };
  for (const line of lines) {
    if (line.startsWith('|')) { if (list) { html += `</${list}>`; list = null; } table.push(line); continue; }
    if (table.length) flush();
    const h = /^(#{1,3}) (.*)/.exec(line);
    const ol = /^\d+\. (.*)/.exec(line);
    const ul = /^- (.*)/.exec(line);
    if (h) { flush(); html += `<h${h[1].length + 1}>${inline(h[2])}</h${h[1].length + 1}>`; }
    else if (ol) { if (list !== 'ol') { flush(); list = 'ol'; html += '<ol>'; } html += `<li>${inline(ol[1])}</li>`; }
    else if (ul) { if (list !== 'ul') { flush(); list = 'ul'; html += '<ul>'; } html += `<li>${inline(ul[1])}</li>`; }
    else if (line.trim()) { flush(); html += `<p>${inline(line)}</p>`; }
    else flush();
  }
  flush();
  return html;
}

async function render() {
  const root = document.getElementById('root');
  const states = ['a', 'b', 'c', 'd'];
  const optFrames = (opt) => [...states.map((s) => frame(t.states[s], { opt, state: s })), frame(t.states.e, { opt, state: 'a', ts: 3.1 })].join('');
  let measured = null;
  try { measured = await (await fetch('measured.json')).json(); } catch { /* the table waits for verify.mjs */ }
  let rec = '';
  try { rec = md(await (await fetch(env.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md')).text()); } catch { rec = ''; }
  const table = measured ? `<table class="m"><thead><tr>${t.cols.map((c) => `<th>${c}</th>`).join('')}</tr></thead><tbody>${['today', ...optionIds].map((o) => {
    const m = measured.options[o];
    return `<tr><td>${o === 'today' ? t.today : `${o} ${t.opts[o][0]}`}</td><td>${m.rows.a}</td><td>${m.rows.b}</td><td>${m.rows.c}</td><td>${m.extra100} px</td><td>${m.extra310} px</td><td>${m.extraC} px</td><td>${m.overflow310.length ? esc(m.overflow310.join('; ')) : t.none}</td></tr>`;
  }).join('')}</tbody></table>` : '';
  root.innerHTML = `
    <header class="top"><h1>${t.title}</h1><p>${t.question}</p><p class="muted">${t.base}</p><p class="muted">${t.legal}</p>
      <nav class="ctl">${seg('lang', [['en', t.vals.en], ['de', t.vals.de]], env.lang)}${seg('theme', [['light', t.vals.light], ['dark', t.vals.dark]], env.theme)}${seg('ts', [['100', t.vals[100]], ['310', t.vals[310]]], env.ts === 1 ? 100 : 310)}${seg('device', [['iphone', t.vals.iphone], ['android', t.vals.android]], env.device)}${seg('links', [['assumed', t.vals.assumed], ['today', t.vals.today]], env.links)}</nav>
    </header>
    <section class="opt" id="today"><h2>${t.today}</h2><p>${t.todayBlurb}</p><div class="frames">${frame(t.before, { opt: 'before', state: 'a' })}${states.map((s) => frame(t.states[s], { opt: 'today', state: s })).join('')}${frame(t.states.e, { opt: 'today', state: 'a', ts: 3.1 })}</div></section>
    ${optionIds.map((o) => `<section class="opt" id="${o}"><h2>${o} ${t.opts[o][0]}</h2><p>${t.opts[o][1]}</p>${o === 'SC2' ? `<p class="note">${t.sc2Note}</p>` : ''}<div class="frames">${optFrames(o)}</div></section>`).join('')}
    <section class="opt" id="next"><h2>${t.next}</h2><div class="frames">${frame(t.nexts.SC3, { opt: 'SC3', state: 'a', frame: 'undone' })}${frame(t.nexts.SC4, { opt: 'SC4', state: 'a', frame: 'opened' })}${frame(t.nexts.SC4next, { opt: 'SC4', state: 'd' })}</div></section>
    <section class="doc" id="measured"><h2>${t.measured}</h2><p class="muted">${t.measuredNote}</p>${table}</section>
    <section class="doc" id="copy"><h2>${t.copyTitle}</h2><p class="muted">${t.copyNote}</p><table><thead><tr><th>key</th><th>EN</th><th>DE</th><th></th></tr></thead><tbody>${newWords.map((w) => `<tr>${w.map((c) => `<td>${esc(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></section>
    <section class="doc" id="rec"><h2>${t.rec}</h2>${rec}</section>`;
  document.documentElement.lang = env.lang;
  document.title = t.title;
  document.body.dataset.ready = '1';
}

// verify.mjs: one phone at the top left, zoom 1, measured.
globalThis.show = (opts) => {
  const stage = document.getElementById('stage');
  stage.innerHTML = phone({ ...env, ...opts });
  return measure(stage.firstElementChild);
};
globalThis.multi = multi;

if (params.get('measure') === '1') {
  document.body.classList.add('measuring');
  document.body.dataset.ready = '1';
} else {
  render();
}
