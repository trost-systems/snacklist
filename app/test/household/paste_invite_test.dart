import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

String _location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

/// The clipboard holds [text]; the list returned grows with each read.
List<String> _clipboard(WidgetTester tester, String? text) {
  final reads = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        reads.add(call.method);
        return text == null ? null : {'text': text};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return reads;
}

void main() {
  testWidgets('Step 1: a pasted link opens the join flow; joining counts '
      'as paste', (tester) async {
    final reads = _clipboard(
      tester,
      'Komm in unseren Hummlist-Haushalt: '
      'https://app.hummlist.com/join/ABCD2345 · Code: ABCD2345',
    );
    final o = await pumpOnboarding(tester, location: '/welcome');
    expect(reads, isEmpty, reason: 'only a tap reads the clipboard');
    await tapKey(tester, 'invite-paste');
    expect(reads, hasLength(1));
    expect(_location(o), '/join/ABCD2345');
    expect(find.text('Familie Trost'), findsWidgets);
    expect(o.pending.methodOf('ABCD2345'), JoinMethod.paste);
    await tapKey(tester, 'join-confirm');
    expect(o.session.joins, [('ABCD2345', JoinMethod.paste)]);
  });

  testWidgets('a code from the install referrer joins as referrer', (
    tester,
  ) async {
    final o = await pumpOnboarding(tester, location: '/welcome');
    o.pending.remember('ABCD2345', via: JoinMethod.referrer);
    o.router.go('/');
    await tester.pumpAndSettle();
    expect(_location(o), '/join/ABCD2345');
    await tapKey(tester, 'join-confirm');
    expect(o.session.joins, [('ABCD2345', JoinMethod.referrer)]);
  });

  testWidgets('a bare code with its dash works too', (tester) async {
    _clipboard(tester, ' abcd-2345 ');
    final o = await pumpOnboarding(tester, location: '/welcome');
    await tapKey(tester, 'invite-paste');
    expect(_location(o), '/join/ABCD2345');
  });

  testWidgets('nothing usable: says so and stays', (tester) async {
    _clipboard(tester, 'Milch, Brot, Eier');
    final o = await pumpOnboarding(tester, location: '/welcome');
    await tapKey(tester, 'invite-paste');
    expect(_location(o), '/welcome');
    expect(
      find.text('In der Zwischenablage ist kein Einladungslink und kein Code.'),
      findsOneWidget,
    );
    expect(o.pending.code, isNull);
  });

  testWidgets('an empty clipboard says so too', (tester) async {
    _clipboard(tester, null);
    await pumpOnboarding(tester, location: '/welcome');
    await tapKey(tester, 'invite-paste');
    expect(_key('invite-paste-nothing'), findsOneWidget);
  });

  testWidgets('signed out: the invite waits for sign-in', (tester) async {
    _clipboard(tester, 'https://app.hummlist.com/?invite=WXYZ6789');
    final o = await pumpOnboarding(
      tester,
      location: '/login',
      session: const SignedOut(),
    );
    await tapKey(tester, 'invite-paste');
    expect(_location(o), '/login?invite=WXYZ6789');
    expect(
      find.text('Einladung gemerkt. Melde dich an, dann trittst du bei.'),
      findsOneWidget,
    );
    expect(_key('invite-paste'), findsNothing);
    expect(o.pending.code, 'WXYZ6789');
  });
}
