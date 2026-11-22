import 'package:family_groceries/household/household_switcher.dart';
import 'package:family_groceries/household/switcher_sheet.dart';
import 'package:family_groceries/list/list_parts.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/trip/rules.dart' as trip_rules;
import 'package:family_groceries/trip/trip_on_list.dart';
import 'package:material_ui/material_ui.dart';

/// The households and trip mode on the list screen.
final class const ShellListParts() implements ListParts {
  @override
  Future<void> openHouseholds(BuildContext context, {int? openNow}) =>
      showHouseholdSheet(context, openNow: openNow);

  @override
  Future<void> openSwitcher(BuildContext context) => showSwitcherSheet(context);

  @override
  Widget around(Widget list) => TripOnList(child: list);

  @override
  Widget tripStrip({required bool hidden}) => TripStripSlot(hidden: hidden);

  @override
  Widget tripEnded() => const TripEndedSlot();

  @override
  Widget detectedTrip() => const DetectedTripSlot();

  @override
  bool Function(Item item)? boughtOnTrip(
    BuildContext context,
    String? listId,
  ) => switch (runningOn(context, listId)) {
    final trip? => (item) => trip_rules.boughtOnTrip(trip, item),
    null => null,
  };
}
