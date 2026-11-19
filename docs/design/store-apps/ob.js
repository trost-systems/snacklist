// Round OB: how onboarding picks and links stores. Today (after job 313) and OB1 to OB5 as hook records for phone.js,
// each walked through six scenarios. The first frame of a walk is a live phone; drives[] below taps it to the end of the
// store step, and verify.mjs checks that those taps match the counts in `metrics`.
import { ic, esc, badge, chains } from './phone.js';

const L = (en, de) => ({ en, de });
const at = (act, arg) => `data-act="${act}"${arg === undefined ? '' : ` data-arg="${esc(arg)}"`}`;

// Strings: the ARB's where the app has one (main, or job 313's branch for the chain ones), new copy marked "new".
const W = {
  en: {
    progress: (i, n) => `Step ${i} of ${n}`, storesTitle: 'Where do you shop?',
    storesHint: 'Pick the stores you shop at. Your list shows them in this order.',
    addOwn: 'Add your own store', next: 'Continue', skip: 'Skip', hardware: 'Hardware store',
    skipHint: 'Start without stores. You can add them later under List → Edit.',
    needTitle: 'What do you need right now?', storeName: 'Store name', exit: 'Leave setup', back: 'Back',
    isThis: (c) => `Is this ${c}?`, existing: (st, c) => `Is your “${st}” the chain ${c}?`, appLine: (a) => `Then you can open ${a} right from the list.`,
    yes: 'Yes', keep: 'No, keep it as is', no: 'No', withCountry: (c, cc) => `${c} (${cc})`, openApp: (a) => `Open ${a}`,
    countries: { DE: 'Germany', AT: 'Austria' }, appTitle: 'App', choose: 'Which app should open?', open: 'Open',
    joinTitle: 'Join a household', joinBtn: 'Join household', joined: (h) => `You're now in “${h}”.`, joinBody: 'You were invited to',
    // new
    other: 'Other store', addTyped: (q) => `Add “${q}”`, cardTitle: 'Where do you shop?', cardDone: 'Done', cardLater: 'Not now',
    searchStores: 'Search stores', onList: 'On your list',
  },
  de: {
    progress: (i, n) => `Schritt ${i} von ${n}`, storesTitle: 'Wo kauft ihr ein?',
    storesHint: 'Wähl die Läden, in denen ihr einkauft. In dieser Reihenfolge stehen sie in der Liste.',
    addOwn: 'Eigenen Laden hinzufügen', next: 'Weiter', skip: 'Überspringen', hardware: 'Baumarkt',
    skipHint: 'Ohne Läden starten. Du kannst sie später unter Liste → Anpassen anlegen.',
    needTitle: 'Was fehlt gerade?', storeName: 'Name des Ladens', exit: 'Einrichtung verlassen', back: 'Zurück',
    isThis: (c) => `Ist das ${c}?`, existing: (st, c) => `Ist dein „${st}“ die Kette ${c}?`, appLine: (a) => `Dann kannst du ${a} direkt aus der Liste öffnen.`,
    yes: 'Ja', keep: 'Nein, so lassen', no: 'Nein', withCountry: (c, cc) => `${c} (${cc})`, openApp: (a) => `${a} öffnen`,
    countries: { DE: 'Deutschland', AT: 'Österreich' }, appTitle: 'App', choose: 'Welche App soll sich öffnen?', open: 'Öffnen',
    joinTitle: 'Einem Haushalt beitreten', joinBtn: 'Haushalt beitreten', joined: (h) => `Du bist jetzt in „${h}“.`, joinBody: 'Du wurdest eingeladen zu',
    other: 'Anderer Laden', addTyped: (q) => `„${q}“ hinzufügen`, cardTitle: 'Wo kauft ihr ein?', cardDone: 'Fertig', cardLater: 'Später',
    searchStores: 'Läden suchen', onList: 'Auf eurer Liste',
  },
};
const w = (s) => W[s.lang];
const cname = (s, key) => w(s).withCountry(chains[key].name, w(s).countries[chains[key].country]);

// Today's chips (app/lib/household/popular_stores.dart): one German list for every phone, plain names.
const popular = ['EDEKA', 'REWE', 'Lidl', 'Aldi Süd', 'Aldi Nord', 'Kaufland', 'Netto', 'Penny', 'dm', 'Rossmann'];
// The region's chains from the registry, in the order a picker shows them (most stores first).
export const regionChains = {
  DE: ['edeka:DE', 'rewe:DE', 'lidl:DE', 'aldi-sued:DE', 'aldi-nord:DE', 'kaufland:DE', 'netto-md:DE', 'penny:DE', 'dm:DE', 'rossmann:DE'],
  AT: ['billa:AT', 'spar-at:AT', 'aldi-sued:AT', 'lidl:AT', 'penny:AT', 'mpreis:AT', 'dm:AT'],
};
// A chain with two apps (registry note on billa:AT): the default first, as Peter's pick 4 keeps it (the registry's app).
export const appsOf = { 'billa:AT': ['BILLA', 'jö Bonus Club'] };
const appName = (p) => p.app ?? (p.key ? chains[p.key].app : null);

// Matches for a typed name: the phone's region first, then every country (job 313's match_retailer rule).
const matches = (q, region) => {
  const n = q.trim().toLowerCase();
  if (n.length < 2) return [];
  const hit = (k) => chains[k].aliases.some((a) => a.startsWith(n) || n.startsWith(`${a} `) || n === a) || chains[k].name.toLowerCase().startsWith(n);
  const home = regionChains[region].filter(hit);
  const rest = Object.keys(chains).filter((k) => !home.includes(k) && chains[k].country !== region && hit(k) && !home.some((h) => chains[h].chain === chains[k].chain));
  return [...home, ...rest].slice(0, 3);
};
const exact = (q, region) => regionChains[region].find((k) => chains[k].aliases.includes(q.trim().toLowerCase()) || chains[k].name.toLowerCase() === q.trim().toLowerCase());

