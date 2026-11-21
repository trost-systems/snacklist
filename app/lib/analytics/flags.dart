import 'package:family_groceries/analytics/posthog_client.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The flag that offers the public REST API: its keys under Zugänge (job
/// 73) and its line on the Premium page (job 87).
const publicApiFlag = 'public-api';

/// The flag that shows the Verlauf tab, the grocery log (job 199).
const groceryLogFlag = 'grocery-log';

/// The flag that shows prices on the list's rows, the list's total and
/// the household's currency (job 190). Free for everyone.
const pricesFlag = 'prices-and-trip-total';

/// The flag that turns on trip mode: the question on a tick, the trip strip
/// with its stopwatch and the trip's summary (job 234).
const tripModeFlag = 'trip-mode';

/// The flag that shows which list Siri, Alexa and AI assistants add to when
/// no list is named, next to the household they use (job 207).
const defaultListFlag = 'default-list-voice-target';

/// The flag that shows the decluttered list (job 229): one switcher for
/// household and list in a see-through header, the total as a row of the
/// list, and the switcher sheet with a page per household and its members.
const listDeclutterFlag = 'list-declutter';

/// The flag that turns on feedback with a screenshot (job 267, FB2): a
/// shake on iOS and Android asks to report the screen, the annotator marks
/// up a screenshot, the form sends it, and Einstellungen' shake switch.
const feedbackFb2Flag = 'feedback-fb2';

/// The flag that turns on Feedback & ideas (job 268, FB4): More's row opens
/// a page with the user's own notes, their status and Snacklist Support's
/// replies, a badge for new answers, and the ideas the household can +1.
/// Off, More's row opens the form as before.
const feedbackFb4Flag = 'feedback-fb4';

/// The flag that turns on JH2, joining a household in the browser first
/// (job 271): the start screen's two buttons, „Bestehendem Haushalt
/// beitreten“ on the name step, the sign-in sheet for an invite, joining
/// from a link without asking again, the approval wait's new words, the QR
/// code on a person's invite and the web app's „Öffnen“ card on phones.
const joinHouseholdJh2Flag = 'join-household-jh2';

/// The flag that keeps the add sheet's rows still while typing (job 272,
/// IN1 and ST1): rows made on the device on every key with a category
/// guess, the server's rows merged in below them, no change under a finger,
/// and a new grocery's store from what the household buys most for its
/// category.
const inputStableRowsFlag = 'input-stable-rows';

/// The flag that ranks the add sheet's rows on the device (job 274): the
/// catalog follows the server's changes once a day, the household's index
/// comes with each resync, and every key shows the rows the server would.
const onDeviceCatalogFlag = 'on-device-catalog';

/// The flag that shows each add land in the list (job 276): while the add
/// sheet is open the list behind it drops its store and category headings
/// and ends in „Gerade hinzugefügt“ with this opening's adds, and slides
/// back into its stores and categories when the sheet closes. After an add
/// the sheet shows the item's details until the next letter, and while the
/// server's suggestions load a thin line runs above the field and rows that
/// answer an older text are dimmed.
const addFeedbackListFlag = 'add-feedback-list';

/// The flag that makes the add sheet compact (job 322, AS1), on top of
/// [addFeedbackListFlag]: no Schließen key, only the grab handle; after an
/// add no „Hinzugefügt“ note and no Rückgängig, but one row of chips (Menge
/// with its steppers, the store, the category and Details) whose options
/// fold out as one sideways line; the sheet as tall as what it shows; the
/// list behind it only the last two adds. A swipe down, a tap beside it,
/// the system back or Enter in the empty field closes it.
const addSheetCompactFlag = 'add-sheet-compact';

/// The flag for the add sheet's match rows (job 324, AM2), on top of
/// [addSheetCompactFlag]: while typing, the items already on the list that
/// are the same thing show as rows that merge into one, tick it off or put
/// a ticked one back, each with one tap, above the + row, which (like
/// Enter) adds the typed item separately. Only ticked ones: Enter puts the
/// first back.
const addMatchRowsFlag = 'add-match-rows';

/// The flag that asks for the user's name (job 297, DN3 and DE1): right
/// after the sign-in a screen asks „Wie sollen wir dich nennen?“, prefilled
/// with a Google or Apple name and required without one (once, with „Jetzt
/// nicht“, for members whose name is still their e-mail's), and Konto gets
/// a row to change it. Off, neither shows.
const displayNameFlag = 'display-name';

/// The flag that turns on reporting content in the app (job 281, RC2):
/// More's feedback row says „Auch: Inhalte melden“, Feedback & ideas (or,
/// without FB4, the feedback form opened from More) has „Inhalt melden“,
/// which opens the report form (Legal B.4) with its picker of the
/// household's items and lists and the confirmation with the report's
/// number. Off, nothing of it shows.
const reportContentEntryFlag = 'report-content-entry';

/// The flag that opens a store's chain app (job 313, DL1 and SS): the app
/// key in a linked store's section header with its one-time tip, the store
/// screen's app card with the app to open and its chain, chains suggested
/// while a store is named, „Ist das …?“ when a saved name is a chain, and
/// the list's card asking about existing stores once. Off, none shows.
const openStoreAppFlag = 'open-store-app';

/// The flag for the store rating prompt's trip moments (job 326): the
/// prompt after a fresh trip summary, all planned items bought, is left
/// (ST1), or once „Kaufst du gerade ein?“ after the emptying tick is
/// answered „Nein“ (ST2); none while a trip runs or after an emptying taken
/// back; held back after a failed trip save, a join, a household switch or
/// a bug note; at most two a year, 180 days apart. Off, today's prompt after
/// an emptied list.
const ratingTriggersV2Flag = 'rating-triggers-v2';

/// The flag that hides categories from what users see (job 350): no
/// category headings in the list, no category chip in the add and edit
/// sheets, no category order on the store screens. Items keep their order;
/// categories still sort them underneath.
const hideCategoriesFlag = 'hide-categories';

/// PostHog feature flags, the app's runtime toggles (job 44,
/// docs/ANALYTICS.md "Feature flags"). Read a toggle with [isOn] wherever it
/// matters; nothing else in the app reads PostHog flags.
///
/// After the analytics yes PostHog evaluates flags for this install (the
/// SDK, which serves the values it last received, also offline). Without
/// one, every install shares one evaluation ([sharedFlagsId]), cached on the
/// device without an id. Every flag is off until a first answer, and in a
/// build without a project key. Changelog and release holds stay in
/// `releases/flags.json`, not here.
class Flags({
  /// On whatever PostHog serves: the `FLAGS_ON` define of a build that
  /// cannot reach PostHog.
  final Set<String> forced = const {},
}) extends Cubit<Map<String, bool>> {
  this : super(const {});

  /// Whether the flag [key] is on for this install; off when unknown.
  bool isOn(String key) => forced.contains(key) || (state[key] ?? false);

  /// The values PostHog served; `Analytics` only.
  void replace(Map<String, bool> values) => emit(Map.unmodifiable(values));
}
