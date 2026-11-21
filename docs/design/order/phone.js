// The list screen as the release web build draws it (list-declutter): the see-through top bar, store dividers,
// category heads, rows with their price chip, the floating add field and tab bar, the trip strip, and the edit sheet.
// Geometry from tools/capture-today.mjs (io/real/*.json); verify.mjs checks the Today rows against it.
import { icons } from './icons.js';
import { byId, catKey, catOf, layout, orderOf, sectionIds, stores } from './model.js';
import { arb, proposed } from './strings.js';

export const esc = (x) => String(x).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
export const ic = (name, cls = 'icon') => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name]}"/></svg>`;

// ARB text with the two ICU forms the round uses: {name} and {count, plural, =1{…} other{…}}.
export const w = (lang, key, params = {}) => {
  const src = arb[lang][key] ?? proposed[lang][key];
  if (src === undefined) throw new Error(`no string ${key}`);
  const plural = src.replace(/\{(\w+), plural, =1\{([^}]*)\} other\{([^}]*(?:\{\w+\}[^}]*)*)\}\}/g, (_, k, one, other) => (Number(params[k]) === 1 ? one : other));
  return plural.replace(/\{(\w+)\}/g, (_, k) => params[k] ?? `{${k}}`);
};
// A new word on screen: marked so the page shows which words the app does not have yet.
const nw = (lang, key, params) => `<span class="new" data-proposed="${key}">${esc(w(lang, key, params))}</span>`;

const storeName = (lang, store) => (store === 'none' ? w(lang, 'noStore') : stores.find((x) => x.id === store).name);
const qtyLabel = (item) => (item.qty === '' ? '' : /^\d+$/.test(item.qty) ? `${item.qty}×` : item.qty);
const cell = (item) => (item.emoji ? `<span class="emo">${item.emoji}</span>` : '<span class="emo"><i class="hexcell"></i></span>');

const row = (s, opt, id, last) => {
  const item = byId[id];
  const mark = s.fresh === id || s.moved === id ? ' target' : '';
  const tail = s.sortMode
    ? `<span class="handle" data-handle="${id}" aria-label="${esc(w(s.lang, 'dragCategory', { name: item[s.lang] }))}">${ic('drag_handle')}</span>`
    : `<button class="chip" data-chip tabindex="-1"><span>${ic('add', 'icon tiny')}${esc(w(s.lang, 'priceAdd'))}</span></button>`;
  return `<div class="item${last ? ' last' : ''}${mark}${s.lifted === id ? ' lifted' : ''}" data-row="${id}" data-act="tick:${id}" data-hold="${id}">
    ${cell(item)}<span class="nm">${qtyLabel(item) ? `<b class="q">${esc(qtyLabel(item))}</b> ` : ''}<b>${esc(item[s.lang])}</b></span>${tail}</div>`;
};

const divider = (s, store, n) => `<div class="sdivider" data-divider="${store}"><span class="dname">${esc(storeName(s.lang, store))}</span><i class="dline"></i>
  <span class="dtail"><span class="dcount"><b>${n}</b>${s.ts >= 200 ? '' : ` ${esc(w(s.lang, 'itemsWord', { count: n }))}`}</span>${ic('expand_more', 'icon dchev')}</span></div>`;

// A section's rows with what the option puts between them: category heads (`heads`), a quiet gap where the category
// changes (`gaps`), or nothing.
const section = (s, opt, store) => {
  const ids = orderOf(s, opt.kind, store);
  if (!ids.length) return '';
  const heads = opt.heads(s);
  const gaps = opt.gaps?.(s) ?? false;
  const parts = [];
  ids.forEach((id, k) => {
    const cat = catOf(s, id);
    const prev = k ? catOf(s, ids[k - 1]) : null;
    if (heads && cat !== prev) parts.push(`<div class="cat" data-cat="${cat}">${esc(w(s.lang, catKey[cat]))}</div>`);
    else if (gaps && k && cat !== prev) parts.push('<i class="gap" data-gap></i>');
    const next = ids[k + 1];
    const last = !next || (heads && catOf(s, next) !== cat) || (gaps && catOf(s, next) !== cat);
    parts.push(row(s, opt, id, last));
  });
  return `<section class="store" data-store="${store}">${divider(s, store, ids.length)}${parts.join('')}</section>`;
};

const topbar = (s, opt) => {
  const switcher = `<button class="hexbtn switcher" tabindex="-1"><span><span class="two"><small>${s.lang === 'de' ? 'Familie Brandt' : 'Brandt family'}</small><b>${s.lang === 'de' ? 'Einkaufsliste' : 'Shopping list'}</b></span>${ic('unfold_more', 'icon updown')}</span></button>`;
  if (s.sortMode) return `${switcher}<button class="hexbtn honey" data-act="sortMode"><span>${esc(w(s.lang, 'done'))}</span></button>`;
  const sort = opt.sortButton ? `<button class="hexbtn iconbtn" data-act="sortMode" aria-label="${esc(w(s.lang, 'sortItems'))}" data-proposed="sortItems"><span>${ic('swap_vert')}</span></button>` : '';
  return `${switcher}${sort}<button class="hexbtn edit" data-act="${opt.settings ? 'screen:stores' : ''}"><span>${esc(w(s.lang, 'listEdit'))}</span></button>`;
};

