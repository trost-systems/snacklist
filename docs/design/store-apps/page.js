import { Phone, initial, view } from './phone.js';
import * as OS from './os.js';
import * as SS from './ss.js';
import * as OB from './ob.js';

const params = new URLSearchParams(location.search);
const round = document.body.dataset.round;
const S = {
  lang: params.get('lang') === 'de' ? 'de' : 'en',
  theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  ts: ({ 200: 200, 310: 310 })[params.get('ts')] ?? 100,
  platform: params.get('platform') === 'android' ? 'android' : 'ios',
  installed: params.get('installed') !== 'no',
  scenario: (round === 'OB' ? OB : SS).scenarios.some((x) => x.id === params.get('scenario')) ? params.get('scenario') : (round === 'OB' ? OB : SS).scenarios[0].id,
};
const defaults = { lang: 'en', theme: 'light', ts: '100', platform: 'ios', installed: 'yes', scenario: (round === 'OB' ? OB : SS).scenarios[0].id };

const W = {
  en: {
    overview: 'Store apps: prototype rounds OS, SS and OB', back: 'Store apps overview',
    OB: 'Round OB: picking and linking stores during onboarding',
    OBshort: 'Peter (19 Nov 2026): “regarding linking stores: I think we missed the onboarding part.” Five ways for onboarding to pick and link stores, next to today plus job 313’s card. Taps and screens are counted against today in six scenarios.',
    overviewNote: 'Peter (18 Nov 2026): “Give me a prototype round for the open store app. I want to see where we best put these, and we might also need to think about how we allow users to select stores if we’re now starting to need to recognise them properly. Also make suggestions that scale across countries.” Two rounds, five options each, next to today. Round OB (19 Nov 2026) adds onboarding. Mock data only (the fictional Familie Brandt); nothing is sent, nothing opens.',
    OS: 'Round OS: where “Open &lt;store&gt; app” lives', SS: 'Round SS: picking and recognising stores, across countries',
    OSshort: 'Five places for the action: the store’s header, the trip strip, the store’s screen, a store menu, and the moment a store is done.',
    SSshort: 'Five ways to turn free-text stores into recognised chains with an optional branch: a chain picker, type-ahead with “Is this Lidl?”, nearby on a map, a directory by country, and a lazy match only where an app exists. With the registry proposal.',
    note: {
      OS: 'Each option shows the list of five stores (dm, Lidl, a long ALDI SÜD name, a market without an app, REWE), what a tap does with the app installed and without it, the long name and the store without an app at the largest text, and the option’s own screen. The first phone is live: tap it. The controls set language, theme, text size, platform and whether the apps are installed.',
      SS: 'Each option walks five scenarios: the household’s existing stores get linked, a new store, a store not in the registry, one chain in two countries, and a change of country. Pick a scenario above; every option shows it as a strip of frames with its taps counted.',
      OB: 'Each option walks six scenarios: a new user in Germany (Lidl, dm, REWE), a new user in Austria (Hofer, SPAR, Lidl; Hofer is ALDI SÜD with its own app), a store not in the registry, choosing nothing or skipping, a chain with two apps (BILLA or jö Bonus Club), and joining an existing household. The first phone of each strip is live: tap it. Taps count from arriving at the store step until every store with an app is linked. Mock data only.',
    },
    light: 'Light', dark: 'Dark', text: 'Text', largest: '200 % (Android’s largest)', ios: '310 % (iOS’s largest)',
    platform: 'Platform', installed: 'Apps', inst: 'installed', notInst: 'not installed', scenario: 'Scenario',
    pick: 'Pick', runner: 'Runner-up', jump: 'Recommendation, measured table and open questions',
    factsTitle: 'Today, from the code', taps: (n) => (n === null ? 'No way to open an app.' : `Taps from the list to the app: <b>${n}</b>.`),
    walkTaps: (n) => `Taps: <b>${n}</b>`,
  },
  de: {
    overview: 'Händler-Apps: Prototyp-Runden OS, SS und OB', back: 'Übersicht Händler-Apps',
    OB: 'Runde OB: Läden im Einstieg wählen und verbinden',
    OBshort: 'Peter (19. Nov 2026): „regarding linking stores: I think we missed the onboarding part.“ Fünf Wege, im Einstieg Läden zu wählen und zu verbinden, neben heute plus der Karte aus Job 313. Tipps und Bildschirme sind in sechs Szenarien gegen heute gezählt.',
    overviewNote: 'Peter (18. Nov 2026): „Give me a prototype round for the open store app. I want to see where we best put these, and we might also need to think about how we allow users to select stores if we’re now starting to need to recognise them properly. Also make suggestions that scale across countries.“ Zwei Runden mit je fünf Optionen, neben heute. Runde OB (19. Nov 2026) ergänzt den Einstieg. Nur Beispieldaten (die erfundene Familie Brandt); nichts wird gesendet, nichts öffnet sich.',
    OS: 'Runde OS: wo „&lt;Laden&gt;-App öffnen“ sitzt', SS: 'Runde SS: Läden wählen und erkennen, über Ländergrenzen',
    OSshort: 'Fünf Orte für die Aktion: der Kopf des Ladens, der Einkaufsstreifen, die Seite des Ladens, ein Laden-Menü und der Moment, in dem ein Laden erledigt ist.',
    SSshort: 'Fünf Wege, aus frei getippten Läden erkannte Ketten mit optionaler Filiale zu machen: eine Ketten-Auswahl, Vorschläge beim Tippen mit „Ist das Lidl?“, in der Nähe auf der Karte, ein Verzeichnis nach Ländern und ein fauler Abgleich nur, wo es eine App gibt. Mit dem Vorschlag für das Verzeichnis.',
    note: {
      OS: 'Jede Option zeigt die Liste mit fünf Läden (dm, Lidl, ein langer ALDI-SÜD-Name, ein Markt ohne App, REWE), was ein Tipp mit installierter und ohne App tut, den langen Namen und den Laden ohne App bei größter Schrift, und den eigenen Bildschirm der Option. Das erste Handy ist live: tipp es an. Oben stellst du Sprache, Farben, Schriftgröße, Plattform und installierte Apps ein.',
      SS: 'Jede Option geht fünf Szenarien durch: die vorhandenen Läden werden verbunden, ein neuer Laden, ein Laden, den das Verzeichnis nicht kennt, eine Kette in zwei Ländern und ein Wechsel des Landes. Wähl oben ein Szenario; jede Option zeigt es als Bildfolge mit gezählten Tipps.',
      OB: 'Jede Option geht sechs Szenarien durch: neu in Deutschland (Lidl, dm, REWE), neu in Österreich (Hofer, SPAR, Lidl; Hofer ist ALDI SÜD mit eigener App), ein Laden, den das Verzeichnis nicht kennt, nichts wählen oder überspringen, eine Kette mit zwei Apps (BILLA oder jö Bonus Club) und einem bestehenden Haushalt beitreten. Das erste Handy jeder Bildfolge ist live: tipp es an. Gezählt wird ab Ankunft im Laden-Schritt, bis jeder Laden mit App verbunden ist. Nur Beispieldaten.',
    },
    light: 'Hell', dark: 'Dunkel', text: 'Text', largest: '200 % (größte bei Android)', ios: '310 % (größte bei iOS)',
    platform: 'Plattform', installed: 'Apps', inst: 'installiert', notInst: 'nicht installiert', scenario: 'Szenario',
    pick: 'Wahl', runner: 'Zweite Wahl', jump: 'Empfehlung, Messwerte und offene Fragen',
    factsTitle: 'Heute, laut Code', taps: (n) => (n === null ? 'Keine Möglichkeit, eine App zu öffnen.' : `Tipps von der Liste bis zur App: <b>${n}</b>.`),
    walkTaps: (n) => `Tipps: <b>${n}</b>`,
  },
}[S.lang];

