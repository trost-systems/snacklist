// Round SS: how users pick and recognise stores, across countries. SS1 to SS5 as hook records for phone.js, each with
// a walk per scenario: frames (state over phone.initial), a caption and the taps from the list to that frame.
import { ic, esc, t, badge, chains, chainsByCountry } from './phone.js';
import { listStores } from './data.js';

const at = (act, arg) => `data-act="${act}"${arg === undefined ? '' : ` data-arg="${esc(arg)}"`}`;
const L = (en, de) => ({ en, de });
const cname = (s, cc) => t(s).countries[cc];

// --- The household before: free-text stores, nothing linked. "Aldi" is two chains in Germany. ----------------------

const legacy = () => {
  const by = Object.fromEntries(listStores.map((x) => [x.id, x]));
  return [
    { ...structuredClone(by.dm), link: null },
    { ...structuredClone(by.lidl), link: null },
    { ...structuredClone(by.aldi), name: 'Aldi', link: null },
    { ...structuredClone(by.markt), link: null },
  ];
};
const linkAll = (stores, map) => stores.map((x) => (x.id in map ? { ...x, ...map[x.id] } : x));
const migrated = (extra = {}) => linkAll(legacy(), { dm: { link: 'dm:DE' }, lidl: { link: 'lidl:DE' }, aldi: { link: 'aldi-sued:DE' }, markt: { own: true }, ...extra });
const withStore = (stores, store) => [...stores, { items: [], ...store }];

// --- Shared pieces ---------------------------------------------------------------------------------------------------

const disclaimer = (s) => `<p class="small disclaimer">${esc(t(s).storesDisclaimer)}</p>`;
const appTag = (s, key) => (chains[key]?.app ? `<span class="apptag">${ic('open_in_new', 'sm')}${esc(chains[key].app)}</span>` : `<span class="apptag none">${esc(t(s).noApp)}</span>`);

// Under a store's name on the Stores screen: what it is linked to.
const storeSub = (s, st) => {
  const c = st.link && chains[st.link];
  if (c) return `<span class="ssub linked" data-linked="${st.link}">${ic('check_circle_outline')}${esc(c.name)} · ${esc(cname(s, c.country))}${st.branch ? ` · ${esc(st.branch)}` : ''}${c.app ? ` · ${esc(c.app)}` : ''}</span>`;
  if (st.own) return `<span class="ssub" data-own>${esc(t(s).ownStore)}${st.branch ? ` · ${esc(st.branch)}` : ''}</span>`;
  return s.opt.unlinkedSub?.(s, st) ?? '';
};

// On the store's own screen: chain, branch, app.
const storeExtra = (s, st) => {
  const c = st.link && chains[st.link];
  if (!c) {
    return `<div class="card chaincard"><button class="crow" ${at('noop')}>${ic('link')}<span class="grow">${esc(st.own ? t(s).ownStore : t(s).linkChain)}</span>${ic('chevron_right')}</button></div>`;
  }
  return `<div class="card chaincard" data-chaincard="${st.link}">
    <div class="crow"><span class="clabel">${esc(t(s).chainRow)}</span><b class="grow">${esc(c.name)} · ${esc(cname(s, c.country))}</b>${ic('chevron_right')}</div>
    <div class="crow"><span class="clabel">${esc(t(s).branchRow)}</span><span class="grow">${esc(st.branch ?? t(s).branchNone)}</span>${ic('chevron_right')}</div>
    <div class="crow"><span class="clabel">${esc(t(s).appRowLabel)}</span><span class="grow">${c.app ? esc(c.app) : esc(t(s).appRowNone)}</span></div></div>`;
};

// OS1's header key on linked stores, so the list shows what linking buys.
const headerExtra = (s, st) => {
  const c = st.link && chains[st.link];
  return c?.app ? `<button class="appbtn" ${at('noop')} aria-label="${esc(t(s).openApp(c.app))}" data-open="${st.id}">${ic('open_in_new')}</button>` : '';
};

const closebar = (s, title) => `<div class="appbar plain"><button class="iconbtn" ${at('noop')} aria-label="${esc(t(s).cancel)}">${ic('close')}</button><h1>${esc(title)}</h1></div>`;
const backbar = (s, title) => `<div class="appbar plain"><button class="iconbtn" ${at('noop')} aria-label="${esc(t(s).back)}">${ic('arrow_back')}</button><h1>${esc(title)}</h1></div>`;
const field = (s, value, placeholder, icon = null) => `<div class="hexfield"><span>${icon ? ic(icon) : ''}<span class="grow fieldtext ${value ? '' : 'ph'}">${esc(value || placeholder)}</span>${value ? '<i class="caretline"></i>' : ''}</span></div>`;

const matches = (q, keys) => {
  const n = q.trim().toLowerCase();
  if (!n) return keys;
  return keys.filter((k) => chains[k].aliases.some((a) => a.startsWith(n) || n.startsWith(a)) || chains[k].name.toLowerCase().startsWith(n));
};
const chainRow = (s, key, { sub = true, hi = false } = {}) => `<button class="pickrow ${hi ? 'hi' : ''}" ${at('noop')} data-chain="${key}"><span class="grow"><b>${esc(chains[key].name)}</b>${sub ? `<span class="small">${esc(cname(s, chains[key].country))}</span>` : ''}</span>${appTag(s, key)}</button>`;
const keepRow = (s, q) => `<button class="pickrow keep" ${at('noop')} data-keep>${ic('add')}<span class="grow"><b>${esc(q ? t(s).notListed(q) : t(s).notListedPlain)}</b><span class="small">${esc(t(s).notListedBody)}</span></span></button>`;

