import { CATALOG } from './data';
import type { Item, Lang, StoreId } from './data';

/* ---------- Menge: a port of app/lib/list/quantity.dart for one term per side ---------- */

type Kind = 'mass' | 'vol' | 'count';
interface Term {
  /** Base units: g, ml or pieces. */
  amount: number;
  kind: Kind | null;
  text: string;
}

const UNIT: Record<string, { kind: Kind; factor: number }> = {
  g: { kind: 'mass', factor: 1 },
  kg: { kind: 'mass', factor: 1000 },
  ml: { kind: 'vol', factor: 1 },
  l: { kind: 'vol', factor: 1000 },
  stück: { kind: 'count', factor: 1 },
};

const num = (s: string) => Number(s.replace(',', '.'));
const de = (n: number) => String(Math.round(n * 10000) / 10000).replace('.', ',');

function term(text: string): Term {
  const m = /^(\d+(?:[.,]\d+)?)\s*([a-zA-Zä]+)?$/.exec(text.trim());
  if (!m) return { amount: 0, kind: null, text };
  const unit = m[2] ? UNIT[m[2].toLowerCase()] : { kind: 'count' as Kind, factor: 1 };
  if (!unit) return { amount: 0, kind: null, text };
  return { amount: num(m[1] ?? '0') * unit.factor, kind: unit.kind, text };
}

function format(t: Term): string {
  if (t.kind === 'mass') return t.amount >= 1000 ? `${de(t.amount / 1000)} kg` : `${de(t.amount)} g`;
  if (t.kind === 'vol') return t.amount >= 1000 ? `${de(t.amount / 1000)} l` : `${de(t.amount)} ml`;
  if (t.kind === 'count') return de(t.amount);
  return t.text;
}

/** mergeQuantities: "500 g" + "1 kg" = "1,5 kg", "2" + null = "3", null + null = "2", "500 g" + null = "500 g". */
export function mergeQty(open: string | null, other: string | null): string {
  if (!open && !other) return '2';
  let a = open ? term(open) : null;
  let b = other ? term(other) : null;
  if (!a && b?.kind === 'count') a = term('1');
  if (!b && a?.kind === 'count') b = term('1');
  if (!a) return format(b as Term);
  if (!b) return format(a);
  if (a.kind && a.kind === b.kind) return format({ ...a, amount: a.amount + b.amount });
  return `${format(a)} + ${format(b)}`;
}

/** quantityLabel: a count reads "6×", anything else as it is; one piece shows nothing. */
export function qtyLabel(qty: string | null): string {
  if (!qty) return '';
  return /^\d+(?:,\d+)?$/.test(qty) ? `${qty}×` : qty;
}

/** One more of what is on the list: a count steps by 1, a weight or volume by its own Menge (one more pack). */
export function stepOf(open: string | null): string {
  const t = open ? term(open) : null;
  return t && (t.kind === 'mass' || t.kind === 'vol') ? format(t) : '1';
}

export function times(amount: string, k: number): string {
  const t = term(amount);
  return t.kind ? format({ ...t, amount: t.amount * k }) : amount;
}

/* ---------- The typed line ---------- */

export interface Typed {
  name: string;
  qty: string | null;
}

const UNITS = 'kg|g|ml|l|stück';

/** parseEntry's rules that matter here: an amount up front, an amount with a unit at the end, "x2" at the end, and a bare
 * count 1–20 at the end when the rest is a name the household knows (`known`: the list and the catalog here; production also
 * asks the dictionary) and the word before it holds no digit ("Windeln Größe 4", and so "Omega 3 2"). */
export function parseTyped(text: string, known: string[] = []): Typed {
  const t = text.trim().replace(/\s+/g, ' ');
  let m = new RegExp(`^(\\d+(?:[.,]\\d+)?)(?:\\s*(${UNITS})\\.?)?\\s+(.+)$`, 'i').exec(t);
  if (m) return { name: m[3] ?? '', qty: m[2] ? `${m[1]} ${m[2].toLowerCase()}` : (m[1] ?? null) };
  m = new RegExp(`^(.+?)\\s+(\\d+(?:[.,]\\d+)?)\\s*(${UNITS})\\.?$`, 'i').exec(t);
  if (m) return { name: m[1] ?? '', qty: `${m[2]} ${(m[3] ?? '').toLowerCase()}` };
  m = /^(.+?)\s+[x×](\d+)$/i.exec(t);
  if (m) return { name: m[1] ?? '', qty: m[2] ?? null };
  m = /^(.+)\s([1-9]\d?)$/.exec(t);
  const isKnown = (n: string) => known.some((k) => k.toLowerCase() === n.toLowerCase());
  if (m && Number(m[2]) <= 20 && !/\d/.test((m[1] ?? '').split(' ').pop() ?? '') && isKnown(m[1] ?? '')) return { name: m[1] ?? '', qty: m[2] ?? null };
  return { name: t, qty: null };
}

export const knownNames = (items: Item[], lang: Lang) => [...items.map((it) => it.name[lang]), ...CATALOG.map((c) => c.name[lang])];

/** item_key without the stemming: folded letters, numbers and amounts dropped ("Omega 3 2" and "Omega 3" are both "omega"). */
export function keyOf(name: string): string {
  return name
    .toLowerCase()
    .replace(/ä/g, 'a')
    .replace(/ö/g, 'o')
    .replace(/ü/g, 'u')
    .replace(/ß/g, 'ss')
    .replace(new RegExp(`\\b\\d+(?:[.,]\\d+)?\\s*(?:${UNITS})?\\b`, 'gi'), ' ')
    .replace(/[^a-z]+/g, ' ')
    .trim();
}

