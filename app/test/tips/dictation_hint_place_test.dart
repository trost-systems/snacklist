// Job 386: the dictation tip is a card at the top of the list, in every look
// and with „Zuletzt verwendet“ open or folded. Before, it floated above the
// shell's tab bar, over the add field and the list's last rows (TestFlight
// 1472).
import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/tips/hints.dart';
import 'package:family_groceries/tips/usage_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/shell_harness.dart';
import '../list/fake_repository.dart';
import 'hints_cubit_test.dart' show MemoryHintStore;

void main() {
  /// Ten typed adds and every other hint done: the dictation tip is next.
  MemoryHintStore dictationDue() {
    var log = UsageLog(since: DateTime(2026, 11));
    for (var i = 0; i < 10; i++) {
      log = log.record(Signal.typedAdd);
    }
    for (final hint in hints.where((h) => h.id != HintId.dictation)) {
      log = log.acted(hint.id);
    }
    return MemoryHintStore()..logs['peter'] = log.toJson();
  }

  /// Bought rows for „Zuletzt verwendet“.
  void bought(FakeRepository repo) {
    for (final (id, name) in [('b1', 'Glühbirne'), ('b2', 'Gläser')]) {
      repo.rows[id] = shellItem(
        id,
        name,
        'lidl',
        'other',
      ).copyWith(status: ItemStatus.bought);
    }
  }

  for (final look in Look.values) {
    for (final usedOpen in [true, false]) {
      final used = usedOpen ? 'open' : 'folded';
      testWidgets('${look.name}, Zuletzt verwendet $used: the tip is the '
          'first row of the list, clear of the add field and the tabs', (
        tester,
      ) async {
        appLook = look;
        addTearDown(() => appLook = Look.hex);
        await pumpShell(
          tester,
          Brightness.dark,
          inset: 34,
          long: true,
          hints: dictationDue(),
          prefs: const ListPrefs(hintDismissed: true),
          seed: bought,
          flags: {
            listDeclutterFlag,
            pricesFlag,
            if (usedOpen) recentlyUsedOpenFlag,
            if (look == Look.soft) redesignRd1Flag,
          },
        );
        // The hints' quiet start runs on the wall clock.
        await tester.runAsync(() {
          final quiet = Completer<void>();
          Timer(quietAfterStart, quiet.complete);
          return quiet.future;
        });
        await tester.pump(quietAfterStart);
        await tester.pumpAndSettle();

        final tip = find.byKey(const ValueKey('tip-dictation'));
        expect(tip, findsOneWidget);
        final card = tester.getRect(tip);
        final field = tester.getRect(find.byType(TextField).first);
        final tabs = tester.getRect(find.text('Liste').first);
        final firstRow = tester.getRect(find.text('Zahnpasta'));
        expect(card.bottom, lessThan(field.top), reason: 'above the field');
        expect(card.bottom, lessThan(tabs.top), reason: 'above the tabs');
        expect(card.bottom, lessThanOrEqualTo(firstRow.top), reason: 'first');

        await tester.drag(find.text('Zahnpasta'), const Offset(0, -120));
        await tester.pumpAndSettle();
        final scrolledRow = tester.getRect(find.text('Zahnpasta'));
        final moved = firstRow.top - scrolledRow.top;
        expect(moved, greaterThan(0));
        if (tester.any(tip)) {
          expect(
            card.top - tester.getRect(tip).top,
            moreOrLessEquals(moved, epsilon: 0.5),
            reason: 'it scrolls with the list',
          );
        }
      });
    }
  }
}