// --- Screens -----------------------------------------------------------------------------------------------------------

// SS1: one country's chains, a search, the country from the phone's region.
const pickScreen = (s) => {
  const keys = matches(s.query, chainsByCountry[s.country]);
  return `${closebar(s, t(s).addStoreTitle)}
  <div class="body" data-scroll><div class="col">
    <div class="countryline" data-country="${s.country}">${ic('public')}<span class="grow">${esc(s.regionNote ? t(s).countryFromPhone(cname(s, s.country)) : cname(s, s.country))}</span><button class="textbtn" ${at('noop')}>${esc(t(s).changeCountry)}</button></div>
    ${field(s, s.query, t(s).searchChains, 'search')}
    <div class="picklist">${keys.map((k) => chainRow(s, k, { sub: false, hi: k === s.hi })).join('')}${keepRow(s, s.query)}</div>
    ${s.note ? `<p class="small hint">${esc(s.note[s.lang])}</p>` : ''}
    ${disclaimer(s)}
  </div></div>`;
};

// SS4: every country, the household's first; chains as chips; "Other / not listed" last.
const dirScreen = (s) => {
  const order = [s.country, ...Object.keys(chainsByCountry).filter((c) => c !== s.country)];
  const chip = (k) => `<button class="chip ${k === s.hi ? 'on' : ''}" ${at('noop')} data-chain="${k}">${esc(chains[k].name)}${chains[k].app ? ic('open_in_new', 'sm') : ''}</button>`;
  const others = Object.keys(t(s).countries).filter((c) => c !== s.country);
  return `${backbar(s, t(s).directoryTitle)}
  <div class="body" data-scroll><div class="col">
    <div class="section">${esc(cname(s, order[0]))}</div>
    <div class="chips" data-dir="${order[0]}">${chainsByCountry[order[0]].map(chip).join('')}</div>
    <p class="small">${ic('open_in_new', 'sm')} ${esc(t(s).hasApp)}</p>
    <div class="section">${esc(t(s).otherCountries)}</div>
    ${others.map((c) => (c === s.expand && chainsByCountry[c]
      ? `<div class="crow open" data-expanded="${c}"><b class="grow">${esc(cname(s, c))}</b>${ic('expand_more')}</div><div class="chips" data-dir="${c}">${chainsByCountry[c].map(chip).join('')}</div>`
      : `<button class="crow" ${at('noop')}><span class="grow">${esc(cname(s, c))}</span>${ic('chevron_right')}</button>`)).join('')}
    ${keepRow(s, '')}
    ${disclaimer(s)}
  </div></div>`;
};

// SS4's migration: what the server matched, Aldi to choose.
const checkScreen = (s) => `${backbar(s, t(s).migrateTitle)}
  <div class="body" data-scroll><div class="col">
    <p class="small">${esc(t(s).migrateBody)}</p>
    ${s.stores.map((st) => {
      const amb = st.amb && !st.link;
      return `<div class="checkrow" data-check="${st.id}"><span class="grow"><b>${esc(st.name)}</b>${amb ? '' : `<span class="small">${st.link ? `${esc(chains[st.link].name)} · ${esc(cname(s, chains[st.link].country))}` : esc(t(s).ownStore)}</span>`}</span>
        ${amb ? '' : `<span class="hexbox ${st.link ? 'on' : ''}">${st.link ? ic('check') : ''}</span>`}</div>
        ${amb ? `<div class="chips">${st.amb.map((k) => `<button class="chip" ${at('noop')} data-chain="${k}">${esc(chains[k].name)}</button>`).join('')}<button class="chip" ${at('noop')}>${esc(t(s).ownStore)}</button></div>` : ''}`;
    }).join('')}
    <button class="tact honey" ${at('noop')}><span>${esc(t(s).done)}</span></button>
    ${disclaimer(s)}
  </div></div>`;

// SS3: nearby, after a once-only location permission. Map tiles are abstract; addresses are fictional.
const nearbyScreen = (s) => `${backbar(s, t(s).nearbyTitle)}
  <div class="body" data-scroll><div class="col">
    <div class="map" aria-hidden="true">${s.places.map((p, i) => `<span class="pin" style="left:${18 + ((i * 37) % 64)}%;top:${22 + ((i * 29) % 56)}%">${i + 1}</span>`).join('')}<span class="me"></span></div>
    <p class="small privacy">${ic('lock_outline', 'sm')} ${esc(t(s).nearbyPrivacy)}</p>
    ${s.places.map((p, i) => `<button class="pickrow ${p.mine ? 'mine' : ''} ${i === s.hiPlace ? 'hi' : ''}" ${at('noop')} data-place="${i}"><span class="pinno">${i + 1}</span><span class="grow"><b>${esc(p.link ? chains[p.link].name : p.name)}</b><span class="small">${esc(p.branch)} · ${esc(p.dist)}${p.mine ? ` · ${esc(p.mine[s.lang])}` : ''}</span></span>${p.link ? appTag(s, p.link) : ''}</button>`).join('')}
    ${field(s, '', t(s).searchTown, 'search')}
    ${disclaimer(s)}
  </div></div>`;

