// Mock data only: the fictional Familie Brandt and the slice of the retailer registry the scenes use.
// The registry proposal and its verified ids are in registry/retailers.json; verify.mjs checks that every app named here
// matches a verified entry there (same chain, country and app name).

// One chain in one country, keyed chain:country as in registry/retailers.json. `app` is the button's app name (null: no
// button); `ul` whether the registry has a verified https link that opens the app (else iOS can only open the App Store page).
export const chains = {
  'lidl:DE': { chain: 'lidl', name: 'Lidl', country: 'DE', app: 'Lidl Plus', ul: false, aliases: ['lidl'] },
  'lidl:AT': { chain: 'lidl', name: 'Lidl', country: 'AT', app: 'Lidl Plus', ul: false, aliases: ['lidl'] },
  'lidl:FR': { chain: 'lidl', name: 'Lidl', country: 'FR', app: 'Lidl Plus', ul: false, aliases: ['lidl'] },
  'dm:DE': { chain: 'dm', name: 'dm', country: 'DE', app: 'Mein dm', ul: false, aliases: ['dm', 'dm drogerie'] },
  'aldi-sued:DE': { chain: 'aldi-sued', name: 'ALDI SÜD', country: 'DE', app: 'ALDI SÜD', ul: true, aliases: ['aldi', 'aldi süd', 'aldi sued'] },
  'aldi-nord:DE': { chain: 'aldi-nord', name: 'ALDI Nord', country: 'DE', app: 'ALDI Nord', ul: true, aliases: ['aldi', 'aldi nord'] },
  'aldi-sued:AT': { chain: 'aldi-sued', name: 'Hofer', country: 'AT', app: 'HOFER', ul: true, aliases: ['hofer', 'aldi'] },
  'aldi-nord:FR': { chain: 'aldi-nord', name: 'ALDI', country: 'FR', app: 'ALDI', ul: true, aliases: ['aldi'] },
  'rewe:DE': { chain: 'rewe', name: 'REWE', country: 'DE', app: 'REWE', ul: true, aliases: ['rewe'] },
  'edeka:DE': { chain: 'edeka', name: 'EDEKA', country: 'DE', app: 'EDEKA', ul: false, aliases: ['edeka'] },
  'kaufland:DE': { chain: 'kaufland', name: 'Kaufland', country: 'DE', app: 'Kaufland', ul: false, aliases: ['kaufland'] },
  'penny:DE': { chain: 'penny', name: 'PENNY', country: 'DE', app: 'PENNY', ul: false, aliases: ['penny'] },
  'netto-md:DE': { chain: 'netto-md', name: 'Netto Marken-Discount', country: 'DE', app: 'Netto', ul: false, aliases: ['netto'] },
  'rossmann:DE': { chain: 'rossmann', name: 'Rossmann', country: 'DE', app: 'Rossmann', ul: false, aliases: ['rossmann'] },
  'billa:AT': { chain: 'billa', name: 'BILLA', country: 'AT', app: 'BILLA', ul: false, aliases: ['billa'] },
  'spar-at:AT': { chain: 'spar-at', name: 'SPAR', country: 'AT', app: 'SPAR', ul: false, aliases: ['spar', 'eurospar', 'interspar'] },
  'dm:AT': { chain: 'dm', name: 'dm', country: 'AT', app: 'Mein dm', ul: false, aliases: ['dm'] },
  'mpreis:AT': { chain: 'mpreis', name: 'MPREIS', country: 'AT', app: 'MPREIS', ul: false, aliases: ['mpreis'] },
  'penny:AT': { chain: 'penny', name: 'PENNY', country: 'AT', app: 'PENNY', ul: false, aliases: ['penny'] },
  'carrefour:FR': { chain: 'carrefour', name: 'Carrefour', country: 'FR', app: 'Carrefour', ul: true, aliases: ['carrefour'] },
  'leclerc:FR': { chain: 'leclerc', name: 'E.Leclerc', country: 'FR', app: 'E.Leclerc', ul: false, aliases: ['leclerc', 'e.leclerc'] },
  'intermarche:FR': { chain: 'intermarche', name: 'Intermarché', country: 'FR', app: 'Intermarché', ul: true, aliases: ['intermarche', 'intermarché'] },
};