// --- Pieces -----------------------------------------------------------------------------------------------------------

const has = (s, p) => s.picked.some((x) => (p.key ? x.key === p.key : x.name === p.name));
const toggle = (s, p) => ({ ...s, picked: has(s, p) ? s.picked.filter((x) => (p.key ? x.key !== p.key : x.name !== p.name)) : [...s.picked, p] });
const parse = (arg) => (arg.includes(':') ? { key: arg, name: chains[arg].name } : { key: null, name: arg });
const argOf = (p) => p.key ?? p.name;

const chip = (s, p, extra = '') => `<button class="chip ${has(s, p) ? 'on' : ''}" ${at('obChip', argOf(p))} data-pick="${esc(argOf(p))}">${esc(p.name)}${extra}</button>`;
const appbar = (s, step, of, back = true) => `<div class="appbar top obbar">${back ? `<button class="iconbtn" ${at('noop')} aria-label="${esc(w(s).back)}">${ic('arrow_back')}</button>` : ''}<h1>${esc(w(s).progress(step, of))}</h1><button class="iconbtn" ${at('noop')} aria-label="${esc(w(s).exit)}">${ic('close')}</button></div>`;
const progress = (step, of) => `<div class="progress"><i style="width:${(100 * step) / of}%"></i></div>`;
const nextSkip = (s) => `<button class="tact honey" ${at('obNext')} data-next><span>${esc(w(s).next)}</span></button><button class="tact" ${at('obSkip')} data-skip><span>${esc(w(s).skip)}</span></button>`;
const nameField = (s, confirm = 'obAddTyped') => `<div class="hexfield"><span><input data-input="typed" value="${esc(s.typed)}" placeholder="${esc(w(s).storeName)}" aria-label="${esc(w(s).storeName)}" autocomplete="off"><button class="iconbtn sm" ${at(confirm)} data-confirm aria-label="${esc(w(s).addOwn)}">${ic('check')}</button></span></div>`;
const suggestRows = (s) => {
  const keys = matches(s.typed, s.region).filter((k) => !s.picked.some((p) => p.key === k));
  const q = s.typed.trim();
  const own = q && !exact(q, s.region) && !keys.some((k) => chains[k].name.toLowerCase() === q.toLowerCase());
  if (!keys.length && !own) return '';
  return `<div class="picklist" data-suggest>${keys.map((k) => `<button class="pickrow" ${at('obPick', k)} data-chain="${k}"><span class="grow"><b>${esc(chains[k].name)}</b><span class="small">${esc(w(s).countries[chains[k].country])}</span></span></button>`).join('')}${own ? `<button class="pickrow keep" ${at('obAddTyped')} data-keep>${ic('add')}<span class="grow"><b>${esc(w(s).addTyped(q))}</b></span></button>` : ''}</div>`;
};

// The step page as OnboardingStepPage draws it: app bar „Schritt 4 von 7“, the bar, the question, the option's body.
const stepScreen = (s) => `${appbar(s, 4, 7)}
  <div class="body center" data-scroll><div class="col">${progress(4, 7)}<h2 class="heading">${esc(w(s).storesTitle)}</h2>${s.opt.stepBody(s)}</div></div>`;

const needScreen = (s) => `${appbar(s, s.opt.noStep ? 4 : 5, s.opt.noStep ? 6 : 7)}
  <div class="body center" data-scroll><div class="col">${progress(s.opt.noStep ? 4 : 5, s.opt.noStep ? 6 : 7)}<h2 class="heading" data-need>${esc(w(s).needTitle)}</h2>
  <div class="chips">${['Milk|Milch', 'Bread|Brot', 'Bananas|Bananen', 'Toothpaste|Zahnpasta'].map((x) => `<span class="chip">${esc(x.split('|')[s.lang === 'de' ? 1 : 0])}</span>`).join('')}</div>
  <span class="tact honey"><span>${esc(w(s).next)}</span></span></div></div>`;

const joinScreen = (s) => `<div class="appbar plain"><button class="iconbtn" ${at('noop')} aria-label="${esc(w(s).back)}">${ic('arrow_back')}</button><h1>${esc(w(s).joinTitle)}</h1></div>
  <div class="body center" data-scroll><div class="col"><span class="bigicon">${ic('shopping_bag_outlined')}</span><p class="lead center-text">${esc(w(s).joinBody)}</p><h2 class="heading center-text">Familie Brandt</h2>
  <button class="tact honey" ${at('noop')} data-join><span>${esc(w(s).joinBtn)}</span></button></div></div>`;

// --- Sheets and cards -------------------------------------------------------------------------------------------------

const sheets = {
  search: (s) => `<div class="shead"><h2>${esc(w(s).other)}</h2></div><div class="sbody">${nameField(s)}${suggestRows(s)}</div>`,
  ask: (s) => `<div class="shead"><h2 data-ask>${esc(w(s).isThis(cname(s, s.sheet.key)))}</h2></div><div class="sbody"><p class="lead">${esc(w(s).appLine(chains[s.sheet.key].app))}</p>
    <button class="tact honey" ${at('obAskYes')}><span>${esc(w(s).yes)}</span></button><button class="textbtn center" ${at('obAskNo')}>${esc(w(s).keep)}</button></div>`,
};

// Job 313's SS5 card: one unlinked store with an app at a time („1 / 3“), on the list's top.
const askCard = (s) => {
  const q = s.asks?.[0];
  if (!q) return '';
  return `<div class="card asks" data-card="ask"><span class="small">${s.askOf - s.asks.length + 1} / ${s.askOf}</span><b>${esc(w(s).existing(q.name, cname(s, q.key)))}</b>
    <div class="cardbtns"><button class="tact honey" ${at('askYes')}><span>${esc(w(s).yes)}</span></button><button class="textbtn" ${at('askNo')}>${esc(w(s).no)}</button></div></div>`;
};

