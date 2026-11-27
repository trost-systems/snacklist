export type Lang = 'en' | 'de';
export type L10n = Record<Lang, string>;

export type StoreId = 'rewe' | 'dm' | 'none';

export interface Store {
  id: StoreId;
  name: L10n;
  /** Production tints a store's rule; tokens only here. */
  tint: string;
}

export const STORES: Store[] = [
  { id: 'rewe', name: { en: 'REWE', de: 'REWE' }, tint: 'var(--hl-color-cobalt)' },
  { id: 'dm', name: { en: 'dm', de: 'dm' }, tint: 'var(--hl-color-mint-edge)' },
  { id: 'none', name: { en: 'No store', de: 'Ohne Laden' }, tint: 'var(--hl-color-divider)' },
];

export interface Item {
  id: string;
  name: L10n;
  emoji: string;
  qty: number | null;
  unit?: string;
  store: StoreId;
  /** Category order inside a store: production sorts by category, then adds at the end of that category (hide-categories drops only the headings). */
  cat: number;
  /** Insertion order: the oldest first inside a category. */
  seq?: number;
}

const i = (id: string, en: string, de: string, emoji: string, store: StoreId, cat: number, qty: number | null = null, unit?: string): Item => ({
  id,
  name: { en, de },
  emoji,
  qty,
  ...(unit ? { unit } : {}),
  store,
  cat,
});

const MANY: Item[] = [
  i('bananas', 'Bananas', 'Bananen', '🍌', 'rewe', 1, 6),
  i('apples', 'Apples', 'Äpfel', '🍎', 'rewe', 1, 1, 'kg'),
  i('rolls', 'Bread rolls', 'Brötchen', '🥖', 'rewe', 2, 4),
  i('milk', 'Whole milk', 'Vollmilch', '🥛', 'rewe', 3, 2),
  i('butter', 'Butter', 'Butter', '🧈', 'rewe', 3),
  i('pasta', 'Pasta', 'Nudeln', '🍝', 'rewe', 4),
  i('rice', 'Rice', 'Reis', '🍚', 'rewe', 4),
  i('chocolate', 'Chocolate', 'Schokolade', '🍫', 'rewe', 5),
  i('juice', 'Apple juice', 'Apfelsaft', '🧃', 'rewe', 6),
  i('water', 'Sparkling water', 'Mineralwasser', '💧', 'rewe', 6),
  i('toothpaste', 'Toothpaste', 'Zahnpasta', '🪥', 'dm', 7),
  i('showergel', 'Shower gel', 'Duschgel', '🧴', 'dm', 7),
  i('dishsoap', 'Dish soap', 'Spülmittel', '🧽', 'dm', 8),
  i('trashbags', 'Trash bags', 'Müllbeutel', '🗑️', 'none', 8),
  i('candles', 'Tea lights', 'Teelichter', '🕯️', 'none', 9),
];

const LONG: Item[] = [
  i('oatmilk', 'Organic oat drink, barista edition, unsweetened 1 l', 'Bio-Haferdrink Barista-Edition ungesüßt 1 l', '🥛', 'rewe', 3, 3),
  i('bread', 'Spelt wholegrain sunflower seed bread from the farm shop', 'Dinkel-Vollkorn-Sonnenblumenkernbrot vom Hofladen', '🍞', 'rewe', 2),
  i('bananas', 'Bananas', 'Bananen', '🍌', 'rewe', 1, 6),
  i('tomatoes', 'Cherry vine tomatoes, the small sweet ones', 'Kirschrispentomaten, die kleinen süßen', '🍅', 'rewe', 1, 2),
  i('toothpaste', 'Toothpaste for sensitive teeth, extra gentle', 'Zahnpasta für empfindliche Zähne, extra sanft', '🪥', 'dm', 7),
  i('trashbags', 'Trash bags 35 l with drawstring', 'Müllbeutel 35 l mit Zugband', '🗑️', 'none', 8),
];

