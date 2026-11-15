// Round AF: after a tap in the add sheet, how does the user see what was added to which store and section, and find
// or fix it once the sheet is closed? Today (main) and AF1–AF5 as slots on the shared phone (../sandbox.js).
import { esc, ic, todayNote } from '../sandbox.js';

const S = {
  en: {
    change: 'Change',
    show: 'Show',
    nAdded: (n) => `${n} added`,
    oneAdded: (name) => `${name} added`,
    more: (n) => `+${n} more`,
    addedTitle: 'Added',
    addedTo: 'Added to',
    fresh: 'New',
    why: { remembered: 'remembered', usual: (c) => `usual for ${c}`, picked: 'your pick', none: '' },
    learnedStore: (n, s) => `Learned: next time ${n} goes to ${s}`,
    learnedNoStore: (n) => `Learned: next time ${n} goes without a store`,
    learnedCat: (n, c) => `Learned: ${n} goes under ${c} from now on`,
  },
  de: {
    change: 'Ändern',
    show: 'Zeigen',
    nAdded: (n) => `${n} hinzugefügt`,
    oneAdded: (name) => `${name} hinzugefügt`,
    more: (n) => `+${n} weitere`,
    addedTitle: 'Hinzugefügt',
    addedTo: 'Hinzugefügt zu',
    fresh: 'Neu',
    why: { remembered: 'gemerkt', usual: (c) => `üblich für ${c}`, picked: 'deine Wahl', none: '' },
    learnedStore: (n, s) => `Gemerkt: ${n} kommt nächstes Mal zu ${s}`,
    learnedNoStore: (n) => `Gemerkt: ${n} kommt nächstes Mal ohne Laden`,
    learnedCat: (n, c) => `Gemerkt: ${n} steht ab jetzt unter ${c}`,
  },
};
const W = (ph) => S[ph.lang];
const why = (ph, rec) => {
  const w = W(ph).why[rec.why];
  return typeof w === 'function' ? w(ph.catName(rec.categoryId)) : w;
};
// “Lidl · Chilled” for a note or toast: the section never breaks inside, the reason (“usual for Fruit & veg”) gets
// its own line.
const whereHtml = (ph, rec) => `${esc(ph.storeName(rec.storeId))} · <span class="nw">${esc(ph.catName(rec.categoryId))}</span>`;
const whyLine = (ph, rec) => (why(ph, rec) ? `<small class="why">${esc(why(ph, rec))}</small>` : '');
const fixBtn = (ph, rec, w, kinds, label, cls = 'txtbtn') =>
  `<button class="${cls}" data-act="fix" data-item="${rec.itemId}" data-where="${w}" data-kinds="${kinds}" aria-expanded="${ph.fix?.itemId === rec.itemId && ph.fix.where === w && ph.fix.kinds === kinds}">${label}</button>`;
const pickerAt = (ph, rec, w) => (ph.fix?.itemId === rec.itemId && ph.fix.where === w ? `<div class="fixbox">${ph.picker(rec.itemId, ph.fix.kinds)}</div>` : '');
const learnedAt = (ph, rec) => (ph.learned?.itemId === rec.itemId ? ph.learnedLine() : '');
const learning = {
  learnedStore: (ph, it) => (it.storeId ? W(ph).learnedStore(it.name, ph.storeName(it.storeId)) : W(ph).learnedNoStore(it.name)),
  learnedCat: (ph, it) => W(ph).learnedCat(it.name, ph.catName(it.categoryId)),
};
// AF5 at large text (AF-Q3's default): a half sheet leaves no room for suggestions, so from 130 % it is AF3.
const big = (ph) => ph.ts >= 130;
const session = (ph) => ph.session.filter((r) => ph.byId(r.itemId));
// Highlight what was added (a 2 s honey pulse) and bring the newest into view.
const showAdded = (ph) => {
  const recs = session(ph);
  for (const r of recs) ph.marks.hot.add(r.itemId);
  if (recs.length) ph.scrollTarget = recs.at(-1).itemId;
  ph.timer('hot', 2000, () => ph.marks.hot.clear());
};
const viaFix = (w, kinds) => (id, to, kind) => [`[data-act="fix"][data-item="${id}"][data-where="${w}"][data-kinds="${kinds}"]`, kind === 'store' ? `[data-act="fix-store"][data-item="${id}"][data-store="${to}"]` : `[data-act="fix-cat"][data-item="${id}"][data-cat="${to}"]`];
// The chip on a new row after the close (AF3, AF5): store and section, one tap opens both pickers; it wraps at large
// text instead of cutting the section off. The label is one inline run inside the centring flex face, so it wraps as
// text, not as side-by-side columns.
const rowChip = (ph, it) =>
  `<button class="rowchip" data-act="fix" data-item="${it.id}" data-where="list" data-kinds="store,cat" aria-expanded="${ph.fix?.itemId === it.id && ph.fix.where === 'list'}"><span><span class="chiplbl">${esc(ph.storeName(it.storeId))} · <span class="nw">${esc(ph.catName(it.categoryId))}</span>${ic('arrow_drop_down', 'xs')}</span></span></button>`;
