// Mock data only: the fictional Brandt family (the how-to clips' household), never real users' lists.
// The list is job 350's demo list (4 stores, 12 items, categories hidden); prices are set on 8 of 12 so the
// TE1 total (job 348) shows: stores with a price only, „mind.“ where a store has unpriced items, one „ohne Preis“.
export const household = { de: 'Familie Brandt', en: 'Brandt family' };
export const members = [{ name: 'Mia', initial: 'M' }, { name: 'Jonas', initial: 'J' }];
export const lists = [
  { id: 'main', de: 'Einkaufsliste', en: 'Shopping list', count: 12 },
  { id: 'bbq', de: 'Grillabend', en: 'BBQ night', count: 5 },
];
export const otherHousehold = { de: 'WG Lindenstraße', en: 'Linden St. flat', lists: [{ de: 'Einkaufsliste', en: 'Shopping list', count: 3 }] };

export const stores = [
  { id: 'market', de: 'Wochenmarkt', en: 'Farmers market' },
  { id: 'bakery', de: 'Bäckerei', en: 'Bakery' },
  { id: 'super', de: 'Supermarkt', en: 'Supermarket' },
  { id: 'drug', de: 'Drogerie', en: 'Drugstore' },
];

// price in cents for the whole row; null: no price yet („+ Preis“).
export const items = [
  { id: 'apples', store: 'market', de: 'Äpfel', en: 'Apples', qty: '1 kg', detail: 'Elstar', emoji: '🍎', price: 349 },
  { id: 'tomatoes', store: 'market', de: 'Tomaten', en: 'Tomatoes', qty: '500 g', emoji: '🍅', price: null },
  { id: 'bread', store: 'bakery', de: 'Bauernbrot', en: 'Farmhouse bread', qty: '', emoji: '🍞', price: 420 },
  { id: 'rolls', store: 'bakery', de: 'Brötchen', en: 'Bread rolls', qty: '6', emoji: '🥖', price: 240 },
  { id: 'milk', store: 'super', de: 'Vollmilch', en: 'Whole milk', qty: '2', emoji: '🥛', price: 238 },
  { id: 'yogurt', store: 'super', de: 'Joghurt', en: 'Yogurt', qty: '4', emoji: null, price: null },
  { id: 'butter', store: 'super', de: 'Butter', en: 'Butter', qty: '', emoji: '🧈', price: 229 },
  { id: 'coffee', store: 'super', de: 'Kaffee', en: 'Coffee', qty: '', emoji: '☕', price: 699 },
  { id: 'pasta', store: 'super', de: 'Nudeln', en: 'Pasta', qty: '', emoji: '🍝', price: null },
  { id: 'water', store: 'super', de: 'Mineralwasser', en: 'Sparkling water', qty: '6', emoji: '💧', price: null },
  { id: 'toothpaste', store: 'drug', de: 'Zahnpasta', en: 'Toothpaste', qty: '', emoji: '🪥', price: 195 },
  { id: 'soap', store: 'drug', de: 'Spülmittel', en: 'Dish soap', qty: '', emoji: '🧴', price: 149 },
];

// The add sheet after typing „Mi“ / "Mi": recently used first, then bought before.
export const typed = { de: 'Mi', en: 'Mi' };
export const suggestions = [
  { de: 'Milch', en: 'Milk', emoji: '🥛', kind: 'suggestionRecent', store: 'super' },
  { de: 'Minze', en: 'Mint', emoji: '🌿', kind: 'suggestionHistory', store: 'market' },
  { de: 'Mie-Nudeln', en: 'Mie noodles', emoji: '🍜', kind: 'suggestionHistory', store: 'super' },
];

export const money = (lang, cents) => {
  const n = (cents / 100).toFixed(2);
  return lang === 'de' ? `${n.replace('.', ',')} €` : `€${n}`;
};

// TE1 (job 348): a line per store with a price, „mind.“ when the store also has unpriced items; the total says once
// how many have no price.
export const totals = () => {
  const lines = stores.map((s) => {
    const its = items.filter((i) => i.store === s.id);
    const priced = its.filter((i) => i.price !== null);
    return { store: s.id, sum: priced.reduce((a, i) => a + i.price, 0), atLeast: priced.length < its.length, priced: priced.length };
  }).filter((l) => l.priced > 0);
  const unpriced = items.filter((i) => i.price === null).length;
  return { lines, sum: lines.reduce((a, l) => a + l.sum, 0), atLeast: unpriced > 0, unpriced };
};
