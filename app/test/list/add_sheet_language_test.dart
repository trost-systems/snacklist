import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 470: the add sheet offers the catalog words of the language the app
/// shows, and a language switched while it is open counts from the next key.
void main() {
  testWidgets('the sheet offers the words of the app language and follows '
      'a switch at the next key', (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 1400) * 3;
    addTearDown(tester.view.reset);
    final locale = ValueNotifier(const Locale('en'));
    final repo = FakeRepository()
      ..categories = [
        for (final (i, seed) in ['produce', 'chilled', 'other'].indexed)
          Category(id: seed, name: seed, sortOrder: i, seedKey: seed),
      ];
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: locale,
        builder: (context, value, _) => MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: value,
          home: MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => Flags(forced: {onDeviceCatalogFlag})),
              BlocProvider(
                create: (_) => ListCubit(
                  repo,
                  MemoryListCache(),
                  userId: 'peter',
                  householdIndex: () => true,
                )..start(),
              ),
            ],
            child: const ShoppingList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('add-item-field'));
    await tester.tap(field);
    await tester.pumpAndSettle();

    Future<void> type(String text) async {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    }

    // A row's key is its folded name, brand and details.
    Finder row(String name) =>
        find.byKey(ValueKey('suggestion-${name.toLowerCase()}||'));

    await type('mil');
    expect(row('Milk'), findsOneWidget, reason: 'English: Milk');
    expect(row('Milch'), findsNothing, reason: 'no German term in English');

    locale.value = const Locale('de');
    await tester.pumpAndSettle();
    await type('mi');
    await type('mil');
    expect(row('Milch'), findsOneWidget, reason: 'German after the switch');
    expect(row('Milk'), findsNothing);

    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    await type('mi');
    await type('mil');
    expect(row('Milk'), findsOneWidget, reason: 'and back');
  });
}
