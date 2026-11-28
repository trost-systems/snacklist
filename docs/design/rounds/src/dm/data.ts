export type Lang = 'en' | 'de';
export type L10n = Record<Lang, string>;

export type StoreId = 'rewe' | 'dm' | 'none';

export const STORES: { id: StoreId; name: L10n; tint: string }[] = [
  { id: 'rewe', name: { en: 'REWE', de: 'REWE' }, tint: 'var(--hl-color-cobalt)' },
  { id: 'dm', name: { en: 'dm', de: 'dm' }, tint: 'var(--hl-color-mint-edge)' },
  { id: 'none', name: { en: 'No store', de: 'Ohne Laden' }, tint: 'var(--hl-color-divider)' },
];

export interface Item {
  id: string;
  name: L10n;
  emoji: string;
  /** Production's Menge text: "6" (a count, shown 6×), "500 g", "1 kg"; null is one. */
  qty: string | null;
  store: StoreId;
  /** Category order inside a store. */
  cat: number;
}

const i = (id: string, en: string, de: string, emoji: string, store: StoreId, cat: number, qty: string | null = null): Item => ({
  id,
  name: { en, de },
  emoji,
  qty,
  store,
  cat,
});

const LIST: Item[] = [
  i('bananas', 'Bananas', 'Bananen', '🍌', 'rewe', 1, '6'),
  i('apples', 'Apples', 'Äpfel', '🍎', 'rewe', 1, '1 kg'),
  i('rolls', 'Bread rolls', 'Brötchen', '🥖', 'rewe', 2, '4'),
  i('flour', 'Flour', 'Mehl', '🌾', 'rewe', 2, '500 g'),
  i('milk', 'Whole milk', 'Vollmilch', '🥛', 'rewe', 3, '2'),
  i('butter', 'Butter', 'Butter', '🧈', 'rewe', 3),
  i('pasta', 'Pasta', 'Nudeln', '🍝', 'rewe', 4),
  i('rice', 'Rice', 'Reis', '🍚', 'rewe', 4),
  i('chocolate', 'Chocolate', 'Schokolade', '🍫', 'rewe', 5),
  i('toothpaste', 'Toothpaste', 'Zahnpasta', '🪥', 'dm', 7),
  i('omega3', 'Omega 3', 'Omega 3', '💊', 'dm', 7),
  i('showergel', 'Shower gel', 'Duschgel', '🧴', 'dm', 7),
  i('trashbags', 'Bin bags', 'Müllbeutel', '🗑️', 'none', 8),
  i('candles', 'Tea lights', 'Teelichter', '🕯️', 'none', 9),
];

const LONG_ITEM = i('oatdrink', 'Organic oat drink, barista edition, unsweetened', 'Bio-Haferdrink Barista-Edition, ungesüßt', '🥛', 'rewe', 3, '3');

export const FIXTURES = ['exact', 'count', 'unit', 'unitTyped', 'none', 'long'] as const;
export type Fixture = (typeof FIXTURES)[number];

/** The scenario control: what is typed, and the list it is typed against. */
export const SCENARIOS: Record<Fixture, { label: string; typed: L10n; items: () => Item[] }> = {
  exact: { label: 'Exact name: Omega 3 (dm)', typed: { en: 'Omega 3', de: 'Omega 3' }, items: () => LIST },
  count: { label: 'Typed amount: Omega 3 2', typed: { en: 'Omega 3 2', de: 'Omega 3 2' }, items: () => LIST },
  unit: { label: 'Unit item: Mehl (500 g)', typed: { en: 'Flour', de: 'Mehl' }, items: () => LIST },
  unitTyped: { label: 'Unit typed: Mehl 1kg', typed: { en: 'Flour 1kg', de: 'Mehl 1kg' }, items: () => LIST },
  none: { label: 'No match: Hafermilch', typed: { en: 'Oat milk', de: 'Hafermilch' }, items: () => LIST },
  long: { label: 'Long name (3×)', typed: { en: LONG_ITEM.name.en, de: LONG_ITEM.name.de }, items: () => [...LIST.slice(0, 5), LONG_ITEM, ...LIST.slice(5)] },
};