// OB4's card: the region's chains as chips on the first list, until it is answered.
const storesCard = (s) => (s.card
  ? `<div class="card asks" data-card="stores"><b>${esc(w(s).cardTitle)}</b><div class="chips">${regionChains[s.region].map((k) => chip(s, { key: k, name: chains[k].name })).join('')}<button class="chip" ${at('obOther')} data-other>${ic('add', 'sm')}${esc(w(s).other)}</button></div>
    <div class="cardbtns"><button class="tact honey" ${at('cardDone')} data-done><span>${esc(w(s).cardDone)}</span></button><button class="textbtn" ${at('cardLater')}>${esc(w(s).cardLater)}</button></div></div>`
  : '');

// The header key (OS1, Peter's pick: trailing, after the chevron) on stores linked to a chain with an app.
const headerTrail = (s, st) => {
  const app = st.app ?? (st.link ? chains[st.link]?.app : null);
  return app ? `<button class="appbtn" ${at('noop')} aria-label="${esc(w(s).openApp(app))}" data-open="${st.id}">${ic('open_in_new')}</button>` : '';
};

// The store's own screen: job 313's app card, with the choice for a chain with two apps.
const storeExtra = (s, st) => {
  if (!st.link) return '';
  const apps = appsOf[st.link] ?? [chains[st.link].app];
  const cur = st.app ?? apps[0];
  return `<div class="card chaincard" data-chaincard="${st.link}"><div class="crow"><span class="clabel">${esc(w(s).appTitle)}</span><b class="grow">${esc(cur)}</b><span class="tact inline-sm"><span>${esc(w(s).open)}</span></span></div>
    ${apps.length > 1 ? `<p class="small">${esc(w(s).choose)}</p><div class="chips">${apps.map((a) => `<button class="chip ${a === cur ? 'on' : ''}" ${at('noop')} data-app="${esc(a)}">${esc(a)}</button>`).join('')}</div>` : ''}</div>`;
};

// --- What each option's store step shows ------------------------------------------------------------------------------

const ownPart = (s) => (s.naming ? nameField(s, 'obAddOwn') : `<button class="textbtn" ${at('obOwn')} data-own>${ic('add', 'sm')}${esc(w(s).addOwn)}</button>`);
const owns = (s, offered) => s.picked.filter((p) => !offered.some((o) => argOf(o) === argOf(p)));
const regionOffer = (s) => [...regionChains[s.region].map((k) => ({ key: k, name: chains[k].name })), { key: null, name: w(s).hardware }];

const chipsBody = (offer, { hint = true, preview = false } = {}) => (s) => {
  const list = offer(s);
  return `${hint ? `<p>${esc(w(s).storesHint)}</p>` : ''}
    <div class="chips" data-chips>${[...list, ...owns(s, list)].map((p) => chip(s, p)).join('')}${s.naming ? '' : ownPart(s)}</div>
    ${s.naming ? ownPart(s) : ''}${s.naming && s.opt.linkOwn ? suggestRows(s) : ''}
    ${preview ? previewRows(s) : ''}
    ${nextSkip(s)}${hint ? `<p class="small center-text">${esc(w(s).skipHint)}</p>` : ''}`;
};

// OB5: the picked stores as their list headers will look, with the key; a chain with two apps shows both.
const previewRows = (s) => {
  const rows = s.picked.filter((p) => p.key && chains[p.key].app);
  if (!rows.length) return '';
  return `<div class="preview" data-preview><span class="small">${esc(w(s).onList)}</span>${rows.map((p) => {
    const apps = appsOf[p.key];
    return `<div class="prevrow"><div class="shead-row">${badge(p.name)}<i class="rule"></i><span class="appkey">${ic('open_in_new', 'sm')}${esc(appName(p))}</span></div>
      ${apps ? `<div class="chips">${apps.map((a) => `<button class="chip ${a === appName(p) ? 'on' : ''}" ${at('obApp', `${p.key}|${a}`)} data-app="${esc(a)}">${esc(a)}</button>`).join('')}</div>` : ''}</div>`;
  }).join('')}</div>`;
};

const typeBody = (s) => `<div class="chips" data-chips>${s.picked.map((p) => `<button class="chip on" ${at('obChip', argOf(p))} data-pick="${esc(argOf(p))}">${esc(p.name)}${ic('close', 'sm')}</button>`).join('')}</div>
  ${nameField(s)}${suggestRows(s)}${nextSkip(s)}`;

const topBody = (s) => {
  const top = regionChains[s.region].slice(0, 5).map((k) => ({ key: k, name: chains[k].name }));
  const row = (p) => `<button class="check ${has(s, p) ? 'on' : ''}" ${at('obChip', argOf(p))} data-pick="${esc(argOf(p))}"><span class="hexbox">${has(s, p) ? ic('check') : ''}</span><span class="grow">${esc(p.name)}</span></button>`;
  return `<div class="checks" data-chips>${[...top, ...owns(s, top)].map(row).join('')}
    <button class="check" ${at('obOther')} data-other><span class="hexbox plus">${ic('add')}</span><span class="grow">${esc(w(s).other)}</span></button></div>${nextSkip(s)}`;
};

// --- Taps ---------------------------------------------------------------------------------------------------------------