// More › Settings, with the household's shopping country (SS2, SS4).
const settingsScreen = (s) => `${backbar(s, s.lang === 'de' ? 'Einstellungen' : 'Settings')}
  <div class="body" data-scroll><div class="col"><div class="groups"><div class="group">
    <div class="mrow">${ic('language')}<span class="grow"><span class="mlabel">${s.lang === 'de' ? 'Sprache' : 'Language'}</span><span class="msub">${s.lang === 'de' ? 'Deutsch' : 'English'}</span></span></div>
    <button class="mrow" ${at('noop')} data-row="country">${ic('public')}<span class="grow"><span class="mlabel">${esc(t(s).householdCountry)}</span><span class="msub">${esc(cname(s, s.country))}</span></span>${ic('chevron_right')}</button>
  </div></div><p class="small">${esc(t(s).countryAllNote)}</p></div></div>`;

const sheets = {
  // The add-store sheet with a name field; SS2 lists matching chains under it, SS3 offers "Find nearby".
  add: (s) => {
    const sug = s.opt.suggest ? s.opt.suggest(s) : [];
    return `<div class="shead"><h2>${esc(t(s).addStoreTitle)}</h2></div><div class="sbody">
      <div class="field"><span class="flabel">${esc(t(s).newStoreName)}</span>${field(s, s.typed, '')}</div>
      ${sug.length ? `<div class="picklist" data-suggest>${sug.map((k) => chainRow(s, k)).join('')}</div>` : ''}
      ${s.opt.addExtra?.(s) ?? ''}
      <button class="tact honey" ${at('noop')}><span>${esc(t(s).save)}</span></button>
      ${sug.length ? disclaimer(s) : ''}</div>`;
  },
  confirm: (s) => {
    const c = chains[s.sheet.key];
    return `<div class="shead"><h2>${esc(t(s).isThis(`${c.name} (${cname(s, c.country)})`))}</h2></div><div class="sbody">
      <p class="lead">${esc(t(s).isThisBody(c.app))}</p>
      <button class="tact honey" ${at('noop')}><span>${esc(t(s).yes)}</span></button><button class="textbtn center" ${at('noop')}>${esc(t(s).notThis)}</button></div>`;
  },
  which: (s) => `<div class="shead"><h2>${esc(t(s).whichOne(s.sheet.name))}</h2></div><div class="sbody">
      <p class="small">${esc(t(s).whichOneBody)}</p>
      <div class="picklist">${s.sheet.keys.map((k) => chainRow(s, k, { sub: false })).join('')}</div>
      <button class="textbtn center" ${at('noop')}>${esc(t(s).notThis)}</button>${disclaimer(s)}</div>`,
  country: (s) => `<div class="shead"><h2>${esc(s.sheet.household ? t(s).householdCountry : t(s).countrySheet)}</h2></div><div class="sbody">
      ${Object.keys(t(s).countries).map((c) => `<button class="check ${c === s.sheet.pick ? 'on' : ''}" ${at('noop')} data-cc="${c}"><span class="hexbox">${c === s.sheet.pick ? ic('check') : ''}</span><span class="grow">${esc(cname(s, c))}</span></button>`).join('')}
      <p class="small">${esc(s.sheet.household ? t(s).countryAllNote : t(s).holidayHint)}</p></div>`,
};

const locDialog = (s) => `<div class="sysalert" data-dialog="loc"><b>${esc(t(s).locAskTitle)}</b><p>${esc(t(s).locAskBody)}</p>
  <div class="mini-map"></div><button ${at('noop')}>${esc(t(s).locOnce)}</button><button ${at('noop')}>${esc(t(s).locWhile)}</button><button ${at('noop')}>${esc(t(s).locNo)}</button></div>`;

// A card at the top of the list: SS2 asks per matched store, SS5 suggests where an app exists.
const listCard = (s) => {
  const c = s.card;
  if (!c) return '';
  const counter = c.of ? `<span class="small">${c.of}</span>` : '';
  if (c.kind === 'which') {
    return `<div class="card asks" data-card="which">${counter}<b>${esc(c.title[s.lang])}</b><div class="chips">${c.keys.map((k) => `<button class="chip" ${at('noop')} data-chain="${k}">${esc(chains[k].name)}</button>`).join('')}<button class="chip" ${at('noop')}>${esc(c.no[s.lang])}</button></div></div>`;
  }
  return `<div class="card asks" data-card="${c.kind}">${counter}<b>${esc(c.title[s.lang])}</b><div class="cardbtns"><button class="tact honey" ${at('noop')}><span>${esc(c.yes[s.lang])}</span></button><button class="textbtn" ${at('noop')}>${esc(c.no[s.lang])}</button></div></div>`;
};

// SS4's banner on the Stores screen after the server linked the clear matches.
const storesTop = (s) => (s.banner ? `<div class="card asks" data-card="recognised"><b>${esc(t(s).migrateTitle)}</b><p class="small">${esc(t(s).migrateBody)}</p><div class="cardbtns"><button class="tact honey" ${at('noop')}><span>${esc(t(s).migrateCheck)}</span></button></div></div>` : '');

const common = {
  storeSub, storeExtra, headerExtra, storesTop, listTop: listCard,
  screens: { pick: pickScreen, dir: dirScreen, check: checkScreen, nearby: nearbyScreen, settings: settingsScreen },
  sheet: (s) => sheets[s.sheet.kind](s),
  dialog: (s) => locDialog(s),
};

// --- The options ---------------------------------------------------------------------------------------------------

const ssOpt = (o) => ({ ...common, ...o });

