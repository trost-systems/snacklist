// The demo household (the fictional Brandt family), its stores, categories, list, memory and the suggestion engine.
// Plain data and pure functions: the sandbox (sandbox.js) holds the state, the rounds (*/options.js) the options.

export const stores = [
  { id: 'lidl', name: 'Lidl' },
  { id: 'rewe', name: 'Rewe' },
  { id: 'dm', name: 'dm' },
  { id: 'market', name: 'Wochenmarkt am Kollwitzplatz' },
];
export const storeOrder = ['lidl', 'rewe', 'dm', 'market', null];

// Category names as in app/l10n (categoryProduce …); the order is a section's order inside a store.
export const categories = [
  { id: 'produce', en: 'Fruit & veg', de: 'Obst & Gemüse' },
  { id: 'bakery', en: 'Bread & bakery', de: 'Brot & Backwaren' },
  { id: 'chilled', en: 'Chilled', de: 'Kühlregal' },
  { id: 'frozen', en: 'Frozen', de: 'Tiefkühl' },
  { id: 'pantry', en: 'Pantry', de: 'Vorrat & Konserven' },
  { id: 'drinks', en: 'Drinks', de: 'Getränke' },
  { id: 'drugstore', en: 'Drugstore', de: 'Drogerie' },
  { id: 'household', en: 'Household', de: 'Haushalt' },
  { id: 'other', en: 'Other', de: 'Sonstiges' },
];

// The classifier stand-in: what the household could type, by key, with its category (classify_item's job).
export const catalog = [
  { key: 'bananas', en: 'Bananas', de: 'Bananen', cat: 'produce', emoji: '🍌' },
  { key: 'tomatoes', en: 'Tomatoes', de: 'Tomaten', cat: 'produce', emoji: '🍅' },
  { key: 'cucumber', en: 'Cucumber', de: 'Gurke', cat: 'produce', emoji: '🥒' },
  { key: 'carrots', en: 'Carrots', de: 'Karotten', cat: 'produce', emoji: '🥕' },
  { key: 'apples', en: 'Apples', de: 'Äpfel', cat: 'produce', emoji: '🍎' },
  { key: 'lemons', en: 'Lemons', de: 'Zitronen', cat: 'produce', emoji: '🍋' },
  { key: 'rolls', en: 'Bread rolls', de: 'Brötchen', cat: 'bakery', emoji: '🥖' },
  { key: 'milk', en: 'Whole milk', de: 'Vollmilch', cat: 'chilled', emoji: '🥛' },
  { key: 'butter', en: 'Butter', de: 'Butter', cat: 'chilled', emoji: '🧈' },
  { key: 'yogurt', en: 'Natural yoghurt', de: 'Naturjoghurt', cat: 'chilled', emoji: '🥣' },
  { key: 'eggs', en: 'Eggs', de: 'Eier', cat: 'chilled', emoji: '🥚' },
  { key: 'feta', en: 'Feta', de: 'Feta', cat: 'chilled', emoji: '🧀' },
  { key: 'halloumi', en: 'Halloumi', de: 'Halloumi', cat: 'chilled', emoji: '🧀' },
  { key: 'creamcheese', en: 'Cream cheese', de: 'Frischkäse', cat: 'chilled', emoji: '🧀' },
  { key: 'oatmilk', en: 'Oat milk', de: 'Haferdrink', cat: 'chilled', emoji: '🥛' },
  { key: 'buttermilk', en: 'Buttermilk', de: 'Buttermilch', cat: 'chilled', emoji: '🥛' },
  { key: 'mozzarella', en: 'Mozzarella', de: 'Mozzarella', cat: 'chilled', emoji: '🧀' },
  { key: 'honeyyog', en: 'Organic Greek-style yoghurt with honey, 500 g', de: 'Bio-Joghurt nach griechischer Art mit Honig, 500 g', cat: 'chilled', emoji: '🍯' },
  { key: 'peas', en: 'Frozen peas', de: 'TK-Erbsen', cat: 'frozen', emoji: '🫛' },
  { key: 'pasta', en: 'Spaghetti', de: 'Spaghetti', cat: 'pantry', emoji: '🍝' },
  { key: 'oliveoil', en: 'Olive oil', de: 'Olivenöl', cat: 'pantry', emoji: '🫒' },
  { key: 'coffee', en: 'Coffee beans', de: 'Kaffeebohnen', cat: 'pantry', emoji: '☕' },
  { key: 'milkrice', en: 'Rice pudding', de: 'Milchreis', cat: 'pantry', emoji: '🍚' },
  { key: 'water', en: 'Sparkling water', de: 'Sprudel', cat: 'drinks', emoji: '💧' },
  { key: 'toothpaste', en: 'Toothpaste', de: 'Zahnpasta', cat: 'drugstore', emoji: '🪥' },
  { key: 'shampoo', en: 'Shampoo', de: 'Shampoo', cat: 'drugstore', emoji: '🧴' },
  { key: 'toiletpaper', en: 'Toilet paper', de: 'Klopapier', cat: 'household', emoji: '🧻' },
  { key: 'batteries', en: 'Batteries', de: 'Batterien', cat: 'household', emoji: '🔋' },
  { key: 'basil', en: 'Basil', de: 'Basilikum', cat: 'produce', emoji: '🌿' },
  { key: 'blueberries', en: 'Blueberries', de: 'Blaubeeren', cat: 'produce', emoji: '🫐' },
  { key: 'broccoli', en: 'Broccoli', de: 'Brokkoli', cat: 'produce', emoji: '🥦' },
  { key: 'baguette', en: 'Baguette', de: 'Baguette', cat: 'bakery', emoji: '🥖' },
  { key: 'brie', en: 'Brie', de: 'Brie', cat: 'chilled', emoji: '🧀' },
  { key: 'bakingpowder', en: 'Baking powder', de: 'Backpulver', cat: 'pantry', emoji: '🧁' },
  { key: 'beer', en: 'Beer', de: 'Bier', cat: 'drinks', emoji: '🍺' },
  { key: 'sugar', en: 'Sugar', de: 'Zucker', cat: 'pantry', emoji: '🍬' },
  { key: 'spinach', en: 'Spinach', de: 'Spinat', cat: 'produce', emoji: '🥬' },
  { key: 'salt', en: 'Salt', de: 'Salz', cat: 'pantry', emoji: '🧂' },
  { key: 'soap', en: 'Soap', de: 'Seife', cat: 'drugstore', emoji: '🧼' },
];
export const byKey = Object.fromEntries(catalog.map((c) => [c.key, c]));

