import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/log/model.dart' as log;
import 'package:family_groceries/tips/checklist.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/trip/model.dart' as trip;
import 'package:flutter_test/flutter_test.dart';

/// The catalog lists the values of the features' enums itself, since
/// analytics imports no feature (job 305): a value a feature adds is refused
/// until the catalog admits it, and this test names the one to add.
void main() {
  Set<String> allowed(String event, String property) =>
      (eventCatalog[event]![property]! as OneOf).values;
  Set<String> names(List<Enum> values) => {for (final v in values) v.name};

  test('invite_sent admits every channel, place and kind of invite', () {
    expect(allowed('invite_sent', 'channel'), {
      for (final c in InviteChannel.values) c.wire,
    });
    expect(allowed('invite_sent', 'context'), names(InviteContext.values));
    expect(allowed('invite_sent', 'kind'), names(InviteKind.values));
  });

  test('the hint events admit every hint', () {
    for (final event in ['hint_shown', 'hint_dismissed', 'hint_acted']) {
      expect(allowed(event, 'hint_id'), {
        for (final id in HintId.values) id.wire,
      });
    }
  });

  test('checklist_step_done admits every step but the start', () {
    expect(allowed('checklist_step_done', 'step'), {
      for (final s in ChecklistStep.values)
        if (s != ChecklistStep.started) s.wire,
    });
  });

  test('the trip events admit every source and end', () {
    expect(
      allowed('shop_started', 'source'),
      names([
        for (final s in trip.TripSource.values)
          if (s != trip.TripSource.detected) s,
      ]),
      reason: 'a detected trip (job 352) never starts on a device',
    );
    expect(allowed('shop_ended', 'reason'), names(trip.TripEnd.values));
    expect(allowed('trip_logged', 'source'), names(log.TripSource.values));
  });
}