const listFix = viaFix('list', 'store,cat');

// AF3's card where the finger was: the name, then “Added to [store ▾] [section ▾] reason”; at large text without
// “Added to” (the ✓ says it), so a long name leaves room for a suggestion row.
const confirmCard = (ph) => {
  const r = session(ph).at(-1);
  if (!r) return '';
  const chip = (kinds, label) => fixBtn(ph, r, 'confirm', kinds, `<span><span class="chiplbl">${esc(label)}${ic('arrow_drop_down', 'xs')}</span></span>`, 'confirm-chip');
  return `<div class="confirm" data-confirm><p class="confirm-name">${ic('check', 'sm')}<b>${esc(r.name)}</b></p>
    <p class="confirm-to"><span class="muted added-to">${W(ph).addedTo}</span>${chip('store', ph.storeName(r.storeId))}${chip('cat', ph.catName(r.categoryId))}${why(ph, r) ? `<small class="muted">${esc(why(ph, r))}</small>` : ''}</p>
    ${pickerAt(ph, r, 'confirm')}${ph.learned?.itemId === r.itemId ? ph.learnedLine() : ''}</div>`;
};
const scrollToNewest = (ph) => {
  const recs = session(ph);
  if (recs.length) ph.scrollTarget = recs.at(-1).itemId;
};

// The same counting everywhere: after the close a fix goes through the edit sheet (hold, chip, pick, Done) unless the
// option leaves a control for it. `hold:` is a long press; every step counts as one tap.
const editPath = (kind) => (id, to) => [`hold:.item[data-item="${id}"]`, `[data-act="edit-chip"][data-fold="${kind}"]`, kind === 'store' ? `[data-act="edit-store"][data-store="${to}"]` : `[data-act="edit-cat"][data-cat="${to}"]`, '[data-act="edit-done"]'];

