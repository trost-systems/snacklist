// Mock household (the fictional Familie Brandt), the app's strings, and the one reducer every option shares.
// Strings marked ARB are the app's own keys (app/l10n/app_*.arb); the round adds no new UI text.

export const copy = {
  en: {
    hint: 'What do you need?', // addFieldHint
    qty: 'Qty', // itemQuantity
    less: 'One less', // quantityMinus
    more: 'One more', // quantityPlus
    brand: 'Brand', // fieldBrand
    brandNone: 'no brand', // brandNone
    details: 'Details', // fieldProperties
    detailsEx: 'e.g. organic, 1 l', // propertiesExample
    noStore: 'No store', // noStore
    newStore: 'New store', // storeNew
    close: 'Close', // close
    undo: 'Undo', // undo
    justAdded: 'Just added', // justAdded
    addedTo: (n, s) => `Added: ${n} → ${s}`, // addedTo
    price: 'Price', // priceAdd
    list: 'List', more_: 'More', customise: 'Edit', items: 'items', // listEdit
  },
  de: {
    hint: 'Was brauchst du?',
    qty: 'Menge',
    less: 'Eins weniger',
    more: 'Eins mehr',
    brand: 'Marke',
    brandNone: 'ohne Marke',
    details: 'Eigenschaften',
    detailsEx: 'z. B. Bio, 1 l',
    noStore: 'Ohne Laden',
    newStore: 'Neuer Laden',
    close: 'Schließen',
    undo: 'Rückgängig',
    justAdded: 'Gerade hinzugefügt',
    addedTo: (n, s) => `Hinzugefügt: ${n} → ${s}`,
    price: 'Preis',
    list: 'Liste', more_: 'Mehr', customise: 'Anpassen', items: 'Artikel',
  },
};

// Plain-text store names and no logos (Legal N-292).
export const stores = [
  { id: 'edeka', name: 'Edeka' },
  { id: 'lidl', name: 'Lidl' },
  { id: 'dm', name: 'dm' },
  { id: 'rewe', name: 'REWE' },
  { id: 'markt', name: { en: 'Farmers’ market', de: 'Wochenmarkt' } },
];

export const categories = [
  { id: 'produce', en: 'Fruit & veg', de: 'Obst & Gemüse' },
  { id: 'bakery', en: 'Bread & bakery', de: 'Brot & Backwaren' },
  { id: 'chilled', en: 'Chilled', de: 'Kühlregal' },
  { id: 'pantry', en: 'Pantry', de: 'Vorrat & Konserven' },
  { id: 'drinks', en: 'Drinks', de: 'Getränke' },
  { id: 'household', en: 'Household', de: 'Haushalt' },
];

// What typing suggests (the catalog and history), with the store and category the server would pick.
export const catalog = [
  { key: 'oatmilk', en: 'Oat milk', de: 'Hafermilch', emoji: '🥛', cat: 'drinks', store: 'edeka' },
  { key: 'oats', en: 'Oats', de: 'Haferflocken', emoji: '🥣', cat: 'pantry', store: 'edeka' },
  { key: 'bread', en: 'Bread', de: 'Brot', emoji: '🍞', cat: 'bakery', store: 'edeka' },
  { key: 'rolls', en: 'Bread rolls', de: 'Brötchen', emoji: '🥖', cat: 'bakery', store: 'edeka' },
  { key: 'eggs', en: 'Eggs', de: 'Eier', emoji: '🥚', cat: 'chilled', store: 'edeka' },
  { key: 'applejuice', en: 'Apple juice', de: 'Apfelsaft', emoji: '🧃', cat: 'drinks', store: 'edeka' },
];

// Already on the list before the sheet opens: hidden behind the open sheet, back once it closes.
const onList = [
  { key: 'bananas', en: 'Bananas', de: 'Bananen', emoji: '🍌', cat: 'produce', store: null, qty: '6×' },
  { key: 'apples', en: 'Apples', de: 'Äpfel', emoji: '🍎', cat: 'produce', store: null, qty: '1 kg' },
  { key: 'pasta', en: 'Pasta', de: 'Nudeln', emoji: '🍝', cat: 'pantry', store: null, qty: '' },
  { key: 'potty', en: 'Potty', de: 'Töpfchen', emoji: '⬡', cat: 'household', store: 'dm', qty: '' },
];

