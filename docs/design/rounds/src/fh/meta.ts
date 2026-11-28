export const MEASURED = {
  method:
    'scripts/verify-fh.mjs, Chromium, 390×844 phone, device scale 1, every control on whole pixels (line heights rounded to whole px, the step body top-aligned while measuring), soft look (RD1, live) unless a column says hex. Each control is screenshotted unfocused and focused; a pixel counts as changed at 1.1:1 or more. Gaps are px from layout, minus how far the changed pixels reach past the control on that side. WCAG 2.4.13 (focus appearance): changed pixels at 3:1 or more near the control, against the area of a 2 px perimeter of the unfocused control; each WCAG cell shows the smallest area ratio of the six controls and, separately, the smallest median contrast of their counted pixels. Antialiasing moves a count by a few px between runs, so the verify accepts ±0.02× and ±0.2:1 there and demands the same pass or FAIL. Largest text: 200 % (Android’s largest) and 310 % (iOS AX5), EN and DE, both looks.',
  columns: [
    'Option',
    'Chip ↔ next chip, px (unfocused → focused)',
    'Field ↔ check button',
    'Field ↔ chips above',
    'Continue ↔ Skip',
    'Paint on neighbouring list rows',
    'WCAG 2.4.13, light (smallest area ratio, smallest median contrast of six controls)',
    'WCAG 2.4.13, dark',
    'WCAG 2.4.13, light, hex',
    'WCAG 2.4.13, dark, hex',
    'Layout shift on focus',
    'Largest text: clipped labels; indicator over glyphs',
  ],
  rows: [
    ['Today', '8 → 8', '4 → overlaps 1', '16 → 11', '8 → 7', 'none', 'FAIL 0.00×, 0.0:1', 'FAIL 0.00×, 0.0:1', 'FAIL 0.00×, 0.0:1', 'FAIL 0.00×, 0.0:1', '0 px', '0 clipped; 0 px over text'],
    ['FH1', '8 → 8', '4 → 4', '16 → 16', '8 → 8', 'none', 'pass 1.35×, 8.2:1', 'pass 1.37×, 8.4:1', 'pass 1.33×, 8.2:1', 'pass 1.36×, 8.4:1', '0 px', '0 clipped; 0 px over text'],
    ['FH2', '12 → 8', '8 → 4', '20 → 16', '12 → 8', 'none', 'pass 1.03×, 8.2:1', 'pass 1.04×, 9.5:1', 'pass 1.02×, 8.2:1', 'pass 1.04×, 9.5:1', '0 px', '0 clipped; 0 px over text'],
    ['FH3', '8 → 8', '4 → 4', '16 → 16', '8 → 8', 'none', 'pass 1.42×, 8.2:1', 'pass 1.43×, 8.4:1', 'pass 1.41×, 8.2:1', 'pass 1.42×, 8.4:1', '0 px', '0 clipped; fill under text'],
    ['FH4', '8 → 8', '4 → 4', '16 → 16', '8 → 8', 'none', 'pass 1.10×, 8.2:1', 'pass 1.10×, 8.4:1', 'pass 1.10×, 8.2:1', 'pass 1.10×, 8.4:1', '0 px', '0 clipped; 0 px over text'],
    ['FH5', '8 → overlaps 1', '4 → overlaps 3', '16 → 6', '8 → overlaps 1', 'none', 'pass 1.48×, 8.2:1', 'pass 1.48×, 9.5:1', 'pass 1.46×, 8.2:1', 'pass 1.48×, 9.5:1', '0 px', '0 clipped; 0 px over text'],
  ] as string[][],
  notes: [
    'Today: the chips, the text button and list rows show focus as a 12 % grey (10 % cobalt) fill, which changes no pixel by 3:1, so they fail focus appearance in both themes; the field and the buttons pass with their outer ring. The real web build (job 485 reproduction, origin/main 6fb941fa4) measured the same ring: 5 px past the field, 1 px over the check button, 3 px left to the chips. It uses desktop density (30 px chips, rows 8 px apart); this phone replica uses phone density (32 px chips in 48 px tap targets, rows 24 px apart), so its field-to-chips gap reads 16 → 11 instead of 8 → 3: the same 5 px reach.',
    'The field focuses as soon as it opens, by touch too, so its indicator is the one every user sees; the others show for keyboard, switch and screen-reader focus.',
    'FH2 meets the area rule by only 2 to 4 % (1.02× to 1.04×): its 2 px ring is outside, so its perimeter is just longer than the control’s. It also moves the whole step: 4 px more between every row of chips and the buttons.',
    'FH4’s bar is 4 to 8 px, the thinnest that meets the area rule for each control’s size; the text button gets 8 px more room below its label (none at 100 %). A honey bar was not built: honey on a white face is 1.3:1.',
    'Largest text: the own-store field stays 48 px tall in production (store_name_field.dart), so at 310 % its text is cut in every option, the focus style aside (FH-Q5), and at 200 % its text fills it: an inside indicator can touch a glyph by a few px there (0 to 3 px between runs). The column leaves the field out. Indicator over glyphs counts pixels where both the indicator and a glyph change the screen by 1.5:1; FH3’s fill sits under the text by design.',
    'The verify passed 5 fresh runs in a row with these rows.',
  ],
};