const SS1 = ssOpt({
  id: 'SS1', slug: 'chain-picker',
  title: { en: 'SS1 A chain picker, country from the phone', de: 'SS1 Eine Ketten-Auswahl, Land vom Handy' },
  desc: {
    en: '“Add store” opens a searchable list of the chains in one country, taken from the phone’s region (de-AT → Austria), with “Change” next to it. The last row keeps whatever you typed as your own store. Existing stores get a “Link to a chain” line on the Stores screen. Explicit and predictable; every store costs a pick.',
    de: '„Laden hinzufügen“ öffnet eine durchsuchbare Liste der Ketten eines Landes, aus der Region des Handys (de-AT → Österreich), mit „Ändern“ daneben. Die letzte Zeile behält, was du getippt hast, als eigenen Laden. Vorhandene Läden bekommen auf der Seite Läden eine Zeile „Mit einer Kette verbinden“. Ausdrücklich und vorhersehbar; jeder Laden kostet eine Wahl.',
  },
  unlinkedSub: (s) => `<span class="ssub link">${ic('link')}${esc(t(s).linkChain)}</span>`,
});

const SS2 = ssOpt({
  id: 'SS2', slug: 'type-ahead-confirm',
  title: { en: 'SS2 Type as today, matches offered, “Is this Lidl?”', de: 'SS2 Tippen wie heute, Treffer angeboten, „Ist das Lidl?“' },
  desc: {
    en: 'The add-store field stays. While you type, matching chains appear under it: the household’s country first, then any country, so “Hofer” finds Austria’s without a setting. Saving a plain name that matches asks once: “Is this Lidl (Germany)?”. Existing stores get the same question as a card on the list, one store at a time; “Aldi” asks which one.',
    de: 'Das Feld zum Hinzufügen bleibt. Beim Tippen erscheinen passende Ketten darunter: erst das Land des Haushalts, dann jedes Land, also findet „Hofer“ die österreichische ohne Einstellung. Wer einen passenden Namen einfach speichert, wird einmal gefragt: „Ist das Lidl (Deutschland)?“. Vorhandene Läden bekommen dieselbe Frage als Karte auf der Liste, ein Laden nach dem anderen; bei „Aldi“ heißt sie „Welches?“.',
  },
  suggest: (s) => {
    if (!s.typed) return [];
    const home = matches(s.typed, chainsByCountry[s.country]);
    const rest = Object.keys(chains).filter((k) => !home.includes(k) && matches(s.typed, [k]).length);
    return [...home, ...rest].slice(0, 4);
  },
});

const SS3 = ssOpt({
  id: 'SS3', slug: 'nearby-map',
  title: { en: 'SS3 Find it nearby (location on a tap)', de: 'SS3 In der Nähe finden (Standort auf Tipp)' },
  desc: {
    en: '“Find nearby” in the add sheet asks for the location once and lists the shops around you from map data, each with its chain, address and distance. Picking one links the chain and the branch, and the branch tells the country, so there is no country setting. Without location you search a town or postcode. Needs a map data provider: your location goes to it (a note for Legal).',
    de: '„In der Nähe suchen“ im Hinzufügen-Blatt fragt einmal nach dem Standort und listet die Läden um dich aus Kartendaten, jeweils mit Kette, Adresse und Entfernung. Die Wahl verbindet Kette und Filiale, und die Filiale sagt das Land, also gibt es keine Land-Einstellung. Ohne Standort suchst du einen Ort oder eine PLZ. Braucht einen Kartendienst: dein Standort geht an ihn (Hinweis für Legal).',
  },
  addExtra: (s) => `<button class="tact" ${at('noop')} data-nearby><span>${ic('near_me_outlined', 'sm')}${esc(t(s).nearby)}</span></button><p class="small">${esc(t(s).nearbyBody)}</p>`,
});

const SS4 = ssOpt({
  id: 'SS4', slug: 'country-directory',
  title: { en: 'SS4 A directory by country, plus “Other”', de: 'SS4 Ein Verzeichnis nach Ländern, plus „Anderer“' },
  desc: {
    en: '“Add store” opens all chains as chips, the household’s country first and the others folded below, with “Other / not listed” at the end for a free name. The household has a shopping country under Settings. Existing stores: the server links the clear ones, and one “Check” page shows them with Aldi to choose.',
    de: '„Laden hinzufügen“ zeigt alle Ketten als Chips, das Land des Haushalts zuerst, die anderen darunter zugeklappt, und am Ende „Anderer / nicht dabei“ für einen freien Namen. Der Haushalt hat unter Einstellungen ein Einkaufsland. Vorhandene Läden: der Server verbindet die eindeutigen, und eine Seite „Prüfen“ zeigt sie, Aldi zum Auswählen.',
  },
});

const SS5 = ssOpt({
  id: 'SS5', slug: 'lazy-match',
  title: { en: 'SS5 Lazy: free text stays, a match only where an app exists', de: 'SS5 Faul: freier Text bleibt, ein Treffer nur, wo es eine App gibt' },
  desc: {
    en: 'Nothing changes when you add a store. The server matches names against the registry, and only when the match has an app does the list offer, once per store: “Looks like Lidl. Show ‘Open Lidl Plus’ on the list?”. Country is the phone’s region, then any country. Stores without an app are never asked about.',
    de: 'Beim Hinzufügen ändert sich nichts. Der Server gleicht Namen mit dem Verzeichnis ab, und nur wenn der Treffer eine App hat, fragt die Liste einmal je Laden: „Sieht nach Lidl aus. ‚Lidl Plus öffnen‘ auf der Liste zeigen?“. Das Land ist die Region des Handys, dann jedes Land. Läden ohne App werden nie gefragt.',
  },
});

export const options = [SS1, SS2, SS3, SS4, SS5];

