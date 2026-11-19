// The phone: one state object, one view(state) that returns its HTML, and act(state, name, arg) for taps.
// Every option is a record of hooks (os.js, ss.js); the screens below ask the option, never test its label.
import { copy } from './copy.js';
import { icons } from './icons.js';
import { chains, chainsByCountry, household, listStores, categories, storeListing, nearby } from './data.js';

export const ic = (n, cls = '') => `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[n]}"/></svg>`;
export const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const at = (act, arg) => `data-act="${act}"${arg === undefined ? '' : ` data-arg="${esc(arg)}"`}`;

export const t = (s) => copy[s.lang];
export const chainOf = (store) => (store.link ? chains[store.link] : null);
export const appOf = (store) => chainOf(store)?.app ?? null;

// A fresh state. `opt` is the option's hook record; `stores` a deep copy of the household's list so a walk can change it.
export const initial = (opt, over = {}) => ({
  lang: 'en', theme: 'light', ts: 100, platform: 'ios', installed: true,
  opt, screen: 'list', storeId: null, sheet: null, outcome: null, dialog: null,
  trip: false, tripStore: null, ticked: [], folded: [],
  stores: structuredClone(listStores), country: 'DE', query: '', typed: '', toast: null,
  ...over,
});

const tsCls = (s) => (s.ts === 310 ? 'ts310' : s.ts === 200 ? 'ts200' : '');

// --- Pieces -------------------------------------------------------------------------------------------------------

export const badge = (name, extra = '') => `<span class="sbadge ${extra}"><span>${esc(name)}</span></span>`;
const tact = (label, { act, arg, honey = false, icon, cls = '' } = {}) =>
  `<button class="tact ${honey ? 'honey' : ''} ${cls}" ${act ? at(act, arg) : ''}><span>${icon ? ic(icon, 'sm') : ''}${esc(label)}</span></button>`;
const status = () => '<div class="status"><span>9:41</span><span class="grow"></span><span class="sig"></span></div>';
const homeind = () => '<div class="homeind"><i></i></div>';

const itemRow = (s, store, item, i) => {
  const key = `${store.id}:${i}`;
  return `<button class="item" ${at('tick', key)} data-item="${key}"><span class="box"></span>${item.qty ? `<span class="qty">${esc(item.qty)}</span>` : ''}<span class="iname">${esc(item[s.lang])}</span></button>`;
};

const openItems = (s, store) => store.items.map((it, i) => ({ it, i })).filter(({ i }) => !s.ticked.includes(`${store.id}:${i}`));

// The store's section header, as dividers.dart draws it, plus whatever the option adds before the caret.
const header = (s, store) => {
  const open = openItems(s, store).length;
  const folded = s.folded.includes(store.id);
  const extra = s.opt.headerExtra?.(s, store) ?? '';
  return `<div class="shead-row" data-store="${store.id}">
    <button class="shead-hit" ${at('fold', store.id)} aria-label="${esc(store.name)}, ${esc(t(s).itemCount(open))}"></button>
    <span class="shead-left">${badge(store.name)}<i class="rule"></i></span>
    <span class="cnt"><b>${open}</b> ${esc(t(s).itemWord(open))}</span>${extra}<span class="caret ${folded ? 'folded' : ''}" aria-hidden="true">${ic('expand_more')}</span>${s.opt.headerTrail?.(s, store) ?? ''}</div>`;
};

const section = (s, store) => {
  const rows = openItems(s, store);
  const done = rows.length === 0;
  const replaced = done ? s.opt.doneSection?.(s, store) : null;
  if (replaced) return replaced;
  let html = header(s, store);
  if (s.folded.includes(store.id)) return `<section class="ssec" data-sec="${store.id}">${html}</section>`;
  let lastCat = null;
  for (const { it, i } of rows) {
    if (it.cat !== lastCat) { html += `<div class="catlabel">${esc(categories[it.cat][s.lang])}</div>`; lastCat = it.cat; }
    html += itemRow(s, store, it, i);
  }
  return `<section class="ssec" data-sec="${store.id}">${html}</section>`;
};

const tripStrip = (s) => {
  const extra = s.opt.stripExtra?.(s) ?? '';
  return `<div class="tripstrip" data-strip>${extra}<div class="strip-row"><i class="dot"></i><b class="clock">12:04</b><span class="slabel">${esc(t(s).shopRunning)}</span>
    <button class="sbtn" ${at('noop')} aria-label="${esc(t(s).shopPause)}">${ic('pause')}</button><button class="send" ${at('noop')}>${esc(t(s).shopEnd)}</button></div></div>`;
};

