// Round OS: where "Open <store> app" lives. Today and OS1 to OS5 as hook records for phone.js.
import { ic, esc, t, appOf, openApp, badge } from './phone.js';

const at = (act, arg) => `data-act="${act}" data-arg="${esc(arg)}"`;
const storeById = (s, id) => s.stores.find((x) => x.id === id);

// Trip mode is on main behind `trip-mode` (internal only): a tick asks "Are you shopping right now?" and the strip runs.
// The frames start the trip directly, as "Yes, start a trip" would.
const today = {
  id: 'today', slug: 'today',
  title: { en: 'Today (main)', de: 'Heute (main)' },
  desc: {
    en: 'No way to open a retailer’s app. The header folds the section on a tap; a hold does nothing (job 171). Trip mode (internal only) shows its strip above the field.',
    de: 'Keine Möglichkeit, die App eines Händlers zu öffnen. Der Kopf klappt den Abschnitt beim Tippen zu; Halten tut nichts (Job 171). Der Einkaufsmodus (nur intern) zeigt seinen Streifen über dem Feld.',
  },
  tapsToOpen: null,
};

const appBtn = (s, st, cls = 'appbtn') => {
  const app = appOf(st);
  return app ? `<button class="${cls}" ${at('openApp', st.id)} aria-label="${esc(t(s).openApp(app))}" data-open="${st.id}">${ic('open_in_new')}</button>` : '';
};

const OS1 = {
  id: 'OS1', slug: 'header-button',
  title: { en: 'OS1 A button in the store’s header', de: 'OS1 Ein Knopf im Kopf des Ladens' },
  desc: {
    en: 'A raised hex key with the “open in new” glyph sits before the fold caret, only on stores with a known app. One tap from the list, always in view while you shop. Its name for screen readers is “Open Lidl Plus”; on screen it has no words, so the first use needs the label in a tooltip or a first-run tip.',
    de: 'Eine erhabene Hex-Taste mit dem Symbol „in neuem Fenster öffnen“ steht vor dem Klapp-Pfeil, nur bei Läden mit bekannter App. Ein Tipp von der Liste, beim Einkaufen immer im Blick. Screenreader lesen „Lidl Plus öffnen“; auf dem Bildschirm steht kein Wort, also braucht der erste Gebrauch einen Tooltip oder einen Tipp.',
  },
  tapsToOpen: 1,
  headerExtra: (s, st) => appBtn(s, st),
};

const OS2 = {
  id: 'OS2', slug: 'trip-strip',
  title: { en: 'OS2 In the trip strip, for the store you’re at', de: 'OS2 Im Einkaufsstreifen, für den Laden, in dem du bist' },
  desc: {
    en: 'While a trip runs, the strip above the field names the store of your last tick and offers its app: “At Lidl · Open Lidl Plus”. It needs trip mode (behind <code>trip-mode</code>, internal only); without a trip there is no button. At a store without an app the line goes away.',
    de: 'Während ein Einkauf läuft, nennt der Streifen über dem Feld den Laden deines letzten Hakens und bietet seine App an: „Bei Lidl · Lidl Plus öffnen“. Braucht den Einkaufsmodus (hinter <code>trip-mode</code>, nur intern); ohne Einkauf gibt es keinen Knopf. Bei einem Laden ohne App verschwindet die Zeile.',
  },
  tapsToOpen: 1,
  tripOnTick: true,
  stripExtra: (s) => {
    const st = s.tripStore && storeById(s, s.tripStore);
    const app = st && appOf(st);
    if (!app) return '';
    return `<div class="strip-app"><span class="grow">${esc(t(s).tripAt(st.name))}</span><button class="stripopen" ${at('openApp', st.id)} data-open="${st.id}">${ic('open_in_new', 'sm')}${esc(t(s).openApp(app))}</button></div>`;
  },
};

const OS3 = {
  id: 'OS3', slug: 'store-screen',
  title: { en: 'OS3 On the store’s own screen', de: 'OS3 Auf der Seite des Ladens' },
  desc: {
    en: 'List › Edit › Lidl shows an “App” card under the name with “Open”. Nothing changes on the list, so nothing gets in the way, and nothing reminds you either: three taps from the list, in a screen people visit to sort categories.',
    de: 'Liste › Anpassen › Lidl zeigt unter dem Namen eine Karte „App“ mit „Öffnen“. Auf der Liste ändert sich nichts, also stört nichts, aber es erinnert auch nichts daran: drei Tipps von der Liste, in einer Seite, die man zum Sortieren der Kategorien besucht.',
  },
  tapsToOpen: 3,
  storeExtra: (s, st) => {
    const app = appOf(st);
    if (!app) return '';
    return `<div class="card appcard"><span class="flabel">${esc(t(s).appRowLabel)}</span><div class="approw"><span class="hexface">${ic('storefront', 'sm')}</span><b class="grow">${esc(app)}</b>
      <button class="tact honey" ${at('openApp', st.id)} data-open="${st.id}"><span>${ic('open_in_new', 'sm')}${esc(t(s).openAppShort)}</span></button></div></div>`;
  },
};