const toList = (s) => ({ ...s, screen: 'need', sheet: null });
const acts = {
  obChip: (s, arg) => toggle(s, parse(arg)),
  obOwn: (s) => ({ ...s, naming: true, typed: '' }),
  obAddOwn: (s) => {
    const q = s.typed.trim();
    if (!q) return s;
    const k = exact(q, s.region);
    const p = s.opt.linkOwn && k ? { key: k, name: chains[k].name } : { key: null, name: q };
    return { ...toggle(s, p), naming: false, typed: '' };
  },
  obPick: (s, k) => ({ ...s, picked: [...s.picked, { key: k, name: chains[k].name }], typed: '', sheet: null, naming: false }),
  obAddTyped: (s) => {
    const q = s.typed.trim();
    if (!q) return s;
    const k = exact(q, s.region);
    if (k) return { ...s, sheet: { kind: 'ask', key: k, name: q } };
    return { ...s, picked: [...s.picked, { key: null, name: q }], typed: '', sheet: null, naming: false };
  },
  obAskYes: (s) => ({ ...s, picked: [...s.picked, { key: s.sheet.key, name: s.sheet.name }], typed: '', sheet: null }),
  obAskNo: (s) => ({ ...s, picked: [...s.picked, { key: null, name: s.sheet.name }], typed: '', sheet: null }),
  obOther: (s) => ({ ...s, sheet: { kind: 'search' }, typed: '' }),
  obApp: (s, arg) => { const [k, a] = arg.split('|'); return { ...s, picked: s.picked.map((p) => (p.key === k ? { ...p, app: a } : p)) }; },
  obNext: toList,
  obSkip: (s) => toList({ ...s, picked: [] }),
  cardDone: (s) => ({ ...s, card: false, stores: listOf(s.picked, s.lang) }),
  cardLater: (s) => ({ ...s, card: false }),
  askYes: (s) => ({ ...s, asks: s.asks.slice(1), stores: s.stores.map((x) => (x.id === s.asks[0].id ? { ...x, link: s.asks[0].key } : x)) }),
  askNo: (s) => ({ ...s, asks: s.asks.slice(1) }),
};

// --- The options --------------------------------------------------------------------------------------------------------

const common = {
  acts, headerTrail, storeExtra, listTop: (s) => `${askCard(s)}${storesCard(s)}`,
  screens: { ob: stepScreen, need: needScreen, join: joinScreen },
  sheet: (s) => sheets[s.sheet.kind](s),
};
const opt = (o) => ({ ...common, ...o });

export const options = [
  opt({
    id: 'today', title: L('Today (main, plus job 313’s card)', 'Heute (main, plus Karte aus Job 313)'),
    desc: L(
      'Step 4 of 7: eleven German chips for every phone, “Add your own store”, Continue and Skip. The stores are plain names. Once job 313 lands, the first list asks about each one that matches a chain with an app (“Is your “Lidl” the chain Lidl (Germany)?”), one card at a time. That card is what Peter spotted: onboarding asks “Where do you shop?” and the list then asks again. The disclaimer under the chips is gone (N-292, job 313).',
      'Schritt 4 von 7: elf deutsche Chips für jedes Handy, „Eigenen Laden hinzufügen“, Weiter und Überspringen. Die Läden sind reine Namen. Sobald Job 313 landet, fragt die erste Liste jeden, der zu einer Kette mit App passt („Ist dein „Lidl“ die Kette Lidl (Deutschland)?“), eine Karte nach der anderen. Diese Karte hat Peter bemerkt: der Einstieg fragt „Wo kauft ihr ein?“, und die Liste fragt noch einmal. Der Hinweis unter den Chips ist weg (N-292, Job 313).'),
    stepBody: chipsBody((s) => [...popular.map((n) => ({ key: null, name: n })), { key: null, name: w(s).hardware }]),
  }),
  opt({
    id: 'OB1', linkOwn: true, title: L('OB1 Today’s chips, from the phone’s region, linked as you tap', 'OB1 Die Chips von heute, aus der Region des Handys, beim Tippen verbunden'),
    desc: L(
      'The same screen and the same words as today. The chips come from the registry for the phone’s region, so a phone set to Austria shows BILLA, SPAR, Hofer, Lidl, PENNY, MPREIS and dm. A tapped chip is a linked store. “Add your own store” offers matching chains as you type, in any country. A name that matches nothing stays your own store. A chain with two apps gets its default app, and the store’s screen changes it later. Nothing is asked afterwards.',
      'Derselbe Bildschirm mit denselben Worten wie heute. Die Chips kommen aus dem Verzeichnis für die Region des Handys, ein Handy auf Österreich zeigt also BILLA, SPAR, Hofer, Lidl, PENNY, MPREIS und dm. Ein angetippter Chip ist ein verbundener Laden. „Eigenen Laden hinzufügen“ bietet beim Tippen passende Ketten an, in jedem Land. Ein Name ohne Treffer bleibt ein eigener Laden. Eine Kette mit zwei Apps bekommt ihre Standard-App, die Seite des Ladens ändert sie später. Danach wird nichts gefragt.'),
    stepBody: chipsBody(regionOffer),
  }),
  opt({
    id: 'OB2', title: L('OB2 Type-ahead in the step (job 313’s SS2 field)', 'OB2 Vorschläge beim Tippen im Schritt (das SS2-Feld aus Job 313)'),
    desc: L(
      'No chips. The step is the store-name field from job 313. Matching chains appear under it as you type, the phone’s region first and then any country. Each pick lands above the field as a chip with an ×. Saving a plain name that matches asks once (“Is this Lidl (Germany)?”), and a name that matches nothing is added as typed. No hint lines.',
      'Keine Chips. Der Schritt ist das Ladennamen-Feld aus Job 313. Beim Tippen erscheinen passende Ketten darunter, zuerst die Region des Handys, dann jedes Land. Jede Wahl landet als Chip mit × über dem Feld. Wer einen passenden Namen einfach speichert, wird einmal gefragt („Ist das Lidl (Deutschland)?“), ein Name ohne Treffer kommt so dazu, wie er getippt ist. Keine Hinweiszeilen.'),
    stepBody: typeBody,
  }),
  opt({
    id: 'OB3', title: L('OB3 The region’s top five, plus “Other store”', 'OB3 Die fünf größten der Region, plus „Anderer Laden“'),
    desc: L(
      'Five big tick rows with the region’s largest chains, then “Other store”, which opens job 313’s type-ahead in a sheet. There is less to scan than eleven chips, and the rows stay one per line at the largest text. A store outside the top five, such as dm in Germany, costs two taps and a typed name. No hint lines.',
      'Fünf große Haken-Zeilen mit den größten Ketten der Region, dann „Anderer Laden“, das die Vorschläge aus Job 313 in einem Blatt öffnet. Es gibt weniger zu überfliegen als elf Chips, und bei größter Schrift bleibt jede Zeile eine Zeile. Ein Laden außerhalb der fünf, etwa dm in Deutschland, kostet zwei Tipps und einen getippten Namen. Keine Hinweiszeilen.'),
    stepBody: topBody,
  }),
  opt({
    id: 'OB4', noStep: true, title: L('OB4 No store step: one card on the first list', 'OB4 Kein Laden-Schritt: eine Karte auf der ersten Liste'),
    desc: L(
      'Onboarding loses the step, so it has 6 steps instead of 7. The first list starts with one card: “Where do you shop?”, the region’s chains as chips (linked), “Other store” (job 313’s sheet), Done and “Not now”. The card belongs to the household, so the first member to answer it answers for everyone. A joiner sees it only if nobody has answered it yet.',
      'Der Einstieg verliert den Schritt und hat 6 statt 7 Schritte. Die erste Liste beginnt mit einer Karte: „Wo kauft ihr ein?“, die Ketten der Region als Chips (verbunden), „Anderer Laden“ (das Blatt aus Job 313), Fertig und „Später“. Die Karte gehört dem Haushalt, wer sie zuerst beantwortet, beantwortet sie für alle. Wer beitritt, sieht sie nur, wenn noch niemand geantwortet hat.'),
    stepBody: () => '',
  }),
  opt({
    id: 'OB5', linkOwn: true, title: L('OB5 OB1 plus a preview with the “Open app” key', 'OB5 OB1 plus eine Vorschau mit der Taste „App öffnen“'),
    desc: L(
      'OB1’s chips, and under them each picked chain with an app as its list header will look, with the key and the app’s name. A chain with two apps shows both as chips, so the app is chosen right here (BILLA or jö Bonus Club). It shows what linking gives before the list exists. It costs height: at large text, Continue moves further down.',
      'Die Chips aus OB1, und darunter jede gewählte Kette mit App so, wie ihr Kopf auf der Liste aussehen wird, mit Taste und App-Namen. Eine Kette mit zwei Apps zeigt beide als Chips, die App wird also gleich hier gewählt (BILLA oder jö Bonus Club). Das zeigt, was die Verbindung bringt, bevor es die Liste gibt. Es kostet Höhe: bei großer Schrift rutscht Weiter weiter nach unten.'),
    stepBody: chipsBody(regionOffer, { preview: true }),
  }),
];