export const FIXTURES = ['empty', 'one', 'many', 'long', 'duplicate'] as const;
export type Fixture = (typeof FIXTURES)[number];

export const FIXTURE_LABEL: Record<Fixture, string> = {
  empty: 'Empty list',
  one: '1 item',
  many: 'Many items (15)',
  long: 'Long names',
  duplicate: 'Already on the list',
};

export function fixtureItems(f: Fixture): Item[] {
  if (f === 'empty') return [];
  if (f === 'one') return MANY.slice(0, 1);
  if (f === 'long') return LONG;
  return MANY;
}

/** What the person types in each fixture's scripted moments; the duplicate fixture types an item already on the list. */
export function scriptFor(f: Fixture): { typing: L10n; adds: L10n[] } {
  if (f === 'duplicate') return { typing: { en: 'Bananas', de: 'Bananen' }, adds: [{ en: 'Bananas', de: 'Bananen' }, { en: 'Eggs', de: 'Eier' }] };
  if (f === 'long') return { typing: { en: 'Organic', de: 'Bio' }, adds: [{ en: 'Organic free-range eggs, size M', de: 'Bio-Freilandeier Größe M' }, { en: 'Eggs', de: 'Eier' }] };
  return { typing: { en: 'Milk', de: 'Milch' }, adds: [{ en: 'Milk', de: 'Milch' }, { en: 'Eggs', de: 'Eier' }] };
}

/** Items typed in the sandbox take the store they were last bought in, as the catalog suggests it. */
export interface CatalogEntry {
  name: L10n;
  emoji: string;
  store: StoreId;
  cat: number;
}

export const CATALOG: CatalogEntry[] = [
  { name: { en: 'Milk', de: 'Milch' }, emoji: '🥛', store: 'rewe', cat: 3 },
  { name: { en: 'Buttermilk', de: 'Milchreis' }, emoji: '🥛', store: 'rewe', cat: 4 },
  { name: { en: 'Oat milk', de: 'Milchbrötchen' }, emoji: '🥯', store: 'rewe', cat: 2 },
  { name: { en: 'Eggs', de: 'Eier' }, emoji: '🥚', store: 'rewe', cat: 3 },
  { name: { en: 'Banana bread', de: 'Bananenbrot' }, emoji: '🍞', store: 'rewe', cat: 2 },
  { name: { en: 'Organic free-range eggs, size M', de: 'Bio-Freilandeier Größe M' }, emoji: '🥚', store: 'rewe', cat: 3 },
  { name: { en: 'Organic yoghurt', de: 'Bio-Joghurt' }, emoji: '🥣', store: 'rewe', cat: 3 },
  { name: { en: 'Shampoo', de: 'Shampoo' }, emoji: '🧴', store: 'dm', cat: 7 },
  { name: { en: 'Cheese', de: 'Käse' }, emoji: '🧀', store: 'rewe', cat: 3 },
  { name: { en: 'Coffee', de: 'Kaffee' }, emoji: '☕', store: 'rewe', cat: 6 },
];