// The list the household has open: [key, store, qty].
export const startList = [
  ['bananas', 'lidl'], ['tomatoes', 'lidl'], ['cucumber', 'lidl'], ['rolls', 'lidl', '6'], ['milk', 'lidl', '2'], ['butter', 'lidl'], ['yogurt', 'lidl'],
  ['creamcheese', 'rewe'], ['pasta', 'rewe'], ['oliveoil', 'rewe'], ['coffee', 'rewe'], ['water', 'rewe', '6'],
  ['toothpaste', 'dm'], ['shampoo', 'dm'],
  ['batteries', null],
];
// The round RI list: shorter, nothing that "Milk" / "Milch" would match.
export const riList = [
  ['bananas', 'lidl'], ['tomatoes', 'lidl'], ['rolls', 'lidl', '6'], ['butter', 'lidl'],
  ['pasta', 'rewe'], ['coffee', 'rewe'], ['water', 'rewe', '6'],
  ['toothpaste', 'dm'],
];

// Household learning (item_store_memory and category_memory in one): key → { storeId, categoryId }.
export const startMemory = {
  bananas: 'lidl', tomatoes: 'lidl', cucumber: 'lidl', rolls: 'lidl', milk: 'lidl', butter: 'lidl', yogurt: 'lidl', eggs: 'lidl', peas: 'lidl',
  creamcheese: 'rewe', pasta: 'rewe', oliveoil: 'rewe', coffee: 'rewe', water: 'rewe', feta: 'rewe', oatmilk: 'rewe', buttermilk: 'rewe',
  toothpaste: 'dm', shampoo: 'dm', toiletpaper: 'dm',
  honeyyog: 'market', apples: 'market', basil: 'market', blueberries: 'market', baguette: 'lidl', sugar: 'rewe', spinach: 'market',
};
// What the household bought before (history rows, suggest_history), newest first.
export const startHistory = ['basil', 'blueberries', 'baguette', 'sugar', 'spinach', 'eggs', 'feta', 'toiletpaper', 'apples', 'oatmilk', 'honeyyog', 'peas', 'buttermilk', 'milk', 'butter', 'bananas', 'tomatoes', 'cucumber', 'rolls', 'yogurt', 'creamcheese', 'pasta', 'oliveoil', 'coffee', 'water', 'toothpaste', 'shampoo'];
// The usuals before anything is typed: due ones, then recent ones (list_cubit dueUsuals, recentUsuals).
export const usuals = { due: ['eggs', 'toiletpaper'], recent: ['oatmilk', 'apples', 'feta', 'milk'] };

