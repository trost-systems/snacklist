// The phone: list behind, the add sheet, the system keyboard. Every option is a record of layout hooks; the
// renderer never tests an option's id.
import { icons } from './icons.js';
import { categories, catName, curItem, lastTwo, nameOf, stores, storeName, suggestions, t } from './model.js';

const esc = (v) => String(v).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
export const ic = (n, cls = 'icon') => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[n]}"/></svg>`;

const name = (item, lang) => item[lang];
const qtyLabel = (item) => (item.qty === '' ? '' : /^\d+$/.test(item.qty) ? `${item.qty}×` : item.qty);

export const row = (item, env, { cur = false, fresh = false } = {}) => {
  const sub = [item.brand, item.details].filter(Boolean).join(', ');
  return `<div class="item${cur ? ' cur' : ''}${fresh ? ' fresh' : ''}" data-row="${item.id}" data-act="select:${item.id}">
    <span class="hx emo">${item.emoji}</span>
    <span class="nm">${qtyLabel(item) ? `<b style="color:var(--hl-color-brand)">${esc(qtyLabel(item))}</b> ` : ''}<b>${esc(name(item, env.lang))}</b>${sub ? `<span class="sub">${esc(sub)}</span>` : ''}</span>
    <span class="pill"><span>${ic('add')}${esc(t(env.lang).price)}</span></span>
  </div>`;
};

// Controls the options are made of. data-field marks what "every field visible" is checked on.
const qtyCtl = (item, env) => {
  const w = t(env.lang);
  return `<span class="qty" data-field="qty"><span>
    <button data-act="qty-" aria-label="${w.less}">${ic('remove')}</button>
    <input data-input="qty" value="${esc(item.qty === '' ? '' : item.qty)}" placeholder="1" aria-label="${w.qty}" inputmode="decimal">
    <button data-act="qty+" aria-label="${w.more}">${ic('add')}</button>
  </span></span>`;
};
const chip = (field, act, label, { open = false, grow = false, lead = '', arrow = true } = {}) =>
  `<button class="tact${open ? ' open' : ''}${grow ? ' grow' : ''}" data-field="${field}" data-act="${act}" aria-expanded="${open}"><span>${lead}${esc(label)}${arrow ? ic('arrow_drop_down') : ''}</span></button>`;
const storeChip = (item, s, env, o = {}) => chip('store', 'open:store', storeName(item.store, env.lang), { open: s.open === 'store', ...o });
const catChip = (item, s, env, o = {}) => chip('category', 'open:cat', catName(item.cat, env.lang), { open: s.open === 'cat', ...o });
const detailsChip = (item, s, env, o = {}) => {
  const w = t(env.lang);
  const v = [item.brand, item.details].filter(Boolean).join(', ');
  // Compact: only the icon until there is something to show; its name is the button's label.
  const label = v || (o.compact ? '' : w.details);
  return `<button class="tact${s.open === 'details' ? ' open' : ''}${v ? ' on' : ''}${o.grow ? ' grow' : ''}" data-field="details" data-act="open:details" aria-label="${esc(w.details)}"><span>${ic('notes')}${esc(label)}</span></button>`;
};
const field = (fieldName, value, placeholder, { focus = false, wide = false, small = true } = {}) =>
  `<label class="hexfield${focus ? ' focus' : ''}${small ? ' small' : ''}${wide ? ' wide' : ''}" data-field="${fieldName}"><span>
    ${focus && !value ? '<i class="caret"></i>' : ''}<input data-input="${fieldName}" value="${esc(value)}" placeholder="${esc(placeholder)}" aria-label="${esc(placeholder)}">
  </span></label>`;
