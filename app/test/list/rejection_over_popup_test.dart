import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../more/more_harness.dart';

/// A write the server refuses while the item sheet is open on the List tab
/// (job 116): the list's own messenger is under the sheet's barrier, so the
/// message shows above the sheet.
void main() {
  setUpAll(fakeSupabase);
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);

  testWidgets('a refused tick is seen over the open item sheet', (
    tester,
  ) async {
    final more = await pumpMore(
      tester,
      location: listPath,
      routes: listTabRoutes(),
      seed: (repo) => repo
        ..remoteAdd('Milch')
        ..remoteAdd('Brot'),
    );
    await tester.longPress(row('Brot'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-sheet')), findsOneWidget);

    final milk = tester.widget<ItemRow>(row('Milch')).item;
    more.repo.reject = true;
    tester.element(row('Milch')).read<ListCubit>().tick(milk.id);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.text('Änderung abgelehnt: Milch').hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('edit-sheet')), findsOneWidget);
  });
}
