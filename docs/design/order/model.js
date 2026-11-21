// Mock data and the five orders. A supermarket trip (EDEKA) and an IKEA trip of the fictional Brandt family, plus two
// items without a store. `cat` is the category the classifier gives the German name today (checked against a local
// stack by tools/capture-today.mjs); `walk` is where the item really sits in that store, the order a trip ticks it.
export const stores = [
  { id: 'edeka', name: 'EDEKA' },
  { id: 'ikea', name: 'IKEA' },
];

export const items = [
  { id: 'bananas', store: 'edeka', cat: 'produce', emoji: '🍌', en: 'Bananas', de: 'Bananen', qty: '6' },
  { id: 'apples', store: 'edeka', cat: 'produce', emoji: '🍎', en: 'Apples', de: 'Äpfel', qty: '1 kg' },
  { id: 'tomatoes', store: 'edeka', cat: 'produce', emoji: '🍅', en: 'Tomatoes', de: 'Tomaten', qty: '' },
  { id: 'cucumber', store: 'edeka', cat: 'produce', emoji: '🥒', en: 'Cucumber', de: 'Gurke', qty: '' },
  { id: 'bread', store: 'edeka', cat: 'bakery', emoji: '🍞', en: 'Bread', de: 'Brot', qty: '' },
  { id: 'pretzels', store: 'edeka', cat: 'bakery', emoji: '🥨', en: 'Pretzels', de: 'Brezeln', qty: '4' },
  { id: 'mince', store: 'edeka', cat: 'meat', emoji: '🥩', en: 'Minced meat', de: 'Hackfleisch', qty: '500 g' },
  { id: 'milk', store: 'edeka', cat: 'chilled', emoji: '🥛', en: 'Milk', de: 'Milch', qty: '2' },
  { id: 'butter', store: 'edeka', cat: 'chilled', emoji: '🧈', en: 'Butter', de: 'Butter', qty: '' },
  { id: 'eggs', store: 'edeka', cat: 'chilled', emoji: '🥚', en: 'Eggs', de: 'Eier', qty: '10' },
  { id: 'yogurt', store: 'edeka', cat: 'chilled', emoji: null, en: 'Yogurt', de: 'Joghurt', qty: '' },
  { id: 'pasta', store: 'edeka', cat: 'pantry', emoji: '🍝', en: 'Pasta', de: 'Nudeln', qty: '' },
  { id: 'flour', store: 'edeka', cat: 'pantry', emoji: '🌾', en: 'Flour', de: 'Mehl', qty: '' },
  { id: 'passata', store: 'edeka', cat: 'pantry', emoji: '🍅', en: 'Passata', de: 'Passierte Tomaten', qty: '' },
  { id: 'chocolate', store: 'edeka', cat: 'sweets', emoji: '🍫', en: 'Chocolate', de: 'Schokolade', qty: '' },
  { id: 'pizza', store: 'edeka', cat: 'frozen', emoji: '🍕', en: 'Frozen pizza', de: 'Tiefkühlpizza', qty: '2' },
  { id: 'water', store: 'edeka', cat: 'drinks', emoji: '💧', en: 'Sparkling water', de: 'Mineralwasser', qty: '6' },
  { id: 'dishsoap', store: 'edeka', cat: 'household', emoji: '🧴', en: 'Dish soap', de: 'Spülmittel', qty: '' },
  { id: 'tealights', store: 'ikea', cat: 'household', emoji: '🕯️', en: 'Tea lights', de: 'Teelichter', qty: '' },
  { id: 'frame', store: 'ikea', cat: 'household', emoji: '🖼️', en: 'Picture frame', de: 'Bilderrahmen', qty: '' },
  { id: 'spoon', store: 'ikea', cat: 'household', emoji: '🥄', en: 'Wooden spoon', de: 'Kochlöffel', qty: '' },
  { id: 'napkins', store: 'ikea', cat: 'household', emoji: null, en: 'Napkins', de: 'Servietten', qty: '' },
  { id: 'meatballs', store: 'ikea', cat: 'other', emoji: null, en: 'Meatballs', de: 'Köttbullar', qty: '' },
  { id: 'cushion', store: 'ikea', cat: 'other', emoji: null, en: 'Cushion', de: 'Kissen', qty: '2' },
  { id: 'boxes', store: 'ikea', cat: 'other', emoji: null, en: 'Storage boxes', de: 'Aufbewahrungsboxen', qty: '3' },
  { id: 'plant', store: 'ikea', cat: 'household', emoji: '🪴', en: 'Plant', de: 'Zimmerpflanze', qty: '' },
  { id: 'shelf', store: 'ikea', cat: 'other', emoji: null, en: 'Shelf', de: 'Regal', qty: '' },
  { id: 'batteries', store: null, cat: 'household', emoji: '🔋', en: 'Batteries', de: 'Batterien', qty: '' },
  { id: 'card', store: null, cat: 'household', emoji: '💌', en: 'Birthday card', de: 'Geburtstagskarte', qty: '' },
];
export const byId = Object.fromEntries(items.map((i) => [i.id, i]));

