// The list screen as the release web build draws it, with job 350's hide-categories (no category heads) and job 348's
// TE1 total block: the see-through top bar, store dividers, rows with the price chip or the price, the block, the
// option's Recently used section, the floating add field and the tab bar. Geometry from job 347's replica
// (docs/design/order, checked against the release build there).
import { icons } from './icons.js';
import { byId, money, openIn, stores, summary } from './model.js';
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
export const nw = (lang, key, params) => `<span class="new" data-proposed="${key}">${esc(w(lang, key, params))}</span>`;

export const qtyLabel = (item) => (item.qty === '' ? '' : /^\d+$/.test(item.qty) ? `${item.qty}×` : item.qty);
export const cell = (item) => (item.emoji ? `<span class="emo">${item.emoji}</span>` : '<span class="emo"><i class="hexcell"></i></span>');
export const nameHtml = (s, item) => `${qtyLabel(item) ? `<b class="q">${esc(qtyLabel(item))}</b> ` : ''}<b>${esc(item[s.lang])}</b>`;
const chip = (s, item) => (item.price === null
  ? `<button class="chip" data-chip tabindex="-1"><span>${ic('add', 'icon tiny')}${esc(w(s.lang, 'priceAdd'))}</span></button>`
  : `<button class="chip set" data-chip tabindex="-1"><span>${esc(money(s.lang, item.price))}</span></button>`);

// A list row. In the list: data-row, a tap ticks. As a recent row: data-recent, a tap puts it back. `lead` goes before
// the emoji cell (RU4's check), `tail` replaces the price chip.
export const row = (s, id, { last = false, recent = false, cls = '', lead = '', tail } = {}) => {
  const item = byId[id];
  const hi = s.hi?.id === id && s.hi.where === (recent ? 'recent' : 'list') ? ' hi' : '';
  const anim = !recent && s.anim?.id === id ? ` checking${s.anim.phase === 'mid' ? ' mid' : ''}` : '';
  const attr = recent ? `data-recent="${id}" data-act="back:${id}"` : `data-row="${id}" data-act="tick:${id}"`;
  return `<div class="item${last ? ' last' : ''}${cls}${hi}${anim}" ${attr}>${lead}${cell(item)}<span class="nm">${nameHtml(s, item)}</span>${tail ?? chip(s, item)}</div>`;
};

const divider = (s, store, n) => `<div class="sdivider" data-divider="${store}"><span class="dname">${esc(stores.find((x) => x.id === store).name)}</span><i class="dline"></i>
  <span class="dtail"><span class="dcount"><b>${n}</b>${s.ts >= 200 ? '' : ` ${esc(w(s.lang, 'itemsWord', { count: n }))}`}</span>${ic('expand_more', 'icon dchev')}</span></div>`;

const section = (s, store) => {
  const ids = openIn(s, store);
  if (!ids.length) return '';
  return `<section class="store" data-store="${store}">${divider(s, store, ids.length)}${ids.map((id, k) => row(s, id, { last: k === ids.length - 1 })).join('')}</section>`;
};

// TE1 (job 343's block, job 348's app): only stores with a priced item get a line, the total once with one count of
// what has no price, no block when nothing has a price.
const amount = (lang, sum, cls) => {
  const num = money(lang, sum.cents);
  const full = sum.unpriced > 0 ? w(lang, 'moneyAtLeast', { amount: num }) : num;
  const at = full.indexOf(num);
  return `<span class="${cls}" data-amount>${at > 0 ? `<span class="marks">${esc(full.slice(0, at))}</span>` : ''}${esc(num)}${full.slice(at + num.length) ? `<span class="marks">${esc(full.slice(at + num.length))}</span>` : ''}</span>`;
};
const block = (s) => {
  const { lang } = s;
  const sm = summary(s);
  if (sm.total.priced === 0) return '';
  const lines = sm.groups.filter((g) => g.priced > 0);
  const many = lines.length > 1;
  const counts = sm.total.unpriced > 0 ? `<span class="tcounts" data-counts>${esc(w(lang, 'subtotalsUnpriced', { count: sm.total.unpriced }))}</span>` : '';
  return `<div class="blk" data-block>${many ? `<div class="bhead" role="heading">${esc(w(lang, 'tripTotal'))}</div>${lines.map((g) => `<div class="sline" data-line="${g.store}"><span class="sname"><b>${esc(g.name)}</b></span>${amount(lang, g, 'samt')}</div>`).join('')}<div class="bdiv"></div>` : ''}
    <div class="tline" data-total><div class="trow"><span class="ttitle${many ? ' big' : ''}">${esc(w(lang, many ? 'subtotalsTotal' : 'tripTotal'))}</span>${amount(lang, sm.total, 'tamt')}</div>${counts}</div></div>`;
};