export const RECOMMENDATION = {
  en: [
    'FH1, the inset ring. Every gap stays what it is unfocused (8 → 8 between chips, 4 → 4 beside the field, 8 → 8 between the buttons), because nothing is drawn past the control. It is one style for every control, where today mixes an outer ring with grey fills that fail the contrast rule; it keeps today’s 3 px cobalt and the field’s cobalt contour, so it reads as the same app; it follows the hexagon and the soft shapes alike; and it passes WCAG 2.4.13 in both themes and looks with at least 1.33×. On a honey control it turns navy, because cobalt-light on honey is only 1.6:1 in dark.',
    'Runner-up: FH4, the underline bar. Also no change to any gap and a pass everywhere, and it reads like a tab or a Material text field. It came second because its bar changes thickness with the control (4 to 8 px), it needs extra room under the text button’s label at large text, and on chips it is easy to read as “selected”.',
    'Not recommended: FH3 (filled) is the boldest and keeps every gap, but a cobalt chip competes with the honey “picked” state, and a honey button turns navy when focused. FH2 keeps a ring outside but costs 4 px of air everywhere, all the time. FH5’s glow is soft but still reaches into the gaps (8 → overlaps 1).',
  ],
  de: [
    'FH1, der Ring innen. Jeder Abstand bleibt, wie er ohne Fokus ist (8 → 8 zwischen Chips, 4 → 4 neben dem Feld, 8 → 8 zwischen den Knöpfen), weil nichts über das Element hinaus gezeichnet wird. Es ist ein Stil für alle Elemente, wo heute ein Ring außen und graue Flächen gemischt sind, die die Kontrastregel nicht erfüllen; es behält das heutige 3-px-Kobaltblau und die kobaltblaue Feldkontur und wirkt so wie dieselbe App; es folgt Sechseck und weichen Formen gleich; und es erfüllt WCAG 2.4.13 in beiden Themes und Looks mit mindestens 1,33×. Auf einem gelben Element wird es dunkelblau, weil Hellkobalt auf Gelb im Dunkelmodus nur 1,6:1 hat.',
    'Zweite Wahl: FH4, der Balken unten. Auch er ändert keinen Abstand und besteht überall, und er liest sich wie ein Tab oder ein Material-Textfeld. Er ist Zweiter, weil der Balken mit dem Element seine Dicke ändert (4 bis 8 px), unter der Schrift des Textknopfs bei großer Schrift mehr Platz braucht und auf Chips leicht als „ausgewählt“ gelesen wird.',
    'Nicht empfohlen: FH3 (gefüllt) ist am deutlichsten und hält jeden Abstand, aber ein kobaltblauer Chip konkurriert mit dem gelben „gewählt“, und ein gelber Knopf wird beim Fokus dunkelblau. FH2 behält einen Ring außen, kostet aber überall und immer 4 px Luft. FH5 leuchtet weich, reicht aber trotzdem in die Abstände (8 → 1 px Überlappung).',
  ],
};

export const QUESTIONS: { id: string; en: string; de: string; default: { en: string; de: string } }[] = [
  {
    id: 'FH-Q1',
    en: 'Which option should the app build?',
    de: 'Welche Option soll die App bekommen?',
    default: { en: 'FH1', de: 'FH1' },
  },
  {
    id: 'FH-Q2',
    en: 'Should the chips, the text button, list rows and the stores screen’s rows get the same indicator as fields and buttons, replacing today’s grey fill?',
    de: 'Sollen Chips, Textknopf, Listenzeilen und die Zeilen der Läden-Seite denselben Fokus wie Felder und Knöpfe bekommen, statt der heutigen grauen Fläche?',
    default: { en: 'yes: today’s fill fails 3:1', de: 'ja: die heutige Fläche verfehlt 3:1' },
  },
  {
    id: 'FH-Q3',
    en: 'Should a text field keep showing its indicator after a tap (touch), as Flutter does today, or only for keyboard focus?',
    de: 'Soll ein Textfeld seinen Fokus auch nach einem Tipp (Touch) zeigen, wie Flutter es heute tut, oder nur bei Tastaturfokus?',
    default: { en: 'keep it: it marks where typing goes', de: 'behalten: es zeigt, wohin getippt wird' },
  },
  {
    id: 'FH-Q4',
    en: 'On a honey control (picked chip, main button) the indicator turns navy instead of cobalt. Fine, or should honey controls keep cobalt in light mode at least?',
    de: 'Auf einem gelben Element (gewählter Chip, Hauptknopf) wird der Fokus dunkelblau statt kobaltblau. In Ordnung, oder sollen gelbe Elemente zumindest im hellen Modus kobaltblau behalten?',
    default: { en: 'navy in both themes, one rule', de: 'dunkelblau in beiden Themes, eine Regel' },
  },
  {
    id: 'FH-Q5',
    en: 'The own-store field is fixed at 48 px, so at the largest text its text is cut. Fix that with the focus change, or separately?',
    de: 'Das Feld für den eigenen Laden ist fest 48 px hoch, bei größter Schrift wird der Text abgeschnitten. Mit der Fokus-Änderung beheben oder getrennt?',
    default: { en: 'separately, its own small job', de: 'getrennt, eigener kleiner Auftrag' },
  },
  {
    id: 'FH-Q6',
    en: 'Roll it out behind a flag (soft and hex looks both), or ship it straight away as a fix?',
    de: 'Hinter einem Flag ausrollen (für beide Looks) oder direkt als Korrektur ausliefern?',
    default: { en: 'straight away: no layout change, contrast only goes up', de: 'direkt: kein Layout-Wechsel, der Kontrast steigt nur' },
  },
];
