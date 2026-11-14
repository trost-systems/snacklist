import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';

/// Job 234: Mehr › „Einkauf starten“, only with the flag on and no trip
/// running.
void main() {
  final row = find.byKey(const ValueKey('more-start-trip'));
  final routes = [
    ...moreTabRoutes(),
    GoRoute(path: listPath, builder: (_, _) => const Text('list-page')),
  ];

  testWidgets('the flag off: no row', (tester) async {
    await pumpMore(tester, routes: routes);
    expect(row, findsNothing);
    expect(find.text('Einkauf starten'), findsNothing);
  });

  testWidgets('the row starts a trip by hand and goes to the list; then it '
      'is gone', (tester) async {
    final more = await pumpMore(
      tester,
      routes: routes,
      flags: const {tripModeFlag},
    );
    expect(row, findsOneWidget);
    expect(
      find.text(
        'Die Uhr läuft ab jetzt, die Liste, wie sie jetzt ist, gilt als '
        'geplant.',
      ),
      findsOneWidget,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('list-page'), findsOneWidget);
    final trips = tester.element(find.text('list-page')).read<TripCubit>();
    expect(trips.state, isA<Running>());
    more.router.go(morePath);
    await tester.pumpAndSettle();
    expect(row, findsNothing, reason: 'a trip runs');
  });
}
