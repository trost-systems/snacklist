// Draws one phone frame of one option: the list (job 350's hidden categories, job 348's TE1 total), a tick, the
// menu open, the add sheet with the keyboard, the settings page and the empty list. Everything a user could tap
// carries data-tap; item rows data-row; the bars over the list data-chrome="top|bottom"; system chrome (status bar,
// keyboard) data-system. measure.js reads these.
import { icons } from './icons.js';
import { household, items, lists, members, money, otherHousehold, stores, suggestions, totals, typed } from './data.js';
import { dests, legal, menuDests, moreGroups, morePageDests } from './places.js';
import { arb, proposed } from './strings.js';

export const esc = (x) => String(x).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
const ic = (name, cls = 'icon') => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name]}"/></svg>`;

// ARB text with the ICU forms the round uses: {name} and {count, plural, =1{…} other{…}}.
export const w = (lang, key, params = {}) => {
  const src = arb[lang][key] ?? proposed[lang][key];
  if (src === undefined) throw new Error(`no string ${key}`);
  const plural = src.replace(/\{(\w+), plural, =1\{([^}]*)\} other\{((?:[^{}]|\{\w+\})*)\}\}/g, (_, k, one, other) => (Number(params[k]) === 1 ? one : other));
  return plural.replace(/\{(\w+)\}/g, (_, k) => params[k] ?? `{${k}}`);
};
const t = (s, key, params) => esc(w(s.lang, key, params));
// A word the app does not have yet, marked on the round page.
const nw = (s, key) => `<span class="new" data-proposed="${key}">${t(s, key)}</span>`;

const storeName = (s, id) => stores.find((x) => x.id === id)[s.lang];
const qty = (it) => (it.qty === '' ? '' : /^\d+$/.test(it.qty) ? `${it.qty}×` : it.qty);
const listName = (s) => esc(lists[0][s.lang]);
const hh = (s) => esc(household[s.lang]);

const statusBar = () => `<div class="status" data-system><span>9:41</span><i class="sig"></i></div>`;

// ---- list parts ----

const cell = (it) => (it.emoji ? `<span class="emo">${it.emoji}</span>` : '<span class="emo"><i class="ph"></i></span>');

const priceTail = (s, o, it) => {
  const name = esc(it[s.lang]);
  if (o.price === 'chip') {
    return it.price === null
      ? `<button class="pchip" data-tap aria-label="${t(s, 'priceAdd')} ${name}"><span class="face">${ic('add', 'icon tiny')}${t(s, 'priceAdd')}</span></button>`
      : `<button class="pchip set" data-tap aria-label="${t(s, 'priceAdd')} ${name}"><span class="face">${esc(money(s.lang, it.price))}</span></button>`;
  }
  if (o.price === 'leader') {
    return it.price === null
      ? `<i class="lead"></i><button class="pleader none" data-tap aria-label="${t(s, 'priceAdd')} ${name}"><span class="face">+ ${t(s, 'priceAdd')}</span></button>`
      : `<i class="lead"></i><button class="pleader" data-tap aria-label="${t(s, 'priceAdd')} ${name}"><span class="face">${esc(money(s.lang, it.price))}</span></button>`;
  }
  return it.price === null
    ? `<button class="ptext none" data-tap aria-label="${t(s, 'priceAdd')} ${name}"><span class="face">${ic('add', 'icon small')}</span></button>`
    : `<button class="ptext" data-tap aria-label="${t(s, 'priceAdd')} ${name}"><span class="face">${esc(money(s.lang, it.price))}</span></button>`;
};

const tickCtl = (o) => (['circle', 'box', 'sticker'].includes(o.tick) ? `<span class="tk ${o.tick}">${ic('check', 'icon tkicon')}</span>` : '');

const row = (s, o, it, { ticked = false, last = false } = {}) => {
  const q = qty(it);
  const ctl = tickCtl(o);
  const name = `<span class="nm"><span class="nl">${q ? `<b class="q">${esc(q)}</b> ` : ''}<b class="n">${esc(it[s.lang])}</b></span>${it.detail ? `<small class="dt">${esc(it.detail)}</small>` : ''}</span>`;
  const swipe = o.tick === 'swipe' ? `<span class="swipebg">${ic('check')}</span>` : '';
  return `<div class="item${ticked ? ' ticked' : ''}${last ? ' last' : ''}" data-row="${it.id}" data-tap="row">${swipe}<div class="iin">
    ${o.tickAt === 'end' ? '' : ctl}${cell(it)}${name}${priceTail(s, o, it)}${o.tickAt === 'end' ? ctl : ''}</div></div>`;
};