export const options = [
  {
    id: 'today',
    name: { en: 'Today', de: 'Heute' },
    line: {
      en: 'Main: “✓ Added: Feta → Rewe” with Undo, the store only when the tapped row knew it, no section; the list waits behind the scrim, nothing moves on close.',
      de: 'Main: „✓ Hinzugefügt: Feta → Rewe“ mit Rückgängig, der Laden nur, wenn die getippte Zeile ihn kannte, keine Kategorie; die Liste wartet hinter dem Schleier, beim Schließen bewegt sich nichts.',
    },
    storeRule: 'today',
    fix: { open: { store: null, cat: null }, after: { store: editPath('store'), cat: editPath('cat') } },
  },
  {
    id: 'AF1',
    name: { en: 'Show me on close', de: 'Beim Schließen zeigen' },
    line: {
      en: 'Today’s note grows to “✓ Halloumi → Lidl · Chilled” with Change and Show; closing scrolls the list to what was added, pulses it and marks it “New”.',
      de: 'Die Notiz von heute wird zu „✓ Halloumi → Lidl · Kühlregal“ mit Ändern und Zeigen; beim Schließen scrollt die Liste zum Hinzugefügten, lässt es aufleuchten und markiert es „Neu“.',
    },
    storeRule: 'st1',
    ...learning,
    note: (ph) => {
      const n = ph.sheet.note;
      if (n?.kind !== 'added') return todayNote(ph);
      const rec = n.rec;
      return `<div class="note grown" data-note><p role="status"><b>✓ ${esc(rec.name)}</b> → ${whereHtml(ph, rec)}${whyLine(ph, rec)}</p>
        <span class="note-acts"><button class="txtbtn" data-act="undo">${ph.T.undo}</button>${fixBtn(ph, rec, 'note', 'store,cat', W(ph).change)}<button class="txtbtn strong" data-act="show">${W(ph).show}</button></span></div>
        ${pickerAt(ph, rec, 'note')}${learnedAt(ph, rec)}`;
    },
    onClose: showAdded,
    rowExtra: (ph, it) => (ph.marks.fresh.has(it.id) && !ph.sheet.open ? `<span class="newmark">${W(ph).fresh}</span>` : ''),
    act: (ph, a) => {
      if (a.act === 'show') ph.close();
    },
    fix: { open: { store: viaFix('note', 'store,cat'), cat: viaFix('note', 'store,cat') }, after: { store: editPath('store'), cat: editPath('cat') } },
  },
  {
    id: 'AF2',
    name: { en: 'Added tray', de: 'Ablage „Hinzugefügt“' },
    line: {
      en: 'A tray at the top of the sheet lists every add of this session with its store and section, each one tap to change; after the close a “3 added · Show” bar above the field for 5 s.',
      de: 'Eine Ablage oben im Blatt zeigt jedes Hinzugefügte dieser Runde mit Laden und Kategorie, beides mit einem Tipp änderbar; nach dem Schließen 5 s lang eine Leiste „3 hinzugefügt · Zeigen“ über dem Feld.',
    },
    storeRule: 'st1',
    ...learning,
    note: (ph) => (ph.sheet.note?.kind === 'already' ? todayNote(ph) : ''),
    sheetTop: (ph) => {
      const recs = session(ph).slice().reverse();
      if (!recs.length) return '';
      const shown = recs.slice(0, 3);
      return `<div class="tray" data-tray><p class="tray-h">${ic('check', 'xs')} ${W(ph).addedTitle} · ${recs.length}</p>${shown
        .map(
          (r) => `<div class="tray-line" data-rec="${r.itemId}"><span class="tray-name">${esc(r.name)}${why(ph, r) ? `<small>${esc(why(ph, r))}</small>` : ''}</span>
            ${fixBtn(ph, r, 'tray', 'store', `<span class="badge-hex sm"><i>${esc(ph.storeName(r.storeId))}</i></span>`, 'traybtn')}
            ${fixBtn(ph, r, 'tray', 'cat', `<span class="secname">${esc(ph.catName(r.categoryId))}</span>`, 'traybtn')}</div>
            ${pickerAt(ph, r, 'tray')}${learnedAt(ph, r)}`,
        )
        .join('')}${recs.length > 3 ? `<p class="tray-more">${W(ph).more(recs.length - 3)}</p>` : ''}</div>`;
    },
    onClose: (ph) => {
      const recs = session(ph);
      if (!recs.length) return;
      ph.after.bar = recs.length;
      ph.timer('bar', 5000, () => (ph.after.bar = null));
    },
    onWake: (ph) => ph.after.bar && ph.timer('bar', 5000, () => (ph.after.bar = null)),
    lasts: 5000,
    bar: (ph) => {
      if (!ph.after.bar) return '';
      const recs = session(ph);
      const text = recs.length === 1 ? W(ph).oneAdded(recs[0].name) : W(ph).nAdded(recs.length);
      return `<div class="addedbar" data-bar>${ic('check', 'sm')}<span class="grow">${esc(text)}</span><button class="txtbtn strong" data-act="show">${W(ph).show}</button></div>`;
    },
    act: (ph, a) => {
      if (a.act === 'show') {
        ph.after.bar = null;
        showAdded(ph);
      }
    },
    fix: { open: { store: viaFix('tray', 'store'), cat: viaFix('tray', 'cat') }, after: { store: editPath('store'), cat: editPath('cat') }, late: { store: editPath('store'), cat: editPath('cat') } },
  },
  {
    id: 'AF3',
    name: { en: 'Confirm in place', de: 'Bestätigung an Ort und Stelle' },
    line: {
      en: 'The tapped row becomes “✓ Halloumi · Added to [Lidl ▾] [Chilled ▾]” where the finger is and stays while you type the next; after the close the list shows the newest, and new rows carry a “Lidl · Chilled” chip.',
      de: 'Die getippte Zeile wird dort, wo der Finger ist, zu „✓ Halloumi · Hinzugefügt zu [Lidl ▾] [Kühlregal ▾]“ und bleibt, während du das Nächste tippst; nach dem Schließen zeigt die Liste das Neueste, neue Zeilen tragen einen Chip „Lidl · Kühlregal“.',
    },
    storeRule: 'st1',
    ...learning,
    learnedIn: 'list',
    note: (ph) => (ph.sheet.note?.kind === 'already' ? todayNote(ph) : ''),
    confirm: (ph) => confirmCard(ph),
    onClose: scrollToNewest,
    rowExtra: (ph, it) => (ph.marks.fresh.has(it.id) && !ph.sheet.open ? rowChip(ph, it) : ''),
    fix: { open: { store: viaFix('confirm', 'store'), cat: viaFix('confirm', 'cat') }, after: { store: listFix, cat: listFix } },
  },
  {
    id: 'AF4',
    name: { en: 'Toast with Show and Change', de: 'Hinweis mit Zeigen und Ändern' },
    line: {
      en: 'An app-wide snackbar “Halloumi → Lidl · Chilled  Change  Show” floats above the sheet and stays 6 s after the close; several adds collapse into “3 added · Show”.',
      de: 'Eine App-weite Snackbar „Halloumi → Lidl · Kühlregal  Ändern  Zeigen“ schwebt über dem Blatt und bleibt nach dem Schließen 6 s; mehrere werden zu „3 hinzugefügt · Zeigen“.',
    },
    storeRule: 'st1',
    ...learning,
    note: (ph) => (ph.sheet.note?.kind === 'already' ? todayNote(ph) : ''),
    float: (ph) => {
      const recs = session(ph);
      if (!recs.length || (!ph.sheet.open && !ph.after.toast)) return '';
      const one = recs.length === 1 ? recs[0] : null;
      const text = one ? `<b>${esc(one.name)}</b> → ${whereHtml(ph, one)}${whyLine(ph, one)}` : esc(W(ph).nAdded(recs.length));
      return `<div class="toast" data-toast role="status"><div class="toast-row"><span class="grow">${text}</span>
        ${one ? fixBtn(ph, one, 'toast', 'store,cat', W(ph).change, 'toastbtn') : ''}<button class="toastbtn" data-act="show">${W(ph).show}</button></div>
        ${one ? pickerAt(ph, one, 'toast') + learnedAt(ph, one) : ''}</div>`;
    },
    onClose: (ph) => {
      if (!session(ph).length) return;
      ph.after.toast = true;
      ph.timer('toast', 6000, () => (ph.after.toast = false));
    },
    onWake: (ph) => ph.after.toast && ph.timer('toast', 6000, () => (ph.after.toast = false)),
    lasts: 6000,
    act: (ph, a) => {
      if (a.act !== 'show') return;
      if (ph.sheet.open) ph.close();
      showAdded(ph);
    },
    fix: { open: { store: viaFix('toast', 'store,cat'), cat: viaFix('toast', 'store,cat') }, after: { store: viaFix('toast', 'store,cat'), cat: viaFix('toast', 'store,cat') }, late: { store: editPath('store'), cat: editPath('cat') } },
  },
  {
    id: 'AF5',
    name: { en: 'Split view', de: 'Geteilte Ansicht' },
    line: {
      en: 'The sheet stops at about half height without a dark scrim; the list above scrolls itself to where each add goes and the new row appears there, lit, with a “Lidl · Chilled” chip to change it. From 130 % text the sheet is full height with the scrim and confirms in place as AF3 does (AF-Q3).',
      de: 'Das Blatt hält auf halber Höhe, ohne dunklen Schleier; die Liste darüber scrollt selbst dorthin, wo das Hinzugefügte landet, und die neue Zeile erscheint dort, hell, mit einem Chip „Lidl · Kühlregal“ zum Ändern. Ab 130 % Text ist das Blatt voll hoch mit Schleier und bestätigt an Ort und Stelle wie AF3 (AF-Q3).',
    },
    storeRule: 'st1',
    ...learning,
    half: (ph) => !big(ph),
    scrim: (ph) => (big(ph) ? undefined : false),
    note: (ph) => {
      const n = ph.sheet.note;
      if (n?.kind !== 'added') return todayNote(ph);
      if (big(ph)) return '';
      return `<div class="note" data-note><p role="status">✓ ${esc(ph.T.added(n.rec.name, ph.storeName(n.rec.storeId)))}${whyLine(ph, n.rec)}</p><button class="txtbtn" data-act="undo">${ph.T.undo}</button></div>`;
    },
    confirm: (ph) => (big(ph) ? confirmCard(ph) : ''),
    learnedIn: 'list',
    onAdd: (ph, rec) => {
      if (big(ph)) return;
      ph.scrollTarget = rec.itemId;
      ph.marks.hot.add(rec.itemId);
      ph.timer('hot', 2000, () => ph.marks.hot.clear());
    },
    onClose: (ph) => big(ph) && scrollToNewest(ph),
    onCorrect: (ph, it) => (ph.scrollTarget = it.id),
    rowExtra: (ph, it) => (ph.marks.fresh.has(it.id) && (!big(ph) || !ph.sheet.open) ? rowChip(ph, it) : ''),
    fix: { open: { store: listFix, cat: listFix }, after: { store: listFix, cat: listFix } },
  },
];

