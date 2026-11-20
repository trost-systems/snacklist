// Round AM's phone: AS1's sheet (chips under the grabber, up to three rows while typing, no close key) with five
// ways to show a match. Each option is a record: `typing` draws the rows while a match is on screen, `enter` names
// the action Enter sends, `offer` (AM4) the row after an add. The renderer never tests an option's id. Nothing
// here moves or marks a row behind the sheet (Peter t1077u): matches and what became of them show in the sheet.
import { catChip, detailsChip, detailsField, esc, ic, input, keyboard, picker, qtyCtl, row, settle, storeChip } from '../phone.js';
import { byId, curItem, lastTwo, matches, mergeQty, sameItem, storeName, suggestions, t } from './model.js';

export { settle };

const qtyText = (q) => (q === '' ? '' : /^\d+$/.test(q) ? `${q}×` : q);
// What tells two items with one name apart: store, brand, details. Plain-text store names (N-292).
const facts = (i, lang) => [i.store ? storeName(i.store, lang) : '', i.brand, i.details].filter(Boolean).join(' · ');
const nameLine = (i, lang) => `${qtyText(i.qty) ? `<b class="q">${esc(qtyText(i.qty))}</b> ` : ''}<b>${esc(i[lang])}</b>`;

// A match as a list row: the list's look, blue (accent) when open, struck through when ticked.
const matchBody = (m, env, extra = '') => {
  const i = m.item;
  const f = facts(i, env.lang);
  return `<span class="hx emo">${i.emoji}</span><span class="nm">${nameLine(i, env.lang)}${f ? `<span class="sub">${esc(f)}</span>` : ''}</span>${extra}`;
};
const mattrs = (m) => `data-match="${m.item.id}" data-status="${m.item.status}" data-kind="${m.kind}"`;
const enterMark = ic('keyboard_return', 'icon ret');

const catalogRows = (s, env, enterFirst = true) =>
  suggestions(s, env.lang)
    .map((c, i) => `<button class="sugg${i === 0 && enterFirst ? ' first' : ''}" data-act="take:${i}" data-outcome="${i === 0 ? 'none' : ''}"><span class="hx emo">${c.emoji}</span><span>${esc(c[env.lang])}</span>${i === 0 && enterFirst ? enterMark : ''}</button>`)
    .join('');
const newRow = (s, env, act = 'new', enter = false) =>
  `<button class="sugg newrow${enter ? ' first' : ''}" data-act="${act}" data-outcome="new">${ic('add')}<span>${esc(s.text.trim())}</span>${enter ? enterMark : ''}</button>`;
const tickBtn = (id, env) => `<button class="roundbtn" data-act="tick:${id}" data-outcome="tick" aria-label="${esc(t(env.lang).tickOff)}">${ic('check_circle_outline')}</button>`;

// The rows while typing, plain AS1: catalog suggestions, the first one on Enter.
const plain = (s, env) => `${catalogRows(s, env)}`;

// Whatever Enter does with no match: the first suggestion, else the typed text as a new item.
const plainEnter = (s, lang) => (suggestions(s, lang).length ? 'take:0' : 'new');

