// One phone of round SC: the launch list (RD1, categories hidden, open-store-app on; no prices, totals, trips or log)
// with an option's card at the top. Sizes follow the release web build captured in sc/real/ (tools/capture-today.mjs):
// list from 72 px under the screen's top, 48 px rows (79 px at 310 %), 52 px store headers, 20 px after a section,
// the add field 11 px over the tab bar. The card takes HintCard's slot and look (app/lib/tips/hint_views.dart).
import { copy } from './copy.mjs';
import { icon } from './icons.mjs';
import { items, itemsOf, states, storeById } from './data.mjs';

export const devices = {
  iphone: { w: 390, h: 844, top: 47, bottom: 34, clock: '9:41' },
  android: { w: 360, h: 664, top: 24, bottom: 0, clock: '9:41' },
};

export const optionIds = ['SC1', 'SC2', 'SC3', 'SC4', 'SC5'];
// What each option shows when a second store finishes in the same session.
export const multi = { SC1: 'stack', SC2: 'latest', SC3: 'latest', SC4: 'latest', SC5: 'combined' };

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const qty = (q) => (q ? (/^\d+$/.test(q) ? `${q}×` : q) : '');

function row(i, lang, { last = false, recent = false } = {}) {
  const q = qty(i.qty);
  return `<div class="row${last ? ' last' : ''}${recent ? ' recent' : ''}" ${recent ? 'data-recent' : 'data-row'}><span class="emo">${i.icon}</span><span class="name">${q ? `<b class="q">${esc(q)}</b> ` : ''}${esc(i[lang])}</span></div>`;
}

function section(id, lang, a) {
  const s = storeById(id);
  const list = itemsOf(id);
  const n = list.length;
  return `<section class="sec" data-sec="${id}">
    <div class="head" data-head>
      <span class="sname">${esc(s.name)}</span><i class="rule"></i>
      <span class="cnt"><b>${n}</b><span class="word"> ${esc(a.items(n))}</span></span>
      <span class="chev">${icon('expandMore', 24)}</span>
      <span class="key" role="button" aria-label="${esc(a.storeAppOpen(s.app))}">${icon('openInNew', 22)}</span>
    </div>
    ${list.map((i, k) => row(i, lang, { last: k === n - 1 })).join('')}
  </section>`;
}

const btn = (label, kind, ic) => `<span class="btn ${kind}" role="button" data-action>${ic ? icon(ic, 20) : ''}<span class="bl">${esc(label)}</span></span>`;
const closeX = (a) => `<span class="x" role="button" aria-label="${esc(a.close)}" data-action>${icon('close', 20)}</span>`;
const lead = (name) => `<span class="lead">${icon(name, 22)}</span>`;

// The cards. `done` is the session's finished stores, oldest first; the last one just finished.
function cards(opt, done, open, lang, links, ts) {
  const a = copy[lang].app;
  const s = storeById(done.at(-1));
  const open1 = btn(a.storeAppOpen(s.app), 'primary', 'openInNew');
  const nextId = open[0];
  switch (opt) {
    case 'SC1': {
      const one = (st) => `<div class="card c1" data-card>${lead('store')}
        <div class="body wrap"><p class="t">${esc(a.done(st.name))}</p>${btn(a.storeAppOpen(st.app), 'primary', 'openInNew')}</div>${closeX(a)}</div>`;
      return [...done].reverse().map((id) => one(storeById(id))).join('');
    }
    case 'SC2':
      return `<div class="card c2" data-card>
        <div class="top">${lead('store')}<p class="t">${esc(a.done(s.name))}</p>${closeX(a)}</div>
        <div class="acts">${open1}${links === 'assumed' ? btn(a.card, 'secondary', 'card') : ''}</div></div>`;
    case 'SC3': {
      const bought = itemsOf(s.id);
      const names = bought.slice(0, 3).map((i) => i[lang]).join(', ');
      return `<div class="card c3" data-card>
        <div class="top">${lead('check')}<div class="tt"><p class="t">${esc(a.bought(bought.length, s.name))}</p>${ts >= 2 ? '' : `<p class="sub">${esc(names)}, ${esc(a.more(bought.length - 3))}</p>`}</div>${closeX(a)}</div>
        <div class="acts">${open1}${btn(a.undoTick, 'secondary', 'undo')}</div></div>`;
    }
    case 'SC4': {
      const next = nextId ? storeById(nextId) : null;
      return `<div class="card c4" data-card>${lead('store')}
        <div class="body wrap"><p class="t">${esc(a.done(s.name))}</p>${open1}</div>${closeX(a)}
        ${next ? `<div class="next" role="button" data-action>${icon('arrowDown', 20)}<span class="nl">${esc(a.next(next.name))}</span><span class="left">${esc(a.left(itemsOf(next.id).length))}</span></div>` : ''}</div>`;
    }
    case 'SC5': {
      if (done.length === 1) {
        return `<div class="card c5" data-card>
          <div class="top">${lead('check')}<p class="t">${esc(a.finished(s.name))}</p></div>
          <div class="acts">${open1}${btn(a.imDone, 'secondary')}</div></div>`;
      }
      const lines = [...done].reverse().map((id, k) => {
        const st = storeById(id);
        return `<div class="sline"><span class="sn">${esc(st.name)}</span>${btn(a.storeAppOpen(st.app), k === 0 ? 'primary' : 'secondary', 'openInNew')}</div>`;
      }).join('');
      return `<div class="card c5" data-card>
        <div class="top">${lead('check')}<p class="t">${esc(a.storesDone(done.length))}</p></div>
        ${lines}<div class="acts">${btn(a.imDone, 'secondary')}</div></div>`;
    }
    default:
      return '';
  }
}