export const scenarios = [
  { id: 'migrate', title: L('Existing stores', 'Vorhandene Läden') },
  { id: 'new', title: L('A new store', 'Ein neuer Laden') },
  { id: 'unlisted', title: L('Not in the list', 'Nicht in der Liste') },
  { id: 'twocountries', title: L('One chain, two countries', 'Eine Kette, zwei Länder') },
  { id: 'country', title: L('Changing country', 'Land wechseln') },
];

// --- Walks -------------------------------------------------------------------------------------------------------------

const F = (cap, taps, state) => ({ cap, taps, state });
const stores = (st, more = {}) => ({ screen: 'stores', stores: st, ...more });
const list = (st, more = {}) => ({ screen: 'list', stores: st, ...more });
const hofer = { id: 'hofer', name: 'Hofer', link: 'aldi-sued:AT', items: [] };
const rewe = { id: 'rewe', name: 'REWE', link: 'rewe:DE', items: [] };
const hof = { id: 'hof', name: 'Hofladen Sonnenwiese', own: true, items: [] };

const placesHome = (mine = false) => [
  { link: 'lidl:DE', branch: 'Lindenallee 12', dist: '350 m', mine: mine ? L('your “Lidl”', 'dein „Lidl“') : null },
  { link: 'rewe:DE', branch: 'Marktplatz 3', dist: '600 m' },
  { link: 'dm:DE', branch: 'Marktplatz 5', dist: '650 m', mine: mine ? L('your “dm”', 'dein „dm“') : null },
  { link: 'aldi-sued:DE', branch: 'Bahnhofstraße 40', dist: '900 m', mine: mine ? L('your “Aldi”', 'dein „Aldi“') : null },
  { link: null, name: 'Hofladen Sonnenwiese', branch: 'Feldweg 2', dist: '2.1 km' },
];
const placesAT = [
  { link: 'aldi-sued:AT', branch: 'Grenzweg 3', dist: '200 m' },
  { link: 'billa:AT', branch: 'Brückenplatz 1', dist: '450 m' },
  { link: 'lidl:AT', branch: 'Uferstraße 18', dist: '700 m' },
  { link: 'spar-at:AT', branch: 'Kirchgasse 7', dist: '800 m' },
];
const placesFR = [
  { link: 'carrefour:FR', branch: 'Rue du Marché 9', dist: '300 m' },
  { link: 'lidl:FR', branch: 'Avenue de la Gare 21', dist: '550 m' },
  { link: 'aldi-nord:FR', branch: 'Rue des Tilleuls 4', dist: '900 m' },
  { link: 'leclerc:FR', branch: 'Route de Strasbourg', dist: '2.4 km' },
];

const sameLidl = L('Lidl Plus is one app in every country; the entry for Austria differs only in its web link.', 'Lidl Plus ist in jedem Land dieselbe App; der Eintrag für Österreich unterscheidet sich nur im Web-Link.');
const hoferNote = L('Hofer is ALDI SÜD in Austria, with its own app (HOFER). In France, Spain and the Netherlands “ALDI” is ALDI Nord’s.', 'Hofer ist ALDI SÜD in Österreich, mit eigener App (HOFER). In Frankreich, Spanien und den Niederlanden ist „ALDI“ die von ALDI Nord.');