export const COPY = {
  en: {
    household: 'Brandt family',
    list: 'Shopping list',
    edit: 'Edit',
    items: (n: number) => (n === 1 ? 'item' : 'items'),
    tabs: ['List', 'More'],
    fieldHint: 'What do you need?',
    sheetHint: 'Tap to add · ↵ takes the first suggestion',
    typeToSuggest: 'Type to see suggestions',
    asTyped: 'As typed',
    catalog: 'From the catalog',
    merge: 'Merge',
    tickOff: 'Tick off',
    clear: 'Clear',
    close: 'Close',
    noStore: 'No store',
    storeChip: (s: string) => `Store: ${s}`,
    details: 'Details',
    emptyList: 'Your list is empty. Type what you need below.',
    send: 'send',
    space: 'space',
    // AE1
    ae1Behind: (n: number) => (n === 0 ? 'Your list is empty. What you add shows up here.' : `Your list (${n} ${n === 1 ? 'item' : 'items'}) is behind this sheet.`),
    ae1BehindSub: 'Tap here or send an empty field to see it.',
    ae1Lands: (list: string) => `Each item goes onto ${list}, under its store. Add as many as you like.`,
    ae1Just: (n: number, total: number) => `Just added: ${n} · ${total} on the list`,
    ae1Onto: (store: string) => `→ ${store}`,
    ae1HintLine: 'Send adds it to the list · the sheet stays open for the next one',
    ae1DupNote: (name: string, qty: string) => `${name} is already on the list${qty ? ` (${qty})` : ''}. Pick what to do:`,
    ae1MergeSub: 'Adds 1 to the one on the list',
    ae1TickSub: 'Ticks off the one on the list',
    ae1SecondSub: (name: string) => `Puts a second ${name} on the list`,
    ae1SecondDone: (name: string) => `${name} is on the list twice now.`,
    // AE2 / AE5 / AE4 / AE3
    newTag: 'New',
    plusOne: (qty: string) => `+1 → ${qty}`,
    landsHere: 'Lands here',
    landingHint: 'Type an item to see where it lands.',
    landsIn: (store: string) => `Lands in ${store}`,
    done: 'Done',
  },
  de: {
    household: 'Familie Brandt',
    list: 'Einkaufsliste',
    edit: 'Anpassen',
    items: () => 'Artikel',
    tabs: ['Liste', 'Mehr'],
    fieldHint: 'Was brauchst du?',
    sheetHint: 'Antippen fügt hinzu · ↵ nimmt den ersten Vorschlag',
    typeToSuggest: 'Tippe, um Vorschläge zu sehen',
    asTyped: 'Wie getippt',
    catalog: 'Aus dem Katalog',
    merge: 'Zusammenführen',
    tickOff: 'Abhaken',
    clear: 'Eingabe leeren',
    close: 'Schließen',
    noStore: 'Ohne Laden',
    storeChip: (s: string) => `Laden: ${s}`,
    details: 'Eigenschaften',
    emptyList: 'Die Liste ist leer. Tippe unten ein, was fehlt.',
    send: 'Senden',
    space: 'Leerzeichen',
    ae1Behind: (n: number) => (n === 0 ? 'Die Liste ist leer. Was du hinzufügst, steht dann hier.' : `Deine Liste (${n} Artikel) liegt hinter diesem Fenster.`),
    ae1BehindSub: 'Tippe hierhin oder sende ein leeres Feld, um sie zu sehen.',
    ae1Lands: (list: string) => `Jeder Artikel kommt auf die ${list}, unter seinen Laden. Füge so viele hinzu, wie du willst.`,
    ae1Just: (n: number, total: number) => `Gerade hinzugefügt: ${n} · ${total} auf der Liste`,
    ae1Onto: (store: string) => `→ ${store}`,
    ae1HintLine: 'Senden setzt es auf die Liste · das Fenster bleibt für den nächsten offen',
    ae1DupNote: (name: string, qty: string) => `${name} steht schon auf der Liste${qty ? ` (${qty})` : ''}. Was soll passieren?`,
    ae1MergeSub: 'Zählt 1 zum vorhandenen dazu',
    ae1TickSub: 'Hakt den vorhandenen ab',
    ae1SecondSub: (name: string) => `Setzt ${name} ein zweites Mal auf die Liste`,
    ae1SecondDone: (name: string) => `${name} steht jetzt zweimal auf der Liste.`,
    newTag: 'Neu',
    plusOne: (qty: string) => `+1 → ${qty}`,
    landsHere: 'Kommt hierhin',
    landingHint: 'Tippe einen Artikel, um zu sehen, wo er landet.',
    landsIn: (store: string) => `Kommt zu ${store}`,
    done: 'Fertig',
  },
};
export type Copy = (typeof COPY)['en'];