// Chains a picker offers per country, in the order a picker shows them (most stores first, as the onboarding chips do).
export const chainsByCountry = {
  DE: ['edeka:DE', 'rewe:DE', 'lidl:DE', 'aldi-sued:DE', 'aldi-nord:DE', 'kaufland:DE', 'netto-md:DE', 'penny:DE', 'dm:DE', 'rossmann:DE'],
  AT: ['billa:AT', 'spar-at:AT', 'aldi-sued:AT', 'lidl:AT', 'penny:AT'],
  FR: ['carrefour:FR', 'leclerc:FR', 'intermarche:FR', 'lidl:FR', 'aldi-nord:FR'],
};

// The list (one household, one list). Each store: its own name (free text, as today), the chain it is linked to (or
// null), and the open items in walking order with their category.
export const household = { name: 'Familie Brandt', list: { en: 'Weekly shop', de: 'Wocheneinkauf' } };

export const listStores = [
  { id: 'dm', name: 'dm', link: 'dm:DE', items: [
    { en: 'Toothpaste', de: 'Zahnpasta', cat: 'other' },
    { en: 'Shower gel', de: 'Duschgel', cat: 'other' },
  ] },
  { id: 'lidl', name: 'Lidl', link: 'lidl:DE', items: [
    { en: 'Milk', de: 'Vollmilch', qty: '2 l', cat: 'chilled' },
    { en: 'Butter', de: 'Butter', cat: 'chilled' },
    { en: 'Bananas', de: 'Bananen', qty: '6×', cat: 'produce' },
    { en: 'Bread', de: 'Brot', cat: 'other' },
  ] },
  { id: 'aldi', name: 'ALDI SÜD am Hauptbahnhof (Ostausgang)', link: 'aldi-sued:DE', items: [
    { en: 'Coffee beans', de: 'Kaffeebohnen', cat: 'other' },
    { en: 'Oats', de: 'Haferflocken', cat: 'other' },
  ] },
  { id: 'markt', name: 'Wochenmarkt', link: null, items: [
    { en: 'Eggs', de: 'Eier', qty: '10×', cat: 'other' },
    { en: 'Apples', de: 'Äpfel', cat: 'produce' },
  ] },
  { id: 'rewe', name: 'REWE', link: 'rewe:DE', items: [
    { en: 'Yogurt', de: 'Joghurt', cat: 'chilled' },
    { en: 'Tomatoes', de: 'Tomaten', cat: 'produce' },
  ] },
];

export const categories = {
  other: { en: 'Other', de: 'Sonstiges' },
  chilled: { en: 'Chilled', de: 'Kühlregal' },
  produce: { en: 'Fruit & veg', de: 'Obst & Gemüse' },
};

// What the store page shows when the app is missing: title and developer as the App Store lists them (iTunes lookup, country=de, 2026-11-18).
export const storeListing = {
  'Lidl Plus': { title: 'Lidl Plus', dev: 'Lidl Digital International GmbH & Co. KG' },
  'Mein dm': { title: 'Mein dm', dev: 'dm-drogerie markt GmbH + Co. KG' },
  'ALDI SÜD': { title: 'ALDI SÜD Angebote & Prospekte', dev: 'ALDI International Services GmbH & Co. oHG' },
  'REWE': { title: 'REWE - Supermarkt', dev: 'REWE Markt GmbH' },
};

// Nearby branches for SS3 (mock addresses in a fictional town; no real places).
export const nearby = [
  { link: 'lidl:DE', branch: 'Lindenallee 12', dist: '350 m' },
  { link: 'rewe:DE', branch: 'Marktplatz 3', dist: '600 m' },
  { link: 'aldi-sued:DE', branch: 'Bahnhofstraße 40', dist: '900 m' },
  { link: 'dm:DE', branch: 'Marktplatz 5', dist: '650 m' },
  { link: null, name: 'Hofladen Sonnenwiese', branch: 'Feldweg 2', dist: '2,1 km' },
];

export const label = (link) => (link ? chains[link] : null);
