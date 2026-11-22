// Round SC's mock list: the Brandt family's stores and items (made up, never user data). Plain data, so the page,
// the capture and verify.mjs read the same list. Store names are plain text (Legal Addendum D: no logos, no brand
// colours); `app` is the registry's app name for the chain (supabase/retailers/retailers.json, DE).
export const stores = [
  { id: 'rewe', name: 'REWE', chain: 'rewe', app: 'REWE', capture: true },
  { id: 'lidl', name: 'Lidl', chain: 'lidl', app: 'Lidl Plus', capture: true },
  { id: 'dm', name: 'dm', chain: 'dm', app: 'Mein dm', capture: true },
  { id: 'netto', name: 'Netto Marken-Discount', chain: 'netto-md', app: 'Netto' },
];

export const items = [
  { store: 'rewe', en: 'Milk', de: 'Milch', qty: '2', icon: '🥛' },
  { store: 'rewe', en: 'Butter', de: 'Butter', icon: '🧈' },
  { store: 'rewe', en: 'Bread', de: 'Brot', icon: '🍞' },
  { store: 'rewe', en: 'Eggs', de: 'Eier', qty: '10', icon: '🥚' },
  { store: 'rewe', en: 'Yogurt', de: 'Joghurt', icon: '🥣' },
  { store: 'rewe', en: 'Cheese', de: 'Käse', icon: '🧀' },
  { store: 'rewe', en: 'Coffee', de: 'Kaffee', icon: '☕' },
  { store: 'rewe', en: 'Tomatoes', de: 'Tomaten', icon: '🍅' },
  { store: 'rewe', en: 'Apples', de: 'Äpfel', qty: '1 kg', icon: '🍎' },
  { store: 'lidl', en: 'Bananas', de: 'Bananen', qty: '6', icon: '🍌' },
  { store: 'lidl', en: 'Pasta', de: 'Nudeln', icon: '🍝' },
  { store: 'lidl', en: 'Rice', de: 'Reis', icon: '🍚' },
  { store: 'lidl', en: 'Cookies', de: 'Kekse', icon: '🍪' },
  { store: 'lidl', en: 'Sparkling water', de: 'Mineralwasser', qty: '6', icon: '💧' },
  { store: 'lidl', en: 'Ice cream', de: 'Eis', icon: '🍨' },
  { store: 'lidl', en: 'Frozen peas', de: 'Erbsen, TK', icon: '🟢' },
  { store: 'dm', en: 'Toothpaste', de: 'Zahnpasta', icon: '🪥' },
  { store: 'dm', en: 'Shower gel', de: 'Duschgel', icon: '🧴' },
  { store: 'dm', en: 'Dish soap', de: 'Spülmittel', icon: '🧽' },
  { store: 'netto', en: 'Oat milk', de: 'Hafermilch', qty: '2', icon: '🥛' },
  { store: 'netto', en: 'Cucumber', de: 'Gurke', icon: '🥒' },
  { store: 'netto', en: 'Paper towels', de: 'Küchenrolle', icon: '🧻' },
  { store: 'netto', en: 'Onions', de: 'Zwiebeln', icon: '🧅' },
];

// The states every option is shown in. `done` lists the stores finished in this session, oldest first; the last one
// is the store whose last item was just ticked. `open` are the stores still on the list, in list order.
export const states = {
  a: { done: ['rewe'], open: ['lidl', 'dm'] },
  b: { done: ['dm'], open: [] },
  c: { done: ['rewe', 'lidl'], open: ['dm'] },
  d: { done: ['netto'], open: ['lidl', 'dm'] },
  // Only on the storyboard: Lidl finished while REWE, above it in list order, is still open; dm comes after Lidl.
  f: { done: ['lidl'], open: ['rewe', 'dm'] },
};
export const stateKeys = ['a', 'b', 'c', 'd'];
export const storeById = (id) => stores.find((s) => s.id === id);
export const itemsOf = (id) => items.filter((i) => i.store === id);
