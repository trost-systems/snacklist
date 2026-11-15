// Mock data and the app's own strings (app/l10n/app_de.arb and its English twin) for the chrome around the flows.
// The Brandt family is fictional; nothing here comes from a real account.

export const chrome = {
  en: {
    household: 'Brandt family', edit: 'Edit', noStore: 'No store', items: (n) => `${n} items`,
    addHint: 'What do you need?', list: 'List', history: 'History', more: 'More',
    total: 'Shopping total', totalMeta: '0 priced · 9 open', price: 'Price',
    moreTitle: 'More', startTrip: 'Start a trip', startTripSub: 'The clock runs from now; the list as it is now counts as planned.',
    account: 'Account', invite: 'Invite your partner', access: 'Access', settings: 'Settings', usage: 'Usage data',
    tips: 'Tips', feedback: 'Send feedback', rate: 'Rate Snacklist', help: 'Help & contact',
    fbTitle: 'Send feedback', close: 'Close', message: 'Your message', messageHint: 'What did you notice?',
    type: 'Type (optional)', bug: 'Bug', idea: 'Idea', other: 'Other', contact: 'Peter may contact me about this',
    included: 'Included: App version, device, language and current screen. No list items.',
    send: 'Send', thanks: 'Thanks!', back: 'Back', cancel: 'Cancel', notNow: 'Not now',
  },
  de: {
    household: 'Familie Brandt', edit: 'Anpassen', noStore: 'Ohne Laden', items: (n) => `${n} Artikel`,
    addHint: 'Was brauchst du?', list: 'Liste', history: 'Verlauf', more: 'Mehr',
    total: 'Einkaufssumme', totalMeta: '0 mit Preis · 9 offen', price: 'Preis',
    moreTitle: 'Mehr', startTrip: 'Einkauf starten', startTripSub: 'Die Uhr läuft ab jetzt, die Liste, wie sie jetzt ist, gilt als geplant.',
    account: 'Konto', invite: 'Partner einladen', access: 'Zugänge', settings: 'Einstellungen', usage: 'Nutzungsdaten',
    tips: 'Tipps', feedback: 'Feedback senden', rate: 'Snacklist bewerten', help: 'Hilfe & Kontakt',
    fbTitle: 'Feedback senden', close: 'Schließen', message: 'Deine Nachricht', messageHint: 'Was ist dir aufgefallen?',
    type: 'Art (optional)', bug: 'Bug', idea: 'Idee', other: 'Sonstiges', contact: 'Peter darf mich dazu kontaktieren',
    included: 'Wird mitgeschickt: App-Version, Gerät, Sprache und aktueller Bildschirm. Keine Listeneinträge.',
    send: 'Senden', thanks: 'Danke!', back: 'Zurück', cancel: 'Abbrechen', notNow: 'Nicht jetzt',
  },
};

// The total as the app formats it (NumberFormat.simpleCurrency(locale), pricing.dart): €0.00, 0,00 €.
export const money = (lang, cents = 0) => new Intl.NumberFormat(lang === 'de' ? 'de-DE' : 'en-US', { style: 'currency', currency: 'EUR' }).format(cents / 100);

// Where each chrome string comes from in app/l10n/app_<lang>.arb: the key, its placeholder values, and for
// `included` the two keys the form joins. verify.mjs fails when a value here drifts from the ARB.
// `household` and `notNow` are mock or new copy and have no key.
export const arbOf = {
  edit: ['listEdit'], noStore: ['noStore'], items: ['listItemCount', { count: 9 }], addHint: ['addFieldHint'],
  list: ['tabList'], history: ['tabHistory'], more: ['tabMore'], total: ['tripTotal'], totalMeta: ['tripCounts', { priced: 0, open: 9 }],
  price: ['priceAdd'], moreTitle: ['tabMore'], startTrip: ['shopStartByHand'], startTripSub: ['shopStartByHandHint'], account: ['account'],
  invite: ['inviteMember'], access: ['accessTitle'], settings: ['settingsTitle'], usage: ['analyticsSection'], tips: ['hintsTitle'],
  feedback: ['feedbackRow'], rate: ['rateApp'], help: ['helpRow'], fbTitle: ['feedbackRow'], close: ['feedbackClose'],
  message: ['feedbackMessage'], messageHint: ['feedbackMessageHint'], type: ['feedbackCategories'], bug: ['feedbackCategoryBug'],
  idea: ['feedbackCategoryIdea'], other: ['feedbackCategoryOther'], contact: ['feedbackContact'], included: [['feedbackAttachedTitle', 'feedbackAttached']],
  send: ['feedbackSend'], thanks: ['feedbackThanks'], back: ['onboardingBack'], cancel: ['cancel'],
};