const FACTS = {
  en: {
    OS: [
      'A store is a household row with a free-text name (1 to 40 characters), an optional <code>seed_key</code> (only dm, lidl, edeka and hardware) and an order. No chain, branch or country (<code>supabase/migrations/20261022150000_foundation.sql</code>).',
      'The list’s store header (<code>dividers.dart</code>, min 52 px): the name badge (32 px, at most 220 px, then an ellipsis), a brand rule, the count, a 52 × 48 fold key. A tap folds; a hold does nothing since job 171.',
      'Trip mode (job 234) is on main behind <code>trip-mode</code>, internal only: a tick asks “Are you shopping right now?”, then a 52 px dark strip runs above the field (text clamped at 130 %). Its summary has a section per store.',
      'The app opens no other app today: no Android <code>&lt;queries&gt;</code> for retailers, no iOS query schemes; <code>url_launcher</code> serves legal links only.',
      'How the button would open an app (DL1 brief): Android launches the package (with <code>&lt;queries&gt;</code>), else <code>market://details</code>. iOS opens the retailer’s https link with “universal links only”; if no app takes it, the <code>itms-apps://</code> App Store page. So iOS can’t tell before the tap whether the app is there: the label stays “Open Lidl Plus” in both cases.',
    ],
    SS: [
      'Stores are free text per household. <code>add_store</code> maps a typed name to a seed for dm, Lidl and EDEKA only (their researched layouts), and a rename clears the seed.',
      'Onboarding offers ten German chains as chips (<code>popular_stores.dart</code>): EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto, Penny, dm, Rossmann. Only three are known to the server.',
      'Households have no country or locale; only purchases record a country. Prices default to EUR.',
      'Store names appear as plain text in a neutral badge: no logos, no chain colours (Legal, Addendum D). The store-name disclaimer stands word for word under the onboarding store choices and under More › Stores (Legal L-7, N-23); the options below put it under every new chain list too, for Legal to confirm.',
    ],
  },
  de: {
    OS: [
      'Ein Laden ist eine Zeile des Haushalts mit frei getipptem Namen (1 bis 40 Zeichen), optionalem <code>seed_key</code> (nur dm, lidl, edeka und hardware) und Reihenfolge. Keine Kette, keine Filiale, kein Land (<code>supabase/migrations/20261022150000_foundation.sql</code>).',
      'Der Kopf eines Ladens auf der Liste (<code>dividers.dart</code>, mind. 52 px): das Namensschild (32 px, höchstens 220 px, dann Auslassungspunkte), eine Linie, die Anzahl, eine Klapp-Taste 52 × 48. Tippen klappt; Halten tut seit Job 171 nichts.',
      'Der Einkaufsmodus (Job 234) ist auf main hinter <code>trip-mode</code>, nur intern: ein Haken fragt „Kaufst du gerade ein?“, dann läuft ein 52 px dunkler Streifen über dem Feld (Text bei 130 % gedeckelt). Die Übersicht hat einen Abschnitt je Laden.',
      'Heute öffnet die App keine andere App: keine Android-<code>&lt;queries&gt;</code> für Händler, keine iOS-Query-Schemes; <code>url_launcher</code> öffnet nur Rechtstexte.',
      'Wie der Knopf eine App öffnen würde (DL1-Auftrag): Android startet das Paket (mit <code>&lt;queries&gt;</code>), sonst <code>market://details</code>. iOS öffnet den https-Link des Händlers mit „nur Universal Links“; nimmt ihn keine App an, die <code>itms-apps://</code>-Seite im App Store. iOS weiß also vor dem Tipp nicht, ob die App da ist: die Beschriftung bleibt in beiden Fällen „Lidl Plus öffnen“.',
    ],
    SS: [
      'Läden sind freier Text je Haushalt. <code>add_store</code> ordnet einem getippten Namen nur für dm, Lidl und EDEKA einen Seed zu (ihre recherchierten Laufwege), und Umbenennen löscht den Seed.',
      'Der Einstieg bietet zehn deutsche Ketten als Chips an (<code>popular_stores.dart</code>): EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto, Penny, dm, Rossmann. Nur drei kennt der Server.',
      'Haushalte haben kein Land und keine Sprache; nur Käufe speichern ein Land. Preise sind standardmäßig in EUR.',
      'Ladennamen erscheinen als reiner Text in einem neutralen Schild: keine Logos, keine Kettenfarben (Legal, Addendum D). Der Hinweis zu Ladennamen steht wörtlich unter der Laden-Auswahl im Einstieg und unter Mehr › Läden (Legal L-7, N-23); die Optionen unten setzen ihn auch unter jede neue Ketten-Liste, zur Bestätigung durch Legal.',
    ],
  },
}[S.lang];