/** Typed names the sandbox knows besides the list: store and emoji the catalog would give them. */
export const CATALOG: { name: L10n; emoji: string; store: StoreId; cat: number }[] = [
  { name: { en: 'Oat milk', de: 'Hafermilch' }, emoji: '🥛', store: 'rewe', cat: 3 },
  { name: { en: 'Omega 3 capsules', de: 'Omega-3-Kapseln' }, emoji: '💊', store: 'dm', cat: 7 },
  { name: { en: 'Wholemeal flour', de: 'Vollkornmehl' }, emoji: '🌾', store: 'rewe', cat: 2 },
  { name: { en: 'Eggs', de: 'Eier' }, emoji: '🥚', store: 'rewe', cat: 3 },
  { name: { en: 'Banana bread', de: 'Bananenbrot' }, emoji: '🍞', store: 'rewe', cat: 2 },
  { name: { en: 'Oat flakes', de: 'Haferflocken' }, emoji: '🥣', store: 'rewe', cat: 4 },
];

export const COPY = {
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
    send: 'Senden',
    space: 'Leerzeichen',
    newTag: 'Neu',
    merged: (item: string) => `Zusammengeführt: ${item}`,
    ticked: (name: string) => `${name} abgehakt`,
    added: (name: string) => `Hinzugefügt: ${name}`,
    // DM1 actions under the row
    plus: (amount: string, result: string) => `+${amount} → ${result}`,
    raise: (name: string, result: string) => `${name} auf ${result} erhöhen`,
    dm1Hint: (name: string) => `${name} steht schon auf der Liste: oben`,
    newEntry: 'Als neuen Eintrag',
    enterDoes: (what: string) => `↵ ${what}`,
    // DM2 worded buttons
    dm2Kicker: (amount: string) => `+${amount} dazu`,
    dm2Second: 'Als zweiter Eintrag',
    // DM3 one sentence
    dm3Line: (name: string, qty: string, store: string) => `${name} steht schon auf der Liste (${qty}, ${store}).`,
    dm3Merge: (result: string) => `Auf ${result} erhöhen`,
    dm3Tick: 'Abhaken: hab ich schon',
    dm3New: (name: string) => `${name} zusätzlich als eigenen Eintrag`,
    // DM4 card
    dm4Title: 'Schon auf der Liste',
    dm4Or: 'Oder neu hinzufügen',
    // DM5 choose, then confirm
    dm5Ask: (name: string) => `${name} steht schon drauf. Was möchtest du?`,
    dm5ChooseMerge: 'Mehr davon',
    dm5ChooseTick: 'Abhaken',
    dm5ChooseNew: 'Neuer Eintrag',
    dm5Amount: 'Menge dazu',
    dm5Less: 'weniger',
    dm5More: 'mehr',
    dm5DoMerge: (result: string) => `Auf ${result} erhöhen`,
    dm5DoTick: (name: string) => `${name} abhaken`,
    dm5DoNew: (name: string) => `${name} neu hinzufügen`,
  },
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
    send: 'send',
    space: 'space',
    newTag: 'New',
    merged: (item: string) => `Merged: ${item}`,
    ticked: (name: string) => `${name} ticked off`,
    added: (name: string) => `Added: ${name}`,
    plus: (amount: string, result: string) => `+${amount} → ${result}`,
    raise: (name: string, result: string) => `raise ${name} to ${result}`,
    dm1Hint: (name: string) => `${name} is already on the list: above`,
    newEntry: 'As a new entry',
    enterDoes: (what: string) => `↵ ${what}`,
    dm2Kicker: (amount: string) => `Add ${amount}`,
    dm2Second: 'As a second entry',
    dm3Line: (name: string, qty: string, store: string) => `${name} is already on the list (${qty}, ${store}).`,
    dm3Merge: (result: string) => `Raise it to ${result}`,
    dm3Tick: 'Tick off: I have it already',
    dm3New: (name: string) => `Add ${name} as a separate entry`,
    dm4Title: 'Already on the list',
    dm4Or: 'Or add new',
    dm5Ask: (name: string) => `${name} is already on it. What would you like?`,
    dm5ChooseMerge: 'More of it',
    dm5ChooseTick: 'Tick off',
    dm5ChooseNew: 'New entry',
    dm5Amount: 'Amount to add',
    dm5Less: 'less',
    dm5More: 'more',
    dm5DoMerge: (result: string) => `Raise to ${result}`,
    dm5DoTick: (name: string) => `Tick off ${name}`,
    dm5DoNew: (name: string) => `Add ${name} as new`,
  },
};
export type Copy = (typeof COPY)['de'];
