import 'package:family_groceries/push/push_target.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/PUSH.md, "The message": the `data` contract a tap is read from.
void main() {
  const household = '00000000-0000-4000-8000-000000000001';
  const list = '00000000-0000-4000-8000-000000000002';
  const target = PushTarget(householdId: household, listId: list);

  test('a list message names its household and list', () {
    expect(
      pushTargetOf({
        'kind': 'list',
        'v': '1',
        'household_id': household,
        'list_id': list,
      }),
      target,
    );
  });

  test('a newer version is read while its ids are there', () {
    expect(
      pushTargetOf({
        'kind': 'list',
        'v': '7',
        'household_id': household,
        'list_id': list,
        'item_id': '00000000-0000-4000-8000-000000000003',
      }),
      target,
    );
    expect(
      pushTargetOf({
        'kind': 'list',
        'household_id': household,
        'list_id': list,
      }),
      target,
    );
  });

  test('an unknown kind, a missing or empty id opens nothing', () {
    expect(
      pushTargetOf({
        'kind': 'trip',
        'v': '1',
        'household_id': household,
        'list_id': list,
      }),
      isNull,
    );
    expect(pushTargetOf({'kind': 'list', 'household_id': household}), isNull);
    expect(
      pushTargetOf({'kind': 'list', 'household_id': '', 'list_id': list}),
      isNull,
    );
    expect(pushTargetOf({'household_id': household, 'list_id': list}), isNull);
    expect(pushTargetOf(const {}), isNull);
  });
}
