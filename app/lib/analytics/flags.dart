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

/// The flag that turns on JH2, joining a household in the browser first
/// (job 271): the start screen's two buttons, „Bestehendem Haushalt
/// beitreten“ on the name step, the sign-in sheet for an invite, joining
/// from a link without asking again, the approval wait's new words, the QR
/// code on a person's invite and the web app's „Öffnen“ card on phones.
const joinHouseholdJh2Flag = 'join-household-jh2';

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
