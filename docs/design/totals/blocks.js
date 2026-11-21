// Today's ST3 block and the five TE options. Each option is a record of hooks the phone calls: `block` (the end of
// the list), and optionally `divider` (extra on a store divider), `bar` (in the top bar) and `sheet`. The phone
// never tests an option's id.
import { icons } from './icons.js';
import { empty, floor, groupName, marked, money, summary, w, zero, firstUnpriced } from './model.js';

export const esc = (v) => String(v).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
export const ic = (n, cls = 'icon') => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[n]}"/></svg>`;

// summary_block.dart's _details: bought and open while a trip runs (or „all bought“), then how many lack a price.
const details = (lang, bought, open, { allBought, split = false, unpricedCount = true }) => {
  const part = (sum) => (empty(sum) ? money(lang, 0) : marked(lang, sum, { withFloor: false }));
  const shows = (sum) => !empty(sum) || !floor(sum);
  const unpriced = (bought?.unpriced ?? 0) + open.unpriced;
  const out = [];
  if (allBought) out.push(w(lang, 'subtotalsAllBought'));
  else if (bought && (split || !empty(bought) || floor(bought))) {
    if (shows(bought)) out.push(w(lang, 'subtotalsBought', { amount: part(bought) }));
    if (shows(open)) out.push(w(lang, 'subtotalsOpen', { amount: part(open) }));
  }
  if (unpricedCount && unpriced > 0) out.push(w(lang, 'subtotalsUnpriced', { count: unpriced }));
  return out;
};

// An amount with „at least“ and „≈“ in the muted marks style, the number itself in the line's style.
const amount = (lang, sum, cls) => {
  const full = marked(lang, sum);
  const num = money(lang, sum.cents);
  const at = full.indexOf(num);
  return `<span class="${cls}" data-amount>${at > 0 ? `<span class="marks">${esc(full.slice(0, at))}</span>` : ''}${esc(num)}${full.slice(at + num.length) ? `<span class="marks">${esc(full.slice(at + num.length))}</span>` : ''}</span>`;
};

const storeLine = (lang, g, { unpricedCount = true } = {}) => {
  const d = details(lang, g.bought, g.open, { allBought: g.allBought, unpricedCount });
  return `<div class="sline" data-line="${g.store ?? 'none'}" ${g.allBought ? '' : `data-act="jump:${g.store ?? 'none'}" role="button"`}>
    <span class="sname"><b>${esc(groupName(lang, g.store))}</b>${d.length ? `<span class="sdet">${g.allBought ? ic('check', 'icon tiny') : ''}${esc(d.join(' · '))}</span>` : ''}</span>
    ${empty(g.sum) ? '' : amount(lang, g.sum, 'samt')}</div>`;
};

const totalLine = (lang, sm, { title, counts, extra = '', act = '' }) => `<div class="tline"${act} data-total>
    <div class="trow"><span class="ttitle${sm.perStore ? ' big' : ''}">${esc(title)}</span>${empty(sm.total) ? '' : amount(lang, sm.total, 'tamt')}${extra}</div>
    ${counts.length ? `<span class="tcounts" data-counts>${esc(counts.join(' · '))}</span>` : ''}</div>`;

const head = (lang) => `<div class="bhead" role="heading">${esc(w(lang, 'tripTotal'))}</div>`;
const rule = '<div class="bdiv"></div>';
const block = (inner, cls = '') => `<div class="blk${cls}" data-block>${inner}</div>`;

// Today (main, job 237): every group with something open, its unpriced count, the total with both counts.
const todayBlock = (s, env) => {
  const { lang } = env;
  const sm = summary(s);
  if (!sm.groups.length) return '';
  const counts = sm.split
    ? details(lang, sm.bought, sm.open, { allBought: false, split: true })
    : [...(sm.total.priced > 0 ? [w(lang, 'subtotalsPriced', { count: sm.total.priced })] : []), ...(sm.total.unpriced > 0 ? [w(lang, 'subtotalsUnpriced', { count: sm.total.unpriced })] : [])];
  return block(`${sm.perStore ? `${head(lang)}${sm.groups.map((g) => storeLine(lang, g)).join('')}${rule}` : ''}
    ${totalLine(lang, sm, { title: w(lang, sm.perStore ? 'subtotalsTotal' : 'tripTotal'), counts })}`);
};