// Measured only (OB-Q1): OB1 without the two hint lines, for Peter's “as little UI text as possible”.
export const lean = opt({ ...options[1], id: 'OB1-lean', stepBody: chipsBody(regionOffer, { hint: false }) });

export const scenarios = [
  { id: 'de', title: L('New user in DE', 'Neu in DE') },
  { id: 'at', title: L('New user in AT', 'Neu in AT') },
  { id: 'unlisted', title: L('Not in the registry', 'Nicht im Verzeichnis') },
  { id: 'skip', title: L('Nothing, or skip', 'Nichts, oder überspringen') },
  { id: 'twoapps', title: L('A chain with two apps', 'Eine Kette mit zwei Apps') },
  { id: 'joiner', title: L('Joining a household', 'Einem Haushalt beitreten') },
];

// --- The measured paths ---------------------------------------------------------------------------------------------------
// Per option and scenario: taps on the store step (Continue or Skip included), names typed, store screens in onboarding,
// and taps afterwards on the list until every store with an app is linked (or, for two apps, opens jö Bonus Club).
// drives[] taps the live first frame along the same path; verify.mjs checks the step taps and the stores it ends with.

const JOE = 4; // List › Edit, the store, the app row, jö Bonus Club (job 313's store screen).
export const metrics = {
  today: { de: [4, 0, 1, 3], at: [6, 2, 1, 3], unlisted: [4, 1, 1, 1], skip: [1, 0, 1, 0], twoapps: [3, 1, 1, 1 + JOE], joiner: [0, 0, 0, 0] },
  OB1: { de: [4, 0, 1, 0], at: [4, 0, 1, 0], unlisted: [4, 1, 1, 0], skip: [1, 0, 1, 0], twoapps: [2, 0, 1, JOE], joiner: [0, 0, 0, 0] },
  OB2: { de: [4, 3, 1, 0], at: [4, 3, 1, 0], unlisted: [3, 2, 1, 0], skip: [1, 0, 1, 0], twoapps: [2, 1, 1, JOE], joiner: [0, 0, 0, 0] },
  OB3: { de: [5, 1, 1, 0], at: [4, 0, 1, 0], unlisted: [4, 1, 1, 0], skip: [1, 0, 1, 0], twoapps: [2, 0, 1, JOE], joiner: [0, 0, 0, 0] },
  OB4: { de: [0, 0, 0, 4], at: [0, 0, 0, 4], unlisted: [0, 1, 0, 4], skip: [0, 0, 0, 1], twoapps: [0, 0, 0, 2 + JOE], joiner: [0, 0, 0, 0] },
  OB5: { de: [4, 0, 1, 0], at: [4, 0, 1, 0], unlisted: [4, 1, 1, 0], skip: [1, 0, 1, 0], twoapps: [3, 0, 1, 0], joiner: [0, 0, 0, 0] },
};
export const totalOf = (id, sc) => metrics[id][sc][0] + metrics[id][sc][3];

