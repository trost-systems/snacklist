export type OptionId = 'today' | 'fh1' | 'fh2' | 'fh3' | 'fh4' | 'fh5';
export const OPTION_ORDER: readonly OptionId[] = ['today', 'fh1', 'fh2', 'fh3', 'fh4', 'fh5'];

export type ControlKind = 'chip' | 'button' | 'textButton' | 'field' | 'row';

export type Token =
  | 'accent'
  | 'on-accent'
  | 'accent-soft'
  | 'honey'
  | 'on-honey'
  | 'text'
  | 'surface'
  | 'surface-raised'
  | 'border'
  | 'edge'
  | 'brand'
  | 'honey-edge'
  | 'surface-edge';

export type Layer =
  | { t: 'stroke'; outset: number; width: number; color: Token; includeEdge?: boolean }
  | { t: 'bar'; thickness: number; inset: number; color: Token }
  | { t: 'glow'; outset: number; width: number; blur: number; opacity: number; color: Token; includeEdge?: boolean }
  | { t: 'overlay'; color: 'ink' | Token; opacity: number };

export interface FocusLook {
  layers: Layer[];
  face?: Token;
  text?: Token;
  contour?: Token;
}

export interface ControlCtx {
  kind: ControlKind;
  honey: boolean;
  faced: boolean;
  /** Its contour's width: 1 for a chip (Material's side), 2 for the rest. */
  contour: number;
}

export interface Spacing {
  chips: number;
  stack: number;
  inline: number;
}

export type Room = Record<ControlKind, { t: number; b: number; x: number }>;

const NO_ROOM: Room = {
  chip: { t: 0, b: 0, x: 0 },
  textButton: { t: 0, b: 0, x: 0 },
  button: { t: 0, b: 0, x: 0 },
  field: { t: 0, b: 0, x: 0 },
  row: { t: 0, b: 0, x: 0 },
};

export interface OptionDef {
  id: OptionId;
  code: string;
  slug: string;
  name: { en: string; de: string };
  line: { en: string; de: string };
  spacing: Spacing;
  room: Room;
  focus: (c: ControlCtx) => FocusLook;
}

const RING = 3;
const GAP = 2;

const focusColourForFace = (c: ControlCtx): Token => (c.honey ? 'on-honey' : 'accent');