const detailsField = (item, s, env, o = {}) => field('details', item.details, o.placeholder ?? t(env.lang).detailsEx, { focus: s.open === 'details', ...o });
const brandField = (item, s, env, o = {}) => field('brand', item.brand, t(env.lang).brand, o);
const storeOpts = (item, env, { line = false } = {}) => {
  const w = t(env.lang);
  const o = (id, label) => `<button class="opt${(item.store ?? 'none') === id ? ' on' : ''}" data-act="store:${id}"><span>${esc(label)}</span></button>`;
  return `<div class="line${line ? ' nowrap' : ''}" data-opts="store">${o('none', w.noStore)}${stores.map((x) => o(x.id, nameOf(x.name, env.lang))).join('')}<button class="opt" data-inert title="Job 313: type-ahead with chain suggestions"><span>${ic('add')}${esc(w.newStore)}</span></button></div>`;
};
const catOpts = (item, env, { line = false } = {}) =>
  `<div class="line${line ? ' nowrap' : ''}" data-opts="cat">${categories.map((c) => `<button class="opt${item.cat === c.id ? ' on' : ''}" data-act="cat:${c.id}"><span>${esc(c[env.lang])}</span></button>`).join('')}</div>`;
const picker = (item, s, env) => (s.open === 'store' ? storeOpts(item, env) : s.open === 'cat' ? catOpts(item, env) : '');
const input = (s, env) => {
  const focus = s.open !== 'details';
  return `<label class="hexfield${focus ? ' focus' : ''}" data-field="input"><span>${focus && !s.text ? '<i class="caret"></i>' : ''}
    <input data-input="text" value="${esc(s.text)}" placeholder="${esc(t(env.lang).hint)}" enterkeyhint="send">${ic('mic')}
  </span></label>`;
};
const suggRows = (s, env) =>
  suggestions(s, env.lang)
    .map((c, i) => `<button class="sugg${i === 0 ? ' first' : ''}" data-act="take:${i}"><span class="hx emo">${c.emoji}</span><span>${esc(c[env.lang])}</span>${i === 0 ? ic('keyboard_return') : ''}</button>`)
    .join('');
const typing = (s) => s.text.trim() !== '';