const topbar = (s) => `<button class="hexbtn switcher" tabindex="-1"><span><span class="two"><small>${s.lang === 'de' ? 'Familie Brandt' : 'Brandt family'}</small><b>${s.lang === 'de' ? 'Einkaufsliste' : 'Shopping list'}</b></span>${ic('unfold_more', 'icon updown')}</span></button>
  <button class="hexbtn edit" tabindex="-1"><span>${esc(w(s.lang, 'listEdit'))}</span></button>`;

// env: theme, ts (100, 200, 310), device. show: 'recent' (the section under the bar) or a row id; else the top.
// still: a static frame (highlights hold instead of fading).
export const phone = (s, opt, env, { live = false, show = '', still = !live } = {}) => {
  const st = { ...s, ts: env.ts };
  const cls = `phone th-${env.theme} ${env.device} ts${env.ts}${still ? ' still' : ''}`;
  const status = `<div class="status"><span>${env.device === 'android' ? '9:41' : '21:46'}</span><i class="sig"></i></div>`;
  const body = stores.map((x) => section(st, x.id)).join('');
  return `<div class="${cls}" data-opt="${opt.id}"${live ? ' data-live' : ''}${show ? ` data-show="${show}"` : ''}>${status}
    <div class="screen">
      <div class="scroll" data-scroll><div class="content" data-content>
        <div class="topgap" data-topgap></div>${body}${block(st)}${opt.recent(st, env)}
        <div class="endpad" data-endpad></div>
      </div></div>
      <div class="topbar" data-topbar>${topbar(st)}</div>
      <div class="bottom" data-bottom>${opt.peek ? opt.peek(st, env) : ''}
        <div class="addfield" data-addfield><span>${esc(w(s.lang, 'addFieldHint'))}</span></div>
        <div class="tabs"><span class="tab on">${ic('shopping_cart_outlined')}<span>${esc(w(s.lang, 'tabList'))}</span></span><span class="tab">${ic('history')}<span>${esc(w(s.lang, 'tabHistory'))}</span></span><span class="tab">${ic('menu')}<span>${esc(w(s.lang, 'tabMore'))}</span></span></div>
      </div>
    </div>
    </div>`;
};

const rect = (el) => el.getBoundingClientRect();

// RU2's peek shows while the tray's header is behind it or below it.
export const updatePeek = (ph) => {
  const peek = ph.querySelector('[data-peek]');
  if (!peek) return;
  const head = ph.querySelector('[data-tray-head]');
  if (!head) {
    peek.hidden = true;
    return;
  }
  peek.hidden = false;
  const show = rect(head).top >= rect(peek).top - 0.5;
  peek.hidden = !show;
};

// After layout: the list's top inset is the top bar's height and its end clears the bottom band. Scrolled to `show`,
// else to the top (a live phone keeps its scroll).
export const settle = (root) => {
  for (const ph of root.querySelectorAll('.phone')) {
    const top = ph.querySelector('[data-topbar]').offsetHeight;
    ph.querySelector('[data-topgap]').style.height = `${top}px`;
    const screen = ph.querySelector('.screen');
    ph.querySelector('[data-endpad]').style.height = `${screen.offsetHeight - ph.querySelector('[data-bottom]').offsetTop - ph.querySelector('[data-addfield]').offsetTop + 24}px`;
    const sc = ph.querySelector('[data-scroll]');
    const show = ph.dataset.show;
    if (show) {
      const el = show === 'recent' ? ph.querySelector('[data-recent-section]') : ph.querySelector(`[data-row="${show}"]`) ?? ph.querySelector(`[data-recent="${show}"]`);
      if (el) sc.scrollTop = el.offsetTop - top - (show === 'recent' ? 8 : 120);
    } else if (!ph.dataset.keepScroll) {
      sc.scrollTop = 0;
    }
    updatePeek(ph);
  }
};

// What a person sees at the current scroll: whole rows between the top bar's bottom and the bottom band's top (the
// add field, or RU2's peek while it shows). toFirstRecent: px to scroll until the newest recent item is whole above the
// add field (null: none shows, as Today's folded tile). sectionPx: the whole section's height.
export const measure = (ph) => {
  const top = rect(ph.querySelector('[data-topbar]')).bottom;
  const add = rect(ph.querySelector('[data-addfield]')).top;
  const peek = ph.querySelector('[data-peek]:not([hidden])');
  const band = peek ? rect(peek).top : add;
  const whole = (el) => {
    const b = rect(el);
    return b.height > 0 && b.top >= top - 0.5 && b.bottom <= band + 0.5;
  };
  const recents = [...ph.querySelectorAll('[data-recent]')].filter((el) => rect(el).height > 0);
  const sec = ph.querySelector('[data-recent-section]');
  return {
    active: [...ph.querySelectorAll('[data-row]')].filter(whole).length,
    recent: recents.filter(whole).length,
    toFirstRecent: recents.length ? Math.max(0, Math.ceil(rect(recents[0]).bottom - add - 0.5)) : null,
    sectionPx: sec ? Math.round(rect(sec).height) : 0,
  };
};