const storeSum = (store) => totals().lines.find((l) => l.store === store);

const storeHead = (s, o, store, n) => {
  const nm = esc(storeName(s, store));
  const count = `<span class="dcount"><b>${n}</b>${s.ts >= 2 ? '' : ` ${t(s, 'itemsWord', { count: n })}`}</span>`;
  if (o.stores === 'rule') return `<div class="shead rule" data-tap="store"><span class="sname">${nm}</span><i class="sline"></i><span class="stail">${count}${ic('expand_more', 'icon chev')}</span></div>`;
  if (o.stores === 'caps') return `<div class="shead caps" data-tap="store"><span class="sname">${nm}</span><span class="stail">${count}</span></div>`;
  if (o.stores === 'card') {
    const sum = storeSum(store);
    return `<div class="shead card" data-tap="store"><span class="sname">${nm}</span><span class="stail">${sum ? `<span class="ssum">${sum.atLeast ? `${t(s, 'moneyAtLeast', { amount: money(s.lang, sum.sum) })}` : esc(money(s.lang, sum.sum))}</span>` : count}${ic('expand_more', 'icon chev')}</span></div>`;
  }
  return `<div class="shead title" data-tap="store"><span class="sname">${nm}</span><span class="stail">${count}</span></div>`;
};

const section = (s, o, store, { tickId } = {}) => {
  const its = items.filter((i) => i.store === store);
  const rows = its.map((it, k) => row(s, o, it, { ticked: it.id === tickId, last: k === its.length - 1 })).join('');
  return `<section class="store" data-store="${store}">${storeHead(s, o, store, its.length)}<div class="rows">${rows}</div></section>`;
};

// TE1 (job 348): a line per store with a price, the total with „mind.“ and once „N ohne Preis“.
const totalBlock = (s, o) => {
  const tot = totals();
  const amt = (sum, atLeast) => (atLeast ? t(s, 'moneyAtLeast', { amount: money(s.lang, sum) }) : esc(money(s.lang, sum)));
  const lines = tot.lines.map((l) => `<div class="tline"><span class="tname">${esc(storeName(s, l.store))}</span><span class="tamt">${amt(l.sum, l.atLeast)}</span></div>`).join('');
  return `<div class="totals" data-totals><div class="tin"><div class="ttitle">${t(s, 'tripTotal')}</div>${lines}
    <div class="tgrand"><div class="tline big"><span class="tname">${t(s, 'subtotalsTotal')}</span><span class="tamt">${amt(tot.sum, tot.atLeast)}</span></div>
    <div class="tun">${t(s, 'subtotalsUnpriced', { count: tot.unpriced })}</div></div></div></div>`;
};

const recently = (s) => `<div class="used" data-tap="used"><span>${t(s, 'recentlyUsed')}</span>${ic('expand_more', 'icon chev')}</div>`;

const listBody = (s, o, opts = {}) => {
  const ids = o.stores === 'tabs' && s.storeTab ? [s.storeTab] : stores.map((x) => x.id);
  return `<div class="content">${ids.map((id) => section(s, o, id, opts)).join('')}${totalBlock(s, o)}${recently(s)}</div>`;
};

// ---- headers ----

const switcher = (s) => `<button class="switcher" data-tap aria-label="${hh(s)}, ${listName(s)}"><span class="face"><span class="two"><small>${hh(s)}</small><b>${listName(s)}</b></span>${ic('unfold_more', 'icon updown')}</span></button>`;
const editBtn = (s) => `<button class="btn edit" data-tap data-dest="edit"><span class="face">${t(s, 'listEdit')}</span></button>`;
const iconBtn = (name, label, cls = '', dest = '') => `<button class="ibtn ${cls}" data-tap${dest ? ` data-dest="${dest}"` : ''} aria-label="${esc(label)}"><span class="face">${ic(name)}</span></button>`;
const avatars = (s) => `<button class="avatars" data-tap aria-label="${hh(s)}">${members.map((m, k) => `<span class="av av${k}">${m.initial}</span>`).join('')}</button>`;