export const options = {
  AM1: {
    id: 'AM1',
    // Matches lead the rows. A tap on one (or Enter on the first) merges into it, its round key ticks it off.
    typing: (s, env, ms) => {
      const first = sameItem(s, env.lang);
      return `${ms
        .map((m) => {
          const open = m.item.status === 'open';
          const isEnter = first && m.item.id === first.item.id;
          return `<div class="mrow ${m.item.status}" ${mattrs(m)}><button class="mbody" data-act="${open ? 'merge' : 'back'}:${m.item.id}" data-outcome="${open ? 'merge' : 'back'}">${matchBody(m, env, open ? '' : ic('replay', 'icon lead'))}${isEnter ? enterMark : ''}</button>${open ? tickBtn(m.item.id, env) : ''}</div>`;
        })
        .join('')}${newRow(s, env, 'new', !first)}`;
    },
    enter: (s, lang) => {
      const m = sameItem(s, lang);
      if (m) return `${m.item.status === 'open' ? 'merge' : 'back'}:${m.item.id}`;
      return matches(s, lang).length ? 'new' : plainEnter(s, lang);
    },
  },
  AM2: {
    id: 'AM2',
    // One row per outcome, each marked by its icon and by showing its result: merge shows the amount after it
    // (2× Pasta), tick off shows the name struck through, a ticked match shows Back on the list's icon. The + row adds.
    // No row is on Enter (none is honey, AS1's add colour): Enter keeps the list as it is, as today's refusal, and the
    // sheet says so.
    typing: (s, env, ms) => {
      const rows = [];
      for (const m of ms) {
        const i = m.item;
        const f = facts(i, env.lang);
        const sub = f ? `<span class="sub">${esc(f)}</span>` : '';
        if (i.status === 'ticked') {
          rows.push(`<button class="sugg orow back" ${mattrs(m)} data-act="back:${i.id}" data-outcome="back">${ic('replay')}<span class="nm">${nameLine(i, env.lang)}${sub}</span>${m === ms[0] ? enterMark : ''}</button>`);
          continue;
        }
        const merged = { ...i, qty: mergeQty(i.qty, '') };
        rows.push(`<button class="sugg orow merge" ${mattrs(m)} data-act="merge:${i.id}" data-outcome="merge">${ic('call_merge')}<span class="nm">${nameLine(merged, env.lang)}${sub}</span></button>`);
        // The first open match also gets a tick-off row, with the same second line so both rows read as one item.
        if (i === ms.find((x) => x.item.status === 'open').item) rows.push(`<button class="sugg orow tick" ${mattrs(m)} data-act="tick:${i.id}" data-outcome="tick">${ic('check_circle_outline')}<span class="nm"><s>${esc(i[env.lang])}</s>${sub}</span></button>`);
      }
      const first = sameItem(s, env.lang);
      return `${rows.slice(0, 3).join('')}${newRow(s, env, 'new', !first)}`;
    },
    enter: (s, lang) => {
      const m = sameItem(s, lang);
      if (m) return m.item.status === 'open' ? `keep:${m.item.id}` : `back:${m.item.id}`;
      return matches(s, lang).length ? 'new' : plainEnter(s, lang);
    },
  },
  AM3: {
    id: 'AM3',
    // One match at a time, as a row, and three equal keys under it. Several matches: their names above, one tap
    // switches. Enter takes the honey key: Merge for an open match, Back on the list for a ticked one.
    typing: (s, env, ms) => {
      const w = t(env.lang);
      const focus = (s.focus && ms.find((m) => m.item.id === s.focus)) || sameItem(s, env.lang);
      const switcher =
        ms.length > 1
          ? `<div class="line nowrap" data-opts="matches">${ms
              .map((m) => `<button class="opt${focus && m.item.id === focus.item.id ? ' on' : ''} ${m.item.status}" ${mattrs(m)} data-act="focus:${m.item.id}"><span>${m.item.status === 'ticked' ? ic('check') : ''}${esc(m.item[env.lang])}</span></button>`)
              .join('')}</div>`
          : '';
      if (!focus) return `${switcher}${newRow(s, env, 'new', true)}`;
      const open = focus.item.status === 'open';
      const id = focus.item.id;
      const keys = open
        ? `<button class="tact" data-act="tick:${id}" data-outcome="tick" aria-label="${esc(w.tickOff)}"><span>${ic('check_circle_outline')}</span></button>
           <button class="tact on" data-act="merge:${id}" data-outcome="merge"><span>${ic('call_merge')}${esc(w.merge)}${enterMark}</span></button>
           <button class="tact" data-act="new:${id}" data-outcome="new"><span>${ic('add')}${esc(w.newItem)}</span></button>`
        : `<button class="tact on" data-act="back:${id}" data-outcome="back"><span>${ic('replay')}${esc(w.readd)}${enterMark}</span></button>
           <button class="tact" data-act="new:${id}" data-outcome="new"><span>${ic('add')}${esc(w.newItem)}</span></button>`;
      return `${switcher}<div class="mrow card ${focus.item.status}" ${ms.length > 1 ? '' : mattrs(focus)}><div class="mbody">${matchBody(focus, env)}</div></div><div class="decide${open ? '' : ' two'}">${keys}</div>`;
    },
    enter: (s, lang) => {
      const ms = matches(s, lang);
      const focus = (s.focus && ms.find((m) => m.item.id === s.focus)) || sameItem(s, lang);
      if (focus) return `${focus.item.status === 'open' ? 'merge' : 'back'}:${focus.item.id}`;
      return ms.length ? 'new' : plainEnter(s, lang);
    },
  },
  AM4: {
    id: 'AM4',
    // Today's order inside AS1: Enter always adds; then the item it matched shows over the chips with one key,
    // Merge (or Back on the list for a ticked one). Typing on, or a tap elsewhere, keeps both.
    hidesWhileTyping: true,
    typing: (s, env) => `${catalogRows(s, env, false)}${newRow(s, env, 'add', true)}`,
    enter: (s, lang) => (sameItem(s, lang) ? 'add' : plainEnter(s, lang)),
    offer: (s, env) => {
      const w = t(env.lang);
      const m = byId(s, s.offer.match);
      const ticked = m.status === 'ticked';
      return `<div class="mrow ${m.status}" ${mattrs({ item: m, kind: 'offer' })}><div class="mbody">${matchBody({ item: m }, env)}</div><button class="tact" data-act="fold" data-outcome="${ticked ? 'back' : 'merge'}"><span>${ic(ticked ? 'replay' : 'call_merge')}${esc(ticked ? w.readd : w.merge)}</span></button></div>`;
    },
  },
  AM5: {
    id: 'AM5',
    // Bring!'s tiles: what is on the list is blue; a tap ticks it off, as in Bring!, and so does Enter. A ticked
    // tile comes back with a tap. The + in a tile's corner merges. The last tile adds the typed text as new.
    typing: (s, env, ms) => {
      const first = sameItem(s, env.lang);
      const tile = (m) => {
        const i = m.item;
        const open = i.status === 'open';
        const f = facts(i, env.lang);
        const isEnter = first && i.id === first.item.id;
        return `<div class="tile ${i.status}" ${mattrs(m)}><button class="tbody" data-act="${open ? 'tick' : 'back'}:${i.id}" data-outcome="${open ? 'tick' : 'back'}">
          <span class="emo">${open ? i.emoji : ic('check')}</span><b>${esc(i[env.lang])}</b>${qtyText(i.qty) ? `<span class="tq">${esc(qtyText(i.qty))}</span>` : ''}${f ? `<span class="sub">${esc(f)}</span>` : ''}${isEnter ? enterMark : ''}</button>
          ${open ? `<button class="corner" data-act="merge:${i.id}" data-outcome="merge" aria-label="${esc(t(env.lang).more)}">${ic('add')}</button>` : ''}</div>`;
      };
      return `<div class="tiles">${ms.map(tile).join('')}<div class="tile newtile"><button class="tbody" data-act="new" data-outcome="new"><span class="emo">${ic('add')}</span><b>${esc(s.text.trim())}</b>${first ? '' : enterMark}</button></div></div>`;
    },
    enter: (s, lang) => {
      const m = sameItem(s, lang);
      if (m) return `${m.item.status === 'open' ? 'tick' : 'back'}:${m.item.id}`;
      return matches(s, lang).length ? 'new' : plainEnter(s, lang);
    },
  },
};
export const ids = Object.keys(options);