async function themeCss() {
  const css = await (await fetch(document.querySelector('link[data-tokens]').href)).text();
  const light = css.match(/:root\s*{([^}]*)}/)[1];
  const dark = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)[1];
  const st = document.createElement('style');
  st.textContent = `.th-light{${light}color-scheme:light}.th-dark{${dark}color-scheme:dark}`;
  document.head.append(st);
}

// RECOMMENDATION.md (or .de.md) is one source for the page and the PR.
function md(src) {
  const inline = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`([^`]+)`/g, '<code>$1</code>');
  const out = [];
  const lines = src.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (/^# |^<!--/.test(l)) continue;
    if (/^## /.test(l)) out.push(`<h2>${inline(l.slice(3))}</h2>`);
    else if (/^### /.test(l)) out.push(`<h3>${inline(l.slice(4))}</h3>`);
    else if (/^```/.test(l)) {
      const code = [];
      while (++i < lines.length && !/^```/.test(lines[i])) code.push(lines[i]);
      out.push(`<pre>${code.join('\n').replace(/&/g, '&amp;').replace(/</g, '&lt;')}</pre>`);
    } else if (/^\|/.test(l)) {
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) rows.push(lines[i++]);
      i--;
      const cells = (r) => r.slice(1, -1).split('|').map((c) => c.trim());
      out.push(`<div class="table-wrap"><table><tr>${cells(rows[0]).map((c) => `<th>${inline(c)}</th>`).join('')}</tr>${rows.slice(2).map((r) => `<tr>${cells(r).map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</table></div>`);
    } else if (/^\d+\. |^- /.test(l)) {
      const ordered = /^\d/.test(l);
      const items = [];
      while (i < lines.length && /^\d+\. |^- /.test(lines[i])) items.push(lines[i++].replace(/^\d+\. |^- /, ''));
      i--;
      out.push(`<${ordered ? 'ol' : 'ul'}>${items.map((x) => `<li>${inline(x)}</li>`).join('')}</${ordered ? 'ol' : 'ul'}>`);
    } else if (l.trim()) out.push(`<p>${inline(l)}</p>`);
  }
  return out.join('\n');
}