// The list on screen in every flow: the same shape as the baseline drive of the real app.
export const list = [
  { cat: { en: 'Fruit & veg', de: 'Obst & Gemüse' , arb: 'categoryProduce' }, items: [
    { e: '🍌', q: '6×', en: 'Bananas', de: 'Bananen' },
    { e: '🍎', q: '1 kg', en: 'Apples', de: 'Äpfel' },
  ] },
  { cat: { en: 'Bread & bakery', de: 'Brot & Backwaren' , arb: 'categoryBakery' }, items: [{ e: '🍞', en: 'Bread', de: 'Brot' }] },
  { cat: { en: 'Chilled', de: 'Kühlregal' , arb: 'categoryChilled' }, items: [
    { e: '🥛', q: '2×', en: 'Milk', de: 'Milch' },
    { e: '🧈', en: 'Butter', de: 'Butter' },
  ] },
  { cat: { en: 'Pantry', de: 'Vorrat & Konserven' , arb: 'categoryPantry' }, items: [
    { e: '🍝', en: 'Pasta', de: 'Nudeln' },
    { e: '🥣', id: 'oat', en: 'Oat milk', de: 'Hafermilch' },
    { e: '🍚', en: 'Rice', de: 'Reis' },
  ] },
  { cat: { en: 'Sweets & snacks', de: 'Süßes & Snacks' , arb: 'categorySweets' }, items: [{ e: '🍪', en: 'Cookies', de: 'Kekse' }] },
];

// Three situations a user is in when they want to tell Peter something. Each flow shows its path for each.
export const scenarios = {
  bug: {
    label: { en: 'Wrong category', de: 'Falsche Kategorie' },
    what: { en: 'Oat milk lands in Pantry instead of Chilled.', de: 'Hafermilch landet im Vorrat statt im Kühlregal.' },
    message: { en: 'Oat milk keeps ending up under Pantry. In our shop it’s in the fridge.', de: 'Hafermilch landet immer im Vorrat. Bei uns steht sie im Kühlregal.' },
    category: 'bug',
    screen: 'list',
  },
  error: {
    label: { en: 'Change rejected', de: 'Änderung abgelehnt' },
    what: { en: 'The server refused a change; Lea does not see it.', de: 'Der Server hat eine Änderung abgelehnt; Lea sieht sie nicht.' },
    message: { en: 'I added oat milk on the bus and Lea never got it.', de: 'Ich hab im Bus Hafermilch eingetragen und Lea hat sie nie bekommen.' },
    category: 'bug',
    screen: 'list',
    // Today's snackbar for a refused write (`syncFailed`, list_scope.dart `rejectionText`, `ItemRejected`).
    snack: { en: 'Change rejected: Oat milk', de: 'Änderung abgelehnt: Hafermilch' },
  },
  idea: {
    label: { en: 'Feature idea', de: 'Idee' },
    what: { en: 'The user wants the list in aisle order.', de: 'Wunsch: Liste in der Reihenfolge der Gänge.' },
    message: { en: 'Could the list follow the aisles of my store?', de: 'Kann die Liste der Reihenfolge der Gänge in meinem Laden folgen?' },
    category: 'idea',
    screen: 'list',
  },
};