const c = (sel) => ({ click: sel });
const f = (value) => ({ fill: value });
const pick = (k) => c(`[data-pick="${k}"]`);
const sug = (k) => c(`[data-chain="${k}"]`);
const next = c('[data-next]');
const ownTyped = (name) => [c('[data-own]'), f(name), c('[data-confirm]')];
export const drives = {
  today: {
    de: [pick('Lidl'), pick('dm'), pick('REWE'), next],
    at: [pick('Lidl'), ...ownTyped('Hofer'), ...ownTyped('SPAR'), next],
    unlisted: [pick('Lidl'), ...ownTyped('Hofladen Sonnenwiese'), next],
    skip: [c('[data-skip]')],
    twoapps: [...ownTyped('BILLA'), next],
  },
  OB1: {
    de: [pick('lidl:DE'), pick('dm:DE'), pick('rewe:DE'), next],
    at: [pick('aldi-sued:AT'), pick('spar-at:AT'), pick('lidl:AT'), next],
    unlisted: [pick('lidl:DE'), ...ownTyped('Hofladen Sonnenwiese'), next],
    skip: [c('[data-skip]')],
    twoapps: [pick('billa:AT'), next],
  },
  OB2: {
    de: [f('Li'), sug('lidl:DE'), f('dm'), sug('dm:DE'), f('Re'), sug('rewe:DE'), next],
    at: [f('Hof'), sug('aldi-sued:AT'), f('Sp'), sug('spar-at:AT'), f('Li'), sug('lidl:AT'), next],
    unlisted: [f('Li'), sug('lidl:DE'), f('Hofladen Sonnenwiese'), c('[data-keep]'), next],
    skip: [c('[data-skip]')],
    twoapps: [f('Bi'), sug('billa:AT'), next],
  },
  OB3: {
    de: [pick('lidl:DE'), pick('rewe:DE'), c('[data-other]'), f('dm'), sug('dm:DE'), next],
    at: [pick('aldi-sued:AT'), pick('spar-at:AT'), pick('lidl:AT'), next],
    unlisted: [pick('lidl:DE'), c('[data-other]'), f('Hofladen Sonnenwiese'), c('[data-keep]'), next],
    skip: [c('[data-skip]')],
    twoapps: [pick('billa:AT'), next],
  },
  OB5: {
    de: [pick('lidl:DE'), pick('dm:DE'), pick('rewe:DE'), next],
    at: [pick('aldi-sued:AT'), pick('spar-at:AT'), pick('lidl:AT'), next],
    unlisted: [pick('lidl:DE'), ...ownTyped('Hofladen Sonnenwiese'), next],
    skip: [c('[data-skip]')],
    twoapps: [pick('billa:AT'), c('[data-app="jö Bonus Club"]'), next],
  },
  // OB4 has no step; its drive taps the card on the first list.
  OB4: {
    de: [pick('lidl:DE'), pick('dm:DE'), pick('rewe:DE'), c('[data-done]')],
    at: [pick('aldi-sued:AT'), pick('spar-at:AT'), pick('lidl:AT'), c('[data-done]')],
    unlisted: [pick('lidl:DE'), c('[data-other]'), f('Hofladen Sonnenwiese'), c('[data-keep]'), c('[data-done]')],
    skip: [c('[data-act="cardLater"]')],
    twoapps: [pick('billa:AT'), c('[data-done]')],
  },
};
// The stores each drive must end with: chain keys, or the name for a store of one's own.
export const expected = {
  today: { de: ['Lidl', 'dm', 'REWE'], at: ['Lidl', 'Hofer', 'SPAR'], unlisted: ['Lidl', 'Hofladen Sonnenwiese'], skip: [], twoapps: ['BILLA'] },
  linked: { de: ['lidl:DE', 'dm:DE', 'rewe:DE'], at: ['aldi-sued:AT', 'spar-at:AT', 'lidl:AT'], unlisted: ['lidl:DE', 'Hofladen Sonnenwiese'], skip: [], twoapps: ['billa:AT'] },
};

// --- Walks ------------------------------------------------------------------------------------------------------------------

const regionOf = { de: 'DE', at: 'AT', unlisted: 'DE', skip: 'DE', twoapps: 'AT', joiner: 'AT' };
const pool = {
  'lidl:DE': ['Milk|Vollmilch|chilled', 'Bananas|Bananen|produce'], 'Lidl': ['Milk|Vollmilch|chilled', 'Bananas|Bananen|produce'], 'lidl:AT': ['Milk|Milch|chilled'],
  'dm:DE': ['Toothpaste|Zahnpasta|other'], 'dm': ['Toothpaste|Zahnpasta|other'], 'rewe:DE': ['Bread|Brot|other'], 'REWE': ['Bread|Brot|other'],
  'aldi-sued:AT': ['Coffee beans|Kaffeebohnen|other', 'Bananas|Bananen|produce'], 'Hofer': ['Coffee beans|Kaffeebohnen|other'],
  'spar-at:AT': ['Bread|Brot|other'], 'SPAR': ['Bread|Brot|other'], 'billa:AT': ['Milk|Milch|chilled', 'Bread|Brot|other'], 'BILLA': ['Milk|Milch|chilled'],
  'Hofladen Sonnenwiese': ['Eggs|Eier|other'],
};
const itemsOf = (p) => (pool[p.key ?? p.name] ?? []).map((x) => { const [en, de, cat] = x.split('|'); return { en, de, cat }; });
const slug = (p) => (p.key ?? p.name).replace(/[^a-z]/gi, '').toLowerCase();
export const listOf = (picked) => picked.map((p) => ({ id: slug(p), name: p.name, link: p.key, app: p.app, items: itemsOf(p) }));
const loose = (lang) => [{ id: 'none', name: lang === 'de' ? 'Kein Laden' : 'No store', link: null, items: [{ en: 'Milk', de: 'Milch', cat: 'chilled' }, { en: 'Bananas', de: 'Bananen', cat: 'produce' }, { en: 'Toothpaste', de: 'Zahnpasta', cat: 'other' }] }];

