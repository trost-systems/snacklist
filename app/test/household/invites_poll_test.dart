import 'dart:async';

import 'package:family_groceries/household/invites_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'harness.dart';

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _lifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

void main() {
  testWidgets('Einladungen polls only while on screen and in the front', (
    tester,
  ) async {
    final invites = FakeInvites();
    await pumpMore(tester, location: invitesPath, app: true, invites: invites);
    expect(find.byKey(const ValueKey('invites-page')), findsOneWidget);
    var loads = invites.loads;
    await tester.pump(InvitesCubit.livePeriod);
    expect(invites.loads, loads + 1, reason: 'polls while shown');

    await _tap(tester, 'tab-list');
    loads = invites.loads;
    await tester.pump(const Duration(seconds: 20));
    expect(invites.loads, loads, reason: 'no polls on the list tab');

    await _tap(tester, 'tab-more');
    expect(find.byKey(const ValueKey('invites-page')), findsOneWidget);
    expect(invites.loads, loads + 1, reason: 'back on screen: one reload');
    await tester.pump(InvitesCubit.livePeriod);
    expect(invites.loads, loads + 2, reason: 'polls again');

    await _lifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    ]);
    loads = invites.loads;
    await tester.pump(const Duration(seconds: 20));
    expect(invites.loads, loads, reason: 'no polls while hidden');

    await _lifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(invites.loads, loads + 1, reason: 'in front again: one reload');
    await tester.pump(InvitesCubit.livePeriod);
    expect(invites.loads, loads + 2, reason: 'polls again');
  });

  testWidgets('a load that never answers does not stop the polling', (
    tester,
  ) async {
    final invites = FakeInvites();
    await pumpMore(tester, location: invitesPath, app: true, invites: invites);
    // The next load hangs: the network took the request and never answered.
    invites.slowLoads = Completer<void>();
    await tester.pump(InvitesCubit.livePeriod);
    final hung = invites.loads;
    invites.slowLoads = null;
    await tester.pump(InvitesCubit.loadTimeout + InvitesCubit.livePeriod);
    expect(
      invites.loads,
      greaterThan(hung),
      reason: 'polls again after the timeout',
    );
  });
}
