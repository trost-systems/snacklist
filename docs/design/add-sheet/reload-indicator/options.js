// Round RI: how the add sheet shows that the server's suggestions are still on the way, without rows jumping under
// the finger. Today (main: nothing) and RI1–RI3 on the shared phone, with today's 120 ms debounce and a simulated reply.
import { ic } from '../sandbox.js';
import { riList } from '../model.js';

const stale = { en: 'older suggestion, still loading', de: 'älterer Vorschlag, lädt noch' };
const loadingLabel = { en: 'Loading suggestions', de: 'Vorschläge laden' };
// While the reply is on the way every row but job 272's typed row is provisional: it answers an older text, or it
// was built on the device from the usuals.
const isStale = (ph, r) => ph.loading && r.source !== 'typed' && (r.forText !== ph.key || r.device);

// The options sit on job 272's base: the typed row follows every keystroke, and four row slots are kept while typing
// so the sheet does not grow when the reply lands. Only the indicator differs between RI1–RI3.
const base = { typedLive: true, reserve: 4 };

export const options = [
  {
    id: 'today',
    name: { en: 'Today', de: 'Heute' },
    line: {
      en: 'Main: nothing shows that rows are loading. From the second letter the rows (the “as typed” row too) still answer the first letter until the reply lands, then they change in place.',
      de: 'Main: nichts zeigt, dass Zeilen laden. Ab dem zweiten Buchstaben antworten die Zeilen (auch „Wie getippt“) noch auf den ersten Buchstaben, bis die Antwort kommt; dann ändern sie sich an Ort und Stelle.',
    },
  },
  {
    id: 'base',
    name: { en: '272 base, no indicator', de: 'Basis 272, ohne Anzeige' },
    line: {
      en: 'The control: job 272’s live typed row and four kept row slots, with no indicator. Every RI option is this phone plus its indicator, so compare each of them with this one.',
      de: 'Die Kontrolle: die mitlaufende getippte Zeile und vier freigehaltene Zeilenplätze aus Job 272, ohne Anzeige. Jede RI-Variante ist dieses Telefon plus ihre Anzeige; vergleiche jede mit diesem.',
    },
    ...base,
  },
  {
    id: 'RI1',
    name: { en: 'Dim stale rows', de: 'Alte Zeilen abblenden' },
    line: {
      en: 'While the reply is on the way, rows that answer an older text (or were made on the device) fade to 55 % and are marked stale for screen readers; they still take a tap. The typed row stays at full strength.',
      de: 'Solange die Antwort unterwegs ist, verblassen Zeilen, die auf einen älteren Text antworten (oder auf dem Gerät entstanden), auf 55 % und sind für Screenreader als veraltet markiert; ein Tipp nimmt sie trotzdem. Die getippte Zeile bleibt kräftig.',
    },
    ...base,
    rowClass: (ph, r) => (isStale(ph, r) ? 'stale' : ''),
    rowAria: (ph, r) => (isStale(ph, r) ? `aria-description="${stale[ph.lang]}"` : ''),
    indicator: '.srow.stale',
  },
  {
    id: 'RI2',
    name: { en: 'Progress line', de: 'Ladelinie' },
    line: {
      en: 'A 2 px line runs along the sheet’s bottom edge, right above the field, while rows load; it takes no space. With reduced motion it stands still.',
      de: 'Eine 2 px Linie läuft an der Unterkante des Blatts, direkt über dem Feld, solange Zeilen laden; sie braucht keinen Platz. Bei reduzierter Bewegung steht sie still.',
    },
    ...base,
    sheetEdge: (ph) => (ph.loading ? `<div class="loadline" role="progressbar" aria-label="${loadingLabel[ph.lang]}"><i></i></div>` : ''),
    indicator: '.loadline',
  },
  {
    id: 'RI3',
    name: { en: 'Spinner in the field', de: 'Ladesymbol im Feld' },
    line: {
      en: 'A small 18 px spinner in the field, left of the clear ✕, while rows load; the slot is always kept, so nothing shifts. With reduced motion a still ring.',
      de: 'Ein kleiner 18-px-Ladekreis im Feld, links vom Leeren-✕, solange Zeilen laden; der Platz bleibt immer frei, nichts verschiebt sich. Bei reduzierter Bewegung ein stehender Ring.',
    },
    ...base,
    fieldTrail: (ph) => `<span class="spinslot">${ph.loading ? `<span class="spinner" role="progressbar" aria-label="${loadingLabel[ph.lang]}"></span>` : ''}</span>`,
    indicator: '.spinner',
  },
];

const t = (en, de) => ({ en, de });
export const latencies = { fast: 150, typical: 450, slow: 1800 };
export const word = t('Milk', 'Milch');

// The frames: a fast typist just finished the word (rows still answer “M”, the reply is on the way), and settled.
export const round = {
  id: 'ri',
  label: 'RI',
  rec: { pick: 'RI2', runnerUp: 'RI1' },
  title: { en: 'Reload indicator (RI1–RI3)', de: 'Ladeanzeige (RI1–RI3)' },
  compare: {
    en: 'While the server’s suggestions for what is typed are still on the way: how the add sheet shows it without rows jumping under the finger. Debounce as today (120 ms), the reply after the chosen latency. Today (main) and the control “272 base, no indicator” (job 272’s live typed row and four kept row slots) next to three options, each of them that base plus its indicator. Type in any phone, or play a fast typist or a slow reply on all of them.',
    de: 'Solange die Vorschläge des Servers für das Getippte noch unterwegs sind: wie das Hinzufügen-Blatt das zeigt, ohne dass Zeilen unter dem Finger springen. Entprellen wie heute (120 ms), die Antwort nach der gewählten Wartezeit. Heute (main) und die Kontrolle „Basis 272, ohne Anzeige“ (mitlaufende getippte Zeile und vier freigehaltene Zeilenplätze aus Job 272) neben drei Varianten, jede diese Basis plus ihre Anzeige. In jedes Telefon tippen, oder eine schnelle Tipperin bzw. eine langsame Antwort auf allen abspielen.',
  },
  options,
  scenarios: {
    typical: { name: t('Reply 450 ms', 'Antwort 450 ms') },
    fast: { name: t('Reply 150 ms', 'Antwort 150 ms') },
    slow: { name: t('Reply 1800 ms', 'Antwort 1800 ms') },
  },
  scenarioLabel: t('Reply time', 'Antwortzeit'),
  frames: [
    { id: 'loading', name: t('Typed fast, reply on the way', 'Schnell getippt, Antwort unterwegs') },
    { id: 'settled', name: t('Reply landed', 'Antwort da') },
  ],
  list: riList,
  latency: (scen) => latencies[scen],
  // Frames are built without timers: the loading frame types the word key by key with the reply held back.
  setup: (ph, scen, frame) => {
    ph.open();
    const w = word[ph.lang];
    for (let i = 1; i <= w.length; i++) ph.type(w.slice(0, i));
    clearTimeout(ph.debounce);
    if (frame === 'settled') ph.settle();
  },
  plays: [
    { id: 'fast', name: t('Play fast typist', 'Schnelle Tipperin abspielen'), gap: 70 },
    { id: 'slowreply', name: t('Play slow reply', 'Langsame Antwort abspielen'), gap: 220, latency: 1800 },
  ],
  icon: ic,
};
