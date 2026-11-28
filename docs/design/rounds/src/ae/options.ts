import type { L10n } from './data';
import type { DupDefault } from './model';

export const OPTION_ORDER = ['today', 'ae1', 'ae2', 'ae3', 'ae4', 'ae5'] as const;
export type OptionId = (typeof OPTION_ORDER)[number];

/** What sits where the list was while the add surface is open. */
export type Behind =
  | 'lastTwo' // production: the list is swapped for the last two adds, under the scrim
  | 'list' // the real list, undimmed, ending at the sheet
  | 'inline' // no sheet: the field is a row inside the list
  | 'landing' // a card above the sheet with the target store's rows and a ghost for the item
  | 'dimmedList'; // the real list under the scrim; an add flies into its row

export interface OptionSpec {
  code: string;
  slug: string;
  name: L10n;
  line: L10n;
  behind: Behind;
  scrim: boolean;
  dup: DupDefault;
  /** AE1's words: the sheet says what is behind it, where items go, and what a duplicate does. */
  explain: boolean;
  /** Suggestion rows shown before the sheet scrolls; production has 3. */
  sheetRows: number;
  motion: boolean;
}

export const OPTIONS: Record<OptionId, OptionSpec> = {
  today: {
    code: 'Today',
    slug: 'today',
    name: { en: 'Today (main 151458422)', de: 'Heute (main 151458422)' },
    line: {
      en: 'The compact add sheet as users have it. While it is open the list is swapped for the last two adds, under a 40 % black scrim: before the first add the area above the sheet is empty. Enter on an item already on the list takes the honey “As typed” row and adds a second one.',
      de: 'Das kompakte Hinzufügen-Fenster, wie es Nutzer haben. Solange es offen ist, ist die Liste durch die letzten zwei Hinzufügungen ersetzt, unter 40 % Schwarz: vor dem ersten Hinzufügen ist die Fläche über dem Fenster leer. Enter auf einem Artikel, der schon auf der Liste steht, nimmt die gelbe Zeile „Wie getippt“ und legt ihn ein zweites Mal an.',
    },
    behind: 'lastTwo',
    scrim: true,
    dup: 'typed',
    explain: false,
    sheetRows: 3,
    motion: false,
  },
  ae1: {
    code: 'AE1',
    slug: 'ae1-explain',
    name: { en: 'Say what is happening', de: 'Sagen, was passiert' },
    line: {
      en: 'Communication only. Same layout, same visible area. A card at the top of the scrim says the list is behind the sheet, with its count, and closes the sheet on a tap; the sheet says where items go; the adds above it get a heading and their store; a duplicate gets a sentence and rows that say what each does.',
      de: 'Nur Worte. Gleiches Layout, gleich viel sichtbar. Eine Karte oben im Abdunkel-Bereich sagt, dass die Liste hinter dem Fenster liegt, mit ihrer Anzahl, und schließt es beim Antippen; das Fenster sagt, wohin Artikel kommen; die Hinzufügungen darüber bekommen eine Überschrift und ihren Laden; ein Doppelter bekommt einen Satz und Zeilen, die sagen, was sie tun.',
    },
    behind: 'lastTwo',
    scrim: true,
    dup: 'typed',
    explain: true,
    sheetRows: 3,
    motion: false,
  },
  ae2: {
    code: 'AE2',
    slug: 'ae2-list-peeks',
    name: { en: 'The list stays in view', de: 'Die Liste bleibt sichtbar' },
    line: {
      en: 'No scrim and no swap: the real list stays above the sheet, undimmed and scrollable, with the top bar. The sheet shows two suggestion rows instead of three. A new item appears in its place with a honey wash and “New”; a duplicate scrolls its row into view and Enter adds 1 to it.',
      de: 'Kein Abdunkeln, kein Austausch: die echte Liste bleibt über dem Fenster, hell und scrollbar, mit der oberen Leiste. Das Fenster zeigt zwei Vorschläge statt drei. Ein neuer Artikel erscheint an seinem Platz, gelb hinterlegt mit „Neu“; bei einem Doppelten scrollt seine Zeile ins Bild und Enter zählt 1 dazu.',
    },
    behind: 'list',
    scrim: false,
    dup: 'merge',
    explain: false,
    sheetRows: 2,
    motion: false,
  },
  ae3: {
    code: 'AE3',
    slug: 'ae3-inline-row',
    name: { en: 'Add inside the list', de: 'Direkt in der Liste hinzufügen' },
    line: {
      en: 'No sheet. Tapping the add bar turns it into a row at the end of a store in the list; suggestions open under it as rows, and the item is added above it, in its place. The field follows the store of the last add. A duplicate outlines the row already there and Enter adds 1 to it.',
      de: 'Kein Fenster. Das Eingabefeld wird zu einer Zeile am Ende eines Ladens in der Liste; Vorschläge öffnen sich darunter als Zeilen, und der Artikel kommt darüber an seinen Platz. Das Feld folgt dem Laden des letzten Hinzufügens. Bei einem Doppelten wird die vorhandene Zeile umrandet und Enter zählt 1 dazu.',
    },
    behind: 'inline',
    scrim: false,
    dup: 'merge',
    explain: false,
    sheetRows: 3,
    motion: false,
  },
  ae4: {
    code: 'AE4',
    slug: 'ae4-landing-preview',
    name: { en: 'Show where it lands', de: 'Zeigen, wo es landet' },
    line: {
      en: 'Today’s sheet and scrim, but the empty area becomes a card of the target store: before typing, the list’s stores and counts; while typing, the rows around the spot with a dashed ghost of the item; after the add, the item in that spot. A duplicate shows the row already there and what it becomes.',
      de: 'Das heutige Fenster mit Abdunkeln, aber die leere Fläche wird eine Karte des Ziel-Ladens: vor dem Tippen die Läden der Liste mit Anzahl; beim Tippen die Zeilen um die Stelle mit einem gestrichelten Platzhalter; nach dem Hinzufügen der Artikel an dieser Stelle. Ein Doppelter zeigt die vorhandene Zeile und was aus ihr wird.',
    },
    behind: 'landing',
    scrim: true,
    dup: 'merge',
    explain: false,
    sheetRows: 3,
    motion: false,
  },
  ae5: {
    code: 'AE5',
    slug: 'ae5-fly-to-row',
    name: { en: 'Fly into the list', de: 'In die Liste fliegen' },
    line: {
      en: 'Today’s sheet, but the real list stays behind the scrim, dimmed instead of swapped. Each add flies from the field to its row, which lifts out of the scrim for a moment and then settles; a duplicate’s row lifts and its quantity counts up. Reduced motion: no flight, the row only lifts.',
      de: 'Das heutige Fenster, aber die echte Liste bleibt abgedunkelt dahinter, statt ersetzt zu werden. Jedes Hinzufügen fliegt vom Feld zu seiner Zeile, die kurz aus dem Abdunkeln auftaucht und sich dann setzt; bei einem Doppelten taucht seine Zeile auf und die Menge zählt hoch. Weniger Bewegung: kein Flug, die Zeile taucht nur auf.',
    },
    behind: 'dimmedList',
    scrim: true,
    dup: 'merge',
    explain: false,
    sheetRows: 3,
    motion: true,
  },
};