export const storeName = (id, lang) => (id ? stores.find((s) => s.id === id).name : T[lang].noStore);
export const catName = (id, lang) => categories.find((c) => c.id === id)?.[lang] ?? categories.at(-1)[lang];

const norm = (s) => s.toLowerCase().normalize('NFC').trim();
// suggest_match: the same name, a prefix, a word prefix, in-word from 4 letters.
export const matches = (name, text) => {
  const n = norm(name), t = norm(text);
  if (!t) return false;
  return n.startsWith(t) || n.split(/[\s-]+/).some((w) => w.startsWith(t)) || (t.length >= 4 && n.includes(t));
};
export const keyFor = (text, lang) => catalog.find((c) => norm(c[lang]) === norm(text))?.key ?? null;

// classify_item: memory, then the dictionary, then Other.
export const classify = (key, memory) => memory[key]?.categoryId ?? byKey[key]?.cat ?? 'other';

// ST1: the household's most-used store for a category, counted over the open list and the memory.
export const usualStore = (cat, list, memory) => {
  const n = {};
  for (const it of list) if (it.categoryId === cat && it.storeId) n[it.storeId] = (n[it.storeId] ?? 0) + 1;
  for (const [k, m] of Object.entries(memory)) if (m.storeId && (m.categoryId ?? byKey[k]?.cat) === cat) n[m.storeId] = (n[m.storeId] ?? 0) + 1;
  const best = Object.entries(n).sort((a, b) => b[1] - a[1] || storeOrder.indexOf(a[0]) - storeOrder.indexOf(b[0]))[0];
  return best ? best[0] : null;
};

// A suggestion row: { source, key|null, name, storeId, categoryId, forText }.
export const itemKey = (row) => row.key ?? `typed:${norm(row.name)}`;
const onList = (list) => new Set(list.filter((it) => !it.bought).map(itemKey));

// guess_store / parse_item's store: the remembered one, else the category's store (category_store: dm for drugstore).
export const guessStore = (key, categoryId, memory) => (key && memory[key]?.storeId) || (categoryId === 'drugstore' ? 'dm' : null);

// suggest_entries (20261106163919_hardware_categories.sql): the typed row and catalog rows carry parse_item's store,
// history rows guess_store's; up to 8 rows: typed, 3 history, 3 catalog (pack, size and brand rows left out).
export const serverRows = (text, { lang, list, memory, history }) => {
  const t = text.trim();
  if (!t) return [];
  const key = keyFor(t, lang);
  const near = t.length >= 3 ? catalog.find((c) => matches(c[lang], t)) : null;
  const typedCat = key ? classify(key, memory) : (near?.cat ?? 'other');
  const typed = { source: 'typed', key, name: key ? byKey[key][lang] : t, storeId: guessStore(key, typedCat, memory), categoryId: typedCat, forText: t };
  const skip = onList(list);
  const seen = new Set([key ?? `typed:${norm(t)}`]);
  const rows = [typed];
  for (const k of history) {
    if (rows.length >= 4 || seen.has(k) || skip.has(k) || !matches(byKey[k][lang], t)) continue;
    seen.add(k);
    rows.push({ source: 'history', key: k, name: byKey[k][lang], storeId: guessStore(k, classify(k, memory), memory), categoryId: classify(k, memory), forText: t });
  }
  let cat = 0;
  for (const c of catalog) {
    if (cat >= 3 || seen.has(c.key) || skip.has(c.key) || !matches(c[lang], t)) continue;
    seen.add(c.key);
    cat++;
    rows.push({ source: 'catalog', key: c.key, name: c[lang], storeId: guessStore(c.key, classify(c.key, memory), memory), categoryId: classify(c.key, memory), forText: t });
  }
  return rows;
};