// An English household types English names, and the classifier gives some of them other categories (read from the
// release build by tools/capture-today.mjs, io/real/*.json): tea lights land in Pantry.
export const catEn = { pretzels: 'other', mince: 'other', tealights: 'pantry', frame: 'other', spoon: 'other', napkins: 'other', plant: 'other', card: 'other' };

// Added while the round runs: a grocery the store has never seen, and an IKEA item.
export const extras = [
  { id: 'ketchup', store: 'edeka', cat: 'pantry', emoji: null, en: 'Ketchup', de: 'Ketchup', qty: '' },
  { id: 'hangers', store: 'ikea', cat: 'other', emoji: null, en: 'Hangers', de: 'Kleiderbügel', qty: '10' },
];
for (const x of extras) byId[x.id] = x;

// Category walk orders: EDEKA's researched layout (docs/STORE_LAYOUTS.md), and the household's route order for IKEA
// and no store (a household's own store starts from it).
export const layout = {
  edeka: ['produce', 'bakery', 'meat', 'chilled', 'pantry', 'sweets', 'frozen', 'drinks', 'household', 'drugstore', 'other'],
  ikea: ['produce', 'bakery', 'chilled', 'meat', 'pantry', 'sweets', 'drinks', 'frozen', 'household', 'drugstore', 'other'],
  none: ['produce', 'bakery', 'chilled', 'meat', 'pantry', 'sweets', 'drinks', 'frozen', 'household', 'drugstore', 'other'],
};
export const catKey = {
  produce: 'categoryProduce', bakery: 'categoryBakery', meat: 'categoryMeat', chilled: 'categoryChilled', pantry: 'categoryPantry',
  sweets: 'categorySweets', frozen: 'categoryFrozen', drinks: 'categoryDrinks', household: 'categoryHousehold', other: 'categoryOther',
};

// Where the items really are, the order a trip ticks them. This EDEKA has its bakery counter by the checkout and the
// eggs by the flour. IKEA: market hall (kitchen, textiles, frames, storage, candles, plants), warehouse, then the food
// shop after the tills.
export const walk = {
  edeka: ['bananas', 'apples', 'tomatoes', 'cucumber', 'milk', 'butter', 'yogurt', 'mince', 'pasta', 'passata', 'flour', 'eggs', 'chocolate', 'water', 'dishsoap', 'pizza', 'pretzels', 'bread'],
  ikea: ['spoon', 'napkins', 'cushion', 'frame', 'boxes', 'tealights', 'plant', 'shelf', 'meatballs'],
};

// The scenario everyone fixes: the household has never bought eggs at this EDEKA, so they sit with the milk; here
// they stand next to the flour.
export const fix = { item: 'eggs', after: 'flour' };

export const storeKey = (store) => store ?? 'none';
export const sectionIds = ['edeka', 'ikea', 'none'];

// The category an item shows under: an edit's pick, else what the classifier gives the name in this language.
export const catOf = (s, id) => s.cats[id] ?? (s.lang === 'en' ? catEn[id] : undefined) ?? byId[id].cat;

// Today: store, then the category in that store's walk order, then the order of adding (sort_key = max + 1024, so an
// item whose category changed goes to the end of its new group).
export const categorical = (s, ids, store) => {
  const lay = layout[store];
  return [...ids].sort((a, b) => lay.indexOf(catOf(s, a)) - lay.indexOf(catOf(s, b)) || s.added[a] - s.added[b]);
};