export const initial = () => ({
  items: onList.map((c, i) => ({ id: `old${i}`, ...c, details: '', brand: '', old: true })),
  added: [],
  cur: null,
  text: '',
  open: null,
  sheet: true,
  seq: 0,
});

export const t = (lang) => copy[lang];
export const nameOf = (x, lang) => (typeof x === 'string' ? x : x[lang]);
export const storeName = (id, lang) => (id ? nameOf(stores.find((s) => s.id === id).name, lang) : copy[lang].noStore);
export const catName = (id, lang) => categories.find((c) => c.id === id)[lang];
export const curItem = (s) => s.items.find((i) => i.id === s.cur) ?? null;
export const lastTwo = (s) => s.added.slice(-2).map((id) => s.items.find((i) => i.id === id));

export const suggestions = (s, lang) => {
  const q = s.text.trim().toLowerCase();
  if (!q) return [];
  return catalog.filter((c) => c[lang].toLowerCase().startsWith(q) || c.en.toLowerCase().startsWith(q)).slice(0, 3);
};

const step = (qty, up) => {
  const n = qty === '' ? 1 : Number.parseInt(qty, 10);
  if (Number.isNaN(n)) return qty;
  const next = up ? n + 1 : n - 1;
  return next <= 1 ? '' : String(next);
};

const patch = (s, id, f) => ({ ...s, items: s.items.map((i) => (i.id === id ? { ...i, ...f(i) } : i)) });

// One reducer for every option. An option's layout decides which actions it offers, never what they do,
// except `where`: AS2's single chip, whose panel stays open after the store and closes after the category.
export const act = (s, a, lang) => {
  const [verb, arg] = a.split(':');
  switch (verb) {
    case 'type':
      return { ...s, text: arg ?? '', open: null };
    case 'take':
    case 'enter': {
      const pick = suggestions(s, lang)[verb === 'take' ? Number(arg) : 0];
      if (!pick && verb === 'enter' && !s.text.trim()) return { ...s, sheet: false, open: null };
      if (!pick && verb === 'enter') {
        // Free text: a new item, no store, a category the server would guess (pantry here).
        const id = `n${s.seq}`;
        const name = s.text.trim();
        const item = { id, key: name, en: name, de: name, emoji: '⬡', cat: 'pantry', store: null, qty: '', details: '', brand: '' };
        return { ...s, items: [...s.items, item], added: [...s.added, id], cur: id, text: '', open: null, seq: s.seq + 1 };
      }
      if (!pick) return s;
      const id = `n${s.seq}`;
      const item = { id, key: pick.key, en: pick.en, de: pick.de, emoji: pick.emoji, cat: pick.cat, store: pick.store, qty: '', details: '', brand: '' };
      return { ...s, items: [...s.items, item], added: [...s.added, id], cur: id, text: '', open: null, seq: s.seq + 1 };
    }
    case 'qty+':
    case 'qty-':
      return patch(s, s.cur, (i) => ({ qty: step(i.qty, verb === 'qty+') }));
    case 'qty':
      return patch(s, s.cur, () => ({ qty: arg ?? '' }));
    case 'open':
      return { ...s, open: s.open === arg ? null : arg, text: '' };
    case 'store':
      return { ...patch(s, s.cur, () => ({ store: arg === 'none' ? null : arg })), open: s.open === 'where' ? 'where' : null };
    case 'cat':
      return { ...patch(s, s.cur, () => ({ cat: arg })), open: null };
    case 'details':
      return patch(s, s.cur, () => ({ details: arg ?? '' }));
    case 'brand':
      return patch(s, s.cur, () => ({ brand: arg ?? '' }));
    case 'select':
      return s.sheet && s.added.slice(-2).includes(arg) ? { ...s, cur: arg, open: null, text: '' } : s;
    case 'noop':
      return s;
    case 'dismiss':
      return { ...s, sheet: false, open: null, text: '' };
    default:
      throw new Error(`unknown action ${a}`);
  }
};

export const run = (actions, lang, from = initial()) => actions.reduce((s, a) => act(s, a, lang), from);
