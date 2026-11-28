import { CATALOG, STORES } from './data';
import type { Item, L10n, Lang, StoreId } from './data';

export type Phase = 'closed' | 'open';

/** One opening of the add surface; `session` holds the ids added or raised while it is open, newest last. */
export interface State {
  items: Item[];
  phase: Phase;
  text: string;
  session: string[];
  /** The row that just changed, for the highlight and the motion. `seq` restarts the animation on a repeat. */
  flash: { id: string; kind: 'new' | 'merged'; seq: number } | null;
  /** Set after a take of an exact duplicate in Today's and AE1's default (a second row). */
  secondOf: string | null;
  nextSeq: number;
}

export type RowKind = 'merge' | 'tick' | 'typed' | 'catalog';

export interface Row {
  kind: RowKind;
  name: string;
  emoji: string;
  /** The open item the row acts on (merge, tick) or the one an exact duplicate would double. */
  match: Item | null;
  store: StoreId;
  cat: number;
}

export type DupDefault = 'typed' | 'merge';

export type Action =
  | { type: 'open' }
  | { type: 'close' }
  | { type: 'text'; text: string }
  | { type: 'take'; row: Row; lang: Lang }
  | { type: 'reset'; items: Item[] };

export const initialState = (items: Item[]): State => ({
  items: items.map((it, n) => ({ ...it, seq: n })),
  phase: 'closed',
  text: '',
  session: [],
  flash: null,
  secondOf: null,
  nextSeq: items.length,
});

const norm = (s: string) => s.trim().toLocaleLowerCase('de');

export function qtyLabel(item: Pick<Item, 'qty' | 'unit'>): string | null {
  if (item.qty === null) return null;
  return item.unit ? `${item.qty} ${item.unit}` : `${item.qty}×`;
}

export const raisedQty = (item: Item): string => qtyLabel({ qty: (item.qty ?? 1) + 1, ...(item.unit ? { unit: item.unit } : {}) }) ?? '';

export function catalogFor(name: string, lang: Lang) {
  return CATALOG.find((c) => norm(c.name[lang]) === norm(name)) ?? null;
}

export function rowsFor(state: State, lang: Lang): Row[] {
  const text = state.text.trim();
  if (!text) return [];
  const match = state.items.find((it) => norm(it.name[lang]) === norm(text)) ?? null;
  const own = catalogFor(text, lang);
  const typed: Row = {
    kind: 'typed',
    name: text,
    emoji: own?.emoji ?? match?.emoji ?? '',
    match,
    store: own?.store ?? match?.store ?? 'none',
    cat: own?.cat ?? match?.cat ?? 99,
  };
  const catalog: Row[] = CATALOG.filter((c) => norm(c.name[lang]).includes(norm(text)) && norm(c.name[lang]) !== norm(text))
    .slice(0, 3)
    .map((c) => ({ kind: 'catalog', name: c.name[lang], emoji: c.emoji, match: null, store: c.store, cat: c.cat }));
  if (!match) return [typed, ...catalog];
  const merge: Row = { ...typed, kind: 'merge', name: match.name[lang], emoji: match.emoji };
  const tick: Row = { ...typed, kind: 'tick', name: match.name[lang], emoji: match.emoji };
  return [merge, tick, typed, ...catalog];
}

/** Which row Enter takes. Today puts the honey tint on the as-typed row, so an exact duplicate becomes a second row. */
export function defaultRow(rows: Row[], dup: DupDefault): Row | null {
  if (!rows.length) return null;
  if (dup === 'merge') return rows[0] ?? null;
  return rows.find((r) => r.kind === 'typed') ?? rows[0] ?? null;
}

export function reduce(state: State, action: Action): State {
  switch (action.type) {
    case 'reset':
      return initialState(action.items);
    case 'open':
      return state.phase === 'open' ? state : { ...state, phase: 'open', session: [], flash: null, secondOf: null };
    case 'close':
      return { ...state, phase: 'closed', text: '', secondOf: null };
    case 'text':
      return { ...state, text: action.text, secondOf: null };
    case 'take': {
      const { row, lang } = action;
      if ((row.kind === 'merge' || row.kind === 'tick') && row.match) {
        const id = row.match.id;
        if (row.kind === 'tick') {
          return { ...state, text: '', items: state.items.filter((it) => it.id !== id), session: state.session.filter((s) => s !== id) };
        }
        return {
          ...state,
          text: '',
          items: state.items.map((it) => (it.id === id ? { ...it, qty: (it.qty ?? 1) + 1 } : it)),
          session: [...state.session.filter((s) => s !== id), id],
          flash: { id, kind: 'merged', seq: state.nextSeq },
          nextSeq: state.nextSeq + 1,
        };
      }
      const id = `new-${state.nextSeq}`;
      const name: L10n = { en: row.name, de: row.name };
      name[lang] = row.name;
      const item: Item = { id, name, emoji: row.emoji, qty: null, store: row.store, cat: row.cat, seq: state.nextSeq };
      return {
        ...state,
        text: '',
        items: [...state.items, item],
        session: [...state.session, id],
        flash: { id, kind: 'new', seq: state.nextSeq },
        secondOf: row.match?.id ?? null,
        nextSeq: state.nextSeq + 1,
      };
    }
  }
}

export interface Section {
  store: StoreId;
  items: Item[];
}

const seqOf = (it: Item) => it.seq ?? 0;

/** Store order, then category, then oldest first: a new item ends its category's group, not the store. */
export function sectionsOf(items: Item[]): Section[] {
  return STORES.map((s) => ({
    store: s.id,
    items: items.filter((it) => it.store === s.id).sort((a, b) => a.cat - b.cat || seqOf(a) - seqOf(b)),
  })).filter((s) => s.items.length > 0);
}

/** The open item a new row would follow in its store, or null when it starts the store. */
export function landingAfter(items: Item[], store: StoreId, cat: number): Item | null {
  const inStore = sectionsOf(items).find((s) => s.store === store)?.items ?? [];
  const before = inStore.filter((it) => it.cat <= cat);
  return before[before.length - 1] ?? null;
}
