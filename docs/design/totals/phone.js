// The list screen as the app draws it with list-declutter (job 229) and the ST3 block (job 237): the see-through
// top bar, store dividers, category heads, rows with their price chip, the block, „Recently used“, the trip strip,
// the add field and the tab bar. Geometry from the release web build (tools/capture-today.mjs).
import { esc, ic } from './blocks.js';
import { catOrder, groupName, lineCents, money, openItems, stores, summary, w } from './model.js';

const qtyLabel = (item) => (item.qty === '' ? '' : /^\d+$/.test(item.qty) ? `${item.qty}×` : item.qty);

const row = (item, s, env, last) => {
  const priced = s.priced.includes(item.id);
  const est = item.price.per === 'kg';
  const chip = priced ? esc(est ? w(env.lang, 'moneyEstimate', { amount: money(env.lang, lineCents(item)) }) : money(env.lang, lineCents(item))) : `${ic('add', 'icon tiny')}${esc(w(env.lang, 'priceAdd'))}`;
  return `<div class="item${last ? ' last' : ''}${s.target === item.id ? ' target' : ''}" data-row="${item.id}" data-act="tick:${item.id}">
    <span class="emo">${item.emoji}</span>
    <span class="nm">${qtyLabel(item) ? `<b class="q">${esc(qtyLabel(item))}</b> ` : ''}<b>${esc(item[env.lang])}</b></span>
    <button class="chip${priced ? ' set' : ''}${s.target === item.id ? ' open' : ''}" data-act="price:${item.id}" data-chip><span>${chip}</span></button></div>`;
};

const storeDivider = (store, n, s, opt, env) => {
  const g = summary(s).groups.find((x) => x.store === store);
  const extra = opt.divider && g ? opt.divider(g, s, env) : '';
  return `<div class="sdivider" data-divider="${store ?? 'none'}"><span class="dname">${esc(groupName(env.lang, store))}</span><i class="dline"></i>
    <span class="dtail"><span class="dcount"><b>${n}</b> ${esc(w(env.lang, 'itemsWord', { count: n }))}</span>${extra}${ic('expand_more', 'icon dchev')}</span></div>`;
};

const listBody = (s, opt, env) => {
  const open = openItems(s);
  return [...stores.map((x) => x.id), null].map((store) => {
    const mine = open.filter((i) => i.store === store);
    if (!mine.length) return '';
    const cats = catOrder.filter((c) => mine.some((i) => i.cat === c));
    return `<section class="store" data-store="${store ?? 'none'}">${storeDivider(store, mine.length, s, opt, env)}${cats.map((c) => {
      const rows = mine.filter((i) => i.cat === c);
      return `<div class="cat">${esc(w(env.lang, c))}</div>${rows.map((i, k) => row(i, s, env, k === rows.length - 1)).join('')}`;
    }).join('')}</section>`;
  }).join('');
};

// show: a store whose divider the list is scrolled to, instead of its end.
export const phone = (s, opt, env, { live = false, show = '' } = {}) => {
  const cls = `phone th-${env.theme} ${env.device} ts${env.ts}`;
  const status = `<div class="status"><span>${env.device === 'android' ? '9:41' : '21:46'}</span><i class="sig"></i></div>`;
  const bar = opt.bar ? opt.bar(s, env) : '';
  const sheet = opt.sheet ? opt.sheet(s, env) : '';
  const trip = s.trip ? `<div class="trip" data-trip><i class="dot"></i><b>0:10</b><span>${esc(w(env.lang, 'shopRunning'))}</span><span class="pause"><i></i><i></i></span><span class="end"><span>${esc(w(env.lang, 'shopEnd'))}</span></span></div>` : '';
  return `<div class="${cls}" data-opt="${opt.id}"${live ? ' data-live' : ''}${show ? ` data-show="${show}"` : ''}>${status}
    <div class="screen">
      <div class="scroll" data-scroll><div class="content" data-content>
        <div class="topgap" data-topgap></div>
        ${listBody(s, opt, env)}
        ${opt.block(s, env)}
        <div class="used" data-used><span>${esc(w(env.lang, 'recentlyUsed'))}</span>${ic('expand_more')}</div>
        <div class="endpad" data-endpad></div>
      </div></div>
      <div class="topbar" data-topbar>
        <button class="hexbtn switcher"><span><span class="two"><small>${env.lang === 'de' ? 'Familie Brandt' : 'Brandt family'}</small><b>${env.lang === 'de' ? 'Einkaufsliste' : 'Shopping list'}</b></span>${ic('expand_more', 'icon updown')}</span></button>
        ${bar}
        <button class="hexbtn edit"><span>${esc(w(env.lang, 'listEdit'))}</span></button>
      </div>
      <div class="bottom" data-bottom>${trip}
        <div class="addfield"><span>${esc(w(env.lang, 'addFieldHint'))}</span></div>
        <div class="tabs"><span class="tab on">${ic('shopping_cart_outlined')}${esc(w(env.lang, 'tabList'))}</span><span class="tab">${ic('history')}${esc(w(env.lang, 'tabHistory'))}</span><span class="tab">${ic('menu')}${esc(w(env.lang, 'tabMore'))}</span></div>
      </div>
      ${sheet ? `<div class="scrim" data-act="sheet"></div><div class="sheet" data-sheet><div class="grab" data-act="sheet"><i></i></div><div class="sheetbody">${sheet}</div></div>` : ''}
    </div>
    ${env.device === 'ios' ? '<div class="homeind"><i></i></div>' : ''}</div>`;
};

// After layout: the list's top inset is the top bar's height, its end clears the bottom band, and it is scrolled to
// the end (where the block sits) unless a target row asks to be shown.
export const settle = (root) => {
  for (const ph of root.querySelectorAll('.phone')) {
    const top = ph.querySelector('[data-topbar]').offsetHeight;
    ph.querySelector('[data-topgap]').style.height = `${top}px`;
    const screen = ph.querySelector('.screen');
    ph.querySelector('[data-endpad]').style.height = `${screen.offsetHeight - ph.querySelector('[data-bottom]').offsetTop + 24}px`;
    const sc = ph.querySelector('[data-scroll]');
    const target = ph.querySelector('.item.target') ?? (ph.dataset.show ? ph.querySelector(`[data-divider="${ph.dataset.show}"]`) : null);
    if (target) sc.scrollTop = target.offsetTop - top - (target.matches('.item') ? 60 : 8);
    else if (!ph.dataset.keepScroll) sc.scrollTop = sc.scrollHeight;
  }
};