const storeTabs = (s, active = s.storeTab ?? 'all') => {
  const tab = (id, label, n) => `<button class="stab${id === active ? ' on' : ''}" data-tap><span class="face"><span>${label}</span><small>${n}</small></span></button>`;
  return `<div class="stabs">${tab('all', nw(s, 'allStores'), items.length)}${stores.map((x) => tab(x.id, esc(x[s.lang]), items.filter((i) => i.store === x.id).length)).join('')}</div>`;
};

const header = (s, o) => {
  switch (o.nav) {
    case 'float':
    case 'fab':
    case 'split':
      return `<header class="appbar bar-switch" data-chrome="top">${switcher(s)}${editBtn(s)}</header>`;
    case 'dock':
      return `<header class="appbar bar-title" data-chrome="top"><div class="ttl"><small>${hh(s)}</small><b>${listName(s)}</b></div>${editBtn(s)}</header>`;
    case 'docked':
      return `<header class="appbar bar-large" data-chrome="top"><button class="large" data-tap><small>${hh(s)}</small><span><b>${listName(s)}</b>${ic('expand_more', 'icon')}</span></button></header>`;
    case 'panel':
      return `<header class="appbar bar-panel" data-chrome="top"><button class="ptitle" data-tap><small>${hh(s)}</small><span><b>${listName(s)}</b>${ic('expand_more', 'icon')}</span></button>${iconBtn('tune', w(s.lang, 'listEdit'), '', 'edit')}</header>`;
    case 'drawer':
      return `<header class="appbar bar-drawer" data-chrome="top">${iconBtn('menu', w(s.lang, 'menu'))}<div class="ttl"><small>${hh(s)}</small><b>${listName(s)}</b></div>${iconBtn('tune', w(s.lang, 'listEdit'), '', 'edit')}</header>`;
    case 'avatars':
      return `<header class="appbar bar-avatars" data-chrome="top"><div class="arow"><button class="ptitle" data-tap><small>${hh(s)}</small><span><b>${listName(s)}</b>${ic('expand_more', 'icon')}</span></button>${avatars(s)}</div>
        <div class="seg" role="tablist"><button class="on" data-tap>${t(s, 'tabList')}</button><button data-tap data-dest="history">${t(s, 'tabHistory')}</button></div></header>`;
    case 'storeTabs':
      return `<header class="appbar bar-tabs" data-chrome="top"><div class="arow">${switcher(s)}${iconBtn('more_horiz', w(s.lang, 'menu'))}</div>${storeTabs(s)}</header>`;
    case 'textTabs':
      return `<header class="appbar bar-receipt" data-chrome="top"><button class="ptitle" data-tap><small>${hh(s)}</small><span><b>${listName(s)}</b>${ic('expand_more', 'icon')}</span></button>${editBtn(s)}</header>`;
    default:
      throw new Error(`nav ${o.nav}`);
  }
};

// ---- bottoms ----

const addField = (s, { mic = false, cls = '' } = {}) => `<button class="addfield ${cls}" data-tap><span class="face"><span class="hint">${t(s, 'addFieldHint')}</span>${mic ? ic('mic_none', 'icon mic') : ''}</span></button>`;
const tabsDef = (s, withStores) => [
  ['shopping_cart_outlined', w(s.lang, 'tabList'), 'list-tab'],
  ['history', w(s.lang, 'tabHistory'), 'history'],
  ...(withStores ? [['storefront_outlined', w(s.lang, 'storesTitle'), 'edit']] : []),
  ['menu', w(s.lang, 'tabMore'), 'more'],
];
const tabBar = (s, { withStores = false, active = 0, cls = '' } = {}) =>
  `<nav class="tabbar ${cls}"><span class="face">${tabsDef(s, withStores).map(([i, l, d], k) => `<button class="tab${k === active ? ' on' : ''}" data-tap data-dest="${d}"><span class="face"><span class="ti">${ic(i)}</span><span class="tl">${esc(l)}</span></span></button>`).join('')}</span></nav>`;