// What a note can carry besides its text. `signal` is the debugging value Peter gets from it (the table's
// "debug value" counts the signals a flow delivers by default); `list` marks list content (item, store or
// household names, or a picture of the list), which never goes without the user's choice and a preview; `redacted`
// marks a field that goes with its list text blacked out unless the user reveals it.
export const fields = {
  screen: { signal: 'screen', label: { en: 'Screen', de: 'Bildschirm' }, value: () => ({ en: 'List', de: 'Liste' }) },
  version: { signal: 'build', label: { en: 'App version', de: 'App-Version' }, value: () => ({ en: '1.4.0 (1325)', de: '1.4.0 (1325)' }) },
  // Today's platform and OS (`os_version`); the device model needs #281's `device_model` column.
  device: { signal: 'build', label: { en: 'System', de: 'System' }, value: () => ({ en: 'iOS 26.1', de: 'iOS 26.1' }) },
  model: { signal: 'build', label: { en: 'Device model (#281)', de: 'Gerätemodell (#281)' }, value: () => ({ en: 'iPhone 15', de: 'iPhone 15' }) },
  language: { label: { en: 'Language', de: 'Sprache' }, value: (l) => ({ en: l === 'de' ? 'German' : 'English', de: l === 'de' ? 'Deutsch' : 'Englisch' }) },
  display: { signal: 'display', label: { en: 'Display', de: 'Anzeige' }, value: () => ({ en: 'Dark · text 130 % · online', de: 'Dunkel · Text 130 % · online' }) },
  plan: { label: { en: 'Premium', de: 'Premium' }, value: () => ({ en: 'No', de: 'Nein' }) },
  // The refused write names its item, so it is list content under the same chip and preview rule as `item`.
  error: { signal: ['error', 'case'], list: true, label: { en: 'Rejected change', de: 'Abgelehnte Änderung' }, value: () => ({ en: 'ItemRejected · add · 42501 · Oat milk · 18:42', de: 'ItemRejected · add · 42501 · Hafermilch · 18:42' }) },
  errlink: { signal: ['error', 'steps'], label: { en: 'Link to the error report', de: 'Verknüpfung zum Fehlerbericht' }, value: () => ({ en: 'ItemRejected 18:42, already in Sentry; this only links your note', de: 'ItemRejected 18:42, schon in Sentry; das verknüpft nur deine Notiz' }) },
  steps: { signal: 'steps', label: { en: 'Last 8 steps', de: 'Letzte 8 Schritte' }, value: () => ({ en: 'open list · add item · tick · open item · change category · … (fixed names, kept on this phone until you send)', de: 'Liste öffnen · Eintrag hinzufügen · abhaken · Eintrag öffnen · Kategorie ändern · … (feste Namen, bis zum Senden nur auf dem Telefon)' }) },
  flags: { signal: 'flags', label: { en: 'Feature switches', de: 'Funktionsschalter' }, value: () => ({ en: 'trip-mode on · public-api off', de: 'trip-mode an · public-api aus' }) },
  shot: { signal: 'shot', list: true, redacted: true, label: { en: 'Screenshot', de: 'Bildschirmfoto' }, value: () => ({ en: 'Item names blacked out', de: 'Eintragsnamen geschwärzt' }) },
  item: { signal: 'case', list: true, label: { en: 'Item', de: 'Eintrag' }, value: () => ({ en: 'Oat milk: Pantry → Chilled', de: 'Hafermilch: Vorrat & Konserven → Kühlregal' }) },
  crash: { signal: ['error', 'steps'], label: { en: 'Link to the crash report', de: 'Verknüpfung zum Absturzbericht' }, value: () => ({ en: 'Crash 7f3a…, yesterday 18:42. Already reported automatically (usage-data yes); this only links your note', de: 'Absturz 7f3a…, gestern 18:42. Schon automatisch gemeldet (Ja zu Nutzungsdaten); das verknüpft nur deine Notiz' }) },
  score: { signal: 'case', label: { en: 'Your rating', de: 'Deine Bewertung' }, value: () => ({ en: '2 of 5 (survey “shopping today”)', de: '2 von 5 (Umfrage „Einkauf heute“)' }) },
};

// The eight debugging signals and what each is worth to Peter (`w`): the exact error or the user's own case
// tells him what to fix without asking back (3); a picture or the last steps let him reproduce it (2);
// the rest narrows it down (1). The table's debug value is the sum over the signals a flow sends by default.
export const signals = {
  error: { w: 3, en: 'the exact error or crash', de: 'der genaue Fehler oder Absturz' },
  case: { w: 3, en: 'the item or case itself', de: 'der Eintrag oder Fall selbst' },
  shot: { w: 2, en: 'a (redacted) screenshot', de: 'ein (geschwärztes) Bildschirmfoto' },
  steps: { w: 2, en: 'the last steps (names only)', de: 'die letzten Schritte (nur Namen)' },
  screen: { w: 1, en: 'which screen', de: 'welcher Bildschirm' },
  build: { w: 1, en: 'app version and system', de: 'App-Version und System' },
  display: { w: 1, en: 'theme, text size, online', de: 'Design, Textgröße, online' },
  flags: { w: 1, en: 'feature switches', de: 'Funktionsschalter' },
};
export const maxDebug = Object.values(signals).reduce((n, s) => n + s.w, 0);