export interface MatchInfo {
  item: Item;
  /** The amount the person typed, as the option reads it. */
  typedQty: string | null;
  /** What a plain Enter adds when nothing is typed: Today merges the typed Menge (none = production's rule), DM steps. */
  step: string;
}

/**
 * The open item the typed line is the same thing as. `smart` is the DM reading: a bare number after a name that is on
 * the list is its amount ("Omega 3 2" is Omega 3, 2 more), and an untyped amount is one more of the item.
 */
export function matchOf(text: string, items: Item[], lang: Lang, smart: boolean): MatchInfo | null {
  if (!text.trim()) return null;
  const typed = parseTyped(text, knownNames(items, lang));
  const key = keyOf(typed.name);
  if (!key) return null;
  const item = items.find((it) => keyOf(it.name[lang]) === key);
  if (!item) return null;
  let typedQty = typed.qty;
  if (smart && !typedQty) {
    const m = /^(.+)\s([1-9]\d?)$/.exec(text.trim());
    if (m && (m[1] ?? '').toLowerCase() === item.name[lang].toLowerCase()) typedQty = m[2] ?? null;
  }
  return { item, typedQty, step: typedQty ?? (smart ? stepOf(item.qty) : '') };
}

/** The Menge after adding `amount` ('' is production's merge of no typed Menge). */
export const mergedQty = (item: Item, amount: string) => mergeQty(item.qty, amount || null);

/* ---------- Sandbox state ---------- */

export type Mark = 'new' | 'raised';

export interface Note {
  kind: 'merged' | 'ticked' | 'added';
  text: string;
}

export interface State {
  phase: 'closed' | 'open';
  text: string;
  items: Item[];
  marks: Record<string, Mark>;
  note: Note | null;
  /** DM5's stepper: how many steps of one more; 0 is what was typed. */
  k: number;
  /** DM5: the action picked before confirming. */
  choice: 'merge' | 'tick' | 'new';
  seq: number;
}

export type Action =
  | { type: 'open' }
  | { type: 'close' }
  | { type: 'text'; text: string }
  | { type: 'k'; k: number }
  | { type: 'choose'; choice: State['choice'] }
  | { type: 'merge'; id: string; qty: string; note: string }
  | { type: 'tick'; id: string; note: string }
  | { type: 'add'; name: string; qty: string | null; lang: Lang; note: string };

export const initialState = (items: Item[]): State => ({ phase: 'closed', text: '', items, marks: {}, note: null, k: 0, choice: 'merge', seq: 0 });

const fresh = { text: '', k: 0, choice: 'merge' as const };

export function reduce(s: State, a: Action): State {
  switch (a.type) {
    case 'open':
      return { ...s, phase: 'open' };
    case 'close':
      return { ...s, phase: 'closed', ...fresh, marks: {}, note: null };
    case 'text':
      return { ...s, text: a.text, k: 0, choice: 'merge', note: a.text ? null : s.note };
    case 'k':
      return { ...s, k: Math.max(1, a.k) };
    case 'choose':
      return { ...s, choice: a.choice };
    case 'merge':
      return {
        ...s,
        ...fresh,
        items: s.items.map((it) => (it.id === a.id ? { ...it, qty: a.qty } : it)),
        marks: { ...s.marks, [a.id]: 'raised' },
        note: { kind: 'merged', text: a.note },
        seq: s.seq + 1,
      };
    case 'tick':
      return { ...s, ...fresh, items: s.items.filter((it) => it.id !== a.id), note: { kind: 'ticked', text: a.note }, seq: s.seq + 1 };
    case 'add': {
      const cat = CATALOG.find((c) => keyOf(c.name[a.lang]) === keyOf(a.name));
      const like = s.items.find((it) => keyOf(it.name[a.lang]) === keyOf(a.name));
      const store: StoreId = like?.store ?? cat?.store ?? 'rewe';
      const id = `new-${s.seq + 1}`;
      const item: Item = { id, name: { en: a.name, de: a.name }, emoji: like?.emoji ?? cat?.emoji ?? '', qty: a.qty, store, cat: like?.cat ?? cat?.cat ?? 9 };
      return { ...s, ...fresh, items: [...s.items, item], marks: { ...s.marks, [id]: 'new' }, note: { kind: 'added', text: a.note }, seq: s.seq + 1 };
    }
  }
}

export function sectionsOf(items: Item[]): { store: StoreId; items: Item[] }[] {
  const order: StoreId[] = ['rewe', 'dm', 'none'];
  return order
    .map((store) => ({
      store,
      items: items
        .map((it, n) => ({ it, n }))
        .filter(({ it }) => it.store === store)
        .sort((a, b) => a.it.cat - b.it.cat || a.n - b.n)
        .map(({ it }) => it),
    }))
    .filter((sec) => sec.items.length > 0);
}

/** Catalog rows for the typed name, after the match and the typed row. */
export function catalogRows(text: string, lang: Lang) {
  const key = keyOf(parseTyped(text).name);
  if (key.length < 2) return [];
  return CATALOG.filter((c) => keyOf(c.name[lang]).includes(key) && keyOf(c.name[lang]) !== key).slice(0, 3);
}

/** How many `unit` steps make `amount` ("1 kg" is two of "500 g"); at least 1. */
export function stepsIn(amount: string, unit: string): number {
  const a = term(amount);
  const u = term(unit);
  if (!a.kind || a.kind !== u.kind || !u.amount) return 1;
  return Math.max(1, Math.round(a.amount / u.amount));
}