const chipBtn = (label, act, extra = '') => `<button class="schip${extra}" data-act="${act}"><span>${label}${ic('arrow_drop_down', 'icon drop')}</span></button>`;

// The edit sheet (edit_item_sheet.dart): name, brand, quantity with its stepper, properties, the store and category
// chips, „Ich bringe das“, Cancel and Done. The options swap the category chip: IO4 a „Next to …“ chip, IO5 Move up and
// Move down keys.
const editSheet = (s, opt) => {
  const id = s.sheet.id;
  const item = byId[id];
  const store = item.store ?? 'none';
  const lang = s.lang;
  let chips = chipBtn(esc(storeName(lang, store)), '');
  if (opt.fix === 'nextTo') {
    const shown = orderOf(s, opt.kind, store);
    const before = shown[shown.indexOf(id) - 1];
    chips += chipBtn(before ? nw(lang, 'placeNextTo', { name: byId[before][lang] }) : nw(lang, 'placeFirst'), 'menu:place', ' place');
  } else {
    chips += chipBtn(esc(w(lang, catKey[catOf(s, id)])), 'menu:cat');
  }
  const steps = opt.fix === 'step' ? `<div class="steps"><button class="hexbtn small" data-act="step:up"><span>${ic('keyboard_arrow_up')}${esc(w(lang, 'listMoveUp'))}</span></button><button class="hexbtn small" data-act="step:down"><span>${ic('keyboard_arrow_down')}${esc(w(lang, 'listMoveDown'))}</span></button></div>` : '';
  let menu = '';
  if (s.sheet.menu === 'cat') {
    const lay = layout[store].filter((c) => catKey[c]);
    menu = `<div class="menu" data-menu>${lay.map((c) => `<button class="mi${c === catOf(s, id) ? ' on' : ''}" data-act="setCat:${c}">${esc(w(lang, catKey[c]))}</button>`).join('')}</div>`;
  }
  if (s.sheet.menu === 'place') {
    const shown = orderOf(s, opt.kind, store).filter((x) => x !== id);
    const before = orderOf(s, opt.kind, store)[orderOf(s, opt.kind, store).indexOf(id) - 1] ?? 'first';
    menu = `<div class="menu" data-menu><button class="mi${before === 'first' ? ' on' : ''}" data-act="nextTo:first">${nw(lang, 'placeFirst')}</button>${shown.map((x) => `<button class="mi item-mi${x === before ? ' on' : ''}" data-act="nextTo:${x}">${cell(byId[x])}<span>${esc(byId[x][lang])}</span></button>`).join('')}</div>`;
  }
  return `<div class="scrim" data-act="done"></div><div class="esheet" data-sheet><div class="grab"><i></i></div>
    <label>${esc(w(lang, 'fieldName'))}</label><div class="field"><span>${esc(item[lang])}</span></div>
    <label>${esc(w(lang, 'fieldBrand'))}</label><div class="field muted"><span>${esc(w(lang, 'brandNone'))}</span></div>
    <label>${esc(w(lang, 'itemQuantity'))}</label><div class="qrow"><div class="field"><span>${esc(item.qty)}</span></div><span class="hexkey">${ic('remove')}</span><span class="hexkey">${ic('add')}</span></div>
    <label>${esc(w(lang, 'fieldProperties'))}</label><div class="field muted"><span>${esc(w(lang, 'propertiesExample'))}</span></div>
    <div class="chips">${chips}</div>${steps}
    <div class="claim"><i class="hexcell big"></i><span>${esc(w(lang, 'claimMine'))}</span></div>
    <div class="actions"><button class="link" data-act="done">${esc(w(lang, 'cancel'))}</button><button class="hexbtn honey" data-act="done"><span>${esc(w(lang, 'done'))}</span></button></div>
    ${menu}</div>`;
};