const bottom = (s) => `<div class="bottom" data-bottom>${s.trip ? tripStrip(s) : ''}
  <div class="addfield"><span>${esc(t(s).addFieldHint)}</span>${ic('mic_none')}</div>
  <div class="tabs"><span class="tab on">${ic('shopping_cart', 'sm')}${esc(t(s).tabList)}</span><span class="tab">${ic('menu', 'sm')}${esc(t(s).tabMore)}</span></div></div>`;

// --- Screens ------------------------------------------------------------------------------------------------------

const listScreen = (s) => `
  <div class="appbar list-top"><button class="switch" ${at('noop')}><span class="sw-h">${esc(household.name)}</span><span class="sw-l">${esc(household.list[s.lang])}</span>${ic('arrow_drop_down', 'sm')}</button><span class="grow"></span>
    <button class="tact" ${at('go', 'stores')}><span>${esc(t(s).listEdit)}</span></button></div>
  <div class="body list" data-scroll>${s.opt.listTop?.(s) ?? ''}${s.stores.map((st) => section(s, st)).join('')}</div>
  ${bottom(s)}`;

const backbar = (s, title, to) => `<div class="appbar plain"><button class="iconbtn" ${at('go', to)} aria-label="${esc(t(s).back)}">${ic('arrow_back')}</button><h1>${esc(title)}</h1></div>`;

const storesScreen = (s) => `${backbar(s, t(s).storesTitle, 'list')}
  <div class="body" data-scroll><div class="col">
    ${s.opt.storesTop?.(s) ?? ''}
    <p class="small">${esc(t(s).storesHint)}</p>
    ${s.stores.map((st) => `<button class="srow" ${at('store', st.id)} data-row="${st.id}"><span class="grow"><span class="sname">${esc(st.name)}</span>${s.opt.storeSub?.(s, st) ?? ''}</span>${ic('delete_outline', 'muted')}${ic('drag_handle')}</button>`).join('')}
    <div class="srow nostore"><span class="grow sname muted">${esc(t(s).noStore)}</span>${ic('chevron_right')}</div>
  </div></div>
  <div class="fab">${tact(t(s).storeAdd, { honey: true, icon: 'add', act: 'add' })}</div>`;

const storeScreen = (s) => {
  const st = s.stores.find((x) => x.id === s.storeId);
  const cats = [...new Set(st.items.map((i) => i.cat))];
  return `${backbar(s, st.name, 'stores')}
  <div class="body" data-scroll><div class="col">
    <div class="hexfield"><span><span class="grow fieldtext">${esc(st.name)}</span>${ic('edit_outlined')}</span></div>
    ${s.opt.storeExtra?.(s, st) ?? ''}
    <p class="small">${esc(t(s).storeLayoutHint)}</p>
    ${cats.map((c) => `<div class="srow"><span class="grow sname">${esc(categories[c][s.lang])}</span>${ic('drag_handle')}</div>`).join('')}
  </div></div>`;
};

const summaryScreen = (s) => {
  const planned = s.stores.reduce((n, st) => n + st.items.length, 0);
  const bought = s.ticked.length;
  return `${backbar(s, t(s).shopSummaryTitle, 'list')}
  <div class="body" data-scroll><div class="col">
    <p class="lead"><b>${esc(t(s).shopLede(bought, planned))}</b></p>
    <p class="small">${esc(t(s).shopShoppedFor('34 min'))}</p>
    ${s.stores.filter((st) => st.items.some((_, i) => s.ticked.includes(`${st.id}:${i}`))).map((st) => `
      <div class="sumstore" data-sum="${st.id}"><div class="sumhead">${badge(st.name)}<span class="grow"></span>${s.opt.summaryExtra?.(s, st) ?? ''}</div>
      ${st.items.map((it, i) => `<div class="sumrow"><span class="grow">${esc(it[s.lang])}</span><span class="small">${esc(s.ticked.includes(`${st.id}:${i}`) ? t(s).shopBought : t(s).shopNotBought)}</span></div>`).join('')}</div>`).join('')}
  </div></div>`;
};

// What happens outside Snacklist after "Open <app>". Android launches the package, else the Play page. iOS opens the
// registry's https link when it has one (the app if installed, else the App Store page); without one, only the App
// Store page can open, where "Open" starts an installed app.
export const outcomeKind = (s, link) => {
  const ul = chains[link]?.ul;
  if (s.platform === 'android') return s.installed ? 'app' : 'store';
  if (!ul) return s.installed ? 'storeOpen' : 'store';
  return s.installed ? 'app' : 'store';
};