const bottom = (s, o, { active = 0, noAdd = false } = {}) => {
  const add = noAdd ? '' : addField(s);
  switch (o.nav) {
    case 'float':
      return `<footer class="dock dock-float" data-chrome="bottom">${add}${tabBar(s, { active })}</footer>`;
    case 'dock':
      return `<footer class="dock dock-pill" data-chrome="bottom">${iconBtn('menu', w(s.lang, 'menu'), 'menubtn')}${noAdd ? '' : addField(s, { mic: true })}</footer>`;
    case 'docked':
      return `<footer class="dock dock-docked" data-chrome="bottom">${add ? `<div class="addwrap">${add}</div>` : ''}${tabBar(s, { withStores: true, active })}</footer>`;
    case 'panel':
      return noAdd ? '' : `<footer class="dock dock-panel" data-chrome="bottom">${addField(s, { mic: true })}</footer>`;
    case 'fab': {
      const tabs = tabsDef(s, true);
      const b = (k) => `<button class="tab${k === active ? ' on' : ''}" data-tap data-dest="${tabs[k][2]}"><span class="face"><span class="ti">${ic(tabs[k][0])}</span><span class="tl">${esc(tabs[k][1])}</span></span></button>`;
      return `<footer class="dock dock-fab" data-chrome="bottom"><nav class="tabbar"><span class="face">${b(0)}${b(1)}<span class="fabgap"></span>${b(2)}${b(3)}</span></nav>
        <button class="fab" data-tap aria-label="${t(s, 'addItem')}"><span class="face">${ic('add')}</span></button></footer>`;
    }
    case 'drawer':
    case 'avatars':
    case 'storeTabs':
      return noAdd ? '' : `<footer class="dock dock-solo" data-chrome="bottom">${addField(s, { mic: o.nav !== 'storeTabs' })}</footer>`;
    case 'textTabs':
      return `<footer class="dock dock-receipt" data-chrome="bottom">${add ? `<div class="addwrap">${add}</div>` : ''}${tabBar(s, { active })}</footer>`;
    case 'split':
      return `<footer class="dock dock-split" data-chrome="bottom">${tabBar(s, { active })}<button class="fab bite" data-tap aria-label="${t(s, 'addItem')}"><span class="face">${ic('add')}</span></button></footer>`;
    default:
      throw new Error(`nav ${o.nav}`);
  }
};

// ---- menus ----

const listRows = (s, { current = true } = {}) => {
  const lrow = (l, on) => `<button class="mrow lrow${on ? ' on' : ''}" data-tap><span class="mi">${ic(on ? 'check' : 'list')}</span><span class="ml">${esc(l[s.lang])}</span><small>${l.count}</small></button>`;
  return `${lists.map((l, k) => lrow(l, current && k === 0)).join('')}<button class="mrow add" data-tap><span class="mi">${ic('add')}</span><span class="ml">${nw(s, 'newList')}</span></button>`;
};
// A place's row; every row carries data-dest so verify can check that each option draws every place.
const destRow = (s, id) => `<button class="mrow" data-tap data-dest="${id}"><span class="mi">${ic(dests[id].icon)}</span><span class="ml">${t(s, dests[id].key)}</span>${ic('chevron_right', 'icon chev')}</button>`;
// The places in More's grouping, History and Edit first; RD8's popover shows the legal pages as one line of links.
const destGroups = (s, ids, { legalLinks = false, moreRow = false } = {}) => {
  const groups = [['history', 'edit'], ...moreGroups].map((g) => g.filter((d) => ids.includes(d))).filter((g) => g.length);
  const out = groups.map((g) => (legalLinks && g.every((d) => legal.includes(d))
    ? `<div class="legal">${g.map((d) => `<button class="llink" data-tap data-dest="${d}">${t(s, dests[d].key)}</button>`).join('')}</div>`
    : `<div class="mgroup">${g.map((d) => destRow(s, d)).join('')}</div>`));
  if (moreRow) out.splice(out.length - (legalLinks ? 1 : 0), 0, `<div class="mgroup"><button class="mrow" data-tap data-dest="more"><span class="mi">${ic('more_horiz')}</span><span class="ml">${t(s, 'tabMore')}</span>${ic('chevron_right', 'icon chev')}</button></div>`);
  return out.join('');
};
const householdHead = (s) => `<div class="hhead"><span class="avs">${members.map((m, k) => `<span class="av av${k}">${m.initial}</span>`).join('')}</span><span class="hn"><b>${hh(s)}</b><small>${t(s, 'householdMembers', { count: members.length })}</small></span><button class="btn small" data-tap><span class="face">${t(s, 'switcherInvite')}</span></button></div>`;
const otherHh = (s) => `<button class="mrow other" data-tap><span class="mi">${ic('home_outlined')}</span><span class="ml">${esc(otherHousehold[s.lang])}</span><small>${otherHousehold.lists.length}</small>${ic('chevron_right', 'icon chev')}</button>`;
const grab = '<i class="grab"></i>';

