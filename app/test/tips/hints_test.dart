import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/tips/checklist.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final start = DateTime(2026, 11, 8, 9);
  final later = start.add(const Duration(seconds: 11));

  HintContext context({
    HintPlatform platform = HintPlatform.android,
    bool firstSession = false,
    bool covered = false,
    bool listHidden = false,
    int items = 6,
    int stores = 1,
    int members = 1,
    bool owner = true,
    HouseholdKind? kind,
    bool canAddHousehold = false,
  }) => HintContext(
    platform: platform,
    startedAt: start,
    firstSession: firstSession,
    covered: covered,
    listHidden: listHidden,
    items: items,
    stores: stores,
    members: members,
    owner: owner,
    kind: kind,
    canAddHousehold: canAddHousehold,
  );

  Hint hint(
    HintId id, {
    Signal? retiredBy,
    Set<HintPlatform>? platforms,
    HintAction? action,
    bool Function(UsageLog log)? when,
  }) => Hint(
    id: id,
    title: (l10n) => id.wire,
    body: (l10n) => id.wire,
    icon: Icons.lightbulb_outline,
    retiredBy: retiredBy,
    platforms: platforms,
    action: action,
    when: (log, _, _) => when?.call(log) ?? true,
  );

  final edit = hint(HintId.editLongPress, retiredBy: Signal.itemEdited);
  final amounts = hint(HintId.quickAddAmounts, retiredBy: Signal.amountAdd);
  UsageLog fresh() => UsageLog(since: start.subtract(const Duration(days: 3)));

  group('nextHint', () {
    test('picks the first eligible hint', () {
      expect(nextHint([edit, amounts], fresh(), later, context()), edit);
    });

    test('waits for its trigger', () {
      final siri = hint(HintId.siri, when: (log) => log.activeDays >= 3);
      var log = fresh();
      expect(nextHint([siri], log, later, context()), isNull);
      for (var day = 0; day < 3; day++) {
        log = log.activeOn(start.add(Duration(days: day)));
      }
      expect(nextHint([siri], log, later, context()), siri);
    });

    test('shows nothing in the first 10 s after the start', () {
      expect(
        nextHint(
          [edit],
          fresh(),
          start.add(const Duration(seconds: 9)),
          context(),
        ),
        isNull,
      );
      expect(
        nextHint([edit], fresh(), start.add(quietAfterStart), context()),
        edit,
      );
    });

    test('shows nothing over a sheet, dialog or the keyboard', () {
      expect(nextHint([edit], fresh(), later, context(covered: true)), isNull);
    });

    test('shows nothing in onboarding or with the List tab away', () {
      expect(
        nextHint([edit], fresh(), later, context(listHidden: true)),
        isNull,
      );
    });

    test('shows nothing in the first session before the first item', () {
      expect(
        nextHint([edit], fresh(), later, context(firstSession: true, items: 0)),
        isNull,
      );
      expect(
        nextHint([edit], fresh(), later, context(firstSession: true)),
        edit,
      );
      expect(nextHint([edit], fresh(), later, context(items: 0)), edit);
    });

    test('a used feature retires its hint for good', () {
      final log = fresh().record(Signal.itemEdited);
      expect(nextHint([edit, amounts], log, later, context()), amounts);
    });

    test('X hides a hint for good', () {
      final log = fresh().dismissed(HintId.editLongPress, start);
      expect(
        nextHint([edit], log, later.add(const Duration(days: 30)), context()),
        isNull,
      );
    });

    test('a tapped action retires its hint', () {
      final log = fresh().acted(HintId.editLongPress);
      expect(nextHint([edit], log, later, context()), isNull);
    });

    test('at most one new hint per 24 h', () {
      final log = fresh()
          .shown(HintId.editLongPress, start)
          .acted(HintId.editLongPress);
      expect(nextHint([edit, amounts], log, later, context()), isNull);
      expect(
        nextHint(
          [edit, amounts],
          log,
          start.add(const Duration(hours: 23, minutes: 59)),
          context(),
        ),
        isNull,
      );
      expect(
        nextHint([edit, amounts], log, start.add(newHintEvery), context()),
        amounts,
      );
    });

    test('a hint shown before comes back first, inside the 24 h', () {
      final log = fresh().shown(HintId.quickAddAmounts, start);
      expect(nextHint([edit, amounts], log, later, context()), amounts);
    });

    test('three showings without a tap or X retire a hint', () {
      var log = fresh();
      for (var session = 0; session < 3; session++) {
        expect(nextHint([edit], log, later, context()), edit);
        log = log.shown(HintId.editLongPress, later);
      }
      expect(nextHint([edit], log, later, context()), isNull);
    });

    test('three X in a row pause every hint for 14 days', () {
      final ids = [HintId.siri, HintId.dictation, HintId.homeWidget];
      var log = fresh();
      for (final id in ids) {
        log = log.dismissed(id, start);
      }
      expect(log.pausedUntil, start.add(UsageLog.pauseFor));
      final day13 = start.add(const Duration(days: 13));
      final day14 = start.add(const Duration(days: 14));
      expect(nextHint([edit], log, day13, context()), isNull);
      expect(nextHint([edit], log, day14, context()), edit);
    });

    test('an action between two X ends the streak', () {
      final log = fresh()
          .dismissed(HintId.siri, start)
          .dismissed(HintId.dictation, start)
          .acted(HintId.invitePartner)
          .dismissed(HintId.homeWidget, start);
      expect(log.pausedUntil, isNull);
      expect(nextHint([edit], log, later, context()), edit);
    });

    test('a hint shows only on its platforms', () {
      final phones = hint(
        HintId.dictation,
        platforms: const {HintPlatform.ios, HintPlatform.android},
      );
      expect(nextHint([phones], fresh(), later, context()), phones);
      expect(
        nextHint([phones], fresh(), later, context(platform: HintPlatform.web)),
        isNull,
      );
    });

    test('a household button needs the app to add a household', () {
      final own = hint(HintId.ownHousehold, action: HintAction.addHousehold);
      expect(nextHint([own], fresh(), later, context()), isNull);
      expect(
        nextHint([own], fresh(), later, context(canAddHousehold: true)),
        own,
      );
    });
  });

  group('the catalogue', () {
    Hint? pick(UsageLog log, HintContext c, {DateTime? at}) =>
        nextHint(hints, log, at ?? later, c);

    UsageLog days(int n, {UsageLog? log}) {
      var result = log ?? fresh();
      for (var day = 0; day < n; day++) {
        result = result.activeOn(start.add(Duration(days: day)));
      }
      return result;
    }

    test('every hint has its own id', () {
      expect({for (final h in hints) h.id}, hasLength(hints.length));
      expect({for (final h in hints) h.id}, HintId.values.toSet());
    });

    test('invite-partner: alone with 3 items a day after the start', () {
      final c = context(items: 3);
      expect(pick(fresh(), c)?.id, HintId.invitePartner);
      expect(pick(UsageLog(since: start), c)?.id, isNot(HintId.invitePartner));
      expect(pick(fresh(), context(items: 3, members: 2))?.id, isNull);
      expect(
        pick(fresh(), context(items: 3, kind: HouseholdKind.solo))?.id,
        isNull,
      );
      expect(
        pick(fresh().note(Signal.memberJoined), c)?.id,
        isNot(HintId.invitePartner),
      );
    });

    test('edit-long-press: 5 open items, until the first edit', () {
      final c = context(members: 2, items: 5);
      expect(pick(fresh(), c)?.id, HintId.editLongPress);
      expect(pick(fresh(), context(members: 2, items: 4)), isNull);
      expect(pick(fresh().record(Signal.itemEdited), c), isNull);
    });

    test('quick-add-amounts: 5 typed adds without an amount', () {
      final c = context(members: 2, items: 0);
      var log = fresh();
      for (var i = 0; i < 5; i++) {
        expect(pick(log, c), isNull);
        log = log.record(Signal.plainTypedAdd);
      }
      expect(pick(log, c)?.id, HintId.quickAddAmounts);
      expect(pick(log.record(Signal.amountAdd), c), isNull);
    });

    test('store-order: after the first finished shop with a store', () {
      final c = context(members: 2, items: 0);
      expect(pick(fresh(), c), isNull);
      final shopped = fresh().record(Signal.shopDone);
      expect(pick(shopped, c)?.place, HintPlace.belowEdit);
      expect(pick(shopped, c)?.id, HintId.storeOrder);
      expect(pick(shopped, context(members: 2, items: 0, stores: 0)), isNull);
      expect(pick(shopped.record(Signal.categoryReorder), c), isNull);
    });

    test('add-store: 3 active days without a store', () {
      final c = context(members: 2, items: 0, stores: 0);
      expect(pick(days(2), c), isNull);
      expect(pick(days(3), c)?.id, HintId.addStore);
      expect(pick(days(3).note(Signal.storeAdded), c), isNull);
    });

    test('dictation: 10 typed adds, phones only, above the add bar', () {
      final c = context(members: 2, items: 0);
      var log = fresh();
      for (var i = 0; i < 10; i++) {
        log = log.record(Signal.typedAdd);
      }
      expect(pick(log, c)?.id, HintId.dictation);
      expect(pick(log, c)?.place, HintPlace.aboveAddBar);
      expect(
        pick(log, context(members: 2, items: 0, platform: HintPlatform.web)),
        isNull,
      );
      expect(pick(log.record(Signal.micUsed), c), isNull);
    });

    test('ai-assistant: a club anywhere, or 7 days on a computer', () {
      final club = context(members: 2, items: 0, kind: HouseholdKind.club);
      expect(pick(fresh(), club)?.id, HintId.aiAssistant);
      expect(pick(fresh(), club)?.action, HintAction.access);
      final web = context(members: 2, items: 0, platform: HintPlatform.web);
      expect(pick(days(6), web), isNull);
      expect(pick(days(7), web)?.id, HintId.aiAssistant);
      expect(pick(days(7), context(members: 2, items: 0)), isNot(isNull));
      expect(
        pick(days(7), context(members: 2, items: 0))?.id,
        isNot(HintId.aiAssistant),
      );
      expect(pick(fresh().note(Signal.assistantConnected), club), isNull);
    });

    test('siri: 3 active days, iPhone only, once native Siri is live', () {
      final ios = context(members: 2, items: 0, platform: HintPlatform.ios);
      expect(
        pick(days(3), ios)?.id,
        Environment.nativeSiriLive ? HintId.siri : isNot(HintId.siri),
        reason: 'NATIVE_SIRI_LIVE is ${Environment.nativeSiriLive}',
      );
      expect(
        pick(days(3), context(members: 2, items: 0, stores: 2))?.id,
        isNot(HintId.siri),
      );
    });

    test('siri: offered nowhere while the native-siri hold stands', () {
      final siri = hints.singleWhere((h) => h.id == HintId.siri);
      expect(
        siri.offered(HintPlatform.ios, canAddHousehold: true),
        Environment.nativeSiriLive,
      );
    });

    test('home-widget: 5 active days on a phone, until a widget is placed', () {
      final android = context(members: 2, items: 0);
      expect(pick(days(4), android), isNull);
      expect(pick(days(5), android)?.id, HintId.homeWidget);
      expect(pick(days(5).note(Signal.widgetPlaced), android), isNull);
    });

    test('own-household: a member of another household, once the app can '
        'add one', () {
      final joined = context(members: 2, items: 0, owner: false);
      expect(pick(days(3), joined), isNull, reason: 'gated until job 169b');
      final can = context(
        members: 2,
        items: 0,
        owner: false,
        canAddHousehold: true,
      );
      expect(pick(days(3), can)?.id, HintId.ownHousehold);
      expect(pick(days(3), can)?.action, HintAction.addHousehold);
      expect(pick(days(3).note(Signal.householdOwned), can), isNull);
    });

    test('second-household: 14 active days, once the app can add one', () {
      final c = context(members: 2, items: 0, stores: 2);
      final dismissedOthers = days(14)
          .dismissed(HintId.homeWidget, start)
          .acted(HintId.homeWidget);
      expect(pick(dismissedOthers, c), isNull);
      expect(
        pick(
          dismissedOthers,
          context(members: 2, items: 0, stores: 2, canAddHousehold: true),
        )?.id,
        HintId.secondHousehold,
      );
    });

    for (final locale in AppLocalizations.supportedLocales) {
      test('the amounts hint quotes lines that parse with an amount, '
          '${locale.languageCode}', () {
        final body = lookupAppLocalizations(locale).tipAmountsBody;
        final examples = [
          for (final m in RegExp('[„“]([^“”]+)[“”]').allMatches(body)) m[1]!,
        ];
        expect(examples, hasLength(2));
        for (final line in examples) {
          expect(parseEntry(line).quantity, isNotNull, reason: line);
        }
      });
    }
  });

  group('UsageLog', () {
    test('survives a round trip through its JSON', () {
      final log = fresh()
          .record(Signal.typedAdd)
          .record(Signal.typedAdd)
          .activeOn(start)
          .shown(HintId.siri, start)
          .dismissed(HintId.siri, start)
          .reporting('first_shop');
      final back = UsageLog.parse(log.toJson(), now: later);
      expect(back.toJson(), log.toJson());
      expect(back.count(Signal.typedAdd), 2);
      expect(back.of(HintId.siri).dismissed, isTrue);
    });

    test("reads job 80's dismissed tips as dismissed hints", () {
      final log = UsageLog.parse(
        '{"dismissed": ["edit-long-press", "gone-tip"]}',
        now: start,
      );
      expect(log.of(HintId.editLongPress).dismissed, isTrue);
      expect(log.of(HintId.quickAddAmounts).dismissed, isFalse);
      expect(log.since, start);
    });

    test('an unreadable log starts over', () {
      for (final json in [null, 'not json', '[1]', '{"counts": "many"}']) {
        final log = UsageLog.parse(json, now: start);
        expect(log.since, start, reason: json);
        expect(log.counts, isEmpty, reason: json);
      }
    });

    test('counts a day once', () {
      final log = fresh()
          .activeOn(start)
          .activeOn(start.add(const Duration(hours: 5)))
          .activeOn(start.add(const Duration(days: 1)));
      expect(log.activeDays, 2);
    });

    test('a change that changes nothing keeps the log', () {
      final log = fresh().note(Signal.storeAdded);
      expect(identical(log.note(Signal.storeAdded), log), isTrue);
      final active = log.activeOn(start);
      expect(identical(active.activeOn(start), active), isTrue);
    });
  });

  group('the checklist', () {
    List<ChecklistStep> steps(HouseholdKind? kind, {bool owner = true}) => [
      for (final e in Checklist.of(fresh(), kind: kind, owner: owner).entries)
        e.step,
    ];

    test('a partner household: started, invite, first shop', () {
      expect(steps(HouseholdKind.partner), [
        ChecklistStep.started,
        ChecklistStep.invite,
        ChecklistStep.firstShop,
      ]);
      expect(steps(null), steps(HouseholdKind.partner));
    });

    test('shopping alone: no invite', () {
      expect(steps(HouseholdKind.solo), [
        ChecklistStep.started,
        ChecklistStep.firstShop,
      ]);
    });

    test('a club: the AI assistant too', () {
      expect(steps(HouseholdKind.club), [
        ChecklistStep.started,
        ChecklistStep.invite,
        ChecklistStep.firstShop,
        ChecklistStep.assistant,
      ]);
    });

    test('someone who joined: no invite', () {
      final checklist = Checklist.of(
        fresh(),
        kind: HouseholdKind.family,
        owner: false,
      );
      expect(checklist.joined, isTrue);
      expect(checklist.has(ChecklistStep.invite), isFalse);
    });

    test('a tick, a saved edit or a finished shop does the first shop', () {
      bool shopped(UsageLog log) => Checklist.of(
        log,
        kind: HouseholdKind.solo,
        owner: true,
      ).entries.any((e) => e.step == ChecklistStep.firstShop && e.done);
      expect(shopped(fresh()), isFalse);
      expect(shopped(fresh().record(Signal.itemTicked)), isTrue);
      expect(shopped(fresh().record(Signal.itemEdited)), isTrue);
      expect(shopped(fresh().record(Signal.shopDone)), isTrue);
    });

    test('steps are done by what the log saw', () {
      final log = fresh()
          .note(Signal.memberJoined)
          .record(Signal.shopDone)
          .note(Signal.assistantConnected);
      final checklist = Checklist.of(
        log,
        kind: HouseholdKind.club,
        owner: true,
      );
      expect(checklist.open, 0);
      expect(
        Checklist.of(fresh(), kind: HouseholdKind.club, owner: true).open,
        3,
      );
    });
  });
}