const walks = {
  SS1: {
    migrate: [
      F(L('Stores: each says “Link to a chain”', 'Läden: jeder sagt „Mit einer Kette verbinden“'), 1, stores(legacy())),
      F(L('Aldi: the picker with its name', 'Aldi: die Auswahl mit seinem Namen'), 2, { screen: 'pick', query: 'Aldi', regionNote: true }),
      F(L('After 4 stores (2 taps each)', 'Nach 4 Läden (je 2 Tipps)'), 9, stores(migrated())),
    ],
    new: [
      F(L('Add store: Germany’s chains', 'Laden hinzufügen: Ketten in Deutschland'), 2, { screen: 'pick', regionNote: true }),
      F(L('Typed “re”', '„re“ getippt'), 2, { screen: 'pick', query: 're', regionNote: true, hi: 'rewe:DE' }),
      F(L('REWE linked', 'REWE verbunden'), 3, stores(withStore(migrated(), rewe))),
    ],
    unlisted: [
      F(L('No chain matches: keep it as typed', 'Keine Kette passt: so behalten'), 2, { screen: 'pick', query: 'Hofladen Sonnenwiese', regionNote: true }),
      F(L('Own store, no app button', 'Eigener Laden, ohne App-Knopf'), 3, stores(withStore(migrated(), hof))),
    ],
    twocountries: [
      F(L('Change country for this store', 'Land für diesen Laden ändern'), 3, { screen: 'pick', regionNote: true, sheet: { kind: 'country', pick: 'AT' } }),
      F(L('Austria’s chains', 'Ketten in Österreich'), 4, { screen: 'pick', country: 'AT', hi: 'aldi-sued:AT', note: hoferNote }),
      F(L('Hofer (AT) next to Lidl (DE)', 'Hofer (AT) neben Lidl (DE)'), 5, stores(withStore(migrated(), hofer))),
    ],
    country: [
      F(L('Moved to France: Change, France', 'Nach Frankreich gezogen: Ändern, Frankreich'), 3, { screen: 'pick', regionNote: true, sheet: { kind: 'country', pick: 'FR' } }),
      F(L('France’s chains (ALDI is ALDI Nord’s)', 'Ketten in Frankreich (ALDI ist von ALDI Nord)'), 4, { screen: 'pick', country: 'FR', hi: 'carrefour:FR' }),
      F(L('Old stores keep Germany', 'Alte Läden behalten Deutschland'), 5, stores(withStore(migrated(), { id: 'carrefour', name: 'Carrefour', link: 'carrefour:FR' }))),
    ],
  },
  SS2: {
    migrate: [
      F(L('A card on the list, store by store', 'Eine Karte auf der Liste, Laden für Laden'), 0, list(legacy(), { card: { kind: 'confirm', of: '1 / 3', title: L('Is your “Lidl” the chain Lidl (Germany)?', 'Ist dein „Lidl“ die Kette Lidl (Deutschland)?'), yes: L('Yes', 'Ja'), no: L('No', 'Nein') } })),
      F(L('“Aldi” is two chains: which one?', '„Aldi“ sind zwei Ketten: welche?'), 2, list(linkAll(legacy(), { lidl: { link: 'lidl:DE' }, dm: { link: 'dm:DE' } }), { card: { kind: 'which', of: '3 / 3', keys: ['aldi-sued:DE', 'aldi-nord:DE'], title: L('Which Aldi is your “Aldi”?', 'Welches Aldi ist dein „Aldi“?'), no: L('Neither', 'Keins') } })),
      F(L('Linked: the market is never asked', 'Verbunden: der Markt wird nie gefragt'), 3, list(linkAll(legacy(), { lidl: { link: 'lidl:DE' }, dm: { link: 'dm:DE' }, aldi: { link: 'aldi-sued:DE' } }))),
    ],
    new: [
      F(L('Typing “Re”: REWE offered', '„Re“ getippt: REWE angeboten'), 2, stores(migrated(), { sheet: { kind: 'add' }, typed: 'Re' })),
      F(L('Saved without picking: asked once', 'Ohne Wahl gespeichert: einmal gefragt'), 3, stores(withStore(migrated(), { ...rewe, link: null }), { sheet: { kind: 'confirm', key: 'rewe:DE' } })),
      F(L('REWE linked', 'REWE verbunden'), 4, stores(withStore(migrated(), rewe))),
    ],
    unlisted: [
      F(L('Nothing matches: just save', 'Nichts passt: einfach speichern'), 2, stores(migrated(), { sheet: { kind: 'add' }, typed: 'Hofladen Sonnenwiese' })),
      F(L('Own store, no question', 'Eigener Laden, keine Frage'), 3, stores(withStore(migrated(), hof))),
    ],
    twocountries: [
      F(L('“Hof”: Austria’s Hofer, no setting', '„Hof“: Hofer aus Österreich, ohne Einstellung'), 2, stores(migrated(), { sheet: { kind: 'add' }, typed: 'Hof' })),
      F(L('“Lidl”: Germany first, then Austria', '„Lidl“: erst Deutschland, dann Österreich'), 2, stores(migrated(), { sheet: { kind: 'add' }, typed: 'Lidl' })),
      F(L('Hofer (AT) next to Lidl (DE)', 'Hofer (AT) neben Lidl (DE)'), 3, stores(withStore(migrated(), hofer))),
    ],
    country: [
      F(L('More › Settings › Shopping country', 'Mehr › Einstellungen › Einkaufsland'), 3, { screen: 'settings', sheet: { kind: 'country', pick: 'FR', household: true } }),
      F(L('“Carre”: France first now', '„Carre“: jetzt Frankreich zuerst'), 7, stores(migrated(), { country: 'FR', sheet: { kind: 'add' }, typed: 'Carre' })),
      F(L('Old stores keep Germany', 'Alte Läden behalten Deutschland'), 8, stores(withStore(migrated(), { id: 'carrefour', name: 'Carrefour', link: 'carrefour:FR' }))),
    ],
  },
  SS3: {
    migrate: [
      F(L('Find nearby, from the Stores screen', 'In der Nähe suchen, von der Seite Läden'), 2, stores(legacy(), { dialog: 'loc' })),
      F(L('Your stores marked on the map', 'Deine Läden auf der Karte markiert'), 3, { screen: 'nearby', places: placesHome(true), hiPlace: 0 }),
      F(L('Linked with branches; the market stays own', 'Mit Filialen verbunden; der Markt bleibt eigener'), 6, stores(linkAll(legacy(), { lidl: { link: 'lidl:DE', branch: 'Lindenallee 12' }, dm: { link: 'dm:DE', branch: 'Marktplatz 5' }, aldi: { link: 'aldi-sued:DE', branch: 'Bahnhofstraße 40' }, markt: { own: true } }))),
    ],
    new: [
      F(L('Add store: Find nearby', 'Laden hinzufügen: In der Nähe suchen'), 2, stores(migrated(), { sheet: { kind: 'add' } })),
      F(L('Location, once', 'Standort, einmal'), 3, stores(migrated(), { sheet: { kind: 'add' }, dialog: 'loc' })),
      F(L('Shops around you', 'Läden um dich herum'), 4, { screen: 'nearby', places: placesHome(), hiPlace: 1 }),
      F(L('REWE, Marktplatz 3', 'REWE, Marktplatz 3'), 5, { screen: 'store', storeId: 'rewe', stores: withStore(migrated(), { ...rewe, branch: 'Marktplatz 3' }) }),
    ],
    unlisted: [
      F(L('The farm shop is on the map', 'Der Hofladen ist auf der Karte'), 4, { screen: 'nearby', places: placesHome(), hiPlace: 4 }),
      F(L('Own store with an address, no app', 'Eigener Laden mit Adresse, ohne App'), 5, { screen: 'store', storeId: 'hof', stores: withStore(migrated(), { ...hof, branch: 'Feldweg 2' }) }),
    ],
    twocountries: [
      F(L('Near the border: Austria’s shops', 'An der Grenze: Läden in Österreich'), 4, { screen: 'nearby', places: placesAT, hiPlace: 0 }),
      F(L('The branch sets the country', 'Die Filiale bestimmt das Land'), 5, stores(withStore(migrated(), { ...hofer, branch: 'Grenzweg 3' }))),
    ],
    country: [
      F(L('In France: no setting, the branch says it', 'In Frankreich: keine Einstellung, die Filiale sagt es'), 4, { screen: 'nearby', places: placesFR, hiPlace: 0 }),
      F(L('Old stores keep Germany', 'Alte Läden behalten Deutschland'), 5, stores(withStore(migrated(), { id: 'carrefour', name: 'Carrefour', link: 'carrefour:FR', branch: 'Rue du Marché 9' }))),
    ],
  },
  SS4: {
    migrate: [
      F(L('Stores: “We recognised 3”', 'Läden: „3 erkannt“'), 1, stores(linkAll(legacy(), { dm: { link: 'dm:DE' }, lidl: { link: 'lidl:DE' } }), { banner: true })),
      F(L('Check: Aldi to choose', 'Prüfen: Aldi zum Auswählen'), 2, { screen: 'check', stores: linkAll(legacy(), { dm: { link: 'dm:DE' }, lidl: { link: 'lidl:DE' }, aldi: { amb: ['aldi-sued:DE', 'aldi-nord:DE'] } }) }),
      F(L('After Done', 'Nach Fertig'), 4, stores(migrated())),
    ],
    new: [
      F(L('Add store: Germany first', 'Laden hinzufügen: Deutschland zuerst'), 2, { screen: 'dir', hi: 'rewe:DE' }),
      F(L('REWE linked', 'REWE verbunden'), 3, stores(withStore(migrated(), rewe))),
    ],
    unlisted: [
      F(L('“Other / not listed” at the end', '„Anderer / nicht dabei“ am Ende'), 2, { screen: 'dir', scrollEnd: true }),
      F(L('A free name', 'Ein freier Name'), 3, { screen: 'dir', sheet: { kind: 'add' }, typed: 'Hofladen Sonnenwiese' }),
      F(L('Own store, no app button', 'Eigener Laden, ohne App-Knopf'), 4, stores(withStore(migrated(), hof))),
    ],
    twocountries: [
      F(L('Austria unfolded', 'Österreich aufgeklappt'), 3, { screen: 'dir', expand: 'AT', hi: 'aldi-sued:AT', scrollTo: 'AT' }),
      F(L('Hofer (AT) next to Lidl (DE)', 'Hofer (AT) neben Lidl (DE)'), 4, stores(withStore(migrated(), hofer))),
    ],
    country: [
      F(L('More › Settings › Shopping country', 'Mehr › Einstellungen › Einkaufsland'), 3, { screen: 'settings', sheet: { kind: 'country', pick: 'FR', household: true } }),
      F(L('France first now', 'Jetzt Frankreich zuerst'), 7, { screen: 'dir', country: 'FR', hi: 'carrefour:FR' }),
      F(L('Old stores keep Germany', 'Alte Läden behalten Deutschland'), 8, stores(withStore(migrated(), { id: 'carrefour', name: 'Carrefour', link: 'carrefour:FR' }))),
    ],
  },
  SS5: {
    migrate: [
      F(L('One offer, on a store with an app', 'Ein Angebot, bei einem Laden mit App'), 0, list(legacy(), { card: { kind: 'suggest', title: L('Looks like Lidl (Germany). Show “Open Lidl Plus” on the list?', 'Sieht nach Lidl (Deutschland) aus. „Lidl Plus öffnen“ auf der Liste zeigen?'), yes: L('Show button', 'Knopf zeigen'), no: L('No thanks', 'Nein, danke') } })),
      F(L('“Aldi”: which one, or no', '„Aldi“: welches, oder nein'), 2, list(linkAll(legacy(), { lidl: { link: 'lidl:DE' }, dm: { link: 'dm:DE' } }), { card: { kind: 'which', keys: ['aldi-sued:DE', 'aldi-nord:DE'], title: L('Looks like Aldi. Which one has your app?', 'Sieht nach Aldi aus. Welches hat deine App?'), no: L('No thanks', 'Nein, danke') } })),
      F(L('Buttons where you said yes', 'Knöpfe, wo du ja gesagt hast'), 3, list(linkAll(legacy(), { lidl: { link: 'lidl:DE' }, dm: { link: 'dm:DE' }, aldi: { link: 'aldi-sued:DE' } }))),
    ],
    new: [
      F(L('Add store as today', 'Laden hinzufügen wie heute'), 2, stores(migrated(), { sheet: { kind: 'add' }, typed: 'REWE' })),
      F(L('Back on the list: the offer', 'Zurück auf der Liste: das Angebot'), 4, list(withStore(migrated(), { ...rewe, link: null, items: [listStores[4].items[0]] }), { card: { kind: 'suggest', title: L('Looks like REWE (Germany). Show “Open REWE” on the list?', 'Sieht nach REWE (Deutschland) aus. „REWE öffnen“ auf der Liste zeigen?'), yes: L('Show button', 'Knopf zeigen'), no: L('No thanks', 'Nein, danke') } })),
    ],
    unlisted: [
      F(L('Add store as today', 'Laden hinzufügen wie heute'), 2, stores(migrated(), { sheet: { kind: 'add' }, typed: 'Hofladen Sonnenwiese' })),
      F(L('Nothing asked, ever', 'Nie eine Frage'), 3, stores(withStore(migrated(), hof))),
    ],
    twocountries: [
      F(L('“Hofer” in a German household', '„Hofer“ in einem deutschen Haushalt'), 4, list(withStore(migrated(), { ...hofer, link: null, items: [listStores[2].items[0]] }), { card: { kind: 'suggest', title: L('Looks like Hofer (Austria). Show “Open HOFER” on the list?', 'Sieht nach Hofer (Österreich) aus. „HOFER öffnen“ auf der Liste zeigen?'), yes: L('Show button', 'Knopf zeigen'), no: L('No thanks', 'Nein, danke') } })),
      F(L('Hofer (AT) next to Lidl (DE)', 'Hofer (AT) neben Lidl (DE)'), 5, stores(withStore(migrated(), hofer))),
    ],
    country: [
      F(L('Phone region France: matches follow', 'Handy-Region Frankreich: Treffer folgen'), 4, list(withStore(migrated(), { id: 'carrefour', name: 'Carrefour', link: null, items: [listStores[4].items[1]] }), { country: 'FR', card: { kind: 'suggest', title: L('Looks like Carrefour (France). Show “Open Carrefour” on the list?', 'Sieht nach Carrefour (Frankreich) aus. „Carrefour öffnen“ auf der Liste zeigen?'), yes: L('Show button', 'Knopf zeigen'), no: L('No thanks', 'Nein, danke') } })),
      F(L('Old stores keep Germany', 'Alte Läden behalten Deutschland'), 5, stores(withStore(migrated(), { id: 'carrefour', name: 'Carrefour', link: 'carrefour:FR' }))),
    ],
  },
};

