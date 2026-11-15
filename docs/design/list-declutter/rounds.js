// The prototype rounds, newest first. Each has its own page (`<path>/index.html`) with only its own sets, phones,
// recommendation and data; the overview (`index.html`) lists them with their one-line `blurb`. Plain data, so the shoot scripts import it too.
export const rounds = [
  {
    path: 'st',
    blurb: { en: 'Five ways to show what each store costs, and the total.', de: 'Fünf Wege zu zeigen, was jeder Laden kostet, und die Gesamtsumme.' },
    date: { en: 'Nov 14', de: '14. Nov.' },
    title: { en: 'Per-store subtotals (ST1–ST5)', de: 'Summen je Laden (ST1–ST5)' },
    compare: {
      en: 'Five ways to show a subtotal per store and the final total on the round 2 pick (R2, its switcher opening SS5), next to Today and R2.',
      de: 'Fünf Wege, eine Teilsumme je Laden und die Gesamtsumme zu zeigen, auf der Wahl aus Runde 2 (R2, ihr Umschalter öffnet SS5), neben Heute und R2.',
    },
    sets: { st: ['today', 'R2', 'ST1', 'ST2', 'ST3', 'ST4', 'ST5'] },
    rec: { view: 'recst', file: 'RECOMMENDATION-ST' },
    own: ['ST1', 'ST2', 'ST3', 'ST4', 'ST5'],
    data: ['three', 'one', 'mixed'],
    people: false,
  },
  {
    path: 'ss-bb',
    blurb: { en: 'Five switcher sheets and five bottom areas on the round 2 base.', de: 'Fünf Umschalter-Blätter und fünf untere Bereiche auf der Basis von Runde 2.' },
    date: { en: 'Nov 13', de: '13. Nov.' },
    title: { en: 'Switcher sheet + bottom area (SS/BB)', de: 'Umschalter-Blatt + unterer Bereich (SS/BB)' },
    compare: {
      en: 'Round 2 on a fixed base (see-through header with the combined switcher, total as a row, three tabs): five switcher sheets (SS), five bottom areas (BB), and LD4 with three tabs.',
      de: 'Runde 2 auf einer festen Basis (durchscheinende Kopfzeile mit dem kombinierten Umschalter, Summe als Zeile, drei Tabs): fünf Umschalter-Blätter (SS), fünf untere Bereiche (BB) und LD4 mit drei Tabs.',
    },
    sets: {
      ss: ['today', 'SS1', 'SS2', 'SS3', 'SS4', 'SS5'],
      bb: ['today', 'R2', 'BB1', 'BB2', 'BB3', 'BB4', 'BB5'],
      ld4: ['today', 'LD1', 'R2', 'BB4', 'LD4', 'LD4-3T'],
    },
    rec: { view: 'rec', file: 'RECOMMENDATION' },
    own: ['R2', 'SS1', 'SS2', 'SS3', 'SS4', 'SS5', 'BB1', 'BB2', 'BB3', 'BB4', 'BB5', 'LD4-3T'],
    data: ['shot', 'big'],
    people: true,
  },
  {
    path: 'round1',
    blurb: { en: 'Five ways to give the list more room than Today.', de: 'Fünf Wege, der Liste mehr Platz als heute zu geben.' },
    date: { en: 'Nov 13', de: '13. Nov.' },
    title: { en: 'List declutter round 1 (LD1–LD5)', de: 'Liste entrümpeln, Runde 1 (LD1–LD5)' },
    compare: {
      en: 'Five ways to give the list more room than Today: slimmer bars, a collapsing header, plan and shop modes, a bottom dock, a list that owns the chrome.',
      de: 'Fünf Wege, der Liste mehr Platz als heute zu geben: schmalere Leisten, eine einklappende Kopfzeile, Planen und Einkaufen getrennt, ein Dock unten, die Liste trägt die Bedienung.',
    },
    sets: { r1: ['today', 'LD1', 'LD2', 'LD3', 'LD4', 'LD5'] },
    rec: { view: 'rec1', file: 'RECOMMENDATION-R1' },
    own: ['LD1', 'LD2', 'LD3', 'LD4', 'LD5'],
    data: ['shot', 'big'],
    people: true,
  },
];

// Rounds of other features, each in its own folder beside this one (`docs/design/<folder>/`, and beside the
// overview in the preview build). The overview lists them with the rounds above, newest first; they own no views here.
export const linked = [
  {
    href: '../feedback-experience/',
    blurb: { en: 'Five ways to send Peter feedback, from shake to “report this”.', de: 'Fünf Wege, Peter Feedback zu schicken, vom Schütteln bis „Melden“.' },
    date: { en: 'Nov 15', de: '15. Nov.' },
    title: { en: 'Feedback experience (FB1–FB5)', de: 'Feedback-Erlebnis (FB1–FB5)' },
  },
];

// Every view a round page shows: its sets, its recommendation, its phones, and `every` (all its phones, for the shoot scripts).
export const viewsOf = (round) => new Set([...Object.keys(round.sets), round.rec.view, 'every', ...Object.values(round.sets).flat()]);

// The page a view lives on. Old links named views of one shared page (`/#/ST3`); each now has one home round.
const aliases = { '': 'st', all: 'r1', today: 'st' };
export const roundOf = (view) => {
  const v = aliases[view] ?? view;
  return rounds.find((r) => r.own.includes(v) || r.sets[v] || r.rec.view === v);
};