// What became of a match, in the chips' place until the next letter: the app's own sentences.
const note = (s, env) => {
  const w = t(env.lang);
  const i = byId(s, s.note.id);
  const named = `${qtyText(i.qty) ? `${qtyText(i.qty)} ` : ''}${i[env.lang]}`;
  const say = { merge: [ic('call_merge'), w.merged(named)], tick: [ic('check_circle_outline'), w.ticked(i[env.lang])], back: [ic('replay'), `${w.readd}: ${named}`], already: [ic('list'), w.already(i[env.lang])] }[s.note.kind];
  return `<div class="amnote" data-note="${s.note.kind}">${say[0]}<span>${esc(say[1])}</span></div>`;
};

const body = (s, opt, env) => {
  const item = curItem(s);
  const ms = matches(s, env.lang);
  const typed = s.text.trim() !== '';
  if (typed) {
    const shows = opt.hidesWhileTyping ? sameItem(s, env.lang) : ms.length;
    const rows = shows ? opt.typing(s, env, ms) : plain(s, env);
    return `<div class="sbody" data-typing>${rows}${input(s, env)}</div>`;
  }
  if (!item) return `<div class="sbody">${s.note ? note(s, env) : ''}${input(s, env)}</div>`;
  const offer = s.offer && opt.offer ? opt.offer(s, env) : '';
  return `<div class="sbody">${offer}
    <div class="line tight" data-fieldline>${qtyCtl(item, env)}${storeChip(item, s, env, { arrow: false })}${catChip(item, s, env, { arrow: false })}${detailsChip(item, s, env, { compact: true })}</div>
    ${s.open === 'details' ? detailsField(item, s, env) : picker(item, s, env)}
    ${input(s, env)}</div>`;
};

const behindRow = (i, s, opt, env) => {
  const marked = i.id === s.cur && s.added.length > 1 && s.text.trim() === '';
  const html = row(i, env, { cur: marked }).replace(/data-act="select:/, 'data-act="edit:');
  return i.status === 'ticked' ? html.replace('class="item', 'class="item tickedrow').replace(/<span class="hx emo">[^<]*<\/span>/, `<span class="hx">${ic('check')}</span>`) : html;
};

// Closed: the whole list, open items and then the ticked ones.
const closedList = (s, opt, env) =>
  `<div class="list" data-list>${['open', 'ticked'].map((st) => s.items.filter((i) => i.status === st).map((i) => behindRow(i, { ...s, cur: null }, opt, env)).join('')).join('<div class="section"></div>')}</div>`;

export const phone = (s, opt, env, { live = false } = {}) => {
  const cls = `phone th-${env.theme} ${env.device} ts${env.ts}${s.sheet ? '' : ' closed'}`;
  const status = `<div class="status"><span>${env.device === 'android' ? '9:41' : '21:46'}</span><i class="sig"></i></div>`;
  if (!s.sheet) return `<div class="${cls}" data-opt="${opt.id}" data-state="closed"${live ? ' data-live' : ''}>${status}${closedList(s, opt, env)}</div>`;
  const behind = lastTwo(s).map((i) => behindRow(i, s, opt, env)).join('');
  return `<div class="${cls}" data-opt="${opt.id}" data-state="${s.sheet ? 'open' : 'closed'}"${live ? ' data-live' : ''}>${status}
    <div class="list behind" data-list data-act="dismiss">${behind}</div>
    <div class="sheet" data-sheet><div class="grab" data-grab aria-label="${esc(t(env.lang).close)}" role="button" data-act="dismiss"><i></i></div>${body(s, opt, env)}</div>
    ${keyboard(env)}${env.device === 'ios' ? '<div class="homeind"><i></i></div>' : ''}</div>`;
};