export const OPTIONS: Record<OptionId, OptionDef> = {
  today: {
    id: 'today',
    code: 'Today',
    slug: 'outer-ring',
    name: { en: 'Today: ring outside', de: 'Heute: Ring außen' },
    line: {
      en: 'Production: a field turns its contour cobalt and adds a 3 px ring 2 px outside it (it focuses as soon as it opens, by touch too); buttons get the ring; chips and rows a 12 % grey fill, the text button a 10 % cobalt fill.',
      de: 'Produktion: Ein Feld färbt seine Kontur kobaltblau und bekommt einen 3-px-Ring 2 px außerhalb (es ist fokussiert, sobald es aufgeht, auch per Touch); Knöpfe bekommen den Ring; Chips und Zeilen eine 12-%-Grautönung, der Textknopf eine 10-%-Kobalttönung.',
    },
    spacing: { chips: 8, stack: 8, inline: 4 },
    room: NO_ROOM,
    focus: (c) => {
      switch (c.kind) {
        case 'button':
          return { layers: [{ t: 'stroke', outset: GAP + RING / 2, width: RING, color: 'accent' }] };
        case 'field':
          return { contour: 'brand', layers: [{ t: 'stroke', outset: GAP + RING / 2, width: RING, color: 'accent' }] };
        case 'chip':
        case 'row':
          return { layers: [{ t: 'overlay', color: 'ink', opacity: 0.12 }] };
        case 'textButton':
          return { layers: [{ t: 'overlay', color: 'brand', opacity: 0.1 }] };
      }
    },
  },
  fh1: {
    id: 'fh1',
    code: 'FH1',
    slug: 'inset-ring',
    name: { en: 'Inset ring', de: 'Ring innen' },
    line: {
      en: 'The contour turns cobalt and the same 3 px ring grows inward from it: nothing reaches past the control, so every gap stays.',
      de: 'Die Kontur wird kobaltblau und derselbe 3-px-Ring wächst von ihr nach innen: nichts ragt über das Element hinaus, jeder Abstand bleibt.',
    },
    spacing: { chips: 8, stack: 8, inline: 4 },
    room: NO_ROOM,
    focus: (c) => ({
      contour: focusColourForFace(c),
      layers: [{ t: 'stroke', outset: -((c.faced ? c.contour : 0) + RING / 2), width: RING, color: focusColourForFace(c) }],
    }),
  },
  fh2: {
    id: 'fh2',
    code: 'FH2',
    slug: 'reserved-ring',
    name: { en: 'Ring with room', de: 'Ring mit Platz' },
    line: {
      en: 'A thinner 2 px ring outside, and 4 px more between controls (12 instead of 8, 8 instead of 4 beside the field), so a focused ring still leaves today’s air. Rows take the inset ring.',
      de: 'Ein schmalerer 2-px-Ring außen und 4 px mehr zwischen den Elementen (12 statt 8, neben dem Feld 8 statt 4), damit ein Ring noch die heutige Luft lässt. Zeilen bekommen den Ring innen.',
    },
    spacing: { chips: 12, stack: 12, inline: 8 },
    room: NO_ROOM,
    focus: (c) =>
      c.kind === 'row'
        ? { layers: [{ t: 'stroke', outset: -(1 + RING / 2), width: RING, color: 'accent' }] }
        : { layers: [{ t: 'stroke', outset: GAP + 1, width: 2, color: 'accent', includeEdge: true }] },
  },
  fh3: {
    id: 'fh3',
    code: 'FH3',
    slug: 'filled',
    name: { en: 'Filled', de: 'Gefüllt' },
    line: {
      en: 'The focused control turns cobalt with light text (a honey one turns navy with honey text), like a lit key. A field keeps its face for typing and gets a tint with an inner ring.',
      de: 'Das fokussierte Element wird kobaltblau mit heller Schrift (ein gelbes wird dunkelblau mit gelber Schrift), wie eine beleuchtete Taste. Ein Feld bleibt zum Tippen hell, mit Tönung und Ring innen.',
    },
    spacing: { chips: 8, stack: 8, inline: 4 },
    room: NO_ROOM,
    focus: (c) =>
      c.kind === 'field'
        ? {
            face: 'accent-soft',
            layers: [{ t: 'stroke', outset: -(c.contour + RING / 2), width: RING, color: 'accent' }],
          }
        : c.honey
          ? { face: 'on-honey', text: 'honey', layers: [] }
          : { face: 'accent', text: 'on-accent', layers: [] },
  },
  fh4: {
    id: 'fh4',
    code: 'FH4',
    slug: 'accent-bar',
    name: { en: 'Underline bar', de: 'Balken unten' },
    line: {
      en: 'A bar along the bottom inside the control, as thick as WCAG’s area rule needs for its size (4 to 8 px), like a tab’s indicator.',
      de: 'Ein Balken unten im Element, so dick, wie die WCAG-Flächenregel für seine Größe verlangt (4 bis 8 px), wie bei einem Tab.',
    },
    spacing: { chips: 8, stack: 8, inline: 4 },
    room: { ...NO_ROOM, textButton: { t: 0, b: 8, x: 0 } },
    focus: (c) => ({
      layers: [{ t: 'bar', thickness: 0, inset: c.faced ? c.contour : 0, color: focusColourForFace(c) }],
    }),
  },
  fh5: {
    id: 'fh5',
    code: 'FH5',
    slug: 'glow',
    name: { en: 'Glow', de: 'Leuchten' },
    line: {
      en: 'A 3 px accent halo hugging the contour, fading out over about 6 px. Rows glow inward instead.',
      de: 'Ein 3-px-Lichtsaum direkt an der Kontur, der über etwa 6 px ausläuft. Zeilen leuchten nach innen.',
    },
    spacing: { chips: 8, stack: 8, inline: 4 },
    room: NO_ROOM,
    focus: (c) =>
      c.kind === 'row'
        ? {
            layers: [
              { t: 'glow', outset: -5, width: 4, blur: 3, opacity: 0.45, color: 'accent' },
              { t: 'stroke', outset: -1.5, width: 3, color: 'accent' },
            ],
          }
        : {
            layers: [
              { t: 'glow', outset: 4, width: 4, blur: 3, opacity: 0.45, color: 'accent', includeEdge: true },
              { t: 'stroke', outset: 1.5, width: 3, color: 'accent', includeEdge: true },
            ],
          },
  },
};