// opt: 'before' (REWE's last item still open), 'today' (no card), SC1..SC5.
// frame: null, or what the page's storyboard shows after a tap: 'undone' (SC3), 'opened' (SC4).
export function phone({ opt, state = 'a', lang = 'en', theme = 'light', ts = 1, device = 'iphone', links = 'assumed', frame = null }) {
  const a = copy[lang].app;
  const d = devices[device];
  const st = states[state];
  let open = [...st.open];
  let done = [...st.done];
  let card = optionIds.includes(opt) ? cards(opt, done, open, lang, links, ts) : '';
  let snack = '';
  if (opt === 'before') {
    open = [done.at(-1), ...open];
    done = done.slice(0, -1);
  }
  if (frame === 'undone') {
    open = [done.at(-1), ...open];
    card = '';
  }
  if (frame === 'opened') {
    card = '';
    snack = `<div class="snack" data-snack><span>${esc(a.hidden(storeById(st.done.at(-1)).name))}</span><span class="sa" role="button">${esc(a.undo)}</span></div>`;
  }
  const lastOne = (id) => (opt === 'before' || frame === 'undone') && id === open[0];
  const sections = open.map((id) => {
    if (!lastOne(id)) return section(id, lang, a);
    // The store whose last item is (back) on the list: only that item is open.
    const s = storeById(id);
    const i = itemsOf(id).at(-1);
    return `<section class="sec" data-sec="${id}"><div class="head" data-head><span class="sname">${esc(s.name)}</span><i class="rule"></i><span class="cnt"><b>1</b><span class="word"> ${esc(a.items(1))}</span></span><span class="chev">${icon('expandMore', 24)}</span><span class="key" role="button">${icon('openInNew', 22)}</span></div>${row(i, lang, { last: true })}</section>`;
  }).join('');
  const recent = done.flatMap((id) => itemsOf(id)).reverse();
  const recentHtml = recent.length
    ? `<div class="recent-head" data-recent-head><span>${esc(a.recentlyUsed)}</span>${icon('expandLess', 24)}</div>${recent.map((i) => row(i, lang, { recent: true })).join('')}`
    : '';
  const empty = open.length ? '' : `<p class="empty" data-empty>${esc(a.emptyList)}</p>`;
  return `<div class="phone ${device} ${theme}" style="--ts:${ts};--w:${d.w}px;--h:${d.h}px;--top:${d.top}px;--bot:${Math.max(12, d.bottom)}px" data-opt="${opt}" data-state="${state}" data-ts="${ts}">
    <div class="status"><span>${d.clock}</span><i class="sig"></i></div>
    <div class="screen">
      <div class="scroll" data-scroll>
        ${card ? `<div class="slot" data-slot>${card}</div>` : ''}
        ${sections}${empty}${recentHtml}<div class="endpad"></div>
      </div>
      <div class="topbar" data-topbar>
        <span class="chip"><span class="cl"><small>${esc(a.household)}</small><b>${esc(a.list)}</b></span>${icon('unfold', 20)}</span>
        <span class="ebtn">${esc(a.edit)}</span>
      </div>
      ${snack}
      <div class="add" data-add><span>${esc(a.addFieldHint)}</span></div>
      <div class="tabs"><span class="tab on">${icon('cart', 22)}<span>${esc(a.tabList)}</span></span><span class="tab">${icon('menu', 22)}<span>${esc(a.tabMore)}</span></span></div>
      ${device === 'iphone' ? '<i class="homebar"></i>' : ''}
    </div>
  </div>`;
}