// The scenarios: each plays its adds on a fresh phone (sheet open after the adds), the second frame closes the sheet.
const t = (en, de) => ({ en, de });
export const scenarios = {
  one: { name: t('One known item', 'Ein bekannter Artikel'), ops: [['open'], ['type', t('Fet', 'Fet')], ['take', 'feta']] },
  several: {
    name: t('Three adds, two stores', 'Drei hinzu, zwei Läden'),
    ops: [['open'], ['type', t('Egg', 'Eie')], ['take', 'eggs'], ['type', t('Toil', 'Klop')], ['take', 'toiletpaper'], ['type', t('Carrots', 'Karotten')], ['take', 'typed']],
  },
  long: { name: t('Long names', 'Lange Namen'), ops: [['open'], ['type', t('Organic', 'Bio-J')], ['take', 'honeyyog']] },
  first: { name: t('First-time grocery', 'Zum ersten Mal'), ops: [['open'], ['type', t('Halloumi', 'Halloumi')], ['take', 'typed']] },
  empty: { name: t('Into an empty section', 'In eine leere Kategorie'), ops: [['open'], ['type', t('Peas', 'Erbsen')], ['take', 'peas']] },
  fix: {
    name: t('Fix, then add again', 'Korrigieren, wieder hinzufügen'),
    ops: [['open'], ['type', t('Halloumi', 'Halloumi')], ['take', 'typed'], ['correct', 'halloumi', 'rewe'], ['buy', 'halloumi'], ['close'], ['open'], ['type', t('Hallo', 'Hallo')], ['take', 'halloumi']],
  },
};