export const walk = (opt, scenario) => walks[opt.id][scenario].map((f) => {
  const st = { ...f.state };
  if (st.scrollTo) delete st.scrollTo;
  return { cap: f.cap, taps: f.taps, state: st, scrollTo: f.state.scrollTo ? `dir-${f.state.scrollTo}` : f.state.scrollEnd ? 'end' : null };
});

// The facts under each option for the chosen scenario.
const facts = {
  SS1: { typing: L('yes (search)', 'ja (Suche)'), location: L('no', 'nein'), country: L('per store, from the phone’s region, “Change”', 'je Laden, aus der Handy-Region, „Ändern“') },
  SS2: { typing: L('yes (as today)', 'ja (wie heute)'), location: L('no', 'nein'), country: L('household setting; matches in any country', 'Einstellung im Haushalt; Treffer in jedem Land') },
  SS3: { typing: L('no (or a town)', 'nein (oder ein Ort)'), location: L('yes, once per search, sent to a map service', 'ja, einmal je Suche, an einen Kartendienst'), country: L('from the branch', 'aus der Filiale') },
  SS4: { typing: L('no (only “Other”)', 'nein (nur „Anderer“)'), location: L('no', 'nein'), country: L('household setting', 'Einstellung im Haushalt') },
  SS5: { typing: L('yes (as today)', 'ja (wie heute)'), location: L('no', 'nein'), country: L('phone region, then any country', 'Handy-Region, dann jedes Land') },
};
export const walkNote = (opt, scenario, lang) => {
  const fs = walks[opt.id][scenario];
  const f = facts[opt.id];
  const w = lang === 'de' ? ['Tipps bis zum Ende', 'Tippen', 'Standort', 'Land'] : ['Taps to the end', 'Typing', 'Location', 'Country'];
  return `${w[0]}: <b data-total="${opt.id}">${fs[fs.length - 1].taps}</b> · ${w[1]}: ${f.typing[lang]} · ${w[2]}: ${f.location[lang]} · ${w[3]}: ${f.country[lang]}`;
};