const recOf = async (path) => {
  const src = await (await fetch(path)).text();
  return { src, pick: src.match(/<!-- pick: (\w+) -->/)?.[1], runner: src.match(/<!-- runner-up: (\w+) -->/)?.[1] };
};
const recFile = S.lang === 'de' ? 'RECOMMENDATION.de.md' : 'RECOMMENDATION.md';
const btn = (k, v, label) => `<button data-set="${k}=${v}" aria-pressed="${String(S[k] === true ? 'yes' : S[k] === false ? 'no' : S[k]) === String(v)}">${label}</button>`;
const baseControls = () => `<span class="lbl">Lang</span>${btn('lang', 'en', 'English')}${btn('lang', 'de', 'Deutsch')}<span class="sep"></span>${btn('theme', 'light', W.light)}${btn('theme', 'dark', W.dark)}<span class="sep"></span>${btn('ts', 100, `${W.text} 100 %`)}${btn('ts', 200, `${W.text} ${W.largest}`)}${btn('ts', 310, `${W.text} ${W.ios}`)}`;
const qs = () => { const q = new URLSearchParams(location.search); q.delete('scenario'); const s = q.toString(); return s ? `?${s}` : ''; };
const R = { OS, SS, OB };
const optTitle = (r, id) => R[r].options.find((o) => o.id === id)?.title[S.lang] ?? '';

async function overviewPage(app) {
  const recs = { OS: await recOf(`os/${recFile}`), SS: await recOf(`ss/${recFile}`), OB: await recOf(`ob/${recFile}`) };
  const card = (id) => `<a class="ocard" href="${id.toLowerCase()}/${qs()}" data-round-link="${id}"><h2>${W[id]}</h2><p>${W[`${id}short`]}</p>
    <p><span class="tag pick">${W.pick}</span> ${optTitle(id, recs[id].pick)}</p><p><span class="tag runner">${W.runner}</span> ${optTitle(id, recs[id].runner)}</p></a>`;
  app.innerHTML = `<header class="page-head"><div class="title-row"><h1>${W.overview}</h1></div><p class="note">${W.overviewNote}</p><div class="controls">${baseControls()}</div></header>
    <div class="view"><div class="cards">${card('OB')}${card('OS')}${card('SS')}</div></div>`;
  document.title = W.overview;
}

const stateFor = (opt, f) => initial(opt, { lang: S.lang, theme: S.theme, ts: f.ts ?? S.ts, platform: S.platform, installed: S.installed, ...structuredClone(f.state) });