// IO5's stores screen (List → Edit, stores_screen.dart) with the new switch on top.
const storesScreen = (s) => `<div class="stores-screen" data-screen="stores"><div class="sbar"><button class="back" data-act="screen:list" aria-label="${s.lang === 'de' ? 'Zurück' : 'Back'}">${ic('arrow_back')}</button><b>${esc(w(s.lang, 'storesTitle'))}</b></div>
  <button class="switchrow" data-act="showCats" role="switch" aria-checked="${s.showCats}"><span>${nw(s.lang, 'showCategories')}</span><i class="switch${s.showCats ? ' on' : ''}"><i></i></i></button>
  <p class="shint">${esc(w(s.lang, 'storesHint'))}</p>
  ${stores.map((x) => `<div class="srow"><span class="hexbtn"><span>${esc(x.name)}</span></span>${ic('delete_outline', 'icon muted')}${ic('drag_handle', 'icon muted')}</div>`).join('')}
  <div class="srow none"><span class="hexbtn sunk"><span>${esc(w(s.lang, 'noStore'))}</span></span>${ic('chevron_right', 'icon muted')}</div><p class="shint small">${esc(w(s.lang, 'noStoreRowHint'))}</p>
  <div class="sadd"><span class="hexbtn honey"><span>${ic('add')}${esc(w(s.lang, 'storeAdd'))}</span></span></div></div>`;

// env: theme, ts (100, 200, 310), device. show: a section or row to scroll to (else the top).
export const phone = (s, opt, env, { live = false, show = '' } = {}) => {
  const st = { ...s, ts: env.ts };
  const cls = `phone th-${env.theme} ${env.device} ts${env.ts}${s.sortMode ? ' sorting' : ''}`;
  const status = `<div class="status"><span>${env.device === 'android' ? '9:41' : '21:46'}</span><i class="sig"></i></div>`;
  const trip = s.trip ? `<div class="trip" data-trip><i class="dot"></i><b>0:${String(4 + s.trip.ticked.length).padStart(2, '0')}</b><span>${esc(w(s.lang, 'shopRunning'))}</span><span class="pause"><i></i><i></i></span><button class="end" data-act="endTrip"><span>${esc(w(s.lang, 'shopEnd'))}</span></button></div>` : '';
  const body = sectionIds.map((store) => section(st, opt, store)).join('');
  return `<div class="${cls}" data-opt="${opt.id}"${s.sheet ? ` data-sheet-for="${s.sheet.id}"` : ''}${live ? ' data-live' : ''}${show ? ` data-show="${show}"` : ''}>${status}
    <div class="screen">
      <div class="scroll" data-scroll><div class="content" data-content>
        <div class="topgap" data-topgap></div>${body}
        <div class="used" data-used><span>${esc(w(s.lang, 'recentlyUsed'))}</span>${ic('expand_more')}</div>
        <div class="endpad" data-endpad></div>
      </div></div>
      <div class="topbar" data-topbar>${topbar(st, opt)}</div>
      <div class="bottom" data-bottom>${trip}
        <div class="addfield" data-addfield><span>${esc(w(s.lang, 'addFieldHint'))}</span></div>
        <div class="tabs"><span class="tab on">${ic('shopping_cart_outlined')}<span>${esc(w(s.lang, 'tabList'))}</span></span><span class="tab">${ic('history')}<span>${esc(w(s.lang, 'tabHistory'))}</span></span><span class="tab">${ic('menu')}<span>${esc(w(s.lang, 'tabMore'))}</span></span></div>
      </div>
      ${s.sheet?.kind === 'edit' ? editSheet(st, opt) : ''}
      ${s.screen === 'stores' ? storesScreen(st) : ''}
    </div>
    </div>`;
};

// After layout: the list's top inset is the top bar's height and its end clears the bottom band. It is scrolled so
// that `show` (a section or a row) sits under the bar, or, with the edit sheet open, so the edited row sits just above
// the sheet; else it stays at the top.
export const settle = (root) => {
  for (const ph of root.querySelectorAll('.phone')) {
    const top = ph.querySelector('[data-topbar]').offsetHeight;
    ph.querySelector('[data-topgap]').style.height = `${top}px`;
    const screen = ph.querySelector('.screen');
    ph.querySelector('[data-endpad]').style.height = `${screen.offsetHeight - ph.querySelector('[data-bottom]').offsetTop + 24}px`;
    const sc = ph.querySelector('[data-scroll]');
    const sheet = ph.querySelector('[data-sheet]');
    const show = ph.dataset.show;
    if (sheet) {
      const target = ph.querySelector(`[data-row="${ph.dataset.sheetFor}"]`);
      if (target) sc.scrollTop = target.offsetTop + target.offsetHeight - sheet.offsetTop + 8;
      const menu = sheet.querySelector('[data-menu]');
      const on = menu?.querySelector('.on');
      if (on) menu.scrollTop = on.offsetTop - menu.clientHeight / 2 + on.offsetHeight / 2;
    } else if (show) {
      const el = ph.querySelector(`[data-divider="${show}"]`) ?? ph.querySelector(`[data-row="${show}"]`);
      if (el) sc.scrollTop = el.offsetTop - top - (el.matches('.item') ? 120 : 8);
    } else if (!ph.dataset.keepScroll) {
      sc.scrollTop = 0;
    }
  }
};