// The options. `body` is the sheet under its grabber; `card` (AS4) is the current row in the list behind.
export const options = {
  today: {
    id: 'today',
    today: true,
    body: (s, env) => {
      const w = t(env.lang);
      const item = curItem(s);
      if (!item) return input(s, env);
      return `<div class="today-head"><button class="xbtn" data-x aria-label="${w.close}"><span>${ic('close')}</span></button></div>
        <div class="addednote"><span>✓ ${esc(w.addedTo(name(item, env.lang), storeName(item.store, env.lang)))}</span><button class="undo" data-undo>${esc(w.undo)}</button></div>
        <div class="sbody" style="padding-bottom:0"><span class="flabel">${esc(w.qty)}</span>
        <div class="line nowrap" data-today-line>${field('qty', item.qty, '', { small: false }).replace('class="hexfield', 'style="flex:0 0 72px" class="hexfield')}
          <button class="tact" data-act="qty-"><span>${ic('remove')}</span></button><button class="tact" data-act="qty+"><span>${ic('add')}</span></button>
          ${storeChip(item, s, env)}${catChip(item, s, env)}
          ${field('brand', item.brand, w.brandNone).replace('class="hexfield', 'style="flex:0 0 150px" class="hexfield')}
          ${field('details', item.details, w.detailsEx).replace('class="hexfield', 'style="flex:0 0 190px" class="hexfield')}</div></div>
        <div class="room" style="height:57px"></div><div class="sbody">${input(s, env)}</div>`;
    },
  },
  AS1: {
    id: 'AS1',
    brand: false,
    body: (s, env) => {
      const item = curItem(s);
      if (typing(s) || !item) return `<div class="sbody">${suggRows(s, env)}${input(s, env)}</div>`;
      return `<div class="sbody">
        <div class="line tight" data-fieldline>${qtyCtl(item, env)}${storeChip(item, s, env, { arrow: false })}${catChip(item, s, env, { arrow: false })}${detailsChip(item, s, env, { compact: true })}</div>
        ${s.open === 'details' ? detailsField(item, s, env) : picker(item, s, env)}
        ${input(s, env)}</div>`;
    },
  },
  AS2: {
    id: 'AS2',
    brand: true,
    body: (s, env) => {
      const item = curItem(s);
      if (typing(s) || !item) return `<div class="sbody">${input(s, env)}${suggRows(s, env)}</div>`;
      const where = `${storeName(item.store, env.lang)} · ${catName(item.cat, env.lang)}`;
      return `<div class="sbody">${input(s, env)}
        <div class="line" data-fieldline>${qtyCtl(item, env)}<button class="tact grow${s.open === 'where' ? ' open' : ''}" data-field="store category" data-act="open:where"><span>${ic('storefront_outlined')}${esc(where)}${ic('arrow_drop_down')}</span></button></div>
        ${s.open === 'where' ? `${storeOpts(item, env, { line: true })}${catOpts(item, env, { line: true })}` : ''}
        <div class="grid2">${brandField(item, s, env)}${field('details', item.details, t(env.lang).details)}</div></div>`;
    },
  },
  AS3: {
    id: 'AS3',
    brand: true,
    body: (s, env) => {
      const item = curItem(s);
      if (typing(s) || !item) return `<div class="sbody">${suggRows(s, env)}${input(s, env)}</div>`;
      return `<div class="sbody"><div class="grid2" data-fieldline>
        ${qtyCtl(item, env).replace('class="qty"', 'class="qty" style="justify-self:start"')}${storeChip(item, s, env, { lead: ic('storefront_outlined') })}
        ${catChip(item, s, env, { lead: ic('category_outlined') })}${brandField(item, s, env)}
        ${detailsField(item, s, env, { wide: true, placeholder: t(env.lang).details })}</div>
        ${picker(item, s, env)}${input(s, env)}</div>`;
    },
  },
  AS4: {
    id: 'AS4',
    brand: false,
    body: (s, env) => `<div class="sbody">${suggRows(s, env)}${input(s, env)}</div>`,
    card: (item, s, env) => `<div class="rowcard" data-card data-act="noop">${row(item, env)}
      <div class="line tight" data-fieldline>${qtyCtl(item, env)}${storeChip(item, s, env, { arrow: false })}${catChip(item, s, env, { arrow: false })}${detailsChip(item, s, env, { compact: true })}</div>
      ${s.open === 'details' ? detailsField(item, s, env) : picker(item, s, env)}</div>`,
  },
  AS5: {
    id: 'AS5',
    brand: false,
    body: (s, env) => {
      const item = curItem(s);
      if (typing(s) || !item) return `<div class="sbody">${suggRows(s, env)}${input(s, env)}</div>`;
      return `<div class="sbody">
        <div class="line" data-fieldline style="flex-wrap:nowrap">${qtyCtl(item, env)}<div class="grow">${detailsField(item, s, env, { placeholder: t(env.lang).details })}</div></div>
        <div data-field="store">${storeOpts(item, env, { line: true })}</div>
        <div data-field="category">${catOpts(item, env, { line: true })}</div>
        ${input(s, env)}</div>`;
    },
  },
};

const keyboard = (env) => {
  const rows = env.lang === 'de' ? ['qwertzuiop', 'asdfghjkl', 'yxcvbnm'] : ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  const k = (c, cls = '') => `<span class="k ${cls}">${c}</span>`;
  const pred = env.lang === 'de' ? ['Ich', 'Die', 'Das'] : ['I', 'The', 'I’m'];
  return `<div class="kbd" aria-hidden="true"><div class="pred">${pred.map((p) => `<span>${p}</span>`).join('')}</div><div class="keys">
    <div class="row">${[...rows[0]].map((c) => k(c)).join('')}</div>
    <div class="row">${[...rows[1]].map((c) => k(c)).join('')}</div>
    <div class="row">${k('⇧', 'w')}${[...rows[2]].map((c) => k(c)).join('')}${k('⌫', 'w')}</div>
    <div class="row">${k('123', 'w')}${k(env.device === 'android' ? ',' : '☺', 'w')}${k('', 'space')}${k('⏎', 'go')}</div></div></div>`;
};

