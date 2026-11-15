// The phone: today's list screen with the add sheet over it, as a small state model plus a renderer.
// An option (a round's options.js entry) plugs into named slots; with no slot set the phone is Today (main).
import { icons } from './icons.js';
import * as M from './model.js';

export const ic = (name, cls = '') => `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name]}"/></svg>`;
export const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

const DEBOUNCE = 120;
let uid = 0;

export class Phone {
  constructor({ opt, lang = 'en', theme = 'light', ts = 100, list = M.startList, latency = 0, frozen = false, motion = 'full' }) {
    Object.assign(this, { opt, lang, theme, ts, latency, frozen, motion });
    this.T = M.T[lang];
    this.memory = Object.fromEntries(Object.entries(M.startMemory).map(([k, s]) => [k, { storeId: s }]));
    this.history = [...M.startHistory];
    this.items = list.map(([key, storeId, qty]) => this.#item({ key, name: M.byKey[key][lang] }, storeId, M.byKey[key].cat, qty));
    this.session = [];
    this.sheet = this.#blankSheet(false);
    this.fix = null; // { itemId, where, kinds }
    this.learned = null; // { itemId, text }
    this.edit = null; // { itemId, storeId, categoryId, fold }
    this.marks = { hot: new Set(), fresh: new Set() };
    this.after = {}; // option state after the close (bar, toast …)
    this.scrollTarget = null;
    this.cache = {};
    this.inflight = new Set();
    this.log = []; // { t, what } for the verify script
    this.adds = []; // every AddRecord ever, for the verify script
  }

  // ---- model ----
  #item(row, storeId, categoryId, qty = null) {
    const key = row.key ?? null;
    return { id: `i${++uid}`, key, name: row.name, qty, emoji: M.byKey[key]?.emoji ?? '', storeId, categoryId, bought: false };
  }
  #blankSheet(open) {
    return { open, text: '', rows: open ? M.emptyRows(this.ctx()) : [], answered: '', pick: {}, fold: null, note: null, pendingEnter: null };
  }
  ctx() {
    return { lang: this.lang, list: this.items, memory: this.memory, history: this.history };
  }
  active() {
    return this.items.filter((it) => !it.bought);
  }
  byId(id) {
    return this.items.find((it) => it.id === id);
  }
  get key() {
    return this.sheet.text.trim();
  }
  get loading() {
    return !!this.key && this.sheet.answered !== this.key;
  }
  get lastRec() {
    return this.session.at(-1) ?? null;
  }
  // An option's flag, fixed or by phone (AF5 changes shape at large text).
  flag(k) {
    const v = this.opt[k];
    return typeof v === 'function' ? v(this) : v;
  }
  storeName(id) {
    return M.storeName(id, this.lang);
  }
  catName(id) {
    return M.catName(id, this.lang);
  }

  open() {
    if (this.sheet.open) return;
    this.sheet = this.#blankSheet(true);
    this.session = [];
    this.fix = this.learned = null;
    this.marks = { hot: new Set(), fresh: new Set() };
    this.after = {};
    this.#clearTimers();
  }
  close() {
    if (!this.sheet.open) return;
    this.sheet.open = false;
    this.sheet.fold = null;
    this.fix = null;
    this.opt.onClose?.(this);
  }
  type(text) {
    clearTimeout(this.debounce);
    const s = this.sheet;
    s.text = text;
    s.note = null;
    s.fold = null;
    this.fix = null;
    this.learned = null;
    const key = text.trim();
    if (!key) {
      s.rows = M.emptyRows(this.ctx());
      s.answered = '';
      return;
    }
    if (!this.latency) {
      s.rows = M.serverRows(key, this.ctx());
      s.answered = key;
      return;
    }
    // add_sheet_cubit.type: a cached answer at once; the first letter on the device; later letters keep the rows.
    const known = this.cache[key];
    if (known) {
      s.rows = known;
      s.answered = key;
    } else if (!s.rows.length || s.answered === '' && s.rows.every((r) => r.forText === '')) {
      s.rows = M.deviceRows(key, this.ctx());
    } else if (this.opt.typedLive) {
      // Job 272's typed row, built on the device on every keystroke; the other rows still answer the older text.
      const [typed] = M.deviceRows(key, this.ctx());
      s.rows = [typed, ...s.rows.filter((r) => r.source !== 'typed')];
    }
    if (!known) this.debounce = setTimeout(() => this.#fetch(key), DEBOUNCE);
  }
  #fetch(key) {
    if (this.inflight.has(key)) return;
    this.inflight.add(key);
    this.log.push({ t: performance.now(), what: `fetch ${key}` });
    setTimeout(() => {
      this.inflight.delete(key);
      const rows = M.serverRows(key, this.ctx());
      this.cache[key] = rows;
      if (this.key === key && this.sheet.open) {
        this.sheet.rows = rows;
        this.sheet.answered = key;
        this.log.push({ t: performance.now(), what: `reply ${key}` });
        if (this.sheet.pendingEnter === key) {
          this.sheet.pendingEnter = null;
          this.take(rows[0]);
        }
        this.render();
      }
    }, this.latency);
  }
  // The reply for what is typed lands now (frames and the verify script).
  settle() {
    clearTimeout(this.debounce);
    const rows = M.serverRows(this.key, this.ctx());
    this.cache[this.key] = rows;
    this.sheet.rows = rows;
    this.sheet.answered = this.key;
  }
  takeFirst() {
    if (!this.key) return;
    if (!this.loading && this.sheet.rows.length) this.take(this.sheet.rows[0]);
    else {
      this.sheet.pendingEnter = this.key;
      clearTimeout(this.debounce);
      this.#fetch(this.key);
    }
  }

  // Where an add goes. Today: the row's store, else what the server's insert trigger remembers; the note names a
  // store only when the row knew it. The options: memory, else ST1 (the usual store for the category), else none.
  place(row) {
    const k = M.itemKey(row);
    const categoryId = this.sheet.pick.cat ?? row.categoryId ?? M.classify(row.key, this.memory);
    if (this.sheet.pick.store !== undefined) return { storeId: this.sheet.pick.store, categoryId, why: 'picked', shown: true };
    const mem = this.memory[k]?.storeId ?? null;
    if (this.opt.storeRule !== 'st1') {
      const storeId = row.storeId ?? mem;
      return { storeId, categoryId, why: storeId ? 'remembered' : 'none', shown: !!row.storeId };
    }
    if (mem) return { storeId: mem, categoryId, why: 'remembered', shown: true };
    const usual = M.usualStore(categoryId, this.active(), this.memory);
    return usual ? { storeId: usual, categoryId, why: 'usual', shown: true } : { storeId: null, categoryId, why: 'none', shown: true };
  }
  take(row) {
    if (!row) return;
    const k = M.itemKey(row);
    const dupe = this.active().find((it) => M.itemKey(it) === k);
    this.log.push({ t: performance.now(), what: `take ${row.name}` });
    if (dupe) {
      this.sheet.note = { kind: 'already', name: dupe.name };
      return;
    }
    const p = this.place(row);
    const item = this.#item(row, p.storeId, p.categoryId);
    this.items.push(item);
    const rec = { itemId: item.id, storeId: p.storeId, categoryId: p.categoryId, why: p.why, shown: p.shown, name: item.name };
    this.session.push(rec);
    this.adds.push(rec);
    this.marks.fresh.add(item.id);
    const s = this.sheet;
    clearTimeout(this.debounce);
    this.cache = {};
    Object.assign(s, { text: '', rows: M.emptyRows(this.ctx()), answered: '', pick: {}, fold: null, note: { kind: 'added', rec } });
    this.fix = this.learned = null;
    this.opt.onAdd?.(this, rec);
  }
  undo() {
    const rec = this.sheet.note?.rec;
    if (!rec) return;
    this.items = this.items.filter((it) => it.id !== rec.itemId);
    this.session = this.session.filter((r) => r !== rec);
    this.sheet.note = null;
    this.sheet.rows = M.emptyRows(this.ctx());
  }
  // A correction: the item moves, the household memory learns it (items_learn), the next add uses it.
  correct(itemId, change) {
    const it = this.byId(itemId);
    Object.assign(it, change);
    this.memory[M.itemKey(it)] = { storeId: it.storeId, categoryId: it.categoryId };
    for (const r of this.adds) if (r.itemId === itemId) Object.assign(r, change, { why: 'picked', shown: true });
    const text = 'storeId' in change ? this.opt.learnedStore?.(this, it) : this.opt.learnedCat?.(this, it);
    this.learned = text ? { itemId, text } : null;
    this.fix = null;
    this.marks.hot.add(itemId);
    this.opt.onCorrect?.(this, it);
  }
  buy(itemId) {
    const it = this.byId(itemId);
    it.bought = true;
    if (it.key) this.history = [it.key, ...this.history.filter((k) => k !== it.key)];
  }

  // ---- render ----
  mount(host) {
    this.host = host;
    host.addEventListener('click', (e) => this.#click(e));
    host.addEventListener('input', (e) => {
      if (e.target.matches('input.field')) {
        this.wake();
        this.open();
        this.type(e.target.value);
        this.render();
      }
    });
    host.addEventListener('keydown', (e) => {
      if (!e.target.matches('input.field')) return;
      if (e.key === 'Enter') {
        e.preventDefault();
        this.wake();
        this.takeFirst();
        this.render();
      } else if (e.key === 'Escape') {
        this.close();
        this.render();
      }
    });
    host.addEventListener('focusin', (e) => {
      if (e.target.matches('input.field') && !this.sheet.open) {
        this.wake();
        this.open();
        this.render();
      }
    });
    host.addEventListener('pointerdown', (e) => {
      this.wake();
      this.held = false;
      clearTimeout(this.holdTimer);
      const row = e.target.closest('.item[data-item]');
      if (!row || e.target.closest('button')) return;
      this.holdTimer = setTimeout(() => {
        this.held = true;
        this.openEdit(row.dataset.item);
        this.render();
      }, 450);
    });
    for (const ev of ['pointerup', 'pointercancel', 'pointerleave']) host.addEventListener(ev, () => clearTimeout(this.holdTimer));
    host.addEventListener('contextmenu', (e) => {
      const row = e.target.closest('.item[data-item]');
      if (!row) return;
      e.preventDefault();
      this.openEdit(row.dataset.item);
      this.render();
    });
    host.addEventListener('scroll', (e) => {
      if (e.target.matches?.('.list') && this.after.bar && !this.programmatic) {
        this.after.bar = null;
        this.render();
      }
    }, true);
    this.render();
  }
  // A frame phone stands still for its screenshot until someone touches it.
  wake() {
    if (!this.frozen) return;
    this.frozen = false;
    this.host.querySelector('.phone')?.classList.remove('frozen');
    if (this.marks.hot.size) this.timer('hot', 2000, () => this.marks.hot.clear());
    this.opt.onWake?.(this);
  }
  timer(name, ms, fn) {
    if (this.frozen) return;
    this.timers ??= {};
    clearTimeout(this.timers[name]);
    this.timers[name] = setTimeout(() => {
      fn();
      this.render();
    }, ms);
  }
  #clearTimers() {
    for (const t of Object.values(this.timers ?? {})) clearTimeout(t);
    this.timers = {};
  }
  openEdit(itemId) {
    const it = this.byId(itemId);
    this.edit = { itemId, storeId: it.storeId, categoryId: it.categoryId, fold: null };
  }

  #click(e) {
    const el = e.target.closest('[data-act]');
    // The click that ends a hold is the hold's, not a tap.
    if (this.held) {
      this.held = false;
      return;
    }
    if (!el || !this.host.contains(el)) return;
    this.wake();
    const a = el.dataset;
    const keep = () => this.host.querySelector('input.field')?.focus({ preventScroll: true });
    switch (a.act) {
      case 'take':
        this.take(this.sheet.rows[Number(a.i)]);
        keep();
        break;
      case 'close':
        this.close();
        break;
      case 'clear':
        this.type('');
        keep();
        break;
      case 'undo':
        this.undo();
        keep();
        break;
      case 'chip':
        this.sheet.fold = this.sheet.fold === a.fold ? null : a.fold;
        break;
      case 'pick-store':
        this.sheet.pick.store = a.store || null;
        this.sheet.fold = null;
        keep();
        break;
      case 'pick-cat':
        this.sheet.pick.cat = a.cat;
        this.sheet.fold = null;
        keep();
        break;
      case 'fix':
        this.fix = this.fix?.itemId === a.item && this.fix.where === a.where && this.fix.kinds === a.kinds ? null : { itemId: a.item, where: a.where, kinds: a.kinds };
        this.learned = null;
        break;
      case 'fix-store':
        this.correct(a.item, { storeId: a.store || null });
        if (this.sheet.open) keep();
        break;
      case 'fix-cat':
        this.correct(a.item, { categoryId: a.cat });
        if (this.sheet.open) keep();
        break;
      case 'tick':
        // Without a scrim (AF5) a tap on the list closes the sheet, as the scrim tap does (AF-Q1's default).
        if (this.sheet.open) this.close();
        else this.buy(a.item);
        break;
      case 'edit-chip':
        this.edit.fold = this.edit.fold === a.fold ? null : a.fold;
        break;
      case 'edit-store':
        this.edit.storeId = a.store || null;
        this.edit.fold = null;
        break;
      case 'edit-cat':
        this.edit.categoryId = a.cat;
        this.edit.fold = null;
        break;
      case 'edit-cancel':
        this.edit = null;
        break;
      case 'edit-done': {
        const { itemId, storeId, categoryId } = this.edit;
        const it = this.byId(itemId);
        this.edit = null;
        if (it.storeId !== storeId) this.correct(itemId, { storeId });
        if (it.categoryId !== categoryId) this.correct(itemId, { categoryId });
        break;
      }
      case 'scrim':
        if (this.edit) this.edit = null;
        else this.close();
        break;
      case 'open':
        this.open();
        keep();
        break;
      default:
        this.opt.act?.(this, a, el);
    }
    this.render();
  }

  render() {
    if (!this.host) return;
    const T = this.T;
    const s = this.sheet;
    const o = this.opt;
    const focused = document.activeElement?.matches?.('input.field') && this.host.contains(document.activeElement);
    const listTop = this.host.querySelector('.list')?.scrollTop ?? 0;
    const bodyTop = this.host.querySelector('.sheet-body')?.scrollTop ?? 0;
    const scrim = s.open && this.flag('scrim') !== false;
    const dock = `<div class="dock ${s.open && this.flag('half') ? 'half' : ''}">
      ${o.float?.(this) ?? ''}
      ${s.open ? this.#sheet() : (o.bar?.(this) ?? '')}
      <div class="addbar">${this.#field()}</div>
      ${s.open ? `<p class="sheet-hint">${esc(T.sheetHint)}</p>` : this.#nav()}
    </div>`;
    this.host.innerHTML = `<div class="phone th-${this.theme} ${this.motion === 'reduce' ? 'rm' : ''} ${this.frozen ? 'frozen' : ''} ${this.ts >= 130 ? 'ts-big' : ''}" data-opt="${o.id}" style="--ts:${this.ts / 100}">
      <div class="status"><b>9:41</b><span class="grow"></span><span class="sig"></span></div>
      <div class="hdr"><span class="tact"><span><b>${T.home}</b>${ic('expand_more', 'sm')}</span></span><span class="grow"></span><span class="tact"><span>${T.edit}</span></span></div>
      <div class="list" data-list>${this.#sections()}<div class="endpad"></div></div>
      ${scrim || this.edit ? `<div class="scrim" data-act="scrim"></div>` : ''}
      ${dock}
      ${this.edit ? this.#editSheet() : ''}
      <div class="homeind"><i></i></div>
    </div>`;
    const list = this.host.querySelector('.list');
    this.programmatic = true;
    list.scrollTop = listTop;
    const body = this.host.querySelector('.sheet-body');
    if (body) body.scrollTop = bodyTop;
    if (focused && s.open) {
      const f = this.host.querySelector('input.field');
      f.focus({ preventScroll: true });
      f.setSelectionRange(f.value.length, f.value.length);
    }
    if (this.scrollTarget) {
      const id = this.scrollTarget;
      this.scrollTarget = null;
      this.reveal(id);
    }
    requestAnimationFrame(() => (this.programmatic = false));
  }

  // Scrolls the list to the row, in the part of the list nobody covers: the store's divider at the top when the row
  // fits below it, else the row's category header, else the row itself. The list's top edge lands on that element, so
  // no half row sits under the header.
  reveal(itemId) {
    const list = this.host.querySelector('.list');
    const row = list.querySelector(`[data-item="${itemId}"]`);
    if (!row) return;
    const lr = list.getBoundingClientRect();
    const cover = this.coverTop();
    const top = lr.top, room = Math.min(lr.bottom, cover) - top - 8;
    if (!lr.height) return (this.scrollTarget = itemId);
    const wrap = row.closest('.item-wrap');
    const r = wrap.getBoundingClientRect();
    let cat = wrap.previousElementSibling;
    while (cat && !cat.matches('.cat')) cat = cat.previousElementSibling;
    const anchor = [row.closest('section'), cat, wrap].find((e) => e && r.bottom - e.getBoundingClientRect().top <= room) ?? wrap;
    this.programmatic = true;
    list.scrollTo({ top: list.scrollTop + anchor.getBoundingClientRect().top - top, behavior: 'instant' });
  }
  // The top of whatever covers the list from below: the open sheet (without a scrim), the bar, the add field.
  coverTop() {
    const dock = this.host.querySelector('.dock');
    const parts = [...dock.children].filter((c) => c.getBoundingClientRect().height);
    return Math.min(...parts.map((c) => c.getBoundingClientRect().top));
  }

  #nav() {
    const [l, h, m] = this.T.tabs;
    return `<nav class="nav"><span class="pill-wrap"><span class="pill-nav" role="tablist">
      <span class="on" role="tab" aria-selected="true">${ic('shopping_cart')}<em>${l}</em></span>
      <span role="tab" aria-selected="false">${ic('history')}<em>${h}</em></span>
      <span role="tab" aria-selected="false">${ic('menu')}<em>${m}</em></span></span></span></nav>`;
  }
  #field() {
    const s = this.sheet;
    return `<label class="addfield"><span class="in">
      <input class="field" autocomplete="off" spellcheck="false" aria-label="${esc(this.T.addHint)}" placeholder="${esc(this.T.addHint)}" value="${esc(s.text)}">
      ${this.opt.fieldTrail?.(this) ?? ''}
      ${s.open && s.text ? `<button class="ibtn" data-act="clear" aria-label="${this.T.clear}">${ic('close')}</button>` : ''}
      <button class="ibtn" data-act="noop" aria-label="${this.T.mic}">${ic('mic_none')}</button></span></label>`;
  }

  // The list: store dividers, uppercase category headers, rows. An option may add to a row (rowExtra).
  #sections() {
    const T = this.T;
    const act = this.active();
    return M.storeOrder
      .filter((st) => act.some((it) => it.storeId === st))
      .map((st) => {
        const its = act.filter((it) => it.storeId === st);
        const cats = M.categories.map((c) => c.id).filter((c) => its.some((it) => it.categoryId === c));
        return `<section data-store="${st}"><div class="div"><span class="badge-hex"><i>${esc(this.storeName(st))}</i></span><span class="rule"></span>
          <span class="count"><b>${its.length}</b> ${T.items(its.length)}</span><span class="tact fold" aria-hidden="true"><span>${ic('expand_more', 'sm')}</span></span></div>
          ${cats
            .map(
              (c) => `<div class="cat" data-cat="${c}"><span>${esc(this.catName(c))}</span><i></i></div>${its
                .filter((it) => it.categoryId === c)
                .map((it) => this.#row(it))
                .join('')}`,
            )
            .join('')}</section>`;
      })
      .join('');
  }
  #row(it) {
    const extra = this.opt.rowExtra?.(this, it) ?? '';
    const hot = this.marks.hot.has(it.id) ? 'hot' : '';
    return `<div class="item-wrap"><div class="item ${hot}" data-item="${it.id}" data-act="tick" role="checkbox" aria-checked="false">
      <span class="emoji">${it.emoji}</span><span class="iname">${it.qty ? `<b class="qty">${esc(it.qty)}×</b> ` : ''}${esc(it.name)}</span>${extra}</div>
      ${this.fix?.itemId === it.id && this.fix.where === 'list' ? `<div class="fixbox in-list">${this.picker(it.id, this.fix.kinds)}</div>` : ''}
      ${this.learned?.itemId === it.id && this.flag('learnedIn') === 'list' && (!this.sheet.open || this.flag('scrim') === false) ? this.learnedLine() : ''}</div>`;
  }

  // ---- the sheet ----
  #sheet() {
    const T = this.T;
    const s = this.sheet;
    const o = this.opt;
    const first = s.rows[0];
    const storeId = s.pick.store !== undefined ? s.pick.store : first?.storeId;
    const catId = s.pick.cat ?? first?.categoryId;
    const chip = (fold, label, auto, changed) =>
      `<button class="chip ${changed ? 'on' : ''} ${s.fold === fold ? 'open' : ''}" data-act="chip" data-fold="${fold}" aria-expanded="${s.fold === fold}"><span>${auto ? ic('hdr_auto_outlined', 'auto') : ''}<em>${esc(label)}</em>${ic('arrow_drop_down', 'sm')}</span></button>`;
    const fold =
      s.fold === 'store'
        ? `<div class="opts">${[null, ...M.stores.map((x) => x.id)].map((id) => `<button class="opt ${id === storeId ? 'on' : ''}" data-act="pick-store" data-store="${id ?? ''}"><span>${id ? '' : ic('storefront_outlined', 'sm')}${esc(this.storeName(id))}</span></button>`).join('')}</div>`
        : s.fold === 'cat'
          ? `<div class="opts">${M.categories.map((c) => `<button class="opt ${c.id === catId ? 'on' : ''}" data-act="pick-cat" data-cat="${c.id}"><span>${esc(c[this.lang])}</span></button>`).join('')}</div>`
          : '';
    const typing = !!this.key;
    const rows = s.rows.map((r, i) => this.#suggestion(r, i, i === 0 && typing)).join('');
    const empty = !s.rows.length && !s.note ? `<p class="empty-hint">${esc(T.typeToSuggest)}</p>` : '';
    return `<section class="sheet" aria-label="${this.lang === 'de' ? 'Hinzufügen' : 'Add'}" data-sheet>
      <div class="sheet-head"><i class="grab"></i><div class="chips">${chip('store', s.pick.store !== undefined || storeId ? this.storeName(storeId) : T.chipStore, s.pick.store === undefined, s.pick.store !== undefined)}${chip('cat', catId ? this.catName(catId) : T.chipCat, !s.pick.cat, !!s.pick.cat)}</div>
        <button class="tact hexkey" data-act="close" aria-label="${T.close}"><span>${ic('close')}</span></button></div>
      ${fold}
      ${o.sheetTop?.(this) ?? ''}
      <div class="sheet-body">
        ${(o.note ?? todayNote)(this)}
        ${o.confirm?.(this) ?? ''}
        <div class="rows ${typing ? '' : 'capped'}" style="${o.reserve && typing ? `--slots:${o.reserve}` : ''}" data-rows>${rows}${empty}</div>
      </div>
      ${o.sheetEdge?.(this) ?? ''}
    </section>`;
  }
  #suggestion(r, i, first) {
    const T = this.T;
    const ownStore = r.storeId && this.sheet.pick.store === undefined && r.storeId !== this.sheet.rows[0]?.storeId ? `<span class="badge-hex sm"><i>${esc(this.storeName(r.storeId))}</i></span>` : '';
    const emoji = M.byKey[r.key]?.emoji ?? M.catalog.find((c) => r.name.length > 2 && M.matches(c[this.lang], r.name))?.emoji ?? '';
    const cls = this.opt.rowClass?.(this, r) ?? '';
    return `<button class="srow ${first ? 'first' : ''} ${cls}" data-act="take" data-i="${i}" data-name="${esc(r.name)}" data-for="${esc(r.forText)}" ${this.opt.rowAria?.(this, r) ?? ''}>
      <span class="emoji">${emoji || (r.source === 'due' ? '🔁' : ic('hexagon_outlined', 'sm'))}</span>
      <span class="grow"><b class="sname">${esc(r.name)}</b><small>${esc(T.src[r.source])}</small></span>${ownStore}
      ${first ? `<span class="tact hexkey" aria-hidden="true"><span>${ic('keyboard_return', 'sm')}</span></span>` : ''}</button>`;
  }

  // The fix picker: one tap opened it, the second picks. Stores first, then the sections.
  picker(itemId, kinds) {
    const it = this.byId(itemId);
    const T = this.T;
    const parts = [];
    if (kinds.includes('store'))
      parts.push(`<div class="pick-row" data-pick="store"><span class="pick-l">${T.storeL}</span>${[null, ...M.stores.map((x) => x.id)]
        .map((id) => `<button class="opt ${id === it.storeId ? 'on' : ''}" data-act="fix-store" data-item="${itemId}" data-store="${id ?? ''}"><span>${esc(this.storeName(id))}</span></button>`)
        .join('')}</div>`);
    if (kinds.includes('cat'))
      parts.push(`<div class="pick-row" data-pick="cat"><span class="pick-l">${T.catL}</span>${M.categories
        .filter((c) => c.id !== 'other')
        .map((c) => `<button class="opt ${c.id === it.categoryId ? 'on' : ''}" data-act="fix-cat" data-item="${itemId}" data-cat="${c.id}"><span>${esc(c[this.lang])}</span></button>`)
        .join('')}</div>`);
    return parts.join('');
  }
  learnedLine() {
    return this.learned ? `<p class="learned" role="status">${ic('lightbulb_outline', 'sm')}<span>${esc(this.learned.text)}</span></p>` : '';
  }

  #editSheet() {
    const T = this.T;
    const e = this.edit;
    const it = this.byId(e.itemId);
    const opts =
      e.fold === 'store'
        ? `<div class="opts">${[null, ...M.stores.map((x) => x.id)].map((id) => `<button class="opt ${id === e.storeId ? 'on' : ''}" data-act="edit-store" data-store="${id ?? ''}"><span>${esc(this.storeName(id))}</span></button>`).join('')}</div>`
        : e.fold === 'cat'
          ? `<div class="opts">${M.categories.map((c) => `<button class="opt ${c.id === e.categoryId ? 'on' : ''}" data-act="edit-cat" data-cat="${c.id}"><span>${esc(c[this.lang])}</span></button>`).join('')}</div>`
          : '';
    return `<section class="edit-sheet" data-edit><i class="grab"></i>
      <label class="lab">${T.name}</label><div class="efield">${esc(it.name)}</div>
      <div class="chips"><button class="chip" data-act="edit-chip" data-fold="store"><span><em>${esc(this.storeName(e.storeId))}</em>${ic('arrow_drop_down', 'sm')}</span></button>
        <button class="chip" data-act="edit-chip" data-fold="cat"><span><em>${esc(this.catName(e.categoryId))}</em>${ic('arrow_drop_down', 'sm')}</span></button></div>
      ${opts}
      <div class="actions"><button class="txt" data-act="edit-cancel">${T.cancel}</button><button class="tact honey" data-act="edit-done"><span>${T.done}</span></button></div></section>`;
  }
}

// Main's note: "✓ Added: Milk → Lidl" with Undo; the store only when the tapped row knew it.
export const todayNote = (ph) => {
  const n = ph.sheet.note;
  if (!n) return '';
  const T = ph.T;
  if (n.kind === 'already') return `<div class="note" data-note><p role="status">${esc(T.already(n.name))}</p></div>`;
  const text = n.rec.shown && n.rec.storeId ? T.added(n.rec.name, ph.storeName(n.rec.storeId)) : T.addedItem(n.rec.name);
  return `<div class="note" data-note><p role="status">✓ ${esc(text)}</p><button class="txtbtn" data-act="undo">${T.undo}</button></div>`;
};