const sheet = (inner, cls = '') => `<div class="scrim"></div><div class="sheet ${cls}" data-sheet>${grab}<div class="sheetin">${inner}</div></div>`;

const switcherSheet = (s) => sheet(`${householdHead(s)}<div class="mgroup">${listRows(s)}</div><div class="mlabel">${nw(s, 'households')}</div><div class="mgroup">${otherHh(s)}</div>`);

const navOpen = (s, o) => {
  const ids = menuDests(o);
  switch (o.nav) {
    case 'float':
    case 'fab':
    case 'split':
    case 'textTabs':
    case 'docked':
      return switcherSheet(s);
    case 'dock':
      return sheet(`<div class="mlabel">${t(s, 'listsTitle')}</div><div class="mgroup">${listRows(s)}</div>${destGroups(s, ids)}<div class="mgroup">${otherHh(s)}</div>`, 'menu');
    case 'panel':
      return `<div class="scrim"></div><div class="panel" data-sheet><div class="sheetin">${householdHead(s)}<div class="mgroup">${listRows(s)}</div><div class="mgroup">${otherHh(s)}</div>${destGroups(s, ids)}</div></div>`;
    case 'drawer':
      return `<div class="scrim"></div><aside class="drawer" data-sheet><div class="sheetin">${householdHead(s)}<div class="mlabel">${t(s, 'listsTitle')}</div><div class="mgroup">${listRows(s)}</div>${destGroups(s, ids)}<div class="mgroup">${otherHh(s)}</div></div></aside>`;
    case 'avatars':
      return sheet(`${householdHead(s)}${destGroups(s, ids)}<div class="mgroup">${otherHh(s)}</div>`);
    case 'storeTabs':
      return `<div class="scrim clear"></div><div class="popover" data-sheet><div class="sheetin">${destGroups(s, ids, { legalLinks: true, moreRow: true })}</div></div>`;
    default:
      throw new Error(`nav ${o.nav}`);
  }
};

// ---- add sheet with the keyboard ----

const keyboard = (s) => {
  const rows = s.lang === 'de' ? ['qwertzuiopü', 'asdfghjklöä', 'yxcvbnm'] : ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  const r = (k) => `<div class="krow">${[...k].map((c) => `<i>${c}</i>`).join('')}</div>`;
  return `<div class="kbd" data-system>${r(rows[0])}${r(rows[1])}<div class="krow"><i class="wide">⇧</i>${[...rows[2]].map((c) => `<i>${c}</i>`).join('')}<i class="wide">⌫</i></div><div class="krow"><i class="wide2">123</i><i class="space">${s.lang === 'de' ? 'Leerzeichen' : 'space'}</i><i class="wide2">⏎</i></div></div>`;
};

const addSheet = (s, o) => {
  const sugg = suggestions.map((x) => `<button class="srow" data-tap><span class="emo">${x.emoji}</span><span class="nm"><b>${esc(x[s.lang])}</b><small>${t(s, x.kind)} · ${esc(storeName(s, x.store))}</small></span>${ic('add', 'icon')}</button>`).join('');
  return `<div class="scrim"></div><div class="sheet add" data-sheet>${grab}<div class="sheetin">
    <div class="afield"><span class="face"><span class="typed">${esc(typed[s.lang])}<i class="caret"></i></span>${ic('close', 'icon clr')}</span></div>
    <div class="sgroup">${sugg}</div><p class="ahint">${t(s, 'addSheetHint')}</p></div></div>${keyboard(s)}`;
};

// ---- tick question ----

const tickAsk = (s) => sheet(`<p class="ask">${t(s, 'shopAskTitle')}</p><div class="askbtns"><button class="btn primary" data-tap><span class="face">${t(s, 'shopAskYes')}</span></button><button class="btn" data-tap><span class="face">${t(s, 'shopAskNo')}</span></button></div>
  <div class="mistake"><span>${t(s, 'shopAskMistake')}</span><button class="btn text" data-tap><span class="face">${t(s, 'shopAskTakeBack')}</span></button></div>`, 'ask');