// The prior for a key a store has not seen: after the last item of its category in the sequence; else before the
// first item of a later category in the store's walk order; else at the end.
export const placeByPrior = (s, seq, id, store) => {
  const lay = layout[store];
  const cat = catOf(s, id);
  const same = seq.filter((x) => catOf(s, x) === cat);
  if (same.length) {
    const at = seq.indexOf(same[same.length - 1]) + 1;
    return [...seq.slice(0, at), id, ...seq.slice(at)];
  }
  const later = seq.findIndex((x) => lay.indexOf(catOf(s, x)) > lay.indexOf(cat));
  return later < 0 ? [...seq, id] : [...seq.slice(0, later), id, ...seq.slice(later)];
};

// One trip teaches the ticked keys their order; keys not ticked keep their place after the last ticked key before them.
export const learnTrip = (seq, ticked) => {
  const t = ticked.filter((id) => seq.includes(id));
  const out = [...t];
  for (const id of seq.filter((x) => !t.includes(x))) {
    const before = seq.slice(0, seq.indexOf(id)).reverse().find((x) => out.includes(x));
    out.splice(before ? out.indexOf(before) + 1 : 0, 0, id);
  }
  return out;
};

// Moves `id` to just after `anchor` (to the top with anchor null).
export const placeAfter = (seq, id, anchor) => {
  const rest = seq.filter((x) => x !== id);
  const at = anchor ? rest.indexOf(anchor) + 1 : 0;
  return [...rest.slice(0, at), id, ...rest.slice(at)];
};

// The fewest single-item moves that turn `from` into `to`: n minus the longest run of `from` already in `to`'s order.
export const movesBetween = (from, to) => {
  const r = from.filter((id) => to.includes(id)).map((id) => to.indexOf(id));
  const best = r.map(() => 1);
  for (let i = 0; i < r.length; i += 1) for (let j = 0; j < i; j += 1) if (r[j] < r[i]) best[i] = Math.max(best[i], best[j] + 1);
  return r.length - Math.max(0, ...best);
};

// Adjacent swaps between two orders (each is one Move up or Move down).
export const swapsBetween = (from, to) => {
  const r = from.filter((id) => to.includes(id)).map((id) => to.indexOf(id));
  let n = 0;
  for (let i = 0; i < r.length; i += 1) for (let j = i + 1; j < r.length; j += 1) if (r[i] > r[j]) n += 1;
  return n;
};

// The share of item pairs a list puts in the walk's order (1 = the walk exactly).
export const agreement = (seq, real) => {
  const r = seq.filter((id) => real.includes(id)).map((id) => real.indexOf(id));
  let good = 0;
  let all = 0;
  for (let i = 0; i < r.length; i += 1) for (let j = i + 1; j < r.length; j += 1) { all += 1; if (r[i] < r[j]) good += 1; }
  return all ? good / all : 1;
};

// How each option orders a store: `categorical` (today's keys), `learned` (a sequence its trips wrote, the prior for
// keys it has not seen) or `manual` (a sequence only drags write, starting from today's order).
export const orderOf = (s, kind, store) => {
  const open = s.open.filter((id) => storeKey(byId[id].store) === store);
  if (kind === 'categorical') return categorical(s, open, store);
  return s.seq[store].filter((id) => open.includes(id));
};

const baseAdded = Object.fromEntries([...items, ...extras].map((x, k) => [x.id, k]));

// The starting state. kind: how the option orders. A learning store has seen every item but the eggs (never bought at
// this EDEKA) on earlier trips; a manual store starts from today's order. `lang` matters: it picks the categories.
export const initial = (kind, lang) => {
  const s = { lang, kind, open: items.map((i) => i.id), cats: {}, added: { ...baseAdded }, seq: {}, fresh: null, sheet: null, sortMode: false, showCats: false, trip: null, moved: null, lifted: null, screen: 'list' };
  for (const store of sectionIds) {
    const mine = items.filter((i) => storeKey(i.store) === store).map((i) => i.id);
    if (kind === 'learned') {
      const real = walk[store] ?? mine;
      let seq = real.filter((id) => id !== fix.item);
      for (const id of categorical(s, mine.filter((id) => !seq.includes(id)), store)) seq = placeByPrior(s, seq, id, store);
      s.seq[store] = seq;
    } else {
      s.seq[store] = categorical(s, mine, store);
    }
  }
  return s;
};

