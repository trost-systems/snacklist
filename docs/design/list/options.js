// Today and RU1 to RU4 as records: the Recently used section at the list's end (`recent`), RU2's peek above the add
// field (`peek`), whether the section starts folded (`folded`), and how a tick leaves the list (`motion`).
import { byId } from './model.js';
import { cell, esc, ic, nameHtml, nw, qtyLabel, row, w } from './phone.js';

const chev = (open) => ic('expand_more', `icon chev${open ? ' up' : ''}`);
const count = (n) => `<span class="rucount" data-count>${n}</span>`;

export const options = {
  // Main today: a folded ExpansionTile, full width between 1 px rules; open, the list's own rows at 55 % without the
  // price chip (ru/real/en-100-expanded.png).
  today: {
    id: 'today',
    folded: true,
    motion: 'collapse',
    recent: (s) => {
      if (!s.recent.length) return '';
      const rows = s.folded ? '' : s.recent.map((id, k) => row(s, id, { recent: true, last: k === s.recent.length - 1, cls: ' faded', tail: '' })).join('');
      return `<section class="ru today${s.folded ? '' : ' open'}" data-recent-section><div class="used" data-act="fold" role="button" data-head><span>${esc(w(s.lang, 'recentlyUsed'))}</span>${chev(!s.folded)}</div>${rows}</section>`;
    },
  },

  RU1: {
    id: 'RU1',
    folded: false,
    remember: true,
    motion: 'collapse',
    recent: (s) => {
      if (!s.recent.length) return '';
      const rows = s.recent.map((id, k) => row(s, id, { recent: true, last: k === s.recent.length - 1, cls: ' faded', tail: '' })).join('');
      return `<section class="ru ru1" data-recent-section><div class="ruhead" data-act="fold" role="button" data-head><span class="htext"><span class="rutitle">${esc(w(s.lang, 'recentlyUsed'))}</span> ${count(s.recent.length)}</span>${chev(!s.folded)}</div>
        ${s.folded ? '' : `<p class="ruhint">${nw(s.lang, 'ruHintTap')}</p>${rows}`}</section>`;
    },
  },

  RU2: {
    id: 'RU2',
    folded: false,
    motion: 'fly',
    recent: (s) => {
      if (!s.recent.length) return '';
      const rows = s.recent.map((id) => {
        const item = byId[id];
        const hi = s.hi?.id === id && s.hi.where === 'recent' ? ' hi' : '';
        return `<div class="citem${hi}" data-recent="${id}" data-act="back:${id}">${cell(item)}<span class="nm">${nameHtml(s, item)}</span>${ic('undo', 'icon undo')}</div>`;
      }).join('');
      return `<section class="ru tray" data-recent-section><div class="trayhead" data-act="fold" role="button" data-head data-tray-head>${ic('check_circle', 'icon tcheck')}<span class="htext"><span class="rutitle">${nw(s.lang, 'ruTicked')}</span> ${count(s.recent.length)}</span>${chev(!s.folded)}</div>
        ${s.folded ? '' : `<div class="crows">${rows}</div>`}</section>`;
    },
    peek: (s) => {
      if (!s.recent.length) return '';
      const item = byId[s.recent[0]];
      const hi = s.hi?.id === item.id && s.hi.where === 'recent' ? ' hi' : '';
      return `<div class="peek" data-peek data-act="scrollTray" hidden><span class="plabel">${nw(s.lang, 'ruTicked')} · ${s.recent.length}</span>
        <button class="ppill${hi}" data-act="back:${item.id}" data-peek-pill="${item.id}">${cell(item)}<span class="pname">${esc(item[s.lang])}</span>${ic('undo', 'icon undo')}</button></div>`;
    },
  },

  RU3: {
    id: 'RU3',
    folded: false,
    motion: 'shrink',
    recent: (s) => {
      if (!s.recent.length) return '';
      const chips = s.recent.map((id) => {
        const item = byId[id];
        const hi = s.hi?.id === id && s.hi.where === 'recent' ? ' hi' : '';
        const q = qtyLabel(item) ? `<span class="q">${esc(qtyLabel(item))}</span> ` : '';
        return `<button class="rchip${hi}" data-recent="${id}" data-act="back:${id}">${cell(item)}<span>${q}${esc(item[s.lang])}</span></button>`;
      }).join('');
      return `<section class="ru ru3" data-recent-section><div class="ovl" data-head>${esc(w(s.lang, 'recentlyUsed'))}</div><p class="ruhint">${nw(s.lang, 'ruChipsHint')}</p>
        <div class="rchips">${chips}</div></section>`;
    },
  },

  RU4: {
    id: 'RU4',
    folded: false,
    motion: 'collapse',
    limit: 5,
    recent: (s) => {
      if (!s.recent.length) return '';
      const shown = s.showAll ? s.recent : s.recent.slice(0, 5);
      const lead = `<span class="rcheck">${ic('check', 'icon')}</span>`;
      const rows = shown.map((id, k) => row(s, id, { recent: true, last: k === shown.length - 1, cls: ' struck', lead, tail: '' })).join('');
      const more = !s.showAll && s.recent.length > 5 ? `<button class="showall" data-act="showAll" data-show-all>${nw(s.lang, 'ruShowAll', { count: s.recent.length })}</button>` : '';
      return `<section class="ru ru4" data-recent-section><div class="ldiv" data-head><i></i><span>${esc(w(s.lang, 'recentlyUsed'))} · ${s.recent.length}</span><i></i></div>
        ${rows}${more}<p class="ruhint end">${nw(s.lang, 'ruUntickHint')}</p></section>`;
    },
  },
};
export const ids = ['RU1', 'RU2', 'RU3', 'RU4'];
export const all = ['today', ...ids];