// _offline: the typed line and the usuals that match, built on the device (no store, no category).
export const deviceRows = (text, { lang, list }) => {
  const t = text.trim();
  if (!t) return [];
  const key = keyFor(t, lang);
  const skip = onList(list);
  const rows = [{ source: 'typed', key, name: key ? byKey[key][lang] : t, storeId: null, categoryId: null, forText: t, device: true }];
  for (const k of [...usuals.due, ...usuals.recent]) if (k !== key && !skip.has(k) && matches(byKey[k][lang], t)) rows.push({ source: 'history', key: k, name: byKey[k][lang], storeId: null, categoryId: null, forText: t, device: true });
  return rows;
};

// The rows before anything is typed: due, then recent usuals, those on the list left out. Like sheetRows they carry
// only the name: no store, no category (the server's insert trigger fills both in).
export const emptyRows = ({ lang, list }) => {
  const skip = onList(list);
  return [...usuals.due.map((k) => ['due', k]), ...usuals.recent.map((k) => ['recent', k])]
    .filter(([, k]) => !skip.has(k))
    .map(([source, k]) => ({ source, key: k, name: byKey[k][lang], storeId: null, categoryId: null, forText: '' }));
};

export const T = {
  en: {
    addHint: 'What do you need?',
    sheetHint: 'Tap to add · ↵ takes the first suggestion',
    added: (n, s) => `Added: ${n} → ${s}`,
    addedItem: (n) => `Added: ${n}`,
    already: (n) => `${n} is already on the list`,
    undo: 'Undo',
    noStore: 'No store',
    chipStore: 'Store',
    chipCat: 'Category',
    src: { typed: 'As typed', history: 'Bought before', catalog: 'From the catalog', due: 'Due again', recent: 'Recently used' },
    typeToSuggest: 'Type to see suggestions',
    close: 'Close',
    clear: 'Clear',
    mic: 'Dictate',
    items: (n) => (n === 1 ? 'item' : 'items'),
    home: 'Home',
    edit: 'Edit',
    tabs: ['List', 'History', 'More'],
    name: 'Name',
    cancel: 'Cancel',
    done: 'Done',
    storeL: 'Store',
    catL: 'Section',
    hold: 'Tap ticks off · hold to edit',
  },
  de: {
    addHint: 'Was brauchst du?',
    sheetHint: 'Antippen fügt hinzu · ↵ nimmt den ersten Vorschlag',
    added: (n, s) => `Hinzugefügt: ${n} → ${s}`,
    addedItem: (n) => `Hinzugefügt: ${n}`,
    already: (n) => `${n} steht schon auf der Liste`,
    undo: 'Rückgängig',
    noStore: 'Ohne Laden',
    chipStore: 'Laden',
    chipCat: 'Kategorie',
    src: { typed: 'Wie getippt', history: 'Schon mal gekauft', catalog: 'Aus dem Katalog', due: 'Wieder fällig', recent: 'Zuletzt verwendet' },
    typeToSuggest: 'Tippe, um Vorschläge zu sehen',
    close: 'Schließen',
    clear: 'Leeren',
    mic: 'Diktieren',
    items: () => 'Artikel',
    home: 'Zuhause',
    edit: 'Anpassen',
    tabs: ['Liste', 'Verlauf', 'Mehr'],
    name: 'Name',
    cancel: 'Abbrechen',
    done: 'Fertig',
    storeL: 'Laden',
    catL: 'Kategorie',
    hold: 'Tippen hakt ab · Halten bearbeitet',
  },
};