const P = (k) => ({ key: k, name: chains[k].name });
const N = (n) => ({ key: null, name: n });
const picksFor = {
  today: { de: [N('Lidl'), N('dm'), N('REWE')], at: [N('Lidl'), N('Hofer'), N('SPAR')], unlisted: [N('Lidl'), N('Hofladen Sonnenwiese')], twoapps: [N('BILLA')] },
  linked: { de: [P('lidl:DE'), P('dm:DE'), P('rewe:DE')], at: [P('aldi-sued:AT'), P('spar-at:AT'), P('lidl:AT')], unlisted: [P('lidl:DE'), N('Hofladen Sonnenwiese')], twoapps: [P('billa:AT')] },
};
// What job 313's card asks about today's plain stores: the exact matches with an app, in the phone's region first.
const asksFor = (sc) => picksFor.today[sc].map((p) => ({ id: slug(p), name: p.name, key: exact(p.name, regionOf[sc]) })).filter((q) => q.key && chains[q.key].app);

const F = (cap, taps, state, extra = {}) => ({ cap, taps, state, ...extra });
const step = (sc, more = {}) => ({ screen: 'ob', region: regionOf[sc], picked: [], typed: '', ...more });
let LANG = 'en';
const firstList = (picked, more = {}) => ({ screen: 'list', stores: picked.length ? listOf(picked) : loose(LANG), ...more });
const storeScreen = (picked, id) => ({ screen: 'store', storeId: id, stores: listOf(picked) });
const brandt = () => listOf(picksFor.linked.de);
const caps = {
  arrive: L('Arriving at the step', 'Ankunft im Schritt'), picked: L('Picked', 'Gewählt'), list: L('First list', 'Erste Liste'),
  asks: L('First list: job 313 asks again', 'Erste Liste: Job 313 fragt noch einmal'), linkedAll: L('All linked', 'Alles verbunden'),
  joe: L('Store screen: jö Bonus Club chosen', 'Seite des Ladens: jö Bonus Club gewählt'), skipped: L('Skipped: the list without stores', 'Übersprungen: die Liste ohne Läden'),
  join: L('Invite link opened (phone set to Austria)', 'Einladung geöffnet (Handy auf Österreich)'), joined: L('Joined: the household’s links, keys and German apps', 'Beigetreten: die Verbindungen, Tasten und deutschen Apps des Haushalts'),
};

const walkFor = (id, sc) => {
  const [s1, , , later] = metrics[id][sc];
  const total = s1 + later;
  const o = options.find((x) => x.id === id);
  if (sc === 'joiner') {
    const last = id === 'OB4'
      ? [F(L('Nobody answered yet: the card asks the joiner, once for all', 'Noch niemand hat geantwortet: die Karte fragt, wer beitritt, einmal für alle'), 0, { screen: 'list', stores: loose(LANG), card: true, region: 'AT', picked: [] })]
      : [];
    return [F(caps.join, 0, { screen: 'join' }), F(caps.joined, 0, { screen: 'list', stores: brandt(), toast: W[LANG].joined('Familie Brandt') }), ...last];
  }
  const live = { live: true };
  if (o.noStep) {
    const picks = picksFor.linked[sc] ?? [];
    const frames = [F(L('First list, once setup is done', 'Erste Liste, nach der Einrichtung'), 0, firstList([], { card: true, region: regionOf[sc], picked: [] }), live)];
    if (sc === 'skip') return [...frames, F(L('“Not now”: no stores, no card', '„Später“: keine Läden, keine Karte'), 1, firstList([]))];
    if (sc === 'unlisted') frames.push(F(L('“Other store”: job 313’s sheet', '„Anderer Laden“: das Blatt aus Job 313'), 2, firstList([], { card: true, region: 'DE', picked: [P('lidl:DE')], sheet: { kind: 'search' }, typed: 'Hofladen Sonnenwiese' })));
    else frames.push(F(caps.picked, total - (sc === 'twoapps' ? JOE : 0) - 1, firstList([], { card: true, region: regionOf[sc], picked: picks })));
    frames.push(F(caps.linkedAll, total - (sc === 'twoapps' ? JOE : 0), firstList(picks)));
    if (sc === 'twoapps') frames.push(F(caps.joe, total, storeScreen([{ ...P('billa:AT'), app: 'jö Bonus Club' }], 'billaat')));
    return frames;
  }
  const frames = [F(caps.arrive, 0, step(sc), live)];
  if (sc === 'skip') return [...frames, F(caps.skipped, 1, firstList([]))];
  const picks = id === 'today' ? picksFor.today[sc] : picksFor.linked[sc];
  if (id === 'OB2') frames.push(F(L('Typing: matches, the region first', 'Beim Tippen: Treffer, die Region zuerst'), sc === 'unlisted' ? 1 : s1 - 2, step(sc, { picked: picks.slice(0, -1), typed: { de: 'Re', at: 'Li', unlisted: 'Hofladen Sonnenwiese', twoapps: 'Bi' }[sc] })));
  if (id === 'OB3' && (sc === 'de' || sc === 'unlisted')) frames.push(F(L('“Other store”: job 313’s sheet', '„Anderer Laden“: das Blatt aus Job 313'), 3 - (sc === 'unlisted' ? 1 : 0), step(sc, { picked: picks.filter((p) => p.key !== 'dm:DE' && p.key), sheet: { kind: 'search' }, typed: sc === 'de' ? 'dm' : 'Hofladen Sonnenwiese' })));
  if ((id === 'today' || id === 'OB1' || id === 'OB5') && sc === 'unlisted') frames.push(F(L('“Add your own store”, typed', '„Eigenen Laden hinzufügen“, getippt'), 2, step(sc, { picked: picks.slice(0, 1), naming: true, typed: 'Hofladen Sonnenwiese' })));
  if (id === 'OB1' && sc === 'at') frames.push(F(L('Aside: “Hofer” typed on a German phone is still found', 'Nebenbei: „Hofer“ auf einem deutschen Handy getippt wird trotzdem gefunden'), undefined, step('de', { picked: [P('lidl:DE')], naming: true, typed: 'Hofer' })));
  const pickedApp = id === 'OB5' && sc === 'twoapps' ? [{ ...P('billa:AT'), app: 'jö Bonus Club' }] : picks;
  frames.push(F(caps.picked, s1 - 1, step(sc, { picked: pickedApp, scrollEnd: id === 'OB5' })));
  if (id === 'today' && later > 0) {
    const qs = asksFor(sc);
    frames.push(F(caps.asks, s1, firstList(picks, { asks: qs, askOf: qs.length })));
    frames.push(F(caps.linkedAll, s1 + qs.length, firstList(picks.map((p) => { const k = exact(p.name, regionOf[sc]); return k && chains[k].app ? { ...p, key: k } : p; }))));
  } else frames.push(F(caps.list, s1, firstList(pickedApp)));
  if (sc === 'twoapps' && later >= JOE) frames.push(F(caps.joe, total, storeScreen([{ ...P('billa:AT'), app: 'jö Bonus Club' }], 'billaat')));
  return frames;
};