const OS4 = {
  id: 'OS4', slug: 'store-menu',
  title: { en: 'OS4 A store menu from the header (no hold)', de: 'OS4 Ein Laden-Menü aus dem Kopf (ohne Halten)' },
  desc: {
    en: 'A “more” key before the caret opens a sheet for the store: “Open Lidl Plus” and “Edit store”. Every store gets the key, so the header looks the same with or without an app. A hold stays inert: job 171 (Peter) took the hold menu away, so it is a visible key, two taps.',
    de: 'Eine „Mehr“-Taste vor dem Pfeil öffnet ein Blatt für den Laden: „Lidl Plus öffnen“ und „Laden bearbeiten“. Jeder Laden hat die Taste, der Kopf sieht mit und ohne App gleich aus. Halten bleibt ohne Wirkung: Job 171 (Peter) hat das Halte-Menü entfernt, also eine sichtbare Taste, zwei Tipps.',
  },
  tapsToOpen: 2,
  headerExtra: (s, st) => `<button class="appbtn" ${at('menu', st.id)} aria-label="${esc(t(s).storeMenuLabel(st.name))}" data-menu="${st.id}">${ic('more_horiz')}</button>`,
  sheet: (s) => {
    const st = storeById(s, s.sheet.storeId);
    const app = appOf(st);
    return `<div class="shead"><h2>${esc(st.name)}</h2></div><div class="sbody">
      ${app ? `<button class="lrow tap" ${at('openApp', st.id)} data-open="${st.id}">${ic('open_in_new')}<span class="t grow">${esc(t(s).openApp(app))}</span></button>` : ''}
      <button class="lrow tap" ${at('editStore', st.id)}>${ic('edit_outlined')}<span class="t grow">${esc(t(s).editStore)}</span></button></div>`;
  },
  acts: {
    menu: (s, id) => ({ ...s, sheet: { storeId: id } }),
    editStore: (s, id) => ({ ...s, sheet: null, screen: 'store', storeId: id }),
  },
};

const OS5 = {
  id: 'OS5', slug: 'store-done',
  title: { en: 'OS5 When a store is done, and in the summary', de: 'OS5 Wenn ein Laden erledigt ist, und in der Übersicht' },
  desc: {
    en: 'Ticking the last item of a store turns its section into one line: “Lidl done · Open Lidl Plus”, the moment you walk to the checkout and need the card or coupons. The trip summary repeats it per store. Before that moment there is no button.',
    de: 'Der letzte Haken eines Ladens macht aus seinem Abschnitt eine Zeile: „Lidl erledigt · Lidl Plus öffnen“, genau wenn du zur Kasse gehst und Karte oder Coupons brauchst. Die Übersicht nach dem Einkauf wiederholt es je Laden. Vorher gibt es keinen Knopf.',
  },
  tapsToOpen: 1,
  doneSection: (s, st) => {
    const app = appOf(st);
    if (!app) return null;
    return `<section class="ssec" data-sec="${st.id}"><div class="donecard" data-done="${st.id}"><span class="donecheck">${ic('check', 'sm')}</span>
      <b class="grow donetext">${esc(t(s).storeDone(st.name))}</b>
      <button class="tact honey" ${at('openApp', st.id)} data-open="${st.id}"><span>${ic('open_in_new', 'sm')}${esc(t(s).openApp(app))}</span></button></div></section>`;
  },
  summaryExtra: (s, st) => {
    const app = appOf(st);
    return app ? `<button class="textbtn" ${at('openApp', st.id)} data-open="${st.id}">${ic('open_in_new', 'sm')}${esc(t(s).openApp(app))}</button>` : '';
  },
};

export const options = [today, OS1, OS2, OS3, OS4, OS5];

// The two Lidl items and both dm items ticked: dm is done, Lidl has two left.
const tickedSome = ['dm:0', 'dm:1', 'lidl:1', 'lidl:3'];

