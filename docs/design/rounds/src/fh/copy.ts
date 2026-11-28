export type Lang = 'en' | 'de';

export const CHAINS = ['EDEKA', 'REWE', 'Lidl', 'ALDI SÜD', 'ALDI Nord', 'Kaufland', 'Netto', 'PENNY', 'dm', 'Rossmann'];

export const COPY = {
  en: {
    progress: 'Step 4 of 7',
    back: 'Back',
    leave: 'Leave setup',
    title: 'Where do you shop?',
    hardware: 'Hardware store',
    addOwn: 'Add your own store',
    storeName: 'Store name',
    cancel: 'Cancel',
    next: 'Continue',
    skip: 'Skip',
    listTitle: 'Groceries',
    store: 'REWE',
    rows: [
      { name: 'Milk', qty: '2', detail: '1.5 % fat' },
      { name: 'Bread', qty: null, detail: 'Sourdough' },
      { name: 'Apples', qty: '6', detail: null },
      { name: 'Coffee', qty: null, detail: 'Beans' },
    ],
    tabs: ['List', 'History', 'More'],
  },
  de: {
    progress: 'Schritt 4 von 7',
    back: 'Zurück',
    leave: 'Einrichtung verlassen',
    title: 'Wo kauft ihr ein?',
    hardware: 'Baumarkt',
    addOwn: 'Eigenen Laden hinzufügen',
    storeName: 'Name des Ladens',
    cancel: 'Abbrechen',
    next: 'Weiter',
    skip: 'Überspringen',
    listTitle: 'Einkauf',
    store: 'REWE',
    rows: [
      { name: 'Milch', qty: '2', detail: '1,5 % Fett' },
      { name: 'Brot', qty: null, detail: 'Sauerteig' },
      { name: 'Äpfel', qty: '6', detail: null },
      { name: 'Kaffee', qty: null, detail: 'Bohnen' },
    ],
    tabs: ['Liste', 'Verlauf', 'Mehr'],
  },
} as const;