function mountFrame(host, opt, f) {
  const s = stateFor(opt, f);
  if (f.live) host.phone = new Phone(host, s);
  else host.innerHTML = view(s);
  if (f.scrollTo) {
    const sc = host.querySelector('[data-scroll]');
    const target = f.scrollTo.startsWith('dir-') ? host.querySelector(`[data-expanded="${f.scrollTo.slice(4)}"]`) : host.querySelector(`[data-sec="${f.scrollTo}"]`);
    if (sc && f.scrollTo === 'end') sc.scrollTop = sc.scrollHeight;
    else if (sc && target) sc.scrollTop = target.offsetTop - 4;
  }
}

async function roundPage(app) {
  const rec = await recOf(recFile);
  const mod = R[round];
  const tag = (id) => (id === rec.pick ? `<span class="tag pick">${W.pick}</span>` : id === rec.runner ? `<span class="tag runner">${W.runner}</span>` : '');
  const framesOf = (opt) => (round === 'OS' ? mod.frames(opt) : mod.walk(opt, S.scenario, S.lang));
  const cell = (opt, f, i) => `<figure class="cell"><figcaption>${f.cap[S.lang]}${f.taps !== undefined ? ` · ${W.walkTaps(f.taps)}` : ''}</figcaption><div class="host" data-frame="${opt.id}:${i}"></div></figure>`;
  const section = (opt) => {
    const fs = framesOf(opt);
    const meta = round === 'OS' ? `<p class="meter" data-taps="${opt.id}">${W.taps(opt.tapsToOpen)}</p>` : `<p class="meter" data-walk="${opt.id}">${mod.walkNote(opt, S.scenario, S.lang)}</p>`;
    return `<section class="option" id="${opt.id}" data-option="${opt.id}"><h2>${opt.title[S.lang]}${tag(opt.id)}</h2><p>${opt.desc[S.lang]}</p>${meta}<div class="frames">${fs.map((f, i) => cell(opt, f, i)).join('')}</div></section>`;
  };
  const extraControls = round === 'OS'
    ? `<span class="lbl">${W.platform}</span>${btn('platform', 'ios', 'iOS')}${btn('platform', 'android', 'Android')}<span class="sep"></span><span class="lbl">${W.installed}</span>${btn('installed', 'yes', W.inst)}${btn('installed', 'no', W.notInst)}`
    : `<span class="lbl">${W.scenario}</span>${mod.scenarios.map((x) => btn('scenario', x.id, x.title[S.lang])).join('')}`;
  app.innerHTML = `<header class="page-head">
      <div class="title-row"><h1>${W[round]}</h1><a class="back-link" href="../${qs()}">← ${W.back}</a></div>
      <p class="note">${W.note[round]}</p>
      <div class="controls">${baseControls()}</div>
      <div class="controls">${extraControls}</div>
      <p class="note"><b>${W.pick}: ${optTitle(round, rec.pick)}</b> · ${W.runner}: ${optTitle(round, rec.runner)} · <a href="#rec">${W.jump} ↓</a></p>
    </header>
    <div class="view">
      <section class="facts"><h2>${W.factsTitle}</h2><ul>${(round === 'OB' ? OB.facts[S.lang] : FACTS[round]).map((x) => `<li>${x}</li>`).join('')}</ul></section>
      ${mod.options.map(section).join('')}
      ${round === 'SS' ? await SS.registrySection(S.lang) : ''}
      <section class="rec" id="rec">${md(rec.src)}</section>
    </div>`;
  for (const opt of mod.options) {
    framesOf(opt).forEach((f, i) => mountFrame(app.querySelector(`[data-frame="${opt.id}:${i}"]`), opt, f));
  }
  document.title = W[round];
}

async function main() {
  await themeCss();
  document.documentElement.className = `th-${S.theme}`;
  document.documentElement.lang = S.lang;
  const app = document.getElementById('app');
  if (round === 'overview') await overviewPage(app); else await roundPage(app);
  app.querySelectorAll('[data-set]').forEach((b) => b.addEventListener('click', () => {
    const [k, v] = b.dataset.set.split('=');
    const q = new URLSearchParams(location.search);
    if (v === defaults[k]) q.delete(k); else q.set(k, v);
    location.search = q.toString();
  }));
  if (location.hash) document.querySelector(location.hash)?.scrollIntoView();
  fit();
  addEventListener('resize', fit);
  document.body.dataset.ready = '1';
}

// On a phone the 390 px phones shrink to the screen.
function fit() {
  const z = Math.min(1, (innerWidth - 20) / 394);
  document.querySelectorAll('.host').forEach((p) => { p.style.zoom = z < 1 ? String(z) : ''; });
}

main();