const outcome = (s) => {
  const st = s.stores.find((x) => x.id === s.outcome.storeId);
  const app = appOf(st);
  const kind = outcomeKind(s, st.link);
  const L = t(s);
  const ios = s.platform === 'ios';
  const back = ios ? `<button class="iosback" ${at('closeOutcome')}>◀ ${esc(L.backTo)}</button>` : `<button class="andback top" ${at('closeOutcome')} aria-label="${esc(L.back)}">${ic('arrow_back')}</button>`;
  if (kind === 'app') {
    return `<div class="outside app-open" data-outcome="app">${back}
      <div class="ghost-app">${ic('storefront', 'xl')}<b>${esc(L.appOpens(app))}</b><span>${esc(L.appOpensSub)}</span></div></div>`;
  }
  const listing = storeListing[app] ?? { title: app, dev: '' };
  const btn = kind === 'storeOpen' ? L.openAppShort : ios ? L.get : L.install;
  const note = kind === 'storeOpen' ? L.storePageNoLink(app) : L.storePageNote;
  return `<div class="outside storepage ${ios ? 'ios' : 'android'}" data-outcome="${kind}">${back}
    <div class="sp-head">${esc(ios ? L.appStore : L.playStore)}</div>
    <div class="sp-app"><span class="sp-icon">${ic('storefront')}</span><span class="grow"><b>${esc(listing.title)}</b><span>${esc(listing.dev)}</span></span></div>
    <span class="sp-get">${esc(btn)}</span>
    <p class="sp-note">${esc(note)}</p></div>`;
};

const screens = { list: listScreen, stores: storesScreen, store: storeScreen, summary: summaryScreen };

export const view = (s) => {
  const body = (s.opt.screens?.[s.screen] ?? screens[s.screen])(s);
  const sheet = s.sheet ? `<div class="scrim" ${at('closeSheet')}></div><div class="sheet" data-sheet><div class="handle"></div>${s.opt.sheet(s)}</div>` : '';
  const dialog = s.dialog ? `<div class="scrim dim"></div>${s.opt.dialog(s)}` : '';
  const toast = s.toast ? `<div class="snack">${esc(s.toast)}</div>` : '';
  return `<div class="phone ${tsCls(s)} th-${s.theme}" data-screen="${s.screen}">${status()}${body}${sheet}${dialog}${toast}${s.outcome ? outcome(s) : ''}${homeind()}</div>`;
};

// --- Taps ---------------------------------------------------------------------------------------------------------

export const openApp = (s, storeId) => {
  const st = s.stores.find((x) => x.id === storeId);
  return { ...s, sheet: null, outcome: { app: appOf(st), storeId } };
};

const base = {
  noop: (s) => s,
  fold: (s, id) => ({ ...s, folded: s.folded.includes(id) ? s.folded.filter((x) => x !== id) : [...s.folded, id] }),
  tick: (s, key) => ({ ...s, ticked: [...s.ticked, key], trip: s.opt.tripOnTick ? true : s.trip, tripStore: key.split(':')[0] }),
  go: (s, to) => ({ ...s, screen: to, sheet: null }),
  store: (s, id) => ({ ...s, screen: 'store', storeId: id }),
  openApp,
  closeOutcome: (s) => ({ ...s, outcome: null }),
  closeSheet: (s) => ({ ...s, sheet: null }),
  add: (s) => s,
};

export const act = (s, name, arg) => (s.opt.acts?.[name] ?? base[name])(s, arg);

// A live phone in the page: renders, counts taps, and tells the page after each one.
export class Phone {
  constructor(el, state, onTap) {
    this.el = el;
    this.s = state;
    this.taps = 0;
    this.onTap = onTap;
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-act]');
      if (!b || !el.contains(b)) return;
      const name = b.dataset.act;
      if (name === 'noop') return;
      this.taps += 1;
      this.s = act(this.s, name, b.dataset.arg);
      this.render();
      this.onTap?.(this, name);
    });
    el.addEventListener('input', (e) => {
      if (e.target.dataset.input) {
        const pos = e.target.selectionStart;
        this.s = { ...this.s, [e.target.dataset.input]: e.target.value };
        this.render();
        const f = el.querySelector(`[data-input="${e.target.dataset.input}"]`);
        f?.focus();
        f?.setSelectionRange(pos, pos);
      }
    });
    this.render();
  }

  render() {
    const scroll = this.el.querySelector('[data-scroll]')?.scrollTop ?? 0;
    this.el.innerHTML = view(this.s);
    const sc = this.el.querySelector('[data-scroll]');
    if (sc) sc.scrollTop = scroll;
  }
}

export { chains, chainsByCountry, nearby };