// The groups with a price in them (or bought on the trip with one): the receipt without empty lines.
const pricedGroups = (sm) => sm.groups.filter((g) => !empty(g.sum));
// The total's second line: bought and open while a trip runs, then one count of what has no price.
const totalCounts = (lang, sm, { unpricedCount = true } = {}) =>
  sm.split ? details(lang, sm.bought, sm.open, { allBought: false, split: true, unpricedCount }) : unpricedCount && sm.total.unpriced > 0 ? [w(lang, 'subtotalsUnpriced', { count: sm.total.unpriced })] : [];

// TE1 and TE5's sheet: only lines with a price, one count on the total, nothing when nothing has a price.
const pricedReceipt = (s, env, { always = false } = {}) => {
  const { lang } = env;
  const sm = summary(s);
  if (empty(sm.total) && !always) return '';
  const lines = pricedGroups(sm);
  const many = lines.length > 1;
  return `${many ? `${head(lang)}${lines.map((g) => storeLine(lang, g, { unpricedCount: false })).join('')}${rule}` : ''}
    ${totalLine(lang, { ...sm, perStore: many }, { title: w(lang, many ? 'subtotalsTotal' : 'tripTotal'), counts: totalCounts(lang, sm) })}`;
};

export const options = {
  today: { id: 'today', block: todayBlock },

  TE1: { id: 'TE1', block: (s, env) => { const r = pricedReceipt(s, env); return r ? block(r) : ''; } },

  // One line, folded by default; a tap opens TE1's store lines above it.
  TE2: {
    id: 'TE2',
    block: (s, env) => {
      const { lang } = env;
      const sm = summary(s);
      if (empty(sm.total)) return '';
      const lines = pricedGroups(sm);
      const chev = `<span class="chev${s.open ? ' up' : ''}">${ic('expand_more')}</span>`;
      const fold = lines.length > 1;
      const tl = totalLine(lang, { ...sm, perStore: false }, { title: w(lang, 'tripTotal'), counts: totalCounts(lang, sm), extra: fold ? chev : '', act: fold ? ' data-act="fold" role="button"' : '' });
      return block(`${s.open && fold ? `${lines.map((g) => storeLine(lang, g, { unpricedCount: false })).join('')}${rule}` : ''}${tl}`);
    },
  },

  // Each store's open sum on its divider; at the end one total line, only once something has a price.
  TE3: {
    id: 'TE3',
    divider: (g, s, env) => (empty(g.open) ? '' : `<span class="dsum" data-dsum>${esc(marked(env.lang, g.open))}</span>`),
    block: (s, env) => {
      const { lang } = env;
      const sm = summary(s);
      if (empty(sm.total)) return '';
      return block(totalLine(lang, { ...sm, perStore: false }, { title: w(lang, 'tripTotal'), counts: totalCounts(lang, sm) }));
    },
  },

  // The total and a link to the next item without a price; the store lines only once every item has one.
  TE4: {
    id: 'TE4',
    block: (s, env) => {
      const { lang } = env;
      const sm = summary(s);
      if (!sm.groups.length) return '';
      const next = firstUnpriced(s);
      const nudge = next ? `<button class="nudge" data-act="next:${next.id}" data-nudge>${esc(w(lang, 'subtotalsUnpriced', { count: sm.total.unpriced }))}${ic('expand_more', 'icon go')}</button>` : '';
      if (empty(sm.total)) return block(`<div class="tline one" data-total><div class="trow"><span class="ttitle">${esc(w(lang, 'tripTotal'))}</span>${nudge}</div></div>`);
      if (!next) return todayBlock(s, env);
      return block(`${totalLine(lang, { ...sm, perStore: false }, { title: w(lang, 'tripTotal'), counts: totalCounts(lang, sm, { unpricedCount: false }) })}${nudge}`);
    },
  },

  // No block: the amount sits in the top bar once something has a price; a tap opens TE1's receipt in a sheet.
  TE5: {
    id: 'TE5',
    block: () => '',
    bar: (s, env) => {
      const sm = summary(s);
      if (empty(sm.total)) return '';
      const t = sm.total;
      return `<button class="hexbtn amt" data-act="sheet" data-bar-amount><span>${esc(marked(env.lang, { ...t, unpriced: 0 }))}${floor(t) ? '<i class="plus">+</i>' : ''}</span></button>`;
    },
    sheet: (s, env) => (s.sheet ? pricedReceipt(s, env, { always: true }) : ''),
  },

  // Nothing at all: the zero the costs are measured against.
  none: { id: 'none', block: () => '' },
};
export const ids = ['TE1', 'TE2', 'TE3', 'TE4', 'TE5'];
export { zero };