export const play = (ph, ops) => {
  for (const [op, a, b] of ops) {
    if (op === 'open') ph.open();
    else if (op === 'close') ph.close();
    else if (op === 'type') ph.type(a[ph.lang]);
    else if (op === 'take') ph.take(ph.sheet.rows.find((r) => (a === 'typed' ? r.source === 'typed' : r.key === a)));
    else if (op === 'correct') ph.correct(ph.items.find((it) => it.key === a && !it.bought).id, { storeId: b });
    else if (op === 'buy') ph.buy(ph.items.find((it) => it.key === a && !it.bought).id);
  }
};

export const round = {
  id: 'af',
  label: 'AF',
  rec: { pick: 'AF3', runnerUp: 'AF5' },
  title: { en: 'Add feedback (AF1–AF5)', de: 'Rückmeldung beim Hinzufügen (AF1–AF5)' },
  compare: {
    en: 'After a tap in the add sheet: which item went to which store and section, and how to find or fix it once the sheet is closed. Today (main) next to five options. Each phone plays the scenario’s adds; the left one stays open, the right one is just after the close. Every phone is live: type, tap rows, close, change the store.',
    de: 'Nach einem Tipp im Hinzufügen-Blatt: welcher Artikel in welchen Laden und welche Kategorie kam, und wie man ihn nach dem Schließen findet oder korrigiert. Heute (main) neben fünf Varianten. Jedes Telefon spielt das Hinzufügen des Szenarios ab; das linke bleibt offen, das rechte ist direkt nach dem Schließen. Jedes Telefon ist echt: tippen, Zeilen antippen, schließen, Laden ändern.',
  },
  options,
  scenarios,
  frames: [
    { id: 'open', name: t('Sheet open, after the adds', 'Blatt offen, nach dem Hinzufügen') },
    { id: 'after', name: t('After the close', 'Nach dem Schließen') },
  ],
  setup: (ph, scen, frame) => {
    play(ph, scenarios[scen].ops);
    if (frame === 'after') play(ph, [['close']]);
  },
};