// ---- More page (the real More tab's rows), or, for an option whose menu holds every place, that menu at its end ----

const holdsAll = (o) => morePageDests(o).length === 0 && !['float', 'fab', 'split', 'textTabs', 'docked'].includes(o.nav);
export const screenName = (o) => (holdsAll(o) ? { en: 'Menu, scrolled to its end', de: 'Menü, ans Ende gescrollt' } : { en: 'More', de: 'Mehr' });

const morePage = (s, o) => {
  const tabsNav = ['float', 'docked', 'fab', 'textTabs', 'split'].includes(o.nav);
  const head = tabsNav
    ? `<header class="pagebar" data-chrome="top"><h1>${t(s, 'tabMore')}</h1></header>`
    : `<header class="pagebar back" data-chrome="top">${iconBtn('arrow_back', 'Back')}<h1>${t(s, 'tabMore')}</h1></header>`;
  const body = `<div class="content page">${destGroups(s, morePageDests(o)).replaceAll('class="mgroup"', 'class="mgroup card"')}<p class="version">${t(s, 'appVersion', { version: '0.1.0' })}</p></div>`;
  return `${head}<div class="scroll page" data-scroll>${body}</div>${tabsNav ? bottom(s, o, { active: o.nav === 'docked' || o.nav === 'fab' ? 3 : 2, noAdd: true }) : ''}`;
};
const screenFrame = (s, o) => (holdsAll(o) ? `<div class="scroll" data-scroll>${listBody(s, o)}</div>${header(s, o)}${bottom(s, o)}${navOpen(s, o)}` : morePage(s, o));

// ---- empty ----

const emptyBody = (s, o) => `<div class="content"><div class="empty" data-empty><i class="motif"></i><p>${t(s, 'emptyList')}</p>${o.nav === 'fab' || o.nav === 'split' ? `<button class="btn primary" data-tap><span class="face">${ic('add', 'icon small')}${t(s, 'addItem')}</span></button>` : ''}</div>${recently(s)}</div>`;

// ---- frame ----

export const frame = (s0, o, kind) => {
  // RD8 shows a tick inside the Supermarket tab: in the shop, one store.
  const s = o.nav === 'storeTabs' && kind === 'tick' ? { ...s0, storeTab: 'super' } : s0;
  const scroll = (body) => `<div class="scroll" data-scroll>${body}</div>`;
  let inner;
  if (kind === 'list') inner = `${scroll(listBody(s, o))}${header(s, o)}${bottom(s, o)}`;
  else if (kind === 'tick') inner = `${scroll(listBody(s, o, { tickId: o.nav === 'storeTabs' ? 'milk' : 'tomatoes' }))}${header(s, o)}${bottom(s, o)}${tickAsk(s)}`;
  else if (kind === 'nav') inner = `${scroll(listBody(s, o))}${header(s, o)}${bottom(s, o)}${navOpen(s, o)}`;
  else if (kind === 'add') inner = `${scroll(listBody(s, o))}${header(s, o)}${addSheet(s, o)}`;
  else if (kind === 'screen') inner = screenFrame(s, o);
  else if (kind === 'empty') inner = `${scroll(emptyBody(s, o))}${header(s, o)}${bottom(s, o)}`;
  else throw new Error(`frame ${kind}`);
  const r = o.r;
  const style = `--r-xs:${r.xs}px;--r-sm:${r.sm}px;--r-md:${r.md}px;--r-lg:${r.lg}px;--r-xl:${r.xl}px;--ts:${s.ts}`;
  return `<div class="phone o-${o.id} th-${s.theme} nav-${o.nav} tick-${o.tick} price-${o.price}${o.priceQuiet ? ' price-quiet' : ''} stores-${o.stores} f-${kind}${s.ts >= 2 ? ' ts-large' : ''}" style="${style}" data-option="${o.id}" data-frame="${kind}"${kind === 'screen' && holdsAll(o) ? ' data-menu-end' : ''} lang="${s.lang}">
    ${statusBar()}<div class="screen">${inner}</div><div class="homeind" data-system><i></i></div></div>`;
};