// Frames per option: a caption and the state (over phone.initial). `scrollTo` scrolls the list to a store's section;
// `ts` fixes the text size for that frame (the page's control sets the others).
export const frames = (opt) => {
  const L = (en, de) => ({ en, de });
  const list = { cap: L('The list (live: tap it)', 'Die Liste (live: tippen)'), live: true, state: {} };
  const installed = { cap: L('Lidl tapped, app installed', 'Lidl getippt, App installiert'), state: { outcome: { storeId: 'lidl' }, installed: true } };
  const missing = { cap: L('Lidl tapped, app not installed', 'Lidl getippt, App fehlt'), state: { outcome: { storeId: 'lidl' }, installed: false } };
  const linked = { cap: L('ALDI SÜD tapped (has an app link), installed', 'ALDI SÜD getippt (mit App-Link), installiert'), state: { outcome: { storeId: 'aldi' }, installed: true } };
  const longName = { cap: L('Long name and a store without an app, 310 %', 'Langer Name und ein Laden ohne App, 310 %'), state: {}, scrollTo: 'aldi', ts: 310 };
  switch (opt.id) {
    case 'today':
      return [list, { cap: L('A trip runs (trip mode)', 'Ein Einkauf läuft (Einkaufsmodus)'), state: { trip: true, tripStore: 'lidl', ticked: ['lidl:1'] } }, longName];
    case 'OS1':
      return [list, installed, linked, missing, longName, { cap: L('Header at 200 %', 'Kopf bei 200 %'), state: {}, ts: 200, scrollTo: 'lidl' }];
    case 'OS2': {
      const trip = { trip: true, tripStore: 'lidl', ticked: ['lidl:1'] };
      return [{ ...list, cap: L('A trip at Lidl (live)', 'Einkauf bei Lidl (live)'), state: trip }, { ...installed, state: { ...trip, ...installed.state } }, { ...missing, state: { ...trip, ...missing.state } },
        { cap: L('At the market: no app, no line', 'Auf dem Markt: keine App, keine Zeile'), state: { trip: true, tripStore: 'markt', ticked: ['lidl:1', 'markt:0'] }, scrollTo: 'markt' },
        { cap: L('Strip at 310 %', 'Streifen bei 310 %'), state: trip, ts: 310 }];
    }
    case 'OS3':
      return [list, { cap: L('List › Edit › Lidl (live)', 'Liste › Anpassen › Lidl (live)'), live: true, state: { screen: 'store', storeId: 'lidl' } }, { ...missing, state: { ...missing.state, screen: 'store', storeId: 'lidl' } },
        { cap: L('A store without an app: no card', 'Laden ohne App: keine Karte'), state: { screen: 'store', storeId: 'markt' } },
        { cap: L('Long name, 310 %', 'Langer Name, 310 %'), state: { screen: 'store', storeId: 'aldi' }, ts: 310 }];
    case 'OS4':
      return [list, { cap: L('The menu', 'Das Menü'), state: { sheet: { storeId: 'lidl' } } }, { cap: L('A store without an app: edit only', 'Laden ohne App: nur bearbeiten'), state: { sheet: { storeId: 'markt' } } }, installed, longName];
    case 'OS5':
      return [{ ...list, cap: L('dm done, Lidl in progress (live)', 'dm erledigt, Lidl läuft (live)'), state: { trip: true, tripStore: 'lidl', ticked: tickedSome } }, installed,
        { cap: L('The trip summary', 'Die Übersicht nach dem Einkauf'), state: { screen: 'summary', ticked: [...tickedSome, 'lidl:0', 'lidl:2', 'markt:0', 'markt:1'] } },
        { cap: L('Market done: no app, plain header', 'Markt erledigt: keine App, normaler Kopf'), state: { trip: true, ticked: [...tickedSome, 'markt:0', 'markt:1'] }, scrollTo: 'markt' },
        { cap: L('Done line, long name, 310 %', 'Erledigt-Zeile, langer Name, 310 %'), state: { trip: true, ticked: [...tickedSome, 'aldi:0', 'aldi:1'] }, scrollTo: 'aldi', ts: 310 }];
    default:
      return [list];
  }
};

// The state each option is measured in, and Today in the same state, for "extra height" and "rows in view".
export const measureState = (opt) => {
  if (opt.id === 'OS2') return { trip: true, tripStore: 'lidl', ticked: ['lidl:1'] };
  if (opt.id === 'OS5') return { trip: true, tripStore: 'lidl', ticked: tickedSome };
  return {};
};

export { badge, openApp };
