import 'dart:convert';

import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/new_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const draft = OnboardingDraft(
    step: OnboardingStep.need,
    kinds: [HouseholdKind.club, HouseholdKind.solo],
    otherKind: 'Nachbarn',
    name: 'Kegelclub',
    stores: [
      NewStore('REWE', chain: (chain: 'rewe', country: 'DE')),
      NewStore('Bäcker Kühn'),
    ],
    items: [DraftItem(id: 'a', text: '2 Gurken')],
    userId: 'u',
    householdId: 'h',
    ownHouseholdFor: 'u',
    requestId: 'r',
  );

  test('a draft reads back as it was written', () {
    expect(
      OnboardingDraft.fromJson(jsonDecode(jsonEncode(draft.toJson()))),
      draft,
    );
  });

  test('a draft from before job 168c reads as an ordinary one', () {
    final json = {...draft.toJson()}
      ..remove('own_household_for')
      ..remove('request_id');
    final read = OnboardingDraft.fromJson(json);
    expect(read?.ownHouseholdFor, isNull);
    expect(read?.requestId, isNull);
    expect(read?.items, draft.items);
  });

  test('a draft from before job 321 reads its stores as plain ones', () {
    final json = {
      ...draft.toJson(),
      'stores': ['REWE', 'Bäcker Kühn', 7],
    };
    expect(OnboardingDraft.fromJson(json)?.stores, const [
      NewStore('REWE'),
      NewStore('Bäcker Kühn'),
    ]);
  });

  test('a draft of a newer build or a cut-off write is no draft', () {
    expect(OnboardingDraft.fromJson({...draft.toJson(), 'step': 'pets'}), null);
    expect(OnboardingDraft.fromJson({'step': 'who'}), null);
    expect(OnboardingDraft.fromJson('who'), null);
  });

  test('an unknown kind or a broken item is left out, the rest kept', () {
    final json = {
      ...draft.toJson(),
      'kinds': ['pets', 'family'],
      'items': [
        {'id': 'a'},
        {'id': 'b', 'text': 'Milch'},
      ],
    };
    final read = OnboardingDraft.fromJson(json);
    expect(read?.kinds, [HouseholdKind.family]);
    expect(read?.items, [const DraftItem(id: 'b', text: 'Milch')]);
  });

  test('the first kind makes the household, the others wait', () {
    expect(draft.kind, HouseholdKind.club);
    expect(draft.laterKinds, [HouseholdKind.solo]);
    expect(const OnboardingDraft().kind, isNull);
  });
}