// Read in the browser, on a phone rendered at zoom 1. Rows: whole open item rows between the list's top (72 px under
// the status bar) and the add field. Extra: the card slot's height, which pushes every row down. Problems: text or a
// control outside the card, controls overlapping each other, a control under 44 px, the primary action not in view
// above the add field at scroll top, lines of text overlapping.
export function measure(ph) {
  const r = (el) => el.getBoundingClientRect();
  const screen = r(ph.querySelector('.screen'));
  const listTop = screen.top + 72;
  const addTop = r(ph.querySelector('[data-add]')).top;
  const snack = ph.querySelector('[data-snack]');
  const bandTop = snack ? Math.min(addTop, r(snack).top) : addTop;
  const rows = [...ph.querySelectorAll('[data-row]')].filter((el) => {
    const b = r(el);
    return b.top >= listTop - 0.5 && b.bottom <= bandTop + 0.5;
  }).length;
  const slot = ph.querySelector('[data-slot]');
  const problems = [];
  const cardsEls = [...ph.querySelectorAll('[data-card]')];
  for (const c of cardsEls) {
    const outer = r(c);
    const cb = { left: outer.left + 2, right: outer.right - 2, top: outer.top + 2, bottom: outer.bottom - 2 };
    for (const el of c.querySelectorAll('p, span, svg, .btn')) {
      const b = r(el);
      if (b.width === 0) continue;
      if (b.left < cb.left - 0.5 || b.right > cb.right + 0.5 || b.top < cb.top - 0.5 || b.bottom > cb.bottom + 0.5) problems.push(`outside card: "${(el.textContent || el.className.baseVal || el.className).trim().slice(0, 30)}"`);
    }
    for (const el of c.querySelectorAll('p, .bl, .nl, .left, .sn')) {
      if (el.scrollWidth > el.clientWidth + 1) problems.push(`clipped text: "${el.textContent.slice(0, 30)}"`);
    }
    const controls = [...c.querySelectorAll('[data-action]')];
    for (const el of controls) {
      const b = r(el);
      if (b.height < 44 - 0.5 || b.width < 44 - 0.5) problems.push(`small target ${Math.round(b.width)}x${Math.round(b.height)}: "${el.textContent.trim().slice(0, 20) || 'x'}"`);
    }
    for (let i = 0; i < controls.length; i += 1) {
      for (let j = i + 1; j < controls.length; j += 1) {
        const p = r(controls[i]);
        const q = r(controls[j]);
        if (p.left < q.right - 0.5 && q.left < p.right - 0.5 && p.top < q.bottom - 0.5 && q.top < p.bottom - 0.5) problems.push(`controls overlap: "${controls[i].textContent.trim().slice(0, 16)}" / "${controls[j].textContent.trim().slice(0, 16)}"`);
      }
    }
    const texts = [...c.querySelectorAll('p, .bl, .nl, .left, .sn')];
    const lines = texts.flatMap((el) => {
      const range = document.createRange();
      range.selectNodeContents(el);
      const own = el.getBoundingClientRect();
      return [...range.getClientRects()].filter((b) => b.bottom <= own.bottom + 0.5 && b.width > 0).map((b) => ({ el, b }));
    });
    for (let i = 0; i < lines.length; i += 1) {
      for (let j = i + 1; j < lines.length; j += 1) {
        const p = lines[i].b;
        const q = lines[j].b;
        if (lines[i].el === lines[j].el) continue;
        const v = Math.min(p.bottom, q.bottom) - Math.max(p.top, q.top);
        const h = Math.min(p.right, q.right) - Math.max(p.left, q.left);
        if (h > 1 && v > Math.min(p.height, q.height) / 4) problems.push(`text overlaps: "${lines[i].el.textContent.slice(0, 16)}" / "${lines[j].el.textContent.slice(0, 16)}"`);
      }
    }
  }
  const primary = cardsEls[0]?.querySelector('.btn.primary');
  const primaryInView = primary ? r(primary).bottom <= bandTop + 0.5 && r(primary).top >= listTop - 0.5 : null;
  if (primary && !primaryInView) problems.push('primary action not in view at scroll top');
  return {
    rows,
    extra: slot ? Math.round(r(slot).height) : 0,
    cards: cardsEls.length,
    primaryInView,
    problems,
    listTop: Math.round(listTop - screen.top),
    addTop: Math.round(addTop - screen.top),
  };
}

export const allItems = items;