export const walk = (o, sc, lang = 'en') => { LANG = lang; return walkFor(o.id, sc).map((fr) => {
  const st = { ...fr.state };
  const end = st.scrollEnd;
  delete st.scrollEnd;
  return { cap: fr.cap, taps: fr.taps, state: st, live: fr.live, scrollTo: end ? 'end' : null };
}); };

const T = {
  en: ['On the step', 'typed', 'Later on the list', 'Total', 'Today (after 313)', 'Store screens in onboarding'],
  de: ['Im Schritt', 'getippt', 'Später auf der Liste', 'Gesamt', 'Heute (nach 313)', 'Laden-Bildschirme im Einstieg'],
};
export const walkNote = (o, sc, lang) => {
  const [s1, typed, screens, later] = metrics[o.id][sc];
  const t = T[lang];
  const tot = s1 + later;
  const d = tot - totalOf('today', sc);
  return `${t[0]}: <b data-step="${o.id}">${s1}</b>${typed ? ` (${typed}× ${t[1]})` : ''} · ${t[2]}: <b>${later}</b> · ${t[3]}: <b data-total="${o.id}">${tot}</b> · ${t[4]}: ${totalOf('today', sc)}${o.id === 'today' ? '' : ` (<b>${d > 0 ? '+' : ''}${d}</b>)`} · ${t[5]}: ${screens}`;
};

export const facts = {
  en: [
    'The store step is step 4 of 7 (<code>app/lib/onboarding/steps.dart</code>, <code>_StoresStep</code>): <code>popularStores</code> offers ten German chains and “Hardware store” to every phone, nothing preselected. “Add your own store” opens <code>StoreNameField</code> in place. Continue and Skip are equal buttons, and a line under them says where to add stores later.',
    'The same chips are on <code>CreateHouseholdScreen</code> (a second household from the switcher), so whatever wins here goes there too.',
    'Joiners (invite link or code) never see the store step: stores belong to the household. A link to a chain is household data in job 313 (<code>stores.retailer_chain</code>, <code>retailer_country</code>, <code>app</code>), so a joiner gets the links as they are.',
    'Job 313 (in progress) asks about the household’s unlinked stores on the list, one card at a time, but only those whose exact match has an app (SS5). A store made in onboarding today is such a store.',
    'Country is the phone’s region (Peter’s pick, SS-Q2). No option asks for location.',
  ],
  de: [
    'Der Laden-Schritt ist Schritt 4 von 7 (<code>app/lib/onboarding/steps.dart</code>, <code>_StoresStep</code>): <code>popularStores</code> bietet jedem Handy zehn deutsche Ketten und „Baumarkt“ an, nichts vorgewählt. „Eigenen Laden hinzufügen“ öffnet <code>StoreNameField</code> an Ort und Stelle. Weiter und Überspringen sind gleichwertige Knöpfe, eine Zeile darunter sagt, wo man Läden später anlegt.',
    'Dieselben Chips stehen auf <code>CreateHouseholdScreen</code> (ein zweiter Haushalt aus dem Wechsler), was hier gewinnt, gilt also auch dort.',
    'Wer beitritt (Einladungslink oder Code), sieht den Laden-Schritt nie: Läden gehören dem Haushalt. Die Verbindung zu einer Kette ist in Job 313 Haushaltsdaten (<code>stores.retailer_chain</code>, <code>retailer_country</code>, <code>app</code>), wer beitritt, bekommt sie also, wie sie sind.',
    'Job 313 (in Arbeit) fragt auf der Liste nach den unverbundenen Läden des Haushalts, eine Karte nach der anderen, aber nur nach denen, deren genauer Treffer eine App hat (SS5). Ein heute im Einstieg angelegter Laden ist so ein Laden.',
    'Das Land ist die Region des Handys (Peters Wahl, SS-Q2). Keine Option fragt nach dem Standort.',
  ],
};