// The live phone's actions. Each returns a new state.
export const act = (s0, a) => {
  const s = structuredClone(s0);
  const [verb, arg, arg2] = a.split(':');
  s.fresh = verb === 'add' ? s.fresh : null;
  s.moved = null;
  const storeOfItem = (id) => storeKey(byId[id].store);
  switch (verb) {
    case 'tick': {
      if (s.sortMode) return s0;
      s.open = s.open.filter((x) => x !== arg);
      if (s.trip) s.trip.ticked.push(arg);
      else s.trip = { ticked: [arg] };
      break;
    }
    case 'endTrip': {
      // The trip teaches each store the order of its ticks (learning options only); then the list fills up again,
      // as next week's list would, so the new order shows.
      if (s.kind === 'learned' && s.trip) for (const store of sectionIds) s.seq[store] = learnTrip(s.seq[store], s.trip.ticked.filter((id) => storeOfItem(id) === store));
      s.open = [...new Set([...s.open, ...(s.trip?.ticked ?? [])])];
      s.trip = null;
      break;
    }
    case 'walkTrip': {
      // A whole trip in walk order: every item ticked where it really is.
      s.trip = { ticked: [...walk.edeka, ...walk.ikea].filter((id) => s.open.includes(id)) };
      s.open = s.open.filter((id) => !s.trip.ticked.includes(id));
      return act(s, 'endTrip');
    }
    case 'add': {
      if (s.open.includes(arg)) break;
      s.open.push(arg);
      s.added[arg] = 1000 + Object.keys(s.added).length;
      const store = storeOfItem(arg);
      if (!s.seq[store].includes(arg)) s.seq[store] = s.kind === 'learned' ? placeByPrior(s, s.seq[store], arg, store) : [...categorical(s, [...s.seq[store], arg], store)];
      s.fresh = arg;
      break;
    }
    case 'hold':
      s.sheet = { kind: 'edit', id: arg };
      break;
    case 'menu':
      s.sheet = { ...s.sheet, menu: arg };
      break;
    case 'setCat': {
      // The edit sheet's category pick: the item goes to the end of its new group (and the household remembers it).
      const id = s.sheet.id;
      s.cats[id] = arg;
      s.added[id] = 2000 + Object.keys(s.added).length;
      s.sheet = { kind: 'edit', id };
      s.moved = id;
      break;
    }
    case 'nextTo': {
      const id = s.sheet.id;
      const store = storeOfItem(id);
      s.seq[store] = placeAfter(s.seq[store], id, arg === 'first' ? null : arg);
      s.sheet = { kind: 'edit', id };
      s.moved = id;
      break;
    }
    case 'step': {
      // Move up / Move down by one place in the store's list (IO5). Crossing into another category's run takes that
      // category, so the item stays under a heading when categories show.
      const id = s.sheet.id;
      const store = storeOfItem(id);
      const shown = orderOf(s, s.kind, store);
      const i = shown.indexOf(id);
      const j = arg === 'up' ? i - 1 : i + 1;
      if (j < 0 || j >= shown.length) break;
      const other = shown[j];
      if (s.kind === 'categorical') {
        const [ci, cj] = [catOf(s, id), catOf(s, other)];
        if (ci !== cj) {
          s.cats[id] = cj;
          const run = shown.filter((x) => catOf(s, x) === cj);
          s.added[id] = arg === 'up' ? Math.max(...run.map((x) => s.added[x])) + 0.5 : Math.min(...run.map((x) => s.added[x])) - 0.5;
        } else {
          [s.added[id], s.added[other]] = [s.added[other], s.added[id]];
        }
      } else {
        s.seq[store] = placeAfter(s.seq[store], id, arg === 'up' ? shown[j - 1] ?? null : other);
      }
      s.moved = id;
      break;
    }
    case 'done':
      s.sheet = null;
      break;
    case 'sortMode':
      s.sortMode = !s.sortMode;
      s.lifted = null;
      break;
    case 'drop': {
      // A drag ends: `arg` lands after `arg2` (or first). A drop in another store's section is not offered here.
      const store = storeOfItem(arg);
      s.seq[store] = placeAfter(s.seq[store], arg, arg2 === 'first' ? null : arg2);
      s.moved = arg;
      break;
    }
    case 'screen':
      s.screen = arg;
      break;
    case 'showCats':
      s.showCats = !s.showCats;
      break;
    default:
      throw new Error(`unknown action ${a}`);
  }
  return s;
};