const closedList = (s, env) => {
  const w = t(env.lang);
  const sections = categories
    .map((c) => [c, s.items.filter((i) => i.cat === c.id)])
    .filter(([, items]) => items.length)
    .map(([c, items]) => `<div class="section">${esc(c[env.lang])}</div>${items.map((i) => row(i, env)).join('')}`)
    .join('');
  return `<div class="appbar" style="padding-left:12px"><button class="tact"><span>Familie Brandt${ic('expand_more')}</span></button><span style="flex:1"></span><button class="tact"><span>${esc(w.customise)}</span></button></div>
    <div class="list" data-list>${sections}</div>
    <div style="position:absolute;left:16px;right:16px;bottom:96px;z-index:6">${input({ ...s, text: '', open: 'none' }, env)}</div>
    <div class="tabs"><span class="tab on">${ic('shopping_cart_outlined')}${esc(w.list)}</span><span class="tab">${ic('menu')}${esc(w.more_)}</span></div>`;
};

// Today's list behind the sheet: everything already on it, then "Just added".
const todayBehind = (s, env) => {
  const old = s.items.filter((i) => i.old).slice(-2);
  const added = s.added.map((id) => s.items.find((i) => i.id === id));
  return `${old.map((i) => row(i, env)).join('')}${added.length ? `<div class="section" data-just-added>${esc(t(env.lang).justAdded)}</div>${added.map((i) => row(i, env)).join('')}` : ''}`;
};

export const phone = (s, opt, env, { live = false, gesture = null } = {}) => {
  const cls = `phone th-${env.theme} ${env.device} ts${env.ts}${s.sheet ? '' : ' closed'}`;
  const status = `<div class="status"><span>${env.device === 'android' ? '9:41' : '21:46'}</span><i class="sig"></i></div>`;
  if (!s.sheet) return `<div class="${cls}" data-opt="${opt.id}" data-state="closed"${live ? ' data-live' : ''}>${status}${closedList(s, env)}${env.device === 'ios' ? '<div class="homeind"><i></i></div>' : ''}</div>`;
  const behind = opt.today
    ? todayBehind(s, env)
    : lastTwo(s)
        .map((i) => (opt.card && i.id === s.cur ? opt.card(i, s, env) : row(i, env, { cur: i.id === s.cur && s.added.length > 1 && !typing(s) })))
        .join('');
  const g = gesture ? `<div class="gesture ${gesture}" data-gesture="${gesture}"><i class="dot"></i></div>` : '';
  return `<div class="${cls}" data-opt="${opt.id}" data-state="open"${live ? ' data-live' : ''}>${status}
    <div class="list behind" data-list data-act="dismiss">${behind}</div>
    <div class="sheet" data-sheet><div class="grab" data-grab aria-label="${esc(t(env.lang).close)}" role="button" data-act="dismiss"><i></i></div>${opt.body(s, env)}</div>
    ${keyboard(env)}${env.device === 'ios' ? '<div class="homeind"><i></i></div>' : ''}${g}</div>`;
};

// After layout: the list behind ends at the sheet's top edge; a gesture mark sits on the grabber or the list.
export const settle = (root) => {
  for (const ph of root.querySelectorAll('.phone')) {
    const sheet = ph.querySelector('[data-sheet]');
    if (!sheet) continue;
    ph.style.setProperty('--sheet-h', `${sheet.offsetHeight}px`);
    const g = ph.querySelector('[data-gesture]');
    if (!g) continue;
    const box = ph.getBoundingClientRect();
    const target = g.dataset.gesture === 'swipe' ? sheet.querySelector('[data-grab]') : ph.querySelector('.status');
    const r = target.getBoundingClientRect();
    const y = g.dataset.gesture === 'swipe' ? r.top - box.top - 12 : r.bottom - box.top + 60;
    Object.assign(g.style, { left: `${box.width / 2 - 22}px`, top: `${y}px` });
  }
};
