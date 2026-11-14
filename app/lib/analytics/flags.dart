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

/// PostHog feature flags, the app's runtime toggles (job 44,
/// docs/ANALYTICS.md "Feature flags"). Read a toggle with [isOn] wherever it
/// matters; nothing else in the app reads PostHog flags.
///
/// Every flag is off until PostHog turned it on for this install: before
/// the analytics yes (the SDK does not run, so no flag request is made),
/// after a no, in a build without a project key, and offline until a first
/// answer. Later the SDK serves the values it last received, also offline.
/// Changelog and release holds stay in `releases/flags.json`, not here.
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

  /// Every flag back to off; `Analytics` only.
  void clear() => emit(const {});
}