// The registry proposal on the page: the verified table per country, from registry/retailers.json.
export const registrySection = async (lang) => {
  const r = await (await fetch('../registry/retailers.json')).json();
  const de = lang === 'de';
  const countries = [...new Set(r.entries.map((e) => e.country))];
  const rows = countries.map((cc) => {
    const es = r.entries.filter((e) => e.country === cc);
    return `<tr><td><b>${cc}</b></td><td>${es.map((e) => `<span class="regchip ${e.status}" title="${esc(e.note ?? '')}">${esc(e.name)}${e.app?.universalLink ? ' 🔗' : ''}${e.status === 'no-app' ? ' –' : ''}</span>`).join(' ')}</td><td>${es.filter((e) => e.status === 'verified').length}</td></tr>`;
  }).join('');
  return `<section class="rec" id="registry" data-registry="${r.entries.length}"><h2>${de ? 'Das Verzeichnis: verifizierte Händler-Apps je Land' : 'The registry: verified retailer apps per country'}</h2>
    <p>${de ? `Stand ${r.updated}. Jede ID ist gegen Apple (iTunes-Lookup im Land) und Google Play geprüft, Links gegen die AASA-Datei bei Apple und Googles Digital Asset Links. 🔗 = ein https-Link, der die App öffnet (sonst öffnet iOS die Seite im App Store). – = keine App gefunden. Keine ID ist geraten.` : `As of ${r.updated}. Every id is checked against Apple (iTunes lookup in that country) and Google Play, links against Apple’s AASA copy and Google’s Digital Asset Links. 🔗 = an https link that opens the app (otherwise iOS opens the App Store page). – = no app found. No id is guessed.`}</p>
    <div class="table-wrap"><table class="regtable"><tr><th>${de ? 'Land' : 'Country'}</th><th>${de ? 'Ketten' : 'Chains'}</th><th>${de ? 'Verifiziert' : 'Verified'}</th></tr>${rows}</table></div></section>`;
};

export { badge };
